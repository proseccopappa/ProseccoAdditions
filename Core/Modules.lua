-- ProseccoUI / Core / Modules.lua
-- The module registry and the one on/off path.
--
-- A module file registers itself while it loads and does nothing else:
--   local M = ns.RegisterModule("panels", {
--       title       = "Panels",
--       description = "...",      -- the switch's tooltip on the General tab
--       pages       = { "Panels" },
--       defaults    = { list = {}, nextId = 1 }, -- `enabled = false` is added
--       affects     = { "Hides Blizzard's quest list." }, -- nil: no popup
--       affectsOff  = { "Blizzard's quest list shows again." }, -- off popup
--       reload      = true,       -- on/off needs a /reload
--       locked      = "reason",   -- cannot be switched on; off everywhere
--       keep        = { "list", "nextId" }, -- content: kept by page Reset
--   })
--   function M:Enable() end   -- lazy, idempotent. Returns false, before doing
--                             -- anything, when an addon it needs is missing.
--   function M:Disable() end  -- removes what is visible (or reload = true)
--   function M:Apply() end    -- reads ns.db.modules.<key>; any number of runs
--   function M:BuildPage(pageName, parent, y, W) ... return y end -- new y
-- Optional, never at login:
--   function M:SwitchedOn() end  -- turned on by the user or a profile
--                                -- switch/copy/import, after Enable worked
--   function M:ProfileSwitched() end  -- a profile switch/copy/import with
--                                     -- the module on in both profiles
--   function M:CheckImport(cfg, path) end  -- an imported profile's settings,
--       before anything is replaced: true, or false and the bad value's path
--       (Core checks types against the defaults; this is for content)
--   function M:GetHeaderBuilder(pageName) end  -- a fixed header for a page
--   function M:PageShown(pageName) end  -- Ellesmere shows a cached page again
--
-- Core never names a module. A module never reads another module's table.

local _, ns = ...

local list, byKey = {}, {}
local running = {}      -- key -> true from a successful Enable to the next Disable
-- key -> why the last Enable did not start the module: "error" (it threw) or
-- "missing" (it returned false). Not retried until /reload or switched off,
-- so the error or chat line is not repeated on every settings change.
local failed = {}
-- Why no module may start this session (Integrations sets it while loading,
-- before the first Apply); nil: they may.
local blocked
function ns.BlockModules(reason) blocked = reason end
function ns.ModulesBlocked() return blocked ~= nil end

function ns.RegisterModule(key, def)
    assert(type(key) == "string" and key:match("^%a[%w_]*$"), "ProseccoAdditions: bad module key")
    assert(not byKey[key], "ProseccoAdditions: module registered twice: " .. key)
    -- Ellesmere refuses the whole plugin on a duplicate key or a missing title,
    -- which would take the core pages with it.
    assert(key ~= "General" and key ~= "Profiles", "ProseccoAdditions: module key taken by the core: " .. key)
    assert(type(def.title) == "string" and type(def.pages) == "table", "ProseccoAdditions: module needs title and pages: " .. key)
    def.key = key
    def.defaults = def.defaults or {}
    if def.defaults.enabled == nil then def.defaults.enabled = false end   -- every module default OFF
    list[#list + 1] = def
    byKey[key] = def
    return def
end

function ns.ModuleList() return list end
function ns.GetModule(key) return byKey[key] end
-- A `locked` module is off in every profile; the saved `enabled` is kept for
-- when the lock is lifted.
function ns.IsModuleEnabled(key) return ns.db.modules[key].enabled == true and not byKey[key].locked end

-- This session's state, for /pui status: "on", "FAILED" (Enable threw),
-- "not started" (Enable returned false), "locked" or "off".
function ns.ModuleState(key)
    if failed[key] == "error" then return "FAILED" end
    if failed[key] == "missing" then return "not started" end
    if running[key] then return "on" end
    if byKey[key].locked then return "locked" end
    return "off"
end

-- One broken module must not take the others down: the error is logged with
-- a stack and still shown by BugSack. Returns ok, then the method's result.
local function Call(M, method)
    if type(M[method]) ~= "function" then return true end
    return xpcall(function() return M[method](M) end, ns.ErrorHandler(M.key .. ":" .. method))
end

-- Brings every module in line with the active profile (Enable/Disable where
-- `enabled` and the running state differ), then redraws the running ones.
-- Runs at login, after every settings change and after a profile switch.
-- Returns the titles of `reload` modules that changed state. `switched` (a
-- profile switch, copy or import) also runs SwitchedOn for modules turned on.
function ns.Apply(atLogin, switched)
    local needReload, status = {}, {}
    for _, M in ipairs(list) do
        local want = ns.IsModuleEnabled(M.key)
        if not want and failed[M.key] then
            -- Switched off after an Enable that did not start it: Disable
            -- gives back what the module took in other addons. Disable is
            -- idempotent.
            failed[M.key] = nil
            Call(M, "Disable")
            if M.reload and not atLogin then needReload[#needReload + 1] = M.title end
        end
        if want ~= (running[M.key] == true) and not failed[M.key] then
            if want then
                local ok, started = true, false
                if not blocked then ok, started = Call(M, "Enable") end
                -- A failed Enable is not running (no Apply on half a module)
                -- and is not retried on every settings change; nor is one
                -- that returned false.
                running[M.key] = (ok and started ~= false) or nil
                failed[M.key] = (not ok and "error") or (started == false and "missing") or nil
                if started == false and ok then
                    status[#status + 1] = M.key .. " not started"
                elseif not ok then
                    status[#status + 1] = M.key .. " FAILED"
                    -- Take down what the half Enable registered, or it keeps
                    -- working while off. The other addons' values stay taken:
                    -- the module is still on in the profile and runs again
                    -- after a /reload.
                    ns.HoldOwned(true)
                    Call(M, "Disable")
                    ns.HoldOwned(false)
                elseif switched then
                    Call(M, "SwitchedOn")
                end
            else
                Call(M, "Disable")
                running[M.key] = nil
            end
            if M.reload and not atLogin then needReload[#needReload + 1] = M.title end
        elseif switched and running[M.key] then
            -- On in both profiles: what the module owns in another addon can
            -- still differ between them (e.g. Damage Meter's Detached Header).
            Call(M, "ProfileSwitched")
        end
        if running[M.key] then
            Call(M, "Apply")
            status[#status + 1] = M.key
        end
    end
    if atLogin and blocked then ns.Print(blocked) end
    if atLogin then
        ns.Log("SESSION", "modules on: %s", #status > 0 and table.concat(status, ", ") or "none")
    end
    return needReload
end

-- Ellesmere's own profile changed under the running modules (a spec switch).
-- Owned values are kept per Ellesmere profile, so the new one gets ours the
-- way a switch writes them: SwitchedOn.
function ns.RewriteOwned()
    for _, M in ipairs(list) do
        if running[M.key] then Call(M, "SwitchedOn") end
    end
end

-- The module toggle on the General tab. The switch takes effect at once; a
-- module's menu row comes and goes only with a reload. A module that changes
-- other addons asks first, in Ellesmere's popup; the others switch without
-- one. Cancel changes nothing. `refresh` redraws the page after either.
function ns.SetModuleEnabled(key, on, refresh)
    local M = byKey[key]
    -- SwitchedOn writes the settings a module owns in another addon only on
    -- this explicit switch, never at login, so a value changed in the other
    -- addon is not silently rewritten. It runs now, reload or not.
    local function commit()
        ns.db.modules[key].enabled = on
        ns.Apply()
        if on and running[key] then Call(M, "SwitchedOn") end
        if refresh then refresh() end
    end
    -- Off has its own list: some on lines read wrong under "undoes".
    local lines = on and M.affects or (M.affectsOff or M.affects)
    if not lines then commit() return end
    local message = (on and "Turning this on:\n" or (M.affectsOff and "Turning this off:\n" or "Turning this off undoes:\n"))
        .. "- " .. table.concat(lines, "\n- ") .. "\n\n"
        .. "Press Reload to apply on the General page to finish."
    ns.Ellesmere.Confirm({
        title       = M.title .. (on and ": turn on" or ": turn off"),
        message     = message,
        confirmText = on and "Turn on" or "Turn off",
        onConfirm   = commit,
        onCancel    = refresh,
    })
end
