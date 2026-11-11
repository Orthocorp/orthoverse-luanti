-- orthoverse_wallets: wallet players and guests.
--
-- Three kinds of player can join:
--   * wallet players: their name is bound to an Ethereum wallet by the auth
--     service (web/auth), which writes registry.json;
--   * password characters: made on the website with a name and password, in
--     registry.json without a wallet until they link one;
--   * guests: named Guest-XXXXXX (six hexadecimal digits) by the play page,
--     new each visit, and deleted when they leave (nothing of theirs is kept).
-- Anyone else is turned away.
--
-- Building: a wallet player may dig and build on the lands whose token their
-- wallet holds now, according to owners.json (the auth service reads the
-- Orthoverse contract on Ethereum mainnet), and on every croft: a land at
-- castle level 0 is open land, where any wallet player may mine and build,
-- token or not (pure commons: anyone may dig anyone's blocks). Password
-- characters without a wallet may too, after their first hour of play (so a
-- character made a minute ago cannot wreck a croft). Upgrading the
-- castle makes the land its holder's alone; so does flipping it into the
-- futuristic realm (level 8 is not a croft), until it is flipped back. A land's ground below and sky above
-- go with it. (A land can be held with another level's rights than its
-- token's, orthoverse.rights_level: Tir Na Nog, a croft held as if at level
-- 7, for its adventure.) Guests can explore but not build. Nobody builds on henges, the
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
local ACCOUNT_URL = "orthoverse.land/account/"
local CROFT_AFTER = 3600  -- seconds of play before a character without a wallet builds on crofts

------------------------------------------------------------------------------
-- The auth service's files

local registry = {}     -- lower-case name -> {name, address (nil for a password character without a wallet)}
local deleted = {}      -- lower-case name -> {name, at}: characters the admin deleted (characters.sh)
local owners = nil      -- token -> owner address (or false), nil if unknown
local owners_updated = nil
local last_raw = {}

local function is_guest_name(name) return name:find(GUEST_PATTERN) ~= nil end

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
				if type(p) == "table" and type(p.name) == "string" then
					registry[key] = {
						name = p.name,
						address = type(p.address) == "string" and p.address:lower() or nil,
						-- the game account's password record (see below)
						srp = type(p.srp) == "string" and p.srp:match("^#1#[%w+/]+=*#[%w+/]+=*$") and p.srp or nil,
						-- when the website made that password, for one entry
						issued = tonumber(p.issued),
						-- the skin designed on the website: its picture's hash
						-- (the picture is skins/<name>.png)
						skin = type(p.skin) == "table" and type(p.skin.h) == "string" and p.skin.h:match("^%x+$")
							and #p.skin.h <= 32 and p.skin.h or nil,
						-- locked by the admin (characters.sh): kept out
						locked = p.locked ~= nil and p.locked ~= false,
						since = p.since,
					}
				end
			end
			last_raw.registry = raw
		else
			core.log("warning", "[orthoverse_wallets] registry.json did not parse; keeping the old one")
		end
	end
	raw = read_file("deleted.json")
	if raw and raw ~= last_raw.deleted then
		local data = core.parse_json(raw)
		if type(data) == "table" and type(data.deleted) == "table" then
			deleted = {}
			for key, d in pairs(data.deleted) do
				if type(d) == "table" and type(d.name) == "string" and tonumber(d.at) then
					deleted[key] = {name = d.name, at = tonumber(d.at)}
				end
			end
			last_raw.deleted = raw
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

-- Time played, per player, in mod storage (so it is known while they are away)
local storage = core.get_mod_storage()
local unsaved
local function played(name)
	return storage:get_int("played:" .. name) + math.floor(unsaved and unsaved[name] or 0)
end

-- Seconds played since last written down, per player online
unsaved = {}
local function save_played(name)
	local secs = math.floor(unsaved[name] or 0)
	if secs > 0 then
		storage:set_int("played:" .. name, storage:get_int("played:" .. name) + secs)
		unsaved[name] = (unsaved[name] or 0) - secs
	end
end

-- The admin's decisions (characters.sh): a locked or deleted character is put
-- out of the game; a deleted one's game account and player data (what it
-- carries, where it stands, its rank) are removed once it is out, and what
-- this mod kept about it. A name made again since is left alone.
local function enforce()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if not is_guest_name(name) then
			local p = registry[name:lower()]
			if not (p and p.name == name) then
				core.kick_player(name, "This character has been deleted.")
			elseif p.locked then
				core.kick_player(name, "This character is locked.")
			end
		end
	end
	for key, d in pairs(deleted) do
		local name = d.name
		if storage:get_string("deleted:" .. name) ~= tostring(d.at) and not core.get_player_by_name(name) then
			if not registry[key] then
				if core.get_auth_handler().get_auth(name) then core.remove_player_auth(name) end
				core.remove_player(name)
				for _, k in ipairs({"played:", "entered:", "visit:"}) do storage:set_string(k .. name, "") end
				core.log("action", "[orthoverse_wallets] deleted character " .. name .. " removed from the game")
			end
			storage:set_string("deleted:" .. name, tostring(d.at))
		end
	end
end

-- Guests are not kept: when a guest leaves, its game account and player data
-- (what it carried, where it stood) are deleted, and so is what this mod kept
-- about it. Guests still in the game when the server stopped go when it
-- starts again.
-- A guest on its way in (between the engine asking and the player being in
-- the game, its account is there but its player is not): never removed then,
-- or the engine finds no account when the player arrives, and stops
local arriving = {}   -- name -> when it asked to join
core.register_on_prejoinplayer(function(name)
	if is_guest_name(name) then arriving[name] = core.get_us_time() / 1e6 end
end)
core.register_on_joinplayer(function(player) arriving[player:get_player_name()] = nil end)

local function forget_guest(name)
	if not is_guest_name(name) or core.get_player_by_name(name) then return end
	if arriving[name] and core.get_us_time() / 1e6 - arriving[name] < 60 then return end
	core.remove_player(name)
	if core.get_auth_handler().get_auth(name) then core.remove_player_auth(name) end
	for _, k in ipairs({"played:", "entered:", "visit:"}) do storage:set_string(k .. name, "") end
end

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	if is_guest_name(name) then core.after(1, forget_guest, name) end
end)

core.after(3, function()
	local auth = core.get_auth_handler()
	if not auth.iterate then return end
	local old = {}
	for name in auth.iterate() do
		if is_guest_name(name) and not core.get_player_by_name(name) then old[#old + 1] = name end
	end
	for _, name in ipairs(old) do forget_guest(name) end
	if #old > 0 then core.log("action", "[orthoverse_wallets] " .. #old .. " guests left from before removed") end
end)

local timer = 0
core.register_globalstep(function(dtime)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		unsaved[name] = (unsaved[name] or 0) + dtime
	end
	timer = timer + dtime
	if timer >= RELOAD_EVERY then
		timer = 0
		for name in pairs(unsaved) do save_played(name) end
		reload()
		enforce()
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	save_played(name)
	unsaved[name] = nil
end)

core.register_on_shutdown(function()
	for name in pairs(unsaved) do save_played(name) end
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

-- A name made on the website (with a wallet or a password), exactly as made
local function is_registered(name)
	local p = registry[name:lower()]
	return p ~= nil and p.name == name
end

-- A password character without a wallet
local function without_wallet(name)
	return is_registered(name) and not wallet_of(name)
end

-- Minutes until a character without a wallet may build on crofts (0: may)
local function croft_wait(name)
	return math.max(0, math.ceil((CROFT_AFTER - played(name)) / 60))
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

-- Each entry into the game has its own password (the website makes one when
-- the player presses Enter, and keeps its record in registry.json): the
-- account is set to it here, before the engine checks it, and it is let in
-- once, within ENTRY_FOR seconds. A password that leaks, or one changed with
-- the game's own menu, is no use afterwards. The account is also made here
-- for a new character: otherwise the first client to join under a new name
-- would set its password, and anyone who saw the name first could take it.
local ENTRY_FOR = 600
local entering = {}   -- name -> the entry (its issued time) now joining

core.register_on_prejoinplayer(function(name)
	if is_guest(name) then
		return
	end
	reload()   -- a name chosen, or a password made, a moment ago (read only if changed)
	if not is_registered(name) then
		return "This name is not known here. At " .. PLAY_URL ..
			" sign in or make a character, or play as a guest."
	end
	local p = registry[name:lower()]
	if p.locked then return "This character is locked." end
	local again = "Enter the game from " .. PLAY_URL .. ": press Enter again there."
	if not (p.srp and p.issued) or os.time() - p.issued > ENTRY_FOR then return again end
	if storage:get_string("entered:" .. name) == tostring(p.issued) then return again end   -- already used
	local auth = core.get_auth_handler()
	local have = auth.get_auth(name)
	if not have then
		if not auth.create_auth(name, p.srp) then return "This character is still being set up. Try again in a minute." end
		core.log("action", "[orthoverse_wallets] game account made for " .. name)
	elseif have.password ~= p.srp then
		auth.set_password(name, p.srp)
	end
	entering[name] = p.issued
end)

-- Let in: that entry's password is used up
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	if entering[name] then
		storage:set_string("entered:" .. name, tostring(entering[name]))
		entering[name] = nil
	end
end)

------------------------------------------------------------------------------
-- Building

-- Whether `name` may change the world at `pos`, and if not, why not
-- Crofts (castle level 0 exactly) are open land
local function is_croft(land, key)
	return land ~= nil and not HENGES[key] and orthoverse.rights_level(land, key) == 0
end

-- What players are told about open land (crofts), wherever it comes up
local OPEN_LAND = "Open land: anyone can build here, but the holder owns it and can claim it at any time."

local function may_build(name, pos)
	local land, key = orthoverse.land_at(pos)
	if is_guest(name) then
		if is_croft(land, key) then
			return false, land.name .. " is open land, but guests can explore and not build: make a character " ..
				"or sign in at " .. PLAY_URL .. " to mine and build here. " .. OPEN_LAND
		end
		return false, "Guests can explore but not build. Make a character or sign in at " .. PLAY_URL ..
			" to build on open land (crofts, castle level 0)."
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
	if is_croft(land, key) and without_wallet(name) then
		local wait = croft_wait(name)
		if wait == 0 then return true end
		return false, land.name .. " is open land. You can mine and build on open land after your first hour " ..
			"of play (" .. wait .. " minute" .. (wait == 1 and "" or "s") .. " to go), or at once with a wallet linked at " ..
			ACCOUNT_URL .. ". " .. OPEN_LAND
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
		"and on open land (crofts, castle level 0), which anyone can build on until its holder claims it."
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
				"travel by the henges, but not build. Nothing is kept: when you leave, this guest and everything " ..
				"it carries are gone. Make a character or sign in at " .. PLAY_URL ..
				" to keep what you find and build on open land (crofts, castle level 0).")
		elseif without_wallet(name) then
			local wait = croft_wait(name)
			core.chat_send_player(name, "Welcome, " .. name .. ". " .. (wait == 0
				and "You can mine and build on open land (crofts, castle level 0). "
				or ("You can mine and build on open land (crofts, castle level 0) after your first hour of play (" ..
					wait .. " minute" .. (wait == 1 and "" or "s") .. " to go). ")) .. OPEN_LAND .. " " ..
				"Lands belong to Ethereum wallets: link one at " .. ACCOUNT_URL .. " to hold lands and build on them.")
		else
			local n = 0
			local wallet = wallet_of(name)
			for _, land in pairs(LANDS) do
				if wallet and owner_of(land) == wallet then n = n + 1 end
			end
			core.chat_send_player(name, ("Welcome, %s. Your wallet holds %d land%s: /mylands lists them, /home takes you there. " ..
				"Anyone signed in may also mine and build on open land (crofts, castle level 0). " .. OPEN_LAND):format(
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
		if not wallet then
			return true, "Your character has no wallet linked, so holds no lands. Link one at " .. ACCOUNT_URL .. "."
		end
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

------------------------------------------------------------------------------
-- Arriving where you clicked on the map: the website (POST /auth/visit, for
-- the admin and holders of a level 7 land) writes visits.json; on joining
-- within 10 minutes the player is put there. Checked again here: the
-- teleport privilege, or a land at castle level 7 (either realm) held now.
-- Or at an adventure chosen on the Adventures page (any character): a visit
-- with "adventure" (a land key) instead of x and z puts the player at its
-- entrance, if it is open (orthoverse.adventure.travel).

local VISIT_FOR = 600   -- seconds a visit waits for the player to join

-- The highest castle level (0-7, either realm) among the lands `name`'s
-- wallet holds now, or nil if it holds none
local function highest_level(name)
	local wallet = wallet_of(name)
	if not wallet then return nil end
	local best
	for key, land in pairs(LANDS) do
		if not HENGES[key] and owner_of(land) == wallet then
			local level = orthoverse.rights_level(land, key) % 8
			if not best or level > best then best = level end
		end
	end
	return best
end

local function may_visit(name)
	if core.check_player_privs(name, {teleport = true}) then return true end
	return (highest_level(name) or 0) >= 7
end

local storage = core.get_mod_storage()
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local raw = read_file("visits.json")
	local data = raw and core.parse_json(raw)
	local v = type(data) == "table" and type(data.visits) == "table" and data.visits[name:lower()]
	if type(v) ~= "table" or v.name ~= name or not tonumber(v.t) then return end
	if os.time() - tonumber(v.t) > VISIT_FOR then return end
	if storage:get_string("visit:" .. name) == tostring(v.at) then return end   -- already taken
	if type(v.adventure) == "string" then
		storage:set_string("visit:" .. name, tostring(v.at))
		local key = v.adventure
		core.after(1, function()
			local ad = orthoverse.adventure
			if not (ad and ad.travel and core.get_player_by_name(name)) then return end
			local ok, msg = ad.travel(name, key)
			if not ok then core.chat_send_player(name, msg) end
		end)
		return
	end
	if not tonumber(v.x) or not tonumber(v.z) then return end
	storage:set_string("visit:" .. name, tostring(v.at))
	if not may_visit(name) then return end
	local x, z = math.floor(tonumber(v.x)), math.floor(tonumber(v.z))
	local land, key = orthoverse.land_at(vector.new(x, 0, z))
	local h = HENGES[key]
	local label = h and h.name or land and (land.name .. " (" .. key .. ")") or ("the sea at " .. key)
	core.after(1, function() orthoverse.teleport_to(name, x, z, label, 0) end)
end)

-- /home: to one of your own lands (any holder; no privilege needed). This
-- takes the place of Minetest Game's /home (sethome), which needs a privilege
-- players here do not have.
local home_command = {
	params = "[land name]",
	privs = {},
	description = "Go to one of the lands your wallet holds",
	func = function(name, param)
		if is_guest(name) then
			return false, "Guests hold no lands. Sign in with a wallet at " .. PLAY_URL .. "."
		end
		local wallet = wallet_of(name)
		if not wallet then return false, "Your name is not linked to a wallet." end
		if not owners then return false, "Who owns which land is still being checked. Try again in a few minutes." end
		local mine = {}
		for key, land in pairs(LANDS) do
			if owner_of(land) == wallet then mine[#mine + 1] = {key = key, name = land.name} end
		end
		table.sort(mine, function(a, b) return a.name < b.name end)
		if #mine == 0 then
			return false, "Your wallet " .. short(wallet) .. " holds no Orthoverse lands."
		end
		local q = param:lower():match("^%s*(.-)%s*$")
		local pick = {}
		for _, l in ipairs(mine) do
			if q == "" or l.name:lower():find(q, 1, true) or l.key == q then pick[#pick + 1] = l end
		end
		if q == "" and #mine > 1 then
			local names = {}
			for _, l in ipairs(mine) do names[#names + 1] = l.name end
			return true, "Which one? /home <name>: " .. table.concat(names, ", ")
		end
		if #pick == 0 then return false, "None of your lands is called \"" .. param .. "\"." end
		if #pick > 1 then
			local names = {}
			for _, l in ipairs(pick) do names[#names + 1] = l.name end
			return false, "Which one? " .. table.concat(names, ", ")
		end
		orthoverse.teleport_to_land(name, pick[1].key, pick[1].name .. " (" .. pick[1].key .. ")")
		return true, "Going home to " .. pick[1].name .. "..."
	end,
}
if core.registered_chatcommands["home"] then
	core.override_chatcommand("home", home_command)
else
	core.register_chatcommand("home", home_command)
end

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
			local yours = owner and owner == wallet_of(name) and " (yours)" or ""
			return true, ("Land %s: %s%s. %s"):format(key, land.name, yours, OPEN_LAND)
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
	is_registered = is_registered,
	without_wallet = without_wallet,
	wallet_of = wallet_of,
	owner_of = owner_of,
	may_build = may_build,
	is_croft = is_croft,
	highest_level = highest_level,
	updated = function() return owners_updated end,
	-- A character's skin from the website: its hash and the picture's file,
	-- or nil if it has none
	skin_of = function(name)
		local p = is_registered(name) and registry[name:lower()]
		if not (p and p.skin) then return nil end
		return p.skin, DIR .. "/skins/" .. name:lower() .. ".png"
	end,
}
