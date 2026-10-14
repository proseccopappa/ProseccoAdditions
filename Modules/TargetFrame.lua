-- ProseccoUI / Modules / TargetFrame.lua
-- Empty frames with Ellesmere's borders where its target frame stands while
-- there is no target, and where its player cast bar stands while nothing is
-- cast. Each has its own switch.
--
-- Ellesmere's target frame is a secure unit button that its unit watch hides
-- with no target, with no option to stay shown. Ours is a plain frame on
-- UIParent anchored to it (read, never changed), so it is shown and hidden
-- in combat too. Its border is Ellesmere's, taken again when Ellesmere's
-- options close. Resource Bars' Cast Bar is not secure and only fades out
-- when idle, so ours shows from the player's cast events.
--
-- Off: the frames are hidden, no events.

local ADDON, ns = ...

local M = ns.RegisterModule("targetFrame", {
    -- Named for what it adds; the key stays targetFrame so saved settings carry
    -- over.
    title       = "Frame backgrounds",
    description = "Empty frames with Ellesmere's borders where its target frame and its cast bar stand while you have no target or cast nothing.",
    pages       = { "Frame backgrounds" },
    defaults    = {
        -- Which empty frames: the target frame's and the cast bar's.
        target = true,
        castbar = false,
        -- Every background the health bar's, or this colour and alpha.
        healthBackground = true,
        bgColor = "111111", bgAlpha = 1,
        -- Percent: the alpha of the backgrounds, the power bar's
        -- included; borders, seam, divider and the portrait keep theirs.
        alpha = 100,
        -- Ellesmere's colours for border, ring and Outer Ring, or these.
        ellesmereColors = true,
        borderColor = "000000", ringColor = "000000", outerRingColor = "000000",
    },
})

local function DB() return ns.db.modules.targetFrame end


local frame, host
local LayoutParts
local active = false

local function Update()
    local target = ns.Ellesmere.TargetFrame()
    if not (active and target and frame and DB().target ~= false) then
        if frame then frame:Hide() end
        return
    end
    -- Ellesmere's frames hide in pet battles.
    local show = not UnitExists("target") and not (C_PetBattles and C_PetBattles.IsInBattle())
    frame:SetShown(show)
end

-- The power bar and the portrait, copied from Ellesmere's as empty boxes on
-- the places of its parts: its Power Bar Seam, a detached bar's own border,
-- a detached portrait's shape, ring, Outer Ring and Inner Shadow, and an
-- attached portrait's divider. Above our border (the holder is level +1), as
-- Ellesmere's seam and detached parts lie above its border.
-- Not copied: a seam on a power bar above the health bar (ns.Border.Seam
-- draws on a top edge only), the solid strip of an attached power bar's own
-- border, the seam's 1 px gap at the divider, and Ellesmere's offset
-- defaults for a textured detached power border.
local over, powerBox, portraitBox
local PORTRAIT_BG = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Portraits\\portrait_bg_circle.tga"

local function Parts()
    if over then return end
    over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints(frame)
    over:EnableMouse(false)
    over.seam = over:CreateTexture(nil, "OVERLAY")
    over.divider = over:CreateTexture(nil, "OVERLAY")
    powerBox = CreateFrame("Frame", nil, frame)
    powerBox:EnableMouse(false)
    powerBox.bg = powerBox:CreateTexture(nil, "BACKGROUND")
    powerBox.bg:SetAllPoints()
    portraitBox = CreateFrame("Frame", nil, frame)
    portraitBox:EnableMouse(false)
    portraitBox.bg = portraitBox:CreateTexture(nil, "BACKGROUND")
    portraitBox.bg:SetAllPoints()
    portraitBox.mask = portraitBox:CreateMaskTexture()
    portraitBox.ring = portraitBox:CreateTexture(nil, "OVERLAY")
    portraitBox.ringBase = portraitBox:CreateTexture(nil, "OVERLAY", nil, -1)
    portraitBox.ringMask = portraitBox:CreateMaskTexture()
    portraitBox.ringBase:AddMaskTexture(portraitBox.ringMask)
    portraitBox.outer = portraitBox:CreateTexture(nil, "OVERLAY", nil, 1)
    portraitBox.shadow = portraitBox:CreateTexture(nil, "ARTWORK", nil, 7)
end

LayoutParts = function(target)
    Parts()
    local level = target:GetFrameLevel()
    over:SetFrameLevel(level + 3)
    local power, backdrop = ns.Ellesmere.TargetParts()
    local look = ns.Ellesmere.TargetLook()
    -- Every background is the health bar's, or the colour set here.
    local hr, hg, hb, ha = unpack(look.healthBg)
    local d = DB()
    if not d.healthBackground then
        hr, hg, hb = ns.HexToRGB(d.bgColor)
        ha = tonumber(d.bgAlpha) or 1
    end
    -- The Alpha slider fades the backgrounds only, not a detached portrait's,
    -- which lies over the frame: faded, the frame showed through it.
    local fullA = ha
    ha = ha * math.max(0, math.min(100, tonumber(d.alpha) or 100)) / 100
    frame.bg:SetColorTexture(hr, hg, hb, ha)
    -- Own colours: nil keeps Ellesmere's.
    local own = d.ellesmereColors == false
    local borderHex = own and d.borderColor or nil
    local ringHex = own and d.ringColor or nil
    local outerHex = own and d.outerRingColor or nil
    local border = ns.Ellesmere.TargetBorder()
    if borderHex then border.color = borderHex end

    -- Power bar: attached, the seam on its join; detached, a box of its own
    -- with its own border.
    over.seam:Hide()
    powerBox:Hide()
    if power then
        if look.powerAttached then
            -- Our frame's background already covers it with the same
            -- colour; a second layer would darken it.
            if look.powerSeam and not look.powerAbove and ns.Ellesmere.BorderSeamArt(border.style) then
                ns.Border.Seam(over.seam, power, border)
            end
        else
            powerBox:ClearAllPoints()
            powerBox:SetAllPoints(power)
            powerBox:SetFrameLevel(level + 4)
            powerBox.bg:SetColorTexture(hr, hg, hb, ha)
            if look.powerBorder then
                if borderHex then look.powerBorder.color = borderHex end
                ns.Border.Apply(powerBox, look.powerBorder)
            end
            powerBox:Show()
        end
    end

    -- Portrait: detached, a box with its shape, rings and shadow; attached,
    -- inside our frame with the divider.
    portraitBox:Hide()
    over.divider:Hide()
    if backdrop then
        portraitBox:ClearAllPoints()
        portraitBox:SetAllPoints(backdrop)
        -- A round detached portrait's background is a white shaded
        -- disc, tinted with the background colour; the shape mask still
        -- clips it. Other shapes get a plain colour.
        if look.roundPortrait then
            portraitBox.bg:SetTexture(PORTRAIT_BG)
            portraitBox.bg:SetVertexColor(hr, hg, hb, fullA)
        else
            portraitBox.bg:SetVertexColor(1, 1, 1, 1)     -- clear the disc's tint
            portraitBox.bg:SetColorTexture(hr, hg, hb, fullA)
        end
        portraitBox.outer:Hide()
        portraitBox.shadow:Hide()
        if look.detached then
            portraitBox:SetFrameLevel(level + 5)
            ns.Ellesmere.ShapePortrait(portraitBox, ringHex)
            ns.Ellesmere.PortraitExtras(portraitBox, outerHex)
        else
            -- Under our border, as Ellesmere's portrait.
            portraitBox:SetFrameLevel(level)
            ns.Ellesmere.SquarePortrait(portraitBox)
            portraitBox.bg:Hide()       -- inside our frame, whose background covers it
            if look.divider then ns.Ellesmere.PortraitDivider(over.divider, backdrop, look.portraitRight, borderHex) end
        end
        portraitBox:Show()
    end
end

local function Layout()
    local target = ns.Ellesmere.TargetFrame()
    if not (frame and target) then return end
    frame:ClearAllPoints()
    frame:SetAllPoints(target)
    frame:SetFrameStrata(target:GetFrameStrata())
    frame:SetFrameLevel(target:GetFrameLevel())
    local border = ns.Ellesmere.TargetBorder()
    if DB().ellesmereColors == false then border.color = DB().borderColor end
    ns.Border.Apply(frame, border)
    LayoutParts(target)
end

-- The empty cast bar. `casting` is set by the player's cast events: a
-- start hides ours, an end shows it again unless another cast or channel
-- still runs (a failed second cast fires while the first goes on).
local cast, castHost
local casting = false
local castAlways = false    -- Ellesmere's Always Show: its own bar already stands there empty
-- No empower events: Classic content has no empowered spells.
local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }

-- Still casting or channelling. A secret answer counts as no cast, so the end
-- event that asked is trusted (Assumed: the player's own cast info is not
-- secret in Forever).
local function StillCasting()
    local name = UnitCastingInfo("player")
    if issecretvalue(name) then return false end
    if name ~= nil then return true end
    local channel = UnitChannelInfo("player")
    if issecretvalue(channel) then return false end
    return channel ~= nil
end

local function UpdateCast()
    if not cast then return end
    local bar = ns.Ellesmere.PlayerCastBar()
    local show = active and bar ~= nil and DB().castbar == true and not casting and not castAlways
        and not (C_PetBattles and C_PetBattles.IsInBattle())
    cast:SetShown(show)
end

local function LayoutCast()
    local bar = ns.Ellesmere.PlayerCastBar()
    if not (cast and bar) then return end
    cast:ClearAllPoints()
    cast:SetAllPoints(bar)
    -- Under Ellesmere's bar, which is faded out while ours shows.
    cast:SetFrameStrata(bar:GetFrameStrata())
    cast:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 2))
    local d = DB()
    local border, bg, always = ns.Ellesmere.CastBarLook()
    castAlways = always
    if d.ellesmereColors == false then border.color = d.borderColor end
    local r, g, b, a = unpack(bg)
    if not d.healthBackground then
        r, g, b = ns.HexToRGB(d.bgColor)
        a = tonumber(d.bgAlpha) or 1
    end
    a = a * math.max(0, math.min(100, tonumber(d.alpha) or 100)) / 100
    cast.bg:SetColorTexture(r, g, b, a)
    ns.Border.Apply(cast, border)
end

local function OnCastEvent(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Resource Bars may make its bar after our first Apply at
        -- login (Assumed).
        casting = StillCasting()
        LayoutCast()
    elseif CAST_START[event] then
        casting = true
    elseif event ~= "PET_BATTLE_OPENING_START" and event ~= "PET_BATTLE_CLOSE" then
        casting = StillCasting()
    end
    UpdateCast()
end

-- Registered only while the switch is on: off does no work.
local function ApplyCast()
    local on = active and DB().castbar == true
    if on then
        if not cast then
            cast = CreateFrame("Frame", nil, UIParent)
            cast:EnableMouse(false)
            cast.bg = cast:CreateTexture(nil, "BACKGROUND")
            cast.bg:SetAllPoints()
            cast:Hide()
            castHost = CreateFrame("Frame")
            castHost:SetScript("OnEvent", OnCastEvent)
        end
        for _, e in ipairs(CAST_EVENTS) do castHost:RegisterUnitEvent(e, "player") end
        castHost:RegisterEvent("PLAYER_ENTERING_WORLD")
        castHost:RegisterEvent("PET_BATTLE_OPENING_START")
        castHost:RegisterEvent("PET_BATTLE_CLOSE")
        casting = StillCasting()
        LayoutCast()
    elseif castHost then
        castHost:UnregisterAllEvents()
    end
    UpdateCast()
end

-- PLAYER_ENTERING_WORLD: Ellesmere may spawn its target frame after our
-- first Apply at login (Assumed).
local function OnEvent(_, event)
    if event == "PLAYER_ENTERING_WORLD" then Layout() end
    Update()
end

-- Ellesmere's options may have changed the target frame's or the cast
-- bar's border.
local function OnMenuClosed()
    if not active then return end
    if DB().target ~= false then Layout() end
    if DB().castbar == true then LayoutCast(); UpdateCast() end
end

-- The target frame's events only while its switch is on.
local function ApplyTarget()
    if active and DB().target ~= false then
        if not frame then
            frame = CreateFrame("Frame", nil, UIParent)
            frame:EnableMouse(false)
            frame.bg = frame:CreateTexture(nil, "BACKGROUND")
            frame.bg:SetAllPoints()
            frame:Hide()
            host = CreateFrame("Frame")
            host:SetScript("OnEvent", OnEvent)
        end
        host:RegisterEvent("PLAYER_TARGET_CHANGED")
        host:RegisterEvent("PLAYER_ENTERING_WORLD")
        host:RegisterEvent("PET_BATTLE_OPENING_START")
        host:RegisterEvent("PET_BATTLE_CLOSE")
        Layout()
    elseif host then
        host:UnregisterAllEvents()
    end
    Update()
end

function M:Enable()
    active = true
    ns.Ellesmere.OnMenuClosed(OnMenuClosed)
end

function M:Apply()
    ApplyTarget()
    ApplyCast()
end

function M:Disable()
    active = false
    ApplyTarget()
    ApplyCast()
end

function M:BuildPage(_, parent, y, W)
    local _, h
    if DB().target ~= false and not ns.Ellesmere.TargetFrame() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Ellesmere's target frame is not loaded: turn on EllesmereUI Unit Frames with its own target frame." }); y = y - h
    end
    local function changed() ns.Apply() end
    _, h = W:SectionHeader(parent, "ENABLE BACKGROUNDS", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Target background",
          tooltip = "An empty frame with the target frame's border where Ellesmere's target frame stands while you have no target.",
          getValue = function() return DB().target ~= false end,
          setValue = function(v) DB().target = v and true or false; changed() end },
        { type = "toggle", text = "Player castbar",
          tooltip = "An empty bar with the cast bar's border and background where Ellesmere's Cast Bar (Resource Bars) stands while you cast nothing.",
          getValue = function() return DB().castbar == true end,
          setValue = function(v)
              DB().castbar = v and true or false
              changed()
              ns.Ellesmere.RebuildPage()      -- the not-loaded label shows or hides
          end }); y = y - h
    if DB().castbar == true and not ns.Ellesmere.PlayerCastBar() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Ellesmere's Cast Bar is off or not loaded: turn on Resource Bars and its Cast Bar." }); y = y - h
    end
    _, h = W:SectionHeader(parent, "BACKGROUND", y); y = y - h
    y = ns.Rows(W, parent, y,
        { type = "toggle", text = "Use Health Background",
          tooltip = "Every background of the empty target frame is the target frame's health bar background (Ellesmere's Bar Background), and the empty cast bar's is the cast bar's own background. Off: the colour beside, for both.",
          getValue = function() return DB().healthBackground ~= false end,
          setValue = function(v)
              DB().healthBackground = v and true or false
              changed()
              ns.Ellesmere.RebuildPage()      -- the colour row shows or hides
          end },
        ns.BackgroundCell({ text = "Background", cfg = DB, colorKey = "bgColor", alphaKey = "bgAlpha", default = 1,
            follows = function() return DB().healthBackground ~= false end, onChange = changed,
            tooltip = "Colour and alpha of every background of the empty frame." }))
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Alpha", min = 0, max = 100, step = 1,
          tooltip = "The alpha of the empty frames' backgrounds, the power bar's and the cast bar's included. Borders and the detached portrait stay fully shown.",
          getValue = function() return tonumber(DB().alpha) or 100 end,
          setValue = function(v) DB().alpha = v; changed() end },
        { type = "spacer" }); y = y - h
    _, h = W:SectionHeader(parent, "COLOURS", y); y = y - h
    local function followsEllesmere() return DB().ellesmereColors ~= false end
    local function colour(text, key, tip)
        return ns.BackgroundCell({ text = text, cfg = DB, colorKey = key, follows = followsEllesmere, onChange = changed, tooltip = tip })
    end
    y = ns.Rows(W, parent, y,
        { type = "toggle", text = "Use Ellesmere Colours",
          tooltip = "Border, ring and Outer Ring take the colours of Ellesmere's target frame, and the empty cast bar's border the cast bar's.",
          getValue = followsEllesmere,
          setValue = function(v)
              DB().ellesmereColors = v and true or false
              changed()
              ns.Ellesmere.RebuildPage()      -- the colour rows show or hide
          end },
        colour("Border Colour", "borderColor", "The frame's border, the power bar's border and seam, the portrait divider, and the empty cast bar's border."),
        colour("Ring Colour", "ringColor", "The detached portrait's ring."),
        colour("Outer Ring Colour", "outerRingColor", "The detached portrait's Outer Ring."))
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Border, power bar and portrait follow Ellesmere's target frame (Unit Frames, Target), apart from the colours above. Change them there." }); y = y - h
    if not ns.IsModuleEnabled("targetFrame") then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "Frame backgrounds is off: turn it on under Modules on the General page." }); y = y - h
    end
    return y
end

-- For the simulator's tests.
function M.Frame() return frame end
function M.CastFrame() return cast end
function M.CastEvent(event) OnCastEvent(castHost, event) end
function M.Parts() return powerBox, portraitBox end
