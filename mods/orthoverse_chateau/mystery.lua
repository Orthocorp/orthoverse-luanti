-- Death at the Château: the mystery. At the start of each run a murderer, a
-- weapon and a room are drawn, and the château's clue places are filled with
-- evidence written to fit: alibis that clear the innocent (and the rooms they
-- were in), notes that clear the empty rooms, a weapon taken for an innocent
-- reason, the murder weapon hidden behind a puzzle, a trace in the room
-- where he died, and a false alibi for the murderer that does not cover the
-- moment of death. The player reads, strikes out, asks Madame Or's cards
-- twice, and accuses: wrong once is forgiven, wrong twice and they are shown
-- out (orthoverse.adventure.expel), with nothing.

local S = core.get_translator("orthoverse_chateau")
local C = orthoverse.chateau
local tex = C.tex

local READINGS = 2
local ACCUSATIONS = 2
local NOTES = {"Do", "Ré", "Mi", "Fa", "Sol", "La", "Si"}
local TUNE_LENGTH = 5
local FEMALE = {marquise = true, ivoire = true, ["or"] = true}
-- Where each weapon belongs
local HOME = {chandelier = "salle_a_manger", coupe_papier = "bureau", belladone = "jardin", pistolet = "armes",
	cordon = "musique", tisonnier = "bibliotheque"}

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end
local function pick(t) return t[math.random(#t)] end
local function hhmm(m) return ("%d:%02d"):format(math.floor(m / 60) % 24, m % 60) end
local function name_of(id) return C.person[id].name end
local function names(list)
	local n = {}
	for i, id in ipairs(list) do n[i] = name_of(id) end
	if #n <= 1 then return n[1] or "" end
	return table.concat(n, ", ", 1, #n - 1) .. " and " .. n[#n]
end
local function them(list)
	if #list > 1 then return "them" end
	return FEMALE[list[1]] and "her" or "him"
end

------------------------------------------------------------------------------
-- The run

local function adventure(pos)
	local ad = orthoverse.adventure
	if not (ad and ad.at) then return end
	local key, def = ad.at(pos)
	if not key then return end
	return key, def, ad.runs and ad.runs[key]
end

local function area(def)
	local a, b = def.corner1, def.corner2
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

-- The run (and its mystery) a player is in, at this château
local function case_of(player, pos)
	if not (player and player:is_player()) then return end
	local name = player:get_player_name()
	local key, def, run = adventure(pos or player:get_pos())
	if not (run and run.members[name] and run.chateau) then return end
	return run.chateau, key, def, run
end
C.case_of = case_of

local function outside_run(player)
	core.chat_send_player(player:get_player_name(),
		S("Nothing to find here now: the mystery is laid out when a run begins."))
end

------------------------------------------------------------------------------
-- What the clues say

local ALIBI = {
	salon = "A score sheet for piquet, left on the card table in Le Grand Salon. The players: %s. The first hand " ..
		"was dealt at %s and the last at %s, each one timed in the margin.",
	bibliotheque = "The visitors' book of La Bibliothèque. Signed by %s: in at %s, out at %s.",
	salle_a_manger = "The butler's book: \"%s stayed at the table in La Salle à Manger over the port, from %s until " ..
		"%s. I served %s myself and did not leave the room.\"",
	jardin = "The gardener's notebook: \"%s among the orchids in Le Jardin d'Hiver from %s to %s. I never let a " ..
		"guest out of my sight near my plants.\"",
	cave = "The steward's cellar book: \"Took %s down to La Cave à Vin to taste the old vintages at %s. Brought %s " ..
		"up again at %s.\"",
	musique = "The programme of the evening's recital in La Salle de Musique, each piece ticked off as it was " ..
		"played. In the audience, noted by the page-turner: %s, from %s until %s.",
	armes = "A billiards score card from La Salle d'Armes. The players: %s. Break at %s; the last frame ended at %s.",
	cuisine = "The cook's slate in La Cuisine: \"%s down here from %s to %s, eating my pastries and under my feet " ..
		"the whole time.\"",
}

local function alibi_text(room, who, t1, t2)
	local w, a, b = names(who), hhmm(t1), hhmm(t2)
	if room == "salle_a_manger" then return ALIBI[room]:format(w, a, b, them(who)) end
	if room == "cave" then return ALIBI[room]:format(w, a, them(who), b) end
	return ALIBI[room]:format(w, a, b)
end

local EMPTY_ROOM = {
	salon = "The footman's note: \"I tended the fire in Le Grand Salon from ten o'clock until the body was found, " ..
		"and no one came in.\"",
	bibliotheque = "The librarian's note: \"I locked La Bibliothèque at half past nine, and the key never left " ..
		"my pocket until morning.\"",
	salle_a_manger = "The butler's book: \"From ten until midnight the footmen and I cleared La Salle à Manger, " ..
		"and no guest set foot in it.\"",
	jardin = "The gardener's notebook: \"Raked the gravel in Le Jardin d'Hiver at nine. In the morning not a " ..
		"footprint marked it.\"",
	cave = "The steward's cellar book: \"Bolted La Cave à Vin at nine. Found the bolt as I left it at six.\"",
	bureau = "The valet's note: \"Monsieur le Comte's study was locked all evening. I carry the only key, and I " ..
		"sat at its door until midnight.\"",
	musique = "The piano tuner's note: \"I chalked the door of La Salle de Musique when I left at half past " ..
		"nine, as I always do. The chalk was unbroken in the morning.\"",
	armes = "The gamekeeper's note: \"I locked La Salle d'Armes after dinner and kept the key on my belt all " ..
		"night.\"",
	cuisine = "The cook's slate: \"My girls and I were in La Cuisine until well past midnight. No guest came " ..
		"down all night.\"",
}

local DECOY = {
	chandelier = "Le Chandelier en Argent, with a footman's note tucked under it: \"Taken down to be polished " ..
		"before dinner, and not brought back up.\" It is spotless, and it was nowhere near Monsieur Lenoir.",
	coupe_papier = "Le Coupe-Papier en Ivoire, with the valet's note: \"Borrowed to open the evening's post at " ..
		"eight, and left here since.\" There is not a mark on it.",
	belladone = "La Fiole de Belladone, with the Doctor's card: \"Taken at seven to make up drops for the cook's " ..
		"eyes.\" The vial is still full to its mark.",
	pistolet = "Le Pistolet de Duel, with the gamekeeper's tag: \"Taken down for cleaning.\" It has not been " ..
		"fired: the pan is full of old dust.",
	cordon = "Le Cordon de Velours, in a maid's sewing basket with a note: \"Caught in the window and torn: to " ..
		"mend.\" It was here all evening.",
	tisonnier = "Le Tisonnier en Fer Forgé, with a maid's note: \"Carried up at eight to see to a bedroom fire.\" " ..
		"It is cold and clean.",
}

local MOTIVE = {
	comte = "A bundle of unpaid bills, the oldest years overdue, tied with purple ribbon. A card on top: " ..
		"\"I will take them all off your hands, and the château with them. S.L.\"",
	marquise = "A letter in a woman's hand, unsigned: \"He has my letters, and he means to sell them. I will not " ..
		"be ruined by a dealer in pictures.\"",
	general = "A gambling marker for forty thousand francs, signed by Le Général Safran and made over to " ..
		"S. Lenoir.",
	ivoire = "A concert programme with a note pencilled across it: \"The violin was never yours to sell, S.L. " ..
		"Give it back, or you will pay.\"",
	emeraude = "A page torn from a bank ledger, its figures altered and initialled L.É. Pinned to it, a card: " ..
		"\"I know. S.L.\"",
	duc = "A copy of a letter from Le Duc Azur to a foreign minister. On the back, in another hand: \"The " ..
		"original is somewhere safe. S.L.\"",
	docteur = "A death certificate signed by Docteur Cendre, and a note with it: \"Natural causes, Émile? We " ..
		"both know better. S.L.\"",
	["or"] = "A tarot card, the Tower, with a message on its back: \"You read my fortune, Madame. I have read " ..
		"your past. S.L.\"",
}

local NOTHING = {
	"Nothing here but dust and a forgotten glove.",
	"Old letters about the vineyards, of no interest to anyone.",
	"Spare candles, a tinderbox and a moth.",
	"A child's drawing of the château, years old.",
	"Receipts for coal and candles. Nothing more.",
}

local TRACE = "Half hidden here, a black onyx cufflink engraved S.L.: Monsieur Lenoir's. Beside it, a patch of " ..
	"carpet has been scrubbed so hard that the pile is worn."
local WEAPON_FOUND = "Pushed out of sight here: %s, wiped clean, but not clean enough. Whoever killed Monsieur " ..
	"Lenoir hid it here."

------------------------------------------------------------------------------
-- Drawing a run's mystery

local function poskey(p) return p.x .. "," .. p.y .. "," .. p.z end

-- A page that answers (the safe, the piano, the rack, the table, the
-- accusation): what a player sends back counts only for the page last shown
-- to them, and only near the thing it belongs to
local function show(player, d, formname, fs, pos)
	local name = player:get_player_name()
	d.open = d.open or {}
	d.open[name] = {form = formname, pos = pos}
	core.show_formspec(name, formname, fs)
end

local function draw(def)
	local d = {
		murderer = pick(C.PEOPLE).id, weapon = pick(C.WEAPONS).id, room = pick(C.ROOMS).id,
		T = 22 * 60 + math.random(5, 110),
		vintage = math.random(1745, 1789), year = math.random(1730, 1760),
		tune = {}, readings = READINGS, accusations = ACCUSATIONS,
		facts = {}, found = {}, ticks = {}, sel = {}, opened = {}, played = {}, keys = {},
	}
	for i = 1, TUNE_LENGTH do d.tune[i] = math.random(#NOTES) end
	local T = d.T
	-- The innocent, in groups of one or two, each where others saw them at
	-- the moment of death (not in the room where he died, nor the study,
	-- which was locked)
	local innocent = {}
	for _, p in ipairs(C.PEOPLE) do if p.id ~= d.murderer then innocent[#innocent + 1] = p.id end end
	shuffle(innocent)
	local rooms = {}
	for _, r in ipairs(C.ROOMS) do if r.id ~= d.room and r.id ~= "bureau" then rooms[#rooms + 1] = r.id end end
	shuffle(rooms)
	local facts = {}
	local used = {}
	local alibi_rooms = {}
	local i = 1
	while i <= #innocent do
		local n = (i < #innocent and math.random(3) > 1) and 2 or 1
		local who = {innocent[i], n == 2 and innocent[i + 1] or nil}
		local room = table.remove(rooms, 1)
		local t1 = T - math.random(20, 70)
		local t2 = T + math.random(10, 50)
		facts[#facts + 1] = {text = alibi_text(room, who, t1, t2)}
		used[room] = true
		alibi_rooms[#alibi_rooms + 1] = room
		i = i + n
	end
	-- The rooms nobody was in
	for _, r in ipairs(C.ROOMS) do
		if r.id ~= d.room and not used[r.id] then facts[#facts + 1] = {text = EMPTY_ROOM[r.id]} end
	end
	-- The murderer's alibi, for the wrong time (in a room where others were,
	-- before or after them)
	local hroom = pick(alibi_rooms)
	local t1, t2
	if math.random(2) == 1 then
		t2 = T - math.random(8, 35)
		t1 = t2 - math.random(30, 60)
	else
		t1 = T + math.random(10, 30)
		t2 = t1 + math.random(30, 50)
	end
	facts[#facts + 1] = {text = alibi_text(hroom, {d.murderer}, t1, t2)}
	-- A weapon taken for an innocent reason
	local others = {}
	for _, w in ipairs(C.WEAPONS) do if w.id ~= d.weapon then others[#others + 1] = w.id end end
	d.decoy = pick(others)
	facts[#facts + 1] = {text = DECOY[d.decoy]}
	-- The clue places
	local p1, p2 = area(def)
	local spots = {}
	for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {"group:chateau_spot"})) do
		local meta = core.get_meta(pos)
		spots[#spots + 1] = {pos = pos, room = meta:get_string("room"), gate = meta:get_string("gate")}
	end
	shuffle(spots)
	local function take(ok)
		for k, sp in ipairs(spots) do
			if ok(sp) then return table.remove(spots, k) end
		end
	end
	-- the trace in the room where he died; the weapon behind a puzzle,
	-- elsewhere
	local sp = take(function(s) return s.room == d.room end)
	if sp then d.facts[poskey(sp.pos)] = {text = TRACE} end
	sp = take(function(s) return s.gate ~= "" and s.room ~= d.room end) or take(function(s) return s.gate ~= "" end)
		or take(function() return true end)
	if sp then d.facts[poskey(sp.pos)] = {text = WEAPON_FOUND:format(C.weapon[d.weapon].name)} end
	for _, f in ipairs(shuffle(facts)) do
		sp = table.remove(spots, 1)
		if not sp then
			core.log("error", "[orthoverse_chateau] not enough clue places for the clues")
			break
		end
		d.facts[poskey(sp.pos)] = f
	end
	-- and the rest: motives, and nothing much
	local motives = {}
	for id, text in pairs(MOTIVE) do motives[#motives + 1] = text end
	shuffle(motives)
	for _, s in ipairs(spots) do
		d.facts[poskey(s.pos)] = {text = table.remove(motives) or pick(NOTHING)}
	end
	-- The weapons that are not in their places
	for _, wid in ipairs({d.weapon, d.decoy}) do
		local w = C.weapon[wid]
		for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {w.place})) do
			local nd = core.get_node(pos)
			core.swap_node(pos, {name = w.gone, param2 = nd.param2})
		end
	end
	core.log("action", ("[orthoverse_chateau] a run drawn: %s, %s, %s at %s"):format(d.murderer, d.weapon, d.room, hhmm(T)))
	return d
end
C.draw = draw

------------------------------------------------------------------------------
-- The casebook: the clues found, and the names struck out

local function note(d, name, title, text, k)
	d.found[name] = d.found[name] or {}
	for _, e in ipairs(d.found[name]) do
		if e.k == k then return end
	end
	table.insert(d.found[name], {title = title, text = text, k = k})
end

local function show_found(player, d, title, text, k)
	note(d, player:get_player_name(), title, text, k)
	C.show_text(player, title, text .. "\n\n" .. S("(Noted in your casebook.)"))
end

local function casebook_fs(name, d)
	local list = d and d.found[name] or {}
	local items = {}
	for i, e in ipairs(list) do items[i] = core.formspec_escape(e.title) end
	local sel = d and math.min(d.sel[name] or 1, #list) or 0
	local fs = {"formspec_version[4]size[17,11.7]box[0,0;17,0.9;#3a2030]label[0.3,0.45;" ..
		core.formspec_escape(S("Casebook: the death of Monsieur Sébastien Lenoir")) .. "]"}
	if not d then
		fs[#fs + 1] = "label[0.4,1.6;" .. core.formspec_escape(S("Your casebook is empty. It fills in a run at the château.")) .. "]"
		fs[#fs + 1] = "button_exit[7,10.7;3,0.7;ok;" .. S("Close") .. "]"
		return table.concat(fs)
	end
	fs[#fs + 1] = ("label[0.4,1.3;%s]"):format(core.formspec_escape(("Lenoir died at %s, if his watch is right. Madame Or's " ..
		"readings left: %d. Accusations left: %d."):format(d.found_time and hhmm(d.T) or "?", d.readings, d.accusations)))
	fs[#fs + 1] = "textlist[0.4,1.8;5.6,8.6;clues;" .. table.concat(items, ",") .. ";" .. sel .. "]"
	local text = list[sel] and list[sel].text or S("Nothing found yet. Search the château.")
	fs[#fs + 1] = "textarea[6.2,1.8;5.4,8.6;;;" .. core.formspec_escape(text) .. "]"
	local ticks = d.ticks[name] or {}
	local y = 1.8
	fs[#fs + 1] = "label[11.9,1.6;" .. S("Strike out:") .. "]"
	local function box(id, label)
		y = y + 0.37
		fs[#fs + 1] = ("checkbox[11.9,%.2f;t_%s;%s;%s]"):format(y, id, core.formspec_escape(label), ticks[id] and "true" or "false")
	end
	for _, p in ipairs(C.PEOPLE) do box(p.id, p.name) end
	y = y + 0.12
	for _, w in ipairs(C.WEAPONS) do box(w.id, w.name) end
	y = y + 0.12
	for _, r in ipairs(C.ROOMS) do box(r.id, r.name) end
	fs[#fs + 1] = "button_exit[0.4,10.7;3,0.7;ok;" .. S("Close") .. "]"
	return table.concat(fs)
end

core.register_craftitem("orthoverse_chateau:casebook", {
	description = S("Casebook") .. "\n" .. S("Use it (left click) to read your clues and strike out names"),
	inventory_image = tex("casebook"),
	stack_max = 1,
	groups = {orthoverse_kit = 1},
	on_use = function(itemstack, user)
		if not (user and user:is_player()) then return end
		local d = case_of(user)
		core.show_formspec(user:get_player_name(), "orthoverse_chateau:casebook", casebook_fs(user:get_player_name(), d))
	end,
})

core.register_craftitem("orthoverse_chateau:key", {
	description = S("The gardener's key"),
	inventory_image = tex("key"),
	stack_max = 1,
	groups = {not_in_creative_inventory = 1},
})

------------------------------------------------------------------------------
-- The clue places

local function spot_title(pos)
	local meta = core.get_meta(pos)
	local r = C.room[meta:get_string("room")]
	return (r and r.name or "") .. ": " .. (meta:get_string("spot") ~= "" and meta:get_string("spot") or
		core.registered_nodes[core.get_node(pos).name].description)
end

-- The safe's lock: four figures
local function safe_fs()
	return "formspec_version[4]size[9,4.4]box[0,0;9,0.9;#3a2030]label[0.3,0.45;" .. S("The wall safe") .. "]" ..
		"textarea[0.4,1.1;8.2,1.2;;;" .. core.formspec_escape(S("A dial of four figures. Scratched beside it: \"The year I sat for it.\"")) .. "]" ..
		"field[0.4,2.9;3,0.8;code;;]field_close_on_enter[code;false]" ..
		"button[3.6,2.9;2.4,0.8;try;" .. S("Turn") .. "]button_exit[6.2,2.9;2.4,0.8;no;" .. S("Leave") .. "]"
end

local function open_spot(pos, node, player)
	local d = case_of(player, pos)
	if not d then return outside_run(player) end
	local meta = core.get_meta(pos)
	local gate = meta:get_string("gate")
	if node.name == "orthoverse_chateau:safe" then
		show(player, d, "orthoverse_chateau:safe", safe_fs(), pos)
		return
	end
	if gate == "piano" and not d.opened.piano then
		core.chat_send_player(player:get_player_name(), S("The bench's lid is locked fast. There is a tiny keyhole shaped like a treble clef."))
		return
	end
	local f = d.facts[poskey(pos)]
	show_found(player, d, spot_title(pos), f and f.text or pick(NOTHING), poskey(pos))
end

for _, id in ipairs({"spot_drawers", "spot_papers", "spot_barrel", "spot_box", "spot_armchair", "spot_bench",
		"safe", "safe_open"}) do
	core.override_item("orthoverse_chateau:" .. id, {
		on_rightclick = function(pos, node, clicker) open_spot(pos, node, clicker) end,
	})
end

------------------------------------------------------------------------------
-- The weapons in their places

local function weapon_place(pos, node, player)
	local d = case_of(player, pos)
	if not d then return outside_run(player) end
	local nd = core.registered_nodes[node.name]
	local w = C.weapon[nd._weapon]
	if w.id == "belladone" and not d.opened.cabinet then
		local held = player:get_wielded_item():get_name()
		if held ~= "orthoverse_chateau:key" then
			core.chat_send_player(player:get_player_name(), S("The apothecary cabinet is locked. The gardener keeps its key."))
			return
		end
		d.opened.cabinet = true
		core.sound_play("orthoverse_chateau_click", {pos = pos, gain = 0.6, max_hear_distance = 12}, true)
	end
	local room = C.room[HOME[w.id]]
	local where = room and (" in " .. room.name) or ""
	if nd._gone then
		show_found(player, d, w.name, ("%s is not in its place%s."):format(w.name, where), "w:" .. w.id)
	else
		show_found(player, d, w.name, ("%s is in its place%s, the dust round it undisturbed. It was not used.")
			:format(w.name, where), "w:" .. w.id)
	end
end

for _, w in ipairs(C.WEAPONS) do
	for _, n in ipairs({w.place, w.gone}) do
		local groups = table.copy(core.registered_nodes[n].groups)
		groups.chateau_weapon = 1
		core.override_item(n, {groups = groups,
			on_rightclick = function(pos, node, clicker) weapon_place(pos, node, clicker) end})
	end
end

------------------------------------------------------------------------------
-- What the run fixes: the body's watch, the menu's wine, the sheet music's
-- tune, the year of the Comte's portrait

function C.body_text(pos)
	local _, _, run = adventure(pos)
	local d = run and run.chateau
	local t = d and hhmm(d.T) or "?"
	if d then d.found_time = true end
	return ("Monsieur Sébastien Lenoir lies at the foot of the stairs. His pocket watch, smashed as he fell, stopped " ..
		"at %s.\n\nThere is too little blood here: he did not die where he lies. Someone carried him here " ..
		"afterwards."):format(t)
end

function C.portrait_text(pos, id)
	local p = C.person[id]
	local text = p.about
	if id == "comte" then
		local _, _, run = adventure(pos)
		local d = run and run.chateau
		text = text .. ("\n\nOn the frame, a brass plate: \"Painted in the year %s, for my fortieth birthday.\"")
			:format(d and tostring(d.year) or "....")
	end
	return text
end

core.override_item("orthoverse_chateau:menu_card", {
	on_rightclick = function(pos, _, clicker)
		local d = case_of(clicker, pos)
		C.show_text(clicker, S("Tonight's menu"),
			"Consommé of pheasant\nSole in champagne\nRoast saddle of lamb with truffles\nPear tart\n\n" ..
			("Wine: Château d'Améthyste, the %s, from the Comte's own cellar."):format(d and tostring(d.vintage) or "...."))
	end,
})

local function tune_text(tune)
	local t = {}
	for i, n in ipairs(tune) do t[i] = NOTES[n] end
	return table.concat(t, " - ")
end

core.override_item("orthoverse_chateau:music_stand", {
	on_rightclick = function(pos, _, clicker)
		local d = case_of(clicker, pos)
		C.show_text(clicker, S("Geneviève's sheet music"),
			"A nocturne, the pages marked in Mademoiselle Ivoire's hand. In the margin, circled twice, a little " ..
			"phrase of five notes:\n\n    " .. (d and tune_text(d.tune) or "...") ..
			"\n\nand beside it: \"For the bench, when I forget the key.\"")
	end,
})

------------------------------------------------------------------------------
-- The piano

local function piano_fs(d, name)
	local played = d and d.played[name] or {}
	local t = {}
	for i, n in ipairs(played) do t[i] = NOTES[n] end
	local fs = {"formspec_version[4]size[9.5,4]box[0,0;9.5,0.9;#3a2030]label[0.3,0.45;" .. S("The grand piano") .. "]"}
	for i, n in ipairs(NOTES) do
		fs[#fs + 1] = ("button[%.2f,1.3;1.2,1.5;n%d;%s]"):format(0.35 + (i - 1) * 1.28, i, n)
	end
	fs[#fs + 1] = "label[0.4,3.3;" .. core.formspec_escape(#t > 0 and table.concat(t, " ") or S("(play)")) .. "]"
	return table.concat(fs)
end

core.override_item("orthoverse_chateau:piano", {
	on_rightclick = function(pos, _, clicker)
		if not (clicker and clicker:is_player()) then return end
		local d = case_of(clicker, pos)
		local name = clicker:get_player_name()
		if not d then return outside_run(clicker) end
		show(clicker, d, "orthoverse_chateau:piano", piano_fs(d, name), pos)
	end,
})

------------------------------------------------------------------------------
-- The secret ways: a false volume in the library; a rack in the cellar that
-- turns when the right bottle is drawn

local function open_near(pos, name, r)
	local list = core.find_nodes_in_area(vector.offset(pos, -r, -r, -r), vector.offset(pos, r, r, r), {name})
	for _, p in ipairs(list) do core.remove_node(p) end
	if #list > 0 then core.sound_play("orthoverse_chateau_grind", {pos = pos, gain = 0.8, max_hear_distance = 16}, true) end
	return #list
end

core.override_item("orthoverse_chateau:false_book", {
	on_rightclick = function(pos, _, clicker)
		local d = case_of(clicker, pos)
		if not d then return outside_run(clicker) end
		if open_near(pos, "orthoverse_chateau:shelf_door", 3) > 0 then
			core.chat_send_player(clicker:get_player_name(), S("You tip the red volume back. Something clicks, and part of the shelves swings away."))
		end
	end,
})

local function rack_fs(d)
	local years = {d.vintage}
	while #years < 6 do
		local y = math.random(1745, 1789)
		local dup = false
		for _, v in ipairs(years) do if v == y then dup = true end end
		if not dup then years[#years + 1] = y end
	end
	table.sort(years)
	local fs = {"formspec_version[4]size[9,4.6]box[0,0;9,0.9;#3a2030]label[0.3,0.45;" .. S("A wine rack") .. "]" ..
		"label[0.4,1.4;" .. core.formspec_escape(S("Six dusty bottles of Château d'Améthyste lie in the middle row. One is not quite like the others.")) .. "]"}
	for i, y in ipairs(years) do
		fs[#fs + 1] = ("button[%.2f,2.3;1.3,1;v%d;%d]"):format(0.4 + (i - 1) * 1.4, y, y)
	end
	fs[#fs + 1] = "button_exit[3.5,3.6;2,0.7;no;" .. S("Leave") .. "]"
	return table.concat(fs)
end

core.override_item("orthoverse_chateau:rack_door", {
	on_rightclick = function(pos, _, clicker)
		local d = case_of(clicker, pos)
		if not d then return outside_run(clicker) end
		show(clicker, d, "orthoverse_chateau:rack", rack_fs(d), pos)
	end,
})

core.override_item("orthoverse_chateau:keyhook", {
	on_rightclick = function(pos, node, clicker)
		local d = case_of(clicker, pos)
		if not d then return outside_run(clicker) end
		local inv = clicker:get_inventory()
		local stack = ItemStack("orthoverse_chateau:key")
		if inv:room_for_item("main", stack) then
			inv:add_item("main", stack)
			core.swap_node(pos, {name = "orthoverse_chateau:keyhook_empty", param2 = node.param2})
			core.chat_send_player(clicker:get_player_name(), S("You take the gardener's key from its hook."))
		end
		-- (what is in the hand now: the key may have gone into the slot held,
		-- and returning nothing would put back what was there before)
		return clicker:get_wielded_item()
	end,
})

------------------------------------------------------------------------------
-- Madame Or's table and the accusation

local function choices()
	local s, w, r = {}, {}, {}
	for i, p in ipairs(C.PEOPLE) do s[i] = core.formspec_escape(p.name) end
	for i, x in ipairs(C.WEAPONS) do w[i] = core.formspec_escape(x.name) end
	for i, x in ipairs(C.ROOMS) do r[i] = core.formspec_escape(x.name) end
	return table.concat(s, ","), table.concat(w, ","), table.concat(r, ",")
end

local function three_fs(title, intro, button, d)
	local s, w, r = choices()
	return "formspec_version[4]size[11,6.4]box[0,0;11,0.9;#3a2030]label[0.3,0.45;" .. core.formspec_escape(title) .. "]" ..
		"textarea[0.4,1.1;10.2,1.6;;;" .. core.formspec_escape(intro) .. "]" ..
		"label[0.4,3.0;" .. S("Who") .. "]dropdown[2.2,2.7;8.4,0.7;who;" .. s .. ";1;true]" ..
		"label[0.4,3.9;" .. S("With") .. "]dropdown[2.2,3.6;8.4,0.7;with;" .. w .. ";1;true]" ..
		"label[0.4,4.8;" .. S("Where") .. "]dropdown[2.2,4.5;8.4,0.7;where;" .. r .. ";1;true]" ..
		"button[0.4,5.5;5,0.7;go;" .. core.formspec_escape(button) .. "]button_exit[6,5.5;4.6,0.7;no;" .. S("Not yet") .. "]"
end

core.override_item("orthoverse_chateau:fortune_table", {
	on_rightclick = function(pos, _, clicker)
		local d = case_of(clicker, pos)
		if not d then return outside_run(clicker) end
		if d.readings <= 0 then
			C.show_text(clicker, S("Madame Or's table"), S("The cards lie face down, and will not turn again tonight."))
			return
		end
		show(clicker, d, "orthoverse_chateau:table", three_fs(S("Madame Or's table"),
			("Name a guest, a weapon and a room, and the cards will turn. One that is wrong will show its face; if " ..
			"none is wrong, none will. The cards will answer %d more time%s tonight.")
				:format(d.readings, d.readings == 1 and "" or "s"), S("Turn the cards"), d), pos)
	end,
})

core.override_item("orthoverse_chateau:accusation_desk", {
	on_rightclick = function(pos, _, clicker)
		local d = case_of(clicker, pos)
		if not d then return outside_run(clicker) end
		if d.solved then return end
		show(clicker, d, "orthoverse_chateau:accuse", three_fs(S("The accusation"),
			d.accusations > 1 and S("Name the murderer, the weapon and the room. If you are wrong, you may try once more; wrong a second time and the Comte will have you shown out.")
				or S("Name the murderer, the weapon and the room. You have been wrong once tonight: if you are wrong again, the Comte will have you shown out."),
			S("I accuse"), d), pos)
	end,
})

local function chosen(fields)
	local s = C.PEOPLE[tonumber(fields.who) or 0]
	local w = C.WEAPONS[tonumber(fields.with) or 0]
	local r = C.ROOMS[tonumber(fields.where) or 0]
	return s, w, r
end

------------------------------------------------------------------------------
-- The answers to every page

core.register_on_player_receive_fields(function(player, formname, fields)
	if not formname:match("^orthoverse_chateau:") then return end
	local name = player:get_player_name()
	local d, key = case_of(player)
	if formname == "orthoverse_chateau:casebook" then
		if not d then return true end
		d.ticks[name] = d.ticks[name] or {}
		for f, v in pairs(fields) do
			local id = f:match("^t_([%w_]+)$")
			if id then d.ticks[name][id] = (v == "true") or nil end
		end
		if fields.clues then
			local ev = core.explode_textlist_event(fields.clues)
			if ev.type == "CHG" or ev.type == "DCL" then
				d.sel[name] = ev.index
				core.show_formspec(name, formname, casebook_fs(name, d))
			end
		end
		return true
	end
	if not d then return true end
	local o = d.open and d.open[name]
	if not o or o.form ~= formname or not o.pos or vector.distance(player:get_pos(), o.pos) > 6 then return true end
	local at = o.pos
	if formname == "orthoverse_chateau:safe" then
		if not (fields.try or fields.key_enter_field) then return true end
		if tostring(fields.code or ""):gsub("%s", "") == tostring(d.year) then
			local nd = core.get_node(at)
			if nd.name == "orthoverse_chateau:safe" then
				core.swap_node(at, {name = "orthoverse_chateau:safe_open", param2 = nd.param2})
			end
			core.sound_play("orthoverse_chateau_click", {pos = at, gain = 0.8, max_hear_distance = 12}, true)
			local f = d.facts[poskey(at)]
			show_found(player, d, spot_title(at), f and f.text or pick(NOTHING), poskey(at))
		else
			core.chat_send_player(name, S("The dial turns, but the door stays shut."))
		end
		return true
	end
	if formname == "orthoverse_chateau:piano" then
		for i = 1, #NOTES do
			if fields["n" .. i] then
				core.sound_play("orthoverse_chateau_note_" .. i, {pos = at, gain = 0.9, max_hear_distance = 24}, true)
				local played = d.played[name] or {}
				played[#played + 1] = i
				while #played > TUNE_LENGTH do table.remove(played, 1) end
				d.played[name] = played
				local match = #played == TUNE_LENGTH
				for k = 1, TUNE_LENGTH do if played[k] ~= d.tune[k] then match = false end end
				if match and not d.opened.piano then
					d.opened.piano = true
					core.after(0.8, function()
						core.sound_play("orthoverse_chateau_click", {pos = at, gain = 0.8, max_hear_distance = 12}, true)
						core.chat_send_player(name, S("As the last note fades, something clicks inside the piano bench."))
					end)
				end
				show(player, d, formname, piano_fs(d, name), at)
			end
		end
		return true
	end
	if formname == "orthoverse_chateau:rack" then
		for f in pairs(fields) do
			local y = tonumber(f:match("^v(%d+)$") or "")
			if y then
				core.close_formspec(name, formname)
				if y == d.vintage then
					open_near(at, "orthoverse_chateau:rack_door", 3)
					core.chat_send_player(name, S("You draw the bottle half out. With a groan, the whole rack turns on a hidden pivot."))
				else
					core.chat_send_player(name, S("The bottle will not move."))
				end
			end
		end
		return true
	end
	if formname == "orthoverse_chateau:table" then
		if not fields.go or d.readings <= 0 then return true end
		local s, w, r = chosen(fields)
		if not (s and w and r) then return true end
		d.open[name] = nil
		d.readings = d.readings - 1
		local wrong = {}
		if s.id ~= d.murderer then wrong[#wrong + 1] = s.name end
		if w.id ~= d.weapon then wrong[#wrong + 1] = w.name end
		if r.id ~= d.room then wrong[#wrong + 1] = r.name end
		local q = ("%s, %s, %s"):format(s.name, w.name, r.name)
		local answer
		if #wrong == 0 then
			answer = "All three cards lie still. None of them is wrong."
		else
			answer = ("The cards turn, and one shows its face: %s. That one is wrong."):format(pick(wrong))
		end
		core.sound_play("orthoverse_chateau_card", {to_player = name, gain = 0.8}, true)
		show_found(player, d, ("Madame Or's cards (%d)"):format(READINGS - d.readings), "You asked: " .. q .. ".\n\n" .. answer,
			"r" .. d.readings)
		return true
	end
	if formname == "orthoverse_chateau:accuse" then
		if not fields.go or d.solved or d.accusations <= 0 then return true end
		local s, w, r = chosen(fields)
		if not (s and w and r) then return true end
		d.open[name] = nil
		core.close_formspec(name, formname)
		core.sound_play("orthoverse_chateau_gong", {to_player = name, gain = 0.9}, true)
		if s.id == d.murderer and w.id == d.weapon and r.id == d.room then
			d.solved = true
			core.log("action", "[orthoverse_chateau] " .. name .. " solved it")
			C.show_text(player, S("Solved"), ("\"%s,\" you say, \"with %s, in %s.\"\n\nThe room is silent. Then %s rises, " ..
				"very pale, and does not deny it. Le Comte d'Améthyste bows to you: the château is in your debt.")
				:format(s.name, w.short, r.name, s.name))
			orthoverse.adventure.finish(name, key)
		else
			d.accusations = d.accusations - 1
			if d.accusations > 0 then
				C.show_text(player, S("Non."), S("Le Comte shakes his head. \"Non.\" He says no more. You may try once more."))
			else
				core.log("action", "[orthoverse_chateau] " .. name .. " was shown out")
				orthoverse.adventure.expel(name, key, S("Wrong again. Le Comte d'Améthyste has you shown out into the storm."))
			end
		end
		return true
	end
	return true
end)

------------------------------------------------------------------------------
-- The run begins: the mystery is drawn. And the storm.

core.register_on_mods_loaded(function()
	local ad = orthoverse.adventure
	if not (ad and ad.on_enter) then return end
	table.insert(ad.on_enter, function(player, key, def, run)
		if run.chateau or def.template ~= "chateau" then return end
		run.chateau = draw(def)
	end)
end)

local storm = 0
core.register_globalstep(function(dtime)
	storm = storm + dtime
	if storm < 1 then return end
	storm = 0
	local ad = orthoverse.adventure
	if not (ad and ad.runs) then return end
	for _, run in pairs(ad.runs) do
		if run.chateau and math.random(45) == 1 then
			for n in pairs(run.members) do
				local p = core.get_player_by_name(n)
				if p then
					local id = p:hud_add({type = "image", position = {x = 0.5, y = 0.5}, scale = {x = -100, y = -100},
						text = "[fill:16x16:#ffffff^[opacity:70", z_index = 900})
					core.after(0.12, function()
						local q = core.get_player_by_name(n)
						if q then q:hud_remove(id) end
					end)
					core.after(1 + math.random() * 2, function()
						core.sound_play("orthoverse_chateau_thunder", {to_player = n, gain = 0.7}, true)
					end)
				end
			end
		end
	end
end)

------------------------------------------------------------------------------
-- How to play: the notice in the hall

local RULES = [[Monsieur Sébastien Lenoir is dead. One of the eight other guests killed him, with one of six weapons, in one of nine rooms. It is different every time you come.

Search the château. Right-click drawers, papers, barrels, chairs, caskets and the like: what you find goes into your casebook. Use the casebook (left click with it in your hand) to read your clues and strike out names, weapons and rooms.

His watch tells you when he died. A guest whom others saw somewhere at that moment did not kill him, and a room where people were at that moment is not where he died. Check the times: an alibi for the wrong hour clears no one.

A weapon still in its place, untouched, was not used. Right-click the weapons' places to look.

Some places are locked or hidden. The château's puzzles open them, and the answers are somewhere in the house.

Madame Or's table in Le Grand Salon answers twice. Name a guest, a weapon and a room: her cards show one of the three that is wrong, or none if all three are right.

When you are sure, make your accusation at the desk in Le Grand Salon. You may be wrong once. Wrong twice, and you are shown out, with nothing.]]

C.on_wall("notice", "How to play (right-click)", tex("papers"), {
	on_rightclick = function(_, _, clicker)
		if clicker and clicker:is_player() then C.show_text(clicker, S("Death at the Château: how to play"), RULES) end
	end,
})
