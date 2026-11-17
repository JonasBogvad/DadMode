-- DadMode: keeping personal data private
--
-- The one being guided whispers his status, quests and gear to the guide who asked, so no
-- other computer in the party receives them. This file is the guide's side of a safety net:
-- if a whisper does not arrive, the guide asks once more for the party channel, and remembers
-- that for this person until a whisper does get through.

local ADDON, ns = ...
local IsMe, Member, Tell = ns.IsMe, ns.Member, ns.Tell

local FIRST = "1.25.0"      -- the first version that whispers
local WAIT = 6              -- seconds without any answer before asking for the party channel
local asked = {}            -- name -> { at = time, auto = bool, fell = bool }
local bad = {}              -- name -> true: his whispers do not reach this computer

local function Whispers(m)
    local d = ns.questData[m.name]
    local v = ns.peerVersion[m.name] or (d and d.st and d.st.v)
    return v and DadMode_VersionNumber and DadMode_VersionNumber(v) >= DadMode_VersionNumber(FIRST)
end

-- An answer, as opposed to a call or a hello
local function IsAnswer(text)
    local h3 = text:sub(1, 3)
    return text == "QE" or h3 == "QS:" or h3 == "ST:" or h3 == "GR:" or text:sub(1, 2) == "Q:"
        or text:sub(1, 5) == "PERM:" or text:sub(1, 7) == "LOCKED:" or text:sub(1, 5) == "DENY:"
end

-- The guide just asked for quests and gear (auto = the addon asked by itself)
function DadMode_NoteAsk(auto)
    for _, m in ipairs(DadMode_Candidates and DadMode_Candidates() or {}) do
        if Whispers(m) then
            if bad[m.name] then
                Tell("TO:" .. m.key .. ":QREQ:" .. (auto and "ap" or "p"))
            else
                asked[m.name] = { at = GetTime(), auto = auto }
            end
        end
    end
end

-- The guide just asked for the short status
function DadMode_NoteStatusAsk()
    for _, m in ipairs(DadMode_Candidates and DadMode_Candidates() or {}) do
        if Whispers(m) and bad[m.name] then Tell("TO:" .. m.key .. ":SREQ:p") end
    end
end

-- Every message that arrives passes through here first
function DadMode_Heard(text, channel, sender)
    if IsMe(sender) then return end
    local m = Member(sender)
    if not m or not IsAnswer(text) then return end
    local a = asked[m.name]
    if channel == "WHISPER" then
        bad[m.name] = nil                       -- whispers from him do arrive
    elseif a and a.fell then
        bad[m.name] = true                      -- nothing came by whisper, the party channel worked
    end
    asked[m.name] = nil
end

function DadMode_PrivateTick()
    local now = GetTime()
    for name, a in pairs(asked) do
        if not a.fell and now - a.at > WAIT then
            a.fell, a.at = true, now
            for _, m in ipairs(ns.Party()) do
                if m.name == name then Tell("TO:" .. m.key .. ":QREQ:" .. (a.auto and "ap" or "p")) end
            end
        elseif a.fell and now - a.at > 20 then
            asked[name] = nil                   -- no answer either way: he is gone or does not answer
        end
    end
end

function DadMode_WhisperBad(name) return bad[name] == true end
