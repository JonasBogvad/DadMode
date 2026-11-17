-- DadMode: the window where the one being guided picks who to find

local ADDON, ns = ...

local PICK_W, PICK_HALF = 268, 130

function DadMode_CreatePicker()
    ns.picker = CreateFrame("Frame", "DadModePicker", UIParent)
    ns.picker:SetSize(300, 200)
    ns.picker:SetPoint("CENTER", 0, 40)
    ns.picker:SetFrameStrata("DIALOG")
    ns.picker:SetMovable(true)
    ns.picker:EnableMouse(true)
    ns.picker:RegisterForDrag("LeftButton")
    ns.picker:SetScript("OnDragStart", ns.picker.StartMoving)
    ns.picker:SetScript("OnDragStop", ns.picker.StopMovingOrSizing)
    ns.WindowLook(ns.picker)
    ns.picker.showSettings = false

    ns.picker.title = ns.picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.picker.title:SetPoint("TOP", 0, -12)
    ns.picker.sub = ns.picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.picker.sub:SetPoint("TOP", ns.picker.title, "BOTTOM", 0, -4)
    local ver = ns.picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ver:SetPoint("BOTTOMLEFT", 6, 4)
    ver:SetText("|cff9aa0a6" .. ns.VERSION .. "|r")
    ns.AddScaleGrip(ns.picker, "picker", false)

    ns.picker.names = {}
    for i = 1, 4 do
        ns.picker.names[i] = ns.BigButton(ns.picker, PICK_W, 34, function(self)
            if not self.who then return end
            ns.db.marked[self.who] = (not ns.db.marked[self.who]) or nil
            ns.RefreshPicker()
            ns.UpdateArrows()
        end)
    end

    ns.picker.empty = ns.picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.picker.empty:SetWidth(PICK_W)
    ns.picker.empty:SetText("|cff9aa0a6You are not in a party yet.\nJoin a party and open this again.|r")

    ns.picker.marker = ns.BigButton(ns.picker, PICK_W, 26, function()
        ns.db.waypoint = nil
        if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
        ns.RefreshPicker()
    end)
    ns.picker.marker.label:SetText("Remove the red marker")

    ns.picker.role = ns.BigButton(ns.picker, PICK_W, 26, function() DadMode_RepairCalls() end)
    ns.picker.role.label:SetText("CALLS ARE OFF  (click to fix)")
    ns.picker.role.bg:SetColorTexture(0.55, 0.18, 0.18, 1)

    local function SoundButton(kind, label)
        local b
        b = ns.BigButton(ns.picker, PICK_HALF, 26, function()
            ns.db.sounds[kind] = ((ns.db.sounds[kind] or ns.DEFAULT_SOUND[kind]) % #ns.SOUNDS) + 1
            ns.Beep(kind, true)                 -- play it, so he hears what he picked
            ns.RefreshPicker()
        end)
        b.kind, b.title = kind, label
        return b
    end
    ns.picker.callSound = SoundButton("call", "Call")
    ns.picker.farSound = SoundButton("far", "Far")

    ns.picker.move = ns.BigButton(ns.picker, PICK_HALF, 26, function()
        ns.moving = not ns.moving
        ns.bar:EnableMouse(ns.moving)
        ns.RefreshPicker()
        ns.UpdateArrows()
    end)
    ns.picker.far = ns.BigButton(ns.picker, PICK_HALF, 26, function()
        ns.db.farWarning = not ns.db.farWarning
        ns.RefreshPicker()
    end)
    ns.picker.size = ns.BigButton(ns.picker, PICK_W, 26, function()
        ns.db.arrowSize = (ns.db.arrowSize or 2) % #ns.ARROW_SIZES + 1
        ns.RefreshPicker()
        ns.UpdateArrows()
    end)

    ns.picker.more = ns.BigButton(ns.picker, PICK_HALF, 28, function()
        if DadMode_HasOptionsPage() then
            DadMode_OpenSettings()           -- the full page in the game's Options window
        else
            ns.picker.showSettings = not ns.picker.showSettings
            ns.RefreshPicker()
        end
    end)
    ns.picker.close = ns.BigButton(ns.picker, PICK_HALF, 28, function() ns.picker:Hide() end)
    ns.picker.close.label:SetText("Done")

    for _, b in ipairs({ ns.picker.move, ns.picker.far, ns.picker.callSound, ns.picker.farSound, ns.picker.marker, ns.picker.role,
        ns.picker.size, ns.picker.more, ns.picker.close }) do
        ns.FontSize(b.label, 12)
    end

    ns.picker:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "DadModePicker") end
end

-- Fills in the window and stacks whatever is visible from the top down, so it is never taller than needed
function ns.RefreshPicker()
    if not ns.picker then return end
    if ns.db.helper then
        ns.picker.title:SetText("|cffffd100DadMode settings|r")
        ns.picker.sub:SetText("|cff9aa0a6Want arrows yourself? Gold = arrow to them|r")
    else
        ns.picker.title:SetText("|cffffd100Who do you want to find?|r")
        ns.picker.sub:SetText("|cff9aa0a6Gold = you get an arrow to them|r")
    end
    local list = ns.Party()
    local y = -50
    local function Row(b, height)
        b:ClearAllPoints()
        b:SetPoint("TOP", ns.picker, "TOP", 0, y)
        b:Show()
        y = y - height - 4
    end
    local function Pair(left, right)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", ns.picker, "TOPLEFT", 16, y)
        left:Show()
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", ns.picker, "TOPRIGHT", -16, y)
        right:Show()
        y = y - 30
    end

    for i, b in ipairs(ns.picker.names) do
        local m = list[i]
        if m then
            b.who = m.name
            b.label:SetText(m.name)
            if ns.db.marked[m.name] then
                b.bg:SetColorTexture(0.62, 0.48, 0.16, 1)
                b.label:SetTextColor(1, 1, 1)
            else
                b.bg:SetColorTexture(ns.LOOK.quiet[1], ns.LOOK.quiet[2], ns.LOOK.quiet[3], 1)
                b.label:SetTextColor(0.80, 0.75, 0.60)
            end
            Row(b, 34)
        else
            b.who = nil
            b:Hide()
        end
    end
    if #list == 0 then
        ns.picker.empty:ClearAllPoints()
        ns.picker.empty:SetPoint("TOP", ns.picker, "TOP", 0, y - 2)
        ns.picker.empty:Show()
        y = y - 40
    else
        ns.picker.empty:Hide()
    end

    if ns.db.waypoint then Row(ns.picker.marker, 26) else ns.picker.marker:Hide() end

    -- Only shown when something is wrong: he is in the dad role but his calls are switched off
    if not ns.db.helper and not ns.db.alerts then Row(ns.picker.role, 26) else ns.picker.role:Hide() end

    if ns.picker.showSettings then
        for _, b in ipairs({ ns.picker.callSound, ns.picker.farSound }) do
            local choice = ns.SOUNDS[ns.db.sounds[b.kind] or ns.DEFAULT_SOUND[b.kind]] or ns.SOUNDS[1]
            b.label:SetText(b.title .. ": " .. choice.name)
        end
        Pair(ns.picker.callSound, ns.picker.farSound)
        ns.picker.move.label:SetText(ns.moving and "Lock arrows" or "Move arrows")
        ns.picker.far.label:SetText(ns.db.farWarning and "Far warning: on" or "Far warning: off")
        Pair(ns.picker.move, ns.picker.far)
        ns.picker.size.label:SetText("Arrow size: " .. (ns.ARROW_SIZES[ns.db.arrowSize or 2] or ns.ARROW_SIZES[2])[1])
        Row(ns.picker.size, 26)
    else
        for _, b in ipairs({ ns.picker.callSound, ns.picker.farSound, ns.picker.move, ns.picker.far, ns.picker.size }) do b:Hide() end
    end

    y = y - 4
    ns.picker.more.label:SetText(ns.picker.showSettings and "Fewer options" or "Settings")
    Pair(ns.picker.more, ns.picker.close)
    ns.picker:SetHeight(-y + 18)
end

local function OpenPicker(showSettings)
    if not ns.picker then return end
    ns.picker.showSettings = showSettings and true or false
    ns.RefreshPicker()
    ns.picker:Show()
end

-- used by other files of DadMode
ns.OpenPicker = OpenPicker
