-- Orthoverse coordinate helpers, shared by the main and mapgen environments.
--
-- Old Orthoverse land keys are "x:z" with z growing southwards (Minecraft style).
-- Luanti's z grows northwards, so the land row is mirrored. Lands are 96 nodes
-- square and centred on the origin: land 0:0 covers x,z in -48..47, so that each
-- land lines up with one mapchunk (chunksize 6).

local C = {}

C.LAND = 96
C.TILE = 16
C.HALF = 48
C.MAP_RADIUS = 56   -- playable lands -56..56
C.RIM = 57          -- plains ring with mountains on the outer edge
C.WALL = 58         -- world edge

local floor = math.floor

-- Luanti node x,z -> old land key coordinates (lx, lz)
function C.land_of(x, z)
	-- 0 - n rather than -n: Lua would print -0 as "-0" and break the land keys
	return floor((x + C.HALF) / C.LAND), 0 - floor((z + C.HALF) / C.LAND)
end

function C.key(lx, lz)
	return lx .. ":" .. lz
end

-- Position inside the land, in old (Minecraft-style) orientation:
-- u grows eastwards 0..95, v grows southwards 0..95.
function C.local_uv(x, z)
	local u = (x + C.HALF) % C.LAND
	local v = C.LAND - 1 - ((z + C.HALF) % C.LAND)
	return u, v
end

-- Luanti node x,z of the north-west corner of a land, given old land coords.
function C.land_origin(lx, lz)
	local x0 = lx * C.LAND - C.HALF
	local zn = -lz * C.LAND - C.HALF + C.LAND - 1 -- northernmost z (v = 0)
	return x0, zn
end

-- Old-orientation local u,v back to Luanti x,z.
function C.world_xz(lx, lz, u, v)
	local x0, zn = C.land_origin(lx, lz)
	return x0 + u, zn - v
end

-- Tile index used by the token string: posY * 6 + posX (0..35).
function C.tile_index(u, v)
	return floor(v / C.TILE) * 6 + floor(u / C.TILE)
end

return C
