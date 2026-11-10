-- Generates a ready-made adventure, adventures/<name>.we and .json, from
-- tools/adventures/<name>.lua (setting orthoverse_generate_adventure: gullet,
-- fallen_star), and checks it: that a player can walk from the start to every
-- spawner, chest and the finish, that its gated places can be reached only
-- through their ways in, that nobody climbs out or in, and that every sign
-- hangs on a wall (or, for one whose builder has its own checks, g.check:
-- Tir Na Nog, a climb, those). See tools/adventures/README.md.
local NAME = core.settings:get("orthoverse_generate_adventure") or "gullet"
assert(NAME:match("^[%w_]+$"), "orthoverse_generate_adventure: a plain name")
local g = dofile(core.get_game_info().path .. "/tools/adventures/" .. NAME .. ".lua")
local out = {}
local function flush() core.safe_file_write(core.get_worldpath() .. "/result.txt", table.concat(out, "\n")) end
local function say(s) out[#out + 1] = s; core.log("action", "[" .. NAME .. "] " .. s); flush() end

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
-- (not in lava, or anything else that burns)
local function harmful(p)
	local d = core.registered_nodes[core.get_node(p).name]
	return d and (d.damage_per_second or 0) > 0
end
local function standable(p)
	return walkable({x = p.x, y = p.y - 1, z = p.z}) and not walkable(p) and not walkable({x = p.x, y = p.y + 1, z = p.z})
		and not harmful(p) and not harmful({x = p.x, y = p.y + 1, z = p.z})
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
		if not s.aloft and not near(vector.add(O, {x = s.x, y = s.y + 1, z = s.z}), 2) then bad[#bad + 1] = "spawner " .. s.kind end
	end
	for _, c in ipairs(g.chests) do
		if not near(vector.add(O, c), 1) then bad[#bad + 1] = "chest " .. c.kind .. " at " .. core.pos_to_string(c) end
	end
	local fin = vector.add(O, g.finish)
	say(("%s: %d places reachable; finish reachable %s; unreachable: %s"):format(label, n, tostring(near(fin, 1)),
		#bad > 0 and table.concat(bad, ", ") or "none"))
	-- with their ways in walled off, gated places must be out of reach (and
	-- reachable with them open)
	for _, gt in ipairs(g.gated or {}) do
		local target = vector.add(O, gt.target)
		local seen2, key2 = reach(O, start, gt.blocked)
		say(("%s: %s (with them: %s)"):format(label, gt.label, tostring(seen[key(target)] == true)) ..
			": " .. tostring(seen2[key2(target)] == true))
	end
	-- the entrance has a way in from outside: from open ground, the gate can
	-- be reached
	local outside = vector.add(O, g.outside or {x = 2, y = g.gate.y, z = 2})
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
	-- and nobody on the land gets into the dungeon without the gate
	local into = false
	local c1, c2 = g.info.corner1, g.info.corner2
	for k3 in pairs(seen3) do
		local x, y, z = k3:match("^([^,]+),([^,]+),([^,]+)$")
		x, y, z = tonumber(x) - O.x, tonumber(y) - O.y, tonumber(z) - O.z
		if x >= math.min(c1.x, c2.x) and x <= math.max(c1.x, c2.x) and z >= math.min(c1.z, c2.z) and z <= math.max(c1.z, c2.z)
				and y >= math.min(c1.y, c2.y) and y <= math.max(c1.y, c2.y) then into = ("%d,%d,%d"):format(x, y, z) break end
	end
	say(label .. ": the dungeon reachable from the land: " .. (into and ("true (at " .. into .. ")") or "false"))
	-- where the ground is open to the sky (a player could fall in, unless a
	-- barrier keeps them off)
	local holes = 0
	local gy = g.info.ground
	for x = 0, g.info.size.x - 1 do for z = 0, g.info.size.z - 1 do
		local open = true
		for y = gy, math.min(gy + 6, g.info.size.y - 1) do
			if walkable(vector.add(O, {x = x, y = y, z = z})) then open = false break end
		end
		if open and not walkable(vector.add(O, {x = x, y = gy - 1, z = z})) then holes = holes + 1 end
	end end
	say(label .. ": open holes in the ground: " .. holes)
	-- and the portcullis is down: from inside, the fort cannot be reached
	local back = false
	for dx = -1, 1 do for dz = -1, 1 do
		if seen[key(vector.add(O, {x = g.gate.x + dx, y = g.gate.y, z = g.gate.z + dz}))] then back = true end
	end end
	say(label .. ": entrance reachable from inside: " .. tostring(back))
	-- nobody gets out of the dungeon's area (onto the land, or above it)
	local out = false
	local a1, a2 = g.info.corner1, g.info.corner2
	for k in pairs(seen) do
		local x, y, z = k:match("^([^,]+),([^,]+),([^,]+)$")
		x, y, z = tonumber(x) - O.x, tonumber(y) - O.y, tonumber(z) - O.z
		if x < math.min(a1.x, a2.x) or x > math.max(a1.x, a2.x) or z < math.min(a1.z, a2.z) or z > math.max(a1.z, a2.z)
				or y > math.max(a1.y, a2.y) then out = true break end
	end
	say(label .. ": can climb out: " .. tostring(out))
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
			local data, n
			if g.compact then
				-- the compact form (.ovt), for a big one: see orthoverse_adventure
				local tpl
				tpl, n = orthoverse.adventure.capture(A, vector.add(A, vector.subtract(size, 1)))
				data = core.compress(core.serialize(tpl), "zstd")
				core.safe_file_write(core.get_worldpath() .. "/" .. NAME .. ".ovt", data)
			else
				data, n = worldedit.serialize(A, vector.add(A, vector.subtract(size, 1)))
				core.safe_file_write(core.get_worldpath() .. "/" .. NAME .. ".we", data)
			end
			local info = table.copy(g.info)
			core.safe_file_write(core.get_worldpath() .. "/" .. NAME .. ".json", core.write_json(info))
			say(("saved %d nodes, %d bytes"):format(n, #data))
			-- For the checks, doors open (the players carry their cards), and
			-- what a run changes changed (The Wyrm Below's bridge risen)
			for _, nm in ipairs(g.open_for_checks or {}) do
				for _, p in ipairs(core.find_nodes_in_area(A, vector.add(A, vector.subtract(size, 1)), {nm})) do
					core.remove_node(p)
				end
			end
			for from, to in pairs(g.swap_for_checks or {}) do
				for _, p in ipairs(core.find_nodes_in_area(A, vector.add(A, vector.subtract(size, 1)), {from})) do
					core.set_node(p, {name = to})
				end
			end
			if g.check then
				-- its own checks (Tir Na Nog: jumps, not walking)
				g.check(A, {say = say, walkable = walkable, standable = standable})
			else
				check(A, "built")
			end
			flush()
		end)
	end)
end)

orthoverse = orthoverse or {}
orthoverse.gullet_test = {g = g, reach = reach, check = check, forceload = forceload, say = say}
