-- ProseccoAdditions / Integrations / Ellesmere.lua
-- Everything ProseccoAdditions touches in EllesmereUI goes through this file. Only
-- public API (the plugin API and functions without a leading "_"); no field
-- starting with "_" is read or written here.
-- Checked against EllesmereUI 9.3.9 (a3b97b7).

local ADDON, ns = ...

local E = {}
ns.Ellesmere = E

local function EUI() return _G.EllesmereUI end

-- What the modules call in EllesmereUI outside its options menu, all from its
-- main addon and set while it loads, before ours (the content header calls
-- are set later, with the menu). A newer EllesmereUI that renamed one
-- would give Lua errors in every module, so none starts and the chat says
-- which are missing. Calls already checked where they are made are left out.
local NEEDED = {
    "AbbreviateNumber", "AppendSharedMediaTextures", "ApplyBorderStyle", "ApplyModuleFont",
    "BORDER_EDGE_MAP", "BorderCompanionThickness", "BorderPx", "BorderPxStep",
    "BuildBarTextureTables", "CLASS_ICON_SPRITE_COORDS", "ELLESMERE_GREEN", "GetActiveModule",
    "GetActiveProfileName", "GetBorderDefaults", "GetBorderTextureDropdown", "GetClassColor",
    "GetFontOutlineFlag", "GetFontPath", "GetFontUseShadow", "GetPluginModuleKey",
    "GetProfileList", "GetProfilesDB", "InvalidateModulePageCache", "IsSearchPrebuild",
    "IsShown", "OpenPlugin", "PP", "PlaceBorderDividerV", "ProfileChangesFont",
    "ProfileChangesStyle", "ProfileChangesWindowSkins", "RefreshAllAddons", "RefreshPage",
    "RegisterOnHide", "RegisterOnShow", "RegisterPlugin", "ResolveTexturePath",
    "ShowConfirmPopup", "SwitchProfile",
}

-- The names in NEEDED that EllesmereUI lacks; empty when all are there.
function E.MissingAPI()
    local eui, missing = EUI(), {}
    for _, name in ipairs(NEEDED) do
        if not (eui and eui[name] ~= nil) then missing[#missing + 1] = name end
    end
    return missing
end

do
    local missing = E.MissingAPI()
    if #missing > 0 then
        ns.BlockModules(("EllesmereUI %s lacks %s. The modules stay off until ProseccoAdditions is updated for it.")
            :format(C_AddOns.GetAddOnMetadata("EllesmereUI", "Version") or "?", table.concat(missing, ", ")))
    end
end

-- Border on one of OUR frames. `px` = whole pixels at UIParent scale, the
-- unit of Ellesmere's Border Size sliders. Ellesmere's legacy `size` is a
-- step 1-4 for textured styles, so the exact size goes in as edgePx (15th
-- argument) with the nearest step beside it, as Ellesmere's slider writes it.
-- offX/offY: Ellesmere's Border Width/Height Offset for a textured style
-- (nil = the texture's default); a solid border ignores them.
function E.Border(frame, px, r, g, b, a, style, offX, offY)
    local eui = EUI()
    if px <= 0 then
        eui.ApplyBorderStyle(frame, 0, r, g, b, a, style)          -- 0 hides the border
        return
    end
    local step = eui.BorderPxStep(px, style)
    eui.ApplyBorderStyle(frame, step, r, g, b, a, style, offX, offY, nil, nil, nil, nil, nil, px)
end

-- A border style's horizontal seam art, the strip Ellesmere's unit frames
-- draw along the health/power join ("Power Bar Seam"); nil for a style
-- without it.
function E.BorderSeamArt(style)
    return EUI().GetBorderCompanion(style, "sepH")
end

-- The seam art's thickness for a border of `px` pixels, snapped at effective
-- scale es.
function E.BorderSeamThickness(style, px, es)
    local eui = EUI()
    return eui.BorderCompanionThickness(style, eui.BorderPxStep(px, style), px, es)
end

-- A border style's vertical seam on OUR texture `tex`, its line on the right
-- edge of OUR frame `anchor` and its art reaching right of it, as Ellesmere
-- lays an attached portrait's divider. False for a style without one.
function E.BorderSeamV(tex, anchor, style, px)
    local eui = EUI()
    if not eui.GetBorderCompanion(style, "sepV") then return false end
    eui.PlaceBorderDividerV(tex, anchor, false, true, style, eui.BorderPxStep(px, style), px,
        anchor:GetEffectiveScale())
    return true
end

-- Snap v to whole physical pixels at effective scale es.
function E.SnapForES(v, es)
    return EUI().PP.SnapForES(v, es)
end

-- True for a textured border style (not "solid"), the only kind with offsets.
function E.IsTexturedBorder(style)
    return style ~= nil and style ~= "" and style ~= "solid"
end

-- Ellesmere's own Border Width | Height Offset slider pair, as on its power
-- bar and damage meter pages. It shows the texture's default until moved and
-- writes nil when moved back onto it. No addonKey: the global per-texture
-- defaults, which E.Border gets. spec: getTex, getPx, getX, setX, getY, setY,
-- apply, plus cell fields (disabled, disabledTooltip). Only valid while
-- Ellesmere's options are loaded (our pages are built inside them).
function E.BorderOffsetCells(spec)
    local eui = EUI()
    return eui.BorderOffsetRowCfgs({
        getTex = spec.getTex,
        getStep = function() return eui.BorderPxStep(spec.getPx(), spec.getTex()) end,
        getSizeKey = function() return nil end,
        getPx = spec.getPx,
        getX = spec.getX, setX = spec.setX,
        getY = spec.getY, setY = spec.setY,
        apply = spec.apply,
        disabled = spec.disabled,
        disabledTooltip = spec.disabledTooltip,
        tooltip = "Moves the textured border's art out (higher) or in (lower) from the frame's edge.",
    })
end

-- Size and anchor offsets snapped to whole physical pixels, as Ellesmere's
-- PP.Size/PP.Point do for its own rows: an edge on half a pixel blurs.
function E.PixelSize(frame, w, h)
    EUI().PP.Size(frame, w, h)
end

-- PP.Point snaps the offset, but a frame pinned by its middle on an axis
-- (CENTER, or TOP/BOTTOM for x, LEFT/RIGHT for y) with an odd pixel count on
-- that axis still gets both edges on half pixels; Ellesmere moves such a
-- centre half a pixel too. Call after the size is set. Assumes the anchor
-- point sits on a whole pixel: true for the screen (Inferred), not for
-- every frame.
function E.PixelPoint(frame, point, rel, relPoint, x, y)
    local PP = EUI().PP
    local m = PP.mult
    x, y = PP.Scale(x), PP.Scale(y)
    local function odd(dim) return math.floor(dim / m + 0.5) % 2 == 1 end
    if not point:find("LEFT") and not point:find("RIGHT") and odd(frame:GetWidth()) then x = x + m / 2 end
    if not point:find("TOP") and not point:find("BOTTOM") and odd(frame:GetHeight()) then y = y + m / 2 end
    frame:SetPoint(point, rel, relPoint, x, y)
end

-- One physical pixel in `frame`'s own units: Ellesmere's PP.mult is one
-- pixel in UIParent units, and a frame with its own scale (RXP's Window
-- Scale) has other units.
function E.PixelUnit(frame)
    return EUI().PP.mult * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
end

-- Ellesmere's widget factory (Toggle, DualRow, SectionHeader ...). Only valid
-- inside buildPage, which Ellesmere runs after its options addon has loaded.
function E.Widgets()
    return EUI().Widgets
end

-- values, order for a border style dropdown: Ellesmere's styles plus every
-- LibSharedMedia border.
function E.BorderStyles()
    return EUI().GetBorderTextureDropdown()
end

-- opts: title, message, confirmText, onConfirm, onCancel, reload. With
-- reload = true the confirm button is the secure /reload click on Forever.
function E.Confirm(opts)
    EUI():ShowConfirmPopup(opts)
end

-- Ellesmere's own profiles in its order, for the spec profiles on our
-- Profiles page.
function E.ProfileNames()
    local order, profiles = EUI().GetProfileList()
    local out = {}
    for _, name in ipairs(order or {}) do
        if profiles and profiles[name] then out[#out + 1] = name end
    end
    return out
end

function E.HasProfile(name)
    local _, profiles = EUI().GetProfileList()
    return profiles ~= nil and profiles[name] ~= nil
end

-- Whether Ellesmere has spec profiles of its own: its spec handler and its
-- login pre-seed then switch Ellesmere too, and whichever runs last wins.
function E.HasOwnSpecProfiles()
    local sp = EUI().GetProfilesDB().specProfiles
    return type(sp) == "table" and next(sp) ~= nil
end

-- Switches Ellesmere to profile `name` the way its own spec handler does:
-- SwitchProfile, a synchronous RefreshAllAddons, and its reload popup when
-- the profile changes the font, window skins or style. `beforeRefresh` runs
-- between the two, so values written into the new profile are drawn by the
-- refresh. False when the profile is missing or already active.
function E.SwitchProfile(name, beforeRefresh)
    local eui = EUI()
    local _, profiles = eui.GetProfileList()
    local data = profiles and profiles[name]
    if not data or eui.GetActiveProfileName() == name then return false end
    local font = eui.ProfileChangesFont(data)
    local skins = eui.ProfileChangesWindowSkins(data)
    local style = eui.ProfileChangesStyle(data)
    eui.SwitchProfile(name)
    if beforeRefresh then beforeRefresh() end
    eui.RefreshAllAddons()
    if font or skins or style then
        eui:ShowConfirmPopup({
            title       = "Reload Required",
            message     = "Ellesmere profile \"" .. name .. "\" changes the "
                .. (font and "font" or skins and "window skins" or "style") .. ". A UI reload is needed to apply it.",
            confirmText = "Reload Now",
            cancelText  = "Later",
            reload      = true,
        })
    end
    return true
end

-- Our section in Ellesmere's options panel (its plugin API).
function E.RegisterPlugin(spec)
    if ns.ModulesBlocked() then return false end       -- RegisterPlugin may be among the missing
    return EUI().RegisterPlugin(ADDON, spec)
end

function E.OpenPlugin(moduleKey, pageName)
    return EUI().OpenPlugin(ADDON, moduleKey, pageName)
end

-- buildPage also runs in the search's hidden pre-build pass with a stub widget
-- factory; side effects (our own preview frames) are skipped then.
function E.IsSearchPrebuild()
    return EUI().IsSearchPrebuild()
end

-- Re-read the values of the visible page (no rebuild).
function E.RefreshPage()
    EUI():RefreshPage()
end

-- Rebuild the visible page, for rows whose layout depends on a value.
function E.RebuildPage()
    EUI():RefreshPage(true)
end

-- After a profile switch, reset or import: the cached pages hold labels built
-- from the old profile, so they are dropped and the visible page rebuilt.
function E.RebuildPages(moduleKeys)
    local eui = EUI()
    local active = eui:GetActiveModule()
    local ours = false
    for _, key in ipairs(moduleKeys) do
        local full = eui.GetPluginModuleKey(ADDON, key)
        if full then
            eui:InvalidateModulePageCache(full)
            if full == active then ours = true end
        end
    end
    if ours then eui:RefreshPage(true) end
end

-- Ellesmere's bar textures plus every SharedMedia statusbar texture, for a
-- background dropdown, built once (Ellesmere's append also picks up
-- textures registered later). Returns names, order; "none" = flat colour.
local barTex, barNames, barOrder
function E.BarTextures()
    if not barTex then
        local eui = EUI()
        barTex, barNames, barOrder = eui.BuildBarTextureTables(true)
        eui.AppendSharedMediaTextures(barNames, barOrder, nil, barTex)
        barNames.none = "None (flat colour)"   -- already first in Ellesmere's order
    end
    return barNames, barOrder
end

-- File path of a bar texture key, or nil for "none" or a texture that is gone.
function E.BarTexturePath(key)
    if key == nil or key == "none" then return nil end
    E.BarTextures()
    return EUI().ResolveTexturePath(barTex, key, nil)
end

-- Ellesmere's UI font and outline, so our labels match its look.
function E.Font()
    local eui = EUI()
    return eui.GetFontPath(), eui.GetFontOutlineFlag()
end

-- True when Ellesmere's global Outline Mode draws a drop shadow instead of
-- an outline (its modes "none" and "shadow").
function E.FontUseShadow()
    return EUI().GetFontUseShadow() == true
end

-- ---------------------------------------------------------------------------
-- Damage Meters (Modules/DamageMeter.lua). Only named frames and Ellesmere's
-- saved settings; nothing in EllesmereUI._ModuleNS or any other "_" field.
-- Checked against 9.3.9 (1424549).
-- ---------------------------------------------------------------------------

local DM_FOLDER = "EllesmereUIDamageMeters"
local DM_MAX_WINDOWS = 5            -- the meter's MAX_WINDOWS

-- Ellesmere's damage meter windows that exist now, EllesmereUIDMFrame1..5
-- (on Forever a window can also show the threat list: the same frame). A
-- window added after login is found on the next call. A closed or rebuilt
-- window keeps its global name but loses its parent (Ellesmere hides it and
-- sets its parent nil), so it is left out. A window built later under a
-- closed window's name (close 3, then New Window) cannot be reached by that
-- name: the global still points at the closed one.
-- FIELD RESULT 2026-10-10 (build 70338): after close + New Window,
-- EnumerateFrames found a shown EllesmereUIDMFrame3 that was not
-- _G.EllesmereUIDMFrame3. So when a name points at a closed window and fewer
-- windows are found than windowCount, every frame is searched once by name.
-- A search that comes up short is not repeated while the count and what is
-- found stay the same, so a click does not search every time.
local found = setmetatable({}, { __mode = "k" })    -- windows the search found
local failedFor                                     -- "count:found" of a search that came up short

local function SearchDMFrames()
    local f = EnumerateFrames()
    while f do
        -- Nameplates can be forbidden: their methods error from addon code.
        local n = not f:IsForbidden() and f:GetName()
        if n and n:match("^EllesmereUIDMFrame%d$") and f:GetParent() then found[f] = true end
        f = EnumerateFrames(f)
    end
end

local function CollectDMFrames()
    local out, seen, stale = {}, {}, false
    for i = 1, DM_MAX_WINDOWS do
        local f = _G["EllesmereUIDMFrame" .. i]
        if f and f:GetParent() then
            out[#out + 1] = f
            seen[f] = true
        elseif f then
            stale = true
        end
    end
    for f in pairs(found) do
        if not seen[f] and f:GetParent() then out[#out + 1] = f end
    end
    return out, stale
end

function E.DMFrames()
    local out, stale = CollectDMFrames()
    local want = E.DMWindowCount()
    if not (stale and #out < want) then
        failedFor = nil
    elseif want .. ":" .. #out ~= failedFor then
        SearchDMFrames()
        out = CollectDMFrames()
        failedFor = #out < want and (want .. ":" .. #out) or nil
    end
    return out
end

-- The active Ellesmere profile's damage meter settings: the table Ellesmere's
-- NewDB keeps in EllesmereUIDB.profiles[name].addons[folder], under .dm. nil
-- when the meter addon is not loaded.
local function DMSettings(profile)
    if not C_AddOns.IsAddOnLoaded(DM_FOLDER) then return nil end
    local db = _G.EllesmereUIDB
    local p = db and db.profiles and db.profiles[profile or EUI().GetActiveProfileName()]
    local addon = p and p.addons and p.addons[DM_FOLDER]
    return addon and type(addon.dm) == "table" and addon.dm or nil
end

-- The same for read-only use from a module (the preview).
function E.DMSettings(profile) return DMSettings(profile) end

-- How many damage meter windows Ellesmere builds (its saved windowCount),
-- 0 when the meter addon is not loaded.
function E.DMWindowCount()
    local c = DMSettings()
    if not c then return 0 end
    return math.max(1, tonumber(c.windowCount) or 1)
end

-- Forever Essentials' Threat Meter keeps account-wide settings in
-- EllesmereUIDB.threatMeter. ProseccoAdditions does not style it; the target stays
-- so the values once taken from it can be given back.
local function ThreatSettings(create)
    local db = _G.EllesmereUIDB
    if not (db and C_AddOns.IsAddOnLoaded("EllesmereUIForeverEssentials")) then return false end
    if create and type(db.threatMeter) ~= "table" then db.threatMeter = {} end
    return true, db.threatMeter
end

-- The active Ellesmere profile's chat settings (Modules/Chat.lua):
-- EllesmereUIDB.profiles[name].addons.EllesmereUIChat.chat. nil when the
-- chat addon is not loaded. Checked against 9.4 (3926028).
local CHAT_FOLDER = "EllesmereUIChat"
local function ChatSettings(profile)
    if not C_AddOns.IsAddOnLoaded(CHAT_FOLDER) then return nil end
    local db = _G.EllesmereUIDB
    local p = db and db.profiles and db.profiles[profile or EUI().GetActiveProfileName()]
    local addon = p and p.addons and p.addons[CHAT_FOLDER]
    return addon and type(addon.chat) == "table" and addon.chat or nil
end

-- The active Ellesmere profile's Quest Tracker settings: EllesmereUIDB
-- .profiles[name].addons.EllesmereUIQuestTracker.questTracker. nil when
-- Ellesmere's Quest Tracker is not loaded. Checked against 9.4 (c6e5240).
local QT_FOLDER = "EllesmereUIQuestTracker"
local function QTSettings(profile)
    if not C_AddOns.IsAddOnLoaded(QT_FOLDER) then return nil end
    local db = _G.EllesmereUIDB
    local p = db and db.profiles and db.profiles[profile or EUI().GetActiveProfileName()]
    local addon = p and p.addons and p.addons[QT_FOLDER]
    return addon and type(addon.questTracker) == "table" and addon.questTracker or nil
end

-- The active Ellesmere profile's minimap settings (Modules/Minimap.lua):
-- EllesmereUIDB.profiles[name].addons.EllesmereUIMinimap.minimap. nil when
-- Ellesmere's minimap is not loaded.
local MINIMAP_FOLDER = "EllesmereUIMinimap"
local function MinimapSettings(profile)
    if not C_AddOns.IsAddOnLoaded(MINIMAP_FOLDER) then return nil end
    local db = _G.EllesmereUIDB
    local p = db and db.profiles and db.profiles[profile or EUI().GetActiveProfileName()]
    local addon = p and p.addons and p.addons[MINIMAP_FOLDER]
    return addon and type(addon.minimap) == "table" and addon.minimap or nil
end

-- Ellesmere's target unit frame (a global name, no "_"), for the Target
-- Frame module's empty frame in its place; nil when its unit frames are not
-- loaded or its target frame source is Blizzard's or hidden (not spawned).
-- A secure frame we only read and anchor to, never change.
function E.TargetFrame()
    if not C_AddOns.IsAddOnLoaded("EllesmereUIUnitFrames") then return nil end
    return _G.EllesmereUIUnitFrames_Target
end

-- The target frame's border settings as one of our border tables, so our
-- frame gets the same border: Ellesmere draws it over the whole frame with
-- its unit frame settings borderSize/borderSizePx/borderTexture/borderColor/
-- borderAlpha and the texture offsets, in EllesmereUIDB.profiles[name]
-- .addons.EllesmereUIUnitFrames.target (a saved table leaves defaults out).
-- Its texture shift is not carried over: our border has none.
function E.TargetBorder()
    local db = _G.EllesmereUIDB
    local p = db and db.profiles and db.profiles[EUI().GetActiveProfileName()]
    local addon = p and p.addons and p.addons.EllesmereUIUnitFrames
    local t = addon and type(addon.target) == "table" and addon.target or {}
    local style = t.borderTexture or "solid"
    if style == "" then style = "solid" end
    local step = tonumber(t.borderSize) or 1
    local eui = EUI()
    -- Ellesmere's legacy size when no exact one is saved.
    local px = eui.BorderPx(t.borderSizePx, step, style) or eui.BorderLegacyPx(step, style)
    -- A textured border's offsets the user never set come from Ellesmere's
    -- unit frame defaults for the style and step, scaled to the exact edge;
    -- without them our border would take the texture's general defaults. The
    -- defaults' shift is dropped (Assumed: 0 for the styles in use).
    local ox, oy = tonumber(t.borderTextureOffset), tonumber(t.borderTextureOffsetY)
    if style ~= "solid" and px > 0 and (not ox or not oy) then
        local dox, doy = eui.GetBorderDefaults("unitframes", style, step)
        local map = eui.BORDER_EDGE_MAP
        local f = px * eui.PP.mult / ((map and (map[step] or map[1])) or 12)
        ox = ox or eui.PP.Snap(dox * f)
        oy = oy or eui.PP.Snap(doy * f)
    end
    local c = type(t.borderColor) == "table" and t.borderColor or {}
    return { style = style, size = px,
        color = string.format("%02X%02X%02X", (c.r or 0) * 255 + 0.5, (c.g or 0) * 255 + 0.5, (c.b or 0) * 255 + 0.5),
        alpha = tonumber(t.borderAlpha) or 1,
        offsetX = ox, offsetY = oy }
end

-- Ellesmere's player cast bar from Resource Bars, for Frame backgrounds'
-- empty cast bar: the frame it creates under a global name once the bar is
-- on (no "_"). Never hidden: idle, it is faded to alpha 0. Not secure; read
-- and anchored to, never changed. Settings: EllesmereUIDB.profiles[name]
-- .addons.EllesmereUIResourceBars.castBar (a saved table leaves defaults
-- out). nil when Resource Bars is not loaded or its Cast Bar is off.
local function CastBarSettings()
    if not C_AddOns.IsAddOnLoaded("EllesmereUIResourceBars") then return nil end
    local db = _G.EllesmereUIDB
    local p = db and db.profiles and db.profiles[EUI().GetActiveProfileName()]
    local addon = p and p.addons and p.addons.EllesmereUIResourceBars
    return addon and type(addon.castBar) == "table" and addon.castBar or {}
end

function E.PlayerCastBar()
    local cb = CastBarSettings()
    if not cb or cb.enabled == false then return nil end
    return _G.ERB_CastBarFrame
end

-- The cast bar's border (one of our border tables) and background colour,
-- as Ellesmere draws them (borderSize/borderSizePx/borderTexture/borderR-A,
-- offsets under the "resourcebars" defaults key, background bgR-A), and
-- whether Always Show keeps its empty bar on screen. The texture shift and
-- Extend Top/Bottom are not carried over: our border has none.
function E.CastBarLook()
    local cb = CastBarSettings() or {}
    local style = cb.borderTexture or "solid"
    if style == "" then style = "solid" end
    local step = tonumber(cb.borderSize) or 1
    local eui = EUI()
    local px = step > 0 and (eui.BorderPx(cb.borderSizePx, step, style) or eui.BorderLegacyPx(step, style)) or 0
    local ox, oy = tonumber(cb.borderTextureOffset), tonumber(cb.borderTextureOffsetY)
    if style ~= "solid" and px > 0 and (not ox or not oy) then
        local dox, doy = eui.GetBorderDefaults("resourcebars", style, step)
        local map = eui.BORDER_EDGE_MAP
        local f = px * eui.PP.mult / ((map and (map[step] or map[1])) or 12)
        ox = ox or eui.PP.Snap(dox * f)
        oy = oy or eui.PP.Snap(doy * f)
    end
    local border = { style = style, size = px,
        color = string.format("%02X%02X%02X", (tonumber(cb.borderR) or 0) * 255 + 0.5,
            (tonumber(cb.borderG) or 0) * 255 + 0.5, (tonumber(cb.borderB) or 0) * 255 + 0.5),
        alpha = tonumber(cb.borderA) or 1,
        offsetX = ox, offsetY = oy }
    local bg = { tonumber(cb.bgR) or 0, tonumber(cb.bgG) or 0, tonumber(cb.bgB) or 0, tonumber(cb.bgA) or 0.7 }
    return border, bg, cb.alwaysShow == true
end

-- The target frame's settings table (see E.TargetBorder), or an empty one.
local function TargetSettings()
    local db = _G.EllesmereUIDB
    local p = db and db.profiles and db.profiles[EUI().GetActiveProfileName()]
    local addon = p and p.addons and p.addons.EllesmereUIUnitFrames
    return addon and type(addon.target) == "table" and addon.target or {}
end

-- The parts of Ellesmere's target frame our empty frame copies: its power
-- bar (`Power`) and its portrait's backdrop (`Portrait.backdrop`, set for
-- every portrait mode). Each nil when the frame has none or hides it; read
-- and anchored to, never changed. They keep their place while the unit
-- watch hides the frame (Inferred).
function E.TargetParts()
    local t = E.TargetFrame()
    if not t then return nil, nil end
    local power = t.Power
    if not (power and power.IsShown and power:IsShown()) then power = nil end
    local portrait = t.Portrait
    local backdrop = type(portrait) == "table" and portrait.backdrop
    if not (backdrop and backdrop.IsShown and backdrop:IsShown()) then backdrop = nil end
    return power, backdrop
end

-- What else of the target frame's look the empty frame copies, from the
-- same settings:
--   powerAttached   the power bar sits above or below the health bar
--   powerSeam       Ellesmere's "Power Bar Seam" shows
--   powerAbove      the bar is above the health bar
--   healthBg        r, g, b, a of the health bar's background
--   powerBorder     a border table for a detached bar's own border, or nil
--   detached        the portrait is detached
--   roundPortrait   detached with a round shape (Circle, Pixels Circle)
--   portraitRight   the portrait is on the right
--   divider         the attached portrait's divider shows
function E.TargetLook()
    local t = TargetSettings()
    local pos = t.powerPosition or "below"
    local look = {}
    look.powerAttached = pos == "below" or pos == "above"
    look.powerAbove = pos == "above"
    look.powerSeam = t.borderPowerSeam == true and look.powerAttached and (tonumber(t.borderSize) or 1) > 0
    local psize = tonumber(t.powerBorderSize) or 0
    if not look.powerAttached and psize > 0 then
        local style = t.powerBorderStyle or "solid"
        local pc = type(t.powerBorderColor) == "table" and t.powerBorderColor or {}
        look.powerBorder = { style = style,
            size = EUI().BorderPx(t.powerBorderSizePx, psize, style) or EUI().BorderLegacyPx(psize, style),
            color = string.format("%02X%02X%02X", (pc.r or 0) * 255 + 0.5, (pc.g or 0) * 255 + 0.5, (pc.b or 0) * 255 + 0.5),
            alpha = tonumber(t.powerBorderAlpha) or 1,
            offsetX = tonumber(t.powerBorderOffsetX), offsetY = tonumber(t.powerBorderOffsetY) }
    end
    -- The health bar's background with no unit to colour it: its Bar
    -- Background colour at its opacity. A background coloured by the unit's
    -- class has no unit here and takes that colour too.
    local hb = type(t.customBgColor) == "table" and t.customBgColor or { r = 0.067, g = 0.067, b = 0.067 }
    look.healthBg = { hb.r or 0, hb.g or 0, hb.b or 0, (tonumber(t.customBgAlpha) or 100) / 100 }
    look.detached = (t.portraitStyle or "attached") == "detached"
    local shape = t.detachedPortraitShape or "portrait"
    look.roundPortrait = look.detached and (shape == "circle" or shape == "pixelsCircle")
    -- An attached portrait on top is laid on the right, as Ellesmere does.
    look.portraitRight = (t.portraitSide or "right") ~= "left"
    look.divider = t.portraitSeparator == true and not look.detached
    return look
end

-- A detached portrait's shape on OUR frame `box` (as large as Ellesmere's
-- backdrop): its background, mask and ring, laid as Ellesmere lays them: the
-- mask 1 px in when the ring shows, the ring art (natively 7 px) grown by
-- 7 - size past the box and clipped by the mask, except Pixels Circle, whose
-- ring lies outside the mask 4 px further in. The ring has Ellesmere's set
-- colour, or `ringHex` ("RRGGBB") when given. Pixels Circle is drawn grey
-- (see below). Our textures: box.bg, box.mask, box.ring, box.ringBase,
-- box.ringMask (ringBase is masked by ringMask).
function E.ShapePortrait(box, ringHex)
    local t = TargetSettings()
    local eui = EUI()
    local shape = t.detachedPortraitShape or "portrait"
    local maskPath = shape ~= "none" and eui.SHAPE_MASKS and eui.SHAPE_MASKS[shape]
    local ringPath = eui.SHAPE_BORDERS and eui.SHAPE_BORDERS[shape]
    local size = tonumber(t.detachedPortraitBorderSize) or 7
    -- Ellesmere always shows the ring; at size 0 the mask clips it away,
    -- except Pixels Circle's, which is outside the mask.
    local showRing = ringPath and (size > 0 or shape == "pixelsCircle")
    box.ringBase:Hide()
    local PP = eui.PP
    box.bg:SetShown(shape ~= "none")
    -- Removing a mask a texture does not have may error (Ellesmere pcalls
    -- it), so which masks are on is kept on the box (ours).
    if box.bgMasked then box.bg:RemoveMaskTexture(box.mask) box.bgMasked = false end
    if box.ringMasked then box.ring:RemoveMaskTexture(box.mask) box.ringMasked = false end
    local unmasked = shape == "pixelsCircle"
    if maskPath then
        box.mask:ClearAllPoints()
        if size >= 1 then
            PP.Point(box.mask, "TOPLEFT", box, "TOPLEFT", 1, -1)
            PP.Point(box.mask, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
        else
            box.mask:SetAllPoints(box)
        end
        box.mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        box.bg:AddMaskTexture(box.mask)
        box.bgMasked = true
    end
    if not showRing then box.ring:Hide() return end
    local off = (7 - size) - (unmasked and 4 or 0)
    box.ring:ClearAllPoints()
    PP.Point(box.ring, "TOPLEFT", box, "TOPLEFT", -off, off)
    PP.Point(box.ring, "BOTTOMRIGHT", box, "BOTTOMRIGHT", off, -off)
    if maskPath and not unmasked then
        box.ring:AddMaskTexture(box.mask)
        box.ringMasked = true
    end
    box.ring:SetTexture(ringPath)
    -- Always the set colour, never the class colour.
    local bc = type(t.detachedPortraitBorderColor) == "table" and t.detachedPortraitBorderColor or {}
    local r, g, b = bc.r or 0, bc.g or 0, bc.b or 0
    if ringHex then r, g, b = ns.HexToRGB(ringHex) end
    local a = (tonumber(t.detachedPortraitBorderOpacity) or 100) / 100
    if unmasked then
        -- Pixels Circle in grey: its black becomes 112 and its white 162.
        -- A flat 112 cut out by the ring's own alpha, with the ring added
        -- on top at 50/255, gives 112 + 50 * texel without shipping an
        -- edited copy of Ellesmere's art.
        box.ringMask:ClearAllPoints()
        box.ringMask:SetAllPoints(box.ring)
        box.ringMask:SetTexture(ringPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        box.ringBase:ClearAllPoints()
        box.ringBase:SetAllPoints(box.ring)
        box.ringBase:SetColorTexture(r * 112 / 255, g * 112 / 255, b * 112 / 255, a)
        box.ringBase:Show()
        box.ring:SetBlendMode("ADD")
        box.ring:SetVertexColor(r * 50 / 255, g * 50 / 255, b * 50 / 255, a)
    else
        box.ring:SetBlendMode("BLEND")
        box.ring:SetVertexColor(r, g, b, a)
    end
    box.ring:Show()
end

-- The outer ring's art for its setting, as Ellesmere picks it.
local function OuterRingPath(key, frameTex)
    local GBC = EUI().GetBorderCompanion
    if key == "border" then return GBC(frameTex, "ring") end
    if key == "pixels" or key == "pixels-textured" then return GBC(key, "ring") end
    if key == "pixels-shadow" then return GBC("pixels", "ringShadow") end
    if key == "pixels-textured-shadow" then return GBC("pixels-textured", "ringShadow") end
    if key == "thin-border" then return "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_ring_thin_border.tga" end
    return nil
end

-- A round detached portrait's Outer Ring and Inner Shadow on OUR frame
-- `box`, laid as Ellesmere's: the ring Outer Ring Size percent of the box,
-- less 4 px, tinted with the frame border's colour or `outerHex`; the shadow
-- over the box under the shape ring, masked by the shape.
function E.PortraitExtras(box, outerHex)
    local t = TargetSettings()
    local shape = t.detachedPortraitShape or "portrait"
    local round = shape == "circle" or shape == "pixelsCircle"
    local path = round and OuterRingPath(t.detachedPortraitOuterRing or "none", t.borderTexture or "solid")
    if path then
        local scale = tonumber(t.detachedPortraitOuterRingScale) or 118
        local w, h = box:GetWidth(), box:GetHeight()
        if w < 1 then w = 46 end
        if h < 1 then h = 46 end
        local ext = (scale - 100) / 200
        local ox, oy = w * ext - 4, h * ext - 4
        local PP = EUI().PP
        box.outer:SetTexture(path)
        box.outer:ClearAllPoints()
        PP.Point(box.outer, "TOPLEFT", box, "TOPLEFT", -ox, oy)
        PP.Point(box.outer, "BOTTOMRIGHT", box, "BOTTOMRIGHT", ox, -oy)
        local bc = type(t.borderColor) == "table" and t.borderColor or {}
        local r, g, b = bc.r or 0, bc.g or 0, bc.b or 0
        if outerHex then r, g, b = ns.HexToRGB(outerHex) end
        box.outer:SetVertexColor(r, g, b, tonumber(t.borderAlpha) or 1)
        box.outer:Show()
    else
        box.outer:Hide()
    end
    if round and t.detachedPortraitInnerShadow then
        box.shadow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_inner_shadow.tga")
        box.shadow:SetAllPoints(box)
        if box.bgMasked and not box.shadowMasked then
            box.shadow:AddMaskTexture(box.mask)
            box.shadowMasked = true
        end
        box.shadow:Show()
    else
        box.shadow:Hide()
    end
end

-- An attached portrait's backdrop on OUR frame `box`: the grey square with
-- no shape (Ellesmere drops the mask and ring when not detached).
function E.SquarePortrait(box)
    if box.bgMasked then box.bg:RemoveMaskTexture(box.mask) box.bgMasked = false end
    if box.ringMasked then box.ring:RemoveMaskTexture(box.mask) box.ringMasked = false end
    box.bg:Show()
    box.ring:Hide()
    box.ringBase:Hide()
end

-- The attached portrait's divider on OUR texture `tex`, on the inner edge of
-- `box` (Ellesmere's backdrop, only anchored to), placed as Ellesmere's
-- PlaceBorderDividerV, in the border's colour or `hex`. A solid border has
-- no divider art.
function E.PortraitDivider(tex, box, right, hex)
    local t = TargetSettings()
    local style = t.borderTexture or "solid"
    local step = tonumber(t.borderSize) or 1
    local eui = EUI()
    if style == "solid" or step <= 0 or not eui.GetBorderCompanion(style, "sepV") then tex:Hide() return end
    local c = type(t.borderColor) == "table" and t.borderColor or {}
    local r, g, b = c.r or 0, c.g or 0, c.b or 0
    if hex then r, g, b = ns.HexToRGB(hex) end
    tex:SetVertexColor(r, g, b, tonumber(t.borderAlpha) or 1)
    eui.PlaceBorderDividerV(tex, box, right, true, style, step, eui.BorderPx(t.borderSizePx, step, style),
        box:GetEffectiveScale())
end

-- What our panels need of Ellesmere's map: its shape and its border's
-- thickness in pixels; nil when Ellesmere's minimap is not loaded. The
-- rectangular shape shows the middle 192/256 of the square Minimap, and the
-- border lies inside that rectangle. Defaults as Ellesmere's.
function E.MinimapLook()
    local c = MinimapSettings()
    if not c then return nil end
    local shape = c.shape or "square"
    -- Blizzard Style and Classic Style draw Blizzard's ring and top bar
    -- instead of Ellesmere's border: no straight bordered edge to join, so
    -- the panels keep their gap as on a round map.
    local stock = c.useBlizzardStyle == true or c.useClassicStyle == true
    local size = tonumber(c.borderSize) or 1
    local px = EUI().BorderPx(c.borderSizePx, size, c.borderTexture or "solid") or size
    return { shape = shape, borderPx = px, rectangular = shape == "rectangular",
        round = stock or shape == "circle" or shape == "textured_circle" }
end

-- How far the rectangular map's visible part lies inside the square
-- Minimap frame, top and bottom, in the map's units snapped to `u` (one
-- pixel); 0 for the other shapes. The middle 192/256 (MinimapLook), 2 px
-- further in:
-- FIELD RESULT 2026-10-12 (dev49): with the plain inset a 1-2 px strip of
-- empty map showed between our panels and the map (the edge of Ellesmere's
-- rectangular mask is not fully opaque).
function E.MinimapInset(look, h, u)
    if not look.rectangular then return 0 end
    local Snap = ns.Border.Snap
    return Snap(h * 32 / 256, u) + 2 * u
end

-- Whether Ellesmere's Quest Tracker is loaded, which is what hides
-- Blizzard's tracker once its Visibility is "never".
function E.QuestTrackerLoaded()
    return C_AddOns.IsAddOnLoaded(QT_FOLDER)
end

-- An owned setting is { target = "damageMeters" | "threatMeter" | "chat" |
-- "questTracker" | "minimap", key = "a.b.c" }. All but the Threat Meter's
-- belong to one Ellesmere profile, so they carry its name; the Threat
-- Meter's are account-wide (profile = nil).
function E.OwnedProfile(target)
    if target == "damageMeters" or target == "chat" or target == "questTracker" or target == "minimap" then
        return EUI().GetActiveProfileName()
    end
    return nil
end

-- available, table. available = false when the addon (or the profile) is
-- missing, so there is nothing to read or write.
local function Root(target, profile, create)
    if target == "damageMeters" then
        local t = DMSettings(profile)
        return t ~= nil, t
    elseif target == "chat" then
        local t = ChatSettings(profile)
        return t ~= nil, t
    elseif target == "questTracker" then
        local t = QTSettings(profile)
        return t ~= nil, t
    elseif target == "minimap" then
        local t = MinimapSettings(profile)
        return t ~= nil, t
    elseif target == "threatMeter" then
        return ThreatSettings(create)
    end
    error("ProseccoAdditions: unknown Ellesmere target " .. tostring(target))
end

-- Returns available, value (nil = not set, Ellesmere uses its default).
function E.ReadOwned(target, profile, key)
    local ok, t = Root(target, profile, false)
    if not ok then return false end
    for part in key:gmatch("[^%.]+") do
        if type(t) ~= "table" then return true, nil end
        t = t[part]
    end
    return true, t
end

-- Writes value (nil removes it, so Ellesmere's default applies again),
-- creating tables on the way. False when there is nowhere to write.
-- Ellesmere reads these values when it builds its windows, so a change
-- shows after a /reload.
function E.WriteOwned(target, profile, key, value)
    local ok, t = Root(target, profile, true)
    if not ok then return false end
    local parts = {}
    for part in key:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
        t = t[parts[i]]
    end
    t[parts[#parts]] = value
    return true
end

for _, target in ipairs({ "damageMeters", "threatMeter", "chat", "questTracker", "minimap" }) do
    ns.RegisterOwner(target, E)
end

-- Whether Ellesmere's options panel is open.
function E.MenuShown()
    return EUI():IsShown() == true
end

-- The fixed header above the page being built (a preview): builder is
-- (headerFrame, width) -> height. Ellesmere's own preview pages call
-- SetContentHeader from their page builder. Not in the plugin API, so
-- Assumed; a renamed one errors visibly in the page build.
function E.SetPageHeader(builder)
    EUI():SetContentHeader(builder)
end

-- New height for that header after a change. While the left button is down
-- (a slider dragged further down the page) the rows scroll with the change
-- so the slider stays under the mouse; otherwise (a toggle, the panel
-- opening) the rows just move, as in Ellesmere's own previews, so the top of
-- the page stays in view.
function E.SetContentHeaderHeight(h)
    if IsMouseButtonDown("LeftButton") then
        EUI():UpdateContentHeaderHeight(h)
    else
        EUI():SetContentHeaderHeightSilent(h)
    end
end

-- Calls fn every time Ellesmere's options panel opens (its RegisterOnShow,
-- a registration, not a hook). Registered once per fn; fn gates on its own
-- state.
local menuShownFns = {}
function E.OnMenuShown(fn)
    for _, f in ipairs(menuShownFns) do
        if f == fn then return end
    end
    menuShownFns[#menuShownFns + 1] = fn
    if #menuShownFns == 1 then
        EUI():RegisterOnShow(function()
            for _, f in ipairs(menuShownFns) do xpcall(f, ns.ErrorHandler("ellesmere:menuShown")) end
        end)
    end
end

-- Calls fn every time Ellesmere's options panel closes: Escape, its X, or
-- combat closing it (its RegisterOnHide). It cannot be undone, so each fn is
-- registered once and gates on its own state.
local menuClosedFns = {}
function E.OnMenuClosed(fn)
    for _, f in ipairs(menuClosedFns) do
        if f == fn then return end
    end
    menuClosedFns[#menuClosedFns + 1] = fn
    if #menuClosedFns == 1 then
        EUI():RegisterOnHide(function()
            -- Ellesmere's loop has no pcall: an error of ours would stop
            -- the other registrants' callbacks.
            for _, f in ipairs(menuClosedFns) do xpcall(f, ns.ErrorHandler("ellesmere:menuClosed")) end
        end)
    end
end

-- Ellesmere's flat micro menu icons, white PNGs its Data Bars tint. They
-- ship in EllesmereUI itself (a dependency), so they are there whether or
-- not the Data Bars addon is on. `name` without folder or extension.
function E.MicroMenuIcon(name)
    return "Interface\\AddOns\\EllesmereUI\\media\\micromenu\\" .. name .. ".png"
end

-- Whole physical pixels in UIParent units (padding is set in pixels, like
-- the border size).
function E.Pixels(n)
    return EUI().PP.Scale((tonumber(n) or 0) * EUI().PP.mult)
end

local BAR_FALLBACK = "Interface\\Buttons\\WHITE8X8"     -- the damage meter's BAR_TEX
local THIN_LINE = { ["thin-line-top"] = true, ["thin-line-bottom"] = true }

-- What the test bars need to look like Ellesmere's damage meter rows, read
-- from the damage meter settings (defaults as Ellesmere's) and Ellesmere's
-- public font, texture and colour functions. nil when the meter addon is not
-- loaded.
function E.DMBarStyle()
    local c = DMSettings()
    if not c then return nil end
    local eui = EUI()
    local s = {}
    -- Texture: the meter adds "blizzard" to the shared list; the thin-line
    -- styles draw a 1 px line, here a flat bar (Unverified look).
    local key = c.barTexture or "atrocity"
    if key == "blizzard" then
        s.texture = "Interface\\TargetingFrame\\UI-StatusBar"
    elseif THIN_LINE[key] then
        s.texture = BAR_FALLBACK
    else
        E.BarTextures()
        s.texture = eui.ResolveTexturePath(barTex, key, BAR_FALLBACK)
    end
    -- Bar height and spacing on one pixel grid, as the meter's RowMetrics.
    local es = UIParent:GetEffectiveScale()
    local PP = eui.PP
    s.barH = PP.SnapForES(c.barHeight or 18, es)
    s.barSp = PP.SnapForES(c.barSpacing or 2, es)
    s.leftSize = c.leftFontSize or c.fontSize or 11
    s.rightSize = c.rightFontSize or c.fontSize or 11
    s.headerH = c.hdrHeight or 22
    s.iconStyle = c.iconStyle or "spec"
    s.iconZoom = tonumber(c.classIconZoom) or 0.06
    s.showIcon = s.iconStyle ~= "none"
    -- The row border and the icon border, defaults as the meter's.
    s.borderSize = tonumber(c.borderSize) or 0
    s.borderStyle = c.borderTexture or "solid"
    -- *SizePx is Ellesmere's packed "px|step|tex"; its exact size counts only
    -- while it pairs with the size and texture, else the step.
    s.borderPx = EUI().BorderPx(c.borderSizePx, s.borderSize, s.borderStyle) or s.borderSize
    s.borderFollowFill, s.borderFollowIcon = c.borderFollowFill == true, c.borderFollowFillIcon == true
    s.borderR, s.borderG, s.borderB, s.borderA = c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1
    s.iconBorder = c.customIconBorder == true and (tonumber(c.iconBorderSize) or 0) > 0
    s.iconBorderStyle = c.iconBorderTexture or "solid"
    local iconSize = tonumber(c.iconBorderSize) or 0
    s.iconBorderPx = EUI().BorderPx(c.iconBorderSizePx, iconSize, s.iconBorderStyle) or iconSize
    s.iconBorderR, s.iconBorderG, s.iconBorderB, s.iconBorderA =
        c.iconBorderR or 0, c.iconBorderG or 0, c.iconBorderB or 0, c.iconBorderA or 1
    s.classColor = c.showClassColor ~= false
    if c.barColorUseAccent ~= false then
        local a = eui.ELLESMERE_GREEN
        s.barR, s.barG, s.barB = a.r, a.g, a.b
    else
        local bc = c.barColor or {}
        s.barR, s.barG, s.barB = bc.r or 0.35, bc.g or 0.55, bc.b or 0.8
    end
    s.fillAlpha = c.barFillAlpha or 1
    s.trackR, s.trackG, s.trackB, s.trackA = c.barBgR or 0, c.barBgG or 0, c.barBgB or 0, c.barBgAlpha or 0
    s.trackClass = c.barBgUseClassColor == true
    s.leftClass, s.rightClass = c.leftTextUseClassColor == true, c.rightTextUseClassColor == true
    local lc, rc = c.leftTextColor or {}, c.rightTextColor or {}
    s.leftR, s.leftG, s.leftB = lc.r or 1, lc.g or 1, lc.b or 1
    s.rightR, s.rightG, s.rightB = rc.r or 1, rc.g or 1, rc.b or 1
    s.hideNumbers = c.hideNumbers == true
    s.leftX, s.leftY = tonumber(c.leftTextOffsetX) or 0, tonumber(c.leftTextOffsetY) or 0
    s.rightX, s.rightY = tonumber(c.rightTextOffsetX) or 0, tonumber(c.rightTextOffsetY) or 0
    return s
end

-- A test bar's class icon in the damage meter's Icon Style, as its rows set
-- theirs. A test row has no spec, so "spec" shows the class icon, as
-- Ellesmere does for a row without one. The sprite styles are Ellesmere's
-- own files and its public coordinate table. False when there is nothing to
-- show.
local CLASS_SPRITES = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local function Zoom(u1, u2, v1, v2, z)
    local du, dv = (u2 - u1) * z, (v2 - v1) * z
    return u1 + du, u2 - du, v1 + dv, v2 - dv
end
function E.DMClassIcon(tex, class, style, zoom)
    if style == "none" then return false end
    if style == "spec" or style == "blizzard" then
        local co = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if not co then return false end
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        tex:SetTexCoord(Zoom(co[1], co[2], co[3], co[4], zoom))
        return true
    end
    local sprites = EUI().CLASS_ICON_SPRITE_COORDS
    local co = type(sprites) == "table" and sprites[class]
    if not co then return false end
    tex:SetTexture(CLASS_SPRITES .. style .. ".tga")
    tex:SetTexCoord(co[1], co[2], co[3], co[4])
    return true
end

-- A test bar's row border and icon border as Ellesmere draws them on its
-- rows: Follow Fill draws four plain strips from the row's (with Include
-- Icon, the icon's) left edge to the fill's end, always solid; otherwise its
-- border style round the whole row; the icon border round the icon. Drawn
-- on frames of ours, children of the test row, kept in a weak table. A
-- mirror of Ellesmere's row look, not one of ProseccoAdditions's borders.
local rowParts = setmetatable({}, { __mode = "k" })
function E.DMRowBorder(row, fill, icon, s)
    local p = rowParts[row]
    if not p then
        p = {}
        p.full = CreateFrame("Frame", nil, row)
        p.full:SetAllPoints(row)
        p.strips = CreateFrame("Frame", nil, row)
        p.strips:SetPoint("TOPLEFT", row, "TOPLEFT")
        p.strips:SetSize(1, 1)      -- inert; the strips carry the shape, as Ellesmere's
        for _, k in ipairs({ "top", "bottom", "left", "right" }) do p[k] = p.strips:CreateTexture(nil, "OVERLAY") end
        p.icon = CreateFrame("Frame", nil, row)
        p.icon:SetAllPoints(icon)
        rowParts[row] = p
    end
    local lv = row:GetFrameLevel()
    p.full:SetFrameLevel(lv + 3)
    p.strips:SetFrameLevel(lv + 3)
    p.icon:SetFrameLevel(lv + 6)
    local sz = s.borderSize
    if sz > 0 and s.borderFollowFill then
        p.full:Hide()
        local ft = fill:GetStatusBarTexture()
        local left = s.borderFollowIcon and row or fill
        for _, k in ipairs({ "top", "bottom", "left", "right" }) do
            p[k]:SetColorTexture(s.borderR, s.borderG, s.borderB, s.borderA)
            p[k]:ClearAllPoints()
        end
        p.top:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
        p.top:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, 0)
        p.top:SetHeight(sz)
        p.bottom:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 0)
        p.bottom:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, 0)
        p.bottom:SetHeight(sz)
        p.left:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -sz)
        p.left:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, sz)
        p.left:SetWidth(sz)
        p.right:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, -sz)
        p.right:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, sz)
        p.right:SetWidth(sz)
        p.strips:Show()
    elseif sz > 0 then
        p.strips:Hide()
        E.Border(p.full, s.borderPx, s.borderR, s.borderG, s.borderB, s.borderA, s.borderStyle)
        p.full:Show()
    else
        p.strips:Hide()
        p.full:Hide()
    end
    if s.iconBorder and icon:IsShown() then
        E.Border(p.icon, s.iconBorderPx, s.iconBorderR, s.iconBorderG, s.iconBorderB, s.iconBorderA, s.iconBorderStyle)
        p.icon:Show()       -- ApplyBorderStyle shows its target too
    else
        p.icon:Hide()
    end
end

-- A test bar's text in the damage meter's font, outline and shadow, the way
-- its rows set theirs.
function E.DMFont(fs, size)
    EUI().ApplyModuleFont(fs, nil, size, "damageMeters")
end

-- Ellesmere's Header Height (Damage Meters > Header, UI units). On the
-- EllesmereUI look the header is exactly this tall, the rows start right
-- under it and the title and buttons are centred in it. nil when not loaded.
function E.DMHeaderHeight()
    local c = DMSettings()
    return c and (tonumber(c.hdrHeight) or 22)
end

-- Ellesmere's header background colour and opacity (Damage Meters >
-- Header; default 1B1B1B at 1).
function E.DMHeaderBg()
    local c = DMSettings()
    if not c then return nil end
    local hc = c.hdrBgColor
    return hc and hc.r or 0x1B / 255, hc and hc.g or 0x1B / 255, hc and hc.b or 0x1B / 255,
        tonumber(c.hdrBgAlpha) or 1
end

-- The damage meter header's button icons, right to left as Ellesmere lays
-- them out (settings, segment, meter type, reset, new window), and their
-- tint: Ellesmere's own media files for its EllesmereUI look (the stock
-- looks swap in other art). The file names are Assumed: a renamed file
-- shows empty.
local DM_MEDIA = "Interface\\AddOns\\" .. DM_FOLDER .. "\\Media\\"
function E.DMHeaderIcons()
    local c = DMSettings()
    if not c then return nil end
    local icons = { "dm_settings.png", "dm_sheet.png", "dm_home_damage.png" }
    if c.hideResetButton ~= true then icons[#icons + 1] = "dm_undo.png" end
    icons[#icons + 1] = "dm_open.png"
    for i, f in ipairs(icons) do icons[i] = DM_MEDIA .. f end
    local r, g, b = 1, 1, 1
    if c.iconColorUseAccent == true then
        local a = EUI().ELLESMERE_GREEN
        if a then r, g, b = a.r, a.g, a.b end
    elseif type(c.iconColor) == "table" then
        r, g, b = c.iconColor.r or 1, c.iconColor.g or 1, c.iconColor.b or 1
    end
    return icons, r, g, b, 0.4      -- ICON_ALPHA, the idle look
end

-- True when the damage meter uses one of Ellesmere's stock looks (Global
-- Settings > Style), which draw their own window art.
function E.DMStockStyle()
    local c = DMSettings()
    return c ~= nil and (c.useBlizzardStyle == true or c.useClassicStyle == true)
end

-- Ellesmere's class colour (custom colours and darkening included).
function E.ClassColor(token)
    local cc = EUI().GetClassColor(token)
    return cc.r, cc.g, cc.b
end

-- Ellesmere's number abbreviation.
function E.Abbreviate(n)
    return EUI().AbbreviateNumber(n)
end

-- ---------------------------------------------------------------------------
-- Chat (Modules/Chat.lua). Only Ellesmere's saved chat settings are read
-- here; every chat frame Ellesmere draws is anonymous, so the module places
-- its frames by Blizzard's named ChatFrame1 and GeneralDockManager.
-- Checked against 9.4 (3926028).
-- ---------------------------------------------------------------------------

-- True when the chat uses Blizzard Style or Classic WoW UI (Chat > Style),
-- which draw Blizzard's own frame art and ignore Background Opacity.
function E.ChatStockStyle()
    local c = ChatSettings()
    return c ~= nil and (c.useBlizzardStyle == true or c.useClassicStyle == true)
end

-- Height of Ellesmere's tabs (Chat > Tabs > Tab Height, UI units): its tabs
-- stand on the bottom edge of Blizzard's tab row at this height. nil when
-- the chat addon is not loaded. The EllesmereUI style only: Classic and the
-- Forever variant use 32 and 28.
function E.ChatTabHeight()
    local c = ChatSettings()
    return c and (tonumber(c.tabHeight) or 24)
end

-- The chat addon's version string from its .toc (Modules/Chat.lua gates the
-- tab-row fix on it); nil when it is not loaded.
function E.ChatVersion()
    if not C_AddOns.IsAddOnLoaded(CHAT_FOLDER) then return nil end
    return C_AddOns.GetAddOnMetadata(CHAT_FOLDER, "Version")
end
