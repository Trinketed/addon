---------------------------------------------------------------------------
-- TrinketedHistory: ReplayEngine.lua
-- Playback engine for v3 event logs (ArenaBlackBox-style keyed tables)
-- Handles decompression, state management, event processing
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local LibDeflate = LibStub("LibDeflate")

---------------------------------------------------------------------------
-- Hex color string to r,g,b floats
---------------------------------------------------------------------------
local function HexToRGB(hex)
    if #hex == 8 then hex = hex:sub(3) end
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b
end

local CLASS_COLORS = {
    ["Warrior"]     = "ffc79c6e",
    ["Paladin"]     = "fff58cba",
    ["Hunter"]      = "ffabd473",
    ["Rogue"]       = "fffff569",
    ["Priest"]      = "ffffffff",
    ["Shaman"]      = "ff0070de",
    ["Mage"]        = "ff69ccf0",
    ["Warlock"]     = "ff9482c9",
    ["Druid"]       = "ffff7d0a",
}

local CLASS_COLORS_RGB = {}
for class, hex in pairs(CLASS_COLORS) do
    local r, g, b = HexToRGB(hex)
    CLASS_COLORS_RGB[class] = { r = r, g = g, b = b }
end
addon.CLASS_COLORS_RGB = CLASS_COLORS_RGB

---------------------------------------------------------------------------
-- Power type colors
---------------------------------------------------------------------------
addon.POWER_COLORS = {
    [0] = { r = 0.0, g = 0.0, b = 1.0 },   -- mana
    [1] = { r = 1.0, g = 0.0, b = 0.0 },   -- rage
    [3] = { r = 1.0, g = 1.0, b = 0.0 },   -- energy
}

---------------------------------------------------------------------------
-- Class → tracked cooldown spellIDs (major CDs visible in the CD tracker)
-- Order matters: displayed left to right in this order
---------------------------------------------------------------------------
addon.CLASS_COOLDOWNS = {
    ["Warrior"] = {
        42292,  -- PvP Trinket
        6552,   -- Pummel
        72,     -- Shield Bash
        1719,   -- Recklessness
        12292,  -- Death Wish
        871,    -- Shield Wall
        20230,  -- Retaliation
        12975,  -- Last Stand
        23920,  -- Spell Reflection
        3411,   -- Intervene
        18499,  -- Berserker Rage
        5246,   -- Intimidating Shout
        20252,  -- Intercept
        12809,  -- Concussion Blow
        676,    -- Disarm
    },
    ["Paladin"] = {
        42292,  -- PvP Trinket
        31884,  -- Avenging Wrath
        642,    -- Divine Shield
        498,    -- Divine Protection
        10278,  -- Blessing of Protection
        1044,   -- Blessing of Freedom
        27148,  -- Blessing of Sacrifice
        10308,  -- Hammer of Justice
        20066,  -- Repentance
        20216,  -- Divine Favor
        27154,  -- Lay on Hands
    },
    ["Hunter"] = {
        42292,  -- PvP Trinket
        19574,  -- Bestial Wrath
        3045,   -- Rapid Fire
        23989,  -- Readiness
        19263,  -- Deterrence
        19503,  -- Scatter Shot
        19577,  -- Intimidation
        27068,  -- Wyvern Sting
        34490,  -- Silencing Shot
        14311,  -- Freezing Trap
        5384,   -- Feign Death
    },
    ["Rogue"] = {
        42292,  -- PvP Trinket
        1766,   -- Kick
        31224,  -- Cloak of Shadows
        26669,  -- Evasion
        26889,  -- Vanish
        11305,  -- Sprint
        2094,   -- Blind
        14185,  -- Preparation
        13750,  -- Adrenaline Rush
        13877,  -- Blade Flurry
        14177,  -- Cold Blood
        36554,  -- Shadowstep
        408,    -- Kidney Shot
    },
    ["Priest"] = {
        42292,  -- PvP Trinket
        33206,  -- Pain Suppression
        10060,  -- Power Infusion
        14751,  -- Inner Focus
        34433,  -- Shadowfiend
        10890,  -- Psychic Scream
        15487,  -- Silence
        6346,   -- Fear Ward
        25437,  -- Desperate Prayer
        32375,  -- Mass Dispel
    },
    ["Mage"] = {
        42292,  -- PvP Trinket
        2139,   -- Counterspell
        45438,  -- Ice Block
        11958,  -- Cold Snap
        12472,  -- Icy Veins
        12042,  -- Arcane Power
        12043,  -- Presence of Mind
        11129,  -- Combustion
        31687,  -- Summon Water Elemental
        33043,  -- Dragon's Breath
        33933,  -- Blast Wave
        1953,   -- Blink
        66,     -- Invisibility
        27088,  -- Frost Nova
    },
    ["Warlock"] = {
        42292,  -- PvP Trinket
        19647,  -- Spell Lock
        27277,  -- Devour Magic
        27223,  -- Death Coil
        17928,  -- Howl of Terror
        30283,  -- Shadowfury
        18288,  -- Amplify Curse
        18708,  -- Fel Domination
    },
    ["Shaman"] = {
        42292,  -- PvP Trinket
        25454,  -- Earth Shock
        32182,  -- Heroism
        2825,   -- Bloodlust
        16166,  -- Elemental Mastery
        30823,  -- Shamanistic Rage
        8177,   -- Grounding Totem
        8143,   -- Tremor Totem
        16190,  -- Mana Tide Totem
        16188,  -- Nature's Swiftness
    },
    ["Druid"] = {
        42292,  -- PvP Trinket
        22812,  -- Barkskin
        22842,  -- Frenzied Regeneration
        29166,  -- Innervate
        17116,  -- Nature's Swiftness
        33831,  -- Force of Nature
        8983,   -- Bash
        33786,  -- Cyclone
        18562,  -- Swiftmend
        16979,  -- Feral Charge - Bear
        33357,  -- Dash
        27009,  -- Nature's Grasp
    },
}

---------------------------------------------------------------------------
-- Rank-proof SPELL_DB resolution.
-- The combat log records the spell ID of the rank actually cast (e.g.
-- Kidney Shot rank 2 = 8643), while SPELL_DB and CLASS_COOLDOWNS curate one
-- ID per spell (408). All ranks of a spell share a name, so on an ID miss
-- we resolve through a name → candidate-IDs index built lazily from
-- SPELL_DB.
--
-- Distinct spells can also share a name across classes (Shaman vs Druid
-- Nature's Swiftness, Mage vs Druid Remove Curse/Clearcasting), so a name
-- alone is not always enough: with multiple candidates the caster's class
-- picks the right one — via CLASS_COOLDOWNS membership, or an optional
-- `class = "Druid"` field on the SPELL_DB entry for spells that aren't
-- cooldown-tracked. If it's still ambiguous we return no entry at all:
-- wrong attribution is worse than none.
--
-- SPELL_DB names may carry a curation-only "(Shaman)"-style suffix to stay
-- readable; the index registers both the full and the stripped (in-game)
-- name so lookups by combat-log name still hit.
--
-- Returns: canonicalSpellID, dbEntry (dbEntry nil when unknown/ambiguous;
-- the raw spellID passes through in that case). casterClass is optional.
-- Exposed as addon.ResolveSpell for ReplayUI/Core (they load after us).
---------------------------------------------------------------------------
local nameCandidates   -- lowercased name → sorted { spellID, ... }
local cdClassOfID      -- spellID → class name, from CLASS_COOLDOWNS
local function BuildNameIndex()
    nameCandidates, cdClassOfID = {}, {}
    for class, list in pairs(addon.CLASS_COOLDOWNS) do
        for _, id in ipairs(list) do cdClassOfID[id] = class end
    end
    local function register(key, id)
        local list = nameCandidates[key]
        if not list then list = {}; nameCandidates[key] = list end
        list[#list + 1] = id
    end
    for id, entry in pairs(SPELL_DB) do
        if entry.name then
            local full = entry.name:lower()
            register(full, id)
            local stripped = full:gsub("%s*%b()$", "")
            if stripped ~= full then register(stripped, id) end
        end
    end
    -- Deterministic candidate order regardless of pairs() iteration.
    for _, list in pairs(nameCandidates) do table.sort(list) end
end

local function ResolveSpell(spellID, spellName, casterClass)
    if spellID and SPELL_DB and SPELL_DB[spellID] then
        return spellID, SPELL_DB[spellID]
    end
    if not (spellName and SPELL_DB) then return spellID, nil end
    if not nameCandidates then BuildNameIndex() end
    local candidates = nameCandidates[spellName:lower()]
    if not candidates then return spellID, nil end
    if #candidates == 1 then
        return candidates[1], SPELL_DB[candidates[1]]
    end
    if casterClass then
        for _, id in ipairs(candidates) do
            if cdClassOfID[id] == casterClass or SPELL_DB[id].class == casterClass then
                return id, SPELL_DB[id]
            end
        end
    end
    return spellID, nil
end
addon.ResolveSpell = ResolveSpell

---------------------------------------------------------------------------
-- Decompress an eventLog string into parsed data
-- v3 format: { v=3, startTime, roster={guid={name,class,race,spec,team}}, events={...} }
-- Returns: { roster, events, matchDuration } or nil, errorMsg
---------------------------------------------------------------------------
function addon:DecompressGameLog(eventLogStr)
    if not eventLogStr or eventLogStr == "" then
        return nil, "No event log data."
    end

    local decoded = LibDeflate:DecodeForPrint(eventLogStr)
    if not decoded then return nil, "Failed to decode event log." end

    local json = LibDeflate:DecompressZlib(decoded)
    if not json then return nil, "Failed to decompress event log." end

    local data = addon.JSONToTable(json)
    if not data then return nil, "Failed to parse event log JSON." end

    if data.v ~= 3 then
        return nil, "Unsupported event log version: " .. tostring(data.v)
    end

    local events = data.events
    if not events or #events == 0 then
        return nil, "No events in event log."
    end

    local roster = data.roster or {}

    -- Find match duration from the last event timestamp
    local matchDuration = events[#events].t or 0

    -- Pet → owner map, so pet-sourced casts (Spell Lock, Devour Magic…) can
    -- be attributed to the owning player. Two sources:
    --   * summon events (mid-match summons; owner is src, pet is dst)
    --   * pet_owner events (explicit unit-token scans recorded since this
    --     feature landed — covers pets that existed before the gates)
    -- Then a name-based backfill: a pet GUID changes on every re-summon but
    -- warlock/hunter pet names persist, so unmapped pet GUIDs inherit the
    -- owner of a same-named mapped pet (covers pre-existing pets in logs
    -- recorded before pet_owner events existed).
    local petOwner = {}
    local ownerByPetName = {}
    for _, ev in ipairs(events) do
        if ev.type == "summon" and ev.srcGUID and ev.dstGUID and roster[ev.srcGUID] then
            petOwner[ev.dstGUID] = ev.srcGUID
            if ev.dst then ownerByPetName[ev.dst] = ev.srcGUID end
        elseif ev.type == "pet_owner" and ev.petGUID and ev.ownerGUID then
            petOwner[ev.petGUID] = ev.ownerGUID
            if ev.pet then ownerByPetName[ev.pet] = ev.ownerGUID end
        end
    end
    if next(ownerByPetName) then
        for _, ev in ipairs(events) do
            local sg, dg = ev.srcGUID, ev.dstGUID
            if sg and not petOwner[sg] and sg:find("^Pet%-") and ev.src and ownerByPetName[ev.src] then
                petOwner[sg] = ownerByPetName[ev.src]
            end
            if dg and not petOwner[dg] and dg:find("^Pet%-") and ev.dst and ownerByPetName[ev.dst] then
                petOwner[dg] = ownerByPetName[ev.dst]
            end
        end
    end

    return {
        roster = roster,
        events = events,
        matchDuration = matchDuration,
        petOwner = petOwner,
    }
end

---------------------------------------------------------------------------
-- Build initial replay state from roster
---------------------------------------------------------------------------
local function BuildInitialState(parsedData)
    -- petOwner is static for the whole log; state holds a shared reference.
    local state = { players = {}, petOwner = parsedData.petOwner }
    for guid, info in pairs(parsedData.roster) do
        state.players[guid] = {
            name = info.name,
            class = info.class,
            spec = info.spec,
            team = info.team,
            health = 0,
            healthMax = 0,
            power = 0,
            powerMax = 0,
            powerType = 0,
            auras = {},
            cooldowns = {},
        }
    end
    return state
end

---------------------------------------------------------------------------
-- Deep-copy replay state (for reset during seek)
---------------------------------------------------------------------------
local function CopyState(src)
    local dst = { players = {}, petOwner = src.petOwner }
    for guid, p in pairs(src.players) do
        local aurasCopy = {}
        for id, a in pairs(p.auras) do
            aurasCopy[id] = { spell = a.spell, spellID = a.spellID, auraType = a.auraType, applied = a.applied, duration = a.duration, expires = a.expires, stacks = a.stacks }
        end
        local cdsCopy = {}
        for id, cd in pairs(p.cooldowns) do
            cdsCopy[id] = { spell = cd.spell, spellID = cd.spellID, castTime = cd.castTime, cd = cd.cd, cat = cd.cat }
        end
        dst.players[guid] = {
            name = p.name,
            class = p.class,
            spec = p.spec,
            team = p.team,
            health = p.health,
            healthMax = p.healthMax,
            power = p.power,
            powerMax = p.powerMax,
            powerType = p.powerType,
            auras = aurasCopy,
            cooldowns = cdsCopy,
        }
    end
    return dst
end

---------------------------------------------------------------------------
-- Actor lookup that sees through pets: an event sourced from a pet GUID is
-- attributed to the owning player (Spell Lock / Devour Magic land on the
-- warlock's cooldown row).
---------------------------------------------------------------------------
local function GetActorPlayer(state, guid)
    if not guid then return nil end
    local player = state.players[guid]
    if player then return player end
    local owner = state.petOwner and state.petOwner[guid]
    return owner and state.players[owner] or nil
end

---------------------------------------------------------------------------
-- Process a single v3 event and update replay state
-- Events use keyed tables: { t, type, subtype, src, srcGUID, dst, dstGUID,
--   spellID, spell, amount, hp, hpMax, power, powerMax, powerType, ... }
---------------------------------------------------------------------------
local function ProcessEvent(state, ev)
    local evType = ev.type

    -- unit_state: update HP, power, target for a player
    if evType == "unit_state" then
        local guid = ev.guid
        local player = guid and state.players[guid]
        if player then
            if ev.hp then player.health = ev.hp end
            if ev.hpMax then player.healthMax = ev.hpMax end
            if ev.power then player.power = ev.power end
            if ev.powerMax then player.powerMax = ev.powerMax end
            if ev.powerType then player.powerType = ev.powerType end
        end

    -- death
    elseif evType == "death" then
        local guid = ev.dstGUID
        local player = guid and state.players[guid]
        if player then
            player.health = 0
        end

    -- damage/heal: HP is tracked via unit_state polling, not arithmetic
    -- These events are only used for the combat log feed

    -- aura_applied
    elseif evType == "aura_applied" then
        local guid = ev.dstGUID
        local player = guid and state.players[guid]
        if player and ev.spellID then
            -- aura_applied carries no duration; fall back to SPELL_DB so major
            -- CDs/CCs still show a countdown. Rank-proof lookup, keyed to the
            -- caster's class when we know it (pets resolve to their owner).
            local caster = GetActorPlayer(state, ev.srcGUID)
            local _, db = ResolveSpell(ev.spellID, ev.spell, caster and caster.class)
            local dur = db and db.dur
            player.auras[ev.spellID] = {
                spell = ev.spell,
                spellID = ev.spellID,
                auraType = ev.auraType, -- "BUFF" or "DEBUFF"
                applied = ev.t,
                duration = dur,
                expires = dur and (ev.t + dur) or nil,
                stacks = 1,
            }
        end

    -- aura_removed
    elseif evType == "aura_removed" then
        local guid = ev.dstGUID
        local player = guid and state.players[guid]
        if player and ev.spellID then
            player.auras[ev.spellID] = nil
        end

    -- aura_refresh
    elseif evType == "aura_refresh" then
        local guid = ev.dstGUID
        local player = guid and state.players[guid]
        if player and ev.spellID and player.auras[ev.spellID] then
            local a = player.auras[ev.spellID]
            a.applied = ev.t
            if a.duration then a.expires = ev.t + a.duration end
        end

    -- aura_dose: stack count changed (SPELL_AURA_APPLIED_DOSE / _REMOVED_DOSE)
    elseif evType == "aura_dose" then
        local guid = ev.dstGUID
        local player = guid and state.players[guid]
        if player and ev.spellID and player.auras[ev.spellID] then
            player.auras[ev.spellID].stacks = ev.stacks or 1
        end

    -- aura_snapshot: full aura state from polling (fires every 0.2s while
    -- recording). The polled `expires` is GetTime()-absolute from recording
    -- time and is meaningless during replay, so we can't translate it back to
    -- replay time directly. Instead, we MERGE: if we're already tracking this
    -- spellID, keep its existing applied/expires (set when the aura first
    -- became visible) so the countdown doesn't reset on every poll. Only
    -- synthesize applied = ev.t for auras we haven't seen before. Auras no
    -- longer in the snapshot are treated as removed.
    elseif evType == "aura_snapshot" then
        local guid = ev.guid
        local player = guid and state.players[guid]
        if player and ev.auras then
            local newAuras = {}
            for _, a in ipairs(ev.auras) do
                if a.spellID then
                    local existing = player.auras[a.spellID]
                    if existing then
                        -- Preserve prior applied/expires. Backfill duration if
                        -- we previously didn't know it (e.g. aura_applied path
                        -- had no SpellDB match) but now the poll reports one.
                        newAuras[a.spellID] = existing
                        if (not existing.duration or existing.duration == 0)
                           and a.duration and a.duration > 0 then
                            existing.duration = a.duration
                            existing.expires = (existing.applied or ev.t) + a.duration
                        end
                        -- Stacks are authoritative from the poll; update if the
                        -- snapshot reports a fresh count (covers pre-existing
                        -- stacks or missed dose events).
                        if a.stacks then existing.stacks = a.stacks end
                    else
                        -- Unseen aura: likely pre-existing at match start or
                        -- applied while the unit was out of combat-log range.
                        -- Approximate applied = snapshot time.
                        local dur = a.duration
                        if not dur or dur == 0 then
                            -- Snapshots carry no caster, so ambiguous
                            -- same-name spells resolve to nothing (safe).
                            local _, db = ResolveSpell(a.spellID, a.spell)
                            dur = db and db.dur
                        end
                        newAuras[a.spellID] = {
                            spell = a.spell,
                            spellID = a.spellID,
                            auraType = a.auraType,
                            applied = ev.t,
                            duration = dur,
                            expires = dur and (ev.t + dur) or nil,
                            stacks = a.stacks or 1,
                        }
                    end
                end
            end
            player.auras = newAuras
        end

    -- cast_success: track cooldowns from SPELL_DB (pet casts attribute to
    -- the owning player)
    elseif evType == "cast_success" then
        local player = GetActorPlayer(state, ev.srcGUID)
        if player and ev.spellID then
            local canonicalID, dbEntry = ResolveSpell(ev.spellID, ev.spell, player.class)
            if dbEntry and dbEntry.cd and dbEntry.cd > 1.5 then
                -- Keyed by the canonical ID so the tracker icons (keyed from
                -- CLASS_COOLDOWNS) find it whatever rank was actually cast.
                player.cooldowns[canonicalID] = {
                    spell = ev.spell,
                    spellID = canonicalID,
                    castTime = ev.t,
                    cd = dbEntry.cd,
                    cat = dbEntry.cat,
                }
            end
        end

    -- player_entered: add to state if not already present
    elseif evType == "player_entered" then
        local guid = ev.guid
        if guid and not state.players[guid] then
            state.players[guid] = {
                name = ev.name,
                class = ev.class,
                spec = nil,
                team = ev.team,
                health = 0,
                healthMax = 0,
                power = 0,
                powerMax = 0,
                powerType = 0,
                auras = {},
                cooldowns = {},
            }
        end
    end
end

---------------------------------------------------------------------------
-- Build feed events: full combat log
-- Returns array of { time, type, spellName, spellID, srcName, dstName,
--                     srcClass, dstClass, cat, amount, extraSpell }
---------------------------------------------------------------------------
local function BuildFeedEvents(parsedData)
    local feed = {}

    -- Build GUID->class lookup from roster
    local guidToClass = {}
    local guidToName = {}
    for guid, info in pairs(parsedData.roster) do
        guidToClass[guid] = info.class
        guidToName[guid] = info.name
    end
    -- Pets take their owner's class so their feed rows color correctly
    -- (names stay the pet's own).
    for petGUID, ownerGUID in pairs(parsedData.petOwner or {}) do
        local info = parsedData.roster[ownerGUID]
        if info then guidToClass[petGUID] = info.class end
    end

    for _, ev in ipairs(parsedData.events) do
        local evType = ev.type
        local countBefore = #feed

        -- Skip polling/state events — only show combat actions
        if evType == "unit_state" or evType == "aura_snapshot" or evType == "cooldown_state"
            or evType == "pet_owner"
            or evType == "player_entered" or evType == "gates_open" or evType == "match_end"
            or evType == "target_change" or evType == "focus_change"
            or evType == "loss_of_control" or evType == "aura_refresh"
            or evType == "aura_dose" or evType == "extra_attacks" then
            -- skip

        elseif evType == "death" then
            table.insert(feed, {
                time = ev.t, type = "death", cat = "death",
                dstName = ev.dst or (ev.dstGUID and guidToName[ev.dstGUID]),
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                -- GUID kept so the UI's Death Recap can match the victim
                -- against raw events (unit_state polls, damage, auras).
                dstGUID = ev.dstGUID,
            })

        elseif evType == "damage" then
            local spellName = ev.spell
            if ev.subtype == "auto_melee" then spellName = "Melee"
            elseif ev.subtype == "auto_ranged" then spellName = "Auto Shot"
            elseif ev.subtype == "env" then spellName = ev.envType or "Environment"
            end
            table.insert(feed, {
                time = ev.t, type = "damage", cat = "damage",
                spellName = spellName, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                amount = ev.amount, critical = ev.critical,
            })

        elseif evType == "heal" then
            local effective = (ev.amount or 0) - (ev.overhealing or 0)
            table.insert(feed, {
                time = ev.t, type = "heal", cat = "healing",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                amount = effective, critical = ev.critical,
            })

        elseif evType == "cast_success" then
            local cat = "cast"
            local dbEntry = select(2, ResolveSpell(ev.spellID, ev.spell,
                ev.srcGUID and guidToClass[ev.srcGUID]))
            if dbEntry then cat = dbEntry.cat end
            table.insert(feed, {
                time = ev.t, type = "cast_success", cat = cat,
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
            })

        elseif evType == "cast_start" then
            table.insert(feed, {
                time = ev.t, type = "cast_start", cat = "cast",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
            })

        elseif evType == "interrupt" then
            table.insert(feed, {
                time = ev.t, type = "interrupt", cat = "interrupt",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                extraSpell = ev.extraSpell,
            })

        elseif evType == "dispel" then
            table.insert(feed, {
                time = ev.t, type = "dispel", cat = "dispel",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                extraSpell = ev.extraSpell,
            })

        elseif evType == "steal" then
            table.insert(feed, {
                time = ev.t, type = "steal", cat = "dispel",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                extraSpell = ev.extraSpell,
            })

        elseif evType == "aura_applied" then
            table.insert(feed, {
                time = ev.t, type = "aura_applied", cat = "aura",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                auraType = ev.auraType,
            })

        elseif evType == "aura_removed" then
            table.insert(feed, {
                time = ev.t, type = "aura_removed", cat = "aura",
                spellName = ev.spell, spellID = ev.spellID,
                dstName = ev.dst,
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                auraType = ev.auraType,
            })

        elseif evType == "aura_break" then
            table.insert(feed, {
                time = ev.t, type = "aura_break", cat = "aura",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                extraSpell = ev.extraSpell,
            })

        elseif evType == "miss" then
            -- Swing/ranged misses (parry, dodge, block…) carry no spell name;
            -- label them like the damage branch instead of showing "?".
            local missSpell = ev.spell
            if ev.subtype == "swing" then missSpell = "Melee"
            elseif ev.subtype == "range" then missSpell = "Auto Shot"
            end
            table.insert(feed, {
                time = ev.t, type = "miss", cat = "miss",
                spellName = missSpell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                missType = ev.missType,
            })

        elseif evType == "absorb" then
            table.insert(feed, {
                time = ev.t, type = "absorb", cat = "healing",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                amount = ev.amount,
            })

        elseif evType == "summon" then
            table.insert(feed, {
                time = ev.t, type = "summon", cat = "cast",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
            })

        elseif evType == "energize" or evType == "drain" then
            table.insert(feed, {
                time = ev.t, type = evType, cat = "power",
                spellName = ev.spell, spellID = ev.spellID,
                srcName = ev.src, dstName = ev.dst,
                srcClass = ev.srcGUID and guidToClass[ev.srcGUID],
                dstClass = ev.dstGUID and guidToClass[ev.dstGUID],
                amount = ev.amount,
            })

        elseif evType == "cast_fail" then
            -- skip: not useful for replay
        end

        -- Keep a reference (not a copy) to the raw recorded event on every
        -- feed entry so dev mode can surface it (raw-event tooltip in the
        -- replay feed).
        if #feed > countBefore then
            feed[#feed].raw = ev
        end
    end
    return feed
end

---------------------------------------------------------------------------
-- Build timeline markers for the scrubber (curated overview set)
-- Returns array of { time, cat, label, player, team }
---------------------------------------------------------------------------
local function BuildTimelineMarkers(parsedData)
    local markers = {}
    local roster = parsedData.roster
    for _, ev in ipairs(parsedData.events) do
        if ev.type == "death" then
            local info = ev.dstGUID and roster[ev.dstGUID]
            table.insert(markers, {
                time = ev.t, cat = "death",
                label = ev.dst, player = ev.dst,
                team = info and info.team,
            })
        elseif ev.type == "cast_success" then
            -- Pet casts attribute to the owner for team/class context.
            local info = ev.srcGUID and (roster[ev.srcGUID]
                or (parsedData.petOwner and roster[parsedData.petOwner[ev.srcGUID]]))
            local dbEntry = select(2, ResolveSpell(ev.spellID, ev.spell, info and info.class))
            if dbEntry then
                local cat = dbEntry.cat
                if cat == "trinket" or cat == "racial" or cat == "cc_break"
                    or cat == "offensive_cd" or cat == "defensive_cd" or cat == "interrupt" then
                    table.insert(markers, {
                        time = ev.t, cat = cat,
                        label = ev.spell,
                        player = ev.src or (info and info.name),
                        team = info and info.team,
                    })
                end
            end
        end
    end
    return markers
end

---------------------------------------------------------------------------
-- Build search-filtered markers: all deaths + any cast_success whose spell
-- name matches the query substring (case-insensitive). Used when the user
-- types in the tick-search box.
-- Returns array of { time, cat, label, player, team }
---------------------------------------------------------------------------
local function BuildSearchMarkers(parsedData, query)
    local markers = {}
    local roster = parsedData.roster
    local q = query and query:lower() or ""
    for _, ev in ipairs(parsedData.events) do
        if ev.type == "death" then
            local info = ev.dstGUID and roster[ev.dstGUID]
            table.insert(markers, {
                time = ev.t, cat = "death",
                label = ev.dst, player = ev.dst,
                team = info and info.team,
            })
        elseif ev.type == "cast_success" and ev.spell then
            if ev.spell:lower():find(q, 1, true) then
                local info = ev.srcGUID and (roster[ev.srcGUID]
                    or (parsedData.petOwner and roster[parsedData.petOwner[ev.srcGUID]]))
                local dbEntry = select(2, ResolveSpell(ev.spellID, ev.spell, info and info.class))
                table.insert(markers, {
                    time = ev.t,
                    cat = (dbEntry and dbEntry.cat) or "cast",
                    label = ev.spell,
                    player = ev.src or (info and info.name),
                    team = info and info.team,
                })
            end
        end
    end
    return markers
end

---------------------------------------------------------------------------
-- Replay session object
---------------------------------------------------------------------------
function addon:CreateReplaySession(eventLogStr)
    local parsed, err = self:DecompressGameLog(eventLogStr)
    if not parsed then
        return nil, err
    end

    local initialState = BuildInitialState(parsed)
    local feedEvents = BuildFeedEvents(parsed)
    local markers = BuildTimelineMarkers(parsed)

    local session = {
        parsed = parsed,
        initialState = initialState,
        state = CopyState(initialState),
        feedEvents = feedEvents,
        markers = markers,

        -- Playback state
        status = "stopped",
        currentTime = 0,
        cursorIndex = 1,
        speed = 1,
        matchDuration = parsed.matchDuration,
        seeking = false,
    }

    -- Seek to a specific time
    function session:SeekTo(targetTime)
        self.seeking = true
        self.state = CopyState(self.initialState)
        self.cursorIndex = 1
        local events = self.parsed.events
        while self.cursorIndex <= #events and events[self.cursorIndex].t <= targetTime do
            ProcessEvent(self.state, events[self.cursorIndex])
            self.cursorIndex = self.cursorIndex + 1
        end
        self.currentTime = targetTime
    end

    -- Advance playback by dt seconds
    function session:Advance(dt)
        if self.status ~= "playing" then return end
        self.seeking = false
        self.currentTime = math.min(self.currentTime + dt * self.speed, self.matchDuration)
        local events = self.parsed.events
        while self.cursorIndex <= #events and events[self.cursorIndex].t <= self.currentTime do
            ProcessEvent(self.state, events[self.cursorIndex])
            self.cursorIndex = self.cursorIndex + 1
        end
        if self.currentTime >= self.matchDuration then
            self.status = "paused"
        end
    end

    function session:Play()
        if self.currentTime >= self.matchDuration then
            self:SeekTo(0)
        end
        self.status = "playing"
        self.seeking = false
    end

    function session:Pause()
        self.status = "paused"
    end

    function session:TogglePlayPause()
        if self.status == "playing" then
            self:Pause()
        else
            self:Play()
        end
    end

    function session:SetSpeed(speed)
        self.speed = speed
    end

    -- Return markers for the scrub track. Empty query → curated overview set.
    -- Non-empty query → all deaths + cast_success events whose spell name
    -- substring-matches the query.
    function session:GetMarkersForQuery(query)
        if not query or query == "" then
            return self.markers
        end
        return BuildSearchMarkers(self.parsed, query)
    end

    function session:Destroy()
        self.parsed = nil
        self.state = nil
        self.initialState = nil
        self.feedEvents = nil
        self.markers = nil
    end

    return session
end
