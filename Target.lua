-- DadMode: Who a guide's calls and waypoints are for

-- Shared with DadMode.lua through the table the game gives every file of an addon.
-- Things that only exist after login (saved settings, windows) are read as ns.<name>.
local ADDON, ns = ...
local Party, peerVersion, questData
    = ns.Party, ns.peerVersion, ns.questData

-- The people in the party a guide can guide: everybody who runs DadMode and is not a guide
function DadMode_Candidates()
    local out = {}
    for _, m in ipairs(Party()) do
        local d = questData[m.name]
        local role = DadMode_RoleOf and DadMode_RoleOf(m.name) or nil
        local known = peerVersion[m.name] or d
        if known and role ~= "g" then out[#out + 1] = m end
    end
    return out
end

-- The one chosen, or nil for "everyone". Second value: true when there are two or more to choose from.
function DadMode_TargetName()
    local list = DadMode_Candidates()
    if #list == 1 then return list[1].name, false end
    if #list >= 2 then
        for _, m in ipairs(list) do
            if ns.db.aim and m.key == ns.db.aim then return m.name, true end
        end
        return nil, true
    end
    return nil, false
end

function DadMode_TargetLine()
    local list = DadMode_Candidates()
    if #list == 0 then return "|cff9aa0a6Guiding: nobody with DadMode in the party|r" end
    if #list == 1 then return "Guiding: |cffffd100" .. list[1].name .. "|r" end
    local who = DadMode_TargetName()
    return "Guiding: |cffffd100" .. (who or "everyone") .. "|r  |cff9aa0a6(click to change)|r"
end

-- everyone -> first -> second -> ... -> everyone
function DadMode_NextTarget()
    local list = DadMode_Candidates()
    if #list < 2 then return end
    local at = 0
    for i, m in ipairs(list) do
        if ns.db.aim and m.key == ns.db.aim then at = i end
    end
    local nxt = list[at + 1]
    ns.db.aim = nxt and nxt.key or nil
end

-- A message for one person. Versions before 1.23 do not know the address, so they get it plain.
function DadMode_AimAt(name, body)
    for _, m in ipairs(Party()) do
        if m.name == name then
            local d = questData[m.name]
            local v = peerVersion[m.name] or (d and d.st and d.st.v)
            if v and DadMode_VersionNumber and DadMode_VersionNumber(v) >= DadMode_VersionNumber("1.23.0") then
                return "TO:" .. m.key .. ":" .. body
            end
        end
    end
    return body
end

-- A call, a cancel or a waypoint: to the chosen one when one of several is chosen, else to all
function DadMode_Aim(body)
    local who, several = DadMode_TargetName()
    if who and several then return DadMode_AimAt(who, body) end
    return body
end
