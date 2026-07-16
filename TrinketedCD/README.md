# TrinketedCD

Arena cooldown tracker addon for World of Warcraft. Part of the [Trinketed](https://github.com/Trinketed/addon) addon suite.

## Features

- Tracks enemy trinket and major cooldown usage in arena
- Class-colored cooldown display with duration timers
- Supports all arena brackets (2v2, 3v3, 5v5)
- Configurable display layout and positioning
- Test mode for trying out the UI outside of arena
- Import/export cooldown profiles

## Supported Zones

- Nagrand Arena
- Blade's Edge Arena
- Ruins of Lordaeron

## Dependencies

Requires the core [Trinketed](https://github.com/Trinketed/addon) addon to be installed and loaded first.

## Development

This repo is included as a git submodule in the [main Trinketed repo](https://github.com/Trinketed/addon). To work on it:

```
git clone --recurse-submodules git@github.com:Trinketed/addon.git
cd TrinketedCD
# make changes, commit, push to this repo
cd ..
git add TrinketedCD
git commit -m "Update TrinketedCD"
git push  # triggers auto-release
```

## File Structure

| File | Purpose |
|------|---------|
| `Core.lua` | Namespace, constants, state, event handling, slash commands |
| `CooldownData.lua` | Cooldown spell database (abilities, durations, classes) |
| `Tracker.lua` | Combat log parsing, cooldown state tracking |
| `Display.lua` | UI frames, cooldown bars, timer rendering |
| `Options.lua` | Settings panel, layout configuration |
| `Serialize.lua` | Import/export profile serialization |
| `TestMode.lua` | Simulated arena environment for UI testing |

## Data Storage

Settings and profiles are stored in `TrinketedCDDB` (WoW SavedVariables).
