# Trinketed

A modular WoW addon suite for arena PvP on the Anniversary (TBC) realms. Tracks
party cooldowns, records every arena match automatically, and replays them
in-game — with VOD timestamps and a companion web app for deeper analysis.

## Addons

| Addon | Ships in release | Description |
|-------|------------------|-------------|
| **Trinketed** (core) | ✅ | Framework, shared UI library (`TrinketedLib`), options panel, slash commands |
| **TrinketedCD** | ✅ | Real-time party cooldown tracker with customizable bars and import/export |
| **TrinketedHistory** | ✅ | Match history, sessions/teams/enemies stats, full match replays, death recap, share strings |
| **TrinketedAuras** | local-only | Personal buff/debuff icon groups |
| **TrinketedLC** | local-only | Loss-of-control alerts (CC, silences, interrupt lockouts) |
| **TrinketedLOS** | local-only | Line-of-sight alert relay (experimental; excluded pending security fixes) |

"Local-only" modules are tracked in this repo and load on dev machines but are
excluded from packaged releases (see `ignore` in `pkgmeta.yaml`). To ship one,
remove its `ignore` entry and add a `move-folders` line.

## Installation (users)

Download the latest zip from [Releases](https://github.com/Trinketed/addon/releases)
and extract into `Interface/AddOns/`:

```
Interface/AddOns/
  Trinketed/           <- Core (required)
  TrinketedCD/         <- Cooldown tracker
  TrinketedHistory/    <- Match history + replays
```

## Commands

- `/trinketed` or `/trink` — open settings
- `/trinketed share [n]` — export a recorded match as a share string
- `/trinketed import` — import a shared match and open its replay
- `/trinketed noreload` — cancel a pending post-arena auto-reload
- `/trinketed help` — list all registered commands

## Repository Structure

Single repo, flat layout — the repo root **is** the core addon and each module
is a plain sibling folder (no submodules):

```
Trinketed/                  <- This repo = the core addon
  Trinketed.toc             <- Core manifest
  Trinketed.lua             <- Slash dispatch, welcome tab, verification
  TrinketedLib/             <- Shared UI library (colors, fonts, widgets, options panel)
  Libs/                     <- LibStub, LibDeflate, DRList-1.0 (committed for dev;
                               replaced by upstream at package time via externals)
  Fonts/                    <- Inter, Space Grotesk, JetBrains Mono
  TrinketedCD/              <- Module folders (each with its own .toc,
  TrinketedHistory/            `## Dependencies: Trinketed`)
  TrinketedAuras/
  TrinketedLC/
  TrinketedLOS/
  pkgmeta.yaml              <- BigWigsMods packager config
  .github/workflows/        <- auto-tag.yml, release.yml
  docs/  tools/             <- Dev-only, stripped from releases
```

## Development Setup

The dev workflow uses NTFS junctions so the game loads the checkout directly —
no copy step, no drift:

```powershell
git clone git@github.com:Trinketed/addon.git C:\dev\Trinketed
git -C C:\dev\Trinketed config core.autocrlf false
```

Then, with WoW closed, remove any real `Trinketed*` folders from
`Interface\AddOns\` and junction each module (note: the core points at the
repo **root**):

```powershell
$addons = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns"
New-Item -ItemType Junction -Path "$addons\Trinketed"        -Target "C:\dev\Trinketed"
New-Item -ItemType Junction -Path "$addons\TrinketedCD"      -Target "C:\dev\Trinketed\TrinketedCD"
New-Item -ItemType Junction -Path "$addons\TrinketedHistory" -Target "C:\dev\Trinketed\TrinketedHistory"
New-Item -ItemType Junction -Path "$addons\TrinketedAuras"   -Target "C:\dev\Trinketed\TrinketedAuras"
New-Item -ItemType Junction -Path "$addons\TrinketedLC"      -Target "C:\dev\Trinketed\TrinketedLC"
New-Item -ItemType Junction -Path "$addons\TrinketedLOS"     -Target "C:\dev\Trinketed\TrinketedLOS"
```

Daily loop: edit → `/reload` in-game to test → commit/push. On another machine:
`git pull` → `/reload`. Lua edits need only a `/reload`; TOC changes or
new addon folders need a full client restart. Addons report version `"dev"`
when running from a checkout — real versions are stamped only in packaged
builds.

## Packaging

The [BigWigsMods packager](https://github.com/BigWigsMods/packager) reads
`pkgmeta.yaml` and:

1. Stages the repo root as the `Trinketed/` addon folder
2. Substitutes `@project-version@` in TOCs with the git tag
3. Fetches external libraries (LibStub, LibDeflate, DRList-1.0) from upstream
4. Hoists shipped module folders out to siblings (`move-folders`)
5. Strips dev files and local-only modules (`ignore`)

Local build (WSL/Linux; output lands in `.release/`, which is gitignored):

```bash
curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh -o /tmp/release.sh
bash /tmp/release.sh -e -d -z -g retail
```

## Releases

Releases are automatic. Every push to `main` triggers:

1. **auto-tag.yml** — bumps the patch version and creates the next `v*` tag
2. **release.yml** — packager builds the zip and publishes a GitHub Release
   (and uploads to CurseForge once `CF_API_KEY` + `## X-Curse-Project-ID` are set)

Manual version bumps: push a tag like `v0.2.0` yourself; auto-tag continues
from the highest existing tag.

## Game Version

Built for the WoW Anniversary (TBC) client, which runs the retail 11.x engine.
Interface version: `110207`.
