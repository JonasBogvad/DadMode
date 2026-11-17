-- DadMode: the /dadmode and /dad commands

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_DADMODE1 = "/dadmode"
SlashCmdList["DADMODE"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        ns.OpenPicker(ns.db.helper)
    elseif msg == "off" then
        ns.db.enabled = false
        ns.Print("Arrows off. /dadmode on brings them back.")
    elseif msg == "on" then
        ns.db.enabled = true
        ns.Print("Arrows on.")
    elseif msg == "alerts" then
        ns.db.alerts = not ns.db.alerts
        if ns.RefreshPicker then ns.RefreshPicker() end
        ns.Print(ns.db.alerts and "You will see pings." or "You will not see pings.")
    elseif msg == "follow" then
        ns.db.follow = not ns.db.follow
        ns.Print(ns.db.follow and "Follow button on." or "Follow button off.")
    elseif msg == "waypoint" then
        ns.SendWaypoint()
    elseif msg == "stop" or msg:sub(1, 5) == "stop " then
        ns.RecordStop(msg:sub(6))
    elseif msg == "travel" then
        pcall(ns.ResolveStops)
        ns.Print("Zeppelin platforms and boat docks this computer knows:")
        for _, key in ipairs(ns.STOP_ORDER) do
            local stop, p = ns.STOPS[key], ns.db.stops and ns.db.stops[key]
            ns.Print("  " .. ns.Ride(stop) .. " " .. stop.at .. " to " .. stop.to .. (stop.who and (" (" .. stop.who .. ")") or "") .. ": "
                .. (p and ((p.manual and "|cff6fcf97recorded by a guide|r" or p.approx and "|cffe8c36arough, the town only|r" or "|cff6fcf97known|r")
                    .. "  continent " .. p.cont .. ", " .. p.n .. ", " .. p.w) or "|cffeb7a7aunknown|r"))
        end
        local pn, pw, pc = ns.WorldPos("player")
        ns.Print("You: " .. (pn and ("continent " .. pc .. ", " .. math.floor(pn) .. ", " .. math.floor(pw)) or "no position here"))
        if ns.db.waypoint then
            local key = ns.TravelStep(ns.db.waypoint)
            ns.Print("Marker: " .. (key == nil and "walk straight to it" or key == "unknown" and "another continent, no platform known"
                or ("first the " .. ns.Ride(ns.STOPS[key]) .. " from " .. ns.STOPS[key].at .. " to " .. ns.STOPS[key].to)))
        end
    elseif msg == "minimap" then
        ns.ToggleMinimapButton()
    elseif msg == "quests" then
        ns.OpenQuests()
    elseif msg == "debug" then
        local function Try(f, ...)
            local ok, a, b = pcall(f, ...)
            return ok and (tostring(a) .. (b and b ~= "" and (" / " .. tostring(b)) or "")) or "error"
        end
        ns.Print("Me: UnitName=" .. Try(UnitName, "player") .. "  GetUnitName=" .. (GetUnitName and Try(GetUnitName, "player", true) or "n/a"))
        for _, m in ipairs(ns.Party()) do
            ns.Print(m.unit .. ": UnitName=" .. Try(UnitName, m.unit) .. "  GetUnitName=" .. (GetUnitName and Try(GetUnitName, m.unit, true) or "n/a") .. "  key=" .. tostring(m.key))
        end
        ns.Print("Last call heard: " .. (ns.lastHeard or "none since login"))
    elseif msg == "status" then
        local names = {}
        for _, m in ipairs(ns.Party()) do names[#names + 1] = m.name end
        ns.Print("DadMode " .. ns.VERSION .. ". Role: " .. (ns.db.helper and "guide" or "being guided") .. ". I show calls: " .. (ns.db.alerts and "yes" or "no")
            .. ". Party: " .. (#names > 0 and table.concat(names, ", ") or "nobody"))
        if DadMode_VersionLines and #names > 0 then
            pcall(DadMode_AskVersions)
            for _, line in ipairs(DadMode_VersionLines()) do ns.Print("  " .. line) end
            ns.Print("  Type it again in a few seconds if someone just joined.")
        end
    elseif msg == "clear" then
        ns.Dismiss()
    elseif msg == "resetsize" then
        ns.ResetSizes()
    elseif msg == "settings" or msg == "options" then
        DadMode_OpenSettings()
    elseif msg == "testbox" then
        if DadMode_TestBox then DadMode_TestBox() end
    elseif msg == "guides" then
        if DadMode_OpenGuides then DadMode_OpenGuides(true) end
    elseif msg == "role" then
        if ns.roleWin then ns.roleWin:Show() end
    elseif msg == "helper" or msg == "guide" then
        ns.ToggleHelper()
    elseif msg == "test" then
        ns.TestCall()
    else
        ns.Print("/dadmode (pick people), /dadmode settings, /dadmode follow (follow button on or off), /dadmode status, /dadmode clear (remove a ping), /dadmode role (guide or being guided), /dadmode on, /dadmode off, /dadmode alerts, /dadmode test, /dad (ping the party)")
    end
end

SLASH_DADPING1 = "/dad"
SlashCmdList["DADPING"] = function(msg)
    ns.SendPing(msg)
end
