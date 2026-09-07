--[[
    Automated Unit Test Suite for deathstats mod
    Copyright (C) 2026 SaKeL
--]]

-- String helper for Lua 5.1 / Luanti compatibility
local unpack = unpack or table.unpack
if not string.split then
    rawset(string, "split", function(str, sep)
        local parts = {}
        local pattern = string.format("([^%s]+)", sep)
        for part in str:gmatch(pattern) do
            table.insert(parts, part)
        end
        return parts
    end)
end

if not table.copy then
    rawset(table, "copy", function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do
            res[k] = (type(v) == "table" and table.copy(v)) or v
        end
        return res
    end)
end

-- Mock core / minetest engine environment
vector = {
    new = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end,
    copy = function(v) return { x = v.x, y = v.y, z = v.z } end,
    zero = function() return { x = 0, y = 0, z = 0 } end,
    distance = function(a, b)
        local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end,
    round = function(v)
        return { x = math.floor(v.x + 0.5), y = math.floor(v.y + 0.5), z = math.floor(v.z + 0.5) }
    end,
    direction = function(from, to)
        local dx = to.x - from.x
        local dy = to.y - from.y
        local dz = to.z - from.z
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len == 0 then len = 1 end
        return { x = dx / len, y = dy / len, z = dz / len }
    end,
    add = function(a, b)
        return { x = a.x + (type(b) == "table" and b.x or b), y = a.y + (type(b) == "table" and b.y or b), z = a.z + (type(b) == "table" and b.z or b) }
    end,
    subtract = function(a, b)
        return { x = a.x - (type(b) == "table" and b.x or b), y = a.y - (type(b) == "table" and b.y or b), z = a.z - (type(b) == "table" and b.z or b) }
    end,
    multiply = function(a, s)
        if type(s) == "table" then
            return { x = a.x * s.x, y = a.y * s.y, z = a.z * s.z }
        else
            return { x = a.x * s, y = a.y * s, z = a.z * s }
        end
    end,
}

local deferred_tasks = {}

core = {
    registered_items = {
        ["default:pick_diamond"] = { description = "Diamond Pickaxe" },
        ["default:sword_steel"] = { description = "Steel Sword" },
        ["default:stone_with_coal"] = { description = "Coal Ore", groups = { cracky = 3, ore = 1 } },
        ["default:stone_with_iron"] = { description = "Iron Ore", groups = { cracky = 2, ore = 1 } },
        ["default:water_source"] = { description = "Water Source", groups = { water = 3, liquid = 3 } },
        ["default:lava_source"] = { description = "Lava Source", groups = { lava = 3, liquid = 3, igniter = 1 } },
        ["default:stone"] = { description = "Stone", walkable = true },
    },
    registered_nodes = {
        ["default:stone"] = { walkable = true, drawtype = "normal" },
        ["default:dirt"] = { walkable = true, drawtype = "normal" },
        ["default:water_source"] = { walkable = false, drawtype = "liquid" },
        ["default:lava_source"] = { walkable = false, drawtype = "liquid" },
        ["bones:bones"] = { walkable = true, drawtype = "normal" },
        ["air"] = { walkable = false, drawtype = "airlike" },
    },
    registered_entities = {
        ["mobs_monster:zombie"] = { description = "Zombie" },
        ["mcl_mobs:creeper"] = { description = "Creeper" },
    },
    get_current_modname = function() return "deathstats" end,
    loaded_mods = { ["deathstats"] = ".", ["hudbars"] = "." },
    get_modpath = function(modname)
        if not modname or modname == "deathstats" then return "." end
        return core.loaded_mods and core.loaded_mods[modname]
    end,
    colorize = function(color, text)
        return "\27(c@" .. color .. ")" .. text .. "\27E"
    end,
    get_translator = function()
        return function(s, ...)
            local args = { ... }
            if #args == 0 then return s end
            local res = s
            for i, arg in ipairs(args) do
                res = res:gsub("@" .. i, tostring(arg))
            end
            return res
        end
    end,
    strip_colors = function(s) return s and (s:gsub("\27%b()", ""):gsub("\27.", "")) or "" end,
    formspec_escape = function(s) return s or "" end,
    get_gametime = function() return 1000 end,
    settings = {
        data = {},
        get = function(self, k) return self.data[k] end,
        get_bool = function(self, k, default)
            local v = self.data[k]
            if v == nil then return default end
            return v == true or v == "true"
        end,
        set = function(self, k, v) self.data[k] = v end,
        set_bool = function(self, k, v) self.data[k] = v end,
    },
    get_item_group = function(name, grp)
        local def = core.registered_items[name]
        return (def and def.groups and def.groups[grp]) or 0
    end,
    world_nodes = {},
    get_node = function(pos)
        local k = string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
        local val = core.world_nodes[k] or pos.node_name or "air"
        return { name = (type(val) == "table" and val.name) or val }
    end,
    get_node_or_nil = function(pos)
        return core.get_node(pos)
    end,
    set_node = function(pos, node)
        local k = string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
        core.world_nodes[k] = (type(node) == "table" and node.name) or node
    end,
    find_nodes_in_area = function(minp, maxp, nodenames)
        local res = {}
        for _, nname in ipairs(nodenames) do
            for k, v in pairs(core.world_nodes) do
                if v == nname then
                    local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
                    if x and y and z then
                        x, y, z = tonumber(x), tonumber(y), tonumber(z)
                        if x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z then
                            table.insert(res, { x = x, y = y, z = z })
                        end
                    end
                end
            end
        end
        return res
    end,
    node_metas = {},
    get_meta = function(pos)
        local key = string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
        if core.node_metas and core.node_metas[key] then
            return core.node_metas[key]
        end
        return {
            get_string = function(self, k) return "" end,
            set_string = function(self, k, v) end,
        }
    end,
    serialize = function(val)
        local function ser(v)
            local tv = type(v)
            if tv == "number" or tv == "boolean" then
                return tostring(v)
            elseif tv == "string" then
                return string.format("%q", v)
            elseif tv == "table" then
                local parts = {}
                for k, sub_v in pairs(v) do
                    local key_str = (type(k) == "number") and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
                    table.insert(parts, key_str .. "=" .. ser(sub_v))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            elseif tv == "nil" then
                return "nil"
            else
                error("unsupported type: " .. tv)
            end
        end
        return "return " .. ser(val)
    end,
    deserialize = function(str)
        if not str or str == "" then return nil end
        local loader = rawget(_G, "loadstring") or rawget(_G, "load")
        if loader then
            local fn = loader(str)
            if fn then
                local ok, res = pcall(fn)
                if ok then return res end
            end
        end
        return nil
    end,
    sound_play = function(name, params)
        core.last_sound = { name = name, params = params }
    end,
    show_formspec = function(name, formname, fs)
        core.last_formspec = { name = name, formname = formname, fs = fs }
    end,
    close_formspec = function(name, formname)
        core.closed_formspec = { name = name, formname = formname }
    end,
    after = function(delay, func, ...)
        table.insert(deferred_tasks, { func = func, args = { ... } })
    end,
    active_particlespawners = {},
    next_particlespawner_id = 1,
    add_particlespawner = function(def)
        local id = core.next_particlespawner_id
        core.next_particlespawner_id = core.next_particlespawner_id + 1
        core.active_particlespawners[id] = def
        return id
    end,
    delete_particlespawner = function(id, _playername)
        core.active_particlespawners[id] = nil
    end,
    spawned_entities = {},
    add_entity = function(pos, name)
        local def = core.registered_entities and core.registered_entities[name]
        local init_props = {}
        if def and def.initial_properties then
            for k, v in pairs(def.initial_properties) do init_props[k] = v end
        end
        local ent = {
            name = name,
            pos = pos,
            properties = init_props,
            yaw = 0,
            removed = false,
            is_valid = function(self) return not self.removed end,
            set_pos = function(self, p) self.pos = p end,
            get_pos = function(self) return self.pos end,
            set_properties = function(self, p)
                for k, v in pairs(p) do self.properties[k] = v end
            end,
            get_properties = function(self) return self.properties end,
            set_yaw = function(self, y) self.yaw = y end,
            get_yaw = function(self) return self.yaw end,
            set_rotation = function(self, r) self.rotation = r end,
            get_rotation = function(self) return self.rotation or { x = 0, y = self.yaw or 0, z = 0 } end,
            set_animation = function(self, anim, speed, blend, loop)
                self.animation = { anim = anim, speed = speed, blend = blend, loop = loop }
            end,
            set_armor_groups = function(self, g) self.armor_groups = g end,
            set_bone_override = function(self, bone, override)
                self.bone_overrides = self.bone_overrides or {}
                self.bone_overrides[bone] = override
            end,
            get_bone_override = function(self, bone)
                return self.bone_overrides and self.bone_overrides[bone]
            end,
            set_bone_position = function(self, bone, b_pos, rot)
                self.bone_positions = self.bone_positions or {}
                self.bone_positions[bone] = { pos = b_pos, rot = rot }
            end,
            get_bone_position = function(self, bone)
                if self.bone_positions and self.bone_positions[bone] then
                    return self.bone_positions[bone].pos, self.bone_positions[bone].rot
                end
                return vector.zero(), vector.zero()
            end,
            remove = function(self) self.removed = true end,
        }
        table.insert(core.spawned_entities, ent)
        return ent
    end,
    spawned_items = {},
    add_item = function(pos, item)
        local itm = {
            pos = pos,
            item = item,
            velocity = { x = 0, y = 0, z = 0 },
            set_velocity = function(self, v) self.velocity = v end,
        }
        table.insert(core.spawned_items, itm)
        return itm
    end,
    raycast = function(pos1, pos2, objects, liquids)
        return function() return nil end
    end,
    is_creative_enabled = function(name) return false end,
}

rawset(_G, "ItemStack", function(item_param)
    local item_str = type(item_param) == "string" and item_param or (type(item_param) == "table" and (item_param.name or (item_param.get_name and item_param:get_name()))) or ""
    local item_name, count_str = item_str:match("^([^%s]+)%s*(%d*)")
    item_name = item_name or item_str
    local item_count = tonumber(count_str) or 1
    return {
        name = item_name,
        get_name = function() return item_name end,
        is_empty = function() return item_name == "" end,
        get_count = function() return item_count end,
        take_item = function(self, n) return self end,
        to_table = function() return { name = item_name, count = item_count, wear = 0, metadata = "" } end,
        to_string = function() return item_name .. (item_count > 1 and (" " .. item_count) or "") end,
    }
end)

local hb_hidden = {}
rawset(_G, "hb", {
    hudtables = {
        health = {
            hudids = {
                HUDGuy = { bg = 101, icon = 102, bar = 103, text = 104 },
                CamHUDGuy = { bg = 201, icon = 202, bar = 203, text = 204 },
            },
            hudstate = {
                HUDGuy = { hidden = false, value = 20, max = 20 },
                CamHUDGuy = { hidden = false, value = 20, max = 20 },
            },
        },
        breath = {
            hudids = {
                HUDGuy = { bg = 105, icon = 106, bar = 107, text = 108 },
                CamHUDGuy = { bg = 205, icon = 206, bar = 207, text = 208 },
            },
            hudstate = {
                HUDGuy = { hidden = false, value = 10, max = 10 },
                CamHUDGuy = { hidden = false, value = 10, max = 10 },
            },
        },
        hunger = {
            hudids = {
                HUDGuy = { bg = 109, icon = 110, bar = 111, text = 112 },
                CamHUDGuy = { bg = 209, icon = 210, bar = 211, text = 212 },
            },
            hudstate = {
                HUDGuy = { hidden = false, value = 20, max = 20 },
                CamHUDGuy = { hidden = false, value = 20, max = 20 },
            },
        },
    },
    players = {},
    hide_hudbar = function(player, id)
        local name = player:get_player_name()
        hb_hidden[name] = hb_hidden[name] or {}
        hb_hidden[name][id] = true
        if hb.hudtables[id] and hb.hudtables[id].hudstate and hb.hudtables[id].hudstate[name] then
            hb.hudtables[id].hudstate[name].hidden = true
        end
        return true
    end,
    unhide_hudbar = function(player, id)
        local name = player:get_player_name()
        if hb_hidden[name] then
            hb_hidden[name][id] = nil
        end
        if hb.hudtables[id] and hb.hudtables[id].hudstate and hb.hudtables[id].hudstate[name] then
            hb.hudtables[id].hudstate[name].hidden = false
        end
        return true
    end,
    change_hudbar = function(_player, _id, ...)
        return true
    end,
    init_hudbar = function(_player, _id, _start_val, _start_max, _start_hidden)
        return true
    end,
    get_hidden = function() return hb_hidden end,
})

local function run_deferred_tasks()
    local tasks = deferred_tasks
    deferred_tasks = {}
    for _, t in ipairs(tasks) do
        t.func(unpack(t.args))
    end
end

local function make_dispatcher()
    local list = {}
    local register = function(fn) table.insert(list, fn) end
    local dispatch = function(...)
        local res
        for _, fn in ipairs(list) do
            local r = fn(...)
            if r ~= nil then
                res = r
            end
        end
        return res
    end
    return register, dispatch
end

core.register_on_punchplayer, core.on_punchplayer = make_dispatcher()
core.register_on_punchnode, core.on_punchnode = make_dispatcher()
core.register_on_dignode, core.on_dignode = make_dispatcher()
core.register_on_placenode, core.on_placenode = make_dispatcher()
core.register_on_craft, core.on_craft = make_dispatcher()
core.register_on_item_eat, core.on_item_eat = make_dispatcher()
core.register_on_rightclickplayer, core.on_rightclickplayer = make_dispatcher()
core.register_on_item_pickup, core.on_item_pickup = make_dispatcher()
core.register_on_player_hpchange, core.on_player_hpchange = make_dispatcher()
core.register_on_joinplayer, core.on_joinplayer = make_dispatcher()
core.register_on_leaveplayer, core.on_leaveplayer = make_dispatcher()
core.register_on_shutdown, core.on_shutdown = make_dispatcher()
core.register_globalstep, core.on_globalstep = make_dispatcher()
core.register_on_mods_loaded, core.on_mods_loaded = make_dispatcher()
core.register_on_dieplayer, core.on_dieplayer = make_dispatcher()
core.register_on_respawnplayer, core.on_respawnplayer = make_dispatcher()
core.register_on_player_receive_fields, core.on_receive_fields = make_dispatcher()
core.get_connected_players = function() return {} end
core.log = function(...) end
core.chatcommands = {}
core.register_chatcommand = function(name, def)
    core.chatcommands[name] = def
end

local mock_storage = {}
core.get_mod_storage = function()
    return {
        get_string = function(self, k) return mock_storage[k] or "" end,
        set_string = function(self, k, v) mock_storage[k] = v end,
    }
end

-- Load mod files
core.register_entity = function(name, def)
    core.registered_entities[name] = def
    return def
end
core.register_item = function(name, def)
    core.registered_items[name] = def
    return def
end

local modpath = (core.get_modpath and core.get_modpath("deathstats")) or "."
local ftest = io.open(modpath .. "/api.lua", "r")
if ftest then
    ftest:close()
else
    modpath = "/Users/juraj/Library/Application Support/minetest/mods/deathstats"
end

-- Mock player_api to verify animation hook
rawset(_G, "player_api", {
    set_animation = function(player, anim_name, speed, loop)
        if loop == nil then loop = true end
        player.current_anim = { anim = anim_name, speed = speed or 30, loop = loop }
    end,
})

dofile(modpath .. "/api.lua")
dofile(modpath .. "/stats.lua")
dofile(modpath .. "/reason.lua")
dofile(modpath .. "/gui.lua")
dofile(modpath .. "/compat/hudbars.lua")

-- Trigger mod loading completion so entities are hooked
core.on_mods_loaded()

print("=== RUNNING DEATHSTATS UNIT TESTS ===")

-- TEST 1: Utilities
assert(deathstats.format_time(45) == "45s", "format_time 45s failed")
assert(deathstats.format_time(125) == "2m 5s", "format_time 2m 5s failed")
assert(deathstats.format_time(3725) == "1h 2m 5s", "format_time 1h 2m 5s failed")
assert(deathstats.format_time(90000) == "1d 1h 0m", "format_time 1d failed")

assert(deathstats.format_number(1234567) == "1,234,567", "format_number 1.2M failed")
assert(deathstats.format_number(42) == "42", "format_number 42 failed")

assert(deathstats.format_name("default:sword_steel") == "Steel Sword", "format_name failed")
assert(deathstats.format_name("everness:coral_tree") == "Coral Tree", "format_name fallback failed")

-- Verify Luanti translation escape sequences, color resets (\27E), and tooltips are cleaned
core.registered_items["default:stone_with_coal"] = { description = "\27(T@default)Coal Ore\27E" }
assert(deathstats.format_name("default:stone_with_coal") == "Coal Ore", "format_name failed to strip translation escape E")

core.registered_items["default:stone_with_iron"] = { description = "\27(c@#ff4444)Iron Ore\27E" }
assert(deathstats.format_name("default:stone_with_iron") == "Iron Ore", "format_name failed to strip color code escape E")

core.registered_items["default:stone_with_diamond"] = { description = "Diamond Ore\nRare and precious gemstone." }
assert(deathstats.format_name("default:stone_with_diamond") == "Diamond Ore", "format_name failed to strip multiline description")
print("  [PASS] Utilities (time, number, name formatting & translation escape stripping)")

local mock_players = {}
local function create_mock_player(name)
    local p = {
        name = name,
        pos = { x = 0, y = 10, z = 0 },
        breath = 10,
        hp = 20,
        armor_groups = { fleshy = 100 },
        camera = nil,
        eye_offset = nil,
        physics_override = { speed = 1, jump = 1, gravity = 1, sneak = true },
        velocity = { x = 0, y = 0, z = 0 },
        look_vertical = 0,
        hud_flags = {},
        huds = {},
        hud_id_counter = 1,
        get_player_name = function(self) return self.name end,
        is_player = function(self) return true end,
        attached_parent = nil,
        set_attach = function(self, parent, bone, pos, rot, forced_visible)
            self.attached_parent = parent
        end,
        get_attach = function(self)
            return self.attached_parent
        end,
        set_detach = function(self)
            self.attached_parent = nil
        end,
        add_velocity = function(self, vel)
            self.velocity = vector.add(self.velocity, vel)
        end,
        get_pos = function(self)
            if self.attached_parent then
                return self.attached_parent:get_pos()
            end
            return self.pos
        end,
        set_pos = function(self, pos) self.pos = pos end,
        get_hp = function(self) return self.hp end,
        set_hp = function(self, hp, reason)
            local diff = hp - self.hp
            if core.on_player_hpchange then
                diff = core.on_player_hpchange(self, diff, reason or { type = "set_hp" })
            end
            self.hp = math.max(0, self.hp + diff)
        end,
        get_armor_groups = function(self) return self.armor_groups end,
        set_armor_groups = function(self, ag) self.armor_groups = ag end,
        properties = {
            visual_size = { x = 1, y = 1, z = 1 },
            mesh = "character.b3d",
            textures = { "character.png" },
            eye_height = 1.625,
            pointable = true,
            interaction_range = 4,
        },
        get_properties = function(self) return self.properties end,
        set_properties = function(self, props)
            for k, v in pairs(props) do
                self.properties[k] = v
            end
        end,
        inventory = {
            lists = { main = {}, craft = {}, hand = {} },
            sizes = { main = 32, craft = 9, hand = 0 },
            get_list = function(self, list_name) return self.lists[list_name] end,
            set_list = function(self, list_name, l)
                local wrapped = {}
                for i, item in ipairs(l or {}) do
                    wrapped[i] = (type(item) == "table" and item.get_name) and item or rawget(_G, "ItemStack")(item)
                end
                self.lists[list_name] = wrapped
            end,
            get_size = function(self, list_name) return (self.sizes and self.sizes[list_name]) or #(self.lists[list_name] or {}) end,
            set_size = function(self, list_name, sz)
                self.sizes = self.sizes or {}
                self.sizes[list_name] = sz
                self.lists[list_name] = self.lists[list_name] or {}
            end,
            get_stack = function(self, list_name, i) return (self.lists[list_name] or {})[i] end,
            set_stack = function(self, list_name, i, stack)
                self.lists[list_name] = self.lists[list_name] or {}
                local item = (type(stack) == "table" and stack.get_name) and stack or rawget(_G, "ItemStack")(stack)
                self.lists[list_name][i] = item
            end,
        },
        get_inventory = function(self) return self.inventory end,
        get_breath = function(self) return self.breath end,
        get_velocity = function(self) return self.velocity end,
        set_velocity = function(self, v) self.velocity = v end,
        set_physics_override = function(self, po)
            for k, v in pairs(po) do
                self.physics_override[k] = v
            end
        end,
        get_physics_override = function(self) return self.physics_override end,
        get_wielded_item = function(self)
            return {
                get_name = function() return "default:sword_steel" end,
                get_definition = function() return core.registered_items["default:sword_steel"] end,
            }
        end,
        set_camera = function(self, cam) self.camera = cam end,
        get_camera = function(self) return self.camera end,
        look_horizontal = 0,
        set_look_horizontal = function(self, h) self.look_horizontal = h end,
        get_look_horizontal = function(self) return self.look_horizontal end,
        set_look_vertical = function(self, v) self.look_vertical = v end,
        get_look_vertical = function(self) return self.look_vertical end,
        set_eye_offset = function(self, o1, o2) self.eye_offset = { o1, o2 } end,
        get_eye_offset = function(self) return unpack(self.eye_offset or {}) end,
        nametag_attributes = {
            text = name,
            color = { a = 255, r = 255, g = 255, b = 255 },
            bgcolor = { a = 0, r = 0, g = 0, b = 0 },
        },
        get_nametag_attributes = function(self)
            return self.nametag_attributes
        end,
        set_nametag_attributes = function(self, attrs)
            self.nametag_attributes = self.nametag_attributes or {}
            for k, v in pairs(attrs) do
                self.nametag_attributes[k] = v
            end
        end,
        children = {},
        get_children = function(self)
            return self.children or {}
        end,
        hud_set_flags = function(self, flags)
            for k, v in pairs(flags) do
                self.hud_flags[k] = v
            end
        end,
        get_meta = function(self)
            self.meta_obj = self.meta_obj or {
                fields = {},
                get_string = function(s, k) return s.fields[k] or "" end,
                set_string = function(s, k, v) s.fields[k] = v or "" end,
                get_int = function(s, k) return tonumber(s.fields[k]) or 0 end,
                set_int = function(s, k, v) s.fields[k] = tostring(v) end,
            }
            return self.meta_obj
        end,
        hud_add = function(self, def)
            local id = self.hud_id_counter
            self.hud_id_counter = self.hud_id_counter + 1
            self.huds[id] = def
            return id
        end,
        hud_change = function(self, id, stat, val)
            self.huds[id] = self.huds[id] or {}
            self.huds[id][stat] = val
        end,
        hud_remove = function(self, id)
            self.huds[id] = nil
        end,
        respawn = function(self)
            self.respawned = true
            self.hp = 20
            deathstats.on_player_respawn(self)
        end,
    }
    mock_players[name] = p
    return p
end

local player1 = create_mock_player("Alice")
local player2 = create_mock_player("Bob")

core.get_player_by_name = function(name)
    return mock_players[name]
end

-- Initialize player data via join hook
core.on_joinplayer(player1)
core.on_joinplayer(player2)

-- TEST 3: Direct Killer & Weapon Identification
local pvp_reason = {
    type = "punch",
    object = player2,
}
local analysis_pvp = deathstats.analyze_death(player1, pvp_reason)
assert(analysis_pvp.category == "pvp", "PvP category failed")
assert(analysis_pvp.killer_name == "Bob", "PvP killer name failed")
assert(analysis_pvp.weapon == "Steel Sword", "PvP weapon detection failed")
print("  [PASS] PvP death analysis & weapon detection")

-- TEST 4: Environmental Fallbacks
local fall_reason = {
    type = "fall",
}
local analysis_fall = deathstats.analyze_death(player1, fall_reason)
assert(analysis_fall.category == "fall", "Fall category failed")
print("  [PASS] Fall death analysis")

-- Drowning fallback (reason = nil, breath = 0, node = water)
player1.breath = 0
player1.pos = { x = 0, y = 5, z = 0, node_name = "default:water_source" }
local analysis_drown = deathstats.analyze_death(player1, nil)
assert(analysis_drown.category == "drown", "Drowning fallback failed")
print("  [PASS] Drowning fallback inspection")

-- Lava fallback
player1.breath = 10
player1.pos = { x = 0, y = 1, z = 0, node_name = "default:lava_source" }
local analysis_lava = deathstats.analyze_death(player1, nil)
assert(analysis_lava.category == "lava", "Lava fallback failed")
print("  [PASS] Lava fallback inspection")

-- Recent puncher fallback when reason is nil
player1.pos = { x = 0, y = 10, z = 0, node_name = "air" }
deathstats.recent_punches["Alice"] = {
    hitter = player2,
    time = 1000,
    tool_desc = "Steel Sword",
}
local analysis_recent = deathstats.analyze_death(player1, nil)
assert(analysis_recent.category == "pvp", "Recent puncher fallback failed")
assert(analysis_recent.killer_name == "Bob", "Recent puncher name failed")
print("  [PASS] Recent puncher fallback inspection")

-- TEST 5: Live Stats Tracking
local pdata = deathstats.get_player_data(player1)
assert(pdata ~= nil, "get_player_data failed")

core.on_dignode({ x = 0, y = 0, z = 0 }, { name = "default:stone" }, player1)
assert(pdata.current_run.blocks_mined == 1, "blocks_mined failed")
assert(pdata.current_run.total_ores == 0, "total_ores check failed")

core.on_dignode({ x = 0, y = 0, z = 0 }, { name = "default:stone_with_diamond" }, player1)
core.on_dignode({ x = 0, y = 0, z = 0 }, { name = "default:stone_with_coal" }, player1)
assert(pdata.current_run.blocks_mined == 3, "blocks_mined with ore failed")
assert(pdata.current_run.total_ores == 2, "total_ores with ore failed")
assert(pdata.current_run.ores_mined["default:stone_with_diamond"] == 1, "ore breakdown failed")
assert(pdata.current_run.ores_mined["default:stone_with_coal"] == 1, "coal ore breakdown failed")

-- Repeat with cached ore
core.on_dignode({ x = 0, y = 0, z = 0 }, { name = "default:stone_with_coal" }, player1)
assert(pdata.current_run.blocks_mined == 4, "blocks_mined with repeated ore failed")
assert(pdata.current_run.total_ores == 3, "total_ores with repeated ore failed")
assert(pdata.current_run.ores_mined["default:stone_with_coal"] == 2, "coal ore breakdown repeat check failed")

core.on_craft({ get_count = function() return 4 end }, player1, nil, nil)
assert(pdata.current_run.items_crafted == 4, "crafting tracking failed")

core.on_item_eat(4, nil, nil, player1, nil)
assert(pdata.current_run.items_consumed == 1, "eating tracking failed")

core.on_player_hpchange(player1, -6, nil)
assert(pdata.current_run.damage_taken == 6, "damage taken failed")

core.on_punchplayer(player2, player1, 1.0, nil, nil, 10)
assert(pdata.current_run.damage_dealt == 10, "damage dealt failed")

-- TEST 5B: Mob Combat Damage & Projectile Tracking
local mob_ent_def = core.registered_entities["mobs_monster:zombie"]
local zombie_instance = {
    name = "mobs_monster:zombie",
    health = 20,
}
zombie_instance.object = {
    get_hp = function() return zombie_instance.health end,
    is_player = function() return false end,
    get_luaentity = function() return zombie_instance end,
}
zombie_instance.on_punch = mob_ent_def.on_punch

-- Direct player punch to mob
local old_dmg = pdata.current_run.damage_dealt
zombie_instance:on_punch(player1, 1.0, { damage_groups = { fleshy = 6 } }, { x=0, y=0, z=1 }, 6)
zombie_instance.health = 14
assert(pdata.current_run.damage_dealt == old_dmg + 6, "Direct mob damage tracking failed")

-- Arrow projectile punch to mob (fired by player1)
local arrow_luaent = {
    name = "x_bows:arrow_entity",
    _user = player1,
    _user_name = "Alice",
}
local arrow_obj = {
    is_player = function() return false end,
    get_luaentity = function() return arrow_luaent end,
}
old_dmg = pdata.current_run.damage_dealt
zombie_instance:on_punch(arrow_obj, 1.0, { damage_groups = { fleshy = 14 } }, { x=0, y=0, z=1 }, 14)
zombie_instance.health = 0
assert(pdata.current_run.damage_dealt == old_dmg + 14, "Projectile mob damage tracking failed")
assert(pdata.current_run.mobs_killed == 1, "Projectile mob kill tracking failed")

-- Subsequent punch to already dead corpse must not award additional mob kills
zombie_instance:on_punch(player1, 1.0, { damage_groups = { fleshy = 5 } }, { x=0, y=0, z=1 }, 5)
assert(pdata.current_run.mobs_killed == 1, "Hitting dead mob corpse must not award duplicate kill")
print("  [PASS] Live statistics engine (mining, ores, crafting, eating, mob & projectile damage)")

-- TEST 5C: Projectile PvP Death Analysis
local proj_pvp_reason = {
    type = "punch",
    object = {
        is_player = function() return false end,
        get_luaentity = function()
            return {
                name = "x_bows:arrow_entity",
                _user = player2,
                _user_name = "Bob",
            }
        end,
    },
}
local analysis_proj = deathstats.analyze_death(player1, proj_pvp_reason)
assert(analysis_proj.category == "pvp", "Projectile PvP category failed")
assert(analysis_proj.killer_name == "Bob", "Projectile PvP killer name failed")
assert(analysis_proj.weapon == "Bow & Arrow", "Projectile weapon name failed")
print("  [PASS] Projectile PvP kill recognition (x_bows arrow / x_obsidianmese sword projectile)")

-- TEST 6: Death Trigger, Formspec Immobilization & Camera Control
player1:set_hp(0)
deathstats.trigger_death_screen(player1, pvp_reason)

-- Verify player is registered as dead
assert(deathstats.dead_players["Alice"] == true, "Player Alice not marked dead")

-- Verify formspec is immediately shown to immobilize player
assert(core.last_formspec ~= nil and core.last_formspec.formname == "deathstats:death", "Death formspec must be displayed immediately to immobilize player")

-- Verify camera switched to circular smooth orbit in first person mode with eye offset around corpse
assert(player1.camera ~= nil and player1.camera.mode == "first", "Camera mode must be 'first' during deathcam orbit")
assert(player1.eye_offset ~= nil and player1.eye_offset[1].z < 0, "First person eye offset must project backwards")
assert(player1.properties.visual_size.x == 0, "Player must be invisible during orbit")
assert(deathstats.player_camera_data["Alice"].corpse ~= nil, "Corpse entity must be spawned")
assert(player1.look_vertical > 0, "Camera look_vertical must be tilted downward toward corpse")
assert(core.last_sound ~= nil and core.last_sound.params.to_player == "Alice", "Sound play failed")
assert(core.last_sound.name == "deathstats_death", "Sound name must be 'deathstats_death' group")
assert(pdata.last_life.blocks_mined == 4, "Last life snapshot blocks failed")
assert(pdata.last_life.items_crafted == 4, "Last life snapshot craft failed")
assert(pdata.lifetime.deaths == 1, "Lifetime deaths failed")

-- Verify HUD elements positioning (spaced at y=0.20, 0.33, 0.37)
local hud_you_died = nil
local hud_cause = nil
local hud_funny = nil
local hud_splatter = nil
for id, hdef in pairs(player1.huds) do
    assert(hdef.type ~= nil, "HUD element must use 'type' field (no deprecated hud_elem_type)")
    if hdef.text and hdef.text:find("deathstats_you_died") then
        hud_you_died = hdef
    end
    if hdef.text and hdef.text:find("deathstats_blood_splatter") then
        hud_splatter = hdef
    end
    if hdef.type == "text" and hdef.number == 0xFFFFFF then
        hud_cause = hdef
    end
    if hdef.type == "text" and hdef.number == 0xEEEEEE then
        hud_funny = hdef
    end
end
assert(hud_splatter ~= nil, "Blood splatter HUD overlay must exist on death")
assert(hud_splatter.position.x == 0.5 and hud_splatter.position.y == 0.5, "Splatter must be centered at 0.5, 0.5")
assert(hud_splatter.alignment.x == 0 and hud_splatter.alignment.y == 0, "Splatter must be centered with alignment 0, 0")
assert(hud_splatter.scale.x <= -100 and hud_splatter.scale.y <= -100, "Splatter scale must cover 100%+ of viewport")
assert(hud_you_died ~= nil, "YOU DIED HUD element not found on death")
assert(hud_you_died.position.y == 0.20, "YOU DIED must be positioned at y=0.20")
assert(hud_cause ~= nil and hud_cause.position.y == 0.33, "Death cause must be positioned at y=0.33")
assert(hud_funny ~= nil and hud_funny.position.y == 0.37, "Humorous quote must be positioned at y=0.37")
print("  [PASS] Death trigger, formspec immobilization, first-person camera orbit, HUD positioning & white text")

-- TEST 7: Anti-ESC, Immediate Formspec Re-show on Quit & Clean TRY AGAIN Button
core.last_formspec = nil
core.on_receive_fields(player1, "deathstats:death", { quit = "true" })

-- Formspec MUST be re-shown IMMEDIATELY without delay to prevent zombie state (#11523)
assert(core.last_formspec ~= nil and core.last_formspec.formname == "deathstats:death", "ESC should immediately re-show death formspec")
assert(core.last_formspec.fs:find("position%[0%.96,0%.88%]"), "Death formspec must be docked to side at position 0.96, 0.88")
assert(core.last_formspec.fs:find("anchor%[1%.00,1%.0%]"), "Death formspec must have right anchor (1.0, 1.0)")
assert(core.last_formspec.fs:find("btn_try_again;TRY AGAIN%]"), "Button must say 'TRY AGAIN' without '(respawn)' text")
assert(not core.last_formspec.fs:find("TRY AGAIN %(RESPAWN%)"), "Button must not contain '(RESPAWN)'")
assert(not core.last_formspec.fs:find("Ores Mined:"), "Ore breakdown must be removed from initial death formspec")
assert(deathstats.dead_players["Alice"] == true, "Alice must remain dead after pressing ESC")
print("  [PASS] Anti-ESC protection, immediate formspec re-show on quit & unobstructed death scene")

-- TEST 8: Transparent Lifetime Modal, Accessible Tabs, 2-Column Grid & Buttons
deathstats.show_lifetime_stats_formspec(player1, "overview")
assert(core.last_formspec.fs:find("bgcolor%[#00000000;both;#00000000%]"), "Lifetime formspec must have transparent backdrop")
assert(core.last_formspec.fs:find("box%[0%.4,0%.2;13%.7,4%.95;#121218f2%]"), "Content card must end at height 4.95 above buttons")
assert(core.last_formspec.fs:find("box%[0%.4,5%.15;13%.7,0%.06;#991111%]"), "Bottom border must frame content at y=5.15 above buttons")
assert(core.last_formspec.fs:find("button%[0%.4,5%.35;5%.0,0%.72;btn_back_death;"), "Back button must be positioned below dark content card")
assert(core.last_formspec.fs:find("button%[9%.1,5%.35;5%.0,0%.72;btn_modal_respawn;"), "Respawn button must be positioned below dark content card")
assert(core.last_formspec.fs:find("border=true;bordercolor=#ff5555"), "Active tab must have distinct accessible border")
assert(core.last_formspec.fs:find("▶ Overview"), "Active tab must have visual indicator")
assert(core.last_formspec.fs:find("style%[btn_back_death;.*border=true"), "Back button must have border")
assert(core.last_formspec.fs:find("btn_modal_respawn;TRY AGAIN%]"), "Modal respawn button must say 'TRY AGAIN'")

-- Test Ores Tab 2-column layout
deathstats.show_lifetime_stats_formspec(player1, "ores")
assert(core.last_formspec.fs:find("Total Ores Extracted:.*varieties"), "Lifetime ores tab must show varieties")
print("  [PASS] Transparent Lifetime Modal, Accessible Tabs, 2-Column Ore Grid & Consistent Buttons")

-- TEST 9: Proper Respawn & Camera Reset to Normal Behaviors
core.on_receive_fields(player1, "deathstats:death", { btn_try_again = "true" })

assert(player1.respawned == true, "Player respawn must be called on Try Again")
assert(deathstats.dead_players["Alice"] == nil, "Alice must be removed from dead_players on respawn")
assert(next(player1.huds) == nil, "Death HUD elements must be cleared on respawn")
assert(player1.camera ~= nil and player1.camera.mode == "first", "Camera must immediately force 'first' person mode on respawn")

-- Execute deferred camera release callback
run_deferred_tasks()
assert(player1.camera.mode == "any", "Camera must be unlocked to 'any' mode after delay so F7 works normally")
print("  [PASS] Respawn mechanics: HUD cleared, camera reset to 1st person then unlocked")

-- TEST 10: Fall Damage Loop Immunity & One-Time Death Guard
player1:set_hp(20)
local data_before = deathstats.get_player_data(player1)
local deaths_before = data_before.lifetime.deaths

-- 1. Player falls and dies
player1:set_hp(0)
deathstats.trigger_death_screen(player1, { type = "fall" })

assert(deathstats.dead_players["Alice"] == true, "Alice must be marked dead")
assert(data_before.lifetime.deaths == deaths_before + 1, "Deaths should increment by exactly 1")

-- 2. Simulate subsequent fall collision damage packets arriving while dead
local dmg_result = core.on_player_hpchange(player1, -50, { type = "fall" })
assert(dmg_result == 0, "Damage while dead must return 0 to suppress damage sounds and damage accumulation")

-- 3. Simulate subsequent engine on_dieplayer / show_death_screen callbacks while dead
core.on_dieplayer(player1, { type = "fall" })
core.show_death_screen(player1, { type = "fall" })

assert(data_before.lifetime.deaths == deaths_before + 1, "Deaths must NOT increment in a loop from repeated engine callbacks")

-- 4. Respawn and verify clean state
core.on_respawnplayer(player1)
assert(deathstats.dead_players["Alice"] == nil, "Player must not be marked dead after respawn")
print("  [PASS] Fall damage loop immunity, one-time death guard & damage sound suppression")

-- TEST 11: Bones Mod Camera Targeting & Delayed Placement Tracking
-- Case A: Bones placed prior to deathstats hook (standard execution order via optional_depends = bones)
local bones_loc = { x = 10, y = 5, z = 10 }
core.set_node(bones_loc, { name = "bones:bones" })
player1:set_pos(bones_loc)
player1:set_hp(0)

deathstats.trigger_death_screen(player1, { type = "punch" })

assert(deathstats.dead_players["Alice"] == true, "Alice must be dead")
local cam_data = deathstats.player_camera_data["Alice"]
assert(cam_data ~= nil and cam_data.has_bones == true, "Camera must detect bones block")
assert(player1.camera ~= nil and player1.camera.mode == "first", "Camera mode must be 'first' when looking at bones")
assert(player1.look_vertical > 0, "Camera look_vertical must be tilted downwards (>0) directly toward the bones")
assert(player1:get_attach() ~= nil, "Player must be attached to camera anchor")
local ppos = player1:get_pos()
local dist_to_bones = vector.distance(ppos, bones_loc)
assert(dist_to_bones < 0.5, "Anchor must be stationed at bones node center")

-- Test globalstep maintains yaw & pitch while pointing at bones
player1:set_look_vertical(0)
core.on_globalstep(0.1)
assert(player1.look_vertical == cam_data.pitch, "Globalstep must maintain camera pitch pointing at bones")
assert(player1.look_horizontal == cam_data.yaw, "Globalstep must maintain camera yaw pointing at bones")

-- Respawn resets camera data
core.on_respawnplayer(player1)
assert(deathstats.player_camera_data["Alice"] == nil, "Camera data must be cleared on respawn")

-- Case B: Bones placed delayed (e.g. on subsequent tick)
core.world_nodes = {}
local late_loc = { x = 20, y = 5, z = 20 }
player1:set_pos(late_loc)
player1:set_hp(0)

deathstats.trigger_death_screen(player1, { type = "punch" })
assert(deathstats.player_camera_data["Alice"].has_bones == false, "Initially no bones placed")
assert(player1.camera.mode == "first", "Always defaults to first mode for orbit")

-- Simulate bones mod placing bones node on subsequent tick
core.set_node(late_loc, { name = "bones:bones" })
core.on_globalstep(0.1)

local late_cam = deathstats.player_camera_data["Alice"]
assert(late_cam ~= nil and late_cam.has_bones == true, "Globalstep must detect delayed bones placement")
assert(player1.camera.mode == "first", "Delayed bones detection maintains first mode")
assert(player1.look_vertical > 0, "Delayed bones detection must orient camera downward at bones")

core.on_respawnplayer(player1)
core.world_nodes = {}
print("  [PASS] Bones camera targeting: open-space anchoring, direct aim & delayed placement detection")

-- TEST 13: Player Join HP Check & Death Screen Recovery (aligning with Luanti builtin/game/death_screen.lua)
-- Case A: Player joins with HP > 0 (alive): cleans up any stale death effects, camera, and HUDs
deathstats.dead_players["Alice"] = true
deathstats.player_camera_data["Alice"] = { has_bones = true }
deathstats.active_animations["Alice"] = { elapsed = 0.5 }
player1.hud_flags.crosshair = false
player1.hud_flags.hotbar = false
player1:set_hp(20)

core.on_joinplayer(player1)
assert(deathstats.dead_players["Alice"] == nil, "Joinplayer with HP > 0 must clear dead_players")
assert(deathstats.player_camera_data["Alice"] == nil, "Joinplayer with HP > 0 must clear camera data")
assert(deathstats.active_animations["Alice"] == nil, "Joinplayer with HP > 0 must clear active animations")
assert(player1.hud_flags.crosshair == true, "Joinplayer must restore crosshair HUD")
assert(player1.hud_flags.hotbar == true, "Joinplayer must restore hotbar HUD")
local expected_hb = not (deathstats.compat_hudbars and deathstats.compat_hudbars.manages_healthbar and deathstats.compat_hudbars.manages_healthbar())
assert(player1.hud_flags.healthbar == expected_hb, "Joinplayer must set healthbar HUD according to hudbars presence")

-- Case B: Player joins with HP == 0 (dead on join): triggers death screen immediately
core.last_formspec = nil
deathstats.dead_players["Alice"] = nil
player1:set_hp(0)
core.on_joinplayer(player1)
assert(deathstats.dead_players["Alice"] == true, "Joinplayer with HP == 0 must trigger death screen")
assert(core.last_formspec ~= nil and core.last_formspec.formname == "deathstats:death", "Joinplayer with HP == 0 must show death formspec immediately")

-- Case C: Player leaves while dead: saves stats and cleans up in-memory effects
core.on_leaveplayer(player1)
assert(deathstats.dead_players["Alice"] == nil, "Leaveplayer must clean up in-memory effects")

-- Case D: In-place revival / healing while dead (on_player_hpchange with hp_change > 0)
deathstats.dead_players["Alice"] = true

local change_result = core.on_player_hpchange(player1, 10, { type = "heal" })
assert(change_result == 10, "Healing hpchange must not be suppressed")
assert(deathstats.dead_players["Alice"] == nil, "Healing while dead must immediately clear dead_players")

-- Case E: Globalstep dead-player recovery (if external mod calls set_hp without hpchange hook)
deathstats.dead_players["Alice"] = true
player1:set_hp(20)
core.on_globalstep(0.1)
assert(deathstats.dead_players["Alice"] == nil, "Globalstep must auto-clear dead_players when HP > 0")

-- Case F: Centralized deathstats.reset_player_effects direct invocation
deathstats.dead_players["Alice"] = true
deathstats.reset_player_effects(player1)
assert(deathstats.dead_players["Alice"] == nil, "reset_player_effects must clear dead_players")

print("  [PASS] Player join HP check, death screen recovery & comprehensive effect reset (Luanti #11523 compliant)")

-- TEST 14: Engine Death Screen Override & Delegate
assert(type(core.show_death_screen) == "function", "core.show_death_screen must be defined and overridden")
if minetest then
    assert(type(minetest.show_death_screen) == "function", "minetest.show_death_screen must be synchronized")
end
local test_reason = { type = "fall" }
core.show_death_screen(player1, test_reason)
assert(deathstats.dead_players["Alice"] == true, "show_death_screen must register player in dead_players")
local t14_pdata = deathstats.get_player_data(player1)
assert(t14_pdata and t14_pdata.last_life.last_cause == "Fell from a high place", "show_death_screen must analyze and record fall death in last_life")
assert(core.last_formspec ~= nil, "show_death_screen must display death formspec")
deathstats.reset_player_effects(player1)
assert(deathstats.dead_players["Alice"] == nil, "reset_player_effects must clear dead_players")
print("  [PASS] Engine death screen override (core.show_death_screen)")

-- TEST 15: Responsive Banner Aspect Ratio Preservation Across Screen Sizes
local expected_tex_aspect = 1376 / 558

local test_screens = {
    { name = "16:9 Widescreen (1080p)", w = 1920, h = 1080 },
    { name = "16:9 Widescreen (1440p)", w = 2560, h = 1440 },
    { name = "16:9 4K UHD", w = 3840, h = 2160 },
    { name = "16:10 MacBook / Laptop", w = 1920, h = 1200 },
    { name = "16:10 MacBook Retina", w = 2880, h = 1800 },
    { name = "21:9 Ultrawide", w = 2560, h = 1080 },
    { name = "32:9 Super Ultrawide", w = 5120, h = 1440 },
    { name = "4:3 Standard Display", w = 1024, h = 768 },
    { name = "Steam Deck (1280x800)", w = 1280, h = 800 },
    { name = "Mobile Portrait (1080x1920)", w = 1080, h = 1920 },
}

for _, scr in ipairs(test_screens) do
    core.get_player_window_information = function(pname)
        return { size = { x = scr.w, y = scr.h } }
    end
    local sx, sy = deathstats.get_banner_responsive_scale(player1)
    assert(sx < 0 and sy < 0, "Scale values must be negative percentages")
    -- In Minetest, sx and sy are percentages of screen width and screen height
    local rendered_w = (-sx / 100) * scr.w
    local rendered_h = (-sy / 100) * scr.h
    local rendered_aspect = rendered_w / rendered_h
    local aspect_diff = math.abs(rendered_aspect - expected_tex_aspect)
    assert(aspect_diff < 0.01, string.format("Aspect ratio mismatch for %s: rendered %.4f vs expected %.4f",
        scr.name, rendered_aspect, expected_tex_aspect))
end

-- Verify graceful fallback when get_player_window_information is not supported
core.get_player_window_information = nil
local def_sx, def_sy = deathstats.get_banner_responsive_scale(player1)
local def_rendered_aspect = (-def_sx * 16) / (-def_sy * 9)
assert(math.abs(def_rendered_aspect - expected_tex_aspect) < 0.01, "Fallback must preserve 16:9 aspect ratio")
print("  [PASS] Responsive banner scaling & aspect ratio preservation across screen resolutions")

-- TEST 16: Unified API Architecture & Upstream Method Availability
local expected_methods = {
    "truncate_str",
    "create_empty_stats",
    "format_time",
    "format_number",
    "format_name",
    "play_death_sound",
    "format_projectile_name",
    "resolve_puncher_player",
    "load_player_stats",
    "save_player_stats",
    "get_player_data",
    "record_player_death",
    "get_funny_note",
    "resolve_entity_info",
    "inspect_surroundings_fallback",
    "analyze_death",
    "find_player_bones",
    "find_ground_surface",
    "is_liquid_at",
    "is_in_liquid",
    "aim_camera_at_bones",
    "set_death_camera",
    "reset_camera",
    "clear_death_hud",
    "reset_player_effects",
    "get_banner_responsive_scale",
    "trigger_death_screen",
    "respawn_player",
    "on_player_respawn",
    "show_death_formspec",
    "show_lifetime_stats_formspec",
    "show_lifetime_formspec",
    "rotate_corpse_bone",
    "rotate_corpse_bone_planar",
    "fracture_corpse_limbs",
    "is_player_online",
    "zero_player_velocity",
    "restore_player_inventory_and_hand",
    "is_inventory_list_empty",
    "serialize_inventory_list",
    "deserialize_inventory_list",
    "is_player_starving",
}

for _, method_name in ipairs(expected_methods) do
    assert(type(deathstats[method_name]) == "function",
        string.format("deathstats.%s must be defined as a function in api.lua", method_name))
end

local expected_tables = {
    "config",
    "colors",
    "active_huds",
    "active_animations",
    "dead_players",
    "player_camera_data",
    "is_respawning",
    "players",
    "recent_punches",
    "recent_falls",
    "recent_starvations",
    "funny_notes",
}

for _, table_name in ipairs(expected_tables) do
    assert(type(deathstats[table_name]) == "table",
        string.format("deathstats.%s must be defined as a table in api.lua", table_name))
end

-- Validate common color tokens exist in deathstats.colors
assert(deathstats.colors.transparent == "#00000000", "transparent color token must exist")
assert(deathstats.colors.crimson_border == "#991111", "crimson_border color token must exist")
assert(deathstats.colors.tab_active_bg == "#a81818", "tab_active_bg color token must exist")
assert(deathstats.colors.btn_primary_bg == "#881111", "btn_primary_bg color token must exist")
assert(deathstats.colors.hud_white == 0xFFFFFF, "hud_white color token must exist")

print("  [PASS] Unified API: all methods, state variables & colors map defined upstream in api.lua")

-- TEST 17: Funny Notes Expansion (5x quotes, translatable S(), void category removed)
assert(deathstats.funny_notes.void == nil, "void category must be removed from funny_notes")

local expected_categories = {
    pvp = 35,
    mob = 35,
    fall = 35,
    lava = 30,
    fire = 25,
    drown = 25,
    suffocate = 25,
    starve = 25,
    unknown = 30,
}

local total_quotes = 0
for cat, min_count in pairs(expected_categories) do
    local list = deathstats.funny_notes[cat]
    assert(type(list) == "table", string.format("Category '%s' must exist in deathstats.funny_notes", cat))
    assert(#list >= min_count, string.format("Category '%s' has %d quotes, expected at least %d", cat, #list, min_count))
    for i, note in ipairs(list) do
        assert(type(note) == "string" and note ~= "", string.format("Quote %d in category '%s' must be non-empty string", i, cat))
    end
    total_quotes = total_quotes + #list
end

assert(total_quotes >= 260, string.format("Expected at least 260 total quotes, got %d", total_quotes))
print(string.format("  [PASS] Funny notes: void removed, %d translatable quotes across 9 categories (5x expansion)", total_quotes))

-- TEST 18: Reconnect Death Recovery & Single Death Recording Guard
local recon_data = deathstats.get_player_data(player1)
recon_data.last_life.last_cause = "Slain by Zombie King"
recon_data.last_life.last_weapon = "Dark Blade"
recon_data.last_life.last_killer = "Zombie King"
recon_data.last_life.last_funny = "A royal execution."
local deaths_before_reconnect = recon_data.lifetime.deaths

-- Player joins dead (reconnect scenario)
player1:set_hp(0)
deathstats.dead_players["Alice"] = nil
core.on_joinplayer(player1)

assert(deathstats.dead_players["Alice"] == true, "Reconnecting dead player must be marked dead")
assert(recon_data.lifetime.deaths == deaths_before_reconnect,
    "Reconnect while dead must NOT increment lifetime.deaths counter")
assert(core.last_formspec ~= nil and core.last_formspec.formname == "deathstats:death",
    "Death formspec must be presented on dead player reconnect")
deathstats.reset_player_effects(player1)
player1:set_hp(20)
print("  [PASS] Reconnect death screen recovery: stats preserved & death count deduplicated")

-- TEST 19: Formspec Colorization & Parameter Substitution Verification
deathstats.show_death_formspec(player1, {
    category = "mob",
    reason_text = "Slain by Zombie King",
    funny_note = "A royal execution.",
})
assert(core.last_formspec ~= nil, "Death formspec must be shown")
assert(core.last_formspec.fs:find("\27%(c@"), "Death formspec must use core.colorize escape sequences for styled labels")
assert(not core.last_formspec.fs:find("style%[lbl_"), "Death formspec must not use non-functional style[lbl_ identifiers")

deathstats.show_lifetime_stats_formspec(player1, "overview")
assert(core.last_formspec ~= nil, "Lifetime formspec must be shown")
assert(core.last_formspec.fs:find("\27%(c@"), "Lifetime formspec must use core.colorize escape sequences for styled labels")
assert(not core.last_formspec.fs:find("style%[lbl_"), "Lifetime formspec must not use non-functional style[lbl_ identifiers")
print("  [PASS] Formspec colorization: core.colorize applied & non-functional style[lbl_ eliminated")

-- TEST 20: Camera Look Packet Throttling & Globalstep Idle Fast Exit
-- 1. Idle fast-exit: no dead players and no animations
deathstats.dead_players = {}
deathstats.active_animations = {}
core.on_globalstep(0.1) -- Must return without error or side effects

-- 2. Look orientation packet throttling
deathstats.dead_players["Alice"] = true
player1.hp = 0
deathstats.player_camera_data["Alice"] = { has_bones = true, yaw = 1.5, pitch = 0.5 }
player1.look_horizontal = 1.52 -- drift = 0.02 (<= 0.05 threshold)
player1.look_vertical = 0.52   -- drift = 0.02 (<= 0.05 threshold)

local yaw_packet_sent = false
local pitch_packet_sent = false
local orig_set_yaw = player1.set_look_horizontal
local orig_set_pitch = player1.set_look_vertical

player1.set_look_horizontal = function(self, h)
    yaw_packet_sent = true
    orig_set_yaw(self, h)
end
player1.set_look_vertical = function(self, v)
    pitch_packet_sent = true
    orig_set_pitch(self, v)
end

core.on_globalstep(0.016)
assert(not yaw_packet_sent, "Camera yaw packet must NOT be sent when orientation drift is <= 0.05 rad")
assert(not pitch_packet_sent, "Camera pitch packet must NOT be sent when orientation drift is <= 0.05 rad")

-- Now drift is significant (drift = 0.20 > 0.05 threshold)
player1.look_horizontal = 1.70
player1.look_vertical = 0.70
core.on_globalstep(0.016)
assert(yaw_packet_sent, "Camera yaw packet must be sent when orientation drift exceeds 0.05 rad")
assert(pitch_packet_sent, "Camera pitch packet must be sent when orientation drift exceeds 0.05 rad")

player1.set_look_horizontal = orig_set_yaw
player1.set_look_vertical = orig_set_pitch
deathstats.reset_player_effects(player1)
player1:set_hp(20)
print("  [PASS] Camera look packet throttling & globalstep fast-exit optimization")

-- TEST 21: Dynamic Scrollable Tabs (Ores & Combat) & Damage Label Clarity
-- 1. Verify death formspec damage label clarity
deathstats.show_death_formspec(player1, { reason_text = "Fell from a high place" })
assert(core.last_formspec ~= nil, "Death formspec must be rendered")
assert(core.last_formspec.fs:find("Damage:.*dealt.*taken"), "Short stats must indicate 'dealt' and 'taken' for damage")

-- 2. Verify scroll_container and scrollbar on Ores tab with 16 distinct ores (> 12 items / 8 rows)
local pdata22 = deathstats.get_player_data(player1)
pdata22.lifetime.ores_mined = {}
for i = 1, 16 do
    local ore_id = string.format("default:mineral_%02d", i)
    pdata22.lifetime.ores_mined[ore_id] = i * 10
end
pdata22.lifetime.total_ores = 1360

deathstats.show_lifetime_stats_formspec(player1, "ores")
assert(core.last_formspec ~= nil, "Lifetime ores formspec must be rendered")
assert(core.last_formspec.fs:find("scroll_container%[0%.8,2%.18;12%.40,2%.80;ore_scroll;vertical;0%.1;0%.1%]"),
    "Ores tab must use scroll_container when content exceeds 5 rows")
assert(core.last_formspec.fs:find("scrollbaroptions%[min=0;max="),
    "Ores scrollbar must configure scrollbaroptions")
assert(core.last_formspec.fs:find("scrollbar%[13%.35,2%.18;0%.28,2%.80;vertical;ore_scroll;0%]"),
    "Ores scrollbar must be positioned beside the scroll container")
for i = 1, 16 do
    local ore_id = string.format("default:mineral_%02d", i)
    assert(core.last_formspec.fs:find(ore_id, 1, true),
        string.format("All 16 ores must be rendered without truncation (missing %s)", ore_id))
end

-- 3. Verify JohnnyBravo case (12 ores = 6 rows) activates scrollbar
pdata22.lifetime.ores_mined = {}
for i = 1, 12 do
    pdata22.lifetime.ores_mined[string.format("default:ore_%02d", i)] = 1
end
deathstats.show_lifetime_stats_formspec(player1, "ores")
assert(core.last_formspec.fs:find("scrollbar%[13%.35,2%.18;0%.28,2%.80;vertical;ore_scroll;0%]"),
    "6 rows (12 items) must activate scrollbar for JohnnyBravo")

-- 4. Verify small list (<= 5 rows / 10 items) uses standard container without scrollbar
pdata22.lifetime.ores_mined = {}
for i = 1, 6 do
    pdata22.lifetime.ores_mined[string.format("default:small_ore_%02d", i)] = 1
end
deathstats.show_lifetime_stats_formspec(player1, "ores")
assert(core.last_formspec.fs:find("container%[0%.8,2%.18%]"),
    "Small list must use standard container")
assert(not core.last_formspec.fs:find("scrollbar%["),
    "Small list must NOT have a scrollbar")

-- 5. Verify scroll_container and scrollbar on Combat tab with 16 distinct mob types
pdata22.lifetime.mobs_slain = {}
for i = 1, 16 do
    local mob_id = string.format("mobs:creature_%02d", i)
    pdata22.lifetime.mobs_slain[mob_id] = i * 5
end
pdata22.lifetime.mobs_killed = 680

deathstats.show_lifetime_stats_formspec(player1, "combat")
assert(core.last_formspec ~= nil, "Lifetime combat formspec must be rendered")
assert(core.last_formspec.fs:find("scroll_container%[0%.8,2%.18;12%.40,2%.80;combat_scroll;vertical;0%.1;0%.1%]"),
    "Combat tab must use scroll_container when content exceeds 5 rows")
assert(core.last_formspec.fs:find("scrollbaroptions%[min=0;max="),
    "Combat scrollbar must configure scrollbaroptions")
assert(core.last_formspec.fs:find("scrollbar%[13%.35,2%.18;0%.28,2%.80;vertical;combat_scroll;0%]"),
    "Combat scrollbar must be positioned beside the scroll container")
for i = 1, 16 do
    local mob_id = string.format("mobs:creature_%02d", i)
    local mob_title = deathstats.format_name(mob_id)
    assert(core.last_formspec.fs:find(mob_title, 1, true),
        string.format("All 16 mobs must be rendered without truncation (missing %s)", mob_title))
end

deathstats.reset_player_effects(player1)
print("  [PASS] Dynamic scrollable tabs (all ores & mobs browsable) & short stats damage clarity")

-- TEST 22: Cinematic Camera Orbit Geometry, Obstacle Raycasting & Cleanup
local p_orbit = create_mock_player("OrbitPlayer")
p_orbit:set_pos({ x = 40, y = 10, z = 40 })
p_orbit:set_hp(0)

core.spawned_entities = {}
deathstats.set_death_camera(p_orbit)

-- 1. Verify player ghosting, first camera mode, and stationary anchor attachment
assert(p_orbit.camera ~= nil and p_orbit.camera.mode == "first", "Player camera must be set to 'first' during deathcam")
assert(p_orbit.eye_offset ~= nil and p_orbit.eye_offset[1].z < 0, "Eye offset must project backwards in first-person mode")
assert(p_orbit.properties.visual_size.x == 0, "Player ghost must have visual_size 0")
assert(p_orbit.properties.interaction_range == 0, "Player interaction_range must be 0")
assert(p_orbit.physics_override.speed == 0, "Player speed must be frozen to 0")
assert(p_orbit:get_attach() ~= nil, "Player must be attached to camera anchor entity")

local cam_data22 = deathstats.player_camera_data["OrbitPlayer"]
assert(cam_data22 ~= nil, "Camera data must be initialized")
assert(cam_data22.corpse ~= nil, "Corpse entity must be spawned")
assert(cam_data22.anchor ~= nil, "Anchor entity must be spawned")
assert(cam_data22.orbit_center.x == 40 and cam_data22.orbit_center.z == 40, "Orbit center must match death pos")

-- 2. Verify smooth orbit circle progression and yaw rotation
local initial_angle = cam_data22.orbit_angle
deathstats.update_death_camera(p_orbit, 1.0)
local expected_angle = (initial_angle + cam_data22.orbit_speed * 1.0) % (2 * math.pi)
assert(math.abs(cam_data22.orbit_angle - expected_angle) < 0.001, "Orbit angle must advance smoothly by speed * dtime")
assert(math.abs(p_orbit.look_horizontal - expected_angle) < 0.001, "Player yaw must rotate smoothly with orbit angle")

-- 3. Verify stationary base positioning (bypasses packet fights and horizontal jitter)
assert(vector.distance(p_orbit:get_pos(), cam_data22.orbit_center) < 0.001, "Player and anchor remain stationary at orbit center")

-- 4. Verify downward pitch pointing directly at corpse
assert(p_orbit.look_vertical > 0, "Camera must tilt downward (> 0) toward corpse")

-- 4b. Verify continuous obstacle avoidance, proportional height scaling & hold-timer hysteresis
local orig_raycast = core.raycast
local obstacle_detected = true
core.set_node({ x = 42, y = 11, z = 40 }, { name = "default:stone" })
core.raycast = function()
    if not obstacle_detected then
        return function() return nil end
    end
    local called = false
    return function()
        if not called then
            called = true
            return {
                type = "node",
                under = { x = 42, y = 11, z = 40 },
                intersection_point = { x = 42.0, y = 11.0, z = 40.0 },
            }
        end
        return nil
    end
end

-- Run multiple steps with obstacle present: camera must pull in smoothly and prime hold timer
for _ = 1, 15 do
    deathstats.update_death_camera(p_orbit, 0.05)
end
assert(cam_data22.eff_radius < 3.0, "Camera eff_radius must decrease smoothly when obstacle is detected")
assert(cam_data22.obstacle_hold_timer == 0.5, "Obstacle hold timer must be primed to 0.5s when obstacle is active")
assert(p_orbit.eye_offset[1].y < 15, "Eye offset Y must scale down proportionally with eff_radius (proportional height)")
local contracted_radius = cam_data22.eff_radius

-- Clear the obstacle: verify hold-timer prevents immediate accordion expansion over transient gaps
obstacle_detected = false
deathstats.update_death_camera(p_orbit, 0.1)
assert(cam_data22.obstacle_hold_timer > 0, "Hold timer must be counting down while gap is present")
assert(cam_data22.eff_radius <= contracted_radius + 0.05, "Camera must not bounce outward while hold timer is active")

-- Advance past hold duration: camera must smoothly ease back out towards nominal radius
for _ = 1, 25 do
    deathstats.update_death_camera(p_orbit, 0.1)
end
assert(cam_data22.eff_radius > contracted_radius, "Camera must smoothly ease out towards nominal radius after hold expires")
assert(cam_data22.eff_radius <= 3.2, "Camera must not overshoot nominal radius")
core.raycast = orig_raycast

-- 5. Verify reset_camera restores properties, unlocks camera mode, detaches player, and removes corpse & anchor
local corpse_ref = cam_data22.corpse
local anchor_ref = cam_data22.anchor
deathstats.reset_camera(p_orbit)
assert(corpse_ref.removed == true, "Corpse entity must be removed on reset_camera")
assert(anchor_ref.removed == true, "Anchor entity must be removed on reset_camera")
assert(cam_data22.corpse == nil, "Corpse reference in camera data must be nil after reset")
assert(cam_data22.anchor == nil, "Anchor reference in camera data must be nil after reset")
assert(p_orbit:get_attach() == nil, "Player must be detached on reset_camera")
assert(p_orbit.camera.mode == "first", "Camera mode must be set to 'first' on reset_camera")
run_deferred_tasks()
assert(p_orbit.camera.mode == "any", "Camera mode must be unlocked to 'any' after deferred delay")
assert(p_orbit.properties.visual_size.x == 1, "Player visual_size must be restored on reset_camera")
assert(p_orbit.properties.interaction_range == 4, "Player interaction_range must be restored")
assert(p_orbit.physics_override.speed == 1, "Player physics_override must be restored")
print("  [PASS] Cinematic Camera Orbit Geometry, Obstacle Raycasting & Cleanup")

-- TEST 23: Multi-Skin Mod Compatibility & Visual Extraction
local p_skin = create_mock_player("SkinUser")

-- 1. Default fallback
local vis_default = deathstats.get_player_visuals(p_skin)
assert(vis_default.mesh == "character.b3d", "Default mesh must be character.b3d")
assert(vis_default.textures[1] == "character.png", "Default texture must be character.png")

-- 2. 3d_armor compatibility
rawset(_G, "armor", {
    textures = { ["SkinUser"] = { skin = "armor_skin.png", armor = "armor_chest.png", wielditem = "armor_sword.png" } },
    models = { ["SkinUser"] = "3d_armor_character.b3d" },
})
local vis_armor = deathstats.get_player_visuals(p_skin)
assert(vis_armor.mesh == "3d_armor_character.b3d", "3d_armor mesh must be inherited")
assert(vis_armor.textures[1] == "armor_skin.png", "3d_armor skin texture must be inherited")
assert(vis_armor.textures[2] == "armor_chest.png", "3d_armor armor texture must be inherited")
assert(vis_armor.textures[3] == "armor_sword.png", "3d_armor wielditem texture must be inherited")
rawset(_G, "armor", nil)

-- 3. skinsdb compatibility
rawset(_G, "skins", {
    get_player_skin = function(p)
        return {
            get_texture = function() return "skinsdb_custom_texture.png" end,
            get_meta = function(self, k)
                if k == "visual_size_x" then return "1.15" end
                if k == "visual_size_y" then return "1.15" end
                return nil
            end,
        }
    end,
})
local vis_skinsdb = deathstats.get_player_visuals(p_skin)
assert(vis_skinsdb.textures[1] == "skinsdb_custom_texture.png", "skinsdb custom texture must be inherited")
assert(vis_skinsdb.visual_size.x == 1.15, "skinsdb visual size must be inherited")
rawset(_G, "skins", nil)

-- 4. simple_skins compatibility
rawset(_G, "skins", {
    skins = { ["SkinUser"] = "character_warrior" },
})
local vis_simple = deathstats.get_player_visuals(p_skin)
assert(vis_simple.textures[1] == "character_warrior.png", "simple_skins texture must be inherited")
rawset(_G, "skins", nil)

-- 5. wardrobe compatibility
rawset(_G, "wardrobe", {
    playerSkins = { ["SkinUser"] = "wardrobe_robe.png" },
})
local vis_wardrobe = deathstats.get_player_visuals(p_skin)
assert(vis_wardrobe.textures[1] == "wardrobe_robe.png", "wardrobe texture must be inherited")
rawset(_G, "wardrobe", nil)

-- 6. clothing compatibility (layers on top of base skin)
rawset(_G, "clothing", {
    player_textures = { ["SkinUser"] = { clothing = "jeans_blue.png", cape = "cape_velvet.png" } },
})
local vis_clothing = deathstats.get_player_visuals(p_skin)
assert(vis_clothing.textures[1]:find("jeans_blue%.png"), "clothing texture layer must be appended")
assert(vis_clothing.textures[1]:find("cape_velvet%.png"), "clothing cape texture layer must be appended")
rawset(_G, "clothing", nil)

-- 7. Corpse entity activation & posing
local mock_corpse = {
    props = {},
    anim = nil,
    set_properties = function(self, pr) self.props = pr end,
    set_animation = function(self, range, speed, blend, loop)
        self.anim = { range = range, speed = speed, blend = blend, loop = loop }
    end,
    set_rotation = function(self, rot) self.rot = rot end,
    set_yaw = function(self, yaw) self.yaw = yaw end,
}
deathstats.pose_corpse(mock_corpse, "character.b3d")
assert(mock_corpse.anim ~= nil, "Corpse entity must receive animation")
assert(mock_corpse.anim.range.x == 166 and mock_corpse.anim.range.y == 166, "Corpse entity must be frozen flat on frame 166")
assert(mock_corpse.anim.speed == 1 and mock_corpse.anim.loop == false, "Corpse entity must have speed=1 and loop=false to lock flat pose in Irrlicht")
print("  [PASS] Multi-Skin Mod Compatibility & Corpse Appearance Inheritance")

-- TEST 24: Luanti Out-of-the-Box Drops & Bones Preservation (Zero Inventory Interference)
local p_drop = create_mock_player("DropTester")
p_drop:set_pos({ x = 10, y = 5, z = 10 })
p_drop:set_hp(0)

-- Populate player inventory before death
p_drop.inventory.lists["main"] = {
    rawget(_G, "ItemStack")("default:dirt 64"),
    rawget(_G, "ItemStack")("default:pick_diamond 1"),
}
p_drop.inventory.lists["craft"] = {
    rawget(_G, "ItemStack")("default:stick 4"),
}

core.spawned_items = {}
deathstats.set_death_camera(p_drop)

-- Verify that deathstats did NOT drop or scatter items itself, leaving them for the game / mods
assert(#core.spawned_items == 0, "deathstats must not drop item entities itself")
assert(#p_drop.inventory.lists["main"] == 2, "Main inventory must remain intact for game/mods")
assert(#p_drop.inventory.lists["craft"] == 1, "Craft inventory must remain intact for game/mods")
assert(p_drop.inventory.lists["main"][1]:get_name() == "default:dirt", "Items in main inventory must not be modified")

print("  [PASS] Luanti Out-of-the-Box Drops & Bones Preservation (Zero Inventory Interference)")

-- TEST 25: Death Animation Loop Prevention & Corpse Freeze Lock
local p_anim = create_mock_player("AnimTester")
p_anim.current_anim = nil

-- 1. Normal state: animations set as requested
player_api.set_animation(p_anim, "walk", 30, true)
assert(p_anim.current_anim.anim == "walk" and p_anim.current_anim.loop == true, "Normal animation should apply with loop=true")

-- 2. Mark player dead in deathstats
deathstats.dead_players["AnimTester"] = true

-- 3. Lay animation must be forced to loop=false and speed=1
player_api.set_animation(p_anim, "lay")
assert(p_anim.current_anim.anim == "lay", "Lay animation should be set")
assert(p_anim.current_anim.loop == false, "Death animation MUST force loop=false to prevent jiggling/dying loop")
assert(p_anim.current_anim.speed == 1, "Death animation MUST have non-zero speed=1 to hold final flat frame")

-- 4. Non-death animations while dead must be suppressed
player_api.set_animation(p_anim, "walk", 30, true)
assert(p_anim.current_anim.anim == "lay", "Non-death animations must be blocked while dead")

-- Clean up
deathstats.dead_players["AnimTester"] = nil
print("  [PASS] Death Animation Loop Prevention & Corpse Freeze Lock")

-- TEST 26: Post-Respawn Fall Damage Immunity & Full HP (1 Heart Bug Fix)
local p_fall = create_mock_player("FallRespawnTester")
p_fall.hp = 0
p_fall.velocity = { x = 0, y = -38, z = 0 } -- downward fall velocity

-- Trigger death sequence
deathstats.trigger_death_screen(p_fall, { type = "fall" })
assert(p_fall.velocity.x == 0 and p_fall.velocity.y == 0 and p_fall.velocity.z == 0, "Player velocity must be zeroed on death")
assert(p_fall.properties.is_visible == false, "Player must be invisible during death sequence")

-- Respawn player
deathstats.respawn_player(p_fall)
assert(p_fall.properties.is_visible == true, "Player visibility must be restored on respawn")
assert(p_fall.velocity.x == 0 and p_fall.velocity.y == 0 and p_fall.velocity.z == 0, "Player velocity must be zeroed on respawn")
assert(p_fall:get_hp() == 20, "Player must respawn with full health (20 HP)")
assert(deathstats.respawn_immunity["FallRespawnTester"] ~= nil, "Respawn immunity must be active")
assert(deathstats.respawn_immunity["FallRespawnTester"] > core.get_gametime(), "Immunity timestamp must be in future")

-- Simulate delayed fall damage packet arriving immediately after respawn (the 1-heart bug)
local delayed_fall_damage = core.on_player_hpchange(p_fall, -18, { type = "fall" })
assert(delayed_fall_damage == 0, "Delayed fall damage packet must be suppressed (return 0) during immunity window")
assert(p_fall:get_hp() == 20, "Player must retain full 20 HP / 10 hearts (not reduced to 2 HP / 1 heart)")

-- Simulate delayed nil reason packet from engine collision
local delayed_nil_damage = core.on_player_hpchange(p_fall, -18, nil)
assert(delayed_nil_damage == 0, "Delayed nil-reason fall damage must be suppressed during immunity window")
assert(p_fall:get_hp() == 20, "Player must retain full 20 HP")

-- Simulate immunity expiry after 2.5 seconds
local old_gametime = core.get_gametime
core.get_gametime = function() return 1005 end -- > 1000 + 2.0
local legit_damage = core.on_player_hpchange(p_fall, -4, { type = "punch" })
assert(legit_damage == -4, "Legitimate damage after immunity expiry must be processed normally")
p_fall:set_hp(p_fall:get_hp() + legit_damage)
assert(p_fall:get_hp() == 16, "HP should decrease after legitimate damage post-immunity")
core.get_gametime = old_gametime

-- Clean up
deathstats.respawn_immunity["FallRespawnTester"] = nil
print("  [PASS] Post-Respawn Fall Damage Immunity & Full HP (1 Heart Bug Fix)")

-- ==========================================================
-- TEST 27: Ground Surface Detection & Corpse Ground Snapping
-- ==========================================================
-- 1. Direct bones detection snaps to bones.y + 0.5
local snap_bones_pos = { x = 10, y = 3, z = 10 }
local surface_bones = deathstats.find_ground_surface({ x = 10, y = 20, z = 10 }, snap_bones_pos)
assert(surface_bones == 3.5, "find_ground_surface must return bones_pos.y + 0.5")

-- 2. Fall death in mid-air (player at y = 35) above walkable ground at y = 4 (surface at 4.5)
core.registered_nodes["default:dirt_with_grass"] = { walkable = true, drawtype = "normal" }
core.world_nodes["15,4,15"] = { name = "default:dirt_with_grass" }
core.world_nodes["15,5,15"] = { name = "air" }

local surface_ground = deathstats.find_ground_surface({ x = 15, y = 35, z = 15 }, nil)
assert(surface_ground == 4.5, "find_ground_surface must detect ground at y = 4.5 from falling position at y = 35")

-- 3. Raycast-based ground detection (e.g. slab with intersection_point at 4.625)
local prev_ray = core.raycast
core.raycast = function(p1, p2, objects, liquids)
    local called = false
    return function()
        if not called then
            called = true
            return {
                type = "node",
                under = { x = 15, y = 4, z = 15 },
                intersection_point = { x = 15, y = 4.625, z = 15 },
            }
        end
        return nil
    end
end
local surface_ray = deathstats.find_ground_surface({ x = 15, y = 35, z = 15 }, nil)
assert(surface_ray == 4.625, "find_ground_surface must return exact intersection_point.y from core.raycast")
core.raycast = prev_ray

-- 4. Corpse placed via set_death_camera must rest directly on the ground, not in mid-air
local p_cliff = create_mock_player("CliffJumper")
p_cliff:set_pos({ x = 15, y = 35, z = 15 })
p_cliff:set_hp(0)
deathstats.set_death_camera(p_cliff)

local cliff_cam = deathstats.player_camera_data["CliffJumper"]
assert(cliff_cam ~= nil, "Camera data must be initialized for high-fall death")
assert(cliff_cam.corpse ~= nil, "Corpse must be spawned")
local corpse_y = cliff_cam.corpse:get_pos().y
assert(corpse_y == 4.5, "Corpse must rest flush on ground at y = 4.5, NOT floating at y = 35!")
assert(cliff_cam.orbit_center.y == 4.5, "Orbit center must be aligned with ground surface at y = 4.5")
deathstats.reset_camera(p_cliff)

-- 5. Water Death: Player dying in deep lake must stay static at exact place of death (Luanti out-of-the-box behavior)
core.world_nodes["20,2,20"] = { name = "default:stone" }
core.world_nodes["20,12,20"] = { name = "default:water_source" }
local p_swimmer = create_mock_player("LakeDiver")
p_swimmer:set_pos({ x = 20, y = 12.5, z = 20 })
p_swimmer:set_hp(0)
local drown_death_info = { category = "drown", reason_text = "drowned" }
deathstats.set_death_camera(p_swimmer, drown_death_info)

local diver_cam = deathstats.player_camera_data["LakeDiver"]
assert(diver_cam ~= nil, "Camera data must be initialized for drowning death")
assert(diver_cam.corpse ~= nil, "Corpse must be spawned in water")
local diver_corpse_y = diver_cam.corpse:get_pos().y
assert(diver_corpse_y == 12.5, string.format("Corpse must stay at exact place of death (y = 12.5), but got y = %s", tostring(diver_corpse_y)))
assert(diver_cam.orbit_center.y == 12.5, "Orbit center must stay at exact water death position")
assert(diver_cam.anchor:get_pos().y == 12.5, "Camera anchor must be at exact water death position")
assert(p_swimmer:get_attach() ~= nil, "Player must be attached to camera anchor orbiting corpse")

-- Verify planar fractured limb pose without abnormal vertical droop
local arm_l_init = diver_cam.corpse:get_bone_override("Arm_Left")
assert(arm_l_init ~= nil, "Drowned corpse must have fractured limb rotation applied")
assert(arm_l_init.rotation.vec.x == 0 and arm_l_init.rotation.vec.y == 0,
    "Drowned corpse limbs must stay planar (x=0, y=0) without vertical droop")
assert(arm_l_init.rotation.vec.z ~= 0, "Drowned corpse must have broken Z rotation applied")

-- Step camera frames: corpse, orbit center, anchor, and player must remain completely static at y = 12.5
deathstats.update_death_camera(p_swimmer, 1.0)
assert(diver_cam.corpse:get_pos().y == 12.5, "Corpse entity must stay static at y = 12.5")
assert(diver_cam.orbit_center.y == 12.5, "Orbit center must stay static at y = 12.5")
assert(diver_cam.anchor:get_pos().y == 12.5, "Camera anchor must stay static at y = 12.5")
assert(p_swimmer:get_pos().y == 12.5, "Player camera base pos must stay static at y = 12.5")
assert(p_swimmer:get_attach() ~= nil, "Player must remain attached to anchor")

deathstats.update_death_camera(p_swimmer, 10.0)
assert(diver_cam.corpse:get_pos().y == 12.5, "Corpse must remain static after 10s")
assert(diver_cam.orbit_center.y == 12.5, "Orbit center must remain static after 10s")
assert(diver_cam.anchor:get_pos().y == 12.5, "Anchor must remain static after 10s")

deathstats.reset_camera(p_swimmer)

-- 6. Lava Death: Player dying in lava pool must stay at exact place of death, NOT pinned to lava floor
core.world_nodes["30,1,30"] = { name = "default:stone" }
core.world_nodes["30,8,30"] = { name = "default:lava_source" }
local p_lava_diver = create_mock_player("LavaSwimmer")
p_lava_diver:set_pos({ x = 30, y = 8.0, z = 30 })
p_lava_diver:set_hp(0)
local lava_death_info = { category = "lava", reason_text = "burned in lava" }
deathstats.set_death_camera(p_lava_diver, lava_death_info)

local lava_cam = deathstats.player_camera_data["LavaSwimmer"]
assert(lava_cam ~= nil, "Camera data must be initialized for lava death")
assert(lava_cam.corpse ~= nil, "Corpse must be spawned in lava")
local lava_corpse_y = lava_cam.corpse:get_pos().y
assert(lava_corpse_y == 8.0, string.format("Corpse must stay at exact place of death in lava (y = 8.0), but got y = %s", tostring(lava_corpse_y)))
assert(lava_cam.orbit_center.y == 8.0, "Orbit center must remain at exact lava death position")
deathstats.reset_camera(p_lava_diver)

-- 7. Mid-Air Death: Dying in the air from non-fall causes (/kill, suicide, mobs, projectiles)
-- must keep corpse, camera anchor, and player at exact mid-air position without snapping 40 blocks to the ground,
-- and anchor must have non-degenerate properties to prevent client physics falling & rubber-banding.
local p_midair = create_mock_player("AirSkydiver")
p_midair:set_pos({ x = 15, y = 35, z = 15 })
p_midair:set_hp(0)
local air_death_info = { category = "suicide", reason_text = "Died in mid-air" }

-- Ground surface check for non-fall death must return pos.y (35), NOT ground (4.5)
local air_surface = deathstats.find_ground_surface({ x = 15, y = 35, z = 15 }, nil, air_death_info)
assert(air_surface == 35, string.format("Mid-air non-fall death must remain at pos.y = 35, got %s", tostring(air_surface)))

-- Standing near ground within 2.5 nodes must still properly snap to walkable ground
local near_ground_surface = deathstats.find_ground_surface({ x = 15, y = 5.2, z = 15 }, nil, air_death_info)
assert(near_ground_surface == 4.5, string.format("Standing near ground (y = 5.2) must snap to surface at 4.5, got %s", tostring(near_ground_surface)))

-- Set death camera in mid-air
deathstats.set_death_camera(p_midair, air_death_info)
local air_cam = deathstats.player_camera_data["AirSkydiver"]
assert(air_cam ~= nil, "Camera data must exist for mid-air death")
assert(air_cam.corpse:get_pos().y == 35, "Corpse must be positioned at death altitude y = 35, not ground!")
assert(air_cam.orbit_center.y == 35, "Orbit center must be at death altitude y = 35, not ground!")
assert(air_cam.anchor:get_pos().y == 35, "Anchor must be at death altitude y = 35, not ground!")
assert(p_midair:get_pos().y == 35, "Player position must be at death altitude y = 35, not ground!")
assert(p_midair:get_attach() ~= nil, "Player must be attached to camera anchor in mid-air")

-- Verify camera_anchor entity is completely invisible to other players
local anchor_props = air_cam.anchor:get_properties()
assert(anchor_props.visual_size.x == 0 and anchor_props.visual_size.y == 0, "Anchor must have zero visual size")
assert(anchor_props.is_visible == false, "Anchor must be marked is_visible = false so other players cannot see it")
assert(anchor_props.pointable == false, "Anchor must not be pointable")
assert(anchor_props.use_texture_alpha == true, "Anchor must have use_texture_alpha enabled")
assert(anchor_props.physical == false, "Anchor must not have physics enabled")

-- Simulate external mod resetting physics override (e.g. 3d_armor or playerphysics restoring gravity to 1)
p_midair:set_physics_override({ speed = 1, jump = 1, gravity = 1 })
assert(p_midair:get_physics_override().gravity == 1, "Physics override was set to 1 by external mod")

-- Run camera update frame: must enforce zero gravity and maintain attachment
deathstats.update_death_camera(p_midair, 0.05)
assert(p_midair:get_physics_override().gravity == 0, "Death camera update must lock gravity back to 0")
assert(p_midair:get_physics_override().speed == 0, "Death camera update must lock speed back to 0")

-- Simulate delayed bones appearing at y = 35: player must be detached, set to new_center, and re-attached to anchor
core.world_nodes["15,35,15"] = { name = "bones:bones" }
core.node_metas["15,35,15"] = {
    get_string = function(self, key)
        if key == "owner" then return "AirSkydiver" end
        return ""
    end,
}
deathstats.update_death_camera(p_midair, 0.05)
assert(air_cam.has_bones == true, "Delayed bones must be recognized")
assert(air_cam.orbit_center.y == 35, "Orbit center must align with bones")
assert(p_midair:get_pos().y == 35, "Player position must align with bones")
assert(p_midair:get_attach() ~= nil, "Player must remain securely attached to anchor")

deathstats.reset_camera(p_midair)

print("  [PASS] Ground Surface Detection & Corpse Ground Snapping")

-- ==========================================================
-- TEST 28: Smooth Death Camera Orbit & Lifecycle (Zero Hurt Sounds & Zero Jitter)
-- ==========================================================
local p_attach = create_mock_player("AttachUser")
p_attach:set_pos({ x = 15, y = 4.5, z = 15 })
p_attach:set_hp(0)
p_attach.armor_groups = { fleshy = 100 }

-- 1. Verify set_death_camera initializes stationary anchor attachment and full damage immunity
core.spawned_entities = {}
deathstats.set_death_camera(p_attach)

local attach_data = deathstats.player_camera_data["AttachUser"]
assert(attach_data ~= nil, "Camera data must exist")
assert(attach_data.corpse ~= nil, "Corpse entity must be spawned")
assert(attach_data.anchor ~= nil, "Anchor entity must be spawned")
assert(p_attach:get_attach() ~= nil, "Player must be attached to stationary anchor (bypasses client gravity and falling physics)")
assert(p_attach.camera ~= nil and p_attach.camera.mode == "first", "Player camera must be set to first")
assert(p_attach.eye_offset ~= nil and p_attach.eye_offset[1].z < 0, "Eye offset must project backwards in first-person mode")
assert(p_attach:get_armor_groups().immortal == 1, "Player armor groups must be set to immortal = 1 while dead")
assert(p_attach.physics_override.gravity == 0, "Player physics override must have gravity = 0 while dead")
assert(p_attach.physics_override.speed == 0, "Player physics override must have speed = 0 while dead")
assert(p_attach.properties.is_visible == false, "Player must be invisible while dead")

-- 2. Verify update_death_camera advances yaw orientation without moving base position (zero packet desync)
local initial_yaw = p_attach.look_horizontal
local initial_anchor_pos = vector.copy(p_attach:get_pos())
deathstats.update_death_camera(p_attach, 0.5)
assert(p_attach.look_horizontal ~= initial_yaw, "Player yaw must rotate with orbit angle")
assert(vector.distance(initial_anchor_pos, p_attach:get_pos()) < 0.001, "Anchor base position must remain strictly stationary at orbit center")

-- 3. Verify reset_camera detaches player, removes corpse & anchor, and restores camera & properties
deathstats.reset_camera(p_attach)
assert(p_attach:get_attach() == nil, "Player must be detached after reset")
assert(attach_data.corpse == nil, "Corpse reference must be nil after reset")
assert(attach_data.anchor == nil, "Anchor reference must be nil after reset")
assert(p_attach.camera.mode == "first", "Camera mode must be set to 'first' on reset")
assert(p_attach.eye_offset[1].z == 0 and p_attach.eye_offset[1].y == 0, "Eye offset must be reset to zero on respawn")
run_deferred_tasks()
assert(p_attach.camera.mode == "any", "Camera mode must be unlocked to 'any' on reset")
assert(p_attach:get_armor_groups().immortal == nil, "Immortal armor group must be removed after reset")
assert(p_attach:get_armor_groups().fleshy == 100, "Original fleshy armor group must be restored")
assert(p_attach.properties.is_visible == true, "Player visibility must be restored")
assert(p_attach.physics_override.speed == 1, "Player physics speed must be restored")

-- 4. Verify on_leaveplayer cleans up corpse entity and camera data
local p_leaver = create_mock_player("LeaverCam")
p_leaver:set_pos({ x = 15, y = 4.5, z = 15 })
p_leaver:set_hp(0)
deathstats.set_death_camera(p_leaver)

local leaver_data = deathstats.player_camera_data["LeaverCam"]
local leaver_corpse = leaver_data.corpse
assert(leaver_corpse.removed == false, "Corpse must be active before leave")

core.on_leaveplayer(p_leaver)
assert(leaver_corpse.removed == true, "Corpse must be removed when player leaves")
assert(deathstats.player_camera_data["LeaverCam"] == nil, "Camera data must be cleared on leave")
print("  [PASS] Smooth Death Camera Orbit & Lifecycle (Zero Hurt Sounds & Zero Jitter)")

-- TEST 29: Corpse Limb Fractures on Fall Death (Continuous Ground Plane Alignment)
-- 1. Verify rotate_corpse_bone_planar using modern set_bone_override (Luanti >= 5.9)
local test_corpse_modern = {
    bone_overrides = {},
    set_bone_override = function(self, bone, override)
        self.bone_overrides[bone] = override
    end,
    get_bone_override = function(self, bone)
        return self.bone_overrides[bone]
    end,
}
local applied_ok = deathstats.rotate_corpse_bone_planar(test_corpse_modern, "Arm_Left", -1.25)
assert(applied_ok == true, "rotate_corpse_bone_planar must succeed with set_bone_override")
local left_arm_ov = test_corpse_modern:get_bone_override("Arm_Left")
assert(left_arm_ov ~= nil, "Bone override must be set on Arm_Left")
assert(left_arm_ov.rotation ~= nil, "Bone override must specify rotation table")
assert(left_arm_ov.rotation.vec.x == 0, "Rotation around local X must be 0 to keep arm flush on the ground")
assert(left_arm_ov.rotation.vec.y == 0, "Rotation around local Y must be 0 to keep arm flush on the ground")
assert(math.abs(left_arm_ov.rotation.vec.z - (-1.25)) < 0.001, "Rotation around local Z must equal requested radians")
assert(left_arm_ov.rotation.absolute == false, "Rotation must be relative (absolute=false) to animated lay pose")
assert(left_arm_ov.rotation.interpolation == 0, "Rotation interpolation must be 0 for instantaneous fracture")

-- 2. Verify rotate_corpse_bone_planar legacy fallback using set_bone_position (Luanti <= 5.8)
local test_corpse_legacy = {
    bone_positions = {
        ["Arm_Right"] = { pos = { x = 3, y = 5, z = 0 }, rot = { x = 0, y = 0, z = 10 } }
    },
    set_bone_position = function(self, bone, pos, rot)
        self.bone_positions[bone] = { pos = pos, rot = rot }
    end,
    get_bone_position = function(self, bone)
        local b = self.bone_positions[bone]
        return b and b.pos or vector.zero(), b and b.rot or vector.zero()
    end,
}
local legacy_rad = 0.5235987756 -- ~30 degrees
local legacy_ok = deathstats.rotate_corpse_bone_planar(test_corpse_legacy, "Arm_Right", legacy_rad)
assert(legacy_ok == true, "rotate_corpse_bone_planar must succeed with legacy set_bone_position")
local legacy_pos, legacy_rot = test_corpse_legacy:get_bone_position("Arm_Right")
assert(legacy_pos.x == 3 and legacy_pos.y == 5, "Legacy bone position coordinates must be preserved")
assert(legacy_rot.x == 0 and legacy_rot.y == 0, "Legacy rotation around X and Y must remain coplanar (0)")
assert(math.abs(legacy_rot.z - (10 + math.deg(legacy_rad))) < 0.01, "Legacy rotation around Z must add degrees to initial rot")

-- 3. Verify fracture_corpse_limbs with custom angles
local custom_angles = {
    ["Arm_Left"] = -0.785,
    ["Arm_Right"] = 0.85,
    ["Leg_Left"] = 0.42,
    ["Leg_Right"] = -0.55,
    ["Head"] = 0.25,
}
local test_corpse_custom = core.add_entity({ x = 0, y = 0, z = 0 }, "deathstats:corpse")
local res_angles = deathstats.fracture_corpse_limbs(test_corpse_custom, custom_angles)
assert(res_angles["Arm_Left"] == -0.785, "Arm_Left custom angle must be applied")
assert(res_angles["Arm_Right"] == 0.85, "Arm_Right custom angle must be applied")
assert(res_angles["Leg_Left"] == 0.42, "Leg_Left custom angle must be applied")
assert(res_angles["Leg_Right"] == -0.55, "Leg_Right custom angle must be applied")
assert(res_angles["Head"] == 0.25, "Head custom angle must be applied")

for _, bone in ipairs({ "Arm_Left", "Arm_Right", "Leg_Left", "Leg_Right", "Head" }) do
    local ov = test_corpse_custom:get_bone_override(bone)
    assert(ov ~= nil, string.format("Bone override for %s must be present", bone))
    assert(ov.rotation.vec.x == 0 and ov.rotation.vec.y == 0,
        string.format("Bone %s must have X=0 and Y=0 to stay flat against the floor", bone))
    assert(ov.rotation.vec.z == custom_angles[bone],
        string.format("Bone %s must have Z matching custom angle", bone))
end

-- 4. Verify fracture_corpse_limbs with random generation conforms to anatomical fracture ranges
local test_corpse_rand = core.add_entity({ x = 0, y = 0, z = 0 }, "deathstats:corpse")
local rand_res = deathstats.fracture_corpse_limbs(test_corpse_rand)
for _, bone in ipairs({ "Arm_Left", "Arm_Right", "Leg_Left", "Leg_Right", "Head" }) do
    local ov = test_corpse_rand:get_bone_override(bone)
    assert(ov ~= nil, string.format("Random fracture must apply override to %s", bone))
    assert(ov.rotation.vec.x == 0 and ov.rotation.vec.y == 0,
        string.format("Bone %s must have X=0 and Y=0 to guarantee 0 vertical clipping or lifting", bone))
    assert(ov.rotation.vec.z ~= 0, string.format("Bone %s must have non-zero rotation for broken bone look", bone))
    assert(ov.rotation.vec.z == rand_res[bone], string.format("Returned angle for %s must match override", bone))
end

local left_arm_deg = math.deg(rand_res["Arm_Left"])
assert((left_arm_deg >= -80.01 and left_arm_deg <= -34.99) or (left_arm_deg >= 19.99 and left_arm_deg <= 55.01),
    string.format("Arm_Left angle (%f deg) must fall within broken bone ranges", left_arm_deg))

local right_arm_deg = math.deg(rand_res["Arm_Right"])
assert((right_arm_deg >= 34.99 and right_arm_deg <= 80.01) or (right_arm_deg >= -55.01 and right_arm_deg <= -19.99),
    string.format("Arm_Right angle (%f deg) must fall within broken bone ranges", right_arm_deg))

local left_leg_deg = math.deg(rand_res["Leg_Left"])
assert((left_leg_deg >= 14.99 and left_leg_deg <= 50.01) or (left_leg_deg >= -30.01 and left_leg_deg <= -9.99),
    string.format("Leg_Left angle (%f deg) must fall within broken bone ranges", left_leg_deg))

local right_leg_deg = math.deg(rand_res["Leg_Right"])
assert((right_leg_deg >= -50.01 and right_leg_deg <= -14.99) or (right_leg_deg >= 9.99 and right_leg_deg <= 30.01),
    string.format("Leg_Right angle (%f deg) must fall within broken bone ranges", right_leg_deg))

local head_deg = math.deg(rand_res["Head"])
assert(head_deg >= -25.01 and head_deg <= 25.01,
    string.format("Head angle (%f deg) must fall within limp neck range [-25, 25]", head_deg))

-- 5. Verify set_death_camera applies limb fractures on fall death
local p_fallguy = create_mock_player("FallGuy")
p_fallguy:set_pos({ x = 20, y = 4.5, z = 20 })
p_fallguy:set_hp(0)
local fall_death_info = { category = "fall", reason_text = "FallGuy fell from a high place" }
deathstats.set_death_camera(p_fallguy, fall_death_info)

local fall_cam_data = deathstats.player_camera_data["FallGuy"]
assert(fall_cam_data ~= nil, "Camera data must be initialized for FallGuy")
local fall_corpse = fall_cam_data.corpse
assert(fall_corpse ~= nil, "Corpse entity must be spawned for FallGuy")
for _, bone in ipairs({ "Arm_Left", "Arm_Right", "Leg_Left", "Leg_Right", "Head" }) do
    local ov = fall_corpse:get_bone_override(bone)
    assert(ov ~= nil, string.format("Fall corpse must have fractured override on %s", bone))
    assert(ov.rotation.vec.x == 0 and ov.rotation.vec.y == 0,
        string.format("Fall corpse %s must be strictly flat on ground plane (x=0, y=0)", bone))
    assert(ov.rotation.vec.z ~= 0, string.format("Fall corpse %s must have broken Z rotation", bone))
end
deathstats.reset_camera(p_fallguy)

-- 6. Verify non-fall deaths (PvP, mob, etc.) ALSO fracture limbs (all deaths have fractured bones)
local p_pvp = create_mock_player("PvPGuy")
p_pvp:set_pos({ x = 30, y = 4.5, z = 30 })
p_pvp:set_hp(0)
local pvp_death_info = { category = "pvp", reason_text = "PvPGuy was slain by Bob" }
deathstats.set_death_camera(p_pvp, pvp_death_info)

local pvp_cam_data = deathstats.player_camera_data["PvPGuy"]
local pvp_corpse = pvp_cam_data.corpse
assert(pvp_corpse ~= nil, "Corpse entity must be spawned for PvPGuy")
for _, bone in ipairs({ "Arm_Left", "Arm_Right", "Leg_Left", "Leg_Right", "Head" }) do
    local ov = pvp_corpse:get_bone_override(bone)
    assert(ov ~= nil, string.format("PvP corpse must have fractured override on %s", bone))
    assert(ov.rotation.vec.x == 0 and ov.rotation.vec.y == 0,
        string.format("PvP corpse %s must be strictly flat on ground plane (x=0, y=0)", bone))
    assert(ov.rotation.vec.z ~= 0, string.format("PvP corpse %s must have broken Z rotation", bone))
end
deathstats.reset_camera(p_pvp)

-- 7. Verify config disable suppresses fractures
deathstats.config.enable_limb_fractures = false
local p_nofall = create_mock_player("NoFractureGuy")
p_nofall:set_pos({ x = 40, y = 4.5, z = 40 })
p_nofall:set_hp(0)
deathstats.set_death_camera(p_nofall, { category = "fall", reason_text = "fell" })
local nofall_corpse = deathstats.player_camera_data["NoFractureGuy"].corpse
assert(nofall_corpse:get_bone_override("Arm_Left") == nil,
    "Disabled enable_limb_fractures must prevent limb fractures on death")
deathstats.reset_camera(p_nofall)
deathstats.config.enable_limb_fractures = true

-- Also verify enable_fall_fractures = false suppresses fractures (backward compatibility)
deathstats.config.enable_fall_fractures = false
local p_nofall2 = create_mock_player("NoFractureGuy2")
p_nofall2:set_pos({ x = 40, y = 4.5, z = 40 })
p_nofall2:set_hp(0)
deathstats.set_death_camera(p_nofall2, { category = "pvp", reason_text = "slain" })
local nofall2_corpse = deathstats.player_camera_data["NoFractureGuy2"].corpse
assert(nofall2_corpse:get_bone_override("Arm_Left") == nil,
    "Disabled enable_fall_fractures must also prevent limb fractures on death")
deathstats.reset_camera(p_nofall2)
deathstats.config.enable_fall_fractures = true

print("  [PASS] Corpse Limb Fractures on All Deaths (Continuous Ground Plane Alignment)")

-- ==========================================
-- TEST SUITE 30: Player HUD, Hand/Weapon (wielditem) & Custom Bars (hb) Suppression & Restoration
-- ==========================================

-- Verify compatibility layer module is loaded
assert(deathstats.compat_hudbars ~= nil, "deathstats.compat_hudbars must be initialized")

-- 1. Complete Wielditem & HUD Suppression during death sequence
local p_hud = create_mock_player("HUDGuy")
p_hud:set_pos({ x = 50, y = 4.5, z = 50 })
p_hud:set_hp(0)
hb.players["HUDGuy"] = p_hud
deathstats.trigger_death_screen(p_hud, { type = "fall" })

assert(p_hud.hud_flags.wielditem == false, "Player wielditem (hand/weapon) must be hidden (false) during death screen")
assert(p_hud.hud_flags.hotbar == false, "Player hotbar must be hidden (false) during death screen")
assert(p_hud.hud_flags.healthbar == false, "Player healthbar must be hidden (false) during death screen")
assert(p_hud.hud_flags.breathbar == false, "Player breathbar must be hidden (false) during death screen")
assert(p_hud.hud_flags.crosshair == false, "Player crosshair must be hidden (false) during death screen")
assert(p_hud.hud_flags.minimap == false, "Player minimap must be hidden (false) during death screen")

-- Verify hudbars (hb) integration hides custom health, breath, hunger bars
assert(hb_hidden["HUDGuy"] ~= nil, "hb_hidden entry must exist for dead player")
assert(hb_hidden["HUDGuy"]["health"] == true, "hb.hide_hudbar must be called for health hudbar")
assert(hb_hidden["HUDGuy"]["hunger"] == true, "hb.hide_hudbar must be called for hunger hudbar")
assert(hb_hidden["HUDGuy"]["breath"] == true, "hb.hide_hudbar must be called for breath hudbar")

-- Verify player is paused from hb.players to bypass hudbars globalstep updates
assert(hb.players["HUDGuy"] == nil, "Dead player must be removed from hb.players globalstep update loop")
assert(deathstats.compat_hudbars.paused_players["HUDGuy"] == true, "Player must be recorded in paused_players")

-- Verify underlying HUD components were zero-scaled
assert(p_hud.huds[103] and p_hud.huds[103].scale and p_hud.huds[103].scale.x == 0,
    "statbar scale must be zero-scaled during death")
assert(p_hud.huds[103] and p_hud.huds[103].number == 0, "statbar number must be zeroed during death")

-- Verify hooked hb functions strictly reject updates and unhide calls while player is dead
local unhide_res = hb.unhide_hudbar(p_hud, "health")
assert(unhide_res == false, "hb.unhide_hudbar must reject unhiding while player is dead")
local change_res = hb.change_hudbar(p_hud, "health", 20, 20)
assert(change_res == false, "hb.change_hudbar must reject changes while player is dead")

-- 2. Complete Restoration of HUD, Wielditem & Custom Bars upon Respawn
p_hud:respawn()
assert(p_hud.hud_flags.wielditem == true, "Player wielditem must be restored (true) on respawn")
assert(p_hud.hud_flags.hotbar == true, "Player hotbar must be restored (true) on respawn")
assert(p_hud.hud_flags.crosshair == true, "Player crosshair must be restored (true) on respawn")
assert(p_hud.hud_flags.minimap == true, "Player minimap must be restored (true) on respawn")

-- When hudbars is active, default engine healthbar and breathbar MUST remain false to prevent 2 duplicate healthbars!
assert(p_hud.hud_flags.healthbar == false, "Player default healthbar must remain suppressed (false) on respawn when hudbars is active")
assert(p_hud.hud_flags.breathbar == false, "Player default breathbar must remain suppressed (false) on respawn when hudbars is active")

-- hudbars custom bars must be unhidden so only hudbars displays
assert(hb_hidden["HUDGuy"]["health"] == nil, "hb.unhide_hudbar must be called for health hudbar on respawn")
assert(hb_hidden["HUDGuy"]["hunger"] == nil, "hb.unhide_hudbar must be called for hunger hudbar on respawn")
assert(hb_hidden["HUDGuy"]["breath"] == nil, "hb.unhide_hudbar must be called for breath hudbar on respawn")
assert(hb.players["HUDGuy"] == p_hud, "Player must be restored to hb.players on respawn")
assert(deathstats.compat_hudbars.paused_players["HUDGuy"] == nil, "paused_players entry must be cleared on respawn")
assert(p_hud.huds[103].scale and p_hud.huds[103].scale.x == 1, "statbar scale must be restored to 1 on respawn")

-- 3. Direct set_death_camera and reset_camera suppression and restoration
local p_cam_hud = create_mock_player("CamHUDGuy")
p_cam_hud:set_pos({ x = 60, y = 5, z = 60 })
p_cam_hud:set_hp(0)
deathstats.set_death_camera(p_cam_hud)

assert(p_cam_hud.hud_flags.wielditem == false, "set_death_camera must suppress wielditem")
assert(p_cam_hud.hud_flags.hotbar == false, "set_death_camera must suppress hotbar")
assert(p_cam_hud.hud_flags.healthbar == false, "set_death_camera must suppress healthbar")
assert(hb_hidden["CamHUDGuy"] ~= nil and hb_hidden["CamHUDGuy"]["hunger"] == true,
    "set_death_camera must hide custom hunger bar via hb")

deathstats.reset_camera(p_cam_hud)
assert(p_cam_hud.hud_flags.wielditem == true, "reset_camera must restore wielditem")
assert(p_cam_hud.hud_flags.hotbar == true, "reset_camera must restore hotbar")
assert(p_cam_hud.hud_flags.healthbar == false, "reset_camera must keep default healthbar suppressed when hudbars is active")
assert(hb_hidden["CamHUDGuy"]["hunger"] == nil, "reset_camera must unhide custom hunger bar via hb")

-- 4. Globalstep reinforcement test
local p_reinforce = create_mock_player("ReinforceGuy")
p_reinforce:set_pos({ x = 70, y = 10, z = 70 })
p_reinforce:set_hp(0)
deathstats.trigger_death_screen(p_reinforce, { type = "fall" })
-- Simulate a rogue mod re-adding player to hb.players or unhiding state
hb.players["ReinforceGuy"] = p_reinforce
core.on_globalstep(0.1)
assert(hb.players["ReinforceGuy"] == nil, "Globalstep reinforcement must re-remove dead player from hb.players")
p_reinforce:respawn()

-- 5. Fallback restoration when hudbars does not manage healthbar
local orig_hb_health = hb.hudtables.health
hb.hudtables.health = nil
local p_nohb = create_mock_player("NoHBGuy")
p_nohb:set_pos({ x = 80, y = 10, z = 80 })
p_nohb:set_hp(0)
deathstats.trigger_death_screen(p_nohb, { type = "fall" })
assert(p_nohb.hud_flags.healthbar == false, "Default healthbar must be hidden during death without hudbars")
p_nohb:respawn()
assert(p_nohb.hud_flags.healthbar == true, "Default healthbar must be restored (true) on respawn when hudbars is absent")
hb.hudtables.health = orig_hb_health

print("  [PASS] Player HUD, Hand/Weapon (wielditem) & Custom Bars (hb) Suppression & Restoration")

-- TEST 31: Thematic Death Screen Overlays (Lava, Fire, Drown & Blood Fallback)
do
    print("\n--- TEST 31: Thematic Death Screen Overlays (Lava, Fire, Drown, Blood) ---")

-- 1. Lava Death
local p_lava = create_mock_player("LavaTester")
p_lava:set_pos({ x = 100, y = 10, z = 100 })
core.set_node({ x = 100, y = 10, z = 100 }, { name = "default:lava_source" })
deathstats.trigger_death_screen(p_lava, { type = "burn" })
local lava_splatter_found = false
local lava_banner_found = false
for _, hdef in pairs(p_lava.huds) do
    if hdef.text and hdef.text:find("deathstats_lava_splatter%.png") then
        lava_splatter_found = true
    end
    if hdef.text and hdef.text:find("deathstats_you_died_lava%.png") then
        lava_banner_found = true
    end
end
assert(lava_splatter_found, "Lava death must select deathstats_lava_splatter.png overlay")
assert(lava_banner_found, "Lava death must select deathstats_you_died_lava.png banner")
p_lava:respawn()

-- 2. Fire Death
local p_fire = create_mock_player("FireTester")
p_fire:set_pos({ x = 200, y = 10, z = 200 })
core.set_node({ x = 200, y = 10, z = 200 }, { name = "air" })
deathstats.trigger_death_screen(p_fire, { type = "burn" })
local fire_splatter_found = false
local fire_banner_found = false
for _, hdef in pairs(p_fire.huds) do
    if hdef.text and hdef.text:find("deathstats_fire_splatter%.png") then
        fire_splatter_found = true
    end
    if hdef.text and hdef.text:find("deathstats_you_died_fire%.png") then
        fire_banner_found = true
    end
end
assert(fire_splatter_found, "Fire death must select deathstats_fire_splatter.png overlay")
assert(fire_banner_found, "Fire death must select deathstats_you_died_fire.png banner")
p_fire:respawn()

-- 3. Drown Death
local p_drown = create_mock_player("DrownTester")
p_drown:set_pos({ x = 300, y = 10, z = 300 })
deathstats.trigger_death_screen(p_drown, { type = "drown" })
local drown_splatter_found = false
local drown_banner_found = false
for _, hdef in pairs(p_drown.huds) do
    if hdef.text and hdef.text:find("deathstats_drown_splatter%.png") then
        drown_splatter_found = true
    end
    if hdef.text and hdef.text:find("deathstats_you_died_drown%.png") then
        drown_banner_found = true
    end
end
assert(drown_splatter_found, "Drown death must select deathstats_drown_splatter.png overlay")
assert(drown_banner_found, "Drown death must select deathstats_you_died_drown.png banner")
p_drown:respawn()

-- 4. Fall / Combat Death (Fallback to blood splatter and standard banner)
local p_fall_overlay = create_mock_player("FallTester")
p_fall_overlay:set_pos({ x = 400, y = 10, z = 400 })
deathstats.trigger_death_screen(p_fall_overlay, { type = "fall" })
local blood_splatter_found = false
local standard_banner_found = false
for _, hdef in pairs(p_fall_overlay.huds) do
    if hdef.text and hdef.text:find("deathstats_blood_splatter%.png") then
        blood_splatter_found = true
    end
    if hdef.text and hdef.text:find("deathstats_you_died%.png") and not hdef.text:find("deathstats_you_died_") then
        standard_banner_found = true
    end
end
assert(blood_splatter_found, "Fall/combat death must fallback to deathstats_blood_splatter.png overlay")
assert(standard_banner_found, "Fall/combat death must fallback to deathstats_you_died.png banner")
p_fall_overlay:respawn()

print("  [PASS] Thematic overlay & banner selection: lava, fire, drown, and blood fallback")
end

-- ==========================================================
-- TEST 32: Complete Invisibility for Camera Anchor & Orbiting Deceased Player
-- ==========================================================
do
    print("\n--- TEST 32: Complete Invisibility for Camera Anchor & Orbiting Deceased Player ---")
local p_multi = create_mock_player("GhostPlayer")
p_multi:set_pos({ x = 50, y = 10, z = 50 })
p_multi:set_hp(0)
p_multi.properties.textures = { "my_cool_skin.png" }
p_multi.nametag_attributes = {
    text = "GhostPlayer",
    color = { a = 255, r = 255, g = 255, b = 255 },
    bgcolor = { a = 128, r = 0, g = 0, b = 0 },
}

-- Attach an external child object to the player (e.g. 3d_armor helmet or wielditem)
local child_entity = core.add_entity({ x = 50, y = 10, z = 50 }, "test:armor_helmet")
child_entity.properties.visual_size = { x = 1, y = 1, z = 1 }
child_entity.properties.is_visible = true
child_entity.properties.pointable = true
p_multi.children = { child_entity }

-- 1. Trigger death camera
deathstats.set_death_camera(p_multi)
local mdata = deathstats.player_camera_data["GhostPlayer"]
assert(mdata ~= nil, "Camera data must be initialized for GhostPlayer")

-- A. Player visibility, nametag, and properties
local mprops = p_multi:get_properties()
assert(mprops.is_visible == false, "Player must be marked is_visible = false")
assert(mprops.visual_size.x == 0 and mprops.visual_size.y == 0 and mprops.visual_size.z == 0, "Player visual_size must be zero")
assert(mprops.pointable == false, "Player must not be pointable")
assert(mprops.show_on_minimap == false, "Player must be hidden on minimap")
assert(mprops.textures[1] == "deathstats_transparent.png", "Player textures must be set to transparent texture")
assert(mprops.use_texture_alpha == true, "Player must have use_texture_alpha enabled")
assert(mprops.selectionbox[1] == 0 and mprops.selectionbox[4] == 0, "Player selectionbox must be zero")

local mnametag = p_multi:get_nametag_attributes()
assert(mnametag.text == "", "Player nametag text must be completely empty while dead")
assert(mnametag.color.a == 0, "Player nametag alpha must be 0 (completely transparent)")
assert(mnametag.bgcolor.a == 0, "Player nametag background alpha must be 0")

-- B. Camera anchor visibility
assert(mdata.anchor ~= nil, "Camera anchor must be created")
local aprops = mdata.anchor:get_properties()
assert(aprops.is_visible == false, "Camera anchor must be marked is_visible = false")
assert(aprops.visual_size.x == 0 and aprops.visual_size.y == 0 and aprops.visual_size.z == 0, "Camera anchor visual_size must be zero")
assert(aprops.pointable == false, "Camera anchor must not be pointable")
assert(aprops.show_on_minimap == false, "Camera anchor must be hidden on minimap")
assert(aprops.use_texture_alpha == true, "Camera anchor must have use_texture_alpha enabled")
assert(aprops.selectionbox[1] == 0 and aprops.selectionbox[4] == 0, "Camera anchor selectionbox must be zero")

-- C. Attached child entities
local cprops = child_entity:get_properties()
assert(cprops.is_visible == false, "Attached child entity must be marked is_visible = false")
assert(cprops.visual_size.x == 0 and cprops.visual_size.y == 0, "Attached child entity visual_size must be zero")
assert(cprops.pointable == false, "Attached child entity must not be pointable")

-- 2. Simulate external mod globalstep trying to restore player properties and nametag
p_multi:set_properties({
    is_visible = true,
    visual_size = { x = 1, y = 1, z = 1 },
    pointable = true,
})
p_multi:set_nametag_attributes({
    text = "GhostPlayer",
    color = { a = 255, r = 255, g = 255, b = 255 },
})
mdata.anchor:set_properties({
    is_visible = true,
    visual_size = { x = 1, y = 1, z = 1 },
})

-- Run update_death_camera frame: must immediately re-enforce 100% invisibility
deathstats.update_death_camera(p_multi, 0.05)

local re_props = p_multi:get_properties()
assert(re_props.is_visible == false, "update_death_camera must re-enforce is_visible = false on player")
assert(re_props.visual_size.x == 0 and re_props.visual_size.y == 0, "update_death_camera must re-enforce zero visual_size on player")
assert(re_props.pointable == false, "update_death_camera must re-enforce pointable = false on player")
assert(re_props.textures[1] == "deathstats_transparent.png", "update_death_camera must re-enforce transparent textures on player")

local re_nametag = p_multi:get_nametag_attributes()
assert(re_nametag.text == "", "update_death_camera must re-enforce empty nametag text")
assert(re_nametag.color.a == 0, "update_death_camera must re-enforce zero alpha on nametag")

local re_aprops = mdata.anchor:get_properties()
assert(re_aprops.is_visible == false, "update_death_camera must re-enforce is_visible = false on anchor")
assert(re_aprops.visual_size.x == 0 and re_aprops.visual_size.y == 0, "update_death_camera must re-enforce zero visual_size on anchor")

-- 3. Respawn: Clean restoration of original player appearance, nametag, and anchor removal
local anchor_multi = mdata.anchor
deathstats.reset_camera(p_multi)
assert(deathstats.player_camera_data["GhostPlayer"] == nil, "Camera data must be cleared on respawn")
assert(anchor_multi.removed == true, "Camera anchor must be removed on respawn")

local respawn_props = p_multi:get_properties()
assert(respawn_props.is_visible == true, "Player is_visible must be restored to true on respawn")
assert(respawn_props.visual_size.x == 1 and respawn_props.visual_size.y == 1, "Player visual_size must be restored to 1 on respawn")
assert(respawn_props.pointable == true, "Player pointable must be restored to true on respawn")
assert(respawn_props.textures[1] == "my_cool_skin.png", "Player skin textures must be cleanly restored on respawn")
assert(respawn_props.show_on_minimap == true, "Player minimap visibility must be restored on respawn")

local respawn_nametag = p_multi:get_nametag_attributes()
assert(respawn_nametag.text == "GhostPlayer", "Player nametag text must be restored on respawn")
assert(respawn_nametag.color.a == 255, "Player nametag alpha must be restored to 255 on respawn")
assert(respawn_nametag.bgcolor.a == 128, "Player nametag bgcolor alpha must be restored on respawn")

print("  [PASS] Complete invisibility for camera anchor & orbiting player, with full respawn restoration")
end

--------------------------------------------------------------------------------
-- TEST 33: Offline Player Safety & Network Packet Quota Optimization
--------------------------------------------------------------------------------
do
    print("\n--- TEST 33: Offline Player Safety & Network Packet Quota Optimization ---")

-- A. is_player_online helper verification
assert(deathstats.is_player_online(nil) == false, "nil must not be online")
assert(deathstats.is_player_online("NonExistentPlayer") == false, "Unregistered player must not be online")

local p_safety = create_mock_player("SafetyTester")
mock_players["SafetyTester"] = p_safety
deathstats.left_players["SafetyTester"] = nil
assert(deathstats.is_player_online("SafetyTester") == true, "Active player must be online")
assert(deathstats.is_player_online(p_safety) == true, "Active ObjectRef must be online")

-- B. Disconnect / Leave handling prevents animation calls and deferred timers
deathstats.set_death_camera(p_safety)
assert(deathstats.player_camera_data["SafetyTester"] ~= nil, "Camera data should exist before leave")

-- Track player_api.set_animation calls and core.after calls
p_safety.current_anim = nil

local timers_scheduled = 0
local orig_after = core.after
core.after = function(delay, func, ...)
    timers_scheduled = timers_scheduled + 1
    orig_after(delay, func, ...)
end

-- Simulate player leave event
core.on_leaveplayer(p_safety)

-- Verify player marked as left and camera cleaned up
assert(deathstats.left_players["SafetyTester"] == true, "Player must be marked in left_players")
assert(deathstats.is_player_online("SafetyTester") == false, "Leaving player must report offline")
assert(deathstats.player_camera_data["SafetyTester"] == nil, "Camera data must be nil after leave")

-- Verify NO set_animation was called during reset_player_effects(p_safety, true)
assert(p_safety.current_anim == nil, "set_animation must NOT be called on leaving player")
assert(timers_scheduled == 0, "No deferred retry timers (core.after) should be scheduled for leaving player")

-- Verify animation hook directly returns for offline/left player without calling underlying set_animation
player_api.set_animation(p_safety, "stand", 30)
assert(p_safety.current_anim == nil, "player_api hook must no-op when player is offline or in left_players")

-- Restore spy
core.after = orig_after

-- C. Network packet quota optimization: verify child entity property caching & look yaw throttling
local p_network = create_mock_player("NetworkTester")
mock_players["NetworkTester"] = p_network
deathstats.left_players["NetworkTester"] = nil

local child_armor = {
    props = { is_visible = true, visual_size = { x = 1, y = 1, z = 1 }, pointable = true },
    prop_call_count = 0,
    is_player = function() return false end,
    get_properties = function(self) return self.props end,
    set_properties = function(self, new_props)
        self.prop_call_count = self.prop_call_count + 1
        for k, v in pairs(new_props) do self.props[k] = v end
    end,
}
p_network.children = { child_armor }

-- Initialize death camera
deathstats.set_death_camera(p_network)
local initial_calls = child_armor.prop_call_count
assert(initial_calls > 0, "Child armor should be hidden initially")
assert(child_armor.props.is_visible == false, "Child armor should be hidden")

-- Simulate 10 consecutive ticks with tiny dtime (angle delta < 0.008 radians)
local yaw_calls = 0
local saved_set_yaw = p_network.set_look_horizontal
p_network.set_look_horizontal = function(self, yaw)
    yaw_calls = yaw_calls + 1
    saved_set_yaw(self, yaw)
end

for _ = 1, 10 do
    deathstats.update_death_camera(p_network, 0.0001)
end

-- child:set_properties must not have been called redundantly across the 10 frames
assert(child_armor.prop_call_count == initial_calls,
    "child:set_properties must not be called when properties are already hidden (prevents packet flooding)")

-- player:set_look_horizontal must have been suppressed for delta < 0.008
assert(yaw_calls == 0,
    "player:set_look_horizontal must be throttled when delta < 0.008 rad (prevents packet quota exhaustion)")

-- Clean up
p_network.set_look_horizontal = saved_set_yaw
deathstats.reset_camera(p_network)

-- D. zero_player_velocity helper: modern Luanti 5.9+ vs legacy Minetest <= 5.8
local modern_player = {
    vel = { x = 3, y = -15, z = 4 },
    get_velocity = function(self) return self.vel end,
    add_velocity = function(self, v) self.vel = vector.add(self.vel, v) end,
    get_player_velocity = function() error("Deprecated get_player_velocity must NOT be called on modern Luanti") end,
    add_player_velocity = function() error("Deprecated add_player_velocity must NOT be called on modern Luanti") end,
    set_velocity = function() error("Simulated PlayerSAO set_velocity failure") end,
}
deathstats.zero_player_velocity(modern_player)
assert(modern_player.vel.x == 0 and modern_player.vel.y == 0 and modern_player.vel.z == 0,
    "modern_player velocity must be zeroed using get_velocity and add_velocity")

local legacy_player = {
    vel = { x = 0, y = -25, z = 0 },
    get_player_velocity = function(self) return self.vel end,
    add_player_velocity = function(self, v) self.vel = vector.add(self.vel, v) end,
}
deathstats.zero_player_velocity(legacy_player)
assert(legacy_player.vel.x == 0 and legacy_player.vel.y == 0 and legacy_player.vel.z == 0,
    "legacy_player velocity must be zeroed using fallback methods")

print("  [PASS] Offline player animation safety & network packet quota optimization")
end

--------------------------------------------------------------------------------
-- TEST 34: Orbiting Camera Non-Pointability & Zero-Reach Protection
--------------------------------------------------------------------------------
do
    print("\n--- TEST 34: Orbiting Camera Non-Pointability & Zero-Reach Protection ---")

    -- A. Item registration verification: deathstats:camera_hand must have range = 0, pointable = false, liquids_pointable = false, pointabilities
    local hand_def = core.registered_items["deathstats:camera_hand"]
    assert(hand_def ~= nil, "deathstats:camera_hand item must be registered")
    assert(hand_def.range == 0, "deathstats:camera_hand range must be exactly 0")
    assert(hand_def.pointable == false, "deathstats:camera_hand pointable must be false")
    assert(hand_def.liquids_pointable == false, "deathstats:camera_hand liquids_pointable must be false")
    assert(type(hand_def.pointabilities) == "table", "deathstats:camera_hand pointabilities must be a table")
    assert(type(hand_def.pointabilities.nodes) == "table" and type(hand_def.pointabilities.objects) == "table",
        "deathstats:camera_hand pointabilities must define empty nodes and objects tables")

    -- B. Verify corpse entity selectionbox and pointable
    local corpse_def = core.registered_entities["deathstats:corpse"]
    assert(corpse_def ~= nil, "deathstats:corpse entity must be registered")
    assert(corpse_def.initial_properties.pointable == false, "corpse initial_properties pointable must be false")
    assert(corpse_def.initial_properties.selectionbox ~= nil, "corpse initial_properties must specify selectionbox")
    assert(corpse_def.initial_properties.selectionbox[1] == 0 and corpse_def.initial_properties.selectionbox[4] == 0,
        "corpse initial_properties selectionbox must be zero size")

    -- Ensure bones_mode is bones so inventory is retained (simulating bones mod / keepInventory)
    core.settings:set("bones_mode", "bones")

    -- C. set_death_camera enforces zero-reach camera hand and stashes inventory
    local p_orbit_reach = create_mock_player("OrbitReachTester")
    p_orbit_reach:set_pos({ x = 120, y = 5, z = 120 })
    p_orbit_reach:set_hp(0)

    -- Populate inventory with held tool and blocks (simulating keepInventory / delayed drop)
    local inv = p_orbit_reach:get_inventory()
    inv:set_stack("main", 1, rawget(_G, "ItemStack")("default:sword_steel 1"))
    inv:set_stack("main", 2, rawget(_G, "ItemStack")("default:pick_steel 1"))
    inv:set_stack("main", 3, rawget(_G, "ItemStack")("default:cobble 64"))
    inv:set_stack("hand", 1, rawget(_G, "ItemStack")("custom_mod:magic_hand 1"))
    inv:set_size("hand", 1)

    deathstats.set_death_camera(p_orbit_reach)

    -- Assert hand inventory list is now size 1 with deathstats:camera_hand
    assert(inv:get_size("hand") == 1, "Player hand inventory list must be size 1 during death camera")
    local active_hand = inv:get_stack("hand", 1)
    local active_hand_name = (type(active_hand) == "table" and active_hand.name) or active_hand
    assert(active_hand_name == "deathstats:camera_hand",
        "Player hand inventory list must hold deathstats:camera_hand during death camera")

    -- Assert main inventory is left completely intact for the game / mods
    local main_after = inv:get_list("main")
    local has_main_items = false
    for _, st in ipairs(main_after or {}) do
        if st and not st:is_empty() then has_main_items = true end
    end
    assert(has_main_items, "Main inventory items must remain intact for game/mods out of the box")

    local cdata = deathstats.player_camera_data["OrbitReachTester"]
    assert(cdata ~= nil, "Camera data must exist for OrbitReachTester")
    assert(cdata.saved_hand_stack ~= nil, "Saved hand stack must be preserved in camera data")

    -- Assert corpse instance in world has selectionbox = 0 and pointable = false
    assert(cdata.corpse ~= nil, "Corpse entity must exist in camera data")
    local corpse_props = cdata.corpse:get_properties()
    assert(corpse_props.pointable == false, "Live corpse entity must have pointable = false")
    assert(corpse_props.selectionbox and corpse_props.selectionbox[1] == 0 and corpse_props.selectionbox[4] == 0,
        "Live corpse entity must have selectionbox = 0")

    -- D. Globalstep re-enforcement if external mod alters hand
    inv:set_stack("hand", 1, { name = "rogue_mod:long_reach_tool", count = 1 })
    deathstats.update_death_camera(p_orbit_reach, 0.05)
    local re_hand = inv:get_stack("hand", 1)
    local re_hand_name = (type(re_hand) == "table" and re_hand.name) or re_hand
    assert(re_hand_name == "deathstats:camera_hand",
        "update_death_camera must re-enforce deathstats:camera_hand in hand inventory list")

    -- Verify main inventory is stashed and cleared on globalstep tick so camera_hand takes effect
    local main_during_orbit = inv:get_list("main")
    local is_main_empty = true
    for _, st in ipairs(main_during_orbit or {}) do
        if st and not st:is_empty() then is_main_empty = false end
    end
    assert(is_main_empty, "Main inventory must be cleared to empty during camera orbit so camera_hand takes effect")
    assert(cdata.stashed_main ~= nil and #cdata.stashed_main >= 3, "Stashed main inventory must be preserved in camera data")

    -- E. Action cancellation guards: punch, place, dig, eat, rightclick, pickup callbacks blocked while dead
    deathstats.dead_players["OrbitReachTester"] = true

    local punch_result = core.on_punchnode({ x = 120, y = 5, z = 121 }, { name = "default:stone" }, p_orbit_reach, {})
    assert(punch_result == true, "core.on_punchnode must cancel punch action for dead player")

    local place_result = core.on_placenode({ x = 120, y = 6, z = 120 }, { name = "default:cobble" }, p_orbit_reach, {}, "default:cobble", {})
    assert(place_result == true, "core.on_placenode must prevent block placement for dead player")

    local dig_result = core.on_dignode({ x = 120, y = 5, z = 121 }, { name = "default:stone" }, p_orbit_reach)
    assert(dig_result == true, "core.on_dignode must prevent block digging for dead player")

    local eat_result = core.on_item_eat(2, "", "default:apple", p_orbit_reach, {})
    assert(eat_result == "default:apple", "core.on_item_eat must prevent item consumption for dead player")

    local punch_player_res = core.on_punchplayer(p_orbit_reach, player1, 1.0, nil, nil, 10)
    assert(punch_player_res == true, "core.on_punchplayer must block dead victim from receiving punch damage")

    local punch_by_dead_res = core.on_punchplayer(player1, p_orbit_reach, 1.0, nil, nil, 10)
    assert(punch_by_dead_res == true, "core.on_punchplayer must block dead player from punching others")

    local rc_res = core.on_rightclickplayer(p_orbit_reach, player1)
    assert(rc_res == true, "core.on_rightclickplayer must block rightclick interaction for dead player")

    local pickup_item = rawget(_G, "ItemStack")("default:diamond 5")
    local pickup_res = core.on_item_pickup(pickup_item, p_orbit_reach, {})
    assert(pickup_res == pickup_item, "core.on_item_pickup must return uncollected itemstack for dead player")

    -- F. Respawn restores original inventory and hand
    deathstats.reset_camera(p_orbit_reach)

    local restored_main = inv:get_list("main")
    assert(restored_main ~= nil and #restored_main >= 3, "Main inventory must be restored on respawn")
    local item1_name = (restored_main[1] and ((restored_main[1].get_name and restored_main[1]:get_name()) or restored_main[1].name))
    assert(item1_name == "default:sword_steel", "Slot 1 must be restored to default:sword_steel")
    local item2_name = (restored_main[2].get_name and restored_main[2]:get_name()) or restored_main[2].name
    local item3_name = (restored_main[3].get_name and restored_main[3]:get_name()) or restored_main[3].name
    assert(item2_name == "default:pick_steel", "Slot 2 must be restored to default:pick_steel")
    assert(item3_name == "default:cobble", "Slot 3 must be restored to default:cobble")

    local restored_hand = inv:get_stack("hand", 1)
    local restored_hand_name = (type(restored_hand) == "table" and (restored_hand.get_name and restored_hand:get_name() or restored_hand.name)) or restored_hand
    assert(restored_hand_name == "custom_mod:magic_hand", "Custom hand must be restored on respawn")

    -- G. Disconnect / Leaveplayer restoration
    local p_leave_reach = create_mock_player("LeaveReachTester")
    p_leave_reach:set_pos({ x = 130, y = 5, z = 130 })
    p_leave_reach:set_hp(0)
    local leave_inv = p_leave_reach:get_inventory()
    leave_inv:set_stack("main", 1, rawget(_G, "ItemStack")("default:diamond 5"))
    deathstats.set_death_camera(p_leave_reach)
    local held_stack = leave_inv:get_stack("main", 1)
    assert(held_stack and held_stack:get_name() == "default:diamond",
        "Main inventory must remain intact for game/mods while dead")

    -- Player leaves while dead
    core.on_leaveplayer(p_leave_reach)
    local leave_restored_main = leave_inv:get_list("main")
    assert(leave_restored_main ~= nil and leave_restored_main[1], "Main inventory must remain intact on leave")
    local leave_item1_name = (leave_restored_main[1].get_name and leave_restored_main[1]:get_name()) or leave_restored_main[1].name
    assert(leave_item1_name == "default:diamond",
        "Player inventory must remain intact when disconnecting during death camera")

    print("  [PASS] Orbiting camera non-pointability & zero-reach protection (hand range 0, corpse/anchor non-pointable, actions guarded, clean restore)")
end

--------------------------------------------------------------------------------
-- TEST 35: Joinplayer Inventory & Hand Verification & Restoration
--------------------------------------------------------------------------------
do
    print("\n--- TEST 35: Joinplayer Inventory & Hand Verification & Restoration ---")

    -- Case A: Player joins alive with in-memory stashed hand
    local p_join1 = create_mock_player("JoinAliveTester")
    p_join1:set_pos({ x = 200, y = 5, z = 200 })
    p_join1:set_hp(20)
    local inv1 = p_join1:get_inventory()
    inv1:set_stack("hand", 1, "deathstats:camera_hand")
    inv1:set_size("hand", 1)

    deathstats.player_camera_data["JoinAliveTester"] = {
        saved_hand_size = 1,
        saved_hand_stack = "custom_mod:miner_hand",
    }

    core.on_joinplayer(p_join1)

    local hand_res1 = inv1:get_stack("hand", 1)
    local hand_res1_name = (type(hand_res1) == "table" and hand_res1:get_name()) or hand_res1
    assert(hand_res1_name == "custom_mod:miner_hand",
        "Joinplayer must restore custom hand stack")

    -- Case B: Player joins alive after crash/reboot (camera data nil, legacy metadata purged)
    local p_join2 = create_mock_player("CrashRebootTester")
    p_join2:set_pos({ x = 210, y = 5, z = 210 })
    p_join2:set_hp(20)
    local inv2 = p_join2:get_inventory()
    inv2:set_stack("hand", 1, "deathstats:camera_hand")
    inv2:set_size("hand", 1)

    local meta2 = p_join2:get_meta()
    meta2:set_string("deathstats:stashed_main", core.serialize({
        { name = "default:mese_crystal", count = 9, wear = 0, metadata = "" },
    }))
    meta2:set_string("deathstats:stashed_offhand", core.serialize({
        { name = "default:torch", count = 64, wear = 0, metadata = "" },
    }))
    meta2:set_string("deathstats:stashed_hand", core.serialize({
        size = 1,
        stack = "custom:gloves",
    }))

    -- Simulate server reboot: player_camera_data has no entry
    deathstats.player_camera_data["CrashRebootTester"] = nil

    core.on_joinplayer(p_join2)

    local hand_res2 = inv2:get_stack("hand", 1)
    local hand_res2_name = (type(hand_res2) == "table" and hand_res2:get_name()) or hand_res2
    assert(hand_res2_name == "custom:gloves",
        "Joinplayer must recover stashed hand stack from player metadata after crash")
    assert(meta2:get_string("deathstats:stashed_main") == "",
        "Legacy stashed_main metadata must be purged")
    assert(meta2:get_string("deathstats:stashed_offhand") == "",
        "Legacy stashed_offhand metadata must be purged")
    assert(meta2:get_string("deathstats:stashed_hand") == "",
        "Metadata stashed_hand must be cleared after restoration")

    -- Case C: Stuck deathstats:camera_hand purged and properties restored on join
    local p_join3 = create_mock_player("StuckHandTester")
    p_join3:set_pos({ x = 220, y = 5, z = 220 })
    p_join3:set_hp(20)
    p_join3:set_properties({ pointable = false, interaction_range = 0 })
    local inv3 = p_join3:get_inventory()
    inv3:set_stack("hand", 1, "deathstats:camera_hand")
    inv3:set_size("hand", 1)
    inv3:set_stack("main", 1, "deathstats:camera_hand")
    inv3:set_stack("craft", 1, "deathstats:camera_hand")

    core.on_joinplayer(p_join3)

    assert(inv3:get_size("hand") == 0, "Stuck deathstats:camera_hand must be purged from hand list")
    local leaked_main = inv3:get_stack("main", 1)
    local leaked_main_name = (type(leaked_main) == "table" and leaked_main:get_name()) or leaked_main
    assert(leaked_main_name ~= "deathstats:camera_hand", "Camera hand must be purged from main list")
    local leaked_craft = inv3:get_stack("craft", 1)
    local leaked_craft_name = (type(leaked_craft) == "table" and leaked_craft:get_name()) or leaked_craft
    assert(leaked_craft_name ~= "deathstats:camera_hand", "Camera hand must be purged from craft list")
    local props3 = p_join3:get_properties()
    assert(props3.pointable == true, "Joinplayer alive must ensure pointable = true")
    assert(props3.interaction_range == 4, "Joinplayer alive must restore interaction_range = 4")

    -- Case D: Player reconnects while dead (hp == 0): inventory items preserved intact
    local p_join4 = create_mock_player("DeadReconnectTester")
    p_join4:set_pos({ x = 230, y = 5, z = 230 })
    p_join4:set_hp(0)
    local inv4 = p_join4:get_inventory()
    inv4:set_stack("main", 1, rawget(_G, "ItemStack")("default:gold_ingot 32"))

    -- Player joins while dead
    core.on_joinplayer(p_join4)

    -- Inventory items must remain intact for game / mods
    local main_res4 = inv4:get_list("main")
    assert(main_res4 ~= nil and main_res4[1]:get_name() == "default:gold_ingot",
        "Dead player reconnect must preserve player inventory items intact")

    -- Player respawns: items remain untouched
    deathstats.reset_camera(p_join4)
    local respawn_main = inv4:get_list("main")
    assert(respawn_main ~= nil and respawn_main[1]:get_name() == "default:gold_ingot",
        "Respawn after dead reconnect leaves inventory untouched for game/mods")

    print("  [PASS] Joinplayer inventory & hand verification & restoration (in-memory, crash metadata, stuck hand purge, dead reconnect)")
end

--------------------------------------------------------------------------------
-- TEST 36: Userdata ItemStack Hand Stashing & Serialization Safety
--------------------------------------------------------------------------------
do
    print("\n--- TEST 36: Userdata ItemStack Hand Stashing & Serialization Safety ---")

    -- Helper to create a genuine Lua userdata with metatable mimicking Luanti C++ LuaItemStack
    local function create_mock_userdata_itemstack(str)
        local u = io.tmpfile()
        local item_obj = rawget(_G, "ItemStack")(str)
        debug.setmetatable(u, {
            __index = item_obj,
            __tostring = function() return item_obj:to_string() end,
        })
        return u
    end

    -- Verify that userdata throws error if passed directly to core.serialize
    local test_ud = create_mock_userdata_itemstack("default:sword_diamond 1 50")
    assert(type(test_ud) == "userdata", "Test object must be genuine userdata")
    local ok_ser = pcall(function() core.serialize(test_ud) end)
    assert(not ok_ser, "core.serialize must reject userdata with unsupported type error")

    -- Case A: Player dies with userdata ItemStacks in inventory and custom hand
    local p_ud = create_mock_player("UserdataDeathTester")
    p_ud:set_pos({ x = 300, y = 10, z = 300 })
    p_ud:set_hp(0)
    local inv_ud = p_ud:get_inventory()

    -- Populate with userdata ItemStacks (including empty slots)
    local main_list_ud = {
        create_mock_userdata_itemstack("default:sword_diamond 1 50"),
        create_mock_userdata_itemstack("default:pick_mese 1 100"),
        create_mock_userdata_itemstack(""), -- empty slot
        create_mock_userdata_itemstack("default:torch 64"),
    }
    inv_ud.lists["main"] = main_list_ud
    inv_ud.sizes["main"] = 4

    local offhand_list_ud = {
        create_mock_userdata_itemstack("default:shield_diamond 1 0"),
    }
    inv_ud.lists["offhand"] = offhand_list_ud
    inv_ud.sizes["offhand"] = 1

    local hand_stack_ud = create_mock_userdata_itemstack("custom_mod:heavy_hammer")
    inv_ud.lists["hand"] = { hand_stack_ud }
    inv_ud.sizes["hand"] = 1

    -- Trigger death camera stashing
    -- This MUST NOT raise "unsupported type: userdata"
    local death_ok, err_msg = pcall(function()
        deathstats.set_death_camera(p_ud)
    end)
    assert(death_ok, "set_death_camera must not throw error on userdata ItemStacks: " .. tostring(err_msg))

    -- Verify that deathstats leaves the player's main and offhand inventory completely intact for the game / mods
    assert(#inv_ud.lists["main"] == 4, "Main inventory must remain intact for game/mods")
    assert(inv_ud.lists["main"][1]:get_name() == "default:sword_diamond", "Main items must be preserved")
    assert(#inv_ud.lists["offhand"] == 1, "Offhand inventory must remain intact for game/mods")

    -- Check that metadata contains valid serialized string for hand with 0 userdata
    local meta_ud = p_ud:get_meta()
    local raw_hand = meta_ud:get_string("deathstats:stashed_hand")
    assert(raw_hand and raw_hand ~= "", "Hand stack must be persisted into metadata")
    local des_hand = core.deserialize(raw_hand)
    assert(des_hand.size == 1 and des_hand.stack == "custom_mod:heavy_hammer", "Hand stack must be preserved")

    -- Case B: Respawn cleanly restores custom hand
    deathstats.reset_camera(p_ud)

    local restored_hand_ud = inv_ud:get_stack("hand", 1)
    local restored_hand_name = (type(restored_hand_ud) == "table" and restored_hand_ud:get_name()) or restored_hand_ud
    assert(restored_hand_name == "custom_mod:heavy_hammer", "Custom hand restored")

    -- Case C: Dead player with completely EMPTY userdata inventory (all slots empty ItemStacks)
    -- Must not falsely mark as has_items or throw error
    local p_empty = create_mock_player("EmptyUserdataTester")
    p_empty:set_pos({ x = 310, y = 10, z = 310 })
    p_empty:set_hp(0)
    local inv_empty = p_empty:get_inventory()
    inv_empty.lists["main"] = {
        create_mock_userdata_itemstack(""),
        create_mock_userdata_itemstack(""),
        create_mock_userdata_itemstack(""),
    }
    inv_empty.sizes["main"] = 3
    inv_empty.lists["hand"] = { create_mock_userdata_itemstack("") }
    inv_empty.sizes["hand"] = 1

    local empty_ok, empty_err = pcall(function()
        deathstats.set_death_camera(p_empty)
    end)
    assert(empty_ok, "set_death_camera must succeed with empty userdata inventory: " .. tostring(empty_err))

    print("  [PASS] Userdata ItemStack hand stashing & serialization safety (0% userdata in serialize, zero inventory interference)")
end

--------------------------------------------------------------------------------
-- TEST 37: Dead Reconnect Post-Shutdown State Persistence (Corpse & Previous Run Statistics)
--------------------------------------------------------------------------------
do
    print("\n--- TEST 37: Dead Reconnect Post-Shutdown State Persistence (Corpse & Previous Run Statistics) ---")

    local p_recon = create_mock_player("ShutdownReconnectTester")
    p_recon:set_pos({ x = 75, y = 12, z = 75 })
    p_recon:set_properties({
        mesh = "character.b3d",
        textures = { "custom_character_skin.png" },
        visual_size = { x = 1, y = 1, z = 1 },
    })

    -- 1. Simulate run statistics before dying
    p_recon:set_hp(0)
    local data = deathstats.get_player_data(p_recon)
    data.current_run.blocks_mined = 25
    data.current_run.total_ores = 7
    data.current_run.damage_dealt = 85
    data.current_run.damage_taken = 30
    data.current_run.mobs_killed = 4
    data.current_run.items_crafted = 6

    -- 2. Player dies before server shutdown
    local death_info = {
        category = "mob",
        reason_text = "Slain by Dungeon Master",
        weapon = "Infernal Staff",
        funny_note = "Mastered the dungeon, failed the test.",
    }
    deathstats.record_player_death(p_recon, death_info)
    deathstats.set_death_camera(p_recon, death_info)

    -- Verify metadata was saved on initial death
    local meta = p_recon:get_meta()
    assert(meta:get_string("deathstats:death_active") == "1", "death_active must be 1")
    assert(meta:get_string("deathstats:last_life") ~= "", "last_life metadata must be saved")
    assert(meta:get_string("deathstats:corpse_data") ~= "", "corpse_data metadata must be saved")

    -- 3. Simulate total server shutdown / crash:
    -- Wipe in-memory Lua tables and all active world entities
    deathstats.players = {}
    deathstats.player_camera_data = {}
    deathstats.dead_players = {}

    -- Player reconnects with hp == 0 and transparent properties saved by engine
    p_recon:set_properties({
        textures = { "deathstats_transparent.png" },
        visual_size = { x = 0, y = 0, z = 0 },
        is_visible = false,
    })
    p_recon:set_hp(0)

    -- 4. Reconnect event occurs (joinplayer while dead)
    core.on_joinplayer(p_recon)

    -- 5. Verify corpse entity was recreated at exact death coordinates
    local reconnect_cam_data = deathstats.player_camera_data["ShutdownReconnectTester"]
    assert(reconnect_cam_data ~= nil, "Camera data must be initialized on reconnect")
    assert(reconnect_cam_data.corpse ~= nil and reconnect_cam_data.corpse.removed == false,
        "Corpse entity must be spawned and active on dead reconnect")
    assert(reconnect_cam_data.corpse.pos.x == 75 and reconnect_cam_data.corpse.pos.z == 75,
        "Corpse position must match exact death coordinates")
    assert(reconnect_cam_data.corpse:get_properties().textures ~= nil and reconnect_cam_data.corpse:get_properties().textures[1] == "custom_character_skin.png",
        "Corpse must inherit original player skin from metadata, never transparent texture")

    -- 6. Verify previous run statistics were completely preserved
    local restored_data = deathstats.players["ShutdownReconnectTester"]
    assert(restored_data ~= nil, "Player data must be restored on reconnect")
    assert(restored_data.last_life ~= nil, "last_life must be restored")
    assert(restored_data.last_life.blocks_mined == 25, "blocks_mined must be 25")
    assert(restored_data.last_life.total_ores == 7, "total_ores must be 7")
    assert(restored_data.last_life.damage_dealt == 85, "damage_dealt must be 85")
    assert(restored_data.last_life.damage_taken == 30, "damage_taken must be 30")
    assert(restored_data.last_life.mobs_killed == 4, "mobs_killed must be 4")
    assert(restored_data.last_life.items_crafted == 6, "items_crafted must be 6")
    assert(restored_data.last_life.last_cause == "Slain by Dungeon Master", "last_cause must match")

    -- 7. Verify death screen formspec presents the restored pre-shutdown statistics
    assert(core.last_formspec ~= nil and core.last_formspec.formname == "deathstats:death",
        "Death formspec must be presented on reconnect")
    assert(core.last_formspec.fs:find("Mined: 25 %(7 ores%)"),
        "Formspec must display 25 mined and 7 ores from before shutdown")
    assert(core.last_formspec.fs:find("Slain by Dungeon Master"),
        "Formspec must display exact fatal blow from before shutdown")

    -- 8. Verify lifetime deaths was not double-incremented
    assert(restored_data.lifetime.deaths == 1,
        "Reconnect must not double-increment lifetime.deaths counter")

    -- 9. Verify clean respawn clears metadata and removes corpse
    local reconnect_corpse_ref = reconnect_cam_data.corpse
    deathstats.on_player_respawn(p_recon)
    assert(meta:get_string("deathstats:death_active") == "", "death_active must be cleared on respawn")
    assert(reconnect_corpse_ref.removed == true, "Corpse entity must be removed on respawn")
    assert(deathstats.player_camera_data["ShutdownReconnectTester"] == nil, "Camera data must be cleaned up on respawn")

    print("  [PASS] Dead reconnect post-shutdown corpse & stats persistence (corpse spawned, skin restored, exact stats preserved, 0 duplicates)")
end

--------------------------------------------------------------------------------
-- TEST 38: Server Disconnect During Death Screen & Engine show_death_screen Reconnect
--------------------------------------------------------------------------------
do
    print("\n--- TEST 38: Server Disconnect During Death Screen & Engine show_death_screen Reconnect ---")

    local p_disc = create_mock_player("ServerShutdownPlayer")
    p_disc:set_pos({ x = 100, y = 20, z = 100 })

    -- 1. Player reaches 0 HP and simulate an extensive run before dying
    p_disc:set_hp(0)
    local data = deathstats.get_player_data(p_disc)
    data.current_run.blocks_mined = 142
    data.current_run.total_ores = 38
    data.current_run.damage_dealt = 550
    data.current_run.damage_taken = 95
    data.current_run.mobs_killed = 12
    data.current_run.players_killed = 2
    data.current_run.items_crafted = 24
    data.current_run.items_consumed = 8
    data.current_run.distance_traveled = 350.5

    -- 2. Player dies in the world
    local fatal_info = {
        category = "pvp",
        reason_text = "Slain by RivalKnight with Diamond Sword",
        weapon = "Diamond Sword",
        killer_name = "RivalKnight",
        funny_note = "A legendary duel remembered by the victor.",
    }
    deathstats.trigger_death_screen(p_disc, fatal_info)

    -- Assert death screen was triggered and stats saved
    local meta = p_disc:get_meta()
    assert(meta:get_string("deathstats:death_active") == "1", "death_active must be '1' while in death screen")
    assert(data.last_life.blocks_mined == 142, "last_life.blocks_mined must be 142")
    assert(data.last_life.total_ores == 38, "last_life.total_ores must be 38")
    assert(data.lifetime.deaths == 1, "lifetime.deaths must be 1")

    -- 3. Abrupt server disconnect / shutdown occurs while player is looking at the death screen!
    -- In-memory server tables are wiped (fresh server restart)
    deathstats.players = {}
    deathstats.dead_players = {}
    deathstats.player_camera_data = {}
    deathstats.active_huds = {}
    core.last_formspec = nil

    -- 4. Player reconnects to the newly started server with hp == 0
    p_disc:set_hp(0)

    -- Luanti engine builtin/game/death_screen.lua on_joinplayer executes:
    -- core.show_death_screen(player) WITHOUT is_reconnect parameter!
    core.show_death_screen(p_disc)

    -- 5. Verify stats from previous death are FULLY PERSISTED and NOT wiped
    local persisted_recon_data = deathstats.players["ServerShutdownPlayer"]
    assert(persisted_recon_data ~= nil, "Player data must exist on reconnect")
    assert(persisted_recon_data.last_life ~= nil, "last_life must not be nil")
    assert(persisted_recon_data.last_life.blocks_mined == 142,
        "blocks_mined must retain 142 from previous death, got: " .. tostring(persisted_recon_data.last_life.blocks_mined))
    assert(persisted_recon_data.last_life.total_ores == 38,
        "total_ores must retain 38 from previous death, got: " .. tostring(persisted_recon_data.last_life.total_ores))
    assert(persisted_recon_data.last_life.damage_dealt == 550,
        "damage_dealt must retain 550, got: " .. tostring(persisted_recon_data.last_life.damage_dealt))
    assert(persisted_recon_data.last_life.damage_taken == 95,
        "damage_taken must retain 95, got: " .. tostring(persisted_recon_data.last_life.damage_taken))
    assert(persisted_recon_data.last_life.mobs_killed == 12,
        "mobs_killed must retain 12, got: " .. tostring(persisted_recon_data.last_life.mobs_killed))
    assert(persisted_recon_data.last_life.players_killed == 2,
        "players_killed must retain 2, got: " .. tostring(persisted_recon_data.last_life.players_killed))
    assert(persisted_recon_data.last_life.items_crafted == 24,
        "items_crafted must retain 24, got: " .. tostring(persisted_recon_data.last_life.items_crafted))
    assert(persisted_recon_data.last_life.last_cause == "Slain by RivalKnight with Diamond Sword",
        "last_cause must retain exact kill credit from previous death")

    -- 6. Verify lifetime deaths counter was not double incremented on reconnect
    assert(persisted_recon_data.lifetime.deaths == 1,
        "lifetime.deaths must remain 1 after reconnecting to death screen, got: " .. tostring(persisted_recon_data.lifetime.deaths))

    -- 7. Verify the death formspec presents the restored stats
    assert(core.last_formspec ~= nil and core.last_formspec.formname == "deathstats:death",
        "Death screen formspec must be presented on reconnect")
    assert(core.last_formspec.fs:find("Mined: 142 %(38 ores%)"),
        "Formspec must display 142 mined (38 ores) from previous death")
    assert(core.last_formspec.fs:find("Slain by RivalKnight"),
        "Formspec must display death cause from previous death")

    -- 8. Respawn player and verify clean reset
    deathstats.on_player_respawn(p_disc)
    assert(meta:get_string("deathstats:death_active") == "", "death_active must be cleared after respawning")

    print("  [PASS] Server disconnect during death screen & engine show_death_screen reconnect persistence")
end

--------------------------------------------------------------------------------
-- TEST 39: Elastic "YOU DIED" Slap Animation Trajectory & Prominence
--------------------------------------------------------------------------------
do
    print("\n--- TEST 39: Elastic 'YOU DIED' Slap Animation Trajectory & Prominence ---")

    -- 1. Verify default configuration duration has been updated to 2.4s
    assert(deathstats.config.animation_duration == 2.4,
        "deathstats.config.animation_duration must default to 2.4 seconds, got: " .. tostring(deathstats.config.animation_duration))

    local target_w = -32.0
    local target_h = -23.0

    -- 2. Test progress = 0: starting distant scale (15% of target) and initial opacity stage
    local sx0, sy0, a0, impact0 = deathstats.calculate_slap_animation(0.0, target_w, target_h)
    assert(math.abs(sx0 - (target_w * 0.15)) < 0.001, "Scale at progress 0 must be 15% of target")
    assert(math.abs(sy0 - (target_h * 0.15)) < 0.001, "Scale at progress 0 must be 15% of target")
    assert(a0 == 60, "Initial alpha at progress 0 must be 60")
    assert(impact0 == false, "Impact must not be reached at progress 0")

    -- 3. Test progress = 0.35: peak prominent zoom-in overshoot (> 1.25x target, ~1.31x) and subtitle impact trigger
    local sx_peak, sy_peak, a_peak, impact_peak = deathstats.calculate_slap_animation(0.35, target_w, target_h)
    local zoom_ratio = sx_peak / target_w
    assert(zoom_ratio > 1.25, "Peak zoom ratio must be > 1.25x target scale for prominence, got: " .. tostring(zoom_ratio))
    assert(zoom_ratio < 1.35, "Peak zoom ratio must stay within reasonable bounds (< 1.35x), got: " .. tostring(zoom_ratio))
    assert(math.abs((sy_peak / target_h) - zoom_ratio) < 0.001, "Aspect ratio must be preserved during peak zoom")
    assert(a_peak == 255, "Alpha at peak zoom must be fully opaque (255)")
    assert(impact_peak == true, "Subtitles impact must trigger at or by progress 0.35")

    -- 4. Test progress = 0.75: recoil bounce undershoot (< 0.95x target, ~0.91x)
    local sx_bounce, sy_bounce, a_bounce, impact_bounce = deathstats.calculate_slap_animation(0.75, target_w, target_h)
    local bounce_ratio = sx_bounce / target_w
    assert(bounce_ratio < 0.95, "Recoil bounce must undershoot resting scale (< 0.95x), got: " .. tostring(bounce_ratio))
    assert(bounce_ratio > 0.85, "Recoil bounce must be stable (> 0.85x), got: " .. tostring(bounce_ratio))
    assert(math.abs((sy_bounce / target_h) - bounce_ratio) < 0.001, "Aspect ratio must be preserved during recoil bounce")
    assert(a_bounce == 255, "Alpha during recoil must be 255")
    assert(impact_bounce == true, "Impact must remain true during recoil")

    -- 5. Test progress = 1.0: exact convergence to resting target scale (1.000x)
    local sx1, sy1, a1, impact1 = deathstats.calculate_slap_animation(1.0, target_w, target_h)
    assert(math.abs(sx1 - target_w) < 0.001, "Final scale X must converge exactly to target_w, got: " .. tostring(sx1))
    assert(math.abs(sy1 - target_h) < 0.001, "Final scale Y must converge exactly to target_h, got: " .. tostring(sy1))
    assert(a1 == 255, "Final alpha must be 255")
    assert(impact1 == true, "Final impact must be true")

    print("  [PASS] Elastic 'YOU DIED' slap animation trajectory & prominence (2.4s, peak ~1.31x, bounce ~0.91x, exact 1.00x rest)")
end

-- ==========================================
-- TEST 40: Corpse Particle Spawners (Water, Lava, Fire, Impact)
-- ==========================================
do
    print("\n--- TEST 40: Corpse Particle Spawners (Water, Lava, Fire, Impact) ---")

    local test_pos = vector.new(50, 5, 50)

    -- 1. Detection of effect types across causes and environments
    assert(deathstats.get_corpse_effect_type(test_pos, { category = "drown" }) == "water",
        "Category drown must map to water effect")
    assert(deathstats.get_corpse_effect_type(test_pos, { category = "lava" }) == "lava",
        "Category lava must map to lava effect")
    assert(deathstats.get_corpse_effect_type(test_pos, { category = "fire" }) == "fire",
        "Category fire must map to fire effect")
    assert(deathstats.get_corpse_effect_type(test_pos, { category = "fall" }) == "impact",
        "Category fall must map to impact node particle effect")
    assert(deathstats.get_corpse_effect_type(test_pos, { category = "mob" }) == "impact",
        "Category mob must map to impact node particle effect")
    assert(deathstats.get_corpse_effect_type(test_pos, { category = "pvp" }) == "impact",
        "Category pvp must map to impact node particle effect")

    -- Node-based environment detection fallbacks
    core.world_nodes["50,5,50"] = "default:water_source"
    assert(deathstats.get_corpse_effect_type(test_pos, nil) == "water",
        "Corpse immersed in water_source must trigger water bubbles effect")
    core.world_nodes["50,5,50"] = "default:lava_source"
    assert(deathstats.get_corpse_effect_type(test_pos, nil) == "lava",
        "Corpse immersed in lava_source must trigger lava fire effect")
    core.world_nodes["50,5,50"] = "fire:basic_flame"
    assert(deathstats.get_corpse_effect_type(test_pos, nil) == "fire",
        "Corpse resting in fire must trigger smoke effect")
    core.world_nodes["50,5,50"] = "air"

    -- 2. Water (bubbles): continuous, upward buoyancy, animated 5x5 frames, modern + legacy
    local water_def = deathstats.create_corpse_particlespawner_def("water", test_pos)
    assert(water_def ~= nil, "Water definition must not be nil")
    assert(water_def.time == 0, "Water bubbles must be continuous (time = 0)")
    assert(water_def.amount == 8, "Water bubbles rate must be 8 per second")
    assert(water_def.texture == "deathstats_particle_bubble.png", "Water texture must be deathstats_particle_bubble.png")
    assert(water_def.animation and water_def.animation.type == "vertical_frames", "Water animation must be vertical_frames")
    assert(water_def.animation.aspect_w == 5 and water_def.animation.aspect_h == 5, "Water animation frames must be 5x5 px")
    assert(water_def.pos and water_def.pos.min and water_def.pos.max, "Modern pos range must be defined")
    assert(water_def.minpos and water_def.maxpos, "Legacy minpos/maxpos must be defined")
    assert(water_def.vel and water_def.vel.min.y > 0 and water_def.vel.max.y > 0, "Bubbles must move upwards (vel.y > 0)")
    assert(water_def.minvel and water_def.minvel.y > 0 and water_def.maxvel.y > 0, "Legacy minvel/maxvel must move upwards")
    assert(water_def.acc and water_def.acc.min.y > 0, "Bubbles must have buoyancy acceleration (acc.y > 0)")
    assert(water_def.texpool and #water_def.texpool > 0, "Modern texpool must be defined")

    -- 3. Lava (fire): continuous, glowing embers, leaping upwards, modern + legacy
    local lava_def = deathstats.create_corpse_particlespawner_def("lava", test_pos)
    assert(lava_def ~= nil, "Lava definition must not be nil")
    assert(lava_def.time == 0, "Lava fire must be continuous (time = 0)")
    assert(lava_def.glow == 14, "Lava fire must have maximum glow = 14")
    assert(lava_def.texture == "deathstats_particle_fire.png", "Lava texture must be deathstats_particle_fire.png")
    assert(lava_def.animation and water_def.animation.type == "vertical_frames", "Lava animation must be vertical_frames")
    assert(lava_def.animation.aspect_w == 5 and lava_def.animation.aspect_h == 5, "Lava animation frames must be 5x5 px")
    assert(lava_def.pos and lava_def.minpos, "Lava pos and minpos must both be defined")
    assert(lava_def.vel and lava_def.vel.max.y > lava_def.vel.min.y, "Lava velocity must span upwards")
    assert(lava_def.texpool and lava_def.texpool[1].blend == "add", "Lava texpool must use additive blend")

    -- 4. Fire (smoke): continuous, billowing upward convection, modern + legacy
    local fire_def = deathstats.create_corpse_particlespawner_def("fire", test_pos)
    assert(fire_def ~= nil, "Fire definition must not be nil")
    assert(fire_def.time == 0, "Fire smoke must be continuous (time = 0)")
    assert(fire_def.texture == "deathstats_particle_smoke.png", "Fire texture must be deathstats_particle_smoke.png")
    assert(fire_def.animation and fire_def.animation.type == "vertical_frames", "Fire animation must be vertical_frames")
    assert(fire_def.animation.aspect_w == 5 and fire_def.animation.aspect_h == 5, "Fire animation frames must be 5x5 px")
    assert(fire_def.pos and fire_def.minpos, "Smoke pos and minpos must both be defined")
    assert(fire_def.vel and fire_def.vel.min.y > 0, "Smoke velocity must be upward")
    assert(fire_def.acc and fire_def.acc.min.y > 0, "Smoke acceleration must rise")

    -- 5. Impact (all others): non-continuous impact burst, default node particles, customized gravity/speed
    core.world_nodes["50,4,50"] = "default:stone"
    local impact_def = deathstats.create_corpse_particlespawner_def("impact", test_pos)
    assert(impact_def ~= nil, "Impact definition must not be nil")
    assert(impact_def.time == 0.15, "Impact particles must be a short burst at moment of death (time = 0.15)")
    assert(impact_def.amount == 28, "Impact amount must be 28 shards")
    assert(impact_def.node and impact_def.node.name == "default:stone",
        "Impact node must be default:stone from ground below corpse")
    assert(impact_def.size and impact_def.size.min == 0 and impact_def.size.max == 0,
        "Impact size must be 0 for randomized node dig particle shards")
    assert(impact_def.minsize == 0 and impact_def.maxsize == 0,
        "Legacy minsize/maxsize must be 0 for node particle shards")
    assert(impact_def.vel and impact_def.vel.min.y > 0 and impact_def.vel.max.y > 0,
        "Impact particles must fly upwards (vel.y > 0)")
    assert(impact_def.acc and impact_def.acc.min.y == -9.81 and impact_def.acc.max.y == -9.81,
        "Impact acceleration must apply customized downward gravity (-9.81)")
    assert(impact_def.collisiondetection == true, "Impact particles must have collision detection")

    -- 6. Particle spawner invocation and lifecycle management
    core.active_particlespawners = {}
    local pids = deathstats.spawn_corpse_particles(test_pos, { category = "drown" })
    assert(#pids == 1, "spawn_corpse_particles must return array with 1 spawner ID")
    local spawner_id = pids[1]
    assert(core.active_particlespawners[spawner_id] ~= nil, "Active particle spawner must be registered in engine")
    assert(core.active_particlespawners[spawner_id].texture == "deathstats_particle_bubble.png",
        "Active spawner texture must match bubble particle")

    -- Clean up spawner
    core.delete_particlespawner(spawner_id)
    assert(core.active_particlespawners[spawner_id] == nil, "delete_particlespawner must remove spawner from engine")

    -- 7. Disabled setting toggle verification
    deathstats.config.enable_corpse_particles = false
    local empty_pids = deathstats.spawn_corpse_particles(test_pos, { category = "drown" })
    assert(#empty_pids == 0, "No particle spawners should spawn when enable_corpse_particles = false")
    deathstats.config.enable_corpse_particles = true

    -- 8. Verify camera orbit integration and automatic cleanup on release
    local mock_player = {
        name = "ParticleTester",
        get_player_name = function(self) return self.name end,
        is_player = function() return true end,
        is_valid = function() return true end,
        get_pos = function() return vector.new(10, 1, 10) end,
        get_look_horizontal = function() return 0 end,
        get_look_vertical = function() return 0 end,
        set_look_horizontal = function() end,
        set_look_vertical = function() end,
        set_detach = function() end,
        get_attach = function() return nil end,
        set_attach = function() end,
        set_properties = function() end,
        get_properties = function() return { textures = { "character.png" }, visual_size = { x = 1, y = 1 } } end,
        set_nametag_attributes = function() end,
        get_nametag_attributes = function() return { text = "ParticleTester", color = { a = 255, r = 255, g = 255, b = 255 } } end,
        set_armor_groups = function() end,
        get_armor_groups = function() return { fleshy = 100 } end,
        set_physics_override = function() end,
        get_physics_override = function() return { speed = 1, jump = 1, gravity = 1 } end,
        get_inventory = function()
            return {
                get_list = function() return {} end,
                get_size = function() return 0 end,
                set_size = function() end,
                set_stack = function() end,
                get_stack = function() return nil end,
                is_empty = function() return true end,
            }
        end,
        hud_add = function() return 1 end,
        hud_change = function() end,
        hud_remove = function() end,
        get_meta = function()
            local store = {}
            return {
                get_string = function(self, k) return store[k] or "" end,
                set_string = function(self, k, v) store[k] = v end,
            }
        end,
        get_children = function() return {} end,
    }

    core.active_particlespawners = {}
    deathstats.dead_players["ParticleTester"] = true
    deathstats.set_death_camera(mock_player, { category = "lava", reason_text = "Melted in lava" })
    local cdata = deathstats.player_camera_data["ParticleTester"]
    assert(cdata ~= nil, "Camera data must be established")
    assert(cdata.particle_spawners and #cdata.particle_spawners == 1,
        "Camera data must track active particle spawner ID")
    local active_pid = cdata.particle_spawners[1]
    assert(core.active_particlespawners[active_pid] ~= nil, "Engine must have active spawner running")
    assert(core.active_particlespawners[active_pid].texture == "deathstats_particle_fire.png",
        "Active spawner must be fire particle for lava death")

    -- Release camera (e.g. respawn) must delete particle spawner
    deathstats.reset_camera(mock_player)
    assert(deathstats.player_camera_data["ParticleTester"] == nil, "Camera data must be cleared on release")
    assert(core.active_particlespawners[active_pid] == nil, "Particle spawner must be cleanly deleted on release")

    -- 9. Texture asset files existence check
    local bubble_f = io.open("textures/deathstats_particle_bubble.png", "rb")
    assert(bubble_f ~= nil, "deathstats_particle_bubble.png texture must exist")
    bubble_f:close()

    local fire_f = io.open("textures/deathstats_particle_fire.png", "rb")
    assert(fire_f ~= nil, "deathstats_particle_fire.png texture must exist")
    fire_f:close()

    local smoke_f = io.open("textures/deathstats_particle_smoke.png", "rb")
    assert(smoke_f ~= nil, "deathstats_particle_smoke.png texture must exist")
    smoke_f:close()

    print("  [PASS] Corpse particle spawner effects (water bubbles, lava fire, smoke, node impact debris, lifecycle & textures)")
end

-- ==========================================
-- TEST 41: Starvation Detection (hbhunger, hudbars, stamina, set_hp, & priority)
-- ==========================================
do
    print("\n--- TEST 41: Starvation Detection (hbhunger, hudbars, stamina, set_hp) ---")

    local p_starve = {
        is_player = function() return true end,
        get_player_name = function() return "StarveTester" end,
        get_hp = function() return 0 end,
        set_hp = function() end,
        get_breath = function() return 10 end,
        get_pos = function() return { x = 0, y = 5, z = 0, node_name = "air" } end,
        get_velocity = function() return { x = 0, y = 0, z = 0 } end,
        get_properties = function() return { eye_height = 1.625 } end,
        get_inventory = function()
            local inv_store = {}
            return {
                get_list = function(self, listname) return inv_store[listname] or {} end,
                get_size = function(self, listname) return (inv_store[listname] and #inv_store[listname]) or 0 end,
                set_size = function(self, listname, sz) inv_store[listname] = inv_store[listname] or {} end,
                set_stack = function(self, listname, idx, stack)
                    inv_store[listname] = inv_store[listname] or {}
                    inv_store[listname][idx] = stack
                end,
                get_stack = function(self, listname, idx)
                    if inv_store[listname] and inv_store[listname][idx] then
                        return inv_store[listname][idx]
                    end
                    return { is_empty = function() return true end, get_count = function() return 0 end, get_name = function() return "" end }
                end,
                is_empty = function(self, listname)
                    return not inv_store[listname] or #inv_store[listname] == 0
                end,
            }
        end,
        get_meta = function()
            local store = {}
            return {
                get_string = function(self, k) return store[k] or "" end,
                set_string = function(self, k, v) store[k] = v end,
            }
        end,
    }

    -- 1. Verify deathstats.is_player_starving with hbhunger
    _G.hbhunger = {
        hunger = {
            ["StarveTester"] = 0,
        },
        SAT_MAX = 30,
        SAT_INIT = 20,
    }

    assert(deathstats.is_player_starving(p_starve) == true,
        "is_player_starving must return true when hbhunger.hunger is 0")

    _G.hbhunger.hunger["StarveTester"] = 1
    assert(deathstats.is_player_starving(p_starve) == true,
        "is_player_starving must return true when hbhunger.hunger is 1 (hbhunger damage threshold)")

    _G.hbhunger.hunger["StarveTester"] = 20
    assert(deathstats.is_player_starving(p_starve) == false,
        "is_player_starving must return false when hbhunger.hunger is 20")

    -- 2. Verify with hbhunger.get_hunger_raw
    _G.hbhunger.hunger["StarveTester"] = nil
    _G.hbhunger.get_hunger_raw = function(pl) return 0 end
    assert(deathstats.is_player_starving(p_starve) == true,
        "is_player_starving must return true when hbhunger.get_hunger_raw returns 0")

    _G.hbhunger.get_hunger_raw = function(pl) return 20 end
    assert(deathstats.is_player_starving(p_starve) == false,
        "is_player_starving must return false when hbhunger.get_hunger_raw returns 20")

    -- 3. Verify with hudbars (hb) registered & unregistered bar states (regression test for hudbars/init.lua:448)
    _G.hbhunger = nil
    local orig_hb = _G.hb
    _G.hb = {
        hudtables = {
            ["health"] = {
                hudstate = { ["StarveTester"] = { value = 20, max = 20 } }
            },
            ["breath"] = {
                hudstate = { ["StarveTester"] = { value = 10, max = 10 } }
            },
        },
        get_hudbar_state = function(pl, id)
            -- Replicates exact behavior of hudbars/init.lua:448 when bar is not in hudtables
            local tbl = _G.hb.hudtables[id]
            return tbl.hudstate[pl:get_player_name()] -- triggers error if tbl is nil
        end,
    }
    -- With only health and breath registered (satiation/hunger not registered), must NOT crash
    assert(deathstats.is_player_starving(p_starve) == false,
        "is_player_starving must gracefully handle hudbars when hunger/satiation is not registered")

    -- Now register satiation in hudtables with value <= 1
    _G.hb.hudtables["satiation"] = {
        hudstate = { ["StarveTester"] = { value = 0.5, max = 30 } }
    }
    assert(deathstats.is_player_starving(p_starve) == true,
        "is_player_starving must return true when hb satiation bar is <= 1")

    -- Set satiation > 1
    _G.hb.hudtables["satiation"].hudstate["StarveTester"].value = 18
    assert(deathstats.is_player_starving(p_starve) == false,
        "is_player_starving must return false when hb satiation bar is > 1")

    -- Animal attack simulation (like animalia mob attack dealing damage via punch)
    p_starve.get_hp = function() return 10 end
    local hp_res = core.on_player_hpchange(p_starve, -3, { type = "punch" })
    assert(hp_res == -3, "Animal punch must not crash and must pass through hp_change")
    _G.hb = orig_hb

    -- 4. Verify with stamina mod
    _G.stamina = {
        get = function(pl) return 0 end,
    }
    assert(deathstats.is_player_starving(p_starve) == true,
        "is_player_starving must return true when stamina.get is 0")
    _G.stamina.get = function(pl) return 20 end
    assert(deathstats.is_player_starving(p_starve) == false,
        "is_player_starving must return false when stamina.get is 20")
    _G.stamina = nil

    -- 5. Verify analyze_death with hbhunger and reason { type = "set_hp" } (actual hbhunger behavior)
    _G.hbhunger = {
        hunger = {
            ["StarveTester"] = 0,
        },
    }

    local hbhunger_death_reason = { type = "set_hp" }
    local analysis_hbhunger = deathstats.analyze_death(p_starve, hbhunger_death_reason)
    assert(analysis_hbhunger.category == "starve",
        "analyze_death must identify starve category when hbhunger player dies of set_hp")
    assert(analysis_hbhunger.reason_text == "Starved to death",
        "analyze_death reason_text must be 'Starved to death'")
    assert(analysis_hbhunger.funny_note ~= nil and #analysis_hbhunger.funny_note > 0,
        "analyze_death must supply a humorous epitaph for starvation")

    -- 6. Verify analyze_death when hbhunger is active but death was NOT from starvation (e.g. /kill with full hunger)
    _G.hbhunger.hunger["StarveTester"] = 20
    local kill_command_reason = { type = "set_hp" }
    local analysis_kill = deathstats.analyze_death(p_starve, kill_command_reason)
    assert(analysis_kill.category == "unknown",
        "analyze_death must NOT identify starve when set_hp occurs with full hunger")

    -- 7. Verify analyze_death with explicit reason tables from other mods
    _G.hbhunger.hunger["StarveTester"] = 0
    local explicit_starve = { type = "starve" }
    local analysis_exp = deathstats.analyze_death(p_starve, explicit_starve)
    assert(analysis_exp.category == "starve", "Explicit { type = 'starve' } must produce starve category")

    local stamina_starve = { type = "set_hp", cause = "stamina:starve" }
    local analysis_stam = deathstats.analyze_death(p_starve, stamina_starve)
    assert(analysis_stam.category == "starve", "stamina:starve cause must produce starve category")

    -- 8. Verify environmental fallback (reason is nil or empty table) when starving
    local analysis_nil = deathstats.analyze_death(p_starve, nil)
    assert(analysis_nil.category == "starve",
        "Environmental fallback must identify starve category when reason is nil and player is starving")

    local analysis_empty = deathstats.analyze_death(p_starve, {})
    assert(analysis_empty.category == "starve",
        "Environmental fallback must identify starve category when reason is {} and player is starving")

    -- 9. Hazard Priority: Fall, PvP, Lava, Drown must take precedence even if hunger is 0
    local fall_while_hungry = { type = "fall" }
    local analysis_fall_hungry = deathstats.analyze_death(p_starve, fall_while_hungry)
    assert(analysis_fall_hungry.category == "fall",
        "Fall damage must take precedence over hunger when reason.type == 'fall'")

    local burn_while_hungry = { type = "burn" }
    p_starve.get_pos = function() return { x = 0, y = 5, z = 0, node_name = "default:lava_source" } end
    local analysis_burn_hungry = deathstats.analyze_death(p_starve, burn_while_hungry)
    assert(analysis_burn_hungry.category == "lava",
        "Lava damage must take precedence over hunger when burning in lava")
    p_starve.get_pos = function() return { x = 0, y = 5, z = 0, node_name = "air" } end

    -- 10. Verify on_player_hpchange starvation tracking & race condition safety
    deathstats.recent_starvations["StarveTester"] = nil
    p_starve.get_hp = function() return 1 end
    core.on_player_hpchange(p_starve, -1, { type = "set_hp" })
    assert(deathstats.recent_starvations["StarveTester"] ~= nil,
        "on_player_hpchange must record timestamp in recent_starvations during starvation damage")

    -- Clear hbhunger hunger table simulating another mod resetting hunger in on_dieplayer early
    p_starve.get_hp = function() return 0 end
    _G.hbhunger.hunger["StarveTester"] = 20
    local analysis_race = deathstats.analyze_death(p_starve, { type = "set_hp" })
    assert(analysis_race.category == "starve",
        "recent_starvations timestamp must safely protect against race conditions where hunger was reset early")

    -- 11. Cleanup on player reset / respawn
    deathstats.reset_player_effects(p_starve)
    assert(deathstats.recent_starvations["StarveTester"] == nil,
        "reset_player_effects must cleanly purge recent_starvations")

    _G.hbhunger = nil

    print("  [PASS] Starvation detection & hbhunger integration (set_hp, fallback, priority, race immunity, cleanup)")
end

-- TEST 42: Bones Mod Settings Compatibility & Corpse Suppression
do
    print("\n--- TEST 42: Bones Mod Settings Compatibility & Corpse Suppression ---")

    -- 1. Helper: deathstats.get_bones_mode()
    core.loaded_mods["bones"] = nil
    core.settings:set("bones_mode", "bones")
    local should_show_bones, mode, has_mod = deathstats.get_bones_mode()
    assert(has_mod == false, "has_bones_mod must be false when bones mod is not loaded")
    assert(should_show_bones == false, "should_show_bones must be false when bones mod is not loaded")
    assert(mode == "bones", "mode must be bones")

    core.loaded_mods["bones"] = "/path/to/bones"
    core.settings:set("bones_mode", "bones")
    local show_b, mode_b, has_b = deathstats.get_bones_mode()
    assert(has_b == true, "has_bones_mod must be true when loaded_mods has bones")
    assert(mode_b == "bones", "mode must be 'bones'")
    assert(show_b == true, "should_show_bones must be true when bones_mode == 'bones'")

    core.settings:set("bones_mode", "drop")
    local show_d, mode_d = deathstats.get_bones_mode()
    assert(mode_d == "drop", "mode must be 'drop'")
    assert(show_d == false, "should_show_bones must be false when bones_mode == 'drop'")

    core.settings:set("bones_mode", "keep")
    local show_k, mode_k = deathstats.get_bones_mode()
    assert(mode_k == "keep", "mode must be 'keep'")
    assert(show_k == false, "should_show_bones must be false when bones_mode == 'keep'")

    -- 2. Corpse suppression when bones_mode == "bones":
    -- When player dies with bones_mode == "bones", deathstats must NOT spawn deathstats:corpse
    core.settings:set("bones_mode", "bones")
    local p_bones_user = create_mock_player("BonesUser")
    p_bones_user:set_pos({ x = 50, y = 10, z = 50 })
    p_bones_user:set_hp(0)

    deathstats.trigger_death_screen(p_bones_user, { type = "punch" })
    local cdata_bones = deathstats.player_camera_data["BonesUser"]
    assert(cdata_bones ~= nil, "Camera data must be initialized")
    assert(cdata_bones.expect_bones == true, "expect_bones must be true when bones_mode == 'bones'")
    assert(cdata_bones.corpse == nil, "Corpse entity must NOT be spawned when bones_mode == 'bones'")
    assert(cdata_bones.corpse_pos == nil, "corpse_pos must be nil when expecting bones")

    -- 3. Delayed bones placement: orbit locks onto bones, corpse remains nil
    local bones_node_pos = { x = 50, y = 10, z = 50 }
    core.set_node(bones_node_pos, { name = "bones:bones" })
    core.on_globalstep(0.1)

    assert(cdata_bones.has_bones == true, "has_bones must be detected by update_death_camera")
    assert(cdata_bones.bones_pos.x == 50 and cdata_bones.bones_pos.y == 10 and cdata_bones.bones_pos.z == 50,
        "bones_pos must match bones node coordinates")
    assert(cdata_bones.orbit_center.x == 50 and cdata_bones.orbit_center.y == 10 and cdata_bones.orbit_center.z == 50,
        "Orbit center must be centered directly on the bones node")
    assert(cdata_bones.corpse == nil, "Corpse entity must remain nil after bones placed")

    -- 4. Corpse purge: if a corpse entity existed, update_death_camera and aim_camera_at_bones immediately remove it
    local dummy_corpse_removed = false
    local dummy_corpse = {
        is_valid = function() return true end,
        remove = function() dummy_corpse_removed = true end,
    }
    cdata_bones.corpse = dummy_corpse
    cdata_bones.has_bones = false -- simulate before detection
    core.on_globalstep(0.1)
    assert(dummy_corpse_removed == true, "Existing corpse must be removed upon delayed bones detection")
    assert(cdata_bones.corpse == nil, "Corpse reference must be cleared")

    dummy_corpse_removed = false
    cdata_bones.corpse = dummy_corpse
    deathstats.aim_camera_at_bones(p_bones_user, bones_node_pos)
    assert(dummy_corpse_removed == true, "Existing corpse must be removed by aim_camera_at_bones")
    assert(cdata_bones.corpse == nil, "Corpse reference must be cleared by aim_camera_at_bones")

    -- 5. Fallback: when bones mod is absent, corpse IS spawned
    core.loaded_mods["bones"] = nil
    core.world_nodes = {}
    core.on_respawnplayer(p_bones_user)
    p_bones_user:set_hp(0)
    deathstats.set_death_camera(p_bones_user)
    local cdata_nobones = deathstats.player_camera_data["BonesUser"]
    assert(cdata_nobones ~= nil, "Camera data must exist")
    assert(cdata_nobones.expect_bones == false, "expect_bones must be false when bones mod is absent")
    assert(cdata_nobones.corpse ~= nil, "Corpse entity must be spawned when bones mod is not active")

    -- 6. Clean up
    core.on_respawnplayer(p_bones_user)
    core.settings:set("bones_mode", "bones")
    core.loaded_mods["bones"] = nil

    print("  [PASS] Bones mod settings compatibility, corpse suppression & bones fallback")
end

print("\nALL 42 TEST SUITES PASSED SUCCESSFULLY!")




