-- Beast Lore Plus: detect the Beast Lore tooltip and append the Pet Abilities section
--
-- On Forever, Beast Lore shows the unit GameTooltip with extra lines (Tameable / Cannot Be Tamed,
-- Specialization:, Diet:). We hook unit tooltips and act only when a "Tameable" line is present.
-- With "Show details without casting Beast Lore" on, beasts are shown on plain mouseover too:
-- the Beast Lore lines seen last time are replayed (BLP.db.lore), or "Tameable" for beasts in
-- the database, followed by the Pet Abilities section. Specialization and Diet are also remembered
-- per creature family (BLP.db.loreFamily), so a beast never lored shows those of its family.
-- Sources, in order: your own casts, the bundled Data/Lore.lua (lines seen in game, imported each
-- release), then lines shared by other Beast Lore Plus users (2 different hunters must agree).
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
Lore.IsFamilyLine = function(text) return type(text) == "string" and isFamilyLine(text:lower()) end

-- Specialization and Diet: the label in Blizzard's default tooltip yellow (NORMAL_FONT_COLOR),
-- the value after the colon in white.
local LORE_GOLD = { 1, 0.82, 0 }
local function addLoreLine(tooltip, text, r, g, b)
    if isFamilyLine(text:lower()) then
        local label, value = text:match("^(.-:)%s*(.*)$")
        if label then text = ("%s |cffffffff%s|r"):format(label, value) end
        r, g, b = LORE_GOLD[1], LORE_GOLD[2], LORE_GOLD[3]
    end
    tooltip:AddLine(text, r or 1, g or 1, b or 1)
end

-- Remember a beast's Beast Lore lines so they can be shown again without casting, and its
-- Specialization and Diet for its whole family.
local function remember(npcId, lines, colors, tameable, family)
    local db = BLP.db
    if not db then return end
    db.lore = db.lore or {}
    local entry = { tameable = tameable, lines = {}, name = lines[1] ~= "" and lines[1] or nil }
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
    if tameable and #famLines > 0 and BLP.Community and BLP.Community.ShareLore then
        local texts = {}
        for _, l in ipairs(famLines) do texts[#texts + 1] = l[1] end
        BLP.Community.ShareLore(npcId, family, texts)
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
        -- (Bundled with an empty list = tamed in game with nothing: already confirmed.)
        local confirmedNone = empty and (source == "bundled"
            or BLP.Community.NothingConfirmations(npcId) >= BLP.Community.NOTHING_QUORUM)
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

local function unitFamily(unit)
    if not unit or not UnitCreatureFamily then return nil end
    local ok, family = pcall(UnitCreatureFamily, unit)
    family = ok and BLP.Plain(family) or nil
    return type(family) == "string" and family ~= "" and family or nil
end
Lore.UnitFamily = unitFamily

-- The creature family ("Wolf", "Wind Serpent"...) of the beast a tooltip shows. Tries the
-- tooltip's unit, then mouseover / target when they are the same beast, then the family
-- remembered for this NPC (from a Beast Lore cast or a tame). Remembers what it finds.
local function tooltipFamily(tooltip, guid)
    local family
    if tooltip.GetUnit then
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        family = unitFamily(ok and BLP.Plain(unit) or nil)
    end
    if not family and guid then
        for _, unit in ipairs({ "mouseover", "target" }) do
            if BLP.SafeUnitGUID(unit) == guid then
                family = unitFamily(unit)
                if family then break end
            end
        end
    end
    local npcId = BLP.NpcIdFromGUID(guid)
    local db = BLP.db
    if npcId and db then
        db.npcFamily = db.npcFamily or {}
        if family then db.npcFamily[npcId] = family else family = db.npcFamily[npcId] end
    end
    if not family and npcId then
        local bundled = BLP.LoreData and BLP.LoreData.beasts and BLP.LoreData.beasts[npcId]
        family = bundled and bundled.family
            or (BLP.Community and BLP.Community.SharedNpcFamily and BLP.Community.SharedNpcFamily(npcId))
    end
    return family
end
Lore.TooltipFamily = tooltipFamily

local function plainList(t)
    if type(t) ~= "table" or #t == 0 then return nil end
    local out = {}
    for _, v in ipairs(t) do out[#out + 1] = type(v) == "table" and v[1] or v end
    return out
end

-- Specialization / Diet lines for a beast not lored yourself: own casts on its family, bundled
-- data (family, then this NPC), then shared lines (family, then this NPC).
function Lore.FamilyLines(npcId, family)
    local db, data, C = BLP.db or {}, BLP.LoreData or {}, BLP.Community
    local shared = C and C.SharedLore
    if family then
        local own = db.loreFamily and db.loreFamily[family]
        local lines = plainList(own and own.lines)
            or plainList(data.families and data.families[family])
            or (shared and shared(family))
        if lines then return lines end
    end
    local beast = data.beasts and data.beasts[npcId]
    return plainList(beast and beast.lines) or (shared and shared("#" .. npcId)) or nil
end

local function process(tooltip, data, knownGUID, isRecheck)
    if not BLP.isHunter or not BLP.db then return end
    local guid = knownGUID or tooltipGUID(tooltip, data)
    local npcId = BLP.NpcIdFromGUID(guid)
    if not npcId then return end

    local lines, colors = readLines(tooltip)
    local tameable, notTameable, lore, ours = classify(lines)
    if (tameable or notTameable) and not ours then
        remember(npcId, lines, colors, tameable, tooltipFamily(tooltip, guid))
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
    -- With the game's tooltip data (TooltipDataProcessor) every line is already known, so the
    -- lines can be added straight away instead of a frame later (no flicker). Wait only when the
    -- data holds Beast Lore lines the tooltip has not drawn yet.
    local complete = false
    if data and type(data.lines) == "table" then
        complete = true
        for _, l in ipairs(data.lines) do
            local text = BLP.Plain(l.leftText)
            if type(text) == "string" and isLoreLine(strip(text):lower()) then complete = false end
        end
    end
    if BLP.db.alwaysShow and (isRecheck or complete or not C_Timer) then
        local cached = BLP.db.lore and BLP.db.lore[npcId]
        local bundled = BLP.LoreData and BLP.LoreData.beasts and BLP.LoreData.beasts[npcId]
        if cached and type(cached.lines) == "table" then
            for _, l in ipairs(cached.lines) do addLoreLine(tooltip, l[1], l[2], l[3], l[4]) end
            if cached.tameable then appendSection(tooltip, npcId)
            elseif tooltip:IsShown() then tooltip:Show() end
        elseif bundled and bundled.tameable == false then
            local c = BLP.COLORS.red
            tooltip:AddLine(L.NOT_TAMEABLE, c[1], c[2], c[3])
            if tooltip:IsShown() then tooltip:Show() end
        else
            local family = tooltipFamily(tooltip, guid)
            local famLines = Lore.FamilyLines(npcId, family)
            -- Only tameable beasts are in the data (or were shared as tameable), so "Tameable" is safe.
            local sharedTameable = BLP.Community and BLP.Community.SharedLore and BLP.Community.SharedLore("#" .. npcId)
            if BLP.GetTeaches(npcId) or bundled or sharedTameable then
                local c = BLP.COLORS.green
                tooltip:AddLine(L.TAMEABLE, c[1], c[2], c[3])
                for _, text in ipairs(famLines or {}) do addLoreLine(tooltip, text) end
                appendSection(tooltip, npcId)
            end
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
