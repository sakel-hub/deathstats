--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local VEC_ZERO = vector.new(0, 0, 0)
local GRAV_ACCEL = { x = 0, y = -9.81, z = 0 }
local FALL_VEL = { x = 0, y = -1.2, z = 0 }
local scratch_pos = { x = 0, y = 0, z = 0 }
local scratch_vel = { x = 0, y = 0, z = 0 }
local DOWNWARD_PROBE_DYS = { 0.25, 0.65, 1.15, 1.65, 2.15 }
local random_float = deathstats.random_float

core.register_entity("deathstats:corpse", {
    initial_properties = {
        visual = "mesh",
        mesh = "character.b3d",
        textures = { "character.png" },
        visual_size = { x = 1, y = 1, z = 1 },
        collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
        stepheight = 0.6,
        selectionbox = { 0, 0, 0, 0, 0, 0 },
        pointable = false,
        physical = true,
        collide_with_objects = false,
        static_save = false,
    },
    on_activate = function(self)
        if self.object then
            if self.object.set_armor_groups then
                self.object:set_armor_groups({ immortal = 1 })
            end
            local ragdoll_enabled = (deathstats.config.enable_corpse_ragdoll ~= false)
            if self.object.set_properties then
                self.object:set_properties({
                    collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
                    stepheight = 0.6,
                    selectionbox = { 0, 0, 0, 0, 0, 0 },
                    pointable = false,
                    physical = ragdoll_enabled,
                })
            end
        end
        self._settled = false
        self._timer = 0
    end,
    on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end
        if deathstats.config.enable_corpse_inspect == false then return end
        local cname = clicker:get_player_name()
        if deathstats.dead_players and deathstats.dead_players[cname] then return end
        deathstats.show_corpse_epitaph_formspec(clicker, self)
    end,
    on_punch = function(self, _hitter, _time_from_last_punch, _tool_capabilities, dir, _damage)
        if not self.object or (self.object.is_valid and not self.object:is_valid()) then
            return true
        end
        local is_settled = self._settled or (self.physics and self.physics.settled)
        if is_settled then
            -- Defensively ensure non-physical so the engine mover cannot translate this entity
            if self.object.set_properties then
                self.object:set_properties({ physical = false })
            end
            if self.object.set_velocity then
                self.object:set_velocity(VEC_ZERO)
            end
            if self.object.set_acceleration then
                self.object:set_acceleration(VEC_ZERO)
            end

            -- Simulate slight punch impact reaction without flying away
            local pos = (self.object.get_pos and self.object:get_pos()) or self._settled_pos
            if pos then
                -- Subtle micro-displacement in horizontal punch direction (stays grounded)
                local dir_x = dir and dir.x or 0
                local dir_z = dir and dir.z or 0
                local dlen = math.sqrt(dir_x * dir_x + dir_z * dir_z)
                if dlen > 0.001 and self.object.set_pos then
                    local base_pos = self._settled_pos or pos
                    local micro_x = (dir_x / dlen) * 0.04
                    local micro_z = (dir_z / dlen) * 0.04
                    self.object:set_pos(vector.new(base_pos.x + micro_x, base_pos.y, base_pos.z + micro_z))
                end

                -- Play node impact sound & debris burst
                local under_pos = vector.new(pos.x, pos.y - 0.5, pos.z)
                local node = core.get_node_or_nil(under_pos) or core.get_node_or_nil(pos)
                local node_name = (node and node.name and node.name ~= "air" and node.name ~= "ignore") and node.name
                    or (deathstats.get_fallback_ground_node and deathstats.get_fallback_ground_node())
                if node_name then
                    local ndef = core.registered_nodes[node_name]
                    local sound_name, base_gain, base_pitch = deathstats.get_node_impact_sound(ndef)
                    if sound_name then
                        core.sound_play(sound_name, {
                            pos = pos,
                            gain = math.min(1.0, math.max(0.2, (base_gain or 1.0) * 0.5)),
                            pitch = base_pitch or 1.0,
                            max_hear_distance = 16,
                        }, true)
                    end
                    if deathstats.spawn_impact_burst then
                        deathstats.spawn_impact_burst(pos, node_name, 0.4)
                    end
                end
            end

            -- Schedule deferred check to nullify any engine-level C++ knockback and restore anchor
            core.after(0, function()
                if not self.object or (self.object.is_valid and not self.object:is_valid()) then return end
                if self.object.set_velocity then self.object:set_velocity(VEC_ZERO) end
                if self.object.set_acceleration then self.object:set_acceleration(VEC_ZERO) end
                if self.object.set_properties then self.object:set_properties({ physical = false }) end
                if self._settled_pos and self.object.set_pos then
                    self.object:set_pos(self._settled_pos)
                end
            end)
        end
        return true
    end,
    on_step = function(self, dtime, moveresult)
        if self._decay_time and core.get_gametime() >= self._decay_time then
            deathstats.dissolve_corpse(self.object)
            return
        end
        if self._settled then
            -- Guard against any rogue velocity or drift on settled corpse
            if self.object and (not self.object.is_valid or self.object:is_valid()) then
                if self.object.get_velocity then
                    local v = self.object:get_velocity()
                    if v and (v.x ~= 0 or v.y ~= 0 or v.z ~= 0) then
                        self.object:set_velocity(VEC_ZERO)
                    end
                end
                if self._settled_pos and self.object.get_pos and self.object.set_pos then
                    local cp = self.object:get_pos()
                    if cp and vector.distance(cp, self._settled_pos) > 0.05 then
                        self.object:set_pos(self._settled_pos)
                    end
                end
            end

            -- Throttled ground support check (every 0.35s) to avoid node queries every step
            self._ground_check_timer = (self._ground_check_timer or 0) + (dtime or 0)
            if self._ground_check_timer >= 0.35 then
                self._ground_check_timer = 0
                local cur_p = (self.object and self.object.get_pos and self.object:get_pos()) or self._settled_pos
                if cur_p and not deathstats.has_ground_support(cur_p) then
                    -- Wake up into ragdoll free-fall if ground beneath was dug out
                    self._settled = false
                    self._settled_pos = nil
                    if self._particle_spawners then
                        for _, pid in ipairs(self._particle_spawners) do
                            core.delete_particlespawner(pid)
                        end
                        self._particle_spawners = nil
                    end
                    self._effect_type = nil
                    local pname = self._player_name
                    local cdata = pname and deathstats.player_camera_data and deathstats.player_camera_data[pname]
                    if cdata then
                        if cdata.particle_spawners then
                            for _, pid in ipairs(cdata.particle_spawners) do
                                core.delete_particlespawner(pid)
                            end
                            cdata.particle_spawners = nil
                        end
                        cdata.current_effect_type = nil
                        cdata.corpse_settled = false
                        cdata.corpse_settled_particles_checked = false
                    end
                    self._timer = 0
                    self._air_timer = 0
                    self._slide_timer = 0
                    self._bounce_count = 0
                    if self.object.set_properties then
                        self.object:set_properties({
                            physical = true,
                            pointable = false,
                        })
                    end
                    if self.object.set_acceleration then
                        self.object:set_acceleration(GRAV_ACCEL)
                    end
                    if self.object.set_velocity then
                        self.object:set_velocity(FALL_VEL)
                    end
                    return
                end
            end
            return
        end
        if not dtime or dtime <= 0 then return end
        if not self.object or (self.object.is_valid and not self.object:is_valid()) then return end

        self._timer = (self._timer or 0) + dtime

        local pos = self.object.get_pos and self.object:get_pos()
        if not pos or (pos.y and (pos.y < -31000 or pos.y > 31000)) then
            deathstats.settle_corpse_at_rest(self)
            return
        end

        -- Chunk safety: use get_node_or_nil to prevent force-loading new mapblocks
        local node = core.get_node_or_nil(pos)
        if not node or node.name == "ignore" then
            deathstats.settle_corpse_at_rest(self)
            return
        end

        local cur_v = (self.object.get_velocity and self.object:get_velocity()) or VEC_ZERO
        local vx, vy, vz = cur_v.x or 0, cur_v.y or 0, cur_v.z or 0
        -- Sanity check: prevent NaN physics corruption
        if vx ~= vx or vy ~= vy or vz ~= vz then
            deathstats.settle_corpse_at_rest(self)
            return
        end

        local ndef = core.registered_nodes[node.name]
        local is_liquid = (ndef and ndef.liquidtype and ndef.liquidtype ~= "none")
            or deathstats.is_in_liquid(pos)
        local is_lava = is_liquid and ((node.name:find("lava") ~= nil) or (ndef and ndef.groups and ndef.groups.lava))

        if is_liquid then
            local drag
            local target_acc_y
            scratch_pos.x = pos.x
            scratch_pos.y = pos.y + 0.6
            scratch_pos.z = pos.z
            local node_above = core.get_node_or_nil(scratch_pos)
            local ndef_above = node_above and node_above.name ~= "ignore" and core.registered_nodes[node_above.name]
            local above_is_air = not ndef_above or ndef_above.liquidtype == "none"
            local above_is_solid = ndef_above and ndef_above.walkable and ndef_above.liquidtype == "none"

            if is_lava then
                -- Dense viscous lava buoyancy & drag
                drag = math.exp(-4.5 * dtime)
                target_acc_y = above_is_air and -3.0 or 5.5
                if self.object.set_acceleration then
                    self.object:set_acceleration({ x = 0, y = target_acc_y, z = 0 })
                end
                local target_vy = (cur_v.y + target_acc_y * dtime) * drag
                if above_is_air and target_vy > 0.3 then
                    target_vy = 0.05
                end
                if self.object.set_velocity then
                    scratch_vel.x = cur_v.x * drag
                    scratch_vel.y = target_vy
                    scratch_vel.z = cur_v.z * drag
                    self.object:set_velocity(scratch_vel)
                end
            else
                -- Water / liquid buoyancy
                drag = math.exp(-2.8 * dtime)
                target_acc_y = above_is_air and -3.0 or 4.5
                if self.object.set_acceleration then
                    self.object:set_acceleration({ x = 0, y = target_acc_y, z = 0 })
                end
                local target_vy = (cur_v.y + target_acc_y * dtime) * drag
                if above_is_air and target_vy > 0.4 then
                    target_vy = 0.1
                end
                if self.object.set_velocity then
                    scratch_vel.x = cur_v.x * drag
                    scratch_vel.y = target_vy
                    scratch_vel.z = cur_v.z * drag
                    self.object:set_velocity(scratch_vel)
                end
            end

            local speed_liq = math.sqrt(cur_v.x * cur_v.x + cur_v.z * cur_v.z)
            if (above_is_air or above_is_solid or self._timer > 8.0) and speed_liq < 0.2 and math.abs(cur_v.y) < 0.25 and self._timer > 1.2 then
                deathstats.settle_corpse_at_rest(self)
                return
            end
        else
            -- Airborne or ground contact
            local touching_ground = false
            local had_vertical_collision = false
            local had_wall_collision = false
            local collision_old_vy = nil
            local ground_node_name = nil

            local wall_collision_axis = nil
            if moveresult and type(moveresult) == "table" then
                touching_ground = moveresult.touching_ground or false
                if moveresult.collisions and type(moveresult.collisions) == "table" then
                    for i = 1, #moveresult.collisions do
                        local col = moveresult.collisions[i]
                        if col.axis == "y" and col.old_velocity and col.old_velocity.y < -0.6 then
                            had_vertical_collision = true
                            collision_old_vy = col.old_velocity.y
                            if col.node_pos then
                                local n = core.get_node_or_nil(col.node_pos)
                                if n and n.name ~= "air" and n.name ~= "ignore" then
                                    ground_node_name = n.name
                                end
                            end
                        elseif (col.axis == "x" or col.axis == "z") and col.old_velocity then
                            local h_old = math.sqrt((col.old_velocity.x or 0)^2 + (col.old_velocity.z or 0)^2)
                            if h_old > 0.8 then
                                had_wall_collision = true
                                self._had_wall_collision = true
                                wall_collision_axis = col.axis
                            end
                        end
                    end
                end
            end

            -- Discrete node scan check for solid ground beneath corpse
            scratch_pos.x = pos.x
            scratch_pos.y = pos.y - 0.25
            scratch_pos.z = pos.z
            local node_below1 = core.get_node_or_nil(scratch_pos)
            local def1 = node_below1 and node_below1.name ~= "ignore" and core.registered_nodes[node_below1.name]
            local has_ground = (def1 and def1.walkable and node_below1.name ~= "air")
            local ground_node_y = has_ground and math.floor(pos.y - 0.25 + 0.5) or nil
            if not has_ground then
                scratch_pos.y = pos.y - 0.65
                local node_below2 = core.get_node_or_nil(scratch_pos)
                local def2 = node_below2 and node_below2.name ~= "ignore" and core.registered_nodes[node_below2.name]
                has_ground = (def2 and def2.walkable and node_below2.name ~= "air")
                if has_ground and node_below2 then
                    ground_node_name = ground_node_name or node_below2.name
                    ground_node_y = math.floor(pos.y - 0.65 + 0.5)
                else
                    scratch_pos.y = pos.y - 1.15
                    local node_below3 = core.get_node_or_nil(scratch_pos)
                    local def3 = node_below3 and node_below3.name ~= "ignore" and core.registered_nodes[node_below3.name]
                    if def3 and def3.walkable and node_below3.name ~= "air" then
                        ground_node_name = ground_node_name or node_below3.name
                        ground_node_y = math.floor(pos.y - 1.15 + 0.5)
                    end
                end
            elseif node_below1 then
                ground_node_name = ground_node_name or node_below1.name
            end
            local ground_top = ground_node_y and (ground_node_y + 0.5)
            local ground_clearance = ground_top and (pos.y - ground_top)

            if not moveresult then
                touching_ground = has_ground and cur_v.y <= 0.35 and (math.abs(cur_v.y) < 0.35 or self._timer > 0.15)
                if has_ground and self._last_vy and self._last_vy < -2.2 and cur_v.y <= 0.35 then
                    had_vertical_collision = true
                    collision_old_vy = self._last_vy
                end
            else
                -- If moveresult is present, also confirm ground if solid node is directly beneath and vertical speed is small
                if has_ground and math.abs(cur_v.y) < 0.35 then
                    touching_ground = true
                end
            end

            -- If ground collision occurred but node wasn't in collision list, check downward
            if not ground_node_name and (had_vertical_collision or touching_ground) then
                for i = 1, #DOWNWARD_PROBE_DYS do
                    local dy = DOWNWARD_PROBE_DYS[i]
                    scratch_pos.x = pos.x
                    scratch_pos.y = pos.y - dy
                    scratch_pos.z = pos.z
                    local n = core.get_node_or_nil(scratch_pos)
                    if n and n.name ~= "air" and n.name ~= "ignore" then
                        local d = core.registered_nodes[n.name]
                        if d and d.walkable then
                            ground_node_name = n.name
                            break
                        end
                    end
                end
                ground_node_name = ground_node_name or deathstats.get_fallback_ground_node()
            end

            -- Inelastic ground bounce handling (max 2 bounces before ground slide)
            local max_bounces = 2
            self._bounce_count = self._bounce_count or 0
            if had_vertical_collision and self._bounce_count < max_bounces then
                local old_impact_vy = math.abs(collision_old_vy or cur_v.y)
                local restitution = tonumber(deathstats.config.ragdoll_restitution) or 0.25
                local ndef_ground = ground_node_name and core.registered_nodes[ground_node_name]
                local is_soft = deathstats.is_soft_node(ndef_ground, ground_node_name)
                if is_soft then
                    restitution = restitution * 0.4
                end

                local rebound_vy = old_impact_vy * restitution
                if rebound_vy >= 0.8 then
                    self._bounce_count = self._bounce_count + 1
                    local rebound_vx = cur_v.x * 0.65
                    local rebound_vz = cur_v.z * 0.65
                    scratch_vel.x = rebound_vx
                    scratch_vel.y = rebound_vy
                    scratch_vel.z = rebound_vz
                    if self.object.set_velocity then
                        self.object:set_velocity(scratch_vel)
                    end
                    if self.object.set_acceleration then
                        self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                    end

                    -- Impact transfers linear momentum into rotational tumbling torque
                    if self._rot_speed and deathstats.config.ragdoll_tumbling ~= false then
                        local torque = math.sqrt(rebound_vx * rebound_vx + rebound_vz * rebound_vz) * 0.9
                        self._rot_speed.x = self._rot_speed.x + torque
                        self._rot_speed.z = self._rot_speed.z + (math.random() - 0.5) * torque
                    end

                    if deathstats.config.enable_corpse_impact_sounds ~= false and deathstats.config.enable_sounds ~= false then
                        local sound_name, base_gain, base_pitch = deathstats.get_node_impact_sound(ndef_ground)
                        if sound_name then
                            local impact_mult = math.min(1.0, math.max(0.25, old_impact_vy / 8.0))
                            core.sound_play(sound_name, {
                                pos = pos,
                                gain = math.min(1.0, base_gain * impact_mult * 1.5),
                                pitch = base_pitch,
                                max_hear_distance = 20,
                            }, true)
                        end
                    end
                    if deathstats.config.enable_corpse_particles ~= false and not self._impact_particles_done then
                        deathstats.spawn_impact_burst(pos, ground_node_name, old_impact_vy)
                        if self._bounce_count >= max_bounces then
                            self._impact_particles_done = true
                        end
                    end

                    -- Apply immediate physical impact reaction to corpse limbs on bounce
                    deathstats.apply_corpse_bounce_impact(self.object, old_impact_vy, scratch_vel, self._rot, self._bounce_count)

                    -- Record shock state for decaying rebound flight oscillation
                    self._bounce_shock = math.min(1.6, math.max(0.35, old_impact_vy / 5.5))
                    self._bounce_shock_timer = 0.45
                    self._flail_timer = 1.0 -- immediately allow next flight limb update

                    self._last_vy = rebound_vy
                    return
                end
            end

            if had_wall_collision then
                local defl_vx = cur_v.x * -0.2
                local defl_vz = cur_v.z * -0.2
                if self.object.set_velocity then
                    scratch_vel.x = defl_vx
                    scratch_vel.y = cur_v.y
                    scratch_vel.z = defl_vz
                    self.object:set_velocity(scratch_vel)
                end
                -- Inelastic angular braking: vertical surface absorbs spinning momentum
                if self._rot_speed then
                    self._rot_speed.x = (self._rot_speed.x or 0) * 0.15
                    self._rot_speed.z = (self._rot_speed.z or 0) * 0.15
                end
                -- Gently deflect yaw parallel to wall so head/feet do not penetrate wall blocks
                if wall_collision_axis and self._base_yaw then
                    if wall_collision_axis == "x" then
                        local cy = math.cos(self._base_yaw)
                        self._base_yaw = (cy >= 0) and 0 or math.pi
                    elseif wall_collision_axis == "z" then
                        local sy = math.sin(self._base_yaw)
                        self._base_yaw = (sy >= 0) and (math.pi * 0.5) or (math.pi * 1.5)
                    end
                    self._rot = self._rot or { x = 0, y = self._base_yaw, z = 0 }
                    self._rot.y = self._base_yaw
                    if self.object.set_rotation then
                        self.object:set_rotation(self._rot)
                    end
                end
            end

            if touching_ground then
                self._air_timer = 0
                self._slide_timer = (self._slide_timer or 0) + dtime

                local pitch_slope = 0
                if deathstats.config.enable_slope_pitch ~= false then
                    pitch_slope = deathstats.detect_corpse_slope_pitch(pos, self._base_yaw or 0) or 0
                end

                local down_x, down_z, slope_angle = deathstats.get_terrain_downhill_dir(pos, self._base_yaw or 0, pitch_slope)
                local eff_slope = math.max(slope_angle, math.abs(pitch_slope))

                -- Active uphill suppression: on any slope or stairs, brake velocity moving against downhill direction
                if eff_slope > 0.25 and (down_x ~= 0 or down_z ~= 0) then
                    local v_down = cur_v.x * down_x + cur_v.z * down_z
                    if v_down < 0 then
                        local brake = math.exp(-8.0 * dtime)
                        cur_v.x = cur_v.x * brake
                        cur_v.z = cur_v.z * brake
                    end
                end

                local accel_mag = 9.81 * math.sin(eff_slope) - 4.5 * math.cos(eff_slope)
                -- Steep slope (> 28 degrees = ~0.48 rad): gravity overcomes friction and corpse rolls downhill
                if eff_slope > 0.48 and self._slide_timer < 4.0 and (down_x ~= 0 or down_z ~= 0) and accel_mag > 0 then
                    local new_vx = cur_v.x + down_x * accel_mag * dtime
                    local new_vz = cur_v.z + down_z * accel_mag * dtime
                    local new_vy = math.min(-1.5, cur_v.y)
                    if self.object.set_velocity then
                        scratch_vel.x = new_vx
                        scratch_vel.y = new_vy
                        scratch_vel.z = new_vz
                        self.object:set_velocity(scratch_vel)
                    end
                    if self.object.set_acceleration then
                        self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                    end
                    if self._rot and deathstats.config.ragdoll_tumbling ~= false then
                        -- Keep pitch aligned with slope incline so torso lays flush with slope face
                        -- Roll like a barrel/log along longitudinal spine axis (Roll Z) to avoid dipping head/feet into ground
                        self._rot.x = pitch_slope
                        self._rot.z = (self._rot.z or 0) + accel_mag * 1.0 * dtime
                        if self.object.set_rotation then
                            self.object:set_rotation(self._rot)
                        end
                    end
                else
                    -- Kinetic surface friction on ground
                    local friction = math.exp(-4.5 * dtime)
                    local new_vx = cur_v.x * friction
                    local new_vz = cur_v.z * friction
                    if self.object.set_velocity then
                        scratch_vel.x = new_vx
                        scratch_vel.y = cur_v.y
                        scratch_vel.z = new_vz
                        self.object:set_velocity(scratch_vel)
                    end
                    -- Keep downward gravity active so corpse rests firmly on ground and drops over edges
                    if self.object.set_acceleration then
                        self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                    end

                    -- Align pitch flush towards ground slope to avoid digging into terrain
                    if self._rot then
                        self._rot.x = pitch_slope or 0
                        -- Ground friction dampens roll angular velocity, preserving resting roll angle
                        if self._rot_speed and self._rot_speed.z and math.abs(self._rot_speed.z) > 0.01 then
                            self._rot.z = (self._rot.z or 0) + self._rot_speed.z * dtime
                            self._rot_speed.z = self._rot_speed.z * math.exp(-4.5 * dtime)
                        end
                        if self.object.set_rotation then
                            self.object:set_rotation(self._rot)
                        end
                    end

                    local ground_speed = math.sqrt(new_vx * new_vx + new_vz * new_vz)

                    -- Decay bounce shock timer while on ground
                    if self._bounce_shock_timer and self._bounce_shock_timer > 0 then
                        self._bounce_shock_timer = self._bounce_shock_timer - dtime
                        self._bounce_shock = (self._bounce_shock or 0) * math.exp(-4.5 * dtime)
                        if self._bounce_shock_timer <= 0 then
                            self._bounce_shock = 0
                        end
                    end

                    -- Dynamic limb movement while sliding on ground or tumbling down stairs/hills
                    if ground_speed > 0.2 or (self._bounce_shock and self._bounce_shock > 0.05) then
                        self._flail_timer = (self._flail_timer or 0) + dtime
                        local flail_hz = deathstats.config.ragdoll_flail_rate or 10.0
                        local flail_interval = 1.0 / flail_hz
                        if ground_speed < 1.5 then
                            flail_interval = flail_interval * 1.5
                        end
                        if self._flail_timer >= flail_interval then
                            self._flail_timer = 0
                            scratch_vel.x = new_vx
                            scratch_vel.y = cur_v.y
                            scratch_vel.z = new_vz
                            deathstats.update_ragdoll_slide_limbs(self.object, scratch_vel, self._base_yaw or 0, self._bounce_shock, self._slide_timer)
                        end
                    end

                    if ground_speed < 0.15 or self._slide_timer > 4.5 then
                        deathstats.settle_corpse_at_rest(self)
                        return
                    end
                end
            else
                -- In air: gravity acceleration and aerodynamic drag
                self._slide_timer = 0
                self._air_timer = (self._air_timer or 0) + dtime

                if self.object.set_acceleration then
                    self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
                end
                local air_drag = math.exp(-0.25 * dtime)
                if self.object.set_velocity then
                    scratch_vel.x = cur_v.x * air_drag
                    scratch_vel.y = cur_v.y
                    scratch_vel.z = cur_v.z * air_drag
                    self.object:set_velocity(scratch_vel)
                end

                -- Tumbling rotation with aerodynamic angular damping
                if self._tumbling and (deathstats.config.ragdoll_tumbling ~= false) then
                    self._rot = self._rot or { x = 0, y = self._base_yaw or 0, z = 0 }
                    self._rot_speed = self._rot_speed or { x = 0, y = 0, z = 0 }
                    local ang_drag = math.exp(-0.6 * dtime)
                    self._rot_speed.x = self._rot_speed.x * ang_drag
                    self._rot_speed.z = self._rot_speed.z * ang_drag
                    self._rot.x = self._rot.x + self._rot_speed.x * dtime
                    self._rot.z = self._rot.z + self._rot_speed.z * dtime

                    -- Ground proximity envelope: clamp pitch to prevent head/feet dipping below floor
                    if ground_clearance and ground_clearance < 0.85 then
                        local ratio = math.max(0, math.min(1.0, ground_clearance / 0.85))
                        local max_pitch = math.asin(ratio)
                        if math.abs(self._rot.x) > max_pitch then
                            self._rot.x = math.max(-max_pitch, math.min(max_pitch, self._rot.x))
                            if self._rot_speed then self._rot_speed.x = 0 end
                        end
                    end

                    if self.object.set_rotation then
                        self.object:set_rotation(self._rot)
                    end
                end

                -- Dynamic limb flail during high velocity flight or rebound shock (throttled to ragdoll_flail_rate Hz)
                local speed_3d = math.sqrt(cur_v.x * cur_v.x + cur_v.y * cur_v.y + cur_v.z * cur_v.z)
                local flail_hz = deathstats.config.ragdoll_flail_rate or 10.0
                local flail_interval = 1.0 / flail_hz
                if speed_3d < 2.0 then
                    flail_interval = flail_interval * 2.0
                end

                -- Decay bounce shock timer
                if self._bounce_shock_timer and self._bounce_shock_timer > 0 then
                    self._bounce_shock_timer = self._bounce_shock_timer - dtime
                    self._bounce_shock = (self._bounce_shock or 0) * math.exp(-4.5 * dtime)
                    if self._bounce_shock_timer <= 0 then
                        self._bounce_shock = 0
                    end
                end

                if speed_3d > 1.0 or (self._bounce_shock and self._bounce_shock > 0.05) then
                    self._flail_timer = (self._flail_timer or 0) + dtime
                    if self._flail_timer >= flail_interval then
                        self._flail_timer = 0
                        deathstats.update_ragdoll_flight_limbs(self.object, cur_v, self._base_yaw or 0, self._bounce_shock)
                    end
                end

                -- Anti-snag: if corpse has stopped moving even without touching_ground flag (e.g. caught on ledge/corner/wall)
                if (self._timer or 0) > 0.35 and speed_3d < 0.12 and math.abs(cur_v.y) < 0.15 then
                    deathstats.settle_corpse_at_rest(self)
                    return
                end

                -- Airborne failsafe: if falling for over 10 seconds (e.g. huge drop or snagged geometry)
                if self._air_timer > 10.0 then
                    local ground_y = deathstats.find_ground_surface(pos, nil, self._death_info or { category = "fall" })
                    if ground_y and (pos.y - ground_y) <= 40.0 then
                        if self.object.set_pos then
                            scratch_pos.x = pos.x
                            scratch_pos.y = ground_y + 0.02
                            scratch_pos.z = pos.z
                            self.object:set_pos(scratch_pos)
                        end
                    end
                    deathstats.settle_corpse_at_rest(self)
                    return
                end
            end
        end

        self._last_vy = cur_v.y
    end,
})

--- Register attached wielditem entity displayed in the corpse's right hand when inventory is retained
core.register_entity("deathstats:corpse_wielditem", {
    initial_properties = {
        visual = "wielditem",
        visual_size = { x = 0.25, y = 0.25, z = 0.25 },
        pointable = false,
        physical = false,
        collide_with_objects = false,
        static_save = false,
    },
    on_activate = function(self)
        if self.object then
            self.object:set_armor_groups({ immortal = 1 })
            if self.object.set_properties then
                self.object:set_properties({
                    selectionbox = { 0, 0, 0, 0, 0, 0 },
                    pointable = false,
                    physical = false,
                    collide_with_objects = false,
                })
            end
        end
    end,
    on_step = function(self)
        local parent = self.object and self.object.get_attach and self.object:get_attach()
        if not parent then
            if self.object and self.object.remove then
                self.object:remove()
            end
        end
    end,
})


--- Set the corpse entity into a pose matching the active model
---@param corpse ObjectRef The corpse entity object
---@param mesh_name string|nil The model mesh name
---@param anim_name string|nil "lay" (default) or "sit"
function deathstats.pose_corpse(corpse, mesh_name, anim_name)
    if not corpse then return end
    local req_anim = anim_name or "lay"

    local anim_def = nil
    local papi = rawget(_G, "player_api") or rawget(_G, "x_player_api")
    if papi and type(papi) == "table" and type(papi.registered_models) == "table" and mesh_name and papi.registered_models[mesh_name] then
        local model_def = papi.registered_models[mesh_name]
        if model_def and type(model_def) == "table" and model_def.animations then
            if req_anim == "sit" then
                anim_def = model_def.animations.sit
            else
                anim_def = model_def.animations.lay or model_def.animations.die
            end
        end
    end

    local def_mod = rawget(_G, "default")
    if not anim_def and def_mod and def_mod.registered_player_models and mesh_name and def_mod.registered_player_models[mesh_name] then
        local model_def = def_mod.registered_player_models[mesh_name]
        if model_def.animations then
            if req_anim == "sit" then
                anim_def = model_def.animations.sit
            else
                anim_def = model_def.animations.lay or model_def.animations.die
            end
        end
    end

    local mcl_p = rawget(_G, "mcl_player")
    if not anim_def and mcl_p and mcl_p.registered_players then
        anim_def = (req_anim == "sit") and { x = 81, y = 160 } or { x = 162, y = 166 }
    end

    if not anim_def then
        anim_def = (req_anim == "sit") and { x = 81, y = 160 } or { x = 162, y = 166 }
    end

    -- Multi-track glTF support (track name string or { track = "lay", ... })
    local track_name = (type(anim_def) == "string" and anim_def) or (type(anim_def) == "table" and anim_def.track)
    if track_name then
        if corpse.play_animation then
            corpse:play_animation(track_name, { speed = 1, loop = false, priority = 0 })
        end
        if corpse.set_animation then
            corpse:set_animation({ x = 0, y = 0 }, 1, 0, false)
        end
        return
    end

    -- Freeze pose on the final frame (lay frame 166 or sit frame 81)
    local target_frame = (req_anim == "sit") and ((type(anim_def) == "table" and (anim_def.x or anim_def[1])) or 81)
        or ((type(anim_def) == "table" and (anim_def.y or anim_def[2])) or 166)

    if corpse.set_animation then
        corpse:set_animation({ x = target_frame, y = target_frame }, 1, 0, false)
    end
end

--- Rotate a corpse bone in 3D space (local X, Y, Z axes)
--- Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)
---@param corpse ObjectRef The corpse entity object
---@param bone_name string The name of the bone to rotate
---@param rot_vec Vector The rotation vector in radians (x, y, z)
---@return boolean success True if the rotation was applied
function deathstats.rotate_corpse_bone(corpse, bone_name, rot_vec)
    if not corpse or not bone_name or not rot_vec then return false end

    -- Multiplayer network bandwidth optimization: skip bone packet if angular change is below threshold
    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    if luaent then
        luaent._applied_bones = luaent._applied_bones or {}
        local last = luaent._applied_bones[bone_name]
        local rx = rot_vec.x or 0
        local ry = rot_vec.y or 0
        local rz = rot_vec.z or 0
        if last then
            local dx = math.abs(rx - last.x)
            local dy = math.abs(ry - last.y)
            local dz = math.abs(rz - last.z)
            if dx < 0.05 and dy < 0.05 and dz < 0.05 then
                return true
            end
        end
        luaent._applied_bones[bone_name] = { x = rx, y = ry, z = rz }
    end

    -- Luanti >= 5.9.0 ObjectRef:set_bone_override
    -- Vec rotation is in radians; absolute = false applies relative to the frozen lay animation pose
    if corpse.set_bone_override then
        local success = corpse:set_bone_override(bone_name, {
            rotation = {
                vec = vector.new(rot_vec.x or 0, rot_vec.y or 0, rot_vec.z or 0),
                absolute = false,
                interpolation = 0,
            },
        })
        if success ~= false then return true end
    end

    -- Luanti <= 5.8 fallback: set_bone_position(bone, pos, rot_deg)
    if corpse.set_bone_position then
        local base_store = (type(luaent) == "table" and luaent) or (type(corpse) == "table" and corpse) or nil
        local base
        if base_store then
            if not base_store._base_bone_rot then
                base_store._base_bone_rot = {}
            end
            if not base_store._base_bone_rot[bone_name] then
                local cur_pos, cur_rot
                if corpse.get_bone_position then
                    cur_pos, cur_rot = corpse:get_bone_position(bone_name)
                end
                base_store._base_bone_rot[bone_name] = {
                    pos = cur_pos or vector.zero(),
                    rot = cur_rot or vector.zero(),
                }
            end
            base = base_store._base_bone_rot[bone_name]
        else
            local cur_pos, cur_rot
            if corpse.get_bone_position then
                cur_pos, cur_rot = corpse:get_bone_position(bone_name)
            end
            base = {
                pos = cur_pos or vector.zero(),
                rot = cur_rot or vector.zero(),
            }
        end
        local deg_vec = vector.new(
            base.rot.x + math.deg(rot_vec.x or 0),
            base.rot.y + math.deg(rot_vec.y or 0),
            base.rot.z + math.deg(rot_vec.z or 0)
        )
        corpse:set_bone_position(bone_name, base.pos, deg_vec)
        return true
    end

    return false
end

--- Rotate a corpse bone strictly along the horizontal floor plane (around local Z axis)
--- Uses modern set_bone_override (Luanti >= 5.9, radians, relative) with fallback to set_bone_position (Luanti <= 5.8, degrees)
---@param corpse ObjectRef The corpse entity object
---@param bone_name string The name of the bone to rotate
---@param z_rad number The rotation angle in radians around local Z axis
---@return boolean success True if the rotation was applied
function deathstats.rotate_corpse_bone_planar(corpse, bone_name, z_rad)
    return deathstats.rotate_corpse_bone(corpse, bone_name, vector.new(0, 0, z_rad))
end

--- Programmatically rotate corpse limbs on fall death to simulate fractured / broken bones.
--- Rotates arms, legs, and head strictly along the horizontal floor plane (around local Z axis),
--- guaranteeing that limbs stay flush touching the ground without lifting into the air or clipping underground.
---@param corpse ObjectRef The corpse entity object
---@param custom_angles table<string, number>|nil Optional map of bone names to z-axis rotation radians
---@return table<string, number> applied_angles Map of bone names to applied z radians
function deathstats.fracture_corpse_limbs(corpse, custom_angles)
    if not corpse then return {} end

    local angles = {}
    if custom_angles and type(custom_angles) == "table" then
        for k, v in pairs(custom_angles) do
            if type(v) == "table" then
                angles[k] = v
            else
                angles[k] = tonumber(v) or 0
            end
        end
    else
        -- Anatomical broken bone angle ranges (local Z rotation):
        -- Left Arm: 50% chance splayed outwards (-80 to -35 deg), 30% folded inward across torso (+20 to +55 deg)
        local left_arm_deg = (math.random() < 0.5) and random_float(-80, -35) or random_float(20, 55)
        -- Right Arm: 50% chance splayed outwards (+35 to +80 deg), 30% folded inward across torso (-55 to -20 deg)
        local right_arm_deg = (math.random() < 0.5) and random_float(35, 80) or random_float(-55, -20)
        -- Legs: Anatomically, corpses naturally splay outward (Left Leg -70 to -15 deg, Right Leg +15 to +70 deg).
        -- Crossed legs (adducted across body midline: Left Leg > 0 or Right Leg < 0) occur at a reduced, natural probability (~4%).
        -- If one leg crosses inward, the other leg remains splayed outward to prevent unnatural double-crossed knots.
        local cross_prob = 0.04
        local left_leg_deg, right_leg_deg
        if math.random() < cross_prob then
            if math.random() < 0.5 then
                -- Left leg crosses inward across midline (+10 to +30 deg); Right leg stays outward (+15 to +70 deg)
                left_leg_deg = random_float(10, 30)
                right_leg_deg = random_float(15, 70)
            else
                -- Right leg crosses inward across midline (-30 to -10 deg); Left leg stays outward (-70 to -15 deg)
                left_leg_deg = random_float(-70, -15)
                right_leg_deg = random_float(-30, -10)
            end
        else
            -- Both legs naturally splay outward (abducted away from each other)
            left_leg_deg = random_float(-70, -15)
            right_leg_deg = random_float(15, 70)
        end
        -- Head: limp neck turned sideways on the floor (-45 to +45 deg)
        local head_deg = random_float(-45, 45)

        angles["Arm_Left"] = math.rad(left_arm_deg)
        angles["Arm_Right"] = math.rad(right_arm_deg)
        angles["Leg_Left"] = math.rad(left_leg_deg)
        angles["Leg_Right"] = math.rad(right_leg_deg)
        angles["Head"] = math.rad(head_deg)
    end

    local applied = {}
    for bone_name, val in pairs(angles) do
        local applied_ok
        if type(val) == "table" then
            applied_ok = deathstats.rotate_corpse_bone(corpse, bone_name, val)
        else
            applied_ok = deathstats.rotate_corpse_bone_planar(corpse, bone_name, val)
        end
        if applied_ok then
            applied[bone_name] = val
        end
    end

    return applied
end

--- Get the active corpse entity for a player name if currently spawned
---@param player_name string
---@return ObjectRef|nil corpse The active corpse entity or nil
function deathstats.get_corpse(player_name)
    if not player_name or player_name == "" then return nil end
    local data = deathstats.player_camera_data and deathstats.player_camera_data[player_name]
    return data and data.corpse
end

--- Get the attached wielditem entity from a corpse
---@param corpse ObjectRef|nil The corpse entity object
---@return ObjectRef|nil went The attached wielditem entity or nil
function deathstats.get_corpse_wielditem(corpse)
    if not corpse then return nil end
    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    return luaent and luaent._wielditem_entity
end

--- Safely remove a corpse entity and any attached wielditem entity
---@param corpse ObjectRef|nil The corpse object reference
function deathstats.remove_corpse(corpse)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local xbows_mod = rawget(_G, "XBows")
    if xbows_mod and type(xbows_mod.cleanup_corpse_arrows) == "function" and corpse.get_luaentity then
        xbows_mod.cleanup_corpse_arrows(corpse)
    end
    -- Also remove any attached child entities (arrows, custom objects) to prevent orphans
    if corpse.get_children then
        local children = corpse:get_children()
        if type(children) == "table" then
            for i = 1, #children do
                local child = children[i]
                if child and (not child.is_valid or child:is_valid()) and child.remove then
                    child:remove()
                end
            end
        end
    end
    local went = deathstats.get_corpse_wielditem(corpse)
    if went and (not went.is_valid or went:is_valid()) and went.remove then
        went:remove()
    end
    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    if luaent then
        if type(luaent._particle_spawners) == "table" then
            for i = 1, #luaent._particle_spawners do
                core.delete_particlespawner(luaent._particle_spawners[i])
            end
            luaent._particle_spawners = nil
        end
        luaent._wielditem_entity = nil
    end
    if deathstats.player_corpses then
        for pname, c_obj in pairs(deathstats.player_corpses) do
            if c_obj == corpse then
                deathstats.player_corpses[pname] = nil
            end
        end
    end
    if (not corpse.is_valid or corpse:is_valid()) and corpse.remove then
        corpse:remove()
    end
end

--- Spawn gentle ash / smoke dissipation particles when a corpse decays


--- Dissolve and cleanly remove a persistent corpse with dissipation particles
---@param corpse ObjectRef|nil The corpse object reference
function deathstats.dissolve_corpse(corpse)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local pos = corpse.get_pos and corpse:get_pos()
    if pos then
        deathstats.spawn_decay_particles(pos)
    end
    deathstats.remove_corpse(corpse)
end

--- Unhide and restore native visual scale for any arrows attached to a corpse
--- Defensively resets is_visible = true and restores visual_size if previously zeroed
---@param corpse ObjectRef|nil The corpse entity object
function deathstats.unhide_corpse_arrows(corpse)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    if not corpse.get_children then return end
    local children = corpse:get_children()
    if type(children) ~= "table" then return end
    for i = 1, #children do
        local child = children[i]
        if child and (not child.is_valid or child:is_valid()) then
            local cent = child.get_luaentity and child:get_luaentity()
            if cent and (cent._is_arrow or (cent.name and cent.name:find("^x_bows:"))) then
                if child.set_properties then
                    local restore_props = { is_visible = true }
                    if child.get_properties then
                        local cp = child:get_properties()
                        if cp and cp.visual_size and cp.visual_size.x == 0 and cp.visual_size.y == 0 then
                            local init_vs = cent.initial_properties and cent.initial_properties.visual_size
                            restore_props.visual_size = init_vs or { x = 1, y = 1, z = 1 }
                        end
                    end
                    child:set_properties(restore_props)
                end
            end
        end
    end
end

--- Spawn and configure the corpse placeholder entity at the given position
---@param corpse_pos table The {x, y, z} coordinates where corpse should be placed
---@param visuals table The player visual appearance table (mesh, textures, visual_size, yaw)
---@param player ObjectRef|nil Optional player reference for transferring attached arrows
---@param death_info table|nil Optional death analysis table
---@param last_blow table|nil Optional lethal blow data


--- Check if 3d_armor is configured to drop or destroy armor on player death
---@param player ObjectRef|nil Optional player reference
---@return boolean drops True if armor is ejected/dropped from inventory on death
function deathstats.is_armor_dropped(_player)
    local armor_mod = rawget(_G, "armor")
    if not armor_mod then
        return false
    end
    if armor_mod.config and type(armor_mod.config) == "table" then
        if armor_mod.config.drop ~= nil or armor_mod.config.destroy ~= nil then
            return (armor_mod.config.drop == true) or (armor_mod.config.destroy == true)
        end
    end
    local drop_set = core.settings:get_bool("armor_drop")
    local dest_set = core.settings:get_bool("armor_destroy")
    if drop_set ~= nil or dest_set ~= nil then
        return (drop_set == true) or (dest_set == true)
    end
    return false
end

--- Check if player inventory/items are dropped or lost on death
--- If false, the player keeps items in inventory, so corpse should display wielded item
---@param player ObjectRef|nil Optional player reference
---@return boolean dropped True if items are dropped on death, false if kept
function deathstats.is_inventory_dropped(player)
    -- Creative mode: players do not lose inventory
    if player and player:is_player() then
        local name = player:get_player_name()
        if name and core.is_creative_enabled(name) then
            return false
        end
    end

    -- Engine & Game Settings: keep_inventory flags
    local setting_keys = {
        "keep_inventory",
        "keepinventory",
        "mcl_keepInventory",
        "gamerule:keepInventory",
    }
    for _, key in ipairs(setting_keys) do
        if core.settings:get_bool(key) == true then
            return false
        end
    end

    -- Bones mod configuration (Luanti Game / default games)
    local _, bones_mode, has_bones_mod = deathstats.get_bones_mode()
    if has_bones_mod then
        if bones_mode == "keep" then
            return false
        elseif bones_mode == "drop" or bones_mode == "bones" then
            return true
        end
    else
        local mode_setting = core.settings:get("bones_mode")
        if mode_setting == "keep" then
            return false
        elseif mode_setting == "drop" then
            return true
        end
    end

    -- Mod-specific drop handlers
    if rawget(_G, "mcl_death_drop") ~= nil or rawget(_G, "rp_drop_items_on_die") ~= nil then
        return true
    end

    -- Default engine behavior (without bones or drop mods, inventory is kept)
    return false
end

--- Extract the player's active wielded item name, ignoring internal camera hands
---@param player ObjectRef The player object
---@return string item_name The item technical name (e.g. "default:sword_steel"), or "" if empty/hand
function deathstats.get_player_wield_item(player)
    if not player or not player:is_player() then
        return ""
    end

    -- Check player's direct wielded item
    local stack = player:get_wielded_item()
    local name = deathstats.get_stack_name(stack)
    if name ~= "" and name ~= "deathstats:camera_hand" then
        return name
    end

    -- Check inventory main list at wield index
    local inv = player:get_inventory()
    local wield_idx = player:get_wield_index() or 1
    if inv then
        local main_stack = inv:get_stack("main", wield_idx)
        local main_name = deathstats.get_stack_name(main_stack)
        if main_name ~= "" and main_name ~= "deathstats:camera_hand" then
            return main_name
        end
    end

    -- Check stashed main inventory from player metadata if available
    local meta = player:get_meta()
    if meta then
        local raw_main = meta:get_string("deathstats:stashed_main")
        if raw_main and raw_main ~= "" then
            local des_main = core.deserialize(raw_main)
            if type(des_main) == "table" then
                local idx = wield_idx or 1
                if des_main[idx] and des_main[idx] ~= "" and des_main[idx] ~= "deathstats:camera_hand" then
                    return deathstats.get_stack_name(des_main[idx])
                end
            end
        end
    end

    -- Check 3d_armor textures table if available
    local armor_mod = rawget(_G, "armor")
    if armor_mod and armor_mod.textures then
        local pname = player:get_player_name()
        local a_tex = pname and armor_mod.textures[pname]
        if a_tex and a_tex.wielditem and a_tex.wielditem ~= "" and a_tex.wielditem ~= "3d_armor_trans.png" and a_tex.wielditem ~= "blank.png" then
            local item_clean = a_tex.wielditem:gsub("%.png$", ""):gsub("_", ":", 1)
            if core.registered_items[a_tex.wielditem] then
                return a_tex.wielditem
            elseif core.registered_items[item_clean] then
                return item_clean
            else
                return a_tex.wielditem
            end
        end
    end

    return ""
end

--- Extract player visual characteristics (mesh, textures, visual_size, yaw) across all skin mods
---@param player ObjectRef The player object
---@return table visuals { mesh = string, textures = table, visual_size = table, yaw = number, armor_dropped = boolean }
function deathstats.get_player_visuals(player)
    if deathstats.compat_skins and deathstats.compat_skins.get_player_visuals then
        return deathstats.compat_skins.get_player_visuals(player)
    end
    if not player or not player:is_player() then
        return {
            mesh = "character.b3d",
            textures = { "character.png" },
            visual_size = { x = 1, y = 1, z = 1 },
            yaw = 0,
            armor_dropped = false,
            inventory_dropped = false,
            wield_item = "",
        }
    end
    local props = player:get_properties() or {}
    return {
        mesh = props.mesh or "character.b3d",
        textures = props.textures or { "character.png" },
        visual_size = props.visual_size or { x = 1, y = 1, z = 1 },
        yaw = (player.get_look_horizontal and player:get_look_horizontal()) or 0,
        armor_dropped = deathstats.is_armor_dropped(player),
        inventory_dropped = deathstats.is_inventory_dropped(player),
        wield_item = deathstats.get_player_wield_item(player),
    }
end


---@return ObjectRef|nil corpse The spawned corpse entity or nil if failed (e.g. mapblock not loaded)
function deathstats.spawn_and_setup_corpse(corpse_pos, visuals, player, death_info, last_blow)
    if not corpse_pos or not visuals then return nil end
    local corpse = core.add_entity(corpse_pos, "deathstats:corpse")
    if corpse then
        local ragdoll_enabled = (deathstats.config.enable_corpse_ragdoll ~= false)
        corpse:set_properties({
            mesh = visuals.mesh,
            textures = visuals.textures,
            visual_size = visuals.visual_size,
            selectionbox = { 0, 0, 0, 0, 0, 0 },
            pointable = false,
            physical = ragdoll_enabled,
            collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
            stepheight = 0.6,
        })
        if corpse.set_rotation then
            corpse:set_rotation({ x = 0, y = visuals.yaw or 0, z = 0 })
        elseif corpse.set_yaw then
            corpse:set_yaw(visuals.yaw or 0)
        end
        deathstats.pose_corpse(corpse, visuals.mesh)

        local luaent = corpse.get_luaentity and corpse:get_luaentity()
        if luaent then
            luaent._base_yaw = visuals.yaw or 0
            luaent._mesh = visuals.mesh
            local pname = player and player.get_player_name and player:get_player_name()
            luaent._player_name = pname
            if pname and deathstats.player_corpses and deathstats.player_corpses[pname] then
                if deathstats.player_corpses[pname] ~= corpse then
                    deathstats.dissolve_corpse(deathstats.player_corpses[pname])
                end
                deathstats.player_corpses[pname] = nil
            end
            luaent._death_info = death_info
            local pdata = player and deathstats.get_player_data(player)
            luaent._last_life = pdata and pdata.last_life
        end
        local is_moving = false
        local in_liquid = deathstats.is_in_liquid(corpse_pos, death_info)
        local in_liquid_nodes = deathstats.is_liquid_at(corpse_pos)
            or deathstats.is_liquid_at({ x = corpse_pos.x, y = corpse_pos.y + 0.5, z = corpse_pos.z })
            or deathstats.is_liquid_at({ x = corpse_pos.x, y = corpse_pos.y - 0.5, z = corpse_pos.z })

        if ragdoll_enabled then
            local vel, rot_speed = deathstats.calculate_corpse_impulse(player, death_info, last_blow)
            if in_liquid_nodes and (not vel or (vel.x == 0 and vel.y == 0 and vel.z == 0)) then
                vel = vector.new(0, 1.2, 0)
                rot_speed = vector.zero()
            end
            if vel and (vel.x ~= 0 or vel.y ~= 0 or vel.z ~= 0) then
                is_moving = true
                if corpse.set_velocity then corpse:set_velocity(vel) end
                if corpse.set_acceleration then
                    corpse:set_acceleration(in_liquid_nodes and { x = 0, y = 3.5, z = 0 } or { x = 0, y = -9.81, z = 0 })
                end
                local initial_roll = 0
                if deathstats.config.ragdoll_resting_poses ~= false then
                    local yaw = visuals.yaw or 0
                    local fwd_x = -math.sin(yaw)
                    local fwd_z = math.cos(yaw)
                    local vel_len = math.sqrt(vel.x * vel.x + vel.z * vel.z)
                    if vel_len > 0.1 then
                        local dot_fwd = (vel.x * fwd_x + vel.z * fwd_z) / vel_len
                        if dot_fwd > 0.35 then
                            -- Knocked forward (struck from behind): topple forward onto chest/face
                            initial_roll = math.pi
                        elseif dot_fwd < -0.35 then
                            -- Knocked backward (struck from front): fall backward onto back
                            initial_roll = 0
                        else
                            -- Knocked sideways: topple onto side
                            initial_roll = (math.random() < 0.5) and (math.pi / 2) or (-math.pi / 2)
                        end
                    end
                end

                if luaent then
                    luaent._velocity = vel
                    luaent._rot_speed = rot_speed
                    luaent._rot = { x = 0, y = visuals.yaw or 0, z = initial_roll }
                    luaent._base_yaw = visuals.yaw or 0
                    luaent._tumbling = (deathstats.config.ragdoll_tumbling ~= false) and (rot_speed.x ~= 0 or rot_speed.z ~= 0)
                    luaent._impact_damage = (last_blow and last_blow.damage) or 5
                    luaent._death_info = death_info
                    luaent._settled = false
                    luaent._timer = 0
                    luaent._air_timer = 0
                    luaent._slide_timer = 0
                end
                deathstats.update_ragdoll_flight_limbs(corpse, vel, visuals.yaw or 0)
            end
        end

        local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
            and (deathstats.config.enable_fall_fractures ~= false)

        if not is_moving then
            local roll = 0
            local pose_type = "supine"
            local is_wall = deathstats.detect_wall_behind(corpse_pos, visuals.yaw or 0)
            if deathstats.config.ragdoll_resting_poses ~= false then
                if is_wall then
                    local w_pick = math.random()
                    if w_pick < 0.55 then
                        pose_type = "wall_sit"
                        roll = 0
                    elseif w_pick < 0.85 then
                        pose_type = "slouch"
                        roll = math.rad(random_float(-8, 8))
                    else
                        pose_type = "supine"
                        roll = 0
                    end
                else
                    local pick = math.random()
                    if pick < 0.30 then
                        pose_type = "prone"
                        roll = math.pi
                    elseif pick < 0.60 then
                        pose_type = "lateral"
                        roll = (math.random() < 0.5) and (math.pi / 2) or (-math.pi / 2)
                    else
                        pose_type = "supine"
                        roll = 0
                    end
                end
            end

            if pose_type == "wall_sit" or pose_type == "slouch" then
                deathstats.pose_corpse(corpse, visuals.mesh, "sit")
            end

            local pitch = (pose_type == "slouch") and math.rad(-8) or 0
            if not in_liquid then
                local is_wall_sitting = (pose_type == "wall_sit" or pose_type == "slouch")
                corpse_pos = deathstats.ensure_corpse_clearance(corpse_pos, visuals.yaw or 0, is_wall_sitting)
                local pose_offset = deathstats.get_pose_elevation_offset(pose_type)
                if deathstats.config.enable_slope_pitch ~= false and pose_type ~= "wall_sit" and pose_type ~= "slouch" then
                    local detected_pitch, target_y, ground_found = deathstats.detect_corpse_slope_pitch(corpse_pos, visuals.yaw or 0)
                    pitch = detected_pitch or 0
                    if (ground_found or ground_found == nil) and target_y and math.abs(target_y - corpse_pos.y) <= 1.2 then
                        target_y = target_y + pose_offset
                        if corpse.set_pos then
                            corpse:set_pos(vector.new(corpse_pos.x, target_y, corpse_pos.z))
                        end
                    elseif pose_offset > 0 and corpse.set_pos then
                        corpse:set_pos(vector.new(corpse_pos.x, corpse_pos.y + pose_offset, corpse_pos.z))
                    elseif corpse.set_pos then
                        corpse:set_pos(corpse_pos)
                    end
                elseif pose_offset > 0 and corpse.set_pos then
                    corpse:set_pos(vector.new(corpse_pos.x, corpse_pos.y + pose_offset, corpse_pos.z))
                elseif corpse.set_pos then
                    corpse:set_pos(corpse_pos)
                end
            end
            if corpse.set_rotation then
                corpse:set_rotation({ x = pitch, y = visuals.yaw or 0, z = roll })
            end
            if luaent then
                luaent._settled = true
                luaent._rot = { x = pitch, y = visuals.yaw or 0, z = roll }
                luaent._pose_type = pose_type
                local cur_p = (corpse.get_pos and corpse:get_pos()) or corpse_pos
                luaent._settled_pos = cur_p and vector.new(cur_p.x, cur_p.y, cur_p.z)
            end
            local cur_p = (corpse.get_pos and corpse:get_pos()) or corpse_pos
            local ambient_light = cur_p and deathstats.sample_corpse_ambient_light(cur_p, visuals.yaw or 0)
            local corpse_props = {
                physical = false,
                pointable = (deathstats.config.enable_corpse_inspect ~= false),
                selectionbox = deathstats.get_pose_selectionbox(pose_type),
                collisionbox = { -0.4, -0.15, -0.4, 0.4, 0.25, 0.4 },
                stepheight = 0.6,
            }
            if ambient_light and ambient_light > 0 then
                corpse_props.glow = ambient_light
            end
            if corpse.set_properties then
                corpse:set_properties(corpse_props)
            end
            deathstats.settle_ragdoll_limbs(corpse, (last_blow and last_blow.damage) or 5, pose_type, nil, roll)
        elseif fractures_enabled then
            deathstats.fracture_corpse_limbs(corpse)
        end

        -- Attach 3D wielditem entity to right hand if inventory items are retained on death
        if visuals.wield_item and visuals.wield_item ~= "" and not visuals.inventory_dropped then
            local wield_ent = core.add_entity(corpse_pos, "deathstats:corpse_wielditem")
            if wield_ent then
                wield_ent:set_properties({
                    textures = { visuals.wield_item },
                    wield_item = visuals.wield_item,
                    visual_size = { x = 0.25, y = 0.25, z = 0.25 },
                    pointable = false,
                })
                if wield_ent.set_attach then
                    -- Attach to lower palm of right hand (y=6.0 places item in palm, z=1.5 aligns with grip)
                    wield_ent:set_attach(corpse, "Arm_Right", { x = 0, y = 6.0, z = 1.5 }, { x = 90, y = 0, z = 90 }, true)
                end
                if luaent then
                    luaent._wielditem_entity = wield_ent
                end
            end
        end

        -- Transfer attached x_bows arrows from player to corpse if x_bows is loaded
        local xbows_loaded = rawget(_G, "XBows")
        if player and xbows_loaded and type(xbows_loaded.transfer_arrows_to_corpse) == "function" then
            xbows_loaded.transfer_arrows_to_corpse(player, corpse)
            deathstats.unhide_corpse_arrows(corpse)
        end
    end
    return corpse
end
