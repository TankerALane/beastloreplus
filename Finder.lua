-- Beast Lore Plus: Ability Finder window
local _, BLP = ...
local L = BLP.L

local Finder = {}
BLP.Finder = Finder

local ROW_H = 18
local VISIBLE = 18
local frame
local state = { ability = nil, rank = 0, zone = nil, search = "", upgradesOnly = false,
                sortKey = "level", asc = true }
local data = {}       -- filtered/sorted rows
local abilityButtons = {}
local rankButtons = {}
local rows = {}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local byAbility -- key -> { {npcId, beast, rank, conf, source}, ... }

local function buildIndex()
    byAbility = {}
    for npcId, b in pairs(BLP.Beasts) do
        for _, t in ipairs(b.teaches) do
            local list = byAbility[t.ability] or {}
            byAbility[t.ability] = list
            list[#list + 1] = { npcId = npcId, beast = b, ability = t.ability, rank = t.rank,
                                conf = t.conf or b.conf, source = "bundled" }
        end
    end
end

-- Community-confirmed gap beasts (3+ senders), rebuilt each refresh.
local function communityRows()
    local out = {}
    if not BLP.db then return out end
    for npcId, entry in pairs(BLP.db.community.reports) do
        if not BLP.Beasts[npcId] then
            local teaches, source = BLP.Community.GetGapReport(npcId)
            if teaches and source == "community" then
                local beast = { name = entry.name or ("NPC " .. npcId), zones = {}, teaches = teaches }
                for _, t in ipairs(teaches) do
                    out[#out + 1] = { npcId = npcId, beast = beast, ability = t.ability, rank = t.rank,
                                      conf = "community", source = "community" }
                end
            end
        end
    end
    return out
end

local function abilityKeys()
    local keys = {}
    for key, ab in pairs(BLP.Abilities) do
        if not ab.trainerOnly and byAbility[key] then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return BLP.AbilityName(a) < BLP.AbilityName(b) end)
    return keys
end

local function contains(hay, needle)
    return hay and hay:lower():find(needle, 1, true) ~= nil
end

local function rowMatches(r, search)
    if state.ability and r.ability ~= state.ability then return false end
    if state.rank > 0 and r.rank ~= state.rank then return false end
    if state.zone then
        local ok = false
        for _, z in ipairs(r.beast.zones or {}) do if z == state.zone then ok = true end end
        if not ok then return false end
    end
    if state.upgradesOnly then
        local s = BLP.Status(r.ability, r.rank)
        if s ~= "upgrade" and s ~= "missing" then return false end
    end
    if search ~= "" then
        if not (contains(r.beast.name, search) or contains(BLP.AbilityName(r.ability), search)) then
            local zoneHit = false
            for _, z in ipairs(r.beast.zones or {}) do if contains(z, search) then zoneHit = true end end
            if not zoneHit then return false end
        end
    end
    return true
end

local function sortRows()
    local key, asc = state.sortKey, state.asc
    table.sort(data, function(a, b)
        local va, vb
        if key == "name" then va, vb = a.beast.name, b.beast.name
        elseif key == "zone" then va, vb = (a.beast.zones or {})[1] or "~", (b.beast.zones or {})[1] or "~"
        elseif key == "rank" then va, vb = BLP.AbilityName(a.ability) .. a.rank, BLP.AbilityName(b.ability) .. b.rank
        else va, vb = a.beast.minLevel or 999, b.beast.minLevel or 999 end
        if va == vb then
            if a.beast.name == b.beast.name then return a.npcId < b.npcId end
            return a.beast.name < b.beast.name
        end
        if asc then return va < vb end
        return va > vb
    end)
end

local function collect()
    wipe(data)
    local search = (state.search or ""):lower()
    local sources = {}
    if state.ability then
        sources[1] = byAbility[state.ability] or {}
    else
        for _, list in pairs(byAbility) do sources[#sources + 1] = list end
    end
    sources[#sources + 1] = communityRows()
    for _, list in ipairs(sources) do
        for _, r in ipairs(list) do
            if rowMatches(r, search) then data[#data + 1] = r end
        end
    end
    sortRows()
end

local function zonesInScope()
    local set, out = {}, {}
    local saveZone = state.zone
    state.zone = nil
    local search = (state.search or ""):lower()
    local lists = state.ability and { byAbility[state.ability] or {} } or byAbility
    for _, list in pairs(lists) do
        for _, r in ipairs(list) do
            if rowMatches(r, search) then
                for _, z in ipairs(r.beast.zones or {}) do
                    if not set[z] then set[z] = true out[#out + 1] = z end
                end
            end
        end
    end
    state.zone = saveZone
    table.sort(out)
    return out
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local function levelText(b)
    if not b.minLevel then return "?" end
    if b.maxLevel and b.maxLevel ~= b.minLevel then return b.minLevel .. "-" .. b.maxLevel end
    return tostring(b.minLevel)
end

local function tagText(r)
    if r.source == "community" then return "|cff9d9d9d" .. L.COMMUNITY .. "|r" end
    if r.conf == "unverified" or r.conf == "conflict" then return "|cff9d9d9d" .. L.UNVERIFIED .. "|r" end
    return ""
end

local function updateRows()
    if not frame then return end
    local offset = frame.scroll:GetVerticalScroll()
    local first = math.floor(offset / ROW_H)
    local showStatus = BLP.isHunter
    for i, row in ipairs(rows) do
        local r = data[first + i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(first + i - 1) * ROW_H)
        row:SetPoint("RIGHT", frame.content, "RIGHT")
        if r then
            row.data = r
            local status = BLP.Status(r.ability, r.rank)
            if showStatus and status then
                row.dot:Show()
                if status == "unknown" then
                    row.dot:SetTexture(BLP.MEDIA .. "unknown")
                    row.dot:SetVertexColor(1, 1, 1)
                else
                    row.dot:SetTexture(BLP.MEDIA .. "dot")
                    local c = BLP.StatusColor(status)
                    row.dot:SetVertexColor(c[1], c[2], c[3])
                end
            else
                row.dot:Hide()
            end
            local b = r.beast
            local name = b.name
            if b.elite then name = name .. " |cffd4a44c(elite)|r" end
            if b.rare then name = name .. " |cffc0c0ff(rare)|r" end
            row.name:SetText(name)
            row.rank:SetText(state.ability and L.RANK:format(r.rank) or (BLP.AbilityName(r.ability) .. " " .. r.rank))
            row.level:SetText(levelText(b))
            row.zone:SetText(table.concat(b.zones or {}, ", "))
            row.tag:SetText(tagText(r))
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end
end

local function updateHeader()
    local key = state.ability
    if not key then
        frame.info:SetText(("All abilities \226\128\148 %d result(s)"):format(#data))
    else
        local ab = BLP.Abilities[key]
        local text = BLP.AbilityName(key)
        if state.rank > 0 then
            local r = ab.ranks[state.rank]
            local bits = {}
            if r and r.petLevel then bits[#bits + 1] = "pet level " .. r.petLevel end
            if r and r.tp then bits[#bits + 1] = r.tp .. " training points" end
            text = text .. " " .. L.RANK:format(state.rank)
            if #bits > 0 then text = text .. ": " .. table.concat(bits, ", ") end
            if BLP.isHunter then
                local s = BLP.Status(key, state.rank)
                text = text .. "   " .. BLP.DotString(s) .. " " .. BLP.StatusText(s)
            end
        elseif BLP.isHunter and BLP.char and BLP.char.scanned then
            local known = BLP.char.known[key]
            text = text .. "   (you know " .. (known and L.RANK:format(known) or "no rank") .. ")"
        end
        frame.info:SetText(text .. ("  \226\128\148 %d result(s)"):format(#data))
    end
    for _, btn in ipairs(abilityButtons) do
        if btn.key == state.ability then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    local max = key and BLP.MaxRank(key) or 0
    for i, btn in ipairs(rankButtons) do
        local rank = i - 1
        btn:SetShown(rank == 0 or rank <= max)
        if rank == state.rank then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    frame.zoneBtn:SetText("Zone: " .. (state.zone or "All"))
    local canUpgrade = BLP.isHunter and BLP.char and BLP.char.scanned
    frame.upgrades:SetEnabled(canUpgrade and true or false)
    frame.upgrades:SetChecked(canUpgrade and state.upgradesOnly or false)
    frame.upgradesLabel:SetTextColor(canUpgrade and 1 or 0.5, canUpgrade and 0.82 or 0.5, canUpgrade and 0 or 0.5)
    frame.statusHeader:SetShown(BLP.isHunter)
end

function Finder.Refresh()
    if not frame or not frame:IsShown() then return end
    if not state.upgradesOnly or (BLP.isHunter and BLP.char.scanned) then
        collect()
    else
        state.upgradesOnly = false
        collect()
    end
    frame.content:SetHeight(math.max(1, #data * ROW_H))
    updateHeader()
    updateRows()
    if BLP.db then
        BLP.db.finder.ability, BLP.db.finder.rank = state.ability, state.rank
        BLP.db.finder.upgradesOnly = state.upgradesOnly
    end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local function rowTooltip(row)
    local r = row.data
    if not r then return end
    local b = r.beast
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.name, 1, 1, 1)
    GameTooltip:AddLine(("Level %s"):format(levelText(b)), 0.8, 0.8, 0.8)
    if b.zones and #b.zones > 0 then GameTooltip:AddLine(table.concat(b.zones, ", "), 0.8, 0.8, 0.8, true) end
    local c = BLP.COLORS
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.PET_ABILITIES, c.gold[1], c.gold[2], c.gold[3])
    for _, t in ipairs(b.teaches or {}) do
        local s = BLP.Status(t.ability, t.rank)
        local prefix = s and (BLP.DotString(s) .. " ") or ""
        GameTooltip:AddLine(prefix .. BLP.AbilityName(t.ability) .. " " .. L.RANK:format(t.rank), 1, 1, 1)
    end
    if BLP.isHunter then
        local s = BLP.Status(r.ability, r.rank)
        local col = BLP.StatusColor(s)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(BLP.StatusText(s), col[1], col[2], col[3], true)
    end
    if r.source == "community" then
        GameTooltip:AddLine("From community reports (3+ hunters agreed).", 0.6, 0.6, 0.6, true)
    elseif r.conf ~= "confirmed" then
        GameTooltip:AddLine("Only one source (or sources disagree): unverified.", 0.6, 0.6, 0.6, true)
    end
    if BLP.db.showNpcId then GameTooltip:AddLine("NPC ID: " .. r.npcId, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function makeHeader(parent, text, key, width, x)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 18)
    b:SetPoint("TOPLEFT", x, 0)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetText(text)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    if key then
        b:SetScript("OnClick", function()
            if state.sortKey == key then state.asc = not state.asc else state.sortKey, state.asc = key, true end
            Finder.Refresh()
        end)
    end
    return b
end

local COLS = { dot = 4, name = 24, rank = 238, level = 336, zone = 394, tag = 568 }

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(12, 12)
    row.dot:SetPoint("LEFT", COLS.dot, 0)
    local function fs(x, w, font)
        local f = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        f:SetPoint("LEFT", x, 0)
        f:SetWidth(w)
        f:SetJustifyH("LEFT")
        f:SetWordWrap(false)
        return f
    end
    row.name = fs(COLS.name, 210)
    row.rank = fs(COLS.rank, 96)
    row.level = fs(COLS.level, 56)
    row.zone = fs(COLS.zone, 170, "GameFontDisableSmall")
    row.tag = fs(COLS.tag, 70, "GameFontDisableSmall")
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function openZoneMenu(btn)
    local zones = zonesInScope()
    local current = GetZoneText and BLP.Plain(GetZoneText())
    local function pick(z) state.zone = z Finder.Refresh() end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(btn, function(_, root)
            root:CreateTitle("Filter by zone")
            root:CreateButton("All zones", function() pick(nil) end)
            if current and current ~= "" then
                root:CreateButton("Current zone (" .. current .. ")", function() pick(current) end)
            end
            root:CreateDivider()
            for _, z in ipairs(zones) do root:CreateButton(z, function() pick(z) end) end
            if root.SetScrollMode then root:SetScrollMode(400) end
        end)
        return
    end
    -- Fallback: cycle through the zones in scope.
    local idx = 0
    for i, z in ipairs(zones) do if z == state.zone then idx = i end end
    pick(zones[idx + 1])
end

local function create()
    buildIndex()
    local f = CreateFrame("Frame", "BeastLorePlusFinder", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(880, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    if f.TitleText then f.TitleText:SetText(L.FINDER_TITLE) end

    local logo = f:CreateTexture(nil, "OVERLAY")
    logo:SetSize(20, 20)
    logo:SetPoint("TOPLEFT", 6, -2)
    logo:SetTexture(BLP.LOGO)

    -- Left: search + ability list
    local search = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    search:SetSize(160, 20)
    search:SetPoint("TOPLEFT", 18, -34)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        Finder.Refresh()
    end)
    if search.Instructions then search.Instructions:SetText("Search beast, ability, zone") end
    f.search = search

    local keys = abilityKeys()
    table.insert(keys, 1, false) -- "All abilities"
    local listScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 10, -60)
    listScroll:SetPoint("BOTTOMLEFT", 10, 12)
    listScroll:SetWidth(170)
    local list = CreateFrame("Frame", nil, listScroll)
    list:SetSize(170, #keys * 21)
    listScroll:SetScrollChild(list)
    for i, key in ipairs(keys) do
        local b = CreateFrame("Button", nil, list)
        b:SetSize(168, 20)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 21)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexture(key and BLP.AbilityIcon(key) or BLP.LOGO)
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetWidth(140)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        text:SetText(key and BLP.AbilityName(key) or "All abilities")
        b.key = key or nil
        b:SetScript("OnClick", function()
            state.ability = b.key
            if not b.key or state.rank > BLP.MaxRank(b.key) then state.rank = 0 end
            state.zone = nil
            Finder.Refresh()
        end)
        abilityButtons[#abilityButtons + 1] = b
    end

    -- Right: info, rank buttons, zone filter, upgrades toggle
    local right = 206
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.info:SetPoint("TOPLEFT", right, -36)
    f.info:SetPoint("RIGHT", -16, 0)
    f.info:SetJustifyH("LEFT")

    for rank = 0, 8 do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(rank == 0 and 44 or 28, 22)
        b:SetText(rank == 0 and "All" or tostring(rank))
        if rank == 0 then b:SetPoint("TOPLEFT", right, -60)
        else b:SetPoint("LEFT", rankButtons[rank], "RIGHT", 2, 0) end
        b:SetScript("OnClick", function() state.rank = rank Finder.Refresh() end)
        rankButtons[#rankButtons + 1] = b
    end

    local zoneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    zoneBtn:SetSize(160, 22)
    zoneBtn:SetPoint("TOPLEFT", right + 300, -60)
    zoneBtn:SetScript("OnClick", openZoneMenu)
    zoneBtn:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then state.zone = nil Finder.Refresh() end
    end)
    f.zoneBtn = zoneBtn

    local up = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    up:SetSize(24, 24)
    up:SetPoint("LEFT", zoneBtn, "RIGHT", 10, 0)
    up:SetScript("OnClick", function(self) state.upgradesOnly = self:GetChecked() and true or false Finder.Refresh() end)
    up:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Show only upgrades for me")
        GameTooltip:AddLine("Ranks you know at a lower level (orange) or not at all (red).", 1, 1, 1, true)
        if not BLP.isHunter then
            GameTooltip:AddLine("Hunters only.", 0.6, 0.6, 0.6)
        elseif not (BLP.char and BLP.char.scanned) then
            GameTooltip:AddLine(L.OPEN_TRAINING, 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    up:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.upgrades = up
    f.upgradesLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.upgradesLabel:SetPoint("LEFT", up, "RIGHT", 2, 0)
    f.upgradesLabel:SetText("Only upgrades for me")

    -- Column headers
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", right, -92)
    header:SetPoint("RIGHT", -34, 0)
    header:SetHeight(18)
    f.statusHeader = makeHeader(header, "", nil, 20, COLS.dot - 2)
    makeHeader(header, "Beast", "name", 210, COLS.name - 2)
    makeHeader(header, "Rank", "rank", 96, COLS.rank - 2)
    makeHeader(header, "Level", "level", 56, COLS.level - 2)
    makeHeader(header, "Zone", "zone", 170, COLS.zone - 2)

    -- Results list (virtualised rows)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", right, -112)
    scroll:SetPoint("BOTTOMRIGHT", -34, 36)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(640, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", updateRows)
    scroll:HookScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)
    f.scroll, f.content = scroll, content
    for i = 1, VISIBLE + 2 do rows[i] = createRow(content) end

    -- Legend
    local legend = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    legend:SetPoint("BOTTOMLEFT", right, 14)
    if BLP.isHunter then
        legend:SetText(("%s you know it   %s upgrade   %s not learned   %s open Beast Training"):format(
            BLP.DotString("known"), BLP.DotString("upgrade"), BLP.DotString("missing"), BLP.DotString("unknown")))
    else
        legend:SetText("Learned status is shown on hunters only.")
    end
    f:SetScript("OnShow", Finder.Refresh)
    frame = f
end

function Finder.Toggle()
    if not frame then
        create()
        local saved = BLP.db and BLP.db.finder or {}
        if saved.ability and BLP.Abilities[saved.ability] then state.ability = saved.ability end
        state.rank = tonumber(saved.rank) or 0
        state.upgradesOnly = saved.upgradesOnly and true or false
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function Finder.Open(abilityKey, rank)
    if not frame or not frame:IsShown() then Finder.Toggle() end
    state.ability = abilityKey
    state.rank = rank or 0
    Finder.Refresh()
end
