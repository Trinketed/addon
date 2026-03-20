# Replay Viewer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-game arena match replay viewer to TrinketedHistory that reconstructs matches from recorded CLEU events with unit frames, event feed, and playback controls.

**Architecture:** Three new files loaded by TrinketedHistory: a spell database (`ReplaySpells.lua`), a playback engine + replay state manager (`ReplayEngine.lua`), and the replay window UI (`ReplayUI.lua`). The existing `Core.lua` gets minimal changes — a "Replay" button on match rows and a function to open the viewer. The engine is decoupled from the UI: it maintains replay state and the UI reads from it each frame.

**Tech Stack:** Lua 5.1, WoW Retail API (Interface 110207), TrinketedLib widgets, LibDeflate, LibStub.

**Spec:** `docs/superpowers/specs/2026-03-11-replay-viewer-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `TrinketedHistory/ReplaySpells.lua` | Spell database: `REPLAY_SPELLS` table mapping spell names to `{id, cat, dur}` for TBC 2.4.3 arena spells |
| `TrinketedHistory/ReplayEngine.lua` | Playback engine: decompression, replay state, event processing, seeking, clock/speed control |
| `TrinketedHistory/ReplayUI.lua` | Replay window: unit frames, event feed, timeline scrubber, transport controls |
| `TrinketedHistory/Core.lua` | (modify) Add "Replay" button to match rows, wire up to open replay window |
| `TrinketedHistory/TrinketedHistory.toc` | (modify) Add new files to load order |

---

## Chunk 1: Foundation — Spell Database, TOC, and Engine Skeleton

### Task 1: Create the spell database file

**Files:**
- Create: `TrinketedHistory/ReplaySpells.lua`

This file defines the `REPLAY_SPELLS` table on the `TrinketedHistory` addon table. Reference `TrinketedCD/CooldownData.lua` for correct spell IDs and names — it uses the exact spell names that appear in CLEU events. Categories for the replay viewer differ from TrinketedCD's categories: we use `"cc"`, `"defensive"`, `"offensive"`, `"trinket"`.

- [ ] **Step 1: Create `ReplaySpells.lua` with the full spell database**

```lua
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
    ["Kidney Shot"]             = { id = 8643,  cat = "cc" },  -- varies by combo pts
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
    ["Blessing of Sacrifice"]   = { id = 27147, cat = "defensive", dur = 10 },
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
    ["Will of the Forsaken"]    = { id = 7744,  cat = "trinket" },
}
```

Cross-reference the spell IDs with `TrinketedCD/CooldownData.lua` to verify they match what CLEU actually records. Add or adjust entries based on the existing cooldown database. This list is a starting point — the user can expand it over time.

- [ ] **Step 2: Commit**

```bash
git add TrinketedHistory/ReplaySpells.lua
git commit -m "feat(replay): add TBC arena spell database for replay viewer"
```

### Task 2: Update the TOC file

**Files:**
- Modify: `TrinketedHistory/TrinketedHistory.toc`

- [ ] **Step 1: Add new files to the TOC load order**

The TOC currently has only `Core.lua`. Add the three new files before `Core.lua` so the data and engine are available when Core initializes:

```
## Interface: 110207
## Title: Trinketed - History
## Notes: Arena match history and VOD timestamps
## Author: apwek
## Version: @project-version@
## Dependencies: Trinketed
## SavedVariables: TrinketedHistoryDB

ReplaySpells.lua
ReplayEngine.lua
ReplayUI.lua
Core.lua
```

- [ ] **Step 2: Commit**

```bash
git add TrinketedHistory/TrinketedHistory.toc
git commit -m "feat(replay): add replay files to TOC load order"
```

### Task 3: Create the replay engine skeleton

**Files:**
- Create: `TrinketedHistory/ReplayEngine.lua`

The engine is responsible for: decompressing game logs, managing replay state (per-player HP/power/auras/cooldowns), processing CLEU events to advance state, and handling the playback clock. The UI reads from `addon.replay` state each frame.

- [ ] **Step 1: Create `ReplayEngine.lua` with decompression and state initialization**

```lua
---------------------------------------------------------------------------
-- TrinketedHistory: ReplayEngine.lua
-- Playback engine: decompression, state management, event processing
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local LibDeflate = LibStub("LibDeflate")

local REPLAY_SPELLS = addon.REPLAY_SPELLS

---------------------------------------------------------------------------
-- Hex color string to r,g,b floats (for CLASS_COLORS "ffc79c6e" format)
---------------------------------------------------------------------------
local function HexToRGB(hex)
    -- Strip leading "ff" alpha if present
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
-- Damage suffixes that subtract from HP
---------------------------------------------------------------------------
local DAMAGE_EVENTS = {
    SWING_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    RANGE_DAMAGE = true,
    DAMAGE_SHIELD = true,
    ENVIRONMENTAL_DAMAGE = true,
}

---------------------------------------------------------------------------
-- Heal suffixes that add to HP
---------------------------------------------------------------------------
local HEAL_EVENTS = {
    SPELL_HEAL = true,
    SPELL_PERIODIC_HEAL = true,
}

---------------------------------------------------------------------------
-- Decompress a gameLog string into parsed data
-- Returns: { initialState, events, matchDuration } or nil, errorMsg
---------------------------------------------------------------------------
function addon:DecompressGameLog(gameLogStr)
    if not gameLogStr or gameLogStr == "" then
        return nil, "No game log data."
    end

    local decoded = LibDeflate:DecodeForPrint(gameLogStr)
    if not decoded then return nil, "Failed to decode game log." end

    local json = LibDeflate:DecompressZlib(decoded)
    if not json then return nil, "Failed to decompress game log." end

    -- JSONToTable is local in Core.lua, so we use the global reference set there
    local data = addon.JSONToTable(json)
    if not data then return nil, "Failed to parse game log JSON." end

    if data.v ~= 1 then
        return nil, "Unsupported game log version: " .. tostring(data.v)
    end

    local events = data.events
    if not events or #events == 0 then
        return nil, "No events in game log."
    end

    local initialState = data.initialState or { players = {}, timestamp = events[1][1] }
    local baseTs = initialState.timestamp

    -- Convert all event timestamps to match-relative seconds
    for _, ev in ipairs(events) do
        ev[1] = ev[1] - baseTs
    end
    initialState.timestamp = 0

    local matchDuration = events[#events][1]

    return {
        initialState = initialState,
        events = events,
        matchDuration = matchDuration,
    }
end

---------------------------------------------------------------------------
-- Build initial replay state from parsed data
---------------------------------------------------------------------------
local function BuildInitialState(parsedData)
    local state = { players = {} }
    for guid, info in pairs(parsedData.initialState.players) do
        state.players[guid] = {
            name = info.name,
            class = info.class,
            team = info.team,
            health = info.health or 0,
            healthMax = info.healthMax or 0,
            power = info.power or 0,
            powerMax = info.powerMax or 0,
            powerType = info.powerType or 0,
            auras = {},
            cooldowns = {},
            alive = true,
        }
    end
    return state
end

---------------------------------------------------------------------------
-- Deep-copy replay state (for reset during seek)
---------------------------------------------------------------------------
local function CopyState(src)
    local dst = { players = {} }
    for guid, p in pairs(src.players) do
        dst.players[guid] = {
            name = p.name,
            class = p.class,
            team = p.team,
            health = p.health,
            healthMax = p.healthMax,
            power = p.power,
            powerMax = p.powerMax,
            powerType = p.powerType,
            auras = {},
            cooldowns = {},
            alive = p.alive,
        }
    end
    return dst
end

---------------------------------------------------------------------------
-- Process a single CLEU event and update replay state
-- ev format: { relativeTs, subevent, hideCaster, srcGUID, srcName,
--              srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags,
--              dstRaidFlags, spellID/swingAmount, spellName/..., ... }
---------------------------------------------------------------------------
local function ProcessEvent(state, ev, currentTime)
    local subevent = ev[2]
    local srcGUID = ev[4]
    local srcName = ev[5]
    local dstGUID = ev[8]
    local dstName = ev[9]

    -- Ensure player entries exist for GUIDs we haven't seen
    if srcGUID and not state.players[srcGUID] and srcName then
        state.players[srcGUID] = {
            name = srcName,
            class = nil,
            team = nil,
            health = 0,
            healthMax = 0,
            power = 0,
            powerMax = 0,
            powerType = 0,
            auras = {},
            cooldowns = {},
            alive = true,
        }
    end
    if dstGUID and not state.players[dstGUID] and dstName then
        state.players[dstGUID] = {
            name = dstName,
            class = nil,
            team = nil,
            health = 0,
            healthMax = 0,
            power = 0,
            powerMax = 0,
            powerType = 0,
            auras = {},
            cooldowns = {},
            alive = true,
        }
    end

    -- Damage events
    if DAMAGE_EVENTS[subevent] then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount
            if subevent == "SWING_DAMAGE" then
                amount = ev[12]  -- swing damage: amount is at position 12
            elseif subevent == "ENVIRONMENTAL_DAMAGE" then
                amount = ev[13]
            else
                amount = ev[15]  -- spell/range damage: spellID(12), spellName(13), spellSchool(14), amount(15)
            end
            if amount and type(amount) == "number" then
                player.health = math.max(0, player.health - amount)
            end
        end

    -- Heal events
    elseif HEAL_EVENTS[subevent] then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount = ev[15]       -- spellID(12), spellName(13), spellSchool(14), amount(15)
            local overhealing = ev[16]  -- overhealing(16)
            if amount and type(amount) == "number" then
                local effective = amount - (overhealing or 0)
                player.health = math.min(player.healthMax, player.health + effective)
            end
        end

    -- Power events
    elseif subevent == "SPELL_ENERGIZE" or subevent == "SPELL_PERIODIC_ENERGIZE" then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount = ev[15]
            if amount and type(amount) == "number" then
                player.power = math.min(player.powerMax, player.power + amount)
            end
        end

    elseif subevent == "SPELL_DRAIN" or subevent == "SPELL_LEECH" then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount = ev[15]
            if amount and type(amount) == "number" then
                player.power = math.max(0, player.power - amount)
            end
        end
        -- SPELL_LEECH also energizes the source
        if subevent == "SPELL_LEECH" then
            local source = srcGUID and state.players[srcGUID]
            if source then
                local extraAmount = ev[17]
                if extraAmount and type(extraAmount) == "number" then
                    source.power = math.min(source.powerMax, source.power + extraAmount)
                end
            end
        end

    -- Death
    elseif subevent == "UNIT_DIED" then
        local player = dstGUID and state.players[dstGUID]
        if player then
            player.health = 0
            player.alive = false
        end

    -- Aura applied
    elseif subevent == "SPELL_AURA_APPLIED" then
        local spellName = ev[13]
        local spellID = ev[12]
        local auraType = ev[15]  -- "BUFF" or "DEBUFF"
        if spellName and REPLAY_SPELLS[spellName] then
            local player = dstGUID and state.players[dstGUID]
            if player then
                local spellInfo = REPLAY_SPELLS[spellName]
                player.auras[spellName] = {
                    spellID = spellID,
                    applied = currentTime,
                    duration = spellInfo.dur,
                    isDebuff = (auraType == "DEBUFF"),
                    cat = spellInfo.cat,
                }
            end
        end

    -- Aura removed
    elseif subevent == "SPELL_AURA_REMOVED" then
        local spellName = ev[13]
        if spellName and REPLAY_SPELLS[spellName] then
            local player = dstGUID and state.players[dstGUID]
            if player then
                player.auras[spellName] = nil
            end
        end

    -- Cooldown tracking via cast success
    elseif subevent == "SPELL_CAST_SUCCESS" then
        local spellName = ev[13]
        local spellID = ev[12]
        if spellName and REPLAY_SPELLS[spellName] then
            local spellInfo = REPLAY_SPELLS[spellName]
            local cat = spellInfo.cat
            if cat == "trinket" or cat == "offensive" or cat == "defensive" then
                local player = srcGUID and state.players[srcGUID]
                if player then
                    player.cooldowns[spellName] = {
                        spellID = spellID,
                        cast = currentTime,
                        duration = spellInfo.dur,
                    }
                end
            end
        end
    end
end
addon.ProcessEvent = ProcessEvent

---------------------------------------------------------------------------
-- Build filtered event list for the event feed
-- Returns array of { time, subevent, spellName, spellID, srcName, dstName,
--                     srcClass, dstClass, cat, amount, duration }
---------------------------------------------------------------------------
local function BuildFeedEvents(parsedData, state)
    local feed = {}
    local initialPlayers = parsedData.initialState.players

    -- Build GUID->class lookup from initial state
    local guidToClass = {}
    for guid, info in pairs(initialPlayers) do
        guidToClass[guid] = info.class
    end

    for _, ev in ipairs(parsedData.events) do
        local subevent = ev[2]
        local srcGUID = ev[4]
        local srcName = ev[5]
        local dstGUID = ev[8]
        local dstName = ev[9]

        local spellName, spellID, cat, amount, duration

        if subevent == "UNIT_DIED" then
            cat = "death"
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = "death",
                srcName = nil,
                dstName = dstName,
                srcClass = nil,
                dstClass = dstGUID and guidToClass[dstGUID],
            })
        elseif DAMAGE_EVENTS[subevent] then
            -- Exclude swing damage and environmental (auto-attacks/passive)
            -- Only include named spell damage
            if subevent ~= "SWING_DAMAGE" and subevent ~= "ENVIRONMENTAL_DAMAGE" then
                spellID = ev[12]
                spellName = ev[13]
                amount = ev[15]
                if spellName then
                    table.insert(feed, {
                        time = ev[1],
                        subevent = subevent,
                        cat = "damage",
                        spellName = spellName,
                        spellID = spellID,
                        srcName = srcName,
                        dstName = dstName,
                        srcClass = srcGUID and guidToClass[srcGUID],
                        dstClass = dstGUID and guidToClass[dstGUID],
                        amount = amount,
                    })
                end
            end
        elseif HEAL_EVENTS[subevent] then
            spellID = ev[12]
            spellName = ev[13]
            amount = ev[15]
            local overhealing = ev[16] or 0
            if spellName then
                table.insert(feed, {
                    time = ev[1],
                    subevent = subevent,
                    cat = "healing",
                    spellName = spellName,
                    spellID = spellID,
                    srcName = srcName,
                    dstName = dstName,
                    srcClass = srcGUID and guidToClass[srcGUID],
                    dstClass = dstGUID and guidToClass[dstGUID],
                    amount = amount - overhealing,
                })
            end
        elseif subevent == "SPELL_AURA_APPLIED" then
            spellName = ev[13]
            spellID = ev[12]
            if spellName and REPLAY_SPELLS[spellName] then
                local info = REPLAY_SPELLS[spellName]
                table.insert(feed, {
                    time = ev[1],
                    subevent = subevent,
                    cat = info.cat,
                    spellName = spellName,
                    spellID = spellID,
                    srcName = srcName,
                    dstName = dstName,
                    srcClass = srcGUID and guidToClass[srcGUID],
                    dstClass = dstGUID and guidToClass[dstGUID],
                    duration = info.dur,
                })
            end
        elseif subevent == "SPELL_CAST_SUCCESS" then
            spellName = ev[13]
            spellID = ev[12]
            if spellName and REPLAY_SPELLS[spellName] then
                local info = REPLAY_SPELLS[spellName]
                if info.cat == "trinket" or info.cat == "offensive" or info.cat == "defensive" then
                    table.insert(feed, {
                        time = ev[1],
                        subevent = subevent,
                        cat = info.cat,
                        spellName = spellName,
                        spellID = spellID,
                        srcName = srcName,
                        dstName = dstName,
                        srcClass = srcGUID and guidToClass[srcGUID],
                        dstClass = dstGUID and guidToClass[dstGUID],
                    })
                end
            end
        end
    end
    return feed
end

---------------------------------------------------------------------------
-- Build timeline markers for the scrubber
-- Returns array of { time, cat, label }
---------------------------------------------------------------------------
local function BuildTimelineMarkers(parsedData)
    local markers = {}
    for _, ev in ipairs(parsedData.events) do
        local subevent = ev[2]
        if subevent == "UNIT_DIED" then
            table.insert(markers, { time = ev[1], cat = "death", label = ev[9] })
        elseif subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_AURA_APPLIED" then
            local spellName = ev[13]
            if spellName and REPLAY_SPELLS[spellName] then
                local info = REPLAY_SPELLS[spellName]
                if info.cat == "trinket" or info.cat == "offensive" or info.cat == "defensive" then
                    table.insert(markers, { time = ev[1], cat = info.cat, label = spellName })
                end
            end
        end
    end
    return markers
end

---------------------------------------------------------------------------
-- Replay session object
-- Created when user opens replay, destroyed on close
---------------------------------------------------------------------------
function addon:CreateReplaySession(gameLogStr)
    local parsed, err = self:DecompressGameLog(gameLogStr)
    if not parsed then
        return nil, err
    end

    local initialState = BuildInitialState(parsed)
    local feedEvents = BuildFeedEvents(parsed, initialState)
    local markers = BuildTimelineMarkers(parsed)

    local session = {
        parsed = parsed,
        initialState = initialState,
        state = CopyState(initialState),
        feedEvents = feedEvents,
        markers = markers,

        -- Playback state
        status = "stopped",   -- "stopped", "playing", "paused"
        currentTime = 0,
        cursorIndex = 1,
        speed = 1,
        matchDuration = parsed.matchDuration,
        seeking = false,      -- true during seek (disables lerp)
    }

    -- Seek to a specific time
    function session:SeekTo(targetTime)
        self.seeking = true
        self.state = CopyState(self.initialState)
        self.cursorIndex = 1
        local events = self.parsed.events
        while self.cursorIndex <= #events and events[self.cursorIndex][1] <= targetTime do
            ProcessEvent(self.state, events[self.cursorIndex], events[self.cursorIndex][1])
            self.cursorIndex = self.cursorIndex + 1
        end
        self.currentTime = targetTime
    end

    -- Advance playback by dt seconds (called from OnUpdate)
    function session:Advance(dt)
        if self.status ~= "playing" then return end
        self.seeking = false
        self.currentTime = math.min(self.currentTime + dt * self.speed, self.matchDuration)
        local events = self.parsed.events
        while self.cursorIndex <= #events and events[self.cursorIndex][1] <= self.currentTime do
            ProcessEvent(self.state, events[self.cursorIndex], events[self.cursorIndex][1])
            self.cursorIndex = self.cursorIndex + 1
        end
        -- Auto-pause at end
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

    function session:Destroy()
        self.parsed = nil
        self.state = nil
        self.initialState = nil
        self.feedEvents = nil
        self.markers = nil
    end

    return session
end
```

Note: `addon.JSONToTable` must be exposed from Core.lua. We'll wire that up in Task 7.

- [ ] **Step 2: Commit**

```bash
git add TrinketedHistory/ReplayEngine.lua
git commit -m "feat(replay): add playback engine with decompression, state management, and event processing"
```

---

## Chunk 2: Replay Window UI

### Task 4: Create the replay window frame and layout

**Files:**
- Create: `TrinketedHistory/ReplayUI.lua`

This is the largest file. It creates the replay window with three zones (unit frames, event feed, transport bar) and wires them to the replay session.

- [ ] **Step 1: Create `ReplayUI.lua` with the window frame, unit frames panel, and transport bar**

```lua
---------------------------------------------------------------------------
-- TrinketedHistory: ReplayUI.lua
-- Replay viewer window: unit frames, event feed, timeline, transport
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C
local REPLAY_SPELLS = addon.REPLAY_SPELLS

local replayFrame = nil
local session = nil

-- Layout constants
local FRAME_W, FRAME_H = 950, 560
local UNIT_PANEL_W = 600
local FEED_PANEL_W = 330
local TRANSPORT_H = 40
local UNIT_FRAME_W = 270
local UNIT_FRAME_H = 55
local HP_BAR_H = 12
local POWER_BAR_H = 6
local ICON_SIZE = 16
local ICON_GAP = 2
local FEED_ROW_H = 18

local SPEEDS = { 0.5, 1, 2, 4 }
local speedIndex = 2  -- default 1x

---------------------------------------------------------------------------
-- Helper: format seconds as m:ss
---------------------------------------------------------------------------
local function FormatTime(secs)
    if not secs or secs < 0 then secs = 0 end
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    return string.format("%d:%02d", m, s)
end

---------------------------------------------------------------------------
-- Helper: format seconds as m:ss.t (with tenths)
---------------------------------------------------------------------------
local function FormatTimeTenths(secs)
    if not secs or secs < 0 then secs = 0 end
    local m = math.floor(secs / 60)
    local s = secs % 60
    return string.format("%d:%04.1f", m, s)
end

---------------------------------------------------------------------------
-- Helper: abbreviate number (1234 -> "1.2k")
---------------------------------------------------------------------------
local function AbbrevNumber(n)
    if not n or type(n) ~= "number" then return "" end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(math.floor(n))
end

---------------------------------------------------------------------------
-- Helper: get class color string for inline use
---------------------------------------------------------------------------
local CLASS_COLOR_HEX = {
    ["Warrior"] = "c79c6e", ["Paladin"] = "f58cba", ["Hunter"] = "abd473",
    ["Rogue"] = "fff569", ["Priest"] = "ffffff", ["Shaman"] = "0070de",
    ["Mage"] = "69ccf0", ["Warlock"] = "9482c9", ["Druid"] = "ff7d0a",
}
addon.CLASS_COLOR_HEX = CLASS_COLOR_HEX  -- shared with engine

local function ClassColorStr(class)
    local hex = class and CLASS_COLOR_HEX[class]
    if hex then return "|cff" .. hex end
    return "|cffffffff"
end

---------------------------------------------------------------------------
-- Category colors for feed and markers
---------------------------------------------------------------------------
local CAT_COLORS = {
    cc        = { r = 0.3, g = 0.6, b = 1.0 },
    damage    = { r = 1.0, g = 0.3, b = 0.3 },
    healing   = { r = 0.3, g = 1.0, b = 0.3 },
    death     = { r = 1.0, g = 0.1, b = 0.1 },
    defensive = { r = 0.91, g = 0.73, b = 0.14 },
    offensive = { r = 1.0, g = 0.5, b = 0.1 },
    trinket   = { r = 0.91, g = 0.73, b = 0.14 },
}

---------------------------------------------------------------------------
-- Create a single unit frame
---------------------------------------------------------------------------
local function CreateUnitFrame(parent, yOffset)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(UNIT_FRAME_W, UNIT_FRAME_H)
    f:SetPoint("TOPLEFT", 10, yOffset)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    f:SetBackdropColor(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], C.bgRaised[4])
    f:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], C.borderSubtle[4])

    -- Name label
    f.nameText = f:CreateFontString(nil, "OVERLAY")
    f.nameText:SetFont(lib.FONT_BODY, 10, "")
    f.nameText:SetPoint("TOPLEFT", 4, -3)
    f.nameText:SetWidth(UNIT_FRAME_W - 60)
    f.nameText:SetJustifyH("LEFT")

    -- HP text (current/max)
    f.hpText = f:CreateFontString(nil, "OVERLAY")
    f.hpText:SetFont(lib.FONT_MONO, 9, "")
    f.hpText:SetPoint("TOPRIGHT", -4, -3)
    f.hpText:SetJustifyH("RIGHT")
    f.hpText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- HP bar background
    f.hpBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.hpBarBg:SetPoint("TOPLEFT", 3, -15)
    f.hpBarBg:SetSize(UNIT_FRAME_W - 6, HP_BAR_H)
    f.hpBarBg:SetColorTexture(0, 0, 0, 0.5)

    -- HP bar fill
    f.hpBar = f:CreateTexture(nil, "ARTWORK")
    f.hpBar:SetPoint("TOPLEFT", f.hpBarBg, "TOPLEFT")
    f.hpBar:SetHeight(HP_BAR_H)
    f.hpBar:SetColorTexture(0.5, 0.5, 0.5, 1)

    -- Power bar background
    f.powerBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.powerBarBg:SetPoint("TOPLEFT", f.hpBarBg, "BOTTOMLEFT", 0, -1)
    f.powerBarBg:SetSize(UNIT_FRAME_W - 6, POWER_BAR_H)
    f.powerBarBg:SetColorTexture(0, 0, 0, 0.5)

    -- Power bar fill
    f.powerBar = f:CreateTexture(nil, "ARTWORK")
    f.powerBar:SetPoint("TOPLEFT", f.powerBarBg, "TOPLEFT")
    f.powerBar:SetHeight(POWER_BAR_H)
    f.powerBar:SetColorTexture(0, 0, 1, 1)

    -- Icon row container (for auras/cooldowns)
    f.iconRow = CreateFrame("Frame", nil, f)
    f.iconRow:SetPoint("TOPLEFT", f.powerBarBg, "BOTTOMLEFT", 0, -2)
    f.iconRow:SetSize(UNIT_FRAME_W - 6, ICON_SIZE)

    f.icons = {}   -- pool of icon frames

    -- State tracking for lerp
    f.targetHealth = 0
    f.displayHealth = 0
    f.guid = nil

    return f
end

---------------------------------------------------------------------------
-- Update a unit frame from replay state
---------------------------------------------------------------------------
local function UpdateUnitFrame(uf, playerState, currentTime, seeking)
    if not playerState then
        uf:Hide()
        return
    end
    uf:Show()

    -- Name + spec + class color
    local name = playerState.name or "?"
    if playerState.spec then
        name = name .. " (" .. playerState.spec .. ")"
    end
    local classColor = addon.CLASS_COLORS_RGB[playerState.class]
    if classColor then
        uf.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    else
        uf.nameText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    end
    uf.nameText:SetText(name)

    -- HP
    local hp = playerState.health
    local hpMax = playerState.healthMax
    uf.targetHealth = hp

    if seeking then
        uf.displayHealth = hp
    end
    -- Lerp display health toward target
    local displayHP = uf.displayHealth
    if math.abs(displayHP - hp) > 1 then
        uf.displayHealth = displayHP + (hp - displayHP) * 0.15
    else
        uf.displayHealth = hp
    end

    local barWidth = UNIT_FRAME_W - 6
    local hpFrac = hpMax > 0 and (uf.displayHealth / hpMax) or 0
    uf.hpBar:SetWidth(math.max(1, barWidth * hpFrac))

    -- HP bar color by class
    if classColor then
        uf.hpBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
    end

    -- HP text
    if hpMax > 0 then
        uf.hpText:SetText(math.floor(uf.displayHealth) .. "/" .. hpMax)
    else
        uf.hpText:SetText("?")
    end

    -- Power
    local power = playerState.power
    local powerMax = playerState.powerMax
    local powerType = playerState.powerType
    if powerMax > 0 then
        uf.powerBarBg:Show()
        uf.powerBar:Show()
        local powerFrac = power / powerMax
        uf.powerBar:SetWidth(math.max(1, barWidth * powerFrac))
        local pc = addon.POWER_COLORS[powerType]
        if pc then
            uf.powerBar:SetColorTexture(pc.r, pc.g, pc.b, 1)
        end
    else
        uf.powerBarBg:Hide()
        uf.powerBar:Hide()
    end

    -- Icons: auras + cooldowns
    local iconIdx = 0

    -- Active auras
    for spellName, aura in pairs(playerState.auras) do
        iconIdx = iconIdx + 1
        local icon = uf.icons[iconIdx]
        if not icon then
            icon = CreateFrame("Frame", nil, uf.iconRow)
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon.tex = icon:CreateTexture(nil, "ARTWORK")
            icon.tex:SetAllPoints()
            icon.border = icon:CreateTexture(nil, "OVERLAY")
            icon.border:SetPoint("TOPLEFT", -1, 1)
            icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
            icon.border:SetColorTexture(1, 0, 0, 1)
            icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            icon.cooldown:SetAllPoints()
            icon.cooldown:SetDrawEdge(false)
            uf.icons[iconIdx] = icon
        end
        icon:SetPoint("TOPLEFT", (iconIdx - 1) * (ICON_SIZE + ICON_GAP), 0)
        -- Icon texture
        local texID = aura.spellID and GetSpellTexture(aura.spellID)
        if texID then
            icon.tex:SetTexture(texID)
        else
            icon.tex:SetColorTexture(0.3, 0.3, 0.3, 1)
        end
        -- Border color: red for debuff, green for buff
        if aura.isDebuff then
            icon.border:SetColorTexture(1, 0, 0, 0.8)
        else
            icon.border:SetColorTexture(0, 1, 0, 0.8)
        end
        -- Duration sweep
        if aura.duration and aura.applied then
            icon.cooldown:SetCooldown(GetTime() - (currentTime - aura.applied), aura.duration)
            icon.cooldown:Show()
        else
            icon.cooldown:Hide()
        end
        icon:Show()
    end

    -- Active cooldowns
    for spellName, cd in pairs(playerState.cooldowns) do
        if cd.duration and cd.cast then
            local elapsed = currentTime - cd.cast
            if elapsed < cd.duration then
                iconIdx = iconIdx + 1
                local icon = uf.icons[iconIdx]
                if not icon then
                    icon = CreateFrame("Frame", nil, uf.iconRow)
                    icon:SetSize(ICON_SIZE, ICON_SIZE)
                    icon.tex = icon:CreateTexture(nil, "ARTWORK")
                    icon.tex:SetAllPoints()
                    icon.border = icon:CreateTexture(nil, "OVERLAY")
                    icon.border:SetPoint("TOPLEFT", -1, 1)
                    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
                    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
                    icon.cooldown:SetAllPoints()
                    icon.cooldown:SetDrawEdge(false)
                    uf.icons[iconIdx] = icon
                end
                icon:SetPoint("TOPLEFT", (iconIdx - 1) * (ICON_SIZE + ICON_GAP), 0)
                local texID = cd.spellID and GetSpellTexture(cd.spellID)
                if texID then
                    icon.tex:SetTexture(texID)
                    icon.tex:SetDesaturated(true)
                else
                    icon.tex:SetColorTexture(0.2, 0.2, 0.2, 1)
                end
                icon.border:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.8)
                icon.cooldown:SetCooldown(GetTime() - elapsed, cd.duration)
                icon.cooldown:Show()
                icon:Show()
            end
        end
    end

    -- Hide unused icons
    for i = iconIdx + 1, #uf.icons do
        uf.icons[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- Create the main replay window
---------------------------------------------------------------------------
local function CreateReplayFrame()
    if replayFrame then return replayFrame end

    local frame = lib:CreateWindowFrame("TrinketedReplayFrame", {
        width = FRAME_W,
        height = FRAME_H,
        title = "Replay",
        onClose = function()
            if session then
                session:Destroy()
                session = nil
            end
        end,
    })

    -- ===== UNIT FRAMES PANEL (left side) =====
    frame.unitPanel = CreateFrame("Frame", nil, frame)
    frame.unitPanel:SetPoint("TOPLEFT", 6, -30)
    frame.unitPanel:SetSize(UNIT_PANEL_W, FRAME_H - TRANSPORT_H - 36)

    -- Section label: Friendly
    frame.friendlyLabel = frame.unitPanel:CreateFontString(nil, "OVERLAY")
    frame.friendlyLabel:SetFont(lib.FONT_DISPLAY, 10, "")
    frame.friendlyLabel:SetPoint("TOPLEFT", 10, -4)
    frame.friendlyLabel:SetTextColor(C.partyBlue[1], C.partyBlue[2], C.partyBlue[3])
    frame.friendlyLabel:SetText("FRIENDLY TEAM")

    -- Friendly unit frames (up to 5)
    frame.friendlyFrames = {}
    for i = 1, 5 do
        frame.friendlyFrames[i] = CreateUnitFrame(frame.unitPanel, -20 - (i - 1) * (UNIT_FRAME_H + 4))
        frame.friendlyFrames[i]:Hide()
    end

    -- Divider (position set dynamically by RefreshUnitFrames)
    local divider = frame.unitPanel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])
    frame.teamDivider = divider

    -- Section label: Enemy
    frame.enemyLabel = frame.unitPanel:CreateFontString(nil, "OVERLAY")
    frame.enemyLabel:SetFont(lib.FONT_DISPLAY, 10, "")
    frame.enemyLabel:SetTextColor(C.enemyRed[1], C.enemyRed[2], C.enemyRed[3])
    frame.enemyLabel:SetText("ENEMY TEAM")

    -- Enemy unit frames (up to 5)
    frame.enemyFrames = {}
    for i = 1, 5 do
        frame.enemyFrames[i] = CreateUnitFrame(frame.unitPanel, 0) -- positioned dynamically
        frame.enemyFrames[i]:Hide()
    end

    -- ===== EVENT FEED PANEL (right side) =====
    frame.feedPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.feedPanel:SetPoint("TOPLEFT", UNIT_PANEL_W + 6, -30)
    frame.feedPanel:SetPoint("BOTTOMRIGHT", -6, TRANSPORT_H + 6)
    frame.feedPanel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame.feedPanel:SetBackdropColor(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], C.sidebarBg[4])
    frame.feedPanel:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], C.borderDefault[4])

    -- Filter chips using lib:CreateCheckbox() toggle chips with custom group logic
    frame.filterChips = {}
    local filterNames = { "All", "CC", "Dmg", "Heal", "CDs", "Deaths" }
    local filterCats = { "all", "cc", "damage", "healing", "cd", "death" }
    frame.activeFilters = { all = true }

    local chipX = 6
    for idx, label in ipairs(filterNames) do
        local cat = filterCats[idx]
        local isOn = (cat == "all")  -- All starts active

        local function onToggle(newState)
            if cat == "all" then
                frame.activeFilters = { all = true }
            else
                frame.activeFilters.all = nil
                if newState then
                    frame.activeFilters[cat] = true
                else
                    frame.activeFilters[cat] = nil
                    -- If no filters active, re-enable All
                    local anyActive = false
                    for _, c in ipairs(filterCats) do
                        if c ~= "all" and frame.activeFilters[c] then anyActive = true; break end
                    end
                    if not anyActive then
                        frame.activeFilters = { all = true }
                    end
                end
            end
            -- Sync all chip visuals to match activeFilters state
            for _, chip in ipairs(frame.filterChips) do
                local shouldBeOn = frame.activeFilters[chip.cat] or frame.activeFilters.all
                chip.checkbox:SetChecked(shouldBeOn)
            end
            if frame.RefreshFeed then frame:RefreshFeed() end
        end

        -- lib:CreateCheckbox returns the checkbox frame; position in feedPanel
        local checkbox = lib:CreateCheckbox(frame.feedPanel, chipX, -6, label, isOn, onToggle)
        frame.filterChips[idx] = { checkbox = checkbox, cat = cat }
        chipX = chipX + (checkbox:GetWidth() or 40) + 4
    end

    -- Feed scroll frame
    frame.feedScroll = CreateFrame("ScrollFrame", nil, frame.feedPanel, "UIPanelScrollFrameTemplate")
    frame.feedScroll:SetPoint("TOPLEFT", 4, -26)
    frame.feedScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    frame.feedContent = CreateFrame("Frame", nil, frame.feedScroll)
    frame.feedContent:SetWidth(FEED_PANEL_W - 30)
    frame.feedContent:SetHeight(1)
    frame.feedScroll:SetScrollChild(frame.feedContent)

    frame.feedRows = {}  -- row pool

    -- ===== TRANSPORT BAR (bottom) =====
    frame.transport = CreateFrame("Frame", nil, frame)
    frame.transport:SetPoint("BOTTOMLEFT", 6, 6)
    frame.transport:SetPoint("BOTTOMRIGHT", -6, 6)
    frame.transport:SetHeight(TRANSPORT_H)

    -- Jump to start
    local btnStart = CreateFrame("Button", nil, frame.transport)
    btnStart:SetSize(24, 20)
    btnStart:SetPoint("LEFT", 4, 0)
    btnStart.text = btnStart:CreateFontString(nil, "OVERLAY")
    btnStart.text:SetFont(lib.FONT_MONO, 10, "")
    btnStart.text:SetPoint("CENTER")
    btnStart.text:SetText("|<")
    btnStart.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    btnStart:SetScript("OnClick", function()
        if session then session:SeekTo(0); session.status = "paused" end
    end)

    -- Play/pause
    frame.btnPlay = CreateFrame("Button", nil, frame.transport)
    frame.btnPlay:SetSize(24, 20)
    frame.btnPlay:SetPoint("LEFT", btnStart, "RIGHT", 2, 0)
    frame.btnPlay.text = frame.btnPlay:CreateFontString(nil, "OVERLAY")
    frame.btnPlay.text:SetFont(lib.FONT_MONO, 12, "")
    frame.btnPlay.text:SetPoint("CENTER")
    frame.btnPlay.text:SetText(">")
    frame.btnPlay.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    frame.btnPlay:SetScript("OnClick", function()
        if session then session:TogglePlayPause() end
    end)

    -- Jump to end
    local btnEnd = CreateFrame("Button", nil, frame.transport)
    btnEnd:SetSize(24, 20)
    btnEnd:SetPoint("LEFT", frame.btnPlay, "RIGHT", 2, 0)
    btnEnd.text = btnEnd:CreateFontString(nil, "OVERLAY")
    btnEnd.text:SetFont(lib.FONT_MONO, 10, "")
    btnEnd.text:SetPoint("CENTER")
    btnEnd.text:SetText(">|")
    btnEnd.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    btnEnd:SetScript("OnClick", function()
        if session then
            session:SeekTo(session.matchDuration)
            session.status = "paused"
        end
    end)

    -- Speed button
    frame.btnSpeed = CreateFrame("Button", nil, frame.transport)
    frame.btnSpeed:SetSize(34, 20)
    frame.btnSpeed:SetPoint("LEFT", btnEnd, "RIGHT", 8, 0)
    frame.btnSpeed.text = frame.btnSpeed:CreateFontString(nil, "OVERLAY")
    frame.btnSpeed.text:SetFont(lib.FONT_MONO, 10, "")
    frame.btnSpeed.text:SetPoint("CENTER")
    frame.btnSpeed.text:SetText("1x")
    frame.btnSpeed.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    frame.btnSpeed:SetScript("OnClick", function()
        speedIndex = (speedIndex % #SPEEDS) + 1
        local speed = SPEEDS[speedIndex]
        if session then session:SetSpeed(speed) end
        frame.btnSpeed.text:SetText(speed .. "x")
    end)

    -- Timeline scrubber track
    frame.scrubTrack = CreateFrame("Button", nil, frame.transport)
    frame.scrubTrack:SetPoint("LEFT", frame.btnSpeed, "RIGHT", 10, 0)
    frame.scrubTrack:SetPoint("RIGHT", frame.transport, "RIGHT", -70, 0)
    frame.scrubTrack:SetHeight(6)

    frame.scrubTrackBg = frame.scrubTrack:CreateTexture(nil, "BACKGROUND")
    frame.scrubTrackBg:SetAllPoints()
    frame.scrubTrackBg:SetColorTexture(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)

    -- Scrub thumb
    frame.scrubThumb = CreateFrame("Frame", nil, frame.scrubTrack)
    frame.scrubThumb:SetSize(10, 14)
    frame.scrubThumbTex = frame.scrubThumb:CreateTexture(nil, "OVERLAY")
    frame.scrubThumbTex:SetAllPoints()
    frame.scrubThumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Click-to-seek on scrub track
    frame.scrubTrack:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and session then
            local x = self:GetLeft()
            local w = self:GetWidth()
            local cursorX = GetCursorPosition() / self:GetEffectiveScale()
            local frac = math.max(0, math.min(1, (cursorX - x) / w))
            session:SeekTo(frac * session.matchDuration)
            session.status = "paused"
            frame.scrubbing = true
        end
    end)

    frame.scrubTrack:SetScript("OnMouseUp", function()
        frame.scrubbing = false
    end)

    -- Time display
    frame.timeText = frame.transport:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetFont(lib.FONT_MONO, 10, "")
    frame.timeText:SetPoint("RIGHT", -4, 0)
    frame.timeText:SetJustifyH("RIGHT")
    frame.timeText:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    -- ===== ERROR MESSAGE (shown when decompression fails) =====
    frame.errorText = frame:CreateFontString(nil, "OVERLAY")
    frame.errorText:SetFont(lib.FONT_BODY, 12, "")
    frame.errorText:SetPoint("CENTER")
    frame.errorText:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
    frame.errorText:Hide()

    -- ===== TIMELINE MARKERS =====
    frame.markerPool = {}

    -- ===== OnUpdate: advance playback and refresh UI =====
    frame:SetScript("OnUpdate", function(self, dt)
        if not session then return end

        -- Handle scrub dragging
        if frame.scrubbing then
            local x = frame.scrubTrack:GetLeft()
            local w = frame.scrubTrack:GetWidth()
            local cursorX = GetCursorPosition() / frame.scrubTrack:GetEffectiveScale()
            local frac = math.max(0, math.min(1, (cursorX - x) / w))
            session:SeekTo(frac * session.matchDuration)
        end

        -- Advance playback
        session:Advance(dt)

        -- Update play/pause button text
        if session.status == "playing" then
            frame.btnPlay.text:SetText("||")
        else
            frame.btnPlay.text:SetText(">")
        end

        -- Update scrub thumb position
        if session.matchDuration > 0 then
            local frac = session.currentTime / session.matchDuration
            local trackW = frame.scrubTrack:GetWidth()
            frame.scrubThumb:SetPoint("CENTER", frame.scrubTrack, "LEFT", trackW * frac, 0)
        end

        -- Update time display
        frame.timeText:SetText(FormatTime(session.currentTime) .. " / " .. FormatTime(session.matchDuration))

        -- Update unit frames
        frame:RefreshUnitFrames()

        -- Update feed highlight
        frame:RefreshFeedHighlight()
    end)

    -- ===== Refresh unit frame positions and state =====
    function frame:RefreshUnitFrames()
        if not session then return end
        local state = session.state

        -- Sort players into friendly/enemy lists
        local friendly, enemy = {}, {}
        for guid, p in pairs(state.players) do
            if p.team == "friendly" then
                table.insert(friendly, { guid = guid, state = p })
            elseif p.team == "enemy" then
                table.insert(enemy, { guid = guid, state = p })
            end
        end

        -- Position friendly frames
        local friendlyCount = math.min(#friendly, 5)
        for i = 1, 5 do
            if i <= friendlyCount then
                self.friendlyFrames[i]:SetPoint("TOPLEFT", 10, -20 - (i - 1) * (UNIT_FRAME_H + 4))
                UpdateUnitFrame(self.friendlyFrames[i], friendly[i].state,
                    session.currentTime, session.seeking)
            else
                self.friendlyFrames[i]:Hide()
            end
        end

        -- Position divider and enemy label below friendly frames
        local divY = -20 - friendlyCount * (UNIT_FRAME_H + 4) - 4
        self.teamDivider:ClearAllPoints()
        self.teamDivider:SetPoint("TOPLEFT", self.unitPanel, "TOPLEFT", 10, divY)
        self.teamDivider:SetPoint("RIGHT", self.unitPanel, "RIGHT", -10, 0)

        self.enemyLabel:ClearAllPoints()
        self.enemyLabel:SetPoint("TOPLEFT", self.unitPanel, "TOPLEFT", 10, divY - 8)

        local enemyStartY = divY - 24
        local enemyCount = math.min(#enemy, 5)
        for i = 1, 5 do
            if i <= enemyCount then
                self.enemyFrames[i]:SetPoint("TOPLEFT", 10, enemyStartY - (i - 1) * (UNIT_FRAME_H + 4))
                UpdateUnitFrame(self.enemyFrames[i], enemy[i].state,
                    session.currentTime, session.seeking)
            else
                self.enemyFrames[i]:Hide()
            end
        end
    end

    -- ===== Refresh event feed =====
    function frame:RefreshFeed()
        if not session then return end

        -- Hide all rows
        for _, row in ipairs(self.feedRows) do
            row:Hide()
        end

        local feedEvents = session.feedEvents
        local filters = self.activeFilters

        -- Filter events
        local visible = {}
        for _, ev in ipairs(feedEvents) do
            local show = false
            if filters.all then
                show = true
            else
                local cat = ev.cat
                if cat == "cc" and filters.cc then show = true
                elseif cat == "damage" and filters.damage then show = true
                elseif cat == "healing" and filters.healing then show = true
                elseif (cat == "trinket" or cat == "offensive" or cat == "defensive") and filters.cd then show = true
                elseif cat == "death" and filters.death then show = true
                end
            end
            if show then
                table.insert(visible, ev)
            end
        end

        self.visibleFeedEvents = visible

        -- Create/update rows
        local contentHeight = 0
        for idx, ev in ipairs(visible) do
            local row = self.feedRows[idx]
            if not row then
                row = CreateFrame("Button", nil, self.feedContent)
                row:SetSize(FEED_PANEL_W - 30, FEED_ROW_H)

                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetColorTexture(0, 0, 0, 0)

                row.text = row:CreateFontString(nil, "OVERLAY")
                row.text:SetFont(lib.FONT_MONO, 9, "")
                row.text:SetPoint("LEFT", 2, 0)
                row.text:SetPoint("RIGHT", -2, 0)
                row.text:SetJustifyH("LEFT")

                self.feedRows[idx] = row
            end

            row:SetPoint("TOPLEFT", 0, -((idx - 1) * FEED_ROW_H))
            row.eventTime = ev.time

            -- Format the row text
            local timeStr = FormatTimeTenths(ev.time)
            local catColor = CAT_COLORS[ev.cat] or { r = 1, g = 1, b = 1 }
            local catHex = string.format("%02x%02x%02x",
                catColor.r * 255, catColor.g * 255, catColor.b * 255)

            local parts = { "|cff" .. catHex .. timeStr .. "|r" }

            if ev.cat == "death" then
                table.insert(parts, " |cffff0000" .. (ev.dstName or "?") .. " died|r")
            else
                local spellStr = ev.spellName or "?"
                if ev.srcClass then
                    spellStr = ClassColorStr(ev.srcClass) .. spellStr .. "|r"
                end
                table.insert(parts, "  " .. spellStr)

                if ev.srcName and ev.dstName then
                    local src = ClassColorStr(ev.srcClass) .. ev.srcName .. "|r"
                    local dst = ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
                    table.insert(parts, "  " .. src .. " > " .. dst)
                elseif ev.srcName then
                    table.insert(parts, "  " .. ClassColorStr(ev.srcClass) .. ev.srcName .. "|r")
                end

                if ev.amount and ev.amount ~= 0 then
                    table.insert(parts, "  " .. AbbrevNumber(math.abs(ev.amount)))
                end
                if ev.duration then
                    table.insert(parts, "  " .. ev.duration .. "s")
                end
            end

            row.text:SetText(table.concat(parts))

            -- Click to seek
            row:SetScript("OnClick", function()
                if session then
                    session:SeekTo(ev.time)
                    session.status = "paused"
                end
            end)

            row:Show()
            contentHeight = contentHeight + FEED_ROW_H
        end

        self.feedContent:SetHeight(math.max(contentHeight, 1))
    end

    -- ===== Refresh feed highlight and auto-scroll (called from OnUpdate) =====
    function frame:RefreshFeedHighlight()
        if not session or not self.visibleFeedEvents then return end
        local ct = session.currentTime
        local lastPastIdx = nil
        for idx, row in ipairs(self.feedRows) do
            if row:IsShown() and row.eventTime then
                row.bg:SetColorTexture(0, 0, 0, 0)
                if row.eventTime <= ct then
                    row.text:SetAlpha(1.0)
                    lastPastIdx = idx
                else
                    row.text:SetAlpha(0.3)
                end
            end
        end
        -- Accent highlight on most recent past event
        if lastPastIdx and self.feedRows[lastPastIdx] then
            self.feedRows[lastPastIdx].bg:SetColorTexture(
                C.accent[1], C.accent[2], C.accent[3], 0.1)
        end
        -- Auto-scroll to keep current time visible during playback
        if session.status == "playing" and lastPastIdx then
            local scrollMax = self.feedScroll:GetVerticalScrollRange()
            local targetScroll = math.max(0, (lastPastIdx - 5) * FEED_ROW_H)
            self.feedScroll:SetVerticalScroll(math.min(targetScroll, scrollMax))
        end
    end

    -- ===== Place timeline markers on the scrub track =====
    function frame:RefreshMarkers()
        -- Hide existing
        for _, m in ipairs(self.markerPool) do
            m:Hide()
        end

        if not session then return end

        for i, marker in ipairs(session.markers) do
            local m = self.markerPool[i]
            if not m then
                m = self.scrubTrack:CreateTexture(nil, "OVERLAY")
                m:SetSize(2, 10)
                self.markerPool[i] = m
            end
            local frac = session.matchDuration > 0 and (marker.time / session.matchDuration) or 0
            local trackW = self.scrubTrack:GetWidth()
            m:ClearAllPoints()
            m:SetPoint("CENTER", self.scrubTrack, "LEFT", trackW * frac, 0)

            local cc = CAT_COLORS[marker.cat] or { r = 1, g = 1, b = 1 }
            m:SetColorTexture(cc.r, cc.g, cc.b, 0.8)
            m:Show()
        end
    end

    replayFrame = frame
    return frame
end

---------------------------------------------------------------------------
-- Public API: open replay for a game record
---------------------------------------------------------------------------
function addon:OpenReplay(game)
    local frame = CreateReplayFrame()

    -- Clean up previous session
    if session then
        session:Destroy()
        session = nil
    end

    -- Reset speed
    speedIndex = 2
    frame.btnSpeed.text:SetText("1x")

    -- Hide error text
    frame.errorText:Hide()
    frame.unitPanel:Show()
    frame.feedPanel:Show()
    frame.transport:Show()

    -- Try to load
    if not game.gameLog then
        frame.errorText:SetText("No game log recorded for this match.")
        frame.errorText:Show()
        frame.unitPanel:Hide()
        frame.feedPanel:Hide()
        frame.transport:Hide()
        frame:Show()
        return
    end

    local newSession, err = self:CreateReplaySession(game.gameLog)
    if not newSession then
        frame.errorText:SetText(err or "Failed to load replay data.")
        frame.errorText:Show()
        frame.unitPanel:Hide()
        frame.feedPanel:Hide()
        frame.transport:Hide()
        frame:Show()
        return
    end

    session = newSession

    -- Build title
    local enemyComp = game.enemyComp and table.concat(game.enemyComp, "/") or "?"
    local result = game.result or "?"
    local map = game.map or "Arena"
    frame.titleText:SetText("Replay: " .. result .. " vs " .. enemyComp .. " - " .. map)

    -- Reset filter chips
    frame.activeFilters = { all = true }
    for _, chip in ipairs(frame.filterChips) do
        chip.checkbox:SetChecked(true)
    end

    -- Build feed and markers
    frame:RefreshFeed()
    frame:RefreshMarkers()

    frame:Show()
end
```

- [ ] **Step 2: Commit**

```bash
git add TrinketedHistory/ReplayUI.lua
git commit -m "feat(replay): add replay window UI with unit frames, event feed, and transport controls"
```

---

## Chunk 3: Integration — Wire Up Core.lua

### Task 5: Expose `JSONToTable` from Core.lua

**Files:**
- Modify: `TrinketedHistory/Core.lua`

The `JSONToTable` function is currently `local` in Core.lua. The replay engine needs it for decompression. Expose it on the addon table.

- [ ] **Step 1: Find the `JSONToTable` definition and expose it**

After the `local function JSONToTable(str)` definition (and its closing `end`), add:

```lua
addon.JSONToTable = JSONToTable
```

This goes right after line ~3166 (the `return parseValue()` / `end` of `JSONToTable`). Find the exact line by searching for `return parseValue()` followed by `end` inside the JSON parser section.

- [ ] **Step 2: Commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(replay): expose JSONToTable for replay engine"
```

### Task 6: Add Replay button to match history rows

**Files:**
- Modify: `TrinketedHistory/Core.lua`

Add a small "Replay" button to each row in the match history list. The button appears only if the game has a `gameLog` field.

- [ ] **Step 1: Add a replay button to each history row**

Inside `RefreshHistory()`, find the row creation block (inside `if not row then`). After the existing `row.timeStr` font string creation and before the `-- Alternating background` comment, add a replay button:

```lua
            row.replayBtn = CreateFrame("Button", nil, row)
            row.replayBtn:SetSize(16, 16)
            row.replayBtn:SetPoint("RIGHT", -4, 0)
            row.replayBtn.icon = row.replayBtn:CreateFontString(nil, "OVERLAY")
            row.replayBtn.icon:SetFont(lib.FONT_MONO, 10, "")
            row.replayBtn.icon:SetPoint("CENTER")
            row.replayBtn.icon:SetText(">")
            row.replayBtn.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            row.replayBtn:SetScript("OnEnter", function(self)
                lib:ShowMicroTip(self, "Open replay", "TOP", 0, 4)
            end)
            row.replayBtn:SetScript("OnLeave", function()
                lib:HideMicroTip()
            end)
```

Then in the row population section (after row creation, where game data is set), add the click handler and visibility toggle:

```lua
        -- Replay button
        if game.gameLog then
            row.replayBtn:Show()
            row.replayBtn:SetScript("OnClick", function()
                addon:OpenReplay(game)
            end)
        else
            row.replayBtn:Hide()
        end
```

Place this after the `row.timeStr:SetText(...)` / `row.timeStr:SetTextColor(...)` lines and before `row:Show()`.

- [ ] **Step 2: Commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(replay): add replay button to match history rows"
```

### Task 7: Verify HideMicroTip exists

**Files:**
- Check: `TrinketedLib/Widgets.lua`

The replay button uses `lib:HideMicroTip()`. Verify this function exists in Widgets.lua. If only `lib:ShowMicroTip()` exists, `HideMicroTip` may be handled differently (e.g., the tooltip hides itself on leave via the frame's OnLeave). Check the existing implementation and adjust the OnLeave handler if needed.

- [ ] **Step 1: Read Widgets.lua ShowMicroTip implementation**

Look at how `ShowMicroTip` works (around lines 11-36 of `TrinketedLib/Widgets.lua`). Verify `lib:HideMicroTip()` exists. If it doesn't, check how the micro-tip is hidden (it may hide via the tooltip frame's own OnLeave). Adjust the OnLeave handler to match whatever pattern the existing code uses.

- [ ] **Step 2: Commit if changes were needed**

```bash
git add TrinketedHistory/Core.lua
git commit -m "fix(replay): correct micro-tip hide behavior on replay button"
```

---

## Chunk 4: Polish and Final Verification

### Task 8: Manual testing checklist

No code to write — this is a verification task to run in-game.

- [ ] **Step 1: Sync to WoW and load**

```bash
~/bin/sync-trinketed.sh
```

Then reload UI in-game. Check for Lua errors on load.

- [ ] **Step 2: Verify options panel**

Open `/trinketed` → History. Verify the "Game Logging" section appears with the checkbox and description text.

- [ ] **Step 3: Enable game logging and play a match**

Toggle "Record combat events for replay" on. Enter an arena match. After the match, verify:
- No Lua errors during the game
- `TrinketedHistoryDB.games[#games].gameLog` is a non-nil string (check with `/dump`)

- [ ] **Step 4: Test replay button**

Open the history window (`/trinketed history`). Find the match with game log data. Verify:
- A small ">" replay button appears on the right side of the row
- Rows without game log data do NOT show the button
- Hovering shows "Open replay" micro-tip

- [ ] **Step 5: Test replay viewer**

Click the replay button. Verify:
- Replay window opens with correct title (result, enemy comp, map)
- Unit frames show for both teams with names and class colors
- Health bars display initial values
- Event feed shows events
- Play button starts playback — health bars update, events highlight
- Pause button pauses
- Speed button cycles through 0.5x/1x/2x/4x
- Timeline scrubber shows markers (deaths, trinkets, CDs)
- Clicking scrubber seeks to that position
- Clicking an event in the feed seeks to that time
- Jump-to-start and jump-to-end buttons work
- Closing the window stops playback

- [ ] **Step 6: Test export still works**

Run `/trinketed export`. Verify the export string does NOT contain gameLog data (it should be stripped).

### Task 9: Final commit

- [ ] **Step 1: Commit all remaining changes**

```bash
git add -A
git status  # verify no unexpected files
git commit -m "feat(replay): arena match replay viewer with unit frames, event feed, and playback controls

Adds in-game replay viewer for TrinketedHistory:
- Spell database (ReplaySpells.lua) covering TBC 2.4.3 arena CCs, defensives, offensives
- Playback engine (ReplayEngine.lua) with decompression, state management, seeking
- Replay window (ReplayUI.lua) with unit frames, event feed, timeline scrubber
- Replay button on match history rows (only shown for games with recorded logs)
- Requires 'Record combat events for replay' setting to be enabled"
```
