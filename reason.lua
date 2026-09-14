--[[
    deathstats - Combat Punch Listener & Recent Punch Recording
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

-- Register combat listener to record recent punches for weapon/killer deduction
core.register_on_punchplayer(function(player, hitter, _time_from_last_punch, _tool_capabilities, dir, damage)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not name or name == "" or deathstats.dead_players[name] then return end

    local real_attacker, _, proj_name = deathstats.resolve_puncher_player(hitter)
    local tool_name = nil
    local tool_desc = nil

    if proj_name then
        tool_name = proj_name
        tool_desc = deathstats.format_projectile_name(proj_name)
    elseif real_attacker and real_attacker:is_player() then
        local item = real_attacker:get_wielded_item()
        local iname = deathstats.get_stack_name(item)
        if iname ~= "" then
            tool_name = iname
            tool_desc = deathstats.format_name(tool_name)
        else
            tool_desc = "Bare Hands"
        end
    elseif hitter and hitter:get_luaentity() then
        local ent = hitter:get_luaentity()
        local ent_def = core.registered_entities[ent.name]
        tool_desc = (ent_def and ent_def.description) or deathstats.format_name(ent.name)
    end

    local attacker_ref = real_attacker or hitter
    local attacker_name, is_player, attacker_desc
    if attacker_ref then
        attacker_name, is_player, attacker_desc = deathstats.resolve_entity_info(attacker_ref)
    end

    local ppos = player:get_pos()
    local hpos = (hitter and hitter.get_pos and hitter:get_pos())
    local punch_dir = (dir and (dir.x ~= 0 or dir.z ~= 0) and dir)
        or (hpos and ppos and vector.direction(hpos, ppos))
        or nil

    local attacker_hp = nil
    local attacker_max_hp = nil
    if attacker_ref then
        local luaent = attacker_ref.get_luaentity and attacker_ref:get_luaentity()
        if luaent and (luaent.health or luaent.hp) then
            attacker_hp = math.max(0, math.floor((luaent.health or luaent.hp) + 0.5))
            local max_hp = luaent.hp_max or luaent.max_hp
            if not max_hp and attacker_ref.get_properties then
                local props = attacker_ref:get_properties()
                max_hp = props and props.hp_max
            end
            attacker_max_hp = math.max(1, math.floor((max_hp or attacker_hp) + 0.5))
        elseif attacker_ref.get_hp then
            attacker_hp = math.max(0, attacker_ref:get_hp())
            local props = attacker_ref.get_properties and attacker_ref:get_properties()
            attacker_max_hp = (props and props.hp_max) or 20
        end
    end

    deathstats.recent_punches[name] = {
        attacker_name = attacker_name,
        is_player = is_player,
        attacker_desc = attacker_desc,
        projectile = proj_name,
        time = core.get_gametime(),
        tool_name = tool_name,
        tool_desc = tool_desc or "Bare Hands",
        damage = damage,
        dir = punch_dir and vector.copy(punch_dir),
        hitter_pos = hpos and vector.copy(hpos),
        attacker_hp = attacker_hp,
        attacker_max_hp = attacker_max_hp,
    }
end)
