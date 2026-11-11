-- orthoverse_weather: rain and snow (after paramat's snowdrift).
--
-- Whether it rains is a slow noise over the map and over time, so showers
-- drift across the world and players near each other share them. What falls
-- depends on the ground under the player, not on Minetest Game's climate
-- (the Orthoverse has none: each land's tiles decide what it looks like):
--
--   desert dunes, badlands       nothing falls (the sky stays clear)
--   barren hills and mountains   rain, but only in the heaviest weather
--   evergreen forest             snow
--   mountains, high up           snow
--   anywhere else, and the sea   rain
--
-- Nothing falls inside an adventure (each has weather of its own design),
-- indoors or underground (rain and snow fall only where the sky is open
-- above the player), or under water. In wet weather the clouds close in and
-- grey (Minetest Game's weather mod moves the clouds; this changes what it
-- asks for), and rain sounds while the player is out in it.
--
-- Each player gets one particle spawner a second, not a message per drop.
--
-- The admin (server privilege) can set the weather for testing:
--   /weather rain | snow | clear | auto

orthoverse = orthoverse or {}
orthoverse.weather = {}

local C = orthoverse.coords
local G = tonumber(core.get_mapgen_setting("mgflat_ground_level")) or 8

local STEP = 1                -- seconds between looks at each player
local RADIUS = 14             -- how far round the player it falls
local RAIN = tonumber(core.settings:get("orthoverse_weather_rain")) or 220   -- drops a second
local SNOW = tonumber(core.settings:get("orthoverse_weather_snow")) or 70    -- flakes a second
local WET = 0.35              -- noise over this: rain or snow (about a fifth of the time)
local WET_BARREN = 0.6        -- on barren land, only over this
local HIGH = G + 10           -- mountain snow line
local RAIN_GAIN = 0.25

-- Weather noise: over the map (x, z) and time; one unit of time a second
local np = {
	offset = 0, scale = 1, spread = {x = 600, y = 500, z = 600},
	seed = 7731, octaves = 2, persist = 0.5, lacunarity = 2.0,
}
local noise
local forced = nil   -- "rain", "snow", "clear" from /weather, or nil

-- What the ground is under `pos`: the tile's feature letter, or "sea"
local function ground(pos)
	local land, key = orthoverse.land_at(pos)
	local h = orthoverse.henges and orthoverse.henges[key]
	if h then return "3" end   -- henges: plains
	if not (land and land.token) then return "sea" end
	local lx, lz = C.land_of(pos.x, pos.z)
	local u, v = C.local_uv(pos.x, pos.z)
	local i = C.tile_index(u, v)
	return land.token:sub(3 + i, 3 + i)
end

-- "rain", "snow" or nil at `pos` now
function orthoverse.weather.at(pos)
	local f = ground(pos)
	if forced then
		if forced == "clear" then return nil end
		return forced
	end
	if f == "b" or f == "d" then return nil end
	noise = noise or core.get_perlin(np)
	local n = noise:get_3d({x = pos.x, y = core.get_gametime(), z = pos.z})
	local wet = (f == "8" or f == "9") and WET_BARREN or WET
	if n <= wet then return nil end
	if f == "7" or ((f == "1" or f == "9") and pos.y > HIGH) then return "snow" end
	return "rain"
end

local state = {}    -- name -> "rain" | "snow" | nil (what falls on them now)
local sounds = {}   -- name -> the rain sound's handle

local function stop_sound(name)
	if sounds[name] then core.sound_stop(sounds[name]) end
	sounds[name] = nil
end

-- Clouds and light in wet weather (over Minetest Game's own)
local base_get = weather.get
weather.get = function(player)
	local params = base_get(player)
	local s = state[player:get_player_name()]
	if s then
		params.clouds = params.clouds or {}
		params.clouds.density = math.max(params.clouds.density or 0, s == "snow" and 0.75 or 0.85)
		params.clouds.thickness = math.max(params.clouds.thickness or 0, 24)
		params.clouds.color = s == "snow" and "#d8dce2e5" or "#a4abb4e5"
		params.lighting = params.lighting or {}
		params.lighting.shadows = {intensity = 0.1}
	end
	return params
end

local function refresh_sky(player)
	local params = weather.get(player)
	if params.clouds then player:set_clouds(params.clouds) end
	if params.lighting then player:set_lighting(params.lighting) end
end

local function fall(player, kind, head)
	local name = player:get_player_name()
	local box = {min = vector.offset(head, -RADIUS, 8, -RADIUS), max = vector.offset(head, RADIUS, 12, RADIUS)}
	if kind == "rain" then
		core.add_particlespawner({
			amount = RAIN * STEP, time = STEP, playername = name,
			pos = box,
			vel = {min = {x = 0, y = -13, z = 0}, max = {x = 0, y = -11, z = 0}},
			exptime = 1.4, size = 2.8, vertical = true,
			collisiondetection = true, collision_removal = true,
			texture = "orthoverse_weather_raindrop.png",
		})
	else
		for i = 1, 4 do   -- four kinds of flake each second
			core.add_particlespawner({
				amount = math.ceil(SNOW * STEP / 4), time = STEP, playername = name,
				pos = box,
				vel = {min = {x = -0.4, y = -2.2, z = -0.4}, max = {x = 0.4, y = -1.6, z = 0.4}},
				exptime = 8, size = {min = 1.4, max = 2.2},
				collisiondetection = true, collision_removal = true,
				texture = "orthoverse_weather_snowflake" .. math.random(1, 12) .. ".png",
			})
		end
	end
end

local function in_adventure(pos)
	local ad = orthoverse.adventure
	return ad and ad.at and ad.at(pos) ~= nil
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < STEP then return end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		local head = vector.round(vector.offset(pos, 0, 2, 0))
		local kind = not in_adventure(pos) and orthoverse.weather.at(pos) or nil
		if kind ~= state[name] then
			state[name] = kind
			refresh_sky(player)
		end
		-- Out under the open sky (full daylight reaches above the head) and
		-- not under water
		local node = core.get_node_or_nil(head)
		local def = node and core.registered_nodes[node.name]
		local open = kind and (core.get_node_light(vector.offset(head, 0, 1, 0), 0.5) or 0) >= 15
			and not (def and def.liquidtype and def.liquidtype ~= "none")
		if open then fall(player, kind, head) end
		if open and kind == "rain" then
			if not sounds[name] then
				sounds[name] = core.sound_play("orthoverse_weather_rain",
					{to_player = name, gain = RAIN_GAIN, loop = true, fade = 0.5})
			end
		else
			stop_sound(name)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	stop_sound(name)
	state[name] = nil
end)

core.register_chatcommand("weather", {
	params = "rain | snow | clear | auto",
	description = "Set the weather everywhere, for testing (auto: as the noise says)",
	privs = {server = true},
	func = function(_, param)
		param = param:lower():match("^%s*(%a*)")
		if param == "auto" then forced = nil
		elseif param == "rain" or param == "snow" or param == "clear" then forced = param
		else return false, "Say rain, snow, clear or auto." end
		return true, "Weather: " .. param .. "."
	end,
})
