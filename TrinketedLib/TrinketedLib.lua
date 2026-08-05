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

    -- Feedback
    statusSuccess = { 0.290, 0.870, 0.500 },
    statusError   = { 0.902, 0.224, 0.224 },
}

---------------------------------------------------------------------------
-- Version Helper
---------------------------------------------------------------------------
function lib:GetVersion(addonName)
    local v = C_AddOns.GetAddOnMetadata(addonName or "Trinketed", "Version")
    if not v or v:find("^@") then return "dev" end
    return v
end

---------------------------------------------------------------------------
-- Sub-Addon Registry
---------------------------------------------------------------------------
lib.subAddons = lib.subAddons or {}
lib.subCommands = lib.subCommands or {}

function lib:RegisterSubAddon(name, opts)
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

---------------------------------------------------------------------------
-- Shrink-to-fit for FontStrings
-- WoW's UI space is resolution-independent (768 units tall on any screen),
-- but glyphs rasterize at PHYSICAL pixel sizes — so the same string can be
-- a few units wider on a 1080p screen than on 1440p, enough to clip in a
-- tightly budgeted column. Call after SetText: restores the FontString's
-- base size, then steps the font size down (never up) until the string
-- fits maxWidth. The base size is remembered per FontString, so pooled/
-- recycled rows re-fit correctly for each new string.
---------------------------------------------------------------------------
function lib:FitText(fs, maxWidth)
    local font, size, flags = fs:GetFont()
    if not font then return end
    local base = fs.__fitBaseSize
    if not base then
        base = size
        fs.__fitBaseSize = size
    elseif size ~= base then
        fs:SetFont(font, base, flags)
    end
    maxWidth = maxWidth or fs:GetWidth()
    if not maxWidth or maxWidth <= 0 then return end
    local w = fs:GetStringWidth()
    if w <= maxWidth or w == 0 then return end
    -- Linear estimate with a safety margin, then one corrective step —
    -- glyph metrics aren't perfectly linear in point size.
    local newSize = math.max(6, base * maxWidth / w * 0.97)
    fs:SetFont(font, newSize, flags)
    local w2 = fs:GetStringWidth()
    if w2 > maxWidth then
        fs:SetFont(font, math.max(6, newSize * maxWidth / w2 * 0.97), flags)
    end
end
