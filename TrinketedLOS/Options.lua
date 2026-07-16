---------------------------------------------------------------------------
-- TrinketedLOS: Options.lua
-- Settings content registered into the master Trinketed options panel.
-- Behaviour toggles (send/receive/sound/scope) plus the alert frame
-- appearance and position. Everything applies live.
---------------------------------------------------------------------------
local ADDON, ns = ...
local addon = ns.addon
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local CW = function() return lib:GetContentWidth() end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
function addon:InitOptions()
    lib:RegisterSubAddon("Line of Sight", {
        order = 5,
        OnSelect = function(contentFrame)
            addon:BuildOptionsContent(contentFrame)
        end,
    })
end

local function ApplyAndRefresh()
    ns.Display:ApplySettings()
end

---------------------------------------------------------------------------
-- Options content
---------------------------------------------------------------------------
function addon:BuildOptionsContent(parent)
    local tabBar = lib:CreateTabBar(parent, {
        { "general", "General" },
    }, { height = 26, tabWidth = 90 })

    -- Right-aligned: Lock toggle + Test toggle
    local lockBtn = lib:CreateButton(tabBar.frame, 0, 0, 80, addon.db.locked and "Unlock" or "Lock", function()
        addon:ToggleLock()
    end)
    lockBtn:ClearAllPoints()
    lockBtn:SetPoint("RIGHT", tabBar.frame, "RIGHT", -8, 0)
    lockBtn:SetSize(80, 18)
    for _, region in ipairs({ lockBtn:GetRegions() }) do
        if region:GetObjectType() == "FontString" then lockBtn.lbl = region end
    end
    lockBtn:HookScript("OnClick", function()
        if lockBtn.lbl then lockBtn.lbl:SetText(addon.db.locked and "Unlock" or "Lock") end
    end)
    addon._lockBtn = lockBtn

    local testBtn = lib:CreateButton(tabBar.frame, 0, 0, 70, "Test", function()
        ns.Display:ShowAlert(UnitName("player"), "Regrowth")
    end)
    testBtn:ClearAllPoints()
    testBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)
    testBtn:SetSize(70, 18)

    self:PopulateGeneralTab(tabBar.contents["general"])
    tabBar:SelectTab("general")
end

---------------------------------------------------------------------------
-- General tab
---------------------------------------------------------------------------
function addon:PopulateGeneralTab(parent)
    local db = addon.db
    local cw = CW()
    local y = -8

    y = lib:CreateSectionHeader(parent, y, "BEHAVIOUR", cw)
    y = y - 6

    lib:CreateCheckbox(parent, 10, y, "Enabled", db.enabled, function(checked)
        db.enabled = checked
        ApplyAndRefresh()
    end)
    lib:CreateCheckbox(parent, 110, y, "Play sound on alert", db.playSound, function(checked)
        db.playSound = checked
    end)
    y = y - 30

    lib:CreateCheckbox(parent, 10, y, "Warn allies when I lose line of sight on them", db.sendEnabled, function(checked)
        db.sendEnabled = checked
    end)
    y = y - 28

    lib:CreateCheckbox(parent, 10, y, "Show an alert when an ally can't see me", db.receiveEnabled, function(checked)
        db.receiveEnabled = checked
    end)
    y = y - 28

    lib:CreateCheckbox(parent, 10, y, "Only inside arenas, battlegrounds and dungeons", db.onlyInstanced, function(checked)
        db.onlyInstanced = checked
    end)
    y = y - 36

    y = lib:CreateSectionHeader(parent, y, "TIMING", cw)
    y = y - 6

    lib:CreateSlider(parent, 10, y, "Alert hold (sec)", 1, 10, 1, math.floor((db.holdTime or 3) + 0.5), function(val)
        db.holdTime = val
    end)
    lib:CreateSlider(parent, 300, y, "Min ping gap (sec)", 1, 5, 1, math.floor((db.throttle or 1.5) + 0.5), function(val)
        db.throttle = val
    end)
    y = y - 50

    y = lib:CreateSectionHeader(parent, y, "ALERT FRAME", cw)
    y = y - 6

    lib:CreateSlider(parent, 10, y, "Scale %", 50, 200, 5, math.floor((db.scale or 1) * 100 + 0.5), function(val)
        db.scale = val / 100
        ApplyAndRefresh()
    end)
    y = y - 46

    lib:CreateSlider(parent, 10, y, "Offset X", -800, 800, 5, math.floor((db.x or 0) + 0.5), function(val)
        db.x = val
        ApplyAndRefresh()
    end)
    lib:CreateSlider(parent, 300, y, "Offset Y", -500, 500, 5, math.floor((db.y or 0) + 0.5), function(val)
        db.y = val
        ApplyAndRefresh()
    end)
    y = y - 50

    local hint = parent:CreateFontString(nil, "OVERLAY")
    hint:SetFont(addon.FONT_BODY, 10, "")
    hint:SetPoint("TOPLEFT", 10, y)
    hint:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    hint:SetText("Unlock (top right) to drag the alert; Test previews it. Allies need this addon to receive your warnings.")
end
