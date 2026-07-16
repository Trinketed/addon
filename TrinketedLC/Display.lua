---------------------------------------------------------------------------
-- TrinketedLC: Display.lua
-- Faithful port of BetterBlizzFrames' BBF.SetupLoCFrame (temp_tbc/modules/loc.lua):
-- a center-screen Loss-of-Control alert with red top/bottom lines, a shadow
-- background, a main icon (+optional cooldown swipe), a secondary icon, the
-- effect name (e.g. "Cycloned") and the remaining time. Player only.
---------------------------------------------------------------------------
local ADDON, ns = ...
local addon = ns.addon
local lib = LibStub("TrinketedLib-1.0")

local GetTime        = GetTime
local UnitGUID       = UnitGUID
local UnitBuff       = UnitBuff
local UnitChannelInfo = UnitChannelInfo
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local C_UnitAuras    = C_UnitAuras
local C_LossOfControl = C_LossOfControl
local C_Spell        = C_Spell
local unpack         = unpack
local sformat        = string.format

local Display = {}
ns.Display = Display

Display.locked   = true
Display.unlockMode = false
Display.testMode = false

local SAMPLE_ICON = 136022   -- Cyclone icon, used for unlock/test previews

local function isHardCC(t)
    return ns.Data.hardCCSet[t]
end

local function GetSchoolInfo(school)
    local schoolNames = {
        -- Single schools
        [1]   = {"Physical",     0.85, 0.65, 0.45},
        [2]   = {"Holy",         1.00, 0.95, 0.60},
        [4]   = {"Fire",         1.00, 0.35, 0.10},
        [8]   = {"Nature",       0.30, 0.85, 0.30},
        [16]  = {"Frost",        0.45, 0.70, 1.00},
        [32]  = {"Shadow",       0.50, 0.25, 0.75},
        [64]  = {"Arcane",       0.80, 0.60, 1.00},

        -- Dual/multi schools
        [3]   = {"Holystrike",   1.00, 0.85, 0.50},
        [5]   = {"Flamestrike",  1.00, 0.45, 0.10},
        [6]   = {"Holyfire",     1.00, 0.65, 0.30},
        [9]   = {"Stormstrike",  0.40, 0.80, 1.00},
        [10]  = {"Holystorm",    0.90, 0.90, 0.60},
        [12]  = {"Firestorm",    1.00, 0.55, 0.10},
        [17]  = {"Froststrike",  0.50, 0.75, 1.00},
        [18]  = {"Holyfrost",    0.80, 0.90, 1.00},
        [20]  = {"Frostfire",    0.80, 0.45, 1.00},
        [24]  = {"Froststorm",   0.50, 0.80, 1.00},
        [28]  = {"Spellfrost",   0.60, 0.70, 1.00},
        [33]  = {"Shadowstrike", 0.65, 0.25, 0.60},
        [34]  = {"Twilight",     0.70, 0.40, 0.85},
        [36]  = {"Shadowflame",  0.80, 0.30, 0.60},
        [40]  = {"Shadowstorm",  0.50, 0.30, 0.85},
        [48]  = {"Shadowfrost",  0.55, 0.40, 0.85},
        [65]  = {"Spellstrike",  0.90, 0.60, 1.00},
        [66]  = {"Divine",       1.00, 0.85, 0.55},
        [96]  = {"Spellshadow",  0.75, 0.45, 0.85},
        [124] = {"Elemental",    0.95, 0.60, 0.20},
        [126] = {"Chromatic",    0.95, 0.95, 1.00},
        [127] = {"Magic",        0.90, 0.90, 1.00},

        -- Extra
        [200] = {"Astral",       0.50, 0.85, 1.00},
        [201] = {"Chaos",        1.00, 0.15, 0.15},
        [202] = {"Chimeric",     0.95, 0.55, 0.85},
        [203] = {"Cosmic",       0.80, 0.80, 1.00},
        [204] = {"Radiant",      1.00, 0.70, 0.40},
        [205] = {"Volcanic",     1.00, 0.40, 0.20},
        [206] = {"Plague",       0.55, 0.80, 0.40},
    }
    return unpack(schoolNames[school] or {"Interrupted", 1, 1, 1})
end

---------------------------------------------------------------------------
-- Frame construction (mirrors BBF.SetupLoCFrame)
---------------------------------------------------------------------------
function Display:Init()
    local db = addon.db

    local parentFrame = CreateFrame("Frame", "TrinketedLCParentFrame", UIParent)
    parentFrame:SetSize(256, 58)
    parentFrame:SetMovable(true)
    parentFrame:EnableMouse(false)
    parentFrame:RegisterForDrag("LeftButton")
    self.parentFrame = parentFrame

    local frame = CreateFrame("Frame", "TrinketedLCFrameLoC", parentFrame, "BackdropTemplate")
    frame:SetSize(256, 58)
    frame:SetPoint("CENTER", parentFrame, "CENTER")
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:Hide()
    self.frame = frame

    -- Pop-in animation (overshoot + settle).
    frame.fadeInScale = frame:CreateAnimationGroup()
    frame.fadeIn = frame.fadeInScale:CreateAnimation("Alpha")
    frame.fadeIn:SetFromAlpha(0)
    frame.fadeIn:SetToAlpha(1)
    frame.fadeIn:SetDuration(0.10)
    frame.fadeIn:SetOrder(1)
    frame.fadeIn:SetSmoothing("OUT")

    frame.scaleOvershoot = frame.fadeInScale:CreateAnimation("Scale")
    frame.scaleOvershoot:SetScaleFrom(0.85, 0.85)
    frame.scaleOvershoot:SetScaleTo(1.1, 1.1)
    frame.scaleOvershoot:SetDuration(0.08)
    frame.scaleOvershoot:SetOrder(1)
    frame.scaleOvershoot:SetSmoothing("OUT")

    frame.scaleSettle = frame.fadeInScale:CreateAnimation("Scale")
    frame.scaleSettle:SetScaleFrom(1.1, 1.1)
    frame.scaleSettle:SetScaleTo(1, 1)
    frame.scaleSettle:SetDuration(0.07)
    frame.scaleSettle:SetOrder(2)
    frame.scaleSettle:SetSmoothing("IN")

    frame.fadeInScale:SetToFinalAlpha(true)

    -- Fade-out + shrink animation.
    frame.fadeOutShrink = frame:CreateAnimationGroup()
    frame.fadeOut = frame.fadeOutShrink:CreateAnimation("Alpha")
    frame.fadeOut:SetFromAlpha(1)
    frame.fadeOut:SetToAlpha(0)
    frame.fadeOut:SetDuration(0.07)
    frame.fadeOut:SetOrder(1)
    frame.fadeOut:SetSmoothing("IN")

    frame.scaleDown = frame.fadeOutShrink:CreateAnimation("Scale")
    frame.scaleDown:SetScaleFrom(1, 1)
    frame.scaleDown:SetScaleTo(0.85, 0.85)
    frame.scaleDown:SetDuration(0.07)
    frame.scaleDown:SetOrder(1)
    frame.scaleDown:SetSmoothing("IN")

    frame.fadeOutShrink:SetToFinalAlpha(false)
    frame.fadeOutShrink:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
        frame:SetScale(1)
        frame.duration = nil
        frame.expiration = nil
        frame.lockedBy = nil
    end)

    -- Red lines.
    frame.RedLineTop = frame:CreateTexture(nil, "BACKGROUND")
    frame.RedLineTop:SetTexture("Interface\\Cooldown\\Loc-RedLine")
    frame.RedLineTop:SetSize(236, 27)
    frame.RedLineTop:SetPoint("BOTTOM", frame, "TOP")

    frame.RedLineBottom = frame:CreateTexture(nil, "BACKGROUND")
    frame.RedLineBottom:SetTexture("Interface\\Cooldown\\Loc-RedLine")
    frame.RedLineBottom:SetSize(236, 27)
    frame.RedLineBottom:SetPoint("TOP", frame, "BOTTOM")
    frame.RedLineBottom:SetTexCoord(0, 1, 1, 0)

    -- Background.
    frame.blackBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.blackBg:SetTexture("Interface\\Cooldown\\loc-shadowbg")
    frame.blackBg:SetPoint("TOPLEFT", frame.RedLineTop, "BOTTOMLEFT")
    frame.blackBg:SetPoint("BOTTOMRIGHT", frame.RedLineBottom, "TOPRIGHT")

    -- Main icon (+ cooldown swipe).
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetSize(48, 48)
    frame.Icon:SetPoint("CENTER", frame, "CENTER", -70, 0)

    frame.Icon.Cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.Icon.Cooldown:SetAllPoints(frame.Icon)
    frame.Icon.Cooldown:Hide()

    -- Secondary icon (root/silence/disarm/interrupt).
    frame.SecondaryIcon = CreateFrame("Frame", nil, frame)
    frame.SecondaryIcon:SetSize(35, 35)
    frame.SecondaryIcon:SetPoint("RIGHT", frame.Icon, "LEFT", -4, 0)

    frame.SecondaryIcon.Cooldown = CreateFrame("Cooldown", nil, frame.SecondaryIcon, "CooldownFrameTemplate")
    frame.SecondaryIcon.Cooldown:SetAllPoints(frame.SecondaryIcon)

    local cooldownSwipe = frame.SecondaryIcon:GetRegions()
    if cooldownSwipe then
        cooldownSwipe:SetAllPoints(frame.SecondaryIcon)
    end

    frame.SecondaryIcon.icon = frame.SecondaryIcon:CreateTexture(nil, "ARTWORK")
    frame.SecondaryIcon.icon:SetAllPoints()
    frame.SecondaryIcon.icon:SetTexture(nil)

    -- School text for the main icon.
    frame.Icon.SchoolText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.Icon.SchoolText:SetPoint("BOTTOM", frame.Icon, "BOTTOM", 0, 1)
    frame.Icon.SchoolText:SetJustifyH("CENTER")
    frame.Icon.SchoolText:SetTextColor(1, 1, 1)

    -- School text for the secondary icon.
    frame.SecondaryIcon.SchoolText = frame.SecondaryIcon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.SecondaryIcon.SchoolText:SetPoint("BOTTOM", frame.SecondaryIcon, "BOTTOM", 0, 1)
    frame.SecondaryIcon.SchoolText:SetJustifyH("CENTER")
    frame.SecondaryIcon.SchoolText:SetTextColor(1, 1, 1)
    frame.SecondaryIcon.SchoolText:SetDrawLayer("OVERLAY", 7)

    -- Effect name (e.g. "Cycloned").
    frame.AbilityName = frame:CreateFontString(nil, "ARTWORK", "MovieSubtitleFont")
    frame.AbilityName:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 5, -4)
    frame.AbilityName:SetSize(0, 20)

    -- Time left.
    frame.TimeLeft = CreateFrame("Frame", nil, frame)
    frame.TimeLeft:SetSize(200, 20)
    frame.TimeLeft:SetPoint("TOPLEFT", frame.AbilityName, "BOTTOMLEFT")

    frame.TimeLeft.NumberText = frame.TimeLeft:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    frame.TimeLeft.NumberText:SetPoint("LEFT", frame.TimeLeft, "LEFT", 0, -3)
    frame.TimeLeft.NumberText:SetShadowOffset(2, -2)
    frame.TimeLeft.NumberText:SetTextColor(1, 1, 1)

    -- UNIT_AURA-driven scan.
    frame:SetScript("OnUpdate", function(self)
        local now = GetTime()
        if self.expiration then
            local timeLeft = self.expiration - now
            if timeLeft <= 0 then
                Display:CheckAuras()
            else
                self.TimeLeft.NumberText:SetText(sformat("%.1f seconds", timeLeft))
                if self.interruptData and self.secondaryCC == self.interruptData and self.interruptData.expiration <= now then
                    self.interruptData = nil
                    Display:CheckAuras()
                end
            end
        end
    end)

    -- Drag-to-move while unlocked.
    parentFrame:SetScript("OnDragStart", function(self)
        if not Display.locked then self:StartMoving() end
    end)
    parentFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        addon.db.x = x
        addon.db.y = y
    end)

    self:ApplySettings()
end

---------------------------------------------------------------------------
-- Apply saved settings (scale, position, icon-only layout, line/bg alpha)
---------------------------------------------------------------------------
function Display:ApplySettings()
    local db = addon.db
    local frame = self.frame
    local parentFrame = self.parentFrame
    if not frame then return end

    parentFrame:SetScale(db.scale or 1)
    parentFrame:ClearAllPoints()
    parentFrame:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)

    local iconOnly = db.iconOnly
    frame.Icon:ClearAllPoints()
    frame.Icon:SetPoint("CENTER", frame, "CENTER", iconOnly and 0 or -70, 0)
    frame.RedLineTop:SetSize(iconOnly and 70 or 236, 27)
    frame.RedLineBottom:SetSize(iconOnly and 70 or 236, 27)
    frame.AbilityName:SetShown(not iconOnly)
    frame.TimeLeft:SetShown(not iconOnly)

    local bgAlpha = db.hideBackground and 0 or 0.6
    local lineAlpha = db.hideRedLines and 0 or 1
    frame.blackBg:SetAlpha(bgAlpha)
    frame.RedLineTop:SetAlpha(lineAlpha)
    frame.RedLineBottom:SetAlpha(lineAlpha)

    if LossOfControlFrame then
        LossOfControlFrame.blackBg:SetAlpha(bgAlpha)
        LossOfControlFrame.RedLineTop:SetAlpha(lineAlpha)
        LossOfControlFrame.RedLineBottom:SetAlpha(lineAlpha)
    end

    if self.unlockMode then
        self:ShowPreview(true)
    elseif not self.testMode then
        self:CheckAuras()
    end
end

---------------------------------------------------------------------------
-- Aura scan + priority + display (mirrors checkAuras)
---------------------------------------------------------------------------
function Display:CheckAuras()
    local frame = self.frame
    if not frame then return end
    if self.unlockMode or self.testMode then return end
    if not addon.db.enabled then
        frame:Hide()
        return
    end

    local mainHardCC, secondHardCC, silence, disarm, root
    local interrupt = frame.interruptData
    local now = GetTime()

    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
        if not aura then break end

        local spellID = aura.spellId
        local ccType = addon:GetLabel(spellID)
        local remaining = aura.expirationTime and (aura.expirationTime - now) or 0
        local duration = aura.duration or 0

        if ccType == "Silenced" and duration == 0 then
            frame.silenceFallbacks = frame.silenceFallbacks or {}
            local fallback = frame.silenceFallbacks[spellID]
            if not fallback or fallback.expirationTime <= now then
                local solarBeamDuration = 8.1
                fallback = {
                    startTime = now,
                    duration = solarBeamDuration,
                    expirationTime = now + solarBeamDuration,
                }
                frame.silenceFallbacks[spellID] = fallback
            end
            duration = fallback.duration
            aura.expirationTime = fallback.expirationTime
            remaining = fallback.expirationTime - now
        end

        if ccType and remaining > 0 then
            local auraData = {
                icon = aura.icon,
                type = ccType,
                duration = duration,
                expiration = aura.expirationTime,
                remaining = remaining,
                spellID = spellID,
            }

            if isHardCC(ccType) then
                if ccType == "Stunned" or ccType == "Horrified" then
                    local isSameType = (mainHardCC and mainHardCC.type == ccType)
                    if not mainHardCC or not isSameType or remaining > mainHardCC.remaining then
                        if mainHardCC and not (mainHardCC.type == "Stunned" or mainHardCC.type == "Horrified") then
                            secondHardCC = mainHardCC
                        end
                        mainHardCC = auraData
                    end
                elseif not mainHardCC then
                    mainHardCC = auraData
                elseif auraData.spellID ~= mainHardCC.spellID then
                    if not secondHardCC or auraData.remaining > secondHardCC.remaining then
                        secondHardCC = auraData
                    end
                end
            elseif ccType == "Silenced" or ccType == "Silenced+" then
                if not silence or remaining > silence.remaining then
                    silence = auraData
                end
            elseif ccType == "Disarmed" then
                if not disarm or remaining > disarm.remaining then
                    disarm = auraData
                end
            elseif ccType == "Rooted" then
                if not root or remaining > root.remaining then
                    root = auraData
                end
            end
        end
    end

    -- Clear interrupt if expired.
    if interrupt and interrupt.expiration <= now then
        frame.interruptData = nil
        interrupt = nil
    end

    -- Priority logic.
    local main, secondary
    local fullCC = mainHardCC

    if fullCC then
        main = fullCC
        if interrupt and silence then
            secondary = (silence.remaining > interrupt.remaining) and silence or interrupt
        elseif interrupt then
            secondary = interrupt
        elseif secondHardCC then
            secondary = secondHardCC
        else
            secondary = interrupt or silence or disarm or root
        end
    elseif interrupt and silence then
        if silence.remaining > interrupt.remaining then
            main = silence
            secondary = interrupt
        else
            main = interrupt
            secondary = silence
        end
    elseif interrupt then
        main = interrupt
        secondary = silence or disarm or root
    elseif silence then
        main = silence
        secondary = disarm or root
    elseif disarm then
        main = disarm
        secondary = root
    elseif root then
        main = root
        secondary = nil
    end

    frame.mainCC = main
    frame.secondaryCC = secondary

    -- Main display.
    if main then
        if frame.fadeOutShrink:IsPlaying() then
            frame.fadeOutShrink:Stop()
        end

        frame.Icon:SetTexture(main.icon)
        if (addon.db.showCooldown or addon.db.iconOnly) then
            frame.Icon.Cooldown:Show()
            frame.Icon.Cooldown:SetCooldown(main.expiration - main.duration, main.duration)
        else
            frame.Icon.Cooldown:Hide()
        end

        local r, g, b = 1, 0.819, 0
        if main.type == "Silenced" and interrupt then
            frame.AbilityName:SetText("Silenced")
            _, r, g, b = GetSchoolInfo(interrupt.school)
        elseif main == interrupt then
            frame.AbilityName:SetText("Interrupted")
            _, r, g, b = GetSchoolInfo(interrupt.school)
        else
            frame.AbilityName:SetText(main.type or "Unknown")
        end
        frame.AbilityName:SetTextColor(r, g, b)

        frame.duration = main.duration
        frame.expiration = main.expiration
        frame.lockedBy = main.spellID

        if not frame:IsShown() then
            frame:SetAlpha(0)
            frame:SetScale(0.85)
            frame:Show()
            frame.fadeInScale:Stop()
            frame.fadeInScale:Play()
        end

        if main == interrupt or (main.type == "Silenced" and interrupt) then
            local name, sr, sg, sb = GetSchoolInfo(interrupt.school)
            frame.Icon.SchoolText:SetText(name)
            frame.Icon.SchoolText:SetTextColor(sr, sg, sb)
        else
            frame.Icon.SchoolText:SetText("")
        end
    else
        if interrupt and (interrupt.expiration - now) > 0.2 then
            -- wait: interrupt about to become main
        else
            if not frame.fadeOutShrink:IsPlaying() then
                frame.fadeOutShrink:Stop()
                frame.fadeOutShrink:Play()
            end
            frame.expiration = nil
        end
        frame.Icon.SchoolText:SetText("")
    end

    -- Secondary display.
    if secondary then
        frame.SecondaryIcon.icon:SetTexture(secondary.icon)
        frame.SecondaryIcon.Cooldown:SetCooldown(secondary.expiration - secondary.duration, secondary.duration)
        frame.SecondaryIcon:Show()

        if interrupt and (secondary == interrupt or secondary == silence) then
            local name, sr, sg, sb = GetSchoolInfo(interrupt.school)
            frame.SecondaryIcon.SchoolText:SetText(name)
            frame.SecondaryIcon.SchoolText:SetTextColor(sr, sg, sb)
        else
            frame.SecondaryIcon.SchoolText:SetText("")
        end
    else
        frame.SecondaryIcon:Hide()
        frame.SecondaryIcon.SchoolText:SetText("")
    end

    if frame.silenceFallbacks then
        for spellID, fallback in pairs(frame.silenceFallbacks) do
            if fallback.expirationTime <= now then
                frame.silenceFallbacks[spellID] = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Interrupt capture (mirrors the interruptWatcher in SetupLoCFrame)
---------------------------------------------------------------------------
function Display:OnCombatLog()
    local frame = self.frame
    if not frame then return end

    local _, event, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID, spellName, _, _, _, school = CombatLogGetCurrentEventInfo()

    if not ns.Data.interruptEvents[event] then return end
    if destGUID ~= UnitGUID("player") then return end

    local duration = ns.Data.interruptSpells[spellID]
    if not duration then return end

    if event ~= "SPELL_INTERRUPT" then
        local _, _, _, _, _, _, notInterruptibleChannel = UnitChannelInfo("player")
        local ccData
        local schoolName = GetSchoolInfo(school) or ""
        if schoolName == "Interrupted" then
            for i = 1, C_LossOfControl.GetActiveLossOfControlDataCount() do
                local cc = C_LossOfControl.GetActiveLossOfControlData(i)
                if cc and cc.locType == "SCHOOL_INTERRUPT" then
                    ccData = cc
                    break
                end
            end
            if ccData then
                school = ccData.lockoutSchool
                duration = ccData.duration
            else
                return
            end
        end
        if not ccData and notInterruptibleChannel ~= false then
            return
        end
    end

    -- Reduce duration based on active buffs.
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, auraSpellID = UnitBuff("player", i)
        if not name then break end
        local mult = ns.Data.spellLockReducer[auraSpellID]
        if mult then
            duration = duration * mult
        end
    end

    local schoolName = GetSchoolInfo(school)
    local now = GetTime()
    local expirationTime = now + duration

    frame.interruptData = {
        icon = C_Spell.GetSpellTexture(spellID),
        type = schoolName or "Interrupted",
        duration = duration,
        expiration = expirationTime,
        expirationTime = expirationTime,
        remaining = duration,
        spellID = spellID,
        school = school,
    }

    self:CheckAuras()
end

function Display:RefreshAll()
    self:CheckAuras()
end

---------------------------------------------------------------------------
-- Preview (used by unlock and test): show a static sample alert
---------------------------------------------------------------------------
function Display:ShowPreview(asPlaceholder)
    local frame = self.frame
    if not frame then return end
    frame.fadeInScale:Stop()
    frame.fadeOutShrink:Stop()
    frame.expiration = nil
    frame:SetAlpha(1)
    frame:SetScale(1)

    frame.Icon:SetTexture(SAMPLE_ICON)
    if addon.db.showCooldown or addon.db.iconOnly then
        frame.Icon.Cooldown:Show()
        frame.Icon.Cooldown:SetCooldown(GetTime(), 6)
    else
        frame.Icon.Cooldown:Hide()
    end
    frame.Icon.SchoolText:SetText("")
    frame.AbilityName:SetText("Cycloned")
    frame.AbilityName:SetTextColor(1, 0.819, 0)
    frame.TimeLeft.NumberText:SetText("6.0 seconds")
    frame.SecondaryIcon:Hide()
    frame.SecondaryIcon.SchoolText:SetText("")
    frame:Show()
end

---------------------------------------------------------------------------
-- Lock / unlock (drag to reposition)
---------------------------------------------------------------------------
function Display:SetLocked(locked)
    self.locked = locked
    self.unlockMode = not locked
    local parentFrame = self.parentFrame
    local frame = self.frame
    if locked then
        if parentFrame then parentFrame:EnableMouse(false) end
        if frame then
            frame:SetMovable(false)
            frame.interruptData = nil
        end
        self.testMode = false
        self:CheckAuras()
    else
        self.testMode = false
        if parentFrame then parentFrame:EnableMouse(true) end
        self:ShowPreview(true)
    end
end

---------------------------------------------------------------------------
-- Test mode (preview alert without a real aura)
---------------------------------------------------------------------------
function Display:ToggleTest()
    if not self.locked then return end
    self.testMode = not self.testMode
    if self.testMode then
        self:ShowPreview(false)
        addon:Print("Lose Control test |cff4ADE80ON|r")
    else
        self.frame.expiration = nil
        self.frame:Hide()
        self:CheckAuras()
        addon:Print("Lose Control test |cffE63939OFF|r")
    end
end

---------------------------------------------------------------------------
-- Event dispatch (called from Core)
---------------------------------------------------------------------------
function Display:OnEvent(event, ...)
    if event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then self:CheckAuras() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:CheckAuras()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:OnCombatLog()
    end
end
