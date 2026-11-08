-- orthoverse_combat: hold-and-release fighting (an experiment for adventures).
--
-- Hold the attack button to wind up a weapon and release to strike. Each
-- weapon has its own curve: ready after a moment, full strength later, a short
-- sweet spot at full strength, and an arm that tires if held too long. On
-- release the blow is traced from the eye along the view: what it meets, how
-- far away (each weapon has a best range and a reach) and where on the target
-- (head, body, legs; front, side, behind). Hidden numbers on the SRD 5.2
-- model (d20 plus bonuses against armour class, weapon dice) decide the rest.
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
-- Weapons (docs/combat-numbers.md; steel for now: +1 to hit, +1 damage)

local DEBUG = core.settings:get_bool("orthoverse_combat_debug", false)
local MATERIAL = {hit = 1, dmg = 1}
local RANK_BONUS = 2          -- rank 1 to 4
local SWEET = 0.25            -- seconds at full strength that count as the sweet spot, at rank 1
local DRAIN = 1.0             -- seconds for a tired arm to drop to half strength

local weapons = {
	dagger = {desc = "Dagger", kind = "thrust", ready = 0.1, full = 0.3, tires = 1.5, best = 1.5, reach = 2.5,
		dice = {1, 4}, behind = 0.5},
	short_sword = {desc = "Short sword", kind = "slash", ready = 0.2, full = 0.5, tires = 2.0, best = 2.0, reach = 3.0,
		dice = {1, 6}},
	broadsword = {desc = "Broadsword", kind = "slash", ready = 0.4, full = 1.2, tires = 2.5, best = 2.5, reach = 3.5,
		dice = {1, 8}, full_dice = {1, 10}},
	spear = {desc = "Spear", kind = "thrust", ready = 0.3, full = 0.8, tires = 2.5, best = 3.5, reach = 4.5,
		dice = {1, 6}},
	war_hammer = {desc = "War hammer", kind = "bash", ready = 0.7, full = 1.8, tires = 3.0, best = 2.0, reach = 3.0,
		dice = {1, 10}},
}
local by_item = {}

for id, w in pairs(weapons) do
	w.id = id
	w.item = "orthoverse_combat:" .. id
	w.image = "orthoverse_combat_" .. id .. ".png"
	by_item[w.item] = w
	core.register_tool(w.item, {
		description = S(w.desc) .. "\n" .. S("Hold to wind up, release to strike"),
		inventory_image = w.image,
		wield_scale = {x = 1.3, y = 1.3, z = 1},
		-- digs nothing; the default punch does nothing (blows are ours)
		tool_capabilities = {full_punch_interval = 0.5, max_drop_level = 0, groupcaps = {}, damage_groups = {fleshy = 0}},
		groups = {orthoverse_weapon = 1},
		range = w.reach + 0.5,
	})
end

------------------------------------------------------------------------------
-- Minetest Game's swords go: they do nothing to monsters (only these weapons
-- do), so they would only confuse. Their recipes go with them, and any left
-- in inventories or chests turn into short swords.

for _, material in ipairs({"wood", "stone", "bronze", "steel", "mese", "diamond"}) do
	local name = "default:sword_" .. material
	if core.registered_items[name] then
		core.clear_craft({output = name})
		core.unregister_item(name)
		core.register_alias(name, "orthoverse_combat:short_sword")
	end
end
core.clear_craft({type = "fuel", recipe = "default:sword_wood"})

------------------------------------------------------------------------------
-- How strong a blow is, from how long it was held

-- Returns strength (0.25 .. 1), the phase, and whether in the sweet spot
local function strength(w, held)
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

------------------------------------------------------------------------------
-- The charge bar: a strip above the hotbar showing the hold, with the sweet
-- spot marked

local BAR_W, BAR_H = 240, 10
local huds = {}     -- name -> {bg, fill, sweet, ready, w}

local function fill_tex(colour) return "[fill:1x1:" .. colour end

local function hud_el(player, x, w, h, colour, z)
	return player:hud_add({
		type = "image", position = {x = 0.5, y = 1}, alignment = {x = 1, y = 0},
		offset = {x = x, y = -96}, scale = {x = math.max(1, w), y = h},
		text = fill_tex(colour), z_index = z,
	})
end

local function bar_x(w, t) return math.floor(BAR_W * math.min(1, t / (w.tires + DRAIN))) end

local function show_bar(player, w)
	local name = player:get_player_name()
	local h = huds[name]
	if h and h.w == w then return h end
	if h then for _, id in pairs(h.ids) do player:hud_remove(id) end end
	local left = -BAR_W / 2
	h = {w = w, ids = {}, last = -1}
	h.ids.bg = hud_el(player, left - 2, BAR_W + 4, BAR_H + 4, "#1a1410", 900)
	h.ids.ready = hud_el(player, left + bar_x(w, w.ready), 2, BAR_H, "#8a8070", 902)
	h.ids.sweet = hud_el(player, left + bar_x(w, w.full), math.max(3, bar_x(w, w.full + SWEET) - bar_x(w, w.full)),
		BAR_H, "#f5c64a", 901)
	h.ids.tires = hud_el(player, left + bar_x(w, w.tires), 2, BAR_H, "#c0503a", 902)
	h.ids.fill = hud_el(player, left, 1, BAR_H - 4, "#efe6d0", 903)
	huds[name] = h
	return h
end

local PHASE_COLOUR = {feeble = "#7a7266", rising = "#efe6d0", sweet = "#fff2a8", full = "#efe6d0", tired = "#d07a5a"}

local function update_bar(player, w, held, phase)
	local h = show_bar(player, w)
	local x = bar_x(w, held)
	if x == h.last and phase == h.phase then return end
	h.last, h.phase = x, phase
	player:hud_change(h.ids.fill, "scale", {x = math.max(1, x), y = BAR_H - 4})
	player:hud_change(h.ids.fill, "offset", {x = -BAR_W / 2, y = -96})
	player:hud_change(h.ids.fill, "text", fill_tex(PHASE_COLOUR[phase]))
end

local function hide_bar(player)
	local name = player:get_player_name()
	local h = huds[name]
	if not h then return end
	for _, id in pairs(h.ids) do player:hud_remove(id) end
	huds[name] = nil
end

-- The weapon in the hand. The client swings a held tool over and over while
-- the attack button is down, and the server cannot stop it, so while winding
-- up the wielded item is drawn invisible and the weapon is drawn on the HUD
-- instead (the raised-weapon picture, as in Ultima Underworld): it rises as
-- the blow gathers strength, glints at the sweet spot, sags when the arm
-- tires, and swings across on release.

local WEAPON_SCALE = 16       -- screen pixels per texture pixel
local raised = {}             -- name -> {id, token}

local function hide_wielded(player, w, hide)
	local stack = player:get_wielded_item()
	if stack:get_name() ~= w.item then return end
	local look = hide and "blank.png" or ""
	local meta = stack:get_meta()
	if meta:get_string("wield_image") == look then return end
	meta:set_string("wield_image", look)
	player:set_wielded_item(stack)
end

local function weapon_hud(player, texture, x, y)
	local name = player:get_player_name()
	local r = raised[name]
	if not r then
		r = {token = 0}
		r.id = player:hud_add({
			type = "image", position = {x = 0.62, y = 1}, alignment = {x = 1, y = -1},
			offset = {x = x, y = y}, scale = {x = WEAPON_SCALE, y = WEAPON_SCALE},
			text = texture, z_index = 800,
		})
		raised[name] = r
		return r
	end
	if r.text ~= texture then player:hud_change(r.id, "text", texture) end
	if r.x ~= x or r.y ~= y then player:hud_change(r.id, "offset", {x = x, y = y}) end
	r.text, r.x, r.y = texture, x, y
	return r
end

local function drop_weapon_hud(player)
	local name = player:get_player_name()
	local r = raised[name]
	if r then player:hud_remove(r.id); raised[name] = nil end
end

-- While winding up: how far up the weapon is drawn follows the strength
local function show_raised(player, w, held, phase)
	local s = strength(w, held)
	local up = (s - 0.25) / 0.75                                  -- 0 .. 1
	local tex = w.image .. "^[transformFX"
	if phase == "sweet" then tex = tex .. "^[colorize:#ffd84a:100"
	elseif phase == "tired" then tex = tex .. "^[colorize:#a04030:50" end
	local y = math.floor(150 - 210 * up)
	if phase == "tired" then y = y + 30 end
	weapon_hud(player, tex, 0, y)
end

-- On release: the swing across, then back to the ordinary hand view
local function show_swing(player, w)
	local name = player:get_player_name()
	local r = weapon_hud(player, w.image .. "^[transformFXR90", -260, 70)
	r.token = r.token + 1
	local token = r.token
	core.after(0.22, function()
		local p = core.get_player_by_name(name)
		local cur = raised[name]
		if not p or not cur or cur.token ~= token then return end
		drop_weapon_hud(p)
		hide_wielded(p, w, false)
	end)
end

------------------------------------------------------------------------------
-- The blow

local misses = {}   -- "attacker|target id" -> misses in a row (bad luck smoothing)

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

local function strike(player, w, held)
	local s, phase, sweet = strength(w, held)
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
	local ent = target and target:get_luaentity()
	if DEBUG then
		core.log("action", ("[orthoverse_combat] release after %.2f s: %s"):format(held,
			ent and (ent.name .. (ent._orthoverse_target and "" or " (not a target)")) or "nothing in reach"))
	end
	if not ent or not ent._orthoverse_target then return end
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
		local glance = blow.distance > w.best
		local key = player:get_player_name() .. "|" .. tostring(target)
		local bonus = RANK_BONUS + MATERIAL.hit + (sweet and 2 or 0)
			+ (blow.side == "side" and 1 or 0) + (blow.side == "behind" and 3 or 0)
			+ (glance and -2 or 0) + math.max(0, ((misses[key] or 0) - 1) * 2)
		if phase == "feeble" then bonus = RANK_BONUS end
		local d20 = math.random(20)
		local ac = ent._orthoverse_target.ac or 10
		blow.d20, blow.total, blow.ac = d20, d20 + bonus, ac
		if d20 == 1 or (d20 ~= 20 and d20 + bonus < ac) then
			blow.result, blow.why = "miss", ("Miss (rolled %d vs %d)"):format(d20 + bonus, ac)
			misses[key] = (misses[key] or 0) + 1
		else
			misses[key] = 0
			blow.crit = d20 == 20
			local dice = (phase == "sweet" or phase == "full") and w.full_dice or w.dice
			local n, sides = dice[1], dice[2]
			local dmg = roll(blow.crit and 2 * n or n, sides) + (phase == "feeble" and 0 or MATERIAL.dmg)
			dmg = dmg * s
			if blow.zone == "head" then dmg = dmg * 1.5 end
			if blow.side == "behind" then dmg = dmg * (1 + (w.behind or 0.25)) end
			if glance then dmg = dmg * 0.5 end
			blow.damage = math.max(1, math.floor(dmg + 0.5))
			blow.result = glance and "glance" or "hit"
			blow.stun = blow.zone == "head" and s >= 1 and 1 or nil
		end
	end
	blow.text = describe(blow)
	if ent._on_blow then ent._on_blow(ent, blow) end
	return blow
end

orthoverse.combat.weapons = weapons
orthoverse.combat.strength = strength

------------------------------------------------------------------------------
-- Watching the attack button

local holding = {}   -- name -> {t0 = seconds, w = weapon, phase}

local function now() return core.get_us_time() / 1e6 end

core.register_globalstep(function()
	local t = now()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local w = by_item[player:get_wielded_item():get_name()]
		local down = player:get_player_control().dig
		local h = holding[name]
		if h and h.w ~= w then
			-- weapon changed while winding up: no blow
			holding[name] = nil
			hide_bar(player)
			drop_weapon_hud(player)
			hide_wielded(player, h.w, false)
			h = nil
		end
		if w and down and not h then
			holding[name] = {t0 = t, w = w}
			hide_wielded(player, w, true)
			show_raised(player, w, 0, "feeble")
			raised[name].token = raised[name].token + 1   -- cancels a swing still being shown
		elseif w and down and h then
			local _, phase = strength(w, t - h.t0)
			update_bar(player, w, t - h.t0, phase)
			show_raised(player, w, t - h.t0, phase)
		elseif h and not down then
			holding[name] = nil
			hide_bar(player)
			show_swing(player, h.w)
			strike(player, h.w, t - h.t0)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	holding[name], huds[name], raised[name] = nil, nil, nil
end)

-- A weapon left invisible (the server stopped mid-swing) is shown again
core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	for i, stack in ipairs(inv:get_list("main") or {}) do
		if by_item[stack:get_name()] and stack:get_meta():get_string("wield_image") ~= "" then
			stack:get_meta():set_string("wield_image", "")
			inv:set_stack("main", i, stack)
		end
	end
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
		local extra = blow.d20 and ("  [d20 %d +%d vs %d, %.1f m, held %.2f s]"):format(blow.d20, blow.total - blow.d20,
			blow.ac, blow.distance, blow.held) or ("  [%.1f m]"):format(blow.distance)
		dummy_label(self, blow.text, colour)
		core.log("action", "[orthoverse_combat] " .. blow.weapon.id .. " " .. blow.text .. extra)
		if blow.attacker and blow.attacker:is_player() then
			core.chat_send_player(blow.attacker:get_player_name(), blow.weapon.desc .. ": " .. blow.text .. extra)
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
