# TrinketedHistory Session Breakdown Design

## Overview

Add a "Sessions" tab to the TrinketedHistory window that groups arena matches into play sessions and displays aggregate stats with drill-down into individual matches.

## Session Definition

A session is a contiguous group of matches where:
- The time gap between consecutive matches (end of one to start of next) does not exceed **60 minutes**
- The **friendly team composition** (partners) does not change

Either condition triggers a new session.

## Data Approach: Computed Sessions

Sessions are computed on-the-fly from existing match data. No schema changes to `TrinketedHistoryDB`.

**Algorithm:**
1. Sort all matches chronologically (oldest first)
2. Walk matches sequentially
3. Start a new session when:
   - Time gap > 60 minutes between `endTime` of previous match and `startTime` of current match
   - Partners change (different set of friendly team names, excluding self)
4. Aggregate stats per session

**Computed session object:**
```lua
{
  games = { ... },            -- references to match records
  startTime = <number>,       -- first match startTime
  endTime = <number>,         -- last match endTime
  bracket = "3v3",            -- from the matches
  partners = {"Name", ...},   -- friendly team minus self
  wins = <number>,
  losses = <number>,
  ratingStart = <number>,     -- ratingBefore of first game
  ratingEnd = <number>,       -- ratingAfter of last game
  ratingChange = <number>,    -- net change
}
```

## UI Changes

### Tab System

Add a tab bar between the window title and the filter rows:
- **Matches** tab (default) — current view, unchanged
- **Sessions** tab — new session breakdown view

Clicking a tab shows/hides the corresponding content panels (filters, table, stats).

### Sessions Tab: Filters

Simple filter row:
- **Bracket** dropdown: All / 2v2 / 3v3 / 5v5
- **Date range** dropdown: All / Last 7 days / Last 30 days / Custom

### Sessions Tab: Table

Columns:
| # | Date | Partners | Bracket | Games | W-L | Win% | Rating | Net |
|---|------|----------|---------|-------|-----|------|--------|-----|

- **#**: Session index (newest first)
- **Date**: Start date/time of session
- **Partners**: Friendly team names (class-colored)
- **Bracket**: 2v2 / 3v3 / 5v5
- **Games**: Total match count
- **W-L**: Wins - Losses
- **Win%**: Percentage with color gradient (red → yellow → green)
- **Rating**: Start → End rating
- **Net**: Net rating change (green positive, red negative)

### Drill-down

Clicking a session row expands it inline to show individual matches within that session, using the same match row format as the Matches tab (result, teams, rating, duration, time).

## Technical Notes

- Reuses existing UI patterns from TrinketedLib (colors, fonts, row pooling)
- Session computation is fast — just sorting + gap detection on an array
- Tab state is local (not persisted), defaults to Matches
- Existing Matches tab and its filters are completely unchanged
