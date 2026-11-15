-- Death at the Château: builds the ready-made adventure in a world, so that
-- it can be saved as adventures/chateau.ovt (the compact form; see
-- tools/adventures/README.md).
--
--   local g = dofile(".../tools/adventures/chateau.lua")
--   g.build(origin)        -- origin: the south-west bottom corner
--   g.info                 -- what goes in adventures/chateau.json
--
-- Coordinates are relative to the origin: x east, z north, y up. The land's
-- ground is y = 8 (players stand at y = 9). A château in the style of
-- Versailles, a forecourt in front. One player at a time; no monsters. The
-- mystery (who, with what, where) is drawn at the start of each run by
-- mods/orthoverse_chateau/mystery.lua, which fills the clue places.
--
--   Ground floor, three by three (each room lined in its own finish):
--     La Bibliothèque     | La Galerie (mirrors) | Le Jardin d'Hiver
--     La Salle à Manger   | Le Grand Salon       | La Salle de Musique
--     La Salle d'Armes    | the entrance hall    | Le Bureau du Comte
--   The hall: the start, the grand staircase up (Lenoir's body at its foot),
--     a stair down to the cellar, the notice. The study's door is locked.
--   Below: La Cuisine (under the dining room, by the service stair), La Cave
--     à Vin (under the study, by the hall's stair). A rack in the cellar
--     turns (the menu's vintage) to a secret stair up into the study. From
--     the kitchen a tunnel runs under the house to the conservatory.
--   Upstairs: the guests' bedrooms, of no significance.
--   Puzzles: the false volume (a closet in the library); the wine rack (the
--     study); the piano (the tune on Geneviève's sheet music opens the
--     bench); the safe (the year on the Comte's portrait); the apothecary
--     cabinet (the gardener's key, in the kitchen).

local g = {}

local SX, SY, SZ = 72, 30, 70
local NG, NF = 8, 9         -- the land's ground (the ground floor), and where players stand on it
local B = 1                 -- the basement's floor (players stand at 2)
local CEIL = 15             -- the ground floor's ceiling
local UP = 16               -- the upper floor (players stand at 17)
local UPC = 21              -- its ceiling

local STONE = "orthoverse_chateau:stone"
local SLATE = "orthoverse_chateau:slate"
local CORNICE = "orthoverse_chateau:cornice"
local CEILING = "orthoverse_chateau:ceiling"
local PARQUET = "orthoverse_chateau:parquet"
local PANEL = "orthoverse_chateau:panel"
local WOOD = "orthoverse_chateau:panel_wood"
local FLAG = "orthoverse_chateau:flagstone"
local PANE = "default:glass"   -- (windows: whole blocks, so nobody outside can lean into the area)
local GLASS = "default:glass"
local FENCE = "default:fence_wood"
local CHANDELIER = "orthoverse_chateau:chandelier"
local CANDLES = "orthoverse_chateau:candles"
local GRAVEL = "default:gravel"
local ROCK = "default:stone"
local DIRT = "default:dirt"
local GRASS = "default:dirt_with_grass"
local SIGN = "default:sign_wall_wood"
local CHEST = "orthoverse_loot:chest"

g.info = {
	name = "Death at the Château",
	line = "Monsieur Lenoir came to dinner. He did not leave. Who killed him, with what, and where?",
	limit = 45,
	rank_min = 1, rank_max = 20,
	party_max = 1,
	finish_xp = 250,
	kit = {"orthoverse_chateau:casebook"},
	size = {x = SX, y = SY, z = SZ},
	ground = NG,
	dig = {{min = {x = 0, y = 0, z = 0}, max = {x = SX - 1, y = NG - 1, z = SZ - 1}}},
	corner1 = {x = 4, y = 0, z = 14},
	corner2 = {x = 67, y = SY - 1, z = 65},
	start = {x = 36.5, y = NF, z = 18.5},
	arrival = {x = 36.5, y = NF, z = 4.5},
}
g.compact = true

g.spawners = {}
g.chests = {}
g.signs = {}
g.spots = {}
g.finish = {x = 40, y = NF, z = 39}
g.gate = {x = 36, y = NF, z = 9}
g.surface = NF
g.outside = {x = 6, y = NF, z = 4}
g.rim = {}
-- For the checks: the secret ways open
g.open_for_checks = {"orthoverse_chateau:rack_door", "orthoverse_chateau:shelf_door"}
g.gated = {}

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
-- (a fill from y1 up to y2 that is empty when y2 < y1: under the steps)
local function upto(x1, y1, z1, x2, y2, z2, name)
	if y2 >= y1 then box(x1, y1, z1, x2, y2, z2, name) end
end
local function air_upto(x1, y1, z1, x2, y2, z2)
	if y2 >= y1 then box(x1, y1, z1, x2, y2, z2, "air") end
end
local function meta(x, y, z, fields) metas[#metas + 1] = {x = x, y = y, z = z, fields = fields, construct = true} end

-- param2 for a plate on a wall: the wall is to the north, east, south or west
local WALL = {n = 0, e = 1, s = 2, w = 3}
-- param2 for a block whose front faces south, west, north or east
local FACE = {s = 0, w = 1, n = 2, e = 3}

local SIGN_P2 = {["+x"] = 2, ["-x"] = 3, ["+z"] = 4, ["-z"] = 5}
local function sign(x, y, z, dir, text)
	set(x, y, z, SIGN, SIGN_P2[dir])
	g.signs[#g.signs + 1] = {x = x, y = y, z = z, dir = dir, text = text:match("^[^\n]*")}
	meta(x, y, z, {text = text, infotext = '"' .. text .. '"'})
end

local function chest(x, y, z, kind, param2)
	set(x, y, z, CHEST, param2 or 0)
	meta(x, y, z, {kind = kind, infotext = "Loot chest (" .. kind .. ")"})
	g.chests[#g.chests + 1] = {x = x, y = y, z = z, kind = kind}
end

-- A clue place: its block, what it is called, its room, the puzzle in front
-- of it (if any)
local function spot(x, y, z, name, param2, label, room, gate)
	set(x, y, z, "orthoverse_chateau:" .. name, param2)
	meta(x, y, z, {spot = label, room = room, gate = gate or "", infotext = label})
	g.spots[#g.spots + 1] = {x = x, y = y, z = z, label = label, room = room, gate = gate}
end

------------------------------------------------------------------------------
-- The plan: the château's cells (each the room's lining and what is in it),
-- between the structural walls at x 4, 25, 46, 67 and z 14, 31, 48, 65

local CELLS = {
	armes = {5, 15, 24, 30}, salle_a_manger = {5, 32, 24, 47}, bibliotheque = {5, 49, 24, 64},
	hall = {26, 15, 45, 30}, salon = {26, 32, 45, 47}, galerie = {26, 49, 45, 64},
	bureau = {47, 15, 66, 30}, musique = {47, 32, 66, 47}, jardin = {47, 49, 66, 64},
}
local LINING = {
	armes = "orthoverse_chateau:damask_green", salle_a_manger = "orthoverse_chateau:damask_red",
	bibliotheque = WOOD, hall = PANEL, salon = PANEL, galerie = PANEL, bureau = WOOD,
	musique = "orthoverse_chateau:damask_blue", jardin = nil,
}
local FLOOR = {
	armes = PARQUET, salle_a_manger = PARQUET, bibliotheque = PARQUET, hall = "orthoverse_chateau:marble_white",
	salon = PARQUET, galerie = "orthoverse_chateau:marble_white", bureau = PARQUET,
	musique = PARQUET, jardin = FLAG,
}

local function ground()
	box(0, 0, 0, SX - 1, NG - 4, SZ - 1, ROCK)
	box(0, NG - 3, 0, SX - 1, NG - 1, SZ - 1, DIRT)
	box(0, NG, 0, SX - 1, NG, SZ - 1, GRASS)
end

-- The forecourt: gravel, low hedges, lamps, the gate and its sign
local function forecourt()
	box(4, NG, 0, 67, NG, 13, GRAVEL)
	for _, x in ipairs({6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
			40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65}) do
		if x % 8 ~= 0 then set(x, NF, 12, "default:bush_leaves") end
	end
	for _, x in ipairs({8, 16, 24, 32, 40, 48, 56, 64}) do set(x, NF, 12, "default:mese_post_light") end
	set(g.gate.x, g.gate.y, g.gate.z, "orthoverse_adventure:gate", 0)
	set(38, NF, 9, "orthoverse_adventure:board", 0)
	box(32, NF, 9, 33, NF + 2, 9, STONE)
	sign(32, NF + 1, 8, "+z", "DEATH AT THE CHÂTEAU\nMonsieur Lenoir came to dinner. He did not leave.\n" ..
		"A murder mystery for one. No fighting.\nAll ranks.")
end

-- The shell: outer walls, floors, the ground floor's ceiling, the structural
-- walls between the cells, the rooms' linings
local function shell()
	-- outer and inner structural walls (ground floor)
	for _, x in ipairs({4, 25, 46, 67}) do box(x, NF, 14, x, CEIL, 65, STONE) end
	for _, z in ipairs({14, 31, 48, 65}) do box(4, NF, z, 67, CEIL, z, STONE) end
	-- floors and ceilings
	for id, c in pairs(CELLS) do
		box(c[1], NG, c[2], c[3], NG, c[4], FLOOR[id])
		box(c[1], CEIL, c[2], c[3], CEIL, c[4], CEILING)
		if LINING[id] then
			box(c[1], NF, c[2], c[3], CEIL - 1, c[2], LINING[id])
			box(c[1], NF, c[4], c[3], CEIL - 1, c[4], LINING[id])
			box(c[1], NF, c[2], c[1], CEIL - 1, c[4], LINING[id])
			box(c[3], NF, c[2], c[3], CEIL - 1, c[4], LINING[id])
		end
		-- a gilded cornice round the top of the walls
		if LINING[id] then
			for x = c[1], c[3] do set(x, CEIL - 1, c[2], CORNICE); set(x, CEIL - 1, c[4], CORNICE) end
			for z = c[2], c[4] do set(c[1], CEIL - 1, z, CORNICE); set(c[3], CEIL - 1, z, CORNICE) end
		end
	end
	-- outside: a cornice band at the ceiling's height
	for x = 4, 67 do set(x, CEIL, 14, CORNICE); set(x, CEIL, 65, CORNICE) end
	for z = 14, 65 do set(4, CEIL, z, CORNICE); set(67, CEIL, z, CORNICE) end
end

-- A doorway through a wall and the linings either side, 2 wide (or more)
local function doorway_x(x, z1, z2, h)     -- through the wall at x (x - 1 .. x + 1)
	air(x - 1, NF, z1, x + 1, NF + (h or 3) - 1, z2)
end
local function doorway_z(z, x1, x2, h)
	air(x1, NF, z - 1, x2, NF + (h or 3) - 1, z + 1)
end

-- Windows in the outer walls: a pane in the wall, a niche in the lining
local function windows()
	local function win_z(z, x, inner)   -- in a north or south wall
		for y = NF + 1, NF + 4 do set(x, y, z, PANE, 0); if inner then set(x, y, inner, "air") end end
	end
	local function win_x(x, z, inner)
		for y = NF + 1, NF + 4 do set(x, y, z, PANE, 1); if inner then set(inner, y, z, "air") end end
	end
	for _, x in ipairs({9, 14, 19, 51, 56, 61}) do win_z(14, x, 15) end
	for _, x in ipairs({29, 32, 39, 42}) do win_z(14, x, 15) end
	for _, x in ipairs({9, 19}) do win_z(65, x, 64) end
	for _, x in ipairs({31, 40}) do win_z(65, x, 64) end
	for _, z in ipairs({19, 26, 36, 43}) do win_x(4, z, 5) end
	for _, z in ipairs({53, 58}) do win_x(4, z, 5) end
	for _, z in ipairs({19, 26, 36, 43}) do win_x(67, z, 66) end
end

local function chandeliers(id, list)
	for _, p in ipairs(list) do set(p[1], CEIL - 1, p[2], CHANDELIER) end
end

------------------------------------------------------------------------------
-- The rooms

local function hall()
	local c = CELLS.hall
	-- the front doors (locked: the storm), and the doors to the study
	air(35, NF, 15, 36, NF + 1, 15)
	for _, x in ipairs({35, 36}) do
		set(x, NF, 14, "orthoverse_chateau:door_low", 0); set(x, NF + 1, 14, "orthoverse_chateau:door_high", 0)
	end
	air(45, NF, 21, 47, NF + 1, 22)
	for _, z in ipairs({21, 22}) do
		set(46, NF, z, "orthoverse_chateau:door_low", 1); set(46, NF + 1, z, "orthoverse_chateau:door_high", 1)
	end
	-- to the armoury, to the salon
	doorway_x(25, 21, 22)
	doorway_z(31, 34, 37, 4)
	-- a carpet up the middle
	box(34, NG, 16, 37, NG, 29, "orthoverse_chateau:carpet")
	-- the grand staircase: up the west side from z 18 to the landing (room
	-- to walk on to it from the south)
	for k = 1, 8 do
		local z = 17 + k
		box(27, NF, z, 28, NG + k, z, PARQUET)
		box(27, NG + k, z, 28, NG + k, z, "stairs:stair_wood", 0)
	end
	air(27, CEIL, 21, 28, CEIL, 23)
	air(27, UP, 21, 28, UP, 24)
	box(29, NF, 19, 29, NF, 25, FENCE)      -- the banister
	-- Lenoir, at its foot
	set(30, NF, 17, "orthoverse_chateau:rug", FACE.e)
	-- the stair down to the cellar: down the east side, northwards
	for k = 1, 7 do
		local z = 22 + k
		air_upto(43, NG - k + 2, z, 44, NG, z)
		set(43, NG - k + 1, z, "stairs:stair_stone", 2); set(44, NG - k + 1, z, "stairs:stair_stone", 2)
		upto(43, B + 1, z, 44, NG - k, z, ROCK)
	end
	box(42, NF, 23, 42, NF, 29, FENCE)
	-- fittings: the clock, mirrors, the notice, light
	set(32, NF, 16, "orthoverse_chateau:clock_case", FACE.n)
	set(32, NF + 1, 16, "orthoverse_chateau:clock", FACE.n)
	set(44, NF + 2, 18, "orthoverse_chateau:notice", WALL.e)
	set(32, NF + 2, 29, "orthoverse_chateau:mirror", WALL.n)
	set(39, NF + 2, 29, "orthoverse_chateau:mirror", WALL.n)
	chandeliers("hall", {{35, 19}, {35, 26}, {40, 19}})
	set(39, NF, 16, "orthoverse_chateau:table", 0); set(39, NF + 1, 16, CANDLES)
end

local function armes()
	local c = CELLS.armes
	doorway_z(31, 14, 15)
	box(12, NF, 20, 13, NF, 24, "orthoverse_chateau:billiard_table")
	set(6, NF + 2, 22, "orthoverse_chateau:pistols", WALL.w)
	set(6, NF + 2, 17, "orthoverse_chateau:mirror", WALL.w)
	set(6, NF + 2, 27, "orthoverse_chateau:mirror", WALL.w)
	set(20, NF, 26, "orthoverse_chateau:table", 0)
	spot(20, NF + 1, 26, "spot_box", 0, "a cigar box", "armes")
	spot(23, NF, 17, "spot_drawers", FACE.w, "the cue cabinet", "armes")
	set(18, NF, 28, "orthoverse_chateau:armchair", FACE.s)
	set(16, NF, 28, "orthoverse_chateau:armchair", FACE.s)
	chandeliers("armes", {{12, 19}, {12, 25}, {19, 22}})
end

local function salle_a_manger()
	-- to the salon, to the library
	doorway_x(25, 39, 40)
	doorway_z(48, 14, 15)
	-- the banquet table, and the guests round it
	box(11, NF, 39, 20, NF, 40, "orthoverse_chateau:dining_table")
	local seats = {
		{21, 39, WALL.e, "comte"}, {21, 40, WALL.e, nil},
		{12, 38, WALL.s, "marquise"}, {15, 38, WALL.s, "general"}, {18, 38, WALL.s, "ivoire"},
		{12, 41, WALL.n, "emeraude"}, {15, 41, WALL.n, "duc"}, {18, 41, WALL.n, "docteur"},
		{10, 39, WALL.w, "or"}, {10, 40, WALL.w, nil},
	}
	for _, s in ipairs(seats) do
		-- (a chair's back is toward its param2's wall)
		if s[4] then
			set(s[1], NF, s[2], "orthoverse_chateau:guest_chair", s[3])
			meta(s[1], NF, s[2], {guest = s[4], infotext = ""})
		else
			set(s[1], NF, s[2], "orthoverse_chateau:chair", s[3])
		end
	end
	set(11, NF + 1, 40, "orthoverse_chateau:goblet_spilt", 0)     -- Lenoir's place, at the foot
	set(15, NF + 1, 39, "orthoverse_chateau:candlestick")
	set(13, NF + 1, 40, CANDLES); set(18, NF + 1, 40, CANDLES)
	for _, p in ipairs({{12, 39}, {17, 39}, {12, 40}, {15, 40}, {19, 39}, {20, 40}}) do
		set(p[1], NF + 1, p[2], "orthoverse_chateau:goblet")
	end
	set(20, NF + 1, 39, "orthoverse_chateau:menu_card")
	spot(16, NF + 1, 40, "spot_papers", 0, "a napkin, folded with something inside", "salle_a_manger")
	spot(14, NF, 46, "spot_drawers", FACE.s, "the sideboard", "salle_a_manger")
	set(15, NF, 46, "orthoverse_chateau:drawers", FACE.s)
	-- the service stair down to the kitchen: down the west side, northwards
	for k = 1, 7 do
		local z = 33 + k
		air_upto(6, NG - k + 2, z, 7, NG, z)
		set(6, NG - k + 1, z, "stairs:stair_wood", 2); set(7, NG - k + 1, z, "stairs:stair_wood", 2)
		upto(6, B + 1, z, 7, NG - k, z, ROCK)
	end
	box(8, NF, 34, 8, NF, 40, FENCE)
	box(6, NF, 41, 8, NF, 41, FENCE)
	set(23, NF + 2, 36, "orthoverse_chateau:mirror", WALL.e)
	set(23, NF + 2, 43, "orthoverse_chateau:mirror", WALL.e)
	chandeliers("salle_a_manger", {{13, 39}, {18, 40}})
end

local function bibliotheque()
	local c = CELLS.bibliotheque
	doorway_x(25, 56, 57)
	-- shelves on the west and north walls
	box(5, NF, 50, 5, NF + 4, 63, "default:bookshelf")
	box(6, NF, 64, 23, NF + 4, 64, "default:bookshelf")
	-- the hearth, in the north wall
	air(14, NF, 64, 15, NF + 1, 64)
	set(14, NF, 64, "orthoverse_chateau:fireplace", FACE.s); set(15, NF, 64, "orthoverse_chateau:fireplace", FACE.s)
	set(16, NF, 63, "orthoverse_chateau:fire_irons")
	set(13, NF, 61, "orthoverse_chateau:armchair", FACE.n)
	set(17, NF, 61, "orthoverse_chateau:armchair", FACE.n)
	-- the reading tables
	box(12, NF, 54, 13, NF, 55, "orthoverse_chateau:table")
	spot(12, NF + 1, 55, "spot_papers", 0, "the reading table", "bibliotheque")
	set(13, NF + 1, 54, CANDLES)
	box(18, NF, 54, 19, NF, 55, "orthoverse_chateau:table")
	set(18, NF + 1, 55, CANDLES)
	-- the closet in the north-west corner, behind shelves; one volume is false
	box(9, NF, 60, 9, NF + 4, 63, "default:bookshelf")
	box(6, NF, 60, 9, NF + 4, 60, "default:bookshelf")
	air(6, NF, 61, 8, NF + 2, 63)
	set(9, NF, 62, "orthoverse_chateau:shelf_door", FACE.e)
	set(9, NF + 1, 62, "orthoverse_chateau:shelf_door", FACE.e)
	set(9, NF + 2, 61, "orthoverse_chateau:false_book", FACE.e)
	spot(7, NF, 63, "spot_box", 0, "a strongbox in the hidden closet", "bibliotheque", "closet")
	set(6, NF, 61, CANDLES)
	g.gated[#g.gated + 1] = {label = "the library's closet reachable without the false volume",
		target = {x = 7, y = NF, z = 62}, blocked = {{{x = 9, y = NF, z = 62}, {x = 9, y = NF + 1, z = 62}}}}
	chandeliers("bibliotheque", {{15, 55}, {15, 60}})
end

local function galerie()
	doorway_z(48, 34, 37, 4)
	box(27, NG, 50, 44, NG, 63, "orthoverse_chateau:marble_white")
	for x = 27, 44 do for z = 50, 63 do
		if (x + z) % 2 == 0 then set(x, NG, z, "orthoverse_chateau:marble_black") end
	end end
	for _, x in ipairs({28, 34, 37, 43}) do
		set(x, NF + 1, 63, "orthoverse_chateau:mirror", WALL.n)
		set(x, NF + 2, 63, "orthoverse_chateau:mirror", WALL.n)
	end
	chandeliers("galerie", {{30, 56}, {35, 56}, {40, 56}})
	set(36, NF, 63, "orthoverse_chateau:clock_case", FACE.s)
	set(36, NF + 1, 63, "orthoverse_chateau:clock", FACE.s)
end

local function salon()
	doorway_x(46, 39, 40)
	box(29, NG, 35, 42, NG, 44, "orthoverse_chateau:carpet")
	-- the fireplace in the west wall
	set(26, NF, 35, "orthoverse_chateau:fireplace", FACE.e); set(26, NF, 36, "orthoverse_chateau:fireplace", FACE.e)
	-- the portraits: south and north walls
	local south = {"comte", "marquise", "general", "ivoire"}
	local north = {"emeraude", "duc", "docteur", "or"}
	for i, id in ipairs(south) do set(28 + (i - 1) * 2 + (i > 2 and 7 or 0), NF + 2, 33, "orthoverse_chateau:portrait_" .. id, WALL.s) end
	for i, id in ipairs(north) do set(28 + (i - 1) * 2 + (i > 2 and 7 or 0), NF + 2, 46, "orthoverse_chateau:portrait_" .. id, WALL.n) end
	set(44, NF + 2, 36, "orthoverse_chateau:portrait_lenoir", WALL.e)
	-- Madame Or's table, and the accusation
	set(31, NF, 39, "orthoverse_chateau:fortune_table", 0)
	set(30, NF, 39, "orthoverse_chateau:chair", WALL.w)
	set(32, NF, 39, "orthoverse_chateau:chair", WALL.e)
	set(31, NF, 38, CANDLES)
	set(40, NF, 39, "orthoverse_chateau:accusation_desk", 0)
	chest(41, NF, 40, "finish", 0)
	-- armchairs, a writing bureau
	spot(35, NF, 44, "spot_armchair", FACE.s, "an armchair by the fire (down the side of the cushion)", "salon")
	set(37, NF, 44, "orthoverse_chateau:armchair", FACE.s)
	set(28, NF, 37, "orthoverse_chateau:armchair", FACE.e)
	set(43, NF, 45, "orthoverse_chateau:desk", FACE.s)
	spot(43, NF + 1, 45, "spot_papers", 0, "the writing bureau", "salon")
	chandeliers("salon", {{31, 36}, {40, 36}, {31, 43}, {40, 43}, {35, 40}})
end

local function musique()
	doorway_z(48, 56, 57)
	-- the piano, its bench, the music stand
	set(55, NF, 40, "orthoverse_chateau:piano", FACE.s)
	set(56, NF, 40, "orthoverse_chateau:piano_body", 0)
	set(55, NF, 41, "orthoverse_chateau:piano_body", 0)
	set(56, NF, 41, "orthoverse_chateau:piano_body", 0)
	spot(55, NF, 39, "spot_bench", 0, "the piano bench", "musique", "piano")
	set(52, NF, 39, "orthoverse_chateau:music_stand")
	set(60, NF, 43, "orthoverse_chateau:harp")
	-- the curtains on the east wall, one with its cord
	for _, z in ipairs({35, 38, 41, 44}) do
		for y = NF + 1, NF + 4 do set(65, y, z, "orthoverse_chateau:curtain_plain", WALL.e) end
	end
	set(65, NF + 2, 38, "orthoverse_chateau:curtain", WALL.e)
	-- the audience's chairs
	for _, x in ipairs({51, 53, 57, 59}) do set(x, NF, 35, "orthoverse_chateau:chair", WALL.s) end
	spot(61, NF, 35, "spot_armchair", FACE.n, "an armchair at the back", "musique")
	spot(48, NF, 45, "spot_drawers", FACE.e, "a music cabinet", "musique")
	chandeliers("musique", {{55, 37}, {55, 44}, {61, 40}})
end

local function jardin()
	local c = CELLS.jardin
	-- glass walls outside, a glass roof
	box(48, NF, 65, 66, CEIL - 1, 65, GLASS)
	box(67, NF, 49, 67, CEIL - 1, 64, GLASS)
	for _, x in ipairs({50, 55, 60, 65}) do box(x, NF, 65, x, CEIL - 1, 65, STONE) end
	for _, z in ipairs({52, 57, 62}) do box(67, NF, z, 67, CEIL - 1, z, STONE) end
	box(47, NF, 49, 47, CEIL - 1, 64, "orthoverse_chateau:panel")
	box(48, NF, 49, 66, CEIL - 1, 49, "orthoverse_chateau:panel")
	-- the dome: glass, stepping in
	for i = 0, 5 do
		local y = CEIL + i
		for x = 47 + i, 66 - i do for z = 49 + i, 64 - i do
			local edge = x == 47 + i or x == 66 - i or z == 49 + i or z == 64 - i
			if edge or i == 5 then set(x, y, z, GLASS) end
		end end
		if i == 0 then box(48, y, 50, 65, y, 63, "air") end
	end
	-- beds of plants
	for _, b in ipairs({{49, 51, 53, 54}, {60, 51, 64, 54}, {49, 60, 51, 63}, {61, 60, 64, 63}}) do
		box(b[1], NG, b[2], b[3], NG, b[4], GRASS)
		for x = b[1], b[3] do for z = b[2], b[4] do
			local plant = ({"default:fern_1", "default:junglegrass", "flowers:viola", "flowers:tulip",
				"flowers:rose", "default:fern_1", "flowers:geranium"})[(x * 3 + z * 7) % 7 + 1]
			set(x, NF, z, plant)
		end end
	end
	set(48, NF, 52, "orthoverse_chateau:cabinet", FACE.e)
	set(48, NF, 53, "orthoverse_chateau:drawers", FACE.e)
	box(56, NF, 51, 57, NF, 51, "orthoverse_chateau:table")
	spot(56, NF + 1, 51, "spot_box", 0, "the potting bench", "jardin")
	set(57, NF + 1, 51, CANDLES)
	spot(65, NF, 58, "spot_barrel", 0, "a water butt", "jardin")
	-- light: chandeliers hung from the top of the dome, lamps on posts
	set(54, CEIL + 4, 56, CHANDELIER); set(59, CEIL + 4, 57, CHANDELIER)
	for _, lp in ipairs({{50, 57}, {64, 57}, {57, 62}, {57, 54}}) do set(lp[1], NF, lp[2], "default:mese_post_light") end
	-- (its doors: from the music room and the gallery)
	doorway_z(48, 56, 57)
	doorway_x(46, 56, 57)
	-- where the tunnel comes up: a stair rising east, the floor open over it
	for k = 1, 7 do
		local x = 51 + k
		air(x, B + k, 57, x, NG, 58)
		set(x, B + k, 57, "stairs:stair_cobble", 1); set(x, B + k, 58, "stairs:stair_cobble", 1)
		upto(x, B + 1, 57, x, B + k - 1, 58, ROCK)
	end
	box(51, NF, 56, 57, NF, 56, FENCE)
	box(51, NF, 59, 57, NF, 59, FENCE)
	box(51, NF, 57, 51, NF, 58, FENCE)
end

local function bureau()
	-- mahogany, the desk, the safe; the secret stair's head, railed
	box(55, NF, 22, 56, NF, 22, "orthoverse_chateau:desk", FACE.s)
	set(55, NF + 1, 22, "orthoverse_chateau:letter_opener", 0)
	spot(56, NF + 1, 22, "spot_papers", 0, "the papers on the Comte's desk", "bureau", "study")
	set(55, NF, 23, "orthoverse_chateau:chair", WALL.n)
	spot(65, NF + 2, 28, "safe", WALL.e, "the wall safe", "bureau", "safe")
	spot(48, NF, 27, "spot_drawers", FACE.e, "the locked drawers (forced long ago)", "bureau", "study")
	set(48, NF, 26, "orthoverse_chateau:drawers", FACE.e)
	set(57, NF, 29, "default:bookshelf"); set(58, NF, 29, "default:bookshelf")
	set(52, NF + 2, 29, "orthoverse_chateau:mirror", WALL.n)
	set(50, NF, 18, "orthoverse_chateau:armchair", FACE.e)
	chandeliers("bureau", {{55, 20}, {55, 26}})
	-- the hole over the secret stair, railed
	box(63, NF, 17, 63, NF, 24, FENCE)
	box(63, NF, 24, 65, NF, 24, FENCE)
end

-- Below ground: the kitchen, the cellar, the tunnel, the secret stair
local function basement()
	-- the kitchen, under the dining room
	box(5, B, 32, 24, B + 6, 47, STONE)
	box(6, B, 33, 23, B, 46, "orthoverse_chateau:kitchen_tile")
	air(6, B + 1, 33, 23, B + 6, 46)
	-- (the service stair comes down its west side: keep its steps)
	for k = 1, 7 do
		local z = 33 + k
		set(6, NG - k + 1, z, "stairs:stair_wood", 2); set(7, NG - k + 1, z, "stairs:stair_wood", 2)
		upto(6, B + 1, z, 7, NG - k, z, STONE)
		air_upto(6, NG - k + 2, z, 7, B + 6, z)
	end
	box(12, B + 1, 39, 17, B + 1, 40, "orthoverse_chateau:table")
	set(13, B + 2, 39, CANDLES); set(16, B + 2, 40, CANDLES)
	for _, x in ipairs({10, 13, 16, 19}) do set(x, B + 1, 33, "orthoverse_chateau:oven", FACE.n) end
	for _, x in ipairs({9, 11, 18, 20, 22}) do set(x, B + 3, 46, "orthoverse_chateau:copper", WALL.n) end
	set(23, B + 3, 42, "orthoverse_chateau:keyhook", WALL.e)
	spot(22, B + 1, 34, "spot_barrel", 0, "the flour barrel", "cuisine")
	spot(20, B + 1, 46, "spot_drawers", FACE.s, "the pantry dresser", "cuisine")
	set(21, B + 1, 46, "orthoverse_chateau:drawers", FACE.s)
	for _, cp in ipairs({{10, 36}, {10, 43}, {16, 36}, {16, 43}, {21, 39}}) do set(cp[1], B + 6, cp[2], CHANDELIER) end
	-- the tunnel to the conservatory: north from the kitchen, then east
	air(14, B + 1, 47, 15, B + 3, 58)
	air(14, B + 1, 57, 51, B + 3, 58)
	for z = 47, 58 do
		for _, x in ipairs({13, 16}) do for y = B + 1, B + 3 do
			if x == 13 or z <= 56 then set(x, y, z, "default:mossycobble") end
		end end
		set(14, B, z, "default:mossycobble"); set(15, B, z, "default:mossycobble")
		set(14, B + 4, z, "default:mossycobble"); set(15, B + 4, z, "default:mossycobble")
	end
	for x = 13, 51 do
		for _, z in ipairs({56, 59}) do for y = B + 1, B + 3 do
			if not (x >= 14 and x <= 15 and z == 56) then set(x, y, z, "default:mossycobble") end
		end end
		set(x, B, 57, "default:mossycobble"); set(x, B, 58, "default:mossycobble")
		set(x, B + 4, 57, "default:mossycobble"); set(x, B + 4, 58, "default:mossycobble")
	end
	air(14, B + 1, 57, 15, B + 3, 58)
	for x = 17, 49, 4 do set(x, B + 1, (x % 8 == 1) and 57 or 58, "orthoverse_chateau:ivy") end
	for z = 50, 56, 3 do set(15, B + 1, z, "orthoverse_chateau:ivy") end
	for x = 20, 48, 9 do set(x, B + 3, 57, "default:torch_wall", 5) end   -- (on the wall to the south)
	set(14, B + 3, 52, "default:torch_wall", 3)
	-- the cellar, under the study and the hall's east side
	box(42, B, 15, 67, B + 6, 32, STONE)
	box(43, B, 16, 66, B, 31, FLAG)
	air(43, B + 1, 16, 66, B + 6, 31)
	-- (the hall's stair comes down at its west side)
	for k = 1, 7 do
		local z = 22 + k
		set(43, NG - k + 1, z, "stairs:stair_stone", 2); set(44, NG - k + 1, z, "stairs:stair_stone", 2)
		upto(43, B + 1, z, 44, NG - k, z, ROCK)
		air_upto(43, NG - k + 2, z, 44, B + 6, z)
	end
	box(43, B + 1, 16, 44, B + 6, 22, ROCK)
	-- racks along the walls, barrels in rows
	for x = 46, 62 do for y = B + 1, B + 4 do set(x, y, 31, "orthoverse_chateau:wine_rack", FACE.s) end end
	for z = 25, 30 do for y = B + 1, B + 4 do set(66, y, z, "orthoverse_chateau:wine_rack", FACE.w) end end
	for _, row in ipairs({19, 22}) do
		for x = 47, 59, 2 do set(x, B + 1, row, "orthoverse_chateau:barrel", 0) end
	end
	spot(50, B + 1, 28, "spot_barrel", 0, "a barrel marked 'vinegar'", "cave")
	set(56, B + 1, 26, "orthoverse_chateau:table")
	spot(56, B + 2, 26, "spot_box", 0, "the steward's cash box", "cave")
	set(57, B + 1, 26, "orthoverse_chateau:table"); set(57, B + 2, 26, CANDLES)
	for _, cp in ipairs({{47, 27}, {53, 27}, {59, 27}, {53, 17}, {48, 17}, {59, 17}}) do set(cp[1], B + 6, cp[2], CHANDELIER) end
	-- the secret stair: up to the study, behind a rack that turns
	box(63, B + 1, 16, 63, B + 6, 24, STONE)
	box(66, B + 1, 16, 66, B + 6, 23, STONE)
	box(64, B + 1, 15, 65, B + 6, 15, STONE)
	for k = 1, 7 do
		local z = 24 - k
		set(64, B + k, z, "stairs:stair_stone", 2); set(65, B + k, z, "stairs:stair_stone", 2)
		upto(64, B + 1, z, 65, B + k - 1, z, ROCK)
		air_upto(64, B + k + 1, z, 65, B + 6, z)
	end
	-- (the last step is the study's floor; the floor is open over the rest)
	air(64, NG, 18, 65, NG, 23)
	air(64, B + 1, 24, 65, B + 6, 24)
	set(64, B + 1, 24, "orthoverse_chateau:rack_door", FACE.n); set(65, B + 1, 24, "orthoverse_chateau:rack_door", FACE.n)
	set(64, B + 2, 24, "orthoverse_chateau:rack_door", FACE.n); set(65, B + 2, 24, "orthoverse_chateau:rack_door", FACE.n)
	set(64, B + 3, 24, "orthoverse_chateau:rack_door", FACE.n); set(65, B + 3, 24, "orthoverse_chateau:rack_door", FACE.n)
	for y = B + 4, B + 6 do
		set(64, y, 24, "orthoverse_chateau:wine_rack", FACE.n); set(65, y, 24, "orthoverse_chateau:wine_rack", FACE.n)
	end
	for _, x in ipairs({62, 66}) do for y = B + 1, B + 4 do set(x, y, 24, "orthoverse_chateau:wine_rack", FACE.n) end end
	g.gated[#g.gated + 1] = {label = "the study reachable without turning the rack",
		target = {x = 56, y = NF, z = 20}, blocked = {{{x = 64, y = B + 1, z = 24}, {x = 65, y = B + 3, z = 24}}}}
end

-- Upstairs: the landing, a corridor, the bedrooms (of no significance)
local function upstairs()
	box(25, UP, 14, 46, UPC + 1, 48, STONE)
	box(26, UP, 15, 45, UP, 47, PARQUET)
	box(26, UPC, 15, 45, UPC, 47, CEILING)
	-- the landing (over the stairwell), the corridor
	air(26, UP + 1, 15, 33, UPC - 1, 26)
	air(34, UP + 1, 15, 37, UPC - 1, 47)
	box(26, UP + 1, 15, 33, UPC - 1, 15, PANEL)
	box(26, UP + 1, 15, 26, UPC - 1, 26, PANEL)
	air(27, CEIL, 21, 28, CEIL, 23)
	air(27, UP, 21, 28, UP, 24)
	-- (the staircase's top step, in the floor)
	set(27, UP, 25, "stairs:stair_wood", 0); set(28, UP, 25, "stairs:stair_wood", 0)
	box(29, UP + 1, 20, 29, UP + 1, 24, FENCE)
	box(27, UP + 1, 20, 28, UP + 1, 20, FENCE)
	-- bedrooms: west of the corridor (south of the landing is the stair) and east
	local rooms = {{27, 28, 32, 33}, {27, 35, 32, 40}, {27, 42, 32, 46}, {39, 16, 44, 21}, {39, 23, 44, 29},
		{39, 31, 44, 37}, {39, 39, 44, 46}}
	for _, r in ipairs(rooms) do
		air(r[1], UP + 1, r[2], r[3], UPC - 1, r[4])
		local door_x = r[1] < 34 and 33 or 38
		local zd = math.floor((r[2] + r[4]) / 2)
		air(door_x, UP + 1, zd, door_x, UP + 2, zd)
		local bx = r[1] < 34 and r[1] or r[3]
		set(bx, UP + 1, zd - 1, "orthoverse_chateau:bed", r[1] < 34 and WALL.w or WALL.e)
		set(bx, UP + 1, zd, "orthoverse_chateau:bed", r[1] < 34 and WALL.w or WALL.e)
		set(bx, UP + 1, zd - 2, "orthoverse_chateau:drawers", r[1] < 34 and FACE.e or FACE.w)
		set(bx, UP + 2, zd - 2, CANDLES)
		set(math.floor((r[1] + r[3]) / 2), UPC - 1, zd, CHANDELIER)
	end
	for z = 18, 44, 6 do set(35, UPC - 1, z, CHANDELIER) end
	-- windows over the wings' roofs and at the front
	for _, z in ipairs({18, 24, 30, 37, 44}) do
		for y = UP + 2, UP + 3 do set(25, y, z, PANE, 1); set(46, y, z, PANE, 1) end
	end
	for _, x in ipairs({29, 32, 36, 40, 43}) do for y = UP + 2, UP + 3 do set(x, y, 14, PANE, 0) end end
	for x = 25, 46 do set(x, UPC + 1, 14, CORNICE); set(x, UPC + 1, 48, CORNICE) end
end

-- Roofs: slate, hipped; the middle higher than the wings
local function roofs()
	local function hip(x1, z1, x2, z2, y0, top)
		for x = x1, x2 do for z = z1, z2 do
			local d = math.min(x - x1, x2 - x, z - z1, z2 - z)
			for y = y0, math.min(y0 + d, top) do set(x, y, z, SLATE) end
		end end
	end
	hip(4, 14, 25, 65, CEIL + 1, CEIL + 6)        -- the west wing and the library
	hip(46, 14, 67, 48, CEIL + 1, CEIL + 6)       -- the east wing (not the conservatory)
	hip(25, 48, 46, 65, CEIL + 1, CEIL + 5)       -- the gallery
	hip(25, 14, 46, 48, UPC + 2, SY - 1)          -- the middle
end

------------------------------------------------------------------------------

function g.plan()
	local out = {}
	for _, lv in ipairs({{"the ground floor", NF}, {"below", B + 1}, {"upstairs", UP + 1}}) do
		out[#out + 1] = "-- " .. lv[1]
		for z = SZ - 1, 0, -1 do
			local row = {}
			for x = 0, SX - 1 do
				local n = get(x, lv[2], z)
				local ch = "#"
				if n == "air" then ch = "." elseif n:find("spot_") or n:find(":safe") then ch = "?"
				elseif n:find("door") then ch = "D" elseif n:find("stair") then ch = "/" elseif n == FENCE then ch = "+"
				elseif n:find("chair") then ch = "h" elseif n:find("table") or n:find("desk") then ch = "T"
				elseif n == PANE or n == GLASS then ch = "=" end
				row[#row + 1] = ch
			end
			out[#out + 1] = table.concat(row)
		end
	end
	return table.concat(out, "\n")
end

-- Extra checks: every clue place, weapon place and puzzle can be reached
-- (with the secret ways open)
function g.check_more(O, t)
	local start = vector.add(O, vector.round({x = g.info.start.x - 0.5, y = g.info.start.y, z = g.info.start.z - 0.5}))
	local seen, key = t.reach(O, start)
	local function near(p)
		for dx = -2, 2 do for dz = -2, 2 do for dy = -2, 1 do
			if seen[key(vector.add(p, {x = dx, y = dy, z = dz}))] then return true end
		end end end
	end
	local bad = {}
	for _, s in ipairs(g.spots) do
		if not near(vector.add(O, s)) then bad[#bad + 1] = s.label end
	end
	local things = {}
	for x = 0, SX - 1 do for y = 0, SY - 1 do for z = 0, SZ - 1 do
		local n = get(x, y, z)
		if n:find("^orthoverse_chateau:") and (n:find("candlestick") or n:find("letter_opener") or n:find("cabinet")
				or n:find("pistols") or n == "orthoverse_chateau:curtain" or n:find("fire_irons") or n:find("piano$")
				or n:find("music_stand") or n:find("menu_card") or n:find("keyhook") or n:find("false_book")
				or n:find("rack_door") or n:find("fortune_table") or n:find("accusation_desk") or n:find("portrait_comte")
				or n:find(":rug")) then
			things[#things + 1] = {p = {x = x, y = y, z = z}, n = n}
		end
	end end end
	for _, th in ipairs(things) do
		if not near(vector.add(O, th.p)) then bad[#bad + 1] = th.n .. " at " .. core.pos_to_string(th.p) end
	end
	t.say(("clue places: %d; unreachable things: %s"):format(#g.spots, #bad > 0 and table.concat(bad, ", ") or "none"))
	-- Everything hung on a wall has a wall behind it (not a doorway or a
	-- window's niche)
	local hung = {}
	local BEHIND = {[0] = {0, 1}, [1] = {1, 0}, [2] = {0, -1}, [3] = {-1, 0}}
	for x = 0, SX - 1 do for y = 0, SY - 1 do for z = 0, SZ - 1 do
		local n = get(x, y, z)
		local def = core.registered_nodes[n]
		if def and def.node_box and def.node_box.fixed and type(def.node_box.fixed[1]) == "number"
				and def.node_box.fixed[3] == 0.4375 and def.paramtype2 == "facedir" then
			local b = BEHIND[(p2grid[idx(x, y, z)] or 0) % 4]
			local w = get(x + b[1], y, z + b[2])
			local wd = core.registered_nodes[w]
			if not (wd and wd.walkable and wd.drawtype == "normal") then hung[#hung + 1] = n:gsub("^.*:", "") .. " at " .. core.pos_to_string({x = x, y = y, z = z}) end
		end
	end end end
	-- Chandeliers hang from something; what stands or lies stands on something
	local floating = {}
	for x = 0, SX - 1 do for y = 1, SY - 2 do for z = 0, SZ - 1 do
		local n = get(x, y, z)
		local def = core.registered_nodes[n]
		if n == CHANDELIER then
			local up = core.registered_nodes[get(x, y + 1, z)]
			if not (up and up.walkable) then floating[#floating + 1] = "chandelier at " .. core.pos_to_string({x = x, y = y, z = z}) end
		elseif def and n:find("^orthoverse_chateau:") and (def.drawtype == "plantlike" or (def.node_box and def.node_box.fixed
				and def.node_box.fixed[5] == -0.4375)) then
			local down = core.registered_nodes[get(x, y - 1, z)]
			if not (down and down.walkable) then floating[#floating + 1] = n:gsub("^.*:", "") .. " at " .. core.pos_to_string({x = x, y = y, z = z}) end
		end
	end end end
	t.say("floating: " .. (#floating > 0 and table.concat(floating, ", ") or "none"))
	t.say("hung with no wall behind: " .. (#hung > 0 and table.concat(hung, ", ") or "none"))
	t.say("the bedrooms reachable by the grand staircase: " .. tostring(near(vector.add(O, {x = 30, y = UP + 1, z = 30})) == true))
	local gated = 0
	for _, s in ipairs(g.spots) do if s.gate then gated = gated + 1 end end
	t.say(("clue places behind a puzzle: %d"):format(gated))
end

function g.build(origin)
	grid, p2grid, metas = {}, {}, {}
	g.spots, g.chests, g.signs, g.gated = {}, {}, {}, {}
	ground()
	forecourt()
	shell()
	windows()
	hall()
	armes()
	salle_a_manger()
	bibliotheque()
	galerie()
	salon()
	musique()
	jardin()
	basement()
	bureau()
	upstairs()
	roofs()
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
	for name in pairs(missing) do core.log("error", "[chateau] no such node: " .. name) end
	for _, m in ipairs(metas) do
		local pos = vector.add(p1, m)
		local node = core.get_node(pos)
		local def = core.registered_nodes[node.name]
		if m.construct and def and def.on_construct then def.on_construct(pos) end
		local mt = core.get_meta(pos)
		for k, v in pairs(m.fields) do mt:set_string(k, v) end
	end
	-- the guests' chairs and the rug set their figures by timer
	for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {"group:orthoverse_timer"})) do
		core.get_node_timer(pos):start(1)
	end
	return missing
end

return g
