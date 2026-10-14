-- ProseccoUI / Modules / RXPTheme.lua
-- A RestedXP Guides theme, "Prosecco", through RXP's theme API: colours,
-- font and flat textures of our own (RXP's art is not copied). The user
-- picks it in RXP's options; ProseccoUI never sets RXP's theme.
--
-- What a theme cannot do is done in one pass after RXP draws, only while
-- Prosecco is in use: font and outline, our backgrounds and border, header
-- and footer. RXP's spacing inside the step boxes is not written; only
-- Header Height, Header Extend, Step Gap, Scroll Bar Outside, the window
-- titles and a few frame levels move or lift RXP's frames.
--
-- Off: no frames, no hooks. Once on, the hooks stay until /reload and do
-- nothing while off. Turning it off needs a /reload.

local _, ns = ...

local THEME = "Prosecco"
local FLAT = "Interface\\Buttons\\WHITE8X8"

local M = ns.RegisterModule("rxpTheme", {
    title       = "RXP Theme",
    description = "A Prosecco theme for RestedXP Guides: colours, font, flat art and ProseccoAdditions' border.",
    pages       = { "RXP Theme", "Advanced" },
    defaults    = {
        font = "global",            -- "global" = General's, "" = Ellesmere's font
        outline = "global",         -- global | ellesmere | none | shadow | OUTLINE | THICKOUTLINE (ns.Media.Outline)
        -- Header: header, footer, step badges and the Active Targets/Items
        -- title bars. Body: step boxes and RXP's other windows. Window
        -- (winColor below): Active Targets/Items.
        headerBgColor = "000000", headerBgAlpha = 1,
        bodyColor = "000000", bodyAlpha = 0.8,
        -- The step list's own colour; an older profile takes Body's (M:Migrate).
        stepListColor = "000000", stepListAlpha = 0.8,
        stepGap = 7,                             -- px between the step boxes (RXP's own is 5 units)
        badgePadding = 4,                        -- px our badge box reaches past RXP's on each side
        headerHeight = 0,                        -- RXP's header height in its units; 0 = RXP's own (35)
        headerDrop = 2,                          -- px our header box reaches below RXP's bottom edge, list moved too
        sidePadding = 0,                         -- px all guide window boxes reach past RXP's left and right
        hideVersion = false,                     -- the version line in the footer
        footerMouseover = false,                 -- footer shown only under the mouse
        hideLogos = false,                       -- the header's logo and class icon
        centerHeader = false,                    -- guide name centred on the whole header
        rowColor = "1A1A1A", rowAlpha = 0.9,     -- the steps in the list
        rowBorder = true,                        -- a 1 px line round each step in the list
        rowBorderColor = "000000", rowBorderAlpha = 1,
        scrollOutside = true,                    -- the list's scroll bar outside the window's right edge
        scrollMouseover = false,                 -- the scroll bar shown only under the mouse
        accentColor = "4D4D4D",                  -- a list step under the mouse
        pinColor = "D9D9D9",                     -- map pins, route lines, timer bars, tooltip text
        textColor = "FFFFFF",
        border = { useGlobal = true, style = "solid", size = 1, color = "000000", alpha = 1 },
        -- The boxes take the General page's colours: Header ones the Global
        -- Header Background, the rest the Global Background (BG_KIND).
        useGlobalBackground = true,
        -- Active Targets and Active Items' frame; the title bar takes Header.
        winColor = "000000", winAlpha = 0.4,
        winPadding = 4,                          -- px our window box reaches past RXP's on each side
        winTitlePadding = 2,                     -- the same for the title box
        arrowTexture = "prosecco",               -- a key in ARROWS below
        arrowColor = "E1E1E1",                   -- tint; the arrow files are white
    },
    affects     = {
        "Adds the theme \"Prosecco\" to RestedXP Guides. Pick it in RXP's options: Look and Feel > Choose Theme.",
        "While that theme is in use, ProseccoAdditions sets the font and outline of the guide text, draws its own backgrounds and border under the guide window and step boxes, and shows RestedXP's own logo in the header. RXP's spacing inside the step boxes is not changed; Header Height makes the header taller, Header Extend moves the step list down, Scroll Bar Outside lets the step list's rows reach into the room the bar leaves, and the titles of Active Targets and Active Items are centred in a title bar.",
        "Turning it off needs a /reload; RXP then goes back to its default theme. Picking another theme in RXP also needs a /reload to get RXP's own font back.",
    },
    affectsOff  = {
        "The \"Prosecco\" theme is removed from RestedXP Guides; RXP goes back to its default theme.",
        "ProseccoAdditions' backgrounds, border and font on the guide window are removed.",
    },
    reload      = true,
})

local function DB() return ns.db.modules.rxpTheme end

local active = false        -- between Enable and Disable; gates the hooks
local lastTheme             -- what the theme was built from at the last Apply (runtime only)
local lastArrow             -- what the arrow was drawn with at the last Apply (runtime only)
local arrowTinted = false   -- our colour is on RXP's arrow now (runtime only)
local warned = false        -- "RXP not loaded" printed this session
local waiter                -- frame that waits for the end of combat (Apply)

-- ---------------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------------

local function FontPath()
    return ns.Media.FontPath(DB().font)
end

-- SetFont flags and whether the text gets a drop shadow.
local function Outline()
    return ns.Media.Outline(DB().outline)
end

local function RGBA(hex, a)
    local r, g, b = ns.HexToRGB(hex)
    return { r, g, b, a }
end

-- Which global colour each background follows with Use Global Background on.
local BG_KIND = {
    headerBgColor = "headerBackground", bodyColor = "background", winColor = "background",
    stepListColor = "background",
}

-- A background's colour and alpha as drawn: its own, or the global one.
local function Bg(colorKey, alphaKey, default)
    local d = DB()
    return ns.BackgroundColor(d.useGlobalBackground, BG_KIND[colorKey], d[colorKey],
        tonumber(d[alphaKey]) or default)
end

-- What the theme is built from. Apply runs after every settings change in
-- any module; the theme is registered again (RXP redraws and reloads its
-- guide) only when this has changed.
local function ThemeKey()
    local d = DB()
    local bg, bgA = Bg("bodyColor", "bodyAlpha", 0.8)
    return strjoin("|", FontPath(), bg, tostring(bgA), d.rowColor, tostring(d.rowAlpha),
        d.accentColor, d.pinColor, d.textColor)
end

-- A new table every time: RXP fills it in place and restyles its step boxes
-- only when the theme table changes. Every key RXP Blue has is given, so
-- none of RXP's art is filled in.
local function BuildTheme()
    local d = DB()
    local r, g, b = ns.HexToRGB(d.textColor)
    local path = ns.RXP.TEXTURE_PATH
    return {
        name = THEME,
        displayName = "Prosecco",
        author = "ProseccoAdditions",
        applicable = true,
        background = RGBA(Bg("bodyColor", "bodyAlpha", 0.8)),
        bottomFrameBG = RGBA(d.rowColor, tonumber(d.rowAlpha) or 0.9),
        bottomFrameHighlight = RGBA(d.accentColor, 1),
        mapPins = RGBA(d.pinColor, 1),
        tooltip = "|cFF" .. ns.RGBToHex(ns.HexToRGB(d.pinColor)),
        textColor = { r, g, b },
        font = FontPath(),
        texturePath = path,
        headerTexture = "rxp-banner",
        -- guideName is the header and footer: RXP Blue gives them no fill and
        -- paints them with its banner art, which ours leaves empty.
        bgTextures = { edge = FLAT, bottom = FLAT, guideName = FLAT },
        edges = { edge = path .. "rxp-borders", guideName = path .. "rxp-borders" },
    }
end

-- ---------------------------------------------------------------------------
-- The pass after RXP draws
-- ---------------------------------------------------------------------------

-- RXP frame -> our frame under it, carrying the part's background and our
-- border. Weak keys: nothing is stored on RXP's frames; ours are their
-- children so they follow RXP's show, hide and fade (RXP hides an empty step
-- box with SetAlpha(0)).
local skins = setmetatable({}, { __mode = "k" })
local footerTouched = false     -- we have hidden part of RXP's footer (runtime only)
local headerTouched = false     -- we have hidden RXP's logos or guide-name line (runtime only)
local nameLine                  -- our guide-name line on the header (CenterName below)

-- Gives RXP's footer back as RXP shows it.
local function RestoreFooter()
    if footerTouched then
        ns.RXP.SetFooter(true, true)
        footerTouched = false
    end
end

-- Gives RXP's header back as RXP shows it.
local function RestoreHeader()
    if headerTouched then
        ns.RXP.SetHeaderIcons(true)
        ns.RXP.SetHeaderTextShown(true)
        headerTouched = false
    end
    if nameLine then nameLine:Hide() end
end

local rowEdges = setmetatable({}, { __mode = "k" })    -- RXP list row -> our 1 px line round it

-- RXP's own gap between step boxes, in its units.
local RXP_STEP_GAP = 5

local function HideEdges()
    for _, f in pairs(skins) do f:Hide() end
    for _, f in pairs(rowEdges) do f:Hide() end
    ns.RXP.ShiftScrollFrame(0)
    ns.RXP.SpaceSteps(RXP_STEP_GAP, 0)
    ns.RXP.SetHeaderHeight(nil)
    ns.RXP.PlaceScrollBar(nil)
    ns.RXP.SetScrollBarAlpha(1)
    local wins, titles = ns.RXP.Windows()
    for i, w in ipairs(wins) do
        if titles[i] then ns.RXP.PlaceTitle(titles[i], w, false, 0, 0) end
    end
    RestoreFooter()
    RestoreHeader()
end

-- What GetFont returned right after our SetFont, per string: a string that
-- still reads the same was not reset by RXP, whatever form the client gives
-- the path or flags in (e.g. "OUTLINE, SLUG"), so every write is a
-- fixpoint. The wanted path and flags are kept so a settings change counts.
local gotPath = setmetatable({}, { __mode = "k" })
local gotFlags = setmetatable({}, { __mode = "k" })
local wantKey = setmetatable({}, { __mode = "k" })

-- The "shadow" outline mode (or Ellesmere's outline with its shadow) gives
-- RXP's text a black drop shadow. The string's own shadow is saved before
-- our first one and put back when the mode has no shadow.
local shadowBefore = setmetatable({}, { __mode = "k" })
local function Shadow(fs, on)
    local b = shadowBefore[fs]
    if on then
        if not b then
            local x, y = fs:GetShadowOffset()
            local r, g, bl, a = fs:GetShadowColor()
            shadowBefore[fs] = { x, y, r, g, bl, a }
        end
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    elseif b then
        fs:SetShadowOffset(b[1], b[2])
        fs:SetShadowColor(b[3], b[4], b[5], b[6])
        shadowBefore[fs] = nil
    end
end

local function Fonts()
    -- The colour too: RXP sets it only when it creates a string. It does
    -- not change sizes, so it is written every pass, outside the fixpoint.
    local tr, tg, tb = ns.HexToRGB(DB().textColor)
    local path = FontPath()
    local flags, shadow = Outline()
    local want = path .. "|" .. flags .. "|" .. tostring(shadow)
    local texts, inStep, inList, rxpColour = ns.RXP.Texts()
    local relayout, relist = false, false
    for i, fs in ipairs(texts) do
        -- List row text is skipped: RXP colours it from the theme's
        -- textColor on every guide load.
        if not rxpColour[i] then fs:SetTextColor(tr, tg, tb) end
        local cur, size, curFlags = fs:GetFont()
        -- size is nil for a string RXP has not given a font yet.
        if size and not (wantKey[fs] == want and cur == gotPath[fs] and curFlags == gotFlags[fs]) then
            fs:SetFont(path, size, flags)
            Shadow(fs, shadow)
            local p, _, f = fs:GetFont()
            gotPath[fs], gotFlags[fs], wantKey[fs] = p, f, want
            if inStep[i] then relayout = true end
            if inList[i] then relist = true end
        end
    end
    -- RXP sized the list's rows for its plain text; it sizes them again for
    -- ours on its next update.
    if relist then ns.RXP.RedrawList() end
    return relayout
end

-- Frame levels. Our frame for a part goes UNDER the part, so RXP's content
-- (text, logo, class icon, badge number) is drawn over our border. Our
-- border's lines sit at our level + 2 (Border.Apply's holder, then
-- Ellesmere's line container), so the part must be at + 3 or more.
-- From the step list's level B (RXP's scroll area is at B+1, its rows B+2):
--   step list: ours at B-2 (lines at B, under the rows);
--   header and footer, which lie over the list's edges: ours at B+4, the
--   part lifted to B+7, the footer's resize grip and cog to B+8;
--   step box at S: ours at S-3; its badge lifted to S+4, ours at S+1.
-- FIELD RESULT 2026-10-06 (0.4.0-dev3): with our border over the parts, a
-- Pixels border at 16 px covered the badge's number and the header's logo.
local PART = {
    header = { color = "headerBgColor", alpha = "headerBgAlpha" },
    footer = { color = "headerBgColor", alpha = "headerBgAlpha" },
    list   = { color = "stepListColor", alpha = "stepListAlpha" },
    step   = { color = "bodyColor",     alpha = "bodyAlpha" },
    badge  = { color = "headerBgColor", alpha = "headerBgAlpha" },
    window = { color = "winColor",      alpha = "winAlpha",      whole = true, under = true },
    wtitle = { color = "headerBgColor", alpha = "headerBgAlpha", whole = true, under = true },
}

-- The strata just below a frame's own, for `under` parts (BACKGROUND has none).
local STRATA_BELOW = {
    LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
    FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG",
}

-- `bare`: no backdrop insets and no border of ours (the docked list).
-- `whole`: no backdrop insets, our border kept (a docked step box).
local NO_BORDER = { style = "solid", size = 0, color = "000000", alpha = 1 }
local function Skin(box, k, level, grow, raise, side, drop, bare, whole)
    local f = skins[box]
    if not f then
        f = CreateFrame("Frame", nil, box)
        f:EnableMouse(false)
        f.tex = f:CreateTexture(nil, "BACKGROUND")
        f.tex:SetAllPoints(f)
        skins[box] = f
    end
    local keys = PART[k]
    -- `under`: Active Targets and Active Items. Their buttons are one level
    -- above the window, which sits low, so no level under it leaves room for
    -- both boxes and borders: one strata down, all of ours is under RXP's
    -- window, and `level` orders only ours.
    -- FIELD RESULT 2026-10-07 (build 70245): in the same strata the title's
    -- border covered the icons.
    local below = keys.under and STRATA_BELOW[box:GetFrameStrata()]
    if below then f:SetFrameStrata(below) end
    f:SetFrameLevel(math.max(0, level))
    local hex, a = Bg(keys.color, keys.alpha, 1)
    local r, g, b = ns.HexToRGB(hex)
    if keys.color == "headerBgColor" then
        ns.PaintHeader(f.tex, r, g, b, a)           -- header, footer, badge, title: the Global Header Texture
    else
        f.tex:SetColorTexture(r, g, b, a)
    end
    ns.RXP.ClearBackground(box)
    -- The part RXP paints (its frame less the backdrop insets). `grow` (the
    -- badge) makes a bigger box round RXP's number, so a thick border does
    -- not cover it and nothing of RXP's moves.
    -- `raise` moves only the top edge up: the footer's top line otherwise
    -- lies exactly on the step list's bottom line.
    -- `whole`: Active Targets and Active Items use the whole frame, since
    -- RXP's insets there are uneven (4, 2, 2, 4).
    -- FIELD RESULT 2026-10-07 (build 70245): a box that followed the insets
    -- put the centred title 1 px off centre.
    local l, r2, t, b2 = 0, 0, 0, 0
    if not (keys.whole or bare or whole) then l, r2, t, b2 = ns.RXP.Insets(box) end
    if raise and raise ~= 0 then t = t - raise * ns.Ellesmere.PixelUnit(box) end
    -- `side` moves only the left and right edges out: RXP's rows and step
    -- text reach almost to the edge, so the boxes grow instead of RXP's
    -- layout moving. `drop` moves only the bottom edge down (Header Extend);
    -- the header lies over the list, so it covers the list's top.
    if drop and drop ~= 0 then b2 = b2 - drop * ns.Ellesmere.PixelUnit(box) end
    if side and side ~= 0 then
        local u = ns.Ellesmere.PixelUnit(box)
        l, r2 = l - side * u, r2 - side * u
    end
    if ns.Border.Outside(f, box, grow or 0, l, r2, t, b2) then
        ns.Border.Apply(f, bare and NO_BORDER or DB().border)
        f:Show()
    else
        f:Hide()
    end
end

-- Header Height: 0 keeps RXP's own (35, in RXP's units). A set height never
-- cuts the guide name: at least the text plus the larger backdrop inset on
-- each side, so the name stays inside our box (the header less its insets).
local function HeaderHeight()
    local hh = tonumber(DB().headerHeight) or 0
    if hh <= 0 then return nil end
    local fs, header = ns.RXP.HeaderText()
    if not header then return nil end
    local textH = 0
    -- No font yet: RXP has not styled its window (Fonts above).
    if fs and select(2, fs:GetFont()) then textH = math.ceil(fs:GetStringHeight()) end
    local _, _, t, b = ns.RXP.Insets(header)
    return math.max(hh, textH + 2 * math.max(t, b))
end

local FOOTER_RAISE = 4      -- px our footer box reaches above RXP's top edge
local BADGE_LIFT = 2        -- px the step badges sit higher than RXP puts them
local HEADER_OVERLAP = 1    -- px our header box reaches over the list; the list does not move

local function Parts()
    -- Step Gap and the badge lift first, so the boxes below are skinned
    -- where they now are.
    local CSF = ns.RXP.StepColumn()
    if CSF then
        local u = ns.Ellesmere.PixelUnit(CSF)
        ns.RXP.SpaceSteps((tonumber(DB().stepGap) or 7) * u, BADGE_LIFT * u)
    end
    local B = ns.RXP.BaseLevel()
    local side = tonumber(DB().sidePadding) or 0
    local boxes, kind, owner = ns.RXP.Boxes()
    for i, box in ipairs(boxes) do
        local k = kind[i]
        if k == "list" and ns.RXP.IsDocked() then
            -- Docked under the Quest Tracker, the tracker's border goes round
            -- the tracker and the list: the box fills the list edge to edge,
            -- with no border or padding of its own.
            Skin(box, k, B - 2, 0, 0, 0, nil, true)
        elseif k == "list" then
            Skin(box, k, B - 2, 0, 0, side)
        elseif k == "header" then
            ns.RXP.SetLevel(box, B + 7)
            -- Before the box: it is drawn round the header as it then is.
            ns.RXP.SetHeaderHeight(HeaderHeight())
            -- Header Extend moves the list down with it; the overlap reaches
            -- over the list without moving it.
            Skin(box, k, B + 4, 0, 0, side, (tonumber(DB().headerDrop) or 0) + HEADER_OVERLAP)
        elseif k == "footer" then
            ns.RXP.SetLevel(box, B + 7)
            Skin(box, k, B + 4, 0, FOOTER_RAISE, side)
        elseif k == "step" and ns.RXP.DockedStep(box) then
            -- Docked, a step box is as wide as the list above it: the whole
            -- box with no Side Padding, so its edges line up with the border
            -- round the tracker and the list.
            Skin(box, k, box:GetFrameLevel() - 3, 0, 0, 0, nil, nil, true)
        elseif k == "step" then
            Skin(box, k, box:GetFrameLevel() - 3, 0, 0, side)
        else    -- badge
            local S = owner[i]:GetFrameLevel()
            ns.RXP.SetLevel(box, S + 4)
            Skin(box, k, S + 1, tonumber(DB().badgePadding) or 0)
        end
    end
    local sf = ns.RXP.ScrollFrame()
    if sf then ns.RXP.ShiftScrollFrame((tonumber(DB().headerDrop) or 0) * ns.Ellesmere.PixelUnit(sf)) end
    local grip, cog = ns.RXP.FooterButtons()
    ns.RXP.SetLevel(grip, B + 8)
    ns.RXP.SetLevel(cog, B + 8)
end

-- A 1 px line round each step in the guide list, on a frame of ours per row,
-- a child of the row so it follows RXP's layout, alpha and hiding. RXP keeps
-- its rows once made, so only missing ones are made. The pass runs on every
-- step-box layout and a guide has a few hundred rows, so a row is drawn
-- again only when its size, place, level or colour changed (rowDrawn).
local ROW_BORDER = { style = "solid", size = 1, color = "000000", alpha = 1 }
local rowDrawn = setmetatable({}, { __mode = "k" })     -- edge frame -> { w, h, left, top, level, colour, alpha }
local function RowBorders()
    local d = DB()
    ROW_BORDER.color, ROW_BORDER.alpha = d.rowBorderColor, tonumber(d.rowBorderAlpha) or 1
    for _, row in ipairs(ns.RXP.ListRows()) do
        local f = rowEdges[row]
        if d.rowBorder then
            if not f then
                f = CreateFrame("Frame", nil, row)
                f:EnableMouse(false)
                rowEdges[row] = f
                rowDrawn[f] = {}
            end
            local w, h, l, t, lv = row:GetWidth(), row:GetHeight(), row:GetLeft(), row:GetTop(), row:GetFrameLevel() + 1
            local s = rowDrawn[f]
            if s[1] ~= w or s[2] ~= h or s[3] ~= l or s[4] ~= t or s[5] ~= lv
                or s[6] ~= ROW_BORDER.color or s[7] ~= ROW_BORDER.alpha then
                -- On whole pixels round the part RXP paints: a row can sit on
                -- half a pixel, where a 1 px line is drawn blurred.
                if not ns.Border.Outside(f, row, 0, ns.RXP.Insets(row)) then f:SetAllPoints(row) end
                f:SetFrameLevel(lv)
                ns.Border.Apply(f, ROW_BORDER)
                s[1], s[2], s[3], s[4], s[5], s[6], s[7] = w, h, l, t, lv, ROW_BORDER.color, ROW_BORDER.alpha
            end
            f:Show()
        elseif f then
            f:Hide()
        end
    end
end

-- The list's scroll bar outside our list box on the right, 2 px from it
-- plus the border's width. With Scroll Bar on Mouseover it shows only while
-- the mouse is over the window or the bar. Docked, the dock places and shows
-- it and keeps this request for when it undocks.
local function ScrollBar()
    local d = DB()
    local sf = ns.RXP.ScrollFrame()
    local box = sf and skins[sf:GetParent()]      -- our step-list box (the scroll frame's parent is the list)
    if d.scrollOutside and box and box:IsShown() then
        -- A solid line lies inside our box, a textured one is centred on its
        -- edge, so half of it reaches out.
        local b = ns.Border.Resolve(d.border)
        local out = ns.Ellesmere.IsTexturedBorder(b.style) and (tonumber(b.size) or 0) / 2 or 0
        ns.RXP.PlaceScrollBar(box, (2 + out) * ns.Ellesmere.PixelUnit(box))
    else
        ns.RXP.PlaceScrollBar(nil)
    end
    ns.RXP.SetScrollBarAlpha((not d.scrollMouseover or ns.RXP.GuideHovered()) and 1 or 0)
end

local function OnGuideHover()
    if active and DB().scrollMouseover and ns.RXP.ActiveName() == THEME then ScrollBar() end
end

-- The footer: with Footer on Mouseover it shows only while the mouse is
-- over it; Hide Version Text keeps the version line hidden.
local function Footer()
    local d = DB()
    if not (d.hideVersion or d.footerMouseover) then
        RestoreFooter()
        return
    end
    local shown = not d.footerMouseover or ns.RXP.FooterHovered()
    ns.RXP.SetFooter(shown, shown and not d.hideVersion)
    footerTouched = true
end

-- The guide name centred on the whole header. RXP's line starts 29 px in
-- (room for the logo), so its text is right of the middle. Our own line
-- across the header shows RXP's text, font and colour, and RXP's line is
-- hidden with alpha 0; RXP's anchors are not written. RXP's line is hidden
-- only once ours shows its text, so if RXP changes it, RXP's stays visible.
local function CenterName()
    local fs, header = ns.RXP.HeaderText()
    if not (fs and header) then return end
    if not nameLine then
        local host = CreateFrame("Frame", nil, header)
        host:EnableMouse(false)
        host:SetAllPoints(header)
        nameLine = ns.Media.FontString(host)
        nameLine:SetJustifyH("CENTER")
        nameLine:SetJustifyV("MIDDLE")
        nameLine.host = host
    end
    nameLine.host:SetFrameLevel(header:GetFrameLevel() + 1)
    -- Centred on our header box, which is what shows: Header Extend and Side
    -- Padding move its edges, so RXP's frame centre is off.
    nameLine:ClearAllPoints()
    local box = skins[header]
    if box and box:IsShown() then
        nameLine:SetPoint("LEFT", box, "LEFT", 0, 0)
        nameLine:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    else
        local l, r = ns.RXP.Insets(header)
        nameLine:SetPoint("LEFT", header, "LEFT", l, 0)
        nameLine:SetPoint("RIGHT", header, "RIGHT", -r, 0)
    end
    local path, size, flags = fs:GetFont()
    if not path then return end             -- RXP has not given its line a font yet
    nameLine:SetFont(path, size, flags)
    -- Only r, g, b: RXP's line is hidden with alpha 0, and GetTextColor's
    -- fourth value is that alpha.
    -- FIELD RESULT 2026-10-07 (build 70245): with all four copied, our line
    -- had alpha 0 a second after it showed.
    local cr, cg, cb = fs:GetTextColor()
    nameLine:SetTextColor(cr, cg, cb)
    nameLine:SetShadowOffset(fs:GetShadowOffset())
    nameLine:SetShadowColor(fs:GetShadowColor())
    nameLine:SetText(fs:GetText() or "")
    nameLine:Show()
    ns.RXP.SetHeaderTextShown(false)
end

-- The header: RXP's own logo and class icon, or none; the guide name where
-- RXP puts it, or centred.
local function Header()
    local d = DB()
    ns.RXP.UseRXPIcons()
    if not (d.hideLogos or d.centerHeader) then
        RestoreHeader()
        return
    end
    headerTouched = true
    ns.RXP.SetHeaderIcons(not d.hideLogos)
    if d.centerHeader then
        CenterName()
    else
        if nameLine then nameLine:Hide() end
        ns.RXP.SetHeaderTextShown(true)
    end
end

local function OnHeaderText()
    if active and DB().centerHeader and ns.RXP.ActiveName() == THEME then CenterName() end
end

local function OnFooterHover()
    if active and DB().footerMouseover and ns.RXP.ActiveName() == THEME then Footer() end
end

-- Active Targets and Active Items, the same way as the guide window: our
-- frame under each, one strata below RXP's (see Skin), the title's box over
-- the window's. A window whose backdrop RXP's own option hides gets none of
-- ours either. Padding grows our boxes outward: RXP's buttons are secure
-- and placed by RXP, so they are not moved.
-- The title gets our font face and outline at RXP's size (RXP sets face,
-- size 9 and no outline in UpdateVisuals); written only when it differs.
local function TitleFont(t)
    local fs = t.text
    if not (fs and fs.GetFont) then return end
    local path, size, flags = fs:GetFont()
    local want = FontPath()
    local wantFlags, shadow = Outline()
    if want and size and (path ~= want or (flags or "") ~= wantFlags) then
        fs:SetFont(want, size, wantFlags)
    end
    if size then Shadow(fs, shadow) end
end

-- Whole pixels each title moves up from RXP's place, so both windows have
-- the same room between title and first button (RXP: targets' buttons 15
-- below the top and title 8 above, items' button 16 below and title 10).
local TITLE_UP = {
    RXPTargetFrame = 2,
    RXPItemFrame   = -1,
}

-- The title bar: the title box spans the whole width of the window's box at
-- its top, with the title centred in it, like the guide window's header over
-- its list. The window's box reaches up to the title's top.
local function TitleBar(t, winSkin, titlePad)
    local f = skins[t]
    if not (f and winSkin) then return end
    local u = ns.Ellesmere.PixelUnit(t)
    local h = (math.floor(t:GetHeight() / u + 0.5) + 2 * titlePad) * u
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", winSkin, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", winSkin, "TOPRIGHT", 0, -h)
end

local function Windows()
    local wins, titles = ns.RXP.Windows()
    local d = DB()
    local pad = tonumber(d.winPadding) or 0
    local titlePad = tonumber(d.winTitlePadding) or 0
    for i, w in ipairs(wins) do
        local t = titles[i]
        local titleY
        if t then
            local u = ns.Ellesmere.PixelUnit(t)
            titleY = ns.RXP.PlaceTitle(t, w, true, 0, (TITLE_UP[w:GetName() or ""] or 0) * u)
        end
        local barOn = t and titleY and w.backdropInfo
        if w.backdropInfo then
            -- With the title bar the top goes up to the title's top. Without
            -- a title the top edge stays on RXP's.
            local raise = -pad
            if barOn then
                raise = titleY / ns.Ellesmere.PixelUnit(w) + titlePad - pad
            end
            Skin(w, "window", 1, pad, raise)
        elseif skins[w] then
            skins[w]:Hide()
        end
        if t then
            Skin(t, "wtitle", 4, titlePad)
            if barOn then TitleBar(t, skins[w], titlePad) end
            TitleFont(t)
        end
    end
end

-- The waypoint arrows to pick from: key -> name shown and file in Media/RXP.
-- A new arrow is a white file there (it is tinted with Arrow Color) plus a
-- line here and in ARROW_ORDER; WoW needs a full restart for a new file.
local ARROWS = {
    prosecco = { text = "Prosecco", file = "rxp_navigation_arrow-1" },
    bordered = { text = "Prosecco Bordered", file = "rxp_navigation_arrow-bordered" },
}
local ARROW_ORDER = { "prosecco", "bordered" }

-- Runs right after RXP sets the arrow's texture. With another theme or the
-- module off, only takes our colour off again.
local function Arrow()
    local tex = ns.RXP.ArrowTexture()
    if not tex then return end
    if active and ns.RXP.ActiveName() == THEME then
        local arrow = ARROWS[DB().arrowTexture] or ARROWS.prosecco
        tex:SetTexture(ns.RXP.TEXTURE_PATH .. arrow.file)
        tex:SetVertexColor(ns.HexToRGB(DB().arrowColor))
        arrowTinted = true
    elseif arrowTinted then
        tex:SetVertexColor(1, 1, 1)
        arrowTinted = false
    end
end

local function WindowsPass()
    if active and ns.RXP.ActiveName() == THEME then Windows() end
end

local function Pass()
    if not active then return end
    if ns.RXP.ActiveName() ~= THEME then
        HideEdges()             -- another theme picked in RXP's options
        return
    end
    local relayout = Fonts()
    Parts()
    ns.RXP.OnWindowRedraw(WindowsPass)
    Windows()
    if DB().centerHeader then ns.RXP.OnHeaderText(OnHeaderText) end
    Header()
    if DB().footerMouseover then ns.RXP.OnFooterHover(OnFooterHover) end
    Footer()
    RowBorders()
    if DB().scrollMouseover then ns.RXP.OnGuideHover(OnGuideHover) end
    ScrollBar()
    -- RXP sized the step lines for the font before ours; one more layout
    -- with ours (this pass runs again inside it and changes nothing).
    if relayout then ns.RXP.Relayout() end
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

-- A profile from before the global background keeps its own colours
-- (Core's FillProfile).
function M:KeepOwnBackgrounds(cfg)
    if cfg.useGlobalBackground == nil then cfg.useGlobalBackground = false end
end

-- The old background colours and the key each group was merged into. The
-- first key of a group is its primary. Every old colour's default was
-- 000000; the number is the old default alpha.
local BG_MERGE = {
    { color = "headerBgColor", alpha = "headerBgAlpha", from = {
        { "headerColor", "headerAlpha", 1 }, { "footerColor", "footerAlpha", 1 },
        { "badgeColor", "badgeAlpha", 1 }, { "winTitleColor", "winTitleAlpha", 1 } } },
    { color = "bodyColor", alpha = "bodyAlpha", from = {
        { "listColor", "listAlpha", 0.8 }, { "stepColor", "stepAlpha", 0.8 },
        { "bgColor", "bgAlpha", 0.8 } } },
}

-- An old value differs from its default only when the user set it
-- (defaults are written into the profile; a set value equal to its default
-- cannot be told apart and gives the same colour anyway).
local function OldSet(cfg, colorKey, alphaKey, defAlpha)
    local hex, a = cfg[colorKey], cfg[alphaKey]
    return (hex ~= nil and tostring(hex):upper():gsub("#", "") ~= "000000")
        or (a ~= nil and tonumber(a) ~= defAlpha)
end

-- Runs before the defaults are filled (Core's FillProfile). A group whose
-- new key exists is done (migrated, filled or set) and left alone.
-- Otherwise the new key takes the primary's colour and alpha if the user set
-- it, else the first old one set; with none set the defaults fill it. The
-- old keys stay unused in the profile.
function M:Migrate(cfg)
    -- A profile without stepListColor had the step list in Body's colour;
    -- it keeps it (after the merge below has made Body).
    local listFromBody = cfg.stepListColor == nil and cfg.stepListAlpha == nil
    for _, g in ipairs(BG_MERGE) do
        if cfg[g.color] == nil and cfg[g.alpha] == nil then
            for _, o in ipairs(g.from) do
                if OldSet(cfg, o[1], o[2], o[3]) then
                    cfg[g.color] = cfg[o[1]] or "000000"
                    cfg[g.alpha] = tonumber(cfg[o[2]]) or o[3]
                    break
                end
            end
        end
    end
    if listFromBody and (cfg.bodyColor ~= nil or cfg.bodyAlpha ~= nil) then
        cfg.stepListColor = cfg.bodyColor or "000000"
        cfg.stepListAlpha = tonumber(cfg.bodyAlpha) or 0.8
    end
end

function M:Enable()
    if not ns.RXP.IsLoaded() then
        if not warned then
            warned = true
            ns.Print("RXP Theme is on, but RestedXP Guides is not loaded.")
        end
        return false
    end
    active = true
    ns.RXP.OnRedraw(Pass)
    ns.RXP.OnArrowRedraw(Arrow)
end

-- After combat: Apply again, which reads the settings as they are then.
local function OnCombatEnd()
    waiter:UnregisterEvent("PLAYER_REGEN_ENABLED")
    M:Apply()
end

-- RXP's guide window has no secure frames and RXP redraws it in combat
-- itself, so the pass also runs in combat. A new theme does not: RXP's
-- redraw for it scales Active Targets, which has secure buttons. It waits
-- for the end of combat (a profile switch or import can cause it there).
function M:Apply()
    if not active then return end
    local key = ThemeKey()
    if key ~= lastTheme then
        if InCombatLockdown() then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function()
                    xpcall(OnCombatEnd, ns.ErrorHandler("rxpTheme:combat"))
                end)
            end
            waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            ns.RXP.RegisterTheme(BuildTheme())     -- RXP redraws if Prosecco is picked
            lastTheme = key
        end
    end
    -- Not on every pass: RXP turns the arrow many times a second, and
    -- setting its texture only when RXP does keeps us out of that.
    local arrowKey = strjoin("|", tostring(DB().arrowTexture), tostring(DB().arrowColor), tostring(ns.RXP.ActiveName()))
    if arrowKey ~= lastArrow then
        ns.RXP.RefreshArrow()
        lastArrow = arrowKey
    end
    Pass()
end

function M:Disable()
    active = false
    if waiter then waiter:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    lastArrow = nil
    HideEdges()
    Arrow()
end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------

local function Status()
    if not ns.RXP.IsLoaded() then return "RestedXP Guides is not loaded." end
    if not ns.IsModuleEnabled("rxpTheme") then return "RXP Theme is off: turn it on under Modules on the General page." end
    if ns.RXP.Selected() ~= THEME then
        return "Now pick \"Prosecco by ProseccoAdditions\" in RestedXP's options: Look and Feel > Choose Theme."
    end
    if ns.RXP.ActiveName() ~= THEME then return "Picked in RestedXP; it shows after /reload." end
    return "RestedXP uses the Prosecco theme."
end

local function Color(text, key, alphaKey, tooltip)
    if BG_KIND[key] then
        return ns.BackgroundCell({ text = text, tooltip = tooltip, cfg = DB, colorKey = key, alphaKey = alphaKey,
            default = 1, onChange = function() ns.Apply() end,
            follows = function() return DB().useGlobalBackground == true end })
    end
    return { type = "colorpicker", text = text, hasAlpha = alphaKey ~= nil, tooltip = tooltip,
        getValue = function()
            local r, g, b = ns.HexToRGB(DB()[key])
            if alphaKey then return r, g, b, tonumber(DB()[alphaKey]) or 1 end
            return r, g, b
        end,
        setValue = function(r, g, b, a)
            DB()[key] = ns.RGBToHex(r, g, b)
            if alphaKey then DB()[alphaKey] = a or 1 end
            ns.Apply()
        end }
end

-- Docked under the Quest Tracker, RXP's header and footer are hidden and the
-- dock places the list and its scroll bar, so these options do nothing and
-- are greyed; the value is kept for Standalone. A cell's own greying is
-- kept, with the dock's reason first.
local function docked() return ns.RXP.IsDocked() end
local function inDock(cell, why)
    local own, ownTip = cell.disabled, cell.disabledTooltip
    local tip = "This option does nothing while the guide is in the Quest Tracker (Guide Window: Integrated): " .. why
    cell.disabled = function() return docked() or (own ~= nil and own()) end
    cell.disabledTooltip = function()
        if docked() then return tip end
        if type(ownTip) == "function" then return ownTip() end
        return ownTip
    end
    return cell
end
local NO_HEADER = "RestedXP's header is hidden there."
local NO_FOOTER = "RestedXP's footer is hidden there."

-- The Advanced tab: the standalone window's header, footer and scroll bar
-- (all greyed while the guide is in the tracker).
local function AdvancedPage(parent, y, W, changed)
    local _, h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "The standalone guide window's header, footer and scroll bar. With Guide Window on Integrated (Quest Tracker, RXP tab) the tracker places the list and hides RestedXP's header and footer, so those do nothing there." }); y = y - h

    _, h = W:SectionHeader(parent, "HEADER", y); y = y - h
    _, h = W:DualRow(parent, y,
        inDock({ type = "slider", text = "Header Height", min = 0, max = 80, step = 1,
          tooltip = "Height of RestedXP's header; the guide name, logo and class icon stay centred on it, and it never gets so low that the guide name leaves its box. It grows upward, and step boxes above it move up with it. 0 keeps RestedXP's own height (35).",
          getValue = function() return tonumber(DB().headerHeight) or 0 end,
          setValue = function(v) DB().headerHeight = v; changed() end }, NO_HEADER),
        inDock({ type = "toggle", text = "Center Header Text",
          tooltip = "Centres the guide name on the whole header. RestedXP centres it in the space right of the logo.",
          getValue = function() return DB().centerHeader == true end,
          setValue = function(v) DB().centerHeader = v and true or false; changed() end }, NO_HEADER)); y = y - h
    _, h = W:DualRow(parent, y,
        inDock({ type = "slider", text = "Header Extend", min = 0, max = 16, step = 1,
          tooltip = "Moves the bottom edge of the header's box this many pixels down, and the step list's rows and scroll bar down with it.",
          getValue = function() return DB().headerDrop end,
          setValue = function(v) DB().headerDrop = v; changed() end }, NO_HEADER),
        inDock({ type = "toggle", text = "Hide Logos",
          tooltip = "Hides RestedXP's logo and class icon in the header of the guide window.",
          getValue = function() return DB().hideLogos == true end,
          setValue = function(v) DB().hideLogos = v and true or false; changed() end }, NO_HEADER)); y = y - h

    _, h = W:SectionHeader(parent, "FOOTER", y); y = y - h
    _, h = W:DualRow(parent, y,
        inDock({ type = "toggle", text = "Footer on Mouseover",
          tooltip = "Shows the guide window's footer, with its cog and resize grip, only while the mouse is over it. Timer bars still show.",
          getValue = function() return DB().footerMouseover == true end,
          setValue = function(v) DB().footerMouseover = v and true or false; changed() end }, NO_FOOTER),
        inDock({ type = "toggle", text = "Hide Version Text",
          tooltip = "Hides RestedXP's version line in the footer of the guide window.",
          getValue = function() return DB().hideVersion == true end,
          setValue = function(v) DB().hideVersion = v and true or false; changed() end }, NO_FOOTER)); y = y - h

    _, h = W:SectionHeader(parent, "STEP LIST", y); y = y - h
    _, h = W:DualRow(parent, y,
        inDock({ type = "toggle", text = "Scroll Bar Outside",
          tooltip = "Puts the step list's scroll bar outside the guide window, right of its border. Off: RestedXP's place inside the list.",
          getValue = function() return DB().scrollOutside == true end,
          setValue = function(v) DB().scrollOutside = v and true or false; changed() end },
          "the scroll bar is always outside the list there."),
        inDock({ type = "toggle", text = "Scroll Bar on Mouseover",
          tooltip = "Shows the scroll bar only while the mouse is over the guide window or the bar. The mouse wheel scrolls the list either way.",
          getValue = function() return DB().scrollMouseover == true end,
          setValue = function(v) DB().scrollMouseover = v and true or false; changed() end },
          "the scroll bar always shows only while the mouse is on the list there.")); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "label", text = "Header Extend moves the step list down; Scroll Bar Outside lets the list's rows reach into the room the bar leaves." }); y = y - h
    return y
end

-- Two tabs: RXP Theme holds the look of the parts seen in both guide window
-- modes; Advanced the standalone window's parts (AdvancedPage).
function M:BuildPage(pageName, parent, y, W)
    local _, h
    local function changed() ns.Apply() end
    _, h = W:DualRow(parent, y, { type = "label", text = Status() }); y = y - h
    if pageName == "Advanced" then return AdvancedPage(parent, y, W, changed) end

    _, h = W:SectionHeader(parent, "FONT", y); y = y - h
    local fonts, fontOrder = ns.Media.FontList(true)
    local outlines, outlineOrder = ns.Media.OutlineList(true)
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Font", values = fonts, order = fontOrder,
          tooltip = "The guide text. Its size is RestedXP's own (Font Size in RXP's options). Global font follows the Global Settings page.",
          getValue = function() return DB().font end,
          setValue = function(v) DB().font = v; changed() end },
        { type = "dropdown", text = "Outline", values = outlines, order = outlineOrder,
          tooltip = "Step text, step titles, the step list, header and footer. Shadow is a drop shadow without an outline; Ellesmere's outline also takes Ellesmere's shadow when its Outline Mode uses one. Global outline follows the Global Settings page.",
          getValue = function() return DB().outline end,
          setValue = function(v) DB().outline = v; changed() end }); y = y - h
    _, h = W:DualRow(parent, y,
        Color("Text", "textColor"),
        { type = "spacer" }); y = y - h

    _, h = W:SectionHeader(parent, "BACKGROUNDS", y); y = y - h
    _, h = W:DualRow(parent, y,
        ns.UseGlobalBackgroundCell(DB, changed, "Header takes the Global Header Background; Body and the Active Targets/Items Window the Global Background (Global Settings page)."),
        { type = "spacer" }); y = y - h
    y = ns.Rows(W, parent, y,
        Color("Header", "headerBgColor", "headerBgAlpha", "The guide window's header and footer, the step badges and the title bars of Active Targets and Active Items."),
        Color("Body", "bodyColor", "bodyAlpha", "The step boxes and RestedXP's other windows, such as the leveling tracker."),
        Color("Step List", "stepListColor", "stepListAlpha", "The step list's background, in both guide window modes."))

    _, h = W:SectionHeader(parent, "STEP LIST", y); y = y - h
    _, h = W:DualRow(parent, y,
        Color("List Steps", "rowColor", "rowAlpha", "Each step in the guide list."),
        Color("List Step Highlight", "accentColor", nil, "A step in the list under the mouse.")); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "List Step Border",
          tooltip = "A 1 px line round each step in the guide list.",
          getValue = function() return DB().rowBorder == true end,
          setValue = function(v) DB().rowBorder = v and true or false; changed() end },
        { type = "colorpicker", text = "List Step Border Color", hasAlpha = true,
          disabled = function() return DB().rowBorder ~= true end,
          disabledTooltip = "This option needs List Step Border on.",
          getValue = function()
              local r, g, b = ns.HexToRGB(DB().rowBorderColor)
              return r, g, b, tonumber(DB().rowBorderAlpha) or 1
          end,
          setValue = function(r, g, b, a)
              DB().rowBorderColor = ns.RGBToHex(r, g, b)
              DB().rowBorderAlpha = a or 1
              changed()
          end }); y = y - h

    _, h = W:SectionHeader(parent, "SPACING", y); y = y - h
    _, h = W:DualRow(parent, y,
        inDock({ type = "slider", text = "Side Padding", min = 0, max = 16, step = 1,
          tooltip = "Makes the boxes of the header, step list, footer and step boxes this many pixels wider on each side, so a thick border does not crowd RestedXP's text. RestedXP's own spacing is not changed. Standalone only.",
          getValue = function() return DB().sidePadding end,
          setValue = function(v) DB().sidePadding = v; changed() end },
          "the step list and the step boxes line up with the tracker's border there."),
        { type = "slider", text = "Step Badge Padding", min = 0, max = 16, step = 1,
          tooltip = "Makes the step badge's box this many pixels larger on each side, so a thick border does not cover the step number.",
          getValue = function() return DB().badgePadding end,
          setValue = function(v) DB().badgePadding = v; changed() end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Step Gap", min = 0, max = 30, step = 1,
          tooltip = "Pixels between RestedXP's step boxes when more than one step is shown. The step badges sit 2 px higher than RestedXP puts them, over the gap.",
          getValue = function() return tonumber(DB().stepGap) or 7 end,
          setValue = function(v) DB().stepGap = v; changed() end },
        { type = "spacer" }); y = y - h

    _, h = W:SectionHeader(parent, "BORDER", y); y = y - h
    y = ns.Border.Rows(W, parent, y, function() return DB().border end, changed)

    _, h = W:SectionHeader(parent, "WAYPOINT ARROW AND MAP", y); y = y - h
    local arrows = {}
    for k, a in pairs(ARROWS) do arrows[k] = a.text end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Arrow Texture", values = arrows, order = ARROW_ORDER,
          tooltip = "The arrow RestedXP shows toward the next waypoint.",
          getValue = function() return DB().arrowTexture end,
          setValue = function(v) DB().arrowTexture = v; changed() end },
        Color("Arrow Color", "arrowColor", nil, "The colour of the waypoint arrow.")); y = y - h
    _, h = W:DualRow(parent, y,
        Color("Map Pins", "pinColor", nil, "Map pin text, route lines on the map, timer bars and the tooltip line."),
        { type = "spacer" }); y = y - h

    _, h = W:SectionHeader(parent, "ACTIVE TARGETS AND ACTIVE ITEMS", y); y = y - h
    y = ns.Rows(W, parent, y,
        Color("Window", "winColor", "winAlpha", "The frame behind the buttons. The title bar takes the Header colour."))
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Window Padding", min = 0, max = 16, step = 1,
          tooltip = "Makes the window's box this many pixels larger to the left, right and bottom, so the buttons do not sit against the border. The top stays under the title.",
          getValue = function() return DB().winPadding end,
          setValue = function(v) DB().winPadding = v; changed() end },
        { type = "slider", text = "Title Padding", min = 0, max = 16, step = 1,
          tooltip = "Makes the title bar this many pixels taller above and below the title, so a thick border does not cover it.",
          getValue = function() return DB().winTitlePadding end,
          setValue = function(v) DB().winTitlePadding = v; changed() end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "RestedXP's spacing inside the step boxes is its own and is not changed. The windows take the theme's Border." }); y = y - h
    return y
end
