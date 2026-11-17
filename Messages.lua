-- DadMode: sending messages to the party or to one person, at the pace the game allows

local ADDON, ns = ...

-- Every message DadMode sends, in one place. All of them travel on the game's hidden addon
-- channel under the label "DADMODE"; none of them shows up in chat.
--
--   Sent to the whole party (nothing personal in them)
--     PING:<text>            a call                      CLEAR              the call is cancelled
--     ACK  HERE  MUTED       answers to a call           VER:<version>      sent along with ACK
--     WP:<map>:<x>:<y>       a waypoint                  WPC                remove the waypoint
--     WPOK  WPNO  WPHERE     answers to a waypoint       TS:<stop>=<c>:<n>:<w>~...   zeppelin and boat spots
--     WEAR:<item>            "put this on"               WEARSEEN/OK/NO/GONE:<id>    answers to that
--     HI:<version>:<g|d>     version and role            HI?                everybody say HI
--     QREQ  QREQ:a  QREQ:p   ask for status, quests and gear (a = the addon asked, p = answer on the party channel)
--     SREQ  SREQ:p           ask for the short status    QC:<id>,<id>       which of these quests are done?
--     LOCKED:<ask|no>:<name>  DENY:<what>:<name>  UNLOCK:<name>             approval answers, for one guide
--     TO:<name>:<message>    any of the above, meant for one person only
--
--   Whispered to the one guide who asked (personal: no other computer receives them)
--     PERM:status=1~gold=0~...   what he shares          ST:<key>=<value>~...   status, two messages
--     QS:<count>  Q:<quests>  QE  the quest log          QD:<id>=<0|1>,...       answer to QC
--     GR:<slot>=<item>:<condition>~...   GL:<slot>=<item string>~...   SS:<stat>=<n>~...   gear and stats
--     BGS:<count>  BG:<item string>~...  gear in the bags              CN:<item>:<kind>=<n>~...  consumables
--   If a whisper does not arrive, Private.lua asks again with ":p" and the answer comes on the party channel.

local REFUSED = {
    [3] = "you are sending too fast", [8] = "you are sending too fast",
    [5] = "you are not in a party", [11] = "the game blocks addon messages right now (dungeon or fight)",
}

-- Returns true when the game accepted the message, otherwise false and the reason
-- Sends one message. Without "to" it goes to the whole party. With "to" (a name exactly as the
-- game reported it) it is whispered to that one person, and nobody else's computer receives it.
local function Tell(body, to)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "this game version has no addon messages" end
    local ok, res
    if to then
        ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, body, "WHISPER", to)
    else
        ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, body, "PARTY")
    end
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
        local item = outbox[1]
        local ok, _, code
        if type(item) == "table" then ok, _, code = Tell(item[1], item[2]) else ok, _, code = Tell(item) end
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
    -- somebody else asked while this answer was going out: now it is their turn
    if not outbox[1] and DadMode_NextRequest then DadMode_NextRequest() end
end
DadMode_PumpOutbox = PumpOutbox

-- to = whisper it to this one person; without it the message goes to the party
local function Queue(body, to)
    if not outbox[1] and GetTime() - outbox.at > 12 then outbox.burst = 0 end
    outbox[#outbox + 1] = to and { body, to } or body
end

-- used by other files of DadMode
ns.PumpOutbox = PumpOutbox
ns.Queue = Queue
ns.Tell = Tell
ns.outbox = outbox
