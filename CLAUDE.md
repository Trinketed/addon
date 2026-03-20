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
- **Widgets:** Toggle chips, sliders, buttons, section headers, tab bars, micro-tooltips (`TrinketedLib/Widgets.lua`)
- **Options panel:** Fixed-size (932×520) sidebar-tabbed settings frame built lazily on first open (`TrinketedLib/OptionsPanel.lua`)

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

TrinketedCD and TrinketedHistory are git submodules with their own repos (`Trinketed/cd` and `Trinketed/history` on GitHub). All repos use `main` as the default branch.

**Development workflow:** Edit files directly in the submodule directories (`TrinketedCD/` and `TrinketedHistory/`), commit and push from within them. The `~/bin/sync-trinketed.sh` script rsyncs all addon directories to the WoW AddOns folder for local testing.

**Automated submodule updates:** Each submodule repo has a `notify-parent.yml` workflow that triggers the parent repo's `update-submodule.yml` on push to `main`. This automatically updates the submodule pointer, which then triggers auto-tag → release. No manual submodule pointer management is needed.

**Pipeline:** Submodule push → `notify-parent.yml` → `update-submodule.yml` → `auto-tag.yml` → `release.yml`

The `RELEASE_TOKEN` PAT is stored as an org-level secret on the Trinketed GitHub org.

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
- **Inner tabs:** Sub-addons use `lib:CreateTabBar(parent, tabs, opts)` for horizontal top tabs within their options content area — not custom sidebar tab code
- **Panel size:** All sub-addons share the same fixed-size options panel (932×520). Do not use `contentWidth` to resize per tab — design content to fit the 780px content area (`lib:GetContentWidth()`) so switching tabs is not visually jarring
- **Gold accent color:** The brand color is `lib.C.accent` (gold: 0.91, 0.73, 0.14), used in chat output as `|cffE8B923`
- **WoW API color strings:** Use `|cff` hex format for chat print coloring (e.g., `|cffE8B923Trinketed|r`)
