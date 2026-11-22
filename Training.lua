-- Beast Lore Plus: read Beast Training and keep this character's learned ranks
local _, BLP = ...

local Training = {}
BLP.Training = Training

-- Last parsed list, for /blp debug: { { key=, rank=, spellId=, name=, sub=, kind= }, ... }
Training.lastScan = nil
Training.lastSource = nil

local function eventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        local ok, valid = pcall(C_EventUtils.IsEventValid, event)
        return ok and valid
    end
    return true
end

-- Merge a parsed list into the saved known ranks. Nothing is ever removed: a hunter never
-- unlearns an ability, and Beast Training only lists what the current pet's family can use.
-- Every ability it lists is marked verified: its ranks are now known exactly, so a missing lower
-- rank can show yellow.
local function merge(list, source)
    local char = BLP.char
    if not char then return end
    char.verified = char.verified or {}
    local changed = false
    for _, e in ipairs(list) do
        if e.key and e.rank then
            if BLP.AddKnownRank(e.key, e.rank) then changed = true end
            if not char.verified[e.key] then
                char.verified[e.key] = true
                changed = true
            end
        end
    end
    if not char.scanned then changed = true end
    char.scanned = true
    char.lastScan = time()
    Training.lastScan = list
    Training.lastSource = source
    if changed and BLP.Finder and BLP.Finder.Refresh then BLP.Finder.Refresh() end
end

---------------------------------------------------------------------------
-- Forever: Beast Training is a trainer frame of type Pet
---------------------------------------------------------------------------
local function isPetTrainer()
    if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType then
        local ok, t = pcall(C_Trainer.GetTrainerType)
        return ok and t ~= nil and t == Enum.TrainerType.Pet
    end
    return false
end

local function trainerServiceSpellId(i)
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
        if ok and type(data) == "table" then return BLP.Plain(data.id) end
    end
    return nil
end

function Training.ScanTrainer()
    if not GetNumTrainerServices then return false end
    local ok, n = pcall(GetNumTrainerServices)
    if not ok or type(n) ~= "number" or n == 0 then return false end
    local petTrainer = isPetTrainer()
    local list, matched = {}, 0
    for i = 1, n do
        local name, sub, kind
        if GetTrainerServiceInfo then
            local ok2, a, b, c = pcall(GetTrainerServiceInfo, i)
            if ok2 then name, sub, kind = BLP.Plain(a), BLP.Plain(b), BLP.Plain(c) end
        end
        if kind ~= "header" then
            local spellId = trainerServiceSpellId(i)
            local key, rank = BLP.ResolveSpell(spellId, name, sub)
            if key then matched = matched + 1 end
            list[#list + 1] = { key = key, rank = rank, spellId = spellId, name = name, sub = sub, kind = kind }
        end
    end
    -- Not reported as a Pet trainer: accept only if most entries are pet abilities we know
    -- (a class or profession trainer never is).
    if not petTrainer and (matched < 2 or matched * 2 < #list) then return false end
    merge(list, petTrainer and "trainer" or "trainer (matched by content)")
    return true
end

---------------------------------------------------------------------------
-- Classic Craft API (not on Forever 1.60.1; kept behind a feature test)
---------------------------------------------------------------------------
function Training.ScanCraft()
    if not GetNumCrafts or not GetCraftInfo then return false end
    local ok, n = pcall(GetNumCrafts)
    if not ok or type(n) ~= "number" or n == 0 then return false end
    if GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() then return false end -- a profession
    local list = {}
    for i = 1, n do
        local ok2, name, sub, kind = pcall(GetCraftInfo, i)
        if ok2 and kind ~= "header" then
            local key, rank = BLP.ResolveSpell(nil, name, sub)
            list[#list + 1] = { key = key, rank = rank, name = name, sub = sub, kind = kind }
        end
    end
    merge(list, "craft")
    return true
end

---------------------------------------------------------------------------
-- "You have learned a new spell: [Bite (Rank 3)]" (Forever sends a spell link)
---------------------------------------------------------------------------
-- Highest rank of an ability the current pet knows, or nil.
function Training.PetRank(key)
    local read = BLP.Community and BLP.Community.ReadPetAbilities
    if not read then return nil end
    local ok, list = pcall(read)
    if not ok or type(list) ~= "table" then return nil end
    local best
    for _, t in ipairs(list) do
        if t.ability == key and (not best or t.rank > best) then best = t.rank end
    end
    return best
end

local learnPattern
local function onSystemMessage(msg)
    msg = BLP.Plain(msg)
    if type(msg) ~= "string" or not ERR_LEARN_SPELL_S then return end
    if not learnPattern then
        local p = ERR_LEARN_SPELL_S:gsub("%%s", "\001")
        p = p:gsub("[%%%(%)%.%-%+%*%?%[%]%^%$]", "%%%0")
        p = p:gsub("\001", "(.+)")
        learnPattern = "^" .. p .. "$"
    end
    local what = msg:match(learnPattern)
    if not what then return end
    local spellId = tonumber(what:match("|Hspell:(%d+)"))
    local key, rank, explicit = BLP.ResolveSpell(spellId, what:match("%[(.-)%]") or what, nil)
    local from = explicit and "message" or "assumed"
    if key and not explicit then
        -- No rank in the message (Forever sends "[Lightning Breath]" for Rank 2). Abilities are
        -- learned from the pet, so take the rank the current pet knows.
        local petRank = Training.PetRank(key)
        if petRank then rank, explicit, from = petRank, true, "pet" end
    end
    BLP.Log("learned: %s spell=%s -> %s %s (%s)", (what:gsub("|", "/")), tostring(spellId), tostring(key),
        tostring(rank), from)
    if key and rank then
        -- The link carries the hunter's copy of the spell (e.g. 1265043 for Tendon Rip 1), not the
        -- pet's; remember it so later scans and messages match by ID too (only when the rank is sure).
        if spellId and explicit and not BLP.SpellIndex[spellId] then
            BLP.SpellIndex[spellId] = { key = key, rank = rank }
        end
        -- Saved even before the first Beast Training scan; the dots stay grey until that scan.
        if BLP.AddKnownRank(key, rank) and BLP.Finder and BLP.Finder.Refresh then BLP.Finder.Refresh() end
    end
end

Training.OnSystemMessage = onSystemMessage

-- Record what the trainer reported, for /blp debug.
local function trainerEvent(event)
    local info = { event = event, time = time() }
    if C_Trainer and C_Trainer.GetTrainerType then
        local ok, t = pcall(C_Trainer.GetTrainerType)
        info.trainerType = ok and BLP.Plain(t) or "error"
    end
    info.petType = Enum and Enum.TrainerType and Enum.TrainerType.Pet
    if GetNumTrainerServices then
        local ok, n = pcall(GetNumTrainerServices)
        info.services = ok and BLP.Plain(n) or "error"
    end
    info.scanned = Training.ScanTrainer()
    Training.lastTrainerEvent = info
    if event == "TRAINER_SHOW" then
        local unmatched = {}
        for _, e in ipairs(info.scanned and Training.lastScan or {}) do
            if not e.key then
                unmatched[#unmatched + 1] = ("%s/%s#%s"):format(tostring(e.name), tostring(e.sub), tostring(e.spellId))
            end
        end
        local listed = {}
        for _, e in ipairs(info.scanned and Training.lastScan or {}) do
            if e.key then listed[#listed + 1] = ("%s:%s(%s)"):format(e.key, tostring(e.rank), tostring(e.kind)) end
        end
        BLP.Log("trainer: type=%s pet=%s services=%s scanned=%s unmatched=[%s] listed=[%s]",
            tostring(info.trainerType), tostring(info.petType), tostring(info.services), tostring(info.scanned),
            table.concat(unmatched, "; "), table.concat(listed, " "))
    end
end

BLP.OnInit(function()
    if not BLP.isHunter then return end
    BLP.On("TRAINER_SHOW", function() C_Timer.After(0.1, function() trainerEvent("TRAINER_SHOW") end) end)
    BLP.On("TRAINER_UPDATE", function() trainerEvent("TRAINER_UPDATE") end)
    if eventValid("CRAFT_UPDATE") then
        BLP.On("CRAFT_SHOW", Training.ScanCraft)
        BLP.On("CRAFT_UPDATE", Training.ScanCraft)
    end
    BLP.On("CHAT_MSG_SYSTEM", onSystemMessage)
end)
