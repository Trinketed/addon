# Trinketed

A modular WoW addon suite for arena PvP. Tracks cooldowns, records match history, and provides VOD timestamps.

## Addons

| Addon | Description |
|-------|-------------|
| **Trinketed** (core) | Framework, shared UI library, slash command dispatch |
| **[TrinketedCD](https://github.com/Trinketed/cd)** | Arena cooldown tracker |
| **[TrinketedHistory](https://github.com/Trinketed/history)** | Match history, session breakdown, VOD timestamps |

## Installation

Download the latest release from [Releases](https://github.com/Trinketed/addon/releases) and extract to your `Interface/AddOns/` folder. The zip contains three addon folders:

```
Interface/AddOns/
  Trinketed/           <- Core (required)
  TrinketedCD/         <- Cooldown tracker
  TrinketedHistory/    <- Match history
```

## Commands

- `/trinketed` or `/trink` -- open settings
- `/trinketed history` -- toggle match history window
- `/trinketed help` -- list all commands

## Repository Structure

This is the main repo. TrinketedCD and TrinketedHistory live in separate repos and are included here as git submodules.

```
Trinketed/                  <- This repo
  Trinketed.toc             <- Core addon manifest
  Trinketed.lua             <- Slash commands, initialization
  TrinketedLib/             <- Shared UI library (colors, fonts, widgets)
  Libs/                     <- External dependencies (LibStub, LibDeflate)
  Fonts/                    <- Custom fonts (Inter, Space Grotesk, JetBrains Mono)
  TrinketedCD/              <- Submodule -> github.com/Trinketed/cd
  TrinketedHistory/         <- Submodule -> github.com/Trinketed/history
  pkgmeta.yaml              <- BigWigsMods packager config
```

### Submodules

Each feature addon is a separate git repo pinned at a specific commit:

```
git clone --recurse-submodules git@github.com:Trinketed/addon.git
```

To update a submodule after pushing changes to its repo:

```
cd TrinketedHistory
git pull origin master
cd ..
git add TrinketedHistory
git commit -m "Update TrinketedHistory submodule"
```

### Packaging

The [BigWigsMods packager](https://github.com/BigWigsMods/packager) handles release builds. It:

1. Packages this repo root as the `Trinketed/` addon folder
2. Fetches external libraries (LibStub, LibDeflate)
3. Moves submodule folders out to sibling addon folders (`TrinketedCD/`, `TrinketedHistory/`)
4. Strips docs, markdown files, and config files

## Releases

Releases are automatic. Every push to `main` triggers:

1. **auto-tag.yml** -- bumps the patch version and creates a new `v*` tag
2. **release.yml** -- BigWigsMods packager builds the addon zip and creates a GitHub Release

You can also manually tag for specific version bumps (e.g. `git tag v0.2.0`).

## Game Version

Built for WoW 11.0.2 (Retail). Interface version: `110207`.
