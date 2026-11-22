-- Beast Lore Plus: Ability Finder window
local _, BLP = ...
local L = BLP.L

local Finder = {}
BLP.Finder = Finder

local ROW_H = 18
local createRow -- defined below; rows are created as the visible area needs them
local frame
local state = { ability = nil, rank = 0, zone = nil, search = "", sortKey = "zone", asc = true,
                level = nil,  -- nil = follow the character's level
                show = { learnable = true, learned = true, later = true } }
local data = {}       -- filtered/sorted rows
local abilityButtons = {}
local rankButtons = {}
local headerButtons = {} -- sort key -> column header button
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

-- The level used for "can learn now": the Level box, or the character's level.
local function effectiveLevel()
    if state.level then return state.level end
    return BLP.Plain(UnitLevel("player")) or 60
end

-- "learned": this hunter knows the rank (green). "learnable": not learned, and the beast is at
-- or below the level (you can tame it now). "later": not learned, beast above the level.
local function category(r)
    if BLP.Status(r.ability, r.rank) == "known" then return "learned" end -- yellow is not learned
    local min = r.beast.minLevel
    if not min or min <= effectiveLevel() then return "learnable" end
    return "later"
end

local function matchesSearch(r, search)
    if search == "" then return true end
    if contains(r.beast.name, search) or contains(BLP.AbilityName(r.ability), search) then return true end
    for _, z in ipairs(r.beast.zones or {}) do if contains(z, search) then return true end end
    return false
end

local function rowMatches(r, search)
    if state.ability and r.ability ~= state.ability then return false end
    if state.rank > 0 and r.rank ~= state.rank then return false end
    if state.zone then
        local ok = false
        for _, z in ipairs(r.beast.zones or {}) do if z == state.zone then ok = true end end
        if not ok then return false end
    end
    if not state.show[category(r)] then return false end
    return matchesSearch(r, search)
end

---------------------------------------------------------------------------
-- Zone distance (nearest first). Zone centres come from the client's map data; a dungeon uses
-- the zone it sits in. Other continents sort after this one. Falls back to A-Z if unavailable.
---------------------------------------------------------------------------
local zoneCenters -- name -> { cont, x, y }
local FAR = 1e9

local function mapsAvailable()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo
        and C_Map.GetWorldPosFromMapPos and CreateVector2D
end

local function mapCenter(mapID)
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
    if ok and cont and pos then return { cont = cont, x = pos.x, y = pos.y } end
    return nil
end

local function buildZoneCenters()
    if zoneCenters or not mapsAvailable() then return end
    local mapID = BLP.Plain(C_Map.GetBestMapForUnit("player"))
    if not mapID then return end -- loading screen: try again later
    local top = mapID
    for _ = 1, 10 do
        local info = C_Map.GetMapInfo(top)
        if info and info.parentMapID and info.parentMapID ~= 0 then top = info.parentMapID else break end
    end
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, top, nil, true)
    if not ok or type(kids) ~= "table" then return end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    local centers = {}
    for _, info in ipairs(kids) do
        local name = BLP.Plain(info.name)
        if name and (not centers[name] or (info.mapType == zoneType and not centers[name].zone)) then
            local c = mapCenter(info.mapID) or (info.parentMapID and mapCenter(info.parentMapID))
            if c then
                c.zone = info.mapType == zoneType
                centers[name] = c
            end
        end
    end
    zoneCenters = centers
end

-- Where the player is, in world coordinates.
local function playerWorldPos()
    if not mapsAvailable() then return nil end
    local mapID = BLP.Plain(C_Map.GetBestMapForUnit("player"))
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition and BLP.Plain(C_Map.GetPlayerMapPosition(mapID, "player"))
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos or CreateVector2D(0.5, 0.5))
    if ok and cont and world then return { cont = cont, x = world.x, y = world.y } end
    return mapCenter(mapID)
end

local function zoneDistance(name, me)
    local c = zoneCenters and zoneCenters[name]
    if not c or not me then return FAR end
    local d = math.sqrt((c.x - me.x) ^ 2 + (c.y - me.y) ^ 2)
    if c.cont ~= me.cont then d = d + 1e7 end
    return d
end

local function beastDistance(b, me)
    local best = FAR
    for _, z in ipairs(b.zones or {}) do
        local d = zoneDistance(z, me)
        if d < best then best = d end
    end
    return best
end

local function sortRows()
    local key, asc = state.sortKey, state.asc
    table.sort(data, function(a, b)
        if a.ability ~= b.ability then return BLP.AbilityName(a.ability) < BLP.AbilityName(b.ability) end
        if a.rank ~= b.rank then return a.rank < b.rank end
        local va, vb
        if key == "name" then va, vb = a.beast.name, b.beast.name
        elseif key == "zone" then va, vb = a.dist or FAR, b.dist or FAR
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

local resultCount = 0

local rankCounts = {}
local abilityCounts = {}
local searchCounts = {}  -- rows per ability matching the search text alone

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
    -- How many rows each ability would show under the other filters (for the ability list).
    wipe(abilityCounts)
    wipe(searchCounts)
    do
        local savedAbility, savedRank = state.ability, state.rank
        state.ability, state.rank = nil, 0
        for _, list in pairs(byAbility) do
            for _, r in ipairs(list) do
                if rowMatches(r, search) then abilityCounts[r.ability] = (abilityCounts[r.ability] or 0) + 1 end
                if search ~= "" and matchesSearch(r, search) then
                    searchCounts[r.ability] = (searchCounts[r.ability] or 0) + 1
                end
            end
        end
        state.ability, state.rank = savedAbility, savedRank
    end
    -- How many rows each rank would show under the other filters (for the rank buttons).
    wipe(rankCounts)
    if state.ability then
        local savedRank = state.rank
        state.rank = 0
        for _, list in ipairs(sources) do
            for _, r in ipairs(list) do
                if rowMatches(r, search) then rankCounts[r.rank] = (rankCounts[r.rank] or 0) + 1 end
            end
        end
        state.rank = savedRank
    end
    for _, list in ipairs(sources) do
        for _, r in ipairs(list) do
            if rowMatches(r, search) then data[#data + 1] = r end
        end
    end
    if state.sortKey == "zone" then
        buildZoneCenters()
        local me = playerWorldPos()
        for _, r in ipairs(data) do r.dist = beastDistance(r.beast, me) end
    end
    sortRows()
    resultCount = #data
    -- One ability and one rank picked: a single group, no headers needed.
    if state.ability and state.rank > 0 then return end
    local grouped, header = {}, nil
    for _, r in ipairs(data) do
        if not header or header.ability ~= r.ability or header.rank ~= r.rank then
            if header then grouped[#grouped + 1] = { spacer = true } end
            header = { header = true, ability = r.ability, rank = r.rank, count = 0 }
            grouped[#grouped + 1] = header
        end
        header.count = header.count + 1
        grouped[#grouped + 1] = r
    end
    wipe(data)
    for i, r in ipairs(grouped) do data[i] = r end
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
    -- Nearest first (A-Z among zones the map data does not know).
    buildZoneCenters()
    local me = playerWorldPos()
    local dist = {}
    for _, z in ipairs(out) do dist[z] = zoneDistance(z, me) end
    table.sort(out, function(a, b)
        if dist[a] ~= dist[b] then return dist[a] < dist[b] end
        return a < b
    end)
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
    if r.conf == "unverified" or r.conf == "conflict" then
        if BLP.Community.ConfirmedInGame(r.npcId, r.ability, r.rank) then
            return "|cff2ea84a" .. L.CONFIRMED_IN_GAME .. "|r"
        end
        return "|cff9d9d9d" .. L.UNVERIFIED .. "|r"
    end
    return ""
end

local function updateRows()
    if not frame then return end
    -- Enough row slots to fill the visible area (+2 for partial rows while scrolling).
    local needed = math.ceil((frame.scroll:GetHeight() or 0) / ROW_H) + 2
    while #rows < needed do rows[#rows + 1] = createRow(frame.content) end
    local offset = frame.scroll:GetVerticalScroll()
    local first = math.floor(offset / ROW_H)
    local showStatus = BLP.isHunter
    for i, row in ipairs(rows) do
        local r = data[first + i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(first + i - 1) * ROW_H)
        row:SetPoint("RIGHT", frame.content, "RIGHT")
        row.hIcon:Hide()
        row.hText:Hide()
        row.hInfo:Hide()
        row.hLine:Hide()
        if r and r.spacer then
            row.data = nil
            row:Hide()
        elseif r and r.header then
            row.data = r
            for _, f in ipairs({ row.name, row.rank, row.level, row.zone, row.tag }) do f:SetText("") end
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
            row.hIcon:SetTexture(BLP.AbilityIcon(r.ability))
            row.hIcon:Show()
            row.hText:SetText(BLP.AbilityName(r.ability) .. " " .. L.RANK:format(r.rank))
            row.hText:Show()
            local rk = BLP.Abilities[r.ability] and BLP.Abilities[r.ability].ranks[r.rank] or {}
            local bits = {}
            if rk.petLevel then bits[#bits + 1] = "pet level " .. rk.petLevel end
            if rk.tp and rk.tp > 0 then bits[#bits + 1] = rk.tp .. " TP" end
            bits[#bits + 1] = r.count .. (r.count == 1 and " beast" or " beasts")
            row.hInfo:SetText(table.concat(bits, "  \194\183  "))
            row.hInfo:Show()
            row.hLine:Show()
            row:Show()
        elseif r then
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
            local later = category(r) == "later"
            local shade = later and 0.55 or 1
            row.name:SetTextColor(shade, shade, shade)
            row.rank:SetTextColor(shade, shade, shade)
            row.level:SetTextColor(later and 0.85 or 1, later and 0.35 or 1, later and 0.3 or 1)
            row.rank:SetText(state.ability and L.RANK_SHORT:format(r.rank) or (BLP.AbilityName(r.ability) .. " " .. L.RANK:format(r.rank)))
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
        frame.info:SetText(("All abilities \226\128\148 %d result(s)"):format(resultCount))
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
                text = text .. "   " .. BLP.DotString(s) .. BLP.DOT_GAP .. BLP.StatusText(s)
            end
        elseif BLP.isHunter and BLP.char and BLP.char.scanned then
            local known = BLP.char.known[key]
            text = text .. "   (you know " .. (known and L.RANK_SHORT:format(known) or "no rank") .. ")"
        end
        frame.info:SetText(text .. ("  \226\128\148 %d result(s)"):format(resultCount))
    end
    local searching = (state.search or "") ~= ""
    local slot = 0
    for _, btn in ipairs(abilityButtons) do
        if btn.key == state.ability then btn:LockHighlight() else btn:UnlockHighlight() end
        -- Searching shrinks the list; level, toggles and zone only grey (the list stays put).
        local shown = not btn.key or not searching or (searchCounts[btn.key] or 0) > 0 or btn.key == state.ability
        btn:SetShown(shown)
        if shown then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 0, -slot * 21)
            slot = slot + 1
        end
        local empty = btn.key and (abilityCounts[btn.key] or 0) == 0
        btn.text:SetTextColor(empty and 0.5 or 1, empty and 0.5 or 0.82, empty and 0.5 or 0)
        btn.icon:SetDesaturated(empty and true or false)
    end
    if abilityButtons[1] then abilityButtons[1]:GetParent():SetHeight(math.max(1, slot * 21)) end
    -- Sort arrow on the active column.
    for sortKey, hb in pairs(headerButtons) do
        local active = sortKey == state.sortKey
        hb.arrow:SetShown(active)
        if active then
            if state.asc then hb.arrow:SetTexCoord(0, 0.5625, 0, 1) else hb.arrow:SetTexCoord(0, 0.5625, 1, 0) end
        end
        hb.label:SetTextColor(active and 1 or 1, active and 1 or 0.82, active and 1 or 0)
    end
    local max = key and BLP.MaxRank(key) or 0
    local knownRank = (key and BLP.isHunter and BLP.char and BLP.char.scanned) and (BLP.char.known[key] or 0) or 0
    -- Only ranks with at least one beast under the current filters get a button (the selected
    -- rank always keeps its button); visible buttons close up so there are no gaps.
    local prev = rankButtons[1]
    for i, btn in ipairs(rankButtons) do
        local rank = i - 1
        local shown = rank == 0 or (rank <= max and ((rankCounts[rank] or 0) > 0 or rank == state.rank))
        btn:SetShown(shown)
        if shown and rank > 0 then
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", prev, "RIGHT", 2, 0)
            prev = btn
        end
        if rank == state.rank then btn:LockHighlight() else btn:UnlockHighlight() end
        btn.known = rank > 0 and rank <= knownRank and BLP.Status(key, rank) == "known"
        btn:SetNormalFontObject(btn.known and "GameFontDisable" or "GameFontNormal")
        btn.ability = key
    end
    frame.zoneBtn:SetText("Zone: " .. (state.zone or "All"))
    if not frame.levelBox:HasFocus() then
        frame.levelBox:SetText(tostring(effectiveLevel()))
    end
    local canKnow = BLP.isHunter and BLP.char and BLP.char.scanned
    for toggleKey, cb in pairs(frame.toggles) do
        local enabled = toggleKey ~= "learned" or canKnow
        cb:SetEnabled(enabled and true or false)
        local on = state.show[toggleKey] and true or false
        if cb.invert then on = not on end
        cb:SetChecked(on)
        cb.label:SetTextColor(enabled and 1 or 0.5, enabled and 0.82 or 0.5, enabled and 0 or 0.5)
    end
    frame.statusHeader:SetShown(BLP.isHunter)
end

local lastView
function Finder.Refresh()
    if not frame or not frame:IsShown() then return end
    collect()
    local height = math.max(1, #data * ROW_H)
    frame.content:SetHeight(height)
    if frame.scroll.UpdateScrollChildRect then frame.scroll:UpdateScrollChildRect() end
    local view = tostring(state.ability) .. ":" .. state.rank
    local maxScroll = math.max(0, height - frame.scroll:GetHeight())
    if view ~= lastView then
        frame.scroll:SetVerticalScroll(0)
    elseif frame.scroll:GetVerticalScroll() > maxScroll then
        frame.scroll:SetVerticalScroll(maxScroll)
    end
    lastView = view
    updateHeader()
    updateRows()
    if BLP.db then
        BLP.db.finder.ability, BLP.db.finder.rank = state.ability, state.rank
        BLP.db.finder.show = state.show
        BLP.db.finder.level = state.level
        BLP.db.finder.sortKey, BLP.db.finder.asc = state.sortKey, state.asc
    end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local function rowTooltip(row)
    local r = row.data
    if not r then return end
    if r.header then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(BLP.AbilityName(r.ability) .. " " .. L.RANK:format(r.rank))
        if BLP.isHunter then
            local st = BLP.Status(r.ability, r.rank)
            local col = BLP.StatusColor(st)
            GameTooltip:AddLine(BLP.StatusText(st), col[1], col[2], col[3], true)
        end
        GameTooltip:AddLine("Click to show only this ability and rank.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
        return
    end
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
        local prefix = s and (BLP.DotString(s) .. BLP.DOT_GAP) or ""
        GameTooltip:AddLine(prefix .. BLP.AbilityName(t.ability) .. " " .. L.RANK:format(t.rank), 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    if BLP.isHunter then
        local s = BLP.Status(r.ability, r.rank)
        local col = BLP.StatusColor(s)
        GameTooltip:AddLine(BLP.StatusText(s), col[1], col[2], col[3], true)
    end
    local cat = category(r)
    if cat == "later" then
        GameTooltip:AddLine(("Not yet: this beast is level %d, above level %d."):format(b.minLevel, effectiveLevel()),
            0.85, 0.35, 0.3, true)
    elseif cat == "learnable" then
        GameTooltip:AddLine(("Can learn now: tameable at level %d."):format(effectiveLevel()), 0.18, 0.66, 0.29, true)
    end
    if r.source == "community" then
        GameTooltip:AddLine("From community reports (3+ hunters agreed).", 0.6, 0.6, 0.6, true)
    elseif r.conf ~= "confirmed" then
        GameTooltip:AddLine("Only one source (or sources disagree): unverified.", 0.6, 0.6, 0.6, true)
    end
    if BLP.db.showNpcId then GameTooltip:AddLine("NPC ID: " .. r.npcId, 0.6, 0.6, 0.6) end
    local tomtom = rawget(_G, "TomTom") and " and TomTom arrow" or ""
    GameTooltip:AddLine(("Click: map pin%s to this beast."):format(tomtom), 0.83, 0.64, 0.30, true)
    GameTooltip:Show()
end

local SORT_TIPS = {
    name = "Sort by beast name (click again to reverse).",
    rank = "Sort by ability and rank (click again to reverse).",
    level = "Sort by beast level, lowest first (click again: highest first).",
    zone = "Sort by distance from you, nearest first (click again: farthest first).",
}

local function makeHeader(parent, text, key, width, x)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 18)
    b:SetPoint("TOPLEFT", x, 0)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetText(text)
    b.label = fs
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    if key then
        b.arrow = b:CreateTexture(nil, "OVERLAY")
        b.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        b.arrow:SetSize(9, 8)
        b.arrow:SetPoint("LEFT", fs, "RIGHT", 4, 0)
        b.arrow:Hide()
        headerButtons[key] = b
        b:SetScript("OnClick", function()
            if state.sortKey == key then state.asc = not state.asc else state.sortKey, state.asc = key, true end
            Finder.Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(text)
            GameTooltip:AddLine(SORT_TIPS[key], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

local COLS = { dot = 4, name = 28, rank = 238, level = 336, zone = 394, tag = 540 }

function createRow(parent)
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
    row.zone = fs(COLS.zone, 142, "GameFontDisableSmall")
    row.tag = fs(COLS.tag, 100, "GameFontDisableSmall")
    row.hIcon = row:CreateTexture(nil, "ARTWORK")
    row.hIcon:SetSize(16, 16)
    row.hIcon:SetPoint("LEFT", COLS.name, 0)
    row.hText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.hText:SetPoint("LEFT", row.hIcon, "RIGHT", 6, 0)
    row.hInfo = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.hInfo:SetPoint("LEFT", COLS.level, 0)
    row.hLine = row:CreateTexture(nil, "BACKGROUND")
    row.hLine:SetColorTexture(BLP.COLORS.gold[1], BLP.COLORS.gold[2], BLP.COLORS.gold[3], 0.35)
    row.hLine:SetHeight(1)
    row.hLine:SetPoint("BOTTOMLEFT", 0, 0)
    row.hLine:SetPoint("BOTTOMRIGHT", 0, 0)
    row:SetScript("OnClick", function(self)
        local r = self.data
        if r and r.header then
            state.ability, state.rank = r.ability, r.rank
            Finder.Refresh()
        elseif r and not r.spacer and BLP.Waypoint then
            BLP.Waypoint.ToBeast(r.npcId, r.beast)
        end
    end)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- A lighter strip behind a scroll bar, so it doubles as a divider between panels.
local function styleScrollBar(scroll)
    local bar = scroll.ScrollBar or (scroll.GetName and scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"])
    if not bar then return end
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.55, 0.50, 0.40, 0.22)
    bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 18)
    bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -18)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local line = bar:CreateTexture(nil, "BORDER")
        line:SetColorTexture(BLP.COLORS.gold[1], BLP.COLORS.gold[2], BLP.COLORS.gold[3], 0.35)
        line:SetWidth(1)
        line:SetPoint("TOP" .. side, bg, "TOP" .. side)
        line:SetPoint("BOTTOM" .. side, bg, "BOTTOM" .. side)
    end
end

local function openZoneMenu(btn)
    local zones = zonesInScope()
    local current = GetZoneText and BLP.Plain(GetZoneText())
    local function pick(z) state.zone = z Finder.Refresh() end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(btn, function(_, root)
            root:CreateTitle("Filter by zone (nearest first)")
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
    f:SetSize(880, 560)
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
    -- Short placeholder so it fits the box; the full hint is in the tooltip.
    if search.Instructions then
        search.Instructions:SetText(SEARCH or "Search")
        search.Instructions:SetWordWrap(false)
    end
    search:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SEARCH or "Search")
        GameTooltip:AddLine("Type part of a beast name, an ability or a zone.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.search = search

    local keys = abilityKeys()
    table.insert(keys, 1, false) -- "All abilities"
    -- Tall enough to show the whole ability list without scrolling (60 px above it, 12 below).
    f:SetHeight(math.max(560, 60 + #keys * 21 + 16))
    local listScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 10, -60)
    listScroll:SetPoint("BOTTOMLEFT", 10, 12)
    listScroll:SetWidth(170)
    styleScrollBar(listScroll)
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
        b.text, b.icon = text, icon
        b:SetScript("OnClick", function()
            state.ability = b.key
            if not b.key or state.rank > BLP.MaxRank(b.key) then state.rank = 0 end
            state.zone = nil
            Finder.Refresh()
        end)
        abilityButtons[#abilityButtons + 1] = b
    end

    -- Right: info, rank buttons, zone filter; level box and learn-state toggles below
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
        if rank > 0 then
            b:SetScript("OnEnter", function(self)
                if not self.ability then return end
                local rk = BLP.Abilities[self.ability].ranks[rank] or {}
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(BLP.AbilityName(self.ability) .. " " .. L.RANK:format(rank))
                if rk.petLevel then GameTooltip:AddLine("Pet level " .. rk.petLevel, 1, 1, 1) end
                if self.known then
                    local c = BLP.COLORS.green
                    GameTooltip:AddLine("You already know this rank.", c[1], c[2], c[3])
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
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

    -- Level box and the three learn-state toggles
    local levelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("TOPLEFT", right, -94)
    levelLabel:SetText("Level")
    local levelBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    levelBox:SetSize(30, 20)
    levelBox:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)
    levelBox:SetAutoFocus(false)
    levelBox:SetNumeric(true)
    levelBox:SetMaxLetters(2)
    local function applyLevel(self)
        local n = tonumber(self:GetText())
        if n and n >= 1 and n <= 60 then state.level = n else state.level = nil end
        Finder.Refresh()
    end
    levelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    levelBox:SetScript("OnEditFocusLost", applyLevel)
    levelBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    levelBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Level")
        GameTooltip:AddLine("Beasts at or below this level can be tamed now. Defaults to your level; clear it to follow your level again.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    levelBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.levelBox = levelBox

    f.toggles = {}
    local TOGGLES = {
        { key = "later", invert = true, label = "Can learn now",
          tip = "Only beasts at or below the level, so you can tame them now. Untick to also see higher beasts (dimmed)." },
        { key = "learned", label = "Already learned",
          tip = "Also show ranks you already know. Untick to see only what you still need. Needs one Beast Training scan on this hunter." },
    }
    local anchor = levelBox
    for _, t in ipairs(TOGGLES) do
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", anchor, "RIGHT", anchor == levelBox and 18 or 6, 0)
        cb.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        cb.label:SetText(t.label)
        cb.invert = t.invert
        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked() and true or false
            if t.invert then state.show[t.key] = not checked else state.show[t.key] = checked end
            Finder.Refresh()
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(t.label)
            GameTooltip:AddLine(t.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.toggles[t.key] = cb
        anchor = cb.label
    end

    -- Column headers
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", right, -122)
    header:SetPoint("RIGHT", -34, 0)
    header:SetHeight(18)
    f.statusHeader = makeHeader(header, "", nil, 20, COLS.dot - 2)
    makeHeader(header, "Beast", "name", 210, COLS.name - 2)
    makeHeader(header, "Rank", "rank", 96, COLS.rank - 2)
    makeHeader(header, "Level", "level", 56, COLS.level - 2)
    makeHeader(header, "Zone", "zone", 142, COLS.zone - 2)

    -- Results list (virtualised rows)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", right, -142)
    scroll:SetPoint("BOTTOMRIGHT", -34, 36)
    styleScrollBar(scroll)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(640, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", updateRows)
    scroll:HookScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) updateRows() end)
    f.scroll, f.content = scroll, content

    -- Legend
    local legend = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    legend:SetPoint("BOTTOMLEFT", right, 14)
    if BLP.isHunter then
        local g = BLP.DOT_GAP
        legend:SetText(("%s%syou know it      %s%supgrade      %s%snot learned      %s%sopen Beast Training"):format(
            BLP.DotString("known"), g, BLP.DotString("upgrade"), g, BLP.DotString("missing"), g,
            BLP.DotString("unknown"), g))
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
        if type(saved.show) == "table" then
            for k in pairs(state.show) do
                if saved.show[k] ~= nil then state.show[k] = saved.show[k] and true or false end
            end
        end
        state.show.learnable = true -- what you can learn now is always shown
        state.level = tonumber(saved.level)
        if SORT_TIPS[saved.sortKey] then state.sortKey = saved.sortKey end
        if saved.asc ~= nil then state.asc = saved.asc and true or false end
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function Finder.Open(abilityKey, rank)
    if not frame or not frame:IsShown() then Finder.Toggle() end
    state.ability = abilityKey
    state.rank = rank or 0
    Finder.Refresh()
end

BLP.OnInit(function()
    BLP.On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, Finder.Refresh) end)
end)

-- Test hooks (used by tests/run_tests.lua; harmless in game).
Finder._test = {
    state = state,
    build = function() buildIndex() end,
    collect = function() collect() return data, resultCount, rankCounts end,
}
