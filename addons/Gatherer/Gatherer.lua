-- Gatherer (c) 2026 Status kuo
-- Licensed under the GNU General License (see LICENSE file)

print("========================================")
print("|cff69BE28          Gatherer         |r")
print("========================================")

local frame = CreateFrame("Frame")


local addonEnabled = true
local isMiner = false
local isPicker = false

-- name of the gather tracker we asked for and haven't seen confirmed yet
local pendingRequest = nil

-- a character's class never changes, so this is settled once at load
local isHunter = select(2, UnitClass("player")) == "HUNTER"

local MINING_SKILL_ID = 186
local HERBALISM_SKILL_ID = 182
local FIND_MINERALS = "Find Minerals"
local FIND_HERBS = "Find Herbs"
local TRACKER_SPELLS = { [FIND_MINERALS] = 2580, [FIND_HERBS] = 2383 }
local GATHER_TRACKERS = { FIND_MINERALS, FIND_HERBS }


-- true if the player has learned the skill line (rank above 0)
local function KnowsSkill(skillID)

    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then

        local info = C_SkillInfo.GetSkillLineInfoByID(skillID)

        return info ~= nil and (info.rank or 0) > 0
    end

    return false
end


local function CheckProfessions()

    local miner = KnowsSkill(MINING_SKILL_ID)
    local picker = KnowsSkill(HERBALISM_SKILL_ID)

    -- fall back to the profession list for anything the skill lines missed
    if GetProfessions and GetProfessionInfo then

        for _, professionIndex in pairs({ GetProfessions() }) do

            local name = professionIndex and GetProfessionInfo(professionIndex)

            if name == "Mining" then
                miner = true
            elseif name == "Herbalism" then
                picker = true
            end
        end
    end

    -- this runs on several events; only report changes
    if miner and not isMiner then
        print("Profession: Mining detected.")
    end

    if picker and not isPicker then
        print("Profession: Herbalism detected.")
    end

    isMiner = miner
    isPicker = picker
end


-- iterates the client's tracking entries, skipping empty slots:
--   for index, info in Trackers() do ... end
local function Trackers()

    local index = 0
    local count = C_Minimap.GetNumTrackingTypes()

    return function()

        while index < count do

            index = index + 1

            local info = C_Minimap.GetTrackingInfo(index)

            if info then
                return index, info
            end
        end
    end
end


-- Does this tracking entry describe the named gather spell? Some entries omit
-- the name or spellID, so try the English name, then the spell ID, then the
-- client-localized spell name.
local function MatchesTracker(info, trackerName)

    if info.name == trackerName then
        return true
    end

    local spellID = TRACKER_SPELLS[trackerName]

    if not spellID then
        return false
    end

    if info.spellID == spellID then
        return true
    end

    if info.name and C_Spell and C_Spell.GetSpellName then
        return info.name == C_Spell.GetSpellName(spellID)
    end

    return false
end


-- returns the index and active state of the named tracker, or nil, false
local function FindTracker(trackerName)

    for index, info in Trackers() do

        if MatchesTracker(info, trackerName) then
            return index, info.active
        end
    end

    return nil, false
end


-- name of the gather tracker that is currently on, or nil
local function ActiveGatherTracker()

    for _, trackerName in ipairs(GATHER_TRACKERS) do

        local _, active = FindTracker(trackerName)

        if active then
            return trackerName
        end
    end

    return nil
end


-- The tracker we should switch on automatically, or nil. With both
-- professions (or neither) there is nothing automatic to do: for Mining +
-- Herbalism the toggle button is the only thing that switches trackers.
local function WantedTracker()

    if isMiner and not isPicker then
        return FIND_MINERALS
    elseif isPicker and not isMiner then
        return FIND_HERBS
    end

    return nil
end


-- Hunters only: returns the index and info of the active "Track ..." ability
-- (Track Beasts, Track Humanoids, ...), or nil if none is on
local function FindActiveHunterTrack()

    if not isHunter then
        return nil
    end

    for index, info in Trackers() do

        -- only spells count; minimap filters such as "Track Quest POIs" are
        -- type "other" and are often on by default
        if info.active and info.type == "spell" and info.name and info.name:find("^Track ") then
            return index, info
        end
    end

    return nil
end


local CHECK_DELAY = 0.25   -- let the client settle before checking tracking
local VERIFY_DELAY = 1.5   -- how long a cast gets to take effect
local AURA_DELAY = 1.6     -- outlast the global cooldown an Aspect triggers
local MAX_TRACKING_RETRIES = 3
local trackingRetries = 0
local auraCheckPending = false

local CheckTracking -- forward declaration, used by VerifyTracking for retries


-- SetTracking casts the Find spell, which can fail silently (e.g. during the
-- global cooldown after an Aspect). Confirm it took, otherwise clear the
-- request flag and try again a limited number of times.
local function VerifyTracking(trackerName)

    C_Timer.After(VERIFY_DELAY, function()

        local _, active = FindTracker(trackerName)

        if active then
            trackingRetries = 0
            print("Gatherer: " .. trackerName .. " enabled.")
            return
        end

        pendingRequest = nil

        if not addonEnabled or UnitIsDeadOrGhost("player") then
            trackingRetries = 0
            return
        end

        -- player switched to the other gather tracker or a Hunter Track in the meantime
        if ActiveGatherTracker() or FindActiveHunterTrack() then
            trackingRetries = 0
            return
        end

        if trackingRetries < MAX_TRACKING_RETRIES then
            trackingRetries = trackingRetries + 1
            CheckTracking()
        else
            trackingRetries = 0
            print("Gatherer: Could not enable " .. trackerName .. ".")
        end
    end)
end


function CheckTracking()

    if UnitIsDeadOrGhost("player") then
        return
    end

    -- the request has been confirmed
    if pendingRequest and ActiveGatherTracker() == pendingRequest then
        pendingRequest = nil
    end

    -- a Hunter chose a Track ability; leave it until they use the button
    if FindActiveHunterTrack() then
        return
    end

    local wanted = WantedTracker()

    if not wanted or pendingRequest then
        return
    end

    local index, active = FindTracker(wanted)

    if index and not active then

        pendingRequest = wanted

        C_Minimap.SetTracking(index, true)

        VerifyTracking(wanted)
    end
end


-- minimap button: its icon shows what the character gathers, and with both
-- professions a click toggles between Find Minerals / Find Herbs
local MINING_ICON = "Interface\\AddOns\\Gatherer\\icons\\copper"
local HERBS_ICON = "Interface\\AddOns\\Gatherer\\icons\\peacebloom"
local NEITHER_ICON = "Interface\\AddOns\\Gatherer\\icons\\Soil" -- dual skill, nothing active

-- angle around the minimap edge (degrees, 0 = right, 90 = top); the default
-- tracking icon sits near 140, so this stays just above it on the upper-left
local MINIMAP_ANGLE = 115
local MINIMAP_RADIUS = 105

local toggleButton = CreateFrame("Button", "GathererToggleButton", Minimap)
toggleButton:SetSize(31, 31)
toggleButton:SetFrameStrata("MEDIUM")
toggleButton:SetFrameLevel(8)
toggleButton:SetPoint("CENTER", Minimap, "CENTER",
    MINIMAP_RADIUS * math.cos(math.rad(MINIMAP_ANGLE)),
    MINIMAP_RADIUS * math.sin(math.rad(MINIMAP_ANGLE)))
toggleButton:EnableMouse(true)
toggleButton:RegisterForClicks("LeftButtonUp")
toggleButton:Hide()

-- standard round minimap button layers
local background = toggleButton:CreateTexture(nil, "BACKGROUND")
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetSize(20, 20)
background:SetPoint("TOPLEFT", 7, -5)

toggleButton.icon = toggleButton:CreateTexture(nil, "ARTWORK")
toggleButton.icon:SetSize(20, 20)
toggleButton.icon:SetPoint("TOPLEFT", 7, -5)

local border = toggleButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")

toggleButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")


local function UpdateToggleButton()

    if not addonEnabled then
        toggleButton:Hide()
        return
    end

    -- no gathering profession, or a Hunter Track ability is on: hide the
    -- button (it comes back when that tracking is turned off)
    if not (isMiner or isPicker) or FindActiveHunterTrack() then
        toggleButton:Hide()
        return
    end

    if isMiner and isPicker then

        -- dual skill: show whichever tracker is currently active
        local activeTracker = ActiveGatherTracker()

        if activeTracker == FIND_HERBS then
            toggleButton.icon:SetTexture(HERBS_ICON)
        elseif activeTracker == FIND_MINERALS then
            toggleButton.icon:SetTexture(MINING_ICON)
        else
            toggleButton.icon:SetTexture(NEITHER_ICON)
        end

        toggleButton.icon:SetDesaturated(activeTracker == nil)

    elseif isPicker then
        toggleButton.icon:SetTexture(HERBS_ICON)
        toggleButton.icon:SetDesaturated(false)
    else
        toggleButton.icon:SetTexture(MINING_ICON)
        toggleButton.icon:SetDesaturated(false)
    end

    toggleButton:Show()
end


toggleButton:SetScript("OnClick", function(self)

    -- only characters with both professions have anything to toggle
    if not (isMiner and isPicker) then
        return
    end

    if UnitIsDeadOrGhost("player") or InCombatLockdown() then
        return
    end

    -- minerals -> herbs; herbs or nothing -> minerals
    local nextTracker = ActiveGatherTracker() == FIND_MINERALS and FIND_HERBS or FIND_MINERALS
    local nextIndex = FindTracker(nextTracker)

    if nextIndex then
        C_Minimap.SetTracking(nextIndex, true)
    end

    if GameTooltip:IsOwned(self) then
        self:GetScript("OnEnter")(self)
    end
end)

toggleButton:SetScript("OnEnter", function(self)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Gatherer")
    GameTooltip:AddLine("Tracking: " .. (ActiveGatherTracker() or "None"), 1, 1, 1)

    if isMiner and isPicker then
        GameTooltip:AddLine("Click to switch Minerals / Herbs.", 0.7, 0.7, 0.7)
    end

    GameTooltip:Show()
end)

toggleButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)


-- Entry points shared by the event handlers and /gatherer.

local function ScheduleCheck()
    C_Timer.After(CHECK_DELAY, CheckTracking)
end

-- forget any unconfirmed request and try to get tracking on again
local function RetryTracking()
    pendingRequest = nil
    ScheduleCheck()
end

-- skill data often isn't ready at login; re-read it, then check tracking
local function RecheckProfessions()
    CheckProfessions()
    UpdateToggleButton()
    ScheduleCheck()
end

-- the full startup sequence used on login and when the addon is re-enabled
local function Refresh()
    CheckProfessions()
    UpdateToggleButton()
    RetryTracking()
end


-- player command to enable or disable the addon
SLASH_GATHERER1 = "/gatherer"
SlashCmdList["GATHERER"] = function()
    addonEnabled = not addonEnabled
    print("Gatherer: " .. (addonEnabled and "enabled." or "disabled."))

    if addonEnabled then
        Refresh()
    else
        UpdateToggleButton()
    end
end



-- diagnostic: /gatherdiag prints what the client reports for professions and trackers
SLASH_GATHERERDIAG1 = "/gatherdiag"
SlashCmdList["GATHERERDIAG"] = function()

    print("Gatherer diag: isMiner=" .. tostring(isMiner) .. " isPicker=" .. tostring(isPicker) .. " isHunter=" .. tostring(isHunter))

    print("addonEnabled=" .. tostring(addonEnabled) .. " activeGatherTracker=" .. tostring(ActiveGatherTracker())
        .. " pendingRequest=" .. tostring(pendingRequest) .. " activeHunterTrack=" .. tostring(FindActiveHunterTrack()))

    local bx, by = toggleButton:GetCenter()
    local mx, my = Minimap:GetCenter()
    print("button: shown=" .. tostring(toggleButton:IsShown()) .. " center=" .. tostring(bx) .. "," .. tostring(by)
        .. " minimap center=" .. tostring(mx) .. "," .. tostring(my)
        .. " screen=" .. tostring(UIParent:GetWidth()) .. "x" .. tostring(UIParent:GetHeight()))

    for _, skillID in ipairs({ MINING_SKILL_ID, HERBALISM_SKILL_ID }) do

        local info = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and C_SkillInfo.GetSkillLineInfoByID(skillID)

        print("skill " .. skillID .. ": " .. (info and (tostring(info.name) .. " rank " .. tostring(info.rank)) or "nil"))
    end

    if GetProfessions and GetProfessionInfo then

        for slot, professionIndex in pairs({ GetProfessions() }) do
            print("profession slot " .. slot .. ": " .. tostring(GetProfessionInfo(professionIndex)))
        end
    else
        print("GetProfessions unavailable")
    end

    for index, info in Trackers() do
        print("tracker " .. index .. ": " .. tostring(info.name) .. " spellID=" .. tostring(info.spellID)
            .. " active=" .. tostring(info.active) .. " type=" .. tostring(info.type))
    end
end


-- one handler per event; the events registered below come from this table
local eventHandlers = {}

function eventHandlers.PLAYER_ENTERING_WORLD()
    Refresh()
end

function eventHandlers.MINIMAP_UPDATE_TRACKING()
    UpdateToggleButton()
    CheckTracking()   -- does nothing while dead
end

function eventHandlers.PLAYER_ALIVE()

    if not UnitIsDeadOrGhost("player") then
        RetryTracking()
    end
end

function eventHandlers.PLAYER_UNGHOST()
    RetryTracking()
end

-- skill data often isn't ready at login; re-check when it loads
eventHandlers.SKILL_LINES_CHANGED = RecheckProfessions
eventHandlers.SPELLS_CHANGED = RecheckProfessions

-- buffs changed (e.g. a Hunter Aspect added, swapped or removed);
-- fires often, so only queue one check at a time
function eventHandlers.UNIT_AURA()

    if auraCheckPending or UnitIsDeadOrGhost("player") then
        return
    end

    auraCheckPending = true

    C_Timer.After(AURA_DELAY, function()
        auraCheckPending = false

        if addonEnabled then
            CheckTracking()
        end
    end)
end


local function OnEvent(_, event, ...)

    local handler = eventHandlers[event]

    if addonEnabled and handler then
        handler(...)
    end
end


for event in pairs(eventHandlers) do

    if event == "UNIT_AURA" then
        frame:RegisterUnitEvent(event, "player")
    else
        frame:RegisterEvent(event)
    end
end

frame:SetScript("OnEvent", OnEvent)