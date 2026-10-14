-- ProseccoAdditions / Modules / QuestTrackerFrame.lua
-- The Quest Tracker's frame and settings page. Reads the quest list through
-- M.Quests(); calls the quest log API itself only for clicks (abandon,
-- open), the item buttons' cooldown and the order.
--
-- One frame of ours on UIParent: a header ("Quests", the quest log's fill),
-- the RXP guide's progress under it (at the bottom in Integrated), then the
-- watched quests by zone in a scroll frame. The quest item buttons are
-- secure action buttons on the scroll child; everything else is insecure.
-- While a button is on the tracker the whole draw waits out combat: the
-- buttons cannot be moved then, nor the scroll child they hang on (a
-- protected frame protects what it is anchored to). The redraw queued on
-- PLAYER_REGEN_ENABLED catches the tracker up.
--
-- Order: with an RXP guide loaded, quests the guide names come first, by the
-- next step that names them; the rest follow Blizzard's watch order (sorted
-- by distance). Zones come in the order of their first quest. Within a zone,
-- completed quests go to the top, the bottom or stay (Completed Quests).

local _, ns = ...

local M = ns.GetModule("questTracker")
local DB = M.DB

local DOT_TEX = ns.RXP.TEXTURE_PATH .. "white_circle"   -- our own texture, also used by the RXP theme
local DOT_R, DOT_G, DOT_B = 0.25, 0.6, 1                -- the blue of the guide dot
local ZONE_R, ZONE_G, ZONE_B = 0.85, 0.85, 0.85
local OBJ_R, OBJ_G, OBJ_B = 0.8, 0.8, 0.8
-- Ellesmere's tracker colours: completed 40FF59.
local DONE_R, DONE_G, DONE_B = 0.251, 1, 0.349
local FAIL_R, FAIL_G, FAIL_B = 1, 0.25, 0.25
local INDENT = 10           -- objectives under their quest title, UI units
local PROGRESS_BORDER = { style = "solid", size = 1, color = "000000", alpha = 1 }
local HL_DROP = 2           -- px the Guide Highlight reaches further below its title than above (DrawRows)
local SCROLL_STEP = 24

local function num(v, fallback) return tonumber(v) or fallback end
-- The tracker's own border while the dock draws one round it and the step list.
local NO_BORDER = { style = "solid", size = 0, color = "000000", alpha = 1 }

local frame, header, progress, scroll, child
local rows = {}             -- row pool, reused on every draw
local expanded = {}         -- zone -> true: opened by a click while Current Zone Only is on (runtime)
local buttons = {}          -- secure item button pool, laid out only out of combat
local placed = 0            -- buttons on the tracker right now; the rest wait in `parking`
local parking               -- hidden holder for unused buttons, off the tracker
local itemPlan = {}         -- the draw's button placements, filled by DrawRows for LayoutItems
local timerRows = {}        -- { fs, ends }: timed quests' rows the ticker refreshes
local ticker                -- 1 s C_Timer ticker, running only while timerRows has rows
-- Where RXP's guide hangs in Integrated mode: an empty frame over the
-- tracker's rect, placed by coordinates in Draw. Not the tracker itself:
-- with an item button the tracker is protected (see Frozen), and RXP's
-- frames, which RXP moves in combat, must not hang on it.
local dockAnchor

-- Whether the tracker is frozen: in combat while an item button sits on it.
-- The buttons are secure, and the frames they hang on (child, scroll, frame)
-- cannot be moved or hidden then either. Unused buttons wait in `parking`,
-- so a tracker without a quest item keeps updating in combat.
local function Frozen()
    return placed > 0 and InCombatLockdown()
end

-- A click that would change the tracker while it is frozen: says so instead
-- of changing a saved state nobody can see until after combat.
local function RefuseFrozen()
    if not Frozen() then return false end
    ns.Print("The tracker changes after combat.")
    return true
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

-- Every text in the tracker takes the face and outline (with the shadow) of
-- the TEXT settings; only the sizes differ. face/outline: optional overrides
-- (nil or "tracker" = the shared settings), for Quest Completed. "global"
-- follows the General page; a face of "" is Ellesmere's font.
local function Font(fs, size, face, outline)
    local d = DB()
    if face == nil or face == "tracker" then face = d.font end
    if not outline or outline == "" or outline == "tracker" then outline = d.outline end
    local flags, shadow = ns.Media.Outline(outline)
    fs:SetFont(ns.Media.FontPath(face), tonumber(size) or 12, flags)
    if shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function OnDragStart()
    -- With secure buttons under the frame, moving it in combat is blocked.
    if Frozen() then return end
    frame.dragRight, frame.dragTop = frame:GetRight(), frame:GetTop()
    frame:StartMoving()
end

-- StopMovingOrSizing re-anchors the frame to the screen; the drag becomes
-- new saved offsets instead, so the position stays the one the page shows.
local function OnDragStop()
    frame:StopMovingOrSizing()
    local d = DB()
    if frame.dragRight then
        d.x = math.floor((tonumber(d.x) or 0) + (frame:GetRight() - frame.dragRight) + 0.5)
        d.y = math.floor((tonumber(d.y) or 0) + (frame:GetTop() - frame.dragTop) + 0.5)
    end
    frame.dragRight, frame.dragTop = nil, nil
    M.Draw()
    ns.Ellesmere.RefreshPage()
end

local function OnHeaderClick(_, button)
    if button ~= "LeftButton" or DB().unlocked then return end
    if RefuseFrozen() then return end
    DB().collapsed = not DB().collapsed
    M.Draw()
end

-- In Integrated the progress row's box is the guide's header: a click folds
-- RXP's step list and step boxes away and back. Frozen, the tracker is open
-- (a collapsed one has no item buttons), and an open tracker looks the same
-- with the guide folded or not: only RXP's frames move, and they do not hang
-- on the tracker. The redraw after combat finds the same state.
local function OnFootClick(_, button)
    local d = DB()
    if button ~= "LeftButton" or d.unlocked then return end
    d.rxpFolded = not d.rxpFolded
    if Frozen() then
        ns.RXP.SetDockFolded(d.rxpFolded)
    else
        M.Draw()
    end
end

-- The quest list's scroll bar, beside the list outside the tracker's edge
-- (as the docked guide list's), with the RXP theme's art: a Slider and two
-- buttons of ours, sized as Blizzard's UIPanelScrollBarTemplate. Shown only
-- while the list can scroll, and then by alpha only while the mouse is on
-- the tracker or the bar, so the bar keeps taking the mouse.
local bar
local barReach = 0          -- units right of the tracker, up to the bar, that count as on it
local barLeft = false       -- Scroll Bar Side: the bar and barReach left of the tracker
local BAR_ART = ns.RXP.TEXTURE_PATH .. "Scrollbar/"
local syncing = false       -- SyncBar is setting the bar's value, not the player

-- The bar's range, value and arrows from the scroll frame.
local function SyncBar()
    local max = math.max(0, child:GetHeight() - scroll:GetHeight())
    local v = scroll:GetVerticalScroll()
    syncing = true
    bar:SetMinMaxValues(0, max)
    bar:SetValue(v)
    syncing = false
    bar.up:SetEnabled(v > 0)
    bar.down:SetEnabled(v < max)
end

local function ScrollTo(v)
    local max = math.max(0, child:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(math.max(0, math.min(max, v)))
    SyncBar()
end

local function BarHovered()
    return bar:IsMouseOver() or bar.up:IsMouseOver() or bar.down:IsMouseOver()
end

-- On the tracker, on the strip between it and the bar (as the docked guide
-- list's), or on the bar.
local function Hovered()
    return frame:IsMouseOver(0, 0, barLeft and -barReach or 0, barLeft and 0 or barReach) or BarHovered()
end

-- While the mouse is on the tracker: nothing tells when it leaves through a
-- gap between rows or the padding (the tracker itself takes the mouse only
-- while unlocked), so a watch runs from the first OnEnter until the mouse
-- is off both the tracker and the bar, then stops.
local function WatchHover(self)
    local over = Hovered()
    local a = over and 1 or 0
    if self:GetAlpha() ~= a then self:SetAlpha(a) end
    if not over then self:SetScript("OnUpdate", nil) end
end

local function OnHover()
    if bar:IsShown() then bar:SetScript("OnUpdate", WatchHover) end
end

local function OnWheel(_, delta)
    ScrollTo(scroll:GetVerticalScroll() - delta * SCROLL_STEP)
    OnHover()       -- the wheel over the list shows the bar too
end

local function MakeBar()
    bar = CreateFrame("Slider", nil, frame)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(16)
    bar:SetValueStep(1)
    bar:SetThumbTexture(BAR_ART .. "Knob")
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(18, 24)
    thumb:SetTexCoord(0.2, 0.8, 0.125, 0.875)
    bar:SetScript("OnValueChanged", function(_, v)
        -- The scroll child carries the secure item buttons: moving it is
        -- protected in combat (M.EnterCombat hides the bar).
        if syncing or Frozen() then return end
        scroll:SetVerticalScroll(v)
        SyncBar()
    end)
    bar:EnableMouse(true)       -- a Slider from CreateFrame takes no mouse
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", OnWheel)
    bar:SetScript("OnEnter", OnHover)
    local function arrow(dir, sign)
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(18, 16)
        for _, state in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
            b["Set" .. state .. "Texture"](b, BAR_ART .. dir .. "-" .. state)
            local t = b["Get" .. state .. "Texture"](b)
            t:SetTexCoord(0.2, 0.8, 0.25, 0.75)
        end
        b:SetScript("OnClick", function()
            if not Frozen() then ScrollTo(scroll:GetVerticalScroll() + sign * SCROLL_STEP) end
        end)
        b:SetScript("OnEnter", OnHover)
        -- A disabled arrow (at the top or the bottom of the list) gets no
        -- OnEnter without this (Inferred), and the bar would not show under
        -- the mouse there.
        b:SetMotionScriptsWhileDisabled(true)
        -- The arrows lie outside the bar's rect: without a wheel of their
        -- own it would reach the camera.
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", OnWheel)
        return b
    end
    bar.up = arrow("Up", -1)
    bar.up:SetPoint("BOTTOM", bar, "TOP")
    bar.down = arrow("Down", 1)
    bar.down:SetPoint("TOP", bar, "BOTTOM")
    bar:SetAlpha(0)
    bar:Hide()
end

local function EnsureFrame()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetDontSavePosition(true)     -- our offsets are the saved position
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop", OnDragStop)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    -- With Header Seam the header above the seam has its own background.
    frame.headerBg = frame:CreateTexture(nil, "BACKGROUND")

    header = CreateFrame("Button", nil, frame)
    header:RegisterForClicks("LeftButtonUp")
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnClick", OnHeaderClick)
    header:SetScript("OnDragStart", function() if DB().unlocked then OnDragStart() end end)
    header:SetScript("OnDragStop", function() if frame.dragRight then OnDragStop() end end)
    header.title = ns.Media.FontString(header)
    header.title:SetPoint("LEFT")
    header.count = ns.Media.FontString(header)
    header.count:SetPoint("RIGHT")

    progress = CreateFrame("Frame", nil, frame)
    progress.name = ns.Media.FontString(progress)
    progress.name:SetPoint("TOPLEFT")
    progress.name:SetJustifyH("LEFT")
    progress.name:SetWordWrap(false)
    progress.pct = ns.Media.FontString(progress)
    progress.pct:SetPoint("TOPRIGHT")
    -- The bar's 1 px border: ns.Border.Apply on a frame round the track.
    progress.box = CreateFrame("Frame", nil, progress)
    progress.track = progress:CreateTexture(nil, "ARTWORK")
    progress.track:SetColorTexture(1, 1, 1, 0.12)
    progress.fill = progress:CreateTexture(nil, "OVERLAY")
    progress.fill:SetColorTexture(DOT_R, DOT_G, DOT_B, 1)

    -- Header Seam: our border's line under the header, edge to edge, as the
    -- Damage Meter's Header Seam. Above the background and the border holder
    -- (frame level + 1).
    frame.seam = CreateFrame("Frame", nil, frame)
    frame.seam:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.seam:EnableMouse(false)
    frame.seam.tex = frame.seam:CreateTexture(nil, "OVERLAY")
    -- Joined to the guide's step list, the progress row at the bottom gets a
    -- box of its own, as the header has with Header Seam: a seam over it and
    -- the Header Background under it.
    frame.footBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.footSeam = CreateFrame("Frame", nil, frame)
    frame.footSeam:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.footSeam:EnableMouse(false)
    frame.footSeam.tex = frame.footSeam:CreateTexture(nil, "OVERLAY")
    frame.foot = CreateFrame("Button", nil, frame)
    frame.foot:RegisterForClicks("LeftButtonUp")
    frame.foot:SetScript("OnClick", OnFootClick)
    frame.foot:Hide()

    scroll = CreateFrame("ScrollFrame", nil, frame)
    -- The list takes the wheel only. A frame that takes mouse motion takes the
    -- mouse focus and clicks with it (Ellesmere measured this), so the world
    -- under the list (mouseover, click to target) and an unlocked drag would be
    -- blocked. The bar's watch starts on the title and zone rows, their fold
    -- buttons, the item buttons, the header, the bar and the wheel instead.
    scroll:SetScript("OnMouseWheel", OnWheel)
    child = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(child)
    MakeBar()
    header:HookScript("OnEnter", OnHover)
    frame.foot:SetScript("OnEnter", OnHover)
end

-- Quest rows open the quest or untrack it, as on Blizzard's tracker: a chat
-- link first while the edit box is open, then the watch toggle (Shift),
-- else the quest log via QuestMapFrame_OpenToQuestDetails, which Blizzard's
-- tracker calls. That it opens from an addon, in combat too, is Unverified.
-- Alt-click: abandon after Ellesmere's confirm popup (no Blizzard
-- StaticPopup is driven from addon code), with the calls Blizzard's own
-- Abandon makes: select the quest, mark it, then AbandonQuest on accept. The
-- previous selection is put back so the quest log keeps its own.
local function MarkForAbandon(id)
    local old = C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(id)
    C_QuestLog.SetAbandonQuest()
    return old
end

local function Abandon(id)
    if not C_QuestLog.CanAbandonQuest(id) then
        ns.Print("This quest can't be abandoned.")
        return
    end
    local title = C_QuestLog.GetTitleForQuestID(id) or "this quest"
    local old = MarkForAbandon(id)
    local items = C_QuestLog.GetAbandonQuestItems()
    C_QuestLog.SetSelectedQuest(old or 0)
    local function DoAbandon()
        -- The quest may have left the log while the popup was open; then
        -- SetAbandonQuest would mark whatever the log has selected.
        if not C_QuestLog.GetLogIndexForQuestID(id) then return end
        local prev = MarkForAbandon(id)
        if C_QuestLog.GetAbandonQuest() == id then C_QuestLog.AbandonQuest() end
        C_QuestLog.SetSelectedQuest(prev or 0)
    end
    if not DB().abandonConfirm then
        DoAbandon()
        return
    end
    local msg = "Abandon \"" .. title .. "\"?"
    if items and #items > 0 then
        msg = msg .. "\nItems from this quest will be destroyed."
    end
    ns.Ellesmere.Confirm({
        title = "Abandon Quest",
        message = msg,
        confirmText = "Abandon",
        onConfirm = DoAbandon,
    })
end

local function OnQuestClick(self, button)
    local id = self.questID
    if not id then return end
    -- Right-click folds the quest to its title and back; left-click keeps
    -- Blizzard's tracker behaviour below.
    if button == "RightButton" then
        if RefuseFrozen() then return end
        local folded = DB().folded
        folded[id] = not folded[id] or nil
        M.Draw()
        return
    end
    if button ~= "LeftButton" then return end
    if ChatFrameUtil.TryInsertQuestLinkForQuestID(id) then return end
    -- The watch toggle first, so a QUESTWATCHTOGGLE bound to Alt keeps untracking.
    if IsModifiedClick("QUESTWATCHTOGGLE") then
        C_QuestLog.RemoveQuestWatch(id)
        return
    end
    if IsAltKeyDown() and DB().altAbandon then
        Abandon(id)
        return
    end
    -- Questie's tracker refuses this in combat; that it is blocked there is
    -- Inferred.
    if InCombatLockdown() then
        ns.Print("The quest log opens after combat.")
        return
    end
    QuestMapFrame_OpenToQuestDetails(id)
end

-- Every zone header folds and opens on a click. With Current Zone Only on,
-- other zones keep a runtime toggle (closed by default, open for this
-- session); otherwise the choice is saved per zone.
local function OnZoneClick(self, button)
    if button ~= "LeftButton" or not self.zone then return end
    if RefuseFrozen() then return end
    local d = DB()
    if d.currentZoneOnly and self.zone ~= (GetRealZoneText() or "") then
        expanded[self.zone] = not expanded[self.zone] or nil
    else
        d.foldedZones[self.zone] = not d.foldedZones[self.zone] or nil
    end
    M.Draw()
end

-- The minimize icon in the gutter: folds the quest to its title, the same
-- toggle as a right-click on the title.
local function OnFoldClick(self)
    local id = self:GetParent().questID
    if not id then return end
    if RefuseFrozen() then return end
    local folded = DB().folded
    folded[id] = not folded[id] or nil
    M.Draw()
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", OnHover)        -- the scroll bar shows under the mouse
    r.text = ns.Media.FontString(r)
    r.text:SetJustifyH("LEFT")
    r.text:SetJustifyV("TOP")
    r.text:SetWordWrap(true)
    -- The quest's XP after the title: its own text, since one FontString has
    -- one size and XP Size can differ from Title Size.
    r.xp = ns.Media.FontString(r)
    -- Guide Highlight box: on the scroll child, one level under the rows, so
    -- the row's text and dot draw over it; its border through ns.Border.Apply.
    r.hl = CreateFrame("Frame", nil, child)
    r.hl:SetFrameLevel(child:GetFrameLevel())
    r.hl.bg = r.hl:CreateTexture(nil, "BACKGROUND")
    r.hl.bg:SetAllPoints(r.hl)
    -- The dot's outline is the same circle in black, one pixel larger all round.
    r.dotEdge = r:CreateTexture(nil, "OVERLAY", nil, 0)
    r.dotEdge:SetTexture(DOT_TEX)
    r.dotEdge:SetVertexColor(0, 0, 0, 1)
    r.dot = r:CreateTexture(nil, "OVERLAY", nil, 1)
    r.dot:SetTexture(DOT_TEX)
    r.dot:SetVertexColor(DOT_R, DOT_G, DOT_B, 1)
    -- Minimize icon, in the dot's place on quests outside the guide.
    r.fold = CreateFrame("Button", nil, r)
    r.fold:SetScript("OnClick", OnFoldClick)
    r.fold:SetScript("OnEnter", OnHover)   -- in the gutter, the row's own OnEnter does not fire
    r.fold.txt = ns.Media.FontString(r.fold)
    r.fold.txt:SetPoint("CENTER")
    rows[i] = r
    return r
end

-- ---------------------------------------------------------------------------
-- Quest item buttons
-- ---------------------------------------------------------------------------

-- Blizzard's own tracker buttons use the item from protected code
-- (UseQuestLogSpecialItem), which an addon cannot. The addon way is
-- Questie's: a SecureActionButtonTemplate whose item attribute is the quest
-- item's link. Attributes, anchors and visibility are touched only out of
-- combat (LayoutItems).
local function OnItemEnter(self)
    OnHover()       -- the scroll bar shows under the mouse (hidden in combat: nothing then)
    if not self.logIndex then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetQuestLogSpecialItem(self.logIndex)
end

local function ItemButton(i)
    local b = buttons[i]
    if b then return b end
    -- No name: nothing finds the buttons by name, so no globals.
    b = CreateFrame("Button", nil, child, "SecureActionButtonTemplate")
    b:SetAttribute("type1", "item")
    -- Both, as Questie: Forever can fire clicks on the down press.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)      -- trim the icon's baked edge
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    b.count = ns.Media.FontString(b)
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    ns.Border.Apply(b, { style = "solid", size = 1, color = "000000", alpha = 1 })
    b:SetScript("OnEnter", OnItemEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

local function UpdateCooldown(b)
    if not b.logIndex then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(b.logIndex)
    if start then
        CooldownFrame_Set(b.cooldown, start, duration, enable)
    else
        b.cooldown:Clear()
    end
end

-- On BAG_UPDATE_COOLDOWN: only the swipes change.
function M.UpdateItemCooldowns()
    for _, b in ipairs(buttons) do
        if b:IsShown() then UpdateCooldown(b) end
    end
end

-- Places the buttons the draw planned. Never in combat: the pool's frames
-- are protected (see Frozen).
local function LayoutItems()
    -- Also guarded here, not only in M.Draw: before the first button exists
    -- M.Draw runs in combat (a /reload or an enable mid-fight), and creating or
    -- placing a secure button then is blocked. The rows draw with their gap at
    -- the right; the forced redraw after combat places the buttons.
    if InCombatLockdown() then return end
    local d = DB()
    local size = num(d.itemSize, 26)
    for i, p in ipairs(itemPlan) do
        local b = ItemButton(i)
        -- "item:<id>" as Questie uses, not the full link: the proven form on
        -- Forever. The plan keeps the link for the data half's comparisons.
        b:SetAttribute("item1", p.item:match("item:%d+") or p.item)
        b.logIndex = p.logIndex
        b.icon:SetTexture(p.tex)
        Font(b.count, num(d.objectiveSize, 10))
        b.count:SetTextColor(1, 1, 1)
        if p.charges and p.charges > 1 then
            b.count:SetText(p.charges)
            b.count:Show()
        else
            b.count:Hide()
        end
        b:SetSize(size, size)
        b:SetParent(child)
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -p.y)
        UpdateCooldown(b)
        b:Show()
    end
    placed = #itemPlan
    -- Unused buttons leave the tracker, so a secure frame no longer hangs on
    -- it and the tracker is not frozen in combat for their sake.
    for i = #itemPlan + 1, #buttons do
        local b = buttons[i]
        b.logIndex = nil
        b:Hide()
        if not parking then
            parking = CreateFrame("Frame", nil, UIParent)
            parking:Hide()
        end
        b:ClearAllPoints()
        b:SetParent(parking)
    end
end

-- The pull (PLAYER_REGEN_DISABLED). The wheel and the scroll bar move the
-- scroll child the secure buttons hang on, a protected move in combat: the
-- wheel is turned off and the bar hidden (shown, it would take clicks it
-- cannot act on); the redraw after combat gives both back.
function M.EnterCombat()
    if frame and placed > 0 then
        scroll:EnableMouseWheel(false)
        bar:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Timed quests
-- ---------------------------------------------------------------------------

local function TimeText(s)
    s = math.max(0, math.floor(s + 0.5))
    if s >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
    end
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function TickTimers()
    for _, t in ipairs(timerRows) do
        t.fs:SetText("Time left: " .. TimeText(t.ends - GetTime()))
    end
end

-- Runs the 1 s ticker exactly while a timer row shows; it only writes the
-- rows' texts, never lays anything out. When a timer runs out the quest
-- fails, and QUEST_LOG_UPDATE redraws past the row.
local function SetTicker()
    if timerRows[1] then
        if not ticker then ticker = C_Timer.NewTicker(1, TickTimers) end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- ---------------------------------------------------------------------------
-- Order
-- ---------------------------------------------------------------------------

-- Watched quests in display order, grouped by zone: zones (in order) and
-- zone -> its quests. `guide` (questID -> step) or nil.
local function Ordered(guide)
    local d = DB()
    local watchIdx = {}
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if id then watchIdx[id] = i end
    end
    local list = {}
    for _, q in ipairs(M.Quests()) do
        if q.watched then list[#list + 1] = q end
    end
    local LAST = math.huge
    table.sort(list, function(a, b)
        local ga, gb = guide and guide[a.id] or LAST, guide and guide[b.id] or LAST
        if ga ~= gb then return ga < gb end
        local wa, wb = watchIdx[a.id] or LAST, watchIdx[b.id] or LAST
        if wa ~= wb then return wa < wb end
        return a.logIndex < b.logIndex
    end)
    local zones, byZone = {}, {}
    for _, q in ipairs(list) do
        local z = q.zone or ""
        if not byZone[z] then
            byZone[z] = {}
            zones[#zones + 1] = z
        end
        local t = byZone[z]
        t[#t + 1] = q
    end
    if d.completed == "top" or d.completed == "bottom" then
        for _, z in ipairs(zones) do
            local done, open = {}, {}
            for _, q in ipairs(byZone[z]) do
                if q.complete then done[#done + 1] = q else open[#open + 1] = q end
            end
            local a, b = done, open
            if d.completed == "bottom" then a, b = open, done end
            for _, q in ipairs(b) do a[#a + 1] = q end
            byZone[z] = a
        end
    end
    return zones, byZone, #list
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Lays out one text row at y (from the top of the scroll child, going down)
-- and returns the y under it.
local function PlaceRow(r, y, x, w, text, size, cr, cg, cb)
    Font(r.text, size)
    r.text:SetTextColor(cr, cg, cb)
    r.text:ClearAllPoints()
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.text:SetWidth(w)
    r.text:SetText(text)
    local h = math.ceil(r.text:GetStringHeight())
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    r:SetSize(w, h)
    r:Show()
    return y + h
end

-- "1.2k" for 1200, "850" for 850.
local function XpText(xp)
    if xp >= 1000 then
        local t = string.format("%.1fk", xp / 1000)
        return (t:gsub("%.0k", "k"))
    end
    return tostring(xp)
end

local function TitleText(q)
    return q.level and q.level > 0 and ("[" .. q.level .. "] " .. q.title) or tostring(q.title)
end

-- The title row with the XP after it in its own size and colour. On one
-- line the XP follows the title, bottoms aligned; when the title wraps, the
-- title gets narrower and the XP sits at the right end of its first line
-- (a FontString does not tell where its last line ends).
local function PlaceTitle(r, y, x, w, q, size, cr, cg, cb)
    local d = DB()
    if not (d.questXP and q.xp) then return PlaceRow(r, y, x, w, TitleText(q), size, cr, cg, cb) end
    local xs = num(d.xpSize, size)
    Font(r.xp, xs)
    local xr, xg, xb = ns.HexToRGB(d.xpColor)
    r.xp:SetTextColor(xr, xg, xb, num(d.xpAlpha, 1))
    r.xp:SetText(XpText(q.xp) .. " xp")
    local xw = math.ceil(r.xp:GetStringWidth())
    local gap = math.max(2, math.floor(size * 0.3 + 0.5))
    Font(r.text, size)
    r.text:SetText(TitleText(q))
    local tw = r.text:GetUnboundedStringWidth()
    local oneLine = tw + gap + xw <= w
    local ny = PlaceRow(r, y, x, oneLine and w or (w - gap - xw), TitleText(q), size, cr, cg, cb)
    r.xp:ClearAllPoints()
    if oneLine then
        r.xp:SetPoint("BOTTOMLEFT", r.text, "BOTTOMLEFT", math.ceil(tw) + gap, 0)
    else
        local lineH = (ny - y) / math.max(1, r.text:GetNumLines())
        r.xp:SetPoint("BOTTOMRIGHT", r.text, "TOPLEFT", w, -lineH)
    end
    r.xp:Show()
    return ny
end

local function DrawRows(width, guide, current)
    local d = DB()
    local zones, byZone, shown = Ordered(guide)
    local titleSize, objSize = num(d.titleSize, 12), num(d.objectiveSize, 10)
    -- Title gutter: wide enough for the guide dot, which the scroll frame
    -- would otherwise clip at its left edge from Title Size 13 up.
    local dotSize = math.floor(titleSize * 0.6 + 0.5)
    -- Also room for the dot's outline and the Guide Highlight's border left of it.
    local gutter = math.max(INDENT, dotSize + 6)
    local here = d.currentZoneOnly and GetRealZoneText() or nil
    local u = ns.Ellesmere.PixelUnit(frame)
    local hr, hg, hb = ns.HexToRGB(d.highlightColor)
    local ha = num(d.highlightAlpha, 0.25)
    -- A fixed 1 px solid border in the box's colour at half opacity, so it
    -- follows a new Highlight colour. Built per draw, not per frame.
    local hlBorder = { style = "solid", size = 1, color = d.highlightColor, alpha = 0.5 }
    local itemSize = num(d.itemSize, 26)
    local qGap = 4          -- px between quests
    local oGap = num(d.objectiveSpacing, 1)
    wipe(itemPlan)
    wipe(timerRows)
    local y, n = 0, 0
    local function nextRow()
        n = n + 1
        local r = Row(n)
        r.questID, r.zone = nil, nil
        r:SetScript("OnClick", nil)
        r:EnableMouse(false)
        r.dot:Hide()
        r.dotEdge:Hide()
        r.fold:Hide()
        r.hl:Hide()
        r.xp:Hide()
        return r
    end
    for zi, z in ipairs(zones) do
        local quests = byZone[z]
        local open
        if d.currentZoneOnly and z ~= here then
            open = expanded[z] == true
        else
            open = not d.foldedZones[z]
        end
        if zi > 1 then y = y + 6 end
        local r = nextRow()
        local label = open and z or (z .. " (" .. #quests .. ")")
        y = PlaceRow(r, y, 0, width, label, titleSize, ZONE_R, ZONE_G, ZONE_B)
        r.zone = z
        r:EnableMouse(true)
        r:SetScript("OnClick", OnZoneClick)
        if open then
            for _, q in ipairs(quests) do
                y = y + qGap
                r = nextRow()
                local x, w = 0, width
                local inGuide = guide and guide[q.id]
                -- The quest's item button: its rows leave room at the right,
                -- and its placement is noted for LayoutItems. Shown while
                -- complete only if Blizzard says so (showWhenComplete).
                local bw, blockTop = 0, y
                if d.itemButtons and q.item and (not q.complete or q.showWhenComplete) then
                    bw = itemSize + 6
                    itemPlan[#itemPlan + 1] = { y = y, item = q.item, tex = q.itemTexture,
                        charges = q.charges, logIndex = q.logIndex }
                end
                if d.rxpDot and inGuide then
                    -- The dot sits in a gutter of its own, so titles with and
                    -- without one line up after it.
                    r.dot:SetSize(dotSize, dotSize)
                    r.dot:ClearAllPoints()
                    r.dot:SetPoint("RIGHT", r, "TOPLEFT", -3, -math.floor(titleSize / 2))
                    r.dot:Show()
                    r.dotEdge:SetSize(dotSize + 2 * u, dotSize + 2 * u)
                    r.dotEdge:ClearAllPoints()
                    r.dotEdge:SetPoint("CENTER", r.dot, "CENTER")
                    r.dotEdge:Show()
                end
                -- The minimize click area fills the dot's slot on every
                -- quest: with the dot it is invisible and the dot itself
                -- takes the click; without it it shows "-" open, "+" folded.
                local f = r.fold
                -- Font first, also for the empty text: SetText on a
                -- FontString without a font is an error.
                Font(f.txt, titleSize)
                if d.rxpDot and inGuide then
                    f.txt:SetText("")
                else
                    f.txt:SetTextColor(OBJ_R, OBJ_G, OBJ_B)
                    f.txt:SetText(d.folded[q.id] and "+" or "-")
                end
                f:SetSize(dotSize + 6, titleSize + 4)
                f:ClearAllPoints()
                f:SetPoint("RIGHT", r, "TOPLEFT", -1, -math.floor(titleSize / 2))
                f:Show()
                -- Only the quests of RXP's active steps, the ones the
                -- player is doing now; the dot marks every quest the guide
                -- names.
                local lit = d.rxpHighlight and current and current[q.id]
                if lit then
                    -- A box across the whole width of the list, from its left
                    -- edge (the row starts after the gutter), its 1 px edge
                    -- inside that width. It reaches HL_DROP px further below
                    -- the title than above: with equal offsets the title sat
                    -- low in the box.
                    r.hl.bg:SetColorTexture(hr, hg, hb, ha)
                    r.hl:ClearAllPoints()
                    r.hl:SetPoint("TOPLEFT", r, "TOPLEFT", -gutter, 1)
                    r.hl:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, -1 - HL_DROP * u)
                    r.hl:Show()
                    ns.Border.Apply(r.hl, hlBorder)
                end
                local c = GetQuestDifficultyColor(q.level or 0)
                y = PlaceTitle(r, y, x + gutter, w - gutter - bw, q, titleSize, c.r, c.g, c.b)
                if bw > 0 then
                    -- The button is taller than the text row: the title (and
                    -- the highlight, dot and icon on it) is centred against
                    -- the button instead of hanging at its top.
                    local pre = math.floor((itemSize - (y - blockTop)) / 2)
                    if pre > 0 then
                        r:ClearAllPoints()
                        r:SetPoint("TOPLEFT", child, "TOPLEFT", x + gutter, -(blockTop + pre))
                        y = y + pre
                    end
                end
                -- What follows the highlighted title moves down with the
                -- box's bottom, so the gap under the box stays as it was.
                if lit then y = y + HL_DROP * u end
                r.questID = q.id
                r:EnableMouse(true)
                r:SetScript("OnClick", OnQuestClick)
                -- not folded: a folded quest shows only its title, and a
                -- right-click opens it again.
                if not d.folded[q.id] then
                    -- Objective Spacing: between the title and the first
                    -- line under it; 1 between the lines under it.
                    local g = oGap
                    if q.timerEnds then
                        -- The ticker rewrites this text once a second;
                        -- timerRows keeps its FontString and end time.
                        local tr = nextRow()
                        y = PlaceRow(tr, y + g, gutter + INDENT, width - gutter - INDENT - bw,
                            "Time left: " .. TimeText(q.timerEnds - GetTime()), objSize, OBJ_R, OBJ_G, OBJ_B)
                        timerRows[#timerRows + 1] = { fs = tr.text, ends = q.timerEnds }
                        g = 1
                    end
                    if q.failed then
                        y = PlaceRow(nextRow(), y + g, gutter + INDENT, width - gutter - INDENT - bw, "Failed", objSize, FAIL_R, FAIL_G, FAIL_B)
                    elseif q.complete then
                        -- The turn-in NPC and zone instead of "Ready to turn
                        -- in", which stays when QuestieDB has no answer.
                        local done = "Ready to turn in"
                        if d.turnIn and q.turnInNpc then
                            done = "Turn in: " .. q.turnInNpc .. (q.turnInZone and (", " .. q.turnInZone) or "")
                        end
                        y = PlaceRow(nextRow(), y + g, gutter + INDENT, width - gutter - INDENT - bw, done, objSize, DONE_R, DONE_G, DONE_B)
                    else
                        for _, o in ipairs(q.objectives) do
                            local cr, cg, cb = OBJ_R, OBJ_G, OBJ_B
                            if o.finished then cr, cg, cb = DONE_R, DONE_G, DONE_B end
                            y = PlaceRow(nextRow(), y + g, gutter + INDENT, width - gutter - INDENT - bw, o.text, objSize, cr, cg, cb)
                            g = 1
                        end
                    end
                end
                -- A short quest block must not end above its button's bottom,
                -- or the button lies over the next quest's full-width rows.
                if bw > 0 and y < blockTop + itemSize then y = blockTop + itemSize end
            end
        end
    end
    -- The highlight box is not a child of its row, so it is hidden with it here.
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].hl:Hide() end
    return y, shown
end

-- The progress row: guide name, percent, a thin bar. Under the header at
-- `top`, or with `atBottom` on the frame's bottom padding. Returns its
-- height, 0 when hidden.
local function DrawProgress(width, top, atBottom)
    local d = DB()
    local name, step, total
    if d.rxpProgress then name, step, total = ns.RXP.GuideProgress() end
    if not name then
        progress:Hide()
        return 0
    end
    local size = num(d.objectiveSize, 10)
    Font(progress.name, size)
    Font(progress.pct, size)
    progress.name:SetTextColor(OBJ_R, OBJ_G, OBJ_B)
    progress.pct:SetTextColor(OBJ_R, OBJ_G, OBJ_B)
    local pct = math.floor(step / total * 100 + 0.5)
    progress.pct:SetText(pct .. "%")
    progress.name:SetText(name)
    progress.name:SetPoint("RIGHT", progress.pct, "LEFT", -6, 0)
    local textH = math.ceil(math.max(progress.name:GetStringHeight(), progress.pct:GetStringHeight()))
    local u = ns.Ellesmere.PixelUnit(frame)
    local barH = 3 * u
    local barW = width - 2 * u      -- inside the 1 px edge
    progress.track:ClearAllPoints()
    progress.track:SetPoint("TOPLEFT", progress, "TOPLEFT", u, -(textH + 3 + u))
    progress.track:SetSize(barW, barH)
    progress.fill:ClearAllPoints()
    progress.fill:SetPoint("TOPLEFT", progress.track, "TOPLEFT")
    progress.fill:SetSize(math.max(u, barW * step / total), barH)
    -- Ellesmere's solid border lies inside its frame: the box is the track
    -- grown by one pixel all round.
    progress.box:ClearAllPoints()
    progress.box:SetPoint("TOPLEFT", progress.track, "TOPLEFT", -u, u)
    progress.box:SetPoint("BOTTOMRIGHT", progress.track, "BOTTOMRIGHT", u, -u)
    -- Black and opaque, as the other 1 px edges.
    ns.Border.Apply(progress.box, PROGRESS_BORDER)
    local h = textH + 3 + barH + 2 * u
    progress:ClearAllPoints()
    if atBottom then
        progress:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", num(d.padding, 8), num(d.padding, 8))
    else
        progress:SetPoint("TOPLEFT", frame, "TOPLEFT", num(d.padding, 8), -top)
    end
    progress:SetSize(width, h)
    progress:Show()
    return h
end

-- No quest rows: the tracker or its quests folded. The item buttons leave
-- too, so combat does not freeze a folded tracker; the caller lays them out.
-- Returns the number of watched quests.
local function HideRows(guide)
    scroll:Hide()       -- hides the item buttons with the scroll child
    for _, r in ipairs(rows) do r:Hide(); r.hl:Hide() end
    wipe(timerRows)     -- no visible rows for the ticker to write to
    wipe(itemPlan)
    return select(3, Ordered(guide))
end

-- The dock anchor on the tracker's rect, with the tracker's own pixel
-- snapping (same point, same size).
local function PlaceDockAnchor()
    if not dockAnchor then return end
    local d = DB()
    dockAnchor:ClearAllPoints()
    ns.Ellesmere.PixelPoint(dockAnchor, "TOPRIGHT", UIParent, "TOPRIGHT", num(d.x, -40), num(d.y, -260))
    ns.Ellesmere.PixelSize(dockAnchor, frame:GetWidth(), frame:GetHeight())
end

function M.Draw()
    if not ns.IsModuleEnabled("questTracker") then return end
    -- Frozen: the data half queues a forced redraw on PLAYER_REGEN_ENABLED.
    -- Without item buttons the tracker keeps updating in combat.
    if Frozen() then return end
    EnsureFrame()
    local d = DB()
    local pad = num(d.padding, 8)
    local W = math.max(120, num(d.width, 260))
    local inner = W - pad * 2
    local unlocked = d.unlocked == true
    -- Integrated with RXP's classic window there to dock: the guide's step list
    -- hangs under the tracker inside one border, which the dock draws
    -- (M.ApplyGuideDock). The setting, not the dock's state: this draw runs
    -- before ApplyGuideDock on a switch.
    local joined = d.rxpDock == "integrated" and ns.RXP.CanDock()
    -- Joined, the progress row is the guide's header: a click folds the guide
    -- away (OnFootClick). Collapsed with the guide open, the row stays with the
    -- guide under it; with the guide folded too, only the "Quests" header is
    -- left. Without the row nothing is folded: there would be nothing to click
    -- to open the guide again.
    local guideHead = joined and d.rxpProgress and ns.RXP.GuideProgress() ~= nil
    local onlyHeader = d.collapsed and not (guideHead and not d.rxpFolded)
    -- Always Max Height does not hold while collapsed.
    local fixed = d.fixedHeight and not d.collapsed

    -- Header.
    local hs = num(d.headerSize, 13)
    Font(header.title, hs)
    Font(header.count, hs)
    header.title:SetTextColor(1, 1, 1)
    header.title:SetText("Quests")      -- after SetFont: SetText without a font is an error
    header.count:SetTextColor(OBJ_R, OBJ_G, OBJ_B)
    local inLog = #M.Quests()
    if unlocked then
        header.count:SetText("Drag to move")
    else
        header.count:SetText(inLog .. "/" .. C_QuestLog.GetMaxNumQuestsCanAccept())
    end
    -- Header Height: 0 follows the text; a set height never cuts the text.
    local textH = math.ceil(header.title:GetStringHeight())
    local hh = num(d.headerHeight, 0)
    if hh <= 0 then hh = textH + 6 end
    hh = math.max(hh, textH)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    header:SetSize(inner, hh)

    -- The guide decides the order whether or not its dot is shown.
    local guide = ns.RXP.GuideQuests()
    local current = d.rxpHighlight and ns.RXP.ActiveQuests() or nil
    local top = pad + hh
    local height, shown
    -- Header Seam, only while open: the line sits 3 px under the header and the
    -- content moves down as much again, only when Seam drew a line (border size
    -- 0 or a texture without seam art draws none).
    local u = ns.Ellesmere.PixelUnit(frame)
    local seamDrawn, seamLine = false, 0
    local seamAt = ns.Border.Snap(top + 3, u)
    -- Seam runs folded too (its frame then hidden), so the folded height and
    -- the header background know whether a line would be drawn.
    if d.headerSeam then
        frame.seam:ClearAllPoints()
        frame.seam:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -seamAt)
        frame.seam:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -seamAt)
        frame.seam:SetHeight(1)
        frame.seam:Show()
        local drawn, line = ns.Border.Seam(frame.seam.tex, frame.seam, d.border)
        seamDrawn, seamLine = drawn == true, line or 0
        if seamDrawn and not onlyHeader then top = seamAt + 3 end
    end
    if not seamDrawn or onlyHeader then frame.seam:Hide() end
    -- With the seam the header is the box from the frame's top edge to the seam
    -- line, and its text is centred in that whole box. Not minus the border: a
    -- textured border's Size is not its drawn thickness (FIELD RESULT 2026-10-09
    -- (build 70291): subtracting Size shrank the header to almost nothing at a
    -- 16 px textured border).
    if seamDrawn then
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, 0)
        header:SetSize(inner, seamAt)
    end
    -- The progress row's box at the bottom (joined), `footAt` high from the
    -- frame's bottom edge; 0 without one.
    local footAt = 0
    local footBgTop = 0         -- how far under footAt the progress box's background starts (a textured seam)
    local contentH = 0
    if onlyHeader then
        progress:Hide()
        bar:Hide()
        shown = HideRows(guide)
        LayoutItems()
        -- With Header Seam the folded frame's bottom edge lies where the
        -- seam line lies when open (a solid seam sits just above seamAt,
        -- the frame's own border just inside its bottom), so the header
        -- box looks the same folded and open.
        height = seamDrawn and seamAt or (top + pad)
    else
        -- Joined: the progress row goes to the bottom, just over the seam to the
        -- step list; `foot` is its room there, 6 under the quests.
        local ph = DrawProgress(inner, top + 4, joined)
        local foot = 0
        if ph > 0 and joined then
            foot = 6 + ph
            -- The box mirrors the header's with Header Seam: as high as
            -- padding + row + 3, its seam line inside its top and the dock's
            -- join seam inside its bottom (the same border), the row centred
            -- between them, and the quests ending 9 over its line as they
            -- start 9 under the header's.
            local drawn, line, thick = ns.Border.Seam(frame.footSeam.tex, frame.footSeam, d.border)
            if drawn then
                -- Guide Header Height: the box's height from the frame's
                -- bottom edge; 0 = padding + row + 3, and never so low that
                -- the row leaves the box.
                local gh = num(d.guideHeaderHeight, 0)
                footAt = ns.Border.Snap(gh > 0 and math.max(gh, ph + 2) or (pad + ph + 3), u)
                local footLine = line or 0
                -- A textured seam's art starts with a faint row over its
                -- line: the box's background starts under it, at the line.
                -- FIELD RESULT 2026-10-12 (Pixels, size 16): from the art's
                -- top the background showed one pixel over the seam's line,
                -- a sixteenth of the art.
                footBgTop = thick and ns.Ellesmere.BorderSeamArt(ns.Border.Resolve(d.border).style)
                    and ns.Ellesmere.SnapForES(thick / 16, frame.footSeam:GetEffectiveScale()) or 0
                foot = 9 + footAt - pad
                frame.footSeam:ClearAllPoints()
                frame.footSeam:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, footAt - footLine)
                frame.footSeam:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, footAt - footLine)
                frame.footSeam:SetHeight(1)
                progress:ClearAllPoints()
                progress:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, ns.Border.Snap((footAt - ph) / 2, u))
            end
        elseif ph > 0 then
            top = top + 4 + ph
        end
        child:SetWidth(inner)
        -- Collapsed with the guide's header: the header, the row and the
        -- guide. The scroll frame is left as it is, so the list opens again
        -- where it was scrolled.
        if d.collapsed then
            contentH, shown = 0, HideRows(guide)
        else
            contentH, shown = DrawRows(inner, guide, current)
            child:SetHeight(math.max(1, contentH))
        end
        LayoutItems()
        local maxH = num(d.maxHeight, 520)
        -- No higher than from the tracker's top to the screen's bottom, less
        -- what the docked guide hangs under it, so the list scrolls instead.
        -- The tracker hangs from UIParent's top by d.y.
        local fromTop = UIParent:GetTop() * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
        maxH = math.min(maxH, fromTop + num(d.y, -260) - ns.RXP.BelowHeight() - 4)
        local room = math.max(40, maxH - top - 6 - pad - foot)
        local visible = math.min(contentH, room)
        if not d.collapsed then
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -(top + 6))
            scroll:SetSize(inner, math.max(1, visible))
            scroll:EnableMouseWheel(contentH > visible)
            scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, contentH - visible)))
            scroll:SetShown(contentH > 0)
        end
        -- The bar beside the list, 2 px out from the tracker's edge plus the
        -- half of a textured border that reaches out (a solid line lies
        -- inside), as the guide list's bar; its arrows inside the list's height.
        if contentH > visible and visible > 40 then
            local b = ns.Border.Resolve(d.border)
            local out = ns.Ellesmere.IsTexturedBorder(b.style) and (tonumber(b.size) or 0) / 2 or 0
            local gap = (2 + out) * u
            barReach = gap
            -- Scroll Bar Side: the same place mirrored outside the
            -- left edge.
            barLeft = d.scrollBarSide == "left"
            local p, rp, x = "LEFT", "TOPRIGHT", gap
            if barLeft then p, rp, x = "RIGHT", "TOPLEFT", -gap end
            bar:ClearAllPoints()
            bar:SetPoint("TOP" .. p, frame, rp, x, -(top + 6 + 16))
            bar:SetPoint("BOTTOM" .. p, frame, rp, x, -(top + 6 + visible - 16))
            bar:Show()
            SyncBar()
            -- The mouse may be on the tracker already (a zone or the header
            -- clicked open): the watch sets the alpha now and stops itself
            -- at once when the mouse is elsewhere.
            bar:SetScript("OnUpdate", WatchHover)
            WatchHover(bar)
        else
            bar:Hide()
        end
        if fixed then
            height = top + 6 + room + foot + pad    -- Max Height, or more if the 40 floor for the list applies
        else
            -- No quests: the row 4 under the header, as at the top; with
            -- its box, the box's line on the header's seam line (one line),
            -- or 3 under the header row, where that seam would be.
            if contentH == 0 and footAt > 0 then
                local lineAt = seamDrawn and (seamAt - seamLine) or (top + 3)
                foot = lineAt + footAt - top - pad
            elseif contentH == 0 and foot > 0 then
                foot = 4 + ph
            end
            height = top + (contentH > 0 and (6 + visible) or 0) + foot + pad
        end
    end

    -- Background and border on whole pixels: an edge on half a pixel draws the
    -- border blurred.
    ns.Ellesmere.PixelSize(frame, W, height)
    frame:ClearAllPoints()
    ns.Ellesmere.PixelPoint(frame, "TOPRIGHT", UIParent, "TOPRIGHT", num(d.x, -40), num(d.y, -260))
    local bgHex, bgA = ns.BackgroundColor(d.useGlobalBackground, "background", d.bgColor, num(d.bgAlpha, 0.75))
    local r, g, b = ns.HexToRGB(bgHex)
    frame.bg:SetColorTexture(r, g, b, bgA)
    -- Header Background: with Header Seam it fills the header down to the seam
    -- line and the frame's background starts there; without, the frame's
    -- background covers the header. Joined, it also fills the progress box at
    -- the bottom (footBg), and the frame's background ends there.
    frame.bg:ClearAllPoints()
    frame.bg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, footAt - footBgTop)
    frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, footAt - footBgTop)
    -- Unset: the tracker's Background, so turning Header Seam on alone
    -- changes no colour. With Use Global Background: the Global Header
    -- Background, as the other modules' headers.
    local hHex, hA = ns.BackgroundColor(d.useGlobalBackground, "headerBackground",
        d.headerColor or d.bgColor, num(d.headerAlpha, num(d.bgAlpha, 0.75)))
    local hr, hg, hb = ns.HexToRGB(hHex)
    -- No quests, both boxes and no Always Max Height: the boxes meet on the
    -- header's seam line, drawn once by the header's seam (drawn twice, a
    -- translucent line or background came out darker); the frame's own
    -- background has no room left.
    local meet = footAt > 0 and contentH == 0 and seamDrawn and not fixed
    -- The progress row's box (joined), from the frame's bottom edge up to
    -- and with its seam line.
    if footAt > 0 then
        ns.PaintHeader(frame.footBg, hr, hg, hb, hA)
        frame.footBg:ClearAllPoints()
        frame.footBg:SetPoint("BOTTOMLEFT")
        frame.footBg:SetPoint("BOTTOMRIGHT")
        -- A solid seam thicker than the box (Border Size near 32 with a small
        -- Padding) leaves it no room under the header's line: no box then
        -- (0 is no size to SetHeight, and less is none at all).
        local footH = meet and (footAt - seamLine) or math.min(footAt - footBgTop, height)
        if footH > 0 then frame.footBg:SetHeight(footH) end
        frame.footBg:SetShown(footH > 0)
        frame.footSeam:SetShown(not meet)
    else
        frame.footBg:Hide()
        frame.footSeam:Hide()
    end
    -- The click that folds the guide (OnFootClick): the progress row's box,
    -- or the row with the padding under it and 3 over it without one. Not
    -- while unlocked, when a drag there moves the tracker.
    if guideHead and progress:IsShown() and not unlocked then
        frame.foot:ClearAllPoints()
        frame.foot:SetPoint("BOTTOMLEFT")
        frame.foot:SetPoint("BOTTOMRIGHT")
        frame.foot:SetHeight(footAt > 0 and footAt or (pad + progress:GetHeight() + 3))
        frame.foot:Show()
    else
        frame.foot:Hide()
    end
    frame.bg:SetShown(not meet)
    if seamDrawn then
        ns.PaintHeader(frame.headerBg, hr, hg, hb, hA)
        frame.headerBg:ClearAllPoints()
        frame.headerBg:SetPoint("TOPLEFT")
        frame.headerBg:SetPoint("TOPRIGHT")
        frame.headerBg:SetHeight(math.min(seamAt, height))
        frame.headerBg:Show()
        frame.bg:SetPoint("TOP", frame, "TOP", 0, -math.min(seamAt, height))
    else
        frame.headerBg:Hide()
        frame.bg:SetPoint("TOP")
    end
    -- Joined: the dock's border goes round the tracker and the step list, from
    -- a frame of ours not anchored to this one (protected with an item button).
    -- The dock waits out combat (a /reload in a fight): until it is up the
    -- tracker keeps its own border, and the draw after combat runs after the
    -- dock.
    local edgeJoined = joined and (ns.RXP.IsDocked() or not InCombatLockdown())
    ns.Border.Apply(frame, edgeJoined and NO_BORDER or d.border)
    frame:EnableMouse(unlocked)
    -- Nothing watched: no frame, unless it is being placed or the guide
    -- hangs under it.
    frame:SetShown(shown > 0 or unlocked or joined)
    SetTicker()
    PlaceDockAnchor()
    ns.RXP.SetDockFolded(guideHead and d.rxpFolded == true)
end

-- RXP's step list and step boxes under the tracker (Integrated), anchored
-- to the dock anchor so they follow the tracker as it grows, folds and
-- moves. The dock draws the tracker's border round both, at the tracker's
-- strata and level, which the anchor carries.
local function DockBorder() return DB().border end
function M.ApplyGuideDock()
    local d = DB()
    if d.rxpDock == "integrated" and frame then
        if not dockAnchor then
            dockAnchor = CreateFrame("Frame", nil, UIParent)
            -- Clamped as the tracker is (EnsureFrame): same point, same size,
            -- so a place past the screen's edge (a profile from a larger
            -- screen) puts both on the same rect.
            dockAnchor:SetClampedToScreen(true)
            PlaceDockAnchor()
        end
        dockAnchor:SetFrameStrata(frame:GetFrameStrata())
        dockAnchor:SetFrameLevel(frame:GetFrameLevel())
        ns.RXP.Dock(dockAnchor, num(d.rxpDockGap, 6), DockBorder, d.rxpStepsSide, d.scrollBarSide)
    else
        ns.RXP.Undock()
    end
end

function M.HideFrame()
    if not frame then return end
    if Frozen() then
        -- The module was switched off in combat: hiding the frame would
        -- hide its secure buttons, a protected operation. One shot at
        -- regen; a draw queued by a re-enable runs a frame after it
        -- (C_Timer.After), so it shows again last.
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(f)
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", nil)
            M.HideFrame()
        end)
        return
    end
    wipe(timerRows)
    SetTicker()
    frame:Hide()
    frame:EnableMouse(false)
end

-- ---------------------------------------------------------------------------
-- "Quest Completed" in the middle of the screen
-- ---------------------------------------------------------------------------

local done

-- `objective`: an objective done (its text under it), not the whole quest.
function M.ShowCompleted(title, objective)
    local key = objective and "objectiveText" or "completedText"
    if not DB()[key] then
        ns.Log("QUESTS", "%s off: no completed text", key)
        return
    end
    if not done then
        done = CreateFrame("Frame", nil, UIParent)
        done:SetFrameStrata("HIGH")
        done:SetSize(600, 80)
        done:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
        done.big = ns.Media.FontString(done)
        done.big:SetPoint("TOP")
        done.small = ns.Media.FontString(done)
        done.small:SetPoint("TOP", done.big, "BOTTOM", 0, -4)
        done.anim = done:CreateAnimationGroup()
        local fade = done.anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetStartDelay(2.5)
        fade:SetDuration(1.5)
        done.anim:SetScript("OnFinished", function() done:Hide() end)
    end
    local d = DB()
    local big = num(d.completedSize, 28)
    -- The tracker's font, always outlined.
    Font(done.big, big, "tracker", "OUTLINE")
    Font(done.small, M.CompletedTitleSize(), "tracker", "OUTLINE")
    done.big:SetTextColor(1, 0.82, 0)
    done.small:SetTextColor(1, 1, 1)
    done.big:SetText(objective and "Objective Completed" or "Quest Completed")
    done.small:SetText(title or "")
    done.anim:Stop()
    done:SetAlpha(1)
    done:Show()
    done.anim:Play()
end

-- The quest name under "Quest Completed": its own size, or 16/28 of
-- Completed Size until that is set.
function M.CompletedTitleSize()
    local d = DB()
    return num(d.completedTitleSize, math.max(8, math.floor(num(d.completedSize, 28) * 16 / 28 + 0.5)))
end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------

local function SliderCell(text, tip, key, minV, maxV, fallback, changed)
    return { type = "slider", text = text, min = minV, max = maxV, step = 1, tooltip = tip,
        getValue = function() return num(DB()[key], fallback) end,
        setValue = function(v) DB()[key] = v; changed() end }
end

local function ColorCell(text, tip, colorKey, alphaKey, fallbackAlpha, changed)
    return { type = "colorpicker", text = text, tooltip = tip, hasAlpha = true,
        getValue = function()
            local r, g, b = ns.HexToRGB(DB()[colorKey])
            return r, g, b, num(DB()[alphaKey], fallbackAlpha)
        end,
        setValue = function(r, g, b, a)
            DB()[colorKey] = ns.RGBToHex(r, g, b)
            DB()[alphaKey] = a or 1
            changed()
        end }
end

local function ToggleCell(text, tip, key, changed)
    return { type = "toggle", text = text, tooltip = tip,
        getValue = function() return DB()[key] == true end,
        setValue = function(v) DB()[key] = v and true or false; changed() end }
end

-- The off label under each tab.
local function OffRow(W, parent, y)
    if ns.IsModuleEnabled("questTracker") then return y end
    local _, h = W:DualRow(parent, y,
        { type = "label", text = "Quest Tracker is off: turn it on under Modules on the General page." })
    return y - h
end

-- Advanced: the XP after quest titles.
local function AdvancedPage(parent, y, W)
    local _, h
    local function changed() ns.Apply() end
    _, h = W:SectionHeader(parent, "QUEST XP", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "XP Size", min = 8, max = 20, step = 1,
          tooltip = "Font size of the XP after quest titles (Quest XP on the Quest Tracker tab). Follows Title Size until you move it.",
          getValue = function() return num(DB().xpSize, num(DB().titleSize, 12)) end,
          setValue = function(v) DB().xpSize = v; changed() end },
        ColorCell("XP Color", "Colour and opacity of the XP after quest titles.", "xpColor", "xpAlpha", 1, changed)); y = y - h
    return OffRow(W, parent, y)
end

-- RXP: what the tracker does with a loaded RestedXP guide.
local function RXPPage(parent, y, W)
    local _, h
    local function changed() ns.Apply() end
    _, h = W:SectionHeader(parent, "RESTEDXP GUIDE", y); y = y - h
    _, h = W:DualRow(parent, y,
        ToggleCell("Guide Dot", "A small blue dot before quests the loaded RestedXP guide names.", "rxpDot", changed),
        ToggleCell("Guide Dot in Dialogs", "The same blue dot on the guide's quests in NPC dialogs: the gossip list and the quest greeting.", "rxpDialogDot", changed)); y = y - h
    _, h = W:DualRow(parent, y,
        ToggleCell("Guide Progress", "The loaded guide's name and progress (current step of all steps) under the header. With Guide Window Integrated: at the tracker's bottom, over the step list, as the guide's header; click it to fold RestedXP's step list, step boxes and timer bars away and back.", "rxpProgress", function()
            changed()
            ns.Ellesmere.RefreshPage()      -- grey Guide Header Height in or out
        end),
        { type = "spacer" }); y = y - h
    _, h = W:DualRow(parent, y,
        ToggleCell("Guide Highlight", "A box across the tracker behind the titles of the quests in the guide's current steps, the ones at the top of RestedXP's window. Works together with the dot.", "rxpHighlight", changed),
        ColorCell("Highlight", "Colour and opacity of the Guide Highlight box. Its 1 px border takes the same colour at half opacity.", "highlightColor", "highlightAlpha", 0.25, changed)); y = y - h
    local noRXP = function() return not ns.RXP.IsLoaded() end
    if noRXP() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "RestedXP Guides is not loaded: the tracker keeps Blizzard's order and shows no dot, highlight, progress or guide window." }); y = y - h
    end

    _, h = W:SectionHeader(parent, "GUIDE WINDOW", y); y = y - h
    local dockGap = SliderCell("Guide Gap", "Pixels between the step list and RestedXP's current step box under it (to the top of its step badge).", "rxpDockGap", 0, 30, 6, changed)
    dockGap.disabled = function() return noRXP() or DB().rxpDock ~= "integrated" end
    dockGap.disabledTooltip = "This option needs Guide Window set to Integrated."
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Guide Window",
          values = { standalone = "Standalone", integrated = "Integrated" },
          order = { "standalone", "integrated" },
          tooltip = "Integrated: RestedXP's step list hangs under the tracker, as wide as it, in one border with a seam, and RestedXP's current step box under the list. No RestedXP header or footer; the list's scroll bar and options cog show when the mouse is on the list. Standalone: RestedXP's own window, where you put it. Active Targets and Active Items stay their own windows.",
          disabled = noRXP, disabledTooltip = "This option needs RestedXP Guides loaded.",
          getValue = function() return DB().rxpDock end,
          setValue = function(v)
              DB().rxpDock = v
              changed()
              ns.Ellesmere.RefreshPage()      -- grey Guide Gap, Step List Height and Guide Header Height in or out
          end },
        dockGap); y = y - h
    -- RXP's own window height, read from the list each time the page is drawn.
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Step List Height", min = 40, max = 800, step = 1,
          tooltip = "Height of RestedXP's step list under the tracker. It is RestedXP's own window height, the one an Alt-drag of its corner sets, so it also holds in Standalone.",
          disabled = function() return ns.RXP.ListHeight() == nil end,
          disabledTooltip = "This option needs Guide Window on Integrated and RestedXP's step list shown (Show step list in RestedXP's options, and the guide not folded away in the tracker).",
          getValue = function() return ns.RXP.ListHeight() or 108 end,
          setValue = function(v) ns.RXP.SetListHeight(v) end },
        (function()
            local c = SliderCell("Guide Header Height", "Height of the guide's header box at the tracker's bottom, where the guide's name and progress are; the text stays centred. 0 follows the text and Padding. Needs a border that draws the seam line above the box.", "guideHeaderHeight", 0, 60, 0, changed)
            c.disabled = function() return noRXP() or DB().rxpDock ~= "integrated" or not DB().rxpProgress end
            c.disabledTooltip = "This option needs Guide Window on Integrated and Guide Progress on."
            return c
        end)()); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Steps Position",
          values = { under = "Under", left = "Left", right = "Right" },
          order = { "under", "left", "right" },
          tooltip = "Where RestedXP's step boxes stand. Under: under the step list. Left or Right: beside the tracker, level with its top, the newest step first; Guide Gap is then the space to the tracker. Changes made in combat show when combat ends.",
          disabled = function() return noRXP() or DB().rxpDock ~= "integrated" end,
          disabledTooltip = "This option needs Guide Window set to Integrated.",
          getValue = function() return DB().rxpStepsSide or "under" end,
          setValue = function(v) DB().rxpStepsSide = v; changed() end },
        { type = "spacer" }); y = y - h
    return OffRow(W, parent, y)
end

function M:BuildPage(pageName, parent, y, W)
    local _, h
    local function changed() ns.Apply() end
    local E = ns.Ellesmere
    if pageName == "Advanced" then return AdvancedPage(parent, y, W) end
    if pageName == "RXP" then return RXPPage(parent, y, W) end

    if not E.QuestTrackerLoaded() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Ellesmere's Quest Tracker is not loaded, so Blizzard's tracker is still shown. Turn Ellesmere's Quest Tracker on, or another addon has to hide Blizzard's tracker: ProseccoAdditions does not, since hiding it from addon code can taint it." }); y = y - h
    end

    _, h = W:SectionHeader(parent, "SET ELLESMERE SETTINGS", y); y = y - h
    local names = {}
    for _, o in ipairs(M.OWNED) do names[#names + 1] = o.label end
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Use it if you changed them in Ellesmere's or Questie's options." },
        { type = "button", text = "Set Values Again", width = 180,
          disabled = function() return not ns.IsModuleEnabled("questTracker") end,
          disabledTooltip = "This option needs Quest Tracker on.",
          onClick = function()
              ns.Ellesmere.Confirm({
                  title = "Quest Tracker: hide the other trackers",
                  message = "Set these again, so only ProseccoAdditions' tracker shows?\n- " .. table.concat(names, "\n- "),
                  confirmText = "Set and reload",
                  reload = true,
                  onConfirm = M.WriteOwned,
              })
          end }); y = y - h

    _, h = W:SectionHeader(parent, "POSITION AND SIZE", y); y = y - h
    _, h = W:DualRow(parent, y,
        ToggleCell("Unlock (drag with the mouse)", "While unlocked the tracker can be dragged by its header, and is shown even with nothing tracked.", "unlocked", changed),
        SliderCell("Width", "Width of the tracker.", "width", 160, 480, 260, changed)); y = y - h
    _, h = W:DualRow(parent, y,
        SliderCell("Max Height", "The tracker grows with its quests up to this height; past it, scroll with the mouse wheel.", "maxHeight", 150, 1000, 520, changed),
        ToggleCell("Always Max Height", "The tracker is always Max Height tall, however few quests it holds. Collapsing it with a header click still folds it to the header (with the guide's progress row in Guide Window: Integrated while the guide is open).", "fixedHeight", changed)); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Scroll Bar Side",
          values = { right = "Right", left = "Left" },
          order = { "right", "left" },
          tooltip = "Which side of the tracker the quest list's scroll bar sits on, and in Guide Window: Integrated also the step list's scroll bar and the guide's cog.",
          getValue = function() return DB().scrollBarSide or "right" end,
          setValue = function(v) DB().scrollBarSide = v; changed() end },
        SliderCell("Padding", "Pixels between the tracker's edge and its text.", "padding", 0, 24, 8, changed)); y = y - h
    _, h = W:DualRow(parent, y,
        SliderCell("Header Height", "Height of the \"Quests\" header; its text stays centred. 0 follows the text size.", "headerHeight", 0, 60, 0, changed),
        SliderCell("Objective Spacing", "Pixels between a quest's title and the first line under it (objectives, turn-in, timer).", "objectiveSpacing", 0, 20, 1, changed)); y = y - h

    _, h = W:SectionHeader(parent, "FRAME", y); y = y - h
    local function follows() return DB().useGlobalBackground == true end
    local headerBg = ns.BackgroundCell({ text = "Header Background",
        tooltip = "Background of the header above the Attached header line, and of the guide progress box at the bottom in Guide Window: Integrated. Without Attached header the header has the tracker's Background.",
        cfg = DB, colorKey = "headerColor", alphaKey = "headerAlpha", default = 0.75,
        follows = follows, onChange = changed,
        -- The progress box needs the guide's progress row (Draw); a guide
        -- loaded or not is not followed here, as a border that draws no
        -- seam is not for Header Seam.
        disabled = function()
            local d = DB()
            return not d.headerSeam and not (d.rxpDock == "integrated" and d.rxpProgress and ns.RXP.IsLoaded())
        end,
        disabledTooltip = "This option needs Attached header on, or Guide Window on Integrated with Guide Progress on." })
    if headerBg then
        local getHeaderBg = headerBg.getValue
        headerBg.getValue = function()
            if DB().headerColor then return getHeaderBg() end
            local r, g, b = ns.HexToRGB(DB().bgColor)
            return r, g, b, num(DB().bgAlpha, 0.75)
        end
    end
    y = ns.Rows(W, parent, y,
        ns.UseGlobalBackgroundCell(DB, changed),
        ns.BackgroundCell({ text = "Background", tooltip = "Background of the tracker.",
            cfg = DB, colorKey = "bgColor", alphaKey = "bgAlpha", default = 0.75,
            follows = follows, onChange = changed }),
        ToggleCell("Attached header", "A line of the tracker's border under the header, edge to edge. The header above it gets Header Background.", "headerSeam", function()
            changed()
            ns.Ellesmere.RefreshPage()      -- grey Header Background in or out
        end),
        headerBg)

    _, h = W:SectionHeader(parent, "BORDER", y); y = y - h
    y = ns.Border.Rows(W, parent, y, function() return DB().border end, changed)

    _, h = W:SectionHeader(parent, "TEXT", y); y = y - h
    local fonts, fontOrder = ns.Media.FontList(true)
    local outlines, outlineOrder = ns.Media.OutlineList(true)
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Font", values = fonts, order = fontOrder,
          tooltip = "Every text in the tracker. The Quest Completed text uses it too. Global font follows the Global Settings page.",
          getValue = function() return DB().font end,
          setValue = function(v) DB().font = v; changed() end },
        { type = "dropdown", text = "Outline", values = outlines, order = outlineOrder,
          tooltip = "Every text in the tracker. Shadow is a drop shadow without an outline; Ellesmere's outline also takes Ellesmere's shadow when its Outline Mode uses one. The Quest Completed text is always outlined. Global outline follows the Global Settings page.",
          getValue = function() return DB().outline end,
          setValue = function(v) DB().outline = v; changed() end }); y = y - h
    _, h = W:DualRow(parent, y,
        SliderCell("Header Size", "Font size of the \"Quests\" header.", "headerSize", 8, 24, 13, changed),
        SliderCell("Title Size", "Font size of zone names and quest titles.", "titleSize", 8, 20, 12, changed)); y = y - h
    _, h = W:DualRow(parent, y,
        SliderCell("Objective Size", "Font size of objectives and the guide progress.", "objectiveSize", 8, 18, 10, changed),
        { type = "spacer" }); y = y - h

    _, h = W:SectionHeader(parent, "QUESTS", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Completed Quests",
          values = { top = "Top of the zone", bottom = "Bottom of the zone", inorder = "In order" },
          order = { "top", "bottom", "inorder" },
          tooltip = "Where quests that are ready to turn in go within their zone.",
          getValue = function() return DB().completed end,
          setValue = function(v) DB().completed = v; changed() end },
        ToggleCell("Current Zone Only", "Other zones are folded to one line with their number of quests; click one to open it.", "currentZoneOnly", changed)); y = y - h
    _, h = W:DualRow(parent, y,
        ToggleCell("Turn-in NPC", "Completed quests show who to turn in to and where, from Questie's database, instead of \"Ready to turn in\".", "turnIn", changed),
        ToggleCell("Quest XP", "The quest's XP after the title, abbreviated (1.2k). Its size and colour are on the Advanced tab.", "questXP", changed)); y = y - h
    local itemSize = SliderCell("Item Button Size", "Size of the quest item buttons.", "itemSize", 18, 40, 26, changed)
    itemSize.disabled = function() return not DB().itemButtons end
    itemSize.disabledTooltip = "This option needs Quest Item Buttons on."
    _, h = W:DualRow(parent, y,
        ToggleCell("Quest Item Buttons", "The quest's usable item as a clickable button at the quest's right edge. While any quest has one, the tracker waits out combat before it redraws.", "itemButtons", function()
            changed()
            ns.Ellesmere.RefreshPage()      -- grey Item Button Size in or out
        end),
        itemSize); y = y - h
    local warn = ToggleCell("Abandon Warning", "Ask before an alt-click abandons a quest. Off: the quest is abandoned at once.", "abandonConfirm", changed)
    warn.disabled = function() return not DB().altAbandon end
    warn.disabledTooltip = "This option needs Alt-Click Abandons on."
    _, h = W:DualRow(parent, y,
        ToggleCell("Alt-Click Abandons", "Alt-click a quest title to abandon the quest.", "altAbandon", function()
            changed()
            ns.Ellesmere.RefreshPage()      -- grey Abandon Warning in or out
        end),
        warn); y = y - h
    if not _G.LibQuestieDB then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "QuestieDB is not loaded: completed quests show \"Ready to turn in\" without the NPC." }); y = y - h
    end

    _, h = W:SectionHeader(parent, "QUEST COMPLETED POP-UP TEXT", y); y = y - h
    _, h = W:DualRow(parent, y,
        ToggleCell("Quest Completed Text", "\"Quest Completed\" in large text in the middle of the screen when a quest's objectives are all done. Fades out after a few seconds.", "completedText", changed),
        { type = "button", text = "Show Example", width = 160,
          disabled = function() return not ns.IsModuleEnabled("questTracker") or not DB().completedText end,
          disabledTooltip = "This option needs Quest Tracker and Quest Completed Text on.",
          onClick = function() M.ShowCompleted("Example Quest") end }); y = y - h
    _, h = W:DualRow(parent, y,
        ToggleCell("Objective Completed Text", "\"Objective Completed\" the same way, with the objective under it, when one objective of a quest is done and the quest is not complete yet.", "objectiveText", changed),
        { type = "button", text = "Show Example", width = 160,
          disabled = function() return not ns.IsModuleEnabled("questTracker") or not DB().objectiveText end,
          disabledTooltip = "This option needs Quest Tracker and Objective Completed Text on.",
          onClick = function() M.ShowCompleted("Kobolds slain: 8/8", true) end }); y = y - h
    _, h = W:DualRow(parent, y,
        SliderCell("Completed Size", "Font size of the Quest Completed and Objective Completed texts. The quest name under them follows until Quest name size is moved.", "completedSize", 12, 48, 28, changed),
        { type = "slider", text = "Quest name size", min = 8, max = 40, step = 1,
          tooltip = "Font size of the quest name under Quest Completed. Follows Completed Size until you move it.",
          getValue = function() return M.CompletedTitleSize() end,
          setValue = function(v) DB().completedTitleSize = v; changed() end }); y = y - h

    return OffRow(W, parent, y)
end
