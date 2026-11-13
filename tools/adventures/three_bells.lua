-- The Three Bells: builds the ready-made adventure in a world, so that it can
-- be saved as adventures/three-bells.we (see tools/adventures/README.md).
--
--   local tb = dofile(".../tools/adventures/three_bells.lua")
--   tb.build(origin)        -- origin: the south-west bottom corner
--   tb.info                 -- what goes in adventures/three-bells.json
--
-- Coordinates below are relative to the origin: x east, z north, y up. The
-- ground layer is y = 8 (players stand at y = 9); the crypt is below it.
--
--   Courtyard (outside the dungeon): gate, board, the way in.
--   Hub: the start; west to the Grate, east to the Library, stairs down to the
--     crypt, north to the tower.
--   West wing: the Grate -> the Stepping Stones -> the Sunken Lever -> the
--     iron bell's rope.
--   East wing: the Library -> the Dark Maze -> the Ceiling -> the bronze
--     bell's rope.
--   Crypt: the Four Levers -> the Two Plates -> the silver bell's rope.
--   Tower: three steel doors, each opened by one bell's rope, then a stair up
--     to the belfry and the finish.
--
-- All wiring runs under walls and floors. Mesecons links used: a wall lever
-- powers the node under the block it hangs on; a wire there climbs to a door
-- standing diagonally above it; a pressure plate powers the nodes diagonally
-- below it; a Mesecons torch is off while the node two behind it is powered.

local tb = {}

local SX, SY, SZ = 60, 47, 42
local G, F = 8, 9           -- ground layer, standing height
local CF, CS = 1, 2         -- crypt floor, crypt standing height

local WALL = "default:stonebrick"
local FLOOR = "default:stone_block"
local TOWER = "default:sandstonebrick"
local ROOF = "default:wood"
local STONE = "default:stone"
local LAMP = "default:meselamp"
local BARS = "xpanes:bar_flat"
local FENCE = "default:fence_wood"
local WIRE = "mesecons:wire_00000000_off"
local VWIRE = "mesecons_extrawires:vertical_off"
local LEVER = "mesecons_walllever:wall_lever_off"
local PLATE = "mesecons_pressureplates:pressure_plate_stone_off"
local TORCH = "mesecons_torch:mesecon_torch_on"
local DOOR = "doors:door_steel_a"
local SIGN = "default:sign_wall_wood"
local OWNER = "the founder"  -- no player can have this name, so only the wiring opens the doors

tb.info = {
	name = "The Three Bells",
	line = "A mad bellfounder hid three bells in his tower. Each room is a trap he built for thieves.",
	limit = 60,
	rank_min = 1, rank_max = 20,   -- puzzles only: every rank
	size = {x = SX, y = SY, z = SZ},
	ground = G,
	dig = {
		{min = {x = 13, y = 0, z = 12}, max = {x = 45, y = 7, z = 39}},   -- the crypt
		{min = {x = 2, y = 2, z = 11}, max = {x = 12, y = 7, z = 31}},    -- the pit and the well
		{min = {x = 45, y = 4, z = 21}, max = {x = 57, y = 7, z = 31}},   -- under the Ceiling
	},
	corner1 = {x = 2, y = 0, z = 11},
	corner2 = {x = 57, y = SY - 1, z = 39},
	start = {x = 29.5, y = F, z = 13.5},
	arrival = {x = 29.5, y = F, z = 4.5},
}

-- Where the doors and levers are, for tests
tb.doors = {
	grate = {x = 12, y = F, z = 16}, library = {x = 47, y = F, z = 16}, levers = {x = 25, y = CS, z = 27},
	iron = {x = 24, y = F, z = 28}, bronze = {x = 35, y = F, z = 28}, silver = {x = 29, y = F, z = 35},
	well = {x = 12, y = F, z = 28}, ceiling = {x = 47, y = F, z = 28}, plates = {x = 25, y = CS, z = 34},
}
tb.levers = {
	library = {x = 42, y = F, z = 19}, decoys = {{x = 38, y = F, z = 19}, {x = 40, y = F, z = 19}, {x = 45, y = F, z = 13}},
	combination = {{x = 34, y = CS, z = 23}, {x = 34, y = CS, z = 25}, {x = 34, y = CS, z = 27}, {x = 34, y = CS, z = 29}},
	iron = {x = 22, y = F, z = 28}, bronze = {x = 37, y = F, z = 28}, silver = {x = 29, y = CS, z = 35},
	well = {x = 7, y = 4, z = 28},
	ceiling = {{x = 50, y = F, z = 30}, {x = 52, y = F, z = 30}, {x = 54, y = F, z = 30}, {x = 56, y = F, z = 30}},
}
tb.two_plates = {{x = 17, y = CS, z = 20}, {x = 22, y = CS, z = 20}}
tb.plates = {{x = 16, y = F, z = 22}, {x = 18, y = F, z = 23}}
tb.finish = {x = 29, y = 33, z = 30}

------------------------------------------------------------------------------
-- A grid of the whole template, written in one go

local grid, p2grid, metas, special

local function idx(x, y, z) return x + y * SX + z * SX * SY + 1 end

local function set(x, y, z, name, param2)
	assert(x >= 0 and x < SX and y >= 0 and y < SY and z >= 0 and z < SZ, ("outside: %d,%d,%d"):format(x, y, z))
	local i = idx(x, y, z)
	grid[i] = name
	p2grid[i] = param2 or 0
end

local function box(x1, y1, z1, x2, y2, z2, name, param2)
	for z = z1, z2 do for y = y1, y2 do for x = x1, x2 do set(x, y, z, name, param2) end end end
end

local function air(x1, y1, z1, x2, y2, z2) box(x1, y1, z1, x2, y2, z2, "air") end

-- A room's inside: floor at fy, air above for h, lamps in the ceiling
local function room(x1, z1, x2, z2, fy, h, floor, lamps)
	box(x1, fy, z1, x2, fy, z2, floor or FLOOR)
	air(x1, fy + 1, z1, x2, fy + h, z2)
	if lamps ~= false then
		for z = z1 + 1, z2 - 1, 4 do for x = x1 + 1, x2 - 1, 4 do set(x, fy + h + 1, z, LAMP) end end
	end
end

local function opening(x1, y1, z1, x2, y2, z2, floor_y)
	air(x1, y1, z1, x2, y2, z2)
	if floor_y then box(x1, floor_y, z1, x2, floor_y, z2, FLOOR) end
end

local function mark(x, y, z) special[#special + 1] = {x = x, y = y, z = z} end

local function wire(x, y, z) set(x, y, z, WIRE); mark(x, y, z) end

local function wires(list) for _, p in ipairs(list) do wire(p[1], p[2], p[3]) end end

-- A steel door that only the wiring opens (param2: 0/2 in a wall along x,
-- 1/3 in a wall along z)
local function door(x, y, z, param2)
	set(x, y, z, DOOR, param2)
	set(x, y + 1, z, "doors:hidden", param2)
	metas[#metas + 1] = {x = x, y = y, z = z, fields = {owner = OWNER,
		infotext = "A steel door, worked by the founder's mechanisms"}, construct = true}
	mark(x, y, z)
end

-- A wall lever; dir: which way the wall it hangs on is
local LEVER_P2 = {["+z"] = 0, ["+x"] = 1, ["-z"] = 2, ["-x"] = 3}
local function lever(x, y, z, dir) set(x, y, z, LEVER, LEVER_P2[dir]); mark(x, y, z) end

-- A wall sign; dir: which way the wall it hangs on is
local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}
local function sign(x, y, z, dir, text)
	set(x, y, z, SIGN, SIGN_P2[dir])
	metas[#metas + 1] = {x = x, y = y, z = z, fields = {text = text, infotext = '"' .. text .. '"'}, construct = true}
end

------------------------------------------------------------------------------
-- The parts

local function ground_and_courtyard()
	box(0, G, 0, SX - 1, G, SZ - 1, "default:dirt_with_grass")
	-- The courtyard, outside the dungeon area
	box(20, G, 1, 39, G, 10, "default:cobble")
	box(19, F, 0, 19, F + 1, 10, WALL)
	box(40, F, 0, 40, F + 1, 10, WALL)
	box(19, F, 0, 40, F + 1, 0, WALL)
	air(28, F, 0, 31, F + 1, 0)
	box(28, G, 0, 31, G, 0, "default:cobble")
	for _, p in ipairs({{20, 2}, {39, 2}, {20, 9}, {39, 9}}) do set(p[1], F, p[2], "default:mese_post_light") end
	set(29, F, 8, "orthoverse_adventure:gate", 0)
	set(26, F, 10, "orthoverse_adventure:board", 0)
	sign(33, F + 1, 10, "+z", "THE THREE BELLS\nA mad bellfounder hid three bells in his tower. " ..
		"Each room is a trap he built for thieves.\nRight-click the gate to go in.")
end

local function massing()
	-- One block of masonry for the ground floor, rooms carved out of it
	box(2, G, 11, 57, 14, 32, WALL)
	for x = 2, 57, 2 do set(x, 15, 11, WALL); set(x, 15, 32, WALL) end
	for z = 11, 32, 2 do set(2, 15, z, WALL); set(57, 15, z, WALL) end
	-- The rock the crypt, the pit, the well and the Ceiling's wiring are cut
	-- from (dug out when placed)
	for _, d in ipairs(tb.info.dig) do box(d.min.x, d.min.y, d.min.z, d.max.x, d.max.y, d.max.z, STONE) end
end

local function ground_floor()
	room(25, 12, 34, 21, G, 5)                   -- hub
	room(13, 12, 21, 20, G, 5)                   -- W1: the Grate
	room(3, 12, 11, 20, G, 5)                    -- W2: the Stepping Stones
	room(3, 22, 11, 30, G, 5)                    -- W3: the Sunken Lever
	room(13, 25, 22, 31, G, 5)                   -- the iron bell's rope
	room(38, 12, 46, 20, G, 5)                   -- E1: the Library
	room(48, 12, 56, 20, G, 5, FLOOR, false)     -- E2: the Dark Maze
	room(48, 22, 56, 30, G, 5)                   -- E3: the Ceiling
	room(37, 25, 46, 31, G, 5)                   -- the bronze bell's rope
	opening(22, F, 16, 24, F + 2, 17, G)         -- hub to the Grate
	opening(35, F, 16, 37, F + 2, 17, G)         -- hub to the Library
	opening(29, F, 22, 30, F + 2, 23, G)         -- hub to the tower
	box(28, F, 11, 31, F + 2, 11, BARS, 0)       -- the barred way in from the courtyard
	sign(27, F + 1, 21, "+z", "Three doors bar the founder's tower. Ring his bells to open them: " ..
		"the iron bell (west), the bronze bell (east) and the silver bell (below).")
end

-- W1: a slot in the north wall too low to climb through; beyond it six
-- pressure plates. Something thrown through (a pebble from the pile) opens the
-- door to W2 while it lies there.
local function grate()
	-- The slot: three wide, a half slab and a block high, so a pebble fits
	-- through but a player (1.77 tall) does not
	box(16, F, 21, 18, F, 21, "stairs:slab_stonebrick", 0)
	air(16, F + 1, 21, 18, F + 1, 21)
	air(16, F, 22, 18, F + 1, 23)                     -- the alcove beyond
	for z = 22, 23 do
		for x = 16, 18 do
			set(x, F, z, PLATE); mark(x, F, z)
			wire(x, G, z)                             -- under the plates
		end
	end
	wires({{16, G, 21}, {15, G, 21}, {14, G, 21}, {13, G, 21}, {12, G, 21},
		{12, G, 20}, {12, G, 19}, {12, G, 18}, {12, G, 17}})
	door(12, F, 16, 1)
	set(14, F, 19, "orthoverse_adventure:pebbles")
	sign(19, F + 1, 20, "+z", "THE FOUNDER'S GRATE\nMy door opens while something weighs on the floor beyond the slot. " ..
		"(Stand right at the slot, look straight through it and throw with the drop key.)")
end

-- E1: bookshelves along two walls; one of four levers among them works, the
-- one under the gold block.
local function library()
	box(38, F, 20, 46, F + 2, 20, "default:bookshelf")
	box(46, F, 12, 46, F + 2, 14, "default:bookshelf")
	box(46, F, 18, 46, F + 2, 19, "default:bookshelf")
	set(42, F + 2, 20, "default:goldblock")
	lever(42, F, 19, "+z")
	lever(38, F, 19, "+z")
	lever(40, F, 19, "+z")
	lever(45, F, 13, "+x")
	wires({{42, G, 20}, {43, G, 20}, {44, G, 20}, {45, G, 20}, {46, G, 20}, {46, G, 19}, {46, G, 18},
		{47, G, 18}, {47, G, 17}})
	door(47, F, 16, 1)
	sign(38, F + 1, 13, "-x", "THE FOUNDER'S LIBRARY\nMy own book lies beneath my golden name.")
end

local function crypt()
	room(26, 22, 34, 29, CF, 5)                  -- C1: the Four Levers
	room(26, 32, 32, 35, CF, 5)                  -- the silver bell's rope
	room(16, 22, 24, 35, CF, 5)                  -- (C2: the Two Plates)
	-- Stairs down from the hub's north-east corner
	for k = 0, 6 do
		local z = 14 + k
		air(33, G - k, z, 34, G, z)
		box(33, G - 1 - k, z, 34, G - 1 - k, z, "stairs:stair_stonebrick", 2)
	end
	room(33, 21, 34, 21, CF, 5, FLOOR, false)        -- through C1's south wall
	for z = 14, 20 do set(32, F, z, FENCE) end
	set(33, F, 21, FENCE); set(34, F, 21, FENCE)
end

-- C1: four levers on the east wall open the door to C2 only when set high,
-- low, high, low. Behind the wall: levers 2 and 4 power a bus; levers 1 and 3
-- each switch off a torch that otherwise powers it; a last torch, reading the
-- bus, powers the door when the bus is off.
local function four_levers()
	local zs = {23, 25, 27, 29}
	for i, z in ipairs(zs) do
		lever(34, CS, z, "+x")
		if i % 2 == 1 then
			wires({{35, CF, z}, {36, CF, z}})
			set(38, CF, z, TORCH, 3); mark(38, CF, z)  -- on while this lever is low
		else
			wires({{35, CF, z}, {36, CF, z}, {37, CF, z}, {38, CF, z}})
		end
	end
	for z = 23, 31 do wire(39, CF, z) end              -- the bus
	set(37, CF, 31, TORCH, 2); mark(37, CF, 31)       -- on while the bus is off
	for x = 25, 36 do wire(x, CF, 31) end              -- to the door, under the walls
	wires({{25, CF, 30}, {25, CF, 29}, {25, CF, 28}})
	door(25, CS, 27, 1)
	sign(34, CS + 2, 26, "+x", "THE FOUR LEVERS\nHigh, low, high, low: so rang my bells.")
end

-- W2: a pit of water across the room, with stepping stones rising from it
-- to a way out high in the north wall. Who falls in climbs the ladder back
-- to the start.
local function stepping_stones()
	air(3, 4, 12, 11, G, 20)                          -- the pit, down to y = 3
	box(3, 4, 12, 11, 5, 20, "default:water_source")
	box(10, 4, 15, 11, G, 17, WALL)                   -- where you come in
	box(10, 5, 14, 10, G, 14, "default:ladder_wood", 4)
	-- each top: level with the last or one higher, a block's gap between
	for _, p in ipairs({{8, 16, 8}, {6, 16, 9}, {4, 16, 9}, {4, 18, 10}, {4, 20, 10}}) do
		box(p[1], 4, p[2], p[1], p[3], p[2], WALL)
	end
	air(4, 11, 21, 4, 12, 21)                         -- the way out, into W3
	set(4, 10, 22, WALL); set(4, 9, 23, WALL)
	sign(11, F + 1, 18, "+x", "THE STEPPING STONES\nMind the gaps.")
end

-- W3: a well in the floor; the lever that opens the door to the iron bell's
-- rope is at the bottom of it.
local function sunken_lever()
	air(5, 4, 24, 9, G, 28)
	box(5, 4, 24, 9, G, 28, "default:water_source")
	lever(7, 4, 28, "+z")
	-- up through the rock and under the wall, one block up per step
	wires({{7, 3, 29}, {8, 4, 29}, {9, 5, 29}, {10, 6, 29}, {11, 7, 29}, {12, G, 29}})
	door(12, F, 28, 1)
	sign(3, F + 1, 26, "-x", "THE SUNKEN LEVER\nI dropped my key down the well. Fetch it if you can hold your breath.")
end

-- E2: a maze of high walls in the dark (no lamps), from the Library's door
-- to a way out in the far corner.
local function dark_maze()
	box(48, F, 12, 56, F + 2, 20, "default:mossycobble")
	-- cells on even offsets (5 x 5), passages carved by a seeded walk
	local seed = 7
	local function rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
	local seen = {}
	local function carve(i, j)
		seen[i .. ":" .. j] = true
		air(48 + i, F, 12 + j, 48 + i, F + 2, 12 + j)
		local dirs = {{2, 0}, {-2, 0}, {0, 2}, {0, -2}}
		for k = 4, 2, -1 do local r = rand(k); dirs[k], dirs[r] = dirs[r], dirs[k] end
		for _, d in ipairs(dirs) do
			local ni, nj = i + d[1], j + d[2]
			if ni >= 0 and ni <= 8 and nj >= 0 and nj <= 8 and not seen[ni .. ":" .. nj] then
				air(48 + i + d[1] / 2, F, 12 + j + d[2] / 2, 48 + i + d[1] / 2, F + 2, 12 + j + d[2] / 2)
				carve(ni, nj)
			end
		end
	end
	carve(0, 4)
	-- a few fireflies for a faint glow here and there
	for _, c in ipairs({{2, 0}, {8, 2}, {4, 6}, {0, 8}, {6, 4}}) do set(48 + c[1], F + 1, 12 + c[2], "fireflies:firefly") end
	air(56, F, 21, 56, F + 1, 21)                    -- the way out, into E3
	sign(46, F + 1, 15, "+x", "Beyond this door: THE DARK MAZE\nKeep a hand on the wall.")
end

-- E3: four levers on the north wall open the door to the bronze bell's rope
-- when set as the ceiling shows: gold for high, obsidian for low. The logic
-- (as in the Four Levers) lies in the rock under the floor.
local function ceiling()
	local pattern = {false, true, true, false}
	for i, x in ipairs({50, 52, 54, 56}) do
		lever(x, F, 30, "+z")
		wire(x, G, 31)                                -- under the wall
		set(x, 14, 29, pattern[i] and "default:goldblock" or "default:obsidian")
		if pattern[i] then
			wires({{x, 7, 30}, {x, 7, 29}})
			set(x, 7, 27, TORCH, 4); mark(x, 7, 27)  -- on while this lever is low
		else
			wires({{x, 7, 30}, {x, 7, 29}, {x, 7, 28}, {x, 7, 27}})
		end
	end
	for x = 49, 56 do wire(x, 7, 26) end               -- the bus
	set(47, 7, 26, TORCH, 2); mark(47, 7, 26)         -- on while the bus is off
	wires({{46, 7, 26}, {46, 7, 27}, {46, 7, 28}, {46, 7, 29}, {47, G, 29}})
	door(47, F, 28, 1)
	sign(48, F + 1, 24, "-x", "THE CEILING\nAs above, so below.")
end

-- C2: two pressure plates behind two slots in the south wall; the door to
-- the silver bell's rope opens only while both bear weight (two pebbles).
-- The logic lies in the rock south of the room.
local function two_plates()
	for _, x0 in ipairs({17, 22}) do
		box(x0, CS, 21, x0 + 1, CS, 21, "stairs:slab_stonebrick", 0)
		air(x0, CS + 1, 21, x0 + 1, CS + 1, 21)
		air(x0, CS, 19, x0 + 1, CS + 1, 20)
		for z = 19, 20 do
			for x = x0, x0 + 1 do
				set(x, CS, z, PLATE); mark(x, CS, z)
				wire(x, CF, z)
			end
		end
	end
	set(17, CF, 17, TORCH, 4); mark(17, CF, 17)       -- on while plate A is bare
	set(23, CF, 17, TORCH, 4); mark(23, CF, 17)       -- on while plate B is bare
	for x = 16, 23 do wire(x, CF, 16) end              -- the bus
	set(14, CF, 16, TORCH, 2); mark(14, CF, 16)       -- on while the bus is off
	for z = 16, 36 do wire(13, CF, z) end              -- round to the door, through the rock
	for x = 14, 25 do wire(x, CF, 36) end
	wire(25, CF, 35)
	door(25, CS, 34, 1)
	set(16, CS, 24, "orthoverse_adventure:pebbles")
	sign(16, CS + 1, 26, "-x", "THE TWO PLATES\nBoth must bear weight at once.")
end

local function tower()
	box(23, G, 23, 36, 39, 36, TOWER)
	-- Ground floor: a ring round a core, with crosswalls and the three doors
	room(24, 24, 35, 35, G, 5, FLOOR, false)
	box(26, F, 26, 33, 31, 33, TOWER)                 -- the core
	air(27, F, 27, 32, 31, 32)
	box(28, F, 28, 31, 31, 31, TOWER)                 -- the pillar the stair winds round
	box(31, F, 24, 31, F + 4, 25, TOWER)              -- go round by the west
	box(24, F, 28, 25, F + 4, 28, TOWER); door(24, F, 28, 0)
	box(29, F, 34, 29, F + 4, 35, TOWER); door(29, F, 35, 1)
	box(34, F, 28, 35, F + 4, 28, TOWER); door(35, F, 28, 0)
	air(32, F, 26, 32, F + 1, 26)                     -- into the core
	opening(29, F, 23, 30, F + 2, 23, G)              -- from the hub
	for _, p in ipairs({{24, 30}, {28, 24}, {35, 32}, {28, 35}}) do set(p[1], F + 5, p[2], LAMP) end
	-- The stair: round the pillar, one block up per step, to the belfry
	local cells = {}
	for z = 27, 32 do cells[#cells + 1] = {32, z, 0} end
	for x = 31, 27, -1 do cells[#cells + 1] = {x, 32, 3} end
	for z = 31, 27, -1 do cells[#cells + 1] = {27, z, 2} end
	for x = 28, 31 do cells[#cells + 1] = {x, 27, 1} end
	-- The pillar's face beside every fourth step (but at a corner) holds a
	-- lamp: the stair is shut in, and was pitch dark
	local function inner(c)
		if c[1] == 32 and c[2] >= 28 and c[2] <= 31 then return 31, c[2] end
		if c[1] == 27 and c[2] >= 28 and c[2] <= 31 then return 28, c[2] end
		if c[2] == 32 and c[1] >= 28 and c[1] <= 31 then return c[1], 31 end
		if c[2] == 27 and c[1] >= 28 and c[1] <= 31 then return c[1], 28 end
	end
	local lamps = {}
	for j = 1, 24 do
		local c = cells[(j % #cells) + 1]
		local y = G + j
		set(c[1], y, c[2], "stairs:stair_sandstonebrick", c[3])
		if j < #cells then box(c[1], F, c[2], c[1], y - 1, c[2], TOWER) end
		local ix, iz = inner(c)
		if ix and j % 4 == 0 and y + 1 <= 31 then lamps[#lamps + 1] = {ix, y + 1, iz} end
	end
	for _, l in ipairs(lamps) do set(l[1], l[2], l[3], LAMP) end
	-- The belfry. Its floor took the stair's last step, leaving a full block
	-- to jump at the top, in the dark: the step is put back, flush with the
	-- floor (32, 32, 31). The two squares before it are open (headroom for
	-- the steps below them), fenced at their sides.
	room(24, 24, 35, 35, 32, 6, TOWER, false)
	set(32, 32, 31, "stairs:stair_sandstonebrick", 0)
	for z = 29, 30 do set(32, 32, z, "air"); set(31, 33, z, FENCE); set(33, 33, z, FENCE) end
	set(32, 33, 28, FENCE)
	for _, a in ipairs({26, 32}) do
		box(a, 34, 23, a + 1, 37, 23, BARS, 0); box(a, 34, 36, a + 1, 37, 36, BARS, 0)
		box(23, 34, a, 23, 37, a + 1, BARS, 1); box(36, 34, a, 36, 37, a + 1, BARS, 1)
	end
	for _, b in ipairs({{26, 26}, {33, 33}, {26, 33}}) do
		set(b[1], 35, b[2], "default:goldblock")
		box(b[1], 36, b[2], b[1], 38, b[2], FENCE)
	end
	for _, p in ipairs({{29, 29}, {30, 30}, {25, 25}, {34, 34}, {25, 34}, {34, 25}}) do set(p[1], 39, p[2], LAMP) end
	set(tb.finish.x, tb.finish.y, tb.finish.z, "orthoverse_adventure:finish")
	sign(29, 34, 35, "+z", "The founder's three bells. Touch the finish to complete the adventure.")
	for k = 0, 6 do box(23 + k, 40 + k, 23 + k, 36 - k, 40 + k, 36 - k, ROOF) end
end

-- The ropes: a lever beside each tower door's wall, one wire under the wall
local function ropes()
	lever(22, F, 28, "+x"); wire(23, G, 28)
	sign(22, F + 2, 26, "+x", "THE IRON BELL\nPull its rope.")
	lever(37, F, 28, "-x"); wire(36, G, 28)
	sign(37, F + 2, 30, "-x", "THE BRONZE BELL\nPull its rope.")
	-- The silver bell's rope climbs from the crypt through the wall to the
	-- tower floor
	lever(29, CS, 35, "+z"); wire(29, CF, 36)
	for y = CF, G do set(28, y, 36, VWIRE); mark(28, y, 36) end
	wire(29, G, 36)
	sign(31, CS + 1, 35, "+z", "THE SILVER BELL\nPull its rope.")
end

------------------------------------------------------------------------------

function tb.build(origin)
	grid, p2grid, metas, special = {}, {}, {}, {}
	ground_and_courtyard()
	massing()
	ground_floor()
	grate()
	library()
	crypt()
	four_levers()
	stepping_stones()
	sunken_lever()
	dark_maze()
	ceiling()
	two_plates()
	tower()
	ropes()
	-- Write the grid
	local p1 = vector.new(origin)
	local p2 = vector.add(p1, vector.new(SX - 1, SY - 1, SZ - 1))
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(p1, p2)
	local va = VoxelArea(e1, e2)
	local data, p2data = vm:get_data(), vm:get_param2_data()
	local cids, missing = {}, {}
	for z = 0, SZ - 1 do for y = 0, SY - 1 do for x = 0, SX - 1 do
		local i = idx(x, y, z)
		local name = grid[i] or "air"
		if not cids[name] then
			if not core.registered_nodes[name] then missing[name] = true; name = "air" end
			cids[name] = core.get_content_id(name)
			cids[grid[i] or "air"] = cids[name]
		end
		local vi = va:index(p1.x + x, p1.y + y, p1.z + z)
		data[vi] = cids[grid[i] or "air"]
		p2data[vi] = p2grid[i] or 0
	end end end
	vm:set_data(data)
	vm:set_param2_data(p2data)
	vm:write_to_map(true)
	for name in pairs(missing) do core.log("error", "[three_bells] no such node: " .. name) end
	-- Metadata (signs and doors set up as when placed)
	for _, m in ipairs(metas) do
		local pos = vector.add(p1, m)
		local node = core.get_node(pos)
		local def = core.registered_nodes[node.name]
		if m.construct and def and def.on_construct then def.on_construct(pos) end
		local meta = core.get_meta(pos)
		for k, v in pairs(m.fields) do meta:set_string(k, v) end
	end
	-- Mesecons: connect the wires, then let every part settle
	for _, s in ipairs(special) do
		local pos = vector.add(p1, s)
		local name = core.get_node(pos).name
		local def = core.registered_nodes[name]
		-- Vertical wires pick their top and bottom pieces; pressure plates
		-- start the timer they check with
		if def and def.after_place_node and name:find("vertical") then def.after_place_node(pos) end
		if def and def.on_construct and name:find("pressure_plate") then def.on_construct(pos) end
	end
	for pass = 1, 2 do
		for _, s in ipairs(special) do
			local pos = vector.add(p1, s)
			mesecon.on_placenode(pos, core.get_node(pos))
		end
	end
	return missing
end

return tb
