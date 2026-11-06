-- Gatherer (c) 2026 Status kuo
-- Licensed under the GNU General License (see LICENSE file)

print("========================================")
print("|cff69BE28          Gatherer         |r")
print("========================================")

local frame = CreateFrame("Frame")


local addonEnabled = true
local isMiner = false
local isPicker = false

local herbalismRequest = false
local miningRequest = false

local isHunter = false

local MINING_SKILL_ID = 186
local HERBALISM_SKILL_ID = 182
local TRACKER_SPELLS = { ["Find Minerals"] = 2580, ["Find Herbs"] = 2383 }


-- true if the player has learned the skill line (rank above 0)
local function KnowsSkill(skillID)

    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then

        local info = C_SkillInfo.GetSkillLineInfoByID(skillID)

        return info ~= nil and (info.rank or 0) > 0
    end

    return false
end


local function CheckProfessions()

    local _, classToken = UnitClass("player")
    isHunter = classToken == "HUNTER"

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


local function FindTracker(trackerName)

    local numberOfTrackers = C_Minimap.GetNumTrackingTypes()

    for i = 1, numberOfTrackers do

        local info = C_Minimap.GetTrackingInfo(i)

        if info then

            local spellID = TRACKER_SPELLS[trackerName]
            local match = info.name == trackerName

            -- some entries omit the name or spellID; also match by spell ID
            -- and by the client-localized spell name
            if not match and spellID then
                if info.spellID == spellID then
                    match = true
                elseif C_Spell and C_Spell.GetSpellName and info.name then
                    match = info.name == C_Spell.GetSpellName(spellID)
                end
            end

            if match then
                return i, info.active
            end
        end
    end

    return nil, false
end


-- Hunters only: returns the index and info of the active "Track ..." ability
-- (Track Beasts, Track Humanoids, ...), or nil if none is on
local function FindActiveHunterTrack()

    if not isHunter then
        return nil
    end

    local numberOfTrackers = C_Minimap.GetNumTrackingTypes()

    for i = 1, numberOfTrackers do

        local info = C_Minimap.GetTrackingInfo(i)

        if info and info.active and info.name and info.name:find("^Track ") then
            return i, info
        end
    end

    return nil
end


local MAX_TRACKING_RETRIES = 3
local trackingRetries = 0
local auraCheckPending = false

local CheckTracking -- forward declaration, used by VerifyTracking for retries


-- SetTracking casts the Find spell, which can fail silently (e.g. during the
-- global cooldown after an Aspect). Confirm it took, otherwise clear the
-- request flag and try again a limited number of times.
local function VerifyTracking(trackerName, clearRequest)

    C_Timer.After(1.5, function()

        local _, active = FindTracker(trackerName)

        if active then
            trackingRetries = 0
            print("Gatherer: " .. trackerName .. " enabled.")
            return
        end

        clearRequest()

        if not addonEnabled or UnitIsDeadOrGhost("player") then
            trackingRetries = 0
            return
        end

        -- player switched to the other gather tracker or a Hunter Track in the meantime
        local _, mineralsActive = FindTracker("Find Minerals")
        local _, herbsActive = FindTracker("Find Herbs")

        if mineralsActive or herbsActive or FindActiveHunterTrack() then
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

    local mineralIndex, mineralsActive = FindTracker("Find Minerals")
    local herbIndex, herbsActive = FindTracker("Find Herbs")

    if mineralsActive then
        miningRequest = false
    end

    if herbsActive then
        herbalismRequest = false
    end

    -- a Hunter chose a Track ability; leave it until they use the button
    if FindActiveHunterTrack() then
        return
    end


    if isMiner and not isPicker then

        if mineralIndex and not miningRequest then

            if not mineralsActive then

                miningRequest = true

                C_Minimap.SetTracking(mineralIndex, true)

                VerifyTracking("Find Minerals", function() miningRequest = false end)
            end
        end


    elseif isPicker and not isMiner then

        if herbIndex and not herbalismRequest then

            if not herbsActive then

                herbalismRequest = true

                C_Minimap.SetTracking(herbIndex, true)

                VerifyTracking("Find Herbs", function() herbalismRequest = false end)
            end
        end


    end

    -- Mining + Herbalism: never automatic. The toggle button is the only thing
    -- that switches between Find Minerals and Find Herbs.
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
        local _, mineralsActive = FindTracker("Find Minerals")
        local _, herbsActive = FindTracker("Find Herbs")

        if herbsActive then
            toggleButton.icon:SetTexture(HERBS_ICON)
        elseif mineralsActive then
            toggleButton.icon:SetTexture(MINING_ICON)
        else
            toggleButton.icon:SetTexture(NEITHER_ICON)
        end

        toggleButton.icon:SetDesaturated(not mineralsActive and not herbsActive)

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

    local mineralIndex, mineralsActive = FindTracker("Find Minerals")
    local herbIndex = FindTracker("Find Herbs")

    if mineralsActive then
        if herbIndex then
            C_Minimap.SetTracking(herbIndex, true)
        end
    elseif mineralIndex then
        C_Minimap.SetTracking(mineralIndex, true)
    end

    if GameTooltip:IsOwned(self) then
        self:GetScript("OnEnter")(self)
    end
end)

toggleButton:SetScript("OnEnter", function(self)

    local _, mineralsActive = FindTracker("Find Minerals")
    local _, herbsActive = FindTracker("Find Herbs")

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Gatherer")
    GameTooltip:AddLine("Tracking: " .. (mineralsActive and "Find Minerals" or herbsActive and "Find Herbs" or "None"), 1, 1, 1)

    if isMiner and isPicker then
        GameTooltip:AddLine("Click to switch Minerals / Herbs.", 0.7, 0.7, 0.7)
    end

    GameTooltip:Show()
end)

toggleButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)


-- player command to enable or disable the addon
SLASH_GATHERER1 = "/gatherer"
SlashCmdList["GATHERER"] = function()
    addonEnabled = not addonEnabled
    print("Gatherer: " .. (addonEnabled and "enabled." or "disabled."))

    if not addonEnabled then
        UpdateToggleButton()
    else
        -- run the same startup sequence used on login/respawn
        CheckProfessions()
        UpdateToggleButton()

        miningRequest = false
        herbalismRequest = false

        C_Timer.After(0.25, CheckTracking)
    end
end



-- diagnostic: /gatherdiag prints what the client reports for professions and trackers
SLASH_GATHERERDIAG1 = "/gatherdiag"
SlashCmdList["GATHERERDIAG"] = function()

    print("Gatherer diag: isMiner=" .. tostring(isMiner) .. " isPicker=" .. tostring(isPicker) .. " isHunter=" .. tostring(isHunter))

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

    for i = 1, C_Minimap.GetNumTrackingTypes() do

        local info = C_Minimap.GetTrackingInfo(i)

        if info then
            print("tracker " .. i .. ": " .. tostring(info.name) .. " spellID=" .. tostring(info.spellID)
                .. " active=" .. tostring(info.active) .. " type=" .. tostring(info.type))
        end
    end
end


local function OnEvent(_, event)

    if not addonEnabled then
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then

        CheckProfessions()
        UpdateToggleButton()

        miningRequest = false
        herbalismRequest = false

        C_Timer.After(0.25, CheckTracking)


    elseif event == "MINIMAP_UPDATE_TRACKING" then

        UpdateToggleButton()

        if UnitIsDeadOrGhost("player") then
            return
        end

        CheckTracking()


    elseif event == "PLAYER_ALIVE" then

        if UnitIsDeadOrGhost("player") then
            return
        end

        miningRequest = false
        herbalismRequest = false

        C_Timer.After(0.25, CheckTracking)


    elseif event == "UNIT_AURA" then

        -- buffs changed (e.g. a Hunter Aspect added, swapped or removed);
        -- fires often, so only queue one check at a time
        if auraCheckPending or UnitIsDeadOrGhost("player") then
            return
        end

        auraCheckPending = true

        -- wait out the global cooldown the Aspect triggered before casting
        C_Timer.After(1.6, function()
            auraCheckPending = false

            if addonEnabled then
                CheckTracking()
            end
        end)


    elseif event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" then

        -- skill data often isn't ready at login; re-check when it loads
        CheckProfessions()
        UpdateToggleButton()

        C_Timer.After(0.25, CheckTracking)


    elseif event == "PLAYER_UNGHOST" then

        miningRequest = false
        herbalismRequest = false

        C_Timer.After(0.25, CheckTracking)

    end
end


frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterUnitEvent("UNIT_AURA", "player")

frame:SetScript("OnEvent", OnEvent)