-- ProseccoAdditions / Modules / Panels.lua
-- Cosmetic panels: empty frames you create, place and style, each with its
-- own size, anchor (the screen or a named frame), layer, background and
-- border. Panels are named frames (ProseccoUIPanel<id>) so other frames can
-- anchor to them; those names are the only globals this module makes.
--
-- Off: no frames are created, no events registered. Turning it off hides the
-- panels; WoW cannot delete a frame, so they wait hidden until it is on again.

local _, ns = ...

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local ANCHORS = { "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT",
                  "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local NAME_PREFIX = "ProseccoAdditionsPanel"

local M = ns.RegisterModule("panels", {
    title       = "Panels",
    description = "Empty frames you create, place and style. Other frames can anchor to them by name.",
    -- The picked panel's settings, and making and deleting panels.
    pages       = { "Panels", "Add/delete panels" },
    defaults    = { list = {}, nextId = 1 },
    -- The panels are what the user made, not settings: a page Reset must not
    -- delete them or hand an id out again.
    keep        = { "list", "nextId" },
})

-- Runtime state; nothing here is saved.
local frames = {}           -- panel id -> our frame
local idOf = setmetatable({}, { __mode = "k" })   -- our frame -> panel id
local host                  -- event frame while the module is on
local selected = 1          -- the panel shown on the settings page

local function DB() return ns.db.modules.panels end

local function NewPanel(id)
    return {
        id = id, name = "Panel " .. id,
        w = 200, h = 120,
        point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
        attach = "screen",              -- "screen" = UIParent, "frame" = the frame named in `parent`
        parent = "UIParent",
        strata = "MEDIUM", levelMode = "absolute", level = 2, levelOffset = 1,
        texture = "none", bgColor = "000000", bgAlpha = 0.5,
        useGlobalBackground = true,     -- the colour is the Global Settings page's Global Background
        border = { useGlobal = true, style = "solid", size = 1, color = "404040", alpha = 1 },
        unlocked = false,
    }
end

-- Fills fields a panel lacks (a hand-edited import, or a field added in a
-- later version) from a new panel's values; a set value is never changed.
local function Normalize(list)
    local d = DB()
    -- nextId above every id in the list: an import can lack it or carry a
    -- lower one, and a new panel would then get an id that is taken.
    local top = 0
    for _, p in ipairs(list) do
        if type(p.id) == "number" and p.id > top then top = p.id end
    end
    if (tonumber(d.nextId) or 1) <= top then d.nextId = top + 1 end
    for _, p in ipairs(list) do
        if type(p.id) ~= "number" then
            p.id = tonumber(d.nextId) or 1
            d.nextId = p.id + 1
        end
        ns.FillDefaults(p, NewPanel(p.id))
    end
end

-- An import's panel list (checked by Core's ImportProfile before the profile
-- is replaced): every entry a panel table with its fields' types, and no id
-- twice, since a frame is found by id. An entry without an id gets a free
-- one in Normalize.
function M:CheckImport(cfg, path)
    if type(cfg.list) ~= "table" then return true end
    local ids = {}
    for i, p in ipairs(cfg.list) do
        local at = path .. ".list[" .. i .. "]"
        if type(p) ~= "table" then return false, at end
        local ok, where = ns.SameTypes(p, NewPanel(0), at)
        if not ok then return false, where end
        if p.id ~= nil then
            if ids[p.id] then return false, at .. ".id" end
            ids[p.id] = true
        end
    end
    return true
end

local function PanelById(id)
    for _, p in ipairs(DB().list) do
        if p.id == id then return p end
    end
end

local function PanelByName(name)
    local id = tonumber(tostring(name or ""):match("^" .. NAME_PREFIX .. "(%d+)$"))
    return id and PanelById(id)
end

-- True when anchoring `p` to the frame named `name` would close a loop of
-- panels anchored to each other (SetPoint raises an error on a loop).
local function MakesLoop(p, name)
    local seen = { [p.id] = true }
    local q = PanelByName(name)
    while q do
        if seen[q.id] then return true end
        seen[q.id] = true
        q = (q.attach == "frame") and PanelByName(q.parent) or nil
    end
    return false
end

-- Panels were named ProseccoUIPanel<id> before 0.7.0-alpha3: a panel anchored
-- to another panel by the old name gets the new one.
function M:Migrate(cfg)
    if type(cfg.list) ~= "table" then return end
    for _, p in ipairs(cfg.list) do
        local id = type(p) == "table" and tostring(p.parent or ""):match("^ProseccoUIPanel(%d+)$")
        if id then p.parent = NAME_PREFIX .. id end
    end
end

-- The frame a panel is anchored to, and whether the one asked for was found.
-- A name typed in the menu may not exist (yet), be forbidden, or loop back.
local function Target(p)
    if p.attach ~= "frame" then return UIParent, true end
    -- A deleted panel's frame still exists (hidden); it counts as gone.
    if tostring(p.parent or ""):match("^" .. NAME_PREFIX .. "%d+$") and not PanelByName(p.parent) then
        return UIParent, false
    end
    local f = _G[p.parent or ""]
    -- Frames only: a Texture or FontString has no frame level to follow.
    if type(f) ~= "table" or type(f.GetFrameLevel) ~= "function" then return UIParent, false end
    if f.IsForbidden and f:IsForbidden() then return UIParent, false end
    if MakesLoop(p, p.parent) then return UIParent, false end
    return f, true
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function OnDragStart(self)
    if InCombatLockdown() then return end   -- see M:Apply: a panel may be protected in combat
    self.dragLeft, self.dragBottom = self:GetLeft(), self:GetBottom()
    self:StartMoving()
end

-- StopMovingOrSizing re-anchors the frame to the screen. The drag is turned
-- into a change of the panel's own offsets instead, so its anchor point and
-- the frame it is attached to stay what the menu says.
local function OnDragStop(self)
    self:StopMovingOrSizing()
    local p = PanelById(idOf[self])
    if p and self.dragLeft then
        p.x = math.floor((tonumber(p.x) or 0) + (self:GetLeft() - self.dragLeft) + 0.5)
        p.y = math.floor((tonumber(p.y) or 0) + (self:GetBottom() - self.dragBottom) + 0.5)
    end
    self.dragLeft, self.dragBottom = nil, nil
    ns.Apply()
    ns.Ellesmere.RefreshPage()
end

local function CreatePanelFrame(id)
    local f = CreateFrame("Frame", NAME_PREFIX .. id, UIParent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    -- Shown only while unlocked, so an invisible panel can still be found.
    f.hint = ns.Media.FontString(f)
    f.hint:SetPoint("CENTER")
    f:SetMovable(true)
    -- Our offsets are the saved position; WoW's layout cache must not keep one too.
    f:SetDontSavePosition(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", OnDragStart)
    f:SetScript("OnDragStop", OnDragStop)
    frames[id] = f
    idOf[f] = id
    return f
end

local function ApplyPanel(p)
    local f = frames[p.id]
    -- Whole pixels: an edge on half a pixel draws the border blurred.
    ns.Ellesmere.PixelSize(f, math.max(4, tonumber(p.w) or 200), math.max(4, tonumber(p.h) or 120))
    local target = Target(p)
    f:ClearAllPoints()
    ns.Ellesmere.PixelPoint(f, p.point or "CENTER", target, p.relPoint or "CENTER",
        tonumber(p.x) or 0, tonumber(p.y) or 0)

    f:SetFrameStrata(p.strata or "MEDIUM")
    if p.attach == "frame" and p.levelMode == "parent" then
        f:SetFrameLevel(math.max(0, target:GetFrameLevel() + (tonumber(p.levelOffset) or 1)))
    else
        f:SetFrameLevel(math.max(0, tonumber(p.level) or 2))
    end

    -- Background: a bar texture tinted by the colour, or a flat colour.
    local hex, a = ns.BackgroundColor(p.useGlobalBackground, "background", p.bgColor, tonumber(p.bgAlpha) or 0.5)
    local r, g, b = ns.HexToRGB(hex)
    local path = ns.Ellesmere.BarTexturePath(p.texture)
    if path then
        f.bg:SetTexture(path)
        f.bg:SetVertexColor(r, g, b, a)
    else
        f.bg:SetVertexColor(1, 1, 1, 1)    -- a tint left from a texture would darken the colour
        f.bg:SetColorTexture(r, g, b, a)
    end

    ns.Border.Apply(f, p.border)

    local unlocked = p.unlocked == true
    f:EnableMouse(unlocked)
    local font, flags = ns.Ellesmere.Font()
    f.hint:SetFont(font, 12, flags)
    f.hint:SetText(p.name)
    f.hint:SetShown(unlocked)
    f:Show()
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

-- A secure frame (an action bar, a unit frame) anchored to a panel makes the
-- panel protected (Inferred), and then SetPoint, SetSize and Hide are blocked
-- in combat. So nothing is moved or hidden in combat: the change waits for
-- the end of combat and then reads the settings as they are.
local pendingAfterCombat = false

local function DrawAll()
    local list, live = DB().list, {}
    Normalize(list)
    -- Every frame exists before any is anchored, so a panel attached to a
    -- panel later in the list finds it.
    for _, p in ipairs(list) do
        live[p.id] = true
        if not frames[p.id] then CreatePanelFrame(p.id) end
    end
    -- One panel per call: an error in one (e.g. anchored to a frame that is
    -- itself anchored to the panel) is logged and the rest are still drawn.
    for _, p in ipairs(list) do
        xpcall(function() ApplyPanel(p) end, ns.ErrorHandler("panels:" .. p.id))
    end
    for id, f in pairs(frames) do
        if not live[id] then f:Hide() end
    end
end

local function HideAll()
    for _, f in pairs(frames) do
        f:EnableMouse(false)
        f:Hide()
    end
end

local function Defer()
    pendingAfterCombat = true
    host:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        host:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not pendingAfterCombat then return end
        pendingAfterCombat = false
        if ns.IsModuleEnabled("panels") then DrawAll() else HideAll() end
    elseif InCombatLockdown() then
        Defer()
    else
        DrawAll()
    end
end

-- A profile from before the global background keeps its panels' own
-- colours.
function M:KeepOwnBackgrounds(cfg)
    if type(cfg.list) ~= "table" then return end
    for _, p in ipairs(cfg.list) do
        if type(p) == "table" and p.useGlobalBackground == nil then p.useGlobalBackground = false end
    end
end

function M:Enable()
    if not host then
        host = CreateFrame("Frame")
        -- A panel can be attached to a frame another addon creates after our
        -- login; entering the world (login, reload, zoning) anchors again.
        host:SetScript("OnEvent", function(_, event)
            xpcall(function() OnEvent(_, event) end, ns.ErrorHandler("panels:" .. event))
        end)
    end
    host:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function M:Apply()
    if InCombatLockdown() then Defer() return end
    DrawAll()
end

function M:Disable()
    if not host then return end
    host:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if InCombatLockdown() then Defer() return end
    HideAll()
end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------

-- What the page holds between rebuilds; nothing here is saved.
local newName = ""          -- the name typed for a new panel
local renameTo, renameId    -- the name typed for panel renameId, until Rename
local copyFrom              -- the id of the panel Copy takes settings from
local deleteId              -- the id of the panel Delete removes

local function CreatePanel(name)
    local d = DB()
    local id = tonumber(d.nextId) or 1
    d.nextId = id + 1
    local p = NewPanel(id)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" then p.name = name end
    d.list[#d.list + 1] = p
    selected = #d.list
    ns.Apply()
    return p
end

-- Copy setting from panel: size, background, border and layer, not the
-- name or the place. A panel on the screen keeps a fixed level, as Attach
-- To sets it, since it has no frame to follow.
local COPIED = { "w", "h", "texture", "bgColor", "bgAlpha", "useGlobalBackground", "strata", "level" }
local function CopyPanel(from, to)
    for _, k in ipairs(COPIED) do to[k] = from[k] end
    to.border = ns.DeepCopy(from.border)
    if to.attach == "frame" then
        to.levelMode, to.levelOffset = from.levelMode, from.levelOffset
    end
end

-- Pairs of id -> "n. name" for a dropdown, leaving out `skip`.
local function PanelChoices(skip)
    local values, order = {}, {}
    for i, q in ipairs(DB().list) do
        if q.id ~= skip then
            values[q.id] = i .. ". " .. q.name
            order[#order + 1] = q.id
        end
    end
    return values, order
end

-- The picked panel's layer.
local function LayerRows(W, parent, y, p, P, changed, rebuild)
    local _, h
    local strataVals = {}
    for _, s in ipairs(STRATA) do strataVals[s] = s end
    local strata = { type = "dropdown", text = "Strata", values = strataVals, order = STRATA,
        getValue = function() return P().strata end,
        setValue = function(v) P().strata = v; changed() end }
    local levelSlider = { type = "slider", text = "Frame Level", min = 0, max = 128, step = 1,
        tooltip = "Higher levels draw on top, within the same strata.",
        getValue = function() return P().level end,
        setValue = function(v) P().level = v; changed() end }
    if p.attach ~= "frame" then
        _, h = W:DualRow(parent, y, strata, levelSlider); y = y - h
        return y
    end
    _, h = W:DualRow(parent, y, strata,
        { type = "dropdown", text = "Level Comes From",
          values = { absolute = "A fixed number", parent = "The frame it is attached to" },
          order = { "absolute", "parent" },
          getValue = function() return P().levelMode end,
          setValue = function(v) P().levelMode = v; changed(); rebuild() end }); y = y - h
    if p.levelMode == "parent" then
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "That Frame's Level, Plus", min = -20, max = 20, step = 1,
              getValue = function() return P().levelOffset end,
              setValue = function(v) P().levelOffset = v; changed() end },
            { type = "spacer" }); y = y - h
    else
        _, h = W:DualRow(parent, y, levelSlider, { type = "spacer" }); y = y - h
    end
    return y
end

-- The Panels tab: the picked panel's settings.
local function PanelPage(parent, y, W, changed, rebuild)
    local _, h
    local d = DB()
    _, h = W:SectionHeader(parent, "PANEL", y); y = y - h
    local values, order = {}, {}
    for i, p in ipairs(d.list) do
        values[i] = i .. ". " .. p.name
        order[i] = i
    end
    if #order == 0 then values[1] = "(no panels yet)"; order[1] = 1 end
    selected = math.max(1, math.min(selected, #d.list))
    local p = d.list[selected]
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Panel", values = values, order = order,
          disabled = function() return #DB().list == 0 end,
          disabledTooltip = "This option needs a panel: create one first.",
          getValue = function() return selected end,
          setValue = function(v) selected = tonumber(v) or 1; rebuild() end },
        -- The number in the frame name is the panel's id, not its place in the list:
        -- ids are never reused, so a frame anchored to a deleted panel never
        -- lands on a new one. The frame name is what Frame Name takes.
        { type = "label", text = p and ("Current selection: " .. p.name .. " (" .. NAME_PREFIX .. p.id .. ")")
            or "No panels yet." }); y = y - h
    if not p then
        _, h = W:DualRow(parent, y, { type = "label", text = "Create a panel on the Add/delete panels tab to get its settings here." })
        return y - h
    end
    -- Every row below acts on this panel; the page is rebuilt when another is picked.
    local id = p.id
    local function P() return PanelById(id) end

    _, h = W:DualRow(parent, y,
        { type = "input", text = "Rename This Panel", inputWidth = 160, inputStyle = "popup",
          -- Typed text belongs to the panel it was typed for: another pick,
          -- a profile switch or an import shows that panel's own name.
          getValue = function() return renameId == id and renameTo or P().name end,
          setValue = function(v) renameTo, renameId = tostring(v or ""), id end },
        { type = "button", text = "Rename", width = 130,
          onClick = function()
              local v = renameId == id and tostring(renameTo or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
              renameTo, renameId = nil, nil
              if v ~= "" then P().name = v end
              changed(); rebuild()
          end }); y = y - h
    local cValues, cOrder = PanelChoices(id)
    if not cValues[copyFrom] then copyFrom = cOrder[1] end
    if #cOrder == 0 then cValues[0] = "(no other panel)"; cOrder[1] = 0 end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Copy setting from panel:", values = cValues, order = cOrder,
          tooltip = "Size, background, border and layer. Not the name or the place.",
          disabled = function() return #DB().list < 2 end,
          disabledTooltip = "There is no other panel to copy from.",
          getValue = function() return copyFrom or 0 end,
          setValue = function(v) copyFrom = tonumber(v) end },
        { type = "button", text = "Copy", width = 130,
          disabled = function() return PanelById(copyFrom) == nil end,
          disabledTooltip = "There is no other panel to copy from.",
          onClick = function()
              local from = PanelById(copyFrom)
              if not from then return end
              ns.Ellesmere.Confirm({
                  title = "Copy panel settings",
                  message = "Give \"" .. P().name .. "\" the size, background, border and layer of \"" .. from.name .. "\"?",
                  confirmText = "Copy",
                  onConfirm = function()
                      local src = PanelById(copyFrom)
                      if src and P() then CopyPanel(src, P()) end
                      changed(); rebuild()
                  end,
              })
          end }); y = y - h

    -- Size and place: what moves the panel on the left, where it is pinned on
    -- the right.
    _, h = W:SectionHeader(parent, "SIZE AND PLACE", y); y = y - h
    local anchorVals = {}
    for _, a in ipairs(ANCHORS) do anchorVals[a] = a end
    local onScreen = p.attach ~= "frame"
    local width = { type = "slider", text = "Width", min = 4, max = 1200, step = 1,
        getValue = function() return P().w end,
        setValue = function(v) P().w = v; changed() end }
    local height = { type = "slider", text = "Height", min = 4, max = 1200, step = 1,
        getValue = function() return P().h end,
        setValue = function(v) P().h = v; changed() end }
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Unlock (drag with the mouse)",
          tooltip = "While unlocked the panel shows its name and can be dragged.",
          getValue = function() return P().unlocked == true end,
          setValue = function(v) P().unlocked = v and true or false; changed() end },
        { type = "dropdown", text = "Attach To",
          values = { screen = "The screen", frame = "Another frame" }, order = { "screen", "frame" },
          tooltip = "On the screen it is placed against the screen edges; attached to a frame it follows that frame.",
          getValue = function() return P().attach end,
          setValue = function(v)
              P().attach = v
              if v ~= "frame" then P().parent, P().levelMode = "UIParent", "absolute" end
              changed(); rebuild()
          end }); y = y - h
    _, h = W:DualRow(parent, y, width,
        { type = "dropdown", text = "Its Own Corner", values = anchorVals, order = ANCHORS,
          tooltip = "Which point of the panel is pinned.",
          getValue = function() return P().point end,
          setValue = function(v) P().point = v; changed() end }); y = y - h
    if onScreen then
        _, h = W:DualRow(parent, y, height,
            { type = "dropdown", text = "Pinned To Screen's", values = anchorVals, order = ANCHORS,
              getValue = function() return P().relPoint end,
              setValue = function(v) P().relPoint = v; changed() end }); y = y - h
    else
        _, h = W:DualRow(parent, y, height,
            { type = "dropdown", text = "Pinned To Its", values = anchorVals, order = ANCHORS,
              getValue = function() return P().relPoint end,
              setValue = function(v) P().relPoint = v; changed() end }); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Frame Name", inputWidth = 200, inputStyle = "popup",
              tooltip = "A frame's global name, e.g. ChatFrame1 or " .. NAME_PREFIX .. "1. Find one with /fstack.",
              getValue = function() return P().parent or "" end,
              setValue = function(v) P().parent = strtrim(tostring(v or "")); changed(); rebuild() end },
            { type = "spacer" }); y = y - h
        local _, found = Target(p)
        _, h = W:DualRow(parent, y,
            { type = "label", text = not ns.IsModuleEnabled("panels") and ("Attached to \"" .. tostring(p.parent) .. "\" when Panels is on.")
                or found and ("Attached to \"" .. tostring(p.parent) .. "\".")
                or ("\"" .. tostring(p.parent) .. "\" not found, or it would loop: on the screen for now.") }); y = y - h
    end

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "X Offset", min = -1200, max = 1200, step = 1,
          getValue = function() return tonumber(P().x) or 0 end,
          setValue = function(v) P().x = v; changed() end },
        { type = "slider", text = "Y Offset", min = -1200, max = 1200, step = 1,
          getValue = function() return tonumber(P().y) or 0 end,
          setValue = function(v) P().y = v; changed() end }); y = y - h
    -- One pixel per click; larger steps with the X and Y Offset sliders.
    local function nudge(dx, dy)
        P().x = (tonumber(P().x) or 0) + dx
        P().y = (tonumber(P().y) or 0) + dy
        changed(); ns.Ellesmere.RefreshPage()
    end
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Left", width = 150, onClick = function() nudge(-1, 0) end },
        { type = "button", text = "Right", width = 150, onClick = function() nudge(1, 0) end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Down", width = 150, onClick = function() nudge(0, -1) end },
        { type = "button", text = "Up", width = 150, onClick = function() nudge(0, 1) end }); y = y - h

    -- Background
    _, h = W:SectionHeader(parent, "BACKGROUND", y); y = y - h
    local texNames, texOrder = ns.Ellesmere.BarTextures()
    y = ns.Rows(W, parent, y,
        ns.UseGlobalBackgroundCell(P, changed, "Colour this panel with the Global Background on the Global Settings page."),
        { type = "dropdown", text = "Texture", values = texNames, order = texOrder,
          tooltip = "A bar texture tinted by the colour, or a flat colour.",
          getValue = function() return P().texture or "none" end,
          setValue = function(v) P().texture = v; changed() end },
        ns.BackgroundCell({ text = "Colour", cfg = P, colorKey = "bgColor", alphaKey = "bgAlpha", default = 0.5,
          follows = function() return P().useGlobalBackground == true end,
          onChange = changed }))

    -- Border
    _, h = W:SectionHeader(parent, "BORDER", y); y = y - h
    y = ns.Border.Rows(W, parent, y, function() return P().border end, changed)

    -- Layer
    _, h = W:SectionHeader(parent, "LAYER", y); y = y - h
    return LayerRows(W, parent, y, p, P, changed, rebuild)
end

-- The Add/delete panels tab.
local function AddDeletePage(parent, y, W, changed, rebuild)
    local _, h
    _, h = W:SectionHeader(parent, "ADD", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "input", text = "Name for a New Panel", inputWidth = 160, inputStyle = "popup",
          getValue = function() return newName end,
          setValue = function(v) newName = tostring(v or "") end },
        { type = "button", text = "Create", width = 130,
          onClick = function()
              local p = CreatePanel(newName)
              newName = ""
              ns.Print("panel created: " .. p.name .. " (" .. NAME_PREFIX .. p.id .. ")")
              rebuild()
          end }); y = y - h

    _, h = W:SectionHeader(parent, "DELETE", y); y = y - h
    local values, order = PanelChoices()
    if not values[deleteId] then
        -- No valid choice (first build, or the chosen panel is gone): the
        -- panel picked on the Panels tab.
        selected = math.max(1, math.min(selected, #DB().list))
        local picked = DB().list[selected]
        deleteId = picked and picked.id or nil
    end
    if #order == 0 then values[0] = "(no panels yet)"; order[1] = 0 end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Choose panel to delete", values = values, order = order,
          disabled = function() return #DB().list == 0 end,
          disabledTooltip = "There are no panels yet.",
          getValue = function() return deleteId or 0 end,
          setValue = function(v) deleteId = tonumber(v) end },
        { type = "button", text = "Delete This Panel", width = 160,
          disabled = function() return PanelById(deleteId) == nil end,
          disabledTooltip = "There are no panels yet.",
          onClick = function()
              local id = deleteId
              local q = PanelById(id)
              if not q then return end
              ns.Ellesmere.Confirm({
                  title = "Delete panel",
                  message = "Delete \"" .. q.name .. "\"? Frames anchored to it fall back to the screen.",
                  confirmText = "Delete",
                  onConfirm = function()
                      local list = DB().list
                      for i, r in ipairs(list) do
                          if r.id == id then
                              table.remove(list, i)
                              -- The Panels tab keeps showing the panel it had
                              -- (it is picked by place in the list).
                              if i < selected then selected = selected - 1 end
                              break
                          end
                      end
                      deleteId = nil
                      changed(); rebuild()
                  end,
              })
          end }); y = y - h
    return y
end

function M:BuildPage(pageName, parent, y, W)
    local _, h
    local d = DB()
    Normalize(d.list)       -- the page can be built while the module is off
    local function changed() ns.Apply() end
    -- Both tabs show panels by name, so a pick, a new name, a new or a
    -- deleted panel drops the other tab's cached page too.
    local function rebuild() ns.Ellesmere.RebuildPages({ "panels" }) end
    if pageName == "Add/delete panels" then
        y = AddDeletePage(parent, y, W, changed, rebuild)
    else
        y = PanelPage(parent, y, W, changed, rebuild)
    end
    if not ns.IsModuleEnabled("panels") then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Panels is off: turn it on under Modules on the General page." }); y = y - h
    end
    return y
end
