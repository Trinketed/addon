# Trinketed Addon Suite Architecture Design

**Date:** 2026-02-26
**Status:** Approved

## Overview

Trinketed is a WoW addon suite for TBC Anniversary (Interface 110207). The `Trinketed/addon` GitHub repo acts as a parent addon containing a shared library (TrinketedLib) and pulling sub-addons as git submodules. Users install one addon via WoWUp and get everything. Individual sub-addons can be disabled in the WoW addon list.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| VOD timestamp functionality | Moves into TrinketedHistory sub-addon | Keeps parent as pure framework |
| TrinketedLib location | Embedded in parent repo | Only serves this suite, not general-purpose |
| Options panel style | Single window, sidebar with sub-addon tabs | TrinketedCD alone has 4 internal tabs; scales naturally |
| UI extraction scope | Extract everything reusable from TrinketedCD | Widgets are stable; avoids duplication in TrinketedHistory |
| Inter-addon communication | Deferred — not needed yet | No concrete consumer; add when TrinketedHistory needs cooldown data |
| Font location | Parent addon's `Fonts/` folder | One copy shared by all sub-addons |
| Library pattern | LibStub-based (`TrinketedLib-1.0`) | Already used by both addons; handles versioning |
| Slash commands | Unified `/trinketed` with sub-commands | Single entry point; sub-addons register sub-commands |

## Constraints

- WoW TBC Anniversary client (modern Classic engine, TBC content)
- Lua 5.1 — no `goto`, no method calls on string literals
- Pure Lua, no external build tools beyond BigWigs packager
- Interface version: 110207

## GitHub Organization

```
Trinketed/addon     → installs as "Trinketed" (parent + framework)
Trinketed/cd        → git submodule, installs as "TrinketedCD"
Trinketed/history   → git submodule, installs as "TrinketedHistory"
```

## Folder Structure

### In the repo (Trinketed/addon)

```
Trinketed/addon/
├── Trinketed.toc
├── Trinketed.lua                       ← minimal loader: slash command dispatch, event wiring
├── Fonts/
│   ├── Inter-Regular.ttf
│   ├── JetBrainsMono-Regular.ttf
│   └── SpaceGrotesk-Bold.ttf
├── Libs/
│   └── LibStub/
│       └── LibStub.lua
├── TrinketedLib/
│   ├── TrinketedLib.lua                ← LibStub registration, constants, colors, fonts
│   ├── Widgets.lua                     ← CreateCheckbox, CreateSlider, CreateButton, etc.
│   └── OptionsPanel.lua               ← master sidebar frame + sub-addon/sub-command registration
├── TrinketedCD/                        ← git submodule → Trinketed/cd
├── TrinketedHistory/                   ← git submodule → Trinketed/history
├── pkgmeta.yaml
├── .github/
│   └── workflows/
│       └── release.yml
└── docs/
    └── plans/
```

### Installed on disk (after BigWigs packaging)

```
Interface/AddOns/
├── Trinketed/
│   ├── Trinketed.toc
│   ├── Trinketed.lua
│   ├── Fonts/
│   ├── Libs/LibStub/
│   └── TrinketedLib/
├── TrinketedCD/                        ← sibling, moved by pkgmeta move-folders
│   ├── TrinketedCD.toc
│   ├── Core.lua
│   ├── Tracker.lua
│   ├── Display.lua
│   ├── Options.lua
│   ├── TestMode.lua
│   ├── Serialize.lua
│   └── CooldownData.lua
└── TrinketedHistory/                   ← sibling, moved by pkgmeta move-folders
    ├── TrinketedHistory.toc
    └── Core.lua
```

## TrinketedLib Architecture

### TrinketedLib.lua — Constants & Registration

Registers via LibStub as `TrinketedLib-1.0`. Provides:

- **Font paths** — `lib.FONT_DISPLAY`, `lib.FONT_BODY`, `lib.FONT_MONO`, all pointing to `Interface\\AddOns\\Trinketed\\Fonts\\...`
- **Color palette** — `lib.C` table with the full theme (surfaces, accents, text hierarchy, borders, semantic colors)
- **Sub-addon registry** — `lib:RegisterSubAddon(name, opts)` for options panel tabs
- **Sub-command registry** — `lib:RegisterSubCommand(name, handler)` for slash command dispatch

### Color Palette (lib.C)

```lua
-- Surfaces
frameBg        = {0.078, 0.078, 0.086, 0.97}
frameBorder    = {0.35, 0.30, 0.15, 0.6}
sidebarBg      = {0.039, 0.039, 0.039, 1}
tabActive      = {0.110, 0.110, 0.118, 1}
tabHover       = {0.078, 0.078, 0.086, 1}
bgElevated     = {0.133, 0.133, 0.149}
bgRaised       = {0.110, 0.110, 0.118}
contentBg      = {0.055, 0.055, 0.060, 0.5}

-- Accent
accent         = {0.91, 0.73, 0.14}
accentGlow     = {0.96, 0.82, 0.31}
accentDim      = {0.55, 0.45, 0.20, 0.35}

-- Text (4-tier hierarchy)
textBright     = {0.957, 0.957, 0.961}
textNormal     = {0.612, 0.639, 0.686}
textDim        = {0.361, 0.369, 0.400}
textMuted      = {0.290, 0.290, 0.322}

-- Borders
borderSubtle   = {0.165, 0.165, 0.184}
borderDefault  = {0.227, 0.227, 0.259}
divider        = {0.35, 0.30, 0.15, 0.25}

-- Semantic
partyBlue      = {0.271, 0.482, 0.616}
enemyRed       = {0.902, 0.224, 0.224}
rowHover       = {1, 1, 1, 0.04}
```

### Widgets.lua — Shared UI Components

Extracted from TrinketedCD's Options.lua. All methods on the lib object:

- `lib:CreateCheckbox(parent, label, default, onChange)` — toggle chip with gold highlight
- `lib:CreateSlider(parent, label, min, max, step, default, onChange)` — range slider with value display
- `lib:CreateButton(parent, label, width, onClick)` — styled button (dark bg, gold hover)
- `lib:CreateSectionHeader(parent, text)` — text label + divider line
- `lib:CreateDropdown(parent, label, items, default, onChange)` — dropdown selector
- `lib:ShowMicroTip(anchor, text)` / `lib:HideMicroTip()` — lightweight tooltips

All widgets use `lib.C` for colors and `lib.FONT_*` for fonts internally. Sub-addons never hardcode theme values.

### OptionsPanel.lua — Master Options Frame

**Registration API:**

```lua
lib:RegisterSubAddon(name, opts)
-- opts = {
--     order = number,                   -- sidebar sort position
--     icon = string,                    -- optional texture path for sidebar
--     OnSelect = function(contentFrame) -- called when sidebar tab selected
--         -- sub-addon builds its UI into contentFrame
--     end,
-- }
```

**Frame structure:**

```
TrinketedOptionsFrame (Frame, 800x500)
├── backdrop (dark bg + gold border)
├── titleBar
│   ├── titleText ("Trinketed")
│   └── closeButton
├── sidebar (~140px left column, sidebarBg color)
│   ├── entry[1] "Cooldowns"   → TrinketedCD
│   ├── entry[2] "History"     → TrinketedHistory
│   └── ... future sub-addons
└── contentArea (fills remaining width)
    └── populated by active sub-addon's OnSelect(contentFrame)
```

When a sidebar entry is clicked, the previous content is hidden/released and `OnSelect(contentFrame)` is called on the newly selected sub-addon. The sub-addon owns the content area and can build internal sub-tabs (TrinketedCD rebuilds its General/Party/Enemy/Test tabs inside).

**Panel controls:**

- `lib:ToggleOptionsPanel()` — show/hide
- `lib:ShowOptionsPanel(subAddonName)` — open to specific tab
- Escape key closes the panel (registered in `UISpecialFrames`)

## Slash Command System

### Unified `/trinketed` command

```
/trinketed                              → opens master panel (first registered tab)
/trinketed cd|cooldown|cooldowns        → opens panel to Cooldowns tab
/trinketed history                      → opens panel to History tab
/trinketed test                         → routes to TrinketedCD: toggle test mode
/trinketed lock                         → routes to TrinketedCD: toggle lock
/trinketed reset                        → routes to TrinketedCD: reset positions
/trinketed help                         → prints available sub-commands
```

**Registration API:**

```lua
lib:RegisterSubCommand(name, handler)
-- handler receives remaining args as a string
-- Example:
lib:RegisterSubCommand("cd", function(args)
    lib:ShowOptionsPanel("Cooldowns")
end)
lib:RegisterSubCommand("test", function(args)
    TrinketedCD:ToggleTestMode()
end)
```

**Dispatch logic in Trinketed.lua:**

```lua
SLASH_TRINKETED1 = "/trinketed"
SLASH_TRINKETED2 = "/trink"
SlashCmdList["TRINKETED"] = function(msg)
    local cmd, args = msg:match("^(%S+)%s*(.*)$")
    if not cmd then
        lib:ToggleOptionsPanel()
        return
    end
    cmd = cmd:lower()
    local handler = lib:GetSubCommand(cmd)
    if handler then
        handler(args)
    else
        print("|cffe8ba23Trinketed:|r Unknown command '" .. cmd .. "'. Type /trinketed help")
    end
end
```

TrinketedCD removes its `/tcd` and `/trinketedcd` slash commands. Everything goes through `/trinketed`.

## TOC Files

### Trinketed.toc

```toc
## Interface: 110207
## Title: Trinketed
## Notes: Trinketed addon suite framework
## Author: ...
## Version: @project-version@
## SavedVariables: TrinketedDB

Libs\LibStub\LibStub.lua
TrinketedLib\TrinketedLib.lua
TrinketedLib\Widgets.lua
TrinketedLib\OptionsPanel.lua
Trinketed.lua
```

### TrinketedCD.toc

```toc
## Interface: 110207
## Title: Trinketed - Cooldowns
## Notes: Arena cooldown tracker
## Author: ...
## Version: @project-version@
## Dependencies: Trinketed
## SavedVariables: TrinketedCDDB

CooldownData.lua
Core.lua
Serialize.lua
Tracker.lua
Display.lua
TestMode.lua
Options.lua
```

### TrinketedHistory.toc

```toc
## Interface: 110207
## Title: Trinketed - History
## Notes: Arena match history and VOD timestamps
## Author: ...
## Version: @project-version@
## Dependencies: Trinketed
## SavedVariables: TrinketedHistoryDB

Core.lua
```

Key: `## Dependencies: Trinketed` ensures WoW loads sub-addons after the parent. Sub-addons can be individually disabled in the addon list. The `Trinketed -` title prefix groups them visually.

## TrinketedCD Refactor Summary

### Files removed from TrinketedCD
- `Fonts/` directory (uses parent's fonts)
- `Libs/LibStub/` (loaded by parent)
- `pkgmeta.yaml` (releases driven from parent)
- `.github/workflows/release.yml` (releases driven from parent)

### Core.lua changes
- Remove font constant definitions (use `TrinketedLib.FONT_*`)
- Remove slash command registration (register sub-commands via `lib:RegisterSubCommand`)
- Remove class color constants if moved to lib (evaluate — may stay since they're tracker-specific)

### Options.lua changes
- Remove color palette `C` table (use `lib.C`)
- Remove widget builder functions (use `lib:Create*`)
- Remove micro-tip system (use `lib:ShowMicroTip`)
- Remove master frame creation (register via `lib:RegisterSubAddon`)
- Keep all settings content (General/Party/Enemy/Test tab logic, grid builder, import/export)
- Internal sub-tabs built inside the content frame provided by `OnSelect`

## pkgmeta.yaml

```yaml
package-as: Trinketed

externals:
  Libs/LibStub: https://repos.wowace.com/wow/libstub/trunk

move-folders:
  Trinketed/TrinketedCD: TrinketedCD
  Trinketed/TrinketedHistory: TrinketedHistory

ignore:
  - .github
  - docs
  - "*.md"
  - .gitignore
  - .gitmodules
  - pkgmeta.yaml
```

- `package-as: Trinketed` — parent repo installs as `Trinketed/`
- `move-folders` — extracts submodule folders to sibling AddOn directories in the zip
- Final zip: `Trinketed/`, `TrinketedCD/`, `TrinketedHistory/` at the same level

## GitHub Actions

### release.yml (in Trinketed/addon)

```yaml
name: Package and Release
on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: BigWigsMods/packager@v2
        with:
          args: -g classic
```

### Release flow

1. Update submodule refs to desired commits
2. Push tag `v1.2.0` to `Trinketed/addon`
3. GitHub Actions checks out repo + all submodules recursively
4. BigWigs packager builds zip with all three addon folders
5. GitHub Release created with the zip
6. WoWUp users pointing at `Trinketed/addon` get the update

## Future Extensibility

- **New sub-addons:** Create repo (e.g., `Trinketed/ratings`), add as submodule, add to `move-folders` in pkgmeta.yaml. Sub-addon registers with `lib:RegisterSubAddon` and `lib:RegisterSubCommand`. Done.
- **Inter-addon messaging:** When needed, add `lib:RegisterMessage(event, callback)` and `lib:SendMessage(event, ...)` to TrinketedLib. Sub-addons fire custom events, others listen.
- **Shared data providers:** When needed, add `lib:RegisterDataProvider(name, getterFn)` and `lib:GetData(name, ...)`. Sub-addons expose queryable APIs.
