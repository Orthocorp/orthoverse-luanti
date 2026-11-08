-- orthoverse_animals: fits Animalia (mods/animals) to the Orthoverse.
--
-- Animalia picks each animal's spawning places by biome group, worked out from
-- the registered biomes. The Orthoverse has one grassy temperate biome, which
-- falls into Animalia's "temperate", "grassland" and "urban" groups, so the
-- countryside animals spawn: cows, sheep, horses, pigs, chickens, cats, rats,
-- songbirds and owls, bats underground and tropical fish in the sea.
--
-- The forest animals (fox, opossum, reindeer, turkey, wolf, grizzly bear)
-- belong to the "boreal" group, which is empty here. Creatura treats an empty
-- biome list as "anywhere", so left alone they would spawn on every land, and
-- bears (which Animalia spawns on sand) on every beach. So:
--   * with orthoverse_forest_animals (on by default), the Orthoverse biome joins
--     the group, and each forest animal only spawns with a tree trunk within a
--     few blocks: in the woods of the lands' wood tiles, not on open grass;
--   * grizzly bears attack players, so they also need orthoverse_bears (off by
--     default), and then spawn on soil in the woods instead of on sand;
--   * with orthoverse_forest_animals off, the group gets a placeholder biome
--     that does not exist, so none of them spawn by themselves.
-- Any of them can still be placed or spawned by an admin.

if not core.get_modpath("animalia") then
	return
end

local FOREST = core.settings:get_bool("orthoverse_forest_animals", true)
local BEARS = FOREST and core.settings:get_bool("orthoverse_bears", false)
local TREE_NEAR = 6         -- blocks from a tree trunk within which forest animals spawn

local forest_animals = {
	["animalia:fox"] = true,
	["animalia:opossum"] = true,
	["animalia:reindeer"] = true,
	["animalia:turkey"] = true,
	["animalia:wolf"] = true,
	["animalia:grizzly_bear"] = true,
}

-- After Animalia has sorted the biomes into groups (this mod loads after it),
-- and before the engine reads the ABMs
core.register_on_mods_loaded(function()
	local group = animalia.registered_biome_groups and animalia.registered_biome_groups.boreal
	if not group or #group.biomes > 0 then return end
	if not FOREST then
		-- Creatura matches a listed name that starts with the current biome's
		-- name, so the placeholder must not start with "orthoverse"
		table.insert(group.biomes, "no_forest_floor_here")
		core.log("action", "[orthoverse_animals] forest animals do not spawn by themselves")
		return
	end
	table.insert(group.biomes, "orthoverse")
	for _, abm in ipairs(core.registered_abms) do
		local mob = type(abm.label) == "string" and abm.label:match("^(%S+) spawning$")
		if mob and forest_animals[mob] then
			local action = abm.action
			if mob == "animalia:grizzly_bear" then
				abm.nodenames = {"group:soil"}
			end
			if mob == "animalia:grizzly_bear" and not BEARS then
				abm.action = function() end
			else
				abm.action = function(pos, ...)
					if core.find_node_near(pos, TREE_NEAR, "group:tree") then
						return action(pos, ...)
					end
				end
			end
		end
	end
	core.log("action", "[orthoverse_animals] forest animals spawn in the woods" ..
		(BEARS and ", bears included" or "; bears off"))
end)
