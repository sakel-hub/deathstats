--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Compatibility Layer: Player Skins, Outfits & Human Appearance Frameworks
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

deathstats.compat_skins = deathstats.compat_skins or {}
local cs = deathstats.compat_skins

--- Standard humanoid mesh models recognized across Luanti games
local KNOWN_HUMANOID_MESHES = {
    ["character.b3d"] = true,
    ["3d_armor_character.b3d"] = true,
    ["skinsdb_3d_armor_character_5.b3d"] = true,
    ["character_female.b3d"] = true,
    ["myappearance_character.b3d"] = true,
}

--- Deep copy helper
---@param orig table Original table
---@return table copy Cloned table
local function deep_copy(orig)
    if type(orig) ~= "table" then return orig end
    local res = {}
    for k, v in pairs(orig) do
        res[k] = deep_copy(v)
    end
    return res
end

--- Validate whether a given mesh is an accepted humanoid player model
--- Disallows non-human meshes (e.g. mobs, vehicles)
---@param mesh string|nil The mesh file name
---@return boolean is_humanoid True if the mesh is an accepted humanoid model
function cs.is_humanoid_mesh(mesh)
    if not mesh or mesh == "" then
        return false
    end
    if KNOWN_HUMANOID_MESHES[mesh] then
        return true
    end
    -- Check player_api registered models
    local papi = rawget(_G, "player_api")
    if papi and papi.registered_models and papi.registered_models[mesh] then
        return true
    end
    -- Check default registered player models
    local def_mod = rawget(_G, "default")
    if def_mod and def_mod.registered_player_models and def_mod.registered_player_models[mesh] then
        return true
    end
    -- Check voxlibre / mineclonia player models
    local mcl_p = rawget(_G, "mcl_player")
    if mcl_p and mcl_p.registered_players and mesh:find("character") then
        return true
    end
    return false
end

--- Extract the underlying base skin texture across all supported skin frameworks
--- Evaluates dynamic compilers (edit_skin, myappearance), registries (collectible_skins, skinsdb,
--- simple_skins, wardrobe, nc_skins, u_skins, multiskin, mcl_skins), and engine properties
---@param player ObjectRef The player object
---@param name string The player's name
---@return string|nil skin_texture The resolved base skin texture
---@return string|nil custom_mesh Any custom humanoid mesh associated with the skin
---@return string format Format version ("1.0" or "1.8")
---@return number|nil vs_x Visual size X multiplier
---@return number|nil vs_y Visual size Y multiplier
function cs.extract_base_skin(player, name)
    local vs_x, vs_y = nil, nil
    local custom_mesh = nil

    -- 1. edit_skin (Mr. Rar) - Procedural layer compiler
    local edit_skin_mod = rawget(_G, "edit_skin")
    if edit_skin_mod and type(edit_skin_mod.compile_skin) == "function" then
        local es_skin = nil
        if edit_skin_mod.player_skins and edit_skin_mod.player_skins[player] then
            es_skin = edit_skin_mod.player_skins[player]
        else
            local meta = player:get_meta()
            local raw = meta:get_string("edit_skin:skin")
            if raw and raw ~= "" then
                local des = core.deserialize(raw)
                if type(des) == "table" then
                    es_skin = des
                end
            end
        end
        if es_skin then
            local compiled = edit_skin_mod.compile_skin(es_skin)
            if compiled and compiled ~= "" then
                return compiled, nil, "1.8", vs_x, vs_y
            end
        end
    end

    -- 2. myappearance (Don) - Modular 9-part character appearance
    local myappearance_mod = rawget(_G, "myappearance")
    if myappearance_mod and type(myappearance_mod) == "table" then
        local ap = myappearance_mod[name]
        if type(ap) == "table" and ap.skin then
            local parts = {
                ap.skin or "",
                ap.pants or "",
                ap.shirt or "",
                ap.shoes or "",
                ap.face or "",
                ap.eyes or "",
                ap.belt or "",
                ap.overlay or "",
                ap.hair or "",
            }
            local skin_texture = table.concat(parts)
            if skin_texture:sub(-1) == "^" then
                skin_texture = skin_texture:sub(1, -2)
            end
            if skin_texture ~= "" then
                return skin_texture, "myappearance_character.b3d", "1.0", vs_x, vs_y
            end
        end
    end

    -- 3. collectible_skins (Zughy) - Skin registry with custom models
    local cs_mod = rawget(_G, "collectible_skins")
    if cs_mod and type(cs_mod.get_player_skin) == "function" then
        local skin_data = cs_mod.get_player_skin(name)
        if type(skin_data) == "table" then
            if skin_data.texture and skin_data.texture ~= "" then
                local model = skin_data.model
                if model and cs.is_humanoid_mesh(model) then
                    custom_mesh = model
                end
                return skin_data.texture, custom_mesh, "1.0", vs_x, vs_y
            end
        end
    end

    -- 4. skinsdb (bell07) - Multi-format skin database
    local skins_mod = rawget(_G, "skins")
    if skins_mod and type(skins_mod.get_player_skin) == "function" then
        local skin = skins_mod.get_player_skin(player)
        if skin then
            local ver = (skin.get_meta and skin:get_meta("format")) or "1.0"
            local stex = (skin.get_texture and skin:get_texture()) or nil
            local mx = skin.get_meta and skin:get_meta("visual_size_x")
            local my = skin.get_meta and skin:get_meta("visual_size_y")
            local mesh_meta = skin.get_meta and skin:get_meta("mesh")
            if mesh_meta and cs.is_humanoid_mesh(mesh_meta) then
                custom_mesh = mesh_meta
            end
            if mx and my then
                vs_x = tonumber(mx)
                vs_y = tonumber(my)
            end
            if stex and stex ~= "" then
                return stex, custom_mesh, ver, vs_x, vs_y
            end
        end
    end

    -- 5. simple_skins (TenPlus1)
    if skins_mod and skins_mod.skins and skins_mod.skins[name] then
        local s_id = skins_mod.skins[name]
        if s_id and s_id ~= "" then
            return s_id .. ".png", nil, "1.0", vs_x, vs_y
        end
    end

    -- 6. wardrobe (AntumDeluge)
    local wardrobe_mod = rawget(_G, "wardrobe")
    if wardrobe_mod then
        if wardrobe_mod.playerSkins and wardrobe_mod.playerSkins[name] then
            return wardrobe_mod.playerSkins[name], nil, "1.0", vs_x, vs_y
        elseif wardrobe_mod.skin and wardrobe_mod.skin[name] then
            return wardrobe_mod.skin[name], nil, "1.0", vs_x, vs_y
        end
    end

    -- 7. nc_skins (NodeCore / Warr1024)
    local nc_skins_mod = rawget(_G, "nc_skins")
    if nc_skins_mod and type(nc_skins_mod.get_skin) == "function" then
        local nc_tex = nc_skins_mod.get_skin(name)
        if nc_tex and nc_tex ~= "" then
            return nc_tex, nil, "1.0", vs_x, vs_y
        end
    end

    -- 8. u_skins (Zeg9 / Casimir)
    local u_skins_mod = rawget(_G, "u_skins")
    if u_skins_mod and u_skins_mod.u_skins and u_skins_mod.u_skins[name] then
        local u_id = u_skins_mod.u_skins[name]
        if u_id and u_id ~= "" then
            return u_id .. ".png", nil, "1.0", vs_x, vs_y
        end
    end

    -- 9. multiskin (stu)
    local multiskin_mod = rawget(_G, "multiskin")
    if multiskin_mod and multiskin_mod.layers and multiskin_mod.layers[name] then
        local m_skin = multiskin_mod.layers[name].skin
        if m_skin and m_skin ~= "" then
            return m_skin, nil, "1.0", vs_x, vs_y
        end
    end

    -- 10. mcl_skins (VoxeLibre / Mineclonia)
    local mcl_skins_mod = rawget(_G, "mcl_skins")
    if mcl_skins_mod and type(mcl_skins_mod.get_player_skin) == "function" then
        local skin_data = mcl_skins_mod.get_player_skin(player)
        if type(skin_data) == "table" and skin_data.texture and skin_data.texture ~= "" then
            return skin_data.texture, nil, "1.0", vs_x, vs_y
        elseif type(skin_data) == "string" and skin_data ~= "" then
            return skin_data, nil, "1.0", vs_x, vs_y
        end
    end

    -- 11. 3d_armor texture table
    local armor_mod = rawget(_G, "armor")
    if armor_mod and armor_mod.textures and armor_mod.textures[name] then
        local a_skin = armor_mod.textures[name].skin
        if a_skin and a_skin ~= "" and a_skin ~= "character.png" then
            return a_skin, nil, "1.0", vs_x, vs_y
        end
    end

    -- 12. player_api get_textures
    local player_api_mod = rawget(_G, "player_api")
    if player_api_mod and type(player_api_mod.get_textures) == "function" then
        local p_tex = player_api_mod.get_textures(player)
        if type(p_tex) == "table" and p_tex[1] and p_tex[1] ~= "" and p_tex[1] ~= "blank.png" and p_tex[1] ~= "deathstats_transparent.png" then
            return p_tex[1], nil, "1.0", vs_x, vs_y
        end
    end

    -- 13. properties.textures fallback
    local props = player:get_properties()
    if props and props.textures and type(props.textures) == "table" and #props.textures > 0 then
        if props.textures[2] and props.textures[2] ~= "blank.png" and props.textures[2] ~= "" and props.textures[2] ~= "deathstats_transparent.png" then
            return props.textures[2], nil, "1.8", vs_x, vs_y
        elseif props.textures[1] and props.textures[1] ~= "" then
            return props.textures[1], nil, "1.0", vs_x, vs_y
        end
    end

    return "character.png", nil, "1.0", vs_x, vs_y
end

--- Collect clothing and cape overlays from clothing mods
--- Handles SFENCE and stu clothing mods, gathering all clothing layers
---@param name string The player's name
---@return string|nil clothes_overlay Concatenated overlay of all clothes (without cape)
---@return string|nil cape_overlay Cape texture
function cs.get_clothing_overlays(name)
    local clothing_mod = rawget(_G, "clothing")
    if not clothing_mod or not clothing_mod.player_textures or not clothing_mod.player_textures[name] then
        return nil, nil
    end

    local c = clothing_mod.player_textures[name]
    local cape = (c.cape and c.cape ~= "" and c.cape ~= "blank.png") and c.cape or nil
    local layers = {}

    -- SFENCE clothing mod can contain shirt, pants, hat, shoes, etc.
    for k, v in pairs(c) do
        if k ~= "skin" and k ~= "cape" and v and v ~= "" and v ~= "blank.png" and v ~= "3d_armor_trans.png" then
            table.insert(layers, v)
        end
    end

    local clothes_overlay = nil
    if #layers > 0 then
        clothes_overlay = table.concat(layers, "^")
    end

    return clothes_overlay, cape
end

--- Comprehensive visual characteristic extractor across all human appearance mods
--- Generates model mesh, textures, visual_size, yaw, and armor state for the corpse
--- Disallows non-human mob morphs (disguises, simple_morph) to guarantee valid human corpse
---@param player ObjectRef The player object
---@return table visuals { mesh = string, textures = table, visual_size = table, yaw = number, armor_dropped = boolean }
function cs.get_player_visuals(player)
    if not player or not player:is_player() then
        return {
            mesh = "character.b3d",
            textures = { "character.png" },
            visual_size = { x = 1, y = 1, z = 1 },
            yaw = 0,
            armor_dropped = false,
        }
    end

    local name = player:get_player_name()
    local props = player:get_properties()

    local armor_mod = rawget(_G, "armor")
    local skins_mod = rawget(_G, "skins")

    -- Character size and rotation
    local visual_size = deep_copy((props and props.visual_size) or { x = 1, y = 1, z = 1 })
    local yaw = player:get_look_horizontal() or 0
    if visual_size.x == 0 and visual_size.y == 0 then
        visual_size = { x = 1, y = 1, z = 1 }
    end

    local drops_armor = deathstats.is_armor_dropped(player)
    local drops_inventory = deathstats.is_inventory_dropped(player)
    local wield_item = deathstats.get_player_wield_item(player)

    -- Extract base skin and metadata
    local skin_tex, custom_mesh, format, vs_x, vs_y = cs.extract_base_skin(player, name)
    if not skin_tex or skin_tex == "" then
        skin_tex = "character.png"
    end
    if vs_x and vs_y then
        visual_size = { x = vs_x, y = vs_y, z = vs_x }
    end

    -- Support character_creator dimensions if stored in player metadata
    local meta = player:get_meta()
    if meta then
        local cc_w = (meta.get_float and meta:get_float("character_creator:width"))
            or tonumber(meta:get_string("character_creator:width"))
        local cc_h = (meta.get_float and meta:get_float("character_creator:height"))
            or tonumber(meta:get_string("character_creator:height"))
        if cc_w and cc_h and cc_w > 0 and cc_h > 0 then
            visual_size = { x = cc_w, y = cc_h, z = cc_w }
        end
    end

    -- Determine slot architecture
    local raw_mesh = (armor_mod and armor_mod.models and armor_mod.models[name])
        or custom_mesh
        or (props and props.mesh)
        or "character.b3d"

    local is_skinsdb = (raw_mesh == "skinsdb_3d_armor_character_5.b3d")
        or (raw_mesh and raw_mesh:find("skinsdb") ~= nil)
        or (skins_mod and skins_mod.armor_loaded == true)
        or (skins_mod and skins_mod.get_player_skin and (armor_mod ~= nil or (props and props.textures and #props.textures >= 4)))

    local is_3d_armor = not is_skinsdb and (
        (raw_mesh == "3d_armor_character.b3d")
        or (armor_mod and ((armor_mod.textures and armor_mod.textures[name]) or (raw_mesh and raw_mesh:find("3d_armor"))))
        or (armor_mod and props and props.textures and #props.textures == 3)
    )

    -- Sanitize mesh: guarantee valid human mesh (strictly excluding non-human models/morphs)
    local mesh = raw_mesh
    if is_skinsdb then
        mesh = "skinsdb_3d_armor_character_5.b3d"
    elseif is_3d_armor then
        mesh = (cs.is_humanoid_mesh(raw_mesh) and raw_mesh) or "3d_armor_character.b3d"
    else
        if not cs.is_humanoid_mesh(mesh) then
            mesh = "character.b3d"
        end
    end

    -- Collect clothing overlays
    local clothes_overlay, cape_overlay = cs.get_clothing_overlays(name)

    local textures

    -- 1. skinsdb + 3d_armor (4 material slots)
    -- Slot 1: v10 skin / blank.png + cape
    -- Slot 2: v18 skin / blank.png + clothing
    -- Slot 3: 3D armor geometry overlay
    -- Slot 4: wielditem (blank.png on corpse)
    if is_skinsdb then
        local v10_texture = (format == "1.8") and "blank.png" or skin_tex
        local v18_texture = (format == "1.8") and skin_tex or "blank.png"

        if clothes_overlay then
            v18_texture = (v18_texture == "blank.png") and clothes_overlay or (v18_texture .. "^" .. clothes_overlay)
        end
        if cape_overlay then
            v10_texture = (v10_texture == "blank.png") and cape_overlay or (v10_texture .. "^" .. cape_overlay)
        end

        local armor_texture = "blank.png"
        if not drops_armor and armor_mod and armor_mod.textures and armor_mod.textures[name] then
            local a_tex = armor_mod.textures[name]
            if a_tex.armor and a_tex.armor ~= "" and a_tex.armor ~= "blank.png" and a_tex.armor ~= "3d_armor_trans.png" then
                armor_texture = a_tex.armor
            end
        elseif not drops_armor and props and props.textures and props.textures[3] and props.textures[3] ~= "blank.png" and props.textures[3] ~= "3d_armor_trans.png" then
            armor_texture = props.textures[3]
        end

        textures = {
            v10_texture,
            v18_texture,
            armor_texture,
            "blank.png",
        }

    -- 2. Standalone 3d_armor (3 material slots: skin, armor, wielditem)
    elseif is_3d_armor then
        local final_skin = skin_tex
        if clothes_overlay then
            final_skin = final_skin .. "^" .. clothes_overlay
        end
        if cape_overlay then
            final_skin = final_skin .. "^" .. cape_overlay
        end

        local armor_tex = "3d_armor_trans.png"
        if not drops_armor and armor_mod and armor_mod.textures and armor_mod.textures[name] then
            local a_tex = armor_mod.textures[name]
            if a_tex.armor and a_tex.armor ~= "" and a_tex.armor ~= "blank.png" and a_tex.armor ~= "3d_armor_trans.png" then
                armor_tex = a_tex.armor
            end
        end

        textures = {
            final_skin,
            armor_tex,
            "3d_armor_trans.png",
        }

    -- 3. Standard humanoid model (1 slot or base textures)
    else
        local final_skin = skin_tex
        if clothes_overlay then
            final_skin = final_skin .. "^" .. clothes_overlay
        end
        if cape_overlay then
            final_skin = final_skin .. "^" .. cape_overlay
        end

        textures = { final_skin }
    end

    -- 4. Invisibility / Transparent Texture Trap Protection
    local is_transparent = true
    for _, tex in ipairs(textures) do
        if tex ~= "deathstats_transparent.png" and tex ~= "blank.png" and tex ~= "" and tex ~= "3d_armor_trans.png" then
            is_transparent = false
            break
        end
    end

    if is_transparent and meta then
        local raw_orig = meta:get_string("deathstats:orig_textures")
        if raw_orig and raw_orig ~= "" then
            local des = core.deserialize(raw_orig)
            if type(des) == "table" and #des > 0 then
                textures = des
                is_transparent = false
            end
        end
    end

    if is_transparent then
        if is_skinsdb then
            textures = { "character.png", "blank.png", "blank.png", "blank.png" }
        elseif is_3d_armor then
            textures = { "character.png", "3d_armor_trans.png", "3d_armor_trans.png" }
        else
            textures = { "character.png" }
        end
    end

    -- Recover mesh, visual_size, yaw from metadata if engine reset them to defaults
    if meta then
        if not mesh or mesh == "" or not cs.is_humanoid_mesh(mesh) then
            local raw_mesh_meta = meta:get_string("deathstats:orig_mesh")
            if raw_mesh_meta and raw_mesh_meta ~= "" and cs.is_humanoid_mesh(raw_mesh_meta) then
                mesh = raw_mesh_meta
            end
        end
        if visual_size.x == 0 and visual_size.y == 0 then
            local raw_vs = meta:get_string("deathstats:orig_visual_size")
            if raw_vs and raw_vs ~= "" then
                local des = core.deserialize(raw_vs)
                if type(des) == "table" then visual_size = des end
            end
        end
        if yaw == 0 then
            local raw_yaw = meta:get_string("deathstats:orig_yaw")
            if raw_yaw and raw_yaw ~= "" then
                yaw = tonumber(raw_yaw) or yaw
            end
        end
    end

    return {
        mesh = mesh,
        textures = textures,
        visual_size = visual_size,
        yaw = yaw,
        armor_dropped = drops_armor,
        inventory_dropped = drops_inventory,
        wield_item = wield_item,
    }
end

-- Export delegation to main deathstats API
deathstats.get_player_visuals = cs.get_player_visuals
