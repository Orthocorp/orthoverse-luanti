-- orthoverse_wallets: wallet players and guests.
--
-- Two kinds of player can join:
--   * wallet players: their name is bound to an Ethereum wallet by the auth
--     service (web/auth), which writes registry.json;
--   * guests: named Guest-XXXXXX (six hexadecimal digits) by the play page.
-- Anyone else (the old name-and-password accounts) is turned away.
--
-- Building: a wallet player may dig and build on the lands whose token their
-- wallet holds now, according to owners.json (the auth service reads the
-- Orthoverse contract on Ethereum mainnet), and on every croft: a land at
-- castle level 0 is common land, where any wallet player may mine and build,
-- token or not (pure commons: anyone may dig anyone's blocks). Upgrading the
-- castle makes the land its holder's alone; so does flipping it into the
-- futuristic realm (level 8 is not a croft), until it is flipped back. A land's ground below and sky above
-- go with it. Guests can explore but not build. Nobody builds on henges, the
-- sea or the rim, except players with the protection_bypass privilege (the
-- admin has every privilege).
--
-- Both files live in <world>/orthoverse_auth/, mounted from the auth service.

local C = orthoverse.coords
local LANDS = orthoverse.lands
local HENGES = orthoverse.henges

local DIR = core.get_worldpath() .. "/orthoverse_auth"
local GUEST_PATTERN = "^Guest%-%x%x%x%x%x%x$"
local RELOAD_EVERY = 15   -- seconds
local PLAY_URL = "orthoverse.land/play/"

------------------------------------------------------------------------------
-- The auth service's files

local registry = {}     -- lower-case name -> {name, address}
local owners = nil      -- token -> owner address (or false), nil if unknown
local owners_updated = nil
local last_raw = {}

local function read_file(name)
	local f = io.open(DIR .. "/" .. name, "r")
	if not f then return nil end
	local raw = f:read("*a")
	f:close()
	return raw
end

local function reload()
	local raw = read_file("registry.json")
	if raw and raw ~= last_raw.registry then
		local data = core.parse_json(raw)
		if type(data) == "table" and type(data.players) == "table" then
			registry = {}
			for key, p in pairs(data.players) do
				if type(p) == "table" and type(p.name) == "string" and type(p.address) == "string" then
					registry[key] = {name = p.name, address = p.address:lower()}
				end
			end
			last_raw.registry = raw
		else
			core.log("warning", "[orthoverse_wallets] registry.json did not parse; keeping the old one")
		end
	end
	raw = read_file("owners.json")
	if raw and raw ~= last_raw.owners then
		local data = core.parse_json(raw, false)
		if type(data) == "table" and type(data.owners) == "table" then
			owners = {}
			for token, owner in pairs(data.owners) do
				owners[token:lower()] = type(owner) == "string" and owner:lower() or false
			end
			owners_updated = data.updated
			last_raw.owners = raw
		else
			core.log("warning", "[orthoverse_wallets] owners.json did not parse; keeping the old one")
		end
	end
end

reload()
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer >= RELOAD_EVERY then
		timer = 0
		reload()
	end
end)

------------------------------------------------------------------------------
-- Who is who

local function is_guest(name)
	return name:find(GUEST_PATTERN) ~= nil
end

-- The wallet a player's name is bound to, or nil
local function wallet_of(name)
	local p = registry[name:lower()]
	if p and p.name == name then
		return p.address
	end
end

local function short(address)
	return address:sub(1, 6) .. "…" .. address:sub(-4)
end

-- The wallet holding a land (address): a player's wallet, or the land's 2023
-- owner if they still hold it; false if neither (held by someone else, so
-- nobody here can build on it); nil if not known yet
local function owner_of(land)
	if not owners or not land.token then return nil end
	local o = owners[land.token:lower()]
	if o == nil then return nil end
	return o
end

------------------------------------------------------------------------------
-- Joining

core.register_on_prejoinplayer(function(name)
	if is_guest(name) then
		return
	end
	if not wallet_of(name) then
		reload()   -- a name chosen a moment ago
	end
	if wallet_of(name) then
		return
	end
	return "This name is not linked to a wallet. At " .. PLAY_URL ..
		" sign in with your wallet, or play as a guest."
end)

------------------------------------------------------------------------------
-- Building

-- Whether `name` may change the world at `pos`, and if not, why not
-- Crofts (castle level 0 exactly) are common land
local function is_croft(land, key)
	return land ~= nil and not HENGES[key] and tonumber(land.level) == 0
end

local function may_build(name, pos)
	local land, key = orthoverse.land_at(pos)
	if is_guest(name) then
		if is_croft(land, key) then
			return false, land.name .. " is a croft, common land: sign in at " .. PLAY_URL ..
				" with any Ethereum wallet to mine and build here. Guests can explore but not build."
		end
		return false, "Guests can explore but not build. Sign in at " .. PLAY_URL ..
			" with an Ethereum wallet to build on crofts, the common lands, and on lands you hold."
	end
	if not land then
		return false, "Nobody can build on the open sea or at the edge of the world."
	end
	if HENGES[key] then
		return false, "Nobody can build on " .. HENGES[key].name .. "."
	end
	local wallet = wallet_of(name)
	if wallet and is_croft(land, key) then
		return true
	end
	local owner = owner_of(land)
	if owner == nil then
		return false, "Who owns " .. land.name .. " is still being checked. Try again in a few minutes."
	end
	if wallet and owner == wallet then
		return true
	end
	if owner == false then
		return false, land.name .. " is not held by any player here, so nobody can build on it."
	end
	return false, land.name .. " belongs to " .. short(owner) .. ". You can build on lands your wallet holds, " ..
		"and on crofts (castle level 0), which are common land."
end

local old_is_protected = core.is_protected
function core.is_protected(pos, name)
	if not name or name == "" then
		return old_is_protected(pos, name)
	end
	if core.check_player_privs(name, {protection_bypass = true}) then
		return old_is_protected(pos, name)
	end
	if not may_build(name, pos) then
		return true
	end
	return old_is_protected(pos, name)
end

local last_told = {}
core.register_on_protection_violation(function(pos, name)
	if not name or name == "" then return end
	local now = core.get_us_time()
	if last_told[name] and now - last_told[name] < 3000000 then return end
	last_told[name] = now
	local _, why = may_build(name, pos)
	if why then
		core.chat_send_player(name, why)
	end
end)

core.register_on_leaveplayer(function(player)
	last_told[player:get_player_name()] = nil
end)

------------------------------------------------------------------------------
-- Greeting, and commands

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	core.after(2, function()
		if not core.get_player_by_name(name) then return end
		if is_guest(name) then
			core.chat_send_player(name, "Welcome, " .. name .. ". As a guest you can explore, ride and " ..
				"travel by the henges. Sign in with an Ethereum wallet at " .. PLAY_URL ..
				" to mine and build on crofts, the common lands.")
		else
			local n = 0
			local wallet = wallet_of(name)
			for _, land in pairs(LANDS) do
				if wallet and owner_of(land) == wallet then n = n + 1 end
			end
			core.chat_send_player(name, ("Welcome, %s. Your wallet holds %d land%s: /mylands lists them. " ..
				"Anyone signed in may also mine and build on crofts (castle level 0), the common lands."):format(
				name, n, n == 1 and "" or "s"))
		end
	end)
end)

core.register_chatcommand("mylands", {
	description = "List the lands your wallet holds, which you can build on",
	func = function(name)
		if is_guest(name) then
			return true, "Guests hold no lands. Sign in with a wallet at " .. PLAY_URL .. "."
		end
		local wallet = wallet_of(name)
		if not wallet then return false, "Your name is not linked to a wallet." end
		if not owners then return true, "Who owns which land is still being checked. Try again in a few minutes." end
		local list = {}
		for key, land in pairs(LANDS) do
			if owner_of(land) == wallet then
				list[#list + 1] = ("%s (%s)"):format(land.name, key)
			end
		end
		table.sort(list)
		if #list == 0 then
			return true, "Your wallet " .. short(wallet) .. " holds no Orthoverse lands."
		end
		return true, ("Your wallet %s holds %d land%s: %s"):format(short(wallet), #list,
			#list == 1 and "" or "s", table.concat(list, ", "))
	end,
})

core.override_chatcommand("whereami", {
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then return false, "No player." end
		local land, key = orthoverse.land_at(player:get_pos())
		if not land then
			return true, "Land " .. key .. ": open sea or the edge of the world."
		end
		local h = HENGES[key]
		if h then
			return true, ("Land %s: %s, a henge."):format(key, h.name)
		end
		local owner = owner_of(land)
		if is_croft(land, key) then
			local yours = owner and owner == wallet_of(name) and "yours, and " or ""
			return true, ("Land %s: %s, a croft: %scommon land, where anyone signed in may mine and build."):format(
				key, land.name, yours)
		end
		local whose = owner == nil and "owner being checked"
			or owner == false and "not held by a player"
			or (owner == wallet_of(name) and "yours" or "held by " .. short(owner))
		return true, ("Land %s: %s (level %d), %s."):format(key, land.name, land.level, whose)
	end,
})

-- For other mods
orthoverse.wallets = {
	is_guest = is_guest,
	wallet_of = wallet_of,
	owner_of = owner_of,
	may_build = may_build,
	is_croft = is_croft,
	updated = function() return owners_updated end,
}
