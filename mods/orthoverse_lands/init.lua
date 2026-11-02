-- orthoverse_lands: loads the frozen land table and shares it with the mapgen threads.

local modpath = core.get_modpath(core.get_current_modname())

orthoverse = rawget(_G, "orthoverse") or {}
local C = dofile(modpath .. "/coords.lua")
orthoverse.coords = C

local f = assert(io.open(modpath .. "/data/lands.json", "r"))
local raw = f:read("*a")
f:close()
local data = assert(core.parse_json(raw), "orthoverse_lands: lands.json did not parse")
assert(data.format == 1, "orthoverse_lands: unsupported lands.json format")

orthoverse.lands = data.lands
orthoverse.henges = data.henges

local count = 0
for _ in pairs(data.lands) do count = count + 1 end
core.log("action", ("[orthoverse_lands] %d lands, henges loaded"):format(count))

-- The mapgen environment cannot see this one; hand the data over via IPC.
core.ipc_set("orthoverse:lands", { lands = data.lands, henges = data.henges })
core.ipc_set("orthoverse:lands_path", modpath)

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
