--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

---@class DeathStatsConfig
---@field enable_sounds boolean Enable death sound effects and cinematic musical cues
---@field enable_camera boolean Enable smooth third-person cinematic camera orbit around corpse
---@field enable_animation boolean Enable cinematic HUD animations (blood splatter, death banner slap)
---@field enable_limb_fractures boolean Enable limb displacement and disarticulation ragdoll physics
---@field enable_fall_fractures boolean Enable severe limb fracture effects from high fall velocity impacts
---@field animation_duration number Duration in seconds of the death screen animation sequence
---@field blood_splatter_opacity number Opacity factor for blood splatter HUD vignette (0.0 to 1.0)
---@field formspec_side string Screen dock side for stats dossier ("left" or "right")
---@field banner_texture string Texture overlay file used for the cinematic "YOU DIED" banner
---@field orbit_radius number Distance in blocks from orbit center to death camera
---@field orbit_height number Vertical elevation offset in blocks above corpse for camera orbit
---@field orbit_speed number Orbital rotation speed in radians per second
---@field enable_corpse_particles boolean Enable ambient atmospheric death particles (flies, smoke, bubbles)
---@field enable_corpse_ragdoll boolean Enable physical ragdoll entity spawn with trajectory and bone tumbling
---@field ragdoll_force_multiplier number Knockback impulse scaling multiplier applied to ragdoll corpse
---@field ragdoll_max_velocity number Maximum allowed initial launch velocity clamp in blocks/second
---@field ragdoll_tumbling boolean Enable rotational tumbling physics during ragdoll flight
---@field ragdoll_restitution number Bounciness elasticity coefficient for terrain collisions (0.0 to 1.0)
---@field ragdoll_flail_rate number Limb twitching and flailing oscillation frequency in Hertz
---@field ragdoll_resting_poses boolean Enable contextual resting poses (prone, supine, slumped, folded)
---@field enable_corpse_impact_sounds boolean Enable bone cracking and terrain impact collision audio
---@field enable_slope_pitch boolean Enable raycast terrain slope inclination alignment for corpses
---@field enable_scoreboard boolean Enable live tactical scoreboard overlay HUD
---@field scoreboard_key string Keybinding name used to toggle the live scoreboard HUD
---@field time_format string Time display formatting mode ("dhms", "hms", or "seconds")
---@field scoreboard_update_interval number Refresh interval in seconds between scoreboard HUD updates
---@field scoreboard_suppress_chat boolean Automatically suppress background chat messages when scoreboard is open
---@field afk_timeout number Idle duration in seconds before flagging player as AFK
---@field chat_death_coords boolean Broadcast precise XYZ death coordinates in chat upon player death
---@field enable_corpse_inspect boolean Enable right-click inspection dossier dialog for settled corpses
---@field enable_mvp_badges boolean Display MVP ribbons and achievement badges on scoreboard entries
---@field enable_hall_of_fame boolean Enable Hall of Fame leaderboard tab on full scoreboard formspec
---@field corpse_decay_time number Lifespan duration in seconds before settled corpses dissolve
---@field enable_revenge boolean Track and highlight killer vendettas with revenge indicators
---@field announce_revenge boolean Broadcast server-wide announcement when a player avenges their death

---@class DeathStatsColors
---@field transparent string Hex color string for fully transparent elements
---@field card_sidebar string Hex color string for sidebar card background
---@field card_modal string Hex color string for modal dialog background
---@field card_panel string Hex color string for statistics panel background
---@field card_inset string Hex color string for inset sub-panels
---@field row_alt string Hex color string for alternating table row striping
---@field row_viewer string Hex color string highlighting the viewer player row
---@field tab_bar_bg string Hex color string for tab navigation bar background
---@field tab_bar_sep string Hex color string for tab separator dividers
---@field tooltip_bg string Hex color string for tooltip dialog backgrounds
---@field crimson_border string Hex color string for crimson accent borders
---@field crimson_glow string Hex color string for crimson glowing highlights
---@field active_strip string Hex color string for active navigation indicators
---@field text_gold string Hex color string for gold stat labels and headers
---@field text_crimson string Hex color string for crimson danger and death text
---@field text_white string Hex color string for standard white text
---@field text_muted string Hex color string for dimmed or secondary text
---@field text_ping_good string Hex color string for optimal network latency ping
---@field text_ping_warn string Hex color string for moderate network latency ping
---@field text_ping_bad string Hex color string for high network latency ping
---@field text_dead string Hex color string for deceased player status text
---@field text_afk string Hex color string for away-from-keyboard status text
---@field btn_primary_bg string Hex color string for primary action button background
---@field btn_primary_hover_bg string Hex color string for hovered primary button background
---@field btn_primary_border string Hex color string for primary button border
---@field btn_primary_hover_border string Hex color string for hovered primary button border
---@field btn_primary_text string Hex color string for primary button label text
---@field btn_secondary_bg string Hex color string for secondary button background
---@field btn_secondary_hover_bg string Hex color string for hovered secondary button background
---@field btn_secondary_border string Hex color string for secondary button border
---@field btn_secondary_hover_border string Hex color string for hovered secondary button border
---@field btn_secondary_text string Hex color string for secondary button label text
---@field tab_active_bg string Hex color string for active tab background
---@field tab_active_hover_bg string Hex color string for hovered active tab background
---@field tab_active_border string Hex color string for active tab border
---@field tab_active_hover_border string Hex color string for hovered active tab border
---@field tab_active_text string Hex color string for active tab label text
---@field tab_inactive_bg string Hex color string for inactive tab background
---@field tab_inactive_hover_bg string Hex color string for hovered inactive tab background
---@field tab_inactive_border string Hex color string for inactive tab border
---@field tab_inactive_hover_border string Hex color string for hovered inactive tab border
---@field tab_inactive_text string Hex color string for inactive tab label text
---@field hud_white integer Numeric hex color (0xRRGGBB) for white HUD text
---@field hud_soft_white integer Numeric hex color (0xRRGGBB) for soft-white HUD text
---@field hud_gold integer Numeric hex color (0xRRGGBB) for golden HUD highlights
---@field hud_crimson integer Numeric hex color (0xRRGGBB) for crimson HUD warnings
---@field hud_muted integer Numeric hex color (0xRRGGBB) for dimmed HUD elements
---@field hud_cyan integer Numeric hex color (0xRRGGBB) for cyan tactical metrics
---@field hud_green integer Numeric hex color (0xRRGGBB) for green status indicators
---@field hud_ping_good integer Numeric hex color (0xRRGGBB) for low ping latency
---@field hud_ping_warn integer Numeric hex color (0xRRGGBB) for moderate ping latency
---@field hud_ping_bad integer Numeric hex color (0xRRGGBB) for high ping latency
---@field hud_dead integer Numeric hex color (0xRRGGBB) for deceased status HUD indicators
---@field hud_afk integer Numeric hex color (0xRRGGBB) for AFK status HUD indicators

---@class DeathInfo
---@field category string Broad category of death (e.g. "pvp", "mob", "fall", "drown", "lava", "fire", "starve", "suffocation", "explosion", "void")
---@field reason_text string Human-readable death description
---@field weapon string? Weapon or projectile name that dealt the fatal blow
---@field killer_name string? Name of killer player, mob entity, or hazard
---@field killer_health number? Remaining health of killer at moment of death
---@field funny_note string? Humorous epitaph quotation
---@field depth_desc string? Descriptive depth label (e.g. "Deep Underground", "Sky High")
---@field biome_name string? Biome identifier at death location
---@field pos Vector? Position vector where death occurred
---@field custom_message string? Optional custom death notification message

---@class PlayerLifetimeStats
---@field time_alive number Total seconds survived in this life
---@field blocks_mined number Total blocks dug/mined
---@field total_ores number Total rare ores extracted
---@field damage_dealt number Total damage inflicted on players and mobs
---@field damage_taken number Total damage received
---@field mobs_killed number Total monsters and hostile mobs slain
---@field items_crafted number Total items crafted
---@field deaths number Total deaths recorded
---@field pvp_kills number Total opposing players slain
---@field distance_traveled number Total horizontal meters traversed
---@field last_cause string? Cause of last death
---@field last_category string? Category of last death
---@field last_killer string? Killer name of last death
---@field last_weapon string? Weapon used in last death
---@field last_funny string? Humorous note from last death
---@field last_coords string? Coordinate string of last death
---@field best_life table? Personal best achievement record

---@class PlayerVisuals
---@field mesh string 3D model filename (e.g. "character.b3d", "character.glb")
---@field textures string[] Array of texture string identifiers
---@field visual_size Vector Visual scale multiplier vector {x, y, z}
---@field yaw number Horizontal facing rotation in radians
---@field armor_dropped boolean Whether player armor was dropped on death
---@field inventory_dropped boolean Whether player inventory items were dropped on death
---@field wield_item string Wielded item name string

---@class ScoreboardColumnDef
---@field order number Sort order placement priority (e.g. 10 to 100)
---@field title string Header label text displayed on full scoreboard
---@field title_small string? Abbreviated header label displayed on compact HUD
---@field pct number Width proportion of total scoreboard width (0.0 to 1.0)
---@field min_w number Minimum column width in pixels
---@field icon string? Icon texture name displayed in column header
---@field tooltip string? Tooltip description shown on column hover
---@field get_value fun(player: ObjectRef, item: table, is_small: boolean): string Callback returning formatted cell value string
---@field get_color (fun(player: ObjectRef, item: table): integer)? Optional callback returning text color (0xRRGGBB)
---@field sort_key (fun(item: table): any)? Optional callback returning sortable primitive value

---@class ScoreboardEntry
---@field name string Player username
---@field kills number Lifetime PvP kills
---@field deaths number Lifetime deaths
---@field kd number Calculated kill-to-death ratio
---@field damage_dealt number Lifetime damage dealt
---@field blocks_mined number Lifetime blocks mined
---@field survival_time number Current life survival time in seconds
---@field armor number Total armor defense value
---@field hp number Current health points
---@field ping number Network ping latency in milliseconds
---@field is_afk boolean True if player is currently away-from-keyboard
---@field is_dead boolean True if player is currently deceased
---@field score number Tactical composite leaderboard score

---@class DeathStats
---@field modpath string Filesystem path to the deathstats mod root directory
---@field storage StorageRef Luanti persistent mod storage reference
---@field config DeathStatsConfig Active configuration settings table
---@field colors DeathStatsColors Central color palette and HUD theme constants
---@field active_huds table<string, table<string, any>> Map of player names to their active death screen HUD element IDs
---@field active_animations table<string, table<string, any>> Map of player names to running cinematic animation states
---@field active_scoreboard_huds table<string, table<string, any>> Map of player names to active live scoreboard HUD element IDs
---@field scoreboard_states table<string, boolean> Map of player names to live scoreboard visibility states (true = visible)
---@field open_scoreboard_formspecs table<string, boolean> Map of player names to full scoreboard formspec open states
---@field open_scoreboard_tabs table<string, string> Map of player names to active tab ID on full scoreboard formspec
---@field scoreboard_bg_cache table<string, string> Cached background formspec texture strings keyed by layout dimensions
---@field formatted_name_cache table<string, string> Cache of formatted item and mob display strings
---@field node_tile_texture_cache table<string, string> Cache of resolved node tile texture strings
---@field registered_columns table<string, table<string, any>> Registered custom scoreboard column definitions
---@field last_activity table<string, number> Timestamps of last recorded player interaction for AFK detection
---@field player_last_pos table<string, Vector> Last recorded positions of players for movement tracking
---@field player_last_look table<string, number> Last recorded horizontal view pitch/yaw for AFK tracking
---@field dead_players table<string, boolean> Set of player names currently deceased and viewing death screen
---@field player_camera_data table<string, table<string, any>> Camera orbit tracking data and original camera modes
---@field is_respawning table<string, boolean> Flags marking players currently in respawn transition
---@field players table<string, table<string, any>> In-memory cache of loaded player lifetime statistics
---@field recent_punches table<string, table<string, any>> Most recent combat punches received by player for killer attribution
---@field recent_falls table<string, number> Timestamps and peak elevations of recent falls for fatal fall analysis
---@field recent_starvations table<string, number> Timestamps of recent hunger starvation events
---@field recent_dehydrations table<string, number> Timestamps of recent thirst dehydration events
---@field last_blow table<string, table<string, any>> Recorded fatal blow attack metadata per player
---@field last_death_reason table<string, table<string, any>> Recorded death reason tables per player
---@field respawn_immunity table<string, boolean> Flags marking temporary post-respawn damage immunity
---@field left_players table<string, boolean> Flags tracking players who disconnected while deceased
---@field player_corpses table<string, table<string, any>> Active corpse entity references and visual tracking state
---@field is_shutting_down boolean True during server shutdown to suppress redundant cleanup logic
---@field compat_hunger table<string, any> Integration hooks for external hunger and stamina mods
---@field compat_skins table<string, any> Integration hooks for player appearance and custom skin mods
---@field compat_hudbars table<string, any>? Compatibility layer hooks for hudbars mod and extensions
---@field fall_peaks table<string, number> Highest recorded elevations during airborne falls for fatal fall distance tracking
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
    --- Server shutdown flag used to suppress redundant cleanup logic
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
