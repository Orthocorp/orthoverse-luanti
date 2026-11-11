-- orthoverse_armor: 3D Armor (mods/armor) fitted to the Orthoverse.
--
-- - What a player wears can be taken off and put back
--   (orthoverse.armor.worn / set_worn), so that creative mode and adventures
--   can put it aside with the rest of what they carry: armour taken from the
--   Creative tab never leaves the land, and a party goes into an adventure
--   with its kit.
-- - Armour does not change a player's speed, jumping or gravity: 3D Armor
--   would set those whenever armour is put on or taken off, over what the
--   game sets (combat, adventures). For now armour only protects; what heavy
--   armour costs comes with the combat's armour class.
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
