-- ProseccoUI / Modules / Volume.lua
-- The Microbar's volume popup (the same module as Microbar.lua, which draws
-- the bar): a slider and an on/off box for each of the five sound channels,
-- opened by a click on the speaker; the wheel on the speaker sets Master.
--
-- The sound CVars are not protected, so they are read and written in combat
-- too, and no frame here is secure. While shown, the popup closes on a click
-- outside it (GLOBAL_MOUSE_DOWN) and repaints on CVAR_UPDATE, which every
-- sound CVar write fires, so changes from Blizzard's options show too.

local _, ns = ...

local M = ns.GetModule("volume")
local DB = M.DB

local CHANNELS = {
    { cvar = "Sound_MasterVolume",   enable = "Sound_EnableAllSound", label = "Master" },
    { cvar = "Sound_SFXVolume",      enable = "Sound_EnableSFX",      label = "Effects" },
    { cvar = "Sound_MusicVolume",    enable = "Sound_EnableMusic",    label = "Music" },
    { cvar = "Sound_AmbienceVolume", enable = "Sound_EnableAmbience", label = "Ambience" },
    { cvar = "Sound_DialogVolume",   enable = "Sound_EnableDialog",   label = "Dialog" },
}

-- Runtime only
local popup, rows
local anchor                -- the speaker button the popup hangs under
local host                  -- event frame while the popup is shown
local refreshing = false    -- set while Refresh paints the sliders

-- ---------------------------------------------------------------------------
-- The CVars
-- ---------------------------------------------------------------------------

-- 0..100. A missing CVar reads as full volume, as in Ellesmere's block.
local function Percent(ch)
    local v = tonumber(GetCVar(ch.cvar)) or 1
    return math.floor(math.max(0, math.min(1, v)) * 100 + 0.5)
end

local function SetPercent(ch, p)
    SetCVar(ch.cvar, math.max(0, math.min(100, p)) / 100)
end

local function IsOn(ch) return GetCVarBool(ch.enable) end

local function Toggle(ch) SetCVar(ch.enable, IsOn(ch) and 0 or 1) end

-- Wheel: 1 %, or 10 % with Shift (Ellesmere's steps).
local function Step(delta) return delta * (IsShiftKeyDown() and 10 or 1) end

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

local function Background(f)
    local hex, a = ns.BackgroundColor(DB().useGlobalBackground, "background", DB().bgColor, tonumber(DB().bgAlpha) or 0.75)
    local r, g, b = ns.HexToRGB(hex)
    f.bg:SetColorTexture(r, g, b, a)
    ns.Border.Apply(f, DB().border)
end

local function Text(parent, size)
    local fs = ns.Media.FontString(parent)
    local font, flags = ns.Ellesmere.Font()
    fs:SetFont(font, size, flags)
    fs:SetTextColor(1, 1, 1, 1)
    return fs
end

-- ---------------------------------------------------------------------------
-- The popup
-- ---------------------------------------------------------------------------

local ROW_H, PAD, SLIDER_H = 30, 8, 10

local function Refresh()
    if not (popup and popup:IsShown()) then return end
    refreshing = true
    for i, ch in ipairs(CHANNELS) do
        local row = rows[i]
        local p, on = Percent(ch), IsOn(ch)
        row.value:SetText(p .. "%")
        if math.abs(row.slider:GetValue() - p) >= 0.5 then row.slider:SetValue(p) end
        row.fill:SetWidth(math.max(0.01, row.track:GetWidth() * p / 100))
        row.mark:SetShown(on)
        local c = on and 1 or 0.5
        row.name:SetTextColor(c, c, c, 1)
        row.slider:SetAlpha(on and 1 or 0.5)
    end
    refreshing = false
end

local function NewRow(i, ch)
    local row = CreateFrame("Frame", nil, popup)
    row.ch = ch
    -- The on/off box: filled while the channel is on.
    local box = CreateFrame("Button", nil, row)
    box:SetSize(12, 12)
    box:SetPoint("TOPLEFT", 0, -1)
    box.edge = box:CreateTexture(nil, "BACKGROUND")
    box.edge:SetAllPoints()
    box.edge:SetColorTexture(0.5, 0.5, 0.5, 1)
    box.inner = box:CreateTexture(nil, "BORDER")
    box.inner:SetPoint("TOPLEFT", 1, -1)
    box.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    box.inner:SetColorTexture(0.08, 0.08, 0.08, 1)
    row.mark = box:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT", 3, -3)
    row.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    row.mark:SetColorTexture(0.85, 0.85, 0.85, 1)
    box:RegisterForClicks("LeftButtonUp")
    box:SetScript("OnClick", function() Toggle(ch) end)
    row.box = box

    row.name = Text(row, 11)
    row.name:SetPoint("LEFT", box, "RIGHT", 6, 0)
    row.name:SetText(ch.label)
    row.value = Text(row, 11)
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetPoint("TOP", box, "TOP", 0, 0)
    row.value:SetJustifyH("RIGHT")

    -- A plain Slider, no template: Blizzard's slider templates differ between
    -- clients.
    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(0, 100)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    s:SetHeight(SLIDER_H)
    s:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
    s:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.track = s:CreateTexture(nil, "BACKGROUND")
    row.track:SetPoint("LEFT", 0, 0)
    row.track:SetPoint("RIGHT", 0, 0)
    row.track:SetHeight(4)
    row.track:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    row.fill = s:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
    row.fill:SetHeight(4)
    row.fill:SetColorTexture(0.85, 0.85, 0.85, 1)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = s:GetThumbTexture()
    thumb:SetSize(6, SLIDER_H)
    thumb:SetVertexColor(0.95, 0.95, 0.95, 1)
    -- A value set while Refresh paints is the CVar's own coming back; only the
    -- user's moves write the CVar.
    s:SetScript("OnValueChanged", function(_, v)
        if refreshing then return end
        SetPercent(ch, math.floor(v + 0.5))
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(_, delta) SetPercent(ch, Percent(ch) + Step(delta)) end)
    row.slider = s
    rows[i] = row
    return row
end

local function Layout()
    local w = 200          -- px
    ns.Ellesmere.PixelSize(popup, w, 2 * PAD + #CHANNELS * ROW_H)
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", popup, "RIGHT", -PAD, 0)
        row:SetHeight(ROW_H)
    end
    Background(popup)
end

local function EnsurePopup()
    if popup then return end
    -- HIGH: over Ellesmere's bars and our panels (MEDIUM), under dialogs.
    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("HIGH")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)         -- a click on its background must not fall through to the world
    popup.bg = popup:CreateTexture(nil, "BACKGROUND")
    popup.bg:SetAllPoints()
    popup:Hide()
    rows = {}
    for i, ch in ipairs(CHANNELS) do NewRow(i, ch) end
    Layout()
end

local function ClosePopup()
    if not (popup and popup:IsShown()) then return end
    popup:Hide()
    host:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    host:UnregisterEvent("CVAR_UPDATE")
end

local function OnEvent(_, event, cvar)
    if event == "GLOBAL_MOUSE_DOWN" then
        if popup:IsShown() and not popup:IsMouseOver() and not (anchor and anchor:IsMouseOver()) then ClosePopup() end
    elseif event == "CVAR_UPDATE" then
        -- Only the sound CVars; the event names every CVar written.
        if type(cvar) == "string" and cvar:find("^Sound_") then
            Refresh()
            M.PaintSpeaker()
        end
    end
end

-- Under the bar when there is room, else over it (a bar at the screen's
-- bottom); clamped to the screen either way.
local function Place()
    popup:ClearAllPoints()
    if anchor:GetBottom() and anchor:GetBottom() > popup:GetHeight() + 8 then
        ns.Ellesmere.PixelPoint(popup, "TOP", anchor, "BOTTOM", 0, -4)
    else
        ns.Ellesmere.PixelPoint(popup, "BOTTOM", anchor, "TOP", 0, 4)
    end
end

local function OpenPopup()
    EnsurePopup()
    if not host then
        host = CreateFrame("Frame")
        host:SetScript("OnEvent", function(_, event, ...)
            local a = ...
            xpcall(function() OnEvent(_, event, a) end, ns.ErrorHandler("volume:" .. event))
        end)
    end
    Layout()
    Place()
    popup:Show()
    Refresh()
    host:RegisterEvent("GLOBAL_MOUSE_DOWN")
    host:RegisterEvent("CVAR_UPDATE")
end

-- ---------------------------------------------------------------------------
-- For the bar (Microbar.lua)
-- ---------------------------------------------------------------------------

-- A click on the speaker `button`.
function M.ToggleVolume(button)
    anchor = button
    if popup and popup:IsShown() then ClosePopup() else OpenPopup() end
end

M.CloseVolume = ClosePopup

function M.VolumeShown() return popup ~= nil and popup:IsShown() end

-- The wheel on the speaker: Master.
function M.VolumeWheel(delta)
    SetPercent(CHANNELS[1], Percent(CHANNELS[1]) + Step(delta))
end

-- Master's percent and whether all sound is on, for the speaker's colour and tooltip.
function M.VolumeMaster()
    return Percent(CHANNELS[1]), IsOn(CHANNELS[1])
end

-- All sound on or off (Master's "Enable All Sound"), from a right-click on
-- the speaker. A plain CVar, so also in combat.
function M.ToggleMute()
    Toggle(CHANNELS[1])
    M.PaintSpeaker()
    if popup and popup:IsShown() then Refresh() end
end

-- After a settings change: the open popup takes the new width and colours.
function M.ApplyVolume()
    if not (popup and popup:IsShown()) then return end
    Layout()
    Place()
    Refresh()
end

