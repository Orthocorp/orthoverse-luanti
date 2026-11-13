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
-- /adventure (no arguments) explains the commands. Anyone can travel to an
-- open adventure's entrance: /adventure go <name> (on its own, the list).

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
-- Who may go in: character rank (orthoverse_rank), set by the builder
local RANK_MIN_DEFAULT, RANK_MAX_DEFAULT = 1, 5
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
	return wallet ~= nil and wallet == w.owner_of(land) and orthoverse.rights_level(land, key) % 8 >= UNLOCK_LEVEL
end

------------------------------------------------------------------------------
-- Saved dungeons (templates): every node of the area by name, param2,
-- metadata and node timers, in a file per version

local function template_file(key, version)
	return DIR .. "/" .. key:gsub(":", "_") .. "-v" .. version .. ".dat"
end

-- Every node of an area (p1 to p2, smallest and largest corners): the table
-- that save_template writes and restore reads, also the compact form of a
-- ready-made adventure (<name>.ovt)
local function capture(p1, p2)
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
	return {size = {x = size.x, y = size.y, z = size.z}, palette = palette, nodes = nodes, param2 = param2,
		metas = metas, timers = timers}, n
end

local function save_template(key, def)
	local p1, p2 = area_of(def)
	local tpl, n = capture(p1, p2)
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
			rank_min = def.rank_min or RANK_MIN_DEFAULT, rank_max = def.rank_max or RANK_MAX_DEFAULT,
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
-- that finishes takes out the gold and gems it found in loot chests (items
-- marked orthoverse_loot:found), as much as their own inventory has room
-- for; the rest stays behind. Dying loses nothing of their own: it was put aside.
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
	local kept = core.deserialize(raw, true) or {}
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
	-- (armour worn inside stays inside too)
	if orthoverse.armor then orthoverse.armor.set_worn(player, {}) end
	meta:set_string(WON, "")
	meta:set_string(KEPT, core.serialize(kept))
end

-- Give back what was put aside (into an empty inventory: see above), and
-- any treasure brought out
local function give_back(player)
	local meta = player:get_meta()
	local raw = meta:get_string(KEPT)
	if raw == "" then return end
	local kept = core.deserialize(raw, true) or {}
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
	if orthoverse.armor and kept.armor then orthoverse.armor.set_worn(player, kept.armor) end
	-- Treasure goes where there is room; with a full inventory, the rest is
	-- left behind
	local brought, lost = 0, 0
	for _, st in ipairs(kept.found or {}) do
		local stack = ItemStack(st)
		local left = inv:add_item("main", stack)
		brought = brought + stack:get_count() - left:get_count()
		lost = lost + left:get_count()
	end
	meta:set_string(KEPT, "")
	local name = player:get_player_name()
	if brought > 0 then core.chat_send_player(name, "You bring out the gold and gems you found.") end
	if lost > 0 then
		core.chat_send_player(name, ("Your pack was full: %d piece%s of treasure stayed behind."):format(lost, lost == 1 and "" or "s"))
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
	-- and the armour they wear (3D Armor)
	if orthoverse.armor then
		out.armor = orthoverse.armor.worn(player)
		orthoverse.armor.set_worn(player, {})
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
		". Find what else you need inside. Gold and gems from its chests come out with you if you finish.")
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
	if def.arrival then
		local at = vec(def.arrival)
		player:set_pos(orthoverse.bodies and orthoverse.bodies.place(player, at) or at)
	end
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
	-- (not inside a companion already there: orthoverse_bodies)
	local b = orthoverse.bodies
	player:set_pos(b and b.place(player, vec(def.start)) or vec(def.start))
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

------------------------------------------------------------------------------
-- Sky adventures (def.catch_falls: Tir Na Nog's, a climb from stone to stone
-- in the air). Nobody is hurt by a fall: a player who falls is caught by the
-- wind and set down on the last checkpoint they stood on (the start until
-- then). A checkpoint is a block (orthoverse_adventure:checkpoint).

local CATCH_BELOW = 6      -- caught this far below the checkpoint
local CATCH_SPEED = -14    -- or falling this fast (a fall of about ten blocks)

local function checkpoint_of(run, name, def)
	run.checkpoint = run.checkpoint or {}
	return run.checkpoint[name] or vec(def.start)
end

local function catch(player, run, def)
	local name = player:get_player_name()
	local at = checkpoint_of(run, name, def)
	local from = player:get_pos()
	core.add_particlespawner({amount = 24, time = 0.3, pos = {min = vector.offset(from, -0.5, 0, -0.5),
		max = vector.offset(from, 0.5, 1.8, 0.5)}, vel = {min = vector.new(-1, 2, -1), max = vector.new(1, 4, 1)},
		exptime = {min = 0.6, max = 1.2}, size = {min = 2, max = 4}, texture = "orthoverse_adventure_wind.png", glow = 8})
	-- (set down on it: landing ends the fall, and a fall does no harm here;
	-- not again for a moment, while the player's own game catches up)
	run.caught = run.caught or {}
	run.caught[name] = core.get_us_time() + 1e6
	player:set_pos(vector.offset(at, 0, 0.1, 0))
	core.chat_send_player(name, "The wind catches you and sets you down again.")
end

-- A maze (def.maze: {min, max, wall}, its corners odd distances apart), made
-- anew for each run: passages one block wide between walls (min.y is the
-- floor, the walls stand on it to max.y), open on the middle of its east and
-- west sides (the way in and out).
local function make_maze(m)
	local a, b = vec(m.min), vec(m.max)
	if not (a and b) then return end
	local w = core.get_content_id(m.wall or "default:stonebrick")
	local air = core.get_content_id("air")
	local cx, cz = math.floor((b.x - a.x) / 2), math.floor((b.z - a.z) / 2)   -- cells across
	local open = {}   -- "x,z" (block offsets) -> true where there is no wall
	local function k(x, z) return x .. "," .. z end
	local seen = {}
	local stack = {{0, 0}}
	seen[k(0, 0)] = true
	open[k(1, 1)] = true
	local rnd = PcgRandom(core.get_us_time() % 2147483647)
	while #stack > 0 do
		local c = stack[#stack]
		local next = {}
		for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
			local nx, nz = c[1] + d[1], c[2] + d[2]
			if nx >= 0 and nz >= 0 and nx < cx and nz < cz and not seen[k(nx, nz)] then next[#next + 1] = {nx, nz, d} end
		end
		if #next == 0 then
			stack[#stack] = nil
		else
			local n = next[rnd:next(1, #next)]
			seen[k(n[1], n[2])] = true
			open[k(c[1] * 2 + 1 + n[3][1], c[2] * 2 + 1 + n[3][2])] = true
			open[k(n[1] * 2 + 1, n[2] * 2 + 1)] = true
			stack[#stack + 1] = {n[1], n[2]}
		end
	end
	-- the ways in and out, in the middle of the east and west sides
	local mz = math.floor(cz / 2) * 2 + 1
	open[k(0, mz)] = true
	open[k(b.x - a.x, mz)] = true
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(a, b)
	local va = VoxelArea(e1, e2)
	local data = vm:get_data()
	for x = 0, b.x - a.x do for z = 0, b.z - a.z do
		local id = open[k(x, z)] and air or w
		for y = a.y + 1, b.y do data[va:index(a.x + x, y, a.z + z)] = id end
	end end
	vm:set_data(data)
	vm:write_to_map(true)
end
orthoverse.adventure.make_maze = make_maze

core.register_node("orthoverse_adventure:checkpoint", {
	description = "Checkpoint (a sky adventure's: who falls is set down on the last they stood on)",
	tiles = {"orthoverse_adventure_checkpoint.png", "orthoverse_adventure_checkpoint_side.png"},
	paramtype = "light",
	light_source = 9,
	groups = {cracky = 2},
	sounds = rawget(_G, "default") and default.node_sound_glass_defaults() or nil,
})

-- Checkpoints and falls, every step, for the members of sky runs
core.register_globalstep(function()
	for key, run in pairs(runs) do
		local def = adventures[key]
		if def and def.catch_falls then
			for name in pairs(run.members) do
				local player = core.get_player_by_name(name)
				if player and not (run.caught and (run.caught[name] or 0) > core.get_us_time()) then
					local pos = player:get_pos()
					local under = core.get_node(vector.new(math.floor(pos.x + 0.5), math.floor(pos.y - 0.1 + 0.5),
						math.floor(pos.z + 0.5))).name
					if under == "orthoverse_adventure:checkpoint" then
						local at = vector.new(math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
						local was = checkpoint_of(run, name, def)
						if not vector.equals(vector.round(was), at) then
							run.checkpoint[name] = at
							core.chat_send_player(name, "Checkpoint: a fall now brings you back here.")
							core.sound_play("orthoverse_props_bell", {to_player = name, gain = 0.3, pitch = 1.6}, true)
						end
					end
					local cp = checkpoint_of(run, name, def)
					if pos.y < cp.y - CATCH_BELOW or player:get_velocity().y < CATCH_SPEED then
						catch(player, run, def)
					end
				end
			end
		end
	end
end)

-- and no harm from falling, in a sky run
core.register_on_player_hpchange(function(player, change, reason)
	if change < 0 and reason and reason.type == "fall" then
		local key = run_of(player:get_player_name())
		local def = key and adventures[key]
		if def and def.catch_falls then return 0 end
	end
	return change
end, true)

-- A new run of a sky adventure starts at its start, with a new maze
table.insert(orthoverse.adventure.on_enter, function(player, key, def, run)
	if not def.catch_falls then return end
	run.checkpoint = run.checkpoint or {}
	run.checkpoint[player:get_player_name()] = nil
	if def.maze and not run.maze_made then
		run.maze_made = true
		make_maze(def.maze)
	end
end)

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
				local pos = player:get_pos()
				if def.catch_falls and not inside(def, pos) and pos.y < checkpoint_of(run, name, def).y - 2 then
					-- fell out of the sky's area: caught, not out of the run
					catch(player, run, def)
					remaining = remaining + 1
				elseif not inside(def, pos) and t > run.started + 2 then
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

-- In a run, a dropped item falls at the player's feet rather than being
-- thrown: nothing found inside can be tossed over a wall (the Mill's yard)
-- or out of a gorge to someone waiting outside. Things dropped inside are
-- cleared when the run ends. Things made to be thrown and worth nothing
-- (group throwable: the pebbles) are thrown as usual: puzzles need them
-- thrown (The Three Bells' pressure plates behind slots).
local item_drop = core.item_drop
function core.item_drop(itemstack, dropper, pos)
	if dropper and dropper.is_player and dropper:is_player() and run_of(dropper:get_player_name()) and
			core.get_item_group(ItemStack(itemstack):get_name(), "throwable") == 0 then
		local p = vector.offset(dropper:get_pos(), 0, 0.5, 0)
		local obj = core.add_item(p, itemstack)
		if obj then obj:set_velocity({x = 0, y = 0, z = 0}) end
		return ItemStack("")
	end
	return item_drop(itemstack, dropper, pos)
end

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
		if n and (read_file(TEMPLATES_DIR .. "/" .. n .. ".we") or read_file(TEMPLATES_DIR .. "/" .. n .. ".ovt")) then
			out[#out + 1] = n
		end
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

-- Turning a ready-made adventure round (half a turn, seen from above), so
-- its entrance is at the other end: where a block goes, and which way it
-- faces. Positions are relative to the south-west corner.
local FACEDIR_HALF = {2, 3, 0, 1, 10, 11, 8, 9, 6, 7, 4, 5, 18, 19, 16, 17, 14, 15, 12, 13, 22, 23, 20, 21}
local WALLMOUNTED_HALF = {0, 1, 3, 2, 5, 4, 6, 7}

local function half_turn_param2(name, param2)
	local def = core.registered_nodes[name]
	local pt = def and def.paramtype2 or "none"
	param2 = param2 or 0
	if pt == "facedir" or pt == "colorfacedir" then
		local o = param2 % 32
		return param2 - o + (FACEDIR_HALF[o + 1] or o)
	elseif pt == "4dir" or pt == "color4dir" then
		local o = param2 % 4
		return param2 - o + (o + 2) % 4
	elseif pt == "wallmounted" or pt == "colorwallmounted" then
		local o = param2 % 8
		return param2 - o + WALLMOUNTED_HALF[o + 1]
	elseif pt == "degrotate" then
		return (param2 + 120) % 240
	elseif pt == "colordegrotate" then
		local o = param2 % 32
		return param2 - o + (o + 12) % 24
	end
	return param2
end

-- The template's description turned round: its points and boxes
local function half_turn_info(info)
	local sx, sz = info.size.x - 1, info.size.z - 1
	local function pt(t)
		if type(t) ~= "table" then return t end
		return {x = sx - t.x, y = t.y, z = sz - t.z}
	end
	local out = {}
	for k, v in pairs(info) do out[k] = v end
	for _, k in ipairs({"corner1", "corner2", "start", "arrival"}) do out[k] = pt(info[k]) end
	if type(info.dig) == "table" then
		out.dig = {}
		for i, box in ipairs(info.dig) do
			local a, b = pt(box.min), pt(box.max)
			out.dig[i] = {min = {x = math.min(a.x, b.x), y = math.min(a.y, b.y), z = math.min(a.z, b.z)},
				max = {x = math.max(a.x, b.x), y = math.max(a.y, b.y), z = math.max(a.z, b.z)}}
		end
	end
	return out
end

-- WorldEdit's deserialize, with each block put where the turned-round
-- adventure has it. It sets every block with core.add_node(entry, entry) and
-- its metadata with core.get_meta(entry), where the entry (unlike any position
-- the engine passes, as to on_construct) has a name: so those calls are moved.
local function deserialize_half_turned(p1, size, data)
	local add_node, get_meta = core.add_node, core.get_meta
	local function moved(pos)
		return {x = p1.x + (size.x - 1) - (pos.x - p1.x), y = pos.y, z = p1.z + (size.z - 1) - (pos.z - p1.z)}
	end
	core.add_node = function(pos, node)
		if type(pos) == "table" and pos.name then
			return add_node(moved(pos), {name = node.name, param1 = node.param1,
				param2 = half_turn_param2(node.name, node.param2)})
		end
		return add_node(pos, node)
	end
	core.get_meta = function(pos)
		if type(pos) == "table" and pos.name then return get_meta(moved(pos)) end
		return get_meta(pos)
	end
	local ok, n = pcall(worldedit.deserialize, p1, data)
	core.add_node, core.get_meta = add_node, get_meta
	if not ok then
		core.log("error", "[orthoverse_adventure] placing turned round: " .. tostring(n))
		return nil
	end
	return n
end

-- A ready-made adventure in the compact form (<name>.ovt: capture's table,
-- compressed): every node written at once, turned round if asked, then its
-- metadata and node timers. Returns the number of nodes set, or nil.
local function place_compact(p1, tpl, turned, skip_air)
	local sx, sy, sz = tpl.size.x + 1, tpl.size.y + 1, tpl.size.z + 1
	local p2 = vector.add(p1, tpl.size)
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(p1, p2)
	local va = VoxelArea(e1, e2)
	local data, p2data = vm:get_data(), vm:get_param2_data()
	local cids, air = {}, core.get_content_id("air")
	for i, name in ipairs(tpl.palette) do
		cids[i] = core.registered_nodes[name] and core.get_content_id(name) or air
	end
	local turn = {}   -- palette index -> {param2 -> turned param2}
	local n = 0
	for z = 0, sz - 1 do
		for y = 0, sy - 1 do
			local row = z * sy * sx + y * sx
			for x = 0, sx - 1 do
				local pi = tpl.nodes[row + x + 1]
				local p2v = tpl.param2[row + x + 1] or 0
				local tx, tz = x, z
				if turned then
					tx, tz = sx - 1 - x, sz - 1 - z
					local t = turn[pi]
					if not t then t = {}; turn[pi] = t end
					local v = t[p2v]
					if not v then v = half_turn_param2(tpl.palette[pi], p2v); t[p2v] = v end
					p2v = v
				end
				local vi = va:index(p1.x + tx, p1.y + y, p1.z + tz)
				if cids[pi] ~= air then
					data[vi] = cids[pi]
					p2data[vi] = p2v
					n = n + 1
				elseif not skip_air then
					data[vi] = air
					p2data[vi] = p2v
				end
			end
		end
	end
	vm:set_data(data)
	vm:set_param2_data(p2data)
	vm:write_to_map(true)
	local function at(rel)
		if turned then rel = {x = sx - 1 - rel.x, y = rel.y, z = sz - 1 - rel.z} end
		return vector.add(p1, rel)
	end
	for _, m in ipairs(tpl.metas or {}) do core.get_meta(at(m.p)):from_table(m.m) end
	for _, t in ipairs(tpl.timers or {}) do core.get_node_timer(at(t.p)):set(t.t, t.e) end
	return n
end

-- Place ready-made adventure `tname` with its south-west corner's ground
-- layer at `at` (the block a player stands on), and make it this land's
-- adventure (closed, not yet saved). `turned`: half a turn round, so the
-- entrance is at the north end instead of the south. Calls done(ok,
-- message) when finished (the area is loaded first).
local CLEAR_ABOVE = 40

-- The land's own ground, as the map makes it: on a land of the flipped
-- (futuristic) realm, castle level 8 and up, tarmac over stone; otherwise
-- grass over dirt. A ready-made adventure's ground is grass over dirt, and
-- takes the land's instead, so it fits the land (whatever was left on the
-- spot before, such as an earlier adventure's grass).
local function land_ground(land)
	if land and (tonumber(land.level) or 0) >= 8 and core.registered_nodes["orthoverse_nodes:tarmac"] then
		return "orthoverse_nodes:tarmac", "default:stone"
	end
	return nil, nil
end

local function wear_land_ground(p1, p2, ground, top, under)
	local swap = {}
	if top and top ~= "default:dirt_with_grass" then swap["default:dirt_with_grass"] = core.get_content_id(top) end
	if under and under ~= "default:dirt" then swap["default:dirt"] = core.get_content_id(under) end
	if not next(swap) then return end
	local ids = {}
	for from, to in pairs(swap) do ids[core.get_content_id(from)] = to end
	local a, b = vector.new(p1.x, ground - 3, p1.z), vector.new(p2.x, ground, p2.z)
	local vm = VoxelManip()
	local e1, e2 = vm:read_from_map(a, b)
	local va = VoxelArea(e1, e2)
	local data = vm:get_data()
	for i in va:iterp(a, b) do
		local to = ids[data[i]]
		if to then data[i] = to end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

local function place_template(tname, at, by, done, turned)
	local info = core.parse_json(read_file(TEMPLATES_DIR .. "/" .. tname .. ".json") or "", nil)
	local data = read_file(TEMPLATES_DIR .. "/" .. tname .. ".we")
	local compact
	if not data then
		local blob = read_file(TEMPLATES_DIR .. "/" .. tname .. ".ovt")
		local ok, t = pcall(function() return blob and core.deserialize(core.decompress(blob, "zstd"), true) end)
		compact = ok and type(t) == "table" and type(t.size) == "table" and t or nil
	end
	if type(info) ~= "table" or type(info.size) ~= "table" or not (data or compact) then
		return done(false, "There is no ready-made adventure called " .. tname .. ".")
	end
	if turned and info.whole_land then return done(false, (info.name or tname) .. " cannot be turned round.") end
	if turned then info = half_turn_info(info) end
	if data and not (worldedit and worldedit.deserialize) then return done(false, "Placing it needs WorldEdit.") end
	local p1 = vector.subtract(vector.round(at), vector.new(0, info.ground or 0, 0))
	if info.whole_land then
		-- the whole land, from its south-west corner, its ground the map's
		if not compact then return done(false, "A whole-land adventure must be in the compact form (.ovt).") end
		local C = orthoverse.coords
		local x0 = math.floor((p1.x + C.HALF) / C.LAND) * C.LAND - C.HALF
		local z0 = math.floor((p1.z + C.HALF) / C.LAND) * C.LAND - C.HALF
		local G = tonumber(core.get_mapgen_setting("mgflat_ground_level")) or 8
		p1 = vector.new(x0, G - (info.ground or 0), z0)
	end
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
	-- Above the ground, everything is cleared to well over the template's
	-- top (trees, hills), so nothing hangs over a low or sunken adventure
	local top = vector.new(p2.x, math.max(p2.y, p1.y + (info.ground or 0) + CLEAR_ABOVE), p2.z)
	local low = vector.subtract(p1, vector.new(0, 24, 0))
	for _, nd in ipairs(info.nodes or {}) do low.y = math.min(low.y, p1.y + nd.y - 2) end
	core.emerge_area(low, top, function(_, _, left)
		if left > 0 then return end
		local ground = p1.y + (info.ground or 0)
		local surf, under = land_ground(land)
		local air = core.get_content_id("air")
		if info.keep_ground then
			-- The land stays as it is (its hills and trees): only the boxes it
			-- asks for are cleared, and only its own blocks are set
			for _, box in ipairs(info.clear or {}) do
				local a, b = offset(p1, box.min), offset(p1, box.max)
				for _, obj in ipairs(core.get_objects_in_area(a, vector.add(b, 1))) do
					if not obj:is_player() then obj:remove() end
				end
				fill(a, b, air)
			end
			local n = place_compact(p1, compact, false, true)
			-- and what it has outside its box (Tir Na Nog's gate, down on the ground)
			for _, nd in ipairs(info.nodes or {}) do
				if core.registered_nodes[nd.name] then
					core.set_node(offset(p1, nd), {name = nd.name, param2 = nd.param2 or 0})
					n = n + 1
				end
			end
			if orthoverse.note_built then orthoverse.note_built(p1, p2) end
			for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {"group:orthoverse_timer"})) do
				if not core.get_node_timer(pos):is_started() then core.get_node_timer(pos):start(1) end
			end
			local fp = info.footprint or {min = info.corner1, max = info.corner2}
			adventures[key] = {
				name = (info.name or tname):sub(1, 60), line = (info.line or ""):sub(1, 200), version = 0, open = false,
				limit = info.limit or LIMIT_DEFAULT, creator = by,
				corner1 = offset(p1, info.corner1), corner2 = offset(p1, info.corner2),
				start = offset(p1, info.start), arrival = offset(p1, info.arrival),
				rank_min = tonumber(info.rank_min), rank_max = tonumber(info.rank_max),
				footprint = {min = offset(p1, fp.min), max = offset(p1, fp.max)},
				kit = type(info.kit) == "table" and info.kit or nil,
				catch_falls = info.catch_falls and true or nil,
				approach = info.approach and offset(p1, info.approach) or nil,
				approach_line = info.approach_line and info.approach_line:sub(1, 200) or nil,
				finish_xp = tonumber(info.finish_xp),
				maze = info.maze and {min = offset(p1, info.maze.min), max = offset(p1, info.maze.max),
					wall = info.maze.wall} or nil,
			}
			save_def(key)
			write_public()
			return done(true, ("%s placed on %s (%d blocks). It is closed: look round and change what you like, then " ..
				"/adventure save and /adventure open."):format(adventures[key].name, land.name, n))
		end
		for _, obj in ipairs(core.get_objects_in_area(vector.new(p1.x, ground, p1.z), top)) do
			if not obj:is_player() then obj:remove() end
		end
		fill(vector.new(p1.x, ground, p1.z), top, air)
		local dig = {}
		for _, box in ipairs(info.dig or {}) do
			dig[#dig + 1] = {offset(p1, box.min), offset(p1, box.max)}
			fill(dig[#dig][1], dig[#dig][2], air)
		end
		underpin(p1, p2, ground, dig)
		local n
		if compact then n = place_compact(p1, compact, turned)
		elseif turned then n = deserialize_half_turned(p1, info.size, data)
		else n = worldedit.deserialize(p1, data) end
		if not n then return done(false, "The file " .. tname .. (compact and ".ovt" or ".we") .. " could not be read.") end
		-- so a castle upgrade or a flip of the land keeps it
		if orthoverse.note_built then orthoverse.note_built(p1, p2) end
		-- its ground takes the land's: tarmac on a land of the flipped realm
		wear_land_ground(p1, p2, ground, surf, under)
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
		done(true, ("%s placed on %s (%d blocks)%s. It is closed: look round and change what you like, then " ..
			"/adventure save and /adventure open."):format(adventures[key].name, land.name, n,
			turned and ", turned round (its entrance at the north end)" or ""))
	end)
end

------------------------------------------------------------------------------
-- Going to an adventure: anyone, to the entrance (the arrival point) of an
-- open one, outside the gate. Not during a run; once every GO_EVERY seconds.

local GO_EVERY = 30
local went = {}   -- name -> when they last went

-- A name to match against: lower case, letters and digits only ("St
-- Morwen's" and "st morwens" match)
local function plain(s) return (s or ""):lower():gsub("[^%w]", "") end

local function ranks_of(def)
	return ("ranks %d to %d"):format(def.rank_min or RANK_MIN_DEFAULT, def.rank_max or RANK_MAX_DEFAULT)
end

-- Is an arrival point safe to put a player at? Solid ground under the feet,
-- room to stand (nothing solid, no water to drown in), and nothing that
-- hurts (lava, fire) within two blocks. Returns true, or false and why. (A
-- holder could otherwise set it in the air, or dig a pit or pour lava under
-- it, and send strangers there from the Adventures page.) Checked when the
-- arrival point is set, when the adventure is opened, and before anyone is
-- sent there; if it is not safe then, the player is not moved at all.
local function safe_arrival(at)
	local feet = vector.new(math.floor(at.x + 0.5), math.floor(at.y + 0.5), math.floor(at.z + 0.5))
	local function def_at(p)
		local n = core.get_node(p).name
		return core.registered_nodes[n], n
	end
	local below, bn = def_at(vector.offset(feet, 0, -1, 0))
	if bn == "ignore" then return false, "it is not loaded" end
	if not (below and below.walkable) then return false, "there is no solid ground under it" end
	for dy = 0, 1 do
		local d, n = def_at(vector.offset(feet, 0, dy, 0))
		if n == "ignore" then return false, "it is not loaded" end
		if not d or d.walkable or (d.drowning or 0) > 0 then return false, "there is no room to stand there" end
	end
	for dz = -2, 2 do for dy = -1, 2 do for dx = -2, 2 do
		local d = def_at(vector.offset(feet, dx, dy, dz))
		if d and (d.damage_per_second or 0) > 0 then return false, "something that burns is next to it" end
	end end end
	return true
end

-- Take `name` to the entrance of the open adventure on land `key`. Used by
-- /adventure go and by the website (a player who chose an adventure on the
-- Adventures page arrives there on joining: orthoverse_wallets).
local function travel(name, key)
	local def = adventures[key]
	if not (def and def.open and def.arrival) then return false, "That adventure is not open." end
	for _, run in pairs(runs) do
		if run.members[name] then return false, "Not during a run: /adventure leave first." end
	end
	-- (or, for one whose gate is hard to get to, as Tir Na Nog's on the top of
	-- a mountain, where the way up to it starts)
	local at = vec(def.approach or def.arrival)
	core.emerge_area(vector.subtract(at, 16), vector.add(at, 16), function(_, _, remaining)
		if remaining > 0 then return end
		local p = core.get_player_by_name(name)
		if not p or p:get_hp() <= 0 then return end
		for _, run in pairs(runs) do
			if run.members[name] then return end   -- went through a gate meanwhile
		end
		local ok, why = safe_arrival(at)
		if not ok then
			core.log("warning", ("[orthoverse_adventure] the arrival point of %s (%s) is not safe (%s): %s was not sent there")
				:format(def.name, key, why, name))
			core.chat_send_player(name, "The entrance to " .. def.name .. " is not safe to arrive at just now (" .. why ..
				"), so you have not been sent there.")
			if def.creator then
				core.chat_send_player(def.creator, "Players cannot arrive safely at the entrance to " .. def.name .. " (" ..
					why .. "). Stand somewhere safe outside the dungeon and /adventure arrival.")
			end
			return
		end
		p:set_pos(orthoverse.bodies and orthoverse.bodies.place(p, at) or at)
		local face = def.approach and def.arrival or def.start
		if face then
			local d = vector.subtract(vec(face), at)
			p:set_look_horizontal(math.atan2(-d.x, d.z))
		end
		local land = orthoverse.lands[key]
		core.chat_send_player(name, ("Welcome to %s%s: %s. %s %s"):format(def.name,
			land and (", on " .. land.name) or "", ranks_of(def), def.line or "",
			def.approach_line or "Right-click the gate to go in."))
	end)
	core.log("action", ("[orthoverse_adventure] %s goes to %s (%s)"):format(name, def.name, key))
	return true, "Going to " .. def.name .. "..."
end
orthoverse.adventure.travel = travel

local function go(name, player, rest)
	local open = {}
	for key, def in pairs(adventures) do
		if def.open and def.arrival then open[#open + 1] = {key = key, def = def} end
	end
	table.sort(open, function(a, b) return (a.def.name or "") < (b.def.name or "") end)
	if rest == "" then
		if #open == 0 then return true, "No adventures are open yet." end
		local names = {}
		for i, a in ipairs(open) do names[i] = a.def.name .. " (" .. ranks_of(a.def) .. ")" end
		return true, "Open adventures: " .. table.concat(names, ", ") .. ". To go to one: /adventure go <name>"
	end
	for _, run in pairs(runs) do
		if run.members[name] then return false, "Not during a run: /adventure leave first." end
	end
	if player:get_hp() <= 0 then return false, "Not while you are dead." end
	local want = plain(rest)
	if want == "" then return false, "Which adventure? /adventure go <name>" end
	local exact, part = {}, {}
	for _, a in ipairs(open) do
		local n, land = plain(a.def.name), orthoverse.lands[a.key]
		if n == want or a.key == rest then exact[#exact + 1] = a
		elseif n:find(want, 1, true) or (land and plain(land.name) == want) then part[#part + 1] = a end
	end
	local found = #exact > 0 and exact or part
	if #found == 0 then
		return false, "No open adventure called \"" .. rest .. "\". /adventure go on its own lists them."
	end
	if #found > 1 then
		local names = {}
		for i, a in ipairs(found) do names[i] = a.def.name end
		return false, "Which one? " .. table.concat(names, ", ")
	end
	local t = now()
	if went[name] and t - went[name] < GO_EVERY and not is_admin(name) then
		return false, ("Wait %d seconds before going again."):format(GO_EVERY - (t - went[name]))
	end
	went[name] = t
	return travel(name, found[1].key)
end
core.register_on_leaveplayer(function(player) went[player:get_player_name()] = nil end)

------------------------------------------------------------------------------
-- The command

local HELP = table.concat({
	"To go to an open adventure's entrance: /adventure go <name>. On its own,",
	"/adventure go lists the open adventures.",
	"",
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
	"/adventure place <name> [north]   (Admin) Place a ready-made adventure, standing on the ground",
	"   at its south-west corner (north: turned round, its entrance at the north end);",
	"   /adventure place on its own lists them.",
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
	params = "[go [<name>] | leave | place <name> [north] | create <name> | name <text> | line <text> | corner1 | corner2 | start | arrival | limit <minutes> | ranks <lowest> <highest> | save | open | close | reset | delete]",
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
		if cmd == "go" then return go(name, player, rest) end
		if cmd == "status" then
			if not def then return false, "This land has no adventure." end
			return true, status(key, def)
		end
		if cmd == "place" then
			if not is_admin(name) then return false, "Placing a ready-made adventure is for the admin." end
			if rest == "" then
				local names = template_names()
				return true, #names > 0 and ("Ready-made adventures: " .. table.concat(names, ", ") ..
					". Stand on the ground at the south-west corner and type /adventure place <name>, " ..
					"or /adventure place <name> north for its entrance at the north end.")
					or "There are no ready-made adventures in " .. TEMPLATES_DIR .. "."
			end
			local tname, facing = rest:match("^(%S+)%s*(%S*)$")
			if not tname or not tname:match("^[%w_%-]+$") then return false, "No ready-made adventure called that." end
			if facing ~= "" and facing ~= "north" and facing ~= "south" then
				return false, "Its entrance can be at the south end (as made) or the north: /adventure place " .. tname .. " north"
			end
			local feet = vector.round(player:get_pos())
			place_template(tname, vector.new(feet.x, feet.y - 1, feet.z), name, function(ok, msg)
				core.chat_send_player(name, msg)
			end, facing == "north")
			return true, "Placing " .. tname .. "…"
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
			local ok, why = safe_arrival(player:get_pos())
			if not ok then return false, "Players could not arrive safely here: " .. why .. ". Stand on solid ground." end
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
			local ok, why = safe_arrival(vec(def.arrival))
			if not ok then
				return false, "Players could not arrive safely at the arrival point: " .. why ..
					". Fix it, or stand somewhere safe outside the dungeon and /adventure arrival."
			end
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
orthoverse.adventure.capture = capture   -- for tools/adventures: a ready-made adventure in the compact form

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
-- One exception: a party in a run may light its way, placing torches (found
-- in loot chests) in the air and taking them down again. The dungeon is put
-- back as saved after the run, torches and all.
local TORCHES = {["default:torch"] = true, ["default:torch_wall"] = true, ["default:torch_ceiling"] = true}
local function torch_ok(name, key, pos)
	local run = runs[key]
	if not (run and run.members[name]) then return false end
	local here = core.get_node(pos).name
	if TORCHES[here] then return true end   -- taking one down
	local player = core.get_player_by_name(name)
	local nd = core.registered_nodes[here]
	return player ~= nil and player:get_wielded_item():get_name() == "default:torch"
		and nd ~= nil and nd.buildable_to == true and (nd.liquidtype or "none") == "none"
end
local old_is_protected = core.is_protected
function core.is_protected(pos, name)
	if name and name ~= "" then
		local key, def = adventure_of_land(pos)
		if def and (inside(def, pos) or in_footprint(def, vector.round(pos))) and not may_manage(name, key) then
			-- (a torch is fine whoever holds the land)
			return not torch_ok(name, key, vector.round(pos))
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
-- A finish of another look (orthoverse_scifi's black box) does what this does
orthoverse.adventure.at_finish = at_finish
orthoverse.adventure.place = place_template
orthoverse.adventure.in_run = function(name)
	for key, run in pairs(runs) do
		if run.members[name] then return key end
	end
end
