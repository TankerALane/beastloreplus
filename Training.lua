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

-- Merge a parsed list into the saved known ranks. Ranks only go up: a hunter never unlearns
-- an ability, and a filtered trainer list must not erase what is already known.
local function merge(list, source)
    local char = BLP.char
    if not char then return end
    local changed = false
    for _, e in ipairs(list) do
        if e.key and e.rank then
            local cur = char.known[e.key] or 0
            if e.rank > cur then
                char.known[e.key] = e.rank
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
    if not isPetTrainer() or not GetNumTrainerServices then return false end
    local ok, n = pcall(GetNumTrainerServices)
    if not ok or type(n) ~= "number" or n == 0 then return false end
    local list = {}
    for i = 1, n do
        local name, sub, kind
        if GetTrainerServiceInfo then
            local ok2, a, b, c = pcall(GetTrainerServiceInfo, i)
            if ok2 then name, sub, kind = BLP.Plain(a), BLP.Plain(b), BLP.Plain(c) end
        end
        if kind ~= "header" then
            local spellId = trainerServiceSpellId(i)
            local key, rank = BLP.ResolveSpell(spellId, name, sub)
            list[#list + 1] = { key = key, rank = rank, spellId = spellId, name = name, sub = sub, kind = kind }
        end
    end
    merge(list, "trainer")
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
    local key, rank = BLP.ResolveSpell(spellId, what:match("%[(.-)%]") or what, nil)
    if key and rank and spellId and BLP.SpellIndex[spellId] then
        -- Only a scanned character gets field updates; otherwise the grey "?" would turn into
        -- misleading reds for everything else.
        local char = BLP.char
        if char and char.scanned and rank > (char.known[key] or 0) then
            char.known[key] = rank
            if BLP.Finder and BLP.Finder.Refresh then BLP.Finder.Refresh() end
        end
    end
end

BLP.OnInit(function()
    if not BLP.isHunter then return end
    BLP.On("TRAINER_SHOW", function() C_Timer.After(0.1, Training.ScanTrainer) end)
    BLP.On("TRAINER_UPDATE", Training.ScanTrainer)
    if eventValid("CRAFT_UPDATE") then
        BLP.On("CRAFT_SHOW", Training.ScanCraft)
        BLP.On("CRAFT_UPDATE", Training.ScanCraft)
    end
    BLP.On("CHAT_MSG_SYSTEM", onSystemMessage)
end)
