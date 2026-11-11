-- orthoverse_armor: 3D Armor (mods/armor) fitted to the Orthoverse.
--
-- - What a player wears can be taken off and put back
--   (orthoverse.armor.worn / set_worn), so that creative mode and adventures
--   can put it aside with the rest of what they carry: armour taken from the
--   Creative tab never leaves the land, and a party goes into an adventure
--   with its kit.
-- - 3D Armor does not change a player's speed, jumping or gravity: it would
--   set those whenever armour is put on or taken off, over what the game sets
--   (combat, adventures). Heavy armour's cost in speed is ours (below).
-- - Armour works through an armour class (below), not 3D Armor's protection.
-- - The character's look stays the game's: orthoverse_skins gives 3D Armor the
--   skin to draw under the armour, and orthoverse_wield shows held items (3D
--   Armor's wieldview is not installed).

orthoverse = orthoverse or {}
orthoverse.armor = {}

-- Before 3D Armor's own join (which sets the physics the first time)
table.insert(core.registered_on_joinplayers, 1, function(player)
	player:get_meta():set_int("player_physics_locked", 1)
end)

local function worn_inventory(player)
	local _, inv = armor:get_valid_player(player, "[orthoverse_armor]")
	return inv
end

-- What the player wears, as item strings (empty slots as "")
function orthoverse.armor.worn(player)
	local inv = worn_inventory(player)
	local out = {}
	if not inv then return out end
	for i, stack in ipairs(inv:get_list("armor") or {}) do out[i] = stack:to_string() end
	return out
end

-- Dresses the player in `list` (as worn() gives it; an empty list takes
-- everything off), and shows it
function orthoverse.armor.set_worn(player, list)
	local inv = worn_inventory(player)
	if not inv then return end
	local items = {}
	for i = 1, inv:get_size("armor") do items[i] = ItemStack((list or {})[i] or "") end
	inv:set_list("armor", items)
	armor:save_armor_inventory(player)
	armor:set_player_armor(player)
end

------------------------------------------------------------------------------
-- Armour class (docs/combat-numbers.md, "Armour"). A player's armour class
-- is 10, plus what each piece they wear adds; a monster's blow is a d20
-- roll plus the monster's attack bonus (3 + half its level) against it:
-- at or over, it hits in full; up to GLANCE under, it glances off (half the
-- damage); further under, it misses. A natural 20 always hits, a natural 1
-- always misses. 3D Armor's own protection (taking a share off every blow)
-- is turned off: armour works through the roll. Breath, explosions and the
-- like are not blows: armour does not turn them (Mobs Redo's explosions punch
-- with the player's own object; the wyrm's fire is marked with unrolled()).
--
-- Heavy armour is slow: each piece takes its share of a full set's cost off
-- walking speed (orthoverse_combat's footwork applies it).

-- What a full set (helmet, chestplate, leggings and boots) adds to armour
-- class, and what it costs in walking speed; a shield's on its own
local FULL = {
	wood    = {ac = 2, slow = 0},
	gold    = {ac = 4, slow = 0.10},
	bronze  = {ac = 5, slow = 0.08},
	steel   = {ac = 6, slow = 0.07},
	diamond = {ac = 7, slow = 0.03},
}
local SHIELD = {
	wood    = {ac = 1, slow = 0},
	gold    = {ac = 2, slow = 0.03},
	bronze  = {ac = 2, slow = 0.02},
	steel   = {ac = 2, slow = 0.02},
	diamond = {ac = 2, slow = 0.01},
}
-- Each piece's share of a full set
local SHARE = {head = 0.15, torso = 0.4, legs = 0.3, feet = 0.15}
local GLANCE = 5

orthoverse.armor.FULL, orthoverse.armor.SHIELD, orthoverse.armor.SHARE = FULL, SHIELD, SHARE

local worn_stats = {}   -- name -> {ac, speed}

local function stats_of(player)
	local add, slow = 0, 0
	for _, it in ipairs(orthoverse.armor.worn(player)) do
		local stack = ItemStack(it)
		if not stack:is_empty() then
			local element = armor:get_element(stack:get_name())
			local material = stack:get_name():match("_(%a+)$")
			if element == "shield" and SHIELD[material] then
				add, slow = add + SHIELD[material].ac, slow + SHIELD[material].slow
			elseif SHARE[element] and FULL[material] then
				add = add + SHARE[element] * FULL[material].ac
				slow = slow + SHARE[element] * FULL[material].slow
			end
		end
	end
	return {ac = 10 + math.floor(add + 0.5), speed = 1 - slow}
end

-- The shield a player wears (its material), or nil
function orthoverse.armor.shield(player)
	for _, it in ipairs(orthoverse.armor.worn(player)) do
		local stack = ItemStack(it)
		if not stack:is_empty() and armor:get_element(stack:get_name()) == "shield" then
			return stack:get_name():match("_(%a+)$") or "steel"
		end
	end
end

-- A player's armour class (10 with nothing on)
function orthoverse.armor.ac(player)
	local s = worn_stats[player:get_player_name()]
	return s and s.ac or 10
end

-- The share of walking speed their armour leaves them
function orthoverse.armor.speed(player)
	local s = worn_stats[player:get_player_name()]
	return s and s.speed or 1
end

-- A monster's attack bonus, from its level
function orthoverse.armor.attack_bonus(level)
	return 3 + math.floor((tonumber(level) or 0) / 2)
end

-- Damage done inside fn is not a blow (no roll against armour)
local unrolled_depth = 0
function orthoverse.armor.unrolled(fn)
	unrolled_depth = unrolled_depth + 1
	local ok, err = pcall(fn)
	unrolled_depth = unrolled_depth - 1
	if not ok then error(err, 0) end
end

armor:register_on_update(function(player)
	worn_stats[player:get_player_name()] = stats_of(player)
	-- no share off every blow: the roll does armour's work
	local groups = player:get_armor_groups()
	if groups.fleshy ~= 100 then
		groups.fleshy = 100
		player:set_armor_groups(groups)
	end
end)

core.register_on_leaveplayer(function(player)
	worn_stats[player:get_player_name()] = nil
end)

-- The Armor tab shows the armour class and walking speed, not 3D Armor's
-- level, heal and fire (heal is turned off, and none of our materials
-- give fire protection)
local armor_formspec = armor.get_armor_formspec
armor.get_armor_formspec = function(self, name, listring)
	local fs = armor_formspec(self, name, listring)
	local player = core.get_player_by_name(name)
	if not player then return fs end
	local speed = math.floor(orthoverse.armor.speed(player) * 100 + 0.5)
	local labels = ("label[5,1;Armour class: %d]label[5,1.5;Walking speed: %d%%%%]"):format(orthoverse.armor.ac(player), speed)
	fs = fs:gsub("label%[5,1%.5;[^%]]*%]", ""):gsub("label%[5,2;[^%]]*%]", "")
	return (fs:gsub("label%[5,1;[^%]]*%]", labels, 1))
end

-- A word on the screen, for a moment
local shown = {}   -- name -> hud id
local function flash(player, text)
	local name = player:get_player_name()
	if shown[name] then player:hud_remove(shown[name]) end
	local id = player:hud_add({type = "text", position = {x = 0.5, y = 0.62}, text = text, number = 0xD8D8D8,
		alignment = {x = 0, y = 0}, offset = {x = 0, y = 0}, size = {x = 1, y = 1}, z_index = 10})
	shown[name] = id
	core.after(0.9, function()
		local p = core.get_player_by_name(name)
		if p and shown[name] == id then p:hud_remove(id); shown[name] = nil end
	end)
end

------------------------------------------------------------------------------
-- Wear. Only blows that land wear armour, each piece as much as its
-- material can take (LIFE: full hits a piece lasts, whatever else is worn):
-- a hit wears every piece worn, a glance half as much, a miss nothing; a
-- blocked blow wears only the shield. 3D Armor's own wear (every punch,
-- falls and burns too, shared out among the pieces worn) is off. The wear
-- bar shows on each piece, and the chat warns when one is nearly worn out.

local LIFE = {wood = 60, gold = 120, bronze = 150, steel = 250, diamond = 500}
orthoverse.armor.LIFE = LIFE

armor.punch = function() end

local function wear(player, share, shield_only)
	local _, inv = armor:get_valid_player(player, "[orthoverse_armor wear]")
	if not inv then return end
	for i, stack in ipairs(inv:get_list("armor") or {}) do
		if not stack:is_empty() then
			local element = armor:get_element(stack:get_name())
			local life = LIFE[stack:get_name():match("_(%a+)$") or ""]
			if life and element and (not shield_only or element == "shield") then
				-- (3D Armor shares the wear out among the pieces worn: undone)
				local n = 0
				for _ in pairs(armor:get_weared_armor_elements(player) or {}) do n = n + 1 end
				armor:damage(player, i, stack, math.ceil(65535 / life * share) * math.max(1, n))
			end
		end
	end
end
orthoverse.armor.wear = wear

core.register_on_player_hpchange(function(player, change, reason)
	if change >= 0 or unrolled_depth > 0 or not reason or reason.type ~= "punch" or not reason.object then
		return change
	end
	local ent = reason.object:get_luaentity()
	if not ent or not ent._orthoverse_target or not ent._level or ent.attack_type == "explode" then return change end
	local roll = math.random(20)
	local total = roll + orthoverse.armor.attack_bonus(ent._level)
	local ac = orthoverse.armor.ac(player)
	local hit = roll == 20 or (roll > 1 and total >= ac)
	local glance = not hit and roll > 1 and total >= ac - GLANCE
	-- A raised shield (orthoverse_combat: right mouse button) takes a blow
	-- from the front: a hit does half, a glance nothing
	local c = orthoverse.combat
	if (hit or glance) and c and c.blocking and c.blocking(player, reason.object:get_pos()) then
		local shield = orthoverse.armor.shield(player)
		core.sound_play(shield == "wood" and "default_dig_choppy" or "default_dig_cracky",
			{to_player = player:get_player_name(), gain = 0.7, pitch = 0.8}, true)
		wear(player, hit and 1 or 0.5, true)
		if glance then
			flash(player, "Blocked")
			return 0
		end
		flash(player, "Blocked: half the blow")
		return math.min(-1, math.ceil(change / 2))
	end
	if hit then
		wear(player, 1)
		return change
	end
	if glance then
		wear(player, 0.5)
		flash(player, ac > 10 and "Glances off your armour" or "A glancing blow")
		core.sound_play("default_dig_cracky", {to_player = player:get_player_name(), gain = 0.5, pitch = 1.3}, true)
		return math.min(-1, math.ceil(change / 2))
	end
	flash(player, "Missed")
	return 0
end, true)
