-- Orthoverse land generator (mapgen environment).
--
-- The engine's flat mapgen supplies the base: flat ground at mgflat_ground_level,
-- with caves, caverns, dungeons and ores underneath. This script then shapes the
-- surface of every land from its token ID: one hex digit per 16 x 16 tile.
--
-- This is the rough first version: correct layout, simple shapes. The visual pass
-- (natural terrain, real tree schematics, hand-built castles) replaces the shape
-- functions below without changing the layout rules.

local IPC = core.ipc_get("orthoverse:lands")
local C = dofile(core.ipc_get("orthoverse:lands_path") .. "/coords.lua")
local HG = dofile(core.ipc_get("orthoverse:lands_path") .. "/henges.lua")
local LANDS, HENGES = IPC.lands, IPC.henges

local G = tonumber(core.get_mapgen_setting("mgflat_ground_level")) or 8
local W = tonumber(core.get_mapgen_setting("water_level")) or 1

local floor, abs, sqrt, max, min, cos, pi =
	math.floor, math.abs, math.sqrt, math.max, math.min, math.cos, math.pi

------------------------------------------------------------------------------
-- Content IDs

local function id(name, fallback)
	if core.registered_nodes[name] then
		return core.get_content_id(name)
	end
	return fallback and id(fallback) or core.get_content_id("air")
end

local c = {
	air = id("air"),
	stone = id("default:stone"),
	cobble = id("default:cobble"),
	mossy = id("default:mossycobble"),
	dirt = id("default:dirt"),
	grass = id("default:dirt_with_grass"),
	conifer = id("default:dirt_with_coniferous_litter", "default:dirt_with_grass"),
	dry = id("default:dry_dirt_with_dry_grass", "default:dirt_with_dry_grass"),
	drydirt = id("default:dry_dirt", "default:dirt"),
	snow = id("default:snowblock"),
	sand = id("default:sand"),
	dsand = id("default:desert_sand"),
	ssand = id("default:silver_sand", "default:sand"),
	dstone = id("default:desert_stone"),
	sstone = id("default:sandstone"),
	gravel = id("default:gravel"),
	water = id("default:water_source"),
	rwater = id("default:river_water_source", "default:water_source"),
	tree = id("default:tree"),
	leaves = id("default:leaves"),
	apple = id("default:apple"),
	aspen = id("default:aspen_tree"),
	aspen_leaves = id("default:aspen_leaves"),
	pine = id("default:pine_tree"),
	needles = id("default:pine_needles"),
	cactus = id("default:cactus"),
	shrub = id("default:dry_shrub"),
	grass_plant = id("default:grass_3"),
	grass_tall = id("default:grass_5"),
	dgrass = id("default:dry_grass_3", "default:dry_shrub"),
	stonebrick = id("default:stonebrick"),
	stone_block = id("default:stone_block"),
	dstonebrick = id("default:desert_stonebrick"),
	dstone_block = id("default:desert_stone_block"),
	sandbrick = id("default:sandstonebrick"),
	obsidian = id("default:obsidian"),
	obsbrick = id("default:obsidianbrick"),
	steel = id("default:steelblock"),
	tin = id("default:tinblock", "default:steelblock"),
	copper = id("default:copperblock"),
	bronze = id("default:bronzeblock"),
	gold = id("default:goldblock"),
	glass = id("default:glass"),
	mese = id("default:meselamp"),
	tarmac = id("orthoverse_nodes:tarmac"),
	edge = id("orthoverse_nodes:world_edge"),
	portal = id("orthoverse_nodes:henge_portal"),
	veil = id("orthoverse_nodes:henge_veil"),
}

-- Minetest Game tree schematics (path handed over by init.lua)
local SCHEM_DIR = core.ipc_get("orthoverse:schematics")
local SCHEM = {
	apple = SCHEM_DIR .. "/apple_tree.mts",
	aspen = SCHEM_DIR .. "/aspen_tree.mts",
	pine = SCHEM_DIR .. "/pine_tree.mts",
	small_pine = SCHEM_DIR .. "/small_pine_tree.mts",
}
local ROTS = {"0", "90", "180", "270"}

local flowers = {}
for _, n in ipairs({"flowers:rose", "flowers:tulip", "flowers:dandelion_yellow",
		"flowers:geranium", "flowers:viola", "flowers:dandelion_white"}) do
	if core.registered_nodes[n] then flowers[#flowers + 1] = id(n) end
end
if #flowers == 0 then flowers[1] = c.grass_plant end

local wools = {}
for _, n in ipairs({"red", "yellow", "blue", "green", "orange", "violet",
		"magenta", "cyan", "white", "pink"}) do
	local name = "wool:" .. n
	if core.registered_nodes[name] then wools[#wools + 1] = id(name) end
end
if #wools == 0 then wools = {c.gold, c.copper, c.mese} end

------------------------------------------------------------------------------
-- Deterministic noise (no world seed: the Orthoverse looks the same everywhere)

local function hash(x, z, s)
	local v = math.sin(x * 12.9898 + z * 78.233 + s * 37.719) * 43758.5453
	return v - floor(v)
end

local function smooth(t) return t * t * (3 - 2 * t) end

local function vnoise(x, z, scale, s)
	local fx, fz = x / scale, z / scale
	local x0, z0 = floor(fx), floor(fz)
	local tx, tz = smooth(fx - x0), smooth(fz - z0)
	local a = hash(x0, z0, s)
	local b = hash(x0 + 1, z0, s)
	local cc = hash(x0, z0 + 1, s)
	local d = hash(x0 + 1, z0 + 1, s)
	return (a + (b - a) * tx) + ((cc + (d - cc) * tx) - (a + (b - a) * tx)) * tz
end

-- Raised-cosine bump: 1 at r = 0, 0 at r >= 1
local function bump(r)
	if r >= 1 then return 0 end
	return (cos(r * pi) + 1) / 2
end

------------------------------------------------------------------------------
-- Which land is where

-- Returns kind ("land", "rim", "sea", "wall"), the 36-character feature string,
-- level, and whether the land is a henge.
local land_cache = {}
local function land_info(lx, lz)
	local key = lx .. ":" .. lz
	local info = land_cache[key]
	if info then return info end
	local ring = max(abs(lx), abs(lz))
	if ring >= C.WALL then
		info = {kind = "wall"}
	elseif ring == C.RIM then
		-- Plains, with mountains along the outer edge (as in the old world)
		local t = {}
		for row = 0, 5 do
			for col = 0, 5 do
				local outer = (lz == -C.RIM and row == 0) or (lz == C.RIM and row == 5)
					or (lx == C.RIM and col == 5) or (lx == -C.RIM and col == 0)
				t[#t + 1] = outer and "1" or "3"
			end
		end
		info = {kind = "rim", feature = table.concat(t), level = 0}
	else
		local land = LANDS[key]
		local henge = HENGES[key]
		if henge then
			info = {kind = "land", feature = henge.feature, level = 0, henge = henge.name}
		elseif land then
			info = {kind = "land", feature = land.token:sub(3, 38), level = land.level}
		else
			info = {kind = "sea"}
		end
	end
	land_cache[key] = info
	return info
end

local function is_landish(lx, lz)
	local k = land_info(lx, lz).kind
	return k ~= "sea"
end

------------------------------------------------------------------------------
-- Tile shapes. Each returns the surface height offset (relative to G), the top
-- node, the filler under it, and optionally water up to some level.
-- a, b: 0..15 inside the tile; dx, dz: -1..1 from the tile centre; r: radius.

local function natural(f, a, b, dx, dz, r, x, z)
	local n = vnoise(x, z, 9, 1) - 0.5
	if f == "0" then      -- lush hill
		return floor(6 * bump(r) + n * 2 + 0.5), c.grass, c.dirt
	elseif f == "1" then  -- lush mountain
		local h = floor(20 * bump(r * 0.95) ^ 1.3 + n * 4 * bump(r) + 0.5)
		if h > 16 then return h, c.snow, c.stone end
		if h > 11 then return h, c.stone, c.stone end
		return h, c.grass, c.dirt
	elseif f == "2" or f == "a" then -- lake
		local depth = floor(6 * bump(r / 0.92) + 0.5)
		if depth > 0 then return -depth, c.sand, c.sand, 0 end
		return 0, (r < 1.05) and c.sand or c.grass, c.dirt
	elseif f == "6" or f == "e" then -- quarry (6 stone, e cobble)
		local m = max(abs(dx), abs(dz))
		local wall = (f == "6") and c.stone or c.cobble
		if m < 0.85 then
			local depth = min(6, 1 + floor((0.85 - m) * 10))
			return -depth, (f == "6") and c.gravel or c.cobble, wall
		end
		return 0, c.gravel, c.dirt
	elseif f == "7" then  -- evergreen forest
		return 0, c.conifer, c.dirt
	elseif f == "8" then  -- barren hill
		return floor(6 * bump(r) + n * 2 + 0.5), c.dry, c.drydirt
	elseif f == "9" then  -- barren mountain
		local h = floor(18 * bump(r * 0.95) ^ 1.3 + n * 4 * bump(r) + 0.5)
		return h, c.stone, c.stone
	elseif f == "b" then  -- desert dunes
		return floor(vnoise(x, z, 6, 2) * 3), c.dsand, c.dsand
	elseif f == "d" then  -- badlands mesas
		local m = vnoise(x, z, 7, 3)
		if m > 0.62 then return 5, c.dstone, c.dstone end
		return floor(m * 2), c.ssand, c.dstone
	end
	-- 3 plains, 4/c/f deciduous wood, 5 lush plains
	return 0, c.grass, c.dirt
end

------------------------------------------------------------------------------
-- The generator

local data = {}

core.register_on_generated(function(vm, minp, maxp, blockseed)
	-- Only the surface band needs work, except the world edge which is tall.
	local band_lo, band_hi = W - 12, G + 48
	local need_surface = not (maxp.y < band_lo or minp.y > band_hi)
	local need_wall = minp.y <= G + 64

	if not need_surface and not need_wall then return end

	local emin, emax = vm:get_emerged_area()
	local area = VoxelArea(emin, emax)
	vm:get_data(data)

	local ylo, yhi = max(minp.y, band_lo), min(maxp.y, band_hi)

	local function set(x, y, z, cid)
		if y >= minp.y and y <= maxp.y and x >= minp.x and x <= maxp.x
				and z >= minp.z and z <= maxp.z then
			data[area:index(x, y, z)] = cid
		end
	end
	local function fill(x, z, y0, y1, cid)
		for y = max(y0, minp.y), min(y1, maxp.y) do
			data[area:index(x, y, z)] = cid
		end
	end

	-- Per-column surface results, used by the object pass
	local tops = {}
	local trees = {}
	local sx = maxp.x - minp.x + 1
	local function ti(x, z) return (z - minp.z) * sx + (x - minp.x) + 1 end

	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local lx, lz = C.land_of(x, z)
			local info = land_info(lx, lz)

			if info.kind == "wall" then
				if need_wall then fill(x, z, minp.y, G + 64, c.edge) end

			elseif need_surface then
				local u, v = C.local_uv(x, z)
				local h, top, filler, water

				if info.kind == "sea" then
					h = (W - 5 - G) + floor(vnoise(x, z, 11, 4) * 3)
					top = (vnoise(x, z, 5, 5) > 0.6) and c.gravel or c.sand
					filler, water = c.sand, W
				else
					local tx, tz = floor(u / 16), floor(v / 16)
					local a, b = u % 16, v % 16
					local dx, dz = (a - 7.5) / 8, (b - 7.5) / 8
					local r = sqrt(dx * dx + dz * dz)
					local f = info.feature:sub(tz * 6 + tx + 1, tz * 6 + tx + 1)
					local realm = (info.level or 0) >= 8 and 1 or 0
					local castle = (info.level or 0) % 8 > 0 and not info.henge
					local in_castle = castle and (tx == 2 or tx == 3)
						and ((realm == 0 and (tz == 2 or tz == 3))
						or (realm == 1 and (tz == 4 or tz == 5)))
					local in_henge = info.henge and
						((u - 47.5) ^ 2 + (v - 47.5) ^ 2) < 20 * 20

					if in_castle or in_henge then
						h, top, filler = 0, (realm == 1) and c.tarmac or c.grass, c.dirt
					elseif realm == 1 then
						h, top, filler = 0, c.tarmac, c.stone
						if f == "2" or f == "a" then -- slime lake
							local depth = floor(5 * bump(r / 0.85) + 0.5)
							if depth > 0 then
								h, top, filler, water = -depth, c.obsidian, c.obsidian, 0
							elseif r < 1.0 then
								top = c.obsbrick
							end
						elseif f == "6" or f == "e" then -- pit
							if max(abs(dx), abs(dz)) < 0.7 then
								h, top, filler = -6, c.obsbrick, c.obsbrick
							end
						end
					else
						h, top, filler, water = natural(f, a, b, dx, dz, r, x, z)
					end

					-- Coasts: slope down to the sea within 14 nodes of a sea edge
					if info.kind ~= "wall" then
						local d = 99
						if u < 14 and not is_landish(lx - 1, lz) then d = min(d, u) end
						if u > 81 and not is_landish(lx + 1, lz) then d = min(d, 95 - u) end
						if v < 14 and not is_landish(lx, lz - 1) then d = min(d, v) end
						if v > 81 and not is_landish(lx, lz + 1) then d = min(d, 95 - v) end
						if d < 14 then
							local s = smooth(d / 14)
							local base = W - 1 - G
							h = floor(base + (h - base) * s + 0.5)
							if h + G <= W + 1 then top, filler = c.sand, c.sand end
							if water and h + G < W then water = nil end
						end
					end
				end

				-- Write the column. Clear biome dust (snow) and anything the base
				-- mapgen left above the flat ground first.
				local surf = G + h
				fill(x, z, G + 1, G + 2, c.air)
				if surf > G then
					fill(x, z, G - 2, surf - 4, c.stone)
					fill(x, z, max(G - 2, surf - 3), surf - 1, filler)
				elseif surf < G then
					fill(x, z, surf + 1, G, c.air)
					fill(x, z, surf - 2, surf - 1, filler)
				else
					fill(x, z, G - 2, G - 1, filler)
				end
				set(x, surf, z, top)
				if water then
					local wl = (info.kind == "sea") and W or (G + water)
					if wl > surf then fill(x, z, surf + 1, wl, (info.kind == "land" and
						(info.level or 0) >= 8) and c.rwater or c.water) end
				end
				tops[ti(x, z)] = surf
			end
		end
	end

	if need_surface then
		------------------------------------------------------------------
		-- Object pass: trees, plants, flipped-realm sculptures, castles, henges
		local done = {}
		for z = minp.z, maxp.z do
			for x = minp.x, maxp.x do
				local lx, lz = C.land_of(x, z)
				local key = lx .. ":" .. lz
				local info = land_info(lx, lz)
				if (info.kind == "land" or info.kind == "rim") and not done[key] then
					done[key] = true
					local Lx0, Lzn = C.land_origin(lx, lz)
					local function top_at(u, v)
						local wx, wz = Lx0 + u, Lzn - v
						if wx < minp.x or wx > maxp.x or wz < minp.z or wz > maxp.z then
							return nil
						end
						return tops[ti(wx, wz)], wx, wz
					end
					local function put(u, v, y, cid)
						set(Lx0 + u, y, Lzn - v, cid)
					end

					local realm = (info.level or 0) >= 8 and 1 or 0
					local lvl = (info.level or 0) % 8

					for tz = 0, 5 do
						for tx = 0, 5 do
							local f = info.feature:sub(tz * 6 + tx + 1, tz * 6 + tx + 1)
							local in_castle = lvl > 0 and not info.henge and (tx == 2 or tx == 3)
								and ((realm == 0 and (tz == 2 or tz == 3))
								or (realm == 1 and (tz == 4 or tz == 5)))
							local u0, v0 = tx * 16, tz * 16
							local in_henge = info.henge and
								((u0 + 8 - 47.5) ^ 2 + (v0 + 8 - 47.5) ^ 2) < 24 * 24

							if not in_castle and not in_henge then
								local s = (lx * 7919 + lz * 104729 + tx * 31 + tz * 17)

								if realm == 0 then
									-- Trees in woods: queue Minetest Game's own tree schematics,
									-- placed after the terrain is written (see below). Trees sit
									-- on a jittered grid so trunks never share a spot, and stay
									-- 4 nodes inside the land so crowns don't cross into the
									-- neighbouring mapchunk.
									if f == "4" or f == "c" or f == "f" or f == "7" then
										for gi = 0, 2 do for gj = 0, 2 do
											local i = gi * 3 + gj
											if hash(s, i, 6) < 0.8 then
												local a = 2 + gi * 5 + floor(hash(s, i, 7) * 3)
												local b = 2 + gj * 5 + floor(hash(s, i, 8) * 3)
												local u, v = u0 + a, v0 + b
												if u >= 4 and u <= 91 and v >= 4 and v <= 91 then
													local y, wx, wz = top_at(u, v)
													if y and y >= G - 1 then
														local kind
														if f == "7" then
															kind = hash(s, i, 9) < 0.4 and "small_pine" or "pine"
														elseif f == "c" then
															kind = "aspen"
														else
															kind = "apple"
														end
														trees[#trees + 1] = {x = wx, y = y + 1, z = wz,
															kind = kind, rot = ROTS[1 + floor(hash(s, i, 10) * 4)]}
													end
												end
											end
										end end
									end
									-- Plants
									for a = 1, 14 do for b = 1, 14 do
										local u, v = u0 + a, v0 + b
										local y = top_at(u, v)
										if y and y >= G - 1 then
											local hv = hash(u + lx * 96, v + lz * 96, 11)
											if (f == "3" or f == "0") and hv < 0.06 then
												put(u, v, y + 1, c.grass_plant)
											elseif f == "5" and hv < 0.12 then
												put(u, v, y + 1, hv < 0.05 and flowers[1 + floor(hv * 1000) % #flowers] or c.grass_tall)
											elseif (f == "8") and hv < 0.04 then
												put(u, v, y + 1, c.dgrass)
											elseif (f == "b" or f == "d") and hv < 0.012 then
												if f == "b" then
													for k = 1, 2 + floor(hv * 100) % 2 do put(u, v, y + k, c.cactus) end
												else
													put(u, v, y + 1, c.shrub)
												end
											end
										end
									end end
								else
									-- Flipped realm sculptures on tarmac (placeholders)
									local lush = f < "8"
									for a = 0, 15 do for b = 0, 15 do
										local u, v = u0 + a, v0 + b
										local y = top_at(u, v)
										if y then
											local ca, cb = abs(a - 7.5), abs(b - 7.5)
											local m = max(ca, cb)
											local d = sqrt(ca * ca + cb * cb)
											if f == "0" or f == "8" then -- cube
												if m <= 4 then
													local mat = lush and c.steel or c.tin
													if m > 3 then
														for k = 1, 8 do put(u, v, y + k, mat) end
													else
														put(u, v, y + 8, mat)
													end
												end
											elseif f == "1" or f == "9" then -- pyramid
												if m <= 6 then
													local mat = lush and c.sandbrick or c.dstonebrick
													for k = 1, floor(7 - m) do put(u, v, y + k, mat) end
												end
											elseif f == "3" or f == "b" then -- square
												if m <= 6 and ((a + b) % 2 == 0) then
													put(u, v, y, lush and c.stone_block or c.dstone_block)
												end
											elseif f == "4" or f == "c" then -- dome
												if d <= 6.5 then
													local outer = floor(sqrt(42.25 - d * d))
													local inner = d < 5.5 and floor(sqrt(30.25 - d * d)) or -1
													for k = max(1, inner + 1), outer do
														put(u, v, y + k, c.glass)
													end
													if d < 1 then put(u, v, y + 1, c.mese) end
												end
											elseif f == "5" or f == "d" then -- speckle
												if hash(u + lx * 96, v + lz * 96, 12) < 0.08 then
													put(u, v, y, wools[1 + floor(hash(u, v, 13) * #wools)])
												end
											elseif f == "7" or f == "f" then -- prism
												if a >= 2 and a <= 13 and cb <= 5.5 then
													local mat = lush and c.copper or c.bronze
													for k = 1, floor(6 - cb) do put(u, v, y + k, mat) end
												end
											end
										end
									end end
								end
							end
						end
					end

					-- Castle placeholder
					if lvl > 0 and not info.henge then
						local v_off = realm == 0 and 32 or 64
						local y = G
						if realm == 0 then
							local wall_h = 3 + lvl
							for a = 34, 61 do for b = 34, 61 do
								local u, v = a, v_off + 2 + (b - 34)
								local edge = a == 34 or a == 61 or b == 34 or b == 61
								local gate = (b == 61) and a >= 46 and a <= 49
								local corner = (a <= 37 or a >= 58) and (b <= 37 or b >= 58)
								local keep = a >= 44 and a <= 51 and b >= 44 and b <= 51
								local keep_edge = keep and (a == 44 or a == 51 or b == 44 or b == 51)
								if corner and (a == 34 or a == 37 or a == 58 or a == 61
										or b == 34 or b == 37 or b == 58 or b == 61) then
									local th = 6 + 2 * lvl
									for k = 1, th do put(u, v, y + k, c.stonebrick) end
									if (a + b) % 2 == 0 then put(u, v, y + th + 1, c.stonebrick) end
								elseif edge and not gate then
									for k = 1, wall_h do put(u, v, y + k, c.stonebrick) end
									if (a + b) % 2 == 0 then put(u, v, y + wall_h + 1, c.stonebrick) end
								elseif keep_edge then
									local kh = 8 + 2 * lvl
									for k = 1, kh do
										local door = b == 51 and (a == 47 or a == 48) and k <= 2
										if not door then put(u, v, y + k, c.stone_block) end
									end
									if (a + b) % 2 == 0 then put(u, v, y + kh + 1, c.stone_block) end
								elseif keep then
									put(u, v, y + 8 + 2 * lvl, c.stone_block)
								end
							end end
						else
							-- Flipped realm: a rocket on its pad
							local cu, cv = 47.5, v_off + 15.5
							local rh = 10 + 3 * lvl
							for a = 32, 63 do for b = v_off, v_off + 31 do
								local d = sqrt((a - cu) ^ 2 + (b - cv) ^ 2)
								if d <= 9 then put(a, b, y, c.stone_block) end
								if d <= 3.2 then
									for k = 1, rh do
										local window = d > 2.4 and k % 6 == 3
										put(a, b, y + k, window and c.mese or c.steel)
									end
									for k = 1, 4 do
										if d <= 3.2 - k * 0.8 then put(a, b, y + rh + k, c.copper) end
									end
								elseif d <= 4.5 and (floor(a) + floor(b)) % 3 == 0 then
									for k = 1, 4 do put(a, b, y + k, c.steel) end -- fins
								end
							end end
						end
					end

					-- Henge: a sarsen circle. 16 uprights, each two stones wide,
					-- under one continuous ring of lintels, round a portal stone.
					if info.henge then
						local y = G
						-- Uprights: 2 x 2 stones, 4 high, evenly round the circle
						for i = 0, 15 do
							local ang = 2 * pi * (i + 0.5) / 16
							local cu = floor(47.5 + 14 * cos(ang))
							local cv = floor(47.5 + 14 * math.sin(ang))
							for a = cu, cu + 1 do for b = cv, cv + 1 do
								for k = 1, 4 do put(a, b, y + k, c.stone) end
							end end
						end
						-- Lintels: one continuous ring resting on top of them
						for a = 30, 65 do for b = 30, 65 do
							local du, dv = a - 47.5, b - 47.5
							local d = sqrt(du * du + dv * dv)
							if d >= 13.2 and d < 15.3 then
								put(a, b, y + 5, c.stone_block)
							end
						end end
						for a = 46, 49 do for b = 46, 49 do put(a, b, y, c.stone_block) end end
						put(47, 47, y + 1, c.portal)
						-- Gateways: the openings at north, south, east and west
						for _, g in pairs(HG.GATES) do
							for a = g.u0, g.u1 do for b = g.v0, g.v1 do
								for k = 1, HG.GATE_HEIGHT do put(a, b, y + k, c.veil) end
							end end
						end
					end
				end
			end
		end
	end

	vm:set_data(data)

	-- Trees go on through the VoxelManip so they use the real schematics.
	-- force_placement = false: a tree never overwrites another tree's trunk or
	-- leaves, or anything else already there.
	for _, t in ipairs(trees) do
		core.place_schematic_on_vmanip(vm, {x = t.x, y = t.y, z = t.z},
			SCHEM[t.kind], t.rot, nil, false, "place_center_x, place_center_z")
	end

	vm:calc_lighting(minp, maxp)
end)
