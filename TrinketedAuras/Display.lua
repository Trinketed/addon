---------------------------------------------------------------------------
-- TrinketedAuras: Display.lua
-- Icon-group rendering: one draggable container per configured group,
-- pooled icon frames with duration text, stack count and cooldown swipe.
-- Live data comes from UNIT_AURA scans of the player; unlock/test modes
-- render preview icons built from each group's configured aura list.
---------------------------------------------------------------------------
local ADDON, ns = ...
local addon = ns.addon
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local GetTime      = GetTime
local C_UnitAuras  = C_UnitAuras
local GetSpellInfo = GetSpellInfo
local sformat      = string.format
local mfloor       = math.floor
local mceil        = math.ceil

local Display = {}
ns.Display = Display

Display.locked      = true
Display.unlockMode  = false
Display.testMode    = false
Display.groupFrames = {}

local FALLBACK_ICON = 134400   -- INV_Misc_QuestionMark

---------------------------------------------------------------------------
-- Spell helpers (entries may be a spellId or a spell name)
---------------------------------------------------------------------------
local function SpellIcon(spell)
    if type(spell) == "number" and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spell)
        if tex then return tex end
    end
    local _, _, icon = GetSpellInfo(spell)
    return icon or FALLBACK_ICON
end

local function EntryMatches(entry, aura)
    if type(entry.spell) == "number" then
        return aura.spellId == entry.spell
    end
    return aura.name and entry.spell and aura.name:lower() == tostring(entry.spell):lower()
end

local function FormatDuration(t)
    if t >= 60 then
        return sformat("%dm", mceil(t / 60))
    elseif t >= 10 then
        return sformat("%d", mfloor(t + 0.5))
    end
    return sformat("%.1f", t)
end

function Display:IsPreviewing()
    return self.unlockMode or self.testMode
end

---------------------------------------------------------------------------
-- Icon pool (per container)
---------------------------------------------------------------------------
local function AcquireIcon(container, index)
    local icon = container.icons[index]
    if icon then return icon end

    icon = CreateFrame("Frame", nil, container)

    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.border:SetColorTexture(0, 0, 0, 0.9)

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.tex)
    icon.cooldown:SetHideCountdownNumbers(true)
    icon.cooldown:SetDrawEdge(false)

    -- Text sits on its own frame so the swipe can't draw over it.
    icon.textFrame = CreateFrame("Frame", nil, icon)
    icon.textFrame:SetAllPoints()
    icon.textFrame:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)

    icon.duration = icon.textFrame:CreateFontString(nil, "OVERLAY")
    icon.duration:SetFont(addon.FONT_DISPLAY, 13, "OUTLINE")
    icon.duration:SetPoint("CENTER", 0, 0)

    icon.stacks = icon.textFrame:CreateFontString(nil, "OVERLAY")
    icon.stacks:SetFont(addon.FONT_DISPLAY, 11, "OUTLINE")
    icon.stacks:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.stacks:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    container.icons[index] = icon
    return icon
end

---------------------------------------------------------------------------
-- Group containers
---------------------------------------------------------------------------
local function ApplyGroupPosition(container)
    local group = container.group
    if not group then return end
    local s = group.scale or 1
    container:SetScale(s)
    container:SetSize(group.iconSize, group.iconSize)
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", (group.x or 0) / s, (group.y or 0) / s)
end

local function CreateContainer(index)
    local container = CreateFrame("Frame", "TrinketedAurasGroup" .. index, UIParent)
    container:SetSize(40, 40)
    container:SetMovable(true)
    container:EnableMouse(false)
    container:SetClampedToScreen(true)
    container:RegisterForDrag("LeftButton")
    container.icons = {}
    container.activeCount = 0

    -- Unlock-mode anchor overlay (gold block + group name above it).
    container.overlay = CreateFrame("Frame", nil, container)
    container.overlay:SetAllPoints()
    container.overlay:SetFrameLevel(container:GetFrameLevel() + 10)
    container.overlay:Hide()

    local overlayBg = container.overlay:CreateTexture(nil, "BACKGROUND")
    overlayBg:SetAllPoints()
    overlayBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.25)

    container.overlay.label = container.overlay:CreateFontString(nil, "OVERLAY")
    container.overlay.label:SetFont(addon.FONT_DISPLAY, 11, "OUTLINE")
    container.overlay.label:SetPoint("BOTTOM", container, "TOP", 0, 4)
    container.overlay.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    container:SetScript("OnDragStart", function(self)
        if not Display.locked then self:StartMoving() end
    end)
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local group = self.group
        if not group then return end
        -- Store offsets in UIParent units so changing scale later keeps
        -- the group anchored at the same screen position.
        local s = self:GetScale()
        local cx, cy = self:GetCenter()
        group.x = cx * s - UIParent:GetWidth() / 2
        group.y = cy * s - UIParent:GetHeight() / 2
        ApplyGroupPosition(self)
    end)

    return container
end

-- Create/refresh one container per configured group; hide leftovers.
function Display:BuildGroups()
    local groups = addon.db.groups
    for i, group in ipairs(groups) do
        local container = self.groupFrames[i]
        if not container then
            container = CreateContainer(i)
            self.groupFrames[i] = container
        end
        container.group = group
        container.overlay.label:SetText(group.name or ("Group " .. i))
        container:EnableMouse(not self.locked)
        container.overlay:SetShown(not self.locked)
        container:Show()
    end
    for i = #groups + 1, #self.groupFrames do
        local container = self.groupFrames[i]
        container.group = nil
        container.overlay:Hide()
        container:Hide()
    end
end

---------------------------------------------------------------------------
-- Layout: place [actives] into a container per its group settings
---------------------------------------------------------------------------
function Display:LayoutGroup(container, actives)
    local group = container.group
    local n = #actives
    container.activeCount = n
    if not group then return end

    local size = group.iconSize or 40
    local step = size + (group.spacing or 4)
    local grow = group.grow or "RIGHT"
    local totalW = n > 0 and (n - 1) * step + size or size

    for i, data in ipairs(actives) do
        local icon = AcquireIcon(container, i)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        if grow == "RIGHT" then
            icon:SetPoint("LEFT", container, "LEFT", (i - 1) * step, 0)
        elseif grow == "LEFT" then
            icon:SetPoint("RIGHT", container, "RIGHT", -(i - 1) * step, 0)
        elseif grow == "UP" then
            icon:SetPoint("BOTTOM", container, "BOTTOM", 0, (i - 1) * step)
        elseif grow == "DOWN" then
            icon:SetPoint("TOP", container, "TOP", 0, -(i - 1) * step)
        else -- CENTER
            icon:SetPoint("CENTER", container, "CENTER", (i - 1) * step - (totalW - size) / 2, 0)
        end

        icon.tex:SetTexture(data.icon or FALLBACK_ICON)
        icon.expirationTime = data.expirationTime
        icon.durationVal = data.duration

        if group.showSwipe and data.duration and data.duration > 0 and data.expirationTime then
            icon.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
            icon.cooldown:Show()
        else
            icon.cooldown:Hide()
        end

        if group.showStacks and (data.count or 0) > 1 then
            icon.stacks:SetText(data.count)
        else
            icon.stacks:SetText("")
        end

        icon.duration:SetFont(addon.FONT_DISPLAY, group.durationFontSize or 13, "OUTLINE")
        icon.duration:ClearAllPoints()
        local anchor = group.durationAnchor or "CENTER"
        if anchor == "ABOVE" then
            icon.duration:SetPoint("BOTTOM", icon, "TOP", 0, 2)
        elseif anchor == "BELOW" then
            icon.duration:SetPoint("TOP", icon, "BOTTOM", 0, -2)
        else
            icon.duration:SetPoint("CENTER", icon, "CENTER", 0, 0)
        end
        icon.duration:SetShown(group.showDuration and true or false)
        icon:Show()
    end

    for i = n + 1, #container.icons do
        container.icons[i]:Hide()
    end

    self:UpdateContainerTexts(container, GetTime())
end

---------------------------------------------------------------------------
-- Live aura scan
---------------------------------------------------------------------------
local function ScanPlayerAuras(filter, out)
    for i = 1, 80 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if not aura then break end
        out[#out + 1] = aura
    end
end

local function CollectActives(group, buffs, debuffs)
    local actives, used = {}, {}
    for _, entry in ipairs(group.auras) do
        local list = entry.filter == "HARMFUL" and debuffs or buffs
        for _, aura in ipairs(list) do
            if not used[aura] and EntryMatches(entry, aura)
                and (not entry.onlyMine or aura.sourceUnit == "player") then
                used[aura] = true
                actives[#actives + 1] = {
                    icon = aura.icon,
                    count = aura.applications or aura.charges or 0,
                    duration = aura.duration,
                    expirationTime = aura.expirationTime and aura.expirationTime > 0 and aura.expirationTime or nil,
                }
            end
        end
    end

    if group.sortByTime then
        table.sort(actives, function(a, b)
            return (a.expirationTime or math.huge) < (b.expirationTime or math.huge)
        end)
    end
    return actives
end

function Display:Refresh()
    if self:IsPreviewing() then return end

    if not addon.db.enabled then
        for _, container in ipairs(self.groupFrames) do
            self:LayoutGroup(container, {})
        end
        return
    end

    local needHelpful, needHarmful = false, false
    for _, group in ipairs(addon.db.groups) do
        if group.enabled then
            for _, entry in ipairs(group.auras) do
                if entry.filter == "HARMFUL" then needHarmful = true else needHelpful = true end
            end
        end
    end

    local buffs, debuffs = {}, {}
    if needHelpful then ScanPlayerAuras("HELPFUL", buffs) end
    if needHarmful then ScanPlayerAuras("HARMFUL", debuffs) end

    for _, container in ipairs(self.groupFrames) do
        local group = container.group
        if group and group.enabled then
            self:LayoutGroup(container, CollectActives(group, buffs, debuffs))
        else
            self:LayoutGroup(container, {})
        end
    end
end

function Display:RefreshAll()
    if self:IsPreviewing() then
        self:ShowPreview()
    else
        self:Refresh()
    end
end

---------------------------------------------------------------------------
-- Apply saved settings (position, scale, layout) to every group
---------------------------------------------------------------------------
function Display:ApplySettings()
    self:BuildGroups()
    for _, container in ipairs(self.groupFrames) do
        if container.group then
            ApplyGroupPosition(container)
        end
    end
    self:RefreshAll()
end

---------------------------------------------------------------------------
-- Duration text ticker (also drives preview countdown resets)
---------------------------------------------------------------------------
function Display:UpdateContainerTexts(container, now)
    local group = container.group
    if not group then return end
    local previewing = self:IsPreviewing()
    local needRefresh = false

    for i = 1, container.activeCount do
        local icon = container.icons[i]
        if icon and icon.expirationTime then
            local remaining = icon.expirationTime - now
            if remaining <= 0 then
                if previewing then
                    -- Loop the fake countdown.
                    local dur = icon.durationVal or 15
                    icon.expirationTime = now + dur
                    if group.showSwipe then
                        icon.cooldown:SetCooldown(now, dur)
                    end
                    remaining = dur
                else
                    needRefresh = true
                end
            end
            if remaining > 0 then
                icon.duration:SetText(FormatDuration(remaining))
                if remaining < 5 then
                    icon.duration:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
                else
                    icon.duration:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
                end
            end
        elseif icon then
            icon.duration:SetText("")
        end
    end

    return needRefresh
end

local ticker = CreateFrame("Frame")
local accum = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    accum = accum + elapsed
    if accum < 0.1 then return end
    accum = 0
    local now = GetTime()
    local needRefresh = false
    for _, container in ipairs(Display.groupFrames) do
        if container:IsShown() and Display:UpdateContainerTexts(container, now) then
            needRefresh = true
        end
    end
    if needRefresh then
        Display:Refresh()
    end
end)

---------------------------------------------------------------------------
-- Preview (unlock + test): fake icons from each group's configured auras
---------------------------------------------------------------------------
local function BuildPreviewActives(group)
    local now = GetTime()
    local actives = {}
    local entries = group.auras
    local count = math.max(#entries, 1)

    for i = 1, count do
        local entry = entries[i]
        local dur = 8 + (i - 1) * 7
        actives[#actives + 1] = {
            icon = entry and SpellIcon(entry.spell) or FALLBACK_ICON,
            count = (i % 3) + 1,
            duration = dur,
            expirationTime = now + dur,
        }
    end
    return actives
end

function Display:ShowPreview()
    for _, container in ipairs(self.groupFrames) do
        local group = container.group
        if group and (self.unlockMode or group.enabled) then
            self:LayoutGroup(container, BuildPreviewActives(group))
        elseif group then
            self:LayoutGroup(container, {})
        end
    end
end

---------------------------------------------------------------------------
-- Lock / unlock (drag groups to reposition)
---------------------------------------------------------------------------
function Display:SetLocked(locked)
    self.locked = locked
    self.unlockMode = not locked
    self.testMode = false

    for _, container in ipairs(self.groupFrames) do
        container:EnableMouse(not locked)
        container.overlay:SetShown(not locked and container.group ~= nil)
    end

    if locked then
        self:Refresh()
    else
        self:ShowPreview()
    end
end

---------------------------------------------------------------------------
-- Test mode (preview icons without real auras)
---------------------------------------------------------------------------
function Display:ToggleTest()
    if not self.locked then return end
    self.testMode = not self.testMode
    if self.testMode then
        self:ShowPreview()
        addon:Print("Aura group test |cff4ADE80ON|r")
    else
        self:Refresh()
        addon:Print("Aura group test |cffE63939OFF|r")
    end
end

---------------------------------------------------------------------------
-- Init + event dispatch (called from Core)
---------------------------------------------------------------------------
function Display:Init()
    self.locked = addon.db.locked
    self.unlockMode = not addon.db.locked
    self:ApplySettings()
    self:SetLocked(addon.db.locked)
end

function Display:OnEvent(event, ...)
    if event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then self:Refresh() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:Refresh()
    end
end
