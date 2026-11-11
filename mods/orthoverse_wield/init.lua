-- orthoverse_wield: what players hold, seen by others.
--
-- The engine shows a player only their own hand: to everyone else they are
-- empty-handed. Here each player carries a small model of the item in their
-- right hand (attached to the character model's right arm, as the monsters
-- carry their weapons), changed when they change what they hold, hidden when
-- the hand is empty.
--
-- And in a fight (orthoverse_combat calls orthoverse.wield.pose), the arm
-- shows the blow: raised while winding up (over the shoulder for a slash,
-- high overhead for a bash, drawn back for a thrust or a spear's jab), then
-- swung through for a moment on the release, then back to the arm's own
-- animation. So others can see a blow coming, as players see the monsters'.

orthoverse = orthoverse or {}
orthoverse.wield = {}

local CHECK_EVERY = 0.2
local SWING_FOR = 0.35            -- seconds the arm stays swung through
local d = math.rad

-- The right arm's rotation (character.b3d, radians, about x: 0 points straight
-- up, 90 back, 180 hangs down, 270 forward) for each blow and phase, and how
-- the hand grips the weapon: across the arm, as anyone holds a thing (and as
-- the monsters carry theirs), or along it, for a thrust's point to lead
local POSES = {
	slash = {windup = {x = d(30), y = 0, z = 0}, strike = {x = d(235), y = 0, z = 0}},
	bash = {windup = {x = d(10), y = 0, z = 0}, strike = {x = d(240), y = 0, z = 0}},
	thrust = {windup = {x = d(170), y = 0, z = 0}, strike = {x = d(270), y = 0, z = 0}, along = true},
	jab = {windup = {x = d(170), y = 0, z = 0}, strike = {x = d(272), y = 0, z = 0}, along = true},
}
local GRIP = {x = -90, y = 225, z = 90}
local GRIP_ALONG = {x = 90, y = 45, z = 90}
local HAND = {x = 0, y = 5.5, z = 3}


core.register_entity("orthoverse_wield:held", {
	initial_properties = {
		visual = "wielditem", wield_item = "air", visual_size = {x = 0.25, y = 0.25},
		physical = false, pointable = false, static_save = false, is_visible = false,
	},
	on_step = function(self)
		if not self.object:get_attach() then self.object:remove() end
	end,
})

local held = {}     -- name -> the object in their hand
local showing = {}  -- name -> the item it shows ("" for none)
local poses = {}    -- name -> {phase, till}
local guarding = {} -- name -> true while the shield is up
local pictures = {} -- name -> {id, texture}: the shield picture in their own view
local GUARD = {x = d(215), y = 0, z = 0}   -- the sword arm while the shield is up

local function item_of(player)
	local name = player:get_wielded_item():get_name()
	local def = core.registered_items[name]
	if name == "" or not def or def.type == "none" then return "" end
	return name
end

local function update(player)
	local name = player:get_player_name()
	local obj = held[name]
	if not (obj and obj:get_pos()) then
		obj = core.add_entity(player:get_pos(), "orthoverse_wield:held")
		if not obj then return end
		obj:set_attach(player, "Arm_Right", HAND, GRIP)
		held[name], showing[name] = obj, nil
	end
	local item = item_of(player)
	if showing[name] ~= item then
		showing[name] = item
		obj:set_properties({wield_item = item ~= "" and item or "air", is_visible = item ~= ""})
	end
end

-- The arm's pose for a blow: phase "windup" (until called again), "strike"
-- (for a moment), or nil (the arm's own animation again). `kind`: the
-- weapon's kind (slash, bash, thrust, jab).
function orthoverse.wield.pose(player, phase, kind)
	local name = player:get_player_name()
	local p = POSES[kind] or POSES.slash
	local obj = held[name]
	local along = phase == "strike" and p.along
	if obj and obj:get_pos() then obj:set_attach(player, "Arm_Right", HAND, along and GRIP_ALONG or GRIP) end
	if phase == nil then
		poses[name] = nil
		if guarding[name] ~= nil then
			player:set_bone_override("Arm_Right", {rotation = {vec = GUARD, absolute = true, interpolation = 0.15}})
		else
			player:set_bone_override("Arm_Right", {})
		end
		return
	end
	poses[name] = {phase = phase, till = phase == "strike" and core.get_us_time() / 1e6 + SWING_FOR or nil}
	player:set_bone_override("Arm_Right", {rotation = {vec = p[phase], absolute = true,
		interpolation = phase == "strike" and 0.08 or 0.25}})
end

-- The shield raised (the left arm across the front, forearm up), or lowered
-- again (orthoverse_combat's blocking). While it is up the sword arm is held
-- still at guard, forward and low: without that the engine plays its digging
-- animation for the held right button, and the arm swings to and fro. The
-- engine draws only the held item in the player's own first-person view, so
-- the player sees the raised shield as a picture at the bottom left of the
-- screen, sliding up into view quickly and down again more slowly. The
-- browser client draws a picture named "firstperson..." only in the
-- first-person view, so the third-person views show just the shield on the
-- character, and slides one named "firstperson_slide..." to a new offset
-- (web/client/patches/luanti-firstperson-hud.patch). The picture stays,
-- below the edge of the screen, while the shield is down.
local SHIELD_UP = {x = d(260), y = d(30), z = 0}
local PICTURE_UP, PICTURE_DOWN = 134, 270   -- its offset below the bottom of the screen

local function picture(player, material)
	local name = player:get_player_name()
	local texture = "shields_inv_shield_" .. (material or "steel") .. ".png^[opacity:230"
	local p = pictures[name]
	if not p then
		-- from the hotbar's middle leftwards, over its four left boxes
		local id = player:hud_add({
			type = "image", name = "firstperson_slide_shield", text = texture,
			position = {x = 0.5, y = 1}, alignment = {x = -1, y = -1},
			offset = {x = 0, y = PICTURE_DOWN}, scale = {x = 36, y = 16}, z_index = -50,
		})
		if not id then return end
		p = {id = id, texture = texture}
		pictures[name] = p
	elseif p.texture ~= texture then
		player:hud_change(p.id, "text", texture)
		p.texture = texture
	end
	return p
end

function orthoverse.wield.shield(player, up)
	local name = player:get_player_name()
	if up then
		player:set_bone_override("Arm_Left", {rotation = {vec = SHIELD_UP, absolute = true, interpolation = 0.15}})
		if not poses[name] then
			player:set_bone_override("Arm_Right", {rotation = {vec = GUARD, absolute = true, interpolation = 0.15}})
		end
		guarding[name] = true
		local p = picture(player, orthoverse.armor and orthoverse.armor.shield(player))
		if p then player:hud_change(p.id, "offset", {x = 0, y = PICTURE_UP}) end
	else
		player:set_bone_override("Arm_Left", {})
		if not poses[name] then player:set_bone_override("Arm_Right", {}) end
		guarding[name] = nil
		local p = pictures[name]
		if p then player:hud_change(p.id, "offset", {x = 0, y = PICTURE_DOWN}) end
	end
end

local since = 0
core.register_globalstep(function(dtime)
	since = since + dtime
	if since < CHECK_EVERY then return end
	since = 0
	local t = core.get_us_time() / 1e6
	for _, player in ipairs(core.get_connected_players()) do
		update(player)
		local name = player:get_player_name()
		local ps = poses[name]
		if ps and ps.till and t >= ps.till then orthoverse.wield.pose(player, nil) end
	end
end)

core.register_on_joinplayer(function(player)
	core.after(0.5, function() if player:get_pos() then update(player) end end)
	-- the shield picture, out of sight, ready to slide up
	core.after(1, function() if player:get_pos() then picture(player) end end)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	if held[name] and held[name]:get_pos() then held[name]:remove() end
	held[name], showing[name], poses[name], guarding[name], pictures[name] = nil, nil, nil, nil, nil
end)
