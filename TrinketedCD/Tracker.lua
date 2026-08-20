---------------------------------------------------------------------------
-- TrinketedCD: Tracker.lua
-- Combat log parsing, player scanning, cooldown state management
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD

---------------------------------------------------------------------------
-- Player Scanning
---------------------------------------------------------------------------
function addon:ScanPartyMembers()
    if addon.state.testMode then return end

    -- Hide in raids (any size) unless we're in an arena instance
    local inArenaInstance = (select(2, IsInInstance()) == "arena")
    if IsInRaid() and not inArenaInstance then
        for guid, info in pairs(self.state.trackedPlayers) do
            if info.team == "party" and not tostring(guid):match("^test_") then
                self.state.trackedPlayers[guid] = nil
                self.state.guidMap[guid] = nil
                self:DestroyBar(guid)
            end
        end
        for i = 1, 4 do
            self.state.unitMap["party" .. i] = nil
        end
        wipe(self.state.petOwnerMap)
        return
    end

    -- Build new set of party members, preserving existing state
    local newGUIDs = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid then newGUIDs[guid] = { unit = unit, slot = i } end
        end
    end

    -- Remove old party entries that are no longer in the group (preserve test players)
    local toRemove = {}
    for guid, info in pairs(self.state.trackedPlayers) do
        if info.team == "party" and not tostring(guid):match("^test_") and not newGUIDs[guid] then
            toRemove[#toRemove + 1] = guid
        end
    end
    for _, guid in ipairs(toRemove) do
        self.state.trackedPlayers[guid] = nil
        self.state.guidMap[guid] = nil
    end

    -- Clear party unit mappings (will be re-set below)
    for i = 1, 4 do
        self.state.unitMap["party" .. i] = nil
    end

    -- Add or update party members, preserving cooldowns/spec for existing entries
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local name = self:StripRealm(UnitName(unit))
            local _, className = UnitClass(unit)
            local race = UnitRace(unit)
            if guid and name and className then
                local formatted = self:FormatClassName(className)
                local existing = self.state.trackedPlayers[guid]
                if existing and existing.team == "party" then
                    -- Preserve cooldowns and spec, update unit/slot/name
                    existing.unit = unit
                    existing.slot = i
                    existing.name = name
                    existing.race = race
                    self:Debug("Party updated: " .. name .. " (" .. formatted .. ") slot " .. i)
                else
                    self.state.trackedPlayers[guid] = {
                        name      = name,
                        class     = formatted,
                        race      = race,
                        team      = "party",
                        slot      = i,
                        unit      = unit,
                        cooldowns = {},
                    }
                    self:Debug("Party scanned: " .. name .. " (" .. formatted .. ") slot " .. i)
                end
                self.state.guidMap[guid] = guid
                self.state.unitMap[unit] = guid
            end
        end
    end
end

-- Map pet GUIDs to their owner GUIDs for pet ability tracking
function addon:ScanPetOwners()
    wipe(self.state.petOwnerMap)

    -- Party pets
    for i = 1, 4 do
        local petUnit = "partypet" .. i
        local ownerUnit = "party" .. i
        if UnitExists(petUnit) and UnitExists(ownerUnit) then
            local petGUID = UnitGUID(petUnit)
            local ownerGUID = UnitGUID(ownerUnit)
            if petGUID and ownerGUID then
                self.state.petOwnerMap[petGUID] = ownerGUID
            end
        end
    end

end

-- Resolve a pet GUID to its owner; falls back to a live partypet scan if the
-- cached map is stale (covers races between a pet cast and UNIT_PET firing).
function addon:ResolvePetOwner(petGUID)
    if not petGUID then return nil end
    local owner = self.state.petOwnerMap[petGUID]
    if owner then return owner end
    for i = 1, 4 do
        local petUnit = "partypet" .. i
        if UnitExists(petUnit) and UnitGUID(petUnit) == petGUID then
            local ownerGUID = UnitGUID("party" .. i)
            if ownerGUID then
                self.state.petOwnerMap[petGUID] = ownerGUID
                return ownerGUID
            end
        end
    end
    return nil
end

-- Try to discover an unknown GUID by checking party units
function addon:TryDiscoverPlayer(guid)
    if not guid or self.state.guidMap[guid] then return end

    -- Check party units
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            local name = self:StripRealm(UnitName(unit))
            local _, className = UnitClass(unit)
            local race = UnitRace(unit)
            if name and className then
                local formatted = self:FormatClassName(className)
                self.state.trackedPlayers[guid] = {
                    name      = name,
                    class     = formatted,
                    race      = race,
                    team      = "party",
                    slot      = i,
                    unit      = unit,
                    cooldowns = {},
                }
                self.state.guidMap[guid] = guid
                self.state.unitMap[unit] = guid
                self:Debug("Discovered party: " .. name .. " (" .. formatted .. ")")
                self:CreateBar(guid)
                self:UpdatePlayerBar(guid)
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Spell Utility Functions
---------------------------------------------------------------------------
function addon:SpellMatchesClass(spellName, playerClass)
    local cdData = self.COOLDOWN_DB[spellName]
    if not cdData then return false end
    for _, class in ipairs(cdData.classes) do
        if class == "ALL" or class == playerClass then
            return true
        end
    end
    return false
end

function addon:SpellMatchesRace(spellName, playerRace)
    local cdData = self.COOLDOWN_DB[spellName]
    if not cdData then return true end
    if not cdData.races then return true end
    if not playerRace then return false end
    for _, race in ipairs(cdData.races) do
        if race == playerRace then
            return true
        end
    end
    return false
end

function addon:IsUniversalSpell(spellName)
    local cdData = self.COOLDOWN_DB[spellName]
    if not cdData then return false end
    for _, c in ipairs(cdData.classes) do
        if c == "ALL" then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Grid System
---------------------------------------------------------------------------

-- Category sort order for default grid generation
local CATEGORY_SORT_ORDER = {
    trinket = 1, major_defensive = 2, cc_break = 3,
    major_offensive = 4, interrupt = 5,
}

-- Build a racial lookup: raceName -> spellName
function addon:ResolveRacialForRace(raceName)
    if not raceName then return nil end
    for spellName, data in pairs(self.COOLDOWN_DB) do
        if data.races then
            local isUniversal = false
            for _, c in ipairs(data.classes) do
                if c == "ALL" then isUniversal = true; break end
            end
            if isUniversal then
                for _, r in ipairs(data.races) do
                    if r == raceName then return spellName end
                end
            end
        end
    end
    return nil
end

-- Resize a grid preserving each cell's visual (row, col) position.
-- New rows/columns get empty slots; removed rows/columns send spells to pool.
function addon:ResizeGrid(grid, newRows, newCols)
    local oldRows = grid.rows or 3
    local oldCols = grid.cols or 4
    if newRows == oldRows and newCols == oldCols then return end

    -- Read current grid as 2D
    local cells = {}
    local disabledCells = {}
    for r = 1, oldRows do
        for c = 1, oldCols do
            local idx = (r - 1) * oldCols + c
            cells[(r - 1) * 1000 + c] = grid.slots[idx] or ""
            disabledCells[(r - 1) * 1000 + c] = grid.disabled[idx]
        end
    end

    -- Build new linear slots preserving positions
    if not grid.removed then grid.removed = {} end
    local newSlots = {}
    local newDisabled = {}
    for r = 1, newRows do
        for c = 1, newCols do
            local idx = (r - 1) * newCols + c
            local key = (r - 1) * 1000 + c
            if r <= oldRows and c <= oldCols then
                newSlots[idx] = cells[key]
                newDisabled[idx] = disabledCells[key]
            else
                newSlots[idx] = ""
            end
        end
    end

    -- Mark displaced spells as removed so they stay in the pool
    for r = 1, oldRows do
        for c = 1, oldCols do
            if r > newRows or c > newCols then
                local spell = cells[(r - 1) * 1000 + c]
                if spell and spell ~= "" then
                    grid.removed[spell] = true
                end
            end
        end
    end

    grid.rows = newRows
    grid.cols = newCols
    grid.slots = newSlots
    grid.disabled = newDisabled
end

-- Generate a default grid for a class+team from COOLDOWN_DB defaults
function addon:GenerateDefaultGrid(className, team)
    local spells = {}
    for spellName, data in pairs(self.COOLDOWN_DB) do
        if data.enabled then
            -- Skip ALL-class spells (trinket/racials handled as placeholders)
            local isClassSpecific = false
            for _, c in ipairs(data.classes) do
                if c == className then isClassSpecific = true; break end
            end
            if isClassSpecific then
                spells[#spells + 1] = { name = spellName, data = data }
            end
        end
    end

    -- Sort by category order then priority
    table.sort(spells, function(a, b)
        local ca = CATEGORY_SORT_ORDER[a.data.category] or 99
        local cb = CATEGORY_SORT_ORDER[b.data.category] or 99
        if ca ~= cb then return ca < cb end
        local pa = a.data.priority or 999
        local pb = b.data.priority or 999
        if pa ~= pb then return pa < pb end
        return a.name < b.name
    end)

    local slots = { "PvP Trinket", "Racial" }
    for _, s in ipairs(spells) do
        slots[#slots + 1] = s.name
    end

    -- Use fixed team grid dimensions
    local gridCols = self.db.party.gridCols or 4
    local gridRows = self.db.party.gridRows or 3

    -- Pad slots to fill rows * cols (overflow spells stay in pool)
    local total = gridRows * gridCols
    while #slots < total do
        slots[#slots + 1] = ""
    end
    -- Truncate if more spells than grid slots (extras go to pool)
    if #slots > total then
        for i = total + 1, #slots do
            slots[i] = nil
        end
    end

    local grid = {
        rows = gridRows,
        cols = gridCols,
        slots = slots,
        disabled = {},
    }
    return grid
end

-- Get (or auto-generate) the grid for a class+team
function addon:GetClassGrid(className, team)
    if not self.db then return nil end
    local grids = self.db.cooldowns.grids
    if not grids[className] then
        grids[className] = {}
    end
    if not grids[className][team] then
        grids[className][team] = self:GenerateDefaultGrid(className, team)
    end
    local grid = grids[className][team]
    -- Ensure removed set exists
    if grid and not grid.removed then
        grid.removed = {}
    end
    -- Migrate: inject newly-added enabled spells into existing grids
    if grid then
        local existing = {}
        for _, slot in ipairs(grid.slots) do
            if slot ~= "" then existing[slot] = true end
        end
        local added = false
        for spellName, data in pairs(self.COOLDOWN_DB) do
            if data.enabled and not existing[spellName] and not grid.removed[spellName] then
                local isClassSpecific = false
                for _, c in ipairs(data.classes) do
                    if c == className then isClassSpecific = true; break end
                end
                if isClassSpecific then
                    -- Find an empty slot or append
                    local placed = false
                    for i, slot in ipairs(grid.slots) do
                        if slot == "" then
                            grid.slots[i] = spellName
                            placed = true
                            break
                        end
                    end
                    if not placed then
                        grid.slots[#grid.slots + 1] = spellName
                        added = true
                    end
                end
            end
        end
        -- Expand grid rows if new spells were appended beyond current capacity
        if added and grid.cols then
            grid.rows = math.ceil(#grid.slots / grid.cols)
            while #grid.slots < grid.rows * grid.cols do
                grid.slots[#grid.slots + 1] = ""
            end
        end
    end
    -- Migrate old grids that used 'size' (NxN) to rows+cols
    if grid and not grid.rows then
        local n = grid.size or grid.cols or 4
        grid.cols = n
        grid.rows = math.ceil(#grid.slots / n)
        if grid.rows < 1 then grid.rows = 1 end
        grid.size = nil
        -- Pad slots to fill rows*cols
        local total = grid.rows * grid.cols
        while #grid.slots < total do
            grid.slots[#grid.slots + 1] = ""
        end
    end
    -- Enforce fixed team grid dimensions
    if grid then
        local teamCols = self.db.party.gridCols or 4
        local teamRows = self.db.party.gridRows or 3
        if grid.cols ~= teamCols or grid.rows ~= teamRows then
            self:ResizeGrid(grid, teamRows, teamCols)
        end
    end
    return grid
end

-- Check if a spell is in the grid (and not disabled)
-- Handles "Racial" placeholder: if spellName is a racial ability, matches "Racial" slot
function addon:IsSpellEnabled(spellName, team, className)
    if not self.db or not className then return true end
    local grid = self:GetClassGrid(className, team)
    if not grid then return true end
    for i, slot in ipairs(grid.slots) do
        if slot == spellName then
            return not grid.disabled[i]
        elseif slot == "Racial" then
            -- Check if spellName is a racial ability (ALL-class + has races)
            local cdData = self.COOLDOWN_DB[spellName]
            if cdData and cdData.races then
                local isUniversal = false
                for _, c in ipairs(cdData.classes) do
                    if c == "ALL" then isUniversal = true; break end
                end
                if isUniversal then
                    return not grid.disabled[i]
                end
            end
        end
    end
    return false
end

-- Check if spell occupies a grid slot
function addon:IsSpellInGrid(spellName, team, className)
    local grid = self:GetClassGrid(className, team)
    if not grid then return false end
    for _, slot in ipairs(grid.slots) do
        if slot == spellName then return true end
    end
    return false
end

-- Get enabled spells for a class from the grid, resolving placeholders
function addon:GetEnabledSpellsForClass(className, raceName, team)
    local grid = self:GetClassGrid(className, team)
    if not grid then return {} end

    local result = {}
    for i, slot in ipairs(grid.slots) do
        if slot ~= "" and not grid.disabled[i] then
            local resolvedName = slot
            if slot == "Racial" then
                resolvedName = self:ResolveRacialForRace(raceName)
            end
            if resolvedName and self.COOLDOWN_DB[resolvedName] then
                result[#result + 1] = resolvedName
            end
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Spec Detection
---------------------------------------------------------------------------
function addon:DetectSpec(guid, playerInfo, spellName)
    if not self.SPEC_MARKERS then return end
    local marker = self.SPEC_MARKERS[spellName]
    if not marker then return end
    if marker.class ~= playerInfo.class then return end
    if playerInfo.spec == marker.spec then return end
    local isFirstDetection = (playerInfo.spec == nil)
    playerInfo.spec = marker.spec
    self:Debug("Spec detected: " .. playerInfo.name .. " = " .. playerInfo.class .. " (" .. marker.spec .. ")")
    -- Refresh bar on first detection to apply spec filtering
    if isFirstDetection and guid then
        self:UpdatePlayerBar(guid)
    end
end

---------------------------------------------------------------------------
-- Cooldown Reset Handler
---------------------------------------------------------------------------
function addon:HandleCooldownResets(guid, playerInfo, cdData, spellName)
    if not cdData.resets then return end
    local didReset = false
    for _, resetSpell in ipairs(cdData.resets) do
        if playerInfo.cooldowns[resetSpell] then
            playerInfo.cooldowns[resetSpell] = nil
            didReset = true
            self:Debug("CD reset: " .. playerInfo.name .. " - " .. resetSpell .. " (by " .. spellName .. ")")
        end
    end
    if didReset then
        self:UpdatePlayerBar(guid)
    end
end

---------------------------------------------------------------------------
-- Cooldown State Management
---------------------------------------------------------------------------
function addon:StartCooldown(guid, spellName, cdData)
    local playerInfo = self.state.trackedPlayers[guid]
    if not playerInfo then return end

    -- Determine effective duration (may be reduced by talent)
    local duration = cdData.duration
    if playerInfo.spec and self.TALENT_CD_ADJUSTMENTS then
        local classAdj = self.TALENT_CD_ADJUSTMENTS[playerInfo.class]
        if classAdj then
            local specAdj = classAdj[playerInfo.spec]
            if specAdj and specAdj[spellName] then
                duration = specAdj[spellName]
                self:Debug("Talent-adjusted CD: " .. spellName .. " " .. cdData.duration .. "s -> " .. duration .. "s")
            end
        end
    end

    local now = GetTime()
    playerInfo.cooldowns[spellName] = {
        startTime      = now,
        duration       = duration,
        expirationTime = now + duration,
        spellID        = cdData.spellID,
        category       = cdData.category,
        buffExpires    = cdData.buffDuration and (now + cdData.buffDuration) or nil,
    }

    self:Debug("CD started: " .. playerInfo.name .. " - " .. spellName .. " (" .. duration .. "s)")

    -- Handle shared cooldowns (e.g., Human racial shares CD with PvP Trinket)
    local sharedList = cdData.sharedCD
    if sharedList then
        if type(sharedList) == "string" then sharedList = { sharedList } end
        for _, sharedName in ipairs(sharedList) do
            local sharedData = self.COOLDOWN_DB[sharedName]
            if sharedData and self:IsSpellEnabled(sharedName, playerInfo.team, playerInfo.class) then
                local sharedDur = cdData.sharedCDDuration or duration
                -- Only apply shared CD if it would be longer than current remaining
                local existing = playerInfo.cooldowns[sharedName]
                if not existing or (now + sharedDur) > existing.expirationTime then
                    playerInfo.cooldowns[sharedName] = {
                        startTime      = now,
                        duration       = sharedDur,
                        expirationTime = now + sharedDur,
                        spellID        = sharedData.spellID,
                        category       = sharedData.category,
                    }
                    self:Debug("  Shared CD: " .. sharedName .. " (" .. sharedDur .. "s)")
                end
            end
        end
    end

    -- Update display
    self:UpdatePlayerBar(guid)

    -- Flash effect on use (after UpdatePlayerBar ensures icon exists)
    if self.db and self.db.general.showFlashOnUse then
        local icon = self.icons[guid] and self.icons[guid][spellName]
        if icon then
            self:PlayUseFlash(icon)
        end
    end
end

function addon:ClearAllCooldowns()
    for guid, info in pairs(self.state.trackedPlayers) do
        wipe(info.cooldowns)
    end
    self:RefreshAllBars()
end

---------------------------------------------------------------------------
-- Cooldown Expiry Notifications (glow effect + sound alert)
---------------------------------------------------------------------------
function addon:OnCooldownExpired(guid, spellName, cdInfo)
    local playerInfo = self.state.trackedPlayers[guid]
    if not playerInfo or not self.db then return end

    -- Play glow effect on the icon (skip in compact mode - icon will be hidden)
    if self.db.general.showGlowOnReady and not self.db.general.compactMode then
        local icon = self.icons[guid] and self.icons[guid][spellName]
        if icon and icon:IsShown() then
            self:PlayReadyGlow(icon)
        end
    end

end

---------------------------------------------------------------------------
-- Combat Log Handler
---------------------------------------------------------------------------
function addon:OnCombatLogEvent()
    local outsideOk = self.db and self.db.general.trackOutsideArena and not IsInRaid()
    if not self.state.inArena and not self.state.testMode and not outsideOk then return end

    local _, eventType, _, sourceGUID, sourceName, sourceFlags, _,
          destGUID, destName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()

    -- Accept cast, aura, and damage events for tracking
    if eventType ~= "SPELL_CAST_SUCCESS" and eventType ~= "SPELL_AURA_APPLIED"
       and eventType ~= "SPELL_AURA_REMOVED" then return end
    if not sourceGUID or not spellName then return end

    -- Debug: log aura events on tracked players to identify passive procs
    if eventType == "SPELL_AURA_APPLIED" and destGUID then
        local destInfo = self.state.trackedPlayers[destGUID]
        if destInfo and destInfo.class == "Rogue" then
            self:Debug("AURA on " .. (destInfo.name or "?") .. ": " .. spellName .. " (ID:" .. (spellID or "?") .. ") src=" .. (sourceName or "?"))
        end
    end

    -- Resolve pet abilities to their owner
    local resolvedGUID = sourceGUID
    local ownerGUID = self:ResolvePetOwner(sourceGUID)
    if ownerGUID then
        resolvedGUID = ownerGUID
    end

    -- Spec detection for tracked players (cheap check, runs on both event types)
    local playerInfo = self.state.trackedPlayers[resolvedGUID]
    if playerInfo then
        self:DetectSpec(resolvedGUID, playerInfo, spellName)
    end

    -- Check if this spell is in our cooldown database (before event filter, for trackEvent support)
    local cdData = self.COOLDOWN_DB[spellName]

    -- Buff removed early (dispel, cancel, etc.) — clear active glow
    if eventType == "SPELL_AURA_REMOVED" then
        if cdData and cdData.buffDuration and destGUID then
            local destInfo = self.state.trackedPlayers[destGUID]
            if destInfo and destInfo.cooldowns[spellName] then
                destInfo.cooldowns[spellName].buffExpires = nil
            end
        end
        return
    end

    -- Filter event type: SPELL_CAST_SUCCESS for normal CDs, or matching trackEvent for ICD-style abilities
    if eventType == "SPELL_CAST_SUCCESS" then
        -- Normal path
    elseif cdData and cdData.trackEvent == eventType then
        -- Aura-triggered ICD (e.g. Cheat Death proc): use destGUID (buff recipient)
        resolvedGUID = destGUID
        playerInfo = self.state.trackedPlayers[resolvedGUID]
    else
        return
    end

    if not playerInfo then
        -- Try to discover via arena/party units
        self:TryDiscoverPlayer(resolvedGUID)
        playerInfo = self.state.trackedPlayers[resolvedGUID]
        if not playerInfo then return end
    end

    if not cdData then return end

    -- Check class match
    if not self:SpellMatchesClass(spellName, playerInfo.class) then return end

    -- Handle cooldown resets (before enabled check - resets are a game mechanic)
    self:HandleCooldownResets(resolvedGUID, playerInfo, cdData, spellName)

    -- Check if spell is enabled for this team (grid-based)
    if not self:IsSpellEnabled(spellName, playerInfo.team, playerInfo.class) then return end

    -- Start tracking the cooldown
    self:StartCooldown(resolvedGUID, spellName, cdData)
end

---------------------------------------------------------------------------
-- Unit Spellcast Handler (more reliable for party members)
---------------------------------------------------------------------------
function addon:OnUnitSpellcast(unit, castGUID, spellID)
    if not unit or not spellID then return end
    -- Only process party units
    if not unit:match("^party%d$") then return end
    local outsideOk = self.db and self.db.general.trackOutsideArena and not IsInRaid()
    if not self.state.inArena and not self.state.testMode and not outsideOk then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    local playerInfo = self.state.trackedPlayers[guid]
    if not playerInfo then return end

    -- WoW 11.0+ moved GetSpellInfo to C_Spell.GetSpellInfo (returns table)
    local spellName
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        spellName = info and info.name
    elseif GetSpellInfo then
        spellName = GetSpellInfo(spellID)
    end
    if not spellName then return end

    -- Spec detection for party members
    self:DetectSpec(guid, playerInfo, spellName)

    local cdData = self.COOLDOWN_DB[spellName]
    if not cdData then return end

    if not self:SpellMatchesClass(spellName, playerInfo.class) then return end

    -- Handle cooldown resets (before enabled check)
    self:HandleCooldownResets(guid, playerInfo, cdData, spellName)

    if not self:IsSpellEnabled(spellName, playerInfo.team, playerInfo.class) then return end

    self:StartCooldown(guid, spellName, cdData)
end

---------------------------------------------------------------------------
-- OnUpdate Ticker for Cooldown Expiration
---------------------------------------------------------------------------
function addon:InitTracker()
    local ticker = CreateFrame("Frame", "TrinketedCDTicker", UIParent)
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0

        local now = GetTime()
        for guid, info in pairs(addon.state.trackedPlayers) do
            -- Collect expired cooldowns first to avoid mutating table during pairs()
            local expired = nil
            for spellName, cd in pairs(info.cooldowns) do
                if now >= cd.expirationTime then
                    expired = expired or {}
                    expired[#expired + 1] = { name = spellName, cd = cd }
                end
            end
            if expired then
                for _, entry in ipairs(expired) do
                    addon:OnCooldownExpired(guid, entry.name, entry.cd)
                    info.cooldowns[entry.name] = nil
                end
                addon:UpdatePlayerBar(guid)
            end
        end

        -- Update active glow and low-timer pulse on all visible icons
        addon:UpdateTimerTexts()
    end)
end
