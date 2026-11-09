-- The Gullet: builds the ready-made combat adventure in a world, so that it
-- can be saved as adventures/gullet.we (see tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/gullet.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/gullet.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 35 (players stand at y = 36): nothing rises more than four
-- blocks above it. Below it, the gorge: its floor is y = 8 (players stand at
-- y = 9), 27 blocks down, open to the sky.
--
--   Thornwatch (on the ground, outside the dungeon): a palisade fort at the
--     mouth of the gorge, with the gate, the board, the smithy and the
--     arrival point. Its gate tower stands over the drop, portcullis down,
--     with a ladder below it to the gorge floor. A kerb and fence, two
--     blocks high, run round the rim.
--   The ravine (the gorge) winds north, narrow at the floor and stepping
--     back as it rises. Tunnels lead off it, bending, to the caves, graded:
--     west: the mossling warren, and through it the wisp hollow;
--     east: the kobold den, then the goblins' cave;
--     west, up a tunnel that climbs: the old crypt (skeletons);
--     east, near the head: the orc hall (orcs and a hexer).
--   Beyond the head of the gorge, in the rock, the warlord's temple:
--   the way in runs through the orc hall; a dark passage from the back of the
--   old crypt is the secret way. The warlord guards the finish, with two
--   skeletons; the finish chest is beside it.
--
-- Each cave has a spawner (once per run, waking when a player comes near) and
-- most a loot chest. Party of one to four, ranks 1 to 5.

local g = {}

local SX, SY, SZ = 64, 40, 80
local G, F = 8, 9           -- the gorge floor, and where players stand on it
local NG, NF = 35, 36       -- the land's ground, and where players stand on it
local BED = 4               -- the template's rock goes down to here

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
	ground = NG,
	-- everything below the ground is the template's (rock, and the gorge and
	-- caves cut into it): cleared first
	dig = {{min = {x = 0, y = BED, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 2, y = 0, z = 13},
	-- the area: the gorge and the caves, up to the ground (players up on the
	-- land around the gorge are not in it)
	corner2 = {x = 61, y = NG, z = 78},
	start = {x = 32.5, y = F, z = 15.5},
	arrival = {x = 32.5, y = NF, z = 4.5},
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
	box(0, BED, 0, SX - 1, NG - 4, SZ - 1, ROCK)
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, "default:dirt")
	box(0, NG, 0, SX - 1, NG, SZ - 1, "default:dirt_with_grass")
end
g.surface = NF

-- Thornwatch: a palisade fort at the mouth of the ravine
local function thornwatch()
	box(20, NG, 1, 44, NG, 11, "default:dirt")
	for z = 2, 11 do set(32, NG, z, GRAVEL); set(33, NG, z, GRAVEL) end
	-- the palisade: logs, three high, a point on every other one, with the
	-- way in from outside on the south side (x 31 to 34), under a lintel
	for x = 20, 44 do
		if x < 31 or x > 34 then
			box(x, NF, 1, x, NF + 2, 1, LOG)
			if x % 2 == 0 then set(x, NF + 3, 1, LOG) end
		end
	end
	box(30, NF + 3, 1, 35, NF + 3, 1, PLANK)
	for x = 31, 34 do set(x, NG, 0, GRAVEL); set(x, NG, 1, GRAVEL) end
	for z = 1, 11 do
		box(20, NF, z, 20, NF + 2, z, LOG); box(44, NF, z, 44, NF + 2, z, LOG)
		if z % 2 == 0 then set(20, NF + 3, z, LOG); set(44, NF + 3, z, LOG) end
	end
	for x = 20, 44 do
		if x < 30 or x > 35 then
			box(x, NF, 12, x, NF + 2, 12, LOG)
			if x % 2 == 0 then set(x, NF + 3, 12, LOG) end
		end
	end
	-- the gate tower over the drop into the gorge, its portcullis down: the
	-- adventure gate takes a party in, and nobody walks out but by the finish
	box(29, NF, 12, 29, NF + 3, 12, LOG); box(36, NF, 12, 36, NF + 3, 12, LOG)
	box(29, NF + 3, 12, 36, NF + 3, 12, PLANK)
	box(30, NF, 12, 35, NF + 2, 12, "xpanes:bar_flat", 0)
	for _, p in ipairs({{21, 2}, {43, 2}, {21, 11}, {43, 11}}) do set(p[1], NF, p[2], "default:mese_post_light") end
	set(32, NF, 9, "orthoverse_adventure:gate", 0)
	g.gate = {x = 32, y = NF, z = 9}
	set(28, NF, 10, "orthoverse_adventure:board", 0)
	sign(38, NF + 1, 11, "+z", "THE GULLET\nTribes dig into the walls of the ravine, and an orc warlord rules them " ..
		"from a temple at its head.\nRight-click the gate to go in. Ranks 1 to 5.")
	-- the smithy: a forge, an anvil block and the recipes on a sign
	box(22, NF, 3, 26, NF, 7, "air")
	box(21, NF, 3, 21, NF + 2, 7, "default:brick")
	box(22, NF + 3, 2, 27, NF + 3, 8, PLANK)
	for _, p in ipairs({{27, 2}, {27, 8}}) do box(p[1], NF, p[2], p[1], NF + 2, p[2], LOG) end
	set(22, NF, 4, "default:furnace", 1)
	set(22, NF, 6, "default:steelblock")
	sign(22, NF + 1, 5, "-x", "THE SMITHY\nWeapons are made from steel or bronze ingots, mese crystals " ..
		"or diamonds, and sticks: see the craft guide. A metal counts in full only from a rank: " ..
		"bronze 3, mese 6, diamond 10.")
	-- the notice board of what is known about the caves
	sign(43, NF + 1, 6, "+x", "WHAT WE KNOW\nWest: a mossling warren, and beyond it a hollow where lights float. " ..
		"East: kobolds, and further in, goblins. Up a tunnel in the west wall: an old crypt. Near the head, east: the orc hall. " ..
		"The warlord's temple lies in the rock beyond the head of the gorge, and the way in runs through the orc hall.")
end

-- The ravine: a gorge that winds north, narrow at the bottom and stepping
-- back as it rises (a ledge every four blocks: too high to climb), its floor
-- rising a little towards the head, with scrub, boulders, bones and a few
-- stunted trees. The caves open off it through tunnels.
local RAV_Z1, RAV_Z2 = 13, 56
local function rav_c(z) return 32 + math.floor(3 * math.sin((z - RAV_Z1) / 8) + 0.5) end
local function rav_w(z)
	local w = 3 + math.floor(1.5 + 1.5 * math.sin((z - RAV_Z1) / 5 + 1) + 0.5)
	if z > RAV_Z2 - 4 then w = math.max(2, w - (z - (RAV_Z2 - 4))) end
	return w
end
local function rav_floor(z) return G + (z < 32 and 0 or (z < 44 and 1 or 2)) end
-- Below y = 24 (where the caves are) the gorge keeps within x 25 to 39, so
-- there are two blocks of rock at least between it and any cave
local LOW_X1, LOW_X2 = 25, 39
local function rav_west(z) return math.max(LOW_X1, rav_c(z) - rav_w(z)) end
local function rav_east(z) return math.min(LOW_X2, rav_c(z) + rav_w(z)) end
g.rav_floor = rav_floor

local function ravine()
	for z = RAV_Z1, RAV_Z2 do
		local c, w, fy = rav_c(z), rav_w(z), rav_floor(z)
		for y = fy + 1, NG do
			local s = math.floor((y - fy - 1) / 4)
			local x1, x2 = c - w - s, c + w + s
			if y <= 24 then x1, x2 = math.max(x1, LOW_X1), math.min(x2, LOW_X2) end
			for x = x1, x2 do set(x, y, z, "air") end
			-- streaks in the faces: moss, cobble, earth near the top
			for _, x in ipairs({x1 - 1, x2 + 1}) do
				if x >= 0 and x < SX and get(x, y, z) == ROCK then
					local r = rnd(10)
					if y >= NG - 3 then set(x, y, z, "default:dirt")
					elseif r == 0 then set(x, y, z, MOSSY)
					elseif r == 1 then set(x, y, z, COBBLE)
					elseif r == 2 then set(x, y, z, "default:gravel") end
				end
			end
		end
		for x = rav_west(z), rav_east(z) do
			local r = rnd(6)
			set(x, fy, z, r == 0 and "default:dirt_with_grass" or (r == 1 and "default:dirt" or GRAVEL))
		end
	end
	-- where the floor rises, a step up all the way across (a block, walkable)
	-- scrub, bones, boulders, a few stunted trees in the middle of the floor
	for z = RAV_Z1 + 4, RAV_Z2 - 2 do
		local fy = rav_floor(z)
		local x1, x2 = rav_west(z), rav_east(z)
		for x = x1, x2 do
			if get(x, fy + 1, z) == "air" then
				local r = rnd(40)
				if r == 0 then set(x, fy + 1, z, "default:dry_shrub")
				elseif r == 1 then set(x, fy + 1, z, "default:junglegrass")
				elseif r == 2 and x > x1 and x < x2 then set(x, fy + 1, z, MOSSY)   -- a boulder
				end
			end
		end
	end
	for _, p in ipairs({{30, 22}, {35, 41}, {31, 50}}) do
		local x, z = p[1], p[2]
		local fy = rav_floor(z)
		box(x, fy + 1, z, x, fy + 3, z, LOG)
		for dx = -1, 1 do for dz = -1, 1 do
			if get(x + dx, fy + 4, z + dz) == "air" then set(x + dx, fy + 4, z + dz, "default:leaves") end
		end end
		set(x, fy + 5, z, "default:leaves")
	end
	-- the ladder down from the gate tower, on the gorge's south face
	box(32, F, 13, 32, NG, 13, "default:ladder_wood", SIGN_P2["-z"])
	sign(34, F + 1, 13, "-z", "The caves open off the gorge. Clear them, or go straight for the warlord: " ..
		"the way to his temple runs through the orc hall.")
	-- round the rim, a stone kerb with a fence on it: two blocks high, so
	-- nobody up on the land walks or jumps over the edge
	g.rim = {}
	local function open(x, z) return x >= 0 and x < SX and z >= 0 and z < SZ and get(x, NG, z) == "air" end
	for z = 0, SZ - 1 do for x = 0, SX - 1 do
		if not open(x, z) and not (z <= 12 and x >= 20 and x <= 44) then
			local edge = false
			for dx = -1, 1 do for dz = -1, 1 do if open(x + dx, z + dz) then edge = true end end end
			if edge then
				set(x, NF, z, MOSSY); set(x, NF + 1, z, FENCE)
				g.rim[#g.rim + 1] = {x, z}
			end
		end
	end end
end

-- A tunnel: 2 wide, 3 high, along `path` ({x, f, z}: f is the floor block's
-- height), each leg straight along x or z, sloping a block at a time; a lamp
-- at each bend
local function tunnel(path)
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local dx, dz = b[1] - a[1], b[3] - a[3]
		assert(dx == 0 or dz == 0, "tunnel legs go along x or z")
		local n = math.max(math.abs(dx), math.abs(dz))
		for k = 0, n do
			local x = a[1] + (n > 0 and math.floor(dx * k / n) or 0)
			local z = a[3] + (n > 0 and math.floor(dz * k / n) or 0)
			local f = a[2] + (n > 0 and math.floor((b[2] - a[2]) * k / n + 0.5) or 0)
			local ox, oz = (dx == 0) and 1 or 0, (dx == 0) and 0 or 1
			for w = 0, 1 do
				local tx, tz = x + ox * w, z + oz * w
				if get(tx, f, tz) == "air" then set(tx, f, tz, ROCK) end
				for y = f + 1, f + 3 do set(tx, y, tz, "air") end
			end
		end
		if i > 1 then set(a[1], a[2] + 4, a[3], LAMP) end
	end
end

-- West: the mossling warren, low and green; its tunnel opens near the
-- gorge's mouth and turns north into it
local function warren()
	cave(12, 17, 22, 27, G, 3, MOSSY, 5)
	tunnel({{rav_west(13), G, 13}, {18, G, 13}, {18, G, 17}})
	for _, p in ipairs({{13, 25}, {20, 18}, {16, 26}, {12, 19}}) do set(p[1], F, p[2], "default:junglegrass") end
	spawner(16, G, 22, "mossling", 3, 8)
	chest(13, F, 18, "common", 1)
end

-- West, beyond the warren: the wisp hollow, reached only through the warren
local function hollow()
	cave(15, 30, 22, 36, G, 4, ROCK, 0)
	tunnel({{16, G, 27}, {16, G, 30}})
	set(21, F, 35, "default:mese_post_light")
	spawner(18, G, 33, "wisp", 2, 10)
	chest(16, F, 35, "common", 1)
end

-- East: the kobold den, bones and a fire; its tunnel opens just inside the
-- gorge and turns north
local function den()
	cave(42, 19, 53, 29, G, 3, FLOOR, 4)
	tunnel({{rav_east(16) - 1, G, 16}, {45, G, 16}, {45, G, 19}})
	for _, p in ipairs({{44, 21}, {51, 27}, {47, 28}}) do set(p[1], F, p[2], "bones:bones") end
	set(49, G, 21, "default:coalblock"); set(49, F, 21, "fire:permanent_flame")
	spawner(49, G, 25, "kobold", 4, 8)
	chest(52, F, 28, "common", 3)
end

-- East, further in: the goblins' cave, with their tents and fire; its
-- tunnel climbs a little and bends south into it
local GOB = G + 1
local function goblins()
	cave(50, 32, 59, 41, GOB, 4, "default:dirt", 4)
	local f = rav_floor(33)
	tunnel({{rav_east(33) - 1, f, 33}, {46, f, 33}, {46, GOB, 37}, {50, GOB, 37}})
	local function tent(x1, z1, colour)
		box(x1, GOB + 1, z1, x1 + 2, GOB + 2, z1 + 2, colour)
		set(x1 + 1, GOB + 3, z1 + 1, colour)
		air(x1 + 1, GOB + 1, z1, x1 + 1, GOB + 2, z1)            -- its door
	end
	tent(51, 34, "wool:red")
	tent(55, 34, "wool:brown")
	set(54, GOB, 38, "default:coalblock"); set(54, GOB + 1, 38, "fire:permanent_flame")
	spawner(52, GOB, 39, "goblin", 3, 10)
	chest(58, GOB + 1, 40, "weapon", 3)
end

-- Up the west wall: a stair cut into the face, a tunnel, the old crypt
local CRYPT = G + 6                                       -- the crypt's floor
local function crypt()
	-- a tunnel from the west face, climbing north inside the rock
	local fy = rav_floor(38)
	tunnel({{rav_west(38), fy, 38}, {22, fy, 38}, {22, CRYPT, 43}, {20, CRYPT, 43}})
	cave(8, 43, 20, 54, CRYPT, 4, FLOOR, 4)
	-- the tombs
	for _, z in ipairs({45, 48, 51}) do
		box(9, CRYPT + 1, z, 11, CRYPT + 1, z + 1, "default:stonebrick")
		box(15, CRYPT + 1, z, 17, CRYPT + 1, z + 1, "default:stonebrick")
	end
	sign(20, CRYPT + 2, 45, "+x", "THE OLD CRYPT\nThe tribes keep away. The dead do not stay down.")
	spawner(13, CRYPT, 48, "skeleton", 3, 8)
	chest(9, CRYPT + 1, 53, "weapon", 1)
	-- the secret way: a dark passage from the back of the crypt to the temple
	air(10, CRYPT + 1, 55, 11, CRYPT + 2, 66)
	box(10, CRYPT, 55, 11, CRYPT, 66, FLOOR)
	air(12, CRYPT + 1, 65, 23, CRYPT + 2, 66)
	box(12, CRYPT, 65, 23, CRYPT, 66, FLOOR)
end

-- East, near the head: the orc hall, through a tunnel that climbs and turns
local HALL = G + 3
local function hall()
	local f = rav_floor(41)
	tunnel({{rav_east(41) - 1, f, 41}, {47, f, 41}, {47, HALL, 44}})
	cave(43, 44, 58, 60, HALL, 5, FLOOR, 4)
	-- pillars and a long table
	for _, p in ipairs({{46, 47}, {55, 47}, {46, 57}, {55, 57}}) do box(p[1], HALL + 1, p[2], p[1], HALL + 5, p[2], COBBLE) end
	box(49, HALL + 1, 50, 52, HALL + 1, 54, PLANK)
	sign(45, HALL + 2, 44, "-z", "THE ORC HALL\nThe warlord's way lies at the back, through the north passage.")
	spawner(50, HALL, 47, "orc", 2, 10)
	spawner(56, HALL, 58, "hexer", 1, 12)
	chest(57, HALL + 1, 45, "common", 3)
	-- the passage north to the temple, climbing
	air(43, HALL + 1, 61, 44, HALL + 3, 66)
	box(43, HALL, 61, 44, HALL, 63, FLOOR)
	box(43, HALL + 1, 64, 44, HALL + 1, 66, FLOOR)
	air(43, HALL + 2, 64, 44, HALL + 5, 66)
	air(41, HALL + 2, 65, 42, HALL + 5, 66)
	box(41, HALL + 1, 65, 42, HALL + 1, 66, FLOOR)
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

-- A plan of the gorge and caves below y = 24, north at the top: "." the
-- gorge, "o" caves and tunnels, "#" rock (for checking by eye)
function g.plan()
	local rows = {}
	for z = SZ - 1, 0, -1 do
		local row = {}
		for x = 0, SX - 1 do
			local ch = "#"
			if get(x, 24, z) == "air" and z >= RAV_Z1 and z <= RAV_Z2 then ch = "."
			else
				for y = F, 24 do if get(x, y, z) == "air" then ch = "o" break end end
			end
			row[#row + 1] = ch
		end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, "\n")
end

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
	goblins()
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
