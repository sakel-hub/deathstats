--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

---@param pos Vector Center position of the decaying corpse
---@return integer|nil spawner_id Particle spawner identifier or nil if disabled
function deathstats.spawn_decay_particles(pos)
    if not pos or deathstats.config.enable_corpse_particles == false then return nil end
    local min_p = vector.new(pos.x - 0.4, pos.y - 0.1, pos.z - 0.4)
    local max_p = vector.new(pos.x + 0.4, pos.y + 0.3, pos.z + 0.4)
    local min_v = vector.new(-0.3, 0.4, -0.3)
    local max_v = vector.new(0.3, 1.1, 0.3)
    local min_a = vector.new(0, 0.05, 0)
    local max_a = vector.new(0, 0.15, 0)

    local anim_def = {
        type = "vertical_frames",
        aspect_w = 5,
        aspect_h = 5,
        length = 0.8,
    }

    return core.add_particlespawner({
        amount = 18,
        time = 0.2,
        collisiondetection = false,
        collision_removal = false,
        -- Legacy client fields (< v5.6)
        minpos = min_p,
        maxpos = max_p,
        minvel = min_v,
        maxvel = max_v,
        minacc = min_a,
        maxacc = max_a,
        minexptime = 0.8,
        maxexptime = 1.5,
        minsize = 1.0,
        maxsize = 2.2,
        texture = "deathstats_particle_smoke.png",
        animation = anim_def,
        -- Modern Luanti fields (v5.6+)
        pos = {
            min = min_p,
            max = max_p,
        },
        vel = {
            min = min_v,
            max = max_v,
        },
        acc = {
            min = min_a,
            max = max_a,
        },
        exptime = { min = 0.8, max = 1.5 },
        size = { min = 1.0, max = 2.2 },
        texpool = {
            {
                name = "deathstats_particle_smoke.png",
                alpha_tween = { 0.8, 0.0 },
                scale_tween = { { x = 0.8, y = 0.8 }, { x = 1.6, y = 1.6 } },
                blend = "alpha",
                animation = anim_def,
            },
        },
    })
end


--- Get the primary tile texture name for a given node for particle fallback
---@param node_name string|nil Name of the node
---@return string texture Name of the texture or fallback
function deathstats.get_node_tile_texture(node_name)
    if not node_name or node_name == "" or node_name == "air" or node_name == "ignore" then
        node_name = deathstats.get_fallback_ground_node()
        if not node_name then return "" end
    end
    local cache = deathstats.node_tile_texture_cache
    local cached = cache and cache[node_name]
    if cached then
        return cached
    end

    local result = ""
    local ndef = core.registered_nodes[node_name]
    if ndef and ndef.tiles then
        local t = ndef.tiles[1]
        if type(t) == "string" then
            result = t
        elseif type(t) == "table" and t.name then
            result = t.name
        end
    end
    if result == "" then
        local fallback_name = deathstats.get_fallback_ground_node()
        if fallback_name and fallback_name ~= node_name then
            local fb_def = core.registered_nodes[fallback_name]
            if fb_def and fb_def.tiles then
                local t = fb_def.tiles[1]
                if type(t) == "string" then
                    result = t
                elseif type(t) == "table" and t.name then
                    result = t.name
                end
            end
        end
    end
    if cache then
        cache[node_name] = result
    end
    return result
end

--- Determine the appropriate particle effect for a corpse based on death cause and environment
---@param corpse_pos table The {x, y, z} position of the corpse
---@param death_info table|nil Optional death analysis table
---@return string effect_type "water"|"lava"|"fire"|"impact"
function deathstats.get_corpse_effect_type(corpse_pos, death_info)
    -- Probe the physical environment around corpse_pos first (detects settled water/lava/fire)
    if corpse_pos then
        local probe_offsets = {
            vector.new(corpse_pos.x, corpse_pos.y, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y - 0.3, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y - 0.6, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y - 1.0, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y + 0.2, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y + 0.5, corpse_pos.z),
        }
        for _, ppos in ipairs(probe_offsets) do
            local node = core.get_node_or_nil(ppos)
            if node and node.name and node.name ~= "air" and node.name ~= "ignore" then
                local nname = node.name:lower()
                if nname:find("lava") then
                    return "lava"
                elseif nname:find("fire") or nname:find("flame") then
                    return "fire"
                elseif nname:find("water") then
                    return "water"
                end
                local ndef = core.registered_nodes[node.name]
                if ndef then
                    local is_liq = (ndef.drawtype == "liquid" or ndef.drawtype == "flowingliquid"
                        or ndef.liquidtype == "source" or ndef.liquidtype == "flowing")
                    if is_liq then
                        if (ndef.groups and ndef.groups.lava) or nname:find("lava") then
                            return "lava"
                        else
                            return "water"
                        end
                    end
                end
                local idef = core.registered_items[node.name]
                if idef and idef.groups then
                    if idef.groups.lava then
                        return "lava"
                    elseif idef.groups.water or idef.groups.liquid then
                        return "water"
                    elseif idef.groups.fire then
                        return "fire"
                    end
                end
            end
        end
    end

    -- Fall back to death_info cause / category if the corpse is on dry ground or in air
    local cat = death_info and death_info.category
    if cat == "lava" then
        return "lava"
    elseif cat == "fire" then
        return "fire"
    elseif cat == "drown" then
        return "water"
    end

    if death_info and death_info.reason_text then
        local rtext = death_info.reason_text:lower()
        if rtext:find("lava") then
            return "lava"
        elseif rtext:find("fire") or rtext:find("burned") or rtext:find("flame") or rtext:find("ashes") then
            return "fire"
        elseif rtext:find("drown") or rtext:find("water") then
            return "water"
        end
    end

    return "impact"
end

--- Calculates rotation-compensated particle emitter vectors for an attached entity.
--- Computes the local direction matching world +Y (straight up) so that particles
--- always rise upward in world space regardless of whether the corpse is prone, supine, or tilted.
---@param rot table|nil Rotation { x = pitch, y = yaw, z = roll } in radians
---@param min_val number Minimum scalar magnitude (e.g. min vertical velocity or acceleration)
---@param max_val number Maximum scalar magnitude (e.g. max vertical velocity or acceleration)
---@param spread_h number Horizontal spread magnitude
---@return table min_v Vector { x, y, z }
---@return table max_v Vector { x, y, z }
function deathstats.calc_oriented_particle_bounds(rot, min_val, max_val, spread_h)
    local pitch = (rot and rot.x) or 0
    local roll = (rot and rot.z) or 0
    local cp = math.cos(pitch)
    local sp = math.sin(pitch)
    local cr = math.cos(roll)
    local sr = math.sin(roll)

    -- Local unit vector that transforms into world +Y (straight UP) under Z-X-Y rotation:
    local ux = sr * cp
    local uy = cr * cp
    local uz = -sp

    -- Helper to determine min and max along an axis given directional component
    local function axis_range(u_comp, min_s, max_s, spread)
        local a = u_comp * min_s
        local b = u_comp * max_s
        local low = math.min(a, b) - (math.abs(u_comp) < 0.8 and spread or 0)
        local high = math.max(a, b) + (math.abs(u_comp) < 0.8 and spread or 0)
        return low, high
    end

    local min_x, max_x = axis_range(ux, min_val, max_val, spread_h)
    local min_y, max_y = axis_range(uy, min_val, max_val, spread_h)
    local min_z, max_z = axis_range(uz, min_val, max_val, spread_h)

    if math.abs(uy) >= 0.7 then
        min_x = -spread_h
        max_x = spread_h
        min_z = -spread_h
        max_z = spread_h
    elseif math.abs(ux) >= 0.7 then
        min_y = -spread_h
        max_y = spread_h
        min_z = -spread_h
        max_z = spread_h
    elseif math.abs(uz) >= 0.7 then
        min_x = -spread_h
        max_x = spread_h
        min_y = -spread_h
        max_y = spread_h
    end

    return vector.new(min_x, min_y, min_z), vector.new(max_x, max_y, max_z)
end

--- Create a modern ParticleSpawner definition table with graceful fallback to older Luanti clients
---@param effect_type string "water"|"lava"|"fire"|"impact"
---@param corpse_pos table The {x, y, z} position of the corpse
---@param attached_obj ObjectRef|nil Optional corpse ObjectRef to attach particles to
---@return table|nil def ParticleSpawner definition table
function deathstats.create_corpse_particlespawner_def(effect_type, corpse_pos, attached_obj)
    if not corpse_pos then return nil end
    local cx, cy, cz = corpse_pos.x, corpse_pos.y, corpse_pos.z
    local has_attached = attached_obj and (not attached_obj.is_valid or attached_obj:is_valid())
    local rot = nil
    if has_attached then
        local luaent = (attached_obj.get_luaentity and attached_obj:get_luaentity())
        rot = (luaent and luaent._rot) or (attached_obj.get_rotation and attached_obj:get_rotation())
    end

    if effect_type == "water" then
        local min_v, max_v = deathstats.calc_oriented_particle_bounds(rot, 0.35, 0.85, 0.15)
        local min_a, max_a = deathstats.calc_oriented_particle_bounds(rot, 0.20, 0.45, 0.05)
        local pos_min_y, pos_max_y = 0.05, 0.25
        local roll = (rot and rot.z) or 0
        local pitch = (rot and rot.x) or 0
        local uy = math.cos(roll) * math.cos(pitch)
        if has_attached and uy < -0.5 then
            local o_max = pos_max_y
            pos_max_y = -pos_min_y
            pos_min_y = -o_max
        end
        -- Bubbles floating upwards through water continuously from random positions on the submerged corpse
        return {
            amount = 8,
            time = 0, -- Continuous spawner
            collisiondetection = false,
            collision_removal = false,
            glow = 3,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.35, y = pos_min_y, z = -0.35 } or { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = has_attached and { x = 0.35, y = pos_max_y, z = 0.35 } or { x = cx + 0.35, y = cy + 0.25, z = cz + 0.35 },
            minvel = has_attached and min_v or { x = -0.15, y = 0.35, z = -0.15 },
            maxvel = has_attached and max_v or { x = 0.15, y = 0.85, z = 0.15 },
            minacc = has_attached and min_a or { x = -0.05, y = 0.20, z = -0.05 },
            maxacc = has_attached and max_a or { x = 0.05, y = 0.45, z = 0.05 },
            minexptime = 1.2,
            maxexptime = 2.4,
            minsize = 1.0,
            maxsize = 1.6,
            texture = "deathstats_particle_bubble.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.8,
            },
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = has_attached and vector.new(-0.35, pos_min_y, -0.35) or vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = has_attached and vector.new(0.35, pos_max_y, 0.35) or vector.new(cx + 0.35, cy + 0.25, cz + 0.35),
            },
            vel = {
                min = has_attached and min_v or vector.new(-0.15, 0.35, -0.15),
                max = has_attached and max_v or vector.new(0.15, 0.85, 0.15),
            },
            acc = {
                min = has_attached and min_a or vector.new(-0.05, 0.20, -0.05),
                max = has_attached and max_a or vector.new(0.05, 0.45, 0.05),
            },
            exptime = { min = 1.2, max = 2.4 },
            size = { min = 1.0, max = 1.6 },
            texpool = {
                {
                    name = "deathstats_particle_bubble.png",
                    alpha_tween = { 0.85, 0.30 },
                    scale_tween = { { x = 0.9, y = 0.9 }, { x = 1.15, y = 1.15 } },
                    blend = "alpha",
                    animation = {
                        type = "vertical_frames",
                        aspect_w = 5,
                        aspect_h = 5,
                        length = 0.8,
                    },
                },
            },
        }

    elseif effect_type == "lava" then
        local min_v, max_v = deathstats.calc_oriented_particle_bounds(rot, 0.50, 1.40, 0.25)
        local min_a, max_a = deathstats.calc_oriented_particle_bounds(rot, 0.30, 0.80, 0.10)
        local pos_min_y, pos_max_y = 0.05, 0.30
        local roll = (rot and rot.z) or 0
        local pitch = (rot and rot.x) or 0
        local uy = math.cos(roll) * math.cos(pitch)
        if has_attached and uy < -0.5 then
            local o_max = pos_max_y
            pos_max_y = -pos_min_y
            pos_min_y = -o_max
        end
        -- Fire and glowing ember sparks leaping continuously from random positions on the burning corpse
        return {
            amount = 12,
            time = 0, -- Continuous spawner
            collisiondetection = true,
            collision_removal = false,
            glow = 14,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.35, y = pos_min_y, z = -0.35 } or { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = has_attached and { x = 0.35, y = pos_max_y, z = 0.35 } or { x = cx + 0.35, y = cy + 0.30, z = cz + 0.35 },
            minvel = has_attached and min_v or { x = -0.25, y = 0.50, z = -0.25 },
            maxvel = has_attached and max_v or { x = 0.25, y = 1.40, z = 0.25 },
            minacc = has_attached and min_a or { x = -0.10, y = 0.30, z = -0.10 },
            maxacc = has_attached and max_a or { x = 0.10, y = 0.80, z = 0.10 },
            minexptime = 0.5,
            maxexptime = 1.2,
            minsize = 1.0,
            maxsize = 1.8,
            texture = "deathstats_particle_fire.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.4,
            },
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = has_attached and vector.new(-0.35, pos_min_y, -0.35) or vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = has_attached and vector.new(0.35, pos_max_y, 0.35) or vector.new(cx + 0.35, cy + 0.30, cz + 0.35),
            },
            vel = {
                min = has_attached and min_v or vector.new(-0.25, 0.50, -0.25),
                max = has_attached and max_v or vector.new(0.25, 1.40, 0.25),
            },
            acc = {
                min = has_attached and min_a or vector.new(-0.10, 0.30, -0.10),
                max = has_attached and max_a or vector.new(0.10, 0.80, 0.10),
            },
            exptime = { min = 0.5, max = 1.2 },
            size = { min = 1.0, max = 1.8 },
            texpool = {
                {
                    name = "deathstats_particle_fire.png",
                    alpha_tween = { 1.0, 0.0 },
                    blend = "add",
                    animation = {
                        type = "vertical_frames",
                        aspect_w = 5,
                        aspect_h = 5,
                        length = 0.4,
                    },
                },
            },
        }

    elseif effect_type == "fire" then
        local min_v, max_v = deathstats.calc_oriented_particle_bounds(rot, 0.30, 0.80, 0.15)
        local min_a, max_a = deathstats.calc_oriented_particle_bounds(rot, 0.15, 0.40, 0.05)
        local pos_min_y, pos_max_y = 0.05, 0.30
        local roll = (rot and rot.z) or 0
        local pitch = (rot and rot.x) or 0
        local uy = math.cos(roll) * math.cos(pitch)
        if has_attached and uy < -0.5 then
            local o_max = pos_max_y
            pos_max_y = -pos_min_y
            pos_min_y = -o_max
        end
        -- Billowing ash smoke rising continuously into the air from the charred corpse
        return {
            amount = 12,
            time = 0, -- Continuous spawner
            collisiondetection = true,
            collision_removal = false,
            glow = 1,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.35, y = pos_min_y, z = -0.35 } or { x = cx - 0.35, y = cy + 0.05, z = cz - 0.35 },
            maxpos = has_attached and { x = 0.35, y = pos_max_y, z = 0.35 } or { x = cx + 0.35, y = cy + 0.30, z = cz + 0.35 },
            minvel = has_attached and min_v or { x = -0.15, y = 0.30, z = -0.15 },
            maxvel = has_attached and max_v or { x = 0.15, y = 0.80, z = 0.15 },
            minacc = has_attached and min_a or { x = -0.05, y = 0.15, z = -0.05 },
            maxacc = has_attached and max_a or { x = 0.05, y = 0.40, z = 0.05 },
            minexptime = 1.0,
            maxexptime = 2.0,
            minsize = 1.2,
            maxsize = 2.4,
            texture = "deathstats_particle_smoke.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.8,
            },
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = has_attached and vector.new(-0.35, pos_min_y, -0.35) or vector.new(cx - 0.35, cy + 0.05, cz - 0.35),
                max = has_attached and vector.new(0.35, pos_max_y, 0.35) or vector.new(cx + 0.35, cy + 0.30, cz + 0.35),
            },
            vel = {
                min = has_attached and min_v or vector.new(-0.15, 0.30, -0.15),
                max = has_attached and max_v or vector.new(0.15, 0.80, 0.15),
            },
            acc = {
                min = has_attached and min_a or vector.new(-0.05, 0.15, -0.05),
                max = has_attached and max_a or vector.new(0.05, 0.40, 0.05),
            },
            exptime = { min = 1.0, max = 2.0 },
            size = { min = 1.2, max = 2.4 },
            texpool = {
                {
                    name = "deathstats_particle_smoke.png",
                    alpha_tween = { 0.75, 0.0 },
                    scale_tween = { { x = 0.8, y = 0.8 }, { x = 1.5, y = 1.5 } },
                    blend = "alpha",
                    animation = {
                        type = "vertical_frames",
                        aspect_w = 5,
                        aspect_h = 5,
                        length = 0.8,
                    },
                },
            },
        }

    else
        -- All others: Node particles around the corpse flying upwards from impact at time of death (non-continuous)
        local ground_node_name = nil
        local ground_param2 = 0
        local check_positions = {
            { x = cx, y = math.floor(cy), z = cz },
            { x = cx, y = math.floor(cy - 0.5), z = cz },
            { x = cx, y = math.floor(cy - 1.0), z = cz },
        }
        for _, cpos in ipairs(check_positions) do
            local n = core.get_node_or_nil(cpos)
            if n and n.name ~= "air" and n.name ~= "ignore" then
                ground_node_name = n.name
                ground_param2 = n.param2 or 0
                break
            end
        end

        ground_node_name = ground_node_name or deathstats.get_fallback_ground_node()
        if not ground_node_name then
            return nil
        end

        local fallback_tex = deathstats.get_node_tile_texture(ground_node_name)

        return {
            amount = 28,
            time = 0.15, -- Moment of death impact burst (not continuous)
            collisiondetection = true,
            collision_removal = false,
            node = { name = ground_node_name, param2 = ground_param2 },
            texture = fallback_tex,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = has_attached and { x = -0.45, y = -0.05, z = -0.45 } or { x = cx - 0.45, y = cy - 0.05, z = cz - 0.45 },
            maxpos = has_attached and { x = 0.45, y = 0.15, z = 0.45 } or { x = cx + 0.45, y = cy + 0.15, z = cz + 0.45 },
            minvel = { x = -1.6, y = 1.8, z = -1.6 },
            maxvel = { x = 1.6, y = 3.6, z = 1.6 },
            minacc = { x = 0, y = -9.81, z = 0 },
            maxacc = { x = 0, y = -9.81, z = 0 },
            minexptime = 0.6,
            maxexptime = 1.2,
            minsize = 0,
            maxsize = 0,
            -- Modern Luanti fields (v5.6+)
            pos = {
                min = has_attached and vector.new(-0.45, -0.05, -0.45) or vector.new(cx - 0.45, cy - 0.05, cz - 0.45),
                max = has_attached and vector.new(0.45, 0.15, 0.45) or vector.new(cx + 0.45, cy + 0.15, cz + 0.45),
            },
            vel = {
                min = vector.new(-1.6, 1.8, -1.6),
                max = vector.new(1.6, 3.6, 1.6),
            },
            acc = {
                min = vector.new(0, -9.81, 0),
                max = vector.new(0, -9.81, 0),
            },
            exptime = { min = 0.6, max = 1.2 },
            size = { min = 0, max = 0 },
            texpool = {
                {
                    name = fallback_tex,
                },
            },
        }
    end
end

--- Spawn an instantaneous localized burst of node debris particles at the impact site
---@param pos Vector The collision contact point
---@param ground_node_name string|nil The node name struck
---@param intensity number|nil Impact velocity or damage
function deathstats.spawn_impact_burst(pos, ground_node_name, intensity)
    if deathstats.config.enable_corpse_particles == false or not pos then return end
    local scale = math.min(2.0, math.max(0.6, (tonumber(intensity) or 5.0) / 6.0))
    local node_name = ground_node_name or deathstats.get_fallback_ground_node()
    if not node_name then return end
    local tex = deathstats.get_node_tile_texture(node_name)
    local cx, cy, cz = pos.x, pos.y, pos.z
    local min_p = vector.new(cx - 0.35, cy - 0.05, cz - 0.35)
    local max_p = vector.new(cx + 0.35, cy + 0.15, cz + 0.35)
    local min_v = vector.new(-1.6 * scale, 1.2 * scale, -1.6 * scale)
    local max_v = vector.new(1.6 * scale, 3.0 * scale, 1.6 * scale)
    local min_a = vector.new(0, -9.81, 0)
    local max_a = vector.new(0, -9.81, 0)
    local p_def = {
        amount = math.floor(16 * scale),
        time = 0.08,
        collisiondetection = true,
        -- Legacy client fields (< v5.6)
        minpos = min_p,
        maxpos = max_p,
        minvel = min_v,
        maxvel = max_v,
        minacc = min_a,
        maxacc = max_a,
        minexptime = 0.4,
        maxexptime = 0.8,
        minsize = 0.8,
        maxsize = 1.6,
        texture = tex,
        node = { name = node_name },
        -- Modern Luanti fields (v5.6+)
        pos = { min = min_p, max = max_p },
        vel = { min = min_v, max = max_v },
        acc = { min = min_a, max = max_a },
        exptime = { min = 0.4, max = 0.8 },
        size = { min = 0.8, max = 1.6 },
        texpool = {
            {
                name = tex,
            },
        },
    }
    core.add_particlespawner(p_def)
end

--- Spawn corpse particle spawner(s) according to death cause/environment
---@param corpse_pos table The {x, y, z} position of the corpse
---@param death_info table|nil Optional death analysis table
---@param attached_obj ObjectRef|nil Optional corpse ObjectRef to attach particles to
---@return number[] spawner_ids Array of active particle spawner IDs
---@return string|nil effect_type The type of effect spawned (e.g. "water", "lava", "fire", "impact")
function deathstats.spawn_corpse_particles(corpse_pos, death_info, attached_obj)
    if not corpse_pos then return {}, nil end
    if deathstats.config.enable_corpse_particles == false then return {}, nil end

    local effect_type = deathstats.get_corpse_effect_type(corpse_pos, death_info)
    local def = deathstats.create_corpse_particlespawner_def(effect_type, corpse_pos, attached_obj)
    if not def then return {}, effect_type end

    local spawner_id = core.add_particlespawner(def)
    local spawner_ids = {}
    if spawner_id and spawner_id > 0 then
        table.insert(spawner_ids, spawner_id)
    end
    return spawner_ids, effect_type
end

