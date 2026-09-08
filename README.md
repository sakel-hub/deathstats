# DeathStats for Luanti

A cinematic, pixel art-themed death screen and lifetime player statistics mod for Luanti.

![YOU DIED](textures/deathstats_you_died.png)

## Features

- **Cinematic Death Presentation**:
  - **Dynamic Thematic Banners & Vignette Overlays**:
    The "YOU DIED" banner typography and fullscreen vignette backdrop dynamically adapt to the cause of death:
    - **Lava / Magma**: Molten glowing lava banner (`deathstats_you_died_lava.png`) and intense magma splatter with fiery embers vignette (`deathstats_lava_splatter.png`).
    - **Fire / Burning**: Burning scorched flame banner (`deathstats_you_died_fire.png`) and charred ash smoke with flame splatter vignette (`deathstats_fire_splatter.png`).
    - **Drowning / Water**: Submerged waterlogged banner (`deathstats_you_died_drown.png`) and underwater splash droplets with aquatic blue vignette (`deathstats_drown_splatter.png`).
    - **Combat, Fall, Starvation, Suffocation, Void & Generic**: Iconic dripping crimson blood banner (`deathstats_you_died.png`) and visceral blood splatter with dark vignette (`deathstats_blood_splatter.png`).
  - Visceral "slapped on screen from distance" animation: accelerates forward from distant perspective, impacts the screen glass with an overshoot bounce, settling firmly into view with synchronous subtitle reveal.
  - Dynamic camera perspective:
    - **Smooth Circular Orbit**: Smoothly orbits around the fallen player corpse or bones block in a circular path in first-person mode, eliminating third-person camera offsets.
    - **Corpse Placeholder Entity**: Spawns an immortal, non-physical corpse mesh entity lying flat on the ground that inherits the player's exact character model, wielditem, and composite skins across 13+ appearance mods (`skinsdb`, `3d_armor`, `clothing`, `player_api`, `mcl_skins`, `simple_skins`, `wardrobe`, `edit_skin`, `collectible_skins`, `myappearance`, `nc_skins`, `u_skins`, `csm_skins`).
    - **Atmospheric Corpse Particles**: Spawns natural particle effects from the corpse:
      - **Water**: continuous animated bubbling air bubbles (5x5 px pixel art) floating upward through water.
      - **Lava**: continuous animated licking fire & ember sparks (5x5 px pixel art) leaping with high glow.
      - **Fire**: continuous animated billowing ash smoke (5x5 px pixel art) drifting upward.
      - **All Others**: dynamic burst of surface node particles flying upward from ground impact at the moment of death with customized gravity and velocity.
    - **Obstacle Avoidance**: Raycasts line-of-sight between camera and corpse, dynamically pulling camera in front of solid walls to eliminate clipping.
    - **Bones Mod Compatibility**: Respects `bones_mode` setting. When `bones_mode == "bones"`, suppresses the corpse entity so the placed bones block is directly visible and fully functional (retaining stored inventory and item drop mechanics), automatically locking camera orbit directly onto the bones. When `bones` is disabled or in `drop`/`keep` mode, falls back to the cinematic corpse entity.
    - **Early Item Drops**: If the game drops inventory on death (`bones_mode == "drop"`, etc.), items scatter around the death position with randomized velocity right as the orbit begins.
  - Clean cinematic display: in-game hotbar and HUDs automatically hidden during death.

- **Intelligent Death Cause & Weapon Detection**:
  - Identifies killers (players or mobs), weapon/tool used for the killing blow (swords, tools, bare hands).
  - Full projectile & ranged weapon attribution: tracks kills and damage from arrows (`x_bows`), sword projectiles (`x_obsidianmese`), and custom ranged weapons directly to the shooter player.
  - Full mob combat damage tracking: tracks all damage dealt to mobs across `mobs_redo`, `creatura`, and custom entities.
  - Robust fallback environmental inspection when engine `reason` is `nil` or generic: detects drowning (breath/water), lava melting, burning in fire, falling impact velocity, suffocation in solid blocks, falling into the void, hunger starvation, and dehydration.
  - **Hunger & Thirst Integration**: Seamlessly detects starvation and dehydration deaths across popular hunger and thirst frameworks including `hbhunger`, `hudbars`, `stamina`, `hunger_ng`, `mcl_hunger`, `thirsty`, and `unified_stamina` (even when damage is applied via generic `set_hp` calls).
  - Hilarious, curated epitaph notes for every cause of death in high-contrast white text.

- **Interactive Death Interface (Modern Formspec v6)**:
  - **Try Again**: Instant respawn, clean HUD removal, and camera restore.
  - **Side-Docked Last Life Card**: Compact summary displaying time survived, blocks mined, total ores mined, damage dealt & taken with clear labels, mobs & players slain, items crafted & consumed, and distance traveled. Positioned neatly on the side of the screen so the fallen player model and death location remain completely unobstructed.
  - **More Statistics (Lifetime Dossier)**: Comprehensive interactive dashboard with transparent backdrop and accessible tab styling, persistent across server restarts using Luanti's Mod Storage:
    - **Overview Tab**: Total playtime, total deaths, K/D ratio, damage statistics, building and survival records.
    - **Ores Breakdown Tab**: Dynamic scrollable 2-column grid showing every single ore variety extracted with item icons, exact counts, and sorted rankings.
    - **Combat & Mobs Tab**: Dynamic scrollable 2-column grid of mobs and players slain with individual kill counts.

## Configuration

The following options can be customized in `minetest.conf` or the in-game Settings menu:
- `deathstats_enable_sounds = true` (toggle death sound effects)
- `deathstats_enable_camera = true` (toggle cinematic camera orbit on death)
- `deathstats_orbit_radius = 3.2` (orbit circle radius in nodes)
- `deathstats_orbit_height = 1.5` (orbit camera height above corpse in nodes)
- `deathstats_orbit_speed = 0.4` (orbit rotation speed in rad/s, ~15.7s for full circle)
- `deathstats_enable_animation = true` (toggle zoom & fade animation)
- `deathstats_animation_duration = 2.4` (duration of screen slap animation in seconds)
- `deathstats_blood_opacity = 240` (opacity of fullscreen splatter vignette overlay across all death causes, 0-255)
- `deathstats_formspec_side = right` (`right`, `left`, or `center` screen alignment)

- **Sound Effects**:
  - Plays authentic CC0 human death sound effects from Freesound picked at random on death (expressive death groans and hurt sounds by kreha). Automatically randomized across 5 engine audio variants (`deathstats_death.1.ogg` through `deathstats_death.5.ogg`).

- **Multiplayer Performance**:
  - High performance, memory-efficient in-memory tracking ($O(1)$ operations).
  - Asynchronous / zero-lag Mod Storage persistence upon death, disconnect, and server shutdown.
  - Clean fallbacks for all engine versions.

## Sound Credits (Freesound CC0 / Public Domain)
- `deathstats_death.1.ogg` – `deathstats_death.5.ogg`: by kreha (CC0, [Freesound](https://freesound.org/people/kreha))

## Testing

DeathStats includes automated unit tests covering death reason analysis, live stat tracking, formspec layouts, corpse mechanics, hunger/thirst compatibility, appearance synchronization, and reconnect persistence:

```bash
lua test.lua
```

## License
- **Code**: LGPL-2.1 or later (C) 2026 SaKeL
- **Textures & Art**: CC0 / Public Domain
- **Sounds**: CC0 / Public Domain

