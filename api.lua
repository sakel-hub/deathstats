--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

---@class DeathStatsConfig
---@field enable_sounds boolean
---@field enable_camera boolean
---@field enable_animation boolean
---@field enable_limb_fractures boolean
---@field enable_fall_fractures boolean
---@field animation_duration number
---@field blood_splatter_opacity number
---@field formspec_side string
---@field banner_texture string
---@field orbit_radius number
---@field orbit_height number
---@field orbit_speed number
---@field enable_corpse_particles boolean
---@field enable_corpse_ragdoll boolean
---@field ragdoll_force_multiplier number
---@field ragdoll_max_velocity number
---@field ragdoll_tumbling boolean
---@field ragdoll_restitution number
---@field ragdoll_flail_rate number
---@field ragdoll_resting_poses boolean
---@field enable_corpse_impact_sounds boolean
---@field enable_slope_pitch boolean
---@field enable_scoreboard boolean
---@field scoreboard_key string
---@field time_format string
---@field scoreboard_update_interval number
---@field scoreboard_suppress_chat boolean
---@field afk_timeout number
---@field chat_death_coords boolean
---@field enable_corpse_inspect boolean
---@field enable_mvp_badges boolean
---@field enable_hall_of_fame boolean
---@field corpse_decay_time number
---@field enable_revenge boolean
---@field announce_revenge boolean

---@class DeathStatsColors
---@field transparent string
---@field card_sidebar string
---@field card_modal string
---@field card_panel string
---@field card_inset string
---@field row_alt string
---@field row_viewer string
---@field tab_bar_bg string
---@field tab_bar_sep string
---@field tooltip_bg string
---@field crimson_border string
---@field crimson_glow string
---@field active_strip string
---@field text_gold string
---@field text_crimson string
---@field text_white string
---@field text_muted string
---@field text_ping_good string
---@field text_ping_warn string
---@field text_ping_bad string
---@field text_dead string
---@field text_afk string
---@field btn_primary_bg string
---@field btn_primary_hover_bg string
---@field btn_primary_border string
---@field btn_primary_hover_border string
---@field btn_primary_text string
---@field btn_secondary_bg string
---@field btn_secondary_hover_bg string
---@field btn_secondary_border string
---@field btn_secondary_hover_border string
---@field btn_secondary_text string
---@field tab_active_bg string
---@field tab_active_hover_bg string
---@field tab_active_border string
---@field tab_active_hover_border string
---@field tab_active_text string
---@field tab_inactive_bg string
---@field tab_inactive_hover_bg string
---@field tab_inactive_border string
---@field tab_inactive_hover_border string
---@field tab_inactive_text string
---@field hud_white integer
---@field hud_soft_white integer
---@field hud_gold integer
---@field hud_crimson integer
---@field hud_muted integer
---@field hud_cyan integer
---@field hud_green integer
---@field hud_ping_good integer
---@field hud_ping_warn integer
---@field hud_ping_bad integer
---@field hud_dead integer
---@field hud_afk integer

---@class DeathStats
---@field modpath string
---@field storage StorageRef
---@field config DeathStatsConfig
---@field colors DeathStatsColors
---@field active_huds table<string, table<string, any>>
---@field active_animations table<string, table<string, any>>
---@field active_scoreboard_huds table<string, table<string, any>>
---@field scoreboard_states table<string, boolean>
---@field open_scoreboard_formspecs table<string, boolean>
---@field open_scoreboard_tabs table<string, string>
---@field scoreboard_bg_cache table<string, string>
---@field formatted_name_cache table<string, string>
---@field node_tile_texture_cache table<string, string>
---@field registered_columns table<string, table<string, any>>
---@field last_activity table<string, number>
---@field player_last_pos table<string, Vector>
---@field player_last_look table<string, number>
---@field dead_players table<string, boolean>
---@field player_camera_data table<string, table<string, any>>
---@field is_respawning table<string, boolean>
---@field players table<string, table<string, any>>
---@field recent_punches table<string, table<string, any>>
---@field recent_falls table<string, number>
---@field recent_starvations table<string, number>
---@field recent_dehydrations table<string, number>
---@field last_blow table<string, table<string, any>>
---@field last_death_reason table<string, table<string, any>>
---@field respawn_immunity table<string, boolean>
---@field left_players table<string, boolean>
---@field player_corpses table<string, table<string, any>>
---@field is_shutting_down boolean
---@field compat_hunger table<string, any>
---@field compat_skins table<string, any>
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
    player_corpses = {},
    is_shutting_down = false,
    compat_hunger = {},
    compat_skins = {},
}

core.register_on_shutdown(function()
    deathstats.is_shutting_down = true
end)

-- Load modular component subsystems in topological order
local modpath = deathstats.modpath

dofile(modpath .. "/src/utils.lua")
dofile(modpath .. "/src/analysis.lua")
dofile(modpath .. "/src/storage.lua")
dofile(modpath .. "/src/physics.lua")
dofile(modpath .. "/src/particles.lua")
dofile(modpath .. "/src/corpse.lua")
dofile(modpath .. "/src/camera.lua")
dofile(modpath .. "/src/hud.lua")
dofile(modpath .. "/src/formspecs.lua")
