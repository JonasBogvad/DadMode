-- DadMode: Extras: version check and warnings on the guide bar

-- Shared with DadMode.lua through the table the game gives every file of an addon.
-- Things that only exist after login (saved settings, windows) are read as ns.<name>.
local ADDON, ns = ...
local BAD, GOOD, GREY, InFight, IsMe, Member, Party, PumpOutbox, Queue, ReadStatus, Tell, VERSION, WARN, handlers, outbox, peerVersion, questData, slots
    = ns.BAD, ns.GOOD, ns.GREY, ns.InFight, ns.IsMe, ns.Member, ns.Party, ns.PumpOutbox, ns.Queue, ns.ReadStatus, ns.Tell, ns.VERSION, ns.WARN, ns.handlers, ns.outbox, ns.peerVersion, ns.questData, ns.slots

local lastHi, lastPoll, lastStatusReply, lastGearAsk = 0, 0, 0, 0
local peerRole = {}         -- name -> "g" guide or "d" being guided
function DadMode_RoleOf(name) return peerRole[name] end
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
    Tell("HI:" .. VERSION .. ":" .. (ns.db.helper and "g" or "d"))
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
    local lines = { "You: " .. (ns.db.helper and "guide" or "being guided") .. ", DadMode " .. VERSION }
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
        local how = DadMode_WhisperState and DadMode_WhisperState(m.name)
        if how == "ok" then text = text .. GREY .. ", answers by whisper|r"
        elseif how == "bad" then text = text .. WARN .. ", whispers do not arrive, using the party channel|r" end
        lines[#lines + 1] = text
    end
    return lines
end

-- What needs attention with one person, as short coloured pieces. Red is urgent, yellow is soon.
local LOW_GEAR = 25         -- percent: below this his most worn piece is worth a word
local function Problems(name, st)
    local a = {}
    if st then
        if st.dead == 1 then a[#a + 1] = BAD .. "DEAD|r" end
        if st.bf == 0 and st.bt then a[#a + 1] = BAD .. "bags full|r"
        elseif st.bf and st.bt and st.bf <= 2 then a[#a + 1] = WARN .. st.bf .. " bag slots left|r" end
        if (st.brk or 0) > 0 then a[#a + 1] = BAD .. st.brk .. " broken|r"
        elseif st.dur and st.dur < LOW_GEAR then a[#a + 1] = WARN .. "gear " .. st.dur .. "%|r" end
        if st.fd == 0 then a[#a + 1] = WARN .. "no food|r" end
        if (st.tp or 0) > 0 then a[#a + 1] = WARN .. st.tp .. " talent point" .. (st.tp > 1 and "s" or "") .. "|r" end
    end
    local v = peerVersion[name] or (st and st.v)
    if v and Num(v) > 0 and Num(v) < Num(VERSION) then
        a[#a + 1] = GREY .. "has DadMode " .. v .. ", you have " .. VERSION .. "|r"
    elseif v and Num(v) > Num(VERSION) then
        a[#a + 1] = WARN .. "has DadMode " .. v .. ", newer than yours|r"
    end
    return a
end

-- The strip at the bottom of the guide bar: who I am guiding, where he is, and what needs
-- attention. Returns the lines, and the one line that matters most for the top of the bar.
-- No lines means there is nobody to show, and the bar leaves the strip out.
function DadMode_Notes()
    local now = GetTime()
    local people = {}
    local picked = DadMode_TargetName and DadMode_TargetName() or nil
    for _, m in ipairs(DadMode_Candidates and DadMode_Candidates() or {}) do
        if not picked or m.name == picked then
            local d = questData[m.name]
            local fresh = d and d.st and now - (d.at or 0) < 180
            people[#people + 1] = { name = m.name, unit = m.unit, st = fresh and d.st or nil }
        end
    end
    -- somebody outside the party who answered a whisper a moment ago
    if #Party() == 0 and DadMode_RemoteState then
        for name, d in pairs(questData) do
            if d.st and now - (d.at or 0) < 180 and DadMode_RemoteState(name) == "ok" then
                people[#people + 1] = { name = name, st = d.st }
            end
        end
    end
    local lines, top = {}, nil
    for _, p in ipairs(people) do
        local head = "|cffe8c36a" .. p.name .. "|r"
        if p.st then
            if p.st.lv then head = head .. "  " .. p.st.lv end
            if p.st.z then head = head .. "  " .. p.st.z end
        end
        if p.unit then
            local dist = ns.Locate(p.unit)
            if dist then head = head .. "  " .. GREY .. math.floor(dist + 0.5) .. " yd|r" end
        else
            head = head .. "  " .. GREY .. "not in your party|r"
        end
        local wrong = Problems(p.name, p.st)
        local state
        if #wrong > 0 then
            state = table.concat(wrong, ", ")
            top = top or (p.name .. ": " .. state)
        elseif p.st then
            state = GOOD .. "all good|r"
        else
            state = GREY .. "no status yet|r"
        end
        if #people == 1 then
            lines[#lines + 1] = head
            lines[#lines + 1] = state
        else
            lines[#lines + 1] = head .. "  " .. state
        end
    end
    return lines, top
end

-- Somebody in the party runs a newer DadMode than this computer: say so once.
-- An addon can not look on the internet. Meeting somebody who has it is how it finds out.
local toldNewer = false
local function Newer(v)
    if toldNewer or not v or Num(v) <= Num(VERSION) then return end
    toldNewer = true
    ns.Print("|cffe8c36aDadMode " .. v .. " is out.|r You have " .. VERSION .. ". Update it in the CurseForge app, then restart the game.")
    if not ns.db.helper and ns.ShowAlert then
        ns.ShowAlert("|cffe8c36aDadMode has a new version|r\nUpdate it in the CurseForge app", 8)
    end
end

function DadMode_ExtrasTick()
    local now = GetTime()
    local inParty = #Party() > 0
    -- a guide needs his gear for the item comparison: ask for everything when it is missing
    -- or ten minutes old. The window does the same when it is open.
    -- Each person is asked at most once in ten minutes: another guide never answers, and
    -- asking him again and again would make dad's addon send everything every time.
    if ns.db.helper and inParty and ns.db.compare ~= false and now - lastGearAsk > 20 then
        local want, modern = false, true
        for _, m in ipairs(Party()) do
            local d = questData[m.name]
            -- only people known to run DadMode: nobody else would answer
            local v = peerVersion[m.name] or (d and d.st and d.st.v)
            local stale = not d or not d.gear or now - (d.gearAt or 0) > 600
            if v and stale and now - (gearAsked[m.name] or -9999) > 600 then
                gearAsked[m.name] = now
                want = true
                if Num(v) < Num("1.22.0") then modern = false end
            end
        end
        if want then
            lastGearAsk = now
            -- "QREQ:a" = asked by the addon itself, not by a click. From 1.22 that never makes
            -- a Yes / No box appear for somebody who has not approved this guide.
            Tell(modern and "QREQ:a" or "QREQ")
            if DadMode_NoteAsk then pcall(DadMode_NoteAsk, true) end
        end
    end
    -- a guide asks for the short status now and then, so the warnings stay fresh
    if ns.db.helper and inParty and ns.helper and ns.helper:IsShown() and now - lastPoll > 45 then
        lastPoll = now
        Tell("SREQ")
        if DadMode_NoteStatusAsk then pcall(DadMode_NoteStatusAsk) end
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
                Newer(v)
            end
            if not known then SayHi() end          -- somebody new: tell them mine too
        end
        return true
    elseif text == "SREQ" or text == "SREQ:p" then
        -- whispered back to the guide who asked; ":p" = he wants it on the party channel
        local to = (text == "SREQ") and sender or nil
        local m = (not IsMe(sender)) and Member(sender) or nil
        if m and not ns.db.helper and not outbox[1] and GetTime() - lastStatusReply > 20 then
            lastStatusReply = GetTime()
            local ok, st1, st2 = pcall(ReadStatus)
            if ok then
                local out = { st1, st2 }
                if DadMode_FilterReply then out = DadMode_FilterReply(out) end
                for _, body in ipairs(out) do Queue(body, to) end
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
