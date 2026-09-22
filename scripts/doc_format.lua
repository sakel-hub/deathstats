-- luacheck: globals export
-- scripts/doc_format.lua
-- Compact Markdown documentation generator for deathstats via lua-language-server
local util = require 'utility'
local jsonb = require 'json-beautify'

export.serializeAndExport = function(docs, outputDir)
    local jsonPath = outputDir .. '/doc.json'
    local mdPath = outputDir .. '/doc.md'

    -- Export standard JSON AST
    local old_support = jsonb.supportSparseArray
    jsonb.supportSparseArray = true
    local jsonOk, jsonErr = util.saveFile(jsonPath, jsonb.beautify(docs))
    jsonb.supportSparseArray = old_support

    -- Build compact, structured Markdown
    local lines = {}
    local function emit(str)
        table.insert(lines, str or "")
    end

    emit("# DeathStats API Reference")
    emit("")
    emit("Cinematic death screen, ragdoll physics simulation, grave epitaphs, lifetime statistics tracking, and tactical live scoreboard for Luanti.")
    emit("")

    -- Table of Contents
    emit("## Table of Contents")
    emit("")
    emit("- [Classes & Data Structures](#classes--data-structures)")
    emit("- [Type Aliases & Callbacks](#type-aliases--callbacks)")
    emit("- [Core & Lifecycle API](#core--lifecycle-api)")
    emit("- [Statistics & Storage API](#statistics--storage-api)")
    emit("- [Death Analysis & Attribution API](#death-analysis--attribution-api)")
    emit("- [Ragdoll & Terrain Physics API](#ragdoll--terrain-physics-api)")
    emit("- [Corpse Entities & Visuals API](#corpse-entities--visuals-api)")
    emit("- [Cinematic Camera Orbit API](#cinematic-camera-orbit-api)")
    emit("- [Particle Effects API](#particle-effects-api)")
    emit("- [Formspecs & UI Dossier API](#formspecs--ui-dossier-api)")
    emit("- [Live Scoreboard HUD API](#live-scoreboard-hud-api)")
    emit("- [Registries & State Tables](#registries--state-tables)")
    emit("")
    emit("---")
    emit("")

    -- Categorize documentation items
    local classes = {}
    local aliases = {}
    local functions = {}
    local variables = {}

    for _, item in ipairs(docs) do
        local name = item.name
        if not name and item.defines and item.defines[1] then
            name = item.defines[1].view
        end

        local def1 = item.defines and item.defines[1]
        local file = (def1 and def1.file) or ""
        local is_foreign = file:find("^%[FOREIGN%]") or file:find("Luanti%.app") or file:find("builtin")

        -- Filter out foreign library definitions, internal engine overrides, and private fields
        local is_valid = name and name ~= "LuaLS"
            and not is_foreign
            and not name:find("^core%.")
            and not name:find("^minetest%.")
            and not name:find("%.%_")
            and not name:find("^deathstats%.[^%.]+%.")
        if is_valid then
            if item.type == "type" and name ~= "deathstats" then
                if def1 and def1.type == "doc.alias" then
                    table.insert(aliases, item)
                else
                    table.insert(classes, item)
                end
            elseif def1 and (def1.view == "function"
                or (def1.extends and def1.extends.type == "function")) then
                table.insert(functions, item)
            elseif name ~= "deathstats" then
                table.insert(variables, item)
            end
        end
    end

    table.sort(classes, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(aliases, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(functions, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(variables, function(a, b) return (a.name or "") < (b.name or "") end)

    -- Classes
    emit("## Classes & Data Structures")
    emit("")
    for _, cls in ipairs(classes) do
        local cname = cls.name or (cls.defines and cls.defines[1] and cls.defines[1].view) or "Unknown"
        emit("### `" .. cname .. "`")
        emit("")
        if cls.desc and cls.desc ~= "" then
            emit(cls.desc)
            emit("")
        end

        if cls.fields and #cls.fields > 0 then
            emit("| Field | Type | Description |")
            emit("| :--- | :--- | :--- |")
            local seen_fields = {}
            for _, field in ipairs(cls.fields) do
                local fname = field.name
                local is_private = fname and fname:find("^_")
                if fname and not seen_fields[fname] and not is_private then
                    seen_fields[fname] = true
                    local ftype = (field.extends and field.extends.view) or "any"
                    ftype = ftype:gsub("|", "\\|")
                    local fdesc = (field.desc or ""):gsub("\n", " "):gsub("|", "\\|")
                    emit(string.format("| `%s` | `%s` | %s |", fname, ftype, fdesc))
                end
            end
            emit("")
        end
    end

    emit("---")
    emit("")

    -- Type Aliases
    if #aliases > 0 then
        emit("## Type Aliases & Callbacks")
        emit("")
        emit("| Type Alias | Signature / Definition |")
        emit("| :--- | :--- |")
        for _, alias in ipairs(aliases) do
            local aname = alias.name or (alias.defines and alias.defines[1] and alias.defines[1].view) or "Unknown"
            local def1 = alias.defines and alias.defines[1]
            local sig = (def1 and def1.view) or "any"
            sig = sig:gsub("|", "\\|")
            emit(string.format("| `%s` | `%s` |", aname, sig))
        end
        emit("")
        emit("---")
        emit("")
    end

    -- Helper to render a function entry
    local function render_func(fn)
        local fname = fn.name or (fn.defines and fn.defines[1] and fn.defines[1].name)
        local def = fn.defines and fn.defines[1]
        local ext = def and def.extends

        emit("#### `" .. tostring(fname) .. "`")
        emit("")

        local desc = (def and def.rawdesc) or (fn.desc) or ""
        -- Strip any trailing raw enum code block that LuaLS appends to rawdesc
        if desc:find("\n\n```lua") then
            desc = desc:sub(1, desc:find("\n\n```lua") - 1)
        end
        desc = desc:gsub("^%s+", ""):gsub("%s+$", "")

        if desc ~= "" then
            emit(desc)
            emit("")
        end

        -- Signature
        if ext and ext.view then
            emit("```lua")
            emit(ext.view)
            emit("```")
            emit("")
        end

        -- Parameters
        if ext and ext.args and #ext.args > 0 then
            emit("**Parameters:**")
            emit("")
            for _, arg in ipairs(ext.args) do
                local aname = arg.name or "?"
                local atype = arg.view or "any"
                local adesc = arg.desc or arg.rawdesc or ""
                if adesc ~= "" then
                    emit(string.format("* `%s` (`%s`): %s", aname, atype, adesc))
                else
                    emit(string.format("* `%s` (`%s`)", aname, atype))
                end
            end
            emit("")
        end

        -- Returns
        if ext and ext.returns then
            local rets = ext.returns
            if rets.type then rets = {rets} end
            if #rets > 0 then
                emit("**Returns:**")
                emit("")
                for _, ret in ipairs(rets) do
                    local rname = ret.name
                    local rtype = ret.view or "any"
                    local rdesc = ret.desc or ret.rawdesc or ""
                    if rname and rname ~= "" then
                        if rdesc ~= "" then
                            emit(string.format("* `%s` (`%s`): %s", rname, rtype, rdesc))
                        else
                            emit(string.format("* `%s` (`%s`)", rname, rtype))
                        end
                    else
                        if rdesc ~= "" then
                            emit(string.format("* `%s`: %s", rtype, rdesc))
                        else
                            emit(string.format("* `%s`", rtype))
                        end
                    end
                end
                emit("")
            end
        end
    end

    -- Group Functions
    local groups = {
        {
            title = "Core & Lifecycle API",
            desc = "Lifecycle management, death screen initialization, respawn handling, player effect clearing, and audio cues.",
            match = function(n)
                return n:find("trigger_death") or n:find("respawn") or n:find("reset_player_effects")
                    or n:find("clear_death_hud") or n:find("is_player_online") or n:find("is_player_dead")
                    or n:find("zero_player_velocity") or n:find("play_death_sound")
                    or n:find("reset_player_activity") or n:find("standalone_huds")
            end
        },
        {
            title = "Statistics & Storage API",
            desc = "Player lifetime achievement dossiers, ModStorage persistence, stat counters, formatting utilities, and data migration.",
            match = function(n)
                return n:find("load_player_stats") or n:find("save_player_stats") or n:find("get_player_data")
                    or n:find("record_player_death") or n:find("create_empty_stats") or n:find("format_time")
                    or n:find("format_number") or n:find("format_compact_number") or n:find("format_name")
                    or n:find("get_stack_name") or n:find("is_stack_empty") or n:find("stack_to_string")
                    or n:find("inventory_list") or n:find("migrate_ores") or n:find("cleanup_invalid_mobs")
                    or n:find("get_last_death_info") or n:find("record_explosion") or n:find("truncate_str")
                    or n:find("random_float") or n:find("safe_normalize")
            end
        },
        {
            title = "Death Analysis & Attribution API",
            desc = "Cause-of-death heuristics, environmental inspection, killer entity resolution, hunger/thirst integration, depth/biome context, and humorous epitaphs.",
            match = function(n)
                return n:find("analyze_death") or n:find("enrich_death") or n:find("funny_note")
                    or n:find("is_mob_entity") or n:find("resolve_entity_info") or n:find("resolve_puncher")
                    or n:find("biome") or n:find("depth") or n:find("inspect_surroundings")
                    or n:find("satiation") or n:find("starving") or n:find("hydration") or n:find("dehydrated")
                    or n:find("sprint_exhausted") or n:find("format_projectile")
            end
        },
        {
            title = "Ragdoll & Terrain Physics API",
            desc = "Procedural ragdoll kinematics, impulse forces, bounce restitution, terrain slope detection, downhill rolling, wall clearance, and ground support probing.",
            match = function(n)
                return n:find("impulse") or n:find("bounce") or n:find("slope") or n:find("downhill")
                    or n:find("hanging_legs") or n:find("wall_behind") or n:find("corpse_clearance")
                    or n:find("ground_support") or n:find("ground_elevation") or n:find("fallback_ground")
                    or n:find("soft_node") or n:find("impact_sound") or n:find("bones")
                    or n:find("liquid") or n:find("ground_surface") or n:find("ambient_light")
                    or n:find("pose_elevation") or n:find("pose_selectionbox") or n:find("settle_corpse")
                    or n:find("settle_ragdoll") or n:find("flight_limbs") or n:find("slide_limbs")
            end
        },
        {
            title = "Corpse Entities & Visuals API",
            desc = "Corpse entity lifecycle, appearance inheritance across skin mods, bone posing, limb fractures, 3D wield items, and arrow transfers.",
            match = function(n)
                return n:find("spawn_and_setup_corpse") or n:find("dissolve_corpse") or n:find("remove_corpse")
                    or n:find("pose_corpse") or n:find("rotate_corpse") or n:find("fracture_corpse")
                    or n:find("get_corpse") or n:find("arrows") or n:find("dropped")
                    or n:find("wield_item") or n:find("visuals")
            end
        },
        {
            title = "Cinematic Camera Orbit API",
            desc = "360-degree circular camera orbit, non-physical camera anchor, raycast obstacle clearance, bones targeting, and HUD suppression.",
            match = function(n)
                return n:find("camera") or n:find("orbit") or n:find("hudbars")
                    or n:find("hook_animation") or n:find("engine_player_attached")
                    or n:find("inventory_and_hand")
            end
        },
        {
            title = "Particle Effects API",
            desc = "Thematic death particle spawners (lava sparks, fire smoke, water bubbles, fly swarm), ground impact dust bursts, and decay dissolution puffs.",
            match = function(n)
                return n:find("particle") or n:find("tile_texture") or n:find("impact_burst")
            end
        },
        {
            title = "Formspecs & UI Dossier API",
            desc = "Interactive formspec interfaces for death summary cards, photo mode overlay, corpse epitaph inspection plaque, and lifetime achievement statistics.",
            match = function(n)
                return n:find("show_death_formspec") or n:find("show_photo_mode")
                    or n:find("show_corpse_epitaph") or n:find("show_lifetime_stats")
                    or n:find("show_lifetime_formspec") or n:find("banner_responsive")
                    or n:find("slap_animation")
            end
        },
        {
            title = "Live Scoreboard HUD API",
            desc = "Tactical multiplayer live scoreboard, pluggable custom columns API, real-time metrics calculation, ping/AFK status, and full roster dialog.",
            match = function(n)
                return n:find("scoreboard") or n:find("player_score") or n:find("hall_of_fame")
                    or n:find("gametime") or n:find("survival_time") or n:find("armor_points")
                    or n:find("player_ping") or n:find("ping_color") or n:find("ping_textcolor")
                    or n:find("is_player_afk") or n:find("get_player_hp") or n:find("window_size")
                    or n:find("format_column_headers") or n:find("format_player_row")
                    or n:find("get_player_row_cells")
            end
        }
    }

    local assigned = {}
    for _, grp in ipairs(groups) do
        emit("## " .. grp.title)
        emit("")
        emit(grp.desc)
        emit("")
        for _, fn in ipairs(functions) do
            local fn_name = fn.name or ""
            if not assigned[fn_name] and grp.match(fn_name) then
                assigned[fn_name] = true
                render_func(fn)
            end
        end
        emit("---")
        emit("")
    end

    -- Remaining functions
    local remaining = {}
    for _, fn in ipairs(functions) do
        local fn_name = fn.name or ""
        if not assigned[fn_name] then
            table.insert(remaining, fn)
        end
    end
    if #remaining > 0 then
        emit("## Miscellaneous Functions")
        emit("")
        for _, fn in ipairs(remaining) do
            render_func(fn)
        end
        emit("---")
        emit("")
    end

    -- Registries & State Tables
    emit("## Registries & State Tables")
    emit("")
    emit("| Registry / Table | Type | Description |")
    emit("| :--- | :--- | :--- |")
    for _, var in ipairs(variables) do
        local vname = var.name or ""
        local def = var.defines and var.defines[1]
        local vtype = (def and def.extends and def.extends.view) or (def and def.view) or "table"
        vtype = vtype:gsub("|", "\\|")
        local vdesc = (def and def.rawdesc) or (var.desc) or ""
        vdesc = vdesc:gsub("\n", " "):gsub("|", "\\|")
        emit(string.format("| `%s` | `%s` | %s |", vname, vtype, vdesc))
    end
    emit("")

    local content = table.concat(lines, "\n")
    local mdOk, mdErr = util.saveFile(mdPath, content)

    if not (jsonOk and mdOk) then
        return false, {jsonPath, mdPath}, {jsonErr, mdErr}
    end

    return true, {jsonPath, mdPath}
end
