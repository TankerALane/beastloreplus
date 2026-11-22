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

-- Spell resolution ---------------------------------------------------------
local k, r = BLP.ResolveSpell(17255)
check(k == "bite" and r == 2, "Bite rank 2 by spell id (17255)")
k, r = BLP.ResolveSpell(nil, "Bite", "Rank 5")
check(k == "bite" and r == 5, "Bite by name + Rank 5")
k, r = BLP.ResolveSpell(nil, "Claw III", nil)
check(k == "claw" and r == 3, "Claw III roman numeral")
check(BLP.ResolveSpell(nil, "Fireball", "Rank 1") == nil, "non-pet spell unresolved")

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
