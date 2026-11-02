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

-- Henge portal stone. Teleporting comes later; for now it marks the spot and glows.
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
