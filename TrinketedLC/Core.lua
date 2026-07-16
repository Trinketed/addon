---------------------------------------------------------------------------
-- TrinketedLC: Core.lua
-- Namespace, SavedVariables, registration, event dispatch.
-- A faithful port of BetterBlizzFrames' Loss-of-Control alert for the
-- Trinketed suite: a center-screen frame that shows the icon, effect name
-- (e.g. "Cycloned"), the duration, and red top/bottom edges for the
-- highest-priority CC / silence / disarm / root / interrupt affecting you.
---------------------------------------------------------------------------
local ADDON, ns = ...
local lib = LibStub("TrinketedLib-1.0")

local addon = {}
ns.addon = addon
TrinketedLC = addon   -- global handle for slash/debug

addon.ADDON_NAME = ADDON
addon.VERSION = lib:GetVersion("TrinketedLC")
addon.FONT_DISPLAY = lib.FONT_DISPLAY
addon.FONT_BODY    = lib.FONT_BODY
addon.FONT_MONO    = lib.FONT_MONO

---------------------------------------------------------------------------
-- Default SavedVariables (mirrors BetterBlizzFrames' LoC frame options)
---------------------------------------------------------------------------
local DEFAULTS = {
    version = 2,
    locked  = true,
    enabled = true,        -- show the alert at all (BBF: enableLoCFrame)
    scale   = 1,           -- BBF: lossOfControlScale
    iconOnly = false,      -- BBF: lossOfControlIconOnly (hide name/duration)
    showCooldown = false,  -- BBF: showCooldownOnLoC (cooldown swipe on main icon)
    hideBackground = false, -- BBF: hideLossOfControlFrameBg
    hideRedLines = false,  -- BBF: hideLossOfControlFrameLines
    x = 0,
    y = 0,
    -- [spellId] = "Label" to add/override; "Ignore" to suppress
    customSpellIds = {},
}

addon.DEFAULTS = DEFAULTS

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

-- Effective effect label for a spellId, honouring customSpellIds overrides.
function addon:GetLabel(spellId)
    local custom = self.db.customSpellIds[spellId]
    if custom ~= nil then
        if custom == "Ignore" then return nil end
        return custom
    end
    return ns.Data.spellList[spellId]
end

---------------------------------------------------------------------------
-- Slash sub-command registration (under /trinketed)
---------------------------------------------------------------------------
local function RegisterSubCommands()
    local function openLC(args)
        if args == "" or args == nil then
            lib:ShowOptionsPanel("Lose Control")
        end
    end
    lib:RegisterSubCommand("lc", openLC)
    lib:RegisterSubCommand("losecontrol", openLC)

    lib:RegisterSubCommand("lclock", function()
        addon:ToggleLock()
    end)
    lib:RegisterSubCommand("lctest", function()
        ns.Display:ToggleTest()
    end)
end

---------------------------------------------------------------------------
-- Lock / unlock (drag to reposition the alert)
---------------------------------------------------------------------------
function addon:ToggleLock()
    self.db.locked = not self.db.locked
    ns.Display:SetLocked(self.db.locked)
    self:Print("Lose Control alert " .. (self.db.locked and "|cff4ADE80locked|r" or "|cffE63939unlocked|r (drag to move)"))
end

---------------------------------------------------------------------------
-- Event frame
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "TrinketedLCFrame", UIParent)
addon.eventFrame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end

        TrinketedLCDB = TrinketedLCDB or {}
        addon:MergeDefaults(TrinketedLCDB, DEFAULTS)
        addon.db = TrinketedLCDB

        ns.Display:Init()
        addon:InitOptions()

        ns.Display:RefreshAll()
        addon:Print(addon.VERSION .. " loaded")
        RegisterSubCommands()

        -- Switch over to live tracking events now that we are initialized.
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("UNIT_AURA")
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        return
    end

    ns.Display:OnEvent(event, ...)
end)
