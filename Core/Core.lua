-- ProseccoAdditions / Core / Core.lua
-- The SavedVariables table, profiles, ns.Apply(), export/import and /prosecco.
--
-- ns.db IS the active profile table (ProseccoAdditionsDB.profiles[name]); a profile
-- switch points it at another table and runs ns.Apply(). Nothing holds a
-- copy, and code reads ns.db at call time, never from an upvalue: a switch,
-- reset or import replaces the table.
--
-- ProseccoAdditionsDB = {
--   version = 1,
--   activeProfile = { ["Name - Realm"] = "Default" },  -- per character
--   profiles = { Default = { global = { border = {...} },
--                            modules = { <key> = {...} } } },
--   log = { enabled, lines },            -- Core/Log.lua; outside the profiles
--   owned = { <module key> = { ... } },  -- ns.OwnedStore; outside the profiles
--   chars = { ["Name - Realm"] = { login = time(), modules = { <key> = {...} },
--     specProfiles = { [1] = { proseccoui, ellesmere }, [2] = {...} } } },
--                     -- ns.CharStore, ns.LoginStamp, spec profiles
--   welcomed = true,  -- the first-start chat line was shown (account-wide)
-- }

local ADDON, ns = ...

ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
ns.db = nil                     -- the active profile; set at PLAYER_LOGIN

local DB_VERSION = 1
local DEFAULT_PROFILE = "Default"

local GLOBAL_DEFAULTS = {
    border = { style = "solid", size = 1, color = "000000", alpha = 1 },
    -- The colours of module boxes with "Use Global Background" on:
    -- `background` for bodies, `headerBackground` for header and title boxes.
    -- Defaults: Ellesmere's own window and header colours.
    background = { color = "000000", alpha = 0.75 },
    headerBackground = { color = "1B1B1B", alpha = 1 },
    -- An Ellesmere bar texture under every header colour, or "none" for a
    -- flat colour. Painted through ns.PaintHeader.
    headerTexture = "none",
    -- The font of modules set to "Global font" / "Global outline": face "" =
    -- Ellesmere's font, outline a mode of ns.Media.Outline.
    font = { face = "", outline = "ellesmere" },
    -- The Microbar in place of the Minimap's bottom panel, with the clock and
    -- FPS/MS as a badge on the map. Here because both modules read it, and a
    -- module never reads another's.
    microbarOnMinimap = false,
}

function ns.Print(msg)
    print("|cff66ccffProseccoAdditions|r: " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- "RRGGBB" (with or without '#') -> r, g, b in 0..1. Anything else is black,
-- so a hand-edited SavedVariables value cannot break a border.
function ns.HexToRGB(hex)
    local s = tostring(hex or ""):gsub("#", "")
    if not s:match("^%x%x%x%x%x%x$") then s = "000000" end
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end

function ns.RGBToHex(r, g, b)
    local function byte(v) return math.floor(math.max(0, math.min(1, v or 0)) * 255 + 0.5) end
    return ("%02X%02X%02X"):format(byte(r), byte(g), byte(b))
end

-- A module box's colour: its own (hex, alpha), or the global one of `kind`
-- ("background" or "headerBackground") when `follow` is true.
function ns.BackgroundColor(follow, kind, hex, alpha)
    if follow then
        local g = ns.db.global[kind]
        return g.color, tonumber(g.alpha) or 1
    end
    return hex, alpha
end

-- Paints our header texture `tex` in r, g, b, a: the Global Header
-- Texture tinted by the colour, or the flat colour. Every header, title and
-- badge box in the addon goes through here, whatever its colour.
function ns.PaintHeader(tex, r, g, b, a)
    local path = ns.Ellesmere.BarTexturePath(ns.db.global.headerTexture)
    if path then
        tex:SetTexture(path)
        tex:SetVertexColor(r, g, b, a)
    else
        tex:SetVertexColor(1, 1, 1, 1)      -- a tint left from a texture would darken the colour
        tex:SetColorTexture(r, g, b, a)
    end
end

-- Lays cells out two per row, skipping nil (a row hidden while it follows
-- a global value, see BackgroundCell); an odd one gets an empty right
-- half. Returns the new y.
function ns.Rows(W, parent, y, ...)
    local cells = {}
    for i = 1, select("#", ...) do
        local c = select(i, ...)
        if c then cells[#cells + 1] = c end
    end
    for i = 1, #cells, 2 do
        local _, h = W:DualRow(parent, y, cells[i], cells[i + 1] or { type = "spacer" })
        y = y - h
    end
    return y
end

-- A colour picker for one module box, or nil while the module follows the
-- global colour: the row is hidden then, not greyed (the Use Global
-- Background toggle rebuilds the page). Lay it out with ns.Rows. spec: text,
-- tooltip, cfg (function returning the table holding colorKey/alphaKey),
-- colorKey, alphaKey (nil: no alpha), default (alpha), follows (function),
-- onChange, and optional disabled/disabledTooltip of the row itself.
function ns.BackgroundCell(spec)
    if spec.follows() then return nil end
    return { type = "colorpicker", text = spec.text, tooltip = spec.tooltip, hasAlpha = spec.alphaKey ~= nil,
        disabled = spec.disabled, disabledTooltip = spec.disabledTooltip,
        getValue = function()
            local c = spec.cfg()
            local r, g, b = ns.HexToRGB(c[spec.colorKey])
            return r, g, b, spec.alphaKey and (tonumber(c[spec.alphaKey]) or spec.default) or 1
        end,
        setValue = function(r, g, b, a)
            local c = spec.cfg()
            c[spec.colorKey] = ns.RGBToHex(r, g, b)
            if spec.alphaKey then c[spec.alphaKey] = a or 1 end
            spec.onChange()
        end }
end

-- The module's "Use Global Background" toggle; `t` returns the table holding
-- `useGlobalBackground`.
function ns.UseGlobalBackgroundCell(t, onChange, tip)
    return { type = "toggle", text = "Use Global Background",
        tooltip = tip or "Draw this module's backgrounds with the Global Background and Global Header Background on the Global Settings page.",
        getValue = function() return t().useGlobalBackground == true end,
        setValue = function(v)
            t().useGlobalBackground = v and true or false
            onChange()
            ns.Ellesmere.RebuildPage()      -- the colour pickers show or hide
        end }
end

-- The Microbar's height while it sits under the minimap, in screen units
-- (height x effective scale), nil when it does not. The Microbar writes it;
-- the Minimap reads it to draw one border round map and bar, with a seam.
-- Runtime only. `fn` listeners run when the height changes (registered
-- once, gated in their bodies).
local minimapBar
local minimapBarFns = {}
function ns.MinimapBar() return minimapBar end
function ns.OnMinimapBar(fn)
    for _, f in ipairs(minimapBarFns) do
        if f == fn then return end
    end
    minimapBarFns[#minimapBarFns + 1] = fn
end
function ns.SetMinimapBar(h)
    if h == minimapBar then return end
    minimapBar = h
    for _, f in ipairs(minimapBarFns) do xpcall(f, ns.ErrorHandler("core:minimapBar")) end
end

function ns.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, nested in pairs(v) do out[k] = ns.DeepCopy(nested) end
    return out
end

-- Missing keys only; a value the user has set is never overwritten.
local function FillDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            FillDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ns.FillDefaults = FillDefaults

-- Whether every value in `t` that `defaults` also has is of the default's
-- type, in nested tables too. Returns true, or false and the path of the
-- first that is not. Keys the defaults lack are not checked: a value with
-- no default (a colour left to the global one) or from another version.
function ns.SameTypes(t, defaults, path)
    for k, dv in pairs(defaults) do
        local v = t[k]
        if v ~= nil then
            local at = path and (path .. "." .. tostring(k)) or tostring(k)
            if type(v) ~= type(dv) then return false, at end
            if type(v) == "table" then
                local ok, where = ns.SameTypes(v, dv, at)
                if not ok then return false, where end
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

local charKey                   -- "Name - Realm", read once at PLAYER_LOGIN

function ns.CharKey() return charKey or "?" end

-- Fills a profile table with defaults: the global settings and one table per
-- registered module (enabled = false unless the profile says otherwise).
-- A module's Migrate(cfg) runs first, on every profile at login before the
-- first Apply and on every profile that becomes active (an import too). Each
-- migration finds its work by a marker in cfg (a key still missing), so it
-- runs once, is idempotent and never writes a key the user has set.
local function FillProfile(p)
    -- A profile from an old version has a global table without a background.
    -- Its modules keep their own colours: each module's KeepOwnBackgrounds
    -- sets a missing "Use Global Background" flag (on by default) to off.
    -- Runs once per profile, since the background is filled right after.
    local keepOwn = type(p.global) == "table" and p.global.background == nil
    if type(p.global) ~= "table" then p.global = {} end
    FillDefaults(p.global, GLOBAL_DEFAULTS)
    if type(p.modules) ~= "table" then p.modules = {} end
    for _, m in ipairs(ns.ModuleList()) do
        if type(p.modules[m.key]) ~= "table" then p.modules[m.key] = {} end
        if keepOwn and m.KeepOwnBackgrounds then m:KeepOwnBackgrounds(p.modules[m.key]) end
        if m.Migrate then m:Migrate(p.modules[m.key]) end
        FillDefaults(p.modules[m.key], m.defaults)
    end
    return p
end

-- The defaults of the global table only (General page's Reset).
function ns.ResetGlobal()
    ns.db.global = {}
    FillDefaults(ns.db.global, GLOBAL_DEFAULTS)
    ns.Apply()
end

-- A module's settings back to its defaults. `enabled` is kept (Reset changes
-- how a module looks; it is switched off by its toggle), and so are the keys
-- in `keep` (content the user made, such as the panels): Ellesmere's Reset
-- popup speaks of settings, not content.
function ns.ResetModuleSettings(key, defaults)
    local old = ns.db.modules[key]
    local t = {}
    for _, k in ipairs(ns.GetModule(key).keep or {}) do t[k] = old[k] end
    FillDefaults(t, defaults)
    t.enabled = old.enabled
    ns.db.modules[key] = t
    ns.Apply()
end

function ns.ActiveProfileName()
    local db = ProseccoAdditionsDB
    return (type(db) == "table" and db.activeProfile and db.activeProfile[ns.CharKey()]) or DEFAULT_PROFILE
end

function ns.ProfileNames()
    local out = {}
    for name in pairs(ProseccoAdditionsDB.profiles) do out[#out + 1] = name end
    table.sort(out)
    return out
end

-- Points this character and ns.db at `name` and redraws. A module the new
-- profile turns on takes its values in other addons (SwitchedOn), as its
-- toggle does. Other addons read those values when they build their frames,
-- so a switch that wrote or gave back any, or switched a `reload` module,
-- asks for a reload. Cancel keeps the switch.
local ownedChanges = 0      -- values written into other addons this session
local function Activate(name)
    ProseccoAdditionsDB.activeProfile[ns.CharKey()] = name
    ns.db = FillProfile(ProseccoAdditionsDB.profiles[name])
    ns.Log("PROFILE", "active profile: %s", name)
    local before = ownedChanges
    local needReload = ns.Apply(false, true)
    -- The menu shows the modules that were on at login, and values written
    -- into other addons show when those rebuild: both after a reload.
    local menuOld = not ns.Options.MenuIsCurrent()
    if #needReload > 0 or menuOld or ownedChanges ~= before then
        local what = #needReload > 0 and table.concat(needReload, ", ")
            or (menuOld and "the modules") or "the other addons' settings"
        ns.Ellesmere.Confirm({
            title       = "Profile: " .. name,
            message     = "Reload so the menu and " .. what .. " match this profile?",
            confirmText = "Reload",
            reload      = true,
            onCancel    = function() ns.Print("type /reload to finish the profile switch.") end,
        })
    end
end

local function CleanName(name)
    return tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function ns.SwitchProfile(name)
    if not ProseccoAdditionsDB.profiles[name] then return false, "no such profile." end
    if name ~= ns.ActiveProfileName() then Activate(name) end
    return true
end

function ns.PresetNames()
    local out = {}
    for name in pairs(ns.Presets) do out[#out + 1] = name end
    table.sort(out)
    return out
end

-- Keys a preset never carries into a profile: a preset is look only, with
-- every module off and nothing placed.
local NOT_LOOK = { "enabled", "point", "relativePoint", "x", "y", "unlocked" }

-- A new profile table from preset `name`: its global and module look values,
-- the rest is filled with the defaults when the profile is activated.
function ns.PresetProfile(name)
    local preset = ns.Presets[name]
    if type(preset) ~= "table" then return nil end
    local p = { global = ns.DeepCopy(preset.global) or {}, modules = {} }
    for key, values in pairs(type(preset.modules) == "table" and preset.modules or {}) do
        local M = ns.GetModule(key)
        if M and type(values) == "table" then
            local t = ns.DeepCopy(values)
            for _, k in ipairs(NOT_LOOK) do t[k] = nil end
            for _, k in ipairs(M.keep or {}) do t[k] = nil end
            p.modules[key] = t
        end
    end
    return p
end

-- Creates a profile and switches this character to it. `source` = nil for the
-- installed defaults, or the name of a profile to copy; `preset` (with no
-- source) the name of a preset in Core/Presets.lua.
function ns.CreateProfile(name, source, preset)
    name = CleanName(name)
    if name == "" then return false, "type a profile name first." end
    if ProseccoAdditionsDB.profiles[name] then return false, "a profile with that name already exists." end
    local src = source and ProseccoAdditionsDB.profiles[source]
    local new = src and ns.DeepCopy(src)
    if not new and preset then
        new = ns.PresetProfile(preset)
        if not new then return false, "no such preset." end
    end
    ProseccoAdditionsDB.profiles[name] = new or {}
    Activate(name)
    return true, name
end

-- Overwrites the active profile with a copy of another one.
function ns.CopyProfileInto(name)
    local src = ProseccoAdditionsDB.profiles[name]
    if not src then return false, "no such profile." end
    local active = ns.ActiveProfileName()
    if name == active then return false, "that is the active profile." end
    ProseccoAdditionsDB.profiles[active] = ns.DeepCopy(src)
    Activate(active)
    return true
end

function ns.DeleteProfile(name)
    local profiles = ProseccoAdditionsDB.profiles
    if not profiles[name] then return false, "no such profile." end
    if #ns.ProfileNames() < 2 then return false, "this is the only profile." end
    profiles[name] = nil
    -- Every character that used it falls back to the first profile left.
    local fallback = ns.ProfileNames()[1]
    for key, p in pairs(ProseccoAdditionsDB.activeProfile) do
        if p == name then ProseccoAdditionsDB.activeProfile[key] = fallback end
    end
    if ns.ActiveProfileName() == fallback and ns.db ~= profiles[fallback] then
        Activate(fallback)
    end
    return true, fallback
end

-- The active profile back to the installed defaults.
function ns.ResetProfile()
    local active = ns.ActiveProfileName()
    ProseccoAdditionsDB.profiles[active] = {}
    Activate(active)
end

-- ---------------------------------------------------------------------------
-- Export / import of the active profile as a readable Lua table, so it can be
-- edited by hand or kept as a backup.
-- ---------------------------------------------------------------------------

local EXPORT_PREFIX = "PA1"
local OLD_PREFIX = "PUI1"       -- exports made before 0.7.0-alpha3 still import

local function Serialize(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        -- Sorted keys: the same profile always gives the same text.
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            if type(k) == "string" then
                out[#out + 1] = "[" .. ("%q"):format(k) .. "]="
            else
                out[#out + 1] = "[" .. ("%.14g"):format(k) .. "]="
            end
            Serialize(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = ("%q"):format(v)
    elseif t == "number" then
        out[#out + 1] = ("%.14g"):format(v)
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    else
        out[#out + 1] = "nil"
    end
end

function ns.ExportProfile()
    local out = {}
    Serialize(ns.db, out)
    return EXPORT_PREFIX .. table.concat(out)
end

-- An export is a table of strings, numbers and booleans. setfenv alone does not
-- stop code in pasted text: strings keep their methods and a function literal
-- can loop forever. Outside string literals, a call needs "(" and a loop needs
-- "function"; an export has neither, nor a long string ("[[", "[=").
local function IsPlainData(text)
    local i, n = 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c == '"' or c == "'" then            -- skip a quoted string, escapes included
            i = i + 1
            while i <= n and text:sub(i, i) ~= c do
                if text:sub(i, i) == "\\" then i = i + 1 end
                i = i + 1
            end
        elseif c == "(" or text:find("^%[[%[=]", i) or text:find("^function", i) then
            return false
        end
        i = i + 1
    end
    return true
end

-- An export may be edited by hand, so it is checked before it replaces
-- anything: each setting the defaults know has their type, and a module
-- with its own content (Panels' list) checks it in CheckImport(cfg). A wrong
-- type would otherwise be a Lua error after the import said it worked.
-- Returns true, or false and the path of the first bad value (public for
-- the sim tests).
function ns.CheckImport(data)
    local ok, at = ns.SameTypes(data, { global = GLOBAL_DEFAULTS, modules = {} })
    if not ok then return false, at end
    for _, m in ipairs(ns.ModuleList()) do
        local cfg = data.modules and data.modules[m.key]
        if cfg ~= nil then
            local path = "modules." .. m.key
            if type(cfg) ~= "table" then return false, path end
            ok, at = ns.SameTypes(cfg, m.defaults, path)
            if ok and m.CheckImport then ok, at = m:CheckImport(cfg, path) end
            if not ok then return false, at end
        end
    end
    return true
end

-- Replaces the active profile. Returns true, or false and a reason to print;
-- on false the active profile is as it was.
function ns.ImportProfile(text)
    text = CleanName(text):gsub("^" .. EXPORT_PREFIX, ""):gsub("^" .. OLD_PREFIX, "")
    if text == "" then return false, "nothing to import." end
    if not text:match("^%b{}$") or not IsPlainData(text) then
        return false, "that does not look like a ProseccoAdditions export."
    end
    local fn = loadstring("return " .. text)
    if not fn then return false, "could not read that text." end
    setfenv(fn, {})                       -- no globals
    -- The text comes from outside the addon; a malformed table must not throw.
    local ok, data = pcall(fn)
    if not ok or type(data) ~= "table" then return false, "could not read that text." end
    if type(data.global) ~= "table" and type(data.modules) ~= "table" then
        return false, "no ProseccoAdditions settings found in that text."
    end
    local valid, at = ns.CheckImport(data)
    if not valid then
        return false, "the setting " .. at .. " has the wrong kind of value; nothing was imported."
    end
    local active = ns.ActiveProfileName()
    ProseccoAdditionsDB.profiles[active] = data
    Activate(active)
    return true
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------

-- SavedVariables exist from our ADDON_LOADED. Only the shape is checked here;
-- profile contents get their defaults when they become active.
local function InitDB()
    -- The settings were saved as ProseccoUIDB before 0.7.0-alpha3; both are
    -- in the .toc so the old one still loads and moves over. The old one is
    -- cleared only once the new one has come back from disk: after a /reload
    -- WoW still saves by the old .toc, which knows only ProseccoUIDB.
    if ProseccoAdditionsDB == nil and type(ProseccoUIDB) == "table" then
        ProseccoAdditionsDB = ProseccoUIDB
    elseif type(ProseccoAdditionsDB) == "table" then
        ProseccoUIDB = nil
    end
    local fresh = type(ProseccoAdditionsDB) ~= "table"
    if fresh then ProseccoAdditionsDB = {} end
    local db = ProseccoAdditionsDB
    -- The first-start line is for a new install only: an existing
    -- ProseccoAdditionsDB means the addon has started on this account before.
    if db.welcomed == nil then db.welcomed = not fresh end
    db.version = db.version or DB_VERSION
    if type(db.activeProfile) ~= "table" then db.activeProfile = {} end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.log) ~= "table" then db.log = {} end
    if type(db.owned) ~= "table" then db.owned = {} end
    if type(db.chars) ~= "table" then db.chars = {} end
end

-- One chat line the first time the addon starts on the account (all modules
-- start off, so nothing else shows that it is there). ProseccoAdditionsDB is
-- account-wide, so it shows once per account, not per character.
function ns.FirstStartNotice()
    if ProseccoAdditionsDB.welcomed then return end
    ProseccoAdditionsDB.welcomed = true
    ns.Print("every module is off until you turn it on. Type /prosecco to open the settings.")
end

-- Another addon's values from before a module took them over, given back
-- when the module goes off. Account-wide, not in a profile: the values
-- belong to the other addon, and a profile switch, reset or import must not
-- carry them off or throw them away.
function ns.OwnedStore(key)
    local owned = ProseccoAdditionsDB.owned
    if type(owned[key]) ~= "table" then owned[key] = {} end
    return owned[key]
end

-- This character's table in ProseccoAdditionsDB.chars: data that belongs to the
-- character, not to a profile (several characters can share a profile).
local function Char()
    local chars = ProseccoAdditionsDB.chars
    local key = ns.CharKey()
    if type(chars[key]) ~= "table" then chars[key] = {} end
    local c = chars[key]
    if type(c.modules) ~= "table" then c.modules = {} end
    return c
end

-- Module `key`'s own table for this character, runtime data that outlives a
-- /reload (XP Bar's session). Not settings: no defaults, no Reset, no export.
function ns.CharStore(key)
    local modules = Char().modules
    if type(modules[key]) ~= "table" then modules[key] = {} end
    return modules[key]
end

-- time() at this character's last real login; the same after a /reload, so
-- data saved with it belongs to this login when the stamps match. Set at the
-- first PLAYER_ENTERING_WORLD (below), nil before it on the first start.
function ns.LoginStamp() return Char().login end

-- ---------------------------------------------------------------------------
-- Spec profiles: the ProseccoAdditions and Ellesmere profiles this character
-- switches to when it changes between its Primary and Secondary spec.
-- Ellesmere's own spec profiles cannot tell the two apart on Forever (it
-- sees one spec per class); GetActiveSpecGroup can (1 = Primary).
--
-- Per character, since a spec belongs to a character and a profile switch
-- must not change where the next spec change goes (ProseccoAdditionsDB.chars):
--   specProfiles = { [1] = { proseccoui = name, ellesmere = name }, [2] = {...} }
-- A missing name = that addon does not switch. Only on a change of spec, not
-- at login: a profile picked by hand stays until the next change.
-- ---------------------------------------------------------------------------

-- Off until it has been tested in game with two specs: the event is not
-- registered and the Profiles page shows no Spec Profiles rows.
ns.SPEC_PROFILES = false

local SPEC_NAMES = { "Primary", "Secondary" }
local specHost, specPending

function ns.SpecGroup() return C_SpecializationInfo.GetActiveSpecGroup() end
function ns.SpecGroupName(group) return SPEC_NAMES[group or ns.SpecGroup()] or "?" end
function ns.HasTwoSpecs() return GetNumSpecGroups() > 1 end

local function SpecMap()
    local c = Char()
    if type(c.specProfiles) ~= "table" then c.specProfiles = {} end
    return c.specProfiles
end

-- addon = "proseccoui" or "ellesmere"
function ns.SpecProfile(group, addon)
    local m = SpecMap()[group]
    return type(m) == "table" and m[addon] or nil
end

local function AnySpecProfile()
    for _, m in pairs(SpecMap()) do
        if type(m) == "table" and (m.proseccoui or m.ellesmere) then return true end
    end
    return false
end

local lastGroup             -- the spec group the last switch (or the watch's start) saw
local function SwitchForSpec()
    local group = ns.SpecGroup()
    lastGroup = group
    local m = SpecMap()[group]
    if type(m) ~= "table" then return end
    local done = {}
    local ellesmere, ours
    -- Ellesmere first: our modules read Ellesmere's values (target frame,
    -- fonts), so they redraw after it has switched. The values our running
    -- modules own in Ellesmere go into its new profile before it redraws.
    if m.ellesmere then
        if ns.Ellesmere.SwitchProfile(m.ellesmere, ns.RewriteOwned) then
            ellesmere = true
            done[#done + 1] = "Ellesmere \"" .. m.ellesmere .. "\""
        elseif not ns.Ellesmere.HasProfile(m.ellesmere) then
            ns.Print("Ellesmere has no profile \"" .. m.ellesmere .. "\" any more (" .. ns.SpecGroupName(group) .. " spec).")
        end
    end
    if m.proseccoui and m.proseccoui ~= ns.ActiveProfileName() then
        if ns.SwitchProfile(m.proseccoui) then
            ours = true
            done[#done + 1] = "ProseccoAdditions \"" .. m.proseccoui .. "\""
            ns.Options.RebuildAll()
        else
            ns.Print("there is no profile \"" .. m.proseccoui .. "\" any more (" .. ns.SpecGroupName(group) .. " spec).")
        end
    end
    -- A ProseccoAdditions switch has just redrawn every module.
    if ellesmere and not ours then ns.Apply() end
    if #done > 0 then
        ns.Print(ns.SpecGroupName(group) .. " spec: " .. table.concat(done, ", ") .. ".")
    end
end

-- The event only while a spec has a profile. Only a change from the group
-- seen last counts (read with GetActiveSpecGroup, not from the payload): the
-- event also fires while the client loads talents, with the same group. A
-- change in combat waits for its end, as Ellesmere's own spec switch does;
-- the switch then reads the spec active at that moment.
local function OnSpecEvent(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not specPending then return end
        specPending = false
    elseif ns.SpecGroup() == lastGroup then
        return
    elseif InCombatLockdown() then
        lastGroup = ns.SpecGroup()
        specPending = true
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    SwitchForSpec()
end

function ns.WatchSpec()
    if ns.SPEC_PROFILES and AnySpecProfile() then
        if not specHost then
            specHost = CreateFrame("Frame")
            specHost:SetScript("OnEvent", function(self, event)
                xpcall(OnSpecEvent, ns.ErrorHandler("core:spec"), self, event)
            end)
        end
        if not specHost:IsEventRegistered("ACTIVE_TALENT_GROUP_CHANGED") then lastGroup = ns.SpecGroup() end
        specHost:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    elseif specHost then
        specHost:UnregisterAllEvents()
        specPending = false
    end
end

function ns.SetSpecProfile(group, addon, name)
    local map = SpecMap()
    if type(map[group]) ~= "table" then map[group] = {} end
    map[group][addon] = name
    ns.WatchSpec()
end

-- Test hooks: what a spec change does without the event, and the event frame.
ns.SwitchForSpec = SwitchForSpec
function ns.SpecHost() return specHost end

-- The integrations that read and write owned targets register here (e.g.
-- Ellesmere's settings tables, Questie's tracker flag), so Core never names
-- them. Each has OwnedProfile/ReadOwned/WriteOwned.
local owners = {}
function ns.RegisterOwner(target, integration)
    owners[target] = integration
end

local function Owner(target)
    return owners[target] or error("ProseccoAdditions: no integration owns target " .. tostring(target))
end

-- Takes over another addon's settings for module `key`. `owned` lists
-- { target, key, value, label } (targets as registered above). Saves each
-- setting's current value, then writes the module's. A saved entry stays
-- while the setting still holds our value (a second press must not save
-- ours as "before"), and is replaced when the user has set something else.
-- Prints the labels of settings it could not reach (addon not loaded).
function ns.TakeOwned(key, owned, tag)
    local store = ns.OwnedStore(key)
    local missing = {}
    for _, o in ipairs(owned) do
        local I = Owner(o.target)
        local profile = I.OwnedProfile(o.target)
        local found, old = I.ReadOwned(o.target, profile, o.key)
        if found then
            local entry
            for _, r in ipairs(store) do
                if r.target == o.target and r.key == o.key and r.profile == profile then entry = r break end
            end
            if not entry then
                entry = { target = o.target, profile = profile, key = o.key, value = old }
                store[#store + 1] = entry
            elseif entry.wrote ~= nil and old ~= nil and old ~= entry.wrote and old ~= o.value then
                -- Set by the user since we wrote ours. An entry without `wrote`
                -- (an old version) keeps its value: `old` may be ours. nil is
                -- never a user change: Ellesmere drops values equal to its
                -- default from the saved profile at logout.
                entry.value = old
            end
            entry.wrote, entry.label = o.value, o.label
            I.WriteOwned(o.target, profile, o.key, o.value)
            ownedChanges = ownedChanges + 1
            ns.Log(tag, "owned %s %s = %s (was %s)", o.target, o.key, tostring(o.value), tostring(old))
        else
            missing[#missing + 1] = o.label
        end
    end
    if #missing > 0 then
        ns.Print("not loaded, left alone: " .. table.concat(missing, ", ") .. ".")
    end
end

-- Writes back every value module `key` saved (nil = the other addon's
-- default) into the profile it was taken from, unless the user has changed
-- the setting since we wrote it: then their value stays and the entry goes.
-- One that cannot be reached now (its addon disabled) is kept for the next
-- time and said so in the chat; `quiet` drops that line (a call on every
-- Apply). `onlyTarget` limits it to that target's entries (a target the
-- module no longer owns). Returns true when a value was written back.
-- Nothing is given back while a failed Enable is being taken down
-- (ns.HoldOwned): the values were taken on purpose, and the module stays on.
local holdOwned = false
function ns.HoldOwned(on) holdOwned = on end

function ns.GiveBackOwned(key, tag, onlyTarget, quiet)
    if holdOwned then return false end
    local store = ns.OwnedStore(key)
    local wrote, missing = false, {}
    for i = #store, 1, -1 do
        local r = store[i]
        if onlyTarget == nil or r.target == onlyTarget then
            local I = Owner(r.target)
            local found, now = I.ReadOwned(r.target, r.profile, r.key)
            if not found then
                missing[#missing + 1] = r.label or r.key
            elseif r.wrote ~= nil and now ~= nil and now ~= r.wrote then
                ns.Log(tag, "left %s %s = %s (changed since we set %s)", r.target, r.key, tostring(now), tostring(r.wrote))
                table.remove(store, i)
            elseif I.WriteOwned(r.target, r.profile, r.key, r.value) then
                ns.Log(tag, "restored %s %s = %s", r.target, r.key, tostring(r.value))
                table.remove(store, i)
                wrote = true
                ownedChanges = ownedChanges + 1
            end
        end
    end
    -- Not for a one-off give-back of one target (Damage Meter gives back old
    -- Threat Meter values at every Enable): that would print at each login.
    if #missing > 0 and onlyTarget == nil and not quiet then
        ns.Print("could not put back (addon or profile not loaded): " .. table.concat(missing, ", ")
            .. ". They are put back the next time this module is turned off with it loaded.")
    end
    return wrote
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        charKey = UnitName("player") .. " - " .. GetRealmName()
        local profile = ns.ActiveProfileName()
        if type(ProseccoAdditionsDB.profiles[profile]) ~= "table" then ProseccoAdditionsDB.profiles[profile] = {} end
        ProseccoAdditionsDB.activeProfile[charKey] = profile
        -- Every profile, not only this character's, so the migration in
        -- FillProfile runs on all of them before the first Apply. An
        -- imported profile is migrated when it is filled.
        for _, p in pairs(ProseccoAdditionsDB.profiles) do
            if type(p) == "table" then FillProfile(p) end
        end
        ns.db = ProseccoAdditionsDB.profiles[profile]
        ns.LogSessionHeader(ns.HookErrors())
        ns.Apply(true)
        ns.Options.Register()
        ns.WatchSpec()
        ns.FirstStartNotice()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The first one of a UI load says whether it is a real login or a
        -- /reload (isInitialLogin); later ones are loading screens. With no
        -- stamp yet (first start), this load counts as the login.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        local c = Char()
        if name == true or c.login == nil then c.login = time() end
    end
end)

-- ---------------------------------------------------------------------------
-- /prosecco
-- ---------------------------------------------------------------------------

local HELP = {
    "/prosecco  open the settings",
    "/prosecco status  modules, version, client build, profile and addons",
    "/prosecco profile  this character's profile",
    "/prosecco log [n|clear|on|off]  the debug log",
    "/prosecco mark <text>  a marker in the debug log",
    "/prosecco help  this list",
}

local function Help()
    ns.Print("commands:")
    for _, line in ipairs(HELP) do print("  " .. line) end
end

-- One line per module with its state this session (ns.ModuleState), for a
-- test report. Core does not read the integrations, so the RXP theme's own
-- state is not here.
local function Status()
    local version, build, _, toc = GetBuildInfo()
    ns.Print(("%s, client %s build %s (interface %s)"):format(
        ns.version, tostring(version), tostring(build), tostring(toc)))
    print("  profile \"" .. ns.ActiveProfileName() .. "\", character " .. ns.CharKey())
    for _, M in ipairs(ns.ModuleList()) do
        print("  " .. M.title .. ": " .. ns.ModuleState(M.key))
    end
    local addons = ns.LoadedAddons()
    print("  addons: " .. (#addons > 0 and table.concat(addons, ", ") or "none"))
end

SLASH_PROSECCOADDITIONS1 = "/prosecco"
SLASH_PROSECCOADDITIONS2 = "/proseccoadditions"
SlashCmdList.PROSECCOADDITIONS = function(msg)
    msg = tostring(msg or "")
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "log" then
        ns.LogCommand(rest:lower())
    elseif cmd == "mark" then
        if rest == "" then rest = "(no text)" end
        ns.Log("MARK", "%s", rest)
        ns.Print("marker saved: \"" .. rest .. "\" -- written to disk on /reload.")
    elseif cmd == "profile" then
        ns.Print("character " .. ns.CharKey() .. ", profile \"" .. ns.ActiveProfileName()
            .. "\" (" .. #ns.ProfileNames() .. " profiles).")
    elseif cmd == "status" then
        Status()
    elseif cmd == "help" then
        Help()
    elseif cmd == "" then
        ns.Options.Open()
    else
        ns.Print("unknown command \"" .. cmd .. "\".")
        Help()
    end
end
