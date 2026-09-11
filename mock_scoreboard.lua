--[[
    deathstats - Mock Scoreboard Data for Testing
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.

    This file provides realistic multi-player mock data for testing
    the tactical HUD scoreboard and scrollable formspec roster.

    Usage:
      Include in init.lua or scoreboard.lua:
        dofile(deathstats.modpath .. "/mock_scoreboard.lua")

      Or enable via luanti.conf:
        deathstats_mock_scoreboard = true

      Or toggle live in-game with chatcommand:
        /mockscores [on|off|toggle|<count>]
        /deathstats mock [on|off|<count>]
--]]

local S = core.get_translator(core.get_current_modname())

deathstats.mock_scoreboard_enabled = true
deathstats.mock_scoreboard_player_count = nil -- nil means all mock players

-- Default template list of mock players with diverse names, combat records, and network latencies
deathstats.mock_players_data = {
    { name = "Viper_99",        pvp = 18, pve = 20, kills = 38, deaths = 4,  armor = 75,  hp = 20, ping = 14,  dmg = 820, mined = 420, time = 3600 },
    { name = "ShadowNinja",     pvp = 14, pve = 15, kills = 29, deaths = 6,  armor = 60,  hp = 0,  ping = 28,  dmg = 610, mined = 350, time = 2900, is_dead = true },
    { name = "FragMaster",      pvp = 15, pve = 10, kills = 25, deaths = 11, armor = 45,  hp = 16, ping = 22,  dmg = 540, mined = 280, time = 2400 },
    { name = "MeseDragon",      pvp = 12, pve = 10, kills = 22, deaths = 10, armor = 65,  hp = 20, ping = 38,  dmg = 490, mined = 310, time = 2200 },
    { name = "PixelQueen",      pvp = 10, pve = 11, kills = 21, deaths = 8,  armor = 55,  hp = 20, ping = 45,  dmg = 480, mined = 510, time = 2100, is_afk = true },
    { name = "ShadowHunter",    pvp = 10, pve = 10, kills = 20, deaths = 7,  armor = 55,  hp = 19, ping = 34,  dmg = 440, mined = 290, time = 2000 },
    { name = "CyberGhost",      pvp = 9,  pve = 10, kills = 19, deaths = 5,  armor = 30,  hp = 19, ping = 82,  dmg = 410, mined = 260, time = 1900 },
    { name = "SwiftBlade",      pvp = 8,  pve = 10, kills = 18, deaths = 6,  armor = 50,  hp = 17, ping = 26,  dmg = 370, mined = 330, time = 1800 },
    { name = "DiamondKnight",   pvp = 7,  pve = 10, kills = 17, deaths = 9,  armor = 95,  hp = 0,  ping = 36,  dmg = 390, mined = 650, time = 1700, is_dead = true },
    { name = "SilentSniper",    pvp = 10, pve = 6,  kills = 16, deaths = 4,  armor = 10,  hp = 15, ping = 142, dmg = 360, mined = 120, time = 1600, is_afk = true },
    { name = "FrostBite",       pvp = 7,  pve = 8,  kills = 15, deaths = 8,  armor = 70,  hp = 0,  ping = 41,  dmg = 320, mined = 400, time = 1500, is_dead = true },
    { name = "IronClad",        pvp = 4,  pve = 10, kills = 14, deaths = 3,  armor = 100, hp = 20, ping = 64,  dmg = 310, mined = 890, time = 1400 },
    { name = "Vortex",          pvp = 6,  pve = 9,  kills = 15, deaths = 13, armor = 40,  hp = 17, ping = 33,  dmg = 330, mined = 240, time = 1450 },
    { name = "CavernWalker",    pvp = 5,  pve = 8,  kills = 13, deaths = 7,  armor = 80,  hp = 19, ping = 52,  dmg = 290, mined = 550, time = 1300 },
    { name = "RetroGamer",      pvp = 4,  pve = 8,  kills = 12, deaths = 12, armor = 25,  hp = 16, ping = 48,  dmg = 260, mined = 180, time = 1200, is_afk = true },
    { name = "VoidWalker",      pvp = 4,  pve = 8,  kills = 12, deaths = 15, armor = 35,  hp = 13, ping = 130, dmg = 250, mined = 200, time = 1150 },
    { name = "MysticMage",      pvp = 3,  pve = 8,  kills = 11, deaths = 9,  armor = 30,  hp = 16, ping = 110, dmg = 240, mined = 150, time = 1100 },
    { name = "SpeedyGonzales",  pvp = 2,  pve = 8,  kills = 10, deaths = 14, armor = 15,  hp = 14, ping = 9,   dmg = 220, mined = 310, time = 1000 },
    { name = "SandStorm",       pvp = 3,  pve = 6,  kills = 9,  deaths = 11, armor = 40,  hp = 14, ping = 88,  dmg = 190, mined = 270, time = 900  },
    { name = "ArcticFox",       pvp = 2,  pve = 6,  kills = 8,  deaths = 10, armor = 50,  hp = 18, ping = 115, dmg = 180, mined = 340, time = 800  },
    { name = "GoldenApple",     pvp = 1,  pve = 6,  kills = 7,  deaths = 5,  armor = 85,  hp = 20, ping = 55,  dmg = 160, mined = 420, time = 750  },
    { name = "NoobSlayer",      pvp = 3,  pve = 4,  kills = 7,  deaths = 16, armor = 20,  hp = 13, ping = 31,  dmg = 150, mined = 90,  time = 700  },
    { name = "MeseconGenius",   pvp = 1,  pve = 5,  kills = 6,  deaths = 8,  armor = 45,  hp = 18, ping = 62,  dmg = 130, mined = 680, time = 600  },
    { name = "GlitchMaster",    pvp = 2,  pve = 3,  kills = 5,  deaths = 18, armor = 0,   hp = 0,  ping = 320, dmg = 110, mined = 50,  time = 500,  is_dead = true },
    { name = "BlockBuster",     pvp = 0,  pve = 4,  kills = 4,  deaths = 12, armor = 70,  hp = 20, ping = 18,  dmg = 90,  mined = 980, time = 450  },
    { name = "PixelArtisan",    pvp = 0,  pve = 3,  kills = 3,  deaths = 17, armor = 15,  hp = 11, ping = 175, dmg = 70,  mined = 460, time = 350  },
    { name = "CraftyBuilder",   pvp = 0,  pve = 2,  kills = 2,  deaths = 14, armor = 20,  hp = 15, ping = 95,  dmg = 45,  mined = 720, time = 250  },
    { name = "CasualMiner",     pvp = 0,  pve = 1,  kills = 1,  deaths = 15, armor = 35,  hp = 20, ping = 210, dmg = 30,  mined = 850, time = 180, is_afk = true },
    { name = "ZombieBait",      pvp = 0,  pve = 0,  kills = 0,  deaths = 35, armor = 5,   hp = 0,  ping = 240, dmg = 12,  mined = 15,  time = 45,  is_dead = true },
    { name = "LavaDiver",       pvp = 0,  pve = 0,  kills = 0,  deaths = 42, armor = 0,   hp = 0,  ping = 195, dmg = 5,   mined = 5,   time = 12,  is_dead = true },
}

-- Preserve original function if not already saved
if not deathstats.orig_get_scoreboard_data then
    deathstats.orig_get_scoreboard_data = deathstats.get_scoreboard_data
end

--- Hooked scoreboard data provider: merges real connected players with mock entries
---@param viewer_player ObjectRef|nil The viewing player
---@param precomputed_base table|nil Optional pre-gathered and pre-sorted player base entries
---@return table entries Sorted, ranked player entry list
function deathstats.get_scoreboard_data(viewer_player, precomputed_base)
    if not deathstats.mock_scoreboard_enabled then
        if deathstats.orig_get_scoreboard_data then
            return deathstats.orig_get_scoreboard_data(viewer_player, precomputed_base)
        end
        return {}
    end

    local viewer_name = viewer_player and viewer_player:is_player() and viewer_player:get_player_name() or ""
    local entries = {}
    local seen_names = {}

    -- 1. Include real connected players first (using standard scoreboard data)
    if deathstats.orig_get_scoreboard_data then
        entries = deathstats.orig_get_scoreboard_data(viewer_player, precomputed_base)
        for _, item in ipairs(entries) do
            seen_names[item.name] = true
        end
    end

    -- 2. Inject mock players (skipping any whose name matches an active connected player)
    local mock_limit = deathstats.mock_scoreboard_player_count or #deathstats.mock_players_data
    local added_count = 0
    for _, mp in ipairs(deathstats.mock_players_data) do
        if not seen_names[mp.name] and added_count < mock_limit then
            added_count = added_count + 1
            local pvp_kills = mp.pvp or math.floor(mp.kills * 0.4)
            local pve_kills = mp.pve or (mp.kills - pvp_kills)
            local total_kills = pvp_kills + pve_kills
            local deaths = mp.deaths
            local kd = (deaths > 0) and (total_kills / deaths) or total_kills
            local dmg = mp.dmg or (total_kills * 20)
            local mined = mp.mined or (total_kills * 15 + 100)
            local time_alive = mp.time or (total_kills * 60 + 300)
            local is_dead = (mp.is_dead == true)
            local is_afk = (mp.is_afk == true)
            local hp = is_dead and 0 or mp.hp

            local mock_data = {
                lifetime = {
                    players_killed = pvp_kills,
                    deaths = deaths,
                    damage_dealt = dmg,
                }
            }
            local comp_score, avg_score = deathstats.calculate_player_score(mock_data, nil)
            local score = mp.score or comp_score

            table.insert(entries, {
                name = mp.name,
                is_viewer = (mp.name == viewer_name),
                is_real = false,
                is_dead = is_dead,
                is_afk = is_afk,
                pvp_kills = pvp_kills,
                pve_kills = pve_kills,
                kills = total_kills,
                damage_dealt = dmg,
                blocks_mined = mined,
                time_alive = time_alive,
                deaths = deaths,
                kd = kd,
                armor = mp.armor,
                hp = hp,
                ping = mp.ping,
                score = score,
                avg_score = avg_score,
            })
        end
    end

    -- 3. Sort:
    -- Real online players are listed first (ignoring score sorting for mock purposes)
    -- Living players rank above dead players.
    table.sort(entries, function(a, b)
        if a.is_real ~= b.is_real then
            return a.is_real == true
        elseif a.is_dead ~= b.is_dead then
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

    -- 4. Assign rank positions
    for rank, item in ipairs(entries) do
        item.rank = rank
    end

    return entries
end

-- Register dedicated chatcommand for live testing
core.register_chatcommand("mockscores", {
    params = S("[on|off|toggle|<count>]"),
    description = S("Toggle or configure mock players in scoreboard for testing"),
    func = function(_name, param)
        if not deathstats.config.enable_scoreboard then
            return false, S("Scoreboard feature is currently disabled.")
        end
        param = (param or ""):match("^%s*(.-)%s*$"):lower()
        if param == "off" or param == "disable" or param == "false" or param == "0" then
            deathstats.mock_scoreboard_enabled = false
            return true, S("Mock scoreboard disabled. Real player data will be shown.")
        elseif param == "on" or param == "enable" or param == "true" then
            deathstats.mock_scoreboard_enabled = true
            deathstats.mock_scoreboard_player_count = nil
            return true, string.format("Mock scoreboard enabled with all %d mock players.", #deathstats.mock_players_data)
        elseif tonumber(param) then
            local count = math.max(1, math.min(#deathstats.mock_players_data, math.floor(tonumber(param))))
            deathstats.mock_scoreboard_enabled = true
            deathstats.mock_scoreboard_player_count = count
            return true, string.format("Mock scoreboard enabled with %d mock players.", count)
        else
            deathstats.mock_scoreboard_enabled = not deathstats.mock_scoreboard_enabled
            local status = deathstats.mock_scoreboard_enabled and "ENABLED" or "DISABLED"
            return true, string.format("Mock scoreboard is now %s (%d mock players configured).", status,
                deathstats.mock_scoreboard_player_count or #deathstats.mock_players_data)
        end
    end,
})

core.log("action", string.format("[deathstats] Mock scoreboard loaded (%d mock players available). Use /mockscores to toggle.",
    #deathstats.mock_players_data))
