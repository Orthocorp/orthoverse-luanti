-- orthoverse_landhud: the land you are on, at the bottom left of the screen.
--
-- Its name in the Midnight font (as on the cards), and above it the land's crest with its headgear, as on the token
-- card: a crest from castle level 1, a baron's cap from 4, a coronet from 5, a
-- crown at 7 (the contract's levels 8-15 are 0-7 with the futuristic style
-- flag). A henge shows its name; the sea and the rim show nothing. On a land
-- your wallet holds, the name is gold, with a line under it ("Your land, level
-- 4"; "Your land, open land"). On a land someone else holds, two lines say
-- what it is and whose ("Open land", then "held by Alice"; "Level 3", then
-- "held by 0x1234...abcd"): on open land anyone may build, but the holder can
-- claim it at any time.
--
-- Crests are single small PNGs in crests/ (cut from web/heraldry by
-- tools/split_crests.py when the server image is built), sent embedded in the
-- HUD image, so a player only ever downloads the crests they see. The crest a
-- land has comes from the chain service's tokens.json (it can change as the
-- castle is upgraded), falling back to lands.json.

local CRESTS = core.get_modpath(core.get_current_modname()) .. "/crests/"
local TOKENS = core.get_worldpath() .. "/orthoverse_chain/tokens.json"
local CHECK_EVERY = 0.5     -- seconds between checks of where players are
local RELOAD_EVERY = 60     -- seconds between reads of tokens.json
local SCALE = 4             -- screen pixels per crest pixel
local CREST_W, CREST_H, GEAR_H = 20, 25, 7
local MARGIN = 12           -- from the screen's edges
local NAME_WIDTH = 260      -- names wider than this at 3x (10 letters) are drawn at 2x
local GAP = 8               -- between the name and the crest
local LINE_GAP = 4          -- between the line under the name and the name
local GOLD = "#f5c64a"      -- your own land's name (the site's gold)
local QUIET = "#efe6d0"     -- the line under it (the site's parchment)

------------------------------------------------------------------------------
-- Text in the Midnight font, pieced together from its letters
-- (textures/orthoverse_midnight.png: Latin-1 in 16 x 16 cells of 8 x 8, made
-- by tools/midnight_atlas.py), with a drop shadow one font pixel down-right

-- The characters of a UTF-8 string, as numbers
local function codepoints(text)
	local out, i = {}, 1
	while i <= #text do
		local b = text:byte(i)
		local c, n = b, 1
		if b >= 0xF0 then c, n = b % 8, 4
		elseif b >= 0xE0 then c, n = b % 16, 3
		elseif b >= 0xC0 then c, n = b % 32, 2 end
		for k = 1, n - 1 do c = c * 64 + (text:byte(i + k) or 0x80) % 64 end
		out[#out + 1] = c
		i = i + n
	end
	return out
end

local function glyphs(codes, atlas, dx, dy)
	local parts = {}
	for i, c in ipairs(codes) do
		if c > 255 then c = 63 end   -- "?"
		if c ~= 32 then
			parts[#parts + 1] = ("%d,%d=%s\\^[sheet\\:16x16\\:%d,%d"):format(
				(i - 1) * 8 + dx, dy, atlas, c % 16, math.floor(c / 16))
		end
	end
	return parts
end

-- The texture for `text` (white, or tinted `colour`), and its size in font
-- pixels. The letters are white, so tinting the whole picture colours them
-- and leaves the shadow dark.
local function text_texture(text, colour)
	local codes = codepoints(text)
	local w, h = #codes * 8 + 1, 9
	local parts = glyphs(codes, "orthoverse_midnight_shadow.png", 1, 1)
	for _, p in ipairs(glyphs(codes, "orthoverse_midnight.png", 0, 0)) do parts[#parts + 1] = p end
	local tex = ("[combine:%dx%d:%s"):format(w, h, table.concat(parts, ":"))
	if colour then tex = tex .. "^[multiply:" .. colour end
	return tex, w, h
end

------------------------------------------------------------------------------
-- Crests

local crest_of_token = {}   -- lower-case token -> crest number, from tokens.json
local last_raw

local function reload_tokens()
	local f = io.open(TOKENS, "r")
	if not f then return end
	local raw = f:read("*a")
	f:close()
	if raw == last_raw then return end
	local data = core.parse_json(raw, nil)
	if type(data) ~= "table" or type(data.tokens) ~= "table" then
		core.log("warning", "[orthoverse_landhud] tokens.json did not parse; keeping the old crests")
		return
	end
	local out = {}
	for token, t in pairs(data.tokens) do
		if type(t) == "table" and tonumber(t.crest) then out[token:lower()] = tonumber(t.crest) end
	end
	crest_of_token, last_raw = out, raw
end

local function crest_number(land)
	local n = land.token and crest_of_token[land.token:lower()]
	if n then return n end
	return tonumber(type(land.crest) == "string" and land.crest:match("^(%d+)%.png$"))
end

local texture_cache = {}    -- crest number -> "[png:..." texture, or false
local function crest_texture(n)
	if texture_cache[n] == nil then
		local f = io.open(CRESTS .. n .. ".png", "rb")
		if f then
			texture_cache[n] = "[png:" .. core.encode_base64(f:read("*a"))
			f:close()
		else
			texture_cache[n] = false
		end
	end
	return texture_cache[n] or nil
end

local function gear_texture(level)
	if level >= 7 then return "orthoverse_landhud_crown.png" end
	if level >= 5 then return "orthoverse_landhud_coronet.png" end
	if level >= 4 then return "orthoverse_landhud_baron.png" end
end

------------------------------------------------------------------------------
-- What to show at a position for a player: name, crest texture, headgear
-- texture, and if the land is theirs, the line under the name

local function yours(pname, land, key)
	local w = orthoverse.wallets
	if not w or w.is_guest(pname) then return nil end
	local wallet = w.wallet_of(pname)
	if not wallet or wallet ~= w.owner_of(land) then return nil end
	local level = (tonumber(land.level) or 0) % 8
	if w.is_croft(land, key) then return "Your land, open land" end
	if level == 0 then return "Your land" end
	return "Your land, level " .. level
end

-- The lines under the name on a land someone else holds: what it is (open
-- land, or its castle level and realm), then who holds it
local function held_by(pname, land, key)
	local w = orthoverse.wallets
	if not w then return nil end
	-- (the rights it gives: Tir Na Nog counts as level 7)
	local level = orthoverse.rights_level(land, key)
	local what = w.is_croft(land, key) and "Open land"
		or level >= 8 and ("Futuristic level " .. (level - 8))
		or ("Level " .. level)
	local holder = w.owner_of(land)
	if not holder then return what end
	return what .. "\nheld by " .. w.name_of_wallet(holder)
end

-- The name, crest, headgear, the line under the name, and whether the land
-- is the player's
local function display_at(pos, pname)
	local land, key = orthoverse.land_at(pos)
	if not land then return nil end
	local henge = orthoverse.henges[key]
	if henge then return henge.name or land.name end
	local line = yours(pname, land, key)
	local mine = line ~= nil
	line = line or held_by(pname, land, key)
	local level = (tonumber(land.level) or 0) % 8
	if level == 0 then return land.name, nil, nil, line, mine end
	local n = crest_number(land)
	local crest = n and crest_texture(n)
	return land.name, crest, crest and gear_texture(level), line, mine
end

------------------------------------------------------------------------------
-- The HUD

local huds = {}     -- name -> {line = id, name = id, crest = id, gear = id, shown = "..."}

local function image(player, texture, scale, y)
	return player:hud_add({
		type = "image",
		position = {x = 0, y = 1},
		alignment = {x = 1, y = -1},
		offset = {x = MARGIN, y = y},
		scale = {x = scale, y = scale},
		text = texture,
		z_index = 10,
	})
end

local function set_image(player, h, field, texture, scale, y)
	if texture then
		if h[field] then
			player:hud_change(h[field], "text", texture)
			player:hud_change(h[field], "scale", {x = scale, y = scale})
			player:hud_change(h[field], "offset", {x = MARGIN, y = y})
		else
			h[field] = image(player, texture, scale, y)
		end
	elseif h[field] then
		player:hud_remove(h[field])
		h[field] = nil
	end
end

local function show(player)
	local pname = player:get_player_name()
	local h = huds[pname]
	if not h then return end
	local name, crest, gear, line, mine = display_at(player:get_pos(), pname)
	local shown = table.concat({name or "", crest or "", gear or "", line or "", mine and "1" or ""}, "|")
	if shown == h.shown then return end
	h.shown = shown
	-- From the bottom edge up: the line (your land), the name, the crest, the
	-- headgear
	local y = -MARGIN
	-- (one or two lines: "Open land" over "held by Alice", which would be too
	-- wide for one beside the hotbar)
	local lines = {}
	if name and line then for l in line:gmatch("[^\n]+") do lines[#lines + 1] = l end end
	for i, field in ipairs({"line", "line2"}) do
		local l = lines[#lines + 1 - i]
		if l then
			local texture, _, th = text_texture(l, QUIET)
			set_image(player, h, field, texture, 2, y)
			y = y - th * 2 - LINE_GAP
		else
			set_image(player, h, field, nil)
		end
	end
	if name then
		local texture, w, th = text_texture(name, mine and GOLD or nil)
		local scale = w * 3 <= NAME_WIDTH and 3 or 2
		set_image(player, h, "name", texture, scale, y)
		y = y - th * scale - GAP
	else
		set_image(player, h, "name", nil)
	end
	set_image(player, h, "crest", crest, SCALE, y)
	set_image(player, h, "gear", gear, SCALE, y - CREST_H * SCALE)
end

core.register_on_joinplayer(function(player)
	huds[player:get_player_name()] = {}
	show(player)
end)

core.register_on_leaveplayer(function(player)
	huds[player:get_player_name()] = nil
end)

reload_tokens()
local t, r = 0, 0
core.register_globalstep(function(dtime)
	t, r = t + dtime, r + dtime
	if r >= RELOAD_EVERY then
		r = 0
		reload_tokens()
	end
	if t < CHECK_EVERY then return end
	t = 0
	for _, player in ipairs(core.get_connected_players()) do show(player) end
end)
