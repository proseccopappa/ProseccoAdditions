-- ProseccoAdditions / Core / Options.lua
-- Our section in Ellesmere's options panel, built with Ellesmere's widgets
-- through its plugin API. Sidebar rows: General (tabs General, Global
-- Settings and Profiles), then one row per module that is on, in load order.
-- The plugin API takes the sidebar as a snapshot at registration, so a module
-- just turned on gets its row only after a reload (General's Reload to apply).

local _, ns = ...

ns.Options = {}

local menuKeys = { "General" }  -- the rows registered this session, General first
local inMenu = {}               -- module key -> true when it has a row this session

local function AllKeys()
    return menuKeys
end

-- After a profile switch, reset or import every cached page is stale.
local function RebuildAll()
    ns.Ellesmere.RebuildPages(AllKeys())
end
ns.Options.RebuildAll = RebuildAll      -- for a profile switch on a spec change

-- ---------------------------------------------------------------------------
-- Copy / paste window for export and import.
-- Created the first time it is needed; no global name.
-- ---------------------------------------------------------------------------

local textFrame
local function ShowText(title, text, onImport)
    if not textFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(620, 400); f:SetPoint("CENTER")
        -- One strata below Ellesmere's confirm popup (FULLSCREEN_DIALOG), so the
        -- "Import?" question opens on top of this window.
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -5)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 42)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(560)
        eb:SetHeight(1500); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(120, 24); btn:SetPoint("BOTTOM", 0, 12)
        btn:SetText("Import")
        btn:SetScript("OnClick", function()
            if f.onImport then f.onImport(f.edit:GetText()) end
        end)
        f.button = btn
        textFrame = f
    end
    textFrame.title:SetText(title)
    textFrame.edit:SetText(text or "")
    textFrame.onImport = onImport
    textFrame.button:SetShown(onImport ~= nil)
    textFrame:Show()
    if onImport then textFrame.edit:SetFocus() else textFrame.edit:HighlightText() end
end

-- ---------------------------------------------------------------------------
-- General: the modules. Global Settings: the global border, with a preview
-- box drawn by ns.Border.Apply (the only thing on screen that uses the border
-- before the first module).
-- ---------------------------------------------------------------------------

local preview                   -- the preview box on the newest built Global Settings page

local function RefreshPreview()
    if preview then ns.Border.Apply(preview, ns.db.global.border) end
end

-- One toggle per module. It switches at once; a module that changes other
-- addons asks first (ns.SetModuleEnabled).
local function ModuleCell(M)
    local tip = M.description or ""
    if M.affects then tip = tip .. "\n\nChanges other addons:\n- " .. table.concat(M.affects, "\n- ") end
    return { type = "toggle", text = M.title, tooltip = tip ~= "" and tip or nil,
        -- A whole sentence: Ellesmere shows a "This option ..." text as it is
        -- and wraps anything else in "This option requires ... to be enabled".
        disabled = M.locked and function() return true end or nil,
        disabledTooltip = M.locked and ("This option is locked: " .. M.locked) or nil,
        getValue = function() return ns.IsModuleEnabled(M.key) end,
        setValue = function(v)
            ns.SetModuleEnabled(M.key, v and true or false, ns.Ellesmere.RefreshPage)
        end }
end

-- The order of the switches on the General tab, Panels last. A module not
-- named here follows in load order.
local SWITCH_ORDER = { "volume", "minimap", "damageMeter", "rxpTheme", "chat",
                       "questTracker", "targetFrame", "xpBar", "trinkets", "panels" }

local function SwitchList()
    local byKey, list, listed = {}, {}, {}
    for _, M in ipairs(ns.ModuleList()) do byKey[M.key] = M end
    for _, key in ipairs(SWITCH_ORDER) do
        if byKey[key] then list[#list + 1] = byKey[key]; listed[key] = true end
    end
    for _, M in ipairs(ns.ModuleList()) do
        if not listed[M.key] then list[#list + 1] = M end
    end
    return list
end

function ns.Options.ReloadToApply()
    ns.Ellesmere.Confirm({
        title = "ProseccoAdditions",
        message = "Reload now so the menu and the modules you switched are up to date?",
        confirmText = "Reload",
        reload = true,
    })
end

local function BuildModuleList(W, parent, y)
    local _, h
    _, h = W:SectionHeader(parent, "MODULES", y); y = y - h
    -- No right cell: a full-width row, so the sentence is not cut off.
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Here you can choose which modules you want, hover each module for tooltip on what it does." }); y = y - h
    -- Always there: a reload is harmless, and a module switched on and off
    -- again may still want one for the other addons' values it gave back.
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Turn module ON/OFF, requires reload to apply." },
        -- Ellesmere's popup reloads: WoW Forever blocks ReloadUI() from addon
        -- code even in a click, and the popup's confirm is a secure /reload
        -- button.
        { type = "button", text = "Reload to apply", width = 150,
          onClick = function() ns.Options.ReloadToApply() end }); y = y - h
    local list = SwitchList()
    for i = 1, #list, 2 do
        _, h = W:DualRow(parent, y, ModuleCell(list[i]),
            list[i + 1] and ModuleCell(list[i + 1]) or { type = "spacer" }); y = y - h
    end
    return y
end

local ABOUT = {
    "A collection of modular enhancements for EllesmereUI,",
    "featuring cosmetic customizations for the chat, damage meter, minimap, and more.",
    "Includes a custom quest tracker, microbar, and XP bar,",
    "along with RestedXP reskinning and integration into the quest tracker.",
    "Each module can be enabled individually,",
    "letting you pick and choose the features and customizations you want.",
}

local function BuildGeneral(_, parent, y)
    local W = ns.Ellesmere.Widgets()
    local _, h
    _, h = W:SectionHeader(parent, "ABOUT", y); y = y - h
    -- Ellesmere's labels never wrap, so the text goes one clause a row.
    for _, text in ipairs(ABOUT) do
        _, h = W:DualRow(parent, y, { type = "label", text = text }); y = y - h
    end
    y = BuildModuleList(W, parent, y)
    return math.abs(y)
end

-- Global Settings: the border, background and font the modules share, with a
-- preview box drawn by ns.Border.Apply.
local function BuildGlobal(_, parent, y)
    local W = ns.Ellesmere.Widgets()
    local _, h
    _, h = W:SectionHeader(parent, "GLOBAL BORDER", y); y = y - h
    y = ns.Border.Rows(W, parent, y, function() return ns.db.global.border end, function()
        ns.Apply()
        RefreshPreview()
    end, true)
    -- No right cell: a full-width row, so the sentence is not cut off.
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Modules with \"Use Global Border\" on follow these values." }); y = y - h

    local function GlobalColor(text, kind, tip)
        return { type = "colorpicker", text = text, hasAlpha = true, tooltip = tip,
            getValue = function()
                local c = ns.db.global[kind]
                local r, g, b = ns.HexToRGB(c.color)
                return r, g, b, tonumber(c.alpha) or 1
            end,
            setValue = function(r, g, b, a)
                local c = ns.db.global[kind]
                c.color, c.alpha = ns.RGBToHex(r, g, b), a or 1
                ns.Apply()
            end }
    end
    _, h = W:SectionHeader(parent, "GLOBAL BACKGROUND", y); y = y - h
    _, h = W:DualRow(parent, y,
        GlobalColor("Global Background", "background", "The background of module boxes: windows, lists and panels."),
        GlobalColor("Global Header Background", "headerBackground", "The background of header and title boxes.")); y = y - h
    local texNames, texOrder = ns.Ellesmere.BarTextures()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Global Header Texture", values = texNames, order = texOrder,
          tooltip = "An Ellesmere bar texture on every header, title and badge box in ProseccoAdditions, tinted by its colour, or a flat colour.",
          getValue = function() return ns.db.global.headerTexture or "none" end,
          setValue = function(v) ns.db.global.headerTexture = v; ns.Apply() end },
        { type = "spacer" }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Modules with \"Use Global Background\" on follow these colours." }); y = y - h

    _, h = W:SectionHeader(parent, "GLOBAL FONT", y); y = y - h
    local fonts, fontOrder = ns.Media.FontList()
    local outlines, outlineOrder = ns.Media.OutlineList()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Global Font", values = fonts, order = fontOrder,
          tooltip = "The font of modules whose Font is set to Global font.",
          getValue = function() return ns.db.global.font.face end,
          setValue = function(v) ns.db.global.font.face = v; ns.Apply() end },
        { type = "dropdown", text = "Global Outline", values = outlines, order = outlineOrder,
          tooltip = "The outline of modules whose Outline is set to Global outline. Shadow is a drop shadow without an outline; Ellesmere's outline also takes Ellesmere's shadow when its Outline Mode uses one.",
          getValue = function() return ns.db.global.font.outline end,
          setValue = function(v) ns.db.global.font.outline = v; ns.Apply() end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Quest Tracker and RXP Theme can follow these." }); y = y - h

    if not ns.Ellesmere.IsSearchPrebuild() then
        _, h = W:SectionHeader(parent, "PREVIEW", y); y = y - h
        local box = CreateFrame("Frame", nil, parent)
        -- Anchored from the left on whole pixels: centred, its edges can land
        -- on half pixels and blur (Inferred).
        ns.Ellesmere.PixelSize(box, 220, 60)
        ns.Ellesmere.PixelPoint(box, "TOPLEFT", parent, "TOPLEFT", 40, y - 16)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
        preview = box
        RefreshPreview()
        y = y - 92
    end
    return math.abs(y)
end

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

local newName, newFrom, copyFrom = "", "__defaults", nil
local PRESET = "__preset:"      -- "Start from" prefix of a preset; other values are profile names

local function Report(ok, msg)
    if msg then ns.Print(msg) end
    if ok then RebuildAll() end
end

-- The profiles a change of spec switches to (off while ns.SPEC_PROFILES is).
local function SpecProfileRows(W, parent, y, names)
    local _, h
    _, h = W:SectionHeader(parent, "SPEC PROFILES", y); y = y - h
    local NONE = "__none"
    local function Choices(list)
        local v, o = { [NONE] = "Don't switch" }, { NONE }
        for _, n in ipairs(list) do v[n] = n; o[#o + 1] = n end
        return v, o
    end
    local pv, po = Choices(names)
    local ev, eo = Choices(ns.Ellesmere.ProfileNames())
    local function SpecCell(group, addon, v, o)
        local who = addon == "ellesmere" and "Ellesmere" or "ProseccoAdditions"
        local spec = ns.SpecGroupName(group)
        return { type = "dropdown", text = who .. ", " .. spec, values = v, order = o,
            tooltip = "The " .. who .. " profile this character switches to when you change to your "
                .. spec .. " spec.",
            getValue = function()
                local n = ns.SpecProfile(group, addon)
                return (n and v[n]) and n or NONE
            end,
            setValue = function(x) ns.SetSpecProfile(group, addon, x ~= NONE and x or nil) end }
    end
    _, h = W:DualRow(parent, y, SpecCell(1, "proseccoui", pv, po), SpecCell(2, "proseccoui", pv, po)); y = y - h
    _, h = W:DualRow(parent, y, SpecCell(1, "ellesmere", ev, eo), SpecCell(2, "ellesmere", ev, eo)); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Switches on a change of spec. Now: " .. ns.SpecGroupName()
            .. (ns.HasTwoSpecs() and "" or " (no second spec)") .. "." }); y = y - h
    if ns.Ellesmere.HasOwnSpecProfiles() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Ellesmere has spec profiles of its own (Ellesmere > Profiles). They switch Ellesmere too: clear them there if Ellesmere switches here." }); y = y - h
    end
    return y
end

local function BuildProfiles(_, parent, y)
    local W = ns.Ellesmere.Widgets()
    local _, h
    local active = ns.ActiveProfileName()
    local names = ns.ProfileNames()

    -- Which profile this character uses
    _, h = W:SectionHeader(parent, "ACTIVE PROFILE", y); y = y - h
    local values, order = {}, {}
    for i, n in ipairs(names) do values[n] = n; order[i] = n end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Profile",
          tooltip = "Every ProseccoAdditions setting, including which modules are on, belongs to this profile. Each character remembers its own choice.",
          values = values, order = order,
          getValue = function() return ns.ActiveProfileName() end,
          setValue = function(v)
              local ok, why = ns.SwitchProfile(v)
              Report(ok, ok and ("now using profile \"" .. v .. "\".") or why)
          end },
        { type = "label", text = "This character: " .. ns.CharKey() }); y = y - h

    if ns.SPEC_PROFILES then y = SpecProfileRows(W, parent, y, names) end

    -- New profile
    _, h = W:SectionHeader(parent, "NEW PROFILE", y); y = y - h
    local srcValues, srcOrder = { __defaults = "Installed defaults" }, { "__defaults" }
    -- Presets: look only, every module off, nothing placed.
    for _, n in ipairs(ns.PresetNames()) do
        srcValues[PRESET .. n] = n .. " (look only)"
        srcOrder[#srcOrder + 1] = PRESET .. n
    end
    for _, n in ipairs(names) do
        srcValues[n] = "Copy of \"" .. n .. "\""
        srcOrder[#srcOrder + 1] = n
    end
    if srcValues[newFrom] == nil then newFrom = "__defaults" end
    _, h = W:DualRow(parent, y,
        { type = "input", text = "Name", inputWidth = 160, inputStyle = "popup",
          getValue = function() return newName end,
          setValue = function(v) newName = tostring(v or "") end },
        { type = "dropdown", text = "Start from", values = srcValues, order = srcOrder,
          getValue = function() return newFrom end,
          setValue = function(v) newFrom = v end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "This character switches to the new profile." },
        { type = "button", text = "Create", width = 130,
          onClick = function()
              local preset = newFrom:sub(1, #PRESET) == PRESET and newFrom:sub(#PRESET + 1) or nil
              local copy = newFrom ~= "__defaults" and not preset and newFrom or nil
              local ok, why = ns.CreateProfile(newName, copy, preset)
              if ok then newName = "" end
              Report(ok, ok and ("created profile \"" .. why .. "\" and switched to it.") or why)
          end }); y = y - h

    -- Copy another profile into this one
    _, h = W:SectionHeader(parent, "COPY INTO \"" .. active .. "\"", y); y = y - h
    local others, otherOrder = {}, {}
    for _, n in ipairs(names) do
        if n ~= active then others[n] = n; otherOrder[#otherOrder + 1] = n end
    end
    if copyFrom == nil or others[copyFrom] == nil then copyFrom = otherOrder[1] end
    local hasOther = #otherOrder > 0
    local noOther = function() return not hasOther end
    -- With nothing to copy from, the dropdown shows a line saying so, not an
    -- empty value.
    if #otherOrder == 0 then others.__none = "No other profile"; otherOrder[1] = "__none" end
    local noOtherTip = "This option needs a second profile. Create one under New Profile."
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Copy from", values = others, order = otherOrder,
          disabled = noOther, disabledTooltip = noOtherTip,
          getValue = function() return copyFrom or "__none" end,
          setValue = function(v) copyFrom = v end },
        { type = "button", text = "Copy", width = 130,
          disabled = noOther, disabledTooltip = noOtherTip,
          onClick = function()
              local from = copyFrom
              ns.Ellesmere.Confirm({
                  title = "Copy profile",
                  message = "Replace everything in \"" .. ns.ActiveProfileName() .. "\" with \""
                      .. tostring(from) .. "\"? The profile you copy from is left alone.",
                  confirmText = "Copy",
                  onConfirm = function()
                      local ok, why = ns.CopyProfileInto(from)
                      Report(ok, ok and ("copied \"" .. tostring(from) .. "\" in.") or why)
                  end,
              })
          end }); y = y - h

    -- Delete / reset
    _, h = W:SectionHeader(parent, "DELETE OR RESET \"" .. active .. "\"", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Delete", width = 130,
          disabled = function() return #names < 2 end,
          disabledTooltip = "This option needs a second profile: the only profile cannot be deleted.",
          onClick = function()
              local name = ns.ActiveProfileName()
              ns.Ellesmere.Confirm({
                  title = "Delete profile",
                  message = "Delete \"" .. name .. "\"? Characters using it move to the first profile left.",
                  confirmText = "Delete",
                  onConfirm = function()
                      local ok, why = ns.DeleteProfile(name)
                      Report(ok, ok and ("deleted \"" .. name .. "\", now using \"" .. why .. "\".") or why)
                  end,
              })
          end },
        { type = "button", text = "Reset to defaults", width = 160,
          onClick = function()
              local name = ns.ActiveProfileName()
              ns.Ellesmere.Confirm({
                  title = "Reset profile",
                  message = "Put every setting in \"" .. name .. "\" back to the installed defaults? "
                      .. "Modules that are on are switched off. Export first if you want a copy.",
                  confirmText = "Reset",
                  onConfirm = function()
                      ns.ResetProfile()
                      Report(true, "\"" .. name .. "\" reset to defaults.")
                  end,
              })
          end }); y = y - h

    -- Text in and out
    _, h = W:SectionHeader(parent, "EXPORT AND IMPORT", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Export", width = 130,
          onClick = function()
              ShowText("Export of \"" .. ns.ActiveProfileName() .. "\" - Ctrl+C to copy", ns.ExportProfile())
          end },
        { type = "button", text = "Import", width = 130,
          onClick = function()
              ShowText("Import into \"" .. ns.ActiveProfileName() .. "\" - Ctrl+V, then Import", "",
                  function(text)
                      ns.Ellesmere.Confirm({
                          title = "Import",
                          message = "Replace everything in \"" .. ns.ActiveProfileName()
                              .. "\" with the pasted settings? Other profiles are not touched.",
                          confirmText = "Import",
                          onConfirm = function()
                              local ok, why = ns.ImportProfile(text)
                              if ok then textFrame:Hide() end
                              Report(ok, ok and ("imported into \"" .. ns.ActiveProfileName() .. "\".")
                                  or ("import failed: " .. why))
                          end,
                      })
                  end)
          end }); y = y - h
    return math.abs(y)
end

-- Test hook for the sim tests.
function ns.Options.BuildProfilesForTest(parent, y) return BuildProfiles("Profiles", parent, y) end

-- ---------------------------------------------------------------------------
-- Module pages: the module's own rows (it is switched on the General tab).
-- ---------------------------------------------------------------------------

-- Whether a page Reset would change anything: a default that is neither
-- `enabled` nor content the module keeps (Panels has only its panels).
local function HasResettable(M)
    local kept = {}
    for _, k in ipairs(M.keep or {}) do kept[k] = true end
    for k in pairs(M.defaults) do
        if k ~= "enabled" and not kept[k] then return true end
    end
    return false
end

local function ModuleSpec(M)
    return {
        key = M.key,
        title = M.title,
        description = M.description,
        pages = M.pages,
        buildPage = function(pageName, parent, y)
            local W = ns.Ellesmere.Widgets()
            if M.BuildPage then y = M:BuildPage(pageName, parent, y, W) end
            return math.abs(y)
        end,
        -- A fixed header above the page's rows (a preview), when the module has one.
        getHeaderBuilder = M.GetHeaderBuilder and function(pageName) return M:GetHeaderBuilder(pageName) end or nil,
        onPageCacheRestore = M.PageShown and function(pageName) M:PageShown(pageName) end or nil,
        onReset = HasResettable(M) and function()
            ns.ResetModuleSettings(M.key, M.defaults)
            RebuildAll()
        end or nil,
    }
end

-- ---------------------------------------------------------------------------

local registered = false

-- Called once at PLAYER_LOGIN, after every module file has registered
-- (registration is a snapshot).
function ns.Options.Register()
    local modules = {
        { key = "General", title = "General",
          description = "Modules, the settings every module shares, and profiles.",
          pages = { "General", "Global Settings", "Profiles" },
          buildPage = function(pageName, parent, y)
              if pageName == "Profiles" then return BuildProfiles(pageName, parent, y) end
              if pageName == "Global Settings" then return BuildGlobal(pageName, parent, y) end
              return BuildGeneral(pageName, parent, y)
          end,
          -- Reset is the global settings only; profiles have their own buttons.
          onReset = function() ns.ResetGlobal(); RebuildAll() end },
    }
    -- Only the modules that are on get a row; after a switch the menu is out
    -- of date until Reload to apply (ns.Options.MenuIsCurrent).
    for _, M in ipairs(ns.ModuleList()) do
        if ns.IsModuleEnabled(M.key) then
            modules[#modules + 1] = ModuleSpec(M)
            menuKeys[#menuKeys + 1] = M.key
            inMenu[M.key] = true
        end
    end
    registered = ns.Ellesmere.RegisterPlugin({ label = "Prosecco Additions", modules = modules })
    ns.Log("SESSION", "options registered: %s", tostring(registered))
end

-- False when the active profile has other modules on than the menu shows
-- (after a profile switch, copy, reset or import): the menu catches up at
-- the next reload.
function ns.Options.MenuIsCurrent()
    if not registered then return true end
    for _, M in ipairs(ns.ModuleList()) do
        if (inMenu[M.key] == true) ~= ns.IsModuleEnabled(M.key) then return false end
    end
    return true
end

function ns.Options.Open()
    if not (registered and ns.Ellesmere.OpenPlugin()) then
        ns.Print("the settings could not be opened (in combat, or not registered: see /prosecco log).")
    end
end
