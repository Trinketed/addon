---------------------------------------------------------------------------
-- TrinketedCD: Display.lua
-- UI frames, icon bars, cooldown sweeps, positioning, lock/unlock
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

addon.bars = {}      -- [guid] -> bar container frame
addon.icons = {}     -- [guid] -> { [spellName] -> icon frame }

---------------------------------------------------------------------------
-- Bar Creation
---------------------------------------------------------------------------
function addon:CreateBar(guid)
    local info = self.state.trackedPlayers[guid]
    if not info then return end
    if self.bars[guid] then return self.bars[guid] end

    local barName = "TrinketedCDBar_" .. info.team .. "_" .. info.slot
    local bar = CreateFrame("Frame", barName, UIParent)
    bar:SetSize(200, 32)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(5)
    bar:SetClampedToScreen(true)

    -- Movable behavior (only when unlocked)
    bar:SetMovable(true)
    bar:EnableMouse(false)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self2)
        if InCombatLockdown() then return end
        if addon.db and not addon.db.general.locked then
            self2:StartMoving()
        end
    end)
    bar:SetScript("OnDragStop", function(self2)
        self2:StopMovingOrSizing()
        addon:SaveBarPosition(guid)
    end)

    -- Background (visible only when unlocked)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0)

    -- Player name label (visible only when unlocked)
    bar.nameText = bar:CreateFontString(nil, "OVERLAY")
    bar.nameText:SetFont(self.FONT_BODY, 11, "")
    bar.nameText:SetPoint("BOTTOM", bar, "TOP", 0, 2)
    bar.nameText:Hide()

    -- Team indicator border (thin colored line at top)
    bar.teamIndicator = bar:CreateTexture(nil, "ARTWORK")
    bar.teamIndicator:SetHeight(2)
    bar.teamIndicator:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
    bar.teamIndicator:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -1)
    bar.teamIndicator:SetColorTexture(C.partyBlue[1], C.partyBlue[2], C.partyBlue[3], 0.8)
    bar.teamIndicator:Hide()

    bar.guid = guid
    bar.playerInfo = info

    self.bars[guid] = bar
    self.icons[guid] = {}

    -- Apply lock state
    local locked = self.db and self.db.general.locked
    bar:EnableMouse(not locked)
    if not locked then
        bar.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.3)
        bar.nameText:SetText(addon:ClassColorWrap(info.name, info.class))
        bar.nameText:SetAlpha(1)
        bar.nameText:Show()
        bar.teamIndicator:Show()
    elseif self.db and self.db.general.showPlayerLabels then
        bar.nameText:SetText(addon:ClassColorWrap(info.name, info.class))
        bar.nameText:SetAlpha(0.7)
        bar.nameText:Show()
    end

    self:PositionBar(guid)
    return bar
end

---------------------------------------------------------------------------
-- Unit Frame Detection (for party frame anchoring)
---------------------------------------------------------------------------

-- Registry for custom addon frame finders: { function(unit) -> frame or nil }
addon.customUnitFrames = {}

-- Find the Blizzard party frame for a given unit token (e.g. "party1")
-- In test mode, falls back to finding frames by slot index since no real units exist
function addon:FindUnitFrame(unit, slotIndex)
    -- 1. Check custom addon frame finders
    for _, finder in ipairs(self.customUnitFrames) do
        local frame = finder(unit)
        if frame and frame:IsVisible() then return frame end
    end

    -- In test mode, real units don't exist — match by slot index instead
    local useSlotMatch = self.state.testMode or not UnitExists(unit)

    if not useSlotMatch then
        -- 2. CompactPartyFrame children (Retail party frames)
        local compactParty = _G["CompactPartyFrame"]
        if compactParty then
            for _, child in pairs({ compactParty:GetChildren() }) do
                if child.unit and child:IsVisible() then
                    if UnitIsUnit(child.unit, unit) then return child end
                end
            end
        end

        -- 3. Compact raid-style party frames (CompactPartyFrameMember1-5)
        for i = 1, 5 do
            local frame = _G["CompactPartyFrameMember" .. i]
            if frame and frame:IsVisible() and frame.unit then
                if UnitIsUnit(frame.unit, unit) then return frame end
            end
        end

        -- 4. Classic party frames (PartyMemberFrame1-4)
        for i = 1, 4 do
            local frame = _G["PartyMemberFrame" .. i]
            if frame and frame:IsVisible() then
                if UnitIsUnit("party" .. i, unit) then return frame end
            end
        end

        -- 5. EditMode party frames (PartyFrame.MemberFrame1-4, Retail 10.0+)
        local partyFrame = _G["PartyFrame"]
        if partyFrame then
            for i = 1, 4 do
                local member = partyFrame["MemberFrame" .. i]
                if member and member:IsVisible() and member.unit then
                    if UnitIsUnit(member.unit, unit) then return member end
                end
            end
        end
    end

    -- Slot-index fallback: find the Nth visible party frame regardless of unit matching
    -- Used in test mode and when real unit lookup fails
    if slotIndex and slotIndex >= 1 and slotIndex <= 4 then
        -- Try CompactPartyFrame children by index
        local compactParty = _G["CompactPartyFrame"]
        if compactParty then
            local visibleMembers = {}
            for _, child in pairs({ compactParty:GetChildren() }) do
                if child.unit and child:IsVisible() then
                    visibleMembers[#visibleMembers + 1] = child
                end
            end
            if visibleMembers[slotIndex] then return visibleMembers[slotIndex] end
        end

        -- Try CompactPartyFrameMember by index
        local frame = _G["CompactPartyFrameMember" .. slotIndex]
        if frame and frame:IsVisible() then return frame end

        -- Try PartyMemberFrame by index
        frame = _G["PartyMemberFrame" .. slotIndex]
        if frame and frame:IsVisible() then return frame end

        -- Try PartyFrame.MemberFrame by index
        local partyFrame = _G["PartyFrame"]
        if partyFrame then
            local member = partyFrame["MemberFrame" .. slotIndex]
            if member and member:IsVisible() then return member end
        end
    end

    return nil
end

-- Find any visible party frame and its slot index (for extrapolation)
function addon:FindAnyPartyFrame()
    -- Check CompactPartyFrame children
    local compactParty = _G["CompactPartyFrame"]
    if compactParty then
        for _, child in pairs({ compactParty:GetChildren() }) do
            if child.unit and child:IsVisible() then
                local idx = child.unit and tonumber(child.unit:match("party(%d+)"))
                if idx then return child, idx end
            end
        end
    end

    for i = 1, 4 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame:IsVisible() then return frame, i end

        frame = _G["PartyMemberFrame" .. i]
        if frame and frame:IsVisible() then return frame, i end
    end

    local partyFrame = _G["PartyFrame"]
    if partyFrame then
        for i = 1, 4 do
            local member = partyFrame["MemberFrame" .. i]
            if member and member:IsVisible() then return member, i end
        end
    end

    return nil, nil
end

-- Estimate vertical spacing between party frames by finding two visible ones
function addon:EstimatePartyFrameSpacing(refFrame, refSlot)
    for i = 1, 4 do
        if i ~= refSlot then
            local other = self:FindUnitFrame("party" .. i, i)
            if other then
                local _, refY = refFrame:GetCenter()
                local _, otherY = other:GetCenter()
                if refY and otherY then
                    local diff = math.abs(refY - otherY) / math.abs(i - refSlot)
                    return diff
                end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Bar Positioning
---------------------------------------------------------------------------
function addon:PositionBar(guid)
    local bar = self.bars[guid]
    local info = self.state.trackedPlayers[guid]
    if not bar or not info or not self.db then return end

    bar:ClearAllPoints()

    if info.team == "party" then
        -- Try anchoring to party unit frames
        if self.db.party.anchorToFrames then
            local unitFrame = self:FindUnitFrame(info.unit, info.slot)
            self:Debug("FindUnitFrame(" .. (info.unit or "nil") .. ", slot " .. (info.slot or "?") .. ") = " .. (unitFrame and (unitFrame:GetName() or "anonymous") or "nil"))
            if unitFrame then
                local side = self.db.party.anchorSide or "RIGHT"
                local offX = self.db.party.anchorOffsetX or 4
                local offY = self.db.party.anchorOffsetY or 0
                if side == "LEFT" then
                    bar:SetPoint("TOPRIGHT", unitFrame, "TOPLEFT", -offX, offY)
                else
                    bar:SetPoint("TOPLEFT", unitFrame, "TOPRIGHT", offX, offY)
                end
                bar:SetParent(unitFrame)
                return
            end

            -- Frame not found — extrapolate from a nearby frame that does exist
            local refFrame, refSlot = self:FindAnyPartyFrame()
            if refFrame and info.slot then
                local slotDiff = info.slot - refSlot
                local _, frameH = refFrame:GetSize()
                -- Estimate spacing between party frames, with robust fallbacks
                local spacing = self:EstimatePartyFrameSpacing(refFrame, refSlot)
                if not spacing or spacing < 1 then
                    spacing = (frameH and frameH > 1) and (frameH + 4) or 60
                end
                local side = self.db.party.anchorSide or "RIGHT"
                local offX = self.db.party.anchorOffsetX or 4
                local offY = (self.db.party.anchorOffsetY or 0) - (slotDiff * spacing)
                if side == "LEFT" then
                    bar:SetPoint("TOPRIGHT", refFrame, "TOPLEFT", -offX, offY)
                else
                    bar:SetPoint("TOPLEFT", refFrame, "TOPRIGHT", offX, offY)
                end
                bar:SetParent(refFrame:GetParent() or UIParent)
                self:Debug("Extrapolated slot " .. info.slot .. " from frame slot " .. refSlot .. " (spacing=" .. spacing .. ", frameH=" .. (frameH or "nil") .. ", diff=" .. slotDiff .. ")")
                return
            end
            -- Fall through to saved/default position if no frames found at all
        end

        -- Re-parent to UIParent if not anchored to a unit frame
        if bar:GetParent() ~= UIParent then
            bar:SetParent(UIParent)
        end

        local saved = self.db.party.positions[tostring(info.slot)]
        if saved then
            bar:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
        else
            bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
                20, -(200 + (info.slot - 1) * 50))
        end
    end
end

function addon:SaveBarPosition(guid)
    local bar = self.bars[guid]
    local info = self.state.trackedPlayers[guid]
    if not bar or not info or not self.db then return end

    -- Don't save position when bar is anchored to a unit frame (coordinates are relative to it, not UIParent)
    if info.team == "party" and self.db.party.anchorToFrames then return end

    local point, _, relPoint, x, y = bar:GetPoint()
    self.db.party.positions[tostring(info.slot)] = {
        point = point, relPoint = relPoint, x = x, y = y,
    }
end

---------------------------------------------------------------------------
-- Cooldown Icon Creation
---------------------------------------------------------------------------
function addon:CreateCooldownIcon(bar, guid, spellName)
    local cdData = self.COOLDOWN_DB[spellName]
    if not cdData then return end

    local info = self.state.trackedPlayers[guid]
    local size = info and self.db.party.iconSize or self.db.general.iconSize

    local icon = CreateFrame("Frame", nil, bar)
    icon:SetSize(size, size)

    -- Black border frame (extends 1px beyond icon for clean outline)
    icon.bgTex = icon:CreateTexture(nil, "BACKGROUND")
    icon.bgTex:SetPoint("TOPLEFT", -1, 1)
    icon.bgTex:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.bgTex:SetColorTexture(0.04, 0.04, 0.05, 1)

    -- Spell texture (faction-specific for trinkets)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    local texturePath
    if cdData.allianceIcon and cdData.hordeIcon then
        if self.playerFaction == "Alliance" then
            texturePath = cdData.allianceIcon
        else
            texturePath = cdData.hordeIcon
        end
    else
        texturePath = GetSpellTexture(cdData.spellID)
    end
    if texturePath then
        icon.texture:SetTexture(texturePath)
    else
        icon.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown sweep overlay
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(true)
    icon.cooldown:SetDrawBling(false)
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.5)
    icon.cooldown:SetHideCountdownNumbers(false)

    -- Category-colored border (1px at icon edge)
    local catColor = self.CD_CATEGORY_COLORS[cdData.category]
    local br, bg, bb = 0.25, 0.25, 0.25
    if catColor then
        br, bg, bb = catColor.r, catColor.g, catColor.b
    end

    local showBorders = self.db and self.db.general.showIconBorders

    icon.borderTop = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    icon.borderTop:SetPoint("TOPLEFT", 0, 0)
    icon.borderTop:SetPoint("TOPRIGHT", 0, 0)
    icon.borderTop:SetHeight(1)
    icon.borderTop:SetColorTexture(br, bg, bb, 0.85)
    if not showBorders then icon.borderTop:Hide() end

    icon.borderBottom = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    icon.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    icon.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    icon.borderBottom:SetHeight(1)
    icon.borderBottom:SetColorTexture(br, bg, bb, 0.85)
    if not showBorders then icon.borderBottom:Hide() end

    icon.borderLeft = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    icon.borderLeft:SetPoint("TOPLEFT", 0, 0)
    icon.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    icon.borderLeft:SetWidth(1)
    icon.borderLeft:SetColorTexture(br, bg, bb, 0.85)
    if not showBorders then icon.borderLeft:Hide() end

    icon.borderRight = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    icon.borderRight:SetPoint("TOPRIGHT", 0, 0)
    icon.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    icon.borderRight:SetWidth(1)
    icon.borderRight:SetColorTexture(br, bg, bb, 0.85)
    if not showBorders then icon.borderRight:Hide() end

    -- Glow overlay (cooldown-ready effect — bright border flash)
    local glowR, glowG, glowB = 1, 1, 1
    if catColor then glowR, glowG, glowB = catColor.r, catColor.g, catColor.b end
    icon.glowFrame = CreateFrame("Frame", nil, icon)
    icon.glowFrame:SetPoint("TOPLEFT", -2, 2)
    icon.glowFrame:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.glowFrame:SetFrameLevel(icon:GetFrameLevel() + 4)
    icon.glowFrame:SetAlpha(0)
    icon.gfTop = icon.glowFrame:CreateTexture(nil, "OVERLAY")
    icon.gfTop:SetPoint("TOPLEFT"); icon.gfTop:SetPoint("TOPRIGHT"); icon.gfTop:SetHeight(2)
    icon.gfTop:SetColorTexture(glowR, glowG, glowB, 1)
    icon.gfBot = icon.glowFrame:CreateTexture(nil, "OVERLAY")
    icon.gfBot:SetPoint("BOTTOMLEFT"); icon.gfBot:SetPoint("BOTTOMRIGHT"); icon.gfBot:SetHeight(2)
    icon.gfBot:SetColorTexture(glowR, glowG, glowB, 1)
    icon.gfLeft = icon.glowFrame:CreateTexture(nil, "OVERLAY")
    icon.gfLeft:SetPoint("TOPLEFT"); icon.gfLeft:SetPoint("BOTTOMLEFT"); icon.gfLeft:SetWidth(2)
    icon.gfLeft:SetColorTexture(glowR, glowG, glowB, 1)
    icon.gfRight = icon.glowFrame:CreateTexture(nil, "OVERLAY")
    icon.gfRight:SetPoint("TOPRIGHT"); icon.gfRight:SetPoint("BOTTOMRIGHT"); icon.gfRight:SetWidth(2)
    icon.gfRight:SetColorTexture(glowR, glowG, glowB, 1)

    icon.glowAnim = icon.glowFrame:CreateAnimationGroup()
    local glowIn = icon.glowAnim:CreateAnimation("Alpha")
    glowIn:SetFromAlpha(0)
    glowIn:SetToAlpha(1)
    glowIn:SetDuration(0.15)
    glowIn:SetOrder(1)
    local glowOut = icon.glowAnim:CreateAnimation("Alpha")
    glowOut:SetFromAlpha(1)
    glowOut:SetToAlpha(0)
    glowOut:SetDuration(1.2)
    glowOut:SetOrder(2)
    icon.glowAnim:SetScript("OnFinished", function()
        icon.glowFrame:SetAlpha(0)
    end)

    -- Flash overlay (spell-just-used effect)
    icon.flashTexture = icon:CreateTexture(nil, "OVERLAY", nil, 4)
    icon.flashTexture:SetAllPoints()
    icon.flashTexture:SetColorTexture(0.902, 0.224, 0.224, 0)

    icon.flashAnim = icon.flashTexture:CreateAnimationGroup()
    local flashIn = icon.flashAnim:CreateAnimation("Alpha")
    flashIn:SetFromAlpha(0)
    flashIn:SetToAlpha(0.55)
    flashIn:SetDuration(0.06)
    flashIn:SetOrder(1)
    local flashOut = icon.flashAnim:CreateAnimation("Alpha")
    flashOut:SetFromAlpha(0.55)
    flashOut:SetToAlpha(0)
    flashOut:SetDuration(0.3)
    flashOut:SetOrder(2)
    icon.flashAnim:SetScript("OnFinished", function()
        icon.flashTexture:SetAlpha(0)
    end)

    -- Low-timer pulse (pulsing colored border when about to expire)
    local bw = 2  -- border width for glow effects
    icon.lowTimerGlow = CreateFrame("Frame", nil, icon)
    icon.lowTimerGlow:SetPoint("TOPLEFT", -bw, bw)
    icon.lowTimerGlow:SetPoint("BOTTOMRIGHT", bw, -bw)
    icon.lowTimerGlow:SetFrameLevel(icon:GetFrameLevel() + 3)
    icon.lowTimerGlow:SetAlpha(0)
    local ltR, ltG, ltB = 0.9, 0.2, 0.2
    icon.ltTop = icon.lowTimerGlow:CreateTexture(nil, "OVERLAY")
    icon.ltTop:SetPoint("TOPLEFT"); icon.ltTop:SetPoint("TOPRIGHT"); icon.ltTop:SetHeight(bw)
    icon.ltTop:SetColorTexture(ltR, ltG, ltB, 1)
    icon.ltBot = icon.lowTimerGlow:CreateTexture(nil, "OVERLAY")
    icon.ltBot:SetPoint("BOTTOMLEFT"); icon.ltBot:SetPoint("BOTTOMRIGHT"); icon.ltBot:SetHeight(bw)
    icon.ltBot:SetColorTexture(ltR, ltG, ltB, 1)
    icon.ltLeft = icon.lowTimerGlow:CreateTexture(nil, "OVERLAY")
    icon.ltLeft:SetPoint("TOPLEFT"); icon.ltLeft:SetPoint("BOTTOMLEFT"); icon.ltLeft:SetWidth(bw)
    icon.ltLeft:SetColorTexture(ltR, ltG, ltB, 1)
    icon.ltRight = icon.lowTimerGlow:CreateTexture(nil, "OVERLAY")
    icon.ltRight:SetPoint("TOPRIGHT"); icon.ltRight:SetPoint("BOTTOMRIGHT"); icon.ltRight:SetWidth(bw)
    icon.ltRight:SetColorTexture(ltR, ltG, ltB, 1)

    icon.lowTimerAnim = icon.lowTimerGlow:CreateAnimationGroup()
    icon.lowTimerAnim:SetLooping("REPEAT")
    local ltIn = icon.lowTimerAnim:CreateAnimation("Alpha")
    ltIn:SetFromAlpha(0)
    ltIn:SetToAlpha(1)
    ltIn:SetDuration(0.35)
    ltIn:SetOrder(1)
    ltIn:SetSmoothing("IN_OUT")
    local ltOut = icon.lowTimerAnim:CreateAnimation("Alpha")
    ltOut:SetFromAlpha(1)
    ltOut:SetToAlpha(0)
    ltOut:SetDuration(0.35)
    ltOut:SetOrder(2)
    ltOut:SetSmoothing("IN_OUT")

    -- Active buff glow (colored border while ability buff is active)
    icon.activeGlow = CreateFrame("Frame", nil, icon)
    icon.activeGlow:SetPoint("TOPLEFT", -bw, bw)
    icon.activeGlow:SetPoint("BOTTOMRIGHT", bw, -bw)
    icon.activeGlow:SetFrameLevel(icon:GetFrameLevel() + 2)
    icon.activeGlow:SetAlpha(0)
    local agc = self.db and self.db.general.activeGlowColor
    local agR, agG, agB = agc and agc.r or 0.3, agc and agc.g or 1, agc and agc.b or 0.3
    icon.agTop = icon.activeGlow:CreateTexture(nil, "OVERLAY")
    icon.agTop:SetPoint("TOPLEFT"); icon.agTop:SetPoint("TOPRIGHT"); icon.agTop:SetHeight(bw)
    icon.agTop:SetColorTexture(agR, agG, agB, 1)
    icon.agBot = icon.activeGlow:CreateTexture(nil, "OVERLAY")
    icon.agBot:SetPoint("BOTTOMLEFT"); icon.agBot:SetPoint("BOTTOMRIGHT"); icon.agBot:SetHeight(bw)
    icon.agBot:SetColorTexture(agR, agG, agB, 1)
    icon.agLeft = icon.activeGlow:CreateTexture(nil, "OVERLAY")
    icon.agLeft:SetPoint("TOPLEFT"); icon.agLeft:SetPoint("BOTTOMLEFT"); icon.agLeft:SetWidth(bw)
    icon.agLeft:SetColorTexture(agR, agG, agB, 1)
    icon.agRight = icon.activeGlow:CreateTexture(nil, "OVERLAY")
    icon.agRight:SetPoint("TOPRIGHT"); icon.agRight:SetPoint("BOTTOMRIGHT"); icon.agRight:SetWidth(bw)
    icon.agRight:SetColorTexture(agR, agG, agB, 1)

    icon.activeGlowAnim = icon.activeGlow:CreateAnimationGroup()
    icon.activeGlowAnim:SetLooping("REPEAT")
    local agIn = icon.activeGlowAnim:CreateAnimation("Alpha")
    agIn:SetFromAlpha(0.5)
    agIn:SetToAlpha(1)
    agIn:SetDuration(0.6)
    agIn:SetOrder(1)
    agIn:SetSmoothing("IN_OUT")
    local agOut = icon.activeGlowAnim:CreateAnimation("Alpha")
    agOut:SetFromAlpha(1)
    agOut:SetToAlpha(0.5)
    agOut:SetDuration(0.6)
    agOut:SetOrder(2)
    agOut:SetSmoothing("IN_OUT")

    -- Tooltip
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self2)
        if not addon.db or not addon.db.general.showSpellTooltips then return end

        GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(cdData.spellID)
        GameTooltip:AddLine(" ")

        local catLabel = addon.CD_CATEGORY_LABELS[cdData.category] or ""
        GameTooltip:AddLine(catLabel, 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Cooldown: " .. cdData.duration .. "s", 0.8, 0.8, 0.8)

        -- Show remaining time if on CD, and detected spec
        local pInfo = addon.state.trackedPlayers[guid]
        if pInfo then
            local cd = pInfo.cooldowns[spellName]
            if cd then
                local remaining = cd.expirationTime - GetTime()
                if remaining > 0 then
                    GameTooltip:AddLine(string.format("Remaining: %.1fs", remaining), 1, 0.5, 0.5)
                end
                if cd.duration ~= cdData.duration then
                    GameTooltip:AddLine("Talent-adjusted (" .. cdData.duration .. "s base)", 0.5, 0.8, 1)
                end
            end
            if pInfo.spec then
                GameTooltip:AddLine("Spec: " .. pInfo.spec, 0.6, 0.8, 1)
            end
        end

        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Click handler for test mode (simulate cooldown)
    icon:SetScript("OnMouseDown", function(self2, button)
        if button == "LeftButton" and addon.state.testMode then
            addon:SimulateCooldown(guid, spellName)
        end
    end)

    -- Forward drag to parent bar for repositioning when unlocked
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        if addon.db and not addon.db.general.locked then
            bar:StartMoving()
        end
    end)
    icon:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        addon:SaveBarPosition(guid)
    end)

    icon.spellName = spellName
    icon.spellData = cdData

    self.icons[guid] = self.icons[guid] or {}
    self.icons[guid][spellName] = icon

    return icon
end

---------------------------------------------------------------------------
-- Spec Filtering Helper
---------------------------------------------------------------------------
function addon:IsSpellVisibleForSpec(spellName, playerSpec)
    if not playerSpec then return true end
    local cdData = self.COOLDOWN_DB[spellName]
    if not cdData or not cdData.spec then return true end
    return cdData.spec == playerSpec
end

---------------------------------------------------------------------------
-- Bar Update / Layout
---------------------------------------------------------------------------
function addon:UpdatePlayerBar(guid)
    local bar = self.bars[guid]
    local info = self.state.trackedPlayers[guid]
    if not bar or not info then return end

    local settings = self.db.party
    if not settings.enabled then
        bar:Hide()
        return
    end

    local size = settings.iconSize or self.db.general.iconSize
    local padding = 0
    local compactMode = self.db.general.compactMode

    -- Get the grid for this player's class+team
    local grid = self:GetClassGrid(info.class, info.team)
    if not grid then
        bar:Hide()
        return
    end

    local cols = grid.cols or 4

    -- Track which spells are still valid (for hiding stale icons)
    local validSpells = {}
    local visibleCount = 0
    local maxCol = 0
    local maxRow = 0

    -- Iterate grid slots in order
    for i, slot in ipairs(grid.slots) do
        if slot ~= "" and not grid.disabled[i] then
            -- Resolve placeholder names
            local spellName = slot
            if slot == "Racial" then
                spellName = self:ResolveRacialForRace(info.race)
            end

            if spellName and self.COOLDOWN_DB[spellName] then
                validSpells[spellName] = true

                -- In compact mode, skip spells not on cooldown
                local isOnCD = info.cooldowns[spellName] ~= nil
                local showIcon = true
                if compactMode and not isOnCD then
                    local existingIcon = self.icons[guid] and self.icons[guid][spellName]
                    if existingIcon then existingIcon:Hide() end
                    showIcon = false
                end

                -- Spec filtering: hide spec-exclusive spells from other specs
                if showIcon and not self:IsSpellVisibleForSpec(spellName, info.spec) then
                    local existingIcon = self.icons[guid] and self.icons[guid][spellName]
                    if existingIcon then existingIcon:Hide() end
                    showIcon = false
                end

                if showIcon then
                    -- Create or reuse icon
                    local icon = self.icons[guid] and self.icons[guid][spellName]
                    if not icon then
                        icon = self:CreateCooldownIcon(bar, guid, spellName)
                    end

                    if icon then
                        -- Tight packing only in compact mode; spec-filtered icons keep fixed grid slots
                        local col, row
                        if compactMode then
                            col = (visibleCount % cols) + 1
                            row = math.floor(visibleCount / cols) + 1
                        else
                            col = ((i - 1) % cols) + 1
                            row = math.floor((i - 1) / cols) + 1
                        end

                        icon:ClearAllPoints()
                        icon:SetSize(size, size)
                        icon:SetPoint("TOPLEFT", bar, "TOPLEFT",
                            (col - 1) * (size + padding),
                            -((row - 1) * (size + padding)))

                        -- Update cooldown state visuals
                        local bordersOn = self.db and self.db.general.showIconBorders
                        local cd = info.cooldowns[spellName]
                        if cd then
                            icon.cooldown:SetCooldown(cd.startTime, cd.duration)
                            if icon.borderTop then
                                if bordersOn then
                                    icon.borderTop:SetAlpha(0.3)
                                    icon.borderBottom:SetAlpha(0.3)
                                    icon.borderLeft:SetAlpha(0.3)
                                    icon.borderRight:SetAlpha(0.3)
                                else
                                    icon.borderTop:Hide()
                                    icon.borderBottom:Hide()
                                    icon.borderLeft:Hide()
                                    icon.borderRight:Hide()
                                end
                            end
                        else
                            icon.cooldown:Clear()
                            if icon.borderTop then
                                if bordersOn then
                                    icon.borderTop:Show()
                                    icon.borderBottom:Show()
                                    icon.borderLeft:Show()
                                    icon.borderRight:Show()
                                    icon.borderTop:SetAlpha(1.0)
                                    icon.borderBottom:SetAlpha(1.0)
                                    icon.borderLeft:SetAlpha(1.0)
                                    icon.borderRight:SetAlpha(1.0)
                                else
                                    icon.borderTop:Hide()
                                    icon.borderBottom:Hide()
                                    icon.borderLeft:Hide()
                                    icon.borderRight:Hide()
                                end
                            end
                            if icon.lowTimerAnim and icon.lowTimerAnim:IsPlaying() then
                                icon.lowTimerAnim:Stop()
                                icon.lowTimerGlow:SetAlpha(0)
                            end
                        end

                        icon:Show()
                        visibleCount = visibleCount + 1
                        if col > maxCol then maxCol = col end
                        if row > maxRow then maxRow = row end
                    end -- if icon
                end -- if showIcon
            end -- if spellName valid
        end -- if slot not empty/disabled
    end

    -- Hide icons for spells no longer in the grid
    if self.icons[guid] then
        for spellName, icon in pairs(self.icons[guid]) do
            if not validSpells[spellName] then
                icon:Hide()
            end
        end
    end

    -- Use fixed team grid dimensions for consistent bar sizing
    local teamCols = settings.gridCols or 4
    local teamRows = settings.gridRows or 3

    -- In test mode, always show bar outline even with no icons
    if visibleCount == 0 then
        if self.state.testMode then
            bar:SetSize(
                teamCols * (size + padding) - padding,
                teamRows * (size + padding) - padding)
            bar.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.3)
            bar.nameText:Show()
            bar.teamIndicator:Show()
            bar:Show()
        else
            bar:Hide()
        end
        return
    end

    -- Resize bar to fit grid
    if compactMode then
        -- Compact: size to visible icons only
        bar:SetSize(
            maxCol * (size + padding) - padding,
            maxRow * (size + padding) - padding)
    else
        -- Normal: always size to fixed team dimensions
        bar:SetSize(
            teamCols * (size + padding) - padding,
            teamRows * (size + padding) - padding)
    end
    bar:Show()
end

---------------------------------------------------------------------------
-- Icon Effect Updates (active glow + low-timer pulse, called from OnUpdate ticker)
---------------------------------------------------------------------------
function addon:UpdateTimerTexts()
    if not self.db then return end

    local now = GetTime()
    local threshold = 5
    local showPulse = self.db.general.showPulseOnLow

    for guid, iconSet in pairs(self.icons) do
        local info = self.state.trackedPlayers[guid]
        if info then
            for spellName, icon in pairs(iconSet) do
                if icon:IsShown() then
                    local cd = info.cooldowns[spellName]
                    if cd then
                        local remaining = cd.expirationTime - now
                        if remaining > 0 then
                            -- Active buff glow (ability buff still active)
                            if cd.buffExpires and now < cd.buffExpires then
                                if icon.activeGlowAnim and not icon.activeGlowAnim:IsPlaying() then
                                    icon.activeGlowAnim:Play()
                                end
                            else
                                if icon.activeGlowAnim and icon.activeGlowAnim:IsPlaying() then
                                    icon.activeGlowAnim:Stop()
                                    icon.activeGlow:SetAlpha(0)
                                end
                            end

                            -- Low-timer pulse
                            if remaining < threshold then
                                if showPulse and icon.lowTimerAnim
                                        and not icon.lowTimerAnim:IsPlaying() then
                                    icon.lowTimerAnim:Play()
                                end
                            else
                                if icon.lowTimerAnim and icon.lowTimerAnim:IsPlaying() then
                                    icon.lowTimerAnim:Stop()
                                    icon.lowTimerGlow:SetAlpha(0)
                                end
                            end
                        else
                            if icon.activeGlowAnim and icon.activeGlowAnim:IsPlaying() then
                                icon.activeGlowAnim:Stop()
                                icon.activeGlow:SetAlpha(0)
                            end
                            if icon.lowTimerAnim and icon.lowTimerAnim:IsPlaying() then
                                icon.lowTimerAnim:Stop()
                                icon.lowTimerGlow:SetAlpha(0)
                            end
                        end
                    else
                        if icon.activeGlowAnim and icon.activeGlowAnim:IsPlaying() then
                            icon.activeGlowAnim:Stop()
                            icon.activeGlow:SetAlpha(0)
                        end
                        if icon.lowTimerAnim and icon.lowTimerAnim:IsPlaying() then
                            icon.lowTimerAnim:Stop()
                            icon.lowTimerGlow:SetAlpha(0)
                        end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Lock/Unlock
---------------------------------------------------------------------------
function addon:ToggleLock()
    if not self.db then return end
    self.db.general.locked = not self.db.general.locked
    local locked = self.db.general.locked

    for guid, bar in pairs(self.bars) do
        bar:EnableMouse(not locked)
        local info = self.state.trackedPlayers[guid]
        if locked then
            bar.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0)
            bar.teamIndicator:Hide()
            -- Show subtle player labels when locked if setting is on
            if self.db.general.showPlayerLabels and info then
                bar.nameText:SetText(self:ClassColorWrap(info.name, info.class))
                bar.nameText:SetAlpha(0.7)
                bar.nameText:Show()
            else
                bar.nameText:Hide()
            end
        else
            bar.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.3)
            if info then
                bar.nameText:SetText(self:ClassColorWrap(info.name, info.class))
                bar.nameText:SetAlpha(1)
                bar.nameText:Show()
                bar.teamIndicator:Show()
            end
        end
    end

    self:RefreshAllBars()
    self:Print("Bars " .. (locked and "|cff4ADE80locked|r" or "|cffE63939unlocked|r -- drag to reposition"))

    -- Sync all lock toggles in options panel
    if self._lockToggles then
        for _, tog in ipairs(self._lockToggles) do
            if tog.SetChecked then tog:SetChecked(locked) end
        end
    end
end

---------------------------------------------------------------------------
-- Refresh / Hide / Reset
---------------------------------------------------------------------------
function addon:RefreshAllBars()
    -- Create bars for players that don't have one yet
    for guid, info in pairs(self.state.trackedPlayers) do
        if not self.bars[guid] then
            self:CreateBar(guid)
        end
        self:PositionBar(guid)
        self:UpdatePlayerBar(guid)
    end

    -- Hide bars for players no longer tracked
    for guid, bar in pairs(self.bars) do
        if not self.state.trackedPlayers[guid] then
            bar:Hide()
            -- Clean up icon references
            if self.icons[guid] then
                for _, icon in pairs(self.icons[guid]) do
                    icon:Hide()
                end
                self.icons[guid] = nil
            end
        end
    end
end

function addon:HideAllBars()
    for guid, bar in pairs(self.bars) do
        bar:Hide()
    end
end

function addon:ResetAllPositions()
    if not self.db then return end
    wipe(self.db.party.positions)
    self:RefreshAllBars()
    self:Print("All bar positions reset to defaults.")
end

function addon:DestroyBar(guid)
    local bar = self.bars[guid]
    if bar then
        bar:Hide()
        self.bars[guid] = nil
    end
    if self.icons[guid] then
        for _, icon in pairs(self.icons[guid]) do
            icon:Hide()
        end
        self.icons[guid] = nil
    end
end

---------------------------------------------------------------------------
-- Visual Effects
---------------------------------------------------------------------------
function addon:UpdateActiveGlowColor()
    local agc = self.db and self.db.general.activeGlowColor
    local r, g, b = agc and agc.r or 0.3, agc and agc.g or 1, agc and agc.b or 0.3
    for _, iconSet in pairs(self.icons) do
        for _, icon in pairs(iconSet) do
            if icon.agTop then
                icon.agTop:SetColorTexture(r, g, b, 1)
                icon.agBot:SetColorTexture(r, g, b, 1)
                icon.agLeft:SetColorTexture(r, g, b, 1)
                icon.agRight:SetColorTexture(r, g, b, 1)
            end
        end
    end
end

function addon:PlayReadyGlow(icon)
    if not icon or not icon.glowAnim then return end
    icon.glowAnim:Stop()
    icon.glowFrame:SetAlpha(0)
    icon.glowAnim:Play()
end

function addon:PlayUseFlash(icon)
    if not icon or not icon.flashAnim then return end
    icon.flashAnim:Stop()
    icon.flashTexture:SetAlpha(0)
    icon.flashAnim:Play()
end

---------------------------------------------------------------------------
-- Re-anchor (delayed, for party frame anchoring after roster/frame changes)
---------------------------------------------------------------------------
function addon:ScheduleReanchor()
    if self._reanchorTimer then return end
    self._reanchorTimer = C_Timer.After(0.5, function()
        self._reanchorTimer = nil
        if self.db and self.db.party.anchorToFrames then
            for guid, info in pairs(self.state.trackedPlayers) do
                if info.team == "party" then
                    self:PositionBar(guid)
                end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function addon:InitDisplay()
    -- Hook party frame show/hide to reposition bars when frames appear/disappear
    local function hookPartyFrame(frameName)
        local frame = _G[frameName]
        if frame then
            hooksecurefunc(frame, "Show", function()
                addon:ScheduleReanchor()
            end)
            hooksecurefunc(frame, "Hide", function()
                addon:ScheduleReanchor()
            end)
        end
    end

    -- Hook Blizzard party frames (may not exist yet at load time, so pcall)
    for i = 1, 4 do
        pcall(hookPartyFrame, "PartyMemberFrame" .. i)
    end
    for i = 1, 5 do
        pcall(hookPartyFrame, "CompactPartyFrameMember" .. i)
    end
end
