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
	self._fought = now()
	self.object:set_animation({x = ANIM.punch_start, y = ANIM.punch_end}, 30, 0, false)
	local dir = vector.normalize(vector.subtract(p, s))
	target:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, dir)
	if target:is_player() then
		target:add_velocity({x = dir.x * 1.5, y = 1, z = dir.z * 1.5})
	end
end

------------------------------------------------------------------------------
-- Choosing whom to fight. Mobs Redo keeps a monster on the first player it
-- picks until it loses them; ours turn to a player who comes clearly nearer
-- (by two blocks or more) and can be seen, and to one who strikes them from
-- no further away than their target, so a party's fight spreads out.

local function can_fight(self, p)
	return p and p:is_player() and p:get_hp() > 0
		and not core.check_player_privs(p:get_player_name(), "peaceful_player")
end

local function sees(self, p)
	local pos = self.object:get_pos()
	local cb = self.object:get_properties().collisionbox
	return core.line_of_sight(vector.add(pos, {x = 0, y = cb[5] * 0.9, z = 0}),
		vector.add(p:get_pos(), {x = 0, y = 1.4, z = 0}))
end

local function retarget(self)
	if self.state ~= "attack" or not self.attack or not self.attack:get_pos() then return end
	local pos = self.object:get_pos()
	local dcur = vector.distance(pos, self.attack:get_pos())
	local best, bd
	for _, p in ipairs(core.get_connected_players()) do
		if p ~= self.attack and can_fight(self, p) then
			local d = vector.distance(pos, p:get_pos())
			if d <= (self.view_range or 14) and (not bd or d < bd) and sees(self, p) then best, bd = p, d end
		end
	end
	if best and bd + 2 <= dcur then
		self._windup = nil
		self:do_attack(best, true)
	end
end

local function struck_by(self, a)
	if not can_fight(self, a) or a == self.attack then return end
	local pos = self.object:get_pos()
	local cur = self.attack and self.attack:get_pos()
	if not cur or vector.distance(pos, a:get_pos()) <= vector.distance(pos, cur) then
		self._windup = nil
		self:do_attack(a, true)
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
		if self._hx then self._hx.stagger = blow.stun or 0.5 end
		struck_by(self, a)
	end
	self:check_for_death({type = "punch", puncher = a})
	if self.state == "die" and orthoverse.rank and a then orthoverse.rank.killed(self, a) end
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
	local mesh = def.visual == nil or def.visual == "mesh"
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
		visual = mesh and "mesh" or def.visual, mesh = mesh and "character.b3d" or nil,
		textures = {def.textures or {"orthoverse_monsters_" .. id .. ".png"}},
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
			if def.after_activate then def.after_activate(self) end
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
				retarget(self)
				-- Close to its target and able to see them counts as fighting
				-- (for experience: a monster that cannot reach anyone gives none)
				local a = self.attack
				if self.state == "attack" and a and a:get_pos()
						and vector.distance(a:get_pos(), self.object:get_pos()) <= (self.reach or 2) + 3 and sees(self, a) then
					self._fought = now()
				end
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
	ent._level, ent._xp, ent._desc = def.level or 1, def.xp or 0, def.desc
	kinds[#kinds + 1] = {name = name, id = id, desc = def.desc}
end

monster("kobold", {
	desc = S("Kobold"), level = 1, xp = 25, size = 0.6, hp = 10, ac = 12, damage = 2, windup = 0.4, interval = 1.2,
	walk = 1.8, run = 3.8, weapon = "orthoverse_combat:dagger_steel_carried",
	sounds = {random = "orthoverse_monsters_mossling_chatter", damage = "orthoverse_monsters_mossling_hurt",
		death = "orthoverse_monsters_mossling_death", distance = 12},
})
monster("goblin", {
	desc = S("Goblin"), level = 2, xp = 50, size = 0.65, hp = 13, ac = 13, damage = 3, windup = 0.45, interval = 1.3,
	walk = 1.7, run = 3.6, weapon = "orthoverse_combat:spear_steel_carried", reach = 2.4,
	sounds = {random = "orthoverse_monsters_mossling_call", damage = "orthoverse_monsters_mossling_hurt",
		death = "orthoverse_monsters_mossling_death", distance = 14},
})
monster("orc", {
	desc = S("Orc"), level = 4, xp = 100, size = 1.12, hp = 26, ac = 13, damage = 5, windup = 0.65, interval = 1.8,
	walk = 1.4, run = 3.0, weapon = "orthoverse_combat:morning_star_steel_carried", reach = 2.3,
	sounds = {random = "orthoverse_monsters_hexer_hiss", damage = "orthoverse_monsters_hexer_hurt",
		death = "orthoverse_monsters_hexer_death", distance = 16},
})
-- The warlord: a great orc in a gold crown, the boss of The Gullet. Slow to
-- wind up, and it hurts.
monster("warlord", {
	desc = S("Orc warlord"), level = 5, xp = 300, size = 1.35, hp = 70, ac = 14, damage = 7, windup = 0.85, interval = 2.0,
	walk = 1.3, run = 2.8, weapon = "orthoverse_combat:war_hammer_bronze_carried", reach = 2.7, view_range = 18,
	sounds = {random = "orthoverse_monsters_hexer_hiss", damage = "orthoverse_monsters_hexer_hurt",
		death = "orthoverse_monsters_hexer_death", distance = 24},
})
monster("skeleton", {
	desc = S("Skeleton"), level = 3, xp = 75, size = 1.0, hp = 18, ac = 13, damage = 4, windup = 0.5, interval = 1.5,
	walk = 1.3, run = 2.8, weapon = "orthoverse_combat:short_sword_bronze_carried", alpha = true,
	sounds = {damage = "default_dig_cracky", death = "default_dug_node", distance = 12},
})
monster("mossling", {
	desc = S("Mossling"), level = 1, xp = 25, size = 0.55, hp = 10, ac = 11, damage = 2, windup = 0.4, interval = 1.5,
	walk = 1.6, run = 3.4,
	sounds = {random = "orthoverse_monsters_mossling_chatter", attack = "orthoverse_monsters_mossling_swipe",
		damage = "orthoverse_monsters_mossling_hurt", death = "orthoverse_monsters_mossling_death", distance = 12},
})

------------------------------------------------------------------------------
-- The hexer (as in esp32-s3-minetest): once it sees a player it keeps its
-- distance, 4.5 to 14 blocks, standing watching them; every four seconds or
-- so, while it can see them, it casts: still for a moment, it draws the life
-- from the ground at its feet and lobs a slow glowing orb at them in an arc,
-- watches it half the way, then moves a few blocks round them to cast from
-- somewhere else. A player who stays within 4 blocks for a moment (it
-- shimmers first: the moment to strike) it blinks away from, at most every
-- 8 s. A blow staggers it: it stands, unable to cast or blink, for half a
-- second (a second for a stunning blow). It moves slowly and stately, hurrying only to back
-- away; its body turns the way it goes and its head keeps its eyes on them.

local HEX = {
	keep = {4.5, 14}, channel = 0.75, blink_near = 4, blink_delay = 0.75, blink_every = 8, goal_time = 4,
	cast_every = 4, view = 20, lose = 24, lose_unseen = 5, think = 0.25,
	orb_speed = 7, orb_gravity = 4, orb_damage = 4, head_max = math.rad(70),
}

core.register_entity("orthoverse_monsters:hex_orb", {
	initial_properties = {
		visual = "sprite", textures = {"orthoverse_monsters_hexer_orb.png"}, visual_size = {x = 0.6, y = 0.6},
		glow = 14, physical = true, collide_with_objects = false, pointable = true,
		collisionbox = {-0.2, -0.2, -0.2, 0.2, 0.2, 0.2}, selectionbox = {-0.25, -0.25, -0.25, 0.25, 0.25, 0.25},
		static_save = false,
	},
	_orthoverse_target = {ac = 1},
	_burst = function(self, pos)
		pos = pos or self.object:get_pos()
		if self._hum then core.sound_stop(self._hum) end
		if pos then
			core.sound_play("orthoverse_monsters_hexer_impact", {pos = pos, gain = 0.7, max_hear_distance = 24}, true)
			core.add_particlespawner({amount = 14, time = 0.15, pos = pos, radius = 0.2,
				vel = {min = {x = -2, y = -1, z = -2}, max = {x = 2, y = 2, z = 2}}, exptime = {min = 0.3, max = 0.7},
				size = {min = 1, max = 2.5}, texture = "orthoverse_monsters_hexer_orb.png", glow = 12})
		end
		self.object:remove()
	end,
	_on_blow = function(self, blow)   -- it can be struck out of the air
		if blow.result ~= "miss" then self:_burst() end
	end,
	on_activate = function(self)
		self._t = 0
		self._hum = core.sound_play("orthoverse_monsters_hexer_orb", {object = self.object, gain = 0.35,
			max_hear_distance = 14, loop = true})
	end,
	on_deactivate = function(self) if self._hum then core.sound_stop(self._hum) end end,
	on_punch = function() return true end,
	on_step = function(self, dtime, moveresult)
		self._t = self._t + dtime
		local pos = self.object:get_pos()
		if not pos then return end
		if self._t > 6 then return self:_burst(pos) end
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.2)) do
			if obj:is_player() then
				local p = obj:get_pos()
				if math.abs(p.x - pos.x) < 0.6 and math.abs(p.z - pos.z) < 0.6 and pos.y > p.y - 0.2 and pos.y < p.y + 1.9 then
					obj:punch(self._owner and self._owner:get_pos() and self._owner or self.object, 1.0,
						{full_punch_interval = 1.0, damage_groups = {fleshy = HEX.orb_damage}}, nil)
					return self:_burst(pos)
				end
			end
		end
		if moveresult and moveresult.collides then return self:_burst(pos) end
		local node = core.registered_nodes[core.get_node(pos).name]
		if node and node.liquidtype ~= "none" then return self:_burst(pos) end
	end,
})

-- Velocity for an orb from `from` to land on `to`: across at orb_speed, in an
-- arc under orb_gravity
local function orb_velocity(from, to)
	local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
	local across = math.sqrt(dx * dx + dz * dz)
	local time = math.max(0.3, across / HEX.orb_speed)
	local vy = (dy + 0.5 * HEX.orb_gravity * time * time) / time
	return {x = dx / time, y = math.max(-10, math.min(12, vy)), z = dz / time}, time
end

-- The ground at its feet dies (inside an adventure only): grass and litter to
-- dirt, flowers and grasses to dry shrubs. The restore after the run puts it back.
local DRAIN = {["default:dirt_with_grass"] = "default:dirt", ["default:dirt_with_dry_grass"] = "default:dirt",
	["default:dirt_with_rainforest_litter"] = "default:dirt", ["default:dirt_with_coniferous_litter"] = "default:dirt"}
local function drain(self, pos)
	if not self._adventure then return end
	local feet = vector.round(pos)
	for _, p in ipairs(core.find_nodes_in_area(vector.subtract(feet, {x = 2, y = 1, z = 2}),
			vector.add(feet, {x = 2, y = 0, z = 2}), {"group:soil", "group:flora", "group:grass"})) do
		if vector.distance(p, feet) <= 2.3 and math.random(3) > 1 then
			local name = core.get_node(p).name
			if DRAIN[name] then core.set_node(p, {name = DRAIN[name]})
			elseif core.get_item_group(name, "flora") > 0 or core.get_item_group(name, "grass") > 0 then
				core.set_node(p, {name = "default:dry_shrub"})
			end
		end
	end
	core.add_particlespawner({amount = 20, time = 0.6, pos = {min = vector.add(pos, {x = -1.5, y = 0, z = -1.5}),
		max = vector.add(pos, {x = 1.5, y = 0.2, z = 1.5})}, vel = {min = {x = 0, y = 0.6, z = 0}, max = {x = 0, y = 1.4, z = 0}},
		exptime = {min = 0.6, max = 1.2}, size = {min = 0.8, max = 1.6}, texture = "orthoverse_monsters_hexer_orb.png^[multiply:#402050"})
end

-- A free spot to stand on near x, z (the ground within a few blocks of y)
local function stand_at(x, y, z)
	for dy = 3, -4, -1 do
		local f = {x = x, y = y + dy - 1, z = z}
		local below = core.registered_nodes[core.get_node(f).name]
		local a = core.registered_nodes[core.get_node({x = x, y = f.y + 1, z = z}).name]
		local b = core.registered_nodes[core.get_node({x = x, y = f.y + 2, z = z}).name]
		if below and below.walkable and a and not a.walkable and a.liquidtype == "none"
				and b and not b.walkable then
			return {x = x, y = f.y + 0.5, z = z}
		end
	end
end

-- Where it blinks to: 4 to 8 blocks away from the player, on the ground,
-- still in its adventure
local function blink_spot(self, pos, from)
	local base = math.atan2(pos.z - from.z, pos.x - from.x)
	for _ = 1, 10 do
		local a = base + math.rad(math.random(-90, 90))
		local r = math.random(4, 8)
		local spot = stand_at(math.floor(pos.x + math.cos(a) * r + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + math.sin(a) * r + 0.5))
		if spot and (not self._adventure or orthoverse.adventure.at(spot) == self._adventure)
				and core.line_of_sight(vector.add(pos, {x = 0, y = 1.5, z = 0}), vector.add(spot, {x = 0, y = 1.5, z = 0})) then
			return spot
		end
	end
end

-- A new place to cast from: a few blocks (1.5 to 3) round the player from
-- where it is, at 8 to 11 blocks
local function new_ground(pos, p, dist)
	local now_a = math.atan2(pos.z - p.z, pos.x - p.x)
	local r = (dist < HEX.keep[1] or dist > HEX.keep[2]) and math.random(8, 11) or math.max(8, math.min(11, dist))
	local turn = math.random(15, 30) / 10 / r * (math.random(2) == 1 and 1 or -1)
	return {x = p.x + math.cos(now_a + turn) * r, y = pos.y, z = p.z + math.sin(now_a + turn) * r}
end

local function eye(obj) return vector.add(obj:get_pos(), {x = 0, y = 1.5, z = 0}) end

local function sees(self, player)
	return core.line_of_sight(eye(self.object), eye(player))
end

-- Turn the head to look at `p` (as far as it turns: 70 degrees either way)
local function look_at(self, p)
	local pos = self.object:get_pos()
	local want = p and math.atan2(-(p.x - pos.x), p.z - pos.z) or nil
	local turn = 0
	if want then
		turn = (want - self.object:get_yaw() + math.pi) % (2 * math.pi) - math.pi
		turn = math.max(-HEX.head_max, math.min(HEX.head_max, turn))
	end
	if math.abs(turn - (self._head or 0)) > 0.1 then
		self._head = turn
		self.object:set_bone_override("Head", {rotation = {vec = {x = 0, y = turn, z = 0}, interpolation = 0.2, absolute = false}})
	end
end

local function hexer_think(self)
	local pos = self.object:get_pos()
	local h = self._hx
	h.cooldown = math.max(0, h.cooldown - HEX.think)
	h.fuse = math.max(0, h.fuse - HEX.think)
	-- the player it is after: still there and in sight, or the nearest it can see
	local p = h.target and core.get_player_by_name(h.target)
	if p and (p:get_hp() <= 0 or vector.distance(p:get_pos(), pos) > HEX.lose) then p = nil end
	if p then
		if sees(self, p) then h.unseen = 0 else h.unseen = h.unseen + HEX.think end
		if h.unseen > HEX.lose_unseen then p = nil end
	end
	if not p and self.attack and self.attack:is_player() then p = self.attack end
	if not p then
		h.target = nil
		local best, bd
		for _, obj in ipairs(core.get_objects_inside_radius(pos, HEX.view)) do
			if obj:is_player() and obj:get_hp() > 0 then
				local d = vector.distance(obj:get_pos(), pos)
				if (not bd or d < bd) and sees(self, obj) then best, bd = obj, d end
			end
		end
		if best then
			p = best
			h.cooldown = math.max(h.cooldown, 1)
			core.sound_play("orthoverse_monsters_hexer_hiss", {object = self.object, gain = 1, max_hear_distance = 32}, true)
		end
	end
	self.attack = nil
	if not p then
		-- wandering, muttering
		h.target, h.goal, h.watch, h.swing = nil, nil, 0, 0
		look_at(self, nil)
		h.wander = h.wander - HEX.think
		if h.wander <= 0 then
			h.wander = math.random(3, 8)
			if math.random(2) == 1 then
				self:set_velocity(0); self:set_animation("stand")
			else
				self:set_yaw(math.random() * 2 * math.pi, 8)
				self:set_velocity(self.walk_velocity); self:set_animation("walk")
			end
		end
		return
	end
	h.target = p:get_player_name()
	local pp = p:get_pos()
	local dist = vector.distance({x = pp.x, y = 0, z = pp.z}, {x = pos.x, y = 0, z = pos.z})
	local function face_player()
		self:yaw_to_pos(pp)
		self:set_velocity(0)
	end
	if dist < HEX.blink_near then
		h.near = (h.near or 0) + HEX.think
		if h.near <= HEX.think and h.fuse <= 0 then
			-- it gathers itself to blink: a shimmer, the moment to strike
			core.add_particlespawner({amount = 16, time = HEX.blink_delay, pos = {min = vector.add(pos, {x = -0.4, y = 0, z = -0.4}),
				max = vector.add(pos, {x = 0.4, y = 1.8, z = 0.4})}, vel = {min = {x = 0, y = 0.3, z = 0}, max = {x = 0, y = 0.8, z = 0}},
				exptime = {min = 0.3, max = 0.6}, size = {min = 1, max = 2}, glow = 12,
				texture = "orthoverse_monsters_hexer_orb.png"})
		end
	else
		h.near = 0
	end
	if (h.stagger or 0) > 0 then
		-- staggered by a blow: no casting, no blinking
		h.stagger = h.stagger - HEX.think
		h.swing, h.near = 0, 0
		self:yaw_to_pos(pp)
		self:set_animation("stand")
	elseif h.swing > 0 then
		-- casting: still, facing them
		face_player()
		h.swing = h.swing - HEX.think
		if h.swing <= 0 then
			local yaw = self.object:get_yaw()
			local from = vector.add(pos, {x = -math.sin(yaw) * 0.5, y = 1.5, z = math.cos(yaw) * 0.5})
			local v, time = orb_velocity(from, vector.add(pp, {x = 0, y = 1, z = 0}))
			local orb = core.add_entity(from, "orthoverse_monsters:hex_orb")
			if orb then
				orb:set_velocity(v)
				orb:set_acceleration({x = 0, y = -HEX.orb_gravity, z = 0})
				local e = orb:get_luaentity()
				if e then e._owner = self.object end
			end
			drain(self, pos)
			self._fought = now()
			h.cooldown = HEX.cast_every + math.random(0, 10) / 10
			h.watch = time / 2
			self:set_animation("stand")
		end
	elseif h.near >= HEX.blink_delay and h.fuse <= 0 then
		-- too close: it blinks away
		local spot = blink_spot(self, pos, pp)
		if spot then
			core.add_particlespawner({amount = 24, time = 0.2, pos = {min = vector.add(pos, {x = -0.4, y = 0, z = -0.4}),
				max = vector.add(pos, {x = 0.4, y = 1.8, z = 0.4})}, vel = {min = {x = -0.5, y = 0.2, z = -0.5}, max = {x = 0.5, y = 1, z = 0.5}},
				exptime = {min = 0.5, max = 1.2}, size = {min = 2, max = 4}, texture = "tnt_smoke.png"})
			self.object:set_pos(spot)
			self.object:set_velocity({x = 0, y = 0, z = 0})
			core.sound_play("orthoverse_monsters_hexer_blink", {pos = spot, gain = 1, max_hear_distance = 24}, true)
			h.fuse, h.watch, h.goal = HEX.blink_every, 0, nil
			h.cooldown = math.min(h.cooldown, 0.5)
		end
	elseif h.watch > 0 then
		-- watching its orb go
		face_player()
		h.watch = h.watch - HEX.think
		if h.watch <= 0 then h.goal, h.goal_t = new_ground(pos, pp, dist), HEX.goal_time end
	elseif h.goal then
		-- on to a new place to cast from
		h.goal_t = h.goal_t - HEX.think
		local gd = vector.distance({x = h.goal.x, y = 0, z = h.goal.z}, {x = pos.x, y = 0, z = pos.z})
		if gd < 0.6 or h.goal_t <= 0 then
			h.goal = nil
			face_player()
			self:set_animation("stand")
		else
			local fast = dist < HEX.keep[1]
			self:yaw_to_pos(h.goal)
			self:set_velocity(fast and self.run_velocity or self.walk_velocity)
			self:set_animation(fast and "run" or "walk")
		end
	elseif dist < HEX.keep[1] or dist > HEX.keep[2] then
		h.goal, h.goal_t = new_ground(pos, pp, dist), HEX.goal_time
	elseif h.cooldown <= 0 and h.unseen == 0 then
		h.swing = HEX.channel
		face_player()
		self.object:set_animation({x = ANIM.punch_start, y = ANIM.punch_end}, 8, 0, true)
		core.sound_play("orthoverse_monsters_hexer_cast", {object = self.object, gain = 1, max_hear_distance = 32}, true)
	else
		-- standing, watching them, until it can cast again
		face_player()
		self:set_animation("stand")
	end
	look_at(self, pp)
end

monster("hexer", {
	desc = S("Hexer"), level = 4, xp = 120, size = 1.0, hp = 20, ac = 12, damage = 4,
	walk = 1.0, run = 2.6, view_range = HEX.view,
	sounds = {random = "orthoverse_monsters_hexer_mutter", damage = "orthoverse_monsters_hexer_hurt",
		death = "orthoverse_monsters_hexer_death", distance = 16},
	do_custom = function(self, dtime)
		self._hx = self._hx or {cooldown = 0, fuse = 0, watch = 0, swing = 0, unseen = 0, wander = 0, think = 0}
		local h = self._hx
		h.think = h.think + dtime
		if h.think >= HEX.think then
			h.think = 0
			hexer_think(self)
		end
		return false   -- the hexer's own mind, not Mobs Redo's
	end,
})

-- The wisp floats: it hovers a man's height above the ground, bobbing, and
-- comes down to a player's chest height when it goes for them. Its picture is
-- eight frames of a flicker (as in esp32-s3-minetest). Close to a player it
-- swells and bursts like a small TNT blast: it hurts everyone near (up to
-- about eight hearts at arm's length) but breaks nothing.

local WISP_HOVER, WISP_BOB = 1.6, 0.25

local function ground_below(pos, down)
	for d = 0, down do
		local def = core.registered_nodes[core.get_node({x = pos.x, y = math.floor(pos.y + 0.5) - d, z = pos.z}).name]
		if not def or def.walkable ~= false then return math.floor(pos.y + 0.5) - d + 0.5 end
	end
end

-- Mobs Redo's blast hurts by making each thing near punch itself, which the
-- engine ignores for players while PvP is off. So our monsters' blasts hurt
-- players here, like a TNT blast: up to 16 health points (8 hearts) at a
-- block away, less further out, nothing beyond the damage radius, with a
-- push away from the blast. Nodes are never broken (mobs_griefing is off).
local mobs_boom = mobs.boom
function mobs:boom(mob, pos, node_radius, entity_radius, texture)
	mobs_boom(self, mob, pos, node_radius, entity_radius, texture)
	if not (pos and mob and mob.name and mob.name:find("^orthoverse_monsters:")) then return end
	local r = entity_radius or (node_radius or 1) * 2
	for _, player in ipairs(core.get_connected_players()) do
		local pp = vector.add(player:get_pos(), {x = 0, y = 1, z = 0})
		local d = vector.distance(pos, pp)
		if d <= r and player:get_hp() > 0 then
			local dmg = math.floor(math.min(16, 4 / math.max(1, d) * r))
			player:set_hp(player:get_hp() - dmg, {type = "set_hp", from = "mod", orthoverse_blast = mob.name})
			local dir = vector.normalize(vector.subtract(pp, pos))
			player:add_velocity({x = dir.x * 6, y = 3, z = dir.z * 6})
		end
	end
end

monster("wisp", {
	desc = S("Wisp"), level = 3, xp = 75, visual = "sprite", size = 0.9, hp = 20, ac = 11, damage = 12, attack_type = "explode",
	glow = 14, collisionbox = {-0.35, -0.35, -0.35, 0.35, 0.35, 0.35}, walk = 1.2, run = 2.6,
	mobs = {fly = true, fly_in = {"air"}, keep_flying = true, explosion_radius = 2, explosion_damage_radius = 4,
		explosion_timer = 1.5, allow_fuse_reset = true, stop_to_explode = true, fall_damage = false, jump = false,
		fear_height = 0, stand_chance = 0},
	sounds = {random = "orthoverse_monsters_wisp_hum", fuse = "orthoverse_monsters_wisp_whine",
		explode = "tnt_explode", distance = 16},
	after_activate = function(self)
		self.object:set_properties({spritediv = {x = 1, y = 8}, initial_sprite_basepos = {x = 0, y = 0}})
		self.object:set_sprite({x = 0, y = 0}, 8, 0.1, false)
		self.object:set_acceleration({x = 0, y = 0, z = 0})
		self._bob = math.random() * 6
	end,
	do_custom = function(self, dtime)
		local pos = self.object:get_pos()
		if not pos or self.state == "die" then return end
		self._bob = (self._bob or 0) + dtime
		if self.v_start then self._fought = now() end
		local want
		local target = self.attack and self.attack:get_pos()
		if target then
			want = target.y + 1.1
		else
			local g = ground_below(pos, 8)
			want = (g or pos.y) + WISP_HOVER + math.sin(self._bob * 1.7) * WISP_BOB
		end
		local v = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		self.object:set_velocity({x = v.x, y = math.max(-2, math.min(2, (want - pos.y) * 2)), z = v.z})
		self.object:set_acceleration({x = 0, y = 0, z = 0})
	end,
})

------------------------------------------------------------------------------
-- The Fallen Star's robots. Ranks 3 to 7.

-- A scrap drone: a small floating machine that rams (as the wisp floats, but
-- it strikes, it does not burst)
monster("drone", {
	desc = S("Scrap drone"), level = 3, xp = 60, visual = "sprite", size = 0.7, hp = 12, ac = 12, damage = 3,
	windup = 0.4, interval = 1.3, glow = 6, collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3}, walk = 1.6, run = 3.6,
	reach = 1.8,
	mobs = {fly = true, fly_in = {"air"}, keep_flying = true, fall_damage = false, jump = false, fear_height = 0,
		stand_chance = 0},
	sounds = {random = "orthoverse_monsters_wisp_hum", damage = "default_dig_metal", death = "default_dug_metal",
		distance = 14},
	after_activate = function(self)
		self.object:set_acceleration({x = 0, y = 0, z = 0})
		self._bob = math.random() * 6
	end,
	do_custom = function(self, dtime)
		local pos = self.object:get_pos()
		if not pos or self.state == "die" then return end
		self._bob = (self._bob or 0) + dtime
		local want
		local target = self.attack and self.attack:get_pos()
		if target then
			want = target.y + 1.2
		else
			local g = ground_below(pos, 8)
			want = (g or pos.y) + 1.4 + math.sin(self._bob * 2.3) * 0.2
		end
		local v = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		self.object:set_velocity({x = v.x, y = math.max(-2, math.min(2, (want - pos.y) * 2)), z = v.z})
		self.object:set_acceleration({x = 0, y = 0, z = 0})
	end,
})

-- A security robot: a steel man with a stun baton
monster("secbot", {
	desc = S("Security robot"), level = 5, xp = 110, size = 1.05, hp = 24, ac = 14, damage = 5, windup = 0.55,
	interval = 1.5, walk = 1.4, run = 3.2, weapon = "orthoverse_combat:mace_steel_carried", reach = 2.3,
	sounds = {damage = "default_dig_metal", death = "default_dug_metal", attack = "orthoverse_monsters_bolt",
		distance = 14},
})

-- The Warden: the ship's great guardian, the boss of The Fallen Star. Its
-- blows are slow to come and crushing when they do.
monster("warden", {
	desc = S("The Warden"), level = 7, xp = 400, size = 1.5, hp = 100, ac = 15, damage = 9, windup = 1.0,
	interval = 2.2, walk = 1.2, run = 2.7, weapon = "orthoverse_combat:war_hammer_steel_carried", reach = 3.0,
	view_range = 20,
	sounds = {damage = "default_dig_metal", death = "default_dug_metal", attack = "orthoverse_monsters_bolt",
		distance = 28},
})

-- A sentry turret: fixed to a ledge, it turns to face a player it can see and
-- fires a bolt every 2.5 s (the bolt flies straight and can be struck down)
local TURRET = {view = 18, every = 2.5, speed = 12, damage = 4}

core.register_entity("orthoverse_monsters:bolt", {
	initial_properties = {
		visual = "sprite", textures = {"orthoverse_monsters_bolt.png"}, visual_size = {x = 0.4, y = 0.4},
		glow = 14, physical = true, collide_with_objects = false, pointable = true,
		collisionbox = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15}, selectionbox = {-0.2, -0.2, -0.2, 0.2, 0.2, 0.2},
		static_save = false,
	},
	_orthoverse_target = {ac = 1},
	_burst = function(self) self.object:remove() end,
	_on_blow = function(self, blow) if blow.result ~= "miss" then self.object:remove() end end,
	on_activate = function(self) self._t = 0 end,
	on_punch = function() return true end,
	on_step = function(self, dtime, moveresult)
		self._t = self._t + dtime
		local pos = self.object:get_pos()
		if not pos then return end
		-- A bolt flies more than a body's width in a server step: test the
		-- whole way it came since the last step against each player's body
		local from = self._last or pos
		self._last = pos
		local seg = vector.subtract(pos, from)
		local len2 = vector.dot(seg, seg)
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 3)) do
			if obj:is_player() and obj:get_hp() > 0 then
				local p = obj:get_pos()
				local mid = {x = p.x, y = p.y + 0.9, z = p.z}
				local k = len2 > 0 and math.max(0, math.min(1, vector.dot(vector.subtract(mid, from), seg) / len2)) or 1
				local c = vector.add(from, vector.multiply(seg, k))
				if math.abs(c.x - p.x) < 0.45 and math.abs(c.z - p.z) < 0.45 and c.y > p.y - 0.1 and c.y < p.y + 1.9 then
					obj:punch(self._owner and self._owner:get_pos() and self._owner or self.object, 1.0,
						{full_punch_interval = 1.0, damage_groups = {fleshy = TURRET.damage}}, nil)
					return self.object:remove()
				end
			end
		end
		if self._t > 3 or (moveresult and moveresult.collides) then return self.object:remove() end
	end,
})

monster("turret", {
	desc = S("Sentry turret"), level = 5, xp = 90, visual = "cube", size = 0.8, hp = 18, ac = 15, damage = 0,
	textures = {"orthoverse_monsters_turret_top.png", "orthoverse_monsters_turret_top.png",
		"orthoverse_monsters_turret_side.png", "orthoverse_monsters_turret_side.png",
		"orthoverse_monsters_turret_side.png", "orthoverse_monsters_turret_front.png"},
	collisionbox = {-0.4, -0.4, -0.4, 0.4, 0.4, 0.4}, walk = 0, run = 0, view_range = TURRET.view,
	mobs = {jump = false, fear_height = 0, stand_chance = 100, walk_chance = 0, attack_type = "dogfight"},
	sounds = {damage = "default_dig_metal", death = "default_dug_metal", distance = 16},
	do_custom = function(self, dtime)
		local pos = self.object:get_pos()
		if not pos or self.state == "die" then return false end
		self.object:set_velocity({x = 0, y = math.min(0, (self.object:get_velocity() or {y = 0}).y), z = 0})
		self._cool = (self._cool or TURRET.every) - dtime
		self._look = (self._look or 0) - dtime
		if self._look > 0 then return false end
		self._look = 0.25
		local best, bd
		for _, player in ipairs(core.get_connected_players()) do
			local pp = player:get_pos()
			local d = vector.distance(pos, pp)
			if d <= TURRET.view and player:get_hp() > 0 and (not bd or d < bd)
					and core.line_of_sight(pos, vector.add(pp, {x = 0, y = 1.4, z = 0})) then
				best, bd = player, d
			end
		end
		if not best then return false end
		self._fought = now()
		local aim = vector.add(best:get_pos(), {x = 0, y = 1.1, z = 0})
		local dir = vector.direction(pos, aim)
		self.object:set_yaw(math.atan2(-dir.x, dir.z))
		if self._cool <= 0 then
			self._cool = TURRET.every
			local from = vector.add(pos, vector.multiply(dir, 0.6))
			local bolt = core.add_entity(from, "orthoverse_monsters:bolt")
			if bolt then
				bolt:set_velocity(vector.multiply(dir, TURRET.speed))
				bolt:get_luaentity()._owner = self.object
				core.sound_play("orthoverse_monsters_bolt", {pos = pos, gain = 0.7, max_hear_distance = 24}, true)
			end
		end
		return false
	end,
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

-- No more than this many monsters near one spawner, so a spawner clicked
-- again and again (its test button, or a hacked client) cannot flood the
-- server with entities
local NEAR_CAP, NEAR_RADIUS = 30, 32

local function monsters_near(pos)
	local n = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, NEAR_RADIUS)) do
		local ent = obj:get_luaentity()
		if ent and ent.name and ent.name:sub(1, 20) == "orthoverse_monsters:" then n = n + 1 end
	end
	return n
end

local function spawn_at(pos, kind, count, run_id, key)
	if not core.registered_entities[kind] then return 0 end
	count = math.min(count, NEAR_CAP - monsters_near(pos))
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
				ent._adventure, ent._run, ent._spawner = key, run_id, core.pos_to_string(pos)
				spawned = spawned + 1
			end
		end
	end
	return spawned
end

-- A spawner whose timer is not running (set by WorldEdit, or lost) starts it
-- when its block loads
core.register_lbm({
	name = "orthoverse_monsters:spawner_timer",
	nodenames = {SPAWNER},
	run_at_every_load = true,
	action = function(pos)
		if not core.get_node_timer(pos):is_started() then core.get_node_timer(pos):start(1) end
	end,
})

core.register_node(SPAWNER, {
	description = S("Monster spawner") .. "\n" .. S("Brings monsters in an adventure, once per run"),
	tiles = {"default_stone_block.png^xpanes_bar.png^[colorize:#200810:60", "default_stone_block.png", "default_stone_block.png"},
	groups = {cracky = 2, orthoverse_timer = 1},   -- orthoverse_timer: placing a ready-made adventure starts its timer
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
		local n = spawn_at(pos, kind, math.max(1, math.min(6, meta:get_int("count"))), nil, key)
		core.chat_send_player(name, n > 0 and ("Brought %d. /adventure reset clears them."):format(n)
			or "There are enough monsters here already. /adventure reset clears them.")
	end
	return true
end)

------------------------------------------------------------------------------
-- Admin: /monster <kind> brings one in front of you, to look at or fight

core.register_chatcommand("monster", {
	params = "<kobold|goblin|orc|warlord|skeleton|mossling|hexer|wisp>",
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
