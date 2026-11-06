-- orthoverse_minimap: every player has the minimap, shown when they join.
--
-- Minetest Game's map mod only allows the minimap to players carrying a
-- mapping kit (or in creative mode), checking every few seconds. It leaves
-- map.update_hud_flags open for overriding: here the minimap is always
-- allowed. The radar (which shows caves) stays as before: creative mode or the
-- "server" privilege only. On joining, the minimap is switched on; V still
-- cycles through the modes, and back to off.

local function radar_allowed(player)
	local name = player:get_player_name()
	return core.is_creative_enabled(name) or core.check_player_privs(name, {server = true})
end

function map.update_hud_flags(player)
	player:hud_set_flags({
		minimap = true,
		minimap_radar = radar_allowed(player),
	})
end

local SURFACE = {
	{type = "surface", label = "Minimap", size = 256},
	{type = "surface", label = "Minimap, close", size = 128},
	{type = "surface", label = "Minimap, wide", size = 512},
}

core.register_on_joinplayer(function(player)
	local modes = {}
	for _, m in ipairs(SURFACE) do modes[#modes + 1] = m end
	if radar_allowed(player) then
		modes[#modes + 1] = {type = "radar", label = "Radar", size = 128}
	end
	modes[#modes + 1] = {type = "off", label = "Minimap off"}
	-- Mode 0 (the first): the surface minimap, on
	player:set_minimap_modes(modes, 0)
	map.update_hud_flags(player)
end)
