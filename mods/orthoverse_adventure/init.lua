-- orthoverse_adventure: adventures on lands.
--
-- A holder of a land at castle level 5 or more (or the admin, anywhere) can
-- make an adventure there: a dungeon area (a box inside the land), a start
-- point inside it, an arrival point outside it, and three kinds of block:
--   * the gate, where players start a run (and see the records);
--   * the finish, which a run reaches to complete the adventure;
--   * the board, which shows who has completed it and the fastest.
--
-- One party at a time: the first player through the gate starts a run, and
-- others may join through the gate for a minute after that. Then the gate is
-- shut until the run ends: two minutes after reaching the finish, at the time
-- limit, or when everyone has left (leaving the area, dying, or being away
-- for five minutes). The dungeon area is then restored from its saved state
-- ("restocking") before the next party may go in.
--
-- While an adventure is open, nobody but the run's players may be inside its
-- area (others are put back at the arrival point), and nobody is in creative
-- mode there, holder included. While it is closed, its holder builds it, then
-- saves it as a new version (/adventure save) and opens it again.
--
-- Records of every completion are kept per version (a builder cannot quietly
-- make it easier after a record), written to <world>/orthoverse_adventures/
-- for the website, with the saved dungeons.
--
-- /adventure (no arguments) explains the commands.

local C = orthoverse.coords
local storage = core.get_mod_storage()
local DIR = core.get_worldpath() .. "/orthoverse_adventures"
core.mkdir(DIR)

local UNLOCK_LEVEL = 5      -- castle level (either realm) that allows an adventure
local JOIN_WINDOW = 60      -- seconds after a run starts in which others may join
local AFTER_FINISH = tonumber(core.settings:get("orthoverse_adventure_after_finish")) or 120   -- seconds to look around after the finish
local AWAY_GRACE = 300      -- seconds a run's player may be away before leaving it
local PARTY_MAX = 6
local LIMIT_MIN, LIMIT_MAX, LIMIT_DEFAULT = 30, 120, 60   -- run time limit, minutes
local SLICE = 16            -- layers restored per server step
local GUARD_EVERY = 1       -- seconds between checks of who is where

local adventures = {}       -- land key -> definition (persisted in mod storage)
local runs = {}             -- land key -> the run in progress
local restocking = {}       -- land key -> true while the area is being restored
local templates = {}        -- land key -> the saved dungeon, loaded

orthoverse.adventure = {on_finish = {}, on_enter = {}}

------------------------------------------------------------------------------
-- Definitions

-- A JSON value from mod storage, or nil
local function stored_json(field)
	local raw = storage:get_string(field)
	if raw == "" then return nil end
	return core.parse_json(raw)
end

local function load_all()
	for _, key in ipairs(stored_json("keys") or {}) do
		local def = stored_json("adv:" .. key)
		if type(def) == "table" then adventures[key] = def end
	end
end

local function save_def(key)
	local keys = {}
	for k in pairs(adventures) do keys[#keys + 1] = k end
	table.sort(keys)
	storage:set_string("keys", core.write_json(keys))
	if adventures[key] then
		storage:set_string("adv:" .. key, core.write_json(adventures[key]))
	else
		storage:set_string("adv:" .. key, "")
	end
end

local function vec(t) return t and vector.new(t.x, t.y, t.z) end

-- The dungeon area's corners (smallest, largest), or nil if not set
local function area_of(def)
	if not def.corner1 or not def.corner2 then return nil end
	local a, b = vec(def.corner1), vec(def.corner2)
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

local function inside(def, pos)
	local p1, p2 = area_of(def)
	if not p1 then return false end
	return pos.x >= p1.x and pos.x <= p2.x + 0.99 and pos.y >= p1.y - 0.5 and pos.y <= p2.y + 0.99 and
		pos.z >= p1.z and pos.z <= p2.z + 0.99
end

-- The adventure whose area holds `pos`: key, definition
local function adventure_at(pos)
	local _, key = orthoverse.land_at(pos)
	local def = key and adventures[key]
	if def and inside(def, pos) then return key, def end
end

-- The adventure on the land at `pos` (area or not)
local function adventure_of_land(pos)
	local _, key = orthoverse.land_at(pos)
	return key, key and adventures[key]
end

------------------------------------------------------------------------------
-- Who may make and run an adventure

local function is_admin(name)
	return core.check_player_privs(name, {protection_bypass = true})
end

local function may_manage(name, key)
	if is_admin(name) then return true end
	local land = orthoverse.lands[key]
	if not land or orthoverse.henges[key] then return false end
	local w = orthoverse.wallets
	local wallet = w.wallet_of(name)
	return wallet ~= nil and wallet == w.owner_of(land) and (tonumber(land.level) or 0) % 8 >= UNLOCK_LEVEL
end

------------------------------------------------------------------------------
-- Saved dungeons (templates): every node of the area by name, param2,
-- metadata and node timers, in a file per version

local function template_file(key, version)
	return DIR .. "/" .. key:gsub(":", "_") .. "-v" .. version .. ".dat"
end

local function save_template(key, def)
	local p1, p2 = area_of(def)
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(p1, p2)
	local va = VoxelArea(e1, e2)
	local data, p2data = vm:get_data(), vm:get_param2_data()
	local palette, index_of, nodes, param2 = {}, {}, {}, {}
	local n = 0
	for z = p1.z, p2.z do
		for y = p1.y, p2.y do
			for x = p1.x, p2.x do
				local i = va:index(x, y, z)
				local cid = data[i]
				local pi = index_of[cid]
				if not pi then
					palette[#palette + 1] = core.get_name_from_content_id(cid)
					pi = #palette
					index_of[cid] = pi
				end
				n = n + 1
				nodes[n] = pi
				param2[n] = p2data[i]
			end
		end
	end
	local metas, timers = {}, {}
	for _, pos in ipairs(core.find_nodes_with_meta(p1, p2)) do
		local m = core.get_meta(pos):to_table()
		-- Inventories hold item stacks: kept as text
		for listname, list in pairs(m.inventory or {}) do
			for i, stack in ipairs(list) do
				list[i] = type(stack) == "string" and stack or stack:to_string()
			end
		end
		local rel = vector.subtract(pos, p1)
		metas[#metas + 1] = {p = {x = rel.x, y = rel.y, z = rel.z}, m = m}
	end
	for z = p1.z, p2.z do
		for y = p1.y, p2.y do
			for x = p1.x, p2.x do
				local t = core.get_node_timer({x = x, y = y, z = z})
				if t:is_started() then
					timers[#timers + 1] = {p = {x = x - p1.x, y = y - p1.y, z = z - p1.z}, t = t:get_timeout(), e = t:get_elapsed()}
				end
			end
		end
	end
	local size = vector.subtract(p2, p1)
	local tpl = {size = {x = size.x, y = size.y, z = size.z}, palette = palette, nodes = nodes, param2 = param2,
		metas = metas, timers = timers}
	local blob = core.compress(core.serialize(tpl), "zstd")
	local file = template_file(key, def.version + 1)
	if not core.safe_file_write(file, blob) then return nil, "The dungeon could not be written to " .. file .. "." end
	templates[key] = {version = def.version + 1, tpl = tpl}
	return true, n
end

local function load_template(key, def)
	local t = templates[key]
	if t and t.version == def.version then return t.tpl end
	local f = io.open(template_file(key, def.version), "rb")
	if not f then return nil end
	local blob = f:read("*a")
	f:close()
	local ok, tpl = pcall(function() return core.deserialize(core.decompress(blob, "zstd"), true) end)
	if not ok or type(tpl) ~= "table" then return nil end
	templates[key] = {version = def.version, tpl = tpl}
	return tpl
end

------------------------------------------------------------------------------
-- Restoring a dungeon from its saved state, a few layers per server step

local jobs = {}   -- land key -> {p1, tpl, y, done}

local function restore(key, done)
	local def = adventures[key]
	local tpl = def and load_template(key, def)
	if not tpl then
		if done then done(false) end
		return
	end
	local p1, p2 = area_of(def)
	-- Dropped items and creatures left behind go first
	for _, obj in ipairs(core.get_objects_in_area(p1, vector.add(p2, 1))) do
		if not obj:is_player() then obj:remove() end
	end
	restocking[key] = true
	jobs[key] = {p1 = p1, tpl = tpl, y = 0, done = done}
end

local function restore_step(key, job)
	local tpl, p1 = job.tpl, job.p1
	local sx, sy, sz = tpl.size.x + 1, tpl.size.y + 1, tpl.size.z + 1
	local y0, y1 = job.y, math.min(job.y + SLICE - 1, sy - 1)
	local a1 = vector.new(p1.x, p1.y + y0, p1.z)
	local a2 = vector.new(p1.x + sx - 1, p1.y + y1, p1.z + sz - 1)
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(a1, a2)
	local va = VoxelArea(e1, e2)
	local data, p2data = vm:get_data(), vm:get_param2_data()
	local cids = job.cids
	if not cids then
		cids = {}
		local air = core.get_content_id("air")
		for i, name in ipairs(tpl.palette) do
			cids[i] = core.registered_nodes[name] and core.get_content_id(name) or air
		end
		job.cids = cids
	end
	for z = 0, sz - 1 do
		for y = y0, y1 do
			local n = z * sy * sx + y * sx   -- position in the saved order (z, then y, then x)
			local vi = va:index(p1.x, p1.y + y, p1.z + z)
			for x = 0, sx - 1 do
				data[vi + x] = cids[tpl.nodes[n + x + 1]]
				p2data[vi + x] = tpl.param2[n + x + 1]
			end
		end
	end
	vm:set_data(data)
	vm:set_param2_data(p2data)
	vm:write_to_map(true)
	job.y = y1 + 1
	if job.y < sy then return false end
	-- Last layer: metadata and timers (cleared where none was saved)
	local p2 = vector.add(p1, tpl.size)
	for _, pos in ipairs(core.find_nodes_with_meta(p1, p2)) do
		core.get_meta(pos):from_table(nil)
	end
	for _, m in ipairs(tpl.metas) do
		core.get_meta(vector.add(p1, m.p)):from_table(m.m)
	end
	for _, t in ipairs(tpl.timers) do
		core.get_node_timer(vector.add(p1, t.p)):set(t.t, t.e)
	end
	return true
end

core.register_globalstep(function()
	for key, job in pairs(jobs) do
		local ok, finished = pcall(restore_step, key, job)
		if not ok then
			core.log("error", "[orthoverse_adventure] restoring " .. key .. " failed: " .. tostring(finished))
			finished = true
		end
		if finished then
			jobs[key] = nil
			restocking[key] = nil
			storage:set_string("dirty:" .. key, "")
			if job.done then job.done(ok) end
		end
	end
end)

------------------------------------------------------------------------------
-- Records

local records = stored_json("records") or {}   -- key -> {["v"..n] = {list}}

local function format_time(secs)
	return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

-- For the website: the adventures and their records
local function write_public()
	local list = {}
	for key, def in pairs(adventures) do
		local land = orthoverse.lands[key]
		local vrec = (records[key] or {})["v" .. def.version] or {}
		local best
		for _, r in ipairs(vrec) do
			if not best or r.secs < best.secs then best = r end
		end
		list[#list + 1] = {key = key, land = land and land.name, name = def.name, line = def.line,
			open = def.open == true, version = def.version, limit = def.limit, completions = #vrec,
			first = vrec[1], best = best, records = vrec}
	end
	table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
	core.safe_file_write(DIR .. "/adventures.json", core.write_json({updated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		adventures = list}, true))
end

local function record_completion(key, def, run, secs)
	local names = {}
	for name in pairs(run.members) do
		if not orthoverse.wallets.is_guest(name) and not may_manage(name, key) then names[#names + 1] = name end
	end
	if #names == 0 then return nil end
	table.sort(names)
	records[key] = records[key] or {}
	local v = "v" .. def.version
	records[key][v] = records[key][v] or {}
	local list = records[key][v]
	local first = #list == 0
	list[#list + 1] = {names = names, secs = secs, size = #names, at = os.date("!%Y-%m-%dT%H:%M:%SZ")}
	storage:set_string("records", core.write_json(records))
	write_public()
	return first, names
end

-- The fastest completions of the current version, best first
local function fastest(key, def, n)
	local list = {}
	for _, r in ipairs((records[key] or {})["v" .. def.version] or {}) do list[#list + 1] = r end
	table.sort(list, function(a, b) return a.secs < b.secs end)
	local out = {}
	for i = 1, math.min(n, #list) do out[i] = list[i] end
	return out, #list
end

------------------------------------------------------------------------------
-- Runs

local function now() return os.time() end

-- Who may go in: character rank (orthoverse_rank), set by the builder
local RANK_MIN_DEFAULT, RANK_MAX_DEFAULT = 1, 5
-- Dying in a run keeps a player out of that adventure for a while: 10
-- minutes, doubling with each further death there within 4 hours, at most an
-- hour; it all clears the next day. Nothing else is lost.
local LOCKOUT_FIRST, LOCKOUT_MAX, LOCKOUT_WINDOW = 600, 3600, 4 * 3600

local function lockouts(player)
	local meta = player:get_meta()
	local raw = meta:get_string("orthoverse_adventure:lockout")
	local t = raw ~= "" and core.parse_json(raw) or {}
	if t.day ~= os.date("!%Y-%m-%d") then t = {day = os.date("!%Y-%m-%d"), keys = {}} end
	t.keys = t.keys or {}
	return t, function() meta:set_string("orthoverse_adventure:lockout", core.write_json(t)) end
end

-- Seconds a player must still wait before going back into an adventure
local function locked_for(player, key)
	local t = lockouts(player)
	local k = t.keys[key]
	return k and math.max(0, (k["until"] or 0) - now()) or 0
end

local function lock_out(player, key)
	local t, save = lockouts(player)
	local k = t.keys[key] or {deaths = 0}
	if not k.last or now() - k.last > LOCKOUT_WINDOW then k.deaths = 0 end
	k.deaths, k.last = k.deaths + 1, now()
	local secs = math.min(LOCKOUT_MAX, LOCKOUT_FIRST * 2 ^ (k.deaths - 1))
	k["until"] = now() + secs
	t.keys[key] = k
	save()
	return secs
end

local function run_of(name)
	for key, run in pairs(runs) do
		if run.members[name] then return key, run end
	end
end

-- The adventurer's kit. Going in, a player's own inventory (main and craft)
-- is put aside and they get the adventure's kit; what they need beyond it
-- they find inside. Coming out, by any way (the finish, time up, leaving,
-- dying, walking out, or after being away), what they carried inside is left
-- there and their own inventory is given back, with one exception: a party
-- that finishes takes out the treasure it found in loot chests (items marked
-- orthoverse_loot:found). Dying loses nothing of their own: it was put aside.
-- A player away when their run ends gets their things back on joining.
local KEPT = "orthoverse_adventure:kept"
local WON = "orthoverse_adventure:won"
local FOUND = "orthoverse_loot:found"
local KIT_DEFAULT = {"orthoverse_combat:short_sword_steel", "orthoverse_loot:draught"}
local LISTS = {"main", "craft"}

local function has_kept(player)
	return player:get_meta():get_string(KEPT) ~= ""
end

-- Treasure keeps its mark inside; outside it is an ordinary item again
local function unmark(stack)
	local m = stack:get_meta()
	m:set_string(FOUND, "")
	m:set_string("description", "")
	return stack
end

-- Empty the adventure inventory. For a player whose party finished, the
-- treasure goes with their own things, to be given back with them.
local function leave_things_inside(player)
	local meta = player:get_meta()
	local raw = meta:get_string(KEPT)
	if raw == "" then return end
	local kept = core.deserialize(raw) or {}
	local won = meta:get_string(WON) ~= ""
	local inv = player:get_inventory()
	kept.found = kept.found or {}
	for _, list in ipairs(LISTS) do
		for _, st in ipairs(inv:get_list(list) or {}) do
			if won and not st:is_empty() and st:get_meta():get_string(FOUND) ~= "" then
				kept.found[#kept.found + 1] = unmark(ItemStack(st)):to_string()
			end
		end
		inv:set_list(list, {})
	end
	meta:set_string(WON, "")
	meta:set_string(KEPT, core.serialize(kept))
end

-- Give back what was put aside (into an empty inventory: see above), and
-- any treasure brought out
local function give_back(player)
	local meta = player:get_meta()
	local raw = meta:get_string(KEPT)
	if raw == "" then return end
	local kept = core.deserialize(raw) or {}
	local inv = player:get_inventory()
	for _, list in ipairs(LISTS) do
		for i, st in pairs(kept[list] or {}) do
			local stack = ItemStack(st)
			if inv:get_stack(list, i):is_empty() then
				inv:set_stack(list, i, stack)
			else
				local left = inv:add_item("main", stack)
				if not left:is_empty() then core.add_item(player:get_pos(), left) end
			end
		end
	end
	local brought = 0
	for _, st in ipairs(kept.found or {}) do
		local left = inv:add_item("main", ItemStack(st))
		if not left:is_empty() then core.add_item(player:get_pos(), left) end
		brought = brought + 1
	end
	meta:set_string(KEPT, "")
	if brought > 0 then
		core.chat_send_player(player:get_player_name(), "You bring out the treasure you found.")
	end
end

local function come_out(player)
	leave_things_inside(player)
	give_back(player)
end

local function put_aside(player, def)
	if has_kept(player) then come_out(player) end   -- anything left from before
	local inv = player:get_inventory()
	local out = {}
	for _, list in ipairs(LISTS) do
		local items = {}
		for i, st in ipairs(inv:get_list(list) or {}) do items[i] = st:to_string() end
		out[list] = items
		inv:set_list(list, {})
	end
	local meta = player:get_meta()
	meta:set_string(WON, "")
	meta:set_string(KEPT, core.serialize(out))
	local given = {}
	for _, it in ipairs(type(def.kit) == "table" and def.kit or KIT_DEFAULT) do
		local stack = ItemStack(it)
		if core.registered_items[stack:get_name()] and not stack:is_empty() then
			inv:add_item("main", stack)
			given[#given + 1] = stack:get_count() > 1 and (stack:get_count() .. " " .. core.registered_items[stack:get_name()].description:match("^[^\n]*"))
				or core.registered_items[stack:get_name()].description:match("^[^\n]*")
		end
	end
	core.chat_send_player(player:get_player_name(), "The gatekeeper keeps your things until you come out" ..
		(#given > 0 and (", and gives you the adventure's kit: " .. table.concat(given, ", ")) or "") ..
		". Find what else you need inside. Treasure from its chests comes out with you if you finish.")
end

local respawn_at = {}   -- name -> where to come back to life

local function on_death_in_run(player)
	local name = player:get_player_name()
	for key, run in pairs(runs) do
		if run.members[name] then
			run.members[name] = nil
			local def = adventures[key]
			-- Before bones can take it: the adventure's things stay inside
			leave_things_inside(player)
			respawn_at[name] = def.arrival and vec(def.arrival)
			if may_manage(name, key) then
				core.chat_send_player(name, "You fell in " .. def.name .. ". Your run is over (no lockout for its builder).")
			else
				local secs = lock_out(player, key)
				core.chat_send_player(name, ("You fell in %s. Your run is over, and you may go in again in %d minutes. " ..
					"Your own things are safe with the gatekeeper."):format(def.name, math.floor(secs / 60)))
			end
		end
	end
end
-- Before every other mod's (bones) on dying
table.insert(core.registered_on_dieplayers, 1, on_death_in_run)

core.register_on_respawnplayer(function(player)
	local name = player:get_player_name()
	if not run_of(name) then come_out(player) end
	local at = respawn_at[name]
	respawn_at[name] = nil
	if at then
		player:set_pos(at)
		return true
	end
end)

-- Back after being away: still in the run (within the grace time), or out of
-- it, with their things back
core.register_on_joinplayer(function(player)
	if player:get_hp() > 0 and not run_of(player:get_player_name()) then come_out(player) end
end)

-- Out of a run (the player is here): their own things back
local function out_of_run(name)
	local player = core.get_player_by_name(name)
	if player and player:get_hp() > 0 then come_out(player) end
end

local function put_at_arrival(name, def, why)
	local player = core.get_player_by_name(name)
	if not player then return end
	if def.arrival then player:set_pos(vec(def.arrival)) end
	if why then core.chat_send_player(name, why) end
end

local function end_run(key, why)
	local run = runs[key]
	local def = adventures[key]
	if not run or not def then return end
	runs[key] = nil
	for name in pairs(run.members) do
		local player = core.get_player_by_name(name)
		if player and inside(def, player:get_pos()) then
			put_at_arrival(name, def, why)
		elseif player and why then
			core.chat_send_player(name, why)
		end
		out_of_run(name)
	end
	-- Things dropped inside stay inside
	local p1, p2 = area_of(def)
	if def.footprint then p1, p2 = vec(def.footprint.min), vec(def.footprint.max) end
	if p1 then
		for _, obj in ipairs(core.get_objects_in_area(p1, p2)) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "__builtin:item" then obj:remove() end
		end
	end
	restore(key, function() core.log("action", "[orthoverse_adventure] " .. key .. " restocked") end)
end

local function start_or_join(name, key)
	local def = adventures[key]
	if not def or not def.open then return false, "This adventure is closed." end
	if restocking[key] then return false, "The adventure is being restocked. Try again in a moment." end
	local player = core.get_player_by_name(name)
	if not player then return false end
	if not may_manage(name, key) then
		local wait = locked_for(player, key)
		if wait > 0 then
			return false, ("You fell in %s not long ago: you may go in again in %d minute%s."):format(
				def.name, math.ceil(wait / 60), math.ceil(wait / 60) == 1 and "" or "s")
		end
		local R = orthoverse.rank
		if R then
			local r, lo, hi = R.get(player), def.rank_min or RANK_MIN_DEFAULT, def.rank_max or RANK_MAX_DEFAULT
			if r < lo then
				return false, ("%s is for ranks %d to %d, and you are rank %d. Come back when you have more experience."):format(
					def.name, lo, hi, r)
			elseif r > hi then
				return false, ("%s is for ranks %d to %d: at rank %d you would make it too easy for yourself."):format(
					def.name, lo, hi, r)
			end
		end
	end
	local run = runs[key]
	if run then
		if run.members[name] then return false, "You are already in this run." end
		if now() > run.join_until or run.finished then
			return false, ("Another party is inside (%s so far). The gate opens again when they come out."):format(
				format_time(now() - run.started))
		end
		local n = 0
		for _ in pairs(run.members) do n = n + 1 end
		if n >= PARTY_MAX then return false, "The party inside is full." end
		run.members[name] = true
	else
		run = {members = {[name] = true}, started = now(), join_until = now() + JOIN_WINDOW,
			version = def.version, away = {}}
		runs[key] = run
		storage:set_string("dirty:" .. key, "1")
		core.chat_send_player(name, ("The run has begun. Companions may follow you through the gate for the next %d " ..
			"seconds. Time limit: %d minutes."):format(JOIN_WINDOW, def.limit or LIMIT_DEFAULT))
	end
	core.chat_send_player(name, "To give up: /adventure leave")
	player:set_pos(vec(def.start))
	put_aside(player, def)
	for _, f in ipairs(orthoverse.adventure.on_enter) do f(player, key, def, run) end
	return true
end

local function finish(name, key)
	local run = runs[key]
	local def = adventures[key]
	if not run or not run.members[name] or run.finished then return end
	run.finished = now()
	local secs = run.finished - run.started
	-- The party takes its treasure out with it
	for n in pairs(run.members) do
		local p = core.get_player_by_name(n)
		if p then p:get_meta():set_string(WON, "1") end
	end
	local first, names = record_completion(key, def, run, secs)
	local who = {}
	for n in pairs(run.members) do who[#who + 1] = n end
	table.sort(who)
	for n in pairs(run.members) do
		core.chat_send_player(n, ("%s completed in %s. You have %s to look around before you are taken out."):format(
			def.name, format_time(secs), AFTER_FINISH >= 120 and (math.floor(AFTER_FINISH / 60) .. " minutes") or (AFTER_FINISH .. " seconds")))
	end
	-- Members whose run is not recorded (the builder, the admin, guests)
	local counted = {}
	for _, n in ipairs(names or {}) do counted[n] = true end
	for n in pairs(run.members) do
		if not counted[n] then
			core.chat_send_player(n, orthoverse.wallets.is_guest(n)
				and "Guests' runs are not recorded: make a character to get on the table."
				or "Your own runs on an adventure you build (and the admin's) are not recorded.")
		end
	end
	if first and names then
		core.chat_send_all(("%s has been completed for the first time, by %s, in %s!"):format(
			def.name, table.concat(names, ", "), format_time(secs)))
	end
	-- Other mods (rank: the finishing bonus) hear of it: the adventure, the
	-- run, and the members whose run counts
	for _, f in ipairs(orthoverse.adventure.on_finish) do f(key, def, run, names or {}) end
end

-- Who is where, once a second
local guard_timer = 0
core.register_globalstep(function(dtime)
	guard_timer = guard_timer + dtime
	if guard_timer < GUARD_EVERY then return end
	guard_timer = 0
	local t = now()
	-- Runs: time limit, the finish, players who left or are away
	for key, run in pairs(runs) do
		local def = adventures[key]
		local remaining = 0
		for name in pairs(run.members) do
			local player = core.get_player_by_name(name)
			if player then
				run.away[name] = nil
				if not inside(def, player:get_pos()) and t > run.started + 2 then
					run.members[name] = nil
					core.chat_send_player(name, "You have left " .. def.name .. ".")
					out_of_run(name)
				else
					remaining = remaining + 1
				end
			else
				run.away[name] = run.away[name] or t
				if t - run.away[name] > AWAY_GRACE then
					run.members[name] = nil
				else
					remaining = remaining + 1
				end
			end
		end
		if remaining == 0 then
			end_run(key, nil)
		elseif run.finished and t > run.finished + AFTER_FINISH then
			end_run(key, "You are back outside " .. def.name .. ".")
		elseif t > run.started + (def.limit or LIMIT_DEFAULT) * 60 then
			end_run(key, "Time is up for " .. def.name .. ".")
		end
	end
	-- Nobody else inside an open or restocking adventure, nor a closed one
	-- but its builders
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local key, def = adventure_at(player:get_pos())
		if def and not is_admin(name) then
			local run = runs[key]
			local member = run and run.members[name]
			if def.open and not member then
				put_at_arrival(name, def, "Adventurers go in through the gate.")
			elseif not def.open and not may_manage(name, key) then
				put_at_arrival(name, def, def.name .. " is closed while it is being built.")
			end
		end
	end
end)

-- No creative mode inside an adventure that is open or in use, holder included
local creative_allowed = orthoverse.creative.allowed
function orthoverse.creative.allowed(name, pos)
	local key, def = adventure_at(pos)
	if def and (def.open or runs[key] or restocking[key]) then return false end
	return creative_allowed(name, pos)
end

-- After a restart: runs are gone, so restore any dungeon a run had changed
core.register_on_mods_loaded(function()
	core.after(3, function()
		for key, def in pairs(adventures) do
			if storage:get_string("dirty:" .. key) == "1" and def.version > 0 then
				local p1, p2 = area_of(def)
				core.emerge_area(p1, p2, function(_, _, left)
					if left == 0 then restore(key) end
				end)
			end
		end
	end)
end)

------------------------------------------------------------------------------
-- The blocks

-- A window title in the Midnight font (the game's "mono" font in the browser
-- client), and buttons in it too
local function title(x, y, w, text)
	return ("hypertext[%s,%s;%s,0.9;title;<global size=16><mono>%s</mono>]"):format(x, y, w,
		core.formspec_escape(core.hypertext_escape(text)))
end
local MONO_BUTTONS = "style_type[button,button_exit;font=mono]"

local function gate_formspec(name, key, def)
	local lines = {}
	local list, total = fastest(key, def, 5)
	for i, r in ipairs(list) do
		lines[#lines + 1] = core.formspec_escape(("%d. %s  %s"):format(i, format_time(r.secs), table.concat(r.names, ", ")))
	end
	local status
	local run = runs[key]
	if not def.open then
		status = "Closed while it is being built."
	elseif restocking[key] then
		status = "Being restocked. Try again in a moment."
	elseif run and (now() > run.join_until or run.finished) then
		status = ("A party is inside (%s so far)."):format(format_time(now() - run.started))
	elseif run then
		status = ("A party has just gone in: you may join them for %d more seconds."):format(run.join_until - now())
	else
		status = "The way is open."
	end
	return table.concat({
		"formspec_version[4]size[10,9.2]", MONO_BUTTONS,
		title(0.5, 0.35, 9, def.name or "Adventure"),
		"textarea[0.5,1.1;9,1.4;;;", core.formspec_escape(def.line or ""), "]",
		"label[0.5,2.9;", core.formspec_escape(status), "]",
		"label[0.5,3.5;", core.formspec_escape(("Ranks %d to %d. Time limit %d minutes. Completed %d time%s (this version)."):format(
			def.rank_min or RANK_MIN_DEFAULT, def.rank_max or RANK_MAX_DEFAULT,
			def.limit or LIMIT_DEFAULT, total, total == 1 and "" or "s")), "]",
		title(0.5, 3.85, 9, "Fastest"),
		"textlist[0.5,4.5;9,3;fast;", #lines > 0 and table.concat(lines, ",") or "Nobody yet: be the first.", ";0;true]",
		"button_exit[0.5,7.9;4,0.9;enter;Enter]",
		"button_exit[5.5,7.9;4,0.9;close;Not now]",
	})
end

local gate_of = {}   -- player name -> adventure key, while its gate form is open
orthoverse.adventure.gate_formspec = function(name, key) return gate_formspec(name, key, adventures[key]) end

core.register_node("orthoverse_adventure:gate", {
	description = "Adventure gate (where a run starts)",
	tiles = {"orthoverse_adventure_gate_side.png", "orthoverse_adventure_gate_side.png", "orthoverse_adventure_gate.png"},
	paramtype2 = "facedir",
	groups = {cracky = 2},
	sounds = default and default.node_sound_stone_defaults(),
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local key, def = adventure_of_land(pos)
		if not def then
			core.chat_send_player(name, "This gate belongs to no adventure (/adventure create on this land).")
			return
		end
		gate_of[name] = key
		core.show_formspec(name, "orthoverse_adventure:gate", gate_formspec(name, key, def))
	end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "orthoverse_adventure:gate" then return end
	local name = player:get_player_name()
	local key = gate_of[name]
	gate_of[name] = nil
	if fields.enter and key then
		local ok, why = start_or_join(name, key)
		if not ok and why then core.chat_send_player(name, why) end
	end
	return true
end)

local function at_finish(pos, player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local key, def = adventure_at(pos)
	if not def then return end
	local run = runs[key]
	if run and run.members[name] then
		finish(name, key)
	elseif may_manage(name, key) and not def.open then
		core.chat_send_player(name, "This is the finish of " .. def.name .. ": a run that reaches it completes the adventure.")
	end
end

core.register_node("orthoverse_adventure:finish", {
	description = "Adventure finish (touch it to complete the adventure)",
	tiles = {"orthoverse_adventure_finish.png"},
	light_source = 6,
	groups = {cracky = 2},
	sounds = default and default.node_sound_stone_defaults(),
	on_rightclick = function(pos, node, clicker) at_finish(pos, clicker) end,
	on_punch = function(pos, node, puncher) at_finish(pos, puncher) end,
})

core.register_node("orthoverse_adventure:board", {
	description = "Adventure board (who has completed it)",
	drawtype = "nodebox",
	tiles = {"orthoverse_adventure_wood.png", "orthoverse_adventure_wood.png", "orthoverse_adventure_wood.png",
		"orthoverse_adventure_wood.png", "orthoverse_adventure_wood.png", "orthoverse_adventure_board.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {-0.5, -0.5, 0.375, 0.5, 0.5, 0.5}},
	groups = {choppy = 2},
	sounds = default and default.node_sound_wood_defaults(),
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local key, def = adventure_of_land(pos)
		if not def then return end
		local list, total = fastest(key, def, 10)
		local rows = {}
		for i, r in ipairs(list) do
			rows[#rows + 1] = core.formspec_escape(("%d. %s  %s (%s)"):format(i, format_time(r.secs),
				table.concat(r.names, ", "), r.at:sub(1, 10)))
		end
		local vrec = (records[key] or {})["v" .. def.version] or {}
		local first = vrec[1]
		core.show_formspec(clicker:get_player_name(), "orthoverse_adventure:board", table.concat({
			"formspec_version[4]size[11,8.5]", MONO_BUTTONS,
			title(0.5, 0.35, 10, (def.name or "Adventure") .. ": records"),
			"label[0.5,1.4;", core.formspec_escape(first and ("First to complete: " .. table.concat(first.names, ", ") ..
				" (" .. first.at:sub(1, 10) .. ")") or "Nobody has completed it yet."), "]",
			"label[0.5,2.0;", core.formspec_escape(("Completed %d time%s. Fastest:"):format(total, total == 1 and "" or "s")), "]",
			"textlist[0.5,2.4;10,5;rec;", #rows > 0 and table.concat(rows, ",") or "", ";0;true]",
			"button_exit[3.5,7.6;4,0.7;close;Close]",
		}))
	end,
})

------------------------------------------------------------------------------
-- Pebbles: a pile to take them from, for puzzles where something must be
-- thrown (a pressure plate behind a grate, say). They do nothing else, so it
-- does not matter that players keep them.

local PEBBLES_MAX = 5

core.register_craftitem("orthoverse_adventure:pebble", {
	description = "Pebble (throw it with the drop key)",
	inventory_image = "orthoverse_adventure_pebble.png",
	stack_max = PEBBLES_MAX,
	groups = {throwable = 1},   -- dropped for real even in creative mode (orthoverse_creative)
})

local function take_pebble(pos, player)
	if not player or not player:is_player() then return end
	local inv = player:get_inventory()
	if inv:contains_item("main", "orthoverse_adventure:pebble " .. PEBBLES_MAX) then
		core.chat_send_player(player:get_player_name(), "Your pockets are full of pebbles.")
		return
	end
	local left = inv:add_item("main", "orthoverse_adventure:pebble")
	if not left:is_empty() then
		core.chat_send_player(player:get_player_name(), "No room for a pebble.")
	end
end

core.register_node("orthoverse_adventure:pebbles", {
	description = "Pile of pebbles (punch it for a pebble)",
	tiles = {"default_gravel.png^[colorize:#6b5f4f:70"},
	groups = {crumbly = 2},
	sounds = default and default.node_sound_gravel_defaults(),
	on_punch = function(pos, node, puncher) take_pebble(pos, puncher) end,
	on_rightclick = function(pos, node, clicker) take_pebble(pos, clicker) end,
})

------------------------------------------------------------------------------
-- Ready-made adventures: the game's adventures/ folder holds, for each, a
-- WorldEdit file of its buildings (<name>.we) and where things are in it
-- (<name>.json: size, the ground layer, underground parts to dig out, the
-- dungeon area's corners, the start, the arrival, name, line, time limit).
-- The admin places one standing at its south-west corner on the ground.

local TEMPLATES_DIR = (function()
	local game = core.get_game_info and core.get_game_info()
	return (game and game.path or (core.get_modpath(core.get_current_modname()) .. "/../..")) .. "/adventures"
end)()

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

local function template_names()
	local out = {}
	for _, file in ipairs(core.get_dir_list(TEMPLATES_DIR, false) or {}) do
		local n = file:match("^(.+)%.json$")
		if n and read_file(TEMPLATES_DIR .. "/" .. n .. ".we") then out[#out + 1] = n end
	end
	table.sort(out)
	return out
end

local function offset(p1, t) return vector.new(p1.x + t.x, p1.y + t.y, p1.z + t.z) end

-- Fill an area with one node
local function fill(a, b, cid)
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(a, b)
	local va = VoxelArea(e1, e2)
	local data = vm:get_data()
	for i in va:iterp(a, b) do data[i] = cid end
	vm:set_data(data)
	vm:write_to_map(true)
end

-- Ground under the floor where the land is lower (or water): dirt, up to
-- DEPTH blocks down, except over the parts dug out (`skip`: boxes)
local function underpin(p1, p2, ground, skip)
	local DEPTH = 24
	local a, b = vector.new(p1.x, ground - DEPTH, p1.z), vector.new(p2.x, ground - 1, p2.z)
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(a, b)
	local va = VoxelArea(e1, e2)
	local data = vm:get_data()
	local dirt = core.get_content_id("default:dirt")
	local open = {}
	for name, def in pairs(core.registered_nodes) do
		if name == "air" or (def.liquidtype and def.liquidtype ~= "none") or not def.walkable then
			open[core.get_content_id(name)] = true
		end
	end
	open[core.get_content_id("air")] = true
	local function dug(x, z)
		for _, box in ipairs(skip) do
			if x >= box[1].x and x <= box[2].x and z >= box[1].z and z <= box[2].z then return true end
		end
	end
	for z = a.z, b.z do
		for x = a.x, b.x do
			for y = b.y, dug(x, z) and b.y + 1 or a.y, -1 do
				local i = va:index(x, y, z)
				if not open[data[i]] then break end
				data[i] = dirt
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

-- Place ready-made adventure `tname` with its south-west corner's ground
-- layer at `at` (the block a player stands on), and make it this land's
-- adventure (closed, not yet saved). Calls done(ok, message) when finished
-- (the area is loaded first).
local function place_template(tname, at, by, done)
	local info = core.parse_json(read_file(TEMPLATES_DIR .. "/" .. tname .. ".json") or "", nil)
	local data = read_file(TEMPLATES_DIR .. "/" .. tname .. ".we")
	if type(info) ~= "table" or type(info.size) ~= "table" or not data then
		return done(false, "There is no ready-made adventure called " .. tname .. ".")
	end
	if not (worldedit and worldedit.deserialize) then return done(false, "Placing it needs WorldEdit.") end
	local p1 = vector.subtract(vector.round(at), vector.new(0, info.ground or 0, 0))
	local p2 = offset(p1, {x = info.size.x - 1, y = info.size.y - 1, z = info.size.z - 1})
	local land, key = orthoverse.land_at(p1)
	for _, c in ipairs({{p2.x, p1.z}, {p1.x, p2.z}, {p2.x, p2.z}}) do
		local _, k = orthoverse.land_at(vector.new(c[1], p1.y, c[2]))
		if k ~= key then
			return done(false, ("%s needs %d x %d blocks on one land, east and north of where you stand " ..
				"(its south-west corner): move so that it fits."):format(info.name or tname, info.size.x, info.size.z))
		end
	end
	if not land or orthoverse.henges[key] then return done(false, "Stand on a land first.") end
	if adventures[key] then
		return done(false, "This land already has an adventure (" .. adventures[key].name .. "): /adventure delete first.")
	end
	core.emerge_area(vector.subtract(p1, vector.new(0, 24, 0)), p2, function(_, _, left)
		if left > 0 then return end
		local ground = p1.y + (info.ground or 0)
		local air = core.get_content_id("air")
		for _, obj in ipairs(core.get_objects_in_area(vector.new(p1.x, ground, p1.z), p2)) do
			if not obj:is_player() then obj:remove() end
		end
		fill(vector.new(p1.x, ground, p1.z), p2, air)
		local dig = {}
		for _, box in ipairs(info.dig or {}) do
			dig[#dig + 1] = {offset(p1, box.min), offset(p1, box.max)}
			fill(dig[#dig][1], dig[#dig][2], air)
		end
		underpin(p1, p2, ground, dig)
		local n = worldedit.deserialize(p1, data)
		if not n then return done(false, "The file " .. tname .. ".we could not be read.") end
		-- so a castle upgrade or a flip of the land keeps it
		if orthoverse.note_built then orthoverse.note_built(p1, p2) end
		-- WorldEdit sets nodes without starting their timers: pressure plates
		-- and monster spawners need theirs
		local q2 = vector.add(p1, {x = (info.size or {}).x or 96, y = (info.size or {}).y or 64, z = (info.size or {}).z or 96})
		for _, pos in ipairs(core.find_nodes_in_area(p1, q2, {"group:orthoverse_timer",
				"mesecons_pressureplates:pressure_plate_stone_off", "mesecons_pressureplates:pressure_plate_wood_off"})) do
			local nd = core.registered_nodes[core.get_node(pos).name]
			if nd and nd.name:find("pressure_plate") and nd.on_construct then nd.on_construct(pos)
			elseif not core.get_node_timer(pos):is_started() then core.get_node_timer(pos):start(1) end
		end
		adventures[key] = {
			name = (info.name or tname):sub(1, 60), line = (info.line or ""):sub(1, 200), version = 0, open = false,
			limit = info.limit or LIMIT_DEFAULT, creator = by,
			corner1 = offset(p1, info.corner1), corner2 = offset(p1, info.corner2),
			start = offset(p1, info.start), arrival = offset(p1, info.arrival),
			rank_min = tonumber(info.rank_min), rank_max = tonumber(info.rank_max),
			footprint = {min = vector.new(p1.x, ground, p1.z), max = p2},
			kit = type(info.kit) == "table" and info.kit or nil,
		}
		save_def(key)
		write_public()
		done(true, ("%s placed on %s (%d blocks). It is closed: look round and change what you like, then " ..
			"/adventure save and /adventure open."):format(adventures[key].name, land.name, n))
	end)
end

------------------------------------------------------------------------------
-- The command

local HELP = table.concat({
	"To give up a run: /adventure leave (it takes you back to the entrance).",
	"",
	"How an adventure works: players gather at the entrance, outside your dungeon. They",
	"right-click the Adventure gate there and are taken to the start, inside the dungeon.",
	"They complete it by touching the Adventure finish. Afterwards everyone is brought",
	"back to the entrance, and the dungeon is put back exactly as you saved it, ready for",
	"the next party. One party at a time; others wait at the gate.",
	"",
	"Making one, step by step (on a land at castle level " .. UNLOCK_LEVEL .. " or more):",
	"",
	"1. /adventure create <name>   Make an adventure on the land you stand on.",
	"2. /adventure line <text>   A one-line description for the gate and the website.",
	"3. Stand at one corner of the dungeon and type /adventure corner1, then at the",
	"   opposite corner (higher or lower too) /adventure corner2. The dungeon is the",
	"   box between them, within this land.",
	"4. Stand where players should appear when they go in, inside the dungeon:",
	"   /adventure start",
	"5. Stand at the entrance, outside the dungeon, where players gather and come back",
	"   to afterwards: /adventure arrival",
	"6. From the Creative tab, place an Adventure gate at the entrance (players",
	"   right-click it to go in) and an Adventure finish at the end of the dungeon",
	"   (touching it completes the adventure). An Adventure board at the entrance shows",
	"   the records, if you want one.",
	"7. Build the dungeon. When it is ready, /adventure save takes a snapshot of it:",
	"   after every run the dungeon goes back to exactly this. Later changes only count",
	"   once you save again, and each save starts fresh records.",
	"8. /adventure open lets players use the gate. While it is closed, only you can be",
	"   inside.",
	"",
	"Any of these can be done again to change it: stand somewhere new and repeat start,",
	"arrival, or (while closed, then save) the corners.",
	"",
	"Other commands:",
	"/adventure limit <minutes>   The time limit, " .. LIMIT_MIN .. " to " .. LIMIT_MAX .. " minutes (60 at first).",
	"/adventure ranks <lowest> <highest>   Who may go in, by character rank (1 to 5 at",
	"   first); its loot chests give metals up to the highest.",
	"/adventure name <text>   Rename it.",
	"/adventure close   Close it to change it (save and open again after).",
	"/adventure reset   Put the saved dungeon back as it was.",
	"/adventure status   How it stands, in the chat.",
	"/adventure delete   Remove it (its records and saved dungeons are kept).",
	"/adventure place <name>   (Admin) Place a ready-made adventure, standing on the ground",
	"   at its south-west corner; /adventure place on its own lists them.",
	"",
	"While it is open, nobody has creative mode in the dungeon, you included. Runs by the",
	"builder, the admin and guests are not recorded: test it with another character to",
	"see a record appear.",
}, "\n")

local function status(key, def)
	local p1, p2 = area_of(def)
	local run = runs[key]
	return table.concat({
		("%s on %s: %s, version %d."):format(def.name, key, def.open and "open" or "closed", def.version),
		p1 and ("Area %s to %s."):format(core.pos_to_string(p1), core.pos_to_string(p2)) or "Area not set (corner1, corner2).",
		def.start and "Start set." or "Start not set.",
		def.arrival and "Arrival set." or "Arrival not set.",
		("Time limit %d minutes."):format(def.limit or LIMIT_DEFAULT),
		("Ranks %d to %d."):format(def.rank_min or RANK_MIN_DEFAULT, def.rank_max or RANK_MAX_DEFAULT),
		run and "A run is in progress." or (restocking[key] and "Restocking." or ""),
	}, " ")
end

core.register_chatcommand("adventure", {
	params = "[leave | place <name> | create <name> | name <text> | line <text> | corner1 | corner2 | start | arrival | limit <minutes> | ranks <lowest> <highest> | save | open | close | reset | delete]",
	description = "Make and run an adventure on your land",
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false, "No player." end
		local pos = vector.round(player:get_pos())
		local land, key = orthoverse.land_at(pos)
		local cmd, rest = param:match("^%s*(%S*)%s*(.-)%s*$")
		local def = key and adventures[key]
		if cmd == "" or cmd == "help" then
			-- In a window: the chat is too small for it
			local text = (def and (status(key, def) .. "\n\n") or "") .. HELP
			core.show_formspec(name, "orthoverse_adventure:help", table.concat({
				"formspec_version[4]size[16,11]", MONO_BUTTONS,
				title(0.5, 0.25, 15, "Adventures"),
				"textarea[0.5,1;15,8.9;;;", core.formspec_escape(text), "]",
				"button_exit[6,10;4,0.8;close;Close]",
			}))
			return true
		end
		if cmd == "leave" or cmd == "quit" then
			for k, run in pairs(runs) do
				if run.members[name] then
					run.members[name] = nil
					put_at_arrival(name, adventures[k], "You have left " .. adventures[k].name .. ".")
					out_of_run(name)
					return true
				end
			end
			return false, "You are not in an adventure."
		end
		if cmd == "status" then
			if not def then return false, "This land has no adventure." end
			return true, status(key, def)
		end
		if cmd == "place" then
			if not is_admin(name) then return false, "Placing a ready-made adventure is for the admin." end
			if rest == "" then
				local names = template_names()
				return true, #names > 0 and ("Ready-made adventures: " .. table.concat(names, ", ") ..
					". Stand on the ground at the south-west corner and type /adventure place <name>.")
					or "There are no ready-made adventures in " .. TEMPLATES_DIR .. "."
			end
			if not rest:match("^[%w_%-]+$") then return false, "No ready-made adventure called that." end
			local feet = vector.round(player:get_pos())
			place_template(rest, vector.new(feet.x, feet.y - 1, feet.z), name, function(ok, msg)
				core.chat_send_player(name, msg)
			end)
			return true, "Placing " .. rest .. "…"
		end
		if not land then return false, "Stand on a land first." end
		if not may_manage(name, key) then
			return false, "Adventures are for holders of a land at castle level " .. UNLOCK_LEVEL .. " or more, on that land."
		end
		if cmd == "create" then
			if def then return false, "This land already has an adventure: " .. def.name .. "." end
			if rest == "" then return false, "Give it a name: /adventure create <name>" end
			adventures[key] = {name = rest:sub(1, 60), line = "", version = 0, open = false, limit = LIMIT_DEFAULT,
				creator = name}
			save_def(key)
			return true, "Adventure " .. rest .. " made on " .. land.name .. ". Next: corner1, corner2, start, arrival, then save and open."
		end
		if not def then return false, "This land has no adventure yet: /adventure create <name>" end
		local run_active = runs[key] ~= nil
		if cmd == "name" or cmd == "line" then
			if rest == "" then return false, "Give the text too." end
			def[cmd] = rest:sub(1, cmd == "name" and 60 or 200)
		elseif cmd == "corner1" or cmd == "corner2" then
			if def.open then return false, "Close it first." end
			def[cmd] = pos
			local p1, p2 = area_of(def)
			if p1 then
				local _, k1 = orthoverse.land_at(p1)
				local _, k2 = orthoverse.land_at(p2)
				if k1 ~= key or k2 ~= key then
					def[cmd] = nil
					save_def(key)
					return false, "The dungeon area must lie within this land."
				end
			end
		elseif cmd == "start" then
			if not inside(def, pos) then return false, "The start must be inside the dungeon area (set its corners first)." end
			def.start = player:get_pos()
		elseif cmd == "arrival" then
			if inside(def, pos) then return false, "The arrival point must be outside the dungeon area." end
			def.arrival = player:get_pos()
		elseif cmd == "limit" then
			local m = tonumber(rest)
			if not m or m < LIMIT_MIN or m > LIMIT_MAX then
				return false, ("The time limit is %d to %d minutes."):format(LIMIT_MIN, LIMIT_MAX)
			end
			def.limit = math.floor(m)
		elseif cmd == "ranks" then
			local lo, hi = rest:match("^(%d+)%s+(%d+)$")
			lo, hi = tonumber(lo), tonumber(hi)
			if not lo or not hi or lo < 1 or hi > 20 or lo > hi then
				return false, "Give the lowest and highest rank that may go in, 1 to 20 (e.g. /adventure ranks 1 5)."
			end
			def.rank_min, def.rank_max = lo, hi
		elseif cmd == "save" then
			if def.open or run_active then return false, "Close it first (and wait for any run to end)." end
			if not area_of(def) or not def.start then return false, "Set the corners and the start first." end
			local ok, n = save_template(key, def)
			if not ok then return false, n end
			def.version = def.version + 1
			save_def(key)
			write_public()
			return true, ("Saved as version %d (%d blocks). Records start afresh for this version."):format(def.version, n)
		elseif cmd == "open" then
			if def.version == 0 then return false, "Save it first (/adventure save)." end
			if not def.arrival then return false, "Set the arrival point first." end
			def.open = true
		elseif cmd == "close" then
			if run_active then end_run(key, def.name .. " has been closed by its builder.") end
			def.open = false
		elseif cmd == "reset" then
			if run_active then return false, "A run is in progress." end
			if def.version == 0 then return false, "Nothing saved yet." end
			restore(key, function(ok) core.chat_send_player(name, ok and "Restored." or "Could not restore.") end)
			return true, "Restoring " .. def.name .. "…"
		elseif cmd == "delete" then
			if run_active then end_run(key, def.name .. " has been removed.") end
			adventures[key] = nil
			save_def(key)
			write_public()
			return true, "The adventure is removed. Its records and saved dungeons are kept."
		else
			return false, "Unknown: type /adventure on its own for the commands."
		end
		save_def(key)
		write_public()
		return true, status(key, def)
	end,
})

load_all()
write_public()

orthoverse.adventure.at = adventure_at

-- Nobody but an adventure's builders (and the admin) digs or builds in it: its
-- area, and for a ready-made one everything it placed (the gate and the
-- village outside too). On a holder's land that is the rule already; on a
-- croft, common land, anyone could otherwise dig a way round the dungeon.
local function in_footprint(def, pos)
	local f = def.footprint
	if not (f and f.min and f.max) then return false end
	return pos.x >= f.min.x and pos.x <= f.max.x and pos.y >= f.min.y and pos.y <= f.max.y
		and pos.z >= f.min.z and pos.z <= f.max.z
end
local old_is_protected = core.is_protected
function core.is_protected(pos, name)
	if name and name ~= "" then
		local key, def = adventure_of_land(pos)
		if def and (inside(def, pos) or in_footprint(def, vector.round(pos))) and not may_manage(name, key) then
			return true
		end
	end
	return old_is_protected(pos, name)
end
-- Whether a player builds an adventure's land (or is the admin): their runs
-- there count for nothing
orthoverse.adventure.may_manage = may_manage
orthoverse.adventure.locked_for = locked_for
orthoverse.adventure.runs = runs
orthoverse.adventure.list = adventures
-- For tests: what the gate's Enter button and the finish block do
orthoverse.adventure.enter = start_or_join
orthoverse.adventure.finish = finish
orthoverse.adventure.place = place_template
orthoverse.adventure.in_run = function(name)
	for key, run in pairs(runs) do
		if run.members[name] then return key end
	end
end
