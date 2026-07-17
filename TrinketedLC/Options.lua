---------------------------------------------------------------------------
-- TrinketedLC: Options.lua
-- Settings content registered into the master Trinketed options panel.
-- Mirrors BetterBlizzFrames' Loss-of-Control frame options, player-only.
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
    lib:RegisterSubAddon("Lose Control", {
        order = 3,
        desc = "On-screen alerts when you are crowd-controlled, silenced, or interrupted.",
        OnSelect = function(contentFrame)
            addon:BuildOptionsContent(contentFrame)
        end,
    })
end

local function ApplyAndRefresh()
    ns.Display:ApplySettings()
end

function addon:BuildOptionsContent(parent)
    local tabBar = lib:CreateTabBar(parent, {
        { "general", "General" },
        { "spells", "Spells" },
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
        ns.Display:ToggleTest()
    end)
    testBtn:ClearAllPoints()
    testBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)
    testBtn:SetSize(70, 18)

    self:PopulateGeneralTab(tabBar.contents["general"])
    self:PopulateSpellsTab(tabBar.contents["spells"])

    tabBar:SelectTab("general")
end

---------------------------------------------------------------------------
-- General tab (enable / scale / layout / appearance / position)
---------------------------------------------------------------------------
function addon:PopulateGeneralTab(parent)
    local db = addon.db
    local cw = CW()
    local y = -8

    y = lib:CreateSectionHeader(parent, y, "LOSE CONTROL ALERT", cw)
    y = y - 6

    lib:CreateCheckbox(parent, 10, y, "Enabled", db.enabled, function(checked)
        db.enabled = checked
        ApplyAndRefresh()
    end)
    y = y - 30

    lib:CreateSlider(parent, 10, y, "Scale %", 50, 200, 5, math.floor(db.scale * 100 + 0.5), function(val)
        db.scale = val / 100
        ApplyAndRefresh()
    end)
    y = y - 46

    y = lib:CreateSectionHeader(parent, y, "LAYOUT & APPEARANCE", cw)
    y = y - 6

    lib:CreateCheckbox(parent, 10, y, "Icon only (hide effect name and duration)", db.iconOnly, function(checked)
        db.iconOnly = checked
        ApplyAndRefresh()
    end)
    y = y - 30

    lib:CreateCheckbox(parent, 10, y, "Show cooldown swipe on icon", db.showCooldown, function(checked)
        db.showCooldown = checked
        ApplyAndRefresh()
    end)
    y = y - 30

    lib:CreateCheckbox(parent, 10, y, "Hide background", db.hideBackground, function(checked)
        db.hideBackground = checked
        ApplyAndRefresh()
    end)
    y = y - 30

    lib:CreateCheckbox(parent, 10, y, "Hide red edge lines", db.hideRedLines, function(checked)
        db.hideRedLines = checked
        ApplyAndRefresh()
    end)
    y = y - 38

    y = lib:CreateSectionHeader(parent, y, "POSITION", cw)
    y = y - 6

    lib:CreateSlider(parent, 10, y, "Offset X", -600, 600, 5, math.floor(db.x + 0.5), function(val)
        db.x = val
        ApplyAndRefresh()
    end)
    lib:CreateSlider(parent, 300, y, "Offset Y", -600, 600, 5, math.floor(db.y + 0.5), function(val)
        db.y = val
        ApplyAndRefresh()
    end)
    y = y - 46

    local hint = parent:CreateFontString(nil, "OVERLAY")
    hint:SetFont(addon.FONT_BODY, 10, "")
    hint:SetPoint("TOPLEFT", 10, y)
    hint:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    hint:SetText("Unlock (top right) to drag the alert freely; the offsets update as you move it.")
end

---------------------------------------------------------------------------
-- Spells tab (custom spell-ID label overrides / Ignore)
---------------------------------------------------------------------------
local function CreateEditBox(parent, x, y, w)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(w, 22)
    bg:SetPoint("TOPLEFT", x, y)
    bg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bg:SetBackdropColor(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)
    bg:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], 1)

    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetPoint("TOPLEFT", 5, -2)
    eb:SetPoint("BOTTOMRIGHT", -5, 2)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetFont(addon.FONT_MONO, 11, "")
    eb:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

function addon:PopulateSpellsTab(parent)
    local cw = CW()
    local y = -8
    y = lib:CreateSectionHeader(parent, y, "ADD / OVERRIDE SPELL", cw)
    y = y - 6

    local idLabel = parent:CreateFontString(nil, "OVERLAY")
    idLabel:SetFont(addon.FONT_BODY, 11, "")
    idLabel:SetPoint("TOPLEFT", 10, y)
    idLabel:SetText("Spell ID")
    idLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    local idBox = CreateEditBox(parent, 70, y + 4, 80)

    local labelLabel = parent:CreateFontString(nil, "OVERLAY")
    labelLabel:SetFont(addon.FONT_BODY, 11, "")
    labelLabel:SetPoint("TOPLEFT", 165, y)
    labelLabel:SetText("Label")
    labelLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    local labelBox = CreateEditBox(parent, 205, y + 4, 180)

    local rebuildList

    -- Add / override: store the typed label for this spell ID.
    local addBtn = lib:CreateButton(parent, 395, y + 2, 90, "Add", function()
        local id = tonumber(idBox:GetText())
        if not id then
            addon:Print("Enter a numeric spell ID.")
            return
        end
        local label = strtrim(labelBox:GetText() or "")
        if label == "" then
            addon:Print("Enter a label (or use Ignore to suppress a spell).")
            return
        end
        addon.db.customSpellIds[id] = label
        idBox:SetText("")
        labelBox:SetText("")
        idBox:ClearFocus()
        labelBox:ClearFocus()
        ns.Display:RefreshAll()
        if rebuildList then rebuildList() end
    end)

    -- Ignore: suppress a base-DB spell from ever showing.
    local ignoreBtn = lib:CreateButton(parent, 395, y - 22, 90, "Ignore", function()
        local id = tonumber(idBox:GetText())
        if not id then
            addon:Print("Enter a numeric spell ID to ignore.")
            return
        end
        addon.db.customSpellIds[id] = "Ignore"
        idBox:SetText("")
        idBox:ClearFocus()
        ns.Display:RefreshAll()
        if rebuildList then rebuildList() end
    end)

    -- Existing custom entries list
    local listY = y - 54
    local listTitle = parent:CreateFontString(nil, "OVERLAY")
    listTitle:SetFont(addon.FONT_BODY, 10, "")
    listTitle:SetPoint("TOPLEFT", 10, listY)
    listTitle:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    local scroll = CreateFrame("ScrollFrame", "TrinketedLCSpellsScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, listY - 18)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local listChild = CreateFrame("Frame", nil, scroll)
    listChild:SetSize(cw - 40, 10)
    scroll:SetScrollChild(listChild)

    local rows = {}
    rebuildList = function()
        for _, r in ipairs(rows) do r:Hide(); r:SetParent(nil) end
        wipe(rows)

        local ids = {}
        for id in pairs(addon.db.customSpellIds) do ids[#ids + 1] = id end
        table.sort(ids)
        listTitle:SetText("CUSTOM ENTRIES (" .. #ids .. ")")
        listChild:SetSize(cw - 40, math.max(10, #ids * 24 + 4))

        for i, id in ipairs(ids) do
            local label = addon.db.customSpellIds[id]
            local name = GetSpellInfo(id) or "spell " .. id
            local row = CreateFrame("Frame", nil, listChild)
            row:SetSize(cw - 44, 22)
            row:SetPoint("TOPLEFT", 0, -((i - 1) * 24))

            local txt = row:CreateFontString(nil, "OVERLAY")
            txt:SetFont(addon.FONT_BODY, 11, "")
            txt:SetPoint("LEFT", 4, 0)
            txt:SetText(string.format("|cffE8B923%d|r  %s  |cff8C8C94(%s)|r", id, name, label))
            txt:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

            lib:CreateButton(row, cw - 44 - 70, -1, 64, "Remove", function()
                addon.db.customSpellIds[id] = nil
                ns.Display:RefreshAll()
                rebuildList()
            end)

            rows[#rows + 1] = row
        end
    end
    rebuildList()
end
