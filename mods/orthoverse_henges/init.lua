-- orthoverse_henges: the henges' gateways take you to the next henge.
--
-- Each henge's stone circle has four gateways, at north, south, east and west
-- (geometry in orthoverse_lands/henges.lua). Walking into one takes you to the
-- centre of the next henge in that direction, facing onwards; at the edge of the
-- 3 x 3 grid it wraps round to the far side, as the old Orthoverse did.

local C = orthoverse.coords
local HG = orthoverse.henge_gates
local HENGES = orthoverse.henges
local G = tonumber(core.get_mapgen_setting("mgflat_ground_level")) or 8

local floor, min, max, pi = math.floor, math.min, math.max, math.pi

-- Where you face on arrival: Luanti yaw 0 looks north (+z), pi/2 west
local YAW = {north = 0, west = pi / 2, south = pi, east = 3 * pi / 2}
local ARRIVE_OFFSET = 4      -- nodes from the centre, in the direction of travel
local COOLDOWN_US = 2000000  -- no second jump within 2 s of arriving
local CHECK_EVERY = 0.2      -- seconds between gateway checks

local function henge_coords(key)
	local a, b = key:match("^(%-?%d+):(%-?%d+)$")
	return tonumber(a), tonumber(b)
end

-- World box of one gateway of the henge at lx, lz
local function gate_box(lx, lz, g)
	local xa, za = C.world_xz(lx, lz, g.u0, g.v0)
	local xb, zb = C.world_xz(lx, lz, g.u1, g.v1)
	return vector.new(min(xa, xb), G + 1, min(za, zb)),
		vector.new(max(xa, xb), G + HG.GATE_HEIGHT, max(za, zb))
end

------------------------------------------------------------------------------
-- Gateways for henges generated before gateways existed: fill each opening
-- with the veil wherever it is still empty air. Nothing happens to land that
-- has not been generated yet (the generator draws gateways itself) or to
-- anything someone has put in an opening.

local function add_missing_gateways()
	local c_air = core.get_content_id("air")
	local c_veil = core.get_content_id("orthoverse_nodes:henge_veil")
	local added = 0
	for key in pairs(HENGES) do
		local lx, lz = henge_coords(key)
		for _, g in pairs(HG.GATES) do
			local minp, maxp = gate_box(lx, lz, g)
			local vm = core.get_voxel_manip()
			local e1, e2 = vm:read_from_map(minp, maxp)
			local area = VoxelArea(e1, e2)
			local data = vm:get_data()
			local changed = false
			for z = minp.z, maxp.z do
				for y = minp.y, maxp.y do
					for x = minp.x, maxp.x do
						local i = area:index(x, y, z)
						if data[i] == c_air then
							data[i] = c_veil
							changed = true
							added = added + 1
						end
					end
				end
			end
			if changed then
				vm:set_data(data)
				vm:write_to_map(true)
			end
		end
	end
	if added > 0 then
		core.log("action", "[orthoverse_henges] added " .. added .. " gateway nodes to existing henges")
	end
end

core.after(1, add_missing_gateways)

------------------------------------------------------------------------------
-- Going through

local arrived = {}  -- player name -> time before which gateways are ignored

local function go_through(player, lx, lz, gate_name, g)
	local tx, tz = HG.destination(lx, lz, g)
	local target = HENGES[C.key(tx, tz)]
	if not target then
		return
	end
	-- The henge's centre is 47.5, 47.5 in land coordinates; arrive a little
	-- beyond it, towards the gateway on the far side, facing onwards
	local x, z = C.world_xz(tx, tz, 47.5 + g.dx * ARRIVE_OFFSET, 47.5 + g.dz * ARRIVE_OFFSET)
	local dest = vector.new(x, G + 1, z)
	-- Load the arrival area first, so the player lands on solid ground
	core.load_area(vector.offset(dest, -16, -4, -16), vector.offset(dest, 16, 8, 16))
	player:set_pos(dest)
	player:set_look_horizontal(YAW[gate_name])
	local name = player:get_player_name()
	arrived[name] = core.get_us_time() + COOLDOWN_US
	core.chat_send_player(name, "You pass through the henge to " .. target.name .. ".")
	core.log("action", ("[orthoverse_henges] %s went %s from %s to %s"):format(
		name, gate_name, C.key(lx, lz), C.key(tx, tz)))
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < CHECK_EVERY then
		return
	end
	timer = 0
	local now = core.get_us_time()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if not arrived[name] or now >= arrived[name] then
			local pos = player:get_pos()
			local nx, ny, nz = floor(pos.x + 0.5), floor(pos.y + 0.5), floor(pos.z + 0.5)
			if ny >= G + 1 and ny <= G + HG.GATE_HEIGHT then
				local lx, lz = C.land_of(nx, nz)
				if HENGES[C.key(lx, lz)] then
					local u, v = C.local_uv(nx, nz)
					local gate_name, g = HG.gate_at(u, v)
					if g then
						go_through(player, lx, lz, gate_name, g)
					end
				end
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	arrived[player:get_player_name()] = nil
end)
