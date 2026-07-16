# Trinketed

## Latest
- Arena season filter in TrinketedHistory: new games capture `GetCurrentArenaSeason()` at save time; pre-existing games are backfilled to season 1 on load. Added a Season dropdown to the Matches, Sessions, and Teams tabs (single-select, populated from the seasons present in the saved games)
- Prune `SPEC_SPELLS`: dropped 25 WotLK 3.0+ talent entries (Bladestorm, Shockwave, Beacon of Light, Divine Storm, Killing Spree, Shadow Dance, Penance, Guardian Spirit, Arcane Barrage, Living Bomb, Deep Freeze, Haunt, Metamorphosis, Demonic Empowerment, Chaos Bolt, Thunderstorm, Feral Spirit, Riptide, Cleanse Spirit, Chimera Shot, Explosive Shot, Starfall, Typhoon, Survival Instincts, Berserk, Wild Growth) — the addon targets TBC 2.4.3, so these were unreachable lookup keys
- Tighten TrinketedHistory Core.lua: removed two unused team-formatting helpers (`FormatTeam`, `FormatTeamClasses`), dead end-of-function stat aggregators in `RefreshHistory` and `RefreshSessions`, and a redundant `compList → qualified` array copy in `RefreshStats`. Extracted three helpers (`FormatWinPct`, `FormatRatingChange`, `FormatEnemyTeam`) to collapse three pairs of duplicated render blocks across the Matches / Sessions / Teams tabs
- Drop dead Death Knight code paths: removed `Deathknight` from `CLASS_COLORS` and the DK `SPEC_SPELLS` block in TrinketedHistory (TBC has no Death Knights)
- Remove unused locals in the replay subsystem: `ICON_SIZE` / `ICON_GAP` in ReplayUI and the never-read `alive` field on player state in ReplayEngine
- Repo hygiene: stripped 53 stray `*Zone.Identifier` files, untracked `firebase-debug.log` and the `.superpowers/` agent scratch dir, normalized `Trinketed.toc` / `pkgmeta.yaml` mode bits, and added matching `.gitignore` rules
- Trim TrinketedHistory debug surfaces: removed the `/trinketed debuglog` and `/trinketed cleu` developer commands, the half-height mini-barcode (and its `bcdebug` / `mbcdebug` / `tsmbdebug` toggles), and the legacy `TrinketedDB → TrinketedHistoryDB` migration shim
- Remove TrinketedHistory export/import: dropped `/trinketed export`, `/trinketed import`, the Export button in the History window, and the Ctrl+left-click minimap shortcut
- Add Sessions tab to TrinketedHistory — groups arena matches into play sessions by time gap and partner changes
- Session list with drill-down showing individual matches in full Matches tab format
- Bracket, time range, and partner filters for sessions
- Auto-release workflow: pushes to main now auto-tag and cut a release

## [v0.1.2](https://github.com/Trinketed/addon/tree/v0.1.2) (2026-02-26)
[Full Changelog](https://github.com/Trinketed/addon/commits/v0.1.2) [Previous Releases](https://github.com/Trinketed/addon/releases)

- Fix LibDeflate external: use GitHub repo instead of curseforge SVN
