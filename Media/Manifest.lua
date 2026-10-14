-- ProseccoAdditions / Media / Manifest.lua
-- Every file in Media/ that is registered with LibSharedMedia, by type.
-- WoW cannot list a folder, so a new file needs a line here, and the game
-- must be restarted (not just /reload) to load a file added since it started.
--
--   [type] = { ["Name shown in dropdowns"] = "path under Media\\" }
-- Types are LibSharedMedia's: font, statusbar, border, background, sound.
-- Media/RXP is not listed: the RXP Theme module loads those files by path
-- (tools/rxp_textures.py draws them).

local _, ns = ...

ns.MediaManifest = {
    font = {
        ["Prosecco"]            = "Fonts\\Prosecco-Regular.otf",
        ["Prosecco ExtraLight"] = "Fonts\\Prosecco-ExtraLight.otf",
        ["Prosecco Light"]      = "Fonts\\Prosecco-Light.otf",
        ["Prosecco Medium"]     = "Fonts\\Prosecco-Medium.otf",
        ["Prosecco SemiBold"]   = "Fonts\\Prosecco-SemiBold.otf",
        ["Prosecco Bold"]       = "Fonts\\Prosecco-Bold.otf",
        ["Prosecco Caps"]       = "Fonts\\ProseccoCaps.otf",
    },
}
