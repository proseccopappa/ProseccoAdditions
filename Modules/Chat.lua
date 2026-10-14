-- ProseccoAdditions / Modules / Chat.lua
-- Our panels around Ellesmere's chat: one around the chat text, one around
-- the tab row, with a gap between them. Ellesmere keeps every chat function;
-- its message frame, tabs, edit box, sidebar and fade are not touched.
--
-- Rules: nothing is written to ChatFrame1's position or size, no Ellesmere
-- function is replaced or hooked, and nothing of ours is put on a Blizzard
-- chat frame.
--
-- Placement: Ellesmere's chat frames are anonymous, so our panels follow
-- Blizzard's named frames: ChatFrame1 (the text rect) and GeneralDockManager
-- (Blizzard's invisible tab row, which Ellesmere's tabs stand on). Tab Gap
-- rewrites only the offset of the row's anchors, so it stays in Blizzard's
-- anchor chain. Never in combat: a docked whisper tab is protected then.
--
-- Owned Ellesmere settings: Background Opacity 0 and Hide Borders (our
-- panels replace them), tab backgrounds at 0 and no active tab underline
-- (the tabs stand on our tab panel), and Tabs Inside Chat Panel off (with it
-- on, the tabs do not follow the tab row). Written when the module goes on
-- or with "Set Ellesmere Values", given back when it goes off, never
-- rewritten at login.
--
-- Typing: while an edit box is shown it sits over the tab panel, on a cover
-- that hides the tabs. EventRegistry's ChatFrame.OnEditBoxShow/Hide say
-- when; a script hook on the edit box would taint the chat type every send
-- reads back. A session ends only when the box hides. Made for Blizzard's
-- Chat Style "Classic"; with "IM Style" the box is always shown.
--
-- Off: no frames, no events. Our panels hide and the tab row and edit boxes
-- go back without a reload; Ellesmere's background and borders come back
-- after a reload.

local _, ns = ...

local OWNED = {
    { target = "chat", key = "bgAlpha",            value = 0,     label = "Chat: Background Opacity" },
    { target = "chat", key = "hideBorders",        value = true,  label = "Chat: Hide Borders" },
    { target = "chat", key = "extendBgBehindTabs", value = false, label = "Chat: Tabs Inside Chat Panel" },
    -- The tabs stand on our tab panel with no background or line of their own.
    { target = "chat", key = "tabBackgroundColor.a",       value = 0,     label = "Chat: Tab Background opacity" },
    { target = "chat", key = "tabBackgroundColorActive.a", value = 0,     label = "Chat: Active Tab Background opacity" },
    { target = "chat", key = "activeUnderline",            value = false, label = "Chat: Active Tab Underline" },
}

local M = ns.RegisterModule("chat", {
    title       = "Chat",
    description = "Panels around Ellesmere's chat and its tabs, with an adjustable gap between them.",
    pages       = { "Chat" },
    defaults    = {
        -- Ellesmere stretches the first tab 10 UI units left of the text; 11 px
        -- holds it inside the tab panel.
        padding = 11,               -- px our chat panel reaches past the text on the sides and below
        topPadding = 0,             -- px it reaches above the text
        tabGap = 8,                 -- px between the chat panel and the tab panel
        seam = false,               -- one border round both panels, a seam line where they meet
        -- No colours or border of its own: the chat panel takes the Global
        -- Background, the tab panel and edit box the Global Header Background, all
        -- the Global Border. Old profiles may still hold chatColor, tabsColor,
        -- border and useGlobalBackground; they are unused.
    },
    affects     = {
        "Ellesmere's chat Background Opacity and both tab background opacities are set to 0, Hide Borders is turned on, and Tabs Inside Chat Panel and the active tab underline are turned off; ProseccoAdditions draws its own panels.",
        "Blizzard's tab row above the chat is moved by the Tab Gap setting.",
        "While you type, the chat's edit box is shown over the tabs instead of under the chat.",
        "The values from before are put back when Chat is turned off.",
    },
    affectsOff  = {
        "Ellesmere's chat background, borders, tab backgrounds, Tabs Inside Chat Panel and tab underline go back to what they were before Chat was turned on (a value you changed in Ellesmere since then stays).",
        "The tab row and the edit box go back to Blizzard's and Ellesmere's places, and ProseccoAdditions' panels are removed.",
    },
    reload      = true,
})

local function DB() return ns.db.modules.chat end

local function WriteOwned() ns.TakeOwned("chat", OWNED, "CHAT") end
local function RestoreOwned() ns.GiveBackOwned("chat", "CHAT") end

-- ---------------------------------------------------------------------------
-- Blizzard's tab row
-- ---------------------------------------------------------------------------

local dockY0                -- the row's offset before our first write (runtime only)
local dockPending = false   -- a write waits for the end of combat
local host                  -- event frame while the module is on

-- Blizzard's two anchors, read back: rel and the offset when the row hangs
-- by its bottom corners off the top corners of one region (as
-- FCFDock_SetPrimary sets it); nil otherwise, and then the row is left
-- alone, so a row someone else placed is never fought over. Only the offset
-- is ever rewritten.
-- FIELD RESULT 2026-10-08 (build 70245): on Forever the row hangs off
-- ChatFrame1Background with offset 0, not off ChatFrame1 with 3 as in retail.
local function DockAnchor(gdm)
    if gdm:GetNumPoints() ~= 2 then return nil end
    local anchor, y
    for i = 1, 2 do
        local point, rel, relPoint, x, py = gdm:GetPoint(i)
        -- Anchors can read back secret in restricted content (Ellesmere guards
        -- the same reads); then the row is left as it is.
        if issecretvalue(x) or issecretvalue(py) then return nil end
        if not rel or x ~= 0 then return nil end
        if not ((point == "BOTTOMLEFT" and relPoint == "TOPLEFT") or (point == "BOTTOMRIGHT" and relPoint == "TOPRIGHT")) then
            return nil
        end
        if anchor and (rel ~= anchor or py ~= y) then return nil end
        anchor, y = rel, py
    end
    return anchor, y
end

-- Puts the row's bottom edge at `bottom` (screen units), or back where
-- Blizzard had it (nil). In combat the write waits for PLAYER_REGEN_ENABLED,
-- which places it from the settings at that time.
local function PlaceDock(bottom)
    local gdm = _G.GeneralDockManager
    if not gdm then return end
    if InCombatLockdown() then
        dockPending = true
        if host then host:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    local rel, now = DockAnchor(gdm)
    if rel == nil then
        ns.Log("CHAT", "tab row not anchored as Blizzard leaves it; left alone")
        return
    end
    dockY0 = dockY0 or now
    local y = dockY0
    if bottom then
        local relTop = rel:GetTop()
        if not relTop or issecretvalue(relTop) then return end      -- see DockAnchor
        y = bottom - relTop
    end
    if math.abs(now - y) < 0.001 then return end
    gdm:SetPoint("BOTTOMLEFT", rel, "TOPLEFT", 0, y)
    gdm:SetPoint("BOTTOMRIGHT", rel, "TOPRIGHT", 0, y)
end

-- The row's scroll child. Blizzard centres the tabs of user-made windows
-- (ChatFrame3 and up) on it 1 unit down, while General and Combat Log stand
-- on the row's bottom edge, so those tabs (and Ellesmere's, which hang on
-- them) stand 1 unit higher. FIELD RESULT 2026-10-09 (build not noted): such
-- a tab's centre is the 26-tall child's centre minus 1.
-- The fix: the child 28 tall; its top stays, so the tabs move down 1.
-- Blizzard sets the height only in XML, so nothing writes it back. Only
-- while Ellesmere's chat is 9.4, so the fix turns itself off when Ellesmere
-- updates, and only when the height is Blizzard's 26 (another value is
-- someone else's). Out of combat: the child parents docked whisper tabs,
-- protected then; in combat it waits with the row. 26 back when off.
local CHILD_HOME, CHILD_FIX = 26, 28
local CHILD_VERSION = "9.4"
local function PlaceScrollChild(on)
    local child = _G.GeneralDockManagerScrollFrameChild
    if not child then return end
    local h = child:GetHeight()
    if issecretvalue(h) then return end                 -- see DockAnchor
    local want
    if on and ns.Ellesmere.ChatVersion() == CHILD_VERSION and math.abs(h - CHILD_HOME) < 0.01 then
        want = CHILD_FIX
    elseif not on and math.abs(h - CHILD_FIX) < 0.01 then
        want = CHILD_HOME
    end
    if not want then return end
    if InCombatLockdown() then
        dockPending = true
        if host then host:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    child:SetHeight(want)
end

-- ---------------------------------------------------------------------------
-- Our panels
-- ---------------------------------------------------------------------------

local chatPanel, tabsPanel, cover
local coverLift = 0         -- how far the cover's bottom stands above the tab panel's (a textured seam)
local joined, seamLine      -- with the seam: the border round both panels, and the line between
local active                -- the edit box over the tabs now (runtime)
local Seat                  -- defined with the edit box code below
local seat                  -- where an edit box goes: offsets off ChatFrame1, set by Draw (runtime)

-- BACKGROUND strata: below the chat frame and Ellesmere's panel (LOW) and
-- tab strip (MEDIUM), so text and tabs draw on top. Not parented to
-- ChatFrame1: it is hidden whenever another docked tab is selected.
local function NewPanel()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    f:EnableMouse(false)
    f.tex = f:CreateTexture(nil, "BACKGROUND")
    f.tex:SetAllPoints(f)
    return f
end

local function Paint(f, hex, alpha, header)
    local r, g, b = ns.HexToRGB(hex)
    if header then
        ns.PaintHeader(f.tex, r, g, b, tonumber(alpha) or 0.65)
    else
        f.tex:SetColorTexture(r, g, b, tonumber(alpha) or 0.65)
    end
end

local function px(v) return tonumber(v) or 0 end

-- Size 0: ns.Border.Apply hides the panel's own border.
local NO_BORDER = { style = "solid", size = 0, color = "000000", alpha = 1 }
-- Always the General page's border.
local BORDER = { useGlobal = true }

-- Assumed: ChatFrame1 has UIParent's scale (Blizzard and Ellesmere set none
-- on it), so its units, UIParent's and those of our panels and the tab row
-- are the same.
local function Draw()
    local cf = _G.ChatFrame1
    if not (cf and chatPanel) then return end
    local left, right, top, bottom = cf:GetLeft(), cf:GetRight(), cf:GetTop(), cf:GetBottom()
    if not (left and right and top and bottom) then return end      -- not laid out yet: PLAYER_ENTERING_WORLD draws
    -- The chat frame's rect can read back secret in restricted content;
    -- then everything stays where it is until the next draw.
    if issecretvalue(left) or issecretvalue(right) or issecretvalue(top) or issecretvalue(bottom) then return end
    local d = DB()
    local u = ns.Ellesmere.PixelUnit(cf)
    local Snap = ns.Border.Snap
    -- With the seam the panels meet: no gap, the seam line is the join.
    local pad, topPad, gap = px(d.padding) * u, px(d.topPadding) * u, d.seam and 0 or px(d.tabGap) * u
    -- Snapped to whole pixels: ChatFrame1 is wherever Edit Mode or Ellesmere put
    -- it, and a panel edge between two pixels draws a blurred border.
    ns.Border.Outside(chatPanel, cf, 0, -pad, -pad, -topPad, -pad)
    -- The tab panel hangs off ChatFrame1's top edge only, like the tab row,
    -- so the two stay together when the chat is resized. Its height is
    -- Ellesmere's tab height (EllesmereUI style; the page warns about the
    -- stock styles).
    local tabsBottom = Snap(top + topPad + gap, u)
    local tabsTop = Snap(tabsBottom + (ns.Ellesmere.ChatTabHeight() or 24), u)
    local dx1, dx2 = Snap(left - pad, u) - left, Snap(right + pad, u) - right
    tabsPanel:ClearAllPoints()
    tabsPanel:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", dx1, tabsBottom - top)
    tabsPanel:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", dx2, tabsBottom - top)
    tabsPanel:SetHeight(tabsTop - tabsBottom)
    Paint(chatPanel, ns.BackgroundColor(true, "background"))
    local hHex, hA = ns.BackgroundColor(true, "headerBackground")
    Paint(tabsPanel, hHex, hA, true)
    if d.seam then
        -- One border round both, like the Damage Meter's Header Seam: the
        -- panels lose their own and the seam line lies over the joined
        -- border's sides.
        ns.Border.Apply(chatPanel, NO_BORDER)
        ns.Border.Apply(tabsPanel, NO_BORDER)
        joined:ClearAllPoints()
        joined:SetPoint("TOPLEFT", tabsPanel, "TOPLEFT")
        joined:SetPoint("BOTTOMRIGHT", chatPanel, "BOTTOMRIGHT")
        ns.Border.Apply(joined, BORDER)
        joined:Show()
        seamLine:ClearAllPoints()
        seamLine:SetPoint("TOPLEFT", chatPanel, "TOPLEFT")
        seamLine:SetPoint("TOPRIGHT", chatPanel, "TOPRIGHT")
        seamLine:SetHeight(1)
        seamLine:Show()
        local _, raise, thick = ns.Border.Seam(seamLine.tex, seamLine, BORDER)
        -- With a textured seam the cover (the edit box's frame) ends a
        -- little above the join, so its bottom line lies on the seam's.
        -- A solid seam lies inside the tab panel like a border line.
        -- FIELD RESULT 2026-10-12 (Pixels, size 16): the seam's line lies
        -- an eighth of the art's thickness under `raise`.
        if thick and ns.Ellesmere.BorderSeamArt(ns.Border.Resolve(BORDER).style) then
            local es = seamLine:GetEffectiveScale()
            coverLift = math.max(0, raise - ns.Ellesmere.SnapForES(thick / 8, es))
        else
            coverLift = 0
        end
    else
        coverLift = 0
        ns.Border.Apply(chatPanel, BORDER)
        ns.Border.Apply(tabsPanel, BORDER)
        joined:Hide()
        seamLine:Hide()
    end
    chatPanel:Show()
    tabsPanel:Show()
    -- The tabs stand on the row's bottom edge: put it on our tab panel's.
    PlaceDock(tabsBottom)
    PlaceScrollChild(true)
    seat = seat or {}
    seat.x1, seat.x2, seat.y = dx1, dx2, tabsTop - top
    -- The box is as tall as its cover. The cover is the Global Header
    -- Background at full opacity, so the tabs do not show through the box.
    seat.h = tabsTop - tabsBottom - coverLift
    cover:ClearAllPoints()
    cover:SetPoint("TOPLEFT", tabsPanel, "TOPLEFT")
    cover:SetPoint("BOTTOMRIGHT", tabsPanel, "BOTTOMRIGHT", 0, coverLift)
    Paint(cover, (ns.BackgroundColor(true, "headerBackground")), 1, true)
    ns.Border.Apply(cover, BORDER)
    if active then Seat(active) end         -- a setting changed while typing
end

-- ---------------------------------------------------------------------------
-- The edit box over the tabs
-- ---------------------------------------------------------------------------

local before = setmetatable({}, { __mode = "k" })   -- edit box -> its points and strata before ours

-- The docked windows' boxes only: ChatFrame1-10. Temporary whisper windows
-- (11+) are never touched (their state is secret), and an undocked window
-- keeps its box.
local function OurBox(eb)
    if not eb or type(eb.GetName) ~= "function" then return false end
    local n = eb:GetName()
    local i = n and tonumber(n:match("^ChatFrame(%d+)EditBox$"))
    if not (i and i <= 10) then return false end
    local cf = _G["ChatFrame" .. i]
    return cf == _G.ChatFrame1 or (cf and cf.isDocked) and true or false
end

-- Anchored to ChatFrame1 (docked frames share its rect), not to our frame,
-- so the box stays in Blizzard's anchor chain. Ellesmere's full chat pass
-- puts the box back under the chat; boxWatch seats it again after that.
-- HIGH strata: above Ellesmere's tab strip (MEDIUM 100) and our cover
-- (MEDIUM 110).
function Seat(eb)
    local cf = _G.ChatFrame1
    if not before[eb] then
        local pts = {}
        for i = 1, eb:GetNumPoints() do pts[i] = { eb:GetPoint(i) } end
        before[eb] = { points = pts, strata = eb:GetFrameStrata(), h = eb:GetHeight() }
    end
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "TOPLEFT", seat.x1, seat.y)
    eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", seat.x2, seat.y)
    eb:SetHeight(seat.h)
    eb:SetFrameStrata("HIGH")
end

local function Unseat(eb)
    local b = before[eb]
    if not b then return end
    before[eb] = nil
    eb:ClearAllPoints()
    for _, p in ipairs(b.points) do eb:SetPoint(unpack(p)) end
    eb:SetHeight(b.h)
    eb:SetFrameStrata(b.strata)
end

-- Ellesmere's full chat pass (ApplyInputPosition) anchors every box under
-- its chat again one tick after these events (FIELD RESULT 2026-10-08
-- (build 70245): a whisper while typing dropped the box under the chat). We
-- seat it again two ticks later, so we run after Ellesmere whichever handler
-- ran first. Not a hook on the box's SetPoint: Blizzard's whisper code moves
-- and reads the box in secure execution, and a hook there taints it.
-- Registered only while a box is seated; the box can stand under the chat
-- for those two ticks.
local BOX_EVENTS = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
    "PLAYER_ENTERING_WORLD",
}
local boxWatch, reseatQueued

local function Reseat()
    xpcall(function()
        if active and seat and active:IsShown() then Seat(active) end
    end, ns.ErrorHandler("chat:reseat"))
end
-- The flag clears here, one tick in: an event from now on starts a new
-- chain, so it still lands after the Ellesmere pass that event queues.
local function ReseatNextTick()
    reseatQueued = false
    C_Timer.After(0, Reseat)
end

local function WatchBox(on)
    if on and not boxWatch then
        boxWatch = CreateFrame("Frame")
        boxWatch:SetScript("OnEvent", function()
            if reseatQueued then return end
            reseatQueued = true
            C_Timer.After(0, ReseatNextTick)
        end)
    end
    if not boxWatch then return end
    for _, e in ipairs(BOX_EVENTS) do
        if on then boxWatch:RegisterEvent(e) else boxWatch:UnregisterEvent(e) end
    end
end

local function OnBoxShow(eb)
    if not (seat and OurBox(eb)) then return end
    active = eb
    Seat(eb)
    cover:Show()
    WatchBox(true)
end

local function OnBoxHide(eb)
    if eb ~= active then return end
    active = nil
    cover:Hide()
    WatchBox(false)
end

local OWNER = "ProseccoAdditions_Chat"

local function Listen(on)
    if on then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxShow", function(_, eb)
            xpcall(function() OnBoxShow(eb) end, ns.ErrorHandler("chat:boxShow"))
        end, OWNER)
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxHide", function(_, eb)
            xpcall(function() OnBoxHide(eb) end, ns.ErrorHandler("chat:boxHide"))
        end, OWNER)
    else
        EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxShow", OWNER)
        EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxHide", OWNER)
    end
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        host:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not dockPending then return end
        dockPending = false
        if ns.IsModuleEnabled("chat") then
            Draw()
        else
            PlaceDock(nil)
            PlaceScrollChild(false)
        end
    else
        -- Entering the world (login, reload, zoning): Ellesmere lays its
        -- chat out after our login pass, so the offsets are taken again
        -- from ChatFrame1's settled rect.
        Draw()
    end
end

local function RedrawIfShown()
    if chatPanel and chatPanel:IsShown() then Draw() end
end

function M:Enable()
    if not chatPanel then
        chatPanel = NewPanel()
        tabsPanel = NewPanel()
        -- The seam's frames: above the panels' own border holders (level 2).
        joined = NewPanel()
        joined.tex:Hide()
        joined:SetFrameLevel(2)
        joined:Hide()
        seamLine = NewPanel()
        seamLine.tex:SetTexture(nil)
        seamLine:SetFrameLevel(4)
        seamLine:Hide()
        -- Over Ellesmere's tab strip (MEDIUM 100) while a box is shown.
        cover = NewPanel()
        cover:SetFrameStrata("MEDIUM")
        cover:SetFrameLevel(110)
        -- Takes the clicks over the tabs while typing, so a click there does
        -- not select a tab or open its menu under the edit box.
        cover:EnableMouse(true)
        cover:Hide()
    end
    if not host then
        host = CreateFrame("Frame")
        host:SetScript("OnEvent", function(_, event)
            xpcall(function() OnEvent(_, event) end, ns.ErrorHandler("chat:" .. event))
        end)
    end
    host:RegisterEvent("PLAYER_ENTERING_WORLD")
    Listen(true)
    -- Ellesmere applies its Tab Height at once; the tab panel follows when
    -- its menu closes (registered once, gated here).
    ns.Ellesmere.OnMenuClosed(RedrawIfShown)
end

function M:Apply()
    Draw()
end

function M:Disable()
    RestoreOwned()
    if not chatPanel then return end
    chatPanel:Hide()
    tabsPanel:Hide()
    joined:Hide()
    seamLine:Hide()
    cover:Hide()
    Listen(false)
    WatchBox(false)
    active = nil
    for eb in pairs(before) do Unseat(eb) end
    host:UnregisterEvent("PLAYER_ENTERING_WORLD")
    PlaceDock(nil)          -- keeps PLAYER_REGEN_ENABLED registered if it has to wait
    PlaceScrollChild(false)
end

function M:SwitchedOn() WriteOwned() end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------

local function SliderCell(text, tip, key, maxV, changed)
    return { type = "slider", text = text, min = 0, max = maxV, step = 1, tooltip = tip,
        getValue = function() return px(DB()[key]) end,
        setValue = function(v) DB()[key] = v; changed() end }
end

local function TabGapCell(changed)
    local c = SliderCell("Tab Gap", "Pixels between the chat panel and the tab panel. The tabs move with it. Waits for the end of combat.", "tabGap", 32, changed)
    c.disabled = function() return DB().seam == true end
    c.disabledTooltip = "Header attached is on: the panels meet at the seam."
    c.rawTooltip = true
    return c
end

-- The tab height is set in Ellesmere (Chat > Tabs); the tab panel follows
-- it when Ellesmere's menu closes (see M:Enable).
local function MainPage(parent, y, W, changed)
    local _, h
    if ns.Ellesmere.ChatStockStyle() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Ellesmere's chat uses Blizzard Style or Classic WoW UI, which draw their own chat art over ProseccoAdditions' panels. This module is made for the EllesmereUI style." }); y = y - h
    end

    _, h = W:SectionHeader(parent, "ELLESMERE SETTINGS", y); y = y - h
    local names = {}
    for _, o in ipairs(OWNED) do names[#names + 1] = o.label end
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Ellesmere's own chat values that ProseccoAdditions sets." },
        { type = "button", text = "Set Ellesmere Values", width = 180,
          disabled = function() return not ns.IsModuleEnabled("chat") end,
          disabledTooltip = "This option needs Chat turned on.",
          onClick = function()
              ns.Ellesmere.Confirm({
                  title = "Chat: set Ellesmere values",
                  message = "Set these again, so only ProseccoAdditions' panels and border show?\n- "
                      .. table.concat(names, "\n- "),
                  confirmText = "Set and reload",
                  reload = true,
                  onConfirm = WriteOwned,
              })
          end }); y = y - h

    -- Blizzard's Chat Style (Options > Social). The edit box over the tabs is
    -- made for Classic, where the box is shown only while typing; with IM it
    -- is always shown and covers the tabs. A reload lets Blizzard's chat
    -- start in the new style.
    _, h = W:SectionHeader(parent, "CHAT STYLE", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Use Classic Chat Style", width = 180,
          disabled = function() return GetCVar("chatStyle") == "classic" end,
          disabledTooltip = "Blizzard's Chat Style is already Classic.", rawTooltip = true,
          onClick = function()
              ns.Ellesmere.Confirm({
                  title = "Chat: Classic Chat Style",
                  message = "Set Blizzard's Chat Style (Options > Social) to Classic, so the edit box is shown only while you type?",
                  confirmText = "Set and reload",
                  reload = true,
                  onConfirm = function() SetCVar("chatStyle", "classic") end,
              })
          end },
        { type = "label", text = "The edit box over the tabs is made for Classic. With IM Style it is always shown and covers the tabs." }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "The chat panel takes the Global Background, the tab panel and the edit box the Global Header Background (the edit box opaque), and both the Global Border (Global Settings page)." }); y = y - h

    _, h = W:SectionHeader(parent, "PADDING", y); y = y - h
    y = ns.Rows(W, parent, y,
        SliderCell("Padding", "Pixels the panel reaches past the chat text on the left, right and bottom.", "padding", 32, changed),
        SliderCell("Top Padding", "Pixels the panel reaches above the chat text.", "topPadding", 32, changed))

    _, h = W:SectionHeader(parent, "HEADER/TABS", y); y = y - h
    y = ns.Rows(W, parent, y,
        TabGapCell(changed),
        { type = "toggle", text = "Header attached",
          tooltip = "One border round the tab panel and the chat panel, with a line of the border where they meet, like Ellesmere's Power Bar Seam. The Pixels styles draw their seam art; Solid a plain line; other textured styles have none. Tab Gap is not used while it is on; in combat the tabs follow when combat ends.",
          getValue = function() return DB().seam == true end,
          setValue = function(v)
              DB().seam = v and true or false
              changed()
              ns.Ellesmere.RefreshPage()      -- Tab Gap greys in or out
          end })
    _, h = W:DualRow(parent, y,
        { type = "label", text = "The tab panel takes Ellesmere's Tab Height (Ellesmere > Chat > Tabs); a change there shows here when Ellesmere's menu closes." }); y = y - h
    return y
end

function M:BuildPage(_, parent, y, W)
    local _, h
    local function changed() ns.Apply() end
    y = MainPage(parent, y, W, changed)
    if not ns.IsModuleEnabled("chat") then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Chat is off: turn it on under Modules on the General page." }); y = y - h
    end
    return y
end
