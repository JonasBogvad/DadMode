-- DadMode: which zeppelin or boat to take when the marker is far away

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Travel: which zeppelin to take when the marker is far away
---------------------------------------------------------------------------

-- Each platform of a zeppelin tower, named after where it is and where it goes. A zeppelin
-- master stands on every platform, and Questie knows where they stand, so that is how the
-- platform's spot is found. The sides are the classic ones; the master's name is the sure sign.
local STOPS = {
    ORG_UC   = { npc = 9564,  who = "Frezza",            at = "Orgrimmar", to = "Undercity", side = "south side" },
    ORG_GROM = { npc = 12136, who = "Snurk Bucksquick",  at = "Orgrimmar", to = "Grom'gol",  side = "north side" },
    UC_ORG   = { npc = 9566,  who = "Zapetta",           at = "Undercity", to = "Orgrimmar", side = "west side" },
    UC_GROM  = { npc = 3150,  who = "Hin Denburg",       at = "Undercity", to = "Grom'gol",  side = "east side" },
    GROM_ORG = { npc = 3149,  who = "Nez'raz",           at = "Grom'gol",  to = "Orgrimmar", side = "side over the water" },
    GROM_UC  = { npc = 12137, who = "Squibby Overspeck", at = "Grom'gol",  to = "Undercity", side = "side away from the water" },
    -- Boats. Nobody that Questie knows stands on a dock. For Ratchet and Booty Bay the town's
    -- flight master is used as a rough spot (wowforever.be flight path guide): the arrow leads to
    -- the town and the text sends him to the dock. A guide can record the exact dock with
    -- /dadmode stop <NAME>. The new Forever ports have no published spot at all.
    RATCHET_BB   = { boat = true, at = "Ratchet", to = "Booty Bay", near = { zone = "The Barrens", area = 17, x = 0.630, y = 0.372 } },
    BB_RATCHET   = { boat = true, at = "Booty Bay", to = "Ratchet", near = { zone = "Stranglethorn Vale", area = 33, x = 0.268, y = 0.770 } },
    STEAM_POWDER = { boat = true, at = "Steamwheedle Port", to = "Powderfuse Port" },
    POWDER_STEAM = { boat = true, at = "Powderfuse Port", to = "Steamwheedle Port" },
    ZEPHRAS_SKY  = { boat = true, at = "Zephras Isle", to = "Skywatcher Plateau" },
    SKY_ZEPHRAS  = { boat = true, at = "Skywatcher Plateau", to = "Zephras Isle" },
}
local LINKS = { { "ORG_UC", "UC_ORG" }, { "ORG_GROM", "GROM_ORG" }, { "UC_GROM", "GROM_UC" },
    { "RATCHET_BB", "BB_RATCHET" }, { "STEAM_POWDER", "POWDER_STEAM" }, { "ZEPHRAS_SKY", "SKY_ZEPHRAS" } }
local STOP_ORDER = { "ORG_UC", "ORG_GROM", "UC_ORG", "UC_GROM", "GROM_ORG", "GROM_UC",
    "RATCHET_BB", "BB_RATCHET", "STEAM_POWDER", "POWDER_STEAM", "ZEPHRAS_SKY", "SKY_ZEPHRAS" }

-- "zeppelin" or "boat"
local function Ride(stop) return stop.boat and "boat" or "zeppelin" end
local ZEPPELIN_COST = 400       -- a ride counts as this many yards of walking
local ZEPPELIN_GAIN = 0.6       -- only suggested when the trip gets this much shorter

-- The game's map number for a zone, found by its name
local mapByName = {}
function DadMode_FindMap(name)
    if mapByName[name] then return mapByName[name] end
    local M = C_Map
    if not (M and M.GetMapInfo and M.GetMapChildrenInfo and M.GetBestMapForUnit) then return nil end
    local ok, id = pcall(M.GetBestMapForUnit, "player")
    if not ok or not ns.Usable(id, "number") then return nil end
    -- climb to the top of the map tree, then look through everything below it
    for _ = 1, 8 do
        local okI, info = pcall(M.GetMapInfo, id)
        local parent = okI and type(info) == "table" and info.parentMapID
        if type(parent) ~= "number" or parent <= 0 then break end
        id = parent
    end
    local okC, kids = pcall(M.GetMapChildrenInfo, id, nil, true)
    if okC and type(kids) == "table" then
        for _, kid in ipairs(kids) do
            if type(kid) == "table" and kid.name == name and type(kid.mapID) == "number" then
                mapByName[name] = kid.mapID
                return kid.mapID
            end
        end
    end
    return nil
end

-- Looks up the platforms in Questie, if this computer has it. Found spots are remembered.
local function ResolveStops()
    ns.db.stops = ns.db.stops or {}
    local missing = false
    for key in pairs(STOPS) do
        if not ns.db.stops[key] then missing = true end
    end
    if not missing then return end
    -- rough spots first: they need no Questie, only the zone's map
    for key, stop in pairs(STOPS) do
        if stop.near and not ns.db.stops[key] then
            local mapID = DadMode_FindMap(stop.near.zone)
            if not mapID and type(QuestieLoader) == "table" and type(QuestieLoader.ImportModule) == "function" then
                local okZ, ZDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
                if okZ and type(ZDB) == "table" and type(ZDB.GetUiMapIdByAreaId) == "function" then
                    local okM, id = pcall(ZDB.GetUiMapIdByAreaId, ZDB, stop.near.area)
                    if okM and type(id) == "number" then mapID = id end
                end
            end
            if mapID then
                local n, w, cont = ns.MapToWorld(mapID, stop.near.x, stop.near.y)
                if n then ns.db.stops[key] = { cont = cont, n = math.floor(n + 0.5), w = math.floor(w + 0.5), approx = true } end
            end
        end
    end
    if type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return end
    local ok, QDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    local okZ, ZDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    if not ok or type(QDB) ~= "table" or type(QDB.QueryNPCSingle) ~= "function" then return end
    if not okZ or type(ZDB) ~= "table" or type(ZDB.GetUiMapIdByAreaId) ~= "function" then return end
    for key, stop in pairs(STOPS) do
        if not ns.db.stops[key] and stop.npc then
            local okN, name = pcall(QDB.QueryNPCSingle, stop.npc, "name")
            local okS, spawns = pcall(QDB.QueryNPCSingle, stop.npc, "spawns")
            -- the name has to match: Forever may use a number for somebody else
            if stop.npc and okN and name == stop.who and okS and type(spawns) == "table" then
                for areaId, list in pairs(spawns) do
                    local first = type(list) == "table" and list[1]
                    if not ns.db.stops[key] and type(first) == "table" and type(first[1]) == "number" and type(first[2]) == "number" then
                        local okM, mapID = pcall(ZDB.GetUiMapIdByAreaId, ZDB, areaId)
                        if okM and type(mapID) == "number" then
                            local n, w, cont = ns.MapToWorld(mapID, first[1] / 100, first[2] / 100)
                            if n then ns.db.stops[key] = { cont = cont, n = math.floor(n + 0.5), w = math.floor(w + 0.5) } end
                        end
                    end
                end
            end
        end
    end
end

-- The stops this computer knows, packed for sending to the one being guided. Several
-- messages when there are many. A spot a guide recorded by hand is marked with "!" and wins
-- over a looked-up one on the other side.
function DadMode_PackStops()
    local msgs, cur = {}, ""
    for _, key in ipairs(STOP_ORDER) do
        local p = ns.db.stops and ns.db.stops[key]
        if p then
            local part = key .. (p.manual and "!" or p.approx and "?" or "") .. "=" .. p.cont .. ":" .. p.n .. ":" .. p.w
            if cur ~= "" and #cur + #part + 1 > 230 then
                msgs[#msgs + 1] = "TS:" .. cur
                cur = ""
            end
            cur = (cur == "" and "" or (cur .. "~")) .. part
        end
    end
    if cur ~= "" then msgs[#msgs + 1] = "TS:" .. cur end
    return msgs
end

function DadMode_ReceiveStops(text)
    ns.db.stops = ns.db.stops or {}
    -- "!" = recorded by a guide, "?" = rough (the town, not the dock). Better kinds replace worse.
    local function Rank(p) return (not p and 0) or (p.manual and 3) or (p.approx and 1) or 2 end
    for key, mark, cont, n, w in text:gmatch("([%u_]+)([!?]?)=(%-?%d+):(%-?%d+):(%-?%d+)") do
        local new = { cont = tonumber(cont), n = tonumber(n), w = tonumber(w),
            manual = (mark == "!") or nil, approx = (mark == "?") or nil }
        if STOPS[key] and Rank(new) > Rank(ns.db.stops[key]) then ns.db.stops[key] = new end
    end
end

-- A guide stands on a dock or platform and records the spot
local function RecordStop(key)
    key = tostring(key or ""):upper():gsub("%s+", "")
    if not STOPS[key] then
        ns.Print("Stand on the dock or platform and type /dadmode stop NAME. The names are:")
        for _, k in ipairs(STOP_ORDER) do
            local p = ns.db.stops and ns.db.stops[k]
            ns.Print("  " .. k .. "  (" .. Ride(STOPS[k]) .. " from " .. STOPS[k].at .. " to " .. STOPS[k].to .. ")  "
                .. (p and ((p.approx and "|cffe8c36arough|r") or "|cff6fcf97known|r") or "|cffeb7a7aunknown|r"))
        end
        return
    end
    local n, w, cont = ns.WorldPos("player")
    if not n then
        ns.Print("|cffeb7a7aNo position here.|r That happens in dungeons.")
        return
    end
    ns.db.stops = ns.db.stops or {}
    ns.db.stops[key] = { cont = cont, n = math.floor(n + 0.5), w = math.floor(w + 0.5), manual = true }
    ns.Print("|cff6fcf97Saved:|r the " .. Ride(STOPS[key]) .. " from " .. STOPS[key].at .. " to " .. STOPS[key].to
        .. " leaves from where you stand. It is sent along with your next waypoint.")
end
DadMode_RecordStop = RecordStop

local function Yards(c1, n1, w1, c2, n2, w2)
    if not (n1 and n2) or c1 ~= c2 then return nil end
    return math.sqrt((n1 - n2) ^ 2 + (w1 - w2) ^ 2)
end

-- Which platform should he walk to first? nil = just walk to the marker.
-- "unknown" = the marker is on another continent and no platform spots are known.
local function TravelStep(wp)
    local pn, pw, pc = ns.WorldPos("player")
    if not pn or not wp or not wp.n then return nil end
    local direct = Yards(pc, pn, pw, wp.cont, wp.n, wp.w)
    local best, bestCost
    for _, link in ipairs(LINKS) do
        for dir = 1, 2 do
            local a, b = ns.db.stops and ns.db.stops[link[dir]], ns.db.stops and ns.db.stops[link[3 - dir]]
            if a and b then
                local walk1 = Yards(pc, pn, pw, a.cont, a.n, a.w)
                local walk2 = Yards(b.cont, b.n, b.w, wp.cont, wp.n, wp.w)
                if walk1 and walk2 then
                    local cost = walk1 + walk2 + ZEPPELIN_COST
                    if not bestCost or cost < bestCost then best, bestCost = link[dir], cost end
                end
            end
        end
    end
    if best and (not direct or bestCost < direct * ZEPPELIN_GAIN) then return best end
    if not direct then return "unknown" end
    return nil
end
DadMode_TravelStep = TravelStep

local travel = { key = nil, at = 0, told = nil, onPlatform = false }

-- Called a few times a second while a marker is set. Returns the platform to walk to, if any.
function DadMode_CurrentStep(wp, now)
    if now - travel.at > 2 then
        travel.at = now
        local key = TravelStep(wp)
        if key ~= travel.key then
            local before = travel.key
            travel.key, travel.onPlatform = key, false
            local stop = key and STOPS[key]
            if stop then
                ns.Beep("call")
                if stop.boat then
                    ns.ShowAlert("|cffff5a5aTake the boat to " .. stop.to .. "|r\nIt leaves from the dock at " .. stop.at .. ".", 12)
                else
                    ns.ShowAlert("|cffff5a5aTake the zeppelin to " .. stop.to .. "|r\nGo up the tower at " .. stop.at .. ", "
                        .. stop.side .. ".\n|cff9aa0a6Zeppelin master " .. stop.who .. " stands on the right platform.|r", 12)
                end
            elseif key == "unknown" then
                ns.ShowAlert("|cffff5a5aThe marker is on another continent|r\nTake a zeppelin or a boat. Ask your guide which one.", 10)
            elseif before and before ~= "unknown" then
                ns.ShowAlert("|cff6fcf97You took the " .. ((STOPS[before] and STOPS[before].boat) and "boat" or "zeppelin")
                    .. ".|r\n|cffff5a5aNow follow the red arrow|r", 8)
            end
        end
    end
    return travel.key and STOPS[travel.key] and travel.key or nil
end

-- At a flight master: which flight point he can fly to is closest to where he has to go?
local function FlightHint()
    local wp = ns.db.waypoint
    if not wp or ns.db.helper or not wp.n then return end
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then return end
    local okM, mapID = pcall(GetTaxiMapID)
    if not okM or not ns.Usable(mapID, "number") then return end
    local okN, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not okN or type(nodes) ~= "table" then return end
    -- fly towards the platform when a zeppelin comes first, otherwise towards the marker
    local tc, tn, tw = wp.cont, wp.n, wp.w
    local key = TravelStep(wp)
    local stop = key and ns.db.stops and ns.db.stops[key]
    if stop then tc, tn, tw = stop.cont, stop.n, stop.w end
    local pn, pw, pc = ns.WorldPos("player")
    local here = pn and Yards(pc, pn, pw, tc, tn, tw) or nil
    local reachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable or 1
    local best, bestDist
    for _, node in ipairs(nodes) do
        if type(node) == "table" and node.state == reachable and ns.Usable(node.name, "string") then
            local x, y = ns.XY(node.position)
            if x then
                local n, w, cont = ns.MapToWorld(mapID, x, y)
                local d = n and Yards(cont, n, w, tc, tn, tw)
                if d and (not bestDist or d < bestDist) then best, bestDist = node.name, d end
            end
        end
    end
    -- only worth it when flying gets him clearly closer than he already is
    if best and (not here or bestDist < here * 0.7) then
        ns.ShowAlert("|cffff5a5aFly to: " .. best .. "|r\n|cff9aa0a6That is the flight point closest to where you have to go.|r", 12)
        ns.Print("Fly to: " .. best)
    end
end
DadMode_FlightHint = FlightHint

-- used by other files of DadMode
ns.FlightHint = FlightHint
ns.RecordStop = RecordStop
ns.ResolveStops = ResolveStops
ns.Ride = Ride
ns.STOPS = STOPS
ns.STOP_ORDER = STOP_ORDER
ns.TravelStep = TravelStep
ns.travel = travel
