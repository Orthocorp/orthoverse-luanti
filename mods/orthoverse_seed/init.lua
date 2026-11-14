-- orthoverse_seed: The Seed. Something fell, and the ground round it is
-- growing. The growth's blocks and what they do, the survey camp's gear, and
-- the camp hangar's crane, for The Seed and any builder's adventure (all in
-- the Creative tab).
--
-- The growth:
-- * Crust, ribbed walls, flesh, glowing nodules: what the growth is made of.
--   When the Heart dies, the growth in its adventure withers to ash.
-- * Membranes: living doors. Fire (a fire pot, a plasma bolt) burns one open.
--   Valves are membranes that may open by themselves: of all the valves of one
--   set in an adventure (a builder right-clicks one to change its set), one,
--   chosen at random at the start of each run, stands open.
-- * Acid: burns, and wears armour as a blow does. Pads float on it, and sink
--   a moment after someone steps on them, coming up again a few seconds later.
-- * Egg sacs: decoration round a spawner, they burst when it wakes (a spawner
--   set to "stealth" wakes for a sneaking player only at half its distance).
-- * Spore vents: spores cloud the sight and slow anyone near without a
--   breathing mask. Gust vents (hidden in a wall): every so often the growth
--   breathes in, then out, and the gust pushes players the way the vent faces.
-- * Creep: a skin that spreads over floors from buds in the floor while a run
--   goes on, slowing whoever wades through it. Fire burns it back.
-- * The Heart: its shell opens when three ganglia (orthoverse_monsters) are
--   cut; its core when its last nodule bursts, and then everything withers.
--
-- The survey camp: stores (three fire pots and a breathing mask for each
-- player, once a run) and a rifle rack (a plasma rifle, once a run, and its
-- charge renewed). The crane: a trolley on a rail, a cable and a magnet, and
-- buttons to drive it (left, right, up, down; the magnet on and off). The
-- magnet lifts the containers under it.
--
-- Everything is put back as saved when the adventure is restored after each
-- run. By Keir Finlow-Bates; textures and sounds CC BY-SA 3.0
-- (tools/seed/make_textures.py).

local S = core.get_translator and core.get_translator("orthoverse_seed") or function(s, ...)
	local args = {...}
	return (s:gsub("@(%d)", function(n) return tostring(args[tonumber(n)]) end))
end

orthoverse = orthoverse or {}
orthoverse.seed = {}

local function now() return core.get_us_time() / 1e6 end
local function tex(name) return "orthoverse_seed_" .. name .. ".png" end
local d = rawget(_G, "default")
local SND = {
	flesh = d and d.node_sound_dirt_defaults({footstep = {name = "default_dirt_footstep", gain = 0.5}}),
	metal = d and d.node_sound_metal_defaults(),
	wood = d and d.node_sound_wood_defaults(),
	gravel = d and d.node_sound_gravel_defaults(),
}

local function sound(name, pos, gain, dist)
	core.sound_play("orthoverse_seed_" .. name, {pos = pos, gain = gain or 0.7, max_hear_distance = dist or 20}, true)
end

------------------------------------------------------------------------------
-- Adventures: which one a position is in, its run, its area

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

local function run_data(run)
	run.seed = run.seed or {ganglia = 0, gear = {}, rifles = {}, dead = false}
	return run.seed
end

local function in_run(player)
	if not player or not player:is_player() then return end
	local key, def, run = adventure(player:get_pos())
	if run and run.members[player:get_player_name()] then return key, def, run end
end

local function tell_members(run, text)
	for n in pairs(run.members) do core.chat_send_player(n, text) end
end

-- Several blocks set at once, in steps (a big area changed without a pause)
local function in_steps(list, per, fn, done)
	local i = 1
	local function step()
		local last = math.min(#list, i + per - 1)
		for j = i, last do fn(list[j]) end
		i = last + 1
		if i <= #list then core.after(0.1, step) elseif done then done() end
	end
	step()
end

------------------------------------------------------------------------------
-- The growth's plain blocks

local function node(id, desc, def)
	def.description = desc
	def.groups = def.groups or {crumbly = 2}
	def.sounds = def.sounds or SND.flesh
	def.is_ground_content = false
	core.register_node("orthoverse_seed:" .. id, def)
end

local function growth(groups)
	groups = groups or {}
	groups.seed_growth = 1
	groups.crumbly = groups.crumbly or 2
	return groups
end

node("crust", S("Growth crust"), {tiles = {tex("crust"), "default_dirt.png", tex("crust_side")}, groups = growth()})
node("wall", S("Ribbed growth"), {tiles = {tex("wall")}, groups = growth()})
node("wall_dark", S("Dark ribbed growth"), {tiles = {tex("wall_dark")}, groups = growth()})
node("flesh", S("Growth flesh"), {tiles = {tex("flesh")}, groups = growth()})
node("nodule", S("Glowing nodule"), {tiles = {tex("nodule")}, light_source = 12, paramtype = "light",
	groups = growth()})
node("ash", S("Ash"), {tiles = {tex("ash")}, groups = {crumbly = 3}, sounds = SND.gravel})
node("heart", S("The Heart's flesh"), {tiles = {tex("heart")}, light_source = 4, paramtype = "light", groups = growth()})

-- What each kind of growth becomes when the Heart dies
local WITHER = {
	["orthoverse_seed:crust"] = "orthoverse_seed:ash", ["orthoverse_seed:wall"] = "orthoverse_seed:ash",
	["orthoverse_seed:wall_dark"] = "orthoverse_seed:ash", ["orthoverse_seed:flesh"] = "orthoverse_seed:ash",
	["orthoverse_seed:heart"] = "orthoverse_seed:ash", ["orthoverse_seed:egg"] = "orthoverse_seed:egg_burst",
	["orthoverse_seed:vent"] = "orthoverse_seed:ash", ["orthoverse_seed:membrane"] = "air",
	["orthoverse_seed:valve"] = "air", ["orthoverse_seed:creep"] = "air", ["orthoverse_seed:bud"] = "orthoverse_seed:ash",
	["orthoverse_seed:shell"] = "air", ["orthoverse_seed:gust"] = "orthoverse_seed:ash",
}

------------------------------------------------------------------------------
-- Fire: what burns, and burning it

local function burn_effect(pos)
	core.add_particlespawner({amount = 16, time = 0.4, pos = {min = vector.offset(pos, -0.5, -0.5, -0.5),
		max = vector.offset(pos, 0.5, 0.5, 0.5)}, vel = {min = {x = -0.3, y = 0.8, z = -0.3}, max = {x = 0.3, y = 2, z = 0.3}},
		exptime = {min = 0.4, max = 0.9}, size = {min = 2, max = 4}, texture = tex("flame"), glow = 14})
end

-- May `player` change things at `pos`? In an adventure, a player of its run
-- (or its builder, while no run is on); elsewhere, whoever may build there
local function may_change(pos, player)
	if not player or not player.is_player or not player:is_player() then return false end
	local name = player:get_player_name()
	local key, _, run = adventure(pos)
	if key then
		if run then return run.members[name] == true end
		return builder(name, key)
	end
	return not core.is_protected(pos, name)
end
orthoverse.seed.may_change = may_change

-- Burn what can burn within `r` of `pos` (what `player` may change); true if
-- anything did
function orthoverse.seed.burn(pos, r, player)
	local found = core.find_nodes_in_area(vector.offset(pos, -r, -r, -r), vector.offset(pos, r, r, r), {"group:seed_burnable"})
	local any = false
	for _, p in ipairs(found) do
		if vector.distance(p, pos) <= r + 0.5 and may_change(p, player) then
			local def = core.registered_nodes[core.get_node(p).name]
			core.set_node(p, {name = def and def._burns_to or "air"})
			burn_effect(p)
			any = true
		end
	end
	if any then sound("squelch", pos, 0.8) end
	return any
end

------------------------------------------------------------------------------
-- Membranes and valves

local MEMBRANE = {
	tiles = {tex("membrane")}, use_texture_alpha = "blend", paramtype = "light", sunlight_propagates = true,
	drawtype = "glasslike",
}

local mem = table.copy(MEMBRANE)
mem.groups = {crumbly = 2, seed_burnable = 1}
node("membrane", S("Membrane (fire burns it open)"), mem)

local VALVE = table.copy(MEMBRANE)
VALVE.groups = {crumbly = 2, seed_burnable = 1}
VALVE.on_construct = function(pos)
	local meta = core.get_meta(pos)
	if meta:get_string("set") == "" then meta:set_string("set", "a") end
	meta:set_string("infotext", "")
end
VALVE.on_rightclick = function(pos, node, clicker)
	if not clicker or not clicker:is_player() then return end
	local name = clicker:get_player_name()
	local key, _, run = adventure(pos)
	if run or not builder(name, key) then return end
	local meta = core.get_meta(pos)
	local set = meta:get_string("set")
	local nxt = string.char(((set:byte() or 97) - 97 + 1) % 8 + 97)
	meta:set_string("set", nxt)
	core.chat_send_player(name, S("Valve set @1: of the valves of each set, one stands open in a run.", nxt))
end
node("valve", S("Valve (a membrane; one of each set stands open in a run)"), VALVE)

-- At the start of each run: one valve of each set opens
local function open_valves(def)
	local p1, p2 = area(def)
	local sets = {}
	for _, p in ipairs(core.find_nodes_in_area(p1, p2, {"orthoverse_seed:valve"})) do
		local s = core.get_meta(p):get_string("set")
		sets[s] = sets[s] or {}
		table.insert(sets[s], p)
	end
	for _, list in pairs(sets) do
		-- the valves of a set that touch are one opening
		local p = list[math.random(#list)]
		local todo, seen = {p}, {}
		while #todo > 0 do
			local q = table.remove(todo)
			local k = core.pos_to_string(q)
			if not seen[k] and core.get_node(q).name == "orthoverse_seed:valve" then
				seen[k] = true
				core.remove_node(q)
				for _, dd in ipairs({{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) do
					todo[#todo + 1] = vector.offset(q, dd[1], dd[2], dd[3])
				end
			end
		end
	end
end
orthoverse.seed.open_valves = open_valves

------------------------------------------------------------------------------
-- Acid and pads

local ACID = {
	drawtype = "liquid", waving = 3,
	tiles = {{name = tex("acid_animated"), backface_culling = false,
		animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 2.0}}},
	special_tiles = {{name = tex("acid_animated"), backface_culling = false,
		animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 2.0}}},
	use_texture_alpha = "blend", paramtype = "light", light_source = 4,
	walkable = false, pointable = false, diggable = false, buildable_to = false, is_ground_content = false,
	drop = "", drowning = 1, liquidtype = "source", liquid_range = 0, liquid_renewable = false,
	liquid_viscosity = 3, damage_per_second = 2, post_effect_color = {a = 160, r = 90, g = 170, b = 30},
	groups = {liquid = 3, not_in_creative_inventory = 0},
	sounds = d and d.node_sound_water_defaults(),
}
local acid = table.copy(ACID)
acid.liquid_alternative_flowing = "orthoverse_seed:acid"
acid.liquid_alternative_source = "orthoverse_seed:acid"
node("acid", S("Acid (burns; wears armour)"), acid)

local PAD_BOX = {type = "fixed", fixed = {-0.5, 0.375, -0.5, 0.5, 0.5, 0.5}}
node("pad", S("Floating pad (sinks a moment after it is stood on)"), {
	drawtype = "nodebox", node_box = PAD_BOX, selection_box = PAD_BOX, collision_box = PAD_BOX,
	tiles = {tex("pad"), tex("pad"), tex("pad_side")}, use_texture_alpha = "clip", paramtype = "light",
	groups = {crumbly = 3},
	on_timer = function(pos)
		-- sinking: the acid closes over it, and it comes up again later
		core.swap_node(pos, {name = "orthoverse_seed:pad_sunk"})
		core.get_node_timer(pos):start(4)
		sound("squelch", pos, 0.4, 12)
	end,
})
local sunk = table.copy(ACID)
sunk.liquid_alternative_flowing = "orthoverse_seed:pad_sunk"
sunk.liquid_alternative_source = "orthoverse_seed:pad_sunk"
sunk.groups = {liquid = 3, not_in_creative_inventory = 1}
sunk.on_timer = function(pos)
	core.swap_node(pos, {name = "orthoverse_seed:pad"})
end
node("pad_sunk", S("Sunken pad"), sunk)

------------------------------------------------------------------------------
-- Egg sacs

local EGG_BOX = {type = "fixed", fixed = {-0.375, -0.5, -0.375, 0.375, 0.375, 0.375}}
node("egg", S("Egg sac (bursts when the spawner beside it wakes)"), {
	drawtype = "nodebox", node_box = EGG_BOX, selection_box = EGG_BOX, tiles = {tex("egg")},
	paramtype = "light", light_source = 2, groups = growth({seed_burnable = 1}), _burns_to = "orthoverse_seed:egg_burst",
})
node("egg_burst", S("Burst egg sac"), {
	drawtype = "nodebox", node_box = EGG_BOX, selection_box = EGG_BOX,
	tiles = {tex("egg_burst"), tex("egg"), tex("egg")}, paramtype = "light", groups = {crumbly = 3},
})

-- A spawner woke (orthoverse_monsters): the egg sacs round it burst
local function hatch(pos)
	local eggs = core.find_nodes_in_area(vector.offset(pos, -3, -1, -3), vector.offset(pos, 3, 3, 3), {"orthoverse_seed:egg"})
	for _, p in ipairs(eggs) do
		core.swap_node(p, {name = "orthoverse_seed:egg_burst"})
		core.add_particlespawner({amount = 10, time = 0.2, pos = p, radius = 0.3,
			vel = {min = {x = -1, y = 0.5, z = -1}, max = {x = 1, y = 2, z = 1}}, exptime = {min = 0.3, max = 0.6},
			size = {min = 1, max = 2}, texture = tex("acid")})
	end
	if #eggs > 0 then sound("pop", pos, 0.8) end
end
orthoverse.seed.hatch = hatch

------------------------------------------------------------------------------
-- Spores and the breathing mask

core.register_tool("orthoverse_seed:mask", {
	description = S("Breathing mask") .. "\n" .. S("Carried: spores do you no harm, while its filters last"),
	inventory_image = tex("mask"),
	groups = {orthoverse_kit = 1},
})

local MASK_USE = math.ceil(65535 / 50)   -- 50 seconds of spores
local spored = {}   -- name -> {hud, till}

-- The player breathes spores for a second: a mask takes it (and wears), or
-- their sight clouds and they slow for a few seconds
function orthoverse.seed.spores(player, secs)
	secs = secs or 4
	local inv = player:get_inventory()
	for i, stack in ipairs(inv:get_list("main") or {}) do
		if stack:get_name() == "orthoverse_seed:mask" then
			local wear = stack:get_wear() + MASK_USE
			if wear >= 65535 then
				inv:set_stack("main", i, ItemStack(""))
				core.chat_send_player(player:get_player_name(), S("Your breathing mask's filters are spent."))
			else
				stack:set_wear(wear)
				inv:set_stack("main", i, stack)
			end
			return false
		end
	end
	local name = player:get_player_name()
	local s = spored[name]
	if s then
		s.till = math.max(s.till, now() + secs)
	else
		local id = player:hud_add({type = "image", position = {x = 0.5, y = 0.5}, scale = {x = -100, y = -100},
			text = tex("spores_overlay"), z_index = -300, alignment = {x = 0, y = 0}})
		spored[name] = {hud = id, till = now() + secs}
		core.chat_send_player(name, S("Spores: you choke, and your eyes stream."))
	end
	if orthoverse.combat and orthoverse.combat.hamper then orthoverse.combat.hamper(player, 0.55, secs) end
	return true
end

core.register_on_leaveplayer(function(player) spored[player:get_player_name()] = nil end)

node("vent", S("Spore vent"), {
	tiles = {tex("vent"), tex("flesh"), tex("flesh")}, groups = growth({orthoverse_timer = 1}),
	on_construct = function(pos) core.get_node_timer(pos):start(1) end,
	on_timer = function(pos)
		local up = vector.offset(pos, 0, 1, 0)
		core.add_particlespawner({amount = 12, time = 1, pos = {min = vector.offset(up, -0.4, -0.4, -0.4),
			max = vector.offset(up, 0.4, -0.2, 0.4)}, vel = {min = {x = -0.4, y = 0.6, z = -0.4}, max = {x = 0.4, y = 1.4, z = 0.4}},
			exptime = {min = 1.5, max = 3}, size = {min = 1, max = 2.5}, texture = tex("spore"), glow = 6})
		for _, obj in ipairs(core.get_objects_inside_radius(up, 2.6)) do
			if obj:is_player() then orthoverse.seed.spores(obj, 4) end
		end
		return true
	end,
})

------------------------------------------------------------------------------
-- Gust vents: the growth breathes

local GUST_CYCLE, GUST_REACH, GUST_SPEED = 14, 32, 3.5
node("gust", S("Gust vent (hidden: pushes players the way it faces, every few seconds)"), {
	tiles = {tex("wall_dark"), tex("wall_dark"), tex("wall_dark"), tex("wall_dark"), tex("wall_dark"), tex("vent")},
	paramtype2 = "facedir", groups = growth({orthoverse_timer = 1}),
	on_construct = function(pos) core.get_node_timer(pos):start(GUST_CYCLE) end,
	on_timer = function(pos, elapsed)
		local key, _, run = adventure(pos)
		core.get_node_timer(pos):start(GUST_CYCLE)
		if key and not run then return false end   -- (in an adventure, only while a run is on)
		local dir = core.facedir_to_dir(core.get_node(pos).param2)
		dir = vector.multiply(dir, -1)   -- the face with the vent looks out
		sound("inhale", pos, 0.9, 32)
		core.after(2.2, function()
			sound("gust", pos, 1.0, 40)
			local t = 0
			local function push()
				for _, obj in ipairs(core.get_objects_inside_radius(pos, GUST_REACH)) do
					if obj:is_player() then
						local to = vector.subtract(obj:get_pos(), pos)
						-- (in front of it, in the open: not through a wall); up
						-- to GUST_SPEED along it
						if vector.dot(to, dir) > 0 and core.line_of_sight(vector.add(pos, dir),
								vector.offset(obj:get_pos(), 0, 1, 0)) then
							local along = vector.dot(obj:get_velocity(), dir)
							if along < GUST_SPEED then
								obj:add_velocity(vector.multiply(dir, math.min(1.5, GUST_SPEED - along)))
							end
						end
					end
				end
				core.add_particlespawner({amount = 20, time = 0.25, pos = {min = vector.offset(pos, -1, -1, -1),
					max = vector.offset(pos, 1, 1, 1)}, vel = {min = vector.multiply(dir, 8), max = vector.multiply(dir, 12)},
					exptime = {min = 1, max = 1.6}, size = {min = 1, max = 2}, texture = tex("spore")})
				t = t + 0.25
				if t < 2 then core.after(0.25, push) end
			end
			push()
		end)
		return false
	end,
})

------------------------------------------------------------------------------
-- Creep: spreads over floors from buds while a run goes on

local CREEP_BOX = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5}}
node("creep", S("Creep (slows; fire burns it)"), {
	drawtype = "nodebox", node_box = CREEP_BOX, selection_box = CREEP_BOX, tiles = {tex("creep")},
	use_texture_alpha = "clip", paramtype = "light", walkable = false, buildable_to = true, floodable = true,
	groups = {crumbly = 3, seed_burnable = 1},
})

local CREEP_EVERY, CREEP_STEP, CREEP_REACH, CREEP_MAX = 30, 5, 5, 60
node("bud", S("Creep bud (in a floor: creep spreads from it during a run)"), {
	tiles = {tex("crust"), "default_dirt.png", tex("crust_side")}, groups = growth({orthoverse_timer = 1}),
	on_construct = function(pos) core.get_node_timer(pos):start(CREEP_EVERY) end,
	on_timer = function(pos)
		core.get_node_timer(pos):start(CREEP_EVERY)
		local _, _, run = adventure(pos)
		if not run then return false end
		local meta = core.get_meta(pos)
		local id = "run:" .. run.started
		if meta:get_string("run") ~= id then meta:set_string("run", id); meta:set_int("n", 0) end
		local n = meta:get_int("n")
		if n >= CREEP_MAX then return false end
		-- floor cells near the bud that the creep can cover: air on a solid block
		local cands = {}
		for _, p in ipairs(core.find_nodes_in_area(vector.offset(pos, -CREEP_REACH, -1, -CREEP_REACH),
				vector.offset(pos, CREEP_REACH, 2, CREEP_REACH), {"air"})) do
			local below = core.registered_nodes[core.get_node(vector.offset(p, 0, -1, 0)).name]
			if below and below.walkable and below.drawtype == "normal" then
				-- next to creep already (or the bud): it spreads, it does not jump
				for _, dd in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
					local q = vector.offset(p, dd[1], 0, dd[2])
					if core.get_node(q).name == "orthoverse_seed:creep" or vector.equals(vector.offset(q, 0, -1, 0), pos) then
						cands[#cands + 1] = p
						break
					end
				end
			end
		end
		for _ = 1, math.min(CREEP_STEP, #cands) do
			local i = math.random(#cands)
			core.set_node(cands[i], {name = "orthoverse_seed:creep"})
			table.remove(cands, i)
			n = n + 1
		end
		meta:set_int("n", n)
		return false
	end,
})

------------------------------------------------------------------------------
-- The Heart: shell, core, and the beat

node("shell", S("The Heart's shell (opens when three ganglia are cut)"), {tiles = {tex("shell")}, groups = growth()})
node("core", S("The Heart's core (opens when its last nodule bursts)"), {tiles = {tex("heart")}, light_source = 6,
	paramtype = "light", groups = growth({orthoverse_timer = 1}),
	on_construct = function(pos) core.get_node_timer(pos):start(1.1) end,
	on_timer = function(pos)
		-- only the lowest, westmost, southmost block of the core beats
		for _, dd in ipairs({{-1, 0, 0}, {0, -1, 0}, {0, 0, -1}}) do
			if core.get_node(vector.offset(pos, dd[1], dd[2], dd[3])).name == "orthoverse_seed:core" then return false end
		end
		local _, _, run = adventure(pos)
		if run then sound("heartbeat", pos, 1.0, 40) end
		return true
	end,
})

local function open_nodes(def, names, effect)
	local p1, p2 = area(def)
	local list = core.find_nodes_in_area(p1, p2, names)
	in_steps(list, 200, function(p)
		core.remove_node(p)
		if effect and math.random(3) == 1 then burn_effect(p) end
	end)
	return #list
end

-- A ganglion was cut (orthoverse_monsters calls this when one dies)
function orthoverse.seed.ganglion_cut(pos)
	local key, def, run = adventure(pos)
	if not run then return end
	local data = run_data(run)
	data.ganglia = data.ganglia + 1
	sound("wither", pos, 0.6, 64)
	for n in pairs(run.members) do
		local p = core.get_player_by_name(n)
		if p then core.sound_play("orthoverse_seed_heartbeat", {to_player = n, gain = 0.8, pitch = 0.7}, true) end
	end
	if data.ganglia == 3 then
		open_nodes(def, {"orthoverse_seed:shell"}, true)
		tell_members(run, S("The whole growth shudders, and somewhere below something tears open."))
	else
		tell_members(run, S("The growth shudders."))
	end
end

-- The growth withers to ash, the monsters of the growth fall
local function wither(def)
	local p1, p2 = area(def)
	local names = {}
	for n in pairs(WITHER) do names[#names + 1] = n end
	local list = core.find_nodes_in_area(p1, p2, names)
	table.sort(list, function(a, b) return a.y > b.y end)
	in_steps(list, 400, function(p)
		local to = WITHER[core.get_node(p).name]
		if to == "air" then core.remove_node(p) elseif to then core.swap_node(p, {name = to}) end
	end)
	for _, obj in ipairs(core.get_objects_in_area(p1, vector.offset(p2, 1, 1, 1))) do
		local ent = obj:get_luaentity()
		if ent and ent._seed_growth then
			local p = obj:get_pos()
			core.add_particlespawner({amount = 16, time = 0.3, pos = vector.offset(p, 0, 0.5, 0), radius = 0.5,
				vel = {min = {x = -0.5, y = -1, z = -0.5}, max = {x = 0.5, y = 0.5, z = 0.5}}, exptime = {min = 0.6, max = 1.2},
				size = {min = 1, max = 3}, texture = tex("ash")})
			obj:remove()
		end
	end
end
orthoverse.seed.wither = wither

-- A nodule of the Heart burst (orthoverse_monsters): if it was the last, the
-- core opens and the growth withers
function orthoverse.seed.nodule_burst(pos, self_obj)
	local key, def, run = adventure(pos)
	if not run then return end
	local data = run_data(run)
	if data.dead then return end
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 24)) do
		local ent = obj:get_luaentity()
		if obj ~= self_obj and ent and ent.name == "orthoverse_monsters:nodule" and ent.state ~= "die" and (ent.health or 0) > 0 then
			return
		end
	end
	-- (and none still to come: a nodule's spawner that has not woken this run)
	for _, sp in ipairs(core.find_nodes_in_area(vector.offset(pos, -24, -8, -24), vector.offset(pos, 24, 8, 24),
			{"orthoverse_monsters:spawner"})) do
		local meta = core.get_meta(sp)
		if meta:get_string("kind") == "orthoverse_monsters:nodule" and meta:get_string("run") ~= "run:" .. run.started then
			return
		end
	end
	data.dead = true
	local n = open_nodes(def, {"orthoverse_seed:core"}, true)
	core.log("action", "[orthoverse_seed] the Heart of " .. key .. " died: " .. n .. " blocks of its core opened")
	sound("wither", pos, 1.0, 96)
	tell_members(run, S("The Heart bursts. All round you the growth greys and crumbles."))
	core.after(1.5, function() wither(def) end)
end

------------------------------------------------------------------------------
-- Things that hurt monsters: fire and plasma. A blow as orthoverse_combat
-- deals one (orthoverse_monsters takes it from there: damage, experience).

local FIRE = {id = "fire_pot", kind = "burn", desc = "fire"}
local PLASMA = {id = "plasma_rifle", kind = "burn", desc = "plasma"}

local function hit(obj, player, weapon, dmg, text)
	local ent = obj:get_luaentity()
	if not (ent and ent._orthoverse_target and ent._on_blow) then return false end
	local ac = ent._orthoverse_target.ac or 10
	dmg = math.max(1, math.floor(dmg - math.max(0, ac - 12) * 0.5 + 0.5))
	ent._on_blow(ent, {attacker = player, weapon = weapon, damage = dmg, result = "hit", zone = "body", side = "front",
		strength = 1, text = text .. " " .. dmg, distance = 1})
	return true
end
orthoverse.seed.hit = hit

------------------------------------------------------------------------------
-- Fire pots: thrown (left click), they burst into flame where they land

core.register_craftitem("orthoverse_seed:fire_pot", {
	description = S("Fire pot") .. "\n" .. S("Throw it (left click): it bursts into flame where it lands"),
	inventory_image = tex("fire_pot"),
	stack_max = 6,
	groups = {orthoverse_kit = 1},
	on_use = function(itemstack, user)
		if not user or not user:is_player() then return end
		local props = user:get_properties()
		local eye = vector.offset(user:get_pos(), 0, props.eye_height or 1.47, 0)
		local dir = user:get_look_dir()
		local obj = core.add_entity(vector.add(eye, vector.multiply(dir, 0.6)), "orthoverse_seed:fire_pot_thrown")
		if obj then
			obj:set_velocity(vector.add(vector.multiply(dir, 13), {x = 0, y = 2, z = 0}))
			obj:set_acceleration({x = 0, y = -9.8, z = 0})
			obj:get_luaentity()._owner = user
		end
		itemstack:take_item()
		return itemstack
	end,
})

local function fire_burst(pos, owner)
	sound("burn", pos, 0.9, 24)
	core.add_particlespawner({amount = 40, time = 0.6, pos = {min = vector.offset(pos, -1, -0.5, -1), max = vector.offset(pos, 1, 1, 1)},
		vel = {min = {x = -0.5, y = 0.5, z = -0.5}, max = {x = 0.5, y = 2.5, z = 0.5}}, exptime = {min = 0.5, max = 1.2},
		size = {min = 2, max = 5}, texture = tex("flame"), glow = 14})
	orthoverse.seed.burn(pos, 1.6, owner)
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 2.2)) do
		if not obj:is_player() then hit(obj, owner, FIRE, 6 + math.random(0, 3), S("Fire")) end
	end
end

core.register_entity("orthoverse_seed:fire_pot_thrown", {
	initial_properties = {
		visual = "sprite", textures = {tex("fire_pot")}, visual_size = {x = 0.4, y = 0.4},
		physical = true, collide_with_objects = false, pointable = false,
		collisionbox = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15}, static_save = false, glow = 8,
	},
	on_activate = function(self) self._t = 0 end,
	on_step = function(self, dtime, moveresult)
		self._t = self._t + dtime
		local pos = self.object:get_pos()
		if not pos then return end
		local burst = self._t > 4 or (moveresult and moveresult.collides)
		if not burst then
			for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.9)) do
				local e = obj:get_luaentity()
				if e and e._orthoverse_target then burst = true break end
			end
			local nd = core.registered_nodes[core.get_node(pos).name]
			if nd and (nd.liquidtype ~= "none" or (nd.groups or {}).seed_burnable) then burst = true end
		end
		if burst then
			fire_burst(pos, self._owner)
			self.object:remove()
		end
	end,
})

------------------------------------------------------------------------------
-- The plasma rifle: twelve shots to a charge, one a second

local SHOTS, SHOT_EVERY = 12, 0.9
local SHOT_WEAR = math.ceil(65535 / SHOTS)
local EMPTY = 65535 - 1   -- a tool is lost at full wear: an empty rifle stops short of it
local last_shot = {}

core.register_tool("orthoverse_seed:plasma_rifle", {
	description = S("Plasma rifle") .. "\n" .. S("Left click to fire. Twelve shots to a charge: renewed at the rifle rack"),
	inventory_image = tex("rifle"),
	wield_scale = {x = 1.6, y = 1.6, z = 1},
	groups = {orthoverse_kit = 1},
	on_use = function(itemstack, user)
		if not user or not user:is_player() then return end
		local name = user:get_player_name()
		local t = now()
		if last_shot[name] and t - last_shot[name] < SHOT_EVERY then return end
		last_shot[name] = t
		local pos = user:get_pos()
		if not in_run(user) and not core.check_player_privs(name, {protection_bypass = true}) then
			core.chat_send_player(name, S("The rifle's cell will not wake out here."))
			return
		end
		if itemstack:get_wear() >= EMPTY then
			sound("click", pos, 0.6, 8)
			core.chat_send_player(name, S("The rifle is spent: the rack at the camp renews its charge."))
			return
		end
		local props = user:get_properties()
		local eye = vector.offset(pos, 0, props.eye_height or 1.47, 0)
		local dir = user:get_look_dir()
		local obj = core.add_entity(vector.add(eye, vector.multiply(dir, 0.8)), "orthoverse_seed:plasma")
		if obj then
			obj:set_velocity(vector.multiply(dir, 24))
			obj:get_luaentity()._owner = user
		end
		sound("plasma_fire", eye, 0.6, 24)
		itemstack:set_wear(math.min(EMPTY, itemstack:get_wear() + SHOT_WEAR))
		return itemstack
	end,
})

core.register_on_leaveplayer(function(player) last_shot[player:get_player_name()] = nil end)

core.register_entity("orthoverse_seed:plasma", {
	initial_properties = {
		visual = "sprite", textures = {tex("plasma")}, visual_size = {x = 0.5, y = 0.5}, glow = 14,
		physical = true, collide_with_objects = false, pointable = false,
		collisionbox = {-0.1, -0.1, -0.1, 0.1, 0.1, 0.1}, static_save = false,
	},
	on_activate = function(self) self._t = 0 end,
	on_step = function(self, dtime, moveresult)
		self._t = self._t + dtime
		local pos = self.object:get_pos()
		if not pos then return end
		local done = self._t > 1.6 or (moveresult and moveresult.collides)
		if not done then
			-- it flies more than a body's width in a step: the whole way since
			-- the last one is tested against each monster's box
			local from = self._last or pos
			self._last = pos
			local seg = vector.subtract(pos, from)
			local len2 = vector.dot(seg, seg)
			for _, obj in ipairs(core.get_objects_inside_radius(pos, 3.5)) do
				local ent = not obj:is_player() and obj:get_luaentity()
				if ent and ent._orthoverse_target then
					local op = obj:get_pos()
					local cb = obj:get_properties().collisionbox
					local mid = vector.offset(op, (cb[1] + cb[4]) / 2, (cb[2] + cb[5]) / 2, (cb[3] + cb[6]) / 2)
					local k = len2 > 0 and math.max(0, math.min(1, vector.dot(vector.subtract(mid, from), seg) / len2)) or 1
					local c = vector.add(from, vector.multiply(seg, k))
					if c.x > op.x + cb[1] - 0.15 and c.x < op.x + cb[4] + 0.15 and c.y > op.y + cb[2] - 0.15
							and c.y < op.y + cb[5] + 0.15 and c.z > op.z + cb[3] - 0.15 and c.z < op.z + cb[6] + 0.15
							and hit(obj, self._owner, PLASMA, 4 + math.random(0, 4), S("Plasma")) then
						done = true
						pos = c
						break
					end
				end
			end
		end
		if not done then
			local nd = core.registered_nodes[core.get_node(pos).name]
			if nd and (nd.groups or {}).seed_burnable then done = true end
		end
		if done then
			sound("plasma_hit", pos, 0.6, 20)
			core.add_particlespawner({amount = 12, time = 0.15, pos = pos, radius = 0.2,
				vel = {min = {x = -2, y = -1, z = -2}, max = {x = 2, y = 2, z = 2}}, exptime = {min = 0.2, max = 0.5},
				size = {min = 1, max = 2}, texture = tex("plasma"), glow = 14})
			orthoverse.seed.burn(pos, 0.6, self._owner)
			self.object:remove()
		end
	end,
})

------------------------------------------------------------------------------
-- The survey camp: stores and the rifle rack

local function give(player, item)
	local left = player:get_inventory():add_item("main", item)
	if not left:is_empty() then core.add_item(player:get_pos(), left) end
end

node("stores", S("Survey stores (three fire pots and a breathing mask, once a run)"), {
	tiles = {tex("stores")}, paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.wood,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local key, _, run = adventure(pos)
		if not run then
			if builder(name, key) then core.chat_send_player(name, S("In a run, each player takes three fire pots and a mask here, once.")) end
			return
		end
		if not run.members[name] then return end
		local data = run_data(run)
		if data.gear[name] then
			core.chat_send_player(name, S("You have had your share of the stores."))
			return
		end
		data.gear[name] = true
		give(clicker, "orthoverse_seed:fire_pot 3")
		give(clicker, "orthoverse_seed:mask")
		sound("click", pos, 0.5, 8)
	end,
})

node("rack", S("Rifle rack (a plasma rifle, once a run; renews its charge)"), {
	tiles = {"orthoverse_seed_rack.png^[transformR90", "orthoverse_seed_rack.png^[transformR90", tex("rack")},
	paramtype2 = "facedir", groups = {cracky = 2}, sounds = SND.metal, light_source = 3, paramtype = "light",
	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local key, _, run = adventure(pos)
		if not run then
			if builder(name, key) then core.chat_send_player(name, S("In a run, each player takes a plasma rifle here, once, and renews its charge.")) end
			return
		end
		if not run.members[name] then return end
		local inv = clicker:get_inventory()
		for i, stack in ipairs(inv:get_list("main") or {}) do
			if stack:get_name() == "orthoverse_seed:plasma_rifle" then
				if stack:get_wear() > 0 then
					stack:set_wear(0)
					inv:set_stack("main", i, stack)
					sound("magnet", pos, 0.5, 10)
					core.chat_send_player(name, S("The rifle's cell hums: twelve shots."))
				end
				return
			end
		end
		local data = run_data(run)
		if data.rifles[name] then
			core.chat_send_player(name, S("The rack holds no more rifles for you."))
			return
		end
		data.rifles[name] = true
		give(clicker, "orthoverse_seed:plasma_rifle")
		sound("click", pos, 0.5, 8)
	end,
})

------------------------------------------------------------------------------
-- The crane

local RAIL, TROLLEY, CABLE = "orthoverse_seed:rail", "orthoverse_seed:trolley", "orthoverse_seed:cable"
local MAGNET, MAGNET_ON, CONTAINER = "orthoverse_seed:magnet", "orthoverse_seed:magnet_on", "orthoverse_seed:container"
local CABLE_MAX = 14

node("rail", S("Crane rail"), {tiles = {tex("rail"), tex("rail"), tex("rail") .. "^[transformR90"}, groups = {cracky = 1},
	sounds = SND.metal})
node("trolley", S("Crane trolley (hangs under a rail; buttons within 24 drive it)"), {tiles = {tex("trolley")},
	groups = {cracky = 1}, sounds = SND.metal})
local CABLE_BOX = {type = "fixed", fixed = {-0.06, -0.5, -0.06, 0.06, 0.5, 0.06}}
node("cable", S("Crane cable"), {drawtype = "nodebox", node_box = CABLE_BOX, selection_box = CABLE_BOX,
	tiles = {tex("cable")}, use_texture_alpha = "clip", paramtype = "light", sunlight_propagates = true,
	walkable = false, groups = {cracky = 1}, sounds = SND.metal})
node("magnet", S("Crane magnet"), {tiles = {tex("magnet_top"), tex("magnet"), tex("magnet")}, groups = {cracky = 1},
	sounds = SND.metal})
node("magnet_on", S("Crane magnet (on)"), {tiles = {tex("magnet_top"), tex("magnet_on"), tex("magnet_on")},
	groups = {cracky = 1, not_in_creative_inventory = 1}, sounds = SND.metal, light_source = 5, paramtype = "light"})
node("container", S("Cargo container (the crane's magnet lifts it)"), {
	tiles = {tex("container_top"), tex("container_top"), tex("container")}, groups = {cracky = 1}, sounds = SND.metal})

local busy = {}   -- trolley position -> time of the last move

local function is(p, name) return core.get_node(p).name == name end

-- The crane nearest `pos`: its trolley, the way its rail runs, its cable and
-- magnet, and the container the magnet holds (if it is on, with one below it)
local function find_crane(pos)
	local list = core.find_nodes_in_area(vector.offset(pos, -24, -12, -24), vector.offset(pos, 24, 16, 24), {TROLLEY})
	table.sort(list, function(a, b) return vector.distance(a, pos) < vector.distance(b, pos) end)
	local T = list[1]
	if not T then return end
	local axis
	if is(vector.offset(T, 1, 1, 0), RAIL) or is(vector.offset(T, -1, 1, 0), RAIL) then axis = vector.new(1, 0, 0)
	else axis = vector.new(0, 0, 1) end
	local cables, M = {}, nil
	local p = vector.offset(T, 0, -1, 0)
	for _ = 1, CABLE_MAX + 1 do
		local n = core.get_node(p).name
		if n == CABLE then cables[#cables + 1] = p
		elseif n == MAGNET or n == MAGNET_ON then M = p break
		else break end
		p = vector.offset(p, 0, -1, 0)
	end
	if not M then return end
	local held = {}
	if is(M, MAGNET_ON) and is(vector.offset(M, 0, -1, 0), CONTAINER) then
		local todo, seen = {vector.offset(M, 0, -1, 0)}, {}
		while #todo > 0 and #held < 64 do
			local q = table.remove(todo)
			local k = core.pos_to_string(q)
			if not seen[k] and is(q, CONTAINER) then
				seen[k] = true
				held[#held + 1] = q
				for _, dd in ipairs({{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) do
					todo[#todo + 1] = vector.offset(q, dd[1], dd[2], dd[3])
				end
			end
		end
	end
	return {T = T, axis = axis, cables = cables, M = M, held = held}
end

-- Is a player (or a monster) in the way at p?
local function occupied(p)
	for _, obj in ipairs(core.get_objects_inside_radius(p, 1.3)) do
		local op = obj:get_pos()
		local ent = obj:get_luaentity()
		if obj:is_player() or (ent and ent._orthoverse_target) then
			if math.abs(op.x - p.x) < 0.8 and math.abs(op.z - p.z) < 0.8 and op.y > p.y - 1.8 and op.y < p.y + 0.5 then
				return true
			end
		end
	end
	return false
end

-- Move the blocks `from` (list of positions) by `delta`; refuses (false) if
-- any place they go is neither air nor one of them
local function shift(from, delta)
	local moving = {}
	for _, p in ipairs(from) do moving[core.pos_to_string(p)] = true end
	local nodes = {}
	for i, p in ipairs(from) do
		local q = vector.add(p, delta)
		if not moving[core.pos_to_string(q)] then
			if core.get_node(q).name ~= "air" or occupied(q) then return false end
		end
		nodes[i] = core.get_node(p)
	end
	for _, p in ipairs(from) do core.set_node(p, {name = "air"}) end
	for i, p in ipairs(from) do core.set_node(vector.add(p, delta), nodes[i]) end
	return true
end

-- A dropped container falls until something holds it up
local function fall(blocks, n)
	n = n or 0
	if n > 24 or #blocks == 0 then return end
	local delta = vector.new(0, -1, 0)
	local moved = shift(blocks, delta)
	if moved then
		for i, p in ipairs(blocks) do blocks[i] = vector.add(p, delta) end
		core.after(0.08, function() fall(blocks, n + 1) end)
	elseif n > 0 then
		sound("clank", blocks[1], 1.0, 32)
	end
end

local function crane_act(pos, what, player)
	local c = find_crane(pos)
	if not c then return end
	local k = core.pos_to_string(c.T)
	local t = now()
	if busy[k] and t - busy[k] < 0.25 then return end
	busy[k] = t
	local all = {c.T}
	for _, p in ipairs(c.cables) do all[#all + 1] = p end
	all[#all + 1] = c.M
	for _, p in ipairs(c.held) do all[#all + 1] = p end
	local ok = true
	if what == "left" or what == "right" then
		-- left and right as the player at the buttons sees them
		local yaw = player and player:get_look_horizontal() or 0
		local right = vector.new(math.cos(yaw), 0, math.sin(yaw))
		local sgn = vector.dot(right, c.axis) >= 0 and 1 or -1
		if what == "left" then sgn = -sgn end
		local delta = vector.multiply(c.axis, sgn)
		if not is(vector.add(vector.offset(c.T, 0, 1, 0), delta), RAIL) then ok = false
		else ok = shift(all, delta) end
	elseif what == "up" then
		if #c.cables == 0 then ok = false
		else
			-- the magnet (and what it holds) rises into the lowest length of cable
			local low = c.cables[#c.cables]
			local load = {c.M}
			for _, p in ipairs(c.held) do load[#load + 1] = p end
			core.set_node(low, {name = "air"})
			ok = shift(load, vector.new(0, 1, 0))
			if not ok then core.set_node(low, {name = CABLE}) end
		end
	elseif what == "down" then
		if #c.cables >= CABLE_MAX then ok = false
		else
			local load = {c.M}
			for _, p in ipairs(c.held) do load[#load + 1] = p end
			local mname = core.get_node(c.M).name
			ok = shift(load, vector.new(0, -1, 0))
			if ok then core.set_node(c.M, {name = CABLE}); core.set_node(vector.offset(c.M, 0, -1, 0), {name = mname}) end
		end
	elseif what == "magnet" then
		if is(c.M, MAGNET) then
			core.swap_node(c.M, {name = MAGNET_ON})
			sound("magnet", c.M, 0.7, 24)
			if is(vector.offset(c.M, 0, -1, 0), CONTAINER) then sound("clank", c.M, 0.8, 24) end
		else
			core.swap_node(c.M, {name = MAGNET})
			sound("click", c.M, 0.5, 16)
			fall(c.held)
		end
		return
	end
	if ok then sound("crane", c.T, 0.6, 24) else sound("clank", c.T, 0.5, 20) end
end
orthoverse.seed.crane_act = crane_act

for _, what in ipairs({"left", "right", "up", "down", "magnet"}) do
	node("button_" .. what, S("Crane button (@1)", what), {
		tiles = {tex("button_magnet") .. "^[colorize:#40444c:255", tex("button_magnet") .. "^[colorize:#40444c:255",
			tex("button_magnet") .. "^[colorize:#40444c:255", tex("button_magnet") .. "^[colorize:#40444c:255",
			tex("button_magnet") .. "^[colorize:#40444c:255", tex("button_" .. what)},
		paramtype2 = "facedir", groups = {cracky = 1}, sounds = SND.metal, light_source = 3, paramtype = "light",
		on_rightclick = function(pos, node, clicker)
			if not may_change(pos, clicker) then return end
			sound("click", pos, 0.4, 8)
			crane_act(pos, what, clicker)
		end,
		on_punch = function(pos, node, puncher)
			if not may_change(pos, puncher) then return end
			sound("click", pos, 0.4, 8)
			crane_act(pos, what, puncher)
		end,
	})
end

------------------------------------------------------------------------------
-- Each second: acid wears armour, creep slows, pads sink under feet, spores fade

local tick = 0
core.register_globalstep(function(dtime)
	tick = tick + dtime
	local t = now()
	for name, s in pairs(spored) do
		if t > s.till then
			local p = core.get_player_by_name(name)
			if p then p:hud_remove(s.hud) end
			spored[name] = nil
		end
	end
	if tick < 0.25 then return end
	local whole = math.floor((t * 4) % 4) == 0   -- once a second, near enough
	tick = 0
	for _, player in ipairs(core.get_connected_players()) do
		local pos = player:get_pos()
		local feet = vector.round(vector.offset(pos, 0, 0.1, 0))
		local fname = core.get_node(feet).name
		local under = vector.round(vector.offset(pos, 0, -0.2, 0))
		local uname = core.get_node(under).name
		if uname == "orthoverse_seed:pad" then
			local timer = core.get_node_timer(under)
			if not timer:is_started() then timer:start(1.2) end
		end
		if fname == "orthoverse_seed:creep" and orthoverse.combat and orthoverse.combat.hamper then
			orthoverse.combat.hamper(player, 0.6, 0.4)
		end
		if whole and (fname == "orthoverse_seed:acid" or fname == "orthoverse_seed:pad_sunk") and orthoverse.armor
				and orthoverse.armor.wear then
			orthoverse.armor.wear(player, 1)
		end
	end
end)

------------------------------------------------------------------------------
-- Runs: one valve of each set opens as a run begins

core.register_on_mods_loaded(function()
	local m = orthoverse.monsters
	if m and m.on_wake then table.insert(m.on_wake, function(pos) hatch(pos) end) end
	local ad = orthoverse.adventure
	if not (ad and ad.on_enter) then return end
	table.insert(ad.on_enter, function(player, key, def, run)
		if run.seed then return end
		run_data(run)
		open_valves(def)
	end)
end)
