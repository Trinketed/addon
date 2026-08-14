---------------------------------------------------------------------------
-- TrinketedHistory: CompLabels.lua
--
-- Comp naming + class icons, kept in lockstep with the Trinketed app.
-- The decision tree is a port of trinketed_pipeline/comps/detector.py
-- (detect_comp); the data tables live in CompLabelsData.lua, GENERATED
-- from the app's canonical registry by scripts/export-comp-labels.py in
-- the web repo. Never hand-edit the data file — regenerate it.
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local CompLabels = {}
addon.CompLabels = CompLabels

local function data()
    return addon.CompLabelsData or {}
end

---------------------------------------------------------------------------
-- Class icons (inline texture escapes for FontStrings)
---------------------------------------------------------------------------
local CLASS_ICONS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- CLASS_ICON_TCOORDS is provided by FrameXML, keyed "WARRIOR", "DEATHKNIGHT".
local function iconKey(class)
    if not class then return nil end
    return class:upper():gsub("%s+", "")
end

-- Inline icon escape for one class, or "" when unknown.
function CompLabels.ClassIcon(class, size)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[iconKey(class)]
    if not coords then return "" end
    size = size or 12
    return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t"):format(
        CLASS_ICONS_TEXTURE, size, size,
        coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256
    )
end

-- Concatenated icons for a team table ({ {class=...}, ... }).
function CompLabels.TeamIcons(team, size)
    if not team then return "" end
    local parts = {}
    for _, member in ipairs(team) do
        local icon = CompLabels.ClassIcon(member.class, size)
        if icon ~= "" then table.insert(parts, icon) end
    end
    return table.concat(parts, "")
end

-- Icons for a slash-separated class key ("Druid/Rogue").
function CompLabels.KeyIcons(compKey, size)
    if not compKey then return "" end
    local parts = {}
    for class in compKey:gmatch("[^/]+") do
        local icon = CompLabels.ClassIcon(class, size)
        if icon ~= "" then table.insert(parts, icon) end
    end
    return table.concat(parts, "")
end

---------------------------------------------------------------------------
-- Comp label detection (port of detect_comp)
---------------------------------------------------------------------------
local function lowerOrNil(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value:lower()
end

local function titleCase(value)
    return (value:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- Sorted { {cls=..., spec=...|nil}, ... } from a team; nil when unusable.
-- Deliberate divergence from the app: a member with class "Unknown"
-- yields NO label (nil) rather than the app's "Resto/Unknown" — in-game
-- we'd rather show the colored roster than a half-known abbreviation.
local function normalizedPairs(team)
    if not team or #team == 0 then return nil end
    local pairsOut = {}
    for _, member in ipairs(team) do
        local cls = lowerOrNil(member.class)
        if cls and cls ~= "unknown" then
            table.insert(pairsOut, { cls = cls, spec = lowerOrNil(member.spec) })
        end
    end
    if #pairsOut ~= #team then return nil end
    table.sort(pairsOut, function(a, b)
        if a.cls ~= b.cls then return a.cls < b.cls end
        return (a.spec or "") < (b.spec or "")
    end)
    return pairsOut
end

local function classKey(pairsIn)
    local classes = {}
    for _, p in ipairs(pairsIn) do table.insert(classes, p.cls) end
    table.sort(classes)
    return table.concat(classes, "|")
end

-- 3v3 spec-aware names use (class, spec-prefix) tuples; empty prefix
-- matches any spec. Greedy multiset match, mirroring _match_spec_comps.
local function matchSpecComp3v3(flatKey, pairsIn)
    local wanted = {}
    for token in flatKey:gmatch("[^|]+") do
        local cls, prefix = token:match("^(.-):(.*)$")
        table.insert(wanted, { cls = cls, prefix = prefix })
    end
    if #wanted ~= #pairsIn then return false end
    local used = {}
    for _, want in ipairs(wanted) do
        local found = nil
        for i, p in ipairs(pairsIn) do
            if not used[i] and p.cls == want.cls then
                if want.prefix == "" or (p.spec and p.spec:sub(1, #want.prefix) == want.prefix) then
                    found = i
                    break
                end
            end
        end
        if not found then return false end
        used[found] = true
    end
    return true
end

local function formatGenerated(pairsIn)
    local d = data()
    local labels = {}
    for _, p in ipairs(pairsIn) do
        if d.pureDpsClasses and d.pureDpsClasses[p.cls] then
            table.insert(labels, (d.pureDps and d.pureDps[p.cls]) or titleCase(p.cls))
        else
            local hybrid = d.hybridSpecLabels and p.spec
                and d.hybridSpecLabels[p.cls .. ":" .. p.spec]
            table.insert(labels, hybrid or titleCase(p.cls))
        end
    end
    table.sort(labels)
    return table.concat(labels, "/")
end

-- The comp label for a team table, or nil when unrecognised — the same
-- answer the app's detect_comp gives for the same roster.
function CompLabels.GetLabel(team)
    local pairsIn = normalizedPairs(team)
    if not pairsIn then return nil end
    local d = data()
    local size = #pairsIn
    local allHaveSpec = true
    for _, p in ipairs(pairsIn) do
        if not p.spec then allHaveSpec = false end
    end

    if size == 2 and d.curated2v2 then
        local key = {}
        for _, p in ipairs(pairsIn) do
            table.insert(key, p.cls .. ":" .. (p.spec or ""))
        end
        local curated = d.curated2v2[table.concat(key, "|")]
        if curated then return curated end
    end

    if size == 2 and allHaveSpec then
        return formatGenerated(pairsIn)
    end

    if size == 3 and allHaveSpec and d.specComps3v3 then
        for flatKey, label in pairs(d.specComps3v3) do
            if matchSpecComp3v3(flatKey, pairsIn) then return label end
        end
    end

    local registry = (size == 3 and d.comps3v3) or (size == 2 and d.comps2v2) or nil
    if registry then
        local named = registry[classKey(pairsIn)]
        if named then return named end
    end

    if (size == 2 or size == 3) and allHaveSpec then
        return formatGenerated(pairsIn)
    end
    return nil
end
