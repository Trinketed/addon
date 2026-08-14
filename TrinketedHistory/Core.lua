---------------------------------------------------------------------------
-- TrinketedHistory: Core.lua
-- Arena match history tracking, VOD timestamp overlay
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local ARENA_ZONES = {
    ["Nagrand Arena"] = true,
    ["Blade's Edge Arena"] = true,
    ["Ruins of Lordaeron"] = true,
}

-- Short codes used in the match tables and filters for compactness.
local MAP_ABBR = {
    ["Nagrand Arena"]      = "NAG",
    ["Blade's Edge Arena"] = "BEA",
    ["Ruins of Lordaeron"] = "ROL",
}
local function AbbrevMap(name)
    if not name then return "—" end
    return MAP_ABBR[name] or name
end

local ADDON_NAME = "TrinketedHistory"
local DISPLAY_NAME = "Trinketed"
local currentSeason = (GetCurrentArenaSeason and GetCurrentArenaSeason()) or 1
if currentSeason == 0 then currentSeason = 1 end

-- GetCurrentArenaSeason() usually returns 0 at load (the server sends season
-- data later), so currentSeason above is often a stale fallback of 1. Tabs
-- whose season filter defaults to "current season" register a re-apply
-- callback here; Apply() re-queries and pushes the real value into every one
-- of them when the panel opens. A registry rather than direct assignment
-- because each tab's dropdown lives in its own do-block scope and can't be
-- reached from the panel's OnShow handler. One table-valued local (Core.lua
-- is near Lua's 200-locals-per-chunk limit).
local seasonDefault = { hooks = {} }

function seasonDefault:Register(fn)
    self.hooks[#self.hooks + 1] = fn
end

function seasonDefault:Apply()
    local fresh = GetCurrentArenaSeason and GetCurrentArenaSeason() or 0
    if fresh > 0 then currentSeason = fresh end
    for _, fn in ipairs(self.hooks) do fn(currentSeason) end
    return currentSeason
end
local BRANDED_TITLE = "|cffE8B923T|r|cffF4F4F5RINKETED|r History"
local PREP_BUFF = "Arena Preparation"
local ROW_HEIGHT = 34
local CLASS_COLORS = {
    ["Warrior"]     = "ffc79c6e",
    ["Paladin"]     = "fff58cba",
    ["Hunter"]      = "ffabd473",
    ["Rogue"]       = "fffff569",
    ["Priest"]      = "ffffffff",
    ["Shaman"]      = "ff0070de",
    ["Mage"]        = "ff69ccf0",
    ["Warlock"]     = "ff9482c9",
    ["Druid"]       = "ffff7d0a",
}

-- Abbreviated spec names (used in comp keys and row display)
local SPEC_SHORT = {
    -- Warrior
    ["Arms"]            = "Arms",
    ["Fury"]            = "Fury",
    ["Protection"]      = "Prot",
    -- Paladin
    ["Holy"]            = "Holy",
    ["Retribution"]     = "Ret",
    -- Rogue
    ["Assassination"]   = "Assa",
    ["Combat"]          = "Combat",
    ["Subtlety"]        = "Sub",
    -- Priest
    ["Discipline"]      = "Disc",
    ["Shadow"]          = "Shadow",
    -- Mage
    ["Frost"]           = "Frost",
    ["Arcane"]          = "Arc",
    ["Fire"]            = "Fire",
    -- Warlock
    ["Affliction"]      = "Aff",
    ["Demonology"]      = "Demo",
    ["Destruction"]     = "Destro",
    -- Shaman
    ["Elemental"]       = "Ele",
    ["Enhancement"]     = "Enh",
    ["Restoration"]     = "Resto",
    -- Hunter
    ["Beast Mastery"]   = "BM",
    ["Marksmanship"]    = "MM",
    ["Survival"]        = "Surv",
    -- Druid
    ["Balance"]         = "Bal",
    ["Feral"]           = "Feral",
}

-- Spell name → { class, spec } mapping for spec detection (TBC 2.4.3 talent spells)
--
-- Entries must be cast (AssignSpec fires off SPELL_CAST_SUCCESS and
-- UNIT_SPELLCAST_SUCCEEDED, so passive talents never trigger) and must sit deep
-- enough in their tree that an off-spec build can't reach them. Shallow talents
-- are deliberately omitted even though they'd raise the hit rate: an Arms
-- warrior carries 28 points of Fury, so Death Wish would tag half of them as
-- Fury. Anything reachable with a 20-point off-tree dip stays out.
local SPEC_SPELLS = {
    -- WARRIOR
    ["Mortal Strike"]       = { class = "Warrior",     spec = "Arms" },
    ["Sweeping Strikes"]    = { class = "Warrior",     spec = "Arms" },
    ["Bloodthirst"]         = { class = "Warrior",     spec = "Fury" },
    ["Rampage"]             = { class = "Warrior",     spec = "Fury" },
    ["Concussion Blow"]     = { class = "Warrior",     spec = "Protection" },
    ["Devastate"]           = { class = "Warrior",     spec = "Protection" },
    ["Shield Slam"]         = { class = "Warrior",     spec = "Protection" },
    -- PALADIN
    ["Avenger's Shield"]    = { class = "Paladin",     spec = "Protection" },
    ["Holy Shock"]          = { class = "Paladin",     spec = "Holy" },
    ["Divine Illumination"] = { class = "Paladin",     spec = "Holy" },
    ["Crusader Strike"]     = { class = "Paladin",     spec = "Retribution" },
    ["Repentance"]          = { class = "Paladin",     spec = "Retribution" },
    -- ROGUE
    ["Mutilate"]            = { class = "Rogue",       spec = "Assassination" },
    ["Cold Blood"]          = { class = "Rogue",       spec = "Assassination" },
    ["Envenom"]             = { class = "Rogue",       spec = "Assassination" },
    ["Blade Flurry"]        = { class = "Rogue",       spec = "Combat" },
    ["Adrenaline Rush"]     = { class = "Rogue",       spec = "Combat" },
    ["Shadowstep"]          = { class = "Rogue",       spec = "Subtlety" },
    ["Hemorrhage"]          = { class = "Rogue",       spec = "Subtlety" },
    ["Preparation"]         = { class = "Rogue",       spec = "Subtlety" },
    -- PRIEST
    ["Power Infusion"]      = { class = "Priest",      spec = "Discipline" },
    ["Pain Suppression"]    = { class = "Priest",      spec = "Discipline" },
    ["Circle of Healing"]   = { class = "Priest",      spec = "Holy" },
    ["Lightwell"]           = { class = "Priest",      spec = "Holy" },
    ["Silence"]             = { class = "Priest",      spec = "Shadow" },
    ["Vampiric Touch"]      = { class = "Priest",      spec = "Shadow" },
    ["Shadowform"]          = { class = "Priest",      spec = "Shadow" },
    -- MAGE
    ["Dragon's Breath"]     = { class = "Mage",        spec = "Fire" },
    ["Blast Wave"]          = { class = "Mage",        spec = "Fire" },
    ["Combustion"]          = { class = "Mage",        spec = "Fire" },
    ["Ice Barrier"]         = { class = "Mage",        spec = "Frost" },
    ["Cold Snap"]           = { class = "Mage",        spec = "Frost" },
    ["Icy Veins"]           = { class = "Mage",        spec = "Frost" },
    ["Summon Water Elemental"] = { class = "Mage",     spec = "Frost" },
    ["Presence of Mind"]    = { class = "Mage",        spec = "Arcane" },
    ["Arcane Power"]        = { class = "Mage",        spec = "Arcane" },
    ["Slow"]                = { class = "Mage",        spec = "Arcane" },
    -- WARLOCK
    ["Unstable Affliction"] = { class = "Warlock",     spec = "Affliction" },
    ["Siphon Life"]         = { class = "Warlock",     spec = "Affliction" },
    ["Dark Pact"]           = { class = "Warlock",     spec = "Affliction" },
    ["Soul Link"]           = { class = "Warlock",     spec = "Demonology" },
    ["Demonic Sacrifice"]   = { class = "Warlock",     spec = "Demonology" },
    ["Summon Felguard"]     = { class = "Warlock",     spec = "Demonology" },
    ["Shadowfury"]          = { class = "Warlock",     spec = "Destruction" },
    ["Conflagrate"]         = { class = "Warlock",     spec = "Destruction" },
    -- SHAMAN
    ["Elemental Mastery"]   = { class = "Shaman",      spec = "Elemental" },
    ["Totem of Wrath"]      = { class = "Shaman",      spec = "Elemental" },
    ["Shamanistic Rage"]    = { class = "Shaman",      spec = "Enhancement" },
    ["Stormstrike"]         = { class = "Shaman",      spec = "Enhancement" },
    ["Earth Shield"]        = { class = "Shaman",      spec = "Restoration" },
    ["Mana Tide Totem"]     = { class = "Shaman",      spec = "Restoration" },
    -- HUNTER
    ["Intimidation"]        = { class = "Hunter",      spec = "Beast Mastery" },
    ["The Beast Within"]    = { class = "Hunter",      spec = "Beast Mastery" },
    ["Bestial Wrath"]       = { class = "Hunter",      spec = "Beast Mastery" },
    ["Silencing Shot"]      = { class = "Hunter",      spec = "Marksmanship" },
    ["Trueshot Aura"]       = { class = "Hunter",      spec = "Marksmanship" },
    ["Wyvern Sting"]        = { class = "Hunter",      spec = "Survival" },
    ["Readiness"]           = { class = "Hunter",      spec = "Survival" },
    -- DRUID
    ["Moonkin Form"]        = { class = "Druid",       spec = "Balance" },
    ["Force of Nature"]     = { class = "Druid",       spec = "Balance" },
    ["Mangle (Cat)"]        = { class = "Druid",       spec = "Feral" },
    ["Mangle (Bear)"]       = { class = "Druid",       spec = "Feral" },
    ["Feral Charge"]        = { class = "Druid",       spec = "Feral" },
    ["Swiftmend"]           = { class = "Druid",       spec = "Restoration" },
    ["Tree of Life"]        = { class = "Druid",       spec = "Restoration" },
    -- Note: Nature's Swiftness excluded — shared between Druid Resto and Shaman Resto
}

-- Arena bracket teamSize → GetPersonalRatedInfo() bracketIndex mapping
local BRACKET_TO_RATED_INDEX = { [2] = 1, [3] = 2, [5] = 3 }

---------------------------------------------------------------------------
-- State (ArenaBlackBox-style state machine)
---------------------------------------------------------------------------
local debugMode = false
local state = "IDLE" -- IDLE / IN_ARENA_PREP / RECORDING / SAVING
local currentMatch = nil
local relevantGUIDs = {}  -- GUID → true for all match participants
local guidToRoster = {}   -- GUID → roster entry reference
local drState = {}        -- drState[guid][drCategory] = { count, resetTime }
local pollTicker = nil
local snapshotTicker = nil
local gatesOpenTime = nil -- GetTime() when gates opened (for relative timestamps)
local ratingsBefore = nil
local hadPrepBuff = false
local prevUnitState = {}     -- guid → signature string (delta-encoding)
local prevAuraSnapshot = {}  -- guid → signature string (delta-encoding)
local prevCooldownSig = nil  -- string signature of active cooldowns
local pendingSave = nil      -- set to "WIN"/"LOSS" when match ends, cleared after save
local trinketLastStart = {}  -- GUID → last startTime from ARENA_COOLDOWNS_UPDATE (dedup)
local lastTargets = {}       -- unit → targetGUID cache for change detection
local UpdateOverlayVisibility  -- forward declaration

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local function dbg(...)
    if not debugMode then return end
    print("|cffff9900" .. DISPLAY_NAME .. " [DEBUG]:|r", ...)
end

-- Persistent developer mode (toggled with /trinketed dev). Unlike debugMode
-- (chat logging, resets on reload), this survives reloads and gates
-- developer-facing UI features — e.g. the replay feed's raw-event tooltip.
-- Other files check it via addon:IsDevMode().
function addon:IsDevMode()
    return TrinketedHistoryDB and TrinketedHistoryDB.settings
        and TrinketedHistoryDB.settings.devMode or false
end

-- Dev mode: copyable-text popup. WoW has no clipboard API, so the text is
-- surfaced pre-selected in an EditBox for Ctrl+C. Reusable from any module
-- feature (game ids today; whatever needs copying next). Frame built once,
-- cached on the addon table.
function addon:ShowDevCopyBox(label, text)
    local f = self.devCopyFrame
    if not f then
        f = CreateFrame("Frame", "TrinketedDevCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(360, 72)
        f:SetPoint("CENTER")
        -- Above the options panel (DIALOG strata) so it can't open underneath.
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        f:SetBackdropColor(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)
        f:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
        tinsert(UISpecialFrames, "TrinketedDevCopyFrame")

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(lib.FONT_DISPLAY, 10, "")
        f.title:SetPoint("TOPLEFT", 10, -8)
        f.title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

        f.hint = f:CreateFontString(nil, "OVERLAY")
        f.hint:SetFont(lib.FONT_BODY, 9, "")
        f.hint:SetPoint("TOPRIGHT", -10, -8)
        f.hint:SetText("Ctrl+C to copy — Esc to close")
        f.hint:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        f.box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        f.box:SetPoint("TOPLEFT", 10, -26)
        f.box:SetPoint("BOTTOMRIGHT", -10, 12)
        f.box:SetFont(lib.FONT_MONO, 10, "")
        f.box:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
        f.box:SetAutoFocus(false)
        f.box:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        f.box:SetBackdropColor(0, 0, 0, 0.5)
        f.box:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
        f.box:SetTextInsets(6, 6, 0, 0)
        f.box:SetScript("OnEscapePressed", function() f:Hide() end)
        f.box:SetScript("OnEnterPressed", function() f:Hide() end)
        -- Read-only in effect: any user edit snaps back to the stored text
        -- so Ctrl+C always grabs the real value.
        f.box:SetScript("OnTextChanged", function(box, isUserInput)
            if isUserInput and box:GetText() ~= f.text then
                box:SetText(f.text or "")
                box:HighlightText()
            end
        end)
        -- Re-select whenever focus lands in the box (including clicking into
        -- it), so a plain Ctrl+C always copies the whole value.
        f.box:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)

        self.devCopyFrame = f
    end
    f.text = text or ""
    f.title:SetText(label or "Copy")
    f.box:SetText(f.text)
    f:Show()
    -- Defer focus by one frame: grabbing focus inside the same click that
    -- opened the box can drop the selection highlight.
    C_Timer.After(0, function()
        if f:IsShown() then
            f.box:SetFocus()
            f.box:HighlightText()
        end
    end)
end

---------------------------------------------------------------------------
-- Timestamp Sync
---------------------------------------------------------------------------
-- Sync GetTime() (session-relative, fractional) with time() (epoch, integer)
-- so the barcode can display epoch timestamps with millisecond precision
local tsBaseEpoch = time()
local tsBaseGetTime = GetTime()

---------------------------------------------------------------------------
-- Barcode Timestamp (low-profile binary encoding for OCR/scraping)
---------------------------------------------------------------------------
-- 50 cells, MSB first:
--   cells  1.. 4 : sync prefix 1 0 1 0
--   cells  5..36 : 32-bit epoch seconds
--   cells 37..46 : 10-bit millisecond (0..999)
--   cells 47..50 : sync suffix 0 1 0 1
-- Pure black (0) / white (1) for max luma contrast — survives 4:2:0 chroma
-- subsampling and h.264 bitrate compression at 720p far better than glyphs.
-- Magenta + cyan anchor markers flank the strip so the same locator logic
-- as the text overlay can find it.
--
-- Wrapped in a `do ... end` block so internal locals stay block-scoped.
-- The only chunk-level local exposed is `barcode` (forward-declared above).
local barcode
do
    local BITS = 50
    local CELL_W = 5            -- physical px per bit at 1.0 effective scale
    local CELL_H = 6
    local MARKER_W = 4

    barcode = CreateFrame("Frame", "TrinketedBarcodeFrame", UIParent)
    barcode:SetFrameStrata("HIGH")
    barcode:Hide()

    local leftMarker = barcode:CreateTexture(nil, "ARTWORK")
    leftMarker:SetColorTexture(1, 0, 1, 1)   -- magenta
    leftMarker:SetPoint("RIGHT", barcode, "LEFT", 0, 0)

    local rightMarker = barcode:CreateTexture(nil, "ARTWORK")
    rightMarker:SetColorTexture(0, 1, 1, 1)  -- cyan
    rightMarker:SetPoint("LEFT", barcode, "RIGHT", 0, 0)

    local cells = {}
    for i = 1, BITS do
        local cell = barcode:CreateTexture(nil, "ARTWORK")
        cell:SetColorTexture(0, 0, 0, 1)
        cells[i] = cell
    end

    local function UpdateScale()
        local effectiveScale = UIParent:GetEffectiveScale()
        if effectiveScale <= 0 then effectiveScale = 1 end
        local inv = 1 / effectiveScale
        local cw = CELL_W * inv
        local h = CELL_H * inv
        barcode:SetSize(cw * BITS, h)
        barcode:ClearAllPoints()
        barcode:SetPoint("TOP", UIParent, "TOP", 0, 0)
        leftMarker:SetSize(MARKER_W * inv, h)
        rightMarker:SetSize(MARKER_W * inv, h)
        for i = 1, BITS do
            cells[i]:ClearAllPoints()
            cells[i]:SetSize(cw, h)
            cells[i]:SetPoint("LEFT", barcode, "LEFT", (i - 1) * cw, 0)
        end
    end
    UpdateScale()

    barcode:RegisterEvent("UI_SCALE_CHANGED")
    barcode:SetScript("OnEvent", function() UpdateScale() end)

    -- Track last-written bits so we skip redundant SetColorTexture calls
    local prev = {}
    for i = 1, BITS do prev[i] = -1 end

    -- Sync prefix (cells 1..4 = 1010) and suffix (cells 47..50 = 0101) are constant
    local fixed = { [1]=1, [2]=0, [3]=1, [4]=0,
                    [47]=0, [48]=1, [49]=0, [50]=1 }
    for idx, b in pairs(fixed) do
        cells[idx]:SetColorTexture(b, b, b, 1)
        prev[idx] = b
    end

    barcode:SetScript("OnUpdate", function()
        local now = tsBaseEpoch + (GetTime() - tsBaseGetTime)
        local secs = math.floor(now)
        local ms = math.floor((now - secs) * 1000)
        -- 32 bits of epoch seconds, MSB first → cells 5..36
        for i = 0, 31 do
            local b = math.floor(secs / 2^(31 - i)) % 2
            local idx = 5 + i
            if prev[idx] ~= b then
                cells[idx]:SetColorTexture(b, b, b, 1)
                prev[idx] = b
            end
        end
        -- 10 bits of milliseconds, MSB first → cells 37..46
        for i = 0, 9 do
            local b = math.floor(ms / 2^(9 - i)) % 2
            local idx = 37 + i
            if prev[idx] ~= b then
                cells[idx]:SetColorTexture(b, b, b, 1)
                prev[idx] = b
            end
        end
    end)
end

-- Separate always-running frame to periodically check visibility
-- (overlay's OnUpdate only fires when shown, so we need an independent ticker)
local visTicker = CreateFrame("Frame")
local visCheckElapsed = 0
visTicker:SetScript("OnUpdate", function(self, dt)
    visCheckElapsed = visCheckElapsed + dt
    if visCheckElapsed >= 2 then
        visCheckElapsed = 0
        UpdateOverlayVisibility()
    end
end)

-- /trinketed tsdebug bypasses the showTimestamp setting and normal
-- queue/recording gating to force-show the text overlay + full barcode
-- for offline OCR/scrape testing.
local tsForceShow = false

-- Check queue/prep status and show/hide overlay accordingly.
-- Visible when: in queue, waiting for confirm, or in arena prep room.
-- Hidden when: game is active, or not queued at all.
UpdateOverlayVisibility = function()
    if tsForceShow then
        barcode:Show()
        return
    end
    -- Hide if user disabled the overlay
    if not TrinketedHistoryDB.settings or not TrinketedHistoryDB.settings.showTimestamp then
        barcode:Hide()
        return
    end
    -- Always hide during active game
    if state == "RECORDING" then
        barcode:Hide()
        return
    end
    -- Show in arena prep room
    if state == "IN_ARENA_PREP" and hadPrepBuff then
        barcode:Show()
        return
    end
    -- Show if queued or confirming
    for i = 1, GetMaxBattlefieldID() do
        local status = GetBattlefieldStatus(i)
        if status == "queued" or status == "confirm" then
            barcode:Show()
            return
        end
    end
    barcode:Hide()
end

---------------------------------------------------------------------------
-- Queue pop timing — print how long the arena queue took to pop
---------------------------------------------------------------------------
local queueTracker = {}  -- battlefield index → { start, mapName, teamSize, popped }

local function FormatQueueTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    if m > 0 then
        return string.format("%dm %02ds", m, s)
    end
    return string.format("%ds", s)
end

local function TrackQueueStatus()
    for i = 1, GetMaxBattlefieldID() do
        local status, mapName, teamSize = GetBattlefieldStatus(i)
        local entry = queueTracker[i]
        if status == "queued" then
            -- New queue in this slot (or a different queue shifted into it)
            if not entry or entry.mapName ~= mapName then
                queueTracker[i] = { start = GetTime(), mapName = mapName, teamSize = teamSize }
            end
        elseif status == "confirm" then
            if not entry then
                -- Reloaded/logged in mid-queue: no local start stamp, but the
                -- server-side wait time below still covers us
                entry = { mapName = mapName, teamSize = teamSize }
                queueTracker[i] = entry
            end
            if not entry.popped then
                entry.popped = true
                -- Prefer the server-tracked wait (survives /reload); fall back
                -- to our own stamp from when we saw the slot enter "queued"
                local waited
                if GetBattlefieldTimeWaited then
                    local ms = GetBattlefieldTimeWaited(i)
                    if type(ms) == "number" and ms > 0 then
                        waited = ms / 1000
                    end
                end
                if not waited and entry.start then
                    waited = GetTime() - entry.start
                end
                local label = mapName or "Arena"
                if type(entry.teamSize) == "number" and entry.teamSize >= 2 and entry.teamSize <= 10 then
                    label = entry.teamSize .. "v" .. entry.teamSize
                end
                if waited then
                    print("|cff00ccff" .. DISPLAY_NAME .. ":|r " .. label ..
                        " queue popped after " .. FormatQueueTime(waited))
                else
                    print("|cff00ccff" .. DISPLAY_NAME .. ":|r " .. label .. " queue popped")
                end
            end
        else
            -- "none"/"active"/etc. — slot is no longer queued or confirming
            queueTracker[i] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function FormatClassName(class)
    if not class or type(class) ~= "string" then return nil end
    return class:sub(1, 1):upper() .. class:sub(2):lower()
end

local function HasPrepBuff()
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == PREP_BUFF then return true end
    end
    return false
end

local function StripRealm(name)
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

local function GetEpochTime()
    return tsBaseEpoch + (GetTime() - tsBaseGetTime)
end

local function GetRelativeTime()
    if not gatesOpenTime then return 0 end
    return GetTime() - gatesOpenTime
end

-- Random per-game id so external tools (the desktop companion app) can
-- identify a record without decoding its eventLog. Uniqueness, not
-- cryptography.
local function GenerateGameId()
    return string.format("%08x-%04x-%04x-%04x",
        time(), math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

local function IsRelevantGUID(guid)
    return guid and relevantGUIDs[guid]
end

-- Snapshot all bracket ratings: returns { [1]=rating, [2]=rating, [3]=rating }
local function SnapshotAllRatings()
    if not GetPersonalRatedInfo then return nil end
    local ratings = {}
    for i = 1, 3 do
        local rating = GetPersonalRatedInfo(i)
        ratings[i] = rating or 0
    end
    dbg("SnapshotAllRatings:", ratings[1], ratings[2], ratings[3])
    return ratings
end

local function AppendEvent(event)
    if not currentMatch or not currentMatch.events then return end
    currentMatch.events[#currentMatch.events + 1] = event
end

local CompressEventLog  -- forward declaration

---------------------------------------------------------------------------
-- SpellDB + DRList Enrichment
---------------------------------------------------------------------------
local DRList = LibStub("DRList-1.0", true)

local function EnrichEvent(event)
    local spellID = event.spellID
    if not spellID then return end

    if DRList then
        local drCat = DRList:GetCategoryBySpellID(spellID)
        if drCat then
            event.ccType = drCat
            event.dr = drCat
        end
    end

    -- Rank-proof lookup (addon.ResolveSpell, ReplayEngine.lua): off-rank
    -- casts resolve by name, disambiguated by the caster's class when two
    -- classes share a spell name.
    local srcEntry = event.srcGUID and guidToRoster[event.srcGUID]
    local dbEntry = select(2, addon.ResolveSpell(spellID, event.spell,
        srcEntry and srcEntry.class))
    if dbEntry then
        event.cat = dbEntry.cat
        if dbEntry.dur then event.dur = dbEntry.dur end
    end
end

---------------------------------------------------------------------------
-- DR Tracking
---------------------------------------------------------------------------
local function UpdateDRState(dstGUID, drCat, event)
    if not drState[dstGUID] then drState[dstGUID] = {} end
    local dr = drState[dstGUID][drCat]

    if not dr or GetTime() > dr.resetTime then
        drState[dstGUID][drCat] = {
            count = 1,
            resetTime = GetTime() + (DRList and DRList.GetResetTime and DRList:GetResetTime(drCat) or 18)
        }
        event.drCount = 1
        event.drMultiplier = 1.0
    else
        dr.count = dr.count + 1
        event.drCount = dr.count
        event.drMultiplier = (DRList and DRList.GetNextDR) and DRList:GetNextDR(dr.count, drCat) or
            ({ [2] = 0.5, [3] = 0.25 })[dr.count] or 0
        dr.resetTime = GetTime() + (DRList and DRList.GetResetTime and DRList:GetResetTime(drCat) or 18)
    end
end

---------------------------------------------------------------------------
-- Roster Management
---------------------------------------------------------------------------
local function AddToRoster(guid, name, class, race, team, unit)
    if not currentMatch or not guid then return end
    if currentMatch.roster[guid] then return end -- already known

    local specName = nil
    -- Try GetArenaOpponentSpec for arena units
    if unit and unit:match("^arena") then
        local arenaIndex = tonumber(unit:match("(%d+)"))
        if arenaIndex and GetArenaOpponentSpec and GetSpecializationInfoByID then
            local specID = GetArenaOpponentSpec(arenaIndex)
            if specID and specID > 0 then
                local _, sn = GetSpecializationInfoByID(specID)
                specName = sn
            end
        end
    end

    -- Realm-qualified name: CLEU names arrive as "Name-Realm" for
    -- cross-realm players already; unit-based names need the realm appended
    -- (UnitName's second return cross-realm, own realm otherwise). Stripped
    -- names collide across realms, so external tools need this to identify
    -- players without decoding GUIDs out of the eventLog.
    local fullName = name
    if fullName and not fullName:find("-", 1, true) then
        local realm
        if unit then
            local _, unitRealm = UnitName(unit)
            realm = unitRealm
        end
        if not realm or realm == "" then
            realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
        end
        if realm and realm ~= "" then
            fullName = fullName .. "-" .. realm
        end
    end

    local entry = {
        name = StripRealm(name),
        fullName = fullName,
        class = FormatClassName(class),
        race = race,
        spec = specName,
        team = team,
    }

    currentMatch.roster[guid] = entry
    relevantGUIDs[guid] = true
    guidToRoster[guid] = entry

    dbg("Roster add:", entry.name, entry.class, entry.spec or "?", team)

    -- Emit player_entered event
    AppendEvent({
        t = GetRelativeTime(),
        type = "player_entered",
        guid = guid,
        name = entry.name,
        class = entry.class,
        race = entry.race,
        team = team,
    })
end

local function SnapshotRoster()
    if not currentMatch then return end

    -- Player
    local playerGUID = UnitGUID("player")
    local playerName = UnitName("player")
    local _, playerClass = UnitClass("player")
    local playerRace = UnitRace("player")
    AddToRoster(playerGUID, playerName, playerClass, playerRace, "friendly", "player")

    -- Party
    for i = 1, 4 do
        local unit = "party" .. i
        local guid = UnitGUID(unit)
        local name = UnitName(unit)
        local _, className = UnitClass(unit)
        local race = UnitRace(unit)
        if guid and name then
            AddToRoster(guid, name, className, race, "friendly", unit)
        end
    end

    -- Arena opponents
    for i = 1, 5 do
        local unit = "arena" .. i
        local guid = UnitGUID(unit)
        local name = UnitName(unit)
        local _, className = UnitClass(unit)
        local race = UnitRace(unit)
        if guid and name then
            AddToRoster(guid, name, className, race, "enemy", unit)
        end
    end
end

local function DiscoverPlayerByGUID(guid)
    if not guid or not currentMatch then return end
    if relevantGUIDs[guid] then return end

    -- Check arena units
    for i = 1, 5 do
        local unit = "arena" .. i
        if UnitGUID(unit) == guid then
            local name = UnitName(unit)
            local _, className = UnitClass(unit)
            local race = UnitRace(unit)
            if name and className then
                AddToRoster(guid, name, className, race, "enemy", unit)
            end
            return
        end
    end

    -- Check player
    if guid == UnitGUID("player") then
        local name = UnitName("player")
        local _, className = UnitClass("player")
        local race = UnitRace("player")
        AddToRoster(guid, name, className, race, "friendly", "player")
        return
    end

    -- Check party
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitGUID(unit) == guid then
            local name = UnitName(unit)
            local _, className = UnitClass(unit)
            local race = UnitRace(unit)
            if name and className then
                AddToRoster(guid, name, className, race, "friendly", unit)
            end
            return
        end
    end
end

local function AssignSpec(guid, spellName)
    local specInfo = SPEC_SPELLS[spellName]
    if not specInfo or not currentMatch then return end

    local entry = guidToRoster[guid]
    if not entry then return end
    if entry.class and entry.class ~= specInfo.class then return end
    if entry.spec then return end

    entry.spec = specInfo.spec
    dbg("Spec detected:", entry.name, "=", specInfo.spec, "(from", spellName .. ")")
    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Spec detected: " ..
        "|c" .. (CLASS_COLORS[entry.class] or "ffffffff") .. entry.name .. "|r" ..
        " = " .. specInfo.spec)
end

---------------------------------------------------------------------------
-- CLEU Event Building
---------------------------------------------------------------------------
local DAMAGE_SUBEVENTS = {
    SPELL_DAMAGE           = "direct",
    SPELL_PERIODIC_DAMAGE  = "periodic",
    SWING_DAMAGE           = "auto_melee",
    RANGE_DAMAGE           = "auto_ranged",
    DAMAGE_SHIELD          = "shield",
    DAMAGE_SPLIT           = "split",
    ENVIRONMENTAL_DAMAGE   = "env",
}

local HEAL_SUBEVENTS = {
    SPELL_HEAL             = "direct",
    SPELL_PERIODIC_HEAL    = "periodic",
}

local MISS_SUBEVENTS = {
    SPELL_MISSED           = true,
    SWING_MISSED           = true,
    RANGE_MISSED           = true,
    SPELL_PERIODIC_MISSED  = true,
    DAMAGE_SHIELD_MISSED   = true,
}

local function BuildDamageEvent(subevent, info, t)
    local subtype = DAMAGE_SUBEVENTS[subevent]
    local srcGUID, srcName = info[4], info[5]
    local dstGUID, dstName = info[8], info[9]

    if subevent == "SWING_DAMAGE" then
        local amount, overkill, school, _, _, _, _, _, absorbed, critical = info[12], info[13], info[14], info[15], info[16], info[17], info[18], info[19], info[20], info[21]
        return {
            t = t, type = "damage", subtype = subtype,
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            school = school, amount = amount, overkill = overkill,
            absorbed = absorbed, critical = critical,
        }
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        local envType = info[12]
        local amount, overkill, school = info[13], info[14], info[15]
        return {
            t = t, type = "damage", subtype = subtype,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            envType = envType, school = school, amount = amount, overkill = overkill,
        }
    else
        local spellID, spellName, spellSchool = info[12], info[13], info[14]
        local amount, overkill, school, _, _, _, absorbed, critical = info[15], info[16], info[17], info[18], info[19], info[20], info[21], info[22]
        return {
            t = t, type = "damage", subtype = subtype,
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName, school = spellSchool or school,
            amount = amount, overkill = overkill, absorbed = absorbed, critical = critical,
        }
    end
end

local function BuildHealEvent(subevent, info, t)
    local subtype = HEAL_SUBEVENTS[subevent]
    local srcGUID, srcName = info[4], info[5]
    local dstGUID, dstName = info[8], info[9]
    local spellID, spellName = info[12], info[13]
    local amount, overhealing, absorbed, critical = info[15], info[16], info[17], info[18]

    return {
        t = t, type = "heal", subtype = subtype,
        src = StripRealm(srcName), srcGUID = srcGUID,
        dst = StripRealm(dstName), dstGUID = dstGUID,
        spellID = spellID, spell = spellName,
        amount = amount, overhealing = overhealing, absorbed = absorbed, critical = critical,
    }
end

local function BuildMissEvent(subevent, info, t)
    local srcGUID, srcName = info[4], info[5]
    local dstGUID, dstName = info[8], info[9]

    if subevent == "SWING_MISSED" then
        local missType, _, amountMissed = info[12], info[13], info[14]
        return {
            t = t, type = "miss", subtype = "swing",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            missType = missType, amountMissed = amountMissed,
        }
    else
        local spellID, spellName = info[12], info[13]
        local missType, _, amountMissed = info[15], info[16], info[17]
        local prefix = subevent:match("^(.+)_MISSED$")
        return {
            t = t, type = "miss", subtype = prefix and prefix:lower() or "spell",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
            missType = missType, amountMissed = amountMissed,
        }
    end
end

local function OnCLEU()
    local info = { CombatLogGetCurrentEventInfo() }
    local timestamp, subevent, hideCaster = info[1], info[2], info[3]
    local srcGUID, srcName, srcFlags, srcRaidFlags = info[4], info[5], info[6], info[7]
    local dstGUID, dstName, dstFlags, dstRaidFlags = info[8], info[9], info[10], info[11]

    if state ~= "RECORDING" then return end

    -- Try to discover unknown GUIDs
    if srcGUID and not relevantGUIDs[srcGUID] then DiscoverPlayerByGUID(srcGUID) end
    if dstGUID and dstGUID ~= srcGUID and not relevantGUIDs[dstGUID] then DiscoverPlayerByGUID(dstGUID) end

    -- Filter: only record events involving match participants
    if not IsRelevantGUID(srcGUID) and not IsRelevantGUID(dstGUID) then return end

    local t = GetRelativeTime()
    local event = nil

    -- Spec detection
    if srcGUID and relevantGUIDs[srcGUID] then
        local spellName = info[13]
        if spellName and SPEC_SPELLS[spellName] then
            AssignSpec(srcGUID, spellName)
        end
    end

    -- Build event based on subevent type
    if DAMAGE_SUBEVENTS[subevent] then
        event = BuildDamageEvent(subevent, info, t)

    elseif HEAL_SUBEVENTS[subevent] then
        event = BuildHealEvent(subevent, info, t)

    elseif MISS_SUBEVENTS[subevent] then
        event = BuildMissEvent(subevent, info, t)

    elseif subevent == "SPELL_AURA_APPLIED" then
        local spellID, spellName, _, auraType = info[12], info[13], info[14], info[15]
        event = {
            t = t, type = "aura_applied",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName, auraType = auraType,
        }

    elseif subevent == "SPELL_AURA_REMOVED" then
        local spellID, spellName, _, auraType = info[12], info[13], info[14], info[15]
        event = {
            t = t, type = "aura_removed",
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName, auraType = auraType,
        }

    elseif subevent == "SPELL_AURA_REFRESH" then
        local spellID, spellName = info[12], info[13]
        event = {
            t = t, type = "aura_refresh",
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
        }

    elseif subevent == "SPELL_AURA_APPLIED_DOSE" or subevent == "SPELL_AURA_REMOVED_DOSE" then
        local spellID, spellName, _, auraType, stacks = info[12], info[13], info[14], info[15], info[16]
        event = {
            t = t, type = "aura_dose",
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName, stacks = stacks,
        }

    elseif subevent == "SPELL_AURA_BROKEN_SPELL" then
        local spellID, spellName = info[12], info[13]
        local extraSpellID, extraSpellName = info[15], info[16]
        event = {
            t = t, type = "aura_break",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
            extraSpellID = extraSpellID, extraSpell = extraSpellName,
        }

    elseif subevent == "SPELL_AURA_BROKEN" then
        local spellID, spellName = info[12], info[13]
        event = {
            t = t, type = "aura_break",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
        }

    elseif subevent == "SPELL_CAST_START" then
        local spellID, spellName = info[12], info[13]
        event = {
            t = t, type = "cast_start",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
        }

    elseif subevent == "SPELL_CAST_SUCCESS" then
        local spellID, spellName = info[12], info[13]
        -- Skip trinket/cc_break/racial — handled by UNIT_SPELLCAST_SUCCEEDED / ARENA_COOLDOWNS_UPDATE
        -- Rank-proof: off-rank/per-class variants (e.g. Arcane Torrent) still
        -- resolve so they don't get double-recorded through both paths.
        local srcEntry = info[4] and guidToRoster[info[4]]
        local dbEntry = select(2, addon.ResolveSpell(spellID, spellName,
            srcEntry and srcEntry.class))
        local skipCat = dbEntry and dbEntry.cat
        if skipCat ~= "trinket" and skipCat ~= "cc_break" and skipCat ~= "racial" then
            event = {
                t = t, type = "cast_success",
                src = StripRealm(srcName), srcGUID = srcGUID,
                dst = StripRealm(dstName), dstGUID = dstGUID,
                spellID = spellID, spell = spellName,
            }
        end

    elseif subevent == "SPELL_CAST_FAILED" then
        local spellID, spellName = info[12], info[13]
        local failReason = info[15]
        event = {
            t = t, type = "cast_fail",
            src = StripRealm(srcName), srcGUID = srcGUID,
            spellID = spellID, spell = spellName, failReason = failReason,
        }

    elseif subevent == "SPELL_INTERRUPT" then
        local spellID, spellName = info[12], info[13]
        local extraSpellID, extraSpellName = info[15], info[16]
        event = {
            t = t, type = "interrupt",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
            extraSpellID = extraSpellID, extraSpell = extraSpellName,
        }

    elseif subevent == "SPELL_DISPEL" then
        local spellID, spellName = info[12], info[13]
        local extraSpellID, extraSpellName, _, auraType = info[15], info[16], info[17], info[18]
        event = {
            t = t, type = "dispel",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
            extraSpellID = extraSpellID, extraSpell = extraSpellName, auraType = auraType,
        }

    elseif subevent == "SPELL_STOLEN" then
        local spellID, spellName = info[12], info[13]
        local extraSpellID, extraSpellName = info[15], info[16]
        event = {
            t = t, type = "steal",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
            extraSpellID = extraSpellID, extraSpell = extraSpellName,
        }

    elseif subevent == "SPELL_ABSORBED" then
        local absorbSrcGUID, absorbSrcName, absorbSpellID, absorbSpellName, absorbAmount
        if type(info[12]) == "number" then
            absorbSrcGUID = info[15]
            absorbSrcName = info[16]
            absorbSpellID = info[19]
            absorbSpellName = info[20]
            absorbAmount = info[22]
        else
            absorbSrcGUID = info[12]
            absorbSrcName = info[13]
            absorbSpellID = info[16]
            absorbSpellName = info[17]
            absorbAmount = info[19]
        end
        event = {
            t = t, type = "absorb",
            src = StripRealm(absorbSrcName), srcGUID = absorbSrcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = absorbSpellID, spell = absorbSpellName,
            amount = absorbAmount,
        }

    elseif subevent == "SPELL_ENERGIZE" or subevent == "SPELL_PERIODIC_ENERGIZE" then
        local spellID, spellName = info[12], info[13]
        local amount, _, powerType = info[15], info[16], info[17]
        event = {
            t = t, type = "energize",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
            amount = amount, powerType = powerType,
        }

    elseif subevent == "SPELL_DRAIN" or subevent == "SPELL_LEECH" then
        local spellID, spellName = info[12], info[13]
        local amount, powerType = info[15], info[17]
        event = {
            t = t, type = "drain",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
            amount = amount, powerType = powerType,
        }

    elseif subevent == "SPELL_SUMMON" then
        local spellID, spellName = info[12], info[13]
        event = {
            t = t, type = "summon",
            src = StripRealm(srcName), srcGUID = srcGUID,
            dst = StripRealm(dstName), dstGUID = dstGUID,
            spellID = spellID, spell = spellName,
        }
        -- Track summoned creatures as relevant (pets, totems, etc.)
        if dstGUID then relevantGUIDs[dstGUID] = true end

    elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        event = {
            t = t, type = "death",
            dst = StripRealm(dstName), dstGUID = dstGUID,
        }

    elseif subevent == "SPELL_EXTRA_ATTACKS" then
        local spellID, spellName = info[12], info[13]
        local amount = info[15]
        event = {
            t = t, type = "extra_attacks",
            src = StripRealm(srcName), srcGUID = srcGUID,
            spellID = spellID, spell = spellName, amount = amount,
        }
    end

    -- Enrich and append
    if event then
        EnrichEvent(event)

        -- DR tracking for aura_applied with CC
        if event.type == "aura_applied" and event.dr and dstGUID then
            UpdateDRState(dstGUID, event.dr, event)
        end

        AppendEvent(event)
    end
end

---------------------------------------------------------------------------
-- Polling (200ms)
---------------------------------------------------------------------------
local ALL_UNITS = { "player", "party1", "party2", "party3", "party4",
                    "arena1", "arena2", "arena3", "arena4", "arena5" }

local function PollUnitState(unit, t)
    local guid = UnitGUID(unit)
    if not guid or not IsRelevantGUID(guid) then return end

    local hp = UnitHealth(unit)
    local hpMax = UnitHealthMax(unit)
    local power = UnitPower(unit)
    local powerMax = UnitPowerMax(unit)
    local powerType = UnitPowerType(unit)

    -- TBC Anniversary: enemy arena units return percentage HP (0-100) not actual values
    local hpIsPercent = (hpMax == 100 and unit:match("^arena"))

    local targetName = UnitName(unit .. "target")
    local targetGUID = UnitGUID(unit .. "target")

    -- Casting info
    local castName, _, _, castStart, castEnd, _, _, _, castSpellID
    if UnitCastingInfo then
        castName, _, _, castStart, castEnd, _, _, _, castSpellID = UnitCastingInfo(unit)
    end

    local chanName, _, _, chanStart, chanEnd, _, _, chanSpellID
    if UnitChannelInfo then
        chanName, _, _, chanStart, chanEnd, _, _, chanSpellID = UnitChannelInfo(unit)
    end

    -- Delta-encode: skip if nothing meaningful changed
    local sig = hp .. "|" .. hpMax .. "|" .. power .. "|" .. powerMax .. "|" .. powerType
        .. "|" .. (targetGUID or "") .. "|" .. (castName or "") .. "|" .. (chanName or "")
    if prevUnitState[guid] == sig then return end
    prevUnitState[guid] = sig

    AppendEvent({
        t = t, type = "unit_state",
        guid = guid,
        hp = hp, hpMax = hpMax, hpPct = hpIsPercent or nil,
        power = power, powerMax = powerMax, powerType = powerType,
        target = StripRealm(targetName), targetGUID = targetGUID,
        casting = castName, castSpellID = castSpellID,
        castEnd = castEnd and (castEnd / 1000) or nil,
        channeling = chanName, channelSpellID = chanSpellID,
        channelEnd = chanEnd and (chanEnd / 1000) or nil,
    })
end

local function PollUnitAuras(unit, t)
    local guid = UnitGUID(unit)
    if not guid or not IsRelevantGUID(guid) then return end

    local auras = {}

    -- Buffs (HELPFUL)
    for i = 1, 40 do
        local name, _, stacks, auraType, duration, expires, source, _, _, spellID = UnitAura(unit, i, "HELPFUL")
        if not name then break end
        local entry = {
            spellID = spellID, spell = name, auraType = "BUFF",
            stacks = (stacks and stacks > 0) and stacks or nil,
            duration = duration, expires = expires,
        }
        if DRList then
            local drCat = DRList:GetCategoryBySpellID(spellID)
            if drCat then entry.ccType = drCat; entry.dr = drCat end
        end
        local db = select(2, addon.ResolveSpell(spellID, name))
        if db then entry.cat = db.cat end
        auras[#auras + 1] = entry
    end

    -- Debuffs (HARMFUL)
    for i = 1, 40 do
        local name, _, stacks, auraType, duration, expires, source, _, _, spellID = UnitAura(unit, i, "HARMFUL")
        if not name then break end
        local entry = {
            spellID = spellID, spell = name, auraType = "DEBUFF",
            stacks = (stacks and stacks > 0) and stacks or nil,
            duration = duration, expires = expires,
        }
        if DRList then
            local drCat = DRList:GetCategoryBySpellID(spellID)
            if drCat then entry.ccType = drCat; entry.dr = drCat end
        end
        local db = select(2, addon.ResolveSpell(spellID, name))
        if db then entry.cat = db.cat end
        auras[#auras + 1] = entry
    end

    if #auras > 0 then
        -- Delta-encode: build signature from spellID:stacks:auraType
        local sigParts = {}
        for _, a in ipairs(auras) do
            sigParts[#sigParts + 1] = a.spellID .. ":" .. (a.stacks or 1) .. ":" .. a.auraType
        end
        table.sort(sigParts)
        local sig = table.concat(sigParts, ",")

        if prevAuraSnapshot[guid] == sig then return end
        prevAuraSnapshot[guid] = sig

        AppendEvent({ t = t, type = "aura_snapshot", guid = guid, auras = auras })
    else
        if prevAuraSnapshot[guid] then
            prevAuraSnapshot[guid] = nil
            AppendEvent({ t = t, type = "aura_snapshot", guid = guid, auras = {} })
        end
    end
end

local function PollPlayerCooldowns(t)
    if not TRACKED_COOLDOWN_SPELLS then return end

    local cooldowns = {}
    for _, spellID in ipairs(TRACKED_COOLDOWN_SPELLS) do
        local start, duration, enabled = GetSpellCooldown(spellID)
        if start and start > 0 and duration > 1.5 then
            local remaining = (start + duration) - GetTime()
            if remaining > 0 then
                local spellName = GetSpellInfo(spellID)
                local db = SPELL_DB and SPELL_DB[spellID]
                cooldowns[#cooldowns + 1] = {
                    spellID = spellID,
                    spell = spellName,
                    start = start,
                    duration = duration,
                    cat = db and db.cat or nil,
                }
            end
        end
    end

    if #cooldowns > 0 then
        -- Delta-encode: skip if same set of spells on cooldown
        local sigParts = {}
        for _, cd in ipairs(cooldowns) do
            sigParts[#sigParts + 1] = cd.spellID
        end
        table.sort(sigParts)
        local sig = table.concat(sigParts, ",")

        if prevCooldownSig == sig then return end
        prevCooldownSig = sig

        AppendEvent({ t = t, type = "cooldown_state", cooldowns = cooldowns })
    elseif prevCooldownSig then
        prevCooldownSig = nil
        AppendEvent({ t = t, type = "cooldown_state", cooldowns = {} })
    end
end

local function PollAllUnits()
    if state ~= "RECORDING" then return end

    local t = GetRelativeTime()

    for _, unit in ipairs(ALL_UNITS) do
        PollUnitState(unit, t)
        PollUnitAuras(unit, t)
    end

    PollPlayerCooldowns(t)
end

---------------------------------------------------------------------------
-- Target/Focus Change Events
---------------------------------------------------------------------------
local function OnUnitTarget(unit)
    if state ~= "RECORDING" then return end
    local guid = UnitGUID(unit)
    if not guid or not IsRelevantGUID(guid) then return end

    local targetGUID = UnitGUID(unit .. "target")
    local targetName = UnitName(unit .. "target")

    -- Deduplicate
    if lastTargets[guid] == targetGUID then return end
    lastTargets[guid] = targetGUID

    AppendEvent({
        t = GetRelativeTime(),
        type = "target_change",
        guid = guid,
        target = StripRealm(targetName),
        targetGUID = targetGUID,
    })
end

local function OnFocusChanged()
    if state ~= "RECORDING" then return end
    local guid = UnitGUID("player")
    local focusGUID = UnitGUID("focus")
    local focusName = UnitName("focus")

    AppendEvent({
        t = GetRelativeTime(),
        type = "focus_change",
        guid = guid,
        target = StripRealm(focusName),
        targetGUID = focusGUID,
    })
end

---------------------------------------------------------------------------
-- Loss of Control
---------------------------------------------------------------------------
local function OnLossOfControl()
    if state ~= "RECORDING" then return end
    if not C_LossOfControl or not C_LossOfControl.GetActiveLossOfControlData then return end

    local numEvents = C_LossOfControl.GetNumEvents and C_LossOfControl.GetNumEvents() or 0
    for i = 1, numEvents do
        local data = C_LossOfControl.GetActiveLossOfControlData(i)
        if data then
            AppendEvent({
                t = GetRelativeTime(),
                type = "loss_of_control",
                locType = data.locType,
                spellID = data.spellID,
                duration = data.duration,
                startTime = data.startTime,
                endTime = data.endTime,
            })
        end
    end
end

---------------------------------------------------------------------------
-- Match Lifecycle
---------------------------------------------------------------------------
local function ResetMatchState()
    state = "IDLE"
    currentMatch = nil
    relevantGUIDs = {}
    guidToRoster = {}
    drState = {}
    lastTargets = {}
    trinketLastStart = {}
    gatesOpenTime = nil
    ratingsBefore = nil
    hadPrepBuff = false
    wipe(prevUnitState)
    wipe(prevAuraSnapshot)
    prevCooldownSig = nil
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
    if snapshotTicker then
        snapshotTicker:Cancel()
        snapshotTicker = nil
    end
end

local function InitMatch()
    currentMatch = {
        startTime = nil,
        endTime = nil,
        map = GetRealZoneText(),
        result = nil,
        duration = nil,
        playerGUID = UnitGUID("player"),
        playerName = StripRealm(UnitName("player")),
        ratingBefore = nil,
        ratingAfter = nil,
        ratingChange = nil,
        mmrBefore = nil,
        mmrAfter = nil,
        mmrChange = nil,
        enemyMMR = nil,
        roster = {},
        events = {},
    }
    relevantGUIDs = {}
    guidToRoster = {}
    drState = {}
    lastTargets = {}
end

---------------------------------------------------------------------------
-- Pet → owner tracking
-- CLEU events from pets carry the pet's GUID; the replayer attributes them
-- back to the owning player (Spell Lock / Devour Magic on the warlock's CD
-- row). SPELL_SUMMON links owner→pet for mid-match summons, but a pet that
-- already existed when the gates opened never appears in a summon event, so
-- we also record explicit pet_owner events from unit tokens at recording
-- start and on every UNIT_PET. One table-valued local (200-locals limit).
---------------------------------------------------------------------------
local petTrack = {
    seen = {},  -- petGUID → ownerGUID already recorded this match
    UNITS = {
        player = "pet",
        party1 = "partypet1", party2 = "partypet2", party3 = "partypet3",
        party4 = "partypet4",
        arena1 = "arenapet1", arena2 = "arenapet2", arena3 = "arenapet3",
        arena4 = "arenapet4", arena5 = "arenapet5",
    },
}

function petTrack:Scan()
    if state ~= "RECORDING" then return end
    for ownerUnit, petUnit in pairs(self.UNITS) do
        local petGUID = UnitGUID(petUnit)
        if petGUID then
            local ownerGUID = UnitGUID(ownerUnit)
            if ownerGUID and self.seen[petGUID] ~= ownerGUID then
                self.seen[petGUID] = ownerGUID
                local petName = UnitName(petUnit)
                AppendEvent({
                    t = GetRelativeTime(), type = "pet_owner",
                    petGUID = petGUID, ownerGUID = ownerGUID,
                    pet = petName and StripRealm(petName) or nil,
                })
                relevantGUIDs[petGUID] = true
                dbg("Pet owner:", petName or petGUID, "→", ownerUnit)
            end
        end
    end
end

local function StartRecording()
    state = "RECORDING"
    gatesOpenTime = GetTime()
    currentMatch.startTime = GetEpochTime()
    -- Server clock alongside the client clock: startTime comes from time()
    -- captured once at addon load (drifts over long sessions, sub-second
    -- digits untrustworthy). The pair lets external tools measure the
    -- client/server delta while keeping the client clock — the one video
    -- recordings are stamped with — for VOD matching.
    currentMatch.serverStartTime = GetServerTime and GetServerTime() or nil

    -- Snapshot ratings
    ratingsBefore = SnapshotAllRatings()

    -- Snapshot roster
    SnapshotRoster()

    -- Emit gates_open
    AppendEvent({ t = 0, type = "gates_open" })

    -- Record pets that already exist at the gates (no SPELL_SUMMON in-log)
    wipe(petTrack.seen)
    petTrack:Scan()

    -- Start 200ms polling
    pollTicker = C_Timer.NewTicker(0.2, PollAllUnits)

    -- Periodic re-snapshot for stealth players
    snapshotTicker = C_Timer.NewTicker(2, function()
        if state == "RECORDING" then
            SnapshotRoster()
        end
    end)

    -- Enable advanced combat logging
    if SetCVar then
        SetCVar("advancedCombatLogging", "1")
    end

    local rosterCount = 0
    for _ in pairs(currentMatch.roster) do rosterCount = rosterCount + 1 end
    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Gates open — recording started (" .. rosterCount .. " players)")
end

-- Games recorded since login/reload — in memory only until SavedVariables
-- flush, so this is exactly the count not yet on disk for web-app upload
local unsyncedGames = 0
local UpdateSyncNudge  -- defined with the Matches tab UI

local function SaveMatch(result)
    if not currentMatch or not currentMatch.startTime then
        dbg("SaveMatch() aborted — no match data")
        return
    end

    state = "SAVING"

    currentMatch.endTime = GetEpochTime()
    currentMatch.result = result
    currentMatch.duration = gatesOpenTime and (GetTime() - gatesOpenTime) or 0

    -- Rating
    if ratingsBefore then
        local ratingsAfter = SnapshotAllRatings()
        if ratingsAfter then
            for i = 1, 3 do
                local before = ratingsBefore[i] or 0
                local after = ratingsAfter[i] or 0
                if before > 0 and after > 0 and before ~= after then
                    currentMatch.ratingBefore = before
                    currentMatch.ratingAfter = after
                    currentMatch.ratingChange = after - before
                    dbg("  Rating detected:", before, "→", after, "(change:", currentMatch.ratingChange .. ")")
                    break
                end
            end
        end
    end

    -- Fallback: try GetBattlefieldScore for ratingChange from scoreboard
    if not currentMatch.ratingChange and GetBattlefieldScore then
        local playerName = StripRealm(UnitName("player"))
        local numScores = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
        for si = 1, numScores do
            local name, _, _, _, _, _, _, _, _, _, _, bgRating, ratingChange = GetBattlefieldScore(si)
            if name and StripRealm(name) == playerName and ratingChange and ratingChange ~= 0 then
                currentMatch.ratingBefore = currentMatch.ratingBefore or (bgRating or 0)
                currentMatch.ratingChange = ratingChange
                currentMatch.ratingAfter = (currentMatch.ratingBefore or 0) + ratingChange
                dbg("  Rating (scoreboard fallback):", currentMatch.ratingBefore, "change:", ratingChange)
                break
            end
        end
    end

    -- MMR from scoreboard (captured independently of how rating was obtained).
    -- Legacy column order: ...rating(12) ratingChange(13) preMatchMMR(14) mmrChange(15)
    if GetBattlefieldScore and GetNumBattlefieldScores then
        local playerName = StripRealm(UnitName("player"))
        local numScores = GetNumBattlefieldScores() or 0
        for si = 1, numScores do
            local name, _, _, _, _, _, _, _, _, _, _, _, _, preMatchMMR, mmrChange = GetBattlefieldScore(si)
            if name and StripRealm(name) == playerName and preMatchMMR and preMatchMMR > 0 then
                currentMatch.mmrBefore = math.floor(preMatchMMR + 0.5)
                currentMatch.mmrChange = math.floor((mmrChange or 0) + 0.5)
                currentMatch.mmrAfter = currentMatch.mmrBefore + currentMatch.mmrChange
                dbg("  MMR (scoreboard):", currentMatch.mmrBefore, "change:", currentMatch.mmrChange)
                break
            end
        end
    end

    -- Per-player rating + MMR + scoreboard stats.
    -- Legacy column order: name(1) killingBlows(2) honorableKills(3) deaths(4)
    -- ... damageDone(10) healingDone(11) rating(12) ratingChange(13)
    -- preMatchMMR(14) mmrChange(15)
    if GetBattlefieldScore and GetNumBattlefieldScores then
        local numScores = GetNumBattlefieldScores() or 0
        for si = 1, numScores do
            local name, killingBlows, _, deaths, _, _, _, _, _, damageDone, healingDone, _, ratingChange, preMatchMMR, mmrChange = GetBattlefieldScore(si)
            if name then
                local cleanName = StripRealm(name)
                for guid, entry in pairs(currentMatch.roster) do
                    if entry.name == cleanName then
                        entry.ratingChange = ratingChange
                        if preMatchMMR and preMatchMMR > 0 then
                            entry.mmr = math.floor(preMatchMMR + 0.5)
                            entry.mmrChange = math.floor((mmrChange or 0) + 0.5)
                        end
                        entry.kbs = killingBlows
                        entry.deaths = deaths
                        entry.damage = damageDone
                        entry.healing = healingDone
                    end
                end
            end
        end
    end

    -- Derive enemy team MMR from any enemy roster entry that has one
    for guid, entry in pairs(currentMatch.roster) do
        if entry.team == "enemy" and entry.mmr and entry.mmr > 0 then
            currentMatch.enemyMMR = entry.mmr
            break
        end
    end

    -- Emit match_end event
    AppendEvent({ t = GetRelativeTime(), type = "match_end", winner = result })

    -- Stop polling
    if pollTicker then pollTicker:Cancel(); pollTicker = nil end
    if snapshotTicker then snapshotTicker:Cancel(); snapshotTicker = nil end

    -- Convert roster to friendlyTeam/enemyTeam arrays for UI compatibility
    local friendlyTeam = {}
    local enemyTeam = {}
    local enemyComp = {}
    local seenClass = {}
    for guid, entry in pairs(currentMatch.roster) do
        local p = {
            name = entry.name,
            fullName = entry.fullName,
            class = entry.class,
            race = entry.race,
            spec = entry.spec,
            ratingChange = entry.ratingChange,
            mmr = entry.mmr,
            mmrChange = entry.mmrChange,
            kbs = entry.kbs,
            deaths = entry.deaths,
            damage = entry.damage,
            healing = entry.healing,
        }
        if entry.team == "friendly" then
            table.insert(friendlyTeam, p)
        elseif entry.team == "enemy" then
            table.insert(enemyTeam, p)
            if entry.class and not seenClass[entry.class] then
                table.insert(enemyComp, entry.class)
                seenClass[entry.class] = true
            end
        end
    end

    -- Determine bracket from team size
    local teamSize = math.max(#friendlyTeam, #enemyTeam)
    local bracketNames = { [2] = "2v2", [3] = "3v3", [5] = "5v5" }
    local bracket = bracketNames[teamSize]

    -- Sorted player GUID list, hoisted out of the eventLog so external tools
    -- (desktop companion, web fingerprint matching) can identify the game
    -- from plain top-level fields without inflating the compressed blob.
    local playerGuids = {}
    for guid in pairs(currentMatch.roster) do
        playerGuids[#playerGuids + 1] = guid
    end
    table.sort(playerGuids)

    -- Compress event log
    local compressedEventLog = CompressEventLog()

    -- Capture arena season (defaults to 1 if API missing or returns 0/nil)
    local season = GetCurrentArenaSeason and GetCurrentArenaSeason() or nil
    if not season or season == 0 then season = 1 end

    -- Save to TrinketedHistoryDB
    table.insert(TrinketedHistoryDB.games, {
        id = GenerateGameId(),
        startTime = currentMatch.startTime,
        endTime = currentMatch.endTime,
        serverStartTime = currentMatch.serverStartTime,
        serverEndTime = GetServerTime and GetServerTime() or nil,
        playerGuids = playerGuids,
        map = currentMatch.map,
        enemyComp = enemyComp,
        result = result,
        playerName = StripRealm(UnitName("player")),
        -- Character identity for cross-realm-safe filtering (see the
        -- backend addon contract): (playerName, playerRealm) is the human
        -- identity, playerGuid the stable machine identity. Distinct from
        -- playerGuids (plural), the all-players list.
        playerRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName(),
        playerGuid = currentMatch.playerGUID,
        friendlyTeam = friendlyTeam,
        enemyTeam = enemyTeam,
        bracket = bracket,
        season = season,
        ratingBefore = currentMatch.ratingBefore,
        ratingAfter = currentMatch.ratingAfter,
        ratingChange = currentMatch.ratingChange,
        mmrBefore = currentMatch.mmrBefore,
        mmrAfter = currentMatch.mmrAfter,
        mmrChange = currentMatch.mmrChange,
        enemyMMR = currentMatch.enemyMMR,
        eventLog = compressedEventLog,
    })

    -- Flush combat log between games
    LoggingCombat(false)
    LoggingCombat(true)
    dbg("Combat log flushed")

    UpdateOverlayVisibility()

    local count = #TrinketedHistoryDB.games
    local eventCount = #currentMatch.events
    local ratingStr = ""
    if currentMatch.ratingChange then
        local sign = currentMatch.ratingChange >= 0 and "+" or ""
        local color = currentMatch.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
        ratingStr = " " .. color .. "(" .. sign .. currentMatch.ratingChange .. " rating, " ..
            (currentMatch.ratingBefore or "?") .. "→" .. (currentMatch.ratingAfter or "?") .. ")|r"
    end
    local mmrStr = ""
    if currentMatch.mmrBefore then
        mmrStr = " |cff888888[MMR " .. currentMatch.mmrBefore ..
            (currentMatch.mmrChange and currentMatch.mmrChange ~= 0
                and string.format(" (%+d)", currentMatch.mmrChange) or "") .. "]|r"
    end
    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Game #" .. count .. " recorded — " .. result .. ratingStr .. mmrStr ..
        " | " .. eventCount .. " events | " .. string.format("%.1fs", currentMatch.duration))

    unsyncedGames = unsyncedGames + 1
    if UpdateSyncNudge then UpdateSyncNudge() end

    ResetMatchState()
end


---------------------------------------------------------------------------
-- History Filters
---------------------------------------------------------------------------
local filters = {
    friendlyComps = {},   -- table of compKey = true for selected player comps (empty = all)
    partners = {},        -- table of name = true for selected partners (empty = all)
    enemyComps = {},      -- table of compKey = true for selected enemy comps (empty = all)
    enemyPlayers = {},    -- table of name = true for selected enemy players (empty = all)
    enemyRaces = {},      -- table of race = true for selected enemy races (empty = all)
    maps = {},            -- table of map name = true for selected arenas (empty = all)
    result = nil,
    bracket = "All",      -- "All" | "2v2" | "3v3" | "5v5"
    season = currentSeason,
    search = "",          -- free-text: space-separated terms, all must match
}

-- Build a sorted slash-separated comp string from a team table
-- Includes spec abbreviation when available: "Arms Warrior/Disc Priest"
local function GetCompKey(team)
    if not team or #team == 0 then return nil end
    local entries = {}
    for _, p in ipairs(team) do
        table.insert(entries, p.class or "?")
    end
    table.sort(entries)
    return table.concat(entries, "/")
end

---------------------------------------------------------------------------
-- Session Computation
---------------------------------------------------------------------------
local SESSION_GAP_SECONDS = 3600  -- 60 minutes

-- Build a sorted slash-separated key from the friendly team, excluding self.
local function GetPartnerKey(game)
    local me = UnitName("player")
    local names = {}
    for _, p in ipairs(game.friendlyTeam or {}) do
        if p.name ~= me then
            table.insert(names, p.name)
        end
    end
    table.sort(names)
    return table.concat(names, "/")
end

-- Group a games array into sessions based on time gaps and partner changes.
-- bracketFilter: "2v2", "3v3", "5v5", or nil (all)
-- daysFilter:    0 or nil = all time, 7/30/90 = last N days
-- mapsFilter:    set of map names {[mapName]=true} to include, or nil = all
-- seasonFilter:  specific season number to include, or nil = all
-- Returns an array of session objects sorted chronologically (oldest first).
local function ComputeSessions(games, bracketFilter, daysFilter, mapsFilter, seasonFilter)
    if not games or #games == 0 then return {} end

    -- Determine cutoff timestamp for daysFilter
    local cutoff = 0
    if daysFilter and daysFilter > 0 then
        cutoff = time() - (daysFilter * 86400)
    end

    local hasMapFilter = mapsFilter and next(mapsFilter) ~= nil

    -- Filter games
    local filtered = {}
    for _, g in ipairs(games) do
        local dominated = true
        if bracketFilter and g.bracket ~= bracketFilter then
            dominated = false
        end
        if dominated and cutoff > 0 and (g.startTime or 0) < cutoff then
            dominated = false
        end
        if dominated and hasMapFilter and (not g.map or not mapsFilter[g.map]) then
            dominated = false
        end
        if dominated and seasonFilter and (g.season or 1) ~= seasonFilter then
            dominated = false
        end
        if dominated then
            table.insert(filtered, g)
        end
    end

    if #filtered == 0 then return {} end

    -- Sort chronologically (oldest first)
    table.sort(filtered, function(a, b)
        return (a.startTime or 0) < (b.startTime or 0)
    end)

    -- Walk through filtered games and group into sessions
    local sessions = {}
    local cur = nil  -- current session being built

    for _, g in ipairs(filtered) do
        local pk = GetPartnerKey(g)
        local needNew = false

        if not cur then
            needNew = true
        else
            local gap = (g.startTime or 0) - (cur.endTime or 0)
            if gap > SESSION_GAP_SECONDS then
                needNew = true
            elseif pk ~= cur.partnerKey then
                needNew = true
            end
        end

        if needNew then
            -- Finalise previous session if any (aggregates computed later)
            if cur then
                table.insert(sessions, cur)
            end
            cur = {
                games     = {},
                startTime = g.startTime,
                endTime   = g.endTime,
                bracket   = g.bracket,
                partnerKey = pk,
            }
        else
            -- Extend current session
            cur.endTime = g.endTime
            if cur.bracket ~= g.bracket then
                cur.bracket = "Mixed"
            end
        end

        table.insert(cur.games, g)
    end

    -- Don't forget the last session
    if cur then
        table.insert(sessions, cur)
    end

    -- Compute aggregates for each session
    local me = UnitName("player")
    for _, s in ipairs(sessions) do
        local wins, losses = 0, 0
        local totalRatingChange = 0
        local playTime = 0

        for _, g in ipairs(s.games) do
            if g.result == "WIN" then
                wins = wins + 1
            elseif g.result == "LOSS" then
                losses = losses + 1
            end
            totalRatingChange = totalRatingChange + (g.ratingChange or 0)
            -- Time actually spent in arena, not the session's wall-clock span
            -- (which would include queue time and breaks between games).
            if g.startTime and g.endTime and g.endTime > g.startTime then
                playTime = playTime + (g.endTime - g.startTime)
            end
        end

        s.wins         = wins
        s.losses       = losses
        s.playTime     = playTime
        s.ratingStart  = s.games[1].ratingBefore
        s.ratingEnd    = s.games[#s.games].ratingAfter
        -- Prefer direct difference when both endpoints are known;
        -- fall back to sum of per-game changes otherwise
        if s.ratingStart and s.ratingEnd then
            s.ratingChange = s.ratingEnd - s.ratingStart
        else
            s.ratingChange = totalRatingChange
        end

        -- MMR endpoints: first/last games in the session that recorded MMR
        for _, g in ipairs(s.games) do
            if g.mmrBefore then s.mmrStart = g.mmrBefore; break end
        end
        for i = #s.games, 1, -1 do
            if s.games[i].mmrAfter then s.mmrEnd = s.games[i].mmrAfter; break end
        end
        if s.mmrStart and s.mmrEnd then
            s.mmrChange = s.mmrEnd - s.mmrStart
        end

        -- Collect unique partners (friendly team members excluding self)
        local seen = {}
        local partners = {}
        for _, g in ipairs(s.games) do
            for _, p in ipairs(g.friendlyTeam or {}) do
                if p.name ~= me and not seen[p.name] then
                    seen[p.name] = true
                    table.insert(partners, { name = p.name, class = p.class })
                end
            end
        end
        s.partners = partners
    end

    return sessions
end

---------------------------------------------------------------------------
-- ComputeTeams: aggregate win/loss by partner combination + bracket
---------------------------------------------------------------------------
local function ComputeTeams(games, bracketFilter, seasonFilter)
    if not games or #games == 0 then return {} end

    local me = UnitName("player")
    local teamMap = {} -- key = "partnerNames|bracket"

    for _, g in ipairs(games) do
        local bracketOk = not bracketFilter or g.bracket == bracketFilter
        local seasonOk = not seasonFilter or (g.season or 1) == seasonFilter
        if bracketOk and seasonOk then
            local pk = GetPartnerKey(g)
            local bracket = g.bracket or "?"
            local key = pk .. "|" .. bracket

            if not teamMap[key] then
                -- Collect partner info from this game
                local partners = {}
                for _, p in ipairs(g.friendlyTeam or {}) do
                    if p.name ~= me then
                        table.insert(partners, { name = p.name, class = p.class })
                    end
                end
                teamMap[key] = {
                    partners = partners,
                    bracket = bracket,
                    wins = 0,
                    losses = 0,
                    netRating = 0,
                    totalGames = 0,
                }
            end

            local t = teamMap[key]
            t.totalGames = t.totalGames + 1
            if g.result == "WIN" then
                t.wins = t.wins + 1
            elseif g.result == "LOSS" then
                t.losses = t.losses + 1
            end
            t.netRating = t.netRating + (g.ratingChange or 0)
        end
    end

    -- Convert to sorted array (most games first)
    local teams = {}
    for _, t in pairs(teamMap) do
        table.insert(teams, t)
    end
    table.sort(teams, function(a, b)
        if a.totalGames ~= b.totalGames then return a.totalGames > b.totalGames end
        return a.wins > b.wins
    end)

    return teams
end

---------------------------------------------------------------------------
-- ComputeEnemies: aggregate lifetime W/L and net rating vs each enemy player.
-- Each game contributes its rating change once to every distinct opponent that
-- appeared on the enemy team — so "Net" is the cumulative points you've gained
-- or lost across all matches you played against that player.
---------------------------------------------------------------------------
local function ComputeEnemies(games, bracketFilter, seasonFilter)
    if not games or #games == 0 then return {} end

    local enemyMap = {} -- key = enemy player name

    for _, g in ipairs(games) do
        local bracketOk = not bracketFilter or g.bracket == bracketFilter
        local seasonOk = not seasonFilter or (g.season or 1) == seasonFilter
        if bracketOk and seasonOk then
            local seen = {}
            for _, p in ipairs(g.enemyTeam or {}) do
                local name = p.name
                if name and not seen[name] then
                    seen[name] = true
                    local e = enemyMap[name]
                    if not e then
                        e = { name = name, class = p.class, race = p.race,
                              wins = 0, losses = 0, netRating = 0, totalGames = 0 }
                        enemyMap[name] = e
                    end
                    if p.class then e.class = p.class end
                    e.totalGames = e.totalGames + 1
                    if g.result == "WIN" then
                        e.wins = e.wins + 1
                    elseif g.result == "LOSS" then
                        e.losses = e.losses + 1
                    end
                    -- Gain/loss is rating-based: prefer the actual before→after
                    -- delta, fall back to the stored ratingChange.
                    local delta
                    if g.ratingBefore and g.ratingAfter then
                        delta = g.ratingAfter - g.ratingBefore
                    else
                        delta = g.ratingChange or 0
                    end
                    e.netRating = e.netRating + delta
                end
            end
        end
    end

    local enemies = {}
    for _, e in pairs(enemyMap) do
        table.insert(enemies, e)
    end
    table.sort(enemies, function(a, b)
        if a.totalGames ~= b.totalGames then return a.totalGames > b.totalGames end
        return a.wins > b.wins
    end)

    return enemies
end

-- Weak-keyed so entries vanish with their game records; never stored on the
-- game table itself (that would persist search text into SavedVariables)
local searchTextCache = setmetatable({}, { __mode = "k" })

local function GameMatchesFilters(game)
    if filters.result and game.result ~= filters.result then
        return false
    end
    -- Player comp filter (multi-select)
    if next(filters.friendlyComps) then
        local comp = GetCompKey(game.friendlyTeam)
        if not comp or not filters.friendlyComps[comp] then return false end
    end
    -- Partners filter (multi-select)
    if next(filters.partners) then
        local found = false
        for _, p in ipairs(game.friendlyTeam or {}) do
            if filters.partners[p.name] then found = true; break end
        end
        if not found then return false end
    end
    -- Enemy comp filter (multi-select)
    if next(filters.enemyComps) then
        local comp = GetCompKey(game.enemyTeam)
        if not comp or not filters.enemyComps[comp] then return false end
    end
    -- Enemy players filter (multi-select)
    if next(filters.enemyPlayers) then
        local found = false
        for _, p in ipairs(game.enemyTeam or {}) do
            if filters.enemyPlayers[p.name] then found = true; break end
        end
        if not found then return false end
    end
    -- Enemy races filter (multi-select)
    if next(filters.enemyRaces) then
        local found = false
        for _, p in ipairs(game.enemyTeam or {}) do
            if p.race and filters.enemyRaces[p.race] then found = true; break end
        end
        if not found then return false end
    end
    -- Map filter (multi-select)
    if next(filters.maps) then
        if not game.map or not filters.maps[game.map] then return false end
    end
    -- Bracket filter (single-select)
    if filters.bracket and filters.bracket ~= "All" and game.bracket ~= filters.bracket then
        return false
    end
    -- Season filter (single-select)
    if filters.season and (game.season or 1) ~= filters.season then
        return false
    end
    -- Free-text search: every space-separated term must match a player
    -- name/class/spec/race on either team, or the map (case-insensitive)
    if filters.search ~= "" then
        local hay = searchTextCache[game]
        if not hay then
            local parts = {}
            local function add(v)
                if type(v) == "string" then parts[#parts + 1] = v end
            end
            for _, team in ipairs({ game.friendlyTeam or {}, game.enemyTeam or {} }) do
                for _, p in ipairs(team) do
                    add(p.name); add(p.class); add(p.spec); add(p.race)
                end
            end
            add(game.map); add(game.bracket)
            hay = table.concat(parts, " "):lower()
            searchTextCache[game] = hay
        end
        for term in filters.search:gmatch("%S+") do
            if not hay:find(term, 1, true) then return false end
        end
    end
    return true
end

local function CollectUniqueComps(teamKey)
    local comps = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        local key = GetCompKey(game[teamKey])
        if key and not seen[key] then
            table.insert(comps, key)
            seen[key] = true
        end
    end
    table.sort(comps)
    return comps
end

local function CollectUniquePartners()
    local playerName = UnitName("player")
    local partners = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        -- Scope partners to selected friendly comps if any
        if next(filters.friendlyComps) then
            local comp = GetCompKey(game.friendlyTeam)
            if not comp or not filters.friendlyComps[comp] then
                -- skip this game
            else
                for _, p in ipairs(game.friendlyTeam or {}) do
                    if p.name ~= playerName and not seen[p.name] then
                        table.insert(partners, { name = p.name, class = p.class })
                        seen[p.name] = true
                    end
                end
            end
        else
            for _, p in ipairs(game.friendlyTeam or {}) do
                if p.name ~= playerName and not seen[p.name] then
                    table.insert(partners, { name = p.name, class = p.class })
                    seen[p.name] = true
                end
            end
        end
    end
    table.sort(partners, function(a, b) return a.name < b.name end)
    return partners
end

local function CollectUniqueEnemyPlayers()
    local players = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        -- Scope to selected enemy comps if any
        if next(filters.enemyComps) then
            local comp = GetCompKey(game.enemyTeam)
            if not comp or not filters.enemyComps[comp] then
                -- skip
            else
                for _, p in ipairs(game.enemyTeam or {}) do
                    if not seen[p.name] then
                        table.insert(players, { name = p.name, class = p.class })
                        seen[p.name] = true
                    end
                end
            end
        else
            for _, p in ipairs(game.enemyTeam or {}) do
                if not seen[p.name] then
                    table.insert(players, { name = p.name, class = p.class })
                    seen[p.name] = true
                end
            end
        end
    end
    table.sort(players, function(a, b) return a.name < b.name end)
    return players
end

local function CollectUniqueEnemyRaces()
    local races = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        -- Scope to selected enemy comps if any
        if next(filters.enemyComps) then
            local comp = GetCompKey(game.enemyTeam)
            if not comp or not filters.enemyComps[comp] then
                -- skip
            else
                for _, p in ipairs(game.enemyTeam or {}) do
                    if p.race and not seen[p.race] then
                        table.insert(races, p.race)
                        seen[p.race] = true
                    end
                end
            end
        else
            for _, p in ipairs(game.enemyTeam or {}) do
                if p.race and not seen[p.race] then
                    table.insert(races, p.race)
                    seen[p.race] = true
                end
            end
        end
    end
    table.sort(races)
    return races
end

local function CollectUniqueSeasons()
    local seasons = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        local s = game.season or 1
        if not seen[s] then
            table.insert(seasons, s)
            seen[s] = true
        end
    end
    table.sort(seasons, function(a, b) return a > b end)  -- newest first
    return seasons
end

---------------------------------------------------------------------------
-- History Content (embedded in the options panel)
---------------------------------------------------------------------------
local historyContent = CreateFrame("Frame", "TrinketedHistoryContent", UIParent)
historyContent:SetSize(1, 1)
historyContent:Hide()

local activeTab = "matches" -- "matches", "sessions", "teams", or "settings"

-- Forward declarations for tab refresh functions
local RefreshHistory
local RefreshSessions
local RefreshTeams
local RefreshEnemies

-- RefreshActiveTab is called from the contentFrame:OnShow hook (set in OnSelect)
local function RefreshActiveTab()
    if activeTab == "sessions" then
        if RefreshSessions then RefreshSessions() end
    elseif activeTab == "teams" then
        if RefreshTeams then RefreshTeams() end
    elseif activeTab == "enemies" then
        if RefreshEnemies then RefreshEnemies() end
    elseif activeTab == "matches" then
        if RefreshHistory then RefreshHistory() end
    end
end

-- Tab container fills the content area
local tabContainer = CreateFrame("Frame", nil, historyContent)
tabContainer:SetAllPoints()

local historyTabBar = lib:CreateTabBar(tabContainer, {
    { "matches", "Matches" },
    { "sessions", "Sessions" },
    { "teams", "Teams" },
    { "enemies", "Enemies" },
    { "settings", "Settings" },
}, {
    height = 26,
    tabWidth = 80,
    onChange = function(key)
        activeTab = key
        if key == "matches" then
            if RefreshHistory then RefreshHistory() end
        elseif key == "sessions" then
            if RefreshSessions then RefreshSessions() end
        elseif key == "teams" then
            if RefreshTeams then RefreshTeams() end
        elseif key == "enemies" then
            if RefreshEnemies then RefreshEnemies() end
        end
    end,
})



local matchesContainer = historyTabBar.contents["matches"]
local sessionsContainer = historyTabBar.contents["sessions"]
local teamsContainer = historyTabBar.contents["teams"]
local enemiesContainer = historyTabBar.contents["enemies"]
local settingsContainer = historyTabBar.contents["settings"]

historyTabBar:SelectTab("matches")

-- Format a comp key ("Disc Priest/Arms Warrior") into class-colored text
local function FormatCompLabel(compKey)
    if not compKey then return "All" end
    -- Parity with the app: class icons + its abbreviation for this class
    -- set when one exists (CompLabels port of the app's comp registry),
    -- class-colored names otherwise.
    local team = {}
    for class in compKey:gmatch("[^/]+") do
        table.insert(team, { class = class })
    end
    local icons = addon.CompLabels and addon.CompLabels.KeyIcons(compKey, 12) or ""
    local label = addon.CompLabels and addon.CompLabels.GetLabel(team)
    if label then
        return icons .. " " .. label
    end
    local parts = {}
    for class in compKey:gmatch("[^/]+") do
        local color = CLASS_COLORS[class] or "ffffffff"
        table.insert(parts, "|c" .. color .. class .. "|r")
    end
    return icons .. " " .. table.concat(parts, "/")
end

---------------------------------------------------------------------------
-- Searchable Multi-Select Dropdown Widget
---------------------------------------------------------------------------
local SD_ROW_H = 18
local SD_MAX_ROWS = 10
local activePopup = nil  -- track which popup is currently open

local function CreateSearchableDropdown(parent, ddName, width, opts)
    local dd = {}

    -- Main trigger button
    local btn = CreateFrame("Button", ddName .. "Btn", parent)
    btn:SetSize(width, 24)
    dd.frame = btn

    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    btnBg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)

    -- 1px border (matching brand pattern)
    local bdrTop = btn:CreateTexture(nil, "ARTWORK")
    bdrTop:SetPoint("TOPLEFT"); bdrTop:SetPoint("TOPRIGHT"); bdrTop:SetHeight(1)
    bdrTop:SetColorTexture(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
    local bdrBot = btn:CreateTexture(nil, "ARTWORK")
    bdrBot:SetPoint("BOTTOMLEFT"); bdrBot:SetPoint("BOTTOMRIGHT"); bdrBot:SetHeight(1)
    bdrBot:SetColorTexture(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
    local bdrL = btn:CreateTexture(nil, "ARTWORK")
    bdrL:SetPoint("TOPLEFT"); bdrL:SetPoint("BOTTOMLEFT"); bdrL:SetWidth(1)
    bdrL:SetColorTexture(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
    local bdrR = btn:CreateTexture(nil, "ARTWORK")
    bdrR:SetPoint("TOPRIGHT"); bdrR:SetPoint("BOTTOMRIGHT"); bdrR:SetWidth(1)
    bdrR:SetColorTexture(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(lib.FONT_BODY, 10, "")
    lbl:SetPoint("LEFT", 6, 0)
    lbl:SetPoint("RIGHT", -16, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    local arrow = btn:CreateFontString(nil, "OVERLAY")
    arrow:SetFont(lib.FONT_MONO, 8, "")
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetText("v")
    arrow:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    function dd:SetLabel(text) lbl:SetText(text) end
    dd:SetLabel(opts.defaultLabel or "All")

    -- Full-screen click-catcher backdrop
    local bdrop = CreateFrame("Button", nil, UIParent)
    bdrop:SetFrameStrata("FULLSCREEN")
    bdrop:SetAllPoints(UIParent)
    bdrop:Hide()
    bdrop:SetScript("OnClick", function() dd:Close() end)

    -- Popup frame
    local popup = CreateFrame("Frame", ddName .. "Pop", UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetSize(width + 20, 200)

    local popBg = popup:CreateTexture(nil, "BACKGROUND")
    popBg:SetAllPoints()
    popBg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 1)

    -- 1px border
    local popBdrTop = popup:CreateTexture(nil, "ARTWORK")
    popBdrTop:SetPoint("TOPLEFT"); popBdrTop:SetPoint("TOPRIGHT"); popBdrTop:SetHeight(1)
    popBdrTop:SetColorTexture(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
    local popBdrBot = popup:CreateTexture(nil, "ARTWORK")
    popBdrBot:SetPoint("BOTTOMLEFT"); popBdrBot:SetPoint("BOTTOMRIGHT"); popBdrBot:SetHeight(1)
    popBdrBot:SetColorTexture(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
    local popBdrL = popup:CreateTexture(nil, "ARTWORK")
    popBdrL:SetPoint("TOPLEFT"); popBdrL:SetPoint("BOTTOMLEFT"); popBdrL:SetWidth(1)
    popBdrL:SetColorTexture(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
    local popBdrR = popup:CreateTexture(nil, "ARTWORK")
    popBdrR:SetPoint("TOPRIGHT"); popBdrR:SetPoint("BOTTOMRIGHT"); popBdrR:SetWidth(1)
    popBdrR:SetColorTexture(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)

    popup:Hide()

    -- "Clear All" button
    local clrBtn = CreateFrame("Button", nil, popup)
    clrBtn:SetSize(width + 10, SD_ROW_H)
    clrBtn:SetPoint("TOPLEFT", 5, -5)
    local clrTxt = clrBtn:CreateFontString(nil, "OVERLAY")
    clrTxt:SetFont(lib.FONT_BODY, 10, "")
    clrTxt:SetPoint("LEFT", 4, 0)
    clrTxt:SetText("All (clear)")
    clrTxt:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    local clrHL = clrBtn:CreateTexture(nil, "HIGHLIGHT")
    clrHL:SetAllPoints()
    clrHL:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
    clrBtn:SetScript("OnClick", function()
        if opts.onClear then opts.onClear() end
        dd:Refresh()
    end)

    -- Search box
    local sBox = CreateFrame("EditBox", ddName .. "Srch", popup)
    sBox:SetSize(width + 4, 18)
    sBox:SetPoint("TOPLEFT", 8, -5 - SD_ROW_H - 2)
    sBox:SetAutoFocus(false)
    sBox:SetFont(lib.FONT_BODY, 10, "")
    sBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    local sBoxBg = sBox:CreateTexture(nil, "BACKGROUND")
    sBoxBg:SetAllPoints()
    sBoxBg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)
    local sBoxBdr = sBox:CreateTexture(nil, "ARTWORK")
    sBoxBdr:SetPoint("BOTTOMLEFT"); sBoxBdr:SetPoint("BOTTOMRIGHT"); sBoxBdr:SetHeight(1)
    sBoxBdr:SetColorTexture(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
    local sPH = sBox:CreateFontString(nil, "ARTWORK")
    sPH:SetFont(lib.FONT_BODY, 10, "")
    sPH:SetPoint("LEFT", 2, 0)
    sPH:SetText("Search...")
    sPH:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    sBox:SetScript("OnEditFocusGained", function() sPH:Hide() end)
    sBox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then sPH:Show() end end)
    sBox:SetScript("OnEscapePressed", function() dd:Close() end)

    -- Scroll frame for options
    local scrollY = -5 - SD_ROW_H - 2 - 22 - 2
    local sf = CreateFrame("ScrollFrame", ddName .. "SF", popup, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 5, scrollY)
    sf:SetPoint("BOTTOMRIGHT", -26, 5)
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(width - 10, 1)
    sf:SetScrollChild(sc)

    local rowPool = {}
    local curOpts = {}

    local function MakeRow(idx)
        local r = CreateFrame("Button", nil, sc)
        r:SetSize(width - 10, SD_ROW_H)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
        r.chk = r:CreateTexture(nil, "OVERLAY")
        r.chk:SetSize(6, 6)
        r.chk:SetPoint("LEFT", 4, 0)
        r.txt = r:CreateFontString(nil, "OVERLAY")
        r.txt:SetFont(lib.FONT_BODY, 10, "")
        r.txt:SetPoint("LEFT", 16, 0)
        r.txt:SetPoint("RIGHT", -2, 0)
        r.txt:SetJustifyH("LEFT")
        r.txt:SetWordWrap(false)
        r.txt:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
        rowPool[idx] = r
        return r
    end

    local function SetChk(tex, on)
        if on then
            tex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            tex:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.6)
        end
    end

    local function FilterDisplay()
        local q = (sBox:GetText() or ""):lower()
        for _, r in ipairs(rowPool) do r:Hide() end
        local vi = 0
        for _, opt in ipairs(curOpts) do
            if q == "" or opt.searchText:find(q, 1, true) then
                vi = vi + 1
                local r = rowPool[vi] or MakeRow(vi)
                r:SetPoint("TOPLEFT", 0, -((vi - 1) * SD_ROW_H))
                r.txt:SetText(opt.text)
                SetChk(r.chk, opt.isChecked())
                r:SetScript("OnClick", function()
                    if opts.onToggle then opts.onToggle(opt.key) end
                    if opts.autoClose then
                        if opts.getLabel then dd:SetLabel(opts.getLabel()) end
                        dd:Close()
                    else
                        SetChk(r.chk, opt.isChecked())
                        if opts.getLabel then dd:SetLabel(opts.getLabel()) end
                    end
                end)
                r:Show()
            end
        end
        sc:SetHeight(math.max(vi * SD_ROW_H, 1))
        local listH = math.min(vi, SD_MAX_ROWS) * SD_ROW_H
        popup:SetHeight(math.max(5 + SD_ROW_H + 2 + 22 + 2 + listH + 8, 60))
    end

    sBox:SetScript("OnTextChanged", function() FilterDisplay() end)

    function dd:Refresh()
        if opts.getLabel then dd:SetLabel(opts.getLabel()) end
        if popup:IsShown() then
            curOpts = opts.getOptions and opts.getOptions() or {}
            FilterDisplay()
        end
    end

    function dd:Open()
        if activePopup and activePopup ~= dd then activePopup:Close() end
        CloseDropDownMenus()
        curOpts = opts.getOptions and opts.getOptions() or {}
        sBox:SetText("")
        sPH:Show()
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        bdrop:Show()
        popup:Show()
        sBox:SetFocus()
        activePopup = dd
        FilterDisplay()
    end

    function dd:Close()
        popup:Hide()
        bdrop:Hide()
        sBox:ClearFocus()
        if activePopup == dd then activePopup = nil end
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then dd:Close() else dd:Open() end
    end)
    btn:SetScript("OnEnter", function()
        btnBg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)
    end)
    btn:SetScript("OnLeave", function()
        btnBg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)
    end)

    return dd
end

---------------------------------------------------------------------------
-- Filter Row 1: Player Comp | Partner | Enemy Comp
---------------------------------------------------------------------------
local friendlyCompDD = CreateSearchableDropdown(matchesContainer, "TkCompDD", 155, {
    defaultLabel = "Player Comp: All",
    getOptions = function()
        local out = {}
        for _, comp in ipairs(CollectUniqueComps("friendlyTeam")) do
            table.insert(out, { key = comp, text = FormatCompLabel(comp), searchText = comp:lower():gsub("/", " "), isChecked = function() return filters.friendlyComps[comp] == true end })
        end
        return out
    end,
    onToggle = function(key)
        if filters.friendlyComps[key] then filters.friendlyComps[key] = nil else filters.friendlyComps[key] = true end
        filters.partners = {}
        RefreshHistory()
    end,
    onClear = function() filters.friendlyComps = {}; filters.partners = {}; RefreshHistory() end,
    getLabel = function()
        if not next(filters.friendlyComps) then return "Player Comp: All" end
        local t = {}; for c in pairs(filters.friendlyComps) do table.insert(t, FormatCompLabel(c)) end
        return "Player Comp: " .. table.concat(t, ", ")
    end,
})
friendlyCompDD.frame:SetPoint("TOPLEFT", 12, -10)

local partnerDD = CreateSearchableDropdown(matchesContainer, "TkPartDD", 155, {
    defaultLabel = "Partner: All",
    getOptions = function()
        local out = {}
        for _, p in ipairs(CollectUniquePartners()) do
            local color = CLASS_COLORS[p.class] or "ffffffff"
            table.insert(out, { key = p.name, text = "|c" .. color .. p.name .. "|r", searchText = p.name:lower(), isChecked = function() return filters.partners[p.name] == true end })
        end
        return out
    end,
    onToggle = function(key)
        if filters.partners[key] then filters.partners[key] = nil else filters.partners[key] = true end
        RefreshHistory()
    end,
    onClear = function() filters.partners = {}; RefreshHistory() end,
    getLabel = function()
        if not next(filters.partners) then return "Partner: All" end
        local t = {}; for n in pairs(filters.partners) do table.insert(t, n) end
        return "Partner: " .. table.concat(t, ", ")
    end,
})
partnerDD.frame:SetPoint("TOPLEFT", 177, -10)

local enemyCompDD = CreateSearchableDropdown(matchesContainer, "TkECompDD", 155, {
    defaultLabel = "Enemy Comp: All",
    getOptions = function()
        local out = {}
        for _, comp in ipairs(CollectUniqueComps("enemyTeam")) do
            table.insert(out, { key = comp, text = FormatCompLabel(comp), searchText = comp:lower():gsub("/", " "), isChecked = function() return filters.enemyComps[comp] == true end })
        end
        return out
    end,
    onToggle = function(key)
        if filters.enemyComps[key] then filters.enemyComps[key] = nil else filters.enemyComps[key] = true end
        filters.enemyPlayers = {}; filters.enemyRaces = {}
        RefreshHistory()
    end,
    onClear = function() filters.enemyComps = {}; filters.enemyPlayers = {}; filters.enemyRaces = {}; RefreshHistory() end,
    getLabel = function()
        if not next(filters.enemyComps) then return "Enemy Comp: All" end
        local t = {}; for c in pairs(filters.enemyComps) do table.insert(t, FormatCompLabel(c)) end
        return "Enemy Comp: " .. table.concat(t, ", ")
    end,
})
enemyCompDD.frame:SetPoint("TOPLEFT", 342, -10)

local bracketDD = CreateSearchableDropdown(matchesContainer, "TkBracketDD", 120, {
    defaultLabel = "Bracket: All",
    getOptions = function()
        local out = {}
        for _, b in ipairs({ "2v2", "3v3", "5v5" }) do
            table.insert(out, {
                key = b,
                text = b,
                searchText = b:lower(),
                isChecked = function() return filters.bracket == b end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if filters.bracket == key then
            filters.bracket = "All"
        else
            filters.bracket = key
        end
        RefreshHistory()
    end,
    onClear = function() filters.bracket = "All"; RefreshHistory() end,
    getLabel = function()
        if filters.bracket == "All" then return "Bracket: All" end
        return "Bracket: " .. filters.bracket
    end,
})
bracketDD.frame:SetPoint("TOPLEFT", 502, -10)

---------------------------------------------------------------------------
-- Filter Row 2: Enemy Players | Enemy Race | Result | Reset
---------------------------------------------------------------------------
local enemyPlayerDD = CreateSearchableDropdown(matchesContainer, "TkEPlrDD", 155, {
    defaultLabel = "Enemy Players: All",
    getOptions = function()
        local out = {}
        for _, p in ipairs(CollectUniqueEnemyPlayers()) do
            local color = CLASS_COLORS[p.class] or "ffffffff"
            table.insert(out, { key = p.name, text = "|c" .. color .. p.name .. "|r", searchText = p.name:lower(), isChecked = function() return filters.enemyPlayers[p.name] == true end })
        end
        return out
    end,
    onToggle = function(key)
        if filters.enemyPlayers[key] then filters.enemyPlayers[key] = nil else filters.enemyPlayers[key] = true end
        RefreshHistory()
    end,
    onClear = function() filters.enemyPlayers = {}; RefreshHistory() end,
    getLabel = function()
        if not next(filters.enemyPlayers) then return "Enemy Players: All" end
        local t = {}; for n in pairs(filters.enemyPlayers) do table.insert(t, n) end
        return "Enemy Players: " .. table.concat(t, ", ")
    end,
})
enemyPlayerDD.frame:SetPoint("TOPLEFT", 12, -36)

local enemyRaceDD = CreateSearchableDropdown(matchesContainer, "TkERaceDD", 155, {
    defaultLabel = "Race: All",
    getOptions = function()
        local out = {}
        for _, race in ipairs(CollectUniqueEnemyRaces()) do
            table.insert(out, { key = race, text = race, searchText = race:lower(), isChecked = function() return filters.enemyRaces[race] == true end })
        end
        return out
    end,
    onToggle = function(key)
        if filters.enemyRaces[key] then filters.enemyRaces[key] = nil else filters.enemyRaces[key] = true end
        RefreshHistory()
    end,
    onClear = function() filters.enemyRaces = {}; RefreshHistory() end,
    getLabel = function()
        if not next(filters.enemyRaces) then return "Race: All" end
        local t = {}; for r in pairs(filters.enemyRaces) do table.insert(t, r) end
        return "Race: " .. table.concat(t, ", ")
    end,
})
enemyRaceDD.frame:SetPoint("TOPLEFT", 177, -36)

local resultDD = CreateSearchableDropdown(matchesContainer, "TkResultDD", 155, {
    defaultLabel = "Result: All",
    getOptions = function()
        return {
            { key = "WIN",  text = "|cff00ff00WIN|r",  searchText = "win",  isChecked = function() return filters.result == "WIN" end },
            { key = "LOSS", text = "|cffff0000LOSS|r", searchText = "loss", isChecked = function() return filters.result == "LOSS" end },
        }
    end,
    onToggle = function(key)
        -- Single-select toggle: clicking the active one clears it, otherwise sets it
        if filters.result == key then
            filters.result = nil
        else
            filters.result = key
        end
        RefreshHistory()
    end,
    onClear = function() filters.result = nil; RefreshHistory() end,
    getLabel = function()
        if filters.result == "WIN" then return "|cff00ff00WIN|r" end
        if filters.result == "LOSS" then return "|cffff0000LOSS|r" end
        return "Result: All"
    end,
})
resultDD.frame:SetPoint("TOPLEFT", 342, -36)

local mapDD = CreateSearchableDropdown(matchesContainer, "TkMapDD", 120, {
    defaultLabel = "Map: All",
    getOptions = function()
        local out = {}
        local maps = { "Nagrand Arena", "Blade's Edge Arena", "Ruins of Lordaeron" }
        for _, m in ipairs(maps) do
            table.insert(out, {
                key = m,
                text = AbbrevMap(m) .. "  |cff888888" .. m .. "|r",
                searchText = (m .. " " .. AbbrevMap(m)):lower(),
                isChecked = function() return filters.maps[m] == true end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if filters.maps[key] then filters.maps[key] = nil else filters.maps[key] = true end
        RefreshHistory()
    end,
    onClear = function() filters.maps = {}; RefreshHistory() end,
    getLabel = function()
        if not next(filters.maps) then return "Map: All" end
        local t = {}; for m in pairs(filters.maps) do table.insert(t, AbbrevMap(m)) end
        return "Map: " .. table.concat(t, ", ")
    end,
})
mapDD.frame:SetPoint("TOPLEFT", 502, -36)

local seasonDD = CreateSearchableDropdown(matchesContainer, "TkSeasonDD", 120, {
    defaultLabel = "|cffE8B923Season " .. currentSeason .. "|r",
    autoClose = true,
    getOptions = function()
        local out = {}
        table.insert(out, {
            key = "all",
            text = "All Seasons",
            searchText = "all",
            isChecked = function() return filters.season == nil end,
        })
        for _, s in ipairs(CollectUniqueSeasons()) do
            local key = tostring(s)
            table.insert(out, {
                key = key,
                text = "Season " .. s,
                searchText = key,
                isChecked = function() return filters.season == s end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if key == "all" then
            filters.season = nil
        else
            local s = tonumber(key)
            if filters.season == s then
                filters.season = nil
            else
                filters.season = s
            end
        end
        RefreshHistory()
    end,
    onClear = function() filters.season = nil; RefreshHistory() end,
    getLabel = function()
        if not filters.season then return "Season: All" end
        return "|cffE8B923Season " .. filters.season .. "|r"
    end,
})
seasonDD.frame:SetPoint("TOPLEFT", 627, -36)

seasonDefault:Register(function(season)
    filters.season = season
    seasonDD:SetLabel("|cffE8B923Season " .. season .. "|r")
end)

---------------------------------------------------------------------------
-- Filter Row 3: free-text search
---------------------------------------------------------------------------
local histSearchBox = CreateFrame("EditBox", "TkHistSearchBox", matchesContainer, "BackdropTemplate")
histSearchBox:SetSize(280, 22)
histSearchBox:SetPoint("TOPLEFT", 12, -62)
histSearchBox:SetFont(lib.FONT_BODY, 11, "")
histSearchBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
histSearchBox:SetAutoFocus(false)
histSearchBox:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeSize = 1,
})
histSearchBox:SetBackdropColor(0, 0, 0, 0.4)
histSearchBox:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
histSearchBox:SetTextInsets(6, 6, 0, 0)

histSearchBox.placeholder = histSearchBox:CreateFontString(nil, "ARTWORK")
histSearchBox.placeholder:SetFont(lib.FONT_BODY, 11, "")
histSearchBox.placeholder:SetPoint("LEFT", 6, 0)
histSearchBox.placeholder:SetText("Search players, class, race, map...")
histSearchBox.placeholder:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

histSearchBox:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    filters.search = text and text:lower() or ""
    self.placeholder:SetShown(filters.search == "")
    if RefreshHistory then RefreshHistory() end
end)
histSearchBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)

-- Reset button (positioned from the right, in row 1)
local resetBtn = CreateFrame("Button", nil, matchesContainer)
resetBtn:SetSize(60, 24)
resetBtn:SetPoint("TOPRIGHT", -16, -10)
do
    local bg = resetBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
    local border = resetBtn:CreateTexture(nil, "ARTWORK")
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])
    local inner = resetBtn:CreateTexture(nil, "ARTWORK", nil, 1)
    inner:SetAllPoints()
    inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
    local label = resetBtn:CreateFontString(nil, "OVERLAY")
    label:SetFont(lib.FONT_BODY, 10, ""); label:SetPoint("CENTER")
    label:SetText("Reset"); label:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    resetBtn:SetScript("OnEnter", function()
        inner:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3], 1)
        label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    resetBtn:SetScript("OnLeave", function()
        inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
        label:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    end)
end

resetBtn:SetScript("OnClick", function()
    filters.friendlyComps = {}
    filters.partners = {}
    filters.enemyComps = {}
    filters.enemyPlayers = {}
    filters.enemyRaces = {}
    filters.maps = {}
    filters.result = nil
    filters.bracket = "All"
    filters.season = currentSeason
    histSearchBox:SetText("")
    friendlyCompDD:SetLabel("Player Comp: All")
    partnerDD:SetLabel("Partner: All")
    enemyCompDD:SetLabel("Enemy Comp: All")
    bracketDD:SetLabel("Bracket: All")
    enemyPlayerDD:SetLabel("Enemy Players: All")
    enemyRaceDD:SetLabel("Race: All")
    resultDD:SetLabel("Result: All")
    mapDD:SetLabel("Map: All")
    seasonDD:SetLabel("|cffE8B923Season " .. currentSeason .. "|r")
    RefreshHistory()
end)

-- Sync nudge: games recorded this session live only in memory until a
-- /reload or logout writes SavedVariables — remind before web-app upload.
-- Lives in filter row 3 (right of the search box), the only row with room.
local syncNudge = CreateFrame("Button", nil, matchesContainer)
syncNudge:SetHeight(22)
syncNudge:SetPoint("TOPRIGHT", -16, -62)
syncNudge:Hide()
do
    local bg = syncNudge:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
    local border = syncNudge:CreateTexture(nil, "ARTWORK")
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    local inner = syncNudge:CreateTexture(nil, "ARTWORK", nil, 1)
    inner:SetAllPoints()
    inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
    local label = syncNudge:CreateFontString(nil, "OVERLAY")
    label:SetFont(lib.FONT_BODY, 10, ""); label:SetPoint("CENTER")
    label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    syncNudge.label = label
    syncNudge:SetScript("OnEnter", function(self)
        inner:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Save to disk")
        GameTooltip:AddLine("Games from this session are only in memory until the UI"
            .. " reloads. Click to reload now so the web app can upload them.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    syncNudge:SetScript("OnLeave", function()
        inner:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], 1)
        GameTooltip:Hide()
    end)
    syncNudge:SetScript("OnClick", function()
        if InCombatLockdown() then
            print("|cffE8B923" .. DISPLAY_NAME .. ":|r Can't reload during combat.")
            return
        end
        if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
    end)
end

UpdateSyncNudge = function()
    if unsyncedGames > 0 then
        syncNudge.label:SetText(unsyncedGames .. " unsaved game" ..
            (unsyncedGames == 1 and "" or "s") .. " — Reload to sync")
        syncNudge:SetWidth(syncNudge.label:GetStringWidth() + 20)
        syncNudge:Show()
    else
        syncNudge:Hide()
    end
end

-- Show the Reset button only when at least one filter differs from the default
-- (default = no comp/partner/etc. filters, and the current season).
local function UpdateResetButton()
    local active =
        next(filters.friendlyComps) or next(filters.partners) or
        next(filters.enemyComps) or next(filters.enemyPlayers) or
        next(filters.enemyRaces) or next(filters.maps) or
        filters.result ~= nil or filters.bracket ~= "All" or
        filters.season ~= currentSeason or filters.search ~= ""
    resetBtn:SetShown(active and true or false)
end
UpdateResetButton()

-- Column headers
local headerY = -92
local headers = {
    { text = "#",        x = 4,   w = 18, justify = "RIGHT" },
    { text = "Result",   x = 24,  w = 28, justify = "LEFT" },
    { text = "Friendly", x = 54,  w = 146, justify = "LEFT" },
    { text = "",         x = 200, w = 12, justify = "CENTER" },  -- vs column (no header)
    { text = "Enemy",    x = 214, w = 146, justify = "LEFT" },
    { text = "Rating",   x = 362, w = 76, justify = "CENTER" },
    { text = "MMR",      x = 440, w = 92, justify = "CENTER" },
    { text = "Dur",      x = 534, w = 28, justify = "LEFT" },
    { text = "Time",     x = 562, w = 86, justify = "RIGHT" },
    { text = "Map",      x = 650, w = 30, justify = "CENTER" },
    { text = "",         x = 686, w = 50, justify = "CENTER" },
}
for _, h in ipairs(headers) do
    if h.text ~= "" then
        local fs = matchesContainer:CreateFontString(nil, "OVERLAY")
        fs:SetFont(lib.FONT_BODY, 10, "")
        fs:SetPoint("TOPLEFT", h.x, headerY)
        fs:SetWidth(h.w)
        fs:SetJustifyH(h.justify)
        fs:SetWordWrap(false)
        fs:SetText(h.text)
        fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end
end

-- Thin separator line below headers
local headerSep = matchesContainer:CreateTexture(nil, "ARTWORK")
headerSep:SetHeight(1)
headerSep:SetPoint("TOPLEFT", 4, headerY - 12)
headerSep:SetPoint("TOPRIGHT", -16, headerY - 12)
headerSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

-- Scroll frame
local scrollFrame = CreateFrame("ScrollFrame", nil, matchesContainer, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 10, headerY - 14)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 100)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(740, 1) -- height grows dynamically
scrollFrame:SetScrollChild(content)

---------------------------------------------------------------------------
-- Stats Panel (bottom of history window)
---------------------------------------------------------------------------
local statsSep = matchesContainer:CreateTexture(nil, "ARTWORK")
statsSep:SetHeight(1)
statsSep:SetPoint("BOTTOMLEFT", 8, 90)
statsSep:SetPoint("BOTTOMRIGHT", -16, 90)
statsSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

local bestHeader = matchesContainer:CreateFontString(nil, "OVERLAY")
bestHeader:SetFont(lib.FONT_DISPLAY, 10, "")
bestHeader:SetPoint("BOTTOMLEFT", 14, 72)
bestHeader:SetText("Best Matchups")
bestHeader:SetTextColor(C.statusSuccess[1], C.statusSuccess[2], C.statusSuccess[3])

local worstHeader = matchesContainer:CreateFontString(nil, "OVERLAY")
worstHeader:SetFont(lib.FONT_DISPLAY, 10, "")
worstHeader:SetPoint("BOTTOMLEFT", 380, 72)
worstHeader:SetText("Worst Matchups")
worstHeader:SetTextColor(C.enemyRed[1], C.enemyRed[2], C.enemyRed[3])

local NUM_STAT_ROWS = 5
local STAT_COL_COMP = 0      -- comp name offset from row left
local STAT_COL_RECORD = 175  -- W/L record offset
local STAT_COL_PCT = 235     -- percentage offset
local STAT_COL_BAR = 270     -- win% bar offset
local STAT_BAR_WIDTH = 70    -- max bar width
local STAT_ROW_WIDTH = 350

local function CreateStatRow(parent, x, y)
    local row = {}

    row.comp = parent:CreateFontString(nil, "OVERLAY")
    row.comp:SetFont(lib.FONT_BODY, 10, "")
    row.comp:SetPoint("BOTTOMLEFT", x + STAT_COL_COMP, y)
    row.comp:SetWidth(170)
    row.comp:SetJustifyH("LEFT")
    row.comp:SetWordWrap(false)
    row.comp:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    row.record = parent:CreateFontString(nil, "OVERLAY")
    row.record:SetFont(lib.FONT_BODY, 10, "")
    row.record:SetPoint("BOTTOMLEFT", x + STAT_COL_RECORD, y)
    row.record:SetWidth(55)
    row.record:SetJustifyH("LEFT")
    row.record:SetWordWrap(false)

    row.pct = parent:CreateFontString(nil, "OVERLAY")
    row.pct:SetFont(lib.FONT_BODY, 10, "")
    row.pct:SetPoint("BOTTOMLEFT", x + STAT_COL_PCT, y)
    row.pct:SetWidth(35)
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetWordWrap(false)

    -- Win% bar background (dark)
    row.barBg = parent:CreateTexture(nil, "ARTWORK")
    row.barBg:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x + STAT_COL_BAR, y + 1)
    row.barBg:SetSize(STAT_BAR_WIDTH, 8)
    row.barBg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)

    -- Win% bar fill
    row.barFill = parent:CreateTexture(nil, "OVERLAY")
    row.barFill:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x + STAT_COL_BAR, y + 1)
    row.barFill:SetSize(1, 8)
    row.barFill:SetColorTexture(0, 1, 0, 0.8)

    row.SetData = function(self, entry)
        if not entry then
            self.comp:SetText("")
            self.record:SetText("")
            self.pct:SetText("")
            self.barBg:Hide()
            self.barFill:Hide()
            return
        end
        self.comp:SetText(FormatCompLabel(entry.comp))
        self.record:SetText("|cff00ff00" .. entry.wins .. "W|r |cffff4444" .. entry.losses .. "L|r")
        self.pct:SetText("|cffffffff" .. math.floor(entry.pct + 0.5) .. "%|r")
        self.barBg:Show()
        local fillWidth = math.max(1, STAT_BAR_WIDTH * entry.pct / 100)
        self.barFill:SetWidth(fillWidth)
        -- Color gradient: red at 0%, yellow at 50%, green at 100%
        local r, g
        if entry.pct <= 50 then
            r = 1
            g = entry.pct / 50
        else
            r = 1 - (entry.pct - 50) / 50
            g = 1
        end
        self.barFill:SetColorTexture(r, g, 0, 0.9)
        self.barFill:Show()
    end

    return row
end

local bestRows = {}
local worstRows = {}
for i = 1, NUM_STAT_ROWS do
    local y = 72 - i * 12
    bestRows[i] = CreateStatRow(matchesContainer, 14, y)
    worstRows[i] = CreateStatRow(matchesContainer, 380, y)
end

local function RefreshStats(filteredList)
    -- Tally wins/losses per enemy comp from the filtered list
    local compStats = {} -- compKey → { wins, losses }
    for _, entry in ipairs(filteredList) do
        local comp = GetCompKey(entry.game.enemyTeam)
        if not comp and entry.game.enemyComp and #entry.game.enemyComp > 0 then
            local sorted = {}
            for _, c in ipairs(entry.game.enemyComp) do table.insert(sorted, c) end
            table.sort(sorted)
            comp = table.concat(sorted, "/")
        end
        if comp then
            if not compStats[comp] then compStats[comp] = { wins = 0, losses = 0 } end
            if entry.game.result == "WIN" then
                compStats[comp].wins = compStats[comp].wins + 1
            else
                compStats[comp].losses = compStats[comp].losses + 1
            end
        end
    end

    -- Build sorted list (best win% first)
    local compList = {}
    for comp, stats in pairs(compStats) do
        local total = stats.wins + stats.losses
        local winPct = (total > 0) and (stats.wins / total * 100) or 0
        table.insert(compList, { comp = comp, wins = stats.wins, losses = stats.losses, total = total, pct = winPct })
    end
    table.sort(compList, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return a.total > b.total
    end)

    -- Best = top of sorted list, Worst = bottom of sorted list
    local best = {}
    local worst = {}
    for i = 1, math.min(NUM_STAT_ROWS, #compList) do
        best[i] = compList[i]
    end
    for i = 1, math.min(NUM_STAT_ROWS, #compList) do
        worst[i] = compList[#compList - i + 1]
    end

    for i = 1, NUM_STAT_ROWS do
        bestRows[i]:SetData(best[i])
        worstRows[i]:SetData(worst[i])
    end
end

local function FormatDuration(seconds)
    if not seconds or seconds < 0 then return "--:--" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

-- Totals spanning many games, so unlike FormatDuration this has to survive
-- passing an hour: "3h 12m", "47m", "38s".
local function FormatPlayTime(seconds)
    if not seconds or seconds <= 0 then return "|cff555555—|r" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    if m > 0 then return string.format("%dm", m) end
    return string.format("%ds", math.floor(seconds))
end

local function ColorClass(name)
    local color = CLASS_COLORS[name] or "ffffffff"
    return "|c" .. color .. name .. "|r"
end

local function FormatTime(ts)
    if not ts then return "?" end
    return date("%m/%d %I:%M%p", ts):lower()
end

-- Abbreviate race names to keep row text compact
local RACE_SHORT = {
    ["Night Elf"]            = "Nelf",
    ["Blood Elf"]            = "Belf",
}

-- playerName (friendly teams only) pins the recording player to the front;
-- everyone else sorts by class then name. See addon.SortTeam.
local function FormatTeamNames(team, playerName)
    if not team or #team == 0 then return nil end
    local names = {}
    local details = {}
    for _, p in ipairs(addon.SortTeam(team, playerName)) do
        local color = CLASS_COLORS[p.class] or "ffffffff"
        local icon = addon.CompLabels and addon.CompLabels.ClassIcon(p.class, 11) or ""
        table.insert(names, icon .. "|c" .. color .. p.name .. "|r")
        -- Build subtitle: "Spec Race" or fallback to class
        local parts = {}
        if p.spec then table.insert(parts, SPEC_SHORT[p.spec] or p.spec) end
        if p.race then table.insert(parts, RACE_SHORT[p.race] or p.race) end
        if #parts > 0 then
            table.insert(details, table.concat(parts, " "))
        else
            table.insert(details, p.class or "?")
        end
    end
    local line1 = table.concat(names, ", ")
    local line2 = "|cff999999" .. table.concat(details, "  ·  ") .. "|r"
    return line1 .. "\n" .. line2
end

-- Win% colored with a red→yellow→green gradient (returns "|cffRRGG00 NN%|r")
local function FormatWinPct(wins, losses)
    local total = wins + losses
    local pct = (total > 0) and (wins / total * 100) or 0
    local pr, pg
    if pct <= 50 then
        pr, pg = 1, pct / 50
    else
        pr, pg = 1 - (pct - 50) / 50, 1
    end
    return string.format("|cff%02x%02x00%d%%|r",
        math.floor(pr * 255 + 0.5), math.floor(pg * 255 + 0.5), math.floor(pct + 0.5))
end

-- Rating change as "<after> (+<change>)" green/red, or em-dash when absent
local function FormatRatingChange(game)
    if not game.ratingChange then return "|cff555555—|r" end
    local sign = game.ratingChange >= 0 and "+" or ""
    local color = game.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
    if game.ratingAfter then
        return color .. game.ratingAfter .. " (" .. sign .. game.ratingChange .. ")|r"
    end
    return color .. sign .. game.ratingChange .. "|r"
end

-- Player MMR, colored by mmrChange; em-dash when absent.
-- (Opponent MMR is stored in game.enemyMMR but not shown here.)
local function FormatMMR(game)
    if not game.mmrBefore then return "|cff555555—|r" end
    local color = "|cffaaaaaa"
    if game.mmrChange and game.mmrChange ~= 0 then
        color = game.mmrChange > 0 and "|cff00ff00" or "|cffff0000"
    end
    return color .. game.mmrBefore .. "|r"
end

-- Enemy team display: prefer FormatTeamNames, fall back to class-only from enemyComp
local function FormatEnemyTeam(game)
    local enemyStr = FormatTeamNames(game.enemyTeam)
    if enemyStr then return enemyStr end
    local team = {}
    local parts = {}
    for _, class in ipairs(game.enemyComp or {}) do
        table.insert(team, { class = class })
        local icon = addon.CompLabels and addon.CompLabels.ClassIcon(class, 11) or ""
        table.insert(parts, icon .. ColorClass(class))
    end
    if #parts == 0 then return "?" end
    -- Same comp abbreviation the Trinketed app shows for this roster.
    local label = addon.CompLabels and addon.CompLabels.GetLabel(team)
    if label then
        return table.concat(parts, " ") .. "  |cff999999" .. label .. "|r"
    end
    return table.concat(parts, " ")
end

local rowPool = {}
-- Virtualized Matches list: with thousands of games we can't create a frame per
-- game (that's what made scrolling lag). Instead we keep a small pool sized to
-- the viewport and recycle rows as the list scrolls — same approach as the
-- replay combat feed. State/methods live on one table to keep top-level locals down.
-- Share/import feature table. Declared here (before the row factory) so row
-- buttons can reference it at click time; functions live in the "Share /
-- Import" section further down, after the JSON + LibDeflate helpers.
local Share = {}

local historyView = { filtered = nil }

-- ---------------------------------------------------------------------------
-- Open in Trinketed: jump from a match row to the Trinketed app / webapp.
-- Addons cannot open external programs or write the clipboard, so both paths
-- are indirect:
--   * App: write TrinketedHistoryDB.jumpIntent, then reload. The reload
--     flushes SavedVariables; the desktop companion's watcher sees the intent
--     and navigates to the game (consume-once on its side, so the intent
--     lingering in later flushes is harmless).
--   * Web: surface the /goto resolver URL pre-selected for Ctrl+C.
-- jumpIntent is a local coordination key like `minimap`/`settings` — never an
-- ingestion input (backend addon contract, § Export Shape).

local WEB_GOTO_URL = "https://trinketed.com/goto?t=%.3f"

local function OpenGameInApp(game)
    if InCombatLockdown() then
        print("|cffE8B923" .. DISPLAY_NAME .. ":|r Can't reload during combat.")
        return
    end
    TrinketedHistoryDB.jumpIntent = {
        gameId = game.id, -- nil for pre-id games; gameStartTime covers those
        gameStartTime = game.startTime,
        createdAt = time(),
    }
    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Opening in Trinketed — reloading UI.")
    if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end

-- Small flyout under the clicked row. Built once; captures the game table
-- reference at open so pooled-row recycling can't swap it mid-interaction.
local jumpFlyout
local function MakeFlyoutButton(parent, yOff, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(164, 20)
    b:SetPoint("TOPLEFT", 4, yOff)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0)
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetFont(lib.FONT_BODY, 10, "")
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetText(text)
    b.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.25)
        self.label:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0)
        self.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        if not MouseIsOver(jumpFlyout) then jumpFlyout:Hide() end
    end)
    return b
end

local function GetJumpFlyout()
    if jumpFlyout then return jumpFlyout end
    local f = CreateFrame("Frame", "TrinketedHistoryJumpFlyout", UIParent, "BackdropTemplate")
    f:SetSize(172, 70)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    f:SetBackdropColor(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)
    f:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
    tinsert(UISpecialFrames, "TrinketedHistoryJumpFlyout")

    f.appBtn = MakeFlyoutButton(f, -4, "Open in Trinketed app")
    f.appBtn.sub = f.appBtn:CreateFontString(nil, "OVERLAY")
    f.appBtn.sub:SetFont(lib.FONT_BODY, 8, "")
    f.appBtn.sub:SetPoint("RIGHT", -6, 0)
    f.appBtn.sub:SetText("reloads UI")
    f.appBtn.sub:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    f.appBtn:SetScript("OnMouseUp", function()
        f:Hide()
        if f.game then OpenGameInApp(f.game) end
    end)

    f.webBtn = MakeFlyoutButton(f, -24, "Copy web link")
    f.webBtn:SetScript("OnMouseUp", function()
        f:Hide()
        if f.game then
            addon:ShowDevCopyBox("Trinketed web link",
                string.format(WEB_GOTO_URL, f.game.startTime))
        end
    end)

    -- Dev-only third entry (hidden otherwise); preserves the old row-click
    -- game-id copy behavior.
    f.devBtn = MakeFlyoutButton(f, -44, "Copy game id (dev)")
    f.devBtn:SetScript("OnMouseUp", function()
        f:Hide()
        local g = f.game
        if not g then return end
        if not g.id then
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r This game predates per-game ids — nothing to copy.")
            return
        end
        addon:ShowDevCopyBox("Game ID  |cff888888#" .. tostring(f.dbIndex) .. "|r", g.id)
    end)

    f:SetScript("OnLeave", function(self)
        if not MouseIsOver(self) then self:Hide() end
    end)
    f:Hide()
    jumpFlyout = f
    return f
end

local function ShowJumpFlyout(row, game, dbIndex)
    local f = GetJumpFlyout()
    f.game = game
    f.dbIndex = dbIndex
    if addon:IsDevMode() then
        f.devBtn:Show()
        f:SetHeight(70)
    else
        f.devBtn:Hide()
        f:SetHeight(50)
    end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, 0)
    f:Show()
end

-- Create one pooled Matches row. The replay button reads row.game (set by
-- :Populate) rather than capturing a game, so rows recycle correctly on scroll.
function historyView:MakeRow()
    local row = CreateFrame("Button", nil, content)
    row:SetSize(740, ROW_HEIGHT)

    row.index = row:CreateFontString(nil, "OVERLAY")
    row.index:SetFont(lib.FONT_BODY, 10, "")
    row.index:SetPoint("LEFT", 4, 0)
    row.index:SetWidth(18)
    row.index:SetWordWrap(false)
    row.index:SetJustifyH("RIGHT")

    row.result = row:CreateFontString(nil, "OVERLAY")
    row.result:SetFont(lib.FONT_BODY, 10, "")
    row.result:SetPoint("LEFT", 24, 0)
    row.result:SetWidth(28)
    row.result:SetWordWrap(false)

    row.friendly = row:CreateFontString(nil, "OVERLAY")
    row.friendly:SetFont(lib.FONT_BODY, 10, "")
    row.friendly:SetPoint("LEFT", 54, 0)
    row.friendly:SetWidth(146)
    row.friendly:SetJustifyH("LEFT")
    row.friendly:SetMaxLines(2)
    row.friendly:SetNonSpaceWrap(false)
    row.friendly:SetWordWrap(true)

    row.vs = row:CreateFontString(nil, "OVERLAY")
    row.vs:SetFont(lib.FONT_BODY, 10, "")
    row.vs:SetPoint("LEFT", 200, 0)
    row.vs:SetWidth(12)
    row.vs:SetWordWrap(false)
    row.vs:SetJustifyH("CENTER")
    row.vs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

    row.enemy = row:CreateFontString(nil, "OVERLAY")
    row.enemy:SetFont(lib.FONT_BODY, 10, "")
    row.enemy:SetPoint("LEFT", 214, 0)
    row.enemy:SetWidth(146)
    row.enemy:SetJustifyH("LEFT")
    row.enemy:SetMaxLines(2)
    row.enemy:SetNonSpaceWrap(false)
    row.enemy:SetWordWrap(true)

    row.rating = row:CreateFontString(nil, "OVERLAY")
    row.rating:SetFont(lib.FONT_BODY, 10, "")
    row.rating:SetPoint("LEFT", 362, 0)
    row.rating:SetWidth(76)
    row.rating:SetWordWrap(false)
    row.rating:SetJustifyH("CENTER")

    row.mmr = row:CreateFontString(nil, "OVERLAY")
    row.mmr:SetFont(lib.FONT_BODY, 10, "")
    row.mmr:SetPoint("LEFT", 440, 0)
    row.mmr:SetWidth(92)
    row.mmr:SetJustifyH("CENTER")
    row.mmr:SetWordWrap(false)

    row.duration = row:CreateFontString(nil, "OVERLAY")
    row.duration:SetFont(lib.FONT_BODY, 10, "")
    row.duration:SetPoint("LEFT", 534, 0)
    row.duration:SetWidth(28)
    row.duration:SetWordWrap(false)
    row.duration:SetJustifyH("CENTER")

    row.timeStr = row:CreateFontString(nil, "OVERLAY")
    row.timeStr:SetFont(lib.FONT_BODY, 10, "")
    row.timeStr:SetPoint("LEFT", 562, 0)
    row.timeStr:SetWidth(86)
    row.timeStr:SetWordWrap(false)
    row.timeStr:SetJustifyH("RIGHT")

    row.mapStr = row:CreateFontString(nil, "OVERLAY")
    row.mapStr:SetFont(lib.FONT_BODY, 10, "")
    row.mapStr:SetPoint("LEFT", 650, 0)
    row.mapStr:SetWidth(30)
    row.mapStr:SetWordWrap(false)
    row.mapStr:SetJustifyH("CENTER")
    row.mapStr:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- Replay + Share stack in the 50px action column (686-736), splitting the
    -- 34px row height. Both read row.game (set by :Populate) so rows recycle.
    row.replayBtn = CreateFrame("Button", nil, row)
    row.replayBtn:SetSize(50, 15)
    row.replayBtn:SetPoint("LEFT", 686, 8)
    row.replayBtn.bg = row.replayBtn:CreateTexture(nil, "BACKGROUND")
    row.replayBtn.bg:SetAllPoints()
    row.replayBtn.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
    row.replayBtn.bdr = row.replayBtn:CreateTexture(nil, "BORDER")
    row.replayBtn.bdr:SetPoint("TOPLEFT"); row.replayBtn.bdr:SetPoint("BOTTOMRIGHT")
    row.replayBtn.bdr:SetColorTexture(0, 0, 0, 0)
    row.replayBtn.icon = row.replayBtn:CreateFontString(nil, "OVERLAY")
    row.replayBtn.icon:SetFont(lib.FONT_BODY, 9, "")
    row.replayBtn.icon:SetPoint("CENTER")
    row.replayBtn.icon:SetText("Replay >")
    row.replayBtn.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    row.replayBtn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        self.icon:SetTextColor(1, 1, 1)
    end)
    row.replayBtn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
        self.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    row.replayBtn:SetScript("OnClick", function()
        if row.game and row.game.eventLog then
            lib:HideOptionsPanel()
            addon:OpenReplay(row.game)
        end
    end)

    row.shareBtn = CreateFrame("Button", nil, row)
    row.shareBtn:SetSize(50, 15)
    row.shareBtn:SetPoint("LEFT", 686, -8)
    row.shareBtn.bg = row.shareBtn:CreateTexture(nil, "BACKGROUND")
    row.shareBtn.bg:SetAllPoints()
    row.shareBtn.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
    row.shareBtn.icon = row.shareBtn:CreateFontString(nil, "OVERLAY")
    row.shareBtn.icon:SetFont(lib.FONT_BODY, 9, "")
    row.shareBtn.icon:SetPoint("CENTER")
    row.shareBtn.icon:SetText("Share")
    row.shareBtn.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    row.shareBtn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        self.icon:SetTextColor(1, 1, 1)
    end)
    row.shareBtn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
        self.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    row.shareBtn:SetScript("OnClick", function()
        if row.game and row.game.eventLog then
            Share.ShowExport(row.game)
        end
    end)

    -- Alternating background
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    -- Hover highlight
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])

    -- Hover: dev mode shows record metadata; everyone gets the click hint.
    row:SetScript("OnEnter", function(self)
        if not self.game then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if addon:IsDevMode() then
            local g = self.game
            GameTooltip:AddLine("Dev — game record", C.accent[1], C.accent[2], C.accent[3])
            GameTooltip:AddDoubleLine("id", g.id or "(none — pre-id game)", 0.55, 0.55, 0.55, 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine("db index", tostring(self.dbIndex), 0.55, 0.55, 0.55, 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine("eventLog", g.eventLog and (#g.eventLog .. " chars") or "(none)", 0.55, 0.55, 0.55, 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine("startTime", tostring(g.startTime), 0.55, 0.55, 0.55, 0.9, 0.9, 0.9)
            if g.serverStartTime then
                GameTooltip:AddDoubleLine("serverStartTime", tostring(g.serverStartTime), 0.55, 0.55, 0.55, 0.9, 0.9, 0.9)
            end
        end
        GameTooltip:AddLine("Click — open in Trinketed", 0.55, 0.55, 0.55)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- OnMouseUp rather than OnClick: it fires on any mouse-enabled frame
    -- with no click-registration involved, so pooled rows can't miss it.
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if not self.game then return end
        ShowJumpFlyout(self, self.game, self.dbIndex)
    end)

    return row
end

-- Fill a pooled row with one game's data (i = original DB index, for the # label).
function historyView:Populate(row, i, game)
    row.game = game
    row.dbIndex = i  -- for the dev-mode tooltip/copy box

    row.index:SetText("#" .. i)
    row.index:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    if game.result == "WIN" then
        row.result:SetText("|cff00ff00WIN|r")
    else
        row.result:SetText("|cffff0000LOSS|r")
    end

    -- Friendly team — show class-colored names
    local friendlyStr = FormatTeamNames(game.friendlyTeam, game.playerName)
    row.friendly:SetText(friendlyStr or "—")

    row.vs:SetText("vs")

    row.enemy:SetText(FormatEnemyTeam(game))
    row.rating:SetText(FormatRatingChange(game))
    row.mmr:SetText(FormatMMR(game))
    -- Shrink-to-fit the fixed-width numeric columns; glyph widths vary by
    -- the viewer's physical resolution, so these can clip on low-DPI
    -- screens that render small fonts slightly wider.
    lib:FitText(row.rating)
    lib:FitText(row.mmr)

    local dur = (game.startTime and game.endTime) and (game.endTime - game.startTime) or nil
    row.duration:SetText(FormatDuration(dur))
    row.duration:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    row.timeStr:SetText(FormatTime(game.startTime))
    row.mapStr:SetText(AbbrevMap(game.map))
    row.timeStr:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    lib:FitText(row.timeStr)

    if game.eventLog then
        row.replayBtn:Show()
        row.shareBtn:Show()
    else
        row.replayBtn:Hide()
        row.shareBtn:Hide()
    end
end

-- Render only the rows visible in the scroll viewport, recycling the pool.
function historyView:Render()
    local filtered = self.filtered
    if not filtered then return end
    local viewH = scrollFrame:GetHeight()
    if not viewH or viewH <= 0 then viewH = 360 end
    local scroll = scrollFrame:GetVerticalScroll() or 0
    local poolNeeded = math.ceil(viewH / ROW_HEIGHT) + 2
    local first = math.max(1, math.floor(scroll / ROW_HEIGHT) + 1)

    for slot = 1, poolNeeded do
        local displayIdx = first + slot - 1
        local entry = filtered[displayIdx]
        local row = rowPool[slot]
        if entry then
            if not row then
                row = self:MakeRow()
                rowPool[slot] = row
            end
            row:SetPoint("TOPLEFT", 0, -((displayIdx - 1) * ROW_HEIGHT))
            if displayIdx % 2 == 0 then
                row.bg:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
            else
                row.bg:SetColorTexture(0, 0, 0, 0)
            end
            self:Populate(row, entry.idx, entry.game)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
end

-- Re-render the window whenever the user scrolls the Matches list.
scrollFrame:HookScript("OnVerticalScroll", function() historyView:Render() end)

function RefreshHistory()
    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}

    -- Apply filters — build list of {originalIndex, game} pairs, newest first
    local filtered = {}
    for i = #allGames, 1, -1 do
        if GameMatchesFilters(allGames[i]) then
            table.insert(filtered, { idx = i, game = allGames[i] })
        end
    end
    historyView.filtered = filtered

    -- Size the scroll child to the full filtered list; only the viewport rows
    -- are realized as frames.
    content:SetHeight(math.max(#filtered * ROW_HEIGHT, 1))
    scrollFrame:SetVerticalScroll(0)
    historyView:Render()

    RefreshStats(filtered)
    UpdateResetButton()
end

---------------------------------------------------------------------------
-- Sessions Tab Content
---------------------------------------------------------------------------
do  -- wrap section: keeps its locals out of the main chunk's 200-local budget
local sessionFilters = {
    bracket = "All",
    days = 0,
    partners = {},  -- table of name = true for selected partners (empty = all)
    maps = {},      -- table of map name = true for selected arenas (empty = all)
    season = currentSeason,
}

local sessionBracketDD = CreateSearchableDropdown(sessionsContainer, "TkSBracketDD", 120, {
    defaultLabel = "Bracket: All",
    getOptions = function()
        local out = {}
        local brackets = { "2v2", "3v3", "5v5" }
        for _, b in ipairs(brackets) do
            table.insert(out, {
                key = b,
                text = b,
                searchText = b:lower(),
                isChecked = function() return sessionFilters.bracket == b end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if sessionFilters.bracket == key then
            sessionFilters.bracket = "All"
        else
            sessionFilters.bracket = key
        end
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function()
        sessionFilters.bracket = "All"
        if RefreshSessions then RefreshSessions() end
    end,
    getLabel = function()
        if sessionFilters.bracket == "All" then return "Bracket: All" end
        return "Bracket: " .. sessionFilters.bracket
    end,
})
sessionBracketDD.frame:SetPoint("TOPLEFT", sessionsContainer, "TOPLEFT", 12, -10)

local sessionDaysDD = CreateSearchableDropdown(sessionsContainer, "TkSDaysDD", 120, {
    defaultLabel = "Time: All",
    getOptions = function()
        local out = {}
        local dayOpts = {
            { key = "7",  text = "Last 7 Days" },
            { key = "30", text = "Last 30 Days" },
            { key = "90", text = "Last 90 Days" },
        }
        for _, d in ipairs(dayOpts) do
            table.insert(out, {
                key = d.key,
                text = d.text,
                searchText = d.text:lower(),
                isChecked = function() return sessionFilters.days == tonumber(d.key) end,
            })
        end
        return out
    end,
    onToggle = function(key)
        local val = tonumber(key)
        if sessionFilters.days == val then
            sessionFilters.days = 0
        else
            sessionFilters.days = val
        end
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function()
        sessionFilters.days = 0
        if RefreshSessions then RefreshSessions() end
    end,
    getLabel = function()
        if sessionFilters.days == 0 then return "Time: All" end
        return "Last " .. sessionFilters.days .. " Days"
    end,
})
sessionDaysDD.frame:SetPoint("LEFT", sessionBracketDD.frame, "RIGHT", 10, 0)

local sessionPartnerDD = CreateSearchableDropdown(sessionsContainer, "TkSPartnerDD", 155, {
    defaultLabel = "Partner: All",
    getOptions = function()
        local playerName = UnitName("player")
        local out = {}
        local seen = {}
        for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
            for _, p in ipairs(game.friendlyTeam or {}) do
                if p.name ~= playerName and not seen[p.name] then
                    local color = CLASS_COLORS[p.class] or "ffffffff"
                    table.insert(out, {
                        key = p.name,
                        text = "|c" .. color .. p.name .. "|r",
                        searchText = p.name:lower(),
                        isChecked = function() return sessionFilters.partners[p.name] == true end,
                    })
                    seen[p.name] = true
                end
            end
        end
        table.sort(out, function(a, b) return a.key < b.key end)
        return out
    end,
    onToggle = function(key)
        if sessionFilters.partners[key] then sessionFilters.partners[key] = nil else sessionFilters.partners[key] = true end
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function() sessionFilters.partners = {}; if RefreshSessions then RefreshSessions() end end,
    getLabel = function()
        if not next(sessionFilters.partners) then return "Partner: All" end
        local t = {}; for n in pairs(sessionFilters.partners) do table.insert(t, n) end
        return "Partner: " .. table.concat(t, ", ")
    end,
})
sessionPartnerDD.frame:SetPoint("LEFT", sessionDaysDD.frame, "RIGHT", 10, 0)

local sessionMapDD = CreateSearchableDropdown(sessionsContainer, "TkSMapDD", 120, {
    defaultLabel = "Map: All",
    getOptions = function()
        local out = {}
        local maps = { "Nagrand Arena", "Blade's Edge Arena", "Ruins of Lordaeron" }
        for _, m in ipairs(maps) do
            table.insert(out, {
                key = m,
                text = AbbrevMap(m) .. "  |cff888888" .. m .. "|r",
                searchText = (m .. " " .. AbbrevMap(m)):lower(),
                isChecked = function() return sessionFilters.maps[m] == true end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if sessionFilters.maps[key] then sessionFilters.maps[key] = nil else sessionFilters.maps[key] = true end
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function() sessionFilters.maps = {}; if RefreshSessions then RefreshSessions() end end,
    getLabel = function()
        if not next(sessionFilters.maps) then return "Map: All" end
        local t = {}; for m in pairs(sessionFilters.maps) do table.insert(t, AbbrevMap(m)) end
        return "Map: " .. table.concat(t, ", ")
    end,
})
sessionMapDD.frame:SetPoint("LEFT", sessionPartnerDD.frame, "RIGHT", 10, 0)

do
    local sessionSeasonDD = CreateSearchableDropdown(sessionsContainer, "TkSSeasonDD", 120, {
        defaultLabel = "|cffE8B923Season " .. currentSeason .. "|r",
        autoClose = true,
        getOptions = function()
            local out = {}
            table.insert(out, {
                key = "all",
                text = "All Seasons",
                searchText = "all",
                isChecked = function() return sessionFilters.season == nil end,
            })
            for _, s in ipairs(CollectUniqueSeasons()) do
                local key = tostring(s)
                table.insert(out, {
                    key = key,
                    text = "Season " .. s,
                    searchText = key,
                    isChecked = function() return sessionFilters.season == s end,
                })
            end
            return out
        end,
        onToggle = function(key)
            if key == "all" then
                sessionFilters.season = nil
            else
                local s = tonumber(key)
                if sessionFilters.season == s then
                    sessionFilters.season = nil
                else
                    sessionFilters.season = s
                end
            end
            if RefreshSessions then RefreshSessions() end
        end,
        onClear = function() sessionFilters.season = nil; if RefreshSessions then RefreshSessions() end end,
        getLabel = function()
            if not sessionFilters.season then return "Season: All" end
            return "|cffE8B923Season " .. sessionFilters.season .. "|r"
        end,
    })
    sessionSeasonDD.frame:SetPoint("LEFT", sessionMapDD.frame, "RIGHT", 10, 0)

    seasonDefault:Register(function(season)
        sessionFilters.season = season
        sessionSeasonDD:SetLabel("|cffE8B923Season " .. season .. "|r")
    end)
end

-- Session column headers
local sessionHeaderY = -40
-- Column x/w must stay in sync with the row FontStrings below. The Time
-- column's space came from trimming columns that were budgeted well above
-- their longest real value ("08/05 14:32", "1500 -> 1550"); the row still
-- ends at 726 inside the 740-wide scroll child.
local sessionHeaders = {
    { text = "#",        x = 4,   w = 22,  justify = "RIGHT" },
    { text = "Date",     x = 28,  w = 76,  justify = "LEFT" },
    { text = "Partners", x = 106, w = 130, justify = "LEFT" },
    { text = "Bracket",  x = 238, w = 44,  justify = "CENTER" },
    { text = "Games",    x = 284, w = 34,  justify = "CENTER" },
    { text = "Time",     x = 320, w = 52,  justify = "CENTER" },
    { text = "W-L",      x = 374, w = 46,  justify = "CENTER" },
    { text = "Win%",     x = 422, w = 42,  justify = "CENTER" },
    { text = "Rating",   x = 466, w = 94,  justify = "CENTER" },
    { text = "MMR",      x = 562, w = 94,  justify = "CENTER" },
    { text = "Net",      x = 658, w = 42,  justify = "CENTER" },
    { text = "",         x = 702, w = 24,  justify = "CENTER" },
}
for _, h in ipairs(sessionHeaders) do
    if h.text ~= "" then
        local fs = sessionsContainer:CreateFontString(nil, "OVERLAY")
        fs:SetFont(lib.FONT_BODY, 10, "")
        fs:SetPoint("TOPLEFT", h.x, sessionHeaderY)
        fs:SetWidth(h.w)
        fs:SetJustifyH(h.justify)
        fs:SetWordWrap(false)
        fs:SetText(h.text)
        fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end
end

-- Thin separator line below session headers
local sessHeaderSep = sessionsContainer:CreateTexture(nil, "ARTWORK")
sessHeaderSep:SetHeight(1)
sessHeaderSep:SetPoint("TOPLEFT", 4, sessionHeaderY - 12)
sessHeaderSep:SetPoint("TOPRIGHT", -16, sessionHeaderY - 12)
sessHeaderSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

-- Sessions scroll frame
local sessScrollFrame = CreateFrame("ScrollFrame", nil, sessionsContainer, "UIPanelScrollFrameTemplate")
sessScrollFrame:SetPoint("TOPLEFT", 10, sessionHeaderY - 14)
sessScrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local sessContent = CreateFrame("Frame", nil, sessScrollFrame)
sessContent:SetSize(740, 1)
sessScrollFrame:SetScrollChild(sessContent)

local SESSION_ROW_HEIGHT = 28
local MATCH_ROW_HEIGHT = 26
local sessionRowPool = {}   -- session summary rows
local matchDrillPool = {}   -- match drill-down rows
local expandedSession = nil -- stores startTime of expanded session for stable identity

---------------------------------------------------------------------------
-- RefreshSessions
---------------------------------------------------------------------------
function RefreshSessions()
    -- Recycle existing rows
    for _, row in ipairs(sessionRowPool) do
        row:Hide()
    end
    for _, row in ipairs(matchDrillPool) do
        row:Hide()
    end

    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}

    -- Build filter args
    local bracketFilter = sessionFilters.bracket ~= "All" and sessionFilters.bracket or nil
    local daysFilter = sessionFilters.days

    local sessions = ComputeSessions(allGames, bracketFilter, daysFilter, sessionFilters.maps, sessionFilters.season)

    -- Filter by partner if any selected
    if next(sessionFilters.partners) then
        local filtered = {}
        for _, s in ipairs(sessions) do
            for _, p in ipairs(s.partners) do
                if sessionFilters.partners[p.name] then
                    table.insert(filtered, s)
                    break
                end
            end
        end
        sessions = filtered
    end

    local totalHeight = 0
    local rowIdx = 0
    local matchRowIdx = 0
    local totalGames = 0
    local totalWins = 0
    local totalLosses = 0
    local totalNetRating = 0
    local hasRating = false

    -- Render sessions newest-first
    local displayNum = 0
    for si = #sessions, 1, -1 do
        displayNum = displayNum + 1
        local s = sessions[si]
        rowIdx = rowIdx + 1

        totalGames = totalGames + #s.games
        totalWins = totalWins + s.wins
        totalLosses = totalLosses + s.losses
        totalNetRating = totalNetRating + s.ratingChange
        if s.ratingStart or s.ratingEnd then hasRating = true end

        -- Create or reuse session row (Button for clickability)
        local row = sessionRowPool[rowIdx]
        if not row then
            row = CreateFrame("Button", nil, sessContent)
            row:SetSize(740, SESSION_ROW_HEIGHT)
            sessionRowPool[rowIdx] = row

            row.index = row:CreateFontString(nil, "OVERLAY")
            row.index:SetFont(lib.FONT_BODY, 10, "")
            row.index:SetPoint("LEFT", 4, 0)
            row.index:SetWidth(22)
            row.index:SetWordWrap(false)
            row.index:SetJustifyH("RIGHT")

            row.dateStr = row:CreateFontString(nil, "OVERLAY")
            row.dateStr:SetFont(lib.FONT_BODY, 10, "")
            row.dateStr:SetPoint("LEFT", 28, 0)
            row.dateStr:SetWidth(76)
            row.dateStr:SetJustifyH("LEFT")
            row.dateStr:SetWordWrap(false)

            row.partners = row:CreateFontString(nil, "OVERLAY")
            row.partners:SetFont(lib.FONT_BODY, 10, "")
            row.partners:SetPoint("LEFT", 106, 0)
            row.partners:SetWidth(130)
            row.partners:SetJustifyH("LEFT")
            row.partners:SetWordWrap(false)

            row.bracket = row:CreateFontString(nil, "OVERLAY")
            row.bracket:SetFont(lib.FONT_BODY, 10, "")
            row.bracket:SetPoint("LEFT", 238, 0)
            row.bracket:SetWidth(44)
            row.bracket:SetWordWrap(false)
            row.bracket:SetJustifyH("CENTER")

            row.games = row:CreateFontString(nil, "OVERLAY")
            row.games:SetFont(lib.FONT_BODY, 10, "")
            row.games:SetPoint("LEFT", 284, 0)
            row.games:SetWidth(34)
            row.games:SetWordWrap(false)
            row.games:SetJustifyH("CENTER")

            row.playTime = row:CreateFontString(nil, "OVERLAY")
            row.playTime:SetFont(lib.FONT_BODY, 10, "")
            row.playTime:SetPoint("LEFT", 320, 0)
            row.playTime:SetWidth(52)
            row.playTime:SetWordWrap(false)
            row.playTime:SetJustifyH("CENTER")

            row.wl = row:CreateFontString(nil, "OVERLAY")
            row.wl:SetFont(lib.FONT_BODY, 10, "")
            row.wl:SetPoint("LEFT", 374, 0)
            row.wl:SetWidth(46)
            row.wl:SetWordWrap(false)
            row.wl:SetJustifyH("CENTER")

            row.winPct = row:CreateFontString(nil, "OVERLAY")
            row.winPct:SetFont(lib.FONT_BODY, 10, "")
            row.winPct:SetPoint("LEFT", 422, 0)
            row.winPct:SetWidth(42)
            row.winPct:SetWordWrap(false)
            row.winPct:SetJustifyH("CENTER")

            row.rating = row:CreateFontString(nil, "OVERLAY")
            row.rating:SetFont(lib.FONT_BODY, 10, "")
            row.rating:SetPoint("LEFT", 466, 0)
            row.rating:SetWidth(94)
            row.rating:SetJustifyH("CENTER")
            row.rating:SetWordWrap(false)

            row.mmr = row:CreateFontString(nil, "OVERLAY")
            row.mmr:SetFont(lib.FONT_BODY, 10, "")
            row.mmr:SetPoint("LEFT", 562, 0)
            row.mmr:SetWidth(94)
            row.mmr:SetJustifyH("CENTER")
            row.mmr:SetWordWrap(false)

            row.net = row:CreateFontString(nil, "OVERLAY")
            row.net:SetFont(lib.FONT_BODY, 10, "")
            row.net:SetPoint("LEFT", 658, 0)
            row.net:SetWidth(42)
            row.net:SetWordWrap(false)
            row.net:SetJustifyH("CENTER")

            row.expandIndicator = row:CreateFontString(nil, "OVERLAY")
            row.expandIndicator:SetFont(lib.FONT_BODY, 10, "")
            row.expandIndicator:SetPoint("LEFT", 702, 0)
            row.expandIndicator:SetWidth(24)
            row.expandIndicator:SetWordWrap(false)
            row.expandIndicator:SetJustifyH("CENTER")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            -- Highlight on hover
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])

            row:SetScript("OnEnter", function()
                row.expandIndicator:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            end)
            row:SetScript("OnLeave", function()
                row.expandIndicator:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end)
        end

        row:SetPoint("TOPLEFT", 0, -totalHeight)

        -- Alternating row color
        if displayNum % 2 == 0 then
            row.bg:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.index:SetText("#" .. displayNum)
        row.index:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        row.dateStr:SetText(date("%m/%d %H:%M", s.startTime))
        row.dateStr:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

        -- Partners: class-colored names joined by ", " or "Solo"
        if s.partners and #s.partners > 0 then
            local pParts = {}
            for _, p in ipairs(s.partners) do
                local color = CLASS_COLORS[p.class] or "ffffffff"
                table.insert(pParts, "|c" .. color .. p.name .. "|r")
            end
            row.partners:SetText(table.concat(pParts, ", "))
        else
            row.partners:SetText("|cff888888Solo|r")
        end

        row.bracket:SetText(s.bracket or "?")
        row.bracket:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

        row.games:SetText(#s.games)
        row.games:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

        -- Total time in arena across the session's games
        row.playTime:SetText(FormatPlayTime(s.playTime))
        row.playTime:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
        lib:FitText(row.playTime)

        row.wl:SetText("|cff00ff00" .. s.wins .. "|r-|cffff0000" .. s.losses .. "|r")
        row.winPct:SetText(FormatWinPct(s.wins, s.losses))

        -- Rating: startRating -> endRating
        if s.ratingStart and s.ratingEnd then
            row.rating:SetText("|cffcccccc" .. s.ratingStart .. " -> " .. s.ratingEnd .. "|r")
        else
            row.rating:SetText("|cff555555—|r")
        end

        -- MMR: startMMR -> endMMR
        if s.mmrStart and s.mmrEnd then
            row.mmr:SetText("|cffaaaaaa" .. s.mmrStart .. " -> " .. s.mmrEnd .. "|r")
        else
            row.mmr:SetText("|cff555555—|r")
        end

        -- Net rating change
        if s.ratingChange and s.ratingChange ~= 0 then
            local sign = s.ratingChange >= 0 and "+" or ""
            local netColor = s.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
            row.net:SetText(netColor .. sign .. s.ratingChange .. "|r")
        elseif s.ratingStart or s.ratingEnd then
            row.net:SetText("|cff888888" .. "0" .. "|r")
        else
            row.net:SetText("|cff555555—|r")
        end

        -- Expand indicator
        local isExpanded = (expandedSession == s.startTime)
        row.expandIndicator:SetText(isExpanded and "v" or ">")
        row.expandIndicator:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        -- OnClick: toggle drill-down (use startTime as stable identity)
        local capturedStartTime = s.startTime
        row:SetScript("OnClick", function()
            if expandedSession == capturedStartTime then
                expandedSession = nil
            else
                expandedSession = capturedStartTime
            end
            RefreshSessions()
        end)

        row:Show()
        totalHeight = totalHeight + SESSION_ROW_HEIGHT

        -- Drill-down: render column header + individual games if expanded
        -- Uses the exact same layout as the Matches tab
        if isExpanded then
            -- Column header row for drill-down
            matchRowIdx = matchRowIdx + 1
            local hrow = matchDrillPool[matchRowIdx]
            if not hrow then
                hrow = CreateFrame("Frame", nil, sessContent)
                hrow:SetSize(740, 16)
                matchDrillPool[matchRowIdx] = hrow
                hrow.bg = hrow:CreateTexture(nil, "BACKGROUND")
                hrow.bg:SetAllPoints()
            end
            hrow:SetPoint("TOPLEFT", 0, -totalHeight)
            hrow.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.9)
            if not hrow.isHeader then
                hrow.isHeader = true
                local drillHeaders = {
                    { text = "Result",   x = 24,  w = 28,  justify = "LEFT" },
                    { text = "Friendly", x = 54,  w = 146, justify = "LEFT" },
                    { text = "",         x = 200, w = 12,  justify = "CENTER" },
                    { text = "Enemy",    x = 214, w = 146, justify = "LEFT" },
                    { text = "Rating",   x = 362, w = 76,  justify = "CENTER" },
                    { text = "MMR",      x = 440, w = 92,  justify = "CENTER" },
                    { text = "Dur",      x = 534, w = 28,  justify = "LEFT" },
                    { text = "Time",     x = 562, w = 86,  justify = "RIGHT" },
                    { text = "Map",      x = 650, w = 30,  justify = "CENTER" },
                }
                for _, dh in ipairs(drillHeaders) do
                    if dh.text ~= "" then
                        local fs = hrow:CreateFontString(nil, "OVERLAY")
                        fs:SetFont(lib.FONT_BODY, 10, "")
                        fs:SetPoint("LEFT", dh.x, 0)
                        fs:SetWidth(dh.w)
                        fs:SetWordWrap(false)
                        fs:SetJustifyH(dh.justify)
                        fs:SetText(dh.text)
                        fs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
                    end
                end
            end
            hrow:Show()
            totalHeight = totalHeight + 16

            for gi, game in ipairs(s.games) do
                matchRowIdx = matchRowIdx + 1
                local mrow = matchDrillPool[matchRowIdx]
                if not mrow then
                    mrow = CreateFrame("Button", nil, sessContent)
                    mrow:SetSize(740, ROW_HEIGHT)
                    matchDrillPool[matchRowIdx] = mrow

                    mrow.result = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.result:SetFont(lib.FONT_BODY, 10, "")
                    mrow.result:SetPoint("LEFT", 24, 0)
                    mrow.result:SetWidth(28)
                    mrow.result:SetWordWrap(false)

                    mrow.friendly = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.friendly:SetFont(lib.FONT_BODY, 10, "")
                    mrow.friendly:SetPoint("LEFT", 54, 0)
                    mrow.friendly:SetWidth(146)
                    mrow.friendly:SetJustifyH("LEFT")
                    mrow.friendly:SetMaxLines(2)
                    mrow.friendly:SetNonSpaceWrap(false)
                    mrow.friendly:SetWordWrap(true)

                    mrow.vs = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.vs:SetFont(lib.FONT_BODY, 10, "")
                    mrow.vs:SetPoint("LEFT", 200, 0)
                    mrow.vs:SetWidth(12)
                    mrow.vs:SetWordWrap(false)
                    mrow.vs:SetJustifyH("CENTER")
                    mrow.vs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

                    mrow.enemy = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.enemy:SetFont(lib.FONT_BODY, 10, "")
                    mrow.enemy:SetPoint("LEFT", 214, 0)
                    mrow.enemy:SetWidth(146)
                    mrow.enemy:SetJustifyH("LEFT")
                    mrow.enemy:SetMaxLines(2)
                    mrow.enemy:SetNonSpaceWrap(false)
                    mrow.enemy:SetWordWrap(true)

                    mrow.rating = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.rating:SetFont(lib.FONT_BODY, 10, "")
                    mrow.rating:SetPoint("LEFT", 362, 0)
                    mrow.rating:SetWidth(76)
                    mrow.rating:SetWordWrap(false)
                    mrow.rating:SetJustifyH("CENTER")

                    mrow.mmr = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.mmr:SetFont(lib.FONT_BODY, 10, "")
                    mrow.mmr:SetPoint("LEFT", 440, 0)
                    mrow.mmr:SetWidth(92)
                    mrow.mmr:SetJustifyH("CENTER")
                    mrow.mmr:SetWordWrap(false)

                    mrow.duration = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.duration:SetFont(lib.FONT_BODY, 10, "")
                    mrow.duration:SetPoint("LEFT", 534, 0)
                    mrow.duration:SetWidth(28)
                    mrow.duration:SetWordWrap(false)
                    mrow.duration:SetJustifyH("CENTER")

                    mrow.timeStr = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.timeStr:SetFont(lib.FONT_BODY, 10, "")
                    mrow.timeStr:SetPoint("LEFT", 562, 0)
                    mrow.timeStr:SetWidth(86)
                    mrow.timeStr:SetWordWrap(false)
                    mrow.timeStr:SetJustifyH("RIGHT")

                    mrow.mapStr = mrow:CreateFontString(nil, "OVERLAY")
                    mrow.mapStr:SetFont(lib.FONT_BODY, 10, "")
                    mrow.mapStr:SetPoint("LEFT", 650, 0)
                    mrow.mapStr:SetWidth(30)
                    mrow.mapStr:SetWordWrap(false)
                    mrow.mapStr:SetJustifyH("CENTER")
                    mrow.mapStr:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

                    -- Replay button mirrors the one on history rows; shown
                    -- only when the match has a recorded event log.
                    mrow.replayBtn = CreateFrame("Button", nil, mrow)
                    mrow.replayBtn:SetSize(50, 18)
                    mrow.replayBtn:SetPoint("LEFT", 686, 0)
                    mrow.replayBtn.bg = mrow.replayBtn:CreateTexture(nil, "BACKGROUND")
                    mrow.replayBtn.bg:SetAllPoints()
                    mrow.replayBtn.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
                    mrow.replayBtn.icon = mrow.replayBtn:CreateFontString(nil, "OVERLAY")
                    mrow.replayBtn.icon:SetFont(lib.FONT_BODY, 9, "")
                    mrow.replayBtn.icon:SetPoint("CENTER")
                    mrow.replayBtn.icon:SetText("Replay >")
                    mrow.replayBtn.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
                    mrow.replayBtn:SetScript("OnEnter", function(self)
                        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
                    end)
                    mrow.replayBtn:SetScript("OnLeave", function(self)
                        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
                    end)

                    mrow.bg = mrow:CreateTexture(nil, "BACKGROUND")
                    mrow.bg:SetAllPoints()

                    -- Hover highlight
                    local hl = mrow:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
                end

                mrow:SetPoint("TOPLEFT", 0, -totalHeight)
                mrow.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.7)

                -- Result
                if game.result == "WIN" then
                    mrow.result:SetText("|cff00ff00WIN|r")
                else
                    mrow.result:SetText("|cffff0000LOSS|r")
                end

                -- Friendly team (two-line: names + spec/race details)
                mrow.friendly:SetText(FormatTeamNames(game.friendlyTeam, game.playerName) or "—")

                mrow.vs:SetText("vs")

                mrow.enemy:SetText(FormatEnemyTeam(game))
                mrow.rating:SetText(FormatRatingChange(game))
                mrow.mmr:SetText(FormatMMR(game))

                -- Duration
                local dur = (game.startTime and game.endTime) and (game.endTime - game.startTime) or nil
                mrow.duration:SetText(FormatDuration(dur))
                mrow.duration:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

                -- Time
                mrow.timeStr:SetText(FormatTime(game.startTime))
                mrow.timeStr:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

                -- Map (abbreviated)
                mrow.mapStr:SetText(AbbrevMap(game.map))

                -- Replay button (only when event log present)
                if game.eventLog then
                    mrow.replayBtn:Show()
                    mrow.replayBtn:SetScript("OnClick", function()
                        lib:HideOptionsPanel()
                        addon:OpenReplay(game)
                    end)
                else
                    mrow.replayBtn:Hide()
                end

                mrow:Show()
                totalHeight = totalHeight + ROW_HEIGHT
            end
        end
    end

    sessContent:SetHeight(math.max(totalHeight, 1))
end
end  -- end Sessions Tab Content wrap

---------------------------------------------------------------------------
-- Teams Tab Content
---------------------------------------------------------------------------
do  -- wrap section: keeps its locals out of the main chunk's 200-local budget
local teamFilters = {
    bracket = "All",
    season = currentSeason,
}

local teamBracketDD = CreateSearchableDropdown(teamsContainer, "TkTeamBracketDD", 120, {
    defaultLabel = "Bracket: All",
    getOptions = function()
        local out = {}
        local brackets = { "2v2", "3v3", "5v5" }
        for _, b in ipairs(brackets) do
            table.insert(out, {
                key = b,
                text = b,
                searchText = b:lower(),
                isChecked = function() return teamFilters.bracket == b end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if teamFilters.bracket == key then
            teamFilters.bracket = "All"
        else
            teamFilters.bracket = key
        end
        if RefreshTeams then RefreshTeams() end
    end,
    onClear = function()
        teamFilters.bracket = "All"
        if RefreshTeams then RefreshTeams() end
    end,
    getLabel = function()
        if teamFilters.bracket == "All" then return "Bracket: All" end
        return "Bracket: " .. teamFilters.bracket
    end,
})
teamBracketDD.frame:SetPoint("TOPLEFT", 10, -10)

do
    local teamSeasonDD = CreateSearchableDropdown(teamsContainer, "TkTeamSeasonDD", 120, {
        defaultLabel = "|cffE8B923Season " .. currentSeason .. "|r",
        autoClose = true,
        getOptions = function()
            local out = {}
            table.insert(out, {
                key = "all",
                text = "All Seasons",
                searchText = "all",
                isChecked = function() return teamFilters.season == nil end,
            })
            for _, s in ipairs(CollectUniqueSeasons()) do
                local key = tostring(s)
                table.insert(out, {
                    key = key,
                    text = "Season " .. s,
                    searchText = key,
                    isChecked = function() return teamFilters.season == s end,
                })
            end
            return out
        end,
        onToggle = function(key)
            if key == "all" then
                teamFilters.season = nil
            else
                local s = tonumber(key)
                if teamFilters.season == s then
                    teamFilters.season = nil
                else
                    teamFilters.season = s
                end
            end
            if RefreshTeams then RefreshTeams() end
        end,
        onClear = function() teamFilters.season = nil; if RefreshTeams then RefreshTeams() end end,
        getLabel = function()
            if not teamFilters.season then return "Season: All" end
            return "|cffE8B923Season " .. teamFilters.season .. "|r"
        end,
    })
    teamSeasonDD.frame:SetPoint("LEFT", teamBracketDD.frame, "RIGHT", 10, 0)

    seasonDefault:Register(function(season)
        teamFilters.season = season
        teamSeasonDD:SetLabel("|cffE8B923Season " .. season .. "|r")
    end)
end

-- Teams column headers
local teamHeaderY = -46
local teamHeaders = {
    { text = "#",        x = 4,   w = 24,  justify = "RIGHT" },
    { text = "Partners", x = 32,  w = 240, justify = "LEFT" },
    { text = "Bracket",  x = 276, w = 50,  justify = "CENTER" },
    { text = "Games",    x = 330, w = 50,  justify = "CENTER" },
    { text = "W-L",      x = 384, w = 60,  justify = "CENTER" },
    { text = "Win%",     x = 448, w = 50,  justify = "CENTER" },
    { text = "Net",      x = 502, w = 60,  justify = "CENTER" },
}
for _, h in ipairs(teamHeaders) do
    local fs = teamsContainer:CreateFontString(nil, "OVERLAY")
    fs:SetFont(lib.FONT_BODY, 10, "")
    fs:SetPoint("TOPLEFT", h.x, teamHeaderY)
    fs:SetWidth(h.w)
    fs:SetJustifyH(h.justify)
    fs:SetWordWrap(false)
    fs:SetText(h.text)
    fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
end

-- Thin separator below team headers
local teamHeaderSep = teamsContainer:CreateTexture(nil, "ARTWORK")
teamHeaderSep:SetHeight(1)
teamHeaderSep:SetPoint("TOPLEFT", 4, teamHeaderY - 12)
teamHeaderSep:SetPoint("TOPRIGHT", -16, teamHeaderY - 12)
teamHeaderSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

-- Teams scroll frame
local teamScrollFrame = CreateFrame("ScrollFrame", nil, teamsContainer, "UIPanelScrollFrameTemplate")
teamScrollFrame:SetPoint("TOPLEFT", 10, teamHeaderY - 14)
teamScrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local teamContent = CreateFrame("Frame", nil, teamScrollFrame)
teamContent:SetSize(740, 1)
teamScrollFrame:SetScrollChild(teamContent)

local TEAM_ROW_HEIGHT = 28
local teamRowPool = {}

---------------------------------------------------------------------------
-- RefreshTeams
---------------------------------------------------------------------------
function RefreshTeams()
    for _, row in ipairs(teamRowPool) do
        row:Hide()
    end

    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}
    local bracketFilter = teamFilters.bracket ~= "All" and teamFilters.bracket or nil
    local teams = ComputeTeams(allGames, bracketFilter, teamFilters.season)

    local totalHeight = 0

    for i, t in ipairs(teams) do
        local row = teamRowPool[i]
        if not row then
            row = CreateFrame("Frame", nil, teamContent)
            row:SetSize(740, TEAM_ROW_HEIGHT)
            teamRowPool[i] = row

            row.index = row:CreateFontString(nil, "OVERLAY")
            row.index:SetFont(lib.FONT_BODY, 10, "")
            row.index:SetPoint("LEFT", 4, 0)
            row.index:SetWidth(24)
            row.index:SetWordWrap(false)
            row.index:SetJustifyH("RIGHT")

            row.partners = row:CreateFontString(nil, "OVERLAY")
            row.partners:SetFont(lib.FONT_BODY, 10, "")
            row.partners:SetPoint("LEFT", 32, 0)
            row.partners:SetWidth(240)
            row.partners:SetJustifyH("LEFT")
            row.partners:SetWordWrap(false)

            row.bracket = row:CreateFontString(nil, "OVERLAY")
            row.bracket:SetFont(lib.FONT_BODY, 10, "")
            row.bracket:SetPoint("LEFT", 276, 0)
            row.bracket:SetWidth(50)
            row.bracket:SetWordWrap(false)
            row.bracket:SetJustifyH("CENTER")

            row.games = row:CreateFontString(nil, "OVERLAY")
            row.games:SetFont(lib.FONT_BODY, 10, "")
            row.games:SetPoint("LEFT", 330, 0)
            row.games:SetWidth(50)
            row.games:SetWordWrap(false)
            row.games:SetJustifyH("CENTER")

            row.wl = row:CreateFontString(nil, "OVERLAY")
            row.wl:SetFont(lib.FONT_BODY, 10, "")
            row.wl:SetPoint("LEFT", 384, 0)
            row.wl:SetWidth(60)
            row.wl:SetWordWrap(false)
            row.wl:SetJustifyH("CENTER")

            row.winPct = row:CreateFontString(nil, "OVERLAY")
            row.winPct:SetFont(lib.FONT_BODY, 10, "")
            row.winPct:SetPoint("LEFT", 448, 0)
            row.winPct:SetWidth(50)
            row.winPct:SetWordWrap(false)
            row.winPct:SetJustifyH("CENTER")

            row.net = row:CreateFontString(nil, "OVERLAY")
            row.net:SetFont(lib.FONT_BODY, 10, "")
            row.net:SetPoint("LEFT", 502, 0)
            row.net:SetWidth(60)
            row.net:SetWordWrap(false)
            row.net:SetJustifyH("CENTER")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
        end

        row:SetPoint("TOPLEFT", 0, -totalHeight)

        -- Alternating row color
        if i % 2 == 0 then
            row.bg:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.index:SetText("#" .. i)
        row.index:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        -- Partners: class-colored names
        if t.partners and #t.partners > 0 then
            local pParts = {}
            for _, p in ipairs(t.partners) do
                local color = CLASS_COLORS[p.class] or "ffffffff"
                table.insert(pParts, "|c" .. color .. p.name .. "|r")
            end
            row.partners:SetText(table.concat(pParts, ", "))
        else
            row.partners:SetText("|cff888888Solo|r")
        end

        row.bracket:SetText(t.bracket or "?")
        row.bracket:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

        row.games:SetText(t.totalGames)
        row.games:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

        row.wl:SetText("|cff00ff00" .. t.wins .. "|r-|cffff0000" .. t.losses .. "|r")
        row.winPct:SetText(FormatWinPct(t.wins, t.losses))

        -- Net rating
        if t.netRating and t.netRating ~= 0 then
            local sign = t.netRating >= 0 and "+" or ""
            local netColor = t.netRating >= 0 and "|cff00ff00" or "|cffff0000"
            row.net:SetText(netColor .. sign .. t.netRating .. "|r")
        else
            row.net:SetText("|cff888888" .. "0" .. "|r")
        end

        row:Show()
        totalHeight = totalHeight + TEAM_ROW_HEIGHT
    end

    teamContent:SetHeight(math.max(totalHeight, 1))
end
end  -- end Teams Tab Content wrap

---------------------------------------------------------------------------
-- Enemies Tab Content
-- Lifetime W/L and cumulative net rating vs each opponent you've faced.
---------------------------------------------------------------------------
-- Defaults to All Seasons (lifetime); bracket/season can still be narrowed.
do  -- wrap section: keeps its locals out of the main chunk's 200-local budget
local enemyFilters = {
    bracket = "All",
    season = nil,
    search = "",
}

local enemyBracketDD = CreateSearchableDropdown(enemiesContainer, "TkEnemyBracketDD", 120, {
    defaultLabel = "Bracket: All",
    getOptions = function()
        local out = {}
        local brackets = { "2v2", "3v3", "5v5" }
        for _, b in ipairs(brackets) do
            table.insert(out, {
                key = b,
                text = b,
                searchText = b:lower(),
                isChecked = function() return enemyFilters.bracket == b end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if enemyFilters.bracket == key then
            enemyFilters.bracket = "All"
        else
            enemyFilters.bracket = key
        end
        if RefreshEnemies then RefreshEnemies() end
    end,
    onClear = function()
        enemyFilters.bracket = "All"
        if RefreshEnemies then RefreshEnemies() end
    end,
    getLabel = function()
        if enemyFilters.bracket == "All" then return "Bracket: All" end
        return "Bracket: " .. enemyFilters.bracket
    end,
})
enemyBracketDD.frame:SetPoint("TOPLEFT", 10, -10)

do
    local enemySeasonDD = CreateSearchableDropdown(enemiesContainer, "TkEnemySeasonDD", 120, {
        defaultLabel = "Season: All",
        autoClose = true,
        getOptions = function()
            local out = {}
            table.insert(out, {
                key = "all",
                text = "All Seasons",
                searchText = "all",
                isChecked = function() return enemyFilters.season == nil end,
            })
            for _, s in ipairs(CollectUniqueSeasons()) do
                local key = tostring(s)
                table.insert(out, {
                    key = key,
                    text = "Season " .. s,
                    searchText = key,
                    isChecked = function() return enemyFilters.season == s end,
                })
            end
            return out
        end,
        onToggle = function(key)
            if key == "all" then
                enemyFilters.season = nil
            else
                local s = tonumber(key)
                if enemyFilters.season == s then
                    enemyFilters.season = nil
                else
                    enemyFilters.season = s
                end
            end
            if RefreshEnemies then RefreshEnemies() end
        end,
        onClear = function() enemyFilters.season = nil; if RefreshEnemies then RefreshEnemies() end end,
        getLabel = function()
            if not enemyFilters.season then return "Season: All" end
            return "|cffE8B923Season " .. enemyFilters.season .. "|r"
        end,
    })
    enemySeasonDD.frame:SetPoint("LEFT", enemyBracketDD.frame, "RIGHT", 10, 0)
end

-- Search box: filter the enemy list by name substring
local enemySearchBox = CreateFrame("EditBox", "TkEnemySearchBox", enemiesContainer, "BackdropTemplate")
enemySearchBox:SetSize(180, 22)
enemySearchBox:SetPoint("TOPLEFT", 272, -9)
enemySearchBox:SetFont(lib.FONT_BODY, 11, "")
enemySearchBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
enemySearchBox:SetAutoFocus(false)
enemySearchBox:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeSize = 1,
})
enemySearchBox:SetBackdropColor(0, 0, 0, 0.4)
enemySearchBox:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
enemySearchBox:SetTextInsets(6, 6, 0, 0)

enemySearchBox.placeholder = enemySearchBox:CreateFontString(nil, "ARTWORK")
enemySearchBox.placeholder:SetFont(lib.FONT_BODY, 11, "")
enemySearchBox.placeholder:SetPoint("LEFT", 6, 0)
enemySearchBox.placeholder:SetText("Search enemy name...")
enemySearchBox.placeholder:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

enemySearchBox:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    enemyFilters.search = text and text:lower() or ""
    self.placeholder:SetShown(enemyFilters.search == "")
    if RefreshEnemies then RefreshEnemies() end
end)
enemySearchBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)

-- Enemies column headers — clickable to sort. Click a column to sort by it;
-- click again to flip direction. Numeric columns start descending, name ascending.
local enemySort = { key = "games", dir = "desc" }

local enemyHeaderY = -46
local enemyHeaders = {
    { text = "#",      x = 4,   w = 24,  justify = "RIGHT"  },                  -- not sortable
    { text = "Enemy",  x = 32,  w = 260, justify = "LEFT",   sortKey = "name"   },
    { text = "Games",  x = 300, w = 60,  justify = "CENTER", sortKey = "games"  },
    { text = "W-L",    x = 368, w = 70,  justify = "CENTER", sortKey = "wins"   },
    { text = "Win%",   x = 446, w = 56,  justify = "CENTER", sortKey = "winpct" },
    { text = "Net",    x = 510, w = 90,  justify = "CENTER", sortKey = "net"    },
}
local enemyHeaderFS = {}  -- sortKey -> fontstring (so we can repaint the arrow)

local function ApplyEnemyHeaderArrows()
    for _, h in ipairs(enemyHeaders) do
        if h.sortKey then
            local fs = enemyHeaderFS[h.sortKey]
            if fs then
                local active = enemySort.key == h.sortKey
                local arrow = active and (enemySort.dir == "desc" and " v" or " ^") or ""
                fs:SetText(h.text .. arrow)
                if active then
                    fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
                else
                    fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
                end
            end
        end
    end
end

for _, h in ipairs(enemyHeaders) do
    if h.sortKey then
        local btn = CreateFrame("Button", nil, enemiesContainer)
        btn:SetPoint("TOPLEFT", h.x, enemyHeaderY)
        btn:SetSize(h.w, 14)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont(lib.FONT_BODY, 10, "")
        fs:SetAllPoints()
        fs:SetJustifyH(h.justify)
        fs:SetWordWrap(false)
        fs:SetText(h.text)
        fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        enemyHeaderFS[h.sortKey] = fs
        btn:SetScript("OnClick", function()
            if enemySort.key == h.sortKey then
                enemySort.dir = (enemySort.dir == "desc") and "asc" or "desc"
            else
                enemySort.key = h.sortKey
                enemySort.dir = (h.sortKey == "name") and "asc" or "desc"
            end
            ApplyEnemyHeaderArrows()
            if RefreshEnemies then RefreshEnemies() end
        end)
        btn:SetScript("OnEnter", function()
            if enemySort.key ~= h.sortKey then
                fs:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
            end
        end)
        btn:SetScript("OnLeave", ApplyEnemyHeaderArrows)
    else
        local fs = enemiesContainer:CreateFontString(nil, "OVERLAY")
        fs:SetFont(lib.FONT_BODY, 10, "")
        fs:SetPoint("TOPLEFT", h.x, enemyHeaderY)
        fs:SetWidth(h.w)
        fs:SetJustifyH(h.justify)
        fs:SetWordWrap(false)
        fs:SetText(h.text)
        fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end
end
ApplyEnemyHeaderArrows()

-- Thin separator below enemy headers
local enemyHeaderSep = enemiesContainer:CreateTexture(nil, "ARTWORK")
enemyHeaderSep:SetHeight(1)
enemyHeaderSep:SetPoint("TOPLEFT", 4, enemyHeaderY - 12)
enemyHeaderSep:SetPoint("TOPRIGHT", -16, enemyHeaderY - 12)
enemyHeaderSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

-- Enemies scroll frame
local enemyScrollFrame = CreateFrame("ScrollFrame", nil, enemiesContainer, "UIPanelScrollFrameTemplate")
enemyScrollFrame:SetPoint("TOPLEFT", 10, enemyHeaderY - 14)
enemyScrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local enemyContent = CreateFrame("Frame", nil, enemyScrollFrame)
enemyContent:SetSize(740, 1)
enemyScrollFrame:SetScrollChild(enemyContent)

local ENEMY_ROW_HEIGHT = 28
local enemyRowPool = {}

---------------------------------------------------------------------------
-- RefreshEnemies
---------------------------------------------------------------------------
function RefreshEnemies()
    for _, row in ipairs(enemyRowPool) do
        row:Hide()
    end

    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}
    local bracketFilter = enemyFilters.bracket ~= "All" and enemyFilters.bracket or nil
    local enemies = ComputeEnemies(allGames, bracketFilter, enemyFilters.season)

    -- Name search filter (case-insensitive substring)
    local q = enemyFilters.search
    if q and q ~= "" then
        local matched = {}
        for _, e in ipairs(enemies) do
            if e.name and e.name:lower():find(q, 1, true) then
                table.insert(matched, e)
            end
        end
        enemies = matched
    end

    -- Apply the column sort chosen via the header buttons.
    local function winPct(e)
        local total = e.wins + e.losses
        return total > 0 and (e.wins / total) or 0
    end
    local key, dir = enemySort.key, enemySort.dir
    table.sort(enemies, function(a, b)
        local av, bv
        if key == "name" then
            av, bv = (a.name or ""):lower(), (b.name or ""):lower()
        elseif key == "wins" then
            av, bv = a.wins, b.wins
        elseif key == "winpct" then
            av, bv = winPct(a), winPct(b)
        elseif key == "net" then
            av, bv = a.netRating or 0, b.netRating or 0
        else -- "games"
            av, bv = a.totalGames, b.totalGames
        end
        if av == bv then
            -- Stable tiebreak: most games, then name.
            if a.totalGames ~= b.totalGames then return a.totalGames > b.totalGames end
            return (a.name or "") < (b.name or "")
        end
        if dir == "asc" then return av < bv else return av > bv end
    end)

    local totalHeight = 0

    for i, e in ipairs(enemies) do
        local row = enemyRowPool[i]
        if not row then
            row = CreateFrame("Frame", nil, enemyContent)
            row:SetSize(740, ENEMY_ROW_HEIGHT)
            enemyRowPool[i] = row

            row.index = row:CreateFontString(nil, "OVERLAY")
            row.index:SetFont(lib.FONT_BODY, 10, "")
            row.index:SetPoint("LEFT", 4, 0)
            row.index:SetWidth(24)
            row.index:SetWordWrap(false)
            row.index:SetJustifyH("RIGHT")

            row.name = row:CreateFontString(nil, "OVERLAY")
            row.name:SetFont(lib.FONT_BODY, 10, "")
            row.name:SetPoint("LEFT", 32, 0)
            row.name:SetWidth(260)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)

            row.games = row:CreateFontString(nil, "OVERLAY")
            row.games:SetFont(lib.FONT_BODY, 10, "")
            row.games:SetPoint("LEFT", 300, 0)
            row.games:SetWidth(60)
            row.games:SetWordWrap(false)
            row.games:SetJustifyH("CENTER")

            row.wl = row:CreateFontString(nil, "OVERLAY")
            row.wl:SetFont(lib.FONT_BODY, 10, "")
            row.wl:SetPoint("LEFT", 368, 0)
            row.wl:SetWidth(70)
            row.wl:SetWordWrap(false)
            row.wl:SetJustifyH("CENTER")

            row.winPct = row:CreateFontString(nil, "OVERLAY")
            row.winPct:SetFont(lib.FONT_BODY, 10, "")
            row.winPct:SetPoint("LEFT", 446, 0)
            row.winPct:SetWidth(56)
            row.winPct:SetWordWrap(false)
            row.winPct:SetJustifyH("CENTER")

            row.net = row:CreateFontString(nil, "OVERLAY")
            row.net:SetFont(lib.FONT_BODY, 10, "")
            row.net:SetPoint("LEFT", 510, 0)
            row.net:SetWidth(90)
            row.net:SetWordWrap(false)
            row.net:SetJustifyH("CENTER")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])

            -- Click an enemy to jump to the Matches tab filtered to games
            -- against them (search box + all-seasons so nothing is hidden)
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and self.enemyName then
                    filters.season = nil
                    seasonDD:SetLabel("Season: All")
                    histSearchBox:SetText(self.enemyName)
                    historyTabBar:SelectTab("matches")
                end
            end)
        end

        row.enemyName = e.name

        row:SetPoint("TOPLEFT", 0, -totalHeight)

        if i % 2 == 0 then
            row.bg:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.index:SetText("#" .. i)
        row.index:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        local color = CLASS_COLORS[e.class] or "ffffffff"
        row.name:SetText("|c" .. color .. (e.name or "?") .. "|r")

        row.games:SetText(e.totalGames)
        row.games:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

        row.wl:SetText("|cff00ff00" .. e.wins .. "|r-|cffff0000" .. e.losses .. "|r")
        row.winPct:SetText(FormatWinPct(e.wins, e.losses))

        -- Net rating: cumulative points gained/lost vs this player
        if e.netRating and e.netRating ~= 0 then
            local sign = e.netRating >= 0 and "+" or ""
            local netColor = e.netRating >= 0 and "|cff00ff00" or "|cffff0000"
            row.net:SetText(netColor .. sign .. e.netRating .. "|r")
        else
            row.net:SetText("|cff888888" .. "0" .. "|r")
        end

        row:Show()
        totalHeight = totalHeight + ENEMY_ROW_HEIGHT
    end

    enemyContent:SetHeight(math.max(totalHeight, 1))
end
end  -- end Enemies Tab Content wrap

local function ToggleHistory()
    if lib:IsOptionsPanelShown() then
        lib:HideOptionsPanel()
    else
        lib:ShowOptionsPanel("History")
    end
end

---------------------------------------------------------------------------
-- Minimap Button
---------------------------------------------------------------------------
local minimapButton = CreateFrame("Button", "TrinketedMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Icon (Medallion of the Horde)
local mmIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
mmIcon:SetSize(21, 21)
mmIcon:SetPoint("CENTER", 0, 0)
mmIcon:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_02")
mmIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)  -- crop default icon border

-- Border overlay (standard minimap button ring)
local mmBorder = minimapButton:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT", 0, 0)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local mmDragging = false

local function UpdateMinimapButtonPos(angle)
    local rad = math.rad(angle or 220)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Default position — will be overridden from SavedVariables in ADDON_LOADED
UpdateMinimapButtonPos(220)

minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

minimapButton:SetScript("OnDragStart", function(self)
    mmDragging = true
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        if TrinketedHistoryDB and TrinketedHistoryDB.minimap then
            TrinketedHistoryDB.minimap.minimapPos = angle
        end
        UpdateMinimapButtonPos(angle)
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    mmDragging = false
    self:SetScript("OnUpdate", nil)
end)

minimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        ToggleHistory()
    elseif button == "RightButton" then
        local count = TrinketedHistoryDB and #TrinketedHistoryDB.games or 0
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r " .. count .. " games recorded.")
        print("  /trinketed history — toggle game history")
        print("  /trinketed minimap — toggle minimap button")
        print("  /trinketed hdebug — toggle history debug logging")
        print("  /trinketed dev — toggle developer mode (raw-data inspection)")
        print("  /trinketed tsdebug — force-show timestamp overlay + barcode")
        print("  /trinketed sbdebug — show live scoreboard leaderboard")
        print("  /trinketed status — dump current state")
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Trinketed", 0, 0.8, 1)
    local count = TrinketedHistoryDB and #TrinketedHistoryDB.games or 0
    GameTooltip:AddLine(count .. " games recorded", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ff00Left-click|r to toggle history", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00ff00Right-click|r for commands", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00ff00Drag|r to reposition", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- JSON / LibDeflate helpers (used by CompressEventLog and consumed by ReplayEngine)
---------------------------------------------------------------------------
local LibDeflate = LibStub("LibDeflate")

-- Minimal JSON serialiser — handles strings, numbers, booleans, nil, arrays, objects
local function JsonEscape(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function IsArray(t)
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            return false
        end
    end
    return true
end

local function TableToJSON(val)
    local vtype = type(val)
    if val == nil then return "null"
    elseif vtype == "boolean" then return val and "true" or "false"
    elseif vtype == "number" then return tostring(val)
    elseif vtype == "string" then return '"' .. JsonEscape(val) .. '"'
    elseif vtype == "table" then
        local parts = {}
        if IsArray(val) then
            for i = 1, #val do
                parts[i] = TableToJSON(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local i = 0
            for k, v in pairs(val) do
                i = i + 1
                parts[i] = '"' .. JsonEscape(tostring(k)) .. '":' .. TableToJSON(v)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

CompressEventLog = function()
    if not currentMatch or not currentMatch.events then return nil end

    local log = {
        v = 3,
        startTime = currentMatch.startTime,
        roster = currentMatch.roster,
        events = currentMatch.events,
    }

    local json = TableToJSON(log)
    local compressed = LibDeflate:CompressZlib(json, { level = 9 })
    if not compressed then
        dbg("CompressEventLog: compression failed")
        return nil
    end
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        dbg("CompressEventLog: encoding failed")
        return nil
    end
    dbg("CompressEventLog:", #log.events, "events,", #json, "bytes JSON →", #encoded, "bytes encoded")
    return encoded
end

-- Minimal JSON parser (used by ReplayEngine to decompress per-match event logs)
local function JSONToTable(str)
    local pos = 1
    local function skipWhitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
    local function parseValue()
        skipWhitespace()
        local ch = str:sub(pos, pos)
        if ch == '"' then
            -- string
            pos = pos + 1
            local start = pos
            local result = {}
            while pos <= #str do
                local c = str:sub(pos, pos)
                if c == '\\' then
                    table.insert(result, str:sub(start, pos - 1))
                    pos = pos + 1
                    local esc = str:sub(pos, pos)
                    if esc == 'n' then table.insert(result, "\n")
                    elseif esc == 'r' then table.insert(result, "\r")
                    elseif esc == 't' then table.insert(result, "\t")
                    elseif esc == '"' then table.insert(result, '"')
                    elseif esc == '\\' then table.insert(result, '\\')
                    else table.insert(result, esc) end
                    pos = pos + 1
                    start = pos
                elseif c == '"' then
                    table.insert(result, str:sub(start, pos - 1))
                    pos = pos + 1
                    return table.concat(result)
                else
                    pos = pos + 1
                end
            end
        elseif ch == '{' then
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) == '}' then pos = pos + 1; return obj end
            while true do
                skipWhitespace()
                local key = parseValue() -- must be a string
                skipWhitespace()
                pos = pos + 1 -- skip ':'
                local val = parseValue()
                obj[key] = val
                skipWhitespace()
                local sep = str:sub(pos, pos)
                pos = pos + 1
                if sep == '}' then return obj end
            end
        elseif ch == '[' then
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) == ']' then pos = pos + 1; return arr end
            while true do
                local val = parseValue()
                table.insert(arr, val)
                skipWhitespace()
                local sep = str:sub(pos, pos)
                pos = pos + 1
                if sep == ']' then return arr end
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4; return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5; return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4; return nil
        else
            -- number
            local numStr = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if numStr then
                pos = pos + #numStr
                return tonumber(numStr)
            end
        end
    end
    return parseValue()
end
addon.JSONToTable = JSONToTable

---------------------------------------------------------------------------
-- Share / Import: export a match as a text string a teammate can import to
-- watch the replay. Populates the Share table declared above the row factory.
---------------------------------------------------------------------------
do  -- wrap section: keeps its locals out of the main chunk's 200-local budget
local SHARE_PREFIX = "TRINKR1!"
local MAX_DECOMPRESSED = 20 * 1024 * 1024  -- refuse absurdly large payloads
local IMPORT_MAX_LETTERS = 1000000         -- paste box cap (strings can be 100k+)
local shareDialog

local function ChatMsg(msg)
    print("|cff00ccff" .. DISPLAY_NAME .. ":|r " .. msg)
end

-- Serialise a full game record (metadata + already-compressed eventLog string)
-- into a printable share string.
function Share.BuildString(game)
    local json = TableToJSON({ v = 1, game = game })
    local compressed = LibDeflate:CompressDeflate(json, { level = 9 })
    if not compressed then
        dbg("Share: compression failed")
        return nil
    end
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        dbg("Share: encoding failed")
        return nil
    end
    dbg("Share:", #json, "bytes JSON →", #encoded, "chars encoded")
    return SHARE_PREFIX .. encoded
end

-- Decode a pasted share string back into a transient game record.
-- Returns game on success, or nil + user-facing error message.
function Share.Decode(text)
    text = tostring(text or ""):gsub("%s+", "")  -- strip paste linebreaks/spaces
    if text == "" then
        return nil, "Paste a share string first."
    end
    if text:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then
        return nil, "Not a Trinketed match string (missing " .. SHARE_PREFIX .. " prefix)."
    end
    local compressed = LibDeflate:DecodeForPrint(text:sub(#SHARE_PREFIX + 1))
    if not compressed then
        return nil, "Could not decode the string — it may be truncated or corrupted."
    end
    local json = LibDeflate:DecompressDeflate(compressed)
    if not json then
        return nil, "Could not decompress the string — it may be truncated or corrupted."
    end
    if #json > MAX_DECOMPRESSED then
        return nil, "Match data too large — refusing to import."
    end
    local ok, payload = pcall(JSONToTable, json)
    if not ok or type(payload) ~= "table" then
        return nil, "Could not parse the match data."
    end
    if payload.v ~= 1 then
        return nil, "Unsupported share format version (" .. tostring(payload.v) .. ")."
    end
    local game = payload.game
    if type(game) ~= "table" or type(game.eventLog) ~= "string" then
        return nil, "The match data contains no replay log."
    end
    return game
end

local function GetShareDialog()
    if shareDialog then return shareDialog end

    local f = CreateFrame("Frame", "TrinketedHistoryShareDialog", UIParent, "BackdropTemplate")
    f:SetSize(480, 300)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(C.frameBg[1], C.frameBg[2], C.frameBg[3], 0.97)
    f:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(lib.FONT_DISPLAY, 13, "")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    f.title = title

    local inst = f:CreateFontString(nil, "OVERLAY")
    inst:SetFont(lib.FONT_BODY, 10, "")
    inst:SetPoint("TOPLEFT", 14, -30)
    inst:SetPoint("TOPRIGHT", -14, -30)
    inst:SetJustifyH("LEFT")
    inst:SetWordWrap(false)
    inst:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    f.inst = inst

    -- Dark backing behind the string box
    local boxBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    boxBg:SetPoint("TOPLEFT", 12, -46)
    boxBg:SetPoint("BOTTOMRIGHT", -12, 66)
    boxBg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)

    local scroll = CreateFrame("ScrollFrame", "TrinketedHistoryShareScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -50)
    scroll:SetPoint("BOTTOMRIGHT", -34, 70)

    local editBox = CreateFrame("EditBox", "TrinketedHistoryShareEditBox", scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(lib.FONT_MONO, 10, "")
    editBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    editBox:SetWidth(414)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnChar", function(self)
        -- Export strings are read-only: restore the string on any typed char
        if f.mode == "export" and self.lockedText then
            self:SetText(self.lockedText)
            self:HighlightText()
        end
    end)
    editBox:SetScript("OnEnterPressed", function()
        if f.mode == "import" then Share.DoImport() end
    end)
    scroll:SetScrollChild(editBox)
    f.editBox = editBox

    local status = f:CreateFontString(nil, "OVERLAY")
    status:SetFont(lib.FONT_BODY, 10, "")
    status:SetPoint("BOTTOMLEFT", 14, 42)
    status:SetPoint("BOTTOMRIGHT", -14, 42)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)
    status:SetText("")
    f.status = status

    -- Bottom buttons (frame is 300 tall; 24px buttons at y=-266 leave a 10px margin)
    f.importBtn = lib:CreateButton(f, 14, -266, 120, "Import", function() Share.DoImport() end)
    f.closeBtn = lib:CreateButton(f, 346, -266, 120, "Close", function() f:Hide() end)

    -- Close (X)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -6, -6)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(lib.FONT_BODY, 14, "")
    closeText:SetPoint("CENTER", 0, 0)
    closeText:SetText("x")
    closeText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function()
        closeText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    end)
    close:SetScript("OnLeave", function()
        closeText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)

    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    shareDialog = f
    return f
end

function Share.ShowExport(game)
    local str = Share.BuildString(game)
    if not str then
        ChatMsg("Could not build a share string for this match.")
        return
    end
    local f = GetShareDialog()
    f.mode = "export"
    f.title:SetText("SHARE MATCH")
    f.inst:SetText("Send this string to a teammate — they can watch it with /trinketed import.")
    f.importBtn:Hide()
    f.editBox:SetMaxLetters(0)
    f.editBox.lockedText = str
    f.editBox:SetText(str)
    f.status:SetTextColor(C.statusSuccess[1], C.statusSuccess[2], C.statusSuccess[3])
    f.status:SetText(string.format("%.0f KB share string. Press Ctrl+C to copy.", #str / 1024))
    f:Show()
    C_Timer.After(0.05, function()
        if f:IsShown() and f.mode == "export" then
            f.editBox:SetFocus()
            f.editBox:HighlightText()
        end
    end)
end

function Share.ShowImport()
    local f = GetShareDialog()
    f.mode = "import"
    f.title:SetText("IMPORT MATCH")
    f.inst:SetText("Paste a " .. SHARE_PREFIX .. " string from a teammate, then click Import.")
    f.importBtn:Show()
    f.editBox.lockedText = nil
    f.editBox:SetMaxLetters(IMPORT_MAX_LETTERS)
    f.editBox:SetText("")
    f.status:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    f.status:SetText("The imported match opens as a replay only — it is never added to your history or stats.")
    f:Show()
    f.editBox:SetFocus()
end

function Share.DoImport()
    local f = shareDialog
    if not f then return end
    local game, err = Share.Decode(f.editBox:GetText())
    if not game then
        err = err or "Import failed."
        f.status:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
        f.status:SetText(err)
        ChatMsg("Import failed: " .. err)
        return
    end
    -- Transient record: intentionally NOT inserted into TrinketedHistoryDB.games
    f.editBox:SetText("")
    f:Hide()
    lib:HideOptionsPanel()
    local ok, openErr = pcall(addon.OpenReplay, addon, game)
    if not ok then
        ChatMsg("Could not open the imported replay: " .. tostring(openErr))
        dbg("Share import OpenReplay error:", tostring(openErr))
    else
        ChatMsg("Match imported — opening replay (not added to your history).")
    end
end

-- Slash commands (registered here, like the scoreboard section, so the
-- handlers can see this section's locals)
lib:RegisterSubCommand("share", function(args)
    local games = TrinketedHistoryDB and TrinketedHistoryDB.games
    if not games or #games == 0 then
        ChatMsg("No recorded matches to share.")
        return
    end
    local n = tonumber((args or ""):match("%d+")) or #games  -- default: latest
    local game = games[n]
    if not game then
        ChatMsg("No match #" .. n .. " — you have " .. #games .. " recorded matches.")
        return
    end
    if not game.eventLog then
        ChatMsg("Match #" .. n .. " has no replay log to share.")
        return
    end
    Share.ShowExport(game)
end)

lib:RegisterSubCommand("import", function()
    Share.ShowImport()
end)

end  -- Share / Import section

---------------------------------------------------------------------------
-- Event Handler
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("ARENA_OPPONENT_UPDATE")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("PVP_RATED_STATS_UPDATE")
frame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
frame:RegisterEvent("UNIT_TARGET")
frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
frame:RegisterEvent("ARENA_COOLDOWNS_UPDATE")
frame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
frame:RegisterEvent("UNIT_PET")

frame:SetScript("OnEvent", function(self, event, ...)
    -----------------------------------------------------------------
    -- ADDON_LOADED
    -----------------------------------------------------------------
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            TrinketedHistoryDB = TrinketedHistoryDB or { games = {} }
            TrinketedHistoryDB.games = TrinketedHistoryDB.games or {}
            TrinketedHistoryDB.minimap = TrinketedHistoryDB.minimap or { minimapPos = 220, hide = false }
            TrinketedHistoryDB.settings = TrinketedHistoryDB.settings or { showTimestamp = true }
            TrinketedHistoryDB.settings.hiddenReplayCDs = TrinketedHistoryDB.settings.hiddenReplayCDs or {}
            -- A jump intent only matters for the flush that immediately
            -- follows its click (the companion consumes it once). Clear any
            -- leftover so it ages out of the file on the next flush.
            TrinketedHistoryDB.jumpIntent = nil

            -- Backfill: stamp pre-season-tracking games as season 1
            for _, g in ipairs(TrinketedHistoryDB.games) do
                if not g.season then g.season = 1 end
            end

            -- Restore minimap button position and visibility
            UpdateMinimapButtonPos(TrinketedHistoryDB.minimap.minimapPos)
            if TrinketedHistoryDB.minimap.hide then
                minimapButton:Hide()
            else
                minimapButton:Show()
            end

            -- Ensure advanced combat logging is enabled
            if SetCVar then
                SetCVar("advancedCombatLogging", "1")
            end

            -- Re-read season at login time in case it wasn't available at file load
            local freshSeason = GetCurrentArenaSeason and GetCurrentArenaSeason() or 0
            if freshSeason > 0 then currentSeason = freshSeason end

            local seasonGames = 0
            for _, g in ipairs(TrinketedHistoryDB.games) do
                if (g.season or 1) == currentSeason then seasonGames = seasonGames + 1 end
            end
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Loaded — |cffE8B923Season " .. currentSeason .. "|r | " ..
                seasonGames .. " games this season, " .. #TrinketedHistoryDB.games .. " total.")

            -- Recover state if we reloaded mid-arena
            local zone = GetRealZoneText()
            if ARENA_ZONES[zone] then
                if state == "IDLE" then
                    state = "IN_ARENA_PREP"
                    InitMatch()
                    currentMatch.map = zone
                    LoggingCombat(true)

                    -- Check if gates already opened (no prep buff = game in progress)
                    local hasBuff = HasPrepBuff()
                    if hasBuff then
                        hadPrepBuff = true
                        dbg("Reload recovery: in prep room")
                        print("|cff00ccff" .. DISPLAY_NAME .. ":|r Reload detected — in arena prep room.")
                    else
                        -- Gates already opened, game is in progress
                        StartRecording()
                        dbg("Reload recovery: game in progress")
                        print("|cff00ccff" .. DISPLAY_NAME .. ":|r Reload detected — arena game in progress. Resuming tracking.")
                    end
                    UpdateOverlayVisibility()
                end
            end
        end

    -----------------------------------------------------------------
    -- ZONE_CHANGED_NEW_AREA
    -----------------------------------------------------------------
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local zone = GetRealZoneText()
        dbg("ZONE_CHANGED_NEW_AREA:", zone)

        if ARENA_ZONES[zone] then
            if state == "IDLE" then
                state = "IN_ARENA_PREP"
                InitMatch()
                currentMatch.map = zone

                -- Request fresh rating data
                if RequestRatedInfo then RequestRatedInfo() end

                -- Enable advanced combat logging
                if SetCVar then
                    SetCVar("advancedCombatLogging", "1")
                end
                LoggingCombat(true)

                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Entered " .. zone .. " — waiting for gates...")
            end
        else
            if state == "RECORDING" then
                -- Left arena mid-recording: use the already-detected winner
                -- if UPDATE_BATTLEFIELD_STATUS saw one, else count it a loss
                SaveMatch(pendingSave or "LOSS")
            elseif state == "IN_ARENA_PREP" then
                ResetMatchState()
            end
            LoggingCombat(false)
            UpdateOverlayVisibility()
        end

    -----------------------------------------------------------------
    -- UNIT_AURA — gates open detection
    -----------------------------------------------------------------
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit ~= "player" then return end
        if state ~= "IN_ARENA_PREP" then return end

        local hasBuff = HasPrepBuff()
        if hasBuff then
            if not hadPrepBuff then
                hadPrepBuff = true
                dbg("Arena Preparation buff detected")
                UpdateOverlayVisibility()
            end
        elseif hadPrepBuff and not hasBuff then
            -- Prep buff was removed = gates opened
            StartRecording()
        end

    -----------------------------------------------------------------
    -- ARENA_OPPONENT_UPDATE
    -----------------------------------------------------------------
    elseif event == "ARENA_OPPONENT_UPDATE" then
        if state == "IN_ARENA_PREP" or state == "RECORDING" then
            SnapshotRoster()
        end

    -----------------------------------------------------------------
    -- UPDATE_BATTLEFIELD_STATUS — match end detection
    -----------------------------------------------------------------
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        UpdateOverlayVisibility()
        TrackQueueStatus()

        if state ~= "RECORDING" then return end

        local winner = GetBattlefieldWinner()
        if not winner then return end

        local playerFaction = GetBattlefieldArenaFaction()
        local matchResult = (winner == playerFaction) and "WIN" or "LOSS"
        pendingSave = matchResult

        dbg("UPDATE_BATTLEFIELD_STATUS: winner =", winner, "playerFaction =", playerFaction, "→", matchResult)

        -- Request fresh data then save
        if RequestRatedInfo then RequestRatedInfo() end
        if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end

        -- Fallback: save after 2s if UPDATE_BATTLEFIELD_SCORE doesn't fire
        C_Timer.After(2, function()
            if pendingSave and currentMatch and currentMatch.startTime then
                dbg("Fallback save timer fired")
                SaveMatch(pendingSave)
                pendingSave = nil
            end
        end)

    -----------------------------------------------------------------
    -- UPDATE_BATTLEFIELD_SCORE — best time to save (scoreboard ready)
    -----------------------------------------------------------------
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        if not pendingSave then return end

        if RequestRatedInfo then RequestRatedInfo() end
        C_Timer.After(0.5, function()
            if pendingSave and currentMatch and currentMatch.startTime then
                dbg("Saving from UPDATE_BATTLEFIELD_SCORE")
                SaveMatch(pendingSave)
                pendingSave = nil
            end
        end)

    -----------------------------------------------------------------
    -- COMBAT_LOG_EVENT_UNFILTERED
    -----------------------------------------------------------------
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCLEU()

    -----------------------------------------------------------------
    -- UNIT_SPELLCAST_SUCCEEDED — spec detection + friendly trinket
    -----------------------------------------------------------------
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if state ~= "RECORDING" then return end
        local unit, _, spellID = ...
        if not unit or not spellID then return end
        local guid = UnitGUID(unit)
        if not guid then return end

        if not relevantGUIDs[guid] then DiscoverPlayerByGUID(guid) end
        if not relevantGUIDs[guid] then return end

        local spellName = GetSpellInfo(spellID)
        if spellName and SPEC_SPELLS[spellName] then
            AssignSpec(guid, spellName)
        end

        -- Friendly trinket/CC-break detection via SPELL_DB
        -- Only for player/party units — arena opponents are handled by ARENA_COOLDOWNS_UPDATE
        if SPELL_DB and not unit:match("^arena") then
            local rosterEntry = guidToRoster[guid]
            local dbEntry = select(2, addon.ResolveSpell(spellID, spellName,
                rosterEntry and rosterEntry.class))
            if dbEntry then
                local cat = dbEntry.cat
                if cat == "trinket" or cat == "cc_break" or cat == "racial" then
                    local name = UnitName(unit)
                    if name then name = StripRealm(name) end
                    local sn = GetSpellInfo(spellID) or dbEntry.name or "?"
                    local evt = {
                        t = GetRelativeTime(), type = "cast_success",
                        src = name or "?", srcGUID = guid,
                        dst = name or "?", dstGUID = guid,
                        spellID = spellID, spell = sn,
                        cat = cat,
                    }
                    EnrichEvent(evt)
                    AppendEvent(evt)
                end
            end
        end

    -----------------------------------------------------------------
    -- PVP_RATED_STATS_UPDATE
    -----------------------------------------------------------------
    elseif event == "PVP_RATED_STATS_UPDATE" then
        if state == "IN_ARENA_PREP" and not ratingsBefore then
            ratingsBefore = SnapshotAllRatings()
            dbg("Pre-match ratings (async):", ratingsBefore and ratingsBefore[1], ratingsBefore and ratingsBefore[2])
        end

    -----------------------------------------------------------------
    -- UNIT_TARGET
    -----------------------------------------------------------------
    elseif event == "UNIT_TARGET" then
        local unit = ...
        if unit then OnUnitTarget(unit) end

    -----------------------------------------------------------------
    -- UNIT_PET — a unit's pet changed (summon/dismiss/swap)
    -----------------------------------------------------------------
    elseif event == "UNIT_PET" then
        petTrack:Scan()

    -----------------------------------------------------------------
    -- PLAYER_FOCUS_CHANGED
    -----------------------------------------------------------------
    elseif event == "PLAYER_FOCUS_CHANGED" then
        OnFocusChanged()

    -----------------------------------------------------------------
    -- ARENA_COOLDOWNS_UPDATE — PvP trinket detection
    -----------------------------------------------------------------
    elseif event == "ARENA_COOLDOWNS_UPDATE" then
        if not C_PvP or not C_PvP.GetArenaCrowdControlInfo then return end

        for i = 1, 5 do
            local unitID = "arena" .. i
            local spellID, itemID, startTime, duration = C_PvP.GetArenaCrowdControlInfo(unitID)
            if spellID and startTime and startTime ~= 0 and duration and duration ~= 0 then
                if state ~= "RECORDING" or not currentMatch then
                    -- skip: not recording
                else
                    local guid = UnitGUID(unitID)
                    if guid and not relevantGUIDs[guid] then
                        DiscoverPlayerByGUID(guid)
                    end
                    if guid then
                        if trinketLastStart[guid] ~= startTime then
                            trinketLastStart[guid] = startTime
                            local t = GetRelativeTime()
                            local name = UnitName(unitID)
                            if name then name = StripRealm(name) end
                            local spellName = GetSpellInfo(spellID) or "PvP Trinket"
                            local evt = {
                                t = t, type = "cast_success",
                                src = name or "?", srcGUID = guid,
                                dst = name or "?", dstGUID = guid,
                                spellID = spellID, spell = spellName,
                                cat = "trinket",
                            }
                            EnrichEvent(evt)
                            if not evt.cat then evt.cat = "trinket" end
                            AppendEvent(evt)
                            dbg("RECORDED trinket from", name, spellID)
                        end
                    end
                end
            end
        end

    -----------------------------------------------------------------
    -- LOSS_OF_CONTROL_ADDED
    -----------------------------------------------------------------
    elseif event == "LOSS_OF_CONTROL_ADDED" then
        OnLossOfControl()
    end
end)

---------------------------------------------------------------------------
-- Sub-Command Registration (via TrinketedLib)
---------------------------------------------------------------------------
local function RegisterSubCommands()
    lib:RegisterSubCommand("history", function()
        ToggleHistory()
    end)

    lib:RegisterSubCommand("clear", function(args)
        if args == "confirm" then
            local old = TrinketedHistoryDB and #TrinketedHistoryDB.games or 0
            TrinketedHistoryDB.games = {}
            if historyContent:IsShown() then
                if activeTab == "sessions" then RefreshSessions()
                elseif activeTab == "teams" then RefreshTeams()
                elseif activeTab == "enemies" then RefreshEnemies()
                else RefreshHistory() end
            end
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Cleared " .. old .. " games.")
        else
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r |cffff4444This will delete ALL " .. #(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) .. " recorded games.|r")
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Type |cffffffff/trinketed clear confirm|r to proceed.")
        end
    end)

    lib:RegisterSubCommand("minimap", function()
        TrinketedHistoryDB.minimap = TrinketedHistoryDB.minimap or { minimapPos = 220, hide = false }
        TrinketedHistoryDB.minimap.hide = not TrinketedHistoryDB.minimap.hide
        if TrinketedHistoryDB.minimap.hide then
            minimapButton:Hide()
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Minimap button |cffff0000hidden|r. Type /trinketed minimap to show.")
        else
            minimapButton:Show()
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Minimap button |cff00ff00shown|r.")
        end
    end)

    lib:RegisterSubCommand("hdebug", function()
        debugMode = not debugMode
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r History debug mode " .. (debugMode and "|cff00ff00ON" or "|cffff0000OFF") .. "|r")
    end)

    lib:RegisterSubCommand("dev", function()
        local s = TrinketedHistoryDB and TrinketedHistoryDB.settings
        if not s then return end
        -- Store nil (not false) when off so the SavedVariables file stays clean.
        s.devMode = not s.devMode or nil
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r Developer mode " .. (s.devMode and "|cff00ff00ON" or "|cffff0000OFF") .. "|r (persists across reloads)")
    end)

    lib:RegisterSubCommand("tsdebug", function()
        tsForceShow = not tsForceShow
        UpdateOverlayVisibility()
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r Timestamp force-show " .. (tsForceShow and "|cff00ff00ON" or "|cffff0000OFF") .. "|r (text overlay + full barcode)")
    end)

    lib:RegisterSubCommand("status", function()
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r State dump:")
        print("  combatLogging:", tostring(LoggingCombat()))
        print("  state:", state)
        print("  hadPrepBuff:", tostring(hadPrepBuff))
        if currentMatch then
            print("  startTime:", tostring(currentMatch.startTime))
            local rosterCount = 0
            for _ in pairs(currentMatch.roster) do rosterCount = rosterCount + 1 end
            print("  roster:", rosterCount, "players")
            for guid, entry in pairs(currentMatch.roster) do
                local color = CLASS_COLORS[entry.class] or "ffffffff"
                print("    |c" .. color .. (entry.name or "?") .. "|r - " .. (entry.class or "?") .. " / " .. (entry.spec or "no spec") .. " (" .. entry.team .. ")")
            end
            if ratingsBefore then
                print("  ratingsBefore: 2v2=" .. tostring(ratingsBefore[1]) ..
                    " 3v3=" .. tostring(ratingsBefore[2]) ..
                    " 5v5=" .. tostring(ratingsBefore[3]))
            else
                print("  ratingsBefore: not captured")
            end
            print("  events:", currentMatch.events and #currentMatch.events or 0)
        end
        print("  debugMode:", tostring(debugMode))
        print("  GetPersonalRatedInfo:", tostring(GetPersonalRatedInfo ~= nil))
        print("  RequestRatedInfo:", tostring(RequestRatedInfo ~= nil))
        print("  GetBattlefieldScore:", tostring(GetBattlefieldScore ~= nil))
        print("  GetBattlefieldTeamInfo:", tostring(GetBattlefieldTeamInfo ~= nil))
        print("  GetArenaOpponentSpec:", tostring(GetArenaOpponentSpec ~= nil))
        print("  GetSpecializationInfoByID:", tostring(GetSpecializationInfoByID ~= nil))
        print("  GetNumArenaOpponentSpecs:", tostring(GetNumArenaOpponentSpecs ~= nil))
        if GetPersonalRatedInfo then
            if RequestRatedInfo then RequestRatedInfo() end
            for bracket, ratedIdx in pairs(BRACKET_TO_RATED_INDEX) do
                local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = GetPersonalRatedInfo(ratedIdx)
                print("  PersonalRatedInfo[" .. bracket .. "v" .. bracket .. "] (idx=" .. ratedIdx .. "):")
                print("    ret1=" .. tostring(r1) .. "  ret2=" .. tostring(r2) ..
                    "  ret3=" .. tostring(r3) .. "  ret4=" .. tostring(r4))
                print("    ret5=" .. tostring(r5) .. "  ret6=" .. tostring(r6) ..
                    "  ret7=" .. tostring(r7) .. "  ret8=" .. tostring(r8))
                if r9 ~= nil or r10 ~= nil or r11 ~= nil or r12 ~= nil then
                    print("    ret9=" .. tostring(r9) .. "  ret10=" .. tostring(r10) ..
                        "  ret11=" .. tostring(r11) .. "  ret12=" .. tostring(r12))
                end
            end
        else
            print("  PersonalRatedInfo: API not available")
        end
        local liveBracket = GetCurrentArenaBracket()
        print("  activeBracket:", tostring(liveBracket))
        for i = 1, GetMaxBattlefieldID() do
            local status, mapName, teamSize, registeredMatch, suspendedQueue, queueType, gameType = GetBattlefieldStatus(i)
            if status and status ~= "none" then
                print("  BattlefieldStatus[" .. i .. "]: status=" .. tostring(status) ..
                    " map=" .. tostring(mapName) .. " teamSize=" .. tostring(teamSize) ..
                    " registered=" .. tostring(registeredMatch) ..
                    " queueType=" .. tostring(queueType) .. " gameType=" .. tostring(gameType))
            end
        end
        if GetBattlefieldTeamInfo then
            for fi = 0, 1 do
                local tName, oldR, newR, mmr = GetBattlefieldTeamInfo(fi)
                if tName and tName ~= "" then
                    print("  BattlefieldTeamInfo[" .. fi .. "]: team=\"" .. tName ..
                        "\" old=" .. tostring(oldR) .. " new=" .. tostring(newR) ..
                        " mmr=" .. tostring(mmr))
                end
            end
        end
        if GetBattlefieldScore and GetNumBattlefieldScores then
            local numScores = GetNumBattlefieldScores()
            if numScores and numScores > 0 then
                print("  BattlefieldScores: " .. numScores .. " entries")
                for si = 1, numScores do
                    local name, _, _, _, _, _, _, _, _, _, _, bgRating, ratingChange, preMatchMMR, mmrChange = GetBattlefieldScore(si)
                    if name then
                        print("    [" .. si .. "] " .. name ..
                            " rating=" .. tostring(bgRating) .. " change=" .. tostring(ratingChange) ..
                            " mmr=" .. tostring(preMatchMMR) .. " mmrChange=" .. tostring(mmrChange))
                    end
                end
            end
        end
        if state ~= "IDLE" and GetArenaOpponentSpec then
            local numSpecs = GetNumArenaOpponentSpecs and GetNumArenaOpponentSpecs() or 0
            print("  numArenaOpponentSpecs:", numSpecs)
            for i = 1, 5 do
                local specID = GetArenaOpponentSpec(i)
                local specName = "N/A"
                if specID and specID > 0 and GetSpecializationInfoByID then
                    local _, sn = GetSpecializationInfoByID(specID)
                    specName = sn or ("specID=" .. specID)
                end
                local aName = UnitName("arena" .. i)
                if aName then
                    print("    arena" .. i .. ": specID=" .. tostring(specID) .. " (" .. specName .. ") - " .. aName)
                end
            end
        end
    end)

    -- Debug scoreboard/leaderboard window: pulls live per-player stats from the
    -- match scoreboard (C_PvP.GetScoreInfo, with legacy GetBattlefieldScore
    -- fallback) and ranks players by damage done. Refreshes on score updates.
    local sbFrame = nil

    local function GetScoreboardRows()
        local rows = {}
        local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
        for i = 1, n do
            local row
            if C_PvP and C_PvP.GetScoreInfo then
                local s = C_PvP.GetScoreInfo(i)
                if s and s.name then
                    row = {
                        name = s.name,
                        classToken = s.classToken,
                        faction = s.faction,
                        kb = s.killingBlows or 0,
                        deaths = s.deaths or 0,
                        damage = s.damageDone or 0,
                        healing = s.healingDone or 0,
                        rating = s.rating,
                        ratingChange = s.ratingChange,
                        mmr = s.prematchMMR,
                        mmrChange = s.mmrChange,
                    }
                end
            elseif GetBattlefieldScore then
                -- Legacy column order: name(1) kb(2) hk(3) deaths(4) honor(5) faction(6)
                -- race(7) class(8) classToken(9) damage(10) healing(11) rating(12)
                -- ratingChange(13) preMatchMMR(14) mmrChange(15)
                local name, kb, _, deaths, _, faction, _, _, classToken, damageDone, healingDone,
                      bgRating, ratingChange, preMatchMMR, mmrChange = GetBattlefieldScore(i)
                if name then
                    row = {
                        name = name,
                        classToken = classToken,
                        faction = faction,
                        kb = kb or 0,
                        deaths = deaths or 0,
                        damage = damageDone or 0,
                        healing = healingDone or 0,
                        rating = bgRating,
                        ratingChange = ratingChange,
                        mmr = preMatchMMR,
                        mmrChange = mmrChange,
                    }
                end
            end
            if row then rows[#rows + 1] = row end
        end
        table.sort(rows, function(a, b) return a.damage > b.damage end)
        return rows
    end

    local function FormatNum(n)
        n = tonumber(n) or 0
        if n >= 1000000 then
            return string.format("%.1fm", n / 1000000)
        elseif n >= 1000 then
            return string.format("%.1fk", n / 1000)
        end
        return tostring(math.floor(n + 0.5))
    end

    -- Renders "1842" or "1842(+15)" — "—" when the API hasn't populated yet.
    -- Values are floored: this client's string.format errors on %d with a float.
    local function FormatRated(base, change)
        base = tonumber(base)
        if not base or base == 0 then return "—" end
        base = math.floor(base + 0.5)
        change = tonumber(change)
        if change and change ~= 0 then
            return string.format("%d(%+d)", base, math.floor(change + 0.5))
        end
        return tostring(base)
    end

    local function BuildScoreboardLines()
        local lines = {}
        if not GetNumBattlefieldScores then
            lines[#lines + 1] = "|cffff4444GetNumBattlefieldScores API unavailable on this client.|r"
            return lines
        end
        local rows = GetScoreboardRows()
        lines[#lines + 1] = string.format("|cffF6C86B%-2s %-16s %4s %3s %8s %8s %11s %11s|r",
            "#", "Name", "KB", "D", "Damage", "Healing", "Rating", "MMR")
        if #rows == 0 then
            lines[#lines + 1] = "|cff888888No scoreboard data — only available during/after a match. Hit [refresh].|r"
        end
        for i, r in ipairs(rows) do
            local color = "ffffffff"
            local cc = r.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.classToken]
            if cc then
                color = cc.colorStr or string.format("ff%02x%02x%02x",
                    math.floor(cc.r * 255 + 0.5), math.floor(cc.g * 255 + 0.5), math.floor(cc.b * 255 + 0.5))
            end
            local stripped = StripRealm and StripRealm(r.name) or r.name
            lines[#lines + 1] = string.format("|cff888888%-2d|r |c%s%-16.16s|r %4d %3d %8s %8s %11s %11s",
                i, color, stripped, math.floor((tonumber(r.kb) or 0) + 0.5), math.floor((tonumber(r.deaths) or 0) + 0.5),
                FormatNum(r.damage), FormatNum(r.healing),
                FormatRated(r.rating, r.ratingChange), FormatRated(r.mmr, r.mmrChange))
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff888888Updated " .. date("%H:%M:%S") .. " — ranked by damage done.|r"
        return lines
    end

    local function ToggleScoreboard()
        if sbFrame then
            if sbFrame:IsShown() then
                sbFrame:Hide()
            else
                sbFrame:Show()
                sbFrame.Render()
            end
            return
        end

        sbFrame = CreateFrame("Frame", "TrinketedScoreboardDebug", UIParent, "BackdropTemplate")
        sbFrame:SetSize(620, 320)
        sbFrame:SetPoint("CENTER")
        sbFrame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        sbFrame:SetBackdropColor(0, 0, 0, 0.85)
        sbFrame:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)
        sbFrame:SetMovable(true)
        sbFrame:EnableMouse(true)
        sbFrame:RegisterForDrag("LeftButton")
        sbFrame:SetScript("OnDragStart", sbFrame.StartMoving)
        sbFrame:SetScript("OnDragStop", sbFrame.StopMovingOrSizing)
        sbFrame:SetFrameStrata("HIGH")

        local title = sbFrame:CreateFontString(nil, "OVERLAY")
        title:SetFont(lib.FONT_DISPLAY, 10, "")
        title:SetPoint("TOPLEFT", 6, -4)
        title:SetText("|cffE8B923Scoreboard Debug|r  (live match leaderboard)")
        title:SetTextColor(C.textBright and C.textBright[1] or 1, C.textBright and C.textBright[2] or 1, C.textBright and C.textBright[3] or 1)

        local closeBtn = CreateFrame("Button", nil, sbFrame)
        closeBtn:SetSize(16, 16)
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY")
        closeBtn.text:SetFont(lib.FONT_MONO, 12, "")
        closeBtn.text:SetPoint("CENTER")
        closeBtn.text:SetText("x")
        closeBtn.text:SetTextColor(0.6, 0.6, 0.6)
        closeBtn:SetScript("OnClick", function() sbFrame:Hide() end)

        local refreshBtn = CreateFrame("Button", nil, sbFrame)
        refreshBtn:SetSize(60, 14)
        refreshBtn:SetPoint("TOPRIGHT", -22, -4)
        refreshBtn.text = refreshBtn:CreateFontString(nil, "OVERLAY")
        refreshBtn.text:SetFont(lib.FONT_MONO, 8, "")
        refreshBtn.text:SetPoint("CENTER")
        refreshBtn.text:SetText("[refresh]")
        refreshBtn.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        refreshBtn:SetScript("OnClick", function()
            if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
            sbFrame.Render()
        end)

        local scroll = CreateFrame("ScrollFrame", nil, sbFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 4, -18)
        scroll:SetPoint("BOTTOMRIGHT", -24, 4)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(580)
        content:SetHeight(1)
        scroll:SetScrollChild(content)

        sbFrame.lines = {}
        local LINE_H = 13

        local function Render()
            local lines = BuildScoreboardLines()
            for i, text in ipairs(lines) do
                local fs = sbFrame.lines[i]
                if not fs then
                    fs = content:CreateFontString(nil, "OVERLAY")
                    fs:SetFont(lib.FONT_MONO, 9, "")
                    fs:SetPoint("TOPLEFT", 2, -((i - 1) * LINE_H))
                    fs:SetPoint("RIGHT", -2, 0)
                    fs:SetJustifyH("LEFT")
                    sbFrame.lines[i] = fs
                end
                fs:SetText(text)
                fs:Show()
            end
            for i = #lines + 1, #sbFrame.lines do
                sbFrame.lines[i]:SetText("")
                sbFrame.lines[i]:Hide()
            end
            content:SetHeight(math.max(1, #lines * LINE_H))
        end
        sbFrame.Render = Render

        sbFrame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
        sbFrame:RegisterEvent("PVP_MATCH_COMPLETE")
        sbFrame:SetScript("OnEvent", function()
            if sbFrame:IsShown() then Render() end
        end)

        if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
        Render()
        sbFrame:Show()
        print("|cffE8B923Trinketed:|r Scoreboard debug window opened. Toggle with /trinketed sbdebug")
    end

    lib:RegisterSubCommand("sbdebug", ToggleScoreboard)
    lib:RegisterSubCommand("scoreboard", ToggleScoreboard)

end

---------------------------------------------------------------------------
-- Register with Trinketed Options Panel
---------------------------------------------------------------------------
local settingsBuilt = false

lib:RegisterSubAddon("History", {
    order = 2,
    desc = "Match history, session and team stats, enemy tracking, and full match replays.",
    OnSelect = function(contentFrame)
        -- Build settings tab content on first open (after SavedVariables are loaded)
        if not settingsBuilt then
            settingsBuilt = true
            local y = -20
            y = lib:CreateSectionHeader(settingsContainer, y, "TIMESTAMP OVERLAY")

            lib:CreateCheckbox(settingsContainer, 20, y, "Show timestamp when in queue",
                TrinketedHistoryDB.settings.showTimestamp, function(isOn)
                    TrinketedHistoryDB.settings.showTimestamp = isOn
                    UpdateOverlayVisibility()
                end)

        end

        -- Embed the history content directly in the options panel
        historyContent:SetParent(contentFrame)
        historyContent:ClearAllPoints()
        historyContent:SetAllPoints(contentFrame)

        -- Refresh data every time the content frame is shown (tab selected or panel re-opened)
        contentFrame:HookScript("OnShow", function()
            -- Re-query the season and default every tab's season filter to it.
            -- At login the API often still returns 0 (season data loads late),
            -- so the value cached at file scope can be stale.
            seasonDefault:Apply()
            historyContent:Show()
            RefreshActiveTab()
        end)
    end,
})

RegisterSubCommands()
