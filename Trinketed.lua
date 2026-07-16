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
        ver:SetText(lib:GetVersion())
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
        histDesc:SetText("Match history and session breakdown with rating tracking and team stats.")
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
    TrinketedDB.verification = TrinketedDB.verification or {}

    print("|cffE8B923Trinketed|r loaded \xe2\x80\x94 |cffF4F4F5/trinketed|r or |cffF4F4F5/trink|r")
end)

---------------------------------------------------------------------------
-- Character Verification — Challenge-Response (/trinketed verify <token>)
---------------------------------------------------------------------------

-- Base32 alphabet (RFC 4648)
local B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
local B32_DECODE = {}
for i = 1, #B32 do B32_DECODE[B32:sub(i, i)] = i - 1 end

-- Must match server-side OBFUSCATION_KEY (0x7A3F5C1D7E2B409)
-- Split into high/low 30-bit halves to avoid Lua 52-bit float precision issues
-- Full 60-bit value: high30 << 30 | low30
local OBF_HI = 0x1E8FD707  -- bits 59..30
local OBF_LO = 0x17E2B409  -- bits 29..0

-- Field set definitions — must match server FIELD_SETS exactly
local FIELD_SETS = {
    [0] = {"class_id", "race_id", "gender", "level"},
    [1] = {"class_id", "race_id", "talent1", "talent2", "talent3"},
    [2] = {"class_id", "race_id", "gender", "talent1", "talent2"},
    [3] = {"class_id", "race_id", "level", "equip_head"},
    [4] = {"class_id", "race_id", "talent2", "talent3", "equip_mainhand"},
    [5] = {"class_id", "race_id", "gender", "guild_name"},
    [6] = {"class_id", "race_id", "level", "talent1", "equip_mainhand"},
    [7] = {"class_id", "race_id", "guild_name", "talent1", "talent3"},
}

-- Field value getters
local FIELD_GETTERS = {
    class_id = function() return tostring(select(3, UnitClass("player")) or 0) end,
    race_id = function() return tostring(select(3, UnitRace("player")) or 0) end,
    gender = function() return tostring(UnitSex("player") or 0) end,
    level = function() return tostring(UnitLevel("player") or 0) end,
    guild_name = function()
        local name = GetGuildInfo("player")
        return name or "nil"
    end,
    talent1 = function() return tostring(select(3, GetTalentTabInfo(1)) or 0) end,
    talent2 = function() return tostring(select(3, GetTalentTabInfo(2)) or 0) end,
    talent3 = function() return tostring(select(3, GetTalentTabInfo(3)) or 0) end,
    equip_head = function() return tostring(GetInventoryItemID("player", 1) or 0) end,
    equip_mainhand = function() return tostring(GetInventoryItemID("player", 16) or 0) end,
}

local function DecodeBase32(str)
    -- Returns a table of 5-bit values
    local bits = {}
    for i = 1, #str do
        local ch = str:sub(i, i):upper()
        local val = B32_DECODE[ch]
        if not val then return nil, "invalid base32 character: " .. ch end
        bits[#bits + 1] = val
    end
    return bits
end

local function DecodeToken(token)
    -- Strip dashes and whitespace
    local clean = token:gsub("[%-%s]", ""):upper()
    if #clean ~= 12 then
        return nil, nil, "Token must be 12 characters"
    end

    local b32vals, err = DecodeBase32(clean)
    if not b32vals then return nil, nil, err end

    -- Reconstruct 60-bit value as two 30-bit halves
    -- 12 base32 chars × 5 bits = 60 bits
    -- We process chars left to right, building hi (bits 59..30) and lo (bits 29..0)
    local hi, lo = 0, 0
    for i = 1, 12 do
        -- Shift the full 60-bit value left by 5, then OR in the new 5 bits
        -- hi gets the top 30 bits, lo gets the bottom 30
        local carry = bit.rshift(lo, 25) -- top 5 bits of lo that overflow into hi
        hi = bit.band(bit.lshift(hi, 5) + carry, 0x3FFFFFFF)
        lo = bit.band(bit.lshift(lo, 5) + b32vals[i], 0x3FFFFFFF)
    end

    -- XOR with obfuscation key
    hi = bit.bxor(hi, OBF_HI)
    lo = bit.bxor(lo, OBF_LO)

    -- Extract fields:
    -- Bits 59..12 = payload (48 bits), bits 11..0 = CRC (12 bits)
    -- payload: bits 47..45 = field_set_index (3 bits), bits 44..0 = salt (45 bits)

    -- CRC = bottom 12 bits of lo
    local crc_got = bit.band(lo, 0xFFF)

    -- Payload = bits 59..12 of the 60-bit value
    -- payload_hi = hi >> 0 (bits 47..18 of payload are bits 59..30 of value, shifted right by 12)
    -- Actually let's think of it differently:
    -- value = hi * 2^30 + lo  (60 bits)
    -- payload = value >> 12 = hi * 2^18 + lo >> 12  (48 bits)
    -- We need payload as two 24-bit halves for CRC check

    -- For CRC verification, compute SHA-256 of the 6-byte payload
    -- payload_hi24 = top 24 bits of 48-bit payload = hi >> (30-24) ... hmm
    -- Let me just build the 6-byte string for the payload

    -- payload (48 bits) = (hi << 18) | (lo >> 12)  but that can overflow
    -- Let's work byte by byte
    -- value (60 bits): hi=bits[59:30], lo=bits[29:0]
    -- payload (48 bits) = value >> 12
    -- byte0 = bits[59:52] = hi >> 22
    -- byte1 = bits[51:44] = (hi >> 14) & 0xFF
    -- byte2 = bits[43:36] = (hi >> 6) & 0xFF
    -- byte3 = bits[35:28] = ((hi & 0x3F) << 2) | (lo >> 28)
    -- byte4 = bits[27:20] = (lo >> 20) & 0xFF
    -- byte5 = bits[19:12] = (lo >> 12) & 0xFF

    local b0 = bit.band(bit.rshift(hi, 22), 0xFF)
    local b1 = bit.band(bit.rshift(hi, 14), 0xFF)
    local b2 = bit.band(bit.rshift(hi, 6), 0xFF)
    local b3 = bit.band(bit.bor(bit.lshift(bit.band(hi, 0x3F), 2), bit.rshift(lo, 28)), 0xFF)
    local b4 = bit.band(bit.rshift(lo, 20), 0xFF)
    local b5 = bit.band(bit.rshift(lo, 12), 0xFF)

    local payload_bytes = string.char(b0, b1, b2, b3, b4, b5)
    local hash = TrinketedSHA256(payload_bytes)
    -- CRC = first 12 bits of SHA-256 = (byte0 << 4) | (byte1 >> 4)
    local h0 = tonumber(hash:sub(1, 2), 16)
    local h1 = tonumber(hash:sub(3, 4), 16)
    local crc_expected = bit.band(bit.bor(bit.lshift(h0, 4), bit.rshift(h1, 4)), 0xFFF)

    if crc_got ~= crc_expected then
        return nil, nil, "Invalid token (checksum mismatch)"
    end

    -- Extract field_set_index (3 bits) = payload bits 47..45
    -- payload bit 47 = hi bit 29 (since payload = hi<<18 | lo>>12, and hi is 30 bits)
    -- field_set_index = top 3 bits of payload = hi >> (30-3-12) ... let me think again
    -- payload is 48 bits: top 3 are set_index, next 45 are salt
    -- payload top 3 bits = b0 >> 5
    local field_set_index = bit.rshift(b0, 5)

    -- Salt = bottom 45 bits of payload (bytes b0..b5 with top 3 bits masked)
    -- salt as 12-char hex: we need the 45-bit value
    -- Clear top 3 bits of b0
    local salt_b0 = bit.band(b0, 0x1F)
    local salt_hex = string.format("%02x%02x%02x%02x%02x%02x", salt_b0, b1, b2, b3, b4, b5)
    -- That's 12 hex chars representing 48 bits, but top 3 bits are zero → matches server's format

    return salt_hex, field_set_index, nil
end

local function GatherFields(setIndex)
    local fieldSet = FIELD_SETS[setIndex]
    if not fieldSet then return nil, "Unknown field set: " .. tostring(setIndex) end

    local values = {}
    for _, name in ipairs(fieldSet) do
        local getter = FIELD_GETTERS[name]
        if getter then
            values[#values + 1] = getter()
        else
            values[#values + 1] = "0"
        end
    end
    return values
end

---------------------------------------------------------------------------
-- Verification Result Popup
---------------------------------------------------------------------------
local verifyPopup

local function ShowVerifyPopup(response)
    if verifyPopup then
        verifyPopup:Show()
    else
        local f = CreateFrame("Frame", "TrinketedVerifyPopup", UIParent, "BackdropTemplate")
        f:SetSize(320, 170)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("DIALOG")
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

        -- Title
        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont(lib.FONT_DISPLAY, 14, "")
        title:SetPoint("TOP", 0, -16)
        title:SetText("|cffE8B923Trinketed|r Verification")
        f.title = title

        -- Instruction
        local inst = f:CreateFontString(nil, "OVERLAY")
        inst:SetFont(lib.FONT_BODY, 11, "")
        inst:SetPoint("TOP", title, "BOTTOM", 0, -10)
        inst:SetText("Copy this code and paste it on trinketed.com")
        inst:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
        f.inst = inst

        -- Edit box (selectable/copyable)
        local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        box:SetSize(240, 32)
        box:SetPoint("TOP", inst, "BOTTOM", 0, -12)
        box:SetFont(lib.FONT_MONO, 16, "")
        box:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        box:SetJustifyH("CENTER")
        box:SetAutoFocus(false)
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        box:SetBackdropColor(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)
        box:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnChar", function(self)
            -- Prevent editing — restore the response code
            self:SetText(self.responseCode or "")
            self:HighlightText()
        end)
        f.editBox = box

        -- Copy button
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(100, 26)
        btn:SetPoint("TOP", box, "BOTTOM", 0, -12)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
        btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.4)

        local btnText = btn:CreateFontString(nil, "OVERLAY")
        btnText:SetFont(lib.FONT_BODY, 11, "")
        btnText:SetPoint("CENTER", 0, 0)
        btnText:SetText("Select & Ctrl+C")
        btnText:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        f.btnText = btnText

        btn:SetScript("OnClick", function()
            box:SetFocus()
            box:HighlightText()
            btnText:SetText("Now press Ctrl+C")
            C_Timer.After(3, function()
                if verifyPopup and verifyPopup:IsShown() then
                    btnText:SetText("Select & Ctrl+C")
                end
            end)
        end)
        btn:SetScript("OnEnter", function()
            btn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.22)
            btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
        end)
        btn:SetScript("OnLeave", function()
            btn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
            btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.4)
        end)

        -- Close button (X)
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

        verifyPopup = f
    end

    verifyPopup.editBox.responseCode = response
    verifyPopup.editBox:SetText(response)
    verifyPopup.btnText:SetText("Select & Ctrl+C")
    verifyPopup:Show()
    verifyPopup.editBox:SetFocus()
    verifyPopup.editBox:HighlightText()
end

lib:RegisterSubCommand("verify", function(args)
    local token = (args or ""):match("^%s*(%S+)")
    if not token or token == "" then
        print("|cffE8B923Trinketed:|r Usage: |cffF4F4F5/trinketed verify <token>|r")
        print("  Get your verification token from trinketed.com/profile/characters")
        return
    end

    local salt_hex, setIndex, err = DecodeToken(token)
    if not salt_hex then
        print("|cffE8B923Trinketed:|r " .. (err or "Invalid token"))
        return
    end

    local values, verr = GatherFields(setIndex)
    if not values then
        print("|cffE8B923Trinketed:|r " .. (verr or "Failed to gather character data"))
        return
    end

    -- Compute SHA-256(salt_hex:field1:field2:...)
    local preimage = salt_hex .. ":" .. table.concat(values, ":")
    local digest = TrinketedSHA256(preimage)
    local response = digest:sub(1, 16)

    ShowVerifyPopup(response)
end)
