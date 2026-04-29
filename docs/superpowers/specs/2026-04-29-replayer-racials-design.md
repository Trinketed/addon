# Replayer Racials — Design

## Goal

Surface race-specific cooldowns ("racials") as first-class entities in the TrinketedHistory replay viewer. Racials should appear in the per-player CD tracker, the gear-menu show/hide dropdown, the scrubber timeline markers, and the combat-log feed filter — i.e., wherever class CDs already appear.

## Background

The replayer's per-player CD tracker (`ReplayUI.lua` ~line 329) renders icons sourced from `addon.CLASS_COOLDOWNS[playerState.class]`. The lookup is class-keyed only, so racials never render even though:

- The roster persists a `race` field per player (v3 event log format).
- `SPELL_DB` (`SpellDB.lua`) already carries metadata for 9 of the 10 TBC racials.
- `TRACKED_COOLDOWN_SPELLS` already polls 6 of the 10 racials during recording.
- Marker (`ReplayEngine.lua:654`) and feed-filter (`ReplayUI.lua:1269`) code already recognizes `cat == "racial"`, including a gold marker color (`ReplayUI.lua:111`) — but no spell currently uses that category.

`TrinketedHistory/ReplaySpells.lua` is loaded via the toc but never referenced in code (dead).

## Scope

**In:** Per-player CD tracker rendering, gear-menu integration, marker/feed integration via SPELL_DB recategorization, race-plumbing through replay state, missing-racial coverage (Draenei), dead-code cleanup of `ReplaySpells.lua`.

**Out:** Engine changes to cooldown-sweep logic (already generic on `SPELL_DB[spellID].cd`); recording-side changes other than the `TRACKED_COOLDOWN_SPELLS` additions; per-spec racials (e.g., Subtlety-only effects).

## Design

### 1. Data model

**1a. New `RACE_COOLDOWNS` table in `ReplayEngine.lua`**, parallel to `CLASS_COOLDOWNS`. List-valued for forward-compat though TBC has 1 racial per race:

```lua
addon.RACE_COOLDOWNS = {
    ["Human"]    = { 20600 }, -- Perception
    ["Dwarf"]    = { 20594 }, -- Stoneform
    ["NightElf"] = { 58984 }, -- Shadowmeld (verify TBC ID — may need 20580)
    ["Gnome"]    = { 20589 }, -- Escape Artist
    ["Draenei"]  = { 28880 }, -- Gift of the Naaru
    ["Orc"]      = { 20572 }, -- Blood Fury
    ["Undead"]   = { 7744 },  -- Will of the Forsaken
    ["Tauren"]   = { 20549 }, -- War Stomp
    ["Troll"]    = { 26297 }, -- Berserking
    ["BloodElf"] = { 28730 }, -- Arcane Torrent
}

addon.RACE_DISPLAY_ORDER = {
    "Human", "Dwarf", "NightElf", "Gnome", "Draenei",
    "Orc", "Undead", "Tauren", "Troll", "BloodElf",
}
```

`RACE_DISPLAY_ORDER` exists so the gear menu's "Racials" submenu has a stable order (lua `pairs()` is unordered).

**1b. Recategorize racials in `SPELL_DB`** to `cat = "racial"`:

| spellID | Name              | Old cat       | New cat |
|---------|-------------------|---------------|---------|
| 20594   | Stoneform         | defensive_cd  | racial  |
| 20600   | Perception        | offensive_cd  | racial  |
| 20549   | War Stomp         | interrupt     | racial  |
| 28730   | Arcane Torrent    | interrupt     | racial  |
| 26297   | Berserking        | offensive_cd  | racial  |
| 20572   | Blood Fury        | offensive_cd  | racial  |
| 58984   | Shadowmeld        | defensive_cd  | racial  |
| 7744    | Will of the Forsaken | trinket    | racial  |
| 20589   | Escape Artist     | cc_break      | racial  |

**1c. Add Gift of the Naaru** (Draenei racial — currently missing from `SPELL_DB`):

```lua
[28880] = { cat = "racial", cd = 180, dur = 15, name = "Gift of the Naaru" },
```

**1d. Plumb `race` through replay state.** Three sites in `ReplayEngine.lua`:

- `BuildInitialState` (line ~226): copy `info.race` into `state.players[guid].race`.
- `CopyState` (line ~248): preserve `p.race` when deep-copying.
- `player_entered` event handler (line ~427): if the event carries `race`, store it.

### 2. Per-player CD tracker rendering

In `ReplayUI.lua` at the cooldown loop (~line 329), build a merged display list per player:

```lua
local classCDs = playerState.class and addon.CLASS_COOLDOWNS[playerState.class] or {}
local raceCDs = playerState.race and addon.RACE_COOLDOWNS[playerState.race] or {}

-- Merged order: trinket → racial(s) → rest of class CDs
local merged = {}
local startIdx = 1
if classCDs[1] == 42292 then
    merged[#merged + 1] = 42292
    startIdx = 2
end
for _, sid in ipairs(raceCDs) do merged[#merged + 1] = sid end
for j = startIdx, #classCDs do merged[#merged + 1] = classCDs[j] end

for idx, spellID in ipairs(merged) do
    -- existing render code, untouched
end
```

Existing icon pooling, hidden-CD filtering, tooltip and right-click-to-hide, and the cooldown sweep are all keyed on `spellID` and need no other changes. The merged list is deterministic per `(class, race)` pair.

### 3. Gear-menu show/hide dropdown

In `ReplayUI.lua` around line 683 (the dropdown initializer):

**level 1** — after the class submenu loop, add a single "Racials" entry:

```lua
info = UIDropDownMenu_CreateInfo()
info.text = "Racials"
info.notCheckable = true
info.hasArrow = true
info.menuList = "__RACIALS__"
UIDropDownMenu_AddButton(info, level)
```

**level 2** — add a sibling branch alongside the class branch:

```lua
elseif menuList == "__RACIALS__" then
    for _, raceKey in ipairs(addon.RACE_DISPLAY_ORDER) do
        local raceCDs = addon.RACE_COOLDOWNS[raceKey] or {}
        for _, spellID in ipairs(raceCDs) do
            -- identical row builder to the class branch (icon + name + checkbox)
        end
    end
```

Hidden-state plumbing (`TrinketedHistoryDB.settings.hiddenReplayCDs[spellID]`) is already spellID-keyed, so toggling racials reuses the existing path.

### 4. Marker / feed / cleanup

- **Timeline markers** (`ReplayEngine.lua:654`): no change. The `cat == "racial"` branch already exists; recategorization (§1b) makes racials flow through.
- **Feed filter** (`ReplayUI.lua:1269`): no change. `cat == "racial"` already maps into the "cd" filter group.
- **Search markers** (`ReplayEngine.lua:676`): no change. Reads `cat` from `SPELL_DB` and passes through.
- **`TRACKED_COOLDOWN_SPELLS`** (`SpellDB.lua:319`): add 26297, 20572, 58984, 28880 (Berserking, Blood Fury, Shadowmeld, Gift of the Naaru) so the recording side polls them.
- **Cleanup**: delete `TrinketedHistory/ReplaySpells.lua` and remove its line from `TrinketedHistory/TrinketedHistory.toc`.

## Trade-offs accepted

- Stoneform et al. lose their secondary effect category (e.g., Stoneform no longer matches a "defensives only" filter). They remain reachable via the unified "Racials" filter. The simplification of single-category racials is judged worth the loss.
- Gold marker color now applies to all racials uniformly. A Stoneform marker will look the same on the timeline as a Berserking marker, which is correct given they're both racials but different from how they render today.
- Racials are appended after the trinket icon, before class CDs. This shifts every player's CD tracker layout by N icons (where N = 1 for all current TBC races). Existing icon-pool indices are stable per `(class, race)`, so no flicker on replay reload.

## Verifications before shipping

- Confirm Shadowmeld spellID for the TBC 2.4.3 Blizzard Classic client. 58984 is the Wrath ID; 20580 may be needed. Test by casting in-game and inspecting the recorded log.
- Confirm `cast_success` actually fires for Perception and Shadowmeld in the current client. If not, the icon shows but the cooldown sweep won't engage. Acceptable degradation (icon stays visible / "ready"), but worth knowing.
- Confirm the recording path captures `race` in the roster for new matches. If old recordings lack race, racial icons silently won't render for those replays, which is the correct fallback.

## File touch-list

| File | Change |
|------|--------|
| `TrinketedHistory/ReplayEngine.lua` | Add `RACE_COOLDOWNS`, `RACE_DISPLAY_ORDER`; plumb `race` through `BuildInitialState`, `CopyState`, `player_entered` |
| `TrinketedHistory/ReplayUI.lua` | Merged-list builder in CD tracker render; "Racials" entry + level-2 branch in gear dropdown |
| `TrinketedHistory/SpellDB.lua` | Recategorize 9 racials to `cat = "racial"`; add Gift of the Naaru entry; extend `TRACKED_COOLDOWN_SPELLS` |
| `TrinketedHistory/ReplaySpells.lua` | Delete (dead code) |
| `TrinketedHistory/TrinketedHistory.toc` | Remove `ReplaySpells.lua` line |
