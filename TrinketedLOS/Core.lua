---------------------------------------------------------------------------
-- TrinketedLOS: Core.lua
-- Namespace, SavedVariables, addon comms, and the detection pipeline.
--
-- When the player gets a "Target not in line of sight" UI error while their
-- intended target is a friendly group member, this broadcasts an addon
-- message over the party/raid/instance channel. Any ally running the addon
-- whose GUID matches the blocked target shows an on-screen alert telling
-- them to reposition. Purely cooperative: non-addon users simply ignore the
-- hidden addon message, and enemies are never targeted.
---------------------------------------------------------------------------
local ADDON, ns = ...
local lib = LibStub("TrinketedLib-1.0")

local addon = {}
ns.addon = addon
TrinketedLOS = addon   -- global handle for slash/debug

addon.ADDON_NAME = ADDON
addon.VERSION = lib:GetVersion("TrinketedLOS")
addon.FONT_DISPLAY = lib.FONT_DISPLAY
addon.FONT_BODY    = lib.FONT_BODY
addon.FONT_MONO    = lib.FONT_MONO

local PREFIX = "TrinketedLOS"
local PROTO  = 1              -- wire protocol version
local SEP    = "\t"           -- payload delimiter (never appears in names/spells)

addon.PREFIX = PREFIX

-- Frequently used API locals
local GetTime          = GetTime
local UnitGUID         = UnitGUID
local UnitExists       = UnitExists
local UnitIsPlayer     = UnitIsPlayer
local UnitInParty      = UnitInParty
local UnitInRaid       = UnitInRaid
local IsInGroup        = IsInGroup
local IsInRaid         = IsInRaid
local UnitName         = UnitName
local GetUnitName      = GetUnitName
local C_ChatInfo       = C_ChatInfo
local C_Spell          = C_Spell
local strsplit         = strsplit

local LE_INSTANCE = LE_PARTY_CATEGORY_INSTANCE

---------------------------------------------------------------------------
-- Default SavedVariables
---------------------------------------------------------------------------
local DEFAULTS = {
    version = 1,
    enabled = true,           -- master switch
    sendEnabled = true,       -- broadcast when I lose LOS on an ally
    receiveEnabled = true,    -- show alerts when an ally can't see me
    onlyInstanced = false,    -- only operate inside arenas/BGs/dungeons
    playSound = true,
    throttle = 1.5,           -- min seconds between pings per target
    -- Alert frame
    locked = true,
    scale = 1,
    x = 0,
    y = 140,
    holdTime = 3,             -- seconds the alert stays up
    debug = false,
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

function addon:Debug(msg)
    if self.db and self.db.debug then
        print("|cffE8B923Trinketed|r |cff8C8C94LOS:|r " .. msg)
    end
end

-- Strip realm suffix so "Bob-Frostmourne" and "Bob" compare equal.
local function ShortName(name)
    if not name then return nil end
    local base = name:match("^([^%-]+)")
    return base or name
end

-- The channel to broadcast on, matching the current group context.
local function GetGroupChannel()
    if IsInGroup(LE_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end
addon.GetGroupChannel = GetGroupChannel

-- Iterate the unit tokens of the current group (excludes the player).
local function ForEachGroupUnit(fn)
    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) then fn(u) end
        end
    else
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then fn(u) end
        end
    end
end

-- Resolve a target NAME (from UNIT_SPELLCAST_SENT) to a friendly group unit.
local function GroupUnitByName(name)
    if not name then return nil end
    local short = ShortName(name)
    local found
    ForEachGroupUnit(function(u)
        if not found and UnitIsPlayer(u) then
            if ShortName(UnitName(u)) == short or ShortName(GetUnitName(u, true)) == short then
                found = u
            end
        end
    end)
    return found
end

-- Is this unit a friendly group member (not the player)?
local function IsFriendlyGroupUnit(u)
    return UnitExists(u) and UnitIsPlayer(u) and (UnitInParty(u) or UnitInRaid(u))
        and not UnitIsUnit(u, "player")
end

---------------------------------------------------------------------------
-- Detection state
---------------------------------------------------------------------------
-- Most recent spell the player sent, so we can attribute an LOS error that
-- carries no target/spell of its own.
local lastCast = { name = nil, spell = nil, t = 0 }

-- Per-GUID send throttle.
local lastSent = {}

-- Allies we've pinged and are waiting to clear once we land a cast on them.
local pendingPings = {}

-- castGUID -> target name, so UNIT_SPELLCAST_SUCCEEDED can be attributed to
-- the ally it landed on. Size-capped to avoid growth from casts that never
-- succeed (e.g. the LOS-failed cast itself).
local castTargets = {}
local castTargetsN = 0

local function ShouldOperate()
    local db = addon.db
    if not db.enabled then return false end
    if db.onlyInstanced then
        local inInstance = IsInInstance()
        if not inInstance then return false end
    end
    return true
end

-- Work out who the player just failed to reach, preferring the freshly-sent
-- cast target and falling back to the current target/focus/mouseover.
local function ResolveBlockedAlly()
    local now = GetTime()

    if lastCast.name and (now - lastCast.t) <= 2.0 then
        local unit = GroupUnitByName(lastCast.name)
        if unit then return unit, lastCast.spell end
    end

    for _, u in ipairs({ "target", "focus", "mouseover" }) do
        if IsFriendlyGroupUnit(u) then
            return u, lastCast.spell
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Outgoing: broadcast an LOS ping about a blocked ally
---------------------------------------------------------------------------
local function BroadcastLOS(unit, spellName)
    local db = addon.db
    if not db.sendEnabled then return end

    local channel = GetGroupChannel()
    if not channel then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    local now = GetTime()
    if lastSent[guid] and (now - lastSent[guid]) < (db.throttle or 1.5) then return end
    lastSent[guid] = now
    pendingPings[guid] = now

    local payload = table.concat({ PROTO, "L", guid, spellName or "" }, SEP)
    C_ChatInfo.SendAddonMessage(PREFIX, payload, channel)
    addon:Debug("sent LOS ping for " .. (UnitName(unit) or "?") .. " on " .. channel)
end

-- Tell the ally to drop the alert now that we've reached them.
local function SendClear(guid)
    local channel = GetGroupChannel()
    if not channel or not guid then return end
    local payload = table.concat({ PROTO, "C", guid }, SEP)
    C_ChatInfo.SendAddonMessage(PREFIX, payload, channel)
    addon:Debug("sent LOS clear for " .. guid)
end

-- A cast just succeeded on castGUID; if it landed on an ally we pinged, clear.
local function OnCastSucceeded(castGUID)
    if not castGUID then return end
    local targetName = castTargets[castGUID]
    if targetName ~= nil then
        castTargets[castGUID] = nil
        castTargetsN = castTargetsN - 1
    end
    if not targetName then return end

    local unit = GroupUnitByName(targetName)
    if not unit then return end
    local guid = UnitGUID(unit)
    if guid and pendingPings[guid] then
        pendingPings[guid] = nil
        SendClear(guid)
    end
end

local function OnLineOfSightError()
    if not ShouldOperate() then return end
    local unit, spell = ResolveBlockedAlly()
    if unit then
        BroadcastLOS(unit, spell)
    end
end

---------------------------------------------------------------------------
-- Incoming: an ally reported they can't see us
---------------------------------------------------------------------------
local function OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if not addon.db.receiveEnabled then return end

    local proto, kind, guid, spellName = strsplit(SEP, text)
    if tonumber(proto) ~= PROTO then return end
    if guid ~= UnitGUID("player") then return end   -- not about me

    local who = ShortName(sender) or "Ally"
    if kind == "C" then
        addon:Debug("incoming LOS clear from " .. tostring(sender))
        ns.Display:ClearAlert(who)
    else
        addon:Debug("incoming LOS from " .. tostring(sender))
        ns.Display:ShowAlert(who, (spellName and spellName ~= "") and spellName or nil)
    end
end

---------------------------------------------------------------------------
-- Slash sub-command registration (under /trinketed)
---------------------------------------------------------------------------
local function RegisterSubCommands()
    local function openLOS(args)
        if args == "" or args == nil then
            lib:ShowOptionsPanel("Line of Sight")
        end
    end
    lib:RegisterSubCommand("los", openLOS)
    lib:RegisterSubCommand("lineofsight", openLOS)

    lib:RegisterSubCommand("loslock", function()
        addon:ToggleLock()
    end)
    lib:RegisterSubCommand("lostest", function()
        ns.Display:ShowAlert(UnitName("player"), "Regrowth")
    end)
end

---------------------------------------------------------------------------
-- Lock / unlock (drag the alert to reposition)
---------------------------------------------------------------------------
function addon:ToggleLock()
    self.db.locked = not self.db.locked
    ns.Display:SetLocked(self.db.locked)
    self:Print("Line of Sight alert " .. (self.db.locked and "|cff4ADE80locked|r" or "|cffE63939unlocked|r (drag to move)"))
end

---------------------------------------------------------------------------
-- Event frame
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "TrinketedLOSEventFrame", UIParent)
addon.eventFrame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end

        TrinketedLOSDB = TrinketedLOSDB or {}
        addon:MergeDefaults(TrinketedLOSDB, DEFAULTS)
        addon.db = TrinketedLOSDB

        ns.Display:Init()
        addon:InitOptions()
        RegisterSubCommands()

        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end

        addon:Print(addon.VERSION .. " loaded")

        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self:RegisterEvent("UI_ERROR_MESSAGE")
        self:RegisterEvent("CHAT_MSG_ADDON")
        return
    end

    if event == "UNIT_SPELLCAST_SENT" then
        local unit, targetName, castGUID, spellID = ...
        lastCast.name = targetName
        lastCast.spell = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or GetSpellInfo(spellID)
        lastCast.t = GetTime()
        if castGUID then
            if castTargetsN > 40 then wipe(castTargets); castTargetsN = 0 end
            if castTargets[castGUID] == nil then castTargetsN = castTargetsN + 1 end
            castTargets[castGUID] = targetName
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID = ...
        OnCastSucceeded(castGUID)

    elseif event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        if message == SPELL_FAILED_LINE_OF_SIGHT then
            OnLineOfSightError()
        end

    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    end
end)
