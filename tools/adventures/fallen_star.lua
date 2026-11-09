-- The Fallen Star: builds the ready-made adventure in a world, so that it can
-- be saved as adventures/fallen_star.we (see tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/fallen_star.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/fallen_star.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 26 (players stand at y = 27): nothing rises more than four
-- blocks above it. A ship from the futuristic realm lies buried in it.
--
--   The salvagers' camp (on the ground, outside the dungeon), south: the
--     gate, the board, the arrival point, and what they have seen.
--   The crater, behind it: stepping back a block every four (too high to
--     climb), under a low glass dome. The ship's torn hull opens off its
--     floor.
--   The upper deck (floor y 18):
--     the cargo hold (the start): crates, scrap drones, a loot locker;
--     the crew corridor, with three cabins each side: crew cabins and the
--       captain's (card lockers: one of the four, chosen each run, holds the
--       blue keycard), the medbay (a medical station), the security office;
--     a loose panel in a cabin wall: the old maintenance duct, down a ladder
--       into the armoury (the secret way).
--   A stair down from the corridor's end into engineering (floor y 12): the
--     live floor, and three relays, west, east and south. Throw all three and
--     the blast door to the lower passage opens (and the floor goes dead).
--   The lower passage: the armoury (blue door: a weapon locker, the red
--     keycard), and the reactor (red door).
--   The reactor room (floor y 2): a catwalk round the walls and a stair down,
--     three glowing reactor cores, two sentry turrets on ledges, the Warden,
--     and the black box (the finish) on its plinth, the finish locker beside.
--
-- Party of one to four, ranks 3 to 7.

local g = {}

local SX, SY, SZ = 64, 31, 64
local NG, NF = 26, 27       -- the land's ground, and where players stand on it
local L1, L2, L3 = 18, 12, 2  -- the decks' floors

local ROCK = "default:stone"
local HULL = "orthoverse_scifi:hull"
local SCORCH = "orthoverse_scifi:hull_scorched"
local DECK = "orthoverse_scifi:deck"
local LIGHT = "orthoverse_scifi:panel_light"
local CRATE = "orthoverse_scifi:crate"
local CONSOLE = "orthoverse_scifi:console"
local REACTOR = "orthoverse_scifi:reactor"
local GLASS = "orthoverse_scifi:glass"
local LOOSE = "orthoverse_scifi:loose_panel"
local BARS = "xpanes:bar"
local SIGN = "default:sign_wall_steel"
local SPAWNER = "orthoverse_monsters:spawner"
local LOOT = "orthoverse_loot:locker"
local CARD_LOCKER = "orthoverse_scifi:locker"

g.info = {
	name = "The Fallen Star",
	line = "A ship from the futuristic realm came down in the hills. Its machines are still running.",
	limit = 60,
	rank_min = 3, rank_max = 7,
	size = {x = SX, y = SY, z = SZ},
	ground = NG,
	-- everything below the ground is the template's: cleared first
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 2, y = 0, z = 8},
	corner2 = {x = 61, y = NG, z = 62},
	start = {x = 32.5, y = L1 + 1, z = 28.5},
	arrival = {x = 32.5, y = NF, z = 2.5},
}

g.spawners, g.chests, g.signs = {}, {}, {}
g.finish = {x = 44, y = L3 + 2, z = 30}
g.gate = {x = 32, y = NF, z = 4}
g.surface = NF
g.outside = {x = 2, y = NF, z = 2}
-- For the checks: doors are opened (the players carry the cards), and these
-- ways must be the only ones in
g.open_for_checks = {"orthoverse_scifi:door_blue", "orthoverse_scifi:door_red", "orthoverse_scifi:blast_door"}
g.gated = {
	{label = "the reactor reachable without the red door", target = {x = 30, y = L3 + 1, z = 30},
		blocked = {{{x = 17, y = 0, z = 30}, {x = 17, y = 30, z = 31}}}},
	{label = "the armoury reachable without the blue door and the duct", target = {x = 6, y = L2 + 1, z = 47},
		blocked = {{{x = 13, y = 0, z = 47}, {x = 13, y = 30, z = 48}}, {{x = 22, y = 19, z = 50}, {x = 22, y = 20, z = 50}}}},
	{label = "the lower passage reachable without the blast door and the duct", target = {x = 15, y = L2 + 1, z = 40},
		blocked = {{{x = 17, y = 0, z = 51}, {x = 17, y = 30, z = 52}}, {{x = 22, y = 19, z = 50}, {x = 22, y = 20, z = 50}}}},
}

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

local seed = 4242
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
local function loot(x, y, z, kind, param2)
	set(x, y, z, LOOT, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot locker (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

local function card_locker(x, y, z, colour, param2)
	set(x, y, z, CARD_LOCKER, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {colour = colour,
		infotext = "Locker (one of these holds the " .. colour .. " keycard)"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = colour .. " card"}
end

-- A room: air inside x1..x2, z1..z2, floor at fy (deck), h high; lights in
-- the ceiling every 4 (if `lights`)
local function room(x1, z1, x2, z2, fy, h, lights)
	box(x1, fy, z1, x2, fy, z2, DECK)
	air(x1, fy + 1, z1, x2, fy + h, z2)
	if lights then
		for z = z1 + 1, z2 - 1, 4 do for x = x1 + 1, x2 - 1, 4 do set(x, fy + h + 1, z, LIGHT) end end
	end
end

------------------------------------------------------------------------------
-- The parts

local function ground()
	box(0, 0, 0, SX - 1, NG - 4, SZ - 1, ROCK)
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, "default:dirt")
	box(0, NG, 0, SX - 1, NG, SZ - 1, "default:dirt_with_grass")
end

-- The ship: a block of hull from deck to deck, scorched in places
local function hull()
	box(2, 1, 22, 61, 24, 62, HULL)
	for z = 22, 62 do for y = 1, 24 do for x = 2, 61 do
		if (x == 2 or x == 61 or z == 22 or z == 62 or y == 24) and rnd(4) == 0 then set(x, y, z, SCORCH) end
	end end end
end

-- The crater: the ship's torn hull opens off its floor
local function crater_open(x, z, y)
	local d = math.sqrt(((x - 32) / 1.5) ^ 2 + (z - 15) ^ 2)
	return d <= 5 + 2 * math.floor((y - (L1 + 1)) / 4)
end

local function crater()
	for z = 0, SZ - 1 do for x = 0, SX - 1 do
		if crater_open(x, z, L1 + 1) then
			set(x, L1, z, rnd(4) == 0 and "default:dirt" or "default:gravel")
		end
		for y = L1 + 1, NG do
			if crater_open(x, z, y) then set(x, y, z, "air") end
		end
	end end
	-- the breach: a torn way through the hull into the hold
	air(28, L1 + 1, 20, 36, L1 + 3, 23)
	box(28, L1, 20, 36, L1, 23, "default:gravel")
	for x = 27, 37 do for y = L1 + 1, L1 + 4 do
		if get(x, y, 22) == HULL and rnd(2) == 0 then set(x, y, 22, SCORCH) end
	end end
	-- scorched earth and twisted plates on the floor
	for _, p in ipairs({{27, 13}, {38, 16}, {30, 18}, {35, 11}}) do set(p[1], L1 + 1, p[2], SCORCH) end
	-- a glass dome over it: flush with the ground at the rim, rising to four
	-- blocks above it in the middle, sealed between its steps
	local hgt = {}
	local function k(x, z) return x .. "," .. z end
	for z = 0, SZ - 1 do for x = 0, SX - 1 do
		if get(x, NG, z) == "air" then
			local dn = math.sqrt(((x - 32) / 11) ^ 2 + ((z - 15) / 7.5) ^ 2)
			hgt[k(x, z)] = NG + math.max(0, math.floor(4 * (1 - dn * dn) + 0.5))
		end
	end end
	for z = 0, SZ - 1 do for x = 0, SX - 1 do
		local y = hgt[k(x, z)]
		if y then
			local low = y
			for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
				low = math.min(low, hgt[k(x + d[1], z + d[2])] or NG)
			end
			for yy = math.max(NG, low), y do set(x, yy, z, GLASS) end
		end
	end end
	-- and a ring of hull round its foot
	for z = 1, SZ - 2 do for x = 1, SX - 2 do
		if not hgt[k(x, z)] then
			for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
				if hgt[k(x + d[1], z + d[2])] then set(x, NG, z, HULL) end
			end
		end
	end end
end

-- The salvagers' camp, on the ground south of the crater
local function camp()
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(28, NF, 4, "orthoverse_adventure:board", 0)
	-- prefab shelters of salvaged plating, with a window each
	local function shelter(x1, z1)
		box(x1, NF, z1, x1 + 3, NF + 2, z1 + 3, HULL)
		air(x1 + 1, NF, z1 + 1, x1 + 2, NF + 1, z1 + 2)
		air(x1 + 1, NF, z1, x1 + 2, NF + 1, z1)               -- the door
		set(x1, NF + 1, z1 + 2, GLASS); set(x1 + 3, NF + 1, z1 + 2, GLASS)
		set(x1 + 1, NF + 2, z1 + 1, LIGHT)
	end
	shelter(19, 1)
	shelter(42, 1)
	-- crates of salvage, a lamp post, the notices on crates
	for _, p in ipairs({{25, 1}, {26, 1}, {25, 2}, {38, 1}, {39, 1}, {39, 2}}) do set(p[1], NF, p[2], CRATE) end
	set(26, NF + 1, 1, CRATE)
	set(36, NF, 5, CRATE); set(36, NF + 1, 5, CRATE)
	sign(36, NF + 1, 4, "+z", "THE FALLEN STAR\nA ship from the futuristic realm came down in the hills. Its machines are " ..
		"still running.\nRight-click the gate to go in. Ranks 3 to 7.")
	set(29, NF, 6, CRATE)
	sign(29, NF, 5, "+z", "WHAT WE HAVE SEEN\nDrones in the hold. Steel men in the corridors. Doors that want cards: " ..
		"blue for the armoury, red for the reactor, and the crew kept theirs in their lockers. Below, a floor " ..
		"that bites. And something big, by the reactor.")
	set(33, NF, 1, "default:mese_post_light")
end

-- The upper deck: the hold, the corridor and its cabins
local function upper()
	room(20, 24, 44, 33, L1, 4, true)                          -- the hold
	for _, p in ipairs({{21, 25}, {22, 25}, {21, 26}, {43, 25}, {43, 26}, {42, 25}, {21, 32}, {22, 32}, {41, 32}}) do
		set(p[1], L1 + 1, p[2], CRATE)
	end
	set(21, L1 + 2, 25, CRATE); set(43, L1 + 2, 25, CRATE)
	sign(40, L1 + 2, 24, "-z", "CARGO HOLD\nCrew deck ahead. Engineering below.")
	spawner(30, L1, 29, "drone", 3, 8)
	loot(43, L1 + 1, 32, "common", 1)
	-- the corridor
	room(31, 34, 33, 51, L1, 4, false)
	for z = 35, 51, 4 do set(32, L1 + 5, z, LIGHT) end
	spawner(32, L1, 41, "secbot", 1, 8)
	-- cabins: west x 23 to 29, east x 35 to 41; doors from the corridor
	for _, c in ipairs({{35, 39, 37}, {41, 45, 43}, {47, 51, 49}}) do
		room(23, c[1], 29, c[2], L1, 3, false); set(26, L1 + 4, c[3], LIGHT)
		room(35, c[1], 41, c[2], L1, 3, false); set(38, L1 + 4, c[3], LIGHT)
		air(30, L1 + 1, c[3], 30, L1 + 2, c[3])
		air(34, L1 + 1, c[3], 34, L1 + 2, c[3])
	end
	-- west 1, 2: crew cabins; west 3: the captain's
	for _, z in ipairs({35, 41}) do box(28, L1 + 1, z, 29, L1 + 1, z + 1, "wool:white") end
	card_locker(23, L1 + 1, 38, "blue", 3)
	card_locker(23, L1 + 1, 44, "blue", 3)
	card_locker(23, L1 + 1, 48, "blue", 3)
	set(28, L1 + 1, 51, CONSOLE, 0)
	loot(29, L1 + 1, 47, "common", 2)
	sign(25, L1 + 2, 51, "+z", "CAPTAIN'S LOG\nPower failing. I have ordered the crew to their stations. " ..
		"If the doors seal, the old maintenance duct still runs behind these cabins.")
	-- east 1: the medbay; east 2: a crew cabin; east 3: the security office
	set(41, L1 + 1, 37, "orthoverse_scifi:medbay")
	loot(40, L1 + 1, 35, "common", 2)
	sign(38, L1 + 2, 39, "+z", "MEDBAY\nOne treatment per patient.")
	box(35, L1 + 1, 41, 36, L1 + 1, 42, "wool:white")
	card_locker(41, L1 + 1, 44, "blue", 1)
	spawner(38, L1, 49, "secbot", 2, 6)
	loot(41, L1 + 1, 50, "weapon", 1)
	set(36, L1 + 1, 51, CONSOLE, 0)
end

-- The stair down at the corridor's end, into engineering (after it, so the
-- steps stand in its air)
local function stair()
	for k = 1, 6 do
		box(31, L1 - k, 51 + k, 33, L1 - k, 51 + k, DECK)
		air(31, L1 - k + 1, 51 + k, 33, L1 + 4, 51 + k)
	end
end

-- Engineering: the live floor and the relays
local function engineering()
	room(18, 38, 48, 60, L2, 5, false)
	for z = 40, 58, 6 do set(17, L2 + 4, z, LIGHT); set(49, L2 + 4, z, LIGHT) end
	for x = 20, 46, 6 do set(x, L2 + 4, 61, LIGHT); set(x, L2 + 4, 37, LIGHT) end
	-- the plates: patches of 3 by 2, the two sets in turn; safe ground at the
	-- foot of the stair, in front of each relay and of the blast door
	local function safe(x, z)
		return (x >= 29 and x <= 35 and z >= 56) or (x <= 19 and z >= 43 and z <= 45) or (x >= 47 and z >= 43 and z <= 45)
			or (x >= 31 and x <= 35 and z <= 39) or (x <= 19 and z >= 50 and z <= 53)
	end
	for z = 38, 60 do for x = 18, 48 do
		if not safe(x, z) then
			local set_ = (math.floor((x - 18) / 3) + math.floor((z - 38) / 2)) % 2 == 0 and "a" or "b"
			set(x, L2, z, "orthoverse_scifi:plate_" .. set_)
		end
	end end
	set(32, L2 + 2, 61, "orthoverse_scifi:floor_controller")
	-- consoles and pipes
	for _, x in ipairs({22, 26, 38, 42}) do set(x, L2 + 1, 60, CONSOLE, 0) end
	-- the relays: west, east and south walls
	set(17, L2 + 2, 44, "orthoverse_scifi:relay", 3)
	set(49, L2 + 2, 44, "orthoverse_scifi:relay", 1)
	set(33, L2 + 2, 37, "orthoverse_scifi:relay", 2)
	sign(30, L2 + 3, 60, "+z", "ENGINEERING\nPower to the blast doors is cut. Throw all three relays. Mind the deck plates.")
	spawner(24, L2, 52, "drone", 2, 10)
	-- the blast door to the lower passage, in the west wall
	box(17, L2 + 1, 51, 17, L2 + 3, 52, "orthoverse_scifi:blast_door", 3)
end

-- The lower passage, the armoury and the duct
local function lower()
	room(14, 28, 16, 53, L2, 4, false)
	for z = 30, 52, 5 do set(15, L2 + 5, z, LIGHT) end
	spawner(15, L2, 40, "secbot", 2, 8)
	-- the armoury, behind the blue door
	room(3, 44, 12, 50, L2, 4, true)
	box(13, L2 + 1, 47, 13, L2 + 2, 48, "orthoverse_scifi:door_blue", 3)
	sign(14, L2 + 3, 46, "-x", "ARMOURY\nBlue clearance.")
	card_locker(3, L2 + 1, 46, "red", 3)
	loot(3, L2 + 1, 49, "weapon", 3)
	for _, p in ipairs({{6, 44}, {7, 44}, {10, 50}}) do set(p[1], L2 + 1, p[2], CRATE) end
	spawner(8, L2, 47, "secbot", 1, 6)
	-- the duct: from the loose panel in the captain's cabin, west above the
	-- engineering ceiling and the passage, and down a ladder into the armoury
	set(22, L1 + 1, 50, LOOSE); set(22, L1 + 2, 50, LOOSE)
	air(12, L1 + 1, 50, 21, L1 + 2, 51)
	air(12, L2 + 1, 51, 12, L1 + 2, 51)
	box(12, L2 + 1, 51, 12, L1 + 2, 51, "default:ladder_steel", SIGN_P2["+z"])
	-- the red door to the reactor
	box(17, L2 + 1, 30, 17, L2 + 2, 31, "orthoverse_scifi:door_red", 3)
	sign(14, L2 + 3, 32, "-x", "REACTOR\nRed clearance.")
end

-- The reactor room
local function reactor()
	box(18, L3, 24, 48, L3, 36, DECK)
	air(18, L3 + 1, 24, 48, L3 + 14, 36)
	-- the catwalk: along the west wall, then down a stair along the south
	box(18, L2, 27, 19, L2, 36, DECK)
	box(18, L2, 25, 19, L2, 26, DECK)
	for z = 27, 36 do set(20, L2 + 1, z, BARS) end
	for k = 1, 10 do box(19 + k, L2 - k, 25, 19 + k, L2 - k, 26, DECK) end
	-- three reactor cores
	for _, x in ipairs({28, 34, 40}) do box(x, L3 + 1, 31, x, L3 + 14, 31, REACTOR) end
	for _, x in ipairs({28, 34, 40}) do
		for _, d in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do set(x + d[1], L3 + 1, 31 + d[2], GLASS) end
	end
	-- two ledges on the east wall, a turret on each
	for _, z in ipairs({26, 33}) do
		box(46, L3 + 6, z, 48, L3 + 6, z + 1, DECK)
		spawner(47, L3 + 6, z, "turret", 1, 14, true)
	end
	-- the Warden, and drones about the cores
	spawner(36, L3, 27, "warden", 1, 12)
	spawner(24, L3, 33, "drone", 2, 12)
	-- the black box on its plinth, the finish locker beside
	set(44, L3 + 1, 30, HULL)
	set(g.finish.x, g.finish.y, g.finish.z, "orthoverse_scifi:black_box")
	loot(45, L3 + 1, 32, "finish", 1)
	sign(48, L3 + 3, 30, "+x", "THE BLACK BOX\nTouch it to claim the ship's record, and The Fallen Star.")
end

------------------------------------------------------------------------------

-- A plan of the ship below the ground, north at the top: "." open to the sky,
-- "1", "2", "3" open on the upper deck, engineering and passage level, the
-- reactor; "#" solid
function g.plan()
	local rows = {}
	for z = SZ - 1, 0, -1 do
		local row = {}
		for x = 0, SX - 1 do
			local ch = "#"
			if get(x, NG, z) == "air" then ch = "."
			elseif get(x, L1 + 2, z) == "air" then ch = "1"
			elseif get(x, L2 + 2, z) == "air" then ch = "2"
			elseif get(x, L3 + 3, z) == "air" then ch = "3" end
			row[#row + 1] = ch
		end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, "\n")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.spawners, g.chests, g.signs = {}, {}, {}
	seed = 4242
	ground()
	hull()
	crater()
	camp()
	upper()
	engineering()
	stair()
	lower()
	reactor()
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
	for name in pairs(missing) do core.log("error", "[fallen_star] no such node: " .. name) end
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
