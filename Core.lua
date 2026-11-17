-- DadMode: constants, small helpers, who is in the party, where everybody is, the big message

-- DadMode: never lose your party.
--   * Pick people in your party. Each one gets a big arrow that points to them, with the distance.
--   * Green = close, yellow = a bit away, red = far. A sound plays when you drift too far.
--   * Anyone in the party can call you: /dad in the addon, or typing !dad in party chat.
-- Arrows only work outdoors. Inside dungeons the game does not share where players are.

-- The game hands every file of an addon the same table, here called ns. A file puts what
-- other files need into it (at the bottom: "used by other files"), and reads the rest as
-- ns.<name>. Things that change while playing (saved settings, windows) live in ns only.
local ADDON, ns = ...

local NEAR, FAR = 40, 110            -- yards: green below NEAR, red above FAR
local PING_SECONDS = 10              -- how long the ping text stays on screen
local PING_ARROW = 60                -- how long the arrow keeps pulsing if he has not arrived
local ARRIVED = 12                   -- yards: this close counts as "found them"
local PING_GAP = 3                   -- seconds: a second ping from the same person sooner than this is ignored
local PREFIX = "DADMODE"
local ARROW = "Interface\\AddOns\\DadMode\\Arrow"

ns.VERSION = "?"
pcall(function()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    ns.VERSION = get and get("DadMode", "Version") or "?"
end)
local peerVersion = {}               -- name -> DadMode version the other person runs


local ARROW_SIZES = { { "Small", 64 }, { "Medium", 96 }, { "Large", 128 } }
local SCALES = { 0.8, 0.9, 1, 1.1, 1.25 }       -- the "Window size" setting
local HELPER_BREAK = 240                        -- guide bar dragged narrower than this: one column
local FOLLOW_RANGE = 30                         -- the follow button only flashes when the caller is this close
local GRIP_MIN, GRIP_MAX = 0.6, 2               -- how small and big a corner drag can make a window
local function ArrowBase()
    return (ARROW_SIZES[ns.db and ns.db.arrowSize or 2] or ARROW_SIZES[2])[2]
end
-- defined further down
-- defined further down
local slots = {}
local pings = {}                     -- name -> time the ping ends
ns.farSince = {}
local farBeeped = {}                 -- name -> true once the far sound has played for this time away
ns.lastPingFrom, lastBeep, ns.lastSent = {}, 0, 0
ns.answered = true                -- did anyone answer my last call
ns.wpOut = false      -- guide side: dad has a waypoint from me right now
local call = { state = nil, who = nil, at = 0 }   -- what the helper bar shows about my last call
ns.moving = false

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

-- what the last incoming call looked like, for /dadmode debug

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
    local choice = SOUNDS[(ns.db.sounds and ns.db.sounds[kind]) or DEFAULT_SOUND[kind]] or SOUNDS[1]
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
    if not ns.alertFrame then return end
    ns.alertFrame.text:SetText(text)
    -- the clickable area is only as big as the text, so it does not block the rest of the screen
    local w = math.min(ns.alertFrame.text:GetStringWidth() or 600, 900)
    local h = ns.alertFrame.text:GetStringHeight() or 40
    ns.alertFrame:SetSize(w + 40, h + 44)
    ns.alertFrame:Show()
    ns.alertFrame.hideAt = GetTime() + (seconds or 5)
    ns.alertFrame.from = nil
end

-- Clears the message on screen and stops any pulsing arrow
local function Dismiss()
    for name in pairs(pings) do pings[name] = nil end
    if ns.alertFrame then ns.alertFrame:Hide() end
end

-- used by other files of DadMode
ns.ARRIVED = ARRIVED
ns.ARROW = ARROW
ns.ARROW_SIZES = ARROW_SIZES
ns.ArrowBase = ArrowBase
ns.Beep = Beep
ns.DEFAULT_SOUND = DEFAULT_SOUND
ns.Dismiss = Dismiss
ns.FAR = FAR
ns.FOLLOW_RANGE = FOLLOW_RANGE
ns.GRIP_MAX = GRIP_MAX
ns.GRIP_MIN = GRIP_MIN
ns.HELPER_BREAK = HELPER_BREAK
ns.Key = Key
ns.Locate = Locate
ns.LocatePoint = LocatePoint
ns.MapToWorld = MapToWorld
ns.NEAR = NEAR
ns.PING_ARROW = PING_ARROW
ns.PING_GAP = PING_GAP
ns.PING_SECONDS = PING_SECONDS
ns.PREFIX = PREFIX
ns.Party = Party
ns.Print = Print
ns.SCALES = SCALES
ns.SOUNDS = SOUNDS
ns.Secret = Secret
ns.ShowAlert = ShowAlert
ns.Tex = Tex
ns.Usable = Usable
ns.WorldPos = WorldPos
ns.XY = XY
ns.call = call
ns.farBeeped = farBeeped
ns.peerVersion = peerVersion
ns.pings = pings
ns.slots = slots
