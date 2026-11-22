-- Beast Lore Plus: core (namespace, saved variables, helpers, status logic, slash commands)
local ADDON, BLP = ...

BLP.ADDON = ADDON
BLP.Abilities = BLP.Abilities or {}
BLP.Beasts = BLP.Beasts or {}

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
BLP.version = (GetMeta and GetMeta(ADDON, "Version")) or "dev"
if BLP.version:find("@", 1, true) then BLP.version = "dev" end

-- Logo palette (gold frame, brown field, the three status dots)
BLP.COLORS = {
    gold    = { 0.83, 0.64, 0.30 },
    brown   = { 0.23, 0.15, 0.08 },
    cream   = { 0.95, 0.89, 0.71 },
    green   = { 0.18, 0.66, 0.29 },
    orange  = { 0.91, 0.54, 0.17 },
    yellow  = { 0.98, 0.85, 0.18 },
    red     = { 0.82, 0.20, 0.17 },
    grey    = { 0.55, 0.55, 0.55 },
}
BLP.GOLD_HEX = "ffd4a44c"

BLP.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
BLP.LOGO = BLP.MEDIA .. "logo"

BLP.L = {
    PET_ABILITIES = "Pet Abilities",
    TEACHES_NOTHING = "Teaches no pet abilities",
    NO_DATA = "No known abilities",
    NO_DATA_HINT = "Tame it to help confirm!",
    OPEN_TRAINING = "Open Beast Training to see which of these you know.",
    UNVERIFIED = "unverified",
    CONFLICT = "unverified",
    COMMUNITY = "community",
    CONFIRMED_IN_GAME = "confirmed in game",
    PENDING = "community: pending (%d/%d)",
    RANK = "(Rank %d)",        -- after an ability name
    RANK_SHORT = "Rank %d",    -- on its own (Finder column)
    TAMEABLE = "Tameable",
    NOT_TAMEABLE = "Cannot Be Tamed",
    FINDER_TITLE = "Beast Lore Plus \226\128\148 Ability Finder",
    STATUS_KNOWN = "You know this rank",
    STATUS_LOWER = "You have a higher rank, but not this one",
    STATUS_UPGRADE = "You know a lower rank: taming this beast is an upgrade",
    STATUS_MISSING = "You have not learned this ability",
    STATUS_UNKNOWN = "Unknown: open Beast Training once",
}
local L = BLP.L

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
function BLP.Print(...)
    local msg = "|c" .. BLP.GOLD_HEX .. "Beast Lore Plus|r:"
    local parts = { ... }
    for i = 1, select("#", ...) do msg = msg .. " " .. tostring(parts[i]) end
    DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Diagnostic log, kept in saved variables so it can be read from disk after /reload.
function BLP.Log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    msg = date("%m-%d %H:%M:%S") .. " " .. (ok and msg or fmt)
    local db = BeastLorePlusDB
    if type(db) ~= "table" then return end
    db.debugLog = type(db.debugLog) == "table" and db.debugLog or {}
    table.insert(db.debugLog, msg)
    while #db.debugLog > 80 do table.remove(db.debugLog, 1) end
end

---------------------------------------------------------------------------
-- Secret-value safety (Forever runs on the modern engine)
---------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue
function BLP.IsSecret(v)
    if issecretvalue == nil then return false end
    local ok, res = pcall(issecretvalue, v)
    return (not ok) or res == true
end

-- Returns v when it is a readable plain value, otherwise nil.
function BLP.Plain(v)
    if v == nil or BLP.IsSecret(v) then return nil end
    return v
end

-- NPC ID from a creature/vehicle GUID ("Creature-0-6825-1-57-3127-C230CEB5A4").
function BLP.NpcIdFromGUID(guid)
    guid = BLP.Plain(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    return nil
end

-- Creature ID embedded in a pet GUID ("Pet-0-xxxx-xxxx-xxxx-<npcId>-<petNumber>").
function BLP.NpcIdFromPetGUID(guid)
    guid = BLP.Plain(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Pet" then return tonumber(id) end
    return nil
end

function BLP.SafeUnitGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    return BLP.Plain(guid)
end

---------------------------------------------------------------------------
-- Spell helpers
---------------------------------------------------------------------------
function BLP.GetSpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok then return BLP.Plain(name) end
    elseif GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok then return BLP.Plain(name) end
    end
    return nil
end

function BLP.GetSpellIcon(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok then return BLP.Plain(tex) end
    elseif GetSpellInfo then
        local ok, _, _, tex = pcall(GetSpellInfo, id)
        if ok then return BLP.Plain(tex) end
    end
    return nil
end

-- spellId -> { key = abilityKey, rank = n }, and lowercase name -> key
BLP.SpellIndex = {}
BLP.NameIndex = {}

function BLP.BuildIndexes()
    wipe(BLP.SpellIndex)
    wipe(BLP.NameIndex)
    BLP.localNamesIndexed = false
    for key, ab in pairs(BLP.Abilities) do
        BLP.NameIndex[ab.name:lower()] = key
        for rank, r in pairs(ab.ranks or {}) do
            for _, id in ipairs(r.spellIds or {}) do
                BLP.SpellIndex[id] = { key = key, rank = rank }
            end
        end
    end
end

-- The client's own (localized) name for an ability, cached.
local localNames = {}
function BLP.AbilityName(key)
    if localNames[key] then return localNames[key] end
    local ab = BLP.Abilities[key]
    if not ab then return key end
    local name
    local r1 = ab.ranks and ab.ranks[1]
    if r1 and r1.spellIds and r1.spellIds[1] then name = BLP.GetSpellName(r1.spellIds[1]) end
    if name then
        localNames[key] = name
        BLP.NameIndex[name:lower()] = key
        return name
    end
    return ab.name
end

function BLP.AbilityIcon(key)
    local ab = BLP.Abilities[key]
    if not ab then return nil end
    if ab.icon then return ab.icon end
    local r1 = ab.ranks and ab.ranks[1]
    return r1 and r1.spellIds and BLP.GetSpellIcon(r1.spellIds[1]) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function BLP.MaxRank(key)
    local ab = BLP.Abilities[key]
    local max = 0
    if ab then for rank in pairs(ab.ranks) do if rank > max then max = rank end end end
    return max
end

-- Resolve (name, "Rank 3") or a spell ID to ability key + rank.
-- Returns key, rank, explicit. explicit is false when nothing gave a rank and 1 was assumed
-- (e.g. Forever's learn message "[Lightning Breath]" for Rank 2).
function BLP.ResolveSpell(spellId, name, subText)
    if spellId and BLP.SpellIndex[spellId] then
        local e = BLP.SpellIndex[spellId]
        return e.key, e.rank, true
    end
    name = BLP.Plain(name)
    if type(name) ~= "string" then return nil end
    if not BLP.localNamesIndexed then
        BLP.localNamesIndexed = true
        for key in pairs(BLP.Abilities) do BLP.AbilityName(key) end -- adds the client's names
    end
    -- "Tendon Rip (Rank 1)" (spell links and learn messages on Forever)
    local paren, parenRank = name:match("^(.-)%s*%(%D-(%d+)%)$")
    if paren and BLP.NameIndex[paren:lower()] then
        name, subText = paren, subText or parenRank
    end
    local base, roman = name:match("^(.-)%s+([IVX]+)$")
    local key = BLP.NameIndex[name:lower()] or (base and BLP.NameIndex[base:lower()])
    if not key then return nil end
    local rank = type(subText) == "string" and tonumber(subText:match("(%d+)")) or nil
    if not rank and spellId and C_Spell and C_Spell.GetSpellSubtext then
        local ok, st = pcall(C_Spell.GetSpellSubtext, spellId)
        st = ok and BLP.Plain(st) or nil
        rank = type(st) == "string" and tonumber(st:match("(%d+)")) or nil
    end
    if not rank and roman then
        local map = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8, IX = 9, X = 10 }
        rank = map[roman]
    end
    return key, rank or 1, rank ~= nil
end

---------------------------------------------------------------------------
-- Status logic
---------------------------------------------------------------------------
BLP.isHunter = false

-- "known" (green) | "lower" (yellow) | "upgrade" (orange) | "missing" (red) | "unknown" (grey ?)
-- | nil (not a hunter).
-- Learning a higher rank does not teach the lower ones, so ranks are tracked one by one
-- (char.ranks). Beast Training only lists the abilities the current pet's family can use, so a
-- lower rank shows yellow only once Beast Training has listed that ability (char.verified);
-- until then it stays green.
function BLP.Status(key, rank)
    if not BLP.isHunter then return nil end
    local char = BeastLorePlusCharDB
    if not char or not char.scanned then return "unknown" end
    local known = char.known and char.known[key] or 0
    if known == 0 then return "missing" end
    if rank > known then return "upgrade" end
    if rank == known then return "known" end
    local have = char.ranks and char.ranks[key]
    if have and have[rank] then return "known" end
    if char.verified and char.verified[key] then return "lower" end
    return "known"
end

-- Record that this character has a rank (Beast Training or a learn message). True if new.
function BLP.AddKnownRank(key, rank)
    local char = BLP.char
    if not char or not key or not rank then return false end
    char.known = char.known or {}
    char.ranks = char.ranks or {}
    char.ranks[key] = char.ranks[key] or {}
    local changed = not char.ranks[key][rank]
    char.ranks[key][rank] = true
    if rank > (char.known[key] or 0) then
        char.known[key] = rank
        changed = true
    end
    return changed
end

function BLP.StatusColor(status)
    local c = BLP.COLORS
    if status == "known" then return c.green end
    if status == "upgrade" then return c.orange end
    if status == "lower" then return c.yellow end
    if status == "missing" then return c.red end
    return c.grey
end

-- Space between a status dot and the text after it.
BLP.DOT_GAP = "   "

-- Inline texture string for a status dot (a texture, tinted; not a font glyph).
function BLP.DotString(status, size)
    size = size or 12
    if status == "unknown" then
        return ("|T%sunknown:%d:%d:0:0:32:32:0:32:0:32|t"):format(BLP.MEDIA, size, size)
    end
    local c = BLP.StatusColor(status)
    return ("|T%sdot:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(BLP.MEDIA, size, size,
        c[1] * 255, c[2] * 255, c[3] * 255)
end

function BLP.StatusText(status)
    if status == "known" then return L.STATUS_KNOWN end
    if status == "upgrade" then return L.STATUS_UPGRADE end
    if status == "lower" then return L.STATUS_LOWER end
    if status == "missing" then return L.STATUS_MISSING end
    return L.STATUS_UNKNOWN
end

-- Can a pet family learn this ability? Trainer-only abilities and BLP.FamilyAll: every family.
-- Unknown families (not in Data/Families.lua) are not filtered.
function BLP.FamilyCanLearn(family, key)
    if not family then return true end
    local ab = BLP.Abilities[key]
    if ab and ab.trainerOnly then return true end
    for _, k in ipairs(BLP.FamilyAll or {}) do if k == key then return true end end
    local list = BLP.Families and BLP.Families[family]
    if not list then return true end
    for _, k in ipairs(list) do if k == key then return true end end
    return false
end

-- Families that can learn an ability: "all", or a sorted list (empty if none is confirmed).
function BLP.FamiliesFor(key)
    local ab = BLP.Abilities[key]
    if ab and ab.trainerOnly then return "all" end
    for _, k in ipairs(BLP.FamilyAll or {}) do if k == key then return "all" end end
    local out = {}
    for family, list in pairs(BLP.Families or {}) do
        for _, k in ipairs(list) do if k == key then out[#out + 1] = family end end
    end
    table.sort(out)
    return out
end

-- What a beast teaches: bundled data first (always wins), then community data that met the
-- 3-sender rule. Returns list, source ("bundled"|"community"|"pending"|nil), extra.
function BLP.GetTeaches(npcId)
    local b = npcId and BLP.Beasts[npcId]
    if b then return b.teaches, "bundled", b end
    if BLP.Community and BLP.Community.GetGapReport then
        local teaches, state, count = BLP.Community.GetGapReport(npcId)
        if teaches then return teaches, state, count end
    end
    return nil
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULTS = {
    minimap = { hide = false },
    share = true,
    showUnknown = true,
    showNpcId = false,
    alwaysShow = false, -- show the details on mouseover without casting Beast Lore
    lore = {},          -- npcId -> Beast Lore lines seen last time
    loreFamily = {},    -- creature family -> Specialization / Diet lines seen last time
    npcFamily = {},     -- npcId -> creature family (from Beast Lore casts and tames)
    community = { reports = {}, tames = {}, lastShare = 0, lore = {}, npcFamily = {} },
    finder = {},
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
BLP.eventFrame = frame

function BLP.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then handlers[event] = nil return false end
    end
    table.insert(handlers[event], fn)
    return true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and BeastLorePlusDB and BeastLorePlusDB.showNpcId then
            BLP.Print("error in", event, err)
        end
    end
end)

BLP.initCallbacks = {}
function BLP.OnInit(fn) table.insert(BLP.initCallbacks, fn) end

BLP.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    BeastLorePlusDB = type(BeastLorePlusDB) == "table" and BeastLorePlusDB or {}
    BeastLorePlusCharDB = type(BeastLorePlusCharDB) == "table" and BeastLorePlusCharDB or {}
    applyDefaults(BeastLorePlusDB, DEFAULTS)
    applyDefaults(BeastLorePlusCharDB, { known = {}, ranks = {}, verified = {}, scanned = false, lastScan = 0 })
    BLP.db = BeastLorePlusDB
    BLP.char = BeastLorePlusCharDB
    local _, class = UnitClass("player")
    BLP.isHunter = (class == "HUNTER")
    BLP.BuildIndexes()
    for _, fn in ipairs(BLP.initCallbacks) do
        local ok, err = pcall(fn)
        if not ok then BLP.Print("init error:", err) end
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_BEASTLOREPLUS1 = "/beastloreplus"
SLASH_BEASTLOREPLUS2 = "/blp"
SlashCmdList.BEASTLOREPLUS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "finder" or msg == "find" then
        if BLP.Finder then BLP.Finder.Toggle() end
    elseif msg == "debug" then
        if BLP.Debug then BLP.Debug.Show() end
    elseif msg == "export" then
        if BLP.Community then BLP.Community.ShowExport() end
    elseif msg == "capture" then
        if BLP.Community then BLP.Community.CaptureCurrentPet() end
    elseif msg == "options" or msg == "config" or msg == "settings" then
        if BLP.Options then BLP.Options.Open() end
    elseif msg == "minimap" then
        if BLP.Minimap then BLP.Minimap.SetShown(BLP.db.minimap.hide) end
    else
        BLP.Print("commands:")
        BLP.Print("  /blp \226\128\148 open the Ability Finder")
        BLP.Print("  /blp options \226\128\148 settings")
        BLP.Print("  /blp minimap \226\128\148 show/hide the minimap button")
        BLP.Print("  /blp export \226\128\148 copy captured tames and conflicts for a GitHub issue")
        BLP.Print("  /blp capture \226\128\148 record the pet you have out now (for export)")
        BLP.Print("  /blp debug \226\128\148 dump target NPC ID, Beast Lore lines and Beast Training")
    end
end
