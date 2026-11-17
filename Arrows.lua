-- DadMode: the arrows to picked party members and to the marker

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Arrows
---------------------------------------------------------------------------

local function GetSlot(i)
    local s = ns.slots[i]
    if s then return s end
    s = CreateFrame("Frame", nil, ns.bar)
    s:SetSize(150, 150)
    s.arrow = s:CreateTexture(nil, "ARTWORK")
    s.arrow:SetTexture(ns.ARROW)
    s.arrow:SetSize(96, 96)
    s.arrow:SetPoint("TOP", 0, 0)
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.name:SetPoint("TOP", s.arrow, "BOTTOM", 0, -2)
    s.dist = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.dist:SetPoint("TOP", s.name, "BOTTOM", 0, -2)
    pcall(function()
        local font, _, flags = s.dist:GetFont()
        if font then s.dist:SetFont(font, 22, flags or "OUTLINE") end
    end)
    -- Used in dungeons, where there is no arrow: only "close by" or "too far"
    s.near = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.near:SetPoint("TOP", s.name, "BOTTOM", 0, -2)
    s.near:SetText("|cff1aff1aclose by|r")
    s.far = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.far:SetPoint("TOP", s.name, "BOTTOM", 0, -2)
    s.far:SetText("|cffff4d4dTOO FAR AWAY|r")
    s.near:Hide()
    s.far:Hide()
    ns.slots[i] = s
    return s
end

local function Shown()
    -- marked party members, plus anyone who just pinged
    local list, now = {}, GetTime()
    for _, m in ipairs(ns.Party()) do
        if ns.db.marked[m.name] or (ns.pings[m.name] and ns.pings[m.name] > now) then
            list[#list + 1] = m
        end
    end
    return list
end

-- In a dungeon the game hides positions, but it still says whether a party member is within
-- about 40 yards. That answer can be a "secret" value addons may not read, only hand to the game
-- to show or hide something. So two labels are stacked and the game picks which one is visible.
-- Returns true when the labels are in use.
function DadMode_ShowRange(s, unit)
    local ok, inRange = pcall(UnitInRange, unit)
    if not ok then return false end
    if ns.Secret(inRange) then
        if not s.near.SetAlphaFromBoolean then return false end
        local a = pcall(s.near.SetAlphaFromBoolean, s.near, inRange, 1, 0)
        local b = pcall(s.far.SetAlphaFromBoolean, s.far, inRange, 0, 1)
        if not (a and b) then return false end
    elseif type(inRange) == "boolean" then
        s.near:SetAlpha(inRange and 1 or 0)
        s.far:SetAlpha(inRange and 0 or 1)
    else
        return false
    end
    s.near:Show()
    s.far:Show()
    return true
end

-- The name of the zone a party member is in, when it is another zone than mine. nil when it is
-- the same zone or the game does not say. Looked up at most once a second for each person.
local zoneSeen = {}
local function OtherZone(unit, now)
    local seen = zoneSeen[unit]
    if seen and now - seen.at < 1 then return seen.name end
    local name
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local okA, mine = pcall(C_Map.GetBestMapForUnit, "player")
        local okB, theirs = pcall(C_Map.GetBestMapForUnit, unit)
        if okA and okB and ns.Usable(mine, "number") and ns.Usable(theirs, "number") and mine ~= theirs then
            local okI, info = pcall(C_Map.GetMapInfo, theirs)
            if okI and type(info) == "table" and ns.Usable(info.name, "string") and info.name ~= "" then name = info.name end
        end
    end
    zoneSeen[unit] = { at = now, name = name }
    return name
end
DadMode_OtherZone = OtherZone        -- for testing

local function UpdateArrows()
    local list = ns.db.enabled and Shown() or {}
    local now = GetTime()
    local n = #list
    local base = ns.ArrowBase()
    local step = base + 64               -- room for one arrow with its name and distance
    ns.bar:SetWidth(math.max(n, 1) * step)
    local worstFar

    for i, m in ipairs(list) do
        local s = GetSlot(i)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", ns.bar, "TOPLEFT", (i - 1) * step, 0)
        s:SetWidth(step)
        s.name:SetText(m.name)

        local pinging = ns.pings[m.name] and ns.pings[m.name] > now
        local size = pinging and (base * 1.17 + base * 0.17 * math.sin(now * 8)) or base
        s.arrow:SetSize(size, size)

        local okC, connected = pcall(UnitIsConnected, m.unit)
        local dist, angle = ns.Locate(m.unit)
        s.near:Hide()
        s.far:Hide()
        if pinging and dist and dist < ns.ARRIVED then
            -- he made it: stop the ping and tell the helper
            ns.pings[m.name] = nil
            pinging = false
            if ns.alertFrame.from == m.name or not ns.alertFrame:IsShown() then
                ns.ShowAlert("|cff1aff1aYou found " .. m.name .. "|r", 2)
            end
            ns.Tell("HERE")
        end
        if okC and connected == false then
            s.arrow:Hide()
            s.dist:SetText("|cff9aa0a6offline|r")
            ns.farSince[m.name] = nil
        elseif not dist then
            s.arrow:Hide()
            local why = angle
            if why == "dungeon" and DadMode_ShowRange(s, m.unit) then
                s.dist:SetText("")
            else
                s.dist:SetText(why == "dungeon" and "|cff9aa0a6no arrows in here|r"
                    or why == "elsewhere" and "|cffff4d4dfar away|r" or "|cff9aa0a6?|r")
            end
            ns.farSince[m.name] = nil
        else
            local r, g, b = 0.44, 0.81, 0.59                      -- green
            if dist > ns.FAR then r, g, b = 0.92, 0.48, 0.48         -- red
            elseif dist > ns.NEAR then r, g, b = 0.91, 0.76, 0.42 end -- yellow
            -- far away and in another zone: they are doing something else on purpose. A grey arrow
            -- that says where they are, and no warning. A call still turns the arrow white.
            local zone = (dist > ns.FAR and not pinging) and OtherZone(m.unit, now) or nil
            if zone then r, g, b = 0.55, 0.57, 0.60 end
            if pinging then r, g, b = 1, 1, 1 end
            if angle then
                s.arrow:SetRotation(angle)
                s.arrow:SetVertexColor(r, g, b)
                s.arrow:Show()
            else
                s.arrow:Hide()
            end
            s.dist:SetText(zone and ("in " .. zone) or (math.floor(dist + 0.5) .. " yd"))
            s.dist:SetTextColor(r, g, b)

            if dist > ns.FAR and ns.db.marked[m.name] and not zone then
                ns.farSince[m.name] = ns.farSince[m.name] or now
                if now - ns.farSince[m.name] > 4 then worstFar = worstFar or m.name end
            else
                ns.farSince[m.name] = nil
                ns.farBeeped[m.name] = nil      -- back in range: the next time away may sound again
            end
        end
        s:Show()
    end
    -- The marker a helper put on the map: a red pulsing arrow of its own
    local wp = ns.db.enabled and ns.db.waypoint or nil
    if wp then
        n = n + 1
        ns.bar:SetWidth(n * step)
        local s = GetSlot(n)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", ns.bar, "TOPLEFT", (n - 1) * step, 0)
        s:SetWidth(step)
        s.near:Hide()
        s.far:Hide()
        local size = base * 1.08 + base * 0.15 * math.sin(now * 6)
        s.arrow:SetSize(size, size)
        local stepKey = DadMode_CurrentStep(wp, now)
        local platform = stepKey and ns.db.stops[stepKey]
        local dist, angle
        if platform then
            s.name:SetText(ns.STOPS[stepKey].boat and "|cffff4d4dBOAT|r" or "|cffff4d4dZEPPELIN|r")
            dist, angle = ns.LocatePoint(platform.n, platform.w, platform.cont)
        else
            s.name:SetText("|cffff4d4dMARKER|r")
            dist, angle = ns.LocatePoint(wp.n, wp.w, wp.cont)
        end
        if platform and platform.approx and dist and dist < 40 then
            -- a rough spot: he is in the right town, the dock he has to find himself
            s.arrow:Hide()
            s.dist:SetText("|cff1aff1ago to the dock|r")
            if not ns.travel.onPlatform then
                ns.travel.onPlatform = true
                ns.ShowAlert("|cff1aff1aYou are in " .. ns.STOPS[stepKey].at .. ".|r\nGo to the dock and wait for the boat to " .. ns.STOPS[stepKey].to .. ".", 10)
            end
        elseif platform and dist and dist < 15 then
            -- on the platform: stay, and say so once
            s.arrow:Hide()
            s.dist:SetText("|cff1aff1await here|r")
            if not ns.travel.onPlatform then
                ns.travel.onPlatform = true
                ns.ShowAlert(ns.STOPS[stepKey].boat and ("|cff1aff1aRight dock.|r\nWait here for the boat to " .. ns.STOPS[stepKey].to .. ".")
                    or ("|cff1aff1aRight platform.|r\nWait here for the zeppelin to " .. ns.STOPS[stepKey].to .. "."), 8)
            end
        elseif platform and dist then
            ns.travel.onPlatform = false
            if angle then
                s.arrow:SetRotation(angle)
                local glow = 0.75 + 0.25 * math.sin(now * 6)
                s.arrow:SetVertexColor(1, 0.25 * glow, 0.25 * glow)
                s.arrow:Show()
            else
                s.arrow:Hide()
            end
            s.dist:SetText("to " .. ns.STOPS[stepKey].to .. "  " .. math.floor(dist + 0.5) .. " yd")
            s.dist:SetTextColor(1, 0.35, 0.35)
        elseif dist and dist < 15 then
            ns.db.waypoint = nil
            if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
            ns.ShowAlert("|cff1aff1aYou reached the marker|r", 3)
            ns.Tell("WPHERE")
        elseif dist then
            if angle then
                s.arrow:SetRotation(angle)
                local glow = 0.75 + 0.25 * math.sin(now * 6)
                s.arrow:SetVertexColor(1, 0.25 * glow, 0.25 * glow)
                s.arrow:Show()
            else
                s.arrow:Hide()
            end
            s.dist:SetText(math.floor(dist + 0.5) .. " yd")
            s.dist:SetTextColor(1, 0.35, 0.35)
        else
            s.arrow:Hide()
            s.dist:SetText(angle == "elsewhere" and "|cffff4d4don another continent|r" or "|cffff4d4dopen your map|r")
        end
        s:Show()
    end
    for i = n + 1, #ns.slots do ns.slots[i]:Hide() end

    if n == 0 and not ns.moving then ns.bar:Hide() else ns.bar:Show() end
    ns.bar.hint:SetShown(ns.moving)

    -- no far warning while someone is calling him: one thing at a time
    local calling = false
    for _, untilTime in pairs(ns.pings) do
        if untilTime > now then calling = true end
    end
    -- One sound and one message each time he drifts away. Nothing more until he has been back.
    if worstFar and ns.db.farWarning and not calling and not ns.farBeeped[worstFar] then
        ns.farBeeped[worstFar] = true
        ns.Beep("far")
        ns.ShowAlert("|cffff4d4dYou are far from " .. worstFar .. "|r\nFollow the arrow", 5)
    end
end

-- used by other files of DadMode
ns.UpdateArrows = UpdateArrows
