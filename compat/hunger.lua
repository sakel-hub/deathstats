--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Compatibility Layer: Satiation, Starvation & Dehydration Detection
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

deathstats.compat_hunger = deathstats.compat_hunger or {}
local ch = deathstats.compat_hunger

ch.hidden_huds = {}

--- Get current satiation / hunger metrics for a player across all supported hunger mods
--- Evaluates hbhunger, stamina, mcl_hunger, hunger_ng, hunger (classic), hudbars, and inventory stack
--- Zero use of pcall: strictly checks types, existence, and validated return values
---@param player ObjectRef The player object
---@return number|nil current The current hunger/satiation points
---@return number|nil max The maximum hunger/satiation capacity
---@return number|nil ratio The normalized saturation ratio from 0.0 (empty) to 1.0 (full)
---@return string|nil mod_name The technical identifier of the detected hunger framework
---@return boolean is_starving True if hunger is at or below the framework's starvation damage threshold
function ch.get_player_satiation(player)
    if not player or not player:is_player() then
        return nil, nil, nil, nil, false
    end
    local name = player:get_player_name()
    if not name or name == "" then
        return nil, nil, nil, nil, false
    end

    -- 1. Check hbhunger (Wuzzy)
    local hbh = rawget(_G, "hbhunger")
    if hbh then
        local cur = nil
        if hbh.hunger and hbh.hunger[name] ~= nil then
            cur = tonumber(hbh.hunger[name])
        elseif type(hbh.get_hunger_raw) == "function" then
            cur = tonumber(hbh.get_hunger_raw(player))
        end
        if cur ~= nil then
            local max = tonumber(hbh.SAT_MAX) or 30
            local is_starving = cur <= 1
            local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
            return cur, max, ratio, "hbhunger", is_starving
        end
    end

    -- 2. Check stamina / stamina redo (TenPlus1 / sofar)
    local stam = rawget(_G, "stamina")
    if stam then
        local cur = nil
        if type(stam.get_saturation) == "function" then
            cur = tonumber(stam.get_saturation(player))
        elseif type(stam.get) == "function" then
            cur = tonumber(stam.get(player))
        elseif type(stam.get_stamina) == "function" then
            cur = tonumber(stam.get_stamina(player))
        end
        if cur == nil then
            local meta = player:get_meta()
            local s_str = meta:get_string("stamina:level")
            if s_str ~= "" then
                cur = tonumber(s_str)
            end
        end
        if cur ~= nil then
            local settings = stam.settings or {}
            local max = tonumber(settings.visual_max) or 20
            local starve_lvl = tonumber(settings.starve_lvl) or 3
            local is_starving = cur < starve_lvl
            local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
            return cur, max, ratio, "stamina", is_starving
        end
    end

    -- 3. Check mcl_hunger (MineClone2 / VoxeLibre / Mineclonia)
    local mcl_h = rawget(_G, "mcl_hunger")
    if mcl_h then
        local cur = nil
        if type(mcl_h.get_hunger) == "function" then
            cur = tonumber(mcl_h.get_hunger(player))
        else
            local meta = player:get_meta()
            local h_str = meta:get_string("mcl_hunger:hunger")
            if h_str ~= "" then
                cur = tonumber(h_str)
            end
        end
        if cur ~= nil then
            local max = 20
            local is_starving = cur <= 0
            local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
            return cur, max, ratio, "mcl_hunger", is_starving
        end
    end

    -- 4. Check hunger_ng (Linuxdirk)
    local hng = rawget(_G, "hunger_ng")
    if hng then
        if type(hng.get_hunger_information) == "function" then
            local info = hng.get_hunger_information(name)
            if info and not info.invalid and type(info.hunger) == "table" then
                local cur = tonumber(info.hunger.exact) or tonumber(info.hunger.floored) or 0
                local max = (type(info.maximum) == "table" and tonumber(info.maximum.hunger)) or 20
                local is_starving
                if type(info.effects) == "table" and type(info.effects.starving) == "table" then
                    is_starving = info.effects.starving.status == true
                else
                    is_starving = cur <= 0
                end
                local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
                return cur, max, ratio, "hunger_ng", is_starving
            end
        end
        local cur = nil
        if type(hng.get_hunger) == "function" then
            cur = tonumber(hng.get_hunger(player))
        elseif hng.hunger and hng.hunger[name] ~= nil then
            cur = tonumber(hng.hunger[name])
        end
        if cur ~= nil then
            local max = 20
            local is_starving = cur <= 0
            local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
            return cur, max, ratio, "hunger_ng", is_starving
        end
    end

    -- 5. Check classic hunger mod (BlockMen / better_hud / pie)
    local hmod = rawget(_G, "hunger")
    if hmod then
        local cur = nil
        if type(hmod.read) == "function" then
            cur = tonumber(hmod.read(player))
        elseif type(hmod.get_hunger) == "function" then
            cur = tonumber(hmod.get_hunger(player))
        elseif hmod.hunger and hmod.hunger[name] ~= nil then
            cur = tonumber(hmod.hunger[name])
        end
        if cur ~= nil then
            local max = 20
            local is_starving = cur <= 1
            local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
            return cur, max, ratio, "hunger", is_starving
        end
    end

    -- 6. Check hudbars (hb) registered bar state for 'satiation' or 'hunger'
    local hb_mod = rawget(_G, "hb")
    if hb_mod then
        for _, bar_id in ipairs({ "satiation", "hunger" }) do
            -- If hb.hudtables is present, verify bar_id is registered first to avoid crashing
            -- in hudbars/init.lua:448 (which indexes hb.hudtables[id].hudstate directly)
            local tbl = hb_mod.hudtables and hb_mod.hudtables[bar_id]
            if not hb_mod.hudtables or tbl then
                local cur = nil
                local max = (tbl and tonumber(tbl.max)) or 20
                if tbl and tbl.hudstate and tbl.hudstate[name] and tbl.hudstate[name].value ~= nil then
                    cur = tonumber(tbl.hudstate[name].value)
                    if tbl.hudstate[name].max ~= nil then
                        max = tonumber(tbl.hudstate[name].max) or max
                    end
                elseif type(hb_mod.get_hudbar_state) == "function" then
                    local state = hb_mod.get_hudbar_state(player, bar_id)
                    if state and state.value ~= nil then
                        cur = tonumber(state.value)
                        if state.max ~= nil then
                            max = tonumber(state.max) or max
                        end
                    end
                end
                if cur ~= nil then
                    local is_starving = cur <= 1
                    local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
                    return cur, max, ratio, "hudbars:" .. bar_id, is_starving
                end
            end
        end
    end

    -- 7. Direct inventory 'hunger' stack count fallback (hbhunger stores count = hunger + 1)
    local inv = player:get_inventory()
    if inv and inv:get_size("hunger") > 0 then
        local st = inv:get_stack("hunger", 1)
        if st and not st:is_empty() then
            local count = st:get_count()
            local cur = math.max(0, count - 1)
            local max = 20
            local is_starving = count <= 2
            local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
            return cur, max, ratio, "inventory", is_starving
        end
    end

    return nil, nil, nil, nil, false
end

--- Check if a player is in a starving state (satiation/hunger depleted)
--- Unified wrapper delegating to deathstats.compat_hunger.get_player_satiation
---@param player ObjectRef The player object
---@return boolean is_starving True if hunger level is at or below starvation threshold
function ch.is_player_starving(player)
    local _, _, _, _, is_starving = ch.get_player_satiation(player)
    return is_starving == true
end

--- Get hydration status and metrics for a player from thirsty mod
---@param player ObjectRef The player object
---@return number|nil current Current hydro points (0-20)
---@return number|nil max Maximum hydration (20)
---@return number|nil ratio Normalized hydration ratio (0.0 to 1.0)
---@return string|nil mod_name Mod identifier ("thirsty")
---@return boolean is_dehydrated True if hydro points <= 0
function ch.get_player_hydration(player)
    if not player or not player:is_player() then
        return nil, nil, nil, nil, false
    end
    local name = player:get_player_name()
    if not name or name == "" then
        return nil, nil, nil, nil, false
    end

    local cur = nil
    local meta = player:get_meta()
    local s_hydro = meta:get_string("thirsty_hydro")
    if s_hydro ~= "" then
        cur = tonumber(s_hydro) or meta:get_float("thirsty_hydro")
    end

    local thirsty_mod = rawget(_G, "thirsty")
    if cur == nil and thirsty_mod then
        if type(thirsty_mod.get_hydro) == "function" then
            cur = tonumber(thirsty_mod.get_hydro(player))
        elseif thirsty_mod.hydro and thirsty_mod.hydro[name] ~= nil then
            cur = tonumber(thirsty_mod.hydro[name])
        elseif thirsty_mod.player and thirsty_mod.player[name] ~= nil then
            local entry = thirsty_mod.player[name]
            if type(entry) == "table" then
                cur = tonumber(entry.hydro or entry.value or 20)
            else
                cur = tonumber(entry) or 20
            end
        end
    end

    -- Check hudbars 'thirst'
    local hb_mod = rawget(_G, "hb")
    if cur == nil and hb_mod and hb_mod.hudtables and hb_mod.hudtables.thirst then
        local tbl = hb_mod.hudtables.thirst
        if tbl.hudstate and tbl.hudstate[name] and tbl.hudstate[name].value ~= nil then
            cur = tonumber(tbl.hudstate[name].value)
        end
    end

    if cur ~= nil then
        local max = 20
        local is_dehydrated = cur <= 0.0
        local ratio = max > 0 and math.max(0, math.min(1, cur / max)) or 0
        return cur, max, ratio, "thirsty", is_dehydrated
    end

    return nil, nil, nil, nil, false
end

--- Check if player is dehydrated (thirst hydro depleted)
---@param player ObjectRef
---@return boolean
function ch.is_player_dehydrated(player)
    local _, _, _, _, is_dehydrated = ch.get_player_hydration(player)
    return is_dehydrated == true
end

--- Check if player was recently sprinting or sprint-stamina exhausted
--- Supports hbsprint, sprint_lite, unified_stamina, stamina
---@param player ObjectRef
---@return boolean
function ch.is_player_sprint_exhausted(player)
    if not player or not player:is_player() then return false end
    local name = player:get_player_name()
    if not name or name == "" then return false end

    -- 1. hbsprint / sprint check
    local spmod = rawget(_G, "sprint")
    if spmod then
        if spmod.stamina and spmod.stamina[name] ~= nil then
            local num = tonumber(spmod.stamina[name])
            if num and num <= 1.0 then return true end
        elseif spmod.players and spmod.players[name] and spmod.players[name].stamina ~= nil then
            local num = tonumber(spmod.players[name].stamina)
            if num and num <= 1.0 then return true end
        end
    end
    local meta = player:get_meta()
    local hbs = meta:get_string("hbsprint:stamina")
    if hbs ~= "" then
        local num = tonumber(hbs) or meta:get_float("hbsprint:stamina")
        if num and num <= 1.0 then
            return true
        end
    end

    -- 2. sprint_lite API check
    local slit = rawget(_G, "sprint_lite")
    if slit then
        if type(slit.get_stamina) == "function" then
            local stam = slit.get_stamina(name) or slit.get_stamina(player)
            if stam and type(stam) == "number" and stam <= 1.0 then
                return true
            end
        elseif slit.players and slit.players[name] and slit.players[name].stamina ~= nil then
            local stam = tonumber(slit.players[name].stamina)
            if stam and stam <= 1.0 then return true end
        end
    end

    -- 3. unified_stamina API check
    local ustam = rawget(_G, "unified_stamina")
    if ustam then
        if type(ustam.get) == "function" then
            local val = ustam.get(name) or ustam.get(player)
            if val and type(val) == "number" and val <= 0.05 then
                return true
            end
        elseif type(ustam.get_stamina) == "function" then
            local val = ustam.get_stamina(player) or ustam.get_stamina(name)
            if val and type(val) == "number" and val <= 0.05 then
                return true
            end
        end
    end

    -- 4. Active sprint key press control check
    local ctrl = player:get_player_control()
    if ctrl and ctrl.aux1 and (ctrl.up or ctrl.down or ctrl.left or ctrl.right) then
        return true
    end

    return false
end

--- Hide standalone HUD statbars registered without hudbars (stamina, hunger, thirst)
---@param player ObjectRef
function ch.hide_standalone_huds(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not name or name == "" then return end

    local all_huds = nil
    if type(player.hud_get_all) == "function" then
        all_huds = player:hud_get_all()
    elseif type(player.huds) == "table" then
        all_huds = player.huds
    end

    local candidate_ids = {}

    -- Check all_huds if accessible
    if all_huds and type(all_huds) == "table" then
        for id, def in pairs(all_huds) do
            if def then
                local is_target = false
                if def.name and (def.name:find("stamina") or def.name:find("hunger") or def.name:find("thirst")) then
                    is_target = true
                elseif def.text and type(def.text) == "string" and (def.text:find("stamina") or def.text:find("hunger") or def.text:find("thirst")) then
                    is_target = true
                end
                if is_target then
                    candidate_ids[id] = def.scale or { x = 1, y = 1 }
                end
            end
        end
    end

    -- Check mod-level HUD ID tables (stamina, thirsty)
    local stam = rawget(_G, "stamina")
    if stam then
        local ids = (stam.hud_ids and stam.hud_ids[name]) or (stam.hud and stam.hud[name])
        if type(ids) == "table" then
            for _, hid in pairs(ids) do
                if type(hid) == "number" and not candidate_ids[hid] then
                    candidate_ids[hid] = { x = 1, y = 1 }
                end
            end
        elseif type(ids) == "number" and not candidate_ids[ids] then
            candidate_ids[ids] = { x = 1, y = 1 }
        end
    end

    local th = rawget(_G, "thirsty")
    if th then
        local ids = (th.hud and th.hud[name]) or (th.hud_ids and th.hud_ids[name])
        if type(ids) == "table" then
            for _, hid in pairs(ids) do
                if type(hid) == "number" and not candidate_ids[hid] then
                    candidate_ids[hid] = { x = 1, y = 1 }
                end
            end
        elseif type(ids) == "number" and not candidate_ids[ids] then
            candidate_ids[ids] = { x = 1, y = 1 }
        end
    end

    for id, orig_scale in pairs(candidate_ids) do
        ch.hidden_huds[name] = ch.hidden_huds[name] or {}
        ch.hidden_huds[name][id] = orig_scale
        player:hud_change(id, "scale", { x = 0, y = 0 })
    end
end

--- Restore standalone HUD statbars upon respawn or effect reset
---@param player ObjectRef
function ch.restore_standalone_huds(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not name or name == "" then return end

    if ch.hidden_huds and ch.hidden_huds[name] then
        for id, orig_scale in pairs(ch.hidden_huds[name]) do
            player:hud_change(id, "scale", orig_scale)
        end
        ch.hidden_huds[name] = nil
    end
end

-- Expose methods directly on deathstats namespace
deathstats.get_player_satiation = ch.get_player_satiation
deathstats.is_player_starving = ch.is_player_starving
deathstats.get_player_hydration = ch.get_player_hydration
deathstats.is_player_dehydrated = ch.is_player_dehydrated
deathstats.is_player_sprint_exhausted = ch.is_player_sprint_exhausted
