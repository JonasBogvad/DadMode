-- DadMode: Gear comparison: any item a guide looks at, against what the one being guided wears

-- Shared with DadMode.lua through the table the game gives every file of an addon.
-- Things that only exist after login (saved settings, windows) are read as ns.<name>.
local ADDON, ns = ...
local BAD, Beep, BigButton, GOOD, GREY, Get, InFight, IsMe, Member, Party, Print, QUALITY, SLOTS, Secret, ShowAlert, Tell, Usable, WARN, call, handlers, questData, slots
    = ns.BAD, ns.Beep, ns.BigButton, ns.GOOD, ns.GREY, ns.Get, ns.InFight, ns.IsMe, ns.Member, ns.Party, ns.Print, ns.QUALITY, ns.SLOTS, ns.Secret, ns.ShowAlert, ns.Tell, ns.Usable, ns.WARN, ns.call, ns.handlers, ns.questData, ns.slots

-- where an item goes
local EQUIP = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local ARMOR = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate" }
-- the heaviest armor a class wears: below level 40, and from 40
local HEAVIEST = {
    PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 },
    ROGUE = { 2, 2 }, DRUID = { 2, 2 }, MONK = { 2, 2 }, DEMONHUNTER = { 2, 2 },
    HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, EVOKER = { 3, 3 },
    WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, DEATHKNIGHT = { 4, 4 },
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }

local function Info(link)
    local I = C_Item
    if not (I and I.GetItemInfoInstant) then return nil end
    local ok, id, _, _, equipLoc, _, classID, subID = pcall(I.GetItemInfoInstant, link)
    if not ok or not Usable(id, "number") or not Usable(equipLoc, "string") then return nil end
    local out = { id = id, loc = equipLoc, class = classID, sub = subID }
    if I.GetItemInfo then
        local okI, name, _, quality, level, minLevel = pcall(I.GetItemInfo, link)
        if okI then
            out.name = Usable(name, "string") and name or nil
            out.quality = Usable(quality, "number") and quality or nil
            out.level = Usable(level, "number") and level or nil
            out.need = Usable(minLevel, "number") and minLevel or nil
        end
    end
    if I.GetDetailedItemLevelInfo then
        local okL, real = pcall(I.GetDetailedItemLevelInfo, link)
        if okL and Usable(real, "number") and real > 0 then out.level = real end
    end
    return out
end

local function Stats(link)
    local f = (C_Item and C_Item.GetItemStats) or GetItemStats
    if type(f) ~= "function" then return nil end
    local ok, t = pcall(f, link)
    if ok and type(t) == "table" and not Secret(t) then return t end
end

-- What changes when he swaps old for new: two lists of plain text, "+6 Stamina" and "-3 Spirit".
-- oldLink = nil compares against an empty slot.
local function Difference(newLink, oldLink)
    local a, b = Stats(newLink), oldLink and Stats(oldLink) or {}
    if not a or not b then return nil end
    local keys, seen = {}, {}
    for k in pairs(a) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
    for k in pairs(b) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
    table.sort(keys)
    local gains, loses, parts = {}, {}, {}
    for _, k in ipairs(keys) do
        local va, vb = a[k], b[k]
        if (va == nil or Usable(va, "number")) and (vb == nil or Usable(vb, "number")) then
            local diff = (va or 0) - (vb or 0)
            if diff ~= 0 and #gains + #loses < 8 then
                local label = (type(_G[k]) == "string" and _G[k]) or tostring(k):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower()
                local size = ("%g"):format(math.floor(math.abs(diff) * 10 + 0.5) / 10)
                local text = (diff > 0 and "+" or "-") .. size .. " " .. label
                if diff > 0 then gains[#gains + 1] = text else loses[#loses + 1] = text end
                parts[#parts + 1] = { key = k, label = label, diff = diff, text = text }
            end
        end
    end
    return gains, loses, parts
end

-- Compares one item against what one person wears.
-- Returns nil when it is not something to wear, otherwise a table:
--   cannot = text why he can not wear it, or
--   worn = his item in that slot (nil = empty), wornLevel, level, gap (level minus wornLevel),
--   gains and loses (lists of text), parts (each stat: key, label, diff, text), same.
-- It only states facts. Whether the item is better for him depends on how he plays, and that
-- is for the guide to judge.
local function Compare(link, d)
    local it = Info(link)
    if not it or not d or not d.gear then return nil end
    local slots = EQUIP[it.loc]
    if not slots then return nil end
    local res = { level = it.level, name = it.name, quality = it.quality, slot = slots[1] }
    local class, lv = d.st and d.st.cl, d.st and d.st.lv
    local heavy = class and HEAVIEST[class]
    if it.class == 4 and ARMOR[it.sub] and heavy and it.loc ~= "INVTYPE_CLOAK" then
        local most = (lv and lv >= 40) and heavy[2] or heavy[1]
        if it.sub > most then
            res.cannot = "can not wear " .. ARMOR[it.sub]
            return res
        end
        res.lighter = (it.sub < most) and ARMOR[it.sub] or nil      -- wearable, but not his armor type
        res.most = ARMOR[most]
    end
    if it.loc == "INVTYPE_SHIELD" and class and not SHIELD[class] then
        res.cannot = "can not use shields"
        return res
    end
    if it.need and lv and it.need > lv then res.needs = it.need end
    -- with two slots (rings, trinkets, one-hand weapons) compare against the weaker one
    local pick, pickLevel
    for _, slot in ipairs(slots) do
        local g = d.gear[slot]
        if g and g.id == it.id then res.same = true end
        local wornLevel = -1
        if g then
            local w = Info(g.link or ("item:" .. g.id))
            wornLevel = w and w.level or 0
        end
        if not pickLevel or wornLevel < pickLevel then pick, pickLevel = slot, wornLevel end
    end
    local g = d.gear[pick]
    res.slot = pick
    if g then
        res.worn = g.link or ("item:" .. g.id)
        local w = Info(res.worn)
        res.wornName, res.wornQuality, res.wornLevel = w and w.name, w and w.quality, w and w.level
        if res.level and res.wornLevel then res.gap = res.level - res.wornLevel end
        if not res.same then res.gains, res.loses, res.parts = Difference(link, res.worn) end
    else
        res.empty = true
        res.gains, res.loses, res.parts = Difference(link, nil)
    end
    return res
end
DadMode_Compare = function(link, name) return Compare(link, questData[name]) end

-- His class and level straight from the game, for when his own DadMode is too old to send them
local function Fill(m, d)
    if not d then return end
    d.st = d.st or {}
    if not d.st.cl and type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, m.unit)
        if ok and Usable(token, "string") then d.st.cl = token end
    end
    if not d.st.lv and type(UnitLevel) == "function" then
        local ok, lv = pcall(UnitLevel, m.unit)
        if ok and Usable(lv, "number") and lv > 0 then d.st.lv = lv end
    end
end

local function Coloured(name, quality, link)
    return "|cff" .. (QUALITY[quality or 1] or "ffffff") .. "[" .. (name or "item") .. "]|r"
end

-- The lines added to an item tooltip
local function TooltipLines(link)
    local lines = {}
    if not ns.db.helper or ns.db.compare == false then return lines end
    for _, m in ipairs(Party()) do
        local d = questData[m.name]
        Fill(m, d)
        local res = d and Compare(link, d)
        if res then
            if res.cannot then
                lines[#lines + 1] = GREY .. m.name .. " " .. res.cannot .. "|r"
            elseif res.same then
                lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r wears this"
            else
                if res.empty then
                    lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r has " .. BAD .. "nothing|r in that slot (" .. SLOTS[res.slot] .. ")"
                else
                    lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r wears " .. Coloured(res.wornName, res.wornQuality)
                        .. (res.wornLevel and (GREY .. "  item level " .. res.wornLevel .. "|r") or "")
                end
                if res.level and res.gap then
                    lines[#lines + 1] = "  This one: item level " .. res.level .. GREY .. "  ("
                        .. ((res.gap > 0 and "+" or "") .. ("%g"):format(res.gap)) .. ")|r"
                end
                if res.gains and #res.gains > 0 then lines[#lines + 1] = "  " .. GREY .. "gains|r  " .. GOOD .. table.concat(res.gains, ", ") .. "|r" end
                if res.loses and #res.loses > 0 then lines[#lines + 1] = "  " .. GREY .. "loses|r  " .. BAD .. table.concat(res.loses, ", ") .. "|r" end
                if res.lighter then lines[#lines + 1] = "  " .. GREY .. "This is " .. res.lighter .. ". He can wear " .. res.most .. ".|r" end
                if res.needs then lines[#lines + 1] = "  " .. GREY .. "Needs level " .. res.needs .. ", he is " .. tostring(d.st and d.st.lv) .. "|r" end
            end
        end
    end
    return lines
end
DadMode_TooltipLines = TooltipLines

local function OnTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local link
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, l = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok and Usable(l, "string") then link = l end
    end
    if not link and type(tooltip.GetItem) == "function" then
        local ok, _, l = pcall(tooltip.GetItem, tooltip)
        if ok and Usable(l, "string") then link = l end
    end
    if not link and type(data) == "table" and Usable(data.id, "number") then link = "item:" .. data.id end
    if not link then return end
    local lines = TooltipLines(link)
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    for _, line in ipairs(lines) do tooltip:AddLine(line, 1, 1, 1) end
    tooltip:Show()
end

function DadMode_HookTooltips()
    pcall(function()
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data) pcall(OnTooltip, tooltip, data) end)
        elseif GameTooltip and GameTooltip.HookScript then
            GameTooltip:HookScript("OnTooltipSetItem", function(tooltip) pcall(OnTooltip, tooltip) end)
            if ItemRefTooltip and ItemRefTooltip.HookScript then
                ItemRefTooltip:HookScript("OnTooltipSetItem", function(tooltip) pcall(OnTooltip, tooltip) end)
            end
        end
    end)
end

-- What the button on a bag row shows, by what happened after the guide clicked it
local WEAR_STATE = {
    asked = { "Asked", "wait" }, seen = { "He sees it", "wait" }, ok = { "He put it on", "done" },
    gone = { "Not in bags", "bad" }, no = { "Didn't work", "bad" }, fail = { "Not sent", "bad" },
}

local function Link(item, name, quality)
    return "|cff" .. (QUALITY[quality or 1] or "ffffff") .. "|H" .. item .. "|h" .. (name or "loading...") .. "|h|r"
end

-- The stats a guide says count for one person: stat key -> its name. Kept between sessions.
-- The addon does not know how he plays. The guide does, and says so here.
local function Focus(name)
    ns.db.focus = ns.db.focus or {}
    local key = tostring(name):lower()
    ns.db.focus[key] = ns.db.focus[key] or {}
    return ns.db.focus[key]
end

function DadMode_ToggleFocus(name, key, label)
    local focus = Focus(name)
    if focus[key] then
        focus[key] = nil
    else
        focus[key] = label
        ns.db.gearSort = "stats"        -- picking a stat is asking for the list in that order
    end
    DadMode_RenderQuests()
end

function DadMode_SetGearSort(mode)
    ns.db.gearSort = mode
    DadMode_RenderQuests()
end

-- How much one item moves the stats that count for him: gains minus losses
local function Score(res, focus)
    local sum = 0
    for _, part in ipairs(res.parts or {}) do
        if focus[part.key] then sum = sum + part.diff end
    end
    return sum
end

-- One row of the "In his bags" list: the facts about one item, and a button when he can wear it
local function BagRow(name, d, item, res, focus)
    local row = { row = true, slot = SLOTS[res.slot] or "", chips = {} }
    row.title = Link(item, res.name, res.quality) .. (res.level and (GREY .. "  " .. res.level .. "|r") or "")
    local sub = {}
    if res.cannot then
        sub[1] = GREY .. name .. " " .. res.cannot .. "|r"
    elseif res.same then
        sub[1] = GREY .. "the same as what he wears|r"
    else
        if res.empty then
            sub[1] = GREY .. "his " .. SLOTS[res.slot]:lower() .. " slot is empty|r"
        else
            sub[1] = GREY .. "instead of|r " .. Link(res.worn, res.wornName, res.wornQuality)
                .. (res.wornLevel and (GREY .. "  " .. res.wornLevel .. "|r") or "")
        end
        if res.lighter then sub[#sub + 1] = GREY .. "this is " .. res.lighter .. ", he can wear " .. res.most .. "|r" end
        if res.needs then sub[#sub + 1] = GREY .. "needs level " .. res.needs .. "|r" end
        -- with stats picked for him, those are bright and come first; the rest is dimmed
        local picked = next(focus) ~= nil
        local function Add(want)
            for _, part in ipairs(res.parts or {}) do
                local counts = (not picked) or focus[part.key]
                if (counts and true or false) == want then
                    row.chips[#row.chips + 1] = { text = part.text, kind = (part.diff > 0 and "good" or "bad") .. (counts and "" or "dim") }
                end
            end
        end
        Add(true)
        Add(false)
        if not res.needs then
            local state = WEAR_STATE[d.wearTold and d.wearTold[item] or ""]
            row.button = { text = state and state[1] or "Put it on", kind = state and state[2] or "action" }
            if row.button.kind ~= "done" then
                row.button.onClick = function() DadMode_TellWear(name, item) end
            end
        end
    end
    row.sub = table.concat(sub, "\n")
    return row
end

-- The "In his bags" part of the Gear tab: a heading, the stats that count for him, how the list
-- is sorted, then one row for each thing he could wear
function DadMode_BagRows(name, d, lines)
    lines[#lines + 1] = "|cffe8c36aIn his bags|r  " .. GREY .. "what changes if he puts it on|r"
    if not d.bagGear then
        lines[#lines + 1] = GREY .. "Not known. " .. name .. " needs DadMode 1.21 or newer.|r"
        return
    end
    if #d.bagGear == 0 then
        lines[#lines + 1] = GREY .. "Nothing to wear in his bags.|r"
        return
    end
    local focus = Focus(name)
    local picked = next(focus) ~= nil
    local mode = ns.db.gearSort or (picked and "stats" or "slot")
    if mode == "stats" and not picked then mode = "slot" end

    local list, stats = {}, {}
    for key, label in pairs(focus) do stats[key] = label end
    for _, item in ipairs(d.bagGear) do
        local res = Compare(item, d)
        if res then
            -- what he can put on right now comes first; what he can not wear comes last
            local rank = (res.cannot and 3) or (res.same and 2) or (res.needs and 1) or 0
            local entry = { item = item, res = res, rank = rank, index = #list + 1, score = 0, gap = -999 }
            if rank <= 1 then
                for _, part in ipairs(res.parts or {}) do stats[part.key] = part.label end
                entry.score = Score(res, focus)
                entry.gap = res.gap or (res.empty and (res.level or 0)) or -999
            end
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if mode == "stats" and a.score ~= b.score then return a.score > b.score end
        if mode == "level" and a.gap ~= b.gap then return a.gap > b.gap end
        if (a.res.slot or 0) ~= (b.res.slot or 0) then return (a.res.slot or 0) < (b.res.slot or 0) end
        if (a.res.level or 0) ~= (b.res.level or 0) then return (a.res.level or 0) > (b.res.level or 0) end
        return a.index < b.index
    end)

    -- the stats to pick from: every stat that shows up in the list
    local names = {}
    for key, label in pairs(stats) do names[#names + 1] = { key = key, label = label } end
    table.sort(names, function(a, b) return a.label < b.label end)
    if #names > 0 then
        local items = {}
        for _, stat in ipairs(names) do
            items[#items + 1] = { text = stat.label, on = focus[stat.key] and true or false,
                onClick = function() DadMode_ToggleFocus(name, stat.key, stat.label) end }
        end
        lines[#lines + 1] = { bar = true, label = "What counts for " .. name .. "? Click his stats.", items = items }
    end
    if #list > 1 then
        local items = {}
        for _, def in ipairs({ { "slot", "By slot" }, { "level", "Item level" }, { "stats", "His stats" } }) do
            if def[1] ~= "stats" or picked then
                items[#items + 1] = { text = def[2], on = (mode == def[1]), onClick = function() DadMode_SetGearSort(def[1]) end }
            end
        end
        lines[#lines + 1] = { bar = true, label = "Sort", items = items }
    end
    for _, entry in ipairs(list) do
        lines[#lines + 1] = BagRow(name, d, entry.item, entry.res, focus)
    end
end

-- "Put this on": a guide points at an item in his bags
local wearBtn, wearItem, wearFrom, wearUntil = nil, nil, nil, 0      -- wearFrom = the guide who asked

function DadMode_TellWear(name, item)
    local d = questData[name]
    if not d then return end
    local ok, why = DadMode_TellPerson(name, "WEAR:" .. item, true)
    d.wearTold = d.wearTold or {}
    d.wearTold[item] = ok and "asked" or "fail"
    if not ok then Print("|cffeb7a7aCould not tell him:|r " .. tostring(why)) end
    DadMode_RenderQuests()
end

local function WornNow(id)
    for slot = 1, 18 do
        if Get(GetInventoryItemID, "player", slot) == id then return true end
    end
    return false
end

local function InBags(id)
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return false end
    for bag = 0, 4 do
        local slots = Get(C.GetContainerNumSlots, bag)
        if type(slots) == "number" then
            for slot = 1, slots do
                local info = Get(C.GetContainerItemInfo, bag, slot)
                if type(info) == "table" and info.itemID == id then return true, info.hyperlink end
            end
        end
    end
    return false
end

local function CreateWearButton()
    wearBtn = BigButton(UIParent, 420, 54, function()
        if not wearItem then return end
        if InFight() then
            ShowAlert("|cffe8c36aNot during a fight.|r\nClick the button again after the fight.", 5)
            return
        end
        local id = tonumber(wearItem:match("item:(%d+)"))
        local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
        if type(equip) == "function" then pcall(equip, wearBtn.link or wearItem) end
        -- a moment later: did it work?
        local function Check()
            if id and WornNow(id) then
                wearBtn:Hide()
                wearItem = nil
                ShowAlert("|cff6fcf97You put it on.|r", 4)
                DadMode_Reply(wearFrom, "WEAROK:" .. id)
            else
                ShowAlert("|cffe8c36aThat did not work by itself.|r\nOpen your bags and right-click " .. (wearBtn.name or "the item") .. ".", 10)
                DadMode_Reply(wearFrom, "WEARNO:" .. (id or 0))
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(1, Check) else Check() end
    end)
    DadModeWear = wearBtn
    wearBtn:SetFrameStrata("HIGH")
    wearBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    wearBtn.bg:SetColorTexture(0.55, 0.42, 0.10, 0.97)
    wearBtn.label:SetTextColor(1, 1, 1)
    wearBtn:Hide()
end

-- his side: a guide says "put this on"
local function ReceiveWear(m, item)
    if ns.db.helper then return end
    local id = tonumber(item:match("item:(%d+)"))
    if not id then return end
    if WornNow(id) then
        DadMode_Reply(m, "WEAROK:" .. id)
        return
    end
    local has, link = InBags(id)
    if not has then
        DadMode_Reply(m, "WEARGONE:" .. id)
        return
    end
    if not wearBtn then CreateWearButton() end
    local name
    if C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(C_Item.GetItemInfo, id)
        if ok and Usable(n, "string") then name = n end
    end
    wearItem, wearFrom, wearUntil = item, m, GetTime() + 120
    wearBtn.name = name
    wearBtn.link = Usable(link, "string") and link or nil
    wearBtn.label:SetText("CLICK TO PUT ON: " .. (name or "the new item"))
    wearBtn:Show()
    Beep("call")
    ShowAlert("|cffe8c36a" .. m.name .. "|r says: put on |cff6fcf97" .. (name or "the new item") .. "|r\nClick the gold button.", 10)
    DadMode_Reply(m, "WEARSEEN:" .. id)
end

function DadMode_WearTick()
    if wearBtn and wearItem and GetTime() > wearUntil then
        wearBtn:Hide()
        wearItem = nil
    end
end

-- Returns true when the message belonged to this feature
function DadMode_WearMessage(text, sender)
    if text:sub(1, 4) ~= "WEAR" then return false end
    local m = (not IsMe(sender)) and Member(sender) or nil
    if not m then return true end
    if text:sub(1, 5) == "WEAR:" then
        ReceiveWear(m, text:sub(6))
        return true
    end
    local kind, id = text:match("^(WEAR%u+):(%d+)$")
    local d = questData[m.name]
    if not kind or not d then return true end
    d.wearTold = d.wearTold or {}
    local note = (kind == "WEAROK" and "ok") or (kind == "WEARSEEN" and "seen") or (kind == "WEARGONE" and "gone") or "no"
    for item in pairs(d.wearTold) do
        if item:match("item:(%d+)") == id then d.wearTold[item] = note end
    end
    -- a link he was not told about through this window still gets a chat line
    if kind == "WEAROK" then Print("|cff6fcf97" .. m.name .. " put it on.|r") end
    if kind == "WEARNO" then Print("|cffe8c36a" .. m.name .. " clicked, but the item did not go on. He has to right-click it in his bags.|r") end
    if kind == "WEARGONE" then Print("|cffeb7a7a" .. m.name .. " does not have that item in his bags any more.|r") end
    DadMode_RenderQuests()
    return true
end

-- A drop he could wear: say so once, with what would change. No verdict.
local told = {}
local function Dropped(link)
    if not ns.db.helper or ns.db.compare == false or not Usable(link, "string") then return end
    local item = link:match("item:[%-%d:]+")
    if not item then return end
    local now = GetTime()
    if told[item] and now - told[item] < 120 then return end
    for _, m in ipairs(Party()) do
        local d = questData[m.name]
        Fill(m, d)
        local res = d and Compare(link, d)
        -- only what he can put on: his own armor type, not what he already wears, and not grey or white
        if res and not res.cannot and not res.same and not res.lighter and (res.quality or 0) >= 2 then
            told[item] = now
            local change = {}
            if res.gains and #res.gains > 0 then change[#change + 1] = GOOD .. table.concat(res.gains, ", ") .. "|r" end
            if res.loses and #res.loses > 0 then change[#change + 1] = BAD .. table.concat(res.loses, ", ") .. "|r" end
            Print("|cffe8c36a" .. m.name .. " can wear|r " .. link
                .. (res.level and (" item level " .. res.level) or "") .. ". "
                .. (res.empty and ("His " .. SLOTS[res.slot]:lower() .. " slot is empty.")
                    or ("He wears " .. Coloured(res.wornName, res.wornQuality) .. (res.wornLevel and (" item level " .. res.wornLevel) or "") .. "."))
                .. (#change > 0 and (" " .. table.concat(change, ", ") .. ".") or "")
                .. (res.needs and (" Needs level " .. res.needs .. ".") or ""))
        end
    end
end
DadMode_Dropped = Dropped

handlers.START_LOOT_ROLL = function(rollID)
    if type(GetLootRollItemLink) ~= "function" then return end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if ok then pcall(Dropped, link) end
end
handlers.LOOT_OPENED = function()
    if type(GetNumLootItems) ~= "function" or type(GetLootSlotLink) ~= "function" then return end
    local ok, n = pcall(GetNumLootItems)
    if not ok or not Usable(n, "number") then return end
    for i = 1, n do
        local okL, link = pcall(GetLootSlotLink, i)
        if okL then pcall(Dropped, link) end
    end
end
handlers.CHAT_MSG_LOOT = function(text)
    if not Usable(text, "string") then return end
    local link = text:match("|c%x+|Hitem:.-|h%[.-%]|h|r") or text:match("|Hitem:.-|h%[.-%]|h")
    if link then pcall(Dropped, link) end
end
