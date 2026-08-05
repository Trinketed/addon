---------------------------------------------------------------------------
-- TrinketedLib: WindowFrame.lua
-- Shared window frame constructor matching the options panel visual style
---------------------------------------------------------------------------
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

-- Standalone windows built here share the options panel's DIALOG strata and
-- frame level, so showing both at once interleaves them into an unreadable
-- overlay. They are mutually exclusive by design — one Trinketed window at a
-- time — which the panel enforces by closing these when it opens.
lib.windowFrames = lib.windowFrames or {}

function lib:CloseAllWindows()
    for _, f in ipairs(self.windowFrames) do
        if f:IsShown() then f:Hide() end
    end
end

function lib:CreateWindowFrame(name, opts)
    local width  = opts.width or 800
    local height = opts.height or 520
    local title  = opts.title or ""

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(C.frameBg[1], C.frameBg[2], C.frameBg[3], C.frameBg[4])
    frame:SetBackdropBorderColor(C.frameBorder[1], C.frameBorder[2], C.frameBorder[3], C.frameBorder[4])
    frame:Hide()

    if not opts.noSpecialFrames then
        table.insert(UISpecialFrames, name)
    end

    lib.windowFrames[#lib.windowFrames + 1] = frame

    -- Close button
    frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeBtn:SetPoint("TOPRIGHT", -3, -3)
    frame.closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- onClose runs on EVERY close path — the close button, Esc via
    -- UISpecialFrames, CloseAllWindows, or any programmatic Hide — so windows
    -- reliably release heavy state (the replay's parsed event log used to
    -- leak whenever it was closed with Esc rather than the button).
    if opts.onClose then
        frame:HookScript("OnHide", opts.onClose)
    end

    -- Title
    frame.titleText = frame:CreateFontString(nil, "OVERLAY")
    frame.titleText:SetFont(lib.FONT_DISPLAY, 12, "")
    frame.titleText:SetPoint("TOPLEFT", 14, -10)
    frame.titleText:SetText(title)
    frame.titleText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

    -- Title divider
    local titleDiv = frame:CreateTexture(nil, "ARTWORK")
    titleDiv:SetPoint("TOPLEFT", 8, -28)
    titleDiv:SetPoint("TOPRIGHT", -8, -28)
    titleDiv:SetHeight(1)
    titleDiv:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])
    frame.titleDivider = titleDiv

    return frame
end
