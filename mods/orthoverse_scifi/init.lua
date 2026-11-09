-- orthoverse_scifi: the blocks of a crashed starship, for The Fallen Star and
-- for any builder's adventure (all in the Creative tab).
--
-- * Hull plating (plain and scorched), deck grating, panel lights, ship's
--   glass, cargo crates, consoles, reactor cores.
-- * A loose panel: looks like hull plating, but players walk through it (the
--   way into a secret duct).
-- * Keycards (blue, red) and card doors: a door opens for a player carrying
--   its card (every block of it, two wide and two high). Card lockers: of all
--   the lockers of one colour in an adventure, one, chosen at random each run,
--   holds that card (one for each player who opens it). A builder right-clicks
--   a locker to change its colour.
-- * Relays and blast doors: when every relay in an adventure is thrown, its
--   blast doors open and its live floors go dead.
-- * Live floor: plates in two sets that take turns to carry a charge (each
--   live for 1.6 s of every 4, sparking a moment before). A player standing
--   on a live plate is jolted (3 health, at most every 0.8 s). A floor
--   controller (hidden in a wall) runs the plates within 32 blocks of it.
-- * A medical station: heals a player fully, once per run.
-- * The black box: a finish of the ship's own look.
--
-- Doors, relays and floors are put back as saved when the adventure is
-- restored after each run. By Keir Finlow-Bates; textures CC BY-SA 3.0.

local S = core.get_translator and core.get_translator("orthoverse_scifi") or function(s) return s end

orthoverse = orthoverse or {}
orthoverse.scifi = {}

local function now() return core.get_us_time() / 1e6 end
local metal = rawget(_G, "default") and default.node_sound_metal_defaults() or nil
local glass_sound = rawget(_G, "default") and default.node_sound_glass_defaults() or nil
local wood = rawget(_G, "default") and default.node_sound_wood_defaults() or nil

local function tex(name) return "orthoverse_scifi_" .. name .. ".png" end

------------------------------------------------------------------------------
-- Adventures: which one a position is in, its run, who may change things

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

local function builder(name, key)
	local ad = orthoverse.adventure
	if key and ad and ad.may_manage then return ad.may_manage(name, key) end
	return core.check_player_privs(name, {protection_bypass = true})
end

-- A run's own scratch space (gone with the run)
local function run_data(run)
	run.scifi = run.scifi or {cards = {}, taken = {}, healed = {}}
	return run.scifi
end

------------------------------------------------------------------------------
-- Plain blocks

local function plain(id, desc, def)
	def.description = desc
	def.groups = def.groups or {cracky = 2}
	def.sounds = def.sounds or metal
	def.is_ground_content = false
	core.register_node("orthoverse_scifi:" .. id, def)
end

plain("hull", S("Hull plating"), {tiles = {tex("hull")}})
plain("hull_scorched", S("Scorched hull plating"), {tiles = {tex("hull_scorched")}})
plain("deck", S("Deck grating"), {tiles = {tex("deck")}})
plain("panel_light", S("Panel light"), {tiles = {tex("panel_light")}, light_source = 12, paramtype = "light"})
plain("glass", S("Ship's glass"), {tiles = {tex("glass")}, drawtype = "glasslike", paramtype = "light",
	sunlight_propagates = true, use_texture_alpha = "blend", sounds = glass_sound})
plain("crate", S("Cargo crate"), {tiles = {tex("crate_top"), tex("crate_top"), tex("crate")}, groups = {choppy = 2},
	sounds = wood})
plain("console", S("Console"), {tiles = {tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("console")},
	paramtype2 = "facedir", light_source = 5, paramtype = "light"})
plain("reactor", S("Reactor core"), {tiles = {tex("reactor")}, light_source = 14, paramtype = "light"})
plain("loose_panel", S("Loose panel (looks like hull plating; walk through it)"), {tiles = {tex("hull")},
	walkable = false})

------------------------------------------------------------------------------
-- Keycards, card doors, card lockers

local COLOURS = {blue = S("blue"), red = S("red")}

for c, label in pairs(COLOURS) do
	core.register_craftitem("orthoverse_scifi:card_" .. c, {
		description = S("Keycard (@1)", label) .. "\n" .. S("Opens the @1 doors", label),
		inventory_image = tex("card_" .. c),
		stack_max = 1,
	})
end

local function carries(player, item)
	return player:get_inventory():contains_item("main", item)
end

-- Every block of a door: the same node, joined to this one, at most 3 away
local function door_blocks(pos, name)
	local out, seen, todo = {}, {}, {pos}
	while #todo > 0 and #out < 12 do
		local p = table.remove(todo)
		local k = core.pos_to_string(p)
		if not seen[k] and vector.distance(p, pos) <= 3 and core.get_node(p).name == name then
			seen[k] = true
			out[#out + 1] = p
			for _, d in ipairs({{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) do
				todo[#todo + 1] = vector.add(p, vector.new(d[1], d[2], d[3]))
			end
		end
	end
	return out
end

local function open_door(pos, name)
	for _, p in ipairs(door_blocks(pos, name)) do core.remove_node(p) end
	core.sound_play("orthoverse_scifi_door", {pos = pos, gain = 0.8, max_hear_distance = 20}, true)
end
orthoverse.scifi.open_door = open_door

for c, label in pairs(COLOURS) do
	local door = "orthoverse_scifi:door_" .. c
	plain("door_" .. c, S("Card door (@1): opens for a player carrying a @2 keycard", label, label), {
		tiles = {tex("hull"), tex("hull"), tex("door_" .. c)}, paramtype2 = "facedir",
		on_rightclick = function(pos, node, clicker)
			if not clicker or not clicker:is_player() then return end
			local name = clicker:get_player_name()
			local key, _, run = adventure(pos)
			if (run and run.members[name] and carries(clicker, "orthoverse_scifi:card_" .. c))
					or (not run and builder(name, key)) then
				open_door(pos, door)
			else
				core.chat_send_player(name, S("The door is locked. Its reader glows @1: it wants a @2 keycard.", label, label))
			end
		end,
	})
end

-- Card lockers
local LOCKER = "orthoverse_scifi:locker"
local function locker_colour(pos)
	local c = core.get_meta(pos):get_string("colour")
	return COLOURS[c] and c or "blue"
end
local function locker_label(pos)
	local c = locker_colour(pos)
	core.get_meta(pos):set_string("infotext", S("Locker (one of these holds the @1 keycard)", COLOURS[c]))
end

plain("locker", S("Card locker: of all the lockers of one colour, one holds that keycard each run"), {
	tiles = {tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("locker")}, paramtype2 = "facedir",
	on_construct = function(pos) locker_label(pos) end,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local key, def, run = adventure(pos)
		local colour = locker_colour(pos)
		if not (run and run.members[name]) then
			if builder(name, key) and not (def and def.open) then
				local next = colour == "blue" and "red" or "blue"
				core.get_meta(pos):set_string("colour", next)
				locker_label(pos)
				core.chat_send_player(name, S("This locker is now one of the @1 keycard's.", COLOURS[next]))
			end
			return
		end
		local data = run_data(run)
		-- Which locker of this colour holds the card: chosen at the first
		-- opening of the run
		if not data.cards[colour] then
			local p1, p2 = area(def)
			local spots = {}
			for _, p in ipairs(core.find_nodes_in_area(p1, p2, {LOCKER})) do
				if locker_colour(p) == colour then spots[#spots + 1] = p end
			end
			data.cards[colour] = #spots > 0 and core.pos_to_string(spots[math.random(#spots)]) or ""
		end
		core.sound_play("orthoverse_scifi_relay", {pos = pos, gain = 0.4, pitch = 0.7, max_hear_distance = 10}, true)
		if data.cards[colour] ~= core.pos_to_string(pos) then
			core.chat_send_player(name, S("Empty: overalls, a mug, a photo of somewhere green."))
			return
		end
		local took = name .. ":" .. colour
		if data.taken[took] then
			core.chat_send_player(name, S("You have the card from here already."))
			return
		end
		local left = clicker:get_inventory():add_item("main", "orthoverse_scifi:card_" .. colour)
		if left:is_empty() then
			data.taken[took] = true
			core.chat_send_player(name, S("A @1 keycard!", COLOURS[colour]))
		else
			core.chat_send_player(name, S("A @1 keycard, but your pack is full.", COLOURS[colour]))
		end
	end,
})

------------------------------------------------------------------------------
-- Relays and blast doors

local RELAY_OFF, RELAY_ON = "orthoverse_scifi:relay", "orthoverse_scifi:relay_on"
local BLAST = "orthoverse_scifi:blast_door"
local dead = {}   -- key -> run start: its relays are all thrown (floors dead)

local function powered_down(key, run)
	return run and dead[key] == run.started
end

plain("blast_door", S("Blast door: opens when every relay in the adventure is thrown"), {
	tiles = {tex("hull"), tex("hull"), tex("blast_door")}, paramtype2 = "facedir",
	on_rightclick = function(pos, node, clicker)
		if clicker and clicker:is_player() then
			core.chat_send_player(clicker:get_player_name(), S("A blast door, sealed. No power reaches its motors."))
		end
	end,
})

local function relay_toggle(pos, node, clicker)
	if not clicker or not clicker:is_player() then return end
	local name = clicker:get_player_name()
	local key, def, run = adventure(pos)
	if not ((run and run.members[name]) or (not run and builder(name, key))) then return end
	local on = node.name == RELAY_OFF
	core.swap_node(pos, {name = on and RELAY_ON or RELAY_OFF, param2 = node.param2})
	core.sound_play("orthoverse_scifi_relay", {pos = pos, gain = 0.7, max_hear_distance = 16}, true)
	if not (on and def) then return end
	local p1, p2 = area(def)
	local off = core.find_nodes_in_area(p1, p2, {RELAY_OFF})
	if #off > 0 then
		core.chat_send_player(name, S("The relay clunks over. @1 to go.", #off))
		return
	end
	-- All thrown: power to the doors, none to the floors
	if run then dead[key] = run.started end
	for _, p in ipairs(core.find_nodes_in_area(p1, p2, {BLAST})) do core.remove_node(p) end
	core.sound_play("orthoverse_scifi_door", {pos = pos, gain = 1, pitch = 0.7, max_hear_distance = 48}, true)
	if run then
		for n in pairs(run.members) do
			core.chat_send_player(n, S("Somewhere a blast door grinds open, and the deck plates fall silent."))
		end
	end
end

plain("relay", S("Relay: throw every relay in the adventure to open its blast doors"), {
	tiles = {tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("relay_off")}, paramtype2 = "facedir",
	on_rightclick = relay_toggle,
})
plain("relay_on", S("Relay (thrown)"), {
	tiles = {tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("hull"), tex("relay_on")}, paramtype2 = "facedir",
	drop = RELAY_OFF, groups = {cracky = 2, not_in_creative_inventory = 1},
	on_rightclick = relay_toggle,
})

------------------------------------------------------------------------------
-- Live floor

local PERIOD, LIVE_FOR, WARN_FOR = 4, 1.6, 0.5
local PLATES = {
	a = {off = "orthoverse_scifi:plate_a", on = "orthoverse_scifi:plate_a_live", start = 0},
	b = {off = "orthoverse_scifi:plate_b", on = "orthoverse_scifi:plate_b_live", start = PERIOD / 2},
}
local LIVE_NAMES = {}
for set, p in pairs(PLATES) do
	plain("plate_" .. set, S("Deck plate (live floor, set @1)", set:upper()), {tiles = {tex("plate")}})
	plain("plate_" .. set .. "_live", S("Deck plate, live"), {tiles = {tex("plate_live")}, light_source = 6,
		paramtype = "light", drop = p.off, groups = {cracky = 2, not_in_creative_inventory = 1}})
	LIVE_NAMES[p.on] = true
end

local function phase(t, start)
	return (t - start) % PERIOD
end

local hurt_at = {}   -- name -> last jolt

local function controller_step(pos)
	local key, def, run = adventure(pos)
	local t = now()
	local off = powered_down(key, run)
	local meta = core.get_meta(pos)
	local p1, p2 = vector.subtract(pos, 32), vector.add(pos, 32)
	if def then
		local a1, a2 = area(def)
		p1, p2 = vector.new(math.max(p1.x, a1.x), math.max(p1.y, a1.y), math.max(p1.z, a1.z)),
			vector.new(math.min(p2.x, a2.x), math.min(p2.y, a2.y), math.min(p2.z, a2.z))
	end
	for set, p in pairs(PLATES) do
		local ph = phase(t, p.start)
		local live = not off and ph < LIVE_FOR
		local was = meta:get_int("live_" .. set) == 1
		if live ~= was then
			meta:set_int("live_" .. set, live and 1 or 0)
			local from = core.find_nodes_in_area(p1, p2, {live and p.off or p.on})
			if #from > 0 then
				if core.bulk_swap_node then core.bulk_swap_node(from, {name = live and p.on or p.off})
				else for _, q in ipairs(from) do core.swap_node(q, {name = live and p.on or p.off}) end end
			end
			if live and #from > 0 then
				core.sound_play("orthoverse_scifi_zap", {pos = from[math.random(#from)], gain = 0.5, max_hear_distance = 20}, true)
			end
		end
		-- sparks just before it goes live
		if not off and ph > PERIOD - WARN_FOR and meta:get_int("warned_" .. set) == 0 then
			meta:set_int("warned_" .. set, 1)
			local plates = core.find_nodes_in_area(p1, p2, {p.off})
			for i = 1, math.min(12, #plates) do
				local q = plates[math.random(#plates)]
				core.add_particlespawner({amount = 4, time = WARN_FOR, pos = vector.add(q, {x = 0, y = 0.55, z = 0}), radius = 0.4,
					vel = {min = {x = -1, y = 0.5, z = -1}, max = {x = 1, y = 2, z = 1}}, exptime = {min = 0.1, max = 0.3},
					size = {min = 0.5, max = 1}, texture = tex("plate_live"), glow = 14})
			end
			core.sound_play("orthoverse_scifi_spark", {pos = pos, gain = 0.3, max_hear_distance = 24}, true)
		elseif ph < PERIOD - WARN_FOR then
			meta:set_int("warned_" .. set, 0)
		end
	end
	if off then return end
	-- Jolt whoever stands on a live plate
	for _, player in ipairs(core.get_connected_players()) do
		local pp = player:get_pos()
		if pp.x >= p1.x - 1 and pp.x <= p2.x + 1 and pp.z >= p1.z - 1 and pp.z <= p2.z + 1
				and pp.y >= p1.y - 1 and pp.y <= p2.y + 2 and player:get_hp() > 0 then
			local under = core.get_node({x = math.floor(pp.x + 0.5), y = math.floor(pp.y + 0.5) - 1, z = math.floor(pp.z + 0.5)}).name
			local name = player:get_player_name()
			if LIVE_NAMES[under] and t - (hurt_at[name] or 0) >= 0.8 then
				hurt_at[name] = t
				player:set_hp(player:get_hp() - 3, {type = "set_hp", from = "mod", orthoverse_live_floor = true})
				core.sound_play("orthoverse_scifi_zap", {pos = pp, gain = 0.8, max_hear_distance = 12}, true)
				player:add_velocity({x = 0, y = 3, z = 0})
			end
		end
	end
end

plain("floor_controller", S("Live floor controller: runs the deck plates within 32 blocks (hide it in a wall)"), {
	tiles = {tex("hull")}, groups = {cracky = 2, orthoverse_timer = 1},
	on_construct = function(pos) core.get_node_timer(pos):start(0.2) end,
	on_timer = function(pos)
		controller_step(pos)
		return true
	end,
})

core.register_on_leaveplayer(function(player) hurt_at[player:get_player_name()] = nil end)

------------------------------------------------------------------------------
-- The medical station

plain("medbay", S("Medical station: heals a player fully, once per run"), {
	tiles = {tex("medbay")}, light_source = 4, paramtype = "light",
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local _, _, run = adventure(pos)
		if run and run.members[name] then
			local data = run_data(run)
			if data.healed[name] then
				core.chat_send_player(name, S("The station blinks: one treatment per patient."))
				return
			end
			data.healed[name] = true
		end
		clicker:set_hp(clicker:get_properties().hp_max, {type = "set_hp", from = "mod", orthoverse_medbay = true})
		core.sound_play("orthoverse_scifi_heal", {pos = pos, gain = 0.7, max_hear_distance = 12}, true)
		core.chat_send_player(name, S("A hiss, a sting, and you feel whole again."))
	end,
})

------------------------------------------------------------------------------
-- The black box: the finish, in the ship's look

plain("black_box", S("Black box (an adventure finish: touch it to complete the adventure)"), {
	tiles = {tex("black_box")}, light_source = 6, paramtype = "light",
	on_rightclick = function(pos, node, clicker)
		local ad = orthoverse.adventure
		if ad and ad.at_finish then ad.at_finish(pos, clicker) end
	end,
	on_punch = function(pos, node, puncher)
		local ad = orthoverse.adventure
		if ad and ad.at_finish then ad.at_finish(pos, puncher) end
	end,
})
