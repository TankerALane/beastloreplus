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
            end
        elseif GetSpellBookItemName then
            local ok, a, b, c = pcall(GetSpellBookItemName, i, BOOKTYPE_PET or "pet")
            if ok then name, sub, spellId = BLP.Plain(a), BLP.Plain(b), BLP.Plain(c) end
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
end

local function tryCapture(attempt)
    if not tameTarget then return end
    local petNpc = BLP.NpcIdFromPetGUID(BLP.SafeUnitGUID("pet"))
    if petNpc and petNpc ~= tameTarget.npcId then
        tameTarget = nil -- a different pet (summoned/stabled): never record
        return
    end
    local teaches, unknown = readPetAbilities()
    if (not teaches or not petNpc) and attempt < 8 then
        C_Timer.After(1, function() tryCapture(attempt + 1) end)
        return
    end
    local target = tameTarget
    tameTarget = nil
    if teaches and petNpc then recordTame(target, teaches, unknown) end
end

local function onChannelStart(unit, _, spellId)
    if unit ~= "player" or BLP.Plain(spellId) ~= TAME_BEAST_SPELL then return end
    local guid = BLP.SafeUnitGUID("target")
    local npcId = BLP.NpcIdFromGUID(guid)
    if not npcId then return end
    local level = BLP.Plain(UnitLevel("target"))
    tameTarget = {
        npcId = npcId, name = BLP.Plain(UnitName("target")), level = level,
        zone = BLP.Plain(GetZoneText and GetZoneText() or nil), started = GetTime(), channeling = true,
    }
end

local function onChannelStop(unit, _, spellId)
    if unit ~= "player" or not tameTarget or BLP.Plain(spellId) ~= TAME_BEAST_SPELL then return end
    tameTarget.channeling = false
    tameTarget.stopped = GetTime()
    -- UNIT_PET follows a successful tame; if it does not come soon, the tame failed.
    local t = tameTarget
    C_Timer.After(5, function() if tameTarget == t and not t.petSeen then tameTarget = nil end end)
end

local function onUnitPet(unit)
    if unit ~= "player" or not tameTarget then return end
    if GetTime() - tameTarget.started > 40 then tameTarget = nil return end
    tameTarget.petSeen = true
    C_Timer.After(1, function() tryCapture(1) end)
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
            lines[#lines + 1] = ("| %d | %s | %s | %d |"):format(npcId, entry.name or "?", abilitiesText(sig), senderCount(s))
        end
    end
    if gaps == 0 then lines[#lines + 1] = "| | (none) | | |" end
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

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, Community.PREFIX)
    end
    -- Everyone with the addon stores reports (the Finder can open on any class).
    BLP.On("CHAT_MSG_ADDON", onAddonMessage)
    if not BLP.isHunter then return end

    BLP.On("UNIT_SPELLCAST_CHANNEL_START", onChannelStart)
    BLP.On("UNIT_SPELLCAST_CHANNEL_STOP", onChannelStop)
    BLP.On("UNIT_PET", onUnitPet)

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
