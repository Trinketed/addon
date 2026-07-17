---------------------------------------------------------------------------
-- TrinketedAuras: Options.lua
-- Settings content registered into the master Trinketed options panel.
-- Groups tab: group list on the left, per-group settings + tracked aura
-- editor on the right. Everything applies live.
---------------------------------------------------------------------------
local ADDON, ns = ...
local addon = ns.addon
local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

local CW = function() return lib:GetContentWidth() end

local LIST_W = 170
local scrollCounter = 0

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
function addon:InitOptions()
    lib:RegisterSubAddon("Auras", {
        order = 4,
        desc = "Configurable icon groups that track your own buffs and debuffs.",
        OnSelect = function(contentFrame)
            addon:BuildOptionsContent(contentFrame)
        end,
    })
end

local function ApplyAndRefresh()
    ns.Display:ApplySettings()
end

---------------------------------------------------------------------------
-- Small local widgets
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

-- Row of mutually-exclusive toggle chips. options = { {value, label, x}, ... }
local function CreateRadioRow(parent, y, options, current, onSelect)
    local chips = {}
    for i, opt in ipairs(options) do
        local value = opt[1]
        chips[i] = lib:CreateCheckbox(parent, opt[3], y, opt[2], current == value, function()
            for j, chip in ipairs(chips) do
                chip:SetChecked(options[j][1] == value)
            end
            onSelect(value)
        end)
    end
    return chips
end

---------------------------------------------------------------------------
-- Options content
---------------------------------------------------------------------------
function addon:BuildOptionsContent(parent)
    local tabBar = lib:CreateTabBar(parent, {
        { "general", "General" },
        { "groups", "Groups" },
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
    self:PopulateGroupsTab(tabBar.contents["groups"])

    tabBar:SelectTab("groups")
end

---------------------------------------------------------------------------
-- General tab
---------------------------------------------------------------------------
function addon:PopulateGeneralTab(parent)
    local db = addon.db
    local cw = CW()
    local y = -8

    y = lib:CreateSectionHeader(parent, y, "AURA TRACKER", cw)
    y = y - 6

    lib:CreateCheckbox(parent, 10, y, "Enabled", db.enabled, function(checked)
        db.enabled = checked
        ApplyAndRefresh()
    end)
    y = y - 38

    y = lib:CreateSectionHeader(parent, y, "HOW IT WORKS", cw)
    y = y - 6

    local lines = {
        "Groups are independent clusters of icons that track buffs/debuffs on you.",
        "Each group has its own position, growth direction, icon size, scale and aura list.",
        "Add auras by spell ID (exact) or by name (catches every rank of a ranked spell).",
        "'Only mine' restricts an aura to ones you cast yourself (e.g. your own Lifebloom).",
        " ",
        "Unlock (top right) to drag groups on screen; Test previews icons without real auras.",
        "Slash commands: /trinketed auras, /trinketed auraslock, /trinketed aurastest",
    }
    for _, line in ipairs(lines) do
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(addon.FONT_BODY, 10, "")
        fs:SetPoint("TOPLEFT", 10, y)
        fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        fs:SetText(line)
        y = y - 16
    end
end

---------------------------------------------------------------------------
-- Groups tab
---------------------------------------------------------------------------
function addon:PopulateGroupsTab(parent)
    local db = addon.db
    local selectedIndex = 1

    -- Left: group list panel
    local listPanel = CreateFrame("Frame", nil, parent)
    listPanel:SetPoint("TOPLEFT", 0, 0)
    listPanel:SetPoint("BOTTOMLEFT", 0, 0)
    listPanel:SetWidth(LIST_W)

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", LIST_W, -4)
    divider:SetPoint("BOTTOMLEFT", LIST_W, 4)
    divider:SetWidth(1)
    divider:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

    local listRows = {}
    local detailFrame = nil
    local RebuildGroupList, ShowGroup

    local function CreateGroupRow(index, group)
        local row = CreateFrame("Button", nil, listPanel)
        row:SetSize(LIST_W - 8, 26)
        row:SetPoint("TOPLEFT", 4, -8 - (index - 1) * 26)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.indicator = row:CreateTexture(nil, "OVERLAY")
        row.indicator:SetPoint("TOPLEFT", 0, 0)
        row.indicator:SetPoint("BOTTOMLEFT", 0, 0)
        row.indicator:SetWidth(3)

        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetFont(addon.FONT_BODY, 11, "")
        row.text:SetPoint("LEFT", 12, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetText(group.name .. (group.enabled and "" or " |cff5C5E66(off)|r"))

        local function UpdateVisual()
            if index == selectedIndex then
                row.bg:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3], C.tabActive[4])
                row.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                row.text:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
            else
                row.bg:SetColorTexture(0, 0, 0, 0)
                row.indicator:SetColorTexture(0, 0, 0, 0)
                row.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end
        end
        UpdateVisual()

        row:SetScript("OnEnter", function()
            if index ~= selectedIndex then
                row.bg:SetColorTexture(C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4])
                row.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
            end
        end)
        row:SetScript("OnLeave", UpdateVisual)
        row:SetScript("OnClick", function()
            selectedIndex = index
            RebuildGroupList()
            ShowGroup(index)
        end)

        return row
    end

    RebuildGroupList = function()
        for _, row in ipairs(listRows) do row:Hide(); row:SetParent(nil) end
        wipe(listRows)

        for i, group in ipairs(db.groups) do
            listRows[#listRows + 1] = CreateGroupRow(i, group)
        end

        local addBtn = lib:CreateButton(listPanel, 4, -8 - #db.groups * 26 - 6, LIST_W - 8, "+ New Group", function()
            local group = addon:NewGroup("Group " .. (#db.groups + 1))
            table.insert(db.groups, group)
            selectedIndex = #db.groups
            ApplyAndRefresh()
            RebuildGroupList()
            ShowGroup(selectedIndex)
        end)
        listRows[#listRows + 1] = addBtn
    end

    ---------------------------------------------------------------------------
    -- Right: selected group detail (rebuilt on every selection)
    ---------------------------------------------------------------------------
    ShowGroup = function(index)
        if detailFrame then
            detailFrame:Hide()
            detailFrame:SetParent(nil)
            detailFrame = nil
        end

        local group = db.groups[index]
        detailFrame = CreateFrame("Frame", nil, parent)
        detailFrame:SetPoint("TOPLEFT", LIST_W + 10, 0)
        detailFrame:SetPoint("BOTTOMRIGHT", 0, 0)

        if not group then
            local fs = detailFrame:CreateFontString(nil, "OVERLAY")
            fs:SetFont(addon.FONT_BODY, 11, "")
            fs:SetPoint("TOPLEFT", 10, -16)
            fs:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            fs:SetText("No group selected. Create one with '+ New Group'.")
            return
        end

        local cw = CW() - LIST_W - 10
        local y = -8

        y = lib:CreateSectionHeader(detailFrame, y, "GROUP SETTINGS", cw)
        y = y - 6

        -- Name + delete
        local nameLabel = detailFrame:CreateFontString(nil, "OVERLAY")
        nameLabel:SetFont(addon.FONT_BODY, 11, "")
        nameLabel:SetPoint("TOPLEFT", 10, y)
        nameLabel:SetText("Name")
        nameLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

        local nameBox = CreateEditBox(detailFrame, 55, y + 4, 170)
        nameBox:SetText(group.name or "")
        nameBox:SetScript("OnEnterPressed", function(self)
            local text = strtrim(self:GetText() or "")
            if text ~= "" then
                group.name = text
                ApplyAndRefresh()
                RebuildGroupList()
            end
            self:ClearFocus()
        end)

        local deleteBtn = lib:CreateButton(detailFrame, 0, y + 2, 100, "Delete Group", function()
            table.remove(db.groups, index)
            selectedIndex = math.min(index, #db.groups)
            if selectedIndex < 1 then selectedIndex = 1 end
            ApplyAndRefresh()
            RebuildGroupList()
            ShowGroup(selectedIndex)
        end)
        deleteBtn:ClearAllPoints()
        deleteBtn:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -10, y + 2)
        y = y - 34

        -- Toggle chips
        lib:CreateCheckbox(detailFrame, 10, y, "Enabled", group.enabled, function(checked)
            group.enabled = checked
            ApplyAndRefresh()
            RebuildGroupList()
        end)
        lib:CreateCheckbox(detailFrame, 110, y, "Show duration", group.showDuration, function(checked)
            group.showDuration = checked
            ApplyAndRefresh()
        end)
        lib:CreateCheckbox(detailFrame, 245, y, "Show stacks", group.showStacks, function(checked)
            group.showStacks = checked
            ApplyAndRefresh()
        end)
        lib:CreateCheckbox(detailFrame, 370, y, "Cooldown swipe", group.showSwipe, function(checked)
            group.showSwipe = checked
            ApplyAndRefresh()
        end)
        y = y - 28

        lib:CreateCheckbox(detailFrame, 10, y, "Sort by time remaining", group.sortByTime, function(checked)
            group.sortByTime = checked
            ApplyAndRefresh()
        end)
        y = y - 32

        -- Growth direction
        local growLabel = detailFrame:CreateFontString(nil, "OVERLAY")
        growLabel:SetFont(addon.FONT_BODY, 11, "")
        growLabel:SetPoint("TOPLEFT", 10, y - 4)
        growLabel:SetText("Grow")
        growLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

        CreateRadioRow(detailFrame, y, {
            { "LEFT",   "Left",   60 },
            { "RIGHT",  "Right",  125 },
            { "UP",     "Up",     195 },
            { "DOWN",   "Down",   250 },
            { "CENTER", "Center", 320 },
        }, group.grow, function(value)
            group.grow = value
            ApplyAndRefresh()
        end)
        y = y - 34

        -- Duration text position
        local textLabel = detailFrame:CreateFontString(nil, "OVERLAY")
        textLabel:SetFont(addon.FONT_BODY, 11, "")
        textLabel:SetPoint("TOPLEFT", 10, y - 4)
        textLabel:SetText("Text")
        textLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

        CreateRadioRow(detailFrame, y, {
            { "ABOVE",  "Above",  60 },
            { "CENTER", "Center", 125 },
            { "BELOW",  "Below",  195 },
        }, group.durationAnchor, function(value)
            group.durationAnchor = value
            ApplyAndRefresh()
        end)
        y = y - 34

        -- Sliders (two columns)
        lib:CreateSlider(detailFrame, 10, y, "Icon size", 16, 64, 2, group.iconSize, function(val)
            group.iconSize = val
            ApplyAndRefresh()
        end)
        lib:CreateSlider(detailFrame, 310, y, "Spacing", 0, 20, 1, group.spacing, function(val)
            group.spacing = val
            ApplyAndRefresh()
        end)
        y = y - 46

        lib:CreateSlider(detailFrame, 10, y, "Scale %", 50, 200, 5, math.floor((group.scale or 1) * 100 + 0.5), function(val)
            group.scale = val / 100
            ApplyAndRefresh()
        end)
        lib:CreateSlider(detailFrame, 310, y, "Duration font", 8, 24, 1, group.durationFontSize, function(val)
            group.durationFontSize = val
            ApplyAndRefresh()
        end)
        y = y - 46

        lib:CreateSlider(detailFrame, 10, y, "Offset X", -800, 800, 5, math.floor((group.x or 0) + 0.5), function(val)
            group.x = val
            ApplyAndRefresh()
        end)
        lib:CreateSlider(detailFrame, 310, y, "Offset Y", -500, 500, 5, math.floor((group.y or 0) + 0.5), function(val)
            group.y = val
            ApplyAndRefresh()
        end)
        y = y - 50

        ---------------------------------------------------------------------------
        -- Tracked auras
        ---------------------------------------------------------------------------
        y = lib:CreateSectionHeader(detailFrame, y, "TRACKED AURAS", cw)
        y = y - 6

        local addFilter = "HELPFUL"
        local addOnlyMine = true

        local spellLabel = detailFrame:CreateFontString(nil, "OVERLAY")
        spellLabel:SetFont(addon.FONT_BODY, 11, "")
        spellLabel:SetPoint("TOPLEFT", 10, y)
        spellLabel:SetText("Spell")
        spellLabel:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

        local spellBox = CreateEditBox(detailFrame, 50, y + 4, 150)

        CreateRadioRow(detailFrame, y + 2, {
            { "HELPFUL", "Buff",   215 },
            { "HARMFUL", "Debuff", 275 },
        }, addFilter, function(value)
            addFilter = value
        end)

        lib:CreateCheckbox(detailFrame, 355, y + 2, "Only mine", addOnlyMine, function(checked)
            addOnlyMine = checked
        end)

        local rebuildAuraList

        local addAura = function()
            local text = strtrim(spellBox:GetText() or "")
            if text == "" then
                addon:Print("Enter a spell ID or spell name.")
                return
            end
            local spell = tonumber(text) or text
            table.insert(group.auras, { spell = spell, filter = addFilter, onlyMine = addOnlyMine })
            spellBox:SetText("")
            spellBox:ClearFocus()
            ApplyAndRefresh()
            rebuildAuraList()
        end

        local addBtn = lib:CreateButton(detailFrame, 0, y + 2, 70, "Add", addAura)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -10, y + 2)
        spellBox:SetScript("OnEnterPressed", addAura)
        y = y - 32

        -- Aura list
        scrollCounter = scrollCounter + 1
        local scroll = CreateFrame("ScrollFrame", "TrinketedAurasListScroll" .. scrollCounter, detailFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, y)
        scroll:SetPoint("BOTTOMRIGHT", -28, 8)
        local listChild = CreateFrame("Frame", nil, scroll)
        listChild:SetSize(cw - 40, 10)
        scroll:SetScrollChild(listChild)

        local auraRows = {}
        rebuildAuraList = function()
            for _, r in ipairs(auraRows) do r:Hide(); r:SetParent(nil) end
            wipe(auraRows)

            listChild:SetSize(cw - 40, math.max(10, #group.auras * 24 + 4))

            for i, entry in ipairs(group.auras) do
                local row = CreateFrame("Frame", nil, listChild)
                row:SetSize(cw - 44, 22)
                row:SetPoint("TOPLEFT", 0, -((i - 1) * 24))

                local name = GetSpellInfo(entry.spell) or tostring(entry.spell)
                local idPart = type(entry.spell) == "number" and ("|cffE8B923" .. entry.spell .. "|r  ") or ""
                local kind = entry.filter == "HARMFUL" and "Debuff" or "Buff"
                local mine = entry.onlyMine and ", mine" or ""

                local txt = row:CreateFontString(nil, "OVERLAY")
                txt:SetFont(addon.FONT_BODY, 11, "")
                txt:SetPoint("LEFT", 4, 0)
                txt:SetText(string.format("%s%s  |cff8C8C94(%s%s)|r", idPart, name, kind, mine))
                txt:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

                lib:CreateButton(row, cw - 44 - 70, -1, 64, "Remove", function()
                    table.remove(group.auras, i)
                    ApplyAndRefresh()
                    rebuildAuraList()
                end)

                auraRows[#auraRows + 1] = row
            end
        end
        rebuildAuraList()
    end

    RebuildGroupList()
    ShowGroup(selectedIndex)
end
