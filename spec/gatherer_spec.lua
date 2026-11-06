local wow = require("wow_mock")

local MINING, HERBALISM = 186, 182
local MINERALS, HERBS = 2580, 2383

local function gatherTrackers()
    return {
        wow.tracker("Find Fish", 43308),
        wow.tracker("Find Minerals", MINERALS),
        wow.tracker("Find Herbs", HERBS),
    }
end

-- load the addon and run the login sequence
local function login()
    wow.load("addons/Gatherer/Gatherer.lua")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(0.25)
end

local function active(name)
    for _, t in ipairs(wow.world.trackers) do
        if t.name == name then return t.active end
    end
end

describe("Gatherer", function()

    before_each(function()
        wow.install()
        wow.world.trackers = gatherTrackers()
    end)

    describe("profession detection", function()

        it("detects Mining from the skill line", function()
            wow.world.skills[MINING] = 75
            login()
            assert.is_true(wow.printed("Mining detected"))
            assert.is_false(wow.printed("Herbalism detected"))
        end)

        it("ignores a skill line with rank 0", function()
            wow.world.skills[MINING] = 0
            login()
            assert.is_false(wow.printed("Mining detected"))
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("falls back to the profession list", function()
            wow.world.professions = { "Herbalism" }
            login()
            assert.is_true(wow.printed("Herbalism detected"))
        end)

        it("only reports a profession once across repeated events", function()
            wow.world.skills[MINING] = 75
            login()
            wow.fire("SKILL_LINES_CHANGED")
            wow.fire("SPELLS_CHANGED")
            local count = 0
            for _, line in ipairs(wow.world.printed) do
                if line:find("Mining detected", 1, true) then count = count + 1 end
            end
            assert.are.equal(1, count)
        end)
    end)

    describe("auto tracking", function()

        it("turns on Find Minerals for a miner", function()
            wow.world.skills[MINING] = 75
            login()
            assert.is_true(active("Find Minerals"))
        end)

        it("turns on Find Herbs for an herbalist", function()
            wow.world.skills[HERBALISM] = 75
            login()
            assert.is_true(active("Find Herbs"))
        end)

        it("does nothing for a character with no gathering profession", function()
            login()
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("never switches automatically with both professions", function()
            wow.world.skills[MINING] = 75
            wow.world.skills[HERBALISM] = 75
            login()
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("does not recast when the tracker is already active", function()
            wow.world.skills[MINING] = 75
            wow.world.trackers[2].active = true
            login()
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("does nothing while dead", function()
            wow.world.skills[MINING] = 75
            wow.world.dead = true
            login()
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("resumes tracking after the player is resurrected", function()
            wow.world.skills[MINING] = 75
            wow.world.dead = true
            login()
            wow.world.dead = false
            wow.fire("PLAYER_UNGHOST")
            wow.advance(0.25)
            assert.is_true(active("Find Minerals"))
        end)

        it("does not cast again while a request is pending", function()
            wow.world.skills[MINING] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.fire("MINIMAP_UPDATE_TRACKING")
            wow.fire("MINIMAP_UPDATE_TRACKING")
            assert.are.equal(1, #wow.world.setTrackingCalls)
        end)

        it("does nothing while the addon is disabled", function()
            wow.world.skills[MINING] = 75
            wow.load("addons/Gatherer/Gatherer.lua")
            SlashCmdList["GATHERER"]()   -- disable
            wow.fire("PLAYER_ENTERING_WORLD")
            wow.advance(0.25)
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)
    end)

    describe("tracker matching", function()

        it("matches by spell ID when the name is a different locale", function()
            wow.world.skills[MINING] = 75
            wow.world.trackers = { { name = "Mineralien finden", spellID = MINERALS, active = false } }
            login()
            assert.is_true(wow.world.trackers[1].active)
        end)

        it("matches by localized spell name when the spell ID is missing", function()
            wow.world.skills[MINING] = 75
            wow.world.spellNames[MINERALS] = "Mineralien finden"
            wow.world.trackers = { { name = "Mineralien finden", active = false } }
            login()
            assert.is_true(wow.world.trackers[1].active)
        end)
    end)

    describe("verification and retries", function()

        it("announces success once the tracker is confirmed", function()
            wow.world.skills[MINING] = 75
            login()
            wow.advance(1.5)
            assert.is_true(wow.printed("Find Minerals enabled"))
        end)

        it("retries a silently failing cast, then gives up after 3 retries", function()
            wow.world.skills[MINING] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.advance(30)
            -- 1 initial attempt + 3 retries
            assert.are.equal(4, #wow.world.setTrackingCalls)
            assert.is_true(wow.printed("Could not enable Find Minerals"))
        end)

        it("succeeds on a retry if the cast works the second time", function()
            wow.world.skills[MINING] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.advance(1.4)
            wow.world.setTrackingWorks = true            wow.advance(10)
            assert.is_true(active("Find Minerals"))
            assert.is_false(wow.printed("Could not enable"))
        end)

        it("stops retrying if the player died in the meantime", function()
            wow.world.skills[MINING] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.world.dead = true
            wow.advance(30)
            assert.are.equal(1, #wow.world.setTrackingCalls)
        end)
    end)

    describe("request bookkeeping", function()

        it("herbalist: does not cast again while a request is pending", function()
            wow.world.skills[HERBALISM] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.fire("MINIMAP_UPDATE_TRACKING")
            wow.fire("MINIMAP_UPDATE_TRACKING")
            assert.are.equal(1, #wow.world.setTrackingCalls)
            assert.are.equal(3, wow.world.setTrackingCalls[1].index)
        end)

        it("herbalist: gives up after 3 retries", function()
            wow.world.skills[HERBALISM] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.advance(30)
            assert.are.equal(4, #wow.world.setTrackingCalls)
            assert.is_true(wow.printed("Could not enable Find Herbs"))
        end)

        it("stops retrying when the player switches to the other gather tracker", function()
            wow.world.skills[MINING] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.world.trackers[3].active = true   -- player picked Find Herbs by hand
            wow.advance(30)
            assert.are.equal(1, #wow.world.setTrackingCalls)
            assert.is_false(wow.printed("Could not enable"))
        end)

        it("re-enables the tracker after the player turns it off", function()
            wow.world.skills[MINING] = 75
            login()
            wow.fire("MINIMAP_UPDATE_TRACKING")   -- client confirms the cast
            wow.advance(2)
            wow.world.trackers[2].active = false
            wow.fire("MINIMAP_UPDATE_TRACKING")
            assert.are.equal(2, #wow.world.setTrackingCalls)
            assert.is_true(active("Find Minerals"))
        end)

        it("clears a pending request on respawn so tracking is attempted again", function()
            wow.world.skills[MINING] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.fire("PLAYER_ALIVE")
            wow.advance(0.25)
            assert.are.equal(2, #wow.world.setTrackingCalls)
        end)

        it("button click with nothing active switches Minerals on", function()
            wow.world.skills[MINING] = 75
            wow.world.skills[HERBALISM] = 75
            login()
            GathererToggleButton.scripts.OnClick(GathererToggleButton)
            assert.is_true(active("Find Minerals"))
        end)

        it("button icon follows the active tracker for a dual-skill character", function()
            wow.world.skills[MINING] = 75
            wow.world.skills[HERBALISM] = 75
            login()
            assert.is_truthy(GathererToggleButton.icon.texture:find("Soil", 1, true))
            wow.world.trackers[3].active = true
            wow.fire("MINIMAP_UPDATE_TRACKING")
            assert.is_truthy(GathererToggleButton.icon.texture:find("peacebloom", 1, true))
            wow.world.trackers[3].active = false
            wow.world.trackers[2].active = true
            wow.fire("MINIMAP_UPDATE_TRACKING")
            assert.is_truthy(GathererToggleButton.icon.texture:find("copper", 1, true))
        end)

        it("tooltip names the active tracker", function()
            wow.world.skills[MINING] = 75
            wow.world.trackers[2].active = true
            login()
            GathererToggleButton.scripts.OnEnter(GathererToggleButton)
            assert.are.equal("Tracking: Find Minerals", GameTooltip.lines[2])
        end)
    end)

    describe("event handling", function()

        -- tracking already on, then switched off behind the addon's back
        local function loginWithTrackerLost()
            wow.world.skills[MINING] = 75
            login()
            wow.fire("MINIMAP_UPDATE_TRACKING")
            wow.advance(2)
            wow.world.trackers[2].active = false
            wow.world.setTrackingCalls = {}
        end

        it("UNIT_AURA re-checks only after the global cooldown has passed", function()
            loginWithTrackerLost()
            wow.fire("UNIT_AURA")
            wow.advance(1.5)
            assert.are.equal(0, #wow.world.setTrackingCalls)
            wow.advance(0.2)
            assert.are.equal(1, #wow.world.setTrackingCalls)
        end)

        it("UNIT_AURA queues one check no matter how often it fires", function()
            loginWithTrackerLost()
            wow.world.setTrackingWorks = false
            wow.fire("UNIT_AURA")
            wow.fire("UNIT_AURA")
            wow.fire("UNIT_AURA")
            wow.advance(1.7)
            assert.are.equal(1, #wow.world.setTrackingCalls)
        end)

        it("UNIT_AURA queues a new check once the previous one has run", function()
            loginWithTrackerLost()
            wow.fire("UNIT_AURA")
            wow.advance(1.7)
            assert.are.equal(1, #wow.world.setTrackingCalls)
            wow.fire("MINIMAP_UPDATE_TRACKING")   -- client confirms the cast
            wow.world.trackers[2].active = false
            wow.fire("UNIT_AURA")
            wow.advance(1.7)
            assert.are.equal(2, #wow.world.setTrackingCalls)
        end)

        it("UNIT_AURA is ignored while dead", function()
            loginWithTrackerLost()
            wow.world.dead = true
            wow.fire("UNIT_AURA")
            wow.advance(5)
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("a queued UNIT_AURA check does nothing if the addon was disabled meanwhile", function()
            loginWithTrackerLost()
            wow.fire("UNIT_AURA")
            SlashCmdList["GATHERER"]()   -- disable
            wow.advance(5)
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("SKILL_LINES_CHANGED picks up a profession that loaded late", function()
            login()
            assert.are.equal(0, #wow.world.setTrackingCalls)
            wow.world.skills[MINING] = 75
            wow.fire("SKILL_LINES_CHANGED")
            wow.advance(0.25)
            assert.is_true(active("Find Minerals"))
            assert.is_true(GathererToggleButton:IsShown())
        end)

        it("SPELLS_CHANGED picks up a profession that loaded late", function()
            login()
            wow.world.skills[HERBALISM] = 75
            wow.fire("SPELLS_CHANGED")
            wow.advance(0.25)
            assert.is_true(active("Find Herbs"))
        end)

        it("PLAYER_ALIVE does nothing while still a ghost", function()
            wow.world.skills[MINING] = 75
            wow.world.dead = true
            login()
            wow.fire("PLAYER_ALIVE")
            wow.advance(0.25)
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("PLAYER_ALIVE resumes tracking after a resurrection", function()
            wow.world.skills[MINING] = 75
            wow.world.dead = true
            login()
            wow.world.dead = false
            wow.fire("PLAYER_ALIVE")
            wow.advance(0.25)
            assert.is_true(active("Find Minerals"))
        end)

        it("MINIMAP_UPDATE_TRACKING updates the button even while dead", function()
            wow.world.skills[MINING] = 75
            wow.world.skills[HERBALISM] = 75
            wow.world.trackers[3].active = true
            login()
            assert.is_truthy(GathererToggleButton.icon.texture:find("peacebloom", 1, true))
            wow.world.dead = true
            wow.world.trackers[3].active = false
            wow.world.trackers[2].active = true
            wow.fire("MINIMAP_UPDATE_TRACKING")
            assert.is_truthy(GathererToggleButton.icon.texture:find("copper", 1, true))
        end)

        it("ignores every event while disabled", function()
            wow.world.skills[MINING] = 75
            wow.load("addons/Gatherer/Gatherer.lua")
            SlashCmdList["GATHERER"]()   -- disable
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_TRACKING", "PLAYER_ALIVE",
                    "PLAYER_UNGHOST", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "UNIT_AURA" }) do
                wow.fire(event)
            end
            wow.advance(5)
            assert.are.equal(0, #wow.world.setTrackingCalls)
            assert.is_false(GathererToggleButton:IsShown())
        end)

        it("re-enabling with /gatherer runs the full startup sequence", function()
            wow.world.skills[MINING] = 75
            wow.load("addons/Gatherer/Gatherer.lua")
            SlashCmdList["GATHERER"]()   -- disable
            assert.is_false(GathererToggleButton:IsShown())
            SlashCmdList["GATHERER"]()   -- enable
            assert.is_true(GathererToggleButton:IsShown())
            wow.advance(0.25)
            assert.is_true(active("Find Minerals"))
        end)

        it("PLAYER_UNGHOST clears a pending request and retries", function()
            wow.world.skills[MINING] = 75
            wow.world.setTrackingWorks = false
            login()
            wow.fire("PLAYER_UNGHOST")
            wow.advance(0.25)
            assert.are.equal(2, #wow.world.setTrackingCalls)
        end)

        it("registers exactly the events it handles", function()
            wow.load("addons/Gatherer/Gatherer.lua")
            local expected = { "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_TRACKING", "PLAYER_ALIVE",
                "PLAYER_UNGHOST", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "UNIT_AURA" }
            local count = 0
            for _ in pairs(wow.frame.events) do count = count + 1 end
            assert.are.equal(#expected, count)
            for _, event in ipairs(expected) do
                assert.is_true(wow.frame.events[event])
            end
        end)
    end)

    describe("Hunters", function()

        before_each(function()
            wow.world.class = "HUNTER"
            wow.world.trackers = {
                wow.tracker("Track Beasts", 1494, true),
                wow.tracker("Find Minerals", MINERALS),
                wow.tracker("Find Herbs", HERBS),
            }
        end)

        it("leaves an active Track ability alone", function()
            wow.world.skills[MINING] = 75
            login()
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("hides the minimap button while a Track ability is on", function()
            wow.world.skills[MINING] = 75
            login()
            assert.is_false(GathererToggleButton:IsShown())
        end)

        it("enables Find Minerals and shows the button when Track is off, among unrelated trackers", function()
            wow.world.skills[MINING] = 75
            wow.world.trackers = {
                wow.tracker("Track Beasts", 1494),
                wow.tracker("Find Minerals", MINERALS),
                { name = "Auctioneer", type = "other", active = false },
                { name = "Flight Master", type = "other", active = true },
                { name = "Innkeeper", type = "other", active = true },
            }
            login()
            assert.is_true(active("Find Minerals"))
            assert.is_true(GathererToggleButton:IsShown())
        end)

        it("ignores an active minimap filter named Track ... (e.g. Track Quest POIs)", function()
            wow.world.skills[MINING] = 75
            wow.world.trackers = {
                wow.tracker("Track Beasts", 1494),
                wow.tracker("Find Minerals", MINERALS),
                { name = "Track Quest POIs", type = "other", active = true },
            }
            login()
            assert.is_true(active("Find Minerals"))
            assert.is_true(GathererToggleButton:IsShown())
        end)

        it("prints diagnostics without errors", function()
            wow.world.skills[MINING] = 75
            login()
            assert.has_no.errors(function() SlashCmdList["GATHERERDIAG"]() end)
            assert.is_true(wow.printed("button: shown="))
        end)

        it("tracks minerals once the Track ability is off", function()
            wow.world.skills[MINING] = 75
            login()
            wow.world.trackers[1].active = false
            wow.fire("MINIMAP_UPDATE_TRACKING")
            assert.is_true(active("Find Minerals"))
        end)
    end)

    describe("minimap button", function()

        it("is hidden without a gathering profession", function()
            login()
            assert.is_false(GathererToggleButton:IsShown())
        end)

        it("is shown for a miner with the mining icon", function()
            wow.world.skills[MINING] = 75
            login()
            assert.is_true(GathererToggleButton:IsShown())
            assert.is_truthy(GathererToggleButton.icon.texture:find("copper", 1, true))
        end)

        it("toggles between Minerals and Herbs for a dual-skill character", function()
            wow.world.skills[MINING] = 75
            wow.world.skills[HERBALISM] = 75
            wow.world.trackers[2].active = true
            login()

            local click = GathererToggleButton.scripts.OnClick
            click(GathererToggleButton)
            assert.is_true(active("Find Herbs"))
            assert.is_false(active("Find Minerals"))

            click(GathererToggleButton)
            assert.is_true(active("Find Minerals"))
        end)

        it("ignores clicks in combat", function()
            wow.world.skills[MINING] = 75
            wow.world.skills[HERBALISM] = 75
            login()
            wow.world.combat = true
            GathererToggleButton.scripts.OnClick(GathererToggleButton)
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)

        it("does nothing on click for a single-profession character", function()
            wow.world.skills[MINING] = 75
            wow.world.trackers[2].active = true
            login()
            GathererToggleButton.scripts.OnClick(GathererToggleButton)
            assert.are.equal(0, #wow.world.setTrackingCalls)
        end)
    end)

    describe("slash commands", function()

        it("registers /gatherer under the key the client looks up", function()
            wow.load("addons/Gatherer/Gatherer.lua")
            assert.are.equal("/gatherer", SLASH_GATHERER1)
            assert.is_function(SlashCmdList["GATHERER"])
        end)

        it("toggles the addon off and on", function()
            wow.load("addons/Gatherer/Gatherer.lua")
            SlashCmdList["GATHERER"]()
            assert.is_true(wow.printed("disabled"))
            SlashCmdList["GATHERER"]()
            assert.is_true(wow.printed("enabled"))
        end)

        it("registers the /gatherdiag command", function()
            wow.load("addons/Gatherer/Gatherer.lua")
            assert.is_function(SlashCmdList["GATHERERDIAG"])
            assert.has_no.errors(function() SlashCmdList["GATHERERDIAG"]() end)
        end)
    end)
end)
