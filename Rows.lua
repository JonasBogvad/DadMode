-- DadMode: the page inside the "How is ... doing" window. Plain text and rows, stacked top to bottom.
-- A row lines up in columns: a label on the left, the facts in the middle with small coloured
-- chips under them, and a button on the right.

local ADDON, ns = ...

local PAD = 8             -- space above and below what is in a row
local LABEL_W = 62        -- the column on the left
local BTN_W = 96          -- the column on the right
local CHIP_H = 18
local GAP = 4

-- What a button looks like: background, then text colour
local BUTTON = {
    action = { 0.40, 0.33, 0.14, 1.00, 0.82, 0.29 },      -- something to click
    wait   = { 0.16, 0.18, 0.22, 0.60, 0.63, 0.65 },      -- asked, waiting for him
    done   = { 0.10, 0.24, 0.14, 0.48, 0.89, 0.58 },
    bad    = { 0.26, 0.11, 0.11, 0.96, 0.64, 0.64 },
}
local CHIP = {
    [true]  = { 0.09, 0.23, 0.13, 0.48, 0.89, 0.58 },     -- he gains this
    [false] = { 0.26, 0.11, 0.11, 0.96, 0.64, 0.64 },     -- he loses this
}

-- Pieces of text between the rows. The first one is the window's own text.
-- Texts and rows belong to the window they were made for (win.texts, win.rows).
local function Text(i)
    local texts = ns.questWin.texts
    if texts[i] then return texts[i] end
    local content = ns.questWin.content
    local fs = (i == 1) and ns.questWin.text or content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(2)
    texts[i] = fs
    return fs
end

local function Row(i)
    local rows = ns.questWin.rows
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, ns.questWin.content)
    r.line = ns.Tex(r, "BACKGROUND", 1, 1, 1, 0.08)
    r.line:SetPoint("TOPLEFT")
    r.line:SetPoint("TOPRIGHT")
    r.line:SetHeight(1)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.label:SetPoint("TOPLEFT", 0, -PAD - 1)
    r.label:SetWidth(LABEL_W)
    r.label:SetJustifyH("LEFT")
    r.main = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.main:SetPoint("TOPLEFT", LABEL_W + 6, -PAD)
    r.main:SetJustifyH("LEFT")
    r.main:SetJustifyV("TOP")
    r.main:SetSpacing(2)
    r.btn = ns.BigButton(r, BTN_W, 24, function(self)
        if self.onClick then self.onClick() end
    end)
    r.btn:SetPoint("RIGHT", 0, 0)
    ns.FontSize(r.btn.label, 12)
    r.btn.onClick = false
    r.chips = {}
    ns.EnableLinks(r)
    rows[i] = r
    return r
end

local function Chip(r, i)
    if r.chips[i] then return r.chips[i] end
    local c = CreateFrame("Frame", nil, r)
    c:SetHeight(CHIP_H)
    c.bg = ns.Tex(c, "BACKGROUND", 0, 0, 0, 1)
    c.bg:SetAllPoints()
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetPoint("CENTER")
    r.chips[i] = c
    return c
end

-- Puts one row on the page at y pixels from the top and returns its height
local function PlaceRow(r, spec, y, width)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 4, -y)
    r:SetWidth(width - 8)
    r.label:SetText(spec.slot or "")
    local mainW = math.max(width - 8 - LABEL_W - 6 - (spec.button and (BTN_W + 10) or 0), 120)
    r.main:SetWidth(mainW)
    r.main:SetText((spec.title or "") .. ((spec.sub and spec.sub ~= "") and ("\n" .. spec.sub) or ""))
    local h = PAD + (r.main:GetStringHeight() or 30)

    -- chips flow from left to right and wrap to a new line when the column is full
    local x, line, n = 0, 0, 0
    for _, chip in ipairs(spec.chips or {}) do
        n = n + 1
        local c = Chip(r, n)
        local look = CHIP[chip.good and true or false]
        c.text:SetText(chip.text)
        c.text:SetTextColor(look[4], look[5], look[6])
        c.bg:SetColorTexture(look[1], look[2], look[3], 1)
        local w = math.min((c.text:GetStringWidth() or 60) + 12, mainW)
        if x > 0 and x + w > mainW then x, line = 0, line + 1 end
        c:SetWidth(w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", LABEL_W + 6 + x, -(h + GAP + line * (CHIP_H + GAP)))
        c:Show()
        x = x + w + GAP
    end
    for i = n + 1, #r.chips do r.chips[i]:Hide() end
    if n > 0 then h = h + GAP + (line + 1) * (CHIP_H + GAP) - GAP end
    h = math.max(h + PAD, 40)

    if spec.button then
        local look = BUTTON[spec.button.kind] or BUTTON.action
        r.btn.bg:SetColorTexture(look[1], look[2], look[3], 1)
        r.btn.label:SetTextColor(look[4], look[5], look[6])
        r.btn.label:SetText(spec.button.text)
        r.btn.onClick = spec.button.onClick or false
        r.btn:Show()
    else
        r.btn.onClick = false
        r.btn:Hide()
    end
    r.spec = spec
    r:SetHeight(h)
    r:Show()
    return h
end

-- blocks: a list where a string is a line of text and a table is a row:
--   { slot = "Ring", title = "...", sub = "...", chips = { { text = "+4 Stamina", good = true } },
--     button = { text = "Put it on", kind = "action", onClick = function } }
function DadMode_LayoutBlocks(blocks)
    local win = ns.questWin
    if not win then return end
    win.texts, win.rows = win.texts or {}, win.rows or {}
    local texts, rows = win.texts, win.rows
    local width = win.content:GetWidth()
    if type(width) ~= "number" or width < 200 then width = 436 end
    local y, usedTexts, usedRows = 4, 0, 0
    local buffer = {}
    local function Flush()
        if #buffer == 0 then return end
        usedTexts = usedTexts + 1
        local fs = Text(usedTexts)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 4, -y)
        fs:SetWidth(width - 8)
        fs:SetText(table.concat(buffer, "\n"))
        fs:Show()
        y = y + (fs:GetStringHeight() or 14) + 6
        buffer = {}
    end
    for _, block in ipairs(blocks) do
        if type(block) == "table" then
            Flush()
            usedRows = usedRows + 1
            y = y + PlaceRow(Row(usedRows), block, y, width)
        else
            buffer[#buffer + 1] = block
        end
    end
    Flush()
    if usedTexts == 0 then Text(1):SetText("") end
    for i = usedTexts + 1, #texts do
        texts[i]:SetText("")
        texts[i]:Hide()
    end
    for i = usedRows + 1, #rows do
        rows[i].spec = false
        rows[i]:Hide()
    end
    win.usedRows = usedRows
    win.content:SetHeight(y + 16)
end
