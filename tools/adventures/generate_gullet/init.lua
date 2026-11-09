-- Generates adventures/gullet.we and .json, and checks that a player can walk
-- from the start to every spawner, chest and the finish (and that the
-- temple can be reached only through the orc hall or the secret way). See
-- tools/adventures/README.md.
local g = dofile(core.get_game_info().path .. "/tools/adventures/gullet.lua")
local out = {}
local function flush() core.safe_file_write(core.get_worldpath() .. "/result.txt", table.concat(out, "\n")) end
local function say(s) out[#out + 1] = s; core.log("action", "[gullet] " .. s); flush() end

local function forceload(O)
	local size = g.info.size
	for x = 0, size.x + 15, 16 do for y = 0, size.y + 15, 16 do for z = 0, size.z + 15, 16 do
		core.forceload_block(vector.add(O, {x = math.min(x, size.x - 1), y = math.min(y, size.y - 1),
			z = math.min(z, size.z - 1)}), true)
	end end end
end

-- Where a player can stand: a walkable node below, room for a body above
local function walkable(p)
	local d = core.registered_nodes[core.get_node(p).name]
	return d and d.walkable ~= false
end
local function standable(p)
	return walkable({x = p.x, y = p.y - 1, z = p.z}) and not walkable(p) and not walkable({x = p.x, y = p.y + 1, z = p.z})
end

-- Every place a player can walk to from `from` (absolute), jumping one block
-- up or dropping up to three; `blocked` (relative boxes) can be walled off
local function reach(O, from, blocked)
	local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
	local function is_blocked(p)
		for _, b in ipairs(blocked or {}) do
			local r = vector.subtract(p, O)
			if r.x >= b[1].x and r.x <= b[2].x and r.y >= b[1].y and r.y <= b[2].y and r.z >= b[1].z and r.z <= b[2].z then return true end
		end
	end
	local seen, queue, head = {[key(from)] = true}, {from}, 1
	local lo, hi = vector.add(O, {x = 0, y = 0, z = 0}), vector.add(O, vector.subtract(g.info.size, 1))
	while head <= #queue do
		local p = queue[head]; head = head + 1
		for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
			for dy = 1, -3, -1 do
				local q = {x = p.x + d[1], y = p.y + dy, z = p.z + d[2]}
				if q.x >= lo.x and q.x <= hi.x and q.z >= lo.z and q.z <= hi.z and q.y > lo.y and q.y < hi.y then
					-- going up needs head room where we stand; going down, room to step over
					local ok = standable(q) and not is_blocked(q)
					if ok and dy == 1 then ok = not walkable({x = p.x, y = p.y + 2, z = p.z}) end
					if ok and dy < 0 then ok = not walkable({x = q.x, y = p.y, z = q.z}) and not walkable({x = q.x, y = p.y + 1, z = q.z}) end
					if ok and not seen[key(q)] then
						seen[key(q)] = true
						queue[#queue + 1] = q
						break
					end
				end
			end
		end
	end
	return seen, key
end

local function check(O, label)
	local start = vector.add(O, vector.round({x = g.info.start.x - 0.5, y = g.info.start.y, z = g.info.start.z - 0.5}))
	say(label .. ": start standable " .. tostring(standable(start)))
	local seen, key = reach(O, start)
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	local function near(p, r)
		for dx = -r, r do for dz = -r, r do for dy = -1, 2 do
			if seen[key(vector.add(p, {x = dx, y = dy, z = dz}))] then return true end
		end end end
		return false
	end
	local bad = {}
	for _, s in ipairs(g.spawners) do
		if not near(vector.add(O, {x = s.x, y = s.y + 1, z = s.z}), 2) then bad[#bad + 1] = "spawner " .. s.kind end
	end
	for _, c in ipairs(g.chests) do
		if not near(vector.add(O, c), 1) then bad[#bad + 1] = "chest " .. c.kind .. " at " .. core.pos_to_string(c) end
	end
	local fin = vector.add(O, g.finish)
	say(("%s: %d places reachable; finish reachable %s; unreachable: %s"):format(label, n, tostring(near(fin, 1)),
		#bad > 0 and table.concat(bad, ", ") or "none"))
	-- with the orc hall's back passage and the secret way walled off, the
	-- temple must be out of reach
	local seen2 = reach(O, start, {{{x = 43, y = 0, z = 61}, {x = 44, y = 30, z = 63}}, {{x = 10, y = 0, z = 55}, {x = 11, y = 30, z = 57}}})
	local key2 = function(p) return p.x .. "," .. p.y .. "," .. p.z end
	local inside = false
	for dx = -2, 2 do for dz = -3, 0 do
		if seen2[key2(vector.add(fin, {x = dx, y = -1, z = dz - 1}))] or seen2[key2(vector.add(fin, {x = dx, y = 0, z = dz - 1}))] then inside = true end
	end end
	say(label .. ": temple reachable without the two ways in: " .. tostring(inside))
	-- Thornwatch has a way in from outside: from open ground west of the fort
	-- (the side the land is on), the gate can be reached
	local outside = vector.add(O, {x = 10, y = g.gate.y, z = 5})
	local seen3, key3 = reach(O, outside)
	local gate_ok = false
	for dx = -1, 1 do for dz = -1, 1 do
		if seen3[key3(vector.add(O, {x = g.gate.x + dx, y = g.gate.y, z = g.gate.z + dz}))] then gate_ok = true end
	end end
	say(label .. ": outside standable " .. tostring(standable(outside)) .. "; gate reachable from outside: " .. tostring(gate_ok))
	-- and from the land, nobody gets up onto the rim's barrier (to jump into
	-- the gorge)
	local over = false
	for _, r in ipairs(g.rim or {}) do
		for y = g.surface, g.surface + 3 do
			if seen3[key3(vector.add(O, {x = r[1], y = y, z = r[2]}))] then over = true end
		end
	end
	say(label .. ": the rim can be climbed from the land: " .. tostring(over))
	-- and the portcullis is down: from inside, the fort cannot be reached
	local back = false
	for dx = -1, 1 do for dz = -1, 1 do
		if seen[key(vector.add(O, {x = g.gate.x + dx, y = g.gate.y, z = g.gate.z + dz}))] then back = true end
	end end
	say(label .. ": fort reachable from inside: " .. tostring(back))
	-- nobody climbs out of the gorge onto the land
	local out = false
	for k in pairs(seen) do
		local y = tonumber(k:match("^[^,]+,([^,]+),"))
		if y and y - O.y >= g.surface then out = true break end
	end
	say(label .. ": can climb out of the gorge: " .. tostring(out))
	-- every sign hangs on something solid
	local DIR = {["+x"] = {x = 1, y = 0, z = 0}, ["-x"] = {x = -1, y = 0, z = 0}, ["+z"] = {x = 0, y = 0, z = 1}, ["-z"] = {x = 0, y = 0, z = -1}}
	local loose = {}
	for _, sg in ipairs(g.signs) do
		local on = vector.add(vector.add(O, sg), DIR[sg.dir])
		if not walkable(on) then loose[#loose + 1] = sg.text .. " at " .. core.pos_to_string(sg) end
	end
	say(label .. ": signs not on a wall: " .. (#loose > 0 and table.concat(loose, "; ") or "none"))
end

core.after(2, function()
	local A = vector.new(300, 200, 500)
	local size = g.info.size
	core.emerge_area(A, vector.add(A, size), function(_, _, left)
		if left > 0 then return end
		forceload(A)
		local missing = g.build(A)
		local m = {}
		for k in pairs(missing) do m[#m + 1] = k end
		say("built; missing nodes: " .. (#m > 0 and table.concat(m, ", ") or "none"))
		core.safe_file_write(core.get_worldpath() .. "/plan.txt", g.plan())
		core.after(3, function()
			local data, n = worldedit.serialize(A, vector.add(A, vector.subtract(size, 1)))
			core.safe_file_write(core.get_worldpath() .. "/gullet.we", data)
			local info = table.copy(g.info)
			core.safe_file_write(core.get_worldpath() .. "/gullet.json", core.write_json(info))
			say(("saved %d nodes, %d bytes"):format(n, #data))
			check(A, "built")
			flush()
		end)
	end)
end)

orthoverse = orthoverse or {}
orthoverse.gullet_test = {g = g, reach = reach, check = check, forceload = forceload, say = say}
