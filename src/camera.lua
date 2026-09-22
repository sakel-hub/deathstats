--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local S = core.get_translator(core.get_current_modname())
local copy = table.copy
local atan2 = math.atan2 or math.atan
local VEC_ZERO = vector.new(0, 0, 0)
local CAMERA_PROBE_STEPS = { 0, 0.06 }
local safe_normalize = deathstats.safe_normalize

--- Register invisible camera anchor entity used to smoothly fly the player's camera
--- Luanti disables client-side player physics, gravity, and fall damage when attached to an entity
core.register_entity("deathstats:camera_anchor", {
    initial_properties = {
        visual = "sprite",
        textures = { "deathstats_transparent.png" },
        visual_size = { x = 0, y = 0, z = 0 },
        collisionbox = { 0, 0, 0, 0, 0, 0 },
        selectionbox = { 0, 0, 0, 0, 0, 0 },
        pointable = false,
        physical = false,
        collide_with_objects = false,
        use_texture_alpha = true,
        shaded = false,
        glow = 0,
        show_on_minimap = false,
        backface_culling = false,
        is_visible = false,
        static_save = false,
    },
    on_activate = function(self)
        if self.object then
            self.object:set_properties({
                is_visible = false,
                visual_size = { x = 0, y = 0, z = 0 },
                collisionbox = { 0, 0, 0, 0, 0, 0 },
                selectionbox = { 0, 0, 0, 0, 0, 0 },
                pointable = false,
                use_texture_alpha = true,
                show_on_minimap = false,
            })
            self.object:set_armor_groups({ immortal = 1 })
            if self.object.set_nametag_attributes then
                self.object:set_nametag_attributes({
                    text = "",
                    color = { a = 0, r = 0, g = 0, b = 0 },
                    bgcolor = { a = 0, r = 0, g = 0, b = 0 },
                })
            end
            if self.object.set_velocity then
                self.object:set_velocity(vector.zero())
            end
        end
    end,
})

--- Register zero-reach, non-pointable camera hand item used during death camera orbit
--- Ensures client shootline/raycast distance is 0, completely preventing node/object selection boxes
core.register_item("deathstats:camera_hand", {
    type = "none",
    range = 0,
    liquids_pointable = false,
    pointable = false,
    pointabilities = {
        nodes = {},
        objects = {},
    },
    wield_image = "deathstats_transparent.png",
    inventory_image = "deathstats_transparent.png",
    description = S("Death Camera Hand"),
    short_description = S("Death Camera Hand"),
    groups = { not_in_creative_inventory = 1 },
    tool_capabilities = {
        full_punch_interval = 999999,
        max_drop_level = 0,
        groupcaps = {},
        damage_groups = {},
    },
    on_use = function() return end,
    on_place = function() return end,
    on_secondary_use = function() return end,
    on_drop = function() return end,
})


deathstats.hooked_animations = {}

--- Wrap an animation function to prevent death animation looping while a player is dead
--- In Luanti Game (MTG) / Repixture, player_api.globalstep calls player_set_animation(player, "lay") every tick
--- which defaults to loop = true at 30 fps, causing a violent 0.13s death replay loop.
--- This hook forces loop = false and speed = 1 so the character cleanly stays in the final flat pose.
---@param mod_table table|nil The mod table containing the animation function
---@param fn_name string The name of the animation function
function deathstats.hook_animation_function(mod_table, fn_name)
    if mod_table and type(mod_table) == "table" and type(mod_table[fn_name]) == "function" and not deathstats.hooked_animations[mod_table[fn_name]] then
        local orig_fn = mod_table[fn_name]
        local hooked_fn = function(player, anim_name, speed, loop)
            if player and player:is_player() then
                local name = player:get_player_name()
                if not deathstats.is_player_online(name) then
                    return
                end
                if deathstats.dead_players[name] then
                    if anim_name == "lay" or anim_name == "die" then
                        return orig_fn(player, anim_name, 1, false)
                    end
                    return
                end
            end
            return orig_fn(player, anim_name, speed, loop)
        end
        deathstats.hooked_animations[hooked_fn] = true
        mod_table[fn_name] = hooked_fn
    end
end

-- Hook available player animation handlers once all mods have loaded
core.register_on_mods_loaded(function()
    deathstats.hook_animation_function(rawget(_G, "x_player_api"), "set_animation")
    deathstats.hook_animation_function(rawget(_G, "player_api"), "set_animation")
    deathstats.hook_animation_function(rawget(_G, "default"), "player_set_animation")
    deathstats.hook_animation_function(rawget(_G, "mcl_player"), "player_set_animation")
end)

--- Set or clear the player_attached flag in player_api / x_player_api and default mods
---@param name string The player name
---@param attached boolean|nil True if attached, nil to clear
function deathstats.set_engine_player_attached(name, attached)
    if not name or name == "" then return end
    local papi = rawget(_G, "x_player_api") or rawget(_G, "player_api")
    if papi and type(papi) == "table" and type(papi.player_attached) == "table" then
        papi.player_attached[name] = attached
    end
    local def_mod = rawget(_G, "default")
    if def_mod and type(def_mod) == "table" and type(def_mod.player_attached) == "table" then
        def_mod.player_attached[name] = attached
    end
end


--- Compute 3D camera eye coordinates along the orbit path around an orbit center
---@param center Vector 3D coordinates of the orbit center (corpse or bones)
---@param radius number Horizontal distance from center
---@param height number Vertical elevation above center
---@param angle number Orbit angle (yaw) in radians
---@return Vector cam_pos 3D world position of the camera eye
function deathstats.get_camera_orbit_pos(center, radius, height, angle)
    return vector.new(
        center.x + radius * math.sin(angle),
        center.y + height,
        center.z - radius * math.cos(angle)
    )
end

--- Update camera position and orientation along the circular orbit
---@param player ObjectRef The deceased player object
---@param dtime number Delta time in seconds since last frame
function deathstats.update_death_camera(player, dtime)
    if not deathstats.config.enable_camera or not player or not player:is_player() then return end
    local name = player:get_player_name()
    local data = deathstats.player_camera_data[name]
    if not data then return end

    -- Fallback / static camera handling if orbit_center is not set (e.g. mocked in tests or static orientation)
    if not data.orbit_center then
        if data.yaw and player.get_look_horizontal then
            local cur_yaw = player:get_look_horizontal()
            if not cur_yaw or math.abs(cur_yaw - data.yaw) > 0.05 then
                if player.set_look_horizontal then player:set_look_horizontal(data.yaw) end
            end
        end
        if data.pitch and player.get_look_vertical then
            local cur_pitch = player:get_look_vertical()
            if not cur_pitch or math.abs(cur_pitch - data.pitch) > 0.05 then
                if player.set_look_vertical then player:set_look_vertical(data.pitch) end
            end
        end
        return
    end

    -- Check for delayed bones placement if bones were not initially detected
    if not data.has_bones then
        local bones_pos = deathstats.find_player_bones(player)
        if bones_pos then
            data.has_bones = true
            data.bones_pos = bones_pos
            local new_center = bones_pos
            data.orbit_center = new_center
            -- When bones are placed, remove any corpse entity so bones block is visible
            if data.corpse then
                deathstats.remove_corpse(data.corpse)
                data.corpse = nil
            end
            if data.corpse_wielditem then
                if (not data.corpse_wielditem.is_valid or data.corpse_wielditem:is_valid()) and data.corpse_wielditem.remove then
                    data.corpse_wielditem:remove()
                end
                data.corpse_wielditem = nil
            end
            data.corpse_pos = nil
            data.corpse_visuals = nil
            local eff_r = data.eff_radius or data.orbit_radius or (deathstats.config.orbit_radius or 3.2)
            local eff_h = data.eff_height or (eff_r * (data.nominal_ratio or 0.46875))
            local cur_angle = data.orbit_angle or (data.yaw or 0)
            if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) then
                if data.anchor.set_velocity then
                    data.anchor:set_velocity(vector.zero())
                end
                if data.anchor.set_acceleration then
                    data.anchor:set_acceleration(vector.zero())
                end
                if data.anchor.move_to then
                    data.anchor:move_to(new_center, false)
                elseif data.anchor.set_pos then
                    data.anchor:set_pos(new_center)
                end
            end
            if player.set_detach then player:set_detach() end
            if player.set_pos then player:set_pos(new_center) end
            if data.anchor and player.set_attach then
                player:set_attach(data.anchor, "", vector.zero(), vector.zero(), false)
            end
            if player.set_eye_offset then
                player:set_eye_offset({ x = 0, y = eff_h * 10, z = -eff_r * 10 }, vector.zero())
                data.last_sent_eye_z = -eff_r * 10
                data.last_sent_eye_y = eff_h * 10
            end
            if player.set_look_horizontal then player:set_look_horizontal(cur_angle) end
            if player.set_look_vertical then player:set_look_vertical(atan2(eff_h, eff_r)) end
        end
    end

    -- Check if corpse needs to be spawned / re-spawned once mapblock is loaded
    local should_show_bones = deathstats.get_bones_mode()
    local bones_active = data.has_bones or (data.bones_pos ~= nil) or data.expect_bones or should_show_bones
    if not bones_active then
        if (not data.corpse or (data.corpse.is_valid and not data.corpse:is_valid())) and data.corpse_pos and data.corpse_visuals then
            local new_corpse = deathstats.spawn_and_setup_corpse(data.corpse_pos, data.corpse_visuals, player, data.death_info, data.last_blow)
            if new_corpse then
                data.corpse = new_corpse
                data.corpse_wielditem = deathstats.get_corpse_wielditem(new_corpse)
            end
            if deathstats.config.enable_corpse_particles ~= false and not data.particle_spawners then
                local effect_type = deathstats.get_corpse_effect_type(data.corpse_pos, data.death_info)
                if effect_type ~= "impact" then
                    data.particle_spawners = deathstats.spawn_corpse_particles(data.corpse_pos, data.death_info, data.corpse)
                    data.current_effect_type = effect_type
                    local c_ent = data.corpse and data.corpse.get_luaentity and data.corpse:get_luaentity()
                    local c_rot = (c_ent and c_ent._rot) or (data.corpse and data.corpse.get_rotation and data.corpse:get_rotation())
                    local r = (c_rot and c_rot.z) or 0
                    local p = (c_rot and c_rot.x) or 0
                    local is_p = (math.cos(r) * math.cos(p) < -0.5)
                    data.particles_were_prone = is_p
                    if c_ent then c_ent._particles_were_prone = is_p end
                end
            end
        end

        -- Transfer fatal arrow from player to corpse on first camera step (dtime > 0)
        -- after on_dieplayer and deferred x_bows core.after(0) attachments have executed
        if dtime and dtime > 0 and not data.arrows_transferred and data.corpse and (not data.corpse.is_valid or data.corpse:is_valid()) then
            data.arrows_transferred = true
            local xbows_loaded = rawget(_G, "XBows")
            if xbows_loaded and type(xbows_loaded.transfer_arrows_to_corpse) == "function" then
                xbows_loaded.transfer_arrows_to_corpse(player, data.corpse)
                deathstats.unhide_corpse_arrows(data.corpse)
            end
        end

        -- Dynamic corpse tracking: smoothly update orbit_center to follow the moving ragdoll corpse
        if data.corpse and (not data.corpse.is_valid or data.corpse:is_valid()) and data.corpse.get_pos then
            local cpos = data.corpse:get_pos()
            if cpos then
                local cvel = (data.corpse.get_velocity and data.corpse:get_velocity()) or vector.zero()
                local cacc = (data.corpse.get_acceleration and data.corpse:get_acceleration()) or vector.zero()
                local vel_len = vector.length(cvel)
                local pos_diff = data.orbit_center and vector.distance(cpos, data.orbit_center) or 0
                local luaent = data.corpse.get_luaentity and data.corpse:get_luaentity()
                local is_settled = (luaent and luaent._settled) or (vel_len < 0.05 and pos_diff < 0.02)

                if not is_settled then
                    -- Ragdoll corpse is actively moving/falling: translate orbit center and move anchor
                    data.corpse_settled = false
                    data.corpse_settled_particles_checked = false
                    data.corpse_pos = cpos
                    data.orbit_center = vector.new(cpos.x, cpos.y, cpos.z)
                    data.corpse_vel = cvel
                    data.corpse_acc = cacc

                    if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) then
                        if data.anchor.move_to then
                            data.anchor:move_to(data.orbit_center, false)
                        elseif data.anchor.set_pos then
                            data.anchor:set_pos(data.orbit_center)
                        end
                        if data.anchor.set_velocity then
                            data.anchor:set_velocity(cvel)
                        end
                        if data.anchor.set_acceleration then
                            data.anchor:set_acceleration(cacc)
                        end
                    end
                elseif not data.corpse_settled then
                    -- Ragdoll corpse has settled: lock final stationary position and zero out velocity once
                    data.corpse_settled = true
                    data.corpse_pos = cpos
                    data.orbit_center = vector.new(cpos.x, cpos.y, cpos.z)
                    data.corpse_vel = VEC_ZERO
                    data.corpse_acc = VEC_ZERO

                    if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) then
                        if data.anchor.set_velocity then
                            data.anchor:set_velocity(VEC_ZERO)
                        end
                        if data.anchor.set_acceleration then
                            data.anchor:set_acceleration(VEC_ZERO)
                        end
                        if data.anchor.set_pos then
                            data.anchor:set_pos(data.orbit_center)
                        end
                    end
                end
                -- When corpse_settled is true, anchor is NEVER touched: zero packets sent, 100% calm stationary scene node!

                -- Re-evaluate environment effect once corpse has settled
                if luaent and luaent._settled and not data.corpse_settled_particles_checked then
                    data.corpse_settled_particles_checked = true
                    if deathstats.config.enable_corpse_particles ~= false then
                        local settled_effect = deathstats.get_corpse_effect_type(cpos, data.death_info)
                        local current_effect = data.current_effect_type or deathstats.get_corpse_effect_type(data.initial_death_pos or cpos, data.death_info)
                        local has_active_spawners = data.particle_spawners and #data.particle_spawners > 0
                        local roll = (luaent._rot and luaent._rot.z) or (data.corpse and data.corpse.get_rotation and data.corpse:get_rotation().z) or 0
                        local pitch = (luaent._rot and luaent._rot.x) or (data.corpse and data.corpse.get_rotation and data.corpse:get_rotation().x) or 0
                        local uy = math.cos(roll) * math.cos(pitch)
                        local is_prone = (uy < -0.5)
                        local orientation_changed = (data.particles_were_prone ~= nil and data.particles_were_prone ~= is_prone)
                        if settled_effect ~= current_effect or not has_active_spawners or orientation_changed then
                            if data.particle_spawners then
                                for _, pid in ipairs(data.particle_spawners) do
                                    core.delete_particlespawner(pid)
                                end
                                data.particle_spawners = nil
                            end
                            if luaent._particle_spawners then
                                for _, pid in ipairs(luaent._particle_spawners) do
                                    core.delete_particlespawner(pid)
                                end
                                luaent._particle_spawners = nil
                            end
                            if settled_effect ~= "impact" then
                                local spawners, eff = deathstats.spawn_corpse_particles(cpos, data.death_info, data.corpse)
                                data.particle_spawners = spawners
                                data.current_effect_type = eff
                                luaent._particle_spawners = spawners
                                luaent._effect_type = eff
                                data.particles_were_prone = is_prone
                                luaent._particles_were_prone = is_prone
                            else
                                data.current_effect_type = settled_effect
                                luaent._effect_type = settled_effect
                            end
                        end
                    end
                end
            end
        end
    else
        -- If bones are active, ensure any lingering corpse entity is removed
        if data.corpse then
            deathstats.remove_corpse(data.corpse)
            data.corpse = nil
        end
        if data.corpse_wielditem then
            if (not data.corpse_wielditem.is_valid or data.corpse_wielditem:is_valid()) and data.corpse_wielditem.remove then
                data.corpse_wielditem:remove()
            end
            data.corpse_wielditem = nil
        end
    end

    -- Check if camera anchor needs to be re-instantiated if lost across engine reload
    if (not data.anchor or (data.anchor.is_valid and not data.anchor:is_valid())) and data.orbit_center then
        local new_anchor = core.add_entity(data.orbit_center, "deathstats:camera_anchor")
        if new_anchor then
            new_anchor:set_pos(data.orbit_center)
            if new_anchor.set_properties then
                new_anchor:set_properties({
                    is_visible = false,
                    visual_size = { x = 0, y = 0, z = 0 },
                    collisionbox = { 0, 0, 0, 0, 0, 0 },
                    selectionbox = { 0, 0, 0, 0, 0, 0 },
                    pointable = false,
                    use_texture_alpha = true,
                    show_on_minimap = false,
                })
            end
            local cvel = data.corpse_vel or vector.zero()
            if new_anchor.set_velocity then
                new_anchor:set_velocity(cvel)
            end
            local cacc = data.corpse_acc or vector.zero()
            if new_anchor.set_acceleration then
                new_anchor:set_acceleration(cacc)
            end
            data.anchor = new_anchor
            if player.set_pos then player:set_pos(data.orbit_center) end
            if player.set_attach then
                player:set_attach(new_anchor, "", vector.zero(), vector.zero(), false)
            end
            local eff_r = data.eff_radius or data.orbit_radius or (deathstats.config.orbit_radius or 3.2)
            local eff_h = data.eff_height or (eff_r * (data.nominal_ratio or 0.46875))
            if player.set_eye_offset then
                player:set_eye_offset({ x = 0, y = eff_h * 10, z = -eff_r * 10 }, vector.zero())
                data.last_sent_eye_z = -eff_r * 10
                data.last_sent_eye_y = eff_h * 10
            end
        end
    end

    -- Keep player physics locked (gravity = 0, speed = 0) against overrides from external mods (e.g. 3d_armor, playerphysics)
    if player.set_physics_override then
        local cur_phys = player.get_physics_override and player:get_physics_override()
        if not cur_phys or cur_phys.gravity ~= 0 or cur_phys.speed ~= 0 then
            player:set_physics_override({ speed = 0, jump = 0, gravity = 0, sneak = false })
        end
    end

    -- Keep player visual properties strictly invisible against overrides from external mods (e.g. 3d_armor, skinsdb)
    if player.get_properties then
        local cur_props = player:get_properties()
        if cur_props and (cur_props.is_visible ~= false
            or (cur_props.visual_size and (cur_props.visual_size.x > 0 or cur_props.visual_size.y > 0))
            or cur_props.pointable ~= false) then
            player:set_properties({
                is_visible = false,
                visual_size = { x = 0, y = 0, z = 0 },
                collisionbox = { 0, 0, 0, 0, 0, 0 },
                selectionbox = { 0, 0, 0, 0, 0, 0 },
                pointable = false,
                interaction_range = 0,
                textures = { "deathstats_transparent.png" },
                use_texture_alpha = true,
                show_on_minimap = false,
            })
        end
    end

    -- Keep player reach strictly at zero: re-enforce camera_hand in "hand" list
    local inv = player:get_inventory()
    if inv and inv.get_stack and inv.set_stack then
        local cur_hand = inv:get_stack("hand", 1)
        local cur_name = deathstats.get_stack_name(cur_hand)
        if cur_name ~= "deathstats:camera_hand" then
            if inv.set_size and (not inv.get_size or inv:get_size("hand") ~= 1) then
                inv:set_size("hand", 1)
            end
            inv:set_stack("hand", 1, "deathstats:camera_hand")
        end
    end

    -- Defer main inventory stashing until after on_dieplayer has completed (dtime > 0)
    -- This allows bones and external drop mods to handle corpse inventory drops without interference.
    -- If keep_inventory or creative is active, stashing main ensures zero-reach camera hand takes effect.
    if dtime and dtime > 0 and data and not data.stashed_main and inv then
        if not deathstats.is_inventory_list_empty(inv, "main") then
            local items = deathstats.serialize_inventory_list(inv, "main")
            data.stashed_main = items
            local meta = player:get_meta()
            if meta then
                meta:set_string("deathstats:stashed_main", core.serialize(items))
            end
            local sz = (inv.get_size and inv:get_size("main")) or #items
            for i = 1, sz do
                inv:set_stack("main", i, "")
            end
        end
    end
    if data and data.stashed_main and inv then
        if not deathstats.is_inventory_list_empty(inv, "main") then
            local sz = (inv.get_size and inv:get_size("main")) or #data.stashed_main
            for i = 1, sz do
                local cur_st = inv.get_stack and inv:get_stack("main", i)
                if not deathstats.is_stack_empty(cur_st) then
                    inv:set_stack("main", i, "")
                end
            end
        end
    end

    -- Keep player nametag completely hidden (transparent text & background) from other players
    if player.get_nametag_attributes and player.set_nametag_attributes then
        local nta = player:get_nametag_attributes()
        if nta and (nta.text ~= "" or (nta.color and nta.color.a and nta.color.a > 0)) then
            player:set_nametag_attributes({
                text = "",
                color = { a = 0, r = 0, g = 0, b = 0 },
                bgcolor = { a = 0, r = 0, g = 0, b = 0 },
            })
        end
    end

    -- Keep camera anchor strictly invisible, non-pointable, and non-shaded
    if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) and data.anchor.get_properties then
        local aprops = data.anchor:get_properties()
        if aprops and (aprops.is_visible ~= false
            or (aprops.visual_size and (aprops.visual_size.x > 0 or aprops.visual_size.y > 0))
            or aprops.pointable ~= false) then
            data.anchor:set_properties({
                is_visible = false,
                visual_size = { x = 0, y = 0, z = 0 },
                collisionbox = { 0, 0, 0, 0, 0, 0 },
                selectionbox = { 0, 0, 0, 0, 0, 0 },
                pointable = false,
                use_texture_alpha = true,
                show_on_minimap = false,
            })
        end
    end

    -- Hide any attached child objects (e.g. 3d armor meshes or wielded items from external mods)
    if player.get_children then
        local children = player:get_children()
        if children then
            for _, child in ipairs(children) do
                if child and (not child.is_valid or child:is_valid()) and child ~= data.anchor and child ~= data.corpse and child ~= data.corpse_wielditem then
                    local cent = child.get_luaentity and child:get_luaentity()
                    local is_arrow = cent and (cent._is_arrow or (cent.name and cent.name:find("^x_bows:")))
                    if is_arrow then
                        if child.set_properties then
                            child:set_properties({
                                is_visible = false,
                                pointable = false,
                            })
                        end
                    else
                        if child.get_properties and child.set_properties then
                            local cp = child:get_properties()
                            if cp and (cp.is_visible ~= false
                                or (cp.visual_size and (cp.visual_size.x > 0 or cp.visual_size.y > 0))
                                or cp.pointable ~= false) then
                                child:set_properties({
                                    is_visible = false,
                                    visual_size = { x = 0, y = 0, z = 0 },
                                    pointable = false,
                                })
                            end
                        elseif child.set_properties then
                            child:set_properties({
                                is_visible = false,
                                visual_size = { x = 0, y = 0, z = 0 },
                                pointable = false,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Keep player attached to camera anchor to prevent falling/rubber-banding if detached by external mods
    if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) then
        if player.get_attach and not player:get_attach() and player.set_attach then
            player:set_attach(data.anchor, "", vector.zero(), vector.zero(), false)
        end
    end

    -- Advance orbit angle smoothly only after ragdoll corpse has settled
    data.orbit_speed = data.orbit_speed or deathstats.config.orbit_speed or 0.4
    if data.corpse_settled ~= false then
        data.orbit_angle = (data.orbit_angle or 0) + data.orbit_speed * (dtime or 0)
    end
    local angle = data.orbit_angle or (data.yaw or 0)
    data.orbit_angle = angle

    local radius = data.orbit_radius or deathstats.config.orbit_radius or 3.2
    local height = data.orbit_height or deathstats.config.orbit_height or 1.5
    local target_radius = radius

    -- Raycast obstacle detection to prevent camera clipping into walls / terrain.
    -- Uses a continuous clearance buffer (zero boundary step discontinuity) and multi-angle probing.
    local buffer = 0.35
    local probe_radius = radius + buffer
    local nominal_ratio = height / math.max(0.1, radius)
    local probe_height = probe_radius * nominal_ratio

    if core.raycast and data.orbit_center then
        local ray_start = vector.new(data.orbit_center.x, data.orbit_center.y + 0.5, data.orbit_center.z)
        local min_clear_r = probe_radius

        -- Directional lookahead probing: check primary camera sightline plus forward lookahead (+0.06 rad)
        -- to detect approaching walls before camera sweeps into them while avoiding phantom drag from past obstacles
        for i = 1, #CAMERA_PROBE_STEPS do
            local offset_angle = CAMERA_PROBE_STEPS[i]
            local p_angle = angle + offset_angle
            local cam_x = data.orbit_center.x + probe_radius * math.sin(p_angle)
            local cam_y = data.orbit_center.y + probe_height
            local cam_z = data.orbit_center.z - probe_radius * math.cos(p_angle)
            local cam_target = vector.new(cam_x, cam_y, cam_z)
            local ray = core.raycast(ray_start, cam_target, false, false)
            for pointed_thing in ray do
                if pointed_thing.type == "node" and pointed_thing.under then
                    local node = core.get_node_or_nil(pointed_thing.under)
                    local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
                    if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                        local hit_pos = pointed_thing.intersection_point or pointed_thing.under
                        -- Only ignore floor strictly beneath corpse feet/pelvis level
                        local is_ground = (hit_pos.y <= data.orbit_center.y - 0.1)
                            and (math.abs(hit_pos.x - data.orbit_center.x) <= 0.6)
                            and (math.abs(hit_pos.z - data.orbit_center.z) <= 0.6)
                        if not is_ground then
                            -- Project 3D hit point to horizontal orbit radius from orbit center
                            local hx = hit_pos.x - data.orbit_center.x
                            local hz = hit_pos.z - data.orbit_center.z
                            local hit_r = math.sqrt(hx * hx + hz * hz)
                            if hit_r >= 0.4 and hit_r < min_clear_r then
                                min_clear_r = hit_r
                            end
                            break
                        end
                    end
                end
            end
        end

        -- Allow camera to zoom in down to 0.4 blocks to avoid penetrating steep terrain or walls
        target_radius = math.max(0.4, math.min(radius, min_clear_r - buffer))

        -- Additional node clearance check: ensure camera eye point is not inside a solid block
        local cam_x = data.orbit_center.x + target_radius * math.sin(angle)
        local cam_y = data.orbit_center.y + target_radius * nominal_ratio
        local cam_z = data.orbit_center.z - target_radius * math.cos(angle)
        local eye_pos = vector.round(vector.new(cam_x, cam_y, cam_z))
        local node_at_cam = core.get_node_or_nil(eye_pos)
        local def_cam = node_at_cam and node_at_cam.name ~= "ignore" and core.registered_nodes[node_at_cam.name]
        if def_cam and def_cam.walkable and node_at_cam.name ~= "air" and def_cam.drawtype ~= "airlike" then
            target_radius = math.max(0.4, target_radius - 0.6)
        end
    end

    -- Smoothly interpolate current radius toward target radius using framerate-independent exponential damping.
    -- Includes a hold-timer hysteresis (0.5s) to suppress rapid accordion pumping when sweeping past
    -- windows, pillars, doors, and alcoves.
    local dt = (dtime and dtime > 0) and dtime or 0.05
    data.obstacle_hold_timer = data.obstacle_hold_timer or 0

    if not data.eff_radius then
        data.eff_radius = target_radius
    else
        if target_radius < data.eff_radius - 0.02 then
            -- Obstacle detected closer than current camera radius:
            -- React rapidly when following a moving corpse (12.0) to prevent ground penetration
            data.obstacle_hold_timer = 0.5
            local is_moving = (data.corpse_settled == false)
            local lerp_speed = is_moving and 12.0 or 4.5
            local factor = 1.0 - math.exp(-lerp_speed * dt)
            data.eff_radius = data.eff_radius + (target_radius - data.eff_radius) * factor
        elseif target_radius > data.eff_radius + 0.02 then
            -- Obstacle has cleared: check hold timer to suppress rapid accordion pumping
            -- over windows, pillars, and small gaps
            if data.obstacle_hold_timer > 0 then
                data.obstacle_hold_timer = data.obstacle_hold_timer - dt
                -- Hold stable safe distance while passing through transient gaps
            else
                -- Path has stayed clear for the full hold duration: ease out gently and cinematically
                local lerp_speed = 1.2
                local factor = 1.0 - math.exp(-lerp_speed * dt)
                data.eff_radius = data.eff_radius + (target_radius - data.eff_radius) * factor
            end
        end
    end
    local eff_radius = data.eff_radius

    -- Strict proportional height scaling: keeping height proportional to radius maintains
    -- a constant sightline angle (pitch) relative to the corpse, eliminating vertical bobbing
    local eff_height = eff_radius * nominal_ratio

    data.eff_height = eff_height
    data.nominal_ratio = nominal_ratio

    -- Update floating-point eye offset in decimeters (1 dm = 0.1 node)
    -- Negative z offsets camera backwards from player entity along line of sight;
    -- positive y offsets camera upwards to maintain the downward orbit vantage point.
    -- Stream eye offset synchronously on active zoom lerp (0.02 dm threshold) while
    -- completely suppressing redundant packets in steady state / open air.
    local target_dm_z = -eff_radius * 10
    local target_dm_y = eff_height * 10

    if player.set_eye_offset then
        local cur_first = (player.get_eye_offset and player:get_eye_offset())
            or (data.last_sent_eye_z and { y = data.last_sent_eye_y, z = data.last_sent_eye_z })
        if not cur_first
            or math.abs(cur_first.y - target_dm_y) > 0.02
            or math.abs(cur_first.z - target_dm_z) > 0.02 then
            player:set_eye_offset({ x = 0, y = target_dm_y, z = target_dm_z }, vector.zero())
            data.last_sent_eye_z = target_dm_z
            data.last_sent_eye_y = target_dm_y
        end
    end

    -- Downward pitch pointing directly at corpse
    local target_pitch = atan2(eff_height, eff_radius)
    if not data.eff_pitch then
        data.eff_pitch = target_pitch
    else
        local pitch_factor = 1.0 - math.exp(-4.0 * dt)
        data.eff_pitch = data.eff_pitch + (target_pitch - data.eff_pitch) * pitch_factor
    end
    local pitch = data.eff_pitch

    -- Suppress redundant horizontal yaw updates to avoid packet flooding (deadband 0.008 rad matching 08cdd88)
    if player.set_look_horizontal then
        local last_yaw = data.last_sent_yaw
        if not last_yaw or math.abs(angle - last_yaw) > 0.008 then
            player:set_look_horizontal(angle)
            data.last_sent_yaw = angle
        end
    end
    -- Suppress redundant vertical pitch updates to avoid packet flooding (deadband 0.005 rad matching 08cdd88)
    if player.set_look_vertical then
        local cur_pitch = player.get_look_vertical and player:get_look_vertical()
        if not cur_pitch or math.abs(pitch - cur_pitch) > 0.005 then
            player:set_look_vertical(pitch)
        end
    end

    -- Store current yaw & pitch in data
    data.yaw = angle
    data.pitch = pitch
end

--- Position and orient camera to point directly at the bones node, aligning the orbit center
---@param player ObjectRef The deceased player object
---@param bones_pos Vector The 3D coordinates of the bones block
function deathstats.aim_camera_at_bones(player, bones_pos)
    if not player or not player:is_player() or not bones_pos then return end
    local name = player:get_player_name()
    local data = deathstats.player_camera_data[name]

    if not data then
        deathstats.set_death_camera(player)
        data = deathstats.player_camera_data[name]
    end

    if data then
        data.has_bones = true
        local new_center = vector.copy(bones_pos)
        data.bones_pos = new_center
        data.orbit_center = new_center
        if data.corpse then
            deathstats.remove_corpse(data.corpse)
            data.corpse = nil
        end
        if data.corpse_wielditem then
            if (not data.corpse_wielditem.is_valid or data.corpse_wielditem:is_valid()) and data.corpse_wielditem.remove then
                data.corpse_wielditem:remove()
            end
            data.corpse_wielditem = nil
        end
        data.corpse_pos = nil
        data.corpse_visuals = nil
        data.corpse_vel = nil
        local eff_r = data.eff_radius or data.orbit_radius or (deathstats.config.orbit_radius or 3.2)
        local eff_h = data.eff_height or (eff_r * (data.nominal_ratio or 0.46875))
        local cur_angle = data.orbit_angle or (data.yaw or 0)
        if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) then
            if data.anchor.set_velocity then
                data.anchor:set_velocity(vector.zero())
            end
            if data.anchor.set_acceleration then
                data.anchor:set_acceleration(vector.zero())
            end
            if data.anchor.move_to then
                data.anchor:move_to(new_center, false)
            elseif data.anchor.set_pos then
                data.anchor:set_pos(new_center)
            end
        end
        if player.set_detach then player:set_detach() end
        if player.set_pos then player:set_pos(new_center) end
        if data.anchor and player.set_attach then
            player:set_attach(data.anchor, "", vector.zero(), vector.zero(), false)
        end
        if player.set_eye_offset then
            player:set_eye_offset({ x = 0, y = eff_h * 10, z = -eff_r * 10 }, vector.zero())
            data.last_sent_eye_z = -eff_r * 10
            data.last_sent_eye_y = eff_h * 10
        end
        local target_pitch = atan2(eff_h, eff_r)
        if player.set_look_horizontal then player:set_look_horizontal(cur_angle) end
        if player.set_look_vertical then player:set_look_vertical(target_pitch) end
        deathstats.update_death_camera(player, 0)
    end
end

--- Restore any stashed inventory and hand reach, verifying both in-memory camera data and persistent metadata.
--- Used on respawn, disconnect, and joinplayer to guarantee 0% item loss and no stuck zero-reach camera hand.
---@param player ObjectRef The player whose inventory and hand reach should be verified and restored
---@return boolean restored True if any inventory lists or hand reach were restored or sanitized
function deathstats.restore_player_inventory_and_hand(player)
    if not player or not player:is_player() then return false end
    local name = player:get_player_name()
    local inv = player:get_inventory()
    if not inv then return false end

    local data = deathstats.player_camera_data[name]
    local meta = player:get_meta()
    local restored = false

    -- Restore Main Inventory if stashed
    local stashed_main = (data and data.stashed_main)
    if not stashed_main and meta then
        local raw = meta:get_string("deathstats:stashed_main")
        if raw and raw ~= "" then
            local des = core.deserialize(raw)
            if type(des) == "table" then
                stashed_main = des
            end
        end
    end

    if stashed_main then
        deathstats.deserialize_inventory_list(inv, "main", stashed_main)
        if data then
            data.stashed_main = nil
        end
        if meta then
            meta:set_string("deathstats:stashed_main", "")
        end
        restored = true
    elseif meta and meta:get_string("deathstats:stashed_main") ~= "" then
        meta:set_string("deathstats:stashed_main", "")
    end

    if meta and meta:get_string("deathstats:stashed_offhand") ~= "" then
        meta:set_string("deathstats:stashed_offhand", "")
    end

    -- Restore Hand Inventory Slot / Reach
    local saved_hand_size = (data and data.saved_hand_size)
    local saved_hand_stack = (data and data.saved_hand_stack)
    if (not saved_hand_size or saved_hand_size == 0) and meta then
        local raw = meta:get_string("deathstats:stashed_hand")
        if raw and raw ~= "" then
            local des = core.deserialize(raw)
            if type(des) == "table" then
                saved_hand_size = des.size or 0
                saved_hand_stack = des.stack
            end
        end
    end

    if inv.set_size and inv.set_stack then
        if saved_hand_size and saved_hand_size > 0 then
            inv:set_size("hand", saved_hand_size)
            inv:set_stack("hand", 1, saved_hand_stack or "")
            restored = true
        else
            -- If no saved custom hand or size is 0:
            -- Verify whether the hand slot currently holds deathstats:camera_hand
            local current_hand = inv.get_stack and inv:get_stack("hand", 1)
            local current_hand_name = deathstats.get_stack_name(current_hand)
            if current_hand_name == "deathstats:camera_hand" then
                inv:set_size("hand", 0)
                restored = true
            end
        end
        if data then
            data.saved_hand_size = nil
            data.saved_hand_stack = nil
        end
        if meta then meta:set_string("deathstats:stashed_hand", "") end
    end

    -- Strip any deathstats:camera_hand if it leaked into main/craft/offhand
    for _, list_name in ipairs({ "main", "craft", "offhand" }) do
        if inv.get_list and inv.set_stack and inv:get_list(list_name) then
            local list = inv:get_list(list_name)
            for idx, item in ipairs(list) do
                local iname = deathstats.get_stack_name(item)
                if iname == "deathstats:camera_hand" then
                    inv:set_stack(list_name, idx, "")
                    restored = true
                end
            end
        end
    end

    -- Restore pointability and interaction range if player is alive
    if player.get_hp and player:get_hp() > 0 and player.set_properties then
        player:set_properties({
            pointable = true,
            interaction_range = 4,
        })
    end

    return restored
end

--- Hide all external HUD bars (hudbars, hunger, stamina) for a player during death sequence
---@param player ObjectRef The deceased player object
function deathstats.hide_all_hudbars(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()

    if deathstats.compat_hudbars and deathstats.compat_hudbars.hide then
        deathstats.compat_hudbars.hide(player)
    else
        local hb_mod = rawget(_G, "hb") or hb
        if hb_mod and hb_mod.hudtables and hb_mod.hide_hudbar and name then
            for id, ht in pairs(hb_mod.hudtables) do
                if ht.hudstate and ht.hudstate[name] and ht.hudids and ht.hudids[name] then
                    hb_mod.hide_hudbar(player, id)
                end
            end
        end
    end
    if deathstats.compat_hunger and deathstats.compat_hunger.hide_standalone_huds then
        deathstats.compat_hunger.hide_standalone_huds(player)
    end
end

--- Restore all external HUD bars (hudbars, hunger, stamina) for a player on respawn
---@param player ObjectRef The respawned player object
function deathstats.restore_all_hudbars(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()

    if deathstats.compat_hudbars and deathstats.compat_hudbars.unhide then
        deathstats.compat_hudbars.unhide(player)
    else
        local hb_mod = rawget(_G, "hb") or hb
        if hb_mod and hb_mod.hudtables and hb_mod.unhide_hudbar and name then
            for id, ht in pairs(hb_mod.hudtables) do
                if ht.hudstate and ht.hudstate[name] and ht.hudids and ht.hudids[name] then
                    hb_mod.unhide_hudbar(player, id)
                end
            end
        end
    end
    if deathstats.compat_hunger and deathstats.compat_hunger.restore_standalone_huds then
        deathstats.compat_hunger.restore_standalone_huds(player)
    end
end

--- Switch player camera to death perspective (smooth circular orbit around corpse/bones)
---@param player ObjectRef The deceased player object
---@param death_info table|nil Optional death analysis information table
function deathstats.set_death_camera(player, death_info)
    if not deathstats.config.enable_camera or not player or not player:is_player() then return end
    local name = player:get_player_name()

    -- Fallback: recover death_info from recorded player statistics if not provided directly
    if not death_info then
        local pdata = deathstats.get_player_data(player)
        if pdata then
            local cat = (pdata.current_run and pdata.current_run.last_category)
                or (pdata.last_life and pdata.last_life.last_category)
            local cause = (pdata.current_run and pdata.current_run.last_cause)
                or (pdata.last_life and pdata.last_life.last_cause)
            if cat or cause then
                death_info = { category = cat, reason_text = cause }
            end
        end
    end

    -- Clean up any existing anchor / camera session
    local old_data = deathstats.player_camera_data[name]
    if old_data then
        if old_data.anchor and (not old_data.anchor.is_valid or old_data.anchor:is_valid()) and old_data.anchor.remove then
            old_data.anchor:remove()
        end
        old_data.anchor = nil
        if old_data.particle_spawners then
            for _, sid in ipairs(old_data.particle_spawners) do
                core.delete_particlespawner(sid, name)
            end
        end
        old_data.particle_spawners = nil
    end
    if player.get_attach and player:get_attach() and player.set_detach then
        player:set_detach()
    end
    deathstats.zero_player_velocity(player)

    -- Determine ground surface and orbit center
    local meta = player:get_meta()
    local saved_corpse = nil
    if meta then
        local raw_corpse = meta:get_string("deathstats:corpse_data")
        if raw_corpse and raw_corpse ~= "" then
            local des = core.deserialize(raw_corpse)
            if type(des) == "table" and des.pos then
                saved_corpse = des
            end
        end
    end

    local ppos = (saved_corpse and saved_corpse.pos) or player:get_pos()
    if not ppos then return end
    local bones_pos = deathstats.find_player_bones(player)
    local should_show_bones = deathstats.get_bones_mode()
    local expect_bones = should_show_bones or (bones_pos ~= nil)
    local surface_y = (saved_corpse and saved_corpse.pos.y) or deathstats.find_ground_surface(ppos, bones_pos, death_info)
    local corpse_pos = vector.new(ppos.x, surface_y, ppos.z)
    local in_liquid = deathstats.is_in_liquid(ppos, death_info)
    local orbit_center = (in_liquid and corpse_pos) or bones_pos or corpse_pos

    -- Cache original player properties and armor groups for clean respawn restoration
    local props = player:get_properties() or {}
    local old_visual_size = copy(props.visual_size or { x = 1, y = 1, z = 1 })
    local old_collisionbox = copy(props.collisionbox or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 })
    local old_selectionbox = copy(props.selectionbox or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 })
    local old_textures = copy(props.textures or { "character.png" })
    local old_mesh = props.mesh
    local old_pointable = (props.pointable ~= nil and props.pointable or true)
    local old_is_visible = (props.is_visible ~= nil and props.is_visible or true)
    local old_interaction_range = props.interaction_range or 4
    local current_physics = player:get_physics_override() or { speed = 1, jump = 1, gravity = 1 }
    local old_physics = copy(current_physics)
    local old_armor_groups = copy(player:get_armor_groups() or { fleshy = 100 })
    local old_nametag_attributes = nil
    if player.get_nametag_attributes then
        local nta = player:get_nametag_attributes()
        if nta then
            old_nametag_attributes = copy(nta)
        end
    end

    -- Detect uninitialized engine default upright sprite properties (e.g. reconnecting while dead)
    local is_upright_default = (props.visual == "upright_sprite")
        or (props.visual_size and props.visual_size.y == 2 and props.visual_size.x == 1)
        or (props.textures and (props.textures[1] == "player.png" or props.textures[1] == "player_back.png"))

    if is_upright_default then
        if meta then
            local raw_vs = meta:get_string("deathstats:orig_visual_size")
            if raw_vs and raw_vs ~= "" then
                local des_vs = core.deserialize(raw_vs)
                if type(des_vs) == "table" and (des_vs.y ~= 2 or des_vs.x ~= 1) then
                    old_visual_size = des_vs
                else
                    old_visual_size = { x = 1, y = 1, z = 1 }
                end
            else
                old_visual_size = { x = 1, y = 1, z = 1 }
            end
            local raw_tex = meta:get_string("deathstats:orig_textures")
            if raw_tex and raw_tex ~= "" then
                local des_tex = core.deserialize(raw_tex)
                if type(des_tex) == "table" and des_tex[1] and des_tex[1] ~= "player.png" and des_tex[1] ~= "player_back.png" then
                    old_textures = des_tex
                else
                    old_textures = nil
                end
            else
                old_textures = nil
            end
            local raw_mesh = meta:get_string("deathstats:orig_mesh")
            if raw_mesh and raw_mesh ~= "" then
                old_mesh = raw_mesh
            end
        else
            old_visual_size = { x = 1, y = 1, z = 1 }
            old_textures = nil
        end
    elseif meta then
        -- Normal death with valid model: persist clean visual properties for future reconnects
        if old_visual_size and (old_visual_size.y ~= 2 or old_visual_size.x ~= 1) then
            meta:set_string("deathstats:orig_visual_size", core.serialize(old_visual_size))
        end
        if old_textures and old_textures[1] ~= "player.png" and old_textures[1] ~= "player_back.png" then
            meta:set_string("deathstats:orig_textures", core.serialize(old_textures))
        end
        if old_mesh and old_mesh ~= "" then
            meta:set_string("deathstats:orig_mesh", old_mesh)
        end
    end

    -- Enforce zero interaction reach for the camera (range = 0 via camera hand)
    local inv = player:get_inventory()
    local saved_hand_size = 0
    local saved_hand_stack = nil

    if inv then
        if inv.get_size and inv:get_size("hand") > 0 then
            saved_hand_size = inv:get_size("hand")
            if inv.get_stack then
                local st = inv:get_stack("hand", 1)
                local st_name = deathstats.get_stack_name(st)
                if st and st_name ~= "deathstats:camera_hand" and not deathstats.is_stack_empty(st) then
                    saved_hand_stack = deathstats.stack_to_string(st)
                end
            end
        end

        -- Strictly enforce zero interaction reach for the player via camera hand
        if inv.set_size and inv.set_stack then
            inv:set_size("hand", 1)
            inv:set_stack("hand", 1, "deathstats:camera_hand")
        end
    end

    -- Persist stashed hand reach into player metadata (survives crashes, timeouts, disconnects)
    if meta then
        if not saved_hand_stack and saved_hand_size == 0 then
            local raw = meta:get_string("deathstats:stashed_hand")
            if raw and raw ~= "" then
                local des = core.deserialize(raw)
                if type(des) == "table" then
                    saved_hand_size = des.size or 0
                    saved_hand_stack = des.stack
                end
            end
        elseif saved_hand_stack or saved_hand_size > 0 then
            meta:set_string("deathstats:stashed_hand", core.serialize({ size = saved_hand_size, stack = saved_hand_stack }))
        end
    end

    local stashed_main = nil
    if meta then
        local raw_main = meta:get_string("deathstats:stashed_main")
        if raw_main and raw_main ~= "" then
            local des_main = core.deserialize(raw_main)
            if type(des_main) == "table" then
                stashed_main = des_main
            end
        end
    end

    -- Grant complete damage immunity while dead to prevent engine damage calculations and hurt sounds
    if player.set_armor_groups then
        player:set_armor_groups({ immortal = 1, fall_damage_add_percent = -100 })
    end

    -- Extract player visuals across skin mods and spawn corpse placeholder entity
    local visuals = deathstats.get_player_visuals(player)
    if not old_textures or old_textures[1] == "player.png" or old_textures[1] == "player_back.png" then
        old_textures = copy(visuals.textures or { "character.png" })
    end
    if not old_mesh or old_mesh == "" then
        old_mesh = visuals.mesh or "character.b3d"
    end

    if saved_corpse then
        if saved_corpse.mesh then visuals.mesh = saved_corpse.mesh end
        if saved_corpse.textures then visuals.textures = saved_corpse.textures end
        if saved_corpse.visual_size then visuals.visual_size = saved_corpse.visual_size end
        if saved_corpse.yaw then visuals.yaw = saved_corpse.yaw end
        if saved_corpse.armor_dropped ~= nil then visuals.armor_dropped = saved_corpse.armor_dropped end
        if saved_corpse.inventory_dropped ~= nil then visuals.inventory_dropped = saved_corpse.inventory_dropped end
        if saved_corpse.wield_item ~= nil then visuals.wield_item = saved_corpse.wield_item end
    elseif meta then
        meta:set_string("deathstats:orig_textures", core.serialize(visuals.textures))
        meta:set_string("deathstats:orig_mesh", visuals.mesh or "character.b3d")
        meta:set_string("deathstats:orig_visual_size", core.serialize(visuals.visual_size))
        meta:set_string("deathstats:orig_yaw", tostring(visuals.yaw or 0))
        meta:set_string("deathstats:corpse_data", core.serialize({
            pos = corpse_pos,
            yaw = visuals.yaw or 0,
            mesh = visuals.mesh,
            textures = visuals.textures,
            visual_size = visuals.visual_size,
            armor_dropped = visuals.armor_dropped,
            inventory_dropped = visuals.inventory_dropped,
            wield_item = visuals.wield_item,
        }))
    end

    local lb = deathstats.last_blow[name]
    local corpse = nil
    if not expect_bones then
        corpse = deathstats.spawn_and_setup_corpse(corpse_pos, visuals, player, death_info, lb)
    end
    local particle_spawners = nil
    local current_effect_type = nil
    local initial_is_prone = false
    if deathstats.config.enable_corpse_particles ~= false then
        local particle_pos = bones_pos or corpse_pos
        particle_spawners, current_effect_type = deathstats.spawn_corpse_particles(particle_pos, death_info, corpse)
        local c_ent = corpse and corpse.get_luaentity and corpse:get_luaentity()
        local c_rot = (c_ent and c_ent._rot) or (corpse and corpse.get_rotation and corpse:get_rotation())
        local r = (c_rot and c_rot.z) or 0
        local p = (c_rot and c_rot.x) or 0
        initial_is_prone = (math.cos(r) * math.cos(p) < -0.5)
        if c_ent then c_ent._particles_were_prone = initial_is_prone end
    end
    if not expect_bones and not corpse and core.after then
        core.after(0.2, function()
            local p = core.get_player_by_name(name)
            local cdata = deathstats.player_camera_data[name]
            if p and p:is_player() and deathstats.dead_players[name] and cdata and not cdata.corpse and not cdata.has_bones and not cdata.expect_bones then
                local retry_corpse = deathstats.spawn_and_setup_corpse(corpse_pos, visuals, p, death_info, lb)
                if retry_corpse then
                    cdata.corpse = retry_corpse
                    cdata.corpse_wielditem = deathstats.get_corpse_wielditem(retry_corpse)
                end
                if deathstats.config.enable_corpse_particles ~= false and not cdata.particle_spawners then
                    cdata.particle_spawners, cdata.current_effect_type = deathstats.spawn_corpse_particles(corpse_pos, death_info, retry_corpse)
                    local rc_ent = retry_corpse and retry_corpse.get_luaentity and retry_corpse:get_luaentity()
                    local rc_rot = (rc_ent and rc_ent._rot) or (retry_corpse and retry_corpse.get_rotation and retry_corpse:get_rotation())
                    local rr = (rc_rot and rc_rot.z) or 0
                    local rp = (rc_rot and rc_rot.x) or 0
                    local ris_p = (math.cos(rr) * math.cos(rp) < -0.5)
                    cdata.particles_were_prone = ris_p
                    if rc_ent then rc_ent._particles_were_prone = ris_p end
                end
            end
        end)
    end

    -- Hide the real player (ghost), nametag, and lock in first-person camera mode
    if player.set_nametag_attributes then
        player:set_nametag_attributes({
            text = "",
            color = { a = 0, r = 0, g = 0, b = 0 },
            bgcolor = { a = 0, r = 0, g = 0, b = 0 },
        })
    end
    if player.set_properties then
        local trans_tex = "deathstats_transparent.png"
        local hidden_textures = { trans_tex }
        if visuals.mesh == "skinsdb_3d_armor_character_5.b3d" or (visuals.mesh and visuals.mesh:find("skinsdb")) then
            hidden_textures = { trans_tex, trans_tex, trans_tex, trans_tex }
        elseif visuals.mesh == "3d_armor_character.b3d" or (visuals.mesh and visuals.mesh:find("3d_armor")) then
            hidden_textures = { trans_tex, trans_tex, trans_tex }
        end

        player:set_properties({
            is_visible = false,
            visual_size = { x = 0, y = 0, z = 0 },
            collisionbox = { 0, 0, 0, 0, 0, 0 },
            selectionbox = { 0, 0, 0, 0, 0, 0 },
            pointable = false,
            interaction_range = 0,
            textures = hidden_textures,
            use_texture_alpha = true,
            show_on_minimap = false,
        })
    end
    if player.get_children then
        local children = player:get_children()
        if children then
            for _, child in ipairs(children) do
                if child and (not child.is_valid or child:is_valid()) and child ~= corpse then
                    local cent = child.get_luaentity and child:get_luaentity()
                    local is_arrow = cent and (cent._is_arrow or (cent.name and cent.name:find("^x_bows:")))
                    if child.set_properties then
                        if is_arrow then
                            child:set_properties({
                                is_visible = false,
                                pointable = false,
                            })
                        else
                            child:set_properties({
                                is_visible = false,
                                visual_size = { x = 0, y = 0, z = 0 },
                                pointable = false,
                            })
                        end
                    end
                end
            end
        end
    end
    if player.set_physics_override then
        player:set_physics_override({ speed = 0, jump = 0, gravity = 0, sneak = false })
    end

    -- Hide gameplay HUD elements and wielditem to ensure clean cinematic view
    player:hud_set_flags({
        crosshair = false,
        hotbar = false,
        healthbar = false,
        breathbar = false,
        minimap = false,
        wielditem = false,
    })
    deathstats.hide_all_hudbars(player)

    -- Notify player_api / default that player is attached so standard animation steps are bypassed
    deathstats.set_engine_player_attached(name, true)

    -- Suspend local client animations while dead so client does not animate player model
    if player.set_local_animation then
        local none = { x = 0, y = 0 }
        player:set_local_animation(none, none, none, none, 1)
    end

    -- Strictly force first-person camera mode (local player model is never rendered in first-person)
    if player.set_camera then
        player:set_camera({ mode = "first" })
    end

    local radius = deathstats.config.orbit_radius or 3.2
    local height = deathstats.config.orbit_height or 1.5
    local speed = deathstats.config.orbit_speed or 0.4
    local initial_pitch = atan2(height, radius)

    -- Determine initial camera orbit angle:
    -- When ragdoll functionality is enabled, position camera looking towards the dead player
    -- from where the last lethal force originated (punch, explosion, projectile, knockback).
    local initial_angle = visuals.yaw or 0
    if deathstats.config.enable_corpse_ragdoll ~= false then
        local force_dir = nil
        local cvel = (corpse and corpse.get_velocity and corpse:get_velocity())
        if not cvel and corpse and corpse.get_luaentity then
            local clua = corpse:get_luaentity()
            cvel = clua and clua._velocity
        end

        -- Check corpse initial horizontal velocity (impulse from last blow)
        if cvel and (cvel.x * cvel.x + cvel.z * cvel.z >= 0.01) then
            force_dir = safe_normalize({ x = cvel.x, y = 0, z = cvel.z })
        end

        -- Check recent punch direction
        if not force_dir then
            local last_punch = name and deathstats.recent_punches[name]
            if last_punch and last_punch.hitter_pos and orbit_center then
                local d = vector.direction(last_punch.hitter_pos, orbit_center)
                if d.x ~= 0 or d.z ~= 0 then
                    force_dir = safe_normalize({ x = d.x, y = 0, z = d.z })
                end
            elseif last_punch and last_punch.dir and (last_punch.dir.x ~= 0 or last_punch.dir.z ~= 0) then
                force_dir = safe_normalize({ x = last_punch.dir.x, y = 0, z = last_punch.dir.z })
            end
        end

        -- Check lethal blow reason object
        if not force_dir and lb and lb.reason and lb.reason.object and lb.reason.object.get_pos and orbit_center then
            local opos = lb.reason.object:get_pos()
            if opos then
                local d = vector.direction(opos, orbit_center)
                if d.x ~= 0 or d.z ~= 0 then
                    force_dir = safe_normalize({ x = d.x, y = 0, z = d.z })
                end
            end
        end

        -- Check lethal blow residual velocity
        if not force_dir and lb and lb.velocity then
            local vx, vz = lb.velocity.x or 0, lb.velocity.z or 0
            if vx * vx + vz * vz >= 0.25 then
                force_dir = safe_normalize({ x = vx, y = 0, z = vz })
            end
        end

        if force_dir and (force_dir.x ~= 0 or force_dir.z ~= 0) then
            -- With eye offset -R backwards along camera line-of-sight, the camera look direction
            -- for yaw angle θ is (-sin(θ), 0, cos(θ)). Setting this equal to force_dir (pointing
            -- from the force source towards the player) positions the camera at the source of force:
            initial_angle = (atan2(-force_dir.x, force_dir.z) + 2 * math.pi) % (2 * math.pi)
        end
    end

    -- Setup camera anchor directly at orbit_center (corpse / bones position).
    -- By stationing the anchor at orbit_center and co-locating the player's base position at orbit_center,
    -- player:set_look_horizontal(angle) sends TOCLIENT_MOVE_PLAYER with Δ = 0, completely eliminating
    -- the 20Hz tug-of-war position snap between the client prediction and server anchor!
    local anchor = core.add_entity(orbit_center, "deathstats:camera_anchor")
    if anchor then
        anchor:set_pos(orbit_center)
        if anchor.set_properties then
            anchor:set_properties({
                is_visible = false,
                visual_size = { x = 0, y = 0, z = 0 },
                collisionbox = { 0, 0, 0, 0, 0, 0 },
                selectionbox = { 0, 0, 0, 0, 0, 0 },
                pointable = false,
                use_texture_alpha = true,
                show_on_minimap = false,
            })
        end
        local cvel = (corpse and corpse.get_velocity and corpse:get_velocity()) or vector.zero()
        local is_moving = vector.length(cvel) >= 0.05
        if is_moving then
            if anchor.set_velocity then
                anchor:set_velocity(cvel)
            end
            local cacc = (corpse and corpse.get_acceleration and corpse:get_acceleration()) or vector.zero()
            if anchor.set_acceleration then
                anchor:set_acceleration(cacc)
            end
        end
    end
    if player.set_pos then player:set_pos(orbit_center) end
    if anchor and player.set_attach then
        player:set_attach(anchor, "", vector.zero(), vector.zero(), false)
    end

    -- Project camera backwards and upwards using floating-point eye offset (in decimeters: 1 dm = 0.1 node)
    if player.set_eye_offset then
        player:set_eye_offset({ x = 0, y = height * 10, z = -radius * 10 }, vector.zero())
    end

    if player.set_look_horizontal then player:set_look_horizontal(initial_angle) end
    if player.set_look_vertical then player:set_look_vertical(initial_pitch) end

    local cvel_init = (corpse and corpse.get_velocity and corpse:get_velocity()) or vector.zero()
    local has_motion = vector.length(cvel_init) >= 0.05

    deathstats.player_camera_data[name] = {
        has_bones = (bones_pos ~= nil),
        bones_pos = bones_pos,
        expect_bones = expect_bones,
        corpse_pos = (not expect_bones) and corpse_pos or nil,
        initial_death_pos = corpse_pos,
        corpse_visuals = (not expect_bones) and visuals or nil,
        orbit_center = orbit_center,
        orbit_angle = initial_angle,
        orbit_radius = radius,
        orbit_height = height,
        nominal_ratio = height / math.max(0.1, radius),
        eff_radius = radius,
        eff_height = height,
        last_sent_eye_z = -radius * 10,
        last_sent_eye_y = height * 10,
        orbit_speed = speed,
        corpse = corpse,
        corpse_wielditem = deathstats.get_corpse_wielditem(corpse),
        anchor = anchor,
        corpse_settled = (not corpse) or (not has_motion),
        old_armor_groups = old_armor_groups,
        old_is_visible = old_is_visible,
        old_visual_size = old_visual_size,
        old_collisionbox = old_collisionbox,
        old_selectionbox = old_selectionbox,
        old_textures = old_textures,
        old_mesh = old_mesh,
        old_pointable = old_pointable,
        old_interaction_range = old_interaction_range,
        old_physics_override = old_physics,
        old_nametag_attributes = old_nametag_attributes,
        saved_hand_size = saved_hand_size,
        saved_hand_stack = saved_hand_stack,
        stashed_main = stashed_main,
        death_info = death_info,
        last_blow = lb,
        particle_spawners = particle_spawners,
        current_effect_type = current_effect_type,
        arrows_transferred = false,
        corpse_settled_particles_checked = false,
        particles_were_prone = initial_is_prone,
    }

    -- Immediately orient camera to starting orbit vantage
    deathstats.update_death_camera(player, 0)
end

--- Reset player camera back to normal first-person behavior, remove corpse, and restore player properties
---@param player ObjectRef The player object to reset
---@param is_leaving boolean|nil True if called when player is leaving the server
function deathstats.reset_camera(player, is_leaving)
    if not player then return end
    local name = player:get_player_name()
    local data = deathstats.player_camera_data[name]

    -- Detach player from camera anchor
    if player.set_detach then
        player:set_detach()
    end

    -- Remove corpse placeholder, camera anchor entities, and particle spawners
    if data then
        if data.particle_spawners then
            for _, pid in ipairs(data.particle_spawners) do
                core.delete_particlespawner(pid)
            end
            data.particle_spawners = nil
        end
        if data.corpse then
            local decay = deathstats.config.corpse_decay_time or 180
            if decay > 0 and not is_leaving then
                -- Check if player already has an active persistent corpse; dissolve older one to prevent spam
                if deathstats.player_corpses[name] and deathstats.player_corpses[name] ~= data.corpse then
                    deathstats.dissolve_corpse(deathstats.player_corpses[name])
                end
                deathstats.player_corpses[name] = data.corpse
                local luaent = data.corpse.get_luaentity and data.corpse:get_luaentity()
                if luaent then
                    luaent._decay_time = core.get_gametime() + decay
                    luaent._persisted_after_respawn = true
                end
                data.corpse = nil
                data.corpse_wielditem = nil
            else
                deathstats.remove_corpse(data.corpse)
                data.corpse = nil
                if data.corpse_wielditem then
                    if (not data.corpse_wielditem.is_valid or data.corpse_wielditem:is_valid()) and data.corpse_wielditem.remove then
                        data.corpse_wielditem:remove()
                    end
                    data.corpse_wielditem = nil
                end
            end
        end
        if data.corpse_wielditem then
            if (not data.corpse_wielditem.is_valid or data.corpse_wielditem:is_valid()) and data.corpse_wielditem.remove then
                data.corpse_wielditem:remove()
            end
            data.corpse_wielditem = nil
        end
        if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) and data.anchor.remove then
            data.anchor:remove()
            data.anchor = nil
        end
    end

    -- Restore player armor groups
    if data and data.old_armor_groups then
        if player.set_armor_groups then
            player:set_armor_groups(data.old_armor_groups)
        end
    else
        if player.set_armor_groups then
            player:set_armor_groups({ fleshy = 100 })
        end
    end

    -- Clear player_attached flag
    deathstats.set_engine_player_attached(name, nil)

    -- Restore original inventory and hand reach (verified against in-memory data and persistent metadata)
    deathstats.restore_player_inventory_and_hand(player)

    deathstats.player_camera_data[name] = nil

    -- Reset camera modes and eye offsets on the player object itself
    if player.set_camera then
        player:set_camera({ mode = "first" })
    end
    if player.set_eye_offset then
        player:set_eye_offset(vector.zero(), vector.zero(), vector.zero())
    end
    if player.set_look_vertical then
        player:set_look_vertical(0)
    end

    -- If player is leaving, offline, or server is shutting down, skip player_api model/skin updates, animations and timers
    if is_leaving or not deathstats.is_player_online(name) or deathstats.is_shutting_down then
        return
    end

    -- Restore player physical and visual properties & nametag
    local meta = player:get_meta()
    local vs = (data and data.old_visual_size) or { x = 1, y = 1, z = 1 }
    if vs.y == 2 and vs.x == 1 then
        vs = { x = 1, y = 1, z = 1 }
    end
    local tex = data and data.old_textures
    if not tex or tex[1] == "player.png" or tex[1] == "player_back.png" or tex[1] == "deathstats_transparent.png" then
        tex = nil
    end
    if not tex and meta then
        local raw = meta:get_string("deathstats:orig_textures")
        if raw and raw ~= "" then
            local des = core.deserialize(raw)
            if type(des) == "table" and des[1] and des[1] ~= "player.png" and des[1] ~= "player_back.png" then
                tex = des
            end
        end
    end
    if not tex then
        tex = { "character.png" }
    end
    local mesh_name = data and data.old_mesh
    if not mesh_name or mesh_name == "" then
        if meta then
            local raw_m = meta:get_string("deathstats:orig_mesh")
            if raw_m and raw_m ~= "" then
                mesh_name = raw_m
            end
        end
    end
    if not mesh_name or mesh_name == "" then
        mesh_name = "character.b3d"
    end

    if player.set_nametag_attributes then
        if data and data.old_nametag_attributes then
            player:set_nametag_attributes(data.old_nametag_attributes)
        else
            player:set_nametag_attributes({
                text = name,
                color = { a = 255, r = 255, g = 255, b = 255 },
                bgcolor = { a = 0, r = 0, g = 0, b = 0 },
            })
        end
    end
    if player.set_properties then
        player:set_properties({
            is_visible = (data and data.old_is_visible ~= nil and data.old_is_visible or true),
            visual = "mesh",
            mesh = mesh_name,
            visual_size = vs,
            collisionbox = (data and data.old_collisionbox) or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 },
            selectionbox = (data and data.old_selectionbox) or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 },
            pointable = (data and data.old_pointable ~= nil and data.old_pointable or true),
            interaction_range = (data and data.old_interaction_range) or 4,
            textures = tex,
            show_on_minimap = true,
        })
    end
    if player.set_physics_override then
        player:set_physics_override((data and data.old_physics_override) or { speed = 1, jump = 1, gravity = 1 })
    end

    -- Reapply model and skins to player_api, x_player_api, and compatible skin frameworks
    local papi = rawget(_G, "player_api")
    if papi and type(papi) == "table" then
        if type(papi.set_model) == "function" then
            pcall(papi.set_model, player, mesh_name)
        end
        if type(papi.set_textures) == "function" and tex then
            pcall(papi.set_textures, player, tex)
        end
    end
    local x_papi = rawget(_G, "x_player_api")
    if x_papi and type(x_papi) == "table" then
        if type(x_papi.set_model) == "function" then
            pcall(x_papi.set_model, player, mesh_name)
        end
        if type(x_papi.set_textures) == "function" and tex then
            pcall(x_papi.set_textures, player, tex)
        end
    end
    local skins_mod = rawget(_G, "skins")
    if skins_mod and skins_mod.update_player_skin then
        skins_mod.update_player_skin(player)
    end
    local armor_mod = rawget(_G, "armor")
    if armor_mod and armor_mod.set_player_armor then
        armor_mod:set_player_armor(player)
    end

    -- Restore standing animation (with deferred retries to ensure player_api handshake is complete)
    local function restore_stand()
        if deathstats.is_shutting_down or not deathstats.is_player_online(name) then return end
        local p = core.get_player_by_name(name)
        if not p or not p:is_player() then return end
        local player_papi = rawget(_G, "player_api")
        if type(player_papi) == "table" and type(player_papi.registered_players) == "table" and not player_papi.registered_players[name] then
            return
        end
        local restore_xpapi = rawget(_G, "x_player_api")
        if type(restore_xpapi) == "table" and type(restore_xpapi.registered_players) == "table" and not restore_xpapi.registered_players[name] then
            return
        end
        local def_mod = rawget(_G, "default")
        local mcl_p = rawget(_G, "mcl_player")
        if player_papi and type(player_papi) == "table" and type(player_papi.set_animation) == "function" then
            pcall(player_papi.set_animation, p, "stand", 30)
        elseif restore_xpapi and type(restore_xpapi) == "table" and type(restore_xpapi.set_animation) == "function" then
            pcall(restore_xpapi.set_animation, p, "stand", 30)
        elseif def_mod and type(def_mod) == "table" and type(def_mod.player_set_animation) == "function" then
            pcall(def_mod.player_set_animation, p, "stand", 30)
        elseif mcl_p and type(mcl_p) == "table" and type(mcl_p.player_set_animation) == "function" then
            pcall(mcl_p.player_set_animation, p, "stand", 30)
        end
        if player_papi and type(player_papi) == "table" then
            if type(player_papi.set_model) == "function" then
                pcall(player_papi.set_model, p, mesh_name)
            end
            if type(player_papi.set_textures) == "function" and tex then
                pcall(player_papi.set_textures, p, tex)
            end
        end
        if restore_xpapi and type(restore_xpapi) == "table" then
            if type(restore_xpapi.set_model) == "function" then
                pcall(restore_xpapi.set_model, p, mesh_name)
            end
            if type(restore_xpapi.set_textures) == "function" and tex then
                pcall(restore_xpapi.set_textures, p, tex)
            end
        end
    end
    restore_stand()
    core.after(0.2, restore_stand)
    core.after(0.5, restore_stand)

    -- Unlock camera to "any" after short delay
    core.after(0.2, function()
        if not deathstats.is_player_online(name) then return end
        local p = core.get_player_by_name(name)
        if p and p:is_player() and p.set_camera then
            p:set_camera({ mode = "any" })
        end
    end)

    -- Restore gameplay HUD flags and custom hudbars
    local is_hb_health = deathstats.compat_hudbars and deathstats.compat_hudbars.manages_healthbar and deathstats.compat_hudbars.manages_healthbar()
    local is_hb_breath = deathstats.compat_hudbars and deathstats.compat_hudbars.manages_breathbar and deathstats.compat_hudbars.manages_breathbar()
    player:hud_set_flags({
        crosshair = true,
        hotbar = true,
        healthbar = not is_hb_health,
        breathbar = not is_hb_breath,
        minimap = true,
        wielditem = true,
    })
    deathstats.restore_all_hudbars(player)
end

-- Clean up corpse and camera data when a player leaves the server
core.register_on_leaveplayer(function(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    deathstats.left_players[name] = true
    deathstats.dead_players[name] = nil

    -- Restore stashed inventory and hand reach before removing camera data
    deathstats.restore_player_inventory_and_hand(player)

    local data = deathstats.player_camera_data[name]
    if data then
        if data.particle_spawners then
            for _, pid in ipairs(data.particle_spawners) do
                core.delete_particlespawner(pid)
            end
            data.particle_spawners = nil
        end
        if data.corpse then
            deathstats.remove_corpse(data.corpse)
            data.corpse = nil
        end
        if data.corpse_wielditem then
            if (not data.corpse_wielditem.is_valid or data.corpse_wielditem:is_valid()) and data.corpse_wielditem.remove then
                data.corpse_wielditem:remove()
            end
            data.corpse_wielditem = nil
        end
        if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) and data.anchor.remove then
            data.anchor:remove()
        end
    end
    deathstats.set_engine_player_attached(name, nil)
    deathstats.player_camera_data[name] = nil
    deathstats.respawn_immunity[name] = nil
    if deathstats.last_death_reason then
        deathstats.last_death_reason[name] = nil
    end
    if deathstats.compat_hunger and deathstats.compat_hunger.hidden_huds then
        deathstats.compat_hunger.hidden_huds[name] = nil
    end
end)

-- Guard all interaction callbacks: orbiting dead players cannot punch, place, dig, or eat
core.register_on_punchnode(function(_pos, _node, puncher, _pointed_thing)
    if puncher and puncher:is_player() and deathstats.dead_players[puncher:get_player_name()] then
        return true
    end
end)

core.register_on_placenode(function(_pos, _newnode, placer, _oldnode, _itemstack, _pointed_thing)
    if placer and placer:is_player() and deathstats.dead_players[placer:get_player_name()] then
        return true
    end
end)

core.register_on_dignode(function(_pos, _oldnode, digger)
    if digger and digger:is_player() and deathstats.dead_players[digger:get_player_name()] then
        return true
    end
end)

core.register_on_item_eat(function(_hp_change, _replace_with_item, itemstack, user, _pointed_thing)
    if user and user:is_player() and deathstats.dead_players[user:get_player_name()] then
        return itemstack
    end
end)

-- Block dead players from receiving punch damage or punching others
core.register_on_punchplayer(function(player, hitter, _time_from_last_punch, _tool_capabilities, _dir, _damage)
    if not next(deathstats.dead_players) then return end
    local p_name = player and player:is_player() and player:get_player_name()
    local h_name = hitter and hitter:is_player() and hitter:get_player_name()
    if (p_name and deathstats.dead_players[p_name]) or (h_name and deathstats.dead_players[h_name]) then
        return true
    end
end)

-- Block rightclicking on dead players or dead players rightclicking
core.register_on_rightclickplayer(function(player, clicker)
    if not next(deathstats.dead_players) then return end
    local p_name = player and player:is_player() and player:get_player_name()
    local c_name = clicker and clicker:is_player() and clicker:get_player_name()
    if (p_name and deathstats.dead_players[p_name]) or (c_name and deathstats.dead_players[c_name]) then
        return true
    end
end)

-- Prevent dead players from picking up inventory items during camera orbit
core.register_on_item_pickup(function(itemstack, picker, _pointed_thing)
    if not next(deathstats.dead_players) then return end
    if picker and picker:is_player() and deathstats.dead_players[picker:get_player_name()] then
        return itemstack
    end
end)

