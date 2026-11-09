-- The Gullet: builds the ready-made combat adventure in a world, so that it
-- can be saved as adventures/gullet.we (see tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/gullet.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/gullet.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The ground
-- layer is y = 8 (players stand at y = 9).
--
--   Thornwatch (outside the dungeon): a palisade fort at the mouth of the
--     ravine, with the gate, the board, the smithy and the arrival point.
--   The ravine runs north between rock walls. Caves in the walls, graded:
--     west: the mossling warren, then the wisp hollow;
--     east: the kobold den;
--     the floor: the goblin camp, behind a fence;
--     up a stair in the west wall: the old crypt (skeletons);
--     up a ramp in the east wall: the orc hall (orcs and a hexer).
--   A rockfall closes the head of the ravine. Behind it, the warlord's temple:
--   the way in runs through the orc hall; a dark passage from the back of the
--   old crypt is the secret way. The warlord guards the finish, with two
--   skeletons; the finish chest is beside it.
--
-- Each cave has a spawner (once per run, waking when a player comes near) and
-- most a loot chest. Party of one to four, ranks 1 to 5.

local g = {}

local SX, SY, SZ = 64, 40, 80
local G, F = 8, 9

local ROCK = "default:stone"
local COBBLE = "default:cobble"
local MOSSY = "default:mossycobble"
local FLOOR = "default:stone_block"
local GRAVEL = "default:gravel"
local TEMPLE = "default:sandstonebrick"
local TEMPLE_FLOOR = "default:sandstone_block"
local LOG = "default:tree"
local PLANK = "default:wood"
local LAMP = "default:meselamp"
local FENCE = "default:fence_wood"
local SIGN = "default:sign_wall_wood"
local SPAWNER = "orthoverse_monsters:spawner"
local CHEST = "orthoverse_loot:chest"
local FINISH = "orthoverse_adventure:finish"

g.info = {
	name = "The Gullet",
	line = "Tribes dig into the walls of a ravine below Thornwatch fort, and an orc warlord rules them from a temple at its head.",
	limit = 60,
	rank_min = 1, rank_max = 5,
	size = {x = SX, y = SY, z = SZ},
	ground = G,
	dig = {},
	corner1 = {x = 2, y = 0, z = 13},
	corner2 = {x = 61, y = SY - 1, z = 78},
	start = {x = 32.5, y = F, z = 15.5},
	arrival = {x = 32.5, y = F, z = 4.5},
}

-- Where things are, for tests: spawners (kind, count, wake), chests (kind)
g.spawners = {}
g.chests = {}
g.signs = {}
g.finish = {x = 32, y = 14, z = 74}

------------------------------------------------------------------------------
-- A grid of the whole template, written in one go

local grid, p2grid, metas

local function idx(x, y, z) return x + y * SX + z * SX * SY + 1 end

local function set(x, y, z, name, param2)
	assert(x >= 0 and x < SX and y >= 0 and y < SY and z >= 0 and z < SZ, ("outside: %d,%d,%d"):format(x, y, z))
	local i = idx(x, y, z)
	grid[i] = name
	p2grid[i] = param2 or 0
end

local function get(x, y, z) return grid[idx(x, y, z)] end

local function box(x1, y1, z1, x2, y2, z2, name, param2)
	for z = z1, z2 do for y = y1, y2 do for x = x1, x2 do set(x, y, z, name, param2) end end end
end

local function air(x1, y1, z1, x2, y2, z2) box(x1, y1, z1, x2, y2, z2, "air") end

-- A repeatable roll of the dice, so every build is the same
local seed = 12345
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end

-- A room carved out of the rock: floor at fy, air above for h, lamps in the
-- ceiling every `every` blocks (none if 0)
local function cave(x1, z1, x2, z2, fy, h, floor, every)
	box(x1, fy, z1, x2, fy, z2, floor or FLOOR)
	air(x1, fy + 1, z1, x2, fy + h, z2)
	every = every or 4
	if every > 0 then
		for z = z1 + 1, z2 - 1, every do for x = x1 + 1, x2 - 1, every do set(x, fy + h + 1, z, LAMP) end end
	end
	-- a rough ceiling: some blocks hang down at the edges
	for _ = 1, math.floor((x2 - x1) * (z2 - z1) / 10) do
		local x, z = x1 + rnd(x2 - x1 + 1), z1 + rnd(z2 - z1 + 1)
		if (x == x1 or x == x2 or z == z1 or z == z2) and get(x, fy + h, z) == "air" then set(x, fy + h, z, ROCK) end
	end
end

local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}
local function sign(x, y, z, dir, text)
	set(x, y, z, SIGN, SIGN_P2[dir])
	g.signs[#g.signs + 1] = {x = x, y = y, z = z, dir = dir, text = text:match("^[^\n]*")}
	metas[#metas + 1] = {x = x, y = y, z = z, fields = {text = text, infotext = '"' .. text .. '"'}, construct = true}
end

-- A spawner in the floor (its block replaces the floor block)
local function spawner(x, y, z, kind, count, wake)
	set(x, y, z, SPAWNER)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {
		kind = "orthoverse_monsters:" .. kind, count = tostring(count), wake = tostring(wake),
		infotext = "Monster spawner: " .. count .. " × " .. kind}}
	g.spawners[#g.spawners + 1] = {x = x, y = y, z = z, kind = kind, count = count, wake = wake}
end

-- A loot chest standing on the floor; facing: param2 (0 faces -z ... )
local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot chest (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

------------------------------------------------------------------------------
-- The parts

local function ground()
	box(0, G, 0, SX - 1, G, SZ - 1, "default:dirt_with_grass")
end

-- Thornwatch: a palisade fort at the mouth of the ravine
local function thornwatch()
	box(20, G, 1, 44, G, 11, "default:dirt")
	for z = 2, 11 do set(32, G, z, GRAVEL); set(33, G, z, GRAVEL) end
	-- the palisade: logs, three high, a point on every other one, with the
	-- way in from outside on the south side (x 31 to 34), under a lintel
	for x = 20, 44 do
		if x < 31 or x > 34 then
			box(x, F, 1, x, F + 2, 1, LOG)
			if x % 2 == 0 then set(x, F + 3, 1, LOG) end
		end
	end
	box(30, F + 3, 1, 30, F + 4, 1, LOG); box(35, F + 3, 1, 35, F + 4, 1, LOG)
	box(30, F + 4, 1, 35, F + 4, 1, PLANK)
	for x = 31, 34 do set(x, G, 0, GRAVEL); set(x, G, 1, GRAVEL) end
	for z = 1, 11 do
		box(20, F, z, 20, F + 2, z, LOG); box(44, F, z, 44, F + 2, z, LOG)
		if z % 2 == 0 then set(20, F + 3, z, LOG); set(44, F + 3, z, LOG) end
	end
	for x = 20, 44 do
		if x < 30 or x > 35 then
			box(x, F, 12, x, F + 2, 12, LOG)
			if x % 2 == 0 then set(x, F + 3, 12, LOG) end
		end
	end
	-- the gate tower over the way into the ravine, its portcullis down: the
	-- adventure gate takes a party in, and nobody walks out but by the finish
	box(29, F, 12, 29, F + 4, 12, LOG); box(36, F, 12, 36, F + 4, 12, LOG)
	box(29, F + 4, 12, 36, F + 4, 12, PLANK)
	box(30, F, 12, 35, F + 3, 12, "xpanes:bar_flat", 0)
	for _, p in ipairs({{21, 2}, {43, 2}, {21, 11}, {43, 11}}) do set(p[1], F, p[2], "default:mese_post_light") end
	set(32, F, 9, "orthoverse_adventure:gate", 0)
	g.gate = {x = 32, y = F, z = 9}
	set(28, F, 10, "orthoverse_adventure:board", 0)
	sign(38, F + 1, 11, "+z", "THE GULLET\nTribes dig into the walls of the ravine, and an orc warlord rules them " ..
		"from a temple at its head.\nRight-click the gate to go in. Ranks 1 to 5.")
	-- the smithy: a forge, an anvil block and the recipes on a sign
	box(22, F, 3, 26, F, 7, "air")
	box(21, F, 3, 21, F + 2, 7, "default:brick")
	box(22, F + 3, 2, 27, F + 3, 8, PLANK)
	for _, p in ipairs({{27, 2}, {27, 8}}) do box(p[1], F, p[2], p[1], F + 2, p[2], LOG) end
	set(22, F, 4, "default:furnace", 1)
	set(22, F, 6, "default:steelblock")
	sign(22, F + 1, 5, "-x", "THE SMITHY\nWeapons are made from steel or bronze ingots, mese crystals " ..
		"or diamonds, and sticks: see the craft guide. A metal counts in full only from a rank: " ..
		"bronze 3, mese 6, diamond 10.")
	-- the notice board of what is known about the caves
	sign(43, F + 1, 6, "+x", "WHAT WE KNOW\nWest: a mossling warren, and a hollow where lights float. " ..
		"East: kobolds. On the floor: a goblin camp. Up the west wall: an old crypt. Up the east wall: the orc hall. " ..
		"The warlord's temple lies behind the rockfall, and the way in runs through the orc hall.")
end

-- The ravine: rock walls, a gravel floor, rough faces
local function ravine()
	box(2, G, 13, 23, 34, 78, ROCK)
	box(41, G, 13, 61, 34, 78, ROCK)
	box(24, G, 77, 40, 34, 78, ROCK)
	box(2, 35, 13, 23, 35, 78, "default:dirt_with_grass")
	box(41, 35, 13, 61, 35, 78, "default:dirt_with_grass")
	box(24, 35, 77, 40, 35, 78, "default:dirt_with_grass")
	for z = 13, 76 do
		for x = 24, 40 do set(x, G, z, rnd(5) == 0 and "default:dirt" or GRAVEL) end
	end
	-- rough faces: some blocks of the walls stand out, some are mossy
	for z = 13, 76 do
		for y = F + 7, 34 do
			if rnd(9) == 0 then set(24, y, z, ROCK) end
			if rnd(9) == 0 then set(40, y, z, ROCK) end
			if rnd(7) == 0 then set(23, y, z, MOSSY) end
			if rnd(7) == 0 then set(41, y, z, MOSSY) end
		end
	end
	-- boulders on the floor
	for _, p in ipairs({{26, 20}, {38, 27}, {25, 33}, {39, 48}, {27, 52}}) do
		set(p[1], F, p[2], MOSSY)
	end
	sign(24, F + 1, 15, "-x", "Clear the caves, or go straight for the warlord. The way to his temple runs " ..
		"through the orc hall, up the ramp in the east wall.")
	-- the rockfall at the head of the ravine
	box(24, G, 58, 40, 24, 63, ROCK)
	for x = 24, 40 do
		for y = F, 24 do if rnd(3) == 0 then set(x, y, 57, COBBLE) end end
		set(x, F, 56, rnd(2) == 0 and GRAVEL or "air")
	end
end

-- West: the mossling warren, low and green
local function warren()
	cave(12, 17, 22, 27, G, 3, MOSSY, 5)
	air(23, F, 21, 23, F + 2, 22)
	set(23, G, 21, MOSSY); set(23, G, 22, MOSSY)
	for _, p in ipairs({{13, 25}, {20, 18}, {16, 26}, {12, 19}}) do set(p[1], F, p[2], "default:junglegrass") end
	spawner(16, G, 22, "mossling", 3, 8)
	chest(13, F, 18, "common", 1)
end

-- West: the wisp hollow
local function hollow()
	cave(15, 30, 22, 36, G, 4, ROCK, 0)
	air(23, F, 33, 23, F + 2, 34)
	set(23, G, 33, ROCK); set(23, G, 34, ROCK)
	set(16, F, 31, "default:mese_post_light")
	spawner(18, G, 33, "wisp", 2, 10)
	chest(16, F, 35, "common", 1)
end

-- East: the kobold den, bones and a fire
local function den()
	cave(42, 19, 53, 29, G, 3, FLOOR, 4)
	air(41, F, 23, 41, F + 2, 24)
	set(41, G, 23, FLOOR); set(41, G, 24, FLOOR)
	for _, p in ipairs({{44, 20}, {51, 27}, {47, 28}}) do set(p[1], F, p[2], "bones:bones") end
	set(48, G, 21, "default:coalblock"); set(48, F, 21, "fire:permanent_flame")
	spawner(49, G, 25, "kobold", 4, 8)
	chest(52, F, 28, "common", 3)
end

-- The floor: the goblin camp behind a fence, with tents
local function camp()
	for x = 26, 38 do set(x, F, 36, FENCE); set(x, F, 46, FENCE) end
	for z = 36, 46 do set(26, F, z, FENCE); set(38, F, z, FENCE) end
	for x = 31, 33 do set(x, F, 36, "air") end          -- the way in, from the south
	for x = 31, 33 do set(x, F, 46, "air") end          -- and out, to the north
	local function tent(x1, z1, colour)
		box(x1, F, z1, x1 + 2, F, z1 + 2, colour)
		box(x1, F + 1, z1, x1 + 2, F + 1, z1 + 2, colour)
		set(x1 + 1, F + 2, z1 + 1, colour)
		air(x1 + 1, F, z1, x1 + 1, F + 1, z1)            -- its door
	end
	tent(27, 38, "wool:red")
	tent(35, 41, "wool:brown")
	tent(27, 42, "wool:red")
	set(32, G, 41, "default:coalblock"); set(32, F, 41, "fire:permanent_flame")
	spawner(33, G, 39, "goblin", 3, 10)
	chest(36, F, 38, "weapon", 2)
end

-- Up the west wall: the stair to the old crypt, and the crypt
local CRYPT = G + 6                                       -- the crypt's floor
local function crypt()
	-- the stair, cut into the face going north, one step a block
	for i = 0, 5 do
		local z = 37 + i
		box(21, G, z, 23, G + 1 + i, z, FLOOR)
		air(21, G + 2 + i, z, 23, G + 5 + i, z)
	end
	air(21, CRYPT + 1, 43, 23, CRYPT + 3, 45)
	box(21, CRYPT, 43, 23, CRYPT, 45, FLOOR)
	cave(8, 43, 20, 54, CRYPT, 4, FLOOR, 4)
	-- the tombs
	for _, z in ipairs({45, 48, 51}) do
		box(9, CRYPT + 1, z, 11, CRYPT + 1, z + 1, "default:stonebrick")
		box(17, CRYPT + 1, z, 19, CRYPT + 1, z + 1, "default:stonebrick")
	end
	sign(20, CRYPT + 2, 46, "+x", "THE OLD CRYPT\nThe tribes keep away. The dead do not stay down.")
	spawner(14, CRYPT, 48, "skeleton", 3, 8)
	chest(9, CRYPT + 1, 53, "weapon", 1)
	-- the secret way: a dark passage from the back of the crypt to the temple
	air(10, CRYPT + 1, 55, 11, CRYPT + 2, 66)
	box(10, CRYPT, 55, 11, CRYPT, 66, FLOOR)
	air(12, CRYPT + 1, 65, 23, CRYPT + 2, 66)
	box(12, CRYPT, 65, 23, CRYPT, 66, FLOOR)
end

-- Up the east wall: the ramp to the orc hall, and the hall
local HALL = G + 2
local function hall()
	box(41, G, 50, 42, G + 1, 52, FLOOR)
	box(41, G, 50, 41, G, 52, FLOOR)
	air(41, F, 50, 41, F + 2, 52)                        -- first step up
	set(41, F, 50, FLOOR); set(41, F, 51, FLOOR); set(41, F, 52, FLOOR)
	air(41, F + 1, 50, 42, F + 4, 52)
	cave(43, 44, 58, 60, HALL, 5, FLOOR, 4)
	box(42, HALL, 50, 42, HALL, 52, FLOOR)
	air(42, HALL + 1, 50, 42, HALL + 4, 52)
	-- pillars and a long table
	for _, p in ipairs({{46, 47}, {55, 47}, {46, 57}, {55, 57}}) do box(p[1], HALL + 1, p[2], p[1], HALL + 5, p[2], COBBLE) end
	box(49, HALL + 1, 50, 52, HALL + 1, 54, PLANK)
	sign(43, HALL + 2, 49, "-x", "THE ORC HALL\nThe warlord's way lies at the back, through the north passage.")
	spawner(50, HALL, 47, "orc", 2, 10)
	spawner(56, HALL, 58, "hexer", 1, 12)
	chest(57, HALL + 1, 45, "common", 3)
	-- the passage north to the temple, climbing two steps
	air(43, HALL + 1, 61, 44, HALL + 3, 66)
	box(43, HALL, 61, 44, HALL, 63, FLOOR)
	box(43, HALL + 1, 64, 44, HALL + 1, 64, FLOOR)
	box(43, HALL + 2, 65, 44, HALL + 2, 66, FLOOR)
	air(43, HALL + 3, 64, 44, HALL + 5, 66)
	air(41, HALL + 3, 65, 42, HALL + 5, 66)
	box(41, HALL + 2, 65, 42, HALL + 2, 66, FLOOR)
end

-- The warlord's temple at the head of the ravine
local TEMPLE_Y = G + 4
local function temple()
	box(24, G, 64, 40, TEMPLE_Y, 76, TEMPLE)               -- the platform
	box(24, TEMPLE_Y + 1, 64, 40, TEMPLE_Y + 9, 64, TEMPLE)
	box(24, TEMPLE_Y + 1, 76, 40, TEMPLE_Y + 9, 76, TEMPLE)
	box(24, TEMPLE_Y + 1, 64, 24, TEMPLE_Y + 9, 76, TEMPLE)
	box(40, TEMPLE_Y + 1, 64, 40, TEMPLE_Y + 9, 76, TEMPLE)
	box(24, TEMPLE_Y + 10, 64, 40, TEMPLE_Y + 10, 76, TEMPLE)
	box(25, TEMPLE_Y, 65, 39, TEMPLE_Y, 75, TEMPLE_FLOOR)
	air(25, TEMPLE_Y + 1, 65, 39, TEMPLE_Y + 9, 75)
	for _, p in ipairs({{27, 67}, {37, 67}, {27, 72}, {37, 72}}) do
		box(p[1], TEMPLE_Y + 1, p[2], p[1], TEMPLE_Y + 9, p[2], "default:sandstone")
	end
	for z = 66, 74, 4 do for x = 26, 38, 4 do set(x, TEMPLE_Y + 9, z, LAMP) end end
	-- the ways in: east, from the orc hall's passage; west, the secret way
	air(40, TEMPLE_Y + 1, 65, 40, TEMPLE_Y + 2, 66)
	air(24, TEMPLE_Y + 1, 65, 24, TEMPLE_Y + 2, 66)
	box(24, TEMPLE_Y, 65, 24, TEMPLE_Y, 66, TEMPLE_FLOOR)
	-- the secret way comes in two blocks higher: steps down
	-- (the crypt's floor is two above the temple's)
	box(23, TEMPLE_Y, 65, 23, TEMPLE_Y + 1, 66, FLOOR)
	air(23, TEMPLE_Y + 2, 65, 23, TEMPLE_Y + 4, 66)
	-- the altar, the finish on it, the finish chest beside
	box(30, TEMPLE_Y + 1, 74, 34, TEMPLE_Y + 1, 75, "default:goldblock")
	set(g.finish.x, g.finish.y, g.finish.z, FINISH)
	chest(35, TEMPLE_Y + 1, 74, "finish", 0)
	sign(32, TEMPLE_Y + 3, 75, "+z", "THE WARLORD'S THRONE\nTouch the crown on the altar to claim the Gullet.")
	spawner(32, TEMPLE_Y, 69, "warlord", 1, 10)
	spawner(28, TEMPLE_Y, 73, "skeleton", 2, 10)
end

------------------------------------------------------------------------------

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.spawners, g.chests, g.signs = {}, {}, {}
	seed = 12345
	ground()
	thornwatch()
	ravine()
	warren()
	hollow()
	den()
	camp()
	crypt()
	hall()
	temple()
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
	for name in pairs(missing) do core.log("error", "[gullet] no such node: " .. name) end
	for _, m in ipairs(metas) do
		local pos = vector.add(p1, m)
		local node = core.get_node(pos)
		local def = core.registered_nodes[node.name]
		if m.construct and def and def.on_construct then def.on_construct(pos) end
		local meta = core.get_meta(pos)
		for k, v in pairs(m.fields) do meta:set_string(k, v) end
	end
	return missing
end

return g
