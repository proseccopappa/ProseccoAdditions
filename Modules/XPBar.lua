-- ProseccoAdditions / Modules / XPBar.lua
-- An XP bar with the level and percent on it and the levelling numbers in an
-- info panel over it. Behind the XP fill, the XP of completed quests in the
-- log and the rested XP show how far they reach.
--
-- "Time this level" comes from TIME_PLAYED_MSG, which only arrives after
-- RequestTimePlayed (Blizzard prints the /played reply in the chat). The
-- module asks once per login when "Ask Time Played" is on.
--
-- The session lasts from a real login to the logout: a /reload keeps it. It
-- is saved per character at PLAYER_LOGOUT with the login's stamp and taken
-- back at the next Enable only for the same login. A level up restarts the
-- time this level, not the session.
--
-- Our frame only, not secure: shown, moved and drawn in combat too. Hidden
-- at the level cap or with XP gain turned off.
--
-- Off: the bar is hidden, no events, no ticker.

local _, ns = ...

local M = ns.RegisterModule("xpBar", {
    title       = "XP Bar",
    description = "An XP bar with time this level and session, XP per hour, time to level, and the XP of completed quests and rested XP.",
    pages       = { "XP Bar" },
    defaults    = {
        width = 470, height = 22,
        point = "CENTER", x = 0, y = -250,
        unlocked = false,
        textSize = 12,          -- the text on the bar
        -- The info panel's text; its header's is 15 % smaller.
        panelTextSize = 14,
        -- Seconds after the mouse left the bar and panel before the open panel
        -- closes; 0 never. Counted by the bar's 1 s ticker.
        infoClose = 5,
        -- The quest fill (and its border) only while the mouse is over the
        -- bar or panel.
        questMouseover = false,
        -- The level and percent on the bar only while the mouse is over the bar
        -- or panel.
        textMouseover = false,
        -- The panel's body background alpha in percent; nil: the global
        -- background's.
        panelAlpha = nil,
        panelColor = nil,       -- its colour (hex); nil: the global background's
        -- A mark every 10 % (TICK).
        ticks = true,
        -- With no XP to gain (level 60) the bar shows the watched faction's
        -- reputation instead of hiding.
        repAtMax = true,
        -- The bar's own border, the global border's by default. The info panel
        -- and Reset Session keep the global border.
        border = { useGlobal = true, style = "solid", size = 1, color = "000000", alpha = 1 },
        askPlayed = true,       -- RequestTimePlayed once per login
        texture = "none",       -- Ellesmere bar texture key, or flat colour
        -- Purple XP, orange quests, blue rested.
        xpColor = "9B1FD6", questColor = "F28C0F", restedColor = "2E6FD9",
    },
})

local function DB() return ns.db.modules.xpBar end

local BORDER = { useGlobal = true }
-- The 10 % marks: 1 px black solid lines whatever the border's style.
local TICK = { style = "solid", size = 1, color = "000000", alpha = 1 }
-- A border round each fill (XP, quests, rested), under the bar's border, so
-- what shows is a line where the fill ends.
local FILL_EDGE = { style = "solid", size = 1, color = "000000", alpha = 1 }
local PANEL_GAP = 16        -- px between the bar and the info panel
-- With rested XP the XP fill takes the rested colour and the rested part
-- shows in it at this alpha.
local RESTED_ALPHA = 0.38

-- The info panel's words in grey, its numbers white.
local GREY = "|cffb3b3b3"

-- Runtime only
local frame, host, ticker
local active = false
local Update                        -- the numbers and texts (below)
local FitPanel                      -- the info panel's height (below)
local hovered = false               -- the mouse over the bar or its panel (Hover)
local panelOpen = false             -- Info on Click: the panel opened by a click
local leftAt                        -- when the mouse left; nil while over
local sessionStart = GetTime()      -- Time this session's start
local rateStart                     -- when the XP count started (Enable): XP/hr and Level in
local sessionXP = 0                 -- XP gained since rateStart
local lastXP, lastMax, lastLevel    -- for the gain on the next PLAYER_XP_UPDATE
local levelPlayed, levelPlayedAt    -- seconds at this level, GetTime() then
local questXP = 0
local killXP                        -- XP of the last kill: Kills to level
local repMode = false               -- the bar shows the watched reputation
local barHot = false                -- the bar's border is the hover border
local questDirty = true
local shownText = {}                -- fontstring -> text last set

-- ---------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------

local function Comma(n)
    local s = tostring(math.floor(n + 0.5))
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function Duration(sec)
    sec = math.max(0, math.floor(sec))
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

-- The XP of every completed quest in the log, read as the Quest Tracker
-- reads a quest's XP. An API this build lacks counts 0.
local function ReadQuestXP()
    local sum, i = 0, 1
    if not (C_QuestLog and C_QuestLog.GetInfo and GetQuestLogRewardXP) then return 0 end
    while true do
        local info = C_QuestLog.GetInfo(i)
        if not info then break end
        local id = info.questID
        if not info.isHeader and id and id > 0 and C_QuestLog.IsComplete(id) then
            -- baseXp, the number Blizzard's reward tooltip and our tracker show.
            local _, base = GetQuestLogRewardXP(id)
            if type(base) == "number" and base > 0 then sum = sum + base end
        end
        i = i + 1
    end
    return sum
end

-- No XP to gain: the level cap, or XP gain turned off.
-- IsPlayerAtEffectiveMaxLevel and IsXPUserDisabled are Mainline APIs
-- (Inferred for Forever); without them only UnitXPMax decides.
local MAX_LEVEL = 60

local function NoXP()
    if (tonumber(UnitXPMax("player")) or 0) <= 0 then return true end
    -- Level 60 is the cap with Forever's Classic content. The retail calls
    -- below may name a higher cap there (Unverified), so the level is checked
    -- by itself.
    if (tonumber(UnitLevel("player")) or 0) >= MAX_LEVEL then return true end
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    return false
end

-- The watched faction's name, reaction and standing between the
-- reaction's thresholds. C_Reputation.GetWatchedFactionData is the Mainline
-- call (Inferred for Forever), GetWatchedFactionInfo the older one.
local function WatchedRep()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local t = C_Reputation.GetWatchedFactionData()
        if t and t.name then
            return t.name, t.reaction, t.currentReactionThreshold, t.nextReactionThreshold, t.currentStanding
        end
        return nil
    end
    if GetWatchedFactionInfo then
        local name, reaction, minV, maxV, value = GetWatchedFactionInfo()
        if name then return name, reaction, minV, maxV, value end
    end
    return nil
end

-- The kill line in the chat, as a pattern from Blizzard's own format
-- ("%s dies, you gain %d experience."; its rested and group bonus texts
-- follow it, and its number is the whole gain). Built once; false when this
-- client lacks the string.
local killPattern
local function KillPattern()
    if killPattern == nil then
        local f = _G.COMBATLOG_XPGAIN_FIRSTPERSON
        if type(f) ~= "string" then
            killPattern = false
        else
            local pat = f:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            pat = pat:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
            killPattern = "^" .. pat
        end
    end
    return killPattern
end

-- A white border while the mouse is over the bar or the Reset Session
-- button, in that border's style and size. Without `cfg` the global one's.
local function HoverBorder(cfg)
    local g = ns.Border.Resolve(cfg or BORDER)
    return { style = g.style, size = g.size, color = "FFFFFF", alpha = 1, offsetX = g.offsetX, offsetY = g.offsetY }
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function Set(fs, text)
    if shownText[fs] ~= text then
        shownText[fs] = text
        fs:SetText(text)
        return true
    end
end

local function Bar(parent, level)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetAllPoints(parent)
    b:SetFrameLevel(level)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    return b
end

local function Text(parent, point, rel, relPoint, x, y, justify)
    local fs = ns.Media.FontString(parent, "OVERLAY")
    fs:SetPoint(point, rel, relPoint, x, y)
    fs:SetJustifyH(justify)
    fs:SetWordWrap(false)
    fs:SetTextColor(1, 1, 1, 1)
    return fs
end

-- Only while unlocked: the bar takes the mouse for Info on Click too, and a
-- click with a small move would start a drag.
local function OnDragStart(self)
    if DB().unlocked ~= true then return end
    self.dragLeft, self.dragBottom = self:GetLeft(), self:GetBottom()
    self:StartMoving()
end

-- StopMovingOrSizing re-anchors the frame to the screen; the drag becomes
-- new offsets of our own instead, so the saved position is the one the page
-- shows.
local function OnDragStop(self)
    if not self.dragLeft then return end        -- locked: no drag was started
    self:StopMovingOrSizing()
    local d = DB()
    d.x = math.floor((tonumber(d.x) or 0) + (self:GetLeft() - self.dragLeft) + 0.5)
    d.y = math.floor((tonumber(d.y) or 0) + (self:GetBottom() - self.dragBottom) + 0.5)
    self.dragLeft, self.dragBottom = nil, nil
    ns.Apply()
    ns.Ellesmere.RefreshPage()
end

local function EnsureFrame()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(2)
    frame:SetMovable(true)
    frame:SetDontSavePosition(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop", OnDragStop)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    -- Quests behind the XP, and the faded rested fill over both; its alpha
    -- keeps the XP and quests visible through it.
    frame.quest = Bar(frame, 3)
    frame.xp = Bar(frame, 4)
    frame.rested = Bar(frame, 5)
    -- Borders on frames of their own above the bars (ns.Border.Apply draws at
    -- its frame's level +1, which the bars covered on `frame`). The fill's
    -- border reaches from the bar's left edge to the end of its fill: its width
    -- is set in Update. Not anchored to the status bar's fill texture:
    -- FIELD RESULT 2026-10-13 (dev72): that anchor made the bar's own SetPoint
    -- fail ("SetPoint would result in anchor family connection").
    frame.fillEdges = {}
    for _, k in ipairs({ "rested", "quest", "xp" }) do
        local e = CreateFrame("Frame", nil, frame)
        e:SetFrameLevel(6)
        e:SetPoint("TOPLEFT", frame, "TOPLEFT")
        e:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
        frame.fillEdges[k] = e
    end
    frame.fillEdge = frame.fillEdges.xp
    -- The 10 % marks: a vertical seam line (TICK) on the right edge of nine
    -- frames from the bar's left edge, each as wide as its share (Layout).
    -- Over the fills and their borders, under the bar's border.
    frame.ticks = {}
    for i = 1, 9 do
        local t = CreateFrame("Frame", nil, frame)
        t:SetFrameLevel(8)
        t:SetPoint("TOPLEFT", frame, "TOPLEFT")
        t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
        t.tex = t:CreateTexture(nil, "OVERLAY")
        frame.ticks[i] = t
    end
    frame.edge = CreateFrame("Frame", nil, frame)
    frame.edge:SetAllPoints()
    frame.edge:SetFrameLevel(9)
    local over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints()
    over:SetFrameLevel(11)          -- over the bars and both borders
    frame.level = Text(over, "LEFT", over, "LEFT", 6, 0, "LEFT")
    frame.pct = Text(over, "RIGHT", over, "RIGHT", -6, 0, "RIGHT")
    frame.hint = Text(over, "BOTTOM", over, "TOP", 0, 3, "CENTER")
    -- The info panel: our frame over the bar, the General page's border and
    -- background. Its lines are placed in Layout.
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetFrameLevel(12)
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    -- The progress row's header box: a texture on the panel, over its
    -- background and under its texts and border.
    panel.header = panel:CreateTexture(nil, "BORDER")
    frame.panel = panel
    -- The progress row: "Progress:", the XP, what is left and a Reset Session
    -- button. Everything is placed in Layout.
    frame.progress = Text(panel, "LEFT", panel, "TOPLEFT", 8, 0, "LEFT")
    frame.progress:SetText("Progress:")
    frame.progress:SetTextColor(0.7, 0.7, 0.7, 1)
    frame.topC = Text(panel, "LEFT", frame.progress, "RIGHT", 6, 0, "LEFT")
    frame.remain = Text(panel, "LEFT", frame.topC, "RIGHT", 6, 0, "LEFT")
    frame.remain:SetTextColor(0.7, 0.7, 0.7, 1)
    -- A seam line under the progress row, then the columns (Layout).
    frame.seam = CreateFrame("Frame", nil, panel)
    frame.seam.tex = frame.seam:CreateTexture(nil, "OVERLAY")
    -- Under it one sentence with the times and rates, wrapped to the panel's
    -- width, then the quests and rested line.
    frame.sentence = Text(panel, "TOPLEFT", panel, "TOPLEFT", 8, 0, "LEFT")
    frame.sentence:SetWordWrap(true)
    frame.bonus = Text(panel, "TOPLEFT", panel, "TOPLEFT", 8, 0, "LEFT")
    -- Reset: the session's time and XP count start over.
    local reset = CreateFrame("Button", nil, panel)
    reset.tex = reset:CreateTexture(nil, "BACKGROUND")
    reset.tex:SetAllPoints()
    reset.text = Text(reset, "CENTER", reset, "CENTER", 0, 0, "CENTER")
    reset.text:SetText("Reset Session")
    reset.text:SetTextColor(0.7, 0.7, 0.7, 1)
    reset:SetScript("OnClick", function()
        sessionStart = GetTime()
        if rateStart then rateStart, sessionXP = sessionStart, 0 end
        Update()
    end)
    frame.reset = reset
    -- Quests on Mouseover: the mouse over the bar or the open panel. The
    -- gap between them counts as the panel's, so moving up does not hide it.
    local function Hover()
        local d = DB()
        local gap = PANEL_GAP
        local overBar = frame:IsMouseOver()
        hovered = overBar or (panel:IsShown() and panel:IsMouseOver(0, -gap, 0, 0))
        leftAt = not hovered and (leftAt or GetTime()) or nil
        if overBar ~= barHot then
            barHot = overBar
            ns.Border.Apply(frame.edge, overBar and HoverBorder(d.border) or d.border)
        end
        if d.textMouseover == true then
            frame.level:SetShown(hovered)
            frame.pct:SetShown(hovered)
        end
        if d.questMouseover then Update() end
    end
    -- Info on Click: a left click on the bar or the panel opens or closes
    -- it. Not while unlocked, where a left drag moves the bar, nor in the
    -- reputation mode, which has no panel. Shift-click posts the progress.
    local function Toggle(_, button)
        local d = DB()
        if button == "LeftButton" and IsShiftKeyDown() then
            if d.unlocked ~= true then M.Announce() end     -- unlocked: the end of a drag
            return
        end
        if button ~= "LeftButton" or d.unlocked == true or repMode then return end
        panelOpen = not panelOpen
        panel:SetShown(panelOpen)
        Hover()
    end
    frame:SetScript("OnMouseUp", Toggle)
    panel:SetScript("OnMouseUp", Toggle)
    frame:SetScript("OnEnter", Hover)
    frame:SetScript("OnLeave", Hover)
    panel:SetScript("OnEnter", Hover)
    panel:SetScript("OnLeave", Hover)
    -- Leaving the panel over the button: the button's leave decides.
    reset:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1, 1)
        ns.Border.Apply(self, HoverBorder())
        Hover()
    end)
    reset:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.7, 0.7, 0.7, 1)
        ns.Border.Apply(self, BORDER)
        Hover()
    end)
    frame:Hide()
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        xpcall(Update, ns.ErrorHandler("xpBar:tick"))
    end)
end

-- The panel's height from its texts: the header, the sentence's wrapped
-- lines, the quests and rested line. Layout stores the measures it uses.
function FitPanel()
    local panel = frame.panel
    if not panel.top then return end
    -- The body's padding over and under its text, and an empty line between
    -- the sentence and the quests and rested line.
    local bodyPad = 9
    local y = panel.top + bodyPad
    frame.sentence:ClearAllPoints()
    frame.sentence:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -y)
    y = y + math.ceil(frame.sentence:GetStringHeight()) + 4 + panel.size + 4
    frame.bonus:ClearAllPoints()
    frame.bonus:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -y)
    y = y + panel.size + 4
    local h = y - 4 + bodyPad
    ns.Ellesmere.PixelSize(panel, frame:GetWidth(), h)
end

-- Each fill's border, as wide as the fill. No fill (no quests or rested
-- beyond the XP), no border: it would draw round a zero-width box or on
-- the XP's. Whole pixels, so its lines are sharp.
local function Edge(e, fill, show)
    if show and fill > 0 then
        local u = ns.Ellesmere.PixelUnit(frame)
        e:SetWidth(math.max(u, ns.Border.Snap(frame:GetWidth() * math.min(1, fill), u)))
        e:Show()
    else
        e:Hide()
    end
end

-- Reputation at Max Level: the watched faction on the bar, its name for the
-- level and its percent; no quests, rested or panel. False when no faction
-- is watched (the bar then hides).
local function ShowRep()
    local name, reaction, minV, maxV, value = WatchedRep()
    if not name then return false end
    repMode = true
    frame:Show()
    frame.panel:Hide()
    frame.quest:Hide()
    frame.rested:Hide()
    frame.fillEdges.quest:Hide()
    frame.fillEdges.rested:Hide()
    local span = (tonumber(maxV) or 0) - (tonumber(minV) or 0)
    local fill = span > 0 and math.max(0, math.min(1, ((tonumber(value) or 0) - minV) / span)) or 1
    frame.xp:SetValue(fill)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then
        frame.xp:SetStatusBarColor(c.r, c.g, c.b, 1)
    else
        frame.xp:SetStatusBarColor(ns.HexToRGB(DB().xpColor))
    end
    Edge(frame.fillEdges.xp, fill, true)
    Set(frame.level, name)
    Set(frame.pct, ("%.1f%%"):format(fill * 100))
    return true
end

Update = function()
    if not (active and frame) then return end
    if NoXP() then
        StopTicker()
        if DB().repAtMax == true and ShowRep() then return end
        -- The ticker stays stopped until an XP or level event. repMode
        -- stays set while hidden, so the way back below shows the rested
        -- fill and the panel.
        frame:Hide()
        return
    end
    local d = DB()
    if repMode then
        repMode = false
        frame.rested:Show()
        frame.panel:SetShown(panelOpen)
    end
    frame:Show()
    StartTicker()
    local close = tonumber(d.infoClose) or 0
    if panelOpen and close > 0 and leftAt and GetTime() - leftAt >= close then
        panelOpen = false
        frame.panel:Hide()
    end
    local cur, max = tonumber(UnitXP("player")) or 0, tonumber(UnitXPMax("player")) or 1
    local rested = tonumber(GetXPExhaustion and GetXPExhaustion()) or 0
    if questDirty then
        questXP = ReadQuestXP()
        questDirty = false
    end
    frame.xp:SetValue(math.min(1, cur / max))
    local xr, xg, xb = ns.HexToRGB(rested > 0 and d.restedColor or d.xpColor)
    frame.xp:SetStatusBarColor(xr, xg, xb, 1)
    frame.quest:SetValue(math.min(1, (cur + questXP) / max))
    local questShown = d.questMouseover ~= true or hovered
    frame.quest:SetShown(questShown)
    frame.rested:SetValue(math.min(1, (cur + rested) / max))
    Edge(frame.fillEdges.xp, cur / max, true)
    Edge(frame.fillEdges.quest, (cur + questXP) / max, questShown and questXP > 0)
    Edge(frame.fillEdges.rested, (cur + rested) / max, rested > 0)

    local now = GetTime()
    local elapsed = now - sessionStart
    local counted = now - (rateStart or now)
    local rate = counted > 0 and sessionXP / counted * 3600 or 0       -- XP per hour
    local left = max - cur
    local qc, rc = d.questColor, d.restedColor

    Set(frame.level, "Level " .. (UnitLevel("player") or 0))
    Set(frame.topC, ("%s / %s XP"):format(Comma(cur), Comma(max)))
    Set(frame.remain, ("(%s left)"):format(Comma(left)))
    Set(frame.pct, ("%.1f%% (%.1f%%)"):format(cur / max * 100, (cur + questXP) / max * 100))
    local text = (GREY .. "Time played this level:|r %s" .. GREY .. ", time this session:|r %s" .. GREY
        .. ".\nLevel in:|r %s " .. GREY .. "(|r%s" .. GREY .. " XP per hour), that's around|r %s " .. GREY .. "kills.|r"):format(
        levelPlayed and Duration(levelPlayed + now - levelPlayedAt) or "?", Duration(elapsed),
        rate > 0 and Duration(left / rate * 3600) or "?", Comma(rate),
        killXP and Comma(math.ceil(left / killXP)) or "?")
    -- Two lines, broken after the session time. A new text can wrap
    -- to another number of lines: the panel's height follows. "XP per
    -- hour", not "XP/hr": the wrap broke after the slash.
    if Set(frame.sentence, text) then FitPanel() end
    Set(frame.bonus, (GREY .. "Quests:|r |cff%s%.1f%%|r   " .. GREY .. "Rested:|r |cff%s%.1f%%|r"):format(
        qc, questXP / max * 100, rc, rested / max * 100))
end

-- Look and place: size, position, colours, font, border.
local function Layout()
    EnsureFrame()
    local d = DB()
    ns.Ellesmere.PixelSize(frame, math.max(50, tonumber(d.width) or 470), math.max(2, tonumber(d.height) or 22))
    frame:ClearAllPoints()
    ns.Ellesmere.PixelPoint(frame, d.point or "CENTER", UIParent, d.point or "CENTER",
        tonumber(d.x) or 0, tonumber(d.y) or 0)

    local r, g, b = ns.HexToRGB(ns.db.global.background.color)
    frame.bg:SetColorTexture(r, g, b, tonumber(ns.db.global.background.alpha) or 1)
    local path = ns.Ellesmere.BarTexturePath(d.texture) or "Interface\\Buttons\\WHITE8X8"
    local function Paint(bar, hex)
        bar:SetStatusBarTexture(path)
        bar:SetStatusBarColor(ns.HexToRGB(hex))
    end
    Paint(frame.xp, d.xpColor)          -- Update gives it the rested colour with rested XP
    Paint(frame.quest, d.questColor)
    Paint(frame.rested, d.restedColor)
    local rr, rg, rb = ns.HexToRGB(d.restedColor)
    frame.rested:SetStatusBarColor(rr, rg, rb, RESTED_ALPHA)
    -- The fill's border lies under the bar's (levels 6 and 9, above).
    barHot = frame:IsShown() and frame:IsMouseOver() or false
    ns.Border.Apply(frame.edge, barHot and HoverBorder(d.border) or d.border)
    local u = ns.Ellesmere.PixelUnit(frame)
    for i, t in ipairs(frame.ticks) do
        if d.ticks == true then
            t:SetWidth(ns.Border.Snap(frame:GetWidth() * i / 10, u))
            ns.Border.SeamV(t.tex, t, TICK)
            t:Show()
        else
            t:Hide()
        end
    end
    for _, e in pairs(frame.fillEdges) do ns.Border.Apply(e, FILL_EDGE) end

    local font, flags = ns.Ellesmere.Font()
    for _, k in ipairs({ "level", "pct", "hint" }) do
        frame[k]:SetFont(font, tonumber(d.textSize) or 12, flags)
    end
    -- The panel's body text, and its header's 15 % smaller.
    local bodySize = tonumber(d.panelTextSize) or 14
    local size = math.floor(bodySize / 1.15 + 0.5)
    for _, k in ipairs({ "progress", "topC", "remain" }) do
        frame[k]:SetFont(font, size, flags)
    end
    frame.sentence:SetFont(font, bodySize, flags)
    frame.bonus:SetFont(font, bodySize, flags)
    -- The panel over the bar by the gap: the progress row, then the times
    -- and rates rows when shown.
    local panel = frame.panel
    panel:ClearAllPoints()
    local pad, badgeH = 6, size + 6        -- header padding
    local hex, ha = ns.BackgroundColor(true, "headerBackground")
    local hr, hg, hb = ns.HexToRGB(hex)
    local reset = frame.reset
    reset.text:SetFont(font, size, flags)
    ns.Ellesmere.PixelSize(reset, math.ceil(reset.text:GetStringWidth()) + 12, badgeH)
    ns.PaintHeader(reset.tex, hr, hg, hb, ha)
    ns.Border.Apply(reset, BORDER)
    frame.progress:ClearAllPoints()
    frame.progress:SetPoint("LEFT", panel, "TOPLEFT", 10, -(pad + badgeH / 2))
    frame.reset:ClearAllPoints()
    frame.reset:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad, -pad)
    -- Under the progress row's header: the seam, then the text (FitPanel).
    local w = frame:GetWidth()
    local top = ns.Border.Snap(pad + badgeH + pad, u)
    panel.top, panel.pad, panel.size = top, pad, bodySize
    frame.seam:ClearAllPoints()
    frame.seam:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -top)
    frame.seam:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -top)
    frame.seam:SetHeight(u)
    frame.seam:SetShown(ns.Border.Seam(frame.seam.tex, frame.seam, BORDER) or false)
    frame.sentence:SetWidth(w - 16)
    wipe(shownText)
    Update()                        -- the texts, so FitPanel measures them
    FitPanel()
    local gap = PANEL_GAP
    panel:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, ns.Border.Snap(gap, u))
    panel:SetHitRectInsets(0, 0, 0, -gap)     -- the gap is the panel's for the mouse
    local bodyA = tonumber(d.panelAlpha)
    bodyA = bodyA and math.max(0, math.min(100, bodyA)) / 100 or tonumber(ns.db.global.background.alpha) or 1
    local br, bg, bb = r, g, b
    if type(d.panelColor) == "string" then br, bg, bb = ns.HexToRGB(d.panelColor) end
    panel.bg:SetColorTexture(br, bg, bb, bodyA)
    panel.header:ClearAllPoints()
    panel.header:SetPoint("TOPLEFT", panel, "TOPLEFT")
    panel.header:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
    panel.header:SetHeight(top)
    ns.PaintHeader(panel.header, hr, hg, hb, ha)
    ns.Border.Apply(panel, BORDER)
    panel:EnableMouse(true)
    frame.level:SetShown(d.textMouseover ~= true or hovered)
    frame.pct:SetShown(d.textMouseover ~= true or hovered)
    panel:SetShown(not repMode and panelOpen)
    -- Unlocked: dragged by the mouse, with a hint over it. Locked, a click
    -- opens and closes the info panel.
    local unlocked = d.unlocked == true
    frame:EnableMouse(true)
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.hint:SetText("XP Bar: drag to move")
    frame.hint:SetShown(unlocked)
    wipe(shownText)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- Durations, not GetTime() values, are saved, with time() when saved: the
-- time between the save and the next Enable (the /reload's loading screen)
-- counts as played.
local function SaveSession()
    local s, now = ns.CharStore("xpBar"), GetTime()
    s.login, s.savedAt = ns.LoginStamp(), time()
    s.session = now - sessionStart
    s.counted = rateStart and now - rateStart or nil
    s.xp = sessionXP
    s.played = levelPlayed and levelPlayed + now - levelPlayedAt or nil
    s.killXP = killXP
end

-- Returns true when the saved session is this login's and was taken back.
local function RestoreSession()
    local s = ns.CharStore("xpBar")
    local login = ns.LoginStamp()
    if not (login and s.login == login and tonumber(s.savedAt) and tonumber(s.counted)) then return false end
    local now, gap = GetTime(), math.max(0, time() - s.savedAt)
    sessionStart = now - (tonumber(s.session) or 0) - gap
    rateStart, sessionXP = now - s.counted - gap, tonumber(s.xp) or 0
    if tonumber(s.played) then levelPlayed, levelPlayedAt = s.played + gap, now end
    killXP = tonumber(s.killXP)
    return true
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_XP_UPDATE" then
        local cur, max = tonumber(UnitXP("player")) or 0, tonumber(UnitXPMax("player")) or 0
        local level = UnitLevel("player")
        if lastXP then
            if level ~= lastLevel and lastMax then
                -- A level up (one gain may cross it with cur above the old
                -- XP): the rest of the old level, then the new XP.
                sessionXP = sessionXP + (lastMax - lastXP) + cur
            elseif cur >= lastXP then
                sessionXP = sessionXP + cur - lastXP
            end
        end
        lastXP, lastMax, lastLevel = cur, max, level
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local msg = ...
        -- A chat text can be secret (Midnight's rules, in combat in an
        -- instance): that kill is not counted, the next one is.
        if issecretvalue and issecretvalue(msg) then return end
        local pat = KillPattern()
        if pat and type(msg) == "string" then
            local _, xp = msg:match(pat)
            xp = tonumber(xp)
            if xp and xp > 0 then killXP = xp end
        end
    elseif event == "PLAYER_LEVEL_UP" then
        levelPlayed, levelPlayedAt = 0, GetTime()
    elseif event == "QUEST_LOG_UPDATE" then
        -- Frequent (kills, loot): read on the next tick, not now.
        questDirty = true
        return
    elseif event == "TIME_PLAYED_MSG" then
        local _, atLevel = ...
        if type(atLevel) == "number" then levelPlayed, levelPlayedAt = atLevel, GetTime() end
    elseif event == "PLAYER_LOGOUT" then
        SaveSession()
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Once per login: isInitialLogin is false on a /reload or a loading
        -- screen.
        local isLogin = ...
        if isLogin then
            -- A new session. Enable ran at PLAYER_LOGIN, before this event,
            -- and took back the last login's session: the login stamp is not
            -- replaced before this event.
            local now = GetTime()
            sessionStart, rateStart, sessionXP, killXP = now, now, 0, nil
            levelPlayed, levelPlayedAt = nil, nil
            if DB().askPlayed and RequestTimePlayed then RequestTimePlayed() end
        end
    end
    Update()
end

function M:Enable()
    active = true
    EnsureFrame()
    if not host then
        host = CreateFrame("Frame")
        host:SetScript("OnEvent", OnEvent)
    end
    -- The XP count starts here, so XP/hr counts only time it was counting;
    -- after a /reload it goes on from where it was (RestoreSession).
    if not rateStart and not RestoreSession() then
        rateStart, sessionXP = GetTime(), 0
    end
    lastXP, lastMax, lastLevel = tonumber(UnitXP("player")) or 0, tonumber(UnitXPMax("player")) or 0, UnitLevel("player")
    host:RegisterUnitEvent("PLAYER_XP_UPDATE", "player")
    host:RegisterEvent("PLAYER_LEVEL_UP")
    host:RegisterEvent("UPDATE_EXHAUSTION")
    host:RegisterEvent("QUEST_LOG_UPDATE")
    host:RegisterEvent("TIME_PLAYED_MSG")
    host:RegisterEvent("PLAYER_ENTERING_WORLD")
    host:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    host:RegisterEvent("UPDATE_FACTION")
    host:RegisterEvent("PLAYER_LOGOUT")
    StartTicker()
end

function M:Apply()
    Layout()
    questDirty = true
    Update()
end

function M:Disable()
    active = false
    rateStart = nil                 -- XP gained while off is not counted
    wipe(ns.CharStore("xpBar"))     -- nor taken back after a /reload
    if host then host:UnregisterAllEvents() end
    StopTicker()
    if frame then frame:Hide() end
end

-- Shift-click: the progress in party chat in a group, else /say. An addon's
-- /say reaches others only inside an instance (Inferred: the retail rule),
-- so outside one the line is put in the chat box to send with Enter. Not in
-- combat: Midnight limits addon chat there (Inferred).
function M.Announce()
    if not active or repMode or NoXP() or InCombatLockdown() then return end
    local cur, max = tonumber(UnitXP("player")) or 0, tonumber(UnitXPMax("player")) or 1
    local left = max - cur
    local counted = GetTime() - (rateStart or GetTime())
    local rate = counted > 0 and sessionXP / counted * 3600 or 0
    local text = ("Level %d: %.1f%% (%s XP to level%s)"):format(UnitLevel("player") or 0, cur / max * 100,
        Comma(left), rate > 0 and (", ~" .. Duration(left / rate * 3600)) or "")
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    -- An instance-only group (a finder group) has INSTANCE_CHAT, not PARTY.
    local home = not LE_PARTY_CATEGORY_HOME or IsInGroup(LE_PARTY_CATEGORY_HOME)
    if IsInGroup() and home then
        send(text, "PARTY")
    elseif IsInGroup() then
        send(text, "INSTANCE_CHAT")
    elseif IsInInstance() then
        send(text, "SAY")
    else
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if open then open(text) end
    end
end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------

function M:BuildPage(pageName, parent, y, W)
    local _, h
    local function changed() ns.Apply() end
    local function Toggle(text, tip, key)
        return { type = "toggle", text = text, tooltip = tip,
            getValue = function() return DB()[key] == true end,
            setValue = function(v)
                DB()[key] = v and true or false
                changed()
            end }
    end
    local function Slider(text, tip, key, minV, maxV)
        return { type = "slider", text = text, min = minV, max = maxV, step = 1, tooltip = tip,
            getValue = function() return tonumber(DB()[key]) or minV end,
            setValue = function(v) DB()[key] = v; changed() end }
    end
    local function Colour(text, key, tip)
        return ns.BackgroundCell({ text = text, cfg = DB, colorKey = key, follows = function() return false end,
            onChange = changed, tooltip = tip })
    end

    do
        _, h = W:DualRow(parent, y,
            { type = "label", text = "The background and the info panel's border are the Global Settings page's. The bar hides at level 60 unless it shows reputation." }); y = y - h
        _, h = W:SectionHeader(parent, "BAR", y); y = y - h
        local texNames, texOrder = ns.Ellesmere.BarTextures()
        local function BorderCfg() return DB().border end
        y = ns.Rows(W, parent, y,
            Toggle("Unlock (drag with the mouse)", "While unlocked the bar can be dragged.", "unlocked"),
            Toggle("Bar Text on Mouseover", "The level and percent on the bar show only while the mouse is over the bar or the info panel.", "textMouseover"),
            Slider("Height", "The bar's height.", "height", 2, 60),
            Slider("Text Size", "The size of the level and percent on the bar.", "textSize", 8, 24),
            Slider("Width", "The bar's width.", "width", 100, 1200),
            { type = "dropdown", text = "Bar Texture", values = texNames, order = texOrder,
              tooltip = "An Ellesmere bar texture tinted by the colours below, or flat colours.",
              getValue = function() return DB().texture or "none" end,
              setValue = function(v) DB().texture = v; changed() end },
            Toggle("10% Marks", "A 1 px black line every 10 % of the bar.", "ticks"),
            Toggle("Reputation at Max Level", "At level 60 the bar shows the faction you watch instead of hiding. No watched faction: hidden.", "repAtMax"),
            { type = "toggle", text = "Use Global Border",
              tooltip = "Draw the bar's border with the settings on the Global Settings page. Off: its own border rows show below.",
              getValue = function() return BorderCfg().useGlobal == true end,
              setValue = function(v)
                  BorderCfg().useGlobal = v and true or false
                  changed()
                  ns.Ellesmere.RebuildPage()      -- the own border rows show or hide
              end },
            Toggle("Quests on Mouseover", "The quest fill shows only while the mouse is over the bar or the info panel.", "questMouseover"))
        -- The bar's own border rows; the toggle above stands in for
        -- Border.Rows' own, so they are built as for the global border.
        if BorderCfg().useGlobal ~= true then
            y = ns.Border.Rows(W, parent, y, BorderCfg, changed, true)
        end
        _, h = W:SectionHeader(parent, "INFO PANEL", y); y = y - h
        y = ns.Rows(W, parent, y,
            Slider("Panel Text Size", "The size of the info panel's text; its header's is 15 % smaller.", "panelTextSize", 8, 24),
            Slider("Close After (sec)", "The open panel closes this many seconds after the mouse leaves the bar and panel. 0: stays open.", "infoClose", 0, 30),
            { type = "colorpicker", text = "Panel Background", hasAlpha = true,
              tooltip = "The colour and alpha of the panel's background under the header. Until set: the Global Settings page's background.",
              getValue = function()
                  local d, gb = DB(), ns.db.global.background
                  local r, g, b = ns.HexToRGB(type(d.panelColor) == "string" and d.panelColor or gb.color)
                  local a = tonumber(d.panelAlpha)
                  return r, g, b, a and a / 100 or tonumber(gb.alpha) or 1
              end,
              setValue = function(r, g, b, a)
                  local d = DB()
                  d.panelColor = ns.RGBToHex(r, g, b)
                  d.panelAlpha = math.floor((a or 1) * 100 + 0.5)
                  changed()
              end },
            Toggle("Ask Time Played", "Asks the server for /played once at login (not on a reload), for Time this level. The answer shows in the chat as after /played. Off: Time this level waits for your own /played.", "askPlayed"))
        _, h = W:SectionHeader(parent, "COLOURS", y); y = y - h
        y = ns.Rows(W, parent, y,
            Colour("XP Colour", "xpColor", "The XP you have."),
            Colour("Quests Colour", "questColor", "The XP of completed quests in the log, behind the XP, and the Quests number."),
            Colour("Rested Colour", "restedColor", "With rested XP: the XP fill, the rested part over the fills, and the Rested number."))
    end
    if not ns.IsModuleEnabled("xpBar") then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "XP Bar is off: turn it on under Modules on the General page." }); y = y - h
    end
    return y
end

-- For the simulator's tests.
function M.Frame() return frame end
function M.SessionXP() return sessionXP end
function M.SetMouseLeftAt(t) leftAt = t end      -- test hook: Close After without waiting
function M.Event(event, ...) OnEvent(host, event, ...) end
