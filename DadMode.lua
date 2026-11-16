-- DadMode: never lose your party.
--   * Pick people in your party. Each one gets a big arrow that points to them, with the distance.
--   * Green = close, yellow = a bit away, red = far. A sound plays when you drift too far.
--   * Anyone in the party can call you: /dad in the addon, or typing !dad in party chat.
-- Arrows only work outdoors. Inside dungeons the game does not share where players are.

local NEAR, FAR = 40, 110            -- yards: green below NEAR, red above FAR
local FAR_REPEAT = 60                -- seconds between "you are far away" reminders (text only, no sound)
local PING_SECONDS = 10              -- how long the ping text stays on screen
local PING_ARROW = 60                -- how long the arrow keeps pulsing if he has not arrived
local ARRIVED = 12                   -- yards: this close counts as "found them"
local PING_GAP = 3                   -- seconds: a second ping from the same person sooner than this is ignored
local PREFIX = "DADMODE"
local ARROW = "Interface\\AddOns\\DadMode\\Arrow"

local VERSION = "?"
pcall(function()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    VERSION = get and get("DadMode", "Version") or "?"
end)
local peerVersion = {}               -- name -> DadMode version the other person runs

local db

local ARROW_SIZES = { { "Small", 64 }, { "Medium", 96 }, { "Large", 128 } }
local SCALES = { 0.8, 0.9, 1, 1.1, 1.25 }       -- the "Window size" setting
local HELPER_BREAK = 240                        -- guide bar dragged narrower than this: one column
local FOLLOW_RANGE = 30                         -- the follow button only flashes when the caller is this close
local GRIP_MIN, GRIP_MAX = 0.6, 2               -- how small and big a corner drag can make a window
local function ArrowBase()
    return (ARROW_SIZES[db and db.arrowSize or 2] or ARROW_SIZES[2])[2]
end
local bar, picker, alertFrame, helper, followBtn, questWin
local OpenQuests                     -- defined further down
local UpdateFollow                   -- defined further down
local slots = {}
local pings = {}                     -- name -> time the ping ends
local farSince, lastFarWarn = {}, 0
local farBeeped = {}                 -- name -> true once the far sound has played for this time away
local lastPingFrom, lastBeep, lastSent = {}, 0, 0
local answered = true                -- did anyone answer my last call
local wpOut = false      -- guide side: dad has a waypoint from me right now
local call = { state = nil, who = nil, at = 0 }   -- what the helper bar shows about my last call
local moving = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Print(msg)
    print("|cffe8c36aDadMode|r: " .. msg)
end

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Usable(v, kind)
    return v ~= nil and not Secret(v) and (kind == nil or type(v) == kind)
end

local function Short(name)
    if not Usable(name, "string") then return nil end
    if Ambiguate then
        local ok, s = pcall(Ambiguate, name, "short")
        if ok and Usable(s, "string") then return s end
    end
    return (name:match("^([^%-]+)")) or name
end

-- Forever characters have a first name and a surname ("Saqu Off"). Some parts of the game give
-- only the first name, others both, others add the realm. Key() boils any of them down to the
-- first name in lower case, so the same person always matches.
local function Key(name)
    if not Usable(name, "string") then return nil end
    local first = name:match("^%s*([^%s%-]+)")
    return first and first:lower() or nil
end

local lastHeard                      -- what the last incoming call looked like, for /dadmode debug
local lastMutedNote

-- Sounds to choose from. All are the game's own interface sounds.
local SOUNDS = {
    { name = "Soft ding",     kit = "TELL_MESSAGE",        id = 3081 },
    { name = "Map ping",      kit = "MAP_PING",            id = 3175 },
    { name = "Bell",          kit = "AUCTION_WINDOW_OPEN", id = 5274 },
    { name = "Ready check",   kit = "READY_CHECK",         id = 8960 },
    { name = "Horn (loud)",   kit = "RAID_WARNING",        id = 8959 },
    { name = "No sound" },
}
local DEFAULT_SOUND = { call = 4, far = 2 }      -- call: Ready check, far away: Map ping

-- kind is "call" (someone wants you) or "far" (you drifted away)
local function Beep(kind, force)
    kind = kind or "call"
    if not force and GetTime() - lastBeep < 2 then return end      -- never two sounds on top of each other
    lastBeep = GetTime()
    local choice = SOUNDS[(db.sounds and db.sounds[kind]) or DEFAULT_SOUND[kind]] or SOUNDS[1]
    if not choice.id then return end
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT[choice.kit]) or choice.id, "Master")
end

local function Tex(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- Party members: { unit = "party1", name = "Saqu" }
local function Party()
    local list = {}
    for i = 1, 4 do
        local unit = "party" .. i
        local okE, exists = pcall(UnitExists, unit)
        if okE and exists and not Secret(exists) then
            local okN, name, realm = pcall(UnitName, unit)
            name = okN and Short(name)
            if name then
                local full = name
                if Usable(realm, "string") and realm ~= "" then full = name .. "-" .. realm end
                list[#list + 1] = { unit = unit, name = name, full = full, key = Key(name) }
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Where is everybody
---------------------------------------------------------------------------

local function XY(v)
    if type(v) ~= "table" then return nil end
    if type(v.GetXY) == "function" then
        local ok, x, y = pcall(v.GetXY, v)
        if ok and Usable(x, "number") and Usable(y, "number") then return x, y end
    end
    if Usable(v.x, "number") and Usable(v.y, "number") then return v.x, v.y end
end

-- Returns north, west, zoneGroup. nil when the game does not tell (dungeons).
local function WorldPos(unit)
    local ok, n, w, _, inst = pcall(UnitPosition, unit)
    if ok and Usable(n, "number") and Usable(w, "number") and (n ~= 0 or w ~= 0) then
        return n, w, Usable(inst) and inst or 0
    end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return end
    local ok2, mapID = pcall(C_Map.GetBestMapForUnit, unit)
    if not ok2 or not Usable(mapID, "number") then return end
    local ok3, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
    if not ok3 or pos == nil or Secret(pos) then return end
    local ok4, cont, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not ok4 or world == nil or Secret(world) then return end
    local ok5, x, y = pcall(world.GetXY, world)
    if ok5 and Usable(x, "number") and Usable(y, "number") then
        return x, y, Usable(cont) and cont or 0
    end
end

-- A spot on a map (0 to 1 across and down) as north, west, zoneGroup
local function MapToWorld(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or world == nil or Secret(world) then return nil end
    local n, w = XY(world)
    if not n then return nil end
    return n, w, Usable(cont) and cont or 0
end

-- Returns distance in yards and how far to turn the arrow (radians, counter-clockwise) to reach a
-- spot in the world. nil, reason when it can not be worked out.
local function LocatePoint(tn, tw, tz)
    local pn, pw, pz = WorldPos("player")
    if not pn then return nil, "dungeon" end
    if not tn then return nil, "unknown" end
    if pz ~= tz then return nil, "elsewhere" end
    local dn, dw = tn - pn, tw - pw
    local dist = math.sqrt(dn * dn + dw * dw)
    local okF, facing = pcall(GetPlayerFacing)
    if not okF or not Usable(facing, "number") then return dist, nil end
    return dist, math.atan2(dw, dn) - facing
end

local function Locate(unit)
    return LocatePoint(WorldPos(unit))
end
DadMode_Locate = Locate              -- for testing

---------------------------------------------------------------------------
-- Big message in the middle of the screen
---------------------------------------------------------------------------

local function ShowAlert(text, seconds)
    if not alertFrame then return end
    alertFrame.text:SetText(text)
    -- the clickable area is only as big as the text, so it does not block the rest of the screen
    local w = math.min(alertFrame.text:GetStringWidth() or 600, 900)
    local h = alertFrame.text:GetStringHeight() or 40
    alertFrame:SetSize(w + 40, h + 44)
    alertFrame:Show()
    alertFrame.hideAt = GetTime() + (seconds or 5)
    alertFrame.from = nil
end

local REFUSED = {
    [3] = "you are sending too fast", [8] = "you are sending too fast",
    [5] = "you are not in a party", [11] = "the game blocks addon messages right now (dungeon or fight)",
}

-- Returns true when the game accepted the message, otherwise false and the reason
local function Tell(body)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "this game version has no addon messages" end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, body, "PARTY")
    if not ok then return false, tostring(res) end
    if res == nil or res == true or res == 0 then return true end
    if res == false then return false, "the game refused it" end
    return false, REFUSED[res] or ("the game refused it, code " .. tostring(res)), res
end

-- Long answers (quests, gear) go through a queue. The game only lets an addon send a short
-- burst and then about one message a second; anything faster is silently thrown away, which
-- is how quest lists used to arrive cut off.
local outbox = { at = 0, burst = 0, tries = 0 }
local OUT_BURST, OUT_GAP = 6, 1.1

local function PumpOutbox()
    local now = GetTime()
    while outbox[1] and now >= outbox.at do
        local ok, _, code = Tell(outbox[1])
        if ok then
            table.remove(outbox, 1)
            outbox.tries = 0
            outbox.burst = outbox.burst + 1
            if outbox.burst >= OUT_BURST then outbox.at = now + OUT_GAP end     -- burst used up: one at a time
        elseif code == 5 then
            for i = #outbox, 1, -1 do outbox[i] = nil end                          -- not in a party any more
        else
            outbox.tries = outbox.tries + 1
            outbox.at = now + 1.5                                                  -- refused: wait and try again
            if outbox.tries > 12 then
                for i = #outbox, 1, -1 do outbox[i] = nil end
                outbox.tries = 0
            end
        end
    end
    if not outbox[1] and now - outbox.at > 12 then outbox.burst = 0 end            -- quiet for a while: burst is back
end
DadMode_PumpOutbox = PumpOutbox

local function Queue(body)
    if not outbox[1] and GetTime() - outbox.at > 12 then outbox.burst = 0 end
    outbox[#outbox + 1] = body
end

-- Clears the message on screen and stops any pulsing arrow
local function Dismiss()
    for name in pairs(pings) do pings[name] = nil end
    if alertFrame then alertFrame:Hide() end
end

---------------------------------------------------------------------------
-- Arrows
---------------------------------------------------------------------------

local function GetSlot(i)
    local s = slots[i]
    if s then return s end
    s = CreateFrame("Frame", nil, bar)
    s:SetSize(150, 150)
    s.arrow = s:CreateTexture(nil, "ARTWORK")
    s.arrow:SetTexture(ARROW)
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
    s.near:SetText("|cff6fcf97close by|r")
    s.far = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.far:SetPoint("TOP", s.name, "BOTTOM", 0, -2)
    s.far:SetText("|cffeb7a7aTOO FAR AWAY|r")
    s.near:Hide()
    s.far:Hide()
    slots[i] = s
    return s
end

local function Shown()
    -- marked party members, plus anyone who just pinged
    local list, now = {}, GetTime()
    for _, m in ipairs(Party()) do
        if db.marked[m.name] or (pings[m.name] and pings[m.name] > now) then
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
    if Secret(inRange) then
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
    if not ok or not Usable(id, "number") then return nil end
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
    db.stops = db.stops or {}
    local missing = false
    for key in pairs(STOPS) do
        if not db.stops[key] then missing = true end
    end
    if not missing then return end
    -- rough spots first: they need no Questie, only the zone's map
    for key, stop in pairs(STOPS) do
        if stop.near and not db.stops[key] then
            local mapID = DadMode_FindMap(stop.near.zone)
            if not mapID and type(QuestieLoader) == "table" and type(QuestieLoader.ImportModule) == "function" then
                local okZ, ZDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
                if okZ and type(ZDB) == "table" and type(ZDB.GetUiMapIdByAreaId) == "function" then
                    local okM, id = pcall(ZDB.GetUiMapIdByAreaId, ZDB, stop.near.area)
                    if okM and type(id) == "number" then mapID = id end
                end
            end
            if mapID then
                local n, w, cont = MapToWorld(mapID, stop.near.x, stop.near.y)
                if n then db.stops[key] = { cont = cont, n = math.floor(n + 0.5), w = math.floor(w + 0.5), approx = true } end
            end
        end
    end
    if type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return end
    local ok, QDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    local okZ, ZDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    if not ok or type(QDB) ~= "table" or type(QDB.QueryNPCSingle) ~= "function" then return end
    if not okZ or type(ZDB) ~= "table" or type(ZDB.GetUiMapIdByAreaId) ~= "function" then return end
    for key, stop in pairs(STOPS) do
        if not db.stops[key] and stop.npc then
            local okN, name = pcall(QDB.QueryNPCSingle, stop.npc, "name")
            local okS, spawns = pcall(QDB.QueryNPCSingle, stop.npc, "spawns")
            -- the name has to match: Forever may use a number for somebody else
            if stop.npc and okN and name == stop.who and okS and type(spawns) == "table" then
                for areaId, list in pairs(spawns) do
                    local first = type(list) == "table" and list[1]
                    if not db.stops[key] and type(first) == "table" and type(first[1]) == "number" and type(first[2]) == "number" then
                        local okM, mapID = pcall(ZDB.GetUiMapIdByAreaId, ZDB, areaId)
                        if okM and type(mapID) == "number" then
                            local n, w, cont = MapToWorld(mapID, first[1] / 100, first[2] / 100)
                            if n then db.stops[key] = { cont = cont, n = math.floor(n + 0.5), w = math.floor(w + 0.5) } end
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
        local p = db.stops and db.stops[key]
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
    db.stops = db.stops or {}
    -- "!" = recorded by a guide, "?" = rough (the town, not the dock). Better kinds replace worse.
    local function Rank(p) return (not p and 0) or (p.manual and 3) or (p.approx and 1) or 2 end
    for key, mark, cont, n, w in text:gmatch("([%u_]+)([!?]?)=(%-?%d+):(%-?%d+):(%-?%d+)") do
        local new = { cont = tonumber(cont), n = tonumber(n), w = tonumber(w),
            manual = (mark == "!") or nil, approx = (mark == "?") or nil }
        if STOPS[key] and Rank(new) > Rank(db.stops[key]) then db.stops[key] = new end
    end
end

-- A guide stands on a dock or platform and records the spot
local function RecordStop(key)
    key = tostring(key or ""):upper():gsub("%s+", "")
    if not STOPS[key] then
        Print("Stand on the dock or platform and type /dadmode stop NAME. The names are:")
        for _, k in ipairs(STOP_ORDER) do
            local p = db.stops and db.stops[k]
            Print("  " .. k .. "  (" .. Ride(STOPS[k]) .. " from " .. STOPS[k].at .. " to " .. STOPS[k].to .. ")  "
                .. (p and ((p.approx and "|cffe8c36arough|r") or "|cff6fcf97known|r") or "|cffeb7a7aunknown|r"))
        end
        return
    end
    local n, w, cont = WorldPos("player")
    if not n then
        Print("|cffeb7a7aNo position here.|r That happens in dungeons.")
        return
    end
    db.stops = db.stops or {}
    db.stops[key] = { cont = cont, n = math.floor(n + 0.5), w = math.floor(w + 0.5), manual = true }
    Print("|cff6fcf97Saved:|r the " .. Ride(STOPS[key]) .. " from " .. STOPS[key].at .. " to " .. STOPS[key].to
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
    local pn, pw, pc = WorldPos("player")
    if not pn or not wp or not wp.n then return nil end
    local direct = Yards(pc, pn, pw, wp.cont, wp.n, wp.w)
    local best, bestCost
    for _, link in ipairs(LINKS) do
        for dir = 1, 2 do
            local a, b = db.stops and db.stops[link[dir]], db.stops and db.stops[link[3 - dir]]
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
                Beep("call")
                if stop.boat then
                    ShowAlert("|cffff5a5aTake the boat to " .. stop.to .. "|r\nIt leaves from the dock at " .. stop.at .. ".", 12)
                else
                    ShowAlert("|cffff5a5aTake the zeppelin to " .. stop.to .. "|r\nGo up the tower at " .. stop.at .. ", "
                        .. stop.side .. ".\n|cff9aa0a6Zeppelin master " .. stop.who .. " stands on the right platform.|r", 12)
                end
            elseif key == "unknown" then
                ShowAlert("|cffff5a5aThe marker is on another continent|r\nTake a zeppelin or a boat. Ask your guide which one.", 10)
            elseif before and before ~= "unknown" then
                ShowAlert("|cff6fcf97You took the " .. ((STOPS[before] and STOPS[before].boat) and "boat" or "zeppelin")
                    .. ".|r\n|cffff5a5aNow follow the red arrow|r", 8)
            end
        end
    end
    return travel.key and STOPS[travel.key] and travel.key or nil
end

-- At a flight master: which flight point he can fly to is closest to where he has to go?
local function FlightHint()
    local wp = db.waypoint
    if not wp or db.helper or not wp.n then return end
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then return end
    local okM, mapID = pcall(GetTaxiMapID)
    if not okM or not Usable(mapID, "number") then return end
    local okN, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not okN or type(nodes) ~= "table" then return end
    -- fly towards the platform when a zeppelin comes first, otherwise towards the marker
    local tc, tn, tw = wp.cont, wp.n, wp.w
    local key = TravelStep(wp)
    local stop = key and db.stops and db.stops[key]
    if stop then tc, tn, tw = stop.cont, stop.n, stop.w end
    local pn, pw, pc = WorldPos("player")
    local here = pn and Yards(pc, pn, pw, tc, tn, tw) or nil
    local reachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable or 1
    local best, bestDist
    for _, node in ipairs(nodes) do
        if type(node) == "table" and node.state == reachable and Usable(node.name, "string") then
            local x, y = XY(node.position)
            if x then
                local n, w, cont = MapToWorld(mapID, x, y)
                local d = n and Yards(cont, n, w, tc, tn, tw)
                if d and (not bestDist or d < bestDist) then best, bestDist = node.name, d end
            end
        end
    end
    -- only worth it when flying gets him clearly closer than he already is
    if best and (not here or bestDist < here * 0.7) then
        ShowAlert("|cffff5a5aFly to: " .. best .. "|r\n|cff9aa0a6That is the flight point closest to where you have to go.|r", 12)
        Print("Fly to: " .. best)
    end
end
DadMode_FlightHint = FlightHint

local function UpdateArrows()
    local list = db.enabled and Shown() or {}
    local now = GetTime()
    local n = #list
    local base = ArrowBase()
    local step = base + 64               -- room for one arrow with its name and distance
    bar:SetWidth(math.max(n, 1) * step)
    local worstFar

    for i, m in ipairs(list) do
        local s = GetSlot(i)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", bar, "TOPLEFT", (i - 1) * step, 0)
        s:SetWidth(step)
        s.name:SetText(m.name)

        local pinging = pings[m.name] and pings[m.name] > now
        local size = pinging and (base * 1.17 + base * 0.17 * math.sin(now * 8)) or base
        s.arrow:SetSize(size, size)

        local okC, connected = pcall(UnitIsConnected, m.unit)
        local dist, angle = Locate(m.unit)
        s.near:Hide()
        s.far:Hide()
        if pinging and dist and dist < ARRIVED then
            -- he made it: stop the ping and tell the helper
            pings[m.name] = nil
            pinging = false
            if alertFrame.from == m.name or not alertFrame:IsShown() then
                ShowAlert("|cff6fcf97You found " .. m.name .. "|r", 2)
            end
            Tell("HERE")
        end
        if okC and connected == false then
            s.arrow:Hide()
            s.dist:SetText("|cff9aa0a6offline|r")
            farSince[m.name] = nil
        elseif not dist then
            s.arrow:Hide()
            local why = angle
            if why == "dungeon" and DadMode_ShowRange(s, m.unit) then
                s.dist:SetText("")
            else
                s.dist:SetText(why == "dungeon" and "|cff9aa0a6no arrows in here|r"
                    or why == "elsewhere" and "|cffeb7a7afar away|r" or "|cff9aa0a6?|r")
            end
            farSince[m.name] = nil
        else
            local r, g, b = 0.44, 0.81, 0.59                      -- green
            if dist > FAR then r, g, b = 0.92, 0.48, 0.48         -- red
            elseif dist > NEAR then r, g, b = 0.91, 0.76, 0.42 end -- yellow
            if pinging then r, g, b = 1, 1, 1 end
            if angle then
                s.arrow:SetRotation(angle)
                s.arrow:SetVertexColor(r, g, b)
                s.arrow:Show()
            else
                s.arrow:Hide()
            end
            s.dist:SetText(math.floor(dist + 0.5) .. " yd")
            s.dist:SetTextColor(r, g, b)

            if dist > FAR and db.marked[m.name] then
                farSince[m.name] = farSince[m.name] or now
                if now - farSince[m.name] > 4 then worstFar = worstFar or m.name end
            else
                farSince[m.name] = nil
                farBeeped[m.name] = nil      -- back in range: the next time away may sound again
            end
        end
        s:Show()
    end
    -- The marker a helper put on the map: a red pulsing arrow of its own
    local wp = db.enabled and db.waypoint or nil
    if wp then
        n = n + 1
        bar:SetWidth(n * step)
        local s = GetSlot(n)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", bar, "TOPLEFT", (n - 1) * step, 0)
        s:SetWidth(step)
        s.near:Hide()
        s.far:Hide()
        local size = base * 1.08 + base * 0.15 * math.sin(now * 6)
        s.arrow:SetSize(size, size)
        local stepKey = DadMode_CurrentStep(wp, now)
        local platform = stepKey and db.stops[stepKey]
        local dist, angle
        if platform then
            s.name:SetText(STOPS[stepKey].boat and "|cffff5a5aBOAT|r" or "|cffff5a5aZEPPELIN|r")
            dist, angle = LocatePoint(platform.n, platform.w, platform.cont)
        else
            s.name:SetText("|cffff5a5aMARKER|r")
            dist, angle = LocatePoint(wp.n, wp.w, wp.cont)
        end
        if platform and platform.approx and dist and dist < 40 then
            -- a rough spot: he is in the right town, the dock he has to find himself
            s.arrow:Hide()
            s.dist:SetText("|cff6fcf97go to the dock|r")
            if not travel.onPlatform then
                travel.onPlatform = true
                ShowAlert("|cff6fcf97You are in " .. STOPS[stepKey].at .. ".|r\nGo to the dock and wait for the boat to " .. STOPS[stepKey].to .. ".", 10)
            end
        elseif platform and dist and dist < 15 then
            -- on the platform: stay, and say so once
            s.arrow:Hide()
            s.dist:SetText("|cff6fcf97wait here|r")
            if not travel.onPlatform then
                travel.onPlatform = true
                ShowAlert(STOPS[stepKey].boat and ("|cff6fcf97Right dock.|r\nWait here for the boat to " .. STOPS[stepKey].to .. ".")
                    or ("|cff6fcf97Right platform.|r\nWait here for the zeppelin to " .. STOPS[stepKey].to .. "."), 8)
            end
        elseif platform and dist then
            travel.onPlatform = false
            if angle then
                s.arrow:SetRotation(angle)
                local glow = 0.75 + 0.25 * math.sin(now * 6)
                s.arrow:SetVertexColor(1, 0.25 * glow, 0.25 * glow)
                s.arrow:Show()
            else
                s.arrow:Hide()
            end
            s.dist:SetText("to " .. STOPS[stepKey].to .. "  " .. math.floor(dist + 0.5) .. " yd")
            s.dist:SetTextColor(1, 0.35, 0.35)
        elseif dist and dist < 15 then
            db.waypoint = nil
            if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
            ShowAlert("|cff6fcf97You reached the marker|r", 3)
            Tell("WPHERE")
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
            s.dist:SetText(angle == "elsewhere" and "|cffff5a5aon another continent|r" or "|cffff5a5aopen your map|r")
        end
        s:Show()
    end
    for i = n + 1, #slots do slots[i]:Hide() end

    if n == 0 and not moving then bar:Hide() else bar:Show() end
    bar.hint:SetShown(moving)

    -- no far warning while someone is calling him: one thing at a time
    local calling = false
    for _, untilTime in pairs(pings) do
        if untilTime > now then calling = true end
    end
    -- The sound plays once each time he drifts away. After that only the text comes back, once a minute.
    if worstFar and db.farWarning and not calling and (not farBeeped[worstFar] or now - lastFarWarn > FAR_REPEAT) then
        lastFarWarn = now
        if not farBeeped[worstFar] then
            farBeeped[worstFar] = true
            Beep("far")
        end
        ShowAlert("|cffeb7a7aYou are far from " .. worstFar .. "|r\nFollow the arrow", 5)
    end
end

---------------------------------------------------------------------------
-- Pings: "look here"
---------------------------------------------------------------------------

-- The party member a sender string belongs to, or nil
local function Member(sender)
    local key = Key(sender)
    if not key then return nil end
    for _, m in ipairs(Party()) do
        if m.key == key then return m end
    end
end

local function IsMe(sender)
    local ok, me = pcall(UnitName, "player")
    return ok and Key(me) ~= nil and Key(me) == Key(sender)
end

local function ReceivePing(sender, text)
    local m = (not IsMe(sender)) and Member(sender) or nil
    lastHeard = tostring(sender) .. " -> " .. (IsMe(sender) and "that is me" or m and ("matched " .. m.name) or "NOT in my party list")
    if not m then return end
    sender = m.name
    if not db.alerts then
        Tell("MUTED")                -- let the caller know why nothing shows here
        if GetTime() - (lastMutedNote or 0) > 30 then
            lastMutedNote = GetTime()
            Print(sender .. " is calling you, but calls are switched off here. Click the gold arrow on the minimap and press the red button.")
        end
        return
    end
    local now = GetTime()
    if lastPingFrom[sender] and now - lastPingFrom[sender] < PING_GAP then return end
    lastPingFrom[sender] = now
    pings[sender] = now + PING_ARROW
    Beep()
    local line = (text and text ~= "") and text or "wants you. Follow the white arrow"
    local dist = Locate(m.unit)
    if dist and dist > FOLLOW_RANGE then
        line = line .. "\n|cff9aa0a6" .. math.floor(dist + 0.5) .. " yards away. Walk towards the arrow first.|r"
    elseif not dist and type(UnitIsVisible) == "function" then
        local ok, seen = pcall(UnitIsVisible, m.unit)
        if ok and Usable(seen, "boolean") and not seen then
            line = line .. "\n|cff9aa0a6" .. sender .. " is far away, not in sight.|r"
        end
    end
    ShowAlert("|cffe8c36a" .. sender .. "|r " .. line, PING_SECONDS)
    alertFrame.from = sender
    Tell("VER:" .. VERSION)
    Tell("ACK")
end

-- Shows on MY screen what dad would see. Works for helpers too.
local function TestCall()
    local list = Party()
    if #list > 0 then
        local who = list[1].name
        pings[who] = GetTime() + PING_ARROW
        Beep()
        ShowAlert("|cffe8c36a" .. who .. "|r wants you. Follow the white arrow  |cff9aa0a6(test)|r", PING_SECONDS)
        alertFrame.from = who
        Print("Test: this is what dad sees when " .. who .. " calls. If you stand next to them it ends right away with \"You found " .. who .. "\".")
    else
        Beep()
        ShowAlert("|cffe8c36aTest|r wants you. Follow the white arrow  |cff9aa0a6(test)|r", 5)
        Print("Test: text and sound only. Join a party to also see the arrow.")
    end
end
DadMode_TestCall = TestCall

-- The helper took the call back
local function ReceiveClear(sender)
    local m = (not IsMe(sender)) and Member(sender) or nil
    if not m then return end
    sender = m.name
    pings[sender] = nil
    if alertFrame and alertFrame.from == sender then alertFrame:Hide() end
end

-- Answers that come back to the helper
function DadMode_ReceiveReply(sender, kind)
    local m = (not IsMe(sender)) and Member(sender) or nil
    if not m then return end
    sender = m.name
    if GetTime() - lastSent > PING_ARROW + 5 then return end       -- only if I called recently
    call.who, call.at = sender, GetTime()
    call.state = (kind == "MUTED" and "muted") or (kind == "HERE" and "here") or "ack"
    if kind == "MUTED" then
        answered = true
        Print(sender .. " has DadMode, but calls are switched off there. On that computer type /dadmode alerts")
    elseif kind == "ACK" then
        answered = true
        Print("|cff6fcf97" .. sender .. " got your call.|r"
            .. (peerVersion[sender] and (" |cff9aa0a6(their DadMode " .. peerVersion[sender] .. ")|r") or ""))
    elseif kind == "HERE" then
        Print("|cff6fcf97" .. sender .. " is with you.|r")
        lastSent = 0
    end
end

local function SendPing(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local okG, grouped = pcall(IsInGroup)
    if not (okG and grouped) then
        Print("You are not in a party.")
        return
    end
    local ok, why = Tell("PING:" .. text:sub(1, 200))
    if ok then
        lastSent = GetTime()
        answered = false
        call.state, call.who, call.at = "sent", nil, lastSent
        Print("Call sent.")
        if C_Timer and C_Timer.After then
            local stamp = lastSent
            C_Timer.After(3, function()
                if not answered and lastSent == stamp then
                    call.state, call.at = "none", GetTime()
                    Print("|cffeb7a7aNobody answered.|r Nobody else in the party has DadMode running. Check it is installed and ticked on their AddOns list.")
                end
            end)
        end
    else
        Print("|cffeb7a7aCall not sent:|r " .. tostring(why) .. ". Type !dad in party chat instead.")
    end
end

DadMode_SendPing = SendPing

local function SendClear()
    Tell("CLEAR")
    lastSent = 0
    call.state = nil
    Print("Call cancelled.")
end

local function ChatPing(text, sender)
    if not Usable(text, "string") or not Usable(sender, "string") then return end
    local rest = text:match("^%s*![Dd][Aa][Dd]%s*(.*)$")
    if not rest then return end
    local word = rest:lower()
    if word == "ok" or word == "clear" or word == "stop" then
        ReceiveClear(sender)
    else
        ReceivePing(sender, rest)
    end
end

---------------------------------------------------------------------------
-- Picker window: who do you want arrows for
---------------------------------------------------------------------------

local RefreshPicker

local function BigButton(parent, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.bg = Tex(b, "BACKGROUND", 0.16, 0.18, 0.22, 1)
    b.bg:SetAllPoints()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", function(self) onClick(self) end)
    return b
end

---------------------------------------------------------------------------
-- Resize corners: drag the bottom right corner of a window, like in Windows
---------------------------------------------------------------------------

local function InFightNow() return InCombatLockdown and InCombatLockdown() end

-- Final size factor of one window: the "Window size" setting times its own corner drag
local function WindowScale(key)
    local own = db.winScale and db.winScale[key] or 1
    return (SCALES[db.scale or 3] or 1) * own
end

function DadMode_GripTexture(grip)
    pcall(function()
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    end)
end

local function MakeGrip(frame)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    DadMode_GripTexture(grip)
    return grip
end

-- For windows made of fixed buttons: dragging the corner makes the whole window bigger or
-- smaller. The top left corner stays where it is and the dragged corner follows the mouse.
-- secure = the window holds buttons the game protects, so it can not be resized in a fight.
-- widthFor(w): optional. Gets the width the mouse asks for and returns the window's natural
-- width for it, so a window can change its layout at a break point while it is dragged.
local function AddScaleGrip(frame, key, secure, onDone, widthFor)
    local grip = MakeGrip(frame)
    frame.grip = grip
    local function Stop()
        if not grip.sizing then return end
        grip.sizing = nil
        grip:SetScript("OnUpdate", nil)
        if onDone then onDone() end
    end
    grip.Stop = Stop
    grip:SetScript("OnMouseDown", function()
        if secure and InFightNow() then return end
        local old = frame:GetScale() or 1
        if old <= 0 then old = 1 end
        local ui = UIParent:GetEffectiveScale() or 1
        local left, top = (frame:GetLeft() or 0) * old, (frame:GetTop() or 0) * old
        local width = frame:GetWidth() or 1
        if width <= 0 then return end
        grip.sizing = true
        grip:SetScript("OnUpdate", function()
            if secure and InFightNow() then Stop() return end
            local cx = GetCursorPosition()
            if not cx then return end
            local want = cx / ui - left
            if widthFor then width = widthFor(want) or width end
            local scale = want / width
            scale = math.min(math.max(scale, GRIP_MIN), GRIP_MAX)
            db.winScale = db.winScale or {}
            db.winScale[key] = scale / (SCALES[db.scale or 3] or 1)
            frame:SetScale(scale)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
        end)
    end)
    grip:SetScript("OnMouseUp", Stop)
    grip:SetScript("OnHide", Stop)
end

local PICK_W, PICK_HALF = 268, 130

function DadMode_CreatePicker()
    picker = CreateFrame("Frame", "DadModePicker", UIParent)
    picker:SetSize(300, 200)
    picker:SetPoint("CENTER", 0, 40)
    picker:SetFrameStrata("DIALOG")
    picker:SetMovable(true)
    picker:EnableMouse(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    Tex(picker, "BACKGROUND", 0.07, 0.08, 0.10, 0.97):SetAllPoints()
    picker.showSettings = false

    picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picker.title:SetPoint("TOP", 0, -12)
    picker.sub = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.sub:SetPoint("TOP", picker.title, "BOTTOM", 0, -4)
    local ver = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ver:SetPoint("BOTTOMLEFT", 6, 4)
    ver:SetText("|cff9aa0a6" .. VERSION .. "|r")
    AddScaleGrip(picker, "picker", false)

    picker.names = {}
    for i = 1, 4 do
        picker.names[i] = BigButton(picker, PICK_W, 34, function(self)
            if not self.who then return end
            db.marked[self.who] = (not db.marked[self.who]) or nil
            RefreshPicker()
            UpdateArrows()
        end)
    end

    picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.empty:SetWidth(PICK_W)
    picker.empty:SetText("|cff9aa0a6You are not in a party yet.\nJoin a party and open this again.|r")

    picker.marker = BigButton(picker, PICK_W, 26, function()
        db.waypoint = nil
        if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
        RefreshPicker()
    end)
    picker.marker.label:SetText("Remove the red marker")

    picker.role = BigButton(picker, PICK_W, 26, function() DadMode_RepairCalls() end)
    picker.role.label:SetText("CALLS ARE OFF  (click to fix)")
    picker.role.bg:SetColorTexture(0.55, 0.18, 0.18, 1)

    local function SoundButton(kind, label)
        local b
        b = BigButton(picker, PICK_HALF, 26, function()
            db.sounds[kind] = ((db.sounds[kind] or DEFAULT_SOUND[kind]) % #SOUNDS) + 1
            Beep(kind, true)                 -- play it, so he hears what he picked
            RefreshPicker()
        end)
        b.kind, b.title = kind, label
        return b
    end
    picker.callSound = SoundButton("call", "Call")
    picker.farSound = SoundButton("far", "Far")

    picker.move = BigButton(picker, PICK_HALF, 26, function()
        moving = not moving
        bar:EnableMouse(moving)
        RefreshPicker()
        UpdateArrows()
    end)
    picker.far = BigButton(picker, PICK_HALF, 26, function()
        db.farWarning = not db.farWarning
        RefreshPicker()
    end)
    picker.size = BigButton(picker, PICK_W, 26, function()
        db.arrowSize = (db.arrowSize or 2) % #ARROW_SIZES + 1
        RefreshPicker()
        UpdateArrows()
    end)

    picker.more = BigButton(picker, PICK_HALF, 28, function()
        if DadMode_HasOptionsPage() then
            DadMode_OpenSettings()           -- the full page in the game's Options window
        else
            picker.showSettings = not picker.showSettings
            RefreshPicker()
        end
    end)
    picker.close = BigButton(picker, PICK_HALF, 28, function() picker:Hide() end)
    picker.close.label:SetText("Done")

    for _, b in ipairs({ picker.move, picker.far, picker.callSound, picker.farSound, picker.marker, picker.role,
        picker.size, picker.more, picker.close }) do
        pcall(function()
            local font, _, flags = b.label:GetFont()
            if font then b.label:SetFont(font, 12, flags) end
        end)
    end

    picker:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "DadModePicker") end
end

-- Fills in the window and stacks whatever is visible from the top down, so it is never taller than needed
function RefreshPicker()
    if not picker then return end
    if db.helper then
        picker.title:SetText("|cffe8c36aDadMode settings|r")
        picker.sub:SetText("|cff9aa0a6Want arrows yourself? Gold = arrow to them|r")
    else
        picker.title:SetText("|cffe8c36aWho do you want to find?|r")
        picker.sub:SetText("|cff9aa0a6Gold = you get an arrow to them|r")
    end
    local list = Party()
    local y = -50
    local function Row(b, height)
        b:ClearAllPoints()
        b:SetPoint("TOP", picker, "TOP", 0, y)
        b:Show()
        y = y - height - 4
    end
    local function Pair(left, right)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, y)
        left:Show()
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -16, y)
        right:Show()
        y = y - 30
    end

    for i, b in ipairs(picker.names) do
        local m = list[i]
        if m then
            b.who = m.name
            b.label:SetText(m.name)
            if db.marked[m.name] then
                b.bg:SetColorTexture(0.62, 0.48, 0.16, 1)
                b.label:SetTextColor(1, 1, 1)
            else
                b.bg:SetColorTexture(0.16, 0.18, 0.22, 1)
                b.label:SetTextColor(0.75, 0.77, 0.8)
            end
            Row(b, 34)
        else
            b.who = nil
            b:Hide()
        end
    end
    if #list == 0 then
        picker.empty:ClearAllPoints()
        picker.empty:SetPoint("TOP", picker, "TOP", 0, y - 2)
        picker.empty:Show()
        y = y - 40
    else
        picker.empty:Hide()
    end

    if db.waypoint then Row(picker.marker, 26) else picker.marker:Hide() end

    -- Only shown when something is wrong: he is in the dad role but his calls are switched off
    if not db.helper and not db.alerts then Row(picker.role, 26) else picker.role:Hide() end

    if picker.showSettings then
        for _, b in ipairs({ picker.callSound, picker.farSound }) do
            local choice = SOUNDS[db.sounds[b.kind] or DEFAULT_SOUND[b.kind]] or SOUNDS[1]
            b.label:SetText(b.title .. ": " .. choice.name)
        end
        Pair(picker.callSound, picker.farSound)
        picker.move.label:SetText(moving and "Lock arrows" or "Move arrows")
        picker.far.label:SetText(db.farWarning and "Far warning: on" or "Far warning: off")
        Pair(picker.move, picker.far)
        picker.size.label:SetText("Arrow size: " .. (ARROW_SIZES[db.arrowSize or 2] or ARROW_SIZES[2])[1])
        Row(picker.size, 26)
    else
        for _, b in ipairs({ picker.callSound, picker.farSound, picker.move, picker.far, picker.size }) do b:Hide() end
    end

    y = y - 4
    picker.more.label:SetText(picker.showSettings and "Fewer options" or "Settings")
    Pair(picker.more, picker.close)
    picker:SetHeight(-y + 18)
end

local function OpenPicker(showSettings)
    if not picker then return end
    picker.showSettings = showSettings and true or false
    RefreshPicker()
    picker:Show()
end

---------------------------------------------------------------------------
-- Helper bar: buttons for the people who look after dad
---------------------------------------------------------------------------

local ICONS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local BEAM = { 5, 6, 3, 2, 7, 1, 4, 8 }      -- the ground beam with the same colour as each icon

local function InFight()
    return InCombatLockdown and InCombatLockdown()
end

local function ApplyIcon()
    if not helper then return end
    if InFight() then
        Print("Not during a fight. Try again after.")
        return
    end
    local n = db.helperIcon or 1
    -- left click: the icon over my own head. Right click picks the next icon (see PostClick).
    helper.star:SetAttribute("type1", "macro")
    helper.star:SetAttribute("macrotext1", "/target player\n/tm " .. n .. "\n/targetlasttarget")
    -- left click: beam on the ground. Right click: take it away again.
    helper.beam:SetAttribute("type1", "worldmarker")
    helper.beam:SetAttribute("marker1", BEAM[n])
    helper.beam:SetAttribute("action1", "set")
    helper.beam:SetAttribute("type2", "worldmarker")
    helper.beam:SetAttribute("marker2", BEAM[n])
    helper.beam:SetAttribute("action2", "clear")
    helper.star.label:SetText(ICONS[n] .. " on my head")
end

function DadMode_SmallFont(b)
    pcall(function()
        local font, _, flags = b.label:GetFont()
        if font then b.label:SetFont(font, 12, flags) end
    end)
end

function DadMode_CreateHelper()
    helper = CreateFrame("Frame", "DadModeHelper", UIParent)
    helper:SetSize(302, 250)
    helper:SetFrameStrata("MEDIUM")
    helper:SetMovable(true)
    helper:SetClampedToScreen(true)
    helper:EnableMouse(true)
    helper:RegisterForDrag("LeftButton")
    if db.helperPos then
        helper:SetPoint(db.helperPos[1], UIParent, db.helperPos[2], db.helperPos[3], db.helperPos[4])
    else
        helper:SetPoint("RIGHT", UIParent, "RIGHT", -260, 0)
    end
    helper:SetScript("OnDragStart", function(self)
        if not InFight() then
            self.dragging = true
            self:StartMoving()
        end
    end)
    helper:SetScript("OnDragStop", function(self)
        -- if a fight started while dragging, DropDragged() already let go of it
        if not self.dragging or InFight() then return end
        self.dragging = false
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        db.helperPos = { point, rel, x, y }
    end)
    Tex(helper, "BACKGROUND", 0.07, 0.08, 0.10, 0.92):SetAllPoints()

    local title = helper:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cffe8c36aDadMode guide|r  |cff9aa0a6" .. VERSION .. "|r")
    helper.status = helper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helper.status:SetPoint("TOPLEFT", 10, -26)

    -- Warnings about the one being guided, and who runs an older DadMode. Always the same
    -- height, because the bar can not change size during a fight.
    local NOTE_H = 44
    helper.note = helper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helper.note:SetPoint("BOTTOMLEFT", 10, 6)
    helper.note:SetHeight(NOTE_H - 6)
    helper.note:SetJustifyH("LEFT")
    helper.note:SetJustifyV("TOP")
    pcall(function() helper.note:SetWordWrap(true) end)

    -- Eight buttons, in two columns or one (setting "Guide bar layout")
    helper.buttons = {}
    local ROW = 28
    local fullHeight = 250
    local function Place(b)
        DadMode_SmallFont(b)
        helper.buttons[#helper.buttons + 1] = b
        return b
    end
    local function Plain(label, onClick)
        local b = Place(BigButton(helper, 140, 24, onClick))
        b.label:SetText(label)
        return b
    end
    local function Secure(label)
        local b = CreateFrame("Button", nil, helper, "SecureActionButtonTemplate")
        b.bg = Tex(b, "BACKGROUND", 0.22, 0.20, 0.12, 1)
        b.bg:SetAllPoints()
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        b.label:SetPoint("CENTER")
        if label then b.label:SetText(label) end
        b:RegisterForClicks("AnyUp", "AnyDown")
        return Place(b)
    end
    -- A short explanation when the mouse rests on a button
    local function Tip(b, head, ...)
        local lines = { ... }
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(head)
            for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    -- Call dad. While a call is running the same button cancels it.
    helper.callBtn = Plain("Call dad", function()
        if call.state == "sent" or call.state == "ack" then SendClear() else DadMode_SendPing("") end
    end)
    Tip(helper.callBtn, "Call dad", "Shows a big call on his screen.", "While it runs, this button cancels it.")
    Plain("Come to me", function() DadMode_SendPing("says: come to me") end)
    Plain("Stop, wait here", function() DadMode_SendPing("says: stop and wait") end)
    Plain("Follow me", function() DadMode_SendPing("says: follow me. Click the green button") end)
    -- Waypoint. Once he has one, the same button removes it. Right click always removes.
    helper.wpBtn = Plain("Waypoint for dad", function() end)
    helper.wpBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" or wpOut then DadMode_SendWaypointClear() else DadMode_SendWaypoint() end
    end)
    pcall(function() helper.wpBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end)
    Tip(helper.wpBtn, "Waypoint for dad", "Sends your map pin, or the spot where you stand.",
        "Click again to remove it.", "Right click: always remove.")
    helper.star = Secure()
    Tip(helper.star, "Icon over my head", "Left click: put it on.", "Right click: pick the next icon.")
    local lastCycle = 0
    helper.star:SetScript("PostClick", function(self, button)
        if button ~= "RightButton" then return end
        local now = GetTime()
        if now - lastCycle < 0.3 then return end      -- press and release both arrive here
        lastCycle = now
        if InFight() then
            Print("Not during a fight. Try again after.")
            return
        end
        db.helperIcon = (db.helperIcon or 1) % 8 + 1
        ApplyIcon()
        Print("Your icon is now " .. ICONS[db.helperIcon] .. ".")
    end)
    helper.beam = Secure("Beam on the ground")
    Tip(helper.beam, "Beam on the ground", "Left click, then click the ground.", "Right click: remove the beam.")
    Plain("How is dad doing", function() OpenQuests() end)

    -- Puts the buttons in one or two columns. Not possible during a fight.
    local function Layout()
        if InFight() then return false end
        local cols = (db.helperCols == 1) and 1 or 2
        local width = (cols == 1) and 160 or 140
        for i, b in ipairs(helper.buttons) do
            local n = i - 1
            b:ClearAllPoints()
            b:SetSize(width, 24)
            b:SetPoint("TOPLEFT", helper, "TOPLEFT", 8 + (n % cols) * (width + 6), -46 - math.floor(n / cols) * ROW)
        end
        fullHeight = 46 + math.ceil(#helper.buttons / cols) * ROW + 6 + NOTE_H
        helper:SetWidth(8 + cols * width + (cols - 1) * 6 + 8)
        helper.note:SetWidth(cols * width + (cols - 1) * 6 - 14)
        helper:SetHeight(db.helperFolded and 44 or fullHeight)
        return true
    end
    helper.Layout = Layout
    Layout()

    -- The small button in the corner folds the bar up to just its title and the call status
    local function ApplyFold()
        for _, b in ipairs(helper.buttons) do
            if db.helperFolded then b:Hide() else b:Show() end
        end
        if db.helperFolded then helper.note:Hide() else helper.note:Show() end
        helper:SetHeight(db.helperFolded and 44 or fullHeight)
        helper.fold.label:SetText(db.helperFolded and "+" or "-")
    end
    helper.fold = BigButton(helper, 22, 18, function()
        if InFight() then
            Print("Not during a fight. Try again after.")
            return
        end
        db.helperFolded = not db.helperFolded
        ApplyFold()
    end)
    helper.fold:SetPoint("TOPRIGHT", -6, -6)
    AddScaleGrip(helper, "helper", true, function()
        local point, _, rel, x, y = helper:GetPoint()
        if point then db.helperPos = { point, rel, x, y } end
    end, function(want)
        -- break point: dragged narrower than this, the buttons go into one column
        local cols = (want < HELPER_BREAK) and 1 or 2
        if cols ~= ((db.helperCols == 1) and 1 or 2) then
            db.helperCols = cols
            helper.Layout()
        end
        return (cols == 1) and 176 or 302
    end)

    ApplyIcon()
    ApplyFold()
    if db.helper and not db.helperHidden then helper:Show() else helper:Hide() end
end

-- The line at the top of the helper bar: did my call arrive, and how far away is he
local function UpdateHelperStatus()
    if not (helper and helper:IsShown()) then return end
    helper.callBtn.label:SetText((call.state == "sent" or call.state == "ack") and "|cffeb7a7aCancel my call|r" or "Call dad")
    helper.wpBtn.label:SetText(wpOut and "|cffeb7a7aRemove his waypoint|r" or "Waypoint for dad")
    local now, text = GetTime(), ""
    if call.state == "sent" then
        text = "|cffe8c36aCalling...|r"
    elseif call.state == "none" then
        text = "|cffeb7a7aNo answer|r"
        if now - call.at > 12 then call.state = nil end
    elseif call.state == "muted" then
        text = "|cffeb7a7a" .. tostring(call.who) .. ": calls are off|r"
        if now - call.at > 12 then call.state = nil end
    elseif call.state == "here" then
        text = "|cff6fcf97" .. tostring(call.who) .. " is with you|r"
        if now - call.at > 10 then call.state = nil end
    elseif call.state == "ack" then
        text = "|cff6fcf97" .. tostring(call.who) .. " got it|r"
        for _, m in ipairs(Party()) do
            if m.name == call.who then
                local dist = Locate(m.unit)
                if dist then text = text .. "  " .. math.floor(dist + 0.5) .. " yd" end
            end
        end
        if now - call.at > PING_ARROW then call.state = nil end
    end
    -- no call going on: the top line carries the most important warning, the bottom shows all
    local notes = DadMode_Notes and DadMode_Notes() or {}
    if text == "" and notes[1] then text = notes[1] end
    helper.status:SetText(text)
    helper.note:SetText(table.concat(notes, "\n"))
end

local roleWin

-- guide = true for someone who looks after dad, false for the one who gets lost
local function SetRole(guide)
    if not helper then return false end
    if InFight() then
        Print("Not during a fight. Try again after.")
        return false
    end
    db.helper = guide and true or false
    db.roleChosen = true
    if db.helper then
        db.alerts, db.farWarning, db.follow = false, false, false
        db.helperHidden = nil
        helper:Show()
        Print("You are a guide. Your buttons are on. Calls and far warnings are off for you, because you are not the one who gets lost.")
    else
        db.alerts, db.farWarning, db.follow = true, true, true
        helper:Hide()
        Print("You are the one being guided. Calls, far warning and the follow button are on.")
    end
    if RefreshPicker then RefreshPicker() end
    return true
end

-- Puts calls back on for someone in the dad role
local function RepairCalls()
    db.alerts, db.farWarning, db.follow = true, true, true
    Print("Calls are on again.")
    if RefreshPicker then RefreshPicker() end
end
DadMode_RepairCalls = RepairCalls
DadMode_SetRole = SetRole

local function ToggleHelper()
    if not db.helper and not db.alerts then return RepairCalls() end
    SetRole(not db.helper)
end

-- Asked once per computer, the first time DadMode starts. /dadmode role opens it again.
function DadMode_CreateRoleWindow()
    roleWin = CreateFrame("Frame", "DadModeRole", UIParent)
    roleWin:SetSize(340, 168)
    roleWin:SetPoint("CENTER", 0, 120)
    roleWin:SetFrameStrata("DIALOG")
    roleWin:EnableMouse(true)
    Tex(roleWin, "BACKGROUND", 0.07, 0.08, 0.10, 0.97):SetAllPoints()
    local title = roleWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffe8c36aWho is using DadMode on this computer?|r")

    roleWin.dad = BigButton(roleWin, 300, 36, function()
        if SetRole(false) then roleWin:Hide() end
    end)
    roleWin.dad:SetPoint("TOP", 0, -40)
    roleWin.dad.label:SetText("I need help finding my party")
    roleWin.guide = BigButton(roleWin, 300, 36, function()
        if SetRole(true) then roleWin:Hide() end
    end)
    roleWin.guide:SetPoint("TOP", 0, -82)
    roleWin.guide.label:SetText("I am a guide for someone")
    for _, b in ipairs({ roleWin.dad, roleWin.guide }) do
        pcall(function()
            local font, _, flags = b.label:GetFont()
            if font then b.label:SetFont(font, 14, flags) end
        end)
    end
    local note = roleWin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOM", 0, 12)
    note:SetText("|cff9aa0a6Asked once. Change it later with /dadmode role|r")
    roleWin:Hide()
end

DadMode_ToggleHelper = ToggleHelper

---------------------------------------------------------------------------
-- Waypoints: a helper puts a marker on dad's map
---------------------------------------------------------------------------
-- Helper sends WP:<map>:<x>:<y>. Dad's addon sets the game's own map pin there and tracks it,
-- then answers WPOK or WPNO. WPC removes it again.

-- Helper's side: my own map pin if I have one, otherwise the spot where I stand
local function SendWaypoint()
    local M = C_Map
    if not M then return Print("This game version has no map pins.") end
    local mapID, x, y, what
    if M.HasUserWaypoint and M.GetUserWaypoint then
        local okH, has = pcall(M.HasUserWaypoint)
        if okH and has == true then
            local okP, point = pcall(M.GetUserWaypoint)
            if okP and type(point) == "table" and Usable(point.uiMapID, "number") then
                local px, py = XY(point.position)
                if px then mapID, x, y, what = point.uiMapID, px, py, "your own map pin" end
            end
        end
    end
    if not mapID and M.GetBestMapForUnit and M.GetPlayerMapPosition then
        local okM, id = pcall(M.GetBestMapForUnit, "player")
        if okM and Usable(id, "number") then
            local okP, pos = pcall(M.GetPlayerMapPosition, id, "player")
            local px, py = XY(okP and pos or nil)
            if px then mapID, x, y, what = id, px, py, "the spot where you stand" end
        end
    end
    if not mapID then
        Print("|cffeb7a7aNo position to send.|r That happens in dungeons. Outdoors it works.")
        return
    end
    local ok, why = Tell(("WP:%d:%.4f:%.4f"):format(mapID, x, y))
    if ok then
        lastSent = GetTime()
        wpOut = true
        Print("Waypoint sent: " .. what .. ".")
        pcall(ResolveStops)
        for _, body in ipairs(DadMode_PackStops()) do Queue(body) end
        PumpOutbox()
    else
        Print("|cffeb7a7aWaypoint not sent:|r " .. tostring(why))
    end
end

local function SendWaypointClear()
    Tell("WPC")
    wpOut = false
    Print("Asked to remove the waypoint.")
end

-- Dad's side
DadMode_SendWaypoint, DadMode_SendWaypointClear = SendWaypoint, SendWaypointClear

function DadMode_ReceiveWaypoint(sender, text)
    local m = (not IsMe(sender)) and Member(sender) or nil
    if not m then return end
    if not db.alerts then
        Tell("MUTED")
        return
    end
    local M = C_Map
    if text == "WPC" then
        if M and M.ClearUserWaypoint then pcall(M.ClearUserWaypoint) end
        db.waypoint = nil
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
        local wn, ww, wcont = MapToWorld(mapID, x, y)
        db.waypoint = { map = mapID, x = x, y = y, n = wn, w = ww, cont = wcont, from = m.name }
        travel.key, travel.at, travel.onPlatform = nil, GetTime() - 1, false     -- route is worked out a second later
        Beep("call")
        ShowAlert("|cffe8c36a" .. m.name .. "|r put a marker on your map\n|cffff5a5aFollow the red arrow|r", 8)
        alertFrame.from = m.name
        Tell("WPOK")
    else
        Tell("WPNO")
    end
end

---------------------------------------------------------------------------
-- Quests: helpers can look at dad's quest log
---------------------------------------------------------------------------
-- Helper sends QREQ. Dad's addon answers with QS:<count>, then Q:<quests>, then QE.
-- One quest is  id~level~done~title~objective;objective   and quests are joined with ^

local questData = {}                 -- name -> { list = {}, done = bool, at = time }
local lastQuestReply, questAsked = 0, 0

local function Clean(text, max)
    text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[~%^;|\n\r]", " ")
    return text:sub(1, max)
end

-- Dad's side: read my quest log
local function ReadQuests()
    local out = {}
    local Q = C_QuestLog
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return out end
    local okN, n = pcall(Q.GetNumQuestLogEntries)
    if not okN or not Usable(n, "number") then return out end
    for i = 1, n do
        local ok, info = pcall(Q.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and not info.isHidden
            and Usable(info.title, "string") and Usable(info.questID, "number") then
            local done = false
            if Q.IsComplete then
                local okD, d = pcall(Q.IsComplete, info.questID)
                done = okD and d == true
            end
            local objs = {}
            if Q.GetQuestObjectives then
                local okO, list = pcall(Q.GetQuestObjectives, info.questID)
                if okO and type(list) == "table" then
                    for _, o in ipairs(list) do
                        if #objs < 4 and type(o) == "table" and Usable(o.text, "string") and o.text ~= "" then
                            objs[#objs + 1] = (o.finished == true and "+" or "-") .. Clean(o.text, 60)
                        end
                    end
                end
            end
            out[#out + 1] = table.concat({
                info.questID, Usable(info.level, "number") and info.level or 0, done and 1 or 0,
                Clean(info.title, 60), table.concat(objs, ";"),
            }, "~")
        end
    end
    return out
end

-- Calls a game function if it exists and returns its first two results when they are readable
local function Get(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return Usable(a) and a or nil, Usable(b) and b or nil
end

local function Flag(v)
    return v == true and 1 or 0
end

local consumables = {}               -- filled by ReadStatus: "itemID:kind" -> how many

-- Dad's side: which potions, food and bandages, as  itemID:kind=count  joined by ~ (biggest stacks first)
function DadMode_ReadConsumables()
    local list = {}
    for key, count in pairs(consumables) do list[#list + 1] = { key = key, count = count } end
    table.sort(list, function(a, b) return a.count > b.count end)
    local parts, len = {}, 3
    for _, e in ipairs(list) do
        local part = e.key .. "=" .. e.count
        if len + #part + 1 > 245 then break end
        parts[#parts + 1] = part
        len = len + #part + 1
    end
    return "CN:" .. table.concat(parts, "~")
end

-- Dad's side: everything a helper might want to know, as two short messages
local function ReadStatus()
    local n, t = {}, {}                  -- numbers, texts
    n.lv = Get(UnitLevel, "player")
    local xp, xpMax = Get(UnitXP, "player"), Get(UnitXPMax, "player")
    if type(xp) == "number" and type(xpMax) == "number" and xpMax > 0 then n.xp = math.floor(xp / xpMax * 100) end
    n.g = Get(GetMoney)
    n.dead = Flag(Get(UnitIsDeadOrGhost, "player"))
    n.afk = Flag(Get(UnitIsAFK, "player"))
    n.cb = Flag(Get(UnitAffectingCombat, "player"))
    n.tp = Get(UnitCharacterPoints, "player")

    -- bags, and what is in them
    local C = C_Container
    if C and C.GetContainerNumSlots then
        local free, total, food, bandage, potion = 0, 0, 0, 0, 0
        consumables = {}
        for bag = 0, 4 do
            local slots = Get(C.GetContainerNumSlots, bag)
            if type(slots) == "number" and slots > 0 then
                local f, family = Get(C.GetContainerNumFreeSlots, bag)
                if type(f) == "number" and (family == nil or family == 0) then
                    free, total = free + f, total + slots
                end
                for slot = 1, slots do
                    local info = Get(C.GetContainerItemInfo, bag, slot)
                    if type(info) == "table" and Usable(info.itemID, "number") and C_Item and C_Item.GetItemInfoInstant then
                        local ok, _, _, _, _, _, class, sub = pcall(C_Item.GetItemInfoInstant, info.itemID)
                        if ok and class == 0 then
                            local count = Usable(info.stackCount, "number") and info.stackCount or 1
                            if sub == 5 then food = food + count
                            elseif sub == 7 then bandage = bandage + count
                            elseif sub == 1 then potion = potion + count end
                            if sub == 5 or sub == 7 or sub == 1 then
                                local key = info.itemID .. ":" .. sub
                                consumables[key] = (consumables[key] or 0) + count
                            end
                        end
                    end
                end
            end
        end
        n.bf, n.bt, n.fd, n.bd, n.pot = free, total, food, bandage, potion
    end

    -- gear: the most worn piece, and how many are broken
    local lowest, broken = nil, 0
    for slot = 1, 18 do
        local cur, max = Get(GetInventoryItemDurability, slot)
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            local pct = math.floor(cur / max * 100)
            if not lowest or pct < lowest then lowest = pct end
            if cur == 0 then broken = broken + 1 end
        end
    end
    n.dur, n.brk = lowest, broken

    -- hearthstone: minutes until it is ready
    local start, duration
    if C and C.GetItemCooldown then start, duration = Get(C.GetItemCooldown, 6948) end
    if type(start) == "number" and type(duration) == "number" then
        n.hcd = (duration > 0) and math.max(0, math.ceil((start + duration - GetTime()) / 60)) or 0
    end

    t.z = Get(GetRealZoneText) or Get(GetZoneText)
    t.sz = Get(GetSubZoneText)
    t.hs = Get(GetBindLocation)
    if Get(UnitExists, "target") == true then
        t.tg = (GetUnitName and Get(GetUnitName, "target", false)) or Get(UnitName, "target")
    end
    t.v = VERSION
    -- his class, so a guide's addon knows which armor he can wear
    if type(UnitClass) == "function" then
        local okC, _, token = pcall(UnitClass, "player")
        if okC and Usable(token, "string") then t.cl = token end
    end

    local a, b = {}, {}
    for k, v in pairs(n) do
        if type(v) == "number" then a[#a + 1] = k .. "=" .. math.floor(v) end
    end
    for k, v in pairs(t) do
        if type(v) == "string" and v ~= "" then b[#b + 1] = k .. "=" .. Clean(v, 40) end
    end
    return ("ST:" .. table.concat(a, "~")):sub(1, 250), ("ST:" .. table.concat(b, "~")):sub(1, 250)
end

-- Dad's side: what he is wearing, as  slot=itemID:condition%  joined by ~
function DadMode_ReadGear()
    local parts = {}
    for slot = 1, 18 do
        local id = Get(GetInventoryItemID, "player", slot)
        if type(id) == "number" and id > 0 then
            local cur, max = Get(GetInventoryItemDurability, slot)
            local pct = (type(cur) == "number" and type(max) == "number" and max > 0) and math.floor(cur / max * 100) or -1
            parts[#parts + 1] = slot .. "=" .. id .. ":" .. pct
        end
    end
    return ("GR:" .. table.concat(parts, "~")):sub(1, 250)
end

-- The exact items he wears, with enchants and random stats, so the guide gets the real tooltip.
-- Several messages, because one item can be long.
function DadMode_ReadGearLinks()
    local msgs, cur = {}, ""
    for slot = 1, 18 do
        local link = Get(GetInventoryItemLink, "player", slot)
        local item = type(link) == "string" and link:match("item:[%-%d:]+") or nil
        if item then
            item = item:gsub(":+$", "")
            local part = slot .. "=" .. item
            if #part <= 230 then
                if cur ~= "" and #cur + #part + 1 > 230 then
                    msgs[#msgs + 1] = "GL:" .. cur
                    cur = ""
                end
                cur = (cur == "" and "" or (cur .. "~")) .. part
            end
        end
    end
    if cur ~= "" then msgs[#msgs + 1] = "GL:" .. cur end
    return msgs
end

-- His total stats. Whatever the game does not tell is simply left out.
function DadMode_ReadStats()
    local n = {}
    local function Stat(i)
        local _, eff = Get(UnitStat, "player", i)
        return eff
    end
    n.str, n.agi, n.sta, n.int, n.spi = Stat(1), Stat(2), Stat(3), Stat(4), Stat(5)
    local _, armor = Get(UnitArmor, "player")
    n.arm = armor
    n.hp = Get(UnitHealthMax, "player")
    n.mp = Get(UnitPowerMax, "player", 0)
    if type(GetSpellBonusDamage) == "function" then
        local best
        for school = 2, 7 do
            local v = Get(GetSpellBonusDamage, school)
            if type(v) == "number" and (not best or v > best) then best = v end
        end
        n.sp = best
    end
    n.heal = Get(GetSpellBonusHealing)
    local base, pos, neg = nil, nil, nil
    if type(UnitAttackPower) == "function" then
        local ok, a, b, c = pcall(UnitAttackPower, "player")
        if ok and Usable(a, "number") then base, pos, neg = a, Usable(b, "number") and b or 0, Usable(c, "number") and c or 0 end
    end
    if base then n.ap = base + pos + neg end
    local crit = Get(GetSpellCritChance, 2)
    if type(crit) == "number" then n.scr = crit * 10 end
    local mcrit = Get(GetCritChance)
    if type(mcrit) == "number" then n.mcr = mcrit * 10 end
    local parts = {}
    for k, v in pairs(n) do
        if type(v) == "number" then parts[#parts + 1] = k .. "=" .. math.floor(v + 0.5) end
    end
    return ("SS:" .. table.concat(parts, "~")):sub(1, 250)
end

-- Things in his bags that can be worn or wielded, so a guide can see whether he is carrying
-- something better than what he has on. At most 16, as item strings like the worn gear.
-- (Global on purpose: this file is at the game's limit of 200 local names.)
function DadMode_ReadBagGear()
    local NOT_GEAR = { [""] = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_TABARD = true,
        INVTYPE_BODY = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }
    local C, I = C_Container, C_Item
    local msgs, found, cur = {}, 0, ""
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo and I and I.GetItemInfoInstant) then return msgs end
    for bag = 0, 4 do
        local slots = Get(C.GetContainerNumSlots, bag)
        if type(slots) == "number" then
            for slot = 1, slots do
                local info = Get(C.GetContainerItemInfo, bag, slot)
                if found < 16 and type(info) == "table" and Usable(info.itemID, "number") then
                    local ok, _, _, _, equipLoc, _, classID = pcall(I.GetItemInfoInstant, info.itemID)
                    if ok and Usable(equipLoc, "string") and not NOT_GEAR[equipLoc] and (classID == 2 or classID == 4) then
                        local link = Usable(info.hyperlink, "string") and info.hyperlink or nil
                        local item = link and link:match("item:[%-%d:]+") or ("item:" .. info.itemID)
                        item = item:gsub(":+$", "")
                        if #item <= 220 then
                            found = found + 1
                            if cur ~= "" and #cur + #item + 1 > 230 then
                                msgs[#msgs + 1] = "BG:" .. cur
                                cur = ""
                            end
                            cur = (cur == "" and "" or (cur .. "~")) .. item
                        end
                    end
                end
            end
        end
    end
    if cur ~= "" then msgs[#msgs + 1] = "BG:" .. cur end
    table.insert(msgs, 1, "BGS:" .. found)       -- start marker with the count, also when there is none
    return msgs
end

function DadMode_SendQuests()
    if outbox[1] then return end                 -- an answer is already on its way to the whole party
    if GetTime() - lastQuestReply < 5 then return end
    lastQuestReply = GetTime()
    local records = ReadQuests()
    local msgs, cur = {}, ""
    local okS, st1, st2 = pcall(ReadStatus)
    if okS then msgs[1], msgs[2] = st1, st2 end
    -- quests first: they are what the guide is waiting for
    msgs[#msgs + 1] = "QS:" .. #records
    for _, rec in ipairs(records) do
        if cur ~= "" and #cur + #rec + 1 > 235 then
            msgs[#msgs + 1] = "Q:" .. cur
            cur = ""
        end
        cur = (cur == "" and "" or (cur .. "^")) .. rec:sub(1, 235)
    end
    if cur ~= "" then msgs[#msgs + 1] = "Q:" .. cur end
    msgs[#msgs + 1] = "QE"
    local okG, gear = pcall(DadMode_ReadGear)
    if okG then msgs[#msgs + 1] = gear end
    local okL, links = pcall(DadMode_ReadGearLinks)
    if okL and type(links) == "table" then
        for _, body in ipairs(links) do msgs[#msgs + 1] = body end
    end
    local okT, stats = pcall(DadMode_ReadStats)
    if okT and stats ~= "SS:" then msgs[#msgs + 1] = stats end
    local okC, cons = pcall(DadMode_ReadConsumables)
    if okS and okC and cons ~= "CN:" then msgs[#msgs + 1] = cons end
    local okB, bagGear = pcall(DadMode_ReadBagGear)
    if okB and type(bagGear) == "table" then
        for _, body in ipairs(bagGear) do msgs[#msgs + 1] = body end
    end
    for _, body in ipairs(msgs) do Queue(body) end
    PumpOutbox()
end

function DadMode_Coins(copper)
    local g, sv, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local out = ""
    if g > 0 then out = out .. "|cffe8c36a" .. g .. "g|r " end
    if g > 0 or sv > 0 then out = out .. "|cffc8cdd3" .. sv .. "s|r " end
    return out .. "|cffd99a6c" .. c .. "c|r"
end

local GOOD, WARN, BAD, GREY = "|cff6fcf97", "|cffe8c36a", "|cffeb7a7a", "|cff9aa0a6"

-- The card at the top: how he is doing right now
function DadMode_StatusLines(name, st, lines)
    local head = "|cffe8c36a" .. name .. "|r"
    if st.lv then
        head = head .. "   level " .. st.lv .. (st.xp and (GREY .. " (" .. st.xp .. "% to " .. (st.lv + 1) .. ")|r") or "")
    end
    if st.g then head = head .. "   " .. DadMode_Coins(st.g) end
    lines[#lines + 1] = head

    local state = {}
    if st.dead == 1 then state[#state + 1] = BAD .. "DEAD|r" end
    if st.cb == 1 then state[#state + 1] = WARN .. "in a fight|r" end
    if st.afk == 1 then state[#state + 1] = WARN .. "away from keyboard|r" end
    if #state > 0 then lines[#lines + 1] = table.concat(state, "   ") end

    if st.z then
        lines[#lines + 1] = "Where: " .. st.z .. ((st.sz and st.sz ~= st.z) and (", " .. st.sz) or "")
    end
    if st.tg then lines[#lines + 1] = "Looking at: " .. st.tg end

    local row = {}
    if st.bf and st.bt then
        local col = (st.bf <= 2 and BAD) or (st.bf <= 6 and WARN) or GOOD
        row[#row + 1] = "Bags: " .. col .. (st.bf == 0 and "FULL" or (st.bf .. " free")) .. "|r" .. GREY .. " of " .. st.bt .. "|r"
    end
    if st.dur then
        local col = ((st.brk or 0) > 0 or st.dur <= 20) and BAD or (st.dur <= 40 and WARN) or GOOD
        row[#row + 1] = "Gear: " .. col .. "worst piece " .. st.dur .. "%|r"
            .. ((st.brk or 0) > 0 and (BAD .. ", " .. st.brk .. " broken, needs repair|r") or "")
    end
    if #row > 0 then lines[#lines + 1] = table.concat(row, "     ") end

    row = {}
    if st.fd then row[#row + 1] = "Food and drink: " .. (st.fd == 0 and (BAD .. "0|r") or st.fd) end
    if st.bd then row[#row + 1] = "Bandages: " .. (st.bd == 0 and (WARN .. "0|r") or st.bd) end
    if st.pot then row[#row + 1] = "Potions: " .. st.pot end
    if #row > 0 then lines[#lines + 1] = table.concat(row, "    ") end

    row = {}
    if st.hs then
        row[#row + 1] = "Hearthstone: " .. st.hs
            .. (st.hcd and (st.hcd == 0 and (GOOD .. ", ready|r") or (GREY .. ", ready in " .. st.hcd .. " min|r")) or "")
    end
    if st.tp and st.tp > 0 then row[#row + 1] = WARN .. "Unspent talent points: " .. st.tp .. "|r" end
    if #row > 0 then lines[#lines + 1] = table.concat(row, "     ") end
end

-- The quest that comes after this one, if the Questie addon is installed on THIS computer.
-- The game itself does not tell which quest follows; Questie's database does.
function DadMode_NextInChain(id)
    if type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return nil end
    local ok, QDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if not ok or type(QDB) ~= "table" or type(QDB.QueryQuestSingle) ~= "function" then return nil end
    local ok2, nextId = pcall(QDB.QueryQuestSingle, id, "nextQuestInChain")
    if not ok2 or type(nextId) ~= "number" or nextId == 0 then return nil end
    local ok3, name = pcall(QDB.QueryQuestSingle, nextId, "name")
    local ok4, level = pcall(QDB.QueryQuestSingle, nextId, "questLevel")
    name = (ok3 and type(name) == "string" and name ~= "") and name or ("quest " .. nextId)
    return name, (ok4 and type(level) == "number" and level > 0) and level or nil
end

-- Who a finished quest is handed in to, and in which zone. Also from Questie.
function DadMode_TurnIn(id)
    if type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return nil end
    local ok, QDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if not ok or type(QDB) ~= "table" or type(QDB.QueryQuestSingle) ~= "function" then return nil end
    local ok2, by = pcall(QDB.QueryQuestSingle, id, "finishedBy")
    if not ok2 or type(by) ~= "table" then return nil end
    local query, who
    if type(by[1]) == "table" and type(by[1][1]) == "number" then
        query, who = QDB.QueryNPCSingle, by[1][1]
    elseif type(by[2]) == "table" and type(by[2][1]) == "number" then
        query, who = QDB.QueryObjectSingle, by[2][1]
    end
    if type(query) ~= "function" then return nil end
    local ok3, name = pcall(query, who, "name")
    if not ok3 or type(name) ~= "string" or name == "" then return nil end
    local zone
    local ok4, zoneID = pcall(query, who, "zoneID")
    if ok4 and type(zoneID) == "number" and zoneID > 0 and C_Map and C_Map.GetAreaInfo then
        local ok5, zoneName = pcall(C_Map.GetAreaInfo, zoneID)
        if ok5 and Usable(zoneName, "string") and zoneName ~= "" then zone = zoneName end
    end
    return name, zone
end

local SLOTS = {
    "Head", "Neck", "Shoulders", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands",
    "Ring", "Ring", "Trinket", "Trinket", "Back", "Main hand", "Off hand", "Ranged",
}
local MUST_HAVE = { [1] = true, [3] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [15] = true, [16] = true }
local QUALITY = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }

-- What he is wearing, slot by slot
local STAT_ROWS = {
    { { "hp", "Health" }, { "mp", "Mana" }, { "arm", "Armor" } },
    { { "sta", "Stamina" }, { "int", "Intellect" }, { "spi", "Spirit" }, { "str", "Strength" }, { "agi", "Agility" } },
    { { "sp", "Spell power" }, { "heal", "Healing" }, { "scr", "Spell crit", true }, { "ap", "Attack power" }, { "mcr", "Melee crit", true } },
}

function DadMode_StatLines(stats, lines)
    for _, row in ipairs(STAT_ROWS) do
        local parts = {}
        for _, def in ipairs(row) do
            local v = stats[def[1]]
            if v then
                parts[#parts + 1] = GREY .. def[2] .. "|r " .. (def[3] and (("%.1f%%"):format(v / 10)) or v)
            end
        end
        if #parts > 0 then lines[#lines + 1] = table.concat(parts, "    ") end
    end
end

function DadMode_GearLines(gear, lines)
    local total, count = 0, 0
    for slot = 1, 18 do
        if slot ~= 4 then
            local g = gear[slot]
            local label = GREY .. SLOTS[slot] .. ":|r "
            if not g then
                lines[#lines + 1] = label .. (MUST_HAVE[slot] and (BAD .. "EMPTY|r") or (GREY .. "empty|r"))
            else
                local name, quality, level
                if C_Item and C_Item.GetItemInfo then
                    local ok, n, _, q, l = pcall(C_Item.GetItemInfo, g.id)
                    if ok and Usable(n, "string") then name, quality, level = n, q, l end
                end
                if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, g.id) end
                local line = label .. (name and ("|cff" .. (QUALITY[quality] or "ffffff") .. "|H" .. (g.link or ("item:" .. g.id)) .. "|h[" .. name .. "]|h|r") or (GREY .. "loading...|r"))
                if type(level) == "number" and level > 0 then
                    line = line .. GREY .. "  item level " .. level .. "|r"
                    total, count = total + level, count + 1
                end
                if g.dur >= 0 and g.dur <= 40 then
                    line = line .. "  " .. ((g.dur <= 20) and BAD or WARN) .. (g.dur == 0 and "BROKEN" or (g.dur .. "%")) .. "|r"
                end
                lines[#lines + 1] = line
            end
        end
    end
    if count > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "Average item level: " .. math.floor(total / count + 0.5)
    end
end

-- Which potions, food and bandages he carries
function DadMode_ConsumableLines(cons, lines)
    local groups = { { 1, "Potions" }, { 5, "Food and drink" }, { 7, "Bandages" } }
    for _, g in ipairs(groups) do
        local parts = {}
        for _, c in ipairs(cons) do
            if c.kind == g[1] then
                local name
                if C_Item and C_Item.GetItemInfo then
                    local ok, n = pcall(C_Item.GetItemInfo, c.id)
                    if ok and Usable(n, "string") then name = n end
                end
                if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, c.id) end
                parts[#parts + 1] = c.count .. "x " .. (name or "loading...")
            end
        end
        lines[#lines + 1] = "|cffe8c36a" .. g[2] .. "|r"
        if #parts == 0 then
            lines[#lines + 1] = "  " .. GREY .. "none|r"
        else
            for _, part in ipairs(parts) do lines[#lines + 1] = "  " .. part end
        end
    end
end

-- Helper's side
-- My own quest log as a table: id -> { title, level, done, objs }
local function MyQuests()
    local mine = {}
    local ok, records = pcall(ReadQuests)
    if not ok or type(records) ~= "table" then return mine end
    for _, rec in ipairs(records) do
        local id, level, done, title, objs = rec:match("^(%d+)~(%d+)~(%d)~([^~]*)~?(.*)$")
        if id then
            local q = { id = tonumber(id), level = tonumber(level), done = done == "1", title = title, objs = {} }
            for o in objs:gmatch("[^;]+") do q.objs[#q.objs + 1] = o end
            mine[q.id] = q
        end
    end
    return mine
end

-- Does this quest match what is typed in the search box?
local function Matches(q, filter)
    if not filter or filter == "" then return true end
    if q.title:lower():find(filter, 1, true) then return true end
    for _, o in ipairs(q.objs) do
        if o:lower():find(filter, 1, true) then return true end
    end
    return false
end

-- Asks the other side which of my quests he has already done. He answers with QD.
local function AskDone(name)
    local d = questData[name]
    if not d then return end
    local has = {}
    for _, q in ipairs(d.list) do has[q.id] = true end
    local ids, seen = {}, {}
    for id in pairs(MyQuests()) do
        if not has[id] then ids[#ids + 1] = id; seen[id] = true end
    end
    -- and the quests of the dungeon picked on the Dungeon tab
    if DadMode_DungeonQuestIds then
        for _, id in ipairs(DadMode_DungeonQuestIds() or {}) do
            if not has[id] and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
        end
    end
    d.check = d.check or {}
    if #ids == 0 then return end
    table.sort(ids)
    d.checkAsked = GetTime()
    local cur = ""
    for _, id in ipairs(ids) do
        if #cur + #tostring(id) + 1 > 230 then
            Tell("QC:" .. cur)
            cur = ""
        end
        cur = (cur == "" and "" or (cur .. ",")) .. id
    end
    if cur ~= "" then Tell("QC:" .. cur) end
end

-- The other side: which of these quests have I already done?
function DadMode_AnswerDone(text)
    local Q = C_QuestLog
    if not (Q and Q.IsQuestFlaggedCompleted) then return end
    local parts, count = {}, 0
    for id in text:gmatch("%d+") do
        count = count + 1
        if count > 60 then break end
        local ok, done = pcall(Q.IsQuestFlaggedCompleted, tonumber(id))
        if ok and Usable(done, "boolean") then parts[#parts + 1] = id .. "=" .. (done and 1 or 0) end
    end
    local cur = ""
    for _, part in ipairs(parts) do
        if #cur + #part + 1 > 230 then
            Tell("QD:" .. cur)
            cur = ""
        end
        cur = (cur == "" and "" or (cur .. ",")) .. part
    end
    if cur ~= "" then Tell("QD:" .. cur) end
end

DadMode_AskDone = function(name) return AskDone(name) end

local STALE = 25        -- seconds without the end of a quest list before what arrived is shown as it is

local function RenderQuests()
    if not (questWin and questWin:IsShown()) then return end
    local filter = questWin.filter
    local view = questWin.view
    local myQuests = MyQuests()
    local now = GetTime()
    local lines, any = {}, false
    local function QuestLine(q)
        return (q.level > 0 and ("|cff9aa0a6[" .. q.level .. "]|r ") or "") .. q.title
    end
    for name, d in pairs(questData) do
        any = true
        -- an old DadMode on his side can lose the end of a long list: show what did arrive
        if d.pending and now - d.pending.at > STALE then
            d.partial = { #d.pending.list, d.pending.expect }
            d.list, d.pending, d.done = d.pending.list, nil, true
            if db.helper then pcall(AskDone, name) end
        end
        -- while the very first list is still coming in, show it as it grows
        local list = (d.done or not d.pending) and d.list or d.pending.list
        local has, ready = {}, 0
        for _, q in ipairs(list) do
            has[q.id] = true
            if q.done then ready = ready + 1 end
        end
        local missing = {}
        for id, q in pairs(myQuests) do
            if not has[id] then missing[#missing + 1] = q end
        end
        local progress = ""
        if d.pending and not d.done then
            progress = GREY .. "  loading " .. #d.pending.list .. " of " .. d.pending.expect .. "...|r"
        elseif d.pending then
            progress = GREY .. "  updating...|r"
        elseif not d.done then
            progress = GREY .. "  loading...|r"
        elseif d.partial then
            progress = "  " .. BAD .. "only " .. d.partial[1] .. " of " .. d.partial[2] .. " arrived. " .. name .. " needs DadMode 1.18 or newer|r"
        end

        if view == "overview" then
            local age = math.floor(now - (d.at or now))
            if d.st and next(d.st) then
                DadMode_StatusLines(name, d.st, lines)
                lines[#lines + 1] = GREY .. "updated " .. (age < 5 and "just now" or (age .. " seconds ago"))
                    .. (d.st.v and ("   DadMode " .. d.st.v) or "") .. "|r"
            else
                lines[#lines + 1] = "|cffe8c36a" .. name .. "|r"
            end
            lines[#lines + 1] = " "
            lines[#lines + 1] = "|cffe8c36aQuests|r  " .. #list .. (ready > 0 and ("   " .. GOOD .. ready .. " ready to hand in|r") or "") .. progress
            if d.done then
                lines[#lines + 1] = (#missing > 0)
                    and ("|cffe8c36aMissing|r  " .. BAD .. #missing .. "|r" .. GREY .. " of your quests are not in his log. See the Missing tab.|r")
                    or ("|cffe8c36aMissing|r  " .. GOOD .. "none|r" .. GREY .. ". He has every quest you have.|r")
            end
            lines[#lines + 1] = " "

        elseif view == "gear" then
            lines[#lines + 1] = "|cffe8c36a" .. name .. "|r"
            if d.stats and next(d.stats) then
                lines[#lines + 1] = "|cffe8c36aStats|r"
                DadMode_StatLines(d.stats, lines)
                lines[#lines + 1] = " "
            end
            lines[#lines + 1] = "|cffe8c36aGear|r  " .. GREY .. "hold the mouse over an item to see its stats|r"
            if d.gear then
                DadMode_GearLines(d.gear, lines)
            else
                lines[#lines + 1] = GREY .. "No gear information. Dad needs DadMode 1.8 or newer.|r"
            end
            lines[#lines + 1] = " "
            if DadMode_BagGearLines then
                DadMode_BagGearLines(name, d, lines)
                lines[#lines + 1] = " "
            end
            if d.cons then
                DadMode_ConsumableLines(d.cons, lines)
                lines[#lines + 1] = " "
            end

        elseif view == "missing" then
            -- quests I am on that he is not: did he never pick them up, or is he already done?
            local shown = {}
            for _, q in ipairs(missing) do
                if Matches(q, filter) then shown[#shown + 1] = q end
            end
            lines[#lines + 1] = "|cffe8c36aYou have, " .. name .. " does not|r  |cff9aa0a6" .. #missing
                .. ((filter and filter ~= "") and (", " .. #shown .. " match the search") or "") .. "|r" .. progress
            if not d.done then
                lines[#lines + 1] = GREY .. "Waiting for his quest list...|r"
            elseif #missing == 0 then
                lines[#lines + 1] = GOOD .. "Nothing missing. He has every quest you have.|r"
            else
                table.sort(shown, function(a, b)
                    if a.level ~= b.level then return a.level < b.level end
                    return a.title < b.title
                end)
                local waited = now - (d.checkAsked or now)
                for _, q in ipairs(shown) do
                    local state = d.check and d.check[q.id]
                    local note
                    if state == true then note = GOOD .. "already done|r"
                    elseif state == false then note = BAD .. "not picked up|r"
                    elseif waited > 4 then note = GREY .. "unknown. " .. name .. " needs DadMode 1.16 or newer|r"
                    else note = GREY .. "checking...|r" end
                    lines[#lines + 1] = QuestLine(q) .. "  " .. note
                end
            end
            lines[#lines + 1] = " "

        elseif view == "dungeon" then
            if DadMode_DungeonLines then
                DadMode_DungeonLines(name, d, list, has, myQuests, filter, lines, progress)
            end
            lines[#lines + 1] = " "

        else    -- "quests"
            local shown = {}
            for _, q in ipairs(list) do
                if Matches(q, filter) then shown[#shown + 1] = q end
            end
            lines[#lines + 1] = "|cffe8c36a" .. name .. "'s quests|r  |cff9aa0a6" .. #list
                .. ((filter and filter ~= "") and (", " .. #shown .. " match the search") or "") .. "|r" .. progress
            table.sort(shown, function(a, b)
                if a.done ~= b.done then return a.done end
                if a.level ~= b.level then return a.level < b.level end
                return a.title < b.title
            end)
            for _, q in ipairs(shown) do
                local mine = myQuests[q.id]
                lines[#lines + 1] = " "
                lines[#lines + 1] = QuestLine(q)
                    .. (q.done and "  |cff6fcf97ready to hand in|r" or "")
                    .. (mine and "  |cff6fb1e8you have it too|r" or ("  |cff9aa0a6only " .. name .. "|r"))
                for _, o in ipairs(q.objs) do
                    local finished = o:sub(1, 1) == "+"
                    lines[#lines + 1] = "    " .. (finished and "|cff6fcf97" or "|cff9aa0a6") .. o:sub(2) .. "|r"
                end
                if mine then
                    local parts = {}
                    for _, o in ipairs(mine.objs) do parts[#parts + 1] = o:sub(2) end
                    lines[#lines + 1] = "    |cff6fb1e8you: " .. (mine.done and "ready to hand in" or (#parts > 0 and table.concat(parts, ", ") or "not done")) .. "|r"
                end
                if q.done then
                    local who, zone = DadMode_TurnIn(q.id)
                    if who then
                        lines[#lines + 1] = "    |cffe8c36ahand in: " .. who .. (zone and (", " .. zone) or "") .. "|r"
                    end
                end
                local nextName, nextLevel = DadMode_NextInChain(q.id)
                if nextName then
                    lines[#lines + 1] = "    |cff6fb1e8then: " .. nextName .. (nextLevel and (" [" .. nextLevel .. "]") or "") .. "|r"
                end
            end
            lines[#lines + 1] = " "
        end
    end
    if not any then
        if now - questAsked < 4 then
            lines[1] = "|cff9aa0a6Asking...|r"
        else
            lines[1] = "|cffeb7a7aNo answer.|r"
            lines[2] = "|cff9aa0a6Dad needs DadMode 1.5 or newer, and must not be set up as a guide.|r"
        end
    end
    -- who runs which DadMode, at the bottom of the overview
    if view == "overview" and DadMode_VersionLines then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffe8c36aDadMode in this party|r"
        for _, line in ipairs(DadMode_VersionLines()) do lines[#lines + 1] = line end
    end
    questWin.text:SetText(table.concat(lines, "\n"))
    questWin.content:SetHeight((questWin.text:GetStringHeight() or 100) + 20)
end

-- The window asks again by itself now and then. Not while a list is still coming in, and not
-- while somebody is typing in the search box: both made the list jump around.
local function AutoRefreshDue()
    if not (questWin and questWin:IsShown()) then return false end
    if GetTime() - questAsked < 60 then return false end
    for _, d in pairs(questData) do
        if d.pending then return false end
    end
    if questWin.search and questWin.search.typing then return false end
    return true
end
DadMode_AutoRefreshDue = AutoRefreshDue

local function AskQuests()
    questAsked = GetTime()
    if DadMode_AskVersions then pcall(DadMode_AskVersions) end
    local ok, why = Tell("QREQ")
    if not ok then Print("|cffeb7a7aCould not ask:|r " .. tostring(why)) end
    RenderQuests()
    if C_Timer and C_Timer.After then C_Timer.After(4.2, RenderQuests) end
end

DadMode_AskQuests = AskQuests
DadMode_RenderQuests = RenderQuests

function DadMode_ReceiveQuestData(sender, text)
    local m = (not IsMe(sender)) and Member(sender) or nil
    if not m then return end
    if text:sub(1, 3) == "CN:" then
        local d = questData[m.name] or { list = {}, done = false }
        questData[m.name] = d
        d.cons = {}
        for id, kind, count in text:sub(4):gmatch("(%d+):(%d+)=(%d+)") do
            d.cons[#d.cons + 1] = { id = tonumber(id), kind = tonumber(kind), count = tonumber(count) }
        end
    elseif text:sub(1, 3) == "GR:" then
        local d = questData[m.name] or { list = {}, done = false }
        questData[m.name] = d
        d.gear, d.gearAt = {}, GetTime()
        for slot, id, dur in text:sub(4):gmatch("(%d+)=(%d+):(-?%d+)") do
            d.gear[tonumber(slot)] = { id = tonumber(id), dur = tonumber(dur) }
        end
    elseif text:sub(1, 4) == "BGS:" then
        local d = questData[m.name] or { list = {}, done = false }
        questData[m.name] = d
        d.bagGear = {}
    elseif text:sub(1, 3) == "BG:" then
        local d = questData[m.name]
        if d and d.bagGear then
            for item in text:sub(4):gmatch("item:[%-%d:]+") do
                if #d.bagGear < 16 then d.bagGear[#d.bagGear + 1] = item end
            end
        end
    elseif text:sub(1, 3) == "GL:" then
        local d = questData[m.name]
        if d and d.gear then
            for slot, item in text:sub(4):gmatch("(%d+)=(item:[%-%d:]+)") do
                local g = d.gear[tonumber(slot)]
                if g then g.link = item end
            end
        end
    elseif text:sub(1, 3) == "SS:" then
        local d = questData[m.name] or { list = {}, done = false }
        questData[m.name] = d
        d.stats = {}
        for k, v in text:sub(4):gmatch("(%a+)=(-?%d+)") do d.stats[k] = tonumber(v) end
    elseif text:sub(1, 3) == "ST:" then
        local d = questData[m.name] or { list = {}, done = false }
        questData[m.name] = d
        d.st = d.st or {}
        d.at = GetTime()
        for pair in text:sub(4):gmatch("[^~]+") do
            local k, v = pair:match("^(%w+)=(.*)$")
            if k then d.st[k] = tonumber(v) or v end
        end
        -- these are only sent when true, so clear them when a new numbers message arrives without them
        if text:find("lv=", 1, true) then
            for _, k in ipairs({ "tp", "hcd" }) do
                if not text:find(k .. "=", 1, true) then d.st[k] = nil end
            end
        elseif not text:find("tg=", 1, true) then
            d.st.tg = nil
        end
    elseif text:sub(1, 3) == "QS:" then
        local d = questData[m.name] or { list = {}, done = false }
        questData[m.name] = d
        d.list = d.list or {}
        -- the list on screen stays until the new one is complete
        d.pending = { list = {}, expect = tonumber(text:sub(4)) or 0, at = GetTime() }
        d.at = GetTime()
    elseif text:sub(1, 3) == "QD:" then
        local d = questData[m.name]
        if d then
            d.check = d.check or {}
            for id, v in text:sub(4):gmatch("(%d+)=(%d)") do d.check[tonumber(id)] = (v == "1") end
        end
    elseif text == "QE" then
        if questData[m.name] then
            local d = questData[m.name]
            if d.pending then d.list, d.pending = d.pending.list, nil end
            d.done, d.partial = true, nil
            if db.helper then
                local who = m.name
                pcall(AskDone, who)
                if C_Timer and C_Timer.After then C_Timer.After(4.5, function() DadMode_RenderQuests() end) end
            end
        end
    elseif text:sub(1, 2) == "Q:" and questData[m.name] then
        for rec in text:sub(3):gmatch("[^%^]+") do
            local id, level, done, title, objs = rec:match("^(%d+)~(%d+)~(%d)~([^~]*)~?(.*)$")
            if id then
                local q = { id = tonumber(id), level = tonumber(level), done = done == "1", title = title, objs = {} }
                for o in objs:gmatch("[^;]+") do q.objs[#q.objs + 1] = o end
                local d = questData[m.name]
                table.insert(d.pending and d.pending.list or d.list, q)
            end
        end
    end
    RenderQuests()
end

function DadMode_CreateQuestWindow()
    questWin = CreateFrame("Frame", "DadModeQuests", UIParent)
    questWin:SetSize(460, 540)
    questWin:SetPoint("CENTER", 220, 0)
    questWin:SetFrameStrata("HIGH")
    questWin:SetMovable(true)
    questWin:SetClampedToScreen(true)
    questWin:EnableMouse(true)
    questWin:RegisterForDrag("LeftButton")
    questWin:SetScript("OnDragStart", questWin.StartMoving)
    questWin:SetScript("OnDragStop", questWin.StopMovingOrSizing)
    Tex(questWin, "BACKGROUND", 0.07, 0.08, 0.10, 0.97):SetAllPoints()
    local title = questWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cffe8c36aHow is dad doing|r")

    local close = BigButton(questWin, 60, 22, function() questWin:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -6)
    close.label:SetText("Close")
    local again = BigButton(questWin, 70, 22, function() AskQuests() end)
    again:SetPoint("RIGHT", close, "LEFT", -6, 0)
    again.label:SetText("Refresh")
    questWin.view = "overview"
    questWin.filter = ""
    questWin.dungeon = false          -- the dungeon picked on the Dungeon tab
    for _, b in ipairs({ close, again }) do
        pcall(function()
            local font, _, flags = b.label:GetFont()
            if font then b.label:SetFont(font, 12, flags) end
        end)
    end

    -- Tabs: one thing at a time
    local TABS = { { "overview", "Overview" }, { "quests", "Quests" }, { "missing", "Missing" }, { "dungeon", "Dungeon" }, { "gear", "Gear" } }
    questWin.tabs = {}
    local function SetView(view)
        questWin.view = view
        for key, tab in pairs(questWin.tabs) do
            local on = (key == view)
            tab.bg:SetColorTexture(on and 0.40 or 0.16, on and 0.33 or 0.18, on and 0.14 or 0.22, 1)
        end
        -- the search box belongs to the two quest lists
        local searching = (view == "quests" or view == "missing" or (view == "dungeon" and questWin.dungeon and true or false))
        if questWin.search then
            questWin.search:SetShown(searching)
            questWin.wipe:SetShown(searching)
        end
        if questWin.scroll then
            questWin.scroll:ClearAllPoints()
            questWin.scroll:SetPoint("TOPLEFT", 12, searching and -92 or -64)
            questWin.scroll:SetPoint("BOTTOMRIGHT", -12, 12)
            questWin.scroll:SetVerticalScroll(0)
        end
        DadMode_RenderQuests()
    end
    questWin.SetView = SetView
    for i, def in ipairs(TABS) do
        local tab = BigButton(questWin, 70, 22, function() SetView(def[1]) end)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 74, -36)
        tab.label:SetText(def[2])
        pcall(function()
            local font, _, flags = tab.label:GetFont()
            if font then tab.label:SetFont(font, 12, flags) end
        end)
        questWin.tabs[def[1]] = tab
    end

    -- Search box: type part of a quest name or objective
    local search = CreateFrame("EditBox", nil, questWin)
    questWin.search = search
    search:SetPoint("TOPLEFT", 12, -64)
    search:SetPoint("TOPRIGHT", -38, -64)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    pcall(function() search:SetFontObject("GameFontHighlight") end)
    pcall(function() search:SetTextInsets(6, 6, 0, 0) end)
    search:SetMaxLetters(40)
    Tex(search, "BACKGROUND", 0.14, 0.15, 0.18, 1):SetAllPoints()
    search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    search.hint:SetPoint("LEFT", 6, 0)
    search.hint:SetText("Search his quests...")
    local function ApplySearch(text)
        text = (type(text) == "string" and text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        questWin.filter = text
        if text == "" then search.hint:Show() else search.hint:Hide() end
        if questWin.scroll then questWin.scroll:SetVerticalScroll(0) end
        DadMode_RenderQuests()
    end
    questWin.ApplySearch = ApplySearch
    search:SetScript("OnTextChanged", function(self) ApplySearch(self:GetText()) end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function(self) self.typing = true end)
    search:SetScript("OnEditFocusLost", function(self) self.typing = false end)
    search.typing = false
    local wipe = BigButton(questWin, 22, 22, function()
        search:SetText("")
        search:ClearFocus()
        ApplySearch("")
    end)
    wipe:SetPoint("TOPRIGHT", -12, -64)
    questWin.wipe = wipe
    wipe.label:SetText("x")
    pcall(function()
        local font, _, flags = wipe.label:GetFont()
        if font then wipe.label:SetFont(font, 12, flags) end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, questWin)
    questWin.scroll = scroll
    scroll:SetPoint("TOPLEFT", 12, -64)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.min(math.max((self:GetVerticalScroll() or 0) - delta * 44, 0), range))
    end)
    questWin.content = CreateFrame("Frame", nil, scroll)
    questWin.content:SetSize(436, 10)
    scroll:SetScrollChild(questWin.content)
    questWin.text = questWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    questWin.text:SetPoint("TOPLEFT", 4, -4)
    questWin.text:SetWidth(428)
    questWin.text:SetJustifyH("LEFT")
    questWin.text:SetJustifyV("TOP")
    questWin.text:SetSpacing(2)

    -- Item names in the gear list are links: the mouse over one shows the game's own tooltip
    pcall(function()
        local c = questWin.content
        c:SetHyperlinksEnabled(true)
        -- links need the mouse; keep the window draggable from the text as well
        c:EnableMouse(true)
        c:RegisterForDrag("LeftButton")
        c:SetScript("OnDragStart", function() questWin:StartMoving() end)
        c:SetScript("OnDragStop", function() questWin:StopMovingOrSizing() end)
        c:SetScript("OnHyperlinkEnter", function(self, link)
            if not GameTooltip or type(link) ~= "string" or link:sub(1, 8) == "dadmode:" then return end
            GameTooltip:SetOwner(questWin, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            if ok then GameTooltip:Show() else GameTooltip:Hide() end
        end)
        c:SetScript("OnHyperlinkLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        c:SetScript("OnHyperlinkClick", function(self, link, text, button)
            if type(link) == "string" and link:sub(1, 13) == "dadmode:wear:" then
                local who, item = link:sub(14):match("^([^:]+):(item:[%-%d:]+)$")
                if who and DadMode_TellWear then DadMode_TellWear(who, item) end
            elseif type(link) == "string" and link:sub(1, 16) == "dadmode:dungeon:" then
                -- a dungeon name on the Dungeon tab was clicked (0 = back to the list)
                local id = tonumber(link:sub(17))
                questWin.dungeon = (id and id > 0) and id or false
                if questWin.dungeon and db.helper then
                    for name in pairs(questData) do pcall(DadMode_AskDone, name) end
                end
                questWin.SetView("dungeon")
            elseif type(SetItemRef) == "function" then
                pcall(SetItemRef, link, text, button)
            end
        end)
    end)

    -- Drag the corner for a wider or taller window. The text re-wraps to the new width.
    local function Fit()
        local w = questWin:GetWidth() or 460
        if w < 100 then return end
        questWin.content:SetWidth(w - 24)
        questWin.text:SetWidth(w - 32)
    end
    pcall(function()
        questWin:SetResizable(true)
        if questWin.SetResizeBounds then questWin:SetResizeBounds(400, 240, 1000, 1100)
        elseif questWin.SetMinResize then questWin:SetMinResize(400, 240) end
    end)
    if db.questSize then questWin:SetSize(db.questSize[1], db.questSize[2]) end
    local grip = MakeGrip(questWin)
    questWin.grip = grip
    grip:SetScript("OnMouseDown", function() grip.sizing = true; questWin:StartSizing("BOTTOMRIGHT") end)
    local function StopSizing()
        if not grip.sizing then return end
        grip.sizing = nil
        questWin:StopMovingOrSizing()
        local w, h = questWin:GetWidth(), questWin:GetHeight()
        if type(w) == "number" and type(h) == "number" and w > 100 and h > 100 then db.questSize = { w, h } end
        Fit()
    end
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)
    questWin:SetScript("OnSizeChanged", Fit)
    Fit()
    SetView("overview")
    questWin:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "DadModeQuests") end
end

function OpenQuests()
    if not questWin then return end
    questWin:Show()
    AskQuests()
end

---------------------------------------------------------------------------
-- Follow button: one click and the character walks after the person
---------------------------------------------------------------------------

local followWho, followName, followUnit

-- Is the caller close enough for the game's follow to work? Unknown counts as yes.
local function CanFollowNow()
    if not followUnit then return true end
    local dist = Locate(followUnit)
    if dist then return dist <= FOLLOW_RANGE end
    -- no positions (dungeon, or the other one is on another continent): ask if he is in sight
    if type(UnitIsVisible) == "function" then
        local ok, seen = pcall(UnitIsVisible, followUnit)
        if ok and Usable(seen, "boolean") then return seen end
    end
    return true
end
DadMode_CanFollowNow = CanFollowNow

-- The person who is calling right now, otherwise the first picked person in the party
function DadMode_FollowTarget()
    local now, list = GetTime(), Party()
    for _, m in ipairs(list) do
        if pings[m.name] and pings[m.name] > now then return m end
    end
    for _, m in ipairs(list) do
        if db.marked[m.name] then return m end
    end
end

-- While the person the button follows is calling, the button flashes so it can not be missed.
-- Only colour and text change here: the game allows that during a fight too.
function DadMode_PulseFollow()
    if not followName then return end
    local now = GetTime()
    if pings[followName] and pings[followName] > now and CanFollowNow() then
        local bright = math.sin(now * 8) > 0
        if bright then
            followBtn.bg:SetColorTexture(0.95, 0.95, 0.95, 1)
            followBtn.label:SetTextColor(0.05, 0.25, 0.12)
        else
            followBtn.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95)
            followBtn.label:SetTextColor(1, 1, 1)
        end
        followBtn.label:SetText("CLICK TO FOLLOW " .. followName)
        followBtn.pulsing = true
    elseif followBtn.pulsing then
        followBtn.pulsing = false
        followBtn.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95)
        followBtn.label:SetTextColor(1, 1, 1)
        followBtn.label:SetText("FOLLOW " .. followName)
    end
end

function UpdateFollow()
    if not followBtn then return end
    local m = (db.enabled and db.follow) and DadMode_FollowTarget() or nil
    local who = m and (m.unit .. ":" .. m.name) or nil
    if who ~= followWho and not InFight() then     -- the game does not let the target change during a fight
        followWho = who
        followName = m and m.name or nil
        followUnit = m and m.unit or nil
        followBtn.pulsing = false
        if who then
            followBtn:SetAttribute("type", "macro")
            followBtn:SetAttribute("macrotext", "/follow " .. m.unit)
            followBtn.label:SetText("FOLLOW " .. m.name)
            followBtn.label:SetTextColor(1, 1, 1)
            followBtn.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95)
            followBtn:Show()
        else
            followBtn:Hide()
        end
    end
    DadMode_PulseFollow()
end

function DadMode_CreateFollow()
    followBtn = CreateFrame("Button", "DadModeFollow", UIParent, "SecureActionButtonTemplate")
    followBtn:SetSize(240, 46)
    followBtn:SetFrameStrata("MEDIUM")
    followBtn:SetMovable(true)
    followBtn:SetClampedToScreen(true)
    followBtn:RegisterForClicks("AnyUp", "AnyDown")
    followBtn:RegisterForDrag("LeftButton")
    if db.followPos then
        followBtn:SetPoint(db.followPos[1], UIParent, db.followPos[2], db.followPos[3], db.followPos[4])
    else
        followBtn:SetPoint("TOP", UIParent, "TOP", 0, -330)
    end
    followBtn:SetScript("OnDragStart", function(self)
        if moving and not InFight() then
            self.dragging = true
            self:StartMoving()
        end
    end)
    followBtn:SetScript("OnDragStop", function(self)
        if not self.dragging or InFight() then return end
        self.dragging = false
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        db.followPos = { point, rel, x, y }
    end)
    followBtn.bg = Tex(followBtn, "BACKGROUND", 0.16, 0.40, 0.27, 0.95)
    followBtn.bg:SetAllPoints()
    followBtn.label = followBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    followBtn.label:SetPoint("CENTER")
    followBtn.label:SetTextColor(1, 1, 1)
    followBtn:SetScript("OnEnter", function(self)
        if not self.pulsing then self.bg:SetColorTexture(0.22, 0.54, 0.36, 1) end
    end)
    followBtn:SetScript("OnLeave", function(self)
        if not self.pulsing then self.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95) end
    end)
    followBtn:Hide()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

function DadMode_CreateBar()
    bar = CreateFrame("Frame", "DadModeBar", UIParent)
    bar:SetSize(160, 150)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    if db.pos then
        bar:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        db.pos = { point, rel, x, y }
    end)
    bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.hint:SetPoint("BOTTOM", bar, "TOP", 0, 4)
    bar.hint:SetText("Drag the arrows and the green button, then press Lock arrows")
    bar.hint:Hide()
    bar:Hide()

    alertFrame = CreateFrame("Frame", nil, UIParent)
    alertFrame:SetSize(900, 120)
    alertFrame:SetPoint("CENTER", 0, 220)
    alertFrame:SetFrameStrata("HIGH")
    alertFrame.text = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    alertFrame.text:SetPoint("TOP", 0, -6)
    alertFrame.text:SetWidth(900)
    alertFrame.hint = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alertFrame.hint:SetPoint("BOTTOM", 0, 6)
    alertFrame.hint:SetText("|cff9aa0a6click this text to clear it|r")
    alertFrame:EnableMouse(true)
    alertFrame:SetScript("OnMouseDown", function() Dismiss() end)
    pcall(function()
        local font = alertFrame.text:GetFont()
        if font then alertFrame.text:SetFont(font, 34, "THICKOUTLINE") end
    end)
    alertFrame:Hide()

    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.05 then return end
        elapsed = 0
        if alertFrame:IsShown() and GetTime() > (alertFrame.hideAt or 0) then alertFrame:Hide() end
        pcall(UpdateFollow)
        pcall(UpdateHelperStatus)
        pcall(PumpOutbox)
        if DadMode_ExtrasTick then pcall(DadMode_ExtrasTick) end
        if DadMode_WearTick then pcall(DadMode_WearTick) end
        if AutoRefreshDue() then pcall(DadMode_AskQuests) end
        local ok, err = pcall(UpdateArrows)
        if not ok and not bar.errorShown then
            bar.errorShown = true
            Print("Arrow error, please report this to the addon author: " .. tostring(err))
        end
    end)
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
-- Left click: the main window for your role. Right click: the helper buttons.

local minimapButton, minimapLib

local function MinimapClick(button)
    if button == "RightButton" then
        DadMode_OpenSettings()       -- settings. It used to switch role, which was too easy to do by accident
    elseif db.helper then
        -- the guide's own window: the bar with the commands. Click again to put it away.
        if not helper then return end
        if InCombatLockdown and InCombatLockdown() then
            Print("The guide bar can not be shown or hidden during a fight.")
        elseif helper:IsShown() then
            helper:Hide()
            db.helperHidden = true
            Print("Guide bar hidden. Left click the minimap button to bring it back.")
        else
            helper:Show()
            db.helperHidden = nil
        end
    else
        OpenPicker()                 -- dad: pick who to find and follow
    end
end

DadMode_MinimapClick = MinimapClick
local function MinimapTooltip(tt)
    tt:AddLine("DadMode " .. VERSION)
    if db.helper then
        tt:AddLine("Left click: show or hide the guide bar", 0.9, 0.9, 0.9)
    else
        tt:AddLine("Left click: pick who to find and follow", 0.9, 0.9, 0.9)
    end
    tt:AddLine("Right click: settings", 0.9, 0.9, 0.9)
    tt:AddLine("Drag: move this button", 0.6, 0.63, 0.65)
end

local function PlaceMinimapButton()
    local angle = math.rad(db.minimap.angle or 215)
    local radius = ((Minimap:GetWidth() or 140) / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function DadMode_CreateMinimapButton()
    db.minimap = db.minimap or {}

    -- If another addon brought the usual minimap button library, use it: then button collectors
    -- such as MinimapButtonButton treat this button like every other addon's.
    local ok = pcall(function()
        local ldb = LibStub("LibDataBroker-1.1")
        local icon = LibStub("LibDBIcon-1.0")
        local obj = ldb:NewDataObject("DadMode", {
            type = "launcher", text = "DadMode", icon = ARROW,
            iconR = 0.91, iconG = 0.76, iconB = 0.42,
            OnClick = function(_, button) MinimapClick(button) end,
            OnTooltipShow = function(tt) MinimapTooltip(tt) end,
        })
        icon:Register("DadMode", obj, db.minimap)
        minimapLib = icon
    end)
    if ok and minimapLib then return end

    -- Otherwise a plain button of our own
    if not Minimap then return end
    local b = CreateFrame("Button", "DadModeMinimapButton", Minimap)
    minimapButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ARROW)
    icon:SetVertexColor(0.91, 0.76, 0.42)
    icon:SetSize(17, 17)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, button) MinimapClick(button) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        MinimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale() or 1
            if mx and px then
                db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
                PlaceMinimapButton()
            end
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceMinimapButton()
    if db.minimap.hide then b:Hide() end
end

local ToggleMinimapButton
function ToggleMinimapButton()
    db.minimap = db.minimap or {}
    db.minimap.hide = not db.minimap.hide
    if minimapLib then
        if db.minimap.hide then minimapLib:Hide("DadMode") else minimapLib:Show("DadMode") end
    elseif minimapButton then
        if db.minimap.hide then minimapButton:Hide() else minimapButton:Show() end
    end
    Print(db.minimap.hide and "Minimap button hidden. /dadmode minimap brings it back." or "Minimap button shown.")
end
DadMode_ToggleMinimapButton = ToggleMinimapButton

---------------------------------------------------------------------------
-- Settings page in the game's own Options window (Options > AddOns > DadMode)
---------------------------------------------------------------------------

local optionsCategory, optionsPanel

-- Makes every DadMode window bigger or smaller. The bars with marker buttons can not be
-- resized during a fight, so those wait until it is over.
local function ApplyScale()
    local base = SCALES[db.scale or 3] or 1
    if picker then picker:SetScale(WindowScale("picker")) end
    for _, f in ipairs({ questWin, roleWin }) do
        if f then f:SetScale(base) end
    end
    if not InFight() then
        if helper then helper:SetScale(WindowScale("helper")) end
        if followBtn then followBtn:SetScale(base) end
    end
end

-- Back to the sizes the addon came with
local function ResetSizes()
    db.winScale, db.questSize, db.scale = nil, nil, 3
    if questWin then questWin:SetSize(460, 540) end
    ApplyScale()
    Print("Window sizes are back to normal." .. (InFight() and " The guide bar follows after the fight." or ""))
end

local function RefreshOptions()
    if not optionsPanel then return end
    for _, row in ipairs(optionsPanel.rows) do row.button.label:SetText(row.text()) end
end

function DadMode_CreateOptions()
    local panel = CreateFrame("Frame", "DadModeOptions", UIParent)
    panel.name = "DadMode"
    panel:Hide()
    optionsPanel = panel
    panel.rows = {}

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DadMode  |cff9aa0a6" .. VERSION .. "|r")

    local y = -56
    local function Row(label, text, onClick)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 16, y - 5)
        fs:SetText(label)
        local b = BigButton(panel, 260, 26, function()
            onClick()
            RefreshOptions()
            if RefreshPicker then RefreshPicker() end
        end)
        b:SetPoint("TOPLEFT", 280, y)
        pcall(function()
            local font, _, flags = b.label:GetFont()
            if font then b.label:SetFont(font, 12, flags) end
        end)
        panel.rows[#panel.rows + 1] = { button = b, text = text }
        y = y - 34
    end
    local function SoundName(kind)
        return (SOUNDS[db.sounds[kind] or DEFAULT_SOUND[kind]] or SOUNDS[1]).name
    end

    Row("Who uses this computer",
        function() return db.helper and "A guide  (click to change)" or "Someone being guided  (click to change)" end,
        function() DadMode_SetRole(not db.helper) end)
    Row("Show calls from the party on my screen",
        function() return db.alerts and "On" or "Off" end,
        function() db.alerts = not db.alerts end)
    Row("Sound when someone calls",
        function() return SoundName("call") end,
        function() db.sounds.call = ((db.sounds.call or DEFAULT_SOUND.call) % #SOUNDS) + 1; Beep("call", true) end)
    Row("Sound when I drift far away",
        function() return SoundName("far") end,
        function() db.sounds.far = ((db.sounds.far or DEFAULT_SOUND.far) % #SOUNDS) + 1; Beep("far", true) end)
    Row("Far-away warning",
        function() return db.farWarning and "On" or "Off" end,
        function() db.farWarning = not db.farWarning end)
    Row("Green follow button",
        function() return db.follow and "Shown" or "Hidden" end,
        function() db.follow = not db.follow end)
    Row("Arrow size",
        function() return (ARROW_SIZES[db.arrowSize or 2] or ARROW_SIZES[2])[1] end,
        function() db.arrowSize = (db.arrowSize or 2) % #ARROW_SIZES + 1 end)
    Row("Window size",
        function() return math.floor((SCALES[db.scale or 3] or 1) * 100 + 0.5) .. "%" end,
        function() db.scale = (db.scale or 3) % #SCALES + 1; ApplyScale() end)
    Row("Reset window sizes",
        function() return "Back to normal size" end,
        function() ResetSizes() end)
    Row("Arrows and follow button",
        function() return moving and "Unlocked: drag them, then click here" or "Locked  (click to move them)" end,
        function() moving = not moving; if bar then bar:EnableMouse(moving) end end)
    Row("Guide bar layout",
        function() return db.helperCols == 1 and "1 column" or "2 columns" end,
        function()
            if InFight() then
                Print("Not during a fight. Try again after.")
                return
            end
            db.helperCols = (db.helperCols == 1) and 2 or 1
            if helper and helper.Layout then helper.Layout() end
        end)
    Row("Try it: show a call on my own screen",
        function() return "Test a call" end,
        function() DadMode_TestCall() end)
    Row("Compare items with his gear (tooltips and drops)",
        function() return db.compare == false and "Off" or "On" end,
        function() db.compare = (db.compare == false) end)
    Row("Minimap button",
        function() return (db.minimap and db.minimap.hide) and "Hidden" or "Shown" end,
        function() DadMode_ToggleMinimapButton() end)

    panel:SetScript("OnShow", RefreshOptions)

    -- Hand the page to the game. If this game version has no such window, the settings stay
    -- reachable from the small DadMode window instead.
    pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "DadMode")
            Settings.RegisterAddOnCategory(category)
            optionsCategory = category
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
            optionsCategory = panel
        end
    end)
end

-- Opens the settings page. Falls back to the small window with its options unfolded.
local function OpenSettings()
    if optionsCategory and not InFight() then
        local ok = pcall(function()
            if Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(type(optionsCategory.GetID) == "function" and optionsCategory:GetID() or optionsCategory)
            else
                InterfaceOptionsFrame_OpenToCategory(optionsCategory)
            end
        end)
        if ok then
            if picker then picker:Hide() end
            return
        end
    end
    OpenPicker(true)
end
DadMode_OpenSettings = OpenSettings
function DadMode_HasOptionsPage() return optionsCategory ~= nil end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

handlers.ADDON_LOADED = function(name)
    if name ~= "DadMode" then return end
    local fresh = (DadModeDB == nil)
    DadModeDB = DadModeDB or {}
    db = DadModeDB
    -- A computer that already used DadMode keeps its role and is not asked
    if db.roleChosen == nil then db.roleChosen = not fresh end
    db.marked = db.marked or {}
    if db.enabled == nil then db.enabled = true end
    if db.alerts == nil then db.alerts = true end
    if db.farWarning == nil then db.farWarning = true end
    if db.helper == nil then db.helper = false end
    if db.follow == nil then db.follow = true end
    db.sounds = db.sounds or {}
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end

handlers.PLAYER_LOGIN = function()
    local ok, err = pcall(function()
        DadMode_CreateBar()
        DadMode_CreatePicker()
        DadMode_CreateHelper()
        DadMode_CreateFollow()
        DadMode_CreateQuestWindow()
        DadMode_CreateMinimapButton()
        DadMode_CreateRoleWindow()
        DadMode_CreateOptions()
        if DadMode_HookTooltips then DadMode_HookTooltips() end
        ApplyScale()
        if not db.roleChosen then roleWin:Show() end
    end)
    if not ok then Print("Could not start, please report this to the addon author: " .. tostring(err)) end
end

local lastPickHint = -9999

handlers.TAXIMAP_OPENED = function()
    pcall(FlightHint)
end

handlers.GROUP_ROSTER_UPDATE = function()
    if not picker then return end
    local list = Party()
    if picker:IsShown() then RefreshPicker() end
    if #list == 0 or not db.enabled or db.helper then return end      -- helpers are never asked
    for _, m in ipairs(list) do
        if db.marked[m.name] then return end                           -- someone here is picked: nothing to do
    end
    if next(db.marked) == nil and not db.askedOnce then
        -- He has never picked anyone: open the window, this one time only
        db.askedOnce = true
        OpenPicker(false)
    elseif GetTime() - lastPickHint > 600 then
        -- Otherwise just one quiet line in chat, at most every 10 minutes
        lastPickHint = GetTime()
        Print("Nobody in this party is picked, so there are no arrows. Click the gold arrow on the minimap to pick someone.")
    end
end

-- A fight is about to start. The game still allows moving these frames for this one moment,
-- so anything being dragged is let go now. Afterwards it would be blocked and stick to the mouse.
-- Item names for the gear list load a moment after they are first asked for
handlers.GET_ITEM_INFO_RECEIVED = function()
    if questWin and questWin:IsShown() and (questWin.view == "gear" or questWin.view == "quests") and not questWin.redraw then
        questWin.redraw = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function()
                questWin.redraw = false
                DadMode_RenderQuests()
            end)
        else
            questWin.redraw = false
            DadMode_RenderQuests()
        end
    end
end

handlers.PLAYER_REGEN_ENABLED = function()
    pcall(ApplyScale)
end

handlers.PLAYER_REGEN_DISABLED = function()
    if helper and helper.grip and helper.grip.Stop then helper.grip.Stop() end
    for _, f in ipairs({ helper, followBtn }) do
        if f and f.dragging then
            f.dragging = false
            f:StopMovingOrSizing()
            local point, _, rel, x, y = f:GetPoint()
            if f == helper then db.helperPos = { point, rel, x, y } else db.followPos = { point, rel, x, y } end
        end
    end
end

handlers.CHAT_MSG_ADDON = function(prefix, text, _, sender)
    if not Usable(prefix, "string") or prefix ~= PREFIX then return end
    if not Usable(text, "string") or not Usable(sender, "string") then return end
    if DadMode_ExtraMessage and DadMode_ExtraMessage(text, sender) then return end
    if DadMode_WearMessage and DadMode_WearMessage(text, sender) then return end
    local body = text:match("^PING:(.*)$")
    if body then
        ReceivePing(sender, body)
    elseif text == "CLEAR" then
        ReceiveClear(sender)
    elseif text == "WPC" or text:sub(1, 3) == "WP:" then
        DadMode_ReceiveWaypoint(sender, text)
    elseif text == "WPHERE" then
        local m = (not IsMe(sender)) and Member(sender) or nil
        if m then
            wpOut = false
            Print("|cff6fcf97" .. m.name .. " reached your marker.|r")
        end
    elseif text == "WPOK" or text == "WPNO" then
        local m = (not IsMe(sender)) and Member(sender) or nil
        if m and GetTime() - lastSent < 30 then
            wpOut = (text == "WPOK")
            Print(text == "WPOK" and ("|cff6fcf97" .. m.name .. " has your waypoint on the map.|r")
                or ("|cffeb7a7a" .. m.name .. " could not get the waypoint.|r Not possible in dungeons, or the map does not allow pins."))
        end
    elseif text:sub(1, 3) == "TS:" then
        local m = (not IsMe(sender)) and Member(sender) or nil
        if m then
            DadMode_ReceiveStops(text:sub(4))
            travel.at = 0                      -- work out the route again with the new spots
        end
    elseif text:sub(1, 3) == "QC:" then
        local m = (not IsMe(sender)) and Member(sender) or nil
        if m and not db.helper then pcall(DadMode_AnswerDone, text:sub(4)) end
    elseif text == "QREQ" then
        local m = (not IsMe(sender)) and Member(sender) or nil
        if m and not db.helper then DadMode_SendQuests() end
    elseif text == "QE" or text:sub(1, 3) == "QS:" or text:sub(1, 3) == "ST:" or text:sub(1, 3) == "QD:" or text:sub(1, 4) == "BGS:" or text:sub(1, 3) == "BG:" or text:sub(1, 3) == "GR:" or text:sub(1, 3) == "GL:" or text:sub(1, 3) == "SS:" or text:sub(1, 3) == "CN:" or text:sub(1, 2) == "Q:" then
        DadMode_ReceiveQuestData(sender, text)
    elseif text:match("^VER:") then
        local m = Member(sender)
        if m then peerVersion[m.name] = text:sub(5, 20) end
    elseif text == "ACK" or text == "HERE" or text == "MUTED" then
        DadMode_ReceiveReply(sender, text)
    end
end

handlers.CHAT_MSG_PARTY = ChatPing
handlers.CHAT_MSG_PARTY_LEADER = ChatPing
handlers.CHAT_MSG_WHISPER = ChatPing

frame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then
        local ok, err = pcall(h, ...)
        if not ok then Print("Error, please report this to the addon author: " .. tostring(err)) end
    end
end)
---------------------------------------------------------------------------
-- Dungeon tab: every quest Questie knows for a dungeon, and where he stands on each
---------------------------------------------------------------------------
do
    local questsFor = {}        -- dungeon area id -> sorted list of quest ids

    local function Modules()
        if type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return nil end
        local ok, QDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
        local okZ, ZDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
        if not ok or type(QDB) ~= "table" or type(QDB.QueryQuestSingle) ~= "function" then return nil end
        if not okZ or type(ZDB) ~= "table" or type(ZDB.GetDungeons) ~= "function" then return nil end
        local okJ, J = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieJourney")
        return QDB, ZDB, (okJ and type(J) == "table") and J or nil
    end

    local function Field(QDB, id, field)
        local ok, v = pcall(QDB.QueryQuestSingle, id, field)
        if ok then return v end
    end

    -- Quest ids of one dungeon. Questie keeps a list per zone for this character's race and
    -- class; a dungeon can be filed under more than one area number.
    local function QuestsFor(areaId)
        if questsFor[areaId] then return questsFor[areaId] end
        local QDB, ZDB, J = Modules()
        if not QDB then return nil end
        local okD, dungeons = pcall(ZDB.GetDungeons, ZDB)
        local entry = okD and type(dungeons) == "table" and dungeons[areaId]
        if type(entry) ~= "table" then return nil end
        local areas = { [areaId] = true }
        if type(entry[2]) == "table" then
            for _, alt in ipairs(entry[2]) do areas[alt] = true end
        end
        local set = {}
        local zoneMap = J and J.zoneMap
        if type(zoneMap) == "table" then
            for area in pairs(areas) do
                if type(zoneMap[area]) == "table" then
                    for id in pairs(zoneMap[area]) do set[id] = true end
                end
            end
        elseif type(QDB.QuestPointers) == "table" then
            -- Questie has not built its lists: look through every quest once
            for id in pairs(QDB.QuestPointers) do
                local zone = Field(QDB, id, "zoneOrSort")
                if zone and areas[zone] then set[id] = true end
            end
        else
            return nil
        end
        local ids = {}
        for id in pairs(set) do
            if type(Field(QDB, id, "name")) == "string" then ids[#ids + 1] = id end
        end
        table.sort(ids)
        questsFor[areaId] = ids
        return ids
    end

    -- All dungeons that have at least one quest: { id, name, count }, sorted by name
    local function Dungeons()
        local QDB, ZDB = Modules()
        if not QDB then return nil end
        local okD, dungeons = pcall(ZDB.GetDungeons, ZDB)
        if not okD or type(dungeons) ~= "table" then return nil end
        local out = {}
        for areaId, entry in pairs(dungeons) do
            if type(areaId) == "number" and type(entry) == "table" then
                local ids = QuestsFor(areaId)
                if ids and #ids > 0 then
                    local name
                    if type(ZDB.GetLocalizedDungeonName) == "function" then
                        local okN, n = pcall(ZDB.GetLocalizedDungeonName, ZDB, areaId)
                        if okN and Usable(n, "string") and n ~= "" then name = n end
                    end
                    out[#out + 1] = { id = areaId, name = name or tostring(entry[1]), count = #ids }
                end
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end
    DadMode_Dungeons = Dungeons

    function DadMode_DungeonQuestIds()
        local id = questWin and questWin.dungeon
        if not id then return {} end
        return QuestsFor(id) or {}
    end

    -- Who gives the quest, and where
    local function StartsAt(QDB, id)
        local by = Field(QDB, id, "startedBy")
        if type(by) ~= "table" then return nil end
        local query, who
        if type(by[1]) == "table" and type(by[1][1]) == "number" then
            query, who = QDB.QueryNPCSingle, by[1][1]
        elseif type(by[2]) == "table" and type(by[2][1]) == "number" then
            query, who = QDB.QueryObjectSingle, by[2][1]
        end
        if type(query) ~= "function" then return nil end
        local ok, name = pcall(query, who, "name")
        if not ok or type(name) ~= "string" or name == "" then return nil end
        local okZ, zoneID = pcall(query, who, "zoneID")
        if okZ and type(zoneID) == "number" and zoneID > 0 and C_Map and C_Map.GetAreaInfo then
            local okA, zoneName = pcall(C_Map.GetAreaInfo, zoneID)
            if okA and Usable(zoneName, "string") and zoneName ~= "" then return name .. ", " .. zoneName end
        end
        return name
    end

    function DadMode_DungeonLines(name, d, list, has, myQuests, filter, lines, progress)
        local QDB = Modules()
        if not QDB then
            lines[#lines + 1] = "|cffe8c36aDungeon quests|r"
            lines[#lines + 1] = GREY .. "This tab needs the Questie addon on this computer.|r"
            return
        end
        local chosen = questWin.dungeon
        if not chosen then
            -- the list of dungeons to pick from. The one he stands in comes first.
            local all = Dungeons() or {}
            lines[#lines + 1] = "|cffe8c36aPick a dungeon|r  " .. GREY .. "click a name|r"
            if #all == 0 then
                lines[#lines + 1] = GREY .. "Questie has no dungeon quests ready yet. Try again in a moment.|r"
                return
            end
            local here = d.st and d.st.z
            local function Link(dg, note)
                return "|cff6fb1e8|Hdadmode:dungeon:" .. dg.id .. "|h[" .. dg.name .. "]|h|r  " .. GREY .. dg.count .. " quests" .. (note or "") .. "|r"
            end
            for _, dg in ipairs(all) do
                if here and dg.name == here then lines[#lines + 1] = Link(dg, ", " .. name .. " is here") end
            end
            for _, dg in ipairs(all) do
                if not (here and dg.name == here) then lines[#lines + 1] = Link(dg) end
            end
            return
        end

        local ids = DadMode_DungeonQuestIds()
        local title = tostring(chosen)
        for _, dg in ipairs(Dungeons() or {}) do
            if dg.id == chosen then title = dg.name end
        end
        local mine = {}
        for _, q in ipairs(list) do mine[q.id] = q end
        local rows, inLog, notTaken, finished = {}, 0, 0, 0
        for _, id in ipairs(ids) do
            local q = { id = id, title = Field(QDB, id, "name") or ("Quest " .. id), level = tonumber(Field(QDB, id, "questLevel")) or 0, objs = {} }
            if mine[id] then inLog = inLog + 1
            elseif d.check and d.check[id] == true then finished = finished + 1
            elseif d.check and d.check[id] == false then notTaken = notTaken + 1 end
            if Matches(q, filter) then rows[#rows + 1] = q end
        end
        table.sort(rows, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            return a.title < b.title
        end)
        lines[#lines + 1] = "|cffe8c36a" .. name .. " in " .. title .. "|r  " .. GREY .. #ids .. " quests|r   |cff6fb1e8|Hdadmode:dungeon:0|h[other dungeon]|h|r" .. progress
        lines[#lines + 1] = GOOD .. inLog .. " in his log|r   " .. BAD .. notTaken .. " not picked up|r   " .. GREY .. finished .. " already done|r"
            .. ((filter and filter ~= "") and (GREY .. "   " .. #rows .. " match the search|r") or "")
        local waited = GetTime() - (d.checkAsked or GetTime())
        local level = d.st and d.st.lv
        for _, q in ipairs(rows) do
            local his = mine[q.id]
            local head = (q.level > 0 and ("|cff9aa0a6[" .. q.level .. "]|r ") or "") .. q.title
            local state = d.check and d.check[q.id]
            lines[#lines + 1] = " "
            if his then
                lines[#lines + 1] = head .. "  " .. GOOD .. (his.done and "in his log, ready to hand in" or "in his log") .. "|r"
                    .. (myQuests[q.id] and "  |cff6fb1e8you have it too|r" or "")
                for _, o in ipairs(his.objs) do
                    local done = o:sub(1, 1) == "+"
                    lines[#lines + 1] = "    " .. (done and "|cff6fcf97" or "|cff9aa0a6") .. o:sub(2) .. "|r"
                end
            elseif state == true then
                lines[#lines + 1] = head .. "  " .. GREY .. "already done|r"
            elseif state == false then
                lines[#lines + 1] = head .. "  " .. BAD .. "not picked up|r" .. (myQuests[q.id] and "  |cff6fb1e8you have it|r" or "")
                local from = StartsAt(QDB, q.id)
                if from then lines[#lines + 1] = "    |cffe8c36astarts at: " .. from .. "|r" end
                local need = tonumber(Field(QDB, q.id, "requiredLevel"))
                if need and level and need > level then
                    lines[#lines + 1] = "    " .. WARN .. "needs level " .. need .. ", he is " .. level .. "|r"
                end
            elseif not d.done then
                lines[#lines + 1] = head .. "  " .. GREY .. "waiting for his quest list...|r"
            elseif waited > 4 then
                lines[#lines + 1] = head .. "  " .. GREY .. "unknown. " .. name .. " needs DadMode 1.16 or newer|r"
            else
                lines[#lines + 1] = head .. "  " .. GREY .. "checking...|r"
            end
        end
    end
end

---------------------------------------------------------------------------
-- Gear comparison: any item a guide looks at, against what the one being guided wears
---------------------------------------------------------------------------
do
    -- where an item goes
    local EQUIP = {
        INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
        INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
        INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
        INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
        INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
        INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
    }
    local ARMOR = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate" }
    -- the heaviest armor a class wears: below level 40, and from 40
    local HEAVIEST = {
        PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 },
        ROGUE = { 2, 2 }, DRUID = { 2, 2 }, MONK = { 2, 2 }, DEMONHUNTER = { 2, 2 },
        HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, EVOKER = { 3, 3 },
        WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, DEATHKNIGHT = { 4, 4 },
    }
    local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }

    local function Info(link)
        local I = C_Item
        if not (I and I.GetItemInfoInstant) then return nil end
        local ok, id, _, _, equipLoc, _, classID, subID = pcall(I.GetItemInfoInstant, link)
        if not ok or not Usable(id, "number") or not Usable(equipLoc, "string") then return nil end
        local out = { id = id, loc = equipLoc, class = classID, sub = subID }
        if I.GetItemInfo then
            local okI, name, _, quality, level, minLevel = pcall(I.GetItemInfo, link)
            if okI then
                out.name = Usable(name, "string") and name or nil
                out.quality = Usable(quality, "number") and quality or nil
                out.level = Usable(level, "number") and level or nil
                out.need = Usable(minLevel, "number") and minLevel or nil
            end
        end
        if I.GetDetailedItemLevelInfo then
            local okL, real = pcall(I.GetDetailedItemLevelInfo, link)
            if okL and Usable(real, "number") and real > 0 then out.level = real end
        end
        return out
    end

    local function Stats(link)
        local f = (C_Item and C_Item.GetItemStats) or GetItemStats
        if type(f) ~= "function" then return nil end
        local ok, t = pcall(f, link)
        if ok and type(t) == "table" and not Secret(t) then return t end
    end

    -- "+6 Stamina, -3 Spirit": what changes when he swaps old for new
    local function Difference(newLink, oldLink)
        local a, b = Stats(newLink), oldLink and Stats(oldLink) or {}
        if not a or not b then return nil end
        local keys, seen = {}, {}
        for k in pairs(a) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
        for k in pairs(b) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            local va, vb = a[k], b[k]
            if (va == nil or Usable(va, "number")) and (vb == nil or Usable(vb, "number")) then
                local diff = (va or 0) - (vb or 0)
                if diff ~= 0 and #parts < 8 then
                    local label = (type(_G[k]) == "string" and _G[k]) or tostring(k):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower()
                    local size = math.floor(math.abs(diff) * 10 + 0.5) / 10
                    parts[#parts + 1] = (diff > 0 and (GOOD .. "+") or (BAD .. "-")) .. ("%g"):format(size) .. " " .. label .. "|r"
                end
            end
        end
        return (#parts > 0) and table.concat(parts, ", ") or nil
    end

    -- Compares one item against what one person wears.
    -- Returns nil when it is not something to wear, otherwise a table:
    --   cannot = text why he can not wear it, or
    --   worn = his item in that slot (nil = empty), wornLevel, level, better (true/false/nil), diff, same
    local function Compare(link, d)
        local it = Info(link)
        if not it or not d or not d.gear then return nil end
        local slots = EQUIP[it.loc]
        if not slots then return nil end
        local res = { level = it.level, name = it.name, quality = it.quality }
        local class, lv = d.st and d.st.cl, d.st and d.st.lv
        local heavy = class and HEAVIEST[class]
        if it.class == 4 and ARMOR[it.sub] and heavy and it.loc ~= "INVTYPE_CLOAK" then
            local most = (lv and lv >= 40) and heavy[2] or heavy[1]
            if it.sub > most then
                res.cannot = "can not wear " .. ARMOR[it.sub]
                return res
            end
            res.lighter = (it.sub < most) and ARMOR[it.sub] or nil      -- wearable, but not his armor type
        end
        if it.loc == "INVTYPE_SHIELD" and class and not SHIELD[class] then
            res.cannot = "can not use shields"
            return res
        end
        if it.need and lv and it.need > lv then res.needs = it.need end
        -- with two slots (rings, trinkets, one-hand weapons) compare against the weaker one
        local pick, pickLevel
        for _, slot in ipairs(slots) do
            local g = d.gear[slot]
            if g and g.id == it.id then res.same = true end
            local wornLevel = -1
            if g then
                local w = Info(g.link or ("item:" .. g.id))
                wornLevel = w and w.level or 0
            end
            if not pickLevel or wornLevel < pickLevel then pick, pickLevel = slot, wornLevel end
        end
        local g = d.gear[pick]
        res.slot = pick
        if g then
            res.worn = g.link or ("item:" .. g.id)
            local w = Info(res.worn)
            res.wornName, res.wornQuality, res.wornLevel = w and w.name, w and w.quality, w and w.level
            if res.level and res.wornLevel then res.better = res.level > res.wornLevel end
            if not res.same then res.diff = Difference(link, res.worn) end
        else
            res.empty = true
            res.better = true
        end
        return res
    end
    DadMode_Compare = function(link, name) return Compare(link, questData[name]) end

    -- His class and level straight from the game, for when his own DadMode is too old to send them
    local function Fill(m, d)
        if not d then return end
        d.st = d.st or {}
        if not d.st.cl and type(UnitClass) == "function" then
            local ok, _, token = pcall(UnitClass, m.unit)
            if ok and Usable(token, "string") then d.st.cl = token end
        end
        if not d.st.lv and type(UnitLevel) == "function" then
            local ok, lv = pcall(UnitLevel, m.unit)
            if ok and Usable(lv, "number") and lv > 0 then d.st.lv = lv end
        end
    end

    local function Coloured(name, quality, link)
        return "|cff" .. (QUALITY[quality or 1] or "ffffff") .. "[" .. (name or "item") .. "]|r"
    end

    -- The lines added to an item tooltip
    local function TooltipLines(link)
        local lines = {}
        if not db.helper or db.compare == false then return lines end
        for _, m in ipairs(Party()) do
            local d = questData[m.name]
            Fill(m, d)
            local res = d and Compare(link, d)
            if res then
                if res.cannot then
                    lines[#lines + 1] = GREY .. m.name .. " " .. res.cannot .. "|r"
                elseif res.same then
                    lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r wears this"
                else
                    if res.empty then
                        lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r has " .. BAD .. "nothing|r in that slot (" .. SLOTS[res.slot] .. ")"
                    else
                        lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r wears " .. Coloured(res.wornName, res.wornQuality)
                            .. (res.wornLevel and (GREY .. "  item level " .. res.wornLevel .. "|r") or "")
                    end
                    if res.level and res.wornLevel then
                        local gap = res.level - res.wornLevel
                        lines[#lines + 1] = "  This one: item level " .. res.level .. "  "
                            .. ((gap > 0 and (GOOD .. "+" .. ("%g"):format(gap))) or (gap < 0 and (BAD .. ("%g"):format(gap))) or (GREY .. "same")) .. "|r"
                    end
                    if res.diff then lines[#lines + 1] = "  " .. res.diff end
                    if res.lighter then lines[#lines + 1] = "  " .. WARN .. "This is " .. res.lighter .. ". His class wears heavier armor.|r" end
                    if res.needs then lines[#lines + 1] = "  " .. WARN .. "Needs level " .. res.needs .. ", he is " .. tostring(d.st and d.st.lv) .. "|r" end
                end
            end
        end
        return lines
    end
    DadMode_TooltipLines = TooltipLines

    local function OnTooltip(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local link
        if TooltipUtil and TooltipUtil.GetDisplayedItem then
            local ok, _, l = pcall(TooltipUtil.GetDisplayedItem, tooltip)
            if ok and Usable(l, "string") then link = l end
        end
        if not link and type(tooltip.GetItem) == "function" then
            local ok, _, l = pcall(tooltip.GetItem, tooltip)
            if ok and Usable(l, "string") then link = l end
        end
        if not link and type(data) == "table" and Usable(data.id, "number") then link = "item:" .. data.id end
        if not link then return end
        local lines = TooltipLines(link)
        if #lines == 0 then return end
        tooltip:AddLine(" ")
        for _, line in ipairs(lines) do tooltip:AddLine(line, 1, 1, 1) end
        tooltip:Show()
    end

    function DadMode_HookTooltips()
        pcall(function()
            if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
                TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data) pcall(OnTooltip, tooltip, data) end)
            elseif GameTooltip and GameTooltip.HookScript then
                GameTooltip:HookScript("OnTooltipSetItem", function(tooltip) pcall(OnTooltip, tooltip) end)
                if ItemRefTooltip and ItemRefTooltip.HookScript then
                    ItemRefTooltip:HookScript("OnTooltipSetItem", function(tooltip) pcall(OnTooltip, tooltip) end)
                end
            end
        end)
    end

    -- Is this item from his bags better than what he wears? Same rule as for drops.
    local function IsUpgrade(res)
        return res and not res.cannot and not res.same and not res.lighter and not res.needs and res.better and true or false
    end

    -- How many things in his bags are better than what he has on
    function DadMode_BagUpgrades(name)
        local d = questData[name]
        if not d or not d.bagGear or not d.gear then return 0 end
        local n = 0
        for _, item in ipairs(d.bagGear) do
            if IsUpgrade(Compare(item, d)) then n = n + 1 end
        end
        return n
    end

    -- The "In his bags" part of the Gear tab
    function DadMode_BagGearLines(name, d, lines)
        lines[#lines + 1] = "|cffe8c36aGear in his bags|r  " .. GREY .. "compared with what he wears|r"
        if not d.bagGear then
            lines[#lines + 1] = GREY .. "Not known. " .. name .. " needs DadMode 1.21 or newer.|r"
            return
        end
        if #d.bagGear == 0 then
            lines[#lines + 1] = GREY .. "Nothing to wear in his bags.|r"
            return
        end
        local rows = {}
        for _, item in ipairs(d.bagGear) do
            local res = Compare(item, d)
            if res then rows[#rows + 1] = { item = item, res = res, up = IsUpgrade(res), index = #rows + 1 } end
        end
        table.sort(rows, function(a, b)
            if a.up ~= b.up then return a.up end
            return (a.res.level or 0) > (b.res.level or 0)
        end)
        for _, row in ipairs(rows) do
            local res = row.res
            local head = "|cff" .. (QUALITY[res.quality or 1] or "ffffff") .. "|H" .. row.item .. "|h[" .. (res.name or "loading...") .. "]|h|r"
                .. (res.level and (GREY .. "  item level " .. res.level .. "|r") or "")
            local note
            if res.cannot then
                note = GREY .. res.cannot .. "|r"
            elseif res.same then
                note = GREY .. "same as what he wears|r"
            elseif res.empty then
                note = GOOD .. "BETTER: his " .. SLOTS[res.slot]:lower() .. " slot is empty|r"
            elseif row.up then
                note = GOOD .. "BETTER than his " .. SLOTS[res.slot]:lower() .. "|r " .. Coloured(res.wornName, res.wornQuality)
                    .. (res.wornLevel and (GREY .. " item level " .. res.wornLevel .. "|r") or "")
            elseif res.needs then
                note = WARN .. "needs level " .. res.needs .. "|r"
            elseif res.lighter then
                note = GREY .. res.lighter .. ", lighter than his class wears|r"
            else
                note = GREY .. "not better than his " .. SLOTS[res.slot]:lower()
                    .. (res.wornLevel and (" (item level " .. res.wornLevel .. ")") or "") .. "|r"
            end
            lines[#lines + 1] = head
            lines[#lines + 1] = "    " .. note
            if row.up and res.diff then lines[#lines + 1] = "    " .. res.diff end
            -- anything he is able to wear can be pointed out to him
            if not res.cannot and not res.same and not res.needs then
                local state = d.wearTold and d.wearTold[row.item]
                lines[#lines + 1] = "    |cff6fb1e8|Hdadmode:wear:" .. name .. ":" .. row.item .. "|h[tell him to put it on]|h|r"
                    .. (state and ("  " .. state) or "")
            end
        end
    end

    -- "Put this on": a guide points at an item in his bags
    local wearBtn, wearItem, wearFrom, wearUntil = nil, nil, nil, 0

    function DadMode_TellWear(name, item)
        local d = questData[name]
        if not d then return end
        local ok, why = Tell("WEAR:" .. item)
        d.wearTold = d.wearTold or {}
        d.wearTold[item] = ok and (GREY .. "told him...|r") or (BAD .. "not sent: " .. tostring(why) .. "|r")
        DadMode_RenderQuests()
    end

    local function WornNow(id)
        for slot = 1, 18 do
            if Get(GetInventoryItemID, "player", slot) == id then return true end
        end
        return false
    end

    local function InBags(id)
        local C = C_Container
        if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return false end
        for bag = 0, 4 do
            local slots = Get(C.GetContainerNumSlots, bag)
            if type(slots) == "number" then
                for slot = 1, slots do
                    local info = Get(C.GetContainerItemInfo, bag, slot)
                    if type(info) == "table" and info.itemID == id then return true, info.hyperlink end
                end
            end
        end
        return false
    end

    local function CreateWearButton()
        wearBtn = BigButton(UIParent, 420, 54, function()
            if not wearItem then return end
            if InFight() then
                ShowAlert("|cffe8c36aNot during a fight.|r\nClick the button again after the fight.", 5)
                return
            end
            local id = tonumber(wearItem:match("item:(%d+)"))
            local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
            if type(equip) == "function" then pcall(equip, wearBtn.link or wearItem) end
            -- a moment later: did it work?
            local function Check()
                if id and WornNow(id) then
                    wearBtn:Hide()
                    wearItem = nil
                    ShowAlert("|cff6fcf97You put it on.|r", 4)
                    Tell("WEAROK:" .. id)
                else
                    ShowAlert("|cffe8c36aThat did not work by itself.|r\nOpen your bags and right-click " .. (wearBtn.name or "the item") .. ".", 10)
                    Tell("WEARNO:" .. (id or 0))
                end
            end
            if C_Timer and C_Timer.After then C_Timer.After(1, Check) else Check() end
        end)
        DadModeWear = wearBtn
        wearBtn:SetFrameStrata("HIGH")
        wearBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        wearBtn.bg:SetColorTexture(0.55, 0.42, 0.10, 0.97)
        wearBtn.label:SetTextColor(1, 1, 1)
        wearBtn:Hide()
    end

    -- his side: a guide says "put this on"
    local function ReceiveWear(m, item)
        if db.helper then return end
        local id = tonumber(item:match("item:(%d+)"))
        if not id then return end
        if WornNow(id) then
            Tell("WEAROK:" .. id)
            return
        end
        local has, link = InBags(id)
        if not has then
            Tell("WEARGONE:" .. id)
            return
        end
        if not wearBtn then CreateWearButton() end
        local name
        if C_Item and C_Item.GetItemInfo then
            local ok, n = pcall(C_Item.GetItemInfo, id)
            if ok and Usable(n, "string") then name = n end
        end
        wearItem, wearFrom, wearUntil = item, m.name, GetTime() + 120
        wearBtn.name = name
        wearBtn.link = Usable(link, "string") and link or nil
        wearBtn.label:SetText("CLICK TO PUT ON: " .. (name or "the new item"))
        wearBtn:Show()
        Beep("call")
        ShowAlert("|cffe8c36a" .. m.name .. "|r says: put on |cff6fcf97" .. (name or "the new item") .. "|r\nClick the gold button.", 10)
        Tell("WEARSEEN:" .. id)
    end

    function DadMode_WearTick()
        if wearBtn and wearItem and GetTime() > wearUntil then
            wearBtn:Hide()
            wearItem = nil
        end
    end

    -- Returns true when the message belonged to this feature
    function DadMode_WearMessage(text, sender)
        if text:sub(1, 4) ~= "WEAR" then return false end
        local m = (not IsMe(sender)) and Member(sender) or nil
        if not m then return true end
        if text:sub(1, 5) == "WEAR:" then
            ReceiveWear(m, text:sub(6))
            return true
        end
        local kind, id = text:match("^(WEAR%u+):(%d+)$")
        local d = questData[m.name]
        if not kind or not d then return true end
        d.wearTold = d.wearTold or {}
        local note = (kind == "WEAROK" and (GOOD .. "he put it on|r")) or (kind == "WEARSEEN" and (GREY .. "he sees the button|r"))
            or (kind == "WEARGONE" and (BAD .. "not in his bags any more|r")) or (WARN .. "it did not work, he has to right-click it|r")
        for item in pairs(d.wearTold) do
            if item:match("item:(%d+)") == id then d.wearTold[item] = note end
        end
        -- a link he was not told about through this window still gets a chat line
        if kind == "WEAROK" then Print("|cff6fcf97" .. m.name .. " put it on.|r") end
        if kind == "WEARNO" then Print("|cffe8c36a" .. m.name .. " clicked, but the item did not go on. He has to right-click it in his bags.|r") end
        if kind == "WEARGONE" then Print("|cffeb7a7a" .. m.name .. " does not have that item in his bags any more.|r") end
        DadMode_RenderQuests()
        return true
    end

    -- A drop: say so once when it looks like an upgrade for him
    local told = {}
    local function Dropped(link)
        if not db.helper or db.compare == false or not Usable(link, "string") then return end
        local item = link:match("item:[%-%d:]+")
        if not item then return end
        local now = GetTime()
        if told[item] and now - told[item] < 120 then return end
        for _, m in ipairs(Party()) do
            local d = questData[m.name]
            Fill(m, d)
            local res = d and Compare(link, d)
            -- only real candidates: he can wear it, it is his armor type, it is better, and not grey or white
            if res and not res.cannot and not res.same and not res.lighter and res.better and (res.quality or 0) >= 2 then
                told[item] = now
                Print("|cff6fcf97Possible upgrade for " .. m.name .. ":|r " .. link
                    .. (res.level and (" item level " .. res.level) or "") .. ". "
                    .. (res.empty and ("His " .. SLOTS[res.slot]:lower() .. " slot is empty.")
                        or ("He wears " .. Coloured(res.wornName, res.wornQuality) .. (res.wornLevel and (" item level " .. res.wornLevel) or "") .. "."))
                    .. (res.needs and (" Needs level " .. res.needs .. ".") or ""))
            end
        end
    end
    DadMode_Dropped = Dropped

    handlers.START_LOOT_ROLL = function(rollID)
        if type(GetLootRollItemLink) ~= "function" then return end
        local ok, link = pcall(GetLootRollItemLink, rollID)
        if ok then pcall(Dropped, link) end
    end
    handlers.LOOT_OPENED = function()
        if type(GetNumLootItems) ~= "function" or type(GetLootSlotLink) ~= "function" then return end
        local ok, n = pcall(GetNumLootItems)
        if not ok or not Usable(n, "number") then return end
        for i = 1, n do
            local okL, link = pcall(GetLootSlotLink, i)
            if okL then pcall(Dropped, link) end
        end
    end
    handlers.CHAT_MSG_LOOT = function(text)
        if not Usable(text, "string") then return end
        local link = text:match("|c%x+|Hitem:.-|h%[.-%]|h|r") or text:match("|Hitem:.-|h%[.-%]|h")
        if link then pcall(Dropped, link) end
    end
end

---------------------------------------------------------------------------
-- Extras: version check and warnings on the guide bar
---------------------------------------------------------------------------
do
    local lastHi, lastPoll, lastStatusReply, lastGearAsk = 0, 0, 0, 0
    local peerRole = {}         -- name -> "g" guide or "d" being guided
    local gearAsked = {}

    -- "1.14.2" as one number, so versions can be compared
    local function Num(v)
        local a, b, c = tostring(v):match("^(%d+)%.(%d+)%.?(%d*)")
        return (tonumber(a) or 0) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
    end
    DadMode_VersionNumber = Num

    local function SayHi(force)
        if #Party() == 0 then return end
        if not force and GetTime() - lastHi < 30 then return end
        lastHi = GetTime()
        Tell("HI:" .. VERSION .. ":" .. (db.helper and "g" or "d"))
    end

    -- Asks everybody's DadMode to say its version and role again
    local lastWho = 0
    function DadMode_AskVersions()
        if #Party() == 0 or GetTime() - lastWho < 10 then return end
        lastWho = GetTime()
        Tell("HI?")
        SayHi()
    end

    -- One line per person in the party: role and version, as far as it is known
    function DadMode_VersionLines()
        local lines = { "You: " .. (db.helper and "guide" or "being guided") .. ", DadMode " .. VERSION }
        for _, m in ipairs(Party()) do
            local d = questData[m.name]
            local v = peerVersion[m.name] or (d and d.st and d.st.v)
            local role = peerRole[m.name] or ((d and d.st) and "d" or nil)      -- only the guided answer with a status
            local text = m.name .. ": "
            if not v then
                text = text .. GREY .. "no DadMode seen|r"
            else
                text = text .. (role == "g" and "guide" or role == "d" and "being guided" or "role unknown") .. ", DadMode " .. v
                if Num(v) > 0 and Num(v) < Num(VERSION) then text = text .. "  " .. BAD .. "older than yours|r"
                elseif Num(v) > Num(VERSION) then text = text .. "  " .. WARN .. "newer than yours|r"
                else text = text .. "  " .. GOOD .. "same as yours|r" end
            end
            lines[#lines + 1] = text
        end
        return lines
    end

    -- Lines for the guide bar: what is wrong with the one being guided, and old versions
    function DadMode_Notes()
        local warn, vers = {}, {}
        local now = GetTime()
        for _, m in ipairs(Party()) do
            local d = questData[m.name]
            local st = d and d.st
            if st and now - (d.at or 0) < 180 then
                local a = {}
                if st.dead == 1 then a[#a + 1] = BAD .. "DEAD|r" end
                if st.cb == 1 and not InFight() then a[#a + 1] = WARN .. "in a fight|r" end
                if st.bf == 0 and st.bt then a[#a + 1] = BAD .. "bags full|r"
                elseif st.bf and st.bt and st.bf <= 2 then a[#a + 1] = WARN .. st.bf .. " bag slots left|r" end
                if (st.brk or 0) > 0 then a[#a + 1] = BAD .. st.brk .. " broken|r" end
                if (st.tp or 0) > 0 then a[#a + 1] = WARN .. st.tp .. " talent point" .. (st.tp > 1 and "s" or "") .. "|r" end
                if DadMode_BagUpgrades and db.compare ~= false then
                    local okU, ups = pcall(DadMode_BagUpgrades, m.name)
                    if okU and ups > 0 then a[#a + 1] = GOOD .. ups .. " better item" .. (ups > 1 and "s" or "") .. " in his bags|r" end
                end
                if #a > 0 then warn[#warn + 1] = m.name .. ": " .. table.concat(a, ", ") end
            end
            local v = peerVersion[m.name] or (st and st.v)
            if v and Num(v) > 0 and Num(v) < Num(VERSION) then
                vers[#vers + 1] = GREY .. m.name .. " has DadMode " .. v .. ", you have " .. VERSION .. "|r"
            elseif v and Num(v) > Num(VERSION) then
                vers[#vers + 1] = WARN .. m.name .. " has DadMode " .. v .. ", newer than yours|r"
            end
        end
        for _, line in ipairs(vers) do warn[#warn + 1] = line end
        return warn
    end

    function DadMode_ExtrasTick()
        local now = GetTime()
        local inParty = #Party() > 0
        -- a guide needs his gear for the item comparison: ask for everything when it is missing
        -- or ten minutes old. The window does the same when it is open.
        -- Each person is asked at most once in ten minutes: another guide never answers, and
        -- asking him again and again would make dad's addon send everything every time.
        if db.helper and inParty and db.compare ~= false and now - lastGearAsk > 20 then
            local want = false
            for _, m in ipairs(Party()) do
                local d = questData[m.name]
                local stale = not d or not d.gear or now - (d.gearAt or 0) > 600
                if stale and now - (gearAsked[m.name] or -9999) > 600 then
                    gearAsked[m.name] = now
                    want = true
                end
            end
            if want then
                lastGearAsk = now
                Tell("QREQ")
            end
        end
        -- a guide asks for the short status now and then, so the warnings stay fresh
        if db.helper and inParty and helper and helper:IsShown() and now - lastPoll > 45 then
            lastPoll = now
            Tell("SREQ")
        end
    end

    -- Returns true when the message was one of these and is dealt with
    function DadMode_ExtraMessage(text, sender)
        local head = text:sub(1, 3)
        if text == "HI?" then
            local m = (not IsMe(sender)) and Member(sender) or nil
            if m and GetTime() - lastHi > 5 then SayHi(true) end
            return true
        elseif head == "HI:" then
            local m = (not IsMe(sender)) and Member(sender) or nil
            if m then
                local known = peerVersion[m.name]
                local v, role = text:sub(4, 24):match("^([%d%.]+):?(%a?)")
                if v then
                    peerVersion[m.name] = v
                    if role == "g" or role == "d" then peerRole[m.name] = role end
                end
                if not known then SayHi() end          -- somebody new: tell them mine too
            end
            return true
        elseif text == "SREQ" then
            local m = (not IsMe(sender)) and Member(sender) or nil
            if m and not db.helper and not outbox[1] and GetTime() - lastStatusReply > 20 then
                lastStatusReply = GetTime()
                local ok, st1, st2 = pcall(ReadStatus)
                if ok then
                    Queue(st1)
                    Queue(st2)
                    PumpOutbox()
                end
            end
            return true
        end
        return false
    end

    local roster = handlers.GROUP_ROSTER_UPDATE
    handlers.GROUP_ROSTER_UPDATE = function(...)
        pcall(SayHi)
        if roster then return roster(...) end
    end
end

for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_DADMODE1 = "/dadmode"
SlashCmdList["DADMODE"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        OpenPicker(db.helper)
    elseif msg == "off" then
        db.enabled = false
        Print("Arrows off. /dadmode on brings them back.")
    elseif msg == "on" then
        db.enabled = true
        Print("Arrows on.")
    elseif msg == "alerts" then
        db.alerts = not db.alerts
        if RefreshPicker then RefreshPicker() end
        Print(db.alerts and "You will see pings." or "You will not see pings.")
    elseif msg == "follow" then
        db.follow = not db.follow
        Print(db.follow and "Follow button on." or "Follow button off.")
    elseif msg == "waypoint" then
        SendWaypoint()
    elseif msg == "stop" or msg:sub(1, 5) == "stop " then
        RecordStop(msg:sub(6))
    elseif msg == "travel" then
        pcall(ResolveStops)
        Print("Zeppelin platforms and boat docks this computer knows:")
        for _, key in ipairs(STOP_ORDER) do
            local stop, p = STOPS[key], db.stops and db.stops[key]
            Print("  " .. Ride(stop) .. " " .. stop.at .. " to " .. stop.to .. (stop.who and (" (" .. stop.who .. ")") or "") .. ": "
                .. (p and ((p.manual and "|cff6fcf97recorded by a guide|r" or p.approx and "|cffe8c36arough, the town only|r" or "|cff6fcf97known|r")
                    .. "  continent " .. p.cont .. ", " .. p.n .. ", " .. p.w) or "|cffeb7a7aunknown|r"))
        end
        local pn, pw, pc = WorldPos("player")
        Print("You: " .. (pn and ("continent " .. pc .. ", " .. math.floor(pn) .. ", " .. math.floor(pw)) or "no position here"))
        if db.waypoint then
            local key = TravelStep(db.waypoint)
            Print("Marker: " .. (key == nil and "walk straight to it" or key == "unknown" and "another continent, no platform known"
                or ("first the " .. Ride(STOPS[key]) .. " from " .. STOPS[key].at .. " to " .. STOPS[key].to)))
        end
    elseif msg == "minimap" then
        ToggleMinimapButton()
    elseif msg == "quests" then
        OpenQuests()
    elseif msg == "debug" then
        local function Try(f, ...)
            local ok, a, b = pcall(f, ...)
            return ok and (tostring(a) .. (b and b ~= "" and (" / " .. tostring(b)) or "")) or "error"
        end
        Print("Me: UnitName=" .. Try(UnitName, "player") .. "  GetUnitName=" .. (GetUnitName and Try(GetUnitName, "player", true) or "n/a"))
        for _, m in ipairs(Party()) do
            Print(m.unit .. ": UnitName=" .. Try(UnitName, m.unit) .. "  GetUnitName=" .. (GetUnitName and Try(GetUnitName, m.unit, true) or "n/a") .. "  key=" .. tostring(m.key))
        end
        Print("Last call heard: " .. (lastHeard or "none since login"))
    elseif msg == "status" then
        local names = {}
        for _, m in ipairs(Party()) do names[#names + 1] = m.name end
        Print("DadMode " .. VERSION .. ". Role: " .. (db.helper and "guide" or "being guided") .. ". I show calls: " .. (db.alerts and "yes" or "no")
            .. ". Party: " .. (#names > 0 and table.concat(names, ", ") or "nobody"))
        if DadMode_VersionLines and #names > 0 then
            pcall(DadMode_AskVersions)
            for _, line in ipairs(DadMode_VersionLines()) do Print("  " .. line) end
            Print("  Type it again in a few seconds if someone just joined.")
        end
    elseif msg == "clear" then
        Dismiss()
    elseif msg == "resetsize" then
        ResetSizes()
    elseif msg == "settings" or msg == "options" then
        DadMode_OpenSettings()
    elseif msg == "role" then
        if roleWin then roleWin:Show() end
    elseif msg == "helper" or msg == "guide" then
        ToggleHelper()
    elseif msg == "test" then
        TestCall()
    else
        Print("/dadmode (pick people), /dadmode settings, /dadmode follow (follow button on or off), /dadmode status, /dadmode clear (remove a ping), /dadmode role (guide or being guided), /dadmode on, /dadmode off, /dadmode alerts, /dadmode test, /dad (ping the party)")
    end
end

SLASH_DADPING1 = "/dad"
SlashCmdList["DADPING"] = function(msg)
    SendPing(msg)
end
