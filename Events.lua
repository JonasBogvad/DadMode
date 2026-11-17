-- DadMode: game events and incoming messages

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

handlers.ADDON_LOADED = function(name)
    if name ~= "DadMode" then return end
    local fresh = (DadModeDB == nil)
    DadModeDB = DadModeDB or {}
    ns.db = DadModeDB
    ns.db = ns.db
    -- A computer that already used DadMode keeps its role and is not asked
    if ns.db.roleChosen == nil then ns.db.roleChosen = not fresh end
    ns.db.marked = ns.db.marked or {}
    if ns.db.enabled == nil then ns.db.enabled = true end
    if ns.db.alerts == nil then ns.db.alerts = true end
    if ns.db.farWarning == nil then ns.db.farWarning = true end
    if ns.db.helper == nil then ns.db.helper = false end
    if ns.db.follow == nil then ns.db.follow = true end
    ns.db.sounds = ns.db.sounds or {}
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ns.PREFIX)
    end
end

handlers.PLAYER_LOGIN = function()
    local ok, err = pcall(function()
        DadMode_CreateBar()
        DadMode_CreatePicker()
        DadMode_CreateHelper()
        DadMode_CreateFollow()
        DadMode_CreateQuestWindow()
        DadMode_CreateMinimapButton()
        DadMode_CreateRoleWindow()
        DadMode_CreateOptions()
        if DadMode_HookTooltips then DadMode_HookTooltips() end
        if DadMode_TrustInit then DadMode_TrustInit() end
        ns.ApplyScale()
        if not ns.db.roleChosen then ns.roleWin:Show() end
    end)
    if not ok then ns.Print("Could not start, please report this to the addon author: " .. tostring(err)) end
end

local lastPickHint = -9999

handlers.TAXIMAP_OPENED = function()
    pcall(ns.FlightHint)
end

handlers.GROUP_ROSTER_UPDATE = function()
    if not ns.picker then return end
    local list = ns.Party()
    if ns.picker:IsShown() then ns.RefreshPicker() end
    if #list == 0 or not ns.db.enabled or ns.db.helper then return end      -- helpers are never asked
    for _, m in ipairs(list) do
        if ns.db.marked[m.name] then return end                           -- someone here is picked: nothing to do
    end
    if next(ns.db.marked) == nil and not ns.db.askedOnce then
        -- He has never picked anyone: open the window, this one time only
        ns.db.askedOnce = true
        ns.OpenPicker(false)
    elseif GetTime() - lastPickHint > 600 then
        -- Otherwise just one quiet line in chat, at most every 10 minutes
        lastPickHint = GetTime()
        ns.Print("Nobody in this party is picked, so there are no arrows. Click the gold arrow on the minimap to pick someone.")
    end
end

-- A fight is about to start. The game still allows moving these frames for this one moment,
-- so anything being dragged is let go now. Afterwards it would be blocked and stick to the mouse.
-- Item names for the gear list load a moment after they are first asked for
handlers.GET_ITEM_INFO_RECEIVED = function()
    if ns.questWin and ns.questWin:IsShown() and (ns.questWin.view == "gear" or ns.questWin.view == "quests") and not ns.questWin.redraw then
        ns.questWin.redraw = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function()
                ns.questWin.redraw = false
                DadMode_RenderQuests()
            end)
        else
            ns.questWin.redraw = false
            DadMode_RenderQuests()
        end
    end
end

handlers.PLAYER_REGEN_ENABLED = function()
    pcall(ns.ApplyScale)
end

handlers.PLAYER_REGEN_DISABLED = function()
    if ns.helper and ns.helper.grip and ns.helper.grip.Stop then ns.helper.grip.Stop() end
    for _, f in ipairs({ ns.helper, ns.followBtn }) do
        if f and f.dragging then
            f.dragging = false
            f:StopMovingOrSizing()
            local point, _, rel, x, y = f:GetPoint()
            if f == ns.helper then ns.db.helperPos = { point, rel, x, y } else ns.db.followPos = { point, rel, x, y } end
        end
    end
end

handlers.CHAT_MSG_ADDON = function(prefix, text, channel, sender)
    if not ns.Usable(prefix, "string") or prefix ~= ns.PREFIX then return end
    if not ns.Usable(text, "string") or not ns.Usable(sender, "string") then return end
    if DadMode_RemoteHeard then
        local ok, verdict = pcall(DadMode_RemoteHeard, text, channel, sender)
        if ok and verdict == "drop" then return end
    end
    if DadMode_Heard then pcall(DadMode_Heard, text, channel, sender) end
    -- "TO:<first name>:<message>" is meant for one person only (from 1.23)
    if text:sub(1, 3) == "TO:" then
        local key, inner = text:match("^TO:([^:]+):(.*)$")
        local okMe, me = pcall(UnitName, "player")
        if not key or not okMe or ns.Key(me) ~= key then return end
        text = inner
    end
    if DadMode_TrackHeard then pcall(DadMode_TrackHeard, text, sender) end
    if DadMode_Gate and DadMode_Gate(text, sender) then return end
    if DadMode_ExtraMessage and DadMode_ExtraMessage(text, sender) then return end
    if DadMode_WearMessage and DadMode_WearMessage(text, sender) then return end
    if DadMode_TalentMessage and DadMode_TalentMessage(text, sender) then return end
    if DadMode_TrackMessage and DadMode_TrackMessage(text, sender) then return end
    local body = text:match("^PING:(.*)$")
    if body then
        ns.ReceivePing(sender, body)
    elseif text == "CLEAR" then
        ns.ReceiveClear(sender)
    elseif text == "WPC" or text:sub(1, 3) == "WP:" then
        DadMode_ReceiveWaypoint(sender, text)
    elseif text == "WPHERE" then
        local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
        if m then
            ns.wpOut = false
            ns.Print("|cff1aff1a" .. m.name .. " reached your marker.|r")
        end
    elseif text == "WPOK" or text == "WPNO" then
        local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
        if m and GetTime() - ns.lastSent < 30 then
            ns.wpOut = (text == "WPOK")
            ns.Print(text == "WPOK" and ("|cff1aff1a" .. m.name .. " has your waypoint on the map.|r")
                or ("|cffff4d4d" .. m.name .. " could not get the waypoint.|r Not possible in dungeons, or the map does not allow pins."))
        end
    elseif text:sub(1, 3) == "TS:" then
        local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
        if m then
            DadMode_ReceiveStops(text:sub(4))
            ns.travel.at = 0                      -- work out the route again with the new spots
        end
    elseif text:sub(1, 3) == "QC:" then
        local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
        if m and not ns.db.helper and not (ns.db.perm and ns.db.perm.quests == false) then pcall(DadMode_AnswerDone, text:sub(4), sender) end
    elseif text == "QREQ" then
        local m = (not ns.IsMe(sender)) and ns.Member(sender) or nil
        if m and not ns.db.helper then DadMode_SendQuests(sender, false) end
    elseif text == "QE" or text:sub(1, 3) == "QS:" or text:sub(1, 3) == "ST:" or text:sub(1, 3) == "QD:" or text:sub(1, 4) == "BGS:" or text:sub(1, 3) == "BG:" or text:sub(1, 3) == "GR:" or text:sub(1, 3) == "GL:" or text:sub(1, 3) == "SS:" or text:sub(1, 3) == "CN:" or text:sub(1, 2) == "Q:" then
        DadMode_ReceiveQuestData(sender, text)
    elseif text:match("^VER:") then
        local m = ns.Member(sender)
        if m then ns.peerVersion[m.name] = text:sub(5, 20) end
    elseif text == "ACK" or text == "HERE" or text == "MUTED" then
        DadMode_ReceiveReply(sender, text)
    end
end

handlers.CHAT_MSG_PARTY = ns.ChatPing
handlers.CHAT_MSG_PARTY_LEADER = ns.ChatPing
handlers.CHAT_MSG_WHISPER = ns.ChatPing

frame:SetScript("OnEvent", function(_, event, ...)
    -- by now every file of the addon has loaded: listen for the events they added too
    if event == "ADDON_LOADED" and (...) == "DadMode" then
        for name in pairs(handlers) do
            pcall(frame.RegisterEvent, frame, name)
        end
    end
    local h = handlers[event]
    if h then
        local ok, err = pcall(h, ...)
        if not ok then ns.Print("Error, please report this to the addon author: " .. tostring(err)) end
    end
end)

for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event)
end

-- used by other files of DadMode
ns.handlers = handlers
