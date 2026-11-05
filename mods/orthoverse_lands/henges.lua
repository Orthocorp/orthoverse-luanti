-- Henge gateways, shared by the generator (which draws them) and the teleporter
-- (which uses them). Loaded with dofile, like coords.lua.
--
-- The nine henges sit on a 3 x 3 grid of lands at -30, 0 and 30 (old land
-- coordinates: z grows southwards). Each stone circle has four gateways, the
-- openings between the uprights at north, south, east and west. Going through
-- one takes you to the centre of the next henge in that direction. At the edge
-- of the grid it wraps round, as the old Orthoverse did: north from the
-- northern row comes out at the southern row.

local H = {}

H.SPACING = 30        -- lands between neighbouring henges
H.EXTENT = 30         -- henges at -30, 0, 30 on both axes

-- Each gateway, in a henge land's local coordinates (u eastwards, v southwards,
-- 0..95; the circle is centred on 47.5, 47.5). The opening is 4 nodes wide and
-- 2 deep, between two uprights, under the lintel ring, from ground level + 1 to
-- ground level + 4. dx, dz: the direction of travel, in old land coordinates.
H.GATES = {
	north = {u0 = 46, u1 = 49, v0 = 33, v1 = 34, dx = 0, dz = -1},
	south = {u0 = 46, u1 = 49, v0 = 61, v1 = 62, dx = 0, dz = 1},
	west  = {u0 = 33, u1 = 34, v0 = 46, v1 = 49, dx = -1, dz = 0},
	east  = {u0 = 61, u1 = 62, v0 = 46, v1 = 49, dx = 1, dz = 0},
}
H.GATE_HEIGHT = 4

-- The gateway at local u, v (node positions), or nil
function H.gate_at(u, v)
	for name, g in pairs(H.GATES) do
		if u >= g.u0 and u <= g.u1 and v >= g.v0 and v <= g.v1 then
			return name, g
		end
	end
end

-- The henge you reach going through gateway `g` of the henge at lx, lz
function H.destination(lx, lz, g)
	local function wrap(n)
		if n > H.EXTENT then return -H.EXTENT end
		if n < -H.EXTENT then return H.EXTENT end
		return n
	end
	return wrap(lx + g.dx * H.SPACING), wrap(lz + g.dz * H.SPACING)
end

return H
