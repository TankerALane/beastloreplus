-- Beast Lore Plus: map pin (and TomTom arrow) to where a beast can be found
--
-- Spawn points come from, in order:
--   1. QuestieDB's NPC spawn data, read at runtime when the player has Questie installed
--      (global NpcDB; nothing is copied into this addon).
--   2. Where you were when you last targeted that beast (remembered by this addon).
-- With neither, the world map opens on the beast's zone.
local _, BLP = ...

local Waypoint = {}
BLP.Waypoint = Waypoint

local MAX_SEEN = 600
local tomtomUid

---------------------------------------------------------------------------
-- Map helpers
---------------------------------------------------------------------------
local mapIdByName -- lowercase name -> uiMapID (zones preferred over dungeons/sub-zones)

local function mapsAvailable()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo
        and C_Map.GetWorldPosFromMapPos and CreateVector2D
end

local function buildMapIndex()
    if mapIdByName or not mapsAvailable() then return end
    local mapID = BLP.Plain(C_Map.GetBestMapForUnit("player"))
    if not mapID then return end
    local top = mapID
    for _ = 1, 10 do
        local info = C_Map.GetMapInfo(top)
        if info and info.parentMapID and info.parentMapID ~= 0 then top = info.parentMapID else break end
    end
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, top, nil, true)
    if not ok or type(kids) ~= "table" then return end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    local index, isZone = {}, {}
    for _, info in ipairs(kids) do
        local name = BLP.Plain(info.name)
        if name then
            local key = name:lower()
            if not index[key] or (info.mapType == zoneType and not isZone[key]) then
                index[key] = info.mapID
                isZone[key] = info.mapType == zoneType
            end
        end
    end
    mapIdByName = index
end

function Waypoint.MapIdByName(name)
    buildMapIndex()
    return mapIdByName and type(name) == "string" and mapIdByName[name:lower()] or nil
end

local function worldPos(mapID, x, y)
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and cont and pos then return cont, pos.x, pos.y end
    return nil
end

local function playerWorld()
    local mapID = BLP.Plain(C_Map.GetBestMapForUnit("player"))
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition and BLP.Plain(C_Map.GetPlayerMapPosition(mapID, "player"))
    local x, y = 0.5, 0.5
    if pos then x, y = pos.x, pos.y end
    local cont, wx, wy = worldPos(mapID, x, y)
    if not cont then return nil end
    return { cont = cont, x = wx, y = wy }
end

---------------------------------------------------------------------------
-- Spawn points
---------------------------------------------------------------------------
-- { mapID, x (0-1), y (0-1), source }
local function questiePoints(npcId)
    local db = rawget(_G, "NpcDB")
    if type(db) ~= "table" or type(db.Get) ~= "function" then return {} end
    local ok, spawns = pcall(db.Get, npcId, "spawns")
    if not ok or type(spawns) ~= "table" then return {} end
    local out = {}
    for areaId, pts in pairs(spawns) do
        local mapID
        if C_Map.GetAreaInfo then
            local okName, areaName = pcall(C_Map.GetAreaInfo, areaId)
            mapID = okName and Waypoint.MapIdByName(BLP.Plain(areaName)) or nil
        end
        if mapID and type(pts) == "table" then
            for _, p in ipairs(pts) do
                local x, y = tonumber(p[1]), tonumber(p[2])
                if x and y and x > 0 and y > 0 then
                    out[#out + 1] = { mapID = mapID, x = x / 100, y = y / 100, source = "Questie spawn data" }
                end
            end
        end
    end
    return out
end

local function seenPoints(npcId)
    local s = BLP.db and BLP.db.seen and BLP.db.seen[npcId]
    if type(s) == "table" and s.m and s.x and s.y then
        return { { mapID = s.m, x = s.x, y = s.y, source = "where you last targeted it" } }
    end
    return {}
end

-- The point nearest to the player (other continents last).
local function nearest(points)
    local me = playerWorld()
    local best, bestD
    for i, p in ipairs(points) do
        if i > 300 then break end
        local d = math.huge
        local cont, wx, wy = worldPos(p.mapID, p.x, p.y)
        if cont and me then
            d = math.sqrt((wx - me.x) ^ 2 + (wy - me.y) ^ 2)
            if cont ~= me.cont then d = d + 1e7 end
        end
        if not best or d < bestD then best, bestD = p, d end
    end
    return best
end

---------------------------------------------------------------------------
-- Setting the pin
---------------------------------------------------------------------------
local function setPin(p, title)
    local pinned = false
    if C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local okCan, can = pcall(C_Map.CanSetUserWaypointOnMap, p.mapID)
        if okCan and can then
            pinned = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(p.mapID, p.x, p.y))
            if pinned and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
        end
    end
    local arrow = false
    local tomtom = rawget(_G, "TomTom")
    if type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" then
        if tomtomUid and type(tomtom.RemoveWaypoint) == "function" then pcall(tomtom.RemoveWaypoint, tomtom, tomtomUid) end
        local ok, uid = pcall(tomtom.AddWaypoint, tomtom, p.mapID, p.x, p.y,
            { title = title, from = "Beast Lore Plus", persistent = false, crazy = true, silent = true })
        if ok then tomtomUid = uid arrow = true end
    end
    return pinned, arrow
end

local function openMap(mapID)
    if not mapID then return end
    if OpenWorldMap then
        pcall(OpenWorldMap, mapID)
    elseif WorldMapFrame and WorldMapFrame.SetMapID then
        if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
    end
end

function Waypoint.ToBeast(npcId, beast)
    if not mapsAvailable() then
        BLP.Print("map pins are not available on this client.")
        return
    end
    local name = beast and beast.name or ("NPC " .. tostring(npcId))
    local points = questiePoints(npcId)
    if #points == 0 then points = seenPoints(npcId) end
    local p = nearest(points)
    if not p then
        local zone = beast and beast.zones and beast.zones[1]
        local mapID = Waypoint.MapIdByName(zone)
        BLP.Print(("no exact spot known for %s%s. Opening the map%s. (With Questie installed, pins use its spawn data.)"):format(
            name, zone and (" in " .. zone) or "", zone and (" on " .. zone) or ""))
        openMap(mapID)
        return
    end
    local info = C_Map.GetMapInfo(p.mapID)
    local zoneName = info and BLP.Plain(info.name) or "?"
    local pinned, arrow = setPin(p, name)
    local how = {}
    if pinned then how[#how + 1] = "map pin" end
    if arrow then how[#how + 1] = "TomTom arrow" end
    BLP.Print(("%s: %s %.1f, %.1f (%s)%s"):format(name, zoneName, p.x * 100, p.y * 100, p.source,
        #how > 0 and (" \226\128\148 " .. table.concat(how, " + ") .. " set") or " \226\128\148 could not place a pin here"))
end

---------------------------------------------------------------------------
-- Remember where known beasts were seen (fallback when Questie is not installed)
---------------------------------------------------------------------------
local function onTargetChanged()
    local npcId = BLP.NpcIdFromGUID(BLP.SafeUnitGUID("target"))
    if not npcId or not BLP.Beasts[npcId] or not mapsAvailable() then return end
    local mapID = BLP.Plain(C_Map.GetBestMapForUnit("player"))
    local pos = mapID and C_Map.GetPlayerMapPosition and BLP.Plain(C_Map.GetPlayerMapPosition(mapID, "player"))
    if not pos then return end
    local seen = BLP.db.seen
    if not seen[npcId] then
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        if n >= MAX_SEEN then return end
    end
    seen[npcId] = { m = mapID, x = math.floor(pos.x * 1000 + 0.5) / 1000, y = math.floor(pos.y * 1000 + 0.5) / 1000 }
end

BLP.OnInit(function()
    if type(BLP.db.seen) ~= "table" then BLP.db.seen = {} end
    BLP.On("PLAYER_TARGET_CHANGED", onTargetChanged)
end)
