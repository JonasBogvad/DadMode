-- DadMode: what the one being guided reports: status, quests, gear, bags

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Quests: helpers can look at dad's quest log
---------------------------------------------------------------------------
-- Helper sends QREQ. Dad's addon answers with QS:<count>, then Q:<quests>, then QE.
-- One quest is  id~level~done~title~objective;objective   and quests are joined with ^

local questData = {}                 -- name -> { list = {}, done = bool, at = time }
lastQuestReply, ns.questAsked = 0, 0

local function Clean(text, max)
    text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[~%^;|\n\r]", " ")
    return text:sub(1, max)
end

-- Dad's side: read my quest log
local function ReadQuests()
    local out = {}
    local Q = C_QuestLog
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return out end
    local okN, n = pcall(Q.GetNumQuestLogEntries)
    if not okN or not ns.Usable(n, "number") then return out end
    for i = 1, n do
        local ok, info = pcall(Q.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and not info.isHidden
            and ns.Usable(info.title, "string") and ns.Usable(info.questID, "number") then
            local done = false
            if Q.IsComplete then
                local okD, d = pcall(Q.IsComplete, info.questID)
                done = okD and d == true
            end
            local objs = {}
            if Q.GetQuestObjectives then
                local okO, list = pcall(Q.GetQuestObjectives, info.questID)
                if okO and type(list) == "table" then
                    for _, o in ipairs(list) do
                        if #objs < 4 and type(o) == "table" and ns.Usable(o.text, "string") and o.text ~= "" then
                            objs[#objs + 1] = (o.finished == true and "+" or "-") .. Clean(o.text, 60)
                        end
                    end
                end
            end
            out[#out + 1] = table.concat({
                info.questID, ns.Usable(info.level, "number") and info.level or 0, done and 1 or 0,
                Clean(info.title, 60), table.concat(objs, ";"),
            }, "~")
        end
    end
    return out
end

-- Calls a game function if it exists and returns its first two results when they are readable
local function Get(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return ns.Usable(a) and a or nil, ns.Usable(b) and b or nil
end

local function Flag(v)
    return v == true and 1 or 0
end

local consumables = {}               -- filled by ReadStatus: "itemID:kind" -> how many

-- Dad's side: which potions, food and bandages, as  itemID:kind=count  joined by ~ (biggest stacks first)
function DadMode_ReadConsumables()
    local list = {}
    for key, count in pairs(consumables) do list[#list + 1] = { key = key, count = count } end
    table.sort(list, function(a, b) return a.count > b.count end)
    local parts, len = {}, 3
    for _, e in ipairs(list) do
        local part = e.key .. "=" .. e.count
        if len + #part + 1 > 245 then break end
        parts[#parts + 1] = part
        len = len + #part + 1
    end
    return "CN:" .. table.concat(parts, "~")
end

-- Dad's side: everything a helper might want to know, as two short messages
local function ReadStatus()
    local n, t = {}, {}                  -- numbers, texts
    n.lv = Get(UnitLevel, "player")
    local xp, xpMax = Get(UnitXP, "player"), Get(UnitXPMax, "player")
    if type(xp) == "number" and type(xpMax) == "number" and xpMax > 0 then n.xp = math.floor(xp / xpMax * 100) end
    n.g = Get(GetMoney)
    n.dead = Flag(Get(UnitIsDeadOrGhost, "player"))
    n.afk = Flag(Get(UnitIsAFK, "player"))
    n.cb = Flag(Get(UnitAffectingCombat, "player"))
    n.tp = Get(UnitCharacterPoints, "player")

    -- bags, and what is in them
    local C = C_Container
    if C and C.GetContainerNumSlots then
        local free, total, food, bandage, potion = 0, 0, 0, 0, 0
        consumables = {}
        for bag = 0, 4 do
            local size = Get(C.GetContainerNumSlots, bag)
            if type(size) == "number" and size > 0 then
                local f, family = Get(C.GetContainerNumFreeSlots, bag)
                if type(f) == "number" and (family == nil or family == 0) then
                    free, total = free + f, total + size
                end
                for slot = 1, size do
                    local info = Get(C.GetContainerItemInfo, bag, slot)
                    if type(info) == "table" and ns.Usable(info.itemID, "number") and C_Item and C_Item.GetItemInfoInstant then
                        local ok, _, _, _, _, _, class, sub = pcall(C_Item.GetItemInfoInstant, info.itemID)
                        if ok and class == 0 then
                            local count = ns.Usable(info.stackCount, "number") and info.stackCount or 1
                            if sub == 5 then food = food + count
                            elseif sub == 7 then bandage = bandage + count
                            elseif sub == 1 then potion = potion + count end
                            if sub == 5 or sub == 7 or sub == 1 then
                                local key = info.itemID .. ":" .. sub
                                consumables[key] = (consumables[key] or 0) + count
                            end
                        end
                    end
                end
            end
        end
        n.bf, n.bt, n.fd, n.bd, n.pot = free, total, food, bandage, potion
    end

    -- gear: the most worn piece, and how many are broken
    local lowest, broken = nil, 0
    for slot = 1, 18 do
        local cur, max = Get(GetInventoryItemDurability, slot)
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            local pct = math.floor(cur / max * 100)
            if not lowest or pct < lowest then lowest = pct end
            if cur == 0 then broken = broken + 1 end
        end
    end
    n.dur, n.brk = lowest, broken

    -- hearthstone: minutes until it is ready
    local start, duration
    if C and C.GetItemCooldown then start, duration = Get(C.GetItemCooldown, 6948) end
    if type(start) == "number" and type(duration) == "number" then
        n.hcd = (duration > 0) and math.max(0, math.ceil((start + duration - GetTime()) / 60)) or 0
    end

    t.z = Get(GetRealZoneText) or Get(GetZoneText)
    t.sz = Get(GetSubZoneText)
    t.hs = Get(GetBindLocation)
    if Get(UnitExists, "target") == true then
        t.tg = (GetUnitName and Get(GetUnitName, "target", false)) or Get(UnitName, "target")
    end
    t.v = ns.VERSION
    -- his class, so a guide's addon knows which armor he can wear
    if type(UnitClass) == "function" then
        local okC, _, token = pcall(UnitClass, "player")
        if okC and ns.Usable(token, "string") then t.cl = token end
    end

    local a, b = {}, {}
    for k, v in pairs(n) do
        if type(v) == "number" then a[#a + 1] = k .. "=" .. math.floor(v) end
    end
    for k, v in pairs(t) do
        if type(v) == "string" and v ~= "" then b[#b + 1] = k .. "=" .. Clean(v, 40) end
    end
    return ("ST:" .. table.concat(a, "~")):sub(1, 250), ("ST:" .. table.concat(b, "~")):sub(1, 250)
end

-- Dad's side: what he is wearing, as  slot=itemID:condition%  joined by ~
function DadMode_ReadGear()
    local parts = {}
    for slot = 1, 18 do
        local id = Get(GetInventoryItemID, "player", slot)
        if type(id) == "number" and id > 0 then
            local cur, max = Get(GetInventoryItemDurability, slot)
            local pct = (type(cur) == "number" and type(max) == "number" and max > 0) and math.floor(cur / max * 100) or -1
            parts[#parts + 1] = slot .. "=" .. id .. ":" .. pct
        end
    end
    return ("GR:" .. table.concat(parts, "~")):sub(1, 250)
end

-- The exact items he wears, with enchants and random stats, so the guide gets the real tooltip.
-- Several messages, because one item can be long.
function DadMode_ReadGearLinks()
    local msgs, cur = {}, ""
    for slot = 1, 18 do
        local link = Get(GetInventoryItemLink, "player", slot)
        local item = type(link) == "string" and link:match("item:[%-%d:]+") or nil
        if item then
            item = item:gsub(":+$", "")
            local part = slot .. "=" .. item
            if #part <= 230 then
                if cur ~= "" and #cur + #part + 1 > 230 then
                    msgs[#msgs + 1] = "GL:" .. cur
                    cur = ""
                end
                cur = (cur == "" and "" or (cur .. "~")) .. part
            end
        end
    end
    if cur ~= "" then msgs[#msgs + 1] = "GL:" .. cur end
    return msgs
end

-- His total stats. Whatever the game does not tell is simply left out.
function DadMode_ReadStats()
    local n = {}
    local function Stat(i)
        local _, eff = Get(UnitStat, "player", i)
        return eff
    end
    n.str, n.agi, n.sta, n.int, n.spi = Stat(1), Stat(2), Stat(3), Stat(4), Stat(5)
    local _, armor = Get(UnitArmor, "player")
    n.arm = armor
    n.hp = Get(UnitHealthMax, "player")
    n.mp = Get(UnitPowerMax, "player", 0)
    if type(GetSpellBonusDamage) == "function" then
        local best
        for school = 2, 7 do
            local v = Get(GetSpellBonusDamage, school)
            if type(v) == "number" and (not best or v > best) then best = v end
        end
        n.sp = best
    end
    n.heal = Get(GetSpellBonusHealing)
    local base, pos, neg = nil, nil, nil
    if type(UnitAttackPower) == "function" then
        local ok, a, b, c = pcall(UnitAttackPower, "player")
        if ok and ns.Usable(a, "number") then base, pos, neg = a, ns.Usable(b, "number") and b or 0, ns.Usable(c, "number") and c or 0 end
    end
    if base then n.ap = base + pos + neg end
    local crit = Get(GetSpellCritChance, 2)
    if type(crit) == "number" then n.scr = crit * 10 end
    local mcrit = Get(GetCritChance)
    if type(mcrit) == "number" then n.mcr = mcrit * 10 end
    local parts = {}
    for k, v in pairs(n) do
        if type(v) == "number" then parts[#parts + 1] = k .. "=" .. math.floor(v + 0.5) end
    end
    return ("SS:" .. table.concat(parts, "~")):sub(1, 250)
end

-- Things in his bags that can be worn or wielded, so a guide can see whether he is carrying
-- something better than what he has on. At most 16, as item strings like the worn gear.
-- (Global on purpose: this file is at the game's limit of 200 local names.)
function DadMode_ReadBagGear()
    local NOT_GEAR = { [""] = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_TABARD = true,
        INVTYPE_BODY = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }
    local C, I = C_Container, C_Item
    local msgs, found, cur = {}, 0, ""
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo and I and I.GetItemInfoInstant) then return msgs end
    for bag = 0, 4 do
        local size = Get(C.GetContainerNumSlots, bag)
        if type(size) == "number" then
            for slot = 1, size do
                local info = Get(C.GetContainerItemInfo, bag, slot)
                if found < 16 and type(info) == "table" and ns.Usable(info.itemID, "number") then
                    local ok, _, _, _, equipLoc, _, classID = pcall(I.GetItemInfoInstant, info.itemID)
                    if ok and ns.Usable(equipLoc, "string") and not NOT_GEAR[equipLoc] and (classID == 2 or classID == 4) then
                        local link = ns.Usable(info.hyperlink, "string") and info.hyperlink or nil
                        local item = link and link:match("item:[%-%d:]+") or ("item:" .. info.itemID)
                        item = item:gsub(":+$", "")
                        if #item <= 220 then
                            found = found + 1
                            if cur ~= "" and #cur + #item + 1 > 230 then
                                msgs[#msgs + 1] = "BG:" .. cur
                                cur = ""
                            end
                            cur = (cur == "" and "" or (cur .. "~")) .. item
                        end
                    end
                end
            end
        end
    end
    if cur ~= "" then msgs[#msgs + 1] = "BG:" .. cur end
    table.insert(msgs, 1, "BGS:" .. found)       -- start marker with the count, also when there is none
    return msgs
end

-- Answers one guide. The answer is whispered to that guide, so no other computer in the party
-- receives it. "party" = the guide asked for the party channel, because whispers did not arrive.
-- Without a sender (an old call) it goes to the party as it always did.
local answering, waitingReq, lastReplyTo, partyOnly = nil, {}, {}, {}
function DadMode_PartyOnly(sender) return partyOnly[ns.Key(sender) or ""] end

function DadMode_NextRequest()
    local nxt = table.remove(waitingReq, 1)
    answering = nil
    if nxt then DadMode_SendQuests(nxt[1], nxt[2]) end
end

function DadMode_SendQuests(sender, party)
    local key = sender and ns.Key(sender) or "*"
    if sender then partyOnly[key] = party or nil end
    if ns.outbox[1] then
        if answering == key then
            -- same guide again. If he now wants it on the party channel, switch what is still queued.
            if party then
                for i, item in ipairs(ns.outbox) do
                    if type(item) == "table" and item[2] == sender then ns.outbox[i] = item[1] end
                end
            end
            return
        end
        for _, w in ipairs(waitingReq) do
            if ns.Key(w[1]) == key then w[2] = party return end
        end
        if sender then waitingReq[#waitingReq + 1] = { sender, party } end
        return
    end
    local stamp = (party and "p" or "w")
    if lastReplyTo[key] and lastReplyTo[key][2] == stamp and GetTime() - lastReplyTo[key][1] < 5 then return end
    lastReplyTo[key] = { GetTime(), stamp }
    answering = key
    lastQuestReply = GetTime()
    local to = (sender and not party) and sender or nil
    local records = ReadQuests()
    local msgs, cur = {}, ""
    local okS, st1, st2 = pcall(ReadStatus)
    if okS then msgs[1], msgs[2] = st1, st2 end
    -- quests first: they are what the guide is waiting for
    msgs[#msgs + 1] = "QS:" .. #records
    for _, rec in ipairs(records) do
        if cur ~= "" and #cur + #rec + 1 > 235 then
            msgs[#msgs + 1] = "Q:" .. cur
            cur = ""
        end
        cur = (cur == "" and "" or (cur .. "^")) .. rec:sub(1, 235)
    end
    if cur ~= "" then msgs[#msgs + 1] = "Q:" .. cur end
    msgs[#msgs + 1] = "QE"
    local okG, gear = pcall(DadMode_ReadGear)
    if okG then msgs[#msgs + 1] = gear end
    local okL, links = pcall(DadMode_ReadGearLinks)
    if okL and type(links) == "table" then
        for _, body in ipairs(links) do msgs[#msgs + 1] = body end
    end
    local okT, stats = pcall(DadMode_ReadStats)
    if okT and stats ~= "SS:" then msgs[#msgs + 1] = stats end
    local okC, cons = pcall(DadMode_ReadConsumables)
    if okS and okC and cons ~= "CN:" then msgs[#msgs + 1] = cons end
    local okB, bagGear = pcall(DadMode_ReadBagGear)
    if okB and type(bagGear) == "table" then
        for _, body in ipairs(bagGear) do msgs[#msgs + 1] = body end
    end
    if DadMode_FilterReply then msgs = DadMode_FilterReply(msgs) end
    for _, body in ipairs(msgs) do ns.Queue(body, to) end
    ns.PumpOutbox()
end

-- used by other files of DadMode
ns.Get = Get
ns.ReadQuests = ReadQuests
ns.ReadStatus = ReadStatus
ns.questData = questData
