---------------------------------------------------------------------------
-- Trinketed: Parent Addon Loader
-- Slash command dispatch, minimal initialization
---------------------------------------------------------------------------
local addonName, addon = ...
Trinketed = addon

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

---------------------------------------------------------------------------
-- Welcome Tab (order = 0 so it appears first in the sidebar)
---------------------------------------------------------------------------
lib:RegisterSubAddon("Welcome", {
    order = 0,
    OnSelect = function(contentFrame)
        -- Large branded header
        local title = contentFrame:CreateFontString(nil, "OVERLAY")
        title:SetFont(lib.FONT_DISPLAY, 28, "")
        title:SetPoint("TOPLEFT", 24, -24)
        title:SetText("|cffE8B923T|r|cffF4F4F5RINKETED|r")

        local ver = contentFrame:CreateFontString(nil, "OVERLAY")
        ver:SetFont(lib.FONT_MONO, 10, "")
        ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -4)
        ver:SetText(C_AddOns.GetAddOnMetadata("Trinketed", "Version") or "")
        ver:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        local desc = contentFrame:CreateFontString(nil, "OVERLAY")
        desc:SetFont(lib.FONT_BODY, 12, "")
        desc:SetPoint("TOPLEFT", ver, "BOTTOMLEFT", -2, -14)
        desc:SetWidth(lib:GetContentWidth() - 48)
        desc:SetJustifyH("LEFT")
        desc:SetText("Arena PvP toolkit for World of Warcraft. Track cooldowns, record match history, and analyze your performance.")
        desc:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

        -- Modules section
        local y = -120
        y = lib:CreateSectionHeader(contentFrame, y, "MODULES", lib:GetContentWidth() - 48)

        local cdTitle = contentFrame:CreateFontString(nil, "OVERLAY")
        cdTitle:SetFont(lib.FONT_BODY, 12, "")
        cdTitle:SetPoint("TOPLEFT", 16, y)
        cdTitle:SetText("|cffF4F4F5Cooldowns|r")

        local cdDesc = contentFrame:CreateFontString(nil, "OVERLAY")
        cdDesc:SetFont(lib.FONT_BODY, 11, "")
        cdDesc:SetPoint("TOPLEFT", cdTitle, "BOTTOMLEFT", 0, -2)
        cdDesc:SetWidth(lib:GetContentWidth() - 64)
        cdDesc:SetJustifyH("LEFT")
        cdDesc:SetText("Real-time arena cooldown tracker with customizable bars and alerts.")
        cdDesc:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

        local histTitle = contentFrame:CreateFontString(nil, "OVERLAY")
        histTitle:SetFont(lib.FONT_BODY, 12, "")
        histTitle:SetPoint("TOPLEFT", cdDesc, "BOTTOMLEFT", 0, -12)
        histTitle:SetText("|cffF4F4F5History|r")

        local histDesc = contentFrame:CreateFontString(nil, "OVERLAY")
        histDesc:SetFont(lib.FONT_BODY, 11, "")
        histDesc:SetPoint("TOPLEFT", histTitle, "BOTTOMLEFT", 0, -2)
        histDesc:SetWidth(lib:GetContentWidth() - 64)
        histDesc:SetJustifyH("LEFT")
        histDesc:SetText("Match history and session breakdown with rating tracking, team stats, and data export.")
        histDesc:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end,
})

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------
SLASH_TRINKETED1 = "/trinketed"
SLASH_TRINKETED2 = "/trink"
SlashCmdList["TRINKETED"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$") or ""

    if msg == "" then
        lib:ToggleOptionsPanel()
        return
    end

    -- Split first word from rest
    local cmd, args = msg:match("^(%S+)%s*(.*)$")
    if not cmd then
        lib:ToggleOptionsPanel()
        return
    end

    local handler = lib:GetSubCommand(cmd)
    if handler then
        handler(args)
    elseif cmd == "help" then
        print("|cffE8B923Trinketed|r commands:")
        print("  |cffF4F4F5/trinketed|r \xe2\x80\x94 open settings")
        -- List registered sub-commands
        local seen = {}
        for name in pairs(lib.subCommands) do
            if not seen[name] then
                print("  |cffF4F4F5/trinketed " .. name .. "|r")
                seen[name] = true
            end
        end
    else
        print("|cffE8B923Trinketed:|r Unknown command '|cffF4F4F5" .. cmd .. "|r'. Type |cffF4F4F5/trinketed help|r")
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Initialize SavedVariables
    TrinketedDB = TrinketedDB or {}

    print("|cffE8B923Trinketed|r loaded \xe2\x80\x94 |cffF4F4F5/trinketed|r or |cffF4F4F5/trink|r")
end)
