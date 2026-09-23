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
---@return string effect_type "water"|"lava"|"fire"|"flies"|"impact"
function deathstats.get_corpse_effect_type(corpse_pos, death_info)
    -- Probe the physical environment around corpse_pos first (detects settled water/lava/fire)
    if corpse_pos then
        local probe_offsets = {
            vector.new(corpse_pos.x, corpse_pos.y + 0.3, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y, corpse_pos.z),
            vector.new(corpse_pos.x, corpse_pos.y - 0.25, corpse_pos.z),
        }
        for _, ppos in ipairs(probe_offsets) do
            local node = core.get_node_or_nil(ppos)
            if node and node.name and node.name ~= "air" and node.name ~= "ignore" then
                local nname = node.name:lower()
                if nname:find("lava") then
                    return "lava"
                elseif nname:find("water") then
                    return "water"
                elseif nname:find("fire") or nname:find("flame") then
                    -- If killed by an explosion, crater flames do not turn dry corpse into smoke
                    if not (death_info and death_info.category == "explosion") then
                        return "fire"
                    end
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
                        if not (death_info and death_info.category == "explosion") then
                            return "fire"
                        end
                    end
                end
            end
        end
    end

    -- Fall back to death_info cause / category if the corpse is on dry ground or in air
    local cat = death_info and death_info.category
    if cat == "explosion" then
        return "flies"
    elseif cat == "lava" then
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

    -- Default effect for all corpses resting on dry ground: a buzzing swarm of flies (spawned alongside impact particles)
    return "flies"
end

--- Calculates rotation-compensated particle emitter position box for an attached entity.
--- Offsets along the local axis corresponding to world +Y (UP) so particles always emit
--- from the top of the corpse regardless of pitch and roll.
---@param rot table|nil Rotation { x = pitch, y = yaw, z = roll } in radians
---@param min_h_offset number Minimum vertical offset above corpse (world space)
---@param max_h_offset number Maximum vertical offset above corpse (world space)
---@param h_spread number Horizontal half-width spread around corpse (world space)
---@return table min_p Vector { x, y, z }
---@return table max_p Vector { x, y, z }
function deathstats.calc_oriented_particle_pos(rot, min_h_offset, max_h_offset, h_spread)
    local pitch = (rot and rot.x) or 0
    local roll = (rot and rot.z) or 0
    local cp = math.cos(pitch)
    local sp = math.sin(pitch)
    local cr = math.cos(roll)
    local sr = math.sin(roll)

    -- Local unit vector that transforms into world +Y (straight UP) under Luanti CAO rotation.
    -- Luanti negates the rotation angles when building the client transform matrix in content_cao.cpp (-m_rotation),
    -- which negates the sine components: M[1] = -sin(roll)*cos(pitch) and M[9] = sin(pitch).
    local ux = -sr * cp
    local uy = cr * cp
    local uz = sp

    local abs_x = math.abs(ux)
    local abs_y = math.abs(uy)
    local abs_z = math.abs(uz)

    local min_p = vector.new(-h_spread, -h_spread, -h_spread)
    local max_p = vector.new(h_spread, h_spread, h_spread)

    if abs_y >= abs_x and abs_y >= abs_z then
        -- Torso is primarily flat / horizontal (supine or prone)
        if uy >= 0 then
            min_p.y = min_h_offset
            max_p.y = max_h_offset
        else
            min_p.y = -max_h_offset
            max_p.y = -min_h_offset
        end
    elseif abs_x >= abs_z then
        -- Corpse is lying on its side (lateral roll)
        if ux >= 0 then
            min_p.x = min_h_offset
            max_p.x = max_h_offset
        else
            min_p.x = -max_h_offset
            max_p.x = -min_h_offset
        end
    else
        -- Corpse is pitched steeply (head/feet tilted up or down)
        if uz >= 0 then
            min_p.z = min_h_offset
            max_p.z = max_h_offset
        else
            min_p.z = -max_h_offset
            max_p.z = -min_h_offset
        end
    end

    return min_p, max_p
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

    -- Local unit vector that transforms into world +Y (straight UP) under Luanti CAO rotation:
    local ux = -sr * cp
    local uy = cr * cp
    local uz = sp

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
---@param effect_type string "water"|"lava"|"fire"|"flies"|"impact"
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
        rot = (attached_obj.get_rotation and attached_obj:get_rotation())
            or (luaent and luaent._rot)
        if luaent then
            if not luaent._rot and rot then
                luaent._rot = rot
            end
            local roll = (rot and rot.z) or 0
            local pitch = (rot and rot.x) or 0
            local uy = math.cos(roll) * math.cos(pitch)
            luaent._particles_were_prone = (uy < -0.5)
        end
    end

    if effect_type == "water" then
        local min_v, max_v = deathstats.calc_oriented_particle_bounds(rot, 0.35, 0.85, 0.15)
        local min_a, max_a = deathstats.calc_oriented_particle_bounds(rot, 0.20, 0.45, 0.05)
        local min_p, max_p
        if has_attached then
            min_p, max_p = deathstats.calc_oriented_particle_pos(rot, 0.05, 0.25, 0.35)
        else
            min_p = vector.new(cx - 0.35, cy + 0.05, cz - 0.35)
            max_p = vector.new(cx + 0.35, cy + 0.25, cz + 0.35)
            min_v = vector.new(-0.15, 0.35, -0.15)
            max_v = vector.new(0.15, 0.85, 0.15)
            min_a = vector.new(-0.05, 0.20, -0.05)
            max_a = vector.new(0.05, 0.45, 0.05)
        end
        -- Bubbles floating upwards through water continuously from random positions on the submerged corpse
        return {
            amount = 8,
            time = 0, -- Continuous spawner
            collisiondetection = false,
            collision_removal = false,
            glow = 4,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = { x = min_p.x, y = min_p.y, z = min_p.z },
            maxpos = { x = max_p.x, y = max_p.y, z = max_p.z },
            minvel = { x = min_v.x, y = min_v.y, z = min_v.z },
            maxvel = { x = max_v.x, y = max_v.y, z = max_v.z },
            minacc = { x = min_a.x, y = min_a.y, z = min_a.z },
            maxacc = { x = max_a.x, y = max_a.y, z = max_a.z },
            minexptime = 1.2,
            maxexptime = 2.4,
            minsize = 1.2,
            maxsize = 2.0,
            texture = "deathstats_particle_bubble.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.8,
            },
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
            exptime = { min = 1.2, max = 2.4 },
            size = { min = 1.2, max = 2.0 },
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
        local min_p, max_p
        if has_attached then
            min_p, max_p = deathstats.calc_oriented_particle_pos(rot, 0.05, 0.30, 0.35)
        else
            min_p = vector.new(cx - 0.35, cy + 0.05, cz - 0.35)
            max_p = vector.new(cx + 0.35, cy + 0.30, cz + 0.35)
            min_v = vector.new(-0.25, 0.50, -0.25)
            max_v = vector.new(0.25, 1.40, 0.25)
            min_a = vector.new(-0.10, 0.30, -0.10)
            max_a = vector.new(0.10, 0.80, 0.10)
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
            minpos = { x = min_p.x, y = min_p.y, z = min_p.z },
            maxpos = { x = max_p.x, y = max_p.y, z = max_p.z },
            minvel = { x = min_v.x, y = min_v.y, z = min_v.z },
            maxvel = { x = max_v.x, y = max_v.y, z = max_v.z },
            minacc = { x = min_a.x, y = min_a.y, z = min_a.z },
            maxacc = { x = max_a.x, y = max_a.y, z = max_a.z },
            minexptime = 0.5,
            maxexptime = 1.2,
            minsize = 1.2,
            maxsize = 2.0,
            texture = "deathstats_particle_fire.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.4,
            },
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
            exptime = { min = 0.5, max = 1.2 },
            size = { min = 1.2, max = 2.0 },
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
        local min_p, max_p
        if has_attached then
            min_p, max_p = deathstats.calc_oriented_particle_pos(rot, 0.05, 0.30, 0.35)
        else
            min_p = vector.new(cx - 0.35, cy + 0.05, cz - 0.35)
            max_p = vector.new(cx + 0.35, cy + 0.30, cz + 0.35)
            min_v = vector.new(-0.15, 0.30, -0.15)
            max_v = vector.new(0.15, 0.80, 0.15)
            min_a = vector.new(-0.05, 0.15, -0.05)
            max_a = vector.new(0.05, 0.40, 0.05)
        end
        -- Billowing ash smoke rising continuously into the air from the charred corpse
        return {
            amount = 12,
            time = 0, -- Continuous spawner
            collisiondetection = true,
            collision_removal = false,
            glow = 2,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = { x = min_p.x, y = min_p.y, z = min_p.z },
            maxpos = { x = max_p.x, y = max_p.y, z = max_p.z },
            minvel = { x = min_v.x, y = min_v.y, z = min_v.z },
            maxvel = { x = max_v.x, y = max_v.y, z = max_v.z },
            minacc = { x = min_a.x, y = min_a.y, z = min_a.z },
            maxacc = { x = max_a.x, y = max_a.y, z = max_a.z },
            minexptime = 1.0,
            maxexptime = 2.0,
            minsize = 1.4,
            maxsize = 2.8,
            texture = "deathstats_particle_smoke.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 5,
                aspect_h = 5,
                length = 0.8,
            },
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
            exptime = { min = 1.0, max = 2.0 },
            size = { min = 1.4, max = 2.8 },
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

    elseif effect_type == "flies" then
        -- Swarm of flies buzzing erratically around the resting corpse
        local anim_def = {
            type = "vertical_frames",
            aspect_w = 5,
            aspect_h = 5,
            length = 0.08,
        }
        local min_p, max_p
        local min_v, max_v
        local min_a, max_a
        if has_attached then
            min_p, max_p = deathstats.calc_oriented_particle_pos(rot, 0.15, 0.65, 0.45)
            min_v, max_v = deathstats.calc_oriented_particle_bounds(rot, 0.1, 0.4, 0.4)
            min_a, max_a = deathstats.calc_oriented_particle_bounds(rot, -0.2, 0.2, 0.4)
        else
            min_p = vector.new(cx - 0.45, cy + 0.15, cz - 0.45)
            max_p = vector.new(cx + 0.45, cy + 0.65, cz + 0.45)
            min_v = vector.new(-0.4, 0.1, -0.4)
            max_v = vector.new(0.4, 0.4, 0.4)
            min_a = vector.new(-0.4, -0.2, -0.4)
            max_a = vector.new(0.4, 0.2, 0.4)
        end

        return {
            amount = 12,
            time = 0, -- Continuous spawner
            collisiondetection = false,
            collision_removal = false,
            glow = 1,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = { x = min_p.x, y = min_p.y, z = min_p.z },
            maxpos = { x = max_p.x, y = max_p.y, z = max_p.z },
            minvel = { x = min_v.x, y = min_v.y, z = min_v.z },
            maxvel = { x = max_v.x, y = max_v.y, z = max_v.z },
            minacc = { x = min_a.x, y = min_a.y, z = min_a.z },
            maxacc = { x = max_a.x, y = max_a.y, z = max_a.z },
            minexptime = 0.8,
            maxexptime = 1.6,
            minsize = 1.0,
            maxsize = 1.6,
            texture = "deathstats_particle_fly.png",
            animation = anim_def,
            -- Modern Luanti fields (v5.6+ / v5.8+)
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
            jitter = {
                min = vector.new(-1.0, -0.5, -1.0),
                max = vector.new(1.0, 0.5, 1.0),
            },
            drag = {
                min = vector.new(0.8, 0.8, 0.8),
                max = vector.new(1.5, 1.5, 1.5),
            },
            exptime = { min = 0.8, max = 1.6 },
            size = { min = 1.0, max = 1.6 },
            texpool = {
                {
                    name = "deathstats_particle_fly.png",
                    animation = anim_def,
                },
            },
        }

    else
        -- Impact / all others: Node particles around the corpse flying upwards from impact at time of death (non-continuous)
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
        local min_p, max_p
        local min_v, max_v
        local min_a, max_a
        if has_attached then
            min_p, max_p = deathstats.calc_oriented_particle_pos(rot, -0.05, 0.15, 0.45)
            min_v, max_v = deathstats.calc_oriented_particle_bounds(rot, 1.8, 3.6, 1.6)
            min_a, max_a = deathstats.calc_oriented_particle_bounds(rot, -9.81, -9.81, 0)
        else
            min_p = vector.new(cx - 0.45, cy - 0.05, cz - 0.45)
            max_p = vector.new(cx + 0.45, cy + 0.15, cz + 0.45)
            min_v = vector.new(-1.6, 1.8, -1.6)
            max_v = vector.new(1.6, 3.6, 1.6)
            min_a = vector.new(0, -9.81, 0)
            max_a = vector.new(0, -9.81, 0)
        end

        return {
            amount = 28,
            time = 0.15, -- Moment of death impact burst (not continuous)
            collisiondetection = true,
            collision_removal = false,
            node = { name = ground_node_name, param2 = ground_param2 },
            texture = fallback_tex,
            attached = has_attached and attached_obj or nil,
            -- Legacy client fields (< v5.6)
            minpos = { x = min_p.x, y = min_p.y, z = min_p.z },
            maxpos = { x = max_p.x, y = max_p.y, z = max_p.z },
            minvel = { x = min_v.x, y = min_v.y, z = min_v.z },
            maxvel = { x = max_v.x, y = max_v.y, z = max_v.z },
            minacc = { x = min_a.x, y = min_a.y, z = min_a.z },
            maxacc = { x = max_a.x, y = max_a.y, z = max_a.z },
            minexptime = 0.6,
            maxexptime = 1.2,
            minsize = 0,
            maxsize = 0,
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
---@return string|nil effect_type The type of effect spawned (e.g. "water", "lava", "fire", "flies", "impact")
function deathstats.spawn_corpse_particles(corpse_pos, death_info, attached_obj)
    if not corpse_pos then return {}, nil end
    if deathstats.config.enable_corpse_particles == false then return {}, nil end

    local effect_type = deathstats.get_corpse_effect_type(corpse_pos, death_info)
    local spawner_ids = {}

    if effect_type == "flies" then
        -- Spawn moment-of-death node debris impact burst
        local impact_def = deathstats.create_corpse_particlespawner_def("impact", corpse_pos, attached_obj)
        if impact_def then
            local imp_id = core.add_particlespawner(impact_def)
            if imp_id and imp_id > 0 then
                table.insert(spawner_ids, imp_id)
            end
        end

        -- Spawn continuous buzzing swarm of flies around the corpse
        local flies_def = deathstats.create_corpse_particlespawner_def("flies", corpse_pos, attached_obj)
        if flies_def then
            local fly_id = core.add_particlespawner(flies_def)
            if fly_id and fly_id > 0 then
                table.insert(spawner_ids, fly_id)
            end
        end

        return spawner_ids, effect_type
    end

    local def = deathstats.create_corpse_particlespawner_def(effect_type, corpse_pos, attached_obj)
    if not def then return {}, effect_type end

    local spawner_id = core.add_particlespawner(def)
    if spawner_id and spawner_id > 0 then
        table.insert(spawner_ids, spawner_id)
    end
    return spawner_ids, effect_type
end


