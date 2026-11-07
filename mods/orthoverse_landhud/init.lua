-- orthoverse_landhud: the land you are on, at the bottom left of the screen.
--
-- Its name, and above it the land's crest with its headgear, as on the token
-- card: a crest from castle level 1, a baron's cap from 4, a coronet from 5, a
-- crown at 7 (the contract's levels 8-15 are 0-7 with the futuristic style
-- flag). A henge shows its name; the sea and the rim show nothing.
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
-- What to show at a position: name, crest texture, headgear texture

local function display_at(pos)
	local land, key = orthoverse.land_at(pos)
	if not land then return nil end
	local henge = orthoverse.henges[key]
	if henge then return henge.name or land.name end
	local level = (tonumber(land.level) or 0) % 8
	if level == 0 then return land.name end
	local n = crest_number(land)
	local crest = n and crest_texture(n)
	return land.name, crest, crest and gear_texture(level)
end

------------------------------------------------------------------------------
-- The HUD

local huds = {}     -- name -> {name = id, crest = id, gear = id, shown = "..."}

local function set_image(player, h, field, texture, y)
	if texture then
		if h[field] then
			player:hud_change(h[field], "text", texture)
		else
			h[field] = player:hud_add({
				type = "image",
				position = {x = 0, y = 1},
				alignment = {x = 1, y = -1},
				offset = {x = 12, y = y},
				scale = {x = SCALE, y = SCALE},
				text = texture,
				z_index = 10,
			})
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
	local name, crest, gear = display_at(player:get_pos())
	local shown = table.concat({name or "", crest or "", gear or ""}, "|")
	if shown == h.shown then return end
	h.shown = shown
	player:hud_change(h.name, "text", name or "")
	-- The name sits on the bottom edge, the crest above it, the headgear on top
	set_image(player, h, "crest", crest, -44)
	set_image(player, h, "gear", gear, -44 - CREST_H * SCALE)
end

core.register_on_joinplayer(function(player)
	huds[player:get_player_name()] = {
		name = player:hud_add({
			type = "text",
			position = {x = 0, y = 1},
			alignment = {x = 1, y = -1},
			offset = {x = 12, y = -12},
			text = "",
			number = 0xFFFFFF,
			size = {x = 2, y = 0},
			style = 1,      -- bold
			z_index = 10,
		}),
	}
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
