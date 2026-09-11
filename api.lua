--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local S = core.get_translator(core.get_current_modname())
local F = core.formspec_escape
local copy = table.copy
local atan2 = math.atan2 or math.atan

deathstats = {
    modpath = core.get_modpath("deathstats") or ".",
    storage = core.get_mod_storage(),
    config = {
        enable_sounds = core.settings:get_bool("deathstats_enable_sounds", true),
        enable_camera = core.settings:get_bool("deathstats_enable_camera", true),
        enable_animation = core.settings:get_bool("deathstats_enable_animation", true),
        enable_limb_fractures = core.settings:get_bool("deathstats_enable_limb_fractures",
            core.settings:get_bool("deathstats_enable_fall_fractures", true)),
        enable_fall_fractures = core.settings:get_bool("deathstats_enable_fall_fractures",
            core.settings:get_bool("deathstats_enable_limb_fractures", true)),
        animation_duration = tonumber(core.settings:get("deathstats_animation_duration")) or 2.4,
        blood_splatter_opacity = tonumber(core.settings:get("deathstats_blood_opacity")) or 240,
        formspec_side = core.settings:get("deathstats_formspec_side") or "right",
        banner_texture = "deathstats_you_died.png",
        orbit_radius = tonumber(core.settings:get("deathstats_orbit_radius")) or 3.2,
        orbit_height = tonumber(core.settings:get("deathstats_orbit_height")) or 1.5,
        orbit_speed = tonumber(core.settings:get("deathstats_orbit_speed")) or 0.4,
        enable_corpse_particles = core.settings:get_bool("deathstats_enable_corpse_particles", true),
        enable_scoreboard = core.settings:get_bool("deathstats_enable_scoreboard", true),
        scoreboard_key = core.settings:get("deathstats_scoreboard_key") or "zoom",
        time_format = core.settings:get("deathstats_time_format") or "24h",
        scoreboard_update_interval = tonumber(core.settings:get("deathstats_scoreboard_update_interval")) or 1.0,
        scoreboard_suppress_chat = core.settings:get_bool("deathstats_scoreboard_suppress_chat", true),
        afk_timeout = tonumber(core.settings:get("deathstats_afk_timeout")) or 120,
    },
    -- Common & Reusable Color Palette for UI Formspecs and HUD Elements
    colors = {
        -- Base & Backdrop
        transparent = "#00000000",
        card_sidebar = "#100808db",
        card_modal = "#121218f2",
        card_panel = "#1b1b24",
        card_inset = "#1f0507dd",
        row_alt = "#242430",
        tab_bar_bg = "#181822",
        tab_bar_sep = "#3a3a4c",

        -- Accents & Framing
        crimson_border = "#991111",
        crimson_glow = "#ff4444",
        active_strip = "#ff4444",

        -- Text & Labels
        text_gold = "#eeddaa",
        text_crimson = "#ff9999",
        text_white = "#ffffff",
        text_muted = "#b5b5c8",
        text_ping_good = "#44ee44",
        text_ping_warn = "#eeee44",
        text_ping_bad = "#ee4444",
        text_dead = "#997777",
        text_afk = "#ddbb55",

        -- Primary Action Button (TRY AGAIN / Respawn)
        btn_primary_bg = "#881111",
        btn_primary_hover_bg = "#aa1818",
        btn_primary_border = "#ff4444",
        btn_primary_hover_border = "#ff7777",
        btn_primary_text = "#ffffff",

        -- Secondary Action Button (MORE STATS / Back)
        btn_secondary_bg = "#242028",
        btn_secondary_hover_bg = "#38323e",
        btn_secondary_border = "#5a5060",
        btn_secondary_hover_border = "#8a8098",
        btn_secondary_text = "#eeddaa",

        -- Active Navigation Tab
        tab_active_bg = "#a81818",
        tab_active_hover_bg = "#c02020",
        tab_active_border = "#ff5555",
        tab_active_hover_border = "#ff7777",
        tab_active_text = "#ffffff",

        -- Inactive Navigation Tab
        tab_inactive_bg = "#252530",
        tab_inactive_hover_bg = "#383848",
        tab_inactive_border = "#4a4a60",
        tab_inactive_hover_border = "#7a7a94",
        tab_inactive_text = "#b5b5c8",

        -- HUD text colors (numeric 0xRRGGBB)
        hud_white = 0xFFFFFF,
        hud_soft_white = 0xEEEEEE,
        hud_gold = 0xFFD700,
        hud_crimson = 0xFF6666,
        hud_muted = 0xAAAAAA,
        hud_cyan = 0x66DDFF,
        hud_green = 0x55FF88,
        hud_ping_good = 0x44EE44,
        hud_ping_warn = 0xEEEE44,
        hud_ping_bad = 0xEE4444,
        hud_dead = 0x997777,
        hud_afk = 0xDDBB55,
    },
    -- Shared State Tracking Variables & Tables
    active_huds = {},
    active_animations = {},
    active_scoreboard_huds = {},
    scoreboard_states = {},
    open_scoreboard_formspecs = {},
    scoreboard_bg_cache = {},
    registered_columns = {},
    last_activity = {},
    player_last_pos = {},
    player_last_look = {},
    dead_players = {},
    player_camera_data = {},
    is_respawning = {},
    players = {},
    recent_punches = {},
    recent_falls = {},
    recent_starvations = {},
    recent_dehydrations = {},
    respawn_immunity = {},
    left_players = {},
    compat_hunger = {},
    compat_skins = {},
}

-- ==========================================
-- Internal Helper Utilities
-- ==========================================

--- Check if a player is currently connected and active on the server
---@param player_or_name ObjectRef|string The player object or player name
---@return boolean is_online True if player is actively connected and not leaving/offline
function deathstats.is_player_online(player_or_name)
    if not player_or_name then return false end
    local name = (type(player_or_name) == "string") and player_or_name or
        (player_or_name.get_player_name and player_or_name:get_player_name())
    if not name or name == "" then return false end
    if deathstats.left_players[name] then return false end

    local p = core.get_player_by_name(name)
    if not p or not p:is_player() then return false end
    return true
end

--- Cancel any player momentum / velocity safely across Luanti engine versions
--- Uses modern player:get_velocity() / player:add_velocity() without triggering deprecation warnings
---@param player ObjectRef The player object
function deathstats.zero_player_velocity(player)
    if not player then return end
    local v
    if player.get_velocity then
        v = player:get_velocity()
    elseif player.get_player_velocity then
        v = player:get_player_velocity()
    end
    if v and (v.x ~= 0 or v.y ~= 0 or v.z ~= 0) then
        if player.add_velocity then
            player:add_velocity(vector.multiply(v, -1))
        elseif player.add_player_velocity then
            player:add_player_velocity(vector.multiply(v, -1))
        end
    elseif player.set_velocity and not player:is_player() then
        player:set_velocity(vector.zero())
    end
end

--- Helper to safely truncate strings to prevent UI overflow
---@param str string|nil The input string to truncate
---@param max_len number The maximum allowable character length
---@return string The truncated string with ellipsis or original string
function deathstats.truncate_str(str, max_len)
    if not str or str == "" then return "None" end
    if #str <= max_len then return str end
    return str:sub(1, max_len - 3) .. "..."
end

--- Create an empty statistics table structure with default zeroed counters
---@return table stats New statistics table containing metrics for mining, combat, crafting, and survival
function deathstats.create_empty_stats()
    return {
        blocks_mined = 0,
        blocks_placed = 0,
        ores_mined = {},       -- [node_name] = count
        total_ores = 0,
        damage_taken = 0,
        damage_dealt = 0,
        mobs_killed = 0,
        mobs_slain = {},       -- [mob_name] = count
        players_killed = 0,
        items_crafted = 0,
        items_consumed = 0,
        distance_traveled = 0,
        time_alive = 0,
        deaths = 0,
        last_cause = "None",
        last_weapon = "None",
        last_killer = "None",
    }
end

-- ==========================================
-- General Purpose String & Math Utilities
-- ==========================================

--- Format a duration in seconds into a human-readable time string (e.g. "1d 2h 3m" or "45s")
---@param sec number The total elapsed duration in seconds
---@return string The formatted human-readable time string
function deathstats.format_time(sec)
    if not sec or sec <= 0 then
        return "0s"
    end
    sec = math.floor(sec)
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    local minutes = math.floor((sec % 3600) / 60)
    local seconds = sec % 60

    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, seconds)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds)
    else
        return string.format("%ds", seconds)
    end
end

--- Format large integer numbers with standard comma thousand separators (e.g. 1,234,567)
---@param n number The raw numeric value to format
---@return string The formatted number with comma separators
function deathstats.format_number(n)
    if not n then return "0" end
    local left, num, right = string.match(tostring(math.floor(n)), '^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

--- Convert an internal node name or item name into a clean, human-readable title
--- Retrieves clean description from registered item definition, or falls back to capitalized name
---@param item_name string The raw registered technical item or node name (e.g. "default:stone_with_iron")
---@return string The sanitized, capitalized human-readable title (e.g. "Iron Ore")
function deathstats.format_name(item_name)
    if not item_name or item_name == "" then
        return S("Unknown")
    end
    -- Check if registered item has a description
    local def = core.registered_items[item_name]
    local desc = def and (def.short_description or def.description)
    if desc and desc ~= "" then
        -- Only take first line of multiline description and strip color/translation escapes
        desc = desc:match("^[^\r\n]+") or desc
        desc = core.strip_colors(desc)
        desc = desc:gsub("\27%b()", ""):gsub("\27.", ""):match("^%s*(.-)%s*$")
        if desc and desc ~= "" then
            return desc
        end
    end

    -- Fallback: extract identifier part after colon and format with spaces and title case
    local sub = string.match(item_name, ":(.+)$") or item_name
    sub = sub:gsub("_", " ")
    return (sub:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

--- Safely get the item name from an ItemStack, itemstring, or table without assuming Lua type.
--- In Luanti C++ engine, ItemStacks are userdata, while mock environments may pass tables or strings.
---@param stack any The ItemStack (userdata), itemstring, or table representation
---@return string name The item name, or "" if empty or nil
function deathstats.get_stack_name(stack)
    if not stack then
        return ""
    end
    local t = type(stack)
    if t == "string" then
        return stack:match("^([^%s]+)") or ""
    elseif t == "userdata" or t == "table" then
        if stack.get_name then
            local name = stack:get_name()
            if type(name) == "string" then
                return name
            end
        end
        if t == "table" and stack.name then
            return tostring(stack.name)
        end
    end
    return ""
end

--- Check whether an item stack or slot is empty, supporting userdata ItemStack, table, string, or nil.
---@param stack any The ItemStack (userdata), itemstring, or table representation
---@return boolean empty True if the stack is empty, contains no items, or is nil/""
function deathstats.is_stack_empty(stack)
    if not stack then
        return true
    end
    local t = type(stack)
    if t == "string" then
        return stack == "" or stack:match("^%s*$") ~= nil
    elseif t == "userdata" or t == "table" then
        if stack.is_empty then
            return stack:is_empty() == true
        end
        if stack.get_name then
            return stack:get_name() == ""
        end
        if t == "table" and stack.name then
            return stack.name == "" or (stack.count ~= nil and stack.count <= 0)
        end
    end
    return false
end

--- Safely convert an ItemStack, table, or string to a pure string representation for serialization.
--- Guaranteed to return a pure string (never userdata) so core.serialize never fails with unsupported type.
--- In Luanti, ItemStack:to_string() preserves count, wear, and item metadata.
---@param stack any The ItemStack (userdata), itemstring, or table representation
---@return string itemstring The item serialized to string (empty string "" if empty)
function deathstats.stack_to_string(stack)
    if not stack then
        return ""
    end
    local t = type(stack)
    if t == "string" then
        return stack
    elseif t == "userdata" or t == "table" then
        if stack.to_string then
            local str = stack:to_string()
            if type(str) == "string" then
                return str
            end
        end
        if stack.get_name then
            local n = stack:get_name()
            local cnt = stack.get_count and stack:get_count() or 1
            local cnt_str = (cnt and cnt > 1) and (" " .. tostring(cnt)) or ""
            return tostring(n or "") .. cnt_str
        end
        if t == "table" and stack.name then
            local cnt = stack.count and stack.count > 1 and (" " .. tostring(stack.count)) or ""
            return tostring(stack.name) .. cnt
        end
    end
    return ""
end

--- Check whether an entire inventory list is empty
---@param inv InvRef The inventory reference
---@param list_name string The inventory list name
---@return boolean is_empty True if list is empty or has no items
function deathstats.is_inventory_list_empty(inv, list_name)
    if not inv then return true end
    if inv.is_empty then
        return inv:is_empty(list_name) == true
    end
    if inv.get_list then
        local list = inv:get_list(list_name)
        if not list or #list == 0 then return true end
        for _, st in ipairs(list) do
            if not deathstats.is_stack_empty(st) then
                return false
            end
        end
        return true
    end
    return true
end

--- Serialize an inventory list into an array of itemstrings
---@param inv InvRef The inventory reference
---@param list_name string The inventory list name
---@return string[] items Array of itemstrings
function deathstats.serialize_inventory_list(inv, list_name)
    local items = {}
    if not inv or not inv.get_list then return items end
    local list = inv:get_list(list_name)
    if not list then return items end
    for idx, item in ipairs(list) do
        if item and not deathstats.is_stack_empty(item) then
            items[idx] = deathstats.stack_to_string(item)
        else
            items[idx] = ""
        end
    end
    return items
end

--- Deserialize an array of itemstrings back into an inventory list
---@param inv InvRef The inventory reference
---@param list_name string The inventory list name
---@param items string[] Array of itemstrings
function deathstats.deserialize_inventory_list(inv, list_name, items)
    if not inv or not inv.set_stack or not items then return end
    local list_size = (inv.get_size and inv:get_size(list_name)) or 0
    if inv.set_size and list_size < #items then
        inv:set_size(list_name, #items)
        list_size = #items
    end
    local max_idx = math.max(#items, list_size)
    for idx = 1, max_idx do
        local stack_str = items[idx] or ""
        inv:set_stack(list_name, idx, stack_str)
    end
end


---@param player ObjectRef The player object who should receive the audio effect
function deathstats.play_death_sound(player)
    if not deathstats.config.enable_sounds or not player then
        return
    end
    local player_name = player:get_player_name()
    core.sound_play("deathstats_death", {
        to_player = player_name,
        gain = 1.0,
        pitch = 1.0,
    })
end

--- Format a projectile entity name into a clean weapon display title
---@param ent_name string|nil The registered technical projectile entity name
---@return string The human-readable weapon or projectile description
function deathstats.format_projectile_name(ent_name)
    if not ent_name or ent_name == "" then return S("Arrow / Projectile") end
    if ent_name == "x_bows:arrow_entity" or ent_name:find("arrow") then
        return S("Bow & Arrow")
    elseif ent_name == "x_obsidianmese:sword_projectile" or ent_name:find("sword_projectile") then
        return S("Sword Projectile")
    end
    return deathstats.format_name(ent_name)
end

--- Extract the real player or entity behind an attack, punch, or projectile
--- Supports direct player punch, x_bows arrows, x_obsidianmese sword projectiles, and standard projectile mods
---@param puncher ObjectRef|nil The raw puncher object passed to on_punchplayer
---@return ObjectRef|nil real_attacker The actual player or mob entity responsible for the attack
---@return boolean is_player True if the attacker was a player (either directly or via shooting a projectile)
---@return string|nil projectile_name The registered entity name of the projectile if fired from distance
---@return string|nil weapon_name The technical item name of the wielded weapon used by a player
function deathstats.resolve_puncher_player(puncher)
    if not puncher then
        return nil, false, nil, nil
    end

    -- 1. Direct player punch
    if puncher:is_player() then
        local item = puncher:get_wielded_item()
        local iname = deathstats.get_stack_name(item)
        if iname == "" then iname = nil end
        return puncher, true, nil, iname
    end

    -- 2. Lua Entity (arrow, sword projectile, or mob)
    local luaent = puncher:get_luaentity()
    if luaent then
        local ent_name = luaent.name or ""
        local shooter = nil

        -- Check common shooter/owner attributes used by x_bows, x_obsidianmese, mobs_redo, etc.
        if luaent._user and type(luaent._user.is_player) == "function" and luaent._user:is_player() then
            shooter = luaent._user
        elseif luaent._user_name and type(luaent._user_name) == "string" then
            shooter = core.get_player_by_name(luaent._user_name)
        elseif luaent.shooter and type(luaent.shooter.is_player) == "function" and luaent.shooter:is_player() then
            shooter = luaent.shooter
        elseif luaent._shooter and type(luaent._shooter.is_player) == "function" and luaent._shooter:is_player() then
            shooter = luaent._shooter
        elseif luaent.owner and type(luaent.owner.is_player) == "function" and luaent.owner:is_player() then
            shooter = luaent.owner
        elseif luaent.owner_id and type(luaent.owner_id) == "string" then
            shooter = core.get_player_by_name(luaent.owner_id)
        elseif luaent.source_player and type(luaent.source_player.is_player) == "function" and luaent.source_player:is_player() then
            shooter = luaent.source_player
        end

        if shooter and shooter:is_player() then
            return shooter, true, ent_name, nil
        end

        -- Check if shooter was a mob entity (e.g. skeleton firing an arrow)
        local mob_shooter = luaent.shooter or luaent._shooter or luaent.owner or luaent._user
        if mob_shooter and mob_shooter.get_luaentity and mob_shooter:get_luaentity() then
            return mob_shooter, false, ent_name, nil
        end

        -- Not a known projectile from a player/mob; return the entity itself
        return puncher, false, ent_name, nil
    end

    return puncher, false, nil, nil
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
    end

    if type(last_life) ~= "table" then
        last_life = deathstats.create_empty_stats()
    else
        last_life.ores_mined = last_life.ores_mined or {}
        last_life.mobs_slain = last_life.mobs_slain or {}
    end

    local data = {
        name = player_name,
        life_start_time = core.get_gametime(),
        last_pos = nil,
        current_run = deathstats.create_empty_stats(),
        lifetime = lifetime,
        last_life = last_life,
    }
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
    local name = player:get_player_name()
    local data = deathstats.players[name]
    if not data then
        data = deathstats.load_player_stats(name)
    end
    if data and not data._meta_last_life_checked and (not data.last_life or not data.last_life.last_cause or data.last_life.last_cause == "None" or (data.last_life.time_alive or 0) == 0) then
        data._meta_last_life_checked = true
        local meta = player:get_meta()
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
---@param player ObjectRef The player who died
---@param death_info table The death analysis table containing reason_text, killer_name, weapon, and funny_note
function deathstats.record_player_death(player, death_info)
    local data = deathstats.get_player_data(player)
    if not data then return end

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
    data.last_life = snapshot

    -- Reset current run for the next life
    data.current_run = deathstats.create_empty_stats()
    data.life_start_time = core.get_gametime()

    -- Persist immediately to Mod Storage and Player Metadata
    deathstats.save_player_stats(player:get_player_name())
    local meta = player:get_meta()
    if meta then
        meta:set_string("deathstats:death_active", "1")
        meta:set_string("deathstats:last_life", core.serialize(data.last_life))
        meta:set_string("deathstats:death_info", core.serialize(death_info))
        meta:set_string("deathstats:lifetime", core.serialize(data.lifetime))
    end

    -- If slain by another player (direct or via projectile), credit the killer
    if death_info.is_player and death_info.killer_name then
        local killer_player = core.get_player_by_name(death_info.killer_name)
        local victim_name = player:get_player_name()
        if killer_player and killer_player:is_player() and death_info.killer_name ~= victim_name then
            local kdata = deathstats.get_player_data(killer_player)
            if kdata then
                kdata.current_run.players_killed = kdata.current_run.players_killed + 1
                kdata.lifetime.players_killed = kdata.lifetime.players_killed + 1
                deathstats.save_player_stats(death_info.killer_name)
            end
        end
    end
end

-- ==========================================
-- Death Reason Analysis & Humorous Epitaphs
-- ==========================================

-- Funny epitaph notes organized by death cause (all wrapped in S() for translation)
deathstats.funny_notes = {
    pvp = {
        S("Next time, try hitting THEM instead."),
        S("They say violence isn't the answer, but it certainly ended this debate."),
        S("Your combat strategy needs a complete restructuring."),
        S("Look on the bright side: at least their weapon has slightly more wear now."),
        S("Skill issue? Or just lag? We'll tell everyone it was lag."),
        S("Respawn, find them, and negotiate terms of surrender."),
        S("A tactical nap in the middle of battle is rarely effective."),
        S("You brought enthusiasm to a sword fight."),
        S("Your block button isn't just decorative."),
        S("PvP stands for Player versus Player, not Player versus Floor."),
        S("Have you tried moving out of the way of the sharp objects?"),
        S("They clearly had a better gaming chair."),
        S("Combat log: 0 hits landed, 1 dignity lost."),
        S("You fought bravely, until you immediately stopped doing that."),
        S("Did you drop your weapon or did you just surrender with style?"),
        S("Your opponent sends their heartfelt compliments for the free loot."),
        S("Maybe pacifism is your true calling."),
        S("You made a wonderful practice dummy for their combo."),
        S("A valiant effort, according to nobody who was watching."),
        S("They didn't even have to use their secondary weapon."),
        S("Next time, consider attacking while facing in their direction."),
        S("That wasn't a duel, that was an eviction notice."),
        S("Your armor looked very shiny right before it shattered."),
        S("Rumor has it they only used one hand to defeat you."),
        S("Tactical retreat was an option, just so you know."),
        S("You donated all your inventory to a very grateful warrior."),
        S("Critical hit! Unfortunately, it wasn't yours."),
        S("A legendary battle, remembered strictly by the victor."),
        S("You zigged when you definitely should have zagged."),
        S("Your health bar disappeared faster than your confidence."),
        S("Next time, try bringing armor with actual durability."),
        S("They thanked you for the target practice."),
        S("The duel was short, sweet, and entirely one-sided."),
        S("Combat tip: the pointy end goes into the OTHER player."),
        S("Respawning now. Time for an epic revenge plot, or another dirt nap."),
    },
    mob = {
        S("Local fauna remains unimpressed by your presence."),
        S("You were thoroughly outmaneuvered by a bunch of pixels."),
        S("Darwin would like to have a word with you."),
        S("You brought a tool to a monster fight."),
        S("The monsters are currently celebrating at the tavern."),
        S("Don't take it personally. They hate everyone equally."),
        S("Pro tip: running away is an ancient and honorable martial art."),
        S("Defeated by an enemy with a mob script shorter than a tweet."),
        S("The monsters didn't even break a sweat. Do monsters sweat?"),
        S("You were outsmarted by an opponent without a cerebral cortex."),
        S("They didn't just bite you, they insulted your entire lineage."),
        S("The local wildlife has voted you off the island."),
        S("Next time, light up the cave before taking a nap."),
        S("You are now officially part of the food chain, near the bottom."),
        S("Even the weakest critter in the dungeon is laughing right now."),
        S("Turns out monsters don't respect your personal space."),
        S("You cornered yourself. The monster was just doing its job."),
        S("Monster morale increased by 100%. Player morale decreased to 0%."),
        S("A creature with three lines of code just dismantled your career."),
        S("They heard you digging from three chunks away."),
        S("Did you try offering them a peaceful peace treaty?"),
        S("That beast will be bragging to its friends all weekend."),
        S("You tried to pet the danger, didn't you?"),
        S("Never bring a carrot to a monster showdown."),
        S("Your shield was in your inventory, cheering you on."),
        S("The dungeon boss is taking notes on how easily you fell."),
        S("Nature is healing, mostly by eliminating you."),
        S("Aggro radius: 10 meters. Survival radius: apparently 0 meters."),
        S("They swarmed you like shoppers on Black Friday."),
        S("You were defeated by something that cannot even open doors."),
        S("The monster didn't even need a critical hit."),
        S("Tip: swinging wildly into the darkness rarely hits the target."),
        S("They ate your lunch and then they ate your health points."),
        S("A glorious demise at the hands of a glorified polygon."),
        S("Next time, bring torches, armor, and maybe a bodyguard."),
    },
    fall = {
        S("It wasn't the fall that got you. It was the sudden stop at the bottom."),
        S("Gravity: 1. You: 0."),
        S("You believed you could fly. Physics respectfully disagreed."),
        S("Next time, pack a parachute or check the depth first."),
        S("High altitude sightseeing: 10/10. Landing: 0/10."),
        S("Look down before you step. Ancient wisdom, highly recommended."),
        S("Terminal velocity achieved. Unfortunately, so was terminal outcome."),
        S("The ground is the most undefeated opponent in history."),
        S("You just discovered a rapid underground transit method."),
        S("Newton sends his warmest mathematical regards."),
        S("That was not a shortcut, that was a cliff."),
        S("Next time, place water at the bottom BEFORE jumping."),
        S("You descended gracefully, right until the abrupt deceleration."),
        S("Gravity remains 100% reliable and completely unforgiving."),
        S("Cliff edges: they sneak up on you when you don't press sneak."),
        S("Congratulations on discovering the fastest way down."),
        S("The view was spectacular for about three seconds."),
        S("Parachute not found. Landing gear: nonexistent."),
        S("You thought the water was deep enough. It was 1 node deep."),
        S("Free falling is easy. Stopping safely is the hard part."),
        S("Physics called: your kinetic energy was fully absorbed by stone."),
        S("Next time, hold shift like your life depends on it. Because it does."),
        S("You tested the canyon's depth with your face."),
        S("An impressive swan dive with a catastrophic score on the landing."),
        S("The cliff did not move. You did."),
        S("Gravity is a harsh mistress with zero sense of humor."),
        S("You aimed for the hay bale and hit pure bedrock."),
        S("Pushed your luck over the ledge, and luck stepped aside."),
        S("Vertical exploration gone horribly wrong."),
        S("The ground welcomed you with open, solid cobblestone."),
        S("Did you trip over your own boots or was that deliberate?"),
        S("That was one giant leap for mankind, and zero survival for you."),
        S("Look on the bright side: you reached the bottom in record time."),
        S("Air resistance was insufficient to break your fall."),
        S("Next time, build stairs instead of taking the express elevator."),
    },
    lava = {
        S("Lava is not warm soup. Do not bathe in the forbidden salsa."),
        S("Crispy on the outside, thoroughly incinerated on the inside."),
        S("Diamonds are fireproof. You, unfortunately, are not."),
        S("You have officially become thermal energy for the ecosystem."),
        S("Hot take: molten rock is hot."),
        S("At least you don't have to worry about cold weather anymore."),
        S("The floor was literal lava and you lost the game."),
        S("A warm mineral bath, recommended by zero dermatologists."),
        S("You tested the swimming mechanics of liquid magma."),
        S("Diamonds mined: 8. Diamonds saved from the lava: 0."),
        S("That wasn't orange juice, but thanks for checking."),
        S("Cooking temperature: 1200 degrees. Doneness: completely vaporized."),
        S("Molten rock cares nothing for your enchanted armor."),
        S("You turned yourself into human fondue."),
        S("Digging straight down: classic, timeless, and completely fatal."),
        S("A spectacular glow, followed by absolute silence."),
        S("Water bucket was in hotbar slot 9. You pressed slot 8."),
        S("You took the term 'fire resistance' as a suggestion."),
        S("The volcano welcomes its latest voluntary offering."),
        S("One does not simply walk into molten lava and expect to survive."),
        S("Your gear went up in smoke before your body even hit the bottom."),
        S("Molten rock: the ultimate garbage disposal for reckless miners."),
        S("Liquid hot magma claims another brave, foolish adventurer."),
        S("You tried to bridge across without sneaking. Bold decision."),
        S("That sizzling sound was your entire inventory disappearing."),
        S("A hot bath sounded nice, but this exceeded expectations."),
        S("Instant cremation, zero paperwork required."),
        S("Next time, carry an obsidian bridge, not your best gear."),
        S("Molten rock has a 100% win rate against reckless miners."),
        S("You are now well-done. Actually, you are well beyond well-done."),
    },
    fire = {
        S("Stop, drop, and... oh, too late."),
        S("Playing with matches in a flammable universe. Bold strategy."),
        S("Smokey Bear is shaking his head in disappointment right now."),
        S("You lit up the room! Briefly. Very briefly."),
        S("Spontaneous human combustion: not just a myth anymore."),
        S("Fire is friendly right up until it touches your shirt."),
        S("You were the hottest thing in the cavern, literally."),
        S("Pyrotechnics display: spectacular. Survival rate: zero."),
        S("Did someone order extra crispy explorer?"),
        S("Flint and steel are tools, not toys. Lesson learned."),
        S("You ran around in circles hoping the flames would get dizzy."),
        S("A campfire is for cooking marshmallows, not yourself."),
        S("Fire safety tip: water extinguishes fire. Air feeds it."),
        S("You turned yourself into a human torch without the superpower part."),
        S("Burning calories is good; burning everything else is bad."),
        S("The heat was on, and you couldn't stand the kitchen."),
        S("Ash to ash, dust to dust, wooden house to a pile of rust."),
        S("Next time, check the wind direction before using a flint."),
        S("You danced with fire and fire won in the first round."),
        S("Smoke inhalation was just the preview; the flames were the feature."),
        S("Extinguisher not found. Dignity extinguished instead."),
        S("Friction caused sparks. Sparks caused fire. Fire caused respawn."),
        S("You were smokin' hot, but not in a flattering way."),
        S("Never try to hug a forest fire."),
        S("A warm campfire story, except you were the campfire."),
    },
    drown = {
        S("Humans need oxygen. Water has oxygen, but lungs don't do chemistry like that."),
        S("Sleeping with the digital fishes."),
        S("You forgot the golden rule: Breathe in, breathe out. Underwater: DO NOT."),
        S("Gills are not currently an unlockable perk on this server."),
        S("Submarine mode: Failed successfully."),
        S("Air bubbles: gone. Lung capacity: exceeded. Regrets: maximum."),
        S("Next time, look up before swimming down."),
        S("You found treasure, but forgot you needed oxygen to spend it."),
        S("Water is life, except when it fills your respiratory system."),
        S("Scuba gear is not craftable with cobblestone."),
        S("You tried to hold your breath until weekend. Unrealistic goal."),
        S("The surface was only three blocks away. Three very long blocks."),
        S("Fish swim. Rocks sink. You behaved remarkably like a rock."),
        S("Bubble counter reached zero. Panic levels reached maximum."),
        S("Deep sea diving without a breathing tube is rarely a long career."),
        S("Placing a door underwater was an option, just saying."),
        S("The ocean claims another sailor of dry land."),
        S("You drank too much of the ocean too quickly."),
        S("Deep diving is fun until the lights go out."),
        S("Aqua-aerobics class has been permanently cancelled."),
        S("Your lungs have formally filed a complaint against your navigation."),
        S("Water exploration: 10/10. Surface return journey: 0/10."),
        S("Swimming lessons are highly recommended for your next life."),
        S("You became an artificial reef in under two minutes."),
        S("Next time, come up for air before checking your inventory."),
    },
    suffocate = {
        S("Becoming one with the geology wasn't meant to be taken literally."),
        S("Gravel does not respect personal space boundaries."),
        S("Walls are meant for walking around, not phasing inside."),
        S("You discovered the interior decor of solid stone."),
        S("Sand has no concept of mercy or structural integrity."),
        S("Physics tip: two objects cannot occupy the same coordinate space."),
        S("You were deeply moved by the cave-in. Literally buried by it."),
        S("Gravel: the quietest assassin in the subterranean world."),
        S("A sudden collapse of geology and good decision-making."),
        S("You dug the ceiling and the ceiling hugged you back."),
        S("Suffocation: nature's way of telling you to carry a shovel."),
        S("You are now an honorary fossil for future archaeologists to discover."),
        S("Teleported straight into a solid wall. Quantum mechanics is tough."),
        S("Solid stone is very firm, opaque, and entirely unbreathable."),
        S("The mine collapsed, and so did your life expectations."),
        S("Never dig straight up. Every loading screen warned you."),
        S("Sand avalanches: sudden, silent, and suffocating."),
        S("You became load-bearing masonry for the mountain above."),
        S("The blocks above were just waiting for you to look up."),
        S("Burying your head in the sand: taken to its logical extreme."),
        S("Gravel drop: 100% accuracy, 0% breathable oxygen."),
        S("You found the center of the earth, from the inside of a stone block."),
        S("Next time, place a torch under falling gravel to survive."),
        S("Trapped between a rock and another, much heavier rock."),
        S("Solid masonry makes for a very poor blanket."),
    },
    starve = {
        S("You starved with an inventory full of cobblestone and regret."),
        S("Your stomach staged a swift and successful mutiny."),
        S("Forgot to eat? In this economy?!"),
        S("A sandwich would have prevented this entire tragic sequence."),
        S("The hunger bar is not a high score counter. Fill it up!"),
        S("You died on an empty stomach. Your grandmother is weeping."),
        S("All those diamonds and not a single loaf of bread to show for it."),
        S("Your digestive system has officially given up on you."),
        S("Nutritional deficiency level: catastrophic biological shutdown."),
        S("Next time, pack snacks before venturing into deep caverns."),
        S("Apples grow on trees. Trees were literally right above you."),
        S("You sprinted everywhere until your metabolism gave out."),
        S("Hunger strike successful: you are no longer hungry, or alive."),
        S("Even a zombie eats better than you did in this life."),
        S("You traded your lunch money for iron ingots."),
        S("Zero calories consumed. Zero life points remaining."),
        S("A single baked potato would have saved the world."),
        S("You ignored the grumbling stomach until it grumbled its last grumble."),
        S("Starvation in a world made of edible apples and wheat. Remarkable."),
        S("Diet plan review: 0 stars. Side effects included total demise."),
        S("Sprinting on an empty stomach: highly discouraged by doctors."),
        S("You had three stacks of cooked meat in a chest at home."),
        S("The hunger monster inside you won the ultimate argument."),
        S("Remember: food goes into the mouth, health goes up. Simple math."),
        S("You perished of malnutrition while surrounded by wild berries."),
        S("Sprinted a marathon, forgot to pack a sandwich."),
        S("Burned calories at Olympic speeds until none were left."),
        S("Ran until your stomach was completely empty."),
    },
    starve_sprint = {
        S("You sprinted everywhere until your metabolism gave out."),
        S("Sprinting on an empty stomach: highly discouraged by doctors."),
        S("Sprinted a marathon, forgot to pack a sandwich."),
        S("Burned calories at Olympic speeds until none were left."),
        S("Ran until your stomach was completely empty."),
    },
    thirst = {
        S("Water, water everywhere, nor any drop to drink."),
        S("You dried up faster than a puddle on scorching sand."),
        S("Dehydration level: 100%. Vitality level: 0%."),
        S("Forgot to drink? Even cacti manage to stay hydrated."),
        S("A single glass of water would have prevented this funeral."),
        S("You turned into a human mummy while staring at an ocean."),
        S("Your throat was drier than the desert at high noon."),
        S("Next time, bring a canteen instead of thirty iron ingots."),
        S("You ignored thirst until your bodily fluids resigned in protest."),
        S("Dehydration strikes again. Hydrate or diedrate!"),
        S("You carried five buckets of lava, but not one of water."),
        S("Dried out like an ancient raisin found behind the couch."),
        S("Your internal organs requested water. You gave them cobblestone."),
        S("Even fish know how to stay wet. Be more like fish."),
        S("Water fountain was ten meters away. Laziness level: lethal."),
        S("Hydro points hit zero. System shutdown inevitable."),
        S("You sprinted through the desert without a water flask."),
        S("Thirst took your life, but left your dignity equally parched."),
        S("Doctor's prescription: drink 8 cups of water a day, preferably while alive."),
        S("You turned to dust and blew away in the gentle breeze."),
        S("Total desiccation achieved. Achievement unlocked: Dried Sponge."),
        S("A canteen full of water weighs very little. Regret weighs a ton."),
        S("You fell victim to the ultimate summer heat wave."),
        S("Your tongue stuck to the roof of your mouth permanently."),
        S("Water is life. Literally."),
    },
    unknown = {
        S("Spontaneous biological failure. Cause: existence was too difficult."),
        S("The universe decided your subscription to life had expired."),
        S("Mistakes were made. Many of them."),
        S("Whatever happened, it looked painful from over here."),
        S("Press F to pay respects."),
        S("Even the coroner threw their hands up in confusion."),
        S("You somehow managed to break the laws of nature and health."),
        S("Cause of death: simply running out of hit points."),
        S("The game engine shrugs in profound bewilderment."),
        S("A mysterious end to an equally puzzling adventure."),
        S("It was a calculated risk, but math was never your strongest subject."),
        S("You ceased to function. Have you tried turning yourself off and on again?"),
        S("Not with a bang, but with a sudden, confusing whimper."),
        S("Whatever just happened, we're blaming it on lag."),
        S("Your character decided today was a good day to take a dirt nap."),
        S("An enigma wrapped in a mystery, covered in a death screen."),
        S("You encountered an unexpected error: Life.exe has stopped working."),
        S("The details are fuzzy, but the result is indisputably flat."),
        S("Even the server console doesn't know what you just did."),
        S("A tragic tale with no witness, no evidence, and no dignity."),
        S("You looked at danger and danger sneezed on you."),
        S("Some questions are better left unanswered. Like how you died just now."),
        S("A glitch in the matrix, or just exceptional clumsiness?"),
        S("The odds were one in a million. Unfortunately, you found the one."),
        S("You entered the room and the room decided you should leave."),
        S("Everything was going great until it immediately wasn't."),
        S("Your health bar took an early retirement."),
        S("Nobody saw anything, which is probably for the best."),
        S("A truly baffling sequence of unfortunate events."),
        S("Respawn, pretend it never happened, and never speak of it again."),
    }
}

--- Pick a random humorous epitaph note for the given death category
---@param category string The death category identifier (e.g. "pvp", "mob", "fall", "lava", etc.)
---@return string note A randomized witty or humorous epitaph quote
function deathstats.get_funny_note(category)
    local list = deathstats.funny_notes[category] or deathstats.funny_notes.unknown
    return list[math.random(#list)]
end

--- Extract name and description from an ObjectRef (Player, LuaEntity, or projectile)
--- Resolves real shooting player if entity is an arrow or sword projectile
---@param obj ObjectRef The attacker object reference
---@return string name The killer's identifier or username
---@return boolean is_player True if the resolved attacker is a player
---@return string entity_desc The human-readable title of the killer
---@return string|nil projectile_name The projectile entity name if launched remotely
function deathstats.resolve_entity_info(obj)
    if not obj then return "Unknown", false, "Unknown", nil end

    -- Check if this object is a projectile fired by a player or mob
    local real_attacker, is_p, proj_name = deathstats.resolve_puncher_player(obj)
    if is_p and real_attacker and real_attacker:is_player() then
        local pname = real_attacker:get_player_name()
        return pname, true, pname, proj_name
    end

    if obj:is_player() then
        local pname = obj:get_player_name()
        return pname, true, pname, nil
    end

    local luaent = obj:get_luaentity()
    if luaent then
        local raw_name = luaent.name or "mob"
        local ent_def = core.registered_entities[raw_name]
        local desc = (ent_def and ent_def.description)
            or (luaent._mcl_entity_name)
            or deathstats.format_name(raw_name)
        return raw_name, false, desc, proj_name
    end

    return "Creature", false, "Creature", nil
end

--- Get current satiation / hunger metrics for a player across all supported hunger mods
--- Delegated to deathstats.compat_hunger.get_player_satiation
---@param player ObjectRef The player object
---@return number|nil current The current hunger/satiation points
---@return number|nil max The maximum hunger/satiation capacity
---@return number|nil ratio The normalized saturation ratio from 0.0 (empty) to 1.0 (full)
---@return string|nil mod_name The technical identifier of the detected hunger framework
---@return boolean is_starving True if hunger is at or below the framework's starvation damage threshold
function deathstats.get_player_satiation(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.get_player_satiation then
        return deathstats.compat_hunger.get_player_satiation(player)
    end
    return nil, nil, nil, nil, false
end

--- Check if a player is in a starving state (satiation/hunger depleted)
--- Seamlessly integrates with hbhunger, hudbars, stamina, hunger_ng, mcl_hunger, and classic hunger
---@param player ObjectRef The player object
---@return boolean is_starving True if hunger level is at or below starvation threshold
function deathstats.is_player_starving(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.is_player_starving then
        return deathstats.compat_hunger.is_player_starving(player)
    end
    local _, _, _, _, is_starving = deathstats.get_player_satiation(player)
    return is_starving == true
end

--- Get hydration status and metrics for a player from thirsty mod
--- Delegated to deathstats.compat_hunger.get_player_hydration
---@param player ObjectRef The player object
---@return number|nil current Current hydro points (0-20)
---@return number|nil max Maximum hydration (20)
---@return number|nil ratio Normalized hydration ratio (0.0 to 1.0)
---@return string|nil mod_name Mod identifier ("thirsty")
---@return boolean is_dehydrated True if hydro points <= 0
function deathstats.get_player_hydration(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.get_player_hydration then
        return deathstats.compat_hunger.get_player_hydration(player)
    end
    return nil, nil, nil, nil, false
end

--- Check if player is dehydrated (thirst hydro depleted)
---@param player ObjectRef
---@return boolean
function deathstats.is_player_dehydrated(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.is_player_dehydrated then
        return deathstats.compat_hunger.is_player_dehydrated(player)
    end
    local _, _, _, _, is_dehydrated = deathstats.get_player_hydration(player)
    return is_dehydrated == true
end

--- Check if player was recently sprinting or sprint-stamina exhausted
--- Supports hbsprint, sprint_lite, unified_stamina, stamina
---@param player ObjectRef
---@return boolean
function deathstats.is_player_sprint_exhausted(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.is_player_sprint_exhausted then
        return deathstats.compat_hunger.is_player_sprint_exhausted(player)
    end
    return false
end

--- Deep environmental and state inspection fallback when engine reason table is nil or incomplete
--- Checks recent combat punches, falling velocity, surrounding nodes (lava, water, suffocation, fall, out-of-world)
---@param player ObjectRef The deceased player object
---@return table analysis The deduced death information table
function deathstats.inspect_surroundings_fallback(player)
    local pos = player:get_pos()
    local name = player:get_player_name()
    local eye_height = 1.625
    local props = player:get_properties()
    if props and props.eye_height then
        eye_height = props.eye_height
    end

    local head_pos = vector.new(pos.x, pos.y + eye_height, pos.z)
    local node_feet = core.get_node(pos)
    local node_head = core.get_node(head_pos)

    -- 1. Check recent PvP or Mob punch / projectile strike (within 3.5 seconds)
    local last_punch = deathstats.recent_punches[name]
    if last_punch and (core.get_gametime() - last_punch.time <= 3.5) then
        local attacker_name = last_punch.attacker_name
        local is_player = last_punch.is_player
        local attacker_desc = last_punch.attacker_desc
        if not attacker_name and last_punch.hitter then
            attacker_name, is_player, attacker_desc = deathstats.resolve_entity_info(last_punch.hitter)
        end
        attacker_name = attacker_name or "Unknown"
        attacker_desc = attacker_desc or attacker_name
        local cat = is_player and "pvp" or "mob"
        local wep = last_punch.tool_desc or "Bare Hands"
        if last_punch.projectile then
            wep = deathstats.format_projectile_name(last_punch.projectile)
        end
        local text = is_player
            and string.format("Slain by %s using %s", attacker_name, wep)
            or string.format("Slain by %s", attacker_desc)
        return {
            category = cat,
            killer_name = attacker_name,
            is_player = is_player,
            weapon = wep,
            reason_text = text,
            funny_note = deathstats.get_funny_note(cat),
        }
    end

    -- 2. Check out-of-world fall (below mapgen bounds)
    if pos.y < -30000 then
        return {
            category = "unknown",
            reason_text = S("Fell out of the world"),
            funny_note = deathstats.get_funny_note("unknown"),
        }
    end

    -- 3. Check lava immersion
    if node_feet.name:find("lava") or node_head.name:find("lava") then
        return {
            category = "lava",
            reason_text = S("Melted in searing lava"),
            funny_note = deathstats.get_funny_note("lava"),
        }
    end

    -- 4. Check fire / burning
    if node_feet.name:find("fire") or node_head.name:find("fire") then
        return {
            category = "fire",
            reason_text = S("Burned to ashes"),
            funny_note = deathstats.get_funny_note("fire"),
        }
    end

    -- 5. Check drowning (head submerged in water or liquid with no breath)
    local breath = player:get_breath()
    local in_water = node_head.name:find("water") or core.get_item_group(node_head.name, "water") ~= 0
    if in_water or (breath and breath <= 0) then
        return {
            category = "drown",
            reason_text = S("Drowned in deep water"),
            funny_note = deathstats.get_funny_note("drown"),
        }
    end

    -- 6. Check suffocation (head buried inside solid opaque node)
    local head_def = core.registered_nodes[node_head.name]
    if head_def and head_def.walkable and head_def.drawtype == "normal" and not node_head.name:find("air") then
        return {
            category = "suffocate",
            reason_text = S("Suffocated inside @1", deathstats.format_name(node_head.name)),
            funny_note = deathstats.get_funny_note("suffocate"),
        }
    end

    -- 7. Check high downward velocity recorded just before death
    local fall_speed = deathstats.recent_falls[name] or 0
    if fall_speed < -12.0 then
        return {
            category = "fall",
            reason_text = S("Fell from a high place"),
            funny_note = deathstats.get_funny_note("fall"),
        }
    end

    -- 8. Check dehydration / thirst (thirsty mod)
    local was_dehydrated = deathstats.is_player_dehydrated(player)
        or (deathstats.recent_dehydrations[name] and (core.get_gametime() - deathstats.recent_dehydrations[name] <= 3.5))
    if was_dehydrated then
        return {
            category = "thirst",
            reason_text = S("Died of dehydration"),
            funny_note = deathstats.get_funny_note("thirst"),
        }
    end

    -- 9. Check starvation (hbhunger, stamina, hunger_ng, hudbars, or inventory hunger)
    local was_starving = deathstats.is_player_starving(player)
        or (deathstats.recent_starvations[name] and (core.get_gametime() - deathstats.recent_starvations[name] <= 3.5))
    if was_starving then
        local note
        if deathstats.is_player_sprint_exhausted(player) then
            note = deathstats.get_funny_note("starve_sprint") or deathstats.get_funny_note("starve")
        else
            note = deathstats.get_funny_note("starve")
        end
        return {
            category = "starve",
            reason_text = S("Starved to death"),
            funny_note = note,
        }
    end

    -- 10. Fallback unknown
    return {
        category = "unknown",
        reason_text = "Died from mysterious causes",
        funny_note = deathstats.get_funny_note("unknown"),
    }
end

--- Main Death Cause Analyzer: parses engine death reason metadata or invokes environmental inspection
---@param player ObjectRef The deceased player object
---@param reason table|nil The engine reason table from on_dieplayer or show_death_screen
---@return table analysis The complete death metadata table (category, reason_text, killer_name, weapon, funny_note)
function deathstats.analyze_death(player, reason)
    if not player then
        return {
            category = "unknown",
            reason_text = "Died",
            funny_note = deathstats.get_funny_note("unknown"),
        }
    end

    local pname = player:get_player_name()

    -- If reason is already an analyzed death_info table with reason_text
    if reason and type(reason) == "table" and reason.reason_text then
        local res = {}
        for k, v in pairs(reason) do res[k] = v end
        if not res.funny_note then
            res.funny_note = deathstats.get_funny_note(res.category or "unknown")
        end
        return res
    end

    -- If reason table is provided and valid
    if reason and type(reason) == "table" and (reason.type or reason.hunger or reason.thirst or reason.cause) then
        local rtype = reason.type or (reason.hunger and "starve") or (reason.thirst and "thirst") or "set_hp"

        -- PUNCH / KILL COMBAT
        if rtype == "punch" or rtype == "kill" then
            local attacker = reason.object
            if attacker then
                local killer_name, is_player, killer_desc, proj_name = deathstats.resolve_entity_info(attacker)
                local weapon_desc = "Bare Hands"

                if proj_name then
                    weapon_desc = deathstats.format_projectile_name(proj_name)
                elseif is_player then
                    local real_att = attacker:is_player() and attacker or core.get_player_by_name(killer_name)
                    if real_att and real_att:is_player() then
                        local wielded = real_att:get_wielded_item()
                        local iname = wielded and wielded:get_name()
                        if iname and iname ~= "" then
                            weapon_desc = deathstats.format_name(iname)
                        end
                    end
                end

                -- Fallback to recent punches if weapon was bare hands or hit by projectile
                local last_punch = deathstats.recent_punches[pname]
                if last_punch and (core.get_gametime() - last_punch.time <= 3.5) then
                    if last_punch.projectile then
                        weapon_desc = deathstats.format_projectile_name(last_punch.projectile)
                    elseif weapon_desc == "Bare Hands" and last_punch.tool_desc and last_punch.tool_desc ~= "Bare Hands" then
                        weapon_desc = last_punch.tool_desc
                    end
                end

                local cat = is_player and "pvp" or "mob"
                local reason_text = is_player
                    and string.format("Slain by %s using %s", killer_name, weapon_desc)
                    or string.format("Slain by %s", killer_desc)

                return {
                    category = cat,
                    killer_name = killer_name,
                    killer_desc = killer_desc,
                    is_player = is_player,
                    weapon = weapon_desc,
                    reason_text = reason_text,
                    funny_note = deathstats.get_funny_note(cat),
                }
            end
        end

        -- FALL DAMAGE
        if rtype == "fall" then
            return {
                category = "fall",
                reason_text = S("Fell from a high place"),
                funny_note = deathstats.get_funny_note("fall"),
            }
        end

        -- DROWNING
        if rtype == "drown" then
            return {
                category = "drown",
                reason_text = S("Drowned in deep water"),
                funny_note = deathstats.get_funny_note("drown"),
            }
        end

        -- BURNING
        if rtype == "burn" then
            local pos = player:get_pos()
            local node = core.get_node(pos)
            if node.name:find("lava") then
                return {
                    category = "lava",
                    reason_text = S("Melted in searing lava"),
                    funny_note = deathstats.get_funny_note("lava"),
                }
            end
            return {
                category = "fire",
                reason_text = S("Burned to ashes"),
                funny_note = deathstats.get_funny_note("fire"),
            }
        end

        -- NODE DAMAGE (Cactus, Spikes, Poison etc.)
        if rtype == "node_damage" and reason.node then
            local node_name = deathstats.format_name(reason.node)
            local cat = "unknown"
            if reason.node:find("lava") then
                cat = "lava"
            elseif reason.node:find("fire") then
                cat = "fire"
            elseif reason.node:find("cactus") then
                cat = "mob"
            end
            return {
                category = cat,
                reason_text = "Pricked or wounded by " .. node_name,
                funny_note = deathstats.get_funny_note(cat),
            }
        end

        -- DEHYDRATION / THIRST (thirsty mod or explicit thirst reason)
        local was_dehydrated = deathstats.is_player_dehydrated(player)
            or (deathstats.recent_dehydrations[pname] and (core.get_gametime() - deathstats.recent_dehydrations[pname] <= 3.5))
        if rtype == "thirst" or rtype == "dehydrate"
            or (reason.thirst ~= nil)
            or (reason.cause and (tostring(reason.cause):find("thirst") or tostring(reason.cause):find("dehydrat")))
            or (rtype == "set_hp" and was_dehydrated) then
            return {
                category = "thirst",
                reason_text = S("Died of dehydration"),
                funny_note = deathstats.get_funny_note("thirst"),
            }
        end

        -- STARVATION (explicit reason type or cause from hunger mods e.g. stamina, mcl_hunger, hunger_ng)
        local was_starving = deathstats.is_player_starving(player)
            or (deathstats.recent_starvations[pname] and (core.get_gametime() - deathstats.recent_starvations[pname] <= 3.5))
        if rtype == "starve" or rtype == "hunger"
            or (reason.hunger and tostring(reason.hunger):find("starve"))
            or (reason.cause and (tostring(reason.cause):find("starve") or tostring(reason.cause):find("hunger")))
            or (rtype == "set_hp" and was_starving) then
            local note
            if deathstats.is_player_sprint_exhausted(player) then
                note = deathstats.get_funny_note("starve_sprint") or deathstats.get_funny_note("starve")
            else
                note = deathstats.get_funny_note("starve")
            end
            return {
                category = "starve",
                reason_text = S("Starved to death"),
                funny_note = note,
            }
        end
    end

    -- Fallback: reason was nil or unknown, inspect physical state & surroundings
    return deathstats.inspect_surroundings_fallback(player)
end

-- ==========================================
-- Corpse Entity, Visuals & Camera Orbit
-- ==========================================

core.register_entity("deathstats:corpse", {
    initial_properties = {
        visual = "mesh",
        mesh = "character.b3d",
        textures = { "character.png" },
        visual_size = { x = 1, y = 1, z = 1 },
        collisionbox = { -0.5, 0.0, -0.5, 0.5, 0.3, 0.5 },
        selectionbox = { 0, 0, 0, 0, 0, 0 },
        pointable = false,
        physical = false,
        collide_with_objects = false,
        static_save = false,
    },
    on_activate = function(self)
        if self.object then
            self.object:set_armor_groups({ immortal = 1 })
            if self.object.set_properties then
                self.object:set_properties({
                    selectionbox = { 0, 0, 0, 0, 0, 0 },
                    pointable = false,
                })
            end
        end
    end,
})

--- Register attached wielditem entity displayed in the corpse's right hand when inventory is retained
core.register_entity("deathstats:corpse_wielditem", {
    initial_properties = {
        visual = "wielditem",
        visual_size = { x = 0.25, y = 0.25, z = 0.25 },
        pointable = false,
        physical = false,
        collide_with_objects = false,
        static_save = false,
    },
    on_activate = function(self)
        if self.object then
            self.object:set_armor_groups({ immortal = 1 })
            if self.object.set_properties then
                self.object:set_properties({
                    selectionbox = { 0, 0, 0, 0, 0, 0 },
                    pointable = false,
                    physical = false,
                    collide_with_objects = false,
                })
            end
        end
    end,
    on_step = function(self)
        local parent = self.object and self.object.get_attach and self.object:get_attach()
        if not parent then
            if self.object and self.object.remove then
                self.object:remove()
            end
        end
    end,
})

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

--- Set the corpse entity into a flat fallen pose matching the active model
---@param corpse ObjectRef The corpse entity object
---@param mesh_name string|nil The model mesh name
function deathstats.pose_corpse(corpse, mesh_name)
    if not corpse or not corpse.set_animation then return end

    local anim_range = nil
    local papi = rawget(_G, "player_api")
    if papi and papi.registered_models and mesh_name and papi.registered_models[mesh_name] then
        local model_def = papi.registered_models[mesh_name]
        if model_def.animations then
            anim_range = model_def.animations.lay or model_def.animations.die
        end
    end

    local def_mod = rawget(_G, "default")
    if not anim_range and def_mod and def_mod.registered_player_models and mesh_name and def_mod.registered_player_models[mesh_name] then
        local model_def = def_mod.registered_player_models[mesh_name]
        if model_def.animations then
            anim_range = model_def.animations.lay or model_def.animations.die
        end
    end

    local mcl_p = rawget(_G, "mcl_player")
    if not anim_range and mcl_p and mcl_p.registered_players then
        anim_range = { x = 162, y = 166 }
    end

    if not anim_range then
        anim_range = { x = 162, y = 166 }
    end

    -- Freeze pose on the final frame of the lay animation so corpse lies completely flat
    -- Note: frame_speed must be non-zero (1) for the Luanti engine to seek to the frame; loop must be false
    local target_frame = (type(anim_range) == "table" and (anim_range.y or anim_range[2])) or 166
    if corpse.set_animation then
        corpse:set_animation({ x = target_frame, y = target_frame }, 1, 0, false)
    end
end

--- Rotate a corpse bone in 3D space (local X, Y, Z axes)
--- Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)
---@param corpse ObjectRef The corpse entity object
---@param bone_name string The name of the bone to rotate
---@param rot_vec Vector The rotation vector in radians (x, y, z)
---@return boolean success True if the rotation was applied
function deathstats.rotate_corpse_bone(corpse, bone_name, rot_vec)
    if not corpse or not bone_name or not rot_vec then return false end

    -- Luanti >= 5.9.0 ObjectRef:set_bone_override
    -- Vec rotation is in radians; absolute = false applies relative to the frozen lay animation pose
    if corpse.set_bone_override then
        local success = corpse:set_bone_override(bone_name, {
            rotation = {
                vec = vector.new(rot_vec.x or 0, rot_vec.y or 0, rot_vec.z or 0),
                absolute = false,
                interpolation = 0,
            },
        })
        if success ~= false then return true end
    end

    -- Luanti <= 5.8 fallback: set_bone_position(bone, pos, rot_deg)
    if corpse.set_bone_position then
        local luaent = corpse.get_luaentity and corpse:get_luaentity()
        local base_store = (type(luaent) == "table" and luaent) or (type(corpse) == "table" and corpse) or nil
        local base
        if base_store then
            if not base_store._base_bone_rot then
                base_store._base_bone_rot = {}
            end
            if not base_store._base_bone_rot[bone_name] then
                local cur_pos, cur_rot
                if corpse.get_bone_position then
                    cur_pos, cur_rot = corpse:get_bone_position(bone_name)
                end
                base_store._base_bone_rot[bone_name] = {
                    pos = cur_pos or vector.zero(),
                    rot = cur_rot or vector.zero(),
                }
            end
            base = base_store._base_bone_rot[bone_name]
        else
            local cur_pos, cur_rot
            if corpse.get_bone_position then
                cur_pos, cur_rot = corpse:get_bone_position(bone_name)
            end
            base = {
                pos = cur_pos or vector.zero(),
                rot = cur_rot or vector.zero(),
            }
        end
        local deg_vec = vector.new(
            base.rot.x + math.deg(rot_vec.x or 0),
            base.rot.y + math.deg(rot_vec.y or 0),
            base.rot.z + math.deg(rot_vec.z or 0)
        )
        corpse:set_bone_position(bone_name, base.pos, deg_vec)
        return true
    end

    return false
end

--- Rotate a corpse bone strictly along the horizontal floor plane (around local Z axis)
--- Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)
---@param corpse ObjectRef The corpse entity object
---@param bone_name string The name of the bone to rotate
---@param z_rad number The rotation angle in radians around local Z axis
---@return boolean success True if the rotation was applied
function deathstats.rotate_corpse_bone_planar(corpse, bone_name, z_rad)
    return deathstats.rotate_corpse_bone(corpse, bone_name, vector.new(0, 0, z_rad))
end

--- Helper to generate a random floating point number between min_val and max_val
local function random_float(min_val, max_val)
    return min_val + math.random() * (max_val - min_val)
end

--- Programmatically rotate corpse limbs on fall death to simulate fractured / broken bones.
--- Rotates arms, legs, and head strictly along the horizontal floor plane (around local Z axis),
--- guaranteeing that limbs stay flush touching the ground without lifting into the air or clipping underground.
---@param corpse ObjectRef The corpse entity object
---@param custom_angles table<string, number>|nil Optional map of bone names to z-axis rotation radians
---@return table<string, number> applied_angles Map of bone names to applied z radians
function deathstats.fracture_corpse_limbs(corpse, custom_angles)
    if not corpse then return {} end

    local angles = {}
    if custom_angles and type(custom_angles) == "table" then
        for k, v in pairs(custom_angles) do
            angles[k] = tonumber(v) or 0
        end
    else
        -- Anatomical broken bone angle ranges (local Z rotation):
        -- Left Arm: 50% chance splayed outwards (-80 to -35 deg), 30% folded inward across torso (+20 to +55 deg)
        local left_arm_deg = (math.random() < 0.5) and random_float(-80, -35) or random_float(20, 55)
        -- Right Arm: 50% chance splayed outwards (+35 to +80 deg), 30% folded inward across torso (-55 to -20 deg)
        local right_arm_deg = (math.random() < 0.5) and random_float(35, 80) or random_float(-55, -20)
        -- Left Leg: 50% chance splayed outwards (+15 to +70 deg), 30% twisted inward (-30 to -10 deg)
        local left_leg_deg = (math.random() < 0.5) and random_float(15, 70) or random_float(-30, -10)
        -- Right Leg: 50% chance splayed outwards (-70 to -15 deg), 30% twisted inward (+10 to +30 deg)
        local right_leg_deg = (math.random() < 0.5) and random_float(-70, -15) or random_float(10, 30)
        -- Head: limp neck turned sideways on the floor (-45 to +45 deg)
        local head_deg = random_float(-45, 45)

        angles["Arm_Left"] = math.rad(left_arm_deg)
        angles["Arm_Right"] = math.rad(right_arm_deg)
        angles["Leg_Left"] = math.rad(left_leg_deg)
        angles["Leg_Right"] = math.rad(right_leg_deg)
        angles["Head"] = math.rad(head_deg)
    end

    local applied = {}
    for bone_name, z_rad in pairs(angles) do
        if deathstats.rotate_corpse_bone_planar(corpse, bone_name, z_rad) then
            applied[bone_name] = z_rad
        end
    end

    return applied
end

--- Get the active corpse entity for a player name if currently spawned
---@param player_name string
---@return ObjectRef|nil corpse The active corpse entity or nil
function deathstats.get_corpse(player_name)
    if not player_name or player_name == "" then return nil end
    local data = deathstats.player_camera_data and deathstats.player_camera_data[player_name]
    return data and data.corpse
end

--- Get the attached wielditem entity from a corpse
---@param corpse ObjectRef|nil The corpse entity object
---@return ObjectRef|nil went The attached wielditem entity or nil
function deathstats.get_corpse_wielditem(corpse)
    if not corpse then return nil end
    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    return luaent and luaent._wielditem_entity
end

--- Safely remove a corpse entity and any attached wielditem entity
---@param corpse ObjectRef|nil The corpse object reference
function deathstats.remove_corpse(corpse)
    if not corpse then return end
    local xbows_mod = rawget(_G, "XBows")
    if xbows_mod and type(xbows_mod.cleanup_corpse_arrows) == "function" then
        xbows_mod.cleanup_corpse_arrows(corpse)
    end
    local went = deathstats.get_corpse_wielditem(corpse)
    if went and (not went.is_valid or went:is_valid()) and went.remove then
        went:remove()
    end
    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    if luaent then
        luaent._wielditem_entity = nil
    end
    if (not corpse.is_valid or corpse:is_valid()) and corpse.remove then
        corpse:remove()
    end
end

--- Spawn and configure the corpse placeholder entity at the given position
---@param corpse_pos table The {x, y, z} coordinates where corpse should be placed
---@param visuals table The player visual appearance table (mesh, textures, visual_size, yaw)
---@param player ObjectRef|nil Optional player reference for transferring attached arrows
---@return ObjectRef|nil corpse The spawned corpse entity or nil if failed (e.g. mapblock not loaded)
function deathstats.spawn_and_setup_corpse(corpse_pos, visuals, player)
    if not corpse_pos or not visuals then return nil end
    local corpse = core.add_entity(corpse_pos, "deathstats:corpse")
    if corpse then
        corpse:set_properties({
            mesh = visuals.mesh,
            textures = visuals.textures,
            visual_size = visuals.visual_size,
            selectionbox = { 0, 0, 0, 0, 0, 0 },
            pointable = false,
        })
        if corpse.set_rotation then
            corpse:set_rotation({ x = 0, y = visuals.yaw or 0, z = 0 })
        elseif corpse.set_yaw then
            corpse:set_yaw(visuals.yaw or 0)
        end
        deathstats.pose_corpse(corpse, visuals.mesh)

        local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
            and (deathstats.config.enable_fall_fractures ~= false)
        if fractures_enabled then
            deathstats.fracture_corpse_limbs(corpse)
        end

        -- Attach 3D wielditem entity to right hand if inventory items are retained on death
        if visuals.wield_item and visuals.wield_item ~= "" and not visuals.inventory_dropped then
            local wield_ent = core.add_entity(corpse_pos, "deathstats:corpse_wielditem")
            if wield_ent then
                wield_ent:set_properties({
                    textures = { visuals.wield_item },
                    wield_item = visuals.wield_item,
                    visual_size = { x = 0.25, y = 0.25, z = 0.25 },
                    pointable = false,
                })
                if wield_ent.set_attach then
                    -- Attach to lower palm of right hand (y=6.0 places item in palm, z=1.5 aligns with grip)
                    wield_ent:set_attach(corpse, "Arm_Right", { x = 0, y = 6.0, z = 1.5 }, { x = 90, y = 0, z = 90 }, true)
                end
                local luaent = corpse.get_luaentity and corpse:get_luaentity()
                if luaent then
                    luaent._wielditem_entity = wield_ent
                end
            end
        end

        -- Transfer attached x_bows arrows from player to corpse if x_bows is loaded
        local xbows_loaded = rawget(_G, "XBows")
        if player and xbows_loaded and type(xbows_loaded.transfer_arrows_to_corpse) == "function" then
            xbows_loaded.transfer_arrows_to_corpse(player, corpse)
        end
    end
    return corpse
end

--- Get the primary tile texture name for a given node for particle fallback
---@param node_name string Name of the node (e.g. "default:dirt")
---@return string texture Name of the texture or fallback
function deathstats.get_node_tile_texture(node_name)
    if not node_name or node_name == "" or node_name == "air" or node_name == "ignore" then
        return "default_dirt.png"
    end
    local ndef = core.registered_nodes[node_name]
    if ndef and ndef.tiles then
        local t = ndef.tiles[1]
        if type(t) == "string" then
            return t
        elseif type(t) == "table" and t.name then
            return t.name
        end
    end
    return "default_dirt.png"
end

--- Determine the appropriate particle effect for a corpse based on death cause and environment
---@param corpse_pos table The {x, y, z} position of the corpse
---@param death_info table|nil Optional death analysis table
---@return string effect_type "water"|"lava"|"fire"|"impact"
function deathstats.get_corpse_effect_type(corpse_pos, death_info)
    local cat = death_info and death_info.category
    if cat == "lava" then
        return "lava"
    elseif cat == "fire" then
        return "fire"
    elseif cat == "drown" then
        return "water"
    end

    if death_info and death_info.reason_text then
        local rtext = death_info.reason_text:lower()
        if rtext:find("lava") then
            return "lava"
        elseif rtext:find("fire") or rtext:find("burned") or rtext:find("flame") or rtext:find("ashes") then
            return "fire"
        elseif rtext:find("drown") or rtext:find("water") then
            return "water"
        end
    end

    if corpse_pos then
        local get_node_fn = core.get_node_or_nil or core.get_node
        local node = get_node_fn and get_node_fn(corpse_pos)
        if node then
            local nname = node.name:lower()
            if nname:find("lava") then
                return "lava"
            elseif nname:find("fire") then
                return "fire"
            elseif nname:find("water") then
                return "water"
            end
            local ndef = core.registered_nodes[node.name]
            if ndef and (ndef.drawtype == "liquid" or ndef.drawtype == "flowingliquid"
                    or ndef.liquidtype == "source" or ndef.liquidtype == "flowing") then
                return "water"
            end
        end
    end

    return "impact"
end

--- Create a modern ParticleSpawner definition table with graceful fallback to older Luanti clients
---@param effect_type string "water"|"lava"|"fire"|"impact"
---@param corpse_pos table The {x, y, z} position of the corpse
---@return table|nil def ParticleSpawner definition table
function deathstats.create_corpse_particlespawner_def(effect_type, corpse_pos)
    if not corpse_pos then return nil end
    local cx, cy, cz = corpse_pos.x, corpse_pos.y, corpse_pos.z

    if effect_type == "water" then
        -- Bubbles floating upwards through water continuously from random positions on the submerged corpse
        return {
            amount = 8,
            time = 0, -- Continuous spawner
            collisiondetection = true,
            collision_removal = false,
            glow = 3,
            -- Legacy client fields (< v5.6)
            minpos = { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = { x = cx + 0.35, y = cy + 0.25, z = cz + 0.35 },
            minvel = { x = -0.15, y = 0.35, z = -0.15 },
            maxvel = { x = 0.15, y = 0.85, z = 0.15 },
            minacc = { x = -0.05, y = 0.20, z = -0.05 },
            maxacc = { x = 0.05, y = 0.45, z = 0.05 },
            minexptime = 1.2,
            maxexptime = 2.4,
            minsize = 1.0,
            maxsize = 1.6,
            texture = "deathstats_particle_bubble.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.8,
            },
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = vector.new(cx + 0.35, cy + 0.25, cz + 0.35),
            },
            vel = {
                min = vector.new(-0.15, 0.35, -0.15),
                max = vector.new(0.15, 0.85, 0.15),
            },
            acc = {
                min = vector.new(-0.05, 0.20, -0.05),
                max = vector.new(0.05, 0.45, 0.05),
            },
            exptime = { min = 1.2, max = 2.4 },
            size = { min = 1.0, max = 1.6 },
            texpool = {
                {
                    name = "deathstats_particle_bubble.png",
                    alpha_tween = { 0.85, 0.30 },
                    scale_tween = { { x = 0.9, y = 0.9 }, { x = 1.15, y = 1.15 } },
                    blend = "alpha",
                    animation = {
                        type = "vertical_frames",
                        aspect_w = 5,
                        aspect_h = 5,
                        length = 0.8,
                    },
                },
            },
        }

    elseif effect_type == "lava" then
        -- Fire and glowing ember sparks leaping continuously from random positions on the burning corpse
        return {
            amount = 12,
            time = 0, -- Continuous spawner
            collisiondetection = true,
            collision_removal = false,
            glow = 14,
            -- Legacy client fields (< v5.6)
            minpos = { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = { x = cx + 0.35, y = cy + 0.30, z = cz + 0.35 },
            minvel = { x = -0.25, y = 0.50, z = -0.25 },
            maxvel = { x = 0.25, y = 1.40, z = 0.25 },
            minacc = { x = -0.10, y = 0.30, z = -0.10 },
            maxacc = { x = 0.10, y = 0.80, z = 0.10 },
            minexptime = 0.5,
            maxexptime = 1.2,
            minsize = 1.0,
            maxsize = 1.8,
            texture = "deathstats_particle_fire.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.4,
            },
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = vector.new(cx + 0.35, cy + 0.30, cz + 0.35),
            },
            vel = {
                min = vector.new(-0.25, 0.50, -0.25),
                max = vector.new(0.25, 1.40, 0.25),
            },
            acc = {
                min = vector.new(-0.10, 0.30, -0.10),
                max = vector.new(0.10, 0.80, 0.10),
            },
            exptime = { min = 0.5, max = 1.2 },
            size = { min = 1.0, max = 1.8 },
            texpool = {
                {
                    name = "deathstats_particle_fire.png",
                    alpha_tween = { 1.0, 0.0 },
                    blend = "add",
                    animation = {
                        type = "vertical_frames",
                        aspect_w = 5,
                        aspect_h = 5,
                        length = 0.4,
                    },
                },
            },
        }

    elseif effect_type == "fire" then
        -- Billowing ash smoke rising continuously into the air from the charred corpse
        return {
            amount = 12,
            time = 0, -- Continuous spawner
            collisiondetection = true,
            collision_removal = false,
            glow = 1,
            -- Legacy client fields (< v5.6)
            minpos = { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = { x = cx + 0.35, y = cy + 0.30, z = cz + 0.35 },
            minvel = { x = -0.15, y = 0.30, z = -0.15 },
            maxvel = { x = 0.15, y = 0.80, z = 0.15 },
            minacc = { x = -0.05, y = 0.15, z = -0.05 },
            maxacc = { x = 0.05, y = 0.40, z = 0.05 },
            minexptime = 1.0,
            maxexptime = 2.0,
            minsize = 1.2,
            maxsize = 2.4,
            texture = "deathstats_particle_smoke.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.8,
            },
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = vector.new(cx + 0.35, cy + 0.30, cz + 0.35),
            },
            vel = {
                min = vector.new(-0.15, 0.30, -0.15),
                max = vector.new(0.15, 0.80, 0.15),
            },
            acc = {
                min = vector.new(-0.05, 0.15, -0.05),
                max = vector.new(0.05, 0.40, 0.05),
            },
            exptime = { min = 1.0, max = 2.0 },
            size = { min = 1.2, max = 2.4 },
            texpool = {
                {
                    name = "deathstats_particle_smoke.png",
                    alpha_tween = { 0.75, 0.0 },
                    scale_tween = { { x = 0.8, y = 0.8 }, { x = 1.5, y = 1.5 } },
                    blend = "alpha",
                    animation = {
                        type = "vertical_frames",
                        aspect_w = 5,
                        aspect_h = 5,
                        length = 0.8,
                    },
                },
            },
        }

    else
        -- All others: Node particles around the corpse flying upwards from impact at time of death (non-continuous)
        local ground_node_name = "default:dirt"
        local ground_param2 = 0
        local get_node_fn = core.get_node_or_nil or core.get_node
        if get_node_fn then
            local check_positions = {
                { x = cx, y = math.floor(cy), z = cz },
                { x = cx, y = math.floor(cy - 0.5), z = cz },
                { x = cx, y = math.floor(cy - 1.0), z = cz },
            }
            for _, cpos in ipairs(check_positions) do
                local n = get_node_fn(cpos)
                if n and n.name ~= "air" and n.name ~= "ignore" then
                    ground_node_name = n.name
                    ground_param2 = n.param2 or 0
                    break
                end
            end
        end

        local fallback_tex = deathstats.get_node_tile_texture(ground_node_name)

        return {
            amount = 28,
            time = 0.15, -- Moment of death impact burst (not continuous)
            collisiondetection = true,
            collision_removal = false,
            node = { name = ground_node_name, param2 = ground_param2 },
            texture = fallback_tex,
            -- Legacy client fields (< v5.6)
            minpos = { x = cx - 0.45, y = cy - 0.05, z = cz - 0.45 },
            maxpos = { x = cx + 0.45, y = cy + 0.15, z = cz + 0.45 },
            minvel = { x = -1.6, y = 1.8, z = -1.6 },
            maxvel = { x = 1.6, y = 3.6, z = 1.6 },
            minacc = { x = 0, y = -9.81, z = 0 },
            maxacc = { x = 0, y = -9.81, z = 0 },
            minexptime = 0.6,
            maxexptime = 1.2,
            minsize = 0,
            maxsize = 0,
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = vector.new(cx - 0.45, cy - 0.05, cz - 0.45),
                max = vector.new(cx + 0.45, cy + 0.15, cz + 0.45),
            },
            vel = {
                min = vector.new(-1.6, 1.8, -1.6),
                max = vector.new(1.6, 3.6, 1.6),
            },
            acc = {
                min = vector.new(0, -9.81, 0),
                max = vector.new(0, -9.81, 0),
            },
            exptime = { min = 0.6, max = 1.2 },
            size = { min = 0, max = 0 },
        }
    end
end

--- Spawn corpse particle spawner(s) according to death cause/environment
---@param corpse_pos table The {x, y, z} position of the corpse
---@param death_info table|nil Optional death analysis table
---@return number[] spawner_ids Array of active particle spawner IDs
function deathstats.spawn_corpse_particles(corpse_pos, death_info)
    if not corpse_pos then return {} end
    if deathstats.config.enable_corpse_particles == false then return {} end

    local effect_type = deathstats.get_corpse_effect_type(corpse_pos, death_info)
    local def = deathstats.create_corpse_particlespawner_def(effect_type, corpse_pos)
    if not def then return {} end

    local spawner_id = core.add_particlespawner(def)
    local spawner_ids = {}
    if spawner_id and spawner_id > 0 then
        table.insert(spawner_ids, spawner_id)
    end
    return spawner_ids
end



--- Wrap an animation function to prevent death animation looping while a player is dead
--- In Luanti Game (MTG) / Repixture, player_api.globalstep calls player_set_animation(player, "lay") every tick
--- which defaults to loop = true at 30 fps, causing a violent 0.13s death replay loop.
--- This hook forces loop = false and speed = 1 so the character cleanly stays in the final flat pose.
---@param mod_table table|nil The mod table containing the animation function
---@param fn_name string The name of the animation function
deathstats.hooked_animations = {}

function deathstats.hook_animation_function(mod_table, fn_name)
    if mod_table and type(mod_table[fn_name]) == "function" and not deathstats.hooked_animations[mod_table[fn_name]] then
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

-- Hook available player animation handlers immediately
deathstats.hook_animation_function(rawget(_G, "player_api"), "set_animation")
deathstats.hook_animation_function(rawget(_G, "default"), "player_set_animation")
deathstats.hook_animation_function(rawget(_G, "mcl_player"), "player_set_animation")

-- Also hook in on_mods_loaded in case a mod initialized late
core.register_on_mods_loaded(function()
    deathstats.hook_animation_function(rawget(_G, "player_api"), "set_animation")
    deathstats.hook_animation_function(rawget(_G, "default"), "player_set_animation")
    deathstats.hook_animation_function(rawget(_G, "mcl_player"), "player_set_animation")
end)

--- Set or clear the player_attached flag in player_api and default mods
---@param name string The player name
---@param attached boolean|nil True if attached, nil to clear
function deathstats.set_engine_player_attached(name, attached)
    local papi = rawget(_G, "player_api")
    if papi and papi.player_attached then
        papi.player_attached[name] = attached
    end
    local def_mod = rawget(_G, "default")
    if def_mod and def_mod.player_attached then
        def_mod.player_attached[name] = attached
    end
end

--- Check if 3d_armor is configured to drop or destroy armor on player death
---@param player ObjectRef|nil Optional player reference
---@return boolean drops True if armor is ejected/dropped from inventory on death
function deathstats.is_armor_dropped(player)
    local armor_mod = rawget(_G, "armor")
    if not armor_mod then
        return false
    end
    if armor_mod.config and type(armor_mod.config) == "table" then
        if armor_mod.config.drop ~= nil or armor_mod.config.destroy ~= nil then
            return (armor_mod.config.drop == true) or (armor_mod.config.destroy == true)
        end
    end
    local drop_set = core.settings:get_bool("armor_drop")
    local dest_set = core.settings:get_bool("armor_destroy")
    if drop_set ~= nil or dest_set ~= nil then
        return (drop_set == true) or (dest_set == true)
    end
    return false
end

--- Check if player inventory/items are dropped or lost on death
--- If false, the player keeps items in inventory, so corpse should display wielded item
---@param player ObjectRef|nil Optional player reference
---@return boolean dropped True if items are dropped on death, false if kept
function deathstats.is_inventory_dropped(player)
    -- 1. Creative mode: players do not lose inventory
    if player and player:is_player() then
        local name = player:get_player_name()
        if name and core.is_creative_enabled(name) then
            return false
        end
    end

    -- 2. Engine & Game Settings: keep_inventory flags
    local setting_keys = {
        "keep_inventory",
        "keepinventory",
        "mcl_keepInventory",
        "gamerule:keepInventory",
    }
    for _, key in ipairs(setting_keys) do
        if core.settings:get_bool(key) == true then
            return false
        end
    end

    -- 3. Bones mod configuration (Luanti Game / default games)
    local _, bones_mode, has_bones_mod = deathstats.get_bones_mode()
    if has_bones_mod then
        if bones_mode == "keep" then
            return false
        elseif bones_mode == "drop" or bones_mode == "bones" then
            return true
        end
    else
        local mode_setting = core.settings:get("bones_mode")
        if mode_setting == "keep" then
            return false
        elseif mode_setting == "drop" then
            return true
        end
    end

    -- 4. Mod-specific drop handlers
    if rawget(_G, "mcl_death_drop") ~= nil or rawget(_G, "rp_drop_items_on_die") ~= nil then
        return true
    end

    -- 5. Default engine behavior (without bones or drop mods, inventory is kept)
    return false
end

--- Extract the player's active wielded item name, ignoring internal camera hands
---@param player ObjectRef The player object
---@return string item_name The item technical name (e.g. "default:sword_steel"), or "" if empty/hand
function deathstats.get_player_wield_item(player)
    if not player or not player:is_player() then
        return ""
    end

    -- 1. Check player's direct wielded item
    local stack = player:get_wielded_item()
    local name = deathstats.get_stack_name(stack)
    if name ~= "" and name ~= "deathstats:camera_hand" then
        return name
    end

    -- 2. Check inventory main list at wield index
    local inv = player:get_inventory()
    local wield_idx = player:get_wield_index() or 1
    if inv then
        local main_stack = inv:get_stack("main", wield_idx)
        local main_name = deathstats.get_stack_name(main_stack)
        if main_name ~= "" and main_name ~= "deathstats:camera_hand" then
            return main_name
        end
    end

    -- 3. Check stashed main inventory from player metadata if available
    local meta = player:get_meta()
    if meta then
        local raw_main = meta:get_string("deathstats:stashed_main")
        if raw_main and raw_main ~= "" then
            local des_main = core.deserialize(raw_main)
            if type(des_main) == "table" then
                local idx = wield_idx or 1
                if des_main[idx] and des_main[idx] ~= "" and des_main[idx] ~= "deathstats:camera_hand" then
                    return deathstats.get_stack_name(des_main[idx])
                end
            end
        end
    end

    -- 4. Check 3d_armor textures table if available
    local armor_mod = rawget(_G, "armor")
    if armor_mod and armor_mod.textures then
        local pname = player:get_player_name()
        local a_tex = pname and armor_mod.textures[pname]
        if a_tex and a_tex.wielditem and a_tex.wielditem ~= "" and a_tex.wielditem ~= "3d_armor_trans.png" and a_tex.wielditem ~= "blank.png" then
            local item_clean = a_tex.wielditem:gsub("%.png$", ""):gsub("_", ":", 1)
            if core.registered_items[a_tex.wielditem] then
                return a_tex.wielditem
            elseif core.registered_items[item_clean] then
                return item_clean
            else
                return a_tex.wielditem
            end
        end
    end

    return ""
end

--- Extract player visual characteristics (mesh, textures, visual_size, yaw) across all skin mods
---@param player ObjectRef The player object
---@return table visuals { mesh = string, textures = table, visual_size = table, yaw = number, armor_dropped = boolean }
function deathstats.get_player_visuals(player)
    if deathstats.compat_skins and deathstats.compat_skins.get_player_visuals then
        return deathstats.compat_skins.get_player_visuals(player)
    end
    local name = player:get_player_name()
    local props = player:get_properties() or {}

    local armor_mod = rawget(_G, "armor")
    local skins_mod = rawget(_G, "skins")
    local wardrobe_mod = rawget(_G, "wardrobe")
    local player_api_mod = rawget(_G, "player_api")
    local mcl_skins_mod = rawget(_G, "mcl_skins")
    local clothing_mod = rawget(_G, "clothing")

    local mesh = (armor_mod and armor_mod.models and armor_mod.models[name]) or props.mesh or "character.b3d"
    local visual_size = copy(props.visual_size or { x = 1, y = 1, z = 1 })
    local yaw = player:get_look_horizontal() or 0

    if visual_size.x == 0 and visual_size.y == 0 then
        visual_size = { x = 1, y = 1, z = 1 }
    end

    local drops_armor = deathstats.is_armor_dropped(player)
    local drops_inventory = deathstats.is_inventory_dropped(player)
    local wield_item = deathstats.get_player_wield_item(player)

    -- Detect if using the 4-slot skinsdb model (skinsdb_3d_armor_character_5.b3d)
    local is_skinsdb = (mesh == "skinsdb_3d_armor_character_5.b3d")
        or (mesh and mesh:find("skinsdb") ~= nil)
        or (skins_mod and skins_mod.armor_loaded == true)
        or (skins_mod and skins_mod.get_player_skin and (armor_mod ~= nil or (props.textures and #props.textures >= 4)))

    -- Detect if using the standard 3-slot 3d_armor model (3d_armor_character.b3d)
    local is_3d_armor = not is_skinsdb and (
        (mesh == "3d_armor_character.b3d")
        or (armor_mod and ((armor_mod.textures and armor_mod.textures[name]) or (mesh and mesh:find("3d_armor"))))
        or (armor_mod and props.textures and #props.textures == 3)
    )

    local textures

    -- 1. skinsdb + 3d_armor support: 4 material slots
    -- Slot 1: v10 (1.0 skin or blank.png, + cape)
    -- Slot 2: v18 (1.8 skin or blank.png, + clothing overlays)
    -- Slot 3: 3d_armor geometry overlay (blank.png if dropped/naked)
    -- Slot 4: wielditem (blank.png on corpse)
    if is_skinsdb then
        mesh = "skinsdb_3d_armor_character_5.b3d"

        local ver = "1.0"
        local skin_tex = "character.png"

        if skins_mod and skins_mod.get_player_skin then
            local skin = skins_mod.get_player_skin(player)
            if skin then
                ver = (skin.get_meta and skin:get_meta("format")) or "1.0"
                skin_tex = (skin.get_texture and skin:get_texture()) or skin_tex
                local vs_x = skin.get_meta and skin:get_meta("visual_size_x")
                local vs_y = skin.get_meta and skin:get_meta("visual_size_y")
                if vs_x and vs_y then
                    visual_size = { x = tonumber(vs_x) or 1, y = tonumber(vs_y) or 1, z = tonumber(vs_x) or 1 }
                end
            end
        elseif props.textures and #props.textures >= 2 then
            if props.textures[2] and props.textures[2] ~= "blank.png" and props.textures[2] ~= "" then
                ver = "1.8"
                skin_tex = props.textures[2]
            elseif props.textures[1] and props.textures[1] ~= "blank.png" and props.textures[1] ~= "" then
                ver = "1.0"
                skin_tex = props.textures[1]
            end
        end

        local v10_texture = (ver == "1.8") and "blank.png" or skin_tex
        local v18_texture = (ver == "1.8") and skin_tex or "blank.png"

        -- Support for clothing on skinsdb
        if clothing_mod and clothing_mod.player_textures and clothing_mod.player_textures[name] then
            local c = clothing_mod.player_textures[name]
            local cape = c.cape
            local layers = {}
            for k, v in pairs(c) do
                if k ~= "skin" and k ~= "cape" and v and v ~= "" and v ~= "blank.png" then
                    table.insert(layers, v)
                end
            end
            if #layers > 0 then
                local overlay = table.concat(layers, "^")
                v18_texture = (v18_texture == "blank.png") and overlay or (v18_texture .. "^" .. overlay)
            end
            if cape and cape ~= "" and cape ~= "blank.png" then
                v10_texture = (v10_texture == "blank.png") and cape or (v10_texture .. "^" .. cape)
            end
        end

        -- Slot 3: 3D Armor mesh geometry
        local armor_texture = "blank.png"
        if not drops_armor and armor_mod and armor_mod.textures and armor_mod.textures[name] then
            local a_tex = armor_mod.textures[name]
            if a_tex.armor and a_tex.armor ~= "" and a_tex.armor ~= "blank.png" and a_tex.armor ~= "3d_armor_trans.png" then
                armor_texture = a_tex.armor
            end
        elseif not drops_armor and props.textures and props.textures[3] and props.textures[3] ~= "blank.png" and props.textures[3] ~= "3d_armor_trans.png" then
            armor_texture = props.textures[3]
        end

        -- Slot 4: Wielditem (corpse holds nothing, so keep blank.png)
        local wielditem_texture = "blank.png"

        textures = {
            v10_texture,
            v18_texture,
            armor_texture,
            wielditem_texture,
        }

    -- 2. Standalone 3d_armor support: 3 material slots (skin, armor, wielditem)
    elseif is_3d_armor then
        mesh = (armor_mod and armor_mod.models and armor_mod.models[name]) or "3d_armor_character.b3d"
        local a_tex = (armor_mod and armor_mod.textures and armor_mod.textures[name]) or {}
        local skin_tex = a_tex.skin or (props.textures and props.textures[1]) or "character.png"
        local armor_tex = a_tex.armor or "3d_armor_trans.png"
        -- Keep slot 3 transparent so the attached 3D wielditem entity renders without 2D quad duplication
        local wield_tex = "3d_armor_trans.png"

        if drops_armor then
            armor_tex = "3d_armor_trans.png"
        end

        -- Clothing support on 3d_armor
        if clothing_mod and clothing_mod.player_textures and clothing_mod.player_textures[name] then
            local c = clothing_mod.player_textures[name]
            if c.clothing and c.clothing ~= "blank.png" and c.clothing ~= "" then
                skin_tex = skin_tex .. "^" .. c.clothing
            end
            if c.cape and c.cape ~= "blank.png" and c.cape ~= "" then
                skin_tex = skin_tex .. "^" .. c.cape
            end
        end

        textures = {
            skin_tex,
            armor_tex,
            wield_tex,
        }

    -- 3. Fallback skin mods: skinsdb (legacy/without armor), simple_skins, wardrobe, player_api, mcl_skins
    else
        textures = copy(props.textures or { "character.png" })

        if skins_mod and skins_mod.get_player_skin then
            local skin = skins_mod.get_player_skin(player)
            if skin then
                local skin_tex = skin.get_texture and skin:get_texture()
                if skin_tex then
                    textures[1] = skin_tex
                end
                local vs_x = skin.get_meta and skin:get_meta("visual_size_x")
                local vs_y = skin.get_meta and skin:get_meta("visual_size_y")
                if vs_x and vs_y then
                    visual_size = { x = tonumber(vs_x) or 1, y = tonumber(vs_y) or 1, z = tonumber(vs_x) or 1 }
                end
            end
        elseif skins_mod and skins_mod.skins and skins_mod.skins[name] then
            textures = { skins_mod.skins[name] .. ".png" }
        elseif wardrobe_mod and wardrobe_mod.playerSkins and wardrobe_mod.playerSkins[name] then
            textures = { wardrobe_mod.playerSkins[name] }
        elseif player_api_mod and player_api_mod.get_textures then
            local p_tex = player_api_mod.get_textures(player)
            if p_tex and #p_tex > 0 then
                textures = copy(p_tex)
            end
        elseif mcl_skins_mod and mcl_skins_mod.get_player_skin then
            local skin_data = mcl_skins_mod.get_player_skin(player)
            if type(skin_data) == "table" and skin_data.texture then
                textures[1] = skin_data.texture
            elseif type(skin_data) == "string" then
                textures[1] = skin_data
            end
        end

        -- Clothing support
        if clothing_mod and clothing_mod.player_textures and clothing_mod.player_textures[name] then
            local c = clothing_mod.player_textures[name]
            if c.clothing and c.clothing ~= "blank.png" and c.clothing ~= "" then
                textures[1] = (textures[1] or "character.png") .. "^" .. c.clothing
            end
            if c.cape and c.cape ~= "blank.png" and c.cape ~= "" then
                textures[1] = (textures[1] or "character.png") .. "^" .. c.cape
            end
        end
    end

    -- 4. Fallback for transparent texture trap:
    -- If textures only contains deathstats_transparent.png, recover original textures from metadata or default
    local is_transparent = true
    if type(textures) == "table" and #textures > 0 then
        for _, tex in ipairs(textures) do
            if tex ~= "deathstats_transparent.png" and tex ~= "blank.png" and tex ~= "" and tex ~= "3d_armor_trans.png" then
                is_transparent = false
                break
            end
        end
    else
        is_transparent = true
    end

    local meta = player:get_meta()
    if is_transparent and meta then
        local raw_orig = meta:get_string("deathstats:orig_textures")
        if raw_orig and raw_orig ~= "" then
            local des = core.deserialize(raw_orig)
            if type(des) == "table" and #des > 0 then
                textures = des
                is_transparent = false
            end
        end
    end
    if is_transparent then
        if is_skinsdb then
            textures = { "character.png", "blank.png", "blank.png", "blank.png" }
        elseif is_3d_armor then
            textures = { "character.png", "3d_armor_trans.png", "3d_armor_trans.png" }
        else
            textures = { "character.png" }
        end
    end

    if meta then
        if not mesh or mesh == "" then
            local raw_mesh = meta:get_string("deathstats:orig_mesh")
            if raw_mesh and raw_mesh ~= "" then mesh = raw_mesh end
        end
        if visual_size.x == 0 and visual_size.y == 0 then
            local raw_vs = meta:get_string("deathstats:orig_visual_size")
            if raw_vs and raw_vs ~= "" then
                local des = core.deserialize(raw_vs)
                if type(des) == "table" then visual_size = des end
            end
        end
        if yaw == 0 then
            local raw_yaw = meta:get_string("deathstats:orig_yaw")
            if raw_yaw and raw_yaw ~= "" then
                yaw = tonumber(raw_yaw) or yaw
            end
        end
    end

    return {
        mesh = mesh,
        textures = textures,
        visual_size = visual_size,
        yaw = yaw,
        armor_dropped = drops_armor,
        inventory_dropped = drops_inventory,
        wield_item = wield_item,
    }
end

--- Check if bones were placed for this player at or near death position
---@param player ObjectRef The deceased player object
---@param search_center Vector|nil Optional search origin (defaults to orbit_center or player pos)
---@return Vector|nil pos The 3D coordinates of the placed bones node, or nil if not found
function deathstats.find_player_bones(player, search_center)
    if not core.registered_nodes["bones:bones"] then return nil end
    if not player or not player:is_player() then return nil end
    local name = player:get_player_name()
    local cam_data = deathstats.player_camera_data[name]
    local center = search_center or (cam_data and cam_data.orbit_center) or player:get_pos()
    if not center then return nil end
    local pos = vector.round(center)

    -- Check direct death node first
    local node = core.get_node(pos)
    if node.name == "bones:bones" then
        local meta = core.get_meta(pos)
        local owner = meta:get_string("owner")
        if owner == "" or owner == name then
            return pos
        end
    end

    -- Search adjacent nodes strictly checking that bones belong to this player
    local minp = vector.new(pos.x - 2, pos.y - 2, pos.z - 2)
    local maxp = vector.new(pos.x + 2, pos.y + 2, pos.z + 2)
    local positions = core.find_nodes_in_area(minp, maxp, { "bones:bones" })
    for _, bpos in ipairs(positions) do
        local meta = core.get_meta(bpos)
        if meta:get_string("owner") == name then
            return bpos
        end
    end
    return nil
end

--- Check if bones mod is active and configured to place/show bones
---@return boolean should_show_bones True if bones mod is active and bones_mode == "bones"
---@return string bones_mode The effective bones_mode setting ("bones", "drop", or "keep")
---@return boolean has_bones_mod True if bones mod is loaded in the world
function deathstats.get_bones_mode()
    local has_bones_mod = false
    if core.get_modpath("bones") then
        has_bones_mod = true
    elseif rawget(_G, "bones") ~= nil and type(rawget(_G, "bones")) == "table" then
        has_bones_mod = true
    end
    local mode = core.settings:get("bones_mode") or "bones"
    if mode ~= "bones" and mode ~= "drop" and mode ~= "keep" then
        mode = "bones"
    end
    local should_show_bones = has_bones_mod and (mode == "bones")
    return should_show_bones, mode, has_bones_mod
end

--- Check if a specific world position contains liquid (water, lava, or modded fluids)
---@param pos Vector The position to check
---@return boolean is_liquid True if the node is liquid
function deathstats.is_liquid_at(pos)
    if not pos then return false end
    local check_pos = vector.round(pos)
    local node = core.get_node(check_pos)
    if not node or node.name == "air" or node.name == "ignore" then
        return false
    end
    if core.get_item_group(node.name, "liquid") ~= 0
        or core.get_item_group(node.name, "water") ~= 0
        or core.get_item_group(node.name, "lava") ~= 0 then
        return true
    end
    local def = core.registered_nodes[node.name]
    if def then
        if def.liquidtype ~= nil and def.liquidtype ~= "none" then
            return true
        end
        if def.drawtype == "liquid" or def.drawtype == "flowingliquid" then
            return true
        end
    end
    local idef = core.registered_items[node.name]
    if idef and idef.groups and (idef.groups.liquid or idef.groups.water or idef.groups.lava) then
        return true
    end
    local nname = node.name:lower()
    if nname:find("water") or nname:find("lava") or nname:find("liquid") then
        return true
    end
    return false
end

--- Check if a death position represents being in a liquid (water, lava, etc.)
--- Checks death category as well as world nodes at feet, torso, and head level
---@param pos Vector Player death position
---@param death_info table|nil Optional death details
---@return boolean in_liquid True if player died in or around liquid
function deathstats.is_in_liquid(pos, death_info)
    if death_info and (death_info.category == "drown" or death_info.category == "lava") then
        return true
    end
    if not pos then return false end
    if deathstats.is_liquid_at(pos) then
        return true
    end
    -- Check surrounding node levels (feet, torso, head, bottom)
    if deathstats.is_liquid_at(vector.new(pos.x, pos.y + 0.5, pos.z))
        or deathstats.is_liquid_at(vector.new(pos.x, pos.y + 1.0, pos.z))
        or deathstats.is_liquid_at(vector.new(pos.x, pos.y - 0.5, pos.z))
        or deathstats.is_liquid_at(vector.new(pos.x, pos.y - 1.0, pos.z)) then
        return true
    end
    return false
end

--- Find the true ground collision surface level beneath a position
--- Ensures the corpse rests directly flush on walkable terrain, slabs, stairs, or bones
--- For liquid deaths (water, lava), prevents pinning to the lake bed and retains exact death position
---@param pos Vector Player or death position
---@param bones_pos Vector|nil Coordinates of bones node if placed
---@param death_info table|nil Optional death analysis information
---@return number surface_y The exact Y coordinate where corpse should rest
function deathstats.find_ground_surface(pos, bones_pos, death_info)
    if not pos then return 0 end

    -- Liquid deaths (water, lava): Never pin to the lake/ocean bottom;
    -- retain the exact place of death so the corpse floats where the player died.
    if deathstats.is_in_liquid(pos, death_info) then
        return pos.y
    end

    if bones_pos then
        return bones_pos.y + 0.5
    end

    -- 1. Check if direct node or bones is already right below or at pos
    local check_pos = vector.round(pos)
    local direct_node = core.get_node(check_pos)
    if direct_node.name == "bones:bones" then
        return check_pos.y + 0.5
    end

    -- Determine downward search depth:
    -- For fall deaths (category == "fall", or nil/unspecified in backward-compatible unit tests),
    -- allow searching down to ground impact level (up to 40 nodes).
    -- For non-fall deaths in mid-air (suicide, /kill, mobs, projectiles, fire), only search near feet (2.5 nodes)
    -- to snap to floors/slabs/stairs if standing on solid ground. If suspended in mid-air, retain exact death height pos.y!
    local is_fall = (death_info == nil) or (death_info.category == nil) or (death_info.category == "fall")
    local max_depth = is_fall and 40 or 2.5

    -- 2. Downward raycast to detect exact collision surface (handles nodes, slabs, stairs, meshes)
    local start_pos = vector.new(pos.x, pos.y + 0.5, pos.z)
    local end_pos = vector.new(pos.x, pos.y - max_depth, pos.z)
    local ray = core.raycast(start_pos, end_pos, false, false)
    for pointed_thing in ray do
        if pointed_thing.type == "node" and pointed_thing.under then
            local node = core.get_node(pointed_thing.under)
            local def = core.registered_nodes[node.name]
            if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                if pointed_thing.intersection_point then
                    return pointed_thing.intersection_point.y
                else
                    return pointed_thing.under.y + 0.5
                end
            end
        end
    end

    -- 3. Fallback: discrete node scanning downward from math.floor(pos.y + 0.5) down to max_depth
    local start_y = math.floor(pos.y + 0.5)
    local check_x = math.floor(pos.x + 0.5)
    local check_z = math.floor(pos.z + 0.5)
    local min_y = math.floor(pos.y - max_depth + 0.5)
    for y = start_y, min_y, -1 do
        local npos = vector.new(check_x, y, check_z)
        local node = core.get_node(npos)
        local def = core.registered_nodes[node.name]
        if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
            return y + 0.5
        end
    end

    -- If no solid ground found within max_depth (e.g. suspended in mid-air / floating), retain pos.y
    return pos.y
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

    -- 1. Check for delayed bones placement if bones were not initially detected
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
            if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) and data.anchor.set_pos then
                data.anchor:set_pos(new_center)
            end
            if player.set_detach then player:set_detach() end
            if player.set_pos then player:set_pos(new_center) end
            if data.anchor and player.set_attach then
                player:set_attach(data.anchor, "", vector.zero(), vector.zero(), false)
            end
        end
    end

    -- 1b. Check if corpse needs to be spawned / re-spawned once mapblock is loaded
    local should_show_bones = deathstats.get_bones_mode()
    local bones_active = data.has_bones or (data.bones_pos ~= nil) or data.expect_bones or should_show_bones
    if not bones_active then
        if (not data.corpse or (data.corpse.is_valid and not data.corpse:is_valid())) and data.corpse_pos and data.corpse_visuals then
            local new_corpse = deathstats.spawn_and_setup_corpse(data.corpse_pos, data.corpse_visuals, player)
            if new_corpse then
                data.corpse = new_corpse
                data.corpse_wielditem = deathstats.get_corpse_wielditem(new_corpse)
            end
            if deathstats.config.enable_corpse_particles ~= false and not data.particle_spawners then
                local effect_type = deathstats.get_corpse_effect_type(data.corpse_pos, data.death_info)
                if effect_type ~= "impact" then
                    data.particle_spawners = deathstats.spawn_corpse_particles(data.corpse_pos, data.death_info)
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

    -- 1c. Check if camera anchor needs to be re-instantiated if lost across engine reload
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
            data.anchor = new_anchor
            if player.set_pos then player:set_pos(data.orbit_center) end
            if player.set_attach then
                player:set_attach(new_anchor, "", vector.zero(), vector.zero(), false)
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

    -- Keep player attached to camera anchor to prevent falling/rubber-banding if detached by external mods
    if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) then
        if player.get_attach and not player:get_attach() and player.set_attach then
            player:set_attach(data.anchor, "", vector.zero(), vector.zero(), false)
        end
    end

    -- 2. Advance orbit angle smoothly
    data.orbit_speed = data.orbit_speed or deathstats.config.orbit_speed or 0.4
    data.orbit_angle = ((data.orbit_angle or 0) + data.orbit_speed * (dtime or 0)) % (2 * math.pi)
    local angle = data.orbit_angle

    local radius = data.orbit_radius or deathstats.config.orbit_radius or 3.2
    local height = data.orbit_height or deathstats.config.orbit_height or 1.5
    local target_radius = radius

    -- Raycast obstacle detection to prevent camera clipping into walls / terrain.
    -- Uses a continuous clearance buffer (zero boundary step discontinuity) and multi-angle probing.
    local buffer = 0.45
    local probe_radius = radius + buffer
    local nominal_ratio = height / math.max(0.1, radius)
    local probe_height = math.max(0.65, probe_radius * nominal_ratio)

    if core.raycast and data.orbit_center then
        local ray_start = vector.new(data.orbit_center.x, data.orbit_center.y + 0.8, data.orbit_center.z)
        local min_clear_r = probe_radius

        -- Multi-angle probe: check primary camera sightline plus lookahead/lookbehind (+/- 0.08 rad)
        -- to detect approaching walls before camera sweeps into them and prevent edge chattering
        local probe_angles = { angle, angle + 0.08, angle - 0.08 }
        for _, p_angle in ipairs(probe_angles) do
            local cam_x = data.orbit_center.x + probe_radius * math.sin(p_angle)
            local cam_y = data.orbit_center.y + probe_height
            local cam_z = data.orbit_center.z - probe_radius * math.cos(p_angle)
            local cam_target = vector.new(cam_x, cam_y, cam_z)
            local ray = core.raycast(ray_start, cam_target, false, false)
            for pointed_thing in ray do
                if pointed_thing.type == "node" and pointed_thing.under then
                    local node = core.get_node(pointed_thing.under)
                    local def = core.registered_nodes[node.name]
                    if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                        local hit_pos = pointed_thing.intersection_point or pointed_thing.under
                        -- Safely ignore floor nodes directly beneath/around the corpse (not an obstacle)
                        local is_ground = (hit_pos.y <= data.orbit_center.y + 0.35)
                            and (math.abs(hit_pos.x - data.orbit_center.x) <= 1.0)
                            and (math.abs(hit_pos.z - data.orbit_center.z) <= 1.0)
                        if not is_ground then
                            -- Project 3D hit point to horizontal orbit radius from orbit center
                            local hx = hit_pos.x - data.orbit_center.x
                            local hz = hit_pos.z - data.orbit_center.z
                            local hit_r = math.sqrt(hx * hx + hz * hz)
                            if hit_r >= 0.8 and hit_r < min_clear_r then
                                min_clear_r = hit_r
                            end
                            break
                        end
                    end
                end
            end
        end

        -- Continuous safe radius: as an obstacle approaches, target_radius transitions
        -- smoothly from full radius downward with zero boundary step jump (no cliff)
        target_radius = math.max(1.2, math.min(radius, min_clear_r - buffer))
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
            -- React smoothly and promptly to avoid clipping, and refresh the hold timer
            data.obstacle_hold_timer = 0.5
            local lerp_speed = 4.5
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

    -- Proportional height scaling: keeping height proportional to radius maintains
    -- a constant sightline angle (pitch) relative to the corpse, eliminating vertical bobbing
    local eff_height = math.max(0.65, eff_radius * nominal_ratio)

    -- Decimeter eye offsets for Luanti client
    local target_dm_z = -eff_radius * 10
    local target_dm_y = eff_height * 10
    if player.set_eye_offset then
        local cur_first = player.get_eye_offset and player:get_eye_offset()
        if not cur_first
            or math.abs(cur_first.y - target_dm_y) > 0.08
            or math.abs(cur_first.z - target_dm_z) > 0.08 then
            player:set_eye_offset({ x = 0, y = target_dm_y, z = target_dm_z }, vector.zero())
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

    -- Suppress redundant horizontal yaw updates to avoid packet flooding
    if player.set_look_horizontal then
        local cur_yaw = player.get_look_horizontal and player:get_look_horizontal()
        if not cur_yaw or math.abs(angle - cur_yaw) > 0.008 then
            player:set_look_horizontal(angle)
        end
    end
    -- Suppress redundant vertical pitch updates to avoid packet flooding
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
        data.bones_pos = bones_pos
        local new_center = bones_pos
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
        if data.anchor and (not data.anchor.is_valid or data.anchor:is_valid()) and data.anchor.set_pos then
            data.anchor:set_pos(new_center)
        end
        if player.set_detach then player:set_detach() end
        if player.set_pos then player:set_pos(new_center) end
        if data.anchor and player.set_attach then
            player:set_attach(data.anchor, "", vector.zero(), vector.zero(), false)
        end
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

    -- 1. Restore Main Inventory if stashed
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

    -- 2. Restore Hand Inventory Slot / Reach
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

    -- 4. Strip any deathstats:camera_hand if it leaked into main/craft/offhand
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

    -- 5. Restore pointability and interaction range if player is alive
    if player.get_hp and player:get_hp() > 0 and player.set_properties then
        player:set_properties({
            pointable = true,
            interaction_range = 4,
        })
    end

    return restored
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

    -- 1. Determine ground surface and orbit center
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

    -- 2. Cache original player properties and armor groups for clean respawn restoration
    local props = player:get_properties() or {}
    local old_visual_size = copy(props.visual_size or { x = 1, y = 1, z = 1 })
    local old_collisionbox = copy(props.collisionbox or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 })
    local old_selectionbox = copy(props.selectionbox or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 })
    local old_textures = copy(props.textures or { "character.png" })
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

    -- 4. Extract player visuals across skin mods and spawn corpse placeholder entity
    local visuals = deathstats.get_player_visuals(player)
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

    local corpse = nil
    if not expect_bones then
        corpse = deathstats.spawn_and_setup_corpse(corpse_pos, visuals, player)
    end
    local particle_spawners = nil
    if deathstats.config.enable_corpse_particles ~= false then
        local particle_pos = bones_pos or corpse_pos
        particle_spawners = deathstats.spawn_corpse_particles(particle_pos, death_info)
    end
    if not expect_bones and not corpse and core.after then
        core.after(0.2, function()
            local p = core.get_player_by_name(name)
            local cdata = deathstats.player_camera_data[name]
            if p and p:is_player() and deathstats.dead_players[name] and cdata and not cdata.corpse and not cdata.has_bones and not cdata.expect_bones then
                local retry_corpse = deathstats.spawn_and_setup_corpse(corpse_pos, visuals, p)
                if retry_corpse then
                    cdata.corpse = retry_corpse
                    cdata.corpse_wielditem = deathstats.get_corpse_wielditem(retry_corpse)
                end
                if deathstats.config.enable_corpse_particles ~= false and not cdata.particle_spawners then
                    cdata.particle_spawners = deathstats.spawn_corpse_particles(corpse_pos, death_info)
                end
            end
        end)
    end

    -- 5. Hide the real player (ghost), nametag, and lock in first-person camera mode
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
                    if child.set_properties then
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
    if deathstats.compat_hudbars and deathstats.compat_hudbars.hide then
        deathstats.compat_hudbars.hide(player)
    else
        local hb_mod = rawget(_G, "hb")
        if hb_mod and hb_mod.hudtables and hb_mod.hide_hudbar then
            for id in pairs(hb_mod.hudtables) do
                hb_mod.hide_hudbar(player, id)
            end
        end
    end

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
    local radius_dm = math.floor(radius * 10)
    local height_dm = math.floor(height * 10)

    -- Set camera eye offset projecting backwards by radius and up by height
    if player.set_eye_offset then
        player:set_eye_offset({ x = 0, y = height_dm, z = -radius_dm }, vector.zero())
    end

    -- 6. Setup stationary camera anchor and attach player at orbit center
    -- Attaching to an anchor bypasses Luanti client physics, gravity, and fall damage completely.
    local anchor_pos = orbit_center
    local anchor = core.add_entity(anchor_pos, "deathstats:camera_anchor")
    if anchor then
        anchor:set_pos(anchor_pos)
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
    end
    if player.set_pos then player:set_pos(anchor_pos) end
    if anchor and player.set_attach then
        player:set_attach(anchor, "", vector.zero(), vector.zero(), false)
    end

    local initial_angle = visuals.yaw or 0
    local initial_pitch = atan2(height, radius)

    if player.set_look_horizontal then player:set_look_horizontal(initial_angle) end
    if player.set_look_vertical then player:set_look_vertical(initial_pitch) end

    deathstats.player_camera_data[name] = {
        has_bones = (bones_pos ~= nil),
        bones_pos = bones_pos,
        expect_bones = expect_bones,
        corpse_pos = (not expect_bones) and corpse_pos or nil,
        corpse_visuals = (not expect_bones) and visuals or nil,
        orbit_center = orbit_center,
        orbit_angle = initial_angle,
        orbit_radius = radius,
        orbit_height = height,
        orbit_speed = speed,
        corpse = corpse,
        corpse_wielditem = deathstats.get_corpse_wielditem(corpse),
        anchor = anchor,
        old_armor_groups = old_armor_groups,
        old_is_visible = old_is_visible,
        old_visual_size = old_visual_size,
        old_collisionbox = old_collisionbox,
        old_selectionbox = old_selectionbox,
        old_textures = old_textures,
        old_pointable = old_pointable,
        old_interaction_range = old_interaction_range,
        old_physics_override = old_physics,
        old_nametag_attributes = old_nametag_attributes,
        saved_hand_size = saved_hand_size,
        saved_hand_stack = saved_hand_stack,
        stashed_main = stashed_main,
        death_info = death_info,
        particle_spawners = particle_spawners,
    }

    -- 7. Immediately orient camera to starting orbit vantage
    deathstats.update_death_camera(player, 0)
end

--- Reset player camera back to normal first-person behavior, remove corpse, and restore player properties
---@param player ObjectRef The player object to reset
---@param is_leaving boolean|nil True if called when player is leaving the server
function deathstats.reset_camera(player, is_leaving)
    if not player then return end
    local name = player:get_player_name()
    local data = deathstats.player_camera_data[name]

    -- 1. Detach player from camera anchor
    if player.set_detach then
        player:set_detach()
    end

    -- 2. Remove corpse placeholder, camera anchor entities, and particle spawners
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
            data.anchor = nil
        end
    end

    -- 3. Restore player armor groups
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

    -- 4. Restore original inventory and hand reach (verified against in-memory data and persistent metadata)
    deathstats.restore_player_inventory_and_hand(player)

    -- 5. Restore player physical and visual properties & nametag
    if data then
        if player.set_nametag_attributes then
            if data.old_nametag_attributes then
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
                is_visible = (data.old_is_visible ~= nil and data.old_is_visible or true),
                visual_size = data.old_visual_size or { x = 1, y = 1, z = 1 },
                collisionbox = data.old_collisionbox or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 },
                selectionbox = data.old_selectionbox or { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 },
                pointable = (data.old_pointable ~= nil and data.old_pointable or true),
                interaction_range = data.old_interaction_range or 4,
                textures = data.old_textures or { "character.png" },
                show_on_minimap = true,
            })
        end
        if player.set_physics_override then
            player:set_physics_override(data.old_physics_override or { speed = 1, jump = 1, gravity = 1 })
        end
    else
        if player.set_nametag_attributes then
            player:set_nametag_attributes({
                text = name,
                color = { a = 255, r = 255, g = 255, b = 255 },
                bgcolor = { a = 0, r = 0, g = 0, b = 0 },
            })
        end
        if player.set_properties then
            local orig_tex = nil
            local meta = player:get_meta()
            if meta then
                local raw_orig = meta:get_string("deathstats:orig_textures")
                if raw_orig and raw_orig ~= "" then
                    local des = core.deserialize(raw_orig)
                    if type(des) == "table" and #des > 0 then
                        orig_tex = des
                    end
                end
            end
            player:set_properties({
                is_visible = true,
                visual_size = { x = 1, y = 1, z = 1 },
                collisionbox = { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 },
                selectionbox = { -0.3, 0.0, -0.3, 0.3, 1.77, 0.3 },
                interaction_range = 4,
                pointable = true,
                textures = orig_tex or { "character.png" },
                show_on_minimap = true,
            })
        end
        if player.set_physics_override then
            player:set_physics_override({ speed = 1, jump = 1, gravity = 1 })
        end
    end

    deathstats.player_camera_data[name] = nil

    -- If player is leaving or offline, bypass camera changes, animations and timers
    if is_leaving or not deathstats.is_player_online(name) then
        return
    end

    -- 5. Restore camera mode back to first person, then unlock to any mode
    if player.set_camera then
        player:set_camera({ mode = "first" })
    end

    -- 6. Reset eye offsets to zero
    if player.set_eye_offset then
        player:set_eye_offset(vector.zero(), vector.zero(), vector.zero())
    end

    -- 7. Reset pitch back to horizontal eye level
    if player.set_look_vertical then
        player:set_look_vertical(0)
    end

    -- 8. Restore standing animation (with deferred retries to ensure player_api handshake is complete)
    local function restore_stand()
        if not deathstats.is_player_online(name) then return end
        local p = core.get_player_by_name(name)
        if not p or not p:is_player() then return end
        local papi = rawget(_G, "player_api")
        local def_mod = rawget(_G, "default")
        local mcl_p = rawget(_G, "mcl_player")
        if papi and papi.set_animation then
            papi.set_animation(p, "stand", 30)
        elseif def_mod and def_mod.player_set_animation then
            def_mod.player_set_animation(p, "stand", 30)
        elseif mcl_p and mcl_p.player_set_animation then
            mcl_p.player_set_animation(p, "stand", 30)
        end
    end
    restore_stand()
    core.after(0.2, restore_stand)
    core.after(0.5, restore_stand)

    -- 9. Unlock camera to "any" after short delay
    core.after(0.2, function()
        if not deathstats.is_player_online(name) then return end
        local p = core.get_player_by_name(name)
        if p and p:is_player() and p.set_camera then
            p:set_camera({ mode = "any" })
        end
    end)

    -- 9. Restore gameplay HUD flags and custom hudbars
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
    if deathstats.compat_hudbars and deathstats.compat_hudbars.unhide then
        deathstats.compat_hudbars.unhide(player)
    else
        local hb_mod = rawget(_G, "hb")
        if hb_mod and hb_mod.hudtables and hb_mod.unhide_hudbar then
            for id in pairs(hb_mod.hudtables) do
                hb_mod.unhide_hudbar(player, id)
            end
        end
    end
    if deathstats.compat_hunger and deathstats.compat_hunger.restore_standalone_huds then
        deathstats.compat_hunger.restore_standalone_huds(player)
    end
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
end)

-- Cleanly verify and restore inventory and hand on player join
core.register_on_joinplayer(function(player)
    if not player or not player:is_player() then return end
    if player:get_hp() > 0 then
        deathstats.restore_player_inventory_and_hand(player)
    end
end)

-- Guard all interaction callbacks: orbiting dead players cannot punch, place, dig, or eat
core.register_on_punchnode(function(pos, node, puncher, pointed_thing)
    if puncher and puncher:is_player() and deathstats.dead_players[puncher:get_player_name()] then
        return true
    end
end)

core.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
    if placer and placer:is_player() and deathstats.dead_players[placer:get_player_name()] then
        return true
    end
end)

core.register_on_dignode(function(pos, oldnode, digger)
    if digger and digger:is_player() and deathstats.dead_players[digger:get_player_name()] then
        return true
    end
end)

core.register_on_item_eat(function(hp_change, replace_with_item, itemstack, user, pointed_thing)
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

    -- 1. Wipe in-memory death state for this player
    deathstats.dead_players[name] = nil
    deathstats.is_respawning[name] = nil
    deathstats.active_animations[name] = nil
    deathstats.recent_starvations[name] = nil
    deathstats.recent_dehydrations[name] = nil

    -- 2. Clear all death and scoreboard HUD elements
    deathstats.clear_death_hud(player)
    if deathstats.hide_scoreboard_hud then
        deathstats.hide_scoreboard_hud(player)
    end

    -- 3. Close any open death screen or statistics formspecs
    core.close_formspec(name, "deathstats:death")
    core.close_formspec(name, "deathstats:lifetime")
    core.close_formspec(name, "deathstats:death_screen")
    core.close_formspec(name, "deathstats:more_stats")

    -- 4. Restore camera perspective, eye offset, fov, gameplay HUDs, and standing animation
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

    -- 1. Strictly guard against repeating death loops:
    -- If player is already dead and death sequence is active, NEVER re-trigger
    if deathstats.dead_players[name] then
        return
    end
    deathstats.dead_players[name] = true
    if deathstats.hide_scoreboard_hud then
        deathstats.hide_scoreboard_hud(player)
    end

    -- 2. Hide gameplay HUD elements (hotbar, healthbar, minimap, crosshair, wielditem) for clean cinematic death screen
    player:hud_set_flags({
        crosshair = false,
        hotbar = false,
        healthbar = false,
        breathbar = false,
        minimap = false,
        wielditem = false,
    })
    if deathstats.compat_hudbars and deathstats.compat_hudbars.hide then
        deathstats.compat_hudbars.hide(player)
    else
        local hb_mod = rawget(_G, "hb")
        if hb_mod and hb_mod.hudtables and hb_mod.hide_hudbar then
            for id in pairs(hb_mod.hudtables) do
                hb_mod.hide_hudbar(player, id)
            end
        end
    end
    if deathstats.compat_hunger and deathstats.compat_hunger.hide_standalone_huds then
        deathstats.compat_hunger.hide_standalone_huds(player)
    end

    -- 3. Analyze death or recover previous death info for reconnecting dead player
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

    -- 5. Camera: switch to cinematic circular orbit around corpse
    deathstats.set_death_camera(player, death_info)

    -- 6. Play random death audio
    deathstats.play_death_sound(player)

    -- 7. Clear any old HUDs
    deathstats.clear_death_hud(player)

    -- 8. Setup HUD Elements positioned down around the horizon
    local huds = {}

    -- A. Fullscreen Splatter Vignette Overlay (Thematic per death type)
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

    -- B. "YOU DIED" Banner centered horizontally, moved to y=0.20
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

    -- C. Subtitle 1: Death Cause & Weapon (pure white font, moved to y=0.33)
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

    -- D. Subtitle 2: Funny Epitaph Note (soft white, moved to y=0.37)
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

    -- 9. Display side-docked death formspec immediately to capture input and prevent player movement
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

    -- 1. Cleanly reset all death screen effects, HUDs, physics, camera, and state
    deathstats.reset_player_effects(player)

    -- 2. Trigger engine respawn (invokes core.register_on_respawnplayer)
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

    -- Deferred reinforcement ticks to guarantee full health across engine/client respawn handshake
    core.after(0.05, function()
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
        end
    end)
    core.after(0.2, function()
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
        end
    end)
end

-- ==========================================
-- Formspec Presentation Interfaces
-- ==========================================

--- Display the elevated death formspec with consistent padding above hotbar area
---@param player ObjectRef The deceased player object
---@param death_info table The death analysis metadata table containing cause, killer, and notes
function deathstats.show_death_formspec(player, death_info)
    if not player then return end
    local name = player:get_player_name()
    local data = deathstats.players[name]
    local last = (data and data.last_life) or {}

    local time_str = deathstats.format_time(last.time_alive or 0)
    local mined_str = deathstats.format_number(last.blocks_mined or 0)
    local ores_str = deathstats.format_number(last.total_ores or 0)
    local dmg_dealt = deathstats.format_number(last.damage_dealt or 0)
    local dmg_taken = deathstats.format_number(last.damage_taken or 0)
    local mobs_slain = deathstats.format_number(last.mobs_killed or 0)
    local players_slain = deathstats.format_number(last.players_killed or 0)
    local items_crafted = deathstats.format_number(last.items_crafted or 0)
    local items_consumed = deathstats.format_number(last.items_consumed or 0)
    local dist_str = string.format("%.1f m", last.distance_traveled or 0)

    local fatal_cause = (death_info and death_info.reason_text) or (last and last.last_cause) or "Unknown"
    local fatal_weapon = (death_info and (death_info.weapon_name or death_info.weapon)) or (last and last.last_weapon) or "None"

    local side = deathstats.config.formspec_side or "right"
    local pos_x = 0.96
    local anchor_x = 1.0
    if side == "left" then
        pos_x = 0.04
        anchor_x = 0.0
    elseif side == "center" then
        pos_x = 0.5
        anchor_x = 0.5
    end

    local c = deathstats.colors

    -- Compact sidebar card docked to the side leaving center death scene completely unobstructed
    local fs = {
        "formspec_version[6]",
        "size[5.6,5.65]",
        string.format("position[%.2f,0.88]", pos_x),
        string.format("anchor[%.2f,1.0]", anchor_x),
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Dark stylized card container (width 5.0, margins 0.3)
        "box[0.3,0.2;5.0,4.45;" .. c.card_sidebar .. "]",
        "box[0.3,0.2;5.0,0.05;" .. c.crimson_border .. "]",
        "box[0.3,4.60;5.0,0.05;" .. c.crimson_border .. "]",

        -- Header: Last Life Summary
        "image[0.5,0.35;0.35,0.35;deathstats_icon_clock.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[0.95,0.58;", F(S("Last Life Summary")), "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.95,0.85;", F(S("Survived: @1", time_str)), "]",

        -- Row 1: Combat Stats
        "image[0.5,1.15;0.32,0.32;deathstats_icon_sword.png]",
        "label[0.95,1.38;", F(S("Damage: @1 dealt / @2 taken", dmg_dealt, dmg_taken)), "]",

        -- Row 2: Kills
        "image[0.5,1.57;0.32,0.32;deathstats_icon_skull.png]",
        "label[0.95,1.80;", F(S("Slain: @1 mobs / @2 pvp", mobs_slain, players_slain)), "]",

        -- Row 3: Mining
        "image[0.5,1.99;0.32,0.32;deathstats_icon_pickaxe.png]",
        "label[0.95,2.22;", F(S("Mined: @1 (@2 ores)", mined_str, ores_str)), "]",

        -- Row 4: Items
        "image[0.5,2.41;0.32,0.32;deathstats_icon_heart.png]",
        "label[0.95,2.64;", F(S("Items: @1 made / @2 eaten", items_crafted, items_consumed)), "]",

        -- Row 5: Fatal Blow Inset Box
        "box[0.5,2.88;4.6,1.52;" .. c.card_inset .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_crimson),
        "label[0.7,3.16;", F(S("Fatal Blow:")), "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.7,3.52;", F(deathstats.truncate_str(fatal_cause, 30)), "]",
        "label[0.7,3.95;", F(deathstats.truncate_str(fatal_weapon, 20) .. "  |  " .. dist_str), "]",

        -- Button Styling
        "style_type[button;border=true;bgimg_middle=true]",
        string.format("style[btn_try_again;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border),
        string.format("style[btn_more_stats;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border),

        -- Action Buttons side by side at bottom
        "button[0.3,4.80;2.4,0.72;btn_try_again;", F(S("TRY AGAIN")), "]",
        "button[2.9,4.80;2.4,0.72;btn_more_stats;", F(S("MORE STATS")), "]",
    }

    core.show_formspec(name, "deathstats:death", table.concat(fs, ""))
end

--- Display the Lifetime Statistics Dashboard with transparent backdrop and accessible tabs
---@param player ObjectRef The player viewing statistics
---@param tab string|nil The active tab name ("overview", "ores", or "combat")
function deathstats.show_lifetime_stats_formspec(player, tab)
    if not player then return end
    local name = player:get_player_name()
    local data = deathstats.players[name]
    local life = (data and data.lifetime) or {}
    tab = tab or "overview"

    local total_time = deathstats.format_time(life.time_alive or 0)
    local deaths = life.deaths or 0
    local kills = (life.mobs_killed or 0) + (life.players_killed or 0)
    local kd_ratio = (deaths > 0) and string.format("%.2f", kills / deaths) or tostring(kills)

    local c = deathstats.colors

    -- Transparent backdrop outside card so YOU DIED banner, blood splatter and 3D scene remain visible
    local fs = {
        "formspec_version[6]",
        "size[14.5,6.2]",
        "position[0.5,0.88]",
        "anchor[0.5,1.0]",
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Dark translucent modal window card (content area)
        "box[0.4,0.2;13.7,4.95;" .. c.card_modal .. "]",
        "box[0.4,0.2;13.7,0.06;" .. c.crimson_border .. "]",
        "box[0.4,5.15;13.7,0.06;" .. c.crimson_border .. "]",

        -- Header
        "image[0.7,0.32;0.4,0.4;deathstats_icon_skull.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[1.25,0.58;", F(S("LIFETIME DOSSIER: @1", name)), "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),

        -- Tab Bar Background Container
        "box[0.4,0.8;13.7,0.68;" .. c.tab_bar_bg .. "]",
        "box[0.4,1.48;13.7,0.04;" .. c.tab_bar_sep .. "]",
    }

    -- Tab Button Styles: active tab has high-contrast bright crimson + glowing border, inactive has distinct slate
    local tab_defs = {
        { id = "tab_overview", key = "overview", x = 0.5 },
        { id = "tab_ores",     key = "ores",     x = 5.1 },
        { id = "tab_combat",   key = "combat",   x = 9.7 },
    }
    for _, t in ipairs(tab_defs) do
        if tab == t.key then
            table.insert(fs, string.format("style[%s;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
                t.id, c.tab_active_bg, c.tab_active_hover_bg, c.tab_active_text, c.tab_active_border, c.tab_active_hover_border))
            table.insert(fs, string.format("box[%.1f,1.45;4.3,0.07;%s]", t.x, c.active_strip))
        else
            table.insert(fs, string.format("style[%s;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
                t.id, c.tab_inactive_bg, c.tab_inactive_hover_bg, c.tab_inactive_text, c.tab_inactive_border, c.tab_inactive_hover_border))
        end
    end

    -- Tab Buttons
    table.insert(fs, "button[0.5,0.85;4.3,0.58;tab_overview;" .. F(tab == "overview" and "▶ Overview" or "Overview") .. "]")
    table.insert(fs, "button[5.1,0.85;4.3,0.58;tab_ores;" .. F(tab == "ores" and "▶ Ores Breakdown" or "Ores Breakdown") .. "]")
    table.insert(fs, "button[9.7,0.85;4.3,0.58;tab_combat;" .. F(tab == "combat" and "▶ Combat Record" or "Combat Record") .. "]")

    if tab == "overview" then
        -- Overview Content: 2x2 grid with generous widths preventing text overflow
        -- Card 1: Survival (Top Left)
        table.insert(fs, "box[0.7,1.65;6.4,1.65;" .. c.card_panel .. "]")
        table.insert(fs, "image[0.9,1.75;0.4,0.4;deathstats_icon_clock.png]")
        table.insert(fs, "label[1.5,1.95;" .. F(S("Total Play Time: @1", total_time)) .. "]")
        table.insert(fs, "label[1.5,2.40;" .. F(S("Total Deaths: @1", deathstats.format_number(deaths))) .. "]")
        table.insert(fs, "label[1.5,2.85;" .. F(S("Distance Walked: @1", string.format("%.1f km", (life.distance_traveled or 0) / 1000))) .. "]")

        -- Card 2: Combat & K/D (Top Right)
        table.insert(fs, "box[7.4,1.65;6.4,1.65;" .. c.card_panel .. "]")
        table.insert(fs, "image[7.6,1.75;0.4,0.4;deathstats_icon_sword.png]")
        table.insert(fs, "label[8.2,1.95;" .. F(S("Damage Dealt: @1", deathstats.format_number(life.damage_dealt or 0))) .. "]")
        table.insert(fs, "label[8.2,2.40;" .. F(S("Damage Taken: @1", deathstats.format_number(life.damage_taken or 0))) .. "]")
        table.insert(fs, "label[8.2,2.85;" .. F(S("K / D Ratio: @1", kd_ratio)) .. "]")

        -- Card 3: Construction & Crafting (Bottom Left)
        table.insert(fs, "box[0.7,3.45;6.4,1.6;" .. c.card_panel .. "]")
        table.insert(fs, "image[0.9,3.55;0.4,0.4;deathstats_icon_pickaxe.png]")
        table.insert(fs, "label[1.5,3.75;" .. F(S("Blocks Mined: @1", deathstats.format_number(life.blocks_mined or 0))) .. "]")
        table.insert(fs, "label[1.5,4.18;" .. F(S("Total Ores Mined: @1", deathstats.format_number(life.total_ores or 0))) .. "]")
        table.insert(fs, "label[1.5,4.60;" .. F(S("Blocks Placed: @1", deathstats.format_number(life.blocks_placed or 0))) .. "]")

        -- Card 4: Sustenance & Recent Cause (Bottom Right, formatted across multiple lines)
        table.insert(fs, "box[7.4,3.45;6.4,1.6;" .. c.card_panel .. "]")
        table.insert(fs, "image[7.6,3.55;0.4,0.4;deathstats_icon_heart.png]")
        table.insert(fs, "label[8.2,3.75;" .. F(S("Items: @1 crafted / @2 eaten", deathstats.format_number(life.items_crafted or 0), deathstats.format_number(life.items_consumed or 0))) .. "]")
        table.insert(fs, "label[8.2,4.18;" .. F(S("Most Recent Cause:")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
        table.insert(fs, "label[8.2,4.58;" .. F(deathstats.truncate_str(life.last_cause or "None", 36)) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))

    elseif tab == "ores" then
        -- Ores Breakdown Table (Dynamic Scrollable 2-Column Grid)
        table.insert(fs, "box[0.7,1.65;13.1,3.4;" .. c.card_panel .. "]")

        local ores = life.ores_mined or {}
        local ore_list = {}
        for ore_name, count in pairs(ores) do
            table.insert(ore_list, { name = ore_name, count = count, title = deathstats.format_name(ore_name) })
        end
        table.sort(ore_list, function(a, b) return a.count > b.count end)

        local total_types = #ore_list
        table.insert(fs, "label[1.0,1.9;" .. F(S("Total Ores Extracted: @1 (@2 varieties)", deathstats.format_number(life.total_ores or 0), total_types)) .. "]")

        if total_types == 0 then
            table.insert(fs, "label[5.0,3.2;" .. F(S("No ores mined yet. Grab a pickaxe!")) .. "]")
        else
            local total_rows = math.ceil(total_types / 2)
            local has_scroll = total_rows > 5
            local container_w = has_scroll and 12.4 or 12.8
            local col_w = has_scroll and 5.95 or 6.15
            local col2_x = has_scroll and 6.25 or 6.45

            if has_scroll then
                table.insert(fs, string.format("scroll_container[0.8,2.18;%.2f,2.80;ore_scroll;vertical;0.1;0.1]", container_w))
            else
                table.insert(fs, "container[0.8,2.18]")
            end

            for i, ore in ipairs(ore_list) do
                local col = ((i - 1) % 2) + 1
                local row = math.floor((i - 1) / 2)
                local x = (col == 1) and 0.1 or col2_x
                local y = 0.08 + row * 0.46

                if row % 2 == 1 then
                    table.insert(fs, "box[" .. x .. "," .. (y - 0.08) .. ";" .. col_w .. ",0.42;" .. c.row_alt .. "]")
                end
                table.insert(fs, "item_image[" .. (x + 0.1) .. "," .. (y - 0.06) .. ";0.38,0.38;" .. F(ore.name) .. "]")
                table.insert(fs, "label[" .. (x + 0.65) .. "," .. (y + 0.13) .. ";" .. F(deathstats.truncate_str(ore.title, 22)) .. "]")
                table.insert(fs, "label[" .. (x + (col_w - 1.85)) .. "," .. (y + 0.13) .. ";" .. F(deathstats.format_number(ore.count)) .. " mined]")
            end

            if has_scroll then
                table.insert(fs, "scroll_container_end[]")
                local content_h = 0.08 + total_rows * 0.46
                local max_scroll = math.max(10, math.ceil((content_h - 2.80 + 0.1) * 10))
                table.insert(fs, string.format("scrollbaroptions[min=0;max=%d;smallstep=5;largestep=20;thumbsize=15;arrows=default]", max_scroll))
                table.insert(fs, "scrollbar[13.35,2.18;0.28,2.80;vertical;ore_scroll;0]")
            else
                table.insert(fs, "container_end[]")
            end
        end

    elseif tab == "combat" then
        -- Combat Details (Dynamic Scrollable 2-Column Grid)
        table.insert(fs, "box[0.7,1.65;13.1,3.4;" .. c.card_panel .. "]")

        local mobs = life.mobs_slain or {}
        local mob_list = {}
        for mob_name, count in pairs(mobs) do
            table.insert(mob_list, { name = mob_name, count = count, title = deathstats.format_name(mob_name) })
        end
        table.sort(mob_list, function(a, b) return a.count > b.count end)

        local total_mob_types = #mob_list
        table.insert(fs, "label[1.0,1.9;" .. F(S("Total Combat Slayings: @1 (@2 players, @3 mobs)", deathstats.format_number(kills), deathstats.format_number(life.players_killed or 0), deathstats.format_number(life.mobs_killed or 0))) .. "]")

        if total_mob_types == 0 and (life.players_killed or 0) == 0 then
            table.insert(fs, "label[5.0,3.2;" .. F(S("No combat kills recorded yet. A peaceful record.")) .. "]")
        else
            local total_rows = math.ceil(total_mob_types / 2)
            local has_scroll = total_rows > 5
            local container_w = has_scroll and 12.4 or 12.8
            local col_w = has_scroll and 5.95 or 6.15
            local col2_x = has_scroll and 6.25 or 6.45

            if has_scroll then
                table.insert(fs, string.format("scroll_container[0.8,2.18;%.2f,2.80;combat_scroll;vertical;0.1;0.1]", container_w))
            else
                table.insert(fs, "container[0.8,2.18]")
            end

            for i, mob in ipairs(mob_list) do
                local col = ((i - 1) % 2) + 1
                local row = math.floor((i - 1) / 2)
                local x = (col == 1) and 0.1 or col2_x
                local y = 0.08 + row * 0.46

                if row % 2 == 1 then
                    table.insert(fs, "box[" .. x .. "," .. (y - 0.08) .. ";" .. col_w .. ",0.42;" .. c.row_alt .. "]")
                end
                table.insert(fs, "image[" .. (x + 0.1) .. "," .. (y - 0.04) .. ";0.35,0.35;deathstats_icon_skull.png]")
                table.insert(fs, "label[" .. (x + 0.65) .. "," .. (y + 0.13) .. ";" .. F(deathstats.truncate_str(mob.title, 22)) .. "]")
                table.insert(fs, "label[" .. (x + (col_w - 1.85)) .. "," .. (y + 0.13) .. ";" .. F(deathstats.format_number(mob.count)) .. " slain]")
            end

            if has_scroll then
                table.insert(fs, "scroll_container_end[]")
                local content_h = 0.08 + total_rows * 0.46
                local max_scroll = math.max(10, math.ceil((content_h - 2.80 + 0.1) * 10))
                table.insert(fs, string.format("scrollbaroptions[min=0;max=%d;smallstep=5;largestep=20;thumbsize=15;arrows=default]", max_scroll))
                table.insert(fs, "scrollbar[13.35,2.18;0.28,2.80;vertical;combat_scroll;0]")
            else
                table.insert(fs, "container_end[]")
            end
        end
    end

    -- Bottom Buttons: Consistent styling and placement below content card
    table.insert(fs, "style_type[button;border=true;bgimg_middle=true]")
    table.insert(fs, string.format("style[btn_back_death;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
        c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border))
    table.insert(fs, string.format("style[btn_modal_respawn;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
        c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border))
    table.insert(fs, "button[0.4,5.35;5.0,0.72;btn_back_death;" .. F(S("< BACK TO DEATH SCREEN")) .. "]")
    table.insert(fs, "button[9.1,5.35;5.0,0.72;btn_modal_respawn;" .. F(S("TRY AGAIN")) .. "]")

    core.show_formspec(name, "deathstats:lifetime", table.concat(fs, ""))
end

deathstats.show_lifetime_formspec = deathstats.show_lifetime_stats_formspec

-- ============================================================================
-- Section 11: Public Scoreboard & Current-Life Leaderboard API
-- ============================================================================

--- Register or override a scoreboard column definition
---@param id string Unique identifier for the column (e.g. "kills", "damage", "ping")
---@param def table Column definition specification (order, title, pct, min_w, icon, get_value, get_color)
function deathstats.register_scoreboard_column(id, def)
    if not id or type(id) ~= "string" or id == "" then return end
    if not def or type(def) ~= "table" then return end

    deathstats.registered_columns[id] = {
        id = id,
        order = def.order or 50,
        title = def.title or id:upper(),
        title_small = def.title_small or def.title or id:sub(1, 3):upper(),
        pct = def.pct or 0.10,
        pct_small = def.pct_small or def.pct or 0.10,
        min_w = def.min_w or 40,
        min_w_small = def.min_w_small or 25,
        icon = def.icon or "deathstats_icon_star.png",
        tooltip = def.tooltip or def.title or id,
        get_value = def.get_value,
        get_color = def.get_color,
    }

    -- Invalidate backdrop texture cache whenever columns change
    deathstats.scoreboard_bg_cache = {}
end

--- Unregister an existing scoreboard column by id
---@param id string Unique column identifier
function deathstats.unregister_scoreboard_column(id)
    if not id then return end
    deathstats.registered_columns[id] = nil
    deathstats.scoreboard_bg_cache = {}
end

--- Query active registered scoreboard columns sorted by their order attribute
---@return table columns Sorted array of column definition tables
function deathstats.get_ordered_scoreboard_columns()
    local cols = {}
    for id, col_def in pairs(deathstats.registered_columns or {}) do
        local c = table.copy(col_def)
        c.id = id
        table.insert(cols, c)
    end
    table.sort(cols, function(a, b)
        if (a.order or 50) ~= (b.order or 50) then
            return (a.order or 50) < (b.order or 50)
        end
        return (a.id or "") < (b.id or "")
    end)
    return cols
end

-- Scoreboard HUD & Formspec Forward Declarations (Implemented in scoreboard.lua)
deathstats.show_scoreboard_hud = deathstats.show_scoreboard_hud or function(_player) end
deathstats.hide_scoreboard_hud = deathstats.hide_scoreboard_hud or function(_player) end
deathstats.update_scoreboard_hud = deathstats.update_scoreboard_hud or function(_player) end
deathstats.show_scoreboard_formspec = deathstats.show_scoreboard_formspec or function(_player) end
deathstats.close_scoreboard_formspec = deathstats.close_scoreboard_formspec or function(_player) end
deathstats.is_player_afk = deathstats.is_player_afk or function(_player_or_name) return false end
deathstats.is_player_dead = deathstats.is_player_dead or function(_player_or_name) return false end
deathstats.reset_player_activity = deathstats.reset_player_activity or function(_player_or_name) end
deathstats.get_player_armor_points = deathstats.get_player_armor_points or function(_player) return 0 end
deathstats.get_player_ping = deathstats.get_player_ping or function(_player_name) return 0 end
deathstats.get_player_hp = deathstats.get_player_hp or function(_player) return 0 end
deathstats.get_scoreboard_cell_color = deathstats.get_scoreboard_cell_color or function(_col, _player, _item, _row_idx) return 0xFFFFFF end
deathstats.get_scoreboard_footer_text = deathstats.get_scoreboard_footer_text or function(_total, _visible) return "" end
deathstats.get_scoreboard_data = deathstats.get_scoreboard_data or function(_viewer_player, _precomputed_base) return {}, {} end
deathstats.calculate_player_score = deathstats.calculate_player_score or function(_pdata, _player, _cached_armor, _cached_hp) return 0, 0 end
