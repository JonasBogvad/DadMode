-- DadMode: the green follow button

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Follow button: one click and the character walks after the person
---------------------------------------------------------------------------

local followWho, followName, followUnit

-- Is the caller close enough for the game's follow to work? Unknown counts as yes.
local function CanFollowNow()
    if not followUnit then return true end
    local dist = ns.Locate(followUnit)
    if dist then return dist <= ns.FOLLOW_RANGE end
    -- no positions (dungeon, or the other one is on another continent): ask if he is in sight
    if type(UnitIsVisible) == "function" then
        local ok, seen = pcall(UnitIsVisible, followUnit)
        if ok and ns.Usable(seen, "boolean") then return seen end
    end
    return true
end
DadMode_CanFollowNow = CanFollowNow

-- The person who is calling right now, otherwise the first picked person in the party
function DadMode_FollowTarget()
    local now, list = GetTime(), ns.Party()
    for _, m in ipairs(list) do
        if ns.pings[m.name] and ns.pings[m.name] > now then return m end
    end
    for _, m in ipairs(list) do
        if ns.db.marked[m.name] then return m end
    end
end

-- While the person the button follows is calling, the button flashes so it can not be missed.
-- Only colour and text change here: the game allows that during a fight too.
function DadMode_PulseFollow()
    if not followName then return end
    local now = GetTime()
    if ns.pings[followName] and ns.pings[followName] > now and CanFollowNow() then
        local bright = math.sin(now * 8) > 0
        if bright then
            ns.followBtn.bg:SetColorTexture(0.95, 0.95, 0.95, 1)
            ns.followBtn.label:SetTextColor(0.05, 0.25, 0.12)
        else
            ns.followBtn.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95)
            ns.followBtn.label:SetTextColor(1, 1, 1)
        end
        ns.followBtn.label:SetText("CLICK TO FOLLOW " .. followName)
        ns.followBtn.pulsing = true
    elseif ns.followBtn.pulsing then
        ns.followBtn.pulsing = false
        ns.followBtn.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95)
        ns.followBtn.label:SetTextColor(1, 1, 1)
        ns.followBtn.label:SetText("FOLLOW " .. followName)
    end
end

function ns.UpdateFollow()
    if not ns.followBtn then return end
    local m = (ns.db.enabled and ns.db.follow) and DadMode_FollowTarget() or nil
    local who = m and (m.unit .. ":" .. m.name) or nil
    if who ~= followWho and not ns.InFight() then     -- the game does not let the target change during a fight
        followWho = who
        followName = m and m.name or nil
        followUnit = m and m.unit or nil
        ns.followBtn.pulsing = false
        if who then
            ns.followBtn:SetAttribute("type", "macro")
            ns.followBtn:SetAttribute("macrotext", "/follow " .. m.unit)
            ns.followBtn.label:SetText("FOLLOW " .. m.name)
            ns.followBtn.label:SetTextColor(1, 1, 1)
            ns.followBtn.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95)
            ns.followBtn:Show()
        else
            ns.followBtn:Hide()
        end
    end
    DadMode_PulseFollow()
end

function DadMode_CreateFollow()
    ns.followBtn = CreateFrame("Button", "DadModeFollow", UIParent, "SecureActionButtonTemplate")
    ns.followBtn:SetSize(240, 46)
    ns.followBtn:SetFrameStrata("MEDIUM")
    ns.followBtn:SetMovable(true)
    ns.followBtn:SetClampedToScreen(true)
    ns.followBtn:RegisterForClicks("AnyUp", "AnyDown")
    ns.followBtn:RegisterForDrag("LeftButton")
    if ns.db.followPos then
        ns.followBtn:SetPoint(ns.db.followPos[1], UIParent, ns.db.followPos[2], ns.db.followPos[3], ns.db.followPos[4])
    else
        ns.followBtn:SetPoint("TOP", UIParent, "TOP", 0, -330)
    end
    ns.followBtn:SetScript("OnDragStart", function(self)
        if ns.moving and not ns.InFight() then
            self.dragging = true
            self:StartMoving()
        end
    end)
    ns.followBtn:SetScript("OnDragStop", function(self)
        if not self.dragging or ns.InFight() then return end
        self.dragging = false
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.followPos = { point, rel, x, y }
    end)
    ns.followBtn.bg = ns.Tex(ns.followBtn, "BACKGROUND", 0.16, 0.40, 0.27, 0.95)
    ns.Edge(ns.followBtn)
    ns.followBtn.bg:SetAllPoints()
    ns.followBtn.label = ns.followBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ns.followBtn.label:SetPoint("CENTER")
    ns.followBtn.label:SetTextColor(1, 1, 1)
    ns.followBtn:SetScript("OnEnter", function(self)
        if not self.pulsing then self.bg:SetColorTexture(0.22, 0.54, 0.36, 1) end
    end)
    ns.followBtn:SetScript("OnLeave", function(self)
        if not self.pulsing then self.bg:SetColorTexture(0.16, 0.40, 0.27, 0.95) end
    end)
    ns.followBtn:Hide()
end
