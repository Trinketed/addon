# Replay Viewer Design Spec

## Overview

An in-game arena match replay viewer for TrinketedHistory. Opened from the match history list, it reconstructs the match from recorded CLEU events — showing unit frames with health/power bars, buff/debuff tracking with duration sweeps, cooldown usage, and a synchronized filterable event feed. Purpose: reviewing your own arena games to spot mistakes and understand what happened.

Target platform: TBC 2.4.3 content on the modern Retail addon API (Interface 110207).

## Data Source

The replay viewer consumes the `gameLog` field stored on each game record. This is a compressed string that decodes to:

```lua
{
    v = 1,
    initialState = {
        players = {
            [guid] = { name, class, team, health, healthMax, power, powerMax, powerType }
        },
        timestamp = epochSeconds  -- e.g. 1773251768.684
    },
    events = {
        { timestamp, subevent, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags,
          dstGUID, dstName, dstFlags, dstRaidFlags, ... },
        ...
    },
    eventCount = N
}
```

Timestamps are epoch seconds with millisecond precision. The viewer converts all timestamps to match-relative seconds: `eventTs - initialState.timestamp`. The `eventCount` field is informational only and not validated.

## Window Layout

Opened from a match row in the history list (button or right-click). Uses `lib:CreateWindowFrame()`. Size: **950x560**.

```
+-----------------------------------------------------------+
|  Replay: WIN vs Rogue/Mage/Priest - Nagrand Arena      [X]|
+-------------------------------+---------------------------+
|                               |                           |
|     UNIT FRAMES PANEL         |     EVENT FEED PANEL      |
|     (~600px)                  |     (~330px)              |
|                               |                           |
|  +- Friendly Team ----------+ | [All] [CC] [Dmg] [Heal]  |
|  | [HP bar] [power] [auras] | | [CDs] [Deaths]           |
|  | [HP bar] [power] [auras] | | ------------------------- |
|  | [HP bar] [power] [auras] | |  0:12.3 Polymorph  M->W  |
|  +---------------------------+ |  0:12.8 Trinket   Warr   |
|                               |  0:13.1 Kidney    R->P   |
|  +- Enemy Team -------------+ |  ...                     |
|  | [HP bar] [power] [auras] | |                           |
|  | [HP bar] [power] [auras] | |                           |
|  | [HP bar] [power] [auras] | |                           |
|  +---------------------------+ |                           |
|                               |                           |
+-------------------------------+---------------------------+
| [|<] [>] [>|]  1x   --*-------------- 1:23 / 2:45       |
|                       ^kill  ^trinket       ^kill          |
+-----------------------------------------------------------+
```

Three zones:
- **Left (~600px)**: Unit frames panel. Friendly team top, enemy team bottom, separated by a subtle divider.
- **Right (~330px)**: Event feed panel with filter chips at top, scrollable event list below.
- **Bottom (~40px)**: Transport controls, speed selector, timeline scrubber with event markers.

### Window Close Behavior
Closing the window (X button or Escape) stops playback and discards the parsed replay data, freeing memory. Reopening the same match re-parses from the compressed string.

## Unit Frames

Each player gets one frame (~280px wide, ~50px tall):

```
+------------------------------------------+
| Warrior (Arms)                    8261   |
| ==================----  HP       /8261   |
| =========-----------    Rage       45    |
| [Trink] [MS] [Poly] [Rend]              |
+------------------------------------------+
```

### Health Bar
- Full width of the frame, ~12px tall.
- Colored by class. The existing `CLASS_COLORS` table stores hex strings (`"ffc79c6e"`); the viewer parses these into r/g/b floats for `SetColorTexture()`.
- Numeric current/max right-aligned.
- Bar transitions smoothly between values (lerp over ~0.2s) during normal playback. When seeking (scrubbing or clicking a feed event), bars snap to target values immediately.

### Power Bar
- Below health bar, thinner (~6px).
- Colored by power type: `0` = mana (blue), `1` = rage (red), `3` = energy (yellow).
- Hidden if no power events exist for this player in the log.

### Name/Spec Label
- Above health bar. Class-colored name, spec in parentheses if detected from the match record.
- Uses `FONT_BODY` at 10pt.

### Icon Row
- Below power bar. Small icons (16x16) for active auras and recent cooldowns.
- **Buffs**: Green border. Duration sweep if duration known from spell database.
- **Debuffs/CC**: Red border. Duration sweep.
- **Cooldowns**: Shown on `SPELL_CAST_SUCCESS`, darkened with sweep for estimated cooldown duration.
- Only arena-relevant spells shown (filtered by spell database). Passive buffs like Mark of the Wild excluded.
- Icon textures retrieved via `GetSpellTexture(spellID)` using the numeric spell ID from the CLEU event (position 12). Falls back to a generic category icon if not found.

### HP/Power Reconstruction
- Initialize from `initialState.players[guid]`.
- Walk forward through CLEU events, accumulating deltas:
  - `SWING_DAMAGE`, `SPELL_DAMAGE`, `SPELL_PERIODIC_DAMAGE`, `RANGE_DAMAGE`, `DAMAGE_SHIELD`, `ENVIRONMENTAL_DAMAGE` → subtract `amount` from HP. The `amount` field in CLEU represents damage actually dealt to HP (post-absorb, post-resist), so no absorb adjustment is needed.
  - `SPELL_HEAL`, `SPELL_PERIODIC_HEAL` → add `amount` to HP (subtract `overhealing` if present).
  - `SPELL_ENERGIZE`, `SPELL_PERIODIC_ENERGIZE` → add to power.
  - `SPELL_DRAIN`, `SPELL_LEECH` → adjust power.
  - `UNIT_DIED` → set HP to 0, mark `alive = false`.
- Clamp HP/power to 0..max.
- **Missing player fallback**: If a player isn't in `initialState` (enemy not visible at game start), they are added to replay state on their first appearance in any event. HP is initialized to an unknown max and displayed as "?" until enough damage/heal events establish a reference point. In practice, most players appear in the initial snapshot since `InitGameLog` scans arena1-5 units.

### Aura Tracking
- `SPELL_AURA_APPLIED` → add to `replayState.players[guid].auras`. Look up spell in database for duration and debuff status. If spell has a known `dur`, record `applied = currentTime` and `duration = dur` for sweep timer display.
- `SPELL_AURA_REMOVED` → remove from `auras` table.
- `SPELL_AURA_APPLIED_DOSE` / `SPELL_AURA_REMOVED_DOSE` → update stack count (if we track stacks; v1 can ignore dose events).
- Only auras present in the spell database are tracked. All others are silently ignored.

### Cooldown Tracking
- `SPELL_CAST_SUCCESS` → if the spell is in the database with `cat` of `"trinket"`, `"offensive"`, or `"defensive"`, add a cooldown icon to the player's icon row. Show the icon darkened with a sweep timer for the spell's `dur` field (representing cooldown duration, not buff duration — the database entry distinguishes these by category).

## Event Feed Panel

### Row Format (~18px tall)
```
 0:12.3  * Polymorph        Mage     -> Warrior     8.0s
```

- **Timestamp**: Match-relative `m:ss.t` format.
- **Category indicator**: Small colored symbol or text badge (CC=blue, Damage=red, Healing=green, Death=skull/red, Defensive=gold, Offensive=orange).
- **Spell name**: Class-colored to match the source.
- **Source -> Target**: Short names (realm-stripped via `StripRealm()` or matched against `initialState.players[guid].name`), class-colored.
- **Extra column**: Duration for CC/auras, amount for damage/healing (abbreviated: 2.1k, 3.4k).

### Filtering
Filter chips at the top using `lib:CreateCheckbox()` toggle chips: `All`, `CC`, `Damage`, `Healing`, `CDs`, `Deaths`. Multiple can be active simultaneously. When `All` is active, others are ignored. Toggling any specific filter deactivates `All`. Deactivating the last active specific filter re-activates `All` (never shows an empty feed from having no filters).

The All/individual interaction logic is implemented as custom `onClick` handlers on top of the standard toggle chip widget.

### Sync Behavior
- During playback, feed auto-scrolls to keep current timestamp visible.
- Most recent event gets a subtle highlight (accent color at low alpha).
- Past events: full opacity. Future events: dimmed (`textDim` color).
- Clicking any row jumps playback to that event's timestamp.

### Filtering Scope
Same curated spell database as unit frames. Auto-attacks and passive procs excluded unless arena-relevant.

## Playback Engine

### State Machine
Three states: `stopped`, `playing`, `paused`.
- `stopped`: Initial state. Unit frames show `initialState` values. Scrubber at 0.
- `playing`: `OnUpdate` advances `currentTime` by `dt * speed`. Events processed as cursor advances.
- `paused`: `currentTime` frozen. User can scrub or click feed events.

### Clock
- `currentTime`: Float, seconds from match start.
- `matchDuration`: Derived from last event timestamp minus first (after match-relative conversion).
- `speed`: One of `0.5`, `1`, `2`, `4`. Applied as multiplier to `dt`.

### Event Cursor
- `cursorIndex`: Integer index into the events array.
- Each OnUpdate tick: while `events[cursorIndex].timestamp <= currentTime`, process event and advance cursor.
- Processing an event updates the replay state tables (per-player HP/power, active auras, cooldown timers).

### Replay State
Maintained as tables indexed by GUID:
```lua
replayState = {
    players = {
        [guid] = {
            health = N,
            healthMax = N,
            power = N,
            powerMax = N,
            auras = { [spellName] = { applied = T, duration = D, isDebuff = bool } },
            cooldowns = { [spellName] = { cast = T, duration = D } },
            alive = bool,
        }
    }
}
```

### Seeking
When the user scrubs to time T or clicks a feed event:
1. Reset all state to `initialState` values.
2. Set `cursorIndex = 1`.
3. Fast-forward: process all events with `timestamp <= T`.
4. Update all unit frames from the rebuilt state (snap, no lerp).

For arena-length matches (typically under 30k events), replaying from start is fast enough. At 30k events, seeking may cause a brief one-frame hitch (~20-50ms) which is acceptable for v1. If this becomes noticeable, batch processing across multiple frames or periodic snapshot caching can be added.

## Timeline Scrubber

Modified `lib:CreateSlider()` spanning the bottom bar.

### Track
- Range: 0 to `matchDuration` seconds.
- Thumb shows current position.
- Click-to-seek on the track.

### Event Markers
Small colored ticks rendered on the track at positions corresponding to key events:
- **Deaths**: Red tick.
- **Trinket uses**: Gold tick.
- **Major defensive CDs**: Blue tick.
- **Major offensive CDs**: Orange tick.

Built at load time by scanning the events array against the spell database.

### Transport Controls
Left of the scrubber:
- `|<` — Jump to start (time 0).
- `>` / `||` — Play/pause toggle.
- `>|` — Jump to end.
- Speed selector: Cycles through `0.5x`, `1x`, `2x`, `4x` on click.

### Time Display
Right of the scrubber: `currentTime / matchDuration` formatted as `m:ss`.

## Spell Database

A Lua table mapping spell names to metadata. Covers TBC 2.4.3 arena-relevant spells. Keyed by spell name with `id` field for icon lookup.

```lua
local REPLAY_SPELLS = {
    -- CC
    ["Polymorph"]           = { id = 12826, cat = "cc",        dur = 10 },
    ["Fear"]                = { id = 5782,  cat = "cc",        dur = 10 },
    ["Psychic Scream"]      = { id = 10890, cat = "cc",        dur = 8 },
    ["Cyclone"]             = { id = 33786, cat = "cc",        dur = 6 },
    ["Hammer of Justice"]   = { id = 10308, cat = "cc",        dur = 6 },
    ["Kidney Shot"]         = { id = 8643,  cat = "cc"              },  -- dur varies by combo points
    ["Blind"]               = { id = 2094,  cat = "cc",        dur = 10 },
    ["Sap"]                 = { id = 11297, cat = "cc",        dur = 10 },
    ["Freezing Trap Effect"]= { id = 14309, cat = "cc",        dur = 10 },

    -- Defensives
    ["Ice Block"]           = { id = 45438, cat = "defensive", dur = 10 },
    ["Divine Shield"]       = { id = 642,   cat = "defensive", dur = 12 },
    ["Pain Suppression"]    = { id = 33206, cat = "defensive", dur = 8 },
    ["Barkskin"]            = { id = 22812, cat = "defensive", dur = 12 },
    ["Cloak of Shadows"]    = { id = 31224, cat = "defensive", dur = 5 },
    ["Evasion"]             = { id = 26669, cat = "defensive", dur = 15 },

    -- Offensives
    ["Bestial Wrath"]       = { id = 19574, cat = "offensive", dur = 18 },
    ["Adrenaline Rush"]     = { id = 13750, cat = "offensive", dur = 15 },
    ["Arcane Power"]        = { id = 12042, cat = "offensive", dur = 15 },

    -- Trinket (TBC: faction-specific trinket items, but CLEU records the shared effect)
    ["PvP Trinket"]         = { id = 42292, cat = "trinket"         },

    -- ... ~80-120 total entries
}
```

Fields:
- `id`: Spell ID for `GetSpellTexture(id)` icon lookup.
- `cat`: `"cc"`, `"defensive"`, `"offensive"`, `"trinket"`, `"healing"`, `"damage"`. Used for feed filtering, icon row display, and timeline markers.
- `dur`: Duration in seconds. For auras: buff/debuff duration (sweep timer). For cooldowns (trinket/offensive/defensive): cooldown duration after cast. `nil` for instants or variable-duration spells. When nil and the spell is an aura, the viewer relies on `SPELL_AURA_REMOVED` to determine when it ended (no sweep timer shown, just presence/absence).

Note: The PvP trinket spell name/ID in CLEU may vary in TBC. The exact names and IDs must be verified against actual CLEU captures. The existing TrinketedCD addon's spell tracking should be referenced for known-correct mappings.

## Entry Point

From the match history list, each row gets a "Replay" button (or the row click handler checks for gameLog presence):
- If `game.gameLog` exists: open replay window.
- If nil: show a micro-tip "No game log recorded" (game was played before the feature was enabled).

## Decompression

On opening the replay window:
1. `LibDeflate:DecodeForPrint(game.gameLog)` — decode from printable string.
2. `LibDeflate:DecompressZlib(decoded)` — decompress.
3. `JSONToTable(json)` — parse into Lua table.
4. Validate `data.v == 1` for version compatibility.
5. Convert all event timestamps from epoch to match-relative seconds.
6. Build initial `replayState` from `initialState`.
7. Scan events to build timeline markers.

If any step fails (decode/decompress returns nil, JSON parse fails, version mismatch), display "Failed to load replay data" in the replay window and disable transport controls.

If `#events == 0`, display "No events recorded" and disable transport controls.

This happens once at open time. The parsed data is held in memory until the window is closed.

## File Location

All replay viewer code lives in `TrinketedHistory/Core.lua` alongside the existing history UI code. The spell database could be a separate file (`TrinketedHistory/ReplaySpells.lua`) loaded via the `.toc` to keep Core.lua from growing excessively, but that's an implementation detail.

## Styling

Follows existing Trinketed conventions:
- Colors: `lib.C.*` palette — `frameBg`, `partyBlue`, `enemyRed`, `accent`, class colors from `CLASS_COLORS` (parsed from hex to r/g/b floats).
- Fonts: `FONT_BODY` for most text, `FONT_DISPLAY` for headers, `FONT_MONO` for timestamps/numbers.
- Borders: 1px `borderSubtle` on unit frames, `borderDefault` on panel dividers.
- Backgrounds: `frameBg` for main panels, `sidebarBg` for the event feed panel, `bgRaised` for unit frame interiors.

## Out of Scope (v1)

- Positional data (CLEU has no coordinates).
- Export/share replay functionality.
- Comparing two replays side by side.
- Snapshot caching for seek optimization (replay-from-start is sufficient).
- `SPELL_AURA_APPLIED_DOSE` / `SPELL_AURA_REMOVED_DOSE` stack tracking.
