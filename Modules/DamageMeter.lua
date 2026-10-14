-- ProseccoUI / Modules / DamageMeter.lua
-- A frame of ours round each of Ellesmere's damage meter windows (background,
-- padding, border), plus test bars in Ellesmere's row look and a preview on
-- our settings page. A window showing Threat gets the same frame.
--
-- Ellesmere's windows are only read. Our frames are their children, so they
-- follow show/hide, fade and scale; nothing is written on their frames and
-- none of their functions is hooked or replaced.
--
-- Owned Ellesmere settings: its window background and border are set to 0
-- (ours replace them) and the meter's look to the Prosecco values. Written
-- when the module is switched on or with "Set Ellesmere Values", given back
-- whenever the module goes off; never rewritten at login.
--
-- Header box: Ellesmere pins its rows to its header's bottom and has no gap
-- setting, so its header is made taller and see-through through its own
-- settings (Header Height = height + 2 x (gap + padding), header opacity 0,
-- header bottom border 0). We draw a header box in its middle, where
-- Ellesmere centres the title and buttons, and the body box under it.
--
-- Off: no frames, no events. Ellesmere's own background and border come back
-- when it rebuilds.

local _, ns = ...

-- The Ellesmere settings this module owns, and the value it needs.
local OWNED = {
    { target = "damageMeters", key = "bgAlpha",                           value = 0, label = "Damage Meters: Background Opacity" },
    { target = "damageMeters", key = "windowBorderSize",                  value = 0, label = "Damage Meters: Window Border Size" },
}
-- The meter's look: the Prosecco values, so the button gives the same look
-- on any Ellesmere profile. Keys as Ellesmere's DM_DEFAULTS.
local GREY48, GREY64 = 48 / 255, 64 / 255
local LOOK = {
    { "barHeight", 26, "Bar Height" }, { "barSpacing", 5, "Bar Spacing" },
    { "barTexture", "none", "Bar Texture" }, { "barFillAlpha", 1, "Bar Opacity" },
    { "barColorUseAccent", false, "Bar Color: Use Accent" },
    { "barColor.r", GREY64, "Bar Color" }, { "barColor.g", GREY64, "Bar Color" }, { "barColor.b", GREY64, "Bar Color" },
    { "showClassColor", false, "Class Colored Bars" },
    { "barBgR", GREY48, "Bar Background" }, { "barBgG", GREY48, "Bar Background" }, { "barBgB", GREY48, "Bar Background" },
    { "barBgAlpha", 1, "Bar Background Opacity" }, { "barBgUseClassColor", false, "Bar Background: Class Color" },
    { "borderSize", 1, "Bar Border Size" }, { "borderTexture", "solid", "Bar Border Style" },
    { "borderFollowFill", true, "Bar Border: Follow Fill" }, { "borderFollowFillIcon", true, "Bar Border: Include Icon" },
    { "borderR", 0, "Bar Border Color" }, { "borderG", 0, "Bar Border Color" }, { "borderB", 0, "Bar Border Color" },
    { "borderA", 1, "Bar Border Color" },
    { "iconStyle", "pixelsComic", "Icon Style" }, { "customIconBorder", true, "Icon Border" },
    { "iconBorderSize", 1, "Icon Border Size" }, { "iconBorderTexture", "solid", "Icon Border Style" },
    { "iconBorderR", 0, "Icon Border Color" }, { "iconBorderG", 0, "Icon Border Color" },
    { "iconBorderB", 0, "Icon Border Color" }, { "iconBorderA", 1, "Icon Border Color" },
    { "leftFontSize", 12, "Left Text Size" }, { "rightFontSize", 12, "Right Text Size" },
    { "leftTextUseClassColor", true, "Left Text: Class Color" }, { "rightTextUseClassColor", true, "Right Text: Class Color" },
    { "leftTextOffsetX", 0, "Left Text X Offset" }, { "leftTextOffsetY", 0, "Left Text Y Offset" },
    { "rightTextOffsetX", 0, "Right Text X Offset" }, { "rightTextOffsetY", 0, "Right Text Y Offset" },
    { "hdrFontSize", 12, "Header Text Size" }, { "hdrTextOffX", -4, "Title X Offset" },
    { "hdrTextOffY", 0, "Title Y Offset" }, { "hdrIconSize", 22, "Header Icon Size" },
    { "hdrTextUseAccent", false, "Header Text: Use Accent" },
}
for _, l in ipairs(LOOK) do
    OWNED[#OWNED + 1] = { target = "damageMeters", key = l[1], value = l[2], label = "Damage Meters: " .. l[3] }
end

local M = ns.RegisterModule("damageMeter", {
    title       = "Damage Meter",
    description = "Background, padding and border around Ellesmere's damage meter windows.",
    pages       = { "Damage Meter" },
    defaults    = {
        -- Ellesmere's own background default is black at 0.75, so the meters
        -- look as dark once theirs is set to 0. The header box colour is
        -- Ellesmere's own header default.
        damage = { padding = 4, bgColor = "000000", bgAlpha = 0.75,
            border = { useGlobal = true, style = "solid", size = 1, color = "000000", alpha = 1 },
            seam = false,       -- one border round header and bars, a line where they meet
            -- Windows side by side share one border with a seam between them.
            joinWindows = true,
            -- Older profiles may hold `detached` and `topPadding`: not read.
            -- The header box is always on; the space under it is Padding.
            header = { height = 22, gap = 4, bgColor = "1B1B1B", bgAlpha = 1 } },
        useGlobalBackground = true,     -- the boxes take the General page's colours
    },
    affects     = {
        "Ellesmere's damage meter background opacity and window border size are set to 0; ProseccoAdditions draws its own.",
        "Ellesmere's damage meter Header Height, header opacity and header bottom border are taken for ProseccoAdditions' header box.",
        "Ellesmere's damage meter bar, bar text, icon and header text values are set to the Prosecco look.",
        "The values from before are put back when Damage Meter is turned off.",
    },
    affectsOff  = {
        "ProseccoAdditions' frame around the damage meter is removed.",
        "Ellesmere's damage meter values go back to what they were before Damage Meter was turned on (a value you changed in Ellesmere since then stays). They show after a /reload, which you are asked for.",
    },
})

local function DB() return ns.db.modules.damageMeter end

-- ---------------------------------------------------------------------------
-- Owned Ellesmere settings
-- ---------------------------------------------------------------------------

local function WriteOwned() ns.TakeOwned("damageMeter", OWNED, "DM") end
local function RestoreOwned() return ns.GiveBackOwned("damageMeter", "DM") end

-- Ellesmere's header is our header box plus, above and below it, the gap
-- and the padding, so the title stays centred in the box. Height and Gap are
-- UI units, as Ellesmere's own Header Height slider; Padding is pixels, as
-- on the box's other sides. With the Header Seam there is no gap.
local function HeaderGap(cfg)
    if cfg.seam then return 0 end
    return tonumber(cfg.header.gap) or 0
end

-- The space between the bar box's top and the first bar: the box's Padding,
-- as on its other sides. Pixels, so it matches the sides at any UI scale.
local function TopPadding(cfg) return ns.Ellesmere.Pixels(cfg.padding) end

-- Ellesmere's Header Height for our header box.
local function HeaderTotal()
    local d = DB().damage
    return (tonumber(d.header.height) or 22) + 2 * (HeaderGap(d) + TopPadding(d))
end

-- Ellesmere's header is ours only in its EllesmereUI look: the stock looks
-- read hdrHeight too but draw their own header art, so no box is drawn
-- there (DrawAll).
local function HeaderUsed()
    return ns.Ellesmere.DMHeaderHeight() ~= nil and not ns.Ellesmere.DMStockStyle()
end

local function HeaderOwned(total)
    return {
        { target = "damageMeters", key = "hdrHeight",           value = total, label = "Damage Meters: Header Height" },
        { target = "damageMeters", key = "hdrBgAlpha",          value = 0,     label = "Damage Meters: Header Opacity" },
        { target = "damageMeters", key = "hdrBottomBorderSize", value = 0,     label = "Damage Meters: Header Bottom Border" },
    }
end
-- `headerWritten` is the total last written from this profile, so M:Apply
-- can tell when our sizes changed without a write (an older profile, a page
-- Reset). Ellesmere's own value is not compared, so a Header Height set in
-- Ellesmere's menu is not written over at login.
local function WriteHeaderOwned()
    if not HeaderUsed() then return end
    local total = HeaderTotal()
    ns.TakeOwned("damageMeterHeader", HeaderOwned(total), "DM")
    DB().damage.headerWritten = total
end
local function RestoreHeaderOwned() return ns.GiveBackOwned("damageMeterHeader", "DM") end

-- ---------------------------------------------------------------------------
-- Our frames around Ellesmere's windows
-- ---------------------------------------------------------------------------

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local STRATA_INDEX = {}
for i, s in ipairs(STRATA) do STRATA_INDEX[s] = i end

-- Above Ellesmere's own window parts: its header is frame level +5, the
-- breakdown panel +20.
local EDGE_LEVEL = 25
local TEST_LEVEL = 22

-- Ellesmere window -> { bg = our frame, edge = our frame, test = our frame or nil }.
-- Weak keys: nothing is written on their frame.
local rings = setmetatable({}, { __mode = "k" })
local host                  -- event frame while the module is on
local active = false        -- between Enable and Disable; gates the menu-closed redraw
local testing = false       -- test bars shown (runtime only)
local preview               -- our page's preview frame, made on first use

-- Ellesmere's meter windows alive now: those its global names point at,
-- plus any window we framed that still has its parent though its name now
-- points at a newer one (close window 2 of 3, then New Window: Ellesmere
-- names the new one EllesmereUIDMFrame3 too).
local function LiveWindows()
    local wins = ns.Ellesmere.DMFrames()
    for win in pairs(rings) do
        if win ~= preview and win:GetParent() then
            local listed = false
            for _, w in ipairs(wins) do if w == win then listed = true break end end
            if not listed then wins[#wins + 1] = win end
        end
    end
    return wins
end

local StartWatch            -- below: watches for windows Ellesmere (re)builds
local MouseOnWindow         -- below: a click that can concern the windows

local function Ring(win)
    local r = rings[win]
    if r then return r end
    r = {}
    -- The background sits one strata below the window, so it is behind every
    -- part of Ellesmere's window whatever their frame levels are.
    r.bg = CreateFrame("Frame", nil, win)
    r.bg:EnableMouse(false)
    -- Ellesmere hides a window before it drops it (on close, and on the
    -- rebuild at its profile, spec or condition switch), so our own frame's
    -- OnHide is the signal to look for the new windows. Hooked on our frame,
    -- not on Ellesmere's.
    r.bg:HookScript("OnHide", function() StartWatch() end)
    -- Shown again: it may join (or part) a row of windows (Joins).
    r.bg:HookScript("OnShow", function() StartWatch() end)
    r.bg.tex = r.bg:CreateTexture(nil, "BACKGROUND")
    r.bg.tex:SetAllPoints(r.bg)
    -- The border on top: with padding 0 it lies on the window's own edge.
    r.edge = CreateFrame("Frame", nil, win)
    r.edge:EnableMouse(false)
    -- The header box: the same two layers, made when first needed (HeaderBox).
    rings[win] = r
    return r
end

local function HeaderBox(win, r)
    if r.hbg then return end
    r.hbg = CreateFrame("Frame", nil, win)
    r.hbg:EnableMouse(false)
    r.hbg.tex = r.hbg:CreateTexture(nil, "BACKGROUND")
    r.hbg.tex:SetAllPoints(r.hbg)
    r.hedge = CreateFrame("Frame", nil, win)
    r.hedge:EnableMouse(false)
end

local function HideHeaderBox(r)
    if r.hbg then r.hbg:Hide(); r.hedge:Hide() end
    if r.seam then r.seam:Hide() end
    if r.hvseam then r.hvseam:Hide() end
end

-- Puts f behind win: one strata below, so it is behind every part of
-- Ellesmere's window whatever their frame levels are. The preview sits in
-- Ellesmere's options panel, where a lower strata would be behind the panel:
-- there the same strata, one level below.
local function Behind(win, f)
    if rings[win].panel then
        f:SetFrameStrata(win:GetFrameStrata())
        f:SetFrameLevel(math.max(0, win:GetFrameLevel() - 1))
    else
        f:SetFrameStrata(STRATA[math.max(1, (STRATA_INDEX[win:GetFrameStrata()] or 3) - 1)])
    end
end

-- One box: background behind the window, border on top.
local function DrawBox(win, bg, edge, color, alpha, border, header)
    local strata = win:GetFrameStrata()
    Behind(win, bg)
    edge:SetFrameStrata(strata)
    edge:SetFrameLevel(win:GetFrameLevel() + EDGE_LEVEL)
    local cr, cg, cb = ns.HexToRGB(color)
    if header then
        ns.PaintHeader(bg.tex, cr, cg, cb, alpha)       -- the Global Header Texture
    else
        bg.tex:SetColorTexture(cr, cg, cb, alpha)
    end
    ns.Border.Apply(edge, border)
    bg:Show()
    edge:Show()
end

-- Header Seam: a line of our border across the join between Ellesmere's
-- header and its rows, edge to edge of our box. Its own frame above the box's
-- border, so the line's ends lie over the side borders as on Ellesmere's unit
-- frames.
local function DrawSeam(win, r, seamH, lx, rx, cfg)
    if not seamH then
        if r.seam then r.seam:Hide() end
        return
    end
    if not r.seam then
        r.seam = CreateFrame("Frame", nil, win)
        r.seam:EnableMouse(false)
        r.seam.tex = r.seam:CreateTexture(nil, "OVERLAY")
    end
    r.seam:SetFrameStrata(win:GetFrameStrata())
    r.seam:SetFrameLevel(win:GetFrameLevel() + EDGE_LEVEL + 2)
    r.seam:ClearAllPoints()
    r.seam:SetPoint("TOPLEFT", win, "TOPLEFT", lx, -seamH)
    r.seam:SetPoint("TOPRIGHT", win, "TOPRIGHT", rx, -seamH)
    r.seam:SetHeight(1)
    r.seam:Show()
    return ns.Border.Seam(r.seam.tex, r.seam, cfg.border)
end

-- The seam down the join with the next window of a row (Joins): `key` names
-- the frame on the ring (vseam for the bar box or the joined box, hvseam
-- for a header box apart, or the part above the Header Seam), from `top`
-- to `bottom` (offsets from the window's top, and from its bottom unless
-- bottomFromTop) at `rx` right of the window. Above the border and the
-- Header Seam. nil top hides it.
local function DrawSeamV(win, r, key, rx, top, bottom, bottomFromTop, cfg)
    local f = r[key]
    if not top then
        if f then f:Hide() end
        return
    end
    if not f then
        f = CreateFrame("Frame", nil, win)
        f:EnableMouse(false)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        r[key] = f
    end
    f:SetFrameStrata(win:GetFrameStrata())
    f:SetFrameLevel(win:GetFrameLevel() + EDGE_LEVEL + 3)
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", win, "TOPRIGHT", rx, top)
    f:SetPoint("BOTTOMRIGHT", win, bottomFromTop and "TOPRIGHT" or "BOTTOMRIGHT", rx, bottom)
    f:SetWidth(1)
    f:Show()
    ns.Border.SeamV(f.tex, f, cfg.border)
end

-- A row's border spans windows that may have other frame levels: it lies
-- above the highest (Joins), and the border redraws on the new level.
local function RaiseEdge(edge, join, cfg)
    edge:SetFrameLevel(join.level + EDGE_LEVEL)
    ns.Border.Apply(edge, cfg.border)
end

-- cfg = modules.damageMeter.damage, read at call time. headerH =
-- Ellesmere's Header Height for this window (EllesmereUI look), else nil:
-- then a plain box round the window. join (Joins): the window is in a row
-- of windows side by side; its boxes reach to the joins (lx, rx), the
-- row's first window draws the one border round the whole row (to
-- join.last), the others none, and each join gets a seam.
local function DrawRing(win, cfg, headerH, join)
    local r = Ring(win)
    local pad = ns.Ellesmere.Pixels(cfg.padding)
    local lx, rx = join and join.lx or -pad, join and join.rx or pad
    local edgeWin = join and join.last or win
    local drawEdge = not join or join.first
    -- Body box top: the window's top plus padding, or with the header box
    -- the padding above the first row (rows start at headerH).
    local top = pad
    local topPad = TopPadding(cfg)
    local over = headerH and HeaderGap(cfg) + topPad
    -- Ellesmere's header can be shorter than gap and padding twice over when
    -- another profile's values were never written into it (no rewrite at
    -- login): then no header box, and the body box starts at the window's top.
    if headerH and headerH - 2 * over < 1 then headerH = nil end
    local edgeTop, seamH
    if headerH then
        top = -(headerH - topPad)
        -- Header box: centred in Ellesmere's header, like its title and
        -- buttons; the window's width plus padding, as the body box. Drawn
        -- from Ellesmere's current value, so it stays round the title even
        -- before a reload has applied a new height.
        HeaderBox(win, r)
        r.hbg:ClearAllPoints()
        r.hbg:SetPoint("TOPLEFT", win, "TOPLEFT", lx, -over)
        r.hbg:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", rx, -(headerH - over))
        r.hedge:ClearAllPoints()
        r.hedge:SetPoint("TOPLEFT", win, "TOPLEFT", lx, -over)
        r.hedge:SetPoint("BOTTOMRIGHT", edgeWin, "TOPRIGHT", pad, -(headerH - over))
        -- Both values into locals: a call in the middle of an argument list
        -- gives only its first value.
        local hd = cfg.header
        local hHex, hA = ns.BackgroundColor(DB().useGlobalBackground, "headerBackground",
            hd.bgColor, tonumber(hd.bgAlpha) or 1)
        DrawBox(win, r.hbg, r.hedge, hHex, hA, cfg.border, true)
        if not drawEdge then r.hedge:Hide() elseif join then RaiseEdge(r.hedge, join, cfg) end
        if cfg.seam then
            -- Joined: one border round header and bars, the seam line where
            -- they meet; Padding stays between the seam and the first row.
            r.hedge:Hide()
            edgeTop = -over
            seamH = headerH - over
        end
    else
        HideHeaderBox(r)
    end
    r.bg:ClearAllPoints()
    r.bg:SetPoint("TOPLEFT", win, "TOPLEFT", lx, top)
    r.bg:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", rx, -pad)
    r.edge:ClearAllPoints()
    r.edge:SetPoint("TOPLEFT", win, "TOPLEFT", lx, edgeTop or top)
    r.edge:SetPoint("BOTTOMRIGHT", edgeWin, "BOTTOMRIGHT", pad, -pad)
    local hex, a = ns.BackgroundColor(DB().useGlobalBackground, "background",
        cfg.bgColor, tonumber(cfg.bgAlpha) or 0.75)
    DrawBox(win, r.bg, r.edge, hex, a, cfg.border)
    if not drawEdge then r.edge:Hide() elseif join then RaiseEdge(r.edge, join, cfg) end
    local crossed, raise, thick = DrawSeam(win, r, seamH, lx, rx, cfg)
    -- The seams down the join on this window's right: one through each box
    -- when the header box is apart. Across the Header Seam two pieces, one
    -- ending at the top of its line and one starting under it, both above it,
    -- so the lines meet in a cross (one piece's dark edges would cut the Header
    -- Seam's line). Without a Header Seam line one piece through the box.
    local inner = join and join.seamRight
    if inner and crossed then
        -- The Header Seam's line: Ellesmere's pixel seam art has it in
        -- texels 4-6 of 32 (measured), laid `raise` above the join; solid is
        -- the `raise` just above the join. At least one pixel, on pixels.
        local lineTop, lineBottom = -seamH + raise, -seamH
        if thick then lineTop, lineBottom = -seamH + raise - thick * 4 / 32, -seamH + raise - thick * 6 / 32 end
        local u, wt = ns.Ellesmere.PixelUnit(win), win:GetTop() or 0
        lineTop = ns.Border.Snap(wt + lineTop, u) - wt
        lineBottom = math.min(ns.Border.Snap(wt + lineBottom, u) - wt, lineTop - u)
        DrawSeamV(win, r, "hvseam", rx, edgeTop, lineTop, true, cfg)
        DrawSeamV(win, r, "vseam", rx, lineBottom, -pad, false, cfg)
    else
        DrawSeamV(win, r, "vseam", rx, inner and (edgeTop or top), -pad, false, cfg)
        local apart = inner and headerH and not cfg.seam
        DrawSeamV(win, r, "hvseam", rx, apart and -over, apart and -(headerH - over), true, cfg)
    end
    for _, k in ipairs({ "seam", "vseam", "hvseam" }) do
        if join and r[k] and r[k]:IsShown() then
            r[k]:SetFrameLevel(join.level + EDGE_LEVEL + (k == "seam" and 2 or 3))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Test bars: fake rows in Ellesmere's look, in a frame of ours over the
-- window's row area. Nothing in Ellesmere or C_DamageMeter is touched.
-- Ends on combat, on switching it off and on /reload.
-- ---------------------------------------------------------------------------

-- WoW Forever has the classic classes (Inferred: Classic content).
local TEST_ROWS = {
    { "Warrior", "WARRIOR" }, { "Mage", "MAGE" }, { "Rogue", "ROGUE" },
    { "Hunter", "HUNTER" }, { "Warlock", "WARLOCK" }, { "Priest", "PRIEST" },
    { "Druid", "DRUID" }, { "Shaman", "SHAMAN" }, { "Paladin", "PALADIN" },
}
local TEST_SECONDS = 60

local function TestRow(t, i)
    local row = t.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, t)
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetMinMaxValues(0, 1)
    -- Text above the fill, as Ellesmere's rows.
    local tf = CreateFrame("Frame", nil, row.fill)
    tf:SetAllPoints(row.fill)
    tf:SetFrameLevel(row.fill:GetFrameLevel() + 2)
    row.pos = ns.Media.FontString(tf)
    row.pos:SetPoint("LEFT", tf, "LEFT", 3, 0)
    row.label = ns.Media.FontString(tf)
    row.label:SetPoint("LEFT", row.pos, "RIGHT", 2, 0)
    row.label:SetPoint("RIGHT", tf, "RIGHT", -70, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.amount = ns.Media.FontString(tf)
    row.amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
    row.amount:SetJustifyH("RIGHT")
    t.rows[i] = row
    return row
end

local function DrawTestBars(win, style)
    local r = Ring(win)
    if not r.test then
        r.test = CreateFrame("Frame", nil, win)
        r.test:EnableMouse(false)
        r.test:SetClipsChildren(true)       -- rows past the window's bottom are cut, as in a scroll frame
        r.test.rows = {}
    end
    local t = r.test
    t:SetFrameLevel(win:GetFrameLevel() + TEST_LEVEL)
    t:ClearAllPoints()
    -- Ellesmere's rows start under the header. Assumed: the EllesmereUI look;
    -- the Blizzard and Classic looks add an inset.
    t:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -style.headerH)
    t:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

    local stride = style.barH + style.barSp
    local top = 0
    for i, data in ipairs(TEST_ROWS) do
        local row = TestRow(t, i)
        local name, class = data[1], data[2]
        local total = math.floor(2400000 * (1 - (i - 1) * 0.09))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -top)
        row:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, -top)
        row:SetHeight(style.barH)
        top = top + stride

        local cr, cg, cb = ns.Ellesmere.ClassColor(class)
        if style.trackClass then
            row.track:SetColorTexture(cr, cg, cb, style.trackA)
        else
            row.track:SetColorTexture(style.trackR, style.trackG, style.trackB, style.trackA)
        end
        -- Ellesmere's Icon Style.
        local iconW = 0
        if ns.Ellesmere.DMClassIcon(row.icon, class, style.iconStyle, style.iconZoom) then
            iconW = style.barH
            row.icon:SetSize(iconW, iconW)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        row.fill:ClearAllPoints()
        row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", iconW, 0)
        row.fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.fill:SetStatusBarTexture(style.texture)
        row.fill:SetAlpha(style.fillAlpha)
        row.fill:SetValue(total / 2400000)
        if style.classColor then
            row.fill:SetStatusBarColor(cr, cg, cb)
        else
            row.fill:SetStatusBarColor(style.barR, style.barG, style.barB)
        end
        ns.Ellesmere.DMRowBorder(row, row.fill, row.icon, style)

        -- Text offsets as Ellesmere's ApplyTextOffsets.
        row.pos:SetPoint("LEFT", row.pos:GetParent(), "LEFT", 3 + style.leftX, style.leftY)
        row.label:SetPoint("RIGHT", row.label:GetParent(), "RIGHT", -70, style.leftY)
        row.amount:SetPoint("RIGHT", row.amount:GetParent(), "RIGHT", -3 + style.rightX, style.rightY)
        ns.Ellesmere.DMFont(row.pos, style.leftSize)
        ns.Ellesmere.DMFont(row.label, style.leftSize)
        ns.Ellesmere.DMFont(row.amount, style.rightSize)
        row.pos:SetText(style.hideNumbers and "" or (i .. "."))
        row.label:SetText(name)
        row.amount:SetText(ns.Ellesmere.Abbreviate(total) .. " (" .. ns.Ellesmere.Abbreviate(total / TEST_SECONDS) .. ")")
        if style.leftClass then
            row.pos:SetTextColor(cr, cg, cb); row.label:SetTextColor(cr, cg, cb)
        else
            row.pos:SetTextColor(style.leftR, style.leftG, style.leftB)
            row.label:SetTextColor(style.leftR, style.leftG, style.leftB)
        end
        if style.rightClass then
            row.amount:SetTextColor(cr, cg, cb)
        else
            row.amount:SetTextColor(style.rightR, style.rightG, style.rightB)
        end
        row:Show()
    end
    t:Show()
end

local function HideTestBars()
    for win, r in pairs(rings) do
        if r.test and win ~= preview then r.test:Hide() end     -- the preview keeps its rows
    end
end

local function StopTest(reason)
    if not testing then return end
    testing = false
    if host then host:UnregisterEvent("PLAYER_REGEN_DISABLED") end
    HideTestBars()
    if reason then ns.Print("damage meter test bars off (" .. reason .. ").") end
end

-- ---------------------------------------------------------------------------
-- Preview: a window of ours with a fake header and the test rows, built from
-- the same Ellesmere settings as its windows, so a value written from our
-- page shows before the reload that puts it into Ellesmere's windows. It
-- sits in the page's fixed content header: the page sets that header when
-- built, as Ellesmere's own preview pages do, and getHeaderBuilder hands the
-- same builder back for Ellesmere's page cache. Ellesmere hides and stashes
-- the header with the page. DrawAll draws our boxes round it as round a real
-- window. Nothing protected.
-- ---------------------------------------------------------------------------

local PREVIEW_ROWS = 5
local PREVIEW_TITLE = "Damage Done (0:06)"
local PREVIEW_BUTTONS = 5   -- Ellesmere's header buttons
local BUTTON_PAD = -2       -- their gap: the glyphs overlap 2 px
local building = false      -- inside the header builder: Ellesmere takes the height we return
local previewH = 0          -- the header height the preview needs, panel units (0 = hidden)
-- At most this much of the page's content area (686 panel units) goes to
-- the preview, so the rows stay usable; a taller preview is drawn smaller
-- than game size to fit.
local PREVIEW_MAX_H = 300

local function PreviewFrame()
    if preview then return preview end
    preview = CreateFrame("Frame", nil, UIParent)
    preview:EnableMouse(false)
    Ring(preview).panel = true
    local h = CreateFrame("Frame", nil, preview)
    h:SetPoint("TOPLEFT", preview, "TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", preview, "TOPRIGHT", 0, 0)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints(h)
    h.title = ns.Media.FontString(h)
    -- Ellesmere's header button glyphs, drawn as it draws them idle.
    h.icons = {}
    for i = 1, PREVIEW_BUTTONS do
        local t = h:CreateTexture(nil, "ARTWORK")
        t:SetDesaturated(true)
        h.icons[i] = t
    end
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    h.line:SetColorTexture(0, 0, 0, 1)
    preview.header = h
    return preview
end

-- Draws the preview in its header from the settings as they are now, or
-- hides it (module off, meter not loaded). Sets previewH; returns whether
-- the preview is shown.
local function DrawPreview()
    local parent = preview and preview:GetParent()
    if not parent then return false end
    local style = active and ns.Ellesmere.DMBarStyle()
    local c = style and ns.Ellesmere.DMSettings()
    local h = 0
    if c then
        -- The header's strata, set here because the frame was made on
        -- UIParent and is moved between Ellesmere's header and its stash.
        preview:SetFrameStrata(parent:GetFrameStrata())
        preview:SetFrameLevel(parent:GetFrameLevel() + 6)
        -- Ellesmere's panel has its own scale (Window Scale); the preview is
        -- drawn at the game's, so heights and text match the real windows.
        local scale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
        local margin = ns.Ellesmere.Pixels(DB().damage.padding) + 8     -- room for the border and the seam
        local full = style.headerH + PREVIEW_ROWS * (style.barH + style.barSp) + 2 * margin
        if full * scale > PREVIEW_MAX_H then scale = PREVIEW_MAX_H / full end
        preview:SetScale(scale)
        local win = ns.Ellesmere.DMFrames()[1]
        local width = win and win:GetWidth() or 300
        local pw = parent:GetWidth()
        if pw > 0 then width = math.min(width, (pw - 40) / scale - 2 * margin) end
        local height = style.headerH + PREVIEW_ROWS * (style.barH + style.barSp)
        preview:SetSize(width, height)
        preview:ClearAllPoints()
        preview:SetPoint("CENTER", parent, "CENTER", 0, 0)
        local hd = preview.header
        hd:SetFrameStrata(parent:GetFrameStrata())
        hd:SetHeight(style.headerH)
        hd.bg:SetColorTexture(ns.Ellesmere.DMHeaderBg())
        ns.Ellesmere.DMFont(hd.title, tonumber(c.hdrFontSize) or 11)
        hd.title:SetText(PREVIEW_TITLE)
        -- Title Position, as Ellesmere anchors its title (the Forever look's
        -- small lift is left out, Assumed).
        hd.title:ClearAllPoints()
        hd.title:SetPoint("LEFT", hd, "LEFT", 6 + (tonumber(c.hdrTextOffX) or 0), tonumber(c.hdrTextOffY) or 0)
        -- Buttons from the right edge at Icon Size, as Ellesmere's
        -- LayoutHeaderButtons.
        local size = tonumber(c.hdrIconSize) or 22
        local files, ir, ig, ib, ia = ns.Ellesmere.DMHeaderIcons()
        for i, t in ipairs(hd.icons) do
            if files[i] then
                t:SetTexture(files[i])
                t:SetVertexColor(ir, ig, ib, ia)
                t:SetSize(size, size)
                t:ClearAllPoints()
                t:SetPoint("RIGHT", hd, "RIGHT", -(size * (i - 1) + BUTTON_PAD * i + 2), 0)
                t:Show()
            else
                t:Hide()                -- Reset hidden in Ellesmere: the rest close up
            end
        end
        local line = tonumber(c.hdrBottomBorderSize) or 0
        if line > 0 then hd.line:SetHeight(line); hd.line:Show() else hd.line:Hide() end
        preview:Show()
        DrawTestBars(preview, style)
        h = (height + 2 * margin) * scale
    else
        preview:Hide()
    end
    previewH = h
    -- A size change after the build (a slider): tell the panel, as Ellesmere's
    -- own previews do.
    if not building and parent:IsShown() and math.abs(parent:GetHeight() - h) > 1 then
        ns.Ellesmere.SetContentHeaderHeight(h)
    end
    return c ~= nil
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

-- Rows of windows side by side: shown windows at the same scale whose tops
-- and bottoms line up within a pixel (Ellesmere snaps a dragged window's
-- edges and size to its nearest window), not overlapping, with at most
-- JOIN_PX pixels between our two boxes. Each join lies on a whole pixel in
-- the middle of the space between the windows. Returns window -> join
-- (DrawRing), and a key that changes when the joins do.
local JOIN_PX = 8

local function Joins(wins, cfg)
    local joins = {}
    if not cfg.joinWindows then return joins, "" end
    local pad = ns.Ellesmere.Pixels(cfg.padding)
    local shown = {}
    for _, w in ipairs(wins) do
        if w:IsVisible() and w:GetLeft() then shown[#shown + 1] = w end
    end
    local right, left = {}, {}
    for _, a in ipairs(shown) do
        local u, es = ns.Ellesmere.PixelUnit(a), a:GetEffectiveScale()
        local best, bestGap
        for _, b in ipairs(shown) do
            local gap = b ~= a and b:GetLeft() - a:GetRight()
            if gap and math.abs(b:GetEffectiveScale() - es) < 0.001
                and math.abs(b:GetTop() - a:GetTop()) <= u and math.abs(b:GetBottom() - a:GetBottom()) <= u
                and gap >= -u and gap - 2 * pad <= JOIN_PX * u and (not best or gap < bestGap) then
                best, bestGap = b, gap
            end
        end
        -- Two windows on the same right neighbour overlap each other: the
        -- first keeps it.
        if best and not left[best] then right[a], left[best] = best, a end
    end
    local key = {}
    for _, w in ipairs(shown) do
        if right[w] and not left[w] then
            local row = { w }
            while right[row[#row]] do row[#row + 1] = right[row[#row]] end
            -- The row's border and seams lie above every window in it.
            local level = 0
            for _, c in ipairs(row) do level = math.max(level, c:GetFrameLevel()) end
            local mids = {}
            for i = 1, #row - 1 do
                local a, b = row[i], row[i + 1]
                mids[i] = ns.Border.Snap((a:GetRight() + b:GetLeft()) / 2, ns.Ellesmere.PixelUnit(a))
            end
            for i, c in ipairs(row) do
                local j = { first = i == 1, last = row[#row], lx = -pad, rx = pad, seamRight = i < #row, level = level }
                if i > 1 then j.lx = mids[i - 1] - c:GetLeft() end
                if i < #row then j.rx = mids[i] - c:GetRight() end
                joins[c] = j
                key[#key + 1] = ("%s:%.2f:%.2f"):format(tostring(c), j.lx, j.rx)
            end
        end
    end
    return joins, table.concat(key, ";")
end
local joinKey = ""          -- the joins DrawAll last drew (runtime only)
M.Joins = Joins             -- for the simulator's tests
M.DrawRing = DrawRing
M.Rings = function() return rings end

local function DrawAll()
    local d = DB()
    local style = testing and ns.Ellesmere.DMBarStyle()
    -- The stock looks add a rail to the header and draw their own art, so the
    -- header box is for the EllesmereUI look only.
    local headerH = not ns.Ellesmere.DMStockStyle() and ns.Ellesmere.DMHeaderHeight() or nil
    local seen = {}
    local wins = LiveWindows()
    local joins
    joins, joinKey = Joins(wins, d.damage)
    for _, win in ipairs(wins) do
        seen[win] = true
        DrawRing(win, d.damage, headerH, joins[win])
        if style then DrawTestBars(win, style) elseif rings[win].test then rings[win].test:Hide() end
    end
    if DrawPreview() then
        seen[preview] = true
        DrawRing(preview, d.damage, headerH)
    end
    -- A window Ellesmere closed (no parent any more) keeps its frame but not
    -- ours.
    for win, r in pairs(rings) do
        if not seen[win] then
            r.bg:Hide(); r.edge:Hide(); HideHeaderBox(r)
            if r.vseam then r.vseam:Hide() end
            if r.test then r.test:Hide() end
        end
    end
end

local function HideAll()
    for _, r in pairs(rings) do
        r.bg:Hide(); r.edge:Hide(); HideHeaderBox(r)
        if r.vseam then r.vseam:Hide() end
        if r.test then r.test:Hide() end
    end
end

-- Ellesmere builds its windows one per frame after its PLAYER_LOGIN (a
-- C_Timer.After(0) chain), after our PLAYER_ENTERING_WORLD draw, and rebuilds
-- them the same way on its profile, spec and condition switches. Its plugin
-- rules forbid hooking its functions, so a short OnUpdate on our own host
-- watches the windows after PLAYER_ENTERING_WORLD, after one of our frames
-- hides with its window, and after a mouse click on a window. It redraws
-- when a live window has no frame of ours or the rows of joined windows
-- change, and stops once every window Ellesmere builds (windowCount) has
-- one, or after WAIT_MAX seconds (the meter disabled, a window merely
-- hidden, a build that never finished). A click's watch is CLICK_WAIT
-- short, or with the meter off every click would run it WAIT_MAX seconds.
local WAIT_MAX = 5
local waited = 0
local waitMax = WAIT_MAX
local waitMin = 0
local ticks, ticksMin = 0, 0
-- A click's watch: a dragged or resized window gets its last position from
-- Ellesmere's own OnUpdate after the button is released, maybe after our
-- first tick, and Ellesmere re-applies positions 0.25 s after a drag, so
-- the joins are checked for CLICK_WAIT and at least CLICK_TICKS frames (at
-- a low frame rate one tick is longer than CLICK_WAIT).
local CLICK_WAIT = 0.4
local CLICK_TICKS = 3

local function WatchWindows(self, elapsed)
    waited = waited + elapsed
    ticks = ticks + 1
    local wins = LiveWindows()
    local missing = false
    for _, win in ipairs(wins) do
        if not rings[win] or not rings[win].bg:IsShown() then missing = true break end
    end
    -- A window moved, resized, shown or hidden next to another changes the
    -- rows of joined windows.
    if active and not missing and select(2, Joins(wins, DB().damage)) ~= joinKey then missing = true end
    if missing and active then
        xpcall(DrawAll, ns.ErrorHandler("damageMeter:windowBuilt"))
    end
    -- A window merely hidden (Ellesmere's visibility rules) keeps our frame,
    -- so the first tick ends the watch, except a click's (StartWatch).
    if (#wins >= ns.Ellesmere.DMWindowCount() and not missing and waited >= waitMin and ticks >= ticksMin) or (waited > waitMax and ticks >= ticksMin) or not active then
        self:SetScript("OnUpdate", nil)
    end
end

-- In combat only a click on a window we frame, or just outside one (a resize
-- ends at its edge), starts the watch, so clicks on the action bars cost
-- nothing. New Window is the "+" in window 1's header, inside the window.
-- Out of combat every click still does: Ellesmere's unlock mode moves and
-- sizes windows from clicks elsewhere, and it cannot start in combat. Our
-- own frames' table, so a click allocates nothing.
local CLICK_MARGIN = 16
function MouseOnWindow()
    for win in pairs(rings) do
        if win ~= preview and win:GetParent() and win:IsVisible()
            and win:IsMouseOver(CLICK_MARGIN, -CLICK_MARGIN, -CLICK_MARGIN, CLICK_MARGIN) then
            return true
        end
    end
    return false
end

-- maxWait: seconds, WAIT_MAX when nil; 0 is a click's watch (CLICK_WAIT).
-- A click during a running watch makes that one last at least as long, and
-- never cuts it short (a rebuild Ellesmere is still doing).
StartWatch = function(maxWait)
    if not (active and host) then return end
    local click = maxWait == 0
    if click and host:GetScript("OnUpdate") then
        waitMin = math.max(waitMin, waited + CLICK_WAIT)
        waitMax = math.max(waitMax, waited + CLICK_WAIT)
        ticksMin = math.max(ticksMin, ticks + CLICK_TICKS)
        return
    end
    waited, ticks = 0, 0
    waitMin = click and CLICK_WAIT or 0
    waitMax = click and CLICK_WAIT or maxWait or WAIT_MAX
    ticksMin = click and CLICK_TICKS or 0
    host:SetScript("OnUpdate", WatchWindows)
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        StopTest("combat")
    else
        -- Entering the world (login, reload, zoning).
        DrawAll()
        if #LiveWindows() < ns.Ellesmere.DMWindowCount() then StartWatch() end
    end
end

-- Ellesmere reads its damage meter values when it builds its windows, and
-- only its own code rebuilds them, so a value written from our page shows in
-- its windows after a reload. Instead of a reload per change: the preview
-- shows the written values at once, the page has one "Reload to Apply"
-- button, and one reminder popup comes when Ellesmere's menu closes with
-- values still unapplied. Cancel keeps the values and prints a line.
local unapplied = false      -- Ellesmere values written since the last reload
local asked = false          -- the popup came once for these values
local function AskReload()
    if not unapplied or asked or ns.Ellesmere.MenuShown() then return end
    asked = true
    ns.Ellesmere.Confirm({
        title = "Damage Meter",
        message = "Ellesmere's damage meter takes the changed values after a reload.",
        confirmText = "Reload",
        reload = true,
        onCancel = function() ns.Print("damage meter: type /reload when you want Ellesmere's values to apply.") end,
    })
end

-- Call after writing one of Ellesmere's damage meter values.
local function Pending()
    unapplied = true
    asked = false
    ns.Ellesmere.OnMenuClosed(AskReload)        -- registered once
    AskReload()                                 -- menu already closed: ask now
end

-- The same, from the page: the preview follows at once. `asking`: the
-- caller asks for the reload itself (the module toggle's popup; a profile
-- switch, copy or import that changed other addons' values), so ours would
-- be a second one; Reload to Apply still goes live.
local function Changed(asking)
    local flip = not unapplied
    if asking then
        unapplied = true
        asked = true
    else
        Pending()
    end
    DrawAll()
    if flip then ns.Ellesmere.RefreshPage() end  -- Reload to Apply goes live
end

local function RedrawIfActive()
    if active then DrawAll() end
end

function M:Enable()
    active = true
    -- Threat Meter values that older profiles still own go back to Ellesmere;
    -- nothing once they are gone.
    ns.GiveBackOwned("damageMeter", "DM", "threatMeter")
    -- Ellesmere rebuilds its windows on its own profile switch and restyles
    -- them while its Damage Meters page is edited; both happen in its menu,
    -- so the frame catches up when the menu closes (a public registration,
    -- not a hook; registered once, gated here).
    ns.Ellesmere.OnMenuClosed(RedrawIfActive)
    if not host then
        host = CreateFrame("Frame")
        host:SetScript("OnEvent", function(_, event)
            -- A mouse click: no closure for it, only the short watch.
            if event == "GLOBAL_MOUSE_UP" then
                if not InCombatLockdown() or MouseOnWindow() then StartWatch(0) end
                return
            end
            xpcall(function() OnEvent(_, event) end, ns.ErrorHandler("damageMeter:" .. event))
        end)
    end
    host:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Ellesmere's New Window button (the "+" in window 1's header) builds a
    -- window at once in its click handler, and nothing we may listen to says
    -- so: no event, and hooking its functions or pages is against its plugin
    -- rules. So a mouse click on a window (MouseOnWindow) starts the watch
    -- above for a few frames, from the next frame, after the click handler.
    -- FIELD RESULT 2026-10-10 (build 70338): without this the new window had
    -- no frame until a /reload. With it a new window got its frame at once,
    -- but not after a window had been closed: the new one is not reachable by
    -- its name then (ns.Ellesmere.DMFrames searches for it).
    host:RegisterEvent("GLOBAL_MOUSE_UP")
end

-- M:Apply runs in combat too: none of these frames is protected (Ellesmere's
-- windows are plain frames). When our header sizes changed without a write
-- (see WriteHeaderOwned) it writes them once. At login Ellesmere builds its
-- windows after this and reads the new value itself, so a reload is pending
-- only when a window already exists.
-- Compared to a hundredth: the total is in UI units from pixels, and a float
-- saved and read back need not be equal to the last bit, which would write
-- Ellesmere's Header Height again at every login, over one set in its menu.
local function HeaderChanged()
    local written = tonumber(DB().damage.headerWritten)
    return not written or math.abs(written - HeaderTotal()) > 0.01
end

function M:Apply()
    if active and HeaderUsed() and HeaderChanged() then
        WriteHeaderOwned()
        if ns.Ellesmere.DMFrames()[1] then Pending() end
    end
    DrawAll()
end

function M:Disable()
    active = false
    local a = RestoreOwned()
    local b = RestoreHeaderOwned()
    DB().damage.headerWritten = nil     -- given back: on again writes it anew
    if a or b then Pending() end    -- Ellesmere's own background and border come back
    DrawPreview()                   -- hidden; the page's header closes up
    if not host then return end
    StopTest()
    host:UnregisterAllEvents()
    host:SetScript("OnUpdate", nil)
    HideAll()
end

local function WriteAllOwned()
    WriteOwned()
    WriteHeaderOwned()
end

-- A profile from before the global background keeps its own colours.
function M:KeepOwnBackgrounds(cfg)
    if cfg.useGlobalBackground == nil then cfg.useGlobalBackground = false end
end

function M:SwitchedOn()
    WriteAllOwned()
    Changed(true)
end

-- A profile switch, copy or import with the module on in both profiles: the
-- new profile's header sizes go into Ellesmere's Header Height. A switch
-- asks for its reload itself.
function M:ProfileSwitched()
    WriteHeaderOwned()
    Changed(true)
end

-- Redraws the preview with everything else, or hides it when the module is off.
local function Redraw()
    if active then DrawAll() else DrawPreview() end
end

-- The preview's header builder: (header, width) -> height. One function, so
-- Ellesmere keeps one identity for it.
local function PreviewHeader(header)
    PreviewFrame():SetParent(header)
    -- Opening the panel again: its scale (Window Scale) and the values may
    -- have changed while it was closed.
    ns.Ellesmere.OnMenuShown(Redraw)
    building = true
    local ok = xpcall(Redraw, ns.ErrorHandler("damageMeter:previewHeader"))
    building = false
    return ok and previewH or 0
end

-- For Ellesmere's getHeaderBuilder.
function M:GetHeaderBuilder(pageName)
    if pageName == "Damage Meter" then return PreviewHeader end
    return nil
end

-- Ellesmere shows the cached page again (onPageCacheRestore, after it has
-- put the header back): values changed on Ellesmere's own page meanwhile
-- show, and the header gets the height they need.
function M:PageShown(pageName)
    if pageName == "Damage Meter" then xpcall(Redraw, ns.ErrorHandler("damageMeter:pageShown")) end
end

-- ---------------------------------------------------------------------------
-- Settings pages
-- ---------------------------------------------------------------------------

local function OwnedRows(W, parent, y)
    local _, h
    _, h = W:SectionHeader(parent, "ELLESMERE SETTINGS", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Puts the Prosecco look into Ellesmere's meter." },
        { type = "button", text = "Set Ellesmere Values", width = 180,
          disabled = function() return not ns.IsModuleEnabled("damageMeter") end,
          disabledTooltip = "This option needs Damage Meter turned on.",
          onClick = function()
              ns.Ellesmere.Confirm({
                  title = "Damage Meter: set Ellesmere values",
                  message = "Write ProseccoAdditions' values into Ellesmere's damage meter again?\n"
                      .. "- Background Opacity and Window Border Size 0\n"
                      .. "- Header Height, header opacity and header bottom border for the header box\n"
                      .. "- the Prosecco look: bars, bar border, bar text, icons and header text ("
                      .. #LOOK .. " values)\nThe values from before come back when Damage Meter is turned off.",
                  confirmText = "Set",
                  onConfirm = function() WriteAllOwned(); Changed() end,
              })
          end }); y = y - h
    return y
end

local function FrameRows(W, parent, y, which)
    local _, h
    local function C() return DB()[which] end
    local function changed() ns.Apply() end
    _, h = W:SectionHeader(parent, "BACKGROUND AND PADDING", y); y = y - h
    local function follows() return DB().useGlobalBackground == true end
    _, h = W:DualRow(parent, y, ns.UseGlobalBackgroundCell(DB, changed), { type = "label", text = "" }); y = y - h
    y = ns.Rows(W, parent, y,
        ns.BackgroundCell({ text = "Background", cfg = C, colorKey = "bgColor", alphaKey = "bgAlpha", default = 0.75,
          follows = follows, onChange = changed,
          tooltip = "Replaces Ellesmere's window background, which this module sets to 0." }),
        { type = "slider", text = "Padding", min = 0, max = 32, step = 1,
          tooltip = "Pixels between Ellesmere's window and the border, and between the top of the bar box and the first bar. The space between bars is Ellesmere's Bar Spacing.",
          getValue = function() return tonumber(C().padding) or 0 end,
          setValue = function(v)
              if v == C().padding then return end
              C().padding = v
              -- The padding is in Ellesmere's Header Height too.
              if ns.IsModuleEnabled("damageMeter") and HeaderUsed() then
                  WriteHeaderOwned()
                  changed()
                  Changed()
              else
                  changed()
              end
          end })
    _, h = W:SectionHeader(parent, "BORDER", y); y = y - h
    y = ns.Border.Rows(W, parent, y, function() return C().border end, changed)
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Join Side by Side",
          tooltip = "Windows placed side by side, with tops and bottoms in line, share one border with a seam where they meet (the Pixels styles draw their seam art, Solid a plain line, other textured styles none). Drag a window next to another; Ellesmere snaps it into line.",
          getValue = function() return C().joinWindows ~= false end,
          setValue = function(v) C().joinWindows = v and true or false; changed() end },
        { type = "spacer" }); y = y - h
    return y
end

local function HeaderOff()
    return not ns.IsModuleEnabled("damageMeter") or not HeaderUsed()
end
local HEADER_OFF_TIP = "This option needs Damage Meter on and Ellesmere's damage meter in the EllesmereUI style."

-- Our own header sizes: Header Height and Gap go into Ellesmere's Header
-- Height with the padding (HeaderOwned).
local function SizeCell(text, key, minV, maxV, tip)
    local function HD() return DB().damage.header end
    return { type = "slider", text = text, min = minV, max = maxV, step = 1, tooltip = tip,
        disabled = function() return HeaderOff() or key == "gap" and DB().damage.seam == true end,
        disabledTooltip = key == "gap" and (HEADER_OFF_TIP .. " Header Gap is not used with Header Seam on.") or HEADER_OFF_TIP,
        getValue = function() return tonumber(HD()[key]) or 0 end,
        setValue = function(v)
            if v == HD()[key] then return end
            HD()[key] = v
            WriteHeaderOwned()
            ns.Apply()                  -- our boxes follow at once; Ellesmere's header after the reload
            Changed()
        end }
end

-- The header box is always on: Header Seam joins it to the bar box with a
-- line, off leaves Header Gap between them.
local function HeaderRows(W, parent, y)
    local _, h
    local function HD() return DB().damage.header end
    _, h = W:SectionHeader(parent, "HEADER", y); y = y - h
    y = ns.Rows(W, parent, y,
        { type = "toggle", text = "Header Seam",
          tooltip = "On: one border round the header box and the bar box, with a line of the border where they meet, like Ellesmere's Power Bar Seam (the Pixels styles draw their seam art, Solid a plain line, other textured styles none). Off: two boxes with Header Gap between them.",
          disabled = HeaderOff, disabledTooltip = HEADER_OFF_TIP,
          getValue = function() return DB().damage.seam == true end,
          setValue = function(v)
              v = v and true or false
              DB().damage.seam = v
              -- The gap goes away (or comes back) in Ellesmere's Header
              -- Height; written before ns.Apply, which would write it too.
              local gapChanged = (tonumber(HD().gap) or 0) ~= 0
              if gapChanged then WriteHeaderOwned() end
              ns.Apply()
              ns.Ellesmere.RefreshPage()      -- Header Gap greys in or out
              if gapChanged then Changed() end
          end },
        ns.BackgroundCell({ text = "Header Background", cfg = HD, colorKey = "bgColor", alphaKey = "bgAlpha", default = 1,
          follows = function() return DB().useGlobalBackground == true end,
          onChange = function() ns.Apply() end,
          disabled = HeaderOff, disabledTooltip = HEADER_OFF_TIP }))
    _, h = W:DualRow(parent, y,
        SizeCell("Header Height", "height", 14, 40, "Height of the header box."),
        SizeCell("Header Gap", "gap", 0, 20, "Space between the header box and the bar box. Not used with Header Seam on.")); y = y - h
    return y
end

-- The PREVIEW section: the preview itself is the fixed header above the
-- rows (PreviewHeader); this row holds the reload that puts Ellesmere's
-- values into its windows.
local function ReloadRows(W, parent, y)
    local _, h
    _, h = W:SectionHeader(parent, "PREVIEW", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Reload to Apply", width = 180,
          tooltip = "Ellesmere reads its damage meter values at a reload. The preview above shows them at once; ProseccoAdditions' own settings apply at once.",
          disabled = function() return not unapplied end,
          disabledTooltip = "This option is for after a change: nothing has changed since the last reload.",
          onClick = function()
              ns.Ellesmere.Confirm({
                  title = "Damage Meter",
                  message = "Reload now so Ellesmere's damage meter takes the changed values?",
                  confirmText = "Reload",
                  reload = true,
              })
          end },
        { type = "label", text = "Ellesmere's values need a reload; the preview shows them now." }); y = y - h
    return y
end

-- One page. Ellesmere's own meter values are not shown here; Set Ellesmere
-- Values sets them to the Prosecco look.
function M:BuildPage(pageName, parent, y, W)
    local _, h
    local on = ns.IsModuleEnabled("damageMeter")
    -- The preview header: the builder parents the frame to the header at
    -- every build. Not during the search's hidden pass.
    if not ns.Ellesmere.IsSearchPrebuild() then ns.Ellesmere.SetPageHeader(PreviewHeader) end
    -- Ellesmere's Blizzard Style and Classic WoW UI draw their own window art
    -- and ignore Window Border Size.
    if ns.Ellesmere.DMStockStyle() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Ellesmere's meter is in Blizzard or Classic style; this module is made for EllesmereUI style." }); y = y - h
    end
    y = ReloadRows(W, parent, y)
    do
        _, h = W:SectionHeader(parent, "TEST BARS", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Test Bars",
              tooltip = "Made-up rows in Ellesmere's bar style, drawn by ProseccoAdditions over every damage meter window.",
              -- Running, not just on in the profile: an Enable that failed
              -- leaves the module on without its event frame.
              disabled = function() return not active or InCombatLockdown() end,
              disabledTooltip = "This option needs Damage Meter on, out of combat.",
              getValue = function() return testing end,
              setValue = function(v)
                  if v then
                      if not ns.Ellesmere.DMBarStyle() then
                          ns.Print("Ellesmere's Damage Meters is not loaded.")
                          ns.Ellesmere.RefreshPage()      -- the toggle goes back to off
                          return
                      end
                      testing = true
                      host:RegisterEvent("PLAYER_REGEN_DISABLED")
                      DrawAll()
                  else
                      StopTest()
                  end
              end },
            { type = "label", text = "Ends in combat or on /reload. Not saved." }); y = y - h
        y = OwnedRows(W, parent, y)
        y = FrameRows(W, parent, y, "damage")
        y = HeaderRows(W, parent, y)
    end
    if not on then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Damage Meter is off: turn it on under Modules on the General page." }); y = y - h
    end
    return y
end
