-- orthoverse_lands: loads the frozen land table and shares it with the mapgen threads.
-- Lands placed later for newly revealed tokens (the chain service's
-- new-lands.json) are added while the server runs, and their terrain is made.
-- Lands are built from their current castle level (the chain service's
-- land-levels.json); a land whose level changes is made again.

local modpath = core.get_modpath(core.get_current_modname())

orthoverse = rawget(_G, "orthoverse") or {}
local C = dofile(modpath .. "/coords.lua")
orthoverse.coords = C
orthoverse.henge_gates = dofile(modpath .. "/henges.lua")

local f = assert(io.open(modpath .. "/data/lands.json", "r"))
local raw = f:read("*a")
f:close()
local data = assert(core.parse_json(raw), "orthoverse_lands: lands.json did not parse")
assert(data.format == 1, "orthoverse_lands: unsupported lands.json format")

orthoverse.lands = data.lands
orthoverse.henges = data.henges
orthoverse.seas = {}
for _, key in ipairs(data.seas or {}) do orthoverse.seas[key] = true end

local count = 0
for _ in pairs(data.lands) do count = count + 1 end
core.log("action", ("[orthoverse_lands] %d lands, henges loaded"):format(count))

-- The mapgen environment cannot see this one; hand the data over via IPC.
-- The mapgen threads reload the lands when the version changes.
local lands_version = 0
local function publish()
	lands_version = lands_version + 1
	core.ipc_set("orthoverse:lands", { lands = orthoverse.lands, henges = orthoverse.henges })
	core.ipc_set("orthoverse:lands_version", lands_version)
end
core.ipc_set("orthoverse:lands_path", modpath)

------------------------------------------------------------------------------
-- New lands

-- Written by the chain service (OV_DATA/chain, mounted into the world folder)
local NEW_LANDS = core.get_worldpath() .. "/orthoverse_chain/new-lands.json"
local LAND_LEVELS = core.get_worldpath() .. "/orthoverse_chain/land-levels.json"
-- The lands that have changed, and when, for the web map and the token cards
-- (the map service draws those again)
local CHANGED_FILE = core.get_worldpath() .. "/orthoverse_changed_lands.json"
local storage = core.get_mod_storage()

-- {key = time} of the new lands whose terrain has been made
local function made_lands()
	local s = storage:get_string("made")
	return s ~= "" and core.parse_json(s) or {}
end

-- A table field of a JSON file from the chain service, or {} if it is not
-- there (yet) or does not parse
local function read_chain(path, field)
	local f = io.open(path, "r")
	if not f then return {} end
	local raw = f:read("*a")
	f:close()
	local ok, parsed = pcall(core.parse_json, raw)
	if not ok or type(parsed) ~= "table" or type(parsed[field]) ~= "table" then
		core.log("warning", "[orthoverse_lands] " .. path .. " did not parse; trying again later")
		return {}
	end
	return parsed[field]
end

local function read_new_lands()
	return read_chain(NEW_LANDS, "lands")
end

local function valid(key, land)
	local lx, lz = key:match("^(%-?%d+):(%-?%d+)$")
	lx, lz = tonumber(lx), tonumber(lz)
	return lx and math.max(math.abs(lx), math.abs(lz)) <= C.MAP_RADIUS
		and type(land) == "table" and type(land.token) == "string"
		and land.token:match("^0x%x+$") and #land.token >= 38
		and type(land.name) == "string" and tonumber(land.level)
end

-- Add the new lands that are not in the table yet (a land is never moved or
-- removed). Returns the keys added.
local function add_new_lands()
	local added = {}
	for key, land in pairs(read_new_lands()) do
		if not orthoverse.lands[key] and not orthoverse.henges[key] then
			if valid(key, land) then
				land.level = tonumber(land.level)
				orthoverse.lands[key] = land
				added[#added + 1] = key
			else
				core.log("warning", "[orthoverse_lands] new land " .. tostring(key) .. " is not valid; ignored")
			end
		end
	end
	return added
end

-- The mapchunks to make again for a new land: its own, and those of the sea
-- cells around it, whose beaches now rise to meet it. A land is exactly one
-- mapchunk across (chunksize 6); in height, the two chunks that hold the
-- surface (y -48..143).
local function regen_area(lx, lz)
	local x0, zn = C.land_origin(lx, lz)
	return vector.new(x0, -48, zn - C.LAND + 1), vector.new(x0 + C.LAND - 1, 143, zn)
end

local function is_sea(lx, lz)
	local key = C.key(lx, lz)
	return math.max(math.abs(lx), math.abs(lz)) <= C.MAP_RADIUS
		and not orthoverse.lands[key] and not orthoverse.henges[key]
end

-- {key = time of the last change}: blocks placed or dug, lands made again or
-- added (and the sea around them), written out every 30 seconds
local changed = (function()
	local f = io.open(CHANGED_FILE, "r")
	if not f then return {} end
	local raw = f:read("*a")
	f:close()
	local ok, parsed = pcall(core.parse_json, raw)
	return ok and type(parsed) == "table" and type(parsed.lands) == "table" and parsed.lands or {}
end)()
local changes_unsaved = false

local function note_changed(lx, lz)
	if math.max(math.abs(lx), math.abs(lz)) > C.MAP_RADIUS then return end
	changed[C.key(lx, lz)] = os.time()
	changes_unsaved = true
end

local function write_changes()
	if not changes_unsaved then return end
	local f = io.open(CHANGED_FILE .. ".tmp", "w")
	if not f then return end
	f:write(core.write_json({ updated = os.time(), lands = changed }))
	f:close()
	os.rename(CHANGED_FILE .. ".tmp", CHANGED_FILE)
	changes_unsaved = false
end
local function save_changes()
	write_changes()
	core.after(30, save_changes)
end
core.after(30, save_changes)
core.register_on_shutdown(write_changes)

-- The tiles (16 x 16, 36 to a land) that players have built on: blocks
-- placed or dug there. A castle upgrade makes a land again but keeps these
-- tiles as they are. {key = {[tile index] = true}}
local built = (function()
	local s = storage:get_string("built")
	local t = s ~= "" and core.parse_json(s) or {}
	-- JSON has string keys; the tile indices are numbers
	local out = {}
	for key, tiles in pairs(t) do
		out[key] = {}
		for i in pairs(tiles) do out[key][tonumber(i)] = true end
	end
	return out
end)()
local built_unsaved = false

local function save_built()
	if not built_unsaved then return end
	local t = {}
	for key, tiles in pairs(built) do
		t[key] = {}
		for i in pairs(tiles) do t[key][tostring(i)] = true end
	end
	storage:set_string("built", core.write_json(t))
	built_unsaved = false
end
local function save_built_loop()
	save_built()
	core.after(10, save_built_loop)
end
core.after(10, save_built_loop)
core.register_on_shutdown(save_built)

local function note_node(pos)
	local lx, lz = C.land_of(pos.x, pos.z)
	note_changed(lx, lz)
	local key = C.key(lx, lz)
	if orthoverse.lands[key] then
		local tile = C.tile_index(C.local_uv(pos.x, pos.z))
		built[key] = built[key] or {}
		if not built[key][tile] then
			built[key][tile] = true
			built_unsaved = true
		end
	end
end
core.register_on_placenode(note_node)
core.register_on_dignode(note_node)

local pending = {}   -- new lands whose terrain is being made

-- The castle level each land's terrain was last made with: the fixed lands
-- were made with their level in lands.json, until made again
local made_level = (function()
	local s = storage:get_string("levels")
	return s ~= "" and core.parse_json(s) or {}
end)()
local fixed_level = {}
for key, land in pairs(data.lands) do fixed_level[key] = tonumber(land.level) or 0 end
local function level_made(key)
	return made_level[key] or fixed_level[key]
end

-- Builds from before tiles were recorded: a land players changed, and that
-- was not made again or newly made since, is kept whole (all 36 tiles), so
-- nothing built before is lost. Done once.
if storage:get_string("built_backfilled") == "" then
	local made = made_lands()
	local n = 0
	for key, when in pairs(changed) do
		local new_land = made[key]
		local by_players = orthoverse.lands[key] and not made_level[key]
			and (not new_land or when > new_land + 60)
		if by_players and not built[key] then
			built[key] = {}
			for i = 0, 35 do built[key][i] = true end
			n = n + 1
		end
	end
	built_unsaved = true
	save_built()
	storage:set_string("built_backfilled", "1")
	core.log("action", ("[orthoverse_lands] %d lands built on before tiles were recorded: kept whole on upgrades"):format(n))
end

-- The built tiles of a land, as a list of {x1, x2, z1, z2} column bounds
local function built_columns(key, lx, lz)
	local cols = {}
	for tile in pairs(built[key] or {}) do
		local tu, tv = tile % 6, math.floor(tile / 6)
		local xa, za = C.world_xz(lx, lz, tu * C.TILE, tv * C.TILE)
		local xb, zb = C.world_xz(lx, lz, tu * C.TILE + C.TILE - 1, tv * C.TILE + C.TILE - 1)
		cols[#cols + 1] = {math.min(xa, xb), math.max(xa, xb), math.min(za, zb), math.max(za, zb)}
	end
	return cols
end

-- Save everything in these columns of p1..p2: nodes, metadata (chests,
-- furnaces, signs) and running node timers
local function save_columns(p1, p2, cols)
	core.load_area(p1, p2)
	local vm = core.get_voxel_manip(p1, p2)
	local emin, emax = vm:get_emerged_area()
	local area = VoxelArea(emin, emax)
	local data, p2d, light = vm:get_data(), vm:get_param2_data(), vm:get_light_data()
	local saved = {nodes = {}, metas = {}}
	for _, c in ipairs(cols) do
		local n, p, l = {}, {}, {}
		local k = 0
		for z = c[3], c[4] do
			for y = p1.y, p2.y do
				local vi = area:index(c[1], y, z)
				for _ = c[1], c[2] do
					k = k + 1
					n[k], p[k], l[k] = data[vi], p2d[vi], light[vi]
					vi = vi + 1
				end
			end
		end
		saved.nodes[#saved.nodes + 1] = {c = c, n = n, p = p, l = l}
		for _, pos in ipairs(core.find_nodes_with_meta(vector.new(c[1], p1.y, c[3]), vector.new(c[2], p2.y, c[4]))) do
			local timer = core.get_node_timer(pos)
			saved.metas[#saved.metas + 1] = {pos = pos, meta = core.get_meta(pos):to_table(),
				timer = timer:is_started() and {timer:get_timeout(), timer:get_elapsed()} or nil}
		end
	end
	return saved
end

local function restore_columns(p1, p2, saved)
	local vm = core.get_voxel_manip(p1, p2)
	local emin, emax = vm:get_emerged_area()
	local area = VoxelArea(emin, emax)
	local data, p2d, light = vm:get_data(), vm:get_param2_data(), vm:get_light_data()
	for _, s in ipairs(saved.nodes) do
		local c, k = s.c, 0
		for z = c[3], c[4] do
			for y = p1.y, p2.y do
				local vi = area:index(c[1], y, z)
				for _ = c[1], c[2] do
					k = k + 1
					data[vi], p2d[vi], light[vi] = s.n[k], s.p[k], s.l[k]
					vi = vi + 1
				end
			end
		end
	end
	vm:set_data(data)
	vm:set_param2_data(p2d)
	vm:set_light_data(light)
	vm:write_to_map(true)
	for _, m in ipairs(saved.metas) do
		core.get_meta(m.pos):from_table(m.meta)
		if m.timer then core.get_node_timer(m.pos):set(m.timer[1], m.timer[2]) end
	end
end

local function make_terrain(key)
	pending[key] = true
	local lx, lz = key:match("^(%-?%d+):(%-?%d+)$")
	lx, lz = tonumber(lx), tonumber(lz)
	local cells = {{lx, lz}}
	for dz = -1, 1 do
		for dx = -1, 1 do
			if (dx ~= 0 or dz ~= 0) and is_sea(lx + dx, lz + dz) then
				cells[#cells + 1] = {lx + dx, lz + dz}
			end
		end
	end
	local left = #cells
	for _, c in ipairs(cells) do
		local p1, p2 = regen_area(c[1], c[2])
		core.delete_area(p1, p2)
		core.emerge_area(p1, p2, function(_, _, remaining)
			if remaining > 0 then return end
			left = left - 1
			if left == 0 then
				local made = made_lands()
				made[key] = os.time()
				storage:set_string("made", core.write_json(made))
				made_level[key] = orthoverse.lands[key].level
				storage:set_string("levels", core.write_json(made_level))
				for _, c2 in ipairs(cells) do note_changed(c2[1], c2[2]) end
				pending[key] = nil
				core.log("action", ("[orthoverse_lands] terrain made for new land %s (%s)")
					:format(orthoverse.lands[key].name, key))
			end
		end)
	end
end

-- Lands whose level changed: made again, a few at a time
local remake_queue, remaking, queued = {}, 0, {}
local REMAKE_AT_ONCE = 4

local function pump()
	while remaking < REMAKE_AT_ONCE and #remake_queue > 0 do
		local key = table.remove(remake_queue, 1)
		local land = orthoverse.lands[key]
		local lx, lz = key:match("^(%-?%d+):(%-?%d+)$")
		local p1, p2 = regen_area(tonumber(lx), tonumber(lz))
		local level = land.level
		remaking = remaking + 1
		-- Tiles players have built on are kept as they are
		local cols = built_columns(key, tonumber(lx), tonumber(lz))
		local saved = #cols > 0 and save_columns(p1, p2, cols)
		core.delete_area(p1, p2)
		core.emerge_area(p1, p2, function(_, _, remaining)
			if remaining > 0 then return end
			if saved then restore_columns(p1, p2, saved) end
			remaking = remaking - 1
			queued[key] = nil
			made_level[key] = level
			storage:set_string("levels", core.write_json(made_level))
			core.log("action", ("[orthoverse_lands] %s (%s) made again at level %d, %d of 36 tiles kept as built")
				:format(land.name, key, level, #cols))
			note_changed(tonumber(lx), tonumber(lz))
			pump()
		end)
	end
end

-- Take the current levels; returns the keys whose level changed
local FRESH_LEVELS = core.get_worldpath() .. "/orthoverse_auth/levels.json"

-- Every land's current level: the chain service's daily land-levels.json,
-- overridden by levels the auth service read from the contract later (just
-- after an upgrade or a flip on the lands page). Both stamp their times in
-- ISO 8601 (UTC), which compare as text.
local function current_levels()
	local f = io.open(LAND_LEVELS, "r")
	local chain_updated = ""
	local levels = {}
	if f then
		local ok, parsed = pcall(core.parse_json, f:read("*a"))
		f:close()
		if ok and type(parsed) == "table" and type(parsed.levels) == "table" then
			levels = parsed.levels
			chain_updated = type(parsed.updated) == "string" and parsed.updated or ""
		end
	end
	f = io.open(FRESH_LEVELS, "r")
	if f then
		local ok, parsed = pcall(core.parse_json, f:read("*a"))
		f:close()
		if ok and type(parsed) == "table" and type(parsed.levels) == "table" then
			for key, v in pairs(parsed.levels) do
				if type(v) == "table" and tonumber(v.level) and type(v.checked) == "string"
						and v.checked > chain_updated then
					levels[key] = tonumber(v.level)
				end
			end
		end
	end
	return levels
end

local function update_levels()
	local changed = {}
	for key, level in pairs(current_levels()) do
		local land = orthoverse.lands[key]
		level = tonumber(level)
		if land and not orthoverse.henges[key] and level and level >= 0 and level < 16
				and level ~= land.level then
			core.log("action", ("[orthoverse_lands] %s (%s): level %d -> %d")
				:format(land.name, key, land.level, level))
			land.level = level
			changed[#changed + 1] = key
		end
	end
	return changed
end

local function remake_changed()
	local made = made_lands()
	for key, land in pairs(orthoverse.lands) do
		-- (new lands not made yet are made below, with their current level)
		local known = data.lands_fixed[key] or made[key]
		if known and not orthoverse.henges[key] and not queued[key] and not pending[key]
				and level_made(key) ~= land.level then
			queued[key] = true
			remake_queue[#remake_queue + 1] = key
		end
	end
	pump()
end

local function check_new_lands()
	local added = add_new_lands()
	local changed = update_levels()
	if #added > 0 or #changed > 0 then
		publish()
	end
	remake_changed()
	-- Terrain for every new land that does not have it yet (also after a
	-- restart part-way)
	local made = made_lands()
	for key, land in pairs(orthoverse.lands) do
		if not data.lands_fixed[key] and not made[key] and not pending[key] then
			core.log("action", ("[orthoverse_lands] new land %s at %s"):format(land.name, key))
			make_terrain(key)
		end
	end
end

-- The fixed lands, so that new ones can be told apart
data.lands_fixed = {}
for key in pairs(data.lands) do data.lands_fixed[key] = true end

add_new_lands()
update_levels()
publish()

-- Terrain is made once the server runs (emerging needs the map); then every
-- minute, look for lands placed since
local function loop()
	check_new_lands()
	core.after(60, loop)
end
core.after(5, loop)

-- Land at a Luanti position (or nil for sea / border).
function orthoverse.land_at(pos)
	local lx, lz = C.land_of(pos.x, pos.z)
	local key = C.key(lx, lz)
	return orthoverse.lands[key], key, lx, lz
end

core.register_chatcommand("whereami", {
	description = "Show which Orthoverse land you are standing on",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then return false, "No player." end
		local land, key = orthoverse.land_at(player:get_pos())
		if not land then
			return true, "Land " .. key .. ": unclaimed sea or border."
		end
		local h = orthoverse.henges[key]
		return true, ("Land %s: %s (level %d)%s"):format(
			key, land.name, land.level, h and (", " .. h.name) or "")
	end,
})

-- /goto <land>: teleport to a land by name (or old coordinates such as 12:-3),
-- for players with the teleport privilege. You arrive on the land's southern
-- side, facing north towards its centre, on the ground.
local function plain(s)
	return s:lower():gsub("\195[\164\165\160\161\162\163]", "a"):gsub("\195\182", "o")
		:gsub("\195[\169\168\170\171]", "e"):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function find_lands(query)
	local q = plain(query)
	local all = {}
	for key, land in pairs(orthoverse.lands) do all[key] = land.name end
	for key, h in pairs(orthoverse.henges) do all[key] = h.name or all[key] end
	if all[q] then return {q}, all end
	local cx, cz = q:match("^(%-?%d+)%s*:%s*(%-?%d+)$")
	if cx and math.max(math.abs(tonumber(cx)), math.abs(tonumber(cz))) <= C.MAP_RADIUS then
		return {tonumber(cx) .. ":" .. tonumber(cz)}, all     -- sea, by coordinates
	end
	local exact, partial = {}, {}
	for key, name in pairs(all) do
		local n = plain(name)
		if n == q then exact[#exact + 1] = key
		elseif n:find(q, 1, true) then partial[#partial + 1] = key end
	end
	if #exact > 0 then return exact, all end
	table.sort(partial, function(a, b) return all[a] < all[b] end)
	return partial, all
end

local ARRIVE_U, ARRIVE_V = 48, 88

-- Teleport `name` to node x, z, standing on the ground there (generating the
-- area if need be), facing `yaw` (0 = north). `label` is what the welcome says.
function orthoverse.teleport_to(name, x, z, label, yaw)
	local top, bottom = vector.new(x, 120, z), vector.new(x, -20, z)
	core.emerge_area(bottom, top, function(_, _, remaining)
		if remaining > 0 then return end
		local player = core.get_player_by_name(name)
		if not player then return end
		local y = top.y
		while y > bottom.y do
			local def = core.registered_nodes[core.get_node({x = x, y = y, z = z}).name]
			if def and (def.walkable or def.liquidtype ~= "none") then break end
			y = y - 1
		end
		player:set_pos({x = x, y = y + 1, z = z})
		player:set_look_horizontal(yaw or 0)
		core.chat_send_player(name, "Welcome to " .. label .. ".")
	end)
end

-- Teleport `name` to the land at `key` ("x:z"): on its southern side, facing
-- north towards its centre
function orthoverse.teleport_to_land(name, key, label)
	local lx, lz = key:match("^(%-?%d+):(%-?%d+)$")
	local x, z = C.world_xz(tonumber(lx), tonumber(lz), ARRIVE_U, ARRIVE_V)
	orthoverse.teleport_to(name, x, z, label, 0)
end

-- Who may use /goto: the teleport privilege (admins), or a land at castle
-- level GOTO_LEVEL or higher (either realm) held now
orthoverse.GOTO_LEVEL = 6
function orthoverse.may_goto(name)
	if core.check_player_privs(name, {teleport = true}) then return true end
	local w = orthoverse.wallets
	return w ~= nil and (w.highest_level(name) or -1) >= orthoverse.GOTO_LEVEL
end

core.register_chatcommand("goto", {
	params = "<land name or x:z>",
	description = "Teleport to an Orthoverse land (holders of a level 6 land and up)",
	privs = {},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false, "No player." end
		if not orthoverse.may_goto(name) then
			return false, "/goto is for holders of a land at castle level " .. orthoverse.GOTO_LEVEL ..
				" or higher. /home takes you to your own lands."
		end
		if param:match("^%s*$") then return false, "Which land? /goto <land name or x:z>" end
		local keys, all = find_lands(param)
		all = all or {}
		if #keys == 0 then return false, "No land called \"" .. param .. "\"." end
		if #keys > 1 then
			local names = {}
			for i = 1, math.min(#keys, 8) do names[i] = all[keys[i]] .. " (" .. keys[i] .. ")" end
			return false, ("%d lands match: %s%s"):format(#keys, table.concat(names, ", "),
				#keys > 8 and ", ..." or "")
		end
		local key = keys[1]
		local label = all[key] and (all[key] .. " (" .. key .. ")") or ("the sea at " .. key)
		orthoverse.teleport_to_land(name, key, label)
		return true, "Going to " .. label .. "..."
	end,
})
