# Trinketed

## [v0.1.19-3-ga96ff41](https://github.com/Trinketed/addon/tree/a96ff41c09725c821b6cdc85b06f408117c9af2a) (2026-07-16)
[Full Changelog](https://github.com/Trinketed/addon/compare/v0.1.19...a96ff41c09725c821b6cdc85b06f408117c9af2a) 

- Consolidate suite into monorepo; drop submodules  
    Make the live AddOns install the source of truth and rebuild the repo  
    from it:  
    - Remove TrinketedCD and TrinketedHistory git submodules; vendor their  
      current content as plain folders synced from the AddOns install  
      (TrinketedHistory is now the 5-file replay version, not the stale  
      single-file submodule; TrinketedCD is the current 7-file version)  
    - Add TrinketedAuras and TrinketedLC modules to the tree  
    - Rewrite pkgmeta.yaml to package all four modules via move-folders  
    - Delete obsolete update-submodule workflow; make release.yml  
      CurseForge-ready (drop submodule checkout, add CF\_API\_KEY env)  
    - Ignore .claude/; keep tools/ and addons.json out of packaged builds  
    - Drop stray firebase-debug.log (contained developer email)  
    TrinketedLOS intentionally left out pending security fixes.  
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>  
- docs: add replayer racials implementation plan  
    Seven-task plan implementing the racials design — recategorize SPELL\_DB,  
    add RACE\_COOLDOWNS, plumb race through replay state, render in CD tracker,  
    add gear-menu submenu, and remove dead ReplaySpells.lua.  
    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>  
- docs: add replayer racials design spec  
    Captures the design for surfacing race-specific cooldowns as first-class  
    entities in the TrinketedHistory replay viewer (per-player tracker, gear  
    menu, timeline markers, feed filter).  
    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>  
