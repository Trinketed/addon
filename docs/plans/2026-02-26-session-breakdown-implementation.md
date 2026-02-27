# Session Breakdown Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Sessions" tab to the TrinketedHistory window that groups arena matches into play sessions (by time gap + partner changes) and displays aggregate stats with drill-down.

**Architecture:** Computed sessions derived on-the-fly from existing match timestamps and team data. A tab bar switches between the current Matches view and a new Sessions view. Session computation groups chronologically sorted matches, splitting on 60-minute gaps or partner changes. No schema changes to TrinketedHistoryDB.

**Tech Stack:** WoW Lua API, existing TrinketedLib color palette, CreateFrame UI widgets

---

### Task 1: Add Session Computation Function

**Files:**
- Modify: `TrinketedHistory/Core.lua` — insert after the `GetCompKey` function (~line 760), before `GameMatchesFilters`

**Step 1: Add the `ComputeSessions` function**

Insert the following function after `GetCompKey` (line 760) and before `GameMatchesFilters` (line 762):

```lua
---------------------------------------------------------------------------
-- Session Computation
-- Groups matches into sessions by time gap (60 min) and partner changes.
---------------------------------------------------------------------------
local SESSION_GAP_SECONDS = 3600 -- 60 minutes

local function GetPartnerKey(game)
    local playerName = UnitName("player")
    local names = {}
    for _, p in ipairs(game.friendlyTeam or {}) do
        if p.name ~= playerName then
            table.insert(names, p.name)
        end
    end
    table.sort(names)
    return table.concat(names, "/")
end

local function ComputeSessions(games, bracketFilter, daysFilter)
    -- Sort games chronologically (oldest first)
    local sorted = {}
    for i, game in ipairs(games) do
        local dominated = true
        -- Apply bracket filter
        if bracketFilter and bracketFilter ~= "All" and game.bracket ~= bracketFilter then
            dominated = false
        end
        -- Apply days filter
        if daysFilter and daysFilter > 0 then
            local cutoff = time() - (daysFilter * 86400)
            if (game.startTime or 0) < cutoff then
                dominated = false
            end
        end
        if dominated then
            table.insert(sorted, game)
        end
    end
    table.sort(sorted, function(a, b) return (a.startTime or 0) < (b.startTime or 0) end)

    if #sorted == 0 then return {} end

    local sessions = {}
    local cur = {
        games = { sorted[1] },
        startTime = sorted[1].startTime,
        endTime = sorted[1].endTime,
        bracket = sorted[1].bracket,
        partnerKey = GetPartnerKey(sorted[1]),
    }

    for i = 2, #sorted do
        local game = sorted[i]
        local gap = (game.startTime or 0) - (cur.endTime or 0)
        local partnerKey = GetPartnerKey(game)

        if gap > SESSION_GAP_SECONDS or partnerKey ~= cur.partnerKey then
            -- Finalize current session and start a new one
            table.insert(sessions, cur)
            cur = {
                games = { game },
                startTime = game.startTime,
                endTime = game.endTime,
                bracket = game.bracket,
                partnerKey = partnerKey,
            }
        else
            table.insert(cur.games, game)
            cur.endTime = game.endTime
            -- If bracket differs within session, mark as mixed
            if cur.bracket ~= game.bracket then
                cur.bracket = "Mixed"
            end
        end
    end
    table.insert(sessions, cur)

    -- Compute aggregate stats for each session
    for _, s in ipairs(sessions) do
        s.wins = 0
        s.losses = 0
        s.ratingStart = nil
        s.ratingEnd = nil
        s.ratingChange = 0
        s.partners = {}
        local partnerSeen = {}

        for j, game in ipairs(s.games) do
            if game.result == "WIN" then
                s.wins = s.wins + 1
            else
                s.losses = s.losses + 1
            end
            if game.ratingChange then
                s.ratingChange = s.ratingChange + game.ratingChange
            end
            if j == 1 and game.ratingBefore then
                s.ratingStart = game.ratingBefore
            end
            if j == #s.games and game.ratingAfter then
                s.ratingEnd = game.ratingAfter
            end

            -- Collect partner info for display
            for _, p in ipairs(game.friendlyTeam or {}) do
                if p.name ~= UnitName("player") and not partnerSeen[p.name] then
                    table.insert(s.partners, { name = p.name, class = p.class })
                    partnerSeen[p.name] = true
                end
            end
        end
    end

    return sessions
end
```

**Step 2: Verify no syntax errors**

Load the addon in-game or use `luac -p Core.lua` if available. The function is self-contained and references only `UnitName`, `time`, and `GetPartnerKey` (defined immediately above it).

**Step 3: Commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(history): add ComputeSessions function for time-gap + partner-change session grouping"
```

---

### Task 2: Add Tab Bar UI

**Files:**
- Modify: `TrinketedHistory/Core.lua` — insert tab bar creation after the title (line 928) and before the `RefreshHistory` forward declaration (line 931)

**Step 1: Create the tab bar and container frames**

Insert after line 928 (`historyFrame.title:SetText(...)`) and before line 930 (`-- Forward declare RefreshHistory`):

```lua
---------------------------------------------------------------------------
-- Tab Bar
---------------------------------------------------------------------------
local activeTab = "matches" -- "matches" or "sessions"

-- Container frame for Matches tab content (all existing UI will be parented here)
local matchesContainer = CreateFrame("Frame", nil, historyFrame)
matchesContainer:SetPoint("TOPLEFT", 0, -24)
matchesContainer:SetPoint("BOTTOMRIGHT", 0, 0)

-- Container frame for Sessions tab content
local sessionsContainer = CreateFrame("Frame", nil, historyFrame)
sessionsContainer:SetPoint("TOPLEFT", 0, -24)
sessionsContainer:SetPoint("BOTTOMRIGHT", 0, 0)
sessionsContainer:Hide()

local function CreateTab(parent, text, tabKey)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(80, 22)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()

    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.label:SetPoint("CENTER", 0, 0)
    tab.label:SetText(text)

    tab.tabKey = tabKey

    tab:SetScript("OnEnter", function(self)
        if activeTab ~= self.tabKey then
            self.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if activeTab ~= self.tabKey then
            self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        end
    end)

    return tab
end

local matchesTab = CreateTab(historyFrame, "Matches", "matches")
matchesTab:SetPoint("TOPLEFT", 12, -22)

local sessionsTab = CreateTab(historyFrame, "Sessions", "sessions")
sessionsTab:SetPoint("LEFT", matchesTab, "RIGHT", 4, 0)

-- Forward declarations for tab refresh functions
local RefreshSessions

local function UpdateTabAppearance()
    if activeTab == "matches" then
        matchesTab.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
        matchesTab.label:SetTextColor(1, 1, 1)
        sessionsTab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        sessionsTab.label:SetTextColor(0.6, 0.6, 0.6)
    else
        sessionsTab.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
        sessionsTab.label:SetTextColor(1, 1, 1)
        matchesTab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        matchesTab.label:SetTextColor(0.6, 0.6, 0.6)
    end
end

local function SwitchTab(tabKey)
    activeTab = tabKey
    UpdateTabAppearance()
    if tabKey == "matches" then
        matchesContainer:Show()
        sessionsContainer:Hide()
        RefreshHistory()
    else
        matchesContainer:Hide()
        sessionsContainer:Show()
        if RefreshSessions then RefreshSessions() end
    end
end

matchesTab:SetScript("OnClick", function() SwitchTab("matches") end)
sessionsTab:SetScript("OnClick", function() SwitchTab("sessions") end)

UpdateTabAppearance()
```

**Step 2: Reparent existing Matches UI elements to matchesContainer**

All existing filter dropdowns, column headers, scroll frame, and stats panel are currently parented to `historyFrame`. We need to adjust their anchoring so they live inside `matchesContainer`.

Change the parent of these elements by updating their anchor points. Since they use `historyFrame` as parent in CreateFrame calls and those can't be reparented easily after creation, the simplest approach is to shift existing Y offsets down by 24px to account for the tab bar, and show/hide them as a group.

Actually, since all existing elements are already children of `historyFrame`, the simplest approach is: rather than reparenting everything, just shift all existing Y offsets down by ~4px to make room for the tab bar, and add show/hide logic that hides/shows them based on the active tab. The tab bar sits at y=-22 and is 22px tall, so existing content starting at y=-28 already has adequate clearance.

Looking at the current layout:
- Filter row 1 starts at y=-28 (line 1162)
- Filter row 2 starts at y=-54 (line 1234)
- Column headers at y=-84 (line 1315)

The tab bar at y=-22 with 22px height ends at y=-44. The filters at y=-28 would overlap. We need to shift existing content down.

**Update all Y offsets for existing Matches content:**

Change `friendlyCompDD.frame:SetPoint("TOPLEFT", 12, -28)` to `("TOPLEFT", 12, -48)` (shift down by 20px).

Apply the same -20px shift to all existing content Y positions:
- Filter row 1: -28 → -48
- Filter row 2: -54 → -74
- `headerY`: -84 → -104
- Export/Reset buttons: -58 → -78

Then wrap all matches-specific elements in show/hide based on `activeTab`.

**Step 3: Commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(history): add tab bar UI with Matches and Sessions tabs"
```

---

### Task 3: Shift Existing Matches Content Down for Tab Bar

**Files:**
- Modify: `TrinketedHistory/Core.lua` — adjust Y offsets for existing elements

**Step 1: Update filter row 1 Y positions**

Line 1162: Change `-28` to `-48`
```lua
friendlyCompDD.frame:SetPoint("TOPLEFT", 12, -48)
```

Line 1185: Change `-28` to `-48`
```lua
partnerDD.frame:SetPoint("TOPLEFT", 177, -48)
```

Line 1208: Change `-28` to `-48`
```lua
enemyCompDD.frame:SetPoint("TOPLEFT", 342, -48)
```

**Step 2: Update filter row 2 Y positions**

Line 1234: Change `-54` to `-74`
```lua
enemyPlayerDD.frame:SetPoint("TOPLEFT", 12, -74)
```

Line 1256: Change `-54` to `-74`
```lua
enemyRaceDD.frame:SetPoint("TOPLEFT", 177, -74)
```

Line 1282: Change `-54` to `-74`
```lua
resultDD.frame:SetPoint("TOPLEFT", 342, -74)
```

**Step 3: Update export/reset button Y positions**

Line 1286: Change `-58` to `-78`
```lua
exportBtn:SetPoint("TOPRIGHT", -80, -78)
```

Line 1294: Change `-58` to `-78`
```lua
resetBtn:SetPoint("TOPRIGHT", -16, -78)
```

**Step 4: Update column header Y position**

Line 1315: Change `-84` to `-104`
```lua
local headerY = -104
```

**Step 5: Add visibility toggling for matches-only elements**

Add a helper after the tab system code to show/hide matches-specific widgets. The simplest approach: we'll use the SwitchTab function to control visibility of the dropdown frames and buttons directly.

After the `SwitchTab` function definition, add references to the matches-only widgets. Since the dropdowns and buttons are defined *after* the tab code, we need to make `SwitchTab` update them lazily. Update `SwitchTab`:

```lua
local matchesWidgets = {}  -- populated after widgets are created

local function SwitchTab(tabKey)
    activeTab = tabKey
    UpdateTabAppearance()
    if tabKey == "matches" then
        for _, w in ipairs(matchesWidgets) do w:Show() end
        sessionsContainer:Hide()
        RefreshHistory()
    else
        for _, w in ipairs(matchesWidgets) do w:Hide() end
        sessionsContainer:Show()
        if RefreshSessions then RefreshSessions() end
    end
end
```

Then after all the matches widgets are created (after the stats panel, around line 1503), add:

```lua
-- Register matches-specific widgets for tab visibility toggling
matchesWidgets = {
    friendlyCompDD.frame, partnerDD.frame, enemyCompDD.frame,
    enemyPlayerDD.frame, enemyRaceDD.frame, resultDD.frame,
    exportBtn, resetBtn, scrollFrame, statsSep, bestHeader, worstHeader,
}
for i = 1, NUM_STAT_ROWS do
    table.insert(matchesWidgets, bestRows[i].comp)  -- These are font strings, not frames
end
-- Actually, the stats rows are font strings/textures parented to historyFrame.
-- The simplest approach: just hide scrollFrame + stats area.
-- The header separator and column headers also need hiding.
```

**Simpler approach:** Rather than tracking every widget, hide the `scrollFrame` and stats rows when switching to sessions (which covers the main content area), and hide the filter dropdowns individually. The column headers and separator are small and can be left as-is since the sessions tab content will overlay them, OR we can wrap them.

**Even simpler approach:** Create a single container frame for all matches content. But since widgets are created as direct children of `historyFrame` via `CreateFrame`, they can be reparented:

After all matches widgets are defined (after stats panel creation ~line 1503), add:

```lua
-- Reparent matches-specific widgets into matchesContainer for tab switching
local function ReparentToMatches(widget)
    widget:SetParent(matchesContainer)
end
ReparentToMatches(friendlyCompDD.frame)
ReparentToMatches(partnerDD.frame)
ReparentToMatches(enemyCompDD.frame)
ReparentToMatches(enemyPlayerDD.frame)
ReparentToMatches(enemyRaceDD.frame)
ReparentToMatches(resultDD.frame)
ReparentToMatches(exportBtn)
ReparentToMatches(resetBtn)
ReparentToMatches(scrollFrame)
ReparentToMatches(headerSep)
ReparentToMatches(statsSep)
ReparentToMatches(bestHeader)
ReparentToMatches(worstHeader)
for i = 1, NUM_STAT_ROWS do
    ReparentToMatches(bestRows[i].comp:GetParent() ~= historyFrame and bestRows[i].comp or bestRows[i].comp)
end
```

Wait — `CreateStatRow` creates font strings and textures directly on `historyFrame`, not child frames. Font strings can't be reparented. Let me reconsider.

**Best approach: Wrap all matches content in a single parent frame from the start.** This means the `matchesContainer` frame should be created *before* any of the filter/table/stats code, and those widgets should be created as children of `matchesContainer` instead of `historyFrame`.

This is the cleanest solution but requires changing the `parent` argument in multiple `CreateFrame`/`CreateFontString` calls.

**Step 5 (revised): Change parent references from historyFrame to matchesContainer**

After inserting the tab bar code (Task 2), all subsequent widget creation should use `matchesContainer` as the parent instead of `historyFrame`. This affects:
- `CreateSearchableDropdown` calls (parent arg)
- `exportBtn`, `resetBtn` CreateFrame calls
- Column header font strings
- `headerSep`, `statsSep` textures
- `bestHeader`, `worstHeader` font strings
- `scrollFrame` CreateFrame
- `CreateStatRow` calls (parent arg)

Specific changes:

1. Line 959 `CreateSearchableDropdown(parent, ...)` — the `parent` parameter is passed in. The calls on lines 1141, 1164, 1187, 1213, 1236, 1258 all pass `historyFrame`. Change to `matchesContainer`.

2. Line 1284 `CreateFrame("Button", nil, historyFrame, ...)` for exportBtn → change to `matchesContainer`
3. Line 1292 `CreateFrame("Button", nil, historyFrame, ...)` for resetBtn → change to `matchesContainer`
4. Line 1328 `historyFrame:CreateFontString(...)` for column headers → change to `matchesContainer:CreateFontString(...)`
5. Line 1338 `historyFrame:CreateTexture(...)` for headerSep → change to `matchesContainer:CreateTexture(...)`
6. Line 1345 `CreateFrame("ScrollFrame", nil, historyFrame, ...)` → change to `matchesContainer`
7. Line 1356 `historyFrame:CreateTexture(...)` for statsSep → change to `matchesContainer:CreateTexture(...)`
8. Line 1362 `historyFrame:CreateFontString(...)` for bestHeader → change to `matchesContainer:CreateFontString(...)`
9. Line 1367 `historyFrame:CreateFontString(...)` for worstHeader → change to `matchesContainer:CreateFontString(...)`
10. Lines 1446-1447 `CreateStatRow(historyFrame, ...)` → change to `CreateStatRow(matchesContainer, ...)`

**Step 6: Commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(history): shift matches UI down for tab bar, reparent to matchesContainer"
```

---

### Task 4: Build Sessions Tab UI

**Files:**
- Modify: `TrinketedHistory/Core.lua` — add sessions tab content after the matches stats panel (after ~line 1503) and before `RefreshHistory` (line 1570)

**Step 1: Add session filters**

Insert after the stat rows creation (line 1448) and before `RefreshStats` (line 1450):

```lua
---------------------------------------------------------------------------
-- Sessions Tab Content
---------------------------------------------------------------------------
local sessionFilters = {
    bracket = "All", -- "All", "2v2", "3v3", "5v5"
    days = 0,        -- 0 = all time, 7, 30, etc.
}

-- Bracket filter dropdown
local sessionBracketDD = CreateSearchableDropdown(sessionsContainer, "TkSBracketDD", 120, {
    defaultLabel = "Bracket: All",
    getOptions = function()
        return {
            { key = "All",  text = "All",  searchText = "all",  isChecked = function() return sessionFilters.bracket == "All" end },
            { key = "2v2",  text = "2v2",  searchText = "2v2",  isChecked = function() return sessionFilters.bracket == "2v2" end },
            { key = "3v3",  text = "3v3",  searchText = "3v3",  isChecked = function() return sessionFilters.bracket == "3v3" end },
            { key = "5v5",  text = "5v5",  searchText = "5v5",  isChecked = function() return sessionFilters.bracket == "5v5" end },
        }
    end,
    onToggle = function(key)
        sessionFilters.bracket = key
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function() sessionFilters.bracket = "All"; if RefreshSessions then RefreshSessions() end end,
    getLabel = function()
        if sessionFilters.bracket == "All" then return "Bracket: All" end
        return "Bracket: " .. sessionFilters.bracket
    end,
})
sessionBracketDD.frame:SetPoint("TOPLEFT", sessionsContainer, "TOPLEFT", 12, -24)

-- Date range filter dropdown
local sessionDaysDD = CreateSearchableDropdown(sessionsContainer, "TkSDaysDD", 120, {
    defaultLabel = "Time: All",
    getOptions = function()
        return {
            { key = "0",   text = "All Time",     searchText = "all",  isChecked = function() return sessionFilters.days == 0 end },
            { key = "7",   text = "Last 7 Days",   searchText = "7",    isChecked = function() return sessionFilters.days == 7 end },
            { key = "30",  text = "Last 30 Days",  searchText = "30",   isChecked = function() return sessionFilters.days == 30 end },
            { key = "90",  text = "Last 90 Days",  searchText = "90",   isChecked = function() return sessionFilters.days == 90 end },
        }
    end,
    onToggle = function(key)
        sessionFilters.days = tonumber(key) or 0
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function() sessionFilters.days = 0; if RefreshSessions then RefreshSessions() end end,
    getLabel = function()
        if sessionFilters.days == 0 then return "Time: All" end
        return "Time: Last " .. sessionFilters.days .. "d"
    end,
})
sessionDaysDD.frame:SetPoint("TOPLEFT", sessionsContainer, "TOPLEFT", 142, -24)
```

**Step 2: Add session column headers**

```lua
-- Session column headers
local sessionHeaderY = -54
local sessionHeaders = {
    { text = "#",        x = 4,   w = 24,  justify = "RIGHT" },
    { text = "Date",     x = 32,  w = 100, justify = "LEFT" },
    { text = "Partners", x = 136, w = 160, justify = "LEFT" },
    { text = "Bracket",  x = 300, w = 50,  justify = "CENTER" },
    { text = "Games",    x = 355, w = 40,  justify = "CENTER" },
    { text = "W-L",      x = 400, w = 50,  justify = "CENTER" },
    { text = "Win%",     x = 455, w = 45,  justify = "CENTER" },
    { text = "Rating",   x = 505, w = 120, justify = "CENTER" },
    { text = "Net",      x = 630, w = 50,  justify = "CENTER" },
}
for _, h in ipairs(sessionHeaders) do
    local fs = sessionsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", h.x, sessionHeaderY)
    fs:SetWidth(h.w)
    fs:SetJustifyH(h.justify)
    fs:SetWordWrap(false)
    fs:SetText("|cff888888" .. h.text .. "|r")
end

local sessionHeaderSep = sessionsContainer:CreateTexture(nil, "ARTWORK")
sessionHeaderSep:SetHeight(1)
sessionHeaderSep:SetPoint("TOPLEFT", sessionsContainer, "TOPLEFT", 4, sessionHeaderY - 12)
sessionHeaderSep:SetPoint("TOPRIGHT", sessionsContainer, "TOPRIGHT", -16, sessionHeaderY - 12)
sessionHeaderSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)
```

**Step 3: Add sessions scroll frame and row pool**

```lua
-- Sessions scroll frame
local sessionScrollFrame = CreateFrame("ScrollFrame", nil, sessionsContainer, "UIPanelScrollFrameTemplate")
sessionScrollFrame:SetPoint("TOPLEFT", sessionsContainer, "TOPLEFT", 10, sessionHeaderY - 14)
sessionScrollFrame:SetPoint("BOTTOMRIGHT", sessionsContainer, "BOTTOMRIGHT", -30, 10)

local sessionContent = CreateFrame("Frame", nil, sessionScrollFrame)
sessionContent:SetSize(740, 1)
sessionScrollFrame:SetScrollChild(sessionContent)

local SESSION_ROW_HEIGHT = 28
local MATCH_ROW_HEIGHT = 26
local sessionRowPool = {}
local expandedSession = nil -- index of currently expanded session, or nil
```

**Step 4: Add the RefreshSessions function**

```lua
function RefreshSessions()
    -- Recycle existing rows
    for _, row in ipairs(sessionRowPool) do
        row:Hide()
    end

    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}
    local bracketFilter = sessionFilters.bracket ~= "All" and sessionFilters.bracket or nil
    local sessions = ComputeSessions(allGames, bracketFilter, sessionFilters.days)

    -- Display newest sessions first
    local totalHeight = 0
    local rowIdx = 0

    for displayIdx = #sessions, 1, -1 do
        local s = sessions[displayIdx]
        rowIdx = rowIdx + 1

        local row = sessionRowPool[rowIdx]
        if not row then
            row = CreateFrame("Button", nil, sessionContent)
            row:SetSize(740, SESSION_ROW_HEIGHT)
            sessionRowPool[rowIdx] = row

            row.index = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.index:SetPoint("LEFT", 4, 0)
            row.index:SetWidth(24)
            row.index:SetJustifyH("RIGHT")

            row.dateStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.dateStr:SetPoint("LEFT", 32, 0)
            row.dateStr:SetWidth(100)
            row.dateStr:SetJustifyH("LEFT")
            row.dateStr:SetWordWrap(false)

            row.partners = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.partners:SetPoint("LEFT", 136, 0)
            row.partners:SetWidth(160)
            row.partners:SetJustifyH("LEFT")
            row.partners:SetWordWrap(false)

            row.bracket = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.bracket:SetPoint("LEFT", 300, 0)
            row.bracket:SetWidth(50)
            row.bracket:SetJustifyH("CENTER")

            row.games = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.games:SetPoint("LEFT", 355, 0)
            row.games:SetWidth(40)
            row.games:SetJustifyH("CENTER")

            row.wl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.wl:SetPoint("LEFT", 400, 0)
            row.wl:SetWidth(50)
            row.wl:SetJustifyH("CENTER")

            row.winPct = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.winPct:SetPoint("LEFT", 455, 0)
            row.winPct:SetWidth(45)
            row.winPct:SetJustifyH("CENTER")

            row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.rating:SetPoint("LEFT", 505, 0)
            row.rating:SetWidth(120)
            row.rating:SetJustifyH("CENTER")

            row.net = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.net:SetPoint("LEFT", 630, 0)
            row.net:SetWidth(50)
            row.net:SetJustifyH("CENTER")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.expandIndicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.expandIndicator:SetPoint("RIGHT", -4, 0)
            row.expandIndicator:SetWidth(16)
        end

        row:SetPoint("TOPLEFT", 0, -totalHeight)

        -- Alternating row color
        local sessionNum = #sessions - displayIdx + 1
        if sessionNum % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.05)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.index:SetText("#" .. sessionNum)
        row.index:SetTextColor(0.5, 0.5, 0.5)

        row.dateStr:SetText(s.startTime and date("%m/%d %H:%M", s.startTime) or "?")
        row.dateStr:SetTextColor(0.8, 0.8, 0.8)

        -- Partners (class-colored)
        local partnerParts = {}
        for _, p in ipairs(s.partners) do
            local color = CLASS_COLORS[p.class] or "ffffffff"
            table.insert(partnerParts, "|c" .. color .. p.name .. "|r")
        end
        row.partners:SetText(#partnerParts > 0 and table.concat(partnerParts, ", ") or "Solo")

        row.bracket:SetText(s.bracket or "?")
        row.bracket:SetTextColor(0.8, 0.8, 0.8)

        row.games:SetText(tostring(#s.games))
        row.games:SetTextColor(0.8, 0.8, 0.8)

        row.wl:SetText("|cff00ff00" .. s.wins .. "|r-|cffff0000" .. s.losses .. "|r")

        local total = s.wins + s.losses
        local pct = total > 0 and (s.wins / total * 100) or 0
        -- Color gradient: red → yellow → green
        local pr, pg
        if pct <= 50 then
            pr = 1
            pg = pct / 50
        else
            pr = 1 - (pct - 50) / 50
            pg = 1
        end
        row.winPct:SetText(string.format("%.0f%%", pct))
        row.winPct:SetTextColor(pr, pg, 0)

        -- Rating
        if s.ratingStart and s.ratingEnd then
            row.rating:SetText(s.ratingStart .. " → " .. s.ratingEnd)
        elseif s.ratingStart then
            row.rating:SetText(tostring(s.ratingStart))
        else
            row.rating:SetText("|cff555555—|r")
        end
        row.rating:SetTextColor(0.8, 0.8, 0.8)

        -- Net rating change
        if s.ratingChange and s.ratingChange ~= 0 then
            local sign = s.ratingChange >= 0 and "+" or ""
            local color = s.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
            row.net:SetText(color .. sign .. s.ratingChange .. "|r")
        else
            row.net:SetText("|cff555555—|r")
        end

        -- Expand/collapse indicator
        local isExpanded = (expandedSession == displayIdx)
        row.expandIndicator:SetText(isExpanded and "▼" or "▶")
        row.expandIndicator:SetTextColor(0.5, 0.5, 0.5)

        -- Click handler for drill-down
        local capturedIdx = displayIdx
        row:SetScript("OnClick", function()
            if expandedSession == capturedIdx then
                expandedSession = nil
            else
                expandedSession = capturedIdx
            end
            RefreshSessions()
        end)

        row:Show()
        totalHeight = totalHeight + SESSION_ROW_HEIGHT

        -- If this session is expanded, show individual matches
        if isExpanded then
            for matchIdx, game in ipairs(s.games) do
                rowIdx = rowIdx + 1
                local mRow = sessionRowPool[rowIdx]
                if not mRow then
                    mRow = CreateFrame("Frame", nil, sessionContent)
                    mRow:SetSize(740, MATCH_ROW_HEIGHT)
                    sessionRowPool[rowIdx] = mRow

                    mRow.result = mRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mRow.result:SetPoint("LEFT", 40, 0)
                    mRow.result:SetWidth(36)

                    mRow.friendly = mRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mRow.friendly:SetPoint("LEFT", 80, 0)
                    mRow.friendly:SetWidth(180)
                    mRow.friendly:SetJustifyH("LEFT")
                    mRow.friendly:SetWordWrap(false)

                    mRow.vs = mRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mRow.vs:SetPoint("LEFT", 264, 0)
                    mRow.vs:SetWidth(16)
                    mRow.vs:SetJustifyH("CENTER")
                    mRow.vs:SetTextColor(0.4, 0.4, 0.4)

                    mRow.enemy = mRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mRow.enemy:SetPoint("LEFT", 284, 0)
                    mRow.enemy:SetWidth(180)
                    mRow.enemy:SetJustifyH("LEFT")
                    mRow.enemy:SetWordWrap(false)

                    mRow.ratingStr = mRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mRow.ratingStr:SetPoint("LEFT", 470, 0)
                    mRow.ratingStr:SetWidth(80)
                    mRow.ratingStr:SetJustifyH("CENTER")

                    mRow.duration = mRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mRow.duration:SetPoint("LEFT", 555, 0)
                    mRow.duration:SetWidth(45)
                    mRow.duration:SetJustifyH("CENTER")

                    mRow.timeStr = mRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mRow.timeStr:SetPoint("LEFT", 605, 0)
                    mRow.timeStr:SetWidth(60)
                    mRow.timeStr:SetJustifyH("RIGHT")

                    mRow.bg = mRow:CreateTexture(nil, "BACKGROUND")
                    mRow.bg:SetAllPoints()
                end

                mRow:SetPoint("TOPLEFT", 0, -totalHeight)

                -- Indented background for drill-down rows
                mRow.bg:SetColorTexture(0.08, 0.08, 0.12, 0.8)

                if game.result == "WIN" then
                    mRow.result:SetText("|cff00ff00W|r")
                else
                    mRow.result:SetText("|cffff0000L|r")
                end

                -- Friendly team — compact format (class-colored names only)
                mRow.friendly:SetText(FormatTeamClasses(game.friendlyTeam) or "—")

                mRow.vs:SetText("vs")

                -- Enemy team
                local enemyStr = FormatTeamClasses(game.enemyTeam)
                if not enemyStr and game.enemyComp then
                    local parts = {}
                    for _, class in ipairs(game.enemyComp) do
                        table.insert(parts, ColorClass(class))
                    end
                    enemyStr = #parts > 0 and table.concat(parts, " ") or "?"
                end
                mRow.enemy:SetText(enemyStr or "?")

                -- Rating change
                if game.ratingChange then
                    local sign = game.ratingChange >= 0 and "+" or ""
                    local color = game.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
                    mRow.ratingStr:SetText(color .. sign .. game.ratingChange .. "|r")
                else
                    mRow.ratingStr:SetText("|cff555555—|r")
                end

                local dur = (game.startTime and game.endTime) and (game.endTime - game.startTime) or nil
                mRow.duration:SetText(FormatDuration(dur))
                mRow.duration:SetTextColor(0.7, 0.7, 0.7)

                mRow.timeStr:SetText(FormatTime(game.startTime))
                mRow.timeStr:SetTextColor(0.5, 0.5, 0.5)

                mRow:Show()
                totalHeight = totalHeight + MATCH_ROW_HEIGHT
            end
        end
    end

    sessionContent:SetHeight(math.max(totalHeight, 1))

    -- Update title with session count
    local sessionCount = #sessions
    local totalGames = 0
    local totalWins = 0
    local totalLosses = 0
    local netRating = 0
    local hasRating = false
    for _, s in ipairs(sessions) do
        totalGames = totalGames + #s.games
        totalWins = totalWins + s.wins
        totalLosses = totalLosses + s.losses
        if s.ratingChange and s.ratingChange ~= 0 then
            netRating = netRating + s.ratingChange
            hasRating = true
        end
    end
    local ratingStr = ""
    if hasRating then
        local sign = netRating >= 0 and "+" or ""
        local color = netRating >= 0 and "|cff00ff00" or "|cffff0000"
        ratingStr = " | Net: " .. color .. sign .. netRating .. "|r"
    end
    historyFrame.title:SetText("Trinketed — " .. sessionCount .. " sessions, " .. totalGames .. " games (" ..
        "|cff00ff00" .. totalWins .. "W|r / |cffff0000" .. totalLosses .. "L|r)" .. ratingStr)
end
```

**Step 5: Commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(history): add Sessions tab with computed session list and drill-down"
```

---

### Task 5: Update ToggleHistory and Refresh Calls

**Files:**
- Modify: `TrinketedHistory/Core.lua`

**Step 1: Update ToggleHistory to respect active tab**

Change the `ToggleHistory` function (~line 1739):

```lua
local function ToggleHistory()
    if historyFrame:IsShown() then
        historyFrame:Hide()
    else
        if activeTab == "sessions" then
            RefreshSessions()
        else
            RefreshHistory()
        end
        historyFrame:Show()
    end
end
```

**Step 2: Update inline RefreshHistory calls to be tab-aware**

The existing code has two places that call `RefreshHistory()` when the frame is visible (lines 2130 and 2396). Update these to call the correct refresh based on the active tab:

```lua
-- Replace: if historyFrame and historyFrame:IsShown() then RefreshHistory() end
-- With:
if historyFrame and historyFrame:IsShown() then
    if activeTab == "sessions" then
        RefreshSessions()
    else
        RefreshHistory()
    end
end
```

**Step 3: Commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(history): update ToggleHistory and refresh calls for tab awareness"
```

---

### Task 6: Manual Testing and Polish

**Step 1: Load addon in WoW and verify**

1. Open history window — should see tab bar with "Matches" and "Sessions"
2. Matches tab should look exactly as before (just shifted down slightly)
3. Click Sessions tab — should show session list grouped by time gap and partners
4. Click a session row — should expand to show individual matches
5. Click again — should collapse
6. Test bracket filter — should filter sessions
7. Test days filter — should filter by date
8. Switch back to Matches tab — should work as before

**Step 2: Edge cases to verify**

- Empty history (no games) — both tabs should show empty gracefully
- Single game — should show as one session
- Games with no rating data — should show "—" for rating columns
- Games with no friendly team data — partners should show "Solo"

**Step 3: Final commit**

```bash
git add TrinketedHistory/Core.lua
git commit -m "feat(history): session breakdown tab - complete feature"
```
