---------------------------------------------------------------------------
-- TrinketedCD: Core.lua
-- Addon namespace, constants, state, event handling, slash commands
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
addon.ADDON_NAME = "TrinketedCD"
addon.VERSION = LibStub("TrinketedLib-1.0"):GetVersion("TrinketedCD")

local TrinketedLib = LibStub("TrinketedLib-1.0")
addon.FONT_DISPLAY = TrinketedLib.FONT_DISPLAY
addon.FONT_BODY    = TrinketedLib.FONT_BODY
addon.FONT_MONO    = TrinketedLib.FONT_MONO

-- Detect arena instance via API instead of hardcoded zone names
function addon:IsInArenaInstance()
    return select(2, IsInInstance()) == "arena"
end

addon.CLASS_COLORS = {
    ["Warrior"]     = { r = 0.78, g = 0.61, b = 0.43, hex = "ffc79c6e" },
    ["Paladin"]     = { r = 0.96, g = 0.55, b = 0.73, hex = "fff58cba" },
    ["Hunter"]      = { r = 0.67, g = 0.83, b = 0.45, hex = "ffabd473" },
    ["Rogue"]       = { r = 1.00, g = 0.96, b = 0.41, hex = "fffff569" },
    ["Priest"]      = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffffff" },
    ["Shaman"]      = { r = 0.00, g = 0.44, b = 0.87, hex = "ff0070de" },
    ["Mage"]        = { r = 0.41, g = 0.80, b = 0.94, hex = "ff69ccf0" },
    ["Warlock"]     = { r = 0.58, g = 0.51, b = 0.79, hex = "ff9482c9" },
    ["Druid"]       = { r = 1.00, g = 0.49, b = 0.04, hex = "ffff7d0a" },
    ["Deathknight"] = { r = 0.77, g = 0.12, b = 0.23, hex = "ffc41f3b" },
}

addon.ALL_CLASSES = {
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
    "Mage", "Warlock", "Shaman", "Druid",
}

addon.ALL_RACES = {
    "Human", "Dwarf", "Night Elf", "Gnome", "Draenei",
    "Orc", "Undead", "Tauren", "Troll", "Blood Elf",
}

---------------------------------------------------------------------------
-- Runtime State
---------------------------------------------------------------------------
addon.state = {
    inArena     = false,
    testMode    = false,

    -- Tracked players: [guid] -> player info table
    trackedPlayers = {},

    -- GUID mapping helpers
    guidMap = {},     -- [guid] -> guid (identity, for existence check)
    unitMap = {},     -- [unit] -> guid

    -- Pet owner mapping for pet abilities (Spell Lock, Gnaw)
    petOwnerMap = {}, -- [petGUID] -> ownerGUID
}

---------------------------------------------------------------------------
-- Default SavedVariables
---------------------------------------------------------------------------
local DEFAULTS = {
    general = {
        locked          = true,
        iconSize        = 36,
        compactMode     = false,
        showIconBorders = true,
        showGlowOnReady = true,
        showFlashOnUse  = true,
        showPulseOnLow  = true,
        showPlayerLabels = true,
        showSpellTooltips = false,
        trackOutsideArena = false,
        activeGlowColor = { r = 0.3, g = 1.0, b = 0.3 },
    },
    party = {
        enabled         = true,
        iconSize        = 36,
        gridCols        = 4,
        gridRows        = 3,
        anchorToFrames  = false,
        anchorSide      = "RIGHT",
        anchorOffsetX   = 4,
        anchorOffsetY   = 0,
        positions       = {},
    },
    cooldowns = {
        grids           = {},
        overrides       = {},
    },
    testMode = {
        lastPlayers     = {},
    },
    debug = false,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function addon:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            self:MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function addon:FormatClassName(class)
    if not class then return nil end
    return class:sub(1, 1):upper() .. class:sub(2):lower()
end

function addon:StripRealm(name)
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

function addon:Print(msg)
    print("|cffE8B923Trinketed:|r " .. msg)
end

function addon:Debug(msg)
    if self.db and self.db.debug then
        print("|cff5C5E66Trinketed [DEBUG]:|r " .. msg)
    end
end

function addon:ClassColorWrap(text, className)
    local c = self.CLASS_COLORS[className]
    if c then
        return "|c" .. c.hex .. text .. "|r"
    end
    return text
end

---------------------------------------------------------------------------
-- Sub-Command Registration (unified under /trinketed)
---------------------------------------------------------------------------
local function RegisterSubCommands()
    local lib = LibStub("TrinketedLib-1.0")

    local function openCD(args)
        if args == "" then
            lib:ShowOptionsPanel("Cooldowns")
        end
    end
    lib:RegisterSubCommand("cd", openCD)
    lib:RegisterSubCommand("cooldown", openCD)
    lib:RegisterSubCommand("cooldowns", openCD)

    lib:RegisterSubCommand("test", function()
        addon:ToggleTestMode()
    end)
    lib:RegisterSubCommand("lock", function()
        addon:ToggleLock()
    end)
    lib:RegisterSubCommand("reset", function()
        addon:ResetAllPositions()
    end)
    lib:RegisterSubCommand("debug", function()
        addon.db.debug = not addon.db.debug
        addon:Print("Debug " .. (addon.db.debug and "|cff4ADE80ON|r" or "|cffE63939OFF|r"))
    end)
end

---------------------------------------------------------------------------
-- Event Frame
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "TrinketedCDFrame", UIParent)
addon.eventFrame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_PET")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addon.ADDON_NAME then
            -- Initialize SavedVariables
            TrinketedCDDB = TrinketedCDDB or {}
            addon:MergeDefaults(TrinketedCDDB, DEFAULTS)
            addon.db = TrinketedCDDB

            -- Cache player faction for faction-specific icons
            addon.playerFaction = UnitFactionGroup("player")

            -- Initialize subsystems
            addon:InitTracker()
            addon:InitDisplay()
            addon:InitOptions()

            -- Detect if already in arena on reload
            if addon:IsInArenaInstance() then
                addon.state.inArena = true
                addon:ClearAllCooldowns()
                addon:ScanPartyMembers()
                addon:ScanPetOwners()
                addon:RefreshAllBars()
            end

            addon:Print(addon.VERSION .. " loaded")
            RegisterSubCommands()
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if addon:IsInArenaInstance() then
            if not addon.state.inArena then
                addon.state.inArena = true
                -- Clear CDs from previous match on arena entry
                addon:ClearAllCooldowns()
                addon:ScanPartyMembers()
                addon:ScanPetOwners()
                addon:RefreshAllBars()
            end
        else
            if addon.state.inArena then
                addon.state.inArena = false
                -- Don't clear cooldowns — let them persist for post-match review
                addon:HideAllBars()
                -- Clear non-test tracked players and associated maps
                local toRemove = {}
                for guid in pairs(addon.state.trackedPlayers) do
                    if not tostring(guid):match("^test_") then
                        toRemove[#toRemove + 1] = guid
                    end
                end
                for _, guid in ipairs(toRemove) do
                    addon.state.trackedPlayers[guid] = nil
                    addon.state.guidMap[guid] = nil
                end
                wipe(addon.state.unitMap)
                wipe(addon.state.petOwnerMap)
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if addon.state.inArena or addon.state.testMode or (addon.db and addon.db.general.trackOutsideArena and not IsInRaid()) then
            addon:ScanPartyMembers()
            addon:ScanPetOwners()
            addon:RefreshAllBars()
        elseif IsInRaid() then
            addon:ScanPartyMembers() -- raid branch tears down party bars
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if addon.state.inArena or addon.state.testMode or (addon.db and addon.db.general.trackOutsideArena and not IsInRaid()) then
            addon:ScanPartyMembers()
            addon:ScanPetOwners()
            addon:RefreshAllBars()
            addon:ScheduleReanchor()
        elseif IsInRaid() then
            -- Joining/converting to a raid outside arena: without this the
            -- guard above skipped ScanPartyMembers entirely, so its raid
            -- teardown never ran and stale bars stayed on screen frozen.
            addon:ScanPartyMembers()
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        addon:OnCombatLogEvent()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        addon:OnUnitSpellcast(...)

    elseif event == "UNIT_PET" then
        -- Re-map when a party member (re)summons/swaps a pet
        if addon.state.inArena or addon.state.testMode or (addon.db and addon.db.general.trackOutsideArena and not IsInRaid()) then
            addon:ScanPetOwners()
        end
    end
end)
