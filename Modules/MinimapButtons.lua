-- ProseccoUI / Modules / MinimapButtons.lua
-- The minimap's buttons as ours, each shown always, on mouseover of the map,
-- or never. Part of the Minimap module, which calls M.LayoutButtons from its
-- Draw and M.ButtonsOff when it goes off.
--
-- Ellesmere's own minimap buttons are never touched: they are turned off
-- through its Show Blizzard Elements settings (owned values in Minimap.lua)
-- and ours, doing what Blizzard's do, stand in their place. Crafting orders
-- stay Ellesmere's: it ignores its hideCraftingOrder setting, so ours would
-- show next to its own.
--
-- Plain buttons (nothing protected), children of Minimap: they also work and
-- move in combat.

local _, ns = ...
local M = ns.GetModule("minimap")

local function DB() return ns.db.modules.minimap.buttons end

-- Runtime only
local frames = {}           -- key -> our button
local host                  -- events while the module is on
local hoverTicker           -- while a button is on mouseover
local hoverInset = 0        -- the map's hidden top and bottom (rectangular shape)
local laidOut = false

-- ---------------------------------------------------------------------------
-- What each button does
-- ---------------------------------------------------------------------------

-- Blizzard's tracking menu, opened from its own button, which Ellesmere keeps
-- hidden in place; the menu is moved next to ours, as Ellesmere's tracking
-- button does it. `menu` is Blizzard's field for the open menu (Assumed).
local function OpenTracking(self)
    local b = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
    -- A client without Blizzard's tracking button: the button does nothing.
    if not (b and b.OpenMenu) then return end
    if b.menu and b.menu:IsShown() then
        b.menu:Hide()
        return
    end
    b:OpenMenu()
    if b.menu then
        b.menu:ClearAllPoints()
        b.menu:SetPoint("TOPRIGHT", self, "TOPLEFT", -4, 0)
    end
end

local function Zoom(step)
    local map = _G.Minimap
    local z = map:GetZoom() + step
    if z >= 0 and z < map:GetZoomLevels() then map:SetZoom(z) end
end

local function HasMail()
    local v = HasNewMail()
    -- HasNewMail can be secret; Ellesmere tests it the same way.
    if issecretvalue(v) then return false end
    return v == true
end

-- "5N", "10H", "40" ... inside an instance; nil outside.
local function DifficultyText()
    local _, instanceType, difficultyID, _, maxPlayers = GetInstanceInfo()
    if instanceType == "none" or not difficultyID or difficultyID == 0 then return nil end
    local _, _, isHeroic, _, displayHeroic, displayMythic = GetDifficultyInfo(difficultyID)
    local tag = displayMythic and "M" or (isHeroic or displayHeroic) and "H" or "N"
    return (maxPlayers and maxPlayers > 0 and maxPlayers or "") .. tag
end

local function Tooltip(self, text)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

-- Bar order, top to bottom. `has`: shown only while it returns true.
local ELEMENTS = {
    { key = "tracking", setting = "tracking", label = "Tracking", atlas = "ui-hud-minimap-tracking",
      click = OpenTracking },
    { key = "calendar", setting = "calendar", label = "Calendar", calendar = true,
      click = function() ToggleCalendar() end },
    { key = "mail", setting = "mail", label = "Mail", atlas = "ui-hud-minimap-mail", noDown = true, has = HasMail,
      enter = function(self)
          GameTooltip:SetOwner(self, "ANCHOR_LEFT")
          local senders = { GetLatestThreeSenders() }
          FormatUnreadMailTooltip(GameTooltip, #senders >= 1 and HAVE_MAIL_FROM or HAVE_MAIL, senders)
          GameTooltip:Show()
      end },
    { key = "difficulty", setting = "difficulty", label = "Instance Difficulty", text = true,
      has = function() return DifficultyText() ~= nil end },
    { key = "zoomIn", setting = "zoom", label = "Zoom In", atlas = "ui-hud-minimap-zoom-in",
      click = function() Zoom(1) end },
    { key = "zoomOut", setting = "zoom", label = "Zoom Out", atlas = "ui-hud-minimap-zoom-out",
      click = function() Zoom(-1) end },
}
M.BUTTON_SETTINGS = {
    { key = "tracking",   label = "Tracking" },
    { key = "calendar",   label = "Calendar" },
    { key = "mail",       label = "Mail" },
    { key = "difficulty", label = "Instance Difficulty" },
    { key = "zoom",       label = "Zoom +/-" },
}

-- Blizzard's atlases for the states of one button: "-up", "-down",
-- "-mouseover".
local function SetArt(b, def)
    local normal, pushed, hover
    if def.calendar then
        local p = "UI-HUD-Calendar-" .. (tonumber(date("%d")) or 1)
        normal, pushed, hover = p .. "-Up", p .. "-Down", p .. "-Mouseover"
    elseif def.key == "zoomIn" or def.key == "zoomOut" then
        normal, pushed, hover = def.atlas, def.atlas .. "-down", def.atlas .. "-mouseover"
    else
        normal, pushed, hover = def.atlas .. "-up", def.atlas .. "-down", def.atlas .. "-mouseover"
    end
    -- Mail has no pressed art (Ellesmere passes none either).
    if def.noDown then pushed = normal end
    b:SetNormalAtlas(normal)
    b:SetPushedAtlas(pushed)
    b:SetHighlightAtlas(hover)
end

local function Ensure(def)
    local b = frames[def.key]
    if b then return b end
    local map = _G.Minimap
    b = CreateFrame("Button", nil, map)
    -- Above Ellesmere's ping blocker (map level +10, takes the mouse), which
    -- would otherwise eat our tooltips and highlight; the level its own buttons
    -- use.
    b:SetFrameLevel(map:GetFrameLevel() + 20)
    b:RegisterForClicks("LeftButtonUp")
    b.def = def
    if def.text then
        b.label = b:CreateFontString(nil, "OVERLAY")
        b.label:SetPoint("CENTER")
    else
        SetArt(b, def)
    end
    if def.click then
        b:SetScript("OnClick", function(self)
            xpcall(function() def.click(self) end, ns.ErrorHandler("minimap:" .. def.key))
        end)
    end
    b:SetScript("OnEnter", function(self)
        if def.enter then def.enter(self) else Tooltip(self, def.label) end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frames[def.key] = b
    return b
end

-- ---------------------------------------------------------------------------
-- Mouseover
-- ---------------------------------------------------------------------------

-- No event says where the cursor is, and the frames Ellesmere lays over the
-- map are not ours to hook, so a 0.1 s ticker checks whether the cursor is
-- over the map's visible part or a button. It runs only while a button is
-- on mouseover and stops with the module.
local function Hovered()
    local map = _G.Minimap
    if map:IsMouseOver(-hoverInset, hoverInset, 0, 0) then return true end
    for _, b in pairs(frames) do
        if b:IsShown() and b:IsMouseOver() then return true end
    end
    return false
end

local function UpdateHover()
    if not _G.Minimap:IsVisible() then return end
    local over = Hovered()
    local d = DB()
    for _, b in pairs(frames) do
        if b:IsShown() and d[b.def.setting] == "mouseover" then
            b:SetAlpha(over and 1 or 0)
            -- A hidden button lets the click through to the map.
            b:EnableMouse(over)
        end
    end
end

local function StopHover()
    if hoverTicker then hoverTicker:Cancel(); hoverTicker = nil end
end

local function StartHover()
    if hoverTicker then return end
    hoverTicker = C_Timer.NewTicker(0.1, function()
        xpcall(UpdateHover, ns.ErrorHandler("minimap:hover"))
    end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- A column inside the map's top right corner, under its border. `top`: from
-- the Minimap frame's top to the map's visible top plus the border (UI units).
function M.LayoutButtons(top, u)
    laidOut = true
    local d = DB()
    local size = 20 * u     -- px
    local gap = 2 * u
    local pad = 4 * u
    local y = -(top + pad)
    local anyHover = false
    for _, def in ipairs(ELEMENTS) do
        local mode = d[def.setting]
        local show = mode ~= "never" and (not def.has or def.has())
        local b = (show or frames[def.key]) and Ensure(def)
        if b then
            if show then
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", _G.Minimap, "TOPRIGHT", -pad, ns.Border.Snap(y, u))
                if def.text then
                    local font, flags = ns.Ellesmere.Font()
                    b.label:SetFont(font, math.max(8, math.floor(size * 0.55 + 0.5)), flags)
                    b.label:SetText(DifficultyText() or "")
                elseif def.calendar then
                    SetArt(b, def)          -- the day may have changed
                end
                if mode == "mouseover" then
                    anyHover = true
                else
                    b:SetAlpha(1)
                    b:EnableMouse(true)
                end
                b:Show()
                y = y - size - gap
            else
                b:Hide()
            end
        end
    end
    if anyHover then
        UpdateHover()
        StartHover()
    else
        StopHover()
    end
end

-- The top of the rectangular map's visible part, for the hover test.
function M.SetHoverInset(inset) hoverInset = inset or 0 end

-- Mail and the instance come and go: lay the column out again (cheap).
local EVENTS = { "UPDATE_PENDING_MAIL", "PLAYER_DIFFICULTY_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }

function M.ButtonsOn(redraw)
    if not host then
        host = CreateFrame("Frame")
        host:SetScript("OnEvent", function(_, event)
            xpcall(redraw, ns.ErrorHandler("minimap:" .. event))
        end)
    end
    for _, e in ipairs(EVENTS) do
        host:RegisterEvent(e)
    end
end

function M.ButtonsOff()
    if host then host:UnregisterAllEvents() end
    StopHover()
    for _, b in pairs(frames) do b:Hide() end
    laidOut = false
end

-- For the simulator's minimap test.
function M.ButtonFrames() return frames, laidOut end
