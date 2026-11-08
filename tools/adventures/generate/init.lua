-- Generates adventures/three-bells.we and .json, and checks every puzzle:
-- first in the copy it builds, then in a copy placed on a land the way
-- /adventure place does it. See tools/adventures/README.md.
local tb = dofile(core.get_game_info().path .. "/tools/adventures/three_bells.lua")
local out = {}
local function flush() core.safe_file_write(core.get_worldpath() .. "/result.txt", table.concat(out, "\n")) end
local function say(s) out[#out + 1] = s; core.log("action", "[tbtest] " .. s); flush() end

local function seq(steps)
	local i = 0
	local function nxt()
		i = i + 1
		local s = steps[i]
		if not s then return end
		local wait = s(nxt)
		if type(wait) == "number" then core.after(wait, nxt) end
	end
	nxt()
end

local function forceload(O)
	for x = 0, 59, 16 do for y = 0, 46, 16 do for z = 0, 41, 16 do
		core.forceload_block(vector.add(O, {x = x, y = y, z = z}), true)
	end end end
	for _, c in ipairs({{59, 46, 41}, {59, 0, 41}, {0, 46, 41}, {59, 46, 0}}) do core.forceload_block(vector.add(O, {x = c[1], y = c[2], z = c[3]}), true) end
end
local function door_open(O, d)
	local p = vector.add(O, tb.doors[d])
	local door = doors.get(p)
	if not door then return "NO DOOR at " .. core.pos_to_string(p) .. " (" .. core.get_node(p).name .. ")" end
	return door:state() and "open" or "closed"
end
local function all_doors(O)
	local r = {}
	for _, d in ipairs({"grate", "library", "levers", "iron", "bronze", "silver"}) do r[#r + 1] = d .. "=" .. door_open(O, d) end
	return table.concat(r, " ")
end
local function click(O, rel)
	local p = vector.add(O, rel)
	local node = core.get_node(p)
	local def = core.registered_nodes[node.name]
	def.on_rightclick(p, node, nil)
end

local function puzzles(O, label, done)
	local item
	seq({
		function() say(label .. " start: " .. all_doors(O)); return 0.5 end,
		function() item = core.add_item(vector.add(vector.add(O, tb.plates[2]), {x = 0, y = 0.7, z = 0}), "orthoverse_adventure:pebble"); return 2 end,
		function()
			local nd = core.get_node(vector.add(O, tb.plates[2]))
			say(label .. " pebble on plate: grate=" .. door_open(O, "grate") .. " plate " .. nd.name .. " item at " .. (item:get_pos() and core.pos_to_string(item:get_pos(), 1) or "gone"))
			item:remove(); return 2 end,
		function() say(label .. " pebble gone: grate=" .. door_open(O, "grate"))
			for _, d in ipairs(tb.levers.decoys) do click(O, d) end; return 1 end,
		function() say(label .. " decoys: library=" .. door_open(O, "library")); click(O, tb.levers.library); return 1 end,
		function() say(label .. " real lever: library=" .. door_open(O, "library"))
			click(O, tb.levers.combination[1]); click(O, tb.levers.combination[3]); return 4 end,
		function()
			local function n(x, y, z) local nd = core.get_node(vector.add(O, {x = x, y = y, z = z})); return nd.name:gsub("^.*:", "") end
			say(label .. " levers high,low,high,low: levers=" .. door_open(O, "levers") .. " L1 " .. n(34, 2, 23) .. " L3 " .. n(34, 2, 27) ..
				" T1 " .. n(38, 1, 23) .. " T3 " .. n(38, 1, 27) .. " bus " .. n(39, 1, 27) .. " TF " .. n(37, 1, 31) .. " route " .. n(30, 1, 31))
			click(O, tb.levers.combination[2]); return 4 end,
		function() say(label .. " lever 2 high too: levers=" .. door_open(O, "levers"))
			click(O, tb.levers.combination[2]); click(O, tb.levers.combination[1]); return 4 end,
		function() say(label .. " low,low,high,low: levers=" .. door_open(O, "levers"))
			click(O, tb.levers.iron); click(O, tb.levers.bronze); click(O, tb.levers.silver); return 2 end,
		function()
			say(label .. " ropes: " .. all_doors(O))
			local function n(x, y, z) local nd = core.get_node(vector.add(O, {x = x, y = y, z = z})); return nd.name:gsub("^.*:", "") end
			local col = {}
			for y = 1, 8 do col[#col + 1] = n(28, y, 36) end
			say("silver: lever " .. n(29, 2, 35) .. " w " .. n(29, 1, 36) .. " col " .. table.concat(col, ",") .. " w " .. n(29, 8, 36))
			flush(); done() end,
	})
end

core.after(2, function()
	local A = vector.new(300, 200, 300)
	local B
	seq({
		function(nxt) core.emerge_area(A, vector.add(A, {x = 60, y = 47, z = 42}), function(_, _, left) if left == 0 then nxt() end end) end,
		function()
			forceload(A)
			local missing = tb.build(A)
			local m = {}
			for k in pairs(missing) do m[#m + 1] = k end
			say("built; missing nodes: " .. (#m > 0 and table.concat(m, ", ") or "none"))
			return 5
		end,
		function()
			local data, n = worldedit.serialize(A, vector.add(A, {x = tb.info.size.x - 1, y = tb.info.size.y - 1, z = tb.info.size.z - 1}))
			core.safe_file_write(core.get_worldpath() .. "/three-bells.we", data)
			core.safe_file_write(core.get_worldpath() .. "/three-bells.json", core.write_json(tb.info))
			say(("saved %d nodes, %d bytes"):format(n, #data))
			return 0.5
		end,
		function(nxt) puzzles(A, "built", nxt) end,
		-- Throwing a pebble as a player does (core.item_drop): from where, at which angle
		function(nxt)
			local tries = {}
			for _, z in ipairs({20.2, 19.7, 19.2, 18.5}) do
				for _, deg in ipairs({-10, 0, 10, 20, 30, 40}) do
					for _, x in ipairs({17.0}) do tries[#tries + 1] = {x = x, z = z, deg = deg} end
				end
			end
			local results = {}
			local function one(i)
				local t = tries[i]
				if not t then say("throws (z = distance south, deg up): " .. table.concat(results, "  ")); return nxt() end
				local feet = vector.add(A, {x = t.x, y = 8.5, z = t.z})
				local a = math.rad(t.deg)
				local obj = core.add_item(vector.add(feet, {x = 0, y = 1.2, z = 0}), "orthoverse_adventure:pebble")
				obj:set_velocity({x = 0, y = math.sin(a) * 2.9 + 2, z = math.cos(a) * 2.9})
				core.after(2.5, function()
					local on = core.get_node(vector.add(A, tb.doors.grate)).name
					local door = door_open(A, "grate")
					results[#results + 1] = ("%.1f/%d:%s"):format(t.z, t.deg, door == "open" and "IN" or "out")
					obj:remove()
					core.after(1.2, function() one(i + 1) end)
				end)
			end
			one(1)
		end,
		-- Placing it on a land with the command's code
		function(nxt)
			local key
			for k, land in pairs(orthoverse.lands) do
				local lx, lz = k:match("^(-?%d+):(-?%d+)$")
				lx, lz = tonumber(lx), tonumber(lz)
				if not orthoverse.henges[k] and lx and math.abs(lx) <= 3 and math.abs(lz) <= 3 then key = k; break end
			end
			local lx, lz = key:match("^(-?%d+):(-?%d+)$")
			lx, lz = tonumber(lx), tonumber(lz)
			local x0, zs = lx * 96 - 48 + 10, -lz * 96 - 48 + 10
			say("land " .. key .. " (" .. orthoverse.lands[key].name .. ") at " .. x0 .. "," .. zs)
			core.emerge_area({x = x0, y = 0, z = zs}, {x = x0 + 60, y = 120, z = zs + 42}, function(_, _, left)
				if left > 0 then return end
				local y = 120
				while y > 0 and not (core.registered_nodes[core.get_node({x = x0, y = y, z = zs}).name] or {}).walkable do y = y - 1 end
				say("ground at y=" .. y)
				local t0 = core.get_us_time()
				orthoverse.adventure.place("three-bells", {x = x0, y = y, z = zs}, "tester", function(ok, msg)
					say(("place: %s %s (%.1f s)"):format(tostring(ok), msg, (core.get_us_time() - t0) / 1e6))
					B = {x = x0, y = y - tb.info.ground, z = zs}
					forceload(B)
					local def = orthoverse.adventure.list[key]
					say("def: " .. core.write_json(def))
					core.after(5, nxt)
				end)
			end)
		end,
		function(nxt) puzzles(B, "placed", nxt) end,
		function() flush(); core.request_shutdown() end,
	})
end)
