-- DadMode: his talents, shown to a guide the way his own talent window shows them
--
-- Nothing here is written per class. The one being guided reads whatever trees his character
-- has and sends them: name, row, column, rank and picture of every talent. The guide's addon
-- draws what arrives. So it works for every class, and keeps working when the game changes
-- its talents.
--
--   guide asks     TREQ                          (whispered when he is not in the party)
--   he answers     TT:<tree>=<name>~...           the trees
--                  TL:<record>^<record>...        talents: tree~index~row~column~rank~most~picture~name
--                  TE:<unspent points>            the end. "TE:none" = this game version does not tell
--   guide points   TPICK:<tree>:<index>           "put your point here"
--   he answers     TPOK:<tree>:<index>

local ADDON, ns = ...
local Usable = ns.Usable

local ICONS = "Interface\\Icons\\"
local lastAsk = {}          -- guide: name -> when his talents were last asked for
local lastPick = 0

---------------------------------------------------------------------------
-- His side: read the talents and send them
---------------------------------------------------------------------------

-- Returns the messages to send, or { "TE:none" } when the game does not tell
function DadMode_ReadTalents()
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" or type(GetNumTalents) ~= "function" then
        return { "TE:none" }
    end
    local okT, tabs = pcall(GetNumTalentTabs)
    if not okT or not Usable(tabs, "number") or tabs < 1 then return { "TE:none" } end
    local names, records = {}, {}
    for tab = 1, math.min(tabs, 5) do
        -- the name is the first or the second value, depending on the game version
        local name = "Tree " .. tab
        if type(GetTalentTabInfo) == "function" then
            local ok, a, b = pcall(GetTalentTabInfo, tab)
            if ok and Usable(a, "string") and a ~= "" then name = a
            elseif ok and Usable(b, "string") and b ~= "" then name = b end
        end
        names[#names + 1] = tab .. "=" .. name:gsub("[~^=]", " ")
        local okN, count = pcall(GetNumTalents, tab)
        if okN and Usable(count, "number") then
            for i = 1, math.min(count, 40) do
                local ok, tname, icon, tier, column, rank, most = pcall(GetTalentInfo, tab, i)
                if ok and Usable(tname, "string") and Usable(tier, "number") and Usable(column, "number") then
                    local picture = ""
                    if Usable(icon, "number") then picture = tostring(icon)
                    elseif Usable(icon, "string") then picture = icon:gsub("^[Ii]nterface\\[Ii]cons\\", ""):gsub("[~^]", "") end
                    records[#records + 1] = table.concat({ tab, i, tier, column,
                        Usable(rank, "number") and rank or 0, Usable(most, "number") and most or 1,
                        picture, (tname:gsub("[~^]", " ")) }, "~")
                end
            end
        end
    end
    local msgs = { "TT:" .. table.concat(names, "~") }
    local cur = ""
    for _, rec in ipairs(records) do
        if cur ~= "" and #cur + #rec + 1 > 235 then
            msgs[#msgs + 1] = "TL:" .. cur
            cur = ""
        end
        cur = (cur == "" and "" or (cur .. "^")) .. rec:sub(1, 235)
    end
    if cur ~= "" then msgs[#msgs + 1] = "TL:" .. cur end
    local unspent = 0
    if type(UnitCharacterPoints) == "function" then
        local ok, n = pcall(UnitCharacterPoints, "player")
        if ok and Usable(n, "number") then unspent = n end
    end
    msgs[#msgs + 1] = "TE:" .. unspent
    return msgs
end

local function SendTalents(m, sender)
    local msgs = DadMode_ReadTalents()
    if DadMode_FilterReply then msgs = DadMode_FilterReply(msgs) end
    -- whispered to the one who asked, unless his whispers do not arrive
    local to = (m.remote or not (DadMode_PartyOnly and DadMode_PartyOnly(sender))) and sender or nil
    for _, body in ipairs(msgs) do ns.Queue(body, to) end
    ns.PumpOutbox()
end

-- A guide points at a talent: say it big, with where to find it
local function Pointed(m, tab, index)
    if type(GetTalentInfo) ~= "function" then return end
    local ok, tname, _, tier, column = pcall(GetTalentInfo, tab, index)
    if not ok or not Usable(tname, "string") then return end
    local tree = "tree " .. tab
    if type(GetTalentTabInfo) == "function" then
        local okT, a, b = pcall(GetTalentTabInfo, tab)
        if okT and Usable(a, "string") and a ~= "" then tree = a
        elseif okT and Usable(b, "string") and b ~= "" then tree = b end
    end
    ns.Beep("call")
    ns.ShowAlert("|cffe8c36a" .. m.name .. "|r says: put your talent point in\n|cff6fcf97" .. tname .. "|r\n"
        .. tree .. (Usable(tier, "number") and (", row " .. tier .. " from the top") or ""), 15)
    DadMode_Reply(m, "TPOK:" .. tab .. ":" .. index)
end

---------------------------------------------------------------------------
-- Guide's side
---------------------------------------------------------------------------

-- Asks one person, or everybody on the page, for his talents. Not more often than every 20 seconds.
function DadMode_AskTalents(force)
    local now = GetTime()
    for name in pairs(ns.questData) do
        local away = DadMode_RemoteState and DadMode_RemoteState(name)
        if (away == nil or away == "ok") and (force or now - (lastAsk[name] or -999) > 20) then
            lastAsk[name] = now
            DadMode_TellPerson(name, "TREQ", true)
        end
    end
end

function DadMode_TalentsAskedAt(name) return lastAsk[name] end

-- A guide clicked a talent in the window
function DadMode_PointAtTalent(name, tab, index, tname)
    if GetTime() - lastPick < 3 then return end
    lastPick = GetTime()
    local ok, why = DadMode_TellPerson(name, "TPICK:" .. tab .. ":" .. index, true)
    local d = ns.questData[name]
    if d and d.talents then d.talents.pointed = ok and { tab = tab, index = index, state = "asked" } or nil end
    if not ok then ns.Print("|cffeb7a7aCould not tell him:|r " .. tostring(why)) end
    DadMode_RenderQuests()
end

local function Receive(m, text)
    local d = ns.questData[m.name] or { list = {}, done = false }
    ns.questData[m.name] = d
    local head = text:sub(1, 3)
    if head == "TT:" then
        d.talPending = { trees = {}, at = GetTime() }
        for tab, name in text:sub(4):gmatch("(%d+)=([^~]*)") do
            d.talPending.trees[tonumber(tab)] = { name = name, list = {}, points = 0 }
        end
    elseif head == "TL:" and d.talPending then
        for rec in text:sub(4):gmatch("[^%^]+") do
            local tab, i, tier, col, rank, most, picture, name = rec:match("^(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]*)~(.*)$")
            local tree = tab and d.talPending.trees[tonumber(tab)]
            if tree then
                rank = tonumber(rank)
                tree.list[#tree.list + 1] = { tab = tonumber(tab), index = tonumber(i), tier = tonumber(tier), col = tonumber(col),
                    rank = rank, most = tonumber(most), name = name,
                    icon = (picture == "" and nil) or tonumber(picture) or (ICONS .. picture) }
                tree.points = tree.points + rank
            end
        end
    elseif head == "TE:" then
        if text == "TE:none" then
            d.talents, d.talPending = { none = true, at = GetTime() }, nil
        elseif d.talPending then
            local old = d.talents
            d.talents, d.talPending = d.talPending, nil
            d.talents.unspent = tonumber(text:sub(4)) or 0
            d.talents.pointed = old and old.pointed or nil
        end
    end
end

-- Returns true when the message belonged to this feature
function DadMode_TalentMessage(text, sender)
    local head = text:sub(1, 3)
    local mine = text == "TREQ" or head == "TT:" or head == "TL:" or head == "TE:"
        or text:sub(1, 6) == "TPICK:" or text:sub(1, 5) == "TPOK:"
    if not mine then return false end
    local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
    if not m then return true end
    if text == "TREQ" then
        if not ns.db.helper then SendTalents(m, sender) end
    elseif text:sub(1, 6) == "TPICK:" then
        local tab, index = text:match("^TPICK:(%d+):(%d+)$")
        if tab and not ns.db.helper then Pointed(m, tonumber(tab), tonumber(index)) end
    elseif text:sub(1, 5) == "TPOK:" then
        local d = ns.questData[m.name]
        if d and d.talents and d.talents.pointed then d.talents.pointed.state = "seen" end
        DadMode_RenderQuests()
    elseif ns.db.helper then
        Receive(m, text)
        DadMode_RenderQuests()
    end
    return true
end

-- The Talents tab: the blocks for one person
function DadMode_TalentBlocks(name, d, lines, now)
    local t = d.talents
    if not t then
        local asked = lastAsk[name]
        if d.talPending then
            lines[#lines + 1] = ns.GREY .. "Loading his talents...|r"
        elseif asked and now - asked < 6 then
            lines[#lines + 1] = ns.GREY .. "Asking for his talents...|r"
        else
            lines[#lines + 1] = "|cffeb7a7aNo answer.|r"
            lines[#lines + 1] = ns.GREY .. name .. " needs DadMode 1.31 or newer to show his talents.|r"
        end
        return
    end
    if t.none then
        lines[#lines + 1] = ns.GREY .. "His game does not let an addon read talents on this version.|r"
        return
    end
    local unspent = t.unspent or 0
    lines[#lines + 1] = (unspent > 0 and (ns.WARN .. unspent .. " talent point" .. (unspent > 1 and "s" or "") .. " to spend|r")
        or (ns.GREY .. "No talent points to spend|r"))
        .. "   " .. ns.GREY .. "Click a talent to point at it for him.|r"
    if t.pointed then
        local what
        for _, tree in pairs(t.trees) do
            for _, tal in ipairs(tree.list) do
                if tal.tab == t.pointed.tab and tal.index == t.pointed.index then what = tal.name end
            end
        end
        if what then
            lines[#lines + 1] = (t.pointed.state == "seen") and (ns.GOOD .. "He sees it: " .. what .. "|r")
                or (ns.GREY .. "Told him: " .. what .. "...|r")
        end
    end
    local trees = {}
    for tab = 1, 5 do
        local tree = t.trees[tab]
        if tree then
            trees[#trees + 1] = { name = tree.name, points = tree.points, list = tree.list,
                onClick = function(tal) DadMode_PointAtTalent(name, tal.tab, tal.index, tal.name) end }
        end
    end
    lines[#lines + 1] = { trees = trees, pointed = t.pointed }
end
