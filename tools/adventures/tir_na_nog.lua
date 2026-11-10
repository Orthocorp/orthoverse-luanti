-- Tir Na Nog: builds the ready-made adventure in a world, so that it can be
-- saved as adventures/tir_na_nog.ovt (the compact form).
--
--   local g = dofile(".../tools/adventures/tir_na_nog.lua")
--   g.build(origin)        -- origin: the template's south-west bottom corner
--   g.info                 -- what goes in adventures/tir_na_nog.json
--
-- A climb in the sky, with no monsters. The whole adventure is one box in
-- the air over the land, from 26 blocks above its ground (clear of the
-- highest trees and hills) to the castle's towers; the land below stays as
-- it is. Outside it there is only the gate, on a small pale pad on the top of
-- a mountain, and the gate takes the party up to the start, at the bottom
-- of the box.
--
-- The way up goes round the land, from stone to stone, rising all the time:
--   the Stepping Stones (north along the east side),
--   the Ghost Steps (west along the north side: they fade and come back, one
--     after another, so keep moving with them),
--   the Spires (south along the west side),
--   the Ice (east along the south side: slippery),
--   the Wind Ladder (up a lone spire), and the last stones to the
--     drawbridge of the castle.
-- Each part ends on a little floating island with a checkpoint. Nobody is
-- hurt by a fall: the wind catches them and sets them down on the last
-- checkpoint they stood on (orthoverse_adventure, catch_falls).
--
-- The castle: through its gate a maze, made anew for every run, and beyond
-- it the treasure hall, the finish and the chest. Its walls are four high:
-- one player standing on another (players are solid) could get up onto
-- walls of three and walk over it.
--
-- Coordinates are relative to the land's south-west corner: x east, z
-- north, and Y as on the map (the ground is the map's, Y = 8; players stand
-- at 9). The template's floor is at Y = BASE.

local g = {}

local SX, SZ = 96, 96
local BASE = 34                 -- the box's floor
local TOP = 150                 -- and its top (the keep's spire)
local SY = TOP - BASE + 1
local G = 8                     -- the map's ground

local STONE = "default:silver_sandstone_brick"
local BLOCK = "default:silver_sandstone_block"
local SMOOTH = "default:silver_sandstone"
local CLOUD = "default:cloud"
local ICE = "default:ice"
local ROCK = "default:stone"
local DIRT = "default:dirt"
local GRASS = "default:dirt_with_grass"
local LADDER = "default:ladder_wood"
local LAMP = "default:meselamp"
local GLASS = "default:glass"
local ROOF = "wool:pink"
local ROOF2 = "wool:magenta"
local TRIM = "default:silver_sandstone_block"
local WALL = "default:sandstonebrick"   -- the castle's outside: cream
local GOLD = "default:goldblock"
local GHOST = "orthoverse_props:ghost_step"
local CHECK = "orthoverse_adventure:checkpoint"
local CHEST = "orthoverse_loot:chest"
local FINISH = "orthoverse_adventure:finish"

-- The castle
local CX1, CX2, CZ1, CZ2 = 24, 70, 24, 68   -- its outer walls
local FLOOR = 100                            -- its floor (players stand at 101)
local MAZE = {x1 = 38, x2 = 68, z1 = 31, z2 = 61}
local MZ = 46                                -- the maze's ways in and out (z)

-- The gate, on the top of the mountain on the second tile of the fourth row
-- from the north (its summit is Y = 28): nobody walks up it, but a rider
-- can, or a friend standing on a friend
local GATE = {x = 24, y = 29, z = 41}
local PAD = GATE.y - 1

local START = {x = 88, y = 38, z = 22}       -- the start's stone (players stand on it)

local function rel(t) return {x = t.x, y = t.y - BASE, z = t.z} end

g.info = {
	name = "Tir Na Nog",
	line = "High over the land the castle of Tir Na Nog floats on the wind. The way up is from stone to stone: " ..
		"no monsters, only the long fall, and the wind that catches you.",
	limit = 40,
	rank_min = 1, rank_max = 20,
	size = {x = SX, y = SY, z = SZ},
	-- placed over the whole land, its floor this far above the ground; the
	-- land under it is kept
	whole_land = true,
	keep_ground = true,
	ground = G - BASE,
	clear = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = SY - 1, z = SZ - 1}},
		{min = {x = GATE.x - 1, y = GATE.y - BASE, z = GATE.z - 3}, max = {x = GATE.x + 1, y = GATE.y + 3 - BASE, z = GATE.z + 1}}},
	corner1 = {x = 0, y = 0, z = 0},
	corner2 = {x = SX - 1, y = SY - 1, z = SZ - 1},
	start = {x = START.x + 0.5, y = START.y + 1 - BASE, z = START.z + 0.5},
	arrival = {x = GATE.x + 0.5, y = GATE.y - BASE, z = GATE.z - 1.5},
	-- the gate's pad, protected as the adventure's
	footprint = {min = {x = GATE.x - 1, y = PAD - 3 - BASE, z = GATE.z - 3}, max = {x = GATE.x + 1, y = GATE.y + 3 - BASE, z = GATE.z + 1}},
	nodes = {},
	-- going there from the Adventures page: the foot of the mountain
	approach = {x = 24.5, y = G + 1 - BASE, z = 48.5},
	approach_line = "Its gate is on the top of the mountain in front of you: find a way up.",
	-- no weapons: an apple for the way
	kit = {"default:apple"},
	catch_falls = true,
	finish_xp = 300,
	maze = {min = {x = MAZE.x1, y = FLOOR - BASE, z = MAZE.z1}, max = {x = MAZE.x2, y = FLOOR + 4 - BASE, z = MAZE.z2},
		wall = STONE},
}
g.compact = true
-- for the checks, every ghost step there
g.swap_for_checks = {["orthoverse_props:ghost_step_gone"] = "orthoverse_props:ghost_step"}

-- Where things are, for tests
g.chests = {}
g.signs = {}
g.spawners = {}
g.checkpoints = {}
g.finish = rel({x = 28, y = FLOOR + 1, z = MZ})
g.sections = {}

------------------------------------------------------------------------------
-- A grid of the whole template (Y as on the map)

local grid, p2grid, metas

local function idx(x, y, z) return x + (y - BASE) * SX + z * SX * SY + 1 end
local function inside(x, y, z) return x >= 0 and x < SX and y >= BASE and y <= TOP and z >= 0 and z < SZ end
local function set(x, y, z, name, param2)
	assert(inside(x, y, z), ("outside: %d,%d,%d"):format(x, y, z))
	local i = idx(x, y, z)
	grid[i] = name
	p2grid[i] = param2 or 0
end
local function get(x, y, z) return inside(x, y, z) and grid[idx(x, y, z)] or "air" end
local function box(x1, y1, z1, x2, y2, z2, name, param2)
	for z = z1, z2 do for y = y1, y2 do for x = x1, x2 do set(x, y, z, name, param2) end end end
end

local seed = 1916
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end

local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	metas[#metas + 1] = {x = x, y = y, z = z, construct = true, fields = {kind = kind, infotext = "Loot chest (" .. kind .. ")"}}
	g.chests[#g.chests + 1] = rel({x = x, y = y, z = z})
	g.chests[#g.chests].kind = kind
end

------------------------------------------------------------------------------
-- Islands: a few blocks of turf on a cone of rock, a checkpoint in the
-- middle (top: the Y players stand on, less one)

local function island(cx, cz, top, r, check)
	for dz = -r, r do for dx = -r, r do
		if dx * dx + dz * dz <= r * r + 1 then
			set(cx + dx, top, cz + dz, GRASS)
			local d = math.sqrt(dx * dx + dz * dz)
			local depth = math.floor((r - d) * 1.6) + 1 + rnd(2)
			for y = top - 1, math.max(BASE, top - depth), -1 do set(cx + dx, y, cz + dz, y > top - 2 and DIRT or ROCK) end
		end
	end end
	if check then
		set(cx, top, cz, CHECK)
		g.checkpoints[#g.checkpoints + 1] = rel({x = cx, y = top + 1, z = cz})
	end
end

------------------------------------------------------------------------------
-- A run of jumps from stone to stone, from `from` (a stone: x, y, z) to an
-- island at `to` (x, z), rising `rise` on the way. The jumps (between the
-- stones' middles; a player is 0.6 wide and stands on an edge):
--   one up: 2 or 3 blocks along; level: 3 or 4; one down: 4.
-- `kind`: "stones" (clouds), "ghost" (ghost steps, a cloud every fourth),
-- "spires" (stones on tall thin spires), "ice" (slippery, two long).
-- Returns the last stone and the island's middle (both {x, y, z}).

local function jumps(from, to, rise, kind)
	local sec = {kind = kind, stones = {}}
	g.sections[#g.sections + 1] = sec
	local dx, dz = to.x - from.x, to.z - from.z
	local D = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / D, dz / D
	-- the island's edge is 3 from its middle (radius 2) and a level jump of 3
	-- onto it: the stones cover D - 6
	local L = D - 6
	local ups = rise
	local downs = math.floor(ups / 5)
	ups = ups + downs
	local up_len, level_len, down_len = 2.5, (kind == "ice" and 3.2 or 3.4), 4
	local levels = math.max(0, math.floor((L - ups * up_len - downs * down_len) / level_len + 0.5))
	local seq = {}
	for _ = 1, ups do seq[#seq + 1] = 1 end
	for _ = 1, levels do seq[#seq + 1] = 0 end
	for _ = 1, downs do seq[#seq + 1] = -1 end
	-- shuffled, but never two downs running, nor a down first
	for i = #seq, 2, -1 do local j = rnd(i) + 1; seq[i], seq[j] = seq[j], seq[i] end
	for i = 1, #seq do
		if seq[i] == -1 and (i == 1 or seq[i - 1] == -1) then
			for j = i + 1, #seq do if seq[j] == 1 then seq[i], seq[j] = seq[j], seq[i] break end end
		end
	end
	local total = 0
	for _, dy in ipairs(seq) do total = total + (dy == 1 and up_len or dy == 0 and level_len or down_len) end
	local scale = L / math.max(total, 1)
	local p = {x = from.x, y = from.y, z = from.z}
	local along = 0
	for i, dy in ipairs(seq) do
		local len = (dy == 1 and up_len or dy == 0 and level_len or down_len) * scale
		along = along + len
		local side = (rnd(3) - 1) * (kind == "ice" and 0 or 1)
		local q = {x = math.floor(from.x + ux * along - uz * side + 0.5), y = p.y + dy,
			z = math.floor(from.z + uz * along + ux * side + 0.5)}
		-- keep each jump within reach
		local function d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end
		local max = dy == 1 and 3 or dy == 0 and 4 or 4.5
		local min = dy == 1 and 2 or 2.8
		if d(p, q) > max or d(p, q) < min then
			q.x = math.floor(from.x + ux * along + 0.5)
			q.z = math.floor(from.z + uz * along + 0.5)
		end
		while d(p, q) > max do
			-- a block back towards the last stone, on the longer way
			if math.abs(q.x - p.x) >= math.abs(q.z - p.z) then q.x = q.x - (q.x > p.x and 1 or -1)
			else q.z = q.z - (q.z > p.z and 1 or -1) end
		end
		if kind == "ghost" then
			if i % 4 == 0 then set(q.x, q.y, q.z, CLOUD)
			else
				-- each a second after the one before: keep moving with them
				set(q.x, q.y, q.z, GHOST, (-2 * i) % 8)
			end
		elseif kind == "spires" then
			set(q.x, q.y, q.z, BLOCK)
			for y = q.y - 1, math.max(BASE, q.y - 5 - rnd(4)), -1 do set(q.x, y, q.z, SMOOTH) end
		elseif kind == "ice" then
			set(q.x, q.y, q.z, ICE)
			-- two long, so there is room to stop
			set(q.x + (math.abs(ux) > math.abs(uz) and (ux > 0 and 1 or -1) or 0), q.y,
				q.z + (math.abs(uz) >= math.abs(ux) and (uz > 0 and 1 or -1) or 0), ICE)
			if math.abs(ux) > math.abs(uz) then q.x = q.x + (ux > 0 and 1 or -1) else q.z = q.z + (uz > 0 and 1 or -1) end
		else
			set(q.x, q.y, q.z, CLOUD)
		end
		sec.stones[#sec.stones + 1] = rel(q)
		p = q
	end
	local mid = {x = math.floor(p.x + ux * 4.5 + 0.5), y = p.y, z = math.floor(p.z + uz * 4.5 + 0.5)}
	return p, mid
end

------------------------------------------------------------------------------
-- The way up

local function course()
	-- the start: a round of white stone, the gate's way up ends here
	for dz = -2, 2 do for dx = -2, 2 do
		if dx * dx + dz * dz <= 5 then set(START.x + dx, START.y, START.z + dz, BLOCK) end
	end end
	for dz = -1, 1 do for dx = -1, 1 do set(START.x + dx, START.y - 1, START.z + dz, ROCK) end end
	set(START.x, START.y - 2, START.z, ROCK)
	local from = {x = START.x, y = START.y, z = START.z + 2}
	-- north along the east side
	local last, mid = jumps(from, {x = 88, z = 86}, 10, "stones")
	island(mid.x, mid.z, mid.y, 2, true)
	-- west along the north side
	last, mid = jumps({x = mid.x - 2, y = mid.y, z = mid.z}, {x = 10, z = 88}, 8, "ghost")
	island(mid.x, mid.z, mid.y, 2, true)
	-- south along the west side
	last, mid = jumps({x = mid.x, y = mid.y, z = mid.z - 2}, {x = 9, z = 10}, 11, "spires")
	island(mid.x, mid.z, mid.y, 2, true)
	-- east along the south side
	last, mid = jumps({x = mid.x + 2, y = mid.y, z = mid.z}, {x = 80, z = 9}, 9, "ice")
	island(mid.x, mid.z, mid.y, 2, true)
	-- the Wind Ladder: up a lone spire on the island's north side, to a
	-- landing at the top
	local lx, lz, ly = mid.x, mid.z + 3, mid.y
	local high = 92
	for y = ly - 4, high do set(lx, y, lz + 1, SMOOTH) end
	for y = ly + 1, high + 1 do set(lx, y, lz, LADDER, 4) end   -- wallmounted, on the spire to the north
	set(lx, ly, lz, ROCK)
	box(lx - 1, high, lz + 1, lx + 1, high, lz + 3, BLOCK)
	set(lx, high, lz + 2, CHECK)
	g.checkpoints[#g.checkpoints + 1] = rel({x = lx, y = high + 1, z = lz + 2})
	g.ladder = rel({x = lx, y = ly + 1, z = lz})
	-- the last stones, north to the drawbridge
	last, mid = jumps({x = lx, y = high, z = lz + 3}, {x = CX2 + 4, z = MZ}, FLOOR - high - 1, "stones")
	return last
end

------------------------------------------------------------------------------
-- The castle

-- A round tower, x/z its middle, r its radius, from y1 to y2: solid up to
-- the castle's walls' height (nobody gets inside), hollow above, cream bands
-- and windows, a cornice, and a steep pink roof with a gold tip
local function roof(cx, cz, r, y)
	local rr = r + 1
	local k = 0
	while rr >= 0 do
		for dz = -rr, rr do for dx = -rr, rr do
			if dx * dx + dz * dz <= rr * rr + rr then set(cx + dx, y + k, cz + dz, ROOF) end
		end end
		k = k + 1
		-- steep: each ring two high, three at the top
		if k % 2 == 0 or rr <= 1 then rr = rr - 1 end
	end
	set(cx, y + k, cz, ROOF2)
	set(cx, y + k + 1, cz, GOLD)
	return y + k + 1
end

local function tower(cx, cz, r, y1, y2)
	for y = y1, y2 do
		for dz = -r, r do for dx = -r, r do
			local d2 = dx * dx + dz * dz
			if d2 <= r * r + r then
				local ring = d2 > (r - 1) * (r - 1) + (r - 1)
				if ring or y <= FLOOR + 8 then
					local name = ((y - y1) % 7 == 6) and TRIM or WALL
					if ring and y > FLOOR + 8 and (y - y1) % 7 >= 2 and (y - y1) % 7 <= 3
							and ((dx == 0 and math.abs(dz) == r) or (dz == 0 and math.abs(dx) == r)) then
						name = GLASS
					end
					set(cx + dx, y, cz + dz, name)
				end
			end
		end end
	end
	-- a cornice, one wider, with battlements
	for dz = -r - 1, r + 1 do for dx = -r - 1, r + 1 do
		local d2 = dx * dx + dz * dz
		if d2 <= (r + 1) * (r + 1) + r + 1 and d2 > (r - 1) * (r - 1) + r then set(cx + dx, y2 + 1, cz + dz, TRIM) end
	end end
	return roof(cx, cz, r, y2 + 2)
end

local function castle(last)
	-- the rock it stands on, narrowing downwards
	for y = FLOOR - 1, FLOOR - 16, -1 do
		local k = FLOOR - 1 - y
		local x1, x2, z1, z2 = CX1 + k, CX2 - k, CZ1 + k, CZ2 - k
		for z = z1, z2 do for x = x1, x2 do
			if k < 2 or rnd(8) > 0 or (x > x1 and x < x2 and z > z1 and z < z2) then set(x, y, z, k < 1 and DIRT or ROCK) end
		end end
	end
	box(CX1, FLOOR, CZ1, CX2, FLOOR, CZ2, BLOCK)
	-- outer walls and battlements
	for y = FLOOR + 1, FLOOR + 8 do
		for x = CX1, CX2 do set(x, y, CZ1, WALL); set(x, y, CZ2, WALL) end
		for z = CZ1, CZ2 do set(CX1, y, z, WALL); set(CX2, y, z, WALL) end
	end
	for x = CX1, CX2, 2 do set(x, FLOOR + 9, CZ1, WALL); set(x, FLOOR + 9, CZ2, WALL) end
	for z = CZ1, CZ2, 2 do set(CX1, FLOOR + 9, z, WALL); set(CX2, FLOOR + 9, z, WALL) end
	-- a band of cream stone under the battlements, and windows
	for x = CX1, CX2 do set(x, FLOOR + 8, CZ1, TRIM); set(x, FLOOR + 8, CZ2, TRIM) end
	for z = CZ1, CZ2 do set(CX1, FLOOR + 8, z, TRIM); set(CX2, FLOOR + 8, z, TRIM) end
	for x = CX1 + 4, CX2 - 4, 5 do
		for y = FLOOR + 5, FLOOR + 6 do set(x, y, CZ1, GLASS); set(x, y, CZ2, GLASS) end
	end
	-- towers round the walls: the corners, the middle of the north and south
	-- walls, and either side of the gate
	for _, t in ipairs({{CX1, CZ1, 3, 18}, {CX2, CZ1, 3, 18}, {CX1, CZ2, 3, 18}, {CX2, CZ2, 3, 18},
			{47, CZ1, 2, 14}, {47, CZ2, 2, 14}, {CX2, MZ - 5, 2, 13}, {CX2, MZ + 5, 2, 13}}) do
		tower(t[1], t[2], t[3], FLOOR, FLOOR + t[4])
	end
	-- the gate in the east wall, and the drawbridge
	box(CX2, FLOOR + 1, MZ - 1, CX2, FLOOR + 3, MZ + 1, "air")
	box(CX2 + 1, FLOOR, MZ - 2, CX2 + 7, FLOOR, MZ + 2, BLOCK)
	-- and its tongue, out to a jump from the last stone (one up)
	assert(last.y == FLOOR - 1, "the last stone is at " .. last.y)
	if last.z + 2 <= MZ - 3 then box(last.x - 1, FLOOR, last.z + 2, last.x + 1, FLOOR, MZ - 3, BLOCK) end
	set(CX2 + 4, FLOOR, MZ, CHECK)
	g.checkpoints[#g.checkpoints + 1] = rel({x = CX2 + 4, y = FLOOR + 1, z = MZ})
	set(CX2 + 7, FLOOR + 1, MZ - 2, LAMP); set(CX2 + 7, FLOOR + 1, MZ + 2, LAMP)
	-- inside the gate: a passage along the maze's east side, closed but for
	-- the way in
	box(CX2 - 1, FLOOR + 1, CZ1 + 1, CX2 - 1, FLOOR + 4, CZ2 - 1, STONE)
	box(CX2 - 1, FLOOR + 1, MZ - 1, CX2 - 1, FLOOR + 4, MZ + 1, "air")
	-- the maze (this one is only the saved one: a run makes its own)
	box(MAZE.x1, FLOOR + 1, MAZE.z1, MAZE.x2, FLOOR + 4, MAZE.z2, STONE)
	for z = MAZE.z1 + 1, MAZE.z2 - 1, 2 do for x = MAZE.x1 + 1, MAZE.x2 - 1 do set(x, FLOOR + 1, z, "air") end end
	-- (rows open east to west, and joined at alternate ends: a winding way)
	for z = MAZE.z1 + 1, MAZE.z2 - 1, 2 do
		for x = MAZE.x1 + 1, MAZE.x2 - 1 do for y = FLOOR + 1, FLOOR + 4 do set(x, y, z, "air") end end
		local k = (z - MAZE.z1 - 1) / 2
		if z + 2 <= MAZE.z2 - 1 then
			local x = (k % 2 == 0) and (MAZE.x2 - 1) or (MAZE.x1 + 1)
			for y = FLOOR + 1, FLOOR + 4 do set(x, y, z + 1, "air") end
		end
	end
	for y = FLOOR + 1, FLOOR + 4 do set(MAZE.x2, y, MZ, "air"); set(MAZE.x1, y, MZ, "air") end
	-- the rest of the castle's floor, either side of the maze: solid (no way round)
	box(MAZE.x1, FLOOR + 1, CZ1 + 1, CX2 - 2, FLOOR + 4, MAZE.z1 - 1, STONE)
	box(MAZE.x1, FLOOR + 1, MAZE.z2 + 1, CX2 - 2, FLOOR + 4, CZ2 - 1, STONE)
	-- and over the passages and maze, open sky. The treasure hall, west of
	-- it: roofed, with pillars and lamps
	local hx1, hx2 = CX1 + 1, MAZE.x1 - 1
	for y = FLOOR + 1, FLOOR + 4 do for z = CZ1 + 1, CZ2 - 1 do
		if z ~= MZ then set(MAZE.x1, y, z, STONE) end
	end end
	box(hx1, FLOOR + 4, CZ1 + 1, MAZE.x1, FLOOR + 8, CZ2 - 1, "air")
	for z = CZ1 + 1, CZ2 - 1 do for y = FLOOR + 4, FLOOR + 8 do set(MAZE.x1, y, z, STONE) end end
	box(hx1, FLOOR + 9, CZ1 + 1, MAZE.x1, FLOOR + 9, CZ2 - 1, STONE)
	for _, z in ipairs({MZ - 15, MZ - 9, MZ - 3, MZ + 3, MZ + 9, MZ + 15}) do
		for _, x in ipairs({hx1 + 3, hx2 - 3}) do
			for y = FLOOR + 1, FLOOR + 8 do set(x, y, z, SMOOTH) end
			set(x, FLOOR + 8, z, LAMP)
		end
	end
	for z = CZ1 + 2, CZ2 - 2, 4 do set(CX1, FLOOR + 5, z, GLASS); set(CX1, FLOOR + 6, z, GLASS) end
	-- over the hall, a pink roof, ridged north to south, and on it the keep:
	-- the tallest tower, with four small ones round it
	local hw = MAZE.x1 - CX1
	for k = 0, math.floor(hw / 2) do
		for z = CZ1, CZ2 do
			for x = CX1 + k, MAZE.x1 - k do
				if get(x, FLOOR + 10 + k, z) == "air" then set(x, FLOOR + 10 + k, z, ROOF) end
			end
		end
	end
	local kx, kz = math.floor((CX1 + MAZE.x1) / 2), MZ
	box(kx - 4, FLOOR + 10, kz - 4, kx + 4, FLOOR + 28, kz + 4, WALL)
	for y = FLOOR + 10, FLOOR + 28, 6 do box(kx - 4, y, kz - 4, kx + 4, y, kz + 4, TRIM) end
	for y = FLOOR + 12, FLOOR + 26, 6 do
		for _, w in ipairs({-2, 0, 2}) do
			set(kx + w, y, kz - 4, GLASS); set(kx + w, y + 1, kz - 4, GLASS)
			set(kx + w, y, kz + 4, GLASS); set(kx + w, y + 1, kz + 4, GLASS)
			set(kx - 4, y, kz + w, GLASS); set(kx - 4, y + 1, kz + w, GLASS)
			set(kx + 4, y, kz + w, GLASS); set(kx + 4, y + 1, kz + w, GLASS)
		end
	end
	box(kx - 5, FLOOR + 29, kz - 5, kx + 5, FLOOR + 29, kz + 5, TRIM)
	tower(kx, kz, 3, FLOOR + 30, FLOOR + 33)
	for _, c in ipairs({{-5, -5}, {5, -5}, {-5, 5}, {5, 5}}) do
		tower(kx + c[1], kz + c[2], 1, FLOOR + 14, FLOOR + 24)
	end
	-- and two more at the hall's ends
	tower(kx, CZ1 + 5, 2, FLOOR + 10, FLOOR + 21)
	tower(kx, CZ2 - 5, 2, FLOOR + 10, FLOOR + 21)
	-- the gatehouse's front: arches over the drawbridge
	for _, z in ipairs({MZ - 2, MZ + 2}) do
		for y = FLOOR + 1, FLOOR + 4 do set(CX2 + 1, y, z, TRIM) end
	end
	box(CX2 + 1, FLOOR + 5, MZ - 2, CX2 + 1, FLOOR + 5, MZ + 2, TRIM)
	box(CX2 + 1, FLOOR + 6, MZ - 1, CX2 + 1, FLOOR + 6, MZ + 1, ROOF)
	set(CX2 + 1, FLOOR + 7, MZ, ROOF)
	-- the dais: the finish, and the chest beside it
	box(26, FLOOR + 1, MZ - 3, 30, FLOOR + 1, MZ + 3, GOLD)
	set(28, FLOOR + 2, MZ, FINISH)
	g.finish = rel({x = 28, y = FLOOR + 2, z = MZ})
	chest(28, FLOOR + 2, MZ - 2, "finish", 3)
	set(28, FLOOR + 2, MZ + 2, LAMP)
	for x = hx1, hx2 do for z = CZ1 + 1, CZ2 - 1 do
		if get(x, FLOOR + 1, z) == "air" and (x + z) % 2 == 0 then set(x, FLOOR, z, SMOOTH) end
	end end
	return last
end

------------------------------------------------------------------------------
-- The gate, on the mountain's top (outside the box: placed on its own): a
-- small pad of white stone, with a little rock under it, and the gate with a
-- lamp either side

local function gate()
	local n = g.info.nodes
	for dz = -3, 1 do for dx = -1, 1 do
		n[#n + 1] = {x = GATE.x + dx, y = PAD - BASE, z = GATE.z + dz, name = BLOCK}
		for y = PAD - 3, PAD - 1 do n[#n + 1] = {x = GATE.x + dx, y = y - BASE, z = GATE.z + dz, name = ROCK} end
	end end
	n[#n + 1] = {x = GATE.x, y = GATE.y - BASE, z = GATE.z, name = "orthoverse_adventure:gate"}
	for _, dx in ipairs({-1, 1}) do
		n[#n + 1] = {x = GATE.x + dx, y = GATE.y - BASE, z = GATE.z + 1, name = STONE}
		n[#n + 1] = {x = GATE.x + dx, y = GATE.y + 1 - BASE, z = GATE.z + 1, name = LAMP}
	end
	g.gate = rel(GATE)
end

function g.plan()
	local out = {}
	for z = SZ - 1, 0, -1 do
		local row = {}
		for x = 0, SX - 1 do
			local ch = "."
			for y = TOP, BASE, -1 do
				local nm = get(x, y, z)
				if nm ~= "air" then
					ch = nm == CHECK and "C" or nm == GHOST and "g" or nm == CLOUD and "o" or nm == ICE and "i"
						or nm == BLOCK and "#" or nm == STONE and "#" or nm == LADDER and "H" or nm == FINISH and "F" or "+"
					break
				end
			end
			row[#row + 1] = ch
		end
		out[#out + 1] = table.concat(row)
	end
	return table.concat(out, "\n")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.chests, g.checkpoints, g.sections, g.info.nodes = {}, {}, {}, {}
	seed = 1916
	local last = course()
	castle(last)
	gate()
	g.last = rel(last)
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
		local i = idx(x, y + BASE, z)
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
	for name in pairs(missing) do core.log("error", "[tir_na_nog] no such node: " .. name) end
	for _, m in ipairs(metas) do
		local pos = vector.add(p1, {x = m.x, y = m.y - BASE, z = m.z})
		local node = core.get_node(pos)
		local def = core.registered_nodes[node.name]
		if m.construct and def and def.on_construct then def.on_construct(pos) end
		local meta = core.get_meta(pos)
		for k, v in pairs(m.fields) do meta:set_string(k, v) end
	end
	-- the ghost steps' timers
	for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {"group:orthoverse_timer"})) do
		core.get_node_timer(pos):start(0.5)
	end
	return missing
end

------------------------------------------------------------------------------
-- The checks (tools/adventures/generate_adventure calls g.check): with jumps,
-- every checkpoint and the finish can be reached from the start, through a
-- few mazes; no stone of a part is far below the checkpoint before it (or
-- the wind would catch a player who is not falling); and the gate's pad.

-- How far a jump goes between stones' middles, by how far up
local function can_jump(dh, dy)
	if dy >= 2 then return false end
	if dy == 1 then return dh <= 3.2 end
	if dy == 0 then return dh <= 4.1 end
	return dh <= 4.6
end

function g.check(O, h)
	local say, walkable, standable = h.say, h.walkable, h.standable
	local function climbable(p)
		local d = core.registered_nodes[core.get_node(p).name]
		return d and d.climbable
	end
	local function holdable(p)
		return (standable(p) or climbable(p)) and not walkable(p)
			and not walkable({x = p.x, y = p.y + 1, z = p.z})
	end
	local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
	local lo, hi = O, vector.add(O, vector.subtract(g.info.size, 1))
	local function clear_between(p, q)
		-- nothing solid in the way, at head height and above the higher end
		local top = math.max(p.y, q.y)
		for t = 0.25, 0.75, 0.25 do
			local x, z = math.floor(p.x + (q.x - p.x) * t + 0.5), math.floor(p.z + (q.z - p.z) * t + 0.5)
			for y = top, top + 1 do
				if walkable({x = x, y = y, z = z}) then return false end
			end
		end
		return not walkable({x = p.x, y = p.y + 2, z = p.z})
	end
	local function reach(from)
		local seen, queue, head = {[key(from)] = true}, {from}, 1
		while head <= #queue do
			local p = queue[head]; head = head + 1
			local on_ladder = climbable(p)
			for dz = -4, 4 do for dx = -4, 4 do
				local dh = math.sqrt(dx * dx + dz * dz)
				for dy = 1, -4, -1 do
					local q = {x = p.x + dx, y = p.y + dy, z = p.z + dz}
					local ok = (dx ~= 0 or dz ~= 0 or (on_ladder and dy == 1)) and q.x >= lo.x and q.x <= hi.x and q.z >= lo.z
						and q.z <= hi.z and q.y > lo.y and q.y < hi.y and not seen[key(q)]
					if ok then
						if on_ladder and dh <= 1 and dy <= 1 then ok = holdable(q)
						elseif dh <= 1.5 and dy <= 0 then ok = holdable(q) and clear_between(p, q)
						else ok = can_jump(dh, dy) and holdable(q) and clear_between(p, q) and not climbable(q) or
							(dh <= 1 and dy == 1 and holdable(q) and not walkable({x = p.x, y = p.y + 2, z = p.z})) end
					end
					if ok then
						seen[key(q)] = true
						queue[#queue + 1] = q
					end
				end
			end end
		end
		return seen
	end
	local start = vector.add(O, vector.round({x = g.info.start.x - 0.5, y = g.info.start.y, z = g.info.start.z - 0.5}))
	say("start standable " .. tostring(standable(start)))
	for m = 1, 3 do
		if orthoverse.adventure.make_maze then
			local mz = g.info.maze
			orthoverse.adventure.make_maze({min = vector.add(O, mz.min), max = vector.add(O, mz.max), wall = mz.wall})
		end
		local seen = reach(start)
		local n = 0
		for _ in pairs(seen) do n = n + 1 end
		local miss = {}
		for i, c in ipairs(g.checkpoints) do
			if not seen[key(vector.add(O, c))] then miss[#miss + 1] = "checkpoint " .. i .. " at " .. core.pos_to_string(c) end
		end
		local fin = vector.add(O, g.finish)
		local near = false
		for dx = -1, 1 do for dz = -1, 1 do for dy = -1, 1 do
			if seen[key(vector.add(fin, {x = dx, y = dy, z = dz}))] then near = true end
		end end end
		for _, ch in ipairs(g.chests) do
			local ok = false
			for dx = -1, 1 do for dz = -1, 1 do for dy = -1, 1 do
				if seen[key(vector.add(O, vector.add(ch, {x = dx, y = dy, z = dz})))] then ok = true end
			end end end
			if not ok then miss[#miss + 1] = "chest" end
		end
		say(("maze %d: %d places reachable; finish reachable %s; unreachable: %s"):format(m, n, tostring(near),
			#miss > 0 and table.concat(miss, ", ") or "none"))
		-- where each part is first out of reach
		for si, sec in ipairs(g.sections) do
			for i, st in ipairs(sec.stones) do
				local at = vector.add(O, {x = st.x, y = st.y + 1, z = st.z})
				if not seen[key(at)] then
					local pv = sec.stones[i - 1]
					say(("  part %d (%s): stone %d of %d at %s not reached, from %s"):format(si, sec.kind, i, #sec.stones,
						core.pos_to_string(st), pv and core.pos_to_string(pv) or "its start"))
					break
				end
			end
		end
		if m == 1 then
			-- a player could stop anywhere they can reach: how far below the
			-- last checkpoint (by height) is the lowest place? (the wind catches
			-- at 6 below)
			local worst = 0
			local cps = {g.info.start}
			for _, c in ipairs(g.checkpoints) do cps[#cps + 1] = c end
			for _, sec in ipairs(g.sections) do
				local prev
				for _, c in ipairs(cps) do
					local d = math.abs(c.x - sec.stones[1].x) + math.abs(c.z - sec.stones[1].z)
					if not prev or d < prev.d then prev = {d = d, y = c.y} end
				end
				for _, s in ipairs(sec.stones) do worst = math.max(worst, prev.y - (s.y + 1)) end
			end
			say("deepest stone below its checkpoint: " .. worst)
		end
	end
	say("signs not on a wall: none (it has none)")
end

return g
