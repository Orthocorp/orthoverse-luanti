-- orthoverse_combat: hold-and-release fighting (an experiment for adventures).
--
-- Hold the attack button to wind up a weapon and release to strike. Each
-- weapon has its own curve: ready after a moment, full strength later, a short
-- sweet spot at full strength, and an arm that tires if held too long. On
-- release the blow is traced from the eye along the view: what it meets, how
-- far away (each weapon has a best range and a reach) and where on the target
-- (head, body, legs; front, side, behind). Hidden numbers on the SRD 5.2
-- model (weapon dice, less what the armour takes) decide the damage; a blow
-- that connects always lands.
-- See docs/combat-numbers.md.
--
-- Only things that opt in take these blows: an entity whose definition has
-- `_orthoverse_target = {ac = <armour class>}` and an `_on_blow(self, blow)`
-- function. For now that is the training dummy (Creative tab), which shows
-- each blow over its head; monsters come next. The weapons dig nothing, so
-- holding the button at a wall does nothing.

local S = core.get_translator and core.get_translator("orthoverse_combat") or function(s) return s end

orthoverse = orthoverse or {}
orthoverse.combat = {}

------------------------------------------------------------------------------
-- Weapons (docs/combat-numbers.md): seven kinds, each in four materials. The
-- material adds to the damage in equal steps (steel +0, bronze +1, harder to
-- make; mese +2, diamond +3). No wooden weapons.

local DEBUG = core.settings:get_bool("orthoverse_combat_debug", false)
local SWEET = 0.25            -- seconds at full strength that count as the sweet spot, at rank 1
local DRAIN = 1.0             -- seconds for a tired arm to drop to half strength
local AIM_CONE = math.rad(20)  -- how far off the look a blow still finds a monster
local SWEET_BONUS = 2          -- damage, for a blow released in the sweet spot
local ARMOUR_SOAK = 0.5        -- damage armour takes off a blow, per point of armour class over 10
                               -- (half as much against bashing weapons)

local kinds = {
	dagger = {desc = "dagger", kind = "thrust", ready = 0.1, full = 0.3, tires = 1.5, best = 1.5, reach = 2.5,
		dice = {1, 4}, behind = 0.5, recover = 0.8},
	short_sword = {desc = "short sword", kind = "slash", ready = 0.2, full = 0.5, tires = 2.0, best = 2.0, reach = 3.0,
		dice = {1, 6}, recover = 0.7},
	broadsword = {desc = "broadsword", kind = "slash", ready = 0.4, full = 1.2, tires = 2.5, best = 2.5, reach = 3.5,
		dice = {1, 8}, full_dice = {1, 10}, recover = 0.6},
	spear = {desc = "spear", kind = "jab", ready = 0.3, full = 0.8, tires = 2.5, best = 3.5, reach = 4.5,
		dice = {1, 6}, wield_scale = 2.0, recover = 0.6},
	mace = {desc = "mace", kind = "bash", ready = 0.4, full = 1.0, tires = 2.5, best = 2.0, reach = 3.0,
		dice = {1, 6}, recover = 0.6},
	morning_star = {desc = "morning star", kind = "bash", ready = 0.5, full = 1.2, tires = 2.6, best = 2.0, reach = 3.0,
		dice = {1, 8}, recover = 0.6},
	war_hammer = {desc = "war hammer", kind = "bash", ready = 0.7, full = 1.8, tires = 3.0, best = 2.0, reach = 3.0,
		dice = {1, 10}, recover = 0.6},
}
local KIND_ORDER = {"dagger", "short_sword", "broadsword", "spear", "mace", "morning_star", "war_hammer"}
local materials = {
	{id = "steel", desc = "Steel", dmg = 0, rank = 1},
	{id = "bronze", desc = "Bronze", dmg = 1, rank = 3},   -- rank: from which the metal counts in full
	{id = "mese", desc = "Mese", dmg = 2, rank = 6},
	{id = "diamond", desc = "Diamond", dmg = 3, rank = 10},
}

local weapons = {}   -- "<kind>_<material>" -> the weapon
local by_item = {}

local function capitalise(s) return s:sub(1, 1):upper() .. s:sub(2) end

for _, kid in ipairs(KIND_ORDER) do
	local k = kinds[kid]
	for _, m in ipairs(materials) do
		local w = setmetatable({kind_id = kid, material = m.id, dmg = m.dmg}, {__index = k})
		w.id = kid .. "_" .. m.id
		w.desc = m.desc .. " " .. k.desc
		w.item = "orthoverse_combat:" .. w.id
		w.image = "orthoverse_combat_" .. w.id .. ".png"
		weapons[w.id], by_item[w.item] = w, w
		core.register_tool(w.item, {
			description = S(w.desc) .. "\n" .. S("Hold to wind up, release to strike")
				.. (m.rank > 1 and ("\n" .. S("Full strength from rank @1", m.rank)) or ""),
			inventory_image = w.image,
			wield_scale = {x = k.wield_scale or 1.3, y = k.wield_scale or 1.3, z = 1},
			-- digs nothing; the default punch does nothing (blows are ours)
			tool_capabilities = {full_punch_interval = 0.5, max_drop_level = 0, groupcaps = {}, damage_groups = {fleshy = 0}},
			groups = {orthoverse_weapon = 1, hold_attack = math.floor(k.full * 1000), hold_tires = math.floor(k.tires * 1000),
				hold_thrust = k.kind == "thrust" and 1 or nil, hold_jab = k.kind == "jab" and 1 or nil,
				hold_recover = math.floor(k.recover * 1000)},
			range = k.reach + 0.5,
		})
		-- What a monster carries: the same weapon without a human hand on it
		core.register_craftitem("orthoverse_combat:" .. w.id .. "_carried", {
			description = S(w.desc),
			inventory_image = w.image,
			groups = {not_in_creative_inventory = 1},
		})
	end
	-- the steel one stands in for the single weapons of patches 1021 to 1025
	core.register_alias("orthoverse_combat:" .. kid, "orthoverse_combat:" .. kid .. "_steel")
end

------------------------------------------------------------------------------
-- Minetest Game's swords go: they do nothing to monsters (only these weapons
-- do), so they would only confuse. Their recipes go with them, and any left
-- in inventories or chests turn into short swords of the same metal.

for _, material in ipairs({"wood", "stone", "bronze", "steel", "mese", "diamond"}) do
	local name = "default:sword_" .. material
	if core.registered_items[name] then
		core.clear_craft({output = name})
		core.unregister_item(name)
		local m = weapons["short_sword_" .. material] and material or "steel"
		core.register_alias(name, "orthoverse_combat:short_sword_" .. m)
	end
end
core.clear_craft({type = "fuel", recipe = "default:sword_wood"})

------------------------------------------------------------------------------
-- Nothing but these weapons does any harm: fists, tools and blocks in the
-- hand do no damage to players, animals or anything else. (Monsters, falls,
-- lava and the like still hurt players; this is only about what a player
-- strikes with.)

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_items) do
		local caps = def.tool_capabilities
		if caps and caps.damage_groups and next(caps.damage_groups)
				and not (def.groups and def.groups.orthoverse_weapon) then
			local new = table.copy(caps)
			new.damage_groups = {}
			core.override_item(name, {tool_capabilities = new})
		end
	end
end)

core.register_on_punchplayer(function(player, hitter)
	-- no player hurts another (a blast is a player "punching" themselves:
	-- Mobs Redo's explosions do it that way, so that one goes through)
	if hitter and hitter:is_player() and hitter:get_player_name() ~= player:get_player_name() then
		return true
	end
end)

------------------------------------------------------------------------------
-- How strong a blow is, from how long it was held

-- Returns strength (0.25 .. 1), the phase, and whether in the sweet spot
local function strength(w, held, sweet_width)
	local SWEET = sweet_width or SWEET
	if held < w.ready then return 0.25, "feeble", false end
	if held < w.full then return 0.5 + 0.5 * (held - w.ready) / (w.full - w.ready), "rising", false end
	if held < w.full + SWEET then return 1, "sweet", true end
	if held < w.tires then return 1, "full", false end
	return 1 - 0.5 * math.min(1, (held - w.tires) / DRAIN), "tired", false
end

local function roll(n, sides)
	local t = 0
	for _ = 1, n do t = t + math.random(sides) end
	return t
end

-- No bar or other sign of the sweet spot: players learn each weapon's timing
-- by feel. The browser client (web/client/patches/luanti-hold-attack.patch)
-- raises the weapon in the hand while the button is held, from the item
-- groups hold_attack (ms to full strength) and hold_tires, makes it tremble
-- and sag once the arm tires, and swings it once on release (a spear is
-- levelled and jabbed forward instead). Other clients swing it over and over
-- while the button is down.

------------------------------------------------------------------------------
-- The blow


local function describe(blow)
	if blow.result == "miss" then return blow.why end
	local bits = {}
	if blow.zone ~= "body" then bits[#bits + 1] = blow.zone end
	if blow.sweet then bits[#bits + 1] = "sweet" end
	if blow.phase == "feeble" then bits[#bits + 1] = "feeble" end
	if blow.phase == "tired" then bits[#bits + 1] = "tired" end
	if blow.side ~= "front" then bits[#bits + 1] = "from " .. blow.side end
	if blow.crit then bits[#bits + 1] = "critical" end
	local head = (blow.result == "glance" and "Glance " or "Hit ") .. blow.damage
	return #bits > 0 and (head .. " (" .. table.concat(bits, ", ") .. ")") or head
end

-- The sound of a blow tells how good it was: a swing on every release, then
-- a swish (nothing), a light tap (a glance), a thud (a hit), a heavy thud
-- with a crunch (the sweet spot) or a blow with a ring (a critical, or a head
-- blow that stuns). tools/weapons/make_blow_sounds.py makes them.
local function blow_sound(name, pos, gain)
	core.sound_play("orthoverse_combat_" .. name, {pos = pos, gain = gain or 1, max_hear_distance = 16,
		pitch = 0.92 + math.random() * 0.16}, true)
end

local function strike(player, w, held)
	-- The striker's rank (orthoverse_rank): a wider sweet spot, extra damage,
	-- and how much of the weapon's metal counts
	local R = orthoverse.rank
	local rank = R and R.get(player) or 1
	local s, phase, sweet = strength(w, held, R and R.sweet(rank))
	local metal = R and math.min(w.dmg, R.material_cap(rank)) or w.dmg
	local props = player:get_properties()
	local eye = vector.add(player:get_pos(), {x = 0, y = props.eye_height or 1.47, z = 0})
	local dir = player:get_look_dir()
	local far = vector.add(eye, vector.multiply(dir, w.reach + 1))
	local target, point
	for pointed in core.raycast(eye, far, true, false) do
		if pointed.type == "node" then
			local def = core.registered_nodes[core.get_node(pointed.under).name]
			if not def or def.walkable ~= false then break end
		elseif pointed.type == "object" and pointed.ref ~= player then
			target, point = pointed.ref, pointed.intersection_point
			break
		end
	end
	if not (target and target:get_luaentity() and target:get_luaentity()._orthoverse_target) then
		-- A forgiving aim: monsters move and some are small, so a blow that
		-- passes close by still finds one, within AIM_CONE of the look and
		-- in reach, with nothing solid in between (the nearest to the line)
		target, point = nil, nil
		local best
		for _, obj in ipairs(core.get_objects_inside_radius(eye, w.reach + 1)) do
			local e = obj ~= player and obj:get_luaentity()
			if e and e._orthoverse_target then
				local op = obj:get_pos()
				local cb = obj:get_properties().collisionbox
				local centre = vector.add(op, {x = (cb[1] + cb[4]) / 2, y = (cb[2] + cb[5]) / 2, z = (cb[3] + cb[6]) / 2})
				local along = vector.dot(vector.subtract(centre, eye), dir)
				if along > 0.2 then
					-- the point of its box nearest to the look line
					local on_line = vector.add(eye, vector.multiply(dir, along))
					local near = {
						x = math.max(op.x + cb[1], math.min(op.x + cb[4], on_line.x)),
						y = math.max(op.y + cb[2], math.min(op.y + cb[5], on_line.y)),
						z = math.max(op.z + cb[3], math.min(op.z + cb[6], on_line.z)),
					}
					local to = vector.subtract(near, eye)
					local len = vector.length(to)
					local angle = len > 0 and math.acos(math.max(-1, math.min(1, vector.dot(to, dir) / len))) or 0
					if angle <= AIM_CONE and len <= w.reach + 0.5 and (not best or angle < best) then
						local clear = true
						for pt in core.raycast(eye, near, false, false) do
							local def = core.registered_nodes[core.get_node(pt.under).name]
							if not def or def.walkable ~= false then clear = false; break end
						end
						if clear then best, target, point = angle, obj, near end
					end
				end
			end
		end
	end
	local ent = target and target:get_luaentity()
	if DEBUG then
		core.log("action", ("[orthoverse_combat] release after %.2f s: %s"):format(held,
			ent and (ent.name .. (ent._orthoverse_target and "" or " (not a target)")) or "nothing in reach"))
	end
	blow_sound("swing", eye, s >= 1 and 0.8 or 0.5)
	if not ent or not ent._orthoverse_target then
		blow_sound("miss", vector.add(eye, vector.multiply(dir, 1.5)), 0.6)
		return
	end
	local blow = {attacker = player, weapon = w, held = held, strength = s, phase = phase, sweet = sweet}
	blow.distance = vector.distance(eye, point)
	-- Where on the target: height on its box, and which side of it
	local tpos = target:get_pos()
	local cb = target:get_properties().collisionbox
	local rel = (point.y - (tpos.y + cb[2])) / math.max(0.01, cb[5] - cb[2])
	blow.zone = rel > 0.75 and "head" or rel < 0.25 and "legs" or "body"
	local yaw = target:get_yaw() or 0
	local facing = {x = -math.sin(yaw), z = math.cos(yaw)}
	local to_attacker = vector.normalize({x = eye.x - tpos.x, y = 0, z = eye.z - tpos.z})
	local d = facing.x * to_attacker.x + facing.z * to_attacker.z
	blow.side = d > 0.5 and "front" or d < -0.5 and "behind" or "side"
	-- Range
	if blow.distance > w.reach then
		blow.result, blow.why = "miss", "Miss (out of reach)"
	else
		-- A blow that connects always lands: no roll to hit. Armour takes
		-- some of the damage instead, and luck only decides the damage dice
		-- (and a critical, 1 in 20, with doubled dice).
		local glance = blow.distance > w.best
		local ac = ent._orthoverse_target.ac or 10
		blow.ac = ac
		blow.crit = phase ~= "feeble" and math.random(20) == 20
		local dice = (phase == "sweet" or phase == "full") and w.full_dice or w.dice
		local n, sides = dice[1], dice[2]
		local dmg = roll(blow.crit and 2 * n or n, sides) + (phase == "feeble" and 0 or metal + (R and R.damage(rank) or 0))
			+ (sweet and SWEET_BONUS or 0) + (blow.side == "side" and 1 or 0)
		dmg = dmg * s
		if blow.zone == "head" then dmg = dmg * 1.5 end
		if blow.side == "behind" then dmg = dmg * (1 + (w.behind or 0.25)) end
		if glance then dmg = dmg * 0.5 end
		dmg = dmg - math.max(0, ac - 10) * ARMOUR_SOAK * (w.kind == "bash" and 0.5 or 1)
		blow.damage = math.max(1, math.floor(dmg + 0.5))
		blow.result = glance and "glance" or "hit"
		blow.stun = blow.zone == "head" and s >= 1 and 1 or nil
	end
	blow.text = describe(blow)
	blow_sound(blow.result == "miss" and "miss" or blow.result == "glance" and "glance"
		or (blow.crit or blow.stun) and "crit" or sweet and "strong" or "hit", point)
	if DEBUG then
		core.log("action", ("[orthoverse_combat] %s on %s: %s (%.1f m, %s, %s)"):format(w.id, ent.name, blow.text,
			blow.distance, blow.zone, blow.side))
	end
	if ent._on_blow then ent._on_blow(ent, blow) end
	return blow
end

orthoverse.combat.weapons = weapons
orthoverse.combat.kinds = kinds
orthoverse.combat.strength = strength
orthoverse.combat.strike = strike   -- for tests

------------------------------------------------------------------------------
-- Watching the attack button

local holding = {}   -- name -> {t0 = seconds, w = weapon, phase}
-- After a blow the arm recovers (each weapon's `recover`, in seconds) before
-- the next can be wound up: held through it, the wind-up counts from its end
-- (the browser client shows it so too: item group hold_recover). Without it a
-- quick weapon could strike again and again, as fast as the button goes.
local rested = {}    -- name -> when the arm has recovered

local function now() return core.get_us_time() / 1e6 end

core.register_globalstep(function()
	local t = now()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local w = by_item[player:get_wielded_item():get_name()]
		local down = player:get_player_control().dig
		local h = holding[name]
		local wield = orthoverse.wield
		if h and h.w ~= w then
			-- weapon changed while winding up: no blow
			holding[name] = nil
			h = nil
			if wield then wield.pose(player, nil) end
		end
		if w and down and not h then
			holding[name] = {t0 = math.max(t, rested[name] or 0), w = w}
			-- others see the arm raised (orthoverse_wield)
			if wield then wield.pose(player, "windup", w.kind) end
		elseif h and not down then
			holding[name] = nil
			if t <= h.t0 then
				-- let go while still recovering: no blow
				if wield then wield.pose(player, nil) end
			else
				if wield then wield.pose(player, "strike", h.w.kind) end
				strike(player, h.w, t - h.t0)
				rested[name] = t + (h.w.recover or 0)
			end
		end
	end
end)

------------------------------------------------------------------------------
-- Footwork. With a weapon in hand, backing away is slower than walking
-- (slower than any monster runs), and backing away while winding up a blow
-- is a crawl, as slow as sneaking: so a fighter cannot keep stepping back
-- out of reach and then dart in to strike. Walking forward or sideways is
-- as ever. Draughts of swiftness (orthoverse_loot) speed it all up for a
-- while: orthoverse.combat.boost(player, multiplier, seconds). Some monsters
-- hold a player back for a moment: orthoverse.combat.hamper(player, ...).
-- (speed_walk only: the beds' `speed` override is left alone.)

local BACK_ARMED = 0.6      -- of walking speed: 2.4 blocks a second
local BACK_WINDING = 0.33   -- as slow as sneaking

local boosts = {}           -- name -> {mult, till}
local applied = {}          -- name -> the speed_walk last set

function orthoverse.combat.boost(player, mult, secs)
	boosts[player:get_player_name()] = {mult = mult, till = now() + secs}
end

-- Held back for a while (a zombie's grab, a ghoul's numbing claws): the
-- slowest of those still holding counts
local hampers = {}          -- name -> {mult, till}
function orthoverse.combat.hamper(player, mult, secs)
	local name = player:get_player_name()
	local cur, till = hampers[name], now() + secs
	if cur and cur.till > now() and cur.mult <= mult then return end
	hampers[name] = {mult = mult, till = till}
end

core.register_globalstep(function()
	local t = now()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local c = player:get_player_control()
		local factor = 1
		if by_item[player:get_wielded_item():get_name()] and c.down and not c.up then
			factor = holding[name] and BACK_WINDING or BACK_ARMED
		end
		local b = boosts[name]
		if b and t > b.till then
			boosts[name] = nil
			b = nil
			core.chat_send_player(name, "Your swiftness wears off.")
		end
		local hm = hampers[name]
		if hm and t > hm.till then hampers[name] = nil; hm = nil end
		local speed = factor * (b and b.mult or 1) * (hm and hm.mult or 1)
		if applied[name] ~= speed then
			applied[name] = speed
			player:set_physics_override({speed_walk = speed})
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	holding[name] = nil
	rested[name] = nil
	boosts[name] = nil
	applied[name] = nil
end)

-- The weapon in the hand is its plain picture, as any item is. Weapons that
-- were given a fist on the grip (patches 1027 to 1031) lose it when held or
-- on joining.

local function plain(player)
	local stack = player:get_wielded_item()
	if by_item[stack:get_name()] and stack:get_meta():get_string("wield_image") ~= "" then
		stack:get_meta():set_string("wield_image", "")
		player:set_wielded_item(stack)
	end
end

core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	for i, stack in ipairs(inv:get_list("main") or {}) do
		if by_item[stack:get_name()] and stack:get_meta():get_string("wield_image") ~= "" then
			stack:get_meta():set_string("wield_image", "")
			inv:set_stack("main", i, stack)
		end
	end
end)

local since = 0
core.register_globalstep(function(dtime)
	since = since + dtime
	if since < 1 then return end
	since = 0
	for _, player in ipairs(core.get_connected_players()) do plain(player) end
end)

------------------------------------------------------------------------------
-- The training dummy: takes every blow and shows it over its head.
-- Right-click it to change its armour (none, leather, chain, plate).

local ARMOUR = {{"no armour", 10}, {"leather", 11}, {"chain", 14}, {"plate", 17}}

local function dummy_label(self, text, colour)
	self.object:set_properties({nametag = text, nametag_color = colour or "#efe6d0"})
	self._label_until = now() + 2.5
end

core.register_entity("orthoverse_combat:dummy", {
	initial_properties = {
		visual = "cube",
		visual_size = {x = 0.8, y = 1.8, z = 0.5},
		textures = {"orthoverse_combat_dummy_side.png", "orthoverse_combat_dummy_side.png",
			"orthoverse_combat_dummy_side.png", "orthoverse_combat_dummy_side.png",
			"orthoverse_combat_dummy_front.png", "orthoverse_combat_dummy_side.png"},
		collisionbox = {-0.4, -0.9, -0.25, 0.4, 0.9, 0.25},
		selectionbox = {-0.4, -0.9, -0.25, 0.4, 0.9, 0.25},
		physical = true,
		static_save = true,
		nametag = "",
	},
	_orthoverse_target = {ac = 10},
	on_activate = function(self, staticdata)
		self.object:set_armor_groups({immortal = 1})
		local armour = tonumber(staticdata) or 1
		self._armour = armour
		self._orthoverse_target = {ac = ARMOUR[armour][2]}
	end,
	get_staticdata = function(self) return tostring(self._armour or 1) end,
	on_rightclick = function(self, clicker)
		self._armour = (self._armour or 1) % #ARMOUR + 1
		self._orthoverse_target = {ac = ARMOUR[self._armour][2]}
		dummy_label(self, ("Training dummy: %s (armour class %d)"):format(ARMOUR[self._armour][1], ARMOUR[self._armour][2]))
	end,
	on_punch = function() return true end,   -- ordinary punches do nothing
	_on_blow = function(self, blow)
		local colour = blow.result == "miss" and "#a09a90" or blow.sweet and "#f5c64a" or "#efe6d0"
		local extra = blow.ac and ("  [armour class %d, %.1f m, held %.2f s]"):format(blow.ac, blow.distance, blow.held)
			or ("  [%.1f m]"):format(blow.distance)
		dummy_label(self, blow.text, colour)
		core.log("action", "[orthoverse_combat] " .. blow.weapon.id .. " " .. blow.text .. extra)
		if blow.attacker and blow.attacker:is_player() then
			core.chat_send_player(blow.attacker:get_player_name(), capitalise(blow.weapon.desc) .. ": " .. blow.text .. extra)
		end
		if blow.result ~= "miss" then
			self.object:set_properties({textures = {"orthoverse_combat_dummy_side.png^[brighten",
				"orthoverse_combat_dummy_side.png^[brighten", "orthoverse_combat_dummy_side.png^[brighten",
				"orthoverse_combat_dummy_side.png^[brighten", "orthoverse_combat_dummy_front.png^[brighten",
				"orthoverse_combat_dummy_side.png^[brighten"}})
			core.after(0.15, function()
				if self.object:get_pos() then
					self.object:set_properties({textures = {"orthoverse_combat_dummy_side.png", "orthoverse_combat_dummy_side.png",
						"orthoverse_combat_dummy_side.png", "orthoverse_combat_dummy_side.png",
						"orthoverse_combat_dummy_front.png", "orthoverse_combat_dummy_side.png"}})
				end
			end)
		end
	end,
	on_step = function(self)
		if self._label_until and now() > self._label_until then
			self._label_until = nil
			self.object:set_properties({nametag = ""})
		end
	end,
})

core.register_craftitem("orthoverse_combat:dummy", {
	description = S("Training dummy") .. "\n" .. S("Place it, then strike it; right-click it to change its armour"),
	inventory_image = "orthoverse_combat_dummy_front.png",
	on_place = function(itemstack, placer, pointed)
		if pointed.type ~= "node" then return itemstack end
		local name = placer and placer:get_player_name() or ""
		if core.is_protected(pointed.above, name) then
			core.record_protection_violation(pointed.above, name)
			return itemstack
		end
		local pos = vector.add(pointed.above, {x = 0, y = 0.4, z = 0})
		local obj = core.add_entity(pos, "orthoverse_combat:dummy", "1")
		if obj and placer then
			-- face the one who placed it
			local p = placer:get_pos()
			obj:set_yaw(math.atan2(-(p.x - pos.x), p.z - pos.z))
		end
		if not core.is_creative_enabled(name) then itemstack:take_item() end
		return itemstack
	end,
})

-- Punch-to-remove for whoever may build where it stands: sneak and punch
core.register_on_mods_loaded(function()
	local def = core.registered_entities["orthoverse_combat:dummy"]
	def.on_punch = function(self, puncher)
		if puncher and puncher:is_player() and puncher:get_player_control().sneak
				and not core.is_protected(vector.round(self.object:get_pos()), puncher:get_player_name()) then
			self.object:remove()
		end
		return true
	end
end)
