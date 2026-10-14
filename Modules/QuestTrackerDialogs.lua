-- ProseccoAdditions / Modules / QuestTrackerDialogs.lua
-- The guide dot next to quests in NPC dialogs (gossip window and quest
-- greeting panel) for the quests the loaded RXP guide names. Our own
-- texture on Blizzard's line buttons, which are plain Buttons, not secure.
--
-- The hooks are installed once, the first time the module is enabled, and
-- gate in their bodies: hooksecurefunc and ScrollUtil callbacks cannot be
-- unregistered.

local _, ns = ...

local M = ns.GetModule("questTracker")
local DB = M.DB

local DOT_TEX = ns.RXP.TEXTURE_PATH .. "white_circle"
local DOT_R, DOT_G, DOT_B = 0.25, 0.6, 1    -- the tracker's guide-dot blue

local hooked = false
-- One dot (plus its black outline) per Blizzard button, created lazily; a
-- weak table, so no field is written on Blizzard's frames.
local dots = setmetatable({}, { __mode = "k" })

local function Dot(button)
    local d = dots[button]
    if d then return d end
    local edge = button:CreateTexture(nil, "OVERLAY", nil, 6)
    edge:SetTexture(DOT_TEX)
    edge:SetVertexColor(0, 0, 0, 1)
    d = button:CreateTexture(nil, "OVERLAY", nil, 7)
    d:SetTexture(DOT_TEX)
    d:SetVertexColor(DOT_R, DOT_G, DOT_B, 1)
    d.edge = edge
    dots[button] = d
    return d
end

-- Shows or hides the dot on one line button. Pooled buttons are reused
-- across line types, so the dot is hidden when the line is not a guide
-- quest. It sits as a badge on the line's icon, which survives Questie
-- changing the icon's texture.
local function Mark(button, questId, guide)
    local d = dots[button]
    local show = questId and guide and guide[questId] and button.Icon
    if not show then
        if d then d:Hide(); d.edge:Hide() end
        return
    end
    d = Dot(button)
    local u = ns.Ellesmere.PixelUnit(button)
    d:SetSize(8, 8)
    d:ClearAllPoints()
    d:SetPoint("BOTTOMRIGHT", button.Icon, "BOTTOMRIGHT", 2, -2)
    d.edge:SetSize(8 + 2 * u, 8 + 2 * u)
    d.edge:ClearAllPoints()
    d.edge:SetPoint("CENTER", d, "CENTER")
    d:Show()
    d.edge:Show()
end

local function Enabled()
    return ns.IsModuleEnabled("questTracker") and DB().rxpDialogDot == true
end

-- The guide map (questID -> step), built at most once per render frame:
-- GuideQuests scans the whole guide, and the initialized callback runs per
-- line of a rebuild. One rebuild runs in one frame, so one GetTime() stamp
-- means one scan per rebuild.
local guideCache, guideStamp
local function Guide()
    if not Enabled() then return nil end
    local now = GetTime()
    if guideStamp ~= now then
        guideStamp, guideCache = now, ns.RXP.GuideQuests()
    end
    return guideCache
end

-- ---------------------------------------------------------------------------
-- Gossip window
-- ---------------------------------------------------------------------------

-- A gossip line's quest id. Quest lines carry info.questID and their own
-- button type; GetID() alone is ambiguous, since option lines use it for
-- their order index.
local function GossipQuestID(elementData)
    if type(elementData) ~= "table" then return nil end
    if not (elementData.availableQuestButton or elementData.activeQuestButton) then return nil end
    local info = elementData.info
    return type(info) == "table" and info.questID or nil
end

local function MarkGossipLine(button, elementData)
    Mark(button, GossipQuestID(elementData), Guide())
end

local function MarkGossip()
    local guide = Guide()
    GossipFrame.GreetingPanel.ScrollBox:ForEachFrame(function(button)
        local ed = button.GetElementData and button:GetElementData()
        Mark(button, GossipQuestID(ed), guide)
    end)
end

-- ---------------------------------------------------------------------------
-- Quest greeting panel
-- ---------------------------------------------------------------------------

-- A greeting title button's quest id, from the globals Blizzard's panel
-- uses. The range guard covers a stale button during the rebuild.
local function GreetingQuestID(button)
    local index = button:GetID()
    if button.isActive == 1 then
        if index < 1 or index > GetNumActiveQuests() then return nil end
        return GetActiveQuestID(index)
    end
    if index < 1 or index > GetNumAvailableQuests() then return nil end
    return (select(5, GetAvailableQuestInfo(index)))
end

local function MarkGreeting()
    local guide = Guide()
    for button in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
        Mark(button, GreetingQuestID(button), guide)
    end
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

local function Install()
    if hooked then return end
    hooked = true
    -- Initialized fires for every line the ScrollBox binds (open, rebuild,
    -- scroll); Released hides the dot so a recycled frame keeps no stale one.
    ScrollUtil.AddInitializedFrameCallback(GossipFrame.GreetingPanel.ScrollBox,
        function(_, button, elementData) MarkGossipLine(button, elementData) end, M, false)
    ScrollUtil.AddReleasedFrameCallback(GossipFrame.GreetingPanel.ScrollBox,
        function(_, button)
            local d = dots[button]
            if d then d:Hide(); d.edge:Hide() end
        end, M)
    -- The greeting panel rebuilds in OnShow at QUEST_GREETING and through a
    -- direct call of the global at QUEST_LOG_UPDATE, so both are hooked.
    QuestFrameGreetingPanel:HookScript("OnShow", MarkGreeting)
    hooksecurefunc("QuestFrameGreetingPanel_OnShow", MarkGreeting)
end

-- Runs at every Apply: installs the hooks once and refreshes any open
-- dialog, so a settings or guide change shows at once (also when off).
function M.ApplyDialogDots()
    if Enabled() then Install() end
    if not hooked then return end
    if GossipFrame:IsShown() then MarkGossip() end
    if QuestFrameGreetingPanel:IsShown() then MarkGreeting() end
end

-- Module off: the hooks stay but show nothing; dots in an open dialog go
-- out here.
function M.HideDialogDots()
    if not hooked then return end
    for _, d in pairs(dots) do
        d:Hide()
        d.edge:Hide()
    end
end
