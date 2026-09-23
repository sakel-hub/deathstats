--[[
    deathstats - Cinematic Death Screen & Player Statistics Tracking
    Copyright (C) 2026 SaKeL

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation; either version 2.1 of the License, or
    (at your option) any later version.
--]]

local S = core.get_translator(core.get_current_modname())

-- ==========================================
-- Mob & Ore Entity Validation & Data Migration
-- ==========================================

--- Validate whether an entity is a genuine living mob (monster, animal, npc)
--- Rejects projectiles, falling nodes, items, boats/carts, and internal utility entities
---@param ent_name string Technical registered entity name
---@param ent_def table|nil Entity definition table
---@param ent_instance table|nil Living LuaEntity instance
---@return boolean is_mob True if the entity is a valid mob
function deathstats.is_mob_entity(ent_name, ent_def, ent_instance)
    if not ent_name or ent_name == "" then return false end
    ent_def = ent_def or core.registered_entities[ent_name]
    local low = ent_name:lower()

    -- Exclude engine built-in, internal and inanimate entities
    if low:find("^__builtin:") or low:find("^deathstats:") then
        return false
    end

    -- Exclude vehicles, itemframes, nametags, and signs
    if low:find("boat") or low:find("cart") or low:find("itemframe")
        or low:find("item_entity") or low:find("nametag") or low:find("sign")
        or low:find("display") or low:find("decoration") then
        return false
    end

    -- Exclude projectiles, ammunition, and weapons
    if low:find("arrow") or low:find("bullet") or low:find("bolt")
        or low:find("projectile") or low:find("missile") or low:find("laser")
        or low:find("bomb") or low:find("grenade") or low:find("tnt")
        or low:find("fireball") or low:find("snowball") or low:find("shot") then
        return false
    end

    -- Exclude dropped items
    if (ent_instance and ent_instance.itemstring) or (ent_def and ent_def.itemstring) then
        return false
    end

    -- Positive mob classifications (mobs_redo, creatura, animalia, petz, mobkit, native)
    if ent_def then
        if ent_def.type == "monster" or ent_def.type == "animal" or ent_def.type == "npc" or ent_def.type == "mob" then
            return true
        end
        if ent_def._csm_mob or ent_def.is_mob or ent_def._is_mob then
            return true
        end
    end
    if ent_instance then
        if ent_instance.type == "monster" or ent_instance.type == "animal" or ent_instance.type == "npc" or ent_instance.type == "mob" then
            return true
        end
        if ent_instance._csm_mob or ent_instance.is_mob or ent_instance._is_mob then
            return true
        end
    end

    -- Name heuristics (mobs_*, animal, monster, zombie, etc.)
    if low:find("mob") or low:find("monster") or low:find("animal") or low:find("creatura")
        or low:find("creature") or low:find("npc") or low:find("zombie") or low:find("skeleton")
        or low:find("spider") or low:find("creeper") or low:find("slime") or low:find("ghost")
        or low:find("golem") or low:find("dragon") or low:find("wolf") or low:find("bear") then
        return true
    end

    -- Living entity properties check (hp_max, health, etc.)
    local hp = (ent_instance and (ent_instance.health or ent_instance.hp))
        or (ent_def and (ent_def.health or ent_def.hp))
    local max_hp = (ent_instance and (ent_instance.hp_max or ent_instance.max_hp))
        or (ent_def and (ent_def.hp_max or ent_def.max_hp))
    if not max_hp and ent_def and ent_def.initial_properties then
        max_hp = ent_def.initial_properties.hp_max
    end
    if (hp and hp > 0) or (max_hp and max_hp > 0) then
        return true
    end

    return false
end


-- ==========================================
-- Death Reason Analysis & Humorous Epitaphs
-- ==========================================

-- Funny epitaph notes organized by death cause (all wrapped in S() for translation)
deathstats.funny_notes = {
    pvp = {
        S("Next time, try hitting THEM instead."),
        S("They say violence isn't the answer, but it certainly ended this debate."),
        S("Your combat strategy needs a complete restructuring."),
        S("Look on the bright side: at least their weapon has slightly more wear now."),
        S("Skill issue? Or just lag? We'll tell everyone it was lag."),
        S("Respawn, find them, and negotiate terms of surrender."),
        S("A tactical nap in the middle of battle is rarely effective."),
        S("You brought enthusiasm to a sword fight."),
        S("Your block button isn't just decorative."),
        S("PvP stands for Player versus Player, not Player versus Floor."),
        S("Have you tried moving out of the way of the sharp objects?"),
        S("They clearly had a better gaming chair."),
        S("Combat log: 0 hits landed, 1 dignity lost."),
        S("You fought bravely, until you immediately stopped doing that."),
        S("Did you drop your weapon or did you just surrender with style?"),
        S("Your opponent sends their heartfelt compliments for the free loot."),
        S("Maybe pacifism is your true calling."),
        S("You made a wonderful practice dummy for their combo."),
        S("A valiant effort, according to nobody who was watching."),
        S("They didn't even have to use their secondary weapon."),
        S("Next time, consider attacking while facing in their direction."),
        S("That wasn't a duel, that was an eviction notice."),
        S("Your armor looked very shiny right before it shattered."),
        S("Rumor has it they only used one hand to defeat you."),
        S("Tactical retreat was an option, just so you know."),
        S("You donated all your inventory to a very grateful warrior."),
        S("Critical hit! Unfortunately, it wasn't yours."),
        S("A legendary battle, remembered strictly by the victor."),
        S("You zigged when you definitely should have zagged."),
        S("Your health bar disappeared faster than your confidence."),
        S("Next time, try bringing armor with actual durability."),
        S("They thanked you for the target practice."),
        S("The duel was short, sweet, and entirely one-sided."),
        S("Combat tip: the pointy end goes into the OTHER player."),
        S("Respawning now. Time for an epic revenge plot, or another dirt nap."),
    },
    mob = {
        S("Local fauna remains unimpressed by your presence."),
        S("You were thoroughly outmaneuvered by a bunch of pixels."),
        S("Darwin would like to have a word with you."),
        S("You brought a tool to a monster fight."),
        S("The monsters are currently celebrating at the tavern."),
        S("Don't take it personally. They hate everyone equally."),
        S("Pro tip: running away is an ancient and honorable martial art."),
        S("Defeated by an enemy with a mob script shorter than a tweet."),
        S("The monsters didn't even break a sweat. Do monsters sweat?"),
        S("You were outsmarted by an opponent without a cerebral cortex."),
        S("They didn't just bite you, they insulted your entire lineage."),
        S("The local wildlife has voted you off the island."),
        S("Next time, light up the cave before taking a nap."),
        S("You are now officially part of the food chain, near the bottom."),
        S("Even the weakest critter in the dungeon is laughing right now."),
        S("Turns out monsters don't respect your personal space."),
        S("You cornered yourself. The monster was just doing its job."),
        S("Monster morale increased by 100%. Player morale decreased to 0%."),
        S("A creature with three lines of code just dismantled your career."),
        S("They heard you digging from three chunks away."),
        S("Did you try offering them a peaceful peace treaty?"),
        S("That beast will be bragging to its friends all weekend."),
        S("You tried to pet the danger, didn't you?"),
        S("Never bring a carrot to a monster showdown."),
        S("Your shield was in your inventory, cheering you on."),
        S("The dungeon boss is taking notes on how easily you fell."),
        S("Nature is healing, mostly by eliminating you."),
        S("Aggro radius: 10 meters. Survival radius: apparently 0 meters."),
        S("They swarmed you like shoppers on Black Friday."),
        S("You were defeated by something that cannot even open doors."),
        S("The monster didn't even need a critical hit."),
        S("Tip: swinging wildly into the darkness rarely hits the target."),
        S("They ate your lunch and then they ate your health points."),
        S("A glorious demise at the hands of a glorified polygon."),
        S("Next time, bring torches, armor, and maybe a bodyguard."),
    },
    fall = {
        S("It wasn't the fall that got you. It was the sudden stop at the bottom."),
        S("Gravity: 1. You: 0."),
        S("You believed you could fly. Physics respectfully disagreed."),
        S("Next time, pack a parachute or check the depth first."),
        S("High altitude sightseeing: 10/10. Landing: 0/10."),
        S("Look down before you step. Ancient wisdom, highly recommended."),
        S("Terminal velocity achieved. Unfortunately, so was terminal outcome."),
        S("The ground is the most undefeated opponent in history."),
        S("You just discovered a rapid underground transit method."),
        S("Newton sends his warmest mathematical regards."),
        S("That was not a shortcut, that was a cliff."),
        S("Next time, place water at the bottom BEFORE jumping."),
        S("You descended gracefully, right until the abrupt deceleration."),
        S("Gravity remains 100% reliable and completely unforgiving."),
        S("Cliff edges: they sneak up on you when you don't press sneak."),
        S("Congratulations on discovering the fastest way down."),
        S("The view was spectacular for about three seconds."),
        S("Parachute not found. Landing gear: nonexistent."),
        S("You thought the water was deep enough. It was 1 node deep."),
        S("Free falling is easy. Stopping safely is the hard part."),
        S("Physics called: your kinetic energy was fully absorbed by stone."),
        S("Next time, hold shift like your life depends on it. Because it does."),
        S("You tested the canyon's depth with your face."),
        S("An impressive swan dive with a catastrophic score on the landing."),
        S("The cliff did not move. You did."),
        S("Gravity is a harsh mistress with zero sense of humor."),
        S("You aimed for the hay bale and hit pure bedrock."),
        S("Pushed your luck over the ledge, and luck stepped aside."),
        S("Vertical exploration gone horribly wrong."),
        S("The ground welcomed you with open, solid cobblestone."),
        S("Did you trip over your own boots or was that deliberate?"),
        S("That was one giant leap for mankind, and zero survival for you."),
        S("Look on the bright side: you reached the bottom in record time."),
        S("Air resistance was insufficient to break your fall."),
        S("Next time, build stairs instead of taking the express elevator."),
    },
    lava = {
        S("Lava is not warm soup. Do not bathe in the forbidden salsa."),
        S("Crispy on the outside, thoroughly incinerated on the inside."),
        S("Diamonds are fireproof. You, unfortunately, are not."),
        S("You have officially become thermal energy for the ecosystem."),
        S("Hot take: molten rock is hot."),
        S("At least you don't have to worry about cold weather anymore."),
        S("The floor was literal lava and you lost the game."),
        S("A warm mineral bath, recommended by zero dermatologists."),
        S("You tested the swimming mechanics of liquid magma."),
        S("Diamonds mined: 8. Diamonds saved from the lava: 0."),
        S("That wasn't orange juice, but thanks for checking."),
        S("Cooking temperature: 1200 degrees. Doneness: completely vaporized."),
        S("Molten rock cares nothing for your enchanted armor."),
        S("You turned yourself into human fondue."),
        S("Digging straight down: classic, timeless, and completely fatal."),
        S("A spectacular glow, followed by absolute silence."),
        S("Water bucket was in hotbar slot 9. You pressed slot 8."),
        S("You took the term 'fire resistance' as a suggestion."),
        S("The volcano welcomes its latest voluntary offering."),
        S("One does not simply walk into molten lava and expect to survive."),
        S("Your gear went up in smoke before your body even hit the bottom."),
        S("Molten rock: the ultimate garbage disposal for reckless miners."),
        S("Liquid hot magma claims another brave, foolish adventurer."),
        S("You tried to bridge across without sneaking. Bold decision."),
        S("That sizzling sound was your entire inventory disappearing."),
        S("A hot bath sounded nice, but this exceeded expectations."),
        S("Instant cremation, zero paperwork required."),
        S("Next time, carry an obsidian bridge, not your best gear."),
        S("Molten rock has a 100% win rate against reckless miners."),
        S("You are now well-done. Actually, you are well beyond well-done."),
    },
    fire = {
        S("Stop, drop, and... oh, too late."),
        S("Playing with matches in a flammable universe. Bold strategy."),
        S("Smokey Bear is shaking his head in disappointment right now."),
        S("You lit up the room! Briefly. Very briefly."),
        S("Spontaneous human combustion: not just a myth anymore."),
        S("Fire is friendly right up until it touches your shirt."),
        S("You were the hottest thing in the cavern, literally."),
        S("Pyrotechnics display: spectacular. Survival rate: zero."),
        S("Did someone order extra crispy explorer?"),
        S("Flint and steel are tools, not toys. Lesson learned."),
        S("You ran around in circles hoping the flames would get dizzy."),
        S("A campfire is for cooking marshmallows, not yourself."),
        S("Fire safety tip: water extinguishes fire. Air feeds it."),
        S("You turned yourself into a human torch without the superpower part."),
        S("Burning calories is good; burning everything else is bad."),
        S("The heat was on, and you couldn't stand the kitchen."),
        S("Ash to ash, dust to dust, wooden house to a pile of rust."),
        S("Next time, check the wind direction before using a flint."),
        S("You danced with fire and fire won in the first round."),
        S("Smoke inhalation was just the preview; the flames were the feature."),
        S("Extinguisher not found. Dignity extinguished instead."),
        S("Friction caused sparks. Sparks caused fire. Fire caused respawn."),
        S("You were smokin' hot, but not in a flattering way."),
        S("Never try to hug a forest fire."),
        S("A warm campfire story, except you were the campfire."),
    },
    drown = {
        S("Humans need oxygen. Water has oxygen, but lungs don't do chemistry like that."),
        S("Sleeping with the digital fishes."),
        S("You forgot the golden rule: Breathe in, breathe out. Underwater: DO NOT."),
        S("Gills are not currently an unlockable perk on this server."),
        S("Submarine mode: Failed successfully."),
        S("Air bubbles: gone. Lung capacity: exceeded. Regrets: maximum."),
        S("Next time, look up before swimming down."),
        S("You found treasure, but forgot you needed oxygen to spend it."),
        S("Water is life, except when it fills your respiratory system."),
        S("Scuba gear is not craftable with cobblestone."),
        S("You tried to hold your breath until weekend. Unrealistic goal."),
        S("The surface was only three blocks away. Three very long blocks."),
        S("Fish swim. Rocks sink. You behaved remarkably like a rock."),
        S("Bubble counter reached zero. Panic levels reached maximum."),
        S("Deep sea diving without a breathing tube is rarely a long career."),
        S("Placing a door underwater was an option, just saying."),
        S("The ocean claims another sailor of dry land."),
        S("You drank too much of the ocean too quickly."),
        S("Deep diving is fun until the lights go out."),
        S("Aqua-aerobics class has been permanently cancelled."),
        S("Your lungs have formally filed a complaint against your navigation."),
        S("Water exploration: 10/10. Surface return journey: 0/10."),
        S("Swimming lessons are highly recommended for your next life."),
        S("You became an artificial reef in under two minutes."),
        S("Next time, come up for air before checking your inventory."),
    },
    suffocate = {
        S("Becoming one with the geology wasn't meant to be taken literally."),
        S("Gravel does not respect personal space boundaries."),
        S("Walls are meant for walking around, not phasing inside."),
        S("You discovered the interior decor of solid stone."),
        S("Sand has no concept of mercy or structural integrity."),
        S("Physics tip: two objects cannot occupy the same coordinate space."),
        S("You were deeply moved by the cave-in. Literally buried by it."),
        S("Gravel: the quietest assassin in the subterranean world."),
        S("A sudden collapse of geology and good decision-making."),
        S("You dug the ceiling and the ceiling hugged you back."),
        S("Suffocation: nature's way of telling you to carry a shovel."),
        S("You are now an honorary fossil for future archaeologists to discover."),
        S("Teleported straight into a solid wall. Quantum mechanics is tough."),
        S("Solid stone is very firm, opaque, and entirely unbreathable."),
        S("The mine collapsed, and so did your life expectations."),
        S("Never dig straight up. Every loading screen warned you."),
        S("Sand avalanches: sudden, silent, and suffocating."),
        S("You became load-bearing masonry for the mountain above."),
        S("The blocks above were just waiting for you to look up."),
        S("Burying your head in the sand: taken to its logical extreme."),
        S("Gravel drop: 100% accuracy, 0% breathable oxygen."),
        S("You found the center of the earth, from the inside of a stone block."),
        S("Next time, place a torch under falling gravel to survive."),
        S("Trapped between a rock and another, much heavier rock."),
        S("Solid masonry makes for a very poor blanket."),
    },
    starve = {
        S("You starved with an inventory full of cobblestone and regret."),
        S("Your stomach staged a swift and successful mutiny."),
        S("Forgot to eat? In this economy?!"),
        S("A sandwich would have prevented this entire tragic sequence."),
        S("The hunger bar is not a high score counter. Fill it up!"),
        S("You died on an empty stomach. Your grandmother is weeping."),
        S("All those diamonds and not a single loaf of bread to show for it."),
        S("Your digestive system has officially given up on you."),
        S("Nutritional deficiency level: catastrophic biological shutdown."),
        S("Next time, pack snacks before venturing into deep caverns."),
        S("Apples grow on trees. Trees were literally right above you."),
        S("You sprinted everywhere until your metabolism gave out."),
        S("Hunger strike successful: you are no longer hungry, or alive."),
        S("Even a zombie eats better than you did in this life."),
        S("You traded your lunch money for iron ingots."),
        S("Zero calories consumed. Zero life points remaining."),
        S("A single baked potato would have saved the world."),
        S("You ignored the grumbling stomach until it grumbled its last grumble."),
        S("Starvation in a world made of edible apples and wheat. Remarkable."),
        S("Diet plan review: 0 stars. Side effects included total demise."),
        S("Sprinting on an empty stomach: highly discouraged by doctors."),
        S("You had three stacks of cooked meat in a chest at home."),
        S("The hunger monster inside you won the ultimate argument."),
        S("Remember: food goes into the mouth, health goes up. Simple math."),
        S("You perished of malnutrition while surrounded by wild berries."),
        S("Sprinted a marathon, forgot to pack a sandwich."),
        S("Burned calories at Olympic speeds until none were left."),
        S("Ran until your stomach was completely empty."),
    },
    starve_sprint = {
        S("You sprinted everywhere until your metabolism gave out."),
        S("Sprinting on an empty stomach: highly discouraged by doctors."),
        S("Sprinted a marathon, forgot to pack a sandwich."),
        S("Burned calories at Olympic speeds until none were left."),
        S("Ran until your stomach was completely empty."),
    },
    thirst = {
        S("Water, water everywhere, nor any drop to drink."),
        S("You dried up faster than a puddle on scorching sand."),
        S("Dehydration level: 100%. Vitality level: 0%."),
        S("Forgot to drink? Even cacti manage to stay hydrated."),
        S("A single glass of water would have prevented this funeral."),
        S("You turned into a human mummy while staring at an ocean."),
        S("Your throat was drier than the desert at high noon."),
        S("Next time, bring a canteen instead of thirty iron ingots."),
        S("You ignored thirst until your bodily fluids resigned in protest."),
        S("Dehydration strikes again. Hydrate or diedrate!"),
        S("You carried five buckets of lava, but not one of water."),
        S("Dried out like an ancient raisin found behind the couch."),
        S("Your internal organs requested water. You gave them cobblestone."),
        S("Even fish know how to stay wet. Be more like fish."),
        S("Water fountain was ten meters away. Laziness level: lethal."),
        S("Hydro points hit zero. System shutdown inevitable."),
        S("You sprinted through the desert without a water flask."),
        S("Thirst took your life, but left your dignity equally parched."),
        S("Doctor's prescription: drink 8 cups of water a day, preferably while alive."),
        S("You turned to dust and blew away in the gentle breeze."),
        S("Total desiccation achieved. Achievement unlocked: Dried Sponge."),
        S("A canteen full of water weighs very little. Regret weighs a ton."),
        S("You fell victim to the ultimate summer heat wave."),
        S("Your tongue stuck to the roof of your mouth permanently."),
        S("Water is life. Literally."),
    },
    unknown = {
        S("Spontaneous biological failure. Cause: existence was too difficult."),
        S("The universe decided your subscription to life had expired."),
        S("Mistakes were made. Many of them."),
        S("Whatever happened, it looked painful from over here."),
        S("Press F to pay respects."),
        S("Even the coroner threw their hands up in confusion."),
        S("You somehow managed to break the laws of nature and health."),
        S("Cause of death: simply running out of hit points."),
        S("The game engine shrugs in profound bewilderment."),
        S("A mysterious end to an equally puzzling adventure."),
        S("It was a calculated risk, but math was never your strongest subject."),
        S("You ceased to function. Have you tried turning yourself off and on again?"),
        S("Not with a bang, but with a sudden, confusing whimper."),
        S("Whatever just happened, we're blaming it on lag."),
        S("Your character decided today was a good day to take a dirt nap."),
        S("An enigma wrapped in a mystery, covered in a death screen."),
        S("You encountered an unexpected error: Life.exe has stopped working."),
        S("The details are fuzzy, but the result is indisputably flat."),
        S("Even the server console doesn't know what you just did."),
        S("A tragic tale with no witness, no evidence, and no dignity."),
        S("You looked at danger and danger sneezed on you."),
        S("Some questions are better left unanswered. Like how you died just now."),
        S("A glitch in the matrix, or just exceptional clumsiness?"),
        S("The odds were one in a million. Unfortunately, you found the one."),
        S("You entered the room and the room decided you should leave."),
        S("Everything was going great until it immediately wasn't."),
        S("Your health bar took an early retirement."),
        S("Nobody saw anything, which is probably for the best."),
        S("A truly baffling sequence of unfortunate events."),
        S("Respawn, pretend it never happened, and never speak of it again."),
    },
    explosion = {
        S("You stood entirely too close to the fuse."),
        S("Next time, consider stepping away from the big red block."),
        S("Physics lesson: explosive decompression is non-negotiable."),
        S("KABOOM! That was quite an impressive firework display."),
        S("You thought you had enough time to run. You did not."),
        S("TNT stands for: Total Negligence Today."),
        S("Rapid unscheduled disassembly of your character."),
        S("You turned yourself into confetti. Happy celebration!"),
        S("The blast wave sends its warmest regards."),
        S("Standing on lit explosives: 0/10, would not recommend."),
    }
}

--- Pick a random humorous epitaph note for the given death category
---@param category string The death category identifier (e.g. "pvp", "mob", "fall", "lava", etc.)
---@return string note A randomized witty or humorous epitaph quote
function deathstats.get_funny_note(category)
    local list = deathstats.funny_notes[category] or deathstats.funny_notes.unknown
    return list[math.random(#list)]
end

--- Extract name and description from an ObjectRef (Player, LuaEntity, or projectile)
--- Resolves real shooting player if entity is an arrow or sword projectile
---@param obj ObjectRef The attacker object reference
---@return string name The killer's identifier or username
---@return boolean is_player True if the resolved attacker is a player
---@return string entity_desc The human-readable title of the killer
---@return string|nil projectile_name The projectile entity name if launched remotely
function deathstats.resolve_entity_info(obj)
    if not obj then return "Unknown", false, "Unknown", nil end

    -- Check if this object is a projectile fired by a player or mob
    local real_attacker, is_p, proj_name = deathstats.resolve_puncher_player(obj)
    if is_p and real_attacker and real_attacker:is_player() then
        local pname = real_attacker:get_player_name()
        return pname, true, pname, proj_name
    end

    if obj:is_player() then
        local pname = obj:get_player_name()
        return pname, true, pname, nil
    end

    local luaent = obj:get_luaentity()
    if luaent then
        local raw_name = luaent.name or "mob"
        local ent_def = core.registered_entities[raw_name]
        local desc = (ent_def and ent_def.description)
            or (luaent._mcl_entity_name)
            or deathstats.format_name(raw_name)
        return raw_name, false, desc, proj_name
    end

    return "Creature", false, "Creature", nil
end

--- Get current satiation / hunger metrics for a player across all supported hunger mods
--- Delegated to deathstats.compat_hunger.get_player_satiation
---@param player ObjectRef The player object
---@return number|nil current The current hunger/satiation points
---@return number|nil max The maximum hunger/satiation capacity
---@return number|nil ratio The normalized saturation ratio from 0.0 (empty) to 1.0 (full)
---@return string|nil mod_name The technical identifier of the detected hunger framework
---@return boolean is_starving True if hunger is at or below the framework's starvation damage threshold
function deathstats.get_player_satiation(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.get_player_satiation then
        return deathstats.compat_hunger.get_player_satiation(player)
    end
    return nil, nil, nil, nil, false
end

--- Check if a player is in a starving state (satiation/hunger depleted)
--- Seamlessly integrates with hbhunger, hudbars, stamina, hunger_ng, mcl_hunger, and classic hunger
---@param player ObjectRef The player object
---@return boolean is_starving True if hunger level is at or below starvation threshold
function deathstats.is_player_starving(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.is_player_starving then
        return deathstats.compat_hunger.is_player_starving(player)
    end
    local _, _, _, _, is_starving = deathstats.get_player_satiation(player)
    return is_starving == true
end

--- Get hydration status and metrics for a player from thirsty mod
--- Delegated to deathstats.compat_hunger.get_player_hydration
---@param player ObjectRef The player object
---@return number|nil current Current hydro points (0-20)
---@return number|nil max Maximum hydration (20)
---@return number|nil ratio Normalized hydration ratio (0.0 to 1.0)
---@return string|nil mod_name Mod identifier ("thirsty")
---@return boolean is_dehydrated True if hydro points <= 0
function deathstats.get_player_hydration(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.get_player_hydration then
        return deathstats.compat_hunger.get_player_hydration(player)
    end
    return nil, nil, nil, nil, false
end

--- Check if player is dehydrated (thirst hydro depleted)
---@param player ObjectRef
---@return boolean
function deathstats.is_player_dehydrated(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.is_player_dehydrated then
        return deathstats.compat_hunger.is_player_dehydrated(player)
    end
    local _, _, _, _, is_dehydrated = deathstats.get_player_hydration(player)
    return is_dehydrated == true
end

--- Check if player was recently sprinting or sprint-stamina exhausted
--- Supports hbsprint, sprint_lite, unified_stamina, stamina
---@param player ObjectRef
---@return boolean
function deathstats.is_player_sprint_exhausted(player)
    if deathstats.compat_hunger and deathstats.compat_hunger.is_player_sprint_exhausted then
        return deathstats.compat_hunger.is_player_sprint_exhausted(player)
    end
    return false
end

--- Deep environmental and state inspection fallback when engine reason table is nil or incomplete
--- Checks recent combat punches, falling velocity, surrounding nodes (lava, water, suffocation, fall, out-of-world)
---@param player ObjectRef The deceased player object
---@return table analysis The deduced death information table
function deathstats.inspect_surroundings_fallback(player)
    local pos = player:get_pos()
    local name = player:get_player_name()
    local eye_height = 1.625
    local props = player:get_properties()
    if props and props.eye_height then
        eye_height = props.eye_height
    end

    local head_pos = vector.new(pos.x, pos.y + eye_height, pos.z)
    local node_feet = core.get_node(pos)
    local node_head = core.get_node(head_pos)

    -- Check recent PvP or Mob punch / projectile strike (within 3.5 seconds)
    local last_punch = deathstats.recent_punches[name]
    if last_punch and (core.get_gametime() - last_punch.time <= 3.5) then
        local attacker_name = last_punch.attacker_name
        local is_player = last_punch.is_player
        local attacker_desc = last_punch.attacker_desc
        if not attacker_name and last_punch.hitter then
            attacker_name, is_player, attacker_desc = deathstats.resolve_entity_info(last_punch.hitter)
        end
        attacker_name = attacker_name or "Unknown"
        attacker_desc = attacker_desc or attacker_name
        local cat = is_player and "pvp" or "mob"
        local wep = last_punch.tool_desc or "Bare Hands"
        if last_punch.projectile then
            wep = deathstats.format_projectile_name(last_punch.projectile)
        end
        local text = is_player
            and string.format("Slain by %s using %s", attacker_name, wep)
            or string.format("Slain by %s", attacker_desc)
        return {
            category = cat,
            killer_name = attacker_name,
            is_player = is_player,
            weapon = wep,
            reason_text = text,
            funny_note = deathstats.get_funny_note(cat),
        }
    end

    -- Check out-of-world fall (below mapgen bounds)
    if pos.y < -30000 then
        return {
            category = "unknown",
            reason_text = S("Fell out of the world"),
            funny_note = deathstats.get_funny_note("unknown"),
        }
    end

    -- Check recent explosion blast (within 4.0s and blast radius + 6 blocks)
    local exp_blast_pos = nil
    if pos and deathstats.recent_explosions then
        local now = core.get_gametime()
        local best_dist = 20.0
        for _, exp in ipairs(deathstats.recent_explosions) do
            if (now - exp.time) <= 4.0 then
                local dist = vector.distance(exp.pos, pos)
                if dist < best_dist and dist <= ((exp.radius or 3) + 6.0) then
                    best_dist = dist
                    exp_blast_pos = vector.copy(exp.pos)
                end
            end
        end
    end
    local lb = deathstats.last_blow and deathstats.last_blow[name]
    if not exp_blast_pos and lb and lb.blast_pos then
        exp_blast_pos = vector.copy(lb.blast_pos)
    end
    if exp_blast_pos then
        return {
            category = "explosion",
            reason_text = S("Blown up by an explosion"),
            blast_pos = exp_blast_pos,
            funny_note = deathstats.get_funny_note("explosion"),
        }
    end

    -- Check lava immersion
    if node_feet.name:find("lava") or node_head.name:find("lava") then
        return {
            category = "lava",
            reason_text = S("Melted in searing lava"),
            funny_note = deathstats.get_funny_note("lava"),
        }
    end

    -- Check fire / burning
    if node_feet.name:find("fire") or node_head.name:find("fire") then
        return {
            category = "fire",
            reason_text = S("Burned to ashes"),
            funny_note = deathstats.get_funny_note("fire"),
        }
    end

    -- Check drowning (head submerged in water or liquid with no breath)
    local breath = player:get_breath()
    local in_water = node_head.name:find("water") or core.get_item_group(node_head.name, "water") ~= 0
    if in_water or (breath and breath <= 0) then
        return {
            category = "drown",
            reason_text = S("Drowned in deep water"),
            funny_note = deathstats.get_funny_note("drown"),
        }
    end

    -- Check suffocation (head buried inside solid opaque node)
    local head_def = core.registered_nodes[node_head.name]
    if head_def and head_def.walkable and head_def.drawtype == "normal" and not node_head.name:find("air") then
        return {
            category = "suffocate",
            reason_text = S("Suffocated inside @1", deathstats.format_name(node_head.name)),
            funny_note = deathstats.get_funny_note("suffocate"),
        }
    end

    -- Check high downward velocity recorded just before death
    local fall_speed = deathstats.recent_falls[name] or 0
    if fall_speed < -12.0 then
        return {
            category = "fall",
            reason_text = S("Fell from a high place"),
            funny_note = deathstats.get_funny_note("fall"),
        }
    end

    -- Check dehydration / thirst (thirsty mod)
    local was_dehydrated = deathstats.is_player_dehydrated(player)
        or (deathstats.recent_dehydrations[name] and (core.get_gametime() - deathstats.recent_dehydrations[name] <= 3.5))
    if was_dehydrated then
        return {
            category = "thirst",
            reason_text = S("Died of dehydration"),
            funny_note = deathstats.get_funny_note("thirst"),
        }
    end

    -- Check starvation (hbhunger, stamina, hunger_ng, hudbars, or inventory hunger)
    local was_starving = deathstats.is_player_starving(player)
        or (deathstats.recent_starvations[name] and (core.get_gametime() - deathstats.recent_starvations[name] <= 3.5))
    if was_starving then
        local note
        if deathstats.is_player_sprint_exhausted(player) then
            note = deathstats.get_funny_note("starve_sprint") or deathstats.get_funny_note("starve")
        else
            note = deathstats.get_funny_note("starve")
        end
        return {
            category = "starve",
            reason_text = S("Starved to death"),
            funny_note = note,
        }
    end

    -- Fallback unknown
    return {
        category = "unknown",
        reason_text = S("Died from mysterious causes"),
        funny_note = deathstats.get_funny_note("unknown"),
    }
end

--- Describe elevation/depth zone for the death location
---@param y number|nil The vertical elevation
---@return string depth_desc Human-readable depth or altitude description
function deathstats.get_depth_description(y)
    if not y then return S("Unknown Altitude") end
    if y >= 1000 then
        return S("Upper Atmosphere")
    elseif y >= 500 then
        return S("Sky Realm")
    elseif y >= 10 then
        return S("Highlands / Surface")
    elseif y >= -10 then
        return S("Sea Level")
    elseif y >= -200 then
        return S("Shallow Caverns")
    elseif y >= -1000 then
        return S("Deep Underground")
    elseif y >= -5000 then
        return S("Abyssal Depths")
    else
        return S("The Void")
    end
end

--- Get biome name at a given 3D position
---@param pos Vector|nil The position to query
---@return string biome_name Clean formatted biome name
function deathstats.get_biome_at_pos(pos)
    if not pos then return S("Unknown") end
    if core.get_biome_data then
        local bdata = core.get_biome_data(pos)
        if bdata and bdata.biome and core.get_biome_name then
            local bname = core.get_biome_name(bdata.biome)
            if bname and bname ~= "" then
                return deathstats.format_name(bname)
            end
        end
    end
    -- Fallback to elevation context
    if pos.y < -10 then
        return S("Underground")
    elseif pos.y > 100 then
        return S("Sky")
    else
        return S("Wilderness")
    end
end

--- Enrich death analysis table with coordinates, depth, biome, killer HP and fall metrics
---@param res table Death analysis table
---@param player ObjectRef The player who died
---@param puncher ObjectRef|nil Optional killer entity or puncher
---@return table enriched The enriched death analysis table
function deathstats.enrich_death_info(res, player, puncher)
    -- Handle argument swap if called as enrich_death_info(player, res, puncher)
    if (res and res.is_player and (not player or not player.is_player))
       or (res and res.get_player_name and (not player or not player.get_player_name)) then
        local tmp = res
        res = player
        player = tmp
    end
    if not res then res = {} end
    if puncher then
        res.puncher = res.puncher or puncher
    end
    local pname = player and player.get_player_name and player:get_player_name()

    -- Location, Depth & Biome
    if not res.pos and player and player.get_pos then
        local pos = player:get_pos()
        if pos then
            res.pos = vector.round(pos)
            res.depth_desc = deathstats.get_depth_description(pos.y)
            res.biome_name = deathstats.get_biome_at_pos(pos)
        end
    elseif res.pos and not res.depth_desc then
        res.depth_desc = deathstats.get_depth_description(res.pos.y)
        res.biome_name = res.biome_name or deathstats.get_biome_at_pos(res.pos)
    end
    if res.pos then
        res.death_pos = res.pos
        res.coords_str = string.format("(X: %d, Y: %d, Z: %d)", res.pos.x, res.pos.y, res.pos.z)
    end

    -- Killer Remaining Health (PvP and PvE Mob)
    local is_pvp = (res.category == "pvp" or res.category == "player" or res.type == "pvp" or res.type == "player")
    local is_mob = (res.category == "mob" or res.is_mob or res.type == "mob")
    local kname = res.killer_name or res.killer
    if is_pvp then
        local kplayer = (res.puncher and res.puncher.is_player and res.puncher:is_player() and res.puncher)
            or (kname and core.get_player_by_name(kname))
        if kplayer and kplayer:is_player() then
            res.killer_hp = math.max(0, kplayer:get_hp())
            local props = kplayer.get_properties and kplayer:get_properties()
            res.killer_max_hp = (props and props.hp_max) or 20
            res.killer_hp_max = res.killer_max_hp
        else
            local last_punch = pname and deathstats.recent_punches[pname]
            if last_punch and last_punch.attacker_hp then
                res.killer_hp = last_punch.attacker_hp
                res.killer_max_hp = last_punch.attacker_max_hp or 20
                res.killer_hp_max = res.killer_max_hp
            end
        end
    elseif is_mob or res.puncher or res.attacker then
        local kattacker = res.puncher or res.attacker
        if kattacker and (not kattacker.is_player or not kattacker:is_player()) then
            local luaent = kattacker.get_luaentity and kattacker:get_luaentity()
            local hp = (luaent and (luaent.health or luaent.hp))
                or (kattacker.get_hp and kattacker:get_hp())
            local max_hp = (luaent and (luaent.hp_max or luaent.max_hp))
            if not max_hp and kattacker.get_properties then
                local props = kattacker:get_properties()
                max_hp = props and props.hp_max
            end
            if hp and hp > 0 then
                res.killer_hp = math.max(0, math.floor(hp + 0.5))
                res.killer_max_hp = math.max(1, math.floor((max_hp or hp) + 0.5))
                res.killer_hp_max = res.killer_max_hp
            end
        end
        if not res.killer_hp then
            local last_punch = pname and deathstats.recent_punches[pname]
            if last_punch and last_punch.attacker_hp then
                res.killer_hp = last_punch.attacker_hp
                res.killer_max_hp = last_punch.attacker_max_hp or 20
                res.killer_hp_max = res.killer_max_hp
            end
        end
        if res.killer_hp then
            res.killer_health = res.killer_hp
        end
    end

    -- Fall Height & Impact Speed
    if res.category == "fall" then
        local peak_y = deathstats.fall_peaks and pname and deathstats.fall_peaks[pname]
        local dpos = res.pos or (player.get_pos and player:get_pos())
        if peak_y and dpos then
            res.fall_height = math.max(1, math.floor(peak_y - dpos.y + 0.5))
        end
        local recent_v = deathstats.recent_falls and pname and deathstats.recent_falls[pname]
        local lb = deathstats.last_blow and pname and deathstats.last_blow[pname]
        local vy = (lb and lb.velocity and lb.velocity.y) or recent_v
        if vy and math.abs(vy) > 0.5 then
            res.fall_speed = math.abs(math.floor(vy * 10 + 0.5) / 10)
            if not res.fall_height and res.fall_speed > 0 then
                res.fall_height = math.max(1, math.floor((res.fall_speed * res.fall_speed) / 19.62 + 0.5))
            end
        end
        if not res.fall_height and res.damage and res.damage > 0 then
            res.fall_height = math.max(1, math.floor(res.damage + 3))
            res.fall_speed = math.floor(math.sqrt(2 * 9.81 * res.fall_height) * 10 + 0.5) / 10
        elseif res.fall_height and (not res.fall_speed or res.fall_speed <= 0) then
            res.fall_speed = math.floor(math.sqrt(2 * 9.81 * res.fall_height) * 10 + 0.5) / 10
        end
    end

    return res
end

--- Main Death Cause Analyzer: parses engine death reason metadata or invokes environmental inspection
---@param player ObjectRef The deceased player object
---@param reason table|nil The engine reason table from on_dieplayer or show_death_screen
---@return table analysis The complete death metadata table (category, reason_text, killer_name, weapon, funny_note)
function deathstats.analyze_death(player, reason)
    if not player then
        return {
            category = "unknown",
            reason_text = S("Died"),
            funny_note = deathstats.get_funny_note("unknown"),
        }
    end
    local res = deathstats.analyze_death_raw(player, reason)
    return deathstats.enrich_death_info(res, player)
end

--- Internal raw death cause analyzer
---@param player ObjectRef The deceased player object
---@param reason table|nil The engine reason table from on_dieplayer or show_death_screen
---@return table analysis The un-enriched death metadata table
function deathstats.analyze_death_raw(player, reason)
    local pname = player:get_player_name()

    -- If reason is already an analyzed death_info table with reason_text
    if reason and type(reason) == "table" and reason.reason_text then
        local res = {}
        for k, v in pairs(reason) do res[k] = v end
        if not res.funny_note then
            res.funny_note = deathstats.get_funny_note(res.category or "unknown")
        end
        return res
    end

    -- If reason table is provided and valid
    if reason and type(reason) == "table" and (reason.type or reason.hunger or reason.thirst or reason.cause) then
        local rtype = reason.type or (reason.hunger and "starve") or (reason.thirst and "thirst") or "set_hp"

        -- EXPLOSION DAMAGE
        local is_exp_reason = (rtype == "explosion" or rtype == "explode"
            or (reason.node and reason.node:find("tnt"))
            or (reason.cause and tostring(reason.cause):lower():find("explos")))
        local ppos = player.get_pos and player:get_pos()
        local exp_blast_pos = nil
        if ppos and deathstats.recent_explosions then
            local now = core.get_gametime()
            local best_dist = 20.0
            for _, exp in ipairs(deathstats.recent_explosions) do
                if (now - exp.time) <= 4.0 then
                    local dist = vector.distance(exp.pos, ppos)
                    if dist < best_dist and dist <= ((exp.radius or 3) + 6.0) then
                        best_dist = dist
                        exp_blast_pos = vector.copy(exp.pos)
                    end
                end
            end
        end
        local lb = deathstats.last_blow and deathstats.last_blow[pname]
        if not exp_blast_pos and lb and lb.blast_pos then
            exp_blast_pos = vector.copy(lb.blast_pos)
        end
        if not exp_blast_pos and reason and (reason.pos or reason.origin) then
            exp_blast_pos = vector.copy(reason.pos or reason.origin)
        end

        if is_exp_reason or (rtype == "set_hp" and exp_blast_pos) then
            return {
                category = "explosion",
                reason_text = S("Blown up by an explosion"),
                blast_pos = exp_blast_pos,
                funny_note = deathstats.get_funny_note("explosion"),
            }
        end

        -- PUNCH / KILL COMBAT
        if rtype == "punch" or rtype == "kill" then
            local attacker = reason.object
            if attacker then
                local killer_name, is_player, killer_desc, proj_name = deathstats.resolve_entity_info(attacker)
                local weapon_desc = "Bare Hands"

                if proj_name then
                    weapon_desc = deathstats.format_projectile_name(proj_name)
                elseif is_player then
                    local real_att = attacker:is_player() and attacker or core.get_player_by_name(killer_name)
                    if real_att and real_att:is_player() then
                        local wielded = real_att:get_wielded_item()
                        local iname = wielded and wielded:get_name()
                        if iname and iname ~= "" then
                            weapon_desc = deathstats.format_name(iname)
                        end
                    end
                end

                -- Fallback to recent punches if weapon was bare hands or hit by projectile
                local last_punch = deathstats.recent_punches[pname]
                if last_punch and (core.get_gametime() - last_punch.time <= 3.5) then
                    if last_punch.projectile then
                        weapon_desc = deathstats.format_projectile_name(last_punch.projectile)
                    elseif weapon_desc == "Bare Hands" and last_punch.tool_desc and last_punch.tool_desc ~= "Bare Hands" then
                        weapon_desc = last_punch.tool_desc
                    end
                end

                local cat = is_player and "pvp" or "mob"
                local reason_text = is_player
                    and string.format("Slain by %s using %s", killer_name, weapon_desc)
                    or string.format("Slain by %s", killer_desc)

                return {
                    category = cat,
                    killer_name = killer_name,
                    killer_desc = killer_desc,
                    is_player = is_player,
                    weapon = weapon_desc,
                    reason_text = reason_text,
                    funny_note = deathstats.get_funny_note(cat),
                }
            end
        end

        -- FALL DAMAGE
        if rtype == "fall" then
            return {
                category = "fall",
                reason_text = S("Fell from a high place"),
                funny_note = deathstats.get_funny_note("fall"),
            }
        end

        -- DROWNING
        if rtype == "drown" then
            return {
                category = "drown",
                reason_text = S("Drowned in deep water"),
                funny_note = deathstats.get_funny_note("drown"),
            }
        end

        -- BURNING
        if rtype == "burn" then
            local pos = player:get_pos()
            local node = core.get_node(pos)
            if node.name:find("lava") then
                return {
                    category = "lava",
                    reason_text = S("Melted in searing lava"),
                    funny_note = deathstats.get_funny_note("lava"),
                }
            end
            return {
                category = "fire",
                reason_text = S("Burned to ashes"),
                funny_note = deathstats.get_funny_note("fire"),
            }
        end

        -- NODE DAMAGE (Cactus, Spikes, Poison etc.)
        if rtype == "node_damage" and reason.node then
            local node_name = deathstats.format_name(reason.node)
            local cat = "unknown"
            if reason.node:find("lava") then
                cat = "lava"
            elseif reason.node:find("fire") then
                cat = "fire"
            elseif reason.node:find("cactus") then
                cat = "mob"
            end
            return {
                category = cat,
                reason_text = S("Pricked or wounded by @1", node_name),
                funny_note = deathstats.get_funny_note(cat),
            }
        end

        -- DEHYDRATION / THIRST (thirsty mod or explicit thirst reason)
        local was_dehydrated = deathstats.is_player_dehydrated(player)
            or (deathstats.recent_dehydrations[pname] and (core.get_gametime() - deathstats.recent_dehydrations[pname] <= 3.5))
        if rtype == "thirst" or rtype == "dehydrate"
            or (reason.thirst ~= nil)
            or (reason.cause and (tostring(reason.cause):find("thirst") or tostring(reason.cause):find("dehydrat")))
            or (rtype == "set_hp" and was_dehydrated) then
            return {
                category = "thirst",
                reason_text = S("Died of dehydration"),
                funny_note = deathstats.get_funny_note("thirst"),
            }
        end

        -- STARVATION (explicit reason type or cause from hunger mods e.g. stamina, mcl_hunger, hunger_ng)
        local was_starving = deathstats.is_player_starving(player)
            or (deathstats.recent_starvations[pname] and (core.get_gametime() - deathstats.recent_starvations[pname] <= 3.5))
        if rtype == "starve" or rtype == "hunger"
            or (reason.hunger and tostring(reason.hunger):find("starve"))
            or (reason.cause and (tostring(reason.cause):find("starve") or tostring(reason.cause):find("hunger")))
            or (rtype == "set_hp" and was_starving) then
            local note
            if deathstats.is_player_sprint_exhausted(player) then
                note = deathstats.get_funny_note("starve_sprint") or deathstats.get_funny_note("starve")
            else
                note = deathstats.get_funny_note("starve")
            end
            return {
                category = "starve",
                reason_text = S("Starved to death"),
                funny_note = note,
            }
        end
    end

    -- Fallback: reason was nil or unknown, inspect physical state & surroundings
    return deathstats.inspect_surroundings_fallback(player)
end
