--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local modpath = core.get_modpath("deathstats")

dofile(modpath .. "/api.lua")
dofile(modpath .. "/compat/hunger.lua")
dofile(modpath .. "/compat/skins.lua")
dofile(modpath .. "/stats.lua")
dofile(modpath .. "/reason.lua")
dofile(modpath .. "/gui.lua")
dofile(modpath .. "/scoreboard.lua")
dofile(modpath .. "/compat/hudbars.lua")

-- Optional mock scoreboard data for testing multi-player rosters (enable via setting deathstats_mock_scoreboard = true)
if core.settings:get_bool("deathstats_mock_scoreboard", false) then
    dofile(modpath .. "/mock_scoreboard.lua")
end

core.log("action", "[deathstats] Mod initialized successfully")
