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

-- The shimmer filling a henge gateway. Walking into it takes you to the next
-- henge (orthoverse_henges); it has no substance and cannot be dug or built on.
core.register_node("orthoverse_nodes:henge_veil", {
	description = "Henge Gateway",
	drawtype = "glasslike",
	tiles = {"default_glass.png^[colorize:#30c060:160^[opacity:110"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 9,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	is_ground_content = false,
	post_effect_color = {a = 70, r = 48, g = 192, b = 96},
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1},
	drop = "",
})
