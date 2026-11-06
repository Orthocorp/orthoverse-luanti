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
-- Which new lands have their terrain, for the web map's redraw
local MADE_FILE = core.get_worldpath() .. "/orthoverse_new_lands_made.json"
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

local function record_made()
	local made = made_lands()
	local f = io.open(MADE_FILE .. ".tmp", "w")
	if not f then return end
	f:write(core.write_json({ updated = os.time(), lands = made }))
	f:close()
	os.rename(MADE_FILE .. ".tmp", MADE_FILE)
end

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
				record_made()
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
		core.delete_area(p1, p2)
		core.emerge_area(p1, p2, function(_, _, remaining)
			if remaining > 0 then return end
			remaking = remaking - 1
			queued[key] = nil
			made_level[key] = level
			storage:set_string("levels", core.write_json(made_level))
			core.log("action", ("[orthoverse_lands] %s (%s) made again at level %d")
				:format(land.name, key, level))
			if remaking == 0 and #remake_queue == 0 then
				record_made()   -- the web map redraws
			else
				pump()
			end
		end)
	end
end

-- Take the current levels; returns the keys whose level changed
local function update_levels()
	local changed = {}
	for key, level in pairs(read_chain(LAND_LEVELS, "levels")) do
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
