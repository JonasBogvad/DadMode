-- DadMode: the page inside the "How is ... doing" window. Blocks stacked from top to bottom:
--   text   plain lines
--   row    a label on the left, the facts in the middle with small coloured chips, a button on the right
--   bar    a line of small buttons to switch things on and off
--   tiles  a grid of small boxes, each with a label and a value

local ADDON, ns = ...

local PAD = 8             -- space above and below what is in a row
local LABEL_W = 62        -- the column on the left of a row
local BTN_W = 96          -- the column on the right of a row
local CHIP_H = 18
local PILL_H = 22
local TILE_H = 46
local GAP = 4

-- Colours in the style of the game's own windows: dark red buttons with gold text, gold labels,
-- and the green and red the game uses for stats in tooltips.
-- A button: background, then text colour
local BUTTON = {
    action = { 0.42, 0.08, 0.06, 1.00, 0.82, 0.00 },      -- something to click
    wait   = { 0.18, 0.17, 0.15, 0.70, 0.70, 0.70 },      -- asked, waiting for him
    done   = { 0.07, 0.24, 0.07, 0.10, 1.00, 0.10 },
    bad    = { 0.30, 0.07, 0.07, 1.00, 0.35, 0.35 },
    off    = { 0.15, 0.14, 0.12, 0.80, 0.75, 0.60 },      -- a switch that is off
}
local CHIP = {
    good    = { 0.06, 0.20, 0.06, 0.10, 1.00, 0.10 },     -- he gains this, or it is done
    bad     = { 0.27, 0.06, 0.06, 1.00, 0.30, 0.30 },     -- he loses this, or it is missing
    gooddim = { 0.09, 0.12, 0.09, 0.35, 0.55, 0.35 },     -- a gain in a stat that does not count for him
    baddim  = { 0.14, 0.10, 0.10, 0.60, 0.42, 0.42 },
    plain   = { 0.17, 0.16, 0.14, 0.90, 0.87, 0.80 },     -- a fact without a colour
    dim     = { 0.12, 0.12, 0.11, 0.60, 0.58, 0.54 },
}
local VALUE = {           -- the colour of the value in a tile
    good = { 0.10, 1.00, 0.10 }, warn = { 1.00, 0.82, 0.00 }, bad = { 1.00, 0.30, 0.30 }, plain = { 1, 1, 1 },
}

local function Look(button, kind)
    local look = BUTTON[kind] or BUTTON.action
    button.bg:SetColorTexture(look[1], look[2], look[3], 1)
    button.label:SetTextColor(look[4], look[5], look[6])
end

---------------------------------------------------------------------------
-- Making the pieces. Each kind is kept on the window and used again on the next draw.
---------------------------------------------------------------------------

-- Pieces of text between the other blocks. The first one is the window's own text.
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
    r.line = ns.Tex(r, "BACKGROUND", 0.80, 0.65, 0.30, 0.22)
    r.line:SetPoint("TOPLEFT")
    r.line:SetPoint("TOPRIGHT")
    r.line:SetHeight(1)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.label:SetPoint("TOPLEFT", 0, -PAD - 1)
    r.label:SetWidth(LABEL_W)
    r.label:SetJustifyH("LEFT")
    r.main = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    for _, fs in ipairs({ r.main, r.sub }) do
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSpacing(2)
    end
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

local function Bar(i)
    local bars = ns.questWin.bars
    if bars[i] then return bars[i] end
    local b = CreateFrame("Frame", nil, ns.questWin.content)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("TOPLEFT", 0, -2)
    b.label:SetJustifyH("LEFT")
    b.pills = {}
    bars[i] = b
    return b
end

local function Pill(b, i)
    if b.pills[i] then return b.pills[i] end
    local p = ns.BigButton(b, 60, PILL_H, function(self)
        if self.onClick then self.onClick() end
    end)
    ns.FontSize(p.label, 11)
    p.onClick = false
    b.pills[i] = p
    return p
end

local function Tiles(i)
    local grids = ns.questWin.grids
    if grids[i] then return grids[i] end
    local g = CreateFrame("Frame", nil, ns.questWin.content)
    g.tiles = {}
    grids[i] = g
    return g
end

local function Tile(g, i)
    if g.tiles[i] then return g.tiles[i] end
    local t = CreateFrame("Frame", nil, g)
    t:SetHeight(TILE_H)
    t.bg = ns.Tex(t, "BACKGROUND", 0.11, 0.10, 0.09, 1)
    t.bg:SetAllPoints()
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.label:SetPoint("TOPLEFT", 8, -6)
    t.value = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t.value:SetPoint("TOPLEFT", 8, -22)
    t.value:SetJustifyH("LEFT")
    pcall(function() t.value:SetWordWrap(false) end)
    g.tiles[i] = t
    return t
end

---------------------------------------------------------------------------
-- Putting one block on the page at y pixels from the top. Each returns its height.
---------------------------------------------------------------------------

-- Small coloured boxes that flow from left to right and wrap. Returns the height they took.
local function FlowChips(r, chips, left, top, room)
    local x, line, n = 0, 0, 0
    for _, chip in ipairs(chips or {}) do
        n = n + 1
        local c = Chip(r, n)
        local look = CHIP[chip.kind] or CHIP.plain
        c.text:SetText(chip.text)
        c.text:SetTextColor(look[4], look[5], look[6])
        c.bg:SetColorTexture(look[1], look[2], look[3], 1)
        local w = math.min((c.text:GetStringWidth() or 60) + 12, room)
        if x > 0 and x + w > room then x, line = 0, line + 1 end
        c:SetWidth(w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", left + x, -(top + line * (CHIP_H + GAP)))
        c:Show()
        x = x + w + GAP
    end
    for i = n + 1, #r.chips do r.chips[i]:Hide() end
    return (n > 0) and ((line + 1) * (CHIP_H + GAP) - GAP) or 0
end

-- spec.chipsTop: the chips sit right under the title, before the smaller lines
local function PlaceRow(r, spec, y, width)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 4, -y)
    r:SetWidth(width - 8)
    local left = spec.slot and (LABEL_W + 6) or 0
    r.label:SetText(spec.slot or "")
    local room = math.max(width - 8 - left - (spec.button and (BTN_W + 10) or 0), 120)
    local h = PAD

    r.main:ClearAllPoints()
    r.main:SetPoint("TOPLEFT", left, -h)
    r.main:SetWidth(room)
    r.main:SetText(spec.title or "")
    h = h + (r.main:GetStringHeight() or 14)

    local function Sub()
        if spec.sub and spec.sub ~= "" then
            r.sub:ClearAllPoints()
            r.sub:SetPoint("TOPLEFT", left, -(h + 2))
            r.sub:SetWidth(room)
            r.sub:SetText(spec.sub)
            r.sub:Show()
            h = h + 2 + (r.sub:GetStringHeight() or 14)
        else
            r.sub:SetText("")
            r.sub:Hide()
        end
    end
    local function Chips()
        local took = FlowChips(r, spec.chips, left, h + GAP, room)
        if took > 0 then h = h + GAP + took end
    end
    if spec.chipsTop then Chips(); Sub() else Sub(); Chips() end
    h = math.max(h + PAD, 36)

    if spec.button then
        Look(r.btn, spec.button.kind)
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

local function PlaceBar(b, spec, y, width)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 4, -y)
    b:SetWidth(width - 8)
    local room = width - 8
    local top = 0
    if spec.label and spec.label ~= "" then
        b.label:SetText(spec.label)
        b.label:Show()
        top = 18
    else
        b.label:SetText("")
        b.label:Hide()
    end
    local x, line, n = 0, 0, 0
    for _, item in ipairs(spec.items or {}) do
        n = n + 1
        local p = Pill(b, n)
        p.label:SetText(item.text)
        Look(p, item.on and "action" or "off")
        p.onClick = item.onClick or false
        p.on = item.on and true or false
        local w = math.min((p.label:GetStringWidth() or 60) + 16, room)
        if x > 0 and x + w > room then x, line = 0, line + 1 end
        p:SetWidth(w)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", x, -(top + line * (PILL_H + GAP)))
        p:Show()
        x = x + w + GAP
    end
    for i = n + 1, #b.pills do b.pills[i]:Hide() end
    local h = top + (n > 0 and ((line + 1) * (PILL_H + GAP)) or 0) + 4
    b.spec = spec
    b:SetHeight(h)
    b:Show()
    return h
end

local function PlaceTiles(g, spec, y, width)
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", 4, -y)
    g:SetWidth(width - 8)
    local room = width - 8
    local cols = math.max(2, math.floor(room / 140))
    local tileW = (room - (cols - 1) * GAP) / cols
    local col, line, n = 0, 0, 0
    for _, tile in ipairs(spec.tiles or {}) do
        n = n + 1
        local t = Tile(g, n)
        local span = tile.wide and math.min(2, cols) or 1
        if col + span > cols then col, line = 0, line + 1 end
        local w = tileW * span + GAP * (span - 1)
        t:SetWidth(w)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", col * (tileW + GAP), -(line * (TILE_H + GAP)))
        t.label:SetText(tile.label)
        t.value:SetWidth(w - 16)
        t.value:SetText(tile.value)
        local c = VALUE[tile.kind] or VALUE.plain
        t.value:SetTextColor(c[1], c[2], c[3])
        t:Show()
        col = col + span
    end
    for i = n + 1, #g.tiles do g.tiles[i]:Hide() end
    local h = (n > 0) and ((line + 1) * (TILE_H + GAP)) or 0
    g.spec = spec
    g:SetHeight(math.max(h, 1))
    g:Show()
    return h + 4
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

-- blocks: a list. A string is a line of text. A table is one of:
--   { row = true, slot = "Ring", title = "...", sub = "...", chipsTop = false,
--     chips = { { text = "+4 Stamina", kind = "good" } },
--     button = { text = "Put it on", kind = "action", onClick = function } }
--   { bar = true, label = "Sort", items = { { text = "By slot", on = true, onClick = function } } }
--   { tiles = { { label = "Bags", value = "12 free", kind = "good", wide = false } } }
function DadMode_LayoutBlocks(blocks)
    local win = ns.questWin
    if not win then return end
    win.texts, win.rows, win.bars, win.grids = win.texts or {}, win.rows or {}, win.bars or {}, win.grids or {}
    local width = win.content:GetWidth()
    if type(width) ~= "number" or width < 200 then width = 436 end
    local y = 4
    local used = { texts = 0, rows = 0, bars = 0, grids = 0 }
    local buffer = {}
    local function Flush()
        if #buffer == 0 then return end
        used.texts = used.texts + 1
        local fs = Text(used.texts)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 4, -y)
        fs:SetWidth(width - 8)
        fs:SetText(table.concat(buffer, "\n"))
        fs:Show()
        y = y + (fs:GetStringHeight() or 14) + 6
        buffer = {}
    end
    for _, block in ipairs(blocks) do
        if type(block) ~= "table" then
            buffer[#buffer + 1] = block
        else
            Flush()
            if block.row then
                used.rows = used.rows + 1
                y = y + PlaceRow(Row(used.rows), block, y, width)
            elseif block.bar then
                used.bars = used.bars + 1
                y = y + PlaceBar(Bar(used.bars), block, y, width)
            elseif block.tiles then
                used.grids = used.grids + 1
                y = y + PlaceTiles(Tiles(used.grids), block, y, width)
            end
        end
    end
    Flush()
    if used.texts == 0 then Text(1):SetText("") end
    for i = used.texts + 1, #win.texts do
        win.texts[i]:SetText("")
        win.texts[i]:Hide()
    end
    for _, kind in ipairs({ "rows", "bars", "grids" }) do
        for i = used[kind] + 1, #win[kind] do
            win[kind][i].spec = false
            win[kind][i]:Hide()
        end
    end
    win.usedRows, win.usedBars, win.usedGrids, win.blocks = used.rows, used.bars, used.grids, blocks
    win.content:SetHeight(y + 16)
end
