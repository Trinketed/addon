---------------------------------------------------------------------------
-- TrinketedCD: Options.lua
-- Settings content — registers into master Trinketed options panel
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local optionsFrame = nil

-- Per-team grid builder state
local gridBuilderState = {
    party = { currentClass = "Warrior", gridSlotPool = {}, poolRowPool = {}, scrollChild = nil, gridParent = nil, filterButtons = {}, searchText = "" },
}

---------------------------------------------------------------------------
-- Init Options
---------------------------------------------------------------------------
function addon:InitOptions()
    lib:RegisterSubAddon("Cooldowns", {
        order = 1,
        OnSelect = function(contentFrame)
            addon:BuildOptionsContent(contentFrame)
        end,
    })
end

function addon:BuildOptionsContent(parent)
    local tabBar = lib:CreateTabBar(parent, {
        { "settings", "Settings" },
        { "spells", "Spells" },
        { "test", "Test" },
    }, {
        height = 26,
        tabWidth = 80,
    })

    -- Right-aligned bar items: import/export
    local exportBtn = lib:CreateButton(tabBar.frame, 0, 0, 60, "Export", function()
        addon:ShowImportExportDialog("export")
    end)
    exportBtn:ClearAllPoints()
    exportBtn:SetPoint("RIGHT", tabBar.frame, "RIGHT", -36, 0)
    exportBtn:SetSize(60, 18)

    local importBtn = lib:CreateButton(tabBar.frame, 0, 0, 60, "Import", function()
        addon:ShowImportExportDialog("import")
    end)
    importBtn:ClearAllPoints()
    importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    importBtn:SetSize(60, 18)

    -- Populate tab contents
    self:PopulateSettingsTab(tabBar.contents["settings"])
    self:PopulateSpellsTab(tabBar.contents["spells"])
    self:PopulateTestModeTab(tabBar.contents["test"])

    tabBar:SelectTab("settings")
end

---------------------------------------------------------------------------
-- Import / Export Dialog
---------------------------------------------------------------------------
local importExportDialog = nil

function addon:ShowImportExportDialog(mode)
    if not importExportDialog then
        local f = CreateFrame("Frame", "TrinketedCDImportExportDialog", UIParent, "BackdropTemplate")
        f:SetSize(480, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(C.frameBg[1], C.frameBg[2], C.frameBg[3], C.frameBg[4])
        f:SetBackdropBorderColor(C.frameBorder[1], C.frameBorder[2], C.frameBorder[3], C.frameBorder[4])
        f:Hide()

        -- Title
        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont(addon.FONT_DISPLAY, 12, "")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        f.title = title

        -- Close button
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() f:Hide() end)

        -- Scroll frame for EditBox
        local scrollBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        scrollBg:SetPoint("TOPLEFT", 12, -36)
        scrollBg:SetPoint("BOTTOMRIGHT", -12, 58)
        scrollBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], C.sidebarBg[4])

        local scroll = CreateFrame("ScrollFrame", "TrinketedCDIEScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -38)
        scroll:SetPoint("BOTTOMRIGHT", -32, 60)

        local editBox = CreateFrame("EditBox", "TrinketedCDIEEditBox", scroll)
        editBox:SetMultiLine(true)
        editBox:SetMaxLetters(0)
        editBox:SetAutoFocus(false)
        editBox:SetFont(addon.FONT_MONO, 10, "")
        editBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
        editBox:SetWidth(420)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(editBox)
        f.editBox = editBox

        -- Status text
        local status = f:CreateFontString(nil, "OVERLAY")
        status:SetFont(addon.FONT_BODY, 10, "")
        status:SetPoint("BOTTOMLEFT", 14, 36)
        status:SetPoint("BOTTOMRIGHT", -14, 36)
        status:SetJustifyH("LEFT")
        status:SetWordWrap(true)
        status:SetText("")
        f.status = status

        -- Export button (BOTTOMLEFT → TOPLEFT conversion: 320 - 8 - 24 = 288)
        local exportBtn = lib:CreateButton(f, 14, -288, 140, "Export", function()
            local str = addon:ExportConfig()
            if str then
                f.editBox:SetText(str)
                f.editBox:HighlightText()
                f.editBox:SetFocus()
                f.status:SetTextColor(C.statusSuccess[1], C.statusSuccess[2], C.statusSuccess[3])
                f.status:SetText("Config exported. Press Ctrl+C to copy.")
            else
                f.status:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
                f.status:SetText("Export failed: no config loaded.")
            end
        end)
        f.exportBtn = exportBtn

        -- Import button
        local importBtn = lib:CreateButton(f, 164, -288, 140, "Import", function()
            local text = f.editBox:GetText()
            if not text or text == "" then
                f.status:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
                f.status:SetText("Paste a config string first.")
                return
            end
            local success, warnOrErr = addon:ImportConfig(text)
            if success then
                f.status:SetTextColor(C.statusSuccess[1], C.statusSuccess[2], C.statusSuccess[3])
                if warnOrErr then
                    f.status:SetText("Config imported with warnings. /reload to refresh options.")
                    addon:Print("Import warnings:\n" .. warnOrErr)
                else
                    f.status:SetText("Config imported! /reload to refresh options panel.")
                end
                addon:Print("Config imported successfully.")
            else
                f.status:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
                f.status:SetText(warnOrErr or "Import failed.")
            end
        end)
        f.importBtn = importBtn

        importExportDialog = f
    end

    local f = importExportDialog
    f.status:SetText("")
    f.editBox:SetText("")

    if mode == "export" then
        f.title:SetText("EXPORT CONFIG")
        local str = addon:ExportConfig()
        if str then
            f.editBox:SetText(str)
            C_Timer.After(0.05, function()
                f.editBox:HighlightText()
                f.editBox:SetFocus()
            end)
            f.status:SetTextColor(C.statusSuccess[1], C.statusSuccess[2], C.statusSuccess[3])
            f.status:SetText("Press Ctrl+C to copy the config string.")
        end
    else
        f.title:SetText("IMPORT CONFIG")
        f.editBox:SetFocus()
    end

    f:Show()
end

---------------------------------------------------------------------------
-- Show/Hide Options
---------------------------------------------------------------------------
function addon:ShowOptions()
    lib:ShowOptionsPanel("Cooldowns")
end

---------------------------------------------------------------------------
-- Settings Tab (merged General + Party settings)
---------------------------------------------------------------------------
function addon:PopulateSettingsTab(parent)
    local y = -10
    local col1 = 10
    local col2 = 270

    -- TRACKING section
    y = lib:CreateSectionHeader(parent, y, "TRACKING")
    y = y - 4

    lib:CreateCheckbox(parent, col1, y, "Enable party cooldown tracking",
        self.db.party.enabled, function(checked)
            self.db.party.enabled = checked
            self:RefreshAllBars()
        end)
    lib:CreateCheckbox(parent, col2, y, "Track outside arena",
        self.db.general.trackOutsideArena, function(checked)
            self.db.general.trackOutsideArena = checked
            if checked and not addon.state.inArena then
                addon:ScanPartyMembers()
                addon:ScanPetOwners()
                addon:RefreshAllBars()
            end
        end)
    y = y - 24

    local lockToggle = lib:CreateCheckbox(parent, col1, y, "Bars locked",
        self.db.general.locked, function(on)
            if on ~= self.db.general.locked then
                addon:ToggleLock()
            end
        end)
    self._lockToggles = self._lockToggles or {}
    self._lockToggles[#self._lockToggles + 1] = lockToggle

    lib:CreateButton(parent, col2, y, 150, "Reset Positions", function()
        addon:ResetAllPositions()
    end)
    y = y - 24

    lib:CreateCheckbox(parent, col1, y, "Debug output",
        self.db.debug, function(checked)
            self.db.debug = checked
        end)
    y = y - 28

    -- APPEARANCE section
    y = lib:CreateSectionHeader(parent, y, "APPEARANCE")
    y = y - 4

    lib:CreateSlider(parent, col1, y, "Icon Size", 16, 48, 2,
        self.db.party.iconSize, function(val)
            self.db.party.iconSize = val
            self:RefreshAllBars()
        end)
    y = y - 42

    lib:CreateCheckbox(parent, col1, y, "Compact mode (active CDs only)",
        self.db.general.compactMode, function(checked)
            self.db.general.compactMode = checked
            self:RefreshAllBars()
        end)
    lib:CreateCheckbox(parent, col2, y, "Show category borders",
        self.db.general.showIconBorders, function(checked)
            self.db.general.showIconBorders = checked
            self:RefreshAllBars()
        end)
    y = y - 24

    lib:CreateCheckbox(parent, col1, y, "Show player name labels",
        self.db.general.showPlayerLabels, function(checked)
            self.db.general.showPlayerLabels = checked
            local locked = self.db.general.locked
            for guid, bar in pairs(self.bars) do
                local info = self.state.trackedPlayers[guid]
                if locked then
                    if checked and info then
                        bar.nameText:SetText(self:ClassColorWrap(info.name, info.class))
                        bar.nameText:SetAlpha(0.7)
                        bar.nameText:Show()
                    else
                        bar.nameText:Hide()
                    end
                end
            end
        end)
    lib:CreateCheckbox(parent, col2, y, "Show spell tooltips on hover",
        self.db.general.showSpellTooltips, function(checked)
            self.db.general.showSpellTooltips = checked
        end)
    y = y - 24

    lib:CreateCheckbox(parent, col1, y, "Glow when CD expires",
        self.db.general.showGlowOnReady, function(checked)
            self.db.general.showGlowOnReady = checked
        end)
    lib:CreateCheckbox(parent, col2, y, "Flash when ability used",
        self.db.general.showFlashOnUse, function(checked)
            self.db.general.showFlashOnUse = checked
        end)
    y = y - 24

    lib:CreateCheckbox(parent, col1, y, "Pulse border on low timer",
        self.db.general.showPulseOnLow, function(checked)
            self.db.general.showPulseOnLow = checked
        end)
    y = y - 28

    -- Active glow color picker
    local glowLabel = parent:CreateFontString(nil, "OVERLAY")
    glowLabel:SetFont(addon.FONT_BODY, 11, "")
    glowLabel:SetPoint("TOPLEFT", col1, y)
    glowLabel:SetText("Active buff glow color")
    glowLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    local agc = self.db.general.activeGlowColor
    local glowSwatch = CreateFrame("Button", nil, parent)
    glowSwatch:SetPoint("TOPLEFT", col1 + 160, y + 3)
    glowSwatch:SetSize(20, 14)

    glowSwatch.bg = glowSwatch:CreateTexture(nil, "BACKGROUND")
    glowSwatch.bg:SetAllPoints()
    glowSwatch.bg:SetColorTexture(agc.r, agc.g, agc.b, 1)

    glowSwatch.border = glowSwatch:CreateTexture(nil, "ARTWORK")
    glowSwatch.border:SetPoint("TOPLEFT", -1, 1)
    glowSwatch.border:SetPoint("BOTTOMRIGHT", 1, -1)
    glowSwatch.border:SetColorTexture(0.4, 0.4, 0.4, 1)
    glowSwatch.bg:SetDrawLayer("ARTWORK", 1)

    glowSwatch:SetScript("OnClick", function()
        local prev = { r = agc.r, g = agc.g, b = agc.b }
        local function setColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            agc.r, agc.g, agc.b = r, g, b
            glowSwatch.bg:SetColorTexture(r, g, b, 1)
            self:UpdateActiveGlowColor()
        end
        local function cancelColor()
            agc.r, agc.g, agc.b = prev.r, prev.g, prev.b
            glowSwatch.bg:SetColorTexture(prev.r, prev.g, prev.b, 1)
            self:UpdateActiveGlowColor()
        end
        ColorPickerFrame:SetColorRGB(agc.r, agc.g, agc.b)
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = setColor
        ColorPickerFrame.cancelFunc = cancelColor
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end)

    y = y - 34

    -- POSITION section
    y = lib:CreateSectionHeader(parent, y, "POSITION")
    y = y - 4

    lib:CreateCheckbox(parent, col1, y, "Anchor to party unit frames",
        self.db.party.anchorToFrames, function(checked)
            self.db.party.anchorToFrames = checked
            self:RefreshAllBars()
        end)
    y = y - 32

    -- Anchor side buttons (LEFT / RIGHT)
    local sideLabel = parent:CreateFontString(nil, "OVERLAY")
    sideLabel:SetFont(addon.FONT_BODY, 10, "")
    sideLabel:SetPoint("TOPLEFT", col1, y)
    sideLabel:SetText("Anchor Side:")
    sideLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    lib:CreateButton(parent, 100, y, 60, "Left", function()
        self.db.party.anchorSide = "LEFT"
        self:RefreshAllBars()
    end)
    lib:CreateButton(parent, 166, y, 60, "Right", function()
        self.db.party.anchorSide = "RIGHT"
        self:RefreshAllBars()
    end)
    y = y - 32

    lib:CreateSlider(parent, col1, y, "Anchor Offset X", -50, 50, 1,
        self.db.party.anchorOffsetX, function(val)
            self.db.party.anchorOffsetX = val
            self:RefreshAllBars()
        end)
    lib:CreateSlider(parent, 300, y, "Anchor Offset Y", -50, 50, 1,
        self.db.party.anchorOffsetY, function(val)
            self.db.party.anchorOffsetY = val
            self:RefreshAllBars()
        end)
    y = y - 48

    lib:CreateButton(parent, col1, y, 180, "Reset Party Positions", function()
        wipe(self.db.party.positions)
        self:RefreshAllBars()
        self:Print("Party bar positions reset.")
    end)
end

---------------------------------------------------------------------------
-- Grid Builder: Drag State
---------------------------------------------------------------------------
local gridDrag = {
    isDragging  = false,
    sourceType  = nil,   -- "grid" or "pool"
    sourceIndex = nil,   -- grid slot index (if from grid)
    spellName   = nil,   -- spell being dragged
    ghostFrame  = nil,
    updateFrame = nil,
    team        = nil,
    state       = nil,
}

-- Reusable context menu frame (avoid creating new one per right-click)
local gridContextMenu = nil
local function GetGridContextMenu()
    if not gridContextMenu then
        gridContextMenu = CreateFrame("Frame", "TrinketedCDGridContextMenu", UIParent, "UIDropDownMenuTemplate")
    end
    return gridContextMenu
end

local function GetGridDragGhost()
    if gridDrag.ghostFrame then return gridDrag.ghostFrame end

    local f = CreateFrame("Frame", "TrinketedCDGridDragGhost", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetSize(34, 34)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.8)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- 4-edge border
    local bTop = f:CreateTexture(nil, "OVERLAY")
    bTop:SetPoint("TOPLEFT", -1, 1)
    bTop:SetPoint("TOPRIGHT", 1, 1)
    bTop:SetHeight(1)
    bTop:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    local bBot = f:CreateTexture(nil, "OVERLAY")
    bBot:SetPoint("BOTTOMLEFT", -1, -1)
    bBot:SetPoint("BOTTOMRIGHT", 1, -1)
    bBot:SetHeight(1)
    bBot:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    local bLeft = f:CreateTexture(nil, "OVERLAY")
    bLeft:SetPoint("TOPLEFT", -1, 1)
    bLeft:SetPoint("BOTTOMLEFT", -1, -1)
    bLeft:SetWidth(1)
    bLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    local bRight = f:CreateTexture(nil, "OVERLAY")
    bRight:SetPoint("TOPRIGHT", 1, 1)
    bRight:SetPoint("BOTTOMRIGHT", 1, -1)
    bRight:SetWidth(1)
    bRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)

    gridDrag.ghostFrame = f
    return f
end

local function GetGridDragUpdateFrame()
    if gridDrag.updateFrame then return gridDrag.updateFrame end
    gridDrag.updateFrame = CreateFrame("Frame", nil, UIParent)
    gridDrag.updateFrame:Hide()
    return gridDrag.updateFrame
end

local function StopGridDrag()
    gridDrag.isDragging = false
    local ghost = GetGridDragGhost()
    ghost:Hide()
    local tracker = GetGridDragUpdateFrame()
    tracker:SetScript("OnUpdate", nil)
    tracker:Hide()
end

-- Hit-test cursor against grid slots and perform drop action
-- Returns true if a drop was performed on a grid slot
local function TryDropOnGridSlot(team, state)
    if not gridDrag.isDragging then return false end
    local droppedSpell = gridDrag.spellName
    if not droppedSpell then return false end

    local grid = addon:GetClassGrid(state.currentClass, team)
    if not grid then return false end

    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale

    for idx, slot in pairs(state.gridSlotPool) do
        if slot:IsShown() then
            local left = slot:GetLeft()
            local right = slot:GetRight()
            local top = slot:GetTop()
            local bottom = slot:GetBottom()
            if left and cx >= left and cx <= right and cy >= bottom and cy <= top then
                if gridDrag.sourceType == "grid" then
                    local srcIdx = gridDrag.sourceIndex
                    if srcIdx ~= idx then
                        local srcSpell = grid.slots[srcIdx] or ""
                        local destSpell = grid.slots[idx] or ""
                        grid.slots[srcIdx] = destSpell
                        grid.slots[idx] = srcSpell
                        local srcDis = grid.disabled[srcIdx]
                        local destDis = grid.disabled[idx]
                        grid.disabled[srcIdx] = destDis
                        grid.disabled[idx] = srcDis
                    end
                elseif gridDrag.sourceType == "pool" then
                    while #grid.slots < idx do
                        grid.slots[#grid.slots + 1] = ""
                    end
                    grid.slots[idx] = droppedSpell
                    grid.disabled[idx] = nil
                    -- Clear removed flag so migration won't skip this spell
                    if grid.removed then grid.removed[droppedSpell] = nil end
                end
                return true
            end
        end
    end
    return false
end

local function StartGridDrag(spellName, sourceType, sourceIndex, texPath, team, state)
    gridDrag.isDragging = true
    gridDrag.sourceType = sourceType
    gridDrag.sourceIndex = sourceIndex
    gridDrag.spellName = spellName
    gridDrag.team = team
    gridDrag.state = state

    local ghost = GetGridDragGhost()
    ghost.icon:SetTexture(texPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    ghost:Show()

    local tracker = GetGridDragUpdateFrame()
    tracker:SetScript("OnUpdate", function()
        if not gridDrag.isDragging then return end
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    end)
    tracker:Show()
end

---------------------------------------------------------------------------
-- Grid Builder: Helper to get spell icon texture
---------------------------------------------------------------------------
local function GetSpellIcon(spellName)
    if not spellName or spellName == "" then return nil end
    local cdData = addon.COOLDOWN_DB[spellName]
    if not cdData then return nil end
    if cdData.allianceIcon and cdData.hordeIcon then
        if addon.playerFaction == "Alliance" then
            return cdData.allianceIcon
        else
            return cdData.hordeIcon
        end
    end
    return GetSpellTexture(cdData.spellID)
end

---------------------------------------------------------------------------
-- Grid Builder: Slot Frame Pool
---------------------------------------------------------------------------
local GRID_SLOT_SIZE = 34
local GRID_SLOT_PAD = 3

local function GetOrCreateGridSlot(state, index, parent)
    if state.gridSlotPool[index] then
        state.gridSlotPool[index]:SetParent(parent)
        return state.gridSlotPool[index]
    end

    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(GRID_SLOT_SIZE, GRID_SLOT_SIZE)
    slot:EnableMouse(true)
    slot:RegisterForDrag("LeftButton")

    -- Background
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints()
    slot.bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)

    -- Spell icon
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Category border (1px)
    slot.borderTop = slot:CreateTexture(nil, "OVERLAY")
    slot.borderTop:SetPoint("TOPLEFT"); slot.borderTop:SetPoint("TOPRIGHT")
    slot.borderTop:SetHeight(1)

    slot.borderBottom = slot:CreateTexture(nil, "OVERLAY")
    slot.borderBottom:SetPoint("BOTTOMLEFT"); slot.borderBottom:SetPoint("BOTTOMRIGHT")
    slot.borderBottom:SetHeight(1)

    slot.borderLeft = slot:CreateTexture(nil, "OVERLAY")
    slot.borderLeft:SetPoint("TOPLEFT"); slot.borderLeft:SetPoint("BOTTOMLEFT")
    slot.borderLeft:SetWidth(1)

    slot.borderRight = slot:CreateTexture(nil, "OVERLAY")
    slot.borderRight:SetPoint("TOPRIGHT"); slot.borderRight:SetPoint("BOTTOMRIGHT")
    slot.borderRight:SetWidth(1)

    -- Empty slot "+" text
    slot.emptyText = slot:CreateFontString(nil, "OVERLAY")
    slot.emptyText:SetFont(addon.FONT_DISPLAY, 18, "OUTLINE")
    slot.emptyText:SetPoint("CENTER")
    slot.emptyText:SetText("+")
    slot.emptyText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- Disabled "X" overlay
    slot.disabledOverlay = slot:CreateTexture(nil, "OVERLAY", nil, 3)
    slot.disabledOverlay:SetAllPoints()
    slot.disabledOverlay:SetColorTexture(0, 0, 0, 0.6)
    slot.disabledOverlay:Hide()

    slot.disabledX = slot:CreateFontString(nil, "OVERLAY")
    slot.disabledX:SetFont(addon.FONT_DISPLAY, 18, "OUTLINE")
    slot.disabledX:SetPoint("CENTER")
    slot.disabledX:SetText("X")
    slot.disabledX:SetTextColor(1, 0.3, 0.3, 0.8)
    slot.disabledX:Hide()

    state.gridSlotPool[index] = slot
    return slot
end

---------------------------------------------------------------------------
-- Grid Builder: Pool Row Frame Pool
---------------------------------------------------------------------------
local POOL_ROW_H = 22

local function GetOrCreatePoolRow(state, index, parent)
    if state.poolRowPool[index] then
        state.poolRowPool[index]:SetParent(parent)
        return state.poolRowPool[index]
    end

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(500, POOL_ROW_H)
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    row.pip = row:CreateTexture(nil, "ARTWORK")
    row.pip:SetSize(3, 14)
    row.pip:SetPoint("LEFT", 6, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 14, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.nameText = row:CreateFontString(nil, "OVERLAY")
    row.nameText:SetFont(addon.FONT_BODY, 10, "")
    row.nameText:SetPoint("LEFT", 34, 0)
    row.nameText:SetWidth(200)
    row.nameText:SetJustifyH("LEFT")

    row.durText = row:CreateFontString(nil, "OVERLAY")
    row.durText:SetFont(addon.FONT_MONO, 9, "")
    row.durText:SetPoint("LEFT", 240, 0)
    row.durText:SetWidth(80)
    row.durText:SetJustifyH("LEFT")

    state.poolRowPool[index] = row
    return row
end

---------------------------------------------------------------------------
-- Grid Builder: Refresh grid display
---------------------------------------------------------------------------
function addon:RefreshGridDisplay(team, state)
    local className = state.currentClass
    local grid = self:GetClassGrid(className, team)
    if not grid then return end

    local gridParent = state.gridParent
    if not gridParent then return end

    local cols = grid.cols or 4
    local rows = grid.rows or 3
    local displaySlots = rows * cols

    -- Ensure slots array is exactly rows*cols
    while #grid.slots < displaySlots do
        grid.slots[#grid.slots + 1] = ""
    end

    -- Resize grid area to fit rows x cols grid
    local gridContentH = rows * (GRID_SLOT_SIZE + GRID_SLOT_PAD) - GRID_SLOT_PAD
    local gridAreaH = gridContentH + 18  -- 14px label + 4px padding
    if state.gridArea then
        state.gridArea:SetHeight(gridAreaH)
    end
    gridParent:SetHeight(gridContentH)

    -- Hide all pooled slots
    for _, slot in pairs(state.gridSlotPool) do slot:Hide() end

    for i = 1, displaySlots do
        local slot = GetOrCreateGridSlot(state, i, gridParent)
        slot:ClearAllPoints()

        local col = ((i - 1) % cols) + 1
        local row = math.floor((i - 1) / cols) + 1

        slot:SetPoint("TOPLEFT", gridParent, "TOPLEFT",
            (col - 1) * (GRID_SLOT_SIZE + GRID_SLOT_PAD),
            -((row - 1) * (GRID_SLOT_SIZE + GRID_SLOT_PAD)))

        local spellName = grid.slots[i] or ""
        local isDisabled = grid.disabled[i]
        slot.slotIndex = i

        if spellName ~= "" then
            -- Filled slot
            local displayName = spellName
            if spellName == "Racial" then
                displayName = "Racial"
            end
            local cdData = addon.COOLDOWN_DB[spellName]
            local texPath
            if spellName == "Racial" then
                texPath = "Interface\\Icons\\Spell_Holy_MindVision"
            else
                texPath = GetSpellIcon(spellName)
            end
            slot.icon:SetTexture(texPath or "Interface\\Icons\\INV_Misc_QuestionMark")
            slot.icon:Show()
            slot.emptyText:Hide()

            -- Category color border
            local catColor = cdData and addon.CD_CATEGORY_COLORS[cdData.category]
            local br, bg, bb = 0.25, 0.25, 0.25
            if catColor then br, bg, bb = catColor.r, catColor.g, catColor.b end
            slot.borderTop:SetColorTexture(br, bg, bb, 0.85)
            slot.borderBottom:SetColorTexture(br, bg, bb, 0.85)
            slot.borderLeft:SetColorTexture(br, bg, bb, 0.85)
            slot.borderRight:SetColorTexture(br, bg, bb, 0.85)

            -- Disabled state
            if isDisabled then
                slot.disabledOverlay:Show()
                slot.disabledX:Show()
            else
                slot.disabledOverlay:Hide()
                slot.disabledX:Hide()
            end

            -- Tooltip
            slot:SetScript("OnEnter", function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                GameTooltip:SetText(displayName, C.textBright[1], C.textBright[2], C.textBright[3])
                if cdData then
                    local catLabel = addon.CD_CATEGORY_LABELS[cdData.category] or ""
                    GameTooltip:AddLine(catLabel, catColor and catColor.r or 0.7,
                        catColor and catColor.g or 0.7, catColor and catColor.b or 0.7)
                    local dur = cdData.duration
                    local durText = dur < 60 and dur .. "s" or string.format("%.0fm", dur / 60)
                    GameTooltip:AddLine("Cooldown: " .. durText, 0.7, 0.7, 0.7)
                end
                if isDisabled then
                    GameTooltip:AddLine("DISABLED", 1, 0.3, 0.3)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Right-click to remove", 0.4, 0.4, 0.4)
                GameTooltip:AddLine("Drag to reorder", 0.4, 0.4, 0.4)
                GameTooltip:Show()
            end)
            slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Right-click to remove
            local mySlotIndex = i
            local mySpellName = spellName
            slot:SetScript("OnMouseDown", function(self2, button)
                if button == "RightButton" then
                    GameTooltip:Hide()
                    grid.slots[mySlotIndex] = ""
                    grid.disabled[mySlotIndex] = nil
                    if not grid.removed then grid.removed = {} end
                    grid.removed[mySpellName] = true
                    addon:RefreshGridDisplay(team, state)
                    addon:RefreshSpellPool(team, state)
                    addon:RefreshAllBars()
                end
            end)

            -- Drag from grid
            local myTexPath = texPath
            local mySpellName = spellName
            slot:SetScript("OnDragStart", function()
                GameTooltip:Hide()
                StartGridDrag(mySpellName, "grid", mySlotIndex, myTexPath, team, state)
            end)
            slot:SetScript("OnDragStop", function()
                if not gridDrag.isDragging then return end
                -- Try dropping on another grid slot first
                if not TryDropOnGridSlot(team, state) then
                    -- If not on a grid slot, check if below grid = remove
                    local scale = UIParent:GetEffectiveScale()
                    local _, cy = GetCursorPosition()
                    cy = cy / scale
                    local gridBottom = gridParent:GetBottom()
                    if gridBottom and cy < gridBottom then
                        grid.slots[mySlotIndex] = ""
                        grid.disabled[mySlotIndex] = nil
                        if not grid.removed then grid.removed = {} end
                        grid.removed[mySpellName] = true
                    end
                end
                StopGridDrag()
                addon:RefreshGridDisplay(team, state)
                addon:RefreshSpellPool(team, state)
                addon:RefreshAllBars()
            end)
        else
            -- Empty slot
            slot.icon:SetTexture(nil)
            slot.icon:Hide()
            slot.emptyText:Show()
            slot.disabledOverlay:Hide()
            slot.disabledX:Hide()

            -- Dashed border for empty slots
            slot.borderTop:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.3)
            slot.borderBottom:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.3)
            slot.borderLeft:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.3)
            slot.borderRight:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.3)

            slot:SetScript("OnEnter", function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                GameTooltip:SetText("Empty Slot", C.textDim[1], C.textDim[2], C.textDim[3])
                GameTooltip:AddLine("Drag a spell here from the pool", 0.4, 0.4, 0.4)
                GameTooltip:Show()

                -- Highlight when dragging
                if gridDrag.isDragging then
                    slot.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.2)
                end
            end)
            slot:SetScript("OnLeave", function()
                GameTooltip:Hide()
                slot.bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
            end)
            slot:SetScript("OnMouseDown", nil)

            -- Accept drop on empty slot
            local mySlotIndex = i
            slot:SetScript("OnDragStop", nil)
            slot:SetScript("OnDragStart", nil)

            -- We handle drop reception via OnMouseUp or the global drag stop
            -- The actual drop is handled by the source's OnDragStop checking cursor position
        end

        slot:Show()
    end

end

---------------------------------------------------------------------------
-- Grid Builder: Refresh spell pool (spells not in grid)
---------------------------------------------------------------------------
function addon:RefreshSpellPool(team, state)
    local className = state.currentClass
    local grid = self:GetClassGrid(className, team)
    if not grid then return end

    local scrollChild = state.scrollChild
    if not scrollChild then return end

    -- Hide all pooled rows
    for _, row in pairs(state.poolRowPool) do row:Hide() end

    -- Build set of spells already in grid
    local inGrid = {}
    for _, slot in ipairs(grid.slots) do
        if slot ~= "" then inGrid[slot] = true end
    end

    -- Collect available spells for this class (not in grid)
    local available = {}
    local searchText = state.searchText and state.searchText:lower() or ""
    for spellName, data in pairs(self.COOLDOWN_DB) do
        if not inGrid[spellName] then
            -- Skip individual racials — they're represented by the "Racial" placeholder
            local isRacial = false
            if data.races then
                for _, c in ipairs(data.classes) do
                    if c == "ALL" then isRacial = true; break end
                end
            end

            if not isRacial then
                -- Check if spell matches current class
                local classMatch = false
                for _, c in ipairs(data.classes) do
                    if c == className or c == "ALL" then classMatch = true; break end
                end

                if classMatch then
                    -- Search filter
                    if searchText == "" or spellName:lower():find(searchText, 1, true) then
                        available[#available + 1] = { name = spellName, data = data }
                    end
                end
            end
        end
    end

    -- Add "Racial" placeholder if not in grid (synthetic entry, not in COOLDOWN_DB)
    if not inGrid["Racial"] then
        if searchText == "" or string.find("racial", searchText, 1, true) then
            available[#available + 1] = { name = "Racial", data = { category = "racial", duration = 0, spellID = 0 } }
        end
    end

    -- Sort by category then name
    local catOrder = { trinket = 1, racial = 2, major_defensive = 3, cc_break = 4, major_offensive = 5, interrupt = 6 }
    table.sort(available, function(a, b)
        local ca = catOrder[a.data.category] or 99
        local cb = catOrder[b.data.category] or 99
        if ca ~= cb then return ca < cb end
        return a.name < b.name
    end)

    local yOffset = 0
    for idx, spell in ipairs(available) do
        local row = GetOrCreatePoolRow(state, idx, scrollChild)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)

        local spellName = spell.name
        local data = spell.data
        local texPath
        if spellName == "Racial" then
            texPath = "Interface\\Icons\\Spell_Holy_MindVision"
        else
            texPath = GetSpellIcon(spellName)
        end

        -- Category pip
        local catColor = addon.CD_CATEGORY_COLORS[data.category]
        if catColor then
            row.pip:SetColorTexture(catColor.r, catColor.g, catColor.b, 0.5)
        else
            row.pip:SetColorTexture(0.5, 0.5, 0.5, 0.3)
        end

        -- Icon
        row.icon:SetTexture(texPath or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Name
        row.nameText:SetText(spellName)
        row.nameText:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

        -- Duration
        if data.duration and data.duration > 0 then
            local durText = data.duration < 60
                and data.duration .. "s"
                or string.format("%.0fm", data.duration / 60)
            row.durText:SetText(durText)
            row.durText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        else
            row.durText:SetText("")
        end

        -- Alternating bg
        if idx % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.015)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        -- Hover
        local myIdx = idx
        row:SetScript("OnEnter", function()
            row.bg:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(spellName, C.textBright[1], C.textBright[2], C.textBright[3])
            if catColor then
                local catLabel = addon.CD_CATEGORY_LABELS[data.category] or ""
                GameTooltip:AddLine(catLabel, catColor.r, catColor.g, catColor.b)
            end
            if data.duration and data.duration > 0 then
                local durText = data.duration < 60
                    and data.duration .. "s cooldown"
                    or string.format("%.0fm cooldown", data.duration / 60)
                GameTooltip:AddLine(durText, 0.7, 0.7, 0.7)
            end
            if data.races then
                GameTooltip:AddLine(table.concat(data.races, ", "), 0.6, 0.6, 0.6)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Drag to grid slot to add", 0.4, 0.4, 0.4)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if myIdx % 2 == 0 then
                row.bg:SetColorTexture(1, 1, 1, 0.015)
            else
                row.bg:SetColorTexture(0, 0, 0, 0)
            end
            GameTooltip:Hide()
        end)

        -- Drag from pool
        local myTexPath = texPath
        local mySpellName = spellName
        row:SetScript("OnDragStart", function()
            GameTooltip:Hide()
            StartGridDrag(mySpellName, "pool", nil, myTexPath, team, state)
        end)
        row:SetScript("OnDragStop", function()
            if not gridDrag.isDragging then return end
            local dropped = TryDropOnGridSlot(team, state)
            StopGridDrag()
            if dropped then
                addon:RefreshGridDisplay(team, state)
                addon:RefreshSpellPool(team, state)
                addon:RefreshAllBars()
            end
        end)

        row:Show()
        yOffset = yOffset + POOL_ROW_H
    end

    -- Hide excess
    for i = #available + 1, #state.poolRowPool do
        if state.poolRowPool[i] then state.poolRowPool[i]:Hide() end
    end

    scrollChild:SetHeight(math.max(yOffset + 10, 1))
end

---------------------------------------------------------------------------
-- Grid Builder: Class Filter Buttons
---------------------------------------------------------------------------
local function UpdateGridFilterButtons(state)
    for _, btn in ipairs(state.filterButtons) do
        local cc = addon.CLASS_COLORS[btn.filterKey]
        if btn.filterKey == state.currentClass then
            if cc then
                btn.bg:SetColorTexture(cc.r, cc.g, cc.b, 0.5)
            else
                btn.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
            end
            btn.text:SetTextColor(1, 1, 1)
        else
            if cc then
                btn.bg:SetColorTexture(cc.r * 0.15, cc.g * 0.15, cc.b * 0.15, 0.7)
                btn.text:SetTextColor(cc.r * 0.6, cc.g * 0.6, cc.b * 0.6)
            else
                btn.bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.9)
                btn.text:SetTextColor(0.50, 0.50, 0.50)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Grid Builder: Main Populate
---------------------------------------------------------------------------
local function PopulateGridBuilder(parent, team, state)
    -- Class filter bar
    local filterBar = CreateFrame("Frame", nil, parent)
    filterBar:SetPoint("TOPLEFT", 6, -6)
    filterBar:SetPoint("TOPRIGHT", -6, -6)
    filterBar:SetHeight(22)

    local filterBarBg = filterBar:CreateTexture(nil, "BACKGROUND")
    filterBarBg:SetAllPoints()
    filterBarBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.8)

    local classFilters = {
        { key = "Warrior",  label = "War" },
        { key = "Paladin",  label = "Pal" },
        { key = "Hunter",   label = "Hun" },
        { key = "Rogue",    label = "Rog" },
        { key = "Priest",   label = "Pri" },
        { key = "Mage",     label = "Mag" },
        { key = "Warlock",  label = "Wlk" },
        { key = "Shaman",   label = "Sha" },
        { key = "Druid",    label = "Dru" },
    }

    local BTN_W = 54
    local BTN_H = 16
    local BTN_PAD = 2

    wipe(state.filterButtons)

    for idx, f in ipairs(classFilters) do
        local btn = CreateFrame("Button", nil, filterBar)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOPLEFT", filterBar, "TOPLEFT",
            4 + (idx - 1) * (BTN_W + BTN_PAD), -3)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.bg = bg

        local cc = addon.CLASS_COLORS[f.key]
        if cc then
            bg:SetColorTexture(cc.r * 0.15, cc.g * 0.15, cc.b * 0.15, 0.7)
        else
            bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.9)
        end

        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(addon.FONT_DISPLAY, 9, "")
        text:SetPoint("CENTER")
        text:SetText(f.label)
        if cc then
            text:SetTextColor(cc.r * 0.6, cc.g * 0.6, cc.b * 0.6)
        else
            text:SetTextColor(0.50, 0.50, 0.50)
        end
        btn.text = text
        btn.filterKey = f.key

        btn:SetScript("OnEnter", function()
            if btn.filterKey ~= state.currentClass then
                if cc then
                    bg:SetColorTexture(cc.r * 0.25, cc.g * 0.25, cc.b * 0.25, 0.8)
                    text:SetTextColor(cc.r, cc.g, cc.b)
                else
                    bg:SetColorTexture(0.110, 0.110, 0.118, 0.9)
                    text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
                end
            end
            lib:ShowMicroTip(btn, f.key)
        end)
        btn:SetScript("OnLeave", function()
            UpdateGridFilterButtons(state)
            lib:HideMicroTip()
        end)
        btn:SetScript("OnClick", function()
            state.currentClass = f.key
            addon:RefreshGridDisplay(team, state)
            addon:RefreshSpellPool(team, state)
            UpdateGridFilterButtons(state)
        end)

        state.filterButtons[#state.filterButtons + 1] = btn
    end

    UpdateGridFilterButtons(state)

    -- Grid dimension controls (below class tabs)
    -- Rows: [-][N][+]   Cols: [-][N][+]   [Clear]
    -- Dimensions are per-team (shared across all classes)
    local teamSettings = (team == "party") and addon.db.party or addon.db.enemy

    local function ResizeAllGrids(newRows, newCols)
        teamSettings.gridRows = newRows
        teamSettings.gridCols = newCols
        -- Resize all existing class grids for this team
        local grids = addon.db.cooldowns.grids
        for className, teamGrids in pairs(grids) do
            if teamGrids[team] then
                addon:ResizeGrid(teamGrids[team], newRows, newCols)
            end
        end
    end

    local rowsLabel = parent:CreateFontString(nil, "OVERLAY")
    rowsLabel:SetFont(addon.FONT_BODY, 9, "")
    rowsLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -32)
    rowsLabel:SetText("Rows:")
    rowsLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    local rowsValue = parent:CreateFontString(nil, "OVERLAY")
    rowsValue:SetFont(addon.FONT_MONO, 11, "")
    rowsValue:SetPoint("LEFT", rowsLabel, "RIGHT", 2, 0)
    rowsValue:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    local function CreateMiniBtn(parentFrame, w, h, label)
        local btn = CreateFrame("Button", nil, parentFrame)
        btn:SetSize(w, h)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.9)
        btn.bg = bg

        local border = btn:CreateTexture(nil, "ARTWORK")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])
        btn.border = border

        local inner = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        inner:SetAllPoints()
        inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.9)
        btn.inner = inner

        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(addon.FONT_BODY, 10, "")
        text:SetPoint("CENTER", 0, 1)
        text:SetText(label)
        text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
        btn.text = text

        btn:SetScript("OnEnter", function()
            inner:SetColorTexture(0.110, 0.110, 0.118, 1)
            text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        end)
        btn:SetScript("OnLeave", function()
            inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.9)
            text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
        end)

        return btn
    end

    local rowsMinus = CreateMiniBtn(parent, 16, 16, "\226\128\147")
    rowsMinus:SetPoint("LEFT", rowsValue, "RIGHT", 3, 0)

    local rowsPlus = CreateMiniBtn(parent, 16, 16, "+")
    rowsPlus:SetPoint("LEFT", rowsMinus, "RIGHT", 2, 0)

    local colsLabel = parent:CreateFontString(nil, "OVERLAY")
    colsLabel:SetFont(addon.FONT_BODY, 9, "")
    colsLabel:SetPoint("LEFT", rowsPlus, "RIGHT", 12, 0)
    colsLabel:SetText("Cols:")
    colsLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    local colsValue = parent:CreateFontString(nil, "OVERLAY")
    colsValue:SetFont(addon.FONT_MONO, 11, "")
    colsValue:SetPoint("LEFT", colsLabel, "RIGHT", 2, 0)
    colsValue:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    local colsMinus = CreateMiniBtn(parent, 16, 16, "\226\128\147")
    colsMinus:SetPoint("LEFT", colsValue, "RIGHT", 3, 0)

    local colsPlus = CreateMiniBtn(parent, 16, 16, "+")
    colsPlus:SetPoint("LEFT", colsMinus, "RIGHT", 2, 0)

    local clearBtn = CreateMiniBtn(parent, 44, 16, "Clear")
    clearBtn:SetPoint("LEFT", colsPlus, "RIGHT", 12, 0)

    local function UpdateDimsDisplay()
        rowsValue:SetText(tostring(teamSettings.gridRows or 3))
        colsValue:SetText(tostring(teamSettings.gridCols or 4))
    end
    UpdateDimsDisplay()

    local function RefreshAfterResize()
        UpdateDimsDisplay()
        addon:RefreshGridDisplay(team, state)
        addon:RefreshSpellPool(team, state)
        addon:RefreshAllBars()
    end

    local function SetMiniBtnTooltip(btn, tipTitle)
        local origEnter = btn:GetScript("OnEnter")
        local origLeave = btn:GetScript("OnLeave")
        btn:SetScript("OnEnter", function(self2)
            if origEnter then origEnter(self2) end
            lib:ShowMicroTip(self2, tipTitle)
        end)
        btn:SetScript("OnLeave", function(self2)
            if origLeave then origLeave(self2) end
            lib:HideMicroTip()
        end)
    end
    SetMiniBtnTooltip(rowsMinus, "Remove Row")
    SetMiniBtnTooltip(rowsPlus, "Add Row")
    SetMiniBtnTooltip(colsMinus, "Remove Column")
    SetMiniBtnTooltip(colsPlus, "Add Column")

    rowsMinus:SetScript("OnClick", function()
        local curRows = teamSettings.gridRows or 3
        if curRows > 1 then
            ResizeAllGrids(curRows - 1, teamSettings.gridCols or 4)
            RefreshAfterResize()
        end
    end)
    rowsPlus:SetScript("OnClick", function()
        local curRows = teamSettings.gridRows or 3
        if curRows < 8 then
            ResizeAllGrids(curRows + 1, teamSettings.gridCols or 4)
            RefreshAfterResize()
        end
    end)
    colsMinus:SetScript("OnClick", function()
        local curCols = teamSettings.gridCols or 4
        if curCols > 1 then
            ResizeAllGrids(teamSettings.gridRows or 3, curCols - 1)
            RefreshAfterResize()
        end
    end)
    colsPlus:SetScript("OnClick", function()
        local curCols = teamSettings.gridCols or 4
        if curCols < 8 then
            ResizeAllGrids(teamSettings.gridRows or 3, curCols + 1)
            RefreshAfterResize()
        end
    end)
    clearBtn:SetScript("OnClick", function()
        local grid = addon:GetClassGrid(state.currentClass, team)
        if grid then
            if not grid.removed then grid.removed = {} end
            local total = (teamSettings.gridRows or 3) * (teamSettings.gridCols or 4)
            for i = 1, total do
                if grid.slots[i] and grid.slots[i] ~= "" then
                    grid.removed[grid.slots[i]] = true
                end
                grid.slots[i] = ""
                grid.disabled[i] = nil
            end
            RefreshAfterResize()
        end
    end)
    clearBtn:SetScript("OnEnter", function(self2)
        self2.inner:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3], 1)
        self2.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        lib:ShowMicroTip(self2, "Clear all slots")
    end)
    clearBtn:SetScript("OnLeave", function(self2)
        self2.inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.9)
        self2.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
        lib:HideMicroTip()
    end)

    -- Save a reference so dims display updates when class changes
    state.updateDimsDisplay = UpdateDimsDisplay

    -- Grid area (below size controls, height adjusts to grid size)
    local gridArea = CreateFrame("Frame", nil, parent)
    gridArea:SetPoint("TOPLEFT", 6, -50)
    gridArea:SetPoint("TOPRIGHT", -6, -50)
    -- Height set dynamically in RefreshGridDisplay
    gridArea:SetHeight(160)
    state.gridArea = gridArea

    local gridAreaBg = gridArea:CreateTexture(nil, "BACKGROUND")
    gridAreaBg:SetAllPoints()
    gridAreaBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.6)

    local gridLabel = gridArea:CreateFontString(nil, "OVERLAY")
    gridLabel:SetFont(addon.FONT_DISPLAY, 9, "")
    gridLabel:SetPoint("TOPLEFT", 4, -2)
    gridLabel:SetText("GRID")
    gridLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    state.gridParent = CreateFrame("Frame", nil, gridArea)
    state.gridParent:SetPoint("TOPLEFT", 6, -14)
    state.gridParent:SetPoint("TOPRIGHT", -6, -14)
    -- Height set dynamically

    -- Pool area (anchored to bottom of gridArea)
    local poolLabel = parent:CreateFontString(nil, "OVERLAY")
    poolLabel:SetFont(addon.FONT_DISPLAY, 9, "")
    poolLabel:SetPoint("TOPLEFT", gridArea, "BOTTOMLEFT", 4, -4)
    poolLabel:SetText("AVAILABLE SPELLS")
    poolLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- Pool search box
    local searchBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    searchBox:SetSize(140, 18)
    searchBox:SetPoint("LEFT", poolLabel, "RIGHT", 10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont(addon.FONT_BODY, 10, "")
    searchBox:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    local searchHint = parent:CreateFontString(nil, "OVERLAY")
    searchHint:SetFont(addon.FONT_BODY, 9, "")
    searchHint:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    searchHint:SetText("Search")
    searchHint:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    searchBox:SetScript("OnTextChanged", function(self2)
        state.searchText = self2:GetText()
        addon:RefreshSpellPool(team, state)
    end)
    searchBox:SetScript("OnEscapePressed", function(self2)
        self2:ClearFocus()
    end)

    -- Pool scroll frame (anchored below pool label)
    local scrollName = "TrinketedCD" .. team:sub(1, 1):upper() .. team:sub(2) .. "GridPoolScroll"
    local scrollFrame = CreateFrame("ScrollFrame", scrollName,
        parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", poolLabel, "BOTTOMLEFT", -1, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(520, 1)
    scrollFrame:SetScrollChild(scrollChild)
    state.scrollChild = scrollChild

    -- Hook class change to also update size display
    for _, btn in ipairs(state.filterButtons) do
        local oldClick = btn:GetScript("OnClick")
        btn:SetScript("OnClick", function()
            if oldClick then oldClick() end
            UpdateDimsDisplay()
        end)
    end

    -- Initial refresh
    addon:RefreshGridDisplay(team, state)
    addon:RefreshSpellPool(team, state)
end

---------------------------------------------------------------------------
-- Party Tab (Settings / Spells inner tabs)
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Spells Tab (Grid Builder, promoted from Party sub-tab)
---------------------------------------------------------------------------
function addon:PopulateSpellsTab(parent)
    PopulateGridBuilder(parent, "party", gridBuilderState.party)
end

---------------------------------------------------------------------------
-- Test Mode Tab
---------------------------------------------------------------------------
function addon:PopulateTestModeTab(parent)
    local y = -10

    y = lib:CreateSectionHeader(parent, y, "TEST MODE")
    y = y - 2

    local desc = parent:CreateFontString(nil, "OVERLAY")
    desc:SetFont(addon.FONT_BODY, 10, "")
    desc:SetPoint("TOPLEFT", 10, y)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText("Preview and position cooldown bars without being in an arena. Click cooldown icons to simulate usage.")
    desc:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    y = y - 26

    -- Action buttons row
    local testToggle = lib:CreateCheckbox(parent, 10, y, "Test mode",
        addon.state.testMode, function(on)
            if on ~= addon.state.testMode then
                addon:ToggleTestMode()
            end
        end)
    self._testToggle = testToggle

    lib:CreateButton(parent, 160, y, 150, "Simulate All CDs", function()
        addon:SimulateAllCooldowns()
    end)
    lib:CreateButton(parent, 320, y, 140, "Clear All CDs", function()
        addon:ClearAllTestCooldowns()
    end)
    y = y - 38

    -- Party player slots
    local partyLabel = parent:CreateFontString(nil, "OVERLAY")
    partyLabel:SetFont(addon.FONT_BODY, 11, "")
    partyLabel:SetPoint("TOPLEFT", 10, y)
    partyLabel:SetText("Party Players")
    partyLabel:SetTextColor(C.partyBlue[1], C.partyBlue[2], C.partyBlue[3])

    local partyLine = parent:CreateTexture(nil, "ARTWORK")
    partyLine:SetPoint("TOPLEFT", 10, y - 14)
    partyLine:SetSize(480, 1)
    partyLine:SetColorTexture(C.partyBlue[1], C.partyBlue[2], C.partyBlue[3], 0.25)

    y = y - 22

    for i = 1, 4 do
        local slotLabel = parent:CreateFontString(nil, "OVERLAY")
        slotLabel:SetFont(addon.FONT_BODY, 10, "")
        slotLabel:SetPoint("TOPLEFT", 10, y)
        slotLabel:SetText(i .. ".")
        slotLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        local slotIndex = i
        local currentClass = "Warrior"
        local currentRace = "Human"
        if self.db and self.db.testMode.lastPlayers and self.db.testMode.lastPlayers[i] then
            currentClass = self.db.testMode.lastPlayers[i].class or "Warrior"
            currentRace = self.db.testMode.lastPlayers[i].race or "Human"
        end

        local classDDName = "TrinketedCDTestClassDD_" .. i
        local classDD = CreateFrame("Frame", classDDName, parent, "UIDropDownMenuTemplate")
        classDD:SetPoint("TOPLEFT", 16, y + 5)
        UIDropDownMenu_SetWidth(classDD, 95)
        UIDropDownMenu_Initialize(classDD, function(self2, level)
            for _, class in ipairs(addon.ALL_CLASSES) do
                local info = UIDropDownMenu_CreateInfo()
                local cc = addon.CLASS_COLORS[class]
                if cc then
                    info.text = "|c" .. cc.hex .. class .. "|r"
                else
                    info.text = class
                end
                info.func = function()
                    UIDropDownMenu_SetText(classDD, "|c" .. (cc and cc.hex or "ffffffff") .. class .. "|r")
                    addon:UpdateTestSlot(slotIndex, class, currentRace)
                    currentClass = class
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local cc = addon.CLASS_COLORS[currentClass]
        UIDropDownMenu_SetText(classDD, "|c" .. (cc and cc.hex or "ffffffff") .. currentClass .. "|r")

        local raceDDName = "TrinketedCDTestRaceDD_" .. i
        local raceDD = CreateFrame("Frame", raceDDName, parent, "UIDropDownMenuTemplate")
        raceDD:SetPoint("TOPLEFT", 150, y + 5)
        UIDropDownMenu_SetWidth(raceDD, 75)
        UIDropDownMenu_Initialize(raceDD, function(self2, level)
            for _, race in ipairs(addon.ALL_RACES) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = race
                info.func = function()
                    UIDropDownMenu_SetText(raceDD, race)
                    addon:UpdateTestSlot(slotIndex, currentClass, race)
                    currentRace = race
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        UIDropDownMenu_SetText(raceDD, currentRace)

        y = y - 28
    end
end
