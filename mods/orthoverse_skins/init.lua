-- orthoverse_skins: player skins.
--
-- A character wears the skin designed for it on the website (the Account
-- page): the auth service paints it and writes skins/<name>.png, with its
-- hash in registry.json (orthoverse_wallets). The game sends each picture to
-- every client as it runs (dynamic media, a new file name for each version),
-- so a new look reaches players already in the game, and puts it on the
-- player within a few seconds. Nobody chooses a skin in the game.
--
-- Guests, who cannot design one, each wear one of the skins below, picked
-- from their name; a character that has not designed one wears the default.
-- The skins are textures for Minetest Game's character model, in the 64 x 32
-- layout; any file in this mod's textures folder called
-- orthoverse_skin_<name>.png is a guest skin too (64 x 64 skins: their top
-- half).

local modpath = core.get_modpath(core.get_current_modname())
local PREFIX = "orthoverse_skin_"

-- Built-in skins, in the order they are shown: key, label, texture
local BUILT_IN = {
	{"default", "Default", "character.png"},
	{"wizard", "Wizard", PREFIX .. "wizard.png"},
	{"elf", "Elf", PREFIX .. "elf.png"},
	{"borgo", "Borgo", PREFIX .. "borgo.png"},
	{"strider", "Strider", PREFIX .. "strider.png"},
}

local skins, by_key = {}, {}

local function add(key, label, texture, file)
	-- file: the PNG itself (texture may be a modifier on it)
	local skin = {key = key, label = label, texture = texture, file = file or texture}
	skins[#skins + 1] = skin
	by_key[key] = skin
end

-- Width and height of a PNG, from its header
local function png_size(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local head = f:read(24)
	f:close()
	if not head or #head < 24 or head:sub(1, 8) ~= "\137PNG\r\n\26\n" then
		return nil
	end
	local function u32(i)
		local a, b, c, d = head:byte(i, i + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	return u32(17), u32(21)
end

local function label_for(key)
	local words = key:gsub("[_-]", " ")
	return words:sub(1, 1):upper() .. words:sub(2)
end

for _, s in ipairs(BUILT_IN) do
	add(s[1], s[2], s[3])
end

-- Extra skins dropped into the textures folder, in name order
local extra = {}
for _, file in ipairs(core.get_dir_list(modpath .. "/textures", false)) do
	local key = file:match("^" .. PREFIX .. "(.+)%.png$")
	if key then
		key = key:lower()
		if not by_key[key] then
			local w, h = png_size(modpath .. "/textures/" .. file)
			if w == 64 and h == 32 then
				extra[#extra + 1] = {key, file, file}
			elseif w == 64 and h == 64 then
				extra[#extra + 1] = {key, "[combine:64x32:0,0=" .. file, file}
			else
				core.log("warning", ("[orthoverse_skins] %s: expected a 64x32 or 64x64 PNG, found %sx%s; skipping")
					:format(file, tostring(w), tostring(h)))
			end
		end
	end
end
table.sort(extra, function(a, b) return a[1] < b[1] end)
for _, e in ipairs(extra) do
	add(e[1], label_for(e[1]), e[2], e[3])
end

local names = {}
for _, s in ipairs(skins) do names[#names + 1] = s.label end
core.log("action", "[orthoverse_skins] skins: " .. table.concat(names, ", "))

------------------------------------------------------------------------------
-- Wearing a skin

-- Website skins: hash -> the texture's name once sent to the clients
local media = {}
local pending = {}    -- hash -> the players waiting for it

local function guest_skin(name)
	local n = 0
	for i = 1, #name do n = (n * 31 + name:byte(i)) % 2147483647 end
	local pool = {}
	for _, s in ipairs(skins) do if s.key ~= "default" then pool[#pool + 1] = s end end
	if #pool == 0 then return by_key.default end
	return pool[n % #pool + 1]
end

local function current(player)
	local name = player:get_player_name()
	local w = orthoverse.wallets
	if w and w.is_guest(name) then return guest_skin(name) end
	local hash = w and w.skin_of(name)
	if hash and media[hash] then
		return {key = "own", label = "Own", texture = media[hash], file = media[hash]}
	end
	return by_key.default
end

------------------------------------------------------------------------------
-- The empty hand, in the colour of the skin's hand (the bottom row of the
-- right arm in the 64 x 32 layout), in Minetest Game's hand shape. Luanti
-- draws whatever is in a player's "hand" list as their empty hand, so each
-- player gets one there, with the picture set on it. orthoverse_creative's
-- instant-digging hand takes the same picture.

local HAND = "orthoverse_skins:hand"
core.register_tool(HAND, {
	description = "Hand",
	inventory_image = "wieldhand.png",
	wield_image = "wieldhand.png",
	wield_scale = {x = 1, y = 1, z = 2.5},
	groups = {not_in_creative_inventory = 1},
	on_drop = function(itemstack) return itemstack end,
})
-- It digs and punches as the ordinary hand does
core.register_on_mods_loaded(function()
	local hand = core.registered_items[""] or {}
	core.override_item(HAND, {
		tool_capabilities = hand.tool_capabilities and table.copy(hand.tool_capabilities) or nil,
		wield_scale = hand.wield_scale or {x = 1, y = 1, z = 2.5},
		range = hand.range,
	})
end)

local function esc(t) return (t:gsub("%^", "\\^"):gsub(":", "\\:")) end

local function hand_image(player)
	return "[combine:1x1:-45,-31=" .. esc(current(player).file) .. "^[resize:16x16^[mask:wieldhand.png"
end

-- Puts the skin's colour on whatever hand is in the hand list (ours, or
-- creative mode's), adding ours if there is none
local function fit_hand(player)
	local inv = player:get_inventory()
	if inv:get_size("hand") < 1 then inv:set_size("hand", 1) end
	local stack = inv:get_stack("hand", 1)
	if stack:is_empty() then stack = ItemStack(HAND) end
	stack:get_meta():set_string("wield_image", hand_image(player))
	inv:set_stack("hand", 1, stack)
end

local function apply(player)
	local tex = current(player).texture
	local name = player:get_player_name()
	if rawget(_G, "armor") and armor.textures and armor.textures[name] then
		-- 3D Armor draws the skin with the armour over it
		armor.textures[name].skin = tex
		armor:update_player_visuals(player)
	else
		player_api.set_textures(player, {tex})
	end
	fit_hand(player)
end

-- player_api gives every joining player the default model first; this mod
-- depends on it, so its join callback runs afterwards
core.register_on_joinplayer(function(player)
	apply(player)
end)

-- Sends a character's website skin to every client (once per version per
-- server run), then puts it on them
local worn = {}       -- name -> the hash they wear

local function fetch(name)
	local w = orthoverse.wallets
	local hash, file = w.skin_of(name)
	if not hash or media[hash] then return end
	if pending[hash] then return end
	local f = io.open(file, "rb")
	local data = f and f:read("*a")
	if f then f:close() end
	if not data or data:sub(1, 8) ~= "\137PNG\r\n\26\n" or #data > 65536 then
		core.log("warning", "[orthoverse_skins] the skin of " .. name .. " is not a PNG")
		return
	end
	local filename = "orthoverse_skin_c_" .. hash .. ".png"
	-- Worn once every client in the game has it (or after a few seconds), so
	-- nobody sees a missing texture on them
	local waiting = {}
	for _, p in ipairs(core.get_connected_players()) do waiting[p:get_player_name()] = true end
	local done = false
	local function wear()
		if done then return end
		done = true
		media[hash] = filename
		pending[hash] = nil
		local player = core.get_player_by_name(name)
		if player then apply(player) end
	end
	pending[hash] = true
	local ok = core.dynamic_add_media({filename = filename, filedata = data, ephemeral = false}, function(who)
		waiting[who] = nil
		for n in pairs(waiting) do if core.get_player_by_name(n) then return end end
		wear()
	end)
	if not ok then pending[hash] = nil return end
	core.after(5, wear)
end

-- A player's skin now: their website skin (sent first if need be), or the
-- one a guest or a character without one wears
local function check(player)
	local name = player:get_player_name()
	local w = orthoverse.wallets
	local hash = w and w.skin_of(name)
	if hash == worn[name] then return end
	worn[name] = hash
	if hash and not media[hash] then fetch(name) else apply(player) end
end

-- Every few seconds: a new skin saved on the website for anyone in the game
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 3 then return end
	timer = 0
	local w = orthoverse.wallets
	if not w then return end
	for _, player in ipairs(core.get_connected_players()) do check(player) end
end)

core.register_on_joinplayer(function(player) check(player) end)

core.register_on_leaveplayer(function(player) worn[player:get_player_name()] = nil end)

-- For other mods and tests
orthoverse_skins = {
	list = skins,
	get = current,
	hand = HAND,
	hand_image = hand_image,
	fit_hand = fit_hand,
}
