-- Eight Queens: the floor of the Queen's hall is a board of eight by eight
-- squares (each three blocks across), cut into eight coloured regions, drawn
-- anew for every run (puzzle.lua). The player is given eight queens and a
-- stack of crosses: a queen in each row, each column and each colour, none
-- touching another, and the doors to the throne room open. The crown before
-- the Queen finishes the adventure.
--
-- Textures and sounds: tools/queens/make_textures.py (CC BY-SA 3.0).

local S = core.get_translator("orthoverse_queens")
local modpath = core.get_modpath("orthoverse_queens")

orthoverse = orthoverse or {}
orthoverse.queens = {}
local Q = orthoverse.queens
local P = dofile(modpath .. "/puzzle.lua")
Q.puzzle = P

local N = 8          -- squares a side
local CELL = 3       -- blocks a square
local TEMPLATE = "queens"

local function tex(name) return "orthoverse_queens_" .. name .. ".png" end

local SND = {
	stone = default and default.node_sound_stone_defaults() or nil,
	wood = default and default.node_sound_wood_defaults() or nil,
	cloth = default and default.node_sound_leaves_defaults() or nil,
}

-- The colours, in the order of the regions (1 to 8)
local COLOURS = {"violet", "orange", "blue", "green", "grey", "red", "yellow", "teal"}
Q.COLOURS = COLOURS

------------------------------------------------------------------------------
-- The floor

local tile_name = {}
for i, c in ipairs(COLOURS) do
	tile_name[i] = {}
	for _, sh in ipairs({"light", "dark"}) do
		local id = "tile_" .. c .. "_" .. sh
		tile_name[i][sh] = "orthoverse_queens:" .. id
		core.register_node("orthoverse_queens:" .. id, {
			description = S("Queen's floor tile (@1, @2)", c, sh),
			tiles = {tex(id)}, is_ground_content = false,
			-- (the floor glows a little, so the colours show by night too)
			paramtype = "light", light_source = 11,
			groups = {cracky = 2, queens_tile = 1}, sounds = SND.stone,
		})
	end
end
core.register_node("orthoverse_queens:tile_blank", {
	description = S("Queen's floor tile (before a run colours it)"),
	tiles = {tex("tile_blank")}, is_ground_content = false, paramtype = "light", light_source = 11,
	groups = {cracky = 2, queens_tile = 1}, sounds = SND.stone,
})

------------------------------------------------------------------------------
-- The run

local function adventure(pos)
	local ad = orthoverse.adventure
	if not (ad and ad.at) then return end
	local key, def = ad.at(pos)
	if not key then return end
	return key, def, ad.runs and ad.runs[key]
end

-- The run (and its board) a player is in, at the hall where `pos` is
local function game_of(player, pos)
	if not (player and player:is_player()) then return end
	local key, def, run = adventure(pos)
	if not (run and run.members[player:get_player_name()] and run.queens) then return end
	return run.queens, key, def, run
end
Q.game_of = game_of

local function area(def)
	local a, b = def.corner1, def.corner2
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

-- The board's south-west corner block and its height: the lowest x and z of
-- the floor's tiles (the floor is square, so turning the adventure round
-- changes nothing)
local function find_board(def)
	local p1, p2 = area(def)
	local tiles = core.find_nodes_in_area(p1, p2, {"group:queens_tile"})
	if #tiles ~= (N * CELL) ^ 2 then return nil end
	local o = vector.new(tiles[1])
	for _, t in ipairs(tiles) do
		o.x, o.z = math.min(o.x, t.x), math.min(o.z, t.z)
	end
	return o
end

-- Which square a block of the floor is in (row counted from the south,
-- column from the west, 1..N), or nil
local function square_of(g, pos)
	local cx = math.floor((pos.x - g.origin.x) / CELL) + 1
	local cz = math.floor((pos.z - g.origin.z) / CELL) + 1
	if pos.y ~= g.origin.y or cx < 1 or cx > N or cz < 1 or cz > N then return end
	return cz, cx
end

-- The block above the middle of a square: where its queen or cross stands
local function stand_of(g, r, c)
	return vector.new(g.origin.x + (c - 1) * CELL + 1, g.origin.y + 1, g.origin.z + (r - 1) * CELL + 1)
end

-- Colour the floor for a new puzzle (light and dark squares in turn, like a
-- chessboard)
local function paint(g)
	local p1 = g.origin
	local p2 = vector.add(p1, vector.new(N * CELL - 1, 0, N * CELL - 1))
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(p1, p2)
	local va = VoxelArea(e1, e2)
	local data = vm:get_data()
	for r = 1, N do
		for c = 1, N do
			local id = core.get_content_id(tile_name[g.region[r][c]][(r + c) % 2 == 0 and "dark" or "light"])
			for dz = 0, CELL - 1 do
				for dx = 0, CELL - 1 do
					data[va:index(p1.x + (c - 1) * CELL + dx, p1.y, p1.z + (r - 1) * CELL + dz)] = id
				end
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

-- A new board for a run
local function new_game(def)
	local origin = find_board(def)
	if not origin then
		core.log("error", "[orthoverse_queens] " .. def.name .. ": no board of " .. N * CELL .. " by " .. N * CELL .. " tiles found")
		return
	end
	local p = P.make(N, math.random, 400) or P.make(N, math.random, 2000)
	if not p then
		core.log("error", "[orthoverse_queens] no puzzle could be made")
		return
	end
	local g = {origin = origin, region = p.region, answer = p.queen, solved = false}
	paint(g)
	return g
end
Q.new_game = new_game

-- The queens on the board, as {[row] = {col, ...}}, and how many
local function queens_on(g)
	local rows, count = {}, 0
	for r = 1, N do
		for c = 1, N do
			if core.get_node(stand_of(g, r, c)).name == "orthoverse_queens:queen" then
				rows[r] = rows[r] or {}
				table.insert(rows[r], c)
				count = count + 1
			end
		end
	end
	return rows, count
end

-- Is the board done? One queen in each row, column and region, and none
-- touching another
local function check(g)
	local rows, count = queens_on(g)
	if count ~= N then return false, count end
	local cols, regs, col = {}, {}, {}
	for r = 1, N do
		if not rows[r] or #rows[r] ~= 1 then return false, count end
		local c = rows[r][1]
		if cols[c] or regs[g.region[r][c]] then return false, count end
		if r > 1 and math.abs(col[r - 1] - c) <= 1 then return false, count end
		cols[c], regs[g.region[r][c]], col[r] = true, true, c
	end
	return true, count
end
Q.check = check

local function tell_run(run, text)
	for n in pairs(run.members) do core.chat_send_player(n, text) end
end

-- The doors of the throne room open (they are gone; the restore after the
-- run puts them back)
local function open_doors(def)
	local p1, p2 = area(def)
	local doors = core.find_nodes_in_area(p1, p2, {"orthoverse_queens:door"})
	for _, pos in ipairs(doors) do core.remove_node(pos) end
	if doors[1] then
		core.sound_play("orthoverse_queens_doors", {pos = doors[1], gain = 1, max_hear_distance = 48}, true)
	end
end

-- After a queen is set down or taken up
local function changed(g, key, def, run)
	if g.solved then return end
	local ok, count = check(g)
	if ok then
		g.solved = true
		open_doors(def)
		tell_run(run, S("Eight queens, and not one of them in another's way. The doors of the throne room swing open."))
	elseif count == N then
		tell_run(run, S("Eight queens are on the floor, but the doors stay shut: the board is not right yet."))
	end
end

------------------------------------------------------------------------------
-- The queens and the crosses: given on entering, set on a square of the
-- floor (in its middle, whichever block of it is clicked), taken up again by
-- hitting them

local PIECE_BOX = {type = "fixed", fixed = {
	{-0.4, -0.5, -0.4, 0.4, -0.3, 0.4},      -- the base
	{-0.28, -0.3, -0.28, 0.28, 0.15, 0.28},  -- the skirt
	{-0.15, 0.15, -0.15, 0.15, 0.55, 0.15},  -- the waist
	{-0.24, 0.55, -0.24, 0.24, 0.68, 0.24},  -- the collar
	{-0.15, 0.68, -0.15, 0.15, 0.85, 0.15},  -- the head
	{-0.2, 0.85, -0.2, 0.2, 1.0, 0.2},       -- the crown
}}
local CROSS_BOX = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5}}

-- Set a piece (queen or cross) on the square a player pointed at
local function set_piece(itemstack, placer, pointed, piece)
	if not (placer and placer:is_player() and pointed and pointed.type == "node") then return itemstack end
	local name = placer:get_player_name()
	local under = pointed.under
	local un = core.get_node(under).name
	-- (pointing at a piece already there: its square)
	if un == "orthoverse_queens:queen" or un == "orthoverse_queens:cross" then under = vector.offset(under, 0, -1, 0) end
	local g, key, def, run = game_of(placer, under)
	if not g then
		core.chat_send_player(name, S("Queens and crosses go on the Queen's floor, in a run."))
		return itemstack
	end
	local r, c = square_of(g, under)
	if not r then
		core.chat_send_player(name, S("Set it on a square of the coloured floor."))
		return itemstack
	end
	local at = stand_of(g, r, c)
	local here = core.get_node(at).name
	if here == piece then return itemstack end
	if here == "orthoverse_queens:queen" or here == "orthoverse_queens:cross" then
		-- (one piece to a square: the one there goes back to the player)
		local back = placer:get_inventory():add_item("main", here)
		if not back:is_empty() then return itemstack end
	elseif here ~= "air" then
		return itemstack
	end
	core.set_node(at, {name = piece})
	core.sound_play("orthoverse_queens_place", {pos = at, gain = 0.6, max_hear_distance = 16}, true)
	itemstack:take_item()
	if piece == "orthoverse_queens:queen" or here == "orthoverse_queens:queen" then changed(g, key, def, run) end
	return itemstack
end

-- Take a piece up again
local function take_piece(pos, node, puncher)
	if not (puncher and puncher:is_player()) then return end
	local g, key, def, run = game_of(puncher, pos)
	if not g then return end
	local below = vector.offset(pos, 0, -1, 0)
	if not square_of(g, below) then return end
	local inv = puncher:get_inventory()
	if not inv:room_for_item("main", node.name) then return end
	inv:add_item("main", node.name)
	core.remove_node(pos)
	if node.name == "orthoverse_queens:queen" then changed(g, key, def, run) end
end

core.register_node("orthoverse_queens:queen", {
	description = S("Queen") .. "\n" .. S("Set her on a square of the Queen's floor; hit her to take her up."),
	drawtype = "nodebox", node_box = PIECE_BOX, paramtype = "light", sunlight_propagates = true,
	tiles = {tex("queen_top"), tex("queen_top"), tex("queen")},
	inventory_image = tex("queen_icon"), wield_image = tex("queen_icon"),
	is_ground_content = false, walkable = false, floodable = false,
	groups = {not_in_creative_inventory = 1}, stack_max = N,
	on_place = function(itemstack, placer, pointed)
		return set_piece(itemstack, placer, pointed, "orthoverse_queens:queen")
	end,
	on_punch = take_piece,
	can_dig = function() return false end,
})

core.register_node("orthoverse_queens:cross", {
	description = S("Cross") .. "\n" .. S("Mark a square that cannot hold a queen; hit it to take it up."),
	drawtype = "nodebox", node_box = CROSS_BOX, paramtype = "light", sunlight_propagates = true,
	use_texture_alpha = "clip", tiles = {tex("cross"), "blank.png"},
	inventory_image = tex("cross"), wield_image = tex("cross"),
	is_ground_content = false, walkable = false, floodable = false,
	groups = {not_in_creative_inventory = 1},
	on_place = function(itemstack, placer, pointed)
		return set_piece(itemstack, placer, pointed, "orthoverse_queens:cross")
	end,
	on_punch = take_piece,
	can_dig = function() return false end,
})

------------------------------------------------------------------------------
-- The hall and the throne room

core.register_node("orthoverse_queens:door", {
	description = S("Doors of the throne room (they open when the floor is solved)"),
	tiles = {tex("door")}, is_ground_content = false,
	groups = {cracky = 1}, sounds = SND.wood,
})

-- The gallery's rail: a gilded rail on slender posts, so that it hides as
-- little of the floor as it can (and too high to climb over)
local function rail_box(top, bar)
	local function arm(x1, z1, x2, z2)
		return {{x1, top - bar, z1, x2, top, z2}, {x1, -0.05, z1, x2, 0.05, z2}}
	end
	return {
		type = "connected",
		fixed = {{-1 / 16, -0.5, -1 / 16, 1 / 16, top, 1 / 16}},
		connect_front = arm(-1 / 32, -0.5, 1 / 32, 0),
		connect_back = arm(-1 / 32, 0, 1 / 32, 0.5),
		connect_left = arm(-0.5, -1 / 32, 0, 1 / 32),
		connect_right = arm(0, -1 / 32, 0.5, 1 / 32),
	}
end
local function rail_collision()
	return {
		type = "connected",
		fixed = {{-1 / 8, -0.5, -1 / 8, 1 / 8, 1, 1 / 8}},
		connect_front = {{-1 / 8, -0.5, -0.5, 1 / 8, 1, 0}},
		connect_back = {{-1 / 8, -0.5, 0, 1 / 8, 1, 0.5}},
		connect_left = {{-0.5, -0.5, -1 / 8, 0, 1, 1 / 8}},
		connect_right = {{0, -0.5, -1 / 8, 0.5, 1, 1 / 8}},
	}
end
core.register_node("orthoverse_queens:rail", {
	description = S("Gilded rail"),
	drawtype = "nodebox", paramtype = "light", sunlight_propagates = true,
	node_box = rail_box(0.5, 0.08), collision_box = rail_collision(),
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.1, 0.5, 0.5, 0.1}},
	connects_to = {"orthoverse_queens:rail"},
	tiles = {tex("gold")}, is_ground_content = false,
	groups = {cracky = 2}, sounds = SND.stone,
})

core.register_node("orthoverse_queens:banner", {
	description = S("The Queen's banner"),
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", sunlight_propagates = true,
	node_box = {type = "fixed", fixed = {-0.4, -0.5, 0.4375, 0.4, 0.5, 0.5}},
	tiles = {tex("banner")}, is_ground_content = false,
	groups = {choppy = 2}, sounds = SND.cloth,
})

local RULES = [[The Queen asks for a queen in every row, in every column and in every colour of her floor: eight queens in all. No queen may touch another, not even corner to corner.

Set a queen on a square with a right click (on any block of the square: she stands in its middle). Hit her to take her up again.

The crosses are for you: mark the squares you know cannot hold a queen.

The gallery above the floor is the place to see it whole.

When all eight stand where they should, the doors to the throne room open. The floor is laid differently every time you come, and there is always exactly one answer.]]

core.register_node("orthoverse_queens:notice", {
	description = S("How to play (right-click)"),
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", sunlight_propagates = true,
	node_box = {type = "fixed", fixed = {-0.5, -0.5, 0.4375, 0.5, 0.5, 0.5}},
	tiles = {tex("notice")}, is_ground_content = false,
	groups = {choppy = 2}, sounds = SND.wood,
	on_rightclick = function(_, _, clicker)
		if not (clicker and clicker:is_player()) then return end
		local fs = "formspec_version[4]size[10,7.5]" ..
			"box[0,0;10,1;#3a2050]label[0.4,0.5;" .. core.formspec_escape(S("Eight Queens: how to play")) .. "]" ..
			"textarea[0.4,1.3;9.2,5.2;;;" .. core.formspec_escape(RULES) .. "]" ..
			"button_exit[3.5,6.6;3,0.7;ok;" .. S("Close") .. "]"
		core.show_formspec(clicker:get_player_name(), "orthoverse_queens:rules", fs)
	end,
})

-- The throne, where the Queen sits (her figure is set by the throne's timer:
-- the restore after a run removes every creature in the area)
local SIT = {x = 81, y = 160}
core.register_entity("orthoverse_queens:queen_figure", {
	initial_properties = {
		visual = "mesh", mesh = "character.b3d", textures = {tex("skin_queen")},
		visual_size = {x = 1, y = 1}, collisionbox = {-0.3, 0, -0.3, 0.3, 1.2, 0.3},
		selectionbox = {-0.3, 0, -0.3, 0.3, 1.2, 0.3},
		physical = false, pointable = true, static_save = false, makes_footstep_sound = false,
		infotext = S("The Queen"),
	},
	on_activate = function(self)
		self.object:set_animation(SIT, 0, 0, false)
	end,
	on_punch = function() return true end,
})

-- Facedir 0..3 to the yaw a sitter faces (facedir 0: the throne's back to
-- the north, so she faces south)
local YAW = {[0] = math.pi, [1] = math.pi / 2, [2] = 0, [3] = -math.pi / 2}

core.register_node("orthoverse_queens:throne", {
	description = S("The Queen's throne"),
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", sunlight_propagates = true,
	node_box = {type = "fixed", fixed = {
		{-0.45, -0.5, -0.45, 0.45, 0.0, 0.45},     -- the seat
		{-0.45, 0.0, 0.3, 0.45, 1.3, 0.45},        -- the back, tall
		{-0.45, 0.0, -0.45, -0.32, 0.35, 0.3},     -- the arms
		{0.32, 0.0, -0.45, 0.45, 0.35, 0.3},
		{-0.2, 1.3, 0.32, 0.2, 1.45, 0.45},        -- the crest
	}},
	selection_box = {type = "fixed", fixed = {-0.45, -0.5, -0.45, 0.45, 1.45, 0.45}},
	collision_box = {type = "fixed", fixed = {-0.45, -0.5, -0.45, 0.45, 1.3, 0.45}},
	tiles = {tex("velvet"), tex("gold"), tex("gold"), tex("gold"), tex("gold"), tex("velvet")},
	is_ground_content = false,
	groups = {choppy = 2, orthoverse_timer = 1}, sounds = SND.wood,
	on_construct = function(pos) core.get_node_timer(pos):start(1) end,
	on_timer = function(pos)
		local at = vector.offset(pos, 0, 0.05, 0)
		for _, obj in ipairs(core.get_objects_inside_radius(at, 0.6)) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "orthoverse_queens:queen_figure" then return true end
		end
		local obj = core.add_entity(at, "orthoverse_queens:queen_figure")
		if obj then obj:set_yaw(YAW[core.get_node(pos).param2 % 4] or 0) end
		return true
	end,
	on_destruct = function(pos)
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.7)) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "orthoverse_queens:queen_figure" then obj:remove() end
		end
	end,
})

-- The crown on its cushion, before the Queen: the finish. Touched once the
-- floor is solved, it completes the adventure
local function crown_touched(pos, player)
	if not (player and player:is_player()) then return end
	local ad = orthoverse.adventure
	if not (ad and ad.at_finish) then return end
	local g = game_of(player, pos)
	if g and not g.solved then return end
	if g then
		core.sound_play("orthoverse_queens_fanfare", {pos = pos, gain = 0.9, max_hear_distance = 32}, true)
	end
	ad.at_finish(pos, player)
end

core.register_node("orthoverse_queens:crown", {
	description = S("The crown (an adventure finish: touch it to complete the adventure)"),
	drawtype = "nodebox", paramtype = "light", sunlight_propagates = true,
	node_box = {type = "fixed", fixed = {
		{-0.35, -0.5, -0.35, 0.35, -0.25, 0.35},   -- the cushion
		{-0.22, -0.25, -0.22, 0.22, 0.0, 0.22},    -- the crown's band
		{-0.22, 0.0, -0.22, -0.12, 0.12, -0.12},   -- its points
		{0.12, 0.0, -0.22, 0.22, 0.12, -0.12},
		{-0.22, 0.0, 0.12, -0.12, 0.12, 0.22},
		{0.12, 0.0, 0.12, 0.22, 0.12, 0.22},
	}},
	tiles = {tex("crown"), tex("cushion"), tex("crown")},
	light_source = 5, is_ground_content = false,
	groups = {cracky = 2}, sounds = SND.stone,
	on_rightclick = function(pos, node, clicker) crown_touched(pos, clicker) end,
	on_punch = function(pos, node, puncher) crown_touched(pos, puncher) end,
})

core.register_node("orthoverse_queens:plinth", {
	description = S("A white plinth"),
	drawtype = "nodebox", paramtype = "light",
	node_box = {type = "fixed", fixed = {{-0.35, -0.5, -0.35, 0.35, 0.5, 0.35}, {-0.45, 0.3, -0.45, 0.45, 0.5, 0.45},
		{-0.45, -0.5, -0.45, 0.45, -0.3, 0.45}}},
	tiles = {tex("plinth")}, is_ground_content = false,
	groups = {cracky = 2}, sounds = SND.stone,
})

------------------------------------------------------------------------------
-- The run begins: a new floor

core.register_on_mods_loaded(function()
	local ad = orthoverse.adventure
	if not (ad and ad.on_enter) then return end
	table.insert(ad.on_enter, function(player, key, def, run)
		if run.queens or def.template ~= TEMPLATE then return end
		run.queens = new_game(def)
	end)
end)
