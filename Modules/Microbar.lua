-- ProseccoAdditions / Modules / Microbar.lua
-- A bar of our own with the game's micro menu buttons the user picks, plus
-- the volume speaker (its popup is in Volume.lua, the same module). The
-- module key stays "volume", the key of the Volume module this replaces, so
-- its saved settings carry over without a migration.
--
-- Opening the spellbook, talents or the journal from addon code taints them,
-- so each micro button is a SecureActionButton that clicks Blizzard's own
-- micro button (type "click"), as Ellesmere's micro menu block does.
-- Blizzard's buttons are never changed. In combat a state driver clears the
-- click type, so a click does nothing; the speaker is a plain button and
-- works in combat too.
--
-- The bar holds secure buttons, so it is placed, sized and shown only out of
-- combat; a change in combat waits for PLAYER_REGEN_ENABLED.
--
-- Off: the bar and the popup are hidden, no events.

local ADDON, ns = ...

local M = ns.RegisterModule("volume", {
    title       = "Microbar",
    description = "A bar with the game's menu buttons you pick and a volume speaker with a popup of the five volume sliders.",
    pages       = { "Microbar", "Enabled buttons" },
    defaults    = {
        point = "TOP", x = 0, y = -4,   -- on UIParent; drag with Unlock
        unlocked = false,
        barWidth = 260,                 -- px; the icons share it and scale
        padding = 2,                    -- px between the bar's edge and the icons
        gap = 2,                        -- px between icons
        bgColor = "000000", bgAlpha = 0.75,
        useGlobalBackground = true,
        border = { useGlobal = true, style = "solid", size = 1, color = "000000", alpha = 1 },
        -- Each icon:
        iconBorder = true,              -- 1 px, the bar border's colour
        iconBg = false, iconBgColor = "000000", iconBgAlpha = 0.5,
        desaturate = false,
        -- The whole bar shown only while the mouse is over it (not on the
        -- minimap).
        mouseover = false,
        -- New buttons start on for the everyday ones; the rest are there to pick.
        buttons = {
            character = true, professions = false, spellbook = true, talents = true,
            questlog = true, guild = true, groupfinder = true, collections = true,
            journal = false, legacy = false, help = false,
            store = false, menu = true, bags = false, volume = true,
        },
    },
})

local function DB() return ns.db.modules.volume end
M.DB = DB

-- Bar order, left to right. `micro`: Blizzard's button the click goes to, in
-- Forever's micro menu; bags is the backpack button. `own`: our icon in
-- Media/MicroMenu; `icon`: Ellesmere's flat icon where ours has none.
local BUTTONS = {
    { key = "character",   micro = "CharacterMicroButton",      own = "Character",   label = "Character" },
    { key = "professions", micro = "ProfessionMicroButton",     own = "Professions", label = "Professions" },
    { key = "spellbook",   micro = "SpellbookMicroButton",      own = "Spellbook",   label = "Spellbook" },
    { key = "talents",     micro = "TalentMicroButton",         own = "Talents",     label = "Talents" },
    { key = "questlog",    micro = "QuestLogMicroButton",       own = "QuestLog",    label = "Quest Log" },
    { key = "guild",       micro = "GuildMicroButton",          own = "Guild",       label = "Guild & Communities" },
    { key = "groupfinder", micro = "LFDMicroButton",            own = "GroupFinder", label = "Group Finder" },
    { key = "collections", micro = "CollectionsMicroButton",    own = "Collections", label = "Collections" },
    { key = "journal",     micro = "EJMicroButton",             icon = "menu-adventure",   label = "Adventure Guide" },
    { key = "legacy",      micro = "LegacyMicroButton",         own = "Legacy",      label = "Legacy" },
    { key = "help",        micro = "HelpMicroButton",           own = "Help",        label = "Customer Support" },
    { key = "store",       micro = "StoreMicroButton",          own = "Shop",        label = "Shop" },
    { key = "menu",        micro = "MainMenuMicroButton",       own = "GameMenu",    label = "Game Menu" },
    { key = "bags",        micro = "MainMenuBarBackpackButton", icon = "menu-bags",        label = "Bags", notMicro = true },
    { key = "volume",      volume = true, own = "Volume", label = "Volume" },
}

local OWN_ICONS = "Interface\\AddOns\\" .. ADDON .. "\\Media\\MicroMenu\\"

-- Runtime only
local bar, mover
local buttons = {}          -- key -> our button
local host                  -- event frame while a change waits for the end of combat
local hoverTicker           -- while the bar is on mouseover
local mapWatch              -- events while the bar sits under the minimap

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

-- Size 0: ns.Border.Apply hides the frame's border.
local NO_BORDER = { style = "solid", size = 0, color = "000000", alpha = 1 }
local ICON_BORDER = { style = "solid", size = 1, color = "000000", alpha = 1 }

-- `alpha`: in place of the setting's (1 on the minimap; 0 while seamed,
-- where the Minimap's bottom panel is the background).
local function Background(f, alpha)
    local d = DB()
    local hex, a = ns.BackgroundColor(d.useGlobalBackground, "background", d.bgColor, tonumber(d.bgAlpha) or 0.75)
    local r, g, b = ns.HexToRGB(hex)
    f.bg:SetColorTexture(r, g, b, alpha or a)
    ns.Border.Apply(f, d.border)
end

-- The speaker's colour: red while all sound is off.
function M.PaintSpeaker()
    local b = buttons.volume
    if not b then return end
    local _, on = M.VolumeMaster()
    if on then b.art:SetVertexColor(1, 1, 1, 1) else b.art:SetVertexColor(1, 0.3, 0.3, 1) end
end

local function OnEnter(self)
    local def = self.def
    if def.volume then
        local p, on = M.VolumeMaster()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Volume")
        GameTooltip:AddLine("Master " .. p .. "%" .. (on and "" or " (off)"), 1, 1, 1)
        GameTooltip:AddLine("Click: the sliders. Right-click: all sound on/off. Wheel: Master, Shift for 10%.", 0.7, 0.7, 0.7)
    else
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(def.label)
        if InCombatLockdown() then GameTooltip:AddLine("Not in combat.", 0.7, 0.7, 0.7) end
    end
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

local function Art(b, def)
    b.art = b:CreateTexture(nil, "ARTWORK")
    if def.own then
        b.art:SetTexture(OWN_ICONS .. def.own)
        -- The icons have empty space round the picture: trimmed so the picture
        -- fills the button.
        b.art:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    else
        b.art:SetTexture(ns.Ellesmere.MicroMenuIcon(def.icon))
    end
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    -- Shown by the button itself while the mouse is over it (HIGHLIGHT
    -- layer): no script, so it needs nothing in combat.
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetColorTexture(1, 1, 1, 0.15)
    b.hl:SetAllPoints()
end

-- Blizzard's button, when Blizzard shows it in its own micro menu: a button
-- a game rule turns off (housing, shop, help ...) still exists but is left
-- out of the menu and gets no layoutIndex. The backpack is not a micro
-- button.
local function Micro(def)
    local micro = _G[def.micro]
    if micro and (def.notMicro or micro.layoutIndex) then return micro end
end

local function Available(def) return def.volume or Micro(def) ~= nil end

-- Out of combat only (secure). nil when Blizzard does not offer that button
-- (Micro): then the key is skipped.
local function EnsureButton(def)
    if buttons[def.key] then return buttons[def.key] end
    local b
    if def.volume then
        b = CreateFrame("Button", nil, bar)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then M.ToggleMute() else M.ToggleVolume(self) end
        end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta) M.VolumeWheel(delta) end)
    else
        local micro = Micro(def)
        if not micro then return nil end
        b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
        b:SetAttribute("*type1", "click")
        b:SetAttribute("*clickbutton1", micro)
        -- With the ActionButtonUseKeyDown CVar on, a secure button acts on key
        -- down only, and our up-clicks would do nothing.
        b:SetAttribute("useOnKeyDown", false)
        b:RegisterForClicks("LeftButtonUp")
        -- Combat: no click type, so a click does nothing; set inside the
        -- secure environment (no addon code touches the button in combat).
        RegisterStateDriver(b, "combatlock", "[combat] combat; nocombat")
        b:SetAttribute("_onstate-combatlock", [[
            if newstate == "combat" then
                self:SetAttribute("*type1", nil)
            else
                self:SetAttribute("*type1", "click")
            end
        ]])
    end
    b.def = def
    Art(b, def)
    -- Tooltips and hover are not protected: allowed on a secure button.
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    buttons[def.key] = b
    return b
end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------

local function OnDragStart()
    if InCombatLockdown() then return end   -- the bar holds secure buttons
    bar.dragLeft, bar.dragBottom = bar:GetLeft(), bar:GetBottom()
    bar:StartMoving()
end

-- The drag becomes new saved offsets, as a panel's, so the bar keeps its
-- anchor point.
local function OnDragStop()
    if not bar.dragLeft then return end
    if InCombatLockdown() then
        -- Combat began during the drag: the bar cannot be moved now; the
        -- deferred layout puts it back at its saved place.
        bar.dragLeft, bar.dragBottom = nil, nil
        ns.Apply()
        return
    end
    bar:StopMovingOrSizing()
    local d = DB()
    d.x = math.floor((tonumber(d.x) or 0) + (bar:GetLeft() - bar.dragLeft) + 0.5)
    d.y = math.floor((tonumber(d.y) or 0) + (bar:GetBottom() - bar.dragBottom) + 0.5)
    bar.dragLeft, bar.dragBottom = nil, nil
    ns.Apply()
    ns.Ellesmere.RefreshPage()
end

local function EnsureBar()
    if bar then return end
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetDontSavePosition(true)   -- our offsets are the saved place
    bar:SetClampedToScreen(true)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar:Hide()
    -- While unlocked a plain frame over the buttons takes the drag, so a
    -- drag never starts on a secure button.
    mover = CreateFrame("Frame", nil, bar)
    mover:SetAllPoints()
    mover:SetFrameLevel(bar:GetFrameLevel() + 20)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", OnDragStart)
    mover:SetScript("OnDragStop", OnDragStop)
    mover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Microbar")
        GameTooltip:AddLine("Drag to move. Lock it on the Microbar page to use the buttons.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mover.tint = mover:CreateTexture(nil, "OVERLAY")
    mover.tint:SetAllPoints()
    mover.tint:SetColorTexture(1, 1, 1, 0.12)
    mover:Hide()
end

-- The picked buttons that exist, in bar order (creates them).
local function Shown()
    local picked, list = DB().buttons, {}
    for _, def in ipairs(BUTTONS) do
        if picked[def.key] then
            local b = EnsureButton(def)
            if b then list[#list + 1] = b end
        end
    end
    return list
end

-- Blizzard's micro menu hidden while the module is on and Hide Blizzard
-- Micro Menu is ticked. Hide() from addon code on MicroMenuContainer (Edit
-- Mode places it) taints the managed frame system, so as in Ellesmere's Data
-- Bars the hide runs in a secure state driver's snippet (Unverified in
-- Forever). Blizzard's buttons stay where they are and still take our
-- buttons' clicks. Out of combat only (the driver is on a secure frame).
local hiders = {}           -- Blizzard frame -> our secure hider
local blizzState            -- last state pushed ("hide"/"show"); nil: never touched
local petWatch              -- PET_BATTLE_* while hidden

-- Blizzard's own micro menu hidden while the bar is on. Not a setting: the
-- sim turns it off (tools/sim/shim/SimExpose.lua).
M.hideBlizzardMenu = true

local function BlizzardMenu(hide, force)
    -- Never touched until the first hide: nothing to put back before that.
    if not hide and blizzState == nil then return end
    local want = hide and "hide" or "show"
    if want == blizzState and not force then return end
    blizzState = want
    -- The names Ellesmere's hider covers; the older two do not exist in
    -- every client.
    for _, name in ipairs({ "MicroMenuContainer", "MainMenuBarMicroButtons", "MicroButtonAndBagsBar" }) do
        local target = _G[name]
        if target then
            local h = hiders[target]
            if not h then
                h = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
                h:SetFrameRef("target", target)
                h:SetAttribute("_onstate-vis", [[
                    local target = self:GetFrameRef("target")
                    if newstate == "hide" then target:Hide() else target:Show() end
                ]])
                hiders[target] = h
            end
            UnregisterStateDriver(h, "vis")
            RegisterStateDriver(h, "vis", want)
        end
    end
    -- A pet battle hides and then shows Blizzard's micro menu again, past a
    -- driver whose state never changes: pushed again when the battle ends.
    if hide and not petWatch then
        petWatch = CreateFrame("Frame")
        petWatch:SetScript("OnEvent", function()
            if InCombatLockdown() then return end
            xpcall(function() BlizzardMenu(true, true) end, ns.ErrorHandler("volume:petBattle"))
        end)
    end
    if petWatch then
        for _, e in ipairs({ "PET_BATTLE_OVER", "PET_BATTLE_CLOSE" }) do
            if hide then petWatch:RegisterEvent(e) else petWatch:UnregisterEvent(e) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Mouseover
-- ---------------------------------------------------------------------------

-- No event says where the cursor is, so a 0.1 s ticker checks while the bar
-- is on mouseover. SetAlpha is not protected, so the bar fades in combat
-- too. It stays shown while the volume popup is open or the bar is unlocked.
local function UpdateHover()
    if not bar:IsShown() then return end
    local over = bar:IsMouseOver() or M.VolumeShown() or DB().unlocked == true
    bar:SetAlpha(over and 1 or 0)
end

local function StopHover()
    if hoverTicker then hoverTicker:Cancel(); hoverTicker = nil end
    if bar then bar:SetAlpha(1) end
end

local function StartHover()
    if not hoverTicker then
        hoverTicker = C_Timer.NewTicker(0.1, function()
            xpcall(UpdateHover, ns.ErrorHandler("volume:hover"))
        end)
    end
    UpdateHover()
end

-- ---------------------------------------------------------------------------
-- On the minimap
-- ---------------------------------------------------------------------------

-- In place of the Minimap module's bottom panel: as wide as the map, under
-- its visible bottom. The bar is anchored to UIParent at the map's place,
-- not to the map: a protected frame anchored to the map would make the map's
-- own moves protected in combat. So the bar follows the map only out of
-- combat: at login, a scale change, Ellesmere's menu closing and any
-- settings change.
-- Returns left, top (from UIParent's bottom left, bar units), width, the
-- map's strata and whether seamed; nil when the setting is off or the map
-- has no place yet.
local STRATA_ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG" }

local function MinimapPlace()
    if ns.db.global.microbarOnMinimap ~= true then return nil end
    local look = ns.Ellesmere.MinimapLook()
    local map = _G.Minimap
    if not (look and map) then return nil end
    local left, bottom, w, h = map:GetLeft(), map:GetBottom(), map:GetWidth(), map:GetHeight()
    -- Not placed yet at login (Ellesmere places it later);
    -- PLAYER_ENTERING_WORLD lays the bar out again.
    if not (left and bottom and w and h) then return nil end
    -- The map's size may be a secret value while Ellesmere animates it.
    if issecretvalue(w) or issecretvalue(h) or issecretvalue(left) or issecretvalue(bottom) then return nil end
    local inset = ns.Ellesmere.MinimapInset(look, h, ns.Ellesmere.PixelUnit(map))
    local k = map:GetEffectiveScale() / bar:GetEffectiveScale()
    -- With the Minimap module on, its border goes round the map and the bar
    -- with a seam between them, and the bar draws no border of its own. Without
    -- it, one pixel up: the bar's top border line on the map's bottom one.
    local seamed = ns.IsModuleEnabled("minimap") and not look.round
    local overlap = (seamed or look.round) and 0 or ns.Ellesmere.PixelUnit(bar)
    return left * k, (bottom + inset) * k + overlap, w * k, map:GetFrameStrata(), seamed
end

-- The bar is not the map's child, so it hides with the map (a pet battle,
-- Ellesmere's visibility) by alpha, which is allowed in combat (Show and
-- Hide are not).
local function FollowMapShown()
    if bar and bar:IsShown() and ns.db.global.microbarOnMinimap == true and ns.IsModuleEnabled("volume") then
        bar:SetAlpha(_G.Minimap:IsVisible() and 1 or 0)
    end
end

local function OnMapChanged()
    if ns.IsModuleEnabled("volume") and ns.db.global.microbarOnMinimap == true then M.Relayout() end
end

local function WatchMap(on)
    if on and not mapWatch then
        mapWatch = CreateFrame("Frame")
        mapWatch:SetScript("OnEvent", function(_, event)
            xpcall(OnMapChanged, ns.ErrorHandler("volume:" .. event))
        end)
        -- Ellesmere redraws its map when its menu closes (a public
        -- registration, once, gated in OnMapChanged).
        ns.Ellesmere.OnMenuClosed(OnMapChanged)
        -- Post-hooks on Blizzard's Minimap, once, gated in FollowMapShown.
        _G.Minimap:HookScript("OnShow", FollowMapShown)
        _G.Minimap:HookScript("OnHide", FollowMapShown)
    end
    if not mapWatch then return end
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        if on then mapWatch:RegisterEvent(e) else mapWatch:UnregisterEvent(e) end
    end
end

-- Out of combat only.
local function Layout()
    EnsureBar()
    local d = DB()
    BlizzardMenu(M.hideBlizzardMenu)
    local list = Shown()
    for _, b in pairs(buttons) do b:Hide() end
    local n = #list
    if n == 0 then
        StopHover()
        WatchMap(false)
        ns.SetMinimapBar(nil)
        bar:Hide()
        return
    end
    local mapLeft, mapTop, mapW, mapStrata, seamed = MinimapPlace()
    WatchMap(ns.db.global.microbarOnMinimap == true)
    local w = mapW or math.max(20, tonumber(d.barWidth) or 260)
    local pad = math.max(0, tonumber(d.padding) or 0)
    local gap = math.max(0, tonumber(d.gap) or 0)
    -- The icons share the width: whole pixels each, the rest split to the
    -- two ends so the row stays centred in the bar.
    local size = math.max(8, math.floor((w - 2 * pad - gap * (n - 1)) / n))
    local left = pad + math.floor((w - 2 * pad - gap * (n - 1) - size * n) / 2)
    -- Each button 3:4, a little taller than wide; the square icon in its
    -- middle.
    local height = math.max(10, math.floor(size * 4 / 3 + 0.5))
    ns.Ellesmere.PixelSize(bar, w, height + 2 * pad)
    bar:ClearAllPoints()
    if mapW then
        ns.Ellesmere.PixelPoint(bar, "TOPLEFT", UIParent, "BOTTOMLEFT", mapLeft, mapTop)
        -- Over the map's hidden strip and the pins in it, as the Minimap
        -- panels. Seamed: one more, the Minimap's border strata, over the
        -- bottom panel that is its background.
        local strata = STRATA_ABOVE[mapStrata] or "MEDIUM"
        if seamed then strata = STRATA_ABOVE[strata] or strata end
        bar:SetFrameStrata(strata)
    else
        ns.Ellesmere.PixelPoint(bar, d.point or "TOP", UIParent, d.point or "TOP", tonumber(d.x) or 0, tonumber(d.y) or 0)
        bar:SetFrameStrata("MEDIUM")
    end
    Background(bar, seamed and 0 or (mapW and 1) or nil)
    if seamed then ns.Border.Apply(bar, NO_BORDER) end
    -- The icon as wide as the button allows, one pixel inside the icon's
    -- border, whose line lies inside the frame.
    local u = ns.Ellesmere.PixelUnit(bar)
    local inset = (d.iconBorder and 2 or 1) * u
    local side = math.max(4, size - 2 * inset)
    local hex, a = ns.BackgroundColor(false, "background", d.iconBgColor, tonumber(d.iconBgAlpha) or 0.5)
    local bgR, bgG, bgB = ns.HexToRGB(hex)
    -- The icon border is always black, 1 px.
    local iconBorder = d.iconBorder and ICON_BORDER or NO_BORDER
    for i, b in ipairs(list) do
        b:ClearAllPoints()
        ns.Ellesmere.PixelSize(b, size, height)
        ns.Ellesmere.PixelPoint(b, "TOPLEFT", bar, "TOPLEFT", left + (i - 1) * (size + gap), -pad)
        b.art:ClearAllPoints()
        ns.Ellesmere.PixelSize(b.art, side, side)
        ns.Ellesmere.PixelPoint(b.art, "CENTER", b, "CENTER", 0, 0)
        b.art:SetDesaturated(d.desaturate == true)
        b.bg:SetColorTexture(bgR, bgG, bgB, a)
        b.bg:SetShown(d.iconBg == true)
        b.hl:Show()
        ns.Border.Apply(b, iconBorder)
        b:Show()
    end
    if not d.buttons.volume then M.CloseVolume() end
    M.PaintSpeaker()
    mover:SetShown(d.unlocked == true and not mapW)
    bar:Show()
    if d.mouseover == true and not mapW then StartHover() else StopHover() end
    if mapW then FollowMapShown() end
    -- The bar's height for the Minimap's border round it.
    ns.SetMinimapBar(seamed and bar:GetHeight() * bar:GetEffectiveScale() or nil)
end

local function HideBar()
    StopHover()
    WatchMap(false)
    ns.SetMinimapBar(nil)
    M.CloseVolume()
    BlizzardMenu(false)
    if bar then bar:Hide() end
end

-- What the settings say now, or after combat (secure buttons in the bar).
local function Update()
    if InCombatLockdown() then
        if not host then
            host = CreateFrame("Frame")
            host:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                xpcall(function()
                    if ns.IsModuleEnabled("volume") then Layout() else HideBar() end
                end, ns.ErrorHandler("volume:PLAYER_REGEN_ENABLED"))
            end)
        end
        host:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if ns.IsModuleEnabled("volume") then Layout() else HideBar() end
end

function M.Relayout() Update() end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

function M:Enable()
    -- Frames come with the first Apply (Layout), out of combat.
end

function M:Apply()
    Update()
    M.ApplyVolume()
end

function M:Disable()
    M.CloseVolume()
    Update()
end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------

function M:BuildPage(pageName, parent, y, W)
    local _, h
    local function changed() ns.Apply() end

    if pageName == "Enabled buttons" then
        local function Pick(def)
            if not def then return { type = "spacer" } end
            local tip = def.volume and "The speaker: a click opens the five volume sliders, the wheel sets Master. Works in combat."
                or ("Opens " .. def.label .. ", as Blizzard's own button. Does nothing in combat.")
            return { type = "toggle", text = def.label, tooltip = tip,
                disabled = function() return not Available(def) end,
                disabledTooltip = "Blizzard does not offer this button in WoW Forever right now.",
                getValue = function() return DB().buttons[def.key] == true end,
                setValue = function(v) DB().buttons[def.key] = v and true or false; changed() end }
        end
        _, h = W:SectionHeader(parent, "BUTTONS TO SHOW", y); y = y - h
        for i = 1, #BUTTONS, 2 do
            _, h = W:DualRow(parent, y, Pick(BUTTONS[i]), Pick(BUTTONS[i + 1])); y = y - h
        end
        return y
    end

    local function Slider(text, tip, key, minV, maxV)
        return { type = "slider", text = text, min = minV, max = maxV, step = 1, tooltip = tip,
            getValue = function() return tonumber(DB()[key]) or minV end,
            setValue = function(v) DB()[key] = v; changed() end }
    end
    local function Toggle(text, tip, key)
        return { type = "toggle", text = text, tooltip = tip,
            getValue = function() return DB()[key] == true end,
            setValue = function(v) DB()[key] = v and true or false; changed() end }
    end

    local function OnMap() return ns.db.global.microbarOnMinimap == true end
    local ON_MAP_TIP = "Not used while the bar is on the Minimap."
    local function Placed(cell) cell.disabled, cell.disabledTooltip = OnMap, ON_MAP_TIP; return cell end

    _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "On the Minimap",
          tooltip = "The bar under Ellesmere's minimap, as wide as the map, in place of the Minimap module's bottom panel; the clock, FPS and latency then show as a small badge on the map. Needs EllesmereUI Minimap. Changes made in combat show when combat ends.",
          getValue = OnMap,
          setValue = function(v) ns.db.global.microbarOnMinimap = v and true or false; changed(); ns.Ellesmere.RefreshPage() end },
        Placed({ type = "toggle", text = "Mouseover",
          tooltip = "The whole bar shown only while the mouse is over it (and while the volume popup is open).",
          getValue = function() return DB().mouseover == true end,
          setValue = function(v) DB().mouseover = v and true or false; changed() end })); y = y - h

    _, h = W:SectionHeader(parent, "BAR", y); y = y - h
    _, h = W:DualRow(parent, y,
        Placed(Slider("Total bar width", "Pixels, the whole bar. The icons share it: more icons, smaller icons.", "barWidth", 60, 800)),
        Placed({ type = "toggle", text = "Unlock (drag with the mouse)",
          tooltip = "While unlocked the bar can be dragged and its buttons do nothing. Not in combat.",
          getValue = function() return DB().unlocked == true end,
          setValue = function(v) DB().unlocked = v and true or false; changed() end })); y = y - h
    _, h = W:DualRow(parent, y,
        Slider("Padding", "Pixels between the bar's edge and the icons.", "padding", 0, 16),
        Slider("Icon Gap", "Pixels between the icons.", "gap", 0, 16)); y = y - h

    _, h = W:SectionHeader(parent, "ICONS", y); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle("Desaturate", "The icons in grey.", "desaturate"),
        Toggle("Icon Background", "A background behind each icon.", "iconBg")); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle("Icon Border", "A black 1 px line round each icon.", "iconBorder"),
        ns.BackgroundCell({ text = "Icon Background Colour", cfg = DB, colorKey = "iconBgColor", alphaKey = "iconBgAlpha",
            default = 0.5, follows = function() return false end, onChange = changed,
            disabled = function() return DB().iconBg ~= true end,
            disabledTooltip = "Turn on Icon Background first.",
            tooltip = "The background behind each icon." })); y = y - h

    _, h = W:SectionHeader(parent, "BACKGROUND", y); y = y - h
    y = ns.Rows(W, parent, y,
        ns.UseGlobalBackgroundCell(DB, changed, "Draw the bar and the popup with the Global Background on the Global Settings page."),
        ns.BackgroundCell({ text = "Background", cfg = DB, colorKey = "bgColor", alphaKey = "bgAlpha", default = 0.75,
            follows = function() return DB().useGlobalBackground == true end, onChange = changed,
            tooltip = "The bar's and the popup's background." }))

    _, h = W:SectionHeader(parent, "BORDER", y); y = y - h
    y = ns.Border.Rows(W, parent, y, function() return DB().border end, changed)

    if not ns.IsModuleEnabled("volume") then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Microbar is off: turn it on under Modules on the General page." }); y = y - h
    end
    return y
end

-- For the simulator's microbar test (with M.VolumeShown in Volume.lua).
function M.BarFrames() return bar, buttons end
