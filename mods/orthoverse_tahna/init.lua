-- The Tomb of Tahna: a mummy queen's tomb under the desert, three levels
-- deep (tools/adventures/tahna.lua builds it). Its blocks, traps and
-- treasure, all in the Creative tab for builders too:
--
-- * Walls of carved signs, sandstone blocks, gold tiles, scorched stone.
-- * Paintings (two blocks by two) and tablets of carved signs: right-click
--   a tablet and the glyphs are read out. The clues to the traps are in them.
-- * Traps, sprung by a plate in the floor (each once a run) or by touch:
--     the falling ceiling: its plate brings the ceiling within reach down
--       over the room, a layer every half second, then lifts it again;
--       whoever is still under it when it comes low takes 30;
--     flame jets: plates among gold tiles; a plate sets the nozzles near it
--       roaring across the hall (30 to whoever is in a jet's path);
--     darts: the dart holes near the plate shoot across the corridor, in
--       volleys (3 a dart, 18 at most to each player);
--     the pit: the false floor round the plate drops away, onto spikes;
--     the false door: touch it, and spears come up through the floor in
--       front of it (28);
--     the archway: walk through it and you are back at the level's start
--       (the nearest "return" mark).
--   Damage is set straight on health (armour does not help).
-- * The endless passage: floor that quietly sets players back along it.
-- * False walls: look like the wall beside them, and can be walked through.
-- * The pyramid's trap: its empty sarcophagus, opened, seals the doorway
--   with a slab and wakes two mummies; a lever opens the slab again.
-- * Tahna's three canopic jars: struck, they break. While any is whole,
--   Tahna (orthoverse_monsters) rises again when struck down.
-- * Her sarcophagus: shut until she is slain, then open; its finish gives
--   each player the Sceptre of Tahna (once a character, ever: treasure, so
--   it comes out with them) and completes the adventure.
--
-- Textures and sounds: tools/tahna/make_textures.py (CC BY-SA 3.0).

local S = core.get_translator("orthoverse_tahna")

orthoverse = orthoverse or {}
orthoverse.tahna = {}
local T = orthoverse.tahna

local function tex(name) return "orthoverse_tahna_" .. name .. ".png" end
local SND = {
	stone = default and default.node_sound_stone_defaults() or nil,
	wood = default and default.node_sound_wood_defaults() or nil,
	glass = default and default.node_sound_glass_defaults() or nil,
	sand = default and default.node_sound_sand_defaults() or nil,
}

local function now() return core.get_us_time() / 1e6 end

------------------------------------------------------------------------------
-- The run

local function adventure(pos)
	local ad = orthoverse.adventure
	if not (ad and ad.at) then return end
	local key, def = ad.at(pos)
	if not key then return end
	return key, def, ad.runs and ad.runs[key]
end

local function data(run)
	run.tahna = run.tahna or {broken = 0, fired = {}, slain = false}
	return run.tahna
end

local function in_run(player, pos)
	if not (player and player:is_player()) then return end
	local key, def, run = adventure(pos or player:get_pos())
	if run and run.members[player:get_player_name()] then return key, def, run end
end

local function tell(run, text)
	for n in pairs(run.members) do core.chat_send_player(n, text) end
end

local function area(def)
	local a, b = def.corner1, def.corner2
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

local function hurt(player, dmg, why)
	if player:get_hp() <= 0 then return end
	player:set_hp(player:get_hp() - dmg, {type = "set_hp", from = "mod", orthoverse_trap = why})
end

local function sound(name, pos, gain, dist)
	core.sound_play("orthoverse_tahna_" .. name, {pos = pos, gain = gain or 1, max_hear_distance = dist or 24}, true)
end

local function near(pos, r, names)
	return core.find_nodes_in_area(vector.offset(pos, -r, -r, -r), vector.offset(pos, r, r, r), names)
end

------------------------------------------------------------------------------
-- The blocks

local function block(id, desc, def)
	def.description = desc
	def.groups = def.groups or {cracky = 2}
	def.sounds = def.sounds or SND.stone
	def.is_ground_content = false
	core.register_node("orthoverse_tahna:" .. id, def)
end

block("glyphs", S("Wall of carved signs"), {tiles = {tex("sandstone_block"), tex("sandstone_block"), tex("glyphs")}})
block("sandstone_block", S("Tomb sandstone"), {tiles = {tex("sandstone_block")}})
block("gold_tile", S("Gold tile"), {tiles = {tex("gold_tile")}, light_source = 3})
block("scorched", S("Scorched stone"), {tiles = {tex("scorched")}})
block("flag", S("Floor flag"), {tiles = {tex("flag")}})
block("dart_hole", S("Dart hole (a dart trap's: the side with the hole shoots)"), {
	tiles = {"default_cobble.png", "default_cobble.png", "default_cobble.png", "default_cobble.png",
		"default_cobble.png", tex("dart_hole")}, paramtype2 = "facedir"})
block("nozzle", S("Flame jet (the side with the mouth roars)"), {
	tiles = {"default_cobble.png", "default_cobble.png", "default_cobble.png", "default_cobble.png",
		"default_cobble.png", tex("nozzle")}, paramtype2 = "facedir"})
block("crusher", S("Falling ceiling (its plate brings it down)"), {tiles = {tex("crusher")}})
block("arch_eye", S("Carved eye (an archway's lintel)"), {tiles = {tex("sandstone_block"), tex("sandstone_block"),
	tex("arch_eye")}, paramtype2 = "facedir"})
block("slab", S("Stone slab (seals a doorway)"), {tiles = {tex("slab")}})
block("pedestal", S("Pedestal"), {
	drawtype = "nodebox", paramtype = "light",
	node_box = {type = "fixed", fixed = {{-0.4, -0.5, -0.4, 0.4, 0.5, 0.4}, {-0.5, 0.35, -0.5, 0.5, 0.5, 0.5},
		{-0.5, -0.5, -0.5, 0.5, -0.35, 0.5}}},
	tiles = {tex("pedestal")}})

-- False walls: the look of a wall, nothing to it
for id, look in pairs({false_cobble = "default:cobble", false_mossy = "default:mossycobble",
		false_glyphs = "orthoverse_tahna:glyphs", false_sandstone = "orthoverse_tahna:sandstone_block",
		false_desert = "default:sandstone"}) do
	local lt = core.registered_nodes[look] and core.registered_nodes[look].tiles
	block(id, S("False wall (looks like @1; walk through it)", look), {
		tiles = lt or {"default_cobble.png"}, walkable = false, groups = {cracky = 2, not_in_creative_inventory = 0},
	})
end

-- Spikes at the bottom of a pit
block("spikes", S("Spikes"), {
	drawtype = "plantlike", tiles = {tex("spikes")}, paramtype = "light", sunlight_propagates = true,
	walkable = false, damage_per_second = 5, inventory_image = tex("spikes"),
	selection_box = {type = "fixed", fixed = {-0.4, -0.5, -0.4, 0.4, 0.1, 0.4}},
})

-- The plates: each looks like the floor round it (a careful eye sees the
-- crack in a flag)
local PLATES = {
	plate_crush = {S("Trap plate: the falling ceiling"), tex("flag_cracked")},
	plate_darts = {S("Trap plate: darts"), tex("flag_cracked")},
	plate_pit = {S("Trap plate: the pit (and false floor)"), tex("flag")},
	plate_flame = {S("Trap plate: flame jets"), tex("scorched")},
}
for id, p in pairs(PLATES) do
	block(id, p[1], {tiles = {p[2]}, groups = {cracky = 2, tahna_plate = 1}})
end
-- False floor: drops away when a pit's plate is stepped on
block("false_floor", S("False floor (drops away with a pit's plate)"), {tiles = {tex("flag")},
	groups = {cracky = 2, tahna_false_floor = 1}})

-- Marks for the archway's trap (invisible, nothing to them)
core.register_node("orthoverse_tahna:arch", {
	description = S("Archway's mark: walking into it sends a player to the nearest return mark"),
	drawtype = "airlike", paramtype = "light", sunlight_propagates = true, walkable = false,
	pointable = false, buildable_to = false, is_ground_content = false, inventory_image = tex("arch_eye"),
	groups = {not_in_creative_inventory = 0},
})
core.register_node("orthoverse_tahna:return", {
	description = S("Return mark (where an archway sends players back to)"),
	drawtype = "airlike", paramtype = "light", sunlight_propagates = true, walkable = false,
	pointable = false, buildable_to = false, is_ground_content = false, inventory_image = tex("flag"),
})
-- The endless passage's floor: stone brick to look at, but whoever treads on
-- it is set back along the passage (east: west by 24; west: east by 8), so
-- the passage seems to go on for ever
for id, d in pairs({loop_east = {S("east"), -24}, loop_west = {S("west"), 8}}) do
	block(id, S("Endless passage's floor (@1 end: sends players back along it)", d[1]), {
		tiles = {"default_stone_brick.png"}, _tahna_shift = d[2]})
end
-- Where the slab will fall (an open doorway until the pyramid's trap)
core.register_node("orthoverse_tahna:slab_open", {
	description = S("Slab's place (open until the trap seals it)"),
	drawtype = "airlike", paramtype = "light", sunlight_propagates = true, walkable = false,
	pointable = false, buildable_to = false, is_ground_content = false, inventory_image = tex("slab"),
})

-- Spears through the floor (the false door's): down, they are a floor tile
block("spear_floor", S("Spear floor (the false door's trap)"), {tiles = {tex("flag")}})
block("spears_up", S("Spears"), {
	drawtype = "plantlike", tiles = {tex("spikes")}, visual_scale = 1.6, paramtype = "light",
	walkable = false, damage_per_second = 4, groups = {cracky = 2, not_in_creative_inventory = 1},
})

------------------------------------------------------------------------------
-- Paintings and tablets

local FRESCOES = {
	sphinx = S("A painting: the sphinx in the sand, and a door between its paws"),
	ceiling = S("A painting: the ceiling of a room coming down, one crushed beneath it, one running out"),
	gold = S("A painting: a figure stepping on gold among flames"),
	jars = S("A painting: the queen on her throne, three jars before her"),
	spears = S("A painting: a door, and spears coming up through the floor before it"),
}
for name, desc in pairs(FRESCOES) do
	for i = 1, 4 do
		block("fresco_" .. name .. "_" .. i, desc, {
			drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", sunlight_propagates = true,
			node_box = {type = "fixed", fixed = {-0.5, -0.5, 0.4375, 0.5, 0.5, 0.5}},
			tiles = {tex("sandstone_block"), tex("sandstone_block"), tex("sandstone_block"), tex("sandstone_block"),
				tex("sandstone_block"), tex("fresco_" .. name .. "_" .. i)},
			groups = {cracky = 2, not_in_creative_inventory = i == 1 and 0 or 1},
			after_place_node = function(pos) core.get_meta(pos):set_string("infotext", desc) end,
			on_construct = function(pos) core.get_meta(pos):set_string("infotext", desc) end,
		})
	end
end

block("tablet", S("Tablet of carved signs (right-click to read; the builder sets its words)"), {
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {-0.45, -0.45, 0.375, 0.45, 0.45, 0.5}},
	tiles = {tex("sandstone_block"), tex("sandstone_block"), tex("sandstone_block"), tex("sandstone_block"),
		tex("sandstone_block"), tex("glyphs") .. "^[colorize:#7a5a20:40"},
	on_construct = function(pos) core.get_meta(pos):set_string("infotext", S("Carved signs")) end,
	on_rightclick = function(pos, node, clicker)
		if not (clicker and clicker:is_player()) then return end
		local text = core.get_meta(pos):get_string("text")
		if text == "" then text = S("The signs are worn away.") end
		core.show_formspec(clicker:get_player_name(), "orthoverse_tahna:tablet",
			"formspec_version[4]size[9,5.2]box[0,0;9,0.9;#5a3a14]label[0.4,0.45;" ..
			core.formspec_escape(S("The carved signs say:")) .. "]textarea[0.4,1.2;8.2,3;;;" ..
			core.formspec_escape(text) .. "]button_exit[3,4.3;3,0.7;ok;" .. S("Close") .. "]")
	end,
})

------------------------------------------------------------------------------
-- The canopic jars

local JARS = {jackal = S("her heart"), falcon = S("her breath"), woman = S("her name")}
for lid, holds in pairs(JARS) do
	block("jar_" .. lid, S("Canopic jar (holds @1; strike it to break it)", holds), {
		drawtype = "nodebox", paramtype = "light", sunlight_propagates = true,
		node_box = {type = "fixed", fixed = {{-0.3, -0.5, -0.3, 0.3, 0.2, 0.3}, {-0.22, 0.2, -0.22, 0.22, 0.5, 0.22}}},
		tiles = {tex("jar_top"), tex("jar_top"), tex("jar_" .. lid)},
		groups = {cracky = 3, tahna_jar = 1},
		on_construct = function(pos) core.get_meta(pos):set_string("infotext", S("A canopic jar")) end,
		on_punch = function(pos, node, puncher)
			local key, def, run = in_run(puncher, pos)
			if not run then return end
			core.swap_node(pos, {name = "orthoverse_tahna:jar_broken"})
			core.get_meta(pos):set_string("infotext", S("A broken jar"))
			sound("jar", pos, 1, 24)
			core.add_particlespawner({amount = 30, time = 0.3, pos = vector.offset(pos, 0, 0.1, 0), radius = 0.3,
				vel = {min = {x = -2, y = 1, z = -2}, max = {x = 2, y = 3, z = 2}}, acc = {x = 0, y = -9, z = 0},
				exptime = {min = 0.5, max = 1}, size = {min = 1, max = 2}, texture = tex("shards")})
			core.add_particlespawner({amount = 25, time = 0.5, pos = vector.offset(pos, 0, 0.3, 0), radius = 0.2,
				vel = {min = {x = -0.3, y = 1, z = -0.3}, max = {x = 0.3, y = 2, z = 0.3}},
				exptime = {min = 1, max = 2}, size = {min = 3, max = 6}, texture = tex("dust") .. "^[colorize:#60ff90:120",
				glow = 8})
			local d = data(run)
			d.broken = d.broken + 1
			local left = 3 - d.broken
			tell(run, S("The jar that held @1 breaks, and something green goes out of it like a breath. Far below, " ..
				"someone cries out.", holds) .. (left > 0 and (" " .. S("(@1 jars left)", left)) or
				(" " .. S("(the last of them)"))))
		end,
	})
end
block("jar_broken", S("Broken canopic jar"), {
	drawtype = "nodebox", paramtype = "light", sunlight_propagates = true,
	node_box = {type = "fixed", fixed = {{-0.3, -0.5, -0.3, 0.3, -0.2, 0.3}, {-0.3, -0.2, -0.3, -0.1, 0.0, 0.3}}},
	tiles = {tex("jar_top"), tex("jar_top"), tex("jar_jackal")},
	groups = {cracky = 3, not_in_creative_inventory = 1},
})

function T.jars_broken(key)
	local run = key and orthoverse.adventure and orthoverse.adventure.runs[key]
	return run and math.min(3, data(run).broken) or 0
end

function T.struck_down(key, left)
	local run = key and orthoverse.adventure and orthoverse.adventure.runs[key]
	if not run then return end
	local d = data(run)
	if not d.told_jars then
		d.told_jars = true
		tell(run, S("Tahna falls to dust, but the dust stirs. Something of her is still kept safe."))
	end
end

function T.risen(key, left)
	local run = key and orthoverse.adventure and orthoverse.adventure.runs[key]
	if run then tell(run, S("Tahna rises again from the dust.")) end
end

------------------------------------------------------------------------------
-- The sarcophagus and the sceptre

local SCEPTRE_TAKEN = "orthoverse_tahna:sceptre"

core.register_craftitem("orthoverse_tahna:sceptre_carried", {
	description = S("The Sceptre of Tahna"), inventory_image = tex("sceptre"),
	groups = {not_in_creative_inventory = 1},
})

-- The sceptre: a trophy, to be set up and shown (it stands like a torch)
core.register_node("orthoverse_tahna:sceptre", {
	description = S("The Sceptre of Tahna") .. "\n" .. S("Taken from the tomb of the mummy queen. It can be set up for show."),
	drawtype = "plantlike", tiles = {tex("sceptre")}, inventory_image = tex("sceptre"), wield_image = tex("sceptre"),
	paramtype = "light", sunlight_propagates = true, walkable = false, light_source = 5,
	selection_box = {type = "fixed", fixed = {-0.25, -0.5, -0.25, 0.25, 0.5, 0.25}},
	stack_max = 1, groups = {dig_immediate = 3, attached_node = 1}, sounds = SND.stone, is_ground_content = false,
})

local SARC_BOX = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.3, 0.5}}

local function sarcophagus_touched(pos, player)
	if not (player and player:is_player()) then return end
	local name = player:get_player_name()
	local key, def, run = in_run(player, pos)
	if not run then return end
	if not data(run).slain then
		core.chat_send_player(name, S("The lid will not move while its queen still walks."))
		return
	end
	local meta = player:get_meta()
	if meta:get_string(SCEPTRE_TAKEN) == "" then
		local stack = ItemStack("orthoverse_tahna:sceptre")
		stack:get_meta():set_string("orthoverse_loot:found", "1")
		local left = player:get_inventory():add_item("main", stack)
		if left:is_empty() then
			meta:set_string(SCEPTRE_TAKEN, "1")
			core.chat_send_player(name, S("You lift the Sceptre of Tahna out of her sarcophagus."))
		else
			core.chat_send_player(name, S("Your pack is full: make room for the sceptre."))
			return
		end
	else
		core.chat_send_player(name, S("You have taken her sceptre before: the sarcophagus is empty for you."))
	end
	local ad = orthoverse.adventure
	if ad and ad.at_finish then ad.at_finish(pos, player) end
end

block("sarcophagus", S("Tahna's sarcophagus (the finish: open once she is slain)"), {
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", node_box = SARC_BOX,
	tiles = {tex("sarc_lid"), tex("sarc_side"), tex("sarc_side")},
	on_construct = function(pos) core.get_meta(pos):set_string("infotext", S("A great sarcophagus, shut")) end,
	on_rightclick = function(pos, node, clicker) sarcophagus_touched(pos, clicker) end,
	on_punch = function(pos, node, puncher) sarcophagus_touched(pos, puncher) end,
})
block("sarcophagus_open", S("Tahna's sarcophagus, open"), {
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", node_box = SARC_BOX,
	tiles = {tex("sarc_open"), tex("sarc_side"), tex("sarc_side")}, light_source = 6,
	groups = {cracky = 2, not_in_creative_inventory = 1},
	on_rightclick = function(pos, node, clicker) sarcophagus_touched(pos, clicker) end,
	on_punch = function(pos, node, puncher) sarcophagus_touched(pos, puncher) end,
})

function T.slain(key, pos)
	local ad = orthoverse.adventure
	local run = key and ad and ad.runs[key]
	local def = key and ad and ad.list[key]
	if not (run and def) then return end
	local d = data(run)
	d.slain = true
	local p1, p2 = area(def)
	for _, p in ipairs(core.find_nodes_in_area(p1, p2, {"orthoverse_tahna:sarcophagus"})) do
		core.swap_node(p, {name = "orthoverse_tahna:sarcophagus_open", param2 = core.get_node(p).param2})
		core.get_meta(p):set_string("infotext", S("The sarcophagus, open: the sceptre lies inside"))
		sound("sarcophagus", p, 1, 40)
	end
	tell(run, S("Tahna falls to dust, and this time the dust is still. Her sarcophagus grinds open."))
end

-- The pyramid's sarcophagus: empty, and a trap
local function decoy_touched(pos, player)
	local key, def, run = in_run(player, pos)
	if not run then return end
	local d = data(run)
	local id = "decoy" .. core.pos_to_string(pos)
	if d.fired[id] then
		core.chat_send_player(player:get_player_name(), S("The sarcophagus is empty."))
		return
	end
	d.fired[id] = true
	sound("sarcophagus", pos, 1, 32)
	core.swap_node(pos, {name = "orthoverse_tahna:decoy_open", param2 = core.get_node(pos).param2})
	core.after(0.8, function()
		for _, p in ipairs(near(pos, 14, {"orthoverse_tahna:slab_open"})) do
			core.set_node(p, {name = "orthoverse_tahna:slab"})
		end
		sound("grind", pos, 1, 32)
		local ms = orthoverse.monsters
		if ms and ms.spawn_at then ms.spawn_at(vector.offset(pos, 0, -1, 0), "orthoverse_monsters:mummy", 2,
			"run:" .. run.started, key) end
		tell(run, S("The sarcophagus is empty. Behind you stone grinds on stone, and the way out is shut. " ..
			"Something in the corners begins to move."))
	end)
end

block("decoy", S("An empty sarcophagus (the pyramid's trap: opened, it seals the doorway and wakes the dead)"), {
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", node_box = SARC_BOX,
	tiles = {tex("sarc_lid"), tex("sarc_side"), tex("sarc_side")},
	on_rightclick = function(pos, node, clicker) decoy_touched(pos, clicker) end,
})
block("decoy_open", S("An empty sarcophagus, open"), {
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", node_box = SARC_BOX,
	tiles = {tex("sarc_open"), tex("sarc_side"), tex("sarc_side")}, groups = {cracky = 2, not_in_creative_inventory = 1},
})

block("lever", S("Lever (opens the slabs near it)"), {
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.25, -0.35, 0.375, 0.25, 0.35, 0.5}, {-0.06, -0.1, 0.0, 0.06, 0.4, 0.375}}},
	tiles = {tex("bronze")}, inventory_image = tex("lever"),
	on_rightclick = function(pos, node, clicker)
		local key, def, run = in_run(clicker, pos)
		if not run then return end
		local slabs = near(pos, 14, {"orthoverse_tahna:slab"})
		for _, p in ipairs(slabs) do core.set_node(p, {name = "orthoverse_tahna:slab_open"}) end
		if #slabs > 0 then
			sound("grind", pos, 1, 32)
			core.chat_send_player(clicker:get_player_name(), S("The lever drags down, and the slab grinds up again."))
		end
	end,
})

------------------------------------------------------------------------------
-- The traps

local function once(run, kind, pos)
	local d = data(run)
	local id = kind .. core.pos_to_string(pos)
	if d.fired[id] then return false end
	d.fired[id] = true
	return true
end

-- Players of the run inside a box
local function players_in(run, p1, p2)
	local out = {}
	for n in pairs(run.members) do
		local pl = core.get_player_by_name(n)
		local p = pl and pl:get_pos()
		if p and p.x >= p1.x - 0.5 and p.x <= p2.x + 0.5 and p.z >= p1.z - 0.5 and p.z <= p2.z + 0.5
				and p.y >= p1.y - 0.5 and p.y <= p2.y + 0.5 then
			out[#out + 1] = pl
		end
	end
	return out
end

-- The falling ceiling: every crusher block within reach of the plate moves
-- down a block every half second until the room is two blocks high (anyone
-- still under it takes the blow), then one more, then it lifts back up
local CRUSH = {reach = 10, delay = 1.0, step = 0.5, damage = 30, hold = 3}

local function crush(pos, key, run)
	local blocks = near(pos, CRUSH.reach, {"orthoverse_tahna:crusher"})
	if #blocks == 0 then return end
	sound("grind", pos, 1, 32)
	tell(run, S("Somewhere above, stone begins to grind."))
	local floor = pos.y
	local low = math.huge
	local x1, x2, z1, z2 = math.huge, -math.huge, math.huge, -math.huge
	for _, b in ipairs(blocks) do
		low = math.min(low, b.y)
		x1, x2, z1, z2 = math.min(x1, b.x), math.max(x2, b.x), math.min(z1, b.z), math.max(z2, b.z)
	end
	local drop = 0
	local hit = {}
	local function move(dir)
		-- the layer of crushers moves by one (down: -1, up: +1), lowest first
		-- going down, highest first going up
		table.sort(blocks, function(a, b) if dir < 0 then return a.y < b.y else return a.y > b.y end end)
		local moved = {}
		for _, b in ipairs(blocks) do
			local to = vector.offset(b, 0, dir, 0)
			local nn = core.get_node(to).name
			if nn == "air" or nn == "orthoverse_tahna:crusher" then
				core.set_node(to, {name = "orthoverse_tahna:crusher"})
				core.set_node(b, {name = "air"})
				moved[#moved + 1] = to
			else
				moved[#moved + 1] = b
			end
		end
		blocks = moved
	end
	local function down()
		if orthoverse.adventure.runs[key] ~= run then return end
		move(-1)
		drop = drop + 1
		local bottom = low - drop
		if bottom - floor <= 2 then
			for _, pl in ipairs(players_in(run, vector.new(x1, floor, z1), vector.new(x2, bottom, z2))) do
				local n = pl:get_player_name()
				if not hit[n] then
					hit[n] = true
					hurt(pl, CRUSH.damage, "crusher")
					core.chat_send_player(n, S("The ceiling comes down on you."))
				end
			end
		end
		if bottom - floor > 1 then
			core.after(CRUSH.step, down)
		else
			-- down: hold, then lift back to where it was
			core.after(CRUSH.hold, function()
				local function up()
					if orthoverse.adventure.runs[key] ~= run or drop <= 0 then return end
					move(1)
					drop = drop - 1
					core.after(CRUSH.step, up)
				end
				sound("grind", pos, 0.8, 32)
				up()
			end)
		end
	end
	core.after(CRUSH.delay, down)
end

-- Darts: every dart hole within reach shoots, in volleys
local DARTS = {reach = 8, volleys = 3, gap = 0.5, damage = 3, speed = 16, most = 18}

core.register_entity("orthoverse_tahna:dart", {
	initial_properties = {
		visual = "sprite", textures = {tex("dart")}, visual_size = {x = 0.5, y = 0.5}, physical = false,
		pointable = false, static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_activate = function(self) self._born = now() end,
	on_step = function(self)
		local pos = self.object:get_pos()
		if not pos then return end
		if now() - self._born > 1.2 then self.object:remove(); return end
		-- (it flies a block or more a step: whoever is on the way since the
		-- last step is hit)
		local last = self._last or pos
		self._last = pos
		for hit in core.raycast(last, pos, true, false) do
			if hit.type == "object" and hit.ref:is_player() and hit.ref:get_hp() > 0 then
				-- (one trap's darts do at most so much to each player)
				local tally = self._tally or {}
				local n = hit.ref:get_player_name()
				local dmg = math.min(DARTS.damage, DARTS.most - (tally[n] or 0))
				if dmg > 0 then
					tally[n] = (tally[n] or 0) + dmg
					hurt(hit.ref, dmg, "dart")
				end
				self.object:remove()
				return
			end
		end
		local nd = core.registered_nodes[core.get_node(pos).name]
		if nd and nd.walkable and now() - self._born > 0.05 then self.object:remove(); return end
	end,
})

local function darts(pos, key, run)
	local holes = near(pos, DARTS.reach, {"orthoverse_tahna:dart_hole"})
	if #holes == 0 then return end
	local tally = {}
	for v = 0, DARTS.volleys - 1 do
		core.after(v * DARTS.gap + 0.2, function()
			if orthoverse.adventure.runs[key] ~= run then return end
			sound("darts", pos, 0.8, 16)
			for _, h in ipairs(holes) do
				-- the hole is on the node's front: facedir's "front" is -z
				-- for param2 0, the way the face looks
				local dir = vector.multiply(core.facedir_to_dir(core.get_node(h).param2), -1)
				local obj = core.add_entity(vector.add(h, vector.multiply(dir, 0.6)), "orthoverse_tahna:dart")
				if obj then
					obj:set_velocity(vector.multiply(dir, DARTS.speed))
					obj:get_luaentity()._tally = tally
				end
			end
		end)
	end
end

-- The pit: the false floor round the plate (and the plate) drop away
local function pit(pos, key, run)
	local floor = near(pos, 2, {"group:tahna_false_floor"})
	floor[#floor + 1] = pos
	for _, p in ipairs(floor) do core.set_node(p, {name = "air"}) end
	sound("grind", pos, 0.8, 16)
end

-- Flame jets: nozzles near the plate roar across the hall
local FLAME = {reach = 7, length = 6, damage = 30, secs = 1.4}

local function flames(pos, key, run)
	local nozzles = near(pos, FLAME.reach, {"orthoverse_tahna:nozzle"})
	if #nozzles == 0 then return end
	sound("flame", pos, 1, 24)
	local hit = {}
	for _, nzl in ipairs(nozzles) do
		local dir = vector.multiply(core.facedir_to_dir(core.get_node(nzl).param2), -1)
		local a = vector.add(nzl, dir)
		local b = vector.add(nzl, vector.multiply(dir, FLAME.length))
		core.add_particlespawner({amount = 80, time = FLAME.secs, pos = {min = vector.offset(a, -0.3, -0.3, -0.3),
			max = vector.offset(a, 0.3, 0.3, 0.3)}, vel = {min = vector.multiply(dir, 8), max = vector.multiply(dir, 11)},
			exptime = {min = 0.4, max = 0.6}, size = {min = 4, max = 8}, texture = tex("flame"), glow = 14})
		local p1 = vector.new(math.min(a.x, b.x), math.min(a.y, b.y) - 1, math.min(a.z, b.z))
		local p2 = vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
		for _, pl in ipairs(players_in(run, p1, p2)) do
			local n = pl:get_player_name()
			if not hit[n] then
				hit[n] = true
				hurt(pl, FLAME.damage, "flame")
				core.chat_send_player(n, S("Fire roars out of the wall and over you."))
			end
		end
	end
end

local SPRUNG = {
	["orthoverse_tahna:plate_crush"] = crush,
	["orthoverse_tahna:plate_darts"] = darts,
	["orthoverse_tahna:plate_pit"] = pit,
	["orthoverse_tahna:plate_flame"] = flames,
}

-- The false door: spears
local SPEARS = {reach = 3, damage = 28, secs = 2.5}
block("false_door", S("A grand door (a false one: touched, spears come up through the floor before it)"), {
	tiles = {tex("sandstone_block"), tex("sandstone_block"), tex("sandstone_block"), tex("sandstone_block"),
		tex("sandstone_block"), tex("false_door")}, paramtype2 = "facedir",
	on_rightclick = function(pos, node, clicker)
		local key, def, run = in_run(clicker, pos)
		if not run then return end
		sound("spears", pos, 1, 20)
		local spots = near(pos, SPEARS.reach, {"orthoverse_tahna:spear_floor"})
		for _, p in ipairs(spots) do
			local above = vector.offset(p, 0, 1, 0)
			if core.get_node(above).name == "air" then core.set_node(above, {name = "orthoverse_tahna:spears_up"}) end
		end
		for _, pl in ipairs(players_in(run, vector.offset(pos, -SPEARS.reach, -2, -SPEARS.reach),
				vector.offset(pos, SPEARS.reach, 2, SPEARS.reach))) do
			local below = vector.round(vector.offset(pl:get_pos(), 0, -0.4, 0))
			if core.get_node(below).name == "orthoverse_tahna:spear_floor" then
				hurt(pl, SPEARS.damage, "spears")
				core.chat_send_player(pl:get_player_name(), S("Spears come up through the floor."))
			end
		end
		core.after(SPEARS.secs, function()
			for _, p in ipairs(near(pos, SPEARS.reach + 1, {"orthoverse_tahna:spears_up"})) do core.remove_node(p) end
		end)
	end,
})

-- Every fifth of a second: what each player in a run stands on, or walks into
local last_teleport = {}
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.2 then return end
	timer = 0
	local ad = orthoverse.adventure
	if not (ad and ad.runs) then return end
	for key, run in pairs(ad.runs) do
		for n in pairs(run.members) do
			local pl = core.get_player_by_name(n)
			local p = pl and pl:get_pos()
			if p and pl:get_hp() > 0 then
				local feet = vector.round(vector.offset(p, 0, -0.6, 0))
				local fn = core.get_node(feet).name
				local fire = SPRUNG[fn]
				if fire and once(run, fn, feet) then fire(feet, key, run) end
				-- the endless passage: back along it, without a sign
				local shift = core.registered_nodes[fn] and core.registered_nodes[fn]._tahna_shift
				if shift then pl:set_pos(vector.offset(p, shift, 0, 0)) end
				-- the archway: back to the nearest return mark
				local body = vector.round(vector.offset(p, 0, 0.6, 0))
				if (core.get_node(body).name == "orthoverse_tahna:arch" or core.get_node(vector.round(p)).name == "orthoverse_tahna:arch")
						and now() - (last_teleport[n] or 0) > 2 then
					local marks = core.find_nodes_in_area(vector.offset(body, -64, -4, -64), vector.offset(body, 64, 4, 64),
						{"orthoverse_tahna:return"})
					local best, bd
					for _, m in ipairs(marks) do
						local d = vector.distance(m, body)
						if not bd or d < bd then best, bd = m, d end
					end
					if best then
						last_teleport[n] = now()
						sound("whoosh", p, 1, 12)
						pl:set_pos(vector.offset(best, 0, -0.45, 0))
						sound("whoosh", best, 1, 12)
						core.chat_send_player(n, S("The archway's eye seems to blink, and the passage turns about you."))
					end
				end
			end
		end
	end
end)

core.register_on_leaveplayer(function(player) last_teleport[player:get_player_name()] = nil end)
