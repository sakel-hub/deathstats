--[[
    deathstats - Tactical Multiplayer Live Scoreboard (HUD & Formspec)
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local S = core.get_translator(core.get_current_modname())
local F = core.formspec_escape

deathstats.scoreboard_bg_cache = deathstats.scoreboard_bg_cache or {}

-- ==========================================
-- In-Game Time & Environment Utilities
-- ==========================================

--- Format the current in-game day/night cycle into a human-readable digital clock string
---@param format string|nil Optional format ("24h" or "12h"). Defaults to mod setting.
---@return string time_str Formatted in-game time (e.g. "19:30" or "07:30 PM")
function deathstats.get_gametime_formatted(format)
    local tod = core.get_timeofday() or 0
    local total_minutes = math.floor(tod * 1440 + 0.5) % 1440
    local hours = math.floor(total_minutes / 60)
    local minutes = total_minutes % 60
    format = format or deathstats.config.time_format or "24h"

    if format == "12h" then
        local suffix = (hours >= 12) and "PM" or "AM"
        local h12 = hours % 12
        if h12 == 0 then h12 = 12 end
        return string.format("%02d:%02d %s", h12, minutes, suffix)
    else
        return string.format("%02d:%02d", hours, minutes)
    end
end

--- Format active survival duration into a compact human-readable string
---@param sec number Duration in seconds
---@param is_small boolean|nil Whether to format for small display
---@return string time_str Formatted time string (e.g. "45s", "14m 20s", "2h 10m")
function deathstats.format_survival_time(sec, is_small)
    sec = math.max(0, math.floor(sec or 0))
    if sec < 60 then
        return string.format("%ds", sec)
    elseif sec < 3600 then
        local m = math.floor(sec / 60)
        local s = sec % 60
        if is_small or s == 0 then
            return string.format("%dm", m)
        else
            return string.format("%dm %ds", m, s)
        end
    else
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        if is_small or m == 0 then
            return string.format("%dh", h)
        else
            return string.format("%dh %dm", h, m)
        end
    end
end

-- ==========================================
-- Live Player Statistics Inspection & Status
-- ==========================================

--- Query player armor defense points across all supported Luanti armor mods and engine groups
--- Supports 3d_armor (level), mcl_armor (armor_points), hbarmor, and engine fleshy group fallbacks
---@param player ObjectRef|nil The player object to inspect
---@return integer points Total effective armor defense points (0-100+)
function deathstats.get_player_armor_points(player)
    if not player or not player:is_player() then
        return 0
    end
    local name = player:get_player_name()

    -- 1. Check 3d_armor mod definition table
    local armor_mod = rawget(_G, "armor")
    if armor_mod and armor_mod.def and armor_mod.def[name] then
        local lvl = armor_mod.def[name].level
        if type(lvl) == "number" and lvl >= 0 then
            return math.floor(lvl)
        end
    end

    -- 2. Check MineClone / Voxelibre mcl_armor player metadata if mod is loaded
    if core.get_modpath("mcl_armor") ~= nil or rawget(_G, "mcl_armor") ~= nil then
        local meta = player:get_meta()
        if meta then
            local mcl_pts = meta:get_int("mcl_armor:armor_points")
            if mcl_pts and mcl_pts > 0 then
                return mcl_pts
            end
        end
    end

    -- 3. Check hbarmor runtime table
    local hbarmor = rawget(_G, "hbarmor")
    if hbarmor and hbarmor.armor and hbarmor.armor[name] then
        local arm = tonumber(hbarmor.armor[name])
        if arm and arm >= 0 then
            return math.floor(arm)
        end
    end

    -- 4. Engine armor groups fallback (fleshy resistance)
    local groups = player:get_armor_groups()
    if groups and groups.fleshy and groups.fleshy < 100 then
        return math.max(0, 100 - groups.fleshy)
    end

    return 0
end

--- Query round-trip network ping latency in milliseconds for a connected player
---@param player_name string Username of the target player
---@return integer ping Latency in milliseconds (0 for local or unavailable)
function deathstats.get_player_ping(player_name)
    if not player_name or player_name == "" then return 0 end
    local info = core.get_player_information(player_name)
    if info and info.avg_rtt then
        return math.max(0, math.floor(info.avg_rtt * 1000 + 0.5))
    end
    return 0
end

--- Evaluate color threshold for ping latency (numeric HUD RGB)
---@param ping integer Network round-trip latency in milliseconds
---@return integer color RGB color (green, yellow, or red)
function deathstats.get_ping_color(ping)
    ping = ping or 0
    if ping < 60 then
        return deathstats.colors.hud_ping_good
    elseif ping <= 140 then
        return deathstats.colors.hud_ping_warn
    else
        return deathstats.colors.hud_ping_bad
    end
end

--- Evaluate formspec text color string for ping latency
---@param ping integer Network round-trip latency in milliseconds
---@return string color_str Hex color string
function deathstats.get_ping_textcolor(ping)
    ping = ping or 0
    if ping < 60 then
        return deathstats.colors.text_ping_good
    elseif ping <= 140 then
        return deathstats.colors.text_ping_warn
    else
        return deathstats.colors.text_ping_bad
    end
end

--- Reset player last active timestamp for ultra-efficient AFK tracking
---@param player_or_name ObjectRef|string The player object or username
function deathstats.reset_player_activity(player_or_name)
    if not player_or_name then return end
    local name = (type(player_or_name) == "string") and player_or_name
        or (player_or_name.get_player_name and player_or_name:get_player_name())
    if name and name ~= "" then
        deathstats.last_activity[name] = core.get_gametime()
    end
end

--- Check if a player is currently deceased (viewing death screen or HP <= 0)
---@param player_or_name ObjectRef|string The player object or username
---@return boolean is_dead True if the player is dead
function deathstats.is_player_dead(player_or_name)
    if not player_or_name then return false end
    local name = (type(player_or_name) == "string") and player_or_name
        or (player_or_name.get_player_name and player_or_name:get_player_name())
    if not name or name == "" then return false end
    if deathstats.dead_players[name] or (deathstats.active_screens and deathstats.active_screens[name]) then
        return true
    end
    local p = (type(player_or_name) ~= "string") and player_or_name or core.get_player_by_name(name)
    if p and p:is_player() and p:get_hp() <= 0 then
        return true
    end
    return false
end

--- Check if a player is currently AFK (away from keyboard)
---@param player_or_name ObjectRef|string The player object or username
---@return boolean is_afk True if inactive duration exceeds afk_timeout setting
function deathstats.is_player_afk(player_or_name)
    if not player_or_name then return false end
    local name = (type(player_or_name) == "string") and player_or_name
        or (player_or_name.get_player_name and player_or_name:get_player_name())
    if not name or name == "" then return false end
    if deathstats.is_player_dead(name) then
        return false
    end
    local last_act = deathstats.last_activity[name]
    if not last_act then
        deathstats.last_activity[name] = core.get_gametime()
        return false
    end
    local timeout = deathstats.config.afk_timeout or 120
    return (core.get_gametime() - last_act) >= timeout
end

--- Get current health points safely
---@param player ObjectRef|nil The player object
---@return integer hp Current health points
function deathstats.get_player_hp(player)
    if not player or not player:is_player() then return 0 end
    return math.max(0, player:get_hp())
end

-- ==========================================
-- Pluggable Scoreboard Column Registration API
-- ==========================================

-- Column registration API is declared in api.lua (deathstats.register_scoreboard_column, etc.)

-- Register Default Columns
deathstats.register_scoreboard_column("rank", {
    order = 10,
    title = "#",
    title_small = "#",
    pct = 0.06,
    pct_small = 0.07,
    min_w = 52,
    min_w_small = 36,
    icon = "deathstats_icon_trophy.png",
    tooltip = S("Leaderboard Rank: Ranked by current life combat and survival"),
    get_value = function(_p, item)
        return string.format("%d", item.rank or 0)
    end,
})

deathstats.register_scoreboard_column("player", {
    order = 20,
    title = S("PLAYER"),
    title_small = S("NAME"),
    pct = 0.24,
    pct_small = 0.23,
    min_w = 144,
    min_w_small = 63,
    icon = "deathstats_icon_player.png",
    tooltip = S("Player Name & Status (Skull = Dead, Zzz = AFK)"),
    get_value = function(_p, item, is_small)
        local tag = ""
        if item.is_dead then
            tag = is_small and "[D] " or "[DEAD] "
        elseif item.is_afk then
            tag = is_small and "[A] " or "[AFK] "
        end
        local max_len = is_small and 12 or 22
        local name = item.name or ""
        local full_str = tag .. name
        if #full_str > max_len then
            full_str = full_str:sub(1, max_len - 1) .. "."
        end
        return full_str
    end,
})

deathstats.register_scoreboard_column("kills", {
    order = 30,
    title = S("KILLS"),
    title_small = S("K"),
    pct = 0.14,
    pct_small = 0.14,
    min_w = 70,
    min_w_small = 38,
    icon = "deathstats_icon_sword.png",
    tooltip = S("Total Kills (Current Life): [PvP Players / PvE Mobs]"),
    get_value = function(_p, item, is_small)
        local pvp = item.pvp_kills or 0
        local pve = item.pve_kills or 0
        if is_small then
            return string.format("%d/%d", pvp, pve)
        else
            return string.format("%d / %d", pvp, pve)
        end
    end,
})

deathstats.register_scoreboard_column("damage", {
    order = 40,
    title = S("DMG"),
    title_small = S("DMG"),
    pct = 0.09,
    pct_small = 0.10,
    min_w = 55,
    min_w_small = 32,
    icon = "deathstats_icon_target.png",
    tooltip = S("Total Damage Dealt (Current Life)"),
    get_value = function(_p, item)
        return string.format("%d", math.min(999999, item.damage_dealt or 0))
    end,
})

deathstats.register_scoreboard_column("mined", {
    order = 50,
    title = S("MINED"),
    title_small = S("MINE"),
    pct = 0.09,
    pct_small = 0.10,
    min_w = 55,
    min_w_small = 32,
    icon = "deathstats_icon_pickaxe.png",
    tooltip = S("Total Nodes Mined (Current Life)"),
    get_value = function(_p, item)
        return string.format("%d", math.min(999999, item.blocks_mined or 0))
    end,
})

deathstats.register_scoreboard_column("time", {
    order = 60,
    title = S("TIME"),
    title_small = S("TIME"),
    pct = 0.11,
    pct_small = 0.11,
    min_w = 68,
    min_w_small = 36,
    icon = "deathstats_icon_clock.png",
    tooltip = S("Active Survival Time (Current Life)"),
    get_value = function(_p, item, is_small)
        return deathstats.format_survival_time(item.time_alive, is_small)
    end,
})

deathstats.register_scoreboard_column("armor", {
    order = 70,
    title = S("ARM"),
    title_small = S("ARM"),
    pct = 0.08,
    pct_small = 0.08,
    min_w = 50,
    min_w_small = 28,
    icon = "deathstats_icon_shield.png",
    tooltip = S("Current Armor Defense Rating"),
    get_value = function(_p, item)
        return string.format("%d", math.min(999, item.armor or 0))
    end,
})

deathstats.register_scoreboard_column("hp", {
    order = 80,
    title = S("HP"),
    title_small = S("HP"),
    pct = 0.08,
    pct_small = 0.07,
    min_w = 50,
    min_w_small = 26,
    icon = "deathstats_icon_heart.png",
    tooltip = S("Current Health Points"),
    get_value = function(_p, item)
        return string.format("%d", math.min(999, item.hp or 0))
    end,
})

deathstats.register_scoreboard_column("ping", {
    order = 90,
    title = S("PING"),
    title_small = S("PING"),
    pct = 0.11,
    pct_small = 0.10,
    min_w = 68,
    min_w_small = 36,
    icon = "deathstats_icon_ping.png",
    tooltip = S("Network Latency: Round-trip ping to server in milliseconds"),
    get_value = function(_p, item)
        return string.format("%dms", math.min(9999, item.ping or 0))
    end,
    get_color = function(_p, item)
        return deathstats.get_ping_color(item.ping)
    end,
})

-- ==========================================
-- Score Calculation & Leaderboard Ranking
-- ==========================================

--- Calculate an aggregate performance score across all categories for ranking
--- Combines Kills, K/D Ratio, Survival (deaths factor), Damage Dealt, Armor, and HP
---@param pdata table Player statistics data table (containing lifetime counters)
---@param player ObjectRef|nil Active player object reference
---@param cached_armor integer|nil Optional pre-computed armor points
---@param cached_hp integer|nil Optional pre-computed health points
---@return integer score Composite score for descending leaderboard sort
---@return integer avg_category_score Normalized average rating across all categories (0-100)
function deathstats.calculate_player_score(pdata, player, cached_armor, cached_hp)
    local life = (pdata and pdata.lifetime) or {}
    local kills = (life.players_killed or 0)
    local deaths = (life.deaths or 0)
    local kd = (deaths > 0) and (kills / deaths) or (kills > 0 and kills or 0.0)
    local armor = cached_armor or deathstats.get_player_armor_points(player)
    local hp = cached_hp or deathstats.get_player_hp(player)
    local dmg_dealt = life.damage_dealt or 0

    -- 1. Normalized Category Ratings (0 to 100)
    local cat_kills = math.min(100, kills * 10)
    local cat_kd = math.min(100, math.floor(kd * 25))
    local cat_survival = (deaths == 0) and (kills > 0 and 100 or 60)
        or math.max(0, math.min(100, math.floor(100 / (1.0 + deaths * 0.1))))
    local cat_vitality = math.min(100, math.floor((armor * 0.5) + (hp * 2.5)))
    local cat_damage = math.min(100, math.floor(dmg_dealt / 10))

    -- Average score across all 5 categories
    local avg_category_score = math.floor((cat_kills + cat_kd + cat_survival + cat_vitality + cat_damage) / 5 + 0.5)

    -- Composite total score for fine-grained tie breaking
    local composite_score = (kills * 100)
        + math.floor(kd * 50)
        + (armor * 2)
        + hp
        + math.floor(dmg_dealt * 0.1)
        - (deaths * 15)

    composite_score = math.max(0, composite_score)
    return composite_score, avg_category_score
end

--- Gather and rank scoreboard entries for all connected players on their current life
--- Data reflects the active life run and resets whenever the player dies
--- Query, rank, and format scoreboard entries for all connected players
--- Accepts an optional precomputed base list to eliminate redundant queries when multiple players update in the same frame
---@param viewer_player ObjectRef|nil The player viewing the board
---@param precomputed_base table|nil Optional pre-gathered and pre-sorted player base entries
---@return table entries Sorted list of player entry tables
---@return table base_list Canonical base entry list (for same-frame reuse across viewers)
function deathstats.get_scoreboard_data(viewer_player, precomputed_base)
    local viewer_name = viewer_player and viewer_player:is_player() and viewer_player:get_player_name() or ""

    local base_list = precomputed_base
    if not base_list then
        base_list = {}
        local players = core.get_connected_players()
        for _, player in ipairs(players) do
            local name = player:get_player_name()
            local data = deathstats.get_player_data(player)
            local run = (data and data.current_run) or {}
            local pvp_kills = run.players_killed or 0
            local pve_kills = run.mobs_killed or 0
            local total_kills = pvp_kills + pve_kills
            local dmg_dealt = run.damage_dealt or 0
            local blocks_mined = run.blocks_mined or 0

            local is_dead = deathstats.is_player_dead(player)
            local is_afk = deathstats.is_player_afk(player)
            local time_alive
            if is_dead then
                time_alive = (data and data.last_life and data.last_life.time_alive) or 0
            else
                local start_t = (data and data.life_start_time) or core.get_gametime()
                time_alive = math.max(0, core.get_gametime() - start_t)
            end

            local armor = deathstats.get_player_armor_points(player)
            local hp = is_dead and 0 or deathstats.get_player_hp(player)
            local ping = deathstats.get_player_ping(name)
            local comp_score, avg_score = deathstats.calculate_player_score(data, player, armor, hp)

            table.insert(base_list, {
                name = name,
                is_viewer = false,
                is_real = true,
                is_dead = is_dead,
                is_afk = is_afk,
                pvp_kills = pvp_kills,
                pve_kills = pve_kills,
                kills = total_kills,
                damage_dealt = dmg_dealt,
                blocks_mined = blocks_mined,
                time_alive = time_alive,
                armor = armor,
                hp = hp,
                ping = ping,
                score = comp_score,
                avg_score = avg_score,
                deaths = (data and data.lifetime and data.lifetime.deaths) or 0,
                kd = (run.deaths and run.deaths > 0) and (total_kills / run.deaths) or total_kills,
            })
        end

        -- Leaderboard sorting:
        -- 1. Living players rank above dead players
        -- 2. PvP kills (descending)
        -- 3. PvE mob kills (descending)
        -- 4. Damage dealt (descending)
        -- 5. Nodes mined (descending)
        -- 6. Survival time (descending)
        -- 7. Name (alphabetical)
        table.sort(base_list, function(a, b)
            if a.is_dead ~= b.is_dead then
                return not a.is_dead
            elseif a.kills ~= b.kills then
                return a.kills > b.kills
            elseif a.pvp_kills ~= b.pvp_kills then
                return a.pvp_kills > b.pvp_kills
            elseif a.damage_dealt ~= b.damage_dealt then
                return a.damage_dealt > b.damage_dealt
            elseif a.blocks_mined ~= b.blocks_mined then
                return a.blocks_mined > b.blocks_mined
            elseif a.time_alive ~= b.time_alive then
                return a.time_alive > b.time_alive
            else
                return a.name < b.name
            end
        end)

        -- Assign rank positions
        for rank, item in ipairs(base_list) do
            item.rank = rank
        end
    end

    -- Construct viewer-specific list (shallow-copying only the viewer entry to set is_viewer = true)
    local entries = {}
    for i, item in ipairs(base_list) do
        if item.name == viewer_name then
            local viewer_entry = {}
            for k, v in pairs(item) do viewer_entry[k] = v end
            viewer_entry.is_viewer = true
            entries[i] = viewer_entry
        else
            entries[i] = item
        end
    end

    return entries, base_list
end

-- ==========================================
-- Screen Size, Line Metrics & Responsiveness
-- ==========================================

--- Get player window size and display scaling parameters safely
---@param player ObjectRef|nil Target player
---@return integer screen_w Screen width in pixels (default 1280)
---@return integer screen_h Screen height in pixels (default 720)
---@return number hud_scaling Client HUD scaling factor
function deathstats.get_player_window_size(player)
    local screen_w = 1280
    local screen_h = 720
    local hud_scaling = 1.0

    if player and player:is_player() then
        local name = player:get_player_name()
        local info = core.get_player_window_information and core.get_player_window_information(name)
        if info then
            if info.size and info.size.x and info.size.x > 0 then
                screen_w = info.size.x
            end
            if info.size and info.size.y and info.size.y > 0 then
                screen_h = info.size.y
            end
            if info.real_hud_scaling and info.real_hud_scaling > 0 then
                hud_scaling = info.real_hud_scaling
            end
        end
    end

    return screen_w, screen_h, hud_scaling
end


--- Compute column layout specifications spanning the full usable width of the scoreboard plaque
--- Pulls dynamically from registered columns and normalizes relative widths
---@param board_w integer Total plaque width in pixels
---@param is_small boolean Whether small-screen condensed mode is active
---@param hud_scale number Active HUD scaling factor
---@return table columns Ordered array of column definitions
---@return integer pad_x Left/right padding in pixels
---@return integer usable_w Usable table width in pixels
function deathstats.get_scoreboard_columns(board_w, is_small, hud_scale)
    hud_scale = hud_scale or 1.0
    local pad_x = is_small and 12 or 20
    local usable_w = math.max(100, board_w - (pad_x * 2))
    local icon_size = math.min(16, math.max(12, math.floor(14 * hud_scale)))

    local reg_cols = deathstats.get_ordered_scoreboard_columns()
    local total_pct = 0
    for _, col in ipairs(reg_cols) do
        local raw_pct = is_small and (col.pct_small or col.pct) or col.pct
        total_pct = total_pct + (raw_pct or 0.10)
    end
    if total_pct <= 0 then total_pct = 1.0 end

    local columns = {}
    local current_x = pad_x
    for i, def in ipairs(reg_cols) do
        local raw_pct = is_small and (def.pct_small or def.pct) or def.pct
        local norm_pct = (raw_pct or 0.10) / total_pct
        local min_w = is_small and (def.min_w_small or def.min_w) or def.min_w or 30

        local col_w = math.floor(usable_w * norm_pct)
        if i == #reg_cols then
            col_w = math.max(min_w, (board_w - pad_x) - current_x)
        else
            col_w = math.max(min_w, col_w)
        end

        local title = is_small and (def.title_small or def.title) or def.title
        local col_entry = {
            id = def.id,
            title = title,
            icon = def.icon,
            icon_size = icon_size,
            tooltip = def.tooltip,
            get_value = def.get_value,
            get_color = def.get_color,
            x = current_x,
            data_x = current_x + icon_size + 5,
            width = col_w,
        }
        table.insert(columns, col_entry)
        current_x = current_x + col_w
    end

    return columns, pad_x, usable_w
end

--- Calculate responsive dimensions, line heights, and max fitting rows inspired by waysigns
---@param player ObjectRef|nil Target player
---@return table metrics Layout metrics table
function deathstats.calculate_scoreboard_metrics(player)
    local screen_w, screen_h, hud_scaling = deathstats.get_player_window_size(player)

    -- Effective HUD scale proportional to display resolution (baseline 1080p)
    local hud_scale = math.min(1.4, math.max(0.75, (screen_h / 1080) * 1.15))
    if hud_scaling and hud_scaling > 0 and hud_scaling ~= 1.0 then
        hud_scale = hud_scale * math.min(1.2, math.max(0.8, hud_scaling))
    end

    -- Font and row line metrics
    local font_h = math.max(14, math.floor(15 * hud_scale + 0.5))
    local line_gap = (screen_h <= 600) and 4 or ((screen_h <= 768) and 5 or math.max(6, math.floor(7 * (screen_h / 1080) + 0.5)))
    local row_height = font_h + line_gap

    -- Vertical layout budgets
    local header_h = math.max(34, math.floor(38 * hud_scale))
    local col_header_h = math.max(24, math.floor(26 * hud_scale))
    local footer_h = math.max(26, math.floor(28 * hud_scale))
    local padding_v = math.max(8, math.floor(10 * hud_scale))

    -- Board plaque dimensions: take full width comfortably while leaving sleek padding from window edge
    local is_small = (screen_w < 780)
    local board_w
    if is_small then
        board_w = math.max(320, math.min(screen_w - 40, 680))
    else
        board_w = math.min(1080, math.max(760, screen_w - 48))
    end
    local board_h = math.floor(math.min(screen_h * 0.74, 620 * hud_scale))
    board_h = math.max(260, math.min(screen_h - 40, board_h))

    local columns, pad_x, usable_w = deathstats.get_scoreboard_columns(board_w, is_small, hud_scale)

    local available_h = board_h - header_h - col_header_h - footer_h - (padding_v * 2)
    local max_rows = math.max(1, math.floor(available_h / row_height))

    return {
        screen_w = screen_w,
        screen_h = screen_h,
        hud_scale = hud_scale,
        hud_scaling = hud_scaling,
        board_w = board_w,
        board_h = board_h,
        font_h = font_h,
        line_gap = line_gap,
        row_height = row_height,
        header_h = header_h,
        col_header_h = col_header_h,
        footer_h = footer_h,
        padding_v = padding_v,
        max_rows = max_rows,
        is_small = is_small,
        columns = columns,
        pad_x = pad_x,
        usable_w = usable_w,
    }
end

-- ==========================================
-- Scoreboard Background Plaque Texture
-- ==========================================

--- Escape special characters (^, :, \) inside sub-texture modifiers for use in [combine]
---@param tex_str string The raw texture or modifier string
---@return string escaped_str The escaped texture string
local function escape_combine_texture(tex_str)
    return (tex_str:gsub("\\", "\\\\"):gsub(":", "\\:"):gsub("%^", "\\^"))
end

--- Generate a composite texture string for the tactical scoreboard plaque
--- Combines dark translucent panel, glowing border, header divider, column header strip, table grid, icons, and status indicators
---@param m table Metrics table from calculate_scoreboard_metrics
---@param viewer_row_idx integer|nil 1-based index of the viewer's row within visible rows
---@param _entries table|nil Visible player entry tables for row status icons
---@return string texture Composite Luanti texture spec
function deathstats.get_scoreboard_bg_texture(m, viewer_row_idx, _entries)
    local w = m.board_w
    local h = m.board_h
    local scale_key = math.floor((m.hud_scale or 1.0) * 100)
    local cache_key = string.format("%d_%d_%s_%d_%d",
        w, h, tostring(m.is_small), scale_key, viewer_row_idx or 0)

    if deathstats.scoreboard_bg_cache and deathstats.scoreboard_bg_cache[cache_key] then
        return deathstats.scoreboard_bg_cache[cache_key]
    end

    local function combine_fill(x, y, fw, fh, color)
        return string.format(":%d,%d=%s", x, y, escape_combine_texture(string.format("[fill:%dx%d:%s", fw, fh, color)))
    end

    -- Header separator line
    local hdr_sep_y = m.header_h
    local col_sep_y = m.header_h + m.col_header_h
    local foot_sep_y = h - m.footer_h

    local parts = {
        "[combine:", w, "x", h,
        -- Base panel: dark translucent tactical card (#12121af0)
        combine_fill(0, 0, w, h, "#12121af0"),
        -- Top crimson accent strip (3px)
        combine_fill(0, 0, w, 3, "#ff4444dd"),
        -- Bottom subtle border line (1px)
        combine_fill(0, h - 1, w, 1, "#99111166"),
        -- Header divider line (1px)
        combine_fill(0, hdr_sep_y, w, 1, "#3a3a4caa"),
        -- Column header divider line (1px)
        combine_fill(0, col_sep_y, w, 1, "#ff444455"),
        -- Footer divider line (1px)
        combine_fill(0, foot_sep_y, w, 1, "#3a3a4caa"),
    }

    -- Subtle vertical column divider lines between table columns
    if m.columns then
        for i = 2, #m.columns do
            local col = m.columns[i]
            local sep_x = col.x - 4
            table.insert(parts, combine_fill(sep_x, hdr_sep_y, 1, foot_sep_y - hdr_sep_y, "#3a3a4c44"))
        end
    end

    -- Optional highlighted background strip behind viewer's row
    if viewer_row_idx and viewer_row_idx >= 1 and viewer_row_idx <= m.max_rows then
        local row_top = col_sep_y + m.padding_v + (viewer_row_idx - 1) * m.row_height
        table.insert(parts, combine_fill(4, row_top, w - 8, m.row_height, "#88181844"))
        table.insert(parts, combine_fill(4, row_top, 3, m.row_height, "#ff4444"))
    end

    -- Embed Infographic Icons into Column Header bar at exact column X coordinates
    if m.columns and #m.columns > 0 then
        local icon_y = hdr_sep_y + math.floor((m.col_header_h - m.columns[1].icon_size) / 2)
        for _, col in ipairs(m.columns) do
            local isz = col.icon_size
            local raw_icon = string.format("%s^[resize:%dx%d", col.icon, isz, isz)
            local escaped_icon = escape_combine_texture(raw_icon)
            table.insert(parts, string.format(":%d,%d=%s", col.x, icon_y, escaped_icon))
        end
    end

    local tex = table.concat(parts)
    if deathstats.scoreboard_bg_cache then
        deathstats.scoreboard_bg_cache[cache_key] = tex
    end
    return tex
end

-- ==========================================
-- Text Formatting & Column Alignment
-- ==========================================

--- Build monospaced column header string
--- If screen is small, collapses to condensed format matching icons
---@param m table Metrics table
---@return string col_header_str Formatted header text
function deathstats.format_column_headers(m)
    if m.is_small then
        return string.format("  %-2s  %-12s  %-5s  %-4s  %-4s  %-4s  %-3s  %-3s  %-5s",
            "#", "NAME", "K", "DMG", "MINE", "TIME", "ARM", "HP", "PING")
    else
        return string.format("   %-3s   %-22s   %-7s   %-6s   %-6s   %-6s   %-4s   %-3s   %-6s",
            "#", "PLAYER", "KILLS", "DMG", "MINED", "TIME", "ARM", "HP", "PING")
    end
end

--- Format a single player row into perfectly aligned monospaced columns
--- All columns have bounded value widths to guarantee fixed total character length
--- All data cells are left-aligned directly underneath the column headers
---@param item table Player scoreboard entry
---@param m table Metrics table
---@return string row_str Formatted row string
function deathstats.format_player_row(item, m)
    if m.is_small then
        local name_len = 12
        local display_name = item.name or ""
        if #display_name > name_len then
            display_name = display_name:sub(1, name_len - 1) .. "."
        end
        local k_str = string.format("%-5s", string.format("%d/%d", item.pvp_kills or 0, item.pve_kills or 0))
        local dmg_str = string.format("%-4d", math.min(9999, item.damage_dealt or 0))
        local mine_str = string.format("%-4d", math.min(9999, item.blocks_mined or 0))
        local time_str = string.format("%-4s", deathstats.format_survival_time(item.time_alive, true))
        local arm_str = string.format("%-3d", math.min(999, item.armor or 0))
        local hp_str = string.format("%-3d", math.min(99, item.hp or 0))
        local ping_str = string.format("%-5s", string.format("%dms", math.min(9999, item.ping or 0)))

        return string.format("  %-2d  %-12s  %s  %s  %s  %s  %s  %s  %s",
            math.min(99, item.rank or 0), display_name, k_str, dmg_str, mine_str, time_str, arm_str, hp_str, ping_str)
    else
        local name_len = 22
        local display_name = item.name or ""
        if #display_name > name_len then
            display_name = display_name:sub(1, name_len - 1) .. "."
        end
        local k_str = string.format("%-7s", string.format("%d / %d", item.pvp_kills or 0, item.pve_kills or 0))
        local dmg_str = string.format("%-6d", math.min(999999, item.damage_dealt or 0))
        local mine_str = string.format("%-6d", math.min(999999, item.blocks_mined or 0))
        local time_str = string.format("%-6s", deathstats.format_survival_time(item.time_alive, false))
        local arm_str = string.format("%-4d", math.min(9999, item.armor or 0))
        local hp_str = string.format("%-3d", math.min(999, item.hp or 0))
        local ping_str = string.format("%-6s", string.format("%dms", math.min(9999, item.ping or 0)))

        return string.format("   %-3d   %-22s   %s   %s   %s   %s   %s   %s   %s",
            math.min(999, item.rank or 0), display_name, k_str, dmg_str, mine_str, time_str, arm_str, hp_str, ping_str)
    end
end

--- Get formatted cell strings for all columns of a player row
--- Iterates over m.columns and invokes each column's get_value callback
---@param item table Player scoreboard entry
---@param m table Metrics table
---@return table cells Array of cell strings
function deathstats.get_player_row_cells(item, m)
    local cells = {}
    if m.columns then
        for _, col in ipairs(m.columns) do
            local val
            if col.get_value then
                val = col.get_value(nil, item, m.is_small) or ""
            else
                val = tostring(item[col.id] or "")
            end
            table.insert(cells, val)
        end
    end
    return cells
end

-- ==========================================
-- HUD Overlay Lifecycle (Show, Update, Hide)
-- ==========================================

--- Determine HUD text color for a scoreboard cell based on column config or player state
---@param col table Column definition
---@param player ObjectRef Target viewer player
---@param item table Row player entry data
---@param row_idx integer 1-based row index
---@return integer color HUD numeric color
function deathstats.get_scoreboard_cell_color(col, player, item, row_idx)
    local cell_color = col.get_color and col.get_color(player, item)
    if cell_color then
        return cell_color
    end
    if item.is_dead then
        return deathstats.colors.hud_dead
    elseif item.is_afk then
        return deathstats.colors.hud_afk
    elseif item.is_viewer then
        return deathstats.colors.hud_gold
    elseif (row_idx % 2 == 0) then
        return deathstats.colors.hud_soft_white
    else
        return deathstats.colors.hud_white
    end
end

--- Generate footer hint string for the live scoreboard HUD overlay
---@param total_count integer Total connected / mock player count
---@param visible_count integer Count of players currently displayed in HUD
---@return string footer_str Formatted footer text
function deathstats.get_scoreboard_footer_text(total_count, visible_count)
    local hidden_players = total_count - visible_count
    if hidden_players > 0 then
        return string.format(" (+%d more players)  •  Use /deathstats scores for full table", hidden_players)
    else
        local key = (deathstats.config.scoreboard_key or "sneak_aux1"):gsub("_", "+"):upper()
        return " Hold [" .. key .. "] to view  •  Use /deathstats scores for full table"
    end
end

--- Display or initialize the 2D HUD Scoreboard overlay for a player
--- Centered at position={x=0.5, y=0.5} with z_index=1000 and monospaced style=1
---@param player ObjectRef The player holding the activation key
---@param precomputed_entries table|nil Optional pre-calculated scoreboard entries
function deathstats.show_scoreboard_hud(player, precomputed_entries)
    if not player or not player:is_player() then return end
    if not deathstats.config.enable_scoreboard then return end
    if deathstats.is_player_dead(player) then return end
    local name = player:get_player_name()

    -- Capture original chat visibility flag and suppress chat while HUD overlay is open
    local existing_state = deathstats.active_scoreboard_huds[name] or deathstats.scoreboard_states[name]
    local prev_chat = existing_state and existing_state.prev_chat_flag
    if prev_chat == nil then
        local flags = player:hud_get_flags()
        if flags and flags.chat ~= nil then
            prev_chat = flags.chat
        else
            prev_chat = true
        end
    end

    -- Clean up any existing scoreboard HUD elements first (keeping chat suppressed)
    deathstats.hide_scoreboard_hud(player, true)

    local metrics = deathstats.calculate_scoreboard_metrics(player)
    local entries = precomputed_entries or deathstats.get_scoreboard_data(player)
    local time_str = deathstats.get_gametime_formatted()

    -- Find viewer's visible row index
    local viewer_row_idx = nil
    for i = 1, math.min(#entries, metrics.max_rows) do
        if entries[i].is_viewer then
            viewer_row_idx = i
            break
        end
    end

    local bg_tex = deathstats.get_scoreboard_bg_texture(metrics, viewer_row_idx, entries)
    local state = {
        metrics = metrics,
        bg_tex = bg_tex,
        viewer_row_idx = viewer_row_idx,
        time_str = time_str,
        prev_chat_flag = prev_chat,
        line_ids = {},
        col_header_ids = {},
        cell_ids = {},
        last_cells = {},
        last_colors = {},
        last_title = nil,
        last_footer = nil,
        update_timer = 0,
    }

    -- Suppress chat on client while scoreboard overlay is held open
    if deathstats.config.scoreboard_suppress_chat ~= false and prev_chat then
        player:hud_set_flags({ chat = false })
    end

    -- 1. Backdrop Plaque (image HUD element)
    state.hud_bg = player:hud_add({
        type = "image",
        position = { x = 0.5, y = 0.5 },
        alignment = { x = 0, y = 0 },
        offset = { x = 0, y = 0 },
        scale = { x = 1, y = 1 },
        text = bg_tex,
        z_index = 1000,
    })

    -- 2. Header Title & Time Text
    -- Offset calculated relative to plaque center (0, 0)
    local top_offset = -math.floor(metrics.board_h / 2)
    local left_offset = -math.floor(metrics.board_w / 2)
    local header_y = top_offset + math.floor(metrics.header_h / 2)
    local title_str = string.format(" DEATHSTATS // SCOREBOARD   •   %s   •   %d %s",
        time_str, #entries, (#entries == 1 and S("PLAYER") or S("PLAYERS")))

    state.hud_title = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.5 },
        alignment = { x = 0, y = 0 },
        offset = { x = 0, y = header_y },
        text = title_str,
        number = deathstats.colors.hud_gold,
        style = 1,
        z_index = 1005,
    })
    state.last_title = title_str

    -- 3. Column Header Titles (Left-aligned at each column data_x)
    local col_hdr_y = top_offset + metrics.header_h + math.floor(metrics.col_header_h / 2)

    for _, c in ipairs(metrics.columns) do
        local hid = player:hud_add({
            type = "text",
            position = { x = 0.5, y = 0.5 },
            alignment = { x = 1, y = 0 },
            offset = { x = left_offset + c.data_x, y = col_hdr_y },
            text = c.title,
            number = deathstats.colors.hud_soft_white,
            style = 1,
            z_index = 1005,
        })
        table.insert(state.col_header_ids, hid)
    end
    state.hud_col_header = state.col_header_ids[1]

    -- 4. Player Rows (Table grid cells left-aligned at each column data_x)
    local rows_start_y = top_offset + metrics.header_h + metrics.col_header_h + metrics.padding_v
    local visible_count = math.min(#entries, metrics.max_rows)

    for i = 1, visible_count do
        local item = entries[i]
        local row_y = rows_start_y + (i - 1) * metrics.row_height + math.floor(metrics.row_height / 2)
        local cells = deathstats.get_player_row_cells(item, metrics)

        state.cell_ids[i] = {}
        state.last_cells[i] = {}
        state.last_colors[i] = {}
        for col_idx, c in ipairs(metrics.columns) do
            local cell_color = deathstats.get_scoreboard_cell_color(c, player, item, i)
            local cell_text = cells[col_idx] or ""

            local cid = player:hud_add({
                type = "text",
                position = { x = 0.5, y = 0.5 },
                alignment = { x = 1, y = 0 },
                offset = { x = left_offset + c.data_x, y = row_y },
                text = cell_text,
                number = cell_color,
                style = 1,
                z_index = 1005,
            })
            table.insert(state.cell_ids[i], cid)
            state.last_cells[i][col_idx] = cell_text
            state.last_colors[i][col_idx] = cell_color
            table.insert(state.line_ids, cid)
        end
    end

    -- 5. Footer Info Text
    local footer_y = math.floor(metrics.board_h / 2) - math.floor(metrics.footer_h / 2)
    local footer_str = deathstats.get_scoreboard_footer_text(#entries, visible_count)

    state.hud_footer = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.5 },
        alignment = { x = 0, y = 0 },
        offset = { x = 0, y = footer_y },
        text = footer_str,
        number = deathstats.colors.hud_muted,
        style = 1,
        z_index = 1005,
    })
    state.last_footer = footer_str

    deathstats.active_scoreboard_huds[name] = state
    deathstats.scoreboard_states[name] = state
end

--- Update existing scoreboard HUD overlay elements with live changes (diff-based)
--- Only changes fields that modified (time, stats, ping) to eliminate network lag
---@param player ObjectRef Target player
---@param precomputed_entries table|nil Optional pre-calculated scoreboard entries
function deathstats.update_scoreboard_hud(player, precomputed_entries)
    if not player or not player:is_player() then return end
    if deathstats.is_player_dead(player) then
        deathstats.hide_scoreboard_hud(player)
        return
    end
    local name = player:get_player_name()
    local state = deathstats.active_scoreboard_huds[name]
    if not state then return end

    local screen_w, screen_h, hud_scaling = deathstats.get_player_window_size(player)
    if not state.metrics or state.metrics.screen_w ~= screen_w
            or state.metrics.screen_h ~= screen_h
            or state.metrics.hud_scaling ~= hud_scaling then
        deathstats.show_scoreboard_hud(player, precomputed_entries)
        return
    end
    local metrics = state.metrics

    local entries = precomputed_entries or deathstats.get_scoreboard_data(player)
    local time_str = deathstats.get_gametime_formatted()
    local visible_count = math.min(#entries, metrics.max_rows)

    -- Check if visible player row count changed
    if state.cell_ids and #state.cell_ids ~= visible_count then
        deathstats.show_scoreboard_hud(player, entries)
        return
    end

    -- Update Title if time or player count changed
    local title_str = string.format(" DEATHSTATS // SCOREBOARD   •   %s   •   %d %s",
        time_str, #entries, (#entries == 1 and S("PLAYER") or S("PLAYERS")))
    if state.hud_title and state.last_title ~= title_str then
        player:hud_change(state.hud_title, "text", title_str)
        state.last_title = title_str
    end

    -- Check if viewer's row rank or visible player statuses changed, updating background plaque from cache
    local viewer_row_idx = nil
    for i = 1, visible_count do
        if entries[i].is_viewer then
            viewer_row_idx = i
            break
        end
    end

    local new_bg = deathstats.get_scoreboard_bg_texture(metrics, viewer_row_idx, entries)
    if new_bg ~= state.bg_tex then
        state.viewer_row_idx = viewer_row_idx
        state.bg_tex = new_bg
        if state.hud_bg then
            player:hud_change(state.hud_bg, "text", new_bg)
        end
    end

    -- Update visible rows (diff-based: only call hud_change on modified text or color)
    for i = 1, visible_count do
        local item = entries[i]
        local cells = deathstats.get_player_row_cells(item, metrics)
        local row_cell_ids = state.cell_ids and state.cell_ids[i]
        if row_cell_ids then
            for col_idx = 1, #metrics.columns do
                local c = metrics.columns[col_idx]
                local cid = row_cell_ids[col_idx]
                if cid and c then
                    local cell_text = cells[col_idx] or ""
                    local cell_color = deathstats.get_scoreboard_cell_color(c, player, item, i)

                    if not state.last_cells or not state.last_cells[i] or state.last_cells[i][col_idx] ~= cell_text then
                        player:hud_change(cid, "text", cell_text)
                        if not state.last_cells then state.last_cells = {} end
                        if not state.last_cells[i] then state.last_cells[i] = {} end
                        state.last_cells[i][col_idx] = cell_text
                    end

                    if not state.last_colors or not state.last_colors[i] or state.last_colors[i][col_idx] ~= cell_color then
                        player:hud_change(cid, "number", cell_color)
                        if not state.last_colors then state.last_colors = {} end
                        if not state.last_colors[i] then state.last_colors[i] = {} end
                        state.last_colors[i][col_idx] = cell_color
                    end
                end
            end
        end
    end

    -- Update footer text if player count changed
    local footer_str = deathstats.get_scoreboard_footer_text(#entries, visible_count)
    if state.hud_footer and state.last_footer ~= footer_str then
        player:hud_change(state.hud_footer, "text", footer_str)
        state.last_footer = footer_str
    end
end

--- Hide and remove all active scoreboard HUD elements for a player
---@param player ObjectRef|string Target player object or player name
---@param keep_chat_state boolean|nil If true, keeps chat state untouched (e.g. during immediate re-show)
function deathstats.hide_scoreboard_hud(player, keep_chat_state)
    if not player then return end
    local name = (type(player) == "string") and player or (player.get_player_name and player:get_player_name())
    if not name or name == "" then return end

    local state = deathstats.active_scoreboard_huds[name] or deathstats.scoreboard_states[name]
    if not state then
        deathstats.active_scoreboard_huds[name] = nil
        deathstats.scoreboard_states[name] = nil
        return
    end

    local p = (type(player) ~= "string") and player or core.get_player_by_name(name)
    if p then
        if state.hud_bg then p:hud_remove(state.hud_bg) end
        if state.hud_title then p:hud_remove(state.hud_title) end
        if state.col_header_ids then
            for _, cid in ipairs(state.col_header_ids) do
                p:hud_remove(cid)
            end
        elseif state.hud_col_header then
            p:hud_remove(state.hud_col_header)
        end
        if state.hud_footer then p:hud_remove(state.hud_footer) end

        if state.line_ids then
            for _, lid in ipairs(state.line_ids) do
                p:hud_remove(lid)
            end
        end

        -- Restore chat visibility if previously suppressed by scoreboard HUD
        if not keep_chat_state and state.prev_chat_flag ~= nil then
            p:hud_set_flags({ chat = state.prev_chat_flag })
        end
    end

    deathstats.active_scoreboard_huds[name] = nil
    deathstats.scoreboard_states[name] = nil
end

-- ==========================================
-- Key Press Detection & Globalstep Loop
-- ==========================================

--- Determine if the player is currently holding the scoreboard activation key/combination
--- Pre-parsed key combination cache for zero-overhead globalstep checks
local cached_key_parts = {}

--- Retrieve pre-parsed list of lowercase control keys for a combination setting
---@param key_setting string|nil Configured key combination string (e.g. "zoom", "sneak+aux1")
---@return table keys Array of string key names
local function get_scoreboard_key_parts(key_setting)
    key_setting = key_setting or deathstats.config.scoreboard_key or "sneak_aux1"
    local parts = cached_key_parts[key_setting]
    if not parts then
        parts = {}
        for part in key_setting:gmatch("[^%+_%-]+") do
            local key = part:match("^%s*(.-)%s*$"):lower()
            if key ~= "" then
                table.insert(parts, key)
            end
        end
        cached_key_parts[key_setting] = parts
    end
    return parts
end

--- Determine if the player is currently holding the scoreboard activation key/combination
--- Supports "zoom", "sneak+aux1", "aux1", "sneak", or custom combinations
---@param player ObjectRef Target player
---@param key_setting string|nil Optional key config string
---@param ctrl table|nil Optional pre-fetched player control table
---@return boolean is_down True if all configured keys are currently pressed
function deathstats.is_scoreboard_key_down(player, key_setting, ctrl)
    if not player or not player:is_player() then return false end
    ctrl = ctrl or player:get_player_control()
    if not ctrl then return false end

    local keys = get_scoreboard_key_parts(key_setting)
    if #keys == 0 then return false end

    for _, key in ipairs(keys) do
        if not ctrl[key] then
            return false
        end
    end

    return true
end

--- Check if player is performing active gameplay input (movement, jumping, attacking, interacting)
--- Excludes the hold-to-view scoreboard key so checking the scoreboard never resets AFK
---@param player ObjectRef Target player
---@param ctrl table|nil Optional pre-fetched player control table
---@return boolean is_active True if active gameplay controls are pressed
local function is_player_input_active(player, ctrl)
    if not player or not player:is_player() then
        return false
    end
    ctrl = ctrl or player:get_player_control()
    if not ctrl then return false end

    -- Core gameplay actions: movement, jumping, attacking, interacting
    if ctrl.up or ctrl.down or ctrl.left or ctrl.right or ctrl.jump or ctrl.dig or ctrl.place or ctrl.LMB or ctrl.RMB then
        return true
    end

    -- Check auxiliary keys only if they are not bound to the scoreboard HUD
    local sb_key = deathstats.config.scoreboard_key or "sneak_aux1"
    if ctrl.aux1 and not sb_key:find("aux1") then
        return true
    end
    if ctrl.sneak and not sb_key:find("sneak") then
        return true
    end

    return false
end

-- Scoreboard hold-key & AFK detection globalstep listener
local afk_check_timer = 0

core.register_globalstep(function(dtime)
    local players = core.get_connected_players()
    if #players == 0 then return end

    -- Fast-exit and cleanup if scoreboard feature is disabled
    if not deathstats.config.enable_scoreboard then
        if next(deathstats.scoreboard_states) then
            for name in pairs(deathstats.scoreboard_states) do
                deathstats.hide_scoreboard_hud(name)
            end
        end
        return
    end

    -- 1. Throttled AFK check interval (every 2.0s)
    afk_check_timer = afk_check_timer + dtime
    local do_afk_check = false
    if afk_check_timer >= 2.0 then
        afk_check_timer = 0
        do_afk_check = true
    end

    -- 2. Process connected players in a single unified pass
    local frame_base = nil
    for _, player in ipairs(players) do
        local name = player:get_player_name()
        local is_dead = deathstats.dead_players[name] or deathstats.is_player_dead(player)

        -- Throttled AFK tracking for living players
        local ctrl = nil
        if do_afk_check and not is_dead then
            ctrl = player:get_player_control()
            if is_player_input_active(player, ctrl) then
                deathstats.reset_player_activity(name)
            else
                local pos = player:get_pos()
                local last_pos = deathstats.player_last_pos[name]
                local moved = false
                if pos and last_pos then
                    local dx = pos.x - last_pos.x
                    local dy = pos.y - last_pos.y
                    local dz = pos.z - last_pos.z
                    if (dx * dx + dy * dy + dz * dz) > 0.05 then
                        moved = true
                    end
                end
                if pos then
                    if last_pos then
                        last_pos.x, last_pos.y, last_pos.z = pos.x, pos.y, pos.z
                    else
                        deathstats.player_last_pos[name] = { x = pos.x, y = pos.y, z = pos.z }
                    end
                end

                local pitch = player:get_look_vertical() or 0
                local yaw = player:get_look_horizontal() or 0
                local last_look = deathstats.player_last_look[name]
                local looked = false
                if last_look then
                    local dp = math.abs(pitch - last_look.pitch)
                    local dyaw = math.abs(yaw - last_look.yaw)
                    if dp > 0.06 or dyaw > 0.06 then
                        looked = true
                    end
                end
                if last_look then
                    last_look.pitch, last_look.yaw = pitch, yaw
                else
                    deathstats.player_last_look[name] = { pitch = pitch, yaw = yaw }
                end

                if moved or looked then
                    deathstats.reset_player_activity(name)
                end
            end
        end

        -- Scoreboard hold-key listener (with same-frame base leaderboard reuse across concurrent viewers)
        if is_dead then
            if deathstats.scoreboard_states[name] then
                deathstats.hide_scoreboard_hud(player)
            end
        else
            local is_held = deathstats.is_scoreboard_key_down(player, nil, ctrl)
            local state = deathstats.scoreboard_states[name]

            if is_held then
                if not state then
                    local entries
                    entries, frame_base = deathstats.get_scoreboard_data(player, frame_base)
                    deathstats.show_scoreboard_hud(player, entries)
                else
                    state.update_timer = (state.update_timer or 0) + dtime
                    local interval = deathstats.config.scoreboard_update_interval or 1.0
                    if state.update_timer >= interval then
                        state.update_timer = 0
                        local entries
                        entries, frame_base = deathstats.get_scoreboard_data(player, frame_base)
                        deathstats.update_scoreboard_hud(player, entries)
                    end
                end
            elseif state then
                deathstats.hide_scoreboard_hud(player)
            end
        end
    end
end)

-- Activity event hooks for zero-overhead AFK tracking
core.register_on_chat_message(function(name, message)
    if message and (message:sub(1, 7) == "/scores" or message:sub(1, 11) == "/deathstats" or message:sub(1, 11) == "/mockscores") then
        return
    end
    deathstats.reset_player_activity(name)
end)

core.register_on_punchnode(function(_pos, _node, puncher)
    deathstats.reset_player_activity(puncher)
end)

core.register_on_dignode(function(_pos, _oldnode, digger)
    deathstats.reset_player_activity(digger)
end)

core.register_on_placenode(function(_pos, _newnode, placer)
    deathstats.reset_player_activity(placer)
end)

core.register_on_craft(function(_itemstack, player)
    deathstats.reset_player_activity(player)
end)

core.register_on_joinplayer(function(player)
    deathstats.reset_player_activity(player)
    if player and player:is_player() then
        local name = player:get_player_name()
        if name and name ~= "" then
            deathstats.left_players[name] = nil
            local pos = player:get_pos()
            if pos then
                deathstats.player_last_pos[name] = { x = pos.x, y = pos.y, z = pos.z }
            end
        end
        -- Reset / ensure clean scoreboard and chat HUD state on join
        deathstats.hide_scoreboard_hud(player)
        if deathstats.config.scoreboard_suppress_chat ~= false then
            player:hud_set_flags({ chat = true })
        end
    end
end)

-- Clean up on player disconnect
core.register_on_leaveplayer(function(player)
    deathstats.hide_scoreboard_hud(player)
    local name = player:get_player_name()
    deathstats.open_scoreboard_formspecs[name] = nil
    deathstats.last_activity[name] = nil
    deathstats.player_last_pos[name] = nil
    deathstats.player_last_look[name] = nil
end)

-- Clean up on player death (close scoreboard HUD and formspec)
core.register_on_dieplayer(function(player)
    deathstats.hide_scoreboard_hud(player)
    deathstats.close_scoreboard_formspec(player)
end)

-- Clean up on player respawn
core.register_on_respawnplayer(function(player)
    deathstats.hide_scoreboard_hud(player)
end)

-- Clean up on server shutdown (restore chat flags and hide scoreboard HUDs)
core.register_on_shutdown(function()
    local to_hide = {}
    for name in pairs(deathstats.active_scoreboard_huds) do
        to_hide[name] = true
    end
    for name in pairs(deathstats.scoreboard_states) do
        to_hide[name] = true
    end
    for name in pairs(to_hide) do
        deathstats.hide_scoreboard_hud(name)
    end
    for _, player in ipairs(core.get_connected_players()) do
        deathstats.hide_scoreboard_hud(player)
    end
end)

-- ==========================================
-- Scrollable Formspec Scoreboard Dialog
-- ==========================================

--- Display the full scrollable formspec scoreboard table with all players
---@param player ObjectRef Target player
function deathstats.show_scoreboard_formspec(player)
    if not player or not player:is_player() then return end
    deathstats.hide_scoreboard_hud(player)
    local name = player:get_player_name()
    if not deathstats.config.enable_scoreboard then
        core.chat_send_player(name, S("Scoreboard feature is currently disabled."))
        return
    end
    if deathstats.is_player_dead(player) then
        core.chat_send_player(name, S("You cannot view the scoreboard while dead."))
        return
    end
    local entries = deathstats.get_scoreboard_data(player)
    local time_str = deathstats.get_gametime_formatted()
    local c = deathstats.colors

    local row_h = 0.52
    local total_rows = #entries

    local reg_cols = deathstats.get_ordered_scoreboard_columns()
    local total_pct = 0
    for _, col in ipairs(reg_cols) do
        total_pct = total_pct + (col.pct or 0.10)
    end
    if total_pct <= 0 then total_pct = 1.0 end

    local usable_fs_w = 13.8
    local fs_cols = {}
    local curr_x = 0.5
    for i, col in ipairs(reg_cols) do
        local norm_pct = (col.pct or 0.10) / total_pct
        local col_w = norm_pct * usable_fs_w
        if i == #reg_cols then
            col_w = (0.5 + usable_fs_w) - curr_x
        end
        table.insert(fs_cols, {
            id = col.id,
            title = col.title,
            icon = col.icon,
            tooltip = col.tooltip,
            get_value = col.get_value,
            get_color = col.get_color,
            x = curr_x,
            w = col_w,
        })
        curr_x = curr_x + col_w
    end

    local fs = {
        "formspec_version[6]",
        "size[15.2,8.6]",
        "position[0.5,0.5]",
        "anchor[0.5,0.5]",
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Outer Card Panel
        "box[0.3,0.3;14.6,8.0;" .. c.card_modal .. "]",
        "box[0.3,0.3;14.6,0.06;" .. c.crimson_border .. "]",
        "box[0.3,8.24;14.6,0.06;" .. c.crimson_border .. "]",

        -- Header Bar
        "image[0.6,0.48;0.45,0.45;deathstats_icon_trophy.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[1.2,0.72;" .. F(S("DEATHSTATS // MULTIPLAYER SCOREBOARD")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_muted),
        "label[8.2,0.72;" .. F(S("In-Game Time: @1", time_str)) .. "]",
        "label[12.2,0.72;" .. F(S("@1 Connected", total_rows)) .. "]",

        -- Column Header Strip
        "box[0.5,1.15;14.2,0.55;" .. c.tab_bar_bg .. "]",
        "box[0.5,1.70;14.2,0.04;" .. c.tab_bar_sep .. "]",
    }

    -- Column Header Tooltips, Icons, and Titles
    for _, col in ipairs(fs_cols) do
        if col.tooltip and col.tooltip ~= "" then
            table.insert(fs, string.format("tooltip[%.2f,1.15;%.2f,0.55;%s]", col.x, col.w, F(col.tooltip)))
        end
        table.insert(fs, string.format("image[%.2f,1.25;0.35,0.35;%s]", col.x + 0.05, col.icon))
        table.insert(fs, string.format("label[%.2f,1.48;%s]", col.x + 0.45, F(col.title)))
    end

    -- Scrollable Container for All Players
    table.insert(fs, string.format("scrollbaroptions[max=%d]", math.max(0, math.ceil((total_rows * row_h - 5.8) / 0.1))))
    table.insert(fs, "scrollbar[14.5,1.85;0.3,5.8;vertical;sb_scroll;0]")
    table.insert(fs, "scroll_container[0.5,1.85;13.9,5.8;sb_scroll;vertical;0.1]")

    -- Player rows inside scroll container
    local last_fs_textcolor = nil
    for i, item in ipairs(entries) do
        local y = (i - 1) * row_h
        local row_bg = item.is_viewer and "#88181844" or ((i % 2 == 0) and c.card_panel or c.row_alt)
        table.insert(fs, string.format("box[0,%.2f;13.8,%.2f;%s]", y, row_h - 0.04, row_bg))

        if item.is_viewer then
            table.insert(fs, string.format("box[0,%.2f;0.08,%.2f;%s]", y, row_h - 0.04, c.crimson_glow))
        end

        local default_text_color = c.text_white
        if item.is_dead then
            default_text_color = c.text_dead
        elseif item.is_afk then
            default_text_color = c.text_afk
        elseif item.is_viewer then
            default_text_color = c.text_gold
        end

        for _, col in ipairs(fs_cols) do
            local rel_x = col.x - 0.5
            local cell_text_color = default_text_color
            if col.id == "ping" then
                cell_text_color = deathstats.get_ping_textcolor(item.ping)
            end

            if cell_text_color ~= last_fs_textcolor then
                table.insert(fs, string.format("style_type[label;textcolor=%s]", cell_text_color))
                last_fs_textcolor = cell_text_color
            end

            if col.id == "player" or col.id == "name" then
                if item.is_dead then
                    table.insert(fs, string.format("image[%.2f,%.2f;0.32,0.32;deathstats_icon_skull.png]", rel_x + 0.05, y + 0.08))
                elseif item.is_afk then
                    table.insert(fs, string.format("image[%.2f,%.2f;0.32,0.32;deathstats_icon_afk.png]", rel_x + 0.05, y + 0.08))
                end
                table.insert(fs, string.format("label[%.2f,%.2f;%s]", rel_x + 0.42, y + 0.26, F(item.name or "")))
            else
                local val
                if col.get_value then
                    val = col.get_value(nil, item, false) or ""
                else
                    val = tostring(item[col.id] or "")
                end
                table.insert(fs, string.format("label[%.2f,%.2f;%s]", rel_x + 0.08, y + 0.26, F(val)))
            end
        end
    end

    table.insert(fs, "scroll_container_end[]")

    -- Footer bar with controls
    table.insert(fs, "box[0.5,7.75;14.2,0.45;" .. c.tab_bar_bg .. "]")
    table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_muted))
    local sb_key_hint = (deathstats.config.scoreboard_key or "sneak_aux1"):gsub("_", "+"):upper()
    table.insert(fs, "label[0.7,7.98;" .. F(S("Tip: Hold [@1] during gameplay for HUD quick-view", sb_key_hint)) .. "]")

    -- Close Button
    table.insert(fs, string.format("style[btn_close_scoreboard;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s]",
        c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border))
    table.insert(fs, "button_exit[12.8,7.78;1.8,0.42;btn_close_scoreboard;" .. F(S("Close")) .. "]")

    core.show_formspec(name, "deathstats:scoreboard", table.concat(fs))
    deathstats.open_scoreboard_formspecs[name] = true
end

--- Close the full scoreboard formspec for a player
---@param player ObjectRef Target player
function deathstats.close_scoreboard_formspec(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    core.close_formspec(name, "deathstats:scoreboard")
    deathstats.open_scoreboard_formspecs[name] = nil
end

-- Register formspec receive fields handler for scoreboard
core.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "deathstats:scoreboard" then
        if fields.btn_close_scoreboard or fields.quit then
            deathstats.close_scoreboard_formspec(player)
            return true
        end
    end
end)

-- ==========================================
-- Chat Command: /deathstats scores & /scores
-- ==========================================

core.register_chatcommand("deathstats", {
    params = S("[scores|scoreboard [on|off]|afk|mock|help]"),
    description = S("View deathstats options, lifetime records, and multiplayer scoreboard"),
    func = function(name, param)
        param = (param or ""):match("^%s*(.-)%s*$"):lower()
        local player = core.get_player_by_name(name)
        if not player then return false end

        local sb_toggle = param:match("^scoreboard%s+(%a+)$")
        if sb_toggle then
            if not core.check_player_privs(name, { server = true }) then
                return false, S("You need the 'server' privilege to change scoreboard settings.")
            end
            if sb_toggle == "on" or sb_toggle == "true" or sb_toggle == "enable" then
                deathstats.config.enable_scoreboard = true
                return true, S("Scoreboard feature enabled.")
            elseif sb_toggle == "off" or sb_toggle == "false" or sb_toggle == "disable" then
                deathstats.config.enable_scoreboard = false
                for _, p in ipairs(core.get_connected_players()) do
                    deathstats.hide_scoreboard_hud(p)
                    local pname = p:get_player_name()
                    if deathstats.open_scoreboard_formspecs[pname] then
                        deathstats.close_scoreboard_formspec(p)
                    end
                end
                return true, S("Scoreboard feature disabled.")
            else
                return false, S("Invalid state. Use '/deathstats scoreboard on' or '/deathstats scoreboard off'.")
            end
        elseif param == "scores" or param == "score" or param == "scoreboard" or param == "top" or param == "" then
            if not deathstats.config.enable_scoreboard then
                return false, S("Scoreboard feature is currently disabled.")
            end
            if deathstats.is_player_dead(player) then
                return false, S("You cannot view the scoreboard while dead.")
            end
            -- Toggle scoreboard dialog on and off
            if deathstats.open_scoreboard_formspecs[name] then
                deathstats.close_scoreboard_formspec(player)
                return true, S("Scoreboard closed.")
            else
                deathstats.show_scoreboard_formspec(player)
                return true
            end
        elseif param == "mock" or param:find("^mock%s*") then
            local sub = param:match("^mock%s*(.*)$")
            local cmd = core.chatcommands["mockscores"]
            if not cmd then
                local modpath = deathstats.modpath or core.get_modpath("deathstats") or "."
                dofile(modpath .. "/mock_scoreboard.lua")
                cmd = core.chatcommands["mockscores"]
            end
            if cmd then
                return cmd.func(name, sub)
            end
            return true, S("Mock scoreboard loaded.")
        elseif param == "afk" or param:find("^afk%s*") then
            local sec_str = param:match("^afk%s*(%d+)$")
            if sec_str then
                local new_timeout = tonumber(sec_str)
                if new_timeout and new_timeout >= 1 then
                    deathstats.config.afk_timeout = new_timeout
                    return true, string.format("AFK timeout set to %d seconds.", new_timeout)
                end
            end
            local timeout = deathstats.config.afk_timeout or 120
            local last_act = deathstats.last_activity[name] or core.get_gametime()
            local idle_sec = math.max(0, core.get_gametime() - last_act)
            local is_afk = deathstats.is_player_afk(name)
            return true, string.format("AFK Timeout: %ds | Current idle time: %ds | Status: %s",
                timeout, idle_sec, is_afk and "AFK" or "ACTIVE")
        elseif param == "help" then
            return true, S("DeathStats Commands:\n/deathstats scores - Toggle full scoreboard\n/scores - Scoreboard shortcut\n/deathstats scoreboard [on|off] - Enable/disable scoreboard (server priv)\n/deathstats afk [seconds] - Check or set AFK timeout\n/deathstats mock [on|off|<count>] - Toggle testing mock players")
        else
            return false, S("Unknown subcommand. Use '/deathstats scores', '/scores', '/deathstats afk', or '/deathstats mock'.")
        end
    end,
})

core.register_chatcommand("scores", {
    description = S("Toggle multiplayer scoreboard table"),
    func = function(name)
        local player = core.get_player_by_name(name)
        if not player then return false end
        if not deathstats.config.enable_scoreboard then
            return false, S("Scoreboard feature is currently disabled.")
        end
        if deathstats.is_player_dead(player) then
            return false, S("You cannot view the scoreboard while dead.")
        end

        if deathstats.open_scoreboard_formspecs[name] then
            deathstats.close_scoreboard_formspec(player)
            return true, S("Scoreboard closed.")
        else
            deathstats.show_scoreboard_formspec(player)
            return true
        end
    end,
})

-- ==========================================
-- Optional Mock Scoreboard Data for Testing
-- ==========================================
-- To test the scoreboard with 17+ players in singleplayer, uncomment the line below:
-- dofile((deathstats.modpath or core.get_modpath("deathstats")) .. "/mock_scoreboard.lua")

