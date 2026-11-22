-- Beast Lore Plus: copyable text window, /blp debug
local _, BLP = ...

local Debug = {}
BLP.Debug = Debug

local window
local function createWindow()
    local f = CreateFrame("Frame", "BeastLorePlusCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(620, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    if f.TitleText then f.title:Hide() end

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(560)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnTextChanged", function(self, user)
        if user and f.text then self:SetText(f.text) self:HighlightText() end -- read-only
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    local select = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    select:SetSize(120, 22)
    select:SetPoint("BOTTOMLEFT", 12, 12)
    select:SetText("Select all")
    select:SetScript("OnClick", function() edit:SetFocus() edit:HighlightText() end)

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)
    return f
end

function Debug.ShowText(title, text)
    window = window or createWindow()
    if window.TitleText then window.TitleText:SetText(title) else window.title:SetText(title) end
    window.text = text
    window.edit:SetText(text)
    window:Show()
    window.edit:SetFocus()
    window.edit:HighlightText()
end

---------------------------------------------------------------------------
-- /blp debug
---------------------------------------------------------------------------
local function has(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return false end
        cur = cur[part]
    end
    return cur ~= nil
end

local PROBES = {
    "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Unit", "C_TooltipInfo.GetTrainerService",
    "C_Trainer.GetTrainerType", "Enum.TrainerType.Pet", "GetNumTrainerServices", "GetTrainerServiceInfo",
    "GetNumCrafts", "GetCraftInfo", "C_SpellBook.HasPetSpells", "C_SpellBook.GetSpellBookItemInfo",
    "Enum.SpellBookSpellBank.Pet", "HasPetSpells", "GetSpellBookItemName", "C_ChatInfo.SendAddonMessage",
    "C_ChatInfo.RegisterAddonMessagePrefix", "Enum.SendAddonMessageResult", "JoinTemporaryChannel",
    "JoinChannelByName", "ChatFrame_RemoveChannel", "Settings.RegisterCanvasLayoutCategory",
    "MenuUtil.CreateContextMenu", "issecretvalue", "C_Spell.GetSpellName",
}

local function q(v)
    if v == nil then return "nil" end
    if BLP.IsSecret(v) then return "SECRET" end
    if type(v) == "string" then return ("%q"):format(v) end
    return tostring(v)
end

function Debug.Text()
    local out = {}
    local function add(s) out[#out + 1] = s end
    local version, build, _, iface = GetBuildInfo()
    add(("Beast Lore Plus %s | client %s (%s) interface %s | hunter=%s"):format(BLP.version,
        q(version), q(build), q(iface), tostring(BLP.isHunter)))
    add(("Tooltip hook: %s"):format(BLP.Lore and BLP.Lore.hookType or "none (not a hunter?)"))
    add("")

    add("== Target")
    local guid = BLP.SafeUnitGUID("target")
    add(("guid=%s npcId=%s name=%s type=%s"):format(q(guid), q(BLP.NpcIdFromGUID(guid)),
        q(BLP.Plain(UnitName("target"))), q(BLP.Plain(UnitCreatureType("target")))))
    local npcId = BLP.NpcIdFromGUID(guid)
    if npcId then
        local teaches, source, extra = BLP.GetTeaches(npcId)
        add(("database: %s%s"):format(source or "missing",
            teaches and (" sig=" .. BLP.Community.Signature(teaches)) or ""))
        if source == "bundled" then add("conf=" .. tostring(extra.conf)) end
    end
    add("")

    add("== Current GameTooltip lines")
    if GameTooltip and GameTooltip:IsShown() then
        for i = 1, GameTooltip:NumLines() do
            local l = _G["GameTooltipTextLeft" .. i]
            local r = _G["GameTooltipTextRight" .. i]
            add(("%d: %s | %s"):format(i, q(l and l:GetText()), q(r and r:IsShown() and r:GetText() or nil)))
        end
    else
        add("(GameTooltip not shown)")
    end
    add("")

    add("== Last Beast Lore display seen")
    local s = BLP.Lore and BLP.Lore.lastSnapshot
    if s then
        add(("at %s npcId=%s tooltip=%s recheck=%s"):format(date("%H:%M:%S", s.time), q(s.npcId),
            q(s.tooltip), tostring(s.recheck)))
        for i, text in ipairs(s.lines) do add(("  %d: %s"):format(i, q(text))) end
        if s.dataLines then
            add("  tooltip data lines (text | right | type):")
            for i, l in ipairs(s.dataLines) do add(("  %d: %s | %s | %s"):format(i, q(l.text), q(l.right), q(l.type))) end
        end
    else
        add("(none yet: cast Beast Lore on a beast)")
    end
    local c = BLP.Lore and BLP.Lore.lastCast
    if c then add(("last Beast Lore cast at %s on npcId %s"):format(date("%H:%M:%S", c.time), q(c.npcId))) end
    add("")

    add("== Beast Training (this character)")
    local char = BLP.char or {}
    add(("scanned=%s lastScan=%s"):format(tostring(char.scanned),
        char.lastScan and char.lastScan > 0 and date("%Y-%m-%d %H:%M", char.lastScan) or "never"))
    local keys = {}
    for k in pairs(char.known or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local have = {}
        for r in pairs(char.ranks and char.ranks[k] or {}) do have[#have + 1] = r end
        table.sort(have)
        add(("  %s = rank %d (has %s)%s"):format(k, char.known[k], #have > 0 and table.concat(have, ",") or "?",
            char.verified and char.verified[k] and ", checked in Beast Training" or ""))
    end
    local te = BLP.Training and BLP.Training.lastTrainerEvent
    if te then
        add(("last trainer event: %s at %s, trainer type=%s (Pet=%s), services=%s, scanned=%s"):format(
            te.event, date("%H:%M:%S", te.time), q(te.trainerType), q(te.petType), q(te.services), tostring(te.scanned)))
    else
        add("last trainer event: none this session (open Beast Training)")
    end
    local last = BLP.Training and BLP.Training.lastScan
    if last then
        add(("last scan this session via %s, %d entries:"):format(BLP.Training.lastSource or "?", #last))
        for i, e in ipairs(last) do
            add(("  %d: spell=%s name=%s sub=%s type=%s -> %s %s"):format(i, q(e.spellId), q(e.name),
                q(e.sub), q(e.kind), tostring(e.key or "UNMATCHED"), tostring(e.rank or "")))
        end
    end
    add("")

    add("== Community")
    local lc = BLP.Community and BLP.Community.lastCapture
    add(("last capture: %s"):format(lc and (lc.npcId .. " " .. (lc.name or "?") .. " " .. lc.sig) or "none"))
    local tlog = BLP.db.debugLog or {}
    add(("diagnostic log (%d, newest last):"):format(#tlog))
    for _, line in ipairs(tlog) do add("  " .. line) end
    local n = 0
    for _ in pairs(BLP.db.community.reports) do n = n + 1 end
    add(("stored NPC reports: %d, own tames: %d, sharing=%s, channel id=%s"):format(n,
        #BLP.db.community.tames, tostring(BLP.db.share),
        q(GetChannelName and GetChannelName(BLP.Community.CHANNEL))))
    add("")

    add("== API presence")
    for _, p in ipairs(PROBES) do add(("  %s %s"):format(has(p) and "yes" or "NO ", p)) end
    return table.concat(out, "\n")
end

function Debug.Show()
    Debug.ShowText("Beast Lore Plus \226\128\148 debug (copy and send to the author)", Debug.Text())
end
