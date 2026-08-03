# TrinketedCD

Party cooldown tracker for arena PvP. Part of the [Trinketed](https://github.com/Trinketed/addon) addon suite.

## Features

- Tracks your **party members'** cooldowns in arena — trinkets, interrupts, defensives, offensives — started automatically from the combat log
- Cooldown bars anchored to party frames (left/right side) or placed freely
- Per-class spell selection arranged in a customizable grid
- Shared and linked cooldowns handled correctly (e.g. Divine Shield / Blessing of Protection)
- Glow when a cooldown comes back up, flash on use, pulse on low timer
- Import/export layout strings to share setups with teammates
- Optional tracking outside arena (suppressed in raids)
- Test mode for configuring the UI outside of arena

Arena detection uses `IsInInstance()` — no hardcoded zone list. All brackets (2v2/3v3/5v5) supported.

## Commands

Open the settings with `/trinketed` → Cooldowns tab. Test mode and all options live there.

## Dependencies

Requires the core [Trinketed](https://github.com/Trinketed/addon) addon (provides `TrinketedLib`).

## Development

This folder is part of the [Trinketed monorepo](https://github.com/Trinketed/addon) — edit, commit, and push there. See the root README for the junction-based dev setup.

## File Structure

| File | Purpose |
|------|---------|
| `Core.lua` | Namespace, constants, state, event handling |
| `CooldownData.lua` | Cooldown spell database (abilities, durations, classes) |
| `Tracker.lua` | Combat log parsing, cooldown state tracking |
| `Display.lua` | UI frames, cooldown bars, timer rendering |
| `Options.lua` | Settings panel, grid layout configuration |
| `Serialize.lua` | Import/export layout serialization |
| `TestMode.lua` | Simulated party for UI testing |

## Data Storage

Settings and layouts are stored in `TrinketedCDDB` (WoW SavedVariables).
