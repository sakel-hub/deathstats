# DeathStats API Reference

Cinematic death screen, ragdoll physics simulation, grave epitaphs, lifetime statistics tracking, and tactical live scoreboard for Luanti.

## Table of Contents

- [Classes & Data Structures](#classes--data-structures)
- [Type Aliases & Callbacks](#type-aliases--callbacks)
- [Core & Lifecycle API](#core--lifecycle-api)
- [Statistics & Storage API](#statistics--storage-api)
- [Death Analysis & Attribution API](#death-analysis--attribution-api)
- [Ragdoll & Terrain Physics API](#ragdoll--terrain-physics-api)
- [Corpse Entities & Visuals API](#corpse-entities--visuals-api)
- [Cinematic Camera Orbit API](#cinematic-camera-orbit-api)
- [Particle Effects API](#particle-effects-api)
- [Formspecs & UI Dossier API](#formspecs--ui-dossier-api)
- [Live Scoreboard HUD API](#live-scoreboard-hud-api)
- [Registries & State Tables](#registries--state-tables)

---

## Classes & Data Structures

### `DeathInfo`

| Field | Type | Description |
| :--- | :--- | :--- |
| `biome_name` | `string?` | Biome identifier at death location |
| `category` | `string` | Broad category of death (e.g. "pvp", "mob", "fall", "drown", "lava", "fire", "starve", "suffocation", "explosion", "void") |
| `custom_message` | `string?` | Optional custom death notification message |
| `depth_desc` | `string?` | Descriptive depth label (e.g. "Deep Underground", "Sky High") |
| `funny_note` | `string?` | Humorous epitaph quotation |
| `killer_health` | `number?` | Remaining health of killer at moment of death |
| `killer_name` | `string?` | Name of killer player, mob entity, or hazard |
| `pos` | `Vector?` | Position vector where death occurred |
| `reason_text` | `string` | Human-readable death description |
| `weapon` | `string?` | Weapon or projectile name that dealt the fatal blow |

### `DeathStats`

| Field | Type | Description |
| :--- | :--- | :--- |
| `active_animations` | `table<string, table<string, any>>` | Map of player names to running cinematic animation states |
| `active_huds` | `table<string, table<string, any>>` | Map of player names to their active death screen HUD element IDs |
| `active_scoreboard_huds` | `table<string, table<string, any>>` | Map of player names to active live scoreboard HUD element IDs |
| `aim_camera_at_bones` | `function deathstats.aim_camera_at_bones(player: ObjectRef, bones_pos: Vector)` |  Position and orient camera to point directly at the bones node, aligning the orbit center  @*param* `player` — The deceased player object  @*param* `bones_pos` — The 3D coordinates of the bones block |
| `analyze_death` | `function deathstats.analyze_death(player: ObjectRef, reason: table\|nil)
  -> analysis: table` |  Main Death Cause Analyzer: parses engine death reason metadata or invokes environmental inspection  @*param* `player` — The deceased player object  @*param* `reason` — The engine reason table from on_dieplayer or show_death_screen  @*return* `analysis` — The complete death metadata table (category, reason_text, killer_name, weapon, funny_note) |
| `analyze_death_raw` | `function deathstats.analyze_death_raw(player: ObjectRef, reason: table\|nil)
  -> analysis: table` |  Internal raw death cause analyzer  @*param* `player` — The deceased player object  @*param* `reason` — The engine reason table from on_dieplayer or show_death_screen  @*return* `analysis` — The un-enriched death metadata table |
| `apply_corpse_bounce_impact` | `function deathstats.apply_corpse_bounce_impact(corpse: ObjectRef, impact_vy: number, _rebound_v: Vector, _rot: table\|nil, bounce_count: number)` |  Apply immediate physical impact reaction to corpse limbs when colliding with ground during bounce  @*param* `corpse` — The corpse entity object  @*param* `impact_vy` — Downward velocity of the impact  @*param* `_rebound_v` — Resulting rebound velocity vector  @*param* `_rot` — Current rotation {x, y, z}  @*param* `bounce_count` — Current bounce index (1 or 2) |
| `calc_oriented_particle_bounds` | `function deathstats.calc_oriented_particle_bounds(rot: table\|nil, min_val: number, max_val: number, spread_h: number)
  -> min_v: table
  2. max_v: table` |  Calculates rotation-compensated particle emitter vectors for an attached entity.  Computes the local direction matching world +Y (straight up) so that particles  always rise upward in world space regardless of whether the corpse is prone, supine, or tilted.  @*param* `rot` — Rotation { x = pitch, y = yaw, z = roll } in radians  @*param* `min_val` — Minimum scalar magnitude (e.g. min vertical velocity or acceleration)  @*param* `max_val` — Maximum scalar magnitude (e.g. max vertical velocity or acceleration)  @*param* `spread_h` — Horizontal spread magnitude  @*return* `min_v` — Vector { x, y, z }  @*return* `max_v` — Vector { x, y, z } |
| `calculate_corpse_impulse` | `function deathstats.calculate_corpse_impulse(player: ObjectRef\|nil, death_info: table\|nil, last_blow: table\|nil)
  -> velocity: Vector
  2. rot_speed: Vector` |  Calculate initial 3D linear launch velocity and angular tumbling impulse for a ragdoll corpse  @*param* `player` — The deceased player  @*param* `death_info` — The death analysis table  @*param* `last_blow` — The recorded lethal blow data  @*return* `velocity` — Initial 3D velocity vector for the corpse  @*return* `rot_speed` — Initial angular tumbling velocity (pitch, yaw, roll) |
| `calculate_player_score` | `function deathstats.calculate_player_score(pdata: table, player: ObjectRef\|nil, cached_armor: integer\|nil, cached_hp: integer\|nil)
  -> score: integer
  2. avg_category_score: integer` |  Calculate an aggregate performance score across all categories for ranking  Combines Kills, K/D Ratio, Survival (deaths factor), Damage Dealt, Armor, and HP  @*param* `pdata` — Player statistics data table (containing lifetime counters)  @*param* `player` — Active player object reference  @*param* `cached_armor` — Optional pre-computed armor points  @*param* `cached_hp` — Optional pre-computed health points  @*return* `score` — Composite score for descending leaderboard sort  @*return* `avg_category_score` — Normalized average rating across all categories (0-100) |
| `calculate_scoreboard_metrics` | `function deathstats.calculate_scoreboard_metrics(player: ObjectRef\|nil)
  -> metrics: table` |  Calculate responsive dimensions, line heights, and max fitting rows inspired by waysigns  @*param* `player` — Target player  @*return* `metrics` — Layout metrics table |
| `calculate_slap_animation` | `function deathstats.calculate_slap_animation(progress: number, target_w: number\|nil, target_h: number\|nil)
  -> scale_x: number
  2. scale_y: number
  3. alpha: number
  4. impact_reached: boolean` |  Calculate distance flight and screen slap animation parameters  Uses an elastic damped sine curve trajectory for prominent zoom-in and bouncy recoil  @*param* `progress` — Animation progress factor from 0.0 to 1.0  @*param* `target_w` — Target scale X percentage (default -32.0)  @*param* `target_h` — Target scale Y percentage (default -23.0)  @*return* `scale_x` — Calculated X dimension scale  @*return* `scale_y` — Calculated Y dimension scale  @*return* `alpha` — Alpha transparency level (0-255)  @*return* `impact_reached` — True if animation reached or passed impact threshold |
| `cleanup_invalid_mobs_slain` | `function deathstats.cleanup_invalid_mobs_slain(data: table)
  -> table\|nil` |  Clean up non-mob entries (arrows, items, falling nodes, vehicles) from player stats  @*param* `data` — Player statistics data table |
| `clear_death_hud` | `function deathstats.clear_death_hud(player: ObjectRef)` |  Remove all active death HUD elements for a player  @*param* `player` — The player whose death HUD elements should be removed |
| `close_scoreboard_formspec` | `function deathstats.close_scoreboard_formspec(player: ObjectRef)` |  Close the full scoreboard formspec for a player  @*param* `player` — Target player |
| `colors` | `DeathStatsColors` | Central color palette and HUD theme constants |
| `compat_hudbars` | `table<string, any>?` | Compatibility layer hooks for hudbars mod and extensions |
| `compat_hunger` | `table<string, any>` | Integration hooks for external hunger and stamina mods |
| `compat_skins` | `table<string, any>` | Integration hooks for player appearance and custom skin mods |
| `config` | `DeathStatsConfig` | Active configuration settings table |
| `create_corpse_particlespawner_def` | `function deathstats.create_corpse_particlespawner_def(effect_type: string, corpse_pos: table, attached_obj: ObjectRef\|nil)
  -> def: table\|nil` |  Create a modern ParticleSpawner definition table with graceful fallback to older Luanti clients  @*param* `effect_type` — water  @*param* `corpse_pos` — The {x, y, z} position of the corpse  @*param* `attached_obj` — Optional corpse ObjectRef to attach particles to  @*return* `def` — ParticleSpawner definition table |
| `create_empty_stats` | `function deathstats.create_empty_stats()
  -> stats: table` |  Create an empty statistics table structure with default zeroed counters  @*return* `stats` — New statistics table containing metrics for mining, combat, crafting, and survival |
| `dead_players` | `table<string, boolean>` | Set of player names currently deceased and viewing death screen |
| `deserialize_inventory_list` | `function deathstats.deserialize_inventory_list(inv: InvRef, list_name: string, items: string[])` |  Deserialize an array of itemstrings back into an inventory list  @*param* `inv` — The inventory reference  @*param* `list_name` — The inventory list name  @*param* `items` — Array of itemstrings |
| `detect_corpse_slope_pitch` | `function deathstats.detect_corpse_slope_pitch(pos: Vector, yaw: number)
  -> pitch: number
  2. target_y: number
  3. ground_found: boolean` |  Detect terrain slope incline along the corpse spine axis using two downward raycasts (head and pelvis)  Returns the pitch angle in radians (matching right-handed Z-X-Y set_rotation) and adjusted contact elevation  @*param* `pos` — Center position of the corpse  @*param* `yaw` — Orientation yaw in radians  @*return* `pitch` — Pitch angle in radians (clamped to [-55°, +55°])  @*return* `target_y` — Adjusted ground midpoint elevation for the corpse  @*return* `ground_found` — True if valid walkable ground was probed under corpse |
| `detect_hanging_legs` | `function deathstats.detect_hanging_legs(pos: Vector, yaw: number)
  -> hanging: boolean` |  Detect if the corpse legs are hanging over an edge, cliff, or stair drop  @*param* `pos` — Center position of the corpse  @*param* `yaw` — Facing yaw of the corpse  @*return* `hanging` — True if pelvis is supported but legs extend over empty space |
| `detect_wall_behind` | `function deathstats.detect_wall_behind(pos: Vector, yaw: number)
  -> is_wall: boolean` |  Detect if there is a solid walkable wall or obstruction behind the corpse  @*param* `pos` — Position of the corpse  @*param* `yaw` — Facing yaw of the corpse in radians  @*return* `is_wall` — True if a solid node is detected behind |
| `dissolve_corpse` | `function deathstats.dissolve_corpse(corpse: ObjectRef\|nil)` |  Dissolve and cleanly remove a persistent corpse with dissipation particles  @*param* `corpse` — The corpse object reference |
| `enrich_death_info` | `function deathstats.enrich_death_info(res: table, player: ObjectRef, puncher: ObjectRef\|nil)
  -> enriched: table` |  Enrich death analysis table with coordinates, depth, biome, killer HP and fall metrics  @*param* `res` — Death analysis table  @*param* `player` — The player who died  @*param* `puncher` — Optional killer entity or puncher  @*return* `enriched` — The enriched death analysis table |
| `ensure_corpse_clearance` | `function deathstats.ensure_corpse_clearance(pos: table, yaw: number, is_wall_sitting: boolean)
  -> adjusted_pos: table` |  Ensures corpse position does not clip into solid walkable blocks or boundaries  Nudges wall-sitting corpses forward away from the wall behind them and resolves solid collisions  @*param* `pos` — The position vector of the corpse  @*param* `yaw` — Facing yaw of the corpse in radians  @*param* `is_wall_sitting` — True if pose is wall_sit or slouch  @*return* `adjusted_pos` — Vector position cleared of solid obstructions |
| `fall_peaks` | `table<string, number>` | Highest recorded elevations during airborne falls for fatal fall distance tracking |
| `find_ground_surface` | `function deathstats.find_ground_surface(pos: Vector, bones_pos: Vector\|nil, death_info: table\|nil)
  -> surface_y: number` |  Find the true ground collision surface level beneath a position  Ensures the corpse rests directly flush on walkable terrain, slabs, stairs, or bones  For liquid deaths (water, lava), prevents pinning to the lake bed and retains exact death position  @*param* `pos` — Player or death position  @*param* `bones_pos` — Coordinates of bones node if placed  @*param* `death_info` — Optional death analysis information  @*return* `surface_y` — The exact Y coordinate where corpse should rest |
| `find_player_bones` | `function deathstats.find_player_bones(player: ObjectRef, search_center: Vector\|nil)
  -> pos: Vector\|nil` |  Check if bones were placed for this player at or near death position  @*param* `player` — The deceased player object  @*param* `search_center` — Optional search origin (defaults to orbit_center or player pos)  @*return* `pos` — The 3D coordinates of the placed bones node, or nil if not found |
| `format_column_headers` | `function deathstats.format_column_headers(m: table)
  -> col_header_str: string` |  Build monospaced column header string  If screen is small, collapses to condensed format matching icons  @*param* `m` — Metrics table  @*return* `col_header_str` — Formatted header text |
| `format_compact_number` | `function deathstats.format_compact_number(n: number)
  -> The: string` |  Format numbers into compact strings (>= 1,000 -> 1k, >= 2,000 -> 2k, >= 10,000 -> 10k, >= 1,000,000 -> 1M)  @*param* `n` — The numeric value to format  @*return* `The` — compact formatted string (e.g. "1k", "10k", "2M") |
| `format_name` | `function deathstats.format_name(item_name: string)
  -> The: string` |  Convert an internal node name or item name into a clean, human-readable title  Retrieves clean description from registered item definition, or falls back to capitalized name  @*param* `item_name` — The raw registered technical item or node name (e.g. "default:stone_with_iron")  @*return* `The` — sanitized, capitalized human-readable title (e.g. "Iron Ore") |
| `format_number` | `function deathstats.format_number(n: number)
  -> The: string` |  Format large integer numbers with standard comma thousand separators (e.g. 1,234,567)  @*param* `n` — The raw numeric value to format  @*return* `The` — formatted number with comma separators |
| `format_player_row` | `function deathstats.format_player_row(item: table, m: table)
  -> row_str: string` |  Format a single player row into perfectly aligned monospaced columns  All columns have bounded value widths to guarantee fixed total character length  All data cells are left-aligned directly underneath the column headers  @*param* `item` — Player scoreboard entry  @*param* `m` — Metrics table  @*return* `row_str` — Formatted row string |
| `format_projectile_name` | `function deathstats.format_projectile_name(ent_name: string\|nil)
  -> The: string` |  Format a projectile entity name into a clean weapon display title  @*param* `ent_name` — The registered technical projectile entity name  @*return* `The` — human-readable weapon or projectile description |
| `format_survival_time` | `function deathstats.format_survival_time(sec: number, is_small: boolean\|nil)
  -> time_str: string` |  Format active survival duration into a compact human-readable string  @*param* `sec` — Duration in seconds  @*param* `is_small` — Whether to format for small display  @*return* `time_str` — Formatted time string (e.g. "45s", "14m 20s", "2h 10m") |
| `format_time` | `function deathstats.format_time(sec: number)
  -> The: string` |  Format a duration in seconds into a human-readable time string (e.g. "1d 2h 3m" or "45s")  @*param* `sec` — The total elapsed duration in seconds  @*return* `The` — formatted human-readable time string |
| `formatted_name_cache` | `table<string, string>` | Cache of formatted item and mob display strings |
| `fracture_corpse_limbs` | `function deathstats.fracture_corpse_limbs(corpse: ObjectRef, custom_angles: table<string, number>\|nil)
  -> applied_angles: table<string, number>` |  Programmatically rotate corpse limbs on fall death to simulate fractured / broken bones.  Rotates arms, legs, and head strictly along the horizontal floor plane (around local Z axis),  guaranteeing that limbs stay flush touching the ground without lifting into the air or clipping underground.  @*param* `corpse` — The corpse entity object  @*param* `custom_angles` — Optional map of bone names to z-axis rotation radians  @*return* `applied_angles` — Map of bone names to applied z radians |
| `funny_notes` | `table` |  Funny epitaph notes organized by death cause (all wrapped in S() for translation) |
| `get_banner_responsive_scale` | `function deathstats.get_banner_responsive_scale(player: table\|ObjectRef)
  -> scale_x: number
  2. scale_y: number` |  Calculate responsive banner scale maintaining exact texture aspect ratio across any screen resolution  @*param* `player` — The player object or mock window info  @*return* `scale_x,scale_y` — The calculated responsive horizontal and vertical scale |
| `get_biome_at_pos` | `function deathstats.get_biome_at_pos(pos: Vector\|nil)
  -> biome_name: string` |  Get biome name at a given 3D position  @*param* `pos` — The position to query  @*return* `biome_name` — Clean formatted biome name |
| `get_bones_mode` | `function deathstats.get_bones_mode()
  -> should_show_bones: boolean
  2. bones_mode: string
  3. has_bones_mod: boolean` |  Check if bones mod is active and configured to place/show bones  @*return* `should_show_bones` — True if bones mod is active and bones_mode == "bones"  @*return* `bones_mode` — The effective bones_mode setting ("bones", "drop", or "keep")  @*return* `has_bones_mod` — True if bones mod is loaded in the world |
| `get_camera_orbit_pos` | `function deathstats.get_camera_orbit_pos(center: Vector, radius: number, height: number, angle: number)
  -> cam_pos: Vector` |  Compute 3D camera eye coordinates along the orbit path around an orbit center  @*param* `center` — 3D coordinates of the orbit center (corpse or bones)  @*param* `radius` — Horizontal distance from center  @*param* `height` — Vertical elevation above center  @*param* `angle` — Orbit angle (yaw) in radians  @*return* `cam_pos` — 3D world position of the camera eye |
| `get_corpse` | `function deathstats.get_corpse(player_name: string)
  -> corpse: ObjectRef\|nil` |  Get the active corpse entity for a player name if currently spawned  @*return* `corpse` — The active corpse entity or nil |
| `get_corpse_effect_type` | `function deathstats.get_corpse_effect_type(corpse_pos: table, death_info: table\|nil)
  -> effect_type: string` |  Determine the appropriate particle effect for a corpse based on death cause and environment  @*param* `corpse_pos` — The {x, y, z} position of the corpse  @*param* `death_info` — Optional death analysis table  @*return* `effect_type` — water |
| `get_corpse_wielditem` | `function deathstats.get_corpse_wielditem(corpse: ObjectRef\|nil)
  -> went: ObjectRef\|nil` |  Get the attached wielditem entity from a corpse  @*param* `corpse` — The corpse entity object  @*return* `went` — The attached wielditem entity or nil |
| `get_depth_description` | `function deathstats.get_depth_description(y: number\|nil)
  -> depth_desc: string` |  Describe elevation/depth zone for the death location  @*param* `y` — The vertical elevation  @*return* `depth_desc` — Human-readable depth or altitude description |
| `get_fallback_ground_node` | `function deathstats.get_fallback_ground_node()
  -> node_name: string\|nil` |  Dynamically discover a representative ground node from core.registered_nodes using node groups  Completely mod-agnostic; avoids hardcoding any specific mod namespace like "default:"  @*return* `node_name` — Technical name of a registered walkable ground node |
| `get_funny_note` | `function deathstats.get_funny_note(category: string)
  -> note: string` |  Pick a random humorous epitaph note for the given death category  @*param* `category` — The death category identifier (e.g. "pvp", "mob", "fall", "lava", etc.)  @*return* `note` — A randomized witty or humorous epitaph quote |
| `get_gametime_formatted` | `function deathstats.get_gametime_formatted(format: string\|nil)
  -> time_str: string` |  Format the current in-game day/night cycle into a human-readable digital clock string  @*param* `format` — Optional format ("24h" or "12h"). Defaults to mod setting.  @*return* `time_str` — Formatted in-game time (e.g. "19:30" or "07:30 PM") |
| `get_hall_of_fame_data` | `function deathstats.get_hall_of_fame_data()
  -> list: table` |  Get the All-Time Hall of Fame players list sorted by lifetime composite score  @*return* `list` — Sorted list of all-time player dossiers |
| `get_last_death_info` | `function deathstats.get_last_death_info(player: string\|ObjectRef)
  -> last_info: table` |  Retrieve the fallback death reason and epitaph information for a player  @*param* `player` — The player object or player username  @*return* `last_info` — Formatted death info table { reason_text = string, funny_note = string, category = string } |
| `get_node_impact_sound` | `function deathstats.get_node_impact_sound(ndef: table\|nil)
  -> sound_name: string\|nil
  2. base_gain: number
  3. base_pitch: number` |  Extract an impact sound specification from a node definition table  Queries Luanti games and engine standard sound keys (dug, footstep, place, dig)  @*param* `ndef` — Node definition table |
| `get_node_tile_texture` | `function deathstats.get_node_tile_texture(node_name: string\|nil)
  -> texture: string` |  Get the primary tile texture name for a given node for particle fallback  @*param* `node_name` — Name of the node  @*return* `texture` — Name of the texture or fallback |
| `get_ordered_scoreboard_columns` | `function deathstats.get_ordered_scoreboard_columns()
  -> columns: table` |  Query active registered scoreboard columns sorted by their order attribute  @*return* `columns` — Sorted array of column definition tables |
| `get_ping_color` | `function deathstats.get_ping_color(ping: integer)
  -> color: integer` |  Evaluate color threshold for ping latency (numeric HUD RGB)  @*param* `ping` — Network round-trip latency in milliseconds  @*return* `color` — RGB color (green, yellow, or red) |
| `get_ping_textcolor` | `function deathstats.get_ping_textcolor(ping: integer)
  -> color_str: string` |  Evaluate formspec text color string for ping latency  @*param* `ping` — Network round-trip latency in milliseconds  @*return* `color_str` — Hex color string |
| `get_player_armor_points` | `function deathstats.get_player_armor_points(player: ObjectRef\|nil)
  -> points: integer` |  Query player armor defense points across all supported Luanti armor mods and engine groups  Supports 3d_armor (level), mcl_armor (armor_points), hbarmor, and engine fleshy group fallbacks  @*param* `player` — The player object to inspect  @*return* `points` — Total effective armor defense points (0-100+) |
| `get_player_data` | `function deathstats.get_player_data(player: ObjectRef)
  -> data: table\|nil` |  Get or initialize the active statistics data table for a player  @*param* `player` — The player object to retrieve data for  @*return* `data` — The active player statistics data table, or nil if player is invalid |
| `get_player_hp` | `function deathstats.get_player_hp(player: ObjectRef\|nil)
  -> hp: integer` |  Get current health points safely  @*param* `player` — The player object  @*return* `hp` — Current health points |
| `get_player_hydration` | `function deathstats.get_player_hydration(player: ObjectRef)
  -> current: number?
  2. max: number?
  3. ratio: number?
  4. source: string?
  5. is_dehydrated: boolean?` |  Get player current hydration and thirst stats across supported thirst mods  @*param* `player` — Luanti player object  @*return* `current` — Current thirst value  @*return* `max` — Maximum thirst value  @*return* `ratio` — Hydration ratio (0.0 - 1.0)  @*return* `source` — Identification of originating thirst mod  @*return* `is_dehydrated` — True if thirst value is critical (<= 1) |
| `get_player_ping` | `function deathstats.get_player_ping(player_name: string)
  -> ping: integer` |  Query round-trip network ping latency in milliseconds for a connected player  @*param* `player_name` — Username of the target player  @*return* `ping` — Latency in milliseconds (0 for local or unavailable) |
| `get_player_row_cells` | `function deathstats.get_player_row_cells(item: table, m: table)
  -> cells: table` |  Get formatted cell strings for all columns of a player row  Iterates over m.columns and invokes each column's get_value callback  @*param* `item` — Player scoreboard entry  @*param* `m` — Metrics table  @*return* `cells` — Array of cell strings |
| `get_player_satiation` | `function deathstats.get_player_satiation(player: ObjectRef)
  -> current: number?
  2. max: number?
  3. ratio: number?
  4. source: string?
  5. is_starving: boolean?` |  Get player current satiation and hunger stats across supported hunger mods  @*param* `player` — Luanti player object  @*return* `current` — Current hunger value  @*return* `max` — Maximum hunger value  @*return* `ratio` — Satiation ratio (0.0 - 1.0)  @*return* `source` — Identification of originating hunger mod  @*return* `is_starving` — True if hunger value is critical (<= 1) |
| `get_player_visuals` | `function deathstats.get_player_visuals(player: ObjectRef)
  -> visuals: PlayerVisuals` |  Extract player visual characteristics (mesh, textures, visual_size, yaw) across all skin mods  @*param* `player` — Luanti player object  @*return* `visuals` — Visual properties table |
| `get_player_wield_item` | `function deathstats.get_player_wield_item(player: ObjectRef)
  -> item_name: string` |  Extract the player's active wielded item name, ignoring internal camera hands  @*param* `player` — The player object  @*return* `item_name` — The item technical name (e.g. "default:sword_steel"), or "" if empty/hand |
| `get_player_window_size` | `function deathstats.get_player_window_size(player: ObjectRef\|nil)
  -> screen_w: integer
  2. screen_h: integer
  3. hud_scaling: number` |  Get player window size and display scaling parameters safely  @*param* `player` — Target player  @*return* `screen_w` — Screen width in pixels (default 1280)  @*return* `screen_h` — Screen height in pixels (default 720)  @*return* `hud_scaling` — Client HUD scaling factor |
| `get_pose_elevation_offset` | `function deathstats.get_pose_elevation_offset(pose_type: string\|nil)
  -> offset: number` |  Return the vertical position offset required to keep different resting poses  (supine, prone, lateral, wall_sit, slouch) resting flat on top of the ground.  In character.b3d lay animation (frame 166), the entity origin (0,0,0) is stationed  along the central torso plane.  Supine and prone both rest flat on the ground with zero vertical offset (0.0),  keeping the body (torso and legs) flush against the ground.  Lateral (roll = +/- pi/2) places the shoulder at -0.27, needing a +0.16 block offset.  Wall sit and slouch maintain upright origin contact (0.0).  @*param* `pose_type` — supine  @*return* `offset` — Vertical offset in nodes |
| `get_pose_selectionbox` | `function deathstats.get_pose_selectionbox(pose_type: string\|nil)
  -> selectionbox: number[]` |  Return the interaction selectionbox bounding box for a given resting pose  to match the physical mesh contact bounds in world space.  @*param* `pose_type` — supine  @*return* `selectionbox` — Bounding box table { minx, miny, minz, maxx, maxy, maxz } |
| `get_scoreboard_bg_texture` | `function deathstats.get_scoreboard_bg_texture(m: table, viewer_row_idx: integer\|nil, _entries: table\|nil)
  -> texture: string` |  Generate a composite texture string for the tactical scoreboard plaque  Combines dark translucent panel, glowing border, header divider, column header strip, table grid, icons, and status indicators  @*param* `m` — Metrics table from calculate_scoreboard_metrics  @*param* `viewer_row_idx` — 1-based index of the viewer's row within visible rows  @*param* `_entries` — Visible player entry tables for row status icons  @*return* `texture` — Composite Luanti texture spec |
| `get_scoreboard_cell_color` | `function deathstats.get_scoreboard_cell_color(col: table, player: ObjectRef, item: table, row_idx: integer)
  -> color: integer` |  Determine HUD text color for a scoreboard cell based on column config or player state  @*param* `col` — Column definition  @*param* `player` — Target viewer player  @*param* `item` — Row player entry data  @*param* `row_idx` — 1-based row index  @*return* `color` — HUD numeric color |
| `get_scoreboard_columns` | `function deathstats.get_scoreboard_columns(board_w: integer, is_small: boolean, hud_scale: number)
  -> columns: table
  2. pad_x: integer
  3. usable_w: integer` |  Compute column layout specifications spanning the full usable width of the scoreboard plaque  Pulls dynamically from registered columns and normalizes relative widths  @*param* `board_w` — Total plaque width in pixels  @*param* `is_small` — Whether small-screen condensed mode is active  @*param* `hud_scale` — Active HUD scaling factor  @*return* `columns` — Ordered array of column definitions  @*return* `pad_x` — Left/right padding in pixels  @*return* `usable_w` — Usable table width in pixels |
| `get_scoreboard_data` | `function deathstats.get_scoreboard_data(viewer_player: ObjectRef\|nil, precomputed_base: table\|nil)
  -> entries: table` |  Hooked scoreboard data provider: merges real connected players with mock entries  @*param* `viewer_player` — The viewing player  @*param* `precomputed_base` — Optional pre-gathered and pre-sorted player base entries  @*return* `entries` — Sorted, ranked player entry list |
| `get_scoreboard_footer_text` | `function deathstats.get_scoreboard_footer_text(total_count: integer, visible_count: integer)
  -> footer_str: string` |  Generate footer hint string for the live scoreboard HUD overlay  @*param* `total_count` — Total connected / mock player count  @*param* `visible_count` — Count of players currently displayed in HUD  @*return* `footer_str` — Formatted footer text |
| `get_stack_name` | `function deathstats.get_stack_name(stack: any)
  -> name: string` |  Safely get the item name from an ItemStack, itemstring, or table without assuming Lua type.  In Luanti C++ engine, ItemStacks are userdata, while mock environments may pass tables or strings.  @*param* `stack` — The ItemStack (userdata), itemstring, or table representation  @*return* `name` — The item name, or "" if empty or nil |
| `get_terrain_downhill_dir` | `function deathstats.get_terrain_downhill_dir(pos: Vector, base_yaw: number\|nil, pitch_slope: number\|nil)
  -> down_x: number
  2. down_z: number
  3. slope_angle: number` |  Probe 3D terrain elevation surrounding the corpse to determine the true downhill slope gradient  Works across stairs, inclines, and irregular cliffs regardless of corpse orientation.  @*param* `pos` — Center position of the corpse  @*param* `base_yaw` — Facing yaw in radians  @*param* `pitch_slope` — Pre-calculated slope pitch along the spine axis  @*return* `down_x` — Downhill direction unit vector X (0 if flat)  @*return* `down_z` — Downhill direction unit vector Z (0 if flat)  @*return* `slope_angle` — Slope steepness angle in radians |
| `has_ground_support` | `function deathstats.has_ground_support(pos: Vector)
  -> has_support: boolean` |  Check if a corpse has solid ground or liquid support beneath it  Used to detect if blocks below a settled corpse have been dug out  Uses integer coordinate rounding to prevent negative coordinate truncation in C++ engine  and probes the corpse collision footprint (±0.28) so corpses on edges/slopes remain grounded  @*param* `pos` — 3D corpse position  @*return* `has_support` — True if supported by walkable ground or liquid |
| `hide_all_hudbars` | `function deathstats.hide_all_hudbars(player: ObjectRef)` |  Hide all external HUD bars (hudbars, hunger, stamina) for a player during death sequence  @*param* `player` — The deceased player object |
| `hide_scoreboard_hud` | `function deathstats.hide_scoreboard_hud(player: string\|ObjectRef, keep_chat_state: boolean\|nil)` |  Hide and remove all active scoreboard HUD elements for a player  @*param* `player` — Target player object or player name  @*param* `keep_chat_state` — If true, keeps chat state untouched (e.g. during immediate re-show) |
| `hide_standalone_huds` | `function deathstats.hide_standalone_huds(player: ObjectRef)` |  Hide standalone HUD statbars during death screen  @*param* `player` — Luanti player object |
| `hook_animation_function` | `function deathstats.hook_animation_function(mod_table: table\|nil, fn_name: string)` |  Wrap an animation function to prevent death animation looping while a player is dead  In Luanti Game (MTG) / Repixture, player_api.globalstep calls player_set_animation(player, "lay") every tick  which defaults to loop = true at 30 fps, causing a violent 0.13s death replay loop.  This hook forces loop = false and speed = 1 so the character cleanly stays in the final flat pose.  @*param* `mod_table` — The mod table containing the animation function  @*param* `fn_name` — The name of the animation function |
| `hooked_animations` | `table` |  Set of hooked external animation functions to prevent death replay looping |
| `inspect_surroundings_fallback` | `function deathstats.inspect_surroundings_fallback(player: ObjectRef)
  -> analysis: table` |  Deep environmental and state inspection fallback when engine reason table is nil or incomplete  Checks recent combat punches, falling velocity, surrounding nodes (lava, water, suffocation, fall, out-of-world)  @*param* `player` — The deceased player object  @*return* `analysis` — The deduced death information table |
| `is_armor_dropped` | `function deathstats.is_armor_dropped(_player: any)
  -> drops: boolean` |  Check if 3d_armor is configured to drop or destroy armor on player death  @*param* `player` — Optional player reference  @*return* `drops` — True if armor is ejected/dropped from inventory on death |
| `is_in_liquid` | `function deathstats.is_in_liquid(pos: Vector, death_info: table\|nil)
  -> in_liquid: boolean` |  Check if a death position represents being in a liquid (water, lava, etc.)  Checks death category as well as world nodes at feet, torso, and head level  @*param* `pos` — Player death position  @*param* `death_info` — Optional death details  @*return* `in_liquid` — True if player died in or around liquid |
| `is_inventory_dropped` | `function deathstats.is_inventory_dropped(player: ObjectRef\|nil)
  -> dropped: boolean` |  Check if player inventory/items are dropped or lost on death  If false, the player keeps items in inventory, so corpse should display wielded item  @*param* `player` — Optional player reference  @*return* `dropped` — True if items are dropped on death, false if kept |
| `is_inventory_list_empty` | `function deathstats.is_inventory_list_empty(inv: InvRef, list_name: string)
  -> is_empty: boolean` |  Check whether an entire inventory list is empty  @*param* `inv` — The inventory reference  @*param* `list_name` — The inventory list name  @*return* `is_empty` — True if list is empty or has no items |
| `is_liquid_at` | `function deathstats.is_liquid_at(pos: Vector)
  -> is_liquid: boolean` |  Check if a specific world position contains liquid (water, lava, or modded fluids)  @*param* `pos` — The position to check  @*return* `is_liquid` — True if the node is liquid |
| `is_mob_entity` | `function deathstats.is_mob_entity(ent_name: string, ent_def: table\|nil, ent_instance: table\|nil)
  -> is_mob: boolean` |  Validate whether an entity is a genuine living mob (monster, animal, npc)  Rejects projectiles, falling nodes, items, boats/carts, and internal utility entities  @*param* `ent_name` — Technical registered entity name  @*param* `ent_def` — Entity definition table  @*param* `ent_instance` — Living LuaEntity instance  @*return* `is_mob` — True if the entity is a valid mob |
| `is_player_afk` | `function deathstats.is_player_afk(player_or_name: string\|ObjectRef)
  -> is_afk: boolean` |  Check if a player is currently AFK (away from keyboard)  @*param* `player_or_name` — The player object or username  @*return* `is_afk` — True if inactive duration exceeds afk_timeout setting |
| `is_player_dead` | `function deathstats.is_player_dead(player_or_name: string\|ObjectRef)
  -> is_dead: boolean` |  Check if a player is currently deceased (viewing death screen or HP <= 0)  @*param* `player_or_name` — The player object or username  @*return* `is_dead` — True if the player is dead |
| `is_player_dehydrated` | `function deathstats.is_player_dehydrated(player: ObjectRef)
  -> is_dehydrated: boolean` |  Check if player is currently dehydrated  @*param* `player` — Luanti player object  @*return* `is_dehydrated` — True if player is dehydrated |
| `is_player_online` | `function deathstats.is_player_online(player_or_name: string\|ObjectRef)
  -> is_online: boolean` |  Check if a player is currently connected and active on the server  @*param* `player_or_name` — The player object or player name  @*return* `is_online` — True if player is actively connected and not leaving/offline |
| `is_player_sprint_exhausted` | `function deathstats.is_player_sprint_exhausted(player: ObjectRef)
  -> is_exhausted: boolean` |  Check if player is exhausted from sprinting  @*param* `player` — Luanti player object  @*return* `is_exhausted` — True if stamina/exhaustion threshold is reached |
| `is_player_starving` | `function deathstats.is_player_starving(player: ObjectRef)
  -> is_starving: boolean` |  Check if player is currently starving  @*param* `player` — Luanti player object  @*return* `is_starving` — True if player is starving |
| `is_respawning` | `table<string, boolean>` | Flags marking players currently in respawn transition |
| `is_scoreboard_key_down` | `function deathstats.is_scoreboard_key_down(player: ObjectRef, key_setting: string\|nil, ctrl: table\|nil)
  -> is_down: boolean` |  Determine if the player is currently holding the scoreboard activation key/combination  Supports "zoom", "sneak+aux1", "aux1", "sneak", or custom combinations  @*param* `player` — Target player  @*param* `key_setting` — Optional key config string  @*param* `ctrl` — Optional pre-fetched player control table  @*return* `is_down` — True if all configured keys are currently pressed |
| `is_shutting_down` | `boolean` | True during server shutdown to suppress redundant cleanup logic |
| `is_soft_node` | `function deathstats.is_soft_node(ndef: table\|nil, node_name: string\|nil)
  -> is_soft: boolean` |  Determine whether a node surface is soft / cushioning using node groups and attributes  Checks fall_damage_add_percent < 0, crumbly, snappy, wool, leaves, sand, soil, snowy, hay  @*param* `ndef` — Node definition table  @*param* `node_name` — Technical node name |
| `is_stack_empty` | `function deathstats.is_stack_empty(stack: any)
  -> empty: boolean` |  Check whether an item stack or slot is empty, supporting userdata ItemStack, table, string, or nil.  @*param* `stack` — The ItemStack (userdata), itemstring, or table representation  @*return* `empty` — True if the stack is empty, contains no items, or is nil/"" |
| `last_activity` | `table<string, number>` | Timestamps of last recorded player interaction for AFK detection |
| `last_blow` | `table<string, table<string, any>>` | Recorded fatal blow attack metadata per player |
| `last_death_reason` | `table<string, table<string, any>>` | Recorded death reason tables per player |
| `left_players` | `table<string, boolean>` | Flags tracking players who disconnected while deceased |
| `load_player_stats` | `function deathstats.load_player_stats(player_name: string)
  -> data: table` |  Load persistent player lifetime statistics from Mod Storage and initialize current run  @*param* `player_name` — The unique username of the player  @*return* `data` — The player data table containing current_run, lifetime, and last_life |
| `migrate_ores_mined` | `function deathstats.migrate_ores_mined(ores_map: table)
  -> ores_map: table` |  Migrate legacy mined ore block names to actual dropped item names (e.g. stone_with_coal -> coal_lump)  @*param* `ores_map` — Map of [item_or_node_name] = count  @*return* `ores_map` — The migrated map |
| `mock_players_data` | `table` |  Default template list of mock players with diverse names, combat records, and network latencies |
| `mock_scoreboard_enabled` | `boolean` |  Whether mock player records are injected into the live scoreboard |
| `mock_scoreboard_player_count` | `nil` |  Target count of mock players to simulate on scoreboard (nil for all)  nil means all mock players |
| `modpath` | `string` | Filesystem path to the deathstats mod root directory |
| `node_tile_texture_cache` | `table<string, string>` | Cache of resolved node tile texture strings |
| `on_player_respawn` | `function deathstats.on_player_respawn(player: ObjectRef)` |  Cleanup handler invoked by engine on player respawn  @*param* `player` — The player that respawned |
| `open_scoreboard_formspecs` | `table<string, boolean>` | Map of player names to full scoreboard formspec open states |
| `open_scoreboard_tabs` | `table<string, string>` | Map of player names to active tab ID on full scoreboard formspec |
| `orig_get_scoreboard_data` | `function` |  |
| `play_death_sound` | `function deathstats.play_death_sound(player: ObjectRef)` | @*param* `player` — The player object who should receive the audio effect |
| `player_camera_data` | `table<string, table<string, any>>` | Camera orbit tracking data and original camera modes |
| `player_corpses` | `table<string, table<string, any>>` | Active corpse entity references and visual tracking state |
| `player_last_look` | `table<string, number>` | Last recorded horizontal view pitch/yaw for AFK tracking |
| `player_last_pos` | `table<string, Vector>` | Last recorded positions of players for movement tracking |
| `players` | `table<string, table<string, any>>` | In-memory cache of loaded player lifetime statistics |
| `pose_corpse` | `function deathstats.pose_corpse(corpse: ObjectRef, mesh_name: string\|nil, anim_name: string\|nil)` |  Set the corpse entity into a pose matching the active model  @*param* `corpse` — The corpse entity object  @*param* `mesh_name` — The model mesh name  @*param* `anim_name` — lay |
| `probe_ground_elevation` | `function deathstats.probe_ground_elevation(probe_x: number, probe_z: number, start_y: number)
  -> elevation: number\|nil` |  Probe surface ground elevation at a specific horizontal coordinate  Uses raycast if available, falling back to discrete vertical node scan  @*param* `probe_x` — X position to probe  @*param* `probe_z` — Z position to probe  @*param* `start_y` — Reference Y position  @*return* `elevation` — Ground contact Y elevation or nil if air/void |
| `random_float` | `function deathstats.random_float(min_val: number, max_val: number)
  -> val: number` |  Generate a pseudo-random floating point number in range [min_val, max_val]  @*param* `min_val` — Minimum bound  @*param* `max_val` — Maximum bound  @*return* `val` — Random floating point value |
| `recent_dehydrations` | `table<string, number>` | Timestamps of recent thirst dehydration events |
| `recent_explosions` | `table` |  Recent in-world explosion events tracked for fatal blast attribution |
| `recent_falls` | `table<string, number>` | Timestamps and peak elevations of recent falls for fatal fall analysis |
| `recent_punches` | `table<string, table<string, any>>` | Most recent combat punches received by player for killer attribution |
| `recent_starvations` | `table<string, number>` | Timestamps of recent hunger starvation events |
| `record_explosion` | `function deathstats.record_explosion(pos: Vector, radius: number\|nil)` |  Record an explosion occurrence with timestamp and coordinates  @*param* `pos` — Center of the explosion  @*param* `radius` — Optional explosion blast radius |
| `record_player_death` | `function deathstats.record_player_death(player: string\|ObjectRef, death_info: table)` |  Finalize statistics for the deceased player run, update lifetime aggregates, and archive to last_life  @*param* `player` — The player who died  @*param* `death_info` — The death analysis table containing reason_text, killer_name, weapon, and funny_note |
| `register_scoreboard_column` | `function deathstats.register_scoreboard_column(id: string, def: table)` |  Register or override a scoreboard column definition  @*param* `id` — Unique identifier for the column (e.g. "kills", "damage", "ping")  @*param* `def` — Column definition specification (order, title, pct, min_w, icon, get_value, get_color) |
| `registered_columns` | `table<string, table<string, any>>` | Registered custom scoreboard column definitions |
| `remove_corpse` | `function deathstats.remove_corpse(corpse: ObjectRef\|nil)` |  Safely remove a corpse entity and any attached wielditem entity  @*param* `corpse` — The corpse object reference |
| `reset_camera` | `function deathstats.reset_camera(player: ObjectRef, is_leaving: boolean\|nil)` |  Reset player camera back to normal first-person behavior, remove corpse, and restore player properties  @*param* `player` — The player object to reset  @*param* `is_leaving` — True if called when player is leaving the server |
| `reset_player_activity` | `function deathstats.reset_player_activity(player_or_name: string\|ObjectRef)` |  Reset player last active timestamp for ultra-efficient AFK tracking  @*param* `player_or_name` — The player object or username |
| `reset_player_effects` | `function deathstats.reset_player_effects(player: ObjectRef, is_leaving: boolean\|nil)` |  Completely reset all death screen effects, HUDs, physics, camera, and state for a player  Centralized, reusable helper covering all edge cases (respawn, join, leave, revival)  @*param* `player` — The player whose death effects should be cleared  @*param* `is_leaving` — True if called when player is leaving the server |
| `resolve_entity_info` | `function deathstats.resolve_entity_info(obj: ObjectRef)
  -> name: string
  2. is_player: boolean
  3. entity_desc: string
  4. projectile_name: string\|nil` |  Extract name and description from an ObjectRef (Player, LuaEntity, or projectile)  Resolves real shooting player if entity is an arrow or sword projectile  @*param* `obj` — The attacker object reference  @*return* `name` — The killer's identifier or username  @*return* `is_player` — True if the resolved attacker is a player  @*return* `entity_desc` — The human-readable title of the killer  @*return* `projectile_name` — The projectile entity name if launched remotely |
| `resolve_puncher_player` | `function deathstats.resolve_puncher_player(puncher: ObjectRef\|nil)
  -> real_attacker: ObjectRef\|nil
  2. is_player: boolean
  3. projectile_name: string\|nil
  4. weapon_name: string\|nil` |  Extract the real player or entity behind an attack, punch, or projectile  Supports direct player punch, x_bows arrows, x_obsidianmese sword projectiles, and standard projectile mods  @*param* `puncher` — The raw puncher object passed to on_punchplayer  @*return* `real_attacker` — The actual player or mob entity responsible for the attack  @*return* `is_player` — True if the attacker was a player (either directly or via shooting a projectile)  @*return* `projectile_name` — The registered entity name of the projectile if fired from distance  @*return* `weapon_name` — The technical item name of the wielded weapon used by a player |
| `respawn_immunity` | `table<string, boolean>` | Flags marking temporary post-respawn damage immunity |
| `respawn_player` | `function deathstats.respawn_player(player: ObjectRef)` |  Initiate player respawn from UI buttons  @*param* `player` — The player requesting respawn |
| `restore_all_hudbars` | `function deathstats.restore_all_hudbars(player: ObjectRef)` |  Restore all external HUD bars (hudbars, hunger, stamina) for a player on respawn  @*param* `player` — The respawned player object |
| `restore_player_inventory_and_hand` | `function deathstats.restore_player_inventory_and_hand(player: ObjectRef)
  -> restored: boolean` |  Restore any stashed inventory and hand reach, verifying both in-memory camera data and persistent metadata.  Used on respawn, disconnect, and joinplayer to guarantee 0% item loss and no stuck zero-reach camera hand.  @*param* `player` — The player whose inventory and hand reach should be verified and restored  @*return* `restored` — True if any inventory lists or hand reach were restored or sanitized |
| `restore_standalone_huds` | `function deathstats.restore_standalone_huds(player: ObjectRef)` |  Restore standalone HUD statbars upon respawn or effect reset  @*param* `player` — Luanti player object |
| `rotate_corpse_bone` | `function deathstats.rotate_corpse_bone(corpse: ObjectRef, bone_name: string, rot_vec: Vector)
  -> success: boolean` |  Rotate a corpse bone in 3D space (local X, Y, Z axes)  Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)  @*param* `corpse` — The corpse entity object  @*param* `bone_name` — The name of the bone to rotate  @*param* `rot_vec` — The rotation vector in radians (x, y, z)  @*return* `success` — True if the rotation was applied |
| `rotate_corpse_bone_planar` | `function deathstats.rotate_corpse_bone_planar(corpse: ObjectRef, bone_name: string, z_rad: number)
  -> success: boolean` |  Rotate a corpse bone strictly along the horizontal floor plane (around local Z axis)  Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)  @*param* `corpse` — The corpse entity object  @*param* `bone_name` — The name of the bone to rotate  @*param* `z_rad` — The rotation angle in radians around local Z axis  @*return* `success` — True if the rotation was applied |
| `safe_normalize` | `function deathstats.safe_normalize(v: Vector)
  -> normalized: Vector` |  Safely normalize a 3D vector without producing NaN on zero length  @*param* `v` — 3D vector to normalize  @*return* `normalized` — The normalized unit vector, or (0,0,0) if zero length |
| `sample_corpse_ambient_light` | `function deathstats.sample_corpse_ambient_light(pos: table, yaw: number\|nil)
  -> light: number\|nil` |  Samples ambient illumination of the open space around a corpse  @*param* `pos` — Position vector of the corpse  @*param* `yaw` — Facing yaw in radians  @*return* `light` — Ambient light value (0-14) or nil if unavailable |
| `save_player_stats` | `function deathstats.save_player_stats(player_name: string)` |  Save player lifetime statistics to Mod Storage  @*param* `player_name` — The unique username of the player |
| `scoreboard_bg_cache` | `table<string, string>` | Cached background formspec texture strings keyed by layout dimensions |
| `scoreboard_states` | `table<string, boolean>` | Map of player names to live scoreboard visibility states (true = visible) |
| `serialize_inventory_list` | `function deathstats.serialize_inventory_list(inv: InvRef, list_name: string)
  -> items: string[]` |  Serialize an inventory list into an array of itemstrings  @*param* `inv` — The inventory reference  @*param* `list_name` — The inventory list name  @*return* `items` — Array of itemstrings |
| `set_death_camera` | `function deathstats.set_death_camera(player: ObjectRef, death_info: table\|nil)` |  Switch player camera to death perspective (smooth circular orbit around corpse/bones)  @*param* `player` — The deceased player object  @*param* `death_info` — Optional death analysis information table |
| `set_engine_player_attached` | `function deathstats.set_engine_player_attached(name: string, attached: boolean\|nil)` |  Set or clear the player_attached flag in player_api / x_player_api and default mods  @*param* `name` — The player name  @*param* `attached` — True if attached, nil to clear |
| `settle_corpse_at_rest` | `function deathstats.settle_corpse_at_rest(luaent: table\|ObjectRef)` |  Settle the corpse entity to a complete rest at its final position  @*param* `luaent` — The corpse Lua entity table or ObjectRef |
| `settle_ragdoll_limbs` | `function deathstats.settle_ragdoll_limbs(corpse: ObjectRef, impact_damage: number\|nil, pose_type: string\|nil, hanging_legs: boolean\|nil, roll_rad: number\|nil)` |  Apply final limp resting fractures or organic pose angles to corpse limbs on landing  @*param* `corpse` — The corpse entity object  @*param* `impact_damage` — Damage of the lethal impact  @*param* `pose_type` — Optional resting pose ("supine", "prone", "lateral")  @*param* `hanging_legs` — True if legs hang over a ledge/drop  @*param* `roll_rad` — Optional corpse roll angle in radians |
| `show_corpse_epitaph_formspec` | `function deathstats.show_corpse_epitaph_formspec(clicker: ObjectRef, corpse_ref: table\|ObjectRef)` |  Show corpse epitaph tombstone plaque formspec when living players right-click a settled corpse  @*param* `clicker` — The living player inspecting the corpse  @*param* `corpse_ref` — The corpse entity reference or luaentity table |
| `show_death_formspec` | `function deathstats.show_death_formspec(player: ObjectRef, death_info: table)` |  Display the elevated death formspec with consistent padding above hotbar area  @*param* `player` — The deceased player object  @*param* `death_info` — The death analysis metadata table containing cause, killer, and notes |
| `show_lifetime_formspec` | `function deathstats.show_lifetime_formspec(player: ObjectRef, from_death_screen: boolean\|nil)` |  Display the lifetime player dossier formspec dialog (alias for show_lifetime_stats_formspec)  @*param* `player` — Luanti player object  @*param* `from_death_screen` — True if launched from death screen modal |
| `show_lifetime_stats_formspec` | `function deathstats.show_lifetime_stats_formspec(player: ObjectRef, tab: string\|nil)` |  Display the Lifetime Statistics Dashboard with transparent backdrop and accessible tabs  @*param* `player` — The player viewing statistics  @*param* `tab` — The active tab name ("overview", "records", "ores", or "combat") |
| `show_photo_mode_formspec` | `function deathstats.show_photo_mode_formspec(player: ObjectRef)` |  Display the elevated death formspec with consistent padding above hotbar area  @*param* `player` — The deceased player object  @*param* `death_info` — The death analysis metadata table containing cause, killer, and notes   Show minimal photo mode overlay with single button to restore death UI  @*param* `player` — The deceased player object |
| `show_scoreboard_formspec` | `function deathstats.show_scoreboard_formspec(player: ObjectRef, tab: string\|nil)` |  Display the full scrollable formspec scoreboard table with all players  @*param* `player` — Target player  @*param* `tab` — Optional tab ("live" or "hall_of_fame"). Defaults to "live". |
| `show_scoreboard_hud` | `function deathstats.show_scoreboard_hud(player: ObjectRef, precomputed_entries: table\|nil)` |  Display or initialize the 2D HUD Scoreboard overlay for a player  Centered at position={x=0.5, y=0.5} with z_index=1000 and monospaced style=1  @*param* `player` — The player holding the activation key  @*param* `precomputed_entries` — Optional pre-calculated scoreboard entries |
| `spawn_and_setup_corpse` | `function deathstats.spawn_and_setup_corpse(corpse_pos: Vector, visuals: table, player: ObjectRef\|nil, death_info: table\|nil, last_blow: table\|nil, is_settled_override: boolean\|nil)
  -> corpse: ObjectRef\|nil` | @*param* `corpse_pos` — Position to spawn the corpse  @*param* `visuals` — Player visuals table (mesh, textures, visual_size, yaw, ...)  @*param* `player` — The dying player entity  @*param* `death_info` — Death metadata  @*param* `last_blow` — Last damage blow information  @*param* `is_settled_override` — True if corpse should spawn directly settled without launch impulses  @*return* `corpse` — The spawned corpse entity or nil if failed (e.g. mapblock not loaded) |
| `spawn_corpse_particles` | `function deathstats.spawn_corpse_particles(corpse_pos: table, death_info: table\|nil, attached_obj: ObjectRef\|nil)
  -> spawner_ids: number[]
  2. effect_type: string\|nil` |  Spawn corpse particle spawner(s) according to death cause/environment  @*param* `corpse_pos` — The {x, y, z} position of the corpse  @*param* `death_info` — Optional death analysis table  @*param* `attached_obj` — Optional corpse ObjectRef to attach particles to  @*return* `spawner_ids` — Array of active particle spawner IDs  @*return* `effect_type` — The type of effect spawned (e.g. "water", "lava", "fire", "flies", "impact") |
| `spawn_decay_particles` | `function deathstats.spawn_decay_particles(pos: Vector)
  -> spawner_id: integer\|nil` | @*param* `pos` — Center position of the decaying corpse  @*return* `spawner_id` — Particle spawner identifier or nil if disabled |
| `spawn_impact_burst` | `function deathstats.spawn_impact_burst(pos: Vector, ground_node_name: string\|nil, intensity: number\|nil)` |  Spawn an instantaneous localized burst of node debris particles at the impact site  @*param* `pos` — The collision contact point  @*param* `ground_node_name` — The node name struck  @*param* `intensity` — Impact velocity or damage |
| `stack_to_string` | `function deathstats.stack_to_string(stack: any)
  -> itemstring: string` |  Safely convert an ItemStack, table, or string to a pure string representation for serialization.  Guaranteed to return a pure string (never userdata) so core.serialize never fails with unsupported type.  In Luanti, ItemStack:to_string() preserves count, wear, and item metadata.  @*param* `stack` — The ItemStack (userdata), itemstring, or table representation  @*return* `itemstring` — The item serialized to string (empty string "" if empty) |
| `storage` | `StorageRef` | Luanti persistent mod storage reference |
| `trigger_death_screen` | `function deathstats.trigger_death_screen(player: ObjectRef, reason: table\|nil, is_reconnect: boolean\|nil)` |  Launch the cinematic death screen experience (Camera, Sound, HUD & Formspec)  @*param* `player` — The deceased player object  @*param* `reason` — The optional death reason table provided by the engine  @*param* `is_reconnect` — True if player was already dead and is reconnecting |
| `truncate_str` | `function deathstats.truncate_str(str: string\|nil, max_len: number)
  -> The: string` |  Helper to safely truncate strings to prevent UI overflow  @*param* `str` — The input string to truncate  @*param* `max_len` — The maximum allowable character length  @*return* `The` — truncated string with ellipsis or original string |
| `unhide_corpse_arrows` | `function deathstats.unhide_corpse_arrows(corpse: ObjectRef\|nil)` |  Unhide and restore native visual scale for any arrows attached to a corpse  Defensively resets is_visible = true and restores visual_size if previously zeroed  @*param* `corpse` — The corpse entity object |
| `unregister_scoreboard_column` | `function deathstats.unregister_scoreboard_column(id: string)` |  Unregister an existing scoreboard column by id  @*param* `id` — Unique column identifier |
| `update_death_camera` | `function deathstats.update_death_camera(player: ObjectRef, dtime: number)` |  Update camera position and orientation along the circular orbit  @*param* `player` — The deceased player object  @*param* `dtime` — Delta time in seconds since last frame |
| `update_ragdoll_flight_limbs` | `function deathstats.update_ragdoll_flight_limbs(corpse: ObjectRef, velocity: Vector, _base_yaw: number, bounce_shock: number\|nil)` |  Procedurally adjust corpse limb angles during flight with 3D aerodynamics, vertical drag & bounce shock  @*param* `corpse` — The corpse entity object  @*param* `velocity` — Current velocity vector  @*param* `_base_yaw` — Facing yaw of the corpse  @*param* `bounce_shock` — Optional active bounce shock impulse |
| `update_ragdoll_slide_limbs` | `function deathstats.update_ragdoll_slide_limbs(corpse: ObjectRef, velocity: Vector, _base_yaw: number, bounce_shock: number\|nil, slide_timer: number\|nil)` |  Procedurally adjust corpse limbs while sliding along ground or tumbling down stairs/hills  Simulates ground surface friction drag, stair step bumps, and reactive limp jostling  @*param* `corpse` — The corpse entity object  @*param* `velocity` — Current velocity vector  @*param* `_base_yaw` — Facing yaw of the corpse  @*param* `bounce_shock` — Active bounce shock impulse  @*param* `slide_timer` — Accumulated sliding duration in seconds |
| `update_scoreboard_hud` | `function deathstats.update_scoreboard_hud(player: ObjectRef, precomputed_entries: table\|nil)` |  Update existing scoreboard HUD overlay elements with live changes (diff-based)  Only changes fields that modified (time, stats, ping) to eliminate network lag  @*param* `player` — Target player  @*param* `precomputed_entries` — Optional pre-calculated scoreboard entries |
| `zero_player_velocity` | `function deathstats.zero_player_velocity(player: ObjectRef)` |  Cancel any player momentum / velocity safely across Luanti engine versions  Uses modern player:get_velocity() / player:add_velocity() without triggering deprecation warnings  @*param* `player` — The player object |

### `DeathStatsColors`

| Field | Type | Description |
| :--- | :--- | :--- |
| `active_strip` | `string` | Hex color string for active navigation indicators |
| `btn_primary_bg` | `string` | Hex color string for primary action button background |
| `btn_primary_border` | `string` | Hex color string for primary button border |
| `btn_primary_hover_bg` | `string` | Hex color string for hovered primary button background |
| `btn_primary_hover_border` | `string` | Hex color string for hovered primary button border |
| `btn_primary_text` | `string` | Hex color string for primary button label text |
| `btn_secondary_bg` | `string` | Hex color string for secondary button background |
| `btn_secondary_border` | `string` | Hex color string for secondary button border |
| `btn_secondary_hover_bg` | `string` | Hex color string for hovered secondary button background |
| `btn_secondary_hover_border` | `string` | Hex color string for hovered secondary button border |
| `btn_secondary_text` | `string` | Hex color string for secondary button label text |
| `card_inset` | `string` | Hex color string for inset sub-panels |
| `card_modal` | `string` | Hex color string for modal dialog background |
| `card_panel` | `string` | Hex color string for statistics panel background |
| `card_sidebar` | `string` | Hex color string for sidebar card background |
| `crimson_border` | `string` | Hex color string for crimson accent borders |
| `crimson_glow` | `string` | Hex color string for crimson glowing highlights |
| `hud_afk` | `integer` | Numeric hex color (0xRRGGBB) for AFK status HUD indicators |
| `hud_crimson` | `integer` | Numeric hex color (0xRRGGBB) for crimson HUD warnings |
| `hud_cyan` | `integer` | Numeric hex color (0xRRGGBB) for cyan tactical metrics |
| `hud_dead` | `integer` | Numeric hex color (0xRRGGBB) for deceased status HUD indicators |
| `hud_gold` | `integer` | Numeric hex color (0xRRGGBB) for golden HUD highlights |
| `hud_green` | `integer` | Numeric hex color (0xRRGGBB) for green status indicators |
| `hud_muted` | `integer` | Numeric hex color (0xRRGGBB) for dimmed HUD elements |
| `hud_ping_bad` | `integer` | Numeric hex color (0xRRGGBB) for high ping latency |
| `hud_ping_good` | `integer` | Numeric hex color (0xRRGGBB) for low ping latency |
| `hud_ping_warn` | `integer` | Numeric hex color (0xRRGGBB) for moderate ping latency |
| `hud_soft_white` | `integer` | Numeric hex color (0xRRGGBB) for soft-white HUD text |
| `hud_white` | `integer` | Numeric hex color (0xRRGGBB) for white HUD text |
| `row_alt` | `string` | Hex color string for alternating table row striping |
| `row_viewer` | `string` | Hex color string highlighting the viewer player row |
| `tab_active_bg` | `string` | Hex color string for active tab background |
| `tab_active_border` | `string` | Hex color string for active tab border |
| `tab_active_hover_bg` | `string` | Hex color string for hovered active tab background |
| `tab_active_hover_border` | `string` | Hex color string for hovered active tab border |
| `tab_active_text` | `string` | Hex color string for active tab label text |
| `tab_bar_bg` | `string` | Hex color string for tab navigation bar background |
| `tab_bar_sep` | `string` | Hex color string for tab separator dividers |
| `tab_inactive_bg` | `string` | Hex color string for inactive tab background |
| `tab_inactive_border` | `string` | Hex color string for inactive tab border |
| `tab_inactive_hover_bg` | `string` | Hex color string for hovered inactive tab background |
| `tab_inactive_hover_border` | `string` | Hex color string for hovered inactive tab border |
| `tab_inactive_text` | `string` | Hex color string for inactive tab label text |
| `text_afk` | `string` | Hex color string for away-from-keyboard status text |
| `text_crimson` | `string` | Hex color string for crimson danger and death text |
| `text_dead` | `string` | Hex color string for deceased player status text |
| `text_gold` | `string` | Hex color string for gold stat labels and headers |
| `text_muted` | `string` | Hex color string for dimmed or secondary text |
| `text_ping_bad` | `string` | Hex color string for high network latency ping |
| `text_ping_good` | `string` | Hex color string for optimal network latency ping |
| `text_ping_warn` | `string` | Hex color string for moderate network latency ping |
| `text_white` | `string` | Hex color string for standard white text |
| `tooltip_bg` | `string` | Hex color string for tooltip dialog backgrounds |
| `transparent` | `string` | Hex color string for fully transparent elements |

### `DeathStatsConfig`

| Field | Type | Description |
| :--- | :--- | :--- |
| `afk_timeout` | `number` | Idle duration in seconds before flagging player as AFK |
| `animation_duration` | `number` | Duration in seconds of the death screen animation sequence |
| `announce_revenge` | `boolean` | Broadcast server-wide announcement when a player avenges their death |
| `banner_texture` | `string` | Texture overlay file used for the cinematic "YOU DIED" banner |
| `blood_splatter_opacity` | `number` | Opacity factor for blood splatter HUD vignette (0.0 to 1.0) |
| `chat_death_coords` | `boolean` | Broadcast precise XYZ death coordinates in chat upon player death |
| `corpse_decay_time` | `number` | Lifespan duration in seconds before settled corpses dissolve |
| `enable_animation` | `boolean` | Enable cinematic HUD animations (blood splatter, death banner slap) |
| `enable_camera` | `boolean` | Enable smooth third-person cinematic camera orbit around corpse |
| `enable_corpse_impact_sounds` | `boolean` | Enable bone cracking and terrain impact collision audio |
| `enable_corpse_inspect` | `boolean` | Enable right-click inspection dossier dialog for settled corpses |
| `enable_corpse_particles` | `boolean` | Enable ambient atmospheric death particles (flies, smoke, bubbles) |
| `enable_corpse_ragdoll` | `boolean` | Enable physical ragdoll entity spawn with trajectory and bone tumbling |
| `enable_fall_fractures` | `boolean` | Enable severe limb fracture effects from high fall velocity impacts |
| `enable_hall_of_fame` | `boolean` | Enable Hall of Fame leaderboard tab on full scoreboard formspec |
| `enable_limb_fractures` | `boolean` | Enable limb displacement and disarticulation ragdoll physics |
| `enable_mvp_badges` | `boolean` | Display MVP ribbons and achievement badges on scoreboard entries |
| `enable_revenge` | `boolean` | Track and highlight killer vendettas with revenge indicators |
| `enable_scoreboard` | `boolean` | Enable live tactical scoreboard overlay HUD |
| `enable_slope_pitch` | `boolean` | Enable raycast terrain slope inclination alignment for corpses |
| `enable_sounds` | `boolean` | Enable death sound effects and cinematic musical cues |
| `formspec_side` | `string` | Screen dock side for stats dossier ("left" or "right") |
| `orbit_height` | `number` | Vertical elevation offset in blocks above corpse for camera orbit |
| `orbit_radius` | `number` | Distance in blocks from orbit center to death camera |
| `orbit_speed` | `number` | Orbital rotation speed in radians per second |
| `ragdoll_flail_rate` | `number` | Limb twitching and flailing oscillation frequency in Hertz |
| `ragdoll_force_multiplier` | `number` | Knockback impulse scaling multiplier applied to ragdoll corpse |
| `ragdoll_max_velocity` | `number` | Maximum allowed initial launch velocity clamp in blocks/second |
| `ragdoll_resting_poses` | `boolean` | Enable contextual resting poses (prone, supine, slumped, folded) |
| `ragdoll_restitution` | `number` | Bounciness elasticity coefficient for terrain collisions (0.0 to 1.0) |
| `ragdoll_tumbling` | `boolean` | Enable rotational tumbling physics during ragdoll flight |
| `scoreboard_key` | `string` | Keybinding name used to toggle the live scoreboard HUD |
| `scoreboard_suppress_chat` | `boolean` | Automatically suppress background chat messages when scoreboard is open |
| `scoreboard_update_interval` | `number` | Refresh interval in seconds between scoreboard HUD updates |
| `time_format` | `string` | Scoreboard clock time display formatting mode ("24h" or "12h") |

### `PlayerLifetimeStats`

| Field | Type | Description |
| :--- | :--- | :--- |
| `best_life` | `table?` | Personal best achievement record |
| `blocks_mined` | `number` | Total blocks dug/mined |
| `damage_dealt` | `number` | Total damage inflicted on players and mobs |
| `damage_taken` | `number` | Total damage received |
| `deaths` | `number` | Total deaths recorded |
| `distance_traveled` | `number` | Total horizontal meters traversed |
| `items_crafted` | `number` | Total items crafted |
| `last_category` | `string?` | Category of last death |
| `last_cause` | `string?` | Cause of last death |
| `last_coords` | `string?` | Coordinate string of last death |
| `last_funny` | `string?` | Humorous note from last death |
| `last_killer` | `string?` | Killer name of last death |
| `last_weapon` | `string?` | Weapon used in last death |
| `mobs_killed` | `number` | Total monsters and hostile mobs slain |
| `pvp_kills` | `number` | Total opposing players slain |
| `time_alive` | `number` | Total seconds survived in this life |
| `total_ores` | `number` | Total rare ores extracted |

### `PlayerVisuals`

| Field | Type | Description |
| :--- | :--- | :--- |
| `armor_dropped` | `boolean` | Whether player armor was dropped on death |
| `inventory_dropped` | `boolean` | Whether player inventory items were dropped on death |
| `mesh` | `string` | 3D model filename (e.g. "character.b3d", "character.glb") |
| `textures` | `string[]` | Array of texture string identifiers |
| `visual_size` | `Vector` | Visual scale multiplier vector {x, y, z} |
| `wield_item` | `string` | Wielded item name string |
| `yaw` | `number` | Horizontal facing rotation in radians |

### `ScoreboardColumnDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `get_color` | `(fun(player: ObjectRef, item: table):integer)?` | Optional callback returning text color (0xRRGGBB) |
| `get_value` | `fun(player: ObjectRef, item: table, is_small: boolean):string` | Callback returning formatted cell value string |
| `icon` | `string?` | Icon texture name displayed in column header |
| `min_w` | `number` | Minimum column width in pixels |
| `order` | `number` | Sort order placement priority (e.g. 10 to 100) |
| `pct` | `number` | Width proportion of total scoreboard width (0.0 to 1.0) |
| `sort_key` | `(fun(item: table):any)?` | Optional callback returning sortable primitive value |
| `title` | `string` | Header label text displayed on full scoreboard |
| `title_small` | `string?` | Abbreviated header label displayed on compact HUD |
| `tooltip` | `string?` | Tooltip description shown on column hover |

### `ScoreboardEntry`

| Field | Type | Description |
| :--- | :--- | :--- |
| `armor` | `number` | Total armor defense value |
| `blocks_mined` | `number` | Lifetime blocks mined |
| `damage_dealt` | `number` | Lifetime damage dealt |
| `deaths` | `number` | Lifetime deaths |
| `hp` | `number` | Current health points |
| `is_afk` | `boolean` | True if player is currently away-from-keyboard |
| `is_dead` | `boolean` | True if player is currently deceased |
| `kd` | `number` | Calculated kill-to-death ratio |
| `kills` | `number` | Lifetime PvP kills |
| `name` | `string` | Player username |
| `ping` | `number` | Network ping latency in milliseconds |
| `score` | `number` | Tactical composite leaderboard score |
| `survival_time` | `number` | Current life survival time in seconds |

---

## Core & Lifecycle API

Lifecycle management, death screen initialization, respawn handling, player effect clearing, and audio cues.

#### `deathstats.clear_death_hud`

Remove all active death HUD elements for a player

```lua
function deathstats.clear_death_hud(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The player whose death HUD elements should be removed

#### `deathstats.hide_standalone_huds`

Hide standalone HUD statbars during death screen

```lua
function deathstats.hide_standalone_huds(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

#### `deathstats.is_player_dead`

Check if a player is currently deceased (viewing death screen or HP <= 0)

```lua
function deathstats.is_player_dead(player_or_name: string|ObjectRef)
  -> is_dead: boolean
```

**Parameters:**

* `player_or_name` (`string|ObjectRef`): The player object or username

**Returns:**

* `is_dead` (`boolean`): True if the player is dead

#### `deathstats.is_player_online`

Check if a player is currently connected and active on the server

```lua
function deathstats.is_player_online(player_or_name: string|ObjectRef)
  -> is_online: boolean
```

**Parameters:**

* `player_or_name` (`string|ObjectRef`): The player object or player name

**Returns:**

* `is_online` (`boolean`): True if player is actively connected and not leaving/offline

#### `deathstats.on_player_respawn`

Cleanup handler invoked by engine on player respawn

```lua
function deathstats.on_player_respawn(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The player that respawned

#### `deathstats.play_death_sound`

```lua
function deathstats.play_death_sound(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The player object who should receive the audio effect

#### `deathstats.reset_player_activity`

Reset player last active timestamp for ultra-efficient AFK tracking

```lua
function deathstats.reset_player_activity(player_or_name: string|ObjectRef)
```

**Parameters:**

* `player_or_name` (`string|ObjectRef`): The player object or username

#### `deathstats.reset_player_effects`

Completely reset all death screen effects, HUDs, physics, camera, and state for a player
 Centralized, reusable helper covering all edge cases (respawn, join, leave, revival)

```lua
function deathstats.reset_player_effects(player: ObjectRef, is_leaving: boolean|nil)
```

**Parameters:**

* `player` (`ObjectRef`): The player whose death effects should be cleared
* `is_leaving` (`boolean|nil`): True if called when player is leaving the server

#### `deathstats.respawn_player`

Initiate player respawn from UI buttons

```lua
function deathstats.respawn_player(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The player requesting respawn

#### `deathstats.restore_standalone_huds`

Restore standalone HUD statbars upon respawn or effect reset

```lua
function deathstats.restore_standalone_huds(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

#### `deathstats.trigger_death_screen`

Launch the cinematic death screen experience (Camera, Sound, HUD & Formspec)

```lua
function deathstats.trigger_death_screen(player: ObjectRef, reason: table|nil, is_reconnect: boolean|nil)
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `reason` (`table|nil`): The optional death reason table provided by the engine
* `is_reconnect` (`boolean|nil`): True if player was already dead and is reconnecting

#### `deathstats.zero_player_velocity`

Cancel any player momentum / velocity safely across Luanti engine versions
 Uses modern player:get_velocity() / player:add_velocity() without triggering deprecation warnings

```lua
function deathstats.zero_player_velocity(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The player object

---

## Statistics & Storage API

Player lifetime achievement dossiers, ModStorage persistence, stat counters, formatting utilities, and data migration.

#### `deathstats.cleanup_invalid_mobs_slain`

Clean up non-mob entries (arrows, items, falling nodes, vehicles) from player stats

```lua
function deathstats.cleanup_invalid_mobs_slain(data: table)
  -> table|nil
```

**Parameters:**

* `data` (`table`): Player statistics data table

**Returns:**

* `table|nil`

#### `deathstats.create_empty_stats`

Create an empty statistics table structure with default zeroed counters

```lua
function deathstats.create_empty_stats()
  -> stats: table
```

**Returns:**

* `stats` (`table`): New statistics table containing metrics for mining, combat, crafting, and survival

#### `deathstats.deserialize_inventory_list`

Deserialize an array of itemstrings back into an inventory list

```lua
function deathstats.deserialize_inventory_list(inv: InvRef, list_name: string, items: string[])
```

**Parameters:**

* `inv` (`InvRef`): The inventory reference
* `list_name` (`string`): The inventory list name
* `items` (`string[]`): Array of itemstrings

#### `deathstats.format_compact_number`

Format numbers into compact strings (>= 1,000 -> 1k, >= 2,000 -> 2k, >= 10,000 -> 10k, >= 1,000,000 -> 1M)

```lua
function deathstats.format_compact_number(n: number)
  -> The: string
```

**Parameters:**

* `n` (`number`): The numeric value to format

**Returns:**

* `The` (`string`): compact formatted string (e.g. "1k", "10k", "2M")

#### `deathstats.format_name`

Convert an internal node name or item name into a clean, human-readable title
 Retrieves clean description from registered item definition, or falls back to capitalized name

```lua
function deathstats.format_name(item_name: string)
  -> The: string
```

**Parameters:**

* `item_name` (`string`): The raw registered technical item or node name (e.g. "default:stone_with_iron")

**Returns:**

* `The` (`string`): sanitized, capitalized human-readable title (e.g. "Iron Ore")

#### `deathstats.format_number`

Format large integer numbers with standard comma thousand separators (e.g. 1,234,567)

```lua
function deathstats.format_number(n: number)
  -> The: string
```

**Parameters:**

* `n` (`number`): The raw numeric value to format

**Returns:**

* `The` (`string`): formatted number with comma separators

#### `deathstats.format_time`

Format a duration in seconds into a human-readable time string (e.g. "1d 2h 3m" or "45s")

```lua
function deathstats.format_time(sec: number)
  -> The: string
```

**Parameters:**

* `sec` (`number`): The total elapsed duration in seconds

**Returns:**

* `The` (`string`): formatted human-readable time string

#### `deathstats.get_last_death_info`

Retrieve the fallback death reason and epitaph information for a player

```lua
function deathstats.get_last_death_info(player: string|ObjectRef)
  -> last_info: table
```

**Parameters:**

* `player` (`string|ObjectRef`): The player object or player username

**Returns:**

* `last_info` (`table`): Formatted death info table { reason_text = string, funny_note = string, category = string }

#### `deathstats.get_player_data`

Get or initialize the active statistics data table for a player

```lua
function deathstats.get_player_data(player: ObjectRef)
  -> data: table|nil
```

**Parameters:**

* `player` (`ObjectRef`): The player object to retrieve data for

**Returns:**

* `data` (`table|nil`): The active player statistics data table, or nil if player is invalid

#### `deathstats.get_stack_name`

Safely get the item name from an ItemStack, itemstring, or table without assuming Lua type.
 In Luanti C++ engine, ItemStacks are userdata, while mock environments may pass tables or strings.

```lua
function deathstats.get_stack_name(stack: any)
  -> name: string
```

**Parameters:**

* `stack` (`any`): The ItemStack (userdata), itemstring, or table representation

**Returns:**

* `name` (`string`): The item name, or "" if empty or nil

#### `deathstats.is_inventory_list_empty`

Check whether an entire inventory list is empty

```lua
function deathstats.is_inventory_list_empty(inv: InvRef, list_name: string)
  -> is_empty: boolean
```

**Parameters:**

* `inv` (`InvRef`): The inventory reference
* `list_name` (`string`): The inventory list name

**Returns:**

* `is_empty` (`boolean`): True if list is empty or has no items

#### `deathstats.is_stack_empty`

Check whether an item stack or slot is empty, supporting userdata ItemStack, table, string, or nil.

```lua
function deathstats.is_stack_empty(stack: any)
  -> empty: boolean
```

**Parameters:**

* `stack` (`any`): The ItemStack (userdata), itemstring, or table representation

**Returns:**

* `empty` (`boolean`): True if the stack is empty, contains no items, or is nil/""

#### `deathstats.load_player_stats`

Load persistent player lifetime statistics from Mod Storage and initialize current run

```lua
function deathstats.load_player_stats(player_name: string)
  -> data: table
```

**Parameters:**

* `player_name` (`string`): The unique username of the player

**Returns:**

* `data` (`table`): The player data table containing current_run, lifetime, and last_life

#### `deathstats.migrate_ores_mined`

Migrate legacy mined ore block names to actual dropped item names (e.g. stone_with_coal -> coal_lump)

```lua
function deathstats.migrate_ores_mined(ores_map: table)
  -> ores_map: table
```

**Parameters:**

* `ores_map` (`table`): Map of [item_or_node_name] = count

**Returns:**

* `ores_map` (`table`): The migrated map

#### `deathstats.random_float`

Generate a pseudo-random floating point number in range [min_val, max_val]

```lua
function deathstats.random_float(min_val: number, max_val: number)
  -> val: number
```

**Parameters:**

* `min_val` (`number`): Minimum bound
* `max_val` (`number`): Maximum bound

**Returns:**

* `val` (`number`): Random floating point value

#### `deathstats.record_explosion`

Record an explosion occurrence with timestamp and coordinates

```lua
function deathstats.record_explosion(pos: Vector, radius: number|nil)
```

**Parameters:**

* `pos` (`Vector`): Center of the explosion
* `radius` (`number|nil`): Optional explosion blast radius

#### `deathstats.record_player_death`

Finalize statistics for the deceased player run, update lifetime aggregates, and archive to last_life

```lua
function deathstats.record_player_death(player: string|ObjectRef, death_info: table)
```

**Parameters:**

* `player` (`string|ObjectRef`): The player who died
* `death_info` (`table`): The death analysis table containing reason_text, killer_name, weapon, and funny_note

#### `deathstats.safe_normalize`

Safely normalize a 3D vector without producing NaN on zero length

```lua
function deathstats.safe_normalize(v: Vector)
  -> normalized: Vector
```

**Parameters:**

* `v` (`Vector`): 3D vector to normalize

**Returns:**

* `normalized` (`Vector`): The normalized unit vector, or (0,0,0) if zero length

#### `deathstats.save_player_stats`

Save player lifetime statistics to Mod Storage

```lua
function deathstats.save_player_stats(player_name: string)
```

**Parameters:**

* `player_name` (`string`): The unique username of the player

#### `deathstats.serialize_inventory_list`

Serialize an inventory list into an array of itemstrings

```lua
function deathstats.serialize_inventory_list(inv: InvRef, list_name: string)
  -> items: string[]
```

**Parameters:**

* `inv` (`InvRef`): The inventory reference
* `list_name` (`string`): The inventory list name

**Returns:**

* `items` (`string[]`): Array of itemstrings

#### `deathstats.stack_to_string`

Safely convert an ItemStack, table, or string to a pure string representation for serialization.
 Guaranteed to return a pure string (never userdata) so core.serialize never fails with unsupported type.
 In Luanti, ItemStack:to_string() preserves count, wear, and item metadata.

```lua
function deathstats.stack_to_string(stack: any)
  -> itemstring: string
```

**Parameters:**

* `stack` (`any`): The ItemStack (userdata), itemstring, or table representation

**Returns:**

* `itemstring` (`string`): The item serialized to string (empty string "" if empty)

#### `deathstats.truncate_str`

Helper to safely truncate strings to prevent UI overflow

```lua
function deathstats.truncate_str(str: string|nil, max_len: number)
  -> The: string
```

**Parameters:**

* `str` (`string|nil`): The input string to truncate
* `max_len` (`number`): The maximum allowable character length

**Returns:**

* `The` (`string`): truncated string with ellipsis or original string

---

## Death Analysis & Attribution API

Cause-of-death heuristics, environmental inspection, killer entity resolution, hunger/thirst integration, depth/biome context, and humorous epitaphs.

#### `deathstats.analyze_death`

Main Death Cause Analyzer: parses engine death reason metadata or invokes environmental inspection

```lua
function deathstats.analyze_death(player: ObjectRef, reason: table|nil)
  -> analysis: table
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `reason` (`table|nil`): The engine reason table from on_dieplayer or show_death_screen

**Returns:**

* `analysis` (`table`): The complete death metadata table (category, reason_text, killer_name, weapon, funny_note)

#### `deathstats.analyze_death_raw`

Internal raw death cause analyzer

```lua
function deathstats.analyze_death_raw(player: ObjectRef, reason: table|nil)
  -> analysis: table
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `reason` (`table|nil`): The engine reason table from on_dieplayer or show_death_screen

**Returns:**

* `analysis` (`table`): The un-enriched death metadata table

#### `deathstats.enrich_death_info`

Enrich death analysis table with coordinates, depth, biome, killer HP and fall metrics

```lua
function deathstats.enrich_death_info(res: table, player: ObjectRef, puncher: ObjectRef|nil)
  -> enriched: table
```

**Parameters:**

* `res` (`table`): Death analysis table
* `player` (`ObjectRef`): The player who died
* `puncher` (`ObjectRef|nil`): Optional killer entity or puncher

**Returns:**

* `enriched` (`table`): The enriched death analysis table

#### `deathstats.format_projectile_name`

Format a projectile entity name into a clean weapon display title

```lua
function deathstats.format_projectile_name(ent_name: string|nil)
  -> The: string
```

**Parameters:**

* `ent_name` (`string|nil`): The registered technical projectile entity name

**Returns:**

* `The` (`string`): human-readable weapon or projectile description

#### `deathstats.get_biome_at_pos`

Get biome name at a given 3D position

```lua
function deathstats.get_biome_at_pos(pos: Vector|nil)
  -> biome_name: string
```

**Parameters:**

* `pos` (`Vector|nil`): The position to query

**Returns:**

* `biome_name` (`string`): Clean formatted biome name

#### `deathstats.get_depth_description`

Describe elevation/depth zone for the death location

```lua
function deathstats.get_depth_description(y: number|nil)
  -> depth_desc: string
```

**Parameters:**

* `y` (`number|nil`): The vertical elevation

**Returns:**

* `depth_desc` (`string`): Human-readable depth or altitude description

#### `deathstats.get_funny_note`

Pick a random humorous epitaph note for the given death category

```lua
function deathstats.get_funny_note(category: string)
  -> note: string
```

**Parameters:**

* `category` (`string`): The death category identifier (e.g. "pvp", "mob", "fall", "lava", etc.)

**Returns:**

* `note` (`string`): A randomized witty or humorous epitaph quote

#### `deathstats.get_player_hydration`

Get player current hydration and thirst stats across supported thirst mods

```lua
function deathstats.get_player_hydration(player: ObjectRef)
  -> current: number?
  2. max: number?
  3. ratio: number?
  4. source: string?
  5. is_dehydrated: boolean?
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

**Returns:**

* `current` (`number?`): Current thirst value
* `max` (`number?`): Maximum thirst value
* `ratio` (`number?`): Hydration ratio (0.0 - 1.0)
* `source` (`string?`): Identification of originating thirst mod
* `is_dehydrated` (`boolean?`): True if thirst value is critical (<= 1)

#### `deathstats.get_player_satiation`

Get player current satiation and hunger stats across supported hunger mods

```lua
function deathstats.get_player_satiation(player: ObjectRef)
  -> current: number?
  2. max: number?
  3. ratio: number?
  4. source: string?
  5. is_starving: boolean?
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

**Returns:**

* `current` (`number?`): Current hunger value
* `max` (`number?`): Maximum hunger value
* `ratio` (`number?`): Satiation ratio (0.0 - 1.0)
* `source` (`string?`): Identification of originating hunger mod
* `is_starving` (`boolean?`): True if hunger value is critical (<= 1)

#### `deathstats.inspect_surroundings_fallback`

Deep environmental and state inspection fallback when engine reason table is nil or incomplete
 Checks recent combat punches, falling velocity, surrounding nodes (lava, water, suffocation, fall, out-of-world)

```lua
function deathstats.inspect_surroundings_fallback(player: ObjectRef)
  -> analysis: table
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object

**Returns:**

* `analysis` (`table`): The deduced death information table

#### `deathstats.is_mob_entity`

Validate whether an entity is a genuine living mob (monster, animal, npc)
 Rejects projectiles, falling nodes, items, boats/carts, and internal utility entities

```lua
function deathstats.is_mob_entity(ent_name: string, ent_def: table|nil, ent_instance: table|nil)
  -> is_mob: boolean
```

**Parameters:**

* `ent_name` (`string`): Technical registered entity name
* `ent_def` (`table|nil`): Entity definition table
* `ent_instance` (`table|nil`): Living LuaEntity instance

**Returns:**

* `is_mob` (`boolean`): True if the entity is a valid mob

#### `deathstats.is_player_dehydrated`

Check if player is currently dehydrated

```lua
function deathstats.is_player_dehydrated(player: ObjectRef)
  -> is_dehydrated: boolean
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

**Returns:**

* `is_dehydrated` (`boolean`): True if player is dehydrated

#### `deathstats.is_player_sprint_exhausted`

Check if player is exhausted from sprinting

```lua
function deathstats.is_player_sprint_exhausted(player: ObjectRef)
  -> is_exhausted: boolean
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

**Returns:**

* `is_exhausted` (`boolean`): True if stamina/exhaustion threshold is reached

#### `deathstats.is_player_starving`

Check if player is currently starving

```lua
function deathstats.is_player_starving(player: ObjectRef)
  -> is_starving: boolean
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

**Returns:**

* `is_starving` (`boolean`): True if player is starving

#### `deathstats.resolve_entity_info`

Extract name and description from an ObjectRef (Player, LuaEntity, or projectile)
 Resolves real shooting player if entity is an arrow or sword projectile

```lua
function deathstats.resolve_entity_info(obj: ObjectRef)
  -> name: string
  2. is_player: boolean
  3. entity_desc: string
  4. projectile_name: string|nil
```

**Parameters:**

* `obj` (`ObjectRef`): The attacker object reference

**Returns:**

* `name` (`string`): The killer's identifier or username
* `is_player` (`boolean`): True if the resolved attacker is a player
* `entity_desc` (`string`): The human-readable title of the killer
* `projectile_name` (`string|nil`): The projectile entity name if launched remotely

#### `deathstats.resolve_puncher_player`

Extract the real player or entity behind an attack, punch, or projectile
 Supports direct player punch, x_bows arrows, x_obsidianmese sword projectiles, and standard projectile mods

```lua
function deathstats.resolve_puncher_player(puncher: ObjectRef|nil)
  -> real_attacker: ObjectRef|nil
  2. is_player: boolean
  3. projectile_name: string|nil
  4. weapon_name: string|nil
```

**Parameters:**

* `puncher` (`ObjectRef|nil`): The raw puncher object passed to on_punchplayer

**Returns:**

* `real_attacker` (`ObjectRef|nil`): The actual player or mob entity responsible for the attack
* `is_player` (`boolean`): True if the attacker was a player (either directly or via shooting a projectile)
* `projectile_name` (`string|nil`): The registered entity name of the projectile if fired from distance
* `weapon_name` (`string|nil`): The technical item name of the wielded weapon used by a player

---

## Ragdoll & Terrain Physics API

Procedural ragdoll kinematics, impulse forces, bounce restitution, terrain slope detection, downhill rolling, wall clearance, and ground support probing.

#### `deathstats.aim_camera_at_bones`

Position and orient camera to point directly at the bones node, aligning the orbit center

```lua
function deathstats.aim_camera_at_bones(player: ObjectRef, bones_pos: Vector)
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `bones_pos` (`Vector`): The 3D coordinates of the bones block

#### `deathstats.apply_corpse_bounce_impact`

Apply immediate physical impact reaction to corpse limbs when colliding with ground during bounce

```lua
function deathstats.apply_corpse_bounce_impact(corpse: ObjectRef, impact_vy: number, _rebound_v: Vector, _rot: table|nil, bounce_count: number)
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `impact_vy` (`number`): Downward velocity of the impact
* `_rebound_v` (`Vector`): Resulting rebound velocity vector
* `_rot` (`table|nil`): Current rotation {x, y, z}
* `bounce_count` (`number`): Current bounce index (1 or 2)

#### `deathstats.calculate_corpse_impulse`

Calculate initial 3D linear launch velocity and angular tumbling impulse for a ragdoll corpse

```lua
function deathstats.calculate_corpse_impulse(player: ObjectRef|nil, death_info: table|nil, last_blow: table|nil)
  -> velocity: Vector
  2. rot_speed: Vector
```

**Parameters:**

* `player` (`ObjectRef|nil`): The deceased player
* `death_info` (`table|nil`): The death analysis table
* `last_blow` (`table|nil`): The recorded lethal blow data

**Returns:**

* `velocity` (`Vector`): Initial 3D velocity vector for the corpse
* `rot_speed` (`Vector`): Initial angular tumbling velocity (pitch, yaw, roll)

#### `deathstats.detect_corpse_slope_pitch`

Detect terrain slope incline along the corpse spine axis using two downward raycasts (head and pelvis)
 Returns the pitch angle in radians (matching right-handed Z-X-Y set_rotation) and adjusted contact elevation

```lua
function deathstats.detect_corpse_slope_pitch(pos: Vector, yaw: number)
  -> pitch: number
  2. target_y: number
  3. ground_found: boolean
```

**Parameters:**

* `pos` (`Vector`): Center position of the corpse
* `yaw` (`number`): Orientation yaw in radians

**Returns:**

* `pitch` (`number`): Pitch angle in radians (clamped to [-55°, +55°])
* `target_y` (`number`): Adjusted ground midpoint elevation for the corpse
* `ground_found` (`boolean`): True if valid walkable ground was probed under corpse

#### `deathstats.detect_hanging_legs`

Detect if the corpse legs are hanging over an edge, cliff, or stair drop

```lua
function deathstats.detect_hanging_legs(pos: Vector, yaw: number)
  -> hanging: boolean
```

**Parameters:**

* `pos` (`Vector`): Center position of the corpse
* `yaw` (`number`): Facing yaw of the corpse

**Returns:**

* `hanging` (`boolean`): True if pelvis is supported but legs extend over empty space

#### `deathstats.detect_wall_behind`

Detect if there is a solid walkable wall or obstruction behind the corpse

```lua
function deathstats.detect_wall_behind(pos: Vector, yaw: number)
  -> is_wall: boolean
```

**Parameters:**

* `pos` (`Vector`): Position of the corpse
* `yaw` (`number`): Facing yaw of the corpse in radians

**Returns:**

* `is_wall` (`boolean`): True if a solid node is detected behind

#### `deathstats.ensure_corpse_clearance`

Ensures corpse position does not clip into solid walkable blocks or boundaries
 Nudges wall-sitting corpses forward away from the wall behind them and resolves solid collisions

```lua
function deathstats.ensure_corpse_clearance(pos: table, yaw: number, is_wall_sitting: boolean)
  -> adjusted_pos: table
```

**Parameters:**

* `pos` (`table`): The position vector of the corpse
* `yaw` (`number`): Facing yaw of the corpse in radians
* `is_wall_sitting` (`boolean`): True if pose is wall_sit or slouch

**Returns:**

* `adjusted_pos` (`table`): Vector position cleared of solid obstructions

#### `deathstats.find_ground_surface`

Find the true ground collision surface level beneath a position
 Ensures the corpse rests directly flush on walkable terrain, slabs, stairs, or bones
 For liquid deaths (water, lava), prevents pinning to the lake bed and retains exact death position

```lua
function deathstats.find_ground_surface(pos: Vector, bones_pos: Vector|nil, death_info: table|nil)
  -> surface_y: number
```

**Parameters:**

* `pos` (`Vector`): Player or death position
* `bones_pos` (`Vector|nil`): Coordinates of bones node if placed
* `death_info` (`table|nil`): Optional death analysis information

**Returns:**

* `surface_y` (`number`): The exact Y coordinate where corpse should rest

#### `deathstats.find_player_bones`

Check if bones were placed for this player at or near death position

```lua
function deathstats.find_player_bones(player: ObjectRef, search_center: Vector|nil)
  -> pos: Vector|nil
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `search_center` (`Vector|nil`): Optional search origin (defaults to orbit_center or player pos)

**Returns:**

* `pos` (`Vector|nil`): The 3D coordinates of the placed bones node, or nil if not found

#### `deathstats.get_bones_mode`

Check if bones mod is active and configured to place/show bones

```lua
function deathstats.get_bones_mode()
  -> should_show_bones: boolean
  2. bones_mode: string
  3. has_bones_mod: boolean
```

**Returns:**

* `should_show_bones` (`boolean`): True if bones mod is active and bones_mode == "bones"
* `bones_mode` (`string`): The effective bones_mode setting ("bones", "drop", or "keep")
* `has_bones_mod` (`boolean`): True if bones mod is loaded in the world

#### `deathstats.get_fallback_ground_node`

Dynamically discover a representative ground node from core.registered_nodes using node groups
 Completely mod-agnostic; avoids hardcoding any specific mod namespace like "default:"

```lua
function deathstats.get_fallback_ground_node()
  -> node_name: string|nil
```

**Returns:**

* `node_name` (`string|nil`): Technical name of a registered walkable ground node

#### `deathstats.get_node_impact_sound`

Extract an impact sound specification from a node definition table
 Queries Luanti games and engine standard sound keys (dug, footstep, place, dig)

```lua
function deathstats.get_node_impact_sound(ndef: table|nil)
  -> sound_name: string|nil
  2. base_gain: number
  3. base_pitch: number
```

**Parameters:**

* `ndef` (`table|nil`): Node definition table

**Returns:**

* `sound_name` (`string|nil`)
* `base_gain` (`number`)
* `base_pitch` (`number`)

#### `deathstats.get_pose_elevation_offset`

Return the vertical position offset required to keep different resting poses
 (supine, prone, lateral, wall_sit, slouch) resting flat on top of the ground.
 In character.b3d lay animation (frame 166), the entity origin (0,0,0) is stationed
 along the back plane (Y min = -0.108, Y max = +0.427).
 Rotating into prone (roll = pi) inverts Y to [-0.427, +0.108], plunging the chest/face
 0.32 blocks into the ground if not offset.
 Lateral (roll = +/- pi/2) places the shoulder at -0.27, needing a +0.16 block offset.
 Wall sit and slouch maintain upright origin contact (0.0).

```lua
function deathstats.get_pose_elevation_offset(pose_type: string|nil)
  -> offset: number
```

**Parameters:**

* `pose_type` (`string|nil`): supine

**Returns:**

* `offset` (`number`): Vertical offset in nodes

#### `deathstats.get_pose_selectionbox`

Return the interaction selectionbox bounding box for a given resting pose
 to match the physical mesh contact bounds in world space.

```lua
function deathstats.get_pose_selectionbox(pose_type: string|nil)
  -> selectionbox: number[]
```

**Parameters:**

* `pose_type` (`string|nil`): supine

**Returns:**

* `selectionbox` (`number[]`): Bounding box table { minx, miny, minz, maxx, maxy, maxz }

#### `deathstats.get_terrain_downhill_dir`

Probe 3D terrain elevation surrounding the corpse to determine the true downhill slope gradient
 Works across stairs, inclines, and irregular cliffs regardless of corpse orientation.

```lua
function deathstats.get_terrain_downhill_dir(pos: Vector, base_yaw: number|nil, pitch_slope: number|nil)
  -> down_x: number
  2. down_z: number
  3. slope_angle: number
```

**Parameters:**

* `pos` (`Vector`): Center position of the corpse
* `base_yaw` (`number|nil`): Facing yaw in radians
* `pitch_slope` (`number|nil`): Pre-calculated slope pitch along the spine axis

**Returns:**

* `down_x` (`number`): Downhill direction unit vector X (0 if flat)
* `down_z` (`number`): Downhill direction unit vector Z (0 if flat)
* `slope_angle` (`number`): Slope steepness angle in radians

#### `deathstats.has_ground_support`

Check if a corpse has solid ground or liquid support beneath it
 Used to detect if blocks below a settled corpse have been dug out
 Uses integer coordinate rounding to prevent negative coordinate truncation in C++ engine
 and probes the corpse collision footprint (±0.28) so corpses on edges/slopes remain grounded

```lua
function deathstats.has_ground_support(pos: Vector)
  -> has_support: boolean
```

**Parameters:**

* `pos` (`Vector`): 3D corpse position

**Returns:**

* `has_support` (`boolean`): True if supported by walkable ground or liquid

#### `deathstats.is_in_liquid`

Check if a death position represents being in a liquid (water, lava, etc.)
 Checks death category as well as world nodes at feet, torso, and head level

```lua
function deathstats.is_in_liquid(pos: Vector, death_info: table|nil)
  -> in_liquid: boolean
```

**Parameters:**

* `pos` (`Vector`): Player death position
* `death_info` (`table|nil`): Optional death details

**Returns:**

* `in_liquid` (`boolean`): True if player died in or around liquid

#### `deathstats.is_liquid_at`

Check if a specific world position contains liquid (water, lava, or modded fluids)

```lua
function deathstats.is_liquid_at(pos: Vector)
  -> is_liquid: boolean
```

**Parameters:**

* `pos` (`Vector`): The position to check

**Returns:**

* `is_liquid` (`boolean`): True if the node is liquid

#### `deathstats.is_soft_node`

Determine whether a node surface is soft / cushioning using node groups and attributes
 Checks fall_damage_add_percent < 0, crumbly, snappy, wool, leaves, sand, soil, snowy, hay

```lua
function deathstats.is_soft_node(ndef: table|nil, node_name: string|nil)
  -> is_soft: boolean
```

**Parameters:**

* `ndef` (`table|nil`): Node definition table
* `node_name` (`string|nil`): Technical node name

**Returns:**

* `is_soft` (`boolean`)

#### `deathstats.probe_ground_elevation`

Probe surface ground elevation at a specific horizontal coordinate
 Uses raycast if available, falling back to discrete vertical node scan

```lua
function deathstats.probe_ground_elevation(probe_x: number, probe_z: number, start_y: number)
  -> elevation: number|nil
```

**Parameters:**

* `probe_x` (`number`): X position to probe
* `probe_z` (`number`): Z position to probe
* `start_y` (`number`): Reference Y position

**Returns:**

* `elevation` (`number|nil`): Ground contact Y elevation or nil if air/void

#### `deathstats.sample_corpse_ambient_light`

Samples ambient illumination of the open space around a corpse

```lua
function deathstats.sample_corpse_ambient_light(pos: table, yaw: number|nil)
  -> light: number|nil
```

**Parameters:**

* `pos` (`table`): Position vector of the corpse
* `yaw` (`number|nil`): Facing yaw in radians

**Returns:**

* `light` (`number|nil`): Ambient light value (0-14) or nil if unavailable

#### `deathstats.settle_corpse_at_rest`

Settle the corpse entity to a complete rest at its final position

```lua
function deathstats.settle_corpse_at_rest(luaent: table|ObjectRef)
```

**Parameters:**

* `luaent` (`table|ObjectRef`): The corpse Lua entity table or ObjectRef

#### `deathstats.settle_ragdoll_limbs`

Apply final limp resting fractures or organic pose angles to corpse limbs on landing

```lua
function deathstats.settle_ragdoll_limbs(corpse: ObjectRef, impact_damage: number|nil, pose_type: string|nil, hanging_legs: boolean|nil, roll_rad: number|nil)
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `impact_damage` (`number|nil`): Damage of the lethal impact
* `pose_type` (`string|nil`): Optional resting pose ("supine", "prone", "lateral")
* `hanging_legs` (`boolean|nil`): True if legs hang over a ledge/drop
* `roll_rad` (`number|nil`): Optional corpse roll angle in radians

#### `deathstats.update_ragdoll_flight_limbs`

Procedurally adjust corpse limb angles during flight with 3D aerodynamics, vertical drag & bounce shock

```lua
function deathstats.update_ragdoll_flight_limbs(corpse: ObjectRef, velocity: Vector, _base_yaw: number, bounce_shock: number|nil)
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `velocity` (`Vector`): Current velocity vector
* `_base_yaw` (`number`): Facing yaw of the corpse
* `bounce_shock` (`number|nil`): Optional active bounce shock impulse

#### `deathstats.update_ragdoll_slide_limbs`

Procedurally adjust corpse limbs while sliding along ground or tumbling down stairs/hills
 Simulates ground surface friction drag, stair step bumps, and reactive limp jostling

```lua
function deathstats.update_ragdoll_slide_limbs(corpse: ObjectRef, velocity: Vector, _base_yaw: number, bounce_shock: number|nil, slide_timer: number|nil)
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `velocity` (`Vector`): Current velocity vector
* `_base_yaw` (`number`): Facing yaw of the corpse
* `bounce_shock` (`number|nil`): Active bounce shock impulse
* `slide_timer` (`number|nil`): Accumulated sliding duration in seconds

---

## Corpse Entities & Visuals API

Corpse entity lifecycle, appearance inheritance across skin mods, bone posing, limb fractures, 3D wield items, and arrow transfers.

#### `deathstats.dissolve_corpse`

Dissolve and cleanly remove a persistent corpse with dissipation particles

```lua
function deathstats.dissolve_corpse(corpse: ObjectRef|nil)
```

**Parameters:**

* `corpse` (`ObjectRef|nil`): The corpse object reference

#### `deathstats.fracture_corpse_limbs`

Programmatically rotate corpse limbs on fall death to simulate fractured / broken bones.
 Rotates arms, legs, and head strictly along the horizontal floor plane (around local Z axis),
 guaranteeing that limbs stay flush touching the ground without lifting into the air or clipping underground.

```lua
function deathstats.fracture_corpse_limbs(corpse: ObjectRef, custom_angles: table<string, number>|nil)
  -> applied_angles: table<string, number>
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `custom_angles` (`table<string, number>|nil`): Optional map of bone names to z-axis rotation radians

**Returns:**

* `applied_angles` (`table<string, number>`): Map of bone names to applied z radians

#### `deathstats.get_corpse`

Get the active corpse entity for a player name if currently spawned

```lua
function deathstats.get_corpse(player_name: string)
  -> corpse: ObjectRef|nil
```

**Parameters:**

* `player_name` (`string`)

**Returns:**

* `corpse` (`ObjectRef|nil`): The active corpse entity or nil

#### `deathstats.get_corpse_effect_type`

Determine the appropriate particle effect for a corpse based on death cause and environment

```lua
function deathstats.get_corpse_effect_type(corpse_pos: table, death_info: table|nil)
  -> effect_type: string
```

**Parameters:**

* `corpse_pos` (`table`): The {x, y, z} position of the corpse
* `death_info` (`table|nil`): Optional death analysis table

**Returns:**

* `effect_type` (`string`): water

#### `deathstats.get_corpse_wielditem`

Get the attached wielditem entity from a corpse

```lua
function deathstats.get_corpse_wielditem(corpse: ObjectRef|nil)
  -> went: ObjectRef|nil
```

**Parameters:**

* `corpse` (`ObjectRef|nil`): The corpse entity object

**Returns:**

* `went` (`ObjectRef|nil`): The attached wielditem entity or nil

#### `deathstats.get_player_visuals`

Extract player visual characteristics (mesh, textures, visual_size, yaw) across all skin mods

```lua
function deathstats.get_player_visuals(player: ObjectRef)
  -> visuals: PlayerVisuals
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object

**Returns:**

* `visuals` (`PlayerVisuals`): Visual properties table

#### `deathstats.get_player_wield_item`

Extract the player's active wielded item name, ignoring internal camera hands

```lua
function deathstats.get_player_wield_item(player: ObjectRef)
  -> item_name: string
```

**Parameters:**

* `player` (`ObjectRef`): The player object

**Returns:**

* `item_name` (`string`): The item technical name (e.g. "default:sword_steel"), or "" if empty/hand

#### `deathstats.is_armor_dropped`

Check if 3d_armor is configured to drop or destroy armor on player death

```lua
function deathstats.is_armor_dropped(_player: any)
  -> drops: boolean
```

**Parameters:**

* `_player` (`any`)

**Returns:**

* `drops` (`boolean`): True if armor is ejected/dropped from inventory on death

#### `deathstats.is_inventory_dropped`

Check if player inventory/items are dropped or lost on death
 If false, the player keeps items in inventory, so corpse should display wielded item

```lua
function deathstats.is_inventory_dropped(player: ObjectRef|nil)
  -> dropped: boolean
```

**Parameters:**

* `player` (`ObjectRef|nil`): Optional player reference

**Returns:**

* `dropped` (`boolean`): True if items are dropped on death, false if kept

#### `deathstats.pose_corpse`

Set the corpse entity into a pose matching the active model

```lua
function deathstats.pose_corpse(corpse: ObjectRef, mesh_name: string|nil, anim_name: string|nil)
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `mesh_name` (`string|nil`): The model mesh name
* `anim_name` (`string|nil`): lay

#### `deathstats.remove_corpse`

Safely remove a corpse entity and any attached wielditem entity

```lua
function deathstats.remove_corpse(corpse: ObjectRef|nil)
```

**Parameters:**

* `corpse` (`ObjectRef|nil`): The corpse object reference

#### `deathstats.rotate_corpse_bone`

Rotate a corpse bone in 3D space (local X, Y, Z axes)
 Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)

```lua
function deathstats.rotate_corpse_bone(corpse: ObjectRef, bone_name: string, rot_vec: Vector)
  -> success: boolean
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `bone_name` (`string`): The name of the bone to rotate
* `rot_vec` (`Vector`): The rotation vector in radians (x, y, z)

**Returns:**

* `success` (`boolean`): True if the rotation was applied

#### `deathstats.rotate_corpse_bone_planar`

Rotate a corpse bone strictly along the horizontal floor plane (around local Z axis)
 Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)

```lua
function deathstats.rotate_corpse_bone_planar(corpse: ObjectRef, bone_name: string, z_rad: number)
  -> success: boolean
```

**Parameters:**

* `corpse` (`ObjectRef`): The corpse entity object
* `bone_name` (`string`): The name of the bone to rotate
* `z_rad` (`number`): The rotation angle in radians around local Z axis

**Returns:**

* `success` (`boolean`): True if the rotation was applied

#### `deathstats.spawn_and_setup_corpse`

```lua
function deathstats.spawn_and_setup_corpse(corpse_pos: Vector, visuals: table, player: ObjectRef|nil, death_info: table|nil, last_blow: table|nil, is_settled_override: boolean|nil)
  -> corpse: ObjectRef|nil
```

**Parameters:**

* `corpse_pos` (`Vector`): Position to spawn the corpse
* `visuals` (`table`): Player visuals table (mesh, textures, visual_size, yaw, ...)
* `player` (`ObjectRef|nil`): The dying player entity
* `death_info` (`table|nil`): Death metadata
* `last_blow` (`table|nil`): Last damage blow information
* `is_settled_override` (`boolean|nil`): True if corpse should spawn directly settled without launch impulses

**Returns:**

* `corpse` (`ObjectRef|nil`): The spawned corpse entity or nil if failed (e.g. mapblock not loaded)

#### `deathstats.unhide_corpse_arrows`

Unhide and restore native visual scale for any arrows attached to a corpse
 Defensively resets is_visible = true and restores visual_size if previously zeroed

```lua
function deathstats.unhide_corpse_arrows(corpse: ObjectRef|nil)
```

**Parameters:**

* `corpse` (`ObjectRef|nil`): The corpse entity object

---

## Cinematic Camera Orbit API

360-degree circular camera orbit, non-physical camera anchor, raycast obstacle clearance, bones targeting, and HUD suppression.

#### `deathstats.get_camera_orbit_pos`

Compute 3D camera eye coordinates along the orbit path around an orbit center

```lua
function deathstats.get_camera_orbit_pos(center: Vector, radius: number, height: number, angle: number)
  -> cam_pos: Vector
```

**Parameters:**

* `center` (`Vector`): 3D coordinates of the orbit center (corpse or bones)
* `radius` (`number`): Horizontal distance from center
* `height` (`number`): Vertical elevation above center
* `angle` (`number`): Orbit angle (yaw) in radians

**Returns:**

* `cam_pos` (`Vector`): 3D world position of the camera eye

#### `deathstats.hide_all_hudbars`

Hide all external HUD bars (hudbars, hunger, stamina) for a player during death sequence

```lua
function deathstats.hide_all_hudbars(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object

#### `deathstats.hook_animation_function`

Wrap an animation function to prevent death animation looping while a player is dead
 In Luanti Game (MTG) / Repixture, player_api.globalstep calls player_set_animation(player, "lay") every tick
 which defaults to loop = true at 30 fps, causing a violent 0.13s death replay loop.
 This hook forces loop = false and speed = 1 so the character cleanly stays in the final flat pose.

```lua
function deathstats.hook_animation_function(mod_table: table|nil, fn_name: string)
```

**Parameters:**

* `mod_table` (`table|nil`): The mod table containing the animation function
* `fn_name` (`string`): The name of the animation function

#### `deathstats.reset_camera`

Reset player camera back to normal first-person behavior, remove corpse, and restore player properties

```lua
function deathstats.reset_camera(player: ObjectRef, is_leaving: boolean|nil)
```

**Parameters:**

* `player` (`ObjectRef`): The player object to reset
* `is_leaving` (`boolean|nil`): True if called when player is leaving the server

#### `deathstats.restore_all_hudbars`

Restore all external HUD bars (hudbars, hunger, stamina) for a player on respawn

```lua
function deathstats.restore_all_hudbars(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The respawned player object

#### `deathstats.restore_player_inventory_and_hand`

Restore any stashed inventory and hand reach, verifying both in-memory camera data and persistent metadata.
 Used on respawn, disconnect, and joinplayer to guarantee 0% item loss and no stuck zero-reach camera hand.

```lua
function deathstats.restore_player_inventory_and_hand(player: ObjectRef)
  -> restored: boolean
```

**Parameters:**

* `player` (`ObjectRef`): The player whose inventory and hand reach should be verified and restored

**Returns:**

* `restored` (`boolean`): True if any inventory lists or hand reach were restored or sanitized

#### `deathstats.set_death_camera`

Switch player camera to death perspective (smooth circular orbit around corpse/bones)

```lua
function deathstats.set_death_camera(player: ObjectRef, death_info: table|nil)
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `death_info` (`table|nil`): Optional death analysis information table

#### `deathstats.set_engine_player_attached`

Set or clear the player_attached flag in player_api / x_player_api and default mods

```lua
function deathstats.set_engine_player_attached(name: string, attached: boolean|nil)
```

**Parameters:**

* `name` (`string`): The player name
* `attached` (`boolean|nil`): True if attached, nil to clear

#### `deathstats.update_death_camera`

Update camera position and orientation along the circular orbit

```lua
function deathstats.update_death_camera(player: ObjectRef, dtime: number)
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `dtime` (`number`): Delta time in seconds since last frame

---

## Particle Effects API

Thematic death particle spawners (lava sparks, fire smoke, water bubbles, fly swarm), ground impact dust bursts, and decay dissolution puffs.

#### `deathstats.calc_oriented_particle_bounds`

Calculates rotation-compensated particle emitter vectors for an attached entity.
 Computes the local direction matching world +Y (straight up) so that particles
 always rise upward in world space regardless of whether the corpse is prone, supine, or tilted.

```lua
function deathstats.calc_oriented_particle_bounds(rot: table|nil, min_val: number, max_val: number, spread_h: number)
  -> min_v: table
  2. max_v: table
```

**Parameters:**

* `rot` (`table|nil`): Rotation { x = pitch, y = yaw, z = roll } in radians
* `min_val` (`number`): Minimum scalar magnitude (e.g. min vertical velocity or acceleration)
* `max_val` (`number`): Maximum scalar magnitude (e.g. max vertical velocity or acceleration)
* `spread_h` (`number`): Horizontal spread magnitude

**Returns:**

* `min_v` (`table`): Vector { x, y, z }
* `max_v` (`table`): Vector { x, y, z }

#### `deathstats.create_corpse_particlespawner_def`

Create a modern ParticleSpawner definition table with graceful fallback to older Luanti clients

```lua
function deathstats.create_corpse_particlespawner_def(effect_type: string, corpse_pos: table, attached_obj: ObjectRef|nil)
  -> def: table|nil
```

**Parameters:**

* `effect_type` (`string`): water
* `corpse_pos` (`table`): The {x, y, z} position of the corpse
* `attached_obj` (`ObjectRef|nil`): Optional corpse ObjectRef to attach particles to

**Returns:**

* `def` (`table|nil`): ParticleSpawner definition table

#### `deathstats.get_node_tile_texture`

Get the primary tile texture name for a given node for particle fallback

```lua
function deathstats.get_node_tile_texture(node_name: string|nil)
  -> texture: string
```

**Parameters:**

* `node_name` (`string|nil`): Name of the node

**Returns:**

* `texture` (`string`): Name of the texture or fallback

#### `deathstats.spawn_corpse_particles`

Spawn corpse particle spawner(s) according to death cause/environment

```lua
function deathstats.spawn_corpse_particles(corpse_pos: table, death_info: table|nil, attached_obj: ObjectRef|nil)
  -> spawner_ids: number[]
  2. effect_type: string|nil
```

**Parameters:**

* `corpse_pos` (`table`): The {x, y, z} position of the corpse
* `death_info` (`table|nil`): Optional death analysis table
* `attached_obj` (`ObjectRef|nil`): Optional corpse ObjectRef to attach particles to

**Returns:**

* `spawner_ids` (`number[]`): Array of active particle spawner IDs
* `effect_type` (`string|nil`): The type of effect spawned (e.g. "water", "lava", "fire", "flies", "impact")

#### `deathstats.spawn_decay_particles`

```lua
function deathstats.spawn_decay_particles(pos: Vector)
  -> spawner_id: integer|nil
```

**Parameters:**

* `pos` (`Vector`): Center position of the decaying corpse

**Returns:**

* `spawner_id` (`integer|nil`): Particle spawner identifier or nil if disabled

#### `deathstats.spawn_impact_burst`

Spawn an instantaneous localized burst of node debris particles at the impact site

```lua
function deathstats.spawn_impact_burst(pos: Vector, ground_node_name: string|nil, intensity: number|nil)
```

**Parameters:**

* `pos` (`Vector`): The collision contact point
* `ground_node_name` (`string|nil`): The node name struck
* `intensity` (`number|nil`): Impact velocity or damage

---

## Formspecs & UI Dossier API

Interactive formspec interfaces for death summary cards, photo mode overlay, corpse epitaph inspection plaque, and lifetime achievement statistics.

#### `deathstats.calculate_slap_animation`

Calculate distance flight and screen slap animation parameters
 Uses an elastic damped sine curve trajectory for prominent zoom-in and bouncy recoil

```lua
function deathstats.calculate_slap_animation(progress: number, target_w: number|nil, target_h: number|nil)
  -> scale_x: number
  2. scale_y: number
  3. alpha: number
  4. impact_reached: boolean
```

**Parameters:**

* `progress` (`number`): Animation progress factor from 0.0 to 1.0
* `target_w` (`number|nil`): Target scale X percentage (default -32.0)
* `target_h` (`number|nil`): Target scale Y percentage (default -23.0)

**Returns:**

* `scale_x` (`number`): Calculated X dimension scale
* `scale_y` (`number`): Calculated Y dimension scale
* `alpha` (`number`): Alpha transparency level (0-255)
* `impact_reached` (`boolean`): True if animation reached or passed impact threshold

#### `deathstats.get_banner_responsive_scale`

Calculate responsive banner scale maintaining exact texture aspect ratio across any screen resolution

```lua
function deathstats.get_banner_responsive_scale(player: table|ObjectRef)
  -> scale_x: number
  2. scale_y: number
```

**Parameters:**

* `player` (`table|ObjectRef`): The player object or mock window info

**Returns:**

* `scale_x` (`number`): The calculated responsive horizontal and vertical scale
* `scale_y` (`number`): The calculated responsive horizontal and vertical scale

#### `deathstats.show_corpse_epitaph_formspec`

Show corpse epitaph tombstone plaque formspec when living players right-click a settled corpse

```lua
function deathstats.show_corpse_epitaph_formspec(clicker: ObjectRef, corpse_ref: table|ObjectRef)
```

**Parameters:**

* `clicker` (`ObjectRef`): The living player inspecting the corpse
* `corpse_ref` (`table|ObjectRef`): The corpse entity reference or luaentity table

#### `deathstats.show_death_formspec`

Display the elevated death formspec with consistent padding above hotbar area

```lua
function deathstats.show_death_formspec(player: ObjectRef, death_info: table)
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object
* `death_info` (`table`): The death analysis metadata table containing cause, killer, and notes

#### `deathstats.show_lifetime_formspec`

Display the lifetime player dossier formspec dialog (alias for show_lifetime_stats_formspec)

```lua
function deathstats.show_lifetime_formspec(player: ObjectRef, from_death_screen: boolean|nil)
```

**Parameters:**

* `player` (`ObjectRef`): Luanti player object
* `from_death_screen` (`boolean|nil`): True if launched from death screen modal

#### `deathstats.show_lifetime_stats_formspec`

Display the Lifetime Statistics Dashboard with transparent backdrop and accessible tabs

```lua
function deathstats.show_lifetime_stats_formspec(player: ObjectRef, tab: string|nil)
```

**Parameters:**

* `player` (`ObjectRef`): The player viewing statistics
* `tab` (`string|nil`): The active tab name ("overview", "records", "ores", or "combat")

#### `deathstats.show_photo_mode_formspec`

Display the elevated death formspec with consistent padding above hotbar area
 Show minimal photo mode overlay with single button to restore death UI

```lua
function deathstats.show_photo_mode_formspec(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): The deceased player object

---

## Live Scoreboard HUD API

Tactical multiplayer live scoreboard, pluggable custom columns API, real-time metrics calculation, ping/AFK status, and full roster dialog.

#### `deathstats.calculate_player_score`

Calculate an aggregate performance score across all categories for ranking
 Combines Kills, K/D Ratio, Survival (deaths factor), Damage Dealt, Armor, and HP

```lua
function deathstats.calculate_player_score(pdata: table, player: ObjectRef|nil, cached_armor: integer|nil, cached_hp: integer|nil)
  -> score: integer
  2. avg_category_score: integer
```

**Parameters:**

* `pdata` (`table`): Player statistics data table (containing lifetime counters)
* `player` (`ObjectRef|nil`): Active player object reference
* `cached_armor` (`integer|nil`): Optional pre-computed armor points
* `cached_hp` (`integer|nil`): Optional pre-computed health points

**Returns:**

* `score` (`integer`): Composite score for descending leaderboard sort
* `avg_category_score` (`integer`): Normalized average rating across all categories (0-100)

#### `deathstats.calculate_scoreboard_metrics`

Calculate responsive dimensions, line heights, and max fitting rows inspired by waysigns

```lua
function deathstats.calculate_scoreboard_metrics(player: ObjectRef|nil)
  -> metrics: table
```

**Parameters:**

* `player` (`ObjectRef|nil`): Target player

**Returns:**

* `metrics` (`table`): Layout metrics table

#### `deathstats.close_scoreboard_formspec`

Close the full scoreboard formspec for a player

```lua
function deathstats.close_scoreboard_formspec(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): Target player

#### `deathstats.format_column_headers`

Build monospaced column header string
 If screen is small, collapses to condensed format matching icons

```lua
function deathstats.format_column_headers(m: table)
  -> col_header_str: string
```

**Parameters:**

* `m` (`table`): Metrics table

**Returns:**

* `col_header_str` (`string`): Formatted header text

#### `deathstats.format_player_row`

Format a single player row into perfectly aligned monospaced columns
 All columns have bounded value widths to guarantee fixed total character length
 All data cells are left-aligned directly underneath the column headers

```lua
function deathstats.format_player_row(item: table, m: table)
  -> row_str: string
```

**Parameters:**

* `item` (`table`): Player scoreboard entry
* `m` (`table`): Metrics table

**Returns:**

* `row_str` (`string`): Formatted row string

#### `deathstats.format_survival_time`

Format active survival duration into a compact human-readable string

```lua
function deathstats.format_survival_time(sec: number, is_small: boolean|nil)
  -> time_str: string
```

**Parameters:**

* `sec` (`number`): Duration in seconds
* `is_small` (`boolean|nil`): Whether to format for small display

**Returns:**

* `time_str` (`string`): Formatted time string (e.g. "45s", "14m 20s", "2h 10m")

#### `deathstats.get_gametime_formatted`

Format the current in-game day/night cycle into a human-readable digital clock string

```lua
function deathstats.get_gametime_formatted(format: string|nil)
  -> time_str: string
```

**Parameters:**

* `format` (`string|nil`): Optional format ("24h" or "12h"). Defaults to mod setting.

**Returns:**

* `time_str` (`string`): Formatted in-game time (e.g. "19:30" or "07:30 PM")

#### `deathstats.get_hall_of_fame_data`

Get the All-Time Hall of Fame players list sorted by lifetime composite score

```lua
function deathstats.get_hall_of_fame_data()
  -> list: table
```

**Returns:**

* `list` (`table`): Sorted list of all-time player dossiers

#### `deathstats.get_ordered_scoreboard_columns`

Query active registered scoreboard columns sorted by their order attribute

```lua
function deathstats.get_ordered_scoreboard_columns()
  -> columns: table
```

**Returns:**

* `columns` (`table`): Sorted array of column definition tables

#### `deathstats.get_ping_color`

Evaluate color threshold for ping latency (numeric HUD RGB)

```lua
function deathstats.get_ping_color(ping: integer)
  -> color: integer
```

**Parameters:**

* `ping` (`integer`): Network round-trip latency in milliseconds

**Returns:**

* `color` (`integer`): RGB color (green, yellow, or red)

#### `deathstats.get_ping_textcolor`

Evaluate formspec text color string for ping latency

```lua
function deathstats.get_ping_textcolor(ping: integer)
  -> color_str: string
```

**Parameters:**

* `ping` (`integer`): Network round-trip latency in milliseconds

**Returns:**

* `color_str` (`string`): Hex color string

#### `deathstats.get_player_armor_points`

Query player armor defense points across all supported Luanti armor mods and engine groups
 Supports 3d_armor (level), mcl_armor (armor_points), hbarmor, and engine fleshy group fallbacks

```lua
function deathstats.get_player_armor_points(player: ObjectRef|nil)
  -> points: integer
```

**Parameters:**

* `player` (`ObjectRef|nil`): The player object to inspect

**Returns:**

* `points` (`integer`): Total effective armor defense points (0-100+)

#### `deathstats.get_player_hp`

Get current health points safely

```lua
function deathstats.get_player_hp(player: ObjectRef|nil)
  -> hp: integer
```

**Parameters:**

* `player` (`ObjectRef|nil`): The player object

**Returns:**

* `hp` (`integer`): Current health points

#### `deathstats.get_player_ping`

Query round-trip network ping latency in milliseconds for a connected player

```lua
function deathstats.get_player_ping(player_name: string)
  -> ping: integer
```

**Parameters:**

* `player_name` (`string`): Username of the target player

**Returns:**

* `ping` (`integer`): Latency in milliseconds (0 for local or unavailable)

#### `deathstats.get_player_row_cells`

Get formatted cell strings for all columns of a player row
 Iterates over m.columns and invokes each column's get_value callback

```lua
function deathstats.get_player_row_cells(item: table, m: table)
  -> cells: table
```

**Parameters:**

* `item` (`table`): Player scoreboard entry
* `m` (`table`): Metrics table

**Returns:**

* `cells` (`table`): Array of cell strings

#### `deathstats.get_player_window_size`

Get player window size and display scaling parameters safely

```lua
function deathstats.get_player_window_size(player: ObjectRef|nil)
  -> screen_w: integer
  2. screen_h: integer
  3. hud_scaling: number
```

**Parameters:**

* `player` (`ObjectRef|nil`): Target player

**Returns:**

* `screen_w` (`integer`): Screen width in pixels (default 1280)
* `screen_h` (`integer`): Screen height in pixels (default 720)
* `hud_scaling` (`number`): Client HUD scaling factor

#### `deathstats.get_scoreboard_bg_texture`

Generate a composite texture string for the tactical scoreboard plaque
 Combines dark translucent panel, glowing border, header divider, column header strip, table grid, icons, and status indicators

```lua
function deathstats.get_scoreboard_bg_texture(m: table, viewer_row_idx: integer|nil, _entries: table|nil)
  -> texture: string
```

**Parameters:**

* `m` (`table`): Metrics table from calculate_scoreboard_metrics
* `viewer_row_idx` (`integer|nil`): 1-based index of the viewer's row within visible rows
* `_entries` (`table|nil`): Visible player entry tables for row status icons

**Returns:**

* `texture` (`string`): Composite Luanti texture spec

#### `deathstats.get_scoreboard_cell_color`

Determine HUD text color for a scoreboard cell based on column config or player state

```lua
function deathstats.get_scoreboard_cell_color(col: table, player: ObjectRef, item: table, row_idx: integer)
  -> color: integer
```

**Parameters:**

* `col` (`table`): Column definition
* `player` (`ObjectRef`): Target viewer player
* `item` (`table`): Row player entry data
* `row_idx` (`integer`): 1-based row index

**Returns:**

* `color` (`integer`): HUD numeric color

#### `deathstats.get_scoreboard_columns`

Compute column layout specifications spanning the full usable width of the scoreboard plaque
 Pulls dynamically from registered columns and normalizes relative widths

```lua
function deathstats.get_scoreboard_columns(board_w: integer, is_small: boolean, hud_scale: number)
  -> columns: table
  2. pad_x: integer
  3. usable_w: integer
```

**Parameters:**

* `board_w` (`integer`): Total plaque width in pixels
* `is_small` (`boolean`): Whether small-screen condensed mode is active
* `hud_scale` (`number`): Active HUD scaling factor

**Returns:**

* `columns` (`table`): Ordered array of column definitions
* `pad_x` (`integer`): Left/right padding in pixels
* `usable_w` (`integer`): Usable table width in pixels

#### `deathstats.get_scoreboard_data`

Hooked scoreboard data provider: merges real connected players with mock entries

```lua
function deathstats.get_scoreboard_data(viewer_player: ObjectRef|nil, precomputed_base: table|nil)
  -> entries: table
```

**Parameters:**

* `viewer_player` (`ObjectRef|nil`): The viewing player
* `precomputed_base` (`table|nil`): Optional pre-gathered and pre-sorted player base entries

**Returns:**

* `entries` (`table`): Sorted, ranked player entry list

#### `deathstats.get_scoreboard_footer_text`

Generate footer hint string for the live scoreboard HUD overlay

```lua
function deathstats.get_scoreboard_footer_text(total_count: integer, visible_count: integer)
  -> footer_str: string
```

**Parameters:**

* `total_count` (`integer`): Total connected / mock player count
* `visible_count` (`integer`): Count of players currently displayed in HUD

**Returns:**

* `footer_str` (`string`): Formatted footer text

#### `deathstats.hide_scoreboard_hud`

Hide and remove all active scoreboard HUD elements for a player

```lua
function deathstats.hide_scoreboard_hud(player: string|ObjectRef, keep_chat_state: boolean|nil)
```

**Parameters:**

* `player` (`string|ObjectRef`): Target player object or player name
* `keep_chat_state` (`boolean|nil`): If true, keeps chat state untouched (e.g. during immediate re-show)

#### `deathstats.is_player_afk`

Check if a player is currently AFK (away from keyboard)

```lua
function deathstats.is_player_afk(player_or_name: string|ObjectRef)
  -> is_afk: boolean
```

**Parameters:**

* `player_or_name` (`string|ObjectRef`): The player object or username

**Returns:**

* `is_afk` (`boolean`): True if inactive duration exceeds afk_timeout setting

#### `deathstats.is_scoreboard_key_down`

Determine if the player is currently holding the scoreboard activation key/combination
 Supports "zoom", "sneak+aux1", "aux1", "sneak", or custom combinations

```lua
function deathstats.is_scoreboard_key_down(player: ObjectRef, key_setting: string|nil, ctrl: table|nil)
  -> is_down: boolean
```

**Parameters:**

* `player` (`ObjectRef`): Target player
* `key_setting` (`string|nil`): Optional key config string
* `ctrl` (`table|nil`): Optional pre-fetched player control table

**Returns:**

* `is_down` (`boolean`): True if all configured keys are currently pressed

#### `deathstats.orig_get_scoreboard_data`

```lua
function
```

#### `deathstats.register_scoreboard_column`

Register or override a scoreboard column definition

```lua
function deathstats.register_scoreboard_column(id: string, def: table)
```

**Parameters:**

* `id` (`string`): Unique identifier for the column (e.g. "kills", "damage", "ping")
* `def` (`table`): Column definition specification (order, title, pct, min_w, icon, get_value, get_color)

#### `deathstats.show_scoreboard_formspec`

Display the full scrollable formspec scoreboard table with all players

```lua
function deathstats.show_scoreboard_formspec(player: ObjectRef, tab: string|nil)
```

**Parameters:**

* `player` (`ObjectRef`): Target player
* `tab` (`string|nil`): Optional tab ("live" or "hall_of_fame"). Defaults to "live".

#### `deathstats.show_scoreboard_hud`

Display or initialize the 2D HUD Scoreboard overlay for a player
 Centered at position={x=0.5, y=0.5} with z_index=1000 and monospaced style=1

```lua
function deathstats.show_scoreboard_hud(player: ObjectRef, precomputed_entries: table|nil)
```

**Parameters:**

* `player` (`ObjectRef`): The player holding the activation key
* `precomputed_entries` (`table|nil`): Optional pre-calculated scoreboard entries

#### `deathstats.unregister_scoreboard_column`

Unregister an existing scoreboard column by id

```lua
function deathstats.unregister_scoreboard_column(id: string)
```

**Parameters:**

* `id` (`string`): Unique column identifier

#### `deathstats.update_scoreboard_hud`

Update existing scoreboard HUD overlay elements with live changes (diff-based)
 Only changes fields that modified (time, stats, ping) to eliminate network lag

```lua
function deathstats.update_scoreboard_hud(player: ObjectRef, precomputed_entries: table|nil)
```

**Parameters:**

* `player` (`ObjectRef`): Target player
* `precomputed_entries` (`table|nil`): Optional pre-calculated scoreboard entries

---

## Registries & State Tables

| Registry / Table | Type | Description |
| :--- | :--- | :--- |
| `deathstats.compat_hudbars` | `table` |  Compatibility layer hooks for hudbars mod and extensions (hbhunger, hbarmor, hbsprint) |
| `deathstats.compat_hunger` | `table<string, any>` |  Compatibility layer hooks and HUD states for external hunger, thirst, and stamina frameworks |
| `deathstats.compat_skins` | `table<string, any>` |  Compatibility layer hooks and texture resolvers for player skins and appearance frameworks |
| `deathstats.fall_peaks` | `table<string, number>` |  Highest recorded elevations during airborne falls for fatal fall distance tracking |
| `deathstats.funny_notes` | `table` |  Funny epitaph notes organized by death cause (all wrapped in S() for translation) |
| `deathstats.hooked_animations` | `table` |  Set of hooked external animation functions to prevent death replay looping |
| `deathstats.is_shutting_down` | `boolean` |  Server shutdown flag used to suppress redundant cleanup logic |
| `deathstats.mock_players_data` | `table` |  Default template list of mock players with diverse names, combat records, and network latencies |
| `deathstats.mock_scoreboard_enabled` | `boolean` |  Whether mock player records are injected into the live scoreboard |
| `deathstats.mock_scoreboard_player_count` | `nil` |  Target count of mock players to simulate on scoreboard (nil for all)  nil means all mock players |
| `deathstats.recent_explosions` | `table` |  Recent in-world explosion events tracked for fatal blast attribution |
| `deathstats.scoreboard_bg_cache` | `table<string, string>` |  Cached background formspec texture strings keyed by layout dimensions |
