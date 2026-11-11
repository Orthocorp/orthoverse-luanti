-- orthoverse_monsters: the adventure monsters, on Mobs Redo (mods/mobs).
--
-- Classic D&D: kobolds, goblins, orcs, skeletons, plus three from
-- esp32-s3-minetest (mosslings, hexers, wisps). All but the wisp are skins on
-- Luanti's character model, painted by tools/monsters/make_monster_skins.py.
-- The adventures add their own: the Mill's, the Fallen Star's robots, and St
-- Morwen's undead (zombies, ghouls, the wight; tools/props/make_st_morwens.py),
-- and The Wyrm Below's goblin cutthroats, deep orcs and the wyrm (its model,
-- skin and sounds from Draconis: LICENSE-wyrm.txt).
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
	if self._on_hit then self._on_hit(self, target, dir) end
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
-- The undead (skeletons, zombies, ghouls, the wight): holy water on a
-- fighter (orthoverse_props' font) makes their blows hurt the undead more;
-- a church bell stuns them; they cannot set foot on consecrated ground
-- (group orthoverse_consecrated).

local HOLY_BONUS = 3
local blessings = {}   -- name -> until

function orthoverse.monsters.bless(player, secs)
	blessings[player:get_player_name()] = now() + secs
end

function orthoverse.monsters.blessed(player)
	if not player.get_player_name then return false end
	local till = blessings[player:get_player_name()]
	return till ~= nil and now() < till
end

core.register_on_leaveplayer(function(player) blessings[player:get_player_name()] = nil end)

-- Every undead within `radius` of `pos` stands stunned for `secs`
function orthoverse.monsters.stun_undead(pos, radius, secs)
	local n = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, radius)) do
		local e = obj:get_luaentity()
		if e and e._undead and e.state ~= "die" then
			e._windup = nil
			e.pause_timer = secs
			obj:set_velocity({x = 0, y = 0, z = 0})
			label(e, S("stunned"), "#b8d8ff")
			n = n + 1
		end
	end
	return n
end

-- Keeping the undead off consecrated ground: back to the last place they
-- stood that was not
local function hallowed(self)
	local pos = self.object:get_pos()
	if not pos then return end
	local cb = self.object:get_properties().collisionbox
	local below = core.get_node({x = pos.x, y = pos.y + cb[2] - 0.7, z = pos.z}).name
	if core.get_item_group(below, "orthoverse_consecrated") > 0 then
		local back = self._unhallowed or vector.offset(pos, 0, 0, -1)
		self.object:set_pos(back)
		self.object:set_velocity({x = 0, y = 0, z = 0})
		self._windup = nil
		if not self._hiss or now() > self._hiss then
			self._hiss = now() + 2
			core.add_particlespawner({amount = 8, time = 0.2, pos = vector.offset(back, 0, 0.3, 0), radius = 0.3,
				vel = {min = {x = -0.5, y = 1, z = -0.5}, max = {x = 0.5, y = 2, z = 0.5}}, exptime = {min = 0.5, max = 1},
				size = {min = 1, max = 2}, texture = "orthoverse_props_fog.png"})
		end
	else
		self._unhallowed = pos
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
	-- Holy water on the striker: the undead take more
	if self._undead and blow.attacker and orthoverse.monsters.blessed(blow.attacker) then
		blow.damage = blow.damage + HOLY_BONUS
		blow.text = (blow.text or "") .. " +" .. HOLY_BONUS .. " holy"
		local pos = self.object:get_pos()
		if pos then
			core.add_particlespawner({amount = 10, time = 0.15, pos = vector.offset(pos, 0, 1, 0), radius = 0.3,
				vel = {min = {x = -1, y = 0.5, z = -1}, max = {x = 1, y = 2, z = 1}}, exptime = {min = 0.3, max = 0.7},
				size = {min = 1, max = 2}, texture = "orthoverse_props_holy_water.png^[colorize:#ffffff:120", glow = 14})
		end
	end
	self.health = self.health - blow.damage
	if self._on_struck then self._on_struck(self, blow) end
	local a = blow.attacker
	if a and a:get_pos() then
		local dir = vector.normalize(vector.subtract(self.object:get_pos(), a:get_pos()))
		-- (a great beast is not knocked back, nor kept from fighting)
		if not self._heavy then
			local push = blow.weapon.kind == "bash" and 4 or 2
			self.object:add_velocity({x = dir.x * push, y = 1.5, z = dir.z * push})
			self.pause_timer = blow.stun or 0.25
			if blow.stun then self._windup = nil end
		end
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
		visual = mesh and "mesh" or def.visual, mesh = mesh and (def.mesh or "character.b3d") or nil,
		textures = {def.textures or {"orthoverse_monsters_" .. id .. ".png"}},
		visual_size = {x = size, y = size},
		collisionbox = def.collisionbox or {-0.3 * size, 0, -0.3 * size, 0.3 * size, 1.7 * size, 0.3 * size},
		selectionbox = def.selectionbox,
		animation = mesh and (def.animation or ANIM) or nil,
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
		do_custom = function(self, dtime, moveresult)
			local t = now()
			if self._windup and t >= self._windup then finish_windup(self) end
			if def.undead then
				self._hal = (self._hal or 0) + dtime
				if self._hal > 0.2 then self._hal = 0; hallowed(self) end
			end
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
			if def.do_custom then return def.do_custom(self, dtime, moveresult) end
		end,
	}
	for k, v in pairs(def.mobs or {}) do base[k] = v end
	mobs:register_mob(name, base)
	local ent = core.registered_entities[name]
	ent._orthoverse_target = {ac = def.ac or 10}
	ent._on_blow = on_blow
	ent._on_struck = def.on_struck
	ent._on_hit = def.on_hit
	ent._undead = def.undead
	ent._heavy = def.heavy
	ent._windup_time = def.windup
	ent._level, ent._xp, ent._desc = def.level or 1, def.xp or 0, def.desc
	kinds[#kinds + 1] = {name = name, id = id, desc = def.desc, great = def.great}
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
	walk = 1.3, run = 2.8, weapon = "orthoverse_combat:short_sword_bronze_carried", alpha = true, undead = true,
	sounds = {damage = "default_dig_cracky", death = "default_dug_node", distance = 12},
})
-- St Morwen's undead.
--
-- The zombie: slow and hard to put down. A blow that lands is a grab: for a
-- moment the player can hardly move.
local function hamper(player, mult, secs, text)
	if not player:is_player() then return end
	if orthoverse.combat and orthoverse.combat.hamper then orthoverse.combat.hamper(player, mult, secs) end
	if text then core.chat_send_player(player:get_player_name(), text) end
end

monster("zombie", {
	desc = S("Zombie"), level = 4, xp = 90, size = 1.0, hp = 30, ac = 10, damage = 4, windup = 0.75, interval = 1.9,
	walk = 0.7, run = 1.7, reach = 2.0, undead = true,
	sounds = {random = "orthoverse_monsters_zombie_groan", damage = "default_dig_crumbly", death = "orthoverse_monsters_zombie_groan",
		distance = 14},
	on_hit = function(self, target)
		hamper(target, 0.15, 0.8, S("The zombie's hands close on you."))
	end,
})

-- The ghoul: quick, in packs, and its claws numb: half speed for two
-- seconds, one blow in three.
monster("ghoul", {
	desc = S("Ghoul"), level = 5, xp = 110, size = 0.95, hp = 22, ac = 13, damage = 3, windup = 0.35, interval = 1.1,
	walk = 1.9, run = 4.0, reach = 1.9, undead = true,
	sounds = {random = "orthoverse_monsters_ghoul_screech", attack = "orthoverse_monsters_ghoul_screech",
		damage = "orthoverse_monsters_mossling_hurt", death = "orthoverse_monsters_ghoul_screech", distance = 16},
	on_hit = function(self, target)
		if math.random(3) == 1 then hamper(target, 0.5, 2, S("A ghoul's claws: your limbs go numb.")) end
	end,
})

-- The wight: St Morwen's dead lord, the boss. Its blows drink life, which
-- heals it; at half its health it calls up two skeletons, once.
local WIGHT_HP = 90
monster("wight", {
	desc = S("The Wight"), level = 8, xp = 500, size = 1.2, hp = WIGHT_HP, ac = 15, damage = 7, windup = 0.8,
	interval = 2.0, walk = 1.3, run = 3.0, weapon = "orthoverse_combat:broadsword_bronze_carried", reach = 2.6,
	view_range = 20, glow = 4, undead = true,
	sounds = {random = "orthoverse_monsters_wight_breath", damage = "default_dig_cracky",
		death = "orthoverse_monsters_wight_breath", distance = 24},
	on_hit = function(self, target)
		self.health = math.min(WIGHT_HP, self.health + self.damage)
		local pos = target:get_pos()
		if pos then
			core.add_particlespawner({amount = 12, time = 0.3, pos = vector.offset(pos, 0, 1, 0), radius = 0.3,
				attract = {kind = "point", strength = 2, origin_attached = self.object, origin = {x = 0, y = 1.5, z = 0}},
				exptime = {min = 0.5, max = 0.9}, size = {min = 1, max = 2},
				texture = "orthoverse_props_fog.png^[colorize:#8fd0ff:160", glow = 10})
		end
		if target:is_player() then core.chat_send_player(target:get_player_name(), S("The wight drinks your life.")) end
	end,
	on_struck = function(self)
		if self._called or self.health > WIGHT_HP / 2 then return end
		self._called = true
		local pos = self.object:get_pos()
		if not pos then return end
		core.sound_play("orthoverse_monsters_wight_breath", {pos = pos, gain = 1, pitch = 0.7, max_hear_distance = 32}, true)
		for _, d in ipairs({{2, 0}, {-2, 0}, {0, 2}, {0, -2}}) do
			local p = vector.offset(pos, d[1], 0.5, d[2])
			local n = core.registered_nodes[core.get_node(p).name]
			if n and not n.walkable and (self._calls or 0) < 2 then
				local obj = core.add_entity(p, "orthoverse_monsters:skeleton")
				local e = obj and obj:get_luaentity()
				if e then
					e._adventure, e._run, e._free = self._adventure, self._run, self._free
					self._calls = (self._calls or 0) + 1
					core.add_particlespawner({amount = 14, time = 0.3, pos = p, radius = 0.4,
						vel = {min = {x = -0.5, y = 0.5, z = -0.5}, max = {x = 0.5, y = 2, z = 0.5}},
						exptime = {min = 0.5, max = 1.2}, size = {min = 2, max = 4}, texture = "orthoverse_props_fog.png"})
				end
			end
		end
		label(self, S("The wight calls its guard!"), "#8fd0ff")
	end,
})
-- The Wyrm Below's tribes, harder than the Gullet's: goblin cutthroats
-- (quick, in packs, poisoned blades that sting for a while) and deep orcs
-- (grey from the dark, heavily armed). Ranks 6 to 12.
monster("cutthroat", {
	desc = S("Goblin cutthroat"), level = 6, xp = 140, size = 0.7, hp = 24, ac = 15, damage = 5, windup = 0.35, interval = 1.1,
	walk = 2.0, run = 4.4, weapon = "orthoverse_combat:dagger_bronze_carried", reach = 2.0,
	textures = {"orthoverse_monsters_goblin.png^[multiply:#b8a0c8"},
	sounds = {random = "orthoverse_monsters_mossling_call", damage = "orthoverse_monsters_mossling_hurt",
		death = "orthoverse_monsters_mossling_death", distance = 14},
	on_hit = function(self, target)
		if math.random(3) == 1 then hamper(target, 0.6, 2, S("The cutthroat's blade stings: your legs drag.")) end
	end,
})
monster("deep_orc", {
	desc = S("Deep orc"), level = 8, xp = 220, size = 1.2, hp = 48, ac = 16, damage = 8, windup = 0.6, interval = 1.7,
	walk = 1.5, run = 3.2, weapon = "orthoverse_combat:war_hammer_bronze_carried", reach = 2.6, view_range = 16,
	textures = {"orthoverse_monsters_orc.png^[multiply:#a4aab4"},
	sounds = {random = "orthoverse_monsters_hexer_hiss", damage = "orthoverse_monsters_hexer_hurt",
		death = "orthoverse_monsters_hexer_death", distance = 18},
})
monster("mossling", {
	desc = S("Mossling"), level = 1, xp = 25, size = 0.55, hp = 10, ac = 11, damage = 2, windup = 0.4, interval = 1.5,
	walk = 1.6, run = 3.4,
	sounds = {random = "orthoverse_monsters_mossling_chatter", attack = "orthoverse_monsters_mossling_swipe",
		damage = "orthoverse_monsters_mossling_hurt", death = "orthoverse_monsters_mossling_death", distance = 12},
})

-- A kobold in a painted skull mask, a sheet with bones painted on it: a
-- skeleton, until struck. Then the mask cracks and it is plainly a kobold
-- (The Mill at Withy Ford's haunting is staged).
monster("masked", {
	desc = S("Skeleton?"), level = 1, xp = 30, size = 0.6, hp = 11, ac = 12, damage = 2, windup = 0.4, interval = 1.2,
	walk = 1.8, run = 3.8, weapon = "orthoverse_combat:dagger_steel_carried",
	sounds = {damage = "orthoverse_monsters_mossling_hurt", death = "orthoverse_monsters_mossling_death", distance = 12},
	on_struck = function(self)
		if self._unmasked then return end
		self._unmasked = true
		self.object:set_properties({textures = {"orthoverse_monsters_kobold.png"}})
		self.textures = {"orthoverse_monsters_kobold.png"}
		self.base_texture = self.textures
		local pos = self.object:get_pos()
		if pos then
			core.add_particlespawner({amount = 12, time = 0.2, pos = vector.offset(pos, 0, 1.1 * 0.6, 0), radius = 0.2,
				vel = {min = {x = -1.5, y = 0, z = -1.5}, max = {x = 1.5, y = 2, z = 1.5}}, exptime = {min = 0.4, max = 0.9},
				size = {min = 1, max = 2}, texture = "default_paper.png^[colorize:#e8e2d0:200"})
			core.sound_play("default_dig_snappy", {pos = pos, gain = 0.8, max_hear_distance = 12}, true)
		end
		self._desc = S("Kobold (unmasked)")
	end,
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

-- The Ringmaster: a hexer in a fine coat who runs the smuggling ring under
-- the mill, the boss of The Mill at Withy Ford. Sturdier than a hexer.
monster("ringmaster", {
	desc = S("The Ringmaster"), level = 5, xp = 300, size = 1.1, hp = 45, ac = 13, damage = 5,
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
-- The wyrm: the dragon of The Wyrm Below, ranks 6 to 12. Its model, skin and
-- sounds are Draconis's fire dragon (by ElCeejo, MIT: LICENSE-wyrm.txt); what
-- it does is ours, and none of Mobs Redo's own behaviour is used.
--
-- It sleeps on its hoard until someone comes near (or strikes it). Then, in
-- turns:
--   * on the ground it walks at the nearest player and slams the ground in
--     front of it (a wind-up, then a blow all round that point), or, when two
--     or more are close, beats its wings to throw them back. This is when it
--     can be struck;
--   * it takes off and hovers out of reach, breathing fireballs in threes
--     (a wind-up each time, and the balls fly straight: step behind a pillar,
--     or strike one down);
--   * and lands again near its target.
-- Below a third of its health it is enraged: shorter turns, quicker fire.
-- It is never knocked back. When it dies it drops the ring (orthoverse_props).

local WYRM = {
	scale = 0.6,             -- of Draconis's full-grown size
	hp = 420, ac = 16, level = 12, xp = 1500,
	wake = 16,               -- a player this near (and seen) wakes it
	view = 30,
	ground = {14, 18}, air = {9, 12},    -- seconds in each turn (enraged: two thirds)
	walk = 2.4, turn = 2.5,  -- blocks a second, radians a second
	reach = 4.5,
	slam = {windup = 0.75, damage = 9, radius = 3.6, ahead = 2.6, every = 2.4},
	repel = {windup = 0.6, damage = 3, radius = 6, push = 11, every = 7},
	breath = {every = 3.4, windup = 0.9, shots = 3, gap = 0.4, speed = 11, damage = 5, radius = 1.6},
	hover = 6,               -- above the floor, ceiling allowing
	enraged = 1 / 3,
	-- The model faces -x with yaw 0 (Luanti's own facing is +z)
	yaw_off = math.pi / 2,
}
local WS = WYRM.scale

-- Draconis's frames, at its speeds
local WA = {
	stand = {1, 59, 20}, stand_fire = {61, 119, 20}, slam = {121, 159, 30}, repel = {161, 209, 30},
	walk = {211, 249, 25}, takeoff = {291, 319, 30}, hover = {321, 359, 30}, hover_fire = {361, 399, 30},
	fly = {401, 439, 30}, land = {481, 509, 30}, sleep = {511, 569, 20}, death = {571, 579, 15},
}
local WA_ONCE = {slam = true, repel = true, takeoff = true, land = true, death = true}

local function wyrm_anim(self, name)
	if self._wa == name then return end
	self._wa = name
	local a = WA[name]
	self.object:set_animation({x = a[1], y = a[2]}, a[3], 0.3, not WA_ONCE[name])
	-- eyes shut in sleep
	self.object:set_properties({textures = {name == "sleep" and "orthoverse_monsters_wyrm.png^orthoverse_monsters_wyrm_shading.png"
		or "orthoverse_monsters_wyrm.png^orthoverse_monsters_wyrm_shading.png^orthoverse_monsters_wyrm_eyes.png"}})
end

local function wyrm_sound(self, name, gain, pitch)
	core.sound_play(name, {object = self.object, gain = gain or 1, pitch = pitch, max_hear_distance = 48}, true)
end

-- Where it faces (Luanti's yaw, with the model's offset taken off)
local function wyrm_fwd(self)
	local yaw = (self.object:get_yaw() or 0) - WYRM.yaw_off
	return {x = -math.sin(yaw), y = 0, z = math.cos(yaw)}
end

local function wyrm_face(self, to, dtime)
	local pos = self.object:get_pos()
	local want = math.atan2(-(to.x - pos.x), to.z - pos.z) + WYRM.yaw_off
	local yaw = self.object:get_yaw() or 0
	local d = (want - yaw + math.pi) % (2 * math.pi) - math.pi
	local step = WYRM.turn * dtime
	self.object:set_yaw(yaw + math.max(-step, math.min(step, d)))
	return math.abs(d)
end

-- The floor under it, and the room over its back
local function solid(p)
	local d = core.registered_nodes[core.get_node(p).name]
	return not d or d.walkable ~= false
end
local function floor_below(pos, down)
	for d = 0, down do
		local p = {x = pos.x, y = math.floor(pos.y + 0.5) - d, z = pos.z}
		if solid(p) then return p.y + 0.5 end
	end
end
local function room_above(pos, up)
	for d = 0, up do
		if solid({x = pos.x, y = math.floor(pos.y + 0.5) + d, z = pos.z}) then return d end
	end
	return up
end

-- Whom it fights: the nearest it can see, kept while it can
local function wyrm_eye(self) return vector.offset(self.object:get_pos(), 0, 2.4 * WS / 0.6, 0) end
local function wyrm_sees(self, p)
	return core.line_of_sight(wyrm_eye(self), vector.offset(p:get_pos(), 0, 1.4, 0))
end
-- It keeps to its lair: nobody further than LEASH from where it woke is
-- fought (it goes home, and sleeps again)
local LEASH = 20
local function far_from_home(self, p)
	local h = self._home
	if not h then return false end
	return vector.distance({x = p.x, y = 0, z = p.z}, {x = h.x, y = 0, z = h.z}) > LEASH
end
local function wyrm_target(self, range)
	local pos = self.object:get_pos()
	local cur = self._wt
	if cur and cur:get_pos() and can_fight(self, cur) and vector.distance(pos, cur:get_pos()) <= WYRM.view
			and not far_from_home(self, cur:get_pos()) then
		if wyrm_sees(self, cur) then self._wt_lost = 0; return cur end
		self._wt_lost = (self._wt_lost or 0) + 1
		if self._wt_lost < 12 then return cur end
	end
	local best, bd
	for _, p in ipairs(core.get_connected_players()) do
		if can_fight(self, p) then
			local d = vector.distance(pos, p:get_pos())
			if d <= (range or WYRM.view) and (not bd or d < bd) and not far_from_home(self, p:get_pos())
					and wyrm_sees(self, p) then best, bd = p, d end
		end
	end
	self._wt, self._wt_lost = best, 0
	return best
end

local function players_near(pos, r)
	local out = {}
	for _, p in ipairs(core.get_connected_players()) do
		if p:get_hp() > 0 and vector.distance(pos, p:get_pos()) <= r then out[#out + 1] = p end
	end
	return out
end

local function hurt(self, player, dmg, from, push, up)
	player:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = dmg}}, nil)
	local dir = vector.direction(from, player:get_pos())
	player:add_velocity({x = dir.x * (push or 3), y = up or 2, z = dir.z * (push or 3)})
	self._fought = now()
end

local function dust(pos, r)
	core.add_particlespawner({amount = 30, time = 0.3, pos = {min = vector.offset(pos, -r, 0, -r), max = vector.offset(pos, r, 0.3, r)},
		vel = {min = {x = -1, y = 0.5, z = -1}, max = {x = 1, y = 2, z = 1}}, exptime = {min = 0.6, max = 1.4},
		size = {min = 3, max = 6}, texture = "orthoverse_monsters_wyrm_smoke.png"})
end

-- Its fire: a ball that flies straight, bursts on what it meets
core.register_entity("orthoverse_monsters:wyrm_fire", {
	initial_properties = {
		visual = "sprite", textures = {"orthoverse_monsters_wyrm_fire.png"}, visual_size = {x = 1.1, y = 1.1},
		glow = 14, physical = false, pointable = true, static_save = false,
		collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3}, selectionbox = {-0.4, -0.4, -0.4, 0.4, 0.4, 0.4},
	},
	_orthoverse_target = {ac = 1},
	_on_blow = function(self, blow) if blow.result ~= "miss" then self._burst(self, true) end end,
	on_punch = function() return true end,
	on_activate = function(self)
		self._t = 0
		core.add_particlespawner({amount = 60, time = 4, attached = self.object, pos = {x = 0, y = 0, z = 0}, radius = 0.25,
			vel = {min = {x = -0.4, y = 0.2, z = -0.4}, max = {x = 0.4, y = 0.8, z = 0.4}}, exptime = {min = 0.2, max = 0.5},
			size = {min = 2, max = 4}, glow = 14, texture = "orthoverse_monsters_wyrm_fire.png"})
	end,
	_burst = function(self, quiet)
		local pos = self.object:get_pos()
		if not pos then return end
		self.object:remove()
		core.add_particlespawner({amount = 24, time = 0.15, pos = pos, radius = 0.4,
			vel = {min = {x = -3, y = -1, z = -3}, max = {x = 3, y = 3, z = 3}}, exptime = {min = 0.3, max = 0.7},
			size = {min = 3, max = 6}, glow = 14, texture = "orthoverse_monsters_wyrm_fire.png"})
		core.sound_play("fire_flint_and_steel", {pos = pos, gain = 0.8, pitch = 0.6, max_hear_distance = 16}, true)
		if quiet then return end
		for _, p in ipairs(players_near(pos, WYRM.breath.radius + 0.9)) do
			local d = vector.distance(pos, vector.offset(p:get_pos(), 0, 0.9, 0))
			if d <= WYRM.breath.radius + 0.9 then
				local owner = self._owner and self._owner:get_pos() and self._owner or self.object
				-- (fire, not a blow: armour does not turn it)
				local function burn()
					p:punch(owner, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = d < 1 and WYRM.breath.damage or
						math.ceil(WYRM.breath.damage / 2)}}, nil)
				end
				if orthoverse.armor then orthoverse.armor.unrolled(burn) else burn() end
			end
		end
	end,
	on_step = function(self, dtime)
		self._t = self._t + dtime
		local pos = self.object:get_pos()
		if not pos then return end
		local from = self._last or pos
		self._last = pos
		if self._t > 4 or solid(vector.round(pos)) then return self._burst(self) end
		-- the whole way since the last step, against each player's body
		local seg = vector.subtract(pos, from)
		local len2 = vector.dot(seg, seg)
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 3)) do
			if obj:is_player() and obj:get_hp() > 0 then
				local p = obj:get_pos()
				local mid = {x = p.x, y = p.y + 0.9, z = p.z}
				local k = len2 > 0 and math.max(0, math.min(1, vector.dot(vector.subtract(mid, from), seg) / len2)) or 1
				local c = vector.add(from, vector.multiply(seg, k))
				if math.abs(c.x - p.x) < 0.6 and math.abs(c.z - p.z) < 0.6 and c.y > p.y - 0.2 and c.y < p.y + 2 then
					self.object:set_pos(c)
					return self._burst(self)
				end
			end
		end
	end,
})

local function wyrm_head(self)
	local f = wyrm_fwd(self)
	return vector.add(vector.offset(self.object:get_pos(), 0, 2.9 * WS / 0.6, 0), vector.multiply(f, 3.6 * WS / 0.6))
end

local function breathe(self, target)
	local from = wyrm_head(self)
	local aim = vector.offset(target:get_pos(), 0, 1.0, 0)
	local dir = vector.direction(from, aim)
	local ball = core.add_entity(vector.add(from, dir), "orthoverse_monsters:wyrm_fire")
	if ball then
		ball:set_velocity(vector.multiply(dir, WYRM.breath.speed))
		ball:get_luaentity()._owner = self.object
	end
	core.add_particlespawner({amount = 14, time = 0.2, pos = from, radius = 0.3,
		vel = {min = vector.multiply(dir, 4), max = vector.multiply(dir, 8)}, exptime = {min = 0.2, max = 0.4},
		size = {min = 4, max = 7}, glow = 14, texture = "orthoverse_monsters_wyrm_fire.png"})
	self._fought = now()
end

local function mode(self, m, t)
	self._wm, self._wmt = m, 0
	self._wmlen = t
	self._act = nil
end

local function turn_len(self, range)
	local len = range[1] + math.random() * (range[2] - range[1])
	return self._enraged and len * 2 / 3 or len
end

local function wyrm_think(self, dtime, moveresult)
	local pos = self.object:get_pos()
	if not pos or self.state == "die" then return false end
	self._wmt = (self._wmt or 0) + dtime
	local t = now()
	local m = self._wm or "sleep"
	if not self._enraged and self.health < WYRM.hp * WYRM.enraged then
		self._enraged = true
		wyrm_sound(self, "orthoverse_monsters_wyrm_roar", 1.5, 0.8)
		label(self, S("The wyrm is enraged!"), "#ff8040")
	end
	local grounded = m == "sleep" or m == "ground" or m == "rest"
	self.object:set_acceleration({x = 0, y = grounded and -10 or 0, z = 0})
	local v = self.object:get_velocity() or {x = 0, y = 0, z = 0}

	if m == "sleep" then
		wyrm_anim(self, "sleep")
		self.object:set_velocity({x = 0, y = v.y, z = 0})
		self._look = (self._look or 0) - dtime
		if self._look > 0 then return false end
		self._look = 0.5
		local woken = self.health < WYRM.hp or wyrm_target(self, WYRM.wake)
		if woken then
			wyrm_sound(self, "orthoverse_monsters_wyrm_roar", 1.5)
			mode(self, "rest", 2)
		end
		return false
	end

	local target = wyrm_target(self)
	if not target then
		self._alone = (self._alone or 0) + dtime
		if self._alone > 25 and grounded then mode(self, "sleep"); self._alone = 0 end
		-- home, on foot
		local h = self._home
		if m == "ground" and h and vector.distance({x = pos.x, y = 0, z = pos.z}, {x = h.x, y = 0, z = h.z}) > 2 then
			wyrm_face(self, h, dtime)
			local f = wyrm_fwd(self)
			local v0 = self.object:get_velocity() or {y = 0}
			self.object:set_velocity({x = f.x * WYRM.walk, y = v0.y, z = f.z * WYRM.walk})
			wyrm_anim(self, "walk")
			return false
		end
	else
		self._alone = 0
		self._fought = t
	end

	if m == "rest" then
		wyrm_anim(self, "stand")
		self.object:set_velocity({x = 0, y = v.y, z = 0})
		if target then wyrm_face(self, target:get_pos(), dtime) end
		if self._wmt >= (self._wmlen or 0) then mode(self, "ground", turn_len(self, WYRM.ground)) end
		return false
	end

	if m == "ground" then
		local act = self._act
		if act then
			self.object:set_velocity({x = 0, y = v.y, z = 0})
			if t < act.at then return false end
			self._act = nil
			if act.kind == "slam" then
				local at = vector.add(pos, vector.multiply(wyrm_fwd(self), WYRM.slam.ahead))
				wyrm_sound(self, "orthoverse_monsters_wyrm_slam", 1.5)
				dust(at, WYRM.slam.radius * 0.7)
				for _, p in ipairs(players_near(at, WYRM.slam.radius)) do
					if math.abs(p:get_pos().y - pos.y) < 2.5 then hurt(self, p, WYRM.slam.damage, at, 4, 5) end
				end
			elseif act.kind == "repel" then
				for _, p in ipairs(players_near(pos, WYRM.repel.radius)) do
					hurt(self, p, WYRM.repel.damage, pos, WYRM.repel.push, 4)
				end
				dust(pos, 2.5)
			end
			self._wa = nil
			return false
		end
		if not target then
			wyrm_anim(self, "stand")
			self.object:set_velocity({x = 0, y = v.y, z = 0})
			return false
		end
		if self._wmt >= (self._wmlen or 0) then
			mode(self, "takeoff", 1.2)
			wyrm_anim(self, "takeoff")
			wyrm_sound(self, "orthoverse_monsters_wyrm_flap", 1.2)
			return false
		end
		local tp = target:get_pos()
		local off = wyrm_face(self, tp, dtime)
		local d = vector.distance({x = pos.x, y = 0, z = pos.z}, {x = tp.x, y = 0, z = tp.z})
		-- two or more close by, or one under its feet: wings
		if (#players_near(pos, WYRM.repel.radius - 1.5) >= 2 or d < 1.8) and t >= (self._repel_ok or 0) then
			self._repel_ok = t + WYRM.repel.every
			self._act = {kind = "repel", at = t + WYRM.repel.windup}
			self._wa = nil; wyrm_anim(self, "repel")
			wyrm_sound(self, "orthoverse_monsters_wyrm_repel", 1.2)
			return false
		end
		if d <= WYRM.reach and off < 0.7 and t >= (self._slam_ok or 0) then
			self._slam_ok = t + WYRM.slam.every * (self._enraged and 0.75 or 1)
			self._act = {kind = "slam", at = t + WYRM.slam.windup}
			self._wa = nil; wyrm_anim(self, "slam")
			wyrm_sound(self, "orthoverse_monsters_wyrm_roar", 0.8, 1.2)
			return false
		end
		if d > WYRM.reach - 1 then
			local f = wyrm_fwd(self)
			local speed = off < 1.2 and WYRM.walk or 0.4
			self.object:set_velocity({x = f.x * speed, y = v.y, z = f.z * speed})
			wyrm_anim(self, "walk")
			-- held up (a pillar, a wall): it flies instead
			local moved = vector.distance(pos, self._was or pos)
			self._was = pos
			self._stuck = moved < 0.4 * WYRM.walk * dtime and (self._stuck or 0) + dtime or 0
			if self._stuck > 2 then self._wmt = self._wmlen or 0 end
		else
			self.object:set_velocity({x = 0, y = v.y, z = 0})
			wyrm_anim(self, "stand")
		end
		return false
	end

	if m == "takeoff" then
		if self._wmt > 0.4 then self.object:set_velocity({x = 0, y = 3, z = 0}) end
		if self._wmt >= (self._wmlen or 0) then mode(self, "air", turn_len(self, WYRM.air)); self._breath_ok = t + 1.2 end
		return false
	end

	local fl = floor_below(pos, 24) or pos.y
	if m == "air" then
		self._flap = (self._flap or 0) - dtime
		if self._flap <= 0 then self._flap = 1.3; wyrm_sound(self, "orthoverse_monsters_wyrm_flap", 0.7) end
		local room = room_above(vector.offset(pos, 0, 3 * WS / 0.6, 0), 10)
		local want_y = math.min(fl + WYRM.hover, pos.y + room - 1)
		local vy = math.max(-2.5, math.min(2.5, (want_y - pos.y) * 1.5))
		local vx, vz = 0, 0
		if target then
			local tp = target:get_pos()
			wyrm_face(self, tp, dtime)
			local flat = {x = tp.x - pos.x, y = 0, z = tp.z - pos.z}
			local d = vector.length(flat)
			if d > 0.1 then
				flat = vector.divide(flat, d)
				local go = d > 11 and 2.5 or (d < 7 and -2 or 0)
				-- and round it, slowly
				vx, vz = flat.x * go - flat.z * 1.2, flat.z * go + flat.x * 1.2
			end
			local b = self._breath
			if b then
				if t >= b.next then
					breathe(self, target)
					b.left = b.left - 1
					b.next = t + WYRM.breath.gap
					if b.left <= 0 then self._breath = nil; self._wa = nil end
				end
			elseif t >= (self._breath_ok or 0) then
				self._breath_ok = t + WYRM.breath.every * (self._enraged and 0.7 or 1)
				self._breath = {left = WYRM.breath.shots, next = t + WYRM.breath.windup}
				wyrm_anim(self, "hover_fire")
				wyrm_sound(self, "orthoverse_monsters_wyrm_breath", 1.2)
			end
		end
		if not self._breath then wyrm_anim(self, "hover") end
		self.object:set_velocity({x = vx, y = vy, z = vz})
		if (self._wmt >= (self._wmlen or 0) or not target) and not self._breath then mode(self, "descend") end
		return false
	end

	if m == "descend" then
		wyrm_anim(self, "fly")
		local vx, vz = 0, 0
		if target then
			local tp = target:get_pos()
			wyrm_face(self, tp, dtime)
			local flat = {x = tp.x - pos.x, y = 0, z = tp.z - pos.z}
			local d = vector.length(flat)
			if d > WYRM.reach then vx, vz = flat.x / d * 2.5, flat.z / d * 2.5 end
		end
		self.object:set_velocity({x = vx, y = -3, z = vz})
		if pos.y - fl < 0.3 or (moveresult and moveresult.touching_ground) or self._wmt > 6 then
			mode(self, "rest", 1)
			self._wa = nil; wyrm_anim(self, "land")
			wyrm_sound(self, "orthoverse_monsters_wyrm_slam", 0.8, 0.8)
			dust(pos, 2)
		end
		return false
	end
	mode(self, "sleep")
	return false
end

monster("wyrm", {
	desc = S("The Wyrm"), level = WYRM.level, xp = WYRM.xp, hp = WYRM.hp, ac = WYRM.ac, damage = WYRM.slam.damage,
	mesh = "orthoverse_monsters_wyrm.b3d", size = 20 * WS, heavy = true, glow = 4, great = true,
	textures = {"orthoverse_monsters_wyrm.png^orthoverse_monsters_wyrm_shading.png"},
	animation = {speed_normal = 20, stand_start = 1, stand_end = 59, walk_start = 211, walk_end = 249},
	collisionbox = {-1.25 * WS, 0, -1.25 * WS, 1.25 * WS, 4.6 * WS, 1.25 * WS},
	selectionbox = {-1.6 * WS, 0, -6 * WS, 1.6 * WS, 4.8 * WS, 6 * WS, rotate = true},
	walk = WYRM.walk, run = WYRM.walk, view_range = WYRM.view, reach = WYRM.reach,
	mobs = {fly = true, fly_in = {"air"}, fall_damage = false, jump = false, fear_height = 0, stand_chance = 100,
		walk_chance = 0, lava_damage = 0, fire_damage = 0, water_damage = 0, stepheight = 1.1, pathfinding = 0,
		on_die = function(self, pos)
			self._wa = nil; wyrm_anim(self, "death")
			self.object:set_velocity({x = 0, y = 0, z = 0})
			self.object:set_acceleration({x = 0, y = -10, z = 0})
			wyrm_sound(self, "orthoverse_monsters_wyrm_roar", 2, 0.6)
			dust(pos, 3)
			-- the ring, on the floor below where it fell
			local fl = floor_below(pos, 24)
			if core.registered_items["orthoverse_props:wyrm_ring"] then
				local at = vector.new(pos.x, (fl or pos.y) + 0.3, pos.z)
				core.after(1.2, function() core.add_item(at, "orthoverse_props:wyrm_ring") end)
			end
			local obj = self.object
			core.after(4, function()
				local p = obj:get_pos()
				if not p then return end
				core.add_particlespawner({amount = 60, time = 0.6, pos = {min = vector.offset(p, -2, 0, -2), max = vector.offset(p, 2, 3, 2)},
					vel = {min = {x = -0.5, y = 0.5, z = -0.5}, max = {x = 0.5, y = 2, z = 0.5}}, exptime = {min = 1, max = 2.5},
					size = {min = 4, max = 8}, texture = "orthoverse_monsters_wyrm_smoke.png"})
				obj:remove()
			end)
			return true
		end},
	sounds = {random = "orthoverse_monsters_wyrm_roar", distance = 48},
	after_activate = function(self)
		self._wm = self._wm or "sleep"
		self._home = self._home or vector.round(self.object:get_pos())
		self._wa = nil
		wyrm_anim(self, "sleep")
		-- a fresh one faces south, its spawner's way in (the builder turns the lair)
		self.object:set_yaw(WYRM.yaw_off + math.pi)
	end,
	do_custom = wyrm_think,
})

------------------------------------------------------------------------------
-- The monster spawner: a grate in the floor, set by the builder

local SPAWNER = "orthoverse_monsters:spawner"

local function may_set(name, pos)
	return core.check_player_privs(name, {protection_bypass = true}) or not core.is_protected(pos, name)
end

-- The great monsters (the wyrm) are for the admin's adventures: one is a
-- whole adventure's climax, worth a day's experience, and heavy for the
-- server. A builder may keep one a spawner already brings (a ready-made
-- adventure's), but not choose one; and a spawner brings one at most.
local function is_admin(name) return core.check_player_privs(name, {protection_bypass = true}) end

-- The kinds `name` may choose, for the spawner at `pos`
local function choosable(name, pos)
	local cur = core.get_meta(pos):get_string("kind")
	local out = {}
	for _, k in ipairs(kinds) do
		if not k.great or is_admin(name) or k.name == cur then out[#out + 1] = k end
	end
	return out
end

local function spawner_formspec(pos, name)
	local meta = core.get_meta(pos)
	local list, sel = {}, 1
	for i, k in ipairs(choosable(name, pos)) do
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
	for _, k in ipairs(kinds) do
		if k.name == kind and k.great then
			-- one at most, and none while one is about
			count = math.min(count, 1)
			for _, obj in ipairs(core.get_objects_inside_radius(pos, NEAR_RADIUS * 2)) do
				local e = obj:get_luaentity()
				if e and e.name == kind then return 0 end
			end
		end
	end
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
		local fs = spawner_formspec(pos, name)
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
	local can = choosable(name, pos)
	if i and can[i] then meta:set_string("kind", can[i].name) end
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
	params = "<kind, e.g. goblin, skeleton, zombie, ghoul, wight>",
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
