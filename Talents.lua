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

local function TabName(tab)
    if type(GetTalentTabInfo) == "function" then
        -- the name is the first or the second value, depending on the game version
        local ok, a, b = pcall(GetTalentTabInfo, tab)
        if ok and Usable(a, "string") and a ~= "" then return a end
        if ok and Usable(b, "string") and b ~= "" then return b end
    end
    return "Tree " .. tab
end

-- The classic way: the game has trees with names, and tells row and column of every talent
local function ReadClassic()
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" or type(GetNumTalents) ~= "function" then return nil end
    local okT, tabs = pcall(GetNumTalentTabs)
    if not okT or not Usable(tabs, "number") or tabs < 1 then return nil end
    local trees, any = {}, false
    for tab = 1, math.min(tabs, 5) do
        local tree = { name = TabName(tab), list = {} }
        local okN, count = pcall(GetNumTalents, tab)
        if okN and Usable(count, "number") then
            for i = 1, math.min(count, 40) do
                local ok, tname, icon, tier, column, rank, most = pcall(GetTalentInfo, tab, i)
                if ok and Usable(tname, "string") and Usable(tier, "number") and Usable(column, "number") then
                    any = true
                    tree.list[#tree.list + 1] = { index = i, name = tname, icon = icon, tier = tier, col = column,
                        rank = Usable(rank, "number") and rank or 0, most = Usable(most, "number") and most or 1 }
                end
            end
        end
        trees[#trees + 1] = tree
    end
    if not any then return nil end
    local unspent = 0
    if type(UnitCharacterPoints) == "function" then
        local ok, n = pcall(UnitCharacterPoints, "player")
        if ok and Usable(n, "number") then unspent = n end
    end
    return trees, unspent
end

-- Name and picture of a spell, whichever way this game version gives them
local function SpellLook(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and Usable(info.name, "string") then
            return info.name, Usable(info.iconID, "number") and info.iconID or nil
        end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, id)
        if ok and Usable(name, "string") then return name, Usable(icon) and icon or nil end
    end
end

-- The names of the three trees, when the game tells them
local function SpecName(i)
    local S = C_SpecializationInfo
    for _, f in ipairs({ S and S.GetSpecializationInfo, GetSpecializationInfo }) do
        if type(f) == "function" then
            local ok, a, b = pcall(f, i)
            if ok and type(a) == "table" and Usable(a.name, "string") and a.name ~= "" then return a.name end
            if ok and Usable(b, "string") and b ~= "" then return b end
        end
    end
end

-- The way WoW Forever does it: every talent of the class is a point in one big tree, with a
-- place across (posX) and down (posY). The three classic trees are groups of that tree, and
-- the game tells their names. One square of the talent window is 600 wide and 600 high.
local SQUARE, LAST_ROW, LAST_COL = 600, 12, 4

local function TraitConfig()
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
        if ok and Usable(id, "number") then return id end
    end
    local S = C_SpecializationInfo
    if S and S.GetCombatConfigIDForSpecGroup and S.GetActiveSpecGroup then
        local okG, group = pcall(S.GetActiveSpecGroup)
        if okG then
            local ok, id = pcall(S.GetCombatConfigIDForSpecGroup, group)
            if ok and Usable(id, "number") then return id end
        end
    end
end

local function TraitLook(T, config, node)
    local entryID = (type(node.activeEntry) == "table" and Usable(node.activeEntry.entryID, "number") and node.activeEntry.entryID)
        or (type(node.entryIDs) == "table" and node.entryIDs[1])
    if not (Usable(entryID, "number") and T.GetEntryInfo and T.GetDefinitionInfo) then return nil end
    local okE, entry = pcall(T.GetEntryInfo, config, entryID)
    local defID = okE and type(entry) == "table" and entry.definitionID
    if not Usable(defID, "number") then return nil end
    local okD, def = pcall(T.GetDefinitionInfo, defID)
    if not okD or type(def) ~= "table" then return nil end
    local name, icon
    if Usable(def.spellID, "number") then name, icon = SpellLook(def.spellID) end
    if Usable(def.overrideName, "string") and def.overrideName ~= "" then name = def.overrideName end
    if Usable(def.overrideIcon, "number") then icon = def.overrideIcon end
    return name, icon
end

local function ReadTraits()
    local T = C_Traits
    if not (T and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo) then return nil end
    local config = TraitConfig()
    if not config then return nil end
    local okI, info = pcall(T.GetConfigInfo, config)
    local treeID = okI and type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    if not Usable(treeID, "number") then return nil end
    local okN, nodes = pcall(T.GetTreeNodes, treeID)
    if not okN or type(nodes) ~= "table" then return nil end

    -- the trees and their names, when the game has them as groups
    local tabOf, trees = {}, {}
    if T.GetGroupDisplayInfoByTreeID then
        local okG, groups = pcall(T.GetGroupDisplayInfoByTreeID, treeID)
        if okG and type(groups) == "table" then
            for i, group in ipairs(groups) do
                if type(group) == "table" and Usable(group.groupID, "number") then
                    tabOf[group.groupID] = i
                    trees[i] = { name = (Usable(group.displayName, "string") and group.displayName ~= "") and group.displayName or ("Tree " .. i), list = {} }
                end
            end
        end
    end
    local grouped = #trees > 0

    local items, xs, seenX = {}, {}, {}
    local top
    for _, nodeID in ipairs(nodes) do
        local ok, node = pcall(T.GetNodeInfo, config, nodeID)
        if ok and type(node) == "table" and Usable(node.posX, "number") and Usable(node.posY, "number")
            and node.ID ~= 0 and node.isVisible ~= false and (not Usable(node.maxRanks, "number") or node.maxRanks > 0) then
            local tab
            if grouped then
                for _, g in ipairs(type(node.groupIDs) == "table" and node.groupIDs or {}) do
                    if tabOf[g] then tab = tabOf[g] break end
                end
            end
            if tab or not grouped then
                local name, icon = TraitLook(T, config, node)
                if name then
                    local rank = (Usable(node.activeRank, "number") and node.activeRank) or (Usable(node.ranksPurchased, "number") and node.ranksPurchased) or 0
                    items[#items + 1] = { x = node.posX, y = node.posY, tab = tab, id = Usable(node.ID, "number") and node.ID or 0,
                        name = name, icon = icon, rank = rank, most = Usable(node.maxRanks, "number") and node.maxRanks or 1 }
                    if not top or node.posY < top then top = node.posY end
                    if not seenX[node.posX] then seenX[node.posX] = true; xs[#xs + 1] = node.posX end
                end
            end
        end
    end
    if #items == 0 then return nil end

    if not grouped then
        -- no groups: the trees are the groups of columns, a wide gap starts the next one
        table.sort(xs)
        local band, count = {}, 1
        for i, x in ipairs(xs) do
            if i > 1 and x - xs[i - 1] > SQUARE * 2 then count = count + 1 end
            band[x] = count
        end
        for b = 1, count do trees[b] = { name = (count == 3 and SpecName(b)) or ("Tree " .. b), list = {} } end
        for _, it in ipairs(items) do it.tab = band[it.x] end
    end
    local left = {}
    for _, it in ipairs(items) do
        if not left[it.tab] or it.x < left[it.tab] then left[it.tab] = it.x end
    end
    -- one talent for each square; where two sit on the same square the newer one counts
    local squares = {}
    for _, it in ipairs(items) do
        it.tier = math.floor((it.y - top) / SQUARE + 0.5) + 1
        it.col = math.floor((it.x - left[it.tab]) / SQUARE + 0.5) + 1
        if it.tier <= LAST_ROW and it.col <= LAST_COL then
            local key = it.tab .. ":" .. it.tier .. ":" .. it.col
            if not squares[key] or it.id > squares[key].id then squares[key] = it end
        end
    end
    local kept = {}
    for _, it in pairs(squares) do kept[#kept + 1] = it end
    table.sort(kept, function(a, b)
        if a.tab ~= b.tab then return a.tab < b.tab end
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.col < b.col
    end)
    for _, it in ipairs(kept) do
        local list = trees[it.tab].list
        list[#list + 1] = { index = #list + 1, name = it.name, icon = it.icon, rank = it.rank, most = it.most, tier = it.tier, col = it.col }
    end

    local unspent = 0
    if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        local ok, any, a, b = pcall(C_ClassTalents.HasUnspentTalentPoints)
        if ok and any == true then unspent = (Usable(a, "number") and a or 0) + (Usable(b, "number") and b or 0) end
    end
    if unspent == 0 and type(UnitCharacterPoints) == "function" then
        local ok, n = pcall(UnitCharacterPoints, "player")
        if ok and Usable(n, "number") then unspent = n end
    end
    return trees, unspent
end

-- His trees, whichever way his game tells them: a list of { name, list of talents }, and the
-- points he has to spend. nil when the game tells neither way.
local function ReadTrees()
    local trees, unspent = ReadClassic()
    if not trees then trees, unspent = ReadTraits() end
    return trees, unspent
end

-- Returns the messages to send, or { "TE:none" } when the game does not tell
function DadMode_ReadTalents()
    local trees, unspent = ReadTrees()
    if not trees then return { "TE:none" } end
    local names, records = {}, {}
    for tab, tree in ipairs(trees) do
        names[#names + 1] = tab .. "=" .. tree.name:gsub("[~^=]", " ")
        for _, t in ipairs(tree.list) do
            local picture = ""
            if Usable(t.icon, "number") then picture = tostring(t.icon)
            elseif Usable(t.icon, "string") then picture = t.icon:gsub("^[Ii]nterface\\[Ii]cons\\", ""):gsub("[~^]", "") end
            records[#records + 1] = table.concat({ tab, t.index, t.tier, t.col, t.rank, t.most, picture, (t.name:gsub("[~^]", " ")) }, "~")
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
    msgs[#msgs + 1] = "TE:" .. (unspent or 0)
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
    local trees = ReadTrees()
    local tree = trees and trees[tab]
    local t
    for _, x in ipairs(tree and tree.list or {}) do
        if x.index == index then t = x end
    end
    if not t then return end
    ns.Beep("call")
    ns.ShowAlert("|cffffd100" .. m.name .. "|r says: put your talent point in\n|cff1aff1a" .. t.name .. "|r\n"
        .. tree.name .. ", row " .. t.tier .. " from the top", 15)
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
    if not ok then ns.Print("|cffff4d4dCould not tell him:|r " .. tostring(why)) end
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
            lines[#lines + 1] = "|cffff4d4dNo answer.|r"
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
