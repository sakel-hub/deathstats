--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Compatibility Layer: hudbars (hb) and extensions (hbhunger, hbarmor, hbsprint)
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local hb_mod = rawget(_G, "hb") or hb

-- Fast exit if hudbars mod is not present
if not core.get_modpath("hudbars") and not hb_mod then
    return
end

deathstats.compat_hudbars = {
    paused_players = {},
}

local compat = deathstats.compat_hudbars

-- Hook hb.unhide_hudbar to prevent any mod or globalstep from unhiding bars while player is dead
if hb_mod and hb_mod.unhide_hudbar then
    compat.orig_unhide_hudbar = hb_mod.unhide_hudbar
    function hb_mod.unhide_hudbar(player, identifier)
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

-- Hook hb.change_hudbar to prevent status updates from altering or re-showing bars while dead
if hb_mod and hb_mod.change_hudbar then
    compat.orig_change_hudbar = hb_mod.change_hudbar
    function hb_mod.change_hudbar(player, identifier, ...)
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

-- Hook hb.init_hudbar to ensure newly registered or initialized bars start hidden if dead
if hb_mod and hb_mod.init_hudbar then
    compat.orig_init_hudbar = hb_mod.init_hudbar
    function hb_mod.init_hudbar(player, identifier, start_value, start_max, start_hidden)
        if not player or not player:is_player() then
            return false
        end
        local name = player:get_player_name()
        if name and deathstats.dead_players[name] then
            start_hidden = true
        end
        local res = compat.orig_init_hudbar(player, identifier, start_value, start_max, start_hidden)
        if name and deathstats.dead_players[name] and hb_mod.players and hb_mod.players[name] then
            compat.paused_players[name] = true
            hb_mod.players[name] = nil
        end
        return res
    end
end

--- Forcibly hide all hudbars and pause hudbars globalstep updates for a deceased player
---@param player ObjectRef The deceased player object
function compat.hide(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not name then return end

    local h = rawget(_G, "hb") or hb
    if not h then return end

    -- Pause hudbars automatic globalstep updates by removing player from hb.players
    if h.players and h.players[name] then
        compat.paused_players[name] = true
        h.players[name] = nil
    end

    -- Forcibly hide and zero-scale all registered HUD bars across all bar types
    -- Covers: progress_bar, statbar_classic, and statbar_modern
    if h.hudtables then
        for identifier, hudtable in pairs(h.hudtables) do
            local has_state = hudtable.hudstate and hudtable.hudstate[name] ~= nil
            local has_ids = hudtable.hudids and hudtable.hudids[name] ~= nil

            -- Call built-in hide only when player state & IDs are initialized in hudbars
            if has_state and has_ids then
                local hide_fn = compat.orig_hide_hudbar or h.hide_hudbar
                if hide_fn then
                    hide_fn(player, identifier)
                end
            end

            -- Direct zero-scaling on all underlying engine HUD IDs to guarantee invisibility
            local ids = has_ids and hudtable.hudids[name]
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

            if has_state then
                hudtable.hudstate[name].hidden = true
            end
        end
    end
end

--- Check if hudbars is actively managing the healthbar
---@return boolean
function compat.manages_healthbar()
    local h = rawget(_G, "hb") or hb
    return h ~= nil and h.hudtables ~= nil and h.hudtables.health ~= nil
end

--- Check if hudbars is actively managing the breathbar
---@return boolean
function compat.manages_breathbar()
    local h = rawget(_G, "hb") or hb
    return h ~= nil and h.hudtables ~= nil and h.hudtables.breath ~= nil
end

--- Restore hudbars visibility and resume hudbars globalstep updates upon player respawn
---@param player ObjectRef The respawned player object
function compat.unhide(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not name then return end

    local h = rawget(_G, "hb") or hb
    if not h then return end

    -- Resume hudbars automatic globalstep updates
    if compat.paused_players[name] or (h.players and not h.players[name]) then
        compat.paused_players[name] = nil
        if h.players then
            h.players[name] = player
        end
    end

    -- Restore all HUD bars
    if h.hudtables then
        for identifier, hudtable in pairs(h.hudtables) do
            local has_state = hudtable.hudstate and hudtable.hudstate[name] ~= nil
            local has_ids = hudtable.hudids and hudtable.hudids[name] ~= nil

            local ids = has_ids and hudtable.hudids[name]
            if ids and ids.bar then
                player:hud_change(ids.bar, "scale", { x = 1, y = 1 })
            end
            if has_state and has_ids then
                local unhide_fn = compat.orig_unhide_hudbar or h.unhide_hudbar
                if unhide_fn then
                    unhide_fn(player, identifier)
                end
            end
        end
    end

    -- Explicitly suppress built-in engine health and breath bars if hudbars manages them
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

-- Re-enforce hide if hudbars initializes in on_joinplayer after deathstats
core.register_on_joinplayer(function(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if name and deathstats.dead_players[name] then
        core.after(0, function()
            local p = core.get_player_by_name(name)
            if p and deathstats.dead_players[name] then
                compat.hide(p)
            end
        end)
    end
end)

-- Globalstep reinforcement while dead (throttled to 0.1s intervals to prevent packet flooding)
local hb_check_timer = 0
core.register_globalstep(function(dtime)
    if not next(deathstats.dead_players) then return end
    hb_check_timer = hb_check_timer + (dtime or 0.1)
    if hb_check_timer < 0.1 then return end
    hb_check_timer = 0

    local h = rawget(_G, "hb") or hb
    if not h then return end

    for name in pairs(deathstats.dead_players) do
        local p = core.get_player_by_name(name)
        if p and p:is_player() and p:get_hp() <= 0 then
            local needs_hide = false
            if h.players and h.players[name] then
                needs_hide = true
            elseif h.hudtables then
                for _, hudtable in pairs(h.hudtables) do
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
