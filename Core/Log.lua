-- ProseccoUI / Core / Log.lua
-- Debug log: a rolling list of text lines in ProseccoUIDB.log.lines (outside
-- the profiles), written to disk on /reload or logout so it can be read
-- outside the game. ProseccoUI errors, blocked actions and ns.Log land here.
--   ns.Log("Panels", "panel %d at %d,%d", id, x, y)
--   /pui mark <text>   drop a marker, then /reload
--   /pui log [n]       show the last lines;  /pui log clear | on | off

local ADDON, ns = ...

local LOG_MAX = 400
local pending = {}          -- lines logged before ProseccoUIDB exists
local sessionStart = GetTime()
local seenErrors = {}       -- message -> line index: a looping error is counted
local justLogged            -- an error our xpcall logged; the global hook skips it once

-- ProseccoUIDB is nil until our ADDON_LOADED; until then lines wait in `pending`.
local function Store()
    local db = ProseccoUIDB
    if type(db) ~= "table" then return pending end
    if type(db.log) ~= "table" then db.log = {} end
    if type(db.log.lines) ~= "table" then db.log.lines = {} end
    local lines = db.log.lines
    if #pending > 0 then
        for _, l in ipairs(pending) do lines[#lines + 1] = l end
        wipe(pending)
    end
    return lines
end

local function Enabled()
    local db = ProseccoUIDB
    return not (type(db) == "table" and type(db.log) == "table" and db.log.enabled == false)
end

local function Push(line)
    local lines = Store()
    lines[#lines + 1] = line
    local dropped = 0
    while #lines > LOG_MAX do table.remove(lines, 1); dropped = dropped + 1 end
    if dropped > 0 then
        -- Keep the repeat counter pointing at the right lines.
        for m, i in pairs(seenErrors) do
            seenErrors[m] = (i - dropped > 0) and (i - dropped) or nil
        end
    end
    return #lines
end

local function Stamp()
    return ("%s +%.1fs"):format(date("%H:%M:%S"), GetTime() - sessionStart)
end

-- Errors, markers and the session header are kept even with the log switched off.
function ns.Log(tag, msg, ...)
    if not Enabled() and tag ~= "ERROR" and tag ~= "MARK" and tag ~= "SESSION" then return end
    msg = tostring(msg)
    if select("#", ...) > 0 then msg = msg:format(...) end
    Push(("[%s] %s: %s"):format(Stamp(), tostring(tag or "?"), msg))
end

function ns.LogError(msg, where, stack)
    msg = tostring(msg)
    local lines = Store()
    local idx = seenErrors[msg]
    if idx and lines[idx] then
        local n = tonumber(lines[idx]:match("^%(x(%d+)%)")) or 1
        lines[idx] = ("(x%d) "):format(n + 1) .. lines[idx]:gsub("^%(x%d+%) ", "")
        return
    end
    stack = stack or debugstack(3, 8, 0) or ""
    seenErrors[msg] = Push(("[%s] ERROR%s: %s\n%s"):format(Stamp(),
        where and (" in " .. where) or "", msg, stack))
end

-- Handler for xpcall around our own code: logs, then passes the error to the
-- normal handler (BugSack / the default error frame) so it stays visible.
-- pcall: an error inside an error handler would hide the original one.
function ns.ErrorHandler(where)
    return function(err)
        pcall(ns.LogError, err, where)
        justLogged = err
        local r = geterrorhandler()(err)
        justLogged = nil
        return r
    end
end

-- Catch ProseccoUI errors outside our own xpcalls (scripts, hooks, timers):
-- through BugGrabber when installed, else chained onto the current error
-- handler, which still gets everything. Called once, at login.
function ns.HookErrors()
    local BG = _G.BugGrabber
    -- BugGrabber is another addon's code, hence pcall.
    if BG and type(BG.RegisterCallback) == "function" then
        local ok = pcall(BG.RegisterCallback, ns, "BugGrabber_BugGrabbed", function(_, err)
            local m = type(err) == "table" and err.message or err
            if type(m) == "string" and m:find(ADDON, 1, true) and m ~= justLogged then
                pcall(ns.LogError, m, nil, type(err) == "table" and err.stack and tostring(err.stack) or "")
            end
        end)
        if ok then return "BugGrabber" end
    end
    local prev = geterrorhandler()
    seterrorhandler(function(msg, ...)
        if type(msg) == "string" and msg:find(ADDON, 1, true) and msg ~= justLogged then
            pcall(ns.LogError, msg)
        end
        return prev(msg, ...)
    end)
    return "errorhandler"
end

-- The addons a bug report needs to know about, as "Name=version" for the
-- loaded ones (the session header and /pui status).
local RELATED_ADDONS = { "EllesmereUI", "EllesmereUIChat", "EllesmereUIDamageMeters",
    "EllesmereUIQuestTracker", "EllesmereUIForeverEssentials", "Questie", "RXPGuides",
    "BugSack", "ProseccoTools" }

function ns.LoadedAddons()
    local out = {}
    for _, n in ipairs(RELATED_ADDONS) do
        if C_AddOns.IsAddOnLoaded(n) then
            out[#out + 1] = n .. "=" .. (C_AddOns.GetAddOnMetadata(n, "Version") or "?")
        end
    end
    return out
end

function ns.LogSessionHeader(errorSource)
    local version, build, _, toc = GetBuildInfo()
    Push("")
    Push(("===== SESSION %s  ProseccoAdditions %s  client %s (%s) interface %s ====="):format(
        date("%Y-%m-%d %H:%M:%S"), ns.version, tostring(version), tostring(build), tostring(toc)))
    ns.Log("SESSION", "addons: %s", table.concat(ns.LoadedAddons(), ", "))
    ns.Log("SESSION", "character %s, profile %s, errors via %s",
        ns.CharKey(), ns.ActiveProfileName(), errorSource)
end

-- Taint shows up as a blocked action, not as a Lua error.
local blockFrame = CreateFrame("Frame")
blockFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
blockFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockFrame:SetScript("OnEvent", function(_, event, who, func)
    if who == ADDON then ns.Log("ERROR", "%s: %s (taint)", event, tostring(func)) end
end)

-- /pui log [n | clear | on | off]
function ns.LogCommand(arg)
    local lines = Store()
    if arg == "clear" then
        wipe(lines); wipe(seenErrors)
        ns.Print("debug log cleared.")
    elseif arg == "off" or arg == "on" then
        ProseccoUIDB.log.enabled = (arg == "on")
        ns.Print("debug log " .. arg .. " (errors and markers are always kept).")
    else
        local n = tonumber(arg) or 15
        ns.Print(("last %d of %d log lines:"):format(math.min(n, #lines), #lines))
        for i = math.max(1, #lines - n + 1), #lines do
            print("  " .. (lines[i]:match("^[^\n]*") or ""))
        end
    end
end
