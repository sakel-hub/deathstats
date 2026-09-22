--[[
    deathstats - Live Player Statistics Engine & Event Listeners
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local ore_cache = {}

--- Check whether a node is considered an ore based on item groups and naming conventions
---@param node_name string The technical node name (e.g. "default:stone_with_iron")
---@return boolean is_ore True if the node is recognized as a mineable ore
local function is_ore_node(node_name)
    if not node_name or node_name == "" then return false end
    local cached = ore_cache[node_name]
    if cached ~= nil then
        return cached
    end

    local is_ore = false
    if core.get_item_group(node_name, "ore") ~= 0
        or core.get_item_group(node_name, "mineral") ~= 0
    then
        is_ore = true
    else
        local low = node_name:lower()
        if low:find("_with_")
            or low:find("_ore")
            or low:find("ore_")
            or low:find("mineral_")
            or low:find("_mineral")
        then
            is_ore = true
        end
    end

    ore_cache[node_name] = is_ore
    return is_ore
end

-- ==========================================
-- HOOKS: Live Statistics Recording
-- ==========================================

-- Mined Blocks & Ore Breakdown (Tracks dropped items via core.get_node_drops)
core.register_on_dignode(function(_pos, oldnode, digger)
    if not digger or not digger:is_player() then return end
    local name = digger:get_player_name()
    if deathstats.dead_players and deathstats.dead_players[name] then return end
    local data = deathstats.get_player_data(digger)
    if not data then return end

    data.current_run.blocks_mined = data.current_run.blocks_mined + 1
    data.lifetime.blocks_mined = data.lifetime.blocks_mined + 1

    local nname = oldnode.name
    if is_ore_node(nname) then
        local tool = ""
        if digger.get_wielded_item then
            local wield = digger:get_wielded_item()
            if wield and wield.get_name then
                tool = wield:get_name()
            end
        end
        local drops = core.get_node_drops(nname, tool) or core.get_node_drops(oldnode, tool)
        local recorded = false
        if drops and type(drops) == "table" and #drops > 0 then
            for _, drop in ipairs(drops) do
                local dname = drop
                local dcount = 1
                if type(drop) == "userdata" or (type(drop) == "table" and drop.get_name) then
                    dname = drop:get_name()
                    dcount = (drop.get_count and drop:get_count()) or 1
                elseif type(drop) == "string" then
                    local parts = drop:split(" ")
                    if parts and #parts >= 1 then
                        dname = parts[1]
                        if parts[2] and tonumber(parts[2]) then
                            dcount = tonumber(parts[2])
                        end
                    end
                end
                if dname and dname ~= "" then
                    data.current_run.total_ores = data.current_run.total_ores + dcount
                    data.current_run.ores_mined[dname] = (data.current_run.ores_mined[dname] or 0) + dcount
                    data.lifetime.total_ores = data.lifetime.total_ores + dcount
                    data.lifetime.ores_mined[dname] = (data.lifetime.ores_mined[dname] or 0) + dcount
                    recorded = true
                end
            end
        end
        if not recorded then
            data.current_run.total_ores = data.current_run.total_ores + 1
            data.current_run.ores_mined[nname] = (data.current_run.ores_mined[nname] or 0) + 1
            data.lifetime.total_ores = data.lifetime.total_ores + 1
            data.lifetime.ores_mined[nname] = (data.lifetime.ores_mined[nname] or 0) + 1
        end
    end
end)

-- Placed Blocks
core.register_on_placenode(function(_pos, _newnode, placer, _oldnode, _itemstack, _pointed_thing)
    if not placer or not placer:is_player() then return end
    if deathstats.dead_players and deathstats.dead_players[placer:get_player_name()] then return end
    local data = deathstats.get_player_data(placer)
    if not data then return end

    data.current_run.blocks_placed = data.current_run.blocks_placed + 1
    data.lifetime.blocks_placed = data.lifetime.blocks_placed + 1
end)

-- Crafted Items
core.register_on_craft(function(itemstack, player, _old_craft_grid, _craft_inv)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if deathstats.dead_players and deathstats.dead_players[name] then return end
    local data = deathstats.get_player_data(player)
    if not data then return end

    local count = (itemstack and itemstack:get_count()) or 1
    data.current_run.items_crafted = data.current_run.items_crafted + count
    data.lifetime.items_crafted = data.lifetime.items_crafted + count
end)

-- Consumed Items (Food / Potions)
core.register_on_item_eat(function(_hp_change, _replace_with_item, _itemstack, user, _pointed_thing)
    if not user or not user:is_player() then return end
    local name = user:get_player_name()
    if deathstats.dead_players and deathstats.dead_players[name] then return end
    deathstats.reset_player_activity(user)
    local data = deathstats.get_player_data(user)
    if not data then return end

    data.current_run.items_consumed = data.current_run.items_consumed + 1
    data.lifetime.items_consumed = data.lifetime.items_consumed + 1
end)

--- Recent in-world explosion events tracked for fatal blast attribution
deathstats.recent_explosions = deathstats.recent_explosions or {}

--- Record an explosion occurrence with timestamp and coordinates
---@param pos Vector Center of the explosion
---@param radius number|nil Optional explosion blast radius
function deathstats.record_explosion(pos, radius)
    if not pos then return end
    local now = core.get_gametime()
    local valid = {}
    for _, exp in ipairs(deathstats.recent_explosions) do
        if (now - exp.time) <= 5.0 then
            table.insert(valid, exp)
        end
    end
    table.insert(valid, {
        pos = vector.copy(pos),
        time = now,
        radius = radius or 3,
    })
    deathstats.recent_explosions = valid
end

-- Damage Taken & In-Place Revival
core.register_on_player_hpchange(function(player, hp_change, reason)
    if not player or not player:is_player() then return hp_change end
    local name = player:get_player_name()

    -- Edge case: if a player currently in dead_players is healed or revived (hp_change > 0),
    -- immediately reset all death screen effects without waiting for respawn
    if deathstats.dead_players[name] and hp_change > 0 then
        deathstats.reset_player_effects(player)
        return hp_change
    end

    -- Suppress delayed fall damage or residual node damage packets arriving right after respawn
    local immunity_until = deathstats.respawn_immunity and deathstats.respawn_immunity[name]
    if immunity_until and core.get_gametime() < immunity_until then
        if hp_change < 0 and (not reason or reason.type == "fall" or reason.type == "node_damage") then
            return 0
        end
    end

    -- Completely suppress damage and damage sounds for dead players (only suppress damage hp_change < 0, never healing/respawn)
    if (deathstats.dead_players[name] or player:get_hp() <= 0) and hp_change < 0 then
        return 0
    end

    if hp_change < 0 then
        local dmg = math.abs(hp_change)
        local data = deathstats.get_player_data(player)
        if data then
            data.current_run.damage_taken = data.current_run.damage_taken + dmg
            data.lifetime.damage_taken = data.lifetime.damage_taken + dmg
        end

        if reason and (reason.type == "explosion" or (reason.node and reason.node:find("tnt"))) then
            if reason.pos or reason.origin then
                deathstats.record_explosion(reason.pos or reason.origin)
            end
        end

        -- Record the lethal blow if player HP drops to <= 0
        local cur_hp = player:get_hp()
        if cur_hp + hp_change <= 0 or cur_hp <= 0 then
            local ppos = player:get_pos()
            local pvel = (player.get_velocity and player:get_velocity()) or vector.zero()
            local blast_pos = nil
            if ppos and deathstats.recent_explosions then
                local now = core.get_gametime()
                local best_dist = 20.0
                for _, exp in ipairs(deathstats.recent_explosions) do
                    if (now - exp.time) <= 4.0 then
                        local dist = vector.distance(exp.pos, ppos)
                        if dist < best_dist then
                            best_dist = dist
                            blast_pos = exp.pos
                        end
                    end
                end
            end
            deathstats.last_blow[name] = {
                damage = dmg,
                hp_change = hp_change,
                reason = reason,
                time = core.get_gametime(),
                pos = ppos and vector.copy(ppos),
                velocity = pvel and vector.copy(pvel),
                blast_pos = blast_pos,
            }
        end

        -- Record recent starvation damage if starving or reason is starvation
        local is_starve = reason and (reason.type == "starve" or reason.type == "hunger"
                or (reason.hunger and tostring(reason.hunger):find("starve"))
                or (reason.cause and (tostring(reason.cause):find("starve") or tostring(reason.cause):find("hunger"))))
        local is_combat_or_env = reason and (reason.type == "punch" or reason.type == "fall" or reason.type == "burn" or reason.type == "drown")
        if is_starve or (not is_combat_or_env and deathstats.is_player_starving(player)) then
            deathstats.recent_starvations[name] = core.get_gametime()
        end

        -- Record recent dehydration damage if dehydrated or reason is thirst
        local is_thirst = reason and (reason.type == "thirst" or reason.type == "dehydrate"
                or (reason.thirst ~= nil)
                or (reason.cause and (tostring(reason.cause):find("thirst") or tostring(reason.cause):find("dehydrat"))))
        if is_thirst or (not is_combat_or_env and deathstats.is_player_dehydrated(player)) then
            deathstats.recent_dehydrations[name] = core.get_gametime()
        end
    end
    return hp_change
end, true)

-- PvP Damage Dealt Tracking (handles both melee and projectiles like x_bows / x_obsidianmese)
core.register_on_punchplayer(function(_player, hitter, _time_from_last_punch, tool_capabilities, _dir, damage)
    local punch_player = deathstats.resolve_puncher_player(hitter)
    if punch_player and punch_player:is_player() then
        deathstats.reset_player_activity(punch_player)
        local data = deathstats.get_player_data(punch_player)
        local dmg = (damage and damage > 0 and damage)
            or (tool_capabilities and tool_capabilities.damage_groups and tool_capabilities.damage_groups.fleshy)
            or 1
        if data and dmg > 0 then
            data.current_run.damage_dealt = data.current_run.damage_dealt + dmg
            data.lifetime.damage_dealt = data.lifetime.damage_dealt + dmg
        end
    end
end)

local internal_entities = {
    ["deathstats:corpse"] = true,
    ["deathstats:corpse_wielditem"] = true,
    ["deathstats:camera_anchor"] = true,
}

--- Helper to hook an entity prototype's on_punch callback to intercept damage dealt to mobs
--- Supports mobs_redo, creatura, animalia, and native engine mobs
---@param ent_name string The registered technical entity name
---@param ent_def table The entity prototype table
local function hook_entity_punch(ent_name, ent_def)
    if not ent_def or ent_def._deathstats_hooked then return end
    if ent_name and internal_entities[ent_name] then return end
    ent_def._deathstats_hooked = true

    local orig_punch = ent_def.on_punch
    ent_def.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        -- Resolve player even if puncher is an arrow entity or sword projectile
        local player = deathstats.resolve_puncher_player(puncher)

        -- Track mob health before the punch across engine types (mobs_redo, creatura, native)
        local hp_before = (self.health and self.health > 0 and self.health)
            or (self.hp and self.hp > 0 and self.hp)
            or (self.object and self.object.get_hp and self.object:get_hp())

        local res = nil
        if orig_punch then
            res = orig_punch(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        end

        if player and player:is_player() then
            deathstats.reset_player_activity(player)
            local data = deathstats.get_player_data(player)
            if data then
                -- Track mob health after punch to get exact damage applied
                local hp_after = (self.health)
                    or (self.hp)
                    or (self.object and self.object.get_hp and self.object:get_hp())

                local dealt
                if hp_before and hp_after and hp_before > hp_after then
                    dealt = hp_before - hp_after
                elseif damage and damage > 0 then
                    dealt = damage
                elseif tool_capabilities and tool_capabilities.damage_groups and (tool_capabilities.damage_groups.fleshy or 0) > 0 then
                    local fleshy = tool_capabilities.damage_groups.fleshy
                    local interval = tool_capabilities.full_punch_interval or 1.0
                    local mult = 1.0
                    if time_from_last_punch and interval > 0 then
                        mult = math.min(1.0, math.max(0.2, time_from_last_punch / interval))
                    end
                    dealt = math.max(1, math.floor(fleshy * mult + 0.5))
                else
                    dealt = 1
                end

                if dealt > 0 then
                    data.current_run.damage_dealt = data.current_run.damage_dealt + dealt
                    data.lifetime.damage_dealt = data.lifetime.damage_dealt + dealt
                end

                -- Check if mob died from this punch / projectile hit
                local was_alive = (not hp_before or hp_before > 0)
                local is_dead = (self.health and self.health <= 0)
                    or (self.hp and self.hp <= 0)
                    or (self.object and self.object.get_hp and self.object:get_hp() <= 0)
                    or self.is_dead or self.dead or (self.state == "die")
                    or (not self.object or (self.object.is_valid and not self.object:is_valid()))
                    or (hp_before and dealt and dealt > 0 and (hp_before - dealt) <= 0)

                if was_alive and is_dead and deathstats.is_mob_entity(ent_name, ent_def, self) then
                    data.current_run.mobs_killed = data.current_run.mobs_killed + 1
                    data.current_run.killstreak = (data.current_run.killstreak or 0) + 1
                    data.current_run.mobs_slain[ent_name] = (data.current_run.mobs_slain[ent_name] or 0) + 1
                    data.lifetime.mobs_killed = data.lifetime.mobs_killed + 1
                    data.lifetime.mobs_slain[ent_name] = (data.lifetime.mobs_slain[ent_name] or 0) + 1
                end
            end
        end

        return res
    end
end

-- Hook all entities on mod load
core.register_on_mods_loaded(function()
    for ent_name, ent_def in pairs(core.registered_entities) do
        hook_entity_punch(ent_name, ent_def)
    end
    -- Hook tnt.boom if present
    local tnt_mod = rawget(_G, "tnt")
    if tnt_mod and type(tnt_mod.boom) == "function" and not tnt_mod._deathstats_hooked then
        tnt_mod._deathstats_hooked = true
        local orig_boom = tnt_mod.boom
        tnt_mod.boom = function(pos, def)
            deathstats.record_explosion(pos, def and def.radius)
            return orig_boom(pos, def)
        end
    end
end)

-- Also wrap core.register_entity so any entity registered dynamically is also hooked
local orig_register_entity = core.register_entity
rawset(core, "register_entity", function(name, prototype)
    hook_entity_punch(name, prototype)
    return orig_register_entity(name, prototype)
end)

-- Player Join / Leave / Shutdown Handlers
core.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    deathstats.left_players[name] = nil
    local data = deathstats.load_player_stats(name)
    data.last_pos = player:get_pos()
    if player:get_hp() > 0 then
        data.life_start_time = core.get_gametime()
    end
end)

core.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    deathstats.left_players[name] = true

    -- Cleanly reset all death screen effects, HUDs, and camera
    deathstats.reset_player_effects(player, true)

    deathstats.save_player_stats(name)
    deathstats.players[name] = nil
    deathstats.recent_punches[name] = nil
    deathstats.recent_falls[name] = nil
    if deathstats.fall_peaks then
        deathstats.fall_peaks[name] = nil
    end
    deathstats.recent_starvations[name] = nil
    deathstats.recent_dehydrations[name] = nil
    deathstats.last_blow[name] = nil
    if deathstats.last_death_reason then
        deathstats.last_death_reason[name] = nil
    end
end)

core.register_on_shutdown(function()
    for name, _ in pairs(deathstats.players) do
        deathstats.save_player_stats(name)
    end
end)

-- Distance, Fall Velocity & Altitude Tracker
local dist_timer = 0
local fall_timer = 0
--- Highest recorded elevations during airborne falls for fatal fall distance tracking
deathstats.fall_peaks = deathstats.fall_peaks or {}

core.register_globalstep(function(dtime)
    fall_timer = fall_timer + dtime
    dist_timer = dist_timer + dtime

    local do_fall = fall_timer >= 0.1
    local do_dist = dist_timer >= 1.0

    if not do_fall and not do_dist then return end

    local players = core.get_connected_players()
    if #players == 0 then
        if do_fall then fall_timer = 0 end
        if do_dist then dist_timer = 0 end
        return
    end

    if do_fall then
        fall_timer = 0
        for _, player in ipairs(players) do
            local name = player:get_player_name()
            if not deathstats.dead_players[name] then
                local vel = (player.get_velocity and player:get_velocity())
                    or (player.get_player_velocity and player:get_player_velocity())
                local pos = player:get_pos()
                if vel and pos then
                    if vel.y < -1.5 then
                        local cur_peak = deathstats.fall_peaks[name]
                        if not cur_peak or pos.y > cur_peak then
                            deathstats.fall_peaks[name] = pos.y
                        end
                        deathstats.recent_falls[name] = vel.y
                    elseif vel.y >= -0.1 then
                        deathstats.fall_peaks[name] = nil
                    end
                end
            end
        end
    end

    if do_dist then
        dist_timer = 0
        for _, player in ipairs(players) do
            local name = player:get_player_name()
            -- Skip dead players: no movement distance tracking while deceased
            if not deathstats.dead_players[name] then
                local data = deathstats.players[name]
                if data then
                    local pos = player:get_pos()
                    if data.last_pos then
                        local dx = pos.x - data.last_pos.x
                        local dy = pos.y - data.last_pos.y
                        local dz = pos.z - data.last_pos.z
                        local dist_sq = dx * dx + dy * dy + dz * dz
                        -- Only count natural movements, ignore sub-millimeter noise (<= 0.05m) and teleports (>= 50m/s)
                        if dist_sq > 0.0025 and dist_sq < 2500.0 then
                            local dist = math.sqrt(dist_sq)
                            data.current_run.distance_traveled = data.current_run.distance_traveled + dist
                            data.lifetime.distance_traveled = data.lifetime.distance_traveled + dist
                        end
                    end
                    data.last_pos = pos
                end
            end
        end
    end
end)
