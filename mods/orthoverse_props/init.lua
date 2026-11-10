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
-- And for St Morwen's (a haunted church):
-- * A secret wall: looks like stone brick; a loose brick opens it as it
--   opens secret shelves.
-- * The great bell: rung (right-click), it stuns every one of the undead
--   within 32 blocks for 4 seconds (once every 20 seconds), and the first
--   ring of a run opens the adventure's crypt gates.
-- * Crypt gates: iron bars, locked, until the bell is rung.
-- * The font: holy water, three flasks a player a run. Drunk (used), it
--   blesses for a minute: blows land harder on the undead.
-- * Consecrated floor: the undead cannot set foot on it.
-- * Headstones, a wall of bones (decoration).
-- * A fog emitter: an invisible node that breathes low fog around it while
--   players are near.
-- * The reliquary: an adventure finish, as the ledger.
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

local SECRET_WALL = "orthoverse_props:secret_wall"
core.register_node(SECRET_WALL, {
	description = S("Secret wall (stone brick; a loose brick near it slides it away)"),
	tiles = {"default_stone_brick.png"},
	paramtype2 = "facedir",
	groups = {cracky = 2},
	is_ground_content = false,
	sounds = stone,
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
		local shelves = core.find_nodes_in_area(vector.subtract(pos, 6), vector.add(pos, 6), {SHELF, SECRET_WALL})
		if #shelves == 0 then
			core.chat_send_player(clicker:get_player_name(), S("The brick wobbles, but nothing happens."))
			return
		end
		local wall = false
		for _, p in ipairs(shelves) do
			if core.get_node(p).name == SECRET_WALL then wall = true end
			core.remove_node(p)
		end
		core.sound_play("default_dig_cracky", {pos = pos, gain = 0.8, pitch = 0.6, max_hear_distance = 16}, true)
		core.chat_send_player(clicker:get_player_name(), wall and S("Something clicks, and part of the wall grinds aside.")
			or S("Something clicks in the wall, and a shelf swings away."))
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

------------------------------------------------------------------------------
-- St Morwen's: the great bell, crypt gates, the font and holy water,
-- consecrated floor, headstones, bones, fog, the reliquary

local function members(run, name)
	return run and run.members or {[name] = true}
end

local CRYPT_GATE = "orthoverse_props:crypt_gate"
local BELL_STUN, BELL_RADIUS, BELL_EVERY = 4, 32, 20
local rung = {}   -- bell position -> when it may ring again

core.register_node(CRYPT_GATE, {
	description = S("Crypt gate (locked until the adventure's great bell is rung)"),
	drawtype = "nodebox",
	tiles = {"orthoverse_props_crypt_gate.png"},
	use_texture_alpha = "clip",
	node_box = {type = "fixed", fixed = {-0.5, -0.5, -0.06, 0.5, 0.5, 0.06}},
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	groups = {cracky = 1, level = 2},
	is_ground_content = false,
	sounds = rawget(_G, "default") and default.node_sound_metal_defaults() or nil,
	on_rightclick = function(pos, node, clicker)
		if clicker and clicker:is_player() then
			core.chat_send_player(clicker:get_player_name(), S("Iron bars, locked fast. Words are cut in the arch: " ..
				"WHEN THE BELL SPEAKS THE DEAD ARE STILL, AND THE DOOR OF THE DEAD IS OPEN."))
		end
	end,
})

local function ring(pos, node, clicker)
	if not clicker or not clicker:is_player() then return end
	local name = clicker:get_player_name()
	if not may_work(name, pos) then return end
	local k = core.pos_to_string(pos)
	local t = core.get_us_time() / 1e6
	if rung[k] and t < rung[k] then
		core.chat_send_player(name, S("The bell still hums. Wait for it to settle."))
		return
	end
	rung[k] = t + BELL_EVERY
	core.sound_play("orthoverse_props_bell", {pos = pos, gain = 1.0, max_hear_distance = 128}, true)
	local n = orthoverse.monsters and orthoverse.monsters.stun_undead and
		orthoverse.monsters.stun_undead(pos, BELL_RADIUS, BELL_STUN) or 0
	local key, def, run = adventure(pos)
	local msg = n > 0 and S("BONG. The dead stagger and stand still.") or S("BONG. The great bell's voice rolls out over the graves.")
	if def and (not run or not run.props_bell) then
		if run then run.props_bell = true end
		local p1, p2 = area(def)
		local gates = core.find_nodes_in_area(p1, p2, {CRYPT_GATE})
		for _, p in ipairs(gates) do core.remove_node(p) end
		if #gates > 0 then msg = msg .. " " .. S("Far below, iron grinds on stone: the crypt gate is open.") end
	end
	for n2 in pairs(members(run, name)) do core.chat_send_player(n2, msg) end
end

core.register_node("orthoverse_props:bell", {
	description = S("Great bell (ring it: the undead near are stunned; the first ring of a run opens the crypt gates)"),
	drawtype = "nodebox",
	tiles = {"orthoverse_props_bell.png"},
	node_box = {type = "fixed", fixed = {
		{-0.15, 0.35, -0.15, 0.15, 0.5, 0.15},
		{-0.3, 0.05, -0.3, 0.3, 0.35, 0.3},
		{-0.4, -0.3, -0.4, 0.4, 0.05, 0.4},
		{-0.5, -0.5, -0.5, 0.5, -0.3, 0.5},
	}},
	paramtype = "light",
	groups = {cracky = 1, level = 2},
	is_ground_content = false,
	sounds = rawget(_G, "default") and default.node_sound_metal_defaults() or nil,
	on_rightclick = ring,
	on_punch = function(pos, node, puncher) ring(pos, node, puncher) end,
})

-- Holy water
local BLESSING, FLASKS = 60, 3

core.register_craftitem("orthoverse_props:holy_water", {
	description = S("Holy water") .. "\n" .. S("Drink (use): for a minute your blows land harder on the undead"),
	inventory_image = "orthoverse_props_holy_water.png",
	on_use = function(stack, user)
		if not user or not user:is_player() or not (orthoverse.monsters and orthoverse.monsters.bless) then return end
		orthoverse.monsters.bless(user, BLESSING)
		core.sound_play("orthoverse_props_bless", {object = user, gain = 0.8, max_hear_distance = 12}, true)
		core.chat_send_player(user:get_player_name(), S("Cold light runs down your arms. For a minute, the dead will feel your blows."))
		local pos = user:get_pos()
		core.add_particlespawner({amount = 20, time = 0.5, pos = vector.offset(pos, 0, 1, 0), radius = 0.5,
			vel = {min = {x = -0.3, y = 0.5, z = -0.3}, max = {x = 0.3, y = 1.5, z = 0.3}}, exptime = {min = 0.5, max = 1},
			size = {min = 1, max = 2}, texture = "orthoverse_props_holy_water.png^[colorize:#ffffff:120", glow = 14})
		stack:take_item()
		return stack
	end,
})

core.register_node("orthoverse_props:font", {
	description = S("Font (gives a run's players holy water: three flasks each)"),
	drawtype = "nodebox",
	tiles = {"orthoverse_props_font_top.png", "orthoverse_props_font_side.png", "orthoverse_props_font_side.png"},
	node_box = {type = "fixed", fixed = {
		{-0.2, -0.5, -0.2, 0.2, 0.1, 0.2},
		{-0.45, 0.1, -0.45, 0.45, 0.4, 0.45},
	}},
	paramtype = "light",
	groups = {cracky = 2},
	is_ground_content = false,
	sounds = stone,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		if not may_work(name, pos) then return end
		local _, _, run = adventure(pos)
		if run then
			run.props_holy = run.props_holy or {}
			if (run.props_holy[name] or 0) >= FLASKS then
				core.chat_send_player(name, S("You have taken all the font will give you."))
				return
			end
		end
		local left = clicker:get_inventory():add_item("main", "orthoverse_props:holy_water")
		if not left:is_empty() then
			core.chat_send_player(name, S("You have no room to carry it."))
			return
		end
		if run then run.props_holy[name] = (run.props_holy[name] or 0) + 1 end
		core.sound_play("orthoverse_props_bless", {pos = pos, gain = 0.5, max_hear_distance = 10}, true)
		core.chat_send_player(name, S("You fill a flask with holy water."))
	end,
})

core.register_node("orthoverse_props:consecrated", {
	description = S("Consecrated floor (the undead cannot set foot on it)"),
	tiles = {"orthoverse_props_consecrated.png", "default_stone_block.png"},
	groups = {cracky = 2, orthoverse_consecrated = 1},
	is_ground_content = false,
	sounds = stone,
})

core.register_node("orthoverse_props:bones", {
	description = S("Wall of bones"),
	tiles = {"orthoverse_props_bones.png"},
	groups = {cracky = 3},
	is_ground_content = false,
	sounds = stone,
})

core.register_node("orthoverse_props:headstone", {
	description = S("Headstone"),
	drawtype = "nodebox",
	tiles = {"default_stone.png", "default_stone.png", "default_stone.png", "default_stone.png",
		"default_stone.png", "orthoverse_props_headstone.png"},
	node_box = {type = "fixed", fixed = {{-0.4, -0.5, -0.1, 0.4, 0.3, 0.1}, {-0.25, 0.3, -0.1, 0.25, 0.45, 0.1}}},
	paramtype = "light",
	paramtype2 = "facedir",
	groups = {cracky = 2},
	is_ground_content = false,
	sounds = stone,
})

core.register_node("orthoverse_props:fog", {
	description = S("Fog emitter (invisible: low fog drifts about it while players are near)"),
	drawtype = "airlike",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	groups = {not_in_creative_inventory = 0, orthoverse_timer = 1},
	inventory_image = "orthoverse_props_fog.png",
	wield_image = "orthoverse_props_fog.png",
	on_construct = function(pos) core.get_node_timer(pos):start(4) end,
	on_timer = function(pos)
		local near = false
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 32)) do
			if obj:is_player() then near = true break end
		end
		if near then
			core.add_particlespawner({amount = 14, time = 4, pos = {min = vector.offset(pos, -4, -0.4, -4),
				max = vector.offset(pos, 4, 0.6, 4)}, vel = {min = {x = -0.25, y = -0.02, z = -0.25},
				max = {x = 0.25, y = 0.05, z = 0.25}}, exptime = {min = 5, max = 8}, size = {min = 18, max = 30},
				texture = {name = "orthoverse_props_fog.png", alpha_tween = {0, 0.9, 0}}, collisiondetection = false})
		end
		return true
	end,
})

core.register_node("orthoverse_props:reliquary", {
	description = S("Reliquary (an adventure finish: touch it to complete the adventure)"),
	drawtype = "nodebox",
	tiles = {"orthoverse_props_reliquary.png"},
	node_box = {type = "fixed", fixed = {{-0.35, -0.5, -0.25, 0.35, -0.05, 0.25}, {-0.25, -0.05, -0.15, 0.25, 0.1, 0.15}}},
	paramtype = "light",
	paramtype2 = "facedir",
	light_source = 4,
	groups = {cracky = 3, oddly_breakable_by_hand = 2},
	is_ground_content = false,
	sounds = stone,
	on_rightclick = function(pos, node, clicker) finish(pos, clicker) end,
	on_punch = function(pos, node, puncher) finish(pos, puncher) end,
})
