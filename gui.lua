--[[
    deathstats - HUD Animation Engine, Camera Globalstep & Engine Overrides
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]


local S = core.get_translator(core.get_current_modname())

-- ==========================================
-- HUD Animation Globalstep & Bones Tracking
-- ==========================================

--- Calculate distance flight and screen slap animation parameters
--- Uses an elastic damped sine curve trajectory for prominent zoom-in and bouncy recoil
---@param progress number Animation progress factor from 0.0 to 1.0
---@param target_w number|nil Target scale X percentage (default -32.0)
---@param target_h number|nil Target scale Y percentage (default -23.0)
---@return number scale_x Calculated X dimension scale
---@return number scale_y Calculated Y dimension scale
---@return number alpha Alpha transparency level (0-255)
---@return boolean impact_reached True if animation reached or passed impact threshold
function deathstats.calculate_slap_animation(progress, target_w, target_h)
    target_w = target_w or -32.0
    target_h = target_h or -23.0
    local start_w  = target_w * 0.15
    local start_h  = target_h * 0.15

    -- Continuous Elastic Damped Oscillation trajectory:
    -- Starts from distant perspective (progress=0 -> factor=0, 15% scale),
    -- surges forward into a prominent zoom-in peaking at ~1.31x scale (progress ~0.35),
    -- bounces back with an undershoot to ~0.91x scale (progress ~0.75),
    -- and smoothly settles to exact resting target scale 1.00x at completion (progress=1.0).
    local factor = 1.0 - (2.0 ^ (-4.5 * progress)) * math.cos(progress * math.pi * 2.5)

    local scale_x = start_w + (target_w - start_w) * factor
    local scale_y = start_h + (target_h - start_h) * factor

    -- Smooth alpha stepped into 5 clean stages to eliminate client texture re-rasterization stutters
    local alpha
    if progress < 0.05 then
        alpha = 60
    elseif progress < 0.12 then
        alpha = 120
    elseif progress < 0.20 then
        alpha = 180
    elseif progress < 0.28 then
        alpha = 230
    else
        alpha = 255
    end

    local impact_reached = (progress >= 0.35)
    return scale_x, scale_y, alpha, impact_reached
end

local calculate_slap_animation = deathstats.calculate_slap_animation

--- Globalstep animation loop for distance flight and visceral screen slap
core.register_globalstep(function(dtime)
    -- Fast exit if no death sequences or animations are active
    if not next(deathstats.dead_players) and not next(deathstats.active_animations) then
        return
    end

    -- Keep dead players camera oriented properly and detect delayed bones
    for name in pairs(deathstats.dead_players) do
        local player = core.get_player_by_name(name)
        if player and player:is_player() then
            if player:get_hp() > 0 then
                -- Player is alive (revived, healed, or respawned), immediately clean up dead state
                deathstats.dead_players[name] = nil
                deathstats.on_player_respawn(player)
            elseif deathstats.config.enable_camera then
                -- Clamp dtime to avoid large visual jumps on lag spikes
                local safe_dt = math.min(dtime or 0.05, 0.1)
                deathstats.update_death_camera(player, safe_dt)
            end
        else
            deathstats.dead_players[name] = nil
        end
    end

    -- Handle HUD distance flight and screen slap animation
    for name, anim in pairs(deathstats.active_animations) do
        local player = core.get_player_by_name(name)
        if not player or not player:is_player() then
            deathstats.active_animations[name] = nil
        else
            anim.elapsed = anim.elapsed + dtime
            local progress = math.min(1.0, anim.elapsed / anim.duration)

            local current_scale_x, current_scale_y, current_alpha, impact_reached =
                calculate_slap_animation(progress, anim.target_scale_x, anim.target_scale_y)

            if anim.hud_you_died then
                if anim.last_scale_x ~= current_scale_x or anim.last_scale_y ~= current_scale_y then
                    anim.last_scale_x = current_scale_x
                    anim.last_scale_y = current_scale_y
                    player:hud_change(anim.hud_you_died, "scale", { x = current_scale_x, y = current_scale_y })
                end
                if anim.last_alpha ~= current_alpha then
                    anim.last_alpha = current_alpha
                    local btex = anim.banner_texture or deathstats.config.banner_texture or "deathstats_you_died.png"
                    local tex = (current_alpha >= 255) and btex or (btex .. "^[opacity:" .. current_alpha)
                    player:hud_change(anim.hud_you_died, "text", tex)
                end
            end

            -- Reveal cause of death and funny quote with punch right as the banner slaps on screen
            if impact_reached and not anim.subtitles_revealed then
                anim.subtitles_revealed = true
                if anim.hud_cause and anim.cause_text then
                    player:hud_change(anim.hud_cause, "text", anim.cause_text)
                end
                if anim.hud_funny and anim.funny_text then
                    player:hud_change(anim.hud_funny, "text", anim.funny_text)
                end
            end

            -- When animation completes, finalize animation tracking
            if progress >= 1.0 then
                deathstats.active_animations[name] = nil
            end
        end
    end
end)

-- ==========================================
-- Formspec Event Handlers
-- ==========================================

--- Retrieve the fallback death reason and epitaph information for a player
---@param player ObjectRef|string The player object or player username
---@return table last_info Formatted death info table { reason_text = string, funny_note = string, category = string }
function deathstats.get_last_death_info(player)
    local name = (type(player) == "string") and player
        or (player and player.get_player_name and player:get_player_name())
    local data = name and deathstats.players[name]
    local p_obj = (type(player) ~= "string") and player or (name and core.get_player_by_name(name))
    local meta = p_obj and p_obj.get_meta and p_obj:get_meta()
    local d_info_str = meta and meta:get_string("deathstats:death_info")
    local d_info = nil
    if d_info_str and d_info_str ~= "" then
        local des = core.deserialize(d_info_str)
        if type(des) == "table" then
            d_info = des
        end
    end

    local last_reason = name and deathstats.last_death_reason and deathstats.last_death_reason[name]
    local last_life = data and data.last_life

    local category = (last_reason and last_reason.category)
        or (d_info and d_info.category)
        or (last_life and last_life.last_category)
        or "unknown"

    local reason_text = (last_reason and last_reason.reason_text)
        or (d_info and d_info.reason_text)
        or (last_life and last_life.last_cause)
        or S("You died")

    local funny_note = (last_reason and last_reason.funny_note)
        or (d_info and d_info.funny_note)
        or (last_life and last_life.last_funny)
        or S("Mistakes were made.")

    return {
        category = category,
        reason_text = reason_text,
        funny_note = funny_note,
        damage = (last_reason and last_reason.damage) or (d_info and d_info.damage),
        killer_name = (last_reason and last_reason.killer_name) or (d_info and d_info.killer_name) or (last_life and last_life.last_killer),
        weapon_name = (last_reason and last_reason.weapon_name) or (d_info and (d_info.weapon_name or d_info.weapon)) or (last_life and last_life.last_weapon),
        node_name = (last_reason and last_reason.node_name) or (d_info and d_info.node_name),
    }
end

core.register_on_player_receive_fields(function(player, formname, fields)
    if not player then return end
    local name = player:get_player_name()

    -- Corpse Epitaph Plaque handling (open for living players)
    if formname == "deathstats:corpse_epitaph" then
        if fields.btn_close_epitaph or fields.quit then
            core.close_formspec(name, "deathstats:corpse_epitaph")
            return true
        end
    end

    -- Lifetime Statistics Dashboard (accessible by both living players via /stats and deceased players)
    if formname == "deathstats:lifetime" then
        if fields.tab_overview then
            deathstats.show_lifetime_stats_formspec(player, "overview")
            return true
        elseif fields.tab_records then
            deathstats.show_lifetime_stats_formspec(player, "records")
            return true
        elseif fields.tab_ores then
            deathstats.show_lifetime_stats_formspec(player, "ores")
            return true
        elseif fields.tab_combat then
            deathstats.show_lifetime_stats_formspec(player, "combat")
            return true
        elseif fields.btn_close then
            core.close_formspec(name, "deathstats:lifetime")
            return true
        elseif fields.btn_back_death then
            if deathstats.is_player_dead(player) then
                deathstats.show_death_formspec(player, deathstats.get_last_death_info(player))
            else
                core.close_formspec(name, "deathstats:lifetime")
            end
            return true
        elseif fields.btn_modal_respawn then
            if deathstats.is_player_dead(player) then
                deathstats.respawn_player(player)
            else
                core.close_formspec(name, "deathstats:lifetime")
            end
            return true
        elseif fields.quit then
            if deathstats.is_player_dead(player) then
                deathstats.show_death_formspec(player, deathstats.get_last_death_info(player))
            end
            return true
        end
        return true
    end

    -- If player is dead: strictly control formspec navigation and prevent closing
    if deathstats.dead_players[name] and not deathstats.is_respawning[name] then
        -- Photo mode toggle: hide UI
        if fields.btn_photo_mode then
            core.close_formspec(name, "deathstats:death")
            deathstats.show_photo_mode_formspec(player)
            return true
        end

        -- Photo mode active: restore death formspec
        if formname == "deathstats:photo_mode" then
            if fields.btn_show_ui or fields.quit then
                core.close_formspec(name, "deathstats:photo_mode")
                deathstats.show_death_formspec(player, deathstats.get_last_death_info(player))
                return true
            end
            return true
        end

        -- Respawn button clicked from death screen
        if fields.btn_try_again then
            deathstats.respawn_player(player)
            return true
        end

        -- Navigation: open Lifetime Stats Dashboard
        if fields.btn_more_stats then
            deathstats.show_lifetime_stats_formspec(player, "overview")
            return true
        end

        -- If player pressed ESC, closed the window, or any formspec was closed while dead:
        -- Immediately re-show the death screen to prevent the "zombie state" (see Luanti #11523)
        -- and keep the player immobilized via active formspec UI without delay
        if fields.quit then
            deathstats.show_death_formspec(player, deathstats.get_last_death_info(player))
            return true
        end
    end
end)

-- ==========================================
-- Engine Hooks & Overrides
-- ==========================================

--- Override core.show_death_screen to suppress the default engine death formspec
---@param player ObjectRef The deceased player
---@param reason table|nil The death cause or reason table
function core.show_death_screen(player, reason)
    local meta = player and player:get_meta()
    local is_reconnect = player and player:get_hp() <= 0 and meta and (meta:get_string("deathstats:death_active") == "1")
    deathstats.trigger_death_screen(player, reason, is_reconnect)
end

-- Catch-all for dieplayer in case show_death_screen was not called
core.register_on_dieplayer(function(player, reason)
    local meta = player and player:get_meta()
    local is_reconnect = player and player:get_hp() <= 0 and meta and (meta:get_string("deathstats:death_active") == "1")
    deathstats.trigger_death_screen(player, reason, is_reconnect)
end)

-- Engine respawn hook: cleanup camera and HUD (never calls player:respawn)
core.register_on_respawnplayer(function(player)
    deathstats.on_player_respawn(player)
    return false
end)

-- Player join hook: check player HP when joining; if dead show death screen, otherwise reset effects (see Luanti builtin death_screen.lua)
core.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    deathstats.left_players[name] = nil
    local meta = player:get_meta()
    if player:get_hp() <= 0 or (meta and meta:get_string("deathstats:death_active") == "1") then
        deathstats.trigger_death_screen(player, nil, true)
    else
        if meta and meta:get_string("deathstats:death_active") ~= "" then
            meta:set_string("deathstats:death_active", "")
            meta:set_string("deathstats:death_info", "")
            meta:set_string("deathstats:corpse_data", "")
        end
        deathstats.reset_player_effects(player)
        deathstats.restore_player_inventory_and_hand(player)
    end
end)
