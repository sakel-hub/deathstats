--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local atan2 = math.atan2 or math.atan
local scratch_pos = { x = 0, y = 0, z = 0 }
local WALL_TEST_DISTS = { 0.55, 0.65 }
local WALL_TEST_YS = { 0.60, 0.80 }

-- ==========================================
-- Corpse Entity, Visuals & Camera Orbit
-- ==========================================

local safe_normalize = deathstats.safe_normalize

--- Calculate initial 3D linear launch velocity and angular tumbling impulse for a ragdoll corpse
---@param player ObjectRef|nil The deceased player
---@param death_info table|nil The death analysis table
---@param last_blow table|nil The recorded lethal blow data
---@return Vector velocity Initial 3D velocity vector for the corpse
---@return Vector rot_speed Initial angular tumbling velocity (pitch, yaw, roll)
function deathstats.calculate_corpse_impulse(player, death_info, last_blow)
    if deathstats.config.enable_corpse_ragdoll == false then
        return vector.zero(), vector.zero()
    end

    local pname = player and player.get_player_name and player:get_player_name()
    local last_punch = pname and deathstats.recent_punches[pname]
    local lb = last_blow or (pname and deathstats.last_blow[pname])

    -- Determine damage of the last blow
    local damage = (lb and lb.damage)
        or (last_punch and last_punch.damage)
        or (death_info and death_info.damage)
        or 5
    damage = math.max(1.0, tonumber(damage) or 1.0)

    -- Determine knockback direction vector
    local ppos = (player and player.get_pos and player:get_pos()) or (lb and lb.pos)
    local dir_h = nil

    local is_fall = death_info and (death_info.category == "fall" or death_info.type == "fall")
    local is_explosion = death_info and (death_info.category == "explode" or death_info.category == "explosion"
        or death_info.type == "explode" or death_info.type == "explosion"
        or (death_info.reason_text and death_info.reason_text:lower():find("explos"))
        or (lb and ((lb.blast_pos ~= nil) or (lb.reason and (lb.reason.type == "explosion" or lb.reason.type == "explode" or (lb.reason.node and lb.reason.node:find("tnt")))))))

    -- True 3D Explosion Blast Vector (Epicenter -> Player)
    if is_explosion then
        local blast_pos = (death_info and (death_info.blast_pos or death_info.explosion_pos or death_info.pos_origin))
            or (lb and (lb.blast_pos or (lb.reason and (lb.reason.pos or lb.reason.origin))))
        if not blast_pos and ppos and deathstats.recent_explosions then
            local now = core.get_gametime()
            local best_d = 20.0
            for _, exp in ipairs(deathstats.recent_explosions) do
                if (now - exp.time) <= 4.0 then
                    local d = vector.distance(exp.pos, ppos)
                    if d < best_d then
                        best_d = d
                        blast_pos = exp.pos
                    end
                end
            end
        end
        if blast_pos and ppos then
            local d = vector.direction(blast_pos, ppos)
            if d.x ~= 0 or d.z ~= 0 then
                dir_h = safe_normalize({ x = d.x, y = 0, z = d.z })
            end
        end
    end

    -- Live player velocity at death time (captures engine knockback vectors)
    if not dir_h and player and player.get_velocity then
        local pvel = player:get_velocity()
        if pvel and (pvel.x ~= 0 or pvel.z ~= 0) then
            local v_mag = math.sqrt(pvel.x * pvel.x + pvel.z * pvel.z)
            if v_mag > 0.3 then
                dir_h = safe_normalize({ x = pvel.x, y = 0, z = pvel.z })
            end
        end
    end

    -- Recent punch direction
    if not dir_h and last_punch and last_punch.dir and (last_punch.dir.x ~= 0 or last_punch.dir.z ~= 0) then
        dir_h = safe_normalize({ x = last_punch.dir.x, y = 0, z = last_punch.dir.z })
    elseif not dir_h and last_punch and last_punch.hitter_pos and ppos then
        local d = vector.direction(last_punch.hitter_pos, ppos)
        if d.x ~= 0 or d.z ~= 0 then
            dir_h = safe_normalize({ x = d.x, y = 0, z = d.z })
        end
    end

    -- Lethal blow reason object (mob, projectile, player)
    if not dir_h and lb and lb.reason and lb.reason.object and ppos and lb.reason.object.get_pos then
        local opos = lb.reason.object:get_pos()
        if opos then
            local d = vector.direction(opos, ppos)
            if d.x ~= 0 or d.z ~= 0 then
                dir_h = safe_normalize({ x = d.x, y = 0, z = d.z })
            end
        end
    end

    -- Residual velocity
    if not dir_h and lb and lb.velocity then
        local vx, vz = lb.velocity.x or 0, lb.velocity.z or 0
        if math.abs(vx) > 0.5 or math.abs(vz) > 0.5 then
            dir_h = safe_normalize({ x = vx, y = 0, z = vz })
        end
    end

    -- Opposite of player look direction
    local ldir = player and player.get_look_dir and player:get_look_dir()
    if not ldir and player and player.get_look_horizontal then
        local yaw = player:get_look_horizontal() or 0
        local pitch = (player.get_look_vertical and player:get_look_vertical()) or 0
        local cos_p = math.cos(pitch)
        ldir = vector.new(-math.sin(yaw) * cos_p, math.sin(pitch), math.cos(yaw) * cos_p)
    end
    if not dir_h and ldir then
        if ldir.x ~= 0 or ldir.z ~= 0 then
            dir_h = safe_normalize({ x = -ldir.x, y = 0, z = -ldir.z })
        end
    end

    -- Fallback: Yaw direction
    if not dir_h then
        local yaw = (player and player.get_look_horizontal and player:get_look_horizontal()) or 0
        dir_h = vector.new(-math.sin(yaw), 0, -math.cos(yaw))
    end

    -- Determine forward/backward alignment of knockback relative to player facing
    local dot_fwd = (ldir and dir_h) and (ldir.x * dir_h.x + ldir.z * dir_h.z) or 0
    local pitch_sign = (dot_fwd > 0.2) and 1.0 or ((dot_fwd < -0.2) and -1.0 or 1.0)

    local rot_mt = {
        __lt = function(a, b)
            local av = (type(a) == "table" and (a.x or a[1])) or a
            local bv = (type(b) == "table" and (b.x or b[1])) or b
            return av < bv
        end,
        __gt = function(a, b)
            local av = (type(a) == "table" and (a.x or a[1])) or a
            local bv = (type(b) == "table" and (b.x or b[1])) or b
            return av > bv
        end,
    }

    -- Calculate Force & Velocity based on Damage of last blow
    local mult = deathstats.config.ragdoll_force_multiplier or 1.0
    local max_vel = deathstats.config.ragdoll_max_velocity or 18.0

    local is_passive = not last_punch and not (lb and lb.reason and lb.reason.object) and death_info and
        (death_info.category == "drown" or death_info.category == "starve" or death_info.category == "hunger"
         or death_info.category == "suffocation" or death_info.category == "suffocate" or death_info.category == "poison")

    if is_passive then
        -- Passive deaths (drowning, suffocation, hunger, poison):
        -- Corpse gently collapses in place with zero knockback impulse
        return vector.zero(), setmetatable(vector.zero(), rot_mt), 0, 0, 0
    end

    if is_explosion then
        -- Explosion: high radial blast velocity and chaotic 3D spin
        local exp_speed = math.min(max_vel, (3.5 + damage * 0.65) * mult)
        exp_speed = math.max(exp_speed, 2.0)
        local exp_lift = math.min(8.0, (2.5 + damage * 0.3) * mult)
        exp_lift = math.max(exp_lift, 2.0)
        local exp_vel = vector.new(dir_h.x * exp_speed, exp_lift, dir_h.z * exp_speed)
        local rot_speed = vector.zero()
        if deathstats.config.ragdoll_tumbling ~= false then
            local exp_pitch_sign = (dot_fwd > 0.1) and -1.0 or ((dot_fwd < -0.1) and 1.0 or -1.0)
            local t_pitch = exp_speed * 1.1 * exp_pitch_sign
            local t_roll = (math.random() - 0.5) * exp_speed * 1.3
            local t_yaw = (math.random() - 0.5) * exp_speed * 0.8
            rot_speed = vector.new(t_pitch, t_yaw, t_roll)
        end
        return exp_vel, setmetatable(rot_speed, rot_mt), rot_speed.x, rot_speed.y, rot_speed.z
    end

    local base_speed = is_fall and 0.8 or 1.5
    local dmg_scale = is_fall and 0.15 or 0.45

    local speed_h = (base_speed + damage * dmg_scale) * mult
    speed_h = math.min(speed_h, max_vel)
    speed_h = math.max(speed_h, 1.0)

    local lift_base = is_fall and 1.5 or 1.2
    local lift_scale = is_fall and 0.08 or 0.22
    local lift_max = is_fall and 4.0 or 8.0
    local vel_y = (lift_base + damage * lift_scale) * mult
    vel_y = math.min(vel_y, lift_max)
    vel_y = math.max(vel_y, 1.0)

    local initial_velocity = vector.new(dir_h.x * speed_h, vel_y, dir_h.z * speed_h)

    -- Initial angular tumbling velocity
    local rot_speed = vector.zero()
    if deathstats.config.ragdoll_tumbling ~= false then
        local tumble_pitch = speed_h * 0.7 * pitch_sign
        local tumble_roll = (math.random() - 0.5) * (2.5 + speed_h * 1.2)
        rot_speed = vector.new(tumble_pitch, 0, tumble_roll)
    end

    return initial_velocity, setmetatable(rot_speed, rot_mt), rot_speed.x, rot_speed.y, rot_speed.z
end

local random_float = deathstats.random_float

--- Apply immediate physical impact reaction to corpse limbs when colliding with ground during bounce
---@param corpse ObjectRef The corpse entity object
---@param impact_vy number Downward velocity of the impact
---@param _rebound_v Vector Resulting rebound velocity vector
---@param _rot table|nil Current rotation {x, y, z}
---@param bounce_count number Current bounce index (1 or 2)
function deathstats.apply_corpse_bounce_impact(corpse, impact_vy, _rebound_v, _rot, bounce_count)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local vy = math.abs(tonumber(impact_vy) or 4.0)
    local shock = math.min(1.6, math.max(0.35, vy / 5.5))
    local bounce_damp = (bounce_count and bounce_count > 1) and 0.65 or 1.0
    local eff_shock = shock * bounce_damp

    -- Inertial shock: sudden deceleration whips limbs and snaps head
    local head_pitch = math.rad(-25) * eff_shock
    local head_yaw = ((math.random() < 0.5) and -1 or 1) * math.rad(random_float(15, 30)) * eff_shock
    local arm_pitch = math.rad(random_float(20, 45)) * eff_shock
    local arm_splay = math.rad(random_float(30, 60)) * eff_shock
    local leg_pitch = math.rad(random_float(-12, 18)) * eff_shock
    local leg_splay = math.rad(random_float(20, 45)) * eff_shock

    deathstats.rotate_corpse_bone(corpse, "Head", vector.new(head_pitch, head_yaw, 0))
    deathstats.rotate_corpse_bone(corpse, "Arm_Left", vector.new(arm_pitch, math.rad(10) * eff_shock, -arm_splay))
    deathstats.rotate_corpse_bone(corpse, "Arm_Right", vector.new(arm_pitch, math.rad(-10) * eff_shock, arm_splay))
    deathstats.rotate_corpse_bone(corpse, "Leg_Left", vector.new(leg_pitch, 0, -leg_splay))
    deathstats.rotate_corpse_bone(corpse, "Leg_Right", vector.new(leg_pitch, 0, leg_splay))
end

--- Apply final limp resting fractures or organic pose angles to corpse limbs on landing
---@param corpse ObjectRef The corpse entity object
---@param impact_damage number|nil Damage of the lethal impact
---@param pose_type string|nil Optional resting pose ("supine", "prone", "lateral")
---@param hanging_legs boolean|nil True if legs hang over a ledge/drop
---@param roll_rad number|nil Optional corpse roll angle in radians
function deathstats.settle_ragdoll_limbs(corpse, impact_damage, pose_type, hanging_legs, roll_rad)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local dmg = tonumber(impact_damage) or 5
    local scale = math.min(1.35, 1.0 + math.max(0, dmg - 10) * 0.015)
    local ptype = pose_type or "supine"

    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    local roll_z = roll_rad or (luaent and luaent._rot and luaent._rot.z)
        or (corpse.get_rotation and corpse:get_rotation().z) or 0
    local is_right_side = (roll_z < -0.1)

    local custom = {}
    if ptype == "prone" then
        -- Prone: Face down on stomach with organic archetypes (collapsed, reach, sprawl)
        -- Limp neck turned sideways (cheek rest) with slight upward tilt so head rests naturally flush with ground
        local arch = math.random(1, 3)
        local head_sign = (math.random() < 0.5) and -1 or 1
        if arch == 1 then
            -- Collapsed: arms drawn up near shoulders, legs straight
            custom["Head"] = vector.new(math.rad(-14), 0, math.rad(head_sign * random_float(45, 70)))
            custom["Arm_Left"] = math.rad(random_float(-55, -35) * scale)
            custom["Arm_Right"] = math.rad(random_float(35, 55) * scale)
            custom["Leg_Left"] = math.rad(random_float(-14, -6) * scale)
            custom["Leg_Right"] = math.rad(random_float(6, 14) * scale)
        elseif arch == 2 then
            -- Asymmetric reach: one arm forward, one trailing back
            local reach_left = (math.random() < 0.5)
            custom["Head"] = vector.new(math.rad(-14), 0, math.rad(head_sign * random_float(50, 75)))
            if reach_left then
                custom["Arm_Left"] = math.rad(random_float(-75, -50) * scale)
                custom["Arm_Right"] = math.rad(random_float(15, 35) * scale)
                custom["Leg_Left"] = math.rad(random_float(-12, -4) * scale)
                custom["Leg_Right"] = math.rad(random_float(15, 30) * scale)
            else
                custom["Arm_Left"] = math.rad(random_float(-35, -15) * scale)
                custom["Arm_Right"] = math.rad(random_float(50, 75) * scale)
                custom["Leg_Left"] = math.rad(random_float(-30, -15) * scale)
                custom["Leg_Right"] = math.rad(random_float(4, 12) * scale)
            end
        else
            -- Limp sprawl: relaxed random limbs
            custom["Head"] = vector.new(math.rad(-14), 0, math.rad(head_sign * random_float(45, 75)))
            custom["Arm_Left"] = math.rad(random_float(-65, -40) * scale)
            custom["Arm_Right"] = math.rad(random_float(40, 65) * scale)
            custom["Leg_Left"] = math.rad(random_float(-22, -10) * scale)
            custom["Leg_Right"] = math.rad(random_float(10, 22) * scale)
        end
    elseif ptype == "lateral" then
        -- Lateral: Lying on side with anatomically grounded resting archetypes (flank rest, limp parallel, gentle splay)
        -- Limbs rest flush against the torso and floor: top arm rests along the hip/flank (pitch ~0°, roll = 0°),
        -- bottom arm rests flat on the floor, and legs rest together (pitch 1° to 8°, separation < 8°).
        -- Local Z is strictly 0 to prevent pointing upward into the sky.
        local arch = math.random(1, 4)
        local head_pitch
        local l_leg_pitch, r_leg_pitch, l_arm_pitch, r_arm_pitch

        if arch == 1 then
            -- Flank rest: top arm lies flat along the hip/thigh, bottom arm under torso, legs gently curled together
            l_leg_pitch = random_float(2, 5) * scale
            r_leg_pitch = random_float(4, 7) * scale
            l_arm_pitch = random_float(-4, 2) * scale
            r_arm_pitch = random_float(-2, 2) * scale
            head_pitch = math.rad(random_float(-6, 6))
        elseif arch == 2 then
            -- Relaxed recovery: subtle leg bend resting together, arms along body
            l_leg_pitch = random_float(3, 6) * scale
            r_leg_pitch = random_float(5, 8) * scale
            l_arm_pitch = random_float(-3, 3) * scale
            r_arm_pitch = random_float(-1, 3) * scale
            head_pitch = math.rad(random_float(-8, 8))
        elseif arch == 3 then
            -- Limp parallel: legs almost straight with minimal separation (< 4°), arms parallel along flanks
            l_leg_pitch = random_float(1, 4) * scale
            r_leg_pitch = random_float(2, 5) * scale
            l_arm_pitch = random_float(-2, 2) * scale
            r_arm_pitch = random_float(-2, 2) * scale
            head_pitch = math.rad(random_float(-5, 5))
        else
            -- Gentle grounded splay: bottom leg slightly trailing, top leg slightly forward, both on ground
            l_leg_pitch = random_float(-3, 0) * scale
            r_leg_pitch = random_float(3, 6) * scale
            l_arm_pitch = random_float(-4, 3) * scale
            r_arm_pitch = random_float(-2, 2) * scale
            head_pitch = math.rad(random_float(-10, 10))
        end

        -- Top limb corresponds to Arm_Left / Leg_Left if lying on right side,
        -- or Arm_Right / Leg_Right if lying on left side.
        if is_right_side then
            custom["Arm_Left"] = vector.new(math.rad(r_arm_pitch), 0, 0)
            custom["Arm_Right"] = vector.new(math.rad(l_arm_pitch), 0, 0)
            custom["Leg_Left"] = vector.new(math.rad(r_leg_pitch), 0, 0)
            custom["Leg_Right"] = vector.new(math.rad(l_leg_pitch), 0, 0)
            custom["Head"] = vector.new(-head_pitch, 0, 0)
        else
            custom["Arm_Left"] = vector.new(math.rad(l_arm_pitch), 0, 0)
            custom["Arm_Right"] = vector.new(math.rad(r_arm_pitch), 0, 0)
            custom["Leg_Left"] = vector.new(math.rad(l_leg_pitch), 0, 0)
            custom["Leg_Right"] = vector.new(math.rad(r_leg_pitch), 0, 0)
            custom["Head"] = vector.new(head_pitch, 0, 0)
        end
    elseif ptype == "wall_sit" or ptype == "slouch" then
        -- Wall sit / slouch: sitting upright against a wall with relaxed or slouched limbs
        local head_sign = (math.random() < 0.5) and -1 or 1
        local head_pitch = math.rad(random_float(12, 26))
        local head_yaw = math.rad(head_sign * random_float(4, 18))
        custom["Head"] = vector.new(head_pitch, head_yaw, 0)

        if ptype == "slouch" then
            -- Slouch: torso slightly tilted back or sideways, one arm fallen outward, legs loose
            local l_splay = (math.random() < 0.5)
            if l_splay then
                custom["Arm_Left"] = vector.new(math.rad(random_float(15, 35)), 0, math.rad(random_float(-25, -10)))
                custom["Arm_Right"] = vector.new(math.rad(random_float(5, 20)), 0, math.rad(random_float(5, 15)))
                custom["Leg_Left"] = math.rad(random_float(-22, -10) * scale)
                custom["Leg_Right"] = math.rad(random_float(4, 14) * scale)
            else
                custom["Arm_Left"] = vector.new(math.rad(random_float(5, 20)), 0, math.rad(random_float(-15, -5)))
                custom["Arm_Right"] = vector.new(math.rad(random_float(15, 35)), 0, math.rad(random_float(10, 25)))
                custom["Leg_Left"] = math.rad(random_float(-14, -4) * scale)
                custom["Leg_Right"] = math.rad(random_float(10, 22) * scale)
            end
        else
            -- Wall sit: balanced resting posture, arms resting downward toward lap
            custom["Arm_Left"] = vector.new(math.rad(random_float(8, 22)), 0, math.rad(random_float(-12, -4)))
            custom["Arm_Right"] = vector.new(math.rad(random_float(8, 22)), 0, math.rad(random_float(4, 12)))
            custom["Leg_Left"] = math.rad(random_float(-12, -2) * scale)
            custom["Leg_Right"] = math.rad(random_float(2, 12) * scale)
        end
    else
        -- Supine: Lying flat on back with organic archetypes (sprawl, relaxed, folded, impact)
        local arch = math.random(1, 4)
        local head_angle = random_float(-45, 45)
        if arch == 1 then
            -- Asymmetric sprawl
            local fling_left = (math.random() < 0.5)
            if fling_left then
                custom["Arm_Left"] = math.rad(random_float(-80, -50) * scale)
                custom["Arm_Right"] = math.rad(random_float(15, 35) * scale)
                custom["Leg_Left"] = math.rad(random_float(-45, -25) * scale)
                custom["Leg_Right"] = math.rad(random_float(8, 18) * scale)
            else
                custom["Arm_Left"] = math.rad(random_float(-35, -15) * scale)
                custom["Arm_Right"] = math.rad(random_float(50, 80) * scale)
                custom["Leg_Left"] = math.rad(random_float(-18, -8) * scale)
                custom["Leg_Right"] = math.rad(random_float(25, 45) * scale)
            end
            custom["Head"] = math.rad(head_angle)
        elseif arch == 2 then
            -- Relaxed rest
            custom["Arm_Left"] = math.rad(random_float(-35, -15) * scale)
            custom["Arm_Right"] = math.rad(random_float(15, 35) * scale)
            custom["Leg_Left"] = math.rad(random_float(-22, -10) * scale)
            custom["Leg_Right"] = math.rad(random_float(10, 22) * scale)
            custom["Head"] = math.rad(random_float(-25, 25))
        elseif arch == 3 then
            -- Peaceful folded
            custom["Arm_Left"] = math.rad(random_float(18, 40) * scale)
            custom["Arm_Right"] = math.rad(random_float(-40, -18) * scale)
            custom["Leg_Left"] = math.rad(random_float(-12, -4) * scale)
            custom["Leg_Right"] = math.rad(random_float(4, 12) * scale)
            custom["Head"] = math.rad(random_float(-15, 15))
        else
            -- Severe / impact sprawl with individual random jitter
            custom["Arm_Left"] = math.rad(random_float(-80, -55) * scale)
            custom["Arm_Right"] = math.rad(random_float(55, 80) * scale)
            custom["Leg_Left"] = math.rad(random_float(-45, -25) * scale)
            custom["Leg_Right"] = math.rad(random_float(25, 45) * scale)
            custom["Head"] = math.rad(head_angle * scale)
        end
    end

    -- Add organic per-joint micro-jitter so no two poses are identical
    for bone_name, val in pairs(custom) do
        local max_j = (ptype == "lateral") and 1.2 or 2.5
        local jitter = math.rad(random_float(-max_j, max_j))
        if type(val) == "table" then
            if ptype == "lateral" and (bone_name:find("Arm") or bone_name:find("Leg")) then
                -- In lateral pose, limbs bend along ground plane (local X), keeping local Z strictly 0
                custom[bone_name] = vector.new((val.x or 0) + jitter, val.y or 0, 0)
            else
                custom[bone_name] = vector.new(val.x or 0, val.y or 0, (val.z or 0) + jitter)
            end
        else
            custom[bone_name] = val + jitter
        end
    end

    -- If legs hang over a ledge/cliff, flex them downward toward the drop (except when sitting)
    if hanging_legs and ptype ~= "wall_sit" and ptype ~= "slouch" then
        if ptype == "lateral" then
            local hang_roll = is_right_side and math.rad(35) or math.rad(-35)
            local cur_l_x = (type(custom["Leg_Left"]) == "table" and custom["Leg_Left"].x) or 0
            local cur_r_x = (type(custom["Leg_Right"]) == "table" and custom["Leg_Right"].x) or 0
            custom["Leg_Left"] = vector.new(cur_l_x, 0, hang_roll)
            custom["Leg_Right"] = vector.new(cur_r_x, 0, hang_roll)
        else
            local hang_pitch = (ptype == "prone") and math.rad(45)
                or (ptype == "supine") and math.rad(-45)
                or math.rad(-30)
            local cur_left_z = (type(custom["Leg_Left"]) == "number" and custom["Leg_Left"])
                or (type(custom["Leg_Left"]) == "table" and custom["Leg_Left"].z) or math.rad(-25 * scale)
            local cur_right_z = (type(custom["Leg_Right"]) == "number" and custom["Leg_Right"])
                or (type(custom["Leg_Right"]) == "table" and custom["Leg_Right"].z) or math.rad(25 * scale)
            custom["Leg_Left"] = vector.new(hang_pitch, 0, cur_left_z)
            custom["Leg_Right"] = vector.new(hang_pitch, 0, cur_right_z)
        end
    end

    deathstats.fracture_corpse_limbs(corpse, custom)
end

--- Procedurally adjust corpse limb angles during flight with 3D aerodynamics, vertical drag & bounce shock
---@param corpse ObjectRef The corpse entity object
---@param velocity Vector Current velocity vector
---@param _base_yaw number Facing yaw of the corpse
---@param bounce_shock number|nil Optional active bounce shock impulse
function deathstats.update_ragdoll_flight_limbs(corpse, velocity, _base_yaw, bounce_shock)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local vx = (velocity and velocity.x) or 0
    local vy = (velocity and velocity.y) or 0
    local vz = (velocity and velocity.z) or 0
    local speed_h = math.sqrt(vx * vx + vz * vz)
    local speed_3d = math.sqrt(vx * vx + vy * vy + vz * vz)

    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    local t = (luaent and luaent._timer) or 0
    local shock = bounce_shock or (luaent and luaent._bounce_shock) or 0
    local shock_decay = math.min(1.2, math.max(0, shock))

    -- Prominent harmonic flutter from wind resistance (well above 0.05 dirty delta threshold)
    local flutter = math.sin(t * 14.0) * math.min(math.rad(18), speed_3d * math.rad(3.5))
    -- Multi-frame damped harmonic recoil ripples through limbs after hard impact
    local shock_osc = math.sin(t * 18.0) * shock_decay * math.rad(30.0)

    -- Dynamic 3D relative limb angles:
    -- Pitch (X-axis): air drag pushes limbs opposite vertical flight (vy > 0 pushes down, vy < 0 drags up)
    -- Yaw (Y-axis): limp sideways splay / oscillation
    -- Roll (Z-axis): planar splay outward along floor plane
    local arm_pitch = math.min(math.rad(55), math.max(math.rad(-35), -vy * 0.05)) + flutter + shock_osc * 0.5
    local arm_roll = math.min(math.rad(70), math.rad(20 + speed_h * 4.0 + shock_decay * 30.0))
    local leg_pitch = math.min(math.rad(40), math.max(math.rad(-25), -vy * 0.035)) - flutter * 0.5 + shock_osc * 0.3
    local leg_roll = arm_roll * 0.5 + shock_decay * math.rad(15)

    -- Arm_Left: roll negative (splay left), pitch drag
    deathstats.rotate_corpse_bone(corpse, "Arm_Left", vector.new(arm_pitch, flutter * 0.5, -arm_roll))
    -- Arm_Right: roll positive (splay right), pitch drag
    deathstats.rotate_corpse_bone(corpse, "Arm_Right", vector.new(arm_pitch, -flutter * 0.5, arm_roll))
    -- Leg_Left: roll negative (splay left)
    deathstats.rotate_corpse_bone(corpse, "Leg_Left", vector.new(leg_pitch, 0, -leg_roll))
    -- Leg_Right: roll positive (splay right)
    deathstats.rotate_corpse_bone(corpse, "Leg_Right", vector.new(leg_pitch, 0, leg_roll))
    -- Head: loose floppy neck with whiplash recoil
    local head_pitch = math.rad(-15) - math.min(math.rad(25), math.max(0, -vy * 0.03)) + flutter * 0.5 - shock_osc * 0.7
    local head_yaw = math.sin(t * 8.0) * math.min(math.rad(18), speed_h * 0.025) + (math.sin(t * 15.0) * shock_decay * math.rad(20))
    deathstats.rotate_corpse_bone(corpse, "Head", vector.new(head_pitch, head_yaw, 0))
end

--- Procedurally adjust corpse limbs while sliding along ground or tumbling down stairs/hills
--- Simulates ground surface friction drag, stair step bumps, and reactive limp jostling
---@param corpse ObjectRef The corpse entity object
---@param velocity Vector Current velocity vector
---@param _base_yaw number Facing yaw of the corpse
---@param bounce_shock number|nil Active bounce shock impulse
---@param slide_timer number|nil Accumulated sliding duration in seconds
function deathstats.update_ragdoll_slide_limbs(corpse, velocity, _base_yaw, bounce_shock, slide_timer)
    if not corpse or (corpse.is_valid and not corpse:is_valid()) then return end
    local fractures_enabled = (deathstats.config.enable_limb_fractures ~= false)
        and (deathstats.config.enable_fall_fractures ~= false)
    if not fractures_enabled then return end

    local vx = (velocity and velocity.x) or 0
    local vz = (velocity and velocity.z) or 0
    local speed_h = math.sqrt(vx * vx + vz * vz)
    local t = slide_timer or 0

    local luaent = corpse.get_luaentity and corpse:get_luaentity()
    local shock = bounce_shock or (luaent and luaent._bounce_shock) or 0
    local shock_decay = math.min(1.2, math.max(0, shock))

    -- Stair step & rough terrain micro-jostle (frequency increases with speed, 12 to 18 rad/s)
    local bump_freq = 12.0 + math.min(6.0, speed_h * 1.5)
    local arm_bump = math.sin(t * bump_freq) * math.min(math.rad(22), speed_h * math.rad(4.5))
    local leg_bump_l = math.sin(t * (bump_freq * 0.9)) * math.min(math.rad(18), speed_h * math.rad(3.5))
    local leg_bump_r = math.cos(t * (bump_freq * 0.9)) * math.min(math.rad(18), speed_h * math.rad(3.5))

    -- Damped bounce recoil oscillation ripples through limbs after hard surface hits
    local shock_osc = math.sin(t * 18.0) * shock_decay * math.rad(28.0)

    -- Dynamic surface drag: arms trailing backward along ground, splaying outward
    local arm_pitch = math.min(math.rad(45), math.max(math.rad(-20), math.rad(10) + arm_bump + shock_decay * math.rad(15)))
    local arm_roll = math.min(math.rad(65), math.rad(25 + speed_h * 4.5 + shock_decay * 25.0))

    -- Legs splay along ground plane: keep local X/Y pitch strictly 0 for planar ground alignment,
    -- varying Z-roll (lateral splay) with alternating step/stair jostle
    local leg_roll_base = math.rad(15 + speed_h * 2.5 + shock_decay * 15.0)
    local leg_roll_l = math.min(math.rad(45), math.max(math.rad(8), leg_roll_base + leg_bump_l))
    local leg_roll_r = math.min(math.rad(45), math.max(math.rad(8), leg_roll_base + leg_bump_r))

    -- Apply bone rotations:
    deathstats.rotate_corpse_bone(corpse, "Arm_Left", vector.new(arm_pitch, math.rad(8), -arm_roll))
    deathstats.rotate_corpse_bone(corpse, "Arm_Right", vector.new(arm_pitch, -math.rad(8), arm_roll))
    deathstats.rotate_corpse_bone(corpse, "Leg_Left", vector.new(0, 0, -leg_roll_l))
    deathstats.rotate_corpse_bone(corpse, "Leg_Right", vector.new(0, 0, leg_roll_r))

    -- Head: flopping from terrain bumps and bounce recoil
    local head_flop = math.sin(t * 10.0) * math.min(math.rad(20), speed_h * math.rad(3.0)) + shock_osc
    local head_pitch = math.rad(-12) + math.sin(t * bump_freq) * math.rad(8) - shock_decay * math.rad(15)
    deathstats.rotate_corpse_bone(corpse, "Head", vector.new(head_pitch, head_flop, 0))
end


--- Probe surface ground elevation at a specific horizontal coordinate
--- Uses raycast if available, falling back to discrete vertical node scan
---@param probe_x number X position to probe
---@param probe_z number Z position to probe
---@param start_y number Reference Y position
---@return number|nil elevation Ground contact Y elevation or nil if air/void
function deathstats.probe_ground_elevation(probe_x, probe_z, start_y)
    start_y = start_y or 0
    if core.raycast then
        local r_start = vector.new(probe_x, start_y + 0.8, probe_z)
        local r_end = vector.new(probe_x, start_y - 4.5, probe_z)
        local ray = core.raycast(r_start, r_end, false, false)
        for pt in ray do
            if pt.type == "node" and pt.under then
                local node = core.get_node_or_nil(pt.under)
                local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
                if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                    return (pt.intersection_point and pt.intersection_point.y) or (pt.under.y + 0.5)
                end
            end
        end
    end

    -- Discrete node scan fallback (checks down to 4 nodes below start_y)
    local check_x = math.floor(probe_x + 0.5)
    local check_z = math.floor(probe_z + 0.5)
    scratch_pos.x = check_x
    scratch_pos.z = check_z
    for dy = 1, -4, -1 do
        local ny = math.floor(start_y + dy + 0.5)
        scratch_pos.y = ny
        local node = core.get_node_or_nil(scratch_pos)
        local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
        if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
            return ny + 0.5
        end
    end
    return nil
end

--- Detect terrain slope incline along the corpse spine axis using two downward raycasts (head and pelvis)
--- Returns the pitch angle in radians (matching right-handed Z-X-Y set_rotation) and adjusted contact elevation
---@param pos Vector Center position of the corpse
---@param yaw number Orientation yaw in radians
---@return number pitch Pitch angle in radians (clamped to [-55°, +55°])
---@return number target_y Adjusted ground midpoint elevation for the corpse
---@return boolean ground_found True if valid walkable ground was probed under corpse
function deathstats.detect_corpse_slope_pitch(pos, yaw)
    if not pos then return 0, 0, false end
    yaw = yaw or 0

    -- Floating in liquid: corpses remain level
    if deathstats.is_in_liquid(pos) then
        return 0, pos.y, false
    end

    -- In character.b3d lay animation (frames 162-166), body lies backward along spine axis:
    -- Forward is -sin(yaw), cos(yaw). Head extends backward (+sin(yaw), -cos(yaw)), pelvis extends forward.
    local fwd_x = -math.sin(yaw)
    local fwd_z = math.cos(yaw)

    local spine_half_span = 0.55
    local head_x = pos.x - fwd_x * spine_half_span
    local head_z = pos.z - fwd_z * spine_half_span
    local pelvis_x = pos.x + fwd_x * spine_half_span
    local pelvis_z = pos.z + fwd_z * spine_half_span

    local y_head = deathstats.probe_ground_elevation(head_x, head_z, pos.y)
    local y_pelvis = deathstats.probe_ground_elevation(pelvis_x, pelvis_z, pos.y)

    if y_head and y_pelvis then
        local delta_y = y_head - y_pelvis
        local dist_h = spine_half_span * 2.0 -- 1.1 node baseline

        -- In Luanti Z-X-Y set_rotation:
        -- Positive pitch around local X tilts the vector at -Z (head) downward.
        -- When delta_y > 0 (head is uphill / higher), negative pitch elevates the head.
        local raw_pitch = -atan2(delta_y, dist_h)

        -- Clamp to natural anatomical slope limits (+/- 55 degrees) to avoid vertical glitches on cliffs
        local max_pitch = math.rad(55)
        local pitch = math.max(-max_pitch, math.min(max_pitch, raw_pitch))

        -- Ground contact: anchor directly to body elevation (torso resting flat on ground)
        -- with a minimal 0.02 block epsilon to prevent coplanar polygon z-fighting
        local y_body = deathstats.probe_ground_elevation(pos.x, pos.z, pos.y)
        local contact_y = y_body or ((y_head + y_pelvis) * 0.5)
        local target_y = contact_y + 0.02
        return pitch, target_y, true
    end

    return 0, pos.y, false
end

--- Probe 3D terrain elevation surrounding the corpse to determine the true downhill slope gradient
--- Works across stairs, inclines, and irregular cliffs regardless of corpse orientation.
---@param pos Vector Center position of the corpse
---@param base_yaw number|nil Facing yaw in radians
---@param pitch_slope number|nil Pre-calculated slope pitch along the spine axis
---@return number down_x Downhill direction unit vector X (0 if flat)
---@return number down_z Downhill direction unit vector Z (0 if flat)
---@return number slope_angle Slope steepness angle in radians
function deathstats.get_terrain_downhill_dir(pos, base_yaw, pitch_slope)
    if not pos then return 0, 0, 0 end
    if deathstats.is_in_liquid(pos) then return 0, 0, 0 end

    base_yaw = base_yaw or 0
    pitch_slope = pitch_slope or 0

    -- Probe 4 surrounding cardinal points at offset D = 0.7
    local d = 0.7
    local y_east = deathstats.probe_ground_elevation(pos.x + d, pos.z, pos.y)
    local y_west = deathstats.probe_ground_elevation(pos.x - d, pos.z, pos.y)
    local y_north = deathstats.probe_ground_elevation(pos.x, pos.z + d, pos.y)
    local y_south = deathstats.probe_ground_elevation(pos.x, pos.z - d, pos.y)
    local y_center = deathstats.probe_ground_elevation(pos.x, pos.z, pos.y)

    local grad_x = 0
    if y_east and y_west then
        grad_x = (y_east - y_west) / (2 * d)
    elseif y_east and y_center then
        grad_x = (y_east - y_center) / d
    elseif y_west and y_center then
        grad_x = (y_center - y_west) / d
    end

    local grad_z = 0
    if y_north and y_south then
        grad_z = (y_north - y_south) / (2 * d)
    elseif y_north and y_center then
        grad_z = (y_north - y_center) / d
    elseif y_south and y_center then
        grad_z = (y_center - y_south) / d
    end

    -- Downhill gradient is opposite to ascent: -grad
    local down_x = -grad_x
    local down_z = -grad_z
    local slope_mag = math.sqrt(down_x * down_x + down_z * down_z)

    local slope_angle
    if slope_mag > 0.15 then
        down_x = down_x / slope_mag
        down_z = down_z / slope_mag
        slope_angle = math.atan(slope_mag)
    else
        down_x = 0
        down_z = 0
        slope_angle = 0
    end

    -- If spine pitch indicates a pronounced incline along the corpse spine,
    -- factor in or fallback to the spine slope direction.
    -- Pelvis is forward (+fwd), head is backward (-fwd).
    -- When pitch_slope < 0 (head higher than pelvis), downhill is towards pelvis (+fwd).
    -- When pitch_slope > 0 (pelvis higher than head), downhill is towards head (-fwd).
    local abs_spine = math.abs(pitch_slope)
    if abs_spine > 0.2 then
        local fwd_x = -math.sin(base_yaw)
        local fwd_z = math.cos(base_yaw)
        local spine_sign = (pitch_slope < 0) and 1 or -1
        local spine_down_x = fwd_x * spine_sign
        local spine_down_z = fwd_z * spine_sign

        if slope_mag <= 0.15 then
            down_x = spine_down_x
            down_z = spine_down_z
            slope_angle = abs_spine
        else
            slope_angle = math.max(slope_angle, abs_spine)
        end
    end

    return down_x, down_z, slope_angle
end

--- Detect if the corpse legs are hanging over an edge, cliff, or stair drop
---@param pos Vector Center position of the corpse
---@param yaw number Facing yaw of the corpse
---@return boolean hanging True if pelvis is supported but legs extend over empty space
function deathstats.detect_hanging_legs(pos, yaw)
    if not pos then return false end
    yaw = yaw or 0
    if deathstats.is_in_liquid(pos) then return false end

    local fwd_x = -math.sin(yaw)
    local fwd_z = math.cos(yaw)

    local pelvis_x = pos.x + fwd_x * 0.50
    local pelvis_z = pos.z + fwd_z * 0.50
    local feet_x = pos.x + fwd_x * 1.50
    local feet_z = pos.z + fwd_z * 1.50

    local function probe_elevation(px, pz)
        local cx = math.floor(px + 0.5)
        local cz = math.floor(pz + 0.5)
        scratch_pos.x = cx
        scratch_pos.z = cz
        for dy = 0, -2, -1 do
            local ny = math.floor(pos.y + dy - 0.2)
            scratch_pos.y = ny
            local node = core.get_node_or_nil(scratch_pos)
            local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
            if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                return ny
            end
        end
        return nil
    end

    local y_pelvis = probe_elevation(pelvis_x, pelvis_z)
    if not y_pelvis then return false end

    local y_feet = probe_elevation(feet_x, feet_z)
    return (not y_feet) or (y_pelvis - y_feet >= 1)
end

--- Detect if there is a solid walkable wall or obstruction behind the corpse
---@param pos Vector Position of the corpse
---@param yaw number Facing yaw of the corpse in radians
---@return boolean is_wall True if a solid node is detected behind
function deathstats.detect_wall_behind(pos, yaw)
    if not pos or not yaw then return false end
    -- Behind vector: in Luanti forward is (-sin(yaw), 0, cos(yaw)), so behind is (sin(yaw), 0, -cos(yaw))
    local b_x = math.sin(yaw)
    local b_z = -math.cos(yaw)

    -- Ensure space at corpse torso itself is not inside a solid block
    scratch_pos.x = pos.x
    scratch_pos.y = pos.y + 0.75
    scratch_pos.z = pos.z
    local torso_self = core.get_node_or_nil(scratch_pos)
    if torso_self and torso_self.name ~= "air" and torso_self.name ~= "ignore" then
        local ndef_self = core.registered_nodes[torso_self.name]
        if ndef_self and ndef_self.walkable then
            return false
        end
    end

    -- Probe behind at torso and shoulder height (y + 0.60 to y + 0.80) so ground blocks
    -- and overhead arches/ceilings are never confused with walls behind the back.
    for i = 1, #WALL_TEST_DISTS do
        local dist = WALL_TEST_DISTS[i]
        local px = pos.x + b_x * dist
        local pz = pos.z + b_z * dist
        for j = 1, #WALL_TEST_YS do
            local dy = WALL_TEST_YS[j]
            scratch_pos.x = px
            scratch_pos.y = pos.y + dy
            scratch_pos.z = pz
            local node = core.get_node_or_nil(scratch_pos)
            if node and node.name ~= "air" and node.name ~= "ignore" then
                local ndef = core.registered_nodes[node.name]
                if ndef and (ndef.walkable ~= false) and (not ndef.liquidtype or ndef.liquidtype == "none") then
                    return true
                end
            end
        end
    end
    return false
end

--- Return the vertical position offset required to keep different resting poses
--- (supine, prone, lateral, wall_sit, slouch) resting flat on top of the ground.
--- In character.b3d lay animation (frame 166), the entity origin (0,0,0) is stationed
--- along the back plane (Y min = -0.108, Y max = +0.427).
--- Rotating into prone (roll = pi) inverts Y to [-0.427, +0.108], plunging the chest/face
--- 0.32 blocks into the ground if not offset.
--- Lateral (roll = +/- pi/2) places the shoulder at -0.27, needing a +0.16 block offset.
--- Wall sit and slouch maintain upright origin contact (0.0).
---@param pose_type string|nil "supine", "prone", "lateral", "wall_sit", or "slouch"
---@return number offset Vertical offset in nodes
function deathstats.get_pose_elevation_offset(pose_type)
    if pose_type == "prone" then
        return 0.32
    elseif pose_type == "lateral" then
        return 0.16
    end
    return 0.0
end

--- Return the interaction selectionbox bounding box for a given resting pose
--- to match the physical mesh contact bounds in world space.
---@param pose_type string|nil "supine", "prone", "lateral", "wall_sit", or "slouch"
---@return number[] selectionbox Bounding box table { minx, miny, minz, maxx, maxy, maxz }
function deathstats.get_pose_selectionbox(pose_type)
    if pose_type == "prone" then
        return { -0.5, -0.45, -0.5, 0.5, 0.15, 0.5 }
    elseif pose_type == "lateral" then
        return { -0.5, -0.30, -0.5, 0.5, 0.30, 0.5 }
    elseif pose_type == "wall_sit" then
        return { -0.4, -0.10, -0.4, 0.4, 0.95, 0.4 }
    elseif pose_type == "slouch" then
        return { -0.4, -0.15, -0.4, 0.4, 0.85, 0.4 }
    end
    return { -0.5, -0.20, -0.5, 0.5, 0.35, 0.5 }
end

--- Ensures corpse position does not clip into solid walkable blocks or boundaries
--- Nudges wall-sitting corpses forward away from the wall behind them and resolves solid collisions
---@param pos table The position vector of the corpse
---@param yaw number Facing yaw of the corpse in radians
---@param is_wall_sitting boolean True if pose is wall_sit or slouch
---@return table adjusted_pos Vector position cleared of solid obstructions
function deathstats.ensure_corpse_clearance(pos, yaw, is_wall_sitting)
    if not pos then return pos end
    local px, py, pz = pos.x, pos.y, pos.z

    -- If resting against a wall (wall_sit, slouch), nudge forward away from the wall behind
    if is_wall_sitting and yaw then
        local f_x = -math.sin(yaw)
        local f_z = math.cos(yaw)
        local nudge_dist = 0.18
        local cand_x = px + f_x * nudge_dist
        local cand_z = pz + f_z * nudge_dist

        scratch_pos.x = cand_x
        scratch_pos.y = py + 0.5
        scratch_pos.z = cand_z
        local cand_node = core.get_node_or_nil(scratch_pos)
        local ndef = cand_node and core.registered_nodes[cand_node.name]
        if not ndef or not ndef.walkable then
            px = cand_x
            pz = cand_z
        end
    end

    -- If corpse torso is inside a walkable solid block, push to nearest open air
    scratch_pos.x = px
    scratch_pos.y = py + 0.5
    scratch_pos.z = pz
    local torso_node = core.get_node_or_nil(scratch_pos)
    local torso_def = torso_node and core.registered_nodes[torso_node.name]
    if torso_def and torso_def.walkable and torso_node.name ~= "air" and torso_node.name ~= "ignore" then
        local dirs = {
            { x = 0.45, z = 0 },
            { x = -0.45, z = 0 },
            { x = 0, z = 0.45 },
            { x = 0, z = -0.45 },
        }
        for i = 1, #dirs do
            local d = dirs[i]
            scratch_pos.x = px + d.x
            scratch_pos.y = py + 0.5
            scratch_pos.z = pz + d.z
            local check_n = core.get_node_or_nil(scratch_pos)
            local check_def = check_n and core.registered_nodes[check_n.name]
            if not check_def or not check_def.walkable then
                px = px + d.x
                pz = pz + d.z
                break
            end
        end
    end

    return vector.new(px, py, pz)
end

--- Samples ambient illumination of the open space around a corpse
---@param pos table Position vector of the corpse
---@param yaw number|nil Facing yaw in radians
---@return number|nil light Ambient light value (0-14) or nil if unavailable
function deathstats.sample_corpse_ambient_light(pos, yaw)
    if not pos or not core.get_node_light then return nil end
    local base_yaw = yaw or 0

    scratch_pos.x = pos.x
    scratch_pos.y = pos.y + 0.5
    scratch_pos.z = pos.z
    local l = core.get_node_light(scratch_pos)
    if l and l > 0 then
        return math.min(14, l)
    end

    local sample_offsets = {
        { x = 0, y = 1.0, z = 0 },
        { x = -math.sin(base_yaw) * 0.5, y = 0.5, z = math.cos(base_yaw) * 0.5 },
        { x = 0, y = 1.5, z = 0 },
        { x = 0.5, y = 0.5, z = 0 },
        { x = -0.5, y = 0.5, z = 0 },
        { x = 0, y = 0.5, z = 0.5 },
        { x = 0, y = 0.5, z = -0.5 },
    }
    local max_l = 0
    for i = 1, #sample_offsets do
        local so = sample_offsets[i]
        scratch_pos.x = pos.x + so.x
        scratch_pos.y = pos.y + so.y
        scratch_pos.z = pos.z + so.z
        local n = core.get_node_or_nil(scratch_pos)
        local ndef = n and core.registered_nodes[n.name]
        if not ndef or not ndef.walkable or (ndef.liquidtype and ndef.liquidtype ~= "none") then
            local sl = core.get_node_light(scratch_pos)
            if sl and sl > max_l then
                max_l = sl
            end
        end
    end
    if max_l > 0 then
        return math.min(14, max_l)
    end
    return (l and math.min(14, l)) or nil
end

--- Settle the corpse entity to a complete rest at its final position
---@param luaent table|ObjectRef The corpse Lua entity table or ObjectRef
function deathstats.settle_corpse_at_rest(luaent)
    if not luaent then return end
    local obj = luaent.object
    if not obj and luaent.get_luaentity then
        local ent = luaent:get_luaentity()
        if ent then
            luaent = ent
            obj = ent.object or luaent
        else
            obj = luaent
        end
    elseif not obj and luaent.get_properties then
        obj = luaent
    end
    if luaent._settled then return end
    luaent._settled = true
    if not obj or (obj.is_valid and not obj:is_valid()) then return end

    if obj.set_velocity then obj:set_velocity(vector.zero()) end
    if obj.set_acceleration then obj:set_acceleration(vector.zero()) end

    local base_yaw = luaent._base_yaw or (obj.get_yaw and obj:get_yaw()) or 0
    local pitch = 0
    local roll = 0
    local pose_type = "supine"
    local pos = obj.get_pos and obj:get_pos()

    -- Determine resting orientation (supine, prone, lateral, wall_sit, slouch).
    -- Wall-sitting postures (wall_sit, slouch) strictly require an actual solid wall
    -- directly behind the corpse's back (is_wall_behind). A prior mid-air wall collision
    -- must never trigger sitting if the corpse landed out in the open or away from a wall.
    local is_wall_behind = pos and deathstats.detect_wall_behind(pos, base_yaw)
    if is_wall_behind and deathstats.config.ragdoll_resting_poses ~= false then
        local w_pick = math.random()
        if w_pick < 0.55 then
            pose_type = "wall_sit"
            roll = 0
            pitch = 0
        elseif w_pick < 0.85 then
            pose_type = "slouch"
            roll = math.rad(random_float(-8, 8))
            pitch = math.rad(-8)
        else
            pose_type = "supine"
            roll = 0
        end
    elseif deathstats.config.ragdoll_resting_poses ~= false and luaent._rot and luaent._rot.z then
        local r = (luaent._rot.z % (2 * math.pi))
        if r > math.pi then r = r - 2 * math.pi end
        local abs_r = math.abs(r)

        if abs_r > (5 * math.pi / 8) then
            pose_type = "prone"
            roll = math.pi
        elseif abs_r >= (3 * math.pi / 8) and abs_r <= (5 * math.pi / 8) then
            pose_type = "lateral"
            roll = (r > 0) and (math.pi / 2) or (-math.pi / 2)
        else
            pose_type = "supine"
            roll = 0
        end
    end
    luaent._pose_type = pose_type

    if pose_type == "wall_sit" or pose_type == "slouch" then
        deathstats.pose_corpse(obj, luaent._mesh, "sit")
    end

    if pos and not deathstats.is_in_liquid(pos) then
        local target_y = nil
        if deathstats.config.enable_slope_pitch ~= false and pose_type ~= "wall_sit" and pose_type ~= "slouch" then
            local detected_pitch, slope_target_y, ground_found = deathstats.detect_corpse_slope_pitch(pos, base_yaw)
            pitch = detected_pitch or 0
            if slope_target_y and (ground_found or (ground_found == nil and math.abs(slope_target_y - pos.y) > 0.001))
                and slope_target_y <= (pos.y + 0.5) and (pos.y - slope_target_y) <= 15.0 then
                target_y = slope_target_y
            end
        end

        -- If slope probe didn't resolve a ground surface or corpse is higher up in the air, find full ground surface below
        if not target_y then
            local surface_y = deathstats.find_ground_surface(pos, nil, luaent._death_info or { category = "fall" })
            if surface_y and surface_y < (pos.y - 0.001) and (pos.y - surface_y) <= 40.0 then
                target_y = surface_y + 0.02
            end
        end

        local pose_offset = deathstats.get_pose_elevation_offset(pose_type)
        if target_y then
            target_y = target_y + pose_offset
        elseif pose_offset > 0 then
            target_y = pos.y + pose_offset
        end

        if target_y and (math.abs(target_y - pos.y) > 0.001) and obj.set_pos then
            obj:set_pos(vector.new(pos.x, target_y, pos.z))
            pos = (obj.get_pos and obj:get_pos()) or vector.new(pos.x, target_y, pos.z)
            -- Re-evaluate slope pitch at exact ground position if slope pitch is enabled
            if deathstats.config.enable_slope_pitch ~= false and pose_type ~= "wall_sit" and pose_type ~= "slouch" then
                pitch = deathstats.detect_corpse_slope_pitch(pos, base_yaw) or pitch
            end
        end
    end

    -- Ensure corpse does not clip through solid nodes or boundaries (especially against walls)
    if pos then
        local is_wall_sitting = (pose_type == "wall_sit" or pose_type == "slouch")
        local cleared_pos = deathstats.ensure_corpse_clearance(pos, base_yaw, is_wall_sitting)
        if cleared_pos and (cleared_pos.x ~= pos.x or cleared_pos.y ~= pos.y or cleared_pos.z ~= pos.z) then
            pos = cleared_pos
            if obj.set_pos then
                obj:set_pos(pos)
            end
        end
    end

    if obj.set_rotation then
        obj:set_rotation({ x = pitch, y = base_yaw, z = roll })
    elseif obj.set_yaw then
        obj:set_yaw(base_yaw)
    end

    local hanging_legs = false
    if pos and deathstats.detect_hanging_legs and pose_type ~= "wall_sit" and pose_type ~= "slouch" then
        hanging_legs = deathstats.detect_hanging_legs(pos, base_yaw)
    end

    luaent._applied_bones = nil
    deathstats.settle_ragdoll_limbs(obj, luaent._impact_damage, pose_type, hanging_legs, roll)

    luaent._settled_pos = pos and vector.new(pos.x, pos.y, pos.z)

    local ambient_light = pos and deathstats.sample_corpse_ambient_light(pos, base_yaw)
    local corpse_props = {
        physical = false,
        pointable = (deathstats.config.enable_corpse_inspect ~= false),
        selectionbox = deathstats.get_pose_selectionbox(pose_type),
    }
    if ambient_light and ambient_light > 0 then
        corpse_props.glow = ambient_light
    end

    if obj.set_properties then
        obj:set_properties(corpse_props)
    end

    -- Re-evaluate environment effects once corpse has settled (e.g. rolled into water/lava)
    if deathstats.config.enable_corpse_particles ~= false and pos then
        local pname = luaent._player_name
        local cdata = pname and deathstats.player_camera_data and deathstats.player_camera_data[pname]
        local dinfo = luaent._death_info or (cdata and cdata.death_info) or {}
        local settled_effect = deathstats.get_corpse_effect_type and deathstats.get_corpse_effect_type(pos, dinfo)
        local current_effect = luaent._effect_type or (cdata and cdata.current_effect_type)
        local has_active_spawners = (luaent._particle_spawners and #luaent._particle_spawners > 0)
            or (cdata and cdata.particle_spawners and #cdata.particle_spawners > 0)

        local uy = math.cos(roll) * math.cos(pitch)
        local is_prone = (uy < -0.5)
        local initial_is_prone = luaent._particles_were_prone or (cdata and cdata.particles_were_prone)
        local orientation_changed = (initial_is_prone ~= nil and initial_is_prone ~= is_prone)

        if settled_effect and (settled_effect ~= current_effect or orientation_changed or (not has_active_spawners and settled_effect ~= "impact")) then
            if luaent._particle_spawners then
                for _, pid in ipairs(luaent._particle_spawners) do
                    core.delete_particlespawner(pid)
                end
                luaent._particle_spawners = nil
            end
            if cdata and cdata.particle_spawners then
                for _, pid in ipairs(cdata.particle_spawners) do
                    core.delete_particlespawner(pid)
                end
                cdata.particle_spawners = nil
            end
            if settled_effect ~= "impact" and deathstats.spawn_corpse_particles then
                local spawners, eff = deathstats.spawn_corpse_particles(pos, dinfo, obj)
                luaent._particle_spawners = spawners
                luaent._effect_type = eff
                luaent._particles_were_prone = is_prone
                if cdata then
                    cdata.particle_spawners = spawners
                    cdata.current_effect_type = eff
                    cdata.particles_were_prone = is_prone
                    cdata.corpse_settled = true
                    cdata.corpse_settled_particles_checked = true
                end
            else
                luaent._effect_type = settled_effect
                if cdata then
                    cdata.current_effect_type = settled_effect
                    cdata.corpse_settled = true
                    cdata.corpse_settled_particles_checked = true
                end
            end
        end
    end
end

local GROUND_PROBE_DYS = { -0.45, -0.85, -0.15, -0.55 }
local GROUND_PROBE_OFFSETS = {
    { x = 0, z = 0 },
    { x = -0.28, z = 0 },
    { x = 0.28, z = 0 },
    { x = 0, z = -0.28 },
    { x = 0, z = 0.28 },
    { x = -0.28, z = -0.28 },
    { x = 0.28, z = -0.28 },
    { x = -0.28, z = 0.28 },
    { x = 0.28, z = 0.28 },
}
local ground_probe_scratch = { x = 0, y = 0, z = 0 }

--- Check if a corpse has solid ground or liquid support beneath it
--- Used to detect if blocks below a settled corpse have been dug out
--- Uses integer coordinate rounding to prevent negative coordinate truncation in C++ engine
--- and probes the corpse collision footprint (±0.28) so corpses on edges/slopes remain grounded
---@param pos Vector 3D corpse position
---@return boolean has_support True if supported by walkable ground or liquid
function deathstats.has_ground_support(pos)
    if not pos then return true end

    local base_x = pos.x
    local base_y = pos.y
    local base_z = pos.z

    -- Track probed integer columns to avoid duplicate node queries when offsets map to same node
    local tested_cols = {}

    for o = 1, #GROUND_PROBE_OFFSETS do
        local off = GROUND_PROBE_OFFSETS[o]
        local px = math.floor(base_x + off.x + 0.5)
        local pz = math.floor(base_z + off.z + 0.5)
        local col_key = px * 65536 + pz

        if not tested_cols[col_key] then
            tested_cols[col_key] = true
            ground_probe_scratch.x = px
            ground_probe_scratch.z = pz

            for i = 1, #GROUND_PROBE_DYS do
                local py = math.floor(base_y + GROUND_PROBE_DYS[i] + 0.5)
                ground_probe_scratch.y = py
                local node = core.get_node_or_nil(ground_probe_scratch)
                if node and node.name ~= "ignore" then
                    if node.name ~= "air" then
                        local ndef = core.registered_nodes[node.name]
                        if ndef then
                            -- Liquid provides buoyancy support
                            if ndef.liquidtype and ndef.liquidtype ~= "none" then
                                return true
                            end
                            -- Solid walkable node provides ground support
                            if ndef.walkable ~= false then
                                return true
                            end
                        else
                            -- Node registered or unknown fallback
                            return true
                        end
                    end
                else
                    -- Mapblock not loaded, assume supported to avoid unnecessary physics
                    return true
                end
            end
        end
    end

    return false
end

local cached_fallback_ground = nil

--- Dynamically discover a representative ground node from core.registered_nodes using node groups
--- Completely mod-agnostic; avoids hardcoding any specific mod namespace like "default:"
---@return string|nil node_name Technical name of a registered walkable ground node
function deathstats.get_fallback_ground_node()
    if cached_fallback_ground and core.registered_nodes[cached_fallback_ground] then
        return cached_fallback_ground
    end
    -- Standard terrain groups across Luanti games (soil, stone, sand, crumbly, cracky)
    local candidate_groups = { "soil", "stone", "sand", "crumbly", "cracky" }
    for _, grp in ipairs(candidate_groups) do
        for name, def in pairs(core.registered_nodes) do
            if def and def.walkable and def.groups and (def.groups[grp] or 0) > 0
                and (def.drawtype == "normal" or not def.drawtype) and name ~= "air" and name ~= "ignore" then
                cached_fallback_ground = name
                return name
            end
        end
    end
    -- Any registered solid walkable node with normal drawtype
    for name, def in pairs(core.registered_nodes) do
        if def and def.walkable and (def.drawtype == "normal" or not def.drawtype) and name ~= "air" and name ~= "ignore" then
            cached_fallback_ground = name
            return name
        end
    end
    return nil
end

--- Determine whether a node surface is soft / cushioning using node groups and attributes
--- Checks fall_damage_add_percent < 0, crumbly, snappy, wool, leaves, sand, soil, snowy, hay
---@param ndef table|nil Node definition table
---@param node_name string|nil Technical node name
---@return boolean is_soft
function deathstats.is_soft_node(ndef, node_name)
    if not ndef then return false end
    if ndef.liquidtype and ndef.liquidtype ~= "none" then
        return true
    end
    local groups = ndef.groups
    if type(groups) == "table" then
        -- Engine group for fall damage reduction (beds, hay, cushions, slime)
        if groups.fall_damage_add_percent and groups.fall_damage_add_percent < 0 then
            return true
        end
        -- Standard Luanti soft material groups
        if (groups.crumbly and groups.crumbly > 0)
            or (groups.snappy and groups.snappy > 0)
            or (groups.leaves and groups.leaves > 0)
            or (groups.wool and groups.wool > 0)
            or (groups.cloth and groups.cloth > 0)
            or (groups.sand and groups.sand > 0)
            or (groups.soil and groups.soil > 0)
            or (groups.snowy and groups.snowy > 0)
            or (groups.hay and groups.hay > 0)
            or (groups.soft and groups.soft > 0) then
            return true
        end
    end
    -- Fallback name check if mod did not assign standard groups
    if node_name and type(node_name) == "string" then
        local lower = node_name:lower()
        if lower:find("sand") or lower:find("snow") or lower:find("leaves")
            or lower:find("wool") or lower:find("hay") or lower:find("dirt")
            or lower:find("mud") or lower:find("sponge") then
            return true
        end
    end
    return false
end

--- Extract an impact sound specification from a node definition table
--- Queries Luanti games and engine standard sound keys (dug, footstep, place, dig)
---@param ndef table|nil Node definition table
---@return string|nil sound_name, number base_gain, number base_pitch
function deathstats.get_node_impact_sound(ndef)
    if not ndef or type(ndef.sounds) ~= "table" then
        return nil, 1.0, 1.0
    end
    -- Standard node sound keys in Luanti games and engine:
    -- 'dug': Node struck / dug impact sound (e.g. default_hard_footstep, default_dirt_footstep with gain 1.0)
    -- 'footstep': Stepping sound on the node
    -- 'place': Node placement sound, also played by engine when falling blocks land
    -- 'dig': Node digging sound
    local sound_keys = { "dug", "footstep", "place", "dig", "step", "fall" }
    for _, key in ipairs(sound_keys) do
        local snd = ndef.sounds[key]
        if type(snd) == "string" and snd ~= "" then
            return snd, 1.0, 1.0
        elseif type(snd) == "table" and type(snd.name) == "string" and snd.name ~= "" then
            return snd.name, tonumber(snd.gain) or 1.0, tonumber(snd.pitch) or 1.0
        end
    end
    return nil, 1.0, 1.0
end


--- Check if bones were placed for this player at or near death position
---@param player ObjectRef The deceased player object
---@param search_center Vector|nil Optional search origin (defaults to orbit_center or player pos)
---@return Vector|nil pos The 3D coordinates of the placed bones node, or nil if not found
function deathstats.find_player_bones(player, search_center)
    if not core.registered_nodes["bones:bones"] then return nil end
    if not player or not player:is_player() then return nil end
    local name = player:get_player_name()
    local cam_data = deathstats.player_camera_data[name]
    local center = search_center or (cam_data and cam_data.orbit_center) or player:get_pos()
    if not center then return nil end
    local pos = vector.round(center)

    -- Check direct death node first
    local node = core.get_node(pos)
    if node.name == "bones:bones" then
        local meta = core.get_meta(pos)
        local owner = meta:get_string("owner")
        if owner == "" or owner == name then
            return pos
        end
    end

    -- Search adjacent nodes strictly checking that bones belong to this player
    local minp = vector.new(pos.x - 2, pos.y - 2, pos.z - 2)
    local maxp = vector.new(pos.x + 2, pos.y + 2, pos.z + 2)
    local positions = core.find_nodes_in_area(minp, maxp, { "bones:bones" })
    for _, bpos in ipairs(positions) do
        local meta = core.get_meta(bpos)
        if meta:get_string("owner") == name then
            return bpos
        end
    end
    return nil
end

--- Check if bones mod is active and configured to place/show bones
---@return boolean should_show_bones True if bones mod is active and bones_mode == "bones"
---@return string bones_mode The effective bones_mode setting ("bones", "drop", or "keep")
---@return boolean has_bones_mod True if bones mod is loaded in the world
function deathstats.get_bones_mode()
    local has_bones_mod = false
    if core.get_modpath("bones") then
        has_bones_mod = true
    elseif rawget(_G, "bones") ~= nil and type(rawget(_G, "bones")) == "table" then
        has_bones_mod = true
    end
    local mode = core.settings:get("bones_mode") or "bones"
    if mode ~= "bones" and mode ~= "drop" and mode ~= "keep" then
        mode = "bones"
    end
    local should_show_bones = has_bones_mod and (mode == "bones")
    return should_show_bones, mode, has_bones_mod
end

--- Check if a specific world position contains liquid (water, lava, or modded fluids)
---@param pos Vector The position to check
---@return boolean is_liquid True if the node is liquid
function deathstats.is_liquid_at(pos)
    if not pos then return false end
    local check_pos = vector.round(pos)
    local node = core.get_node(check_pos)
    if not node or node.name == "air" or node.name == "ignore" then
        return false
    end
    if core.get_item_group(node.name, "liquid") ~= 0
        or core.get_item_group(node.name, "water") ~= 0
        or core.get_item_group(node.name, "lava") ~= 0 then
        return true
    end
    local def = core.registered_nodes[node.name]
    if def then
        if def.liquidtype ~= nil and def.liquidtype ~= "none" then
            return true
        end
        if def.drawtype == "liquid" or def.drawtype == "flowingliquid" then
            return true
        end
    end
    local idef = core.registered_items[node.name]
    if idef and idef.groups and (idef.groups.liquid or idef.groups.water or idef.groups.lava) then
        return true
    end
    local nname = node.name:lower()
    if nname:find("water") or nname:find("lava") or nname:find("liquid") then
        return true
    end
    return false
end

--- Check if a death position represents being in a liquid (water, lava, etc.)
--- Checks death category as well as world nodes at feet, torso, and head level
---@param pos Vector Player death position
---@param death_info table|nil Optional death details
---@return boolean in_liquid True if player died in or around liquid
function deathstats.is_in_liquid(pos, death_info)
    if death_info and (death_info.category == "drown" or death_info.category == "lava") then
        return true
    end
    if not pos then return false end
    if deathstats.is_liquid_at(pos) then
        return true
    end
    -- Check surrounding node levels (feet, torso, head, bottom)
    scratch_pos.x = pos.x
    scratch_pos.z = pos.z
    scratch_pos.y = pos.y + 0.5
    if deathstats.is_liquid_at(scratch_pos) then return true end
    scratch_pos.y = pos.y + 1.0
    if deathstats.is_liquid_at(scratch_pos) then return true end
    scratch_pos.y = pos.y - 0.5
    if deathstats.is_liquid_at(scratch_pos) then return true end
    scratch_pos.y = pos.y - 1.0
    if deathstats.is_liquid_at(scratch_pos) then return true end
    return false
end

--- Find the true ground collision surface level beneath a position
--- Ensures the corpse rests directly flush on walkable terrain, slabs, stairs, or bones
--- For liquid deaths (water, lava), prevents pinning to the lake bed and retains exact death position
---@param pos Vector Player or death position
---@param bones_pos Vector|nil Coordinates of bones node if placed
---@param death_info table|nil Optional death analysis information
---@return number surface_y The exact Y coordinate where corpse should rest
function deathstats.find_ground_surface(pos, bones_pos, death_info)
    if not pos then return 0 end

    -- Liquid deaths (water, lava): Never pin to the lake/ocean bottom;
    -- retain the exact place of death so the corpse floats where the player died.
    if deathstats.is_in_liquid(pos, death_info) then
        return pos.y
    end

    if bones_pos then
        return bones_pos.y + 0.5
    end

    -- Check if direct node or bones is already right below or at pos
    local check_pos = vector.round(pos)
    local direct_node = core.get_node_or_nil(check_pos) or { name = "air" }
    if direct_node.name == "bones:bones" then
        return check_pos.y + 0.5
    end

    -- Determine downward search depth:
    -- For fall deaths (category == "fall", or nil/unspecified in backward-compatible unit tests),
    -- allow searching down to ground impact level (up to 40 nodes).
    -- For non-fall deaths in mid-air (suicide, /kill, mobs, projectiles, fire), only search near feet (2.5 nodes)
    -- to snap to floors/slabs/stairs if standing on solid ground. If suspended in mid-air, retain exact death height pos.y!
    local is_fall = (death_info == nil) or (death_info.category == nil)
        or (death_info.category == "fall") or (death_info.category == "explosion")
    local max_depth = is_fall and 40 or 2.5

    -- Downward raycast to detect exact collision surface (handles nodes, slabs, stairs, meshes)
    local start_pos = vector.new(pos.x, pos.y + 0.5, pos.z)
    local end_pos = vector.new(pos.x, pos.y - max_depth, pos.z)
    local ray = core.raycast(start_pos, end_pos, false, false)
    for pointed_thing in ray do
        if pointed_thing.type == "node" and pointed_thing.under then
            local node = core.get_node_or_nil(pointed_thing.under)
            local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
            if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
                if pointed_thing.intersection_point then
                    return pointed_thing.intersection_point.y
                else
                    return pointed_thing.under.y + 0.5
                end
            end
        end
    end

    -- Fallback: discrete node scanning downward from math.floor(pos.y + 0.5) down to max_depth
    local start_y = math.floor(pos.y + 0.5)
    local check_x = math.floor(pos.x + 0.5)
    local check_z = math.floor(pos.z + 0.5)
    local min_y = math.floor(pos.y - max_depth + 0.5)
    scratch_pos.x = check_x
    scratch_pos.z = check_z
    for y = start_y, min_y, -1 do
        scratch_pos.y = y
        local node = core.get_node_or_nil(scratch_pos)
        local def = node and node.name ~= "ignore" and core.registered_nodes[node.name]
        if def and def.walkable and node.name ~= "air" and def.drawtype ~= "airlike" then
            return y + 0.5
        end
    end

    -- If no solid ground found within max_depth (e.g. suspended in mid-air / floating), retain pos.y
    return pos.y
end
