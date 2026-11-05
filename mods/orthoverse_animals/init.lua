-- orthoverse_animals: fits Animalia (mods/animals) to the Orthoverse.
--
-- Animalia picks each animal's spawning places by biome group, worked out from
-- the registered biomes. The Orthoverse has one grassy temperate biome, which
-- falls into Animalia's "temperate", "grassland" and "urban" groups, so the
-- countryside animals spawn: cows, sheep, horses, pigs, chickens, cats, rats,
-- songbirds and owls, bats underground and tropical fish in the sea.
--
-- The forest animals (grizzly bear, fox, opossum, reindeer, turkey, wolf) belong
-- to the "boreal" group, which is empty here. Creatura treats an empty biome list
-- as "anywhere", so they would spawn on every land, and bears on every beach.
-- Unless orthoverse_forest_animals is true, the group gets a placeholder biome
-- that does not exist, so they do not spawn by themselves (they can still be
-- placed or spawned by an admin).

if not core.get_modpath("animalia") then
	return
end

if core.settings:get_bool("orthoverse_forest_animals", false) then
	return
end

-- After Animalia has sorted the biomes into groups (this mod loads after it)
core.register_on_mods_loaded(function()
	local group = animalia.registered_biome_groups and animalia.registered_biome_groups.boreal
	if group and #group.biomes == 0 then
		-- Creatura matches a listed name that starts with the current biome's
		-- name, so the placeholder must not start with "orthoverse"
		table.insert(group.biomes, "no_forest_floor_here")
		core.log("action", "[orthoverse_animals] forest animals do not spawn by themselves")
	end
end)
