-- ProseccoUI / Modules / Minimap.lua
-- Two panels on Ellesmere's minimap: the zone's name over it, the clock, FPS
-- and latency under it, each seamed to the map's border or a gap apart.
--
-- Nothing of Ellesmere's is moved or written on: the panels are our frames,
-- children of Blizzard's Minimap (which Ellesmere places), anchored to its
-- edges. The map's border is ours too (a round map gets none). Ellesmere's
-- own zone text, clock, FPS, border and buttons are turned off through its
-- settings (owned values, given back when the module goes off; Ellesmere
-- reads them at login, so a reload). Our buttons: MinimapButtons.lua.
--
-- Needs EllesmereUI Minimap. Off: panels hidden, no events, no ticker.

local _, ns = ...

-- Ellesmere's own zone text, clock and FPS readout off: ours replace them.
local OWNED = {
    { target = "minimap", key = "locationMode", value = "none", label = "Minimap: Zone Text" },
    { target = "minimap", key = "clockMode",    value = "none", label = "Minimap: Clock" },
    { target = "minimap", key = "showFPS",      value = false,  label = "Minimap: FPS / MS" },
    -- Ellesmere's own minimap buttons off (its Show Blizzard Elements): ours
    -- replace them. Its instance difficulty as text too.
    { target = "minimap", key = "hideTrackingButton", value = true,  label = "Minimap: Tracking" },
    { target = "minimap", key = "hideGameTime",       value = true,  label = "Minimap: Calendar" },
    { target = "minimap", key = "hideMail",           value = true,  label = "Minimap: Mail" },
    { target = "minimap", key = "hideRaidDifficulty", value = true,  label = "Minimap: Instance Difficulty" },
    { target = "minimap", key = "diffTextEnabled",    value = false, label = "Minimap: Instance Difficulty as Text" },
    { target = "minimap", key = "hideZoomButtons",    value = true,  label = "Minimap: Zoom +/- Icons" },
    -- Its border off: ours draws round the map and the panels (Draw). Size 0
    -- hides it; the exact-pixel size would win over the step size.
    { target = "minimap", key = "borderSize",         value = 0,     label = "Minimap: Border Size" },
    { target = "minimap", key = "borderSizePx",       value = false, label = "Minimap: Border Size (exact pixels)" },
}

local M = ns.RegisterModule("minimap", {
    title       = "Minimap",
    description = "Panels on Ellesmere's minimap: the zone over it, the clock, FPS and latency under it.",
    pages       = { "Minimap" },
    defaults    = {
        top = { show = true, height = 22, seam = true, gap = 4, size = 12 },
        bottom = { show = true, height = 22, seam = true, gap = 4, size = 12,
            clock = true, hour24 = true, serverTime = false, fps = true, latency = true },
        -- Each button: "always", "mouseover" (only while the mouse is over
        -- the map) or "never".
        buttons = { tracking = "mouseover", calendar = "mouseover", mail = "always",
            difficulty = "always", zoom = "mouseover" },
    },
    affects     = {
        "Ellesmere's minimap zone text, clock, FPS readout, border and its buttons (tracking, calendar, mail, difficulty, zoom) are turned off; ProseccoAdditions' panels, border and buttons show them instead.",
        "With a round (circle) map Ellesmere's ring goes too and ProseccoAdditions draws none: use Square or Rectangular.",
        "The values from before are put back when Minimap is turned off.",
    },
    affectsOff  = {
        "Ellesmere's minimap zone text, clock, FPS readout, border and buttons go back to what they were before (a value you changed in Ellesmere since then stays).",
    },
    reload      = true,
})

local function DB() return ns.db.modules.minimap end

local function WriteOwned() ns.TakeOwned("minimap", OWNED, "MINIMAP") end
local function RestoreOwned() ns.GiveBackOwned("minimap", "MINIMAP") end

-- Always the General page's border and header background, as the Chat
-- panels.
local BORDER = { useGlobal = true }
-- Size 0: ns.Border.Apply hides the frame's border.
local NO_BORDER = { style = "solid", size = 0, color = "000000", alpha = 1 }

-- Runtime only
local topPanel, bottomPanel
local joined, seamTop, seamBottom   -- joined border; the two seam lines
local host                  -- event frame while the module is on
local ticker                -- the bottom panel's 1 s update while shown
local running = false
local badgeL, badgeR        -- clock, FPS/MS on the map (Microbar below)
local badgeU                -- pixel size while badges are used, else nil

-- ---------------------------------------------------------------------------
-- Panels
-- ---------------------------------------------------------------------------

local function Text(parent)
    local fs = ns.Media.FontString(parent)
    local font, flags = ns.Ellesmere.Font()
    fs:SetFont(font, 12, flags)
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetWordWrap(false)
    return fs
end

-- The panels' texts always outlined.
local function SetSize(fs, size)
    local font = ns.Ellesmere.Font()
    fs:SetFont(font, tonumber(size) or 12, "OUTLINE")
end

-- Children of Minimap: they share its scale, follow it wherever Ellesmere
-- puts it, and take its opacity and visibility. Above the map's own level,
-- so with the seam our border line lies over Ellesmere's on the join.
local STRATA_ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG" }

local function NewPanel()
    local map = _G.Minimap
    local f = CreateFrame("Frame", nil, map)
    f.level = map:GetFrameLevel() + 2
    f:SetFrameLevel(f.level)
    f.tex = f:CreateTexture(nil, "BACKGROUND")
    f.tex:SetAllPoints(f)
    return f
end

-- Set below Draw (they call it and StopTicker).
local OnBottomHide, OnBottomShow

local function EnsureFrames()
    if topPanel then return end
    topPanel = NewPanel()
    topPanel.zone = Text(topPanel)
    topPanel.zone:SetPoint("LEFT", 4, 0)
    topPanel.zone:SetPoint("RIGHT", -4, 0)
    topPanel.zone:SetJustifyH("CENTER")
    bottomPanel = NewPanel()
    -- The panel goes with the map (a pet battle, Ellesmere's visibility):
    -- no updates while nothing shows them.
    bottomPanel:SetScript("OnHide", function() OnBottomHide() end)
    bottomPanel:SetScript("OnShow", function() OnBottomShow() end)
    bottomPanel.left = Text(bottomPanel)
    bottomPanel.left:SetPoint("LEFT", 6, 0)
    bottomPanel.left:SetJustifyH("LEFT")
    bottomPanel.right = Text(bottomPanel)
    bottomPanel.right:SetPoint("RIGHT", -6, 0)
    bottomPanel.right:SetJustifyH("RIGHT")
    badgeL = NewPanel()
    badgeL.text = Text(badgeL)
    badgeL.text:SetPoint("LEFT", 6, 0)
    badgeR = NewPanel()
    badgeR.text = Text(badgeR)
    badgeR.text:SetPoint("LEFT", 6, 0)
    for _, f in ipairs({ badgeL, badgeR }) do
        f:SetScript("OnHide", function() OnBottomHide() end)
        f:SetScript("OnShow", function() OnBottomShow() end)
    end
    -- Over the panels' backgrounds, under our buttons.
    local map = _G.Minimap
    joined = CreateFrame("Frame", nil, map)
    joined.level = map:GetFrameLevel() + 3
    joined:SetFrameLevel(joined.level)
    seamTop = CreateFrame("Frame", nil, map)
    -- One over the joined border's holder (+4), as Chat's seams.
    seamTop.level = map:GetFrameLevel() + 5
    seamTop:SetFrameLevel(seamTop.level)
    seamTop.tex = seamTop:CreateTexture(nil, "OVERLAY")
    seamBottom = CreateFrame("Frame", nil, map)
    seamBottom.level = map:GetFrameLevel() + 5
    seamBottom:SetFrameLevel(seamBottom.level)
    seamBottom.tex = seamBottom:CreateTexture(nil, "OVERLAY")
end

-- ---------------------------------------------------------------------------
-- Texts
-- ---------------------------------------------------------------------------

-- The zone's colour by its PvP state, as Blizzard colours its own zone text.
local PVP_COLOR = {
    sanctuary = { 0.41, 0.8, 0.94 }, arena = { 1, 0.1, 0.1 }, friendly = { 0.1, 1, 0.1 },
    hostile = { 1, 0.1, 0.1 }, contested = { 1, 0.7, 0 },
}
local ZONE_DEFAULT = { 1, 0.82, 0 }

local function UpdateZone()
    if not (topPanel and topPanel:IsShown()) then return end
    topPanel.zone:SetText(GetMinimapZoneText() or "")
    local c = PVP_COLOR[C_PvP.GetZonePVPInfo()] or ZONE_DEFAULT
    topPanel.zone:SetTextColor(c[1], c[2], c[3], 1)
end

local function ClockText(b)
    local h, m
    if b.serverTime then
        h, m = GetGameTime()
    else
        h, m = tonumber(date("%H")), tonumber(date("%M"))
    end
    if b.hour24 then return string.format("%02d:%02d", h, m) end
    local suffix = h >= 12 and " PM" or " AM"
    h = h % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d%s", h, m, suffix)
end

-- A badge as wide as its text (6 in from each side), on whole pixels;
-- hidden while it has nothing to show.
local function FitBadge(badge, text)
    badge.text:SetText(text)
    if text == "" then badge:SetAlpha(0) return end
    badge:SetAlpha(1)
    badge:SetWidth(math.ceil((badge.text:GetStringWidth() + 12) / badgeU) * badgeU)
end

-- Once a second while the bottom panel shows something: no event says when
-- the frame rate or the latency changes. Strings only when a value changed.
local lastLeft, lastRight
local function UpdateBottom()
    local b = DB().bottom
    local left = b.clock and ClockText(b) or ""
    local right = ""
    if b.fps then right = math.floor(GetFramerate() + 0.5) .. " fps" end
    if b.latency then
        local _, _, home, world = GetNetStats()
        right = (right ~= "" and right .. "  " or "") .. math.max(home or 0, world or 0) .. " ms"
    end
    if left ~= lastLeft then
        lastLeft = left
        if badgeU then FitBadge(badgeL, left) else bottomPanel.left:SetText(left) end
    end
    if right ~= lastRight then
        lastRight = right
        if badgeU then FitBadge(badgeR, right) else bottomPanel.right:SetText(right) end
    end
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        xpcall(UpdateBottom, ns.ErrorHandler("minimap:tick"))
    end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- One panel against the map's visible top ("top") or bottom edge. Seamed
-- (`joined`), it touches the map and the joined border draws round both;
-- otherwise it stands Gap away with its own border.
local function Place(panel, side, cfg, inset, u, joinedSeam)
    local Snap = ns.Border.Snap
    local map = _G.Minimap
    local off = joinedSeam and 0 or Snap((tonumber(cfg.gap) or 0) * u, u)
    panel:ClearAllPoints()
    if side == "top" then
        panel:SetPoint("BOTTOMLEFT", map, "TOPLEFT", 0, off - inset)
        panel:SetPoint("BOTTOMRIGHT", map, "TOPRIGHT", 0, off - inset)
    else
        panel:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, inset - off)
        panel:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, inset - off)
    end
    panel:SetHeight(Snap((tonumber(cfg.height) or 22) * u, u))
    local hex, a = ns.BackgroundColor(true, "headerBackground")
    local r, g, b = ns.HexToRGB(hex)
    ns.PaintHeader(panel.tex, r, g, b, a)
    ns.Border.Apply(panel, joinedSeam and NO_BORDER or BORDER)
    panel:Show()
end

-- The clock and FPS/MS as two small badges in the map's bottom corners while
-- the Microbar takes the bottom panel's place. `bottom`: from the Minimap
-- frame's bottom to the map's visible bottom plus the border. Their widths
-- follow the text (UpdateBottom).
local function PlaceBadge(badge, side, cfg, bottom, line, u)
    local Snap = ns.Border.Snap
    -- 4 px from the border's line.
    local pad = 4 * u
    badge:ClearAllPoints()
    if side == "left" then
        badge:SetPoint("BOTTOMLEFT", _G.Minimap, "BOTTOMLEFT", Snap(line + pad, u), Snap(bottom + pad, u))
    else
        badge:SetPoint("BOTTOMRIGHT", _G.Minimap, "BOTTOMRIGHT", -Snap(line + pad, u), Snap(bottom + pad, u))
    end
    badge:SetHeight(Snap(((tonumber(cfg.size) or 12) + 8) * u, u))
    local hex, a = ns.BackgroundColor(true, "headerBackground")
    local r, g, b = ns.HexToRGB(hex)
    ns.PaintHeader(badge.tex, r, g, b, a)
    ns.Border.Apply(badge, BORDER)
    badge:Show()
end

-- The seam line on the top edge of `rel` (the map's visible top, or the
-- bottom panel), as the Chat's.
local function PlaceSeam(line, shown, rel, y)
    if not shown then line:Hide() return end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, y)
    line:SetPoint("TOPRIGHT", rel, "TOPRIGHT", 0, y)
    line:SetHeight(1)
    line:Show()
    ns.Border.Seam(line.tex, line, BORDER)
end

local function Draw()
    local look = ns.Ellesmere.MinimapLook()
    if not look then return end
    local map = _G.Minimap
    EnsureFrames()
    local d = DB()
    local u = ns.Ellesmere.PixelUnit(map)
    local h = map:GetHeight()
    if not h or issecretvalue(h) then return end
    -- The rectangular map's hidden top and bottom (MinimapInset).
    local inset = ns.Ellesmere.MinimapInset(look, h, u)
    -- A round map has no straight edge to join or border: the panels keep
    -- their gap and the map Ellesmere's look.
    -- One strata over the map's: the rectangular map's hidden top and bottom
    -- strips still carry other addons' pins (Questie's, via HereBeDragons),
    -- which a frame level alone does not cover. Our frames only.
    local strata = STRATA_ABOVE[map:GetFrameStrata()] or "MEDIUM"
    -- The border and seams one strata higher still, the Microbar's strata when
    -- it sits seamed under the map; its background is the bottom panel, in the
    -- panels' strata.
    -- FIELD RESULT 2026-10-12 (dev51-dev53): with the bar's own opaque
    -- background the border's inner line was covered on the bar.
    local lineStrata = STRATA_ABOVE[strata] or strata
    for _, f in ipairs({ topPanel, bottomPanel, badgeL, badgeR, joined, seamTop, seamBottom }) do
        local want = (f == joined or f == seamTop or f == seamBottom) and lineStrata or strata
        if f:GetFrameStrata() ~= want then
            f:SetFrameStrata(want)
            f:SetFrameLevel(f.level)
        end
    end
    local t, b = d.top, d.bottom
    -- The Microbar under the map instead of the bottom panel (a Core setting
    -- both modules read).
    local badge = b.show and ns.db.global.microbarOnMinimap == true and ns.IsModuleEnabled("volume")
    -- A badge with nothing to show is not drawn.
    local hideBadge = badge and not (b.clock or b.fps or b.latency)
    local tSeam = t.show and t.seam and not look.round
    local bSeam = b.show and b.seam and not look.round and not badge
    local line = look.round and 0 or (tonumber(ns.Border.Resolve(BORDER).size) or 0) * u
    if t.show then
        Place(topPanel, "top", t, inset, u, tSeam)
        SetSize(topPanel.zone, t.size)
        UpdateZone()
    else
        topPanel:Hide()
    end
    -- The Microbar seamed under the map: our border goes round it too, the seam
    -- line lies on the map's bottom, and the bar draws no border. Its height
    -- comes through Core.
    local barH = ns.MinimapBar()      -- nil unless seamed under the map
    barH = barH and ns.Border.Snap(barH / map:GetEffectiveScale(), u) or nil
    badgeU = badge and u or nil
    if barH then
        -- Behind the bar, the bottom panel's background in its place; the bar
        -- draws none. One strata under the bar, which sits in the border's.
        bottomPanel:ClearAllPoints()
        bottomPanel:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, inset)
        bottomPanel:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, inset)
        bottomPanel:SetHeight(barH)
        local hex, a = ns.BackgroundColor(true, "headerBackground")
        local r, g, bl = ns.HexToRGB(hex)
        ns.PaintHeader(bottomPanel.tex, r, g, bl, a)
        ns.Border.Apply(bottomPanel, NO_BORDER)
        bottomPanel.left:SetText(""); bottomPanel.right:SetText("")
        bottomPanel:Show()
    end
    if badge and not hideBadge then
        if not barH then bottomPanel:Hide() end
        -- The border's visible line: a solid border's size; a textured
        -- one draws a thin line in a wide edge.
        -- FIELD RESULT 2026-10-12 (dev51): Pixels at size 16 showed a
        -- 2 px line, and badges placed by the size stood 16 px in.
        local edge = look.round and 0 or ns.Ellesmere.IsTexturedBorder(ns.Border.Resolve(BORDER).style) and 2 * u or line
        PlaceBadge(badgeL, "left", b, inset + edge, edge, u)
        PlaceBadge(badgeR, "right", b, inset + edge, edge, u)
        SetSize(badgeL.text, b.size)
        SetSize(badgeR.text, b.size)
        lastLeft, lastRight = nil, nil
        UpdateBottom()
    elseif b.show and not badge then
        badgeL:Hide(); badgeR:Hide()
        Place(bottomPanel, "bottom", b, inset, u, bSeam)
        SetSize(bottomPanel.left, b.size)
        SetSize(bottomPanel.right, b.size)
        lastLeft, lastRight = nil, nil
        UpdateBottom()
    else
        if not barH then bottomPanel:Hide() end
        badgeL:Hide(); badgeR:Hide()
    end
    -- The map's border is ours (Ellesmere's is turned off): one border round
    -- the map's visible part and the panels seamed to it, a seam line at each
    -- join.
    if look.round then
        joined:Hide()
        seamTop:Hide()
        seamBottom:Hide()
    else
        joined:ClearAllPoints()
        if tSeam then
            joined:SetPoint("TOPLEFT", topPanel, "TOPLEFT")
            joined:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT")
        else
            joined:SetPoint("TOPLEFT", map, "TOPLEFT", 0, -inset)
            joined:SetPoint("TOPRIGHT", map, "TOPRIGHT", 0, -inset)
        end
        if bSeam then
            joined:SetPoint("BOTTOMLEFT", bottomPanel, "BOTTOMLEFT")
            joined:SetPoint("BOTTOMRIGHT", bottomPanel, "BOTTOMRIGHT")
        elseif barH then
            joined:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 0, inset - barH)
            joined:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 0, inset - barH)
        else
            joined:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 0, inset)
            joined:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 0, inset)
        end
        ns.Border.Apply(joined, BORDER)
        joined:Show()
        PlaceSeam(seamTop, tSeam, map, -inset)
        if barH then
            PlaceSeam(seamBottom, true, map, -(h - inset))
        else
            PlaceSeam(seamBottom, bSeam, bottomPanel, 0)
        end
    end
    local shows = bottomPanel:IsVisible() or badgeL:IsVisible()
    if b.show and (b.clock or b.fps or b.latency) and shows then StartTicker() else StopTicker() end
    M.SetHoverInset(inset)
    M.LayoutButtons(inset + line, u)
end

function OnBottomHide() StopTicker() end
function OnBottomShow() if running then Draw() end end

local function HidePanels()
    StopTicker()
    if topPanel then
        topPanel:Hide(); bottomPanel:Hide(); badgeL:Hide(); badgeR:Hide()
        joined:Hide(); seamTop:Hide(); seamBottom:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local REDRAW = { PLAYER_ENTERING_WORLD = true, UI_SCALE_CHANGED = true, DISPLAY_SIZE_CHANGED = true }

local function OnEvent(_, event)
    if REDRAW[event] then
        -- A new scale moves the pixel grid; at login Ellesmere places and
        -- sizes the map after our first Apply.
        Draw()
    else
        UpdateZone()
    end
end

local function RedrawIfRunning() if running then Draw() end end

function M:Enable()
    if not ns.Ellesmere.MinimapLook() then
        ns.Print("Minimap: turn on EllesmereUI Minimap; this module adds panels to it.")
        return false
    end
    running = true
    if not host then
        host = CreateFrame("Frame")
        host:SetScript("OnEvent", function(_, event)
            xpcall(function() OnEvent(_, event) end, ns.ErrorHandler("minimap:" .. event))
        end)
    end
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        host:RegisterEvent(e)
    end
    -- Ellesmere redraws its map when its menu closes (size, shape, border);
    -- the panels follow then (a public registration, once, gated here).
    ns.Ellesmere.OnMenuClosed(RedrawIfRunning)
    -- The Microbar under the map changed height.
    ns.OnMinimapBar(RedrawIfRunning)
    M.ButtonsOn(RedrawIfRunning)
end

-- None of our frames is protected and the map is only read, so this also
-- runs in combat.
function M:Apply()
    if running then Draw() end
end

function M:Disable()
    running = false
    RestoreOwned()
    if host then host:UnregisterAllEvents() end
    HidePanels()
    M.ButtonsOff()
end

function M:SwitchedOn() WriteOwned() end

-- For the simulator's minimap test.
function M.Panels() return topPanel, bottomPanel, badgeL, badgeR, joined end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------

function M:BuildPage(pageName, parent, y, W)
    local _, h
    local function changed() ns.Apply() end
    local function Slider(t, text, tip, key, minV, maxV, disabled)
        return { type = "slider", text = text, min = minV, max = maxV, step = 1, tooltip = tip,
            disabled = disabled, disabledTooltip = disabled and "Not used with Attached on." or nil,
            getValue = function() return tonumber(t()[key]) or minV end,
            setValue = function(v) t()[key] = v; changed() end }
    end
    local function Toggle(t, text, tip, key)
        return { type = "toggle", text = text, tooltip = tip,
            getValue = function() return t()[key] == true end,
            setValue = function(v) t()[key] = v and true or false; changed(); ns.Ellesmere.RefreshPage() end }
    end
    local function T() return DB().top end
    local function B() return DB().bottom end

    if not ns.Ellesmere.MinimapLook() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "This module adds panels to EllesmereUI Minimap, which is not loaded." }); y = y - h
    end

    _, h = W:SectionHeader(parent, "ELLESMERE SETTINGS", y); y = y - h
    local names = {}
    for _, o in ipairs(OWNED) do names[#names + 1] = o.label end
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Minimap turns off Ellesmere's zone text, clock, FPS, border and buttons, so they do not show twice." }); y = y - h
    -- Two short rows: Ellesmere's labels never wrap.
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Turned one on again in Ellesmere's menu? Set Ellesmere Values turns them off (reloads the UI)." }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Set Ellesmere Values", width = 180,
          disabled = function() return not (ns.IsModuleEnabled("minimap") and ns.Ellesmere.MinimapLook()) end,
          disabledTooltip = "This option needs Minimap on and EllesmereUI Minimap loaded.",
          onClick = function()
              ns.Ellesmere.Confirm({
                  title = "Minimap: set Ellesmere values",
                  message = "Turn these off again in Ellesmere's minimap, so only ProseccoAdditions' panels and buttons show them?\n- "
                      .. table.concat(names, "\n- "),
                  confirmText = "Set and reload",
                  reload = true,
                  onConfirm = WriteOwned,
              })
          end },
        { type = "spacer" }); y = y - h

    _, h = W:SectionHeader(parent, "TOP PANEL", y); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle(T, "Top Panel", "A panel over the map with the zone's name, in the zone's PvP colour.", "show"),
        Toggle(T, "Attached", "On: one border round the panel and the map, with a seam line between them. Off: Gap between them. A round map always has the gap.", "seam")); y = y - h
    _, h = W:DualRow(parent, y,
        Slider(T, "Height", "Pixels.", "height", 12, 48),
        Slider(T, "Gap", "Pixels between the panel and the map.", "gap", 0, 20, function() return DB().top.seam == true end)); y = y - h
    _, h = W:DualRow(parent, y,
        Slider(T, "Text Size", "The zone's name.", "size", 8, 24),
        { type = "spacer" }); y = y - h

    _, h = W:SectionHeader(parent, "BOTTOM PANEL", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "With Microbar's \"On the Minimap\" on, the bar takes this panel's place and the clock, FPS and latency show as a small badge on the map." }); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle(B, "Bottom Panel", "A panel under the map with the clock on the left and FPS and latency on the right.", "show"),
        Toggle(B, "Attached", "On: one border round the panel and the map, with a seam line between them. Off: Gap between them. A round map always has the gap.", "seam")); y = y - h
    _, h = W:DualRow(parent, y,
        Slider(B, "Height", "Pixels.", "height", 12, 48),
        Slider(B, "Gap", "Pixels between the panel and the map.", "gap", 0, 20, function() return DB().bottom.seam == true end)); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle(B, "Clock", "The time, on the left.", "clock"),
        Toggle(B, "24-Hour Clock", "Off: 12-hour with AM/PM.", "hour24")); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle(B, "Server Time", "Off: your computer's time.", "serverTime"),
        Slider(B, "Text Size", "The clock, FPS and latency.", "size", 8, 24)); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle(B, "FPS", "Frames per second, updated every second.", "fps"),
        Toggle(B, "Latency", "Milliseconds, the higher of home and world, updated every second.", "latency")); y = y - h

    _, h = W:SectionHeader(parent, "BUTTONS", y); y = y - h
    local MODES = { always = "Always", mouseover = "Mouseover", never = "Never" }
    local MODE_ORDER = { "always", "mouseover", "never" }
    local function Mode(e)
        if not e then return { type = "spacer" } end
        return { type = "dropdown", text = e.label, values = MODES, order = MODE_ORDER,
            tooltip = "Mouseover: shown only while the mouse is over the map.",
            getValue = function() return DB().buttons[e.key] end,
            setValue = function(v) DB().buttons[e.key] = v; changed() end }
    end
    local list = M.BUTTON_SETTINGS
    for i = 1, #list, 2 do
        _, h = W:DualRow(parent, y, Mode(list[i]), Mode(list[i + 1])); y = y - h
    end

    if not ns.IsModuleEnabled("minimap") then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Minimap is off: turn it on under Modules on the General page." }); y = y - h
    end
    return y
end
