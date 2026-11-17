-- DadMode: the minimap button

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
-- Left click: the main window for your role. Right click: the helper buttons.

local minimapButton, minimapLib

local function MinimapClick(button)
    if button == "RightButton" then
        DadMode_OpenSettings()       -- settings. It used to switch role, which was too easy to do by accident
    elseif ns.db.helper then
        -- the guide's own window: the bar with the commands. Click again to put it away.
        if not ns.helper then return end
        if InCombatLockdown and InCombatLockdown() then
            ns.Print("The guide bar can not be shown or hidden during a fight.")
        elseif ns.helper:IsShown() then
            ns.helper:Hide()
            ns.db.helperHidden = true
            ns.Print("Guide bar hidden. Left click the minimap button to bring it back.")
        else
            ns.helper:Show()
            ns.db.helperHidden = nil
        end
    else
        ns.OpenPicker()                 -- dad: pick who to find and follow
    end
end

DadMode_MinimapClick = MinimapClick
local function MinimapTooltip(tt)
    tt:AddLine("DadMode " .. ns.VERSION)
    if ns.db.helper then
        tt:AddLine("Left click: show or hide the guide bar", 0.9, 0.9, 0.9)
    else
        tt:AddLine("Left click: pick who to find and follow", 0.9, 0.9, 0.9)
    end
    tt:AddLine("Right click: settings", 0.9, 0.9, 0.9)
    tt:AddLine("Drag: move this button", 0.6, 0.63, 0.65)
end

local function PlaceMinimapButton()
    local angle = math.rad(ns.db.minimap.angle or 215)
    local radius = ((Minimap:GetWidth() or 140) / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function DadMode_CreateMinimapButton()
    ns.db.minimap = ns.db.minimap or {}

    -- If another addon brought the usual minimap button library, use it: then button collectors
    -- such as MinimapButtonButton treat this button like every other addon's.
    local ok = pcall(function()
        local ldb = LibStub("LibDataBroker-1.1")
        local icon = LibStub("LibDBIcon-1.0")
        local obj = ldb:NewDataObject("DadMode", {
            type = "launcher", text = "DadMode", icon = ns.ARROW,
            iconR = 0.91, iconG = 0.76, iconB = 0.42,
            OnClick = function(_, button) MinimapClick(button) end,
            OnTooltipShow = function(tt) MinimapTooltip(tt) end,
        })
        icon:Register("DadMode", obj, ns.db.minimap)
        minimapLib = icon
    end)
    if ok and minimapLib then return end

    -- Otherwise a plain button of our own
    if not Minimap then return end
    local b = CreateFrame("Button", "DadModeMinimapButton", Minimap)
    minimapButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.ARROW)
    icon:SetVertexColor(0.91, 0.76, 0.42)
    icon:SetSize(17, 17)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, button) MinimapClick(button) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        MinimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale() or 1
            if mx and px then
                ns.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
                PlaceMinimapButton()
            end
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceMinimapButton()
    if ns.db.minimap.hide then b:Hide() end
end

function ns.ToggleMinimapButton()
    ns.db.minimap = ns.db.minimap or {}
    ns.db.minimap.hide = not ns.db.minimap.hide
    if minimapLib then
        if ns.db.minimap.hide then minimapLib:Hide("DadMode") else minimapLib:Show("DadMode") end
    elseif minimapButton then
        if ns.db.minimap.hide then minimapButton:Hide() else minimapButton:Show() end
    end
    ns.Print(ns.db.minimap.hide and "Minimap button hidden. /dadmode minimap brings it back." or "Minimap button shown.")
end
DadMode_ToggleMinimapButton = ns.ToggleMinimapButton
