---------------------------------------------------------------------------
-- TrinketedCD: TestMode.lua
-- Fake player creation, cooldown simulation for development and positioning
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD

---------------------------------------------------------------------------
-- Default Test Configuration
---------------------------------------------------------------------------
local DEFAULT_TEST_PLAYERS = {
    { team = "party", class = "Warrior",  race = "Human",     slot = 1 },
    { team = "party", class = "Priest",   race = "Dwarf",     slot = 2 },
    { team = "party", class = "Paladin",  race = "Human",     slot = 3 },
    { team = "party", class = "Druid",    race = "Night Elf", slot = 4 },
}

---------------------------------------------------------------------------
-- Toggle Test Mode
---------------------------------------------------------------------------
function addon:ToggleTestMode()
    self.state.testMode = not self.state.testMode

    if self.state.testMode then
        self:Print("Test mode |cff00ff00ENABLED|r")
        self:Print("  Left-click cooldown icons to simulate usage")
        self:Print("  Use /trinketed cd to configure test players")

        -- Stash real players so test players can take their slots
        self.state.stashedPlayers = {}
        for guid, info in pairs(self.state.trackedPlayers) do
            self.state.stashedPlayers[guid] = info
        end
        for guid in pairs(self.state.stashedPlayers) do
            self.state.trackedPlayers[guid] = nil
            self.state.guidMap[guid] = nil
            if self.state.unitMap then
                for unit, mapped in pairs(self.state.unitMap) do
                    if mapped == guid then
                        self.state.unitMap[unit] = nil
                    end
                end
            end
            self:DestroyBar(guid)
        end

        self:CreateTestPlayers()
        self:ShowBlizzardPartyFrames()
        self:RefreshAllBars()
    else
        self:Print("Test mode |cffff0000DISABLED|r")
        self:HideBlizzardPartyFrames()
        self:ClearTestPlayers()

        -- Restore real players
        if self.state.stashedPlayers then
            for guid, info in pairs(self.state.stashedPlayers) do
                self.state.trackedPlayers[guid] = info
                self.state.guidMap[guid] = guid
                if info.unit then
                    self.state.unitMap[info.unit] = guid
                end
            end
            self.state.stashedPlayers = nil
        end

        self:RefreshAllBars()
    end

    -- Sync test mode toggle in options panel
    if self._testToggle and self._testToggle.SetChecked then
        self._testToggle:SetChecked(self.state.testMode)
    end
end

---------------------------------------------------------------------------
-- Create Test Players
---------------------------------------------------------------------------
function addon:CreateTestPlayers()
    local testConfig = self.db and self.db.testMode.lastPlayers
    if not testConfig or #testConfig == 0 then
        testConfig = DEFAULT_TEST_PLAYERS
        if self.db then
            self.db.testMode.lastPlayers = {}
            for i, tp in ipairs(DEFAULT_TEST_PLAYERS) do
                self.db.testMode.lastPlayers[i] = {
                    team  = tp.team,
                    class = tp.class,
                    race  = tp.race,
                    slot  = tp.slot,
                }
            end
        end
    elseif #testConfig < #DEFAULT_TEST_PLAYERS and self.db then
        -- Migrate: fill in new default slots for 5v5 support
        for i = #testConfig + 1, #DEFAULT_TEST_PLAYERS do
            local tp = DEFAULT_TEST_PLAYERS[i]
            self.db.testMode.lastPlayers[i] = {
                team  = tp.team,
                class = tp.class,
                race  = tp.race,
                slot  = tp.slot,
            }
        end
        testConfig = self.db.testMode.lastPlayers
    end

    -- Team/slot is determined by index position, not saved data
    local SLOT_TEAMS = { "party", "party", "party", "party" }
    local SLOT_NUMS  = { 1, 2, 3, 4 }

    for i, tp in ipairs(testConfig) do
        local team = SLOT_TEAMS[i] or "party"
        local slot = SLOT_NUMS[i] or i
        local guid = "test_" .. i

        -- Fix saved data if team/slot drifted from old layout
        if self.db and tp.team ~= team then
            tp.team = team
            tp.slot = slot
        end

        self.state.trackedPlayers[guid] = {
            name      = "Party " .. slot,
            class     = tp.class,
            race      = tp.race,
            team      = team,
            slot      = slot,
            unit      = "party" .. slot,
            cooldowns = {},
        }
        self.state.guidMap[guid] = guid
    end

    self:Debug("Created " .. #testConfig .. " test players")
end

---------------------------------------------------------------------------
-- Clear Test Players
---------------------------------------------------------------------------
function addon:ClearTestPlayers()
    local toRemove = {}
    for guid in pairs(self.state.trackedPlayers) do
        if tostring(guid):match("^test_") then
            table.insert(toRemove, guid)
        end
    end

    for _, guid in ipairs(toRemove) do
        self.state.trackedPlayers[guid] = nil
        self.state.guidMap[guid] = nil
        self:DestroyBar(guid)
    end
end

---------------------------------------------------------------------------
-- Blizzard Party Frame Visibility (for test mode anchoring)
---------------------------------------------------------------------------

-- When solo, Blizzard party frames are hidden so FindUnitFrame() can't
-- discover them. Following OmniCD's approach: force the real Blizzard compact
-- unit frames visible during test mode so bars can anchor to them naturally.

function addon:ShowBlizzardPartyFrames()
    if not self.db or not self.db.party.anchorToFrames then return end
    if InCombatLockdown() then return end

    -- Don't show if already visible (player is in a real party)
    if CompactRaidFrameContainer and CompactRaidFrameContainer:IsVisible() then
        return
    end

    if CompactRaidFrameManager and CompactRaidFrameContainer then
        CompactRaidFrameManager:Show()
        CompactRaidFrameContainer:Show()
        self.state.shownBlizzardFrames = true
        self:Debug("Forced Blizzard compact party frames visible for test mode")
    end
end

function addon:HideBlizzardPartyFrames()
    if not self.state.shownBlizzardFrames then return end

    if InCombatLockdown() then
        -- Defer hiding until combat ends
        if not self._hideFramesOnRegen then
            self._hideFramesOnRegen = CreateFrame("Frame")
            self._hideFramesOnRegen:SetScript("OnEvent", function(f)
                f:UnregisterEvent("PLAYER_REGEN_ENABLED")
                addon:HideBlizzardPartyFrames()
            end)
        end
        self._hideFramesOnRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    if CompactRaidFrameManager and CompactRaidFrameContainer then
        CompactRaidFrameManager:Hide()
        CompactRaidFrameContainer:Hide()
    end

    self.state.shownBlizzardFrames = nil
    self:Debug("Hidden Blizzard compact party frames after test mode")
end

---------------------------------------------------------------------------
-- Simulate Cooldown (toggle on/off)
---------------------------------------------------------------------------
function addon:SimulateCooldown(guid, spellName)
    if not self.state.testMode then return end

    local info = self.state.trackedPlayers[guid]
    if not info then return end

    local cdData = self.COOLDOWN_DB[spellName]
    if not cdData then return end

    -- Toggle: if already on CD, clear it; otherwise start it
    if info.cooldowns[spellName] then
        info.cooldowns[spellName] = nil
        self:Debug("Test CD cleared: " .. spellName)
    else
        self:StartCooldown(guid, spellName, cdData)
        self:Debug("Test CD started: " .. spellName)
    end

    self:UpdatePlayerBar(guid)
end

---------------------------------------------------------------------------
-- Simulate All Cooldowns for All Test Players
---------------------------------------------------------------------------
function addon:SimulateAllCooldowns()
    if not self.state.testMode then
        self:Print("Enable test mode first! (/trinketed test)")
        return
    end

    for guid, info in pairs(self.state.trackedPlayers) do
        if tostring(guid):match("^test_") then
            local spells = self:GetEnabledSpellsForClass(info.class, info.race, info.team)
            for _, spellName in ipairs(spells) do
                local cdData = self.COOLDOWN_DB[spellName]
                if cdData and not info.cooldowns[spellName] then
                    self:StartCooldown(guid, spellName, cdData)
                end
            end
        end
    end

    self:RefreshAllBars()
    self:Print("All test cooldowns simulated.")
end

---------------------------------------------------------------------------
-- Clear All Test Cooldowns
---------------------------------------------------------------------------
function addon:ClearAllTestCooldowns()
    if not self.state.testMode then return end

    for guid, info in pairs(self.state.trackedPlayers) do
        if tostring(guid):match("^test_") then
            wipe(info.cooldowns)
        end
    end

    self:RefreshAllBars()
    self:Print("All test cooldowns cleared.")
end

---------------------------------------------------------------------------
-- Update Test Slot (called from Options panel)
---------------------------------------------------------------------------
function addon:UpdateTestSlot(slotIndex, className, raceName)
    if not self.db then return end

    local teams = { "party", "party", "party", "party" }
    local slots = { 1, 2, 3, 4 }

    self.db.testMode.lastPlayers[slotIndex] = {
        team  = teams[slotIndex],
        class = className,
        race  = raceName or "Human",
        slot  = slots[slotIndex],
    }

    if self.state.testMode then
        self:ClearTestPlayers()
        self:CreateTestPlayers()
        self:RefreshAllBars()
    end
end

---------------------------------------------------------------------------
-- Add/Remove Test Player Slot
---------------------------------------------------------------------------
function addon:GetTestPlayerCount()
    if not self.db or not self.db.testMode.lastPlayers then return 0 end
    return #self.db.testMode.lastPlayers
end

function addon:RemoveTestSlot(slotIndex)
    if not self.db then return end
    table.remove(self.db.testMode.lastPlayers, slotIndex)

    if self.state.testMode then
        self:ClearTestPlayers()
        self:CreateTestPlayers()
        self:RefreshAllBars()
    end
end
