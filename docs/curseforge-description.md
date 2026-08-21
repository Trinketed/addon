# CurseForge project description (draft)

Paste into the CurseForge project's description editor when creating the
project. Game version: **Burning Crusade Classic (2.5.5)**. Category:
PvP / Arena. This file is repo-internal (docs/ is packager-ignored).

---

**Trinketed** is an arena suite for the TBC Anniversary realms: a party
cooldown tracker, automatic match history, and full in-game replays of
every arena game you play.

## Match history & replays (TrinketedHistory)

- **Every arena match is recorded automatically** — no setup, no keybind.
  Rating changes, comps, maps, durations, per-player scoreboard.
- **Replay any match in-game**: watch the whole game back with unit
  frames, cast bars, cooldowns, CC with DR tracking, and a death recap
  (the victim's final seconds — damage, healing, absorbs, CC).
- **Stats that answer questions**: sessions, teams, and enemies tabs with
  win rates and net rating; filter matches by bracket, comp (same slot
  builder as the web app), match type (skirmishes are detected and kept
  out of your rated list), season, or free-text search.
- **Share strings**: `/trinketed share` exports a match; anyone with the
  addon can `/trinketed import` it and watch the replay.
- **Switching from ArenaAnalytics?** One click in the History settings
  imports your whole ArenaAnalytics record — results, ratings, rosters,
  match types — so your history comes with you. (Imported games have no
  replay; replays exist only for games Trinketed records live.)

## Party cooldowns (TrinketedCD)

Real-time tracker for your party's defensives and offensives with
customizable bars and profile import/export.

## The companion (optional)

Trinketed pairs with **[trinketed.com](https://trinketed.com)** — upload
your match history for a web replay timeline, and sync recorded video so
every game becomes a clip with combat log and unit frames locked to the
footage. The addon is fully functional standalone; the companion adds
the VOD layer.

## Commands

- `/trinketed` — settings
- `/trinketed share [n]` / `/trinketed import` — match share strings
- `/trinketed help` — everything else

## Notes

- After a play session, `/reload` (or log out) writes your latest games
  to disk — the addon nudges you when games haven't been flushed yet.
- Data is stored per-account in SavedVariables; nothing leaves your
  machine unless you use share strings or the companion.
