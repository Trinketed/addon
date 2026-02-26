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
