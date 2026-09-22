--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

-- ==========================================
-- HUD Elements, Animation & Lifecycle Reset
-- ==========================================

--- Remove all active death HUD elements for a player
---@param player ObjectRef The player whose death HUD elements should be removed
function deathstats.clear_death_hud(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    local huds = deathstats.active_huds[name]
    if huds then
        for _, hid in pairs(huds) do
            if type(hid) == "number" then
                player:hud_remove(hid)
            end
        end
        deathstats.active_huds[name] = nil
    end
    deathstats.active_animations[name] = nil
end

--- Completely reset all death screen effects, HUDs, physics, camera, and state for a player
--- Centralized, reusable helper covering all edge cases (respawn, join, leave, revival)
---@param player ObjectRef The player whose death effects should be cleared
---@param is_leaving boolean|nil True if called when player is leaving the server
function deathstats.reset_player_effects(player, is_leaving)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()

    -- Wipe in-memory death state for this player
    deathstats.dead_players[name] = nil
    deathstats.is_respawning[name] = nil
    deathstats.active_animations[name] = nil
    deathstats.recent_starvations[name] = nil
    deathstats.recent_dehydrations[name] = nil
    deathstats.last_blow[name] = nil
    if deathstats.fall_peaks then
        deathstats.fall_peaks[name] = nil
    end

    -- Clear all death and scoreboard HUD elements
    deathstats.clear_death_hud(player)
    if deathstats.hide_scoreboard_hud then
        deathstats.hide_scoreboard_hud(player)
    end

    -- Close any open death screen or statistics formspecs
    core.close_formspec(name, "deathstats:death")
    core.close_formspec(name, "deathstats:photo_mode")
    core.close_formspec(name, "deathstats:lifetime")
    core.close_formspec(name, "deathstats:death_screen")
    core.close_formspec(name, "deathstats:more_stats")
    core.close_formspec(name, "deathstats:corpse_epitaph")

    -- Restore camera perspective, eye offset, fov, gameplay HUDs, and standing animation
    deathstats.reset_camera(player, is_leaving)
end

--- Calculate responsive banner scale maintaining exact texture aspect ratio across any screen resolution
---@param player ObjectRef|table The player object or mock window info
---@return number scale_x, number scale_y The calculated responsive horizontal and vertical scale
function deathstats.get_banner_responsive_scale(player)
    -- Natural texture dimensions of deathstats_you_died.png (1376x558)
    local tex_w = 1376
    local tex_h = 558
    local tex_aspect = tex_w / tex_h -- ~2.46595

    -- Determine player's window aspect ratio (Luanti 5.7+)
    local screen_aspect = 16 / 9 -- graceful default for standard widescreen
    if player and core.get_player_window_information then
        local name = player:get_player_name()
        local win = core.get_player_window_information(name)
        if win and win.size and win.size.x and win.size.y and win.size.x > 0 and win.size.y > 0 then
            screen_aspect = win.size.x / win.size.y
        end
    end

    -- Responsive sizing targets:
    -- On standard widescreen (16:9, 16:10, ultrawide), banner occupies ~32-35% of screen width.
    -- On narrower/square screens (4:3) or mobile/portrait, it expands up to 75% width.
    -- Height is capped at 23% of screen height so it leaves ample breathing room for subtitles and buttons.
    local max_h_pct = 0.23
    local ideal_w_pct
    if screen_aspect >= 1.5 then
        ideal_w_pct = 0.35
    elseif screen_aspect >= 1.0 then
        ideal_w_pct = 0.50
    else
        ideal_w_pct = 0.75
    end

    -- Required height percentage to achieve exact tex_aspect:
    -- (w_pct * screen_w) / (h_pct * screen_h) = tex_aspect
    -- h_pct = w_pct * screen_aspect / tex_aspect
    local h_pct = ideal_w_pct * screen_aspect / tex_aspect
    local w_pct = ideal_w_pct

    if h_pct > max_h_pct then
        h_pct = max_h_pct
        w_pct = h_pct * tex_aspect / screen_aspect
    end

    -- In Luanti HUD image scale: negative value means percentage of screen dimension (-100 = 100%)
    local scale_x = -w_pct * 100
    local scale_y = -h_pct * 100

    return scale_x, scale_y
end

--- Launch the cinematic death screen experience (Camera, Sound, HUD & Formspec)
---@param player ObjectRef The deceased player object
---@param reason table|nil The optional death reason table provided by the engine
---@param is_reconnect boolean|nil True if player was already dead and is reconnecting
function deathstats.trigger_death_screen(player, reason, is_reconnect)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()

    -- Strictly guard against repeating death loops:
    -- If player is already dead and death sequence is active, NEVER re-trigger
    if deathstats.dead_players[name] then
        return
    end
    deathstats.dead_players[name] = true
    if deathstats.hide_scoreboard_hud then
        deathstats.hide_scoreboard_hud(player)
    end

    -- Hide gameplay HUD elements (hotbar, healthbar, minimap, crosshair, wielditem) for clean cinematic death screen
    player:hud_set_flags({
        crosshair = false,
        hotbar = false,
        healthbar = false,
        breathbar = false,
        minimap = false,
        wielditem = false,
    })
    deathstats.hide_all_hudbars(player)

    -- Analyze death or recover previous death info for reconnecting dead player
    local data = deathstats.get_player_data(player)
    local death_info
    local meta = player:get_meta()

    -- Check if player was already dead before this call (reconnect from server shutdown or disconnect)
    if not is_reconnect and player:get_hp() <= 0 and meta and meta:get_string("deathstats:death_active") == "1" then
        is_reconnect = true
    end

    if is_reconnect then
        if meta then
            local meta_info_raw = meta:get_string("deathstats:death_info")
            if meta_info_raw and meta_info_raw ~= "" then
                local des = core.deserialize(meta_info_raw)
                if type(des) == "table" and des.reason_text then
                    death_info = des
                end
            end
            local meta_last_raw = meta:get_string("deathstats:last_life")
            if meta_last_raw and meta_last_raw ~= "" then
                local des = core.deserialize(meta_last_raw)
                if type(des) == "table" then
                    if not data.last_life or not data.last_life.last_cause or data.last_life.last_cause == "None" or (data.last_life.time_alive or 0) == 0 then
                        data.last_life = des
                    end
                end
            end
        end
        if not death_info and data and data.last_life and data.last_life.last_cause and data.last_life.last_cause ~= "None" then
            death_info = {
                category = data.last_life.last_category or (data.last_life.last_cause:lower():find("fell") and "fall") or "reconnect",
                reason_text = data.last_life.last_cause,
                weapon = data.last_life.last_weapon,
                killer_name = data.last_life.last_killer,
                funny_note = data.last_life.last_funny,
            }
        end
        if not death_info then
            death_info = {
                category = (data and data.last_life and data.last_life.last_category) or "reconnect",
                reason_text = (data and data.last_life and data.last_life.last_cause) or "Died before disconnect",
                weapon = (data and data.last_life and data.last_life.last_weapon) or "None",
                killer_name = (data and data.last_life and data.last_life.last_killer) or "Environment",
                funny_note = (data and data.last_life and data.last_life.last_funny) or "Welcome back to the afterlife.",
            }
        end

        -- Re-persist metadata so death_active and last_life remain solid across repeated disconnects
        if meta then
            meta:set_string("deathstats:death_active", "1")
            if data and data.last_life then
                meta:set_string("deathstats:last_life", core.serialize(data.last_life))
            end
            meta:set_string("deathstats:death_info", core.serialize(death_info))
        end
    else
        death_info = deathstats.analyze_death(player, reason)
        deathstats.record_player_death(player, death_info)
        deathstats.save_player_stats(name)
    end

    -- Camera: switch to cinematic circular orbit around corpse
    deathstats.set_death_camera(player, death_info)

    -- Play random death audio
    deathstats.play_death_sound(player)

    -- Clear any old HUDs
    deathstats.clear_death_hud(player)

    -- Setup HUD Elements positioned down around the horizon
    local huds = {}

    -- Fullscreen Splatter Vignette Overlay (Thematic per death type)
    local blood_opacity = deathstats.config.blood_splatter_opacity
    local overlay_tex = "deathstats_blood_splatter.png"
    if death_info then
        if death_info.category == "lava" then
            overlay_tex = "deathstats_lava_splatter.png"
        elseif death_info.category == "fire" then
            overlay_tex = "deathstats_fire_splatter.png"
        elseif death_info.category == "drown" then
            overlay_tex = "deathstats_drown_splatter.png"
        end
    end
    huds.splatter = player:hud_add({
        type = "image",
        position = { x = 0.5, y = 0.5 },
        alignment = { x = 0, y = 0 },
        offset = { x = 0, y = 0 },
        scale = { x = -102, y = -102 }, -- 102% fullscreen responsive coverage with safety overscan against subpixel seams
        text = overlay_tex .. "^[opacity:" .. blood_opacity,
        z_index = 100,
    })

    -- "YOU DIED" Banner centered horizontally, moved to y=0.20
    -- Responsive scale calculated to preserve natural texture aspect ratio (1376x558)
    local target_scale_x, target_scale_y = deathstats.get_banner_responsive_scale(player)
    local initial_scale_x = deathstats.config.enable_animation and (target_scale_x * 0.15) or target_scale_x
    local initial_scale_y = deathstats.config.enable_animation and (target_scale_y * 0.15) or target_scale_y
    local initial_opacity = deathstats.config.enable_animation and 0 or 255
    local banner_img = "deathstats_you_died.png"
    if deathstats.config.banner_texture and deathstats.config.banner_texture ~= "deathstats_you_died.png" then
        banner_img = deathstats.config.banner_texture
    elseif death_info then
        if death_info.category == "lava" then
            banner_img = "deathstats_you_died_lava.png"
        elseif death_info.category == "fire" then
            banner_img = "deathstats_you_died_fire.png"
        elseif death_info.category == "drown" then
            banner_img = "deathstats_you_died_drown.png"
        end
    end
    huds.you_died = player:hud_add({
        type = "image",
        position = { x = 0.5, y = 0.20 },
        alignment = { x = 0, y = 0 },
        scale = { x = initial_scale_x, y = initial_scale_y },
        text = banner_img .. "^[opacity:" .. initial_opacity,
        z_index = 200,
    })

    -- Primary Subtitle: Death Cause & Weapon (pure white font, moved to y=0.33)
    local cause_text = death_info.reason_text or "You died"
    local initial_cause = deathstats.config.enable_animation and "" or cause_text
    huds.cause = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.33 },
        alignment = { x = 0, y = 0 },
        text = initial_cause,
        number = deathstats.colors.hud_white, -- Pure White for maximum legibility
        z_index = 210,
    })
    huds.cached_cause = cause_text

    -- Secondary Subtitle: Funny Epitaph Note (soft white, moved to y=0.37)
    local funny_text = "“" .. (death_info.funny_note or "Mistakes were made.") .. "”"
    local initial_funny = deathstats.config.enable_animation and "" or funny_text
    huds.funny = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.37 },
        alignment = { x = 0, y = 0 },
        text = initial_funny,
        number = deathstats.colors.hud_soft_white, -- Soft White
        z_index = 210,
    })
    huds.cached_funny = funny_text

    deathstats.active_huds[name] = huds

    -- Display side-docked death formspec immediately to capture input and prevent player movement
    deathstats.show_death_formspec(player, death_info)

    -- Trigger HUD banner animation if enabled
    if deathstats.config.enable_animation then
        deathstats.active_animations[name] = {
            elapsed = 0,
            duration = deathstats.config.animation_duration,
            hud_you_died = huds.you_died,
            hud_cause = huds.cause,
            hud_funny = huds.funny,
            cause_text = cause_text,
            funny_text = funny_text,
            subtitles_revealed = false,
            death_info = death_info,
            last_alpha = initial_opacity,
            banner_texture = banner_img,
            target_scale_x = target_scale_x,
            target_scale_y = target_scale_y,
        }
    end
end

--- Initiate player respawn from UI buttons
---@param player ObjectRef The player requesting respawn
function deathstats.respawn_player(player)
    if not player then return end
    local name = player:get_player_name()

    -- Re-entrancy guard to prevent recursive loops
    if deathstats.is_respawning[name] then return end
    deathstats.is_respawning[name] = true

    -- Activate post-respawn immunity against delayed fall damage packets (2.0 second window)
    deathstats.respawn_immunity[name] = core.get_gametime() + 2.0

    -- Cancel any residual downward fall velocity
    deathstats.zero_player_velocity(player)

    -- Cleanly reset all death screen effects, HUDs, physics, camera, and state
    deathstats.reset_player_effects(player)

    -- Trigger engine respawn (invokes core.register_on_respawnplayer)
    player:respawn()

    deathstats.is_respawning[name] = nil
end

--- Cleanup handler invoked by engine on player respawn
---@param player ObjectRef The player that respawned
function deathstats.on_player_respawn(player)
    if not player then return end
    local name = player:get_player_name()

    -- Activate post-respawn immunity against delayed fall damage packets (2.0 second window)
    deathstats.respawn_immunity[name] = core.get_gametime() + 2.0

    -- Cancel any residual downward fall velocity
    deathstats.zero_player_velocity(player)

    local hp_max = (player:get_properties() and player:get_properties().hp_max) or 20
    player:set_hp(hp_max)

    -- Cleanly reset all death screen effects, HUDs, physics, camera, and state
    deathstats.reset_player_effects(player)

    -- Clear persistent death session metadata
    local meta = player:get_meta()
    if meta then
        meta:set_string("deathstats:death_active", "")
        meta:set_string("deathstats:death_info", "")
        meta:set_string("deathstats:corpse_data", "")
        meta:set_string("deathstats:orig_textures", "")
        meta:set_string("deathstats:orig_mesh", "")
        meta:set_string("deathstats:orig_visual_size", "")
        meta:set_string("deathstats:orig_yaw", "")
    end

    -- Send death coordinates chat message if enabled
    if deathstats.config.chat_death_coords ~= false then
        local data = deathstats.players[name]
        local last = data and data.last_life
        local ldr = deathstats.last_death_reason and deathstats.last_death_reason[name]
        local pos = (last and last.death_pos) or (ldr and ldr.death_pos) or (ldr and ldr.pos)
        if pos then
            local depth = (last and last.depth_desc) or (ldr and ldr.depth_desc) or deathstats.get_depth_description(pos.y)
            local biome = (last and last.biome_name) or (ldr and ldr.biome_name) or deathstats.get_biome_at_pos(pos)
            core.chat_send_player(name, core.colorize(deathstats.colors.text_gold, "[DeathStats] ") ..
                core.colorize(deathstats.colors.text_white, string.format("You died at (%d, %d, %d) in %s (%s).",
                    pos.x, pos.y, pos.z, biome, depth)))
        end
    end

    -- Send active vendetta prompt if revenge system is enabled
    if deathstats.config.enable_revenge ~= false then
        local pdata = deathstats.players[name]
        local v_target = pdata and pdata.current_run and pdata.current_run.vendetta_target
        if v_target then
            core.chat_send_player(name, core.colorize(deathstats.colors.text_crimson, "[DeathStats] ") ..
                core.colorize(deathstats.colors.text_gold, "Vendetta Active: ") ..
                core.colorize(deathstats.colors.text_white, "Slay ") ..
                core.colorize(deathstats.colors.text_crimson, v_target) ..
                core.colorize(deathstats.colors.text_white, " during this life to claim revenge!"))
        end
    end

    -- Deferred reinforcement ticks to guarantee full health and correct model/skin across engine/client respawn handshake
    core.after(0.05, function()
        if deathstats.is_shutting_down or not deathstats.is_player_online(name) then return end
        local p = core.get_player_by_name(name)
        if p and p:is_player() then
            deathstats.zero_player_velocity(p)
            local cur_hp_max = (p:get_properties() and p:get_properties().hp_max) or 20
            if p:get_hp() < cur_hp_max then
                p:set_hp(cur_hp_max)
            end
            if deathstats.compat_hudbars and deathstats.compat_hudbars.manages_healthbar and deathstats.compat_hudbars.manages_healthbar() then
                p:hud_set_flags({ healthbar = false, breathbar = false })
            end
            local p_props = p:get_properties()
            if p_props and (p_props.visual == "upright_sprite" or (p_props.visual_size and p_props.visual_size.y == 2 and p_props.visual_size.x == 1) or (p_props.textures and p_props.textures[1] == "player.png")) then
                local papi = rawget(_G, "player_api") or rawget(_G, "x_player_api")
                if papi and type(papi) == "table" and type(papi.set_model) == "function" then
                    pcall(papi.set_model, p, "character.b3d")
                else
                    p:set_properties({ visual = "mesh", mesh = "character.b3d", visual_size = { x = 1, y = 1, z = 1 }, textures = { "character.png" } })
                end
                local skins_mod = rawget(_G, "skins")
                if skins_mod and skins_mod.update_player_skin then
                    skins_mod.update_player_skin(p)
                end
            end
        end
    end)
    core.after(0.2, function()
        if deathstats.is_shutting_down or not deathstats.is_player_online(name) then return end
        local p = core.get_player_by_name(name)
        if p and p:is_player() then
            deathstats.zero_player_velocity(p)
            local cur_hp_max = (p:get_properties() and p:get_properties().hp_max) or 20
            if p:get_hp() < cur_hp_max then
                p:set_hp(cur_hp_max)
            end
            if deathstats.compat_hudbars and deathstats.compat_hudbars.manages_healthbar and deathstats.compat_hudbars.manages_healthbar() then
                p:hud_set_flags({ healthbar = false, breathbar = false })
            end
            local p_props = p:get_properties()
            if p_props and (p_props.visual == "upright_sprite" or (p_props.visual_size and p_props.visual_size.y == 2 and p_props.visual_size.x == 1) or (p_props.textures and p_props.textures[1] == "player.png")) then
                local papi = rawget(_G, "player_api") or rawget(_G, "x_player_api")
                if papi and type(papi) == "table" and type(papi.set_model) == "function" then
                    pcall(papi.set_model, p, "character.b3d")
                else
                    p:set_properties({ visual = "mesh", mesh = "character.b3d", visual_size = { x = 1, y = 1, z = 1 }, textures = { "character.png" } })
                end
                local skins_mod = rawget(_G, "skins")
                if skins_mod and skins_mod.update_player_skin then
                    skins_mod.update_player_skin(p)
                end
            end
        end
    end)
end

