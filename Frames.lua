-- DadMode: the arrow bar, the big message frame, and the timer that drives everything

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

function DadMode_CreateBar()
    ns.bar = CreateFrame("Frame", "DadModeBar", UIParent)
    ns.bar:SetSize(160, 150)
    ns.bar:SetFrameStrata("MEDIUM")
    ns.bar:SetMovable(true)
    ns.bar:SetClampedToScreen(true)
    ns.bar:RegisterForDrag("LeftButton")
    if ns.db.pos then
        ns.bar:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3], ns.db.pos[4])
    else
        ns.bar:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    ns.bar:SetScript("OnDragStart", ns.bar.StartMoving)
    ns.bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.pos = { point, rel, x, y }
    end)
    ns.bar.hint = ns.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.bar.hint:SetPoint("BOTTOM", ns.bar, "TOP", 0, 4)
    ns.bar.hint:SetText("Drag the arrows and the green button, then press Lock arrows")
    ns.bar.hint:Hide()
    ns.bar:Hide()

    ns.alertFrame = CreateFrame("Frame", nil, UIParent)
    ns.alertFrame:SetSize(900, 120)
    ns.alertFrame:SetPoint("CENTER", 0, 220)
    ns.alertFrame:SetFrameStrata("HIGH")
    ns.alertFrame.text = ns.alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ns.alertFrame.text:SetPoint("TOP", 0, -6)
    ns.alertFrame.text:SetWidth(900)
    ns.alertFrame.hint = ns.alertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.alertFrame.hint:SetPoint("BOTTOM", 0, 6)
    ns.alertFrame.hint:SetText("|cff9aa0a6click this text to clear it|r")
    ns.alertFrame:EnableMouse(true)
    ns.alertFrame:SetScript("OnMouseDown", function() ns.Dismiss() end)
    pcall(function()
        local font = ns.alertFrame.text:GetFont()
        if font then ns.alertFrame.text:SetFont(font, 34, "THICKOUTLINE") end
    end)
    ns.alertFrame:Hide()

    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.05 then return end
        elapsed = 0
        if ns.alertFrame:IsShown() and GetTime() > (ns.alertFrame.hideAt or 0) then ns.alertFrame:Hide() end
        pcall(ns.UpdateFollow)
        pcall(ns.UpdateHelperStatus)
        pcall(ns.PumpOutbox)
        if DadMode_ExtrasTick then pcall(DadMode_ExtrasTick) end
        if DadMode_WearTick then pcall(DadMode_WearTick) end
        if DadMode_PrivateTick then pcall(DadMode_PrivateTick) end
        if ns.AutoRefreshDue() then pcall(DadMode_AskQuests) end
        local ok, err = pcall(ns.UpdateArrows)
        if not ok and not ns.bar.errorShown then
            ns.bar.errorShown = true
            ns.Print("Arrow error, please report this to the addon author: " .. tostring(err))
        end
    end)
end
