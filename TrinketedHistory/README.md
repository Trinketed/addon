# TrinketedHistory

Arena match history and VOD timestamp addon for World of Warcraft. Part of the [Trinketed](https://github.com/Trinketed/addon) addon suite.

## Features

### Match History
- Automatically records arena matches (2v2, 3v3, 5v5)
- Tracks teams, specs, races, ratings, rating changes, MMR, duration
- Filterable by comp, partner, enemy comp, enemy player, enemy race, result

### Session Breakdown
- Groups matches into play sessions based on time gaps (60 min) and partner changes
- Session list shows partners, bracket, W-L, win%, rating range, net rating change
- Drill-down expands sessions to show individual matches
- Filter by bracket, time range, or partner

### VOD Timestamps
- Records match start/end times for syncing with stream VODs
- Minimap button for quick access

## Commands

- `/trinketed history` -- toggle the history window
- `/trinketed minimap` -- toggle minimap button

## Dependencies

Requires the core [Trinketed](https://github.com/Trinketed/addon) addon to be installed and loaded first.

## Development

This repo is included as a git submodule in the [main Trinketed repo](https://github.com/Trinketed/addon). To work on it:

```
git clone --recurse-submodules git@github.com:Trinketed/addon.git
cd TrinketedHistory
# make changes, commit, push to this repo
cd ..
git add TrinketedHistory
git commit -m "Update TrinketedHistory"
git push  # triggers auto-release
```

## Data Storage

Match data is stored in `TrinketedHistoryDB` (WoW SavedVariables). Sessions are computed on-the-fly from match data -- no separate storage needed.
