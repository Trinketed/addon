# TrinketedHistory

Arena match history, in-game replays, and VOD timestamps. Part of the [Trinketed](https://github.com/Trinketed/addon) addon suite.

## Features

### Match History
- Automatically records every arena match (2v2, 3v3, 5v5) — no setup
- Tracks teams, specs, races, ratings, rating/MMR changes, duration, and per-player scoreboard stats (killing blows, deaths, damage, healing)
- Skirmishes are detected and labelled, so rating-less games are never mistaken for rated ones
- One-click ArenaAnalytics import (Settings tab): brings your existing history along — results, ratings, rosters, match types. Imported games have no replay (replays exist only for games Trinketed records live) and show an Imported tag instead
- Filterable by comp, partner, enemy comp, enemy player, enemy race, map, bracket, match type (rated/skirmish), season, result — plus free-text search (player/class/race/map terms, all must match)
- Queue timer: prints how long the queue took when it pops

### Sessions / Teams / Enemies
- **Sessions** — matches grouped into play sessions (60-min gap or partner change), with W-L, win%, rating range, net rating; drill-down to individual matches
- **Teams** — per-team records across everything you've played
- **Enemies** — every player you've faced with your record against them; click an enemy to jump to all games versus them

### Replays
- Watch any recorded match back in-game: health/mana, cooldowns, auras, CC with diminishing-returns tracking, filterable event feed
- **Death recap** — click a death in the feed for the victim's final 8 seconds (damage with real amounts, heals, CC, defensives)
- **Share strings** — export any match (`/trinketed share [n]`) as a string a teammate can `/trinketed import` to watch in their own client (imported games never enter their own history/stats)

### Data Persistence
- SavedVariables only write on logout//reload, so the addon (optionally, default on) auto-reloads right after you zone out of an arena — guarded so it never fires while queued or in combat; `/trinketed noreload` cancels
- A sync nudge on the Matches tab shows how many games aren't on disk yet (relevant before uploading to the web app)

### VOD Timestamps
- Barcode overlay encodes epoch timestamps into recorded video for VOD syncing
- Match start/end epoch times stored per game
- Minimap button for quick access

## Commands

- `/trinketed history` — toggle the history window
- `/trinketed share [n]` — export match n (default: latest) as a share string
- `/trinketed import` — paste a share string, opens the replay directly
- `/trinketed noreload` — cancel a pending post-arena auto-reload

## Dependencies

Requires the core [Trinketed](https://github.com/Trinketed/addon) addon (provides `TrinketedLib`, LibDeflate, DRList-1.0).

## Development

This folder is part of the [Trinketed monorepo](https://github.com/Trinketed/addon) — edit, commit, and push there. See the root README for the junction-based dev setup.

## Data Storage

Match data is stored in `TrinketedHistoryDB` (WoW SavedVariables), including a compressed full event log per game (powers replays and the web app). Sessions/teams/enemies views are computed on the fly from match data.
