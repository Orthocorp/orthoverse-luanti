-- orthoverse_bodies: bodies are solid.
--
-- Players: Luanti leaves them non-physical, so each client lets its player
-- walk through everyone else. Here every player is physical (a property sent
-- to every client), and clients then collide with them as with any solid
-- object: nobody walks through anybody. (The idea is esp32-s3-minetest's,
-- which does the same.) A lying player's box is player_api's low one, so it
-- can be stepped over.
--
-- Being solid does not part two players who are already inside each other,
-- which a teleport does: a party through an adventure's gate (all to the
-- same start), a henge, /adventure go, a respawn. So a few times a second,
-- two players found inside each other are parted: the one who arrived last
-- is moved to the nearest free spot (standing room, not in lava, in sight of
-- where they were, in the same adventure if they were in one), if there is
-- one within a few blocks. Other mods can ask for a free spot first:
-- orthoverse.bodies.free_spot(pos, player).
--
-- Monsters (Mobs Redo) are physical and collide with objects already. The
-- animals (Creatura) are physical but pass through everything; the bigger
-- ones are made solid too (BIG below). The small ones (birds, rats, frogs,
-- fish, cats, chickens, foxes...) still slip by.

orthoverse = orthoverse or {}
orthoverse.bodies = {}

local CHECK_EVERY = 0.25
local HALF = 0.3            -- a player's half width (player_api's box)
local HEIGHT = 1.7
local SEARCH = 4            -- blocks round to look for a free spot
local JUMPED = 3            -- moved this far between checks: arrived (teleported)

local function now() return core.get_us_time() / 1e6 end

local function is_attached(player)
	return player:get_attach() ~= nil
end

------------------------------------------------------------------------------
-- Players are solid

core.register_on_joinplayer(function(player)
	player:set_properties({physical = true, collide_with_objects = true})
end)

------------------------------------------------------------------------------
-- A free spot

local function def_at(p)
	return core.registered_nodes[core.get_node(p).name]
end
local function solid(p)
	local d = def_at(p)
	return not d or d.walkable ~= false
end
local function harmful(p)
	local d = def_at(p)
	return d and ((d.damage_per_second or 0) > 0 or d.drowning and d.drowning > 0)
end

-- Two players' feet positions: are their bodies inside each other (well
-- inside: bodies pressed together, as walking into someone leaves them, are
-- not)
local DEEP = 0.15
local function overlap(a, b)
	return math.abs(a.x - b.x) < 2 * HALF - DEEP and math.abs(a.z - b.z) < 2 * HALF - DEEP
		and math.abs(a.y - b.y) < HEIGHT - DEEP
end

-- Whether a player standing at `feet` would be inside another player
-- (`except`: that player)
local function crowded(feet, except)
	for _, other in ipairs(core.get_connected_players()) do
		if other ~= except and not is_attached(other) and overlap(feet, other:get_pos()) then return true end
	end
	return false
end
orthoverse.bodies.crowded = crowded

-- Where to put `player` who is being sent to `pos`: there, or if somebody is
-- standing there, the nearest free spot (or there anyway, if none)
function orthoverse.bodies.place(player, pos)
	if crowded(pos, player) then return orthoverse.bodies.free_spot(pos, player) or pos end
	return pos
end

-- The nearest place to stand round `pos` (a player's feet position) where
-- nobody else is: room for a body, solid ground that does not burn, in sight
-- of `pos`, and in the same adventure area as `pos` (or outside any, as it
-- is). `player`: the one to place (not counted as in the way). nil if none.
function orthoverse.bodies.free_spot(pos, player)
	local ad = orthoverse.adventure
	local key0 = ad and ad.at and ad.at(pos) or nil
	local base = vector.round(pos)
	local eye = vector.offset(pos, 0, 1.4, 0)
	local cands = {}
	for dz = -SEARCH, SEARCH do for dx = -SEARCH, SEARCH do
		if dx ~= 0 or dz ~= 0 then
			cands[#cands + 1] = {dx = dx, dz = dz, d = dx * dx + dz * dz}
		end
	end end
	table.sort(cands, function(a, b) return a.d < b.d end)
	for _, c in ipairs(cands) do
		for _, dy in ipairs({0, 1, -1}) do
			local n = vector.offset(base, c.dx, dy, c.dz)        -- the node the feet are in
			local feet = vector.new(n.x, n.y - 0.5, n.z)
			if solid(vector.offset(n, 0, -1, 0)) and not solid(n) and not solid(vector.offset(n, 0, 1, 0))
					and not harmful(n) and not harmful(vector.offset(n, 0, 1, 0))
					and not crowded(feet, player)
					and (not ad or (ad.at and ad.at(feet)) == key0)
					and core.line_of_sight(eye, vector.offset(feet, 0, 1.4, 0)) then
				return feet
			end
		end
	end
end

------------------------------------------------------------------------------
-- Parting players who are inside each other

local last = {}      -- name -> position at the last check
local arrived = {}   -- name -> when they last arrived somewhere (a jump)

core.register_on_joinplayer(function(player) arrived[player:get_player_name()] = now() end)
core.register_on_respawnplayer(function(player) arrived[player:get_player_name()] = now() end)
core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	last[name], arrived[name] = nil, nil
end)

local since = 0
core.register_globalstep(function(dtime)
	since = since + dtime
	if since < CHECK_EVERY then return end
	since = 0
	local t = now()
	local players = core.get_connected_players()
	for _, p in ipairs(players) do
		local name = p:get_player_name()
		local pos = p:get_pos()
		if last[name] and vector.distance(last[name], pos) > JUMPED then arrived[name] = t end
		last[name] = pos
	end
	local moved = {}
	for i = 1, #players do
		local a = players[i]
		local an = a:get_player_name()
		if not moved[an] and not is_attached(a) and a:get_hp() > 0 then
			for j = i + 1, #players do
				local b = players[j]
				local bn = b:get_player_name()
				if not moved[bn] and not is_attached(b) and b:get_hp() > 0 and overlap(a:get_pos(), b:get_pos()) then
					-- the newcomer moves
					local mover = (arrived[bn] or 0) >= (arrived[an] or 0) and b or a
					local to = orthoverse.bodies.free_spot(mover:get_pos(), mover)
					if to then
						mover:set_pos(to)
						last[mover:get_player_name()] = to
						moved[mover:get_player_name()] = true
					end
					break
				end
			end
		end
	end
end)

------------------------------------------------------------------------------
-- The bigger animals are solid too

local BIG = {"animalia:cow", "animalia:horse", "animalia:pig", "animalia:sheep", "animalia:reindeer",
	"animalia:grizzly_bear", "animalia:wolf"}

core.register_on_mods_loaded(function()
	for _, name in ipairs(BIG) do
		local def = core.registered_entities[name]
		if def then
			def.collide_with_objects = true
			if def.initial_properties then def.initial_properties.collide_with_objects = true end
		end
	end
end)
