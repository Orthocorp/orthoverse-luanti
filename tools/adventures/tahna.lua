-- The Tomb of Tahna: builds the ready-made adventure in a world, so that it
-- can be saved as adventures/tahna.ovt (the compact form; see
-- tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/tahna.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/tahna.json
--
-- Coordinates are relative to the origin: x east, z north, y up. It covers
-- the whole land (96 by 96): a desert raised three blocks above the land
-- round it, with dunes, a small pyramid (a false way in, and a trap), a
-- rock-cut doorway (another), and a sphinx: the real way in is a hidden door
-- between its paws. Under the sand, three levels:
--   level 1 (players stand at y 36) runs west to east;
--   level 2 (y 24) back east to west;
--   level 3 (y 12) west to east again, to Tahna's burial chamber.
-- Each level keeps one of her canopic jars, behind a false wall. Ranks 8 to
-- 15, up to four players.

local g = {}

local SX, SY, SZ = 96, 64, 96
local NG = 44               -- the land's ground round the desert (players outside stand at 45)
local PG = NG + 3           -- the desert's ground, three higher
local PF = PG + 1           -- where players stand on it
local L1, L2, L3 = 35, 23, 11   -- each level's floor (players stand one higher)

local STONE = "default:stone"
local SANDSTONE = "default:sandstone"
local SSBRICK = "default:sandstonebrick"
local DSSTONE = "default:desert_stone"
local DSBLOCK = "default:desert_stone_block"
local SAND = "default:desert_sand"
local COBBLE = "default:cobble"
local MOSSY = "default:mossycobble"
local BRICK = "default:stonebrick"
local GOLD = "default:goldblock"
local LAPIS = "wool:blue"
local BLACK = "wool:black"
local TORCH = "default:torch_wall"
local STAIR = "stairs:stair_stonebrick"
local LADDER = "default:ladder_wood"
local SPAWNER = "orthoverse_monsters:spawner"
local CHEST = "orthoverse_loot:chest"
local T = function(id) return "orthoverse_tahna:" .. id end

g.info = {
	name = "Tomb of Tahna",
	line = "A tomb lies far off in the desert. Enter its darkness, ye mighty, and despair.",
	limit = 90,
	tags = {"combat", "puzzle", "explore"},   -- for the Adventures page (at most three)
	-- (the Adventures page, beside the cover picture: about 35 words, no answers)
	blurb = "You meet a traveller from an antique land, who says, \"A tomb lies far off in the desert. Enter its darkness, ye mighty, and despair.\" Of course you cannot resist such a challenge.",
	rank_min = 8, rank_max = 15,
	party_max = 4,
	finish_xp = 500,
	size = {x = SX, y = SY, z = SZ},
	-- placed over the whole land, from its south-west corner
	whole_land = true,
	ground = NG,
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 1, y = 0, z = 6},
	corner2 = {x = 94, y = SY - 1, z = 94},
	start = {x = 48.5, y = PF, z = 9.5},
	arrival = {x = 48.5, y = NG + 1, z = 2.5},
}
g.compact = true

g.spawners = {}
g.chests = {}
g.signs = {}
g.finish = {x = 84, y = L3 + 2, z = 42}
g.gate = {x = 48, y = NG + 1, z = 4}
g.surface = NG + 1
g.outside = {x = 30, y = NG + 1, z = 2}
g.rim = {}
g.gated = {}

------------------------------------------------------------------------------
-- A grid of the whole template, written in one go

local grid, p2grid, metas

local function idx(x, y, z) return x + y * SX + z * SX * SY + 1 end
local function inside(x, y, z) return x >= 0 and x < SX and y >= 0 and y < SY and z >= 0 and z < SZ end

local function set(x, y, z, name, param2)
	if not inside(x, y, z) then error(("outside: %d,%d,%d (%s)"):format(x, y, z, name)) end
	local i = idx(x, y, z)
	grid[i] = name
	p2grid[i] = param2 or 0
end
local function get(x, y, z) return inside(x, y, z) and grid[idx(x, y, z)] or "air" end
local function box(x1, y1, z1, x2, y2, z2, name, param2)
	for z = math.min(z1, z2), math.max(z1, z2) do
		for y = math.min(y1, y2), math.max(y1, y2) do
			for x = math.min(x1, x2), math.max(x1, x2) do set(x, y, z, name, param2) end
		end
	end
end
local function air(x1, y1, z1, x2, y2, z2) box(x1, y1, z1, x2, y2, z2, "air") end
local function meta(x, y, z, fields) metas[#metas + 1] = {x = x, y = y, z = z, fields = fields, construct = true} end

local seed = 1
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return math.floor(seed / 65536) % n + 1
end
local function hash(x, y, z)
	local n = (x * 374761393 + y * 668265263 + z * 1274126177) % 2147483648
	n = (n * 1103515245 + 12345) % 2147483648
	return (n % 10000) / 10000
end
-- Smooth noise, 0 to 1
local function noise(x, z, scale, s)
	local fx, fz = x / scale, z / scale
	local x0, z0 = math.floor(fx), math.floor(fz)
	local tx, tz = fx - x0, fz - z0
	tx, tz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
	local function v(a, b) return hash(a, s or 0, b) end
	local a = v(x0, z0) * (1 - tx) + v(x0 + 1, z0) * tx
	local b = v(x0, z0 + 1) * (1 - tx) + v(x0 + 1, z0 + 1) * tx
	return a * (1 - tz) + b * tz
end

-- param2 for a plate on a wall: the wall is to the north, east, south or west
local WALL = {n = 0, e = 1, s = 2, w = 3}
-- wallmounted torches: on the wall to the north (+z), and so on
local TW = {n = 4, s = 5, e = 2, w = 3}
local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}

local function sign(x, y, z, dir, text)
	set(x, y, z, "default:sign_wall_wood", SIGN_P2[dir])
	g.signs[#g.signs + 1] = {x = x, y = y, z = z, dir = dir, text = text:match("^[^\n]*")}
	meta(x, y, z, {text = text, infotext = '"' .. text .. '"'})
end

-- (at: where in the room its monsters come, if not round it)
local function spawner(x, y, z, kind, count, wake, at)
	set(x, y, z, SPAWNER)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {
		kind = "orthoverse_monsters:" .. kind, count = tostring(count), wake = tostring(wake),
		at = at and ("(%d,0,%d)"):format(at.x - x, at.z - z) or "",
		per_player = "0.5",   -- half as many again for each player after the first
		infotext = "Monster spawner: " .. count .. " × " .. kind}}
	g.spawners[#g.spawners + 1] = {x = x, y = y, z = z, kind = kind, count = count, wake = wake}
end

local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot chest (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

local function tablet(x, y, z, wall, text)
	set(x, y, z, T("tablet"), WALL[wall])
	meta(x, y, z, {text = text, infotext = "Carved signs"})
end

-- A painting two blocks by two on a wall (x, z: its lower left as seen
-- from the room; it runs along the wall to the right of that)
local function fresco(name, x, y, z, wall)
	local right = ({n = {1, 0}, s = {-1, 0}, e = {0, -1}, w = {0, 1}})[wall]
	-- tiles 1, 2 the bottom row (left, right), 3, 4 the top
	for i, d in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
		local px, pz = x + right[1] * d[1], z + right[2] * d[1]
		set(px, y + d[2], pz, T("fresco_" .. name .. "_" .. i), WALL[wall])
	end
end

------------------------------------------------------------------------------
-- The ground: rock below, the land's grass round the desert, the desert on
-- its plateau

local function ground()
	box(0, 0, 0, SX - 1, NG - 5, SZ - 1, STONE)
	box(0, NG - 4, 0, SX - 1, NG - 1, SZ - 1, "default:dirt")
	box(0, NG, 0, SX - 1, NG, SZ - 1, "default:dirt_with_grass")
	-- the plateau: sandstone under sand, three above the land
	for x = 1, 94 do
		for z = 6, 94 do
			box(x, NG - 6, z, x, PG - 2, z, SANDSTONE)
			box(x, PG - 1, z, x, PG, z, SAND)
			-- the plateau's edge: sandstone, ragged
			if x <= 1 or x >= 94 or z <= 6 or z >= 94 then
				box(x, NG + 1, z, x, PG, z, (hash(x, 1, z) > 0.3) and SANDSTONE or "default:desert_sandstone")
				if hash(x, 2, z) > 0.7 then set(x, PG, z, SAND) end
			end
		end
	end
	-- deeper, stone: the tomb is cut in it
	box(1, 0, 6, 94, NG - 7, 94, STONE)
end

-- Dunes: low rolling heaps of sand, kept off the monuments
local KEEP = {}
local function keep(x1, z1, x2, z2) KEEP[#KEEP + 1] = {x1, z1, x2, z2} end
local function kept(x, z)
	for _, k in ipairs(KEEP) do
		if x >= k[1] and x <= k[3] and z >= k[2] and z <= k[4] then return true end
	end
	return false
end

local function dunes()
	for x = 3, 92 do
		for z = 8, 92 do
			if not kept(x, z) then
				local n = noise(x, z, 11, 5) * 0.7 + noise(x, z, 5, 6) * 0.3
				local hgt = math.floor((n - 0.45) * 9)
				for y = PF, PF + hgt - 1 do set(x, y, z, SAND) end
			end
		end
	end
	-- dry bushes and a few cacti, bones and broken columns
	for _ = 1, 70 do
		local x, z = 4 + rnd(88), 9 + rnd(83)
		if not kept(x, z) then
			local y = PF
			while get(x, y, z) ~= "air" and y < SY - 2 do y = y + 1 end
			local r = rnd(10)
			if r <= 6 then set(x, y, z, "default:dry_shrub")
			elseif r <= 8 then box(x, y, z, x, y + rnd(3), z, "default:cactus")
			else set(x, y, z, "orthoverse_props:bones") end
		end
	end
	for _, c in ipairs({{40, 30}, {44, 30}, {56, 40}, {60, 42}, {34, 60}, {38, 64}}) do
		local x, z = c[1], c[2]
		local y = PF
		while get(x, y, z) ~= "air" and y < SY - 4 do y = y + 1 end
		local hgt = 1 + rnd(4)
		box(x, y, z, x, y + hgt, z, SSBRICK)
		if rnd(2) == 1 then set(x + 1, y, z, SSBRICK) end
	end
end

-- The gate strip, on the land's own ground south of the desert
local function forecourt()
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(51, NG + 1, 4, "orthoverse_adventure:board", 0)
	box(43, NG + 1, 5, 45, NG + 2, 5, SANDSTONE)
	sign(44, NG + 2, 4, "+z", "TOMB OF TAHNA\nEnter its darkness, ye mighty, and despair.\n" ..
		"Ranks 8 to 15. Up to four together.")
	for _, x in ipairs({40, 56}) do set(x, NG + 1, 3, "default:mese_post_light") end
	-- steps up onto the desert, for the way back (inside the box, nobody needs them)
end

------------------------------------------------------------------------------
-- The sphinx: lying, its face to the south, the hidden door between its
-- paws (a false wall that looks like the sandstone round it)

local SPH = {x1 = 12, x2 = 24, z1 = 30, z2 = 52}
local DOOR = {x1 = 17, x2 = 19, z = 30}

local function sphinx()
	keep(SPH.x1 - 3, 18, SPH.x2 + 3, SPH.z2 + 3)
	box(SPH.x1 - 2, PF - 1, 19, SPH.x2 + 2, PF - 1, SPH.z2 + 2, SAND)
	-- the body: long, rounded on top, higher at the haunches
	for z = 34, SPH.z2 do
		local hgt = (z >= 46) and 6 or 5
		for x = SPH.x1, SPH.x2 do
			local edge = (x == SPH.x1 or x == SPH.x2) and 1 or 0
			box(x, PF, z, x, PF + hgt - edge, z, SANDSTONE)
		end
	end
	-- the tail curled round the haunch
	box(SPH.x2 + 1, PF, 44, SPH.x2 + 1, PF, 52, SANDSTONE)
	-- the chest, upright, under the head
	box(SPH.x1, PF, SPH.z1, SPH.x2, PF + 7, 33, SANDSTONE)
	-- the paws, out in front
	for _, xs in ipairs({{13, 15}, {21, 23}}) do
		box(xs[1], PF, 22, xs[2], PF + 1, SPH.z1 - 1, SANDSTONE)
		for x = xs[1], xs[2] do set(x, PF + 1, 22, "default:desert_sandstone") end   -- the toes
	end
	-- the head: a face in sandstone, the striped headdress, the beard
	local hx1, hx2, hz1, hz2 = 15, 21, 28, 33
	box(hx1, PF + 8, hz1, hx2, PF + 12, hz2, SANDSTONE)
	-- the headdress: stripes of blue and gold over the top and down the sides
	for z = hz1, hz2 + 2 do
		for x = hx1 - 1, hx2 + 1 do
			local side = x == hx1 - 1 or x == hx2 + 1
			local top = PF + 13
			local c = ((z + x) % 2 == 0) and LAPIS or GOLD
			if side then box(x, PF + 6, z, x, PF + 12, z, ((z + PF) % 2 == 0) and LAPIS or GOLD)
			else set(x, top, z, c) end
		end
	end
	for x = hx1 - 1, hx2 + 1 do set(x, PF + 13, hz1 - 1, GOLD) end   -- its brow band
	-- the face: eyes, nose, mouth (on the south face, z = hz1 - 1)
	local fz = hz1 - 1
	box(hx1, PF + 8, fz, hx2, PF + 12, fz, SANDSTONE)
	set(16, PF + 11, fz, BLACK); set(20, PF + 11, fz, BLACK)
	set(18, PF + 10, fz - 1, SANDSTONE)            -- the nose
	box(17, PF + 9, fz, 19, PF + 9, fz, "default:desert_sandstone")   -- the mouth's line
	box(17, PF + 7, fz, 19, PF + 7, fz + 1, SANDSTONE)                -- the chin
	box(18, PF + 5, fz + 1, 18, PF + 6, fz + 1, GOLD)                 -- the beard
	-- the hidden door: three wide, three high, in the chest between the paws
	box(DOOR.x1, PF, DOOR.z, DOOR.x2, PF + 2, DOOR.z, T("false_desert"))
end

------------------------------------------------------------------------------
-- The pyramid: a false way in. A passage to a burial chamber with an empty
-- sarcophagus: opened, it seals the doorway with a slab and wakes two
-- mummies. On the chamber's wall, the painting of the sphinx's door; behind
-- the sarcophagus, the lever that lifts the slab.

local PYR = {x1 = 62, x2 = 82, z1 = 70, z2 = 90}

local function pyramid()
	keep(PYR.x1 - 2, PYR.z1 - 4, PYR.x2 + 2, PYR.z2 + 2)
	box(PYR.x1 - 1, PF - 1, PYR.z1 - 3, PYR.x2 + 1, PF - 1, PYR.z2 + 1, SAND)
	local n = 0
	while PYR.x1 + n <= PYR.x2 - n do
		local c = (n == math.floor((PYR.x2 - PYR.x1) / 2)) and GOLD or SANDSTONE
		box(PYR.x1 + n, PF + n, PYR.z1 + n, PYR.x2 - n, PF + n, PYR.z2 - n, c)
		n = n + 1
	end
	-- the chamber inside, and the passage to it from the south face
	local cx = 72
	air(67, PF, 76, 77, PF + 4, 84)
	box(67, PF - 1, 76, 77, PF - 1, 84, T("sandstone_block"))
	for x = 67, 77 do for z = 76, 84 do
		if x == 67 or x == 77 or z == 76 or z == 84 then
			-- (the walls, lined)
		end
	end end
	box(66, PF, 75, 66, PF + 4, 85, T("glyphs")); box(78, PF, 75, 78, PF + 4, 85, T("glyphs"))
	box(66, PF, 85, 78, PF + 4, 85, T("glyphs")); box(66, PF, 75, 78, PF + 4, 75, T("glyphs"))
	box(66, PF + 5, 75, 78, PF + 5, 85, T("sandstone_block"))
	air(cx - 1, PF, PYR.z1, cx + 1, PF + 2, 75)
	box(cx - 1, PF - 1, PYR.z1, cx + 1, PF - 1, 75, T("sandstone_block"))
	-- the slab's place: inside the doorway, where the pyramid is over the
	-- passage (nearer the face its steps leave the passage open to the sky)
	box(cx - 1, PF, PYR.z1 + 4, cx + 1, PF + 2, PYR.z1 + 4, T("slab_open"))
	-- the empty sarcophagus, the painting, the lever, torches
	set(cx, PF, 80, T("decoy"), 0)
	fresco("sphinx", 71, PF + 2, 84, "n")
	set(cx, PF + 1, 84, T("lever"), WALL.n)
	for _, p in ipairs({{68, 77}, {76, 77}, {68, 83}, {76, 83}}) do set(p[1], PF + 3, p[2] < 80 and 76 or 84,
		TORCH, p[2] < 80 and TW.s or TW.n) end
	chest(76, PF, 83, "common", 2)
end

------------------------------------------------------------------------------
-- The rock-cut tomb: another false way in. A doorway in an outcrop, a stair
-- down to a bare chamber; in its middle the floor drops into a spiked pit.

local function rock_tomb()
	keep(6, 66, 32, 92)
	-- the outcrop: desert stone, ragged
	for x = 7, 31 do
		for z = 68, 91 do
			local d = math.max(math.abs(x - 19) / 12, math.abs(z - 80) / 12)
			local hgt = math.floor((1 - d) * 9 + noise(x, z, 4, 9) * 3)
			if hgt > 0 then box(x, PF, z, x, PF + hgt, z, DSSTONE) end
		end
	end
	-- the doorway (facing south), its lintel carved
	air(18, PF, 68, 20, PF + 2, 73)
	box(17, PF + 3, 68, 21, PF + 3, 68, DSBLOCK)
	set(19, PF + 3, 68, T("arch_eye"), 0)
	-- the stair down to the north, six steps
	for k = 1, 6 do
		local z = 73 + k
		box(18, PG - k, z, 20, PG - k, z, DSBLOCK)
		air(18, PG - k + 1, z, 20, PG - k + 4, z)
		set(18, PG - k + 1, z, STAIR, 0); set(19, PG - k + 1, z, STAIR, 0); set(20, PG - k + 1, z, STAIR, 0)
	end
	-- the chamber: bare, a tablet on the far wall
	local fy = PG - 6
	air(15, fy + 1, 80, 23, fy + 4, 88)
	box(14, fy, 79, 24, fy, 89, DSBLOCK)
	box(14, fy + 5, 79, 24, fy + 5, 89, DSBLOCK)
	for x = 14, 24 do for z = 79, 89 do
		if x == 14 or x == 24 or z == 89 then box(x, fy + 1, z, x, fy + 4, z, DSBLOCK) end
	end end
	tablet(19, fy + 2, 88, "n", "Here lies no one. The queen is not here, thief, and she sees you.")
	set(16, fy + 3, 80, TORCH, TW.s); set(22, fy + 3, 80, TORCH, TW.s)
	-- the pit: under the chamber's middle, four deep, spikes, a ladder out
	box(17, fy - 4, 82, 21, fy - 1, 86, "air")
	box(16, fy - 5, 81, 22, fy - 5, 87, DSBLOCK)
	for x = 16, 22 do for z = 81, 87 do
		if x == 16 or x == 22 or z == 81 or z == 87 then box(x, fy - 4, z, x, fy - 1, z, DSBLOCK) end
	end end
	box(17, fy - 4, 82, 21, fy - 4, 86, T("spikes"))
	-- the way out: a column in a corner, its top just under the floor, a
	-- ladder up its side (from it, a jump up to the floor)
	box(17, fy - 4, 86, 17, fy - 1, 86, DSBLOCK)
	for y = fy - 4, fy - 1 do set(18, y, 86, LADDER, 3) end
	box(17, fy, 82, 21, fy, 86, T("false_floor"))
	set(19, fy, 84, T("plate_pit"))
end

------------------------------------------------------------------------------
-- The tomb: rooms and passages cut in the rock, walled with cobble (moss
-- here and there), floored with stone brick

-- What a room's or a passage's shell may replace: the rock it is cut in,
-- never another room's wall (so a passage along a room keeps the room's
-- carved wall on its side, and a doorway keeps the room's floor)
local ROCK = {[STONE] = true, [SANDSTONE] = true, [SAND] = true, ["default:desert_sandstone"] = true,
	["default:dirt"] = true, [DSSTONE] = true}

-- A room: x1..x2, z1..z2 inside, floor at fy, h blocks high inside; walls,
-- floor and ceiling round it. wall: a fixed wall block (or a mix of cobble
-- and moss)
local function room(x1, z1, x2, z2, fy, h, wall, floor)
	for x = x1 - 1, x2 + 1 do
		for z = z1 - 1, z2 + 1 do
			for y = fy, fy + h + 1 do
				local edge = x < x1 or x > x2 or z < z1 or z > z2 or y == fy or y == fy + h + 1
				if edge then
					if ROCK[get(x, y, z)] then
						if y == fy then set(x, y, z, floor or BRICK)
						else set(x, y, z, wall or ((hash(x, y, z) > 0.75) and MOSSY or COBBLE)) end
					end
				else
					set(x, y, z, "air")
				end
			end
		end
	end
end

-- A passage (a room three wide, or as given)
local function passage(x1, z1, x2, z2, fy, h, wall) room(x1, z1, x2, z2, fy, h or 3, wall) end

-- A passage three wide along a line of points (x, z: its middle), each leg
-- straight along x or z. Where it meets a room it cuts through the wall.
local function corridor(pts, fy, wall)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local x1, x2 = math.min(a[1], b[1]), math.max(a[1], b[1])
		local z1, z2 = math.min(a[2], b[2]), math.max(a[2], b[2])
		passage(x1 - 1, z1 - 1, x2 + 1, z2 + 1, fy, 3, wall)
	end
end

-- A doorway through a wall: the wall's blocks between, made air
local function opening(x1, z1, x2, z2, fy, h)
	air(x1, fy + 1, z1, x2, fy + (h or 3), z2)
	box(x1, fy, z1, x2, fy, z2, BRICK)
end

-- Stairs: from (x1..x2) at z0, `n` steps, each one down and one along dz
local function stairs_down(x1, x2, z0, fy, n, dz)
	local p2 = dz > 0 and 2 or 0     -- a stair node faces its high side (param2 0: high to +z)
	for k = 1, n do
		local z = z0 + k * dz
		local y = fy - k             -- the step's top
		for x = x1 - 1, x2 + 1 do
			if x < x1 or x > x2 then
				for yy = y - 1, y + 4 do
					if get(x, yy, z) ~= "air" then set(x, yy, z, (hash(x, yy, z) > 0.7) and MOSSY or COBBLE) end
				end
			end
		end
		box(x1, y - 1, z, x2, y - 1, z, BRICK)
		box(x1, y, z, x2, y, z, STAIR, p2)
		air(x1, y + 1, z, x2, y + 4, z)
		box(x1, y + 5, z, x2, y + 5, z, COBBLE)
	end
end

local function torch(x, y, z, wall) set(x, y, z, TORCH, TW[wall]) end

-- The way into a room with monsters in it: the passage turns, runs along the
-- room's wall, and turns in. The room's spawners stand by the wall just
-- inside, opposite the first turn: whoever comes along the passage wakes
-- them (through the wall), and the monsters are in the room before them.
-- (Each spawner: x, z, kind, count, and where in the room they come: ax, az)
local function guards(fy, list)
	for _, s in ipairs(list) do spawner(s[1], fy, s[2], s[3], s[4], 5, {x = s[5], z = s[6]}) end
end

------------------------------------------------------------------------------
-- Level 1 (floor 35): west to east

local function level1()
	local f = L1
	-- from the sphinx's door: down twelve steps to the north
	air(DOOR.x1, PF, DOOR.z + 1, DOOR.x2, PF + 3, DOOR.z + 1)
	stairs_down(DOOR.x1, DOOR.x2, DOOR.z, PG, 12, 1)
	-- A: the entry hall (the queen's painting and her tablet)
	room(14, 47, 30, 57, f, 5)
	corridor({{18, 43}, {18, 44}, {27, 44}, {27, 47}}, f)
	fresco("jars", 21, f + 2, 57, "n")
	tablet(17, f + 2, 57, "n", "Here sleeps Tahna, who was queen. Her heart, her breath and her name were " ..
		"sealed in three jars and given to the deep places of her house. While the jars endure, she endures.")
	set(27, f + 1, 49, T("return"))
	torch(14, f + 3, 49, "w"); torch(30, f + 3, 49, "e"); torch(14, f + 3, 55, "w"); torch(30, f + 3, 55, "e")
	guards(f, {{18, 47, "skeleton_warrior", 3, 22, 52}})
	chest(15, f + 1, 56, "common", 1)
	-- the darts passage east, turning south along B's wall
	corridor({{30, 53}, {41, 53}, {41, 48}, {44, 48}}, f)
	set(36, f, 53, T("plate_darts"))
	for x = 34, 38, 2 do
		set(x, f + 1, 51, T("dart_hole"), 2); set(x, f + 2, 51, T("dart_hole"), 2)     -- (face north: param2 2)
		set(x, f + 1, 55, T("dart_hole"), 0); set(x, f + 2, 55, T("dart_hole"), 0)     -- (face south)
	end
	fresco("ceiling", 39, f + 1, 54, "n")
	-- B: the falling ceiling's room (bones on its floor, and the dead up and about)
	room(44, 42, 54, 54, f, 6)
	box(44, f + 6, 42, 54, f + 6, 54, T("crusher"))
	for x = 45, 53 do set(x, f, 48, T("plate_crush")) end
	for _, p in ipairs({{46, 44}, {51, 51}, {49, 46}}) do set(p[1], f + 1, p[2], "orthoverse_props:bones") end
	torch(44, f + 3, 44, "w"); torch(54, f + 3, 52, "e")
	guards(f, {{44, 53, "skeleton_warrior", 2, 49, 51}})
	-- on to D, turning north along its wall
	corridor({{55, 48}, {60, 48}, {60, 53}, {63, 53}}, f)
	-- D: the hall of the archway (its east way is the archway: back to A)
	room(63, 42, 73, 54, f, 5, COBBLE)     -- (plain cobble: its false wall must not stand out)
	corridor({{74, 48}, {81, 48}}, f)
	box(74, f + 1, 47, 74, f + 3, 49, T("arch"))
	box(74, f + 4, 47, 74, f + 4, 49, T("arch_eye"), 3)
	torch(63, f + 3, 44, "w"); torch(73, f + 3, 52, "e")
	guards(f, {{63, 48, "mummy", 1, 68, 46}, {63, 47, "statue", 2, 69, 51}})
	-- south: the queen's treasury, gold heaped in it, a chest, and on its
	-- far wall four buttons. Pressed together (as many as there are players)
	-- they drop the slab over its doorway, and it fills with water
	corridor({{68, 41}, {68, 33}}, f)
	room(62, 24, 74, 32, f, 5, T("glyphs"))
	box(62, f, 24, 74, f, 32, T("flood_floor"))
	box(67, f + 1, 33, 69, f + 3, 33, T("slab_open"))
	for _, p in ipairs({{62, 30}, {63, 31}, {62, 31}, {74, 30}, {73, 31}, {74, 31}, {62, 27}, {74, 27}}) do
		set(p[1], f + 1, p[2], GOLD)
	end
	set(62, f + 2, 31, GOLD); set(74, f + 2, 31, GOLD)
	for _, x in ipairs({63, 66, 70, 73}) do set(x, f + 2, 24, T("button"), WALL.s) end
	chest(68, f + 1, 26, "armour", 0)
	torch(62, f + 3, 25, "w"); torch(74, f + 3, 25, "e")
	-- the false wall north, to the first jar, turning west along E's wall
	corridor({{68, 55}, {68, 59}, {61, 59}, {61, 62}}, f)
	box(67, f + 1, 55, 69, f + 3, 55, T("false_cobble"))
	-- E: the jackal's jar, on its pedestal
	room(55, 62, 67, 72, f, 5)
	set(61, f + 1, 69, T("pedestal"))
	set(61, f + 2, 69, T("jar_jackal"))
	guards(f, {{67, 62, "scarab", 6, 62, 66}, {66, 62, "mummy", 1, 58, 67}})
	chest(56, f + 1, 71, "weapon", 1)
	torch(55, f + 3, 67, "w"); torch(67, f + 3, 67, "e")
	-- east, to the stair room
	corridor({{68, 69}, {77, 69}, {77, 64}, {80, 64}}, f)
	room(80, 58, 88, 70, f, 5)
	torch(88, f + 3, 62, "e")
	-- down to level 2: twelve steps south from its south wall
	opening(83, 57, 85, 57, f)
	stairs_down(83, 85, 57, f, 12, -1)
end

------------------------------------------------------------------------------
-- Level 2 (floor 23): east to west

-- The spiral: a passage one wide, two high, winding in to its middle, and
-- nothing there
local function spiral(f)
	local ox, oz = 17, 24
	box(ox, f, oz, ox + 18, f, oz + 18, BRICK)
	box(ox, f + 1, oz, ox + 18, f + 3, oz + 18, COBBLE)
	local pts = {{17, 17}, {1, 17}, {1, 1}, {17, 1}, {17, 15}, {3, 15}, {3, 3}, {15, 3}, {15, 13}, {5, 13}, {5, 5},
		{13, 5}, {13, 11}, {7, 11}, {7, 7}, {11, 7}, {11, 9}, {9, 9}}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		air(ox + a[1], f + 1, oz + a[2], ox + b[1], f + 2, oz + b[2])
	end
	-- the way in, from the false door's room
	air(ox + 18, f + 1, oz + 17, 37, f + 2, oz + 17)
	set(36, f, oz + 17, BRICK)
end

local function level2()
	local f = L2
	-- A: the guard room (the stair comes down north of it; the way turns east
	-- along its north wall)
	room(78, 28, 91, 39, f, 5)
	corridor({{84, 44}, {84, 42}, {89, 42}, {89, 39}}, f)
	guards(f, {{84, 39, "guardian", 1, 84, 33}, {83, 39, "skeleton_warrior", 2, 81, 35}})
	chest(90, f + 1, 29, "armour", 3)
	torch(78, f + 3, 32, "w"); torch(91, f + 3, 36, "e")
	tablet(80, f + 2, 28, "s", "Ra's light lies on the floor of fire. Tread only where it shines.")
	-- B: the hall of fire: gold tiles make the one safe way across; every
	-- other tile is a plate. Jets in the north and south walls
	corridor({{77, 31}, {75, 31}, {75, 36}, {72, 36}}, f)
	room(56, 30, 72, 38, f, 5)
	fresco("gold", 70, f + 2, 38, "n")
	for x = 56, 72 do for z = 30, 38 do set(x, f, z, T("plate_flame")) end end
	-- the gold way: winding from the east door to the west door
	local way = {{72, 36}, {71, 36}, {70, 36}, {70, 35}, {70, 34}, {70, 33}, {69, 33}, {68, 33}, {67, 33}, {67, 34},
		{67, 35}, {67, 36}, {67, 37}, {66, 37}, {65, 37}, {64, 37}, {63, 37}, {63, 36}, {63, 35}, {63, 34}, {62, 34},
		{61, 34}, {60, 34}, {60, 35}, {60, 36}, {60, 37}, {59, 37}, {58, 37}, {57, 37}, {56, 37}}
	for _, w in ipairs(way) do set(w[1], f, w[2], T("gold_tile")) end
	for x = 57, 71, 2 do
		set(x, f + 1, 29, T("nozzle"), 2)       -- in the south wall, facing north
		set(x, f + 1, 39, T("nozzle"), 0)       -- in the north wall, facing south
	end
	for _, p in ipairs({{66, 31}, {61, 38}}) do set(p[1], f + 1, p[2], "orthoverse_props:bones") end
	torch(56, f + 4, 31, "w"); torch(72, f + 4, 33, "e")
	-- C: the false door's room
	corridor({{55, 37}, {53, 37}, {53, 31}, {50, 31}}, f)
	room(38, 30, 50, 42, f, 5)
	box(43, f + 1, 43, 45, f + 3, 43, T("false_door"), 0)
	for x = 42, 46 do for z = 40, 42 do set(x, f, z, T("spear_floor")) end end
	set(44, f + 1, 41, "orthoverse_props:bones")
	fresco("spears", 38, f + 2, 42, "n")
	torch(38, f + 3, 32, "w"); torch(50, f + 3, 40, "e")
	guards(f, {{50, 37, "statue", 2, 44, 37}})
	-- off its west wall, the spiral
	spiral(f)
	-- the true way: a false wall in the south wall, then west along D's wall
	box(38, f + 1, 29, 50, f + 5, 29, COBBLE)
	corridor({{44, 29}, {44, 25}, {38, 25}, {38, 22}}, f)
	box(43, f + 1, 29, 45, f + 3, 29, T("false_cobble"))
	-- D: the falcon's jar
	room(32, 12, 48, 22, f, 5)
	set(40, f + 1, 14, T("pedestal"))
	set(40, f + 2, 14, T("jar_falcon"))
	guards(f, {{44, 22, "mummy", 2, 36, 17}, {45, 22, "scarab", 5, 44, 16}})
	chest(47, f + 1, 13, "common", 3)
	torch(32, f + 3, 16, "w"); torch(48, f + 3, 16, "e")
	-- west: the pit passage, turning north along E's wall
	corridor({{31, 15}, {21, 15}, {21, 20}, {18, 20}}, f)
	-- the pit under its middle
	air(25, f - 4, 14, 29, f - 1, 16)
	box(24, f - 5, 13, 30, f - 5, 17, COBBLE)
	for x = 24, 30 do for z = 13, 17 do
		if x == 24 or x == 30 or z == 13 or z == 17 then box(x, f - 4, z, x, f - 1, z, COBBLE) end
	end end
	box(25, f - 4, 14, 29, f - 4, 16, T("spikes"))
	-- the way out: a column in a corner, its top just under the floor, a
	-- ladder up its side (from it, a jump up to the floor)
	box(25, f - 4, 14, 25, f - 1, 14, COBBLE)
	for y = f - 4, f - 1 do set(26, y, 14, LADDER, 3) end
	box(25, f, 14, 29, f, 16, T("false_floor"))
	set(27, f, 15, T("plate_pit"))
	-- E: the stair room, and the golem that keeps it (too big for the passages)
	room(6, 10, 18, 22, f, 5)
	guards(f, {{18, 15, "golem", 1, 11, 16}})
	torch(6, f + 3, 14, "w"); torch(18, f + 3, 13, "e")
	-- down to level 3: twelve steps north from its north wall
	opening(11, 23, 13, 23, f)
	stairs_down(11, 13, 23, f, 12, 1)
end

------------------------------------------------------------------------------
-- Level 3 (floor 11): west to east, to the burial chamber

-- The endless passage: north from the hall of guardians to a crossway, and
-- east and west from it in plain stone brick. Near each end the floor sends
-- whoever treads on it back along the passage, so it never ends.
-- (it runs the whole width of the land, all but a wall at each end; the
-- floor that sends players back starts five blocks in from each end)
local LOOP = {z = 70, west = {1, 6}, east = {89, 94}}

local function endless(f)
	corridor({{21, 52}, {21, LOOP.z}}, f, BRICK)
	corridor({{2, LOOP.z}, {93, LOOP.z}}, f, BRICK)
	for _, side in ipairs({"west", "east"}) do
		local l = LOOP[side]
		box(l[1], f, LOOP.z - 1, l[2], f, LOOP.z + 1, T("loop_" .. side))
	end
end

local function level3()
	local f = L3
	-- A: the hall of guardians (the stair comes down south-west of it; the
	-- way turns east along its south wall)
	room(14, 40, 28, 52, f, 5)
	corridor({{12, 36}, {12, 37}, {22, 37}, {22, 40}}, f)
	guards(f, {{14, 40, "guardian", 2, 21, 46}})
	torch(14, f + 3, 49, "w"); torch(28, f + 3, 49, "e"); torch(14, f + 3, 44, "w")
	tablet(17, f + 2, 52, "n", "Whoever wakes the queen, the sand will have him. She was dust once, " ..
		"and she remembers how.")
	-- north: the endless passage
	endless(f)
	-- B: the darts passage east, a false wall north to the third jar, turning
	-- south along C's wall
	corridor({{29, 45}, {41, 45}, {41, 40}, {44, 40}}, f)
	box(28, f + 1, 47, 39, f + 3, 47, COBBLE)
	set(36, f, 45, T("plate_darts"))
	for x = 35, 37 do
		set(x, f + 1, 43, T("dart_hole"), 2); set(x, f + 2, 43, T("dart_hole"), 2)
		set(x, f + 1, 47, T("dart_hole"), 0); set(x, f + 2, 47, T("dart_hole"), 0)
	end
	corridor({{32, 47}, {32, 51}, {38, 51}, {38, 53}}, f)
	box(31, f + 1, 47, 33, f + 3, 47, T("false_cobble"))
	-- the woman's jar
	room(30, 54, 42, 64, f, 5)
	set(36, f + 1, 62, T("pedestal"))
	set(36, f + 2, 62, T("jar_woman"))
	guards(f, {{32, 54, "mummy", 2, 35, 59}, {33, 54, "scarab", 4, 39, 60}})
	chest(41, f + 1, 63, "common", 1)
	torch(30, f + 3, 59, "w"); torch(42, f + 3, 59, "e")
	-- C: the antechamber, its statues and the tomb's soldiers
	room(44, 38, 54, 50, f, 6, T("glyphs"), T("sandstone_block"))
	guards(f, {{44, 45, "statue", 2, 49, 46}, {44, 44, "skeleton_warrior", 2, 50, 41}})
	torch(44, f + 4, 48, "w"); torch(54, f + 4, 40, "e")
	-- out of its east wall, south along the burial chamber's wall, and in
	-- through the great doorway (gold)
	corridor({{55, 48}, {57, 48}, {57, 42}, {60, 42}}, f)
	-- D: the burial chamber: walls of carved signs, pillars, braziers, the
	-- sarcophagus on its dais at the east end, the queen's resting place
	room(60, 28, 88, 56, f, 8, T("glyphs"), T("sandstone_block"))
	opening(59, 41, 59, 43, f, 4)
	box(59, f + 1, 40, 59, f + 5, 40, GOLD); box(59, f + 1, 44, 59, f + 5, 44, GOLD)
	box(59, f + 5, 40, 59, f + 5, 44, GOLD)
	-- a gold border on the floor, the way to the dais in gold
	for x = 60, 88 do for z = 28, 56 do
		if x == 60 or x == 88 or z == 28 or z == 56 then set(x, f, z, T("gold_tile")) end
	end end
	for x = 61, 78 do set(x, f, 42, T("gold_tile")) end
	-- pillars: glyph-carved, gold-capped
	for _, px in ipairs({64, 71}) do
		for _, pz in ipairs({33, 51}) do
			box(px, f + 1, pz, px + 1, f + 8, pz + 1, T("glyphs"))
			box(px, f + 8, pz, px + 1, f + 8, pz + 1, GOLD)
		end
	end
	-- braziers between the pillars
	for _, p in ipairs({{68, 34}, {75, 34}, {68, 50}, {75, 50}}) do
		set(p[1], f + 1, p[2], GOLD); set(p[1], f + 2, p[2], "fire:permanent_flame")
	end
	-- the dais
	box(79, f + 1, 36, 87, f + 1, 48, T("sandstone_block"))
	box(79, f + 1, 41, 79, f + 1, 43, "stairs:stair_sandstone_block", 3)
	set(g.finish.x, g.finish.y, g.finish.z, T("sarcophagus"), 1)
	-- the jars' empty niches behind the sarcophagus, and the queen's painting
	fresco("jars", 88, f + 3, 41, "e")
	for _, z in ipairs({38, 46}) do set(87, f + 2, z, T("pedestal")) end
	chest(86, f + 2, 40, "finish", 3)
	torch(60, f + 5, 31, "w"); torch(60, f + 5, 53, "w"); torch(88, f + 5, 31, "e"); torch(88, f + 5, 53, "e")
	-- Tahna, already up when they come in: her spawner by the corner, woken
	-- from the passage
	guards(f, {{60, 48, "tahna", 1, 72, 42}})
end

------------------------------------------------------------------------------
-- The plan, for plan.txt: each level from above

function g.plan()
	local out = {}
	for _, lv in ipairs({{"surface", PF}, {"level 1", L1 + 1}, {"level 2", L2 + 1}, {"level 3", L3 + 1}}) do
		out[#out + 1] = "== " .. lv[1]
		for z = SZ - 1, 0, -1 do
			local row = {}
			for x = 0, SX - 1 do
				local n, fl = get(x, lv[2], z), get(x, lv[2] - 1, z)
				local ch = "."
				if n == "air" then ch = " "
				elseif n:find("jar_") then ch = "J"
				elseif n:find("false_") then ch = "F"
				elseif n:find("sarcophagus") or n:find("decoy") then ch = "S"
				elseif n:find("stair") then ch = "/"
				elseif n == SPAWNER then ch = "M"
				elseif n:find("arch") then ch = "A"
				elseif n == "orthoverse_adventure:gate" then ch = "G"
				else ch = "#" end
				if n == "air" and fl:find("plate") then ch = "^" end
				row[#row + 1] = ch
			end
			out[#out + 1] = table.concat(row)
		end
	end
	return table.concat(out, "\n")
end

------------------------------------------------------------------------------
-- More checks

function g.check_more(O, t)
	local start = vector.add(O, {x = 48, y = PF, z = 9})
	local seen, key = t.reach(O, start)
	local function at(x, y, z) return seen[key(vector.add(O, {x = x, y = y, z = z}))] == true end
	t.say("the sphinx's door, walked to: " .. tostring(at(18, PF, 29)))
	t.say("level 1, the entry hall: " .. tostring(at(22, L1 + 1, 52)))
	t.say("the treasury: " .. tostring(at(68, L1 + 1, 28)))
	t.say("the jackal's jar (beside it): " .. tostring(at(61, L1 + 1, 67)))
	t.say("level 2, the guard room: " .. tostring(at(84, L2 + 1, 34)))
	t.say("the spiral's middle: " .. tostring(at(26, L2 + 1, 33)))
	t.say("the falcon's jar (beside it): " .. tostring(at(40, L2 + 1, 16)))
	t.say("level 3, the hall of guardians: " .. tostring(at(21, L3 + 1, 46)))
	t.say("the endless passage: " .. tostring(at(40, L3 + 1, 70)))
	t.say("the woman's jar (beside it): " .. tostring(at(36, L3 + 1, 60)))
	t.say("the dais (before the sarcophagus): " .. tostring(at(81, L3 + 2, 42)))
	t.say("the pyramid's chamber: " .. tostring(at(72, PF, 78)))
	t.say("the rock tomb's chamber: " .. tostring(at(19, PG - 5, 81)))
	t.say("tahna checks done")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.chests, g.signs, g.spawners = {}, {}, {}
	KEEP = {}
	seed = 4242
	ground()
	forecourt()
	sphinx()
	pyramid()
	rock_tomb()
	keep(44, 6, 53, 12)      -- the start
	dunes()
	level1()
	level2()
	level3()
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
	for name in pairs(missing) do core.log("error", "[tahna] no such node: " .. name) end
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
