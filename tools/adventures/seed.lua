-- The Seed: builds the ready-made adventure in a world, so that it can be
-- saved as adventures/seed.ovt (the compact form; see
-- tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/seed.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/seed.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 36 (players stand at y = 37). Something fell here, and the
-- ground round it is growing: the growth has walled the place in.
--
--   Outside the wall (south): the gate, the board, one sign.
--   The survey camp (inside the wall, south; the start): two huts, the
--     stores (fire pots, masks), the rifle rack, floodlights. East of it the
--     hangar: the crane on its rail, the booth that drives it, and in the
--     floor a loading pit with a cargo container in it, over the hatch to the
--     team's borehole. Lift the container out to get down.
--   The Rind (inside the wall, north): the land's surface under a skin of
--     growth, trees wrapped in it, the Seed's broken husk in its crater, egg
--     sacs, husks.
--   The borehole: a stair down round the drill pipe into the Gut.
--   The Gut (floor 22): ribbed tunnels lit by nodules, creep spreading.
--     From its hub: east, the acid river (pads that sink) and a ganglion on
--     the far shore; north-west, by one of two valves, the Lung; north, by
--     one of two valves, the Nest; west, the way down, shut by the Heart's
--     shell until the three ganglia are cut.
--   The Lung: a great chamber that breathes. Narrow ribs cross a pit of
--     spore vents; gusts from the north wall blow players off them. A
--     ganglion on the far ledge.
--   The Nest: egg sacs over the floor (sneak, and they wake later), crawlers
--     by threes, a ganglion at the back.
--   The Heart (floor 4): a great chamber under the crater, the Heart in the
--     middle with four nodules round it, tendrils, spitters on the walls.
--     When the last nodule bursts its core opens: the finish inside.
--
-- Party of two to four, ranks 5 to 10. Monsters: husks, crawlers, spitters,
-- spore puffs, tendrils, ganglia and the Heart's nodules (orthoverse_monsters).

local g = {}

local SX, SY, SZ = 80, 50, 80
local NG, NF = 36, 37       -- the land's ground, and where players stand on it
local FG = 22               -- the Gut's floor (players stand at 23)
local FH = 4                -- the Heart's floor (well below the Lung's pit)

local ROCK = "default:stone"
local DIRT = "default:dirt"
local GRASS = "default:dirt_with_grass"
local CRUST = "orthoverse_seed:crust"
local WALL = "orthoverse_seed:wall"
local WALLD = "orthoverse_seed:wall_dark"
local FLESH = "orthoverse_seed:flesh"
local NODULE = "orthoverse_seed:nodule"
local HEART = "orthoverse_seed:heart"
local SHELL = "orthoverse_seed:shell"
local CORE = "orthoverse_seed:core"
local MEMBRANE = "orthoverse_seed:membrane"
local VALVE = "orthoverse_seed:valve"
local ACID = "orthoverse_seed:acid"
local PAD = "orthoverse_seed:pad"
local EGG = "orthoverse_seed:egg"
local VENT = "orthoverse_seed:vent"
local GUST = "orthoverse_seed:gust"
local BUD = "orthoverse_seed:bud"
local HULL = "orthoverse_scifi:hull"
local DECK = "orthoverse_scifi:deck"
local PLIGHT = "orthoverse_scifi:panel_light"
local GLASS = "orthoverse_scifi:glass"
local CRATE = "orthoverse_scifi:crate"
local CONSOLE = "orthoverse_scifi:console"
local STEEL = "default:steelblock"
local SIGN = "default:sign_wall_steel"
local SPAWNER = "orthoverse_monsters:spawner"
local CHEST = "orthoverse_loot:chest"
local FINISH = "orthoverse_adventure:finish"

g.info = {
	name = "The Seed",
	line = "Something fell, and the ground round it is growing. The survey team went down after it.",
	limit = 60,
	tags = {"combat", "puzzle", "sci-fi"},   -- for the Adventures page (at most three)
	-- (the Adventures page, under the cover picture: a few sentences, no answers)
	blurb = "The survey team followed it down and never came back up. Now the ground itself is growing over their camp, and the way below changes while you are inside it. Take the team's gear, go down into the growth, and find what is feeding it.",
	rank_min = 5, rank_max = 10,
	size = {x = SX, y = SY, z = SZ},
	ground = NG,
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 3, y = 0, z = 8},
	corner2 = {x = SX - 4, y = NF + 10, z = SZ - 4},
	start = {x = 36.5, y = NF, z = 18.5},
	arrival = {x = 40.5, y = NF, z = 2.5},
}
g.compact = true

-- Where things are, for tests
g.spawners = {}
g.chests = {}
g.signs = {}
g.finish = {x = 38, y = FH + 1, z = 43}
g.gate = {x = 40, y = NF, z = 5}
g.surface = NF
g.outside = {x = 6, y = NF, z = 3}
g.rim = {}
-- For the checks: the crane's container lifted out, the membranes and valves
-- burnt or open, the shell and the core gone
g.open_for_checks = {"orthoverse_seed:container", MEMBRANE, VALVE, SHELL, CORE}
g.valves = {}       -- set -> list of {min, max} (each one opening)
g.gated = {}        -- filled in as the parts are built

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

local seed = 7171
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return math.floor(seed / 65536) % n   -- (the high bits: the low ones repeat)
end

local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}
local function sign(x, y, z, dir, text)
	set(x, y, z, SIGN, SIGN_P2[dir])
	g.signs[#g.signs + 1] = {x = x, y = y, z = z, dir = dir, text = text:match("^[^\n]*")}
	metas[#metas + 1] = {x = x, y = y, z = z, fields = {text = text, infotext = '"' .. text .. '"'}, construct = true}
end

-- A spawner in the floor (its block replaces the floor block); aloft: on a
-- ledge or a wall, not walked to
local function spawner(x, y, z, kind, count, wake, opts)
	opts = opts or {}
	set(x, y, z, SPAWNER)
	local fields = {kind = "orthoverse_monsters:" .. kind, count = tostring(count), wake = tostring(wake),
		infotext = "Monster spawner: " .. count .. " × " .. kind}
	if opts.stealth then fields.stealth = "1" end
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = fields}
	g.spawners[#g.spawners + 1] = {x = x, y = y, z = z, kind = kind, count = count, wake = wake, aloft = opts.aloft}
end

local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot chest (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

local function valve_box(set_name, x1, y1, z1, x2, y2, z2)
	box(x1, y1, z1, x2, y2, z2, VALVE)
	for z = math.min(z1, z2), math.max(z1, z2) do for y = math.min(y1, y2), math.max(y1, y2) do
		for x = math.min(x1, x2), math.max(x1, x2) do
			metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {set = set_name}}
		end
	end end
	g.valves[set_name] = g.valves[set_name] or {}
	table.insert(g.valves[set_name], {min = {x = math.min(x1, x2), y = math.min(y1, y2), z = math.min(z1, z2)},
		max = {x = math.max(x1, x2), y = math.max(y1, y2), z = math.max(z1, z2)}})
end

------------------------------------------------------------------------------
-- Smooth noise, for rough walls

local function hash(x, y, z)
	local v = math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453
	return v - math.floor(v)
end
local function noise(x, y, z, scale)
	local fx, fy, fz = x / scale, y / scale, z / scale
	local x0, y0, z0 = math.floor(fx), math.floor(fy), math.floor(fz)
	local tx, ty, tz = fx - x0, fy - y0, fz - z0
	local function s(t) return t * t * (3 - 2 * t) end
	tx, ty, tz = s(tx), s(ty), s(tz)
	local function l(a, b, t) return a + (b - a) * t end
	local c = {}
	for i = 0, 1 do for j = 0, 1 do for k = 0, 1 do c[i * 4 + j * 2 + k] = hash(x0 + i, y0 + j, z0 + k) end end end
	return l(l(l(c[0], c[4], tx), l(c[2], c[6], tx), ty), l(l(c[1], c[5], tx), l(c[3], c[7], tx), ty), tz)
end

------------------------------------------------------------------------------
-- The ground: rock, then dirt and grass outside the wall

local function ground()
	box(0, 0, 0, SX - 1, NG - 4, SZ - 1, ROCK)
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, DIRT)
	box(0, NG, 0, SX - 1, NG, SZ - 1, GRASS)
end

-- Lining: where a dug space meets rock, the growth's ribbed wall
local function line_with(x1, y1, z1, x2, y2, z2, name)
	for z = z1 - 1, z2 + 1 do for y = y1 - 1, y2 + 1 do for x = x1 - 1, x2 + 1 do
		if inside(x, y, z) then
			local n = get(x, y, z)
			if n == ROCK or n == DIRT then set(x, y, z, name or (rnd(5) == 0 and WALLD or WALL)) end
		end
	end end end
end

-- A room: floor block at fy, air above it for h, lined with growth; a
-- nodule in the walls now and then for light
local function room(x1, z1, x2, z2, fy, h, floor)
	line_with(x1, fy + 1, z1, x2, fy + h, z2)
	box(x1, fy, z1, x2, fy, z2, floor or FLESH)
	air(x1, fy + 1, z1, x2, fy + h, z2)
end

-- Light the growth: nodules set into its walls where a wall faces open air,
-- about one every `every` blocks
local function light_walls(x1, y1, z1, x2, y2, z2, every)
	for z = z1, z2 do for y = y1, y2 do for x = x1, x2 do
		local n = get(x, y, z)
		if (n == WALL or n == WALLD) and rnd(every) == 0 then
			for _, dd in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
				if inside(x + dd[1], y, z + dd[2]) and get(x + dd[1], y, z + dd[2]) == "air" then
					set(x, y, z, NODULE)
					break
				end
			end
		end
	end end end
end

-- A tunnel along straight legs (3 wide, 4 high), floor at fy. Legs between
-- points {x, z}; corners filled
local function tunnel(points, fy, h, w)
	h, w = h or 4, w or 1
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local x1, x2 = math.min(a[1], b[1]), math.max(a[1], b[1])
		local z1, z2 = math.min(a[2], b[2]), math.max(a[2], b[2])
		room(x1 - w, z1 - w, x2 + w, z2 + w, fy, h)
	end
end

------------------------------------------------------------------------------
-- Outside: the gate, the board, the sign; and the wall the growth has raised
-- round the place

local function outside()
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(37, NF, 5, "orthoverse_adventure:board", 0)
	box(42, NF, 6, 44, NF + 2, 6, WALL)
	sign(43, NF + 1, 5, "+z", "THE SEED\nSomething fell, and the ground round it is growing.\nRanks 5 to 10.")
	for _, p in ipairs({{33, 3}, {47, 3}}) do set(p[1], NF, p[2], "default:mese_post_light") end
	-- the wall: two thick, nine high, ribbed and lumpy
	for z = 8, SZ - 4 do for x = 3, SX - 4 do
		local edge = x <= 4 or x >= SX - 5 or z <= 9 or z >= SZ - 5
		if edge then
			local hgt = 8 + (noise(x, 0, z, 5) > 0.6 and 1 or 0)
			for y = NG, NG + hgt do set(x, y, z, rnd(4) == 0 and WALLD or WALL) end
		end
	end end
	-- and crust creeping out from its foot
	for z = 5, SZ - 2 do for x = 1, SX - 2 do
		if get(x, NG, z) == GRASS and noise(x, 3, z, 3) > 0.72 then set(x, NG, z, CRUST) end
	end end
end

------------------------------------------------------------------------------
-- The survey camp

local function hut(x1, z1, w, d, door_side)
	-- hull walls and roof, a deck floor, a panel light; the door on the side
	box(x1, NF, z1, x1 + w - 1, NF + 3, z1 + d - 1, HULL)
	box(x1 + 1, NG, z1 + 1, x1 + w - 2, NG, z1 + d - 2, DECK)
	air(x1 + 1, NF, z1 + 1, x1 + w - 2, NF + 2, z1 + d - 2)
	set(x1 + math.floor(w / 2), NF + 3, z1 + math.floor(d / 2), PLIGHT)
	local mx, mz = x1 + math.floor(w / 2), z1 + math.floor(d / 2)
	if door_side == "+z" then air(mx, NF, z1 + d - 1, mx + 1, NF + 1, z1 + d - 1)
	elseif door_side == "-x" then air(x1, NF, mz, x1, NF + 1, mz + 1)
	elseif door_side == "+x" then air(x1 + w - 1, NF, mz, x1 + w - 1, NF + 1, mz + 1) end
	if door_side ~= "-x" then set(x1, NF + 1, mz, GLASS) end
	if door_side ~= "+x" then set(x1 + w - 1, NF + 1, mz, GLASS) end
end

local function camp()
	-- the yard: trodden earth and deck plates, floodlights at its corners
	for z = 11, 31 do for x = 6, 48 do
		if get(x, NG, z) == GRASS or get(x, NG, z) == CRUST then
			set(x, NG, z, (x + z) % 5 == 0 and DECK or "default:dirt_with_dry_grass")
		end
	end end
	for _, p in ipairs({{22, 12}, {48, 12}, {22, 30}, {48, 30}}) do set(p[1], NF, p[2], "default:mese_post_light") end
	-- the stores hut (west) and the lab hut (north-west)
	hut(24, 12, 7, 6, "+x")
	set(25, NF, 13, "orthoverse_seed:stores", 1)
	set(25, NF, 16, "orthoverse_seed:stores", 1)
	set(29, NF, 13, "orthoverse_seed:rack", 0)
	set(29, NF + 1, 13, "orthoverse_seed:rack", 0)
	hut(24, 22, 8, 6, "+x")
	set(25, NF, 26, CONSOLE, 0); set(26, NF, 26, CONSOLE, 0)
	set(29, NF, 23, CRATE)
	chest(25, NF, 23, "common", 1)
	-- crates and the core samples, stacked
	for _, p in ipairs({{34, 26}, {35, 26}, {34, 27}, {41, 13}, {42, 13}}) do set(p[1], NF, p[2], CRATE) end
	set(34, NF + 1, 26, CRATE)
	-- the way the team came (blocked by the wall now): a track to the south
	for z = 10, 12 do set(40, NG, z, DECK); set(41, NG, z, DECK) end
end

------------------------------------------------------------------------------
-- The hangar and its crane

local HX1, HZ1, HX2, HZ2 = 50, 11, 72, 33   -- the hangar's walls
local RAIL_Y = NF + 7                        -- the crane rail, under the roof
local CZ = 22                                -- the rail's line (z)
local PIT = {x1 = 53, z1 = 21, x2 = 54, z2 = 22}   -- the loading pit: the container in it
g.crane = {pit = PIT, rail_y = RAIL_Y, z = CZ}

local function hangar()
	box(HX1, NF, HZ1, HX2, NF + 8, HZ2, HULL)
	air(HX1 + 1, NF, HZ1 + 1, HX2 - 1, NF + 7, HZ2 - 1)
	box(HX1 + 1, NG, HZ1 + 1, HX2 - 1, NG, HZ2 - 1, DECK)
	-- the great door, open on the camp
	air(HX1, NF, 19, HX1, NF + 4, 24)
	-- roof lights
	for x = HX1 + 3, HX2 - 3, 5 do for z = HZ1 + 3, HZ2 - 3, 6 do set(x, NF + 8, z, PLIGHT) end end
	-- the rail along the hangar, the trolley on it, cable and magnet (raised)
	box(52, RAIL_Y, CZ, 70, RAIL_Y, CZ, "orthoverse_seed:rail")
	set(62, RAIL_Y - 1, CZ, "orthoverse_seed:trolley")
	set(62, RAIL_Y - 2, CZ, "orthoverse_seed:cable")
	set(62, RAIL_Y - 3, CZ, "orthoverse_seed:magnet")
	-- the loading pit, two deep, the container filling it; under its corner
	-- the hatch to the borehole
	box(PIT.x1, NG - 1, PIT.z1, PIT.x2, NG, PIT.z2, "orthoverse_seed:container")
	box(PIT.x1 - 1, NG - 2, PIT.z1 - 1, PIT.x2 + 1, NG - 2, PIT.z2 + 1, HULL)
	-- the pit's walls (hull, so the container cannot be dropped through)
	for z = PIT.z1 - 1, PIT.z2 + 1 do for x = PIT.x1 - 1, PIT.x2 + 1 do
		if x < PIT.x1 or x > PIT.x2 or z < PIT.z1 or z > PIT.z2 then
			set(x, NG - 1, z, HULL)
		end
	end end
	set(PIT.x1, NG - 2, PIT.z1, "air")   -- the hatch
	-- yellow and black round the pit
	for x = PIT.x1 - 1, PIT.x2 + 1 do
		set(x, NG, PIT.z1 - 1, "default:goldblock"); set(x, NG, PIT.z2 + 1, "default:goldblock")
	end
	set(PIT.x1 - 1, NG, PIT.z1, "default:goldblock"); set(PIT.x1 - 1, NG, PIT.z2, "default:goldblock")
	set(PIT.x2 + 1, NG, PIT.z1, "default:goldblock"); set(PIT.x2 + 1, NG, PIT.z2, "default:goldblock")
	-- a second container on the floor further along, and crates: something to
	-- set the first one down beside
	box(66, NF, 21, 67, NF + 1, 22, "orthoverse_seed:container")
	for _, p in ipairs({{70, 13}, {71, 13}, {70, 14}, {70, 31}, {71, 31}, {71, 30}}) do set(p[1], NF, p[2], CRATE) end
	-- the booth: up a stair against the south wall, a window over the pit,
	-- five buttons at the sill (facing the player, who looks north)
	local BY = NF + 3   -- the booth's floor block
	box(52, BY, 12, 58, BY, 15, DECK)
	box(52, BY + 1, 15, 58, BY + 3, 15, GLASS)
	box(51, BY + 1, 12, 51, BY + 3, 15, HULL)
	box(59, BY + 1, 13, 59, BY + 3, 15, HULL)
	set(55, BY + 4, 13, PLIGHT)
	-- the stair up: from the floor by the east of the booth
	for i = 0, 3 do
		set(60 + i, NG + 1 + (3 - i), 12, DECK)
		box(60 + i, NG + 1, 12, 60 + i, NG + (3 - i), 12, HULL)
	end
	air(59, BY + 1, 12, 59, BY + 2, 12)   -- in from the stair's head
	set(59, BY, 12, DECK)
	-- the console at waist height, under the window: the buttons in it, a
	-- screen at each end (the player looks over them, down at the pit)
	set(52, BY + 1, 14, CONSOLE, 0)
	set(53, BY + 1, 14, "orthoverse_seed:button_left", 0)
	set(54, BY + 1, 14, "orthoverse_seed:button_right", 0)
	set(55, BY + 1, 14, "orthoverse_seed:button_up", 0)
	set(56, BY + 1, 14, "orthoverse_seed:button_down", 0)
	set(57, BY + 1, 14, "orthoverse_seed:button_magnet", 0)
	set(58, BY + 1, 14, CONSOLE, 0)
	g.gated[#g.gated + 1] = {label = "the Gut reachable without moving the container",
		target = {x = 52, y = FG + 1, z = 18},
		-- (the pit, and the stair's head under it: the checks only test where
		-- a player lands, not what they fall through)
		blocked = {{{x = PIT.x1, y = NG - 3, z = PIT.z1}, {x = PIT.x2 + 1, y = NG, z = PIT.z2 + 1}}}}
end

------------------------------------------------------------------------------
-- The Rind: the surface inside the wall, north of the camp, under the growth

local function wrapped_tree(x, y, z)
	local hgt = 4 + rnd(3)
	for i = 0, hgt - 1 do set(x, y + i, z, "default:tree") end
	for dz = -2, 2 do for dy = hgt - 2, hgt + 1 do for dx = -2, 2 do
		if math.abs(dx) + math.abs(dz) + math.max(0, dy - hgt) < 4 and rnd(4) > 0 and get(x + dx, y + dy, z + dz) == "air" then
			set(x + dx, y + dy, z + dz, rnd(3) == 0 and FLESH or "default:leaves")
		end
	end end end
	-- and the growth up its trunk
	for i = 0, hgt - 2, 2 do
		if get(x + 1, y + i, z) == "air" then set(x + 1, y + i, z, WALL) end
	end
end

local function rind()
	for z = 32, SZ - 6 do for x = 5, SX - 6 do
		if get(x, NG, z) == GRASS then
			local n = noise(x, 1, z, 6)
			set(x, NG, z, n > 0.35 and CRUST or GRASS)
		end
	end end
	-- the crater: a shallow bowl of crust, the husk of the Seed in it, broken
	-- open, glowing
	local CX, CZr = 40, 54
	for z = CZr - 10, CZr + 10 do for x = CX - 10, CX + 10 do
		local r = math.sqrt((x - CX) ^ 2 + (z - CZr) ^ 2)
		if r <= 10 then
			local depth = r < 7 and 2 or (r < 9 and 1 or 0)
			for y = NG - depth + 1, NG do set(x, y, z, "air") end
			set(x, NG - depth, z, CRUST)
			if r > 9 and r <= 10 then set(x, NF, z, CRUST) end   -- a lip
		end
	end end
	-- the husk: a split shell, taller than a house
	for y = NG - 1, NG + 7 do
		local rr = 4.5 - math.abs(y - (NG + 3)) * 0.45
		for z = CZr - 5, CZr + 5 do for x = CX - 5, CX + 5 do
			local r = math.sqrt((x - CX) ^ 2 + (z - CZr) ^ 2)
			if r <= rr and r > rr - 1.2 and not (x > CX and z < CZr + 1 and y > NG) then
				set(x, y, z, (x + y + z) % 7 == 0 and NODULE or "default:obsidian")
			end
		end end
	end
	set(CX, NG + 1, CZr, NODULE); set(CX - 1, NG, CZr + 1, NODULE)
	-- trees, wrapped in it
	for _, p in ipairs({{10, 40}, {16, 66}, {24, 46}, {62, 44}, {68, 62}, {58, 68}, {12, 54}, {30, 70}, {50, 40}}) do
		wrapped_tree(p[1], NF, p[2])
	end
	-- egg sacs by the crater's lip, crawlers in them; husks wandering
	for _, p in ipairs({{29, 50}, {30, 52}, {28, 53}, {31, 55}}) do set(p[1], NF, p[2], EGG) end
	spawner(30, NG, 53, "crawler", 3, 7)
	spawner(52, NG, 60, "husk", 2, 12)
	spawner(18, NG, 58, "husk", 1, 12)
	-- a team member's pack, dropped
	chest(55, NF, 66, "common", 2)
	-- spore vents among the crust
	for _, p in ipairs({{36, 66}, {46, 42}, {20, 48}}) do set(p[1], NG, p[2], VENT) end
end

------------------------------------------------------------------------------
-- The borehole: a stair round the drill pipe, from under the hatch down into
-- the Gut's hub

local BX, BZ = PIT.x1 + 1, PIT.z1 + 1   -- the pipe (the hatch is at its south-west)
local RING = {{-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}}

local function borehole()
	local top = NG - 3   -- the first step's top block
	box(BX - 2, FG + 1, BZ - 2, BX + 2, NG - 3, BZ + 2, HULL)
	air(BX - 1, FG + 1, BZ - 1, BX + 1, NG - 3, BZ + 1)
	box(BX, FG + 1, BZ, BX, NG - 2, BZ, STEEL)   -- the drill pipe
	-- the pit's floor is open over the stair's first turn (the container rests
	-- on the pipe's head)
	air(BX - 1, NG - 2, BZ - 1, BX + 1, NG - 2, BZ + 1)
	set(BX, NG - 2, BZ, STEEL)
	local k = 0
	local y = top
	while y >= FG + 1 do
		local c = RING[(k % 8) + 1]
		set(BX + c[1], y, BZ + c[2], DECK)
		if (k % 4) == 2 then set(BX + 2 * c[1], y + 2, BZ + 2 * c[2], PLIGHT) end
		k = k + 1
		y = y - 1
	end
	-- the last step lands in the hub (its ceiling opened above the stair)
end

------------------------------------------------------------------------------
-- The Gut

local function gut()
	-- the hub: a chamber round the foot of the borehole
	room(44, 14, 63, 30, FG, 6)
	-- the borehole comes down into it (its hull ends at the hub's ceiling)
	air(BX - 2, FG + 1, BZ - 2, BX + 2, FG + 6, BZ + 2)
	box(BX, FG + 1, BZ, BX, FG + 6, BZ, STEEL)
	local k = 0
	for y = NG - 3, FG + 1, -1 do
		local c = RING[(k % 8) + 1]
		if y <= FG + 6 then set(BX + c[1], y, BZ + c[2], DECK) end
		k = k + 1
	end
	-- dropped gear at the stair's foot
	set(48, FG + 1, 16, CRATE); set(49, FG + 1, 16, CRATE)
	spawner(58, FG, 27, "husk", 2, 10)
	set(60, FG, 16, BUD); set(46, FG, 28, BUD)

	-- East: the tunnel to the acid river
	tunnel({{63, 18}, {68, 18}}, FG, 4)
	room(66, 16, 76, 46, FG, 8)
	-- the river: a pool across the chamber, the pads in a winding line
	box(66, FG - 2, 25, 76, FG, 37, ACID)
	box(65, FG - 3, 24, 77, FG - 3, 38, WALL)
	local path = {{70, 24}, {70, 25}, {70, 26}, {71, 26}, {72, 26}, {72, 27}, {72, 28}, {71, 28}, {70, 28}, {69, 28},
		{69, 29}, {69, 30}, {69, 31}, {70, 31}, {71, 31}, {72, 31}, {73, 31}, {73, 32}, {73, 33}, {73, 34}, {72, 34},
		{71, 34}, {71, 35}, {71, 36}, {71, 37}, {71, 38}}
	for _, p in ipairs(path) do
		if p[2] >= 25 and p[2] <= 37 then set(p[1], FG, p[2], PAD) end
	end
	-- spitters in the walls, up high (they cling where they come out)
	spawner(77, FG + 4, 40, "spitter", 1, 14, {aloft = true})
	spawner(65, FG + 4, 42, "spitter", 1, 14, {aloft = true})
	-- the far shore: the first ganglion, and a chest
	spawner(72, FG, 43, "ganglion", 1, 8)
	chest(75, FG + 1, 45, "weapon", 3)
	-- a crawler nest on the near side
	for _, p in ipairs({{67, 19}, {68, 21}, {67, 22}}) do set(p[1], FG + 1, p[2], EGG) end
	spawner(68, FG, 20, "crawler", 3, 6)

	-- North-west: to the Lung, by one of two valves (set a)
	tunnel({{46, 30}, {46, 34}, {42, 34}}, FG, 4)
	tunnel({{52, 30}, {52, 39}, {42, 39}}, FG, 4)
	valve_box("a", 45, FG + 1, 31, 47, FG + 4, 31)
	valve_box("a", 51, FG + 1, 32, 53, FG + 4, 32)
	tunnel({{42, 34}, {42, 42}}, FG, 4)
	set(41, FG, 39, BUD)

	-- North: to the Nest, by one of two valves (set b)
	tunnel({{58, 30}, {58, 50}}, FG, 4)
	tunnel({{62, 30}, {62, 50}}, FG, 4)
	valve_box("b", 57, FG + 1, 32, 59, FG + 4, 32)
	valve_box("b", 61, FG + 1, 34, 63, FG + 4, 34)
	set(58, FG, 38, BUD)

	-- A side pocket behind a membrane, with a chest
	tunnel({{44, 20}, {40, 20}}, FG, 3, 1)
	box(43, FG + 1, 19, 43, FG + 3, 21, MEMBRANE)
	chest(39, FG + 1, 20, "common", 1)

	-- West: the way down to the Heart, shut by its shell
	tunnel({{44, 25}, {36, 25}}, FG, 4)
	box(42, FG + 1, 24, 42, FG + 4, 26, SHELL)
	box(41, FG + 1, 24, 41, FG + 4, 26, SHELL)
	g.gated[#g.gated + 1] = {label = "the Heart reachable without cutting the ganglia",
		target = {x = 38, y = FH + 1, z = 36},
		blocked = {{{x = 41, y = FG + 1, z = 24}, {x = 42, y = FG + 4, z = 26}}}}
	-- spitters and crawlers along the tunnels
	spawner(46, FG + 2, 36, "spitter", 1, 10, {aloft = true})
	spawner(58, FG, 42, "crawler", 3, 7)
	spawner(74, FG, 20, "husk", 1, 10)
end

------------------------------------------------------------------------------
-- The Lung: ribs over a pit of spores; gusts from the north wall

local function lung()
	local x1, z1, x2, z2 = 8, 42, 44, 72
	local PF = FG - 5     -- the pit's floor
	line_with(x1, PF + 1, z1, x2, FG + 11, z2)
	box(x1, PF, z1, x2, PF, z2, CRUST)
	air(x1, PF + 1, z1, x2, FG + 11, z2)
	-- the entrance ledge (east) and the far ledge (west), at the Gut's floor
	box(38, PF, 42, 44, FG, 48, FLESH)
	box(8, PF, 62, 14, FG, 72, FLESH)
	-- the ribs: narrow bridges, back and forth, from ledge to ledge
	local ribs = {
		{{38, 46}, {30, 46}}, {{30, 46}, {30, 52}}, {{30, 52}, {22, 52}}, {{22, 52}, {22, 48}},
		{{22, 48}, {16, 48}}, {{16, 48}, {16, 58}}, {{16, 58}, {24, 58}}, {{24, 58}, {24, 64}}, {{24, 64}, {14, 64}},
	}
	for _, r in ipairs(ribs) do
		-- a bridge one block thick, held up by a pillar every few blocks
		local a, b = r[1], r[2]
		for z = math.min(a[2], b[2]), math.max(a[2], b[2]) do for x = math.min(a[1], b[1]), math.max(a[1], b[1]) do
			set(x, FG, z, (x + z) % 3 == 0 and WALLD or FLESH)
			if (x + z) % 6 == 0 then box(x, PF, z, x, FG - 1, z, WALLD) end
		end end
	end
	-- the pit: spore vents in its floor, and a way back up: a ramp of growth
	-- in the south-east corner
	for z = z1 + 2, z2 - 2, 4 do for x = x1 + 2, x2 - 8, 5 do
		if get(x, PF + 1, z) == "air" then set(x, PF, z, VENT) end
	end end
	for i = 0, 4 do box(33 + i, PF, 42, 33 + i, PF + i, 43, FLESH) end
	-- the gusts: vents in the north wall, blowing south
	for _, x in ipairs({14, 24, 34}) do
		set(x, FG + 3, z2 + 1, GUST, 0)
	end
	light_walls(x1 - 1, PF, z1 - 1, x2 + 1, FG + 12, z2 + 1, 30)
	-- spore puffs drifting over it; the ganglion on the far ledge
	spawner(30, FG, 47, "spore_puff", 2, 12)
	spawner(16, FG, 55, "spore_puff", 2, 12)
	spawner(11, FG, 69, "ganglion", 1, 8)
	chest(9, FG + 1, 71, "armour", 1)
end

------------------------------------------------------------------------------
-- The Nest

local function nest()
	room(52, 49, 74, 73, FG, 6)
	-- egg sacs over the floor, in clutches, each by a stealthy spawner
	local clutches = {{56, 54}, {66, 55}, {58, 63}, {70, 64}, {63, 69}}
	for _, c in ipairs(clutches) do
		for _, dd in ipairs({{-1, 0}, {1, 1}, {0, -1}, {1, -1}, {-1, 1}}) do
			if rnd(3) > 0 then set(c[1] + dd[1], FG + 1, c[2] + dd[2], EGG) end
		end
		spawner(c[1], FG, c[2], "crawler", 3, 8, {stealth = true})
	end
	-- pillars of growth
	for _, p in ipairs({{60, 58}, {68, 60}, {56, 68}}) do box(p[1], FG + 1, p[2], p[1] + 1, FG + 6, p[2] + 1, FLESH) end
	spawner(54, FG, 71, "husk", 1, 9)
	spawner(72, FG, 72, "ganglion", 1, 8)
	chest(73, FG + 1, 51, "common", 3)
end

------------------------------------------------------------------------------
-- The way down, and the Heart

local function heart()
	-- the descending tunnel: west from the shell, down a block a step
	local x, y = 40, FG
	while y > FH do
		room(x - 1, 24, x, 26, y, 4)
		x = x - 1
		y = y - 1
	end
	-- then north into the chamber
	tunnel({{x, 25}, {x, 30}}, FH, 4)
	-- the chamber
	local x1, z1, x2, z2 = 24, 30, 52, 56
	line_with(x1, FH + 1, z1, x2, FH + 10, z2, WALLD)
	box(x1, FH, z1, x2, FH, z2, FLESH)
	air(x1, FH + 1, z1, x2, FH + 10, z2)
	-- the Heart: a great lump of flesh, round, a hollow inside it (the core),
	-- its way in shut with core
	local CX, CZr, CY = 38, 43, FH + 5
	for zz = CZr - 6, CZr + 6 do for yy = FH + 1, FH + 11 do for xx = CX - 6, CX + 6 do
		local r = math.sqrt((xx - CX) ^ 2 + ((yy - CY) * 1.2) ^ 2 + (zz - CZr) ^ 2)
		if r <= 5.6 + noise(xx, yy, zz, 2) * 0.8 then set(xx, yy, zz, HEART) end
	end end end
	air(CX - 1, FH + 1, CZr - 1, CX + 1, FH + 3, CZr + 1)
	-- the way into the core, from the south: core blocks
	box(CX - 1, FH + 1, CZr - 7, CX + 1, FH + 3, CZr - 2, CORE)
	for zz = CZr - 7, CZr - 2 do for yy = FH + 1, FH + 3 do for xx = CX - 1, CX + 1 do
		if get(xx, yy, zz) ~= CORE then set(xx, yy, zz, CORE) end
	end end end
	-- veins of glowing nodule over the Heart
	for zz = CZr - 7, CZr + 7 do for yy = FH + 1, FH + 12 do for xx = CX - 7, CX + 7 do
		if get(xx, yy, zz) == HEART and rnd(9) == 0 then set(xx, yy, zz, NODULE) end
	end end end
	-- the finish in the core, the chest beside it
	set(CX, FH + 1, CZr, FINISH)
	chest(CX - 1, FH + 1, CZr + 1, "finish", 2)
	-- the four nodules: spawners on the floor round it
	for _, p in ipairs({{CX, CZr - 9}, {CX + 8, CZr}, {CX, CZr + 8}, {CX - 8, CZr}}) do
		spawner(p[1], FH, p[2], "nodule", 1, 14)
	end
	-- tendrils round about, spitters on the walls, husks
	for _, p in ipairs({{30, 36}, {46, 36}, {30, 50}, {46, 50}}) do spawner(p[1], FH, p[2], "tendril", 1, 8) end
	spawner(23, FH + 5, 43, "spitter", 1, 16, {aloft = true})
	spawner(53, FH + 5, 43, "spitter", 1, 16, {aloft = true})
	spawner(34, FH, 33, "husk", 2, 12)
	light_walls(x1 - 1, FH, z1 - 1, x2 + 1, FH + 11, z2 + 1, 26)
	g.gated[#g.gated + 1] = {label = "the finish reachable without the core opening",
		target = {x = CX, y = FH + 1, z = CZr - 1},
		blocked = {{{x = CX - 1, y = FH + 1, z = CZr - 7}, {x = CX + 1, y = FH + 3, z = CZr - 2}}}}
end

------------------------------------------------------------------------------

-- A plan, north at the top: the camp's level, the Gut, the Heart
function g.plan()
	local out = {}
	for _, lv in ipairs({{"the surface", NF}, {"the Gut", FG + 1}, {"the Heart", FH + 1}}) do
		out[#out + 1] = "-- " .. lv[1]
		for z = SZ - 1, 0, -1 do
			local row = {}
			for x = 0, SX - 1 do
				local n = get(x, lv[2], z)
				local below = get(x, lv[2] - 1, z)
				local ch = "#"
				if n == "air" then ch = (below == ACID) and "~" or "." end
				if n == ACID then ch = "~" end
				if n == PAD or below == PAD then ch = "o" end
				if n == VALVE then ch = "V" elseif n == MEMBRANE then ch = "M" elseif n == SHELL then ch = "S"
				elseif n == CORE then ch = "C" elseif n == EGG then ch = "e" end
				row[#row + 1] = ch
			end
			out[#out + 1] = table.concat(row)
		end
	end
	return table.concat(out, "\n")
end

-- Extra checks (tools/adventures/generate_adventure): every choice of valves
-- a run can make still leads to every spawner, chest and the finish
-- Where a player can get to from `from`, falling any height (with damage) as
-- well as walking: the generator's walk drops at most three
local function reach_falling(O, from, blocked, t)
	local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
	local function is_blocked(p)
		for _, b in ipairs(blocked or {}) do
			local r = vector.subtract(p, O)
			if r.x >= b[1].x and r.x <= b[2].x and r.y >= b[1].y and r.y <= b[2].y and r.z >= b[1].z and r.z <= b[2].z then return true end
		end
	end
	local seen, queue, head = {[key(from)] = true}, {from}, 1
	while head <= #queue do
		local p = queue[head]; head = head + 1
		for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
			local nx, nz = p.x + d[1], p.z + d[2]
			if nx >= O.x and nx < O.x + SX and nz >= O.z and nz < O.z + SZ then
				local cands = {}
				-- up a block, level, or off an edge and down however far
				local up = {x = nx, y = p.y + 1, z = nz}
				if t.standable(up) and not t.walkable({x = p.x, y = p.y + 2, z = p.z}) then cands[#cands + 1] = up end
				-- (what is walled off for a check is solid: nobody falls through it)
				local function solid(c) return t.walkable(c) or is_blocked(c) end
				local q = {x = nx, y = p.y, z = nz}
				if not solid(q) and not solid({x = nx, y = p.y + 1, z = nz}) then
					while q.y > O.y + 1 and not solid({x = q.x, y = q.y - 1, z = q.z}) do q = {x = q.x, y = q.y - 1, z = q.z} end
					if t.standable(q) then cands[#cands + 1] = q end
				end
				for _, c in ipairs(cands) do
					if not is_blocked(c) and not seen[key(c)] then
						seen[key(c)] = true
						queue[#queue + 1] = c
					end
				end
			end
		end
	end
	return seen, key
end

function g.check_more(O, t)
	local start = vector.add(O, vector.round({x = g.info.start.x - 0.5, y = g.info.start.y, z = g.info.start.z - 0.5}))
	local targets = {}
	for _, s in ipairs(g.spawners) do
		if not s.aloft then targets[#targets + 1] = {p = vector.add(O, {x = s.x, y = s.y + 1, z = s.z}), what = "spawner " .. s.kind} end
	end
	for _, c in ipairs(g.chests) do targets[#targets + 1] = {p = vector.add(O, c), what = "chest " .. c.kind} end
	targets[#targets + 1] = {p = vector.add(O, g.finish), what = "finish"}
	-- falling any height, the gated places are still out of reach without
	-- their ways in
	for _, gt in ipairs(g.gated) do
		local seen, key = reach_falling(O, start, gt.blocked, t)
		t.say(("falling too: %s: %s"):format(gt.label, tostring(seen[key(vector.add(O, gt.target))] == true)))
	end
	for set_name, list in pairs(g.valves) do
		for i = 1, #list do
			local blocked = {}
			for j = 1, #list do
				if j ~= i then blocked[#blocked + 1] = {list[j].min, list[j].max} end
			end
			local seen, key = t.reach(O, start, blocked)
			local bad = {}
			for _, tg in ipairs(targets) do
				local near = false
				for dx = -2, 2 do for dz = -2, 2 do for dy = -1, 2 do
					if seen[key(vector.add(tg.p, {x = dx, y = dy, z = dz}))] then near = true end
				end end end
				if not near then bad[#bad + 1] = tg.what end
			end
			t.say(("valves %s, only #%d open: unreachable: %s"):format(set_name, i, #bad > 0 and table.concat(bad, ", ") or "none"))
		end
	end
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.spawners, g.chests, g.signs, g.valves, g.gated = {}, {}, {}, {}, {}
	seed = 7171
	ground()
	outside()
	camp()
	hangar()
	rind()
	borehole()
	gut()
	lung()
	nest()
	heart()
	light_walls(43, FG, 13, 77, FG + 9, 74, 20)
	light_walls(36, FG, 18, 46, FG + 5, 40, 16)
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
	for name in pairs(missing) do core.log("error", "[seed] no such node: " .. name) end
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
