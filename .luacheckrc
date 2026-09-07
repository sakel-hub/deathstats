unused_args = false
allow_defined_top = true
max_line_length = false

exclude_files = {
    "./scripts",
    "./bin",
    "./logs",
    "./node_modules",
    "./sounds",
    "./textures",
    "./models",
    "./docs",
    "./locale",
    "./types",
    "./scratch",
}

globals = {
    "deathstats",
    "core.show_death_screen",
    "minetest.show_death_screen",
    "hb",
}

read_globals = {
    "DIR_DELIM", "INIT",

    "minetest", "core",
    "dump", "dump2",

    "Raycast",
    "Settings",
    "PseudoRandom",
    "PerlinNoise",
    "VoxelManip",
    "SecureRandom",
    "VoxelArea",
    "PerlinNoiseMap",
    "PcgRandom",
    "ItemStack",
    "AreaStore",
    "unpack",
    "vector",
    "bit",

    table = {
        fields = {
            "copy",
            "indexof",
            "insert_all",
            "key_value_swap",
            "shuffle",
        }
    },

    string = {
        fields = {
            "split",
            "trim",
        }
    },

    math = {
        fields = {
            "hypot",
            "sign",
            "factorial",
            "round",
        }
    },

    "default",
    "player_api",
    "mcl_core",
    "mcl_player",
    "mcl_mobs",
    "mobs",
    "mobs_redo",
    "creatura",
    "animalia",
    "x_bows",
    "x_obsidianmese",
    "armor",
    "skins",
    "wardrobe",
    "clothing",
    "vl_tuning",
    "mcl_gamerules",
    "mcl_skins",
}
