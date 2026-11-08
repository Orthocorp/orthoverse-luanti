-- orthoverse_rank: a character's rank (1 to 20) and experience, from
-- fighting monsters and finishing adventures (docs/combat-numbers.md).
--
-- Rank gives more health (20 at rank 1, +2 a rank), a wider sweet spot, +1
-- damage every four ranks, and lets a weapon's metal count in full (steel from
-- rank 1, bronze 3, mese 6, diamond 10): orthoverse_combat asks for it.
--
-- Experience: each monster has a value; it is shared by the players of the
-- run within 32 blocks (10% more per extra member), and scaled by how the
-- monster's level compares to each player's rank. Nothing is given for a
-- monster that was not really fighting (it must have attacked in the last
-- 15 s), for a spawner's monsters again the same day (a quarter less each
-- run, down to nothing), past a day's cap per adventure, to guests, or to the
-- builder or the admin in their own adventure. Finishing an adventure gives a
-- bonus once a day. Rank is never lost.

local S = core.get_translator and core.get_translator("orthoverse_rank") or function(s) return s end

orthoverse = orthoverse or {}
local rank_api = {}
orthoverse.rank = rank_api

local KEY = "orthoverse_rank:"
local MAX_RANK = 20
-- Experience to reach each rank (the SRD's thresholds)
local NEEDS = {0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000,
	85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000}
local SHARE_RADIUS = 32
local FOUGHT_WITHIN = 15        -- seconds: the monster must have attacked this recently
local DAY_CAP = 1500            -- experience a day from one adventure's monsters
local FINISH_XP = 200           -- for finishing an adventure, once a day each
local MATERIAL_RANK = {steel = 1, bronze = 3, mese = 6, diamond = 10}

local function now() return core.get_us_time() / 1e6 end
local function today() return os.date("!%Y-%m-%d") end

------------------------------------------------------------------------------
-- Rank from experience, and what a rank gives

local function rank_for(xp)
	local r = 1
	for i = 2, MAX_RANK do
		if xp >= NEEDS[i] then r = i else break end
	end
	return r
end

local function xp_of(player) return player:get_meta():get_int(KEY .. "xp") end
local function rank_of(player) return rank_for(xp_of(player)) end

rank_api.NEEDS = NEEDS
rank_api.MAX = MAX_RANK
rank_api.rank_for = rank_for
rank_api.get = function(player)
	if type(player) == "string" then player = core.get_player_by_name(player) end
	return player and rank_of(player) or 1
end
rank_api.xp = function(player) return xp_of(player) end
rank_api.hp_max = function(rank) return 20 + 2 * (rank - 1) end
-- Seconds of full strength that count as the sweet spot
rank_api.sweet = function(rank) return 0.25 + 0.2 * (rank - 1) / (MAX_RANK - 1) end
-- Extra damage on every blow
rank_api.damage = function(rank) return math.floor(rank / 4) end
-- The highest metal damage bonus a rank lets count (steel +0 ... diamond +3)
rank_api.material_cap = function(rank)
	return rank >= 10 and 3 or rank >= 6 and 2 or rank >= 3 and 1 or 0
end
rank_api.material_rank = MATERIAL_RANK

------------------------------------------------------------------------------
-- The display: rank and progress at the bottom right, and a line for a
-- moment when experience comes in

local huds = {}

local function progress_text(player)
	local xp = xp_of(player)
	local r = rank_for(xp)
	if r >= MAX_RANK then return ("Rank %d   %d xp"):format(r, xp) end
	return ("Rank %d   %d / %d xp"):format(r, xp, NEEDS[r + 1])
end

local function show(player)
	local name = player:get_player_name()
	local h = huds[name]
	if not h then
		h = {}
		h.line = player:hud_add({type = "text", position = {x = 1, y = 1}, alignment = {x = -1, y = -1},
			offset = {x = -16, y = -12}, text = "", number = 0xF5C64A, z_index = 10})
		h.gain = player:hud_add({type = "text", position = {x = 1, y = 1}, alignment = {x = -1, y = -1},
			offset = {x = -16, y = -34}, text = "", number = 0xEFE6D0, z_index = 10})
		huds[name] = h
	end
	player:hud_change(h.line, "text", progress_text(player))
end

local function flash(player, text)
	local h = huds[player:get_player_name()]
	if not h then return end
	player:hud_change(h.gain, "text", text)
	h.until_t = now() + 3
end

core.register_globalstep(function()
	local t = now()
	for name, h in pairs(huds) do
		if h.until_t and t > h.until_t then
			h.until_t = nil
			local player = core.get_player_by_name(name)
			if player then player:hud_change(h.gain, "text", "") end
		end
	end
end)

------------------------------------------------------------------------------
-- Health from rank. Luanti forgets health above 20 when a player leaves, so
-- it is kept in their meta and put back on joining.

local function fit_health(player, heal)
	local max = rank_api.hp_max(rank_of(player))
	local props = player:get_properties()
	if props.hp_max ~= max then
		-- the health bar shows the same 10 hearts, each worth more
		player:set_properties({hp_max = max})
	end
	if heal then player:set_hp(max) end
end

core.register_on_joinplayer(function(player)
	fit_health(player)
	local saved = player:get_meta():get_int(KEY .. "hp")
	if saved > player:get_hp() and player:get_hp() > 0 then
		player:set_hp(math.min(saved, rank_api.hp_max(rank_of(player))))
	end
	show(player)
end)

core.register_on_leaveplayer(function(player)
	player:get_meta():set_int(KEY .. "hp", player:get_hp())
	huds[player:get_player_name()] = nil
end)

core.register_on_respawnplayer(function(player)
	core.after(0, function()
		if player:get_pos() then fit_health(player, true) end
	end)
end)

------------------------------------------------------------------------------
-- Gaining experience

local function add_xp(player, amount, why)
	amount = math.floor(amount + 0.5)
	if amount <= 0 then return 0 end
	local meta = player:get_meta()
	local before = rank_of(player)
	meta:set_int(KEY .. "xp", meta:get_int(KEY .. "xp") + amount)
	local after = rank_of(player)
	show(player)
	flash(player, ("+%d xp%s"):format(amount, why and ("  " .. why) or ""))
	local name = player:get_player_name()
	core.log("action", ("[orthoverse_rank] %s +%d xp (%s), now %d"):format(name, amount,
		core.strip_colors(core.get_translated_string("en", why or "")), meta:get_int(KEY .. "xp")))
	if after > before then
		fit_health(player, true)
		core.sound_play("orthoverse_rank_up", {to_player = name, gain = 0.9}, true)
		local pos = player:get_pos()
		core.add_particlespawner({amount = 40, time = 0.6,
			pos = {min = vector.add(pos, {x = -0.5, y = 0, z = -0.5}), max = vector.add(pos, {x = 0.5, y = 2, z = 0.5})},
			vel = {min = {x = -0.3, y = 1, z = -0.3}, max = {x = 0.3, y = 2.5, z = 0.3}},
			exptime = {min = 0.8, max = 1.6}, size = {min = 1, max = 2.5}, glow = 14,
			texture = "orthoverse_rank_spark.png"})
		local gains = {("health %d"):format(rank_api.hp_max(after))}
		if rank_api.damage(after) > rank_api.damage(before) then gains[#gains + 1] = "+1 damage on every blow" end
		for metal, r in pairs(MATERIAL_RANK) do
			if r > before and r <= after then gains[#gains + 1] = metal .. " weapons now at full strength" end
		end
		core.chat_send_player(name, ("You are now rank %d: %s."):format(after, table.concat(gains, ", ")))
		if after >= 5 and before < 5 then
			core.chat_send_all(("%s has reached rank %d."):format(name, after))
		end
	else
		core.sound_play("orthoverse_rank_xp", {to_player = name, gain = 0.5}, true)
	end
	return amount
end
rank_api.add_xp = add_xp

-- The day's tallies: experience per adventure, and runs per spawner
local function tally(player)
	local meta = player:get_meta()
	local raw = meta:get_string(KEY .. "day")
	local t = raw ~= "" and core.parse_json(raw) or {}
	if t.day ~= today() then t = {day = today(), adv = {}, sp = {}, fin = {}} end
	t.adv, t.sp, t.fin = t.adv or {}, t.sp or {}, t.fin or {}
	return t, function() meta:set_string(KEY .. "day", core.write_json(t)) end
end

-- Experience for the level gap: monster level minus player rank
local function gap_factor(gap)
	if gap <= -5 then return 0 end        -- trivial
	if gap <= -2 then return 0.5 end      -- easy
	if gap <= 1 then return 1 end         -- even
	if gap <= 4 then return 1.5 end       -- hard
	return 2                              -- deadly
end
rank_api.gap_factor = gap_factor

local function counts(name, key)
	local w = orthoverse.wallets
	if w and w.is_guest and w.is_guest(name) then return false end
	local ad = orthoverse.adventure
	if key and ad and ad.may_manage and ad.may_manage(name, key) then return false end
	return true
end

-- A monster has died of a player's blow. `ent` carries _xp (its value), _level,
-- _fought (when it last attacked), _adventure/_run and _spawner.
function rank_api.killed(ent, killer)
	if not (killer and killer:is_player()) then return end
	local pos = ent.object:get_pos()
	if not pos then return end
	local value = ent._xp or 0
	if value <= 0 then return end
	if not ent._fought or now() - ent._fought > FOUGHT_WITHIN then
		flash(killer, "no xp: it was not fighting")
		return
	end
	local ad = orthoverse.adventure
	local key = ad and ad.at and ad.at(pos)
	-- Who shares: the run's players near the kill, or the killer alone
	local sharers = {}
	local run = key and ad.runs and ad.runs[key]
	if run then
		for name in pairs(run.members) do
			local p = core.get_player_by_name(name)
			if p and p:get_hp() > 0 and vector.distance(p:get_pos(), pos) <= SHARE_RADIUS then
				sharers[#sharers + 1] = p
			end
		end
	end
	if #sharers == 0 then sharers = {killer} end
	local n = #sharers
	local each = value * (1 + 0.1 * (n - 1)) / n
	local level = ent._level or 1
	local label = ent._desc or (ent.name or ""):gsub("^.*:", "")
	for _, p in ipairs(sharers) do
		local name = p:get_player_name()
		if counts(name, key) then
			local t, save = tally(p)
			local amount = each * gap_factor(level - rank_of(p))
			-- The same spawner on another run today: a quarter less each time
			if ent._spawner and ent._run then
				local sp = t.sp[ent._spawner] or {runs = 0}
				if sp.last ~= ent._run then
					sp.runs, sp.last = (sp.last and sp.runs + 1) or 0, ent._run
				end
				t.sp[ent._spawner] = sp
				amount = amount * math.max(0, 1 - 0.25 * sp.runs)
			end
			if key then
				local got = t.adv[key] or 0
				amount = math.min(amount, math.max(0, DAY_CAP - got))
				t.adv[key] = got + math.floor(amount + 0.5)
			end
			save()
			if amount >= 0.5 then
				add_xp(p, amount, label)
			elseif gap_factor(level - rank_of(p)) == 0 then
				flash(p, "no xp: too easy for your rank")
			elseif key and (t.adv[key] or 0) >= DAY_CAP then
				flash(p, "no more xp from this adventure today")
			else
				flash(p, "no xp: this spawner again today")
			end
		end
	end
end

-- Finishing an adventure: a bonus for each member whose run counts, once a day
local function on_finish(key, def, run, names)
	for _, name in ipairs(names) do
		local p = core.get_player_by_name(name)
		if p and counts(name, key) then
			local t, save = tally(p)
			if not t.fin[key] then
				t.fin[key] = true
				save()
				add_xp(p, FINISH_XP, "finished " .. (def.name or "the adventure"))
			end
		end
	end
end

core.register_on_mods_loaded(function()
	if orthoverse.adventure and orthoverse.adventure.on_finish then
		table.insert(orthoverse.adventure.on_finish, on_finish)
	end
end)

------------------------------------------------------------------------------
-- /rank: your rank; the admin can set one for testing

core.register_chatcommand("rank", {
	params = "[<player> [<rank> | +<xp>]]",
	description = S("Your rank and experience (the admin: someone's, or set it)"),
	func = function(name, param)
		local who, val = param:match("^(%S+)%s*(%S*)$")
		if not who or who == "" then
			local p = core.get_player_by_name(name)
			if not p then return false end
			local r = rank_of(p)
			return true, progress_text(p) .. (". Health %d, sweet spot %.2f s, +%d damage."):format(
				rank_api.hp_max(r), rank_api.sweet(r), rank_api.damage(r))
		end
		if not core.check_player_privs(name, {server = true}) then
			return false, "Only the admin can look at or set another's rank."
		end
		local p = core.get_player_by_name(who)
		if not p then return false, who .. " is not in the game." end
		if val == "" then return true, who .. ": " .. progress_text(p) end
		local plus = val:match("^%+(%d+)$")
		if plus then
			add_xp(p, tonumber(plus), "from the admin")
		else
			local r = tonumber(val)
			if not r or r < 1 or r > MAX_RANK then return false, "Rank 1 to " .. MAX_RANK .. ", or +<xp>." end
			p:get_meta():set_int(KEY .. "xp", NEEDS[math.floor(r)])
			fit_health(p, true)
			show(p)
		end
		return true, who .. ": " .. progress_text(p)
	end,
})
