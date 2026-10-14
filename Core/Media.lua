-- ProseccoUI / Core / Media.lua
-- Registers the files in Media/Manifest.lua with LibSharedMedia (shipped with
-- EllesmereUI). Ellesmere's dropdowns list every SharedMedia file and pick up
-- late registrations, so registering is all it takes. Not a module: it only
-- adds names to a list.

local ADDON, ns = ...

ns.Media = {}

local DIR = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- EllesmereUI is a dependency and loads first, so LibSharedMedia exists here;
-- if it does not, LibStub raises a visible error.
local LSM = LibStub("LibSharedMedia-3.0")

for mediaType, files in pairs(ns.MediaManifest) do
    for name, file in pairs(files) do
        LSM:Register(mediaType, name, DIR .. file)
    end
end

-- Path of a font by its SharedMedia name. Modules store names, never paths.
function ns.Media.Font(name)
    return LSM:Fetch("font", name)
end

-- Every SharedMedia font, for a dropdown: values (name -> label) and order,
-- new tables per call. "" is Ellesmere's own font; with `withGlobal`,
-- "global" is the Global Font on the General page.
function ns.Media.FontList(withGlobal)
    local values, order = { [""] = "Ellesmere's font" }, { "" }
    if withGlobal then
        values.global = "Global font"
        table.insert(order, 1, "global")
    end
    for _, name in ipairs(LSM:List("font")) do
        values[name] = name
        order[#order + 1] = name
    end
    return values, order
end

-- The path of a font dropdown's value: "global" the General page's face,
-- "" (or nil) Ellesmere's font, anything else a SharedMedia name.
function ns.Media.FontPath(name)
    if name == "global" then name = ns.db.global.font.face end
    if name and name ~= "" then return ns.Media.Font(name) end
    return (ns.Ellesmere.Font())
end

-- The outline modes, as Ellesmere's Outline Mode: "shadow" is no outline
-- with a drop shadow, and "ellesmere" takes Ellesmere's outline and, when its
-- mode draws one, its shadow.
local OUTLINE_VALUES = { ellesmere = "Ellesmere's outline", none = "None", shadow = "Shadow",
    OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" }
local OUTLINE_ORDER = { "ellesmere", "none", "shadow", "OUTLINE", "THICKOUTLINE" }

-- values, order for an outline dropdown, new tables per call; with
-- `withGlobal`, "global" first for the Global Outline on the General page.
function ns.Media.OutlineList(withGlobal)
    local values, order = {}, {}
    if withGlobal then
        values.global = "Global outline"
        order[1] = "global"
    end
    for _, k in ipairs(OUTLINE_ORDER) do
        values[k] = OUTLINE_VALUES[k]
        order[#order + 1] = k
    end
    return values, order
end

-- An outline dropdown's value as SetFont flags and whether the text gets a
-- drop shadow. Anything not listed (a hand-edited value) is Ellesmere's.
function ns.Media.Outline(mode)
    if mode == "global" then mode = ns.db.global.font.outline end
    if mode == "none" then return "", false end
    if mode == "shadow" then return "", true end
    if mode == "OUTLINE" or mode == "THICKOUTLINE" then return mode, false end
    local _, flags = ns.Ellesmere.Font()
    return flags or "", ns.Ellesmere.FontUseShadow()
end

-- A FontString that already has a font: SetText on a new FontString throws
-- "Font not set", so every text of ours is created here. The module's
-- styling still sets the real font; a forgotten styling call shows the
-- game's standard font instead of failing.
function ns.Media.FontString(parent, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    return fs
end
