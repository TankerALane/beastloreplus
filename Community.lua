-- Beast Lore Plus: tame capture, addon-message sharing, community report storage, export
local _, BLP = ...

local Community = {}
BLP.Community = Community

Community.PREFIX = "BLPlus"          -- <= 16 characters
Community.CHANNEL = "BeastLorePlus"  -- hidden custom channel
Community.QUORUM = 3                 -- distinct senders before a gap report is used
Community.MSG_VERSION = "B1"

local TAME_BEAST_SPELL = 1515
local MAX_NPCS = 400        -- stored community NPCs
local MAX_SIGS = 4          -- distinct ability sets kept per NPC
local MAX_SENDERS = 10      -- senders kept per ability set
local MAX_TAMES = 200       -- own captured tames kept for export
local MAX_MSG = 250         -- bytes

---------------------------------------------------------------------------
-- Codec (pure: no WoW API calls, so it can be unit tested)
---------------------------------------------------------------------------
-- A signature is the sorted "key:rank" list joined by ","; "-" means "teaches nothing".
function Community.Signature(teaches)
    local parts = {}
    for _, t in ipairs(teaches) do parts[#parts + 1] = t.ability .. ":" .. t.rank end
    table.sort(parts)
    if #parts == 0 then return "-" end
    return table.concat(parts, ",")
end

-- Parse and validate a signature against the known abilities. Returns teaches list or nil.
function Community.ParseSignature(sig, abilities)
    if type(sig) ~= "string" or #sig > 160 then return nil end
    if sig == "-" then return {} end
    local out, seen = {}, {}
    for entry in sig:gmatch("[^,]+") do
        local key, rank = entry:match("^([a-z_]+):(%d+)$")
        rank = tonumber(rank)
        local ab = key and abilities[key]
        if not ab or ab.trainerOnly or seen[key] or not rank or not ab.ranks[rank] then return nil end
        seen[key] = true
        out[#out + 1] = { ability = key, rank = rank }
        if #out > 8 then return nil end
    end
    if #out == 0 then return nil end
    -- canonical order only (rejects junk that happens to parse)
    if Community.Signature(out) ~= sig then return nil end
    return out
end

-- "B1|npcId|build|addonVersion|signature|name"
function Community.Encode(npcId, build, version, sig, name)
    name = tostring(name or ""):gsub("[|,]", ""):sub(1, 40)
    local msg = table.concat({ Community.MSG_VERSION, tostring(npcId), tostring(build),
                               tostring(version):sub(1, 16), sig, name }, "|")
    if #msg > MAX_MSG then return nil end
    return msg
end

function Community.Decode(msg, abilities)
    if type(msg) ~= "string" or #msg > MAX_MSG then return nil end
    local v, npc, build, ver, sig, name = msg:match("^([^|]+)|([^|]+)|([^|]*)|([^|]*)|([^|]+)|?([^|]*)$")
    if v ~= Community.MSG_VERSION then return nil end
    npc = tonumber(npc)
    if not npc or npc < 1 or npc > 9999999 or npc % 1 ~= 0 then return nil end
    if not build:match("^%d*$") or #build > 10 then return nil end
    if not ver:match("^[%w%.%-]*$") or #ver > 16 then return nil end
    if name and (#name > 40 or name:find("[%c]")) then return nil end
    local teaches = Community.ParseSignature(sig, abilities)
    if not teaches then return nil end
    return { npcId = npc, build = build, version = ver, sig = sig, teaches = teaches,
             name = (name ~= "" and name or nil) }
end

---------------------------------------------------------------------------
-- Report storage and the trust rules (pure apart from `now`)
---------------------------------------------------------------------------
-- store = BeastLorePlusDB.community.reports: [npcId] = { name=, sigs = { [sig] = { senders = {[s]=t}, first=, last= } }, last= }
function Community.AddReport(store, npcId, sig, sender, name, now)
    local entry = store[npcId]
    if not entry then
        local count, oldestId, oldestT = 0, nil, math.huge
        for id, e in pairs(store) do
            count = count + 1
            if (e.last or 0) < oldestT then oldestId, oldestT = id, e.last or 0 end
        end
        if count >= MAX_NPCS and oldestId then store[oldestId] = nil end
        entry = { sigs = {} }
        store[npcId] = entry
    end
    entry.name = entry.name or name
    entry.last = now
    local s = entry.sigs[sig]
    if not s then
        local n, weakest, weakCount = 0, nil, math.huge
        for k, v in pairs(entry.sigs) do
            n = n + 1
            local c = 0
            for _ in pairs(v.senders) do c = c + 1 end
            if c < weakCount then weakest, weakCount = k, c end
        end
        if n >= MAX_SIGS and weakest then entry.sigs[weakest] = nil end
        s = { senders = {}, first = now }
        entry.sigs[sig] = s
    end
    if not s.senders[sender] then
        local c = 0
        for _ in pairs(s.senders) do c = c + 1 end
        if c >= MAX_SENDERS then s.last = now return s end
    end
    s.senders[sender] = now
    s.last = now
    return s
end

local function senderCount(s)
    local c = 0
    for _ in pairs(s.senders) do c = c + 1 end
    return c
end
Community.SenderCount = senderCount

-- Best (most-supported) signature for an NPC: sig, count
function Community.BestSignature(store, npcId)
    local entry = store and store[npcId]
    if not entry then return nil end
    local best, bestCount = nil, 0
    for sig, s in pairs(entry.sigs) do
        local c = senderCount(s)
        if c > bestCount or (c == bestCount and best and sig < best) then best, bestCount = sig, c end
    end
    return best, bestCount
end

-- For an NPC missing from bundled data: teaches, "community"|"pending", count
function Community.GetGapReport(npcId)
    if not npcId or BLP.Beasts[npcId] or not BLP.db then return nil end
    local store = BLP.db.community.reports
    local sig, count = Community.BestSignature(store, npcId)
    if not sig then return nil end
    local teaches = Community.ParseSignature(sig, BLP.Abilities)
    if not teaches then return nil end
    if count >= Community.QUORUM then return teaches, "community", count end
    return teaches, "pending", count
end

-- True when an in-game tame (yours, or any community report) showed this beast teaching this
-- ability at this rank. Used only to replace the "unverified" tag; it never changes the data.
function Community.ConfirmedInGame(npcId, ability, rank)
    if not BLP.db or not npcId then return false end
    local needle = ability .. ":" .. rank
    local function has(sig)
        for entry in (sig or ""):gmatch("[^,]+") do if entry == needle then return true end end
        return false
    end
    local entry = BLP.db.community.reports[npcId]
    if entry then
        for sig in pairs(entry.sigs) do if has(sig) then return true end end
    end
    for _, t in ipairs(BLP.db.community.tames) do
        if t.npcId == npcId and has(t.sig) then return true end
    end
    return false
end

-- How many different hunters (you included, also via /blp capture) saw this beast arrive with no
-- pet abilities. 2 or more removes the "Tame it to help confirm!" hint.
Community.NOTHING_QUORUM = 2
function Community.NothingConfirmations(npcId)
    if not BLP.db or not npcId then return 0 end
    local senders = {}
    local entry = BLP.db.community.reports[npcId]
    local s = entry and entry.sigs["-"]
    if s then for sender in pairs(s.senders) do senders[sender] = true end end
    for _, t in ipairs(BLP.db.community.tames) do
        if t.npcId == npcId and t.sig == "-" and not t.unknown then
            senders[Community.myName or "me"] = true
        end
    end
    local n = 0
    for _ in pairs(senders) do n = n + 1 end
    return n
end

-- Reports that disagree with bundled data (never shown in game, only exported).
function Community.Conflicts()
    local out = {}
    local store = BLP.db and BLP.db.community.reports or {}
    for npcId, entry in pairs(store) do
        local b = BLP.Beasts[npcId]
        if b then
            local bundled = Community.Signature(b.teaches)
            for sig, s in pairs(entry.sigs) do
                if sig ~= bundled then
                    out[#out + 1] = { npcId = npcId, name = b.name, sig = sig, bundled = bundled,
                                      senders = senderCount(s), last = s.last }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.npcId < b.npcId end)
    return out
end

---------------------------------------------------------------------------
-- Sending: small queue, one message every 2 s, back-off on throttle
---------------------------------------------------------------------------
local queue = {}
local sending = false
local function resultName(res)
    if type(res) ~= "number" or not (Enum and Enum.SendAddonMessageResult) then return nil end
    for k, v in pairs(Enum.SendAddonMessageResult) do if v == res then return k end end
    return nil
end

local function trySend(item)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "nosend" end
    local target = item.target
    if item.chatType == "CHANNEL" then
        local id = GetChannelName and GetChannelName(Community.CHANNEL)
        if type(id) ~= "number" or id == 0 then return "nochannel" end
        target = tostring(id)
    elseif item.chatType == "GUILD" and not IsInGuild() then
        return "noguild"
    end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, Community.PREFIX, item.msg, item.chatType, target)
    if not ok then return "error" end
    local name = resultName(res)
    if res == nil or res == true or res == 0 or name == "Success" then return "ok" end
    if name == "AddonMessageThrottle" or name == "ChannelThrottle" or name == "AddOnMessageLockdown" then
        return "retry"
    end
    return "fail"
end

local function pump()
    if #queue == 0 then sending = false return end
    sending = true
    local item = queue[1]
    local res = trySend(item)
    if res == "retry" and item.tries < 6 then
        item.tries = item.tries + 1
        C_Timer.After(math.min(60, 2 ^ item.tries), pump)
        return
    end
    table.remove(queue, 1)
    C_Timer.After(2, pump)
end

local function enqueue(msg)
    for _, chatType in ipairs({ "GUILD", "CHANNEL" }) do
        queue[#queue + 1] = { msg = msg, chatType = chatType, tries = 0 }
    end
    while #queue > 40 do table.remove(queue, 1) end
    if not sending then pump() end
end

function Community.Share(tame)
    if not BLP.db.share or tame.unknown then return end
    local msg = Community.Encode(tame.npcId, tame.build, tame.version, tame.sig, tame.name)
    if msg then
        enqueue(msg)
        tame.shared = time()
    end
end

---------------------------------------------------------------------------
-- Hidden channel
---------------------------------------------------------------------------
local function hideChannelFromChatFrames()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f then
            if ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, f, Community.CHANNEL)
            elseif f.RemoveChannel then
                pcall(f.RemoveChannel, f, Community.CHANNEL)
            end
        end
    end
end

function Community.JoinChannel()
    if not BLP.isHunter or not BLP.db.share then return end
    local id = GetChannelName and GetChannelName(Community.CHANNEL)
    if type(id) ~= "number" or id == 0 then
        local join = JoinTemporaryChannel or JoinChannelByName
        if join then pcall(join, Community.CHANNEL) end
    end
    C_Timer.After(1, hideChannelFromChatFrames)
end

function Community.LeaveChannel()
    if LeaveChannelByName then pcall(LeaveChannelByName, Community.CHANNEL) end
end

function Community.SetSharing(on)
    BLP.db.share = on and true or false
    if on then Community.JoinChannel() else Community.LeaveChannel() end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local myName
local recent = {} -- sender -> { count, windowStart }

local function normalizeSender(sender)
    sender = BLP.Plain(sender)
    if type(sender) ~= "string" or sender == "" or #sender > 64 then return nil end
    if not sender:find("-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if realm then sender = sender .. "-" .. realm end
    end
    return sender
end

local function onAddonMessage(prefix, text, channel, sender)
    if BLP.Plain(prefix) ~= Community.PREFIX then return end
    sender = normalizeSender(sender)
    if not sender or sender == myName then return end
    local now = time()
    local r = recent[sender]
    if not r or now - r.start > 60 then r = { count = 0, start = now } recent[sender] = r end
    r.count = r.count + 1
    if r.count > 10 then return end -- flood: drop silently
    local report = Community.Decode(BLP.Plain(text), BLP.Abilities)
    if not report then return end
    Community.AddReport(BLP.db.community.reports, report.npcId, report.sig, sender, report.name, now)
end

---------------------------------------------------------------------------
-- Tame capture
---------------------------------------------------------------------------
local tameTarget -- { npcId, name, level, zone, started }
Community.lastCapture = nil

local function readPetAbilities()
    local list = {}
    local n
    local useNew = C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.GetSpellBookItemInfo
                   and Enum and Enum.SpellBookSpellBank
    if useNew then
        local ok, num = pcall(C_SpellBook.HasPetSpells)
        n = ok and BLP.Plain(num) or nil
    elseif HasPetSpells then
        local ok, num = pcall(HasPetSpells)
        n = ok and BLP.Plain(num) or nil
    end
    if type(n) ~= "number" or n == 0 then return nil end
    local unknown = {}
    for i = 1, n do
        local name, sub, spellId, passive
        if useNew then
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, Enum.SpellBookSpellBank.Pet)
            if ok and type(info) == "table" then
                name, sub, spellId = BLP.Plain(info.name), BLP.Plain(info.subName), BLP.Plain(info.spellID)
                passive = BLP.Plain(info.isPassive)
                local petAction = Enum.SpellBookItemType and Enum.SpellBookItemType.PetAction
                if petAction and BLP.Plain(info.itemType) == petAction then name = nil end
            end
        elseif GetSpellBookItemName then
            local ok, a, b, c = pcall(GetSpellBookItemName, i, BOOKTYPE_PET or "pet")
            if ok then name, sub, spellId = BLP.Plain(a), BLP.Plain(b), BLP.Plain(c) end
        end
        -- Pet commands and stances (Attack, Follow, Passive...) are not abilities.
        if type(sub) == "string" and (sub:find("Pet Stance", 1, true) or sub:find("Pet Command", 1, true)) then
            name = nil
        end
        if passive == nil and spellId then
            local isPassive = (C_Spell and C_Spell.IsSpellPassive) or _G.IsPassiveSpell
            if isPassive then
                local ok, p = pcall(isPassive, spellId)
                passive = ok and BLP.Plain(p) or nil
            end
        end
        local key, rank = BLP.ResolveSpell(spellId, name, sub)
        local ab = key and BLP.Abilities[key]
        if ab and not ab.trainerOnly and rank then
            list[#list + 1] = { ability = key, rank = rank }
        elseif not ab and not passive and name then
            -- An active pet spell we cannot map (e.g. a Forever ability missing from the data).
            unknown[#unknown + 1] = name .. (sub and sub ~= "" and (" (" .. sub .. ")") or "")
                .. (spellId and (" #" .. spellId) or "")
        end
    end
    return list, unknown
end

local function recordTame(target, teaches, unknown)
    local build = select(2, GetBuildInfo())
    local tame = {
        npcId = target.npcId, name = target.name, level = target.level, zone = target.zone,
        sig = Community.Signature(teaches), build = BLP.Plain(build) or "", version = BLP.version,
        time = time(),
    }
    if unknown and #unknown > 0 then tame.unknown = unknown end
    local tames = BLP.db.community.tames
    table.insert(tames, 1, tame)
    while #tames > MAX_TAMES do table.remove(tames) end
    Community.lastCapture = tame
    if tame.unknown then
        -- The ability list is incomplete: keep it for /blp export, but do not count or share it.
        BLP.Print(("tame of %s recorded with abilities this version does not know (%s). Please /blp export it."):format(
            tame.name or tame.npcId, table.concat(tame.unknown, ", ")))
        return
    end
    Community.AddReport(BLP.db.community.reports, tame.npcId, tame.sig, myName or "me", tame.name, tame.time)
    local b = BLP.Beasts[tame.npcId]
    if b and Community.Signature(b.teaches) ~= tame.sig then
        BLP.Print(("tame of %s recorded; its abilities differ from the bundled data. /blp export to report it."):format(tame.name or tame.npcId))
    elseif not b then
        BLP.Print(("tame of %s recorded (new beast for the database). Thanks!"):format(tame.name or tame.npcId))
    end
    Community.Share(tame)
    -- One-time nudge after the third capture: exports are how the bundled data gets fixed.
    BLP.db.community.captures = (BLP.db.community.captures or 0) + 1
    if BLP.db.community.captures == 3 and not BLP.db.community.nudged then
        BLP.db.community.nudged = true
        BLP.Print("thanks for taming! Type /blp export and paste it into a GitHub issue at github.com/TankerALane/beastloreplus to improve the data for everyone.")
    end
end

-- Diagnostics for /blp debug (saved to disk): tame-related events and decisions.
local function log(fmt, ...) BLP.Log("tame: " .. fmt, ...) end

local tameName
local function isTameSpell(spellId)
    spellId = BLP.Plain(spellId)
    if not spellId then return false end
    if spellId == TAME_BEAST_SPELL then return true end
    tameName = tameName or BLP.GetSpellName(TAME_BEAST_SPELL) or "Tame Beast"
    return BLP.GetSpellName(spellId) == tameName
end

local function snapshotTarget(how)
    local npcId = BLP.NpcIdFromGUID(BLP.SafeUnitGUID("target"))
    if not npcId then return nil end
    return {
        npcId = npcId, name = BLP.Plain(UnitName("target")), level = BLP.Plain(UnitLevel("target")),
        zone = BLP.Plain(GetZoneText and GetZoneText() or nil), started = GetTime(), how = how,
    }
end

local function tryCapture(attempt)
    if not tameTarget then return end
    -- On Forever every hunter pet GUID carries the same generic creature ID (165189 "Hunter Pet"),
    -- so the tamed beast is identified by the Tame Beast target, and the pet by being new.
    local petGUID = BLP.SafeUnitGUID("pet")
    if petGUID and petGUID == tameTarget.prevPet then
        if attempt < 10 then C_Timer.After(1, function() tryCapture(attempt + 1) end) end
        return
    end
    local teaches, unknown = readPetAbilities()
    if (not teaches or not petGUID) and attempt < 10 then
        C_Timer.After(1, function() tryCapture(attempt + 1) end)
        return
    end
    local target = tameTarget
    tameTarget = nil
    if teaches and petGUID then
        log("captured npc %d (pet %s): %s%s", target.npcId, petGUID, Community.Signature(teaches),
            (unknown and #unknown > 0) and (" + unknown " .. table.concat(unknown, ", ")) or "")
        recordTame(target, teaches, unknown)
    else
        log("gave up: petGUID=%s spells=%s", tostring(petGUID), teaches and "read" or "none")
    end
end

-- Any Tame Beast event arms the capture: Forever may use a cast or a channel.
local function onTameEvent(event, unit, a, b, c)
    if unit ~= "player" then return end
    local spellId = (event == "UNIT_SPELLCAST_SENT") and c or b
    if not isTameSpell(spellId) then
        local name = BLP.GetSpellName(BLP.Plain(spellId))
        if name and name:lower():find("tame", 1, true) then
            log("%s spell %s '%s' looks like taming but is not Tame Beast", event, tostring(BLP.Plain(spellId)), name)
        end
        return
    end
    local t = snapshotTarget(event)
    log("%s spell %s target npc %s", event, tostring(BLP.Plain(spellId)), t and t.npcId or "none")
    -- Keep the first arming for the same beast (a later event must not restart the clock).
    if t and (not tameTarget or tameTarget.npcId ~= t.npcId or GetTime() - tameTarget.started > 60) then
        t.prevPet = BLP.SafeUnitGUID("pet")
        tameTarget = t
        Community.lastTameTarget = t
    end
end

local function onUnitPet(unit)
    if unit ~= "player" then return end
    local petGUID = BLP.SafeUnitGUID("pet")
    log("UNIT_PET pet=%s armed=%s", tostring(petGUID), tameTarget and tameTarget.how or "no")
    if not tameTarget then return end
    if GetTime() - tameTarget.started > 60 then
        log("tame window expired")
        tameTarget = nil
        return
    end
    C_Timer.After(1, function() tryCapture(1) end)
end

-- /blp capture: record the pet you have out now. Pet GUIDs carry a generic creature ID on
-- Forever, so the beast comes from your target (target a beast of the same kind) or the last
-- Tame Beast target. A pet may have been trained since it was tamed, so manual captures are kept
-- for export and "confirmed in game" only: never shared or counted toward the 3-sender rule.
function Community.CaptureCurrentPet()
    local petGUID = BLP.SafeUnitGUID("pet")
    if not petGUID then
        BLP.Print("summon the pet you want to record first.")
        return
    end
    local src = snapshotTarget("manual")
    if not src and Community.lastTameTarget then src = Community.lastTameTarget end
    if not src then
        BLP.Print("target a wild beast of the same kind as your pet (it gives the NPC ID), then /blp capture again.")
        return
    end
    local npcId = src.npcId
    local teaches, unknown = readPetAbilities()
    if not teaches then
        BLP.Print("could not read your pet's spellbook yet; try again in a moment.")
        return
    end
    local b = BLP.Beasts[npcId]
    local build = select(2, GetBuildInfo())
    local tame = {
        npcId = npcId, name = b and b.name or src.name,
        level = src.level, zone = src.zone,
        sig = Community.Signature(teaches), build = BLP.Plain(build) or "", version = BLP.version,
        time = time(), manual = true,
    }
    if unknown and #unknown > 0 then tame.unknown = unknown end
    table.insert(BLP.db.community.tames, 1, tame)
    while #BLP.db.community.tames > MAX_TAMES do table.remove(BLP.db.community.tames) end
    Community.lastCapture = tame
    log("manual capture npc %d: %s%s", npcId, tame.sig, tame.unknown and (" + unknown " .. table.concat(tame.unknown, ", ")) or "")
    BLP.Print(("recorded your pet as NPC %d (%s): %s%s. See /blp export."):format(npcId, tame.name or "?",
        tame.sig, tame.unknown and (" + not in addon data: " .. table.concat(tame.unknown, ", ")) or ""))
end

-- An interrupted or failed Tame Beast disarms the capture.
local function onTameStopped(event, unit, _, spellId)
    if unit ~= "player" or not tameTarget or not isTameSpell(spellId) then return end
    -- Pressing the key again mid-cast fires FAILED while the real cast goes on: ignore that.
    local casting = (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player"))
    if casting then return end
    log("%s: tame of npc %d cancelled", event, tameTarget.npcId)
    tameTarget = nil
end

---------------------------------------------------------------------------
-- Export window text
---------------------------------------------------------------------------
local function abilitiesText(sig)
    local teaches = Community.ParseSignature(sig, BLP.Abilities)
    if not teaches then return sig end
    if #teaches == 0 then return "(none)" end
    local parts = {}
    for _, t in ipairs(teaches) do
        parts[#parts + 1] = (BLP.Abilities[t.ability].name) .. " " .. t.rank
    end
    return table.concat(parts, ", ")
end

function Community.ExportText()
    local build = select(2, GetBuildInfo())
    local version = GetBuildInfo()
    local lines = {
        "### Beast Lore Plus data report",
        "",
        ("Addon %s, client %s (%s)"):format(BLP.version, tostring(version), tostring(build)),
        "",
        "#### Tames captured on this account",
        "",
        "| NPC ID | Beast | Level | Zone | Pet arrived with | Bundled data | Date |",
        "|---|---|---|---|---|---|---|",
    }
    local tames = BLP.db.community.tames
    for _, t in ipairs(tames) do
        local b = BLP.Beasts[t.npcId]
        local cmp = not b and "missing" or (Community.Signature(b.teaches) == t.sig and "matches" or
            ("differs: " .. abilitiesText(Community.Signature(b.teaches))))
        local arrived = abilitiesText(t.sig)
        if t.unknown then arrived = arrived .. "; not in addon data: " .. table.concat(t.unknown, ", ") end
        if t.manual then arrived = arrived .. " (manual /blp capture)" end
        lines[#lines + 1] = ("| %d | %s | %s | %s | %s | %s | %s |"):format(t.npcId, t.name or "?",
            tostring(t.level or "?"), t.zone or "?", arrived, cmp, date("%Y-%m-%d", t.time))
    end
    if #tames == 0 then lines[#lines + 1] = "| | (none yet) | | | | | |" end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "#### Community reports that disagree with bundled data"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| NPC ID | Beast | Reported | Bundled | Senders |"
    lines[#lines + 1] = "|---|---|---|---|---|"
    local conflicts = Community.Conflicts()
    for _, c in ipairs(conflicts) do
        lines[#lines + 1] = ("| %d | %s | %s | %s | %d |"):format(c.npcId, c.name or "?",
            abilitiesText(c.sig), abilitiesText(c.bundled), c.senders)
    end
    if #conflicts == 0 then lines[#lines + 1] = "| | (none) | | | |" end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "#### Community reports for beasts missing from bundled data"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| NPC ID | Beast | Reported | Senders |"
    lines[#lines + 1] = "|---|---|---|---|"
    local gaps = 0
    local ids = {}
    for npcId in pairs(BLP.db.community.reports) do
        if not BLP.Beasts[npcId] then ids[#ids + 1] = npcId end
    end
    table.sort(ids)
    for _, npcId in ipairs(ids) do
        local entry = BLP.db.community.reports[npcId]
        for sig, s in pairs(entry.sigs) do
            gaps = gaps + 1
            local n = senderCount(s)
            lines[#lines + 1] = ("| %d | %s | %s | %d%s |"):format(npcId, entry.name or "?", abilitiesText(sig), n,
                n >= Community.QUORUM and " (ready to add)" or "")
        end
    end
    if gaps == 0 then lines[#lines + 1] = "| | (none) | | |" end

    -- Reports that agree with bundled entries still marked unverified: these confirm them.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "#### Community reports that confirm unverified bundled data"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| NPC ID | Beast | Confirms | Senders |"
    lines[#lines + 1] = "|---|---|---|---|"
    local agree = 0
    ids = {}
    for npcId in pairs(BLP.db.community.reports) do
        local b = BLP.Beasts[npcId]
        if b and b.conf ~= "confirmed" then ids[#ids + 1] = npcId end
    end
    table.sort(ids)
    for _, npcId in ipairs(ids) do
        local b = BLP.Beasts[npcId]
        local sig = Community.Signature(b.teaches)
        local s = BLP.db.community.reports[npcId].sigs[sig]
        if s then
            agree = agree + 1
            local n = senderCount(s)
            lines[#lines + 1] = ("| %d | %s | %s | %d%s |"):format(npcId, b.name, abilitiesText(sig), n,
                n >= Community.QUORUM and " (ready to add)" or "")
        end
    end
    if agree == 0 then lines[#lines + 1] = "| | (none) | | |" end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("_\"ready to add\" = reported by %d+ different hunters._"):format(Community.QUORUM)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "#### Beast Lore by family"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| Family | Lines | Seen on NPC |"
    lines[#lines + 1] = "|---|---|---|"
    local families = {}
    for family in pairs(BLP.db.loreFamily or {}) do families[#families + 1] = family end
    table.sort(families)
    for _, family in ipairs(families) do
        local fam = BLP.db.loreFamily[family]
        local parts = {}
        for _, l in ipairs(fam.lines or {}) do parts[#parts + 1] = tostring(l[1]) end
        lines[#lines + 1] = ("| %s | %s | %s |"):format(family, table.concat(parts, "; "), tostring(fam.npcId or "?"))
    end
    if #families == 0 then lines[#lines + 1] = "| (none yet) | | |" end
    return table.concat(lines, "\n")
end

function Community.ShowExport()
    if BLP.Debug then
        BLP.Debug.ShowText("Beast Lore Plus \226\128\148 export (Ctrl+C, then paste into a GitHub issue)",
            Community.ExportText())
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
BLP.OnInit(function()
    local name, realm = UnitFullName("player")
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName())
    myName = name and realm and (name .. "-" .. realm) or name
    Community.myName = myName

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, Community.PREFIX)
    end
    -- Everyone with the addon stores reports (the Finder can open on any class).
    BLP.On("CHAT_MSG_ADDON", onAddonMessage)
    if not BLP.isHunter then return end

    for _, ev in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
                          "UNIT_SPELLCAST_SUCCEEDED" }) do
        BLP.On(ev, function(...) onTameEvent(ev, ...) end)
    end
    BLP.On("UNIT_PET", onUnitPet)
    for _, ev in ipairs({ "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
        BLP.On(ev, function(...) onTameStopped(ev, ...) end)
    end
    -- 1.0.0-dev builds recorded the generic hunter-pet creature ID (165189) by mistake.
    local tames = BLP.db.community.tames
    for i = #tames, 1, -1 do
        if tames[i].npcId == 165189 then table.remove(tames, i) end
    end

    local entered = false
    BLP.On("PLAYER_ENTERING_WORLD", function()
        if entered then return end
        entered = true
        -- Join late so the hidden channel never takes the number of General/Trade.
        C_Timer.After(15, Community.JoinChannel)
        -- Re-share up to 5 recent own tames once a day, so new users hear them too.
        C_Timer.After(90, function()
            if not BLP.db.share then return end
            local now = time()
            if now - (BLP.db.community.lastShare or 0) < 86400 then return end
            BLP.db.community.lastShare = now
            for i = 1, math.min(5, #BLP.db.community.tames) do
                Community.Share(BLP.db.community.tames[i])
            end
        end)
    end)
end)
