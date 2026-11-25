-- zones.lua -- the zones of the world map (C_Map), for the zone condition of a
-- buff: where the player is now, every zone and dungeon to pick from, a zone by name.
--
-- A zone is { mapId, name }. Where the player is counts with every map above
-- the current one: a buff chosen for Elwynn Forest is shown in Goldshire (a
-- smaller map inside it) too. Without C_Map the zone is only its name
-- (GetRealZoneText), and names are compared.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Zones = {}
ns.Dataflows.Zones = Zones

local ZONE_MAP_TYPE = 3      -- Enum.UIMapType.Zone
local DUNGEON_MAP_TYPE = 4   -- Enum.UIMapType.Dungeon
local MAX_PARENTS = 10       -- a map has a few maps above it; a loop guard

local allZones = nil   -- every zone and dungeon, read once: the maps do not change

local function HasMapApi()
    return C_Map ~= nil and C_Map.GetBestMapForUnit ~= nil and C_Map.GetMapInfo ~= nil
end

-- the name of a map; nil -- unknown
function Zones.MapName(mapId)
    if not HasMapApi() then
        return nil
    end
    local info = C_Map.GetMapInfo(mapId)
    return info and info.name
end

-- the zone the player is in now: { mapId, name }; mapId nil without C_Map
function Zones.Current()
    local zoneName = GetRealZoneText and GetRealZoneText() or nil
    if not HasMapApi() then
        return { name = zoneName }
    end
    local mapId = C_Map.GetBestMapForUnit("player")
    if not mapId then
        return { name = zoneName }
    end
    -- a small map inside a zone (a town, a cave): the zone itself is what players pick
    local info = C_Map.GetMapInfo(mapId)
    for _ = 1, MAX_PARENTS do
        local isPickable = info == nil or info.mapType == ZONE_MAP_TYPE or info.mapType == DUNGEON_MAP_TYPE
        local parent = info and info.parentMapID and info.parentMapID > 0 and C_Map.GetMapInfo(info.parentMapID)
        if isPickable or not parent then
            break
        end
        info = parent
    end
    if info then
        return { mapId = info.mapID, name = info.name }
    end
    return { mapId = mapId, name = zoneName }
end

-- Where the player is: { mapIds = { [id] = true }, names = { [lower name] = true } }
-- -- the current map and every map above it, the zone name of the client.
function Zones.Here()
    local here = { mapIds = {}, names = {} }
    local zoneName = GetRealZoneText and GetRealZoneText()
    if zoneName and zoneName ~= "" then
        here.names[zoneName:lower()] = true
    end
    if not HasMapApi() then
        return here
    end
    local mapId = C_Map.GetBestMapForUnit("player")
    for _ = 1, MAX_PARENTS do
        if not mapId or mapId <= 0 then
            break
        end
        here.mapIds[mapId] = true
        local info = C_Map.GetMapInfo(mapId)
        if not info then
            break
        end
        if info.name then
            here.names[info.name:lower()] = true
        end
        mapId = info.parentMapID
    end
    return here
end

-- the top map above the player (the world): every zone is under it
local function RootMap()
    local mapId = C_Map.GetBestMapForUnit("player")
    local root = mapId
    for _ = 1, MAX_PARENTS do
        local info = mapId and C_Map.GetMapInfo(mapId)
        if not info or not info.parentMapID or info.parentMapID <= 0 then
            break
        end
        mapId = info.parentMapID
        root = mapId
    end
    return root
end

local function ReadAll()
    local result = {}
    if not (HasMapApi() and C_Map.GetMapChildrenInfo) then
        return result
    end
    local root = RootMap()
    if not root then
        return result
    end
    local seen = {}
    for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
        local isZone = info.mapType == ZONE_MAP_TYPE or info.mapType == DUNGEON_MAP_TYPE
        if isZone and info.name and info.name ~= "" and not seen[info.mapID] then
            seen[info.mapID] = true
            table.insert(result, { mapId = info.mapID, name = info.name })
        end
    end
    table.sort(result, function(a, b)
        return a.name < b.name
    end)
    return result
end

-- every zone and dungeon of the world, by name; empty -- no map API (or not in the world yet)
function Zones.All()
    if allZones and #allZones > 0 then
        return allZones
    end
    local ok, result = pcall(ReadAll)
    if ok then
        allZones = result
    else
        allZones = {}
    end
    return allZones
end

-- A zone from what was typed: "zone:<map id>" (a picked suggestion) or a
-- zone name (any case; the zone the player is in counts too). nil -- unknown.
function Zones.Find(text)
    local mapId = tonumber(text:match("^zone:(%d+)$"))
    if mapId then
        local name = Zones.MapName(mapId)
        if not name then
            return nil
        end
        return { mapId = mapId, name = name }
    end
    local wanted = text:lower()
    for _, zone in ipairs(Zones.All()) do
        if zone.name:lower() == wanted then
            return { mapId = zone.mapId, name = zone.name }
        end
    end
    local current = Zones.Current()
    if current.name and current.name:lower() == wanted then
        return current
    end
    return nil
end

-- whether the player is in one of the zones ({ { mapId, name } })
function Zones.IsHere(zones)
    local here = Zones.Here()
    for _, zone in ipairs(zones) do
        if zone.mapId and here.mapIds[zone.mapId] then
            return true
        end
        if zone.name and here.names[zone.name:lower()] then
            return true
        end
    end
    return false
end
