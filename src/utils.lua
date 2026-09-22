--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local S = core.get_translator(core.get_current_modname())

--- Safely normalize a 3D vector without producing NaN on zero length
---@param v Vector 3D vector to normalize
---@return Vector normalized The normalized unit vector, or (0,0,0) if zero length
function deathstats.safe_normalize(v)
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

--- Generate a pseudo-random floating point number in range [min_val, max_val]
---@param min_val number Minimum bound
---@param max_val number Maximum bound
---@return number val Random floating point value
function deathstats.random_float(min_val, max_val)
    return min_val + math.random() * (max_val - min_val)
end

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
    if deathstats.is_shutting_down then return false end

    -- Check if player_api registered_players knows this player (avoids offline player warnings)
    local papi = rawget(_G, "player_api")
    if type(papi) == "table" and type(papi.registered_players) == "table" and not papi.registered_players[name] then
        return false
    end
    local xpapi = rawget(_G, "x_player_api")
    if type(xpapi) == "table" and type(xpapi.registered_players) == "table" and not xpapi.registered_players[name] then
        return false
    end

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

