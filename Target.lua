local addonName, addon = ...

-- Default values for settings
local defaultSettings = 
{
    xValue = 0,
    yValue = 0,
    transparent = true
}

-- Initialize your Saved Variables table
-- Target_Settings = Target_Settings or CopyTable(defaultSettings) -- Moved to PLAYER_LOGIN

-- Auto generating the name based on class
-- local classTextureFiles = 
-- {
--     warrior     = "warrior",
--     hunter      = "hunter",
--     mage        = "mage",
--     rogue       = "rogue",
--     druid       = "druid",
--     paladin     = "paladin",
--     shaman      = "shaman",
--     priest      = "priest",
--     deathknight = "deathknight",
--     warlock     = "warlock",
--     monk        = "monk",
--     demonhunter = "demonhunter",
--     evoker      = "evoker"
-- }

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

function createPlayer(unitId)
    local player = nil

    if UnitExists(unitId) then
        player = {}
        player.unitId   = unitId
        player.targetId = unitId .. "target"
        player.guid     = UnitGUID(unitId)
        player.class    = select(2, UnitClass(unitId))
        if player.class then
            player.class = player.class:lower()
        end

        -- auto generate class image based on class name and transparency user setting.
        local classImage = player.class .. (Target_Settings.transparent and "-circle" or "") .. ".tga"

        player.texture  = frame:CreateTexture(player.guid .. "-Texture", "OVERLAY")
        player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
        player.texture:SetSize(32, 32)
    end

    return player
end

function clearPlayers(players)
    -- clear out existing player textures
    if players then
        for unitId, player in pairs(players) do
            if player.texture then
                player.texture:Hide()
                player.texture = nil
            end
        end
    end
    players = {}
end

local players = {}

function initializePlayers()
    -- recreate roster
    clearPlayers(players)

    players["player"] = createPlayer("player")
    players["party1"] = createPlayer("party1")
    players["party2"] = createPlayer("party2")
    players["party3"] = createPlayer("party3")
    players["party4"] = createPlayer("party4")
end

function OnEvent(self, event, ...)
    local arg1 = ...
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        initializePlayers()
    elseif event == "ADDON_LOADED" and arg1 == addonName then
    elseif event == "PLAYER_LOGIN" then
        -- Load the saved settings
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end

        initializeUI()
        -- Initial call to updateNamePlates
        updateNamePlates()
    end
end

frame:SetScript("OnEvent", OnEvent)

function getTargetCount(unitGuid)
    local count = 0
    for unitId, player in pairs(players) do
        if unitGuid == UnitGUID(player.targetId) then
            count = count + 1
        end
    end
    return count
end

local nameplateFrames = {}

function updateNamePlates(self)
    -- remove current frames
    for key, value in pairs(nameplateFrames) do
        value:Hide()
        nameplateFrames[key] = nil
    end

    local currentCounts = {}
    for unitId, player in pairs(players) do
        -- target is showing on personal resource bar if i target myself :)
        if UnitExists(unitId) and UnitExists(player.targetId) and not UnitIsUnit("target", "player") then
            local nameplate = C_NamePlate.GetNamePlateForUnit(player.targetId)
            if nameplate and player.texture then
                local targetGUID  = UnitGUID(player.targetId)
                local targetCount = getTargetCount(targetGUID)

                -- create a frame to hold all the textures on the nameplate
                local width, height = player.texture:GetSize()
                if not nameplateFrames[targetGUID] then
                    nameplateFrames[targetGUID] = CreateFrame("Frame", nil, nameplate)

                    -- set the overall size and center it
                    local xOffset = Target_Settings.xValue
                    local yOffset = Target_Settings.yValue
    
                    nameplateFrames[targetGUID]:SetSize(width * targetCount, height)
                    nameplateFrames[targetGUID]:SetPoint("BOTTOM", nameplate, "TOP", xOffset, yOffset)
                    nameplateFrames[targetGUID]:Show()
                end

                -- now add the player texture at correct position within frame
                if currentCounts[targetGUID] then
                    currentCounts[targetGUID] = currentCounts[targetGUID] + 1
                else
                    currentCounts[targetGUID] = 0
                end

                player.texture:SetParent(nameplateFrames[targetGUID])
                player.texture:SetPoint("LEFT", nameplateFrames[targetGUID], "LEFT", currentCounts[targetGUID] * width, 0)
                player.texture:Show()
            end
        end
    end

    C_Timer.After(0.2, updateNamePlates)
end

function initializeUI()
    -- Create a frame for options
    addon.optionsFrame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
    addon.optionsFrame.name = addonName
    InterfaceOptions_AddCategory(addon.optionsFrame)

    -- Create X slider
    addon.xSlider = CreateFrame("Slider", "TargetXSlider", addon.optionsFrame, "OptionsSliderTemplate")
    addon.xSlider:SetPoint("TOP", addon.optionsFrame, "TOP", 0, -20)
    addon.xSlider:SetMinMaxValues(-200, 200)
    addon.xSlider:SetValue(Target_Settings.xValue)
    addon.xSlider:SetValueStep(1)
    addon.xSlider:SetObeyStepOnDrag(true)
    addon.xSlider:SetWidth(200)
    addon.xSlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("X Offset: " .. floor(value))
        Target_Settings.xValue = value
    end)
    addon.xSlider:Show()

    -- Create Y slider
    addon.ySlider = CreateFrame("Slider", "TargetYSlider", addon.optionsFrame, "OptionsSliderTemplate")
    addon.ySlider:SetPoint("TOP", addon.xSlider, "BOTTOM", 0, -20)
    addon.ySlider:SetMinMaxValues(-200, 200)
    addon.ySlider:SetValue(Target_Settings.yValue)
    addon.ySlider:SetValueStep(1)
    addon.ySlider:SetObeyStepOnDrag(true)
    addon.ySlider:SetWidth(200)
    addon.ySlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("Y Offset: " .. floor(value))
        Target_Settings.yValue = value
    end)
    addon.ySlider:Show()

    -- Create transparent option
    addon.transparentCheck = CreateFrame("CheckButton", "TargetTransparentCheckButton", addon.optionsFrame, "UICheckButtonTemplate")
    addon.transparentCheck:SetPoint("TOP", addon.ySlider, "BOTTOM", 0, -20)
    addon.transparentCheck.text:SetText("Transparent Background")
    addon.transparentCheck:SetChecked(Target_Settings.transparent)
    -- addon.transparentCheck.text.tooltip = "Swap between class color backgrounds and transparent backgrounds."
    addon.transparentCheck:SetScript("OnClick", function(frame)
        local checked = frame:GetChecked()
        Target_Settings.transparent = checked
        initializePlayers()
        updateNamePlates()
    end)
    addon.transparentCheck:Show()

    -- Function to show/hide the options frame
    function addon.optionsFrame:refresh()
        local isVisible = addon.optionsFrame:IsShown()
        addon.optionsFrame:SetShown(not isVisible)
    end
end


