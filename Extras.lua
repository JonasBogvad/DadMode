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
