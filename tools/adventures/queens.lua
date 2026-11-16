-- Eight Queens: builds the ready-made adventure in a world, so that it can be
-- saved as adventures/queens.ovt (the compact form; see
-- tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/queens.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/queens.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 8 (players stand at y = 9). The Queen's hall: a floor of
-- eight by eight squares (three blocks each) in eight colours, coloured anew
-- for each run by mods/orthoverse_queens; a gallery round it, eight blocks
-- up, reached by two stairs, to see it whole. North of the hall, behind
-- doors that open when the floor is solved, the throne room: the Queen on
-- her throne, the crown before her (the finish). One player at a time; no
-- monsters.

local g = {}

local SX, SY, SZ = 48, 30, 64
local NG, NF = 8, 9         -- the ground (the hall's floor), and where players stand on it
local GAL = 16              -- the gallery's floor (players stand at 17)
local TOP = 23              -- the hall's ceiling
local TR_TOP = 20           -- the throne room's ceiling

-- The hall's walls, and the board inside them
local W1, W2 = 5, 42        -- west and east walls (x)
local S1, S2 = 8, 43        -- south and north walls (z)
local BX, BZ = 12, 14       -- the board's south-west corner
local BN = 24               -- its size (8 squares of 3)

local STONE = "orthoverse_chateau:stone"
local SLATE = "orthoverse_chateau:slate"
local CORNICE = "orthoverse_chateau:cornice"
local CEILING = "orthoverse_chateau:ceiling"
local PANEL = "orthoverse_chateau:panel"
local WHITE = "orthoverse_chateau:marble_white"
local BLACK = "orthoverse_chateau:marble_black"
local ROSE = "orthoverse_chateau:marble_rose"
local CARPET = "orthoverse_chateau:carpet"
local CHANDELIER = "orthoverse_chateau:chandelier"
local GLASS = "default:glass"
local RAIL = "orthoverse_queens:rail"   -- (slender, and too high to climb over)
local GRAVEL = "default:gravel"
local ROCK = "default:stone"
local DIRT = "default:dirt"
local GRASS = "default:dirt_with_grass"
local SIGN = "default:sign_wall_wood"
local STAIR = "stairs:stair_stone"

g.info = {
	name = "Eight Queens",
	line = "A queen in every row, column and colour, and none may touch. Solve the Queen's floor to reach her throne.",
	limit = 30,
	tags = {"puzzle", "solo"},   -- for the Adventures page (at most three)
	-- (the Adventures page, beside the cover picture: about 35 words, no answers)
	blurb = "The Queen's floor is eight squares by eight, in eight colours. Set eight queens on it: one in every row, column and colour, none touching. A new floor every time, and only one way to solve it.",
	rank_min = 1, rank_max = 20,
	party_max = 1,
	finish_xp = 300,
	kit = {"orthoverse_queens:queen 8", "orthoverse_queens:cross 99"},
	size = {x = SX, y = SY, z = SZ},
	ground = NG,
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = W1, y = 0, z = S1},
	corner2 = {x = W2, y = SY - 1, z = 61},
	start = {x = 23.5, y = NF, z = 10.5},
	arrival = {x = 23.5, y = NF, z = 2.5},
}
g.compact = true

g.spawners = {}
g.chests = {}
g.signs = {}
g.finish = {x = 23, y = NF + 1, z = 57}
g.gate = {x = 23, y = NF, z = 5}
g.surface = NF
g.outside = {x = 4, y = NF, z = 3}
g.rim = {}
-- For the checks: the doors open (as when the floor is solved)
g.open_for_checks = {"orthoverse_queens:door"}
-- The throne room is shut off until then
g.gated = {{label = "the throne room, its doors shut", target = {x = 23, y = NF, z = 50},
	blocked = {{{x = 22, y = NF, z = S2}, {x = 24, y = NF + 3, z = S2}}}}}

------------------------------------------------------------------------------
-- A grid of the whole template, written in one go

local grid, p2grid, metas

local function idx(x, y, z) return x + y * SX + z * SX * SY + 1 end
local function inside(x, y, z) return x >= 0 and x < SX and y >= 0 and y < SY and z >= 0 and z < SZ end

local function set(x, y, z, name, param2)
	assert(inside(x, y, z), ("outside: %d,%d,%d"):format(x, y, z))
	local i = idx(x, y, z)
	grid[i] = name
	p2grid[i] = param2 or 0
end
local function get(x, y, z) return grid[idx(x, y, z)] or "air" end
local function box(x1, y1, z1, x2, y2, z2, name, param2)
	for z = math.min(z1, z2), math.max(z1, z2) do
		for y = math.min(y1, y2), math.max(y1, y2) do
			for x = math.min(x1, x2), math.max(x1, x2) do set(x, y, z, name, param2) end
		end
	end
end
local function air(x1, y1, z1, x2, y2, z2) box(x1, y1, z1, x2, y2, z2, "air") end
local function meta(x, y, z, fields) metas[#metas + 1] = {x = x, y = y, z = z, fields = fields, construct = true} end

-- param2 for a plate on a wall: the wall is to the north, east, south or west
local WALL = {n = 0, e = 1, s = 2, w = 3}

local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}
local function sign(x, y, z, dir, text)
	set(x, y, z, SIGN, SIGN_P2[dir])
	g.signs[#g.signs + 1] = {x = x, y = y, z = z, dir = dir, text = text:match("^[^\n]*")}
	meta(x, y, z, {text = text, infotext = '"' .. text .. '"'})
end

------------------------------------------------------------------------------
-- The parts

local function ground()
	box(0, 0, 0, SX - 1, NG - 4, SZ - 1, ROCK)
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, DIRT)
	box(0, NG, 0, SX - 1, NG, SZ - 1, GRASS)
end

-- The forecourt: gravel, clipped hedges, lamps, the gate, its sign and the
-- board of who has finished
local function forecourt()
	box(W1, NG, 0, W2, NG, S1 - 1, GRAVEL)
	for x = W1, W2 do
		if math.abs(x - 23) > 3 and x % 6 ~= 5 then set(x, NF, 7, "default:bush_leaves") end
	end
	for _, x in ipairs({5, 11, 17, 29, 35, 41}) do set(x, NF, 7, "default:mese_post_light") end
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(26, NF, 5, "orthoverse_adventure:board", 0)
	box(19, NF, 6, 20, NF + 2, 6, STONE)
	sign(19, NF + 1, 5, "+z", "EIGHT QUEENS\nA queen in every row, column and colour, and none may touch.\n" ..
		"A puzzle for one. No fighting.\nAll ranks.")
end

-- The hall: its walls (stone outside, white panels in), windows high up, the
-- marble floor round the board, the board, the ceiling and the roof
local function hall()
	box(W1, NF, S1, W2, TOP, S1, STONE)
	box(W1, NF, S2, W2, TOP, S2, STONE)
	box(W1, NF, S1, W1, TOP, S2, STONE)
	box(W2, NF, S1, W2, TOP, S2, STONE)
	-- the floor: black and white marble round the board
	for x = W1 + 1, W2 - 1 do
		for z = S1 + 1, S2 - 1 do set(x, NG, z, (x + z) % 2 == 0 and WHITE or BLACK) end
	end
	-- a rose marble border round the board
	box(BX - 1, NG, BZ - 1, BX + BN, NG, BZ - 1, ROSE)
	box(BX - 1, NG, BZ + BN, BX + BN, NG, BZ + BN, ROSE)
	box(BX - 1, NG, BZ - 1, BX - 1, NG, BZ + BN, ROSE)
	box(BX + BN, NG, BZ - 1, BX + BN, NG, BZ + BN, ROSE)
	-- the board: a sample floor (each run colours its own)
	local P = orthoverse.queens and orthoverse.queens.puzzle
	local seed = 12345
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return math.floor(seed / 65536) % n + 1     -- (the high bits)
	end
	local p = P and P.make(8, rnd, 400)
	for r = 1, 8 do
		for c = 1, 8 do
			local name = "orthoverse_queens:tile_blank"
			if p then
				name = "orthoverse_queens:tile_" .. orthoverse.queens.COLOURS[p.region[r][c]] .. "_" ..
					((r + c) % 2 == 0 and "dark" or "light")
			end
			box(BX + (c - 1) * 3, NG, BZ + (r - 1) * 3, BX + c * 3 - 1, NG, BZ + r * 3 - 1, name)
		end
	end
	-- the ceiling (painted), with a skylight of glass over the board, and the
	-- roof
	box(W1, TOP, S1, W2, TOP, S2, CEILING)
	box(BX + 2, TOP, BZ + 2, BX + BN - 3, TOP, BZ + BN - 3, GLASS)
	box(W1, TOP + 1, S1, W2, TOP + 1, S2, SLATE)
	box(BX + 2, TOP + 1, BZ + 2, BX + BN - 3, TOP + 1, BZ + BN - 3, GLASS)
	-- a cornice round the walls, under the ceiling
	for x = W1 + 1, W2 - 1 do set(x, TOP - 1, S1 + 1, CORNICE); set(x, TOP - 1, S2 - 1, CORNICE) end
	for z = S1 + 1, S2 - 1 do set(W1 + 1, TOP - 1, z, CORNICE); set(W2 - 1, TOP - 1, z, CORNICE) end
	-- windows, high, between the gallery and the ceiling (whole blocks of
	-- glass, so nobody outside leans into the area)
	for x = W1 + 3, W2 - 3, 4 do
		box(x, GAL + 2, S1, x + 1, TOP - 2, S1, GLASS)
		box(x, GAL + 2, S2, x + 1, TOP - 2, S2, GLASS)
	end
	for z = S1 + 3, S2 - 3, 4 do
		box(W1, GAL + 2, z, W1, TOP - 2, z + 1, GLASS)
		box(W2, GAL + 2, z, W2, TOP - 2, z + 1, GLASS)
	end
	-- the Queen's banners on the walls, below the gallery
	for x = W1 + 4, W2 - 4, 6 do
		if math.abs(x - 23) > 2 then
			box(x, NF + 2, S1 + 1, x, NF + 4, S1 + 1, "orthoverse_queens:banner", WALL.s)
			box(x, NF + 2, S2 - 1, x, NF + 4, S2 - 1, "orthoverse_queens:banner", WALL.n)
		end
	end
	for z = S1 + 6, S2 - 6, 6 do
		box(W1 + 1, NF + 2, z, W1 + 1, NF + 4, z, "orthoverse_queens:banner", WALL.w)
		box(W2 - 1, NF + 2, z, W2 - 1, NF + 4, z, "orthoverse_queens:banner", WALL.e)
	end
	-- light under the gallery (lamps on the walls' foot)
	for x = W1 + 2, W2 - 2, 6 do
		set(x, NF, S1 + 1, "default:mese_post_light")
		set(x, NF, S2 - 1, "default:mese_post_light")
	end
	-- the notice, by the start, on the south wall
	set(21, NF + 1, S1 + 1, "orthoverse_queens:notice", WALL.s)
	set(26, NF + 1, S1 + 1, "orthoverse_queens:notice", WALL.s)
	-- the entrance: great doors in the south wall (shut: the gate is the way
	-- in)
	box(22, NF, S1, 24, NF + 3, S1, "orthoverse_chateau:panel_wood")
end

-- The gallery: a walk round the hall, eight blocks up, with a rail on its
-- inner edge, and two stairs up to it along the west and east walls
local function gallery()
	local x1, x2, z1, z2 = W1 + 1, W2 - 1, S1 + 1, S2 - 1
	local ix1, ix2, iz1, iz2 = BX - 1, BX + BN, BZ - 1, BZ + BN   -- its inner edge
	for x = x1, x2 do
		for z = z1, z2 do
			if x <= ix1 or x >= ix2 or z <= iz1 or z >= iz2 then set(x, GAL, z, PANEL) end
		end
	end
	-- the rail
	for x = ix1, ix2 do set(x, GAL + 1, iz1, RAIL); set(x, GAL + 1, iz2, RAIL) end
	for z = iz1, iz2 do set(ix1, GAL + 1, z, RAIL); set(ix2, GAL + 1, z, RAIL) end
	-- chandeliers under the gallery's edge
	for x = ix1, ix2, 6 do set(x, GAL - 1, iz1, CHANDELIER); set(x, GAL - 1, iz2, CHANDELIER) end
	for z = iz1 + 6, iz2 - 6, 6 do set(ix1, GAL - 1, z, CHANDELIER); set(ix2, GAL - 1, z, CHANDELIER) end
	-- the stairs: up from the north, along the walls, to the gallery at z 24
	for _, xs in ipairs({{W1 + 1, W1 + 2, W1 + 3}, {W2 - 2, W2 - 1, W2 - 3}}) do
		local a, b, rail = xs[1], xs[2], xs[3]
		for k = 0, GAL - NF do
			local z = 31 - k
			local y = NF + k
			if y < GAL then
				box(a, NG + 1, z, b, y - 1, z, STONE)
				set(a, y, z, STAIR, 2); set(b, y, z, STAIR, 2)
				air(a, y + 1, z, b, GAL + 3, z)       -- (headroom: the gallery is open over the stair)
			end
		end
		-- a rail along the stairwell's edge, on the gallery
		for z = 25, 32 do set(rail, GAL + 1, z, RAIL) end
		box(a, GAL, 32, b, GAL, 32, PANEL)
		box(a, GAL + 1, 32, b, GAL + 1, 32, RAIL)
	end
end

-- The throne room, north of the hall: the doors (gone when the floor is
-- solved), a red carpet up to the dais, the throne, the crown on its plinth
local function throne_room()
	local x1, x2, z1, z2 = 15, 31, S2, 61
	box(x1, NF, z1, x2, TR_TOP, z2, STONE)
	air(x1 + 1, NF, z1 + 1, x2 - 1, TR_TOP - 1, z2 - 1)
	for x = x1 + 1, x2 - 1 do
		for z = z1 + 1, z2 - 1 do set(x, NG, z, (x + z) % 2 == 0 and WHITE or ROSE) end
	end
	box(x1, TR_TOP, z1, x2, TR_TOP, z2, CEILING)
	box(x1, TR_TOP + 1, z1, x2, TR_TOP + 1, z2, SLATE)
	-- the doors, three wide, four high
	box(22, NF, S2, 24, NF + 3, S2, "orthoverse_queens:door")
	-- panels and a cornice
	for x = x1 + 1, x2 - 1 do set(x, TR_TOP - 1, z1 + 1, CORNICE); set(x, TR_TOP - 1, z2 - 1, CORNICE) end
	for z = z1 + 1, z2 - 1 do set(x1 + 1, TR_TOP - 1, z, CORNICE); set(x2 - 1, TR_TOP - 1, z, CORNICE) end
	-- the carpet
	box(22, NG, z1 + 1, 24, NG, 56, CARPET)
	-- the dais: one step up
	box(18, NG + 1, 57, 28, NG + 1, z2 - 1, "orthoverse_chateau:marble_white")
	box(21, NG + 1, 57, 25, NG + 1, z2 - 1, CARPET)
	-- the throne, facing south; the crown on its cushion before her
	set(23, NF + 1, 59, "orthoverse_queens:throne", 0)
	set(g.finish.x, g.finish.y, g.finish.z, "orthoverse_queens:crown")
	-- banners behind the throne and on the side walls
	for x = 19, 27, 2 do
		if x ~= 23 then box(x, NF + 3, z2 - 1, x, NF + 6, z2 - 1, "orthoverse_queens:banner", WALL.n) end
	end
	box(23, NF + 4, z2 - 1, 23, NF + 7, z2 - 1, "orthoverse_queens:banner", WALL.n)
	for z = 47, 57, 5 do
		box(x1 + 1, NF + 2, z, x1 + 1, NF + 5, z, "orthoverse_queens:banner", WALL.w)
		box(x2 - 1, NF + 2, z, x2 - 1, NF + 5, z, "orthoverse_queens:banner", WALL.e)
	end
	-- windows
	for _, z in ipairs({49, 54, 59}) do
		box(x1, NF + 4, z, x1, NF + 7, z + 1, GLASS)
		box(x2, NF + 4, z, x2, NF + 7, z + 1, GLASS)
	end
	-- chandeliers
	for _, c in ipairs({{19, 48}, {27, 48}, {19, 54}, {27, 54}, {23, 51}}) do set(c[1], TR_TOP - 1, c[2], CHANDELIER) end
	-- candles either side of the throne
	set(20, NF + 1, 59, "orthoverse_chateau:candles")
	set(26, NF + 1, 59, "orthoverse_chateau:candles")
end

-- Either side of the throne room, inside the adventure's box: the Queen's
-- privy gardens, walled (nobody walks in from the land, nor out)
local function gardens()
	box(W1, NF, S2, W1, NF + 3, 61, STONE)
	box(W2, NF, S2, W2, NF + 3, 61, STONE)
	box(W1, NF, 61, W2, NF + 3, 61, STONE)
	for x = W1, W2 do set(x, NF + 4, 61, CORNICE) end
	for z = S2, 61 do set(W1, NF + 4, z, CORNICE); set(W2, NF + 4, z, CORNICE) end
	for _, xs in ipairs({{W1 + 1, 14}, {32, W2 - 1}}) do
		-- clipped hedges round a lawn, a fountain in the middle
		for x = xs[1], xs[2] do
			for z = S2 + 1, 60 do
				local edge = x == xs[1] or x == xs[2] or z == S2 + 1 or z == 60
				if edge then set(x, NF, z, "default:bush_leaves") end
			end
		end
		local cx, cz = math.floor((xs[1] + xs[2]) / 2), 52
		box(cx - 1, NF, cz - 1, cx + 1, NF, cz + 1, WHITE)
		set(cx, NF, cz, "default:water_source")
		for _, d in ipairs({{-3, -5}, {3, -5}, {-3, 5}, {3, 5}}) do
			set(cx + d[1], NF, cz + d[2], "default:mese_post_light")
		end
	end
end

------------------------------------------------------------------------------
-- The plan, for plan.txt: the hall's floor from above

function g.plan()
	local out = {}
	for z = SZ - 1, 0, -1 do
		local row = {}
		for x = 0, SX - 1 do
			local n, up, gal = get(x, NG, z), get(x, NF, z), get(x, GAL, z)
			local ch = "."
			if up == "orthoverse_queens:door" then ch = "D"
			elseif up == "orthoverse_queens:throne" then ch = "T"
			elseif get(x, NF + 1, z) == "orthoverse_queens:crown" then ch = "C"
			elseif up == "orthoverse_adventure:gate" then ch = "G"
			elseif up:find("stair") then ch = "/"
			elseif up == STONE or up == GLASS then ch = "#"
			elseif n:find("^orthoverse_queens:tile") then ch = ","
			elseif gal == PANEL then ch = "="
			end
			row[#row + 1] = ch
		end
		out[#out + 1] = table.concat(row)
	end
	return table.concat(out, "\n")
end

------------------------------------------------------------------------------
-- More checks: the board is whole, the gallery and the throne reachable

function g.check_more(O, t)
	local tiles = 0
	for x = 0, SX - 1 do for z = 0, SZ - 1 do
		if get(x, NG, z):find("^orthoverse_queens:tile") then tiles = tiles + 1 end
	end end
	t.say(("board tiles: %d (want %d)"):format(tiles, BN * BN))
	local start = vector.add(O, {x = 23, y = NF, z = 10})
	local seen, key = t.reach(O, start)
	local function at(x, y, z) return seen[key(vector.add(O, {x = x, y = y, z = z}))] == true end
	local squares = 0
	for r = 0, 7 do for c = 0, 7 do
		if at(BX + c * 3 + 1, NF, BZ + r * 3 + 1) then squares = squares + 1 end
	end end
	t.say(("board squares walked to: %d of 64"):format(squares))
	t.say(("the gallery: south %s, west %s, north %s, east %s"):format(tostring(at(23, GAL + 1, 10)),
		tostring(at(8, GAL + 1, 20)), tostring(at(23, GAL + 1, 41)), tostring(at(39, GAL + 1, 20))))
	t.say("the dais before the crown: " .. tostring(at(23, NF, 56)))
	t.say("queens checks done")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.chests, g.signs = {}, {}
	ground()
	forecourt()
	hall()
	gallery()
	throne_room()
	gardens()
	-- Write the grid
	local p1 = vector.new(origin)
	local p2 = vector.add(p1, vector.new(SX - 1, SY - 1, SZ - 1))
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(p1, p2)
	local va = VoxelArea(e1, e2)
	local data, p2data = vm:get_data(), vm:get_param2_data()
	local cids, missing = {}, {}
	local c_air = core.get_content_id("air")
	for z = 0, SZ - 1 do for y = 0, SY - 1 do for x = 0, SX - 1 do
		local i = idx(x, y, z)
		local name = grid[i] or "air"
		if not cids[name] then
			if core.registered_nodes[name] then cids[name] = core.get_content_id(name)
			else missing[name] = true; cids[name] = c_air end
		end
		local vi = va:index(p1.x + x, p1.y + y, p1.z + z)
		data[vi] = cids[name]
		p2data[vi] = p2grid[i] or 0
	end end end
	vm:set_data(data)
	vm:set_param2_data(p2data)
	vm:write_to_map(true)
	for name in pairs(missing) do core.log("error", "[queens] no such node: " .. name) end
	for _, m in ipairs(metas) do
		local pos = vector.add(p1, m)
		local node = core.get_node(pos)
		local def = core.registered_nodes[node.name]
		if m.construct and def and def.on_construct then def.on_construct(pos) end
		local mt = core.get_meta(pos)
		for k, v in pairs(m.fields) do mt:set_string(k, v) end
	end
	for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {"group:orthoverse_timer"})) do
		core.get_node_timer(pos):start(1)
	end
	return missing
end

return g
