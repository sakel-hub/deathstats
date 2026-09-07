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

-- 1. Mined Blocks & Ore Breakdown
core.register_on_dignode(function(pos, oldnode, digger)
    if not digger or not digger:is_player() then return end
    local data = deathstats.get_player_data(digger)
    if not data then return end

    data.current_run.blocks_mined = data.current_run.blocks_mined + 1
    data.lifetime.blocks_mined = data.lifetime.blocks_mined + 1

    local nname = oldnode.name
    if is_ore_node(nname) then
        data.current_run.total_ores = data.current_run.total_ores + 1
        data.current_run.ores_mined[nname] = (data.current_run.ores_mined[nname] or 0) + 1
        data.lifetime.total_ores = data.lifetime.total_ores + 1
        data.lifetime.ores_mined[nname] = (data.lifetime.ores_mined[nname] or 0) + 1
    end
end)

-- 2. Placed Blocks
core.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
    if not placer or not placer:is_player() then return end
    if deathstats.dead_players and deathstats.dead_players[placer:get_player_name()] then return end
    local data = deathstats.get_player_data(placer)
    if not data then return end

    data.current_run.blocks_placed = data.current_run.blocks_placed + 1
    data.lifetime.blocks_placed = data.lifetime.blocks_placed + 1
end)

-- 3. Crafted Items
core.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
    if not player or not player:is_player() then return end
    local data = deathstats.get_player_data(player)
    if not data then return end

    local count = (itemstack and itemstack:get_count()) or 1
    data.current_run.items_crafted = data.current_run.items_crafted + count
    data.lifetime.items_crafted = data.lifetime.items_crafted + count
end)

-- 4. Consumed Items (Food / Potions)
core.register_on_item_eat(function(hp_change, replace_with_item, itemstack, user, pointed_thing)
    if not user or not user:is_player() then return end
    local data = deathstats.get_player_data(user)
    if not data then return end

    data.current_run.items_consumed = data.current_run.items_consumed + 1
    data.lifetime.items_consumed = data.lifetime.items_consumed + 1
end)

-- 5. Damage Taken & In-Place Revival
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
    end
    return hp_change
end, true)

-- 6. PvP Damage Dealt Tracking (handles both melee and projectiles like x_bows / x_obsidianmese)
core.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    local punch_player = deathstats.resolve_puncher_player(hitter)
    if punch_player and punch_player:is_player() then
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

--- Helper to hook an entity prototype's on_punch callback to intercept damage dealt to mobs
--- Supports mobs_redo, creatura, animalia, and native engine mobs
---@param ent_name string The registered technical entity name
---@param ent_def table The entity prototype table
local function hook_entity_punch(ent_name, ent_def)
    if not ent_def or ent_def._deathstats_hooked then return end
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

                if was_alive and is_dead then
                    data.current_run.mobs_killed = data.current_run.mobs_killed + 1
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
end)

-- Also wrap core.register_entity so any entity registered dynamically is also hooked
local orig_register_entity = core.register_entity
core.register_entity = function(name, prototype)
    hook_entity_punch(name, prototype)
    return orig_register_entity(name, prototype)
end

-- 8. Player Join / Leave / Shutdown Handlers
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
end)

core.register_on_shutdown(function()
    for name, _ in pairs(deathstats.players) do
        deathstats.save_player_stats(name)
    end
end)

-- 9. Distance & Fall Velocity Periodic Tracker (runs every 1.0s, extremely lightweight)
local timer = 0
core.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 1.0 then return end
    timer = 0

    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()
        -- Skip dead players: no movement distance or fall speed tracking while deceased
        if not deathstats.dead_players[name] then
            local data = deathstats.players[name]
            if data then
                local pos = player:get_pos()
                if data.last_pos then
                    local dist = vector.distance(pos, data.last_pos)
                    -- Only count natural movements, ignore teleports (> 50m/s)
                    if dist > 0.05 and dist < 50.0 then
                        data.current_run.distance_traveled = data.current_run.distance_traveled + dist
                        data.lifetime.distance_traveled = data.lifetime.distance_traveled + dist
                    end
                end
                data.last_pos = pos

                -- Track vertical speed for fall damage detection
                local vel
                if player.get_velocity then
                    vel = player:get_velocity()
                elseif player.get_player_velocity then
                    vel = player:get_player_velocity()
                end
                if vel then
                    deathstats.recent_falls[name] = vel.y
                end
            end
        end
    end
end)
