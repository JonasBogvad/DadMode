-- DadMode: buttons, backgrounds and resize corners that every window uses

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Buttons and text
---------------------------------------------------------------------------

-- Sets the size of a piece of text and keeps its font. Does nothing if the game refuses.
function ns.FontSize(text, size)
    pcall(function()
        local font, _, flags = text:GetFont()
        if font then text:SetFont(font, size, flags) end
    end)
end


local function BigButton(parent, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.bg = ns.Tex(b, "BACKGROUND", 0.16, 0.18, 0.22, 1)
    b.bg:SetAllPoints()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", function(self) onClick(self) end)
    return b
end

---------------------------------------------------------------------------
-- Resize corners: drag the bottom right corner of a window, like in Windows
---------------------------------------------------------------------------

local function InFightNow() return InCombatLockdown and InCombatLockdown() end

-- Final size factor of one window: the "Window size" setting times its own corner drag
local function WindowScale(key)
    local own = ns.db.winScale and ns.db.winScale[key] or 1
    return (ns.SCALES[ns.db.scale or 3] or 1) * own
end

function DadMode_GripTexture(grip)
    pcall(function()
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    end)
end

local function MakeGrip(win)
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel((win:GetFrameLevel() or 1) + 10)
    DadMode_GripTexture(grip)
    return grip
end

-- For windows made of fixed buttons: dragging the corner makes the whole window bigger or
-- smaller. The top left corner stays where it is and the dragged corner follows the mouse.
-- secure = the window holds buttons the game protects, so it can not be resized in a fight.
-- widthFor(w): optional. Gets the width the mouse asks for and returns the window's natural
-- width for it, so a window can change its layout at a break point while it is dragged.
local function AddScaleGrip(win, key, secure, onDone, widthFor)
    local grip = MakeGrip(win)
    win.grip = grip
    local function Stop()
        if not grip.sizing then return end
        grip.sizing = nil
        grip:SetScript("OnUpdate", nil)
        if onDone then onDone() end
    end
    grip.Stop = Stop
    grip:SetScript("OnMouseDown", function()
        if secure and InFightNow() then return end
        local old = win:GetScale() or 1
        if old <= 0 then old = 1 end
        local ui = UIParent:GetEffectiveScale() or 1
        local left, top = (win:GetLeft() or 0) * old, (win:GetTop() or 0) * old
        local width = win:GetWidth() or 1
        if width <= 0 then return end
        grip.sizing = true
        grip:SetScript("OnUpdate", function()
            if secure and InFightNow() then Stop() return end
            local cx = GetCursorPosition()
            if not cx then return end
            local want = cx / ui - left
            if widthFor then width = widthFor(want) or width end
            local scale = want / width
            scale = math.min(math.max(scale, ns.GRIP_MIN), ns.GRIP_MAX)
            ns.db.winScale = ns.db.winScale or {}
            ns.db.winScale[key] = scale / (ns.SCALES[ns.db.scale or 3] or 1)
            win:SetScale(scale)
            win:ClearAllPoints()
            win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
        end)
    end)
    grip:SetScript("OnMouseUp", Stop)
    grip:SetScript("OnHide", Stop)
end

-- used by other files of DadMode
ns.AddScaleGrip = AddScaleGrip
ns.BigButton = BigButton
ns.MakeGrip = MakeGrip
ns.WindowScale = WindowScale
