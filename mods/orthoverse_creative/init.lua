-- orthoverse_creative: creative mode on your own lands.
--
-- On a land your wallet holds you get fly, fast and noclip, the inventory's
-- creative tab (every block, nothing used up), and no damage. Your own
-- inventory is put away and your creative one (empty the first time, then as
-- you left it) takes its place. Step off the land and it all goes back: the
-- privileges are taken away, the creative inventory is put away, and your own
-- comes back, so nothing taken from the creative tab ever leaves the land.
--
-- Players who can build anywhere (protection_bypass: the admin) are left alone.
-- orthoverse.creative.allowed decides where a player is creative: other mods
-- can extend it (lands shared with a player, homesteads).

local S = core.get_translator and core.get_translator("orthoverse_creative") or function(s) return s end

local PRIVS = { "fly", "fast", "noclip", "creative" }
local LISTS = { "main", "craft" }
local KEY = "orthoverse_creative:"      -- player meta keys
local CHECK_EVERY = 0.5

orthoverse.creative = {}

-- Whether `name` is creative at `pos`: wherever they may build (their own lands)
function orthoverse.creative.allowed(name, pos)
	return orthoverse.wallets.may_build(name, pos) == true
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
-- Entering and leaving

local falling = {}      -- name -> true: no fall damage until on the ground again
local last_safe = {}    -- name -> last position on their land outside any block

local function is_creative(player)
	return player:get_meta():get_string(KEY .. "on") == "1"
end

local function enter(player)
	local name = player:get_player_name()
	local meta = player:get_meta()
	local privs = core.get_player_privs(name)
	local granted = {}
	for _, p in ipairs(PRIVS) do
		if not privs[p] then
			privs[p] = true
			granted[#granted + 1] = p
		end
	end
	core.set_player_privs(name, privs)
	meta:set_string(KEY .. "granted", table.concat(granted, ","))
	save_lists(player, "own")
	load_lists(player, "creative")
	meta:set_string(KEY .. "on", "1")
	refresh_inventory_page(player)
	core.chat_send_player(name, S("Your land: creative mode. Fly (K), fast (J), noclip (H), and every block in the inventory's Creative tab. Your own inventory is kept safe until you leave."))
end

local function inside_block(pos)
	for dy = 0, 1 do
		local node = core.get_node_or_nil(vector.offset(vector.round(pos), 0, dy, 0))
		local def = node and core.registered_nodes[node.name]
		if def and def.walkable then return true end
	end
	return false
end

local function leave(player, quiet)
	local name = player:get_player_name()
	local meta = player:get_meta()
	save_lists(player, "creative")
	load_lists(player, "own")
	local privs = core.get_player_privs(name)
	for p in meta:get_string(KEY .. "granted"):gmatch("[^,]+") do privs[p] = nil end
	core.set_player_privs(name, privs)
	meta:set_string(KEY .. "granted", "")
	meta:set_string(KEY .. "on", "")
	refresh_inventory_page(player)
	-- Leaving through walls with noclip: back to where they were on their land
	if inside_block(player:get_pos()) and last_safe[name] then
		player:set_pos(last_safe[name])
	end
	-- Leaving in the air: no fall damage until they land
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
				local here = orthoverse.creative.allowed(name, pos)
				local on = is_creative(player)
				if here and not on then
					enter(player)
				elseif on and not here then
					leave(player)
				end
				if here and not inside_block(pos) then
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

-- The same for chests, furnaces and shelves on your land: their contents
-- (filled in creative mode) stay on the land
core.register_on_mods_loaded(function()
	for nodename, def in pairs(core.registered_nodes) do
		if def.on_metadata_inventory_put or def.on_metadata_inventory_take or
				def.allow_metadata_inventory_take or def.allow_metadata_inventory_put or
				def.allow_metadata_inventory_move or (def.groups or {}).container then
			local take, put, move = def.allow_metadata_inventory_take,
				def.allow_metadata_inventory_put, def.allow_metadata_inventory_move
			core.override_item(nodename, {
				allow_metadata_inventory_take = function(pos, listname, index, stack, player)
					if reaching_in(player:get_player_name(), pos) then return 0 end
					return take and take(pos, listname, index, stack, player) or stack:get_count()
				end,
				allow_metadata_inventory_put = function(pos, listname, index, stack, player)
					if reaching_in(player:get_player_name(), pos) then return 0 end
					return put and put(pos, listname, index, stack, player) or stack:get_count()
				end,
				allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
					if reaching_in(player:get_player_name(), pos) then return 0 end
					return move and move(pos, from_list, from_index, to_list, to_index, count, player) or count
				end,
			})
		end
	end
end)
