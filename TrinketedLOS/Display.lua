---------------------------------------------------------------------------
-- TrinketedLOS: Display.lua
-- The on-screen alert shown when an ally reports they cannot see you.
-- A single draggable, scalable frame: warning icon, headline and a detail
-- line naming the caster (and the spell, when known). Auto-hides after the
-- configured hold time; unlock/test drive a static preview.
---------------------------------------------------------------------------
local ADDON, ns = ...
local addon = ns.addon
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local GetTime = GetTime

local Display = {}
ns.Display = Display

Display.locked = true

local WARN_ICON = "Interface\\Common\\Indicator-Red"   -- red warning dot

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
function Display:Init()
    local parentFrame = CreateFrame("Frame", "TrinketedLOSParent", UIParent)
    parentFrame:SetSize(280, 56)
    parentFrame:SetMovable(true)
    parentFrame:EnableMouse(false)
    parentFrame:SetClampedToScreen(true)
    parentFrame:RegisterForDrag("LeftButton")
    self.parentFrame = parentFrame

    local frame = CreateFrame("Frame", "TrinketedLOSAlert", parentFrame, "BackdropTemplate")
    frame:SetAllPoints(parentFrame)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:Hide()
    self.frame = frame

    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.92)
    frame:SetBackdropBorderColor(C.enemyRed[1], C.enemyRed[2], C.enemyRed[3], 0.9)

    -- Icon
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetSize(38, 38)
    frame.Icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    frame.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Headline
    frame.Title = frame:CreateFontString(nil, "OVERLAY")
    frame.Title:SetFont(addon.FONT_DISPLAY, 13, "OUTLINE")
    frame.Title:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 10, -1)
    frame.Title:SetJustifyH("LEFT")
    frame.Title:SetText("NO LINE OF SIGHT")
    frame.Title:SetTextColor(C.enemyRed[1], C.enemyRed[2], C.enemyRed[3])

    -- Detail
    frame.Detail = frame:CreateFontString(nil, "OVERLAY")
    frame.Detail:SetFont(addon.FONT_BODY, 12, "")
    frame.Detail:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -4)
    frame.Detail:SetJustifyH("LEFT")
    frame.Detail:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

    -- Unlock hint (only visible while unlocked)
    frame.Hint = frame:CreateFontString(nil, "OVERLAY")
    frame.Hint:SetFont(addon.FONT_BODY, 10, "")
    frame.Hint:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    frame.Hint:SetText("Drag to move")
    frame.Hint:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    frame.Hint:Hide()

    -- Fade out animation
    frame.fadeOut = frame:CreateAnimationGroup()
    local fade = frame.fadeOut:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.4)
    fade:SetOrder(1)
    frame.fadeOut:SetScript("OnFinished", function()
        if not Display.previewMode then
            frame:Hide()
            frame:SetAlpha(1)
        end
    end)

    -- Drag to move while unlocked
    parentFrame:SetScript("OnDragStart", function(self)
        if not Display.locked then self:StartMoving() end
    end)
    parentFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local s = self:GetScale()
        local cx, cy = self:GetCenter()
        addon.db.x = cx * s - UIParent:GetWidth() / 2
        addon.db.y = cy * s - UIParent:GetHeight() / 2
        Display:ApplySettings()
    end)

    self:ApplySettings()
    self:SetLocked(addon.db.locked)
end

---------------------------------------------------------------------------
-- Apply saved settings (scale + position)
---------------------------------------------------------------------------
function Display:ApplySettings()
    local db = addon.db
    local parentFrame = self.parentFrame
    if not parentFrame then return end

    local s = db.scale or 1
    parentFrame:SetScale(s)
    parentFrame:ClearAllPoints()
    parentFrame:SetPoint("CENTER", UIParent, "CENTER", (db.x or 0) / s, (db.y or 0) / s)
end

---------------------------------------------------------------------------
-- Show an alert (the core feature: an ally can't see us)
---------------------------------------------------------------------------
function Display:ShowAlert(caster, spellName)
    local db = addon.db
    local frame = self.frame
    if not frame then return end
    if self.previewMode then return end
    if not db.enabled then return end

    frame.Icon:SetTexture(WARN_ICON)

    local detail
    if spellName and spellName ~= "" then
        detail = string.format("|cffF4F4F5%s|r can't see you — |cffE8B923%s|r", caster, spellName)
    else
        detail = string.format("|cffF4F4F5%s|r can't see you", caster)
    end
    frame.Detail:SetText(detail)

    self._caster = caster

    frame.fadeOut:Stop()
    frame:SetAlpha(1)
    frame:Show()

    if db.playSound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end

    -- Reset the auto-hide timer.
    self._hideAt = GetTime() + (db.holdTime or 3)
    if not self._ticker then
        self._ticker = CreateFrame("Frame")
        self._ticker:SetScript("OnUpdate", function()
            if Display.previewMode then return end
            if Display._hideAt and GetTime() >= Display._hideAt then
                Display._hideAt = nil
                if not Display.frame.fadeOut:IsPlaying() then
                    Display.frame.fadeOut:Play()
                end
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Dismiss the alert early because the caster reached us with a successful cast
---------------------------------------------------------------------------
function Display:ClearAlert(caster)
    local frame = self.frame
    if not frame then return end
    if self.previewMode then return end
    if not frame:IsShown() then return end
    -- Only clear if this alert is the one that caster raised.
    if self._caster and caster and self._caster ~= caster then return end

    self._hideAt = nil
    self._caster = nil
    if not frame.fadeOut:IsPlaying() then
        frame.fadeOut:Play()
    end
end

---------------------------------------------------------------------------
-- Preview (unlock + test): static alert that ignores the hide timer
---------------------------------------------------------------------------
function Display:ShowPreview()
    local frame = self.frame
    if not frame then return end
    frame.fadeOut:Stop()
    frame:SetAlpha(1)
    frame.Icon:SetTexture(WARN_ICON)
    frame.Detail:SetText("|cffF4F4F5" .. (UnitName("player") or "Ally") .. "|r can't see you — |cffE8B923Regrowth|r")
    frame:Show()
end

---------------------------------------------------------------------------
-- Lock / unlock
---------------------------------------------------------------------------
function Display:SetLocked(locked)
    self.locked = locked
    self.previewMode = not locked
    local parentFrame = self.parentFrame
    local frame = self.frame
    if not parentFrame then return end

    if locked then
        parentFrame:EnableMouse(false)
        frame.Hint:Hide()
        frame.fadeOut:Stop()
        frame:SetAlpha(1)
        frame:Hide()
    else
        parentFrame:EnableMouse(true)
        frame.Hint:Show()
        self:ShowPreview()
    end
end
