-- DadMode: a guide puts a marker on the map of the one being guided

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Waypoints: a helper puts a marker on dad's map
---------------------------------------------------------------------------
-- Helper sends WP:<map>:<x>:<y>. Dad's addon sets the game's own map pin there and tracks it,
-- then answers WPOK or WPNO. WPC removes it again.

-- Helper's side: my own map pin if I have one, otherwise the spot where I stand
local function SendWaypoint()
    local M = C_Map
    if not M then return ns.Print("This game version has no map pins.") end
    local mapID, x, y, what
    if M.HasUserWaypoint and M.GetUserWaypoint then
        local okH, has = pcall(M.HasUserWaypoint)
        if okH and has == true then
            local okP, point = pcall(M.GetUserWaypoint)
            if okP and type(point) == "table" and ns.Usable(point.uiMapID, "number") then
                local px, py = ns.XY(point.position)
                if px then mapID, x, y, what = point.uiMapID, px, py, "your own map pin" end
            end
        end
    end
    if not mapID and M.GetBestMapForUnit and M.GetPlayerMapPosition then
        local okM, id = pcall(M.GetBestMapForUnit, "player")
        if okM and ns.Usable(id, "number") then
            local okP, pos = pcall(M.GetPlayerMapPosition, id, "player")
            local px, py = ns.XY(okP and pos or nil)
            if px then mapID, x, y, what = id, px, py, "the spot where you stand" end
        end
    end
    if not mapID then
        ns.Print("|cffff4d4dNo position to send.|r That happens in dungeons. Outdoors it works.")
        return
    end
    local ok, why = ns.Tell(DadMode_Aim(("WP:%d:%.4f:%.4f"):format(mapID, x, y)))
    if ok then
        ns.lastSent = GetTime()
        ns.wpOut = true
        ns.Print("Waypoint sent: " .. what .. ".")
        pcall(ns.ResolveStops)
        for _, body in ipairs(DadMode_PackStops()) do ns.Queue(body) end
        ns.PumpOutbox()
    else
        ns.Print("|cffff4d4dWaypoint not sent:|r " .. tostring(why))
    end
end

local function SendWaypointClear()
    ns.Tell(DadMode_Aim("WPC"))
    ns.wpOut = false
    ns.Print("Asked to remove the waypoint.")
end

-- Dad's side
DadMode_SendWaypoint, DadMode_SendWaypointClear = SendWaypoint, SendWaypointClear

function DadMode_ReceiveWaypoint(sender, text)
    local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
    if not m then return end
    if not ns.db.alerts then
        ns.Tell("MUTED")
        return
    end
    local M = C_Map
    if text == "WPC" then
        if M and M.ClearUserWaypoint then pcall(M.ClearUserWaypoint) end
        ns.db.waypoint = nil
        return
    end
    local mapID, x, y = text:match("^WP:(%d+):([%d%.]+):([%d%.]+)$")
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    local done = false
    if mapID and x and y and M and M.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local allowed = true
        if M.CanSetUserWaypointOnMap then
            local okC, can = pcall(M.CanSetUserWaypointOnMap, mapID)
            allowed = okC and can == true
        end
        if allowed then
            done = pcall(function()
                M.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                end
            end)
        end
    end
    if done then
        local wn, ww, wcont = ns.MapToWorld(mapID, x, y)
        ns.db.waypoint = { map = mapID, x = x, y = y, n = wn, w = ww, cont = wcont, from = m.name }
        ns.travel.key, ns.travel.at, ns.travel.onPlatform = nil, GetTime() - 1, false     -- route is worked out a second later
        ns.Beep("call")
        ns.ShowAlert("|cffffd100" .. m.name .. "|r put a marker on your map\n|cffff4d4dFollow the red arrow|r", 8)
        ns.alertFrame.from = m.name
        ns.Tell("WPOK")
    else
        ns.Tell("WPNO")
    end
end

-- used by other files of DadMode
ns.SendWaypoint = SendWaypoint
