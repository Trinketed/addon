---------------------------------------------------------------------------
-- TrinketedHistory: ReplaySpells.lua
-- TBC 2.4.3 arena-relevant spell database for replay viewer
-- Categories: cc, defensive, offensive, trinket
-- Fields: id (spellID for icon), cat (category), dur (duration in seconds)
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}

TrinketedHistory.REPLAY_SPELLS = {
    -- =====================================================================
    -- CC (crowd control)
    -- =====================================================================
    -- Mage
    ["Polymorph"]               = { id = 12826, cat = "cc", dur = 10 },
    ["Polymorph: Pig"]          = { id = 28272, cat = "cc", dur = 10 },
    ["Polymorph: Turtle"]       = { id = 28271, cat = "cc", dur = 10 },
    ["Frost Nova"]              = { id = 27088, cat = "cc", dur = 8 },
    ["Dragon's Breath"]         = { id = 33043, cat = "cc", dur = 3 },
    ["Ice Block"]               = { id = 45438, cat = "defensive", dur = 10 },
    -- Warlock
    ["Fear"]                    = { id = 6215,  cat = "cc", dur = 10 },
    ["Death Coil"]              = { id = 27223, cat = "cc", dur = 3 },
    ["Howl of Terror"]          = { id = 17928, cat = "cc", dur = 8 },
    ["Seduction"]               = { id = 6358,  cat = "cc", dur = 15 },
    ["Spell Lock"]              = { id = 19647, cat = "cc", dur = 6 },
    -- Priest
    ["Psychic Scream"]          = { id = 10890, cat = "cc", dur = 8 },
    ["Silence"]                 = { id = 15487, cat = "cc", dur = 5 },
    ["Chastise"]                = { id = 44047, cat = "cc", dur = 2 },
    -- Druid
    ["Cyclone"]                 = { id = 33786, cat = "cc", dur = 6 },
    ["Entangling Roots"]        = { id = 26989, cat = "cc", dur = 10 },
    ["Bash"]                    = { id = 8983,  cat = "cc", dur = 4 },
    ["Feral Charge Effect"]     = { id = 45334, cat = "cc", dur = 4 },
    ["Maim"]                    = { id = 22570, cat = "cc" },  -- varies by combo pts
    -- Paladin
    ["Hammer of Justice"]       = { id = 10308, cat = "cc", dur = 6 },
    ["Repentance"]              = { id = 20066, cat = "cc", dur = 6 },
    -- Rogue
    ["Kidney Shot"]             = { id = 408,   cat = "cc" },  -- varies by combo pts
    ["Blind"]                   = { id = 2094,  cat = "cc", dur = 10 },
    ["Sap"]                     = { id = 11297, cat = "cc", dur = 10 },
    ["Gouge"]                   = { id = 1776,  cat = "cc", dur = 4 },
    ["Cheap Shot"]              = { id = 1833,  cat = "cc", dur = 4 },
    -- Hunter
    ["Freezing Trap Effect"]    = { id = 14309, cat = "cc", dur = 10 },
    ["Scatter Shot"]            = { id = 19503, cat = "cc", dur = 4 },
    ["Intimidation"]            = { id = 24394, cat = "cc", dur = 3 },
    ["Wyvern Sting"]            = { id = 27068, cat = "cc", dur = 10 },
    -- Warrior
    ["Intercept Stun"]          = { id = 25274, cat = "cc", dur = 3 },
    ["Intimidating Shout"]      = { id = 5246,  cat = "cc", dur = 8 },
    -- Shaman
    ["Earthbind"]               = { id = 3600,  cat = "cc", dur = 5 },

    -- =====================================================================
    -- DEFENSIVE COOLDOWNS
    -- =====================================================================
    -- Paladin
    ["Divine Shield"]           = { id = 642,   cat = "defensive", dur = 12 },
    ["Blessing of Protection"]  = { id = 10278, cat = "defensive", dur = 10 },
    ["Blessing of Freedom"]     = { id = 1044,  cat = "defensive", dur = 10 },
    ["Blessing of Sacrifice"]   = { id = 27148, cat = "defensive", dur = 10 },
    -- Mage (Ice Block already listed under CC)
    -- Priest
    ["Pain Suppression"]        = { id = 33206, cat = "defensive", dur = 8 },
    ["Power Word: Shield"]      = { id = 25218, cat = "defensive", dur = 30 },
    -- Druid
    ["Barkskin"]                = { id = 22812, cat = "defensive", dur = 12 },
    ["Innervate"]               = { id = 29166, cat = "defensive", dur = 20 },
    -- Rogue
    ["Cloak of Shadows"]        = { id = 31224, cat = "defensive", dur = 5 },
    ["Evasion"]                 = { id = 26669, cat = "defensive", dur = 15 },
    ["Vanish"]                  = { id = 26889, cat = "defensive", dur = 10 },
    -- Hunter
    ["Deterrence"]              = { id = 19263, cat = "defensive", dur = 10 },
    -- Warrior
    ["Shield Wall"]             = { id = 871,   cat = "defensive", dur = 10 },
    ["Spell Reflection"]        = { id = 23920, cat = "defensive", dur = 5 },
    -- Warlock
    ["Fel Domination"]          = { id = 18708, cat = "defensive", dur = 15 },

    -- =====================================================================
    -- OFFENSIVE COOLDOWNS
    -- =====================================================================
    -- Hunter
    ["Bestial Wrath"]           = { id = 19574, cat = "offensive", dur = 18 },
    ["Rapid Fire"]              = { id = 3045,  cat = "offensive", dur = 15 },
    -- Rogue
    ["Adrenaline Rush"]         = { id = 13750, cat = "offensive", dur = 15 },
    ["Blade Flurry"]            = { id = 13877, cat = "offensive", dur = 15 },
    ["Cold Blood"]              = { id = 14177, cat = "offensive" },
    -- Mage
    ["Arcane Power"]            = { id = 12042, cat = "offensive", dur = 15 },
    ["Icy Veins"]               = { id = 12472, cat = "offensive", dur = 20 },
    ["Combustion"]              = { id = 11129, cat = "offensive" },
    -- Warrior
    ["Recklessness"]            = { id = 1719,  cat = "offensive", dur = 15 },
    ["Death Wish"]              = { id = 12292, cat = "offensive", dur = 30 },
    -- Shaman
    ["Bloodlust"]               = { id = 2825,  cat = "offensive", dur = 40 },
    ["Heroism"]                 = { id = 32182, cat = "offensive", dur = 40 },
    ["Elemental Mastery"]       = { id = 16166, cat = "offensive" },
    -- Warlock
    ["Soul Link"]               = { id = 19028, cat = "defensive", dur = nil },

    -- =====================================================================
    -- TRINKET
    -- =====================================================================
    ["PvP Trinket"]             = { id = 42292, cat = "trinket" },
    ["Insignia of the Horde"]   = { id = 42292, cat = "trinket" },
    ["Insignia of the Alliance"]= { id = 42292, cat = "trinket" },
    ["Will of the Forsaken"]    = { id = 7744,  cat = "trinket" },
}
