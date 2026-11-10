-- The Mill at Withy Ford: builds the ready-made adventure in a world, so that
-- it can be saved as adventures/mill.we (see tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/mill.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/mill.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 26 (players stand at y = 27).
--
--   Withy Ford (on the ground, outside the dungeon), south: a hamlet green
--     with the gate, the board, a well, two cottages and the villagers'
--     rumours.
--   The mill yard, walled (two blocks high: nobody climbs in or out), is the
--     dungeon's ground floor: the millpond, the mill race and the still
--     waterwheel in its pit (a windlass beside it), dead trees, wisps.
--   The mill, half-timbered: on the stone ground floor the mill works,
--     sacks, the millstone, mosslings; up an outside stair to the balcony,
--     the miller's rooms (his diary, a chest, a windlass); and from the
--     ground floor a stair down to
--   the cellar: the bone pit, where skeletons rise (two of them kobolds in
--     painted skull masks), a chest, the third windlass, a sluice gate in
--     the west wall, and behind a secret shelf (a loose brick opens it)
--   the smugglers' run: a stair down to the jetty on an underground river.
--     A rowing boat waits at the mooring; downstream, past a ledge where
--     wisps lurk, is the landing and
--   the smugglers' hall: kobolds and goblins among the contraband, two
--     chests, and the Ringmaster's office: the Ringmaster (a hexer in a fine
--     coat), two goblin bodyguards, the miller in chains, the ledger (the
--     finish) on the desk and the finish chest.
--   The shortcut: wind all three windlasses and the cellar's sluice gate
--     rises on a dry culvert that runs down to the hall.
--
-- Party of one to four, ranks 1 to 5.

local g = {}

local SX, SY, SZ = 64, 47, 64
local NG, NF = 26, 27
local CEL = 20                 -- the cellar's floor
local LOW = 9                  -- the river's, the hall's floor

local ROCK = "default:stone"
local BRICK = "default:stonebrick"
local COBBLE = "default:cobble"
local MOSSY = "default:mossycobble"
local PLANK = "default:wood"
local LOG = "default:tree"
local STRAW = "farming:straw"
local LAMP = "default:meselamp"
local SIGN = "default:sign_wall_wood"
local SPAWNER = "orthoverse_monsters:spawner"
local CHEST = "orthoverse_loot:chest"
local WATER = "default:water_source"

g.info = {
	name = "The Mill at Withy Ford",
	line = "Lights in the old mill at night, and screams. The miller vanished last spring. Nobody goes there now.",
	limit = 60,
	rank_min = 1, rank_max = 5,
	size = {x = SX, y = SY, z = SZ},
	ground = NG,
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 2, y = 0, z = 16},
	corner2 = {x = 61, y = SY - 1, z = 62},
	start = {x = 32.5, y = NF, z = 21.5},
	arrival = {x = 32.5, y = NF, z = 5.5},
}

g.spawners, g.chests, g.signs = {}, {}, {}
g.finish = {x = 8, y = LOW + 2, z = 59}
g.gate = {x = 32, y = NF, z = 8}
g.surface = NF
g.outside = {x = 2, y = NF, z = 2}
g.open_for_checks = {"orthoverse_props:secret_shelf", "orthoverse_props:sluice_gate"}
g.gated = {
	{label = "the river reachable without the secret shelf and the sluice", target = {x = 44, y = LOW + 1, z = 43},
		blocked = {{{x = 31, y = CEL + 1, z = 30}, {x = 32, y = CEL + 2, z = 30}}, {{x = 24, y = CEL + 1, z = 21}, {x = 24, y = CEL + 3, z = 22}}}},
}

------------------------------------------------------------------------------

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

local seed = 777
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end

local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}
local function sign(x, y, z, dir, text)
	set(x, y, z, SIGN, SIGN_P2[dir])
	g.signs[#g.signs + 1] = {x = x, y = y, z = z, dir = dir, text = text:match("^[^\n]*")}
	metas[#metas + 1] = {x = x, y = y, z = z, fields = {text = text, infotext = '"' .. text .. '"'}, construct = true}
end

local function spawner(x, y, z, kind, count, wake, aloft)
	set(x, y, z, SPAWNER)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {
		kind = "orthoverse_monsters:" .. kind, count = tostring(count), wake = tostring(wake),
		infotext = "Monster spawner: " .. count .. " × " .. kind}}
	g.spawners[#g.spawners + 1] = {x = x, y = y, z = z, kind = kind, count = count, wake = wake, aloft = aloft}
end

-- facing: param2 (0: the front faces -z (south), 1: -x (west), 2: +z, 3: +x)
local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot chest (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

-- A tunnel: 2 wide, 3 high, along `path` ({x, f, z}: f is the floor's
-- height), each leg straight along x or z, sloping a block at a time; a lamp
-- at each bend
local function tunnel(path, floor)
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
				set(tx, f, tz, floor or COBBLE)
				for y = f + 1, f + 3 do set(tx, y, tz, "air") end
			end
		end
		if i > 1 then set(a[1], a[2] + 4, a[3], LAMP) end
	end
end

------------------------------------------------------------------------------
-- The parts

local function ground()
	box(0, 0, 0, SX - 1, NG - 4, SZ - 1, ROCK)
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, "default:dirt")
	box(0, NG, 0, SX - 1, NG, SZ - 1, "default:dirt_with_grass")
end

-- Withy Ford: the green, the gate, the well, two cottages
local function hamlet()
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(28, NF, 8, "orthoverse_adventure:board", 0)
	-- the well
	box(37, NF, 9, 39, NF, 11, COBBLE)
	set(38, NF, 10, "air")
	set(38, NG, 10, WATER)
	box(37, NF + 1, 9, 37, NF + 2, 9, PLANK); box(39, NF + 1, 11, 39, NF + 2, 11, PLANK)
	-- the cottages: plank walls, a slab roof, a door
	local function cottage(x1, z1)
		box(x1, NF, z1, x1 + 5, NF + 2, z1 + 5, PLANK)
		air(x1 + 1, NF, z1 + 1, x1 + 4, NF + 2, z1 + 4)
		box(x1, NF + 3, z1, x1 + 5, NF + 3, z1 + 5, "stairs:slab_wood")
		air(x1 + 2, NF, z1 + 5, x1 + 3, NF + 1, z1 + 5)       -- the door, facing the green
		set(x1, NF + 1, z1 + 2, "default:glass"); set(x1 + 5, NF + 1, z1 + 2, "default:glass")
	end
	cottage(18, 2)
	cottage(42, 2)
	sign(24, NF + 1, 5, "-x", "WITHY FORD\nLights in the old mill at night, and screams. The miller vanished last " ..
		"spring. Nobody goes there now.\nRight-click the gate to go in. Ranks 1 to 5.")
	sign(41, NF + 1, 5, "+x", "WHAT THE VILLAGERS SAY\nGhosts walk the mill yard, little glowing ones. " ..
		"The cellar is full of the dead, and the dead get up. Carts go by at night with no lights. " ..
		"The miller owed money to a man in a red coat.")
end

-- The mill yard: walled, with the pond, the race, the wheel and dead trees
local function yard()
	for x = 2, 61 do for _, z in ipairs({16, 62}) do set(x, NF, z, COBBLE); set(x, NF + 1, z, MOSSY) end end
	for z = 16, 62 do for _, x in ipairs({2, 61}) do set(x, NF, z, COBBLE); set(x, NF + 1, z, MOSSY) end end
	-- the millpond, and the race from it to the wheel
	for z = 19, 35 do for x = 4, 15 do
		if ((x - 9.5) / 6) ^ 2 + ((z - 27) / 8.5) ^ 2 <= 1 then
			set(x, NG - 2, z, "default:dirt"); set(x, NG - 1, z, WATER); set(x, NG, z, WATER)
		end
	end end
	for x = 14, 22 do for z = 24, 25 do set(x, NG - 1, z, "default:dirt"); set(x, NG, z, WATER) end end
	-- the waterwheel, still now, in its stone-edged pit at the end of the race,
	-- beside the mill's west wall: a rim of dark planks two thick, spokes, and
	-- its axle into the wall
	for z = 18, 31 do for x = 18, 23 do
		if x == 18 or z == 18 or z == 31 then set(x, NG, z, BRICK)
		else set(x, NG - 2, z, "default:dirt"); set(x, NG - 1, z, WATER); set(x, NG, z, WATER) end
	end end
	for x = 14, 18 do for z = 24, 25 do set(x, NG - 1, z, "default:dirt"); set(x, NG, z, WATER) end end
	for y = NG - 4, NF + 4 do for z = 19, 30 do
		local dy, dz = y - (NG + 1), z - 24.5
		local d = math.sqrt(dy ^ 2 + dz ^ 2)
		if d >= 4.5 and d <= 5.5 then
			-- the rim, with a paddle standing out every so often
			set(21, y, z, "default:junglewood"); set(22, y, z, "default:junglewood")
			if (math.floor(math.deg(math.atan2(dy, dz)) + 360) % 45) < 12 then set(20, y, z, "stairs:slab_junglewood") end
		elseif d < 4.5 and (dy == 0 or math.abs(dz) < 0.6 or math.abs(math.abs(dy) - math.abs(dz)) < 0.6) then
			set(22, y, z, "default:fence_junglewood")      -- spokes
		end
	end end
	set(22, NG + 1, 24, "default:tree", 12); set(23, NG + 1, 24, "default:tree", 12)
	set(23, NF, 31, "orthoverse_props:windlass", 2)
	-- dead trees, overgrowth
	for _, p in ipairs({{50, 26}, {46, 48}, {14, 50}, {54, 56}}) do
		box(p[1], NF, p[2], p[1], NF + 2, p[2], LOG)
		set(p[1] + 1, NF + 2, p[2], LOG)
	end
	for z = 18, 60 do for x = 4, 59 do
		if get(x, NF, z) == nil and get(x, NG, z) == "default:dirt_with_grass" then
			local r = rnd(14)
			if r == 0 then set(x, NF, z, "default:dry_shrub") elseif r == 1 then set(x, NF, z, "default:junglegrass") end
		end
	end end
	spawner(50, NG, 40, "wisp", 2, 10)
	spawner(16, NG, 42, "wisp", 1, 10)
end

-- The mill: a roofless stone shell
-- The mill, after the old half-timbered mills: a stone ground floor (the
-- mill works), a jettied upper floor of dark beams and white plaster (the
-- miller's rooms, up an outside stair to a balcony), a steep tiled roof with
-- a cross gable over the balcony, and a chimney. Ground floor x 24..40,
-- z 18..30; upper floor and roof one block wider all round.
local BEAM = "default:junglewood"
local PLASTER = "default:silver_sandstone"
local TILE = "stairs:stair_brick"
local PANE = "xpanes:pane_flat"
local UF = NF + 4              -- the upper floor's floor block (players stand at UF + 1)
local TOP = NF + 8             -- the top plate, where the roof begins

-- A half-timbered wall panel cell: beams at the edges and every third block,
-- plaster between
local function timber(x, y, z, along, lo, hi)
	if y == UF or y == TOP or along == lo or along == hi or (along - lo) % 3 == 0 then
		set(x, y, z, BEAM)
	else
		set(x, y, z, PLASTER)
	end
end

local function mill()
	-- the paved apron about the mill
	for z = 17, 32 do for x = 21, 45 do
		if get(x, NG, z) == "default:dirt_with_grass" then set(x, NG, z, rnd(4) == 0 and COBBLE or "default:stone_block") end
	end end
	-- the ground floor: stone, quoins of stone brick at the corners
	for z = 18, 30 do for x = 24, 40 do for y = NF, NF + 3 do
		if x == 24 or x == 40 or z == 18 or z == 30 then
			local corner = (x == 24 or x == 40) and (z == 18 or z == 30)
			set(x, y, z, corner and BRICK or (rnd(5) == 0 and MOSSY or (rnd(3) == 0 and BRICK or COBBLE)))
		end
	end end end
	air(25, NF, 19, 39, NF + 3, 29)
	box(25, NG, 19, 39, NG, 29, PLANK)
	air(31, NF, 18, 32, NF + 2, 18)                      -- the doorway, to the yard
	box(30, NF, 18, 30, NF + 3, 18, BEAM); box(33, NF, 18, 33, NF + 3, 18, BEAM); box(31, NF + 3, 18, 32, NF + 3, 18, BEAM)
	for _, x in ipairs({27, 36}) do set(x, NF + 2, 18, "xpanes:bar_flat", 0) end
	for _, z in ipairs({22, 27}) do set(40, NF + 2, z, "xpanes:bar_flat", 1) end
	-- the upper floor: its floor, jettied out a block all round, beams showing
	box(23, UF, 17, 41, UF, 31, BEAM)
	box(25, UF, 19, 39, UF, 29, PLANK)
	for x = 26, 38, 4 do box(x, UF, 19, x, UF, 29, BEAM) end
	-- its walls, half-timbered
	for y = UF + 1, TOP do
		for x = 23, 41 do timber(x, y, 17, x, 23, 41); timber(x, y, 31, x, 23, 41) end
		for z = 17, 31 do timber(23, y, z, z, 17, 31); timber(41, y, z, z, 17, 31) end
	end
	air(24, UF + 1, 18, 40, TOP, 30)
	-- windows
	for _, x in ipairs({25, 28, 34, 37}) do
		box(x, UF + 2, 17, x + 1, UF + 2, 17, PANE, 0); box(x, UF + 2, 31, x + 1, UF + 2, 31, PANE, 0)
	end
	for _, z in ipairs({19, 25, 28}) do box(23, UF + 2, z, 23, UF + 2, z + 1, PANE, 1) end
	box(41, UF + 2, 28, 41, UF + 2, 29, PANE, 1)
	-- the roof: steep, tiled, its ridge running north and south; gable ends
	-- half-timbered too
	local function main_roof(x) return x <= 32 and TOP + (x - 22) or TOP + (42 - x) end
	for x = 22, 42 do
		local y = main_roof(x)
		for z = 16, 32 do
			if x == 32 then set(x, y, z, "default:brick") else set(x, y, z, TILE, x < 32 and 1 or 3) end
		end
		if x >= 23 and x <= 41 then
			for yy = TOP + 1, y - 1 do timber(x, yy, 17, x, 23, 41); timber(x, yy, 31, x, 23, 41) end
		end
	end
	box(31, TOP + 4, 17, 33, TOP + 5, 17, PANE, 0)       -- a gable window
	-- the cross gable over the balcony, its ridge running east and west
	local function cross_roof(z) return TOP + (4 - math.abs(z - 24)) end
	for x = 34, 43 do for z = 20, 28 do
		local y = cross_roof(z)
		if y > main_roof(x) or x >= 41 then
			if x == 42 and main_roof(x) < y then set(x, main_roof(x), z, "air") end
			if z == 24 then set(x, y, z, "default:brick") else set(x, y, z, TILE, z < 24 and 0 or 2) end
			if x == 41 then for yy = TOP + 1, y - 1 do timber(41, yy, z, z, 20, 28) end end
		end
	end end
	-- the chimney, by the hearth in the north-east corner
	box(36, UF + 1, 29, 37, TOP + 9, 30, BRICK)
	box(36, UF + 1, 29, 37, UF + 2, 29, "air")
	box(36, UF, 29, 37, UF, 29, "default:coalblock")
	-- the balcony, east, on posts, and the stair down to the yard
	box(42, UF, 19, 44, UF, 23, BEAM)
	for _, p in ipairs({{44, 19}, {44, 23}, {42, 19}}) do box(p[1], NF, p[2], p[1], UF - 1, p[2], "default:fence_junglewood") end
	for x = 42, 44 do set(x, UF + 1, 19, "default:fence_junglewood") end
	for z = 19, 22 do set(44, UF + 1, z, "default:fence_junglewood") end
	set(42, UF + 1, 23, "default:fence_junglewood"); set(44, UF + 1, 23, "default:fence_junglewood")
	air(41, UF + 1, 21, 41, UF + 2, 22)                  -- the door to the miller's rooms
	for k = 0, 3 do box(43, UF - 1 - k, 24 + k, 44, UF - 1 - k, 24 + k, "stairs:stair_junglewood", 2) end
	for _, p in ipairs({{42, 20}, {43, 20}, {42, 21}, {43, 22}}) do set(p[1], NF, p[2], STRAW) end
	set(43, NF + 1, 20, STRAW)
	-- inside, below: the mill works, mosslings among the sacks, and the stair
	-- down to the cellar in the north-west corner
	box(30, NF, 23, 31, NF, 24, "default:stone_block")
	box(30, NF + 1, 23, 31, NF + 1, 24, "stairs:slab_stone")
	box(30, NF + 2, 23, 30, NF + 3, 23, BEAM)             -- the shaft up to the gears
	for _, p in ipairs({{26, 20}, {27, 20}, {26, 21}, {35, 28}, {36, 28}, {38, 20}, {38, 21}}) do set(p[1], NF, p[2], STRAW) end
	set(26, NF + 1, 20, STRAW); set(38, NF + 1, 20, STRAW)
	box(25, NF + 3, 19, 39, NF + 3, 19, BEAM); box(25, NF + 3, 29, 39, NF + 3, 29, BEAM)
	for _, p in ipairs({{29, 19, "-z"}, {35, 19, "-z"}, {29, 29, "+z"}, {35, 29, "+z"}, {39, 24, "+x"}}) do
		set(p[1], NF + 2, p[2], "default:torch_wall", SIGN_P2[p[3]])
	end
	spawner(28, NG, 26, "mossling", 2, 6)
	-- upstairs: the miller's rooms
	box(25, UF + 1, 19, 27, UF + 1, 20, "wool:red")
	set(24, UF + 1, 24, PLANK); set(24, UF + 1, 25, PLANK)
	sign(24, UF + 2, 24, "-x", "THE MILLER'S DIARY\nThey want the cellar and the river under it. I said no. " ..
		"Tonight there were lights again, and a man in a red coat at the door, and")
	chest(38, UF + 1, 18, "common", 2)
	set(41, UF + 2, 26, "orthoverse_props:windlass", 1)
	for _, p in ipairs({{32, 18, "-z"}, {32, 30, "+z"}, {40, 25, "+x"}}) do
		set(p[1], UF + 3, p[2], "default:torch_wall", SIGN_P2[p[3]])
	end
	-- the stair down to the cellar, in the north-west corner
	for k = 1, 6 do
		box(25, NG - k, 28 - k, 26, NG - k, 28 - k, PLANK)
		air(25, NG - k + 1, 28 - k, 26, NG, 28 - k)
	end
	air(25, NG, 28, 26, NG, 28)
end

-- The cellar: the bone pit, the secret shelf, the sluice gate
local function cellar()
	box(24, CEL, 18, 40, NG - 1, 30, BRICK)
	air(25, CEL + 1, 19, 39, NG - 2, 29)
	box(25, CEL, 19, 39, CEL, 29, COBBLE)
	-- (the stair from the mill comes down in the north-west corner)
	for k = 1, 6 do
		box(25, NG - k, 28 - k, 26, NG - k, 28 - k, PLANK)
		air(25, NG - k + 1, 28 - k, 26, NG, 28 - k)
	end
	-- the bone pit
	box(30, CEL - 1, 22, 35, CEL - 1, 26, "default:gravel")
	air(30, CEL, 22, 35, CEL, 26)
	for _, p in ipairs({{31, 23}, {34, 25}, {32, 26}, {30, 24}}) do set(p[1], CEL, p[2], "bones:bones") end
	spawner(33, CEL - 1, 24, "skeleton", 2, 6)
	spawner(37, CEL, 27, "masked", 2, 6)
	sign(39, CEL + 2, 23, "+x", "Scratched on the wall: THE BONES ARE PAINTED")
	chest(38, CEL + 1, 20, "common", 1)
	for _, z in ipairs({20, 28}) do set(32, NG - 1, z, LAMP) end
	-- the north wall: bookshelves, two of them secret, and the loose brick
	for x = 28, 35 do box(x, CEL + 1, 30, x, CEL + 2, 30, "default:bookshelf", 0) end
	box(31, CEL + 1, 30, 32, CEL + 2, 30, "orthoverse_props:secret_shelf", 0)
	set(36, CEL + 2, 30, "orthoverse_props:loose_brick", 0)
	-- the third windlass, and the sluice gate in the west wall
	set(24, CEL + 2, 26, "orthoverse_props:windlass", 3)
	box(24, CEL + 1, 21, 24, CEL + 3, 22, "orthoverse_props:sluice_gate", 3)
end

-- The smugglers' run, the river, the landing
local function river()
	tunnel({{31, CEL, 31}, {31, CEL, 34}, {31, LOW, 45}, {39, LOW, 45}})
	-- the jetty, the river (two deep), its cavern, the landing
	box(40, LOW, 42, 48, LOW, 45, PLANK)
	air(40, LOW + 1, 42, 48, LOW + 5, 45)
	box(42, LOW - 2, 46, 46, LOW - 2, 59, "default:gravel")
	box(42, LOW - 1, 46, 46, LOW, 59, WATER)
	air(42, LOW + 1, 46, 46, LOW + 6, 59)
	box(40, LOW, 60, 48, LOW, 62, PLANK)
	air(40, LOW + 1, 60, 48, LOW + 5, 62)
	for _, z in ipairs({44, 50, 56, 61}) do set(44, LOW + 6, z, LAMP) end
	set(44, LOW + 1, 45, "orthoverse_props:mooring")
	sign(40, LOW + 2, 43, "-x", "Chalked on the rock: BOAT DOWNSTREAM. MIND THE LIGHTS.")
	-- the lookout ledge over the river, west wall
	box(40, LOW + 3, 51, 41, LOW + 3, 53, PLANK)
	air(40, LOW + 4, 51, 41, LOW + 6, 53)
	spawner(40, LOW + 3, 52, "wisp", 2, 9, true)
	-- from the landing west to the hall
	tunnel({{40, LOW, 60}, {35, LOW, 60}}, PLANK)
end

-- The smugglers' hall, and the Ringmaster's office
local function hall()
	box(6, LOW, 48, 34, LOW, 61, PLANK)
	air(6, LOW + 1, 48, 34, LOW + 5, 61)
	for z = 50, 60, 5 do for x = 9, 33, 6 do set(x, LOW + 6, z, LAMP) end end
	-- contraband
	for _, p in ipairs({{20, 49}, {21, 49}, {20, 50}, {28, 60}, {29, 60}, {29, 59}, {24, 55}}) do set(p[1], LOW + 1, p[2], STRAW) end
	set(20, LOW + 2, 49, STRAW)
	for _, p in ipairs({{31, 49}, {32, 49}, {26, 49}}) do set(p[1], LOW + 1, p[2], LOG) end
	spawner(22, LOW, 56, "kobold", 3, 8)
	spawner(28, LOW, 52, "goblin", 3, 8)
	chest(33, LOW + 1, 52, "common", 1)
	chest(17, LOW + 1, 49, "weapon", 2)
	-- the office: a plank wall, a door
	box(16, LOW + 1, 48, 16, LOW + 4, 61, PLANK)
	air(16, LOW + 1, 54, 16, LOW + 2, 55)
	box(7, LOW + 1, 58, 9, LOW + 1, 60, PLANK)                   -- the desk
	set(g.finish.x, g.finish.y, g.finish.z, "orthoverse_props:ledger", 0)
	chest(11, LOW + 1, 61, "finish", 0)
	spawner(10, LOW, 54, "ringmaster", 1, 8)
	spawner(13, LOW, 50, "goblin", 2, 8)
	sign(6, LOW + 2, 52, "-x", "THE MILLER\nChained to the wall, thin as a rake. \"The ledger,\" he whispers. " ..
		"\"Take the ledger to the reeve, and they hang, every one.\"")
	-- the culvert: from the cellar's sluice gate down to the hall
	tunnel({{23, CEL, 21}, {18, CEL, 21}, {18, LOW, 33}, {18, LOW, 47}})
end

------------------------------------------------------------------------------

-- A plan below the ground, north at the top: "~" water, "1" the cellar's
-- level, "2" the river's and the hall's, "#" solid
function g.plan()
	local rows = {}
	for z = SZ - 1, 0, -1 do
		local row = {}
		for x = 0, SX - 1 do
			local ch = "#"
			if get(x, LOW, z) == WATER then ch = "~"
			elseif get(x, CEL + 2, z) == "air" then ch = "1"
			elseif get(x, LOW + 2, z) == "air" then ch = "2" end
			row[#row + 1] = ch
		end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, "\n")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.spawners, g.chests, g.signs = {}, {}, {}
	seed = 777
	ground()
	hamlet()
	yard()
	cellar()
	mill()
	river()
	hall()
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
	for name in pairs(missing) do core.log("error", "[mill] no such node: " .. name) end
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
