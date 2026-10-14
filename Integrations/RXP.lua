-- ProseccoUI / Integrations / RXP.lua
-- Everything ProseccoUI touches in RestedXP Guides goes through this file.
-- The theme API (addon:RegisterTheme) is the main road; _G.RXPGuides_Themes
-- cannot be used, since RXP reads it on its own ADDON_LOADED, before ours.
--
-- Besides the theme: post-hooks on RXPFrame's parts and step boxes for the
-- font, background and border pass. RXP's spacing inside the step boxes is
-- never written; every write we do make is commented where it is made.
-- Everything here except RegisterTheme and RXPFrame is RXP-internal
-- (Assumed): each read checks that the field is there.

local ADDON, ns = ...

local R = {}
ns.RXP = R

-- RXP's AceAddon object, nil when RXP is not loaded (an OptionalDep).
-- GetAddon's second argument makes a missing addon return nil.
local function Addon()
    local ace = LibStub("AceAddon-3.0", true)
    local rxp = ace and ace:GetAddon("RXPGuides", true)
    if rxp and type(rxp.RegisterTheme) == "function" then return rxp end
end

function R.IsLoaded()
    return Addon() ~= nil
end

-- Where a theme's texturePath points for our files.
R.TEXTURE_PATH = "Interface/AddOns/" .. ADDON .. "/Media/RXP/"

-- The theme picked in RXP's options (Look and Feel > Choose Theme). Not the
-- one in use: at login RXP falls back to RXP Blue for a theme it does not
-- know yet, and keeps the pick.
function R.Selected()
    local rxp = Addon()
    local p = rxp and rxp.settings and rxp.settings.profile
    return p and p.activeTheme
end

-- The theme RXP is drawing with now.
function R.ActiveName()
    local rxp = Addon()
    return rxp and rxp.activeTheme and rxp.activeTheme.name
end

-- Registers (or replaces) a theme. When it is the picked one RXP redraws
-- with it: RenderFrame restyles every window part (the arrow too) and
-- reloads the guide on the current step. Not addon:ReloadTheme, which does
-- nothing while RXP's "Preview Changes" is off. RegisterTheme fills the
-- table in place and RXP restyles step boxes only for a new table, so pass
-- a new one each time.
-- Not in combat: RenderFrame scales Active Targets, which has secure
-- buttons (RXP itself leaves it alone in combat). The caller waits.
function R.RegisterTheme(theme)
    local rxp = Addon()
    if not rxp then return false end
    rxp:RegisterTheme(theme)
    if R.Selected() == theme.name and type(rxp.RenderFrame) == "function" then
        rxp.RenderFrame("themeReload")
        R.StyleArrowText()
    end
    return true
end

-- The arrow's distance text gets the theme's font and colour only in RXP's
-- SetupArrow, which runs at login before our theme exists and also sets
-- size 9. The same two writes here, at the size the text has (RXP's Arrow
-- Text Size). arrowFrame.text and activeTheme: Assumed, skipped when missing.
function R.StyleArrowText()
    local rxp = Addon()
    local fs = rxp and rxp.arrowFrame and rxp.arrowFrame.text
    local theme = rxp and rxp.activeTheme
    if not (fs and theme and rxp.font) then return end
    local _, size = fs:GetFont()
    if size then fs:SetFont(rxp.font, size, "OUTLINE") end
    if type(theme.textColor) == "table" then fs:SetTextColor(unpack(theme.textColor)) end
end

-- ---------------------------------------------------------------------------
-- The classic guide window (RXP's "V1"). With RXP's beta V2 window on, RXP
-- hides these frames, and ours (their children) with them. Whether V2 picks
-- up our theme without a /reload is Unverified.
-- ---------------------------------------------------------------------------

local function Window() return _G.RXPFrame end

-- Whether point i of f is already this anchor (so a write can be skipped).
local function At(f, i, point, rel, relPoint, x, y)
    local p, r, rp, px, py = f:GetPoint(i)
    return p == point and r == rel and rp == relPoint
        and math.abs(px - x) < 0.01 and math.abs(py - y) < 0.01
end

-- Calls fn after RXP has drawn: a step-box layout (UpdateText, always called
-- through the table), a window restyle (UpdateVisuals), a font-size change
-- (UpdateGuideFontSize, which resets the header and footer font) and the
-- end of a drag or resize (StopMovingOrSizing). Hooks cannot be removed, so
-- this runs once; fn gates itself.
local hooked = false
function R.OnRedraw(fn)
    local rxp, F = Addon(), Window()
    if hooked or not (rxp and F) then return end
    hooked = true
    local handler = ns.ErrorHandler("rxp:redraw")
    local function run() xpcall(fn, handler) end
    local CSF = F.CurrentStepFrame
    if CSF and type(CSF.UpdateText) == "function" then hooksecurefunc(CSF, "UpdateText", run) end
    if type(F.UpdateVisuals) == "function" then hooksecurefunc(F, "UpdateVisuals", run) end
    if type(rxp.UpdateGuideFontSize) == "function" then hooksecurefunc(rxp, "UpdateGuideFontSize", run) end
    hooksecurefunc(F, "StopMovingOrSizing", run)
end

-- Runs RXP's step-box layout once more after the font pass changed a face
-- or outline: RXP sizes each line from its text height, so lines would stay
-- sized for the old font. The next pass changes nothing, so this does not
-- repeat. `busy` stops the loop when a font does not take (a font file that
-- cannot be loaded): the pass inside would see a change and ask again.
local busy = false
function R.Relayout()
    local F = Window()
    local CSF = F and F.CurrentStepFrame
    if busy or not (CSF and type(CSF.UpdateText) == "function") then return end
    busy = true
    xpcall(CSF.UpdateText, ns.ErrorHandler("rxp:relayout"))      -- RXP's code, not ours
    busy = false
end

-- The parts that get our background and border, each with its kind:
-- "header", "list" (the step list), "footer", "step" (a step box) and
-- "badge" (a step box's title badge; owner[i] is its step box). Refilled in
-- place on each call (the passes run on every step change).
local boxes, kind, owner = {}, {}, {}
local function addBox(f, k, own)
    if f then
        local i = #boxes + 1
        boxes[i], kind[i], owner[i] = f, k, own or false
    end
end
function R.Boxes()
    wipe(boxes); wipe(kind); wipe(owner)
    local F = Window()
    if not F then return boxes, kind, owner end
    local add = addBox
    add(F.GuideName, "header")
    add(F.BottomFrame, "list")
    add(F.Footer, "footer")
    local pool = F.CurrentStepFrame and F.CurrentStepFrame.framePool
    if type(pool) == "table" then
        for _, step in ipairs(pool) do
            add(step, "step")
            add(step.number, "badge", step)     -- the title badge on the box's top edge
        end
    end
    return boxes, kind, owner
end

-- The step list's frame level; the header's and footer's are counted from it.
function R.BaseLevel()
    local F = Window()
    return F and F.BottomFrame and F.BottomFrame:GetFrameLevel() or 0
end

-- Puts one of RXP's window frames at a frame level, so our background and
-- border (children, drawn below it) fit between it and what lies under it.
-- RXP sets these levels once, at creation, and never reads them. Written
-- only when it differs.
function R.SetLevel(f, level)
    if f and f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
end

-- The footer's resize grip and cog, which have to stay above the footer.
function R.FooterButtons()
    local F = Window()
    local footer = F and F.Footer
    if footer then return footer.icon, footer.cog end
end

-- Makes RXP's own background on a part transparent; ours is drawn under it.
-- The theme cannot do it: its one background colour is also used by RXP's
-- other windows. RXP sets the colour again when it restyles, and our pass
-- runs after that. Written only when it differs.
function R.ClearBackground(f)
    if not (f.GetBackdropColor and f.SetBackdropColor) then return end
    local _, _, _, a = f:GetBackdropColor()
    if a and a ~= 0 then f:SetBackdropColor(0, 0, 0, 0) end
end

-- RXP's own logo and class icon in the header, pointed at in RXP's folder,
-- not copied (RXP's art is CC BY-NC-SA). RXP sets them from the theme's
-- texturePath when it restyles, so this runs after it, on every pass.
local RXP_TEXTURES = "Interface/AddOns/RXPGuides/Textures/"
local _, playerClass = UnitClass("player")
function R.UseRXPIcons()
    local F = Window()
    local g = F and F.GuideName
    if not g then return end
    if g.icon then g.icon:SetTexture(RXP_TEXTURES .. "rxp_logo-64") end
    if g.classIcon and playerClass then g.classIcon:SetTexture(RXP_TEXTURES .. playerClass) end
end

-- The header's logo, class icon and guide-name line. RXP sets their
-- picture, text and font but never their alpha, so alpha 0 hides them and
-- stays. Written only when it differs.
local function SetAlpha(r, a)
    if r and r:GetAlpha() ~= a then r:SetAlpha(a) end
end

function R.SetHeaderIcons(shown)
    local F = Window()
    local g = F and F.GuideName
    if not g then return end
    SetAlpha(g.icon, shown and 1 or 0)
    SetAlpha(g.classIcon, shown and 1 or 0)
end

function R.HeaderText()
    local F = Window()
    local g = F and F.GuideName
    return g and g.text, g
end

function R.SetHeaderTextShown(shown)
    SetAlpha((R.HeaderText()), shown and 1 or 0)
end

-- Calls fn after RXP sets the guide name: a post-hook on that string's
-- SetText, once; fn gates itself.
local headerHooked = false
function R.OnHeaderText(fn)
    local fs = R.HeaderText()
    if headerHooked or not fs then return end
    headerHooked = true
    local handler = ns.ErrorHandler("rxp:header")
    hooksecurefunc(fs, "SetText", function() xpcall(fn, handler) end)
end

-- What we show of the footer. RXP never shows, hides or fades the footer or
-- hides the cog, and fades the version line and buttons with SetAlpha only
-- while a timer bar runs. So the footer goes by its alpha (our boxes and the
-- resize grip are its children; it still gets the mouse at alpha 0), and
-- the cog (a child of RXPFrame) and version line by Show and Hide, which
-- RXP's alpha writes do not undo. Timer bars are not touched. Docked, the
-- cog is the dock's (DockHover); the theme's ask is kept for R.Undock.
local cogWanted = true      -- what the theme last asked for the cog, for R.Undock
local dock                  -- the tracker frame while the guide is docked (R.Dock)
function R.SetFooter(shown, textShown)
    local F = Window()
    local footer = F and F.Footer
    if not footer then return end
    local a = shown and 1 or 0
    if footer:GetAlpha() ~= a then footer:SetAlpha(a) end
    cogWanted = shown
    if not dock and footer.cog and footer.cog:IsShown() ~= shown then footer.cog:SetShown(shown) end
    local fs = footer.text
    if fs and fs:IsShown() ~= textShown then fs:SetShown(textShown) end
end

-- True while the mouse is over the footer (its buttons lie inside it). The
-- frame method: Forever has no global MouseIsOver.
-- FIELD RESULT 2026-10-06 (build 70235): /dump MouseIsOver gave nil.
function R.FooterHovered()
    local F = Window()
    return F and F.Footer and F.Footer:IsMouseOver() or false
end

-- Calls fn when the mouse enters or leaves the footer or one of its buttons
-- (the footer gets the mouse through RXP's OnMouseDown for dragging,
-- Inferred). Post-hooks, once; fn gates itself. Moving from the footer onto
-- a button calls fn too, which then sees the mouse still over the footer.
local hoverHooked = false
function R.OnFooterHover(fn)
    local F = Window()
    local footer = F and F.Footer
    if hoverHooked or not footer then return end
    hoverHooked = true
    local handler = ns.ErrorHandler("rxp:footer")
    local function run() xpcall(fn, handler) end
    for _, f in ipairs({ footer, footer.icon, footer.cog }) do
        if f then
            f:HookScript("OnEnter", run)
            f:HookScript("OnLeave", run)
        end
    end
end

-- RXP's two small windows outside the guide window: Active Targets
-- (RXPTargetFrame) and Active Items (RXPItemFrame), each with a title badge
-- (.title). RXP paints both with the theme background in UpdateVisuals, the
-- targets frame also in RenderTargetFrameBackground. They are created when
-- first needed, so they are looked up on every call. V2 versions are left
-- alone.
local windows, titles = {}, {}
local function addWindow(f)
    if f and not f.v2 then
        windows[#windows + 1] = f
        titles[#windows] = f.title or false
    end
end
function R.Windows()
    wipe(windows); wipe(titles)
    addWindow(_G.RXPTargetFrame)
    addWindow(_G.RXPItemFrame)
    return windows, titles
end

-- Calls fn after RXP restyles one of those windows. The windows come into
-- being later than our login, so this is called on every pass and hooks
-- each window once when it first exists. Post-hooks only; fn gates itself.
local windowHooked = setmetatable({}, { __mode = "k" })
local targetingHooked = false
local redrawRun             -- for the first fn given, made once (hooks cannot be removed)
function R.OnWindowRedraw(fn)
    if not redrawRun then
        local handler = ns.ErrorHandler("rxp:windows")
        redrawRun = function() xpcall(fn, handler) end
    end
    for _, f in ipairs((R.Windows())) do
        if not windowHooked[f] and type(f.UpdateVisuals) == "function" then
            windowHooked[f] = true
            hooksecurefunc(f, "UpdateVisuals", redrawRun)
        end
    end
    local rxp = Addon()
    local t = rxp and rxp.targeting
    if not targetingHooked and t and type(t.RenderTargetFrameBackground) == "function" then
        targetingHooked = true
        hooksecurefunc(t, "RenderTargetFrameBackground", redrawRun)
    end
end

-- Places a window's title box: RXP's place moved dx, dy (UI units), or
-- centred over the window at RXP's height moved dy. RXP anchors it once, at
-- creation, so its offsets are read the first time and kept. The title box
-- is a plain frame, not secure. Written only when it differs.
-- Returns the title's top above the window's top (UI units), or nil when the
-- title is not where RXP put it.
local titleHome = setmetatable({}, { __mode = "k" })   -- title -> { x, y } RXP gave it
function R.PlaceTitle(title, window, centred, dx, dy)
    local point, rel, relPoint, x, y = title:GetPoint(1)
    if not point or rel ~= window then return end
    local home = titleHome[title]
    if not home then
        if point ~= "TOPLEFT" then return end           -- not RXP's anchor; leave it
        home = { x, y }
        titleHome[title] = home
    end
    local wantPoint, wantX, wantY = "TOPLEFT", home[1] + dx, home[2] + dy
    if centred then wantPoint, wantX = "TOP", 0 end
    if point == wantPoint and relPoint == wantPoint
        and math.abs(x - wantX) < 0.01 and math.abs(y - wantY) < 0.01 then return wantY end
    title:ClearAllPoints()
    title:SetPoint(wantPoint, window, wantPoint, wantX, wantY)
    return wantY
end

-- The guide window's scroll frame: the step list's rows and its scroll bar.
function R.ScrollFrame()
    local F = Window()
    return F and F.ScrollFrame
end

-- Moves the scroll frame's top edge down by dy (UI units) from where RXP put
-- it, or back with 0, so the list's rows and scroll bar start below our
-- header box with Header Extend. RXP anchors it once, when its file loads,
-- so only the top point is replaced. Docked, the header is hidden and the
-- list starts where RXP put it (R.Dock asks again with the kept dy).
-- Written only when it differs.
local scrollHome
local shiftWant = 0
function R.ShiftScrollFrame(dy)
    shiftWant = dy
    if dock then dy = 0 end
    local sf = R.ScrollFrame()
    if not sf then return end
    local F = Window()
    local list = F.BottomFrame
    local point, rel, relPoint, x, y = sf:GetPoint(1)
    if not point then return end
    if not scrollHome then
        if point ~= "TOPLEFT" or rel ~= list then return end   -- not RXP's anchor; leave it
        scrollHome = { x, y }
    end
    local wantY = scrollHome[2] - dy
    if point == "TOPLEFT" and rel == list and relPoint == "TOPLEFT" and math.abs(x - scrollHome[1]) < 0.01
        and math.abs(y - wantY) < 0.01 then return end
    sf:SetPoint("TOPLEFT", list, "TOPLEFT", scrollHome[1], wantY)
end

-- The step list's scroll bar (the scroll frame template's ScrollBar), in the
-- 20 px RXP leaves free on the list's right.
function R.ScrollBar()
    local sf = R.ScrollFrame()
    return sf and sf.ScrollBar
end

-- Puts the scroll bar outside `box` (our step-list box), `gap` UI units
-- right of it, its arrow buttons inside the box's height (the template's
-- buttons sit 16 units above and below the bar), or back on RXP's own
-- anchors with box = nil. RXP sets the bar's point once, when its file
-- loads, so its anchors are read before our first move and put back as they
-- were. Written only when it differs. Docked, the bar is the dock's
-- (PlaceDocked): the theme's ask is kept and done again by R.Undock.
local barHome
local barBox, barGap        -- the theme's last ask
local barAlpha = 1

local function KeepBarHome(bar)
    if barHome then return end
    barHome = {}
    for i = 1, bar:GetNumPoints() do barHome[i] = { bar:GetPoint(i) } end
end

-- The bar beside `box`, its bottom arrow `bottom` units above the box's
-- bottom edge.
local function PlaceBar(bar, box, gap, bottom, left)
    -- `left`: outside the box's left edge instead (the dock's Scroll Bar Side).
    local p1, rp1, p2, rp2, x = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", gap
    if left then p1, rp1, p2, rp2, x = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", -gap end
    if bar:GetNumPoints() == 2 and At(bar, 1, p1, box, rp1, x, -16)
        and At(bar, 2, p2, box, rp2, x, bottom) then return end
    bar:ClearAllPoints()
    bar:SetPoint(p1, box, rp1, x, -16)
    bar:SetPoint(p2, box, rp2, x, bottom)
end

local FitRows, PlaceAfterCombat     -- below, with the rows' width

local function ThemeBar()
    local bar = R.ScrollBar()
    if not bar then return end
    KeepBarHome(bar)
    if bar:GetAlpha() ~= barAlpha then bar:SetAlpha(barAlpha) end
    -- The place waits for the end of combat with the rows' width (FitRows):
    -- at home the bar hangs on the scroll frame's right edge, which keeps
    -- the place the rows gave it until then.
    if InCombatLockdown() then PlaceAfterCombat() return end
    if barBox then
        PlaceBar(bar, barBox, barGap, 16)
    elseif barHome[1] and select(2, bar:GetPoint(1)) ~= barHome[1][2] then
        bar:ClearAllPoints()
        for _, pt in ipairs(barHome) do bar:SetPoint(unpack(pt)) end
    end
end

-- While the scroll bar is outside the list (Scroll Bar Outside, or docked),
-- the room RXP keeps for it is empty, so the rows reach as close to the
-- list's right edge as to its left. RXP keeps 20 right of its scroll frame
-- against 5 left, and its rows hang from the first one (each on the row
-- above). So the scroll frame's right edge and the first row's right point
-- move out by the same 15, and every row is 15 wider. Standalone, the
-- theme's box follows RXP's uneven insets (4 left, 2 right), so the rows go
-- out by the difference too; docked, the box is the whole list. The scroll
-- frame clips the rows. RXP sizes a row's height from its wrapped text, so
-- the list is redrawn whenever the rows' width changes. RXP anchors the
-- scroll frame once, but the first row on every guide load (ending in
-- UpdateFrame), so a post-hook puts the row's point back. RXP's anchors are
-- read before each move and put back when the bar returns into the list.
local sfRightHome           -- RXP's BOTTOMRIGHT offsets of the scroll frame
local rowBase, rowOurs      -- the first row's TOPRIGHT x: RXP's, and the one we wrote
local rowsWide = false      -- what the rows were last fitted to
local fitHooked = false

-- One of a frame's points by name (GetPoint takes an index).
local function PointNamed(f, name)
    for i = 1, f:GetNumPoints() do
        local p, rel, relPoint, x, y = f:GetPoint(i)
        if p == name then return rel, relPoint, x, y end
    end
end

local function FitRowsNow()
    local rxp, F = Addon(), Window()
    local sf, list, child = F and F.ScrollFrame, F and F.BottomFrame, F and F.ScrollChild
    if not (sf and list and child) then return end
    local wide = (dock ~= nil or barBox ~= nil)
    if not sfRightHome then
        if not wide then return end         -- never moved: RXP's layout as it is
        local rel, relPoint, x, y = PointNamed(sf, "BOTTOMRIGHT")
        if rel ~= list or relPoint ~= "BOTTOMRIGHT" then return end   -- not RXP's anchor; leave it
        sfRightHome = { x, y }
    end
    if not fitHooked and type(list.UpdateFrame) == "function" then
        fitHooked = true
        -- Only RXP's list update without a step (a guide load or redraw)
        -- anchors the first row again; per-step updates, many a second, and
        -- an Alt-drag's OnUpdate pass a second argument and move no rows.
        hooksecurefunc(list, "UpdateFrame", function(_, stepn)
            if stepn == nil then FitRows() end
        end)
    end
    local leftRel, _, leftX = PointNamed(sf, "TOPLEFT")
    local extra = leftRel == list and (-sfRightHome[1] - leftX) or 0
    if extra <= 0 then wide = false end     -- RXP's layout is not the one read above
    if wide and not dock then
        local il, ir = R.Insets(list)
        extra = extra + il - ir
    end
    -- The scroll frame's right edge.
    local _, _, x = PointNamed(sf, "BOTTOMRIGHT")
    local wantX = wide and sfRightHome[1] + extra or sfRightHome[1]
    if not x or math.abs(x - wantX) >= 0.01 then
        sf:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", wantX, sfRightHome[2])
    end
    -- The first row's right point: RXP's unless it is the one we wrote.
    local row = child.framePool and child.framePool[1]
    if row then
        local rel, relPoint, rx, ry = PointNamed(row, "TOPRIGHT")
        if rel == child and relPoint == "TOPRIGHT" then
            if not (rowOurs and math.abs(rx - rowOurs) < 0.01) then rowBase = rx end
            local want = wide and rowBase + extra or rowBase
            if math.abs(rx - want) >= 0.01 then
                row:SetPoint("TOPRIGHT", child, "TOPRIGHT", want, ry)
                -- A guide load anchors the first row again and measures the
                -- rows before our post-hook, so they are measured again.
                if rxp then rxp.updateBottomFrame = true end
            end
            rowOurs = want
        end
    end
    if rowsWide ~= wide then
        rowsWide = wide
        if rxp then rxp.updateBottomFrame = true end
    end
end

-- Placement of RXP's frames waits for the end of combat: the rows, the
-- scroll frame and the theme's scroll bar place are done again together
-- then. RXP can load a guide in combat, which puts the first row back to
-- its width until combat ends. A wait of its own, not the dock's
-- AfterCombat, whose one pending move would replace a dock or undock
-- waiting there; the run after combat reads the state as it is then.
local fitHandler, placeWait
local PlaceHeader           -- below, with the header's height
PlaceAfterCombat = function()
    if not placeWait then
        placeWait = CreateFrame("Frame")
        placeWait:SetScript("OnEvent", function(f)
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if not dock then ThemeBar() end
            -- The theme's boxes round the header and the step boxes over it
            -- go on whole pixels at the new height, as after R.SetListHeight.
            if PlaceHeader() then R.Relayout() end
            FitRows()
        end)
    end
    placeWait:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- The header's height (the theme's Header Height). RXP sets it once (35) and
-- never reads it. The header hangs on the step list by its bottom, so it
-- grows upward; the guide name and icons are centred on it, and the step
-- boxes, which hang on its top in RXP's "top" orientation, move up with it.
-- nil gives RXP's height back. It moves the step boxes, so in combat a
-- change waits with the rows' width. Returns true when written.
local headerHome, headerWant
PlaceHeader = function()
    local F = Window()
    local g = F and F.GuideName
    if not g then return end
    headerHome = headerHome or g:GetHeight()
    local h = headerWant or headerHome
    if math.abs(g:GetHeight() - h) < 0.01 then return false end
    if InCombatLockdown() then PlaceAfterCombat() return false end
    g:SetHeight(h)
    return true
end

function R.SetHeaderHeight(h)
    headerWant = h
    PlaceHeader()
end

FitRows = function()
    if not (rowsWide or dock or barBox) then return end
    if InCombatLockdown() then PlaceAfterCombat() return end
    fitHandler = fitHandler or ns.ErrorHandler("rxp:rows")
    xpcall(FitRowsNow, fitHandler)
end

function R.PlaceScrollBar(box, gap)
    barBox, barGap = box, gap
    if not dock then ThemeBar() end
    FitRows()
end

-- Shows or hides the scroll bar by alpha (it keeps the mouse, so it still
-- scrolls under the pointer); RXP never writes the bar's alpha.
function R.SetScrollBarAlpha(a)
    barAlpha = a
    if not dock then ThemeBar() end
end

-- True while the mouse is over the scroll bar or one of its arrow buttons,
-- which lie outside the bar's own rect; otherwise Scroll Bar on Mouseover
-- would hide the bar while the mouse is on an arrow.
local function BarHovered(bar)
    return bar and (bar:IsMouseOver()
        or (bar.ScrollUpButton and bar.ScrollUpButton:IsMouseOver())
        or (bar.ScrollDownButton and bar.ScrollDownButton:IsMouseOver())) or false
end

-- True while the mouse is over the guide window or its scroll bar (which
-- lies outside the window once placed outside).
function R.GuideHovered()
    local F = Window()
    return (F and F:IsMouseOver()) or BarHovered(R.ScrollBar())
end

-- Calls the theme's fn (R.OnGuideHover) and, while docked, DockHover when
-- the mouse enters or leaves the guide window, its parts, step boxes, list
-- rows, scroll bar or cog. Each frame is hooked once (RXP makes rows and
-- step boxes as needed, so this runs on every pass); the functions gate
-- themselves and see the mouse still over the window when it moves between
-- parts. RXP sets new OnEnter/OnLeave scripts on the list rows on every
-- guide load, which drops our hooks, so the script a frame had after our
-- hook is kept, and a frame is hooked again when it differs.
local guideHooked = setmetatable({}, { __mode = "k" })
-- Whether the list's rows need the hooks again. A guide load gives every row
-- a new script, and new rows come at the end, so the first and last row
-- tell. There are a few hundred rows, and this runs on each theme pass and
-- each R.Dock (every setting change).
local function RowsChanged()
    local rows = R.ListRows()
    local first, last = rows[1], rows[#rows]
    return first ~= nil and (guideHooked[first] ~= (first:GetScript("OnEnter") or false)
        or guideHooked[last] ~= (last:GetScript("OnEnter") or false))
end
local themeHover            -- the theme's fn, the first one given (hooks cannot be removed)
local DockHover             -- the dock's, defined with the dock below
local CheckBelow            -- Keep On Screen's watch, defined with R.BelowHeight
local hoverRun
local function HookGuideHover()
    local F = Window()
    if not F then return end
    if not hoverRun then
        local handler = ns.ErrorHandler("rxp:hover")
        hoverRun = function()
            if dock then xpcall(DockHover, handler) end
            if themeHover then xpcall(themeHover, handler) end
        end
    end
    local function hook(f)
        if not (f and f.HookScript) then return end
        local seen = guideHooked[f]         -- nil: never hooked; false: hooked, no script to compare
        if seen == nil or seen ~= (f:GetScript("OnEnter") or false) then
            f:HookScript("OnEnter", hoverRun)
            f:HookScript("OnLeave", hoverRun)
            guideHooked[f] = f:GetScript("OnEnter") or false
        end
    end
    hook(F); hook(F.BottomFrame); hook(F.GuideName); hook(F.Footer); hook(R.ScrollFrame())
    if F.Footer then hook(F.Footer.cog) end
    local bar = R.ScrollBar()
    if bar then hook(bar); hook(bar.ScrollUpButton); hook(bar.ScrollDownButton) end
    local pool = F.CurrentStepFrame and F.CurrentStepFrame.framePool
    if type(pool) == "table" then for _, step in ipairs(pool) do hook(step) end end
    if RowsChanged() then
        for _, row in ipairs(R.ListRows()) do hook(row) end
    end
end

function R.OnGuideHover(fn)
    themeHover = themeHover or fn
    HookGuideHover()
end

-- The rows of the step list: one frame per guide step, made when a guide
-- loads (ScrollChild.framePool).
local noRows = {}
function R.ListRows()
    local F = Window()
    local pool = F and F.ScrollChild and F.ScrollChild.framePool
    return type(pool) == "table" and pool or noRows
end

-- RXP's waypoint arrow: one texture that arrowFrame:UpdateVisuals sets from
-- the theme's texturePath and DrawArrow turns with SetRotation. RXP never
-- sets its vertex colour.
local function ArrowFrame()
    local rxp = Addon()
    local af = rxp and rxp.arrowFrame
    if af and af.texture and type(af.UpdateVisuals) == "function" then return af end
end

function R.ArrowTexture()
    local af = ArrowFrame()
    return af and af.texture
end

-- Calls fn after RXP sets the arrow's texture. Hooked once; fn gates itself.
local arrowHooked = false
function R.OnArrowRedraw(fn)
    local af = ArrowFrame()
    if arrowHooked or not af then return end
    arrowHooked = true
    local handler = ns.ErrorHandler("rxp:arrow")
    hooksecurefunc(af, "UpdateVisuals", function() xpcall(fn, handler) end)
end

-- Has RXP set the arrow's texture again (and so run fn above). RXP's own
-- function, so our texture is set at the same point RXP sets its own.
function R.RefreshArrow()
    local af = ArrowFrame()
    if af then xpcall(af.UpdateVisuals, ns.ErrorHandler("rxp:arrow"), af) end
end

-- The part of a box RXP paints: its frame shrunk by the backdrop insets
-- (left, right, top, bottom) from BackdropTemplate's backdropInfo. RXP's
-- own boxes use 4, 2, 2, 4.
function R.Insets(f)
    local ins = f.backdropInfo and f.backdropInfo.insets
    if not ins then return 0, 0, 0, 0 end
    return ins.left or 0, ins.right or 0, ins.top or 0, ins.bottom or 0
end

-- The text RXP draws with the theme font and a fixed "" outline: step boxes
-- (title badge and lines), header, footer, and the list rows and their
-- numbers. stepText marks the ones RXP sizes the step boxes from, listText
-- the ones it sizes the list rows from (a row's text, and its number, whose
-- width sets where the text wraps), rxpColour the ones RXP colours itself.
-- RXP sets a row's text font and colour again on every guide load, its
-- number's only when it makes the row.
local texts, stepText, listText, rxpColour = {}, {}, {}, {}
local function addText(fs, inStep, inList, coloured)
    if fs and fs.SetFont then
        local n = #texts + 1
        texts[n], stepText[n], listText[n], rxpColour[n] = fs, inStep, inList or false, coloured or false
    end
end
function R.Texts()
    wipe(texts); wipe(stepText); wipe(listText); wipe(rxpColour)
    local F = Window()
    if not F then return texts, stepText, listText, rxpColour end
    local add = addText
    add(F.GuideName and F.GuideName.text, false)
    add(F.Footer and F.Footer.text, false)
    local pool = F.CurrentStepFrame and F.CurrentStepFrame.framePool
    if type(pool) == "table" then
        for _, step in ipairs(pool) do
            add(step.number and step.number.text, true)
            if type(step.elements) == "table" then
                for _, el in ipairs(step.elements) do add(el.text, true) end
            end
        end
    end
    for _, row in ipairs(R.ListRows()) do
        add(row.text, false, true, true)
        add(row.number and row.number.text, false, true)
    end
    return texts, stepText, listText, rxpColour
end

-- Asks RXP to redraw the step list on its next update, which sizes each
-- row's height from its text again: the flag RXP's own options use.
function R.RedrawList()
    local rxp = Addon()
    if rxp then rxp.updateBottomFrame = true end
end

-- ---------------------------------------------------------------------------
-- The loaded guide, for the Quest Tracker: which quests it names, where the
-- player is in it, and when that changes. All RXP-internal (Assumed):
-- addon.currentGuide.steps (step n at index n), each step's elements with a
-- numeric questId, addon.GetGuideProgress and addon.GetGuideName. Each read
-- checks its field: a missing one gives "no guide", never an error.
-- ---------------------------------------------------------------------------

local function CurrentGuide()
    local rxp = Addon()
    local g = rxp and rxp.currentGuide
    -- With no guide picked RXP loads its welcome guide (empty = true), which is
    -- "no guide" for us.
    if type(g) == "table" and type(g.steps) == "table" and not g.empty then return rxp, g end
end

-- The step the player is on (1-based), or nil.
local function CurrentStep(rxp)
    if type(rxp.GetGuideProgress) ~= "function" then return nil end
    return tonumber((rxp.GetGuideProgress()))
end

-- questID -> the first step at or after the current one that names it, or
-- `past` for a quest the guide names only in steps already behind. nil when
-- no guide is loaded. A new table per call: called once per tracker refresh.
function R.GuideQuests()
    local rxp, g = CurrentGuide()
    if not rxp then return nil end
    local now = CurrentStep(rxp) or 1
    local out, past = {}, #g.steps + 1
    for n, step in ipairs(g.steps) do
        if type(step) == "table" and type(step.elements) == "table" then
            for _, el in ipairs(step.elements) do
                local id = type(el) == "table" and el.questId
                if type(id) == "number" then
                    if n >= now then
                        if not out[id] or out[id] == past then out[id] = n end
                    elseif not out[id] then
                        out[id] = past
                    end
                end
            end
        end
    end
    return out
end

-- questID -> true for the quests in the steps RXP has active (the step it
-- is on, sticky steps still open before it, and a step's tip, as in
-- RXPFrame.activeSteps). nil when no guide is loaded. One table, refilled
-- per call: called once per tracker draw.
local activeQuests = {}
function R.ActiveQuests()
    local F = Window()
    local steps = F and F.activeSteps
    if not (CurrentGuide() and type(steps) == "table") then return nil end
    wipe(activeQuests)
    for _, step in ipairs(steps) do
        if type(step) == "table" and type(step.elements) == "table" then
            for _, el in ipairs(step.elements) do
                local id = type(el) == "table" and el.questId
                if type(id) == "number" then activeQuests[id] = true end
            end
        end
    end
    return activeQuests
end

-- name, current step, number of steps; nil when no guide is loaded.
function R.GuideProgress()
    local rxp, g = CurrentGuide()
    if not rxp then return nil end
    local total = #g.steps
    if total == 0 then return nil end
    local name = type(rxp.GetGuideName) == "function" and rxp.GetGuideName(g) or g.name
    local step = math.max(1, math.min(total, CurrentStep(rxp) or 1))
    return tostring(name or ""), step, total
end

-- Calls fn when RXP loads a guide, moves to a step or drops a step from its
-- active ones. RXP sends these as AceEvent messages (RXP_GUIDE_LOADED,
-- RXP_STEP_ACTIVATED, RXP_STEP_DEACTIVATED; RXP-internal, Assumed), received
-- on our own object embedding AceEvent-3.0; nothing of RXP's is hooked.
-- Registered once; fn gates itself. Without AceEvent the tracker still
-- follows the guide on its next quest log update.
local guideListener
function R.OnGuideChange(fn)
    if guideListener or not Addon() then return end
    local AceEvent = LibStub("AceEvent-3.0", true)
    if not AceEvent then return end
    guideListener = {}
    AceEvent:Embed(guideListener)
    local function run() xpcall(fn, ns.ErrorHandler("rxp:guide")) end
    guideListener:RegisterMessage("RXP_GUIDE_LOADED", run)
    guideListener:RegisterMessage("RXP_STEP_ACTIVATED", run)
    guideListener:RegisterMessage("RXP_STEP_DEACTIVATED", run)
end

-- ---------------------------------------------------------------------------
-- The guide docked under the Quest Tracker (Guide Window: Integrated). From
-- the top: the tracker; RXP's step list right under it, as wide, one border
-- round both with a seam at the join; then RXP's step boxes, Guide Gap
-- under the list. The scroll bar sits outside the list with RXP's cog under
-- it, both shown only while the mouse is on them or the list. RXP's header
-- and footer are hidden. RXP keeps the rest: content, clicks, scrolling and
-- the list's height.
--
-- RXP puts the step boxes back on its header after every list update and
-- every click or drag on the window (SetStepFrameAnchor, also a local call
-- in RXPFrame.OnMouseUp), so both are post-hooked and our anchors put back
-- while docked. RXPFrame hangs on the tracker and the step boxes on the
-- list; nothing of RXP's hangs on the step boxes, so there is no anchor loop.
--
-- The border round tracker and list is a frame of ours (`edge`) on UIParent;
-- the Quest Tracker draws no border of its own while docked. Its bottom
-- follows the list's height and visibility, which RXP changes (Alt-drag,
-- Show step list, hiding the window), so those are post-hooked too. With
-- the list hidden the border goes round the tracker alone and the step
-- boxes hang under the tracker.
--
-- RXP's guide window has no secure frames and RXP moves it in combat
-- itself, so we put it back in combat too. Docking and undocking wait for
-- the end of combat. The frame we dock to never has secure children: the
-- Quest Tracker passes a plain frame over its rect.
--
-- savePosition = false is RXP's own per-frame switch: while docked RXP
-- neither saves the docked place nor loads its saved place over ours. The
-- standalone place stays saved, and R.Undock loads it back.
-- ---------------------------------------------------------------------------

local dockGap = 0
local dockBorder        -- function returning the tracker's border setting (read at call time)
local dockReach = 0     -- RXP units right of the list, up to the bar, that count as on the list
local dockBarLeft = false   -- the list's scroll bar and cog left of it (the Quest Tracker's Scroll Bar Side)
local dockHome          -- RXPFrame's points when it was docked
local dockWidth = 0     -- RXPFrame's width at the last redraw R.Dock asked for (RXP units)
local dockSave          -- RXPFrame.savePosition before the dock
local cogHome           -- the cog's points before its first move
local edge, joinSeam    -- our border round tracker and list, and the seam at the join
local seamDrawn = false
local dockHooked = false
-- Folded (R.SetDockFolded): the guide window above the screen; clampHome
-- is RXPFrame's own clamp to the screen, given back when it comes down,
-- and stepClamp the step boxes whose clamp the fold took off (ClampSteps).
local folded = false
local clampHome
local stepClamp = setmetatable({}, { __mode = "k" })
local FOLD_RISE = 10000     -- RXP units above the tracker: past the top of any screen

-- RXP puts a step box's title badge 5 above the box, so the gap is counted
-- from the list to its top; the theme lifts it badgeLift more.
local BADGE_RISE = 5
local badgeLift = 0         -- RXP units the theme lifts the badges by (runtime only)
local stepGap = 5           -- RXP units between step boxes (RXP's 5, or the theme's Step Gap; R.SpaceSteps)

-- Where the step boxes stand while docked (the Quest Tracker's Steps
-- Position): "under" the list, or beside the tracker, "left" or "right",
-- level with its top, newest step first.
local dockSide = "under"
local stepsReversed = false  -- our order is on RXP's boxes (OrderSteps)

-- Two points, written only when they differ: this runs after every RXP
-- list update.
local function Place2(f, p1, r1, rp1, x1, y1, p2, r2, rp2, x2, y2)
    if f:GetNumPoints() == 2 and At(f, 1, p1, r1, rp1, x1, y1) and At(f, 2, p2, r2, rp2, x2, y2) then return end
    f:ClearAllPoints()
    f:SetPoint(p1, r1, rp1, x1, y1)
    f:SetPoint(p2, r2, rp2, x2, y2)
end

-- RXP's step boxes in its column, each on the one before it, in pool order
-- (the current step last). `reversed`: newest first, the same chain the
-- other way round; else RXP's own order back. By pool index, so running it
-- again changes nothing. A tip box on UIParent is left where RXP put it.
-- This moves RXP's frames, so in combat it waits, reading the state then.
local orderWait
local function OrderSteps(CSF, reversed)
    if InCombatLockdown() then
        if not orderWait then
            orderWait = CreateFrame("Frame")
            orderWait:SetScript("OnEvent", function(f)
                f:UnregisterEvent("PLAYER_REGEN_ENABLED")
                local F = Window()
                if F and F.CurrentStepFrame then
                    xpcall(function() OrderSteps(F.CurrentStepFrame, dock ~= nil and dockSide ~= "under") end,
                        ns.ErrorHandler("rxp:order"))
                end
            end)
        end
        orderWait:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if not reversed and not stepsReversed then return end   -- RXP's order, never touched
    local pool = CSF.framePool
    if type(pool) ~= "table" then return end
    local column = {}
    for _, box in ipairs(pool) do
        local _, rel = box:GetPoint(1)
        if box:IsShown() and rel ~= nil and rel ~= UIParent then column[#column + 1] = box end
    end
    local n = #column
    for i = 1, n do
        local box = reversed and column[n + 1 - i] or column[i]
        if i == 1 then
            Place2(box, "TOPLEFT", CSF, "TOPLEFT", 0, 0, "TOPRIGHT", CSF, "TOPRIGHT", 0, 0)
        else
            local above = reversed and column[n + 2 - i] or column[i - 1]
            Place2(box, "TOPLEFT", above, "BOTTOMLEFT", 0, -stepGap, "TOPRIGHT", above, "BOTTOMRIGHT", 0, -stepGap)
        end
    end
    stepsReversed = reversed
end

-- The border's look and the seam, when the dock or the tracker's settings
-- change. Lines follow size changes by themselves (their anchors).
local function DrawEdge()
    if not edge then
        edge = CreateFrame("Frame", nil, UIParent)
        edge:EnableMouse(false)
        joinSeam = CreateFrame("Frame", nil, edge)
        joinSeam:EnableMouse(false)
        joinSeam.tex = joinSeam:CreateTexture(nil, "OVERLAY")
    end
    -- The tracker's strata and level (the dock anchor carries them), as its
    -- own border had; the seam above the border's lines (Apply's holder is
    -- +1, its lines +2), as the tracker's Header Seam.
    edge:SetFrameStrata(dock:GetFrameStrata())
    edge:SetFrameLevel(dock:GetFrameLevel())
    joinSeam:SetFrameLevel(edge:GetFrameLevel() + 2)
    joinSeam:ClearAllPoints()
    joinSeam:SetPoint("TOPLEFT", dock, "BOTTOMLEFT")
    joinSeam:SetPoint("TOPRIGHT", dock, "BOTTOMRIGHT")
    joinSeam:SetHeight(1)
    local cfg = dockBorder()
    ns.Border.Apply(edge, cfg)
    seamDrawn = ns.Border.Seam(joinSeam.tex, joinSeam, cfg) == true
end

local function PlaceEdge(list, listShown)
    if listShown then
        -- The border's bottom hangs on the list's, so it follows while RXP
        -- sizes the window (every frame during an Alt-drag). It is put on a
        -- whole pixel here, after each list update and at the drag's end.
        -- The list's top is the tracker's bottom, on a whole pixel, so the
        -- snapped list height puts the border's bottom on the pixel the
        -- theme's list box rounds to.
        local h = list:GetHeight() * list:GetEffectiveScale() / edge:GetEffectiveScale()
        local below = ns.Border.Snap(h, ns.Ellesmere.PixelUnit(edge))
        Place2(edge, "TOPLEFT", dock, "TOPLEFT", 0, 0, "BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, h - below)
    else
        Place2(edge, "TOPLEFT", dock, "TOPLEFT", 0, 0, "BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, 0)
    end
    edge:Show()
    joinSeam:SetShown(listShown and seamDrawn)
end

-- The scroll bar outside the list's right edge, 2 px from it plus the half
-- of a textured border that reaches out, as the theme places it. It ends a
-- cog's height higher, and the cog hangs under its down arrow, touching it:
-- the mouse goes from bar to cog without leaving both, since a hidden cog
-- gets no OnEnter. Without the list the bar is hidden with it, and the cog
-- (RXP's menu) hangs at the tracker's bottom corner and stays shown. RXP
-- anchors the cog once, to the footer, so its points are kept for R.Undock.
local function PlaceBarAndCog(F, list, listShown)
    local bar = R.ScrollBar()
    local cog = F.Footer.cog
    if cog and not cogHome then
        cogHome = {}
        for i = 1, cog:GetNumPoints() do cogHome[i] = { cog:GetPoint(i) } end
    end
    if not bar then return end
    KeepBarHome(bar)
    -- The bar's place waits for the end of combat, as the theme's. This runs
    -- in combat on RXP's list updates and reads the border live, so in
    -- combat the bar and dockReach keep their place; R.Dock, which runs on a
    -- border change, places the bar after combat.
    if not InCombatLockdown() then
        local b = ns.Border.Resolve(dockBorder())
        local out = ns.Ellesmere.IsTexturedBorder(b.style) and (tonumber(b.size) or 0) / 2 or 0
        dockReach = (2 + out) * ns.Ellesmere.PixelUnit(list)
        PlaceBar(bar, list, dockReach, 16 + (cog and cog:GetHeight() or 0), dockBarLeft)
    end
    if not cog then return end
    local point, rel, relPoint, x, y = "TOP", bar.ScrollDownButton or bar, "BOTTOM", 0, bar.ScrollDownButton and 0 or -16
    if not listShown then
        if dockBarLeft then
            point, rel, relPoint, x, y = "TOPRIGHT", dock, "BOTTOMLEFT", -dockReach, 0
        else
            point, rel, relPoint, x, y = "TOPLEFT", dock, "BOTTOMRIGHT", dockReach, 0
        end
    end
    if not (cog:GetNumPoints() == 1 and At(cog, 1, point, rel, relPoint, x, y)) then
        cog:ClearAllPoints()
        cog:SetPoint(point, rel, relPoint, x, y)
    end
end

-- RXP clamps a step box to the screen when it shows a tip in it and keeps
-- the clamp when the box later holds a step of the column. Folded, such a
-- box would be held at the screen's top edge, visible and clickable, so its
-- clamp is off while folded and given back after, as the window's. A tip
-- box on UIParent stays clamped where RXP put it.
local function ClampSteps(CSF)
    if folded then
        local pool = CSF.framePool
        if type(pool) ~= "table" then return end
        for _, box in ipairs(pool) do
            if box:IsClampedToScreen() and R.DockedStep(box) then
                stepClamp[box] = true
                box:SetClampedToScreen(false)
            end
        end
    elseif next(stepClamp) then
        for box in pairs(stepClamp) do box:SetClampedToScreen(true) end
        wipe(stepClamp)
    end
end

-- Writes only what differs: this runs after every RXP list update.
local function PlaceDocked()
    local F = Window()
    local CSF = F and F.CurrentStepFrame
    local list = F and F.BottomFrame
    if not (dock and CSF and list) then return end
    -- IsVisible: hiding RXP's window hides the list with it. Folded, the list
    -- is not under the tracker, whatever RXP shows.
    local listShown = list:IsVisible() and not folded
    -- The list lies 3 in from RXPFrame's top and sides, so RXPFrame reaches
    -- 3 past the tracker's sides and 3 up into it: the list's top is the
    -- tracker's bottom and its sides the tracker's, at any Window Scale.
    -- Folded, FOLD_RISE higher, above the screen.
    local rise = folded and FOLD_RISE or 0
    if folded and F:IsClampedToScreen() then
        clampHome = true
        F:SetClampedToScreen(false)
    end
    Place2(F, "TOPLEFT", dock, "BOTTOMLEFT", -3, 3 + rise, "TOPRIGHT", dock, "BOTTOMRIGHT", 3, 3 + rise)
    if clampHome and not folded then
        F:SetClampedToScreen(true)
        clampHome = nil
    end
    -- The gap is in the tracker's units; RXP's frames have RXP's Window Scale.
    -- Folded, the step boxes go up with the window.
    local k = dock:GetEffectiveScale() / F:GetEffectiveScale()
    if dockSide == "left" or dockSide == "right" then
        -- Beside the tracker, as wide as it, the newest box's top level with
        -- the tracker's and its badge above both; folded, up with the window.
        local g, w = dockGap * k, dock:GetWidth() * k
        local y = rise
        if dockSide == "left" then
            Place2(CSF, "TOPRIGHT", dock, "TOPLEFT", -g, y, "TOPLEFT", dock, "TOPLEFT", -g - w, y)
        else
            Place2(CSF, "TOPLEFT", dock, "TOPRIGHT", g, y, "TOPRIGHT", dock, "TOPRIGHT", g + w, y)
        end
        OrderSteps(CSF, true)
    else
        local g = dockGap * k + BADGE_RISE + badgeLift
        local above = folded and F or listShown and list or dock
        Place2(CSF, "TOPLEFT", above, "BOTTOMLEFT", 0, -g, "TOPRIGHT", above, "BOTTOMRIGHT", 0, -g)
        OrderSteps(CSF, false)
    end
    ClampSteps(CSF)
    PlaceEdge(list, listShown)
    PlaceBarAndCog(F, list, listShown)
    -- The list shown or hidden changes what the cog does (DockHover).
    DockHover()
    CheckBelow()
end

-- Shows the bar (by alpha: it keeps the mouse, so wheel and arrows still
-- work) and the cog (by Show and Hide: RXP writes the cog's alpha while a
-- timer bar runs) while the mouse is on the list, the strip between it and
-- the bar, the bar or the cog. Without the list the cog always shows;
-- folded it is hidden with the rest of the guide.
DockHover = function()
    local F = Window()
    local list = F and F.BottomFrame
    if not (dock and list) then return end
    local bar, cog = R.ScrollBar(), F.Footer and F.Footer.cog
    local listShown = list:IsVisible()
    local over = listShown and (list:IsMouseOver(0, 0, dockBarLeft and -dockReach or 0, dockBarLeft and 0 or dockReach) or BarHovered(bar)
        or (cog and cog:IsShown() and cog:IsMouseOver())) and true or false
    local a = over and 1 or 0
    if bar and bar:GetAlpha() ~= a then bar:SetAlpha(a) end
    local cogShown = not folded and (over or not listShown)
    if cog and cog:IsShown() ~= cogShown then cog:SetShown(cogShown) end
end

-- Hooks cannot be removed, so this runs once; the hooks gate on `dock`.
local function HookDock(F, CSF)
    if dockHooked then return end
    dockHooked = true
    local handler = ns.ErrorHandler("rxp:dock")
    local function run() if dock then xpcall(PlaceDocked, handler) end end
    hooksecurefunc(F, "SetStepFrameAnchor", run)
    F:HookScript("OnMouseUp", run)
    CSF:HookScript("OnMouseUp", run)
    -- RXP shows or hides the list as it updates it, which moves the step
    -- boxes and the border's bottom. A shown list's height changes need
    -- nothing: the border, step boxes and bar hang on the list.
    local list = F.BottomFrame
    list:HookScript("OnShow", run)
    list:HookScript("OnHide", run)
    -- RXP moves steps between its step boxes without SetStepFrameAnchor and
    -- ends each step change in UpdateText: folded, a box that held a tip can
    -- now be in the column (ClampSteps); beside the tracker, RXP has just
    -- chained the boxes in its own order again (OrderSteps).
    hooksecurefunc(CSF, "UpdateText", function()
        if dock and (folded or dockSide ~= "under") then xpcall(PlaceDocked, handler) end
        if dock then xpcall(CheckBelow, handler) end
    end)
    -- A guide load gives the list new rows and row scripts and ends in
    -- UpdateFrame without a step: the rows get the hover hooks again, so the
    -- bar and cog follow the mouse without the theme too. Per-step updates
    -- and an Alt-drag pass a second argument (see FitRowsNow).
    if type(list.UpdateFrame) == "function" then
        hooksecurefunc(list, "UpdateFrame", function(_, stepn)
            if dock and stepn == nil and RowsChanged() then xpcall(HookGuideHover, handler) end
        end)
    end
end

-- Docking and undocking move RXP's frames, so they wait for the end of
-- combat (a /reload or a profile switch in combat). One pending move; the
-- last call wins.
local pending
local regen
local function AfterCombat(fn)
    pending = fn
    if not regen then
        regen = CreateFrame("Frame")
        regen:SetScript("OnEvent", function(f)
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local run = pending
            pending = nil
            if run then xpcall(run, ns.ErrorHandler("rxp:dock")) end
        end)
    end
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Whether there is a classic guide window to dock: RXP loaded, and its beta
-- V2 window off (V2 hides these frames).
function R.CanDock()
    local rxp, F = Addon(), Window()
    if not (rxp and F and F.CurrentStepFrame and F.BottomFrame and F.GuideName and F.Footer
        and type(F.SetStepFrameAnchor) == "function") then
        return false
    end
    return not (rxp.v2 and type(rxp.v2.IsGuideWindowEnabled) == "function" and rxp.v2:IsGuideWindowEnabled())
end

-- For the theme: while docked its list box has no border or side padding
-- of its own (the dock's border goes round it).
function R.IsDocked()
    return dock ~= nil
end

-- For the theme: whether `step` is a step box in the column the dock hangs
-- under the list. RXP hangs each step box on the step frame or the box
-- above it; a tip step floats on UIParent instead and is not in the column.
function R.DockedStep(step)
    if not dock then return false end
    local _, rel = step:GetPoint(1)
    return rel ~= nil and rel ~= UIParent
end

-- The step list's height while docked (the Quest Tracker's Step List
-- Height). It is RXP's own window height, the frameHeight its Alt-drag
-- saves, so it also holds standalone: a height of our own would be
-- overwritten, since RXP sets the window's height from frameHeight on every
-- guide load and whenever it shows the list. The list lies 3 in from the
-- window's top and 14 from its bottom. Docked, the window hangs on the
-- tracker by its top only, so its height is free. In the tracker's units;
-- nil while not docked or the list is hidden.
local LIST_INSETS = 17
local LIST_MIN = 50     -- RXP's own floor when it shows the list
function R.ListHeight()
    local F = Window()
    local list = F and F.BottomFrame
    if not (dock and list and list:IsShown()) or folded then return nil end
    return math.floor(list:GetHeight() * list:GetEffectiveScale() / dock:GetEffectiveScale() + 0.5)
end

-- How far RXP's docked frames reach under the tracker's bottom edge, in the
-- tracker's units: the step list and, under it, the column's step boxes
-- (beside the tracker the boxes start at its top). 0 while not docked or
-- folded. For the Quest Tracker's Keep On Screen. Read from where the frames
-- are: all hang on the tracker, so it does not depend on its height.
function R.BelowHeight()
    local F = Window()
    if not (dock and F) or folded then return 0 end
    local s = dock:GetEffectiveScale()
    local base = dock:GetBottom()
    if not base then return 0 end
    base = base * s
    local low = base
    local function reach(f)
        local b = f:IsVisible() and f:GetBottom()
        if b then low = math.min(low, b * f:GetEffectiveScale()) end
    end
    if F.BottomFrame then reach(F.BottomFrame) end
    local CSF = F.CurrentStepFrame
    local pool = CSF and dockSide == "under" and CSF.framePool
    if type(pool) == "table" then
        for _, box in ipairs(pool) do
            local _, rel = box:GetPoint(1)
            if rel ~= nil and rel ~= UIParent then reach(box) end
        end
    end
    return math.ceil((base - low) / s)
end

-- Calls fn when R.BelowHeight changes: a step change resizes the boxes, the
-- list shows or hides, Step List Height. Checked after each placement of
-- the dock and each step box update (HookDock).
local belowFns, belowLast = {}, 0
function R.OnBelowChange(fn)
    for _, f in ipairs(belowFns) do if f == fn then return end end
    belowFns[#belowFns + 1] = fn
end
CheckBelow = function()
    if #belowFns == 0 then return end
    local h = R.BelowHeight()
    if h == belowLast then return end
    belowLast = h
    for _, fn in ipairs(belowFns) do xpcall(fn, ns.ErrorHandler("rxp:below")) end
end

-- In combat the height waits, as our other moves of RXP's frames; the last
-- value set wins.
local heightWait, heightWant
function R.SetListHeight(v)
    if InCombatLockdown() then
        heightWant = v
        if not heightWait then
            heightWait = CreateFrame("Frame")
            heightWait:SetScript("OnEvent", function(f)
                f:UnregisterEvent("PLAYER_REGEN_ENABLED")
                R.SetListHeight(heightWant)
            end)
        end
        heightWait:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local rxp, F = Addon(), Window()
    local p = rxp and rxp.settings and rxp.settings.profile
    if not (p and R.ListHeight()) then return end
    local h = math.max(LIST_MIN, v * dock:GetEffectiveScale() / F:GetEffectiveScale() + LIST_INSETS)
    p.frameHeight = h
    F:SetHeight(h)
    -- The rows and scroll range again on RXP's next update, as its own Show
    -- step list does.
    rxp.updateBottomFrame = true
    -- The step boxes hang on the list and moved with it, so the theme's pass
    -- runs again to put its boxes on whole pixels, as after an Alt-drag.
    R.Relayout()
end

-- The guide folded away under the tracker (a click on the Quest Tracker's
-- progress row): RXP's window, with the list, scroll bar and step boxes,
-- hangs FOLD_RISE above the tracker, past the top of the screen; the cog is
-- hidden (DockHover). Moved, not hidden: hiding RXPFrame pauses the guide
-- (its OnHide stops RXP's update tickers and quest automation), and a
-- hidden step box stops the OnUpdate scripts of its step's actions, such as
-- RXP's hearthstone bind and spirit healer confirms. RXP clamps its window
-- to the screen, so the clamp is off while folded and given back (the step
-- boxes': ClampSteps). A tip step RXP places freely stays where it is, and
-- the timer bars go up with the footer. Runs in combat too: no frame here
-- is secure.
function R.SetDockFolded(v)
    v = v == true
    if v == folded then return end
    folded = v
    if not dock then return end   -- R.Dock folds it as it docks
    xpcall(PlaceDocked, ns.ErrorHandler("rxp:fold"))
    -- The step boxes came down by another distance than the window, so the
    -- theme's boxes on them go on whole pixels again.
    if not v then R.Relayout() end
end

-- Docks the guide under `tracker` with the step boxes `gap` (tracker units)
-- under the list, and `border()` (the tracker's border setting) round
-- tracker and list; or places it again after the tracker's settings changed.
-- false when there is no classic guide window to dock (R.CanDock).
function R.Dock(tracker, gap, border, side, barSide)
    if not R.CanDock() then
        -- RXP's V2 window turned on while docked: the classic frames are
        -- hidden by RXP, and ours (the border) go with the dock.
        if dock then R.Undock() end
        return false
    end
    if InCombatLockdown() then
        AfterCombat(function() R.Dock(tracker, gap, border, side, barSide) end)
        return true
    end
    pending = nil
    local rxp, F = Addon(), Window()
    HookDock(F, F.CurrentStepFrame)
    local first = not dock
    if first then
        dockHome = {}
        for i = 1, F:GetNumPoints() do dockHome[i] = { F:GetPoint(i) } end
        dockSave = F.savePosition
        F.savePosition = false
    end
    dock, dockGap, dockBorder = tracker, gap, border
    dockSide = (side == "left" or side == "right") and side or "under"
    dockBarLeft = barSide == "left"
    DrawEdge()      -- before anything that can run the hooks above, which place it
    -- Hidden, not faded: RXP never shows them itself, and a Hide outlasts the
    -- theme's footer alpha (R.SetFooter). The version line and resize grip go
    -- with them; the cog, a child of RXPFrame, goes under the scroll bar.
    F.GuideName:Hide()
    F.Footer:Hide()
    R.ShiftScrollFrame(shiftWant)
    PlaceDocked()
    HookGuideHover()
    FitRows()       -- the bar is outside the list now: the rows reach its right edge
    -- RXP sizes the list's rows from the window's width when it redraws the
    -- list, which this flag asks for on its next update (as RXP's options
    -- do). The redraw sets every row's text and R.Dock runs on every setting
    -- change, so only when the window's width changed: at the dock, the
    -- tracker's Width, or RXP's Window Scale (RXP does not redraw for it).
    local width = tracker:GetWidth() * tracker:GetEffectiveScale() / F:GetEffectiveScale()
    if first or math.abs(width - dockWidth) >= 0.01 then
        dockWidth = width
        rxp.updateBottomFrame = true
    end
    -- The theme's pass runs inside RXP's step-box layout; its list box drops
    -- its border now (R.IsDocked).
    if first then R.Relayout() end
    return true
end

-- The guide window back as RXP has it: its saved place, loaded by RXP's own
-- loader (the docked place if none is saved), its step boxes on RXP's own
-- anchor, header, footer and cog where they were, the scroll bar where the
-- theme asks. Our anchors on RXP's frames are undone before the window
-- moves.
-- FIELD RESULT 2026-10-11 (0.6.0-dev38): with the window moved first, while
-- they still hung on the list, the game froze (ERROR #109, no Lua error);
-- undone first, it did not. Why is not known.
function R.Undock()
    if InCombatLockdown() then
        if dock or pending then AfterCombat(R.Undock) end
        return
    end
    pending = nil
    if not dock then return end
    dock = nil
    local rxp, F = Addon(), Window()
    local handler = ns.ErrorHandler("rxp:undock")
    -- Standalone nothing is folded: the window's own place and clamp come
    -- back below.
    folded = false
    if edge then
        edge:Hide()
        edge:ClearAllPoints()       -- R.Dock places it again (PlaceEdge)
    end
    local cog = F.Footer.cog
    if cog then
        if cogHome and cogHome[1] then
            cog:ClearAllPoints()
            for _, p in ipairs(cogHome) do cog:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        end
        cog:SetShown(cogWanted)
    end
    ThemeBar()
    FitRows()       -- the rows as wide as the theme's bar place allows
    R.ShiftScrollFrame(shiftWant)
    if F.CurrentStepFrame then ClampSteps(F.CurrentStepFrame) end
    F.GuideName:Show()
    F.Footer:Show()
    F.savePosition = dockSave
    F:ClearAllPoints()
    for _, p in ipairs(dockHome) do F:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    if clampHome then
        F:SetClampedToScreen(true)
        clampHome = nil
    end
    local s = rxp and rxp.settings
    if s and type(s.LoadFramePosition) == "function" then
        xpcall(function() s:LoadFramePosition("RXPFrame", F) end, handler)
    end
    -- LoadFramePosition puts back the size saved standalone; a height set
    -- while docked is only in frameHeight. RXP's next list update puts a
    -- guide with hidewindow at 28 and lifts a window under 28 to 28, so the
    -- height that stays is set here and the theme's pass below runs at it.
    local profile = s and s.profile
    local h = profile and profile.frameHeight
    if h then
        local _, guide = CurrentGuide()
        if guide and guide.hidewindow then h = 28 else h = math.max(h, 28) end
        F:SetHeight(h)
    end
    -- RXP's own order of the step boxes back (it chains them again only on
    -- its next step change).
    if F.CurrentStepFrame then OrderSteps(F.CurrentStepFrame, false) end
    xpcall(F.SetStepFrameAnchor, handler)       -- RXP's code, not ours
    if rxp then rxp.updateBottomFrame = true end     -- the rows back to the window's width (R.Dock)
    R.Relayout()                                     -- the theme's list box takes its border back
    CheckBelow()                                     -- Keep On Screen: nothing under the tracker now
end

-- The step boxes' column (RXP's CurrentStepFrame), for its pixel unit.
function R.StepColumn()
    local F = Window()
    return F and F.CurrentStepFrame
end

-- The step boxes' spacing and badges, for the theme (Step Gap, badge lift).
-- After every step change (UpdateText) RXP stacks its column's boxes 5
-- apart, each on the box above, and sets the column's height to match; it
-- puts each badge 7 in and 5 up from its box's top left once, at creation.
-- The theme's pass runs after UpdateText, so this writes the gap, the
-- column's height to match (the column hangs by its bottom over the header
-- in RXP's "top" orientation, so a different gap would push the boxes into
-- the header) and the badge's point. A tip box on UIParent is left alone.
-- `gap` and `lift` in RXP units; R.SpaceSteps(5, 0) is RXP's layout back.
-- Runs in combat too: no secure frames, and RXP moves these boxes in
-- combat itself. Writes only what differs: the pass runs on every step.
function R.SpaceSteps(gap, lift)
    stepGap = gap
    local F = Window()
    local CSF = F and F.CurrentStepFrame
    local pool = CSF and CSF.framePool
    if type(pool) ~= "table" then return end
    local inPool = {}
    for _, box in ipairs(pool) do inPool[box] = true end
    local total, n = 0, 0
    for _, box in ipairs(pool) do
        local point, rel = box:GetPoint(1)
        -- Shown only: boxes left over from a longer step list are hidden
        -- and not in RXP's height.
        if box:IsShown() and (rel == CSF or inPool[rel]) then
            if inPool[rel] and box:GetNumPoints() == 2 and point == "TOPLEFT" then
                Place2(box, "TOPLEFT", rel, "BOTTOMLEFT", 0, -gap, "TOPRIGHT", rel, "BOTTOMRIGHT", 0, -gap)
            end
            total, n = total + box:GetHeight(), n + 1
        end
        local num = box.number
        if num and num:GetNumPoints() == 1 then
            local p, r, rp = num:GetPoint(1)
            if p == "TOPLEFT" and r == box and rp == "TOPLEFT" and not At(num, 1, "TOPLEFT", box, "TOPLEFT", 7, 5 + lift) then
                num:ClearAllPoints()
                num:SetPoint("TOPLEFT", box, "TOPLEFT", 7, 5 + lift)
            end
        end
    end
    if n > 0 then
        local h = total + gap * (n - 1)
        if math.abs(CSF:GetHeight() - h) > 0.01 then CSF:SetHeight(h) end
    end
    if math.abs(lift - badgeLift) > 0.001 then
        badgeLift = lift
        if dock then xpcall(PlaceDocked, ns.ErrorHandler("rxp:steps")) end
    end
end
