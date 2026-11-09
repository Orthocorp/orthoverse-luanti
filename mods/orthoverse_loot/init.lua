-- orthoverse_loot: what adventurers find and fight with.
--
-- * Loot chests, placed by an adventure's builder. In a run, each player who
--   opens one finds their own share (nobody squabbles over a chest), filled
--   from our tables, never from the builder's inventory: so a builder in
--   creative mode cannot hand out free gear. What a chest may give is capped
--   by the adventure's top rank (an adventure for ranks 1 to 5 gives at most
--   bronze; mese from 6, diamond from 10). Three kinds:
--     common:  a healing draught or two, now and then a weapon
--     weapon:  a weapon, and a draught
--     finish:  the best metal the adventure allows, once a day for each
--              player (a common share after that)
-- * Healing draughts (8 health), found only in chests.
-- * Recipes for the weapons (orthoverse_combat), from ingots, mese
--   crystals or diamonds and sticks: weapons are ordinary items, made or
--   found, and a weapon's metal counts in full only from a rank
--   (orthoverse_rank).
-- * A steel short sword for anyone who enters an adventure with no weapon.

local S = core.get_translator and core.get_translator("orthoverse_loot") or function(s) return s end

orthoverse = orthoverse or {}
orthoverse.loot = {}

local KINDS = {"dagger", "short_sword", "broadsword", "spear", "mace", "morning_star", "war_hammer"}
local METALS = {{id = "steel", rank = 1}, {id = "bronze", rank = 3}, {id = "mese", rank = 6}, {id = "diamond", rank = 10}}
local CHEST_KINDS = {"common", "weapon", "finish"}
local CHEST_LABEL = {common = "Common (draughts, now and then a weapon)", weapon = "Weapon (a weapon and a draught)",
	finish = "Finish (the best metal allowed, once a day each)"}
local DEFAULT_TOP_RANK = 5

------------------------------------------------------------------------------
-- The healing draught

core.register_craftitem("orthoverse_loot:draught", {
	description = S("Healing draught") .. "\n" .. S("Drink (use) to heal 8 health"),
	inventory_image = "orthoverse_loot_draught.png",
	stack_max = 10,
	on_use = function(itemstack, user)
		if not user or not user:is_player() then return itemstack end
		local max = user:get_properties().hp_max
		if user:get_hp() >= max then return itemstack end
		user:set_hp(math.min(max, user:get_hp() + 8), {type = "set_hp", from = "mod", orthoverse_draught = true})
		core.sound_play("default_water_footstep", {pos = user:get_pos(), gain = 0.6, pitch = 1.4, max_hear_distance = 8}, true)
		itemstack:take_item()
		return itemstack
	end,
})

------------------------------------------------------------------------------
-- What a chest gives

-- Metals an adventure up to `top` rank may give
local function metals_for(top)
	local out = {}
	for _, m in ipairs(METALS) do
		if m.rank <= top then out[#out + 1] = m.id end
	end
	return out
end

local function weapon(metal)
	return "orthoverse_combat:" .. KINDS[math.random(#KINDS)] .. "_" .. metal
end

-- A metal from those allowed, the lower ones more often (the best is rare)
local function some_metal(allowed)
	local n = #allowed
	local r = math.random()
	for i = 1, n do
		if r < 0.6 or i == n then return allowed[i] end
		r = (r - 0.6) / 0.4
	end
end

local function fill(kind, top)
	local allowed = metals_for(top)
	local out = {}
	if kind == "finish" then
		out[#out + 1] = weapon(allowed[#allowed])
		out[#out + 1] = "orthoverse_loot:draught 2"
	elseif kind == "weapon" then
		out[#out + 1] = weapon(some_metal(allowed))
		out[#out + 1] = "orthoverse_loot:draught"
	else
		out[#out + 1] = "orthoverse_loot:draught " .. math.random(1, 2)
		if math.random() < 0.35 then out[#out + 1] = weapon(some_metal(allowed)) end
	end
	return out
end
orthoverse.loot.fill = fill
orthoverse.loot.metals_for = metals_for

------------------------------------------------------------------------------
-- Loot chests

local CHEST = "orthoverse_loot:chest"
local shares = {}   -- "<run>|<pos>|<player>" -> list of item strings left in that player's share

local function top_rank(def)
	return (def and tonumber(def.rank_max)) or DEFAULT_TOP_RANK
end

local function adventure_here(pos)
	local ad = orthoverse.adventure
	if not (ad and ad.at) then return nil end
	return ad.at(pos)
end

local function may_set(name, pos)
	local key = adventure_here(pos)
	local ad = orthoverse.adventure
	if key and ad.may_manage then return ad.may_manage(name, key) end
	return core.check_player_privs(name, {protection_bypass = true}) or not core.is_protected(pos, name)
end

local function today() return os.date("!%Y-%m-%d") end

-- Once a day a player may take the finish chest's best share in an adventure
local function finish_taken(player, key)
	local meta = player:get_meta()
	local raw = meta:get_string("orthoverse_loot:finish")
	local t = raw ~= "" and core.parse_json(raw) or {}
	if t.day ~= today() then t = {day = today(), keys = {}} end
	local taken = t.keys[key]
	t.keys[key] = true
	meta:set_string("orthoverse_loot:finish", core.write_json(t))
	return taken
end

local function setup_formspec(pos)
	local meta = core.get_meta(pos)
	local kind = meta:get_string("kind")
	if kind == "" then kind = "common" end
	local items, sel = {}, 1
	for i, k in ipairs(CHEST_KINDS) do
		items[#items + 1] = core.formspec_escape(CHEST_LABEL[k])
		if k == kind then sel = i end
	end
	local spos = pos.x .. "," .. pos.y .. "," .. pos.z
	return "formspec_version[4]size[9,4.6]" ..
		"label[0.4,0.6;" .. core.formspec_escape(S("Loot chest: in a run, each player finds their own share.")) .. "]" ..
		"label[0.4,1.2;" .. core.formspec_escape(S("What it gives is capped by the adventure's top rank.")) .. "]" ..
		"dropdown[0.4,1.8;8.2,0.8;kind;" .. table.concat(items, ",") .. ";" .. sel .. ";true]" ..
		"button_exit[0.4,3.3;3,0.9;save;" .. S("Save") .. "]" ..
		"field[0,0;0,0;pos;;" .. spos .. "]"
end

local function share_formspec(name, id)
	return "formspec_version[4]size[10.5,9.2]" ..
		"label[0.4,0.6;" .. core.formspec_escape(S("Your share of the chest")) .. "]" ..
		"list[detached:orthoverse_loot_" .. name .. ";main;0.4,1;8,1;]" ..
		"label[0.4,2.6;" .. core.formspec_escape(S("Your inventory")) .. "]" ..
		"list[current_player;main;0.4,3;8,4;]" ..
		"listring[detached:orthoverse_loot_" .. name .. ";main]listring[current_player;main]"
end

-- Each player's view of the share they have open
local open_share = {}   -- name -> share id

local function share_inv(name)
	local inv = core.get_inventory({type = "detached", name = "orthoverse_loot_" .. name})
	if inv then return inv end
	inv = core.create_detached_inventory("orthoverse_loot_" .. name, {
		allow_put = function() return 0 end,
		allow_move = function() return 0 end,
		-- Only while the share is open: once closed, the detached list is
		-- emptied, and the share lives on in `shares` alone (so a client that
		-- keeps taking after closing cannot take the same items twice)
		allow_take = function(_, _, _, stack, player)
			return player:get_player_name() == name and open_share[name] and stack:get_count() or 0
		end,
		on_take = function(dinv)
			local id = open_share[name]
			if not id then return end
			local left = {}
			for _, st in ipairs(dinv:get_list("main")) do
				if not st:is_empty() then left[#left + 1] = st:to_string() end
			end
			shares[id] = left
		end,
	}, name)
	inv:set_size("main", 8)
	return inv
end

local function close_share(name)
	open_share[name] = nil
	local inv = core.get_inventory({type = "detached", name = "orthoverse_loot_" .. name})
	if inv then inv:set_list("main", {}) end
end

local function open_chest(pos, player)
	local name = player:get_player_name()
	local ad = orthoverse.adventure
	local key, def = adventure_here(pos)
	local run = key and ad.runs and ad.runs[key]
	if not (run and run.members[name]) then
		core.chat_send_player(name, key and S("Loot chests open for adventurers in a run.")
			or S("A loot chest gives its loot only inside an adventure."))
		return
	end
	local id = ("%s|%s|%s"):format(run.started, core.pos_to_string(pos), name)
	if not shares[id] then
		local kind = core.get_meta(pos):get_string("kind")
		if kind == "" then kind = "common" end
		if kind == "finish" and finish_taken(player, key) then kind = "common" end
		shares[id] = fill(kind, top_rank(def))
		core.sound_play("default_chest_open", {pos = pos, gain = 0.4, max_hear_distance = 10}, true)
	end
	local inv = share_inv(name)
	inv:set_list("main", {})
	for i, st in ipairs(shares[id]) do inv:set_stack("main", i, ItemStack(st)) end
	open_share[name] = id
	core.show_formspec(name, "orthoverse_loot:share", share_formspec(name, id))
end

core.register_node(CHEST, {
	description = S("Loot chest") .. "\n" .. S("For adventures: each player in a run finds their own share; right-click to set what it gives"),
	tiles = {"default_chest_top.png^[multiply:#f0d090", "default_chest_top.png^[multiply:#f0d090",
		"default_chest_side.png^[multiply:#f0d090", "default_chest_side.png^[multiply:#f0d090",
		"default_chest_side.png^[multiply:#f0d090", "default_chest_front.png^[multiply:#f0d090"},
	paramtype2 = "facedir",
	groups = {choppy = 2, oddly_breakable_by_hand = 2},
	is_ground_content = false,
	sounds = rawget(_G, "default") and default.node_sound_wood_defaults() or nil,
	on_construct = function(pos)
		core.get_meta(pos):set_string("kind", "common")
		core.get_meta(pos):set_string("infotext", S("Loot chest"))
	end,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local key, def = adventure_here(pos)
		local in_run = key and orthoverse.adventure.runs[key] and orthoverse.adventure.runs[key].members[name]
		if not in_run and may_set(name, pos) then
			core.show_formspec(name, "orthoverse_loot:setup", setup_formspec(pos))
		else
			open_chest(pos, clicker)
		end
	end,
	can_dig = function(pos, player) return player and may_set(player:get_player_name(), pos) end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	local name = player:get_player_name()
	if formname == "orthoverse_loot:share" then
		if fields.quit then close_share(name) end
		return true
	end
	if formname ~= "orthoverse_loot:setup" then return end
	local pos = fields.pos and core.string_to_pos("(" .. fields.pos .. ")")
	if not pos or core.get_node(pos).name ~= CHEST or not may_set(name, pos) then return true end
	if fields.save or fields.kind then
		local i = tonumber(fields.kind)
		if i and CHEST_KINDS[i] then
			local meta = core.get_meta(pos)
			meta:set_string("kind", CHEST_KINDS[i])
			meta:set_string("infotext", S("Loot chest") .. " (" .. CHEST_KINDS[i] .. ")")
		end
	end
	return true
end)

core.register_on_leaveplayer(function(player) close_share(player:get_player_name()) end)

------------------------------------------------------------------------------
-- A weapon for anyone who goes in without one

local function has_weapon(player)
	for _, st in ipairs(player:get_inventory():get_list("main") or {}) do
		if core.get_item_group(st:get_name(), "orthoverse_weapon") > 0 then return true end
	end
	return false
end

core.register_on_mods_loaded(function()
	local ad = orthoverse.adventure
	if not (ad and ad.on_enter) then return end
	table.insert(ad.on_enter, function(player)
		if has_weapon(player) then return end
		local left = player:get_inventory():add_item("main", "orthoverse_combat:short_sword_steel")
		if left:is_empty() then
			core.chat_send_player(player:get_player_name(),
				S("You go in empty-handed, so the gatekeeper gives you a steel short sword."))
		end
	end)
end)

------------------------------------------------------------------------------
-- Recipes for the weapons: the metal (an ingot, a mese crystal or a diamond)
-- and sticks, a different shape for each kind (none clashes with Minetest
-- Game's tools)

local MATERIAL_ITEM = {steel = "default:steel_ingot", bronze = "default:bronze_ingot",
	mese = "default:mese_crystal", diamond = "default:diamond"}
local SHAPES = {
	dagger = {{"m"}, {"s"}},
	short_sword = {{"m"}, {"m"}, {"s"}},
	broadsword = {{"", "m", ""}, {"", "m", ""}, {"m", "s", "m"}},
	spear = {{"", "", "m"}, {"", "s", ""}, {"s", "", ""}},
	mace = {{"", "m", "m"}, {"", "s", "m"}, {"s", "", ""}},
	morning_star = {{"", "m", ""}, {"m", "s", "m"}, {"", "s", ""}},
	war_hammer = {{"m", "m", "m"}, {"m", "s", "m"}, {"", "s", ""}},
}

if core.registered_items["default:stick"] then
	for kind, shape in pairs(SHAPES) do
		for metal, item in pairs(MATERIAL_ITEM) do
			if core.registered_items[item] then
				local recipe = {}
				for r, row in ipairs(shape) do
					recipe[r] = {}
					for c, cell in ipairs(row) do
						recipe[r][c] = cell == "m" and item or cell == "s" and "default:stick" or ""
					end
				end
				core.register_craft({output = "orthoverse_combat:" .. kind .. "_" .. metal, recipe = recipe})
			end
		end
	end
end
