# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Trinketed is a World of Warcraft addon suite for arena PvP on the Anniversary (TBC) realms. Single monorepo, flat layout: the repo root is the core addon; each module is a plain sibling folder with its own `.toc` declaring `## Dependencies: Trinketed`. No submodules.

- **Trinketed** (repo root) — Framework, shared UI library (`TrinketedLib`), options panel, slash dispatch — *shipped*
- **TrinketedCD/** — Party cooldown tracker — *shipped*
- **TrinketedHistory/** — Match history, sessions/teams/enemies stats, in-game replays, death recap, share strings — *shipped*
- **TrinketedAuras/** — Personal buff/debuff icon groups — *local-only*
- **TrinketedLC/** — Loss-of-control alerts — *local-only*
- **TrinketedLOS/** — Line-of-sight relay — *local-only, excluded pending security fixes (comms spoofing/injection)*

"Local-only" = tracked in git and loaded on dev machines, but listed under `ignore` in `pkgmeta.yaml` so releases exclude it. To ship a module: remove its `ignore` entry, add a `move-folders` line.

All code is Lua 5.1 targeting the WoW retail 11.x API (Interface 110207 — the Anniversary client runs the retail engine). Guard newer APIs: prefer the `C_Spell and C_Spell.GetSpellInfo ... elseif GetSpellInfo` fallback pattern (see `TrinketedCD/Tracker.lua`).

## Development Workflow

Dev machines junction the game's AddOns folders directly into this checkout (`C:\dev\Trinketed` — core junction points at the repo **root**), so editing the repo IS editing what WoW loads:

- Lua edit → `/reload` in-game. TOC changes or new addon folders → full client restart.
- SavedVariables flush to disk only on logout//reload (TrinketedHistory auto-reloads after arena exit when enabled).
- Never create a second copy of the addons; the junctions are the anti-drift mechanism. Cross-machine sync is plain `git pull`/`push`.
- Windows git has no committer identity configured — run git via WSL (`/mnt/c/dev/Trinketed`).
- Addons report version `"dev"` from checkouts; real versions are stamped only in packaged builds.

## Build & Release

No local build step needed for testing (junctions). The BigWigsMods packager runs in CI:

- **Auto-tag:** every push to `main` triggers `auto-tag.yml` → bumps patch tag (`RELEASE_TOKEN` PAT, org-level secret)
- **Release:** the new tag triggers `release.yml` → `BigWigsMods/packager@v2 -g retail` → GitHub Release (CurseForge upload activates once `CF_API_KEY` secret and `## X-Curse-Project-ID` in `Trinketed.toc` exist)
- **Version placeholder:** `.toc` files use `@project-version@` — never hardcode versions
- `pkgmeta.yaml`: externals (LibStub, LibDeflate, DRList-1.0 — committed copies in `Libs/` exist for dev, replaced from upstream at build time), `move-folders` hoists shipped modules to siblings, `ignore` strips dev files + local-only modules
- Local package build (WSL): `bash /tmp/release.sh -e -d -z -g retail` after fetching the packager's `release.sh`; output in `.release/` (gitignored)

## Architecture

### LibStub Pattern

`TrinketedLib-1.0` is registered via LibStub and is the sole shared library. All sub-addons access it with `LibStub("TrinketedLib-1.0")`. It provides:

- **Constants:** Font paths (`lib.FONT_DISPLAY`, `lib.FONT_BODY`, `lib.FONT_MONO`), color palette (`lib.C`)
- **Sub-addon registry:** `RegisterSubAddon(name, opts)` — opts include `order`, `desc` (shown on the Welcome tab's dynamic module list), and `OnSelect`; `RegisterSubCommand(name, handler)`
- **Widgets:** Toggle chips, sliders, buttons, section headers, tab bars, micro-tooltips (`TrinketedLib/Widgets.lua`)
- **Options panel:** Fixed-size (932×520) sidebar-tabbed settings frame built lazily on first open (`TrinketedLib/OptionsPanel.lua`). The master frame is shown before sub-addon selection so contentFrame `OnShow` handlers fire — modules rely on `OnShow` to refresh tab data.

### Slash Command Dispatch

A single entry point (`/trinketed` or `/trink`) in `Trinketed.lua` routes to sub-command handlers registered by sub-addons via `lib:RegisterSubCommand()`. The `help` command is handled directly.

### Sub-Addon Registration

Feature addons register themselves at load time:
1. Call `lib:RegisterSubAddon(name, opts)` with `name`, `order`, `desc`, and `OnSelect` callback
2. Call `lib:RegisterSubCommand(name, handler)` for slash sub-commands
3. The options panel auto-generates sidebar tabs; the Welcome tab renders the module list from the registry

### SavedVariables

Isolated per addon: `TrinketedDB` (core), `TrinketedCDDB`, `TrinketedHistoryDB`, `TrinketedAurasDB`, `TrinketedLCDB`, `TrinketedLOSDB`. Declared in each `.toc`. Do not attach transient/computed fields to persisted tables (use weak-keyed side caches — see `searchTextCache` in TrinketedHistory).

### Known Constraints

- `TrinketedHistory/Core.lua` is close to Lua's 200-locals-per-chunk limit — when adding features, prefer one table-valued local holding related state/functions over multiple chunk-level locals.
- Compile-check Lua before committing (no luac on the system; fengari via Node works — load each file with `luaL_loadstring` and assert OK).
- Frames are never garbage-collected: pool and reuse rows/icons; never recreate frames per refresh.

## Key Files

| File | Purpose |
|------|---------|
| `Trinketed.lua` | Entry point: slash dispatch, Welcome tab, SavedVariables init, verification |
| `TrinketedLib/TrinketedLib.lua` | LibStub library: fonts, colors, sub-addon registry |
| `TrinketedLib/Widgets.lua` | Reusable UI widget constructors |
| `TrinketedLib/OptionsPanel.lua` | Master settings frame with sidebar navigation |
| `TrinketedHistory/Core.lua` | Match recording state machine, history UI (Matches/Sessions/Teams/Enemies/Settings), share/import, queue timer |
| `TrinketedHistory/ReplayEngine.lua` + `ReplayUI.lua` | Replay parsing/playback and viewer (incl. death recap) |
| `pkgmeta.yaml` | BigWigsMods packager configuration (incl. local-only module list) |

## Conventions

- **Color palette:** Always use `lib.C.*` colors from TrinketedLib rather than inline RGBA values
- **Fonts:** Reference `lib.FONT_DISPLAY`, `lib.FONT_BODY`, `lib.FONT_MONO` — fonts live in `Fonts/`
- **UI construction:** Use widget constructors from `Widgets.lua` for consistent styling
- **Inner tabs:** Sub-addons use `lib:CreateTabBar(parent, tabs, opts)` for horizontal top tabs within their options content area — not custom sidebar tab code
- **Panel size:** All sub-addons share the same fixed-size options panel (932×520). Do not use `contentWidth` to resize per tab — design content to fit the 780px content area (`lib:GetContentWidth()`) so switching tabs is not visually jarring
- **Gold accent color:** The brand color is `lib.C.accent` (gold: 0.91, 0.73, 0.14), used in chat output as `|cffE8B923`
- **WoW API color strings:** Use `|cff` hex format for chat print coloring (e.g., `|cffE8B923Trinketed|r`)
- **User-facing chat:** prefix with `|cff00ccff<DisplayName>:|r` (module style) and gate diagnostics behind each module's `dbg()`/debug flag
