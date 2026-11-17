-- DadMode: doing a quest or a dungeon together. A small list on the guide's screen that shows
-- the progress of the one being guided, and updates the moment his progress changes.
--
-- What is on the list, without anybody choosing:
--   in a dungeon     his quests for that dungeon (needs Questie on the guide's computer)
--   anywhere else    the quests both of them have, and the ones the guide pinned with "Track"
--
--   his addon sends   QU:<quest record>   one quest changed (same record as in the quest list)
--                     QX:<quest id>       a quest left his log
--   a guide sends     QW                  "keep me posted", now and then, no answer expected
-- His addon keeps a guide posted for five minutes after that guide last asked for anything.

local ADDON, ns = ...
local Usable = ns.Usable

local FIRST = "1.32.0"      -- the first version that sends changes by itself
local MOST = 6              -- lines on the list
local WATCH = 300           -- seconds a guide stays posted after he last asked
local BATCH = 2             -- seconds between two rounds of changes

---------------------------------------------------------------------------
-- His side: tell the guides when a quest changes
---------------------------------------------------------------------------

local watchers = {}         -- key -> { sender, at, remote }
local known                 -- quest id -> the record the guides have
local dirty, lastBatch = true, 0

-- Every message passes through here: a guide who asks for something is kept posted
function DadMode_TrackHeard(text, sender)
    if ns.db.helper or ns.IsMe(sender) then return end
    local head = text:sub(1, 4)
    if not (text == "QW" or head == "QREQ" or head == "SREQ") then return end
    local m = ns.Member(sender)
    if not m or not DadMode_Trust or DadMode_Trust(sender) ~= "yes" then return end
    watchers[m.key] = { sender = sender, at = GetTime(), remote = m.remote }
end

local function Records()
    local map = {}
    local ok, records = pcall(ns.ReadQuests)
    if not ok or type(records) ~= "table" then return nil end
    for _, rec in ipairs(records) do
        local id = tonumber(rec:match("^(%d+)~"))
        if id then map[id] = rec:sub(1, 235) end
    end
    return map
end

local function SendToWatchers(body, now)
    local all, any = true, false
    for key, w in pairs(watchers) do
        if now - w.at > WATCH then
            watchers[key] = nil
        else
            any = true
            -- to him alone, unless sending to one person does not reach him
            local alone = w.remote or not (DadMode_PartyOnly and DadMode_PartyOnly(w.sender))
            local ok = ns.Tell(body, alone and w.sender or nil)
            if not ok then all = false end
        end
    end
    return all, any
end

local function GuidedTick(now)
    if not dirty or now - lastBatch < BATCH then return end
    lastBatch = now
    local map = Records()
    if not map then return end
    local sharing = not (ns.db.perm and ns.db.perm.quests == false)
    local anyone = false
    for key, w in pairs(watchers) do
        if now - w.at > WATCH then watchers[key] = nil else anyone = true end
    end
    -- nobody to tell: just remember how things stand. A guide who asks gets the whole list anyway.
    if not known or not anyone or not sharing then
        known, dirty = map, false
        return
    end
    local sent, left = 0, false
    for id, rec in pairs(map) do
        if known[id] ~= rec then
            if sent >= MOST then left = true
            else
                sent = sent + 1
                -- the game may refuse in a fight or a dungeon: then it is tried again next round
                if SendToWatchers("QU:" .. rec, now) then known[id] = rec else left = true end
            end
        end
    end
    for id in pairs(known) do
        if not map[id] then
            if sent >= MOST then left = true
            else
                sent = sent + 1
                if SendToWatchers("QX:" .. id, now) then known[id] = nil else left = true end
            end
        end
    end
    dirty = left
end

ns.handlers.QUEST_LOG_UPDATE = function() dirty = true end

---------------------------------------------------------------------------
-- Guide's side: what is on the list
---------------------------------------------------------------------------

local mineAt, mine = -999, {}
local function MyQuests()
    if GetTime() - mineAt > 2 then mineAt, mine = GetTime(), ns.MyQuests() end
    return mine
end

local function Pinned(name)
    ns.db.pinned = ns.db.pinned or {}
    local key = tostring(name):lower()
    ns.db.pinned[key] = ns.db.pinned[key] or {}
    return ns.db.pinned[key]
end

function DadMode_IsPinned(name, id) return Pinned(name)[id] == true end

function DadMode_TogglePin(name, id)
    local pins = Pinned(name)
    pins[id] = (not pins[id]) or nil
    if ns.db.tracker == false then ns.db.tracker = nil end      -- pinning something brings the list back if it was closed
    DadMode_RenderQuests()
end

-- The dungeon I am standing in: { id, name } with Questie's number for it, { name = ... } when
-- Questie does not know it, nil outside dungeons. Looked up at most every three seconds.
local dungeonAt, dungeonNow = -999, nil
local function CurrentDungeon()
    local now = GetTime()
    if now - dungeonAt < 3 then return dungeonNow end
    dungeonAt, dungeonNow = now, nil
    if type(IsInInstance) ~= "function" then return nil end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or not Usable(inside, "boolean") or not inside or kind ~= "party" then return nil end
    local name
    if type(GetInstanceInfo) == "function" then
        local okI, n = pcall(GetInstanceInfo)
        if okI and Usable(n, "string") and n ~= "" then name = n end
    end
    if not name and type(GetRealZoneText) == "function" then
        local okZ, z = pcall(GetRealZoneText)
        if okZ and Usable(z, "string") and z ~= "" then name = z end
    end
    dungeonNow = { name = name or "this dungeon" }
    for _, dg in ipairs(DadMode_Dungeons and DadMode_Dungeons() or {}) do
        if dg.name == name then dungeonNow = { id = dg.id, name = dg.name } end
    end
    return dungeonNow
end

local function DungeonSet(dg)
    if not (dg and dg.id and DadMode_QuestsOfDungeon) then return nil end
    local set = {}
    for _, id in ipairs(DadMode_QuestsOfDungeon(dg.id) or {}) do set[id] = true end
    return set
end

-- "6/15" or "6/15, 2/4": what is left of a quest, short enough for one line
local function Progress(q)
    if q.done then return "ready" end
    local parts = {}
    for _, o in ipairs(q.objs) do
        if o:sub(1, 1) ~= "+" and #parts < 2 then
            parts[#parts + 1] = o:sub(2):match("^(%d+/%d+)") or o:sub(2, 22)
        end
    end
    return (#parts > 0) and table.concat(parts, ", ") or "not done"
end

-- Is this quest of his one of those being followed right now?
local function Tracked(name, id)
    local set = DungeonSet(CurrentDungeon())
    if set then return set[id] == true end
    return MyQuests()[id] ~= nil or Pinned(name)[id] == true
end

-- The people to show: the one chosen on the guide bar, or everybody who is being guided
local function People()
    local out = {}
    local picked = DadMode_TargetName and DadMode_TargetName() or nil
    for _, m in ipairs(DadMode_Candidates and DadMode_Candidates() or {}) do
        if (not picked or m.name == picked) and ns.questData[m.name] then out[#out + 1] = m.name end
    end
    return out
end

-- Returns the heading, the lines { left, right, name, q }, and a small line for the bottom
function DadMode_TrackerLines()
    local people = People()
    if #people == 0 then return nil, {}, nil end
    local now = GetTime()
    local dg = CurrentDungeon()
    local set = DungeonSet(dg)
    local my = MyQuests()
    local lines, more, oldest, foot = {}, 0, nil, nil
    for _, name in ipairs(people) do
        local d = ns.questData[name]
        local list = {}
        for _, q in ipairs(d.list or {}) do
            local on
            if set then on = set[q.id] else on = my[q.id] ~= nil or Pinned(name)[q.id] end
            if on then list[#list + 1] = q end
        end
        table.sort(list, function(a, b)
            if a.done ~= b.done then return not a.done end
            return a.title < b.title
        end)
        for _, q in ipairs(list) do
            if #lines >= MOST then
                more = more + 1
            else
                local me = my[q.id]
                local behind = me and me.done and not q.done        -- I am done and he is not: do not run off
                local right = q.done and (ns.GOOD .. "ready to hand in|r") or ((behind and ns.WARN or "|cffffffff") .. Progress(q) .. "|r")
                if me then right = right .. ns.GREY .. "  you " .. Progress(me) .. "|r" end
                lines[#lines + 1] = { left = ((#people > 1) and (name .. ": ") or "") .. q.title, right = right, name = name, q = q, mine = me }
            end
        end
        local at = math.max(d.liveAt or 0, d.at or 0)
        if not oldest or at < oldest then oldest = at end
        local v = ns.peerVersion[name] or (d.st and d.st.v)
        if v and DadMode_VersionNumber(v) < DadMode_VersionNumber(FIRST) then
            foot = name .. " needs DadMode 1.32 for this to follow along by itself"
        end
    end
    local who = (#people == 1) and people[1] or "Their"
    local title = (#people == 1) and (dg and (who .. " in " .. dg.name) or (who .. "'s quests")) or (dg and ("In " .. dg.name) or "Their quests")
    if more > 0 then foot = "and " .. more .. " more" end
    -- in a dungeon the game may hold messages back: say how old the numbers are
    if dg and oldest and now - oldest > 90 then
        foot = "from " .. math.floor((now - oldest) / 60 + 0.5) .. " min ago, the game holds messages back in here"
    end
    if #lines == 0 then
        if dg and set then
            lines[1] = { left = ns.GREY .. "None of his quests are for this dungeon|r", right = "" }
        elseif dg then
            lines[1] = { left = ns.GREY .. "Questie is needed to know this dungeon's quests|r", right = "" }
        else
            return title, {}, nil       -- nothing shared and nothing pinned: no list
        end
    end
    return title, lines, foot
end

-- A change from him
local function Parse(rec)
    local id, level, done, title, objs = rec:match("^(%d+)~(%d+)~(%d)~([^~]*)~?(.*)$")
    if not id then return nil end
    local q = { id = tonumber(id), level = tonumber(level), done = done == "1", title = title, objs = {} }
    for o in objs:gmatch("[^;]+") do q.objs[#q.objs + 1] = o end
    return q
end

local function Apply(list, q, id)
    for i, old in ipairs(list) do
        if old.id == id then
            if q then list[i] = q else table.remove(list, i) end
            return old
        end
    end
    if q then list[#list + 1] = q end
end

-- Returns true when the message belonged to this feature
function DadMode_TrackMessage(text, sender)
    local head = text:sub(1, 3)
    if text == "QW" then return true end
    if head ~= "QU:" and head ~= "QX:" then return false end
    local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
    if not m or not ns.db.helper then return true end
    local d = ns.questData[m.name]
    if not d or not d.list then return true end        -- his whole list has to be here first
    local q = (head == "QU:") and Parse(text:sub(4)) or nil
    local id = q and q.id or tonumber(text:sub(4))
    if not id then return true end
    local old = Apply(d.list, q, id)
    if d.pending and d.pending.list then Apply(d.pending.list, q, id) end
    d.liveAt = GetTime()
    if q and q.done and not (old and old.done) and Tracked(m.name, id) then
        local who, zone = DadMode_TurnIn(id)
        ns.Print("|cff1aff1a" .. m.name .. " finished " .. q.title .. ".|r"
            .. (who and (" Hand in: " .. who .. (zone and (", " .. zone) or "") .. ".") or ""))
    end
    if ns.questWin and ns.questWin:IsShown() then DadMode_RenderQuests() end
    return true
end

---------------------------------------------------------------------------
-- The list on the screen
---------------------------------------------------------------------------

local frame
local WIDTH = 300

local function Create()
    frame = CreateFrame("Frame", "DadModeTracker", UIParent)
    frame:SetSize(WIDTH, 60)
    local pos = ns.db.trackerPos
    if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80) end
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        if point then ns.db.trackerPos = { point, rel, x, y } end
    end)
    ns.WindowLook(frame, 0.88)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 10, -8)
    frame.title:SetJustifyH("LEFT")
    frame.close = ns.BigButton(frame, 18, 16, function()
        ns.db.tracker = false
        frame:Hide()
        ns.Print("The quest list is put away. The Quest list button on the guide bar brings it back.")
    end)
    frame.close:SetPoint("TOPRIGHT", -6, -6)
    frame.close.label:SetText("x")
    ns.FontSize(frame.close.label, 11)
    frame.close.bg:SetColorTexture(ns.LOOK.quiet[1], ns.LOOK.quiet[2], ns.LOOK.quiet[3], 1)
    frame.foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.foot:SetJustifyH("LEFT")
    frame.rows = {}
    frame:Hide()
end

local function Row(i)
    if frame.rows[i] then return frame.rows[i] end
    local r = CreateFrame("Button", nil, frame)
    r:SetSize(WIDTH - 20, 16)
    r:SetPoint("TOPLEFT", 10, -12 - i * 17)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT")
    r.left:SetWidth(150)
    r.left:SetJustifyH("LEFT")
    pcall(function() r.left:SetWordWrap(false) end)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT")
    r.right:SetJustifyH("RIGHT")
    r.line = false
    r:SetScript("OnEnter", function(self)
        local l = self.line
        if not (l and l.q and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(l.q.title, 1, 0.82, 0)
        for _, o in ipairs(l.q.objs) do
            local done = o:sub(1, 1) == "+"
            GameTooltip:AddLine(l.name .. ": " .. o:sub(2), done and 0.1 or 1, 1, done and 0.1 or 1)
        end
        if l.q.done then
            local who, zone = DadMode_TurnIn(l.q.id)
            GameTooltip:AddLine("Ready to hand in" .. (who and (": " .. who .. (zone and (", " .. zone) or "")) or ""), 0.1, 1, 0.1)
        end
        if l.mine then
            for _, o in ipairs(l.mine.objs) do GameTooltip:AddLine("You: " .. o:sub(2), 0.7, 0.7, 0.7) end
        else
            GameTooltip:AddLine("You do not have this quest", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Click to open it in the window", 0.1, 1, 0.1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnClick", function(self)
        local l = self.line
        if not (l and l.q and ns.questWin) then return end
        ns.OpenQuests()
        ns.questWin.SetView("quests")
        if ns.questWin.search then ns.questWin.search:SetText(l.q.title) end
        ns.questWin.ApplySearch(l.q.title)
    end)
    frame.rows[i] = r
    return r
end

local function Draw()
    if not frame then Create() end
    local title, lines, foot = nil, {}, nil
    if ns.db.helper and ns.db.tracker ~= false then title, lines, foot = DadMode_TrackerLines() end
    if not title or #lines == 0 then
        -- asked for with the button, and nothing to follow yet: say how it fills
        if ns.db.helper and ns.db.tracker == true then
            foot = nil
            if title then
                lines = { { left = ns.GREY .. "Nothing to follow yet. It fills by itself when|r" },
                          { left = ns.GREY .. "you both have the same quest. Or click Track|r" },
                          { left = ns.GREY .. "on one of their quests in the Quests tab.|r" } }
            else
                title = "Quest list"
                lines = { { left = ns.GREY .. "Nobody to guide in your party right now.|r" } }
            end
        else
            if frame:IsShown() then frame:Hide() end
            return
        end
    end
    frame.title:SetText("|cffffd100" .. title .. "|r")
    for i, l in ipairs(lines) do
        local r = Row(i)
        r.left:SetWidth(l.q and 150 or (WIDTH - 20))
        r.left:SetText(l.left)
        r.right:SetText(l.right or "")
        r.line = l
        r:Show()
    end
    for i = #lines + 1, #frame.rows do
        frame.rows[i].line = false
        frame.rows[i]:Hide()
    end
    local h = 30 + #lines * 17
    if foot then
        frame.foot:ClearAllPoints()
        frame.foot:SetPoint("TOPLEFT", 10, -h + 2)
        frame.foot:SetText(foot)
        frame.foot:Show()
        h = h + 16
    else
        frame.foot:SetText("")
        frame.foot:Hide()
    end
    frame:SetHeight(h + 6)
    if not frame:IsShown() then frame:Show() end
end
DadMode_DrawTracker = Draw

-- The button on the guide bar and /dadmode tracker: put the list away when it is showing, show
-- it when it is not. Shown this way it stays, also with nothing to follow.
function DadMode_ToggleTracker()
    if not frame then Create() end
    ns.db.tracker = not frame:IsShown()
    Draw()
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------

local lastDraw, lastWatch, wasIn = 0, 0, nil

-- Coming out of a dungeon: what he still needs from it
local function AfterDungeon(dg)
    local set = DungeonSet(dg)
    if not set then return end
    for _, name in ipairs(People()) do
        local left, had = {}, false
        for _, q in ipairs(ns.questData[name].list or {}) do
            if set[q.id] then
                had = true
                if not q.done then left[#left + 1] = q.title .. " (" .. Progress(q) .. ")" end
            end
        end
        if #left > 0 then
            ns.Print("|cffffd100" .. name .. " still needs from " .. dg.name .. ":|r " .. table.concat(left, ", "))
        elseif had then
            ns.Print("|cff1aff1a" .. name .. " has everything he needs from " .. dg.name .. ".|r")
        end
    end
end

function DadMode_TrackTick()
    if not ns.db then return end
    local now = GetTime()
    if not ns.db.helper then
        GuidedTick(now)
        return
    end
    if now - lastDraw < 0.5 then return end
    lastDraw = now
    local dg = CurrentDungeon()
    if wasIn and not dg then pcall(AfterDungeon, wasIn) end
    wasIn = dg
    -- keep his addon telling me, also when the guide bar is hidden
    if #People() > 0 and now - lastWatch > 60 then
        lastWatch = now
        ns.Tell("QW")
    end
    Draw()
end

function DadMode_TrackDirty() dirty = true end      -- for testing
