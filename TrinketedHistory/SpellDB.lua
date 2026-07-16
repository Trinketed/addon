---------------------------------------------------------------------------
-- ArenaBlackBox: SpellDB.lua
-- Curated spell metadata for TBC/Wrath arena-relevant spells.
-- CC categorization is handled by DRList-1.0 — this covers everything else:
-- offensive_cd, defensive_cd, interrupt, trinket, healing_cd, mobility,
-- dispel, utility, cc_break, racial
---------------------------------------------------------------------------

-- cat = category string used in event enrichment
-- dur = buff/effect duration (seconds) where relevant
-- cd  = base cooldown (seconds) — for cooldown polling reference

SPELL_DB = {

    -- =================================================================
    -- PVP TRINKET / CC BREAK
    -- =================================================================
    [42292] = { cat = "trinket",      cd = 120, name = "PvP Trinket" },
    [18499] = { cat = "cc_break",     cd = 30,  dur = 10, name = "Berserker Rage" },

    -- =================================================================
    -- RACIALS
    -- All racials use cat = "racial" so they group under one filter and
    -- show with the gold accent on the timeline. RACE_COOLDOWNS in
    -- ReplayEngine.lua maps race → spellID for the CD tracker.
    -- =================================================================
    [7744]  = { cat = "racial", cd = 120, name = "Will of the Forsaken" },     -- Undead
    [20589] = { cat = "racial", cd = 105, name = "Escape Artist" },            -- Gnome
    [20594] = { cat = "racial", cd = 180, dur = 8,   name = "Stoneform" },     -- Dwarf
    [20600] = { cat = "racial", cd = 180, dur = 20,  name = "Perception" },    -- Human
    [20549] = { cat = "racial", cd = 90,  dur = 0.5, name = "War Stomp" },     -- Tauren
    [28730] = { cat = "racial", cd = 120, name = "Arcane Torrent" },           -- Blood Elf
    [26297] = { cat = "racial", cd = 180, dur = 15,  name = "Berserking" },    -- Troll
    [20572] = { cat = "racial", cd = 120, dur = 15,  name = "Blood Fury" },    -- Orc
    [58984] = { cat = "racial", cd = 120, name = "Shadowmeld" },               -- Night Elf (TBC ID may be 20580 — verify)
    [28880] = { cat = "racial", cd = 180, dur = 15,  name = "Gift of the Naaru" }, -- Draenei

    -- =================================================================
    -- WARRIOR — OFFENSIVE
    -- =================================================================
    [1719]  = { cat = "offensive_cd", cd = 1800, dur = 15, name = "Recklessness" },
    [12292] = { cat = "offensive_cd", cd = 180,  dur = 30, name = "Death Wish" },
    [5246]  = { cat = "offensive_cd", cd = 180,  name = "Intimidating Shout" },
    [20252] = { cat = "offensive_cd", cd = 30,   name = "Intercept" },
    [12809] = { cat = "offensive_cd", cd = 45,   name = "Concussion Blow" },
    [676]   = { cat = "offensive_cd", cd = 60,   name = "Disarm" },
    [46924] = { cat = "offensive_cd", cd = 90,   dur = 6, name = "Bladestorm" },

    -- WARRIOR — DEFENSIVE
    [871]   = { cat = "defensive_cd", cd = 1800, dur = 10, name = "Shield Wall" },
    [20230] = { cat = "defensive_cd", cd = 1800, dur = 15, name = "Retaliation" },
    [12975] = { cat = "defensive_cd", cd = 480,  dur = 20, name = "Last Stand" },
    [23920] = { cat = "defensive_cd", cd = 10,   dur = 5,  name = "Spell Reflection" },
    [3411]  = { cat = "defensive_cd", cd = 30,   name = "Intervene" },

    -- WARRIOR — INTERRUPT
    [6552]  = { cat = "interrupt", cd = 10, dur = 4, name = "Pummel" },
    [72]    = { cat = "interrupt", cd = 12, dur = 6, name = "Shield Bash" },

    -- =================================================================
    -- PALADIN — OFFENSIVE
    -- =================================================================
    [31884] = { cat = "offensive_cd", cd = 180, dur = 20, name = "Avenging Wrath" },
    [10308] = { cat = "offensive_cd", cd = 60,  name = "Hammer of Justice" },
    [20066] = { cat = "offensive_cd", cd = 60,  name = "Repentance" },
    [20216] = { cat = "offensive_cd", cd = 120, name = "Divine Favor" },

    -- PALADIN — DEFENSIVE
    [642]   = { cat = "defensive_cd", cd = 300, dur = 12, name = "Divine Shield" },
    [498]   = { cat = "defensive_cd", cd = 300, dur = 8,  name = "Divine Protection" },
    [10278] = { cat = "defensive_cd", cd = 300, dur = 10, name = "Blessing of Protection" },
    [1044]  = { cat = "defensive_cd", cd = 25,  dur = 6,  name = "Blessing of Freedom" },
    [27148] = { cat = "defensive_cd", cd = 30,  dur = 30, name = "Blessing of Sacrifice" },
    [27154] = { cat = "defensive_cd", cd = 3600, name = "Lay on Hands" },

    -- PALADIN — HEALING
    [20473] = { cat = "healing_cd",   cd = 6,   name = "Holy Shock" },

    -- =================================================================
    -- HUNTER — OFFENSIVE
    -- =================================================================
    [19574] = { cat = "offensive_cd", cd = 120, dur = 18, name = "Bestial Wrath" },
    [3045]  = { cat = "offensive_cd", cd = 300, dur = 15, name = "Rapid Fire" },
    [23989] = { cat = "offensive_cd", cd = 300, name = "Readiness" },
    [19503] = { cat = "offensive_cd", cd = 30,  name = "Scatter Shot" },
    [19577] = { cat = "offensive_cd", cd = 60,  name = "Intimidation" },
    [27068] = { cat = "offensive_cd", cd = 120, name = "Wyvern Sting" },
    [53209] = { cat = "offensive_cd", cd = 10,  name = "Chimera Shot" },
    [60053] = { cat = "offensive_cd", cd = 3,   name = "Explosive Shot" },

    -- HUNTER — DEFENSIVE
    [19263] = { cat = "defensive_cd", cd = 300, dur = 10, name = "Deterrence" },
    [5384]  = { cat = "defensive_cd", cd = 30,  name = "Feign Death" },
    [34477] = { cat = "utility",      cd = 30,  name = "Misdirection" },

    -- HUNTER — INTERRUPT
    [34490] = { cat = "interrupt", cd = 20, dur = 3, name = "Silencing Shot" },
    [14311] = { cat = "offensive_cd", cd = 30, name = "Freezing Trap" },

    -- =================================================================
    -- ROGUE — OFFENSIVE
    -- =================================================================
    [2094]  = { cat = "offensive_cd", cd = 180, name = "Blind" },
    [14185] = { cat = "offensive_cd", cd = 600, name = "Preparation" },
    [13750] = { cat = "offensive_cd", cd = 300, dur = 15, name = "Adrenaline Rush" },
    [13877] = { cat = "offensive_cd", cd = 120, dur = 15, name = "Blade Flurry" },
    [14177] = { cat = "offensive_cd", cd = 180, name = "Cold Blood" },
    [51690] = { cat = "offensive_cd", cd = 120, dur = 2, name = "Killing Spree" },
    [51713] = { cat = "offensive_cd", cd = 60,  dur = 10, name = "Shadow Dance" },
    [36554] = { cat = "mobility",     cd = 30,  name = "Shadowstep" },
    [408]   = { cat = "offensive_cd", cd = 20,  name = "Kidney Shot" },

    -- ROGUE — DEFENSIVE
    [31224] = { cat = "defensive_cd", cd = 60,  dur = 5,  name = "Cloak of Shadows" },
    [26669] = { cat = "defensive_cd", cd = 300, dur = 15, name = "Evasion" },
    [26889] = { cat = "defensive_cd", cd = 300, name = "Vanish" },
    [11305] = { cat = "mobility",     cd = 300, dur = 15, name = "Sprint" },
    [45182] = { cat = "defensive_cd", cd = 60,  name = "Cheating Death" },

    -- ROGUE — INTERRUPT
    [1766]  = { cat = "interrupt", cd = 10, dur = 5, name = "Kick" },

    -- =================================================================
    -- PRIEST — OFFENSIVE
    -- =================================================================
    [10060] = { cat = "offensive_cd", cd = 180, dur = 15, name = "Power Infusion" },
    [14751] = { cat = "offensive_cd", cd = 180, name = "Inner Focus" },
    [34433] = { cat = "offensive_cd", cd = 300, name = "Shadowfiend" },
    [25467] = { cat = "offensive_cd", cd = 180, name = "Devouring Plague" },
    [10890] = { cat = "offensive_cd", cd = 30,  name = "Psychic Scream" },
    [64044] = { cat = "offensive_cd", cd = 120, dur = 3, name = "Psychic Horror" },

    -- PRIEST — DEFENSIVE
    [33206] = { cat = "defensive_cd", cd = 120, dur = 8,  name = "Pain Suppression" },
    [47788] = { cat = "defensive_cd", cd = 180, dur = 10, name = "Guardian Spirit" },
    [6346]  = { cat = "defensive_cd", cd = 180, dur = 180, name = "Fear Ward" },
    [25437] = { cat = "defensive_cd", cd = 600, name = "Desperate Prayer" },
    [47585] = { cat = "defensive_cd", cd = 75,  dur = 6,  name = "Dispersion" },
    [586]   = { cat = "defensive_cd", cd = 30,  dur = 10, name = "Fade" },

    -- PRIEST — HEALING
    [47540] = { cat = "healing_cd",   cd = 10,  name = "Penance" },

    -- PRIEST — INTERRUPT
    [15487] = { cat = "interrupt", cd = 45, dur = 5, name = "Silence" },

    -- PRIEST — DISPEL
    [527]   = { cat = "dispel", name = "Dispel Magic" },
    [32375] = { cat = "dispel", cd = 15, name = "Mass Dispel" },

    -- =================================================================
    -- MAGE — OFFENSIVE
    -- =================================================================
    [12472] = { cat = "offensive_cd", cd = 180, dur = 20, name = "Icy Veins" },
    [12042] = { cat = "offensive_cd", cd = 180, dur = 15, name = "Arcane Power" },
    [12043] = { cat = "offensive_cd", cd = 180, name = "Presence of Mind" },
    [11129] = { cat = "offensive_cd", cd = 180, name = "Combustion" },
    [31687] = { cat = "offensive_cd", cd = 180, name = "Summon Water Elemental" },
    [33043] = { cat = "offensive_cd", cd = 20,  name = "Dragon's Breath" },
    [33933] = { cat = "offensive_cd", cd = 30,  name = "Blast Wave" },
    [44572] = { cat = "offensive_cd", cd = 30,  name = "Deep Freeze" },
    [44457] = { cat = "offensive_cd", cd = 3,   name = "Living Bomb" },

    -- MAGE — DEFENSIVE
    [45438] = { cat = "defensive_cd", cd = 300, dur = 10, name = "Ice Block" },
    [11958] = { cat = "defensive_cd", cd = 480, name = "Cold Snap" },
    [33405] = { cat = "defensive_cd", cd = 30,  dur = 60, name = "Ice Barrier" },
    [1953]  = { cat = "mobility",     cd = 15,  name = "Blink" },
    [66]    = { cat = "defensive_cd", cd = 300, name = "Invisibility" },
    [27088] = { cat = "offensive_cd", cd = 25,  name = "Frost Nova" },

    -- MAGE — INTERRUPT
    [2139]  = { cat = "interrupt", cd = 24, dur = 8, name = "Counterspell" },

    -- MAGE — DISPEL
    [475]   = { cat = "dispel", name = "Remove Curse" },
    [30449] = { cat = "dispel", cd = 6, name = "Spellsteal" },

    -- =================================================================
    -- WARLOCK — OFFENSIVE
    -- =================================================================
    [27223] = { cat = "offensive_cd", cd = 120, name = "Death Coil" },
    [17928] = { cat = "offensive_cd", cd = 40,  name = "Howl of Terror" },
    [30283] = { cat = "offensive_cd", cd = 20,  name = "Shadowfury" },
    [18288] = { cat = "offensive_cd", cd = 180, name = "Amplify Curse" },
    [47241] = { cat = "offensive_cd", cd = 180, dur = 30, name = "Metamorphosis" },
    [59672] = { cat = "offensive_cd", cd = 10,  name = "Metamorphosis (Charge)" },
    [47847] = { cat = "offensive_cd", cd = 12,  name = "Shadowburn" },

    -- WARLOCK — DEFENSIVE
    [18708] = { cat = "defensive_cd", cd = 900, name = "Fel Domination" },
    [47986] = { cat = "defensive_cd", cd = 30,  name = "Sacrifice (Voidwalker)" },
    [6229]  = { cat = "defensive_cd", cd = 30,  dur = 30, name = "Shadow Ward" },

    -- WARLOCK — INTERRUPT (PET)
    [19647] = { cat = "interrupt", cd = 24, dur = 6, name = "Spell Lock" },
    [27277] = { cat = "dispel",   cd = 8,  name = "Devour Magic" },

    -- WARLOCK — UTILITY
    [18540] = { cat = "utility", name = "Ritual of Doom" },
    [29893] = { cat = "utility", name = "Ritual of Souls" },
    [47883] = { cat = "utility", name = "Soulstone Resurrection" },

    -- =================================================================
    -- SHAMAN — OFFENSIVE
    -- =================================================================
    [32182] = { cat = "offensive_cd", cd = 600, dur = 40, name = "Heroism" },
    [2825]  = { cat = "offensive_cd", cd = 600, dur = 40, name = "Bloodlust" },
    [16166] = { cat = "offensive_cd", cd = 180, name = "Elemental Mastery" },
    [51533] = { cat = "offensive_cd", cd = 180, dur = 45, name = "Feral Spirit" },
    [30823] = { cat = "defensive_cd", cd = 120, dur = 15, name = "Shamanistic Rage" },
    [59159] = { cat = "offensive_cd", cd = 6,   name = "Thunderstorm" },
    [17364] = { cat = "offensive_cd", cd = 8,   name = "Stormstrike" },
    [2894]  = { cat = "offensive_cd", cd = 1200, name = "Fire Elemental Totem" },
    [2062]  = { cat = "offensive_cd", cd = 1200, name = "Earth Elemental Totem" },

    -- SHAMAN — DEFENSIVE
    [16188] = { cat = "defensive_cd", cd = 180, name = "Nature's Swiftness (Shaman)" },
    [8177]  = { cat = "defensive_cd", cd = 15,  name = "Grounding Totem" },
    [8143]  = { cat = "cc_break",     cd = 15,  name = "Tremor Totem" },
    [16190] = { cat = "defensive_cd", cd = 300, name = "Mana Tide Totem" },
    [61301] = { cat = "healing_cd",   cd = 6,   name = "Riptide" },

    -- SHAMAN — INTERRUPT
    [25454] = { cat = "interrupt", cd = 6,  dur = 2, name = "Earth Shock" },
    [57994] = { cat = "interrupt", cd = 6,  dur = 2, name = "Wind Shear" },

    -- SHAMAN — DISPEL
    [8012]  = { cat = "dispel", name = "Purge" },
    [51886] = { cat = "dispel", name = "Cleanse Spirit" },

    -- =================================================================
    -- DRUID — OFFENSIVE
    -- =================================================================
    [33831] = { cat = "offensive_cd", cd = 180, name = "Force of Nature" },
    [8983]  = { cat = "offensive_cd", cd = 60,  name = "Bash" },
    [33786] = { cat = "offensive_cd", cd = 6,   name = "Cyclone" },
    [48505] = { cat = "offensive_cd", cd = 60,  dur = 10, name = "Starfall" },
    [61384] = { cat = "offensive_cd", cd = 20,  name = "Typhoon" },
    [50334] = { cat = "offensive_cd", cd = 180, dur = 15, name = "Berserk" },

    -- DRUID — DEFENSIVE
    [22812] = { cat = "defensive_cd", cd = 60,  dur = 12, name = "Barkskin" },
    [22842] = { cat = "defensive_cd", cd = 180, dur = 10, name = "Frenzied Regeneration" },
    [61336] = { cat = "defensive_cd", cd = 180, dur = 12, name = "Survival Instincts" },
    [29166] = { cat = "utility",      cd = 360, dur = 20, name = "Innervate" },
    [17116] = { cat = "defensive_cd", cd = 180, name = "Nature's Swiftness (Druid)" },
    [33357] = { cat = "mobility",     cd = 300, dur = 15, name = "Dash" },
    [27009] = { cat = "defensive_cd", cd = 60,  name = "Nature's Grasp" },

    -- DRUID — HEALING
    [18562] = { cat = "healing_cd",   cd = 15,  name = "Swiftmend" },
    [48438] = { cat = "healing_cd",   cd = 6,   name = "Wild Growth" },

    -- DRUID — INTERRUPT
    [16979] = { cat = "interrupt", cd = 15, name = "Feral Charge - Bear" },
    [49376] = { cat = "interrupt", cd = 30, name = "Feral Charge - Cat" },

    -- DRUID — DISPEL
    [2782]  = { cat = "dispel", name = "Remove Curse" },
    [2893]  = { cat = "dispel", name = "Abolish Poison" },

    -- =================================================================
    -- DEATH KNIGHT — OFFENSIVE
    -- =================================================================
    [49016] = { cat = "offensive_cd", cd = 180, dur = 30, name = "Hysteria" },
    [49206] = { cat = "offensive_cd", cd = 180, name = "Summon Gargoyle" },
    [49028] = { cat = "offensive_cd", cd = 60,  dur = 20, name = "Dancing Rune Weapon" },
    [47476] = { cat = "interrupt",    cd = 10,  dur = 5, name = "Strangulate" },
    [51271] = { cat = "offensive_cd", cd = 60,  dur = 20, name = "Unbreakable Armor" },
    [55233] = { cat = "defensive_cd", cd = 60,  dur = 10, name = "Vampiric Blood" },
    [49222] = { cat = "defensive_cd", cd = 60,  dur = 20, name = "Bone Shield" },
    [51052] = { cat = "defensive_cd", cd = 120, dur = 10, name = "Anti-Magic Zone" },
    [49039] = { cat = "offensive_cd", cd = 60,  dur = 10, name = "Lichborne" },
    [48743] = { cat = "defensive_cd", cd = 120, name = "Death Pact" },

    -- DEATH KNIGHT — DEFENSIVE
    [48707] = { cat = "defensive_cd", cd = 45,  dur = 5,  name = "Anti-Magic Shell" },
    [48792] = { cat = "defensive_cd", cd = 120, dur = 12, name = "Icebound Fortitude" },
    [47528] = { cat = "interrupt",    cd = 10,  dur = 4,  name = "Mind Freeze" },

    -- DEATH KNIGHT — MOBILITY
    [49576] = { cat = "mobility",     cd = 25,  name = "Death Grip" },

    -- DEATH KNIGHT — UTILITY
    [61999] = { cat = "utility",      cd = 600, name = "Raise Ally" },
    [46584] = { cat = "utility",      cd = 180, name = "Raise Dead" },
    [49005] = { cat = "offensive_cd", cd = 180, dur = 10, name = "Mark of Blood" },
    [51209] = { cat = "offensive_cd", cd = 60,  name = "Hungering Cold" },

    -- =================================================================
    -- CONSUMABLES
    -- =================================================================
    [27236] = { cat = "defensive_cd", cd = 120, name = "Master Healthstone" },
}

-- Spells to poll for cooldown tracking on the player character
-- These are the most important CDs to know the exact remaining time on
TRACKED_COOLDOWN_SPELLS = {
    -- Trinket
    42292,
    -- Warrior
    6552, 72, 1719, 12292, 871, 23920, 3411, 5246, 20252, 12809, 676, 18499, 46924,
    -- Paladin
    31884, 642, 498, 10278, 1044, 27148, 10308, 20066, 20216, 27154,
    -- Hunter
    19574, 3045, 23989, 19263, 19503, 19577, 27068, 34490, 14311, 5384,
    -- Rogue
    1766, 31224, 26669, 26889, 11305, 2094, 14185, 13750, 13877, 14177, 36554, 408, 51690, 51713,
    -- Priest
    33206, 47788, 10060, 14751, 34433, 10890, 15487, 6346, 47585, 32375,
    -- Mage
    2139, 45438, 11958, 12472, 12042, 12043, 1953, 27088,
    -- Warlock
    19647, 27223, 17928, 30283, 18288, 18708,
    -- Shaman
    25454, 57994, 32182, 2825, 16166, 30823, 8177, 8143, 16190, 16188,
    -- Druid
    22812, 22842, 29166, 18562, 33831, 8983, 33786, 16979, 17116, 61336, 50334,
    -- Death Knight
    48707, 48792, 47528, 47476, 49576, 49016, 49206, 49028, 51271, 55233, 49222, 51052,
    -- Racials
    7744, 20589, 20594, 20600, 20549, 28730,
}
