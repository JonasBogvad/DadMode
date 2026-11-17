-- DadMode: the settings page in the game options

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Settings page in the game's own Options window (Options > AddOns > DadMode)
---------------------------------------------------------------------------


-- Makes every DadMode window bigger or smaller. The bars with marker buttons can not be
-- resized during a fight, so those wait until it is over.
local function ApplyScale()
    local base = ns.SCALES[ns.db.scale or 3] or 1
    if ns.picker then ns.picker:SetScale(ns.WindowScale("picker")) end
    for _, f in ipairs({ ns.questWin, ns.roleWin }) do
        if f then f:SetScale(base) end
    end
    if not ns.InFight() then
        if ns.helper then ns.helper:SetScale(ns.WindowScale("helper")) end
        if ns.followBtn then ns.followBtn:SetScale(base) end
    end
end

-- Back to the sizes the addon came with
local function ResetSizes()
    ns.db.winScale, ns.db.questSize, ns.db.scale = nil, nil, 3
    if ns.questWin then ns.questWin:SetSize(460, 540) end
    ApplyScale()
    ns.Print("Window sizes are back to normal." .. (ns.InFight() and " The guide bar follows after the fight." or ""))
end

local function RefreshOptions()
    if not optionsPanel then return end
    for _, row in ipairs(optionsPanel.rows) do row.button.label:SetText(row.text()) end
end

function DadMode_CreateOptions()
    local panel = CreateFrame("Frame", "DadModeOptions", UIParent)
    panel.name = "DadMode"
    panel:Hide()
    optionsPanel = panel
    panel.rows = {}

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DadMode  |cff9aa0a6" .. ns.VERSION .. "|r")

    local y = -56
    local function Row(label, text, onClick)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 16, y - 5)
        fs:SetText(label)
        local b = ns.BigButton(panel, 260, 26, function()
            onClick()
            RefreshOptions()
            if ns.RefreshPicker then ns.RefreshPicker() end
        end)
        b:SetPoint("TOPLEFT", 280, y)
        ns.FontSize(b.label, 12)
        panel.rows[#panel.rows + 1] = { button = b, text = text }
        y = y - 34
    end
    local function SoundName(kind)
        return (ns.SOUNDS[ns.db.sounds[kind] or ns.DEFAULT_SOUND[kind]] or ns.SOUNDS[1]).name
    end

    Row("Who uses this computer",
        function() return ns.db.helper and "A guide  (click to change)" or "Someone being guided  (click to change)" end,
        function() DadMode_SetRole(not ns.db.helper) end)
    Row("Show calls from the party on my screen",
        function() return ns.db.alerts and "On" or "Off" end,
        function() ns.db.alerts = not ns.db.alerts end)
    Row("Sound when someone calls",
        function() return SoundName("call") end,
        function() ns.db.sounds.call = ((ns.db.sounds.call or ns.DEFAULT_SOUND.call) % #ns.SOUNDS) + 1; ns.Beep("call", true) end)
    Row("Sound when I drift far away",
        function() return SoundName("far") end,
        function() ns.db.sounds.far = ((ns.db.sounds.far or ns.DEFAULT_SOUND.far) % #ns.SOUNDS) + 1; ns.Beep("far", true) end)
    Row("Far-away warning",
        function() return ns.db.farWarning and "On" or "Off" end,
        function() ns.db.farWarning = not ns.db.farWarning end)
    Row("Green follow button",
        function() return ns.db.follow and "Shown" or "Hidden" end,
        function() ns.db.follow = not ns.db.follow end)
    Row("Arrow size",
        function() return (ns.ARROW_SIZES[ns.db.arrowSize or 2] or ns.ARROW_SIZES[2])[1] end,
        function() ns.db.arrowSize = (ns.db.arrowSize or 2) % #ns.ARROW_SIZES + 1 end)
    Row("Window size",
        function() return math.floor((ns.SCALES[ns.db.scale or 3] or 1) * 100 + 0.5) .. "%" end,
        function() ns.db.scale = (ns.db.scale or 3) % #ns.SCALES + 1; ApplyScale() end)
    Row("Reset window sizes",
        function() return "Back to normal size" end,
        function() ResetSizes() end)
    Row("Arrows and follow button",
        function() return ns.moving and "Unlocked: drag them, then click here" or "Locked  (click to move them)" end,
        function() ns.moving = not ns.moving; if ns.bar then ns.bar:EnableMouse(ns.moving) end end)
    Row("Guide bar layout",
        function() return ns.db.helperCols == 1 and "1 column" or "2 columns" end,
        function()
            if ns.InFight() then
                ns.Print("Not during a fight. Try again after.")
                return
            end
            ns.db.helperCols = (ns.db.helperCols == 1) and 2 or 1
            if ns.helper and ns.helper.Layout then ns.helper.Layout() end
        end)
    Row("Try it: show a call on my own screen",
        function() return "Test a call" end,
        function() DadMode_TestCall() end)
    Row("Compare drops with their gear",
        function() return ns.db.compare == false and "Off" or "On" end,
        function() ns.db.compare = (ns.db.compare == false) end)
    Row("My guides and what they may see",
        function() return "Open" end,
        function() if DadMode_OpenGuides then DadMode_OpenGuides() end end)
    Row("Minimap button",
        function() return (ns.db.minimap and ns.db.minimap.hide) and "Hidden" or "Shown" end,
        function() DadMode_ToggleMinimapButton() end)

    panel:SetScript("OnShow", RefreshOptions)

    -- Hand the page to the game. If this game version has no such window, the settings stay
    -- reachable from the small DadMode window instead.
    pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "DadMode")
            Settings.RegisterAddOnCategory(category)
            ns.optionsCategory = category
            ns.optionsCategory = category
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
            ns.optionsCategory = panel
            ns.optionsCategory = panel
        end
    end)
end

-- Opens the settings page. Falls back to the small window with its options unfolded.
local function OpenSettings()
    if ns.optionsCategory and not ns.InFight() then
        local ok = pcall(function()
            if Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(type(ns.optionsCategory.GetID) == "function" and ns.optionsCategory:GetID() or ns.optionsCategory)
            else
                InterfaceOptionsFrame_OpenToCategory(ns.optionsCategory)
            end
        end)
        if ok then
            if ns.picker then ns.picker:Hide() end
            return
        end
    end
    ns.OpenPicker(true)
end
DadMode_OpenSettings = OpenSettings
function DadMode_HasOptionsPage() return ns.optionsCategory ~= nil end

-- used by other files of DadMode
ns.ApplyScale = ApplyScale
ns.ResetSizes = ResetSizes
