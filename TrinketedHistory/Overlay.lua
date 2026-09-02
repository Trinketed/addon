-------------------------------------------------------------------------------
-- TrinketedHistory: Overlay.lua
--
-- Stream overlay showing recent rated arena results and session stats,
-- reading the same TrinketedHistoryDB.games this addon records. Formerly the
-- standalone TrinketedOverlay addon (v0.2), rolled in so rows can open the
-- game's replay directly. Visual spec: design_handoff_stream_overlay D1-D12.
--
-- Off by default — enable from the History settings tab, /tko, or
-- /trinketed overlay. Settings live in TrinketedHistoryDB.overlay.
-------------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C
local FONT_D, FONT_M, FONT_B = lib.FONT_DISPLAY, lib.FONT_MONO, lib.FONT_BODY
local A = lib.OVERLAY_ALPHA or 0.92

local PREFIX = "|cff00ccffTrinketed Overlay:|r "

local Overlay = {}
addon.Overlay = Overlay

-------------------------------------------------------------------------------
-- TOKEN MAP (handoff name -> lib.C key)
-------------------------------------------------------------------------------

local BG          = C.frameBg
local BG_DEEP     = C.sidebarBg
local BORDER      = C.borderDefault
local BORDER_SUB  = C.borderSubtle
local TEXT        = C.textBright
local TEXT_DIM    = C.textNormal
local TEXT_FAINT  = C.textDim
local TEXT_FAINTER= C.textMuted
local ACCENT      = C.accent
local WARNING     = C.accentGlow
local WIN, LOSS   = C.win, C.loss
local WIN_T, LOSS_T = C.winText, C.lossText
local ON_CHIP     = C.onChip

local function tex(parent, layer, color, alpha, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    if color then t:SetColorTexture(color[1], color[2], color[3], alpha or 1) end
    return t
end

local function tint(t, color, alpha)
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

local function fs(parent, font, size, color, justify)
    local s = parent:CreateFontString(nil, "OVERLAY")
    s:SetFont(font, size, "")
    if color then s:SetTextColor(color[1], color[2], color[3], 1) end
    if justify then s:SetJustifyH(justify) end
    return s
end

local function fscolor(s, color)
    s:SetTextColor(color[1], color[2], color[3], 1)
end

local WORDMARK = "|cffE8B923T|r|cffF4F4F5RINKETED|r"

-------------------------------------------------------------------------------
-- LAYOUT CONSTANTS (true pixels at 1.0x)
-------------------------------------------------------------------------------

local HEADER_H   = 18
local STRIP_H    = 34
local ROW_H      = 24
local FOOTER_H   = 14
local CHIP_W     = 14
local BAR_W      = 2
local CR_X       = CHIP_W + 5
local CR_W       = 28
local DELTA_W    = 20
local TEAM_GAP_F = 6
local VS_W       = 14    -- "VS" separator cell between the teams
local SIGIL      = 16
local SIGIL_GAP  = 2
local RIGHT_SLACK = 26
local RIGHT_PAD  = 4
local STRIP_INSET = 3
local MAX_POOL_ROWS = 10
local MIN_ROWS, MAX_ROWS = 1, 10
local MIN_SCALE, MAX_SCALE = 0.5, 2.0
local MAX_HISTORY = 50
local SESSION_GAP_SECONDS = 3600
local MAX_TEAM = 5

local function TeamW(size) return size * SIGIL + (size - 1) * SIGIL_GAP end

local function PanelW(size)
    return CHIP_W + 5 + CR_W + DELTA_W + TEAM_GAP_F
        + TeamW(size) + VS_W + TeamW(size) + RIGHT_SLACK + RIGHT_PAD
end

-------------------------------------------------------------------------------
-- CLASS DATA
-------------------------------------------------------------------------------

local CLASS_ICON_TCOORDS = {
    WARRIOR = { 0.00, 0.25, 0.00, 0.25 }, MAGE    = { 0.25, 0.50, 0.00, 0.25 },
    ROGUE   = { 0.50, 0.75, 0.00, 0.25 }, DRUID   = { 0.75, 1.00, 0.00, 0.25 },
    HUNTER  = { 0.00, 0.25, 0.25, 0.50 }, SHAMAN  = { 0.25, 0.50, 0.25, 0.50 },
    PRIEST  = { 0.50, 0.75, 0.25, 0.50 }, WARLOCK = { 0.75, 1.00, 0.25, 0.50 },
    PALADIN = { 0.00, 0.25, 0.50, 0.75 }, UNKNOWN = { 0.25, 0.50, 0.50, 0.75 },
}

-- TBC talent-tab icons keyed "CLASSTOKEN:Spec Name" as the recorder stores
local SPEC_ICONS = {
    ["WARRIOR:Arms"] = "Ability_Rogue_Eviscerate", ["WARRIOR:Fury"] = "Ability_Warrior_InnerRage",
    ["WARRIOR:Protection"] = "Ability_Warrior_DefensiveStance",
    ["PALADIN:Holy"] = "Spell_Holy_HolyBolt", ["PALADIN:Protection"] = "Spell_Holy_DevotionAura",
    ["PALADIN:Retribution"] = "Spell_Holy_AuraOfLight",
    ["HUNTER:Beast Mastery"] = "Ability_Hunter_BeastTaming", ["HUNTER:Marksmanship"] = "Ability_Marksmanship",
    ["HUNTER:Survival"] = "Ability_Hunter_SwiftStrike",
    ["ROGUE:Assassination"] = "Ability_Rogue_Eviscerate", ["ROGUE:Combat"] = "Ability_BackStab",
    ["ROGUE:Subtlety"] = "Ability_Stealth",
    ["PRIEST:Discipline"] = "Spell_Holy_WordFortitude", ["PRIEST:Holy"] = "Spell_Holy_HolyBolt",
    ["PRIEST:Shadow"] = "Spell_Shadow_ShadowWordPain",
    ["SHAMAN:Elemental"] = "Spell_Nature_Lightning", ["SHAMAN:Enhancement"] = "Spell_Nature_LightningShield",
    ["SHAMAN:Restoration"] = "Spell_Nature_MagicImmunity",
    ["MAGE:Arcane"] = "Spell_Holy_MagicalSentry", ["MAGE:Fire"] = "Spell_Fire_FireBolt02",
    ["MAGE:Frost"] = "Spell_Frost_FrostBolt02",
    ["WARLOCK:Affliction"] = "Spell_Shadow_DeathCoil", ["WARLOCK:Demonology"] = "Spell_Shadow_Metamorphosis",
    ["WARLOCK:Destruction"] = "Spell_Shadow_RainOfFire",
    ["DRUID:Balance"] = "Spell_Nature_StarFall", ["DRUID:Feral"] = "Ability_Racial_BearForm",
    ["DRUID:Restoration"] = "Spell_Nature_HealingTouch",
}

-------------------------------------------------------------------------------
-- STATE
-------------------------------------------------------------------------------

local db                      -- TrinketedHistoryDB.overlay
local mainFrame, settingsFrame
local rowFrames = {}
local isLocked = true
local displayList = {}
local lastGameCount = -1
local activeBracket = "ALL"

local RefreshOverlay, RebuildDisplayList, ShowSettings, RefreshSettings
local SetLocked, EnsureFrames

local function Enabled() return db and db.enabled or false end
local function Rows() return db and db.maxRows or 8 end
local function RatedOnly() return not db or db.ratedOnly ~= false end
local function IconStyle() return db and db.iconStyle or "class" end
local function IndicatorStyle() return db and db.indicatorStyle or "chip" end
local function BracketMode() return db and db.bracket or "AUTO" end
local function SpecBadges() return db and db.specBadges or false end
local function ClickReplay() return not db or db.clickReplay ~= false end
local function MockOn() return db and db.mockData or false end

local function SavePosition()
    if not db or not mainFrame then return end
    local point, _, relPoint, x, y = mainFrame:GetPoint()
    db.position = { point = point, relPoint = relPoint, x = x, y = y }
    db.scale = mainFrame:GetScale()
end

-------------------------------------------------------------------------------
-- ICON WIDGET — class atlas / spec icon in a 1px-framed 16px cell; dead =
-- desaturate + 4px loss corner (D12). Sigil style cut by Nick's review.
-------------------------------------------------------------------------------

local function CreateSigil(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(SIGIL, SIGIL)
    f:EnableMouse(false)

    f.border = tex(f, "ARTWORK", BORDER, 1)
    f.border:SetAllPoints()
    f.fillBg = tex(f, "ARTWORK", BG_DEEP, 1, 1)
    f.fillBg:SetPoint("TOPLEFT", 1, -1); f.fillBg:SetPoint("BOTTOMRIGHT", -1, 1)

    f.icon = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.icon:SetPoint("TOPLEFT", 1, -1); f.icon:SetPoint("BOTTOMRIGHT", -1, 1)

    f.badgeBack = tex(f, "OVERLAY", { 0, 0, 0 }, 0.9, 1)
    f.badgeBack:SetSize(8, 8)
    f.badgeBack:SetPoint("BOTTOMRIGHT", 1, -1)
    f.badgeBack:Hide()
    f.badge = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.badge:SetPoint("TOPLEFT", f.badgeBack, "TOPLEFT", 1, -1)
    f.badge:SetPoint("BOTTOMRIGHT", f.badgeBack, "BOTTOMRIGHT", -1, 1)
    f.badge:Hide()

    f.deadCorner = tex(f, "OVERLAY", LOSS, 1, 3)
    f.deadCorner:SetSize(4, 4)
    f.deadCorner:SetPoint("TOPRIGHT", 1, 1)
    f.deadCorner:Hide()

    function f:Setup(classToken, spec, dead)
        local style = IconStyle()
        local specIcon = spec and SPEC_ICONS[classToken .. ":" .. spec]

        if style == "spec" and specIcon then
            self.icon:SetTexture("Interface\\Icons\\" .. specIcon)
            self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        else
            self.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            local tc = CLASS_ICON_TCOORDS[classToken] or CLASS_ICON_TCOORDS.UNKNOWN
            self.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        end
        self.icon:SetDesaturated(dead and true or false)

        if SpecBadges() and specIcon and style ~= "spec" then
            self.badge:SetTexture("Interface\\Icons\\" .. specIcon)
            self.badge:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            self.badge:SetDesaturated(dead and true or false)
            self.badgeBack:Show(); self.badge:Show()
        else
            self.badgeBack:Hide(); self.badge:Hide()
        end

        if dead then self.deadCorner:Show() else self.deadCorner:Hide() end
        self:Show()
    end

    function f:Clear() self:Hide() end
    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- ROW WIDGET (D4) — a Button so a click can open the game's replay
-------------------------------------------------------------------------------

local function CreateMatchRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(false)

    -- Hover highlight: only visible when the row is clickable (has a replay)
    row.hl = tex(row, "HIGHLIGHT", { 1, 1, 1 }, 0.06)
    row.hl:SetAllPoints()

    row.chip = tex(row, "ARTWORK", WIN, A)
    row.chip:SetSize(CHIP_W, ROW_H)
    row.chip:SetPoint("LEFT", 0, 0)
    row.chipLetter = fs(row, FONT_M, 9, ON_CHIP)
    row.chipLetter:SetPoint("CENTER", row.chip, "CENTER", 0, 0)
    row.bar = tex(row, "ARTWORK", WIN, A)
    row.bar:SetSize(BAR_W, ROW_H)
    row.bar:SetPoint("LEFT", 0, 0)
    row.bar:Hide()

    row.cr = fs(row, FONT_M, 11, TEXT, "LEFT")
    row.cr:SetPoint("LEFT", CR_X, 0)
    row.cr:SetWidth(CR_W)

    row.delta = fs(row, FONT_M, 10, WIN_T, "RIGHT")
    row.delta:SetPoint("LEFT", CR_X + CR_W, 0)
    row.delta:SetWidth(DELTA_W)

    row.friendly, row.enemy = {}, {}
    for i = 1, MAX_TEAM do
        row.friendly[i] = CreateSigil(row)
        row.enemy[i] = CreateSigil(row)
    end

    row.vs = fs(row, FONT_M, 7, TEXT_FAINT)
    row.vs:SetText("VS")

    row:SetScript("OnClick", function(self)
        if self.gameRef and addon.OpenReplay then
            local ok, err = pcall(addon.OpenReplay, addon, self.gameRef)
            if not ok then
                print(PREFIX .. "Could not open replay: " .. tostring(err))
            end
        end
    end)

    function row:SetMatch(m, teamSize)
        if not m then self:Hide(); self.gameRef = nil; self:EnableMouse(false); return end
        local isWin = m.result == "WIN"
        local rc = isWin and WIN or (m.result == "LOSS" and LOSS or TEXT_FAINTER)

        if IndicatorStyle() == "bar" then
            self.chip:Hide(); self.chipLetter:Hide()
            self.bar:Show(); tint(self.bar, rc, A)
        else
            self.bar:Hide()
            self.chip:Show(); tint(self.chip, rc, A)
            self.chipLetter:Show()
            self.chipLetter:SetText(isWin and "W" or (m.result == "LOSS" and "L" or "?"))
        end

        self.cr:SetText(m.rating and tostring(m.rating) or "?")
        if m.ratingDelta then
            self.delta:SetText((m.ratingDelta >= 0 and "+" or "") .. m.ratingDelta)
            fscolor(self.delta, m.ratingDelta >= 0 and WIN_T or LOSS_T)
            self.delta:Show()
        else
            self.delta:Hide()
        end

        local fX = CR_X + CR_W + DELTA_W + TEAM_GAP_F
        local eX = fX + TeamW(teamSize) + VS_W
        self.vs:ClearAllPoints()
        self.vs:SetPoint("CENTER", self, "LEFT", fX + TeamW(teamSize) + VS_W / 2, 0)
        local function layout(sigils, players, startX)
            for i = 1, MAX_TEAM do
                local s, p = sigils[i], players and players[i]
                s:ClearAllPoints()
                if p and i <= teamSize then
                    s:SetPoint("LEFT", self, "LEFT", startX + (i - 1) * (SIGIL + SIGIL_GAP), 0)
                    s:Setup(p.class, p.spec, p.dead)
                else
                    s:Clear()
                end
            end
        end
        layout(self.friendly, m.friendly, fX)
        layout(self.enemy, m.enemy, eX)

        -- Click-to-replay: mouse only on rows that can actually open one, so
        -- everything else stays click-through even with the feature on
        local clickable = ClickReplay() and m.game and m.hasReplay or false
        self.gameRef = clickable and m.game or nil
        self:EnableMouse(clickable and true or false)

        self:Show()
    end

    row:Hide()
    return row
end

-------------------------------------------------------------------------------
-- SESSION STATS (60-min chain over the filtered list)
-------------------------------------------------------------------------------

local function ComputeSessionStats()
    local s = { wins = 0, losses = 0, net = 0, cr = nil, mmr = nil,
                streakLen = 0, streakResult = nil, games = 0 }
    local prevStart = nil
    for _, m in ipairs(displayList) do
        if prevStart and m.endTime and (prevStart - m.endTime) > SESSION_GAP_SECONDS then break end
        s.games = s.games + 1
        if m.result == "WIN" then s.wins = s.wins + 1
        elseif m.result == "LOSS" then s.losses = s.losses + 1 end
        if m.ratingDelta then s.net = s.net + m.ratingDelta end
        if not s.cr and m.rating then s.cr = m.rating end
        if not s.mmr and m.mmr then s.mmr = m.mmr end
        prevStart = m.startTime or m.endTime
    end
    for i = 1, s.games do
        local r = displayList[i].result
        if r ~= "WIN" and r ~= "LOSS" then break end
        if not s.streakResult then s.streakResult = r
        elseif r ~= s.streakResult then break end
        s.streakLen = s.streakLen + 1
    end
    return s
end

-------------------------------------------------------------------------------
-- MAIN FRAME (created lazily on first enable)
-------------------------------------------------------------------------------

local resizeDragStart = {}

local function CreateOverlayFrame()
    local f = CreateFrame("Frame", "TrinketedHistoryOverlayFrame", UIParent)
    f:SetSize(PanelW(2), HEADER_H + STRIP_H + ROW_H)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not isLocked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

    f.headerBg = tex(f, "BACKGROUND", BG, A)
    f.headerBg:SetPoint("TOPLEFT", 0, 0); f.headerBg:SetPoint("TOPRIGHT", 0, 0)
    f.headerBg:SetHeight(HEADER_H)
    f.stripBg = tex(f, "BACKGROUND", BG, A)
    f.stripBg:SetPoint("TOPLEFT", 0, -HEADER_H); f.stripBg:SetPoint("TOPRIGHT", 0, -HEADER_H)
    f.stripBg:SetHeight(STRIP_H)
    f.rowsBg = tex(f, "BACKGROUND", BG_DEEP, A)
    f.rowsBg:SetPoint("TOPLEFT", 0, -(HEADER_H + STRIP_H))
    f.rowsBg:SetPoint("BOTTOMRIGHT", 0, 0)

    f.edges = {}
    for i = 1, 4 do f.edges[i] = tex(f, "BORDER", BORDER, A) end
    f.edges[1]:SetPoint("TOPLEFT", 0, 0); f.edges[1]:SetPoint("TOPRIGHT", 0, 0); f.edges[1]:SetHeight(1)
    f.edges[2]:SetPoint("BOTTOMLEFT", 0, 0); f.edges[2]:SetPoint("BOTTOMRIGHT", 0, 0); f.edges[2]:SetHeight(1)
    f.edges[3]:SetPoint("TOPLEFT", 0, 0); f.edges[3]:SetPoint("BOTTOMLEFT", 0, 0); f.edges[3]:SetWidth(1)
    f.edges[4]:SetPoint("TOPRIGHT", 0, 0); f.edges[4]:SetPoint("BOTTOMRIGHT", 0, 0); f.edges[4]:SetWidth(1)

    f.stripLine = tex(f, "ARTWORK", BORDER, A)
    f.stripLine:SetPoint("TOPLEFT", 0, -HEADER_H); f.stripLine:SetPoint("TOPRIGHT", 0, -HEADER_H)
    f.stripLine:SetHeight(1)
    f.rowsLine = tex(f, "ARTWORK", BORDER, A)
    f.rowsLine:SetPoint("TOPLEFT", 0, -(HEADER_H + STRIP_H))
    f.rowsLine:SetPoint("TOPRIGHT", 0, -(HEADER_H + STRIP_H))
    f.rowsLine:SetHeight(1)

    f.wordmark = fs(f, FONT_D, 10, TEXT)
    f.wordmark:SetPoint("LEFT", f.headerBg, "LEFT", 6, 0)
    f.wordmark:SetText(WORDMARK)

    f.cog = CreateFrame("Button", nil, f)
    f.cog:SetSize(10, 10)
    f.cog:SetPoint("RIGHT", f.headerBg, "RIGHT", -5, 0)
    f.cog.tex = tex(f.cog, "ARTWORK", TEXT_FAINT, 1)
    f.cog.tex:SetPoint("CENTER"); f.cog.tex:SetSize(8, 8)
    f.cog.hl = tex(f.cog, "HIGHLIGHT", ACCENT, 1)
    f.cog.hl:SetPoint("CENTER"); f.cog.hl:SetSize(8, 8)
    f.cog:SetScript("OnClick", function() ShowSettings() end)
    f.cog:Hide()

    f.bracketFact = fs(f, FONT_M, 9, ACCENT, "RIGHT")
    f.mockTag = fs(f, FONT_M, 8, WARNING, "RIGHT")
    f.mockTag:SetText("MOCK")
    f.mockTag:Hide()

    f.tiles = {}
    for i = 1, 5 do
        local tile = CreateFrame("Frame", nil, f)
        tile:SetHeight(STRIP_H)
        tile.value = fs(tile, FONT_M, 12, TEXT)
        tile.value:SetPoint("TOP", tile, "TOP", 0, -5)
        tile.label = fs(tile, FONT_M, 8, TEXT_FAINT)
        tile.label:SetPoint("TOP", tile, "TOP", 0, -20)
        f.tiles[i] = tile
    end
    f.tiles[1].label:SetText("RECORD")
    f.tiles[2].label:SetText("NET")
    f.tiles[3].label:SetText("CR")
    f.tiles[4].label:SetText("MMR")
    f.tiles[5].label:SetText("STREAK")

    for i = 1, MAX_POOL_ROWS do
        rowFrames[i] = CreateMatchRow(f, i)
    end

    f.emptyText = fs(f, FONT_M, 8, TEXT_FAINT)
    f.emptyText:SetText("NO GAMES THIS SESSION")
    f.emptyText:Hide()

    f.footerBg = tex(f, "ARTWORK", ACCENT, 0.14)
    f.footerBg:SetPoint("BOTTOMLEFT", 0, 0); f.footerBg:SetPoint("BOTTOMRIGHT", 0, 0)
    f.footerBg:SetHeight(FOOTER_H)
    f.footerBg:Hide()
    f.footerText = fs(f, FONT_M, 8, ACCENT, "LEFT")
    f.footerText:SetPoint("LEFT", f.footerBg, "LEFT", 6, 0)
    f.footerText:SetText("UNLOCKED · DRAG TO MOVE")
    f.footerText:Hide()

    f.grip = CreateFrame("Frame", nil, f)
    f.grip:SetSize(8, 8)
    f.grip:SetPoint("BOTTOMRIGHT", 1, -1)
    f.grip:SetFrameLevel(f:GetFrameLevel() + 10)
    f.grip:EnableMouse(true)
    f.grip.tex = tex(f.grip, "OVERLAY", ACCENT, 1)
    f.grip.tex:SetAllPoints()
    f.grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local x = GetCursorPosition()
        local s = f:GetScale()
        resizeDragStart.x = x; resizeDragStart.scale = s
        resizeDragStart.left = f:GetLeft() * s
        resizeDragStart.top = f:GetTop() * s
        self.isDragging = true
    end)
    f.grip:SetScript("OnMouseUp", function(self) self.isDragging = false; SavePosition(); RefreshSettings() end)
    f.grip:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end
        local cx = GetCursorPosition()
        local dx = cx - resizeDragStart.x
        local baseW = f:GetWidth()
        local newScale = math.max(MIN_SCALE, math.min(MAX_SCALE,
            resizeDragStart.scale + dx / (baseW * resizeDragStart.scale)))
        f:SetScale(newScale)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            resizeDragStart.left / newScale, resizeDragStart.top / newScale)
    end)
    f.grip:Hide()

    mainFrame = f
    return f
end

local function UpdateLockChrome()
    local f = mainFrame
    if not f then return end
    local edgeColor = isLocked and BORDER or ACCENT
    for _, e in ipairs(f.edges) do tint(e, edgeColor, A) end
    f.bracketFact:ClearAllPoints()
    if isLocked then
        f.cog:Hide(); f.grip:Hide()
        f.footerBg:Hide(); f.footerText:Hide()
        f.bracketFact:SetPoint("RIGHT", f.headerBg, "RIGHT", -6, 0)
    else
        f.cog:Show(); f.grip:Show()
        f.footerBg:Show(); f.footerText:Show()
        f.bracketFact:SetPoint("RIGHT", f.cog, "LEFT", -4, 0)
    end
    f.mockTag:ClearAllPoints()
    f.mockTag:SetPoint("RIGHT", f.bracketFact, "LEFT", -4, 0)
end

-------------------------------------------------------------------------------
-- REFRESH
-------------------------------------------------------------------------------

RefreshOverlay = function()
    local f = mainFrame
    if not f then return end

    f.bracketFact:SetText(activeBracket == "ALL" and "ALL" or activeBracket:upper())
    if MockOn() then f.mockTag:Show() else f.mockTag:Hide() end

    local teamSize = 2
    if activeBracket == "3v3" then teamSize = 3
    elseif activeBracket == "5v5" then teamSize = 5
    elseif activeBracket == "ALL" then
        for i = 1, math.min(#displayList, Rows()) do
            local m = displayList[i]
            local n = math.max(m.friendly and #m.friendly or 0, m.enemy and #m.enemy or 0)
            if n > teamSize then teamSize = n end
        end
    end

    local width = PanelW(teamSize)
    f:SetWidth(width)

    local s = ComputeSessionStats()
    local tiles = f.tiles
    local colW = (width - 2 * STRIP_INSET) / 5
    for i = 1, 5 do
        tiles[i]:ClearAllPoints()
        tiles[i]:SetPoint("TOPLEFT", f, "TOPLEFT", STRIP_INSET + (i - 1) * colW, -HEADER_H)
        tiles[i]:SetWidth(colW)
    end

    tiles[1].value:SetText(s.wins .. "-" .. s.losses)
    fscolor(tiles[1].value, TEXT)

    if s.net > 0 then
        tiles[2].value:SetText("+" .. s.net); fscolor(tiles[2].value, WIN_T)
    elseif s.net < 0 then
        tiles[2].value:SetText(tostring(s.net)); fscolor(tiles[2].value, LOSS_T)
    else
        tiles[2].value:SetText("0"); fscolor(tiles[2].value, TEXT_DIM)
    end

    local cr = s.cr or (displayList[1] and displayList[1].rating)
    local mmr = s.mmr or (displayList[1] and displayList[1].mmr)
    tiles[3].value:SetText(cr and tostring(cr) or "—")
    fscolor(tiles[3].value, cr and ACCENT or TEXT_FAINT)
    tiles[4].value:SetText(mmr and tostring(mmr) or "—")
    fscolor(tiles[4].value, mmr and TEXT_DIM or TEXT_FAINT)

    if activeBracket == "ALL" and displayList[1] and displayList[1].bracket then
        local b = displayList[1].bracket:upper()
        tiles[3].label:SetText(b .. " CR")
        tiles[4].label:SetText(b .. " MMR")
    else
        tiles[3].label:SetText("CR")
        tiles[4].label:SetText("MMR")
    end

    if s.streakLen > 0 then
        local w = s.streakResult == "WIN"
        tiles[5].value:SetText((w and "W" or "L") .. s.streakLen)
        fscolor(tiles[5].value, w and WIN_T or LOSS_T)
    else
        tiles[5].value:SetText("—")
        fscolor(tiles[5].value, TEXT_FAINT)
    end

    local visible = math.min(#displayList, Rows())
    for i = 1, MAX_POOL_ROWS do
        local row = rowFrames[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(HEADER_H + STRIP_H + (i - 1) * ROW_H))
        row:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        if i <= visible then row:SetMatch(displayList[i], teamSize)
        else row:SetMatch(nil) end
    end

    if visible == 0 then
        f.emptyText:ClearAllPoints()
        f.emptyText:SetPoint("TOP", f, "TOP", 0, -(HEADER_H + STRIP_H + (ROW_H - 8) / 2))
        f.emptyText:Show()
    else
        f.emptyText:Hide()
    end

    local bodyRows = math.max(visible, 1)
    f:SetHeight(HEADER_H + STRIP_H + bodyRows * ROW_H + (isLocked and 0 or FOOTER_H))
    UpdateLockChrome()
end

-------------------------------------------------------------------------------
-- DATA READER
-------------------------------------------------------------------------------

local function ClassToken(properCase)
    if not properCase then return "UNKNOWN" end
    return properCase:upper()
end

local function TeamToPlayers(team, selfName)
    local players = {}
    for _, p in ipairs(team or {}) do
        table.insert(players, {
            class = ClassToken(p.class),
            spec = p.spec,
            dead = (p.deaths and p.deaths > 0) or false,
            isSelf = (selfName and p.name == selfName) or false,
        })
    end
    table.sort(players, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        return a.class < b.class
    end)
    return players
end

local function GameToRowModel(g, bracketFilter)
    if not g then return nil end
    if RatedOnly() and (g.matchType == "skirmish" or g.matchType == "wargame") then return nil end
    if bracketFilter ~= "ALL" and g.bracket ~= bracketFilter then return nil end
    return {
        result = g.result,
        rating = g.ratingAfter,
        ratingDelta = g.ratingChange,
        mmr = g.mmrAfter,
        friendly = TeamToPlayers(g.friendlyTeam, g.playerName),
        enemy = TeamToPlayers(g.enemyTeam, nil),
        startTime = g.startTime,
        endTime = g.endTime or g.startTime,
        bracket = g.bracket,
        game = g,                              -- click-to-replay target
        hasReplay = g.eventLog ~= nil,         -- imports have no replay
    }
end

local function ResolveBracket()
    local mode = BracketMode()
    if mode ~= "AUTO" then return mode end
    local games = TrinketedHistoryDB and TrinketedHistoryDB.games
    if games then
        for i = #games, 1, -1 do
            local g = games[i]
            if g and g.bracket and not (RatedOnly() and (g.matchType == "skirmish" or g.matchType == "wargame")) then
                return g.bracket
            end
        end
    end
    return "ALL"
end

local MOCK_ROWS

RebuildDisplayList = function()
    if not Enabled() or not mainFrame then return end
    if MockOn() then
        activeBracket = "2v2"
        displayList = MOCK_ROWS
        RefreshOverlay()
        return
    end
    activeBracket = ResolveBracket()
    displayList = {}
    local games = TrinketedHistoryDB and TrinketedHistoryDB.games
    if games then
        for i = #games, 1, -1 do
            local m = GameToRowModel(games[i], activeBracket)
            if m then table.insert(displayList, m) end
            if #displayList >= MAX_HISTORY then break end
        end
    end
    RefreshOverlay()
end

-------------------------------------------------------------------------------
-- MOCK FIXTURE (display only; no game refs, so rows are not clickable)
-------------------------------------------------------------------------------

do
    local t = time()
    local function P(class, spec, dead) return { class = class, spec = spec, dead = dead } end
    MOCK_ROWS = {
        { result = "WIN", rating = 2088, ratingDelta = 9, mmr = 2103, startTime = t - 300, endTime = t - 180, bracket = "2v2",
          friendly = { P("WARLOCK", "Affliction"), P("DRUID", "Restoration") },
          enemy = { P("PRIEST", "Discipline", true), P("HUNTER", "Beast Mastery") } },
        { result = "LOSS", rating = 2079, ratingDelta = -12, mmr = 2094, startTime = t - 900, endTime = t - 700, bracket = "2v2",
          friendly = { P("WARLOCK", "Affliction", true), P("DRUID", "Restoration") },
          enemy = { P("MAGE", "Frost"), P("ROGUE", "Subtlety") } },
        { result = "WIN", rating = 2091, ratingDelta = 7, mmr = 2101, startTime = t - 1500, endTime = t - 1300, bracket = "2v2",
          friendly = { P("WARLOCK", "Affliction"), P("DRUID", "Restoration") },
          enemy = { P("PRIEST", "Shadow", true), P("ROGUE", "Combat") } },
        { result = "WIN", rating = 2084, ratingDelta = 14, mmr = 2088, startTime = t - 2100, endTime = t - 1900, bracket = "2v2",
          friendly = { P("WARLOCK", "Affliction"), P("DRUID", "Restoration") },
          enemy = { P("WARRIOR", "Arms"), P("PALADIN", "Holy", true) } },
        { result = "LOSS", rating = 2070, ratingDelta = -18, mmr = 2075, startTime = t - 2700, endTime = t - 2500, bracket = "2v2",
          friendly = { P("WARLOCK", "Affliction"), P("DRUID", "Restoration", true) },
          enemy = { P("WARLOCK", "Demonology"), P("DRUID", "Restoration") } },
    }
end

-------------------------------------------------------------------------------
-- LOCK / ENABLE
-------------------------------------------------------------------------------

SetLocked = function(locked)
    isLocked = locked
    if db then db.locked = locked end
    if mainFrame then
        mainFrame:EnableMouse(not locked)
        RefreshOverlay()
    end
    RefreshSettings()
end

EnsureFrames = function()
    if not mainFrame then
        CreateOverlayFrame()
        local s = math.max(MIN_SCALE, math.min(MAX_SCALE, db and db.scale or 1.0))
        mainFrame:SetScale(s)
        if db and db.position then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(db.position.point or "TOPRIGHT", UIParent,
                db.position.relPoint or "TOPRIGHT", db.position.x or -20, db.position.y or -200)
        end
        mainFrame:EnableMouse(not isLocked)
    end
end

function Overlay:IsEnabled() return Enabled() end

function Overlay:SetEnabled(on)
    if not db then return end
    -- Store nil (not false) when off so the SavedVariables file stays clean
    db.enabled = on and true or nil
    if on then
        EnsureFrames()
        mainFrame:Show()
        RebuildDisplayList()
    elseif mainFrame then
        mainFrame:Hide()
    end
    RefreshSettings()
end

function Overlay:Toggle()
    self:SetEnabled(not Enabled())
    print(PREFIX .. (Enabled() and "Enabled." or "Disabled."))
end

-------------------------------------------------------------------------------
-- SETTINGS PANEL
-------------------------------------------------------------------------------

local PANEL_W = 260
local PAD = 10
local INNER_W = PANEL_W - 2 * PAD

local function Separator(parent, y)
    local line = tex(parent, "ARTWORK", BORDER_SUB, 1)
    line:SetPoint("TOPLEFT", 0, y); line:SetPoint("TOPRIGHT", 0, y)
    line:SetHeight(1)
end

local function CellButton(parent, w, h, label, fontSize)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = tex(b, "BACKGROUND", BG_DEEP, 1)
    b.bg:SetAllPoints()
    b.label = fs(b, FONT_M, fontSize or 9, TEXT_FAINT)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b.hl = tex(b, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
    b.hl:SetAllPoints()
    function b:SetActive(on)
        if on then
            tint(self.bg, ACCENT, 1); fscolor(self.label, ON_CHIP)
        else
            tint(self.bg, BG_DEEP, 1); fscolor(self.label, TEXT_FAINT)
        end
    end
    return b
end

local function CreateSettingsPanel()
    local f = CreateFrame("Frame", "TrinketedHistoryOverlaySettings", UIParent)
    f:SetSize(PANEL_W, 100)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true)

    f.bg = tex(f, "BACKGROUND", BG, 0.97)
    f.bg:SetAllPoints()
    f.edges = {}
    for i = 1, 4 do f.edges[i] = tex(f, "BORDER", BORDER, 1) end
    f.edges[1]:SetPoint("TOPLEFT", 0, 0); f.edges[1]:SetPoint("TOPRIGHT", 0, 0); f.edges[1]:SetHeight(1)
    f.edges[2]:SetPoint("BOTTOMLEFT", 0, 0); f.edges[2]:SetPoint("BOTTOMRIGHT", 0, 0); f.edges[2]:SetHeight(1)
    f.edges[3]:SetPoint("TOPLEFT", 0, 0); f.edges[3]:SetPoint("BOTTOMLEFT", 0, 0); f.edges[3]:SetWidth(1)
    f.edges[4]:SetPoint("TOPRIGHT", 0, 0); f.edges[4]:SetPoint("BOTTOMRIGHT", 0, 0); f.edges[4]:SetWidth(1)

    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT", 0, 0); title:SetPoint("TOPRIGHT", 0, 0)
    title:SetHeight(26)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    title.bg = tex(title, "BACKGROUND", BG_DEEP, 1)
    title.bg:SetAllPoints()
    title.line = tex(title, "ARTWORK", BORDER, 1)
    title.line:SetPoint("BOTTOMLEFT", 0, 0); title.line:SetPoint("BOTTOMRIGHT", 0, 0)
    title.line:SetHeight(1)
    title.mark = fs(title, FONT_D, 10, TEXT, "LEFT")
    title.mark:SetPoint("LEFT", PAD, 0)
    title.mark:SetText(WORDMARK)
    title.sub = fs(title, FONT_M, 8, TEXT_FAINT, "LEFT")
    title.sub:SetPoint("LEFT", title.mark, "RIGHT", 6, 0)
    title.sub:SetText("OVERLAY · SETTINGS")
    local close = CreateFrame("Button", nil, title)
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", -6, 0)
    close.label = fs(close, FONT_M, 10, TEXT_FAINT)
    close.label:SetPoint("CENTER")
    close.label:SetText("✕")
    close.hl = tex(close, "HIGHLIGHT", { 1, 1, 1 }, 0.08)
    close.hl:SetAllPoints()
    close:SetScript("OnClick", function() f:Hide() end)

    local y = -26

    -- BRACKET (D1)
    y = y - 9
    local bl = fs(f, FONT_M, 8, TEXT_FAINT, "LEFT")
    bl:SetPoint("TOPLEFT", PAD, y)
    bl:SetText("BRACKET")
    f.bracketEcho = fs(f, FONT_M, 9, ACCENT, "RIGHT")
    f.bracketEcho:SetPoint("TOPRIGHT", -PAD, y)
    y = y - 14

    local seg = CreateFrame("Frame", nil, f)
    seg:SetPoint("TOPLEFT", PAD, y)
    seg:SetSize(INNER_W, 20)
    seg.bg = tex(seg, "BACKGROUND", BORDER, 1)
    seg.bg:SetAllPoints()
    local SEG_VALUES = { "AUTO", "2v2", "3v3", "5v5", "ALL" }
    local cellW = math.floor((INNER_W - 6) / 5)
    f.segButtons = {}
    for i, v in ipairs(SEG_VALUES) do
        local w = (i == 5) and (INNER_W - 2 - (cellW + 1) * 4) or cellW
        local b = CellButton(seg, w, 18, v:upper())
        b:SetPoint("TOPLEFT", 1 + (i - 1) * (cellW + 1), -1)
        b.value = v
        b:SetScript("OnClick", function()
            if db then db.bracket = v end
            RebuildDisplayList(); RefreshSettings()
        end)
        f.segButtons[i] = b
    end
    y = y - 24
    local hint = fs(f, FONT_B, 10, TEXT_FAINT, "LEFT")
    hint:SetPoint("TOPLEFT", PAD, y); hint:SetWidth(INNER_W)
    hint:SetText("Auto follows the bracket of your last game this session. Pick one to pin it.")
    hint:SetSpacing(2)
    y = y - 26
    Separator(f, y); y = y - 9

    -- ROWS / SCALE steppers
    local colW = (INNER_W - 12) / 2

    local function Stepper(x, labelText, echoKey)
        local l = fs(f, FONT_M, 8, TEXT_FAINT, "LEFT")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(labelText)
        local box = CreateFrame("Frame", nil, f)
        box:SetPoint("TOPLEFT", x, y - 12)
        box:SetSize(colW, 20)
        box.bg = tex(box, "BACKGROUND", BORDER, 1)
        box.bg:SetAllPoints()
        local btnW = 24
        local minus = CellButton(box, btnW, 18, "−", 10)
        minus:SetPoint("TOPLEFT", 1, -1)
        fscolor(minus.label, TEXT_DIM)
        local plus = CellButton(box, btnW, 18, "+", 10)
        plus:SetPoint("TOPRIGHT", -1, -1)
        fscolor(plus.label, TEXT_DIM)
        local valCell = CreateFrame("Frame", nil, box)
        valCell:SetPoint("TOPLEFT", 1 + btnW + 1, -1)
        valCell:SetSize(colW - 2 * btnW - 4, 18)
        valCell.bg = tex(valCell, "BACKGROUND", BG_DEEP, 1)
        valCell.bg:SetAllPoints()
        valCell.value = fs(valCell, FONT_M, 9, TEXT)
        valCell.value:SetPoint("CENTER")
        f[echoKey] = valCell.value
        return minus, plus
    end

    local rMinus, rPlus = Stepper(PAD, "ROWS", "rowsValue")
    local sMinus, sPlus = Stepper(PAD + colW + 12, "SCALE", "scaleValue")

    local function bumpRows(d)
        if not db then return end
        db.maxRows = math.max(MIN_ROWS, math.min(MAX_ROWS, Rows() + d))
        RefreshOverlay(); RefreshSettings()
    end
    local function bumpScale(d)
        if not mainFrame then return end
        local s = math.max(MIN_SCALE, math.min(MAX_SCALE, mainFrame:GetScale() + d))
        mainFrame:SetScale(s); SavePosition(); RefreshSettings()
    end
    rMinus:SetScript("OnClick", function() bumpRows(-1) end)
    rPlus:SetScript("OnClick", function() bumpRows(1) end)
    sMinus:SetScript("OnClick", function() bumpScale(-0.05) end)
    sPlus:SetScript("OnClick", function() bumpScale(0.05) end)

    y = y - 36
    Separator(f, y); y = y - 9

    -- ICONS / INDICATOR cycles
    local function Cycle(x, labelText, echoKey, hintText, onCycle)
        local l = fs(f, FONT_M, 8, TEXT_FAINT, "LEFT")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(labelText)
        local box = CreateFrame("Frame", nil, f)
        box:SetPoint("TOPLEFT", x, y - 12)
        box:SetSize(colW, 20)
        box.bg = tex(box, "BACKGROUND", BORDER, 1)
        box.bg:SetAllPoints()
        local btnW = 20
        local prev = CellButton(box, btnW, 18, "‹", 10)
        prev:SetPoint("TOPLEFT", 1, -1)
        fscolor(prev.label, TEXT_DIM)
        local nxt = CellButton(box, btnW, 18, "›", 10)
        nxt:SetPoint("TOPRIGHT", -1, -1)
        fscolor(nxt.label, TEXT_DIM)
        local valCell = CreateFrame("Frame", nil, box)
        valCell:SetPoint("TOPLEFT", 1 + btnW + 1, -1)
        valCell:SetSize(colW - 2 * btnW - 4, 18)
        valCell.bg = tex(valCell, "BACKGROUND", BG_DEEP, 1)
        valCell.bg:SetAllPoints()
        valCell.value = fs(valCell, FONT_M, 9, TEXT)
        valCell.value:SetPoint("CENTER")
        f[echoKey] = valCell.value
        local h = fs(f, FONT_B, 9, TEXT_FAINT, "LEFT")
        h:SetPoint("TOPLEFT", x, y - 35)
        h:SetText(hintText)
        prev:SetScript("OnClick", function() onCycle(-1) end)
        nxt:SetScript("OnClick", function() onCycle(1) end)
    end

    local ICON_ORDER = { "class", "spec" }
    local IND_ORDER = { "chip", "bar" }
    local function cycleOf(order, cur, d)
        local idx = 1
        for i, v in ipairs(order) do if v == cur then idx = i end end
        return order[((idx - 1 + d) % #order) + 1]
    end

    Cycle(PAD, "ICONS", "iconValue", "Class · Spec", function(d)
        if db then db.iconStyle = cycleOf(ICON_ORDER, IconStyle(), d) end
        RefreshOverlay(); RefreshSettings()
    end)
    Cycle(PAD + colW + 12, "INDICATOR", "indValue", "Chip · Bar", function(d)
        if db then db.indicatorStyle = cycleOf(IND_ORDER, IndicatorStyle(), d) end
        RefreshOverlay(); RefreshSettings()
    end)

    y = y - 48
    Separator(f, y); y = y - 8

    -- Checkboxes
    local CHECKS = {
        { key = "ratedOnly", label = "RATED ONLY", default = true, rebuild = true },
        { key = "autoMinimize", label = "HIDE IN ARENA", default = false },
        { key = "specBadges", label = "SPEC BADGES", default = false },
        { key = "clickReplay", label = "CLICK TO REPLAY", default = true, hint = "rows open the replay" },
        { key = "mockData", label = "MOCK DATA", default = false, hint = "for positioning", rebuild = true },
    }
    f.checks = {}
    for _, def in ipairs(CHECKS) do
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", PAD, y)
        row:SetSize(INNER_W, 20)
        row.hl = tex(row, "HIGHLIGHT", { 1, 1, 1 }, 0.04)
        row.hl:SetAllPoints()
        row.box = tex(row, "ARTWORK", BORDER, 1)
        row.box:SetSize(10, 10)
        row.box:SetPoint("LEFT", 0, 0)
        row.boxInner = tex(row, "ARTWORK", BG_DEEP, 1, 1)
        row.boxInner:SetSize(8, 8)
        row.boxInner:SetPoint("CENTER", row.box, "CENTER", 0, 0)
        row.label = fs(row, FONT_M, 9, TEXT_DIM, "LEFT")
        row.label:SetPoint("LEFT", 16, 0)
        row.label:SetText(def.label)
        if def.hint then
            row.hint = fs(row, FONT_B, 9, TEXT_FAINT, "RIGHT")
            row.hint:SetPoint("RIGHT", 0, 0)
            row.hint:SetText(def.hint)
        end
        row.def = def
        function row:Update()
            local val = db and db[self.def.key]
            if val == nil then val = self.def.default end
            if val then
                tint(self.box, ACCENT, 1); tint(self.boxInner, ACCENT, 1)
                fscolor(self.label, TEXT)
            else
                tint(self.box, BORDER, 1); tint(self.boxInner, BG_DEEP, 1)
                fscolor(self.label, TEXT_DIM)
            end
        end
        row:SetScript("OnClick", function(self)
            if not db then return end
            local val = db[self.def.key]
            if val == nil then val = self.def.default end
            db[self.def.key] = not val
            self:Update()
            if self.def.rebuild then RebuildDisplayList() else RefreshOverlay() end
        end)
        table.insert(f.checks, row)
        y = y - 22
    end
    y = y - 4
    Separator(f, y); y = y - 10

    -- Buttons
    local btnW = (INNER_W - 12) / 3
    local function ActionButton(x, label, primary)
        local b = CreateFrame("Button", nil, f)
        b:SetPoint("TOPLEFT", x, y)
        b:SetSize(btnW, 22)
        b.bg = tex(b, "BACKGROUND", primary and ACCENT or BG_DEEP, 1)
        b.bg:SetAllPoints()
        if not primary then
            b.border = {}
            for i = 1, 4 do b.border[i] = tex(b, "BORDER", BORDER, 1) end
            b.border[1]:SetPoint("TOPLEFT", 0, 0); b.border[1]:SetPoint("TOPRIGHT", 0, 0); b.border[1]:SetHeight(1)
            b.border[2]:SetPoint("BOTTOMLEFT", 0, 0); b.border[2]:SetPoint("BOTTOMRIGHT", 0, 0); b.border[2]:SetHeight(1)
            b.border[3]:SetPoint("TOPLEFT", 0, 0); b.border[3]:SetPoint("BOTTOMLEFT", 0, 0); b.border[3]:SetWidth(1)
            b.border[4]:SetPoint("TOPRIGHT", 0, 0); b.border[4]:SetPoint("BOTTOMRIGHT", 0, 0); b.border[4]:SetWidth(1)
        end
        b.label = fs(b, FONT_M, 9, primary and ON_CHIP or TEXT_DIM)
        b.label:SetPoint("CENTER")
        b.label:SetText(label)
        b.hl = tex(b, "HIGHLIGHT", { 1, 1, 1 }, 0.08)
        b.hl:SetAllPoints()
        return b
    end

    f.lockBtn = ActionButton(PAD, "UNLOCK", true)
    f.lockBtn:SetScript("OnClick", function() SetLocked(not isLocked) end)
    local resetBtn = ActionButton(PAD + btnW + 6, "RESET")
    resetBtn:SetScript("OnClick", function()
        if mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
            mainFrame:SetScale(1.0)
            SavePosition(); RefreshSettings()
        end
    end)
    local closeBtn = ActionButton(PAD + 2 * (btnW + 6), "CLOSE")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    y = y - 32
    f:SetHeight(-y)

    settingsFrame = f
    return f
end

RefreshSettings = function()
    local f = settingsFrame
    if not f or not f:IsShown() then return end
    local mode = BracketMode()
    f.bracketEcho:SetText(mode:upper())
    for _, b in ipairs(f.segButtons) do b:SetActive(b.value == mode) end
    f.rowsValue:SetText(tostring(Rows()))
    f.scaleValue:SetText(string.format("%.2f×", mainFrame and mainFrame:GetScale() or 1))
    f.iconValue:SetText(IconStyle():upper())
    f.indValue:SetText(IndicatorStyle():upper())
    for _, row in ipairs(f.checks) do row:Update() end
    f.lockBtn.label:SetText(isLocked and "UNLOCK" or "LOCK")
end

ShowSettings = function()
    if not Enabled() then Overlay:SetEnabled(true) end
    if not settingsFrame then CreateSettingsPanel() end
    if settingsFrame:IsShown() then settingsFrame:Hide()
    else settingsFrame:Show(); RefreshSettings() end
end

-------------------------------------------------------------------------------
-- SYNC (count-watch ticker + battlefield events)
-------------------------------------------------------------------------------

local function CheckForNewGames(force)
    if not Enabled() then return end
    local games = TrinketedHistoryDB and TrinketedHistoryDB.games
    local n = games and #games or 0
    if force or n ~= lastGameCount then
        lastGameCount = n
        RebuildDisplayList()
    end
end

local syncEventFrame = CreateFrame("Frame")
syncEventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
syncEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
syncEventFrame:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(1.5, function() CheckForNewGames(true) end)
    end
end)

-------------------------------------------------------------------------------
-- HIDE IN ARENA
-------------------------------------------------------------------------------

local arenaStateFrame = CreateFrame("Frame")
arenaStateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
arenaStateFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
arenaStateFrame:SetScript("OnEvent", function()
    if not mainFrame or not db or not db.autoMinimize or not Enabled() then return end
    local inArenaNow = IsActiveBattlefieldArena and IsActiveBattlefieldArena() or false
    if inArenaNow then
        if mainFrame:IsShown() then
            mainFrame.wasShownBeforeArena = true
            mainFrame:Hide()
        end
    else
        if mainFrame.wasShownBeforeArena then
            mainFrame:Show()
            mainFrame.wasShownBeforeArena = nil
        end
    end
end)

-------------------------------------------------------------------------------
-- INIT + MIGRATION FROM THE STANDALONE ADDON
-------------------------------------------------------------------------------

local function MigrateStandalone()
    -- One-time import from the retired TrinketedOverlay addon's saved vars
    -- (only possible while that addon is still installed and loaded)
    if db.importedStandalone then return end
    local old = _G.TrinketedOverlayDB
    if type(old) ~= "table" then return end
    db.importedStandalone = true
    db.enabled = true -- they had the overlay; keep it on
    for _, k in ipairs({ "maxRows", "scale", "position", "locked", "iconStyle",
                         "indicatorStyle", "bracket", "ratedOnly", "autoMinimize",
                         "specBadges" }) do
        if db[k] == nil and old[k] ~= nil then db[k] = old[k] end
    end
    if old.bracketFilter and not db.bracket then
        db.bracket = (old.bracketFilter == "ALL") and "AUTO" or old.bracketFilter
    end
    if db.indicatorStyle == "orbs" then db.indicatorStyle = "chip" end
    if db.indicatorStyle == "bars" then db.indicatorStyle = "bar" end
    if db.iconStyle == "both" then db.iconStyle = "class"; db.specBadges = true end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGOUT")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "TrinketedHistory" then
        TrinketedHistoryDB = TrinketedHistoryDB or {}
        if not TrinketedHistoryDB.overlay then TrinketedHistoryDB.overlay = {} end
        db = TrinketedHistoryDB.overlay
        MigrateStandalone()
        if not db.maxRows then db.maxRows = 8 end
        if not db.indicatorStyle then db.indicatorStyle = "chip" end
        if not db.iconStyle or db.iconStyle == "sigil" then db.iconStyle = "class" end
        if not db.bracket then db.bracket = "AUTO" end
        if db.locked ~= nil then isLocked = db.locked else isLocked = true; db.locked = true end

        if Enabled() then
            EnsureFrames()
            mainFrame:Show()
            CheckForNewGames(true)
        end

        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(2, function() CheckForNewGames(false) end)
        end
    elseif event == "PLAYER_LOGOUT" then
        if db and mainFrame then
            db.locked = isLocked
            db.scale = mainFrame:GetScale()
            SavePosition()
        end
    end
end)

-------------------------------------------------------------------------------
-- SLASH COMMANDS (/tko kept; also /trinketed overlay)
-------------------------------------------------------------------------------

local function HandleCommand(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "" or msg == "toggle" then
        Overlay:Toggle()
    elseif msg == "test" or msg == "mock" then
        if not Enabled() then Overlay:SetEnabled(true) end
        if db then db.mockData = not db.mockData end
        RebuildDisplayList(); RefreshSettings()
        print(PREFIX .. (MockOn() and "Mock data on." or "Mock data off."))
    elseif msg == "sync" or msg == "refresh" then
        CheckForNewGames(true); print(PREFIX .. "Synced.")
    elseif msg == "unlock" then
        if not Enabled() then Overlay:SetEnabled(true) end
        SetLocked(false); print(PREFIX .. "Unlocked — drag to move, grip to scale.")
    elseif msg == "lock" then
        SetLocked(true); print(PREFIX .. "Locked (click-through).")
    elseif msg == "settings" or msg == "config" or msg == "options" then
        ShowSettings()
    elseif msg == "scale" or msg:match("^scale%s") then
        local val = tonumber(msg:match("^scale%s+(.+)"))
        if val and mainFrame then
            val = math.max(MIN_SCALE, math.min(MAX_SCALE, val))
            mainFrame:SetScale(val); SavePosition(); RefreshSettings()
            print(PREFIX .. "Scale: " .. string.format("%.2f", val))
        else print(PREFIX .. "/tko scale 0.5-2.0") end
    elseif msg == "rows" or msg:match("^rows%s") then
        local val = tonumber(msg:match("^rows%s+(.+)"))
        if val then
            val = math.max(MIN_ROWS, math.min(MAX_ROWS, math.floor(val)))
            if db then db.maxRows = val end
            RefreshOverlay(); RefreshSettings()
            print(PREFIX .. "Rows: " .. val)
        else print(PREFIX .. "/tko rows 1-10") end
    elseif msg == "help" then
        print(PREFIX .. "Commands:")
        print("  /tko             Enable/disable the overlay")
        print("  /tko settings    Settings panel")
        print("  /tko sync        Refresh from history")
        print("  /tko unlock|lock Reposition / click-through")
        print("  /tko scale 1.0   Scale (0.5-2.0)")
        print("  /tko rows 5      Visible rows (1-10)")
        print("  /tko test        Toggle mock data")
    else print(PREFIX .. "Unknown command. /tko help") end
end

SLASH_TRINKETEDOVERLAY1 = "/tko"
SLASH_TRINKETEDOVERLAY2 = "/trinketedoverlay"
SlashCmdList["TRINKETEDOVERLAY"] = HandleCommand

lib:RegisterSubCommand("overlay", function(rest) HandleCommand(rest) end)
