-- orthoverse_admin: pre-generation and an overview map renderer.
-- The admin (setting "name") is given every privilege on joining.
--
-- Pre-generate on startup (then optionally shut down) with these settings:
--   orthoverse_pregen_radius = 3        -- lands around the origin, 0 = off
--   orthoverse_pregen_exit = true       -- shut down when finished
--   orthoverse_render_map = true        -- write a top-down PPM of the area
--   orthoverse_pregen_centre = 0,0      -- centre land (old coordinates)
--
-- Or in game (needs the "server" privilege): /pregen <radius>, /orthomap <radius>

local C = orthoverse.coords
local G = tonumber(core.get_mapgen_setting("mgflat_ground_level")) or 8
local W = tonumber(core.get_mapgen_setting("water_level")) or 1

-- Centre of the area, in old land coordinates (z grows southwards)
local centre_x, centre_z = 0, 0
do
	local s = core.settings:get("orthoverse_pregen_centre")
	if s then
		local a, b = s:match("^%s*(%-?%d+)%s*[,:]%s*(%-?%d+)%s*$")
		if a then centre_x, centre_z = tonumber(a), tonumber(b) end
	end
end

local function bounds(radius)
	local r = radius * C.LAND + C.HALF
	local ox, oz = centre_x * C.LAND, -centre_z * C.LAND
	return vector.new(ox - r, W - 16, oz - r), vector.new(ox + r - 1, G + 48, oz + r - 1)
end

-- Colours for the overview, by node name prefix match (first match wins)
local palette = {
	{"world_edge", {20, 20, 40}}, {"henge_portal", {60, 220, 120}},
	{"tarmac", {40, 40, 46}}, {"water", {40, 90, 190}},
	{"leaves", {40, 120, 40}}, {"needles", {30, 80, 50}}, {"tree", {90, 60, 30}},
	{"snow", {240, 240, 250}}, {"dirt_with_grass", {90, 160, 60}},
	{"coniferous", {80, 110, 60}}, {"dry", {160, 150, 80}},
	{"desert_sand", {210, 170, 110}}, {"silver_sand", {200, 200, 190}},
	{"sand", {225, 210, 150}}, {"desert_stone", {170, 100, 70}},
	{"gravel", {130, 125, 120}}, {"cobble", {110, 110, 110}},
	{"stonebrick", {150, 150, 155}}, {"stone_block", {170, 170, 175}},
	{"obsidian", {30, 20, 40}}, {"steel", {200, 200, 210}}, {"tin", {180, 180, 190}},
	{"copper", {200, 120, 60}}, {"bronze", {180, 110, 50}}, {"glass", {190, 230, 240}},
	{"sandstone", {220, 200, 140}}, {"meselamp", {250, 250, 150}},
	{"wool", {220, 80, 160}}, {"cactus", {40, 140, 40}}, {"flowers", {230, 90, 90}},
	{"grass", {110, 180, 70}}, {"shrub", {140, 110, 60}}, {"apple", {200, 40, 40}},
	{"stone", {125, 125, 125}},
}
local colour_cache = {}
local function colour(name)
	local col = colour_cache[name]
	if col then return col end
	col = {255, 0, 255}
	for _, p in ipairs(palette) do
		if name:find(p[1], 1, true) then col = p[2] break end
	end
	colour_cache[name] = col
	return col
end

-- In-game rendering loads every block it reads into the server, so keep it small.
local MAX_RENDER = 10

-- Top-down overview, north at the top. Read in tiles of one land row by up to
-- ten lands so memory stays small; one pixel per 'step' nodes (4 for big maps).
local function render(radius, path)
	local pmin, pmax = bounds(radius)
	local step = radius > 6 and 4 or 1
	local air = core.get_content_id("air")
	local ignore = core.CONTENT_IGNORE
	local names = {}
	local w = math.floor((pmax.x - pmin.x) / step) + 1
	local h = math.floor((pmax.z - pmin.z) / step) + 1
	local f = assert(io.open(path, "wb"))
	f:write(("P6\n%d %d\n255\n"):format(w, h))
	local band = C.LAND
	local data = {}
	for ztop = pmax.z, pmin.z, -band do
		local zbot = math.max(pmin.z, ztop - band + 1)
		local rows = {}
		for xs = pmin.x, pmax.x, 5 * C.LAND do
			local xe = math.min(pmax.x, xs + 5 * C.LAND - 1)
			-- A fresh VoxelManip per tile: read_from_map grows an existing one.
			local vm = VoxelManip()
			local emin, emax = vm:read_from_map(vector.new(xs, pmin.y, zbot),
				vector.new(xe, pmax.y, ztop))
			local area = VoxelArea(emin, emax)
			vm:get_data(data)
			for z = ztop, zbot, -1 do
				if (pmax.z - z) % step == 0 then
					local row = rows[z] or {}
					rows[z] = row
					for x = xs, xe do
						if (x - pmin.x) % step == 0 then
							local px = "\0\0\0"
							for y = pmax.y, pmin.y, -1 do
								local cid = data[area:index(x, y, z)]
								if cid ~= air and cid ~= ignore then
									local name = names[cid]
									if not name then
										name = core.get_name_from_content_id(cid)
										names[cid] = name
									end
									local base = colour(name)
									-- shade by height so hills read
									local s = math.max(0.55, math.min(1.3, 0.85 + (y - G) * 0.025))
									px = string.char(math.min(255, math.floor(base[1] * s)),
										math.min(255, math.floor(base[2] * s)),
										math.min(255, math.floor(base[3] * s)))
									break
								end
							end
							row[#row + 1] = px
						end
					end
				end
			end
		end
		for z = ztop, zbot, -1 do
			if rows[z] then f:write(table.concat(rows[z])) end
		end
	end
	f:close()
	return w, h
end

-- Generate one row of lands at a time, so the emerge queue stays small even for
-- the whole map.
local function pregen(radius, done)
	local pmin, pmax = bounds(radius)
	local t0 = core.get_us_time()
	core.log("action", ("[orthoverse_admin] pre-generating %s to %s"):format(
		core.pos_to_string(pmin), core.pos_to_string(pmax)))
	local zrow = pmin.z
	local function next_row()
		if zrow > pmax.z then
			local secs = (core.get_us_time() - t0) / 1e6
			core.log("action", ("[orthoverse_admin] pre-generation done in %.1f s"):format(secs))
			if done then done(secs) end
			return
		end
		local z0, z1 = zrow, math.min(pmax.z, zrow + C.LAND - 1)
		zrow = z1 + 1
		core.emerge_area(vector.new(pmin.x, pmin.y, z0), vector.new(pmax.x, pmax.y, z1),
			function(_, _, remaining)
				if remaining == 0 then
					local done_rows = math.floor((zrow - pmin.z) / C.LAND)
					local all_rows = 2 * radius + 1
					if done_rows % 10 == 0 or done_rows == all_rows then
						core.log("action", ("[orthoverse_admin] %d/%d land rows, %.0f s"):format(
							done_rows, all_rows, (core.get_us_time() - t0) / 1e6))
					end
					core.after(0, next_row)
				end
			end)
	end
	next_row()
end

core.register_chatcommand("pregen", {
	params = "<radius in lands>",
	privs = {server = true},
	func = function(name, param)
		local r = tonumber(param) or 1
		pregen(r, function(secs)
			core.chat_send_player(name, ("Pre-generated radius %d in %.1f s"):format(r, secs))
		end)
		return true, "Started."
	end,
})

core.register_chatcommand("orthomap", {
	params = "<radius in lands, at most 10>",
	privs = {server = true},
	func = function(name, param)
		local r = tonumber(param) or 1
		if r > MAX_RENDER then
			return false, "Too big to render in game (it loads every block); " ..
				"use tools/render_map.py on map.sqlite instead."
		end
		local path = core.get_worldpath() .. "/orthomap.ppm"
		local w, h = render(r, path)
		return true, ("Wrote %dx%d map to %s"):format(w, h, path)
	end,
})

local radius = tonumber(core.settings:get("orthoverse_pregen_radius") or "0") or 0
if radius > 0 then
	core.after(1, function()
		pregen(radius, function()
			if core.settings:get_bool("orthoverse_render_map", false) then
				if radius > MAX_RENDER then
					core.log("action", "[orthoverse_admin] map too big to render in game; " ..
						"use tools/render_map.py on map.sqlite instead")
				else
					local path = core.get_worldpath() .. "/orthomap.ppm"
					render(radius, path)
					core.log("action", "[orthoverse_admin] wrote " .. path)
				end
			end
			if core.settings:get_bool("orthoverse_pregen_exit", false) then
				core.request_shutdown("Pre-generation finished", false, 0)
			end
		end)
	end)
end

-- The admin (the server's "name" setting; OV_ADMIN with Docker) gets every
-- privilege when joining. Luanti only gives the admin some automatically and
-- leaves out fly, fast, noclip, teleport, give and others; they are granted
-- for good here, so the admin can also see and pass them on with /privs and /grant.
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local admin = core.settings:get("name")
	if not admin or admin == "" or name ~= admin then
		return
	end
	local privs = core.get_player_privs(name)
	local added = {}
	for priv, def in pairs(core.registered_privileges) do
		-- not those marked as never for the admin (orthoverse_monsters marks
		-- Mobs Redo's peaceful_player: monsters would ignore the admin, who
		-- tests the adventures)
		if not privs[priv] and def.give_to_admin ~= false then
			privs[priv] = true
			added[#added + 1] = priv
		end
	end
	if #added > 0 then
		core.set_player_privs(name, privs)
		table.sort(added)
		core.log("action", "[orthoverse_admin] admin " .. name .. " granted: " .. table.concat(added, ", "))
	end
end)

------------------------------------------------------------------------------
-- Day and night: two thirds of the time day, one third night (the engine's
-- night, with dusk and dawn, is nearer half). The clock runs slower by day
-- and faster by night, keeping the whole day as long as before:
--   orthoverse_time_speed = 72        -- the average speed (the engine's
--                                        time_speed, 72: a 20 minute day)
--   orthoverse_day_share = 0.667      -- of real time, the share that is day
-- Night here is 18:43 to 05:17 (the dark, and most of dusk and dawn).

local NIGHT_FROM, NIGHT_TO = 0.78, 0.22            -- time of day
local BASE = tonumber(core.settings:get("orthoverse_time_speed")) or 72
local SHARE = math.min(0.95, math.max(0.05, tonumber(core.settings:get("orthoverse_day_share")) or 2 / 3))
local NIGHT_PART = (1 - NIGHT_FROM) + NIGHT_TO     -- of the clock: 0.44
local DAY_PART = 1 - NIGHT_PART
-- Real time (in units of a day at the average speed) spent in each:
-- DAY_PART / day_speed = SHARE, NIGHT_PART / night_speed = 1 - SHARE
local DAY_SPEED = BASE * DAY_PART / SHARE
local NIGHT_SPEED = BASE * NIGHT_PART / (1 - SHARE)

local function is_night(t) return t >= NIGHT_FROM or t < NIGHT_TO end

local current
local function pace()
	local t = core.get_timeofday()
	if not t then return end
	local speed = is_night(t) and NIGHT_SPEED or DAY_SPEED
	if speed ~= current then
		current = speed
		core.settings:set("time_speed", tostring(speed))
	end
end
local since = 0
core.register_globalstep(function(dtime)
	since = since + dtime
	if since < 2 then return end
	since = 0
	pace()
end)
core.after(0, pace)
