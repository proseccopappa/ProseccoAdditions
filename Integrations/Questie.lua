-- ProseccoAdditions / Integrations / Questie.lua
-- Everything ProseccoAdditions touches in Questie goes through this file: only
-- Questie.db.profile.trackerEnabled and LibQuestieDB.
--
-- Questie builds its tracker at login only while trackerEnabled is on, so a
-- change shows after a /reload. QuestieTracker:Disable is not called: it
-- reloads the UI and clears Questie's lists itself.

local _, ns = ...

local Q = {}
ns.Questie = Q

-- Questie's active profile table (AceDB), nil when Questie is not loaded.
local function Profile()
    local q = _G.Questie
    local db = type(q) == "table" and q.db
    local p = type(db) == "table" and db.profile
    return type(p) == "table" and p or nil
end

-- The owned-setting interface for Core's TakeOwned/GiveBackOwned (target
-- "questie"). Questie keeps the value in its active profile, so no profile
-- name is stored: a value given back goes into the profile active then.
function Q.OwnedProfile() return nil end

-- Returns available, value (nil = not set, Questie's default applies).
function Q.ReadOwned(_, _, key)
    local p = Profile()
    if not p then return false end
    return true, p[key]
end

-- Returns false when Questie is not loaded.
function Q.WriteOwned(_, _, key, value)
    local p = Profile()
    if not p then return false end
    p[key] = value
    return true
end

-- The turn-in NPC and its zone for a quest, from LibQuestieDB: a global from
-- the QuestieDB addon, not a LibStub library. finishedBy(id) is
-- { [1]=npcIds, [2]=objectIds }; the first NPC is shown, as Questie's quest
-- link tooltip does. The zone id is an area id (C_Map.GetAreaInfo, not
-- GetMapInfo). A turn-in never changes in a session, so it is cached.
local turnIn = {}

local function Lib()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then return nil end
    -- Contract 3 is what Questie 12 requires of QuestieDB. Another version may
    -- answer differently; then nothing is shown rather than guessing its API.
    if not lib.RequireContract(3) then return nil end
    return lib
end

-- Returns npcName, zoneName; both can be nil (QuestieDB missing, object
-- finisher, or no zone). Never errors when QuestieDB is absent.
function Q.TurnIn(questId)
    local hit = turnIn[questId]
    if hit ~= nil then
        if hit == false then return nil end
        return hit[1], hit[2]
    end
    local lib = Lib()
    if not lib then return nil end      -- not cached: retried once QuestieDB loads
    local fb = lib.Quest and lib.Quest.finishedBy and lib.Quest.finishedBy(questId)
    local npcId = type(fb) == "table" and type(fb[1]) == "table" and fb[1][1]
    if type(npcId) ~= "number" then
        -- Object finisher or none: a firm no, cached so it is not decoded again.
        turnIn[questId] = false
        return nil
    end
    local name = lib.Npc and lib.Npc.name and lib.Npc.name(npcId)
    if type(name) ~= "string" then
        turnIn[questId] = false
        return nil
    end
    local z = lib.Npc.zoneID and lib.Npc.zoneID(npcId)
    if not z or z == 0 then
        -- Questie's fallback when the NPC has no zone: the quest's zoneOrSort,
        -- where a negative value is a sort key, not a zone.
        z = lib.Quest.zoneOrSort and lib.Quest.zoneOrSort(questId)
    end
    local zone
    if type(z) == "number" and z > 0 then zone = C_Map.GetAreaInfo(z) end
    turnIn[questId] = { name, zone }
    return name, zone
end

ns.RegisterOwner("questie", Q)
