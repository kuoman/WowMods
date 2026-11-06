-- Minimal fake of the WoW client API, just enough to load and drive addons.
--
--   local wow = require("wow_mock")
--   wow.install()                       -- fresh world + globals
--   wow.world.trackers = { ... }        -- configure the fake client
--   wow.load("addons/Gatherer/Gatherer.lua")
--   wow.fire("PLAYER_ENTERING_WORLD")   -- deliver an event to the addon frame
--   wow.advance(0.25)                   -- run C_Timer callbacks that are due

local M = {}

local function newTexture()
    local t = {}
    return setmetatable(t, { __index = function(self, key)
        -- every texture/frame method is a no-op that remembers its last args
        local fn = function(obj, ...)
            obj["_" .. key] = { ... }
        end
        rawset(self, key, fn)
        return fn
    end })
end

local function newFrame(name)
    local f = { name = name, events = {}, scripts = {}, shown = true }

    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:SetScript(hook, fn) self.scripts[hook] = fn end
    function f:GetScript(hook) return self.scripts[hook] end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateTexture()
        local tex = newTexture()
        function tex:SetTexture(path) self.texture = path end
        function tex:SetDesaturated(v) self.desaturated = v end
        return tex
    end

    -- anything else (SetSize, SetPoint, EnableMouse, ...) is a harmless no-op
    return setmetatable(f, { __index = function(self, key)
        local fn = function() end
        rawset(self, key, fn)
        return fn
    end })
end

-- (re)build the fake client; call before every test for a clean slate
function M.install()
    local world = {
        class = "WARRIOR",
        dead = false,
        combat = false,
        skills = {},          -- [skillID] = rank
        professions = {},     -- list of profession names, e.g. { "Mining" }
        trackers = {},        -- { name=, spellID=, active=, type= }
        setTrackingWorks = true,  -- false simulates a cast that fails silently
        setTrackingCalls = {},
        spellNames = {},      -- [spellID] = localized name
        timers = {},
        now = 0,
        printed = {},
    }
    M.world = world
    M.frames = {}

    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        world.printed[#world.printed + 1] = table.concat(parts, " ")
    end

    _G.CreateFrame = function(_, name)
        local f = newFrame(name)
        M.frames[#M.frames + 1] = f
        if name then _G[name] = f end
        return f
    end
    _G.Minimap = newFrame("Minimap")

    _G.GameTooltip = newFrame("GameTooltip")
    function _G.GameTooltip:SetOwner(owner) self.owner = owner end
    function _G.GameTooltip:IsOwned(o) return self.owner == o end
    function _G.GameTooltip:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end

    _G.SlashCmdList = {}

    _G.UnitClass = function() return world.class:sub(1, 1) .. world.class:sub(2):lower(), world.class end
    _G.UnitIsDeadOrGhost = function() return world.dead end
    _G.InCombatLockdown = function() return world.combat end

    _G.C_SkillInfo = {
        GetSkillLineInfoByID = function(id)
            local rank = world.skills[id]
            if rank == nil then return nil end
            return { rank = rank }
        end,
    }
    _G.GetProfessions = function()
        -- real API returns indexes (possibly nil holes); we use 1..n into the list
        local idx = {}
        for i = 1, #world.professions do idx[i] = i end
        return unpack(idx)
    end
    _G.GetProfessionInfo = function(i) return world.professions[i] end

    _G.C_Spell = { GetSpellName = function(id) return world.spellNames[id] end }

    _G.C_Minimap = {
        GetNumTrackingTypes = function() return #world.trackers end,
        GetTrackingInfo = function(i) return world.trackers[i] end,
        SetTracking = function(i, enabled)
            world.setTrackingCalls[#world.setTrackingCalls + 1] = { index = i, enabled = enabled }
            if not world.setTrackingWorks then return end
            -- the two gather spells are mutually exclusive, like in the game
            local chosen = world.trackers[i]
            if enabled and chosen then
                for _, t in ipairs(world.trackers) do t.active = false end
                chosen.active = true
            elseif chosen then
                chosen.active = false
            end
        end,
    }

    _G.C_Timer = {
        After = function(delay, fn)
            world.timers[#world.timers + 1] = { at = world.now + delay, fn = fn }
        end,
    }
end

-- execute the addon file; returns the frame that registered for events
function M.load(path)
    local before = #M.frames
    local chunk = assert(loadfile(path))
    chunk()
    M.frame = M.frames[before + 1]  -- the first frame the addon created
    return M.frame
end

-- deliver an event to the addon's main frame
function M.fire(event, ...)
    assert(M.frame.events[event], "addon did not register for " .. event)
    M.frame.scripts.OnEvent(M.frame, event, ...)
end

-- move the fake clock forward, running due timers in order
function M.advance(seconds)
    local world = M.world
    local target = world.now + seconds
    while true do
        local nextIdx, nextTimer
        for i, t in ipairs(world.timers) do
            if t.at <= target and (not nextTimer or t.at < nextTimer.at) then
                nextIdx, nextTimer = i, t
            end
        end
        if not nextTimer then break end
        table.remove(world.timers, nextIdx)
        world.now = nextTimer.at
        nextTimer.fn()
    end
    world.now = target
end

-- helper: build a tracker list entry
function M.tracker(name, spellID, active)
    return { name = name, spellID = spellID, active = active or false }
end

function M.printed(pattern)
    for _, line in ipairs(M.world.printed) do
        if line:find(pattern, 1, true) then return true end
    end
    return false
end

return M
