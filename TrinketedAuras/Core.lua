---------------------------------------------------------------------------
-- TrinketedAuras: Core.lua
-- Namespace, SavedVariables, registration, event dispatch.
-- Personal aura tracker for the Trinketed suite: user-configurable icon
-- groups that watch chosen buffs/debuffs on the player (e.g. Lifebloom)
-- and show remaining duration, stack count and a cooldown swipe. Each
-- group is independently draggable, scalable and stylable.
---------------------------------------------------------------------------
local ADDON, ns = ...
local lib = LibStub("TrinketedLib-1.0")

local addon = {}
ns.addon = addon
TrinketedAuras = addon   -- global handle for slash/debug

addon.ADDON_NAME = ADDON
addon.VERSION = lib:GetVersion("TrinketedAuras")
addon.FONT_DISPLAY = lib.FONT_DISPLAY
addon.FONT_BODY    = lib.FONT_BODY
addon.FONT_MONO    = lib.FONT_MONO

---------------------------------------------------------------------------
-- Default SavedVariables
---------------------------------------------------------------------------
local DEFAULTS = {
    version = 1,
    enabled = true,
    locked  = true,
    groups  = {},   -- seeded below on first load
}

-- Per-group defaults (scalar fields only; the auras list is never merged
-- so removing a default entry stays removed).
local GROUP_DEFAULTS = {
    name = "Group",
    enabled = true,
    x = 0,
    y = -160,
    grow = "RIGHT",        -- LEFT | RIGHT | UP | DOWN | CENTER
    iconSize = 40,
    spacing = 4,
    scale = 1,
    showDuration = true,
    showStacks = true,
    showSwipe = true,
    durationFontSize = 13,
    durationAnchor = "CENTER",  -- ABOVE | CENTER | BELOW
    sortByTime = true,
}

addon.DEFAULTS = DEFAULTS
addon.GROUP_DEFAULTS = GROUP_DEFAULTS

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function addon:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            self:MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function addon:Print(msg)
    print("|cffE8B923Trinketed:|r " .. msg)
end

-- Fresh group table with default settings and an empty aura list.
-- Aura entries look like: { spell = 33763 or "Lifebloom", filter = "HELPFUL"|"HARMFUL", onlyMine = true|false }
function addon:NewGroup(name)
    local group = { auras = {} }
    self:MergeDefaults(group, GROUP_DEFAULTS)
    group.name = name or GROUP_DEFAULTS.name
    return group
end

---------------------------------------------------------------------------
-- Slash sub-command registration (under /trinketed)
---------------------------------------------------------------------------
local function RegisterSubCommands()
    local function openAuras(args)
        if args == "" or args == nil then
            lib:ShowOptionsPanel("Auras")
        end
    end
    lib:RegisterSubCommand("auras", openAuras)
    lib:RegisterSubCommand("buffs", openAuras)

    lib:RegisterSubCommand("auraslock", function()
        addon:ToggleLock()
    end)
    lib:RegisterSubCommand("aurastest", function()
        ns.Display:ToggleTest()
    end)
end

---------------------------------------------------------------------------
-- Lock / unlock (drag groups to reposition)
---------------------------------------------------------------------------
function addon:ToggleLock()
    self.db.locked = not self.db.locked
    ns.Display:SetLocked(self.db.locked)
    self:Print("Aura groups " .. (self.db.locked and "|cff4ADE80locked|r" or "|cffE63939unlocked|r (drag to move)"))
end

---------------------------------------------------------------------------
-- Event frame
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "TrinketedAurasFrame", UIParent)
addon.eventFrame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end

        TrinketedAurasDB = TrinketedAurasDB or {}
        addon:MergeDefaults(TrinketedAurasDB, DEFAULTS)
        addon.db = TrinketedAurasDB

        -- Seed the starter Lifebloom group on a fresh install, then make
        -- sure every group picks up any settings added in later versions.
        if #addon.db.groups == 0 then
            local group = addon:NewGroup("Lifebloom")
            group.auras[1] = { spell = 33763, filter = "HELPFUL", onlyMine = true }
            addon.db.groups[1] = group
        end
        for _, group in ipairs(addon.db.groups) do
            addon:MergeDefaults(group, GROUP_DEFAULTS)
            group.auras = group.auras or {}
        end

        ns.Display:Init()
        addon:InitOptions()

        ns.Display:RefreshAll()
        addon:Print(addon.VERSION .. " loaded")
        RegisterSubCommands()

        -- Switch over to live tracking events now that we are initialized.
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterUnitEvent("UNIT_AURA", "player")
        return
    end

    ns.Display:OnEvent(event, ...)
end)
