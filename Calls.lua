-- DadMode: calls ("look here"): sending them, showing them, answering them

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Pings: "look here"
---------------------------------------------------------------------------

-- The party member a sender string belongs to, or nil
local function Member(sender)
    local key = ns.Key(sender)
    if not key then return nil end
    for _, m in ipairs(ns.Party()) do
        if m.key == key then return m end
    end
end

local function IsMe(sender)
    local ok, me = pcall(UnitName, "player")
    return ok and ns.Key(me) ~= nil and ns.Key(me) == ns.Key(sender)
end

local function ReceivePing(sender, text)
    local m = (not IsMe(sender)) and Member(sender) or nil
    ns.lastHeard = tostring(sender) .. " -> " .. (IsMe(sender) and "that is me" or m and ("matched " .. m.name) or "NOT in my party list")
    if not m then return end
    sender = m.name
    if not ns.db.alerts then
        ns.Tell("MUTED")                -- let the caller know why nothing shows here
        if GetTime() - (ns.lastMutedNote or 0) > 30 then
            ns.lastMutedNote = GetTime()
            ns.Print(sender .. " is calling you, but calls are switched off here. Click the gold arrow on the minimap and press the red button.")
        end
        return
    end
    local now = GetTime()
    if ns.lastPingFrom[sender] and now - ns.lastPingFrom[sender] < ns.PING_GAP then return end
    ns.lastPingFrom[sender] = now
    ns.pings[sender] = now + ns.PING_ARROW
    ns.Beep()
    local line = (text and text ~= "") and text or "wants you. Follow the white arrow"
    local dist = ns.Locate(m.unit)
    if dist and dist > ns.FOLLOW_RANGE then
        line = line .. "\n|cff9aa0a6" .. math.floor(dist + 0.5) .. " yards away. Walk towards the arrow first.|r"
    elseif not dist and type(UnitIsVisible) == "function" then
        local ok, seen = pcall(UnitIsVisible, m.unit)
        if ok and ns.Usable(seen, "boolean") and not seen then
            line = line .. "\n|cff9aa0a6" .. sender .. " is far away, not in sight.|r"
        end
    end
    ns.ShowAlert("|cffe8c36a" .. sender .. "|r " .. line, ns.PING_SECONDS)
    ns.alertFrame.from = sender
    ns.Tell("VER:" .. ns.VERSION)
    ns.Tell("ACK")
end

-- Shows on MY screen what dad would see. Works for helpers too.
local function TestCall()
    local list = ns.Party()
    if #list > 0 then
        local who = list[1].name
        ns.pings[who] = GetTime() + ns.PING_ARROW
        ns.Beep()
        ns.ShowAlert("|cffe8c36a" .. who .. "|r wants you. Follow the white arrow  |cff9aa0a6(test)|r", ns.PING_SECONDS)
        ns.alertFrame.from = who
        ns.Print("Test: this is what the one you guide sees when " .. who .. " calls. If you stand next to them it ends right away with \"You found " .. who .. "\".")
    else
        ns.Beep()
        ns.ShowAlert("|cffe8c36aTest|r wants you. Follow the white arrow  |cff9aa0a6(test)|r", 5)
        ns.Print("Test: text and sound only. Join a party to also see the arrow.")
    end
end
DadMode_TestCall = TestCall

-- The helper took the call back
local function ReceiveClear(sender)
    local m = (not IsMe(sender)) and Member(sender) or nil
    if not m then return end
    sender = m.name
    ns.pings[sender] = nil
    if ns.alertFrame and ns.alertFrame.from == sender then ns.alertFrame:Hide() end
end

-- Answers that come back to the helper
function DadMode_ReceiveReply(sender, kind)
    local m = (not IsMe(sender)) and Member(sender) or nil
    if not m then return end
    sender = m.name
    if GetTime() - ns.lastSent > ns.PING_ARROW + 5 then return end       -- only if I called recently
    ns.call.who, ns.call.at = sender, GetTime()
    ns.call.state = (kind == "MUTED" and "muted") or (kind == "HERE" and "here") or "ack"
    if kind == "MUTED" then
        ns.answered = true
        ns.Print(sender .. " has DadMode, but calls are switched off there. On that computer type /dadmode alerts")
    elseif kind == "ACK" then
        ns.answered = true
        ns.Print("|cff6fcf97" .. sender .. " got your call.|r"
            .. (ns.peerVersion[sender] and (" |cff9aa0a6(their DadMode " .. ns.peerVersion[sender] .. ")|r") or ""))
    elseif kind == "HERE" then
        ns.Print("|cff6fcf97" .. sender .. " is with you.|r")
        ns.lastSent = 0
    end
end

local function SendPing(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local okG, grouped = pcall(IsInGroup)
    if not (okG and grouped) then
        ns.Print("You are not in a party.")
        return
    end
    local ok, why = ns.Tell(DadMode_Aim("PING:" .. text:sub(1, 200)))
    if ok then
        ns.lastSent = GetTime()
        ns.answered = false
        ns.call.state, ns.call.who, ns.call.at = "sent", nil, ns.lastSent
        ns.Print("Call sent.")
        if C_Timer and C_Timer.After then
            local stamp = ns.lastSent
            C_Timer.After(3, function()
                if not ns.answered and ns.lastSent == stamp then
                    ns.call.state, ns.call.at = "none", GetTime()
                    ns.Print("|cffeb7a7aNobody answered.|r Nobody else in the party has DadMode running. Check it is installed and ticked on their AddOns list.")
                end
            end)
        end
    else
        ns.Print("|cffeb7a7aCall not sent:|r " .. tostring(why) .. ". Type !dad in party chat instead.")
    end
end

DadMode_SendPing = SendPing

local function SendClear()
    ns.Tell(DadMode_Aim("CLEAR"))
    ns.lastSent = 0
    ns.call.state = nil
    ns.Print("Call cancelled.")
end

local function ChatPing(text, sender)
    if not ns.Usable(text, "string") or not ns.Usable(sender, "string") then return end
    local rest = text:match("^%s*![Dd][Aa][Dd]%s*(.*)$")
    if not rest then return end
    if DadMode_GateChat and DadMode_GateChat(sender) then return end
    local word = rest:lower()
    if word == "ok" or word == "clear" or word == "stop" then
        ReceiveClear(sender)
    else
        ReceivePing(sender, rest)
    end
end

-- used by other files of DadMode
ns.ChatPing = ChatPing
ns.IsMe = IsMe
ns.Member = Member
ns.ReceiveClear = ReceiveClear
ns.ReceivePing = ReceivePing
ns.SendClear = SendClear
ns.SendPing = SendPing
ns.TestCall = TestCall
