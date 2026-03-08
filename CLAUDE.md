# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Trinketed is a World of Warcraft addon suite for arena PvP. It consists of three addons packaged together:

- **Trinketed** (this repo) — Framework, shared UI library (`TrinketedLib`), slash command dispatch
- **TrinketedCD** (submodule → `Trinketed/cd`) — Arena cooldown tracker
- **TrinketedHistory** (submodule → `Trinketed/history`) — Match history and session breakdown

All code is Lua 5.1 targeting the WoW API (Retail, Interface 110207).

## Build & Release

There is no local build step. The BigWigsMods packager runs in CI to produce release zips.

- **Auto-tag:** Every push to `main` triggers `.github/workflows/auto-tag.yml`, which bumps the patch version tag (e.g., v0.1.2 → v0.1.3) using `RELEASE_TOKEN`
- **Release:** Tag creation triggers `.github/workflows/release.yml`, which runs `BigWigsMods/packager@v2 -g retail` to build and publish a GitHub Release
- **Version placeholder:** `.toc` files use `@project-version@` — the packager replaces this with the git tag at build time. Never hardcode versions in `.toc` files.

`pkgmeta.yaml` controls packaging: fetches external libs (LibStub, LibDeflate), moves submodule folders to sibling addon directories, and strips non-essential files.

## Architecture

### LibStub Pattern

`TrinketedLib-1.0` is registered via LibStub and is the sole shared library. All sub-addons access it with `LibStub("TrinketedLib-1.0")`. It provides:

- **Constants:** Font paths (`lib.FONT_DISPLAY`, `lib.FONT_BODY`, `lib.FONT_MONO`), color palette (`lib.C`)
- **Sub-addon registry:** `RegisterSubAddon(name, opts)`, `RegisterSubCommand(name, handler)`
- **Widgets:** Toggle chips, sliders, buttons, section headers, micro-tooltips (`TrinketedLib/Widgets.lua`)
- **Options panel:** Sidebar-tabbed settings frame built lazily on first open (`TrinketedLib/OptionsPanel.lua`)

### Slash Command Dispatch

A single entry point (`/trinketed` or `/trink`) in `Trinketed.lua` routes to sub-command handlers registered by sub-addons via `lib:RegisterSubCommand()`. The `help` command is handled directly.

### Sub-Addon Registration

Feature addons register themselves at load time:
1. Call `lib:RegisterSubAddon(name, opts)` with `name`, `order`, and `OnSelect` callback
2. Call `lib:RegisterSubCommand(name, handler)` for slash sub-commands
3. The options panel auto-generates sidebar tabs from registered sub-addons

### SavedVariables

Each addon has isolated persistence: `TrinketedDB` (core), `TrinketedCDDB` (cooldowns), `TrinketedHistoryDB` (history). Declared in each `.toc` file.

### Submodules

TrinketedCD and TrinketedHistory are git submodules with their own repos. When modifying them, changes must be committed in the submodule repo first, then the submodule reference updated in this parent repo.

## Key Files

| File | Purpose |
|------|---------|
| `Trinketed.lua` | Entry point: slash command dispatch, SavedVariables init |
| `TrinketedLib/TrinketedLib.lua` | LibStub library: fonts, colors, sub-addon registry |
| `TrinketedLib/Widgets.lua` | Reusable UI widget constructors |
| `TrinketedLib/OptionsPanel.lua` | Master settings frame with sidebar navigation |
| `Trinketed.toc` | Addon manifest and file load order |
| `pkgmeta.yaml` | BigWigsMods packager configuration |

## Conventions

- **Color palette:** Always use `lib.C.*` colors from TrinketedLib rather than inline RGBA values
- **Fonts:** Reference `lib.FONT_DISPLAY`, `lib.FONT_BODY`, `lib.FONT_MONO` — fonts live in `Fonts/`
- **UI construction:** Use widget constructors from `Widgets.lua` for consistent styling
- **Gold accent color:** The brand color is `lib.C.accent` (gold: 0.91, 0.73, 0.14), used in chat output as `|cffE8B923`
- **WoW API color strings:** Use `|cff` hex format for chat print coloring (e.g., `|cffE8B923Trinketed|r`)
