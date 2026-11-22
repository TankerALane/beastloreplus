-- Pure-logic tests for Beast Lore Plus. Run from the repo root:  luajit tests/run_tests.lua
-- Stubs just enough of the WoW API to load the addon files' top level.

local failures, passes = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1 else failures = failures + 1 print("FAIL: " .. label) end
end

-- WoW API stubs ------------------------------------------------------------
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
UnitClass = function() return "Hunter", "HUNTER" end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
time = os.time
date = os.date
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
C_Timer = { After = function() end }

local BLP = {}
local function load(path)
    local chunk = assert(loadfile(path))
    chunk("BeastLorePlus", BLP)
end
load("Core.lua")
load("Data/Abilities.lua")
load("Data/Beasts.lua")
load("Community.lua")
BLP.BuildIndexes()
BLP.isHunter = true
BLP.db = { community = { reports = {}, tames = {} }, showUnknown = true }
BLP.char = { known = {}, scanned = false }
BeastLorePlusCharDB = BLP.char

-- Version -----------------------------------------------------------------
check(BLP.version == "dev", "unsubstituted @project-version@ becomes dev")

-- GUIDs -------------------------------------------------------------------
check(BLP.NpcIdFromGUID("Creature-0-6825-1-57-3127-C230CEB5A4") == 3127, "creature GUID")
check(BLP.NpcIdFromGUID("Vehicle-0-6825-1-57-3127-C230CEB5A4") == 3127, "vehicle GUID")
check(BLP.NpcIdFromGUID("Player-1234-0ABCDEF") == nil, "player GUID ignored")
check(BLP.NpcIdFromGUID("Pet-0-6825-1-57-3127-0102030405") == nil, "pet GUID is not a creature")
check(BLP.NpcIdFromPetGUID("Pet-0-6825-1-57-3127-0102030405") == 3127, "pet GUID npc id")
check(BLP.NpcIdFromGUID(nil) == nil and BLP.NpcIdFromGUID(42) == nil, "junk GUIDs")

-- Data integrity ----------------------------------------------------------
local nBeasts, nAbilities = 0, 0
for key, ab in pairs(BLP.Abilities) do
    nAbilities = nAbilities + 1
    check(type(ab.name) == "string", key .. " has a name")
    for rank, r in pairs(ab.ranks) do
        check(type(r.spellIds) == "table", key .. " rank " .. rank .. " spellIds")
    end
end
for npcId, b in pairs(BLP.Beasts) do
    nBeasts = nBeasts + 1
    check(type(npcId) == "number" and npcId > 0, "npc id numeric")
    check(type(b.name) == "string" and type(b.zones) == "table", "beast " .. npcId .. " fields")
    check(b.conf == "confirmed" or b.conf == "unverified" or b.conf == "conflict", "beast " .. npcId .. " conf")
    for _, t in ipairs(b.teaches) do
        local ab = BLP.Abilities[t.ability]
        check(ab and ab.ranks[t.rank] ~= nil, ("beast %d teaches known %s %s"):format(npcId, tostring(t.ability), tostring(t.rank)))
    end
end
check(nAbilities > 0 and nBeasts > 0, "data loaded")

-- Ranks go up with level: no shipped beast teaching rank N is below every rank N-1 teacher.
do
    local byAb = {}
    for npcId, b in pairs(BLP.Beasts) do
        for _, t in ipairs(b.teaches) do
            byAb[t.ability] = byAb[t.ability] or {}
            local list = byAb[t.ability][t.rank] or {}
            byAb[t.ability][t.rank] = list
            list[#list + 1] = b
        end
    end
    for ability, ranks in pairs(byAb) do
        local ref
        for rank = 1, 20 do
            local list = ranks[rank]
            if list then
                local lowest
                for _, b in ipairs(list) do
                    local hi = b.maxLevel or b.minLevel
                    if ref and hi then
                        check(hi >= ref, ("%s rank %d: %s (level %d) is not below every rank %d teacher (%d)"):format(
                            ability, rank, b.name, hi, rank - 1, ref))
                    end
                    if b.minLevel and (not lowest or b.minLevel < lowest) then lowest = b.minLevel end
                end
                if lowest then ref = lowest end
            end
        end
    end
end

-- Spell resolution ---------------------------------------------------------
local k, r = BLP.ResolveSpell(17255)
check(k == "bite" and r == 2, "Bite rank 2 by spell id (17255)")
k, r = BLP.ResolveSpell(nil, "Bite", "Rank 5")
check(k == "bite" and r == 5, "Bite by name + Rank 5")
k, r = BLP.ResolveSpell(nil, "Claw III", nil)
check(k == "claw" and r == 3, "Claw III roman numeral")
check(BLP.ResolveSpell(nil, "Fireball", "Rank 1") == nil, "non-pet spell unresolved")
k, r = BLP.ResolveSpell(1265043, "Tendon Rip (Rank 1)", nil)
check(k == "tendon_rip" and r == 1, "Forever learn link 'Tendon Rip (Rank 1)' with hunter-side id")
k, r = BLP.ResolveSpell(nil, "Bite (Rank 6)", nil)
check(k == "bite" and r == 6, "'Bite (Rank 6)'")
check(BLP.ResolveSpell(nil, "Fireball (Rank 2)", nil) == nil, "non-pet '(Rank N)' unresolved")

-- Status ----------------------------------------------------------------------
check(BLP.Status("bite", 3) == "unknown", "unscanned is unknown")
BLP.char.scanned = true
BLP.char.known.bite = 3
check(BLP.Status("bite", 2) == "known", "lower taught rank is known")
check(BLP.Status("bite", 3) == "known", "same rank is known")
check(BLP.Status("bite", 4) == "upgrade", "higher taught rank is upgrade")
check(BLP.Status("claw", 1) == "missing", "unlearned is missing")
BLP.isHunter = false
check(BLP.Status("bite", 1) == nil, "non-hunter has no status")
BLP.isHunter = true

-- Codec -----------------------------------------------------------------------
local C = BLP.Community
local teaches = { { ability = "claw", rank = 2 }, { ability = "bite", rank = 1 } }
local sig = C.Signature(teaches)
check(sig == "bite:1,claw:2", "signature sorted")
check(C.Signature({}) == "-", "empty signature")
local msg = C.Encode(3127, "71037", "1.0.0", sig, "Venomtail Scorpid")
check(msg == "B1|3127|71037|1.0.0|bite:1,claw:2|Venomtail Scorpid", "encode")
local rep = C.Decode(msg, BLP.Abilities)
check(rep and rep.npcId == 3127 and rep.sig == sig and #rep.teaches == 2, "decode round trip")
check(C.Decode("B1|3127|71037|1.0.0|-|", BLP.Abilities).sig == "-", "decode teaches-nothing")
local junk = {
    "B2|3127|71037|1.0.0|bite:1|x",          -- unknown version
    "B1|abc|71037|1.0.0|bite:1|x",           -- bad npc
    "B1|3127|71037|1.0.0|bite:99|x",         -- rank out of range
    "B1|3127|71037|1.0.0|fireball:1|x",      -- unknown ability
    "B1|3127|71037|1.0.0|claw:2,bite:1|x",   -- not canonical order
    "B1|3127|71037|1.0.0|bite:1,bite:2|x",   -- duplicate ability
    "B1|3127|71037|1.0.0|growl:1|x",         -- trainer-only ability
    "B1|3127|7a|1.0.0|bite:1|x",             -- bad build
    "B1|3127|71037|1.0.0|bite:1|" .. ("x"):rep(300),
    "hello", "", "B1|||||",
}
for i, j in ipairs(junk) do check(C.Decode(j, BLP.Abilities) == nil, "junk rejected #" .. i) end
check(C.Decode(nil, BLP.Abilities) == nil, "nil rejected")

-- Trust rules ---------------------------------------------------------------------
local gapNpc = 999001 -- not in bundled data
BLP.db.community.reports = {}
local store = BLP.db.community.reports
C.AddReport(store, gapNpc, "bite:1", "A-Realm", "Test Wolf", 1)
C.AddReport(store, gapNpc, "bite:1", "A-Realm", "Test Wolf", 2) -- same sender twice
local t1, s1, n1 = C.GetGapReport(gapNpc)
check(s1 == "pending" and n1 == 1, "one sender is pending 1/3")
C.AddReport(store, gapNpc, "bite:1", "B-Realm", nil, 3)
C.AddReport(store, gapNpc, "claw:1", "X-Realm", nil, 3) -- disagreeing report
local _, s2, n2 = C.GetGapReport(gapNpc)
check(s2 == "pending" and n2 == 2, "two senders is pending 2/3")
C.AddReport(store, gapNpc, "bite:1", "C-Realm", nil, 4)
local t3, s3, n3 = C.GetGapReport(gapNpc)
check(s3 == "community" and n3 == 3 and t3[1].ability == "bite", "three senders confirm the gap")
-- Bundled data always wins
local someNpc, someBeast = next(BLP.Beasts)
for i = 1, 5 do C.AddReport(store, someNpc, "-", "S" .. i, nil, 10) end
local bt, bs = BLP.GetTeaches(someNpc)
check(bs == "bundled" and bt == someBeast.teaches, "community never overrides bundled data")
local conflicts = C.Conflicts()
local found = false
for _, c in ipairs(conflicts) do if c.npcId == someNpc and c.sig == "-" then found = true end end
check(found or C.Signature(someBeast.teaches) == "-", "disagreeing report stored as conflict")
-- "Teaches nothing" needs 2 different hunters before the hint goes away
local noneNpc = 999002
check(C.NothingConfirmations(noneNpc) == 0, "no 'nothing' reports yet")
C.AddReport(store, noneNpc, "-", "A-Realm", "Plain Beast", 20)
C.AddReport(store, noneNpc, "-", "A-Realm", "Plain Beast", 21)
check(C.NothingConfirmations(noneNpc) == 1, "same hunter twice counts once")
C.AddReport(store, noneNpc, "-", "B-Realm", nil, 22)
check(C.NothingConfirmations(noneNpc) == 2, "two hunters confirm 'nothing'")
local selfNpc = 999003
C.AddReport(store, selfNpc, "-", "A-Realm", nil, 23)
table.insert(BLP.db.community.tames, { npcId = selfNpc, sig = "-", manual = true })
check(C.NothingConfirmations(selfNpc) == 2, "your own (manual) tame counts as one of the two")
-- Export: agreeing reports for unverified bundled beasts are listed
GetBuildInfo = function() return "1.60.1", "71037", "", 16001 end
local unv
for npcId, b in pairs(BLP.Beasts) do if b.conf == "unverified" then unv = npcId break end end
for i = 1, 3 do C.AddReport(store, unv, C.Signature(BLP.Beasts[unv].teaches), "H" .. i, nil, 30) end
local text = C.ExportText()
check(text:find("confirm unverified bundled data", 1, true) ~= nil, "export has the confirmations section")
check(text:find("| " .. unv .. " |", 1, true) ~= nil and text:find("(ready to add)", 1, true) ~= nil,
    "agreeing report from 3 hunters is listed as ready to add")
-- Finder filters: level 27 hunter, Claw, "Can learn now" on, "Already learned" off
UnitLevel = function() return 27 end
load("Finder.lua")
BLP.db.finder = {}
local FT = BLP.Finder._test
FT.build()
FT.state.ability = "claw"
FT.state.show = { learnable = true, learned = false, later = false }
local rows, count, rankCounts = FT.collect()
local claw4, claw5 = 0, 0
for _, row in ipairs(rows) do
    if not row.header and not row.spacer then
        check((row.beast.minLevel or 0) <= 27, "Can learn now hides beasts above level 27 (" .. row.beast.name .. ")")
        if row.rank == 4 then claw4 = claw4 + 1 end
        if row.rank == 5 then claw5 = claw5 + 1 end
    end
end
check(claw4 >= 2, "Claw 4 keeps the beasts you can tame at 27 (got " .. claw4 .. ")")
check(claw5 == 0 and (rankCounts[5] or 0) == 0, "Claw 5 (lowest beast 34) hidden at 27")
check(count > 0, "some Claw results at 27")
FT.state.show = { learnable = true, learned = true, later = true }
local _, all = FT.collect()
check(all > count, "unticking Can learn now shows more")
-- Nearest-first sort: player in The Barrens (Kalimdor); Eastern Kingdoms zones sort last.
do
    local KALIMDOR = { ["The Barrens"] = { 0, 0 }, ["Durotar"] = { 300, 0 }, ["Ashenvale"] = { 0, 600 },
        ["Mulgore"] = { -300, 100 }, ["Stonetalon Mountains"] = { -200, 500 }, ["Darkshore"] = { 0, 1200 },
        ["Teldrassil"] = { 0, 1500 }, ["Thousand Needles"] = { 0, -700 }, ["Dustwallow Marsh"] = { 300, -500 } }
    local maps, byId, id = {}, {}, 100
    for name, xy in pairs(KALIMDOR) do id = id + 1 maps[#maps + 1] = { mapID = id, name = name, mapType = 3 } byId[id] = { 1, xy } end
    for _, name in ipairs({ "Silverpine Forest", "Elwynn Forest", "Dun Morogh", "Tirisfal Glades", "Westfall",
                            "Loch Modan", "Redridge Mountains", "Duskwood", "Wetlands", "Hillsbrad Foothills" }) do
        id = id + 1 maps[#maps + 1] = { mapID = id, name = name, mapType = 3 } byId[id] = { 0, { 0, 0 } }
    end
    local barrens
    for _, m in ipairs(maps) do if m.name == "The Barrens" then barrens = m.mapID end end
    Enum = { UIMapType = { Zone = 3 } }
    CreateVector2D = function(x, y) return { x = x, y = y } end
    C_Map = {
        GetBestMapForUnit = function() return barrens end,
        GetMapInfo = function(m) return { mapID = m, parentMapID = (m == 1 and 0 or 1) } end,
        GetMapChildrenInfo = function() return maps end,
        GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
        GetWorldPosFromMapPos = function(m) local e = byId[m] if not e then return nil end return e[1], { x = e[2][1], y = e[2][2] } end,
    }
    FT.state.ability, FT.state.rank, FT.state.search = "bite", 3, ""
    FT.state.show = { learnable = true, learned = true, later = true }
    FT.state.sortKey, FT.state.asc = "zone", true
    local sorted = FT.collect()
    local seenEK, order = false, true
    for _, row in ipairs(sorted) do
        if not row.header and not row.spacer then
            local ek = byId[0] == nil and false
            local z = row.beast.zones and row.beast.zones[1]
            local kal = z and KALIMDOR[z] ~= nil
            if not kal and z and z ~= "" then
                for _, m in ipairs(maps) do if m.name == z and byId[m.mapID][1] == 0 then ek = true end end
            end
            if ek then seenEK = true elseif kal and seenEK then order = false end
        end
    end
    check(order, "nearest sort: Kalimdor beasts before Eastern Kingdoms beasts when in The Barrens")
    local firstZone
    for _, row in ipairs(sorted) do if not row.header and not row.spacer then firstZone = row.beast.zones[1] break end end
    check(firstZone ~= "Silverpine Forest", "nearest sort: first Bite 3 beast is not in Silverpine (" .. tostring(firstZone) .. ")")
    C_Map, CreateVector2D = nil, nil
end
-- Tooltip: details without casting Beast Lore (off by default)
do
    load("BeastLore.lua")
    local function mockTip(name, texts)
        local tip = { lines = {} }
        local function add(text, r, g, b)
            local fs = { text = text, c = { r or 1, g or 1, b or 1 } }
            function fs.GetText() return fs.text end
            function fs.GetTextColor() return fs.c[1], fs.c[2], fs.c[3] end
            tip.lines[#tip.lines + 1] = fs
            _G[name .. "TextLeft" .. #tip.lines] = fs
        end
        for _, t in ipairs(texts) do add(t) end
        function tip.GetName() return name end
        function tip.GetUnit() return texts[1], "mouseover" end
        function tip.NumLines() return #tip.lines end
        function tip.AddLine(_, text, r, g, b) add(text, r, g, b) end
        function tip.AddDoubleLine(_, text) add(text) end
        function tip.IsShown() return false end
        function tip.Show() end
        function tip.has(text)
            for _, fs in ipairs(tip.lines) do if fs.text == text then return true end end
            return false
        end
        return tip
    end
    local guid = "Creature-0-1-1-1-3255-00000001"  -- Sunscale Screecher, in the database
    BLP.db.lore, BLP.db.loreFamily = {}, {}
    local families = { ["Sunscale Screecher"] = "Tallstrider", ["Mottled Screecher"] = "Tallstrider" }
    UnitCreatureFamily = function() return nil end
    local function hoverAs(beastName) UnitCreatureFamily = function() return families[beastName] end end

    local plain = mockTip("TipA", { "Sunscale Screecher", "Level 13" })
    BLP.Lore.Process(plain, nil, guid, true)
    check(not plain.has("Pet Abilities"), "default: nothing shown without casting Beast Lore")

    local lored = mockTip("TipB", { "Sunscale Screecher", "Level 13", "Tameable", "Specialization: Cunning", "Diet: Meat" })
    hoverAs("Sunscale Screecher")
    BLP.Lore.Process(lored, nil, guid, true)
    local fam = BLP.db.loreFamily.Tallstrider
    check(fam and #fam.lines == 2 and fam.lines[1][1] == "Specialization: Cunning", "family Specialization / Diet remembered")
    check(lored.has("Pet Abilities"), "Beast Lore tooltip gets the section")
    local cached = BLP.db.lore[3255]
    check(cached and cached.tameable and #cached.lines == 3, "Beast Lore lines remembered")

    BLP.db.alwaysShow = true
    local hover = mockTip("TipC", { "Sunscale Screecher", "Level 13" })
    BLP.Lore.Process(hover, nil, guid, true)
    check(hover.has("Diet: Meat") and hover.has("Specialization: Cunning") and hover.has("Pet Abilities"),
        "toggle on: remembered Beast Lore lines and abilities shown on mouseover")

    local unseen = mockTip("TipD", { "Forest Spider", "Level 5" })
    hoverAs("Forest Spider")
    BLP.Lore.Process(unseen, nil, "Creature-0-1-1-1-30-00000002", true)
    check(unseen.has("Tameable") and unseen.has("Pet Abilities") and not unseen.has("Diet: Meat"),
        "toggle on: database beast never lored shows Tameable (no family seen)")

    local kin = mockTip("TipF", { "Mottled Screecher", "Level 16" })
    hoverAs("Mottled Screecher")
    BLP.Lore.Process(kin, nil, "Creature-0-1-1-1-1021-00000004", true)
    check(kin.has("Specialization: Cunning") and kin.has("Diet: Meat") and kin.has("Pet Abilities"),
        "toggle on: never-lored beast of a lored family shows the family's Specialization and Diet")
    check(BLP.Community.ExportText():find("| Tallstrider | Specialization: Cunning; Diet: Meat | 3255 |", 1, true),
        "export lists Beast Lore by family")
    UnitCreatureFamily = nil

    local other = mockTip("TipE", { "Defias Thug", "Level 9" })
    BLP.Lore.Process(other, nil, "Creature-0-1-1-1-38-00000003", true)
    check(#other.lines == 2, "toggle on: unknown NPCs get nothing")
    BLP.db.alwaysShow = false
end
-- Learn message without a rank: take the rank the pet knows
do
    load("Training.lua")
    ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
    BLP.char.known.lightning_breath = nil
    local realRead = BLP.Community.ReadPetAbilities
    BLP.Community.ReadPetAbilities = function() return { { ability = "lightning_breath", rank = 2 } }, {} end
    BLP.Training.OnSystemMessage("You have learned a new spell: |cff71d5ff|Hspell:25013:0|h[Lightning Breath]|h|r.")
    check(BLP.char.known.lightning_breath == 2, "unranked learn message uses the pet's rank (" ..
        tostring(BLP.char.known.lightning_breath) .. ")")
    check(BLP.SpellIndex[25013] and BLP.SpellIndex[25013].rank == 2, "hunter spell ID cached with the pet's rank")
    BLP.Community.ReadPetAbilities = function() return nil end
    BLP.char.known.cower = nil
    BLP.Training.OnSystemMessage("You have learned a new spell: |cff71d5ff|Hspell:1747:0|h[Cower]|h|r.")
    check(BLP.char.known.cower == 1, "unranked learn message with no pet out: Rank 1")
    check(BLP.SpellIndex[1747] == nil, "assumed rank is not cached")
    BLP.Training.OnSystemMessage("You have learned a new spell: |cff71d5ff|Hspell:1748:0|h[Cower (Rank 2)]|h|r.")
    check(BLP.char.known.cower == 2, "ranked learn message")
    BLP.Community.ReadPetAbilities = realRead
end

-- Caps
local capStore = {}
for i = 1, 450 do C.AddReport(capStore, i, "bite:1", "S", nil, i) end
local count = 0
for _ in pairs(capStore) do count = count + 1 end
check(count <= 400, "NPC cap holds (" .. count .. ")")
check(capStore[1] == nil and capStore[450] ~= nil, "oldest NPC dropped first")
local sigStore = {}
for i = 1, 8 do C.AddReport(sigStore, 1, "bite:" .. math.min(i, 8), "S" .. i, nil, i) end
local sigs = 0
for _ in pairs(sigStore[1].sigs) do sigs = sigs + 1 end
check(sigs <= 4, "signature cap holds")
local senderStore = {}
for i = 1, 30 do C.AddReport(senderStore, 1, "bite:1", "S" .. i, nil, i) end
check(C.SenderCount(senderStore[1].sigs["bite:1"]) <= 10, "sender cap holds")

print(("%d passed, %d failed (%d abilities, %d beasts)"):format(passes, failures, nAbilities, nBeasts))
os.exit(failures == 0 and 0 or 1)
