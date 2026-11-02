-- orthoverse_mapgen: the land generator runs in the engine's mapgen threads.
local modpath = core.get_modpath(core.get_current_modname())

-- One temperate biome everywhere. The land generator decides what the surface
-- looks like; without this, Minetest Game's climate biomes would put ice sheets,
-- snow and desert stone under arbitrary lands.
core.clear_registered_biomes()
core.register_biome({
	name = "orthoverse",
	node_top = "default:dirt_with_grass",
	depth_top = 1,
	node_filler = "default:dirt",
	depth_filler = 3,
	node_riverbed = "default:sand",
	depth_riverbed = 2,
	node_dungeon = "default:cobble",
	node_dungeon_alt = "default:mossycobble",
	node_dungeon_stair = "stairs:stair_cobble",
	node_cave_liquid = {"default:water_source", "default:lava_source"},
	y_max = 31000,
	y_min = -31000,
	heat_point = 50,
	humidity_point = 50,
})

core.register_mapgen_script(modpath .. "/mapgen.lua")

-- Sanity check: warn loudly if the world was created with the wrong map settings.
core.register_on_mods_loaded(function()
	local cs = tonumber(core.get_mapgen_setting("chunksize"))
	if cs ~= 6 then
		core.log("warning", "[orthoverse_mapgen] chunksize is " .. tostring(cs) ..
			", expected 6: lands will not line up with mapchunks")
	end
	if core.get_mapgen_setting("mg_name") ~= "flat" then
		core.log("warning", "[orthoverse_mapgen] mapgen is not 'flat'")
	end
end)
