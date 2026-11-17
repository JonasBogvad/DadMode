-- DadMode: the bar with buttons for a guide, and the role question

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Helper bar: buttons for the people who look after dad
---------------------------------------------------------------------------

local ICONS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local BEAM = { 5, 6, 3, 2, 7, 1, 4, 8 }      -- the ground beam with the same colour as each icon

local function InFight()
    return InCombatLockdown and InCombatLockdown()
end

local function ApplyIcon()
    if not ns.helper then return end
    if InFight() then
        ns.Print("Not during a fight. Try again after.")
        return
    end
    local n = ns.db.helperIcon or 1
    -- left click: the icon over my own head. Right click picks the next icon (see PostClick).
    ns.helper.star:SetAttribute("type1", "macro")
    ns.helper.star:SetAttribute("macrotext1", "/target player\n/tm " .. n .. "\n/targetlasttarget")
    -- left click: beam on the ground. Right click: take it away again.
    ns.helper.beam:SetAttribute("type1", "worldmarker")
    ns.helper.beam:SetAttribute("marker1", BEAM[n])
    ns.helper.beam:SetAttribute("action1", "set")
    ns.helper.beam:SetAttribute("type2", "worldmarker")
    ns.helper.beam:SetAttribute("marker2", BEAM[n])
    ns.helper.beam:SetAttribute("action2", "clear")
    ns.helper.star.label:SetText(ICONS[n] .. " on my head")
end

function DadMode_SmallFont(b)
    ns.FontSize(b.label, 12)
end

function DadMode_CreateHelper()
    ns.helper = CreateFrame("Frame", "DadModeHelper", UIParent)
    ns.helper = ns.helper
    ns.helper:SetSize(302, 250)
    ns.helper:SetFrameStrata("MEDIUM")
    ns.helper:SetMovable(true)
    ns.helper:SetClampedToScreen(true)
    ns.helper:EnableMouse(true)
    ns.helper:RegisterForDrag("LeftButton")
    if ns.db.helperPos then
        ns.helper:SetPoint(ns.db.helperPos[1], UIParent, ns.db.helperPos[2], ns.db.helperPos[3], ns.db.helperPos[4])
    else
        ns.helper:SetPoint("RIGHT", UIParent, "RIGHT", -260, 0)
    end
    ns.helper:SetScript("OnDragStart", function(self)
        if not InFight() then
            self.dragging = true
            self:StartMoving()
        end
    end)
    ns.helper:SetScript("OnDragStop", function(self)
        -- if a fight started while dragging, DropDragged() already let go of it
        if not self.dragging or InFight() then return end
        self.dragging = false
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.helperPos = { point, rel, x, y }
    end)
    ns.WindowLook(ns.helper, 0.92)

    local title = ns.helper:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cffffd100DadMode guide|r  |cff9aa0a6" .. ns.VERSION .. "|r")
    ns.helper.status = ns.helper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.helper.status:SetPoint("TOPLEFT", 10, -26)

    -- Who the calls and waypoints go to. With two or more people to guide, a click changes it.
    ns.helper.aimBtn = ns.BigButton(ns.helper, 286, 22, function()
        DadMode_NextTarget()
        if DadMode_UpdateHelperStatus then DadMode_UpdateHelperStatus() end
    end)
    ns.helper.aimBtn:SetPoint("TOPLEFT", 8, -44)
    ns.helper.aimBtn.bg:SetColorTexture(ns.LOOK.quiet[1], ns.LOOK.quiet[2], ns.LOOK.quiet[3], 1)
    ns.FontSize(ns.helper.aimBtn.label, 11)

    -- Warnings about the one being guided, and who runs an older DadMode. Always the same
    -- height, because the bar can not change size during a fight.
    local NOTE_H = 46            -- the strip at the bottom: who I guide, where he is, what needs attention
    ns.helper.stripOn = false    -- only there when there is somebody to show
    ns.helper.note = ns.helper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.helper.note:SetPoint("BOTTOMLEFT", 10, 6)
    ns.helper.note:SetHeight(NOTE_H - 6)
    ns.helper.note:SetJustifyH("LEFT")
    ns.helper.note:SetJustifyV("TOP")
    pcall(function() ns.helper.note:SetWordWrap(true) end)

    -- Eight buttons, in two columns or one (setting "Guide bar layout")
    ns.helper.buttons = {}
    local ROW = 28
    local fullHeight = 250
    local function Place(b)
        DadMode_SmallFont(b)
        ns.helper.buttons[#ns.helper.buttons + 1] = b
        return b
    end
    local function Plain(label, onClick)
        local b = Place(ns.BigButton(ns.helper, 140, 24, onClick))
        b.label:SetText(label)
        return b
    end
    local function Secure(label)
        local b = CreateFrame("Button", nil, ns.helper, "SecureActionButtonTemplate")
        b.bg = ns.Tex(b, "BACKGROUND", ns.LOOK.button[1], ns.LOOK.button[2], ns.LOOK.button[3], 1)
        b.bg:SetAllPoints()
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        b.label:SetPoint("CENTER")
        if label then b.label:SetText(label) end
        b:RegisterForClicks("AnyUp", "AnyDown")
        return Place(b)
    end
    -- A short explanation when the mouse rests on a button
    local function Tip(b, head, ...)
        local lines = { ... }
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(head)
            for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    -- Call dad. While a call is running the same button cancels it.
    ns.helper.callBtn = Plain("Call", function()
        if ns.call.state == "sent" or ns.call.state == "ack" then ns.SendClear() else DadMode_SendPing("") end
    end)
    Tip(ns.helper.callBtn, "Call", "Shows a big call on the screen of the one you guide.", "While it runs, this button cancels it.")
    Plain("Come to me", function() DadMode_SendPing("says: come to me") end)
    Plain("Stop, wait here", function() DadMode_SendPing("says: stop and wait") end)
    Plain("Follow me", function() DadMode_SendPing("says: follow me. Click the green button") end)
    -- Waypoint. Once he has one, the same button removes it. Right click always removes.
    ns.helper.wpBtn = Plain("Waypoint", function() end)
    ns.helper.wpBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" or ns.wpOut then DadMode_SendWaypointClear() else DadMode_SendWaypoint() end
    end)
    pcall(function() ns.helper.wpBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end)
    Tip(ns.helper.wpBtn, "Waypoint", "Sends your map pin, or the spot where you stand.",
        "Click again to remove it.", "Right click: always remove.")
    ns.helper.star = Secure()
    Tip(ns.helper.star, "Icon over my head", "Left click: put it on.", "Right click: pick the next icon.")
    local lastCycle = 0
    ns.helper.star:SetScript("PostClick", function(self, button)
        if button ~= "RightButton" then return end
        local now = GetTime()
        if now - lastCycle < 0.3 then return end      -- press and release both arrive here
        lastCycle = now
        if InFight() then
            ns.Print("Not during a fight. Try again after.")
            return
        end
        ns.db.helperIcon = (ns.db.helperIcon or 1) % 8 + 1
        ApplyIcon()
        ns.Print("Your icon is now " .. ICONS[ns.db.helperIcon] .. ".")
    end)
    ns.helper.beam = Secure("Beam on the ground")
    Tip(ns.helper.beam, "Beam on the ground", "Left click, then click the ground.", "Right click: remove the beam.")
    ns.helper.howBtn = Plain("How are they doing", function() ns.OpenQuests() end)

    -- Puts the buttons in one or two columns. Not possible during a fight.
    local function Layout()
        if InFight() then return false end
        local cols = (ns.db.helperCols == 1) and 1 or 2
        local width = (cols == 1) and 160 or 140
        for i, b in ipairs(ns.helper.buttons) do
            local n = i - 1
            b:ClearAllPoints()
            b:SetSize(width, 24)
            b:SetPoint("TOPLEFT", ns.helper, "TOPLEFT", 8 + (n % cols) * (width + 6), -72 - math.floor(n / cols) * ROW)
        end
        ns.helper.aimBtn:SetWidth(cols * width + (cols - 1) * 6)
        fullHeight = 72 + math.ceil(#ns.helper.buttons / cols) * ROW + 6 + (ns.helper.stripOn and NOTE_H or 2)
        ns.helper:SetWidth(8 + cols * width + (cols - 1) * 6 + 8)
        ns.helper.note:SetWidth(cols * width + (cols - 1) * 6 - 14)
        ns.helper:SetHeight(ns.db.helperFolded and 44 or fullHeight)
        return true
    end
    ns.helper.Layout = Layout
    Layout()

    -- The small button in the corner folds the bar up to just its title and the call status
    local function ApplyFold()
        for _, b in ipairs(ns.helper.buttons) do
            if ns.db.helperFolded then b:Hide() else b:Show() end
        end
        if ns.db.helperFolded or not ns.helper.stripOn then ns.helper.note:Hide() else ns.helper.note:Show() end
        if ns.db.helperFolded then ns.helper.aimBtn:Hide() else ns.helper.aimBtn:Show() end
        ns.helper:SetHeight(ns.db.helperFolded and 44 or fullHeight)
        ns.helper.fold.label:SetText(ns.db.helperFolded and "+" or "-")
    end
    ns.helper.fold = ns.BigButton(ns.helper, 22, 18, function()
        if InFight() then
            ns.Print("Not during a fight. Try again after.")
            return
        end
        ns.db.helperFolded = not ns.db.helperFolded
        ApplyFold()
    end)
    ns.helper.fold:SetPoint("TOPRIGHT", -6, -6)
    ns.AddScaleGrip(ns.helper, "helper", true, function()
        local point, _, rel, x, y = ns.helper:GetPoint()
        if point then ns.db.helperPos = { point, rel, x, y } end
    end, function(want)
        -- break point: dragged narrower than this, the buttons go into one column
        local cols = (want < ns.HELPER_BREAK) and 1 or 2
        if cols ~= ((ns.db.helperCols == 1) and 1 or 2) then
            ns.db.helperCols = cols
            ns.helper.Layout()
        end
        return (cols == 1) and 176 or 302
    end)

    ns.helper.ApplyFold = ApplyFold
    ApplyIcon()
    ApplyFold()
    if ns.db.helper and not ns.db.helperHidden then ns.helper:Show() else ns.helper:Hide() end
end

-- The line at the top of the helper bar: did my call arrive, and how far away is he
function DadMode_UpdateHelperStatus() if ns.UpdateHelperStatus then ns.UpdateHelperStatus() end end
function ns.UpdateHelperStatus()
    if not (ns.helper and ns.helper:IsShown()) then return end
    -- the buttons carry the name of the one they are for
    local who, several = DadMode_TargetName()
    ns.helper.callBtn.label:SetText((ns.call.state == "sent" or ns.call.state == "ack") and "|cffff4d4dCancel my call|r"
        or (who and ("Call " .. who)) or (several and "Call everyone") or "Call")
    ns.helper.wpBtn.label:SetText(ns.wpOut and "|cffff4d4dRemove the waypoint|r"
        or (who and ("Waypoint for " .. who)) or (several and "Waypoint for all") or "Waypoint")
    ns.helper.howBtn.label:SetText(who and ("How is " .. who .. " doing") or "How are they doing")
    ns.helper.aimBtn.label:SetText(DadMode_TargetLine())
    local now, text = GetTime(), ""
    if ns.call.state == "sent" then
        text = "|cffffd100Calling...|r"
    elseif ns.call.state == "none" then
        text = "|cffff4d4dNo answer|r"
        if now - ns.call.at > 12 then ns.call.state = nil end
    elseif ns.call.state == "muted" then
        text = "|cffff4d4d" .. tostring(ns.call.who) .. ": calls are off|r"
        if now - ns.call.at > 12 then ns.call.state = nil end
    elseif ns.call.state == "locked" then
        text = "|cffff4d4d" .. tostring(ns.call.who) .. " has not approved you|r"
        if now - ns.call.at > 12 then ns.call.state = nil end
    elseif ns.call.state == "denied" then
        text = "|cffff4d4d" .. tostring(ns.call.who) .. " takes no calls from guides|r"
        if now - ns.call.at > 12 then ns.call.state = nil end
    elseif ns.call.state == "here" then
        text = "|cff1aff1a" .. tostring(ns.call.who) .. " is with you|r"
        if now - ns.call.at > 10 then ns.call.state = nil end
    elseif ns.call.state == "ack" then
        text = "|cff1aff1a" .. tostring(ns.call.who) .. " got it|r"
        for _, m in ipairs(ns.Party()) do
            if m.name == ns.call.who then
                local dist = ns.Locate(m.unit)
                if dist then text = text .. "  " .. math.floor(dist + 0.5) .. " yd" end
            end
        end
        if now - ns.call.at > ns.PING_ARROW then ns.call.state = nil end
    end
    -- no call going on: the top line carries what matters most, the strip at the bottom shows it all
    local notes, top = {}, nil
    if DadMode_Notes then notes, top = DadMode_Notes() end
    if text == "" and top then text = top end
    ns.helper.status:SetText(text)
    ns.helper.note:SetText(table.concat(notes, "\n"))
    -- the strip comes and goes with having somebody to guide. The bar can not change size in a
    -- fight, so then it waits until the fight is over.
    local want = #notes > 0
    if want ~= ns.helper.stripOn and not InFight() then
        ns.helper.stripOn = want
        ns.helper.Layout()
        ns.helper.ApplyFold()
    end
end


-- guide = true for someone who looks after dad, false for the one who gets lost
local function SetRole(guide)
    if not ns.helper then return false end
    if InFight() then
        ns.Print("Not during a fight. Try again after.")
        return false
    end
    ns.db.helper = guide and true or false
    ns.db.roleChosen = true
    if ns.db.helper then
        ns.db.alerts, ns.db.farWarning, ns.db.follow = false, false, false
        ns.db.helperHidden = nil
        ns.helper:Show()
        ns.Print("You are a guide. Your buttons are on. Calls and far warnings are off for you, because you are not the one who gets lost.")
    else
        ns.db.alerts, ns.db.farWarning, ns.db.follow = true, true, true
        ns.helper:Hide()
        ns.Print("You are the one being guided. Calls, far warning and the follow button are on.")
    end
    if ns.RefreshPicker then ns.RefreshPicker() end
    return true
end

-- Puts calls back on for someone in the dad role
local function RepairCalls()
    ns.db.alerts, ns.db.farWarning, ns.db.follow = true, true, true
    ns.Print("Calls are on again.")
    if ns.RefreshPicker then ns.RefreshPicker() end
end
DadMode_RepairCalls = RepairCalls
DadMode_SetRole = SetRole

local function ToggleHelper()
    if not ns.db.helper and not ns.db.alerts then return RepairCalls() end
    SetRole(not ns.db.helper)
end

-- Asked once per computer, the first time DadMode starts. /dadmode role opens it again.
function DadMode_CreateRoleWindow()
    ns.roleWin = CreateFrame("Frame", "DadModeRole", UIParent)
    ns.roleWin:SetSize(340, 168)
    ns.roleWin:SetPoint("CENTER", 0, 120)
    ns.roleWin:SetFrameStrata("DIALOG")
    ns.roleWin:EnableMouse(true)
    ns.WindowLook(ns.roleWin)
    local title = ns.roleWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffffd100Who is using DadMode on this computer?|r")

    ns.roleWin.dad = ns.BigButton(ns.roleWin, 300, 36, function()
        if SetRole(false) then ns.roleWin:Hide() end
    end)
    ns.roleWin.dad:SetPoint("TOP", 0, -40)
    ns.roleWin.dad.label:SetText("I need help finding my party")
    ns.roleWin.guide = ns.BigButton(ns.roleWin, 300, 36, function()
        if SetRole(true) then ns.roleWin:Hide() end
    end)
    ns.roleWin.guide:SetPoint("TOP", 0, -82)
    ns.roleWin.guide.label:SetText("I am a guide for someone")
    for _, b in ipairs({ ns.roleWin.dad, ns.roleWin.guide }) do
        ns.FontSize(b.label, 14)
    end
    local note = ns.roleWin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOM", 0, 12)
    note:SetText("|cff9aa0a6Asked once. Change it later with /dadmode role|r")
    ns.roleWin:Hide()
end

DadMode_ToggleHelper = ToggleHelper

-- used by other files of DadMode
ns.InFight = InFight
ns.ToggleHelper = ToggleHelper
