-- orthoverse_creative: creative mode on your own lands, more of it the higher
-- the land's castle level.
--
-- On a land your wallet holds, from castle level 2, you are in creative mode:
-- every block in the inventory's Creative tab, nothing used up, no damage. A
-- croft (level 0) is common land, where everyone builds with what they carry,
-- holder included, so there is no creative mode there (creative blocks would
-- end up in other players' hands). At level 1 the land is yours alone, and
-- you build with what you carry. In creative mode your own inventory is
-- put away and your creative one (empty the first time, then as you left it)
-- takes its place. Step off the land and it all goes back, so nothing taken
-- from the Creative tab ever leaves the land.
--
-- The land's castle level adds abilities (LEVELS below; the contract's levels
-- 8-15 are 0-7 with the futuristic style flag, so they count as 0-7). They
-- follow the land you stand on: walk from a level 2 land of yours to a level 0
-- one and fly and noclip go. Abilities that are not on the land itself
-- (/goto, arriving where you click on the map) are in orthoverse_lands and
-- orthoverse_wallets; they are listed here only for the hints.
--
-- Players who can build anywhere (protection_bypass: the admin) are left alone.
-- orthoverse.creative.allowed decides where a player is creative: other mods
-- can extend it (lands shared with a player, homesteads).

local S = core.get_translator and core.get_translator("orthoverse_creative") or function(s) return s end

-- What each castle level adds, on top of the levels below it. Privileges here
-- are granted while the player stands on the land and taken away when they
-- leave it; `dig` is the instant-digging hand. To move an ability to another
-- level, move it here (and in the website's list, web/site/account). `also`
-- names abilities that live elsewhere, for the hints.
local LEVELS = {
	[2] = { privs = { "creative" } },
	[3] = { privs = { "fly" } },
	[4] = { privs = { "fast" } },
	[5] = { privs = { "noclip" } },
	[6] = { dig = true, also = { "/goto to any land" } },
	[7] = { also = { "arriving anywhere you click on the map" } },
}
local CREATIVE_LEVEL = 2
local PRIV_NAMES = { fly = "fly (K)", fast = "fast (J)", noclip = "noclip (H)" }
local DIG_NAME = "instant digging with your hand"

local LISTS = { "main", "craft" }
local KEY = "orthoverse_creative:"      -- player meta keys
local CHECK_EVERY = 0.5

orthoverse.creative = { LEVELS = LEVELS }

-- Whether `name` is creative at `pos`: on a land their wallet holds, at castle
-- level 2 or more (in either realm)
function orthoverse.creative.allowed(name, pos)
	local w = orthoverse.wallets
	if w.is_guest(name) then return false end
	local land, key = orthoverse.land_at(pos)
	if not land or orthoverse.henges[key] or (tonumber(land.level) or 0) % 8 < CREATIVE_LEVEL then return false end
	local wallet = w.wallet_of(name)
	return wallet ~= nil and wallet == w.owner_of(land)
end

-- The land's level at `pos` for `name` (0-7), or nil if they are not creative
-- there. The contract's levels 8-15 are 0-7 with the futuristic style flag set
function orthoverse.creative.level_at(name, pos)
	if not orthoverse.creative.allowed(name, pos) then return nil end
	local land = orthoverse.land_at(pos)
	return (land and tonumber(land.level) or 0) % 8
end

-- The privileges a level gives (a set)
local function privs_for(level)
	local out = {}
	for l = 0, level do
		for _, p in ipairs((LEVELS[l] or {}).privs or {}) do out[p] = true end
	end
	return out
end

local ALL_PRIVS = privs_for(7)

-- Whether a level gives the instant-digging hand
local function digs_at(level)
	for l = 0, level do
		if (LEVELS[l] or {}).dig then return true end
	end
	return false
end

-- What one level adds, as names
local function names_at(l)
	local def = LEVELS[l] or {}
	local names = {}
	for _, p in ipairs(def.privs or {}) do
		if p ~= "creative" then names[#names + 1] = PRIV_NAMES[p] or p end
	end
	if def.dig then names[#names + 1] = DIG_NAME end
	for _, a in ipairs(def.also or {}) do names[#names + 1] = a end
	return names
end

-- The next level that adds something, and what it adds (for the hint)
local function next_ability(level)
	for l = level + 1, 7 do
		local names = names_at(l)
		if #names > 0 then return l, table.concat(names, " and ") end
	end
end

local function exempt(name)
	return core.check_player_privs(name, { protection_bypass = true })
end

------------------------------------------------------------------------------
-- Inventories

local function save_lists(player, which)
	local inv = player:get_inventory()
	local out = {}
	for _, list in ipairs(LISTS) do
		local items = {}
		for i, stack in ipairs(inv:get_list(list) or {}) do items[i] = stack:to_string() end
		out[list] = items
	end
	player:get_meta():set_string(KEY .. which, core.serialize(out))
end

local function load_lists(player, which)
	local inv = player:get_inventory()
	local saved = core.deserialize(player:get_meta():get_string(KEY .. which)) or {}
	for _, list in ipairs(LISTS) do
		local size = inv:get_size(list)
		local items = {}
		for i = 1, size do items[i] = ItemStack((saved[list] or {})[i] or "") end
		inv:set_list(list, items)
	end
end

local function refresh_inventory_page(player)
	if sfinv.get_page(player):sub(1, 9) == "creative:" and
			not core.check_player_privs(player, { creative = true }) then
		sfinv.set_page(player, sfinv.get_homepage_name(player))
	else
		sfinv.set_player_inventory_formspec(player)
	end
end

------------------------------------------------------------------------------
-- Instant digging: a hand in the player's "hand" list, which Luanti uses in
-- place of the usual one when they hold nothing. Only ever there while they
-- are in creative mode on a land of that level.

local HAND = "orthoverse_creative:hand"
local digtime = 42      -- as Minetest Game's creative hand: maxlevel 256 makes it ~0.16 s
local caps = { times = { digtime, digtime, digtime }, uses = 0, maxlevel = 256 }
core.register_tool(HAND, {
	description = "Instant digging",
	inventory_image = "wieldhand.png",
	wield_image = "wieldhand.png",
	wield_scale = { x = 1, y = 1, z = 2.5 },
	range = 10,
	groups = { not_in_creative_inventory = 1 },
	tool_capabilities = {
		full_punch_interval = 0.9,
		max_drop_level = 0,
		groupcaps = {
			crumbly = caps, cracky = caps, snappy = caps, choppy = caps,
			oddly_breakable_by_hand = caps,
			dig_immediate = { times = { [2] = digtime, [3] = 0 }, uses = 0, maxlevel = 256 },
		},
		damage_groups = { fleshy = 1 },
	},
	on_drop = function(itemstack) return itemstack end,
})

local function set_hand(player, on)
	local inv = player:get_inventory()
	if on then
		if inv:get_size("hand") < 1 then inv:set_size("hand", 1) end
		inv:set_stack("hand", 1, ItemStack(HAND))
	elseif inv:get_size("hand") > 0 then
		inv:set_size("hand", 0)
	end
end

------------------------------------------------------------------------------
-- Privileges, entering and leaving

local falling = {}      -- name -> true: no fall damage until on the ground again
local last_safe = {}    -- name -> last position on their land outside any block

local function is_creative(player)
	return player:get_meta():get_string(KEY .. "on") == "1"
end

local function inside_block(pos)
	for dy = 0, 1 do
		local node = core.get_node_or_nil(vector.offset(vector.round(pos), 0, dy, 0))
		local def = node and core.registered_nodes[node.name]
		if def and def.walkable then return true end
	end
	return false
end

-- Give the player the privileges in `wanted` (a set) that this mod hands out,
-- and take away the ones it gave that are no longer wanted. Privileges the
-- player had anyway are never touched. Returns the lists granted and removed.
local function set_privs(player, wanted)
	local name = player:get_player_name()
	local meta = player:get_meta()
	local granted = {}
	for p in meta:get_string(KEY .. "granted"):gmatch("[^,]+") do granted[p] = true end
	local privs = core.get_player_privs(name)
	local added, removed = {}, {}
	for p in pairs(ALL_PRIVS) do
		if wanted[p] and not privs[p] then
			privs[p] = true
			granted[p] = true
			added[#added + 1] = p
		elseif not wanted[p] and granted[p] then
			privs[p] = nil
			granted[p] = nil
			removed[#removed + 1] = p
		end
	end
	if #added > 0 or #removed > 0 then
		core.set_player_privs(name, privs)
		local list = {}
		for p in pairs(granted) do list[#list + 1] = p end
		table.sort(list)
		meta:set_string(KEY .. "granted", table.concat(list, ","))
	end
	local lost = {}
	for _, p in ipairs(removed) do lost[p] = true end
	-- Lost fly: no fall damage until they land. Lost noclip inside a wall:
	-- back to where they last stood in the open on their land
	if lost.fly then falling[name] = true end
	if lost.noclip and inside_block(player:get_pos()) and last_safe[name] then
		player:set_pos(last_safe[name])
	end
	return added, removed
end

-- What `level` gives, and what the next level up would add
local function abilities_text(level)
	local names = {}
	for p in pairs(privs_for(level)) do
		if PRIV_NAMES[p] then names[#names + 1] = PRIV_NAMES[p] end
	end
	table.sort(names)
	if digs_at(level) then names[#names + 1] = DIG_NAME end
	local text = S("Every block is in the inventory's Creative tab")
	if #names > 0 then text = text .. "; " .. table.concat(names, ", ") end
	text = text .. "."
	local l, more = next_ability(level)
	if l then
		text = text .. " " .. S("A castle at level @1 would add @2.", l, more)
	end
	return text
end

local function enter(player, level)
	local name = player:get_player_name()
	local meta = player:get_meta()
	save_lists(player, "own")
	load_lists(player, "creative")
	meta:set_string(KEY .. "on", "1")
	meta:set_int(KEY .. "level", level)
	set_privs(player, privs_for(level))
	set_hand(player, digs_at(level))
	refresh_inventory_page(player)
	core.chat_send_player(name, S("Your land (level @1): creative mode. Your own inventory is kept safe until you leave.", level) ..
		" " .. abilities_text(level))
end

-- Moving between your own lands of different levels (or the level changing
-- on the chain while you stand there)
local function change_level(player, level)
	local meta = player:get_meta()
	if meta:get_int(KEY .. "level") == level then return end
	meta:set_int(KEY .. "level", level)
	local added, removed = set_privs(player, privs_for(level))
	local had = player:get_inventory():get_size("hand") > 0
	set_hand(player, digs_at(level))
	if #added > 0 or #removed > 0 or had ~= digs_at(level) then
		core.chat_send_player(player:get_player_name(),
			S("This land is level @1.", level) .. " " .. abilities_text(level))
	end
end

local function leave(player, quiet)
	local name = player:get_player_name()
	local meta = player:get_meta()
	save_lists(player, "creative")
	load_lists(player, "own")
	set_privs(player, {})      -- also sees to leaving through walls
	set_hand(player, false)
	meta:set_string(KEY .. "granted", "")
	meta:set_string(KEY .. "on", "")
	refresh_inventory_page(player)
	falling[name] = true
	if not quiet then
		core.chat_send_player(name, S("You have left your land: creative mode is off, and your own inventory is back."))
	end
end

core.register_globalstep((function()
	local t = 0
	return function(dtime)
		t = t + dtime
		if t < CHECK_EVERY then return end
		t = 0
		for _, player in ipairs(core.get_connected_players()) do
			local name = player:get_player_name()
			if not exempt(name) then
				local pos = player:get_pos()
				local level = orthoverse.creative.level_at(name, pos)
				local on = is_creative(player)
				if level and not on then
					enter(player, level)
				elseif on and not level then
					leave(player)
				elseif level then
					change_level(player, level)
				end
				if level and not inside_block(pos) then
					last_safe[name] = pos
				end
			end
			-- On the ground again after leaving in the air
			if falling[name] and player:get_velocity().y > -0.5 then
				local below = core.get_node_or_nil(vector.offset(vector.round(player:get_pos()), 0, -1, 0))
				local def = below and core.registered_nodes[below.name]
				if def and (def.walkable or def.liquidtype ~= "none") then falling[name] = nil end
			end
		end
	end
end)())

-- A player who left (or crashed) in creative mode is put right when they
-- join, wherever they are; the check above turns creative on again if they
-- are on their land
core.register_on_joinplayer(function(player)
	if is_creative(player) then leave(player, true) end
	set_hand(player, false)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	falling[name], last_safe[name] = nil, nil
end)

------------------------------------------------------------------------------
-- What could carry creative blocks off the land, or hurt a creative player

-- No damage in creative mode, and no fall damage just after leaving it
core.register_on_player_hpchange(function(player, change, reason)
	if change >= 0 then return change end
	local name = player:get_player_name()
	if is_creative(player) and reason.type ~= "set_hp" then return 0 end
	if falling[name] and reason.type == "fall" then
		falling[name] = nil
		return 0
	end
	return change
end, true)

-- Dropping a creative block throws it away instead of onto the ground, where
-- it could be picked up off the land
local old_item_drop = core.item_drop
function core.item_drop(itemstack, dropper, pos)
	if dropper and dropper.is_player and dropper:is_player() and is_creative(dropper) then
		return ItemStack("")
	end
	return old_item_drop(itemstack, dropper, pos)
end

-- Reaching onto your land from just off it, with your own inventory: no
-- digging there (blocks placed in creative mode would come away in your own
-- inventory) and no building either. Step onto the land first.
local function reaching_in(name, pos)
	if exempt(name) or not orthoverse.creative.allowed(name, pos) then return false end
	local player = core.get_player_by_name(name)
	return player ~= nil and not is_creative(player)
end

local old_is_protected = core.is_protected
function core.is_protected(pos, name)
	if name and name ~= "" and reaching_in(name, pos) then return true end
	return old_is_protected(pos, name)
end

local last_told = {}
core.register_on_protection_violation(function(pos, name)
	if not name or not reaching_in(name, pos) then return end
	local now = core.get_us_time()
	if last_told[name] and now - last_told[name] < 3000000 then return end
	last_told[name] = now
	core.chat_send_player(name, S("Step onto your land to build there."))
end)

-- Chests, furnaces, shelves and every other block with an inventory: only
-- those who may build where it stands may put things in or take them out
-- (core.is_protected: the holder on a private land, anyone signed in on a
-- croft, the admin anywhere). So a chest filled in creative mode cannot be
-- emptied by visitors, and nothing filled in creative mode is taken from your
-- land with your own inventory (reaching in from just off it).
local function no_access(player, pos)
	local name = player and player:get_player_name() or ""
	return name ~= "" and core.is_protected(pos, name)
end

core.register_on_mods_loaded(function()
	for nodename, def in pairs(core.registered_nodes) do
		if def.on_metadata_inventory_put or def.on_metadata_inventory_take or
				def.allow_metadata_inventory_take or def.allow_metadata_inventory_put or
				def.allow_metadata_inventory_move or (def.groups or {}).container then
			local take, put, move = def.allow_metadata_inventory_take,
				def.allow_metadata_inventory_put, def.allow_metadata_inventory_move
			local rightclick = def.on_rightclick
			local override = {
				allow_metadata_inventory_take = function(pos, listname, index, stack, player)
					if no_access(player, pos) then return 0 end
					return take and take(pos, listname, index, stack, player) or stack:get_count()
				end,
				allow_metadata_inventory_put = function(pos, listname, index, stack, player)
					if no_access(player, pos) then return 0 end
					return put and put(pos, listname, index, stack, player) or stack:get_count()
				end,
				allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
					if no_access(player, pos) then return 0 end
					return move and move(pos, from_list, from_index, to_list, to_index, count, player) or count
				end,
			}
			-- Opening it at all (chests): say why not, instead of showing
			-- contents that cannot be touched
			if rightclick then
				override.on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
					if clicker and clicker:is_player() and no_access(clicker, pos) then
						core.record_protection_violation(pos, clicker:get_player_name())
						return itemstack
					end
					return rightclick(pos, node, clicker, itemstack, pointed_thing)
				end
			end
			core.override_item(nodename, override)
		end
	end
end)
