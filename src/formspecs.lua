--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local S = core.get_translator(core.get_current_modname())
local F = core.formspec_escape

-- ==========================================
-- Formspec Presentation Interfaces
-- ==========================================

--- Display the elevated death formspec with consistent padding above hotbar area
---@param player ObjectRef The deceased player object
---@param death_info table The death analysis metadata table containing cause, killer, and notes
--- Show minimal photo mode overlay with single button to restore death UI
---@param player ObjectRef The deceased player object
function deathstats.show_photo_mode_formspec(player)
    if not player then return end
    local name = player:get_player_name()
    local c = deathstats.colors
    local fs = {
        "formspec_version[6]",
        "size[2.8,0.65]",
        "position[0.96,0.94]",
        "anchor[1.0,1.0]",
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",
        "style_type[button;border=true;bgimg_middle=true]",
        string.format("style[btn_show_ui;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border),
        "button[0,0;2.8,0.65;btn_show_ui;        " .. F(S("SHOW UI")) .. "]",
        "image[0.22,0.14;0.36,0.36;deathstats_icon_eye.png]",
        "tooltip[btn_show_ui;" .. F(S("Restore Death Screen UI")) .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",
    }
    core.show_formspec(name, "deathstats:photo_mode", table.concat(fs, ""))
end

--- Show corpse epitaph tombstone plaque formspec when living players right-click a settled corpse
---@param clicker ObjectRef The living player inspecting the corpse
---@param corpse_ref ObjectRef|table The corpse entity reference or luaentity table
function deathstats.show_corpse_epitaph_formspec(clicker, corpse_ref)
    if not clicker or not clicker:is_player() then return end
    local clicker_name = clicker:get_player_name()
    local luaent = corpse_ref
    if corpse_ref and corpse_ref.get_luaentity then
        luaent = corpse_ref:get_luaentity() or corpse_ref
    end
    if not luaent then return end

    local pname = (luaent and luaent._player_name) or (corpse_ref and corpse_ref._player_name) or "An Adventurer"
    local dinfo = (luaent and luaent._death_info) or (corpse_ref and corpse_ref._death_info) or {}
    local last = (luaent and luaent._last_life) or (corpse_ref and corpse_ref._last_life) or {}
    local cause = dinfo.reason_text or last.last_cause
    if not cause or cause == "" then
        if dinfo.category == "fall" and dinfo.fall_height then
            cause = string.format(S("Fell %dm to their demise"), dinfo.fall_height)
        elseif dinfo.fall_height then
            cause = string.format(S("Fell %dm"), dinfo.fall_height)
        else
            cause = S("Met their untimely end")
        end
    elseif dinfo.fall_height and not cause:find("%d+m") then
        cause = cause .. string.format(" (%dm)", dinfo.fall_height)
    end
    local weapon = dinfo.weapon_name or dinfo.weapon or last.last_weapon
    local funny = dinfo.funny_note or last.last_funny or "May they rest in peace."
    local time_alive = deathstats.format_time(last.time_alive or 0)

    -- Build rich tooltips for Cause of Death, Survival Summary, and Inscripted Words
    local cause_tt = { F(S("Cause of Death: @1", cause)) }
    if dinfo.killer or dinfo.killer_name then
        local k_name = dinfo.killer_name or dinfo.killer
        if dinfo.killer_hp and dinfo.killer_max_hp then
            table.insert(cause_tt, F(S("Slayer: @1 (@2/@3 HP)", k_name, dinfo.killer_hp, dinfo.killer_max_hp)))
        else
            table.insert(cause_tt, F(S("Slayer: @1", k_name)))
        end
    end
    if weapon and weapon ~= "" and weapon ~= "None" then
        table.insert(cause_tt, F(S("Weapon: @1", weapon)))
    end
    if dinfo.fall_height then
        table.insert(cause_tt, F(S("Fall Distance: @1m", dinfo.fall_height)))
    end
    local death_pos = dinfo.pos or (last and last.death_pos)
    if death_pos then
        table.insert(cause_tt, string.format("Location: (%d, %d, %d)",
            math.floor(death_pos.x + 0.5), math.floor(death_pos.y + 0.5), math.floor(death_pos.z + 0.5)))
    end

    local surv_tt = { F(S("Survived: @1", time_alive)) }
    if (last.blocks_mined and last.blocks_mined > 0) or (last.total_ores and last.total_ores > 0) then
        table.insert(surv_tt, F(S("Mining: @1 blocks (@2 ores)",
            deathstats.format_number(last.blocks_mined or 0), deathstats.format_number(last.total_ores or 0))))
    end
    if (last.damage_dealt and last.damage_dealt > 0) or (last.damage_taken and last.damage_taken > 0) then
        table.insert(surv_tt, F(S("Combat: @1 dealt / @2 taken",
            deathstats.format_number(last.damage_dealt or 0), deathstats.format_number(last.damage_taken or 0))))
    end
    if last.mobs_killed and last.mobs_killed > 0 then
        table.insert(surv_tt, F(S("Mobs Slain: @1", deathstats.format_number(last.mobs_killed))))
    end
    if last.players_killed and last.players_killed > 0 then
        table.insert(surv_tt, F(S("Players Slain: @1", deathstats.format_number(last.players_killed))))
    end
    if last.distance_traveled and last.distance_traveled > 0 then
        table.insert(surv_tt, string.format("Distance Traveled: %.1f m", last.distance_traveled))
    end

    local funny_tt = {
        F(S("Epitaph in Memory of @1:", pname)),
        "\"" .. F(funny) .. "\"",
    }

    local c = deathstats.colors
    local fs = {
        "formspec_version[6]",
        "size[8.0,5.4]",
        "position[0.5,0.5]",
        "anchor[0.5,0.5]",
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Stone plaque modal box
        "box[0.3,0.3;7.4,4.8;" .. c.card_modal .. "]",
        "box[0.3,0.3;7.4,0.08;" .. c.btn_secondary_border .. "]",
        "box[0.3,5.02;7.4,0.08;" .. c.btn_secondary_border .. "]",
        "box[0.3,0.3;0.08,4.8;" .. c.btn_secondary_border .. "]",
        "box[7.62,0.3;0.08,4.8;" .. c.btn_secondary_border .. "]",

        -- Header
        "image[0.6,0.5;0.6,0.6;deathstats_icon_skull.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[1.4,0.75;" .. F(S("IN MEMORIAM")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[1.4,1.05;" .. F(S("Here lies @1", pname)) .. "]",

        -- Details Inset
        "box[0.6,1.4;6.8,2.8;" .. c.card_inset .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_crimson),
        "label[0.9,1.72;" .. F(S("Cause of Death:")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.9,2.05;" .. F(deathstats.truncate_str(cause, 45)) .. "]",
        "tooltip[0.8,1.60;6.4,0.65;" .. table.concat(cause_tt, "\n") .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[0.9,2.45;" .. F(S("Time Survived:")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.9,2.78;" .. F(time_alive) .. (weapon and weapon ~= "None" and ("  |  " .. F(weapon)) or "") .. "]",
        "tooltip[0.8,2.35;6.4,0.65;" .. table.concat(surv_tt, "\n") .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        string.format("style_type[label;textcolor=%s]", c.text_muted),
        "label[0.9,3.18;" .. F(S("Inscripted Words:")) .. "]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[0.9,3.52;\"" .. F(deathstats.truncate_str(funny, 50)) .. "\"]",
        "tooltip[0.8,3.10;6.4,0.65;" .. table.concat(funny_tt, "\n") .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        -- Close Button
        "style_type[button;border=true;bgimg_middle=true]",
        string.format("style[btn_close_epitaph;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border),
        "button[2.8,4.4;2.4,0.55;btn_close_epitaph;" .. F(S("CLOSE")) .. "]",
    }

    core.show_formspec(clicker_name, "deathstats:corpse_epitaph", table.concat(fs, ""))
end

--- Display the elevated death formspec with consistent padding above hotbar area
---@param player ObjectRef The deceased player object
---@param death_info table The death analysis metadata table containing cause, killer, and notes
function deathstats.show_death_formspec(player, death_info)
    if not player then return end
    local name = player:get_player_name()
    local data = deathstats.players[name]
    local last = (data and data.last_life) or {}

    local time_str = deathstats.format_time(last.time_alive or 0)
    local mined_str = deathstats.format_number(last.blocks_mined or 0)
    local ores_str = deathstats.format_number(last.total_ores or 0)
    local dmg_dealt = deathstats.format_number(last.damage_dealt or 0)
    local dmg_taken = deathstats.format_number(last.damage_taken or 0)
    local mobs_slain = deathstats.format_number(last.mobs_killed or 0)
    local players_slain = deathstats.format_number(last.players_killed or 0)
    local items_crafted = deathstats.format_number(last.items_crafted or 0)
    local items_consumed = deathstats.format_number(last.items_consumed or 0)
    local dist_str = string.format("%.1f m", last.distance_traveled or 0)

    local fatal_cause = (death_info and death_info.reason_text) or (last and last.last_cause) or "Unknown"
    local fatal_weapon = (death_info and (death_info.weapon_name or death_info.weapon)) or (last and last.last_weapon) or "None"

    local side = deathstats.config.formspec_side or "right"
    local pos_x = 0.96
    local anchor_x = 1.0
    if side == "left" then
        pos_x = 0.04
        anchor_x = 0.0
    elseif side == "center" then
        pos_x = 0.5
        anchor_x = 0.5
    end

    local c = deathstats.colors

    -- Location formatting
    local loc_str = nil
    local loc_tooltip = nil
    local death_p = last.death_pos or (death_info and (death_info.death_pos or death_info.pos))
    if death_p then
        local p = death_p
        local depth = (death_info and death_info.depth_desc) or last.depth_desc or deathstats.get_depth_description(p.y)
        local biome = (death_info and death_info.biome_name) or last.biome_name or deathstats.get_biome_at_pos(p)
        if biome and biome ~= "" and biome ~= "Unknown" then
            loc_str = string.format("(%d, %d, %d) · %s [%s]", p.x, p.y, p.z, depth, biome)
        else
            loc_str = string.format("(%d, %d, %d) · %s", p.x, p.y, p.z, depth)
        end
        loc_tooltip = string.format("Death Location: (X: %d, Y: %d, Z: %d)\nElevation: %s (Y=%d)%s",
            p.x, p.y, p.z, depth, p.y,
            (biome and biome ~= "" and biome ~= "Unknown") and ("\nBiome: " .. biome) or "")
    end

    -- Specific lethal context
    local lethal_sub = nil
    if (death_info and death_info.killer_hp) or last.killer_hp then
        local khp = (death_info and death_info.killer_hp) or last.killer_hp
        local kmax = (death_info and (death_info.killer_max_hp or death_info.killer_hp_max)) or last.killer_max_hp or last.killer_hp_max or 20
        lethal_sub = string.format(S("Killer HP: %d / %d ❤️"), khp, kmax)
    elseif (death_info and death_info.fall_height) or last.fall_height then
        local fh = (death_info and death_info.fall_height) or last.fall_height
        local fs_val = (death_info and death_info.fall_speed) or last.fall_speed
        if fs_val then
            lethal_sub = string.format(S("Fell %dm at %.1f m/s"), fh, fs_val)
        else
            lethal_sub = string.format(S("Fell %d meters"), fh)
        end
    end

    -- Compact sidebar card docked to the side leaving center death scene completely unobstructed
    local fs = {
        "formspec_version[6]",
        "size[5.6,6.2]",
        string.format("position[%.2f,0.88]", pos_x),
        string.format("anchor[%.2f,1.0]", anchor_x),
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Dark stylized card container (width 5.0, margins 0.3)
        "box[0.3,0.2;5.0,5.05;" .. c.card_sidebar .. "]",
        "box[0.3,0.2;5.0,0.05;" .. c.crimson_border .. "]",
        "box[0.3,5.20;5.0,0.05;" .. c.crimson_border .. "]",

        -- Photo Mode Toggle Button (Top Right of Card)
        string.format("style[btn_photo_mode;border=false;bgcolor=%s;bgcolor_hovered=#ffffff22;bordercolor=%s]",
            c.transparent, c.transparent),
        "image_button[4.75,0.30;0.40,0.40;deathstats_icon_camera.png;btn_photo_mode;]",
        "tooltip[btn_photo_mode;" .. F(S("Photo Mode (Hide UI)")) .. ";" .. c.tooltip_bg .. ";" .. c.text_gold .. "]",

        -- Header: Last Life Summary
        "image[0.5,0.35;0.35,0.35;deathstats_icon_clock.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[0.95,0.56;", F(S("Last Life Summary")), "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),
        "label[0.95,0.82;", F(S("Survived: @1", time_str)), "]",
    }

    if last.is_new_record then
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_gold))
        table.insert(fs, "label[0.95,1.05;" .. F(S("★ NEW PERSONAL RECORD!")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    end

    local row_offset = last.is_new_record and 0.22 or 0.0

    -- Row 1: Combat Stats
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_sword.png]", 1.15 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 1.38 + row_offset, F(S("Damage: @1 dealt / @2 taken", dmg_dealt, dmg_taken))))

    -- Row 2: Kills
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_skull.png]", 1.57 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 1.80 + row_offset, F(S("Slain: @1 mobs / @2 pvp", mobs_slain, players_slain))))

    -- Row 3: Mining
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_pickaxe.png]", 1.99 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 2.22 + row_offset, F(S("Mined: @1 (@2 ores)", mined_str, ores_str))))

    -- Row 4: Items
    table.insert(fs, string.format("image[0.5,%.2f;0.32,0.32;deathstats_icon_heart.png]", 2.41 + row_offset))
    table.insert(fs, string.format("label[0.95,%.2f;%s]", 2.64 + row_offset, F(S("Items: @1 made / @2 eaten", items_crafted, items_consumed))))

    -- Row 5: Fatal Blow Inset Box (Expands gracefully with coordinates and lethal details)
    local box_y = 2.85 + row_offset
    local box_h = 2.20 - row_offset
    table.insert(fs, string.format("box[0.5,%.2f;4.6,%.2f;%s]", box_y, box_h, c.card_inset))

    local fatal_full_tt = string.format("Fatal Blow: %s\nWeapon: %s (Distance: %s)%s%s",
        fatal_cause, fatal_weapon, dist_str,
        loc_tooltip and ("\n" .. loc_tooltip) or "",
        lethal_sub and ("\n" .. lethal_sub) or "")
    table.insert(fs, string.format("tooltip[0.5,%.2f;4.6,%.2f;%s;%s;%s]", box_y, box_h, F(fatal_full_tt), c.tooltip_bg, c.text_gold))

    table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
    table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 0.25, F(S("Fatal Blow:"))))
    table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 0.58, F(deathstats.truncate_str(fatal_cause, 32))))
    table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 0.95, F(deathstats.truncate_str(fatal_weapon, 20) .. "  |  " .. dist_str)))

    if loc_str then
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_gold))
        table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 1.30, F(deathstats.truncate_str(loc_str, 42))))
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    end

    if lethal_sub then
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
        table.insert(fs, string.format("label[0.7,%.2f;%s]", box_y + 1.62, F(lethal_sub)))
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
    end

    -- Button Styling
    table.insert(fs, "style_type[button;border=true;bgimg_middle=true]")
    table.insert(fs, string.format("style[btn_try_again;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
        c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border))
    table.insert(fs, string.format("style[btn_more_stats;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
        c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border))

    -- Action Buttons side by side at bottom
    table.insert(fs, string.format("button[0.3,5.40;2.4,0.68;btn_try_again;%s]", F(S("TRY AGAIN"))))
    table.insert(fs, string.format("button[2.9,5.40;2.4,0.68;btn_more_stats;%s]", F(S("MORE STATS"))))

    core.show_formspec(name, "deathstats:death", table.concat(fs, ""))
end

--- Display the Lifetime Statistics Dashboard with transparent backdrop and accessible tabs
---@param player ObjectRef The player viewing statistics
---@param tab string|nil The active tab name ("overview", "records", "ores", or "combat")
function deathstats.show_lifetime_stats_formspec(player, tab)
    if not player then return end
    local name = player:get_player_name()
    local data = deathstats.players[name]
    local life = (data and data.lifetime) or {}
    tab = tab or "overview"

    local total_time = deathstats.format_time(life.time_alive or 0)
    local deaths = life.deaths or 0
    local kills = (life.mobs_killed or 0) + (life.players_killed or 0)
    local kd_ratio = (deaths > 0) and string.format("%.2f", kills / deaths) or tostring(kills)

    local c = deathstats.colors

    -- Transparent backdrop outside card so YOU DIED banner, blood splatter and 3D scene remain visible
    local fs = {
        "formspec_version[6]",
        "size[14.5,6.2]",
        "position[0.5,0.88]",
        "anchor[0.5,1.0]",
        "no_prepends[]",
        "bgcolor[" .. c.transparent .. ";both;" .. c.transparent .. "]",

        -- Dark translucent modal window card (content area)
        "box[0.4,0.2;13.7,4.95;" .. c.card_modal .. "]",
        "box[0.4,0.2;13.7,0.06;" .. c.crimson_border .. "]",
        "box[0.4,5.15;13.7,0.06;" .. c.crimson_border .. "]",

        -- Header
        "image[0.7,0.32;0.4,0.4;deathstats_icon_skull.png]",
        string.format("style_type[label;textcolor=%s]", c.text_gold),
        "label[1.25,0.58;", F(S("LIFETIME DOSSIER: @1", name)), "]",
        string.format("style_type[label;textcolor=%s]", c.text_white),

        -- Tab Bar Background Container
        "box[0.4,0.8;13.7,0.68;" .. c.tab_bar_bg .. "]",
        "box[0.4,1.48;13.7,0.04;" .. c.tab_bar_sep .. "]",
    }

    -- 4 Tab Button Styles: active tab has high-contrast bright crimson + glowing border, inactive has distinct slate
    local tab_defs = {
        { id = "tab_overview", key = "overview", title = "Overview",       x = 0.5 },
        { id = "tab_records",  key = "records",  title = "Personal Bests", x = 3.9 },
        { id = "tab_ores",     key = "ores",     title = "Ores Breakdown", x = 7.3 },
        { id = "tab_combat",   key = "combat",   title = "Combat Record",  x = 10.7 },
    }
    for _, t in ipairs(tab_defs) do
        if tab == t.key then
            table.insert(fs, string.format("style[%s;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
                t.id, c.tab_active_bg, c.tab_active_hover_bg, c.tab_active_text, c.tab_active_border, c.tab_active_hover_border))
            table.insert(fs, string.format("box[%.1f,1.45;3.2,0.07;%s]", t.x, c.active_strip))
        else
            table.insert(fs, string.format("style[%s;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
                t.id, c.tab_inactive_bg, c.tab_inactive_hover_bg, c.tab_inactive_text, c.tab_inactive_border, c.tab_inactive_hover_border))
        end
        local label_txt = (tab == t.key) and ("▶ " .. t.title) or t.title
        table.insert(fs, string.format("button[%.1f,0.85;3.2,0.58;%s;%s]", t.x, t.id, F(label_txt)))
    end

    if tab == "overview" then
        -- Overview Content: 2x2 grid with generous widths preventing text overflow
        -- Card 1: Survival (Top Left)
        table.insert(fs, "box[0.7,1.65;6.4,1.65;" .. c.card_panel .. "]")
        table.insert(fs, "image[0.9,1.75;0.4,0.4;deathstats_icon_clock.png]")
        table.insert(fs, "label[1.5,1.95;" .. F(S("Total Play Time: @1", total_time)) .. "]")
        table.insert(fs, "label[1.5,2.40;" .. F(S("Total Deaths: @1", deathstats.format_number(deaths))) .. "]")
        table.insert(fs, "label[1.5,2.85;" .. F(S("Distance Walked: @1", string.format("%.1f km", (life.distance_traveled or 0) / 1000))) .. "]")

        -- Card 2: Combat & K/D (Top Right)
        table.insert(fs, "box[7.4,1.65;6.4,1.65;" .. c.card_panel .. "]")
        table.insert(fs, "image[7.6,1.75;0.4,0.4;deathstats_icon_sword.png]")
        table.insert(fs, "label[8.2,1.95;" .. F(S("Damage Dealt: @1", deathstats.format_number(life.damage_dealt or 0))) .. "]")
        table.insert(fs, "label[8.2,2.40;" .. F(S("Damage Taken: @1", deathstats.format_number(life.damage_taken or 0))) .. "]")
        table.insert(fs, "label[8.2,2.85;" .. F(S("K / D Ratio: @1", kd_ratio)) .. "]")

        -- Card 3: Construction & Crafting (Bottom Left)
        table.insert(fs, "box[0.7,3.45;6.4,1.6;" .. c.card_panel .. "]")
        table.insert(fs, "image[0.9,3.55;0.4,0.4;deathstats_icon_pickaxe.png]")
        table.insert(fs, "label[1.5,3.75;" .. F(S("Blocks Mined: @1", deathstats.format_number(life.blocks_mined or 0))) .. "]")
        table.insert(fs, "label[1.5,4.18;" .. F(S("Total Ores Mined: @1", deathstats.format_number(life.total_ores or 0))) .. "]")
        table.insert(fs, "label[1.5,4.60;" .. F(S("Blocks Placed: @1", deathstats.format_number(life.blocks_placed or 0))) .. "]")

        -- Card 4: Nemesis & Recent Cause (Bottom Right)
        table.insert(fs, "box[7.4,3.45;6.4,1.6;" .. c.card_panel .. "]")
        table.insert(fs, "image[7.6,3.55;0.4,0.4;deathstats_icon_heart.png]")
        local nemesis_str = S("None")
        local nemesis_max = 0
        if life.killers_count then
            for k, count in pairs(life.killers_count) do
                if count > nemesis_max then
                    nemesis_max = count
                    local display_k = k
                    if k:find(":") then
                        display_k = deathstats.format_name(k)
                    end
                    nemesis_str = string.format("%s (%d deaths)", display_k, count)
                end
            end
        end
        table.insert(fs, "label[8.2,3.75;" .. F(S("Arch-Nemesis: @1", nemesis_str)) .. "]")
        table.insert(fs, "label[8.2,4.18;" .. F(S("Most Recent Cause:")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
        table.insert(fs, "label[8.2,4.58;" .. F(deathstats.truncate_str(life.last_cause or "None", 36)) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))

        local nemesis_tooltip = string.format("Arch-Nemesis: %s\nMost Recent Cause: %s", nemesis_str, life.last_cause or "None")
        table.insert(fs, string.format("tooltip[7.4,3.45;6.4,1.6;%s;%s;%s]", F(nemesis_tooltip), c.tooltip_bg, c.text_gold))

    elseif tab == "records" then
        -- Personal Bests Showcase (Left Panel)
        table.insert(fs, "box[0.7,1.65;6.4,3.4;" .. c.card_panel .. "]")
        table.insert(fs, "image[0.9,1.75;0.4,0.4;deathstats_icon_trophy.png]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_gold))
        table.insert(fs, "label[1.5,1.95;" .. F(S("Personal Bests (Single Life)")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))
        local pb = life.personal_bests or {}
        table.insert(fs, "label[1.0,2.45;" .. F(S("Longest Life: @1", deathstats.format_time(pb.survival_time or 0))) .. "]")
        table.insert(fs, "label[1.0,2.88;" .. F(S("Best Killstreak: @1", pb.killstreak or 0)) .. "]")
        table.insert(fs, "label[1.0,3.31;" .. F(S("Most Kills in 1 Life: @1", pb.kills or 0)) .. "]")
        table.insert(fs, "label[1.0,3.74;" .. F(S("Most Damage Dealt: @1", deathstats.format_number(pb.damage_dealt or 0))) .. "]")
        table.insert(fs, "label[1.0,4.17;" .. F(S("Most Blocks Mined: @1", deathstats.format_number(pb.blocks_mined or 0))) .. "]")
        table.insert(fs, "label[1.0,4.60;" .. F(S("Most Ores Mined: @1", deathstats.format_number(pb.total_ores or 0))) .. "]")

        -- Cause-of-Death Distribution (Right Panel)
        table.insert(fs, "box[7.4,1.65;6.4,3.4;" .. c.card_panel .. "]")
        table.insert(fs, "image[7.6,1.75;0.4,0.4;deathstats_icon_skull.png]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_crimson))
        table.insert(fs, "label[8.2,1.95;" .. F(S("Cause of Death Breakdown")) .. "]")
        table.insert(fs, string.format("style_type[label;textcolor=%s]", c.text_white))

        local cat_counts = life.deaths_by_category or {}
        local total_d = life.deaths or 0
        local cat_list = {}
        for cat_name, count in pairs(cat_counts) do
            table.insert(cat_list, { name = cat_name, count = count })
        end
        table.sort(cat_list, function(a, b) return a.count > b.count end)

        if #cat_list == 0 then
            table.insert(fs, "label[8.2,2.60;" .. F(S("No deaths recorded yet. Undefeated!")) .. "]")
        else
            for i, entry in ipairs(cat_list) do
                if i <= 6 then
                    local y = 2.15 + i * 0.42
                    local pct = (total_d > 0) and math.floor((entry.count / total_d) * 100 + 0.5) or 0
                    local cat_title = deathstats.format_name(entry.name)
                    table.insert(fs, string.format("label[8.0,%.2f;%s]", y, F(string.format("%s: %d (%d%%)", cat_title, entry.count, pct))))
                end
            end
        end
    elseif tab == "ores" then
        -- Ores Breakdown Table (Dynamic Scrollable 2-Column Grid)
        table.insert(fs, "box[0.7,1.65;13.1,3.4;" .. c.card_panel .. "]")

        local ores = life.ores_mined or {}
        local ore_list = {}
        for ore_name, count in pairs(ores) do
            table.insert(ore_list, { name = ore_name, count = count, title = deathstats.format_name(ore_name) })
        end
        table.sort(ore_list, function(a, b) return a.count > b.count end)

        local total_types = #ore_list
        table.insert(fs, "label[1.0,1.9;" .. F(S("Total Ores Extracted: @1 (@2 varieties)", deathstats.format_number(life.total_ores or 0), total_types)) .. "]")

        if total_types == 0 then
            table.insert(fs, "label[5.0,3.2;" .. F(S("No ores mined yet. Grab a pickaxe!")) .. "]")
        else
            local total_rows = math.ceil(total_types / 2)
            local has_scroll = total_rows > 5
            local container_w = has_scroll and 12.4 or 12.8
            local col_w = has_scroll and 5.95 or 6.15
            local col2_x = has_scroll and 6.25 or 6.45

            if has_scroll then
                table.insert(fs, string.format("scroll_container[0.8,2.18;%.2f,2.80;ore_scroll;vertical;0.1;0.1]", container_w))
            else
                table.insert(fs, "container[0.8,2.18]")
            end

            for i, ore in ipairs(ore_list) do
                local col = ((i - 1) % 2) + 1
                local row = math.floor((i - 1) / 2)
                local x = (col == 1) and 0.1 or col2_x
                local y = 0.08 + row * 0.46

                if row % 2 == 1 then
                    table.insert(fs, "box[" .. x .. "," .. (y - 0.08) .. ";" .. col_w .. ",0.42;" .. c.row_alt .. "]")
                end
                table.insert(fs, "item_image[" .. (x + 0.1) .. "," .. (y - 0.06) .. ";0.38,0.38;" .. F(ore.name) .. "]")
                table.insert(fs, "label[" .. (x + 0.65) .. "," .. (y + 0.13) .. ";" .. F(deathstats.truncate_str(ore.title, 22)) .. "]")
                table.insert(fs, "label[" .. (x + (col_w - 1.85)) .. "," .. (y + 0.13) .. ";" .. F(deathstats.format_compact_number(ore.count)) .. " mined]")

                local ore_tt = string.format("Ore / Mineral: %s\nTechnical Name: %s\nTotal Extracted: %s",
                    ore.title, ore.name, deathstats.format_number(ore.count))
                table.insert(fs, string.format("tooltip[%s,%.2f;%s,0.42;%s;%s;%s]",
                    x, y - 0.08, col_w, F(ore_tt), c.tooltip_bg, c.text_gold))
            end

            if has_scroll then
                table.insert(fs, "scroll_container_end[]")
                local content_h = 0.08 + total_rows * 0.46
                local max_scroll = math.max(10, math.ceil((content_h - 2.80 + 0.1) * 10))
                table.insert(fs, string.format("scrollbaroptions[min=0;max=%d;smallstep=5;largestep=20;thumbsize=15;arrows=default]", max_scroll))
                table.insert(fs, "scrollbar[13.35,2.18;0.28,2.80;vertical;ore_scroll;0]")
            else
                table.insert(fs, "container_end[]")
            end
        end

    elseif tab == "combat" then
        -- Combat Details (Dynamic Scrollable 2-Column Grid)
        table.insert(fs, "box[0.7,1.65;13.1,3.4;" .. c.card_panel .. "]")

        local combat_list = {}
        local players = life.players_slain or {}
        for pvictim, count in pairs(players) do
            table.insert(combat_list, {
                name = pvictim,
                count = count,
                title = pvictim, -- exact player username!
                is_player = true,
                icon = "deathstats_icon_sword.png",
            })
        end
        local mobs = life.mobs_slain or {}
        for mob_name, count in pairs(mobs) do
            table.insert(combat_list, {
                name = mob_name,
                count = count,
                title = deathstats.format_name(mob_name),
                is_player = false,
                icon = "deathstats_icon_skull.png",
            })
        end
        table.sort(combat_list, function(a, b)
            if a.count == b.count then
                return a.title < b.title
            end
            return a.count > b.count
        end)

        local total_combat_types = #combat_list
        table.insert(fs, "label[1.0,1.9;" .. F(S("Total Combat Slayings: @1 (@2 players, @3 mobs)",
            deathstats.format_number(kills),
            deathstats.format_number(life.players_killed or 0),
            deathstats.format_number(life.mobs_killed or 0))) .. "]")

        if total_combat_types == 0 and (life.players_killed or 0) == 0 then
            table.insert(fs, "label[5.0,3.2;" .. F(S("No combat kills recorded yet. A peaceful record.")) .. "]")
        else
            local total_rows = math.ceil(total_combat_types / 2)
            local has_scroll = total_rows > 5
            local container_w = has_scroll and 12.4 or 12.8
            local col_w = has_scroll and 5.95 or 6.15
            local col2_x = has_scroll and 6.25 or 6.45

            if has_scroll then
                table.insert(fs, string.format("scroll_container[0.8,2.18;%.2f,2.80;combat_scroll;vertical;0.1;0.1]", container_w))
            else
                table.insert(fs, "container[0.8,2.18]")
            end

            for i, entry in ipairs(combat_list) do
                local col = ((i - 1) % 2) + 1
                local row = math.floor((i - 1) / 2)
                local x = (col == 1) and 0.1 or col2_x
                local y = 0.08 + row * 0.46

                if row % 2 == 1 then
                    table.insert(fs, "box[" .. x .. "," .. (y - 0.08) .. ";" .. col_w .. ",0.42;" .. c.row_alt .. "]")
                end
                table.insert(fs, string.format("image[%s,%.2f;0.35,0.35;%s]", x + 0.1, y - 0.04, entry.icon))
                table.insert(fs, string.format("label[%s,%.2f;%s]", x + 0.65, y + 0.13, F(deathstats.truncate_str(entry.title, 22))))
                table.insert(fs, string.format("label[%s,%.2f;%s]", x + (col_w - 1.85), y + 0.13, F(deathstats.format_number(entry.count)) .. " slain"))

                local row_tt = string.format("%s: %s\nIdentifier: %s\nTotal Slain: %s",
                    entry.is_player and "Player" or "Mob", entry.title, entry.name, deathstats.format_number(entry.count))
                table.insert(fs, string.format("tooltip[%s,%.2f;%s,0.42;%s;%s;%s]",
                    x, y - 0.08, col_w, F(row_tt), c.tooltip_bg, c.text_gold))
            end

            if has_scroll then
                table.insert(fs, "scroll_container_end[]")
                local content_h = 0.08 + total_rows * 0.46
                local max_scroll = math.max(10, math.ceil((content_h - 2.80 + 0.1) * 10))
                table.insert(fs, string.format("scrollbaroptions[min=0;max=%d;smallstep=5;largestep=20;thumbsize=15;arrows=default]", max_scroll))
                table.insert(fs, "scrollbar[13.35,2.18;0.28,2.80;vertical;combat_scroll;0]")
            else
                table.insert(fs, "container_end[]")
            end
        end
    end

    -- Bottom Buttons: Consistent styling and placement below content card
    table.insert(fs, "style_type[button;border=true;bgimg_middle=true]")
    local is_dead = deathstats.is_player_dead and deathstats.is_player_dead(player)
    if is_dead then
        table.insert(fs, string.format("style[btn_back_death;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_secondary_bg, c.btn_secondary_hover_bg, c.btn_secondary_text, c.btn_secondary_border, c.btn_secondary_hover_border))
        table.insert(fs, string.format("style[btn_modal_respawn;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border))
        table.insert(fs, "button[0.4,5.35;5.0,0.72;btn_back_death;" .. F(S("< BACK TO DEATH SCREEN")) .. "]")
        table.insert(fs, "button[9.1,5.35;5.0,0.72;btn_modal_respawn;" .. F(S("TRY AGAIN")) .. "]")
    else
        table.insert(fs, string.format("style[btn_close;bgcolor=%s;bgcolor_hovered=%s;textcolor=%s;font=bold;border=true;bordercolor=%s;bordercolor_hovered=%s]",
            c.btn_primary_bg, c.btn_primary_hover_bg, c.btn_primary_text, c.btn_primary_border, c.btn_primary_hover_border))
        table.insert(fs, "button[4.75,5.35;5.0,0.72;btn_close;" .. F(S("CLOSE")) .. "]")
    end

    core.show_formspec(name, "deathstats:lifetime", table.concat(fs, ""))
end

deathstats.show_lifetime_formspec = deathstats.show_lifetime_stats_formspec

-- ============================================================================
-- Section 11: Public Scoreboard & Current-Life Leaderboard API
-- ============================================================================

--- Register or override a scoreboard column definition
---@param id string Unique identifier for the column (e.g. "kills", "damage", "ping")
---@param def table Column definition specification (order, title, pct, min_w, icon, get_value, get_color)
function deathstats.register_scoreboard_column(id, def)
    if not id or type(id) ~= "string" or id == "" then return end
    if not def or type(def) ~= "table" then return end

    deathstats.registered_columns[id] = {
        id = id,
        order = def.order or 50,
        title = def.title or id:upper(),
        title_small = def.title_small or def.title or id:sub(1, 3):upper(),
        pct = def.pct or 0.10,
        pct_small = def.pct_small or def.pct or 0.10,
        min_w = def.min_w or 40,
        min_w_small = def.min_w_small or 25,
        icon = def.icon or "deathstats_icon_star.png",
        tooltip = def.tooltip or def.title or id,
        get_value = def.get_value,
        get_color = def.get_color,
    }

    -- Invalidate backdrop texture cache whenever columns change
    deathstats.scoreboard_bg_cache = {}
end

--- Unregister an existing scoreboard column by id
---@param id string Unique column identifier
function deathstats.unregister_scoreboard_column(id)
    if not id then return end
    deathstats.registered_columns[id] = nil
    deathstats.scoreboard_bg_cache = {}
end

--- Query active registered scoreboard columns sorted by their order attribute
---@return table columns Sorted array of column definition tables
function deathstats.get_ordered_scoreboard_columns()
    local cols = {}
    for id, col_def in pairs(deathstats.registered_columns or {}) do
        local c = table.copy(col_def)
        c.id = id
        table.insert(cols, c)
    end
    table.sort(cols, function(a, b)
        if (a.order or 50) ~= (b.order or 50) then
            return (a.order or 50) < (b.order or 50)
        end
        return (a.id or "") < (b.id or "")
    end)
    return cols
end

-- Scoreboard HUD & Formspec Forward Declarations (Implemented in scoreboard.lua)
deathstats.show_scoreboard_hud = deathstats.show_scoreboard_hud or function(_player) end
deathstats.hide_scoreboard_hud = deathstats.hide_scoreboard_hud or function(_player) end
deathstats.update_scoreboard_hud = deathstats.update_scoreboard_hud or function(_player) end
deathstats.show_scoreboard_formspec = deathstats.show_scoreboard_formspec or function(_player) end
deathstats.close_scoreboard_formspec = deathstats.close_scoreboard_formspec or function(_player) end
deathstats.is_player_afk = deathstats.is_player_afk or function(_player_or_name) return false end
deathstats.is_player_dead = deathstats.is_player_dead or function(_player_or_name) return false end
deathstats.reset_player_activity = deathstats.reset_player_activity or function(_player_or_name) end
deathstats.get_player_armor_points = deathstats.get_player_armor_points or function(_player) return 0 end
deathstats.get_player_ping = deathstats.get_player_ping or function(_player_name) return 0 end
deathstats.get_player_hp = deathstats.get_player_hp or function(_player) return 0 end
deathstats.get_scoreboard_cell_color = deathstats.get_scoreboard_cell_color or function(_col, _player, _item, _row_idx) return 0xFFFFFF end
deathstats.get_scoreboard_footer_text = deathstats.get_scoreboard_footer_text or function(_total, _visible) return "" end
deathstats.get_scoreboard_data = deathstats.get_scoreboard_data or function(_viewer_player, _precomputed_base) return {}, {} end
deathstats.calculate_player_score = deathstats.calculate_player_score or function(_pdata, _player, _cached_armor, _cached_hp) return 0, 0 end
