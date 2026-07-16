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
microTipBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.92)

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
-- Slider (fully custom — no Blizzard template)
---------------------------------------------------------------------------
local sliderDrag = { active = false, slider = nil }

local dragTracker = CreateFrame("Frame", nil, UIParent)
dragTracker:Hide()
dragTracker:SetScript("OnUpdate", function()
    if not sliderDrag.active then dragTracker:Hide(); return end
    local s = sliderDrag.slider
    local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
    local left = s.track:GetLeft()
    local width = s.track:GetWidth()
    local pct = (cx - left) / width
    pct = math.max(0, math.min(1, pct))
    local raw = s._min + pct * (s._max - s._min)
    local snapped = math.floor((raw - s._min) / s._step + 0.5) * s._step + s._min
    snapped = math.max(s._min, math.min(s._max, snapped))
    s:_SetValue(snapped)
end)

function lib:CreateSlider(parent, x, y, label, minVal, maxVal, step, current, onChange)
    local TRACK_W, TRACK_H = 200, 4
    local THUMB_W, THUMB_H = 12, 12

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(TRACK_W + THUMB_W + 60, 32)
    container:SetPoint("TOPLEFT", x, y)

    local sliderLabel = container:CreateFontString(nil, "OVERLAY")
    sliderLabel:SetFont(self.FONT_BODY, 11, "")
    sliderLabel:SetPoint("TOPLEFT", 0, 0)
    sliderLabel:SetText(label)
    sliderLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    local valText = container:CreateFontString(nil, "OVERLAY")
    valText:SetFont(self.FONT_MONO, 10, "")
    valText:SetPoint("TOPRIGHT", 0, 0)
    valText:SetText(tostring(math.floor(current)))
    valText:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    -- Track
    local track = CreateFrame("Frame", nil, container)
    track:SetSize(TRACK_W, TRACK_H)
    track:SetPoint("TOPLEFT", 0, -18)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)

    local trackFill = track:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("TOPLEFT")
    trackFill:SetPoint("BOTTOMLEFT")
    trackFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)

    -- Thumb
    local thumb = CreateFrame("Button", nil, container)
    thumb:SetSize(THUMB_W, THUMB_H)
    thumb:SetFrameLevel(track:GetFrameLevel() + 2)

    local thumbBg = thumb:CreateTexture(nil, "BACKGROUND")
    thumbBg:SetAllPoints()
    thumbBg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)

    local thumbBorderTop = thumb:CreateTexture(nil, "ARTWORK")
    thumbBorderTop:SetPoint("TOPLEFT"); thumbBorderTop:SetPoint("TOPRIGHT")
    thumbBorderTop:SetHeight(1)

    local thumbBorderBot = thumb:CreateTexture(nil, "ARTWORK")
    thumbBorderBot:SetPoint("BOTTOMLEFT"); thumbBorderBot:SetPoint("BOTTOMRIGHT")
    thumbBorderBot:SetHeight(1)

    local thumbBorderL = thumb:CreateTexture(nil, "ARTWORK")
    thumbBorderL:SetPoint("TOPLEFT"); thumbBorderL:SetPoint("BOTTOMLEFT")
    thumbBorderL:SetWidth(1)

    local thumbBorderR = thumb:CreateTexture(nil, "ARTWORK")
    thumbBorderR:SetPoint("TOPRIGHT"); thumbBorderR:SetPoint("BOTTOMRIGHT")
    thumbBorderR:SetWidth(1)

    local function SetThumbBorder(r, g, b, a)
        thumbBorderTop:SetColorTexture(r, g, b, a)
        thumbBorderBot:SetColorTexture(r, g, b, a)
        thumbBorderL:SetColorTexture(r, g, b, a)
        thumbBorderR:SetColorTexture(r, g, b, a)
    end
    SetThumbBorder(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)

    -- Slider state
    local s = {}
    s._min = minVal
    s._max = maxVal
    s._step = step
    s._value = current
    s._onChange = onChange
    s.track = track
    s.frame = container

    local function UpdateVisual()
        local pct = (s._value - s._min) / (s._max - s._min)
        trackFill:SetWidth(math.max(1, pct * TRACK_W))
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", pct * TRACK_W, 0)
        valText:SetText(tostring(math.floor(s._value)))
    end

    function s:_SetValue(val)
        if val == s._value then return end
        s._value = val
        UpdateVisual()
        if s._onChange then s._onChange(math.floor(val)) end
    end

    function s:SetValue(val)
        val = math.max(s._min, math.min(s._max, val))
        local snapped = math.floor((val - s._min) / s._step + 0.5) * s._step + s._min
        s._value = math.max(s._min, math.min(s._max, snapped))
        UpdateVisual()
    end

    function s:GetValue()
        return s._value
    end

    UpdateVisual()

    -- Drag behavior
    thumb:SetScript("OnMouseDown", function()
        sliderDrag.active = true
        sliderDrag.slider = s
        SetThumbBorder(C.accent[1], C.accent[2], C.accent[3], 1)
        dragTracker:Show()
    end)

    thumb:SetScript("OnMouseUp", function()
        sliderDrag.active = false
        sliderDrag.slider = nil
        SetThumbBorder(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
        dragTracker:Hide()
    end)

    thumb:SetScript("OnEnter", function()
        SetThumbBorder(C.accent[1], C.accent[2], C.accent[3], 0.7)
    end)
    thumb:SetScript("OnLeave", function()
        if not sliderDrag.active then
            SetThumbBorder(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
        end
    end)

    -- Click-on-track to jump
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function()
        local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
        local left = track:GetLeft()
        local width = track:GetWidth()
        local pct = math.max(0, math.min(1, (cx - left) / width))
        local raw = minVal + pct * (maxVal - minVal)
        local snapped = math.floor((raw - minVal) / step + 0.5) * step + minVal
        snapped = math.max(minVal, math.min(maxVal, snapped))
        s:_SetValue(snapped)
        -- Start drag from the new position
        sliderDrag.active = true
        sliderDrag.slider = s
        SetThumbBorder(C.accent[1], C.accent[2], C.accent[3], 1)
        dragTracker:Show()
    end)
    track:SetScript("OnMouseUp", function()
        sliderDrag.active = false
        sliderDrag.slider = nil
        SetThumbBorder(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
        dragTracker:Hide()
    end)

    return container, sliderLabel
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
    bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)

    local border = btn:CreateTexture(nil, "ARTWORK")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

    local inner = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    inner:SetAllPoints()
    inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)

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
        inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
        btnLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

---------------------------------------------------------------------------
-- Tab Bar (horizontal tabs with gold bottom indicator)
---------------------------------------------------------------------------
function lib:CreateTabBar(parent, tabs, opts)
    opts = opts or {}
    local TAB_H = opts.height or 26
    local TAB_W = opts.tabWidth  -- nil = auto-size
    local onChange = opts.onChange

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TAB_H)

    -- Bar background
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.8)

    -- Bottom separator
    local barSep = bar:CreateTexture(nil, "ARTWORK")
    barSep:SetPoint("BOTTOMLEFT", 0, 0)
    barSep:SetPoint("BOTTOMRIGHT", 0, 0)
    barSep:SetHeight(1)
    barSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

    local tabBar = {
        frame = bar,
        contents = {},
        _buttons = {},
        _activeKey = nil,
    }

    -- Create content frames for each tab
    for _, def in ipairs(tabs) do
        local content = CreateFrame("Frame", nil, parent)
        content:SetPoint("TOPLEFT", 0, -TAB_H)
        content:SetPoint("BOTTOMRIGHT", 0, 0)
        content:Hide()
        tabBar.contents[def[1]] = content
    end

    -- Create tab buttons
    local prevBtn = nil
    for i, def in ipairs(tabs) do
        local key, label = def[1], def[2]

        local tab = CreateFrame("Button", nil, bar)
        tab:SetSize(TAB_W or 80, TAB_H)
        if prevBtn then
            tab:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
        else
            tab:SetPoint("TOPLEFT", 6, 0)
        end

        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints()
        tab.bg:SetColorTexture(0, 0, 0, 0)

        tab.indicator = tab:CreateTexture(nil, "OVERLAY")
        tab.indicator:SetPoint("BOTTOMLEFT", 0, 0)
        tab.indicator:SetPoint("BOTTOMRIGHT", 0, 0)
        tab.indicator:SetHeight(2)
        tab.indicator:SetColorTexture(0, 0, 0, 0)

        tab.label = tab:CreateFontString(nil, "OVERLAY")
        tab.label:SetFont(lib.FONT_BODY, 11, "")
        tab.label:SetPoint("CENTER", 0, 1)
        tab.label:SetText(label)
        tab.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        tab.key = key

        -- Auto-size if no fixed width
        if not TAB_W then
            local resized = false
            tab:SetScript("OnUpdate", function(self)
                if resized then return end
                local tw = tab.label:GetStringWidth()
                if tw and tw > 0 then
                    tab:SetWidth(math.max(60, tw + 24))
                    resized = true
                    tab:SetScript("OnUpdate", nil)
                end
            end)
        end

        tab:SetScript("OnEnter", function()
            if tabBar._activeKey ~= key then
                tab.bg:SetColorTexture(C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4])
                tab.label:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
            end
        end)
        tab:SetScript("OnLeave", function()
            if tabBar._activeKey ~= key then
                tab.bg:SetColorTexture(0, 0, 0, 0)
                tab.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end
        end)
        tab:SetScript("OnClick", function()
            tabBar:SelectTab(key)
        end)

        tabBar._buttons[i] = tab
        prevBtn = tab
    end

    function tabBar:SelectTab(key)
        -- Update button visuals
        for _, btn in ipairs(self._buttons) do
            if btn.key == key then
                btn.bg:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3], C.tabActive[4])
                btn.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                btn.label:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
            else
                btn.bg:SetColorTexture(0, 0, 0, 0)
                btn.indicator:SetColorTexture(0, 0, 0, 0)
                btn.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end
        end

        -- Toggle content frames
        for k, content in pairs(self.contents) do
            if k == key then content:Show() else content:Hide() end
        end

        self._activeKey = key
        if onChange then onChange(key, self.contents[key]) end
    end

    function tabBar:GetActive()
        return self._activeKey
    end

    return tabBar
end
