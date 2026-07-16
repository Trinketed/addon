---------------------------------------------------------------------------
-- TrinketedCD: CooldownData.lua
-- TBC 2.4.3 PvP arena spell cooldown database
-- All cooldown durations are BASE (untalented) values
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD

---------------------------------------------------------------------------
-- Categories
---------------------------------------------------------------------------
addon.CD_CATEGORIES = {
    "trinket",
    "major_offensive",
    "major_defensive",
    "interrupt",
    "cc_break",
}

addon.CD_CATEGORY_COLORS = {
    trinket          = { r = 0.91, g = 0.73, b = 0.14 },
    major_offensive  = { r = 1.0, g = 0.2,  b = 0.2 },
    major_defensive  = { r = 0.2, g = 0.8,  b = 0.2 },
    interrupt        = { r = 1.0, g = 0.5,  b = 0.0 },
    cc_break         = { r = 0.8, g = 0.8,  b = 0.0 },
}

addon.CD_CATEGORY_LABELS = {
    trinket          = "PvP Trinket",
    major_offensive  = "Major Offensive",
    major_defensive  = "Major Defensive",
    interrupt        = "Interrupt",
    cc_break         = "CC Break",
}

---------------------------------------------------------------------------
-- Cooldown Database
-- Key: spell name (as returned by combat log)
-- Fields:
--   spellID   - for GetSpellTexture(spellID) icon lookup
--   duration  - cooldown in seconds (base / untalented)
--   category  - one of CD_CATEGORIES
--   classes   - list of class names, or {"ALL"} for universal
--   races     - (optional) restrict to specific races
--   enabled   - default enabled state
--   priority  - default sort order (lower = shown first)
--   sharedCD  - (optional) spell name or list of names that share cooldown
--   sharedCDDuration - (optional) duration of shared CD if different
--   isPetAbility - (optional) true if cast by pet, resolved to owner
---------------------------------------------------------------------------
addon.COOLDOWN_DB = {

    -- =================================================================
    -- PVP TRINKET
    -- =================================================================
    ["PvP Trinket"] = {
        spellID     = 42292,
        duration    = 120,
        category    = "trinket",
        classes     = { "ALL" },
        enabled     = true,
        priority    = 1,
        allianceIcon = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01",
        hordeIcon    = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02",
    },

    -- =================================================================
    -- CONSUMABLES
    -- =================================================================
    ["Master Healthstone"] = {
        spellID     = 27236,
        duration    = 120,
        category    = "major_defensive",
        classes     = { "ALL" },
        enabled     = true,
        priority    = 5,
    },

    -- =================================================================
    -- WARRIOR
    -- =================================================================
    ["Recklessness"] = {
        spellID     = 1719,
        duration    = 1800,
        buffDuration = 15,
        category    = "major_offensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 10,
        sharedCD    = { "Shield Wall", "Retaliation" },
    },
    ["Death Wish"] = {
        spellID     = 12292,
        duration    = 180,
        buffDuration = 30,
        category    = "major_offensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 11,
    },
    ["Shield Wall"] = {
        spellID     = 871,
        duration    = 1800,
        buffDuration = 10,
        category    = "major_defensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 20,
        sharedCD    = { "Recklessness", "Retaliation" },
    },
    ["Retaliation"] = {
        spellID     = 20230,
        duration    = 1800,
        buffDuration = 15,
        category    = "major_defensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 22,
        sharedCD    = { "Recklessness", "Shield Wall" },
    },
    ["Last Stand"] = {
        spellID     = 12975,
        duration    = 480,
        buffDuration = 20,
        category    = "major_defensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 21,
    },
    ["Spell Reflection"] = {
        spellID     = 23920,
        duration    = 10,
        buffDuration = 5,
        category    = "major_defensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 23,
    },
    ["Intervene"] = {
        spellID     = 3411,
        duration    = 30,
        category    = "major_defensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 24,
    },
    ["Berserker Rage"] = {
        spellID     = 18499,
        duration    = 30,
        buffDuration = 10,
        category    = "cc_break",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 40,
    },
    ["Intimidating Shout"] = {
        spellID     = 5246,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 12,
    },
    ["Intercept"] = {
        spellID     = 20252,
        duration    = 30,
        category    = "major_offensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 14,
    },
    ["Concussion Blow"] = {
        spellID     = 12809,
        duration    = 45,
        category    = "major_offensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 15,
        spec        = "Protection",
    },
    ["Disarm"] = {
        spellID     = 676,
        duration    = 60,
        category    = "major_offensive",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 16,
    },
    ["Pummel"] = {
        spellID     = 6552,
        duration    = 10,
        category    = "interrupt",
        classes     = { "Warrior" },
        enabled     = true,
        priority    = 50,
    },
    ["Shield Bash"] = {
        spellID     = 72,
        duration    = 12,
        category    = "interrupt",
        classes     = { "Warrior" },
        enabled     = false,
        priority    = 51,
    },

    -- =================================================================
    -- PALADIN
    -- =================================================================
    ["Avenging Wrath"] = {
        spellID     = 31884,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 10,
    },
    ["Divine Shield"] = {
        spellID     = 642,
        duration    = 300,
        buffDuration = 12,
        category    = "major_defensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 20,
        sharedCD    = "Divine Protection",
    },
    ["Divine Protection"] = {
        spellID     = 498,
        duration    = 300,
        category    = "major_defensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 21,
        sharedCD    = "Divine Shield",
    },
    ["Blessing of Protection"] = {
        spellID     = 10278,
        duration    = 300,
        category    = "major_defensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 22,
    },
    ["Blessing of Freedom"] = {
        spellID     = 1044,
        duration    = 25,
        category    = "major_defensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 23,
    },
    ["Blessing of Sacrifice"] = {
        spellID     = 27148,
        duration    = 30,
        category    = "major_defensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 24,
    },
    ["Hammer of Justice"] = {
        spellID     = 10308,
        duration    = 60,
        category    = "major_offensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 11,
    },
    ["Repentance"] = {
        spellID     = 20066,
        duration    = 60,
        category    = "major_offensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 12,
        spec        = "Retribution",
    },
    ["Divine Favor"] = {
        spellID     = 20216,
        duration    = 120,
        category    = "major_offensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 13,
        spec        = "Holy",
    },
    ["Lay on Hands"] = {
        spellID     = 27154,
        duration    = 3600,
        category    = "major_defensive",
        classes     = { "Paladin" },
        enabled     = true,
        priority    = 25,
    },

    -- =================================================================
    -- HUNTER
    -- =================================================================
    ["Bestial Wrath"] = {
        spellID     = 19574,
        duration    = 120,
        buffDuration = 18,
        category    = "major_offensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 10,
        spec        = "Beast Mastery",
    },
    ["Rapid Fire"] = {
        spellID     = 3045,
        duration    = 300,
        buffDuration = 15,
        category    = "major_offensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 11,
    },
    ["Readiness"] = {
        spellID     = 23989,
        duration    = 300,
        category    = "major_offensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 12,
        spec        = "Survival",
        resets      = { "Bestial Wrath", "Rapid Fire", "Deterrence", "Scatter Shot",
                        "Intimidation", "Wyvern Sting", "Silencing Shot", "Freezing Trap" },
    },
    ["Deterrence"] = {
        spellID     = 19263,
        duration    = 300,
        buffDuration = 10,
        category    = "major_defensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 20,
    },
    ["Scatter Shot"] = {
        spellID     = 19503,
        duration    = 30,
        category    = "major_offensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 13,
    },
    ["Intimidation"] = {
        spellID     = 19577,
        duration    = 60,
        category    = "major_offensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 14,
        spec        = "Beast Mastery",
    },
    ["Wyvern Sting"] = {
        spellID     = 27068,
        duration    = 120,
        category    = "major_offensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 15,
        spec        = "Survival",
    },
    ["Silencing Shot"] = {
        spellID     = 34490,
        duration    = 20,
        category    = "interrupt",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 50,
        spec        = "Marksmanship",
    },
    ["Freezing Trap"] = {
        spellID     = 14311,
        duration    = 30,
        category    = "major_offensive",
        classes     = { "Hunter" },
        enabled     = true,
        priority    = 16,
    },

    -- =================================================================
    -- ROGUE
    -- =================================================================
    ["Cloak of Shadows"] = {
        spellID     = 31224,
        duration    = 60,
        buffDuration = 5,
        category    = "major_defensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 20,
    },
    ["Evasion"] = {
        spellID     = 26669,
        duration    = 300,
        buffDuration = 15,
        category    = "major_defensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 21,
    },
    ["Vanish"] = {
        spellID     = 26889,
        duration    = 300,
        category    = "major_defensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 22,
    },
    ["Sprint"] = {
        spellID     = 11305,
        duration    = 300,
        buffDuration = 15,
        category    = "major_defensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 23,
    },
    ["Blind"] = {
        spellID     = 2094,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 10,
    },
    ["Preparation"] = {
        spellID     = 14185,
        duration    = 600,
        category    = "major_offensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 11,
        spec        = "Subtlety",
        resets      = { "Evasion", "Sprint", "Vanish", "Cold Blood", "Shadowstep" },
    },
    ["Adrenaline Rush"] = {
        spellID     = 13750,
        duration    = 300,
        buffDuration = 15,
        category    = "major_offensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 12,
        spec        = "Combat",
    },
    ["Blade Flurry"] = {
        spellID     = 13877,
        duration    = 120,
        buffDuration = 15,
        category    = "major_offensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 13,
    },
    ["Cold Blood"] = {
        spellID     = 14177,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 14,
    },
    ["Shadowstep"] = {
        spellID     = 36554,
        duration    = 30,
        category    = "major_offensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 15,
        spec        = "Subtlety",
    },
    ["Kidney Shot"] = {
        spellID     = 408,
        duration    = 20,
        category    = "major_offensive",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 16,
    },
    ["Kick"] = {
        spellID     = 1766,
        duration    = 10,
        category    = "interrupt",
        classes     = { "Rogue" },
        enabled     = true,
        priority    = 50,
    },
    ["Cheating Death"] = {
        spellID     = 45182,
        duration    = 60,
        category    = "major_defensive",
        classes     = { "Rogue" },
        spec        = "Subtlety",
        enabled     = true,
        priority    = 3,
        trackEvent  = "SPELL_AURA_APPLIED",
    },

    -- =================================================================
    -- PRIEST
    -- =================================================================
    ["Pain Suppression"] = {
        spellID     = 33206,
        duration    = 120,
        buffDuration = 8,
        category    = "major_defensive",
        classes     = { "Priest" },
        enabled     = true,
        priority    = 20,
        spec        = "Discipline",
    },
    ["Power Infusion"] = {
        spellID     = 10060,
        duration    = 180,
        buffDuration = 15,
        category    = "major_offensive",
        classes     = { "Priest" },
        enabled     = true,
        priority    = 10,
        spec        = "Discipline",
    },
    ["Inner Focus"] = {
        spellID     = 14751,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Priest" },
        enabled     = true,
        priority    = 11,
    },
    ["Psychic Scream"] = {
        spellID     = 10890,
        duration    = 30,
        category    = "major_defensive",
        classes     = { "Priest" },
        enabled     = true,
        priority    = 21,
    },
    ["Fear Ward"] = {
        spellID     = 6346,
        duration    = 180,
        category    = "major_defensive",
        classes     = { "Priest" },
        enabled     = true,
        priority    = 22,
    },
    ["Shadowfiend"] = {
        spellID     = 34433,
        duration    = 300,
        category    = "major_offensive",
        classes     = { "Priest" },
        enabled     = true,
        priority    = 12,
    },
    ["Desperate Prayer"] = {
        spellID     = 25437,
        duration    = 600,
        category    = "major_defensive",
        classes     = { "Priest" },
        races       = { "Human", "Dwarf" },
        enabled     = true,
        priority    = 23,
    },
    ["Devouring Plague"] = {
        spellID     = 25467,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Priest" },
        races       = { "Undead" },
        enabled     = true,
        priority    = 13,
    },
    ["Silence"] = {
        spellID     = 15487,
        duration    = 45,
        category    = "interrupt",
        classes     = { "Priest" },
        enabled     = true,
        priority    = 50,
    },

    -- =================================================================
    -- MAGE
    -- =================================================================
    ["Ice Block"] = {
        spellID     = 45438,
        duration    = 300,
        category    = "major_defensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 20,
    },
    ["Cold Snap"] = {
        spellID     = 11958,
        duration    = 480,
        category    = "major_defensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 21,
        spec        = "Frost",
        resets      = { "Ice Block", "Ice Barrier", "Summon Water Elemental", "Frost Nova", "Icy Veins" },
    },
    ["Icy Veins"] = {
        spellID     = 12472,
        duration    = 180,
        buffDuration = 20,
        category    = "major_offensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 10,
    },
    ["Arcane Power"] = {
        spellID     = 12042,
        duration    = 180,
        buffDuration = 15,
        category    = "major_offensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 11,
        spec        = "Arcane",
    },
    ["Presence of Mind"] = {
        spellID     = 12043,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 12,
    },
    ["Combustion"] = {
        spellID     = 11129,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 13,
        spec        = "Fire",
    },
    ["Summon Water Elemental"] = {
        spellID     = 31687,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 14,
        spec        = "Frost",
    },
    ["Counterspell"] = {
        spellID     = 2139,
        duration    = 24,
        category    = "interrupt",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 50,
    },
    ["Frost Nova"] = {
        spellID     = 27088,
        duration    = 25,
        category    = "cc_break",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 30,
    },
    ["Blink"] = {
        spellID     = 1953,
        duration    = 15,
        category    = "major_defensive",
        classes     = { "Mage" },
        enabled     = false,
        priority    = 22,
    },
    ["Ice Barrier"] = {
        spellID     = 33405,
        duration    = 30,
        buffDuration = 60,
        category    = "major_defensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 23,
    },
    ["Dragon's Breath"] = {
        spellID     = 33043,
        duration    = 20,
        category    = "major_offensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 15,
        spec        = "Fire",
    },
    ["Blast Wave"] = {
        spellID     = 33933,
        duration    = 30,
        category    = "major_offensive",
        classes     = { "Mage" },
        enabled     = true,
        priority    = 16,
    },
    ["Invisibility"] = {
        spellID     = 66,
        duration    = 300,
        category    = "major_defensive",
        classes     = { "Mage" },
        enabled     = false,
        priority    = 24,
    },

    -- =================================================================
    -- WARLOCK
    -- =================================================================
    ["Death Coil"] = {
        spellID     = 27223,
        duration    = 120,
        category    = "major_offensive",
        classes     = { "Warlock" },
        enabled     = true,
        priority    = 10,
    },
    ["Howl of Terror"] = {
        spellID     = 17928,
        duration    = 40,
        category    = "major_offensive",
        classes     = { "Warlock" },
        enabled     = true,
        priority    = 11,
    },
    ["Shadowfury"] = {
        spellID     = 30283,
        duration    = 20,
        category    = "major_offensive",
        classes     = { "Warlock" },
        enabled     = true,
        priority    = 12,
        spec        = "Destruction",
    },
    ["Amplify Curse"] = {
        spellID     = 18288,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Warlock" },
        enabled     = true,
        priority    = 13,
    },
    ["Fel Domination"] = {
        spellID     = 18708,
        duration    = 900,
        category    = "major_defensive",
        classes     = { "Warlock" },
        enabled     = true,
        priority    = 20,
    },
    ["Spell Lock"] = {
        spellID     = 19647,
        duration    = 24,
        category    = "interrupt",
        classes     = { "Warlock" },
        enabled     = true,
        priority    = 50,
        isPetAbility = true,
    },
    ["Devour Magic"] = {
        spellID     = 27277,
        duration    = 8,
        category    = "major_defensive",
        classes     = { "Warlock" },
        enabled     = true,
        priority    = 21,
        isPetAbility = true,
    },

    -- =================================================================
    -- SHAMAN
    -- =================================================================
    ["Heroism"] = {
        spellID     = 32182,
        duration    = 600,
        category    = "major_offensive",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 10,
    },
    ["Bloodlust"] = {
        spellID     = 2825,
        duration    = 600,
        category    = "major_offensive",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 10,
    },
    ["Elemental Mastery"] = {
        spellID     = 16166,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 11,
        spec        = "Elemental",
    },
    ["Shamanistic Rage"] = {
        spellID     = 30823,
        duration    = 120,
        buffDuration = 15,
        category    = "major_defensive",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 20,
        spec        = "Enhancement",
    },
    ["Nature's Swiftness"] = {
        spellID     = 16188,
        duration    = 180,
        category    = "major_defensive",
        classes     = { "Shaman", "Druid" },
        enabled     = true,
        priority    = 21,
    },
    ["Grounding Totem"] = {
        spellID     = 8177,
        duration    = 15,
        category    = "major_defensive",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 22,
    },
    ["Tremor Totem"] = {
        spellID     = 8143,
        duration    = 15,
        category    = "cc_break",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 40,
    },
    ["Earth Shock"] = {
        spellID     = 25454,
        duration    = 6,
        category    = "interrupt",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 50,
    },
    ["Mana Tide Totem"] = {
        spellID     = 16190,
        duration    = 300,
        category    = "major_defensive",
        classes     = { "Shaman" },
        enabled     = true,
        priority    = 23,
        spec        = "Restoration",
    },
    ["Fire Elemental Totem"] = {
        spellID     = 2894,
        duration    = 1200,
        category    = "major_offensive",
        classes     = { "Shaman" },
        enabled     = false,
        priority    = 12,
    },

    -- =================================================================
    -- DRUID
    -- =================================================================
    ["Barkskin"] = {
        spellID     = 22812,
        duration    = 60,
        category    = "major_defensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 20,
    },
    ["Innervate"] = {
        spellID     = 29166,
        duration    = 360,
        category    = "major_defensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 21,
    },
    ["Frenzied Regeneration"] = {
        spellID     = 22842,
        duration    = 180,
        category    = "major_defensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 22,
    },
    ["Force of Nature"] = {
        spellID     = 33831,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 10,
        spec        = "Balance",
    },
    ["Feral Charge"] = {
        spellID     = 16979,
        duration    = 15,
        category    = "interrupt",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 50,
    },
    ["Bash"] = {
        spellID     = 8983,
        duration    = 60,
        category    = "major_offensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 11,
    },
    ["Cyclone"] = {
        spellID     = 33786,
        duration    = 6,
        category    = "major_offensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 12,
    },
    ["Dash"] = {
        spellID     = 33357,
        duration    = 300,
        category    = "major_defensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 24,
    },
    ["Nature's Grasp"] = {
        spellID     = 27009,
        duration    = 60,
        category    = "major_defensive",
        classes     = { "Druid" },
        enabled     = false,
        priority    = 25,
    },
    ["Swiftmend"] = {
        spellID     = 18562,
        duration    = 15,
        category    = "major_defensive",
        classes     = { "Druid" },
        enabled     = true,
        priority    = 23,
        spec        = "Restoration",
    },

    -- =================================================================
    -- RACIAL ABILITIES
    -- =================================================================
    ["Perception"] = {
        spellID     = 20600,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "ALL" },
        races       = { "Human" },
        enabled     = true,
        priority    = 2,
    },
    ["Will of the Forsaken"] = {
        spellID     = 7744,
        duration    = 120,
        category    = "cc_break",
        classes     = { "ALL" },
        races       = { "Undead" },
        enabled     = true,
        priority    = 2,
    },
    ["Escape Artist"] = {
        spellID     = 20589,
        duration    = 105,
        category    = "cc_break",
        classes     = { "ALL" },
        races       = { "Gnome" },
        enabled     = true,
        priority    = 3,
    },
    ["Stoneform"] = {
        spellID     = 20594,
        duration    = 180,
        category    = "major_defensive",
        classes     = { "ALL" },
        races       = { "Dwarf" },
        enabled     = true,
        priority    = 3,
    },
    ["War Stomp"] = {
        spellID     = 20549,
        duration    = 90,
        category    = "interrupt",
        classes     = { "ALL" },
        races       = { "Tauren" },
        enabled     = true,
        priority    = 3,
    },
    ["Arcane Torrent"] = {
        spellID     = 28730,
        duration    = 120,
        category    = "interrupt",
        classes     = { "ALL" },
        races       = { "Blood Elf" },
        enabled     = true,
        priority    = 3,
    },
    ["Berserking"] = {
        spellID     = 26297,
        duration    = 180,
        category    = "major_offensive",
        classes     = { "ALL" },
        races       = { "Troll" },
        enabled     = true,
        priority    = 3,
    },
    ["Blood Fury"] = {
        spellID     = 20572,
        duration    = 120,
        category    = "major_offensive",
        classes     = { "ALL" },
        races       = { "Orc" },
        enabled     = true,
        priority    = 3,
    },
    ["Gift of the Naaru"] = {
        spellID     = 28880,
        duration    = 180,
        category    = "major_defensive",
        classes     = { "ALL" },
        races       = { "Draenei" },
        enabled     = true,
        priority    = 4,
    },
}

---------------------------------------------------------------------------
-- Spec Detection Markers
-- Maps spell names to { class, spec } for identifying talent specs.
-- Only includes deep/signature talents (31pt+) for reliable detection.
---------------------------------------------------------------------------
addon.SPEC_MARKERS = {
    -- Warrior
    ["Mortal Strike"]       = { class = "Warrior",  spec = "Arms" },
    ["Sweeping Strikes"]    = { class = "Warrior",  spec = "Arms" },
    ["Bloodthirst"]         = { class = "Warrior",  spec = "Fury" },
    ["Rampage"]             = { class = "Warrior",  spec = "Fury" },
    ["Shield Slam"]         = { class = "Warrior",  spec = "Protection" },
    ["Devastate"]           = { class = "Warrior",  spec = "Protection" },

    -- Paladin
    ["Holy Shock"]          = { class = "Paladin",  spec = "Holy" },
    ["Divine Favor"]        = { class = "Paladin",  spec = "Holy" },
    ["Avenger's Shield"]    = { class = "Paladin",  spec = "Protection" },
    ["Holy Shield"]         = { class = "Paladin",  spec = "Protection" },
    ["Crusader Strike"]     = { class = "Paladin",  spec = "Retribution" },
    ["Repentance"]          = { class = "Paladin",  spec = "Retribution" },

    -- Hunter
    ["Bestial Wrath"]       = { class = "Hunter",   spec = "Beast Mastery" },
    ["The Beast Within"]    = { class = "Hunter",   spec = "Beast Mastery" },
    ["Intimidation"]        = { class = "Hunter",   spec = "Beast Mastery" },
    ["Silencing Shot"]      = { class = "Hunter",   spec = "Marksmanship" },
    ["Trueshot Aura"]       = { class = "Hunter",   spec = "Marksmanship" },
    ["Wyvern Sting"]        = { class = "Hunter",   spec = "Survival" },
    ["Readiness"]           = { class = "Hunter",   spec = "Survival" },

    -- Rogue
    ["Mutilate"]            = { class = "Rogue",    spec = "Assassination" },
    ["Adrenaline Rush"]     = { class = "Rogue",    spec = "Combat" },
    ["Blade Flurry"]        = { class = "Rogue",    spec = "Combat" },
    ["Shadowstep"]          = { class = "Rogue",    spec = "Subtlety" },
    ["Hemorrhage"]          = { class = "Rogue",    spec = "Subtlety" },
    ["Premeditation"]       = { class = "Rogue",    spec = "Subtlety" },

    -- Priest
    ["Pain Suppression"]    = { class = "Priest",   spec = "Discipline" },
    ["Power Infusion"]      = { class = "Priest",   spec = "Discipline" },
    ["Vampiric Touch"]      = { class = "Priest",   spec = "Shadow" },
    ["Vampiric Embrace"]    = { class = "Priest",   spec = "Shadow" },
    ["Shadowform"]          = { class = "Priest",   spec = "Shadow" },
    ["Circle of Healing"]   = { class = "Priest",   spec = "Holy" },

    -- Mage
    ["Arcane Power"]        = { class = "Mage",     spec = "Arcane" },
    ["Combustion"]          = { class = "Mage",     spec = "Fire" },
    ["Dragon's Breath"]     = { class = "Mage",     spec = "Fire" },
    ["Summon Water Elemental"] = { class = "Mage",  spec = "Frost" },
    ["Cold Snap"]           = { class = "Mage",     spec = "Frost" },

    -- Warlock
    ["Shadowfury"]          = { class = "Warlock",  spec = "Destruction" },
    ["Unstable Affliction"] = { class = "Warlock",  spec = "Affliction" },
    ["Soul Link"]           = { class = "Warlock",  spec = "Demonology" },
    ["Felguard"]            = { class = "Warlock",  spec = "Demonology" },

    -- Shaman
    ["Elemental Mastery"]   = { class = "Shaman",   spec = "Elemental" },
    ["Shamanistic Rage"]    = { class = "Shaman",   spec = "Enhancement" },
    ["Stormstrike"]         = { class = "Shaman",   spec = "Enhancement" },
    ["Mana Tide Totem"]     = { class = "Shaman",   spec = "Restoration" },
    ["Earth Shield"]        = { class = "Shaman",   spec = "Restoration" },

    -- Druid
    ["Force of Nature"]     = { class = "Druid",    spec = "Balance" },
    ["Moonkin Form"]        = { class = "Druid",    spec = "Balance" },
    ["Mangle"]              = { class = "Druid",    spec = "Feral" },
    ["Swiftmend"]           = { class = "Druid",    spec = "Restoration" },
    ["Tree of Life"]        = { class = "Druid",    spec = "Restoration" },
}

---------------------------------------------------------------------------
-- Talent-based Cooldown Adjustments
-- [class][spec][spellName] = adjusted duration (seconds)
-- Only includes clear-cut, high-impact PvP adjustments.
---------------------------------------------------------------------------
addon.TALENT_CD_ADJUSTMENTS = {
    ["Rogue"] = {
        ["Subtlety"] = {
            -- Endurance 2/2 (Sub tier 1): -90s to Evasion, Sprint
            -- Elusiveness 2/2 (Sub tier 5): -90s to Vanish, Blind
            ["Evasion"] = 210,   -- 300 - 90
            ["Sprint"]  = 210,   -- 300 - 90
            ["Vanish"]  = 210,   -- 300 - 90
            ["Blind"]   = 90,    -- 180 - 90
        },
        ["Assassination"] = {
            -- Endurance 2/2 from 20pts Sub (standard 41/0/20)
            ["Evasion"] = 210,   -- 300 - 90
            ["Sprint"]  = 210,   -- 300 - 90
        },
        -- Combat (20/41/0): no Sub talents, no adjustments
    },
    ["Warrior"] = {
        ["Arms"] = {
            -- Improved Intercept 2/2 (Fury tier 4): -10s
            ["Intercept"] = 20,         -- 30 - 10
            -- Intensify Rage 3/3 (Fury tier 3): -600s
            ["Recklessness"]  = 1200,   -- 1800 - 600
            ["Shield Wall"]   = 1200,   -- 1800 - 600
            ["Retaliation"]   = 1200,   -- 1800 - 600
        },
        ["Fury"] = {
            ["Intercept"] = 20,
            ["Recklessness"]  = 1200,
            ["Shield Wall"]   = 1200,
            ["Retaliation"]   = 1200,
        },
    },
    ["Mage"] = {
        ["Frost"] = {
            -- Ice Floes 3/3 (tier 1): -20% on Ice Block
            -- Arctic Winds 5/5 (tier 8): additional x0.80 multiplicative
            ["Ice Block"]   = 192,  -- 300 * 0.80 * 0.80
            ["Cold Snap"]   = 384,  -- 480 * 0.80
            ["Ice Barrier"] = 24,   -- 30 * 0.80
            -- Improved Frost Nova 2/2 (tier 2): -4s
            ["Frost Nova"]  = 21,   -- 25 - 4
        },
    },
    ["Paladin"] = {
        ["Holy"] = {
            -- Guardian's Favor 2/2 (Prot tier 2): -120s
            ["Blessing of Protection"] = 180,  -- 300 - 120
            -- Improved HoJ 3/3 (Prot tier 3): -15s
            ["Hammer of Justice"] = 45,         -- 60 - 15
            -- Improved LoH 2/2 (Holy tier 2): -1200s
            ["Lay on Hands"] = 2400,            -- 3600 - 1200
        },
        ["Retribution"] = {
            -- Improved HoJ 3/3 (Prot tier 3)
            ["Hammer of Justice"] = 45,
        },
        ["Protection"] = {
            -- Sacred Duty 2/2 (Prot tier 7): -60s
            ["Divine Shield"] = 240,            -- 300 - 60
            ["Blessing of Protection"] = 180,
            ["Hammer of Justice"] = 45,
        },
    },
    ["Priest"] = {
        -- Improved Psychic Scream 2/2 (Shadow tier 2): -4s
        -- Taken by all PvP specs (only 10 Shadow pts needed)
        ["Discipline"] = { ["Psychic Scream"] = 26 },
        ["Holy"]       = { ["Psychic Scream"] = 26 },
        ["Shadow"]     = { ["Psychic Scream"] = 26 },
    },
    ["Shaman"] = {
        ["Elemental"] = {
            -- Reverberation 5/5 (Ele tier 2): -1s on shocks
            ["Earth Shock"] = 5,       -- 6 - 1
        },
        ["Enhancement"] = {
            -- Enhancing Totems 2/2 (Enh tier 2): -2s
            ["Grounding Totem"] = 13,  -- 15 - 2
        },
    },
    ["Hunter"] = {
        ["Survival"] = {
            -- Resourcefulness 3/3 (Surv tier 5): -6s on traps
            ["Freezing Trap"] = 24,    -- 30 - 6
        },
        ["Marksmanship"] = {
            -- Rapid Killing 2/2 (MM tier 2): -120s
            ["Rapid Fire"] = 180,      -- 300 - 120
        },
        ["Beast Mastery"] = {
            -- Standard BM goes 41/20+ into MM, gets Rapid Killing
            ["Rapid Fire"] = 180,
        },
    },
}

---------------------------------------------------------------------------
-- Build reverse lookup tables
---------------------------------------------------------------------------
addon.SPELL_ID_TO_NAME = {}
addon.SPELL_BY_CLASS = {}

function addon:BuildCooldownLookups()
    wipe(self.SPELL_ID_TO_NAME)
    wipe(self.SPELL_BY_CLASS)
    for spellName, data in pairs(self.COOLDOWN_DB) do
        self.SPELL_ID_TO_NAME[data.spellID] = spellName
        for _, class in ipairs(data.classes) do
            self.SPELL_BY_CLASS[class] = self.SPELL_BY_CLASS[class] or {}
            table.insert(self.SPELL_BY_CLASS[class], spellName)
        end
    end
end

addon:BuildCooldownLookups()
