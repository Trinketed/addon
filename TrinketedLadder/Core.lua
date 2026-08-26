---------------------------------------------------------------------------
-- TrinketedLadder — arena ladder & activity feed inside the options panel.
--
-- Renders TrinketedData.Ladder, a data-only addon written by the Trinketed
-- desktop app (contract: web repo docs/superpowers/specs/
-- 2026-08-26-companion-addon-datafile-contract.md, schema v1). WoW only
-- re-reads addon files at login//reload, so the pane is explicit about
-- data age and degrades cleanly when the data addon is absent or stale.
--
-- Format/feel deliberately mirrors TrinketedHistory: content embedded in
-- the options panel (Ladder sidebar tab), CreateTabBar sections, BODY-10
-- column headers over a divider, pooled 28px rows. Everything hangs off
-- one namespace table (Lua's 200-locals budget; CS pattern).
---------------------------------------------------------------------------
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local L = {
    SCHEMA = 1,
    STALE_SEC = 86400,
    ROW_H = 28,
    ROW_W = 740,
    bracket = "3v3",
    rows = {},          -- pooled ladder/self row frames (one flat pool)
    activityRows = {},
    selfKeys = nil,     -- set of "name-realmslug" for own-row highlight
}

L.BRACKETS = { "2v2", "3v3", "5v5" }

-- Own copy (module-local, TrinketedCD precedent) — keys are the class
-- tokens the data file carries.
L.CLASS_COLORS = {
    WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473",
    ROGUE = "fff569", PRIEST = "ffffff", SHAMAN = "0070de",
    MAGE = "69ccf0", WARLOCK = "9482c9", DRUID = "ff7d0a",
}

---------------------------------------------------------------------------
-- Data access & freshness
---------------------------------------------------------------------------

function L.GetData()
    return TrinketedData and TrinketedData.Ladder or nil
end

-- "missing" | "version" | "stale" | "ok"
function L.State()
    local data = L.GetData()
    if not data then return "missing" end
    if data.version ~= L.SCHEMA then return "version" end
    if data.generatedAt and (time() - data.generatedAt) > L.STALE_SEC then
        return "stale"
    end
    return "ok"
end

function L.AgeText(epoch)
    if not epoch then return "?" end
    local age = math.max(0, time() - epoch)
    if age < 60 then return "just now" end
    if age < 3600 then return math.floor(age / 60) .. "m ago" end
    if age < 86400 then return math.floor(age / 3600) .. "h ago" end
    return math.floor(age / 86400) .. "d ago"
end

local function slugKey(value)
    return (tostring(value or ""):lower():gsub("[^%w]", ""))
end

-- Own-row keys: the companion's searched characters plus whoever is
-- logged in right now (covers a fresh alt before the companion sees it).
function L.SelfKeys()
    if L.selfKeys then return L.selfKeys end
    local keys = {}
    local data = L.GetData()
    if data and data.player and data.player.characters then
        for _, char in ipairs(data.player.characters) do
            keys[slugKey(char.name) .. "-" .. slugKey(char.realm)] = true
        end
    end
    local me = UnitName("player")
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    if me and realm then
        keys[slugKey(me) .. "-" .. slugKey(realm)] = true
    end
    L.selfKeys = keys
    return keys
end

function L.IsSelf(entry)
    return L.SelfKeys()[slugKey(entry.name) .. "-" .. slugKey(entry.realm)] or false
end

function L.NameText(entry)
    local hex = entry.class and L.CLASS_COLORS[entry.class]
    local name = hex and ("|cff" .. hex .. entry.name .. "|r") or entry.name
    local realm = tostring(entry.realm or "")
    realm = realm:gsub("^%l", string.upper)
    return name .. "|cff5c5f66-" .. realm .. "|r"
end

---------------------------------------------------------------------------
-- Reload nudge (never in combat, never while queued — the reload would
-- drop the queue; same guards as TrinketedHistory's sync nudge)
---------------------------------------------------------------------------

function L.ReloadBlockedReason()
    if InCombatLockdown() then return "in combat" end
    local max = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 0
    for i = 1, max do
        local status = GetBattlefieldStatus(i)
        if status == "queued" or status == "confirm" then return "in queue" end
    end
    return nil
end

---------------------------------------------------------------------------
-- Content (embedded in the options panel, TrinketedHistory pattern:
-- parked on UIParent, reparented into the sub-addon content frame)
---------------------------------------------------------------------------

local ladderContent = CreateFrame("Frame", "TrinketedLadderContent", UIParent)
ladderContent:SetSize(1, 1)
ladderContent:Hide()

local tabContainer = CreateFrame("Frame", nil, ladderContent)
tabContainer:SetAllPoints()

-- No onChange work beyond repaint: the data only changes at /reload, so
-- tab clicks are show/hide + a cheap repopulate of the selected tab.
L.tabBar = lib:CreateTabBar(tabContainer, {
    { "ladder", "Ladder" },
    { "activity", "Activity" },
}, {
    height = 26,
    tabWidth = 80,
    onChange = function(key)
        if key == "ladder" then L.RefreshLadder() else L.RefreshActivity() end
    end,
})

local ladderTab = L.tabBar.contents.ladder
local activityTab = L.tabBar.contents.activity

-- ── Ladder tab: bracket chips row (CS grammar) ──
L.chips = {}
for i, key in ipairs(L.BRACKETS) do
    local chip = CreateFrame("Button", nil, ladderTab)
    chip:SetSize(54, 24)
    chip:SetPoint("TOPLEFT", 10 + (i - 1) * 60, -10)
    chip.bg = chip:CreateTexture(nil, "BACKGROUND")
    chip.bg:SetAllPoints()
    chip.border = CreateFrame("Frame", nil, chip, "BackdropTemplate")
    chip.border:SetAllPoints()
    chip.border:SetBackdrop({ edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    chip.label = chip:CreateFontString(nil, "OVERLAY")
    chip.label:SetFont(lib.FONT_BODY, 10, "")
    chip.label:SetPoint("CENTER")
    chip.label:SetText(key)
    chip:SetScript("OnClick", function()
        L.bracket = key
        L.RefreshLadder()
    end)
    L.chips[i] = { frame = chip, key = key }
end

L.staleBanner = ladderTab:CreateFontString(nil, "OVERLAY")
L.staleBanner:SetFont(lib.FONT_BODY, 10, "")
L.staleBanner:SetPoint("TOPRIGHT", -16, -16)
L.staleBanner:SetJustifyH("RIGHT")
L.staleBanner:SetTextColor(0.95, 0.7, 0.2)

-- ── Ladder tab: column headers (History grammar: BODY 10, textDim,
-- divider underneath) ──
local LADDER_HEADER_Y = -46
L.ladderHeaders = {
    { text = "Rank",   x = 4,   w = 40,  justify = "RIGHT" },
    { text = "Player", x = 56,  w = 240, justify = "LEFT" },
    { text = "Spec",   x = 300, w = 110, justify = "LEFT" },
    { text = "Rating", x = 414, w = 60,  justify = "CENTER" },
    { text = "W-L",    x = 480, w = 90,  justify = "CENTER" },
    { text = "24h",    x = 576, w = 56,  justify = "CENTER" },
}
for _, h in ipairs(L.ladderHeaders) do
    local fs = ladderTab:CreateFontString(nil, "OVERLAY")
    fs:SetFont(lib.FONT_BODY, 10, "")
    fs:SetPoint("TOPLEFT", h.x, LADDER_HEADER_Y)
    fs:SetWidth(h.w)
    fs:SetJustifyH(h.justify)
    fs:SetWordWrap(false)
    fs:SetText(h.text)
    fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
end

local ladderHeaderSep = ladderTab:CreateTexture(nil, "ARTWORK")
ladderHeaderSep:SetHeight(1)
ladderHeaderSep:SetPoint("TOPLEFT", 4, LADDER_HEADER_Y - 12)
ladderHeaderSep:SetPoint("TOPRIGHT", -16, LADDER_HEADER_Y - 12)
ladderHeaderSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

L.scroll = CreateFrame("ScrollFrame", nil, ladderTab, "UIPanelScrollFrameTemplate")
L.scroll:SetPoint("TOPLEFT", 10, LADDER_HEADER_Y - 14)
L.scroll:SetPoint("BOTTOMRIGHT", -30, 26)
L.listChild = CreateFrame("Frame", nil, L.scroll)
L.listChild:SetSize(L.ROW_W, 1)
L.scroll:SetScrollChild(L.listChild)

-- ── Activity tab ──
L.activityHead = activityTab:CreateFontString(nil, "OVERLAY")
L.activityHead:SetFont(lib.FONT_BODY, 10, "")
L.activityHead:SetPoint("TOPLEFT", 10, -14)
L.activityHead:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

local ACTIVITY_HEADER_Y = -40
L.activityHeaders = {
    { text = "When",    x = 4,   w = 56,  justify = "LEFT" },
    { text = "Player",  x = 68,  w = 240, justify = "LEFT" },
    { text = "Bracket", x = 312, w = 50,  justify = "CENTER" },
    { text = "Rating",  x = 370, w = 60,  justify = "CENTER" },
    { text = "Change",  x = 438, w = 60,  justify = "CENTER" },
    { text = "Games",   x = 506, w = 90,  justify = "CENTER" },
}
for _, h in ipairs(L.activityHeaders) do
    local fs = activityTab:CreateFontString(nil, "OVERLAY")
    fs:SetFont(lib.FONT_BODY, 10, "")
    fs:SetPoint("TOPLEFT", h.x, ACTIVITY_HEADER_Y)
    fs:SetWidth(h.w)
    fs:SetJustifyH(h.justify)
    fs:SetWordWrap(false)
    fs:SetText(h.text)
    fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
end

local activityHeaderSep = activityTab:CreateTexture(nil, "ARTWORK")
activityHeaderSep:SetHeight(1)
activityHeaderSep:SetPoint("TOPLEFT", 4, ACTIVITY_HEADER_Y - 12)
activityHeaderSep:SetPoint("TOPRIGHT", -16, ACTIVITY_HEADER_Y - 12)
activityHeaderSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

L.activityScroll = CreateFrame("ScrollFrame", nil, activityTab, "UIPanelScrollFrameTemplate")
L.activityScroll:SetPoint("TOPLEFT", 10, ACTIVITY_HEADER_Y - 14)
L.activityScroll:SetPoint("BOTTOMRIGHT", -30, 26)
L.activityChild = CreateFrame("Frame", nil, L.activityScroll)
L.activityChild:SetSize(L.ROW_W, 1)
L.activityScroll:SetScrollChild(L.activityChild)

-- ── Freshness footer (shared, bottom of the pane) ──
L.footerText = ladderContent:CreateFontString(nil, "OVERLAY")
L.footerText:SetFont(lib.FONT_BODY, 9, "")
L.footerText:SetPoint("BOTTOMLEFT", 14, 8)
L.footerText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

L.reloadBtn = CreateFrame("Button", nil, ladderContent)
L.reloadBtn:SetSize(110, 18)
L.reloadBtn:SetPoint("BOTTOMRIGHT", -16, 5)
L.reloadBtn.label = L.reloadBtn:CreateFontString(nil, "OVERLAY")
L.reloadBtn.label:SetFont(lib.FONT_BODY, 9, "")
L.reloadBtn.label:SetPoint("RIGHT")
L.reloadBtn.label:SetText("/reload to refresh")
L.reloadBtn.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
L.reloadBtn:SetScript("OnClick", function()
    local blocked = L.ReloadBlockedReason()
    if blocked then
        print("|cff00ccffTrinketed:|r not reloading while " .. blocked .. ".")
        return
    end
    C_UI.Reload()
end)
L.reloadBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local blocked = L.ReloadBlockedReason()
    if blocked then
        GameTooltip:AddLine("Blocked: " .. blocked, 0.9, 0.4, 0.3)
    else
        GameTooltip:AddLine("Reload the UI to pick up fresh ladder data", 1, 1, 1)
    end
    GameTooltip:Show()
end)
L.reloadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ── Degraded-state panel (replaces the tab container) ──
L.statePanel = CreateFrame("Frame", nil, ladderContent)
L.statePanel:SetAllPoints()
L.statePanel:Hide()
L.stateTitle = L.statePanel:CreateFontString(nil, "OVERLAY")
L.stateTitle:SetFont(lib.FONT_DISPLAY, 13, "")
L.stateTitle:SetPoint("TOP", 0, -130)
L.stateTitle:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
L.stateBody = L.statePanel:CreateFontString(nil, "OVERLAY")
L.stateBody:SetFont(lib.FONT_BODY, 11, "")
L.stateBody:SetPoint("TOP", 0, -156)
L.stateBody:SetWidth(440)
L.stateBody:SetSpacing(3)
L.stateBody:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
-- Copyable URL (addons can't open browsers — the standard editbox trick).
L.stateUrl = CreateFrame("EditBox", nil, L.statePanel)
L.stateUrl:SetSize(260, 20)
L.stateUrl:SetPoint("TOP", 0, -214)
L.stateUrl:SetFont(lib.FONT_MONO, 11, "")
L.stateUrl:SetJustifyH("CENTER")
L.stateUrl:SetAutoFocus(false)
L.stateUrl:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
L.stateUrl:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
L.stateUrl:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= "https://trinketed.com" then
        self:SetText("https://trinketed.com")
    end
end)
L.stateUrl:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
L.stateUrl:SetText("https://trinketed.com")

---------------------------------------------------------------------------
-- Rows (pooled, History table grammar: BODY 10 columns at fixed offsets)
---------------------------------------------------------------------------

function L.MakeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(L.ROW_W, L.ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    local function fs(x, w, justify)
        local s = row:CreateFontString(nil, "OVERLAY")
        s:SetFont(lib.FONT_BODY, 10, "")
        s:SetPoint("LEFT", x, 0)
        s:SetWidth(w)
        s:SetJustifyH(justify or "LEFT")
        s:SetWordWrap(false)
        return s
    end
    -- Column geometry mirrors L.ladderHeaders / L.activityHeaders.
    row.c1 = fs(4, 40, "RIGHT")
    row.c2 = fs(56, 240, "LEFT")
    row.c3 = fs(300, 110, "LEFT")
    row.c4 = fs(414, 60, "CENTER")
    row.c5 = fs(480, 90, "CENTER")
    row.c6 = fs(576, 56, "CENTER")
    return row
end

local function deltaText(value, zeroLabel)
    if value == nil then return "|cff5c5f66" .. zeroLabel .. "|r" end
    if value > 0 then return "|cff4ade80+" .. value .. "|r" end
    if value < 0 then return "|cffe93939" .. value .. "|r" end
    return "|cff5c5f660|r"
end

function L.PopulateRow(row, entry)
    if entry.divider then
        row.c1:SetText("")
        row.c3:SetText("")
        row.c4:SetText("")
        row.c5:SetText("")
        row.c6:SetText("")
        row.c2:SetText(entry.label)
        row.c2:SetTextColor(entry.color[1], entry.color[2], entry.color[3])
        row.bg:SetColorTexture(entry.color[1], entry.color[2], entry.color[3], 0.06)
        return
    end
    local own = L.IsSelf(entry)
    row.c1:SetText(entry.rank and tostring(entry.rank) or "—")
    row.c1:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    row.c2:SetText(L.NameText(entry))
    row.c2:SetTextColor(1, 1, 1)
    lib:FitText(row.c2, 236)
    row.c3:SetText(entry.spec or "")
    row.c3:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    row.c4:SetText(tostring(entry.rating or ""))
    if own then
        row.c4:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    else
        row.c4:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    end
    row.c5:SetText(string.format(
        "|cff4ade80%d|r|cff5c5f66-|r|cffe93939%d|r", entry.wins or 0, entry.losses or 0))
    row.c6:SetText(deltaText(entry.delta24h, "—"))
    if own then
        row.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.08)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

function L.PopulateActivityRow(row, item)
    row.c1:SetText(item.lastSeenAt and L.AgeText(item.lastSeenAt):gsub(" ago", "") or "")
    row.c1:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    row.c1:SetJustifyH("LEFT")
    row.c2:SetText(L.NameText(item))
    lib:FitText(row.c2, 236)
    row.c3:SetText(item.bracket or "")
    row.c3:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    row.c4:SetText(tostring(item.rating or ""))
    row.c4:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    row.c5:SetText(deltaText(item.ratingChange, "new"))
    row.c6:SetText(string.format(
        "|cff4ade80+%d|r|cff5c5f66/|r|cffe93939-%d|r", item.wins or 0, item.losses or 0))
    row.bg:SetColorTexture(0, 0, 0, 0)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function L.UpdateChips()
    for _, chip in ipairs(L.chips) do
        if chip.key == L.bracket then
            chip.frame.bg:SetColorTexture(C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.35)
            chip.frame.border:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
            chip.frame.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        else
            chip.frame.bg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)
            chip.frame.border:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
            chip.frame.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end
    end
end

-- The display list interleaves cutoff dividers at the first entry whose
-- rank passes each cutoff's rank; cutoffs beyond the listed entries land
-- in the footer instead (the data still names their rating).
function L.LadderDisplayList(board)
    local items = {}
    local cutoffs = board.cutoffs or {}
    local nextCut = 1
    for _, entry in ipairs(board.entries or {}) do
        while cutoffs[nextCut] and cutoffs[nextCut].rank
            and entry.rank and entry.rank > cutoffs[nextCut].rank do
            local cut = cutoffs[nextCut]
            items[#items + 1] = {
                divider = true,
                label = string.upper(cut.title or "") .. " CUTOFF · " .. (cut.rating or ""),
                color = nextCut == 1 and C.accent or C.textDim,
            }
            nextCut = nextCut + 1
        end
        items[#items + 1] = entry
    end
    if board.self and #board.self > 0 then
        items[#items + 1] = { divider = true, label = "YOU", color = C.accent }
        for _, entry in ipairs(board.self) do
            items[#items + 1] = entry
        end
    end
    return items
end

function L.RefreshLadder()
    local data = L.GetData()
    if not data then return end
    L.selfKeys = nil
    L.UpdateChips()
    local board = (data.brackets or {})[L.bracket] or {}
    local items = L.LadderDisplayList(board)
    for i, item in ipairs(items) do
        local row = L.rows[i]
        if not row then
            row = L.MakeRow(L.listChild)
            L.rows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -(i - 1) * L.ROW_H)
        row:Show()
        L.PopulateRow(row, item)
    end
    for i = #items + 1, #L.rows do
        L.rows[i]:Hide()
    end
    L.listChild:SetHeight(math.max(1, #items * L.ROW_H))
    L.scroll:SetVerticalScroll(0)

    -- Cutoffs whose rank exceeds the listed entries: footer summary.
    local beyond = {}
    for _, cut in ipairs(board.cutoffs or {}) do
        local last = board.entries and board.entries[#board.entries]
        if not cut.rank or (last and last.rank and cut.rank > last.rank) then
            beyond[#beyond + 1] = (cut.title or "") .. " " .. (cut.rating or "")
        end
    end
    L.cutoffNote = #beyond > 0 and table.concat(beyond, " · ") or nil
    L.UpdateFooter(data)
end

function L.RefreshActivity()
    local data = L.GetData()
    if not data then return end
    local activity = data.activity or {}
    local items = activity.items or {}
    if #items == 0 then
        L.activityHead:SetText(activity.lastActivityAt
            and ("No ladder activity in the last " .. (activity.hours or 6)
                .. "h — last seen " .. L.AgeText(activity.lastActivityAt))
            or "No recent ladder activity.")
    else
        local total = activity.totalActive or #items
        L.activityHead:SetText(string.format(
            "Rating changes · last %dh · showing %d of %d active players · games are that window only",
            activity.hours or 6, #items, total))
    end
    for i, item in ipairs(items) do
        local row = L.activityRows[i]
        if not row then
            row = L.MakeRow(L.activityChild)
            L.activityRows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -(i - 1) * L.ROW_H)
        row:Show()
        L.PopulateActivityRow(row, item)
    end
    for i = #items + 1, #L.activityRows do
        L.activityRows[i]:Hide()
    end
    L.activityChild:SetHeight(math.max(1, #items * L.ROW_H))
    L.activityScroll:SetVerticalScroll(0)
    L.UpdateFooter(data)
end

function L.UpdateFooter(data)
    local bits = {}
    bits[#bits + 1] = "Ladder as of " .. L.AgeText(data.ladderUpdatedAt or data.generatedAt)
    bits[#bits + 1] = "written " .. L.AgeText(data.generatedAt)
    if data.region then bits[#bits + 1] = string.upper(data.region) end
    if L.cutoffNote then bits[#bits + 1] = L.cutoffNote end
    L.footerText:SetText(table.concat(bits, " · "))
end

function L.Refresh()
    local state = L.State()

    if state == "missing" or state == "version" then
        tabContainer:Hide()
        L.footerText:SetText("")
        L.reloadBtn:Hide()
        L.statePanel:Show()
        if state == "missing" then
            L.stateTitle:SetText("Ladder data comes from the Trinketed desktop app")
            L.stateBody:SetText("Install and run the free desktop app — it writes the ladder"
                .. " into a TrinketedData folder next to your addons."
                .. "\n/reload after it runs.")
            L.stateUrl:Show()
        else
            L.stateTitle:SetText("Update your Trinketed addons")
            L.stateBody:SetText("The desktop app is writing a newer ladder data format than"
                .. " this addon understands.")
            L.stateUrl:Hide()
        end
        return
    end

    L.statePanel:Hide()
    tabContainer:Show()
    L.reloadBtn:Show()
    L.staleBanner:SetText(state == "stale"
        and "Data is over a day old — is the desktop app running?" or "")

    if L.tabBar:GetActive() == "activity" then
        L.RefreshActivity()
    else
        L.RefreshLadder()
    end
end

---------------------------------------------------------------------------
-- Entry points (History pattern: the pane IS the ladder UI)
---------------------------------------------------------------------------

function L.Toggle()
    if lib:IsOptionsPanelShown() then
        lib:HideOptionsPanel()
    else
        lib:ShowOptionsPanel("Ladder")
    end
end

lib:RegisterSubCommand("ladder", L.Toggle)

lib:RegisterSubAddon("Ladder", {
    order = 3,
    desc = "In-game arena ladder and activity feed, fed by the Trinketed desktop app.",
    OnSelect = function(contentFrame)
        -- Embed the ladder content directly in the options panel
        -- (TrinketedHistory's embedding pattern).
        ladderContent:SetParent(contentFrame)
        ladderContent:ClearAllPoints()
        ladderContent:SetAllPoints(contentFrame)

        -- Refresh whenever the pane is shown (tab selected or panel
        -- re-opened) — the data may have changed across a /reload.
        contentFrame:HookScript("OnShow", function()
            ladderContent:Show()
            L.Refresh()
        end)
    end,
})

L.tabBar:SelectTab("ladder")
