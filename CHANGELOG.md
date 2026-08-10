# Trinketed

> Dev-facing changelog. Release notes on GitHub Releases are auto-generated
> from commit messages by the packager; this file is stripped from builds.

## Latest (2026-08)
- **Open in Trinketed:** clicking a row on the Matches tab now opens a flyout with "Open in Trinketed app" and "Copy web link". The app option writes a jump intent to SavedVariables and reloads — the desktop companion picks it up on the flush, brings its window forward, and opens that game's review. The web option surfaces a `trinketed.com/goto` link pre-selected for Ctrl+C (WoW has no clipboard API). Dev mode keeps its game-id copy as a third entry. Without the companion running, the app option is a no-op reload; the web link works for everyone.

## 2026-07
- **Monorepo consolidation:** dropped the TrinketedCD/TrinketedHistory git submodules and vendored all modules as plain sibling folders; TrinketedAuras, TrinketedLC, and TrinketedLOS are now tracked in-repo but excluded from releases (`pkgmeta.yaml` ignore). Deleted the notify-parent/update-submodule workflow chain. Releases ship core + Cooldowns + History.
- **Enemies tab** in TrinketedHistory (Matches | Sessions | Teams | Enemies | Settings): every enemy faced with games/W-L/win%/net rating, sortable columns, name search; click an enemy to jump to the Matches tab filtered to all games against them
- **Free-text match search** on the Matches tab: space-separated terms all must match player names/classes/specs/races on either team or the map
- **Match share strings:** `/trinketed share [n]` exports a match (TRINKR1! prefix, LibDeflate); `/trinketed import` opens a pasted match directly in the replay viewer without adding it to your own history
- **Death recap** in the replay viewer: click a death in the feed for the victim's final 8 seconds — damage with real amounts and crit markers, effective healing, absorbs, misses, CC with DR category tags, and their own defensive casts
- **Queue timer:** chat prints how long the arena queue took when it pops (server-tracked wait time, survives /reload mid-queue)
- **Scoreboard capture:** per-player killing blows, deaths, damage, and healing are stored with each match
- **Safer data persistence:** replaced the old queue-time forced ReloadUI with an opt-out auto-reload that fires after zoning out of an arena (5s countdown, `/trinketed noreload` to cancel, never fires while queued or in combat), plus a Matches-tab nudge showing games not yet flushed to disk
- **Fix:** leaving the arena quickly after a win no longer records a LOSS (uses the already-detected winner)
- Vendored DRList-1.0 (DR tracking in replays) and wired it as a packager external; dynamic Welcome-tab module list driven by `RegisterSubAddon(desc=...)`; options panel now fires content OnShow on first open; removed TrinketedCD's dead legacy color picker; README/CLAUDE.md rewritten for the monorepo

## Earlier (pre-monorepo, unreleased notes)
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
