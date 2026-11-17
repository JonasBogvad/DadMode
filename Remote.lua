-- DadMode: guiding somebody who is not in my party
--
-- A guide remembers the people he has guided (ns.db.known). When they are not in his party,
-- the "How is ... doing" window asks them by whisper, and they answer by whisper. Positions,
-- arrows, calls and waypoints need a party; status, quests, gear and "put it on" do not.
--
-- The one being guided only answers somebody he has already approved as a guide. Anybody
-- else who whispers gets nothing at all: no answer and no Yes / No box.

local ADDON, ns = ...
local Key, Party, Print, Tell, Usable = ns.Key, ns.Party, ns.Print, ns.Tell, ns.Usable

local KEEP = 300            -- seconds somebody outside the party stays "in the conversation"
local MOST = 5              -- how many people are asked by whisper at one time
local remote = {}           -- key -> { name, key, full, id, remote = true, at }
local state = {}            -- key -> { asked = time, heard = time, offline = true }

-- "saqu off" from "Saqu Off-CAMWOW EU5 Realm 4 PvP": who somebody is, whatever the realm part says
local function Id(sender)
    local shown = tostring(sender):match("^([^%-]+)") or tostring(sender)
    return (shown:gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

local function First(sender)
    return tostring(sender):match("^%s*([^%s%-]+)") or tostring(sender)
end

local function InParty(key)
    for _, m in ipairs(Party()) do
        if m.key == key then return true end
    end
    return false
end

local function Note(key, name, sender)
    remote[key] = { name = name, key = key, full = sender, id = Id(sender), remote = true, at = GetTime() }
end

-- For Member(): the person behind a sender when he is outside the party and in the conversation
function DadMode_RemoteMember(key, sender)
    local r = remote[key]
    if r and GetTime() - r.at < KEEP and r.id == Id(sender) and not InParty(key) then return r end
end

-- What a guide may ask for without being in the party
local function IsRequest(text)
    return text == "QREQ" or text:sub(1, 5) == "QREQ:" or text:sub(1, 3) == "QC:" or text:sub(1, 5) == "WEAR:"
        or text == "TREQ" or text:sub(1, 6) == "TPICK:" or text == "QW"
end

-- What the one being guided sends back
local function IsAnswer(text)
    local h3 = text:sub(1, 3)
    return text == "QE" or h3 == "QS:" or h3 == "ST:" or h3 == "QD:" or h3 == "BG:" or h3 == "GR:" or h3 == "GL:"
        or h3 == "SS:" or h3 == "CN:" or text:sub(1, 2) == "Q:" or text:sub(1, 4) == "BGS:" or text:sub(1, 5) == "PERM:"
        or text:match("^WEAR%u+:%d+$") ~= nil
        or h3 == "TT:" or h3 == "TL:" or h3 == "TE:" or text:sub(1, 5) == "TPOK:" or h3 == "QU:" or h3 == "QX:"
end

-- Every addon message passes through here first. Returns "drop" for a whisper from outside
-- the party that has no business here: from a stranger, or something that needs a party.
function DadMode_RemoteHeard(text, channel, sender)
    if channel ~= "WHISPER" or ns.IsMe(sender) then return end
    local key = Key(sender)
    if not key or InParty(key) then return end
    if ns.db.helper then
        -- an answer from somebody I guide
        local k = ns.db.known and ns.db.known[key]
        if k and k.id == Id(sender) and IsAnswer(text) then
            Note(key, k.name, sender)
            state[key] = state[key] or {}
            state[key].heard, state[key].offline = GetTime(), nil
            return
        end
    elseif IsRequest(text) and DadMode_Trust and DadMode_Trust(sender) == "yes" then
        -- a request from a guide I have said yes to
        Note(key, First(sender), sender)
        return
    end
    return "drop"
end

-- Guide's side: somebody in my party answered with his status. Remember him for later.
function DadMode_Know(m, sender)
    if not ns.db.helper or m.remote then return end
    ns.db.known = ns.db.known or {}
    ns.db.known[m.key] = { name = m.name, full = sender, id = Id(sender) }
end

function DadMode_Forget(word)
    local key = Key(word)
    if key and ns.db.known and ns.db.known[key] then
        local name = ns.db.known[key].name
        ns.db.known[key], remote[key], state[key] = nil, nil, nil
        ns.questData[name] = nil
        Print(name .. " is forgotten. He is asked again the next time you are in a party with him.")
        if DadMode_RenderQuests then DadMode_RenderQuests() end
    else
        Print("Nobody by that name is remembered. Type /dadmode forget and then the first name.")
    end
end

-- Asks everybody I have guided who is not in my party. Returns how many were asked.
function DadMode_AskRemote(auto)
    if not ns.db.helper or not ns.db.known then return 0 end
    local n, now = 0, GetTime()
    for key, k in pairs(ns.db.known) do
        if n < MOST and not InParty(key) then
            n = n + 1
            Note(key, k.name, k.full)
            state[key] = state[key] or {}
            local s = state[key]
            -- somebody who was not online a moment ago is left alone for two minutes
            if not (s.offline and s.asked and now - s.asked < 120) then
                s.asked, s.offline = now, nil
                Tell(auto and "QREQ:a" or "QREQ", k.full)
            end
        end
    end
    return n
end

-- Sends something to one person: by whisper when he is outside the party
function DadMode_TellPerson(name, body, aimed)
    for key, r in pairs(remote) do
        if r.name == name and not InParty(key) then
            r.at = GetTime()
            return Tell(body, r.full)
        end
    end
    return Tell((aimed and DadMode_AimAt) and DadMode_AimAt(name, body) or body)
end

-- The answer to something a guide sent: back the way it came
function DadMode_Reply(m, body)
    if m and m.remote then return Tell(body, m.full) end
    return Tell(body)
end

-- nil = in my party. Otherwise how it stands with somebody outside it:
-- "ok" (he answered), "asking", "offline", "silent" (no answer), "gone" (not somebody I guide)
function DadMode_RemoteState(name)
    for _, m in ipairs(Party()) do
        if m.name == name then return nil end
    end
    for key, k in pairs(ns.db.known or {}) do
        if k.name == name then
            local s = state[key]
            if not s or not s.asked then return "gone" end
            if s.offline then return "offline" end
            if s.heard and s.heard >= s.asked then return "ok" end
            return (GetTime() - s.asked < 4) and "asking" or "silent"
        end
    end
    return "gone"
end

-- Lines for the window about the people outside the party who have not answered
function DadMode_RemoteLines()
    local lines = {}
    local names = {}
    for key, k in pairs(ns.db.known or {}) do
        if not InParty(key) then names[#names + 1] = k.name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local how = DadMode_RemoteState(name)
        if how == "offline" then
            lines[#lines + 1] = "|cffe8c36a" .. name .. "|r is not online."
            lines[#lines + 1] = " "
        elseif how == "asking" then
            lines[#lines + 1] = "|cff9aa0a6Asking " .. name .. "...|r"
            lines[#lines + 1] = " "
        elseif how == "silent" then
            lines[#lines + 1] = "|cffe8c36a" .. name .. "|r does not answer."
            lines[#lines + 1] = "|cff9aa0a6He is online but not in your party. To answer from outside it he needs DadMode 1.28 or newer, and he must have approved you as a guide.|r"
            lines[#lines + 1] = " "
        end
    end
    return lines
end

-- A whisper to somebody who is not online makes the game print "No player named ...".
-- That line is the answer to "is he online", and it is kept out of the chat window.
local function OnSystem(text)
    if not Usable(text, "string") or type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return false end
    local now = GetTime()
    for key, k in pairs(ns.db and ns.db.known or {}) do
        local s = state[key]
        if s and s.asked and now - s.asked < 6 then
            for _, who in ipairs({ k.full, tostring(k.full):match("^([^%-]+)") or k.full, k.name }) do
                if text == ERR_CHAT_PLAYER_NOT_FOUND_S:format(who) then
                    s.offline = true
                    if DadMode_RenderQuests then DadMode_RenderQuests() end
                    return true
                end
            end
        end
    end
    return false
end
DadMode_RemoteSystem = OnSystem

pcall(function()
    if type(ChatFrame_AddMessageEventFilter) == "function" then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, text)
            local ok, hit = pcall(OnSystem, text)
            return (ok and hit) and true or false
        end)
    else
        ns.handlers.CHAT_MSG_SYSTEM = function(text) OnSystem(text) end
    end
end)
