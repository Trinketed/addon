---------------------------------------------------------------------------
-- TrinketedLib: OptionsPanel.lua
-- Master options frame with sidebar navigation for sub-addon tabs
---------------------------------------------------------------------------
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local masterFrame = nil
local sidebar = nil
local contentArea = nil
local sidebarButtons = {}
local activeSubAddon = nil
local SIDEBAR_W = 140
local FRAME_W = 932
local FRAME_H = 520

---------------------------------------------------------------------------
-- Build Master Frame (lazy, created on first open)
---------------------------------------------------------------------------
local function BuildMasterFrame()
    if masterFrame then return end

    masterFrame = CreateFrame("Frame", "TrinketedOptionsFrame", UIParent, "BackdropTemplate")
    masterFrame:SetSize(FRAME_W, FRAME_H)
    masterFrame:SetPoint("CENTER")
    masterFrame:SetFrameStrata("DIALOG")
    masterFrame:SetFrameLevel(100)
    masterFrame:SetMovable(true)
    masterFrame:EnableMouse(true)
    masterFrame:RegisterForDrag("LeftButton")
    masterFrame:SetScript("OnDragStart", masterFrame.StartMoving)
    masterFrame:SetScript("OnDragStop", masterFrame.StopMovingOrSizing)
    masterFrame:SetClampedToScreen(true)
    masterFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    masterFrame:SetBackdropColor(C.frameBg[1], C.frameBg[2], C.frameBg[3], C.frameBg[4])
    masterFrame:SetBackdropBorderColor(C.frameBorder[1], C.frameBorder[2], C.frameBorder[3], C.frameBorder[4])
    masterFrame:Hide()

    table.insert(UISpecialFrames, "TrinketedOptionsFrame")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, masterFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)

    ---------------------------------------------------------------------------
    -- Sidebar
    ---------------------------------------------------------------------------
    sidebar = CreateFrame("Frame", nil, masterFrame)
    sidebar:SetPoint("TOPLEFT", 6, -6)
    sidebar:SetPoint("BOTTOMLEFT", 6, 6)
    sidebar:SetWidth(SIDEBAR_W)

    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], C.sidebarBg[4])

    -- Brand header
    local brandText = sidebar:CreateFontString(nil, "OVERLAY")
    brandText:SetFont(lib.FONT_DISPLAY, 13, "OUTLINE")
    brandText:SetPoint("TOP", sidebar, "TOP", 0, -14)
    brandText:SetText("|cffE8B923T|r|cffF4F4F5RINKETED|r")

    local verText = sidebar:CreateFontString(nil, "OVERLAY")
    verText:SetFont(lib.FONT_MONO, 9, "")
    verText:SetPoint("TOP", brandText, "BOTTOM", 0, -3)
    verText:SetText(lib:GetVersion())
    verText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    local brandSep = sidebar:CreateTexture(nil, "ARTWORK")
    brandSep:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -42)
    brandSep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -10, -42)
    brandSep:SetHeight(1)
    brandSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

    ---------------------------------------------------------------------------
    -- Content area
    ---------------------------------------------------------------------------
    contentArea = CreateFrame("Frame", nil, masterFrame)
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    contentArea:SetPoint("BOTTOMRIGHT", masterFrame, "BOTTOMRIGHT", -6, 6)
end

---------------------------------------------------------------------------
-- Populate Sidebar (called when panel opens, reflects registered sub-addons)
---------------------------------------------------------------------------
local function PopulateSidebar()
    for _, btn in ipairs(sidebarButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(sidebarButtons)

    local sorted = lib:GetSortedSubAddons()
    local TAB_H = 30
    local TAB_START_Y = -52

    for i, entry in ipairs(sorted) do
        local tab = CreateFrame("Button", "TrinketedSideTab" .. i, sidebar)
        tab:SetSize(SIDEBAR_W, TAB_H)
        tab:SetPoint("TOPLEFT", 0, TAB_START_Y - (i - 1) * TAB_H)

        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)
        tab.bg = bg

        local indicator = tab:CreateTexture(nil, "OVERLAY")
        indicator:SetPoint("TOPLEFT", 0, 0)
        indicator:SetPoint("BOTTOMLEFT", 0, 0)
        indicator:SetWidth(3)
        indicator:SetColorTexture(0, 0, 0, 0)
        tab.indicator = indicator

        local text = tab:CreateFontString(nil, "OVERLAY")
        text:SetFont(lib.FONT_BODY, 11, "")
        text:SetPoint("LEFT", 16, 0)
        text:SetText(entry.name)
        text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        tab.text = text

        tab.isActive = false
        tab.subAddonName = entry.name

        tab:SetScript("OnEnter", function()
            if not tab.isActive then
                bg:SetColorTexture(C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4])
                text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
            end
        end)
        tab:SetScript("OnLeave", function()
            if not tab.isActive then
                bg:SetColorTexture(0, 0, 0, 0)
                text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end
        end)
        tab:SetScript("OnClick", function()
            lib:SelectSubAddon(entry.name)
        end)

        sidebarButtons[i] = tab
    end
end

---------------------------------------------------------------------------
-- Select a sub-addon tab
---------------------------------------------------------------------------
function lib:SelectSubAddon(name)
    local entry = self.subAddons[name]
    if not entry then return end

    -- Update sidebar visuals
    for _, btn in ipairs(sidebarButtons) do
        if btn.subAddonName == name then
            btn.bg:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3], C.tabActive[4])
            btn.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            btn.text:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
            btn.isActive = true
        else
            btn.bg:SetColorTexture(0, 0, 0, 0)
            btn.indicator:SetColorTexture(0, 0, 0, 0)
            btn.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            btn.isActive = false
        end
    end

    -- Hide previous content
    if activeSubAddon and activeSubAddon.contentFrame then
        activeSubAddon.contentFrame:Hide()
    end

    -- Show or create content for selected sub-addon
    if not entry.contentFrame then
        entry.contentFrame = CreateFrame("Frame", nil, contentArea)
        entry.contentFrame:SetAllPoints(contentArea)
        if entry.OnSelect then
            entry.OnSelect(entry.contentFrame)
        end
    else
        entry.contentFrame:Show()
    end

    activeSubAddon = entry
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function lib:ToggleOptionsPanel()
    BuildMasterFrame()
    if masterFrame:IsShown() then
        masterFrame:Hide()
    else
        self:ShowOptionsPanel()
    end
end

function lib:ShowOptionsPanel(subAddonName)
    BuildMasterFrame()
    PopulateSidebar()

    if subAddonName and self.subAddons[subAddonName] then
        self:SelectSubAddon(subAddonName)
    elseif not activeSubAddon then
        local sorted = self:GetSortedSubAddons()
        if sorted[1] then
            self:SelectSubAddon(sorted[1].name)
        end
    end

    masterFrame:Show()
end

function lib:HideOptionsPanel()
    if masterFrame then
        masterFrame:Hide()
    end
end

function lib:IsOptionsPanelShown()
    return masterFrame and masterFrame:IsShown()
end

function lib:GetContentWidth()
    return FRAME_W - SIDEBAR_W - 12
end
