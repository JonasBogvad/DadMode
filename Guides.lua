-- DadMode: Guides and permissions: the one being guided decides who may guide, and what they may
-- see and do. Everything is allowed for an approved guide unless a switch is turned off.

-- Shared with DadMode.lua through the table the game gives every file of an addon.
-- Things that only exist after login (saved settings, windows) are read as ns.<name>.
local ADDON, ns = ...
local BAD, Beep, BigButton, GOOD, GREY, InFight, IsMe, Key, Member, Party, Print, RefreshPicker, Tell, Tex, WARN, call, questData
    = ns.BAD, ns.Beep, ns.BigButton, ns.GOOD, ns.GREY, ns.InFight, ns.IsMe, ns.Key, ns.Member, ns.Party, ns.Print, ns.RefreshPicker, ns.Tell, ns.Tex, ns.WARN, ns.call, ns.questData

-- what can be switched off, in the order shown on the page
local PERMS = {
    { "status",   "See my level, zone and bag space" },
    { "gold",     "See my gold" },
    { "quests",   "See my quests" },
    { "gear",     "See my gear and what is in my bags" },
    { "call",     "Call me" },
    { "waypoint", "Set waypoints for me" },
    { "wear",     "Tell me to put on gear" },
}
local lock = {}             -- guide side: name -> "ask" or "no" (he has not approved me)
local permOf = {}           -- guide side: name -> what he shares
local told = {}             -- guided side: last "LOCKED"/"DENY" answer per person, to not repeat it
local waiting = {}          -- guided side: people waiting for a Yes or No, in order
local box, guidesPanel, guidesCategory

local function Allowed(what)
    return not (ns.db.perm and ns.db.perm[what] == false)
end

-- "Anna Stormhoof-Some Realm" -> "Anna Stormhoof", "anna stormhoof"
local function Person(sender)
    local shown = tostring(sender):match("^([^%-]+)") or tostring(sender)
    shown = shown:gsub("^%s+", ""):gsub("%s+$", "")
    return shown, shown:lower()
end

local function MyKey()
    local ok, me = pcall(UnitName, "player")
    return ok and Key(me) or nil
end

-- "yes", "no" or "ask" for somebody who wants to guide me
local function Trust(sender)
    local shown, id = Person(sender)
    ns.db.guides = ns.db.guides or {}
    local g = ns.db.guides[id]
    local first = Key(sender)
    if not g and first and ns.db.legacyGuides and ns.db.legacyGuides[first] then
        -- picked before 1.22, when picking was all there was: counts as approved
        g = { name = shown, state = "yes" }
        ns.db.guides[id] = g
        ns.db.legacyGuides[first] = nil
    end
    return g and g.state or "ask", shown, id
end
DadMode_Trust = Trust

-- one-time carry-over for people who used DadMode before guides had to be approved
function DadMode_TrustInit()
    ns.db.guides = ns.db.guides or {}
    ns.db.perm = ns.db.perm or {}
    if DadMode_CreateGuidesPage then pcall(DadMode_CreateGuidesPage) end
    if not ns.db.guidesInit then
        ns.db.guidesInit = true
        ns.db.legacyGuides = {}
        for key, on in pairs(ns.db.marked or {}) do
            if on then ns.db.legacyGuides[key] = true end
        end
    end
end

local function Answer(sender, body)
    local key = Key(sender)
    if not key then return end
    local id = key .. "|" .. body
    if told[id] and GetTime() - told[id] < 15 then return end
    told[id] = GetTime()
    Tell(body .. ":" .. key)
end

local ShowNext

local function Decide(yes)
    local who = table.remove(waiting, 1)
    if who then
        ns.db.guides = ns.db.guides or {}
        ns.db.guides[who.id] = { name = who.shown, state = yes and "yes" or "no" }
        if who.test then
            Print("Test: \"" .. who.shown .. "\" is now " .. (yes and "approved" or "refused")
                .. ". Look at the options, under DadMode, My guides, and remove it there.")
        elseif yes then
            local key = Key(who.shown)
            if key then
                ns.db.marked[key] = true            -- an approved guide is somebody to find as well
                Tell("UNLOCK:" .. key)
            end
            Print("|cff6fcf97" .. who.shown .. " is now your guide.|r You can change that in the options, under DadMode, My guides.")
            if RefreshPicker then pcall(RefreshPicker) end
        elseif not who.test then
            Print(who.shown .. " will not be asked about again. You can change that in the options, under DadMode, My guides.")
        end
    end
    if DadMode_RefreshGuides then DadMode_RefreshGuides() end
    ShowNext()
end
DadMode_DecideGuide = Decide

local function CreateBox()
    box = CreateFrame("Frame", "DadModeApprove", UIParent)
    box:SetSize(420, 150)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    box:SetFrameStrata("DIALOG")
    Tex(box, "BACKGROUND", 0.07, 0.08, 0.11, 0.97):SetAllPoints()
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    box.text:SetPoint("TOP", 0, -16)
    box.text:SetWidth(390)
    box.sub = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.sub:SetPoint("TOP", box.text, "BOTTOM", 0, -8)
    box.sub:SetWidth(390)
    box.sub:SetText("A guide can see how you are doing, call you and set waypoints for you.")
    box.yes = BigButton(box, 180, 34, function() Decide(true) end)
    box.yes:SetPoint("BOTTOMLEFT", 20, 14)
    box.yes.label:SetText("Yes")
    box.yes.bg:SetColorTexture(0.16, 0.42, 0.24, 1)
    box.no = BigButton(box, 180, 34, function() Decide(false) end)
    box.no:SetPoint("BOTTOMRIGHT", -20, 14)
    box.no.label:SetText("No")
    box:Hide()
end

function ShowNext()
    if not box then CreateBox() end
    local who = waiting[1]
    if not who then
        box:Hide()
        return
    end
    box.text:SetText("|cffe8c36a" .. who.shown .. "|r wants to be your guide.")
    box:Show()
end

local function AskApproval(sender)
    local _, shown, id = Trust(sender)
    for _, who in ipairs(waiting) do
        if who.id == id then return end
    end
    waiting[#waiting + 1] = { shown = shown, id = id }
    if #waiting == 1 then
        Beep("far")
        ShowNext()
    end
end

-- Shows the box without anybody else: for looking at it alone (/dadmode testbox)
function DadMode_TestBox()
    for _, who in ipairs(waiting) do
        if who.test then return end
    end
    waiting[#waiting + 1] = { shown = "Test Guide", id = "test guide", test = true }
    if #waiting == 1 then
        Beep("far", true)
        ShowNext()
    end
    Print("Test: this is the box somebody gets the first time a guide calls them.")
end

-- What the one being guided sends back: first what he shares, then only that
function DadMode_FilterReply(msgs)
    local parts = {}
    for _, def in ipairs(PERMS) do parts[#parts + 1] = def[1] .. "=" .. (Allowed(def[1]) and 1 or 0) end
    local out = { "PERM:" .. table.concat(parts, "~") }
    for _, body in ipairs(msgs) do
        local head3, head2 = body:sub(1, 3), body:sub(1, 2)
        local keep = true
        if head3 == "ST:" then
            keep = Allowed("status")
            if keep and not Allowed("gold") then
                body = body:gsub("~g=%-?%d+", ""):gsub("^ST:g=%-?%d+~?", "ST:")
            end
        elseif head3 == "CN:" then
            keep = Allowed("status")
        elseif head3 == "QS:" then
            if not Allowed("quests") then body = "QS:0" end          -- an empty list, so nothing old stays on screen
        elseif head2 == "Q:" then
            keep = Allowed("quests")
        elseif head3 == "GR:" or head3 == "GL:" or head3 == "SS:" or head3 == "BG:" or body:sub(1, 4) == "BGS:" then
            keep = Allowed("gear")
        end
        if keep then out[#out + 1] = body end
    end
    return out
end

-- The chat way of calling ("!dad"): same rule as a call from the addon
function DadMode_GateChat(sender)
    if ns.db.helper then return false end
    if IsMe(sender) or not Member(sender) then return false end
    local state = Trust(sender)
    if state == "ask" then AskApproval(sender) end
    return state ~= "yes" or not Allowed("call")
end

-- Returns true when the message is dealt with here and must go no further
function DadMode_Gate(text, sender)
    local m = (not IsMe(sender)) and Member(sender) or nil

    ---- guide side: answers about what I may do
    local kind, a, key = text:match("^(LOCKED):(%a+):(.+)$")
    if not kind then kind, a, key = text:match("^(DENY):(%a+):(.+)$") end
    if not kind then
        key = text:match("^UNLOCK:(.+)$")
        if key then kind = "UNLOCK" end
    end
    if kind then
        if not m or key ~= MyKey() then return true end
        if kind == "LOCKED" then
            lock[m.name] = (a == "no") and "no" or "ask"
            questData[m.name], permOf[m.name] = nil, nil
            if call.state == "sent" then call.state, call.who, call.at = "locked", m.name, GetTime() end
            DadMode_RenderQuests()
        elseif kind == "UNLOCK" then
            lock[m.name] = nil
            Print("|cff6fcf97" .. m.name .. " approved you as a guide.|r")
            if ns.questWin and ns.questWin:IsShown() then pcall(DadMode_AskQuests) end
        elseif a == "call" then
            if call.state == "sent" then call.state, call.who, call.at = "denied", m.name, GetTime() end
        elseif a == "waypoint" then
            Print("|cffeb7a7a" .. m.name .. " does not take waypoints from guides.|r")
        elseif a == "wear" then
            Print("|cffeb7a7a" .. m.name .. " does not take \"put it on\" from guides.|r")
        end
        return true
    end
    if text:sub(1, 5) == "PERM:" then
        if m then
            local t = {}
            for k, v in text:sub(6):gmatch("(%a+)=(%d)") do t[k] = (v == "1") end
            permOf[m.name] = t
            -- so the window has a place to say "does not share", even when no data follows
            questData[m.name] = questData[m.name] or { list = {}, done = false }
        end
        return true
    end
    -- somebody who has not approved me: whatever of his I overhear is not mine to show
    if ns.db.helper and m and lock[m.name] then
        local h3 = text:sub(1, 3)
        if text == "QE" or h3 == "QS:" or h3 == "ST:" or h3 == "QD:" or h3 == "BG:" or h3 == "GR:" or h3 == "GL:"
            or h3 == "SS:" or h3 == "CN:" or text:sub(1, 2) == "Q:" or text:sub(1, 4) == "BGS:" then
            return true
        end
    end

    ---- guided side: is this person allowed to do this?
    if ns.db.helper then return false end
    local what, qflags
    local h3 = text:sub(1, 3)
    if text:sub(1, 5) == "PING:" or text == "CLEAR" then what = "call"
    elseif h3 == "WP:" or text == "WPC" or h3 == "TS:" then what = "waypoint"
    elseif text:sub(1, 5) == "WEAR:" then what = "wear"
    else
        -- requests for his data. Letters after "QREQ:" : a = asked by the addon itself, not by a
        -- click; p = answer on the party channel, because whispers did not arrive.
        qflags = text:match("^QREQ:(%a+)$")
        if text == "QREQ" or qflags or text == "SREQ" or text == "SREQ:p" or h3 == "QC:" then what = "data"
        else return false end
    end
    if not m then return true end
    local state = Trust(sender)
    if state ~= "yes" then
        Answer(sender, "LOCKED:" .. (state == "no" and "no" or "ask"))
        -- a box only for something the guide did on purpose, not for the addon's own polling
        local auto = text == "SREQ" or text == "SREQ:p" or (qflags and qflags:find("a") ~= nil)
        if state == "ask" and not auto then AskApproval(sender) end
        return true
    end
    if what ~= "data" and not Allowed(what) then
        Answer(sender, "DENY:" .. what)
        return true
    end
    if qflags then
        DadMode_SendQuests(sender, qflags:find("p") ~= nil)
        return true
    end
    return false
end

function DadMode_PermOf(name) return permOf[name] end

-- Lines for the window of a guide who has not been approved
function DadMode_LockLines()
    local lines = {}
    for _, m in ipairs(Party()) do
        local state = lock[m.name]
        if state == "ask" then
            lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r has not approved you as a guide yet."
            lines[#lines + 1] = GREY .. "He has a Yes / No box on his screen. Ask him to click Yes.|r"
            lines[#lines + 1] = " "
        elseif state == "no" then
            lines[#lines + 1] = "|cffe8c36a" .. m.name .. "|r said no to you as a guide."
            lines[#lines + 1] = GREY .. "He can change that in his options, under DadMode, My guides.|r"
            lines[#lines + 1] = " "
        end
    end
    return lines
end

---- the "My guides" page under DadMode in the game options
local function RefreshGuides()
    if not guidesPanel then return end
    local p = guidesPanel
    local list = {}
    for id, g in pairs(ns.db.guides or {}) do list[#list + 1] = { id = id, name = g.name or id, state = g.state } end
    table.sort(list, function(a, b)
        if a.state ~= b.state then return a.state == "yes" end
        return a.name < b.name
    end)
    for i, row in ipairs(p.people) do
        local g = list[i]
        if g then
            row.id = g.id
            row.text:SetText(g.name .. "   " .. (g.state == "yes" and (GOOD .. "approved|r") or (BAD .. "refused|r")))
            row.button.label:SetText(g.state == "yes" and "Remove" or "Forget")
            row.text:Show()
            row.button:Show()
        else
            row.id = nil
            row.text:Hide()
            row.button:Hide()
        end
    end
    p.none:SetText(#list == 0 and (GREY .. "Nobody yet. When a guide calls you for the first time, you are asked.|r")
        or (#list > #p.people and (GREY .. "and " .. (#list - #p.people) .. " more|r") or ""))
    for _, row in ipairs(p.perms) do
        row.button.label:SetText(Allowed(row.key) and (GOOD .. "Yes|r") or (BAD .. "No|r"))
    end
    p.role:SetText(ns.db.helper and (WARN .. "This computer is set up as a guide. These settings matter for the one being guided.|r") or "")
end
DadMode_RefreshGuides = RefreshGuides

local function CreateGuidesPage()
    if guidesPanel then return end
    local p = CreateFrame("Frame", "DadModeGuides", UIParent)
    p.name = "My guides"
    p.parent = "DadMode"
    p:Hide()
    guidesPanel = p
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DadMode: my guides")
    p.role = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.role:SetPoint("TOPLEFT", 16, -40)

    local head = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 16, -62)
    head:SetText("Who may guide me")
    p.people = {}
    local y = -84
    for i = 1, 8 do
        local row = {}
        row.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("TOPLEFT", 16, y - 4)
        row.button = BigButton(p, 110, 22, function()
            if row.id and ns.db.guides then ns.db.guides[row.id] = nil end      -- asked again next time
            RefreshGuides()
        end)
        row.button:SetPoint("TOPLEFT", 340, y)
        ns.FontSize(row.button.label, 12)
        p.people[i] = row
        y = y - 26
    end
    p.none = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.none:SetPoint("TOPLEFT", 16, -88)

    y = y - 14
    local head2 = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head2:SetPoint("TOPLEFT", 16, y)
    head2:SetText("What my guides may do")
    y = y - 24
    p.perms = {}
    for _, def in ipairs(PERMS) do
        local row = { key = def[1] }
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 16, y - 4)
        fs:SetText(def[2])
        row.button = BigButton(p, 110, 22, function()
            ns.db.perm = ns.db.perm or {}
            ns.db.perm[row.key] = not Allowed(row.key)
            RefreshGuides()
        end)
        row.button:SetPoint("TOPLEFT", 340, y)
        ns.FontSize(row.button.label, 12)
        p.perms[#p.perms + 1] = row
        y = y - 26
    end
    p:SetScript("OnShow", RefreshGuides)

    pcall(function()
        if Settings and Settings.RegisterCanvasLayoutSubcategory and ns.optionsCategory and type(ns.optionsCategory.GetID) == "function" then
            guidesCategory = Settings.RegisterCanvasLayoutSubcategory(ns.optionsCategory, p, "My guides")
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(p)
            guidesCategory = p
        end
    end)
end

DadMode_CreateGuidesPage = CreateGuidesPage

-- Opens the page. In chat as well when asked to (/dadmode guides), for when the page can not open.
function DadMode_OpenGuides(chat)
    if not guidesPanel then CreateGuidesPage() end
    local opened = false
    if guidesCategory and not InFight() then
        opened = pcall(function()
            if Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(type(guidesCategory.GetID) == "function" and guidesCategory:GetID() or guidesCategory)
            else
                InterfaceOptionsFrame_OpenToCategory(guidesCategory)
            end
        end)
    end
    if chat or not opened then
        Print("Guides:")
        local any = false
        for _, g in pairs(ns.db.guides or {}) do
            any = true
            Print("  " .. tostring(g.name) .. ": " .. (g.state == "yes" and "approved" or "refused"))
        end
        if not any then Print("  nobody yet") end
        for _, def in ipairs(PERMS) do
            Print("  " .. def[2] .. ": " .. (Allowed(def[1]) and "yes" or "no"))
        end
    end
end
