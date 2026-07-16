---------------------------------------------------------------------------
-- TrinketedCD: Serialize.lua
-- Base64 encoding, table serialization, config import/export
---------------------------------------------------------------------------
TrinketedCD = TrinketedCD or {}
local addon = TrinketedCD

local EXPORT_PREFIX = "!TCD1!"
local FORMAT_VERSION = 1

---------------------------------------------------------------------------
-- Base64 Encode / Decode (RFC 4648)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(data)
    local out = {}
    local len = #data
    local i = 1
    while i <= len do
        local a = string.byte(data, i)
        local b = (i + 1 <= len) and string.byte(data, i + 1) or 0
        local c = (i + 2 <= len) and string.byte(data, i + 2) or 0
        local remain = len - i + 1

        local n = a * 65536 + b * 256 + c

        local c1 = math.floor(n / 262144) + 1
        local c2 = math.floor(n / 4096) % 64 + 1
        local c3 = math.floor(n / 64) % 64 + 1
        local c4 = n % 64 + 1

        out[#out + 1] = string.sub(B64, c1, c1)
        out[#out + 1] = string.sub(B64, c2, c2)
        if remain >= 2 then
            out[#out + 1] = string.sub(B64, c3, c3)
        else
            out[#out + 1] = "="
        end
        if remain >= 3 then
            out[#out + 1] = string.sub(B64, c4, c4)
        else
            out[#out + 1] = "="
        end

        i = i + 3
    end
    return table.concat(out)
end

local B64_DECODE = {}
for i = 1, 64 do
    B64_DECODE[string.byte(B64, i)] = i - 1
end

local function b64decode(data)
    -- Strip whitespace
    data = string.gsub(data, "%s+", "")
    local out = {}
    local len = #data
    local i = 1
    while i <= len do
        local a = B64_DECODE[string.byte(data, i)] or 0
        local b = B64_DECODE[string.byte(data, i + 1)] or 0
        local c = B64_DECODE[string.byte(data, i + 2)] or 0
        local d = B64_DECODE[string.byte(data, i + 3)] or 0

        local n = a * 262144 + b * 4096 + c * 64 + d

        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if string.sub(data, i + 2, i + 2) ~= "=" then
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if string.sub(data, i + 3, i + 3) ~= "=" then
            out[#out + 1] = string.char(n % 256)
        end

        i = i + 4
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Table Serializer
---------------------------------------------------------------------------
local function SerializeValue(val)
    local t = type(val)
    if t == "string" then
        -- Escape backslashes and double quotes
        local escaped = string.gsub(val, "\\", "\\\\")
        escaped = string.gsub(escaped, '"', '\\"')
        return '"' .. escaped .. '"'
    elseif t == "number" then
        if val == math.floor(val) and val >= -2147483648 and val <= 2147483647 then
            return tostring(math.floor(val))
        end
        return tostring(val)
    elseif t == "boolean" then
        return val and "T" or "F"
    elseif t == "table" then
        local parts = {}
        -- Check if table is a pure array (sequential integer keys 1..n)
        local n = #val
        local isArray = true
        local totalKeys = 0
        for _ in pairs(val) do totalKeys = totalKeys + 1 end
        if totalKeys ~= n then isArray = false end

        if isArray and n > 0 then
            for i = 1, n do
                parts[#parts + 1] = SerializeValue(val[i])
            end
        else
            -- Mixed or hash table: use explicit keys
            -- Sort keys for deterministic output
            local keys = {}
            for k in pairs(val) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b)
                local ta, tb = type(a), type(b)
                if ta ~= tb then return ta < tb end
                if ta == "number" then return a < b end
                return tostring(a) < tostring(b)
            end)
            for _, k in ipairs(keys) do
                local kSer
                if type(k) == "number" then
                    kSer = "[" .. tostring(math.floor(k)) .. "]"
                else
                    kSer = '["' .. string.gsub(string.gsub(tostring(k), "\\", "\\\\"), '"', '\\"') .. '"]'
                end
                parts[#parts + 1] = kSer .. "=" .. SerializeValue(val[k])
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    -- nil or unsupported → empty string
    return '""'
end

---------------------------------------------------------------------------
-- Table Deserializer (Recursive Descent Parser)
---------------------------------------------------------------------------
local function CreateParser(str)
    return { s = str, pos = 1 }
end

local function Peek(p)
    return string.sub(p.s, p.pos, p.pos)
end

local function Skip(p, n)
    p.pos = p.pos + (n or 1)
end

local function SkipWhitespace(p)
    while p.pos <= #p.s do
        local ch = string.sub(p.s, p.pos, p.pos)
        if ch == " " or ch == "\n" or ch == "\r" or ch == "\t" then
            p.pos = p.pos + 1
        else
            break
        end
    end
end

local function Expect(p, ch)
    SkipWhitespace(p)
    if Peek(p) ~= ch then
        error("Expected '" .. ch .. "' at position " .. p.pos .. ", got '" .. Peek(p) .. "'")
    end
    Skip(p)
end

local ParseValue -- forward declaration

local function ParseString(p)
    Expect(p, '"')
    local parts = {}
    while p.pos <= #p.s do
        local ch = string.sub(p.s, p.pos, p.pos)
        if ch == '"' then
            Skip(p)
            return table.concat(parts)
        elseif ch == '\\' then
            Skip(p)
            local next = string.sub(p.s, p.pos, p.pos)
            if next == '"' or next == '\\' then
                parts[#parts + 1] = next
            else
                parts[#parts + 1] = next
            end
            Skip(p)
        else
            parts[#parts + 1] = ch
            Skip(p)
        end
    end
    error("Unterminated string at position " .. p.pos)
end

local function ParseNumber(p)
    local start = p.pos
    -- Optional negative sign
    if string.sub(p.s, p.pos, p.pos) == "-" then
        p.pos = p.pos + 1
    end
    -- Integer part
    while p.pos <= #p.s do
        local ch = string.sub(p.s, p.pos, p.pos)
        if ch >= "0" and ch <= "9" then
            p.pos = p.pos + 1
        else
            break
        end
    end
    -- Decimal part
    if p.pos <= #p.s and string.sub(p.s, p.pos, p.pos) == "." then
        p.pos = p.pos + 1
        while p.pos <= #p.s do
            local ch = string.sub(p.s, p.pos, p.pos)
            if ch >= "0" and ch <= "9" then
                p.pos = p.pos + 1
            else
                break
            end
        end
    end
    local numStr = string.sub(p.s, start, p.pos - 1)
    local num = tonumber(numStr)
    if not num then error("Invalid number at position " .. start) end
    return num
end

local function ParseTable(p)
    Expect(p, "{")
    local result = {}
    local arrayIndex = 1
    local isArray = true
    SkipWhitespace(p)

    if Peek(p) == "}" then
        Skip(p)
        return result
    end

    while true do
        SkipWhitespace(p)
        local ch = Peek(p)

        if ch == "[" then
            -- Explicit key: ["str"]=val or [num]=val
            isArray = false
            Skip(p)
            SkipWhitespace(p)
            local key
            if Peek(p) == '"' then
                key = ParseString(p)
            else
                key = ParseNumber(p)
            end
            SkipWhitespace(p)
            Expect(p, "]")
            SkipWhitespace(p)
            Expect(p, "=")
            SkipWhitespace(p)
            result[key] = ParseValue(p)
        else
            -- Array element (no key)
            result[arrayIndex] = ParseValue(p)
            arrayIndex = arrayIndex + 1
        end

        SkipWhitespace(p)
        if Peek(p) == "," then
            Skip(p)
        elseif Peek(p) == "}" then
            Skip(p)
            return result
        else
            error("Expected ',' or '}' at position " .. p.pos .. ", got '" .. Peek(p) .. "'")
        end
    end
end

ParseValue = function(p)
    SkipWhitespace(p)
    local ch = Peek(p)

    if ch == '"' then
        return ParseString(p)
    elseif ch == "{" then
        return ParseTable(p)
    elseif ch == "T" then
        Skip(p)
        return true
    elseif ch == "F" then
        Skip(p)
        return false
    elseif ch == "-" or (ch >= "0" and ch <= "9") then
        return ParseNumber(p)
    else
        error("Unexpected character '" .. ch .. "' at position " .. p.pos)
    end
end

local function Deserialize(str)
    local p = CreateParser(str)
    SkipWhitespace(p)
    local result = ParseValue(p)
    return result
end

---------------------------------------------------------------------------
-- Export Config
---------------------------------------------------------------------------
function addon:ExportConfig()
    local db = self.db
    if not db then return nil, "No config loaded" end

    local exportData = {
        v = FORMAT_VERSION,
        general = {},
        party = {},
        grids = {},
    }

    -- General settings (copy all)
    for k, v in pairs(db.general) do
        exportData.general[k] = v
    end

    -- Party settings (exclude positions)
    exportData.party.enabled = db.party.enabled
    exportData.party.iconSize = db.party.iconSize
    exportData.party.gridCols = db.party.gridCols
    exportData.party.gridRows = db.party.gridRows
    exportData.party.anchorToFrames = db.party.anchorToFrames
    exportData.party.anchorSide = db.party.anchorSide
    exportData.party.anchorOffsetX = db.party.anchorOffsetX
    exportData.party.anchorOffsetY = db.party.anchorOffsetY

    -- Grids (deep copy)
    for className, teams in pairs(db.cooldowns.grids) do
        exportData.grids[className] = {}
        for team, grid in pairs(teams) do
            exportData.grids[className][team] = {
                rows = grid.rows,
                cols = grid.cols,
                slots = {},
                disabled = {},
            }
            for i, slot in ipairs(grid.slots) do
                exportData.grids[className][team].slots[i] = slot
            end
            for k, v in pairs(grid.disabled) do
                exportData.grids[className][team].disabled[k] = v
            end
        end
    end

    local serialized = SerializeValue(exportData)
    return EXPORT_PREFIX .. b64encode(serialized)
end

---------------------------------------------------------------------------
-- Import Config
---------------------------------------------------------------------------
local function ValidateType(val, expected)
    return type(val) == expected
end

local function CopyBoolSetting(src, dst, key)
    if src[key] ~= nil and type(src[key]) == "boolean" then
        dst[key] = src[key]
    end
end

local function CopyNumSetting(src, dst, key)
    if src[key] ~= nil and type(src[key]) == "number" then
        dst[key] = src[key]
    end
end

local function CopyStringSetting(src, dst, key)
    if src[key] ~= nil and type(src[key]) == "string" then
        dst[key] = src[key]
    end
end

local function CopyTableSetting(src, dst, key, validator)
    if src[key] ~= nil and type(src[key]) == "table" then
        if not validator or validator(src[key]) then
            dst[key] = {}
            for k, v in pairs(src[key]) do
                dst[key][k] = v
            end
        end
    end
end

function addon:ImportConfig(encodedStr)
    if not self.db then return nil, "Addon not initialized" end

    -- Strip whitespace
    encodedStr = string.gsub(encodedStr, "%s+", "")

    -- Check prefix
    local prefixLen = #EXPORT_PREFIX
    if string.sub(encodedStr, 1, prefixLen) ~= EXPORT_PREFIX then
        return nil, "Invalid config string (missing header). Make sure you copied the entire string."
    end

    -- Base64 decode
    local b64part = string.sub(encodedStr, prefixLen + 1)
    if #b64part == 0 then
        return nil, "Config string is empty after header."
    end

    local ok, decoded = pcall(b64decode, b64part)
    if not ok or not decoded or #decoded == 0 then
        return nil, "Failed to decode config string. It may be corrupted or truncated."
    end

    -- Deserialize
    local ok2, data = pcall(Deserialize, decoded)
    if not ok2 or type(data) ~= "table" then
        local errMsg = type(data) == "string" and data or "unknown error"
        return nil, "Failed to parse config data: " .. errMsg
    end

    -- Version check
    if not data.v then
        return nil, "Config string is missing version info."
    end
    if data.v > FORMAT_VERSION then
        return nil, "This config requires a newer version of TrinketedCD. Please update your addon."
    end

    local warnings = {}

    -- Validate and apply general settings
    if data.general and type(data.general) == "table" then
        CopyBoolSetting(data.general, self.db.general, "locked")
        CopyNumSetting(data.general, self.db.general, "iconSize")
        CopyBoolSetting(data.general, self.db.general, "compactMode")
        CopyBoolSetting(data.general, self.db.general, "showIconBorders")
        CopyBoolSetting(data.general, self.db.general, "showGlowOnReady")
        CopyBoolSetting(data.general, self.db.general, "showFlashOnUse")
        CopyBoolSetting(data.general, self.db.general, "showPulseOnLow")
        CopyBoolSetting(data.general, self.db.general, "showPlayerLabels")
        CopyBoolSetting(data.general, self.db.general, "showSpellTooltips")
        CopyBoolSetting(data.general, self.db.general, "trackOutsideArena")
        CopyTableSetting(data.general, self.db.general, "activeGlowColor", function(t)
            return type(t.r) == "number" and type(t.g) == "number" and type(t.b) == "number"
        end)
    end

    -- Validate and apply party settings
    if data.party and type(data.party) == "table" then
        CopyBoolSetting(data.party, self.db.party, "enabled")
        CopyNumSetting(data.party, self.db.party, "iconSize")
        CopyNumSetting(data.party, self.db.party, "gridCols")
        CopyNumSetting(data.party, self.db.party, "gridRows")
        CopyBoolSetting(data.party, self.db.party, "anchorToFrames")
        CopyStringSetting(data.party, self.db.party, "anchorSide")
        CopyNumSetting(data.party, self.db.party, "anchorOffsetX")
        CopyNumSetting(data.party, self.db.party, "anchorOffsetY")
    end

    -- Validate and apply grids
    if data.grids and type(data.grids) == "table" then
        -- Build class lookup
        local validClasses = {}
        for _, c in ipairs(self.ALL_CLASSES) do
            validClasses[c] = true
        end

        for className, teams in pairs(data.grids) do
            if not validClasses[className] then
                warnings[#warnings + 1] = "Unknown class '" .. tostring(className) .. "' skipped."
            elseif type(teams) == "table" then
                if not self.db.cooldowns.grids[className] then
                    self.db.cooldowns.grids[className] = {}
                end
                for team, grid in pairs(teams) do
                    if team == "party" then
                        if type(grid) == "table" and type(grid.rows) == "number" and type(grid.cols) == "number" and type(grid.slots) == "table" then
                            -- Validate spell names in slots
                            local cleanSlots = {}
                            for i, slot in ipairs(grid.slots) do
                                if type(slot) ~= "string" then
                                    cleanSlots[i] = ""
                                elseif slot == "" or slot == "PvP Trinket" or slot == "Racial" then
                                    cleanSlots[i] = slot
                                elseif self.COOLDOWN_DB[slot] then
                                    cleanSlots[i] = slot
                                else
                                    cleanSlots[i] = ""
                                    warnings[#warnings + 1] = "Unknown spell '" .. slot .. "' removed from " .. className .. " " .. team .. " grid."
                                end
                            end

                            -- Validate disabled table
                            local cleanDisabled = {}
                            if type(grid.disabled) == "table" then
                                for k, v in pairs(grid.disabled) do
                                    if type(k) == "number" and type(v) == "boolean" then
                                        cleanDisabled[k] = v
                                    end
                                end
                            end

                            self.db.cooldowns.grids[className][team] = {
                                rows = math.floor(grid.rows),
                                cols = math.floor(grid.cols),
                                slots = cleanSlots,
                                disabled = cleanDisabled,
                            }
                        end
                    end
                end
            end
        end
    else
        warnings[#warnings + 1] = "No grid data found in config string."
    end

    -- Refresh display
    self:RefreshAllBars()

    local warnStr = nil
    if #warnings > 0 then
        warnStr = table.concat(warnings, "\n")
    end
    return true, warnStr
end
