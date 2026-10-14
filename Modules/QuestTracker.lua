-- ProseccoUI / Modules / QuestTracker.lua
-- Our own quest tracker: the data half and the module's on/off. The quest
-- log is read from Blizzard's quest API into a plain list; the frame
-- (QuestTrackerFrame.lua) reads it only through M.Quests(). An objective's
-- `finished` decides whether it is done, never its counters: Forever has
-- rows that read 1/1 unfinished.
--
-- Other trackers: Ellesmere's Quest Tracker stays on for its QoL; we set only
-- its Visibility to "never", and Ellesmere then hides Blizzard's tracker (in
-- combat too). That holds whatever mode the user picked there; only a stored
-- per-spec visibilityOverride beats it. Questie's tracker is turned off with
-- its trackerEnabled flag. Both are written when the module goes on, given
-- back when it goes off, never rewritten at login. We never touch Blizzard's
-- tracker: hiding that Edit Mode frame from addon code taints its layout.
--
-- New quests: Blizzard's tracker watches every accepted quest while
-- autoQuestWatch is on, also at alpha 0 (FIELD RESULT 2026-10-09 (build
-- 70291): a new quest came in watched), and re-sorts watches by distance on
-- zone changes. So nothing here adds or sorts watches.
--
-- Off: no frames shown, no events.

local _, ns = ...

local OWNED = {
    { target = "questTracker", key = "visibility",     value = "never", label = "Ellesmere Quest Tracker: Visibility" },
    { target = "questie",      key = "trackerEnabled", value = false,   label = "Questie: Tracker" },
}

local M = ns.RegisterModule("questTracker", {
    title       = "Quest Tracker",
    description = "ProseccoAdditions' own quest tracker, built on Blizzard's quest log, in place of Ellesmere's and Questie's trackers.",
    pages       = { "Quest Tracker", "RXP", "Advanced" },
    defaults    = {
        -- Where Blizzard's tracker sits by default: under the minimap.
        point = "TOPRIGHT", x = -40, y = -260,
        width = 260,
        maxHeight = 520,            -- the frame grows with its content up to this, then scrolls
        fixedHeight = false,        -- Always Max Height: the frame is maxHeight tall whatever it holds
        padding = 8,                -- px between the frame's edge and the text
        unlocked = false,
        collapsed = false,          -- the header click folds the frame to its header
        folded = {},                -- questID -> true: the quest shows only its title (right-click)
        altAbandon = true,          -- alt-click a title: abandon the quest
        abandonConfirm = true,      -- ask first (Ellesmere's confirm popup)
        -- Ellesmere's tracker background.
        bgColor = "090909", bgAlpha = 0.75,
        useGlobalBackground = true, -- Background and Header Background follow General's
        -- headerColor/headerAlpha: no default; nil = Background.
        -- Ellesmere's tracker font sizes.
        headerSize = 13, titleSize = 12, objectiveSize = 10,
        headerHeight = 0,           -- px; 0 = the header text's height plus 6
        font = "global",            -- "global" = General's, "" = Ellesmere's font; one face for every text in the tracker
        outline = "global",         -- global | ellesmere | none | shadow | OUTLINE | THICKOUTLINE (ns.Media.Outline)
        headerSeam = false,         -- a border line under the header while the tracker is open
        completed = "top",          -- "top" | "bottom" | "inorder": completed quests within a zone
        currentZoneOnly = false,
        objectiveSpacing = 1,       -- px between a quest's title and the line under it
        foldedZones = {},           -- zone name -> true: folded to its header by a click
        turnIn = true,              -- completed quests show the turn-in NPC and zone
        questXP = true,             -- the quest's XP after the title, abbreviated
        -- xpSize: no default; nil follows Title Size.
        xpColor = "9D9D9D", xpAlpha = 1,
        rxpDialogDot = true,        -- the guide dot next to quests in NPC dialogs
        itemButtons = true,         -- the quest's special item as a clickable button
        itemSize = 26,              -- px, Blizzard's tracker button size
        rxpDot = true,
        rxpProgress = true,
        rxpHighlight = false,       -- a band behind the titles of quests in RXP's active steps
        rxpDock = "standalone",     -- "integrated": RXP's step list hangs under the tracker, its step boxes under it
        rxpDockGap = 6,             -- px between the step list and the top of the step box's badge
        scrollBarSide = "right",    -- "right" | "left": the list's scroll bar (and the docked guide's bar and cog)
        rxpStepsSide = "under",     -- Integrated: RXP's step boxes "under" the list or beside it ("left"/"right"), newest first
        guideHeaderHeight = 0,      -- px, Integrated: the guide's header box (progress row); 0 = row + padding
        rxpFolded = false,          -- Integrated: the progress row's click folds RXP's step list and boxes away
        highlightColor = "3F99FF", highlightAlpha = 0.25,               -- the box; its 1 px edge takes the colour at 0.5
        completedText = true,       -- "Quest Completed" in the middle of the screen
        objectiveText = true,       -- "Objective Completed" the same way when an objective is done
        completedSize = 28,
        -- The quest name under it; nil follows Completed Size at 16/28.
        completedTitleSize = nil,
        border = { useGlobal = true, style = "solid", size = 1, color = "000000", alpha = 1 },
    },
    affects     = {
        "Ellesmere's Quest Tracker Visibility is set to Never, so Blizzard's tracker is hidden. Its auto-accept, auto-turn-in and quest item key keep working.",
        "Questie's tracker is turned off.",
        "The values from before are put back when Quest Tracker is turned off.",
    },
    affectsOff  = {
        "ProseccoAdditions' quest tracker is removed.",
        "Ellesmere's Quest Tracker Visibility and Questie's tracker go back to what they were before Quest Tracker was turned on, so their trackers show again (a value you changed there since then stays).",
    },
    reload      = true,
})

local function DB() return ns.db.modules.questTracker end
M.DB = DB

-- The old `shadow` toggle becomes the outline mode "shadow". Runs on every
-- profile before the defaults are filled; removing `shadow` makes it run
-- once. With an outline set, the outline stays and the shadow goes. The same
-- for the completed text's own outline.
function M:Migrate(cfg)
    if cfg.shadow == nil then return end
    if cfg.shadow == true then
        if cfg.outline == "none" then cfg.outline = "shadow" end
        if cfg.completedOutline == "none" then cfg.completedOutline = "shadow" end
    end
    cfg.shadow = nil
end

local function WriteOwned() ns.TakeOwned("questTracker", OWNED, "QT") end
local function RestoreOwned() ns.GiveBackOwned("questTracker", "QT") end
M.WriteOwned = WriteOwned
M.OWNED = OWNED

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

-- quests[i] = {
--   id, title, level, zone (the quest log header above it), logIndex,
--   watched, complete, failed, frequency, item (special item link or nil),
--   loaded (false while Blizzard has not sent every objective's text yet),
--   objectives = { { text, type, finished, have, need }, ... },
-- }
-- Log order: zone by zone, as in the quest log. Replaced on every refresh.
local quests = {}

-- Objective rows not ready to read, as Questie's IsObjectiveDataLoaded
-- rejects them: no text or type yet, or a label around a missing name
-- (" : 2/5"). An exactly empty text is a permanent empty row Blizzard adds
-- to some quests; it is skipped, not waited for.
local function Pending(o)
    if o.text == "" then return false end       -- before the type: such rows may have none
    return o.text == nil or o.type == nil or o.text:match("^%s*:") ~= nil
end

local function ReadObjectives(questID, q)
    local rows = C_QuestLog.GetQuestObjectives(questID)
    if not rows then q.loaded = false return end
    for _, o in ipairs(rows) do
        if Pending(o) then
            q.loaded = false
        elseif o.text ~= "" then
            q.objectives[#q.objectives + 1] = {
                text = o.text, type = o.type, finished = o.finished == true,
                have = o.numFulfilled, need = o.numRequired,
            }
        end
    end
end

-- Every quest in the log. GetInfo also returns quests under collapsed
-- headers, and nil after the last entry, so the loop runs until nil.
local function ReadLog()
    local list, zone = {}, nil
    local i = 1
    while true do
        local info = C_QuestLog.GetInfo(i)
        if not info then break end
        if info.isHeader then
            zone = info.title
        elseif not info.isHidden and info.questID and info.questID > 0 then
            local id = info.questID
            local q = {
                id = id, title = info.title, level = info.level, zone = zone, logIndex = i,
                watched = C_QuestLog.GetQuestWatchType(id) ~= nil,
                complete = C_QuestLog.IsComplete(id) == true,
                failed = C_QuestLog.IsFailed(id) == true,
                frequency = info.frequency,
                loaded = true,
                objectives = {},
            }
            -- The special item, read as Blizzard's tracker reads it: link for
            -- the button's item attribute, texture for its icon.
            q.item, q.itemTexture, q.charges, q.showWhenComplete = GetQuestLogSpecialItemInfo(i)
            -- The quest's XP as Blizzard's reward tooltip shows it (baseXp).
            -- Guarded: if a build drops the API, no XP shows instead of an error.
            if GetQuestLogRewardXP then
                local _, baseXp = GetQuestLogRewardXP(id)
                if type(baseXp) == "number" and baseXp > 0 then q.xp = baseXp end
            end
            -- The turn-in NPC and zone for completed quests, from QuestieDB.
            if q.complete then
                q.turnInNpc, q.turnInZone = ns.Questie.TurnIn(id)
            end
            ReadObjectives(id, q)
            list[#list + 1] = q
        end
        i = i + 1
    end
    -- Timed quests; each timer carries its quest id. Stored as the GetTime() the
    -- timer runs out, so the frame's ticker needs no re-read.
    local timers = C_QuestLog.GetQuestTimers and C_QuestLog.GetQuestTimers()
    if timers then
        local ends = {}
        local now = GetTime()
        for _, t in ipairs(timers) do ends[t.questID] = now + t.questTimer end
        for _, q in ipairs(list) do q.timerEnds = ends[q.id] end
    end
    return list
end

-- The list for the frame. Read at call time; replaced on every refresh.
function M.Quests() return quests end

-- Whether anything the frame shows differs between two reads. Field by field,
-- so a burst of QUEST_LOG_UPDATE that changes nothing draws nothing.
local function SameQuest(a, b)
    if a.id ~= b.id or a.title ~= b.title or a.level ~= b.level or a.zone ~= b.zone
       or a.watched ~= b.watched or a.complete ~= b.complete or a.failed ~= b.failed
       -- The item and its charges change the button; the timer's seconds tick
       -- every read, so only its coming or going counts (the ticker draws it).
       or a.item ~= b.item or a.charges ~= b.charges
       -- logIndex feeds the item buttons' cooldown and tooltip, so a log
       -- renumbering alone must also redraw.
       or a.logIndex ~= b.logIndex
       -- XP changes on a level up; the turn-in lookup can start answering once
       -- QuestieDB has loaded.
       or a.xp ~= b.xp or a.turnInNpc ~= b.turnInNpc
       or (a.timerEnds == nil) ~= (b.timerEnds == nil)
       or #a.objectives ~= #b.objectives then
        return false
    end
    for i, o in ipairs(a.objectives) do
        local p = b.objectives[i]
        if o.text ~= p.text or o.finished ~= p.finished then return false end
    end
    return true
end

local function SameList(a, b)
    if #a ~= #b then return false end
    for i, q in ipairs(a) do
        if not SameQuest(q, b[i]) then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Updates
-- ---------------------------------------------------------------------------

-- QUEST_LOG_UPDATE comes in bursts (several per objective tick, and many at
-- login), so a burst is read once, on the next frame.
local host
local active = false
local queued = false
local first = true          -- the first read after switching on or a /reload
local forceDraw = false     -- something besides the quest list changed (zone, guide)

local function Refresh()
    queued = false
    if not active then return end
    local old = quests
    quests = ReadLog()
    -- Drop folds of quests and zones that left the log, or they pile up in
    -- SavedVariables. Only what was in the last read and is gone now: the first
    -- read after login can come before the log is filled. An empty read (a
    -- loading screen) drops nothing.
    local d = ns.db.modules.questTracker
    if #old > 0 and #quests > 0 and (next(d.folded) or next(d.foldedZones)) then
        local ids, zones = {}, {}
        for _, q in ipairs(quests) do
            ids[q.id] = true
            zones[q.zone or ""] = true
        end
        for _, q in ipairs(old) do
            if not ids[q.id] then d.folded[q.id] = nil end
            local z = q.zone or ""
            if not zones[z] then d.foldedZones[z] = nil end
        end
    end
    -- "Quest Completed" only for a quest that was in the last read and not
    -- complete then: not at login, a reload, or for a quest accepted complete.
    -- "Objective Completed" for an objective of such a quest that was not
    -- finished then, while the quest itself is not complete yet.
    if not first then
        -- One text per read; a quest done wins over an objective done in the
        -- same read (they share one frame, the last call shows).
        local questTitle, objectiveText
        local was = {}
        for _, q in ipairs(old) do was[q.id] = q end
        for _, q in ipairs(quests) do
            local w = was[q.id]
            if q.complete and not w then
                -- Not in the last read (accepted complete): no text. Logged,
                -- except after an empty read (login, loading screen), to catch a
                -- quest done in play that showed no text.
                if #old > 0 then ns.Log("QUESTS", "complete, not in the last read: %s", tostring(q.title)) end
            elseif w and not w.complete then
                if q.complete then
                    ns.Log("QUESTS", "quest complete: %s", tostring(q.title))
                    questTitle = questTitle or q.title
                elseif q.loaded and w.loaded and #q.objectives == #w.objectives then
                    -- Compared by position, so only when both reads have every row.
                    for i, o in ipairs(q.objectives) do
                        if o.finished and not w.objectives[i].finished then objectiveText = o.text end
                    end
                end
            end
        end
        if questTitle then
            M.ShowCompleted(questTitle)
        elseif objectiveText then
            M.ShowCompleted(objectiveText, true)
        end
    end
    -- Cleared before the draw: an error in a draw must not keep every later
    -- read counting as the first (no completed text for the rest of the session).
    local draw = first or forceDraw or not SameList(old, quests)
    first, forceDraw = false, false
    if draw then
        M.Draw()
    end
end

local function Queue(redraw)
    if redraw then forceDraw = true end
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        xpcall(Refresh, ns.ErrorHandler("questTracker:refresh"))
    end)
end
M.Queue = Queue

-- Keep On Screen: the guide under the tracker grew or shrank (one function,
-- so enabling again does not register a second one).
local function OnBelowChange()
    if active then Queue(true) end
end

-- QUEST_LOG_UPDATE: objectives, completion, accept and abandon all end in it.
-- QUEST_WATCH_LIST_CHANGED: tracked/untracked and Blizzard's re-sort by
-- distance, which do not change the log. ZONE_CHANGED_NEW_AREA: the zone
-- that "Current Zone Only" keeps open. PLAYER_REGEN_DISABLED/ENABLED: the
-- item buttons are secure, so their layout waits out combat (the frame
-- freezes them at the pull and lays them out again after it).
-- BAG_UPDATE_COOLDOWN: only the buttons' cooldown swipes, no redraw.
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "ZONE_CHANGED_NEW_AREA",
                 "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN" }

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        M.EnterCombat()
        return
    end
    if event == "BAG_UPDATE_COOLDOWN" then
        M.UpdateItemCooldowns()
        return
    end
    Queue(event ~= "QUEST_LOG_UPDATE")
end

function M:Enable()
    active = true
    if not host then
        host = CreateFrame("Frame")
        host:SetScript("OnEvent", OnEvent)
    end
    for _, e in ipairs(EVENTS) do host:RegisterEvent(e) end
    -- A guide loaded or a step done moves quests in the order and changes the
    -- progress bar; no quest log event comes with it.
    ns.RXP.OnGuideChange(function()
        if active then Queue(true) end
    end)
    -- Keep On Screen: the guide under the tracker grew or shrank.
    ns.RXP.OnBelowChange(OnBelowChange)
    first = true
    Queue(true)
end

-- A settings change: draw again from the list we have.
function M:Apply()
    M.Draw()
    M.ApplyDialogDots()
    M.ApplyGuideDock()
end

function M:Disable()
    active = false
    if host then host:UnregisterAllEvents() end
    quests = {}
    M.HideFrame()
    M.HideDialogDots()
    ns.RXP.Undock()
    RestoreOwned()
end

-- A profile from before the global background keeps its own colours.
function M:KeepOwnBackgrounds(cfg)
    if cfg.useGlobalBackground == nil then cfg.useGlobalBackground = false end
end

function M:SwitchedOn() WriteOwned() end
