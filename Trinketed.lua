---------------------------------------------------------------------------
-- Trinketed: Parent Addon Loader
-- Slash command dispatch, minimal initialization
---------------------------------------------------------------------------
local addonName, addon = ...
Trinketed = addon

local lib = LibStub("TrinketedLib-1.0")

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
