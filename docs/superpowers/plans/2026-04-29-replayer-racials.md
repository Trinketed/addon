# Replayer Racials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface race-specific cooldowns ("racials") in the TrinketedHistory replay viewer — per-player CD tracker, gear-menu show/hide, timeline markers, and feed filter.

**Architecture:** Add a race-keyed `RACE_COOLDOWNS` table parallel to existing `CLASS_COOLDOWNS`. Recategorize racials in `SPELL_DB` to a unified `cat = "racial"` so existing marker/feed code (which already handles that category) lights up. Plumb `race` through replay state and merge the racial list into the CD tracker render between trinket and class CDs.

**Tech Stack:** Lua 5.1, WoW Classic TBC client API. No test framework — verification is manual: sync via `~/bin/sync-trinketed.sh`, `/reload` in-game, open replay viewer, observe.

**Spec:** `docs/superpowers/specs/2026-04-29-replayer-racials-design.md`

**Notes for the engineer:**
- All file paths in this plan are repo-relative.
- Line numbers in this plan reflect HEAD at plan-time and will drift as you commit. Use the surrounding context (function names, comments, exact match strings) to locate edits — don't trust raw line numbers.
- "Verify in-game" means: run `~/bin/sync-trinketed.sh`, then `/reload` in WoW, then open the replay viewer (`/trink history` → load a replay) and check.
- Commit messages should follow the existing repo style — see `git log --oneline` for examples (lowercase, conventional, no scope prefixes).

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `TrinketedHistory/SpellDB.lua` | Spell metadata DB | Recategorize 9 racials to `cat = "racial"`; add Gift of the Naaru entry; extend `TRACKED_COOLDOWN_SPELLS` |
| `TrinketedHistory/ReplayEngine.lua` | Decompression, state, event processing | Add `RACE_COOLDOWNS` and `RACE_DISPLAY_ORDER`; copy `race` through `BuildInitialState`/`CopyState`/`player_entered` |
| `TrinketedHistory/ReplayUI.lua` | Replay viewer rendering | Build merged display list in CD tracker render; add "Racials" submenu in gear dropdown |
| `TrinketedHistory/ReplaySpells.lua` | (dead) | Delete |
| `TrinketedHistory/TrinketedHistory.toc` | Addon manifest / load order | Remove `ReplaySpells.lua` line |

---

## Task 1: Recategorize racials in `SPELL_DB`

**Files:**
- Modify: `TrinketedHistory/SpellDB.lua` (the "PVP TRINKET / CC BREAK" and "RACIALS" sections, ~lines 17–32)

- [ ] **Step 1: Replace the racial entries**

Find this block in `TrinketedHistory/SpellDB.lua`:

```lua
    -- =================================================================
    -- PVP TRINKET / CC BREAK
    -- =================================================================
    [42292] = { cat = "trinket",      cd = 120, name = "PvP Trinket" },
    [7744]  = { cat = "racial",       cd = 120, name = "Will of the Forsaken" },
    [20589] = { cat = "cc_break",     cd = 105, name = "Escape Artist" },
    [18499] = { cat = "cc_break",     cd = 30,  dur = 10, name = "Berserker Rage" },

    -- =================================================================
    -- RACIALS
    -- =================================================================
    [20594] = { cat = "defensive_cd", cd = 180, dur = 8,  name = "Stoneform" },
    [20600] = { cat = "offensive_cd", cd = 180, dur = 20, name = "Perception" },
    [20549] = { cat = "interrupt",    cd = 90,  dur = 0.5, name = "War Stomp" },
    [28730] = { cat = "interrupt",    cd = 120, name = "Arcane Torrent" },
    [26297] = { cat = "offensive_cd", cd = 180, dur = 15, name = "Berserking" },
    [20572] = { cat = "offensive_cd", cd = 120, dur = 15, name = "Blood Fury" },
    [58984] = { cat = "defensive_cd", cd = 120, name = "Shadowmeld" },
```

Replace with:

```lua
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
```

What changed:
- Will of the Forsaken (7744) and Escape Artist (20589) moved into the RACIALS section and recategorized to `racial` (were `racial`/`cc_break`).
- Stoneform, Perception, War Stomp, Arcane Torrent, Berserking, Blood Fury, Shadowmeld all changed `cat` to `racial`.
- New entry: Gift of the Naaru (28880).
- Berserker Rage (18499) is NOT a racial — left as `cc_break`.

- [ ] **Step 2: Verify in-game**

Sync, `/reload`, then in chat:

```
/dump SPELL_DB[20594].cat
```

Expected: `"racial"` (was `"defensive_cd"`).

```
/dump SPELL_DB[28880]
```

Expected: a table with `cat = "racial"`, `cd = 180`, `dur = 15`, `name = "Gift of the Naaru"`.

- [ ] **Step 3: Commit**

```bash
git add TrinketedHistory/SpellDB.lua
git commit -m "spelldb: recategorize racials to cat=racial, add Gift of the Naaru"
```

---

## Task 2: Extend `TRACKED_COOLDOWN_SPELLS`

The recording side polls these spell IDs for cooldown state. Currently 6 of 10 racials are tracked; add the 4 missing ones so replays carry full racial CD state going forward.

**Files:**
- Modify: `TrinketedHistory/SpellDB.lua` (the `TRACKED_COOLDOWN_SPELLS` array, last block in the file, ~lines 295–320)

- [ ] **Step 1: Update the Racials line**

Find:

```lua
    -- Racials
    7744, 20589, 20594, 20600, 20549, 28730,
```

Replace with:

```lua
    -- Racials
    7744, 20589, 20594, 20600, 20549, 28730, 26297, 20572, 58984, 28880,
```

- [ ] **Step 2: Verify**

Sync + `/reload`. In chat:

```
/dump #TRACKED_COOLDOWN_SPELLS
```

Compare against the count before the change (it should have grown by 4).

- [ ] **Step 3: Commit**

```bash
git add TrinketedHistory/SpellDB.lua
git commit -m "spelldb: track Berserking/Blood Fury/Shadowmeld/Gift of the Naaru cooldowns"
```

---

## Task 3: Add `RACE_COOLDOWNS` and `RACE_DISPLAY_ORDER`

**Files:**
- Modify: `TrinketedHistory/ReplayEngine.lua` (immediately after the `CLASS_COOLDOWNS` table definition, around line 179)

- [ ] **Step 1: Insert the new tables**

Find the end of the `CLASS_COOLDOWNS` table — the closing `}` after the `["Druid"]` block, around line 179. Immediately after it, insert:

```lua
---------------------------------------------------------------------------
-- Race → tracked cooldown spellIDs (racials for the CD tracker)
-- Each TBC race has one racial. List-valued for forward-compatibility.
---------------------------------------------------------------------------
addon.RACE_COOLDOWNS = {
    ["Human"]    = { 20600 }, -- Perception
    ["Dwarf"]    = { 20594 }, -- Stoneform
    ["NightElf"] = { 58984 }, -- Shadowmeld (TBC ID may be 20580 — verify in-game)
    ["Gnome"]    = { 20589 }, -- Escape Artist
    ["Draenei"]  = { 28880 }, -- Gift of the Naaru
    ["Orc"]      = { 20572 }, -- Blood Fury
    ["Undead"]   = { 7744  }, -- Will of the Forsaken
    ["Tauren"]   = { 20549 }, -- War Stomp
    ["Troll"]    = { 26297 }, -- Berserking
    ["BloodElf"] = { 28730 }, -- Arcane Torrent
}

-- Stable display order for the gear-menu "Racials" submenu (pairs() is unordered).
addon.RACE_DISPLAY_ORDER = {
    "Human", "Dwarf", "NightElf", "Gnome", "Draenei",
    "Orc", "Undead", "Tauren", "Troll", "BloodElf",
}
```

- [ ] **Step 2: Verify**

Sync + `/reload`. In chat:

```
/dump TrinketedHistory.RACE_COOLDOWNS.Dwarf
```

Expected: `{ 20594 }`.

```
/dump TrinketedHistory.RACE_DISPLAY_ORDER[1]
```

Expected: `"Human"`.

- [ ] **Step 3: Commit**

```bash
git add TrinketedHistory/ReplayEngine.lua
git commit -m "replay: add RACE_COOLDOWNS and RACE_DISPLAY_ORDER tables"
```

---

## Task 4: Plumb `race` through replay state

The roster carries `race` per player but it's currently dropped when state is built/copied/extended. The CD tracker render needs `playerState.race` to look up `RACE_COOLDOWNS`.

**Files:**
- Modify: `TrinketedHistory/ReplayEngine.lua` — three sites: `BuildInitialState` (~line 226), `CopyState` (~line 248), `player_entered` event handler (~line 427)

- [ ] **Step 1: `BuildInitialState` — copy `race` from roster**

Find:

```lua
local function BuildInitialState(parsedData)
    local state = { players = {} }
    for guid, info in pairs(parsedData.roster) do
        state.players[guid] = {
            name = info.name,
            class = info.class,
            spec = info.spec,
            team = info.team,
```

Add a `race` line right after `class`:

```lua
local function BuildInitialState(parsedData)
    local state = { players = {} }
    for guid, info in pairs(parsedData.roster) do
        state.players[guid] = {
            name = info.name,
            class = info.class,
            race = info.race,
            spec = info.spec,
            team = info.team,
```

- [ ] **Step 2: `CopyState` — preserve `race` when deep-copying**

Find:

```lua
        dst.players[guid] = {
            name = p.name,
            class = p.class,
            spec = p.spec,
            team = p.team,
```

Add `race`:

```lua
        dst.players[guid] = {
            name = p.name,
            class = p.class,
            race = p.race,
            spec = p.spec,
            team = p.team,
```

- [ ] **Step 3: `player_entered` — capture `race` if present in the event**

Find:

```lua
    elseif evType == "player_entered" then
        local guid = ev.guid
        if guid and not state.players[guid] then
            state.players[guid] = {
                name = ev.name,
                class = ev.class,
                spec = nil,
                team = ev.team,
```

Add `race`:

```lua
    elseif evType == "player_entered" then
        local guid = ev.guid
        if guid and not state.players[guid] then
            state.players[guid] = {
                name = ev.name,
                class = ev.class,
                race = ev.race,
                spec = nil,
                team = ev.team,
```

(`ev.race` may be nil — that's fine; `RACE_COOLDOWNS[nil]` returns nil and the renderer handles that.)

- [ ] **Step 4: Verify in-game**

Sync + `/reload`. Open a replay (`/trink history` → load any recorded match). Then in chat — pause the replay first so state is stable — run:

```
/run for guid, p in pairs(TrinketedHistory.activeReplay.session.state.players) do print(p.name, p.race) end
```

(Adjust the path if the active session lives elsewhere — search for `activeReplay` in `ReplayUI.lua` for the canonical access pattern.) Expected: each player prints their race string (e.g., `"Dwarf"`, `"Tauren"`). If race is nil, the recording predates this work, which is acceptable.

- [ ] **Step 5: Commit**

```bash
git add TrinketedHistory/ReplayEngine.lua
git commit -m "replay: propagate race through replay state"
```

---

## Task 5: Render racials in the per-player CD tracker

Build a merged display list (trinket → racial → class CDs) at the top of the CD render loop.

**Files:**
- Modify: `TrinketedHistory/ReplayUI.lua` — the CD tracker section that begins with the comment `-- Cooldown tracker: show all class CDs to the right of the unit frame`, around line 327

- [ ] **Step 1: Replace the CD-list lookup with a merged list**

Find:

```lua
    -- Cooldown tracker: show all class CDs to the right of the unit frame
    local hiddenCDs = TrinketedHistoryDB and TrinketedHistoryDB.settings and TrinketedHistoryDB.settings.hiddenReplayCDs or {}
    local classCDs = playerState.class and addon.CLASS_COOLDOWNS and addon.CLASS_COOLDOWNS[playerState.class]
    local visIdx = 0
    if classCDs then
        for idx, spellID in ipairs(classCDs) do
```

Replace with:

```lua
    -- Cooldown tracker: show trinket → racial → class CDs to the right of the unit frame
    local hiddenCDs = TrinketedHistoryDB and TrinketedHistoryDB.settings and TrinketedHistoryDB.settings.hiddenReplayCDs or {}
    local classCDs = playerState.class and addon.CLASS_COOLDOWNS and addon.CLASS_COOLDOWNS[playerState.class] or {}
    local raceCDs  = playerState.race  and addon.RACE_COOLDOWNS  and addon.RACE_COOLDOWNS[playerState.race]   or {}

    -- Merged display order: trinket (if first in classCDs) → racial(s) → rest of classCDs.
    local merged = {}
    local startIdx = 1
    if classCDs[1] == 42292 then
        merged[#merged + 1] = 42292
        startIdx = 2
    end
    for _, sid in ipairs(raceCDs) do merged[#merged + 1] = sid end
    for j = startIdx, #classCDs do merged[#merged + 1] = classCDs[j] end

    local visIdx = 0
    if #merged > 0 then
        for idx, spellID in ipairs(merged) do
```

Note the changes:
- `classCDs ... or {}` (default empty so `classCDs[1]` is safe even when class is unknown)
- New `raceCDs` lookup
- New `merged` list construction
- `for idx, spellID in ipairs(classCDs) do` → `for idx, spellID in ipairs(merged) do`
- `if classCDs then` → `if #merged > 0 then`

The body of the loop (icon creation, positioning, texture, tooltip, cooldown sweep) is unchanged — it already keys off `spellID` and `idx`.

- [ ] **Step 2: Verify in-game**

Sync + `/reload`. Open a replay. For each visible player frame:
- The PvP trinket icon is still leftmost (immediately right of the unit frame).
- Immediately to its right: the player's racial icon (e.g., Stoneform for a Dwarf, War Stomp for a Tauren).
- Class CDs follow as before.

Hover the racial icon: tooltip shows the racial spell. Right-click: hides the icon. Open the gear menu (Task 6 not yet done) — the racial won't be in the dropdown yet, but the right-click hide path still works because it writes to `hiddenReplayCDs[spellID]`.

Cast the racial during a recorded test match later and check that the cooldown sweep animates on the icon.

- [ ] **Step 3: Commit**

```bash
git add TrinketedHistory/ReplayUI.lua
git commit -m "replay: render racials in per-player CD tracker"
```

---

## Task 6: Add "Racials" submenu to the gear dropdown

**Files:**
- Modify: `TrinketedHistory/ReplayUI.lua` — the gear-menu dropdown initializer with class submenus, around lines 683–727

- [ ] **Step 1: Add "Racials" entry to the level-1 menu**

Find the class loop in the `level == 1` branch:

```lua
            -- Class submenus
            for _, className in ipairs(CLASS_ORDER) do
                local spells = addon.CLASS_COOLDOWNS[className]
                if spells then
                    info = UIDropDownMenu_CreateInfo()
                    info.text = className
                    info.notCheckable = true
                    info.hasArrow = true
                    info.menuList = className
                    UIDropDownMenu_AddButton(info, level)
                end
            end
```

Immediately after that loop's closing `end`, add:

```lua
            -- Racials submenu (single, lists all races)
            info = UIDropDownMenu_CreateInfo()
            info.text = "Racials"
            info.notCheckable = true
            info.hasArrow = true
            info.menuList = "__RACIALS__"
            UIDropDownMenu_AddButton(info, level)
```

- [ ] **Step 2: Add the level-2 branch for racials**

Find the existing level-2 class branch:

```lua
        elseif level == 2 then
            -- Spells for the selected class
            local className = menuList
            local spells = addon.CLASS_COOLDOWNS[className]
            if spells then
                for _, spellID in ipairs(spells) do
                    info = UIDropDownMenu_CreateInfo()
                    local dbEntry = SPELL_DB and SPELL_DB[spellID]
                    local spellName = dbEntry and dbEntry.name or (GetSpellInfo(spellID) or ("Spell " .. spellID))
                    local texID = GetSpellTexture(spellID)
                    if texID then
                        info.text = "|T" .. texID .. ":14:14:0:0:64:64:4:60:4:60|t " .. spellName
                    else
                        info.text = spellName
                    end
                    info.checked = not hiddenCDs[spellID]
                    info.isNotRadio = true
                    info.keepShownOnClick = true
                    local sid = spellID
                    info.func = function(self, _, _, checked)
                        if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                            if checked then
                                TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = nil
                            else
                                TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = true
                            end
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
```

Replace it with this version (adds an `elseif` for `__RACIALS__`):

```lua
        elseif level == 2 then
            if menuList == "__RACIALS__" then
                -- Racials: iterate races in stable display order
                for _, raceKey in ipairs(addon.RACE_DISPLAY_ORDER or {}) do
                    local raceCDs = addon.RACE_COOLDOWNS and addon.RACE_COOLDOWNS[raceKey]
                    if raceCDs then
                        for _, spellID in ipairs(raceCDs) do
                            info = UIDropDownMenu_CreateInfo()
                            local dbEntry = SPELL_DB and SPELL_DB[spellID]
                            local spellName = dbEntry and dbEntry.name or (GetSpellInfo(spellID) or ("Spell " .. spellID))
                            local texID = GetSpellTexture(spellID)
                            if texID then
                                info.text = "|T" .. texID .. ":14:14:0:0:64:64:4:60:4:60|t " .. spellName
                            else
                                info.text = spellName
                            end
                            info.checked = not hiddenCDs[spellID]
                            info.isNotRadio = true
                            info.keepShownOnClick = true
                            local sid = spellID
                            info.func = function(self, _, _, checked)
                                if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                                    if checked then
                                        TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = nil
                                    else
                                        TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = true
                                    end
                                end
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end
                    end
                end
            else
                -- Spells for the selected class
                local className = menuList
                local spells = addon.CLASS_COOLDOWNS[className]
                if spells then
                    for _, spellID in ipairs(spells) do
                        info = UIDropDownMenu_CreateInfo()
                        local dbEntry = SPELL_DB and SPELL_DB[spellID]
                        local spellName = dbEntry and dbEntry.name or (GetSpellInfo(spellID) or ("Spell " .. spellID))
                        local texID = GetSpellTexture(spellID)
                        if texID then
                            info.text = "|T" .. texID .. ":14:14:0:0:64:64:4:60:4:60|t " .. spellName
                        else
                            info.text = spellName
                        end
                        info.checked = not hiddenCDs[spellID]
                        info.isNotRadio = true
                        info.keepShownOnClick = true
                        local sid = spellID
                        info.func = function(self, _, _, checked)
                            if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                                if checked then
                                    TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = nil
                                else
                                    TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = true
                                end
                            end
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end
        end
```

- [ ] **Step 3: Verify in-game**

Sync + `/reload`. Open a replay, click the gear icon. Confirm:
- A "Racials" entry sits beneath the per-class entries with a sub-arrow.
- Hovering "Racials" reveals all 10 racials in this order: Perception, Stoneform, Shadowmeld, Escape Artist, Gift of the Naaru, Blood Fury, Will of the Forsaken, War Stomp, Berserking, Arcane Torrent.
- Each row has its spell icon and a checkbox reflecting current visibility.
- Toggling Stoneform off hides its icon on Dwarf players in the tracker.
- Toggling it back on restores the icon.

- [ ] **Step 4: Commit**

```bash
git add TrinketedHistory/ReplayUI.lua
git commit -m "replay: add Racials submenu to gear-menu show/hide dropdown"
```

---

## Task 7: Delete `ReplaySpells.lua` (dead code)

**Files:**
- Delete: `TrinketedHistory/ReplaySpells.lua`
- Modify: `TrinketedHistory/TrinketedHistory.toc` (remove `ReplaySpells.lua` line)

- [ ] **Step 1: Confirm there are no remaining references**

Run from the repo root:

```bash
grep -rn "ReplaySpells\|REPLAY_SPELLS" TrinketedHistory/ Trinketed.lua TrinketedLib/ 2>/dev/null
```

Expected: only matches inside `TrinketedHistory/ReplaySpells.lua` itself (and its `:Zone.Identifier` shadow file) and the `TrinketedHistory.toc` load line. If there are *any* matches outside those, stop and audit before continuing.

- [ ] **Step 2: Remove the toc line**

Open `TrinketedHistory/TrinketedHistory.toc` and delete the line `ReplaySpells.lua` (around line 10).

- [ ] **Step 3: Delete the file**

```bash
git rm TrinketedHistory/ReplaySpells.lua
```

If a `TrinketedHistory/ReplaySpells.lua:Zone.Identifier` companion file exists in the working tree (WSL artifact), remove it too:

```bash
rm -f TrinketedHistory/ReplaySpells.lua:Zone.Identifier
```

- [ ] **Step 4: Verify in-game**

Sync + `/reload`. Confirm:
- No load-error popup.
- `/trink history` opens normally.
- Replay viewer functions as before — racial icons still render.

- [ ] **Step 5: Commit**

```bash
git add TrinketedHistory/TrinketedHistory.toc TrinketedHistory/ReplaySpells.lua
git commit -m "replay: remove unused ReplaySpells.lua"
```

---

## Final verification

After Task 7, do one full smoke pass:

- [ ] Sync + `/reload` with a clean WoW restart.
- [ ] Open the replay viewer and load a recent match that has at least one Dwarf, one Tauren, and one Blood Elf if possible.
- [ ] Per-player CD tracker shows trinket → racial → class CDs.
- [ ] Gear menu has the "Racials" submenu with all 10 entries.
- [ ] Right-click hide on a racial icon works; gear-menu toggle works; both reflect each other.
- [ ] Racial casts on the timeline marker bar appear in the gold (`racial`) accent color.
- [ ] Combat-log feed under the "CDs" filter shows racial casts.
- [ ] No Lua errors in `/console scriptErrors 1` mode.

If a recording doesn't carry race for some players (older recordings), those players' racial icons silently won't render — by design.

## Submodule push

After all tasks ship and verification passes, the changes live in the `TrinketedHistory/` submodule. Per `CLAUDE.md`, push from inside the submodule directory:

```bash
cd TrinketedHistory
git push
```

The `notify-parent.yml` → `update-submodule.yml` → `auto-tag.yml` → `release.yml` chain takes over from there. Do **not** manually update the submodule pointer in the parent repo.
