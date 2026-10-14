-- ProseccoAdditions / Core / Border.lua
-- The only border code in the addon: modules draw borders with
-- ns.Border.Apply and build their border menu rows with ns.Border.Rows.
--
-- A border setting has the same shape everywhere:
--   border = { useGlobal = true, style = "solid", size = 1, color = "000000", alpha = 1 }
-- The global one (ns.db.global.border) has no useGlobal. A textured style may
-- have offsetX/offsetY (Ellesmere's Border Width/Height Offset); nil means
-- the texture's default.

local _, ns = ...

ns.Border = {}

-- Ellesmere's ApplyBorderStyle shows/hides the frame it is given (size 0
-- hides it), so the border is drawn on a child holder, never on the frame.
-- Weak keys: the holder goes away with the frame.
local holders = setmetatable({}, { __mode = "k" })

function ns.Border.Resolve(cfg)
    if cfg.useGlobal then return ns.db.global.border end
    return cfg
end

-- `frame` is always one of OUR frames, never a Blizzard or Ellesmere frame.
-- `cfg` is the module's border table, read at call time.
function ns.Border.Apply(frame, cfg)
    local b = ns.Border.Resolve(cfg)
    local holder = holders[frame]
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holders[frame] = holder
    end
    -- The frame's strata may have changed since the holder was made.
    if holder:GetFrameStrata() ~= frame:GetFrameStrata() then holder:SetFrameStrata(frame:GetFrameStrata()) end
    holder:SetFrameLevel(frame:GetFrameLevel() + 1)
    local r, g, bl = ns.HexToRGB(b.color)
    ns.Ellesmere.Border(holder, tonumber(b.size) or 0, r, g, bl, tonumber(b.alpha) or 1, b.style,
        tonumber(b.offsetX), tonumber(b.offsetY))
end

-- The nearest whole pixel (u = one pixel). The 0.001 keeps a value just
-- under half a pixel from rounding differently between passes, as
-- Ellesmere's own snapping does.
local function Snap(v, u) return math.floor(v / u + 0.5 + 0.001) * u end
ns.Border.Snap = Snap

-- Places `edge` (OUR frame, a child of `target` or with its effective scale)
-- on whole pixels around `target`, a frame we only read: its rect shrunk by
-- `inset` (l, r, t, b in the target's units) and grown by `px` pixels per
-- side. Ellesmere's border lines are not pixel-snapped, so a frame whose
-- edges fall between pixels would get blurred lines.
-- Returns false while the target has no position yet.
function ns.Border.Outside(edge, target, px, l, r, t, b)
    local left, right, top, bottom = target:GetLeft(), target:GetRight(), target:GetTop(), target:GetBottom()
    if not (left and right and top and bottom) then return false end
    local u = ns.Ellesmere.PixelUnit(target)
    local grow = (tonumber(px) or 0) * u
    edge:ClearAllPoints()
    edge:SetPoint("TOPLEFT", target, "TOPLEFT", Snap(left + l, u) - grow - left, Snap(top - t, u) + grow - top)
    edge:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", Snap(right - r, u) + grow - right, Snap(bottom + b, u) - grow - bottom)
    return true
end

-- A seam: one border line across a join inside a box, as Ellesmere's "Power
-- Bar Seam". `tex` is OUR texture, `anchor` OUR frame whose top edge is the
-- join. A style with seam art gets it laid as Ellesmere lays it (its line
-- sits in the top 5/32 of the art); solid gets a line just above the join, so
-- it does not cover the first row; other textured styles draw nothing.
-- Returns true when a line was drawn, and its thickness above the join.
function ns.Border.Seam(tex, anchor, cfg)
    local b = ns.Border.Resolve(cfg)
    local px = tonumber(b.size) or 0
    tex:ClearAllPoints()
    if px <= 0 then tex:Hide() return false end
    local es = anchor:GetEffectiveScale()
    local r, g, bl = ns.HexToRGB(b.color)
    local art = ns.Ellesmere.BorderSeamArt(b.style)
    if art then
        local thick = ns.Ellesmere.BorderSeamThickness(b.style, px, es)
        if not thick or thick <= 0 then tex:Hide() return false end
        local raise = ns.Ellesmere.SnapForES(thick * 5 / 32, es)
        tex:SetTexture(art)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(r, g, bl, tonumber(b.alpha) or 1)
        tex:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, raise)
        tex:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, raise)
        tex:SetHeight(thick)
        tex:Show()
        return true, raise, thick   -- the art's line lies in the `raise` above the join
    elseif not ns.Ellesmere.IsTexturedBorder(b.style) then
        local h = px * ns.Ellesmere.PixelUnit(anchor)
        tex:SetColorTexture(r, g, bl, tonumber(b.alpha) or 1)
        tex:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
        tex:SetHeight(h)
        tex:Show()
        return true, h
    end
    tex:Hide()
    return false
end

-- The same across a side-by-side join: one line down the right edge of OUR
-- frame `anchor`. Vertical seam art if the style has it, solid a line just
-- left of the join, other textured styles nothing.
function ns.Border.SeamV(tex, anchor, cfg)
    local b = ns.Border.Resolve(cfg)
    local px = tonumber(b.size) or 0
    tex:ClearAllPoints()
    if px <= 0 then tex:Hide() return false end
    local r, g, bl = ns.HexToRGB(b.color)
    if ns.Ellesmere.BorderSeamV(tex, anchor, b.style, px) then
        tex:SetVertexColor(r, g, bl, tonumber(b.alpha) or 1)
        return tex:IsShown()
    elseif not ns.Ellesmere.IsTexturedBorder(b.style) then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(1, 1, 1, 1)      -- the art's tint would multiply the colour
        tex:SetColorTexture(r, g, bl, tonumber(b.alpha) or 1)
        tex:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
        tex:SetWidth(px * ns.Ellesmere.PixelUnit(anchor))
        tex:Show()
        return true
    end
    tex:Hide()
    return false
end

-- `size` is whole pixels for every style, like Ellesmere's Border Size
-- sliders, so a style pick needs no rebuild.
local SIZE_MAX = 32

-- The border rows of a settings page: Use Global Border (not on the global
-- page), Style, Size and Color. While the border follows the global one only
-- the toggle is shown. `getCfg` returns the border table at call time (a
-- profile switch replaces it); `onChange` runs after every change.
-- Returns the new y.
function ns.Border.Rows(W, parent, y, getCfg, onChange, isGlobal)
    local follows = not isGlobal and getCfg().useGlobal == true
    local function set(key, v)
        getCfg()[key] = v
        onChange()
    end

    local cells = {}
    if not isGlobal then
        cells[#cells + 1] = { type = "toggle", text = "Use Global Border",
            tooltip = "Draw this border with the settings on the Global Settings page.",
            getValue = function() return getCfg().useGlobal == true end,
            setValue = function(v)
                set("useGlobal", v and true or false)
                ns.Ellesmere.RebuildPage()      -- the rows below show or hide
            end }
    end
    if follows then
        return ns.Rows(W, parent, y, cells[1])
    end
    local values, order = ns.Ellesmere.BorderStyles()
    cells[#cells + 1] = { type = "dropdown", text = "Border Style", values = values, order = order,
        getValue = function() return getCfg().style end,
        setValue = function(v)
            -- A new texture starts from its own offsets, as in Ellesmere's menus.
            getCfg().offsetX, getCfg().offsetY = nil, nil
            set("style", v)
            ns.Ellesmere.RebuildPage()      -- the offset row is there only for a textured style
        end }
    cells[#cells + 1] = { type = "slider", text = "Border Size", min = 0, max = SIZE_MAX, step = 1,
        tooltip = "Border size in pixels; for a textured style this is the size of its edge art. 0 hides the border.",
        getValue = function() return getCfg().size end,
        setValue = function(v) set("size", v) end }
    cells[#cells + 1] = { type = "colorpicker", text = "Border Color", hasAlpha = true,
        getValue = function()
            local c = getCfg()
            local r, g, b = ns.HexToRGB(c.color)
            return r, g, b, tonumber(c.alpha) or 1
        end,
        setValue = function(r, g, b, a)
            local c = getCfg()
            c.color = ns.RGBToHex(r, g, b)
            c.alpha = a or 1
            onChange()
        end }

    y = ns.Rows(W, parent, y, unpack(cells))
    if ns.Ellesmere.IsTexturedBorder(getCfg().style) then
        local left, right = ns.Ellesmere.BorderOffsetCells({
            getTex = function() return getCfg().style end,
            getPx = function() return tonumber(getCfg().size) or 0 end,
            getX = function() return getCfg().offsetX end,
            setX = function(v) getCfg().offsetX = v end,
            getY = function() return getCfg().offsetY end,
            setY = function(v) getCfg().offsetY = v end,
            apply = onChange,
        })
        y = ns.Rows(W, parent, y, left, right)
    end
    return y
end
