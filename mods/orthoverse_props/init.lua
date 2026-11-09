-- orthoverse_props: fantasy fittings for adventures (all in the Creative tab),
-- first made for The Mill at Withy Ford.
--
-- * Secret shelf: looks like a bookshelf. A loose brick (stone brick with a
--   crack) within 6 blocks, right-clicked, slides every secret shelf within 6
--   blocks of it out of the way (they come back when the adventure is
--   restored after the run).
-- * Windlasses and sluice gates: when every windlass in an adventure is
--   wound, its sluice gates rise (they open).
-- * A mooring post: beside water, it keeps a rowing boat moored for a run's
--   players (a new one when none is near, at most six a run).
-- * The ledger: an adventure finish, as a book on a desk.
--
-- By Keir Finlow-Bates; textures CC BY-SA 3.0.

local S = core.get_translator and core.get_translator("orthoverse_props") or function(s) return s end

orthoverse = orthoverse or {}
orthoverse.props = {}

local wood = rawget(_G, "default") and default.node_sound_wood_defaults() or nil
local stone = rawget(_G, "default") and default.node_sound_stone_defaults() or nil

local function adventure(pos)
	local ad = orthoverse.adventure
	if not (ad and ad.at) then return end
	local key, def = ad.at(pos)
	if not key then return end
	return key, def, ad.runs and ad.runs[key]
end

local function area(def)
	local a, b = def.corner1, def.corner2
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

-- A run's player, or the builder (or the admin) while there is no run
local function may_work(name, pos)
	local key, def, run = adventure(pos)
	if run then return run.members[name] == true end
	local ad = orthoverse.adventure
	if key and ad and ad.may_manage then return ad.may_manage(name, key) end
	return core.check_player_privs(name, {protection_bypass = true})
end

------------------------------------------------------------------------------
-- The secret shelf and its loose brick

local SHELF = "orthoverse_props:secret_shelf"

core.register_node(SHELF, {
	description = S("Secret shelf (a bookshelf; a loose brick near it slides it away)"),
	tiles = {"default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png",
		"default_bookshelf.png", "default_bookshelf.png"},
	paramtype2 = "facedir",
	groups = {choppy = 2},
	is_ground_content = false,
	sounds = wood,
})

core.register_node("orthoverse_props:loose_brick", {
	description = S("Loose brick (stone brick: right-click to slide away the secret shelves near it)"),
	tiles = {"default_stone_brick.png", "default_stone_brick.png", "default_stone_brick.png",
		"default_stone_brick.png", "default_stone_brick.png", "default_stone_brick.png^orthoverse_props_crack.png"},
	paramtype2 = "facedir",
	groups = {cracky = 2},
	is_ground_content = false,
	sounds = stone,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() or not may_work(clicker:get_player_name(), pos) then return end
		local shelves = core.find_nodes_in_area(vector.subtract(pos, 6), vector.add(pos, 6), {SHELF})
		if #shelves == 0 then
			core.chat_send_player(clicker:get_player_name(), S("The brick wobbles, but nothing happens."))
			return
		end
		for _, p in ipairs(shelves) do core.remove_node(p) end
		core.sound_play("default_dig_cracky", {pos = pos, gain = 0.8, pitch = 0.6, max_hear_distance = 16}, true)
		core.chat_send_player(clicker:get_player_name(), S("Something clicks in the wall, and a shelf swings away."))
	end,
})

------------------------------------------------------------------------------
-- Windlasses and sluice gates

local WIND, WOUND, SLUICE = "orthoverse_props:windlass", "orthoverse_props:windlass_wound", "orthoverse_props:sluice_gate"

core.register_node(SLUICE, {
	description = S("Sluice gate (rises when every windlass in the adventure is wound)"),
	tiles = {"default_wood.png", "default_wood.png", "orthoverse_props_sluice.png"},
	paramtype2 = "facedir",
	groups = {choppy = 2},
	is_ground_content = false,
	sounds = wood,
	on_rightclick = function(pos, node, clicker)
		if clicker and clicker:is_player() then
			core.chat_send_player(clicker:get_player_name(), S("A sluice gate, shut fast. Chains run up from it into the dark."))
		end
	end,
})

local function wind(pos, node, clicker)
	if not clicker or not clicker:is_player() then return end
	local name = clicker:get_player_name()
	if not may_work(name, pos) then return end
	local key, def, run = adventure(pos)
	local wound = node.name == WIND
	core.swap_node(pos, {name = wound and WOUND or WIND, param2 = node.param2})
	core.sound_play("default_wood_footstep", {pos = pos, gain = 0.9, pitch = 0.6, max_hear_distance = 16}, true)
	if not (wound and def) then return end
	local p1, p2 = area(def)
	local left = core.find_nodes_in_area(p1, p2, {WIND})
	if #left > 0 then
		core.chat_send_player(name, S("The chain rattles taut. @1 more to wind.", #left))
		return
	end
	for _, p in ipairs(core.find_nodes_in_area(p1, p2, {SLUICE})) do core.remove_node(p) end
	core.sound_play("default_dig_choppy", {pos = pos, gain = 1, pitch = 0.5, max_hear_distance = 48}, true)
	for n in pairs(run and run.members or {[name] = true}) do
		core.chat_send_player(n, S("With a groan of old timbers, a sluice gate rises somewhere below."))
	end
end

core.register_node(WIND, {
	description = S("Windlass (wind every one in the adventure to raise its sluice gates)"),
	tiles = {"default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png",
		"orthoverse_props_windlass.png"},
	paramtype2 = "facedir",
	groups = {choppy = 2},
	is_ground_content = false,
	sounds = wood,
	on_rightclick = wind,
})
core.register_node(WOUND, {
	description = S("Windlass (wound)"),
	tiles = {"default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png",
		"orthoverse_props_windlass_wound.png"},
	paramtype2 = "facedir",
	groups = {choppy = 2, not_in_creative_inventory = 1},
	drop = WIND,
	is_ground_content = false,
	sounds = wood,
	on_rightclick = wind,
})

------------------------------------------------------------------------------
-- The mooring post

local BOATS_PER_RUN = 6

local function water_beside(pos)
	for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		for dy = 0, -1, -1 do
			local p = vector.offset(pos, d[1], dy, d[2])
			if core.get_item_group(core.get_node(p).name, "water") > 0 then return p end
		end
	end
end

core.register_node("orthoverse_props:mooring", {
	description = S("Mooring post (beside water: keeps a rowing boat there for the players of a run)"),
	drawtype = "nodebox",
	tiles = {"default_tree_top.png", "default_tree_top.png", "default_tree.png"},
	node_box = {type = "fixed", fixed = {-0.2, -0.5, -0.2, 0.2, 0.4, 0.2}},
	paramtype = "light",
	groups = {choppy = 2, orthoverse_timer = 1},
	is_ground_content = false,
	sounds = wood,
	on_construct = function(pos) core.get_node_timer(pos):start(2) end,
	on_timer = function(pos)
		if not core.registered_entities["boats:boat"] then return false end
		local _, _, run = adventure(pos)
		if not run then return true end
		run.props_boats = run.props_boats or 0
		if run.props_boats >= BOATS_PER_RUN then return true end
		local water = water_beside(pos)
		if not water then return true end
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 5)) do
			local e = obj:get_luaentity()
			if e and e.name == "boats:boat" then return true end
		end
		local boat = core.add_entity(vector.offset(water, 0, 0.5, 0), "boats:boat")
		if boat then run.props_boats = run.props_boats + 1 end
		return true
	end,
})

------------------------------------------------------------------------------
-- The ledger: a finish

local function finish(pos, player)
	local ad = orthoverse.adventure
	if ad and ad.at_finish then ad.at_finish(pos, player) end
end

core.register_node("orthoverse_props:ledger", {
	description = S("Ledger (an adventure finish: touch it to complete the adventure)"),
	drawtype = "nodebox",
	tiles = {"orthoverse_props_ledger.png", "orthoverse_props_ledger.png", "orthoverse_props_ledger.png"},
	node_box = {type = "fixed", fixed = {-0.35, -0.5, -0.25, 0.35, -0.3, 0.25}},
	paramtype = "light",
	paramtype2 = "facedir",
	groups = {choppy = 3, oddly_breakable_by_hand = 2},
	is_ground_content = false,
	sounds = wood,
	on_rightclick = function(pos, node, clicker) finish(pos, clicker) end,
	on_punch = function(pos, node, puncher) finish(pos, puncher) end,
})
