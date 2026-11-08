-- orthoverse_monsters: the adventure monsters, on Mobs Redo (mods/mobs).
--
-- Classic D&D: kobolds, goblins, orcs, skeletons, plus three from
-- esp32-s3-minetest (mosslings, hexers, wisps). All but the wisp are skins on
-- Luanti's character model, painted by tools/monsters/make_monster_skins.py.
--
-- Monsters only exist in adventures: none spawn in the world by themselves.
-- A builder places Monster spawners (Creative tab) and sets what each brings;
-- a spawner wakes once per run, when a player of the run comes near. A
-- monster that leaves its adventure's dungeon area, or outlives its run, is
-- removed (the restore after a run removes them all anyway).
--
-- Fighting them is orthoverse_combat's hold-and-release: ordinary punches do
-- nothing. In return they wind up before they strike (the punch animation and
-- a swing sound): step back out of reach and the blow misses.

local S = core.get_translator and core.get_translator("orthoverse_monsters") or function(s) return s end

orthoverse = orthoverse or {}
orthoverse.monsters = {}

local function now() return core.get_us_time() / 1e6 end

-- Mobs Redo's "peaceful_player" privilege makes monsters ignore a player. The
-- server admin gets every privilege, so monsters would ignore the admin, who
-- builds and tests the adventures: not given to the admin automatically.
-- And other code that sets privileges can store it in the admin's record, so
-- it is taken away on joining too: nobody here is meant to have it.
core.register_on_mods_loaded(function()
	local p = core.registered_privileges.peaceful_player
	if p then p.give_to_admin = false; p.give_to_singleplayer = false end
end)
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	if privs.peaceful_player then
		privs.peaceful_player = nil
		core.set_player_privs(name, privs)
	end
end)

local ANIM = {   -- character.b3d
	speed_normal = 30, speed_run = 40,
	stand_start = 0, stand_end = 79, walk_start = 168, walk_end = 187,
	run_start = 168, run_end = 187, punch_start = 189, punch_end = 198,
	die_start = 162, die_end = 166, die_speed = 15, die_loop = false,
}

------------------------------------------------------------------------------
-- What a monster holds: a weapon drawn in its right hand

core.register_entity("orthoverse_monsters:held", {
	initial_properties = {
		visual = "wielditem", wield_item = "air", visual_size = {x = 0.25, y = 0.25},
		physical = false, pointable = false, static_save = false,
	},
	on_step = function(self)
		if not self.object:get_attach() then self.object:remove() end
	end,
})

local function hold(self)
	if not self._weapon or self._held then return end
	local pos = self.object:get_pos()
	if not pos then return end
	local obj = core.add_entity(pos, "orthoverse_monsters:held")
	if not obj then return end
	obj:set_properties({wield_item = self._weapon})
	obj:set_attach(self.object, "Arm_Right", {x = 0, y = 5.5, z = 3}, {x = -90, y = 225, z = 90})
	self._held = obj
end

------------------------------------------------------------------------------
-- Labels over a monster for a moment (the blow it took)

local function label(self, text, colour)
	self.object:set_properties({nametag = text, nametag_color = colour or "#efe6d0"})
	self._label_until = now() + 1.5
end

------------------------------------------------------------------------------
-- Wind-up: the monster raises its arm, then strikes if its target is still
-- within reach

local function begin_windup(self)
	if self._windup or not self.attack then return false end
	self._windup = now() + (self._windup_time or 0.5)
	self.object:set_animation({x = ANIM.punch_start, y = ANIM.punch_end}, 6, 0, false)
	core.sound_play(self._windup_sound or "mobs_swing", {object = self.object, gain = 0.6, max_hear_distance = 12}, true)
	return false   -- not now: see finish_windup
end

local function finish_windup(self)
	local target = self.attack
	self._windup = nil
	if not target or not target:get_pos() then return end
	local s, p = self.object:get_pos(), target:get_pos()
	if not s then return end
	local dist = vector.distance({x = s.x, y = 0, z = s.z}, {x = p.x, y = 0, z = p.z})
	if dist > (self.reach or 2) + 0.6 or math.abs(s.y - p.y) > 2 then
		core.sound_play("mobs_swing", {object = self.object, gain = 0.3, pitch = 0.8, max_hear_distance = 8}, true)
		return
	end
	self.object:set_animation({x = ANIM.punch_start, y = ANIM.punch_end}, 30, 0, false)
	local dir = vector.normalize(vector.subtract(p, s))
	target:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, dir)
	if target:is_player() then
		target:add_velocity({x = dir.x * 1.5, y = 1, z = dir.z * 1.5})
	end
end

------------------------------------------------------------------------------
-- Blows from orthoverse_combat

local function on_blow(self, blow)
	if self.state == "die" then return end
	if blow.result == "miss" then
		label(self, blow.text, "#a09a90")
		return
	end
	self.health = self.health - blow.damage
	local a = blow.attacker
	if a and a:get_pos() then
		local dir = vector.normalize(vector.subtract(self.object:get_pos(), a:get_pos()))
		local push = blow.weapon.kind == "bash" and 4 or 2
		self.object:add_velocity({x = dir.x * push, y = 1.5, z = dir.z * push})
		self.pause_timer = blow.stun or 0.25
		if blow.stun then self._windup = nil end
		if not self.attack and a:is_player() then self:do_attack(a) end
	end
	self:check_for_death({type = "punch", puncher = a})
	if self.state ~= "die" then
		label(self, blow.text, blow.sweet and "#f5c64a" or "#efe6d0")
	end
end

------------------------------------------------------------------------------
-- Staying in the adventure

local function in_place(self)
	local pos = self.object:get_pos()
	if not pos then return false end
	if self._free then return true end   -- brought by the admin outside any adventure
	local ad = orthoverse.adventure
	if not ad then return true end
	local key, def = ad.at(pos)
	if not key then return false end
	if self._adventure and self._adventure ~= key then return false end
	if def.open and self._run and (not ad.runs[key] or ("run:" .. ad.runs[key].started) ~= self._run) then
		return false
	end
	return true
end

------------------------------------------------------------------------------
-- Registering a monster

local kinds = {}     -- name -> description, in the order registered
orthoverse.monsters.kinds = kinds

local function monster(id, def)
	local name = "orthoverse_monsters:" .. id
	local size = def.size or 1
	local mesh = def.visual ~= "sprite"
	local base = {
		type = "monster", passive = false, attack_type = def.attack_type or "dogfight",
		damage = def.damage, hp_min = def.hp, hp_max = def.hp, armor = 100,
		reach = def.reach or 2, view_range = def.view_range or 14,
		walk_velocity = def.walk or 1.5, run_velocity = def.run or 3.2, jump = true, jump_height = 4,
		stepheight = 1.1, fear_height = 4, water_damage = 0, lava_damage = 8, light_damage = 0,
		fall_damage = true, makes_footstep_sound = mesh, pathfinding = 1,
		punch_interval = def.interval or 1.5,
		drops = {},
		sounds = def.sounds or {},
		visual = mesh and "mesh" or "sprite", mesh = mesh and "character.b3d" or nil,
		textures = {{"orthoverse_monsters_" .. id .. ".png"}},
		visual_size = {x = size, y = size},
		collisionbox = def.collisionbox or {-0.3 * size, 0, -0.3 * size, 0.3 * size, 1.7 * size, 0.3 * size},
		animation = mesh and ANIM or nil,
		glow = def.glow,
		use_texture_alpha = def.alpha,
		backface_culling = not def.alpha,
		custom_attack = (def.attack_type or "dogfight") == "dogfight" and begin_windup or nil,
		do_punch = function() return false end,   -- only hold-and-release blows hurt
		after_activate = function(self)
			self._weapon = def.weapon
			core.after(0.1, function() if self.object:get_pos() then hold(self) end end)
		end,
		do_custom = function(self, dtime)
			local t = now()
			if self._windup and t >= self._windup then finish_windup(self) end
			if self._label_until and t > self._label_until then
				self._label_until = nil
				self.object:set_properties({nametag = ""})
			end
			self._check = (self._check or 0) + dtime
			if self._check > 2 then
				self._check = 0
				if not in_place(self) then self.object:remove(); return false end
			end
			if def.do_custom then return def.do_custom(self, dtime) end
		end,
	}
	for k, v in pairs(def.mobs or {}) do base[k] = v end
	mobs:register_mob(name, base)
	local ent = core.registered_entities[name]
	ent._orthoverse_target = {ac = def.ac or 10}
	ent._on_blow = on_blow
	ent._windup_time = def.windup
	kinds[#kinds + 1] = {name = name, id = id, desc = def.desc}
end

monster("kobold", {
	desc = S("Kobold"), size = 0.6, hp = 7, ac = 12, damage = 2, windup = 0.4, interval = 1.2,
	walk = 1.8, run = 3.8, weapon = "orthoverse_combat:dagger",
	sounds = {random = "orthoverse_monsters_mossling_chatter", damage = "orthoverse_monsters_mossling_hurt",
		death = "orthoverse_monsters_mossling_death", distance = 12},
})
monster("goblin", {
	desc = S("Goblin"), size = 0.65, hp = 9, ac = 13, damage = 3, windup = 0.45, interval = 1.3,
	walk = 1.7, run = 3.6, weapon = "orthoverse_combat:spear", reach = 2.4,
	sounds = {random = "orthoverse_monsters_mossling_call", damage = "orthoverse_monsters_mossling_hurt",
		death = "orthoverse_monsters_mossling_death", distance = 14},
})
monster("orc", {
	desc = S("Orc"), size = 1.12, hp = 18, ac = 13, damage = 5, windup = 0.65, interval = 1.8,
	walk = 1.4, run = 3.0, weapon = "orthoverse_combat:war_hammer", reach = 2.3,
	sounds = {random = "orthoverse_monsters_hexer_hiss", damage = "orthoverse_monsters_hexer_hurt",
		death = "orthoverse_monsters_hexer_death", distance = 16},
})
monster("skeleton", {
	desc = S("Skeleton"), size = 1.0, hp = 13, ac = 13, damage = 4, windup = 0.5, interval = 1.5,
	walk = 1.3, run = 2.8, weapon = "orthoverse_combat:short_sword", alpha = true,
	sounds = {damage = "default_dig_cracky", death = "default_dug_node", distance = 12},
})
monster("mossling", {
	desc = S("Mossling"), size = 0.55, hp = 10, ac = 11, damage = 2, windup = 0.4, interval = 1.5,
	walk = 1.6, run = 3.4,
	sounds = {random = "orthoverse_monsters_mossling_chatter", attack = "orthoverse_monsters_mossling_swipe",
		damage = "orthoverse_monsters_mossling_hurt", death = "orthoverse_monsters_mossling_death", distance = 12},
})

-- The hexer keeps its distance and lobs slow orbs
mobs:register_arrow("orthoverse_monsters:hexer_orb", {
	visual = "sprite", visual_size = {x = 0.5, y = 0.5}, textures = {"orthoverse_monsters_hexer_orb.png"},
	velocity = 6, glow = 12,
	hit_player = function(self, player)
		player:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 4}}, nil)
		core.sound_play("orthoverse_monsters_hexer_impact", {pos = player:get_pos(), gain = 0.6}, true)
	end,
	hit_mob = function() end,
	hit_node = function(self, pos)
		core.sound_play("orthoverse_monsters_hexer_impact", {pos = pos, gain = 0.4}, true)
	end,
})
monster("hexer", {
	desc = S("Hexer"), size = 1.0, hp = 16, ac = 12, damage = 4, attack_type = "shoot",
	walk = 1.0, run = 1.8, view_range = 18,
	mobs = {arrow = "orthoverse_monsters:hexer_orb", shoot_interval = 3.5, shoot_offset = 1.2},
	sounds = {random = "orthoverse_monsters_hexer_mutter", shoot_attack = "orthoverse_monsters_hexer_cast",
		damage = "orthoverse_monsters_hexer_hurt", death = "orthoverse_monsters_hexer_death", distance = 16},
})

-- The wisp drifts up, swells and bursts (it breaks nothing on a land)
monster("wisp", {
	desc = S("Wisp"), visual = "sprite", size = 0.9, hp = 20, ac = 11, damage = 12, attack_type = "explode",
	glow = 14, collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3}, walk = 1.2, run = 2.6,
	mobs = {fly = true, fly_in = {"air"}, explosion_radius = 2, explosion_damage_radius = 4, explosion_timer = 1.5,
		allow_fuse_reset = true, stop_to_explode = true, fall_damage = false, jump = false},
	sounds = {random = "orthoverse_monsters_wisp_hum", fuse = "orthoverse_monsters_wisp_whine",
		explode = "tnt_explode", distance = 16},
})

------------------------------------------------------------------------------
-- The monster spawner: a grate in the floor, set by the builder

local SPAWNER = "orthoverse_monsters:spawner"

local function may_set(name, pos)
	return core.check_player_privs(name, {protection_bypass = true}) or not core.is_protected(pos, name)
end

local function spawner_formspec(pos)
	local meta = core.get_meta(pos)
	local list, sel = {}, 1
	for i, k in ipairs(kinds) do
		list[#list + 1] = core.formspec_escape(k.desc)
		if k.name == meta:get_string("kind") then sel = i end
	end
	local spos = pos.x .. "," .. pos.y .. "," .. pos.z
	return table.concat({
		"formspec_version[4]size[8,6.2]",
		"label[0.4,0.6;", S("Monster spawner"), "]",
		"label[0.4,1.3;", S("Brings, once per run, when a player of the run comes near:"), "]",
		"dropdown[0.4,1.7;3.6,0.8;kind;", table.concat(list, ","), ";", sel, ";true]",
		"field[4.3,1.7;1.4,0.8;count;", S("How many"), ";", meta:get_int("count") > 0 and meta:get_int("count") or 1, "]",
		"field[6.0,1.7;1.6,0.8;wake;", S("Wakes within"), ";", meta:get_int("wake") > 0 and meta:get_int("wake") or 10, "]",
		"textarea[0.4,2.9;7.2,1.4;;;", core.formspec_escape(S("Up to 6 at a time; wakes within 4 to 24 blocks. " ..
			"While the adventure is closed it brings nothing by itself: use Bring now to try it.")), "]",
		"button_exit[0.4,4.7;3.4,0.9;save;", S("Save"), "]",
		"button_exit[4.2,4.7;3.4,0.9;test;", S("Bring now"), "]",
	}), spos
end

local function spawn_at(pos, kind, count, run_id, key)
	local spawned = 0
	for _ = 1, count * 6 do
		if spawned >= count then break end
		local p = vector.add(pos, {x = math.random(-2, 2), y = 1, z = math.random(-2, 2)})
		local a, b = core.get_node(p), core.get_node(vector.add(p, {x = 0, y = 1, z = 0}))
		local da, db = core.registered_nodes[a.name], core.registered_nodes[b.name]
		if da and db and not da.walkable and not db.walkable and da.liquidtype == "none" then
			local obj = core.add_entity(vector.add(p, {x = 0, y = -0.45, z = 0}), kind)
			local ent = obj and obj:get_luaentity()
			if ent then
				ent._adventure, ent._run = key, run_id
				spawned = spawned + 1
			end
		end
	end
	return spawned
end

core.register_node(SPAWNER, {
	description = S("Monster spawner") .. "\n" .. S("Brings monsters in an adventure, once per run"),
	tiles = {"default_stone_block.png^xpanes_bar.png^[colorize:#200810:60", "default_stone_block.png", "default_stone_block.png"},
	groups = {cracky = 2},
	sounds = default and default.node_sound_stone_defaults(),
	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("kind", kinds[1].name)
		meta:set_int("count", 2)
		meta:set_int("wake", 10)
		meta:set_string("infotext", S("Monster spawner"))
		core.get_node_timer(pos):start(1)
	end,
	on_rightclick = function(pos, node, clicker)
		local name = clicker and clicker:get_player_name() or ""
		if not may_set(name, pos) then return end
		local fs = spawner_formspec(pos)
		core.show_formspec(name, "orthoverse_monsters:spawner_" .. core.pos_to_string(pos), fs)
	end,
	on_timer = function(pos)
		local ad = orthoverse.adventure
		if not ad then return true end
		local key, def = ad.at(pos)
		local run = key and ad.runs[key]
		if not def or not def.open or not run then return true end
		local meta = core.get_meta(pos)
		local id = "run:" .. run.started
		if meta:get_string("run") == id then return true end
		local wake = math.max(4, math.min(24, meta:get_int("wake")))
		for _, obj in ipairs(core.get_objects_inside_radius(pos, wake)) do
			if obj:is_player() and run.members[obj:get_player_name()] then
				meta:set_string("run", id)
				spawn_at(pos, meta:get_string("kind"), math.max(1, math.min(6, meta:get_int("count"))), id, key)
				break
			end
		end
		return true
	end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	local spos = formname:match("^orthoverse_monsters:spawner_(.+)$")
	if not spos then return end
	local pos = core.string_to_pos(spos)
	local name = player:get_player_name()
	if not pos or core.get_node(pos).name ~= SPAWNER or not may_set(name, pos) then return true end
	local meta = core.get_meta(pos)
	local i = tonumber(fields.kind)
	if i and kinds[i] then meta:set_string("kind", kinds[i].name) end
	if fields.count then meta:set_int("count", math.max(1, math.min(6, tonumber(fields.count) or 1))) end
	if fields.wake then meta:set_int("wake", math.max(4, math.min(24, tonumber(fields.wake) or 10))) end
	local kind = meta:get_string("kind")
	local desc = kind
	for _, k in ipairs(kinds) do if k.name == kind then desc = k.desc end end
	meta:set_string("infotext", S("Monster spawner") .. ": " .. meta:get_int("count") .. " × " .. desc)
	if fields.test then
		local key = orthoverse.adventure and orthoverse.adventure.at(pos)
		local n = spawn_at(pos, kind, meta:get_int("count"), nil, key)
		core.chat_send_player(name, ("Brought %d. /adventure reset clears them."):format(n))
	end
	return true
end)

------------------------------------------------------------------------------
-- Admin: /monster <kind> brings one in front of you, to look at or fight

core.register_chatcommand("monster", {
	params = "<kobold|goblin|orc|skeleton|mossling|hexer|wisp>",
	description = "Bring a monster in front of you (admin)",
	privs = {server = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false end
		local kind = "orthoverse_monsters:" .. (param ~= "" and param or "goblin")
		if not core.registered_entities[kind] then return false, "No such monster." end
		local pos = vector.add(player:get_pos(), vector.multiply(player:get_look_dir(), 4))
		pos.y = player:get_pos().y + 0.5
		local key = orthoverse.adventure and orthoverse.adventure.at(pos)
		local obj = core.add_entity(pos, kind)
		local ent = obj and obj:get_luaentity()
		if ent then ent._adventure, ent._free = key, not key end
		return true, "Brought a " .. param .. "."
	end,
})
