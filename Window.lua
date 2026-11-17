-- DadMode: the "How is <name> doing" window of a guide

local ADDON, ns = ...

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
        if ok5 and ns.Usable(zoneName, "string") and zoneName ~= "" then zone = zoneName end
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
                    if ok and ns.Usable(n, "string") then name, quality, level = n, q, l end
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
                    if ok and ns.Usable(n, "string") then name = n end
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
    local ok, records = pcall(ns.ReadQuests)
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
    local d = ns.questData[name]
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
            ns.Tell("QC:" .. cur)
            cur = ""
        end
        cur = (cur == "" and "" or (cur .. ",")) .. id
    end
    if cur ~= "" then ns.Tell("QC:" .. cur) end
end

-- The other side: which of these quests have I already done?
function DadMode_AnswerDone(text, sender)
    -- whispered back to the one who asked, unless he asked for the party channel
    local to = (sender and not DadMode_PartyOnly(sender)) and sender or nil
    local Q = C_QuestLog
    if not (Q and Q.IsQuestFlaggedCompleted) then return end
    local parts, count = {}, 0
    for id in text:gmatch("%d+") do
        count = count + 1
        if count > 60 then break end
        local ok, done = pcall(Q.IsQuestFlaggedCompleted, tonumber(id))
        if ok and ns.Usable(done, "boolean") then parts[#parts + 1] = id .. "=" .. (done and 1 or 0) end
    end
    local cur = ""
    for _, part in ipairs(parts) do
        if #cur + #part + 1 > 230 then
            ns.Tell("QD:" .. cur, to)
            cur = ""
        end
        cur = (cur == "" and "" or (cur .. ",")) .. part
    end
    if cur ~= "" then ns.Tell("QD:" .. cur, to) end
end

DadMode_AskDone = function(name) return AskDone(name) end

local STALE = 25        -- seconds without the end of a quest list before what arrived is shown as it is

local function RenderQuests()
    if not (ns.questWin and ns.questWin:IsShown()) then return end
    local filter = ns.questWin.filter
    local view = ns.questWin.view
    local myQuests = MyQuests()
    do  -- the title names the one it is about, when it is about one person
        local only, count = nil, 0
        for name in pairs(ns.questData) do only, count = name, count + 1 end
        ns.questWin.title:SetText("|cffe8c36a" .. ((count == 1) and ("How is " .. only .. " doing") or "How are they doing") .. "|r")
    end
    local now = GetTime()
    local lines, any = {}, false
    local function QuestLine(q)
        return (q.level > 0 and ("|cff9aa0a6[" .. q.level .. "]|r ") or "") .. q.title
    end
    for name, d in pairs(ns.questData) do
        any = true
        -- an old DadMode on his side can lose the end of a long list: show what did arrive
        if d.pending and now - d.pending.at > STALE then
            d.partial = { #d.pending.list, d.pending.expect }
            d.list, d.pending, d.done = d.pending.list, nil, true
            if ns.db.helper then pcall(AskDone, name) end
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

        local perm = DadMode_PermOf and DadMode_PermOf(name) or {}
        local hidden = (view == "overview" and perm.status == false and "status")
            or ((view == "quests" or view == "missing" or view == "dungeon") and perm.quests == false and "quests")
            or (view == "gear" and perm.gear == false and "gear")
        if hidden then
            lines[#lines + 1] = "|cffe8c36a" .. name .. "|r"
            lines[#lines + 1] = GREY .. name .. " does not share his " .. hidden .. " with guides.|r"
            lines[#lines + 1] = " "
        elseif view == "overview" then
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
                lines[#lines + 1] = GREY .. "No gear information. " .. name .. " needs DadMode 1.8 or newer.|r"
            end
            lines[#lines + 1] = " "
            if DadMode_BagRows then
                DadMode_BagRows(name, d, lines)
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
    if DadMode_LockLines then
        for _, line in ipairs(DadMode_LockLines()) do
            lines[#lines + 1] = line
            any = true
        end
    end
    if not any then
        if now - ns.questAsked < 4 then
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
    DadMode_LayoutBlocks(lines)
end

-- The window asks again by itself now and then. Not while a list is still coming in, and not
-- while somebody is typing in the search box: both made the list jump around.
local function AutoRefreshDue()
    if not (ns.questWin and ns.questWin:IsShown()) then return false end
    if GetTime() - ns.questAsked < 60 then return false end
    for _, d in pairs(ns.questData) do
        if d.pending then return false end
    end
    if ns.questWin.search and ns.questWin.search.typing then return false end
    return true
end
DadMode_AutoRefreshDue = AutoRefreshDue

local function AskQuests()
    ns.questAsked = GetTime()
    if DadMode_AskVersions then pcall(DadMode_AskVersions) end
    local ok, why = ns.Tell("QREQ")
    if not ok then ns.Print("|cffeb7a7aCould not ask:|r " .. tostring(why)) end
    if ok and DadMode_NoteAsk then pcall(DadMode_NoteAsk, false) end
    RenderQuests()
    if C_Timer and C_Timer.After then C_Timer.After(4.2, RenderQuests) end
end

DadMode_AskQuests = AskQuests
DadMode_RenderQuests = RenderQuests

function DadMode_ReceiveQuestData(sender, text)
    local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
    if not m then return end
    if text:sub(1, 3) == "CN:" then
        local d = ns.questData[m.name] or { list = {}, done = false }
        ns.questData[m.name] = d
        d.cons = {}
        for id, kind, count in text:sub(4):gmatch("(%d+):(%d+)=(%d+)") do
            d.cons[#d.cons + 1] = { id = tonumber(id), kind = tonumber(kind), count = tonumber(count) }
        end
    elseif text:sub(1, 3) == "GR:" then
        local d = ns.questData[m.name] or { list = {}, done = false }
        ns.questData[m.name] = d
        d.gear, d.gearAt = {}, GetTime()
        for slot, id, dur in text:sub(4):gmatch("(%d+)=(%d+):(-?%d+)") do
            d.gear[tonumber(slot)] = { id = tonumber(id), dur = tonumber(dur) }
        end
    elseif text:sub(1, 4) == "BGS:" then
        local d = ns.questData[m.name] or { list = {}, done = false }
        ns.questData[m.name] = d
        d.bagGear = {}
    elseif text:sub(1, 3) == "BG:" then
        local d = ns.questData[m.name]
        if d and d.bagGear then
            for item in text:sub(4):gmatch("item:[%-%d:]+") do
                if #d.bagGear < 16 then d.bagGear[#d.bagGear + 1] = item end
            end
        end
    elseif text:sub(1, 3) == "GL:" then
        local d = ns.questData[m.name]
        if d and d.gear then
            for slot, item in text:sub(4):gmatch("(%d+)=(item:[%-%d:]+)") do
                local g = d.gear[tonumber(slot)]
                if g then g.link = item end
            end
        end
    elseif text:sub(1, 3) == "SS:" then
        local d = ns.questData[m.name] or { list = {}, done = false }
        ns.questData[m.name] = d
        d.stats = {}
        for k, v in text:sub(4):gmatch("(%a+)=(-?%d+)") do d.stats[k] = tonumber(v) end
    elseif text:sub(1, 3) == "ST:" then
        local d = ns.questData[m.name] or { list = {}, done = false }
        ns.questData[m.name] = d
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
        local d = ns.questData[m.name] or { list = {}, done = false }
        ns.questData[m.name] = d
        d.list = d.list or {}
        -- the list on screen stays until the new one is complete
        d.pending = { list = {}, expect = tonumber(text:sub(4)) or 0, at = GetTime() }
        d.at = GetTime()
    elseif text:sub(1, 3) == "QD:" then
        local d = ns.questData[m.name]
        if d then
            d.check = d.check or {}
            for id, v in text:sub(4):gmatch("(%d+)=(%d)") do d.check[tonumber(id)] = (v == "1") end
        end
    elseif text == "QE" then
        if ns.questData[m.name] then
            local d = ns.questData[m.name]
            if d.pending then d.list, d.pending = d.pending.list, nil end
            d.done, d.partial = true, nil
            if ns.db.helper then
                local who = m.name
                pcall(AskDone, who)
                if C_Timer and C_Timer.After then C_Timer.After(4.5, function() DadMode_RenderQuests() end) end
            end
        end
    elseif text:sub(1, 2) == "Q:" and ns.questData[m.name] then
        for rec in text:sub(3):gmatch("[^%^]+") do
            local id, level, done, title, objs = rec:match("^(%d+)~(%d+)~(%d)~([^~]*)~?(.*)$")
            if id then
                local q = { id = tonumber(id), level = tonumber(level), done = done == "1", title = title, objs = {} }
                for o in objs:gmatch("[^;]+") do q.objs[#q.objs + 1] = o end
                local d = ns.questData[m.name]
                table.insert(d.pending and d.pending.list or d.list, q)
            end
        end
    end
    RenderQuests()
end

-- Makes the links inside a frame work: the mouse over an item shows the game's tooltip, a click
-- on a dungeon name opens it. The frame still drags the window.
function ns.EnableLinks(c)
    pcall(function()
        c:SetHyperlinksEnabled(true)
        c:EnableMouse(true)
        c:RegisterForDrag("LeftButton")
        c:SetScript("OnDragStart", function() ns.questWin:StartMoving() end)
        c:SetScript("OnDragStop", function() ns.questWin:StopMovingOrSizing() end)
        c:SetScript("OnHyperlinkEnter", function(self, link)
            if not GameTooltip or type(link) ~= "string" or link:sub(1, 8) == "dadmode:" then return end
            GameTooltip:SetOwner(ns.questWin, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            if ok then GameTooltip:Show() else GameTooltip:Hide() end
        end)
        c:SetScript("OnHyperlinkLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        c:SetScript("OnHyperlinkClick", function(self, link, text, button)
            if type(link) == "string" and link:sub(1, 16) == "dadmode:dungeon:" then
                -- a dungeon name on the Dungeon tab was clicked (0 = back to the list)
                local id = tonumber(link:sub(17))
                ns.questWin.dungeon = (id and id > 0) and id or false
                if ns.questWin.dungeon and ns.db.helper then
                    for name in pairs(ns.questData) do pcall(DadMode_AskDone, name) end
                end
                ns.questWin.SetView("dungeon")
            elseif type(SetItemRef) == "function" then
                pcall(SetItemRef, link, text, button)
            end
        end)
    end)
end

function DadMode_CreateQuestWindow()
    ns.questWin = CreateFrame("Frame", "DadModeQuests", UIParent)
    ns.questWin = ns.questWin
    ns.questWin:SetSize(460, 540)
    ns.questWin:SetPoint("CENTER", 220, 0)
    ns.questWin:SetFrameStrata("HIGH")
    ns.questWin:SetMovable(true)
    ns.questWin:SetClampedToScreen(true)
    ns.questWin:EnableMouse(true)
    ns.questWin:RegisterForDrag("LeftButton")
    ns.questWin:SetScript("OnDragStart", ns.questWin.StartMoving)
    ns.questWin:SetScript("OnDragStop", ns.questWin.StopMovingOrSizing)
    ns.Tex(ns.questWin, "BACKGROUND", 0.07, 0.08, 0.10, 0.97):SetAllPoints()
    local title = ns.questWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cffe8c36aHow are they doing|r")
    ns.questWin.title = title

    local close = ns.BigButton(ns.questWin, 60, 22, function() ns.questWin:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -6)
    close.label:SetText("Close")
    local again = ns.BigButton(ns.questWin, 70, 22, function() AskQuests() end)
    again:SetPoint("RIGHT", close, "LEFT", -6, 0)
    again.label:SetText("Refresh")
    ns.questWin.texts, ns.questWin.rows, ns.questWin.usedRows = {}, {}, 0
    ns.questWin.view = "overview"
    ns.questWin.filter = ""
    ns.questWin.dungeon = false          -- the dungeon picked on the Dungeon tab
    for _, b in ipairs({ close, again }) do
        ns.FontSize(b.label, 12)
    end

    -- Tabs: one thing at a time
    local TABS = { { "overview", "Overview" }, { "quests", "Quests" }, { "missing", "Missing" }, { "dungeon", "Dungeon" }, { "gear", "Gear" } }
    ns.questWin.tabs = {}
    local function SetView(view)
        ns.questWin.view = view
        for key, tab in pairs(ns.questWin.tabs) do
            local on = (key == view)
            tab.bg:SetColorTexture(on and 0.40 or 0.16, on and 0.33 or 0.18, on and 0.14 or 0.22, 1)
        end
        -- the search box belongs to the two quest lists
        local searching = (view == "quests" or view == "missing" or (view == "dungeon" and ns.questWin.dungeon and true or false))
        if ns.questWin.search then
            ns.questWin.search:SetShown(searching)
            ns.questWin.wipe:SetShown(searching)
        end
        if ns.questWin.scroll then
            ns.questWin.scroll:ClearAllPoints()
            ns.questWin.scroll:SetPoint("TOPLEFT", 12, searching and -92 or -64)
            ns.questWin.scroll:SetPoint("BOTTOMRIGHT", -12, 12)
            ns.questWin.scroll:SetVerticalScroll(0)
        end
        DadMode_RenderQuests()
    end
    ns.questWin.SetView = SetView
    for i, def in ipairs(TABS) do
        local tab = ns.BigButton(ns.questWin, 70, 22, function() SetView(def[1]) end)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 74, -36)
        tab.label:SetText(def[2])
        ns.FontSize(tab.label, 12)
        ns.questWin.tabs[def[1]] = tab
    end

    -- Search box: type part of a quest name or objective
    local search = CreateFrame("EditBox", nil, ns.questWin)
    ns.questWin.search = search
    search:SetPoint("TOPLEFT", 12, -64)
    search:SetPoint("TOPRIGHT", -38, -64)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    pcall(function() search:SetFontObject("GameFontHighlight") end)
    pcall(function() search:SetTextInsets(6, 6, 0, 0) end)
    search:SetMaxLetters(40)
    ns.Tex(search, "BACKGROUND", 0.14, 0.15, 0.18, 1):SetAllPoints()
    search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    search.hint:SetPoint("LEFT", 6, 0)
    search.hint:SetText("Search his quests...")
    local function ApplySearch(text)
        text = (type(text) == "string" and text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        ns.questWin.filter = text
        if text == "" then search.hint:Show() else search.hint:Hide() end
        if ns.questWin.scroll then ns.questWin.scroll:SetVerticalScroll(0) end
        DadMode_RenderQuests()
    end
    ns.questWin.ApplySearch = ApplySearch
    search:SetScript("OnTextChanged", function(self) ApplySearch(self:GetText()) end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function(self) self.typing = true end)
    search:SetScript("OnEditFocusLost", function(self) self.typing = false end)
    search.typing = false
    local wipe = ns.BigButton(ns.questWin, 22, 22, function()
        search:SetText("")
        search:ClearFocus()
        ApplySearch("")
    end)
    wipe:SetPoint("TOPRIGHT", -12, -64)
    ns.questWin.wipe = wipe
    wipe.label:SetText("x")
    ns.FontSize(wipe.label, 12)

    local scroll = CreateFrame("ScrollFrame", nil, ns.questWin)
    ns.questWin.scroll = scroll
    scroll:SetPoint("TOPLEFT", 12, -64)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.min(math.max((self:GetVerticalScroll() or 0) - delta * 44, 0), range))
    end)
    ns.questWin.content = CreateFrame("Frame", nil, scroll)
    ns.questWin.content:SetSize(436, 10)
    scroll:SetScrollChild(ns.questWin.content)
    ns.questWin.text = ns.questWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ns.questWin.text:SetPoint("TOPLEFT", 4, -4)
    ns.questWin.text:SetWidth(428)
    ns.questWin.text:SetJustifyH("LEFT")
    ns.questWin.text:SetJustifyV("TOP")
    ns.questWin.text:SetSpacing(2)

    -- Item names are links: the mouse over one shows the game's own tooltip
    ns.EnableLinks(ns.questWin.content)

    -- Drag the corner for a wider or taller window. The text re-wraps to the new width.
    local function Fit()
        local w = ns.questWin:GetWidth() or 460
        if w < 100 then return end
        ns.questWin.content:SetWidth(w - 24)
        if ns.questWin:IsShown() then DadMode_RenderQuests() end     -- rows and text follow the new width
    end
    pcall(function()
        ns.questWin:SetResizable(true)
        if ns.questWin.SetResizeBounds then ns.questWin:SetResizeBounds(400, 240, 1000, 1100)
        elseif ns.questWin.SetMinResize then ns.questWin:SetMinResize(400, 240) end
    end)
    if ns.db.questSize then ns.questWin:SetSize(ns.db.questSize[1], ns.db.questSize[2]) end
    local grip = ns.MakeGrip(ns.questWin)
    ns.questWin.grip = grip
    grip:SetScript("OnMouseDown", function() grip.sizing = true; ns.questWin:StartSizing("BOTTOMRIGHT") end)
    local function StopSizing()
        if not grip.sizing then return end
        grip.sizing = nil
        ns.questWin:StopMovingOrSizing()
        local w, h = ns.questWin:GetWidth(), ns.questWin:GetHeight()
        if type(w) == "number" and type(h) == "number" and w > 100 and h > 100 then ns.db.questSize = { w, h } end
        Fit()
    end
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)
    ns.questWin:SetScript("OnSizeChanged", Fit)
    Fit()
    SetView("overview")
    ns.questWin:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "DadModeQuests") end
end

function ns.OpenQuests()
    if not ns.questWin then return end
    ns.questWin:Show()
    AskQuests()
end

-- used by other files of DadMode
ns.AutoRefreshDue = AutoRefreshDue
ns.BAD = BAD
ns.GOOD = GOOD
ns.GREY = GREY
ns.Matches = Matches
ns.QUALITY = QUALITY
ns.SLOTS = SLOTS
ns.WARN = WARN
