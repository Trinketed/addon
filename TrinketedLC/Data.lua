---------------------------------------------------------------------------
-- TrinketedLC: Data.lua
-- Spell tables for the Loss-of-Control alert, ported verbatim from
-- BetterBlizzFrames' temp_tbc/modules/loc.lua so the TrinketedLC alert shows
-- the exact same effect labels, interrupt durations and reductions.
---------------------------------------------------------------------------
local ADDON, ns = ...
ns.Data = ns.Data or {}

-- spellId -> interrupt lockout duration (seconds)
ns.Data.interruptSpells = {
    [1766] = 5,       -- Kick (Rogue)
    [2139] = 8,       -- Counterspell (Mage)
    [6552] = 4,       -- Pummel (Warrior)
    [72] = 6,         -- Shield Bash (Warrior)
    [8042] = 2,       -- Earth Shock (Shaman)
    [19244] = 5,      -- Spell Lock (Warlock)
    [19675] = 4,      -- Feral Charge Effect (Druid)
    [32747] = 3,      -- Deadly Throw Interrupt
    [132409] = 6,     -- Spell Lock (Warlock)
    [19647] = 6,      -- Spell Lock (Warlock, pet)
    [47528] = 4,      -- Mind Freeze (Death Knight)
    [57994] = 3,      -- Wind Shear (Shaman)
    [91807] = 2,      -- Shambling Rush (Death Knight)
    [96231] = 4,      -- Rebuke (Paladin)
    [93985] = 4,      -- Skull Bash (Druid)
    [116705] = 4,     -- Spear Hand Strike (Monk)
    [147362] = 3,     -- Counter Shot (Hunter)
    [31935] = 3,      -- Avenger's Shield (Paladin)
    [78675] = 5,      -- Solar Beam
    [113286] = 5,     -- Solar Beam (Symbiosis)
    [26679] = 5,      -- Deadly Throw (Rogue) (4-6 sec interrupt depending on combos(3-5))

    [33871] = 8,      -- Shield Bash (Warrior)
    [24259] = 6,      -- Spell Lock (Warlock)
    [43523] = 5,      -- Unstable Affliction (Warlock)
    --[16979] = 4,    -- Feral Charge (Druid)
    [119911] = 6,     -- Optical Blast (Warlock Observer)
    [115781] = 6,     -- Optical Blast (Warlock Observer)
    [102060] = 4,     -- Disrupting Shout
    [26090] = 2,      -- Pummel (Gorilla)
    [50479] = 2,      -- Nethershock
    [97547] = 5,      -- Solar Beam
}

-- Buffs that reduce interrupt lockout duration (spellId -> multiplier)
ns.Data.spellLockReducer = {
    [317920] = 0.7, -- Concentration Aura
    [234084] = 0.5, -- Moon and Stars
    [383020] = 0.5, -- Tranquil Air
}

-- Combat-log events that can feed the interrupt watcher
ns.Data.interruptEvents = {
    ["SPELL_INTERRUPT"] = true,
    ["SPELL_CAST_SUCCESS"] = true,
    ["SPELL_AURA_APPLIED"] = true, -- For Deadly Throw
}

-- spellId -> loss-of-control effect label (the text the alert displays)
ns.Data.spellList = {
    -- *** Incapacitate Effects ***
    [2637]   = "Asleep", -- Hibernate
    [3355]   = "Frozen", -- Freezing Trap Effect
    [19386]  = "Asleep", -- Wyvern Sting
    [118]    = "Polymorphed", -- Polymorph
    [28271]  = "Polymorphed", -- Polymorph: Turtle
    [28272]  = "Polymorphed", -- Polymorph: Pig
    [61025]  = "Polymorphed", -- Polymorph: Serpent
    [61721]  = "Polymorphed", -- Polymorph: Rabbit
    [61780]  = "Polymorphed", -- Polymorph: Turkey
    [61305]  = "Polymorphed", -- Polymorph: Black Cat
    [82691]  = "Frozen", -- Ring of Frost
    [115078] = "Incapacitated", -- Paralysis
    [20066]  = "Incapacitated", -- Repentance
    [9484]   = "Shackled", -- Shackle Undead
    [1776]   = "Gouged", -- Gouge
    [6770]   = "Sapped", -- Sap
    [76780]  = "Incapacitated", -- Bind Elemental
    [51514]  = "Hexed", -- Hex
    [710]    = "Incapacitated", -- Banish
    [107079] = "Incapacitated", -- Quaking Palm (Racial)

    -- *** Disorient Effects ***
    [19503]  = "Disoriented", -- Scatter Shot
    [31661]  = "Disoriented", -- Dragon's Breath
    [123393] = "Disoriented", -- Glyph of Breath of Fire
    [88625]  = "Disoriented", -- Holy Word: Chastise
    [105421] = "Disoriented", -- Blinding Light

    -- *** Controlled Stun Effects ***
    [108194] = "Stunned", -- Asphyxiate
    [91800]  = "Stunned", -- Gnaw (Ghoul)
    [91797]  = "Stunned", -- Monstrous Blow (Dark Transformation Ghoul)
    [115001] = "Stunned", -- Remorseless Winter
    [102795] = "Stunned", -- Bear Hug
    [5211]   = "Stunned", -- Mighty Bash
    [9005]   = "Stunned", -- Pounce
    [22570]  = "Stunned", -- Maim
    [113801] = "Stunned", -- Bash (Treants)
    [117526] = "Stunned", -- Binding Shot
    [24394]  = "Stunned", -- Intimidation
    [126246] = "Stunned", -- Lullaby (Crane pet)
    [126423] = "Stunned", -- Petrifying Gaze (Basilisk pet)
    [126355] = "Stunned", -- Quill (Porcupine pet)
    [90337]  = "Stunned", -- Bad Manner (Monkey)
    [56626]  = "Stunned", -- Sting (Wasp)
    [50519]  = "Stunned", -- Sonic Blast
    [118271] = "Stunned", -- Combustion
    [44572]  = "Stunned", -- Deep Freeze
    [119392] = "Stunned", -- Charging Ox Wave
    [122242] = "Stunned", -- Clash
    [120086] = "Stunned", -- Fists of Fury
    [119381] = "Stunned", -- Leg Sweep
    [115752] = "Stunned", -- Blinding Light (Glyphed)
    [853]    = "Stunned", -- Hammer of Justice
    [110698] = "Stunned", -- Hammer of Justice (Symbiosis)
    [119072] = "Stunned", -- Holy Wrath
    [105593] = "Stunned", -- Fist of Justice
    [408]    = "Stunned", -- Kidney Shot
    [1833]   = "Stunned", -- Cheap Shot
    [118345] = "Stunned", -- Pulverize (Primal Earth Elemental)
    [118905] = "Stunned", -- Static Charge (Capacitor Totem)
    [89766]  = "Stunned", -- Axe Toss (Felguard)
    [22703]  = "Stunned", -- Inferno Effect
    [30283]  = "Stunned", -- Shadowfury
    [132168] = "Stunned", -- Shockwave
    [107570] = "Stunned", -- Storm Bolt
    [20549]  = "Stunned", -- War Stomp (Racial)
    [7922]   = "Stunned", -- Charge Stun
    [58861]  = "Stunned", -- Bash (Spirit Wolves)
    [12809]  = "Stunned", -- Concussion Blow
    [60995]  = "Stunned", -- Demon Charge
    [47481]  = "Stunned", -- Gnaw (Pet variant)
    [85388]  = "Stunned", -- Throwdown
    [20253]  = "Stunned", -- Intercept
    [30153]  = "Stunned", -- Pursuit
    [6572]   = "Stunned", -- Ravage
    [39796]  = "Stunned", -- Stoneclaw Stun
    [34510]  = "Stunned", -- Stun (proc)
    [12355]  = "Stunned", -- Impact
    [23454]  = "Stunned", -- Stun (generic)
    [132169] = "Stunned", -- Storm Bolt
    [96201]  = "Stunned", -- Web Wrap
    [122057] = "Stunned", -- Clash
    [15618]  = "Stunned", -- Snap Kick
    [127361] = "Stunned", -- Bear Hug
    [102546] = "Stunned", -- Pounce

    -- *** Non-controlled Stun Effects ***
    [113953] = "Stunned", -- Paralysis
    [118895] = "Stunned", -- Dragon Roar
    [77505]  = "Stunned", -- Earthquake
    [100]    = "Stunned", -- Charge
    [118000] = "Stunned", -- Dragon Roar

    -- *** Fear Effects ***
    [113004] = "Feared", -- Intimidating Roar (Symbiosis)
    [113056] = "Feared", -- Intimidating Roar (Symbiosis 2)
    [1513]   = "Feared", -- Scare Beast
    [10326]  = "Feared", -- Turn Evil
    [145067] = "Feared", -- Turn Evil (Evil is a Point of View)
    [1450679] = "Feared", -- Turn Evil
    [8122]   = "Feared", -- Psychic Scream
    [113792] = "Feared", -- Psychic Terror (Psyfiend)
    [2094]   = "Blinded", -- Blind (Fear DR)
    [5782]   = "Feared", -- Fear
    [130616] = "Feared", -- Fear
    [118699] = "Feared", -- Fear 2
    [5484]   = "Feared", -- Howl of Terror
    [115268] = "Seduced", -- Mesmerize (Shivarra)
    [6358]   = "Seduced", -- Seduction (Succubus)
    [104045] = "Feared", -- Sleep (Metamorphosis)
    [5246]   = "Feared", -- Intimidating Shout
    [20511]  = "Feared", -- Intimidating Shout (secondary targets)
    [87204]  = "Feared", -- Sin and Punishment

    -- *** Controlled Root Effects ***
    [96294]  = "Rooted", -- Chains of Ice (Chilblains Root)
    [339]    = "Rooted", -- Entangling Roots
    [113275] = "Rooted", -- Entangling Roots (Symbiosis)
    [102359] = "Rooted", -- Mass Entanglement
    [19975]  = "Rooted", -- Nature's Grasp
    [128405] = "Rooted", -- Narrow Escape
    [90327]  = "Rooted", -- Lock Jaw (Dog)
    [54706]  = "Rooted", -- Venom Web Spray (Silithid)
    [50245]  = "Rooted", -- Pin (Crab)
    [4167]   = "Rooted", -- Web (Spider)
    [33395]  = "Rooted", -- Freeze (Water Elemental)
    [122]    = "Rooted", -- Frost Nova
    [110693] = "Rooted", -- Frost Nova (Symbiosis)
    [116706] = "Rooted", -- Disable
    [87194]  = "Rooted", -- Glyph of Mind Blast
    [114404] = "Rooted", -- Void Tendrils
    [115197] = "Rooted", -- Partial Paralysis
    [63685]  = "Rooted", -- Freeze (Frost Shock)
    [107566] = "Rooted", -- Staggering Shout
    [113770] = "Rooted", -- Entangling Roots
    [105771] = "Rooted", -- Warbringer
    [53148]  = "Rooted", -- Charge
    [136634] = "Rooted", -- Narrow Escape
    [81210]  = "Rooted", -- Net
    [91807]  = "Rooted", -- Shambling Rush

    -- *** Non-controlled Root Effects ***
    [64803]  = "Rooted", -- Entrapment
    [111340] = "Rooted", -- Ice Ward
    [123407] = "Rooted", -- Spinning Fire Blossom
    [64695]  = "Rooted", -- Earthgrab Totem
    [25999]  = "Rooted", -- Boar Charge
    [19306]  = "Rooted", -- Counterattack
    [115757] = "Rooted", -- Frost Nova (alt?)
    [35963]  = "Rooted", -- Improved Wing Clip
    [19185]  = "Rooted", -- Entrapment (Hunter talent version)
    [23694]  = "Rooted", -- Improved Hamstring
    [135373] = "Rooted", -- Entrapment
    [45334]  = "Rooted", -- Immobilized
    [44041]  = "Rooted", -- Chastise (Root)
    [44043]  = "Rooted", -- Chastise (Root)
    [44044]  = "Rooted", -- Chastise (Root)
    [44045]  = "Rooted", -- Chastise (Root)
    [44046]  = "Rooted", -- Chastise (Root)
    [44047]  = "Rooted", -- Chastise (Root)
    [1062]   = "Rooted", -- Entangling Roots
    [5195]   = "Rooted", -- Entangling Roots
    [5196]   = "Rooted", -- Entangling Roots
    [9852]   = "Rooted", -- Entangling Roots
    [9853]   = "Rooted", -- Entangling Roots
    [26989]  = "Rooted", -- Entangling Roots
    [19970]  = "Rooted", -- Entangling Roots (Nature's Grasp)
    [19971]  = "Rooted", -- Entangling Roots (Nature's Grasp)
    [19972]  = "Rooted", -- Entangling Roots (Nature's Grasp)
    [19973]  = "Rooted", -- Entangling Roots (Nature's Grasp)
    [19974]  = "Rooted", -- Entangling Roots (Nature's Grasp)
    [27010]  = "Rooted", -- Nature's Grasp
    [865]    = "Rooted", -- Frost Nova
    [6131]   = "Rooted", -- Frost Nova
    [10230]  = "Rooted", -- Frost Nova
    [27088]  = "Rooted", -- Frost Nova
    [16979]  = "Rooted", -- Feral Charge
    [20909]  = "Rooted", -- Counterattack (Rank 2)
    [20910]  = "Rooted", -- Counterattack (Rank 3)
    [27067]  = "Rooted", -- Counterattack (Rank 4)
    [19229]  = "Rooted", -- Improved Wing Clip
    [12494]  = "Rooted", -- Frostbite

    -- *** Disarm Weapon Effects ***
    [50541]  = "Disarmed", -- Clench (Scorpid)
    [91644]  = "Disarmed", -- Snatch (Bird of Prey)
    [117368] = "Disarmed", -- Grapple Weapon
    [126458] = "Disarmed", -- Grapple Weapon (Symbiosis)
    [137461] = "Disarmed", -- Ring of Peace (Disarm effect)
    [64058]  = "Disarmed", -- Psychic Horror (Disarm Effect)
    [51722]  = "Disarmed", -- Dismantle
    [118093] = "Disarmed", -- Disarm (Voidwalker/Voidlord)
    [676]    = "Disarmed", -- Disarm
    [15752]  = "Disarmed", -- Disarm (Warrior talent)
    [14251]  = "Disarmed", -- Riposte
    [142896] = "Disarmed", -- Disarmed

    -- *** Silence Effects ***
    [47476]  = "Silenced", -- Strangulate
    [114238] = "Silenced", -- Glyph of Fae Silence
    [34490]  = "Silenced", -- Silencing Shot
    [102051] = "Silenced+", -- Frostjaw
    [55021]  = "Silenced", -- Counterspell
    [137460] = "Silenced", -- Ring of Peace (Silence effect)
    [116709] = "Silenced", -- Spear Hand Strike
    [31935]  = "Silenced", -- Avenger's Shield
    [15487]  = "Silenced", -- Silence
    [1330]   = "Silenced", -- Garrote
    [24259]  = "Silenced", -- Spell Lock
    [115782] = "Silenced", -- Optical Blast (Observer)
    [18498]  = "Silenced", -- Silenced - Gag Order
    [50613]  = "Silenced", -- Arcane Torrent (Racial, Runic Power)
    [28730]  = "Silenced", -- Arcane Torrent (Racial, Mana)
    [25046]  = "Silenced", -- Arcane Torrent (Racial, Energy)
    [69179]  = "Silenced", -- Arcane Torrent (Racial, Rage)
    [80483]  = "Silenced", -- Arcane Torrent (Racial, Focus)
    [18469]  = "Silenced", -- Improved Counterspell (Mage)
    [18425]  = "Silenced", -- Improved Kick (Rogue)
    [43523]  = "Silenced", -- Unstable Affliction (Silence effect)
    [106839] = "Silenced", -- Skull Bash (Feral)
    [147362] = "Silenced", -- Countershot (Hunter)
    [171138] = "Silenced", -- Shadow Lock (Warlock)
    [183752] = "Silenced", -- Consume Magic (Demon Hunter)
    [187707] = "Silenced", -- Muzzle (Hunter)
    [212619] = "Silenced", -- Call Felhunter (Warlock)
    [231665] = "Silenced", -- Avenger's Shield (Ret/Prot Paladin)
    [351338] = "Silenced", -- Quell (Evoker)
    [97547]  = "Silenced", -- Solar Beam
    [78675]  = "Silenced", -- Solar Beam
    [113286] = "Silenced", -- Solar Beam
    [81261]  = "Silenced", -- Solar Beam
    [142895] = "Silenced", -- Ring of Peace(?) Silence
    [31117]  = "Silenced", -- Unstable Affliction

    -- *** Horror Effects ***
    [64044]  = "Horrified", -- Psychic Horror
    [137143] = "Horrified", -- Blood Horror
    [6789]   = "Horrified", -- Death Coil

    -- *** Mind Control Effects ***
    [605]   = "Mind Controlled", -- Dominate Mind
    [13181] = "Mind Controlled", -- Gnomish Mind Control Cap (Item)
    [67799] = "Mind Controlled", -- Mind Amplification Dish (Item)

    -- *** Spells that DR with themselves only ***
    [33786]  = "Cycloned", -- Cyclone
    [113506] = "Cycloned", -- Cyclone (Symbiosis)

    -- ##########################
    -- Cata Bonus Ones, mop above, needs verifying
    -- ##########################
    -- *** Incapacitate Effects ***
    [49203] = "Incapacitated", -- Hungering Cold

    -- *** Controlled Stun Effects ***
    [93433] = "Stunned", -- Burrow Attack (Worm)
    [83046] = "Stunned", -- Improved Polymorph (Rank 1)
    [83047] = "Stunned", -- Improved Polymorph (Rank 2)
    [93986] = "Stunned", -- Aura of Foreboding
    [54786] = "Stunned", -- Demon Leap
    [46968] = "Stunned", -- Shockwave

    -- *** Non-controlled Stun Effects ***
    [85387] = "Stunned", -- Aftermath
    [15283] = "Stunned", -- Stunning Blow (Weapon Proc)
    [56]    = "Stunned", -- Stun (Weapon Proc)

    -- *** Fear Effects ***
    [5134]  = "Feared", -- Flash Bomb Fear (Item)

    -- *** Controlled Root Effects ***
    [96293] = "Rooted", -- Chains of Ice (Chilblains Rank 1)
    [87193] = "Rooted", -- Paralysis
    [39965] = "Rooted", -- Frost Grenade (Item)
    [55536] = "Rooted", -- Frostweave Net (Item)

    -- *** Non-controlled Root Effects ***
    [47168] = "Rooted", -- Improved Wing Clip
    [83301] = "Rooted", -- Improved Cone of Cold (Rank 1)
    [83302] = "Rooted", -- Improved Cone of Cold (Rank 2)
    [55080] = "Rooted", -- Shattered Barrier (Rank 1)
    [83073] = "Rooted", -- Shattered Barrier (Rank 2)
    [50479] = "Silenced", -- Nether Shock (Nether Ray)
    [86759] = "Silenced", -- Silenced - Improved Kick (Rank 2)

    [13327] = "Incapacitated", -- Reckless Charge (Item)
    [4064]  = "Incapacitated", -- Rough Copper Bomb (Item)
    [4065]  = "Incapacitated", -- Large Copper Bomb (Item)
    [4066]  = "Incapacitated", -- Small Bronze Bomb (Item)
    [4067]  = "Incapacitated", -- Big Bronze Bomb (Item)
    [4068]  = "Incapacitated", -- Iron Grenade (Item)
    [12421] = "Incapacitated", -- Mithril Frag Bomb (Item)
    [4069]  = "Incapacitated", -- Big Iron Bomb (Item)
    [12562] = "Incapacitated", -- The Big One (Item)
    [12543] = "Incapacitated", -- Hi-Explosive Bomb (Item)
    [19769] = "Incapacitated", -- Thorium Grenade (Item)
    [19784] = "Incapacitated", -- Dark Iron Bomb (Item)
    [30216] = "Incapacitated", -- Fel Iron Bomb (Item)
    [30461] = "Incapacitated", -- The Bigger One (Item)
    [30217] = "Incapacitated", -- Adamantite Grenade (Item)
    [67769] = "Incapacitated", -- Cobalt Frag Bomb (Item)
    [67890] = "Incapacitated", -- Cobalt Frag Bomb (Item, Frag Belt)
    [54466] = "Incapacitated", -- Saronite Grenade (Item)

    [13099] = "Rooted", -- Net-o-Matic
    [13119] = "Rooted", -- Net-o-Matic
    [13120] = "Rooted", -- Net-o-Matic
    [13138] = "Rooted", -- Net-o-Matic
    [13139] = "Rooted", -- Net-o-Matic
    [16566] = "Rooted", -- Net-o-Matic
    [52825] = "Rooted", -- Swoop
    [1090]  = "Asleep", -- Magic Dust
    [835]   = "Stunned", -- Tidal Charm
    [15753] = "Stunned", -- Linken's Boomerang Stun
    [13237] = "Stunned", -- Goblin Mortar trinket
    [18798] = "Stunned", -- Freezing Band
    [32752] = "Stunned", -- Summoning Disorientation
    [50318] = "Silenced", -- Serenity Dust (moth pet silence)

    -- late tbc additions
    [6798]   = "Stunned",  -- Bash
    [8983]   = "Stunned",  -- Bash
    [17925]  = "Horrified", -- Death Coil
    [17926]  = "Horrified", -- Death Coil
    [27223]  = "Horrified", -- Death Coil
    [5588]   = "Stunned",  -- Hammer of Justice
    [5589]   = "Stunned",  -- Hammer of Justice
    [10308]  = "Stunned",  -- Hammer of Justice
    [19577]  = "Stunned",  -- Intimidation
    [8643]   = "Stunned",  -- Kidney Shot
    [9823]   = "Stunned",  -- Pounce
    [9827]   = "Stunned",  -- Pounce
    [27006]  = "Stunned",  -- Pounce
    [30413]  = "Stunned",  -- Shadowfury
    [30414]  = "Stunned",  -- Shadowfury
    [99]     = "Disoriented", -- Disorienting Roar

    [20614]  = "Stunned",  -- Intercept Stun (Rank 2)
    [20615]  = "Stunned",  -- Intercept Stun (Rank 3)
    [25273]  = "Stunned",  -- Intercept Stun (Rank 4)

    -- Stun Procs
    [5530]   = "Stunned",  -- Mace Stun Effect
    [15269]  = "Stunned",  -- Blackout Stun
    [16922]  = "Stunned",  -- Imp Starfire Stun
    [11103]  = "Stunned",  -- Impact
    [12357]  = "Stunned",  -- Impact
    [12358]  = "Stunned",  -- Impact
    [12359]  = "Stunned",  -- Impact
    [12360]  = "Stunned",  -- Impact
    [19410]  = "Stunned",  -- Improved Concussive Shot
    [20170]  = "Stunned",  -- Seal of Justice Stun
    [18093]  = "Stunned",  -- Pyroclasm
    [12798]  = "Stunned",  -- Revenge Stun

    -- Disorient / Incapacitate / Fear / Charm
    [33041]  = "Disoriented", -- Dragon's Breath
    [33042]  = "Disoriented", -- Dragon's Breath
    [33043]  = "Disoriented", -- Dragon's Breath
    [6213]   = "Feared",    -- Fear
    [6215]   = "Feared",    -- Fear
    [14309]  = "Frozen",    -- Freezing Trap Effect
    [1777]   = "Gouged",    -- Gouge
    [8629]   = "Gouged",    -- Gouge
    [11285]  = "Gouged",    -- Gouge
    [11286]  = "Gouged",    -- Gouge
    [38764]  = "Gouged",    -- Gouge
    [18657]  = "Asleep",    -- Hibernate
    [18658]  = "Asleep",    -- Hibernate
    [17928]  = "Feared",    -- Howl of Terror
    [25274]  = "Stunned",   -- Intercept Stun
    [10911]  = "Mind Controlled", -- Mind Control
    [10912]  = "Mind Controlled", -- Mind Control
    [12824]  = "Polymorphed", -- Polymorph
    [12825]  = "Polymorphed", -- Polymorph
    [12826]  = "Polymorphed", -- Polymorph
    [8124]   = "Feared",    -- Psychic Scream
    [10888]  = "Feared",    -- Psychic Scream
    [10890]  = "Feared",    -- Psychic Scream
    [2070]   = "Sapped",    -- Sap
    [11297]  = "Sapped",    -- Sap
    [14326]  = "Feared",    -- Scare Beast
    [14327]  = "Feared",    -- Scare Beast
    [20407]  = "Seduced",   -- Seduction
    [30850]  = "Seduced",   -- Seduction
    [24131]  = "Asleep",    -- Wyvern Sting
    [24132]  = "Asleep",    -- Wyvern Sting
    [24133]  = "Asleep",    -- Wyvern Sting
    [24134]  = "Asleep",    -- Wyvern Sting
    [24135]  = "Asleep",    -- Wyvern Sting
    [27068]  = "Asleep",    -- Wyvern Sting
    [27069]  = "Asleep",    -- Wyvern Sting
    [18647]  = "Incapacitated", -- Banish
    [34097]  = "Disarmed",  -- Riposte 2

    -- late additions needs verifying
    [18499]  = "Stunned",  -- Bash
    [20252]  = "Stunned",  -- Intercept Stun (Rank 1)
    [25275]  = "Stunned",  -- Intercept Stun (Rank 5)
    [11578]  = "Stunned",  -- Charge Stun
    [42365]  = "Stunned",  -- Maim
    [12540]  = "Gouged",   -- Gouge
    [14310]  = "Frozen",   -- Freezing Trap Effect
    [14311]  = "Frozen",   -- Freezing Trap Effect
    [27025]  = "Frozen",   -- Freezing Trap Effect
    [9485]   = "Shackled", -- Shackle Undead
    [10955]  = "Shackled", -- Shackle Undead
    [19675]  = "Rooted",   -- Feral Charge Effect
    [24399]  = "Feared",   -- Panic
    [16508]  = "Feared",   -- Intimidating Roar
    [745]    = "Rooted",   -- Web
    [15970]  = "Asleep",   -- Sleep

    -- Added by BBF at runtime on non-MoP clients (SetupLoCFrame)
    [2812]   = "Stunned",  -- Holy Wrath
    [64346]  = "Disarmed", -- Fiery Payback (Fire Mage Disarm)
    [19482]  = "Stunned",  -- War Stomp (Doom Guard)
}

-- CC labels considered "hard" (full loss of control), prioritised as main
ns.Data.hardCCSet = {
    ["Stunned"] = true,
    ["Feared"] = true,
    ["Horrified"] = true,
    ["Cycloned"] = true,
    ["Incapacitated"] = true,
    ["Mind Controlled"] = true,
    ["Disoriented"] = true,
    ["Polymorphed"] = true,
    ["Hexed"] = true,
    ["Frozen"] = true,
    ["Blinded"] = true,
    ["Seduced"] = true,
    ["Asleep"] = true,
    ["Shackled"] = true,
    ["Gouged"] = true,
    ["Sapped"] = true,
}
