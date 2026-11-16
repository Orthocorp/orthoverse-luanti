-- orthoverse_ark: the blocks and ways of The Silent Ark, a dead generation
-- ship in orbit, for that adventure and for any builder's (all in the
-- Creative tab).
--
-- * Space: black blocks, star blocks (three kinds), the red giant's blocks
--   (they glow) and the planet's (sea, land and cloud). A player who touches
--   any of them has fallen off the ship: they are hurt a little and drawn back
--   to the nearest tether mark.
-- * The ship: white hull panels (plain and ribbed), window frames, deck, a
--   frosted panel, dead plants for the hydroponics dome.
-- * Vacuum and low gravity: invisible blocks that fill a space. In vacuum a
--   player breathes from their suit's tank (60 s, shown on the screen), and
--   is hurt each second once it is empty. Air stations fill the tank again.
--   In low gravity a player weighs a third as much and jumps high; leaving it
--   puts their weight back. One block does both, for a walk outside.
-- * Bulkheads: the ship's mind shuts a bulkhead (its open marks become a
--   door) once every living player of the run has crossed its seal plates.
-- * Cryo pods: two blocks high, a sleeper inside. As a player of the run
--   passes, a pod may open and its sleeper come out (which pods, chosen
--   afresh each run; more of them for a bigger party).
-- * Terminals: right-click to read the ship's log (the builder sets it).
-- * The mind's core: once its keeper, the Custodian, is destroyed in the run,
--   a player pulls the core; the ship falls silent, and its pod doors and
--   bridge doors open.
-- * The launch handle: the finish, inside an escape pod.
--
-- Everything is put back as saved when the adventure is restored after a run.
-- By Keir Finlow-Bates; textures and sounds CC BY-SA 3.0, the code MIT.

local S = core.get_translator and core.get_translator("orthoverse_ark") or function(s) return s end

orthoverse = orthoverse or {}
local A = {}
orthoverse.ark = A

local function tex(name) return "orthoverse_ark_" .. name .. ".png" end
local function now() return core.get_us_time() / 1e6 end
local metal = default and default.node_sound_metal_defaults and default.node_sound_metal_defaults() or nil
local stone = default and default.node_sound_stone_defaults() or nil
local glass = default and default.node_sound_glass_defaults() or nil
local plant = default and default.node_sound_leaves_defaults() or nil

local AIR_SECS = 60           -- a full suit tank
local AIR_HURT = 4            -- health a second, with the tank empty
local LOWG = {gravity = 0.3}  -- weight in low gravity (jumps about seven blocks)
local FALL_HURT = 8           -- for falling off the ship
local POD_CHANCE = {0.3, 0.38, 0.46, 0.54}   -- a pod opens, by players in the run

------------------------------------------------------------------------------
-- The run

local function adventure(pos)
	local ad = orthoverse.adventure
	if not (ad and ad.at) then return end
	local key, def = ad.at(pos)
	if not key then return end
	return key, def, ad.runs and ad.runs[key]
end

local function data(run)
	run.ark = run.ark or {sealed = {}, crossed = {}, mind = false, custodian = false}
	return run.ark
end

local function in_run(player, pos)
	if not (player and player:is_player()) then return end
	local key, def, run = adventure(pos or player:get_pos())
	if run and run.members[player:get_player_name()] then return key, def, run end
end

local function tell(run, text)
	for n in pairs(run.members) do core.chat_send_player(n, text) end
end

local function area(def)
	local a, b = def.corner1, def.corner2
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

local function living(run)
	local out = {}
	for n in pairs(run.members) do
		local pl = core.get_player_by_name(n)
		if pl and pl:get_hp() > 0 then out[#out + 1] = pl end
	end
	return out
end

local function sound(name, pos, gain, dist)
	core.sound_play("orthoverse_ark_" .. name, {pos = pos, gain = gain or 1, max_hear_distance = dist or 24}, true)
end

------------------------------------------------------------------------------
-- Plain blocks

local function block(id, desc, def)
	def.description = desc
	def.groups = def.groups or {cracky = 2}
	def.sounds = def.sounds or metal
	def.is_ground_content = false
	core.register_node("orthoverse_ark:" .. id, def)
end

-- Space: whoever touches it has fallen off the ship (group ark_void)
local function void(id, desc, tile, light)
	block(id, desc, {tiles = {tex(tile)}, light_source = light, paramtype = light and "light" or nil,
		groups = {cracky = 1, ark_void = 1}, sounds = stone})
end
void("space", S("Space (black; whoever touches it has fallen off the ship)"), "space")
void("star_1", S("Space with a star"), "star_1", 8)
void("star_2", S("Space with stars"), "star_2", 6)
void("star_3", S("Space with a bright star"), "star_3", 12)
void("giant_core", S("Red giant (its heart)"), "giant_core", 14)
void("giant", S("Red giant"), "giant", 13)
void("giant_edge", S("Red giant (its rim)"), "giant_edge", 11)
void("planet_sea", S("Planet: sea"), "planet_sea", 4)
void("planet_land", S("Planet: land"), "planet_land", 4)
void("planet_cloud", S("Planet: cloud"), "planet_cloud", 5)

block("hull", S("Ark hull panel"), {tiles = {tex("hull")}})
block("hull_rib", S("Ark hull, ribbed"), {tiles = {tex("hull_rib")}})
block("hull_dark", S("Ark hull, dark"), {tiles = {tex("hull_dark")}})
block("frame", S("Window frame"), {tiles = {tex("frame")}})
block("deck", S("Ark deck"), {tiles = {tex("deck")}})
block("strip", S("Ark light strip"), {tiles = {tex("strip")}, light_source = 14, paramtype = "light"})
block("frost", S("Frosted panel"), {tiles = {tex("frost")}, sounds = glass})
block("hazard", S("Hazard stripes"), {tiles = {tex("hazard")}})
block("window", S("Ark window"), {tiles = {tex("window")}, drawtype = "glasslike", paramtype = "light",
	sunlight_propagates = true, use_texture_alpha = "blend", sounds = glass})
block("rail", S("Ark railing"), {tiles = {tex("frame")}, drawtype = "nodebox", paramtype = "light",
	node_box = {type = "connected", fixed = {-0.08, -0.5, -0.08, 0.08, 0.5, 0.08},
		connect_front = {-0.04, 0.3, -0.5, 0.04, 0.42, 0}, connect_back = {-0.04, 0.3, 0, 0.04, 0.42, 0.5},
		connect_left = {-0.5, 0.3, -0.04, 0, 0.42, 0.04}, connect_right = {0, 0.3, -0.04, 0.5, 0.42, 0.04}},
	connects_to = {"orthoverse_ark:rail"},
	-- (as high as a wall to walk into, not to look through)
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.0, 0.5}}})
block("dead_plant", S("Dead plant"), {drawtype = "plantlike", tiles = {tex("dead_plant")}, paramtype = "light",
	sunlight_propagates = true, walkable = false, groups = {snappy = 3}, sounds = plant,
	selection_box = {type = "fixed", fixed = {-0.35, -0.5, -0.35, 0.35, 0.3, 0.35}}})
block("overgrowth", S("Overgrowth (pale tendrils, thick)"), {tiles = {tex("overgrowth")}, groups = {snappy = 2},
	sounds = plant})

------------------------------------------------------------------------------
-- Vacuum and low gravity: invisible, nothing to them

local MARKS = {
	vacuum = {S("Vacuum (in it, a player breathes from their suit's tank)"), true, false},
	lowg = {S("Low gravity (in it, a player weighs a third as much)"), false, true},
	vacuum_lowg = {S("Vacuum and low gravity (outside the ship)"), true, true},
}
for id, m in pairs(MARKS) do
	core.register_node("orthoverse_ark:" .. id, {
		description = m[1], drawtype = "airlike", paramtype = "light", sunlight_propagates = true,
		walkable = false, pointable = false, diggable = false, buildable_to = true, floodable = false,
		is_ground_content = false, inventory_image = tex("mark_" .. id), wield_image = tex("mark_" .. id),
		groups = {not_in_creative_inventory = 0, ark_vacuum = m[2] and 1 or nil, ark_lowg = m[3] and 1 or nil},
		_ark_vacuum = m[2], _ark_lowg = m[3],
	})
end

-- Tether marks: where a player who falls off the ship is drawn back to
core.register_node("orthoverse_ark:tether", {
	description = S("Tether mark (a player who falls off the ship comes back to the nearest)"),
	drawtype = "airlike", paramtype = "light", sunlight_propagates = true, walkable = false, pointable = false,
	buildable_to = false, is_ground_content = false, inventory_image = tex("mark_tether"),
})

------------------------------------------------------------------------------
-- The suit's air, and weight

local suits = {}   -- name -> {air, hud, bg, weight}

local function suit(name)
	suits[name] = suits[name] or {air = AIR_SECS}
	return suits[name]
end

local function show_air(player, s)
	local n = math.ceil(s.air / AIR_SECS * 20)
	if s.air >= AIR_SECS then
		if s.hud then player:hud_remove(s.hud); s.hud = nil end
		if s.label then player:hud_remove(s.label); s.label = nil end
		return
	end
	if not s.hud then
		s.hud = player:hud_add({type = "statbar", position = {x = 0.5, y = 1}, text = tex("air"), text2 = tex("air_empty"),
			number = n, item = 20, direction = 0, size = {x = 24, y = 24}, offset = {x = 25, y = -(48 + 24 + 16 + 30)},
			z_index = 1})
		s.label = player:hud_add({type = "text", position = {x = 0.5, y = 1}, offset = {x = 25 + 245, y = -(48 + 24 + 16 + 18)},
			text = S("SUIT AIR"), number = 0x9fd8ff, alignment = {x = 1, y = 0}, z_index = 1})
	else
		player:hud_change(s.hud, "number", n)
	end
end

-- How much air a player's suit holds, in seconds
function A.air_of(name) return suits[name] and suits[name].air or AIR_SECS end

function A.refill(player)
	local s = suit(player:get_player_name())
	s.air = AIR_SECS
	show_air(player, s)
end

local function weigh(player, low)
	local s = suit(player:get_player_name())
	if low and not s.weight then
		s.weight = true
		player:set_physics_override({gravity = LOWG.gravity})
	elseif not low and s.weight then
		s.weight = nil
		player:set_physics_override({gravity = 1})
	end
end

-- The nearest tether mark, within the adventure
local function tether_for(player, def)
	local pos = player:get_pos()
	local best, bd
	local p1, p2 = area(def)
	for _, m in ipairs(core.find_nodes_in_area(p1, p2, {"orthoverse_ark:tether"})) do
		local d = vector.distance(m, pos)
		if not bd or d < bd then best, bd = m, d end
	end
	return best
end

local tick = 0
core.register_globalstep(function(dtime)
	tick = tick + dtime
	if tick < 0.25 then return end
	local step = tick
	tick = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		local key, def, run = adventure(pos)
		local member = run and run.members[name] and player:get_hp() > 0
		local body = core.registered_nodes[core.get_node(vector.round(vector.offset(pos, 0, 1, 0))).name] or {}
		local feet = core.registered_nodes[core.get_node(vector.round(vector.offset(pos, 0, 0.4, 0))).name] or {}
		-- weight: low wherever the body or the feet are in low gravity
		weigh(player, member and (body._ark_lowg or feet._ark_lowg) or false)
		local s = suits[name]
		if member then
			s = suit(name)
			if body._ark_vacuum then
				s.air = math.max(0, s.air - step)
				if s.air <= 0 then
					s.hurt = (s.hurt or 0) + step
					if s.hurt >= 1 then
						s.hurt = 0
						player:set_hp(player:get_hp() - AIR_HURT, {type = "set_hp", from = "mod", orthoverse_ark = "vacuum"})
						if not s.told then
							s.told = true
							core.chat_send_player(name, S("Your suit's tank is empty. Find air."))
						end
					end
				else
					s.told = nil
				end
			end
			show_air(player, s)
			-- fallen off the ship?
			local under = core.get_node(vector.round(vector.offset(pos, 0, -0.3, 0))).name
			if core.get_item_group(under, "ark_void") > 0 or core.get_item_group(core.get_node(vector.round(pos)).name, "ark_void") > 0 then
				local back = tether_for(player, def)
				if back then
					player:set_pos(back)
					player:add_velocity(vector.multiply(player:get_velocity(), -1))
					player:set_hp(player:get_hp() - FALL_HURT, {type = "set_hp", from = "mod", orthoverse_ark = "fall"})
					core.chat_send_player(name, S("The tether line snaps taut and hauls you back, hard."))
				end
			end
		elseif s then
			-- out of the run: a full tank, the screen clear
			if s.air < AIR_SECS then s.air = AIR_SECS; show_air(player, s) end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local s = suits[player:get_player_name()]
	if s and s.weight then player:set_physics_override({gravity = 1}) end
	suits[player:get_player_name()] = nil
end)
core.register_on_joinplayer(function(player)
	-- (left in low gravity when the server stopped)
	player:set_physics_override({gravity = 1})
end)
core.register_on_dieplayer(function(player)
	local s = suits[player:get_player_name()]
	if s then s.air = AIR_SECS; show_air(player, s) end
end)
-- A new run: a full tank
if orthoverse.adventure and orthoverse.adventure.on_enter then
	table.insert(orthoverse.adventure.on_enter, function(player)
		local s = suit(player:get_player_name())
		s.air = AIR_SECS
		show_air(player, s)
	end)
end

-- No harm from falling in low gravity (a fall there is slow)
core.register_on_player_hpchange(function(player, change, reason)
	if change < 0 and reason and reason.type == "fall" then
		local s = suits[player:get_player_name()]
		if s and s.weight then return 0 end
		-- (nor from falling off the ship onto space: the tether hauls them back)
		local under = core.get_node(vector.round(vector.offset(player:get_pos(), 0, -0.6, 0))).name
		if core.get_item_group(under, "ark_void") > 0 then return 0 end
	end
	return change
end, true)

------------------------------------------------------------------------------
-- Air stations

block("air_station", S("Air station (right-click: fills a suit's tank)"), {
	tiles = {tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("air_station")},
	paramtype2 = "facedir", paramtype = "light", light_source = 6,
	on_rightclick = function(pos, node, clicker)
		if not (clicker and clicker:is_player()) then return end
		A.refill(clicker)
		sound("hiss", pos, 0.8, 12)
		core.chat_send_player(clicker:get_player_name(), S("Air hisses into your suit. The tank is full."))
	end,
})

------------------------------------------------------------------------------
-- Terminals: the ship's log

block("terminal", S("Terminal (right-click to read; the builder sets its log)"), {
	tiles = {tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("terminal")},
	paramtype2 = "facedir", paramtype = "light", light_source = 4,
	on_construct = function(pos) core.get_meta(pos):set_string("infotext", S("Terminal")) end,
	on_rightclick = function(pos, node, clicker)
		if not (clicker and clicker:is_player()) then return end
		local text = core.get_meta(pos):get_string("text")
		if text == "" then text = S("The screen flickers. Nothing.") end
		core.show_formspec(clicker:get_player_name(), "orthoverse_ark:terminal",
			"formspec_version[4]size[10,6.4]bgcolor[#04121cee;true]box[0,0;10,0.9;#0b3348]label[0.4,0.45;" ..
			core.formspec_escape(S("SHIP'S LOG")) .. "]style_type[textarea;textcolor=#9fe8ff;font=mono]textarea[0.4,1.2;9.2,4.2;;;" ..
			core.formspec_escape(text) .. "]button_exit[3.5,5.5;3,0.7;ok;" .. S("Close") .. "]")
	end,
})

------------------------------------------------------------------------------
-- Bulkheads: shut behind the party

block("bulkhead", S("Bulkhead (shut)"), {tiles = {tex("bulkhead")}, groups = {cracky = 1, not_in_creative_inventory = 0}})
core.register_node("orthoverse_ark:bulkhead_open", {
	description = S("Bulkhead's place (open; shut once the whole party has crossed the seal plates beyond it)"),
	drawtype = "airlike", paramtype = "light", sunlight_propagates = true, walkable = false, pointable = false,
	buildable_to = false, is_ground_content = false, inventory_image = tex("bulkhead"),
})
block("seal_plate", S("Seal plate (deck; once every living player of a run has crossed one, the bulkheads near it shut)"),
	{tiles = {tex("deck")}})

local SEAL_REACH = 10

local function seal(key, run, pos)
	local d = data(run)
	local id = core.pos_to_string(pos)
	-- the plates round this one are one seal: find the first of them
	local plates = core.find_nodes_in_area(vector.offset(pos, -4, -1, -4), vector.offset(pos, 4, 1, 4), {"orthoverse_ark:seal_plate"})
	table.sort(plates, function(a, b) return core.pos_to_string(a) < core.pos_to_string(b) end)
	id = plates[1] and core.pos_to_string(plates[1]) or id
	if d.sealed[id] then return end
	d.crossed[id] = d.crossed[id] or {}
	return id, d.crossed[id]
end

local function try_seal(key, run, pos, id, crossed)
	local d = data(run)
	for _, pl in ipairs(living(run)) do
		if not crossed[pl:get_player_name()] then return end
	end
	local marks = {}
	for _, m in ipairs(core.find_nodes_in_area(vector.offset(pos, -SEAL_REACH, -3, -SEAL_REACH),
			vector.offset(pos, SEAL_REACH, 3, SEAL_REACH), {"orthoverse_ark:bulkhead_open"})) do
		-- (only this adventure's: never a neighbour's)
		if adventure(m) == key then marks[#marks + 1] = m end
	end
	-- nobody standing in the doorway
	for _, m in ipairs(marks) do
		for _, obj in ipairs(core.get_objects_inside_radius(m, 0.9)) do
			if obj:is_player() then return end
		end
	end
	d.sealed[id] = true
	for _, m in ipairs(marks) do core.set_node(m, {name = "orthoverse_ark:bulkhead"}) end
	if marks[1] then sound("slam", marks[1], 1, 40) end
	tell(run, S("Behind you a bulkhead slams down and locks. Somewhere a light turns from green to red."))
end

local seal_tick = 0
core.register_globalstep(function(dtime)
	seal_tick = seal_tick + dtime
	if seal_tick < 0.3 then return end
	seal_tick = 0
	local ad = orthoverse.adventure
	if not (ad and ad.runs) then return end
	for key, run in pairs(ad.runs) do
		for n in pairs(run.members) do
			local pl = core.get_player_by_name(n)
			if pl and pl:get_hp() > 0 then
				local feet = vector.round(vector.offset(pl:get_pos(), 0, -0.4, 0))
				if core.get_node(feet).name == "orthoverse_ark:seal_plate" then
					local id, crossed = seal(key, run, feet)
					if id then
						crossed[n] = true
						try_seal(key, run, feet, id, crossed)
					end
				end
			end
		end
	end
end)

------------------------------------------------------------------------------
-- Cryo pods

local POD_BOX = {type = "fixed", fixed = {{-0.5, -0.5, -0.5, 0.5, -0.375, 0.5}, {-0.5, -0.5, 0.375, 0.5, 0.5, 0.5},
	{-0.5, -0.5, -0.5, -0.375, 0.5, 0.5}, {0.375, -0.5, -0.5, 0.5, 0.5, 0.5}}}
local POD_TOP_BOX = {type = "fixed", fixed = {{-0.5, 0.375, -0.5, 0.5, 0.5, 0.5}, {-0.5, -0.5, 0.375, 0.5, 0.5, 0.5},
	{-0.5, -0.5, -0.5, -0.375, 0.5, 0.5}, {0.375, -0.5, -0.5, 0.5, 0.5, 0.5}}}

block("cryo_pod", S("Cryo pod (a sleeper inside; as a player passes it may open)"), {
	tiles = {tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_front")},
	paramtype2 = "facedir", paramtype = "light", light_source = 3,
	groups = {cracky = 2, orthoverse_timer = 1},
	on_construct = function(pos) core.get_node_timer(pos):start(1) end,
	on_timer = function(pos)
		local key, def, run = adventure(pos)
		if not (def and def.open and run) then return true end
		local meta = core.get_meta(pos)
		local id = "run:" .. run.started
		if meta:get_string("run") == id then return true end
		local near = false
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 3.5)) do
			if obj:is_player() and run.members[obj:get_player_name()] then near = true break end
		end
		if not near then return true end
		meta:set_string("run", id)
		local n = 0
		for _ in pairs(run.members) do n = n + 1 end
		if math.random() >= POD_CHANCE[math.max(1, math.min(4, n))] then return true end
		-- (no more than the spawners' limit of monsters near it, however many
		-- pods a builder sets)
		local ms = orthoverse.monsters
		if not core.registered_entities["orthoverse_monsters:sleeper"] or
				(ms and ms.near_count and ms.near_count(pos) >= (ms.NEAR_CAP or 30)) then return true end
		-- it opens: the lid lifts, the sleeper steps out in front
		local node = core.get_node(pos)
		local top = vector.offset(pos, 0, 1, 0)
		core.swap_node(pos, {name = "orthoverse_ark:cryo_pod_open", param2 = node.param2})
		if core.get_node(top).name == "orthoverse_ark:cryo_pod_top" then
			core.swap_node(top, {name = "orthoverse_ark:cryo_pod_top_open", param2 = node.param2})
		end
		sound("crack", pos, 1, 20)
		core.add_particlespawner({amount = 30, time = 0.6, pos = {min = vector.offset(pos, -0.4, 0, -0.4),
			max = vector.offset(pos, 0.4, 1.6, 0.4)}, vel = {min = {x = -0.6, y = 0.2, z = -0.6}, max = {x = 0.6, y = 1, z = 0.6}},
			exptime = {min = 0.8, max = 1.6}, size = {min = 2, max = 4}, texture = tex("mist")})
		local front = vector.subtract(pos, core.facedir_to_dir(node.param2))
		local obj = core.add_entity(vector.offset(front, 0, -0.45, 0), "orthoverse_monsters:sleeper")
		local ent = obj and obj:get_luaentity()
		if ent then ent._adventure, ent._run, ent._spawner = key, id, core.pos_to_string(pos) end
		return true
	end,
	drawtype = "nodebox", node_box = POD_BOX, use_texture_alpha = "clip",
})
block("cryo_pod_top", S("Cryo pod (its top)"), {
	tiles = {tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_front_top")},
	paramtype2 = "facedir", paramtype = "light", drawtype = "nodebox", node_box = POD_TOP_BOX, use_texture_alpha = "clip",
})
block("cryo_pod_open", S("Cryo pod, open and empty"), {
	tiles = {tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_open")},
	paramtype2 = "facedir", paramtype = "light", drawtype = "nodebox", node_box = POD_BOX, use_texture_alpha = "clip",
	groups = {cracky = 2, not_in_creative_inventory = 1},
})
block("cryo_pod_top_open", S("Cryo pod, open and empty (its top)"), {
	tiles = {tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_side"), tex("pod_open_top")},
	paramtype2 = "facedir", paramtype = "light", drawtype = "nodebox", node_box = POD_TOP_BOX, use_texture_alpha = "clip",
	groups = {cracky = 2, not_in_creative_inventory = 1},
})

------------------------------------------------------------------------------
-- The mind's core, and the doors it keeps shut

block("pod_door", S("Pod bay door (opens when the ship's mind is pulled)"), {tiles = {tex("pod_door")},
	groups = {cracky = 1}})
block("bridge_door", S("Bridge door (opens when the ship's mind is pulled)"), {tiles = {tex("bridge_door")},
	groups = {cracky = 1}})

-- The Custodian, destroyed: orthoverse_monsters tells us
function A.custodian_down(pos)
	local key, def, run = adventure(pos)
	if run then data(run).custodian = true end
end

local function pull_core(pos, node, clicker)
	local key, def, run = in_run(clicker, pos)
	if not run then return end
	local d = data(run)
	local name = clicker:get_player_name()
	if d.mind then return end
	if not d.custodian then
		core.chat_send_player(name, S("The core is clamped in its housing. Something on this deck still keeps it."))
		return
	end
	d.mind = true
	core.swap_node(pos, {name = "orthoverse_ark:mind_core_out", param2 = node.param2})
	sound("powerdown", pos, 1, 64)
	local p1, p2 = area(def)
	for _, p in ipairs(core.find_nodes_in_area(p1, p2, {"orthoverse_ark:pod_door", "orthoverse_ark:bridge_door"})) do
		core.remove_node(p)
	end
	tell(run, S("The core slides out in your hands, and its light dies. All through the ship, doors that were locked " ..
		"grind open. Below the hub, the escape pods wait."))
end

block("mind_core", S("The ship's mind: its core (pull it, once its keeper is destroyed)"), {
	tiles = {tex("core")}, light_source = 12, paramtype = "light", drawtype = "nodebox",
	node_box = {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, 0.4, 0.3}},
	on_rightclick = pull_core,
})
block("mind_core_out", S("The ship's mind: its core, pulled"), {
	tiles = {tex("core_dead")}, paramtype = "light", drawtype = "nodebox",
	node_box = {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, -0.2, 0.3}},
	groups = {cracky = 2, not_in_creative_inventory = 1},
})

------------------------------------------------------------------------------
-- The finish: the escape pod's launch handle

block("launch", S("Escape pod launch handle (an adventure finish: pull it to complete the adventure)"), {
	tiles = {tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("launch")},
	paramtype2 = "facedir", paramtype = "light", light_source = 7,
	on_rightclick = function(pos, node, clicker)
		local ad = orthoverse.adventure
		if not (clicker and clicker:is_player() and ad and ad.at_finish) then return end
		local key, def, run = in_run(clicker, pos)
		if run then
			sound("launch", pos, 1, 32)
			core.chat_send_player(clicker:get_player_name(),
				S("Clamps let go. The pod falls away from the dead ship, turns, and the green and blue world fills the window."))
		end
		ad.at_finish(pos, clicker)
	end,
})
