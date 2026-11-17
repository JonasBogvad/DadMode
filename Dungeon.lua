-- DadMode: Dungeon tab: every quest Questie knows for a dungeon, and where he stands on each

-- Shared with DadMode.lua through the table the game gives every file of an addon.
-- Things that only exist after login (saved settings, windows) are read as ns.<name>.
local ADDON, ns = ...
local BAD, GOOD, GREY, Matches, Usable, WARN
    = ns.BAD, ns.GOOD, ns.GREY, ns.Matches, ns.Usable, ns.WARN

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

function DadMode_QuestsOfDungeon(id) return QuestsFor(id) end

function DadMode_DungeonQuestIds()
    local id = ns.questWin and ns.questWin.dungeon
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
    local chosen = ns.questWin.dungeon
    if not chosen then
        -- the list of dungeons to pick from. The one he stands in comes first.
        local all = Dungeons() or {}
        lines[#lines + 1] = "|cffe8c36aPick a dungeon|r"
        if #all == 0 then
            lines[#lines + 1] = GREY .. "Questie has no dungeon quests ready yet. Try again in a moment.|r"
            return
        end
        local here = d.st and d.st.z
        local function Row(dg, isHere)
            return { row = true, title = dg.name, sub = GREY .. dg.count .. " quests|r", chipsTop = true,
                chips = isHere and { { text = name .. " is here", kind = "good" } } or nil,
                button = { text = "Open", kind = "action", onClick = function() DadMode_OpenDungeon(dg.id) end } }
        end
        for _, dg in ipairs(all) do
            if here and dg.name == here then lines[#lines + 1] = Row(dg, true) end
        end
        for _, dg in ipairs(all) do
            if not (here and dg.name == here) then lines[#lines + 1] = Row(dg) end
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
    lines[#lines + 1] = "|cffe8c36a" .. name .. " in " .. title .. "|r  " .. GREY .. #ids .. " quests|r" .. progress
    lines[#lines + 1] = { tiles = {
        { label = "In his log", value = tostring(inLog), kind = "good" },
        { label = "Not picked up", value = tostring(notTaken), kind = (notTaken > 0) and "bad" or nil },
        { label = "Already done", value = tostring(finished) },
    } }
    -- is he ready to go in? The things that are too late to fix once inside.
    local st = d.st
    if st then
        local ready = {}
        if st.dur then
            local broken = (st.brk or 0) > 0
            ready[#ready + 1] = { label = "Gear", value = broken and (st.brk .. " broken, repair first") or ("worst piece " .. st.dur .. "%" .. (st.dur < 25 and ", repair first" or "")),
                kind = (broken or st.dur < 25) and "bad" or (st.dur <= 40 and "warn") or "good", wide = broken or st.dur < 25 }
        end
        if st.bf and st.bt then
            ready[#ready + 1] = { label = "Bags", value = (st.bf == 0) and "FULL" or (st.bf .. " free" .. (st.bf <= 6 and ", tight" or "")),
                kind = (st.bf <= 2 and "bad") or (st.bf <= 6 and "warn") or "good" }
        end
        if st.fd then ready[#ready + 1] = { label = "Food and drink", value = tostring(st.fd), kind = (st.fd == 0) and "bad" or nil } end
        if #ready > 0 then
            lines[#lines + 1] = GREY .. "Ready to go in?|r"
            lines[#lines + 1] = { tiles = ready }
        end
    end
    lines[#lines + 1] = { bar = true, items = { { text = "Other dungeon", onClick = function() DadMode_OpenDungeon(0) end } } }
    if filter and filter ~= "" then lines[#lines + 1] = GREY .. #rows .. " match the search|r" end
    local waited = GetTime() - (d.checkAsked or GetTime())
    local level = d.st and d.st.lv
    for _, q in ipairs(rows) do
        local his = mine[q.id]
        local state = d.check and d.check[q.id]
        local chips, sub = {}, {}
        if his then
            chips[#chips + 1] = { text = his.done and "in his log, ready to hand in" or "in his log", kind = "good" }
            if myQuests[q.id] then chips[#chips + 1] = { text = "you have it too", kind = "plain" } end
            for _, o in ipairs(his.objs) do
                local done = o:sub(1, 1) == "+"
                sub[#sub + 1] = (done and "|cff6fcf97" or "|cff9aa0a6") .. o:sub(2) .. "|r"
            end
        elseif state == true then
            chips[#chips + 1] = { text = "already done", kind = "dim" }
        elseif state == false then
            chips[#chips + 1] = { text = "not picked up", kind = "bad" }
            if myQuests[q.id] then chips[#chips + 1] = { text = "you have it", kind = "plain" } end
            local from = StartsAt(QDB, q.id)
            if from then sub[#sub + 1] = "|cffe8c36astarts at: " .. from .. "|r" end
            local need = tonumber(Field(QDB, q.id, "requiredLevel"))
            if need and level and need > level then
                sub[#sub + 1] = WARN .. "needs level " .. need .. ", he is " .. level .. "|r"
            end
        elseif not d.done then
            chips[#chips + 1] = { text = "waiting for his quest list...", kind = "dim" }
        elseif waited > 4 then
            chips[#chips + 1] = { text = "unknown, " .. name .. " needs DadMode 1.16 or newer", kind = "dim" }
        else
            chips[#chips + 1] = { text = "checking...", kind = "dim" }
        end
        lines[#lines + 1] = ns.QuestRow(q, chips, sub)
    end
end
