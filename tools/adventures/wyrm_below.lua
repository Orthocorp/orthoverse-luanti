-- The Wyrm Below: builds the ready-made adventure in a world, so that it can
-- be saved as adventures/wyrm_below.ovt (the compact form: it is big; see
-- tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/wyrm_below.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/wyrm_below.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 72 (players stand at y = 73); everything is below it, down to
-- the template's floor at y = 0.
--
--   Karn Dolm (on the ground, outside the dungeon): the ruin of a hold, its
--     old stair under a steel grate, the gate, the board and one sign.
--   The upper halls (floor 60): the hold's own rooms, built of cobble, held
--     by goblins: the stair hall (the start), the pillared hall, the guard
--     room (west), the barracks (east), and a landing with the stair down.
--   The delvings (floor 47): the mine below, rough rock and timber, held by
--     orcs: the long gallery, the mess (west), the ore chamber (north) and
--     the forge (east), whose back wall has fallen into the caves.
--   The caves: winding down and down, past a goblin camp and an orc post.
--   The lair (floor 4): a great cavern, pillars of rock, the hoard, and the
--     wyrm asleep on it. East of it a hall of fire: a lake of lava with the
--     stubs of a bridge on either shore, and beyond it, the finish.
--
-- The wyrm drops its ring when it dies; thrown into the lake, it wakes the
-- sleeping bridge (orthoverse_props), and the bridge rises across. Party of
-- two to six, ranks 6 to 12. Monsters: goblins, goblin cutthroats, orcs, deep
-- orcs, and the wyrm.

local g = {}

local SX, SY, SZ = 80, 80, 80
local NG, NF = 72, 73       -- the land's ground, and where players stand on it
local F1 = 60               -- the upper halls' floor (players stand at 61)
local F2 = 47               -- the delvings' floor
local FL = 4                -- the lair's floor

local ROCK = "default:stone"
local COBBLE = "default:cobble"
local MOSSY = "default:mossycobble"
local BRICK = "default:stonebrick"
local FLOOR = "default:stone_block"
local GRAVEL = "default:gravel"
local LOG = "default:tree"
local PLANK = "default:wood"
local LAMP = "default:meselamp"
local SIGN = "default:sign_wall_wood"
local SPAWNER = "orthoverse_monsters:spawner"
local CHEST = "orthoverse_loot:chest"
local FINISH = "orthoverse_adventure:finish"
local LAVA = "default:lava_source"
local SLEEPING = "orthoverse_props:wyrm_lava"
local STILL = "orthoverse_props:still_lava"
local BRIDGE = "orthoverse_props:wyrm_bridge"
local OBSIDIAN = "default:obsidian"
local OBRICK = "default:obsidianbrick"

g.info = {
	name = "The Wyrm Below",
	line = "Goblins and orcs hold the old halls under Karn Dolm, and far below them a wyrm sleeps on a ring made " ..
		"in the lake of fire. The lake keeps what lies beyond: give the ring back to it.",
	limit = 90,
	rank_min = 6, rank_max = 12,
	size = {x = SX, y = SY, z = SZ},
	ground = NG,
	-- everything below the ground is the template's: cleared first
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 1, y = 0, z = 1},
	corner2 = {x = SX - 2, y = NG, z = SZ - 2},
	start = {x = 40.5, y = F1 + 1, z = 21.5},
	arrival = {x = 40.5, y = NF, z = 2.5},
}
g.compact = true

-- Where things are, for tests
g.spawners = {}
g.chests = {}
g.signs = {}
g.finish = {x = 75, y = FL + 1, z = 44}
g.gate = {x = 40, y = NF, z = 7}
g.surface = NF
g.outside = {x = 6, y = NF, z = 4}
g.rim = {}
-- The far shore must be out of reach with the bridge walled off (the checks
-- raise it first, as the ring does)
g.swap_for_checks = {[SLEEPING] = BRIDGE}
g.gated = {{label = "the finish reachable without the bridge", target = {x = 74, y = FL + 1, z = 44},
	blocked = {{{x = 61, y = 0, z = 43}, {x = 71, y = 10, z = 45}}}}}

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

local function get(x, y, z) return grid[idx(x, y, z)] end

local function box(x1, y1, z1, x2, y2, z2, name, param2)
	for z = z1, z2 do for y = y1, y2 do for x = x1, x2 do set(x, y, z, name, param2) end end end
end

local function air(x1, y1, z1, x2, y2, z2) box(x1, y1, z1, x2, y2, z2, "air") end

-- Only where there is still bare rock (so a lining never fills a room)
local function rock_to(x, y, z, name)
	if inside(x, y, z) and get(x, y, z) == ROCK then set(x, y, z, name) end
end

-- A repeatable roll of the dice, so every build is the same
local seed = 4242
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end

-- Smooth noise in 3D, 0 to 1 (for rough cave walls)
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

-- A loot chest standing on the floor; facing: param2
local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot chest (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

------------------------------------------------------------------------------
-- The ground: rock, darker and harder lower down, with ore here and there

local function ground()
	for y = 0, NG - 4 do
		for z = 0, SZ - 1 do for x = 0, SX - 1 do
			local r = rnd(400)
			local name = ROCK
			if r == 0 then name = "default:stone_with_coal"
			elseif r == 1 and y < 50 then name = "default:stone_with_iron"
			elseif r == 2 and y < 30 then name = "default:stone_with_gold"
			elseif r < 6 then name = "default:stone_with_tin" end
			set(x, y, z, name)
		end end
	end
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, "default:dirt")
	box(0, NG, 0, SX - 1, NG, SZ - 1, "default:dirt_with_grass")
end

------------------------------------------------------------------------------
-- Karn Dolm: the ruin on the ground

local function ruin()
	-- broken walls round a yard, x 30 to 50, z 4 to 18; the way in on the south
	local function wall(x1, z1, x2, z2)
		for z = z1, z2 do for x = x1, x2 do
			local h = 1 + rnd(4)
			if (x + z) % 7 == 0 then h = 0 end
			for y = NF, NF + h - 1 do set(x, y, z, rnd(3) == 0 and MOSSY or BRICK) end
		end end
	end
	wall(30, 4, 37, 4); wall(43, 4, 50, 4)
	wall(30, 18, 50, 18)
	wall(30, 5, 30, 17); wall(50, 5, 50, 17)
	-- the yard: old flagstones, grass coming through
	for z = 5, 17 do for x = 31, 49 do
		set(x, NG, z, rnd(4) == 0 and "default:dirt_with_grass" or FLOOR)
	end end
	-- the old stair down, under a steel grate that does not open: the way in
	-- is the gate
	for x = 38, 42 do for z = 12, 15 do set(x, NG, z, "doors:trapdoor_steel", 0) end end
	box(37, NG - 3, 11, 43, NG - 1, 16, COBBLE)
	air(38, NG - 1, 12, 42, NG - 1, 15)
	box(38, NG - 2, 12, 42, NG - 2, 15, GRAVEL)
	-- a fallen pillar, a standing one
	box(34, NF, 9, 34, NF + 4, 9, BRICK); set(34, NF + 5, 9, "stairs:slab_stonebrick")
	box(45, NF, 14, 47, NF, 14, BRICK)
	-- the gate and the board, the sign on the standing wall behind them
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(37, NF, 7, "orthoverse_adventure:board", 0)
	box(42, NF, 9, 44, NF + 2, 9, BRICK)
	sign(43, NF + 1, 8, "+z", "THE WYRM BELOW\nGoblins and orcs hold the old halls under Karn Dolm, and far below them " ..
		"a wyrm sleeps on a ring made in the lake of fire. The lake keeps what lies beyond: give the ring back to it." ..
		"\nRight-click the gate to go in. Ranks 6 to 12.")
	for _, p in ipairs({{31, 5}, {49, 5}}) do set(p[1], NF, p[2], "default:mese_post_light") end
end

------------------------------------------------------------------------------
-- The upper halls: built rooms, as Minetest's own dungeons are built

-- A room: floor at fy, air for h above, its walls lined (where rock) with
-- cobble and moss
local function hall(x1, z1, x2, z2, fy, h, floor, lamps)
	for z = z1 - 1, z2 + 1 do for y = fy, fy + h + 1 do for x = x1 - 1, x2 + 1 do
		rock_to(x, y, z, rnd(3) == 0 and MOSSY or COBBLE)
	end end end
	box(x1, fy, z1, x2, fy, z2, floor or FLOOR)
	air(x1, fy + 1, z1, x2, fy + h, z2)
	if lamps then
		for z = z1 + 2, z2 - 2, lamps do for x = x1 + 2, x2 - 2, lamps do set(x, fy + h + 1, z, LAMP) end end
	end
end

local function upper()
	-- the stair hall: the start. Its old stair up ends in fallen rock
	hall(34, 18, 46, 26, F1, 5, FLOOR, 4)
	for k = 0, 3 do
		box(39, F1 + 1 + k, 17 - k, 41, F1 + 1 + k, 17 - k, "stairs:stair_cobble", 0)
		air(39, F1 + 2 + k, 17 - k, 41, F1 + 5 + k, 17 - k)
	end
	box(39, F1 + 5, 13, 41, F1 + 8, 13, GRAVEL)
	box(38, F1 + 1, 14, 38, F1 + 8, 17, COBBLE); box(42, F1 + 1, 14, 42, F1 + 8, 17, COBBLE)
	-- north to the pillared hall
	hall(39, 27, 41, 29, F1, 4)
	hall(32, 30, 48, 40, F1, 6, FLOOR, 4)
	for _, p in ipairs({{35, 33}, {45, 33}, {35, 37}, {45, 37}}) do box(p[1], F1 + 1, p[2], p[1], F1 + 6, p[2], BRICK) end
	spawner(40, F1, 35, "goblin", 3, 12)
	spawner(38, F1, 39, "orc", 1, 10)
	-- west: the guard room, bunks and a rack
	hall(22, 34, 31, 36, F1, 4)
	hall(10, 28, 21, 42, F1, 5, FLOOR, 4)
	for z = 30, 40, 3 do box(11, F1 + 1, z, 13, F1 + 1, z, "stairs:slab_wood") end
	spawner(17, F1, 35, "goblin", 3, 10)
	spawner(15, F1, 40, "cutthroat", 1, 10)
	chest(20, F1 + 1, 29, "common", 3)
	-- east: the barracks
	hall(49, 34, 55, 36, F1, 4)
	hall(56, 28, 70, 42, F1, 5, FLOOR, 4)
	box(60, F1 + 1, 33, 66, F1 + 1, 37, PLANK)                 -- a long table
	box(60, F1 + 1, 33, 66, F1 + 1, 33, "stairs:slab_wood")
	spawner(63, F1, 31, "cutthroat", 2, 10)
	spawner(63, F1, 40, "goblin", 2, 10)
	chest(69, F1 + 1, 41, "weapon", 2)
	-- the landing, and from the guard room and the barracks their own ways to it
	hall(36, 44, 44, 48, F1, 5, FLOOR, 4)
	hall(39, 41, 41, 43, F1, 4)
	hall(15, 43, 17, 46, F1, 4); hall(18, 45, 35, 46, F1, 4)
	hall(63, 43, 65, 46, F1, 4); hall(45, 45, 62, 46, F1, 4)
	-- the stair down to the delvings: north from the landing
	for k = 1, F1 - F2 do
		local z, fy = 48 + k, F1 - k
		for x = 38, 42 do
			for y = fy - 1, fy + 5 do rock_to(x, y, z, COBBLE) end
		end
		box(39, fy, z, 41, fy, z, BRICK)
		air(39, fy + 1, z, 41, fy + 4, z)
		if k % 4 == 0 then set(40, fy + 5, z, LAMP) end
	end
end

------------------------------------------------------------------------------
-- The delvings: the mine, rough rock and timber

local function gallery(x1, z1, x2, z2, fy, h)
	box(x1, fy, z1, x2, fy, z2, rnd(2) == 0 and ROCK or GRAVEL)
	air(x1, fy + 1, z1, x2, fy + h, z2)
	-- the roof uneven, the floor strewn
	for z = z1, z2 do for x = x1, x2 do
		if rnd(9) == 0 then set(x, fy + h, z, ROCK) end
		local r = rnd(14)
		if r == 0 then set(x, fy, z, GRAVEL) elseif r == 1 then set(x, fy, z, COBBLE) end
	end end
end

-- Timber frames across a gallery running along x (posts on z1 and z2)
local function timbers_x(x1, x2, z1, z2, fy, h)
	for x = x1 + 2, x2 - 2, 5 do
		box(x, fy + 1, z1, x, fy + h - 1, z1, LOG); box(x, fy + 1, z2, x, fy + h - 1, z2, LOG)
		box(x, fy + h, z1, x, fy + h, z2, PLANK)
	end
end
local function timbers_z(z1, z2, x1, x2, fy, h)
	for z = z1 + 2, z2 - 2, 5 do
		box(x1, fy + 1, z, x1, fy + h - 1, z, LOG); box(x2, fy + 1, z, x2, fy + h - 1, z, LOG)
		box(x1, fy + h, z, x2, fy + h, z, PLANK)
	end
end

local function delvings()
	-- the long gallery, east to west, where the stair comes down
	gallery(8, 61, 70, 64, F2, 4)
	timbers_x(8, 70, 61, 64, F2, 4)
	for x = 12, 66, 9 do set(x, F2 + 3, 61, "default:torch_wall", 5) end
	-- west: the mess
	gallery(4, 65, 20, 76, F2, 5)
	box(8, F2 + 1, 68, 16, F2 + 1, 70, PLANK)
	set(6, F2, 74, "default:coalblock"); set(6, F2 + 1, 74, "fire:permanent_flame")
	spawner(12, F2, 73, "orc", 3, 10)
	chest(18, F2 + 1, 75, "common", 2)
	-- north: the ore chamber, mese in its walls
	gallery(38, 65, 42, 69, F2, 4)
	gallery(30, 70, 50, 77, F2, 5)
	timbers_z(70, 77, 30, 50, F2, 5)
	for _, p in ipairs({{29, F2 + 2, 72}, {51, F2 + 3, 75}, {35, F2 + 4, 78}, {45, F2 + 2, 78}, {29, F2 + 3, 76}}) do
		set(p[1], p[2], p[3], "default:stone_with_mese")
	end
	set(40, F2 + 5, 74, LAMP)
	spawner(40, F2, 74, "deep_orc", 2, 10)
	chest(31, F2 + 1, 76, "weapon", 1)
	-- east: the forge, its anvil, its basin of fire
	gallery(60, 65, 74, 77, F2, 6)
	box(63, F2 + 1, 74, 65, F2 + 1, 76, OBRICK)
	set(64, F2 + 1, 75, STILL)
	set(68, F2 + 1, 75, "default:steelblock")
	for _, p in ipairs({{63, 68}, {69, 68}, {66, 73}, {72, 75}}) do set(p[1], F2 + 7, p[2], LAMP) end
	box(62, F2 + 1, 66, 62, F2 + 1, 68, "default:furnace", 3)
	spawner(67, F2, 70, "deep_orc", 1, 10)
	spawner(70, F2, 74, "cutthroat", 2, 10)
	-- the fallen back wall: rubble, and the caves beyond
	for z = 66, 70 do for y = F2 + 1, F2 + 3 do if rnd(3) == 0 then set(74, y, z, GRAVEL) end end end
end

------------------------------------------------------------------------------
-- The caves: down and down. A path of points ({x, floor, z}); between them a
-- passage of rough rock, its floor level across (so it can be walked), its
-- walls and roof uneven

local function carve(cx, fy, cz, w, h)
	local r = math.ceil(w + 1)
	for z = math.floor(cz - r), math.ceil(cz + r) do for x = math.floor(cx - r), math.ceil(cx + r) do
		local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
		local edge = w + (noise(x, fy, z, 3) - 0.5) * 1.6
		-- (never the template's outer two blocks: they stay rock)
		if d <= edge and x >= 2 and x <= SX - 3 and z >= 2 and z <= SZ - 3 and inside(x, fy, z) then
			-- the roof lower towards the walls, rough
			local top = fy + math.floor(h * math.sqrt(math.max(0.15, 1 - (d / math.max(edge, 0.5)) ^ 2)) +
				(noise(x, fy + 7, z, 2) - 0.5) * 2 + 0.5)
			top = math.max(top, fy + 3)
			for y = fy + 1, math.min(top, NG - 5) do set(x, y, z, "air") end
			if inside(x, fy, z) and get(x, fy, z) == "air" then set(x, fy, z, ROCK) end
		end
	end end
end

local lights = {}
local function cave_path(points)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
		local n = math.max(1, math.ceil(len * 2))
		for k = 0, n do
			local t = k / n
			local x = a[1] + (b[1] - a[1]) * t + (noise(k + i * 50, 0, 0, 6) - 0.5) * 2.5
			local z = a[3] + (b[3] - a[3]) * t + (noise(0, k + i * 50, 0, 6) - 0.5) * 2.5
			local fy = math.floor(a[2] + (b[2] - a[2]) * t + 0.5)
			local w = (a[4] or 2.2) + ((b[4] or 2.2) - (a[4] or 2.2)) * t
			carve(x, fy, z, w, a[5] or 4)
			-- the tribes' torches: nobody but the builder can set one here
			if k % 14 == 7 then lights[#lights + 1] = {math.floor(x + 0.5), fy, math.floor(z + 0.5), w} end
		end
	end
end

-- Each light on the floor at the passage's side (once all is carved)
local function place_lights()
	for _, l in ipairs(lights) do
		local x, fy, z, w = l[1], l[2], l[3], l[4]
		for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
			local placed = false
			for r = math.floor(w), 1, -1 do
				local tx, tz = x + d[1] * r, z + d[2] * r
				if inside(tx, fy + 1, tz) and get(tx, fy + 1, tz) == "air" and get(tx, fy, tz) ~= "air"
						and get(tx, fy + 2, tz) == "air" then
					set(tx, fy + 1, tz, "default:torch", 1)
					placed = true
					break
				end
			end
			if placed then break end
		end
	end
end

-- Stalagmites and fallen stones on a cave's floor, now and then
local function strew(x1, z1, x2, z2, y1, y2)
	for z = z1, z2 do for x = x1, x2 do for y = y1, y2 do
		if inside(x, y, z) and get(x, y, z) == "air" and get(x, y - 1, z) ~= "air" and get(x, y - 1, z) ~= nil then
			local r = rnd(70)
			if r == 0 then set(x, y, z, COBBLE)
			elseif r == 1 then set(x, y, z, GRAVEL) end
		end
	end end end
end

local CAVE = {
	{73, F2, 68, 2.3, 4},       -- through the forge's fallen wall
	{76, F2 - 2, 62, 2.2, 4},
	{75, 40, 50, 2.4, 4},
	{70, 35, 38, 2.6, 5},
	{60, 31, 27, 5.5, 6},       -- the goblin camp
	{46, 28, 18, 2.4, 4},
	{30, 25, 13, 2.6, 5},
	{16, 22, 17, 2.4, 4},
	{11, 19, 30, 4.5, 6},       -- the orc post
	{12, 16, 46, 2.4, 4},
	{18, 12, 58, 2.6, 5},
	{28, 8, 64, 2.4, 4},
	{33, FL, 55, 3, 5},         -- into the lair
}

local function caves()
	cave_path(CAVE)
	-- the goblin camp: tents, a fire, their loot
	local cx, cy, cz = 60, 31, 27
	set(cx, cy, cz + 2, "default:coalblock"); set(cx, cy + 1, cz + 2, "fire:permanent_flame")
	local function tent(x1, z1, colour)
		box(x1, cy + 1, z1, x1 + 2, cy + 2, z1 + 2, colour)
		set(x1 + 1, cy + 3, z1 + 1, colour)
		air(x1 + 1, cy + 1, z1, x1 + 1, cy + 2, z1)
	end
	tent(56, 23, "wool:brown"); tent(62, 22, "wool:dark_green")
	spawner(58, cy, 29, "goblin", 3, 12)
	spawner(63, cy, 28, "cutthroat", 2, 12)
	chest(64, cy + 1, 31, "common", 0)
	-- a dead end off the camp, the camp's store
	cave_path({{56, 31, 30, 2, 3}, {50, 31, 36, 1.8, 3}})
	chest(50, 32, 36, "weapon", 2)
	-- the orc post: a barricade, braziers
	local ox, oy, oz = 11, 19, 30
	box(8, oy + 1, oz + 3, 14, oy + 1, oz + 3, "default:fence_wood")
	air(10, oy + 1, oz + 3, 12, oy + 1, oz + 3)
	for _, p in ipairs({{8, oz - 2}, {14, oz - 2}}) do
		if get(p[1], oy + 1, p[2]) == "air" then
			set(p[1], oy + 1, p[2], "default:coalblock"); set(p[1], oy + 2, p[2], "fire:permanent_flame")
		end
	end
	spawner(11, oy, 28, "deep_orc", 2, 12)
	spawner(12, oy, 33, "orc", 2, 12)
	-- before the lair: the wyrm's own guard
	spawner(22, 11, 60, "deep_orc", 2, 10)
	strew(5, 5, 77, 75, 6, 44)
	place_lights()
end

------------------------------------------------------------------------------
-- The lair, and the hall of fire beside it

local LX, LZ, LRX, LRZ = 43, 44, 15, 16

local function lair()
	for z = LZ - LRZ - 1, LZ + LRZ + 1 do for x = LX - LRX - 1, LX + LRX + 1 do
		local dx, dz = (x - LX) / LRX, (z - LZ) / LRZ
		local d = math.sqrt(dx * dx + dz * dz) + (noise(x, 3, z, 4) - 0.5) * 0.12
		if d <= 1 and inside(x, FL, z) then
			set(x, FL, z, rnd(6) == 0 and GRAVEL or ROCK)
			local top = FL + math.floor(3 + 13 * math.sqrt(math.max(0, 1 - d * d)) + (noise(x, 20, z, 3) - 0.5) * 3)
			for y = FL + 1, top do set(x, y, z, "air") end
		end
	end end
	-- pillars of rock, floor to roof
	for _, p in ipairs({{35, 36}, {51, 35}, {34, 52}, {52, 53}, {43, 31}}) do
		for y = FL + 1, FL + 18 do
			for dz = -1, 1 do for dx = -1, 1 do
				if math.abs(dx) + math.abs(dz) < 2 + (y % 3 == 0 and 1 or 0) and inside(p[1] + dx, y, p[2] + dz) then
					set(p[1] + dx, y, p[2] + dz, ROCK)
				end
			end end
		end
	end
	-- the hoard, round the wyrm's bed (kept clear for it)
	for _ = 1, 60 do
		local a, r = rnd(628) / 100, 4 + rnd(60) / 10
		local x, z = math.floor(LX + math.cos(a) * r + 0.5), math.floor(LZ + math.sin(a) * r + 0.5)
		if get(x, FL + 1, z) == "air" then
			local k = rnd(10)
			set(x, FL + 1, z, k < 6 and "default:goldblock" or (k < 8 and "stairs:slab_goldblock" or
				(k == 8 and "default:mese" or "default:steelblock")))
		end
	end
	for _, p in ipairs({{38, 50}, {48, 49}, {40, 41}, {47, 40}}) do set(p[1], FL + 1, p[2], "bones:bones") end
	chest(39, FL + 1, 47, "common", 1)
	chest(47, FL + 1, 46, "weapon", 3)
	-- cracks of fire in the walls, for light: from each point towards the
	-- lair's middle, the first rock that faces the open
	for _, p in ipairs({{24, 8, 40}, {27, 7, 30}, {25, 9, 52}, {40, 7, 24}, {36, 10, 64}, {50, 8, 26},
			{24, 6, 46}, {33, 12, 26}, {46, 11, 64}, {30, 6, 58}, {56, 7, 30}, {57, 8, 58}}) do
		local x, y, z = p[1], p[2], p[3]
		for _ = 1, 20 do
			local open = false
			for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
				if get(x + d[1], y, z + d[2]) == "air" then open = true end
			end
			if get(x, y, z) == ROCK and open then set(x, y, z, STILL) break end
			x = x + (LX > x and 1 or (LX < x and -1 or 0)); z = z + (LZ > z and 1 or (LZ < z and -1 or 0))
		end
	end
	-- pools of fire in the floor, near the walls
	for _, p in ipairs({{31, 44}, {36, 32}, {50, 31}, {33, 56}, {47, 58}, {55, 38}, {29, 38}}) do
		for dz = 0, 1 do for dx = 0, 1 do
			local x, z = p[1] + dx, p[2] + dz
			if get(x, FL + 1, z) == "air" then set(x, FL, z, STILL) end
		end end
	end
	spawner(LX, FL, LZ, "wyrm", 1, 24)
end

local function fire_hall()
	-- the hall: x 57 to 77, z 34 to 54, roof up to 16 above the floor
	for z = 34, 54 do for x = 57, 77 do
		local top = FL + math.floor(8 + 6 * math.sin((z - 34) / 20 * math.pi) + (noise(x, 30, z, 3) - 0.5) * 3)
		if x <= 59 or x >= 76 or z <= 35 or z >= 53 then top = math.min(top, FL + 6) end
		if not ((x == 57 or x == 77) and (z % 5 ~= 0)) then
			set(x, FL, z, ROCK)
			for y = FL + 1, top do set(x, y, z, "air") end
		end
	end end
	-- the way from the lair: wide
	for z = 38, 50 do for x = 55, 58 do
		set(x, FL, z, ROCK)
		for y = FL + 1, FL + 9 do set(x, y, z, "air") end
	end end
	-- the lake: x 61 to 71, wall to wall (z 34 to 54); two deep
	box(61, FL - 2, 34, 71, FL - 2, 54, OBSIDIAN)
	box(61, FL - 1, 34, 71, FL, 54, LAVA)
	-- the sleeping bridge, at the lake's surface, z 43 to 45
	box(61, FL, 43, 71, FL, 45, SLEEPING)
	-- the bridge's stubs on either shore, and their posts
	box(59, FL, 43, 60, FL, 45, BRIDGE)
	box(72, FL, 43, 73, FL, 45, BRIDGE)
	for _, p in ipairs({{60, 42}, {60, 46}, {72, 42}, {72, 46}}) do box(p[1], FL + 1, p[2], p[1], FL + 2, p[2], OBRICK) end
	-- the far shore: a dais, the finish, the finish chest
	box(74, FL, 41, 76, FL, 47, OBRICK)
	set(g.finish.x, g.finish.y, g.finish.z, FINISH)
	chest(75, FL + 1, 47, "finish", 2)
	-- the far shore walled off from everything else
	for z = 34, 54 do for y = FL + 1, FL + 16 do
		if get(77, y, z) == "air" then set(77, y, z, ROCK) end
	end end
end

------------------------------------------------------------------------------

-- A plan, north at the top, of each level: "." open, "#" rock, "~" lava
function g.plan()
	local out = {}
	for _, lv in ipairs({{"upper halls", F1 + 1}, {"delvings", F2 + 1}, {"caves (lowest open block)", nil}, {"lair", FL + 1}}) do
		out[#out + 1] = "-- " .. lv[1]
		for z = SZ - 1, 0, -1 do
			local row = {}
			for x = 0, SX - 1 do
				local ch = "#"
				if lv[2] then
					local n = get(x, lv[2], z)
					ch = n == "air" and "." or ((n == LAVA or n == SLEEPING) and "~" or (n == "#" and "#" or "#"))
					if get(x, lv[2] - 1, z) == LAVA or get(x, lv[2] - 1, z) == SLEEPING then ch = "~" end
				else
					for y = 6, 45 do if get(x, y, z) == "air" then ch = "." break end end
				end
				row[#row + 1] = ch
			end
			out[#out + 1] = table.concat(row)
		end
	end
	return table.concat(out, "\n")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.spawners, g.chests, g.signs = {}, {}, {}
	lights = {}
	seed = 4242
	ground()
	ruin()
	upper()
	delvings()
	caves()
	lair()
	fire_hall()
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
	for name in pairs(missing) do core.log("error", "[wyrm_below] no such node: " .. name) end
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
