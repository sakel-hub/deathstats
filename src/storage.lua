--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local copy = table.copy


--- Migrate legacy mined ore block names to actual dropped item names (e.g. stone_with_coal -> coal_lump)
---@param ores_map table Map of [item_or_node_name] = count
---@return table ores_map The migrated map
function deathstats.migrate_ores_mined(ores_map)
    if not ores_map or type(ores_map) ~= "table" then return ores_map end
    local to_move = {}
    for node_name, count in pairs(ores_map) do
        local low = node_name:lower()
        if low:find("_with_") or low:find("_ore") or low:find("ore_") or low:find("mineral_") or low:find("_mineral") then
            local mapped_item = nil
            local drops = core.get_node_drops(node_name, "")
            if drops and type(drops) == "table" and #drops > 0 then
                local d = drops[1]
                if type(d) == "string" then
                    mapped_item = d:split(" ")[1]
                elseif (type(d) == "userdata" or type(d) == "table") and d.get_name then
                    mapped_item = d:get_name()
                end
            end
            if not mapped_item or mapped_item == node_name then
                if low:find("coal") then
                    mapped_item = "default:coal_lump"
                elseif low:find("iron") then
                    mapped_item = "default:iron_lump"
                elseif low:find("copper") then
                    mapped_item = "default:copper_lump"
                elseif low:find("tin") then
                    mapped_item = "default:tin_lump"
                elseif low:find("gold") then
                    mapped_item = "default:gold_lump"
                elseif low:find("diamond") then
                    mapped_item = "default:diamond"
                elseif low:find("mese") then
                    mapped_item = "default:mese_crystal"
                end
            end
            if mapped_item and mapped_item ~= node_name then
                to_move[node_name] = { target = mapped_item, count = count }
            end
        end
    end
    for old_name, info in pairs(to_move) do
        ores_map[old_name] = nil
        ores_map[info.target] = (ores_map[info.target] or 0) + info.count
    end
    return ores_map
end

--- Clean up non-mob entries (arrows, items, falling nodes, vehicles) from player stats
---@param data table Player statistics data table
function deathstats.cleanup_invalid_mobs_slain(data)
    if not data then return nil end
    local targets = { data.current_run, data.lifetime, data.last_life }
    for i = 1, 3 do
        local tbl = targets[i]
        if tbl and tbl.mobs_slain then
            local to_remove = {}
            for ent_name, count in pairs(tbl.mobs_slain) do
                if not deathstats.is_mob_entity(ent_name) then
                    table.insert(to_remove, { name = ent_name, count = tonumber(count) or 0 })
                end
            end
            local removed = 0
            for _, item in ipairs(to_remove) do
                tbl.mobs_slain[item.name] = nil
                removed = removed + item.count
            end
            if removed > 0 and tbl.mobs_killed then
                tbl.mobs_killed = math.max(0, tbl.mobs_killed - removed)
            end
        end
    end
    return data
end



-- ==========================================
-- Player Statistics Data Management
-- ==========================================

--- Load persistent player lifetime statistics from Mod Storage and initialize current run
---@param player_name string The unique username of the player
---@return table data The player data table containing current_run, lifetime, and last_life
function deathstats.load_player_stats(player_name)
    local raw = deathstats.storage:get_string("player:" .. player_name)
    local lifetime = nil
    if raw ~= "" then
        lifetime = core.deserialize(raw)
    end

    local raw_last = deathstats.storage:get_string("last_life:" .. player_name)
    local last_life = nil
    if raw_last ~= "" then
        last_life = core.deserialize(raw_last)
    end

    -- Dual persistence check: load from player metadata if storage was empty or not flushed
    local player = core.get_player_by_name(player_name)
    local meta = player and player:get_meta()
    if meta then
        if type(lifetime) ~= "table" then
            local meta_raw = meta:get_string("deathstats:lifetime")
            if meta_raw and meta_raw ~= "" then
                local des = core.deserialize(meta_raw)
                if type(des) == "table" then lifetime = des end
            end
        end
        if type(last_life) ~= "table" or not last_life.last_cause or last_life.last_cause == "None" or (last_life.time_alive or 0) == 0 then
            local meta_last_raw = meta:get_string("deathstats:last_life")
            if meta_last_raw and meta_last_raw ~= "" then
                local des = core.deserialize(meta_last_raw)
                if type(des) == "table" then
                    last_life = des
                end
            end
        end
    end

    if type(lifetime) ~= "table" then
        lifetime = deathstats.create_empty_stats()
    else
        -- Ensure all fields exist
        lifetime.ores_mined = lifetime.ores_mined or {}
        lifetime.mobs_slain = lifetime.mobs_slain or {}
        lifetime.players_slain = lifetime.players_slain or {}
        lifetime.deaths_by_category = lifetime.deaths_by_category or {}
        lifetime.killers_count = lifetime.killers_count or {}
        lifetime.personal_bests = lifetime.personal_bests or {
            survival_time = 0,
            kills = 0,
            killstreak = 0,
            blocks_mined = 0,
            total_ores = 0,
            damage_dealt = 0,
        }
    end

    if type(last_life) ~= "table" then
        last_life = deathstats.create_empty_stats()
    else
        last_life.ores_mined = last_life.ores_mined or {}
        last_life.mobs_slain = last_life.mobs_slain or {}
        last_life.players_slain = last_life.players_slain or {}
        last_life.deaths_by_category = last_life.deaths_by_category or {}
        last_life.killers_count = last_life.killers_count or {}
    end

    if lifetime.ores_mined then
        deathstats.migrate_ores_mined(lifetime.ores_mined)
    end
    if last_life.ores_mined then
        deathstats.migrate_ores_mined(last_life.ores_mined)
    end

    local data = {
        name = player_name,
        life_start_time = core.get_gametime(),
        last_pos = nil,
        current_run = deathstats.create_empty_stats(),
        lifetime = lifetime,
        last_life = last_life,
    }

    deathstats.cleanup_invalid_mobs_slain(data)

    deathstats.players[player_name] = data
    return data
end

--- Save player lifetime statistics to Mod Storage
---@param player_name string The unique username of the player
function deathstats.save_player_stats(player_name)
    local data = deathstats.players[player_name]
    if not data or not data.lifetime then return end
    deathstats.storage:set_string("player:" .. player_name, core.serialize(data.lifetime))
    if data.last_life then
        deathstats.storage:set_string("last_life:" .. player_name, core.serialize(data.last_life))
    end

    -- Maintain index of all saved players for Hall of Fame roster
    local idx_str = deathstats.storage:get_string("all_players_index")
    local idx = (idx_str ~= "" and core.deserialize(idx_str)) or {}
    if not idx[player_name] then
        idx[player_name] = true
        deathstats.storage:set_string("all_players_index", core.serialize(idx))
    end

    local player = core.get_player_by_name(player_name)
    local meta = player and player:get_meta()
    if meta then
        meta:set_string("deathstats:lifetime", core.serialize(data.lifetime))
        if data.last_life then
            meta:set_string("deathstats:last_life", core.serialize(data.last_life))
        end
    end
end

--- Get or initialize the active statistics data table for a player
---@param player ObjectRef The player object to retrieve data for
---@return table|nil data The active player statistics data table, or nil if player is invalid
function deathstats.get_player_data(player)
    if not player then return nil end
    local name = type(player) == "string" and player or (player.get_player_name and player:get_player_name())
    if not name or name == "" then return nil end
    local data = deathstats.players[name]
    if not data then
        data = deathstats.load_player_stats(name)
    end
    if data and not data._meta_last_life_checked and (not data.last_life or not data.last_life.last_cause or data.last_life.last_cause == "None" or (data.last_life.time_alive or 0) == 0) then
        data._meta_last_life_checked = true
        local meta = type(player) ~= "string" and player.get_meta and player:get_meta()
        if meta then
            local meta_last_raw = meta:get_string("deathstats:last_life")
            if meta_last_raw and meta_last_raw ~= "" then
                local des = core.deserialize(meta_last_raw)
                if type(des) == "table" then
                    data.last_life = des
                end
            end
        end
    end
    return data
end

--- Finalize statistics for the deceased player run, update lifetime aggregates, and archive to last_life
---@param player ObjectRef|string The player who died
---@param death_info table The death analysis table containing reason_text, killer_name, weapon, and funny_note
function deathstats.record_player_death(player, death_info)
    local name = type(player) == "string" and player or (player and player.get_player_name and player:get_player_name())
    if not name or name == "" then return end
    local data = deathstats.get_player_data(player)
    if not data then return end

    if deathstats.last_death_reason then
        deathstats.last_death_reason[name] = death_info
    end

    local duration = math.max(1, core.get_gametime() - data.life_start_time)
    data.current_run.time_alive = duration
    data.current_run.last_category = death_info.category or "other"
    data.current_run.last_cause = death_info.reason_text or "Unknown"
    data.current_run.last_weapon = death_info.weapon or "None"
    data.current_run.last_killer = death_info.killer_name or (death_info.is_player and "Player" or "Environment")
    data.current_run.last_funny = death_info.funny_note or "Mistakes were made."

    -- Update lifetime aggregates
    data.lifetime.deaths = data.lifetime.deaths + 1
    data.lifetime.time_alive = data.lifetime.time_alive + duration
    data.lifetime.last_category = data.current_run.last_category
    data.lifetime.last_cause = data.current_run.last_cause
    data.lifetime.last_weapon = data.current_run.last_weapon
    data.lifetime.last_killer = data.current_run.last_killer
    data.lifetime.last_funny = data.current_run.last_funny

    local cat = data.current_run.last_category
    local killer = data.current_run.last_killer
    data.lifetime.deaths_by_category = data.lifetime.deaths_by_category or {}
    data.lifetime.deaths_by_category[cat] = (data.lifetime.deaths_by_category[cat] or 0) + 1
    if killer and killer ~= "None" and killer ~= "Environment" and killer ~= "" then
        data.lifetime.killers_count = data.lifetime.killers_count or {}
        data.lifetime.killers_count[killer] = (data.lifetime.killers_count[killer] or 0) + 1
    end

    -- Update personal bests / records
    local pb = data.lifetime.personal_bests
    if not pb then
        pb = {
            survival_time = 0,
            kills = 0,
            killstreak = 0,
            blocks_mined = 0,
            total_ores = 0,
            damage_dealt = 0,
        }
        data.lifetime.personal_bests = pb
    end

    local run_kills = (data.current_run.mobs_killed or 0) + (data.current_run.players_killed or 0)
    local run_streak = data.current_run.killstreak or 0
    local is_new_record = false
    local new_records = {}

    if duration > (pb.survival_time or 0) then
        pb.survival_time = duration
        new_records.survival_time = true
        is_new_record = true
    end
    if run_kills > (pb.kills or 0) then
        pb.kills = run_kills
        new_records.kills = true
        is_new_record = true
    end
    if run_streak > (pb.killstreak or 0) then
        pb.killstreak = run_streak
        new_records.killstreak = true
        is_new_record = true
    end
    if (data.current_run.blocks_mined or 0) > (pb.blocks_mined or 0) then
        pb.blocks_mined = data.current_run.blocks_mined
        new_records.blocks_mined = true
        is_new_record = true
    end
    if (data.current_run.total_ores or 0) > (pb.total_ores or 0) then
        pb.total_ores = data.current_run.total_ores
        new_records.total_ores = true
        is_new_record = true
    end
    if (data.current_run.damage_dealt or 0) > (pb.damage_dealt or 0) then
        pb.damage_dealt = data.current_run.damage_dealt
        new_records.damage_dealt = true
        is_new_record = true
    end

    -- Copy current run to last_life snapshot
    local snapshot = {}
    for k, v in pairs(data.current_run) do
        if type(v) == "table" then
            local t = {}
            for tk, tv in pairs(v) do t[tk] = tv end
            snapshot[k] = t
        else
            snapshot[k] = v
        end
    end
    snapshot.is_new_record = is_new_record
    snapshot.new_records = new_records
    snapshot.personal_bests = copy(pb)
    snapshot.killer_hp = death_info.killer_hp
    snapshot.killer_health = death_info.killer_health or death_info.killer_hp
    snapshot.killer_max_hp = death_info.killer_max_hp or death_info.killer_hp_max
    snapshot.killer_hp_max = snapshot.killer_max_hp
    snapshot.fall_height = death_info.fall_height
    snapshot.fall_speed = death_info.fall_speed
    snapshot.death_pos = death_info.pos
    snapshot.depth_desc = death_info.depth_desc
    snapshot.biome_name = death_info.biome_name
    data.last_life = snapshot

    -- Reset current run for the next life
    data.current_run = deathstats.create_empty_stats()
    data.life_start_time = core.get_gametime()

    -- Persist immediately to Mod Storage and Player Metadata
    deathstats.save_player_stats(name)
    local meta = type(player) ~= "string" and player.get_meta and player:get_meta()
    if not meta and core.get_player_by_name then
        local p_obj = core.get_player_by_name(name)
        if p_obj and p_obj.get_meta then
            meta = p_obj:get_meta()
        end
    end
    if meta then
        local function sanitize_for_serialize(tbl)
            if type(tbl) ~= "table" then return tbl end
            local clean = {}
            for k, v in pairs(tbl) do
                local tv = type(v)
                if tv == "string" or tv == "number" or tv == "boolean" then
                    clean[k] = v
                elseif tv == "table" then
                    clean[k] = sanitize_for_serialize(v)
                end
            end
            return clean
        end
        meta:set_string("deathstats:death_active", "1")
        meta:set_string("deathstats:last_life", core.serialize(data.last_life))
        meta:set_string("deathstats:death_info", core.serialize(sanitize_for_serialize(death_info)))
        meta:set_string("deathstats:lifetime", core.serialize(data.lifetime))
    end

    -- If slain by another player (direct or via projectile), credit the killer
    if (death_info.is_player or death_info.type == "pvp" or death_info.category == "pvp") and death_info.killer_name then
        local killer_player = core.get_player_by_name(death_info.killer_name)
        local victim_name = type(player) == "string" and player or (player and player.get_player_name and player:get_player_name()) or name
        if death_info.killer_name ~= victim_name then
            local kdata = (killer_player and killer_player:is_player() and deathstats.get_player_data(killer_player))
                or deathstats.get_player_data(death_info.killer_name)
                or deathstats.load_player_stats(death_info.killer_name)
            if kdata then
                kdata.current_run.players_killed = (kdata.current_run.players_killed or 0) + 1
                kdata.current_run.killstreak = (kdata.current_run.killstreak or 0) + 1
                kdata.current_run.players_slain = kdata.current_run.players_slain or {}
                kdata.current_run.players_slain[victim_name] = (kdata.current_run.players_slain[victim_name] or 0) + 1

                kdata.lifetime.players_killed = (kdata.lifetime.players_killed or 0) + 1
                kdata.lifetime.players_slain = kdata.lifetime.players_slain or {}
                kdata.lifetime.players_slain[victim_name] = (kdata.lifetime.players_slain[victim_name] or 0) + 1

                -- Check if killer had an active vendetta against the victim
                if deathstats.config.enable_revenge ~= false and kdata.current_run.vendetta_target == victim_name then
                    kdata.current_run.revenges = (kdata.current_run.revenges or 0) + 1
                    kdata.lifetime.revenges = (kdata.lifetime.revenges or 0) + 1
                    kdata.current_run.vendetta_target = nil

                    if deathstats.config.announce_revenge ~= false then
                        core.chat_send_all(core.colorize(deathstats.colors.text_gold, "[DeathStats] ") ..
                            core.colorize(deathstats.colors.text_crimson, "REVENGE! ") ..
                            core.colorize(deathstats.colors.text_gold, death_info.killer_name) ..
                            core.colorize(deathstats.colors.text_white, " has avenged their death and slain ") ..
                            core.colorize(deathstats.colors.text_crimson, victim_name) ..
                            core.colorize(deathstats.colors.text_white, "!"))
                    end
                end

                deathstats.save_player_stats(death_info.killer_name)
            end

            -- Set vendetta target on the victim for their upcoming life
            if deathstats.config.enable_revenge ~= false and data and data.current_run then
                data.current_run.vendetta_target = death_info.killer_name
                deathstats.save_player_stats(victim_name)
            end
        end
    end
end

