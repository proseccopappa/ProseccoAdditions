-- ProseccoUI / Core / Presets.lua
-- The looks a new profile can start from (Profiles > NEW PROFILE > Start
-- from). Data only: ns.CreateProfile copies one into a new profile and fills
-- the rest with the installed defaults.
--
-- A preset is look only. ns.PresetProfile drops `enabled`, positions (point,
-- relativePoint, x, y), `unlocked` and each module's `keep` content, and
-- ignores unregistered modules, so a preset never turns a module on and
-- holds nobody's screen coordinates. Anything else here is used as it is.
--
-- Same shape as a profile and as an Export:
--   global  = { border = {...}, background = {...}, headerBackground = {...} }
--   modules = { <module key> = { <setting> = <value>, ... } }

local _, ns = ...

-- =========================================================================
-- PRESET VALUES. Edit here.
-- "Prosecco" is the addon's own look: border, colours, fonts, sizes and
-- spacing. Behaviour (docking, turn-in lines, click actions) stays at the
-- defaults, and Panels is left out: its panels are personal content.
-- =========================================================================
ns.Presets = {
    Prosecco = {
        global = {
            border = { style = "pixels", size = 16, color = "404040", alpha = 1 },
            background = { color = "000000", alpha = 0.5 },
            headerBackground = { color = "363636", alpha = 1 },
        },
        modules = {
            questTracker = {
                width = 300, maxHeight = 389, fixedHeight = true, padding = 6,
                bgColor = "090909", bgAlpha = 0.75, useGlobalBackground = true,
                font = "", outline = "OUTLINE",
                headerSize = 15, titleSize = 14, objectiveSize = 12, headerHeight = 26,
                headerSeam = true, objectiveSpacing = 1,
                xpColor = "8E65BB", xpAlpha = 1, xpSize = 10, itemSize = 26,
                highlightColor = "3F99FF", highlightAlpha = 0.25, rxpDockGap = 3,
                completedSize = 28,
            },
            rxpTheme = {
                font = "", outline = "OUTLINE",
                headerBgColor = "404040", headerBgAlpha = 1,
                bodyColor = "000000", bodyAlpha = 0.295,  -- same as the step list
                stepListColor = "000000", stepListAlpha = 0.295, stepGap = 7,
                winColor = "000000", winAlpha = 0.53,
                useGlobalBackground = false,
                badgePadding = 1, headerDrop = 3, sidePadding = 2,
                winPadding = 2, winTitlePadding = 1,
                hideVersion = true, footerMouseover = true, hideLogos = true, centerHeader = true,
                rowColor = "262626", rowAlpha = 0.9,
                rowBorder = true, rowBorderColor = "000000", rowBorderAlpha = 1,
                scrollOutside = true, scrollMouseover = true,
                accentColor = "4D4D4D", pinColor = "D9D9D9", textColor = "FFFFFF",
                arrowTexture = "bordered", arrowColor = "404040",
            },
            chat = {
                padding = 8, topPadding = 0, tabGap = 8, seam = true,
            },
            damageMeter = {
                useGlobalBackground = true,
                damage = { padding = 4, bgColor = "000000", bgAlpha = 0.75, seam = true,
                    header = { height = 26, gap = 7, bgColor = "1B1B1B", bgAlpha = 1 } },
            },
            volume = {
                bgColor = "000000", bgAlpha = 0.75, useGlobalBackground = true,
            },
        },
    },
}
