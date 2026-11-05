-- orthoverse_nodes: placeholder nodes. Textures are recoloured Minetest Game
-- textures until the Orthoverse art pass replaces them.

core.register_node("orthoverse_nodes:world_edge", {
	description = "Edge of the Orthoverse",
	tiles = {"default_obsidian.png^[colorize:#101030:140"},
	is_ground_content = false,
	diggable = false,
	pointable = true,
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1},
	drop = "",
})

-- Henge portal stone, at the centre of each henge. It marks the spot and glows.
core.register_node("orthoverse_nodes:henge_portal", {
	description = "Henge Portal",
	tiles = {"default_meselamp.png^[colorize:#30c060:110"},
	light_source = 12,
	is_ground_content = false,
	diggable = false,
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1},
	drop = "",
})

-- Surface of the flipped (tarmac) realm.
core.register_node("orthoverse_nodes:tarmac", {
	description = "Tarmac",
	tiles = {"default_stone.png^[colorize:#1a1a1e:200"},
	is_ground_content = false,
	groups = {cracky = 2, stone = 1},
	sounds = default.node_sound_stone_defaults(),
})

-- The pane filling a henge gateway. Walking into the opening takes you to the
-- next henge (orthoverse_henges). One thin sheet in a plain colour: a pattern,
-- or several layers seen through each other, shimmers into moire as you move.
-- param2 0 spans east-west, 1 north-south.
core.register_node("orthoverse_nodes:henge_veil", {
	description = "Henge Gateway",
	drawtype = "nodebox",
	node_box = {type = "fixed", fixed = {-0.5, -0.5, -1/32, 0.5, 0.5, 1/32}},
	-- Only one face is drawn, seen from both sides; the box's thin edges and its
	-- back are left blank, or they show as lines between the blocks of a gateway
	tiles = {
		"[fill:1x1:#00000000", "[fill:1x1:#00000000", "[fill:1x1:#00000000", "[fill:1x1:#00000000",
		{name = "[fill:16x16:#4ee69a90", backface_culling = false},
		"[fill:1x1:#00000000",
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	light_source = 11,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	is_ground_content = false,
	post_effect_color = {a = 60, r = 78, g = 230, b = 154},
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1},
	drop = "",
})
