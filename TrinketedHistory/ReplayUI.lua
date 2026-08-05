---------------------------------------------------------------------------
-- TrinketedHistory: ReplayUI.lua
-- Replay viewer window: unit frames, event feed, timeline, transport
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C
local replayFrame = nil
local session = nil

-- Layout constants
-- The window is sized to match the main options-panel footprint (932x520) so it
-- fits any screen without scaling. The two teams are laid out side-by-side in
-- two columns (friendly | enemy) rather than stacked, so even 5v5 fits the short
-- height, and the combat feed sits in a third column on the right.
local FRAME_W, FRAME_H = 932, 520
local UNIT_PANEL_W = 512        -- spans both unit columns; feed begins just past it
local FEED_PANEL_W = 408        -- right-hand combat feed column
local TRANSPORT_H = 58
local UNIT_FRAME_W = 160
local UNIT_FRAME_H = 34
local HP_BAR_H = 10
local POWER_BAR_H = 5
local CD_ICON_SIZE = 16
local CD_ICON_GAP = 1
local CD_COLS = 4               -- cooldown icons wrap after this many (keeps them inside the column)
local AURA_ICON_SIZE = 16
local AURA_ICON_GAP = 2
local AURA_ROW_GAP = 2
-- Vertical distance between stacked unit slots within a column: the frame plus
-- two aura rows (buffs + debuffs) beneath it, with gaps.
local UNIT_ROW_STRIDE = UNIT_FRAME_H + 2 * (AURA_ICON_SIZE + AURA_ROW_GAP)
-- Two-column unit layout (coordinates are inside frame.unitPanel).
local UNIT_COL1_X = 4           -- friendly column
local UNIT_COL2_X = 256         -- enemy column
local UNIT_COL_DIVIDER_X = 248  -- vertical divider between the two columns
-- Aura icons per row that fit inside one team column without crossing the
-- divider into the neighboring column (13 at current sizes). Rows render at
-- most this many; with "All auras" on, a heavily buffed unit's overflow is
-- dropped rather than bleeding into the other team's column.
local AURA_MAX_COLS = math.floor((UNIT_COL_DIVIDER_X - UNIT_COL1_X - 4) / (AURA_ICON_SIZE + AURA_ICON_GAP))
local UNITS_TOP_Y = -22         -- first unit row, just below the section labels
local FEED_ROW_H = 20
local FEED_ICON_SIZE = 14

-- DRList-1.0 is used to decide whether an aura is a diminishing-returns CC
-- (stun/incapacitate/silence/root/etc.). Loaded optionally — if the lib is
-- absent we simply fall back to SpellDB-only filtering.
local DRList = LibStub("DRList-1.0", true)

-- Categories from SpellDB that count as "show-worthy" auras on a unit frame.
local AURA_CATS = {
    offensive_cd = true, defensive_cd = true, cc_break = true,
    trinket = true, racial = true, interrupt = true,
    healing_cd = true, mobility = true,
}

local function ShouldShowAura(spellID, spellName)
    if not spellID then return false end
    -- Rank-proof: off-rank aura IDs resolve to their curated entry by name.
    local dbEntry = select(2, addon.ResolveSpell(spellID, spellName))
    if dbEntry and AURA_CATS[dbEntry.cat] then return true end
    if DRList and DRList:GetCategoryBySpellID(spellID) then return true end
    return false
end

local SPEEDS = { 0.5, 1, 2, 4 }
local speedIndex = 2  -- default 1x

---------------------------------------------------------------------------
-- Helper: format seconds as m:ss
---------------------------------------------------------------------------
local function FormatTime(secs)
    if not secs or secs < 0 then secs = 0 end
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    return string.format("%d:%02d", m, s)
end

---------------------------------------------------------------------------
-- Helper: format seconds as m:ss.t (with tenths)
---------------------------------------------------------------------------
local function FormatTimeTenths(secs)
    if not secs or secs < 0 then secs = 0 end
    local m = math.floor(secs / 60)
    local s = secs % 60
    return string.format("%d:%04.1f", m, s)
end

---------------------------------------------------------------------------
-- Helper: abbreviate number (1234 -> "1.2k")
---------------------------------------------------------------------------
local function AbbrevNumber(n)
    if not n or type(n) ~= "number" then return "" end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(math.floor(n))
end

---------------------------------------------------------------------------
-- Helper: get class color escape string
---------------------------------------------------------------------------
local function ClassColorStr(class)
    local rgb = addon.CLASS_COLORS_RGB and addon.CLASS_COLORS_RGB[class]
    if rgb then
        return string.format("|cff%02x%02x%02x", rgb.r * 255, rgb.g * 255, rgb.b * 255)
    end
    return "|cffffffff"
end

---------------------------------------------------------------------------
-- Category colors for feed and markers
---------------------------------------------------------------------------
local CAT_COLORS = {
    damage       = { r = 1.0, g = 0.3, b = 0.3 },
    healing      = { r = 0.3, g = 1.0, b = 0.3 },
    death        = { r = 1.0, g = 0.1, b = 0.1 },
    offensive_cd = { r = 1.0, g = 0.5, b = 0.1 },
    defensive_cd = { r = 0.91, g = 0.73, b = 0.14 },
    interrupt    = { r = 1.0, g = 0.3, b = 0.2 },
    trinket      = { r = 1.0, g = 0.2, b = 0.8 },
    racial       = { r = 0.91, g = 0.73, b = 0.14 },
    cc_break     = { r = 0.91, g = 0.73, b = 0.14 },
    healing_cd   = { r = 0.3, g = 1.0, b = 0.3 },
    mobility     = { r = 0.3, g = 0.6, b = 1.0 },
    dispel       = { r = 0.66, g = 0.33, b = 0.97 },
    utility      = { r = 0.5, g = 0.5, b = 0.5 },
    aura         = { r = 0.6, g = 0.4, b = 0.8 },
    cast         = { r = 0.7, g = 0.7, b = 0.7 },
    miss         = { r = 0.5, g = 0.5, b = 0.5 },
    power        = { r = 0.3, g = 0.5, b = 0.8 },
}

---------------------------------------------------------------------------
-- Dev mode (toggled with /trinketed dev): append a raw recorded event to
-- GameTooltip as sorted key = value lines. Nested tables render one level
-- deep, which covers everything a v3 event can contain.
---------------------------------------------------------------------------
local function DevValueStr(v)
    local t = type(v)
    if t == "table" then
        local parts = {}
        for k, vv in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. (type(vv) == "table" and "{...}" or tostring(vv))
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

local function AddRawEventTooltip(feedEv)
    -- Prefer the raw recorded event; fall back to the derived feed entry.
    local raw = feedEv.raw or feedEv
    if GameTooltip:NumLines() > 0 then
        GameTooltip:AddLine(" ")
    end
    GameTooltip:AddLine("Raw event", C.accent[1], C.accent[2], C.accent[3])
    local keys = {}
    for k in pairs(raw) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        GameTooltip:AddDoubleLine(tostring(k), DevValueStr(raw[k]),
            0.55, 0.55, 0.55, 0.9, 0.9, 0.9)
    end
end

---------------------------------------------------------------------------
-- Death Recap: clicking a death row in the feed opens a compact panel with
-- the victim's final seconds — HP% (from the 200ms unit_state polls) beside
-- every hit, heal, aura and defensive cast involving them, ending at the
-- death. All state lives in this one table; the frame and its line
-- FontStrings are built once and reused across opens.
---------------------------------------------------------------------------
local recap = {
    WINDOW = 8,      -- seconds shown before the death
    ROW_H = 14,
    MAX_LINES = 80,  -- hard cap on pooled line FontStrings
    -- Display labels for SpellDB categories.
    CAT_LABELS = {
        offensive_cd = "offensive CD", defensive_cd = "defensive",
        healing_cd = "healing CD", cc_break = "CC break", trinket = "trinket",
        mobility = "mobility", racial = "racial", interrupt = "interrupt",
        dispel = "dispel", utility = "utility",
    },
    -- SpellDB categories worth surfacing when the victim casts them (their
    -- own reactions to the kill attempt).
    SELF_CAST_CATS = {
        defensive_cd = true, cc_break = true, trinket = true,
        healing_cd = true, mobility = true, racial = true,
    },
}

-- Category tag for a spellID: DRList CC category first (stun/silence/etc.),
-- then SpellDB category label.
function recap:SpellTag(spellID, spellName)
    if not spellID then return nil end
    if DRList then
        local drCat = DRList:GetCategoryBySpellID(spellID)
        if drCat then return drCat end
    end
    local db = select(2, addon.ResolveSpell(spellID, spellName))
    if db and db.cat then return self.CAT_LABELS[db.cat] or db.cat end
    return nil
end

-- HP% column text at time t from the collected samples, colored by severity.
function recap:HPStr(samples, t)
    local pct
    for i = 1, #samples do
        if samples[i].t <= t then pct = samples[i].pct else break end
    end
    if not pct then return "|cff555555 ??%|r" end
    local hex
    if pct > 0.5 then hex = "55ff55"
    elseif pct > 0.2 then hex = "ffd24d"
    else hex = "ff5555" end
    return string.format("|cff%s%3d%%|r", hex, math.floor(pct * 100 + 0.5))
end

-- Build the display lines for the victim's final WINDOW seconds. Single pass
-- over the raw (time-ordered) event list: victim HP is tracked from the start
-- so the window opens with the last known HP even if the first in-window poll
-- comes late; everything targeting the victim (plus their own notable casts)
-- inside the window becomes a line. Returns an array of formatted strings.
function recap:BuildLines(victimGUID, deathTime)
    if not (session and session.parsed) then return {} end
    local roster = session.parsed.roster or {}
    local windowStart = deathTime - self.WINDOW

    local function nameStr(name, guid)
        local info = guid and roster[guid]
        return ClassColorStr(info and info.class) .. (name or "?") .. "|r"
    end

    local samples = {}          -- victim HP polls inside the window { t, pct }
    local hp, hpMax, prePct     -- running victim HP; prePct = last pct before window
    local entries = {}          -- { t, text } in event order

    for _, ev in ipairs(session.parsed.events) do
        if ev.t > deathTime then break end
        local ty = ev.type
        if ty == "unit_state" then
            if ev.guid == victimGUID then
                if ev.hp then hp = ev.hp end
                if ev.hpMax then hpMax = ev.hpMax end
                if hp and hpMax and hpMax > 0 then
                    if ev.t >= windowStart then
                        samples[#samples + 1] = { t = ev.t, pct = hp / hpMax }
                    else
                        prePct = hp / hpMax
                    end
                end
            end
        elseif ev.t >= windowStart then
            local text
            if ty == "damage" and ev.dstGUID == victimGUID then
                local spellName = ev.spell
                if ev.subtype == "auto_melee" then spellName = "Melee"
                elseif ev.subtype == "auto_ranged" then spellName = "Auto Shot"
                elseif ev.subtype == "env" then spellName = ev.envType or "Environment" end
                local amt = AbbrevNumber(ev.amount)
                if ev.critical then amt = amt .. "*" end
                text = nameStr(ev.src, ev.srcGUID) .. "  |cffff4d4d" .. (spellName or "?") .. "  -" .. amt .. "|r"
            elseif ty == "heal" and ev.dstGUID == victimGUID then
                local eff = (ev.amount or 0) - (ev.overhealing or 0)
                if eff > 0 then
                    local amt = AbbrevNumber(eff)
                    if ev.critical then amt = amt .. "*" end
                    text = nameStr(ev.src, ev.srcGUID) .. "  |cff4dff4d" .. (ev.spell or "?") .. "  +" .. amt .. "|r"
                end
            elseif ty == "absorb" and ev.dstGUID == victimGUID then
                text = nameStr(ev.src, ev.srcGUID) .. "  |cffffff66" .. (ev.spell or "?") .. "  " .. AbbrevNumber(ev.amount) .. " abs|r"
            elseif ty == "miss" and ev.dstGUID == victimGUID then
                local missSpell = ev.spell or (ev.subtype == "range" and "Auto Shot") or "Melee"
                text = nameStr(ev.src, ev.srcGUID) .. "  |cff888888" .. missSpell .. "  " .. (ev.missType or "MISS") .. "|r"
            elseif ty == "aura_applied" and ev.dstGUID == victimGUID then
                local prefix = (ev.auraType == "DEBUFF") and "|cffff8080+" or "|cff80ff80+"
                text = prefix .. (ev.spell or "?") .. "|r"
                local tag = self:SpellTag(ev.spellID, ev.spell)
                if tag then text = text .. " |cff888888[" .. tag .. "]|r" end
                if ev.src then text = nameStr(ev.src, ev.srcGUID) .. "  " .. text end
            elseif ty == "aura_break" and ev.dstGUID == victimGUID then
                text = "|cffff8800" .. (ev.spell or "?") .. " broken|r"
                if ev.extraSpell then text = text .. " |cff888888(by " .. ev.extraSpell .. ")|r" end
            elseif (ty == "dispel" or ty == "steal") and ev.dstGUID == victimGUID then
                local verb = ty == "steal" and "stole" or "dispelled"
                text = nameStr(ev.src, ev.srcGUID) .. "  |cffa855f7" .. verb .. " " .. (ev.extraSpell or "?") .. "|r"
            elseif ty == "interrupt" and ev.dstGUID == victimGUID then
                text = nameStr(ev.src, ev.srcGUID) .. "  |cffff5533interrupted"
                if ev.extraSpell then text = text .. " (" .. ev.extraSpell .. ")" end
                text = text .. "|r"
            elseif ty == "cast_success" and ev.srcGUID == victimGUID then
                local victimInfo = roster[victimGUID]
                local db = select(2, addon.ResolveSpell(ev.spellID, ev.spell,
                    victimInfo and victimInfo.class))
                if db and self.SELF_CAST_CATS[db.cat] then
                    text = nameStr(ev.src, ev.srcGUID) .. "  |cff4dd2ffused " .. (ev.spell or "?") .. "|r"
                        .. " |cff888888[" .. (self.CAT_LABELS[db.cat] or db.cat) .. "]|r"
                end
            elseif ty == "death" and ev.dstGUID == victimGUID then
                text = "|cffff0000DEATH|r  " .. nameStr(ev.dst, ev.dstGUID)
            end
            if text then
                entries[#entries + 1] = { t = ev.t, text = text }
            end
        end
    end

    if prePct then
        table.insert(samples, 1, { t = windowStart, pct = prePct })
    end

    -- Keep only the newest MAX_LINES entries (the ones closest to the death).
    if #entries > self.MAX_LINES then
        local trimmed = {}
        for i = #entries - self.MAX_LINES + 1, #entries do
            trimmed[#trimmed + 1] = entries[i]
        end
        entries = trimmed
    end

    -- Compose final strings: relative time + HP% column + event text.
    local lines = {}
    for _, e in ipairs(entries) do
        lines[#lines + 1] = string.format("|cff888888%5.1fs|r %s  %s",
            e.t - deathTime, self:HPStr(samples, e.t), e.text)
    end
    if #lines == 0 then
        lines[1] = "|cff888888No recorded events in the final " .. self.WINDOW .. "s.|r"
    end
    return lines
end

-- Lazily build the recap panel (once). Parented to the replay window so it
-- hides with it; ESC closes it via UISpecialFrames.
function recap:EnsureFrame()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "TrinketedDeathRecapFrame", replayFrame, "BackdropTemplate")
    f:SetSize(360, 300)
    f:SetPoint("TOPRIGHT", replayFrame.feedPanel, "TOPLEFT", -4, 0)
    f:SetFrameLevel(replayFrame.feedPanel:GetFrameLevel() + 10)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    f:SetBackdropColor(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], C.bgRaised[4] or 1)
    f:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], C.borderDefault[4] or 1)
    f:Hide()
    tinsert(UISpecialFrames, "TrinketedDeathRecapFrame")

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(lib.FONT_DISPLAY, 11, "")
    f.title:SetPoint("TOPLEFT", 8, -7)
    f.title:SetWidth(360 - 32)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])

    f.closeBtn = CreateFrame("Button", nil, f)
    f.closeBtn:SetSize(16, 16)
    f.closeBtn:SetPoint("TOPRIGHT", -4, -4)
    f.closeBtn.label = f.closeBtn:CreateFontString(nil, "OVERLAY")
    f.closeBtn.label:SetFont(lib.FONT_MONO, 11, "")
    f.closeBtn.label:SetPoint("CENTER")
    f.closeBtn.label:SetText("x")
    f.closeBtn.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    f.closeBtn:SetScript("OnEnter", function(self)
        self.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    f.closeBtn:SetScript("OnLeave", function(self)
        self.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    f.closeBtn:SetScript("OnClick", function() f:Hide() end)

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 6, -26)
    f.scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetWidth(360 - 34)
    f.content:SetHeight(1)
    f.scroll:SetScrollChild(f.content)

    self.rows = {}
    self.frame = f
    return f
end

-- Open (or repopulate — only one recap at a time) for a feed death event.
-- Purely read-only over the event list; never touches playback state.
function recap:Open(deathEv)
    if not (session and session.parsed) then return end
    local victimGUID = deathEv.dstGUID
    if not victimGUID then
        -- Fallback: resolve the victim by name from the roster.
        for guid, info in pairs(session.parsed.roster or {}) do
            if info.name == deathEv.dstName then victimGUID = guid; break end
        end
    end
    if not victimGUID then return end

    local f = self:EnsureFrame()
    f.title:SetText("Death Recap |cff888888—|r "
        .. ClassColorStr(deathEv.dstClass) .. (deathEv.dstName or "?") .. "|r"
        .. "  |cff888888" .. FormatTimeTenths(deathEv.time) .. "|r")

    local lines = self:BuildLines(victimGUID, deathEv.time)
    for i, text in ipairs(lines) do
        local row = self.rows[i]
        if not row then
            row = f.content:CreateFontString(nil, "OVERLAY")
            row:SetFont(lib.FONT_MONO, 9, "")
            row:SetPoint("TOPLEFT", 2, -((i - 1) * self.ROW_H))
            row:SetWidth(f.content:GetWidth() - 4)
            row:SetJustifyH("LEFT")
            row:SetWordWrap(false)
            self.rows[i] = row
        end
        row:SetText(text)
        lib:FitText(row)  -- long recap lines shrink instead of clipping
        row:Show()
    end
    for i = #lines + 1, #self.rows do
        self.rows[i]:Hide()
    end

    local totalH = #lines * self.ROW_H
    f.content:SetHeight(math.max(totalH, 1))
    f:Show()
    -- Chronological, ending at the death: start scrolled to the bottom.
    f.scroll:SetVerticalScroll(math.max(0, totalH - (f.scroll:GetHeight() or 0)))
end

function recap:Close()
    if self.frame then self.frame:Hide() end
end

---------------------------------------------------------------------------
-- Create a single unit frame
---------------------------------------------------------------------------
local function CreateUnitFrame(parent, yOffset)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(UNIT_FRAME_W, UNIT_FRAME_H)
    f:SetPoint("TOPLEFT", 10, yOffset)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    f:SetBackdropColor(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], C.bgRaised[4] or 1)
    f:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], C.borderSubtle[4] or 1)

    -- Name label
    f.nameText = f:CreateFontString(nil, "OVERLAY")
    f.nameText:SetFont(lib.FONT_BODY, 10, "")
    f.nameText:SetPoint("TOPLEFT", 4, -3)
    f.nameText:SetWidth(UNIT_FRAME_W - 60)
    f.nameText:SetWordWrap(false)
    f.nameText:SetJustifyH("LEFT")

    -- HP text (current/max). Explicit width budget so it can never spill
    -- left into the name column: name ends at 4+100=104, hp starts at
    -- 160-4-52=104. Long values shrink-to-fit instead.
    f.hpText = f:CreateFontString(nil, "OVERLAY")
    f.hpText:SetFont(lib.FONT_MONO, 9, "")
    f.hpText:SetPoint("TOPRIGHT", -4, -3)
    f.hpText:SetWidth(52)
    f.hpText:SetWordWrap(false)
    f.hpText:SetJustifyH("RIGHT")
    f.hpText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- HP bar background
    f.hpBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.hpBarBg:SetPoint("TOPLEFT", 3, -15)
    f.hpBarBg:SetSize(UNIT_FRAME_W - 6, HP_BAR_H)
    f.hpBarBg:SetColorTexture(0, 0, 0, 0.5)

    -- HP bar fill
    f.hpBar = f:CreateTexture(nil, "ARTWORK")
    f.hpBar:SetPoint("TOPLEFT", f.hpBarBg, "TOPLEFT")
    f.hpBar:SetHeight(HP_BAR_H)
    f.hpBar:SetColorTexture(0.5, 0.5, 0.5, 1)

    -- Power bar background
    f.powerBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.powerBarBg:SetPoint("TOPLEFT", f.hpBarBg, "BOTTOMLEFT", 0, -1)
    f.powerBarBg:SetSize(UNIT_FRAME_W - 6, POWER_BAR_H)
    f.powerBarBg:SetColorTexture(0, 0, 0, 0.5)

    -- Power bar fill
    f.powerBar = f:CreateTexture(nil, "ARTWORK")
    f.powerBar:SetPoint("TOPLEFT", f.powerBarBg, "TOPLEFT")
    f.powerBar:SetHeight(POWER_BAR_H)
    f.powerBar:SetColorTexture(0, 0, 1, 1)

    f.icons = {}           -- pool of CD icon frames (positioned externally)
    f.auraBuffIcons = {}   -- pool for buff row (immediately below HP bar)
    f.auraDebuffIcons = {} -- pool for debuff row (below the buff row)

    -- State tracking for lerp
    f.targetHealth = 0
    f.displayHealth = 0
    f.guid = nil

    return f
end

---------------------------------------------------------------------------
-- Create (or reuse) an aura icon below a unit frame in the given pool
---------------------------------------------------------------------------
local function GetOrCreateAuraIcon(uf, pool, idx)
    local icon = pool[idx]
    if icon then return icon end

    icon = CreateFrame("Frame", nil, uf:GetParent())
    icon:SetSize(AURA_ICON_SIZE, AURA_ICON_SIZE)
    icon.bgTex = icon:CreateTexture(nil, "BACKGROUND")
    icon.bgTex:SetPoint("TOPLEFT", -1, 1)
    icon.bgTex:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.bgTex:SetColorTexture(0.04, 0.04, 0.05, 1)
    icon.bdrT = icon:CreateTexture(nil, "BORDER")
    icon.bdrT:SetPoint("TOPLEFT", -1, 1); icon.bdrT:SetPoint("TOPRIGHT", 1, 1); icon.bdrT:SetHeight(1)
    icon.bdrB = icon:CreateTexture(nil, "BORDER")
    icon.bdrB:SetPoint("BOTTOMLEFT", -1, -1); icon.bdrB:SetPoint("BOTTOMRIGHT", 1, -1); icon.bdrB:SetHeight(1)
    icon.bdrL = icon:CreateTexture(nil, "BORDER")
    icon.bdrL:SetPoint("TOPLEFT", -1, 1); icon.bdrL:SetPoint("BOTTOMLEFT", -1, -1); icon.bdrL:SetWidth(1)
    icon.bdrR = icon:CreateTexture(nil, "BORDER")
    icon.bdrR:SetPoint("TOPRIGHT", 1, 1); icon.bdrR:SetPoint("BOTTOMRIGHT", 1, -1); icon.bdrR:SetWidth(1)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawBling(false)
    -- Light swipe so the spell art remains readable while the pie still hints
    -- at remaining fraction.
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.25)
    -- We render our own duration text below so it's visible regardless of the
    -- player's countdownForCooldowns CVar.
    icon.cooldown:SetHideCountdownNumbers(true)

    -- Duration text anchored to the bottom-right corner so it doesn't sit over
    -- the center of the spell icon.
    icon.durText = icon:CreateFontString(nil, "OVERLAY")
    icon.durText:SetFont(lib.FONT_MONO, 10, "OUTLINE")
    icon.durText:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.durText:SetTextColor(1, 1, 1, 1)

    -- Stack count shown in top-left corner for stackable auras (Lifebloom,
    -- Wound Poison, Deadly Poison, Sunder Armor, etc.).
    icon.stackText = icon:CreateFontString(nil, "OVERLAY")
    icon.stackText:SetFont(lib.FONT_MONO, 10, "OUTLINE")
    icon.stackText:SetPoint("TOPLEFT", 1, -1)
    icon.stackText:SetTextColor(1, 0.95, 0.45, 1)

    icon.tipBtn = CreateFrame("Button", nil, icon)
    icon.tipBtn:SetAllPoints()
    icon.tipBtn:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)

    pool[idx] = icon
    return icon
end

local function FormatAuraDuration(seconds)
    if seconds >= 60 then return string.format("%dm", math.floor(seconds / 60)) end
    if seconds >= 10 then return string.format("%d", math.floor(seconds + 0.5)) end
    if seconds >= 1  then return string.format("%.1f", seconds) end
    return ""
end

---------------------------------------------------------------------------
-- Update a unit frame from replay state
---------------------------------------------------------------------------
local function UpdateUnitFrame(uf, playerState, currentTime, seeking, showAllAuras)
    if not playerState then
        uf:Hide()
        for _, ai in ipairs(uf.auraBuffIcons)   do ai:Hide() end
        for _, ai in ipairs(uf.auraDebuffIcons) do ai:Hide() end
        return
    end
    uf:Show()

    -- Name + spec + class color
    local name = playerState.name or "?"
    if playerState.spec then
        name = name .. " (" .. playerState.spec .. ")"
    end
    local classColor = addon.CLASS_COLORS_RGB[playerState.class]
    if classColor then
        uf.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    else
        uf.nameText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    end
    uf.nameText:SetText(name)
    lib:FitText(uf.nameText)  -- name + spec can overrun the column on low-DPI screens

    -- HP
    local hp = playerState.health
    local hpMax = playerState.healthMax
    uf.targetHealth = hp

    if seeking then
        uf.displayHealth = hp
    end
    -- Lerp display health toward target
    local displayHP = uf.displayHealth
    if math.abs(displayHP - hp) > 1 then
        uf.displayHealth = displayHP + (hp - displayHP) * 0.15
    else
        uf.displayHealth = hp
    end

    local barWidth = UNIT_FRAME_W - 6
    local hpFrac = hpMax > 0 and (uf.displayHealth / hpMax) or 0
    uf.hpBar:SetWidth(math.max(1, barWidth * hpFrac))

    -- HP bar color by class
    if classColor then
        uf.hpBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
    end

    -- HP text
    if hpMax > 0 then
        uf.hpText:SetText(math.floor(uf.displayHealth) .. "/" .. hpMax)
    else
        uf.hpText:SetText("?")
    end
    lib:FitText(uf.hpText)

    -- Power
    local power = playerState.power
    local powerMax = playerState.powerMax
    local powerType = playerState.powerType
    if powerMax > 0 then
        uf.powerBarBg:Show()
        uf.powerBar:Show()
        local powerFrac = power / powerMax
        uf.powerBar:SetWidth(math.max(1, barWidth * powerFrac))
        local pc = addon.POWER_COLORS[powerType]
        if pc then
            uf.powerBar:SetColorTexture(pc.r, pc.g, pc.b, 1)
        end
    else
        uf.powerBarBg:Hide()
        uf.powerBar:Hide()
    end

    -- Cooldown tracker: show all class CDs to the right of the unit frame
    local hiddenCDs = TrinketedHistoryDB and TrinketedHistoryDB.settings and TrinketedHistoryDB.settings.hiddenReplayCDs or {}
    local classCDs = playerState.class and addon.CLASS_COOLDOWNS and addon.CLASS_COOLDOWNS[playerState.class]
    local visIdx = 0
    if classCDs then
        for idx, spellID in ipairs(classCDs) do
            -- Skip hidden spells
            if hiddenCDs[spellID] then
                -- ensure pooled icon is hidden
                if uf.icons[idx] then uf.icons[idx]:Hide() end
            else
                visIdx = visIdx + 1
                local icon = uf.icons[idx]
                if not icon then
                    icon = CreateFrame("Frame", nil, uf:GetParent())
                    icon:SetSize(CD_ICON_SIZE, CD_ICON_SIZE)
                    icon.bgTex = icon:CreateTexture(nil, "BACKGROUND")
                    icon.bgTex:SetPoint("TOPLEFT", -1, 1)
                    icon.bgTex:SetPoint("BOTTOMRIGHT", 1, -1)
                    icon.bgTex:SetColorTexture(0.04, 0.04, 0.05, 1)
                    icon.bdrT = icon:CreateTexture(nil, "BORDER")
                    icon.bdrT:SetPoint("TOPLEFT", -1, 1); icon.bdrT:SetPoint("TOPRIGHT", 1, 1); icon.bdrT:SetHeight(1)
                    icon.bdrB = icon:CreateTexture(nil, "BORDER")
                    icon.bdrB:SetPoint("BOTTOMLEFT", -1, -1); icon.bdrB:SetPoint("BOTTOMRIGHT", 1, -1); icon.bdrB:SetHeight(1)
                    icon.bdrL = icon:CreateTexture(nil, "BORDER")
                    icon.bdrL:SetPoint("TOPLEFT", -1, 1); icon.bdrL:SetPoint("BOTTOMLEFT", -1, -1); icon.bdrL:SetWidth(1)
                    icon.bdrR = icon:CreateTexture(nil, "BORDER")
                    icon.bdrR:SetPoint("TOPRIGHT", 1, 1); icon.bdrR:SetPoint("BOTTOMRIGHT", 1, -1); icon.bdrR:SetWidth(1)
                    icon.tex = icon:CreateTexture(nil, "ARTWORK")
                    icon.tex:SetAllPoints()
                    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
                    icon.cooldown:SetAllPoints()
                    icon.cooldown:SetDrawEdge(true)
                    icon.cooldown:SetDrawBling(false)
                    icon.cooldown:SetSwipeColor(0, 0, 0, 0.5)
                    icon.cooldown:SetHideCountdownNumbers(false)
                    icon.tipBtn = CreateFrame("Button", nil, icon)
                    icon.tipBtn:SetAllPoints()
                    icon.tipBtn:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
                    icon.tipBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    uf.icons[idx] = icon
                end

                -- Position using visible index. Wrap after CD_COLS columns so the
                -- icons stay inside the unit's column instead of bleeding into the
                -- adjacent team column or the feed.
                local col = (visIdx - 1) % CD_COLS
                local row = math.floor((visIdx - 1) / CD_COLS)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", uf, "TOPRIGHT", 4 + col * (CD_ICON_SIZE + CD_ICON_GAP), -(row * (CD_ICON_SIZE + CD_ICON_GAP)))

                -- Spell texture — faction-specific for PvP Trinket, fallback via name
                if spellID == 42292 then
                    local faction = UnitFactionGroup(playerState.team == "friendly" and "player" or "arena1")
                    if faction == "Alliance" then
                        icon.tex:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_01")
                    else
                        icon.tex:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_02")
                    end
                else
                    local texID = GetSpellTexture(spellID)
                    if not texID then
                        -- Fallback: try via spell name from SPELL_DB
                        local dbEntry = SPELL_DB and SPELL_DB[spellID]
                        if dbEntry and dbEntry.name then
                            texID = GetSpellTexture(dbEntry.name)
                        end
                    end
                    if texID then
                        icon.tex:SetTexture(texID)
                    else
                        icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    end
                end

                -- Tooltip on hover + right-click to hide
                local thisSpellID = spellID
                local dbEntry = SPELL_DB and SPELL_DB[spellID]
                local spellName = dbEntry and dbEntry.name or ""
                icon.tipBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(thisSpellID)
                    GameTooltip:AddLine("|cff888888Right-click to hide|r")
                    GameTooltip:Show()
                end)
                icon.tipBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                icon.tipBtn:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                            TrinketedHistoryDB.settings.hiddenReplayCDs[thisSpellID] = true
                        end
                        print("|cff00ccff" .. "Trinketed" .. ":|r Hidden " .. (spellName ~= "" and spellName or ("spell " .. thisSpellID)) .. " from replay CD tracker. Use the gear menu to re-enable.")
                    end
                end)

                -- Category border color
                local cat = dbEntry and dbEntry.cat or ""
                local br, bg, bb
                if cat == "trinket" or cat == "racial" or cat == "cc_break" then
                    br, bg, bb = 0.91, 0.73, 0.14
                elseif cat == "offensive_cd" then
                    br, bg, bb = 1.0, 0.2, 0.2
                elseif cat == "defensive_cd" then
                    br, bg, bb = 0.2, 0.8, 0.2
                elseif cat == "interrupt" then
                    br, bg, bb = 1.0, 0.5, 0.0
                elseif cat == "healing_cd" then
                    br, bg, bb = 0.2, 0.8, 0.2
                else
                    br, bg, bb = 0.3, 0.3, 0.3
                end

                -- Check if on cooldown
                local cd = playerState.cooldowns and playerState.cooldowns[spellID]
                if cd then
                    local elapsed = currentTime - cd.castTime
                    if elapsed < cd.cd then
                        icon.tex:SetDesaturated(true)
                        icon.cooldown:SetCooldown(GetTime() - elapsed, cd.cd)
                        icon.cooldown:Show()
                        icon.bdrT:SetColorTexture(br, bg, bb, 0.3)
                        icon.bdrB:SetColorTexture(br, bg, bb, 0.3)
                        icon.bdrL:SetColorTexture(br, bg, bb, 0.3)
                        icon.bdrR:SetColorTexture(br, bg, bb, 0.3)
                    else
                        icon.tex:SetDesaturated(false)
                        icon.cooldown:Hide()
                        icon.bdrT:SetColorTexture(br, bg, bb, 1)
                        icon.bdrB:SetColorTexture(br, bg, bb, 1)
                        icon.bdrL:SetColorTexture(br, bg, bb, 1)
                        icon.bdrR:SetColorTexture(br, bg, bb, 1)
                    end
                else
                    icon.tex:SetDesaturated(false)
                    icon.cooldown:Hide()
                    icon.bdrT:SetColorTexture(br, bg, bb, 1)
                    icon.bdrB:SetColorTexture(br, bg, bb, 1)
                    icon.bdrL:SetColorTexture(br, bg, bb, 1)
                    icon.bdrR:SetColorTexture(br, bg, bb, 1)
                end

                icon:Show()
            end
        end
        -- Hide excess pool entries
        for i = #classCDs + 1, #uf.icons do
            if uf.icons[i] then uf.icons[i]:Hide() end
        end
    else
        for i = 1, #uf.icons do
            if uf.icons[i] then uf.icons[i]:Hide() end
        end
    end

    -- ===== AURA TRACKER =====
    -- Active buffs and debuffs get their own row below the unit frame:
    --   row 1 (immediately below HP bar): BUFFs    (green border)
    --   row 2 (below row 1):               DEBUFFs (red border)
    -- Filtered to curated SpellDB/DRList entries unless showAllAuras is on,
    -- in which case every recorded aura is rendered.
    local buffs, debuffs = {}, {}
    if playerState.auras then
        for spellID, aura in pairs(playerState.auras) do
            if showAllAuras or ShouldShowAura(spellID, aura.spell) then
                if aura.auraType == "DEBUFF" then
                    table.insert(debuffs, aura)
                else
                    -- BUFF and unknown-type both go in the buff row
                    table.insert(buffs, aura)
                end
            end
        end
        local byApplied = function(a, b) return (a.applied or 0) < (b.applied or 0) end
        table.sort(buffs,   byApplied)
        table.sort(debuffs, byApplied)
    end

    local function RenderAuraRow(list, pool, rowIndex, borderColor)
        local br, bg, bb = borderColor[1], borderColor[2], borderColor[3]
        local yOffset = -(AURA_ROW_GAP + (rowIndex - 1) * (AURA_ICON_SIZE + AURA_ROW_GAP))
        local shown = math.min(#list, AURA_MAX_COLS)
        for idx = 1, shown do
            local aura = list[idx]
            local icon = GetOrCreateAuraIcon(uf, pool, idx)

            local col = idx - 1
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", uf, "BOTTOMLEFT",
                col * (AURA_ICON_SIZE + AURA_ICON_GAP), yOffset)

            local texID = GetSpellTexture(aura.spellID)
            if not texID and aura.spell then
                texID = GetSpellTexture(aura.spell)
            end
            icon.tex:SetTexture(texID or "Interface\\Icons\\INV_Misc_QuestionMark")

            icon.bdrT:SetColorTexture(br, bg, bb, 1)
            icon.bdrB:SetColorTexture(br, bg, bb, 1)
            icon.bdrL:SetColorTexture(br, bg, bb, 1)
            icon.bdrR:SetColorTexture(br, bg, bb, 1)

            local duration = aura.duration or 0
            local expires = aura.expires or 0
            local remaining = expires - currentTime
            if duration > 0 and remaining > 0 then
                icon.cooldown:SetCooldown(GetTime() - (duration - remaining), duration)
                icon.cooldown:Show()
                icon.durText:SetText(FormatAuraDuration(remaining))
                icon.durText:Show()
            else
                icon.cooldown:Hide()
                icon.durText:SetText("")
                icon.durText:Hide()
            end

            -- Stack count (only visible when > 1)
            local stacks = aura.stacks
            if stacks and stacks > 1 then
                icon.stackText:SetText(tostring(stacks))
                icon.stackText:Show()
            else
                icon.stackText:SetText("")
                icon.stackText:Hide()
            end

            local thisSpellID = aura.spellID
            local thisExpires = expires
            icon.tipBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(thisSpellID)
                local r = thisExpires - currentTime
                if r > 0 then
                    GameTooltip:AddLine(string.format("%.1fs remaining", r), 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            icon.tipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            icon:Show()
        end
        for i = shown + 1, #pool do
            if pool[i] then pool[i]:Hide() end
        end
    end

    RenderAuraRow(buffs,   uf.auraBuffIcons,   1, { 0.29, 0.87, 0.50 })
    RenderAuraRow(debuffs, uf.auraDebuffIcons, 2, { 0.90, 0.22, 0.22 })
end

---------------------------------------------------------------------------
-- Create the main replay window
---------------------------------------------------------------------------
local function CreateReplayFrame()
    if replayFrame then return replayFrame end

    local frame = lib:CreateWindowFrame("TrinketedReplayFrame", {
        width = FRAME_W,
        height = FRAME_H,
        title = "|cffE8B923T|r|cffF4F4F5RINKETED|r Replay",
        onClose = function()
            if session then
                session:Destroy()
                session = nil
            end
        end,
    })
    -- Make the replay window draggable (the window lib wires this up, but we
    -- previously blanked the scripts; keep it movable so users can reposition
    -- the frame if it doesn't fit their screen).
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Fit-to-screen safety net: the window's natural size (FRAME_W x FRAME_H)
    -- now matches the options panel (932x520) and fits a 1080p screen natively,
    -- so this normally resolves to scale 1 (no-op). It only kicks in on unusually
    -- small displays or a large UI scale, shrinking the whole window uniformly so
    -- nothing is clipped, and re-centering it. We only ever scale DOWN (capped at
    -- 1), so typical displays are unaffected.
    local function FitToScreen()
        local availW = UIParent:GetWidth() * 0.98
        local availH = UIParent:GetHeight() * 0.96
        local scale = math.min(1, availW / FRAME_W, availH / FRAME_H)
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    FitToScreen()
    -- Re-fit if the screen/UI scale changes while the addon is loaded.
    pcall(function() frame:RegisterEvent("DISPLAY_SIZE_CHANGED") end)
    pcall(function() frame:RegisterEvent("UI_SCALE_CHANGED") end)
    frame:HookScript("OnEvent", function(_, event)
        if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
            FitToScreen()
        end
    end)

    -- ===== BACK BUTTON =====
    -- Closes the replay and reopens the options panel on the History sub-addon
    -- (preserving its last-active inner tab), so the user can pick another
    -- match without having to reopen the whole UI.
    frame.titleText:ClearAllPoints()
    frame.titleText:SetPoint("TOPLEFT", 80, -10)

    frame.backBtn = CreateFrame("Button", nil, frame)
    frame.backBtn:SetSize(60, 20)
    frame.backBtn:SetPoint("TOPLEFT", 10, -8)
    frame.backBtn.bg = frame.backBtn:CreateTexture(nil, "BACKGROUND")
    frame.backBtn.bg:SetAllPoints()
    frame.backBtn.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
    frame.backBtn.label = frame.backBtn:CreateFontString(nil, "OVERLAY")
    frame.backBtn.label:SetFont(lib.FONT_BODY, 10, "")
    frame.backBtn.label:SetPoint("CENTER")
    frame.backBtn.label:SetText("< Back")
    frame.backBtn.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    frame.backBtn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
    end)
    frame.backBtn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
    end)
    frame.backBtn:SetScript("OnClick", function()
        if session then
            session:Destroy()
            session = nil
        end
        frame:Hide()
        lib:ShowOptionsPanel("History")
    end)

    -- ===== GEAR MENU (tracked spells config) =====
    local gearBtn = CreateFrame("Button", nil, frame)
    gearBtn:SetSize(20, 20)
    gearBtn:SetPoint("TOPRIGHT", -28, -6)
    gearBtn.icon = gearBtn:CreateFontString(nil, "OVERLAY")
    gearBtn.icon:SetFont(lib.FONT_MONO, 14, "")
    gearBtn.icon:SetPoint("CENTER")
    gearBtn.icon:SetText("*")
    gearBtn.icon:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    gearBtn:SetScript("OnEnter", function(self)
        self.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Tracked Spells")
        GameTooltip:AddLine("Configure which cooldowns to show", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function(self)
        self.icon:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        GameTooltip:Hide()
    end)

    -- Dropdown menu for tracked spells
    local menuFrame = CreateFrame("Frame", "TrinketedReplayCDMenu", UIParent, "UIDropDownMenuTemplate")

    local CLASS_ORDER = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
        "Mage", "Warlock", "Shaman", "Druid" }

    local function InitCDMenu(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local hiddenCDs = TrinketedHistoryDB and TrinketedHistoryDB.settings and TrinketedHistoryDB.settings.hiddenReplayCDs or {}

        if level == 1 then
            -- Show All / Reset option
            info.text = "|cff00ff00Show All (Reset)|r"
            info.notCheckable = true
            info.func = function()
                if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                    wipe(TrinketedHistoryDB.settings.hiddenReplayCDs)
                end
                print("|cff00ccffTrinketed:|r All replay CD tracker spells restored.")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)

            -- Separator
            info = UIDropDownMenu_CreateInfo()
            info.text = ""
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)

            -- Class submenus
            for _, className in ipairs(CLASS_ORDER) do
                local spells = addon.CLASS_COOLDOWNS[className]
                if spells then
                    info = UIDropDownMenu_CreateInfo()
                    info.text = className
                    info.notCheckable = true
                    info.hasArrow = true
                    info.menuList = className
                    UIDropDownMenu_AddButton(info, level)
                end
            end

        elseif level == 2 then
            -- Spells for the selected class
            local className = menuList
            local spells = addon.CLASS_COOLDOWNS[className]
            if spells then
                for _, spellID in ipairs(spells) do
                    info = UIDropDownMenu_CreateInfo()
                    local dbEntry = SPELL_DB and SPELL_DB[spellID]
                    local spellName = dbEntry and dbEntry.name or (GetSpellInfo(spellID) or ("Spell " .. spellID))
                    local texID = GetSpellTexture(spellID)
                    if texID then
                        info.text = "|T" .. texID .. ":14:14:0:0:64:64:4:60:4:60|t " .. spellName
                    else
                        info.text = spellName
                    end
                    info.checked = not hiddenCDs[spellID]
                    info.isNotRadio = true
                    info.keepShownOnClick = true
                    local sid = spellID
                    info.func = function(self, _, _, checked)
                        if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                            if checked then
                                TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = nil
                            else
                                TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = true
                            end
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end

    gearBtn:SetScript("OnClick", function(self)
        UIDropDownMenu_Initialize(menuFrame, InitCDMenu, "MENU")
        ToggleDropDownMenu(1, nil, menuFrame, self, 0, 0)
    end)

    -- ===== UNIT FRAMES PANEL (left side) =====
    frame.unitPanel = CreateFrame("Frame", nil, frame)
    frame.unitPanel:SetPoint("TOPLEFT", 6, -30)
    frame.unitPanel:SetSize(UNIT_PANEL_W, FRAME_H - TRANSPORT_H - 36)

    -- Section label: Friendly
    frame.friendlyLabel = frame.unitPanel:CreateFontString(nil, "OVERLAY")
    frame.friendlyLabel:SetFont(lib.FONT_DISPLAY, 10, "")
    frame.friendlyLabel:SetPoint("TOPLEFT", 10, -4)
    frame.friendlyLabel:SetTextColor(C.partyBlue[1], C.partyBlue[2], C.partyBlue[3])
    frame.friendlyLabel:SetText("FRIENDLY TEAM")

    -- Aura filter toggle (top-right of unit panel)
    -- Off = curated important auras (SpellDB + DRList). On = everything captured
    -- by the aura snapshots, for full "as-if-live" fidelity.
    -- Default on: the whole point of the replay is full fidelity; "Important
    -- only" is the escape hatch when the rows get noisy.
    frame.showAllAuras = true
    frame.auraToggle = CreateFrame("Button", nil, frame.unitPanel, "BackdropTemplate")
    frame.auraToggle:SetSize(90, 16)
    frame.auraToggle:SetPoint("TOPRIGHT", -10, -2)
    frame.auraToggle:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame.auraToggle:SetBackdropColor(0, 0, 0, 0.4)
    frame.auraToggle:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
    frame.auraToggle.label = frame.auraToggle:CreateFontString(nil, "OVERLAY")
    frame.auraToggle.label:SetFont(lib.FONT_BODY, 9, "")
    frame.auraToggle.label:SetPoint("CENTER")
    local function paintAuraToggle()
        if frame.showAllAuras then
            frame.auraToggle.label:SetText("All auras")
            frame.auraToggle.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            frame.auraToggle:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            frame.auraToggle.label:SetText("Important only")
            frame.auraToggle.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            frame.auraToggle:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
        end
    end
    paintAuraToggle()
    frame.auraToggle:SetScript("OnClick", function()
        frame.showAllAuras = not frame.showAllAuras
        paintAuraToggle()
        if frame.RefreshUnitFrames then frame:RefreshUnitFrames() end
    end)

    -- Friendly unit frames (up to 5) — left column. X/Y set in RefreshUnitFrames.
    frame.friendlyFrames = {}
    for i = 1, 5 do
        frame.friendlyFrames[i] = CreateUnitFrame(frame.unitPanel, UNITS_TOP_Y - (i - 1) * (UNIT_ROW_STRIDE))
        frame.friendlyFrames[i]:Hide()
    end

    -- Vertical divider between the friendly and enemy columns (static).
    local divider = frame.unitPanel:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", frame.unitPanel, "TOPLEFT", UNIT_COL_DIVIDER_X, -18)
    divider:SetPoint("BOTTOMLEFT", frame.unitPanel, "BOTTOMLEFT", UNIT_COL_DIVIDER_X, 4)
    divider:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4] or 0.25)
    frame.teamDivider = divider

    -- Section label: Enemy (static, over the second column)
    frame.enemyLabel = frame.unitPanel:CreateFontString(nil, "OVERLAY")
    frame.enemyLabel:SetFont(lib.FONT_DISPLAY, 10, "")
    frame.enemyLabel:SetPoint("TOPLEFT", UNIT_COL2_X + 6, -4)
    frame.enemyLabel:SetTextColor(C.enemyRed[1], C.enemyRed[2], C.enemyRed[3])
    frame.enemyLabel:SetText("ENEMY TEAM")

    -- Enemy unit frames (up to 5) — right column. X/Y set in RefreshUnitFrames.
    frame.enemyFrames = {}
    for i = 1, 5 do
        frame.enemyFrames[i] = CreateUnitFrame(frame.unitPanel, UNITS_TOP_Y - (i - 1) * (UNIT_ROW_STRIDE))
        frame.enemyFrames[i]:Hide()
    end

    -- ===== EVENT FEED PANEL (right side) =====
    frame.feedPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.feedPanel:SetPoint("TOPLEFT", UNIT_PANEL_W + 6, -30)
    frame.feedPanel:SetPoint("BOTTOMRIGHT", -6, TRANSPORT_H + 6)
    frame.feedPanel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame.feedPanel:SetBackdropColor(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], C.sidebarBg[4] or 1)
    frame.feedPanel:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], C.borderDefault[4] or 1)

    -- Filter chips using lib:CreateCheckbox() toggle chips with custom group logic
    frame.filterChips = {}
    local filterNames = { "All", "Dmg", "Heal", "CD", "CC", "Die" }
    local filterCats = { "all", "damage", "healing", "cd", "cc", "death" }
    frame.activeFilters = { all = true }

    local CHIP_W = 42
    local CHIP_H = 18
    local chipX = 4
    for idx, label in ipairs(filterNames) do
        local cat = filterCats[idx]
        local isOn = (cat == "all")

        local btn = CreateFrame("Button", nil, frame.feedPanel)
        btn:SetSize(CHIP_W, CHIP_H)
        btn:SetPoint("TOPLEFT", chipX, -4)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()

        btn.label = btn:CreateFontString(nil, "OVERLAY")
        btn.label:SetFont(lib.FONT_BODY, 9, "")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(label)

        btn.cat = cat
        btn.isOn = isOn

        local function UpdateChipVisual(b)
            if b.isOn then
                b.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
                b.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            else
                b.bg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)
                b.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end
        end
        UpdateChipVisual(btn)

        btn:SetScript("OnClick", function()
            if cat == "all" then
                frame.activeFilters = { all = true }
            else
                frame.activeFilters.all = nil
                if not frame.activeFilters[cat] then
                    frame.activeFilters[cat] = true
                else
                    frame.activeFilters[cat] = nil
                    local anyActive = false
                    for _, c in ipairs(filterCats) do
                        if c ~= "all" and frame.activeFilters[c] then anyActive = true; break end
                    end
                    if not anyActive then
                        frame.activeFilters = { all = true }
                    end
                end
            end
            for _, chip in ipairs(frame.filterChips) do
                chip.isOn = frame.activeFilters[chip.cat] or frame.activeFilters.all
                UpdateChipVisual(chip)
            end
            if frame.RefreshFeed then frame:RefreshFeed() end
        end)

        btn:SetScript("OnEnter", function(self)
            if self.isOn then
                self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.25)
            else
                self.bg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)
            end
        end)
        btn:SetScript("OnLeave", function(self) UpdateChipVisual(self) end)

        frame.filterChips[idx] = btn
        chipX = chipX + CHIP_W + 2
    end

    -- Search box
    frame.searchBox = CreateFrame("EditBox", nil, frame.feedPanel, "BackdropTemplate")
    frame.searchBox:SetPoint("TOPLEFT", 6, -28)
    frame.searchBox:SetPoint("RIGHT", -6, 0)
    frame.searchBox:SetHeight(18)
    frame.searchBox:SetFont(lib.FONT_MONO, 9, "")
    frame.searchBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame.searchBox:SetBackdropColor(0, 0, 0, 0.4)
    frame.searchBox:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
    frame.searchBox:SetTextInsets(4, 4, 0, 0)

    frame.searchBox.placeholder = frame.searchBox:CreateFontString(nil, "ARTWORK")
    frame.searchBox.placeholder:SetFont(lib.FONT_MONO, 9, "")
    frame.searchBox.placeholder:SetPoint("LEFT", 4, 0)
    frame.searchBox.placeholder:SetText("Search...")
    frame.searchBox.placeholder:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    frame.searchQuery = ""
    frame.searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        frame.searchQuery = text and text:lower() or ""
        frame.searchBox.placeholder:SetShown(frame.searchQuery == "")
        if frame.RefreshFeed then frame:RefreshFeed() end
    end)
    frame.searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Feed scroll frame
    frame.feedScroll = CreateFrame("ScrollFrame", nil, frame.feedPanel, "UIPanelScrollFrameTemplate")
    frame.feedScroll:SetPoint("TOPLEFT", 4, -48)
    frame.feedScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    frame.feedContent = CreateFrame("Frame", nil, frame.feedScroll)
    frame.feedContent:SetWidth(FEED_PANEL_W - 30)
    frame.feedContent:SetHeight(1)
    frame.feedScroll:SetScrollChild(frame.feedContent)

    frame.feedRows = {}  -- fixed-size row pool (virtualized window — see RenderFeedWindow)

    -- The feed is virtualized: only the rows visible in the scroll viewport exist
    -- as frames, regardless of how many events the match has. Re-render the window
    -- whenever the user scrolls.
    frame.feedScroll:HookScript("OnVerticalScroll", function()
        if frame.RenderFeedWindow then frame:RenderFeedWindow() end
    end)

    -- ===== TRANSPORT BAR (bottom) =====
    frame.transport = CreateFrame("Frame", nil, frame)
    frame.transport:SetPoint("BOTTOMLEFT", 6, 6)
    frame.transport:SetPoint("BOTTOMRIGHT", -6, 6)
    frame.transport:SetHeight(TRANSPORT_H)

    -- Jump to start (anchored to bottom; the top of transport hosts the tick-search row)
    local btnStart = CreateFrame("Button", nil, frame.transport)
    btnStart:SetSize(24, 20)
    btnStart:SetPoint("BOTTOMLEFT", 4, 6)
    btnStart.text = btnStart:CreateFontString(nil, "OVERLAY")
    btnStart.text:SetFont(lib.FONT_MONO, 10, "")
    btnStart.text:SetPoint("CENTER")
    btnStart.text:SetText("|<")
    btnStart.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    btnStart:SetScript("OnClick", function()
        if session then
            session:SeekTo(0)
            session.status = "paused"
            frame.snapFeedPending = true
        end
    end)

    -- Play/pause
    frame.btnPlay = CreateFrame("Button", nil, frame.transport)
    frame.btnPlay:SetSize(24, 20)
    frame.btnPlay:SetPoint("LEFT", btnStart, "RIGHT", 2, 0)
    frame.btnPlay.text = frame.btnPlay:CreateFontString(nil, "OVERLAY")
    frame.btnPlay.text:SetFont(lib.FONT_MONO, 12, "")
    frame.btnPlay.text:SetPoint("CENTER")
    frame.btnPlay.text:SetText(">")
    frame.btnPlay.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    frame.btnPlay:SetScript("OnClick", function()
        if session then
            session:TogglePlayPause()
            -- Force one refresh so the button/feed update even when pausing into idle.
            frame.snapFeedPending = true
        end
    end)

    -- Jump to end
    local btnEnd = CreateFrame("Button", nil, frame.transport)
    btnEnd:SetSize(24, 20)
    btnEnd:SetPoint("LEFT", frame.btnPlay, "RIGHT", 2, 0)
    btnEnd.text = btnEnd:CreateFontString(nil, "OVERLAY")
    btnEnd.text:SetFont(lib.FONT_MONO, 10, "")
    btnEnd.text:SetPoint("CENTER")
    btnEnd.text:SetText(">|")
    btnEnd.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    btnEnd:SetScript("OnClick", function()
        if session then
            session:SeekTo(session.matchDuration)
            session.status = "paused"
            frame.snapFeedPending = true
        end
    end)

    -- Speed button
    frame.btnSpeed = CreateFrame("Button", nil, frame.transport)
    frame.btnSpeed:SetSize(34, 20)
    frame.btnSpeed:SetPoint("LEFT", btnEnd, "RIGHT", 8, 0)
    frame.btnSpeed.text = frame.btnSpeed:CreateFontString(nil, "OVERLAY")
    frame.btnSpeed.text:SetFont(lib.FONT_MONO, 10, "")
    frame.btnSpeed.text:SetPoint("CENTER")
    frame.btnSpeed.text:SetText("1x")
    frame.btnSpeed.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    frame.btnSpeed:SetScript("OnClick", function()
        speedIndex = (speedIndex % #SPEEDS) + 1
        local speed = SPEEDS[speedIndex]
        if session then session:SetSpeed(speed) end
        frame.btnSpeed.text:SetText(speed .. "x")
    end)

    -- Timeline scrubber track
    frame.scrubTrack = CreateFrame("Button", nil, frame.transport)
    frame.scrubTrack:SetPoint("LEFT", frame.btnSpeed, "RIGHT", 10, 0)
    frame.scrubTrack:SetPoint("RIGHT", frame.transport, "BOTTOMRIGHT", -100, 16)
    frame.scrubTrack:SetHeight(6)

    frame.scrubTrackBg = frame.scrubTrack:CreateTexture(nil, "BACKGROUND")
    frame.scrubTrackBg:SetAllPoints()
    frame.scrubTrackBg:SetColorTexture(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)

    -- Scrub thumb
    frame.scrubThumb = CreateFrame("Frame", nil, frame.scrubTrack)
    frame.scrubThumb:SetSize(10, 14)
    frame.scrubThumbTex = frame.scrubThumb:CreateTexture(nil, "OVERLAY")
    frame.scrubThumbTex:SetAllPoints()
    frame.scrubThumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Click-to-seek on scrub track
    frame.scrubTrack:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and session then
            local x = self:GetLeft()
            local w = self:GetWidth()
            local cursorX = GetCursorPosition() / self:GetEffectiveScale()
            local frac = math.max(0, math.min(1, (cursorX - x) / w))
            session:SeekTo(frac * session.matchDuration)
            session.status = "paused"
            frame.scrubbing = true
            frame.snapFeedPending = true
        end
    end)

    frame.scrubTrack:SetScript("OnMouseUp", function()
        frame.scrubbing = false
    end)

    -- Time display (aligned with the scrubber/buttons row at the bottom of transport)
    frame.timeText = frame.transport:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetFont(lib.FONT_MONO, 10, "")
    frame.timeText:SetPoint("BOTTOMRIGHT", -4, 16)
    frame.timeText:SetJustifyH("RIGHT")
    frame.timeText:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    -- ===== TICK-SEARCH ROW (top of transport) =====
    -- Narrows the scrub-track ticks to cast events matching the typed spell
    -- name (case-insensitive substring). Deaths always remain visible. When
    -- active, ticks are colored by team (friendly/enemy) instead of category.
    frame.tickSearchBox = CreateFrame("EditBox", nil, frame.transport, "BackdropTemplate")
    frame.tickSearchBox:SetPoint("TOPLEFT", 4, -4)
    frame.tickSearchBox:SetSize(160, 16)
    frame.tickSearchBox:SetFont(lib.FONT_MONO, 9, "")
    frame.tickSearchBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    frame.tickSearchBox:SetAutoFocus(false)
    frame.tickSearchBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame.tickSearchBox:SetBackdropColor(0, 0, 0, 0.4)
    frame.tickSearchBox:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
    frame.tickSearchBox:SetTextInsets(4, 4, 0, 0)

    frame.tickSearchBox.placeholder = frame.tickSearchBox:CreateFontString(nil, "ARTWORK")
    frame.tickSearchBox.placeholder:SetFont(lib.FONT_MONO, 9, "")
    frame.tickSearchBox.placeholder:SetPoint("LEFT", 4, 0)
    frame.tickSearchBox.placeholder:SetText("Search ticks...")
    frame.tickSearchBox.placeholder:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    frame.tickSearchQuery = ""
    frame.tickSearchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        frame.tickSearchQuery = text and text:lower() or ""
        frame.tickSearchBox.placeholder:SetShown(frame.tickSearchQuery == "")
        frame:RefreshMarkers()
        frame:UpdateLegend()
    end)
    frame.tickSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- ===== TIMELINE LEGEND =====
    -- Two legend sets sharing the right side of the tick-search row; we toggle
    -- visibility via UpdateLegend() depending on whether a search is active.
    frame.legendCat = {}
    frame.legendTeam = {}

    local catItems = {
        { color = CAT_COLORS.death,        label = "Death" },
        { color = CAT_COLORS.trinket,      label = "Trinket" },
        { color = CAT_COLORS.offensive_cd, label = "Offensive" },
        { color = CAT_COLORS.defensive_cd, label = "Defensive" },
        { color = CAT_COLORS.interrupt,    label = "Interrupt" },
    }
    local teamItems = {
        { color = { r = C.statusSuccess[1], g = C.statusSuccess[2], b = C.statusSuccess[3] }, label = "Friendly" },
        { color = { r = C.statusError[1],   g = C.statusError[2],   b = C.statusError[3]   }, label = "Enemy" },
    }

    -- Lay out legend items right-to-left anchored to TOPRIGHT of transport.
    local function BuildLegend(items, pool)
        local xRight = -4
        for i = #items, 1, -1 do
            local item = items[i]
            local lbl = frame.transport:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(lib.FONT_BODY, 8, "")
            lbl:SetText(item.label)
            lbl:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            lbl:SetPoint("TOPRIGHT", xRight, -7)
            local labelW = lbl:GetStringWidth()

            local swatch = frame.transport:CreateTexture(nil, "ARTWORK")
            swatch:SetSize(8, 8)
            swatch:SetPoint("RIGHT", lbl, "LEFT", -3, 0)
            swatch:SetColorTexture(item.color.r, item.color.g, item.color.b, 1)

            table.insert(pool, lbl)
            table.insert(pool, swatch)

            xRight = xRight - labelW - 3 - 8 - 10
        end
    end
    BuildLegend(catItems, frame.legendCat)
    BuildLegend(teamItems, frame.legendTeam)

    function frame:UpdateLegend()
        local teamMode = self.tickSearchQuery and self.tickSearchQuery ~= ""
        for _, obj in ipairs(self.legendCat)  do obj:SetShown(not teamMode) end
        for _, obj in ipairs(self.legendTeam) do obj:SetShown(teamMode) end
    end
    frame:UpdateLegend()

    -- ===== ERROR MESSAGE (shown when decompression fails) =====
    frame.errorText = frame:CreateFontString(nil, "OVERLAY")
    frame.errorText:SetFont(lib.FONT_BODY, 12, "")
    frame.errorText:SetPoint("CENTER")
    frame.errorText:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
    frame.errorText:Hide()

    -- ===== TIMELINE MARKERS =====
    frame.markerPool = {}

    -- ===== OnUpdate: advance playback and refresh UI =====
    -- Refresh work is throttled to ~33 Hz and skipped entirely when the replay is
    -- idle (paused and not seeking). The old version ran a full unit + feed refresh
    -- on every single frame — on a high-refresh monitor that's the same work 100+
    -- times a second for a paused window, and it scaled with event count.
    frame.refreshAccum = 0
    local REFRESH_INTERVAL = 0.03
    frame:SetScript("OnUpdate", function(self, dt)
        if not session then return end

        -- Scrub dragging is handled immediately for responsiveness.
        if frame.scrubbing then
            local x = frame.scrubTrack:GetLeft()
            local w = frame.scrubTrack:GetWidth()
            local cursorX = GetCursorPosition() / frame.scrubTrack:GetEffectiveScale()
            local frac = math.max(0, math.min(1, (cursorX - x) / w))
            session:SeekTo(frac * session.matchDuration)
            frame.snapFeedPending = true
        end

        -- Nothing changing → no work at all.
        local active = session.status == "playing" or frame.snapFeedPending or frame.scrubbing
        if not active then return end

        -- Throttle; accumulate dt so playback time stays exact across skipped frames.
        frame.refreshAccum = frame.refreshAccum + dt
        if frame.refreshAccum < REFRESH_INTERVAL and not frame.snapFeedPending then return end
        local elapsed = frame.refreshAccum
        frame.refreshAccum = 0

        if session.status == "playing" then
            session:Advance(elapsed)
        end

        -- Play/pause button text
        frame.btnPlay.text:SetText(session.status == "playing" and "||" or ">")

        -- Scrub thumb position
        if session.matchDuration > 0 then
            local frac = session.currentTime / session.matchDuration
            local trackW = frame.scrubTrack:GetWidth()
            frame.scrubThumb:SetPoint("CENTER", frame.scrubTrack, "LEFT", trackW * frac, 0)
        end

        -- Time display
        frame.timeText:SetText(FormatTime(session.currentTime) .. " / " .. FormatTime(session.matchDuration))

        frame:RefreshUnitFrames()
        frame:RefreshFeedHighlight()
    end)

    -- ===== Refresh unit frame positions and state =====
    function frame:RefreshUnitFrames()
        if not session then return end
        local state = session.state

        -- Split into friendly/enemy, then impose a stable order. state.players
        -- is rebuilt on every seek, so raw pairs() order can differ between
        -- refreshes and the unit frames would visibly swap rows mid-replay.
        local friendly, enemy = {}, {}
        for guid, p in pairs(state.players) do
            if p.team == "friendly" then
                table.insert(friendly, { guid = guid, state = p })
            elseif p.team == "enemy" then
                table.insert(enemy, { guid = guid, state = p })
            end
        end
        local stateOf = function(e) return e.state end
        friendly = addon.SortTeam(friendly, session.playerName, stateOf)
        enemy    = addon.SortTeam(enemy, nil, stateOf)

        -- Position friendly frames in the left column
        local friendlyCount = math.min(#friendly, 5)
        for i = 1, 5 do
            if i <= friendlyCount then
                self.friendlyFrames[i]:SetPoint("TOPLEFT", UNIT_COL1_X, UNITS_TOP_Y - (i - 1) * (UNIT_ROW_STRIDE))
                UpdateUnitFrame(self.friendlyFrames[i], friendly[i].state,
                    session.currentTime, session.seeking, self.showAllAuras)
            else
                self.friendlyFrames[i]:Hide()
            end
        end

        -- Position enemy frames in the right column (the divider and enemy label
        -- are now static, set once at creation).
        local enemyCount = math.min(#enemy, 5)
        for i = 1, 5 do
            if i <= enemyCount then
                self.enemyFrames[i]:SetPoint("TOPLEFT", UNIT_COL2_X, UNITS_TOP_Y - (i - 1) * (UNIT_ROW_STRIDE))
                UpdateUnitFrame(self.enemyFrames[i], enemy[i].state,
                    session.currentTime, session.seeking, self.showAllAuras)
            else
                self.enemyFrames[i]:Hide()
            end
        end
    end

    -- ===== Refresh event feed =====
    function frame:RefreshFeed()
        if not session then return end

        -- Hide all rows
        for _, row in ipairs(self.feedRows) do
            row:Hide()
        end

        local feedEvents = session.feedEvents
        local filters = self.activeFilters

        -- Filter events
        local visible = {}
        for _, ev in ipairs(feedEvents) do
            local show = false
            if filters.all then
                show = true
            else
                local cat = ev.cat
                if cat == "death" and filters.death then show = true
                elseif cat == "damage" and filters.damage then show = true
                elseif (cat == "healing" or cat == "healing_cd") and filters.healing then show = true
                elseif (cat == "offensive_cd" or cat == "defensive_cd" or cat == "trinket"
                    or cat == "racial" or cat == "cc_break" or cat == "mobility" or cat == "utility") and filters.cd then show = true
                elseif (cat == "interrupt" or cat == "dispel" or cat == "aura") and filters.cc then show = true
                elseif (cat == "cast" or cat == "miss" or cat == "power") and filters.damage then show = true
                end
            end
            -- Apply search filter
            if show and self.searchQuery and self.searchQuery ~= "" then
                local q = self.searchQuery
                local match = false
                if ev.spellName and tostring(ev.spellName):lower():find(q, 1, true) then match = true end
                if not match and ev.srcName and tostring(ev.srcName):lower():find(q, 1, true) then match = true end
                if not match and ev.dstName and tostring(ev.dstName):lower():find(q, 1, true) then match = true end
                if not match and ev.type and tostring(ev.type):lower():find(q, 1, true) then match = true end
                if not match and ev.extraSpell and tostring(ev.extraSpell):lower():find(q, 1, true) then match = true end
                if not match then show = false end
            end
            if show then
                table.insert(visible, ev)
            end
        end

        self.visibleFeedEvents = visible

        -- Virtualized feed: size the scroll child to the full filtered list, but
        -- only realize the rows visible in the viewport as frames. This keeps the
        -- frame count (and per-frame work) bounded no matter how many thousands of
        -- events a long match produces — the old code created one frame per event.
        self.feedContent:SetHeight(math.max(#visible * FEED_ROW_H, 1))
        self.feedScroll:SetVerticalScroll(0)  -- a new filter/search set: jump to top
        self:RenderFeedWindow()
    end

    -- Create one pooled feed row. Tooltip/click handlers read row.ev (refreshed by
    -- PopulateFeedRow) rather than capturing an event, so a row can be recycled for
    -- different events as the window scrolls without rebuilding closures.
    local function CreateFeedRow(parent)
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(FEED_PANEL_W - 30, FEED_ROW_H)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0, 0, 0, 0)

        row.timeText = row:CreateFontString(nil, "OVERLAY")
        row.timeText:SetFont(lib.FONT_MONO, 9, "")
        row.timeText:SetPoint("LEFT", 2, 0)
        row.timeText:SetWidth(38)
        row.timeText:SetWordWrap(false)
        row.timeText:SetJustifyH("LEFT")

        row.srcText = row:CreateFontString(nil, "OVERLAY")
        row.srcText:SetFont(lib.FONT_MONO, 9, "")
        row.srcText:SetPoint("LEFT", 42, 0)
        row.srcText:SetWidth(80)
        row.srcText:SetJustifyH("RIGHT")
        row.srcText:SetWordWrap(false)

        row.iconBtn = CreateFrame("Button", nil, row)
        row.iconBtn:SetSize(FEED_ICON_SIZE, FEED_ICON_SIZE)
        row.iconBtn:SetPoint("LEFT", 126, 0)
        row.icon = row.iconBtn:CreateTexture(nil, "ARTWORK")
        row.icon:SetAllPoints()
        -- The icon sits on top of the row and swallows its OnEnter, so the
        -- dev-mode raw dump is appended here too — hovering anywhere on the
        -- row (icon included) surfaces the raw event.
        row.iconBtn:SetScript("OnEnter", function(self)
            if row.ev and row.ev.spellID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(row.ev.spellID)
                if addon.IsDevMode and addon:IsDevMode() then
                    AddRawEventTooltip(row.ev)
                end
                GameTooltip:Show()
            end
        end)
        row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.iconBtn:SetScript("OnClick", function()
            if session and row.ev then
                session:SeekTo(row.ev.time)
                session.status = "paused"
                frame.snapFeedPending = true
            end
        end)

        row.spellText = row:CreateFontString(nil, "OVERLAY")
        row.spellText:SetFont(lib.FONT_MONO, 9, "")
        row.spellText:SetPoint("LEFT", 144, 0)
        row.spellText:SetWidth(120)
        row.spellText:SetJustifyH("LEFT")
        row.spellText:SetWordWrap(false)

        row.detailText = row:CreateFontString(nil, "OVERLAY")
        row.detailText:SetFont(lib.FONT_MONO, 9, "")
        row.detailText:SetPoint("LEFT", 268, 0)
        row.detailText:SetPoint("RIGHT", -2, 0)
        row.detailText:SetJustifyH("LEFT")
        row.detailText:SetWordWrap(false)

        row:SetScript("OnClick", function()
            if session and row.ev then
                -- Death rows additionally open the Death Recap panel for the
                -- victim; the seek still happens so the replay lands on the kill.
                if row.ev.cat == "death" then
                    recap:Open(row.ev)
                end
                session:SeekTo(row.ev.time)
                session.status = "paused"
                frame.snapFeedPending = true
            end
        end)

        -- Hover affordance for death rows (the only rows with a special click
        -- action): red tint + tooltip. Other rows keep their plain seek click.
        -- In dev mode every row also gets a raw-event dump appended.
        row:SetScript("OnEnter", function(self)
            if not self.ev then return end
            local isDeath = self.ev.cat == "death"
            local dev = addon.IsDevMode and addon:IsDevMode()
            if not (isDeath or dev) then return end
            if isDeath then
                self.bg:SetColorTexture(CAT_COLORS.death.r, CAT_COLORS.death.g, CAT_COLORS.death.b, 0.15)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if isDeath then
                GameTooltip:SetText("Death Recap")
                GameTooltip:AddLine("Click to review the final seconds before this death.", 0.6, 0.6, 0.6)
            end
            if dev then
                AddRawEventTooltip(self.ev)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self.bg:SetColorTexture(self.bgR or 0, self.bgG or 0, self.bgB or 0, self.bgA or 0)
        end)

        return row
    end

    -- Fill a pooled row with one event's text/icon. No script churn — handlers
    -- are static (set in CreateFeedRow) and read row.ev.
    local function PopulateFeedRow(row, ev)
        row.ev = ev
        row.eventTime = ev.time

        row.timeText:SetText(FormatTimeTenths(ev.time))
        row.timeText:SetTextColor(0.53, 0.53, 0.53)

        local spellID = ev.spellID
        local texID = spellID and GetSpellTexture(spellID)
        if texID then
            row.icon:SetTexture(texID)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.iconBtn:Show()
        else
            row.iconBtn:Hide()
        end

        -- Floor the category color channels: this client's string.format throws on
        -- a non-integer %x argument.
        local catColor = CAT_COLORS[ev.cat] or { r = 0.7, g = 0.7, b = 0.7 }
        local catHex = string.format("%02x%02x%02x",
            math.floor(catColor.r * 255 + 0.5), math.floor(catColor.g * 255 + 0.5), math.floor(catColor.b * 255 + 0.5))

        if ev.cat == "death" then
            row.srcText:SetText("")
            row.spellText:SetText("|cffff0000DEATH|r")
            row.iconBtn:Hide()
            row.detailText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r  |cff707070» recap|r")

        elseif ev.type == "damage" then
            row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
            row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
            local detail = "> " .. ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r"
            if ev.amount then
                local amtStr = AbbrevNumber(ev.amount)
                if ev.critical then amtStr = amtStr .. "*" end
                detail = detail .. "  |cffff4444-" .. amtStr .. "|r"
            end
            row.detailText:SetText(detail)

        elseif ev.type == "heal" or ev.type == "absorb" then
            row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
            row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
            local detail = ""
            if ev.dstName and ev.dstName ~= ev.srcName then
                detail = "> " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
            end
            if ev.amount then
                local amtStr = AbbrevNumber(ev.amount)
                if ev.critical then amtStr = amtStr .. "*" end
                if ev.type == "absorb" then
                    detail = detail .. "  |cffffff00" .. amtStr .. " abs|r"
                else
                    detail = detail .. "  |cff44ff44+" .. amtStr .. "|r"
                end
            end
            row.detailText:SetText(detail)

        elseif ev.type == "interrupt" then
            row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
            row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
            local detail = ""
            if ev.dstName then
                detail = "> " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
            end
            if ev.extraSpell then
                detail = detail .. " |cff888888(" .. ev.extraSpell .. ")|r"
            end
            row.detailText:SetText(detail)

        elseif ev.type == "dispel" or ev.type == "steal" then
            row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
            local verb = ev.type == "steal" and "stole" or "dispelled"
            row.spellText:SetText("|cff" .. catHex .. verb .. "|r")
            local detail = ""
            if ev.extraSpell then
                detail = "|cffffff00" .. ev.extraSpell .. "|r"
            end
            if ev.dstName then
                detail = detail .. " > " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
            end
            row.detailText:SetText(detail)

        elseif ev.type == "aura_applied" then
            row.srcText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r")
            local prefix = (ev.auraType == "DEBUFF") and "|cffff6666+" or "|cff66ff66+"
            row.spellText:SetText(prefix .. (ev.spellName or "?") .. "|r")
            row.detailText:SetText("")

        elseif ev.type == "aura_removed" then
            row.srcText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r")
            local prefix = (ev.auraType == "DEBUFF") and "|cffff6666-" or "|cff66ff66-"
            row.spellText:SetText(prefix .. (ev.spellName or "?") .. "|r")
            row.detailText:SetText("")

        elseif ev.type == "aura_break" then
            row.srcText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r")
            row.spellText:SetText("|cffff8800" .. (ev.spellName or "?") .. "|r")
            local detail = "|cffff8800broken|r"
            if ev.extraSpell then
                detail = detail .. " |cff888888(by " .. ev.extraSpell .. ")|r"
            end
            row.detailText:SetText(detail)

        elseif ev.type == "miss" then
            row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
            row.spellText:SetText("|cff888888" .. (ev.spellName or "?") .. "|r")
            row.detailText:SetText("> " .. ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r" ..
                "  |cff888888" .. (ev.missType or "MISS") .. "|r")

        else
            -- cast_success, cast_start, summon, energize, drain, etc.
            row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
            row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
            local detail = ""
            if ev.dstName and ev.dstName ~= ev.srcName then
                detail = "> " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
            end
            if ev.amount and ev.amount ~= 0 then
                detail = detail .. "  " .. AbbrevNumber(math.abs(ev.amount))
            end
            row.detailText:SetText(detail)
        end

        -- Shrink-to-fit the text columns: glyph widths vary with the
        -- viewer's physical resolution (1080p rasterizes small fonts
        -- slightly wider than 1440p), so a budget that fits one screen can
        -- clip names/amounts on another.
        lib:FitText(row.srcText)
        lib:FitText(row.spellText)
        lib:FitText(row.detailText)
    end

    -- Index of the most recent event at or before the current time (binary search
    -- over the time-ordered visible list) — used for the accent highlight and the
    -- playback auto-follow. O(log n) instead of scanning every row each frame.
    function frame:FeedLastPastIndex()
        local visible = self.visibleFeedEvents
        if not visible then return nil end
        local total = #visible
        if total == 0 then return nil end
        local ct = session and session.currentTime or 0
        if visible[1].time > ct then return nil end
        local lo, hi, ans = 1, total, 1
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if visible[mid].time <= ct then ans = mid; lo = mid + 1 else hi = mid - 1 end
        end
        return ans
    end

    -- Render only the feed rows visible in the current scroll viewport, recycling
    -- the pool. Called on filter/search change, on scroll, and during playback.
    function frame:RenderFeedWindow()
        local visible = self.visibleFeedEvents
        if not visible then return end
        local total = #visible
        local ct = session and session.currentTime or 0

        local viewH = self.feedScroll:GetHeight()
        if not viewH or viewH <= 0 then viewH = 360 end
        local scroll = self.feedScroll:GetVerticalScroll() or 0
        local poolNeeded = math.ceil(viewH / FEED_ROW_H) + 2
        local first = math.max(1, math.floor(scroll / FEED_ROW_H) + 1)

        local lastPastIdx = self:FeedLastPastIndex()

        for slot = 1, poolNeeded do
            local idx = first + slot - 1
            local ev = visible[idx]
            local row = self.feedRows[slot]
            if ev then
                if not row then
                    row = CreateFeedRow(self.feedContent)
                    self.feedRows[slot] = row
                end
                row:SetPoint("TOPLEFT", 0, -((idx - 1) * FEED_ROW_H))
                PopulateFeedRow(row, ev)

                -- Dim future events; accent the most recent past one.
                local a = (ev.time <= ct) and 1.0 or 0.3
                row.timeText:SetAlpha(a)
                row.srcText:SetAlpha(a)
                row.iconBtn:SetAlpha(a)
                row.spellText:SetAlpha(a)
                row.detailText:SetAlpha(a)
                -- Remember the base bg so the death-row hover highlight can
                -- restore it on OnLeave.
                if lastPastIdx and idx == lastPastIdx then
                    row.bgR, row.bgG, row.bgB, row.bgA = C.accent[1], C.accent[2], C.accent[3], 0.1
                else
                    row.bgR, row.bgG, row.bgB, row.bgA = 0, 0, 0, 0
                end
                row.bg:SetColorTexture(row.bgR, row.bgG, row.bgB, row.bgA)
                row:Show()
            elseif row then
                row:Hide()
            end
        end
    end

    -- Keep the playback position visible and refresh dimming. Cheap: moves the
    -- scroll window (which re-renders ~one viewport of rows), no full-list scan.
    function frame:RefreshFeedHighlight()
        if not session or not self.visibleFeedEvents then return end
        local lastPastIdx = self:FeedLastPastIndex()
        if (session.status == "playing" or self.snapFeedPending) and lastPastIdx then
            local scrollMax = self.feedScroll:GetVerticalScrollRange()
            local targetScroll = math.max(0, (lastPastIdx - 5) * FEED_ROW_H)
            self.feedScroll:SetVerticalScroll(math.min(targetScroll, scrollMax))
        end
        self:RenderFeedWindow()
        self.snapFeedPending = nil
    end

    -- ===== Place timeline markers on the scrub track =====
    function frame:RefreshMarkers()
        -- Hide existing
        for _, m in ipairs(self.markerPool) do
            m:Hide()
        end

        if not session then return end

        local query = self.tickSearchQuery or ""
        local markers = session:GetMarkersForQuery(query)
        local teamMode = query ~= ""

        for i, marker in ipairs(markers) do
            local m = self.markerPool[i]
            if not m then
                m = CreateFrame("Button", nil, self.scrubTrack)
                m:SetSize(6, 14)
                m:SetFrameLevel(self.scrubTrack:GetFrameLevel() + 2)
                m.tex = m:CreateTexture(nil, "OVERLAY")
                m.tex:SetSize(2, 10)
                m.tex:SetPoint("CENTER")
                self.markerPool[i] = m
            end
            local frac = session.matchDuration > 0 and (marker.time / session.matchDuration) or 0
            local trackW = self.scrubTrack:GetWidth()
            m:ClearAllPoints()
            m:SetPoint("CENTER", self.scrubTrack, "LEFT", trackW * frac, 0)

            -- Deaths always keep their death color so they remain recognizable
            -- as anchor points regardless of search mode.
            local cc
            if teamMode and marker.cat ~= "death" then
                if marker.team == "friendly" then
                    cc = { r = C.statusSuccess[1], g = C.statusSuccess[2], b = C.statusSuccess[3] }
                elseif marker.team == "enemy" then
                    cc = { r = C.statusError[1], g = C.statusError[2], b = C.statusError[3] }
                end
            end
            cc = cc or CAT_COLORS[marker.cat] or { r = 1, g = 1, b = 1 }
            m.tex:SetColorTexture(cc.r, cc.g, cc.b, 0.8)

            -- Tooltip on hover
            local label = marker.label or "?"
            local playerName = marker.player or ""
            local timeStr = FormatTime(marker.time)
            m:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(label, cc.r, cc.g, cc.b)
                if playerName ~= "" then
                    GameTooltip:AddLine(playerName, 1, 1, 1)
                end
                GameTooltip:AddLine(timeStr, 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            m:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            -- Click to seek
            m:SetScript("OnClick", function()
                if session then
                    session:SeekTo(marker.time)
                    session.status = "paused"
                    frame.snapFeedPending = true
                end
            end)
            m:Show()
        end
    end

    replayFrame = frame
    return frame
end

---------------------------------------------------------------------------
-- Public API: open replay for a game record
---------------------------------------------------------------------------
function addon:OpenReplay(game)
    -- Enforce the one-window-at-a-time invariant from this side too, so any
    -- future caller gets it without having to remember (the panel closes the
    -- replay symmetrically in lib:ShowOptionsPanel).
    lib:HideOptionsPanel()

    local frame = CreateReplayFrame()
    frame:SetFrameStrata("DIALOG")
    frame:Raise()

    -- Clean up previous session
    if session then
        session:Destroy()
        session = nil
    end

    -- A recap left open from a previous replay would otherwise reappear with
    -- the window (child frames keep their shown state through a parent hide).
    recap:Close()

    -- Reset speed
    speedIndex = 2
    frame.btnSpeed.text:SetText("1x")

    -- Hide error text
    frame.errorText:Hide()
    frame.unitPanel:Show()
    frame.feedPanel:Show()
    frame.transport:Show()

    -- Try to load
    if not game.eventLog then
        frame.errorText:SetText("No game log recorded for this match.")
        frame.errorText:Show()
        frame.unitPanel:Hide()
        frame.feedPanel:Hide()
        frame.transport:Hide()
        frame:Show()
        return
    end

    local newSession, err = self:CreateReplaySession(game.eventLog)
    if not newSession then
        frame.errorText:SetText(err or "Failed to load replay data.")
        frame.errorText:Show()
        frame.unitPanel:Hide()
        frame.feedPanel:Hide()
        frame.transport:Hide()
        frame:Show()
        return
    end

    session = newSession
    -- Who recorded this match: their unit frame sorts to the top of the
    -- friendly column. Shared/imported replays are from the recorder's
    -- perspective too, so this is right for them as well.
    session.playerName = game.playerName

    -- Build title
    local enemyComp = game.enemyComp and table.concat(game.enemyComp, "/") or "?"
    local result = game.result or "?"
    local map = game.map or "Arena"
    frame.titleText:SetText("Replay: " .. result .. " vs " .. enemyComp .. " - " .. map)

    -- Surface team MMR on the section labels. Only games recorded after MMR
    -- tracking was added carry these values; older replays just show the label.
    local function mmrTag(v)
        return (v and v > 0) and ("  |cff888888MMR " .. v .. "|r") or ""
    end
    frame.friendlyLabel:SetText("FRIENDLY TEAM" .. mmrTag(game.mmrBefore))
    frame.enemyLabel:SetText("ENEMY TEAM" .. mmrTag(game.enemyMMR))

    -- Reset filter chips
    frame.activeFilters = { all = true }
    for _, chip in ipairs(frame.filterChips) do
        chip.isOn = chip.cat == "all" or true
        if chip.bg and chip.label then
            if chip.isOn then
                chip.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
                chip.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            end
        end
    end

    -- Reset search box
    frame.searchQuery = ""
    frame.searchBox:SetText("")
    frame.searchBox.placeholder:Show()

    -- Reset tick-search box
    frame.tickSearchQuery = ""
    frame.tickSearchBox:SetText("")
    frame.tickSearchBox.placeholder:Show()
    frame:UpdateLegend()

    -- Start paused at t=0 and draw the initial frame explicitly. OnUpdate now
    -- skips all work while the replay is idle, so the opening (paused) view won't
    -- render on its own — we have to seed it here.
    session:SeekTo(0)
    session.status = "paused"
    frame.refreshAccum = 0
    frame.snapFeedPending = true
    frame:RefreshUnitFrames()

    -- Build feed and markers
    frame:RefreshFeed()
    frame:RefreshMarkers()

    frame:Show()
end
