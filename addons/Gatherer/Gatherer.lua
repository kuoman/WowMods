-- Gatherer (c) 2026 Status kuo
-- Licensed under the GNU General License (see LICENSE file)

print("========================================")
print("|cff69BE28          Gatherer         |r")
print("========================================")

local frame = CreateFrame("Frame")


local addonEnabled = true
local isMiner = false
local isPicker = false
local hasTreasure = false

local treasureRequest = false
local herbalismRequest = false
local miningRequest = false

local isHunter = false
local lastGatherer = nil -- "Find Minerals" or "Find Herbs", whichever was last seen active


local function CheckProfessions()

    isMiner = false
    isPicker = false

    local _, classToken = UnitClass("player")
    isHunter = classToken == "HUNTER"

    local profession1, profession2 = GetProfessions()

    local professions = { profession1, profession2 }

    for tableIndex, professionIndex in pairs(professions) do

        if professionIndex then

            local name = GetProfessionInfo(professionIndex)

            if name == "Mining" then
                isMiner = true
                print("Profession: Mining detected.")

            elseif name == "Herbalism" then
                isPicker = true
                print("Profession: Herbalism detected.")
            end
        end
    end
end


local function FindTracker(trackerName)

    local numberOfTrackers = C_Minimap.GetNumTrackingTypes()

    for i = 1, numberOfTrackers do

        local info = C_Minimap.GetTrackingInfo(i)

        if info and info.name == trackerName then
            return i, info.active
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


-- the gather tracker to restore: the only one the player has, otherwise the
-- one they last used (Find Minerals by default)
local function GetPreferredTracker()

    if isMiner and not isPicker then
        return "Find Minerals"
    elseif isPicker and not isMiner then
        return "Find Herbs"
    elseif isMiner and isPicker then
        return lastGatherer or "Find Minerals"
    end

    return nil
end


local function CheckRace()

    if UnitIsDeadOrGhost("player") then
        return
    end

    -- a Hunter chose a Track ability; leave it until they use the button
    if FindActiveHunterTrack() then
        return
    end

    local raceName, raceToken, raceID = UnitRace("player")

    if raceName == "Dwarf" then

        local treasureIndex, treasureActive = FindTracker("Find Treasure")

        if treasureActive then
            treasureRequest = false
            return
        end

        if treasureIndex and not treasureRequest then

            treasureRequest = true

            print("Dwarf Race detected. Enabling Find Treasure tracking.")

            C_Minimap.SetTracking(treasureIndex, true)

            C_Timer.After(0.25, function()

                local _, treasureActiveNow = FindTracker("Find Treasure")

                if treasureActiveNow then
                    print("Gatherer: Find Treasure active.")
                else
                    print("Gatherer: Could not enable Find Treasure.")
                end

                treasureRequest = false

            end)
        end
    end
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
        lastGatherer = "Find Herbs"
    elseif mineralsActive then
        lastGatherer = "Find Minerals"
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


    elseif isMiner and isPicker then

        -- only one tracker can be active at a time; default to Find Minerals
        -- when neither is on, and leave the player's choice (toggle button) alone
        if not mineralsActive and not herbsActive then

            if mineralIndex and not miningRequest then

                miningRequest = true

                C_Minimap.SetTracking(mineralIndex, true)

                VerifyTracking("Find Minerals", function() miningRequest = false end)
            end
        end
    end
end


-- on-screen toggle between Find Minerals / Find Herbs (Mining + Herbalism only)
local MINERALS_ICON = 136025 -- Spell_Nature_Earthquake
local HERBS_ICON = 133939 -- INV_Misc_Flower_02

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

    -- Hunter Track active: show the button (even with only one gathering
    -- profession) so a click can switch back to herbs/minerals
    local hunterTrackIndex, hunterTrackInfo = FindActiveHunterTrack()

    if hunterTrackIndex and GetPreferredTracker() then

        if hunterTrackInfo.texture then
            toggleButton.icon:SetTexture(hunterTrackInfo.texture)
        elseif GetPreferredTracker() == "Find Herbs" then
            toggleButton.icon:SetTexture(HERBS_ICON)
        else
            toggleButton.icon:SetTexture(MINERALS_ICON)
        end

        toggleButton.icon:SetDesaturated(false)
        toggleButton:Show()
        return
    end

    if not (isMiner and isPicker) then
        toggleButton:Hide()
        return
    end

    local _, mineralsActive = FindTracker("Find Minerals")
    local _, herbsActive = FindTracker("Find Herbs")

    if herbsActive then
        toggleButton.icon:SetTexture(HERBS_ICON)
    else
        toggleButton.icon:SetTexture(MINERALS_ICON)
    end

    -- greyed out when neither tracker is on
    toggleButton.icon:SetDesaturated(not mineralsActive and not herbsActive)

    toggleButton:Show()
end


toggleButton:SetScript("OnClick", function(self)

    if UnitIsDeadOrGhost("player") then
        return
    end

    -- Hunter Track active: enabling a gather tracker replaces it, since only
    -- one tracker can be on at a time
    if FindActiveHunterTrack() then

        local gatherIndex = FindTracker(GetPreferredTracker())

        if gatherIndex then
            C_Minimap.SetTracking(gatherIndex, true)
        end

        if GameTooltip:IsOwned(self) then
            self:GetScript("OnEnter")(self)
        end
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
    local hunterTrackIndex, hunterTrackInfo = FindActiveHunterTrack()

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Gatherer")

    if hunterTrackIndex then
        GameTooltip:AddLine("Tracking: " .. hunterTrackInfo.name, 1, 1, 1)
        GameTooltip:AddLine("Click to switch back to " .. (GetPreferredTracker() or "gathering") .. ".", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("Tracking: " .. (mineralsActive and "Find Minerals" or herbsActive and "Find Herbs" or "None"), 1, 1, 1)
        GameTooltip:AddLine("Click to switch Minerals / Herbs.", 0.7, 0.7, 0.7)
    end

    GameTooltip:Show()
end)

toggleButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)


-- player command to enable or diable the addon
SLASH_Gatherer1 = "/gatherer"
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
        treasureRequest = false

        C_Timer.After(0.25, function()
            CheckTracking()
            C_Timer.After(1.2, function()
                CheckRace()
            end)
        end)
    end
end



local function OnEvent(self, event)
    
    if not addonEnabled then
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then

        CheckProfessions()
        UpdateToggleButton()

        miningRequest = false
        herbalismRequest = false
        treasureRequest = false

        C_Timer.After(0.25, function()

            CheckTracking()

            C_Timer.After(1.2, function()
                CheckRace()
            end)

        end)


    elseif event == "MINIMAP_UPDATE_TRACKING" then

        UpdateToggleButton()

        if UnitIsDeadOrGhost("player") then
            return
        end

        CheckTracking()

        C_Timer.After(1.2, function()
            CheckRace()
        end)


    elseif event == "PLAYER_ALIVE" then

        if UnitIsDeadOrGhost("player") then
            return
        end

        miningRequest = false
        herbalismRequest = false
        treasureRequest = false

        C_Timer.After(0.25, function()

            CheckTracking()

            C_Timer.After(1.2, function()
                CheckRace()
            end)

        end)


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


    elseif event == "PLAYER_UNGHOST" then

        miningRequest = false
        herbalismRequest = false
        treasureRequest = false

        C_Timer.After(0.25, function()

            CheckTracking()

            C_Timer.After(1.2, function()
                CheckRace()
            end)

        end)

    end
end


frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterUnitEvent("UNIT_AURA", "player")

frame:SetScript("OnEvent", OnEvent)