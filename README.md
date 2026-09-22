# DeathStats for Luanti

[![AI Assisted](https://www.aihonestybadge.com/badges/ai-assisted.svg)](https://www.aihonestybadge.com)

A cinematic death screen, ragdoll physics, and player statistics mod for Luanti.

![YOU DIED](screenshot.png)

When you die in Luanti, DeathStats turns what used to be an instant respawn prompt into a cinematic moment. An orbiting camera circles your fallen character as ragdoll physics take over, custom banners and screen splatters react to how you met your end, and an on-screen dossier tallies everything you did during that life.

---

## What It Does

### Cinematic Death Sequence
- **Reactive Death Banners & Splatters**: The "YOU DIED" banner and fullscreen screen splatter adapt to your cause of death:
  - **Lava**: Glowing magma banner with embers and lava splatter.
  - **Fire**: Scorched flame banner with smoke and ash.
  - **Drowning**: Waterlogged typography with submerged droplet vignettes and rising bubbles.
  - **Combat, Falls & Hazards**: Classic blood banner with crimson splatter.
- **Smooth Orbiting Deathcam**: Automatically circles the fallen character in first-person mode with built-in raycast wall avoidance so the camera never clips into solid blocks.
- **Photo Mode**: Click the on-screen camera icon (or type `/stats photo`) to hide all UI elements and frame unobstructed screenshots.
- **Vocal Death Audio**: Plays random CC0 death groans and hurt sounds on impact.

### Procedural Ragdoll Corpses
- **Impulse from Fatal Blows**: Explosions launch and tumble corpses across the ground, long falls pancake on impact, and passive deaths (poison, starvation, suffocation) slump in place.
- **Dynamic Terrain Awareness**: Bodies slide down slopes steeper than 28°, match the incline of stairs, and settle into organic resting poses (face-down, face-up, on their side, or sitting propped against a wall).
- **Appearance & Gear Sync**: Accurately inherits your skin, equipped armor, wielded item, and custom humanoid meshes across popular skin frameworks (`skinsdb`, `3d_armor`, `clothing`, `player_api`, `mcl_skins`, etc.).
- **Bones Mod Compatible**: When `bones_mode = "bones"` is active, DeathStats docks directly onto the placed bones block so inventory drops remain fully functional.

### Corpse Persistence & Epitaphs
- **World Persistence**: Corpses remain resting in the world for a few minutes (configurable, default: 3 minutes) before dissolving away with an ash smoke puff.
- **Inspectable Epitaph Plaques**: Other players can right-click any corpse to view a summary plaque with survival time, death cause, killer name, and a humorous epitaph note.
- **Tidy Worlds**: Automatically limits each player to one active corpse at a time to prevent server clutter.

### Cause-of-Death Tracking & Nemesis Revenge
- **Intelligent Attribution**: Identifies killers, weapons, and ranged projectile attacks (`x_bows` arrows, spells).
- **Environmental Fallbacks**: Detects falls, drowning, fire, lava, suffocation, void falls, and starvation/dehydration frameworks (`hbhunger`, `stamina`, `thirsty`, `unified_stamina`).
- **Vendetta & Revenge Bounties**: Getting slain by another player marks them as your active nemesis. Slaying them during your next life triggers a revenge broadcast and unlocks the `[RVNG]` Avenger title badge.

### Lifetime Dossier (`/stats`)
- **Active Life Summary**: Displays survival duration, mined ores, combat damage dealt/taken, kills, crafted items, and distance traveled.
- **Interactive Lifetime Dashboard**: Persistent stats saved in Mod Storage across server restarts:
  - **Overview**: Playtime, K/D ratio, deaths, total damage, survival records.
  - **Ores Breakdown**: Full breakdown of every ore type mined with counts and icons.
  - **Combat & Mobs**: Kill counts for every mob species and player slain.
  - **Hall of Fame**: Server leaderboards for kills, survival time, and mining.

### Tactical Multiplayer Scoreboard
- **Hold-to-View HUD Overlay**: Press and hold **Sneak + Aux1** (or configure to **Zoom**) to display a live scoreboard overlay without opening a blocking dialog.
- **Live Metrics**: Shows Player Name, Kills, Deaths, K/D, Damage, Mined Blocks, Survival Time, Armor, Health, and Color-Coded Ping.
- **AFK & Status Icons**: Displays skull icons for dead players and Zzz icons for AFK players.
- **Roster Dialog**: Use `/scores` (or `/deathstats scores`) to open a full scrollable formspec table.
- **Pluggable Column API**: Other mods can register custom columns using `deathstats.register_scoreboard_column(id, def)`.

---

## Scoreboard Extension Example

```lua
-- Add a custom column to the scoreboard
if deathstats and deathstats.register_scoreboard_column then
    deathstats.register_scoreboard_column("coins", {
        order = 65,
        title = "COINS",
        title_small = "C",
        pct = 0.08,
        min_w = 45,
        icon = "deathstats_icon_star.png",
        tooltip = "Coins collected",
        get_value = function(player, item, is_small)
            return tostring(my_economy.get_coins(item.name) or 0)
        end,
        get_color = function(player, item)
            return 0xFFD700 -- Gold
        end,
    })
end
```

---

## Configuration

Settings can be changed in the in-game Settings menu or in `luanti.conf`:

| Setting | Default | Description |
|---|---|---|
| `deathstats_enable_camera` | `true` | Orbiting deathcam |
| `deathstats_orbit_radius` | `3.2` | Camera distance from corpse (nodes) |
| `deathstats_orbit_height` | `1.5` | Camera height above corpse (nodes) |
| `deathstats_orbit_speed` | `0.4` | Orbit rotation speed in rad/s |
| `deathstats_enable_corpse_ragdoll` | `true` | Ragdoll physics on death |
| `deathstats_ragdoll_force_multiplier`| `1.0` | Velocity multiplier for fatal blow knockback |
| `deathstats_ragdoll_restitution` | `0.25` | Bounce elasticity on hard surfaces |
| `deathstats_ragdoll_resting_poses` | `true` | Poses: prone, supine, lateral, and wall sitting |
| `deathstats_enable_slope_pitch` | `true` | Aligns corpse pitch to hills and stairs |
| `deathstats_corpse_decay_time` | `180` | Seconds corpses remain in world (0 for immediate) |
| `deathstats_enable_corpse_inspect` | `true` | Right-click corpses to inspect epitaph plaques |
| `deathstats_enable_revenge` | `true` | Nemesis vendetta and revenge bounty tracking |
| `deathstats_announce_revenge` | `true` | Broadcast revenge kills to server chat |
| `deathstats_enable_scoreboard` | `true` | Hold-to-view scoreboard HUD and `/scores` |
| `deathstats_scoreboard_key` | `sneak_aux1` | Activation key (`sneak_aux1`, `zoom`, `aux1`, `sneak`) |
| `deathstats_time_format` | `24h` | Time format on scoreboard header (`24h` or `12h`) |
| `deathstats_afk_timeout` | `120` | Inactivity seconds before showing AFK status |
| `deathstats_chat_death_coords` | `true` | Whispers death coords and biome upon respawn |
| `deathstats_blood_opacity` | `240` | Screen vignette opacity (0-255) |
| `deathstats_formspec_side` | `right` | Death stats card screen position (`right`, `left`, `center`) |

---

## Performance

DeathStats is built from the ground up to keep server ticks and network bandwidth light:
- **Bandwidth Throttling**: Ragdoll flailing updates are capped to 10 Hz in flight and 5 Hz on ground slides. Bone rotations ignore micro-movements smaller than 2.8° to avoid packet flooding.
- **Zero-Cost Sleep**: Once a corpse stops moving, it enters an idle rest state and disables all raycasts and collision calculations.
- **Chunk Safety**: Fluid drag and node checks use safe, non-loading queries to avoid pulling unloaded mapblocks into memory.

---

## Testing

DeathStats comes with an extensive automated test suite:

```bash
luacheck .
lua test.lua
```


---

## License & Credits

- **Code**: LGPL-2.1 or later © 2026 SaKeL
- **Textures & Icons**: CC0 / Public Domain
- **Sounds**: CC0 by kreha ([Freesound](https://freesound.org/people/kreha))
