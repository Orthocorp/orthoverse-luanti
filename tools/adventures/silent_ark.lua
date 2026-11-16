-- The Silent Ark: builds the ready-made adventure in a world, so that it can
-- be saved as adventures/silent_ark.ovt (the compact form; see
-- tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/silent_ark.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/silent_ark.json
--
-- Coordinates are relative to the origin: x east, z north, y up. It covers
-- the whole land (96 by 96). On the land's ground, a launch terminal (the
-- gate, the board, the sign). Under it the land is hollowed out from side to
-- side: space, 92 blocks square and 64 high, its walls black and starred, a
-- red giant on one side and a green and blue world below. In it hangs the
-- ark, east to west:
--   the dock (the start), a dead lift shaft in low gravity down to the hub;
--   the hub (low gravity), the spine west to the bridge's locked door, the
--     hydroponics dome south of it;
--   east of the hub, a bulkhead that shuts behind the party, the cryo bay
--     (pods that open as players pass), an airlock, and engineering
--     (airless, holed);
--   out of engineering's north side, a strut outside the hull (airless, low
--     gravity) the length of the ship, to the bridge's airlock;
--   the bridge: the ship's mind, kept by the Custodian. Its core pulled, the
--     bridge door and the pod bay's hatch in the hub's floor open;
--   below the hub, the pod bay: four escape pods (the finish).
-- Ranks 10 to 16, up to four players.

local g = {}

local SX, SY, SZ = 96, 80, 96
local NG = 72               -- the land's ground
local PF = NG + 1           -- where players stand on it
local DECK = 30             -- the ship's main deck (players stand at 31)

local STONE = "default:stone"
local DIRT = "default:dirt"
local GRASS = "default:dirt_with_grass"
local K = function(id) return "orthoverse_ark:" .. id end
local SC = function(id) return "orthoverse_scifi:" .. id end
local VAC, LOWG, VLOWG = K("vacuum"), K("lowg"), K("vacuum_lowg")
local HULL, RIB, DARK, FRAME, DK = K("hull"), K("hull_rib"), K("hull_dark"), K("frame"), K("deck")
local WIN, STRIP, FROST = K("window"), K("strip"), K("frost")
local SPAWNER = "orthoverse_monsters:spawner"
local CHEST = "orthoverse_loot:chest"
local STAIR = "stairs:stair_steelblock"

g.info = {
	name = "The Silent Ark",
	line = "A ship hangs dead in the dark above the world, and something aboard is still awake.",
	limit = 90,
	tags = {"sci-fi", "explore", "combat"},
	-- (the Adventures page, beside the cover picture: about 35 words, no answers)
	blurb = "Far above the Orthoverse a generation ship hangs in the dark, its colonists asleep for three hundred years. " ..
		"Its airlocks still open. Its lights still burn. And something aboard has noticed you come in.",
	rank_min = 10, rank_max = 16,
	party_max = 4,
	finish_xp = 600,
	size = {x = SX, y = SY, z = SZ},
	whole_land = true,
	ground = NG,
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 1, y = 0, z = 1},
	corner2 = {x = 94, y = 66, z = 94},
	start = {x = 48.5, y = 45, z = 50.5},
	arrival = {x = 48.5, y = PF, z = 3.5},
}
g.compact = true

g.spawners = {}
g.chests = {}
g.signs = {}
g.finish = {x = 35, y = 24, z = 42}
g.gate = {x = 48, y = PF, z = 13}
g.surface = PF
g.outside = {x = 30, y = PF, z = 4}
g.rim = {}
g.open_for_checks = {K("pod_door"), K("bridge_door")}
-- the pod bay: only by the stair under the hub's hatch
g.gated = {{label = "the pod bay, with the hub's hatch walled off", target = {x = 37, y = 23, z = 42},
	blocked = {{{x = 44, y = 22, z = 46}, {x = 52, y = 31, z = 50}}}}}

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
local function meta(x, y, z, fields) metas[#metas + 1] = {x = x, y = y, z = z, fields = fields, construct = true} end

local function hash(x, y, z)
	local n = (x * 374761393 + y * 668265263 + z * 1274126177) % 2147483648
	n = (n * 1103515245 + 12345) % 2147483648
	return (n % 10000) / 10000
end

local WALL = {n = 0, e = 1, s = 2, w = 3}       -- facedir: a panel on the wall to the north, ...
local FACE = {s = 0, w = 1, n = 2, e = 3}       -- facedir: a block whose front faces south, ...
local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}

local function sign(x, y, z, dir, text)
	set(x, y, z, "default:sign_wall_steel", SIGN_P2[dir])
	g.signs[#g.signs + 1] = {x = x, y = y, z = z, dir = dir, text = text:match("^[^\n]*")}
	meta(x, y, z, {text = text, infotext = '"' .. text .. '"'})
end

-- (at: where its monsters come, if not round it; aloft: not walked to)
local function spawner(x, y, z, kind, count, wake, at, aloft)
	set(x, y, z, SPAWNER)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {
		kind = "orthoverse_monsters:" .. kind, count = tostring(count), wake = tostring(wake),
		at = at and ("(%d,%d,%d)"):format(at.x - x, (at.y or y) - y, at.z - z) or "",
		per_player = "0.5",   -- half as many again for each player after the first
		infotext = "Monster spawner: " .. count .. " × " .. kind}}
	g.spawners[#g.spawners + 1] = {x = x, y = y, z = z, kind = kind, count = count, wake = wake, aloft = aloft}
end

local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot chest (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

local function terminal(x, y, z, face, text)
	set(x, y, z, K("terminal"), FACE[face])
	meta(x, y, z, {text = text, infotext = "Terminal"})
end

------------------------------------------------------------------------------
-- The land, and space under it

local function ground()
	box(0, 0, 0, SX - 1, NG - 5, SZ - 1, STONE)
	box(0, NG - 4, 0, SX - 1, NG - 1, SZ - 1, DIRT)
	box(0, NG, 0, SX - 1, NG, SZ - 1, GRASS)
end

-- Space: the shell black and starred, the inside empty (vacuum)
local S1, S2 = {x = 1, y = 1, z = 1}, {x = 94, y = 66, z = 94}

local function space()
	for x = S1.x, S2.x do
		for y = S1.y, S2.y do
			for z = S1.z, S2.z do
				local shell = x == S1.x or x == S2.x or y == S1.y or y == S2.y or z == S1.z or z == S2.z
				if shell then
					local r = hash(x, y, z)
					local b = K("space")
					if r > 0.985 then b = K("star_3") elseif r > 0.955 then b = K("star_2") elseif r > 0.92 then b = K("star_1") end
					set(x, y, z, b)
				else
					set(x, y, z, VAC)
				end
			end
		end
	end
	-- the red giant: half a ball on the east wall, high up and to the south
	local c, R = {x = 94, y = 46, z = 18}, 13
	for x = c.x - R, c.x do
		for y = c.y - R, c.y + R do
			for z = c.z - R, c.z + R do
				local d = math.sqrt((x - c.x) ^ 2 + (y - c.y) ^ 2 + (z - c.z) ^ 2)
				if d <= R and y >= S1.y and y <= S2.y and z >= S1.z and z <= S2.z then
					set(x, y, z, d < R * 0.45 and K("giant_core") or d < R * 0.8 and K("giant") or K("giant_edge"))
				end
			end
		end
	end
	-- the world below: the top of a ball rising from the floor, north-west
	local p, PR = {x = 18, y = -4, z = 76}, 17
	for x = p.x - PR, p.x + PR do
		for y = S1.y, p.y + PR do
			for z = p.z - PR, p.z + PR do
				local d = math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2 + (z - p.z) ^ 2)
				if d <= PR and d > PR - 2.5 and x >= S1.x and x <= S2.x and z >= S1.z and z <= S2.z then
					local n = hash(math.floor(x / 4), math.floor(y / 4), math.floor(z / 4))
					local b = n > 0.55 and K("planet_land") or K("planet_sea")
					if hash(x, y, z) > 0.86 then b = K("planet_cloud") end
					set(x, y, z, b)
				end
			end
		end
	end
end

------------------------------------------------------------------------------
-- The ship: rooms of hull hung in space

-- A room: x1..x2, z1..z2 inside, floor at fy, h blocks high inside; its
-- shell (walls, floor, roof) only where there is space (vacuum) or nothing:
-- a room against another keeps the other's wall. fill: what is inside (air,
-- or low gravity, or vacuum)
local function room(x1, z1, x2, z2, fy, h, fill, wall, floor)
	for x = x1 - 1, x2 + 1 do
		for z = z1 - 1, z2 + 1 do
			for y = fy, fy + h + 1 do
				local edge = x < x1 or x > x2 or z < z1 or z > z2 or y == fy or y == fy + h + 1
				if edge then
					local here = get(x, y, z)
					if here == VAC or here == VLOWG then
						if y == fy then set(x, y, z, floor or DK)
						elseif y == fy + h + 1 then set(x, y, z, wall or HULL)
						else set(x, y, z, wall or ((y - fy) % 4 == 0 and RIB or HULL)) end
					end
				else
					set(x, y, z, fill or "air")
				end
			end
		end
	end
end

-- Windows: every other block of a wall's middle rows (x1..x2 or z1..z2 at
-- the wall's x or z), from y1 to y2
local function windows(x1, z1, x2, z2, y1, y2, every)
	every = every or 2
	for x = x1, x2 do
		for z = z1, z2 do
			if ((x - x1) + (z - z1)) % every == 0 then
				for y = y1, y2 do set(x, y, z, WIN) end
			end
		end
	end
end

-- A doorway: through the wall's blocks, the floor kept
local function door(x1, z1, x2, z2, fy, h, fill)
	box(x1, fy + 1, z1, x2, fy + (h or 3), z2, fill or "air")
	box(x1, fy, z1, x2, fy, z2, DK)
end

-- Light strips along a room's roof
local function lights(x1, z1, x2, z2, y, every)
	for x = x1, x2, every or 4 do
		for z = z1, z2, every or 4 do set(x, y, z, STRIP) end
	end
end

------------------------------------------------------------------------------
-- The launch terminal, on the land

local function terminal_building()
	-- the pad: a ring of hazard plating, a mast with a light
	box(38, NG, 4, 58, NG, 22, K("deck"))
	for x = 38, 58 do set(x, NG, 4, K("hazard")); set(x, NG, 22, K("hazard")) end
	for z = 4, 22 do set(38, NG, z, K("hazard")); set(58, NG, z, K("hazard")) end
	-- the building: hull, windows, open to the south
	box(41, PF, 8, 55, PF + 3, 18, HULL)
	box(42, PF, 9, 54, PF + 3, 17, "air")
	box(41, PF + 4, 8, 55, PF + 4, 18, RIB)
	box(42, NG, 9, 54, NG, 17, DK)
	for x = 43, 53, 2 do box(x, PF + 1, 18, x, PF + 2, 18, WIN) end
	for x = 43, 53, 4 do box(x, PF + 1, 8, x, PF + 2, 8, WIN) end
	box(47, PF, 8, 49, PF + 2, 8, "air")     -- the way in
	box(47, NG, 8, 49, NG, 8, DK)
	lights(44, 11, 52, 15, PF + 4, 4)
	-- the lift: a shaft that goes nowhere a player can follow (the gate takes them)
	box(46, PF, 17, 50, PF + 3, 17, K("hazard"))
	box(47, PF, 17, 49, PF + 2, 17, K("bulkhead"))
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(52, PF, 12, "orthoverse_adventure:board", 0)
	sign(45, PF + 1, 7, "+z", "THE SILENT ARK\nA ship hangs dead in the dark above the world, and something aboard is still awake.\n" ..
		"Ranks 10 to 16. Up to four together.")
	-- the mast
	box(56, PF, 20, 56, PF + 5, 20, FRAME)
	set(56, PF + 6, 20, STRIP)
	for _, x in ipairs({38, 58}) do set(x, PF, 4, "default:mese_post_light") end
end

------------------------------------------------------------------------------
-- The dock (the start) and the dead lift shaft

local function dock()
	room(44, 44, 52, 52, 44, 4, "air")
	windows(43, 45, 43, 51, 46, 47); windows(53, 45, 53, 51, 46, 47)
	windows(45, 43, 51, 43, 46, 47); windows(45, 53, 51, 53, 46, 47)
	lights(45, 45, 51, 51, 49, 3)
	-- the tether up to the world above: a ribbed column to the roof of space
	box(48, 50, 48, 48, S2.y - 1, 48, RIB)
	for y = 52, S2.y - 1, 6 do box(47, y, 47, 49, y, 49, FRAME) end
	-- the hole in its floor, down the shaft
	box(47, 44, 47, 49, 44, 49, LOWG)
	terminal(44, 45, 52, "s", "ARK CONCORD - DOCK\nLast arrival: shuttle Wren, year 12 of the voyage.\n" ..
		"Departures since: none.\nDock seal: held by the MIND.")
	set(52, 46, 46, K("air_station"), FACE.w)
	chest(45, 45, 45, "common", 0)
	set(48, 45, 52, K("tether"))
end

-- The shaft: three by three, low gravity, ledges to stand on (the lift's
-- broken platforms) down to the hub
local function shaft()
	room(47, 47, 49, 49, 35, 8, LOWG)
	box(47, 35, 47, 49, 35, 49, LOWG)      -- open into the hub below
	box(47, 44, 47, 49, 44, 49, LOWG)      -- and into the dock above
	windows(46, 47, 46, 49, 37, 42, 3); windows(50, 47, 50, 49, 37, 42, 3)
	box(47, 41, 47, 48, 41, 49, FRAME)
	box(48, 38, 47, 49, 38, 49, FRAME)
	box(47, 35, 47, 48, 35, 49, FRAME)
	box(49, 32, 47, 49, 32, 49, FRAME)     -- (the last, in the hub)
end

------------------------------------------------------------------------------
-- The hub, the spine west, the hydroponics dome

local function hub()
	room(44, 44, 52, 52, DECK, 4, LOWG)
	box(47, 35, 47, 49, 35, 49, LOWG)
	windows(45, 43, 51, 43, 32, 33); windows(45, 53, 51, 53, 32, 33)
	lights(44, 44, 52, 52, 35, 3)
	box(47, 35, 47, 49, 35, 49, LOWG)
	terminal(44, 31, 44, "n", "MIND TO ALL DECKS\nOrbit holds. Survey of the world below continues.\n" ..
		"Sleepers remain asleep until the survey is complete.\nSurvey day 104,211.")
	set(53, 32, 45, K("air_station"), FACE.w)
	-- two hunter drones, up as soon as anyone is down the shaft
	spawner(50, DECK, 51, "hunter_drone", 2, 7, {x = 46, z = 46})
	-- the hatch in the floor, over the stair to the pod bay
	box(45, DECK, 47, 51, DECK, 49, K("pod_door"))
	-- the bulkhead east, open (it shuts behind the party)
	box(53, DECK + 1, 47, 53, DECK + 3, 49, K("bulkhead_open"))
	box(53, DECK, 47, 53, DECK, 49, DK)
	box(53, DECK + 4, 46, 53, DECK + 4, 50, K("hazard"))
end

local function spine_west()
	room(19, 47, 43, 49, DECK, 3, "air")
	door(43, 47, 43, 49, DECK, 3, LOWG)
	for x = 20, 42, 3 do set(x, 32, 46, WIN); set(x, 32, 50, WIN) end
	lights(20, 48, 42, 48, 34, 4)
	-- the bridge door, locked
	box(18, DECK + 1, 47, 18, DECK + 3, 49, K("bridge_door"))
	box(18, DECK, 47, 18, DECK, 49, DK)
	-- south to the dome
	room(28, 42, 30, 46, DECK, 3, "air")
	door(28, 46, 30, 46, DECK, 3)
end

-- The hydroponics dome: half a ball of windows over a dead garden
local function dome()
	local c, R = {x = 29, y = DECK, z = 31}, 9
	for x = c.x - R - 1, c.x + R + 1 do
		for z = c.z - R - 1, c.z + R + 1 do
			for y = c.y, c.y + R + 1 do
				local d = math.sqrt((x - c.x) ^ 2 + (y - c.y) ^ 2 + (z - c.z) ^ 2)
				local flat = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
				if y == c.y and flat <= R + 0.5 then
					set(x, y, z, (flat > R - 0.5) and DK or "default:dry_dirt")
				elseif y > c.y and d <= R - 0.5 then
					set(x, y, z, "air")
				elseif y > c.y and d <= R + 0.5 then
					-- ribs every so often, glass between
					local rib = (math.abs(x - c.x) % 5 == 0 and math.abs(z - c.z) < 2) or (math.abs(z - c.z) % 5 == 0 and math.abs(x - c.x) < 2)
					set(x, y, z, (rib or y == c.y + 1) and FRAME or WIN)
				end
			end
		end
	end
	-- the way in from the spine's corridor
	door(28, 40, 30, 41, DECK, 3)
	box(28, DECK, 40, 30, DECK, 41, DK)
	-- the dead garden: beds, dead plants, the overgrowth
	for x = c.x - 6, c.x + 6, 3 do
		for z = c.z - 6, c.z + 6 do
			if math.abs(z - c.z) > 1 and math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2) < R - 1.5 then
				set(x, DECK + 1, z, hash(x, 1, z) > 0.5 and K("dead_plant") or "default:dry_shrub")
			end
		end
	end
	for _, p in ipairs({{24, 27}, {25, 27}, {24, 28}, {34, 36}, {34, 35}}) do set(p[1], DECK + 1, p[2], K("overgrowth")) end
	box(25, DECK + 2, 27, 25, DECK + 2, 27, K("overgrowth"))
	terminal(29, DECK + 1, 22, "n", "BOTANIST'S NOTE\nThe mind has cut the water to the dome again. It says the " ..
		"colonists will not need food until the survey is finished.\nIt has said that for ninety years.")
	set(38, DECK + 2, 31, K("air_station"), FACE.w)
	chest(22, DECK + 1, 31, "weapon", 1)
	set(29, DECK + 1, 31, K("strip"))
	spawner(29, DECK, 37, "hunter_drone", 2, 7, {x = 29, z = 30})
	spawner(30, DECK, 37, "enforcer", 1, 7, {x = 26, z = 30})
end

------------------------------------------------------------------------------
-- The cryo bay, the airlock, engineering

local function cryo()
	room(54, 38, 74, 58, DECK, 6, "air", nil, DK)
	-- the way in from the hub, and the seal plates just inside
	box(55, DECK, 46, 57, DECK, 50, K("seal_plate"))
	-- frosted walls, windows high up, dim blue light
	for x = 54, 74 do
		if x % 3 == 0 then set(x, 35, 37, WIN); set(x, 35, 59, WIN) end
	end
	lights(55, 40, 73, 56, 37, 3)
	-- pods: two rows along the north and south walls, facing in
	for x = 56, 72, 2 do
		set(x, DECK + 1, 58, K("cryo_pod"), FACE.s); set(x, DECK + 2, 58, K("cryo_pod_top"), FACE.s)
		set(x, DECK + 1, 38, K("cryo_pod"), FACE.n); set(x, DECK + 2, 38, K("cryo_pod_top"), FACE.n)
		set(x + 1, DECK + 1, 58, FROST); set(x + 1, DECK + 2, 58, FROST)
		set(x + 1, DECK + 1, 38, FROST); set(x + 1, DECK + 2, 38, FROST)
	end
	-- and an island down the middle, back to back
	for x = 60, 68, 2 do
		set(x, DECK + 1, 44, K("cryo_pod"), FACE.s); set(x, DECK + 2, 44, K("cryo_pod_top"), FACE.s)
		set(x, DECK + 1, 52, K("cryo_pod"), FACE.n); set(x, DECK + 2, 52, K("cryo_pod_top"), FACE.n)
	end
	box(60, DECK + 1, 45, 68, DECK + 2, 51, FROST)
	box(60, DECK + 3, 44, 68, DECK + 3, 52, HULL)
	terminal(59, DECK + 1, 48, "w", "CRYO CONTROL\nPod 0412: revival aborted.\nPod 0413: revival aborted.\n" ..
		"Pod 0414: revival aborted (subject restless).\nThaw cycles incomplete: 611.\nMIND: hold all pods.")
	chest(73, DECK + 1, 40, "armour", 3)
	spawner(57, DECK, 41, "enforcer", 2, 6, {x = 70, z = 48})
	-- out east
	door(75, 47, 75, 49, DECK, 3)
	box(75, DECK + 1, 47, 75, DECK + 3, 49, K("bulkhead_open"))
	box(75, DECK + 4, 46, 75, DECK + 4, 50, K("hazard"))
end

local function airlock()
	room(76, 46, 79, 50, DECK, 3, "air")
	box(77, DECK, 47, 79, DECK, 49, K("seal_plate"))
	set(78, DECK + 2, 51, K("air_station"), FACE.s)
	set(78, DECK + 1, 48, K("tether"))
	terminal(76, DECK + 1, 51, "s", "AIRLOCK 7 (ENGINEERING)\nHULL BREACH BEYOND THIS POINT. NO ATMOSPHERE.\n" ..
		"Last cycled: chief engineer Okafor, survey day 98,330.")
	door(80, 47, 80, 49, DECK, 3, VAC)
end

local function engineering()
	room(81, 40, 91, 56, DECK, 6, VAC, nil, DK)
	door(80, 47, 80, 49, DECK, 3, VAC)
	-- the breach: a hole in the south wall, scorched round it
	for x = 83, 89 do for y = DECK + 1, DECK + 5 do
		local d = math.abs(x - 86) + math.abs(y - (DECK + 3))
		if d <= 3 then set(x, y, 39, VAC) elseif d <= 4 then set(x, y, 39, SC("hull_scorched")) end
	end end
	-- dead reactors, consoles, crates
	for _, z in ipairs({44, 52}) do
		box(88, DECK + 1, z - 1, 90, DECK + 5, z + 1, DARK)
		box(89, DECK + 2, z, 89, DECK + 4, z, SC("reactor"))
	end
	for _, p in ipairs({{83, 43}, {84, 43}, {83, 54}, {85, 55}, {86, 41}}) do set(p[1], DECK + 1, p[2], SC("crate")) end
	set(83, DECK + 2, 43, SC("crate"))
	-- the turrets' ledges
	box(81, DECK + 3, 40, 83, DECK + 3, 42, FRAME)
	box(81, DECK + 3, 54, 83, DECK + 3, 56, FRAME)
	spawner(81, DECK + 3, 40, "heavy_turret", 1, 9, {x = 82, y = DECK + 3, z = 41}, true)
	spawner(81, DECK + 3, 56, "heavy_turret", 1, 9, {x = 82, y = DECK + 3, z = 55}, true)
	lights(82, 42, 90, 54, DECK + 7, 4)
	set(80, DECK + 2, 45, K("air_station"), FACE.e)
	set(85, DECK + 2, 57, K("air_station"), FACE.s)
	set(84, DECK + 1, 48, K("tether"))
	terminal(92, DECK + 1, 48, "w", "CHIEF ENGINEER'S LOG\nI have cut the mind out of the pod bay circuits. It holds the bay " ..
		"from the bridge, and the way forward inside is sealed.\nIts keeper never sleeps.\nGoing outside.")
	chest(90, DECK + 1, 41, "common", 3)
	spawner(83, DECK, 49, "enforcer", 1, 6, {x = 86, z = 48})
	spawner(85, DECK, 47, "hunter_drone", 2, 6, {x = 86, y = DECK + 2, z = 50})
	-- the hatch north, out onto the strut
	door(86, 57, 88, 57, DECK, 3, VLOWG)
	box(86, DECK + 4, 57, 88, DECK + 4, 57, K("hazard"))
end

------------------------------------------------------------------------------
-- The strut outside the hull: north from engineering, west the length of
-- the ship, south to the bridge's airlock. A walkway three wide with rails,
-- in vacuum and low gravity; over it four blocks of that, then space.

local function strut()
	-- the walkway: three wide along two legs (north out of engineering, then
	-- west the length of the ship to the bridge's airlock)
	local walk = {}
	local function leg(x1, z1, x2, z2)
		for x = x1, x2 do for z = z1, z2 do walk[x .. "," .. z] = true end end
	end
	leg(86, 58, 88, 63)
	leg(10, 61, 88, 63)
	for k in pairs(walk) do
		local x, z = k:match("^(%-?%d+),(%-?%d+)$")
		x, z = tonumber(x), tonumber(z)
		if get(x, DECK, z) == VAC then set(x, DECK, z, DK) end
		for y = DECK + 1, DECK + 4 do if get(x, y, z) == VAC then set(x, y, z, VLOWG) end end
	end
	-- its edges: a frame with a rail on it (not across the ways on and off)
	for k in pairs(walk) do
		local x, z = k:match("^(%-?%d+),(%-?%d+)$")
		x, z = tonumber(x), tonumber(z)
		for dx = -1, 1 do for dz = -1, 1 do
			local ex, ez = x + dx, z + dz
			if not walk[ex .. "," .. ez] and get(ex, DECK, ez) == VAC then
				-- (a light let into the frame every so often)
				set(ex, DECK, ez, ((ex + ez) % 7 == 0) and STRIP or FRAME)
				set(ex, DECK + 1, ez, K("rail"))
				for y = DECK + 2, DECK + 4 do if get(ex, y, ez) == VAC then set(ex, y, ez, VLOWG) end end
				-- the struts that hold it, below
				if (ex + ez) % 8 == 0 then
					for y = DECK - 5, DECK - 1 do if get(ex, y, ez) == VAC then set(ex, y, ez, RIB) end end
				end
			end
		end end
	end
	-- tether marks along it
	for _, x in ipairs({80, 62, 44, 26, 14}) do set(x, DECK + 1, 62, K("tether")) end
	set(87, DECK + 1, 59, K("tether"))
	-- the drones that hunt along it
	spawner(50, DECK, 61, "hunter_drone", 2, 9, {x = 44, y = DECK + 2, z = 62})
	spawner(30, DECK, 61, "hunter_drone", 2, 9, {x = 24, y = DECK + 2, z = 62})
end

------------------------------------------------------------------------------
-- The bridge, and its airlock

local function bridge()
	-- the airlock: in from the strut, the seal plates, the bulkhead behind
	room(9, 58, 13, 60, DECK, 3, "air")
	door(10, 61, 12, 61, DECK, 3, VLOWG)
	box(10, DECK + 1, 61, 12, DECK + 3, 61, K("bulkhead_open"))
	box(10, DECK, 58, 12, DECK, 60, K("seal_plate"))
	set(8, DECK + 2, 59, K("air_station"), FACE.e)
	set(11, DECK + 1, 59, K("tether"))
	-- the bridge: windows west and north on the world below
	room(5, 40, 17, 56, DECK, 6, "air")
	door(10, 57, 12, 57, DECK, 3)
	for z = 41, 55 do for y = DECK + 2, DECK + 5 do set(4, y, z, WIN) end end
	for x = 5, 9 do for y = DECK + 2, DECK + 5 do set(x, y, 57, WIN) end end
	for x = 13, 17 do for y = DECK + 2, DECK + 5 do set(x, y, 57, WIN) end end
	lights(6, 42, 16, 54, DECK + 7, 3)
	-- consoles in rows facing the windows
	for _, z in ipairs({43, 45, 51, 53}) do
		for x = 7, 9 do set(x, DECK + 1, z, SC("console"), FACE.w) end
	end
	-- the mind: its core on a dais
	box(12, DECK + 1, 46, 14, DECK + 1, 50, DARK)
	set(13, DECK + 2, 48, K("mind_core"))
	box(12, DECK + 5, 46, 14, DECK + 6, 50, DARK)
	set(13, DECK + 4, 48, STRIP)
	terminal(14, DECK + 2, 46, "s", "MIND\nSurvey day 104,212.\nThe world below is unsuitable.\nIt has always been unsuitable.\n" ..
		"Keep them sleeping.")
	chest(16, DECK + 1, 41, "armour", 3)
	-- its keeper, its guards, two turrets on the console rows
	spawner(16, DECK, 48, "custodian", 1, 12, {x = 10, z = 48})
	spawner(16, DECK, 47, "enforcer", 2, 12, {x = 10, z = 44})
	spawner(6, DECK, 43, "heavy_turret", 1, 12, {x = 8, y = DECK + 1, z = 43})
	spawner(6, DECK, 53, "heavy_turret", 1, 12, {x = 8, y = DECK + 1, z = 53})
end

------------------------------------------------------------------------------
-- The pod bay, under the hub, and its four pods

local function pod(x1, z1, entry, face_x)
	-- a pod: three by three, two high inside, a window out, the handle
	room(x1, z1, x1 + 2, z1 + 2, 22, 3, "air", RIB, DK)
	set(x1 + 1, 23 + 1, face_x < 0 and z1 - 1 or z1 + 3, WIN)
	local hx = face_x < 0 and x1 or x1 + 2
	local hx_wall = face_x < 0 and x1 - 1 or x1 + 3
	for z = z1, z1 + 2 do set(hx_wall, 24, z, WIN) end
	set(hx_wall, 24, z1 + 1, K("launch"), face_x < 0 and FACE.e or FACE.w)
	box(entry, 23, z1 + 1, entry, 24, z1 + 1, "air")
	box(entry, 22, z1 + 1, entry, 22, z1 + 1, DK)
	set(entry, 25, z1 + 1, K("hazard"))
end

local function pod_bay()
	room(40, 38, 56, 58, 22, 5, "air")
	-- windows in the floor, on the world below
	for x = 42, 54, 4 do for z = 40, 56, 4 do set(x, 22, z, WIN) end end
	lights(41, 39, 55, 57, 28, 3)
	-- the stair down from the hub's hatch (it descends eastward)
	for k = 1, 7 do
		local x, y = 44 + k, DECK - k
		box(x, y + 1, 47, x, DECK - 1, 49, "air")
		box(x, y, 47, x, y, 49, STAIR, 3)
	end
	box(45, 28, 46, 51, 29, 46, HULL); box(45, 28, 50, 51, 29, 50, HULL)
	box(44, 29, 47, 44, 29, 49, HULL); box(52, 29, 47, 52, 29, 49, HULL)
	-- four pods, two each side
	pod(36, 41, 39, -1)
	pod(36, 53, 39, -1)
	pod(58, 41, 57, 1)
	pod(58, 53, 57, 1)
	terminal(48, 24, 59, "s", "POD BAY\nEscape pods 1 to 4: fuelled.\nCourse set: the world below.\nLaunch: MIND ONLY.")
	chest(48, 23, 39, "finish", 0)
	spawner(42, 22, 48, "sleeper", 2, 7, {x = 47, z = 54})
	spawner(54, 22, 48, "enforcer", 1, 7, {x = 50, z = 42})
end

------------------------------------------------------------------------------
-- The plan, for plan.txt: the main deck and the pod bay from above

function g.plan()
	local out = {}
	for _, lv in ipairs({{"surface", PF}, {"dock", 45}, {"main deck", DECK + 1}, {"pod bay", 23}}) do
		out[#out + 1] = "== " .. lv[1]
		for z = SZ - 1, 0, -1 do
			local row = {}
			for x = 0, SX - 1 do
				local n, fl = get(x, lv[2], z), get(x, lv[2] - 1, z)
				local ch
				if n == "air" or n == LOWG then ch = fl == "air" and " " or "."
				elseif n == VAC then ch = " "
				elseif n == VLOWG then ch = ":"
				elseif n == SPAWNER or fl == SPAWNER then ch = "M"
				elseif n == CHEST then ch = "c"
				elseif n:find("cryo_pod") then ch = "P"
				elseif n:find("launch") then ch = "L"
				elseif n:find("bulkhead") then ch = "B"
				elseif n:find("door") then ch = "D"
				elseif n == WIN then ch = "o"
				else ch = "#" end
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
	local start = vector.add(O, {x = 48, y = 45, z = 50})
	local seen, key = t.reach(O, start)
	local function at(x, y, z)
		for dx = -1, 1 do for dz = -1, 1 do
			if seen[key(vector.add(O, {x = x + dx, y = y, z = z + dz}))] then return true end
		end end
		return false
	end
	t.say("down the shaft to the hub: " .. tostring(at(46, 31, 46)))
	t.say("the hydroponics dome: " .. tostring(at(29, 31, 33)))
	t.say("the cryo bay: " .. tostring(at(64, 31, 41)))
	t.say("engineering: " .. tostring(at(85, 31, 48)))
	t.say("the strut, half way: " .. tostring(at(48, 31, 62)))
	t.say("the bridge: " .. tostring(at(10, 31, 48)))
	t.say("the pod bay: " .. tostring(at(48, 23, 44)))
	for _, p in ipairs({{37, 42}, {37, 54}, {59, 42}, {59, 54}}) do
		t.say(("the pod at %d,%d: %s"):format(p[1], p[2], tostring(at(p[1], 23, p[2]))))
	end
	t.say("ark checks done")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.chests, g.signs, g.spawners = {}, {}, {}
	ground()
	space()
	terminal_building()
	-- the ship, inside out: the rooms that others lean on first
	pod_bay()
	hub()
	shaft()
	dock()
	spine_west()
	dome()
	cryo()
	airlock()
	engineering()
	bridge()
	strut()
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
	for name in pairs(missing) do core.log("error", "[silent_ark] no such node: " .. name) end
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
