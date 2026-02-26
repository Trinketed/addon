# Trinketed Addon Suite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the Trinketed addon from a VOD timestamp recorder into a parent addon suite framework with shared library (TrinketedLib), unified options panel, and sub-addon architecture.

**Architecture:** Parent addon (Trinketed) loads TrinketedLib via LibStub, which provides shared fonts, colors, UI widgets, and a master options panel with sidebar tabs. Sub-addons (TrinketedCD, TrinketedHistory) register as sidebar entries and sub-commands via TrinketedLib. BigWigs packager handles git submodules → sibling AddOn folders.

**Tech Stack:** Lua 5.1 (WoW TBC Anniversary, Interface 110207), LibStub, BigWigs packager, GitHub Actions

---

### Task 1: Create TrinketedLib.lua — LibStub Registration, Fonts, Colors

**Files:**
- Create: `TrinketedLib/TrinketedLib.lua`

**Context:** This is the foundation. Extracted from TrinketedCD's `Core.lua:14-16` (fonts) and `Options.lua:21-56` (color palette). All sub-addons will depend on this.

**Step 1: Create the TrinketedLib directory**

```bash
mkdir -p "TrinketedLib"
```

**Step 2: Write TrinketedLib.lua**

```lua
---------------------------------------------------------------------------
-- TrinketedLib: Core
-- LibStub registration, shared constants, font paths, color palette
---------------------------------------------------------------------------
local MAJOR, MINOR = "TrinketedLib-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

---------------------------------------------------------------------------
-- Font Paths (files live in parent addon: Trinketed/Fonts/)
---------------------------------------------------------------------------
lib.FONT_DISPLAY = "Interface\\AddOns\\Trinketed\\Fonts\\SpaceGrotesk-Bold.ttf"
lib.FONT_BODY    = "Interface\\AddOns\\Trinketed\\Fonts\\Inter-Regular.ttf"
lib.FONT_MONO    = "Interface\\AddOns\\Trinketed\\Fonts\\JetBrainsMono-Regular.ttf"

---------------------------------------------------------------------------
-- Color Palette
---------------------------------------------------------------------------
lib.C = {
    -- Surfaces (brand layered dark: deep > base > raised > elevated)
    frameBg     = { 0.078, 0.078, 0.086, 0.97 },
    frameBorder = { 0.35, 0.30, 0.15, 0.6 },
    sidebarBg   = { 0.039, 0.039, 0.039, 1 },
    tabActive   = { 0.110, 0.110, 0.118, 1 },
    tabHover    = { 0.078, 0.078, 0.086, 1 },

    -- Gold accent
    accent      = { 0.91, 0.73, 0.14 },
    accentGlow  = { 0.96, 0.82, 0.31 },
    accentDim   = { 0.55, 0.45, 0.20, 0.35 },

    -- Text hierarchy (4 tiers)
    textBright  = { 0.957, 0.957, 0.961 },
    textNormal  = { 0.612, 0.639, 0.686 },
    textDim     = { 0.361, 0.369, 0.400 },
    textMuted   = { 0.290, 0.290, 0.322 },

    -- Borders
    borderSubtle  = { 0.165, 0.165, 0.184 },
    borderDefault = { 0.227, 0.227, 0.259 },

    -- Surfaces (additional)
    bgElevated  = { 0.133, 0.133, 0.149 },
    bgRaised    = { 0.110, 0.110, 0.118 },

    -- Structural
    divider     = { 0.35, 0.30, 0.15, 0.25 },
    rowHover    = { 1, 1, 1, 0.04 },
    contentBg   = { 0.055, 0.055, 0.060, 0.5 },

    -- Semantic team colors
    partyBlue   = { 0.271, 0.482, 0.616 },
    enemyRed    = { 0.902, 0.224, 0.224 },
}

---------------------------------------------------------------------------
-- Sub-Addon Registry
---------------------------------------------------------------------------
lib.subAddons = lib.subAddons or {}
lib.subCommands = lib.subCommands or {}

function lib:RegisterSubAddon(name, opts)
    -- opts = { order=number, OnSelect=function(contentFrame), icon=string(optional) }
    opts.name = name
    self.subAddons[name] = opts
end

function lib:RegisterSubCommand(name, handler)
    self.subCommands[name:lower()] = handler
end

function lib:GetSubCommand(name)
    return self.subCommands[name:lower()]
end

function lib:GetSortedSubAddons()
    local list = {}
    for _, entry in pairs(self.subAddons) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
    return list
end
```

**Step 3: Verify file exists**

```bash
ls TrinketedLib/TrinketedLib.lua
```

**Step 4: Commit**

```bash
git add TrinketedLib/TrinketedLib.lua
git commit -m "feat: add TrinketedLib core — LibStub registration, fonts, colors, sub-addon registry"
```

---

### Task 2: Create TrinketedLib Widgets.lua — Shared UI Components

**Files:**
- Create: `TrinketedLib/Widgets.lua`

**Context:** Extracted from TrinketedCD's `Options.lua:61-284`. These are the micro-tip system, CreateSectionHeader, CreateCheckbox (toggle chip), CreateSlider, and CreateButton. Converted from local functions to `lib:Method()` calls. All references to `addon.FONT_*` become `lib.FONT_*`, all references to local `C` become `lib.C`.

**Step 1: Write Widgets.lua**

```lua
---------------------------------------------------------------------------
-- TrinketedLib: Widgets.lua
-- Shared UI components: checkboxes, sliders, buttons, section headers, tooltips
---------------------------------------------------------------------------
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

---------------------------------------------------------------------------
-- Micro-Tooltip (lightweight label for small controls)
---------------------------------------------------------------------------
local microTip = CreateFrame("Frame", nil, UIParent)
microTip:SetFrameStrata("TOOLTIP")
microTip:Hide()

local microTipBg = microTip:CreateTexture(nil, "BACKGROUND")
microTipBg:SetAllPoints()
microTipBg:SetColorTexture(0.039, 0.039, 0.039, 0.92)

local microTipText = microTip:CreateFontString(nil, "OVERLAY")
microTipText:SetFont(lib.FONT_BODY, 10, "")
microTipText:SetPoint("CENTER", 0, 0)
microTipText:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

function lib:ShowMicroTip(owner, text, anchor, offX, offY)
    microTipText:SetText(text)
    local tw = microTipText:GetStringWidth() or 40
    local th = microTipText:GetStringHeight() or 12
    microTip:SetSize(tw + 10, th + 6)
    microTip:ClearAllPoints()
    microTip:SetPoint(anchor or "TOP", owner, "BOTTOM", offX or 0, offY or -4)
    microTip:Show()
end

function lib:HideMicroTip()
    microTip:Hide()
end

---------------------------------------------------------------------------
-- Section Header
---------------------------------------------------------------------------
function lib:CreateSectionHeader(parent, y, text, contentWidth)
    local w = contentWidth or 520
    local header = parent:CreateFontString(nil, "OVERLAY")
    header:SetFont(self.FONT_DISPLAY, 10, "")
    header:SetPoint("TOPLEFT", 8, y)
    header:SetText(text)
    header:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("LEFT", header, "RIGHT", 8, 0)
    line:SetSize(w - 8, 1)
    line:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])
    line:SetPoint("RIGHT", parent, "RIGHT", -8, 0)

    return y - 22
end

---------------------------------------------------------------------------
-- Toggle Chip (Checkbox)
---------------------------------------------------------------------------
local function SetToggleBorder(tog, r, g, b, a)
    tog.borderTop:SetColorTexture(r, g, b, a)
    tog.borderBot:SetColorTexture(r, g, b, a)
    tog.borderL:SetColorTexture(r, g, b, a)
    tog.borderR:SetColorTexture(r, g, b, a)
end

local function UpdateToggleVisual(tog)
    if tog.isOn then
        tog.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
        SetToggleBorder(tog, C.accent[1], C.accent[2], C.accent[3], 0.35)
        tog.pip:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        tog.label:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    else
        tog.bg:SetColorTexture(0, 0, 0, 0)
        SetToggleBorder(tog, C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
        tog.pip:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.6)
        tog.label:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    end
end

function lib:CreateCheckbox(parent, x, y, label, checked, onClick)
    local chipH = 22

    local tog = CreateFrame("Button", nil, parent)
    tog:SetPoint("TOPLEFT", x, y)
    tog:SetSize(120, chipH)

    tog.bg = tog:CreateTexture(nil, "BACKGROUND")
    tog.bg:SetAllPoints()

    tog.borderTop = tog:CreateTexture(nil, "ARTWORK")
    tog.borderTop:SetPoint("TOPLEFT"); tog.borderTop:SetPoint("TOPRIGHT")
    tog.borderTop:SetHeight(1)

    tog.borderBot = tog:CreateTexture(nil, "ARTWORK")
    tog.borderBot:SetPoint("BOTTOMLEFT"); tog.borderBot:SetPoint("BOTTOMRIGHT")
    tog.borderBot:SetHeight(1)

    tog.borderL = tog:CreateTexture(nil, "ARTWORK")
    tog.borderL:SetPoint("TOPLEFT"); tog.borderL:SetPoint("BOTTOMLEFT")
    tog.borderL:SetWidth(1)

    tog.borderR = tog:CreateTexture(nil, "ARTWORK")
    tog.borderR:SetPoint("TOPRIGHT"); tog.borderR:SetPoint("BOTTOMRIGHT")
    tog.borderR:SetWidth(1)

    tog.pip = tog:CreateTexture(nil, "OVERLAY")
    tog.pip:SetSize(6, 6)
    tog.pip:SetPoint("LEFT", 8, 0)

    tog.label = tog:CreateFontString(nil, "OVERLAY")
    tog.label:SetFont(self.FONT_BODY, 11, "")
    tog.label:SetPoint("LEFT", tog.pip, "RIGHT", 6, 0)
    tog.label:SetText(label)

    tog.isOn = checked and true or false
    UpdateToggleVisual(tog)

    local resized = false
    tog:SetScript("OnUpdate", function()
        if resized then return end
        local textW = tog.label:GetStringWidth()
        if textW and textW > 0 then
            tog:SetWidth(8 + 6 + textW + 12)
            resized = true
            tog:SetScript("OnUpdate", nil)
        end
    end)

    tog:SetScript("OnClick", function()
        tog.isOn = not tog.isOn
        UpdateToggleVisual(tog)
        if onClick then onClick(tog.isOn) end
    end)

    tog:SetScript("OnEnter", function()
        if tog.isOn then
            tog.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
            SetToggleBorder(tog, C.accent[1], C.accent[2], C.accent[3], 0.5)
            tog.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        else
            tog.bg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)
            SetToggleBorder(tog, C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
            tog.pip:SetColorTexture(C.textNormal[1], C.textNormal[2], C.textNormal[3], 0.9)
            tog.label:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
        end
    end)
    tog:SetScript("OnLeave", function()
        UpdateToggleVisual(tog)
    end)

    tog.GetChecked = function() return tog.isOn end
    tog.SetChecked = function(_, val)
        tog.isOn = val and true or false
        UpdateToggleVisual(tog)
    end

    return tog
end

---------------------------------------------------------------------------
-- Slider
---------------------------------------------------------------------------
function lib:CreateSlider(parent, x, y, label, minVal, maxVal, step, current, onChange)
    local sliderLabel = parent:CreateFontString(nil, "OVERLAY")
    sliderLabel:SetFont(self.FONT_BODY, 11, "")
    sliderLabel:SetPoint("TOPLEFT", x, y)
    sliderLabel:SetText(label)
    sliderLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x + 10, y - 16)
    slider:SetSize(200, 17)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(current)

    local valText = slider:CreateFontString(nil, "OVERLAY")
    valText:SetFont(self.FONT_MONO, 10, "")
    valText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valText:SetText(tostring(math.floor(current)))
    valText:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    slider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value)
        valText:SetText(tostring(rounded))
        if onChange then onChange(rounded) end
    end)

    return slider, sliderLabel
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
function lib:CreateButton(parent, x, y, width, text, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", x, y)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.078, 0.078, 0.086, 1)

    local border = btn:CreateTexture(nil, "ARTWORK")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

    local inner = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    inner:SetAllPoints()
    inner:SetColorTexture(0.078, 0.078, 0.086, 1)

    local btnLabel = btn:CreateFontString(nil, "OVERLAY")
    btnLabel:SetFont(self.FONT_BODY, 10, "")
    btnLabel:SetPoint("CENTER", 0, 0)
    btnLabel:SetText(text)
    btnLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    btn:SetScript("OnEnter", function()
        inner:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3], 1)
        btnLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    btn:SetScript("OnLeave", function()
        inner:SetColorTexture(0.078, 0.078, 0.086, 1)
        btnLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end
```

**Step 2: Commit**

```bash
git add TrinketedLib/Widgets.lua
git commit -m "feat: add TrinketedLib widgets — checkbox, slider, button, section header, micro-tip"
```

---

### Task 3: Create TrinketedLib OptionsPanel.lua — Master Options Frame

**Files:**
- Create: `TrinketedLib/OptionsPanel.lua`

**Context:** This creates the master options frame that `/trinketed` opens. The sidebar lists registered sub-addons. Based on TrinketedCD's `Options.lua:310-415` frame/sidebar creation pattern, but generalized. Sub-addons call `lib:RegisterSubAddon()` then their `OnSelect(contentFrame)` is called when their sidebar tab is clicked.

**Step 1: Write OptionsPanel.lua**

```lua
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
local FRAME_W = 800
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
    verText:SetText("")  -- sub-addons can set this if needed
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
    -- Clear existing buttons
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

    -- Select requested tab, or first available
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

function lib:GetContentWidth()
    return FRAME_W - SIDEBAR_W - 12  -- minus padding
end
```

**Step 2: Commit**

```bash
git add TrinketedLib/OptionsPanel.lua
git commit -m "feat: add TrinketedLib options panel — master frame with sidebar sub-addon tabs"
```

---

### Task 4: Move Fonts to Parent Addon

**Files:**
- Move: `../TrinketedCD/Fonts/Inter-Regular.ttf` → `Fonts/Inter-Regular.ttf`
- Move: `../TrinketedCD/Fonts/JetBrainsMono-Regular.ttf` → `Fonts/JetBrainsMono-Regular.ttf`
- Move: `../TrinketedCD/Fonts/SpaceGrotesk-Bold.ttf` → `Fonts/SpaceGrotesk-Bold.ttf`

**Step 1: Create Fonts directory and copy files**

```bash
mkdir -p Fonts
cp ../TrinketedCD/Fonts/Inter-Regular.ttf Fonts/
cp ../TrinketedCD/Fonts/JetBrainsMono-Regular.ttf Fonts/
cp ../TrinketedCD/Fonts/SpaceGrotesk-Bold.ttf Fonts/
```

**Step 2: Verify files exist**

```bash
ls -la Fonts/
```

Expected: 3 `.ttf` files present.

**Step 3: Commit**

```bash
git add Fonts/
git commit -m "feat: move shared fonts to parent addon"
```

---

### Task 5: Rewrite Trinketed.toc and Trinketed.lua

**Files:**
- Modify: `Trinketed.toc` (complete rewrite)
- Modify: `Trinketed.lua` (complete rewrite)

**Context:** The current Trinketed.toc loads LibDeflate and the VOD timestamp code. The new one loads LibStub + TrinketedLib and a minimal loader. The VOD code moves to TrinketedHistory later.

**Step 1: Rewrite Trinketed.toc**

Replace entire contents with:

```
## Interface: 110207
## Title: Trinketed
## Notes: Trinketed addon suite framework
## Author: apwek
## Version: @project-version@
## SavedVariables: TrinketedDB

Libs\LibStub\LibStub.lua
TrinketedLib\TrinketedLib.lua
TrinketedLib\Widgets.lua
TrinketedLib\OptionsPanel.lua
Trinketed.lua
```

**Step 2: Rewrite Trinketed.lua**

Replace entire contents with:

```lua
---------------------------------------------------------------------------
-- Trinketed: Parent Addon Loader
-- Slash command dispatch, minimal initialization
---------------------------------------------------------------------------
local addonName, addon = ...
Trinketed = addon

local lib = LibStub("TrinketedLib-1.0")

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------
SLASH_TRINKETED1 = "/trinketed"
SLASH_TRINKETED2 = "/trink"
SlashCmdList["TRINKETED"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$") or ""

    if msg == "" then
        lib:ToggleOptionsPanel()
        return
    end

    -- Split first word from rest
    local cmd, args = msg:match("^(%S+)%s*(.*)$")
    if not cmd then
        lib:ToggleOptionsPanel()
        return
    end

    local handler = lib:GetSubCommand(cmd)
    if handler then
        handler(args)
    elseif cmd == "help" then
        print("|cffE8B923Trinketed|r commands:")
        print("  |cffF4F4F5/trinketed|r — open settings")
        -- List registered sub-commands
        local seen = {}
        for name in pairs(lib.subCommands) do
            if not seen[name] then
                print("  |cffF4F4F5/trinketed " .. name .. "|r")
                seen[name] = true
            end
        end
    else
        print("|cffE8B923Trinketed:|r Unknown command '|cffF4F4F5" .. cmd .. "|r'. Type |cffF4F4F5/trinketed help|r")
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Initialize SavedVariables
    TrinketedDB = TrinketedDB or {}

    print("|cffE8B923Trinketed|r loaded — |cffF4F4F5/trinketed|r or |cffF4F4F5/trink|r")
end)
```

**Step 3: Remove old files no longer needed**

Remove `Libs/LibDeflate/` (will move to TrinketedHistory when built) and `DECODER_PROMPT.md`:

```bash
rm -rf Libs/LibDeflate
rm -f DECODER_PROMPT.md
```

**Step 4: Verify the .toc references valid files**

```bash
# Check all files referenced in the .toc exist
ls Libs/LibStub/LibStub.lua
ls TrinketedLib/TrinketedLib.lua
ls TrinketedLib/Widgets.lua
ls TrinketedLib/OptionsPanel.lua
ls Trinketed.lua
```

**Step 5: Commit**

```bash
git add Trinketed.toc Trinketed.lua
git rm -r Libs/LibDeflate
git rm DECODER_PROMPT.md
git commit -m "feat: rewrite parent addon as suite framework with unified slash commands"
```

---

### Task 6: Refactor TrinketedCD — Remove Extracted Code, Wire Up TrinketedLib

**Files:**
- Modify: `../TrinketedCD/TrinketedCD.toc`
- Modify: `../TrinketedCD/Core.lua` (lines 14-16: fonts, lines 255-273: slash commands)
- Modify: `../TrinketedCD/Options.lua` (lines 8-10: frame/content refs, lines 21-56: color palette, lines 61-284: widgets/micro-tip, lines 289-415: sidebar/frame creation, line 646: ShowOptions)

**Context:** TrinketedCD now depends on Trinketed. It uses TrinketedLib for fonts, colors, widgets. It registers as a sub-addon in the master options panel instead of creating its own frame. This is the largest task — it's a mechanical refactor of Options.lua.

**Step 1: Update TrinketedCD.toc**

Replace entire contents with:

```
## Interface: 110207
## Title: Trinketed - Cooldowns
## Notes: Arena cooldown tracker
## Author: apwek
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

Key changes:
- `## Title: Trinketed - Cooldowns` (grouped display name)
- `## Dependencies: Trinketed` (load order + parent required)
- Removed `Libs\LibStub\LibStub.lua` (loaded by parent)

**Step 2: Update Core.lua**

Replace font constants (lines 14-16) to use TrinketedLib:

```lua
-- REPLACE lines 14-16:
-- addon.FONT_DISPLAY = "Interface\\AddOns\\TrinketedCD\\Fonts\\SpaceGrotesk-Bold.ttf"
-- addon.FONT_BODY    = "Interface\\AddOns\\TrinketedCD\\Fonts\\Inter-Regular.ttf"
-- addon.FONT_MONO    = "Interface\\AddOns\\TrinketedCD\\Fonts\\JetBrainsMono-Regular.ttf"
-- WITH:
local TrinketedLib = LibStub("TrinketedLib-1.0")
addon.FONT_DISPLAY = TrinketedLib.FONT_DISPLAY
addon.FONT_BODY    = TrinketedLib.FONT_BODY
addon.FONT_MONO    = TrinketedLib.FONT_MONO
```

Replace slash commands (lines 255-273) to register sub-commands via TrinketedLib:

```lua
-- REPLACE lines 252-273 (the entire slash command section) WITH:
---------------------------------------------------------------------------
-- Sub-Command Registration (unified under /trinketed)
---------------------------------------------------------------------------
local function RegisterSubCommands()
    local lib = LibStub("TrinketedLib-1.0")

    -- Opening options panel to Cooldowns tab
    local function openCD(args)
        if args == "" then
            lib:ShowOptionsPanel("Cooldowns")
        end
    end
    lib:RegisterSubCommand("cd", openCD)
    lib:RegisterSubCommand("cooldown", openCD)
    lib:RegisterSubCommand("cooldowns", openCD)

    -- Direct action commands
    lib:RegisterSubCommand("test", function()
        addon:ToggleTestMode()
    end)
    lib:RegisterSubCommand("lock", function()
        addon:ToggleLock()
    end)
    lib:RegisterSubCommand("reset", function()
        addon:ResetAllPositions()
    end)
    lib:RegisterSubCommand("debug", function()
        addon.db.debug = not addon.db.debug
        addon:Print("Debug " .. (addon.db.debug and "|cff4ADE80ON|r" or "|cffE63939OFF|r"))
    end)
end
```

Then call `RegisterSubCommands()` inside the ADDON_LOADED handler (after line 194, before the end of the ADDON_LOADED block):

```lua
            addon:Print("v" .. addon.VERSION .. " loaded")
            RegisterSubCommands()
```

Also update the loaded message to remove `/tcd` reference since that slash command no longer exists.

**Step 3: Refactor Options.lua**

This is the biggest change. The approach:

**3a.** Remove the local `C` table (lines 21-56) — replace all `C.` references with `lib.C.` where `lib` is obtained at top of file.

**3b.** Remove widget functions (lines 61-284) — `ShowMicroTip`, `HideMicroTip`, `CreateSectionHeader`, `CreateCheckbox`, `CreateSlider`, `CreateButton`. Replace all calls:
- `CreateCheckbox(parent, ...)` → `lib:CreateCheckbox(parent, ...)`
- `CreateSlider(parent, ...)` → `lib:CreateSlider(parent, ...)`
- `CreateButton(parent, ...)` → `lib:CreateButton(parent, ...)`
- `CreateSectionHeader(parent, ...)` → `lib:CreateSectionHeader(parent, ...)`
- `ShowMicroTip(...)` → `lib:ShowMicroTip(...)`
- `HideMicroTip()` → `lib:HideMicroTip()`

**3c.** Remove master frame creation and sidebar (lines 310-415 inside `InitOptions()`). Replace with sub-addon registration.

**3d.** Remove `ShowOptions()` (lines 646-653). Replace with opening via TrinketedLib.

The new top of Options.lua should look like:

```lua
---------------------------------------------------------------------------
-- TrinketedCD: Options.lua
-- Settings content — registers into master Trinketed options panel
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local contentFrames = {}
local sidebarButtons = {}

-- Per-team grid builder state (unchanged)
local gridBuilderState = {
    party = { currentClass = "Warrior", gridSlotPool = {}, poolRowPool = {}, scrollChild = nil, gridParent = nil, filterButtons = {}, searchText = "" },
    enemy = { currentClass = "Warrior", gridSlotPool = {}, poolRowPool = {}, scrollChild = nil, gridParent = nil, filterButtons = {}, searchText = "" },
}
```

**3e.** Rewrite `InitOptions()` to register with master panel instead of creating its own frame:

```lua
function addon:InitOptions()
    lib:RegisterSubAddon("Cooldowns", {
        order = 1,
        OnSelect = function(contentFrame)
            addon:BuildOptionsContent(contentFrame)
        end,
    })
end
```

**3f.** Create `BuildOptionsContent(parent)` which builds the internal sidebar tabs (General, Party, Enemy, Test) inside the content frame provided by the master panel. This reuses the existing tab content population functions (`PopulateGeneralTab`, `PopulatePartyTab`, `PopulateEnemyTab`, `PopulateTestTab`) but the internal tab bar and content areas are children of the provided `parent` frame.

The internal tabs pattern:

```lua
function addon:BuildOptionsContent(parent)
    -- Internal sub-tab sidebar (narrower, left side of content area)
    local INNER_TAB_W = 90
    local innerSidebar = CreateFrame("Frame", nil, parent)
    innerSidebar:SetPoint("TOPLEFT", 0, 0)
    innerSidebar:SetPoint("BOTTOMLEFT", 0, 0)
    innerSidebar:SetWidth(INNER_TAB_W)

    local innerBg = innerSidebar:CreateTexture(nil, "BACKGROUND")
    innerBg:SetAllPoints()
    innerBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.5)

    -- Inner content area
    local innerContent = CreateFrame("Frame", nil, parent)
    innerContent:SetPoint("TOPLEFT", innerSidebar, "TOPRIGHT", 0, 0)
    innerContent:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    -- Build internal tab buttons and content frames
    local tabNames = { "General", "Party", "Enemy", "Test" }
    -- ... (reuse existing tab building logic, adapted to innerSidebar/innerContent)

    -- Populate tab contents using existing functions
    self:PopulateGeneralTab(contentFrames["General"])
    self:PopulatePartyTab(contentFrames["Party"])
    self:PopulateEnemyTab(contentFrames["Enemy"])
    self:PopulateTestTab(contentFrames["Test"])
end
```

**3g.** Replace `addon:ShowOptions()`:

```lua
function addon:ShowOptions()
    lib:ShowOptionsPanel("Cooldowns")
end
```

**Step 4: Remove Fonts directory from TrinketedCD**

```bash
rm -rf ../TrinketedCD/Fonts/
```

**Step 5: Remove LibStub from TrinketedCD**

```bash
rm -rf ../TrinketedCD/Libs/
```

**Step 6: Remove CI/CD from TrinketedCD (releases driven from parent)**

```bash
rm -rf ../TrinketedCD/.github/
rm -f ../TrinketedCD/pkgmeta.yaml
```

**Step 7: Verify TrinketedCD has no broken file references**

```bash
# Check all files referenced in the .toc exist
ls ../TrinketedCD/CooldownData.lua
ls ../TrinketedCD/Core.lua
ls ../TrinketedCD/Serialize.lua
ls ../TrinketedCD/Tracker.lua
ls ../TrinketedCD/Display.lua
ls ../TrinketedCD/TestMode.lua
ls ../TrinketedCD/Options.lua
```

**Step 8: Commit TrinketedCD changes**

```bash
cd ../TrinketedCD
git add -A
git commit -m "refactor: use TrinketedLib for fonts, colors, widgets; register as sub-addon"
cd ../Trinketed
```

---

### Task 7: Create pkgmeta.yaml and GitHub Actions for Parent Repo

**Files:**
- Create: `pkgmeta.yaml`
- Create: `.github/workflows/release.yml`

**Step 1: Write pkgmeta.yaml**

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

**Step 2: Write release.yml**

```bash
mkdir -p .github/workflows
```

```yaml
name: Package and Release

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Package and Release
        uses: BigWigsMods/packager@v2
        with:
          args: -g classic
        env:
          GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
```

**Step 3: Commit**

```bash
git add pkgmeta.yaml .github/workflows/release.yml
git commit -m "feat: add pkgmeta.yaml and GitHub Actions release workflow"
```

---

### Task 8: Set Up Git Submodules

**Files:**
- Create: `.gitmodules`

**Context:** This step should be done when the Trinketed/addon repo is actually set up on GitHub. The submodules point to the sub-addon repos.

**Step 1: Add TrinketedCD as submodule**

```bash
git submodule add https://github.com/Trinketed/cd.git TrinketedCD
```

**Step 2: Add TrinketedHistory as submodule (when repo exists)**

```bash
git submodule add https://github.com/Trinketed/history.git TrinketedHistory
```

**Step 3: Verify .gitmodules**

Expected content:

```
[submodule "TrinketedCD"]
    path = TrinketedCD
    url = https://github.com/Trinketed/cd.git
[submodule "TrinketedHistory"]
    path = TrinketedHistory
    url = https://github.com/Trinketed/history.git
```

**Step 4: Commit**

```bash
git add .gitmodules TrinketedCD TrinketedHistory
git commit -m "feat: add sub-addon git submodules"
```

---

### Task 9: Create TrinketedHistory Scaffold

**Files:**
- Create: `TrinketedHistory/TrinketedHistory.toc`
- Create: `TrinketedHistory/Core.lua`

**Context:** Minimal scaffold for TrinketedHistory. The VOD timestamp code from the old Trinketed.lua will be migrated here later as a separate effort. For now, just the .toc and a Core.lua that registers with TrinketedLib.

**Step 1: Create directory**

```bash
mkdir -p TrinketedHistory
```

**Step 2: Write TrinketedHistory.toc**

```
## Interface: 110207
## Title: Trinketed - History
## Notes: Arena match history and VOD timestamps
## Author: apwek
## Version: @project-version@
## Dependencies: Trinketed
## SavedVariables: TrinketedHistoryDB

Core.lua
```

**Step 3: Write Core.lua**

```lua
---------------------------------------------------------------------------
-- TrinketedHistory: Core.lua
-- Arena match history tracking and VOD timestamp overlay
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")

addon.ADDON_NAME = "TrinketedHistory"
addon.VERSION = "0.1.0"

---------------------------------------------------------------------------
-- Register with Trinketed suite
---------------------------------------------------------------------------
lib:RegisterSubAddon("History", {
    order = 2,
    OnSelect = function(contentFrame)
        addon:BuildOptionsContent(contentFrame)
    end,
})

lib:RegisterSubCommand("history", function(args)
    lib:ShowOptionsPanel("History")
end)

---------------------------------------------------------------------------
-- Options Content (placeholder)
---------------------------------------------------------------------------
function addon:BuildOptionsContent(parent)
    local C = lib.C
    local placeholder = parent:CreateFontString(nil, "OVERLAY")
    placeholder:SetFont(lib.FONT_BODY, 12, "")
    placeholder:SetPoint("CENTER", 0, 0)
    placeholder:SetText("Arena match history — coming soon")
    placeholder:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if name ~= addon.ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    TrinketedHistoryDB = TrinketedHistoryDB or {}
end)
```

**Step 4: Commit**

```bash
git add TrinketedHistory/
git commit -m "feat: add TrinketedHistory scaffold with suite registration"
```

---

### Task 10: Create .gitignore for Parent Repo

**Files:**
- Create: `.gitignore`

**Step 1: Write .gitignore**

```
# OS
.DS_Store
Thumbs.db

# Debug logs
*.log

# Editor
*.swp
*.swo
*~
.vscode/
.idea/
```

**Step 2: Clean up stray files**

```bash
rm -f firebase-debug.log
rm -f nul
```

**Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore"
```

---

### Task 11: Smoke Test — Verify Load Order and Integration

**Files:** None (verification only)

**Step 1: Verify parent addon file structure**

```bash
ls -R Trinketed/
# Expected:
# Trinketed.toc, Trinketed.lua
# Fonts/ (3 .ttf files)
# Libs/LibStub/LibStub.lua
# TrinketedLib/ (3 .lua files)
```

**Step 2: Verify TrinketedCD file structure**

```bash
ls ../TrinketedCD/
# Expected:
# TrinketedCD.toc (with ## Dependencies: Trinketed)
# Core.lua, CooldownData.lua, Serialize.lua, Tracker.lua, Display.lua, TestMode.lua, Options.lua
# NO Fonts/, NO Libs/, NO .github/, NO pkgmeta.yaml
```

**Step 3: Verify no broken references**

Search for old font paths that should have been updated:

```bash
grep -r "AddOns\\\\TrinketedCD\\\\Fonts" ../TrinketedCD/
# Expected: no matches (all should reference Trinketed fonts via TrinketedLib)
```

Search for old slash command registrations:

```bash
grep -r "SLASH_TRINKETEDCD" ../TrinketedCD/
# Expected: no matches
```

Search for old local `C =` palette that should have been removed:

```bash
grep -n "^local C = {" ../TrinketedCD/Options.lua
# Expected: no matches (should use lib.C now)
```

**Step 4: In-game test**

1. Launch WoW TBC Anniversary client
2. At character select, verify addon list shows:
   - `Trinketed` (enabled)
   - `Trinketed - Cooldowns` (enabled, shows dependency on Trinketed)
   - `Trinketed - History` (enabled, shows dependency on Trinketed)
3. Log in, type `/trinketed` — master panel should open with sidebar showing "Cooldowns" and "History"
4. Click "Cooldowns" — should show TrinketedCD's internal tabs (General, Party, Enemy, Test)
5. Click "History" — should show placeholder text
6. Type `/trinketed cd` — should open panel to Cooldowns tab
7. Type `/trinketed history` — should open panel to History tab
8. Type `/trinketed test` — should toggle test mode
9. Type `/trinketed help` — should list available commands
10. Disable "Trinketed - Cooldowns" in addon list, reload — master panel should only show "History"
11. Disable "Trinketed - History" in addon list, reload — master panel should show no tabs (or a "no sub-addons" message)

---

## Task Dependency Order

```
Task 1 (TrinketedLib.lua)  ──┐
Task 2 (Widgets.lua)        ──┼── Task 5 (Rewrite parent .toc/.lua)
Task 3 (OptionsPanel.lua)  ──┘         │
Task 4 (Move fonts)        ────────────┤
                                       ├── Task 6 (Refactor TrinketedCD) ─── Task 8 (Submodules)
Task 7 (pkgmeta + CI)     ────────────┤
Task 9 (TrinketedHistory)  ────────────┤
Task 10 (.gitignore)       ────────────┘
                                       │
                                  Task 11 (Smoke test)
```

Tasks 1-4 can be done in parallel. Task 5 depends on 1-4. Task 6 is the largest and depends on 5. Tasks 7, 9, 10 can be done in parallel with 6. Task 8 depends on the repos existing on GitHub. Task 11 is final verification.
