-- Beast Lore Plus: detect the Beast Lore tooltip and append the Pet Abilities section
--
-- On Forever, Beast Lore shows the unit GameTooltip with extra lines (Tameable / Cannot Be Tamed,
-- Specialization:, Diet:). We hook unit tooltips and act only when a "Tameable" line is present.
-- With "Show details without casting Beast Lore" on, beasts are shown on plain mouseover too:
-- the Beast Lore lines seen last time are replayed (BLP.db.lore), or "Tameable" for beasts in
-- the database, followed by the Pet Abilities section. Specialization and Diet are also remembered
-- per creature family (BLP.db.loreFamily), so a beast never lored shows those of its family.
local _, BLP = ...
local L = BLP.L

local Lore = {}
BLP.Lore = Lore

local BEAST_LORE_SPELL = 1462

-- Last Beast Lore display seen, for /blp debug.
Lore.lastSnapshot = nil
Lore.lastCast = nil

-- Per-tooltip state without writing fields onto Blizzard frames (avoids taint).
local pending = setmetatable({}, { __mode = "k" })

local function textSet(...)
    local set = {}
    for i = 1, select("#", ...) do
        local s = select(i, ...)
        if type(s) == "string" and s ~= "" then set[s:lower()] = true end
    end
    return set
end
local TAMEABLE = textSet(L.TAMEABLE, _G.TAMEABLE, _G.UNIT_TAMEABLE, _G.PET_TAMEABLE)
local NOT_TAMEABLE = textSet(L.NOT_TAMEABLE, _G.NOT_TAMEABLE, _G.UNIT_NOT_TAMEABLE, _G.PET_NOT_TAMEABLE)
local LORE_MARKERS = { "^diet:", "^specialization:" }

local function strip(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Read the tooltip's current left-hand lines (plain values only).
local function readLines(tooltip)
    local out, colors = {}, {}
    local name = tooltip.GetName and tooltip:GetName()
    if not name or not tooltip.NumLines then return out, colors end
    for i = 1, tooltip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and BLP.Plain(fs:GetText())
        out[i] = type(text) == "string" and strip(text) or ""
        if fs and fs.GetTextColor then
            local ok, r, g, b = pcall(fs.GetTextColor, fs)
            r, g, b = BLP.Plain(r), BLP.Plain(g), BLP.Plain(b)
            if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
                colors[i] = { r, g, b }
            end
        end
    end
    return out, colors
end

local function isLoreLine(low)
    if TAMEABLE[low] or NOT_TAMEABLE[low] then return true end
    for _, pat in ipairs(LORE_MARKERS) do if low:find(pat) then return true end end
    return false
end

local function isFamilyLine(low)
    for _, pat in ipairs(LORE_MARKERS) do if low:find(pat) then return true end end
    return false
end

-- Remember a beast's Beast Lore lines so they can be shown again without casting, and its
-- Specialization and Diet for its whole family.
local function remember(npcId, lines, colors, tameable, family)
    local db = BLP.db
    if not db then return end
    db.lore = db.lore or {}
    local entry = { tameable = tameable, lines = {} }
    local famLines = {}
    for i, text in ipairs(lines) do
        local low = text:lower()
        if isLoreLine(low) then
            local c = colors[i]
            local line = c and { text, c[1], c[2], c[3] } or { text }
            entry.lines[#entry.lines + 1] = line
            if isFamilyLine(low) then famLines[#famLines + 1] = line end
        end
    end
    if #entry.lines > 0 then db.lore[npcId] = entry end
    if tameable and family and #famLines > 0 then
        db.loreFamily = db.loreFamily or {}
        db.loreFamily[family] = { lines = famLines, npcId = npcId }
    end
end
Lore.Remember = remember

local function classify(lines)
    local tameable, notTameable, lore, ours = false, false, false, false
    for _, text in ipairs(lines) do
        local low = text:lower()
        if TAMEABLE[low] then tameable = true end
        if NOT_TAMEABLE[low] then notTameable = true end
        for _, pat in ipairs(LORE_MARKERS) do if low:find(pat) then lore = true end end
        if text == L.PET_ABILITIES then ours = true end
    end
    return tameable, notTameable, lore, ours
end

local function sortedTeaches(teaches)
    local rows = {}
    for _, t in ipairs(teaches) do rows[#rows + 1] = t end
    table.sort(rows, function(a, b)
        local na, nb = BLP.AbilityName(a.ability), BLP.AbilityName(b.ability)
        if na == nb then return a.rank < b.rank end
        return na < nb
    end)
    return rows
end

local function tagFor(t, source, beast, extra, npcId)
    if source == "community" then return L.COMMUNITY end
    if source == "pending" then return L.PENDING:format(extra or 0, BLP.Community.QUORUM) end
    local conf = t.conf or (beast and beast.conf)
    if conf ~= "confirmed" and BLP.Community.ConfirmedInGame(npcId, t.ability, t.rank) then
        return L.CONFIRMED_IN_GAME
    end
    if conf == "unverified" then return L.UNVERIFIED end
    if conf == "conflict" then return L.CONFLICT end
    return nil
end

local function appendSection(tooltip, npcId)
    local c = BLP.COLORS
    local db = BLP.db
    tooltip:AddLine(" ")
    tooltip:AddLine(L.PET_ABILITIES, c.gold[1], c.gold[2], c.gold[3])

    local teaches, source, extra = BLP.GetTeaches(npcId)
    local beast = source == "bundled" and extra or nil
    local empty = not teaches or #teaches == 0
    if empty or source == "pending" then
        tooltip:AddLine(L.NO_DATA, c.cream[1], c.cream[2], c.cream[3])
        -- Keep asking for tames until 2 different hunters confirmed it teaches nothing.
        local confirmedNone = empty and BLP.Community.NothingConfirmations(npcId) >= BLP.Community.NOTHING_QUORUM
        if not confirmedNone then
            tooltip:AddLine(L.NO_DATA_HINT, c.grey[1], c.grey[2], c.grey[3], true)
        end
    end
    local anyUnknown = false
    for _, t in ipairs(teaches and sortedTeaches(teaches) or {}) do
        local status = BLP.Status(t.ability, t.rank)
        if status == "unknown" then anyUnknown = true end
        if status ~= "unknown" or db.showUnknown then
            local left = ("%s%s%s %s"):format(BLP.DotString(status), BLP.DOT_GAP, BLP.AbilityName(t.ability),
                L.RANK:format(t.rank))
            local tag = tagFor(t, source, beast, extra, npcId)
            if tag then
                tooltip:AddDoubleLine(left, tag, 1, 1, 1, c.grey[1], c.grey[2], c.grey[3])
            else
                tooltip:AddLine(left, 1, 1, 1)
            end
        end
    end
    if anyUnknown then
        tooltip:AddLine(L.OPEN_TRAINING, c.grey[1], c.grey[2], c.grey[3], true)
    end
    if db.showNpcId then
        tooltip:AddLine("NPC ID: " .. npcId, c.grey[1], c.grey[2], c.grey[3])
    end
    if tooltip:IsShown() then tooltip:Show() end -- resize to the new lines
end

local function tooltipGUID(tooltip, data)
    local guid = data and BLP.Plain(data.guid)
    if guid then return guid end
    if tooltip.GetUnit then
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        unit = ok and BLP.Plain(unit) or nil
        if unit then return BLP.SafeUnitGUID(unit) end
    end
    return nil
end

-- The hovered unit's creature family ("Wolf", "Raptor"...), when the game gives a plain value.
local function tooltipFamily(tooltip)
    if not tooltip.GetUnit or not UnitCreatureFamily then return nil end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and BLP.Plain(unit) or nil
    if not unit then return nil end
    local ok2, family = pcall(UnitCreatureFamily, unit)
    family = ok2 and BLP.Plain(family) or nil
    return type(family) == "string" and family ~= "" and family or nil
end
Lore.TooltipFamily = tooltipFamily

local function process(tooltip, data, knownGUID, isRecheck)
    if not BLP.isHunter or not BLP.db then return end
    local guid = knownGUID or tooltipGUID(tooltip, data)
    local npcId = BLP.NpcIdFromGUID(guid)
    if not npcId then return end

    local lines, colors = readLines(tooltip)
    local tameable, notTameable, lore, ours = classify(lines)
    if (tameable or notTameable) and not ours then
        remember(npcId, lines, colors, tameable, tooltipFamily(tooltip))
    end
    if tameable or notTameable or lore then
        local dataLines
        if data and type(data.lines) == "table" then
            dataLines = {}
            for i, l in ipairs(data.lines) do
                dataLines[i] = { text = BLP.Plain(l.leftText), right = BLP.Plain(l.rightText),
                                 type = BLP.Plain(l.type) }
            end
        end
        Lore.lastSnapshot = { time = time(), npcId = npcId, guid = guid, lines = lines,
                              dataLines = dataLines, tooltip = tooltip:GetName(),
                              recheck = isRecheck or false }
    end
    if ours or notTameable then return end
    if tameable then
        appendSection(tooltip, npcId)
        return
    end
    -- Optional: show the details on plain mouseover, without casting Beast Lore.
    if BLP.db.alwaysShow and (isRecheck or not C_Timer) then
        local cached = BLP.db.lore and BLP.db.lore[npcId]
        if cached and type(cached.lines) == "table" then
            for _, l in ipairs(cached.lines) do
                tooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1)
            end
            if cached.tameable then appendSection(tooltip, npcId)
            elseif tooltip:IsShown() then tooltip:Show() end
        elseif BLP.GetTeaches(npcId) then
            -- Only tameable beasts are in the data, so "Tameable" is safe to show.
            tooltip:AddLine(L.TAMEABLE, 1, 1, 1)
            -- Specialization and Diet from another beast of the same family.
            local family = tooltipFamily(tooltip)
            local fam = family and BLP.db.loreFamily and BLP.db.loreFamily[family]
            if fam and type(fam.lines) == "table" then
                for _, l in ipairs(fam.lines) do
                    tooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1)
                end
            end
            appendSection(tooltip, npcId)
        end
        return
    end
    -- Safety net: if the Beast Lore lines are added after the post-call, look again next frame.
    if not isRecheck and not pending[tooltip] then
        pending[tooltip] = true
        C_Timer.After(0, function()
            pending[tooltip] = nil
            if tooltip:IsShown() and tooltipGUID(tooltip, nil) == guid then
                process(tooltip, nil, guid, true)
            end
        end)
    end
end

Lore.Process = process

BLP.OnInit(function()
    if not BLP.isHunter then return end
    local hooked = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit,
            function(tooltip, data) process(tooltip, data) end)
        Lore.hookType = hooked and "TooltipDataProcessor" or nil
    end
    if not hooked and GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) process(tooltip, nil) end)
        Lore.hookType = "OnTooltipSetUnit"
    end

    BLP.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellId)
        if unit ~= "player" then return end
        spellId = BLP.Plain(spellId)
        if spellId == BEAST_LORE_SPELL then
            Lore.lastCast = { time = time(), npcId = BLP.NpcIdFromGUID(BLP.SafeUnitGUID("target")) }
        end
    end)
end)
