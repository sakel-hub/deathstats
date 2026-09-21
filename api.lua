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
local atan2 = math.atan2 or math.atan
local copy = table.copy
local VEC_ZERO = vector.new(0, 0, 0)
local GRAV_ACCEL = { x = 0, y = -9.81, z = 0 }
local FALL_VEL = { x = 0, y = -1.2, z = 0 }

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
        enable_corpse_ragdoll = core.settings:get_bool("deathstats_enable_corpse_ragdoll", true),
        ragdoll_force_multiplier = tonumber(core.settings:get("deathstats_ragdoll_force_multiplier")) or 1.0,
        ragdoll_max_velocity = tonumber(core.settings:get("deathstats_ragdoll_max_velocity")) or 18.0,
        ragdoll_tumbling = core.settings:get_bool("deathstats_ragdoll_tumbling", true),
        ragdoll_restitution = tonumber(core.settings:get("deathstats_ragdoll_restitution")) or 0.25,
        ragdoll_flail_rate = tonumber(core.settings:get("deathstats_ragdoll_flail_rate")) or 10.0,
        ragdoll_resting_poses = core.settings:get_bool("deathstats_ragdoll_resting_poses", true),
        enable_corpse_impact_sounds = core.settings:get_bool("deathstats_enable_corpse_impact_sounds", true),
        enable_slope_pitch = core.settings:get_bool("deathstats_enable_slope_pitch", true),
        enable_scoreboard = core.settings:get_bool("deathstats_enable_scoreboard", true),
        scoreboard_key = core.settings:get("deathstats_scoreboard_key") or "sneak_aux1",
        time_format = core.settings:get("deathstats_time_format") or "24h",
        scoreboard_update_interval = tonumber(core.settings:get("deathstats_scoreboard_update_interval")) or 1.0,
        scoreboard_suppress_chat = core.settings:get_bool("deathstats_scoreboard_suppress_chat", true),
        afk_timeout = tonumber(core.settings:get("deathstats_afk_timeout")) or 120,
        chat_death_coords = core.settings:get_bool("deathstats_chat_death_coords", true),
        enable_corpse_inspect = core.settings:get_bool("deathstats_enable_corpse_inspect", true),
        enable_mvp_badges = core.settings:get_bool("deathstats_enable_mvp_badges", true),
        enable_hall_of_fame = core.settings:get_bool("deathstats_enable_hall_of_fame", true),
        corpse_decay_time = tonumber(core.settings:get("deathstats_corpse_decay_time")) or 180,
        enable_revenge = core.settings:get_bool("deathstats_enable_revenge", true),
        announce_revenge = core.settings:get_bool("deathstats_announce_revenge", true),
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
        row_viewer = "#88181844",
        tab_bar_bg = "#181822",
        tab_bar_sep = "#3a3a4c",
        tooltip_bg = "#141418f0",

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
    open_scoreboard_tabs = {},
    scoreboard_bg_cache = {},
    formatted_name_cache = {},
    node_tile_texture_cache = {},
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
    last_blow = {},
    last_death_reason = {},
    respawn_immunity = {},
    left_players = {},
    compat_hunger = {},
    compat_skins = {},
    player_corpses = {},
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
        players_slain = {},    -- [victim_name] = count
        killstreak = 0,
        revenges = 0,
        vendetta_target = nil,
        items_crafted = 0,
        items_consumed = 0,
        distance_traveled = 0,
        time_alive = 0,
        deaths = 0,
        last_cause = "None",
        last_weapon = "None",
        last_killer = "None",
        deaths_by_category = {}, -- [category] = count
        killers_count = {},      -- [killer_name] = count
        personal_bests = {
            survival_time = 0,
            kills = 0,
            killstreak = 0,
            blocks_mined = 0,
            total_ores = 0,
            damage_dealt = 0,
        },
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

--- Format numbers into compact strings (>= 1,000 -> 1k, >= 2,000 -> 2k, >= 10,000 -> 10k, >= 1,000,000 -> 1M)
---@param n number The numeric value to format
---@return string The compact formatted string (e.g. "1k", "10k", "2M")
function deathstats.format_compact_number(n)
    if not n then return "0" end
    n = tonumber(n) or 0
    if n >= 1000000 then
        local m = math.floor(n / 1000000)
        return m .. "M"
    elseif n >= 1000 then
        local k = math.floor(n / 1000)
        return k .. "k"
    else
        return tostring(math.floor(n))
    end
end

--- Convert an internal node name or item name into a clean, human-readable title
--- Retrieves clean description from registered item definition, or falls back to capitalized name
---@param item_name string The raw registered technical item or node name (e.g. "default:stone_with_iron")
---@return string The sanitized, capitalized human-readable title (e.g. "Iron Ore")
function deathstats.format_name(item_name)
    if not item_name or item_name == "" then
        return S("Unknown")
    end
    local cache = deathstats.formatted_name_cache
    local cached = cache and cache[item_name]
    if cached then
        return cached
    end

    local result = nil
    -- Check if registered item has a description
    local def = core.registered_items[item_name]
    local desc = def and (def.short_description or def.description)
    if desc and desc ~= "" then
        -- Only take first line of multiline description and strip color/translation escapes
        desc = desc:match("^[^\r\n]+") or desc
        desc = core.strip_colors(desc)
        desc = desc:gsub("\27%b()", ""):gsub("\27.", ""):match("^%s*(.-)%s*$")
        if desc and desc ~= "" then
            result = desc
        end
    end

    if not result then
        -- Fallback: extract identifier part after colon and format with spaces and title case
        local sub = string.match(item_name, ":(.+)$") or item_name
        sub = sub:gsub("(%l)(%u)", "%1 %2")
        sub = sub:gsub("_", " ")
        result = (sub:gsub("(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end))
    end

    if cache then
        cache[item_name] = result
    end
    return result
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
    local name = player.get_player_name and player:get_player_name()
    local cam_data = name and deathstats.player_camera_data[name]
    local pos = (cam_data and (cam_data.orbit_center or cam_data.initial_death_pos))
        or (player.get_pos and player:get_pos())
    if pos then
        core.sound_play("deathstats_death", {
            pos = pos,
            max_hear_distance = 16,
            gain = 1.0,
            pitch = 1.0,
        })
    else
        local player_name = name or (player.get_player_name and player:get_player_name())
        core.sound_play("deathstats_death", {
            to_player = player_name,
            gain = 1.0,
            pitch = 1.0,
        })
    end
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

    -- Direct player punch
    if puncher:is_player() then
        local item = puncher:get_wielded_item()
        local iname = deathstats.get_stack_name(item)
        if iname == "" then iname = nil end
        return puncher, true, nil, iname
    end

    -- Lua Entity (arrow, sword projectile, or mob)
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
-- Mob & Ore Entity Validation & Data Migration
-- ==========================================

--- Validate whether an entity is a genuine living mob (monster, animal, npc)
--- Rejects projectiles, falling nodes, items, boats/carts, and internal utility entities
---@param ent_name string Technical registered entity name
---@param ent_def table|nil Entity definition table
---@param ent_instance table|nil Living LuaEntity instance
---@return boolean is_mob True if the entity is a valid mob
function deathstats.is_mob_entity(ent_name, ent_def, ent_instance)
    if not ent_name or ent_name == "" then return false end
    ent_def = ent_def or core.registered_entities[ent_name]
    local low = ent_name:lower()

    -- Exclude engine built-in, internal and inanimate entities
    if low:find("^__builtin:") or low:find("^deathstats:") then
        return false
    end

    -- Exclude vehicles, itemframes, nametags, and signs
    if low:find("boat") or low:find("cart") or low:find("itemframe")
        or low:find("item_entity") or low:find("nametag") or low:find("sign")
        or low:find("display") or low:find("decoration") then
        return false
    end

    -- Exclude projectiles, ammunition, and weapons
    if low:find("arrow") or low:find("bullet") or low:find("bolt")
        or low:find("projectile") or low:find("missile") or low:find("laser")
        or low:find("bomb") or low:find("grenade") or low:find("tnt")
        or low:find("fireball") or low:find("snowball") or low:find("shot") then
        return false
    end

    -- Exclude dropped items
    if (ent_instance and ent_instance.itemstring) or (ent_def and ent_def.itemstring) then
        return false
    end

    -- Positive mob classifications (mobs_redo, creatura, animalia, petz, mobkit, native)
    if ent_def then
        if ent_def.type == "monster" or ent_def.type == "animal" or ent_def.type == "npc" or ent_def.type == "mob" then
            return true
        end
        if ent_def._csm_mob or ent_def.is_mob or ent_def._is_mob then
            return true
        end
    end
    if ent_instance then
        if ent_instance.type == "monster" or ent_instance.type == "animal" or ent_instance.type == "npc" or ent_instance.type == "mob" then
            return true
        end
        if ent_instance._csm_mob or ent_instance.is_mob or ent_instance._is_mob then
            return true
        end
    end

    -- Name heuristics (mobs_*, animal, monster, zombie, etc.)
    if low:find("mob") or low:find("monster") or low:find("animal") or low:find("creatura")
        or low:find("creature") or low:find("npc") or low:find("zombie") or low:find("skeleton")
        or low:find("spider") or low:find("creeper") or low:find("slime") or low:find("ghost")
        or low:find("golem") or low:find("dragon") or low:find("wolf") or low:find("bear") then
        return true
    end

    -- Living entity properties check (hp_max, health, etc.)
    local hp = (ent_instance and (ent_instance.health or ent_instance.hp))
        or (ent_def and (ent_def.health or ent_def.hp))
    local max_hp = (ent_instance and (ent_instance.hp_max or ent_instance.max_hp))
        or (ent_def and (ent_def.hp_max or ent_def.max_hp))
    if not max_hp and ent_def and ent_def.initial_properties then
        max_hp = ent_def.initial_properties.hp_max
    end
    if (hp and hp > 0) or (max_hp and max_hp > 0) then
        return true
    end

    return false
end

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

    -- Check recent PvP or Mob punch / projectile strike (within 3.5 seconds)
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

    -- Check out-of-world fall (below mapgen bounds)
    if pos.y < -30000 then
        return {
            category = "unknown",
            reason_text = S("Fell out of the world"),
            funny_note = deathstats.get_funny_note("unknown"),
        }
    end

    -- Check lava immersion
    if node_feet.name:find("lava") or node_head.name:find("lava") then
        return {
            category = "lava",
            reason_text = S("Melted in searing lava"),
            funny_note = deathstats.get_funny_note("lava"),
        }
    end

    -- Check fire / burning
    if node_feet.name:find("fire") or node_head.name:find("fire") then
        return {
            category = "fire",
            reason_text = S("Burned to ashes"),
            funny_note = deathstats.get_funny_note("fire"),
        }
    end

    -- Check drowning (head submerged in water or liquid with no breath)
    local breath = player:get_breath()
    local in_water = node_head.name:find("water") or core.get_item_group(node_head.name, "water") ~= 0
    if in_water or (breath and breath <= 0) then
        return {
            category = "drown",
            reason_text = S("Drowned in deep water"),
            funny_note = deathstats.get_funny_note("drown"),
        }
    end

    -- Check suffocation (head buried inside solid opaque node)
    local head_def = core.registered_nodes[node_head.name]
    if head_def and head_def.walkable and head_def.drawtype == "normal" and not node_head.name:find("air") then
        return {
            category = "suffocate",
            reason_text = S("Suffocated inside @1", deathstats.format_name(node_head.name)),
            funny_note = deathstats.get_funny_note("suffocate"),
        }
    end

    -- Check high downward velocity recorded just before death
    local fall_speed = deathstats.recent_falls[name] or 0
    if fall_speed < -12.0 then
        return {
            category = "fall",
            reason_text = S("Fell from a high place"),
            funny_note = deathstats.get_funny_note("fall"),
        }
    end

    -- Check dehydration / thirst (thirsty mod)
    local was_dehydrated = deathstats.is_player_dehydrated(player)
        or (deathstats.recent_dehydrations[name] and (core.get_gametime() - deathstats.recent_dehydrations[name] <= 3.5))
    if was_dehydrated then
        return {
            category = "thirst",
            reason_text = S("Died of dehydration"),
            funny_note = deathstats.get_funny_note("thirst"),
        }
    end

    -- Check starvation (hbhunger, stamina, hunger_ng, hudbars, or inventory hunger)
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

    -- Fallback unknown
    return {
        category = "unknown",
        reason_text = "Died from mysterious causes",
        funny_note = deathstats.get_funny_note("unknown"),
    }
end

--- Describe elevation/depth zone for the death location
---@param y number|nil The vertical elevation
---@return string depth_desc Human-readable depth or altitude description
function deathstats.get_depth_description(y)
    if not y then return S("Unknown Altitude") end
    if y >= 1000 then
        return S("Upper Atmosphere")
    elseif y >= 500 then
        return S("Sky Realm")
    elseif y >= 10 then
        return S("Highlands / Surface")
    elseif y >= -10 then
        return S("Sea Level")
    elseif y >= -200 then
        return S("Shallow Caverns")
    elseif y >= -1000 then
        return S("Deep Underground")
    elseif y >= -5000 then
        return S("Abyssal Depths")
    else
        return S("The Void")
    end
end

--- Get biome name at a given 3D position
---@param pos Vector|nil The position to query
---@return string biome_name Clean formatted biome name
function deathstats.get_biome_at_pos(pos)
    if not pos then return S("Unknown") end
    if core.get_biome_data then
        local bdata = core.get_biome_data(pos)
        if bdata and bdata.biome and core.get_biome_name then
            local bname = core.get_biome_name(bdata.biome)
            if bname and bname ~= "" then
                return deathstats.format_name(bname)
            end
        end
    end
    -- Fallback to elevation context
    if pos.y < -10 then
        return S("Underground")
    elseif pos.y > 100 then
        return S("Sky")
    else
        return S("Wilderness")
    end
end

--- Enrich death analysis table with coordinates, depth, biome, killer HP and fall metrics
---@param res table Death analysis table
---@param player ObjectRef The player who died
---@param puncher ObjectRef|nil Optional killer entity or puncher
---@return table enriched The enriched death analysis table
function deathstats.enrich_death_info(res, player, puncher)
    -- Handle argument swap if called as enrich_death_info(player, res, puncher)
    if (res and res.is_player and (not player or not player.is_player))
       or (res and res.get_player_name and (not player or not player.get_player_name)) then
        local tmp = res
        res = player
        player = tmp
    end
    if not res then res = {} end
    if puncher then
        res.puncher = res.puncher or puncher
    end
    local pname = player and player.get_player_name and player:get_player_name()

    -- Location, Depth & Biome
    if not res.pos and player and player.get_pos then
        local pos = player:get_pos()
        if pos then
            res.pos = vector.round(pos)
            res.depth_desc = deathstats.get_depth_description(pos.y)
            res.biome_name = deathstats.get_biome_at_pos(pos)
        end
    elseif res.pos and not res.depth_desc then
        res.depth_desc = deathstats.get_depth_description(res.pos.y)
        res.biome_name = res.biome_name or deathstats.get_biome_at_pos(res.pos)
    end
    if res.pos then
        res.death_pos = res.pos
        res.coords_str = string.format("(X: %d, Y: %d, Z: %d)", res.pos.x, res.pos.y, res.pos.z)
    end

    -- Killer Remaining Health (PvP and PvE Mob)
    local is_pvp = (res.category == "pvp" or res.category == "player" or res.type == "pvp" or res.type == "player")
    local is_mob = (res.category == "mob" or res.is_mob or res.type == "mob")
    local kname = res.killer_name or res.killer
    if is_pvp then
        local kplayer = (res.puncher and res.puncher.is_player and res.puncher:is_player() and res.puncher)
            or (kname and core.get_player_by_name(kname))
        if kplayer and kplayer:is_player() then
            res.killer_hp = math.max(0, kplayer:get_hp())
            local props = kplayer.get_properties and kplayer:get_properties()
            res.killer_max_hp = (props and props.hp_max) or 20
            res.killer_hp_max = res.killer_max_hp
        else
            local last_punch = pname and deathstats.recent_punches[pname]
            if last_punch and last_punch.attacker_hp then
                res.killer_hp = last_punch.attacker_hp
                res.killer_max_hp = last_punch.attacker_max_hp or 20
                res.killer_hp_max = res.killer_max_hp
            end
        end
    elseif is_mob or res.puncher or res.attacker then
        local kattacker = res.puncher or res.attacker
        if kattacker and (not kattacker.is_player or not kattacker:is_player()) then
            local luaent = kattacker.get_luaentity and kattacker:get_luaentity()
            local hp = (luaent and (luaent.health or luaent.hp))
                or (kattacker.get_hp and kattacker:get_hp())
            local max_hp = (luaent and (luaent.hp_max or luaent.max_hp))
            if not max_hp and kattacker.get_properties then
                local props = kattacker:get_properties()
                max_hp = props and props.hp_max
            end
            if hp and hp > 0 then
                res.killer_hp = math.max(0, math.floor(hp + 0.5))
                res.killer_max_hp = math.max(1, math.floor((max_hp or hp) + 0.5))
                res.killer_hp_max = res.killer_max_hp
            end
        end
        if not res.killer_hp then
            local last_punch = pname and deathstats.recent_punches[pname]
            if last_punch and last_punch.attacker_hp then
                res.killer_hp = last_punch.attacker_hp
                res.killer_max_hp = last_punch.attacker_max_hp or 20
                res.killer_hp_max = res.killer_max_hp
            end
        end
    end

    -- Fall Height & Impact Speed
    if res.category == "fall" then
        local peak_y = deathstats.fall_peaks and pname and deathstats.fall_peaks[pname]
        local dpos = res.pos or (player.get_pos and player:get_pos())
        if peak_y and dpos then
            res.fall_height = math.max(1, math.floor(peak_y - dpos.y + 0.5))
        end
        local recent_v = deathstats.recent_falls and pname and deathstats.recent_falls[pname]
        local lb = deathstats.last_blow and pname and deathstats.last_blow[pname]
        local vy = (lb and lb.velocity and lb.velocity.y) or recent_v
        if vy and math.abs(vy) > 0.5 then
            res.fall_speed = math.abs(math.floor(vy * 10 + 0.5) / 10)
            if not res.fall_height and res.fall_speed > 0 then
                res.fall_height = math.max(1, math.floor((res.fall_speed * res.fall_speed) / 19.62 + 0.5))
            end
        end
        if not res.fall_height and res.damage and res.damage > 0 then
            res.fall_height = math.max(1, math.floor(res.damage + 3))
            res.fall_speed = math.floor(math.sqrt(2 * 9.81 * res.fall_height) * 10 + 0.5) / 10
        elseif res.fall_height and (not res.fall_speed or res.fall_speed <= 0) then
            res.fall_speed = math.floor(math.sqrt(2 * 9.81 * res.fall_height) * 10 + 0.5) / 10
        end
    end

    return res
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
    local res = deathstats.analyze_death_raw(player, reason)
    return deathstats.enrich_death_info(res, player)
end

--- Internal raw death cause analyzer
---@param player ObjectRef The deceased player object
---@param reason table|nil The engine reason table from on_dieplayer or show_death_screen
---@return table analysis The un-enriched death metadata table
function deathstats.analyze_death_raw(player, reason)
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

--- Calculate initial velocity and angular velocity for the ragdoll corpse based on the last blow
local function safe_normalize(v)
    if not v then
        return vector.zero()
    end
    if vector.normalize then
        local res = vector.normalize(v)
        if res then return res end
    end
    local vx, vy, vz = v.x or 0, v.y or 0, v.z or 0
    local len = math.sqrt(vx * vx + vy * vy + vz * vz)
    if len == 0 then
        return vector.zero()
    end
    return vector.new(vx / len, vy / len, vz / len)
end

---@param player ObjectRef|nil The deceased player
---@param death_info table|nil The death analysis table
---@param last_blow table|nil The recorded lethal blow data
---@return Vector velocity Initial 3D velocity vector for the corpse
---@return Vector rot_speed Initial angular tumbling velocity (pitch, yaw, roll)
function deathstats.calculate_corpse_impulse(player, death_info, last_blow)
    if deathstats.config.enable_corpse_ragdoll == false then
        return vector.zero(), vector.zero()
    end

    local pname = player and player.get_player_name and player:get_player_name()
    local last_punch = pname and deathstats.recent_punches[pname]
    local lb = last_blow or (pname and deathstats.last_blow[pname])

    -- Determine damage of the last blow
    local damage = (lb and lb.damage)
        or (last_punch and last_punch.damage)
        or (death_info and death_info.damage)
        or 5
    damage = math.max(1.0, tonumber(damage) or 1.0)

    -- Determine knockback direction vector
    local ppos = (player and player.get_pos and player:get_pos()) or (lb and lb.pos)
    local dir_h = nil

    local is_fall = death_info and (death_info.category == "fall" or death_info.type == "fall")
    local is_explosion = death_info and (death_info.category == "explode" or death_info.category == "explosion"
        or death_info.type == "explode" or death_info.type == "explosion"
        or (death_info.reason_text and death_info.reason_text:lower():find("explos"))
        or (lb and ((lb.blast_pos ~= nil) or (lb.reason and (lb.reason.type == "explosion" or lb.reason.type == "explode" or (lb.reason.node and lb.reason.node:find("tnt")))))))

    -- True 3D Explosion Blast Vector (Epicenter -> Player)
    if is_explosion then
        local blast_pos = (death_info and (death_info.blast_pos or death_info.explosion_pos or death_info.pos_origin))
            or (lb and (lb.blast_pos or (lb.reason and (lb.reason.pos or lb.reason.origin))))
        if not blast_pos and ppos and deathstats.recent_explosions then
            local now = core.get_gametime()
            local best_d = 20.0
            for _, exp in ipairs(deathstats.recent_explosions) do
                if (now - exp.time) <= 4.0 then
                    local d = vector.distance(exp.pos, ppos)
                    if d < best_d then
                        best_d = d
                        blast_pos = exp.pos
                    end
                end
            end
        end
        if blast_pos and ppos then
            local d = vector.direction(blast_pos, ppos)
            if d.x ~= 0 or d.z ~= 0 then
                dir_h = safe_normalize({ x = d.x, y = 0, z = d.z })
            end
        end
    end

    -- Live player velocity at death time (captures engine knockback vectors)
    if not dir_h and player and player.get_velocity then
        local pvel = player:get_velocity()
        if pvel and (pvel.x ~= 0 or pvel.z ~= 0) then
            local v_mag = math.sqrt(pvel.x * pvel.x + pvel.z * pvel.z)
            if v_mag > 0.3 then
                dir_h = safe_normalize({ x = pvel.x, y = 0, z = pvel.z })
            end
        end
    end

    -- Recent punch direction
    if not dir_h and last_punch and last_punch.dir and (last_punch.dir.x ~= 0 or last_punch.dir.z ~= 0) then
        dir_h = safe_normalize({ x = last_punch.dir.x, y = 0, z = last_punch.dir.z })
    elseif not dir_h and last_punch and last_punch.hitter_pos and ppos then
        local d = vector.direction(last_punch.hitter_pos, ppos)
        if d.x ~= 0 or d.z ~= 0 then
            dir_h = safe_normalize({ x = d.x, y = 0, z = d.z })
        end
    end

    -- Lethal blow reason object (mob, projectile, player)
    if not dir_h and lb and lb.reason and lb.reason.object and ppos and lb.reason.object.get_pos then
        local opos = lb.reason.object:get_pos()
        if opos then
            local d = vector.direction(opos, ppos)
            if d.x ~= 0 or d.z ~= 0 then
                dir_h = safe_normalize({ x = d.x, y = 0, z = d.z })
            end
        end
    end

    -- Residual velocity
    if not dir_h and lb and lb.velocity then
        local vx, vz = lb.velocity.x or 0, lb.velocity.z or 0
        if math.abs(vx) > 0.5 or math.abs(vz) > 0.5 then
            dir_h = safe_normalize({ x = vx, y = 0, z = vz })
        end
    end

    -- Opposite of player look direction
    local ldir = player and player.get_look_dir and player:get_look_dir()
    if not ldir and player and player.get_look_horizontal then
        local yaw = player:get_look_horizontal() or 0
        local pitch = (player.get_look_vertical and player:get_look_vertical()) or 0
        local cos_p = math.cos(pitch)
        ldir = vector.new(-math.sin(yaw) * cos_p, math.sin(pitch), math.cos(yaw) * cos_p)
    end
    if not dir_h and ldir then
        if ldir.x ~= 0 or ldir.z ~= 0 then
            dir_h = safe_normalize({ x = -ldir.x, y = 0, z = -ldir.z })
        end
    end

    -- Fallback: Yaw direction
    if not dir_h then
        local yaw = (player and player.get_look_horizontal and player:get_look_horizontal()) or 0
        dir_h = vector.new(-math.sin(yaw), 0, -math.cos(yaw))
    end

    -- Determine forward/backward alignment of knockback relative to player facing
    local dot_fwd = (ldir and dir_h) and (ldir.x * dir_h.x + ldir.z * dir_h.z) or 0
    local pitch_sign = (dot_fwd > 0.2) and 1.0 or ((dot_fwd < -0.2) and -1.0 or 1.0)

    local rot_mt = {
        __lt = function(a, b)
            local av = (type(a) == "table" and (a.x or a[1])) or a
            local bv = (type(b) == "table" and (b.x or b[1])) or b
            return av < bv
        end,
        __gt = function(a, b)
            local av = (type(a) == "table" and (a.x or a[1])) or a
            local bv = (type(b) == "table" and (b.x or b[1])) or b
            return av > bv
        end,
    }

    -- Calculate Force & Velocity based on Damage of last blow
    local mult = deathstats.config.ragdoll_force_multiplier or 1.0
    local max_vel = deathstats.config.ragdoll_max_velocity or 18.0

    local is_passive = not last_punch and not (lb and lb.reason and lb.reason.object) and death_info and
        (death_info.category == "drown" or death_info.category == "starve" or death_info.category == "hunger"
         or death_info.category == "suffocation" or death_info.category == "suffocate" or death_info.category == "poison")

    if is_passive then
        -- Passive deaths (drowning, suffocation, hunger, poison):
        -- Corpse gently collapses in place with zero knockback impulse
        return vector.zero(), setmetatable(vector.zero(), rot_mt), 0, 0, 0
    end

    if is_explosion then
        -- Explosion: high radial blast velocity and chaotic 3D spin
        local exp_speed = math.min(max_vel, (3.5 + damage * 0.65) * mult)
        exp_speed = math.max(exp_speed, 2.0)
        local exp_lift = math.min(8.0, (2.5 + damage * 0.3) * mult)
        exp_lift = math.max(exp_lift, 2.0)
        local exp_vel = vector.new(dir_h.x * exp_speed, exp_lift, dir_h.z * exp_speed)
        local rot_speed = vector.zero()
        if deathstats.config.ragdoll_tumbling ~= false then
            local exp_pitch_sign = (dot_fwd > 0.1) and -1.0 or ((dot_fwd < -0.1) and 1.0 or -1.0)
            local t_pitch = exp_speed * 1.1 * exp_pitch_sign
            local t_roll = (math.random() - 0.5) * exp_speed * 1.3
            local t_yaw = (math.random() - 0.5) * exp_speed * 0.8
            rot_speed = vector.new(t_pitch, t_yaw, t_roll)
        end
        return exp_vel, setmetatable(rot_speed, rot_mt), rot_speed.x, rot_speed.y, rot_speed.z
    end

    local base_speed = is_fall and 0.8 or 1.5
    local dmg_scale = is_fall and 0.15 or 0.45

    local speed_h = (base_speed + damage * dmg_scale) * mult
    speed_h = math.min(speed_h, max_vel)
    speed_h = math.max(speed_h, 1.0)

    local lift_base = is_fall and 1.5 or 1.2
    local lift_scale = is_fall and 0.08 or 0.22
    local lift_max = is_fall and 4.0 or 8.0
    local vel_y = (lift_base + damage * lift_scale) * mult
    vel_y = math.min(vel_y, lift_max)
    vel_y = math.max(vel_y, 1.0)

    local initial_velocity = vector.new(dir_h.x * speed_h, vel_y, dir_h.z * speed_h)

    -- Initial angular tumbling velocity
    local rot_speed = vector.zero()
    if deathstats.config.ragdoll_tumbling ~= false then
        local tumble_pitch = speed_h * 0.7 * pitch_sign
        local tumble_roll = (math.random() - 0.5) * (2.5 + speed_h * 1.2)
        rot_speed = vector.new(tumble_pitch, 0, tumble_roll)
    end

    return initial_velocity, setmetatable(rot_speed, rot_mt), rot_speed.x, rot_speed.y, rot_speed.z
end

--- Helper to generate a random floating point number between min_val and max_val
local function random_float(min_val, max_val)
    return min_val + math.random() * (max_val - min_val)
end

--- Apply immediate physical impact reaction to corpse limbs when colliding with ground during bounce
---@param corpse ObjectRef The corpse entity object
---@param impact_vy number Downward velocity of the impact
---@param _rebound_v Vector Resulting rebound velocity vector
---@param _rot table|nil Current rotation {x, y, z}
---@param bounce_count number Current bounce index (1 or 2)
function deathstats.apply_corpse_bounce_impact(corpse, impact_vy, _rebound_v, _rot, bounce_count)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local vy = math.abs(tonumber(impact_vy) or 4.0)
    local shock = math.min(1.6, math.max(0.35, vy / 5.5))
    local bounce_damp = (bounce_count and bounce_count > 1) and 0.65 or 1.0
    local eff_shock = shock * bounce_damp

    -- Inertial shock: sudden deceleration whips limbs and snaps head
    local head_pitch = math.rad(-25) * eff_shock
    local head_yaw = ((math.random() < 0.5) and -1 or 1) * math.rad(random_float(15, 30)) * eff_shock
    local arm_pitch = math.rad(random_float(20, 45)) * eff_shock
    local arm_splay = math.rad(random_float(30, 60)) * eff_shock
    local leg_pitch = math.rad(random_float(-12, 18)) * eff_shock
    local leg_splay = math.rad(random_float(20, 45)) * eff_shock

    deathstats.rotate_corpse_bone(corpse, "Head", vector.new(head_pitch, head_yaw, 0))
    deathstats.rotate_corpse_bone(corpse, "Arm_Left", vector.new(arm_pitch, math.rad(10) * eff_shock, -arm_splay))
    deathstats.rotate_corpse_bone(corpse, "Arm_Right", vector.new(arm_pitch, math.rad(-10) * eff_shock, arm_splay))
    deathstats.rotate_corpse_bone(corpse, "Leg_Left", vector.new(leg_pitch, 0, -leg_splay))
    deathstats.rotate_corpse_bone(corpse, "Leg_Right", vector.new(leg_pitch, 0, leg_splay))
end

--- Apply final limp resting fractures or organic pose angles to corpse limbs on landing
---@param corpse ObjectRef The corpse entity object
---@param impact_damage number|nil Damage of the lethal impact
---@param pose_type string|nil Optional resting pose ("supine", "prone", "lateral")
---@param hanging_legs boolean|nil True if legs hang over a ledge/drop
---@param roll_rad number|nil Optional corpse roll angle in radians
function deathstats.settle_ragdoll_limbs(corpse, impact_damage, pose_type, hanging_legs, roll_rad)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local dmg = tonumber(impact_damage) or 5
    local scale = math.min(1.35, 1.0 + math.max(0, dmg - 10) * 0.015)
    local ptype = pose_type or "supine"

    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    local roll_z = roll_rad or (luaent and luaent._rot and luaent._rot.z)
        or (corpse.get_rotation and corpse:get_rotation().z) or 0
    local is_right_side = (roll_z < -0.1)

    local custom = {}
    if ptype == "prone" then
        -- Prone: Face down on stomach with organic archetypes (collapsed, reach, sprawl)
        local arch = math.random(1, 3)
        local head_sign = (math.random() < 0.5) and -1 or 1
        if arch == 1 then
            -- Collapsed: arms drawn up near shoulders, legs straight
            custom["Head"] = math.rad(head_sign * random_float(35, 55))
            custom["Arm_Left"] = math.rad(random_float(-55, -35) * scale)
            custom["Arm_Right"] = math.rad(random_float(35, 55) * scale)
            custom["Leg_Left"] = math.rad(random_float(-14, -6) * scale)
            custom["Leg_Right"] = math.rad(random_float(6, 14) * scale)
        elseif arch == 2 then
            -- Asymmetric reach: one arm forward, one trailing back
            local reach_left = (math.random() < 0.5)
            custom["Head"] = math.rad(head_sign * random_float(40, 65))
            if reach_left then
                custom["Arm_Left"] = math.rad(random_float(-75, -50) * scale)
                custom["Arm_Right"] = math.rad(random_float(15, 35) * scale)
                custom["Leg_Left"] = math.rad(random_float(-12, -4) * scale)
                custom["Leg_Right"] = math.rad(random_float(15, 30) * scale)
            else
                custom["Arm_Left"] = math.rad(random_float(-35, -15) * scale)
                custom["Arm_Right"] = math.rad(random_float(50, 75) * scale)
                custom["Leg_Left"] = math.rad(random_float(-30, -15) * scale)
                custom["Leg_Right"] = math.rad(random_float(4, 12) * scale)
            end
        else
            -- Limp sprawl: relaxed random limbs
            custom["Head"] = math.rad(head_sign * random_float(30, 60))
            custom["Arm_Left"] = math.rad(random_float(-65, -40) * scale)
            custom["Arm_Right"] = math.rad(random_float(40, 65) * scale)
            custom["Leg_Left"] = math.rad(random_float(-22, -10) * scale)
            custom["Leg_Right"] = math.rad(random_float(10, 22) * scale)
        end
    elseif ptype == "lateral" then
        -- Lateral: Lying on side with organic archetypes (curled, runner, parallel, splay)
        local arch = math.random(1, 4)
        local head_tilt
        local l_arm, r_arm, l_leg, r_leg

        if arch == 1 then
            -- Semi-fetal / curled: legs resting closely together (spread only 8° to 16°)
            l_leg = random_float(-24, -14) * scale
            r_leg = random_float(-12, -2) * scale
            l_arm = random_float(-35, -18) * scale
            r_arm = random_float(18, 38) * scale
            head_tilt = random_float(-25, -5)
        elseif arch == 2 then
            -- Staggered runner: one leg forward, one trailing back (spread 30° to 45°)
            l_leg = random_float(-32, -20) * scale
            r_leg = random_float(10, 24) * scale
            l_arm = random_float(-35, -15) * scale
            r_arm = random_float(-10, 20) * scale
            head_tilt = random_float(-15, 15)
        elseif arch == 3 then
            -- Limp parallel: legs almost straight with minimal separation (< 18°)
            l_leg = random_float(-15, -6) * scale
            r_leg = random_float(6, 15) * scale
            l_arm = random_float(-20, -8) * scale
            r_arm = random_float(8, 20) * scale
            head_tilt = random_float(-12, 12)
        else
            -- Relaxed splay: natural asymmetric spread
            l_leg = random_float(-35, -20) * scale
            r_leg = random_float(15, 32) * scale
            l_arm = random_float(-35, -15) * scale
            r_arm = random_float(20, 38) * scale
            head_tilt = random_float(-20, 20)
        end

        -- Mirror left/right symmetrically if lying on the right side
        if is_right_side then
            custom["Arm_Left"] = math.rad(-r_arm)
            custom["Arm_Right"] = math.rad(-l_arm)
            custom["Leg_Left"] = math.rad(-r_leg)
            custom["Leg_Right"] = math.rad(-l_leg)
            custom["Head"] = math.rad(-head_tilt)
        else
            custom["Arm_Left"] = math.rad(l_arm)
            custom["Arm_Right"] = math.rad(r_arm)
            custom["Leg_Left"] = math.rad(l_leg)
            custom["Leg_Right"] = math.rad(r_leg)
            custom["Head"] = math.rad(head_tilt)
        end
    else
        -- Supine: Lying flat on back with organic archetypes (sprawl, relaxed, folded, impact)
        local arch = math.random(1, 4)
        local head_angle = random_float(-45, 45)
        if arch == 1 then
            -- Asymmetric sprawl
            local fling_left = (math.random() < 0.5)
            if fling_left then
                custom["Arm_Left"] = math.rad(random_float(-80, -50) * scale)
                custom["Arm_Right"] = math.rad(random_float(15, 35) * scale)
                custom["Leg_Left"] = math.rad(random_float(-45, -25) * scale)
                custom["Leg_Right"] = math.rad(random_float(8, 18) * scale)
            else
                custom["Arm_Left"] = math.rad(random_float(-35, -15) * scale)
                custom["Arm_Right"] = math.rad(random_float(50, 80) * scale)
                custom["Leg_Left"] = math.rad(random_float(-18, -8) * scale)
                custom["Leg_Right"] = math.rad(random_float(25, 45) * scale)
            end
            custom["Head"] = math.rad(head_angle)
        elseif arch == 2 then
            -- Relaxed rest
            custom["Arm_Left"] = math.rad(random_float(-35, -15) * scale)
            custom["Arm_Right"] = math.rad(random_float(15, 35) * scale)
            custom["Leg_Left"] = math.rad(random_float(-22, -10) * scale)
            custom["Leg_Right"] = math.rad(random_float(10, 22) * scale)
            custom["Head"] = math.rad(random_float(-25, 25))
        elseif arch == 3 then
            -- Peaceful folded
            custom["Arm_Left"] = math.rad(random_float(18, 40) * scale)
            custom["Arm_Right"] = math.rad(random_float(-40, -18) * scale)
            custom["Leg_Left"] = math.rad(random_float(-12, -4) * scale)
            custom["Leg_Right"] = math.rad(random_float(4, 12) * scale)
            custom["Head"] = math.rad(random_float(-15, 15))
        else
            -- Severe / impact sprawl with individual random jitter
            custom["Arm_Left"] = math.rad(random_float(-80, -55) * scale)
            custom["Arm_Right"] = math.rad(random_float(55, 80) * scale)
            custom["Leg_Left"] = math.rad(random_float(-45, -25) * scale)
            custom["Leg_Right"] = math.rad(random_float(25, 45) * scale)
            custom["Head"] = math.rad(head_angle * scale)
        end
    end

    -- Add organic per-joint micro-jitter (±2.5 degrees) so no two poses are identical
    for bone_name, angle in pairs(custom) do
        local jitter = math.rad(random_float(-2.5, 2.5))
        custom[bone_name] = angle + jitter
    end

    -- If legs hang over a ledge/cliff, flex them downward toward the drop
    if hanging_legs then
        local hang_pitch = (ptype == "prone") and math.rad(45)
            or (ptype == "supine") and math.rad(-45)
            or math.rad(-30)
        local cur_left_z = custom["Leg_Left"] or math.rad(-25 * scale)
        local cur_right_z = custom["Leg_Right"] or math.rad(25 * scale)
        custom["Leg_Left"] = vector.new(hang_pitch, 0, cur_left_z)
        custom["Leg_Right"] = vector.new(hang_pitch, 0, cur_right_z)
    end

    deathstats.fracture_corpse_limbs(corpse, custom)
end

--- Procedurally adjust corpse limb angles during flight with 3D aerodynamics, vertical drag & bounce shock
---@param corpse ObjectRef The corpse entity object
---@param velocity Vector Current velocity vector
---@param _base_yaw number Facing yaw of the corpse
---@param bounce_shock number|nil Optional active bounce shock impulse
function deathstats.update_ragdoll_flight_limbs(corpse, velocity, _base_yaw, bounce_shock)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local vx = (velocity and velocity.x) or 0
    local vy = (velocity and velocity.y) or 0
    local vz = (velocity and velocity.z) or 0
    local speed_h = math.sqrt(vx * vx + vz * vz)
    local speed_3d = math.sqrt(vx * vx + vy * vy + vz * vz)

    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    local t = (luaent and luaent._timer) or 0
    local shock = bounce_shock or (luaent and luaent._bounce_shock) or 0
    local shock_decay = math.min(1.2, math.max(0, shock))

    -- Prominent harmonic flutter from wind resistance (well above 0.05 dirty delta threshold)
    local flutter = math.sin(t * 14.0) * math.min(math.rad(18), speed_3d * math.rad(3.5))
    -- Multi-frame damped harmonic recoil ripples through limbs after hard impact
    local shock_osc = math.sin(t * 18.0) * shock_decay * math.rad(30.0)

    -- Dynamic 3D relative limb angles:
    -- Pitch (X-axis): air drag pushes limbs opposite vertical flight (vy > 0 pushes down, vy < 0 drags up)
    -- Yaw (Y-axis): limp sideways splay / oscillation
    -- Roll (Z-axis): planar splay outward along floor plane
    local arm_pitch = math.min(math.rad(55), math.max(math.rad(-35), -vy * 0.05)) + flutter + shock_osc * 0.5
    local arm_roll = math.min(math.rad(70), math.rad(20 + speed_h * 4.0 + shock_decay * 30.0))
    local leg_pitch = math.min(math.rad(40), math.max(math.rad(-25), -vy * 0.035)) - flutter * 0.5 + shock_osc * 0.3
    local leg_roll = arm_roll * 0.5 + shock_decay * math.rad(15)

    -- Arm_Left: roll negative (splay left), pitch drag
    deathstats.rotate_corpse_bone(corpse, "Arm_Left", vector.new(arm_pitch, flutter * 0.5, -arm_roll))
    -- Arm_Right: roll positive (splay right), pitch drag
    deathstats.rotate_corpse_bone(corpse, "Arm_Right", vector.new(arm_pitch, -flutter * 0.5, arm_roll))
    -- Leg_Left: roll negative (splay left)
    deathstats.rotate_corpse_bone(corpse, "Leg_Left", vector.new(leg_pitch, 0, -leg_roll))
    -- Leg_Right: roll positive (splay right)
    deathstats.rotate_corpse_bone(corpse, "Leg_Right", vector.new(leg_pitch, 0, leg_roll))
    -- Head: loose floppy neck with whiplash recoil
    local head_pitch = math.rad(-15) - math.min(math.rad(25), math.max(0, -vy * 0.03)) + flutter * 0.5 - shock_osc * 0.7
    local head_yaw = math.sin(t * 8.0) * math.min(math.rad(18), speed_h * 0.025) + (math.sin(t * 15.0) * shock_decay * math.rad(20))
    deathstats.rotate_corpse_bone(corpse, "Head", vector.new(head_pitch, head_yaw, 0))
end

--- Procedurally adjust corpse limbs while sliding along ground or tumbling down stairs/hills
--- Simulates ground surface friction drag, stair step bumps, and reactive limp jostling
---@param corpse ObjectRef The corpse entity object
---@param velocity Vector Current velocity vector
---@param _base_yaw number Facing yaw of the corpse
---@param bounce_shock number|nil Active bounce shock impulse
---@param slide_timer number|nil Accumulated sliding duration in seconds
function deathstats.update_ragdoll_slide_limbs(corpse, velocity, _base_yaw, bounce_shock, slide_timer)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local vx = (velocity and velocity.x) or 0
    local vz = (velocity and velocity.z) or 0
    local speed_h = math.sqrt(vx * vx + vz * vz)
    local t = slide_timer or 0

    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    local shock = bounce_shock or (luaent and luaent._bounce_shock) or 0
    local shock_decay = math.min(1.2, math.max(0, shock))

    -- Stair step & rough terrain micro-jostle (frequency increases with speed, 12 to 18 rad/s)
    local bump_freq = 12.0 + math.min(6.0, speed_h * 1.5)
    local arm_bump = math.sin(t * bump_freq) * math.min(math.rad(22), speed_h * math.rad(4.5))
    local leg_bump_l = math.sin(t * (bump_freq * 0.9)) * math.min(math.rad(18), speed_h * math.rad(3.5))
    local leg_bump_r = math.cos(t * (bump_freq * 0.9)) * math.min(math.rad(18), speed_h * math.rad(3.5))

    -- Damped bounce recoil oscillation ripples through limbs after hard surface hits
    local shock_osc = math.sin(t * 18.0) * shock_decay * math.rad(28.0)

    -- Dynamic surface drag: arms trailing backward along ground, splaying outward
    local arm_pitch = math.min(math.rad(45), math.max(math.rad(-20), math.rad(10) + arm_bump + shock_decay * math.rad(15)))
    local arm_roll = math.min(math.rad(65), math.rad(25 + speed_h * 4.5 + shock_decay * 25.0))

    -- Legs splay along ground plane: keep local X/Y pitch strictly 0 for planar ground alignment,
    -- varying Z-roll (lateral splay) with alternating step/stair jostle
    local leg_roll_base = math.rad(15 + speed_h * 2.5 + shock_decay * 15.0)
    local leg_roll_l = math.min(math.rad(45), math.max(math.rad(8), leg_roll_base + leg_bump_l))
    local leg_roll_r = math.min(math.rad(45), math.max(math.rad(8), leg_roll_base + leg_bump_r))

    -- Apply bone rotations:
    deathstats.rotate_corpse_bone(corpse, "Arm_Left", vector.new(arm_pitch, math.rad(8), -arm_roll))
    deathstats.rotate_corpse_bone(corpse, "Arm_Right", vector.new(arm_pitch, -math.rad(8), arm_roll))
    deathstats.rotate_corpse_bone(corpse, "Leg_Left", vector.new(0, 0, -leg_roll_l))
    deathstats.rotate_corpse_bone(corpse, "Leg_Right", vector.new(0, 0, leg_roll_r))

    -- Head: flopping from terrain bumps and bounce recoil
    local head_flop = math.sin(t * 10.0) * math.min(math.rad(20), speed_h * math.rad(3.0)) + shock_osc
    local head_pitch = math.rad(-12) + math.sin(t * bump_freq) * math.rad(8) - shock_decay * math.rad(15)
    deathstats.rotate_corpse_bone(corpse, "Head", vector.new(head_pitch, head_flop, 0))
end


--- Probe surface ground elevation at a specific horizontal coordinate
--- Uses raycast if available, falling back to discrete vertical node scan
---@param probe_x number X position to probe
---@param probe_z number Z position to probe
---@param start_y number Reference Y position
---@return number|nil elevation Ground contact Y elevation or nil if air/void
function deathstats.probe_ground_elevation(probe_x, probe_z, start_y)
    start_y = start_y or 0
    if core.raycast then
        local r_start = vector.new(probe_x, start_y + 0.8, probe_z)
        local r_end = vector.new(probe_x, start_y - 4.5, probe_z)
        local ray = core.raycast(r_start, r_end, false, false)
        for pt in ray do
            if pt.type == "node" and pt.under then
                local node = core.get_node_or_nil(pt.under)
                local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
                if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                    return (pt.intersection_point and pt.intersection_point.y) or (pt.under.y + 0.5)
                end
            end
        end
    end

    -- Discrete node scan fallback (checks down to 4 nodes below start_y)
    local check_x = math.floor(probe_x + 0.5)
    local check_z = math.floor(probe_z + 0.5)
    for dy = 1, -4, -1 do
        local ny = math.floor(start_y + dy + 0.5)
        local npos = vector.new(check_x, ny, check_z)
        local node = core.get_node_or_nil(npos)
        local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
        if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
            return ny + 0.5
        end
    end
    return nil
end

--- Detect terrain slope incline along the corpse spine axis using two downward raycasts (head and pelvis)
--- Returns the pitch angle in radians (matching right-handed Z-X-Y set_rotation) and adjusted contact elevation
---@param pos Vector Center position of the corpse
---@param yaw number Orientation yaw in radians
---@return number pitch Pitch angle in radians (clamped to [-55°, +55°])
---@return number target_y Adjusted ground midpoint elevation for the corpse
---@return boolean ground_found True if valid walkable ground was probed under corpse
function deathstats.detect_corpse_slope_pitch(pos, yaw)
    if not pos then return 0, 0, false end
    yaw = yaw or 0

    -- Floating in liquid: corpses remain level
    if deathstats.is_in_liquid(pos) then
        return 0, pos.y, false
    end

    -- In character.b3d lay animation (frames 162-166), body lies backward along spine axis:
    -- Forward is -sin(yaw), cos(yaw). Head extends backward (+sin(yaw), -cos(yaw)), pelvis extends forward.
    local fwd_x = -math.sin(yaw)
    local fwd_z = math.cos(yaw)

    local spine_half_span = 0.55
    local head_x = pos.x - fwd_x * spine_half_span
    local head_z = pos.z - fwd_z * spine_half_span
    local pelvis_x = pos.x + fwd_x * spine_half_span
    local pelvis_z = pos.z + fwd_z * spine_half_span

    local y_head = deathstats.probe_ground_elevation(head_x, head_z, pos.y)
    local y_pelvis = deathstats.probe_ground_elevation(pelvis_x, pelvis_z, pos.y)

    if y_head and y_pelvis then
        local delta_y = y_head - y_pelvis
        local dist_h = spine_half_span * 2.0 -- 1.1 node baseline

        -- In Luanti Z-X-Y set_rotation:
        -- Positive pitch around local X tilts the vector at -Z (head) downward.
        -- When delta_y > 0 (head is uphill / higher), negative pitch elevates the head.
        local raw_pitch = -atan2(delta_y, dist_h)

        -- Clamp to natural anatomical slope limits (+/- 55 degrees) to avoid vertical glitches on cliffs
        local max_pitch = math.rad(55)
        local pitch = math.max(-max_pitch, math.min(max_pitch, raw_pitch))

        -- Ground contact: anchor directly to body elevation (torso resting flat on ground)
        -- with a minimal 0.02 block epsilon to prevent coplanar polygon z-fighting
        local y_body = deathstats.probe_ground_elevation(pos.x, pos.z, pos.y)
        local contact_y = y_body or ((y_head + y_pelvis) * 0.5)
        local target_y = contact_y + 0.02
        return pitch, target_y, true
    end

    return 0, pos.y, false
end

--- Probe 3D terrain elevation surrounding the corpse to determine the true downhill slope gradient
--- Works across stairs, inclines, and irregular cliffs regardless of corpse orientation.
---@param pos Vector Center position of the corpse
---@param base_yaw number|nil Facing yaw in radians
---@param pitch_slope number|nil Pre-calculated slope pitch along the spine axis
---@return number down_x Downhill direction unit vector X (0 if flat)
---@return number down_z Downhill direction unit vector Z (0 if flat)
---@return number slope_angle Slope steepness angle in radians
function deathstats.get_terrain_downhill_dir(pos, base_yaw, pitch_slope)
    if not pos then return 0, 0, 0 end
    if deathstats.is_in_liquid(pos) then return 0, 0, 0 end

    base_yaw = base_yaw or 0
    pitch_slope = pitch_slope or 0

    -- Probe 4 surrounding cardinal points at offset D = 0.7
    local d = 0.7
    local y_east = deathstats.probe_ground_elevation(pos.x + d, pos.z, pos.y)
    local y_west = deathstats.probe_ground_elevation(pos.x - d, pos.z, pos.y)
    local y_north = deathstats.probe_ground_elevation(pos.x, pos.z + d, pos.y)
    local y_south = deathstats.probe_ground_elevation(pos.x, pos.z - d, pos.y)
    local y_center = deathstats.probe_ground_elevation(pos.x, pos.z, pos.y)

    local grad_x = 0
    if y_east and y_west then
        grad_x = (y_east - y_west) / (2 * d)
    elseif y_east and y_center then
        grad_x = (y_east - y_center) / d
    elseif y_west and y_center then
        grad_x = (y_center - y_west) / d
    end

    local grad_z = 0
    if y_north and y_south then
        grad_z = (y_north - y_south) / (2 * d)
    elseif y_north and y_center then
        grad_z = (y_north - y_center) / d
    elseif y_south and y_center then
        grad_z = (y_center - y_south) / d
    end

    -- Downhill gradient is opposite to ascent: -grad
    local down_x = -grad_x
    local down_z = -grad_z
    local slope_mag = math.sqrt(down_x * down_x + down_z * down_z)

    local slope_angle
    if slope_mag > 0.15 then
        down_x = down_x / slope_mag
        down_z = down_z / slope_mag
        slope_angle = math.atan(slope_mag)
    else
        down_x = 0
        down_z = 0
        slope_angle = 0
    end

    -- If spine pitch indicates a pronounced incline along the corpse spine,
    -- factor in or fallback to the spine slope direction.
    -- Pelvis is forward (+fwd), head is backward (-fwd).
    -- When pitch_slope < 0 (head higher than pelvis), downhill is towards pelvis (+fwd).
    -- When pitch_slope > 0 (pelvis higher than head), downhill is towards head (-fwd).
    local abs_spine = math.abs(pitch_slope)
    if abs_spine > 0.2 then
        local fwd_x = -math.sin(base_yaw)
        local fwd_z = math.cos(base_yaw)
        local spine_sign = (pitch_slope < 0) and 1 or -1
        local spine_down_x = fwd_x * spine_sign
        local spine_down_z = fwd_z * spine_sign

        if slope_mag <= 0.15 then
            down_x = spine_down_x
            down_z = spine_down_z
            slope_angle = abs_spine
        else
            slope_angle = math.max(slope_angle, abs_spine)
        end
    end

    return down_x, down_z, slope_angle
end

--- Detect if the corpse legs are hanging over an edge, cliff, or stair drop
---@param pos Vector Center position of the corpse
---@param yaw number Facing yaw of the corpse
---@return boolean hanging True if pelvis is supported but legs extend over empty space
function deathstats.detect_hanging_legs(pos, yaw)
    if not pos then return false end
    yaw = yaw or 0
    if deathstats.is_in_liquid(pos) then return false end

    local fwd_x = -math.sin(yaw)
    local fwd_z = math.cos(yaw)

    local pelvis_x = pos.x + fwd_x * 0.50
    local pelvis_z = pos.z + fwd_z * 0.50
    local feet_x = pos.x + fwd_x * 1.50
    local feet_z = pos.z + fwd_z * 1.50

    local function probe_elevation(px, pz)
        local cx = math.floor(px + 0.5)
        local cz = math.floor(pz + 0.5)
        for dy = 0, -2, -1 do
            local ny = math.floor(pos.y + dy - 0.2)
            local node = core.get_node_or_nil(vector.new(cx, ny, cz))
            local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
            if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                return ny
            end
        end
        return nil
    end

    local y_pelvis = probe_elevation(pelvis_x, pelvis_z)
    if not y_pelvis then return false end

    local y_feet = probe_elevation(feet_x, feet_z)
    return (not y_feet) or (y_pelvis - y_feet >= 1)
end

--- Return the vertical position offset required to keep different resting poses
--- (supine, prone, lateral) resting flat on top of the ground.
--- In character.b3d lay animation (frame 166), the entity origin (0,0,0) is stationed
--- along the back plane (Y min = -0.108, Y max = +0.427).
--- Rotating into prone (roll = pi) inverts Y to [-0.427, +0.108], plunging the chest/face
--- 0.32 blocks into the ground if not offset.
--- Lateral (roll = +/- pi/2) places the shoulder at -0.27, needing a +0.16 block offset.
---@param pose_type string|nil "supine", "prone", or "lateral"
---@return number offset Vertical offset in nodes
function deathstats.get_pose_elevation_offset(pose_type)
    if pose_type == "prone" then
        return 0.32
    elseif pose_type == "lateral" then
        return 0.16
    end
    return 0.0
end

--- Return the interaction selectionbox bounding box for a given resting pose
--- to match the physical mesh contact bounds in world space.
---@param pose_type string|nil "supine", "prone", or "lateral"
---@return number[] selectionbox Bounding box table { minx, miny, minz, maxx, maxy, maxz }
function deathstats.get_pose_selectionbox(pose_type)
    if pose_type == "prone" then
        return { -0.5, -0.45, -0.5, 0.5, 0.15, 0.5 }
    elseif pose_type == "lateral" then
        return { -0.5, -0.30, -0.5, 0.5, 0.30, 0.5 }
    end
    return { -0.5, -0.20, -0.5, 0.5, 0.35, 0.5 }
end

--- Settle the corpse entity to a complete rest at its final position
---@param luaent table|ObjectRef The corpse Lua entity table or ObjectRef
function deathstats.settle_corpse_at_rest(luaent)
    if not luaent then return end
    local obj = luaent.object
    if not obj and luaent.get_luaentity then
        local ent = luaent:get_luaentity()
        if ent then
            luaent = ent
            obj = ent.object or luaent
        else
            obj = luaent
        end
    elseif not obj and luaent.get_properties then
        obj = luaent
    end
    if luaent._settled then return end
    luaent._settled = true
    if not obj or (obj.is_valid and not obj:is_valid()) then return end

    if obj.set_velocity then obj:set_velocity(vector.zero()) end
    if obj.set_acceleration then obj:set_acceleration(vector.zero()) end

    local base_yaw = luaent._base_yaw or (obj.get_yaw and obj:get_yaw()) or 0
    local pitch = 0
    local roll = 0
    local pose_type = "supine"
    local pos = obj.get_pos and obj:get_pos()

    -- Determine resting orientation (supine, prone, lateral) from current tumbling roll
    if deathstats.config.ragdoll_resting_poses ~= false and luaent._rot and luaent._rot.z then
        local r = (luaent._rot.z % (2 * math.pi))
        if r > math.pi then r = r - 2 * math.pi end
        local abs_r = math.abs(r)

        if abs_r > (5 * math.pi / 8) then
            pose_type = "prone"
            roll = math.pi
        elseif abs_r >= (3 * math.pi / 8) and abs_r <= (5 * math.pi / 8) then
            pose_type = "lateral"
            roll = (r > 0) and (math.pi / 2) or (-math.pi / 2)
        else
            pose_type = "supine"
            roll = 0
        end
    end
    luaent._pose_type = pose_type

    if pos and not deathstats.is_in_liquid(pos) then
        local target_y = nil
        if deathstats.config.enable_slope_pitch ~= false then
            local detected_pitch, slope_target_y, ground_found = deathstats.detect_corpse_slope_pitch(pos, base_yaw)
            pitch = detected_pitch or 0
            if slope_target_y and (ground_found or (ground_found == nil and math.abs(slope_target_y - pos.y) > 0.001))
                and slope_target_y <= (pos.y + 0.5) and (pos.y - slope_target_y) <= 15.0 then
                target_y = slope_target_y
            end
        end

        -- If slope probe didn't resolve a ground surface or corpse is higher up in the air, find full ground surface below
        if not target_y then
            local surface_y = deathstats.find_ground_surface(pos, nil, luaent._death_info or { category = "fall" })
            if surface_y and surface_y < (pos.y - 0.001) and (pos.y - surface_y) <= 40.0 then
                target_y = surface_y + 0.02
            end
        end

        local pose_offset = deathstats.get_pose_elevation_offset(pose_type)
        if target_y then
            target_y = target_y + pose_offset
        elseif pose_offset > 0 then
            target_y = pos.y + pose_offset
        end

        if target_y and (math.abs(target_y - pos.y) > 0.001) and obj.set_pos then
            obj:set_pos(vector.new(pos.x, target_y, pos.z))
            pos = (obj.get_pos and obj:get_pos()) or vector.new(pos.x, target_y, pos.z)
            -- Re-evaluate slope pitch at exact ground position if slope pitch is enabled
            if deathstats.config.enable_slope_pitch ~= false then
                pitch = deathstats.detect_corpse_slope_pitch(pos, base_yaw) or pitch
            end
        end
    end

    if obj.set_rotation then
        obj:set_rotation({ x = pitch, y = base_yaw, z = roll })
    elseif obj.set_yaw then
        obj:set_yaw(base_yaw)
    end

    local hanging_legs = false
    if pos and deathstats.detect_hanging_legs then
        hanging_legs = deathstats.detect_hanging_legs(pos, base_yaw)
    end

    luaent._applied_bones = nil
    deathstats.settle_ragdoll_limbs(obj, luaent._impact_damage, pose_type, hanging_legs, roll)

    luaent._settled_pos = pos and vector.new(pos.x, pos.y, pos.z)

    if obj.set_properties then
        obj:set_properties({
            physical = false,
            pointable = (deathstats.config.enable_corpse_inspect ~= false),
            selectionbox = deathstats.get_pose_selectionbox(pose_type),
        })
    end

    -- Re-evaluate environment effects once corpse has settled (e.g. rolled into water/lava)
    if deathstats.config.enable_corpse_particles ~= false and pos then
        local pname = luaent._player_name
        local cdata = pname and deathstats.player_camera_data and deathstats.player_camera_data[pname]
        local dinfo = luaent._death_info or (cdata and cdata.death_info) or {}
        local settled_effect = deathstats.get_corpse_effect_type and deathstats.get_corpse_effect_type(pos, dinfo)
        local current_effect = luaent._effect_type or (cdata and cdata.current_effect_type)
        local has_active_spawners = (luaent._particle_spawners and #luaent._particle_spawners > 0)
            or (cdata and cdata.particle_spawners and #cdata.particle_spawners > 0)

        if settled_effect and (settled_effect ~= current_effect or (not has_active_spawners and settled_effect ~= "impact")) then
            if luaent._particle_spawners then
                for _, pid in ipairs(luaent._particle_spawners) do
                    core.delete_particlespawner(pid)
                end
                luaent._particle_spawners = nil
            end
            if cdata and cdata.particle_spawners then
                for _, pid in ipairs(cdata.particle_spawners) do
                    core.delete_particlespawner(pid)
                end
                cdata.particle_spawners = nil
            end
            if settled_effect ~= "impact" and deathstats.spawn_corpse_particles then
                local spawners, eff = deathstats.spawn_corpse_particles(pos, dinfo, obj)
                luaent._particle_spawners = spawners
                luaent._effect_type = eff
                if cdata then
                    cdata.particle_spawners = spawners
                    cdata.current_effect_type = eff
                end
            else
                luaent._effect_type = settled_effect
                if cdata then cdata.current_effect_type = settled_effect end
            end
        end
    end
end

local GROUND_PROBE_DYS = { -0.45, -0.85, -0.15 }
local ground_probe_scratch = { x = 0, y = 0, z = 0 }

--- Check if a corpse has solid ground or liquid support beneath it
--- Used to detect if blocks below a settled corpse have been dug out
---@param pos Vector 3D corpse position
---@return boolean has_support True if supported by walkable ground or liquid
function deathstats.has_ground_support(pos)
    if not pos then return true end

    -- Probe levels below the corpse: directly below (-0.45), further down (-0.85), and at pos (-0.15)
    ground_probe_scratch.x = pos.x
    ground_probe_scratch.z = pos.z
    for i = 1, #GROUND_PROBE_DYS do
        ground_probe_scratch.y = pos.y + GROUND_PROBE_DYS[i]
        local node = core.get_node_or_nil(ground_probe_scratch)
        if node and node.name ~= "ignore" then
            if node.name ~= "air" then
                local ndef = core.registered_nodes[node.name]
                if ndef then
                    -- Liquid provides buoyancy support
                    if ndef.liquidtype and ndef.liquidtype ~= "none" then
                        return true
                    end
                    -- Solid walkable node provides ground support
                    if ndef.walkable ~= false then
                        return true
                    end
                else
                    -- Node registered or unknown fallback
                    return true
                end
            end
        else
            -- Mapblock not loaded, assume supported to avoid unnecessary physics
            return true
        end
    end

    return false
end

local cached_fallback_ground = nil

--- Dynamically discover a representative ground node from core.registered_nodes using node groups
--- Completely mod-agnostic; avoids hardcoding any specific mod namespace like "default:"
---@return string|nil node_name Technical name of a registered walkable ground node
function deathstats.get_fallback_ground_node()
    if cached_fallback_ground and core.registered_nodes[cached_fallback_ground] then
        return cached_fallback_ground
    end
    -- Standard terrain groups across Luanti games (soil, stone, sand, crumbly, cracky)
    local candidate_groups = { "soil", "stone", "sand", "crumbly", "cracky" }
    for _, grp in ipairs(candidate_groups) do
        for name, def in pairs(core.registered_nodes) do
            if def and def.walkable and def.groups and (def.groups[grp] or 0) > 0
                and (def.drawtype == "normal" or not def.drawtype) and name ~= "air" and name ~= "ignore" then
                cached_fallback_ground = name
                return name
            end
        end
    end
    -- Any registered solid walkable node with normal drawtype
    for name, def in pairs(core.registered_nodes) do
        if def and def.walkable and (def.drawtype == "normal" or not def.drawtype) and name ~= "air" and name ~= "ignore" then
            cached_fallback_ground = name
            return name
        end
    end
    return nil
end

--- Determine whether a node surface is soft / cushioning using node groups and attributes
--- Checks fall_damage_add_percent < 0, crumbly, snappy, wool, leaves, sand, soil, snowy, hay
---@param ndef table|nil Node definition table
---@param node_name string|nil Technical node name
---@return boolean is_soft
function deathstats.is_soft_node(ndef, node_name)
    if not ndef then return false end
    if ndef.liquidtype and ndef.liquidtype ~= "none" then
        return true
    end
    local groups = ndef.groups
    if type(groups) == "table" then
        -- Engine group for fall damage reduction (beds, hay, cushions, slime)
        if groups.fall_damage_add_percent and groups.fall_damage_add_percent < 0 then
            return true
        end
        -- Standard Luanti soft material groups
        if (groups.crumbly and groups.crumbly > 0)
            or (groups.snappy and groups.snappy > 0)
            or (groups.leaves and groups.leaves > 0)
            or (groups.wool and groups.wool > 0)
            or (groups.cloth and groups.cloth > 0)
            or (groups.sand and groups.sand > 0)
            or (groups.soil and groups.soil > 0)
            or (groups.snowy and groups.snowy > 0)
            or (groups.hay and groups.hay > 0)
            or (groups.soft and groups.soft > 0) then
            return true
        end
    end
    -- Fallback name check if mod did not assign standard groups
    if node_name and type(node_name) == "string" then
        local lower = node_name:lower()
        if lower:find("sand") or lower:find("snow") or lower:find("leaves")
            or lower:find("wool") or lower:find("hay") or lower:find("dirt")
            or lower:find("mud") or lower:find("sponge") then
            return true
        end
    end
    return false
end

--- Extract an impact sound specification from a node definition table
--- Queries Luanti games and engine standard sound keys (dug, footstep, place, dig)
---@param ndef table|nil Node definition table
---@return string|nil sound_name, number base_gain, number base_pitch
function deathstats.get_node_impact_sound(ndef)
    if not ndef or type(ndef.sounds) ~= "table" then
        return nil, 1.0, 1.0
    end
    -- Standard node sound keys in Luanti games and engine:
    -- 'dug': Node struck / dug impact sound (e.g. default_hard_footstep, default_dirt_footstep with gain 1.0)
    -- 'footstep': Stepping sound on the node
    -- 'place': Node placement sound, also played by engine when falling blocks land
    -- 'dig': Node digging sound
    local sound_keys = { "dug", "footstep", "place", "dig", "step", "fall" }
    for _, key in ipairs(sound_keys) do
        local snd = ndef.sounds[key]
        if type(snd) == "string" and snd ~= "" then
            return snd, 1.0, 1.0
        elseif type(snd) == "table" and type(snd.name) == "string" and snd.name ~= "" then
            return snd.name, tonumber(snd.gain) or 1.0, tonumber(snd.pitch) or 1.0
        end
    end
    return nil, 1.0, 1.0
end

core.register_entity("deathstats:corpse", {
    initial_properties = {
        visual = "mesh",
        mesh = "character.b3d",
        textures = { "character.png" },
        visual_size = { x = 1, y = 1, z = 1 },
        collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
        stepheight = 0.6,
        selectionbox = { 0, 0, 0, 0, 0, 0 },
        pointable = false,
        physical = true,
        collide_with_objects = false,
        static_save = false,
    },
    on_activate = function(self)
        if self.object then
            if self.object.set_armor_groups then
                self.object:set_armor_groups({ immortal = 1 })
            end
            local ragdoll_enabled = (deathstats.config.enable_corpse_ragdoll ~= false)
            if self.object.set_properties then
                self.object:set_properties({
                    collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
                    stepheight = 0.6,
                    selectionbox = { 0, 0, 0, 0, 0, 0 },
                    pointable = false,
                    physical = ragdoll_enabled,
                })
            end
        end
        self._settled = false
        self._timer = 0
    end,
    on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end
        if deathstats.config.enable_corpse_inspect == false then return end
        local cname = clicker:get_player_name()
        if deathstats.dead_players and deathstats.dead_players[cname] then return end
        deathstats.show_corpse_epitaph_formspec(clicker, self)
    end,
    on_punch = function(self, _hitter, _time_from_last_punch, _tool_capabilities, dir, _damage)
        if not self.object or (self.object.is_valid and not self.object:is_valid()) then
            return true
        end
        local is_settled = self._settled or (self.physics and self.physics.settled)
        if is_settled then
            -- Defensively ensure non-physical so the engine mover cannot translate this entity
            if self.object.set_properties then
                self.object:set_properties({ physical = false })
            end
            if self.object.set_velocity then
                self.object:set_velocity(VEC_ZERO)
            end
            if self.object.set_acceleration then
                self.object:set_acceleration(VEC_ZERO)
            end

            -- Simulate slight punch impact reaction without flying away
            local pos = (self.object.get_pos and self.object:get_pos()) or self._settled_pos
            if pos then
                -- Subtle micro-displacement in horizontal punch direction (stays grounded)
                local dir_x = dir and dir.x or 0
                local dir_z = dir and dir.z or 0
                local dlen = math.sqrt(dir_x * dir_x + dir_z * dir_z)
                if dlen > 0.001 and self.object.set_pos then
                    local base_pos = self._settled_pos or pos
                    local micro_x = (dir_x / dlen) * 0.04
                    local micro_z = (dir_z / dlen) * 0.04
                    self.object:set_pos(vector.new(base_pos.x + micro_x, base_pos.y, base_pos.z + micro_z))
                end

                -- Play node impact sound & debris burst
                local under_pos = vector.new(pos.x, pos.y - 0.5, pos.z)
                local node = core.get_node_or_nil(under_pos) or core.get_node_or_nil(pos)
                local node_name = (node and node.name and node.name ~= "air" and node.name ~= "ignore") and node.name
                    or (deathstats.get_fallback_ground_node and deathstats.get_fallback_ground_node())
                if node_name then
                    local ndef = core.registered_nodes[node_name]
                    local sound_name, base_gain, base_pitch = deathstats.get_node_impact_sound(ndef)
                    if sound_name then
                        core.sound_play(sound_name, {
                            pos = pos,
                            gain = math.min(1.0, math.max(0.2, (base_gain or 1.0) * 0.5)),
                            pitch = base_pitch or 1.0,
                            max_hear_distance = 16,
                        }, true)
                    end
                    if deathstats.spawn_impact_burst then
                        deathstats.spawn_impact_burst(pos, node_name, 0.4)
                    end
                end
            end

            -- Schedule deferred check to nullify any engine-level C++ knockback and restore anchor
            core.after(0, function()
                if not self.object or (self.object.is_valid and not self.object:is_valid()) then return end
                if self.object.set_velocity then self.object:set_velocity(VEC_ZERO) end
                if self.object.set_acceleration then self.object:set_acceleration(VEC_ZERO) end
                if self.object.set_properties then self.object:set_properties({ physical = false }) end
                if self._settled_pos and self.object.set_pos then
                    self.object:set_pos(self._settled_pos)
                end
            end)
        end
        return true
    end,
    on_step = function(self, dtime, moveresult)
        if self._decay_time and core.get_gametime() >= self._decay_time then
            deathstats.dissolve_corpse(self.object)
            return
        end
        if self._settled then
            -- Guard against any rogue velocity or drift on settled corpse
            if self.object and (not self.object.is_valid or self.object:is_valid()) then
                if self.object.get_velocity then
                    local v = self.object:get_velocity()
                    if v and (v.x ~= 0 or v.y ~= 0 or v.z ~= 0) then
                        self.object:set_velocity(VEC_ZERO)
                    end
                end
                if self._settled_pos and self.object.get_pos and self.object.set_pos then
                    local cp = self.object:get_pos()
                    if cp and vector.distance(cp, self._settled_pos) > 0.05 then
                        self.object:set_pos(self._settled_pos)
                    end
                end
            end

            -- Throttled ground support check (every 0.35s) to avoid node queries every step
            self._ground_check_timer = (self._ground_check_timer or 0) + (dtime or 0)
            if self._ground_check_timer >= 0.35 then
                self._ground_check_timer = 0
                local cur_p = (self.object and self.object.get_pos and self.object:get_pos()) or self._settled_pos
                if cur_p and not deathstats.has_ground_support(cur_p) then
                    -- Wake up into ragdoll free-fall if ground beneath was dug out
                    self._settled = false
                    self._settled_pos = nil
                    self._timer = 0
                    self._air_timer = 0
                    self._slide_timer = 0
                    self._bounce_count = 0
                    if self.object.set_properties then
                        self.object:set_properties({
                            physical = true,
                            pointable = false,
                        })
                    end
                    if self.object.set_acceleration then
                        self.object:set_acceleration(GRAV_ACCEL)
                    end
                    if self.object.set_velocity then
                        self.object:set_velocity(FALL_VEL)
                    end
                    return
                end
            end
            return
        end
        if not dtime or dtime <= 0 then return end
        if not self.object or (self.object.is_valid and not self.object:is_valid()) then return end

        self._timer = (self._timer or 0) + dtime

        local pos = self.object.get_pos and self.object:get_pos()
        if not pos or (pos.y and (pos.y < -31000 or pos.y > 31000)) then
            deathstats.settle_corpse_at_rest(self)
            return
        end

        -- Chunk safety: use get_node_or_nil to prevent force-loading new mapblocks
        local node = core.get_node_or_nil(pos)
        if not node or node.name == "ignore" then
            deathstats.settle_corpse_at_rest(self)
            return
        end

        local cur_v = (self.object.get_velocity and self.object:get_velocity()) or vector.zero()
        local vx, vy, vz = cur_v.x or 0, cur_v.y or 0, cur_v.z or 0
        -- Sanity check: prevent NaN physics corruption
        if vx ~= vx or vy ~= vy or vz ~= vz then
            deathstats.settle_corpse_at_rest(self)
            return
        end

        local ndef = core.registered_nodes[node.name]
        local is_liquid = (ndef and ndef.liquidtype and ndef.liquidtype ~= "none")
            or deathstats.is_in_liquid(pos)
        local is_lava = is_liquid and ((node.name:find("lava") ~= nil) or (ndef and ndef.groups and ndef.groups.lava))

        if is_liquid then
            if is_lava then
                -- Dense viscous lava drag
                local drag = math.exp(-6.0 * dtime)
                if self.object.set_acceleration then
                    self.object:set_acceleration({ x = 0, y = -1.5, z = 0 })
                end
                if self.object.set_velocity then
                    self.object:set_velocity(vector.new(cur_v.x * drag, cur_v.y * drag, cur_v.z * drag))
                end
            else
                -- Water / liquid buoyancy
                local drag = math.exp(-3.5 * dtime)
                local node_above = core.get_node_or_nil(vector.new(pos.x, pos.y + 0.6, pos.z))
                local ndef_above = node_above and node_above.name ~= "ignore" and core.registered_nodes[node_above.name]
                local above_is_air = not ndef_above or ndef_above.liquidtype == "none"

                local target_acc_y = above_is_air and -1.0 or 2.5
                if self.object.set_acceleration then
                    self.object:set_acceleration({ x = 0, y = target_acc_y, z = 0 })
                end
                local target_vy = cur_v.y * drag
                if above_is_air and cur_v.y > 0.4 then
                    target_vy = 0.1
                end
                if self.object.set_velocity then
                    self.object:set_velocity(vector.new(cur_v.x * drag, target_vy, cur_v.z * drag))
                end
            end

            local speed_liq = math.sqrt(cur_v.x * cur_v.x + cur_v.z * cur_v.z)
            if speed_liq < 0.2 and math.abs(cur_v.y) < 0.3 and self._timer > 0.6 then
                deathstats.settle_corpse_at_rest(self)
                return
            end
        else
            -- Airborne or ground contact
            local touching_ground = false
            local had_vertical_collision = false
            local had_wall_collision = false
            local collision_old_vy = nil
            local ground_node_name = nil

            local wall_collision_axis = nil
            if moveresult and type(moveresult) == "table" then
                touching_ground = moveresult.touching_ground or false
                if moveresult.collisions and type(moveresult.collisions) == "table" then
                    for _, col in ipairs(moveresult.collisions) do
                        if col.axis == "y" and col.old_velocity and col.old_velocity.y < -1.8 then
                            had_vertical_collision = true
                            collision_old_vy = col.old_velocity.y
                            if col.node_pos then
                                local n = core.get_node_or_nil(col.node_pos)
                                if n and n.name ~= "air" and n.name ~= "ignore" then
                                    ground_node_name = n.name
                                end
                            end
                        elseif (col.axis == "x" or col.axis == "z") and col.old_velocity then
                            local h_old = math.sqrt((col.old_velocity.x or 0)^2 + (col.old_velocity.z or 0)^2)
                            if h_old > 0.8 then
                                had_wall_collision = true
                                wall_collision_axis = col.axis
                            end
                        end
                    end
                end
            end

            -- Discrete node scan check for solid ground beneath corpse
            local node_below1 = core.get_node_or_nil(vector.new(pos.x, pos.y - 0.25, pos.z))
            local def1 = node_below1 and node_below1.name ~= "ignore" and core.registered_nodes[node_below1.name]
            local has_ground = (def1 and def1.walkable and node_below1.name ~= "air")
            local ground_node_y = has_ground and math.floor(pos.y - 0.25 + 0.5) or nil
            if not has_ground then
                local node_below2 = core.get_node_or_nil(vector.new(pos.x, pos.y - 0.65, pos.z))
                local def2 = node_below2 and node_below2.name ~= "ignore" and core.registered_nodes[node_below2.name]
                has_ground = (def2 and def2.walkable and node_below2.name ~= "air")
                if has_ground and node_below2 then
                    ground_node_name = ground_node_name or node_below2.name
                    ground_node_y = math.floor(pos.y - 0.65 + 0.5)
                else
                    local node_below3 = core.get_node_or_nil(vector.new(pos.x, pos.y - 1.15, pos.z))
                    local def3 = node_below3 and node_below3.name ~= "ignore" and core.registered_nodes[node_below3.name]
                    if def3 and def3.walkable and node_below3.name ~= "air" then
                        ground_node_name = ground_node_name or node_below3.name
                        ground_node_y = math.floor(pos.y - 1.15 + 0.5)
                    end
                end
            elseif node_below1 then
                ground_node_name = ground_node_name or node_below1.name
            end
            local ground_top = ground_node_y and (ground_node_y + 0.5)
            local ground_clearance = ground_top and (pos.y - ground_top)

            if not moveresult then
                touching_ground = has_ground and cur_v.y <= 0.35 and (math.abs(cur_v.y) < 0.35 or self._timer > 0.15)
                if has_ground and self._last_vy and self._last_vy < -2.2 and cur_v.y <= 0.35 then
                    had_vertical_collision = true
                    collision_old_vy = self._last_vy
                end
            else
                -- If moveresult is present, also confirm ground if solid node is directly beneath and vertical speed is small
                if has_ground and math.abs(cur_v.y) < 0.35 then
                    touching_ground = true
                end
            end

            -- If ground collision occurred but node wasn't in collision list, check downward
            if not ground_node_name and (had_vertical_collision or touching_ground) then
                for _, dy in ipairs({ 0.25, 0.65, 1.15, 1.65, 2.15 }) do
                    local n = core.get_node_or_nil(vector.new(pos.x, pos.y - dy, pos.z))
                    if n and n.name ~= "air" and n.name ~= "ignore" then
                        local d = core.registered_nodes[n.name]
                        if d and d.walkable then
                            ground_node_name = n.name
                            break
                        end
                    end
                end
                ground_node_name = ground_node_name or deathstats.get_fallback_ground_node()
            end

            -- Inelastic ground bounce handling (max 2 bounces before ground slide)
            local max_bounces = 2
            self._bounce_count = self._bounce_count or 0
            if had_vertical_collision and self._bounce_count < max_bounces then
                local old_impact_vy = math.abs(collision_old_vy or cur_v.y)
                local restitution = tonumber(deathstats.config.ragdoll_restitution) or 0.25
                local ndef_ground = ground_node_name and core.registered_nodes[ground_node_name]
                local is_soft = deathstats.is_soft_node(ndef_ground, ground_node_name)
                if is_soft then
                    restitution = restitution * 0.4
                end

                local rebound_vy = old_impact_vy * restitution
                if rebound_vy >= 0.8 then
                    self._bounce_count = self._bounce_count + 1
                    local rebound_vx = cur_v.x * 0.65
                    local rebound_vz = cur_v.z * 0.65
                    if self.object.set_velocity then
                        self.object:set_velocity(vector.new(rebound_vx, rebound_vy, rebound_vz))
                    end
                    if self.object.set_acceleration then
                        self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                    end

                    -- Impact transfers linear momentum into rotational tumbling torque
                    if self._rot_speed and deathstats.config.ragdoll_tumbling ~= false then
                        local torque = math.sqrt(rebound_vx * rebound_vx + rebound_vz * rebound_vz) * 0.9
                        self._rot_speed.x = self._rot_speed.x + torque
                        self._rot_speed.z = self._rot_speed.z + (math.random() - 0.5) * torque
                    end

                    if deathstats.config.enable_corpse_impact_sounds ~= false and deathstats.config.enable_sounds ~= false then
                        local sound_name, base_gain, base_pitch = deathstats.get_node_impact_sound(ndef_ground)
                        if sound_name then
                            local impact_mult = math.min(1.0, math.max(0.25, old_impact_vy / 8.0))
                            core.sound_play(sound_name, {
                                pos = pos,
                                gain = math.min(1.0, base_gain * impact_mult * 1.5),
                                pitch = base_pitch,
                                max_hear_distance = 20,
                            }, true)
                        end
                    end
                    if deathstats.config.enable_corpse_particles ~= false and not self._impact_particles_done then
                        deathstats.spawn_impact_burst(pos, ground_node_name, old_impact_vy)
                        if self._bounce_count >= max_bounces then
                            self._impact_particles_done = true
                        end
                    end

                    -- Apply immediate physical impact reaction to corpse limbs on bounce
                    local rebound_v = vector.new(rebound_vx, rebound_vy, rebound_vz)
                    deathstats.apply_corpse_bounce_impact(self.object, old_impact_vy, rebound_v, self._rot, self._bounce_count)

                    -- Record shock state for decaying rebound flight oscillation
                    self._bounce_shock = math.min(1.6, math.max(0.35, old_impact_vy / 5.5))
                    self._bounce_shock_timer = 0.45
                    self._flail_timer = 1.0 -- immediately allow next flight limb update

                    self._last_vy = rebound_vy
                    return
                end
            end

            if had_wall_collision then
                local defl_vx = cur_v.x * -0.2
                local defl_vz = cur_v.z * -0.2
                if self.object.set_velocity then
                    self.object:set_velocity(vector.new(defl_vx, cur_v.y, defl_vz))
                end
                -- Inelastic angular braking: vertical surface absorbs spinning momentum
                if self._rot_speed then
                    self._rot_speed.x = (self._rot_speed.x or 0) * 0.15
                    self._rot_speed.z = (self._rot_speed.z or 0) * 0.15
                end
                -- Gently deflect yaw parallel to wall so head/feet do not penetrate wall blocks
                if wall_collision_axis and self._base_yaw then
                    if wall_collision_axis == "x" then
                        local cy = math.cos(self._base_yaw)
                        self._base_yaw = (cy >= 0) and 0 or math.pi
                    elseif wall_collision_axis == "z" then
                        local sy = math.sin(self._base_yaw)
                        self._base_yaw = (sy >= 0) and (math.pi * 0.5) or (math.pi * 1.5)
                    end
                    self._rot = self._rot or { x = 0, y = self._base_yaw, z = 0 }
                    self._rot.y = self._base_yaw
                    if self.object.set_rotation then
                        self.object:set_rotation(self._rot)
                    end
                end
            end

            if touching_ground then
                self._air_timer = 0
                self._slide_timer = (self._slide_timer or 0) + dtime

                local pitch_slope = 0
                if deathstats.config.enable_slope_pitch ~= false then
                    pitch_slope = deathstats.detect_corpse_slope_pitch(pos, self._base_yaw or 0) or 0
                end

                local down_x, down_z, slope_angle = deathstats.get_terrain_downhill_dir(pos, self._base_yaw or 0, pitch_slope)
                local eff_slope = math.max(slope_angle, math.abs(pitch_slope))

                -- Active uphill suppression: on any slope or stairs, brake velocity moving against downhill direction
                if eff_slope > 0.25 and (down_x ~= 0 or down_z ~= 0) then
                    local v_down = cur_v.x * down_x + cur_v.z * down_z
                    if v_down < 0 then
                        local brake = math.exp(-8.0 * dtime)
                        cur_v.x = cur_v.x * brake
                        cur_v.z = cur_v.z * brake
                    end
                end

                local accel_mag = 9.81 * math.sin(eff_slope) - 4.5 * math.cos(eff_slope)
                -- Steep slope (> 28 degrees = ~0.48 rad): gravity overcomes friction and corpse rolls downhill
                if eff_slope > 0.48 and self._slide_timer < 4.0 and (down_x ~= 0 or down_z ~= 0) and accel_mag > 0 then
                    local new_vx = cur_v.x + down_x * accel_mag * dtime
                    local new_vz = cur_v.z + down_z * accel_mag * dtime
                    local new_vy = math.min(-1.5, cur_v.y)
                    if self.object.set_velocity then
                        self.object:set_velocity(vector.new(new_vx, new_vy, new_vz))
                    end
                    if self.object.set_acceleration then
                        self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                    end
                    if self._rot and deathstats.config.ragdoll_tumbling ~= false then
                        -- Keep pitch aligned with slope incline so torso lays flush with slope face
                        self._rot.x = pitch_slope
                        -- Roll like a barrel/log along longitudinal spine axis (Roll Z) to avoid dipping head/feet into ground
                        self._rot.z = (self._rot.z or 0) + accel_mag * 1.0 * dtime
                        if self.object.set_rotation then
                            self.object:set_rotation(self._rot)
                        end
                    end
                else
                    -- Kinetic surface friction on ground
                    local friction = math.exp(-4.5 * dtime)
                    local new_vx = cur_v.x * friction
                    local new_vz = cur_v.z * friction
                    if self.object.set_velocity then
                        self.object:set_velocity(vector.new(new_vx, cur_v.y, new_vz))
                    end
                    -- Keep downward gravity active so corpse rests firmly on ground and drops over edges
                    if self.object.set_acceleration then
                        self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                    end

                    -- Align pitch flush towards ground slope to avoid digging into terrain
                    if self._rot then
                        self._rot.x = pitch_slope or 0
                        -- Ground friction dampens roll angular velocity, preserving resting roll angle
                        if self._rot_speed and self._rot_speed.z and math.abs(self._rot_speed.z) > 0.01 then
                            self._rot.z = (self._rot.z or 0) + self._rot_speed.z * dtime
                            self._rot_speed.z = self._rot_speed.z * math.exp(-4.5 * dtime)
                        end
                        if self.object.set_rotation then
                            self.object:set_rotation(self._rot)
                        end
                    end

                    local ground_speed = math.sqrt(new_vx * new_vx + new_vz * new_vz)

                    -- Decay bounce shock timer while on ground
                    if self._bounce_shock_timer and self._bounce_shock_timer > 0 then
                        self._bounce_shock_timer = self._bounce_shock_timer - dtime
                        self._bounce_shock = (self._bounce_shock or 0) * math.exp(-4.5 * dtime)
                        if self._bounce_shock_timer <= 0 then
                            self._bounce_shock = 0
                        end
                    end

                    -- Dynamic limb movement while sliding on ground or tumbling down stairs/hills
                    if ground_speed > 0.2 or (self._bounce_shock and self._bounce_shock > 0.05) then
                        self._flail_timer = (self._flail_timer or 0) + dtime
                        local flail_hz = deathstats.config.ragdoll_flail_rate or 10.0
                        local flail_interval = 1.0 / flail_hz
                        if ground_speed < 1.5 then
                            flail_interval = flail_interval * 1.5
                        end
                        if self._flail_timer >= flail_interval then
                            self._flail_timer = 0
                            deathstats.update_ragdoll_slide_limbs(self.object, vector.new(new_vx, cur_v.y, new_vz), self._base_yaw or 0, self._bounce_shock, self._slide_timer)
                        end
                    end

                    if ground_speed < 0.15 or self._slide_timer > 4.5 then
                        deathstats.settle_corpse_at_rest(self)
                        return
                    end
                end
            else
                -- In air: gravity acceleration and aerodynamic drag
                self._slide_timer = 0
                self._air_timer = (self._air_timer or 0) + dtime

                if self.object.set_acceleration then
                    self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                end
                local air_drag = math.exp(-0.25 * dtime)
                if self.object.set_velocity then
                    self.object:set_velocity(vector.new(cur_v.x * air_drag, cur_v.y, cur_v.z * air_drag))
                end

                -- Tumbling rotation with aerodynamic angular damping
                if self._tumbling and (deathstats.config.ragdoll_tumbling ~= false) then
                    self._rot = self._rot or { x = 0, y = self._base_yaw or 0, z = 0 }
                    self._rot_speed = self._rot_speed or { x = 0, y = 0, z = 0 }
                    local ang_drag = math.exp(-0.6 * dtime)
                    self._rot_speed.x = self._rot_speed.x * ang_drag
                    self._rot_speed.z = self._rot_speed.z * ang_drag
                    self._rot.x = self._rot.x + self._rot_speed.x * dtime
                    self._rot.z = self._rot.z + self._rot_speed.z * dtime

                    -- Ground proximity envelope: clamp pitch to prevent head/feet dipping below floor
                    if ground_clearance and ground_clearance < 0.85 then
                        local ratio = math.max(0, math.min(1.0, ground_clearance / 0.85))
                        local max_pitch = math.asin(ratio)
                        if math.abs(self._rot.x) > max_pitch then
                            self._rot.x = math.max(-max_pitch, math.min(max_pitch, self._rot.x))
                            if self._rot_speed then self._rot_speed.x = 0 end
                        end
                    end

                    if self.object.set_rotation then
                        self.object:set_rotation(self._rot)
                    end
                end

                -- Dynamic limb flail during high velocity flight or rebound shock (throttled to ragdoll_flail_rate Hz)
                local speed_3d = math.sqrt(cur_v.x * cur_v.x + cur_v.y * cur_v.y + cur_v.z * cur_v.z)
                local flail_hz = deathstats.config.ragdoll_flail_rate or 10.0
                local flail_interval = 1.0 / flail_hz
                if speed_3d < 2.0 then
                    flail_interval = flail_interval * 2.0
                end

                -- Decay bounce shock timer
                if self._bounce_shock_timer and self._bounce_shock_timer > 0 then
                    self._bounce_shock_timer = self._bounce_shock_timer - dtime
                    self._bounce_shock = (self._bounce_shock or 0) * math.exp(-4.5 * dtime)
                    if self._bounce_shock_timer <= 0 then
                        self._bounce_shock = 0
                    end
                end

                if speed_3d > 1.0 or (self._bounce_shock and self._bounce_shock > 0.05) then
                    self._flail_timer = (self._flail_timer or 0) + dtime
                    if self._flail_timer >= flail_interval then
                        self._flail_timer = 0
                        deathstats.update_ragdoll_flight_limbs(self.object, cur_v, self._base_yaw or 0, self._bounce_shock)
                    end
                end

                -- Airborne failsafe: if falling for over 10 seconds (e.g. huge drop or snagged geometry)
                if self._air_timer > 10.0 then
                    local ground_y = deathstats.find_ground_surface(pos, nil, self._death_info or { category = "fall" })
                    if ground_y and (pos.y - ground_y) <= 40.0 then
                        if self.object.set_pos then
                            self.object:set_pos(vector.new(pos.x, ground_y + 0.02, pos.z))
                        end
                        deathstats.settle_corpse_at_rest(self)
                        return
                    end
                end
            end
        end

        self._last_vy = cur_v.y
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
    if not corpse then return end

    local anim_def = nil
    local papi = rawget(_G, "player_api")
    if papi and papi.registered_models and mesh_name and papi.registered_models[mesh_name] then
        local model_def = papi.registered_models[mesh_name]
        if model_def.animations then
            anim_def = model_def.animations.lay or model_def.animations.die
        end
    end

    local def_mod = rawget(_G, "default")
    if not anim_def and def_mod and def_mod.registered_player_models and mesh_name and def_mod.registered_player_models[mesh_name] then
        local model_def = def_mod.registered_player_models[mesh_name]
        if model_def.animations then
            anim_def = model_def.animations.lay or model_def.animations.die
        end
    end

    local mcl_p = rawget(_G, "mcl_player")
    if not anim_def and mcl_p and mcl_p.registered_players then
        anim_def = { x = 162, y = 166 }
    end

    if not anim_def then
        anim_def = { x = 162, y = 166 }
    end

    -- Multi-track glTF support (track name string or { track = "lay", ... })
    local track_name = (type(anim_def) == "string" and anim_def) or (type(anim_def) == "table" and anim_def.track)
    if track_name then
        if corpse.play_animation then
            corpse:play_animation(track_name, { speed = 1, loop = false, priority = 0 })
        end
        if corpse.set_animation then
            corpse:set_animation({ x = 0, y = 0 }, 1, 0, false)
        end
        return
    end

    -- Freeze pose on the final frame of the lay animation so corpse lies completely flat
    -- Note: frame_speed must be non-zero (1) for the Luanti engine to seek to the frame; loop must be false
    local target_frame = (type(anim_def) == "table" and (anim_def.y or anim_def[2])) or 166
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

    -- Multiplayer network bandwidth optimization: skip bone packet if angular change is below threshold
    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    if luaent then
        luaent._applied_bones = luaent._applied_bones or {}
        local last = luaent._applied_bones[bone_name]
        local rx = rot_vec.x or 0
        local ry = rot_vec.y or 0
        local rz = rot_vec.z or 0
        if last then
            local dx = math.abs(rx - last.x)
            local dy = math.abs(ry - last.y)
            local dz = math.abs(rz - last.z)
            if dx < 0.05 and dy < 0.05 and dz < 0.05 then
                return true
            end
        end
        luaent._applied_bones[bone_name] = { x = rx, y = ry, z = rz }
    end

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
            if type(v) == "table" then
                angles[k] = v
            else
                angles[k] = tonumber(v) or 0
            end
        end
    else
        -- Anatomical broken bone angle ranges (local Z rotation):
        -- Left Arm: 50% chance splayed outwards (-80 to -35 deg), 30% folded inward across torso (+20 to +55 deg)
        local left_arm_deg = (math.random() < 0.5) and random_float(-80, -35) or random_float(20, 55)
        -- Right Arm: 50% chance splayed outwards (+35 to +80 deg), 30% folded inward across torso (-55 to -20 deg)
        local right_arm_deg = (math.random() < 0.5) and random_float(35, 80) or random_float(-55, -20)
        -- Legs: Anatomically, corpses naturally splay outward (Left Leg -70 to -15 deg, Right Leg +15 to +70 deg).
        -- Crossed legs (adducted across body midline: Left Leg > 0 or Right Leg < 0) occur at a reduced, natural probability (~4%).
        -- If one leg crosses inward, the other leg remains splayed outward to prevent unnatural double-crossed knots.
        local cross_prob = 0.04
        local left_leg_deg, right_leg_deg
        if math.random() < cross_prob then
            if math.random() < 0.5 then
                -- Left leg crosses inward across midline (+10 to +30 deg); Right leg stays outward (+15 to +70 deg)
                left_leg_deg = random_float(10, 30)
                right_leg_deg = random_float(15, 70)
            else
                -- Right leg crosses inward across midline (-30 to -10 deg); Left leg stays outward (-70 to -15 deg)
                left_leg_deg = random_float(-70, -15)
                right_leg_deg = random_float(-30, -10)
            end
        else
            -- Both legs naturally splay outward (abducted away from each other)
            left_leg_deg = random_float(-70, -15)
            right_leg_deg = random_float(15, 70)
        end
        -- Head: limp neck turned sideways on the floor (-45 to +45 deg)
        local head_deg = random_float(-45, 45)

        angles["Arm_Left"] = math.rad(left_arm_deg)
        angles["Arm_Right"] = math.rad(right_arm_deg)
        angles["Leg_Left"] = math.rad(left_leg_deg)
        angles["Leg_Right"] = math.rad(right_leg_deg)
        angles["Head"] = math.rad(head_deg)
    end

    local applied = {}
    for bone_name, val in pairs(angles) do
        local applied_ok
        if type(val) == "table" then
            applied_ok = deathstats.rotate_corpse_bone(corpse, bone_name, val)
        else
            applied_ok = deathstats.rotate_corpse_bone_planar(corpse, bone_name, val)
        end
        if applied_ok then
            applied[bone_name] = val
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
    -- Also remove any attached child entities (arrows, custom objects) to prevent orphans
    if corpse.get_children then
        for _, child in ipairs(corpse:get_children()) do
            if child and (not child.is_valid or child:is_valid()) and child.remove then
                child:remove()
            end
        end
    end
    local went = deathstats.get_corpse_wielditem(corpse)
    if went and (not went.is_valid or went:is_valid()) and went.remove then
        went:remove()
    end
    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    if luaent then
        if luaent._particle_spawners then
            for _, pid in ipairs(luaent._particle_spawners) do
                core.delete_particlespawner(pid)
            end
            luaent._particle_spawners = nil
        end
        luaent._wielditem_entity = nil
    end
    if deathstats.player_corpses then
        for pname, c_obj in pairs(deathstats.player_corpses) do
            if c_obj == corpse then
                deathstats.player_corpses[pname] = nil
            end
        end
    end
    if (not corpse.is_valid or corpse:is_valid()) and corpse.remove then
        corpse:remove()
    end
end

--- Spawn gentle ash / smoke dissipation particles when a corpse decays
---@param pos Vector Center position of the decaying corpse
---@return integer|nil spawner_id Particle spawner identifier or nil if disabled
function deathstats.spawn_decay_particles(pos)
    if not pos or deathstats.config.enable_corpse_particles == false then return nil end
    local min_p = vector.new(pos.x - 0.4, pos.y - 0.1, pos.z - 0.4)
    local max_p = vector.new(pos.x + 0.4, pos.y + 0.3, pos.z + 0.4)
    local min_v = vector.new(-0.3, 0.4, -0.3)
    local max_v = vector.new(0.3, 1.1, 0.3)
    local min_a = vector.new(0, 0.05, 0)
    local max_a = vector.new(0, 0.15, 0)

    local anim_def = {
        type = "vertical_frames",
        aspect_w = 5,
        aspect_h = 5,
        length = 0.8,
    }

    return core.add_particlespawner({
        amount = 18,
        time = 0.2,
        collisiondetection = false,
        collision_removal = false,
        -- Legacy client fields (< v5.6)
        minpos = min_p,
        maxpos = max_p,
        minvel = min_v,
        maxvel = max_v,
        minacc = min_a,
        maxacc = max_a,
        minexptime = 0.8,
        maxexptime = 1.5,
        minsize = 1.0,
        maxsize = 2.2,
        texture = "deathstats_particle_smoke.png",
        animation = anim_def,
        -- Modern Luanti fields (v5.6+)
        pos = {
            min = min_p,
            max = max_p,
        },
        vel = {
            min = min_v,
            max = max_v,
        },
        acc = {
            min = min_a,
            max = max_a,
        },
        exptime = { min = 0.8, max = 1.5 },
        size = { min = 1.0, max = 2.2 },
        texpool = {
            {
                name = "deathstats_particle_smoke.png",
                alpha_tween = { 0.8, 0.0 },
                scale_tween = { { x = 0.8, y = 0.8 }, { x = 1.6, y = 1.6 } },
                blend = "alpha",
                animation = anim_def,
            },
        },
    })
end

--- Dissolve and cleanly remove a persistent corpse with dissipation particles
---@param corpse ObjectRef|nil The corpse object reference
function deathstats.dissolve_corpse(corpse)
    if not corpse then return end
    local pos = corpse.get_pos and corpse:get_pos()
    if pos then
        deathstats.spawn_decay_particles(pos)
    end
    deathstats.remove_corpse(corpse)
end

--- Unhide and restore native visual scale for any arrows attached to a corpse
--- Defensively resets is_visible = true and restores visual_size if previously zeroed
---@param corpse ObjectRef|nil The corpse entity object
function deathstats.unhide_corpse_arrows(corpse)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    if not corpse.get_children then return end
    for _, child in ipairs(corpse:get_children()) do
        if child and (not child.is_valid or child:is_valid()) then
            local cent = child.get_luaentity and child:get_luaentity()
            if cent and (cent._is_arrow or (cent.name and cent.name:find("^x_bows:"))) then
                if child.set_properties then
                    local restore_props = { is_visible = true }
                    if child.get_properties then
                        local cp = child:get_properties()
                        if cp and cp.visual_size and cp.visual_size.x == 0 and cp.visual_size.y == 0 then
                            local init_vs = cent.initial_properties and cent.initial_properties.visual_size
                            restore_props.visual_size = init_vs or { x = 1, y = 1, z = 1 }
                        end
                    end
                    child:set_properties(restore_props)
                end
            end
        end
    end
end

--- Spawn and configure the corpse placeholder entity at the given position
---@param corpse_pos table The {x, y, z} coordinates where corpse should be placed
---@param visuals table The player visual appearance table (mesh, textures, visual_size, yaw)
---@param player ObjectRef|nil Optional player reference for transferring attached arrows
---@param death_info table|nil Optional death analysis table
---@param last_blow table|nil Optional lethal blow data
---@return ObjectRef|nil corpse The spawned corpse entity or nil if failed (e.g. mapblock not loaded)
function deathstats.spawn_and_setup_corpse(corpse_pos, visuals, player, death_info, last_blow)
    if not corpse_pos or not visuals then return nil end
    local corpse = core.add_entity(corpse_pos, "deathstats:corpse")
    if corpse then
        local ragdoll_enabled = (deathstats.config.enable_corpse_ragdoll ~= false)
        corpse:set_properties({
            mesh = visuals.mesh,
            textures = visuals.textures,
            visual_size = visuals.visual_size,
            selectionbox = { 0, 0, 0, 0, 0, 0 },
            pointable = false,
            physical = ragdoll_enabled,
            collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
            stepheight = 0.6,
        })
        if corpse.set_rotation then
            corpse:set_rotation({ x = 0, y = visuals.yaw or 0, z = 0 })
        elseif corpse.set_yaw then
            corpse:set_yaw(visuals.yaw or 0)
        end
        deathstats.pose_corpse(corpse, visuals.mesh)

        local luaent = corpse.get_luaentity and corpse:get_luaentity()
        if luaent then
            luaent._base_yaw = visuals.yaw or 0
            local pname = player and player.get_player_name and player:get_player_name()
            luaent._player_name = pname
            if pname and deathstats.player_corpses and deathstats.player_corpses[pname] then
                if deathstats.player_corpses[pname] ~= corpse then
                    deathstats.dissolve_corpse(deathstats.player_corpses[pname])
                end
                deathstats.player_corpses[pname] = nil
            end
            luaent._death_info = death_info
            local pdata = player and deathstats.get_player_data(player)
            luaent._last_life = pdata and pdata.last_life
        end
        local is_moving = false

        if ragdoll_enabled then
            local vel, rot_speed = deathstats.calculate_corpse_impulse(player, death_info, last_blow)
            if vel and (vel.x ~= 0 or vel.y ~= 0 or vel.z ~= 0) then
                is_moving = true
                if corpse.set_velocity then corpse:set_velocity(vel) end
                if corpse.set_acceleration then corpse:set_acceleration({ x = 0, y = -9.81, z = 0 }) end
                local initial_roll = 0
                if deathstats.config.ragdoll_resting_poses ~= false then
                    local yaw = visuals.yaw or 0
                    local fwd_x = -math.sin(yaw)
                    local fwd_z = math.cos(yaw)
                    local vel_len = math.sqrt(vel.x * vel.x + vel.z * vel.z)
                    if vel_len > 0.1 then
                        local dot_fwd = (vel.x * fwd_x + vel.z * fwd_z) / vel_len
                        if dot_fwd > 0.35 then
                            -- Knocked forward (struck from behind): topple forward onto chest/face
                            initial_roll = math.pi
                        elseif dot_fwd < -0.35 then
                            -- Knocked backward (struck from front): fall backward onto back
                            initial_roll = 0
                        else
                            -- Knocked sideways: topple onto side
                            initial_roll = (math.random() < 0.5) and (math.pi / 2) or (-math.pi / 2)
                        end
                    end
                end

                if luaent then
                    luaent._velocity = vel
                    luaent._rot_speed = rot_speed
                    luaent._rot = { x = 0, y = visuals.yaw or 0, z = initial_roll }
                    luaent._base_yaw = visuals.yaw or 0
                    luaent._tumbling = (deathstats.config.ragdoll_tumbling ~= false) and (rot_speed.x ~= 0 or rot_speed.z ~= 0)
                    luaent._impact_damage = (last_blow and last_blow.damage) or 5
                    luaent._death_info = death_info
                    luaent._settled = false
                    luaent._timer = 0
                    luaent._air_timer = 0
                    luaent._slide_timer = 0
                end
                deathstats.update_ragdoll_flight_limbs(corpse, vel, visuals.yaw or 0)
            end
        end

        local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
            and (deathstats.config.enable_fall_fractures ~= false)

        if not is_moving then
            local roll = 0
            local pose_type = "supine"
            if deathstats.config.ragdoll_resting_poses ~= false then
                local pick = math.random()
                if pick < 0.30 then
                    pose_type = "prone"
                    roll = math.pi
                elseif pick < 0.60 then
                    pose_type = "lateral"
                    roll = (math.random() < 0.5) and (math.pi / 2) or (-math.pi / 2)
                else
                    pose_type = "supine"
                    roll = 0
                end
            end

            local pitch = 0
            local in_liquid = deathstats.is_in_liquid(corpse_pos, death_info)
            if not in_liquid then
                local pose_offset = deathstats.get_pose_elevation_offset(pose_type)
                if deathstats.config.enable_slope_pitch ~= false then
                    local detected_pitch, target_y, ground_found = deathstats.detect_corpse_slope_pitch(corpse_pos, visuals.yaw or 0)
                    pitch = detected_pitch or 0
                    if (ground_found or ground_found == nil) and target_y and math.abs(target_y - corpse_pos.y) <= 1.2 then
                        target_y = target_y + pose_offset
                        if corpse.set_pos then
                            corpse:set_pos(vector.new(corpse_pos.x, target_y, corpse_pos.z))
                        end
                    elseif pose_offset > 0 and corpse.set_pos then
                        corpse:set_pos(vector.new(corpse_pos.x, corpse_pos.y + pose_offset, corpse_pos.z))
                    end
                elseif pose_offset > 0 and corpse.set_pos then
                    corpse:set_pos(vector.new(corpse_pos.x, corpse_pos.y + pose_offset, corpse_pos.z))
                end
            end
            if corpse.set_rotation then
                corpse:set_rotation({ x = pitch, y = visuals.yaw or 0, z = roll })
            end
            if luaent then
                luaent._settled = true
                luaent._rot = { x = pitch, y = visuals.yaw or 0, z = roll }
                luaent._pose_type = pose_type
                local cur_p = (corpse.get_pos and corpse:get_pos()) or corpse_pos
                luaent._settled_pos = cur_p and vector.new(cur_p.x, cur_p.y, cur_p.z)
            end
            if corpse.set_properties then
                corpse:set_properties({
                    physical = false,
                    pointable = (deathstats.config.enable_corpse_inspect ~= false),
                    selectionbox = deathstats.get_pose_selectionbox(pose_type),
                    collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
                    stepheight = 0.6,
                })
            end
            deathstats.settle_ragdoll_limbs(corpse, (last_blow and last_blow.damage) or 5, pose_type, nil, roll)
        elseif fractures_enabled then
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
                if luaent then
                    luaent._wielditem_entity = wield_ent
                end
            end
        end

        -- Transfer attached x_bows arrows from player to corpse if x_bows is loaded
        local xbows_loaded = rawget(_G, "XBows")
        if player and xbows_loaded and type(xbows_loaded.transfer_arrows_to_corpse) == "function" then
            xbows_loaded.transfer_arrows_to_corpse(player, corpse)
            deathstats.unhide_corpse_arrows(corpse)
        end
    end
    return corpse
end

--- Get the primary tile texture name for a given node for particle fallback
---@param node_name string|nil Name of the node
---@return string texture Name of the texture or fallback
function deathstats.get_node_tile_texture(node_name)
    if not node_name or node_name == "" or node_name == "air" or node_name == "ignore" then
        node_name = deathstats.get_fallback_ground_node()
        if not node_name then return "" end
    end
    local cache = deathstats.node_tile_texture_cache
    local cached = cache and cache[node_name]
    if cached then
        return cached
    end

    local result = ""
    local ndef = core.registered_nodes[node_name]
    if ndef and ndef.tiles then
        local t = ndef.tiles[1]
        if type(t) == "string" then
            result = t
        elseif type(t) == "table" and t.name then
            result = t.name
        end
    end
    if result == "" then
        local fallback_name = deathstats.get_fallback_ground_node()
        if fallback_name and fallback_name ~= node_name then
            local fb_def = core.registered_nodes[fallback_name]
            if fb_def and fb_def.tiles then
                local t = fb_def.tiles[1]
                if type(t) == "string" then
                    result = t
                elseif type(t) == "table" and t.name then
                    result = t.name
                end
            end
        end
    end
    if cache then
        cache[node_name] = result
    end
    return result
end

--- Determine the appropriate particle effect for a corpse based on death cause and environment
---@param corpse_pos table The {x, y, z} position of the corpse
---@param death_info table|nil Optional death analysis table
---@return string effect_type "water"|"lava"|"fire"|"impact"
function deathstats.get_corpse_effect_type(corpse_pos, death_info)
    -- Probe the physical environment around corpse_pos first (detects settled water/lava/fire)
    if corpse_pos then
        local probe_offsets = {
            vector.new(corpse_pos.x, corpse_pos.y, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y - 0.3, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y - 0.6, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y - 1.0, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y + 0.2, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y + 0.5, corpse_pos.z),
        }
        for _, ppos in ipairs(probe_offsets) do
            local node = core.get_node_or_nil(ppos)
            if node and node.name and node.name ~= "air" and node.name ~= "ignore" then
                local nname = node.name:lower()
                if nname:find("lava") then
                    return "lava"
                elseif nname:find("fire") or nname:find("flame") then
                    return "fire"
                elseif nname:find("water") then
                    return "water"
                end
                local ndef = core.registered_nodes[node.name]
                if ndef then
                    local is_liq = (ndef.drawtype == "liquid" or ndef.drawtype == "flowingliquid"
                        or ndef.liquidtype == "source" or ndef.liquidtype == "flowing")
                    if is_liq then
                        if (ndef.groups and ndef.groups.lava) or nname:find("lava") then
                            return "lava"
                        else
                            return "water"
                        end
                    end
                end
                local idef = core.registered_items[node.name]
                if idef and idef.groups then
                    if idef.groups.lava then
                        return "lava"
                    elseif idef.groups.water or idef.groups.liquid then
                        return "water"
                    elseif idef.groups.fire then
                        return "fire"
                    end
                end
            end
        end
    end

    -- Fall back to death_info cause / category if the corpse is on dry ground or in air
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

    return "impact"
end

--- Create a modern ParticleSpawner definition table with graceful fallback to older Luanti clients
---@param effect_type string "water"|"lava"|"fire"|"impact"
---@param corpse_pos table The {x, y, z} position of the corpse
---@param attached_obj ObjectRef|nil Optional corpse ObjectRef to attach particles to
---@return table|nil def ParticleSpawner definition table
function deathstats.create_corpse_particlespawner_def(effect_type, corpse_pos, attached_obj)
    if not corpse_pos then return nil end
    local cx, cy, cz = corpse_pos.x, corpse_pos.y, corpse_pos.z
    local has_attached = attached_obj and (not attached_obj.is_valid or attached_obj:is_valid())

    if effect_type == "water" then
        -- Bubbles floating upwards through water continuously from random positions on the submerged corpse
        return {
            amount = 8,
            time = 0, -- Continuous spawner
            collisiondetection = false,
            collision_removal = false,
            glow = 3,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.35, y = 0.05, z = -0.35 } or { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = has_attached and { x = 0.35, y = 0.25, z = 0.35 } or { x = cx + 0.35, y = cy + 0.25, z = cz + 0.35 },
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
                min = has_attached and vector.new(-0.35, 0.05, -0.35) or vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = has_attached and vector.new(0.35, 0.25, 0.35) or vector.new(cx + 0.35, cy + 0.25, cz + 0.35),
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
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.35, y = 0.05, z = -0.35 } or { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = has_attached and { x = 0.35, y = 0.30, z = 0.35 } or { x = cx + 0.35, y = cy + 0.30, z = cz + 0.35 },
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
                min = has_attached and vector.new(-0.35, 0.05, -0.35) or vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = has_attached and vector.new(0.35, 0.30, 0.35) or vector.new(cx + 0.35, cy + 0.30, cz + 0.35),
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
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.35, y = 0.05, z = -0.35 } or { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = has_attached and { x = 0.35, y = 0.30, z = 0.35 } or { x = cx + 0.35, y = cy + 0.30, z = cz + 0.35 },
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
                min = has_attached and vector.new(-0.35, 0.05, -0.35) or vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = has_attached and vector.new(0.35, 0.30, 0.35) or vector.new(cx + 0.35, cy + 0.30, cz + 0.35),
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
        local ground_node_name = nil
        local ground_param2 = 0
        local check_positions = {
            { x = cx, y = math.floor(cy), z = cz },
            { x = cx, y = math.floor(cy - 0.5), z = cz },
            { x = cx, y = math.floor(cy - 1.0), z = cz },
        }
        for _, cpos in ipairs(check_positions) do
            local n = core.get_node_or_nil(cpos)
            if n and n.name ~= "air" and n.name ~= "ignore" then
                ground_node_name = n.name
                ground_param2 = n.param2 or 0
                break
            end
        end

        ground_node_name = ground_node_name or deathstats.get_fallback_ground_node()
        if not ground_node_name then
            return nil
        end

        local fallback_tex = deathstats.get_node_tile_texture(ground_node_name)

        return {
            amount = 28,
            time = 0.15, -- Moment of death impact burst (not continuous)
            collisiondetection = true,
            collision_removal = false,
            node = { name = ground_node_name, param2 = ground_param2 },
            texture = fallback_tex,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.45, y = -0.05, z = -0.45 } or { x = cx - 0.45, y = cy - 0.05, z = cz - 0.45 },
            maxpos = has_attached and { x = 0.45, y = 0.15, z = 0.45 } or { x = cx + 0.45, y = cy + 0.15, z = cz + 0.45 },
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
                min = has_attached and vector.new(-0.45, -0.05, -0.45) or vector.new(cx - 0.45, cy - 0.05, cz - 0.45),
                max = has_attached and vector.new(0.45, 0.15, 0.45) or vector.new(cx + 0.45, cy + 0.15, cz + 0.45),
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
            texpool = {
                {
                    name = fallback_tex,
                },
            },
        }
    end
end

--- Spawn an instantaneous localized burst of node debris particles at the impact site
---@param pos Vector The collision contact point
---@param ground_node_name string|nil The node name struck
---@param intensity number|nil Impact velocity or damage
function deathstats.spawn_impact_burst(pos, ground_node_name, intensity)
    if deathstats.config.enable_corpse_particles == false or not pos then return end
    local scale = math.min(2.0, math.max(0.6, (tonumber(intensity) or 5.0) / 6.0))
    local node_name = ground_node_name or deathstats.get_fallback_ground_node()
    if not node_name then return end
    local tex = deathstats.get_node_tile_texture(node_name)
    local cx, cy, cz = pos.x, pos.y, pos.z
    local min_p = vector.new(cx - 0.35, cy - 0.05, cz - 0.35)
    local max_p = vector.new(cx + 0.35, cy + 0.15, cz + 0.35)
    local min_v = vector.new(-1.6 * scale, 1.2 * scale, -1.6 * scale)
    local max_v = vector.new(1.6 * scale, 3.0 * scale, 1.6 * scale)
    local min_a = vector.new(0, -9.81, 0)
    local max_a = vector.new(0, -9.81, 0)
    local p_def = {
        amount = math.floor(16 * scale),
        time = 0.08,
        collisiondetection = true,
        -- Legacy client fields (< v5.6)
        minpos = min_p,
        maxpos = max_p,
        minvel = min_v,
        maxvel = max_v,
        minacc = min_a,
        maxacc = max_a,
        minexptime = 0.4,
        maxexptime = 0.8,
        minsize = 0.8,
        maxsize = 1.6,
        texture = tex,
        node = { name = node_name },
        -- Modern Luanti fields (v5.6+)
        pos = { min = min_p, max = max_p },
        vel = { min = min_v, max = max_v },
        acc = { min = min_a, max = max_a },
        exptime = { min = 0.4, max = 0.8 },
        size = { min = 0.8, max = 1.6 },
        texpool = {
            {
                name = tex,
            },
        },
    }
    core.add_particlespawner(p_def)
end

--- Spawn corpse particle spawner(s) according to death cause/environment
---@param corpse_pos table The {x, y, z} position of the corpse
---@param death_info table|nil Optional death analysis table
---@param attached_obj ObjectRef|nil Optional corpse ObjectRef to attach particles to
---@return number[] spawner_ids Array of active particle spawner IDs
---@return string|nil effect_type The type of effect spawned (e.g. "water", "lava", "fire", "impact")
function deathstats.spawn_corpse_particles(corpse_pos, death_info, attached_obj)
    if not corpse_pos then return {}, nil end
    if deathstats.config.enable_corpse_particles == false then return {}, nil end

    local effect_type = deathstats.get_corpse_effect_type(corpse_pos, death_info)
    local def = deathstats.create_corpse_particlespawner_def(effect_type, corpse_pos, attached_obj)
    if not def then return {}, effect_type end

    local spawner_id = core.add_particlespawner(def)
    local spawner_ids = {}
    if spawner_id and spawner_id > 0 then
        table.insert(spawner_ids, spawner_id)
    end
    return spawner_ids, effect_type
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
    local papi = rawget(_G, "x_player_api") or rawget(_G, "player_api")
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
function deathstats.is_armor_dropped(_player)
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
    -- Creative mode: players do not lose inventory
    if player and player:is_player() then
        local name = player:get_player_name()
        if name and core.is_creative_enabled(name) then
            return false
        end
    end

    -- Engine & Game Settings: keep_inventory flags
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

    -- Bones mod configuration (Luanti Game / default games)
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

    -- Mod-specific drop handlers
    if rawget(_G, "mcl_death_drop") ~= nil or rawget(_G, "rp_drop_items_on_die") ~= nil then
        return true
    end

    -- Default engine behavior (without bones or drop mods, inventory is kept)
    return false
end

--- Extract the player's active wielded item name, ignoring internal camera hands
---@param player ObjectRef The player object
---@return string item_name The item technical name (e.g. "default:sword_steel"), or "" if empty/hand
function deathstats.get_player_wield_item(player)
    if not player or not player:is_player() then
        return ""
    end

    -- Check player's direct wielded item
    local stack = player:get_wielded_item()
    local name = deathstats.get_stack_name(stack)
    if name ~= "" and name ~= "deathstats:camera_hand" then
        return name
    end

    -- Check inventory main list at wield index
    local inv = player:get_inventory()
    local wield_idx = player:get_wield_index() or 1
    if inv then
        local main_stack = inv:get_stack("main", wield_idx)
        local main_name = deathstats.get_stack_name(main_stack)
        if main_name ~= "" and main_name ~= "deathstats:camera_hand" then
            return main_name
        end
    end

    -- Check stashed main inventory from player metadata if available
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

    -- Check 3d_armor textures table if available
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

    -- Detect if using the standard 3-slot 3d_armor model (3d_armor_character.b3d / 3d_armor_character.glb)
    local is_3d_armor = not is_skinsdb and (
        (mesh == "3d_armor_character.b3d" or mesh == "3d_armor_character.glb")
        or (armor_mod and ((armor_mod.textures and armor_mod.textures[name]) or (mesh and mesh:find("3d_armor"))))
        or (armor_mod and props.textures and #props.textures == 3)
    )

    local textures

    -- skinsdb + 3d_armor support: 4 material slots
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

    -- Standalone 3d_armor support: 3 material slots (skin, armor, wielditem)
    elseif is_3d_armor then
        local fallback_armor = (props.mesh and props.mesh:find("%.glb$")) and "3d_armor_character.glb" or "3d_armor_character.b3d"
        mesh = (armor_mod and armor_mod.models and armor_mod.models[name]) or (mesh and mesh:find("3d_armor") and mesh) or fallback_armor
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

    -- Fallback skin mods: skinsdb (legacy/without armor), simple_skins, wardrobe, player_api, mcl_skins
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

    -- Fallback for transparent texture trap:
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

    -- Check if direct node or bones is already right below or at pos
    local check_pos = vector.round(pos)
    local direct_node = core.get_node_or_nil(check_pos) or { name = "air" }
    if direct_node.name == "bones:bones" then
        return check_pos.y + 0.5
    end

    -- Determine downward search depth:
    -- For fall deaths (category == "fall", or nil/unspecified in backward-compatible unit tests),
    -- allow searching down to ground impact level (up to 40 nodes).
    -- For non-fall deaths in mid-air (suicide, /kill, mobs, projectiles, fire), only search near feet (2.5 nodes)
    -- to snap to floors/slabs/stairs if standing on solid ground. If suspended in mid-air, retain exact death height pos.y!
    local is_fall = (death_info == nil) or (death_info.category == nil)
        or (death_info.category == "fall") or (death_info.category == "explosion")
    local max_depth = is_fall and 40 or 2.5

    -- Downward raycast to detect exact collision surface (handles nodes, slabs, stairs, meshes)
    local start_pos = vector.new(pos.x, pos.y + 0.5, pos.z)
    local end_pos = vector.new(pos.x, pos.y - max_depth, pos.z)
    local ray = core.raycast(start_pos, end_pos, false, false)
    for pointed_thing in ray do
        if pointed_thing.type == "node" and pointed_thing.under then
            local node = core.get_node_or_nil(pointed_thing.under)
            local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
            if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                if pointed_thing.intersection_point then
                    return pointed_thing.intersection_point.y
                else
                    return pointed_thing.under.y + 0.5
                end
            end
        end
    end

    -- Fallback: discrete node scanning downward from math.floor(pos.y + 0.5) down to max_depth
    local start_y = math.floor(pos.y + 0.5)
    local check_x = math.floor(pos.x + 0.5)
    local check_z = math.floor(pos.z + 0.5)
    local min_y = math.floor(pos.y - max_depth + 0.5)
    for y = start_y, min_y, -1 do
        local npos = vector.new(check_x, y, check_z)
        local node = core.get_node_or_nil(npos)
        local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
        if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
            return y + 0.5
        end
    end

    -- If no solid ground found within max_depth (e.g. suspended in mid-air / floating), retain pos.y
    return pos.y
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
                        if settled_effect ~= current_effect or not has_active_spawners then
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
        local probe_steps = { 0, 0.06 }
        for _, offset_angle in ipairs(probe_steps) do
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

    -- Extract player visuals across skin mods and spawn corpse placeholder entity
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

    local lb = deathstats.last_blow[name]
    local corpse = nil
    if not expect_bones then
        corpse = deathstats.spawn_and_setup_corpse(corpse_pos, visuals, player, death_info, lb)
    end
    local particle_spawners = nil
    local current_effect_type = nil
    if deathstats.config.enable_corpse_particles ~= false then
        local particle_pos = bones_pos or corpse_pos
        particle_spawners, current_effect_type = deathstats.spawn_corpse_particles(particle_pos, death_info, corpse)
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

    -- Restore player physical and visual properties & nametag
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

    -- Restore camera mode back to first person, then unlock to any mode
    if player.set_camera then
        player:set_camera({ mode = "first" })
    end

    -- Reset eye offsets to zero
    if player.set_eye_offset then
        player:set_eye_offset(vector.zero(), vector.zero(), vector.zero())
    end

    -- Reset pitch back to horizontal eye level
    if player.set_look_vertical then
        player:set_look_vertical(0)
    end

    -- Restore standing animation (with deferred retries to ensure player_api handshake is complete)
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
--- Show minimal photo mode overlay with single button to restore death UI
---@param player ObjectRef The deceased player object
function deathstats.show_photo_mode_formspec(player)
    if not player then return end
    local name = player:get_player_name()
    local c = deathstats.colors
    local fs = {
        "formspec_version[6]",
        "size[2.8,0.65]",
        "position[0.96,0.94]",
        "anchor[1.0,1.0]",
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",
        "style_type[button;border=true;bgimg_middle=true]",
        string.format("style[btn_show_ui;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border),
        "button[0,0;2.8,0.65;btn_show_ui;        " .. F(S("SHOW UI")) .. "]",
        "image[0.22,0.14;0.36,0.36;deathstats_icon_eye.png]",
        "tooltip[btn_show_ui;" .. F(S("Restore Death Screen UI")) .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",
    }
    core.show_formspec(name, "deathstats:photo_mode", table.concat(fs, ""))
end

--- Show corpse epitaph tombstone plaque formspec when living players right-click a settled corpse
---@param clicker ObjectRef The living player inspecting the corpse
---@param corpse_ref ObjectRef|table The corpse entity reference or luaentity table
function deathstats.show_corpse_epitaph_formspec(clicker, corpse_ref)
    if not clicker or not clicker:is_player() then return end
    local clicker_name = clicker:get_player_name()
    local luaent = corpse_ref
    if corpse_ref and corpse_ref.get_luaentity then
        luaent = corpse_ref:get_luaentity() or corpse_ref
    end
    if not luaent then return end

    local pname = (luaent and luaent._player_name) or (corpse_ref and corpse_ref._player_name) or "An Adventurer"
    local dinfo = (luaent and luaent._death_info) or (corpse_ref and corpse_ref._death_info) or {}
    local last = (luaent and luaent._last_life) or (corpse_ref and corpse_ref._last_life) or {}
    local cause = dinfo.reason_text or last.last_cause
    if not cause or cause == "" then
        if dinfo.category == "fall" and dinfo.fall_height then
            cause = string.format(S("Fell %dm to their demise"), dinfo.fall_height)
        elseif dinfo.fall_height then
            cause = string.format(S("Fell %dm"), dinfo.fall_height)
        else
            cause = S("Met their untimely end")
        end
    elseif dinfo.fall_height and not cause:find("%d+m") then
        cause = cause .. string.format(" (%dm)", dinfo.fall_height)
    end
    local weapon = dinfo.weapon_name or dinfo.weapon or last.last_weapon
    local funny = dinfo.funny_note or last.last_funny or "May they rest in peace."
    local time_alive = deathstats.format_time(last.time_alive or 0)

    -- Build rich tooltips for Cause of Death, Survival Summary, and Inscripted Words
    local cause_tt = { F(S("Cause of Death: @1", cause)) }
    if dinfo.killer or dinfo.killer_name then
        local k_name = dinfo.killer_name or dinfo.killer
        if dinfo.killer_hp and dinfo.killer_max_hp then
            table.insert(cause_tt, F(S("Slayer: @1 (@2/@3 HP)", k_name, dinfo.killer_hp, dinfo.killer_max_hp)))
        else
            table.insert(cause_tt, F(S("Slayer: @1", k_name)))
        end
    end
    if weapon and weapon ~= "" and weapon ~= "None" then
        table.insert(cause_tt, F(S("Weapon: @1", weapon)))
    end
    if dinfo.fall_height then
        table.insert(cause_tt, F(S("Fall Distance: @1m", dinfo.fall_height)))
    end
    local death_pos = dinfo.pos or (last and last.death_pos)
    if death_pos then
        table.insert(cause_tt, string.format("Location: (%d, %d, %d)",
            math.floor(death_pos.x + 0.5), math.floor(death_pos.y + 0.5), math.floor(death_pos.z + 0.5)))
    end

    local surv_tt = { F(S("Survived: @1", time_alive)) }
    if (last.blocks_mined and last.blocks_mined > 0) or (last.total_ores and last.total_ores > 0) then
        table.insert(surv_tt, F(S("Mining: @1 blocks (@2 ores)",
            deathstats.format_number(last.blocks_mined or 0), deathstats.format_number(last.total_ores or 0))))
    end
    if (last.damage_dealt and last.damage_dealt > 0) or (last.damage_taken and last.damage_taken > 0) then
        table.insert(surv_tt, F(S("Combat: @1 dealt / @2 taken",
            deathstats.format_number(last.damage_dealt or 0), deathstats.format_number(last.damage_taken or 0))))
    end
    if last.mobs_killed and last.mobs_killed > 0 then
        table.insert(surv_tt, F(S("Mobs Slain: @1", deathstats.format_number(last.mobs_killed))))
    end
    if last.players_killed and last.players_killed > 0 then
        table.insert(surv_tt, F(S("Players Slain: @1", deathstats.format_number(last.players_killed))))
    end
    if last.distance_traveled and last.distance_traveled > 0 then
        table.insert(surv_tt, string.format("Distance Traveled: %.1f m", last.distance_traveled))
    end

    local funny_tt = {
        F(S("Epitaph in Memory of @1:", pname)),
        "\"" .. F(funny) .. "\"",
    }

    local c = deathstats.colors
    local fs = {
        "formspec_version[6]",
        "size[8.0,5.4]",
        "position[0.5,0.5]",
        "anchor[0.5,0.5]",
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Stone plaque modal box
        "box[0.3,0.3;7.4,4.8;" .. c.card_modal .. "]",
        "box[0.3,0.3;7.4,0.08;" .. c.btn_secondary_border .. "]",
        "box[0.3,5.02;7.4,0.08;" .. c.btn_secondary_border .. "]",
        "box[0.3,0.3;0.08,4.8;" .. c.btn_secondary_border .. "]",
        "box[7.62,0.3;0.08,4.8;" .. c.btn_secondary_border .. "]",

        -- Header
        "image[0.6,0.5;0.6,0.6;deathstats_icon_skull.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[1.4,0.75;" .. F(S("IN MEMORIAM")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[1.4,1.05;" .. F(S("Here lies @1", pname)) .. "]",

        -- Details Inset
        "box[0.6,1.4;6.8,2.8;" .. c.card_inset .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_crimson),
        "label[0.9,1.72;" .. F(S("Cause of Death:")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.9,2.05;" .. F(deathstats.truncate_str(cause, 45)) .. "]",
        "tooltip[0.8,1.60;6.4,0.65;" .. table.concat(cause_tt, "\n") .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[0.9,2.45;" .. F(S("Time Survived:")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.9,2.78;" .. F(time_alive) .. (weapon and weapon ~= "None" and ("  |  " .. F(weapon)) or "") .. "]",
        "tooltip[0.8,2.35;6.4,0.65;" .. table.concat(surv_tt, "\n") .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        string.format("style_type[label;textcolor=%s]", c.text_muted),
        "label[0.9,3.18;" .. F(S("Inscripted Words:")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[0.9,3.52;\"" .. F(deathstats.truncate_str(funny, 50)) .. "\"]",
        "tooltip[0.8,3.10;6.4,0.65;" .. table.concat(funny_tt, "\n") .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        -- Close Button
        "style_type[button;border=true;bgimg_middle=true]",
        string.format("style[btn_close_epitaph;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border),
        "button[2.8,4.4;2.4,0.55;btn_close_epitaph;" .. F(S("CLOSE")) .. "]",
    }

    core.show_formspec(clicker_name, "deathstats:corpse_epitaph", table.concat(fs, ""))
end

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

    -- Location formatting
    local loc_str = nil
    local loc_tooltip = nil
    local death_p = last.death_pos or (death_info and (death_info.death_pos or death_info.pos))
    if death_p then
        local p = death_p
        local depth = (death_info and death_info.depth_desc) or last.depth_desc or deathstats.get_depth_description(p.y)
        local biome = (death_info and death_info.biome_name) or last.biome_name or deathstats.get_biome_at_pos(p)
        if biome and biome ~= "" and biome ~= "Unknown" then
            loc_str = string.format("(%d, %d, %d) · %s [%s]", p.x, p.y, p.z, depth, biome)
        else
            loc_str = string.format("(%d, %d, %d) · %s", p.x, p.y, p.z, depth)
        end
        loc_tooltip = string.format("Death Location: (X: %d, Y: %d, Z: %d)\nElevation: %s (Y=%d)%s",
            p.x, p.y, p.z, depth, p.y,
            (biome and biome ~= "" and biome ~= "Unknown") and ("\nBiome: " .. biome) or "")
    end

    -- Specific lethal context
    local lethal_sub = nil
    if (death_info and death_info.killer_hp) or last.killer_hp then
        local khp = (death_info and death_info.killer_hp) or last.killer_hp
        local kmax = (death_info and (death_info.killer_max_hp or death_info.killer_hp_max)) or last.killer_max_hp or last.killer_hp_max or 20
        lethal_sub = string.format(S("Killer HP: %d / %d ❤️"), khp, kmax)
    elseif (death_info and death_info.fall_height) or last.fall_height then
        local fh = (death_info and death_info.fall_height) or last.fall_height
        local fs_val = (death_info and death_info.fall_speed) or last.fall_speed
        if fs_val then
            lethal_sub = string.format(S("Fell %dm at %.1f m/s"), fh, fs_val)
        else
            lethal_sub = string.format(S("Fell %d meters"), fh)
        end
    end

    -- Compact sidebar card docked to the side leaving center death scene completely unobstructed
    local fs = {
        "formspec_version[6]",
        "size[5.6,6.2]",
        string.format("position[%.2f,0.88]", pos_x),
        string.format("anchor[%.2f,1.0]", anchor_x),
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Dark stylized card container (width 5.0, margins 0.3)
        "box[0.3,0.2;5.0,5.05;" .. c.card_sidebar .. "]",
        "box[0.3,0.2;5.0,0.05;" .. c.crimson_border .. "]",
        "box[0.3,5.20;5.0,0.05;" .. c.crimson_border .. "]",

        -- Photo Mode Toggle Button (Top Right of Card)
        string.format("style[btn_photo_mode;border=false;bgcolor=%s;bgcolor_hovered=#ffffff22;bordercolor=%s]",
            c.transparent, c.transparent),
        "image_button[4.75,0.30;0.40,0.40;deathstats_icon_camera.png;btn_photo_mode;]",
        "tooltip[btn_photo_mode;" .. F(S("Photo Mode (Hide UI)")) .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        -- Header: Last Life Summary
        "image[0.5,0.35;0.35,0.35;deathstats_icon_clock.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[0.95,0.56;", F(S("Last Life Summary")), "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.95,0.82;", F(S("Survived: @1", time_str)), "]",
    }

    if last.is_new_record then
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_gold))
        table.insert(fs, "label[0.95,1.05;" .. F(S("★ NEW PERSONAL RECORD!")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    end

    local row_offset = last.is_new_record and 0.22 or 0.0

    -- Row 1: Combat Stats
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_sword.png]", 1.15 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 1.38 + row_offset, F(S("Damage: @1 dealt / @2 taken", dmg_dealt, dmg_taken))))

    -- Row 2: Kills
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_skull.png]", 1.57 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 1.80 + row_offset, F(S("Slain: @1 mobs / @2 pvp", mobs_slain, players_slain))))

    -- Row 3: Mining
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_pickaxe.png]", 1.99 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 2.22 + row_offset, F(S("Mined: @1 (@2 ores)", mined_str, ores_str))))

    -- Row 4: Items
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_heart.png]", 2.41 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 2.64 + row_offset, F(S("Items: @1 made / @2 eaten", items_crafted, items_consumed))))

    -- Row 5: Fatal Blow Inset Box (Expands gracefully with coordinates and lethal details)
    local box_y = 2.85 + row_offset
    local box_h = 2.20 - row_offset
    table.insert(fs, string.format("box[0.5,%.2f;4.6,%.2f;%s]", box_y, box_h, c.card_inset))

    local fatal_full_tt = string.format("Fatal Blow: %s\nWeapon: %s (Distance: %s)%s%s",
        fatal_cause, fatal_weapon, dist_str,
        loc_tooltip and ("\n" .. loc_tooltip) or "",
        lethal_sub and ("\n" .. lethal_sub) or "")
    table.insert(fs, string.format("tooltip[0.5,%.2f;4.6,%.2f;%s;%s;%s]", box_y, box_h, F(fatal_full_tt), c.tooltip_bg, c.text_gold))

    table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
    table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 0.25, F(S("Fatal Blow:"))))
    table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 0.58, F(deathstats.truncate_str(fatal_cause, 32))))
    table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 0.95, F(deathstats.truncate_str(fatal_weapon, 20) .. "  |  " .. dist_str)))

    if loc_str then
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_gold))
        table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 1.30, F(deathstats.truncate_str(loc_str, 42))))
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    end

    if lethal_sub then
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
        table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 1.62, F(lethal_sub)))
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    end

    -- Button Styling
    table.insert(fs, "style_type[button;border=true;bgimg_middle=true]")
    table.insert(fs, string.format("style[btn_try_again;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
        c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border))
    table.insert(fs, string.format("style[btn_more_stats;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
        c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border))

    -- Action Buttons side by side at bottom
    table.insert(fs, string.format("button[0.3,5.40;2.4,0.68;btn_try_again;%s]", F(S("TRY AGAIN"))))
    table.insert(fs, string.format("button[2.9,5.40;2.4,0.68;btn_more_stats;%s]", F(S("MORE STATS"))))

    core.show_formspec(name, "deathstats:death", table.concat(fs, ""))
end

--- Display the Lifetime Statistics Dashboard with transparent backdrop and accessible tabs
---@param player ObjectRef The player viewing statistics
---@param tab string|nil The active tab name ("overview", "records", "ores", or "combat")
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

    -- 4 Tab Button Styles: active tab has high-contrast bright crimson + glowing border, inactive has distinct slate
    local tab_defs = {
        { id = "tab_overview", key = "overview", title = "Overview",       x = 0.5 },
        { id = "tab_records",  key = "records",  title = "Personal Bests", x = 3.9 },
        { id = "tab_ores",     key = "ores",     title = "Ores Breakdown", x = 7.3 },
        { id = "tab_combat",   key = "combat",   title = "Combat Record",  x = 10.7 },
    }
    for _, t in ipairs(tab_defs) do
        if tab == t.key then
            table.insert(fs, string.format("style[%s;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
                t.id, c.tab_active_bg, c.tab_active_hover_bg, c.tab_active_text, c.tab_active_border, c.tab_active_hover_border))
            table.insert(fs, string.format("box[%.1f,1.45;3.2,0.07;%s]", t.x, c.active_strip))
        else
            table.insert(fs, string.format("style[%s;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
                t.id, c.tab_inactive_bg, c.tab_inactive_hover_bg, c.tab_inactive_text, c.tab_inactive_border, c.tab_inactive_hover_border))
        end
        local label_txt = (tab == t.key) and ("▶ " .. t.title) or t.title
        table.insert(fs, string.format("button[%.1f,0.85;3.2,0.58;%s;%s]", t.x, t.id, F(label_txt)))
    end

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

        -- Card 4: Nemesis & Recent Cause (Bottom Right)
        table.insert(fs, "box[7.4,3.45;6.4,1.6;" .. c.card_panel .. "]")
        table.insert(fs, "image[7.6,3.55;0.4,0.4;deathstats_icon_heart.png]")
        local nemesis_str = S("None")
        local nemesis_max = 0
        if life.killers_count then
            for k, count in pairs(life.killers_count) do
                if count > nemesis_max then
                    nemesis_max = count
                    local display_k = k
                    if k:find(":") then
                        display_k = deathstats.format_name(k)
                    end
                    nemesis_str = string.format("%s (%d deaths)", display_k, count)
                end
            end
        end
        table.insert(fs, "label[8.2,3.75;" .. F(S("Arch-Nemesis: @1", nemesis_str)) .. "]")
        table.insert(fs, "label[8.2,4.18;" .. F(S("Most Recent Cause:")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
        table.insert(fs, "label[8.2,4.58;" .. F(deathstats.truncate_str(life.last_cause or "None", 36)) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))

        local nemesis_tooltip = string.format("Arch-Nemesis: %s\nMost Recent Cause: %s", nemesis_str, life.last_cause or "None")
        table.insert(fs, string.format("tooltip[7.4,3.45;6.4,1.6;%s;%s;%s]", F(nemesis_tooltip), c.tooltip_bg, c.text_gold))

    elseif tab == "records" then
        -- Personal Bests Showcase (Left Panel)
        table.insert(fs, "box[0.7,1.65;6.4,3.4;" .. c.card_panel .. "]")
        table.insert(fs, "image[0.9,1.75;0.4,0.4;deathstats_icon_trophy.png]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_gold))
        table.insert(fs, "label[1.5,1.95;" .. F(S("Personal Bests (Single Life)")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
        local pb = life.personal_bests or {}
        table.insert(fs, "label[1.0,2.45;" .. F(S("Longest Life: @1", deathstats.format_time(pb.survival_time or 0))) .. "]")
        table.insert(fs, "label[1.0,2.88;" .. F(S("Best Killstreak: @1", pb.killstreak or 0)) .. "]")
        table.insert(fs, "label[1.0,3.31;" .. F(S("Most Kills in 1 Life: @1", pb.kills or 0)) .. "]")
        table.insert(fs, "label[1.0,3.74;" .. F(S("Most Damage Dealt: @1", deathstats.format_number(pb.damage_dealt or 0))) .. "]")
        table.insert(fs, "label[1.0,4.17;" .. F(S("Most Blocks Mined: @1", deathstats.format_number(pb.blocks_mined or 0))) .. "]")
        table.insert(fs, "label[1.0,4.60;" .. F(S("Most Ores Mined: @1", deathstats.format_number(pb.total_ores or 0))) .. "]")

        -- Cause-of-Death Distribution (Right Panel)
        table.insert(fs, "box[7.4,1.65;6.4,3.4;" .. c.card_panel .. "]")
        table.insert(fs, "image[7.6,1.75;0.4,0.4;deathstats_icon_skull.png]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
        table.insert(fs, "label[8.2,1.95;" .. F(S("Cause of Death Breakdown")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))

        local cat_counts = life.deaths_by_category or {}
        local total_d = life.deaths or 0
        local cat_list = {}
        for cat_name, count in pairs(cat_counts) do
            table.insert(cat_list, { name = cat_name, count = count })
        end
        table.sort(cat_list, function(a, b) return a.count > b.count end)

        if #cat_list == 0 then
            table.insert(fs, "label[8.2,2.60;" .. F(S("No deaths recorded yet. Undefeated!")) .. "]")
        else
            for i, entry in ipairs(cat_list) do
                if i <= 6 then
                    local y = 2.15 + i * 0.42
                    local pct = (total_d > 0) and math.floor((entry.count / total_d) * 100 + 0.5) or 0
                    local cat_title = deathstats.format_name(entry.name)
                    table.insert(fs, string.format("label[8.0,%.2f;%s]", y, F(string.format("%s: %d (%d%%)", cat_title, entry.count, pct))))
                end
            end
        end
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
                table.insert(fs, "label[" .. (x + (col_w - 1.85)) .. "," .. (y + 0.13) .. ";" .. F(deathstats.format_compact_number(ore.count)) .. " mined]")

                local ore_tt = string.format("Ore / Mineral: %s\nTechnical Name: %s\nTotal Extracted: %s",
                    ore.title, ore.name, deathstats.format_number(ore.count))
                table.insert(fs, string.format("tooltip[%s,%.2f;%s,0.42;%s;%s;%s]",
                    x, y - 0.08, col_w, F(ore_tt), c.tooltip_bg, c.text_gold))
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

        local combat_list = {}
        local players = life.players_slain or {}
        for pvictim, count in pairs(players) do
            table.insert(combat_list, {
                name = pvictim,
                count = count,
                title = pvictim, -- exact player username!
                is_player = true,
                icon = "deathstats_icon_sword.png",
            })
        end
        local mobs = life.mobs_slain or {}
        for mob_name, count in pairs(mobs) do
            table.insert(combat_list, {
                name = mob_name,
                count = count,
                title = deathstats.format_name(mob_name),
                is_player = false,
                icon = "deathstats_icon_skull.png",
            })
        end
        table.sort(combat_list, function(a, b)
            if a.count == b.count then
                return a.title < b.title
            end
            return a.count > b.count
        end)

        local total_combat_types = #combat_list
        table.insert(fs, "label[1.0,1.9;" .. F(S("Total Combat Slayings: @1 (@2 players, @3 mobs)",
            deathstats.format_number(kills),
            deathstats.format_number(life.players_killed or 0),
            deathstats.format_number(life.mobs_killed or 0))) .. "]")

        if total_combat_types == 0 and (life.players_killed or 0) == 0 then
            table.insert(fs, "label[5.0,3.2;" .. F(S("No combat kills recorded yet. A peaceful record.")) .. "]")
        else
            local total_rows = math.ceil(total_combat_types / 2)
            local has_scroll = total_rows > 5
            local container_w = has_scroll and 12.4 or 12.8
            local col_w = has_scroll and 5.95 or 6.15
            local col2_x = has_scroll and 6.25 or 6.45

            if has_scroll then
                table.insert(fs, string.format("scroll_container[0.8,2.18;%.2f,2.80;combat_scroll;vertical;0.1;0.1]", container_w))
            else
                table.insert(fs, "container[0.8,2.18]")
            end

            for i, entry in ipairs(combat_list) do
                local col = ((i - 1) % 2) + 1
                local row = math.floor((i - 1) / 2)
                local x = (col == 1) and 0.1 or col2_x
                local y = 0.08 + row * 0.46

                if row % 2 == 1 then
                    table.insert(fs, "box[" .. x .. "," .. (y - 0.08) .. ";" .. col_w .. ",0.42;" .. c.row_alt .. "]")
                end
                table.insert(fs, string.format("image[%s,%.2f;0.35,0.35;%s]", x + 0.1, y - 0.04, entry.icon))
                table.insert(fs, string.format("label[%s,%.2f;%s]", x + 0.65, y + 0.13, F(deathstats.truncate_str(entry.title, 22))))
                table.insert(fs, string.format("label[%s,%.2f;%s]", x + (col_w - 1.85), y + 0.13, F(deathstats.format_number(entry.count)) .. " slain"))

                local row_tt = string.format("%s: %s\nIdentifier: %s\nTotal Slain: %s",
                    entry.is_player and "Player" or "Mob", entry.title, entry.name, deathstats.format_number(entry.count))
                table.insert(fs, string.format("tooltip[%s,%.2f;%s,0.42;%s;%s;%s]",
                    x, y - 0.08, col_w, F(row_tt), c.tooltip_bg, c.text_gold))
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
    local is_dead = deathstats.is_player_dead and deathstats.is_player_dead(player)
    if is_dead then
        table.insert(fs, string.format("style[btn_back_death;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border))
        table.insert(fs, string.format("style[btn_modal_respawn;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border))
        table.insert(fs, "button[0.4,5.35;5.0,0.72;btn_back_death;" .. F(S("< BACK TO DEATH SCREEN")) .. "]")
        table.insert(fs, "button[9.1,5.35;5.0,0.72;btn_modal_respawn;" .. F(S("TRY AGAIN")) .. "]")
    else
        table.insert(fs, string.format("style[btn_close;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border))
        table.insert(fs, "button[4.75,5.35;5.0,0.72;btn_close;" .. F(S("CLOSE")) .. "]")
    end

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
