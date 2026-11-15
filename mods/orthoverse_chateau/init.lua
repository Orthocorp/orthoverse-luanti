-- Death at the Château: the château's blocks, its furniture, the weapons in
-- their places, the guests seated at dinner and Monsieur Lenoir's body. The
-- mystery itself (what a run draws, the clues, the casebook, Madame Or's
-- table and the accusation) is in mystery.lua.
--
-- Textures and sounds: tools/chateau/make_textures.py (CC BY-SA 3.0).

local S = core.get_translator("orthoverse_chateau")
local modpath = core.get_modpath("orthoverse_chateau")

orthoverse = orthoverse or {}
orthoverse.chateau = {}
local C = orthoverse.chateau

local function tex(name) return "orthoverse_chateau_" .. name .. ".png" end
C.tex = tex

local SND = {
	wood = default and default.node_sound_wood_defaults() or nil,
	stone = default and default.node_sound_stone_defaults() or nil,
	glass = default and default.node_sound_glass_defaults() or nil,
	cloth = default and default.node_sound_leaves_defaults() or nil,
}

local function node(id, def)
	def.is_ground_content = false
	def.groups = def.groups or {cracky = 2}
	core.register_node("orthoverse_chateau:" .. id, def)
end

------------------------------------------------------------------------------
-- Walls, floors and the roof

for _, b in ipairs({
	{"parquet", "Parquet floor", {choppy = 2}, "wood"},
	{"marble_white", "White marble", {cracky = 2}, "stone"},
	{"marble_black", "Black marble", {cracky = 2}, "stone"},
	{"marble_rose", "Rose marble", {cracky = 2}, "stone"},
	{"panel", "White and gold panelling", {choppy = 2}, "wood"},
	{"panel_wood", "Mahogany panelling", {choppy = 2}, "wood"},
	{"stone", "Pale limestone", {cracky = 2}, "stone"},
	{"slate", "Roof slates", {cracky = 2}, "stone"},
	{"cornice", "Gilded cornice", {choppy = 2}, "wood"},
	{"ceiling", "Painted ceiling", {choppy = 2}, "wood"},
	{"damask_red", "Red silk damask", {choppy = 2}, "cloth"},
	{"damask_blue", "Blue silk damask", {choppy = 2}, "cloth"},
	{"damask_green", "Green silk damask", {choppy = 2}, "cloth"},
	{"carpet", "Carpet", {snappy = 2}, "cloth"},
	{"flagstone", "Flagstones", {cracky = 2}, "stone"},
	{"kitchen_tile", "Kitchen tiles", {cracky = 2}, "stone"},
}) do
	-- (the gilded cornice round every room's ceiling gives a soft light)
	node(b[1], {description = S(b[2]), tiles = {tex(b[1])}, groups = b[3], sounds = SND[b[4]],
		paramtype = b[1] == "cornice" and "light" or nil, light_source = b[1] == "cornice" and 9 or nil})
end

------------------------------------------------------------------------------
-- Shapes

-- Against a wall: a thin plate at the back of the block (facedir 0: the wall
-- is to the north, the face looks south)
local PLATE = {type = "fixed", fixed = {-0.5, -0.5, 0.4375, 0.5, 0.5, 0.5}}
local FLAT = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5}}

-- Something that hangs on a wall, its face (front) a texture
local function on_wall(id, desc, front, def)
	def = def or {}
	def.description = S(desc)
	def.drawtype = "nodebox"
	def.node_box = PLATE
	def.paramtype = "light"
	def.paramtype2 = "facedir"
	def.sunlight_propagates = true
	def.use_texture_alpha = "clip"
	def.tiles = def.tiles or {tex("panel"), tex("panel"), tex("panel"), tex("panel"), tex("panel"), front}
	def.groups = def.groups or {choppy = 2}
	def.sounds = def.sounds or SND.wood
	node(id, def)
end
C.on_wall = on_wall

-- Something standing on the floor or a table, drawn as crossed pictures
local function standing(id, desc, t, def)
	def = def or {}
	def.description = S(desc)
	def.drawtype = "plantlike"
	def.tiles = {t}
	def.inventory_image = t
	def.wield_image = t
	def.paramtype = "light"
	def.sunlight_propagates = true
	def.walkable = def.walkable or false
	def.selection_box = def.selection_box or {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, 0.3, 0.3}}
	def.groups = def.groups or {snappy = 3}
	node(id, def)
end
C.standing = standing

-- Something lying flat on the floor or a table
local function lying(id, desc, t, def)
	def = def or {}
	def.description = S(desc)
	def.drawtype = "nodebox"
	def.node_box = FLAT
	def.tiles = {t, "blank.png"}
	def.use_texture_alpha = "clip"
	def.inventory_image = t
	def.paramtype = "light"
	def.paramtype2 = "facedir"
	def.sunlight_propagates = true
	def.walkable = false
	def.groups = def.groups or {snappy = 3}
	node(id, def)
end
C.lying = lying

-- Mirrors and portraits
on_wall("mirror", "Gilded mirror", tex("mirror"))

C.PEOPLE = {
	{id = "comte", name = "Le Comte Richard d'Améthyste", colour = "purple",
		about = "Your host. Old nobility, an old name, and an old château that costs more each year than its vineyards bring in."},
	{id = "marquise", name = "La Marquise Céleste Vermeil", colour = "crimson",
		about = "Aristocratic and refined, with a fiery and dangerous reputation."},
	{id = "general", name = "Le Général Gaston Safran", colour = "saffron",
		about = "A loud military veteran, bold and blustering, with a fondness for the gaming tables."},
	{id = "ivoire", name = "Mademoiselle Geneviève Ivoire", colour = "ivory",
		about = "A poised concert pianist, elegant and composed, with a hidden edge."},
	{id = "emeraude", name = "Monsieur Lucien Émeraude", colour = "emerald",
		about = "A slick Parisian banker: sharp, modern and charming."},
	{id = "duc", name = "Le Duc Henri Azur", colour = "azure",
		about = "A duke of high rank and political prestige, with much to lose."},
	{id = "docteur", name = "Docteur Émile Cendre", colour = "grey",
		about = "A melancholy physician and poet, who carries his medical bag everywhere."},
	{id = "or", name = "Madame Solange Or", colour = "gold",
		about = "A glamorous and theatrical fortune-teller from Paris. Her cards are said never to lie."},
}
C.VICTIM = {id = "lenoir", name = "Monsieur Sébastien Lenoir", colour = "black",
	about = "A wealthy, reclusive art dealer and fixer from Paris, invited to broker a secret deal. Nearly every guest at the table had a reason to want him dead."}
C.person = {}
for _, p in ipairs(C.PEOPLE) do C.person[p.id] = p end
C.person.lenoir = C.VICTIM

for _, p in ipairs(C.PEOPLE) do
	on_wall("portrait_" .. p.id, "Portrait of " .. p.name, tex("portrait_" .. p.id),
		{tiles = {tex("panel"), tex("panel"), tex("panel"), tex("panel"), tex("panel"), tex("portrait_" .. p.id)},
		_person = p.id,
		on_rightclick = function(pos, _, clicker)
			if clicker and clicker:is_player() and C.portrait_text then
				C.show_text(clicker, p.name, C.portrait_text(pos, p.id))
			end
		end})
end
on_wall("portrait_lenoir", "Portrait of " .. C.VICTIM.name, tex("portrait_lenoir"))

-- Light
standing("chandelier", "Crystal chandelier", tex("chandelier"),
	{light_source = 14, visual_scale = 1.4, selection_box = {type = "fixed", fixed = {-0.4, -0.2, -0.4, 0.4, 0.5, 0.4}}})
standing("candles", "Candles", tex("candles"), {light_source = 10})

node("fireplace", {
	description = S("Marble fireplace"),
	tiles = {tex("fireplace_side"), tex("fireplace_side"), tex("fireplace_side"), tex("fireplace_side"),
		tex("fireplace_side"), tex("fireplace")},
	paramtype2 = "facedir", light_source = 11, groups = {cracky = 2}, sounds = SND.stone,
})

------------------------------------------------------------------------------
-- Furniture

local TABLE = {type = "fixed", fixed = {
	{-0.5, 0.375, -0.5, 0.5, 0.5, 0.5},
	{-0.45, -0.5, -0.45, -0.35, 0.375, -0.35}, {0.35, -0.5, -0.45, 0.45, 0.375, -0.35},
	{-0.45, -0.5, 0.35, -0.35, 0.375, 0.45}, {0.35, -0.5, 0.35, 0.45, 0.375, 0.45},
}}
local function table_node(id, desc, top, side, def)
	def = def or {}
	def.description = S(desc)
	def.drawtype = "nodebox"
	def.node_box = TABLE
	def.paramtype = "light"
	def.paramtype2 = "facedir"
	def.tiles = {top, side, side}
	def.groups = def.groups or {choppy = 2}
	def.sounds = SND.wood
	node(id, def)
end
C.table_node = table_node
table_node("dining_table", "Banquet table", tex("cloth"), tex("cloth"))
table_node("table", "Table", tex("table_top"), tex("table_side"))
table_node("desk", "Writing desk", tex("desk_top"), tex("desk_side"),
	{node_box = {type = "fixed", fixed = {{-0.5, 0.25, -0.5, 0.5, 0.5, 0.5}, {-0.5, -0.5, -0.5, -0.3, 0.25, 0.5},
		{0.3, -0.5, -0.5, 0.5, 0.25, 0.5}}}})
table_node("billiard_table", "Billiard table", tex("felt"), tex("billiard_side"),
	{node_box = {type = "fixed", fixed = {{-0.5, 0.125, -0.5, 0.5, 0.5, 0.5}, {-0.3, -0.5, -0.3, 0.3, 0.125, 0.3}}}})
table_node("fortune_table", "Madame Or's table", tex("fortune_top"), tex("fortune_side"),
	{node_box = {type = "fixed", fixed = {{-0.5, 0.25, -0.5, 0.5, 0.5, 0.5}, {-0.45, -0.5, -0.45, 0.45, 0.25, 0.45}}}})
table_node("accusation_desk", "The accusation", tex("accusation_top"), tex("desk_side"),
	{node_box = {type = "fixed", fixed = {{-0.5, 0.25, -0.5, 0.5, 0.5, 0.5}, {-0.4, -0.5, -0.4, 0.4, 0.25, 0.4}}}})

local CHAIR = {type = "fixed", fixed = {
	{-0.35, -0.05, -0.35, 0.35, 0.05, 0.35},
	{-0.35, 0.05, 0.25, 0.35, 0.75, 0.35},
	{-0.35, -0.5, -0.35, -0.25, -0.05, -0.25}, {0.25, -0.5, -0.35, 0.35, -0.05, -0.25},
	{-0.35, -0.5, 0.25, -0.25, -0.05, 0.35}, {0.25, -0.5, 0.25, 0.35, -0.05, 0.35},
}}
local function chair(id, desc, cloth, def)
	def = def or {}
	def.description = S(desc)
	def.drawtype = "nodebox"
	def.node_box = CHAIR
	def.selection_box = {type = "fixed", fixed = {-0.35, -0.5, -0.35, 0.35, 0.75, 0.35}}
	def.collision_box = {type = "fixed", fixed = {-0.35, -0.5, -0.35, 0.35, 0.05, 0.35}}
	def.paramtype = "light"
	def.paramtype2 = "facedir"
	def.tiles = {cloth, tex("table_side"), tex("table_side"), tex("table_side"), cloth, tex("table_side")}
	def.groups = def.groups or {choppy = 2}
	def.sounds = SND.wood
	node(id, def)
end
chair("chair", "Dining chair", tex("velvet_purple"))
node("armchair", {
	description = S("Velvet armchair"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.45, -0.5, -0.45, 0.45, 0.05, 0.45}, {-0.45, 0.05, 0.25, 0.45, 0.6, 0.45},
		{-0.45, 0.05, -0.45, -0.3, 0.3, 0.25}, {0.3, 0.05, -0.45, 0.45, 0.3, 0.25}}},
	tiles = {tex("velvet_red")}, groups = {choppy = 2}, sounds = SND.wood,
})
node("piano", {
	description = S("Grand piano"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.5, 0, -0.5, 0.5, 0.5, 0.5}, {-0.45, -0.5, 0.35, -0.35, 0, 0.45},
		{0.35, -0.5, 0.35, 0.45, 0, 0.45}, {-0.45, -0.5, -0.45, -0.35, 0, -0.35}, {0.35, -0.5, -0.45, 0.45, 0, -0.35}}},
	tiles = {tex("piano_top"), tex("piano_top"), tex("piano_top"), tex("piano_top"), tex("piano_top"), tex("piano_keys")},
	groups = {choppy = 2}, sounds = SND.wood,
})
node("piano_body", {
	description = S("Grand piano (its body)"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.5, 0, -0.5, 0.5, 0.5, 0.5}, {-0.1, -0.5, -0.1, 0.1, 0, 0.1}}},
	tiles = {tex("piano_top")}, groups = {choppy = 2}, sounds = SND.wood,
})
node("bench", {
	description = S("Piano bench"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.45, -0.1, -0.3, 0.45, 0.1, 0.3}, {-0.4, -0.5, -0.25, -0.3, -0.1, 0.25},
		{0.3, -0.5, -0.25, 0.4, -0.1, 0.25}}},
	tiles = {tex("velvet_blue"), tex("piano_top")}, groups = {choppy = 2}, sounds = SND.wood,
})
standing("harp", "Harp", tex("harp"), {visual_scale = 1.6})
node("barrel", {
	description = S("Barrel"), tiles = {tex("barrel_top"), tex("barrel_top"), tex("barrel_side")},
	paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.wood,
})
node("wine_rack", {description = S("Wine rack"), tiles = {tex("table_side"), tex("table_side"), tex("wine_rack")},
	paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.wood})
on_wall("copper", "Copper pans", tex("copper"))
node("oven", {
	description = S("Bread oven"), tiles = {tex("flagstone"), tex("flagstone"), tex("flagstone"), tex("flagstone"),
		tex("flagstone"), tex("oven")}, paramtype2 = "facedir", light_source = 8, groups = {cracky = 2}, sounds = SND.stone,
})
node("drawers", {
	description = S("Chest of drawers"), tiles = {tex("table_top"), tex("table_top"), tex("desk_side"), tex("desk_side"),
		tex("desk_side"), tex("drawers")}, paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.wood,
})
node("clock", {
	description = S("Long-case clock"), tiles = {tex("panel_wood"), tex("panel_wood"), tex("panel_wood"),
		tex("panel_wood"), tex("panel_wood"), tex("clock")}, paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.wood,
})
node("bed", {
	description = S("Bed"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.5, -0.5, -0.5, 0.5, 0.0, 0.5}}},
	tiles = {tex("bed_cover"), tex("table_side"), tex("table_side")}, groups = {choppy = 2}, sounds = SND.wood,
})
standing("ivy", "Ivy", tex("ivy"), {walkable = false, groups = {snappy = 3}, visual_scale = 1.2})
standing("goblet", "Crystal goblet", tex("goblet"))
lying("goblet_spilt", "A spilt goblet", tex("goblet_spilt"))
on_wall("curtain_plain", "Velvet curtain", tex("curtain_gone"))

-- The doors that stay shut: two halves, a plate across the middle of the block
local DOOR = {type = "fixed", fixed = {-0.5, -0.5, -0.0625, 0.5, 0.5, 0.0625}}
for _, half in ipairs({"low", "high"}) do
	node("door_" .. half, {
		description = S("A locked door"), drawtype = "nodebox", node_box = DOOR, paramtype = "light",
		paramtype2 = "facedir", tiles = {tex("panel"), tex("panel"), tex("panel"), tex("panel"), tex("door_" .. half),
			tex("door_" .. half)},
		groups = {choppy = 2}, sounds = SND.wood,
		on_rightclick = function(_, _, clicker)
			if clicker and clicker:is_player() then
				core.chat_send_player(clicker:get_player_name(), S("The door is locked."))
			end
		end,
	})
end

------------------------------------------------------------------------------
-- The weapons in their places (mystery.lua takes one or two away each run)
-- and the other things the mystery uses. Each "gone" form looks the same
-- place with the weapon missing.

C.WEAPONS = {
	{id = "chandelier", name = "Le Chandelier en Argent", short = "the silver candlestick",
		place = "orthoverse_chateau:candlestick", gone = "orthoverse_chateau:candlestick_gone"},
	{id = "coupe_papier", name = "Le Coupe-Papier en Ivoire", short = "the ivory letter opener",
		place = "orthoverse_chateau:letter_opener", gone = "orthoverse_chateau:letter_opener_gone"},
	{id = "belladone", name = "La Fiole de Belladone", short = "the vial of belladonna",
		place = "orthoverse_chateau:cabinet", gone = "orthoverse_chateau:cabinet_gone"},
	{id = "pistolet", name = "Le Pistolet de Duel", short = "the dueling pistol",
		place = "orthoverse_chateau:pistols", gone = "orthoverse_chateau:pistols_gone"},
	{id = "cordon", name = "Le Cordon de Velours", short = "the velvet curtain cord",
		place = "orthoverse_chateau:curtain", gone = "orthoverse_chateau:curtain_gone"},
	{id = "tisonnier", name = "Le Tisonnier en Fer Forgé", short = "the wrought-iron poker",
		place = "orthoverse_chateau:fire_irons", gone = "orthoverse_chateau:fire_irons_gone"},
}
C.weapon = {}
for _, w in ipairs(C.WEAPONS) do C.weapon[w.id] = w end

local function place_pair(w, make)
	make(w.place, false)
	make(w.gone, true)
end
place_pair(C.weapon.chandelier, function(name, gone)
	local id = name:match(":(.*)$")
	if gone then lying(id, "The candlestick's place", tex("dust_ring"), {_weapon = "chandelier", _gone = true})
	else standing(id, "Le Chandelier en Argent", tex("candlestick"), {_weapon = "chandelier", light_source = 6}) end
end)
place_pair(C.weapon.coupe_papier, function(name, gone)
	local id = name:match(":(.*)$")
	lying(id, gone and "The letter opener's place" or "Le Coupe-Papier en Ivoire", tex(gone and "papers" or "letter_opener"),
		{_weapon = "coupe_papier", _gone = gone or nil})
end)
place_pair(C.weapon.belladone, function(name, gone)
	local id = name:match(":(.*)$")
	node(id, {description = S(gone and "The apothecary cabinet" or "The apothecary cabinet (La Fiole de Belladone)"),
		tiles = {tex("table_top"), tex("table_top"), tex("table_side"), tex("table_side"), tex("table_side"),
			tex(gone and "cabinet_empty" or "cabinet")},
		paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.glass, _weapon = "belladone", _gone = gone or nil})
end)
place_pair(C.weapon.pistolet, function(name, gone)
	local id = name:match(":(.*)$")
	on_wall(id, gone and "The pistols' display" or "Les Pistolets de Duel", tex(gone and "pistols_gone" or "pistols"),
		{_weapon = "pistolet", _gone = gone or nil})
end)
place_pair(C.weapon.cordon, function(name, gone)
	local id = name:match(":(.*)$")
	on_wall(id, gone and "Velvet curtain (its cord gone)" or "Velvet curtain and its cord (Le Cordon de Velours)",
		tex(gone and "curtain_gone" or "curtain"), {_weapon = "cordon", _gone = gone or nil})
end)
place_pair(C.weapon.tisonnier, function(name, gone)
	local id = name:match(":(.*)$")
	standing(id, gone and "The fire irons (the poker gone)" or "The fire irons and Le Tisonnier en Fer Forgé",
		tex(gone and "fire_irons_gone" or "fire_irons"), {_weapon = "tisonnier", _gone = gone or nil})
end)

C.ROOMS = {
	{id = "salon", name = "Le Grand Salon", en = "the drawing room"},
	{id = "bibliotheque", name = "La Bibliothèque", en = "the library"},
	{id = "salle_a_manger", name = "La Salle à Manger", en = "the dining room"},
	{id = "jardin", name = "Le Jardin d'Hiver", en = "the conservatory"},
	{id = "cave", name = "La Cave à Vin", en = "the wine cellar"},
	{id = "bureau", name = "Le Bureau du Comte", en = "the Comte's study"},
	{id = "musique", name = "La Salle de Musique", en = "the music room"},
	{id = "armes", name = "La Salle d'Armes", en = "the armoury and billiard room"},
	{id = "cuisine", name = "La Cuisine", en = "the kitchen"},
}
C.room = {}
for _, r in ipairs(C.ROOMS) do C.room[r.id] = r end

-- Places a clue may be found (mystery.lua fills them each run). Metadata:
-- spot (its name, for the casebook), room, gate (the puzzle in front of it,
-- if any)
local SPOT = {chateau_spot = 1, choppy = 2}
node("spot_drawers", {
	description = S("Chest of drawers"), tiles = {tex("table_top"), tex("table_top"), tex("desk_side"), tex("desk_side"),
		tex("desk_side"), tex("drawers")}, paramtype2 = "facedir", groups = SPOT, sounds = SND.wood,
})
lying("spot_papers", "Papers", tex("papers"), {groups = {chateau_spot = 1, snappy = 3}})
node("spot_barrel", {
	description = S("Barrel"), tiles = {tex("barrel_top"), tex("barrel_top"), tex("barrel_side")},
	paramtype2 = "facedir", groups = SPOT, sounds = SND.wood,
})
node("spot_box", {
	description = S("A casket"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {-0.3, -0.5, -0.2, 0.3, -0.1, 0.2}},
	tiles = {tex("desk_side")}, groups = SPOT, sounds = SND.wood,
})
node("spot_armchair", {
	description = S("Velvet armchair"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.45, -0.5, -0.45, 0.45, 0.05, 0.45}, {-0.45, 0.05, 0.25, 0.45, 0.6, 0.45},
		{-0.45, 0.05, -0.45, -0.3, 0.3, 0.25}, {0.3, 0.05, -0.45, 0.45, 0.3, 0.25}}},
	tiles = {tex("velvet_red")}, groups = SPOT, sounds = SND.wood,
})
node("spot_bench", {
	description = S("Piano bench"), drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
	node_box = {type = "fixed", fixed = {{-0.45, -0.1, -0.3, 0.45, 0.1, 0.3}, {-0.4, -0.5, -0.25, -0.3, -0.1, 0.25},
		{0.3, -0.5, -0.25, 0.4, -0.1, 0.25}}},
	tiles = {tex("velvet_blue"), tex("piano_top")}, groups = SPOT, sounds = SND.wood,
})
on_wall("safe", "Wall safe", tex("safe"), {groups = SPOT, sounds = SND.stone})
on_wall("safe_open", "Wall safe (open)", tex("safe_open"), {groups = SPOT, sounds = SND.stone})

-- Things that tell the player something fixed by the run (mystery.lua)
standing("music_stand", "Music stand", tex("music_stand"), {walkable = true,
	selection_box = {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, 0.4, 0.3}},
	collision_box = {type = "fixed", fixed = {-0.1, -0.5, -0.1, 0.1, 0.4, 0.1}}})
standing("menu_card", "Menu card", tex("menu_card"))
on_wall("keyhook", "Key hook", tex("keyhook"))
on_wall("keyhook_empty", "Key hook", tex("keyhook_empty"))
node("false_book", {
	description = S("Bookshelf"), tiles = {"default_wood.png", "default_wood.png", "default_wood.png",
		"default_wood.png", "default_wood.png", tex("false_book")}, paramtype2 = "facedir",
	groups = {choppy = 2}, sounds = SND.wood,
})
-- What the secret ways are shut with (opened in a run: mystery.lua)
node("shelf_door", {
	description = S("Bookshelf"), tiles = {"default_wood.png", "default_wood.png", "default_bookshelf.png"},
	paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.wood,
})
node("rack_door", {
	description = S("Wine rack"), tiles = {tex("table_side"), tex("table_side"), tex("wine_rack")},
	paramtype2 = "facedir", groups = {choppy = 2}, sounds = SND.wood,
})

------------------------------------------------------------------------------
-- The guests at the table, and the body: figures that do not move or speak,
-- set in place by the chair (or the rug) they belong to. The restore after a
-- run removes every creature in the area; the chair's timer sets its guest
-- back.

local SIT = {x = 81, y = 160}
local LAY = {x = 162, y = 166}

core.register_entity("orthoverse_chateau:figure", {
	initial_properties = {
		visual = "mesh", mesh = "character.b3d", textures = {tex("skin_comte")},
		visual_size = {x = 1, y = 1}, collisionbox = {-0.3, 0, -0.3, 0.3, 1.2, 0.3},
		selectionbox = {-0.3, 0, -0.3, 0.3, 1.2, 0.3},
		physical = false, pointable = true, static_save = false, makes_footstep_sound = false,
	},
	_who = "comte",
	on_activate = function(self, staticdata)
		local who, pose = (staticdata or ""):match("^(%w+):(%w+)$")
		if who and C.person[who] then self:set(who, pose) end
	end,
	set = function(self, who, pose)
		self._who, self._pose = who, pose
		local p = C.person[who]
		self.object:set_properties({textures = {tex("skin_" .. who)}, infotext = p.name,
			collisionbox = pose == "lay" and {-0.6, 0, -0.6, 0.6, 0.3, 0.6} or {-0.3, 0, -0.3, 0.3, 1.2, 0.3},
			selectionbox = pose == "lay" and {-0.6, 0, -0.6, 0.6, 0.3, 0.6} or {-0.3, 0, -0.3, 0.3, 1.2, 0.3}})
		self.object:set_animation(pose == "lay" and LAY or SIT, 0, 0, false)
	end,
	on_punch = function() return true end,
	on_rightclick = function(self, clicker)
		if not (clicker and clicker:is_player()) then return end
		local p = C.person[self._who]
		if self._pose == "lay" and C.body_text then
			C.show_text(clicker, p.name, C.body_text(self.object:get_pos()))
		else
			C.show_text(clicker, p.name, p.about)
		end
	end,
})

-- Facedir 0..3 to the yaw a figure faces (facedir 0: the chair's back to the
-- north, so the sitter faces south)
local YAW = {[0] = math.pi, [1] = math.pi / 2, [2] = 0, [3] = -math.pi / 2}

local function keep_figure(pos, who, pose)
	if not C.person[who] then return end
	local at = vector.offset(pos, 0, pose == "lay" and -0.45 or 0.05, 0)
	for _, obj in ipairs(core.get_objects_inside_radius(at, 0.6)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "orthoverse_chateau:figure" then return end
	end
	local obj = core.add_entity(at, "orthoverse_chateau:figure", who .. ":" .. pose)
	if obj then
		local ent = obj:get_luaentity()
		ent:set(who, pose)
		obj:set_yaw(YAW[core.get_node(pos).param2 % 4] or 0)
	end
end

chair("guest_chair", "A guest's chair", tex("velvet_purple"), {
	groups = {choppy = 2, orthoverse_timer = 1},
	on_construct = function(pos) core.get_node_timer(pos):start(1) end,
	on_timer = function(pos)
		keep_figure(pos, core.get_meta(pos):get_string("guest"), "sit")
		return true
	end,
	on_destruct = function(pos)
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.7)) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "orthoverse_chateau:figure" then obj:remove() end
		end
	end,
})
node("rug", {
	description = S("A rug (where Monsieur Lenoir lies)"), drawtype = "nodebox", node_box = FLAT,
	paramtype = "light", paramtype2 = "facedir", walkable = false, tiles = {tex("rug")},
	groups = {snappy = 3, orthoverse_timer = 1},
	on_construct = function(pos) core.get_node_timer(pos):start(1) end,
	on_timer = function(pos)
		keep_figure(pos, "lenoir", "lay")
		return true
	end,
	on_destruct = function(pos)
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.9)) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "orthoverse_chateau:figure" then obj:remove() end
		end
	end,
})

------------------------------------------------------------------------------
-- A page of text (a clue, a portrait, a card)

function C.show_text(player, title, text)
	local fs = "formspec_version[4]size[10,7.5]" ..
		"box[0,0;10,1;#3a2030]label[0.4,0.5;" .. core.formspec_escape(title) .. "]" ..
		"textarea[0.4,1.3;9.2,5.2;;;" .. core.formspec_escape(text or "") .. "]" ..
		"button_exit[3.5,6.6;3,0.7;ok;" .. S("Close") .. "]"
	core.show_formspec(player:get_player_name(), "orthoverse_chateau:text", fs)
end

dofile(modpath .. "/mystery.lua")
