--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Compatibility Layer: hudbars (hb) and extensions (hbhunger, hbarmor, hbsprint)
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

-- Fast exit if hudbars mod is not present
if not core.get_modpath("hudbars") and not rawget(_G, "hb") then
    return
end

deathstats.compat_hudbars = {
    paused_players = {},
}

local compat = deathstats.compat_hudbars

-- 1. Hook hb.unhide_hudbar to prevent any mod or globalstep from unhiding bars while player is dead
if hb.unhide_hudbar then
    compat.orig_unhide_hudbar = hb.unhide_hudbar
    function hb.unhide_hudbar(player, identifier)
        if not player or not player:is_player() then
            return false
        end
        local name = player:get_player_name()
        if name and deathstats.dead_players[name] then
            -- Strictly reject unhiding while the death sequence is active
            return false
        end
        return compat.orig_unhide_hudbar(player, identifier)
    end
end

-- 2. Hook hb.change_hudbar to prevent status updates from altering or re-showing bars while dead
if hb.change_hudbar then
    compat.orig_change_hudbar = hb.change_hudbar
    function hb.change_hudbar(player, identifier, ...)
        if not player or not player:is_player() then
            return false
        end
        local name = player:get_player_name()
        if name and deathstats.dead_players[name] then
            -- Suppress value / visibility updates while dead
            return false
        end
        return compat.orig_change_hudbar(player, identifier, ...)
    end
end

-- 3. Hook hb.init_hudbar to ensure newly registered or initialized bars start hidden if dead
if hb.init_hudbar then
    compat.orig_init_hudbar = hb.init_hudbar
    function hb.init_hudbar(player, identifier, start_value, start_max, start_hidden)
        if not player or not player:is_player() then
            return false
        end
        local name = player:get_player_name()
        if name and deathstats.dead_players[name] then
            start_hidden = true
        end
        return compat.orig_init_hudbar(player, identifier, start_value, start_max, start_hidden)
    end
end

--- Forcibly hide all hudbars and pause hudbars globalstep updates for a deceased player
---@param player ObjectRef The deceased player object
function compat.hide(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not name then return end

    local hb_mod = rawget(_G, "hb")
    if not hb_mod then return end

    -- 1. Pause hudbars automatic globalstep updates by removing player from hb.players
    if hb_mod.players and hb_mod.players[name] then
        compat.paused_players[name] = true
        hb_mod.players[name] = nil
    end

    -- 2. Forcibly hide and zero-scale all registered HUD bars across all bar types
    -- Covers: progress_bar, statbar_classic, and statbar_modern
    if hb_mod.hudtables then
        for identifier, hudtable in pairs(hb_mod.hudtables) do
            -- Call built-in hide
            if compat.orig_hide_hudbar then
                compat.orig_hide_hudbar(player, identifier)
            elseif hb_mod.hide_hudbar then
                hb_mod.hide_hudbar(player, identifier)
            end

            -- Direct zero-scaling on all underlying engine HUD IDs to guarantee invisibility
            local ids = hudtable.hudids and hudtable.hudids[name]
            if ids then
                if ids.bg then
                    player:hud_change(ids.bg, "scale", { x = 0, y = 0 })
                end
                if ids.icon then
                    player:hud_change(ids.icon, "scale", { x = 0, y = 0 })
                end
                if ids.bar then
                    player:hud_change(ids.bar, "scale", { x = 0, y = 0 })
                    player:hud_change(ids.bar, "number", 0)
                    player:hud_change(ids.bar, "item", 0)
                end
                if ids.text then
                    player:hud_change(ids.text, "text", "")
                end
            end

            if hudtable.hudstate and hudtable.hudstate[name] then
                hudtable.hudstate[name].hidden = true
            end
        end
    end
end

--- Check if hudbars is actively managing the healthbar
---@return boolean
function compat.manages_healthbar()
    return hb ~= nil and hb.hudtables ~= nil and hb.hudtables.health ~= nil
end

--- Check if hudbars is actively managing the breathbar
---@return boolean
function compat.manages_breathbar()
    return hb ~= nil and hb.hudtables ~= nil and hb.hudtables.breath ~= nil
end

--- Restore hudbars visibility and resume hudbars globalstep updates upon player respawn
---@param player ObjectRef The respawned player object
function compat.unhide(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not name then return end

    local hb_mod = rawget(_G, "hb")
    if not hb_mod then return end

    -- 1. Resume hudbars automatic globalstep updates
    if compat.paused_players[name] or (hb_mod.players and not hb_mod.players[name]) then
        compat.paused_players[name] = nil
        if hb_mod.players then
            hb_mod.players[name] = player
        end
    end

    -- 2. Restore all HUD bars
    if hb_mod.hudtables then
        for identifier, hudtable in pairs(hb_mod.hudtables) do
            local ids = hudtable.hudids and hudtable.hudids[name]
            if ids and ids.bar then
                player:hud_change(ids.bar, "scale", { x = 1, y = 1 })
            end
            if compat.orig_unhide_hudbar then
                compat.orig_unhide_hudbar(player, identifier)
            elseif hb_mod.unhide_hudbar then
                hb_mod.unhide_hudbar(player, identifier)
            end
        end
    end

    -- 3. Explicitly suppress built-in engine health and breath bars if hudbars manages them
    -- This prevents duplicate health bars (engine statbar + hudbars) on respawn
    local suppress_flags = {}
    if compat.manages_healthbar() then
        suppress_flags.healthbar = false
    end
    if compat.manages_breathbar() then
        suppress_flags.breathbar = false
    end
    if next(suppress_flags) then
        player:hud_set_flags(suppress_flags)
    end
end

-- 4. Globalstep reinforcement while dead (throttled to 0.1s intervals to prevent packet flooding)
local hb_check_timer = 0
core.register_globalstep(function(dtime)
    if not next(deathstats.dead_players) then return end
    hb_check_timer = hb_check_timer + (dtime or 0.1)
    if hb_check_timer < 0.1 then return end
    hb_check_timer = 0

    for name in pairs(deathstats.dead_players) do
        local p = core.get_player_by_name(name)
        if p and p:is_player() and p:get_hp() <= 0 then
            local needs_hide = false
            if hb.players and hb.players[name] then
                needs_hide = true
            elseif hb.hudtables then
                for _, hudtable in pairs(hb.hudtables) do
                    if hudtable.hudstate and hudtable.hudstate[name] and not hudtable.hudstate[name].hidden then
                        needs_hide = true
                        break
                    end
                end
            end
            if needs_hide then
                compat.hide(p)
            end
        end
    end
end)
