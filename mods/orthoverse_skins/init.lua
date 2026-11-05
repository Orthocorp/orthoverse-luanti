-- orthoverse_skins: player skins, chosen in the inventory's Skin tab with a 3D
-- preview of each, and remembered per player.
--
-- The skins are textures for Minetest Game's character model, in the 64 x 32
-- skin layout. Besides the built-in ones below, any file in this mod's textures
-- folder called orthoverse_skin_<name>.png is offered as "<Name>". 64 x 64
-- (modern Minecraft) skins work too: only their top half, which holds the
-- 64 x 32 layout, is used.

local modpath = core.get_modpath(core.get_current_modname())
local PREFIX = "orthoverse_skin_"
local META = "orthoverse_skins:skin"
local PER_PAGE = 5

-- Built-in skins, in the order they are shown: key, label, texture
local BUILT_IN = {
	{"default", "Default", "character.png"},
	{"wizard", "Wizard", PREFIX .. "wizard.png"},
	{"elf", "Elf", PREFIX .. "elf.png"},
	{"borgo", "Borgo", PREFIX .. "borgo.png"},
	{"strider", "Strider", PREFIX .. "strider.png"},
}

local skins, by_key = {}, {}

local function add(key, label, texture)
	local skin = {key = key, label = label, texture = texture}
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
				extra[#extra + 1] = {key, file}
			elseif w == 64 and h == 64 then
				extra[#extra + 1] = {key, "[combine:64x32:0,0=" .. file}
			else
				core.log("warning", ("[orthoverse_skins] %s: expected a 64x32 or 64x64 PNG, found %sx%s; skipping")
					:format(file, tostring(w), tostring(h)))
			end
		end
	end
end
table.sort(extra, function(a, b) return a[1] < b[1] end)
for _, e in ipairs(extra) do
	add(e[1], label_for(e[1]), e[2])
end

local names = {}
for _, s in ipairs(skins) do names[#names + 1] = s.label end
core.log("action", "[orthoverse_skins] skins: " .. table.concat(names, ", "))

------------------------------------------------------------------------------
-- Wearing a skin

local function current(player)
	return by_key[player:get_meta():get_string(META)] or by_key.default
end

local function apply(player)
	player_api.set_textures(player, {current(player).texture})
end

-- player_api gives every joining player the default model first; this mod
-- depends on it, so its join callback runs afterwards
core.register_on_joinplayer(function(player)
	apply(player)
end)

local function choose(player, key)
	if not by_key[key] then return end
	player:get_meta():set_string(META, key)
	apply(player)
end

------------------------------------------------------------------------------
-- The Skin tab

local page_of = {}  -- player name -> page of skins shown

sfinv.register_page("orthoverse_skins:skins", {
	title = "Skin",
	get = function(self, player, context)
		local name = player:get_player_name()
		local pages = math.ceil(#skins / PER_PAGE)
		local page = math.min(page_of[name] or 1, pages)
		local worn = current(player).key
		local fs = {}
		local first = (page - 1) * PER_PAGE + 1
		for i = first, math.min(first + PER_PAGE - 1, #skins) do
			local s = skins[i]
			local x = (i - first) * 1.6
			fs[#fs + 1] = ("model[%.2f,0.1;1.6,3.1;skin_%d;character.b3d;%s;0,180;false;true;0,79;30]")
				:format(x, i, core.formspec_escape(s.texture))
			if s.key == worn then
				-- The one being worn: highlighted, not a button
				fs[#fs + 1] = ("box[%.2f,3.25;1.45,0.8;#4ee69a70]"):format(x)
				fs[#fs + 1] = ("label[%.2f,3.4;%s]"):format(x + 0.15, core.formspec_escape(s.label))
			else
				fs[#fs + 1] = ("button[%.2f,3.25;1.6,0.8;wear_%s;%s]")
					:format(x, s.key, core.formspec_escape(s.label))
			end
		end
		fs[#fs + 1] = "label[0,4.05;Click a name to wear it.]"
		if pages > 1 then
			fs[#fs + 1] = ("label[4.9,4.05;Page %d of %d]"):format(page, pages)
			if page > 1 then fs[#fs + 1] = "button[6.4,3.95;0.8,0.6;skins_prev;<]" end
			if page < pages then fs[#fs + 1] = "button[7.2,3.95;0.8,0.6;skins_next;>]" end
		end
		return sfinv.make_formspec(player, context, table.concat(fs), true)
	end,
	on_player_receive_fields = function(self, player, context, fields)
		local name = player:get_player_name()
		local pages = math.ceil(#skins / PER_PAGE)
		for field in pairs(fields) do
			local key = field:match("^wear_(.+)$")
			if key then
				choose(player, key)
			elseif field == "skins_next" then
				page_of[name] = math.min((page_of[name] or 1) + 1, pages)
			elseif field == "skins_prev" then
				page_of[name] = math.max((page_of[name] or 1) - 1, 1)
			end
		end
		sfinv.set_player_inventory_formspec(player)
	end,
})

core.register_on_leaveplayer(function(player)
	page_of[player:get_player_name()] = nil
end)

-- For other mods and tests
orthoverse_skins = {
	list = skins,
	get = current,
	choose = choose,
}
