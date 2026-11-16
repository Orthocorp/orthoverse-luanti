-- Queens puzzles: an N x N board cut into N coloured regions, to be filled
-- with N queens, one in each row, each column and each region, no two
-- touching (not even corner to corner).
--
-- Made the usual way (after greentec's and Lars Niet's write-ups): queens
-- placed at random to fit the rules, a region grown from each queen at
-- random, reshaped square by square until no other answer fits, then kept
-- only if that answer can be reached by reasoning alone (the steps players use: a line or
-- region with one square left; a region shut in one line clears the rest of
-- the line; k regions shut in k lines; a square that would leave a line or
-- region with nowhere to go). Pure Lua, no engine calls, so it can be
-- tested on its own. random(n) gives 1..n.

local P = {}

local function shuffled(n, random)
	local t = {}
	for i = 1, n do t[i] = i end
	for i = n, 2, -1 do
		local j = random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- Queens that fit the rules, as col[row]: one per row and column, and no two
-- in following rows in neighbouring columns
function P.place(n, random)
	local col, used = {}, {}
	local function go(r)
		if r > n then return true end
		for _, c in ipairs(shuffled(n, random)) do
			if not used[c] and (r == 1 or math.abs(col[r - 1] - c) > 1) then
				col[r], used[c] = c, true
				if go(r + 1) then return true end
				used[c] = nil
			end
		end
		return false
	end
	return go(1) and col or nil
end

-- Regions grown from the queens: region[r][c] = 1..n. Each step picks a
-- region (the smaller ones more often, so none swallows the board) and gives
-- it a free square beside it
function P.grow(n, col, random)
	local reg = {}
	for r = 1, n do reg[r] = {} end
	local size = {}
	for r = 1, n do reg[r][col[r]] = r; size[r] = 1 end
	local left = n * n - n
	local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
	while left > 0 do
		-- the regions that can still grow, weighted against their size
		local opts, total = {}, 0
		for k = 1, n do
			local cells = {}
			for r = 1, n do
				for c = 1, n do
					if reg[r][c] == k then
						for _, d in ipairs(DIRS) do
							local rr, cc = r + d[1], c + d[2]
							if rr >= 1 and rr <= n and cc >= 1 and cc <= n and not reg[rr][cc] then
								cells[#cells + 1] = {rr, cc}
							end
						end
					end
				end
			end
			if #cells > 0 then
				local w = math.max(1, 2 * n - size[k])
				opts[#opts + 1] = {k, cells, w}
				total = total + w
			end
		end
		local x = random(total)
		local pick = opts[#opts]
		for _, o in ipairs(opts) do
			if x <= o[3] then pick = o; break end
			x = x - o[3]
		end
		local cell = pick[2][random(#pick[2])]
		reg[cell[1]][cell[2]] = pick[1]
		size[pick[1]] = size[pick[1]] + 1
		left = left - 1
	end
	return reg
end

-- How many answers (stopping at 2)
function P.count(n, reg)
	local found = 0
	local colused, regused, col = {}, {}, {}
	local function go(r)
		if r > n then found = found + 1; return found >= 2 end
		for c = 1, n do
			local k = reg[r][c]
			if not colused[c] and not regused[k] and (r == 1 or math.abs(col[r - 1] - c) > 1) then
				colused[c], regused[k], col[r] = true, true, c
				if go(r + 1) then return true end
				colused[c], regused[k] = nil, nil
			end
		end
		return false
	end
	go(1)
	return found
end

-- An answer other than `col` (as col[row]), or nil
function P.other(n, reg, want)
	local colused, regused, col = {}, {}, {}
	local function go(r)
		if r > n then
			for i = 1, n do if col[i] ~= want[i] then return true end end
			return false
		end
		for c = 1, n do
			local k = reg[r][c]
			if not colused[c] and not regused[k] and (r == 1 or math.abs(col[r - 1] - c) > 1) then
				colused[c], regused[k], col[r] = true, true, c
				if go(r + 1) then return true end
				colused[c], regused[k] = nil, nil
			end
		end
		return false
	end
	if go(1) then return col end
end

-- Is region k still in one piece (squares joined side to side)?
local function joined(n, reg, k)
	local start, total = nil, 0
	for r = 1, n do
		for c = 1, n do
			if reg[r][c] == k then total = total + 1; start = start or {r, c} end
		end
	end
	if not start then return false end
	local seen, stack, got = {[start[1] * 100 + start[2]] = true}, {start}, 1
	while #stack > 0 do
		local cell = table.remove(stack)
		for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
			local r, c = cell[1] + d[1], cell[2] + d[2]
			if r >= 1 and r <= n and c >= 1 and c <= n and reg[r][c] == k and not seen[r * 100 + c] then
				seen[r * 100 + c] = true; got = got + 1; stack[#stack + 1] = {r, c}
			end
		end
	end
	return got == total
end

-- Reshape the regions until `col` is the only answer: while there is
-- another, give one of its queens' squares (never one of ours) to a
-- neighbouring region, keeping every region in one piece. Returns true if
-- it got there within `steps`
function P.repair(n, reg, col, random, steps)
	for _ = 1, steps do
		local alt = P.other(n, reg, col)
		if not alt then return true end
		local moves = {}
		for r = 1, n do
			local c = alt[r]
			if col[r] ~= c then
				local k = reg[r][c]
				for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
					local rr, cc = r + d[1], c + d[2]
					if rr >= 1 and rr <= n and cc >= 1 and cc <= n and reg[rr][cc] ~= k then
						moves[#moves + 1] = {r, c, reg[rr][cc]}
					end
				end
			end
		end
		local done = false
		while #moves > 0 and not done do
			local i = random(#moves)
			local m = table.remove(moves, i)
			local old = reg[m[1]][m[2]]
			reg[m[1]][m[2]] = m[3]
			if joined(n, reg, old) then done = true else reg[m[1]][m[2]] = old end
		end
		if not done then return false end
	end
	return P.other(n, reg, col) == nil
end

-- Solving by reasoning only. Returns true if the rules below fill the board
-- (with a unique board, that is its answer), and how many rounds it took
function P.reason(n, reg)
	-- cand[r][c]: could still hold a queen; queen[r] = c once placed
	local cand, queen = {}, {}
	for r = 1, n do
		cand[r] = {}
		for c = 1, n do cand[r][c] = true end
	end
	local function cells_of(kind, i)
		local t = {}
		for r = 1, n do
			for c = 1, n do
				if cand[r][c] and ((kind == "row" and r == i) or (kind == "col" and c == i) or (kind == "reg" and reg[r][c] == i)) then
					t[#t + 1] = {r, c}
				end
			end
		end
		return t
	end
	local function put(r, c)
		queen[r] = c
		local k = reg[r][c]
		for rr = 1, n do
			for cc = 1, n do
				if cand[rr][cc] and (rr == r or cc == c or reg[rr][cc] == k or (math.abs(rr - r) <= 1 and math.abs(cc - c) <= 1)) then
					cand[rr][cc] = false
				end
			end
		end
	end
	local placed = 0
	-- Would a queen here leave some line or region without a square?
	local function kills(r, c)
		local k = reg[r][c]
		local function gone(rr, cc)
			return rr == r or cc == c or reg[rr][cc] == k or (math.abs(rr - r) <= 1 and math.abs(cc - c) <= 1)
		end
		for i = 1, n do
			for _, kind in ipairs({"row", "col", "reg"}) do
				local open, done = false, false
				if kind == "row" then done = queen[i] ~= nil or i == r
				elseif kind == "col" then
					done = i == c
					for _, qc in pairs(queen) do if qc == i then done = true end end
				else
					done = i == k
					for qr, qc in pairs(queen) do if reg[qr][qc] == i then done = true end end
				end
				if not done then
					for _, cell in ipairs(cells_of(kind, i)) do
						if not gone(cell[1], cell[2]) then open = true; break end
					end
					if not open then return true end
				end
			end
		end
		return false
	end
	local rounds = 0
	while placed < n do
		rounds = rounds + 1
		if rounds > 200 then return false, rounds end
		local progress = false
		-- 1. a row, column or region with one square left
		for _, kind in ipairs({"row", "col", "reg"}) do
			for i = 1, n do
				local t = cells_of(kind, i)
				if #t == 1 then
					put(t[1][1], t[1][2]); placed = placed + 1; progress = true
				end
			end
		end
		if not progress then
			-- 2. k groups of one kind shut inside k lines of another clear the
			-- rest of those lines (k = 1 to 3)
			local kinds = {{"reg", "row"}, {"reg", "col"}, {"row", "reg"}, {"col", "reg"}}
			for _, pair in ipairs(kinds) do
				local a, b = pair[1], pair[2]
				-- each open group of kind a, as the set of b-lines it touches
				local groups = {}
				for i = 1, n do
					local t = cells_of(a, i)
					if #t > 0 then
						local lines, nl = {}, 0
						for _, cell in ipairs(t) do
							local l = b == "row" and cell[1] or b == "col" and cell[2] or reg[cell[1]][cell[2]]
							if not lines[l] then lines[l] = true; nl = nl + 1 end
						end
						groups[#groups + 1] = {i = i, lines = lines, nl = nl}
					end
				end
				local function try(chosen, union, nu)
					if #chosen > 0 and #chosen == nu then
						-- clear squares of those lines outside the chosen groups
						local inside = {}
						for _, g in ipairs(chosen) do inside[g.i] = true end
						for r = 1, n do
							for c = 1, n do
								if cand[r][c] then
									local l = b == "row" and r or b == "col" and c or reg[r][c]
									local g = a == "row" and r or a == "col" and c or reg[r][c]
									if union[l] and not inside[g] then cand[r][c] = false; progress = true end
								end
							end
						end
						return
					end
					if #chosen >= 3 then return end
					local last = chosen[#chosen] and chosen[#chosen].idx or 0
					for idx = last + 1, #groups do
						local g = groups[idx]
						local u, m = {}, 0
						for l in pairs(union) do u[l] = true; m = m + 1 end
						for l in pairs(g.lines) do if not u[l] then u[l] = true; m = m + 1 end end
						if m <= 3 then
							g.idx = idx
							chosen[#chosen + 1] = g
							try(chosen, u, m)
							chosen[#chosen] = nil
						end
					end
				end
				try({}, {}, 0)
				if progress then break end
			end
		end
		if not progress then
			-- 3. a square that would leave some line or region nowhere to go
			for r = 1, n do
				for c = 1, n do
					if cand[r][c] and kills(r, c) then cand[r][c] = false; progress = true end
				end
			end
		end
		if not progress then return false, rounds end
	end
	return true, rounds, queen
end

-- A new puzzle: {n = n, region = reg, queen = col}. Tries up to `tries`
-- growths (new queens every 20) and returns nil if none would do
function P.make(n, random, tries)
	local col
	for t = 1, tries or 400 do
		if t % 20 == 1 then col = P.place(n, random) end
		local reg = P.grow(n, col, random)
		if P.repair(n, reg, col, random, 60) and P.reason(n, reg) then
			return {n = n, region = reg, queen = col, tries = t}
		end
	end
end

return P
