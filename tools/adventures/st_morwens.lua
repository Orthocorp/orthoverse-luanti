-- St Morwen's: builds the ready-made adventure in a world, so that it can be
-- saved as adventures/st_morwens.we (see tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/st_morwens.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/st_morwens.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 11 (players stand at y = 12). 96 x 96: a land of 6 x 6 tiles.
--
--   The crossroads (outside, south): the road, a gibbet, the gate, the board.
--   Inside a thorn hedge (three high: nobody climbs in or out):
--   the haunted forest: dead pines, fog, wisps, ghoul packs; the path runs
--     north to the lych gate of
--   the graveyard: a brick wall, the path between lamp posts, rows of graves
--     (some of them open in the night: zombies), two mausoleums, and
--   St Morwen's church: white walls, a dark roof, the tower over the door.
--     The church is consecrated: the undead cannot set foot in it. In the
--     nave, the fonts (holy water: blows land harder on the undead); a side
--     chapel; the sacristy, with the crypt stair. The tower: ladders and
--     landings (skeletons) up to the belfry and the great bell. Rung, it
--     stuns the dead about it, and the first ring opens the crypt gate.
--   The crypt, below: past the gate, the ossuary (skeletons, walls of bones),
--     the catacombs (zombies and a ghoul pack, loot in the niches), the
--     flooded vault (wade it), and the tomb of the wight: two skeleton
--     guards, the wight itself, the reliquary of St Morwen (the finish) and
--     the finish chest.
--   The secret way: in the north-west mausoleum, a loose brick opens a stair
--     under the floor, down to the flooded vault, without the bell.
--
-- Party of one to four, ranks 4 to 8.

local g = {}

local SX, SY, SZ = 96, 46, 96
local CR = 3                    -- the crypt's floor
local NG, NF = CR + 8, CR + 9   -- the ground, and where players stand on it

local ROCK = "default:stone"
local BRICK = "default:stonebrick"
local COBBLE = "default:cobble"
local WALLB = "default:brick"
local WHITE = "default:silver_sandstone_brick"
local WHITEB = "default:silver_sandstone_block"
local DARK = "default:obsidianbrick"
local ROOF = "stairs:stair_obsidianbrick"
local GRASS = "default:dirt_with_grass"
local LITTER = "default:dirt_with_coniferous_litter"
local DIRT = "default:dirt"
local GRAVEL = "default:gravel"
local PINE = "default:pine_tree"
local HEDGE = "default:pine_needles"
local FENCE = "default:fence_wood"
local TORCH = "default:torch_wall"
local TORCH_UP = "default:torch"
local LADDER = "default:ladder_wood"
local LAMP = "default:meselamp"
local WATER = "default:water_source"
local SIGN = "default:sign_wall_wood"
local SPAWNER = "orthoverse_monsters:spawner"
local CHEST = "orthoverse_loot:chest"
local HOLY = "orthoverse_props:consecrated"
local BONES = "orthoverse_props:bones"
local HEADSTONE = "orthoverse_props:headstone"
local FOG = "orthoverse_props:fog"
local GATE = "orthoverse_props:crypt_gate"
local SECRET = "orthoverse_props:secret_wall"

g.info = {
	name = "St Morwen's",
	line = "The bell of St Morwen's has not rung in forty years. The dead there do not lie still.",
	limit = 75,
	rank_min = 4, rank_max = 8,
	size = {x = SX, y = SY, z = SZ},
	ground = NG,
	dig = {{min = {x = 22, y = 0, z = 40}, max = {x = 72, y = NG - 1, z = 90}}},
	corner1 = {x = 2, y = 0, z = 11},
	corner2 = {x = 93, y = SY - 1, z = 93},
	start = {x = 48.5, y = NF, z = 13.5},
	arrival = {x = 48.5, y = NF, z = 5.5},
}

g.spawners, g.chests, g.signs = {}, {}, {}
g.finish = {x = 50, y = CR + 3, z = 87}
g.gate = {x = 48, y = NF, z = 8}
g.surface = NF
g.outside = {x = 4, y = NF, z = 4}
g.open_for_checks = {GATE, SECRET}
local TOMB = {x = 50, y = CR + 1, z = 78}
g.gated = {
	{label = "the tomb reachable without the crypt gate and the secret floor", target = TOMB,
		blocked = {{{x = 61, y = CR + 1, z = 59}, {x = 62, y = CR + 3, z = 59}},
			{{x = 27, y = 0, z = 75}, {x = 28, y = NG + 1, z = 77}}}},
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

local seed = 1349
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

-- A torch on a wall: `dir` is the way to the wall
local function torch(x, y, z, dir) set(x, y, z, TORCH, SIGN_P2[dir]) end

------------------------------------------------------------------------------
-- The ground, the crossroads, the hedge

local function ground()
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, DIRT)
	box(0, NG, 0, SX - 1, NG, SZ - 1, GRASS)
	-- under the churchyard, solid rock for the crypt to be cut from
	local d = g.info.dig[1]
	box(d.min.x, d.min.y, d.min.z, d.max.x, NG - 4, d.max.z, ROCK)
end

local function crossroads()
	box(0, NG, 4, SX - 1, NG, 5, GRAVEL)
	box(47, NG, 0, 49, NG, 10, GRAVEL)
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(44, NF, 8, "orthoverse_adventure:board", 0)
	-- the gibbet, empty but for its chain
	box(55, NF, 8, 55, NF + 4, 8, PINE)
	box(56, NF + 4, 8, 57, NF + 4, 8, PINE)
	box(57, NF + 2, 8, 57, NF + 3, 8, FENCE)
	sign(55, NF + 1, 7, "+z", "ST MORWEN'S\nThe bell of St Morwen's has not rung in forty years, and the dead " ..
		"there do not lie still. Ring it, and they say the dead stand still to listen.\nRight-click the gate to go " ..
		"in. Ranks 4 to 8.")
end

-- The thorn hedge, three high, all round
local function hedge()
	for x = 2, 93 do for _, z in ipairs({11, 93}) do box(x, NF, z, x, NF + 2, z, HEDGE) end end
	for z = 11, 93 do for _, x in ipairs({2, 93}) do box(x, NF, z, x, NF + 2, z, HEDGE) end end
end

------------------------------------------------------------------------------
-- The haunted forest: everything inside the hedge but the churchyard

local function in_yard(x, z) return x >= 22 and x <= 74 and z >= 30 and z <= 88 end

-- A dead tree: a tall bare trunk, and crooked twigs (jungle wood fences) reaching
-- out at different heights, turning up at their ends
local TWIG = "default:fence_junglewood"
local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
local function dead_tree(x, z, h)
	box(x, NF, z, x, NF + h - 1, z, PINE)
	local first = rnd(4)
	for b = 0, 1 + rnd(2) do
		local d = DIRS[(first + b) % 4 + 1]
		local y = NF + h - 1 - b * 2 - rnd(2)
		if y >= NF + 3 then
			local len = 1 + rnd(2)
			for k = 1, len do set(x + d[1] * k, y, z + d[2] * k, TWIG) end
			set(x + d[1] * len, y + 1, z + d[2] * len, TWIG)
		end
	end
	if rnd(2) == 0 then set(x, NF + h, z, TWIG) end
end

-- A dark pine, still alive: needles in rings narrowing to the top, none
-- lower than three blocks off the ground
local function pine(x, z, h)
	box(x, NF, z, x, NF + h - 1, z, PINE)
	for y = NF + 3, NF + h do
		local r = math.max(0, math.floor((NF + h - y) / 2.2))
		if y == NF + h then r = 0 end
		for dz = -r, r do for dx = -r, r do
			if (dx ~= 0 or dz ~= 0 or y == NF + h) and math.abs(dx) + math.abs(dz) <= r + 1 and get(x + dx, y, z + dz) == nil then
				set(x + dx, y, z + dz, HEDGE)
			end
		end end
	end
end

local function forest()
	for z = 12, 92 do for x = 3, 92 do
		if not in_yard(x, z) then set(x, NG, z, LITTER) end
	end end
	-- the path north from the gate
	box(47, NG, 12, 49, NG, 29, GRAVEL)
	-- dead pines, well clear of the hedge and the path
	for z = 16, 88, 5 do for x = 7, 88, 5 do
		local tx, tz = x + rnd(3) - 1, z + rnd(3) - 1
		local clear = tx >= 7 and tx <= 88 and tz >= 16 and tz <= 88 and not (tx >= 44 and tx <= 52 and tz <= 30)
			and not (tx >= 19 and tx <= 77 and tz >= 27 and tz <= 91)
		local r = rnd(6)
		if clear then
			if r <= 1 then dead_tree(tx, tz, 6 + rnd(4))
			elseif r == 2 then pine(tx, tz, 8 + rnd(3))
			elseif r == 3 then set(tx, NF, tz, PINE) end   -- a stump
		end
	end end
	for z = 12, 92 do for x = 3, 92 do
		if get(x, NG, z) == LITTER and get(x, NF, z) == nil and rnd(9) == 0 then set(x, NF, z, "default:dry_shrub") end
	end end
	for _, p in ipairs({{12, 18}, {30, 22}, {66, 22}, {84, 18}, {12, 50}, {84, 50}, {12, 80}, {84, 80}, {40, 91}, {60, 91}}) do
		set(p[1], NF, p[2], FOG)
	end
	spawner(16, NG, 22, "ghoul", 3, 10)
	spawner(80, NG, 48, "ghoul", 3, 10)
	spawner(14, NG, 70, "ghoul", 2, 10)
	spawner(32, NG, 18, "wisp", 2, 10)
	spawner(70, NG, 91, "wisp", 2, 10)
	chest(8, NF, 62, "common", 3)
end

------------------------------------------------------------------------------
-- The churchyard

local function grave(x, z, open)
	set(x, NF, z, HEADSTONE, 0)
	if open then
		spawner(x, NG, z + 1, "zombie", 2, 8)
		set(x, NG, z + 2, DIRT)
	else
		box(x, NG, z + 1, x, NG, z + 2, DIRT)
	end
end

local function yard()
	-- the brick wall, two high, its piers three
	for x = 22, 74 do for _, z in ipairs({30, 88}) do box(x, NF, z, x, NF + 1, z, WALLB) end end
	for z = 30, 88 do for _, x in ipairs({22, 74}) do box(x, NF, z, x, NF + 1, z, WALLB) end end
	for x = 22, 74, 6 do set(x, NF + 2, 30, WALLB); set(x, NF + 2, 88, WALLB) end
	for z = 30, 88, 6 do set(22, NF + 2, z, WALLB); set(74, NF + 2, z, WALLB) end
	-- the lych gate
	air(47, NF, 30, 49, NF + 2, 30)
	box(46, NF, 30, 46, NF + 3, 30, WALLB); box(50, NF, 30, 50, NF + 3, 30, WALLB)
	box(45, NF + 4, 29, 51, NF + 4, 31, "stairs:slab_wood")
	-- a fallen stretch of the north wall: the forest gets in
	air(60, NF, 88, 62, NF + 2, 88)
	-- the path and its lamps
	box(47, NG, 31, 49, NG, 43, GRAVEL)
	for z = 33, 43, 5 do
		for _, x in ipairs({46, 50}) do box(x, NF, z, x, NF + 1, z, FENCE); set(x, NF + 2, z, TORCH_UP, 1) end
	end
	-- graves: south of the church, and along its sides
	local open = {["29,37"] = true, ["64,33"] = true, ["31,52"] = true, ["67,56"] = true}
	for _, z in ipairs({33, 37, 41}) do
		for x = 26, 41, 3 do grave(x, z, open[x .. "," .. z]) end
		for x = 55, 70, 3 do grave(x, z, open[x .. "," .. z]) end
	end
	for _, z in ipairs({48, 52, 56}) do for x = 25, 34, 3 do grave(x, z, open[x .. "," .. z]) end end
	for _, z in ipairs({48, 52, 56, 60}) do for x = 61, 70, 3 do grave(x, z, open[x .. "," .. z]) end end
	for _, z in ipairs({84}) do for x = 36, 58, 4 do grave(x, z, false) end end
	spawner(40, NG, 46, "skeleton", 2, 8)
	for _, p in ipairs({{30, 44}, {66, 44}, {28, 64}, {68, 64}, {45, 85}}) do set(p[1], NF, p[2], FOG) end
end

-- A mausoleum: stone brick, a flat roof four high, a door to the south
local function mausoleum(x1, z1, x2, z2)
	box(x1, NF, z1, x2, NF + 3, z2, BRICK)
	air(x1 + 1, NF, z1 + 1, x2 - 1, NF + 2, z2 - 1)
	box(x1 + 1, NG, z1 + 1, x2 - 1, NG, z2 - 1, BRICK)
	box(x1 - 1, NF + 4, z1 - 1, x2 + 1, NF + 4, z2 + 1, "stairs:slab_stonebrick")
	local mx = math.floor((x1 + x2) / 2)
	air(mx, NF, z1, mx + 1, NF + 1, z1)
end

local function mausoleums()
	-- the north-west one: a sarcophagus, the loose brick, and under the floor
	-- the secret stair
	mausoleum(25, 73, 32, 82)
	box(30, NF, 79, 31, NF, 81, WHITEB)
	set(32, NF + 1, 76, "orthoverse_props:loose_brick", 1)
	torch(26, NF + 2, 78, "-x")
	for k = 0, 7 do
		local z, f = 75 + k, NG - 1 - k
		box(27, f, z, 28, f, z, COBBLE)
		air(27, f + 1, z, 28, math.min(NG, f + 3), z)
	end
	box(27, NG, 75, 28, NG, 77, SECRET)
	-- the north-east one: a chest among the coffins
	mausoleum(64, 73, 71, 82)
	box(65, NF, 79, 66, NF, 81, WHITEB); box(69, NF, 79, 70, NF, 81, WHITEB)
	chest(68, NF, 81, "common", 0)
end

------------------------------------------------------------------------------
-- The church

local function church()
	-- the nave: white walls eight high, the roof steep and dark
	box(39, NF, 52, 57, NF + 7, 78, WHITE)
	air(40, NF, 53, 56, NF + 17, 77)
	box(40, NG, 53, 56, NG, 77, HOLY)
	for x = 38, 58 do
		local up = 9 - math.abs(x - 48)
		local y = NF + 8 + up
		for z = 51, 79 do
			if x == 48 then set(x, y, z, DARK)
			else set(x, y, z, ROOF, x < 48 and 1 or 3) end
		end
		-- the gables
		if x >= 39 and x <= 57 then
			for _, z in ipairs({52, 78}) do box(x, NF + 8, z, x, y - 1, z, WHITE) end
		end
	end
	-- windows: tall, on both sides; the great window over the altar
	for _, z in ipairs({56, 60, 64, 72}) do box(39, NF + 2, z, 39, NF + 5, z, "default:glass") end
	for _, z in ipairs({56, 60, 64}) do box(57, NF + 2, z, 57, NF + 5, z, "default:glass") end
	box(46, NF + 3, 78, 50, NF + 8, 78, "default:glass")
	box(48, NF + 9, 78, 48, NF + 11, 78, "default:glass")
	-- pews, the altar, candles, the fonts
	for z = 56, 70, 2 do
		box(41, NF, z, 46, NF, z, "stairs:stair_wood", 2)
		box(50, NF, z, 55, NF, z, "stairs:stair_wood", 2)
	end
	box(42, NF, 74, 54, NF, 77, "stairs:slab_silver_sandstone_brick")
	box(46, NF, 76, 50, NF, 76, WHITEB)
	set(46, NF + 1, 76, TORCH_UP, 1); set(50, NF + 1, 76, TORCH_UP, 1)
	set(44, NF, 54, "orthoverse_props:font"); set(52, NF, 54, "orthoverse_props:font")
	for _, z in ipairs({58, 66, 74}) do torch(40, NF + 5, z, "-x"); torch(56, NF + 5, z, "+x") end
	-- the side chapel, west: a chest before a little altar
	box(32, NF, 59, 39, NF + 4, 68, WHITE)
	air(33, NF, 60, 38, NF + 3, 67)
	box(33, NG, 60, 38, NG, 67, HOLY)
	box(31, NF + 5, 58, 38, NF + 5, 69, "stairs:slab_obsidianbrick")
	air(39, NF, 63, 39, NF + 2, 64)
	box(34, NF, 63, 34, NF, 64, WHITEB)
	set(34, NF + 1, 63, TORCH_UP, 1)
	box(32, NF + 1, 62, 32, NF + 2, 65, "default:glass")
	chest(35, NF, 66, "common", 0)
	-- the sacristy, east: the crypt stair
	box(57, NF, 66, 64, NF + 4, 76, WHITE)
	air(58, NF, 67, 63, NF + 3, 75)
	box(58, NG, 67, 63, NG, 75, HOLY)
	box(58, NF + 5, 65, 65, NF + 5, 77, "stairs:slab_obsidianbrick")
	air(57, NF, 70, 57, NF + 2, 71)
	box(64, NF + 1, 70, 64, NF + 2, 72, "default:glass")
	torch(63, NF + 2, 74, "+x")
	chest(59, NF, 75, "weapon", 0)
	sign(59, NF + 1, 67, "-z", "THE SEXTON'S NOTE\nThe crypt gate will not open. It answers to the bell, they " ..
		"say, as the dead do. I am going up the tower.")
	-- the stair: down from the sacristy's floor, south under its wall
	for k = 0, 7 do
		local z, f = 69 - k, NG - 1 - k
		box(61, f, z, 62, f, z, COBBLE)
		air(61, f + 1, z, 62, math.min(NG, f + 3), z)
	end
	-- the tower, over the door
	box(44, NF, 44, 52, NF + 19, 52, WHITE)
	air(45, NF, 45, 51, NF + 18, 51)
	box(45, NG, 45, 51, NG, 51, HOLY)
	air(47, NF, 44, 49, NF + 2, 44); set(48, NF + 3, 44, "air")
	air(47, NF, 52, 49, NF + 2, 52)
	-- landings, ladders between them
	box(45, NF + 5, 45, 51, NF + 5, 51, "default:wood")
	box(45, NF + 10, 45, 51, NF + 10, 51, "default:wood")
	box(45, NF + 15, 45, 51, NF + 15, 51, "default:wood")
	box(45, NF, 48, 45, NF + 5, 48, LADDER, SIGN_P2["-x"])
	box(51, NF + 6, 48, 51, NF + 10, 48, LADDER, SIGN_P2["+x"])
	box(45, NF + 11, 50, 45, NF + 15, 50, LADDER, SIGN_P2["-x"])
	spawner(49, NF + 5, 50, "skeleton", 2, 6, true)
	spawner(47, NF + 10, 46, "skeleton", 2, 6, true)
	torch(51, NF + 7, 46, "+x"); torch(45, NF + 12, 46, "-x")
	for _, z in ipairs({47, 49}) do air(44, NF + 8, z, 44, NF + 9, z); air(52, NF + 8, z, 52, NF + 9, z) end
	-- the belfry: an arch each side, railed, and the bell
	for _, a in ipairs({{47, 44, 49, 44}, {47, 52, 49, 52}, {44, 47, 44, 49}, {52, 47, 52, 49}}) do
		air(a[1], NF + 16, a[2], a[3], NF + 18, a[4])
		box(a[1], NF + 16, a[2], a[3], NF + 16, a[4], FENCE)
	end
	set(48, NF + 18, 48, "orthoverse_props:bell")
	-- the spire
	local hw = {3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0}
	for l, w in ipairs(hw) do box(48 - w, NF + 19 + l, 48 - w, 48 + w, NF + 19 + l, 48 + w, DARK) end
	set(48, NF + 31, 48, "default:goldblock")
end

------------------------------------------------------------------------------
-- The crypt

local function corridor(x1, z1, x2, z2)
	box(x1, CR, z1, x2, CR, z2, COBBLE)
	air(x1, CR + 1, z1, x2, CR + 3, z2)
end

local function crypt()
	-- from the stair's foot south to the ossuary, through the crypt gate
	corridor(61, 57, 62, 62)
	box(61, CR + 1, 59, 62, CR + 3, 59, GATE, 0)
	torch(61, CR + 3, 61, "-x")
	-- the ossuary: walls of bones
	box(51, CR, 43, 69, CR + 6, 57, BONES)
	box(52, CR, 44, 68, CR, 56, COBBLE)
	air(52, CR + 1, 44, 68, CR + 5, 56)
	air(61, CR + 1, 57, 62, CR + 3, 57)
	for _, p in ipairs({{56, 48}, {64, 48}, {56, 52}, {64, 52}}) do box(p[1], CR + 1, p[2], p[1], CR + 5, p[2], BONES) end
	for _, p in ipairs({{60, 46}, {60, 54}}) do set(p[1], CR + 6, p[2], LAMP) end
	for _, p in ipairs({{53, 45}, {67, 55}, {58, 50}, {66, 46}}) do set(p[1], CR + 1, p[2], "bones:bones") end
	spawner(58, CR, 47, "skeleton", 3, 8)
	spawner(64, CR, 54, "skeleton", 2, 8)
	chest(67, CR + 1, 45, "common", 1)
	-- the catacombs: a grid of narrow ways, west of the ossuary
	for _, z in ipairs({44, 52, 60, 70}) do corridor(30, z, 50, z + 1) end
	for _, x in ipairs({30, 40, 49}) do corridor(x, 44, x + 1, 71) end
	corridor(51, 52, 51, 53)
	for _, p in ipairs({{30, 44}, {40, 52}, {49, 60}, {30, 70}, {40, 70}}) do set(p[1], CR + 4, p[2], LAMP) end
	-- niches in the walls: bones, coffins, and here and there loot
	local niches = {{34, 43}, {38, 46}, {44, 43}, {46, 46}, {34, 54}, {44, 51}, {36, 59}, {46, 62}, {34, 62},
		{36, 69}, {45, 72}, {29, 50}, {32, 66}, {42, 56}, {48, 66}}
	for _, n in ipairs(niches) do
		set(n[1], CR + 1, n[2], "air")
		set(n[1], CR + 2, n[2], "air")
		set(n[1], CR + 1, n[2], rnd(2) == 0 and "bones:bones" or WHITEB)
	end
	set(36, CR + 1, 43, "air"); chest(36, CR + 1, 43, "common", 2)
	set(44, CR + 2, 62, "air"); set(44, CR + 1, 62, "air"); chest(44, CR + 1, 62, "weapon", 0)
	set(29, CR + 2, 56, "air"); set(29, CR + 1, 56, "air"); chest(29, CR + 1, 56, "common", 3)
	spawner(35, CR, 52, "zombie", 2, 8)
	spawner(45, CR, 60, "zombie", 2, 8)
	spawner(40, CR, 66, "zombie", 2, 8)
	spawner(45, CR, 44, "ghoul", 2, 8)
	set(35, CR + 1, 61, FOG)
	-- north from the catacombs to the flooded vault
	corridor(30, 72, 31, 73)
	box(29, CR - 2, 74, 41, CR + 5, 85, BRICK)
	box(30, CR, 74, 40, CR, 74, COBBLE)
	air(30, CR + 1, 74, 40, CR + 4, 84)
	box(30, CR - 1, 75, 40, CR - 1, 84, GRAVEL)
	box(30, CR, 75, 40, CR, 84, WATER)
	for _, z in ipairs({76, 82}) do set(35, CR + 5, z, LAMP) end
	spawner(36, CR, 74, "zombie", 3, 8)
	set(33, CR + 1, 80, FOG)
	-- the secret stair's foot (from the mausoleum) comes in from the west
	corridor(27, 82, 29, 83)
	-- east, to the tomb
	box(41, CR, 82, 41, CR, 83, COBBLE)
	air(41, CR + 1, 82, 41, CR + 3, 83)
	-- the wight's tomb, under the altar
	box(41, CR, 73, 59, CR + 7, 89, BRICK)
	air(42, CR + 1, 74, 58, CR + 6, 88)
	box(42, CR, 74, 58, CR, 88, "default:stone_block")
	air(41, CR + 1, 82, 41, CR + 3, 83)
	for z = 76, 84, 4 do for _, x in ipairs({45, 55}) do box(x, CR + 1, z, x, CR + 6, z, BRICK) end end
	box(42, CR + 1, 85, 58, CR + 1, 88, "default:stone_block")
	box(48, CR + 1, 79, 52, CR + 1, 81, WHITEB)                -- the wight's sarcophagus, broken open
	set(50, CR + 1, 80, "air")
	set(50, CR + 2, 87, WHITEB)
	set(g.finish.x, g.finish.y, g.finish.z, "orthoverse_props:reliquary", 0)
	chest(53, CR + 2, 87, "finish", 0)
	for _, x in ipairs({44, 50, 56}) do set(x, CR + 7, 80, LAMP) end
	torch(42, CR + 4, 86, "-x"); torch(58, CR + 4, 86, "+x")
	spawner(50, CR, 77, "wight", 1, 10)
	spawner(45, CR + 1, 86, "skeleton", 2, 8)
	spawner(55, CR + 1, 86, "skeleton", 1, 8)
	sign(48, CR + 3, 88, "+z", "Cut in the stone: HERE LIES MORWEN'S LORD, WHO SWORE HE WOULD NOT DIE. " ..
		"HE KEPT HIS WORD.")
end

------------------------------------------------------------------------------

-- A plan below the ground, north at the top: "~" water, "1" the crypt's
-- ways, "#" solid
function g.plan()
	local rows = {}
	for z = SZ - 1, 0, -1 do
		local row = {}
		for x = 0, SX - 1 do
			local ch = "#"
			if get(x, CR, z) == WATER then ch = "~"
			elseif get(x, CR + 2, z) == "air" then ch = "1" end
			row[#row + 1] = ch
		end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, "\n")
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.spawners, g.chests, g.signs = {}, {}, {}
	seed = 1349
	ground()
	crossroads()
	hedge()
	forest()
	yard()
	mausoleums()
	church()
	crypt()
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
	for name in pairs(missing) do core.log("error", "[st_morwens] no such node: " .. name) end
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
