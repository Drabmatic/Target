local addonName, addon = ...

-- Default values for settings
local defaultSettings = 
{
    xValue = 0,
    yValue = 0,
    iconType = "default", -- default icon type
    iconSize = "default" -- default icon size
}

local iconTypes = {
    default = {suffix = "", useClassColor = false},
    circle = {suffix = "-circle", useClassColor = false},
    classColor = {suffix = "-color", useClassColor = true}
}

local presetSizes = {
    small = {width = 10, height = 10},
    medium = {width = 20, height = 20},
    default = {width = 32, height = 32},
    bigger = {width = 40, height = 40},
    biggest = {width = 50, height = 50}
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

local players = {} -- Table to store player objects

function createPlayer(unitId)
    local player = players[unitId] or {} -- Reuse player objects if available
    players[unitId] = player -- Store player object in the table

    player.unitId = unitId
    player.targetId = unitId .. "target"
    player.guid = UnitGUID(unitId) or "" -- Assign an empty string if GUID is nil
    player.class = select(2, UnitClass(unitId)) or "Unknown" -- Assign a default value if class is nil
    player.class = player.class:lower()

    local iconType = iconTypes[Target_Settings.iconType] or iconTypes["default"]
    local classImage = player.class .. iconType.suffix .. ".tga"

    if not player.texture then
        player.texture = frame:CreateTexture(player.guid .. "-Texture", "OVERLAY")
    end
    local iconSize = Target_Settings.iconSize or 32
    player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
    player.texture:SetSize(iconSize, iconSize)

    return player
end

function clearPlayers()
    wipe(players) -- Directly clear the table
end

function initializePlayers()
    clearPlayers()

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
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end

        initializeUI()
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
    for key, value in pairs(nameplateFrames) do
        value:Hide()
        nameplateFrames[key] = nil
    end

    local currentCounts = {}
    local xOffset = Target_Settings.xValue
    local yOffset = Target_Settings.yValue

    for unitId, player in pairs(players) do
        local targetIdExists = UnitExists(player.targetId)
        if UnitExists(unitId) and targetIdExists and not UnitIsUnit("target", "player") then
            local nameplate = C_NamePlate.GetNamePlateForUnit(player.targetId)
            if nameplate and player.texture then
                local targetGUID  = UnitGUID(player.targetId) or ""
                local targetCount = getTargetCount(targetGUID)
                local width, height = player.texture:GetSize()
                local nameplateFrame = nameplateFrames[targetGUID]

                if not nameplateFrame then
                    nameplateFrame = CreateFrame("Frame", nil, nameplate)
                    nameplateFrames[targetGUID] = nameplateFrame
                    nameplateFrame:SetSize(width * targetCount, height)
                    nameplateFrame:SetPoint("BOTTOM", nameplate, "TOP", xOffset, yOffset)
                    nameplateFrame:Show()
                end

                currentCounts[targetGUID] = (currentCounts[targetGUID] or 0) + 1

                player.texture:SetParent(nameplateFrame)
                player.texture:SetPoint("LEFT", nameplateFrame, "LEFT", (currentCounts[targetGUID] - 1) * width, 0)
                player.texture:Show()
            end
        end
    end

    C_Timer.After(0.2, updateNamePlates)
end

function initializeUI()
    addon.optionsFrame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
    addon.optionsFrame.name = addonName
    InterfaceOptions_AddCategory(addon.optionsFrame)

    -- X Offset Slider
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
        if addon.xInput:GetText() ~= tostring(value) then
            addon.xInput:SetText(tostring(value))
        end
    end)
    addon.xSlider:Show()

    -- X Offset Label
    addon.xLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.xLabel:SetPoint("TOPLEFT", addon.xSlider, "BOTTOMLEFT", 0, -5)
    addon.xLabel:SetText("X Offset")
    addon.xLabel:Show()

    -- X Offset Input Box
    addon.xInput = CreateFrame("EditBox", "TargetXInput", addon.optionsFrame, "InputBoxTemplate")
    addon.xInput:SetPoint("TOP", addon.xSlider, "BOTTOM", 0, -5)
    addon.xInput:SetSize(80, 20)
    addon.xInput:SetText(tostring(Target_Settings.xValue))
    addon.xInput:SetAutoFocus(false)
    addon.xInput:SetCursorPosition(0)
    addon.xInput:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or Target_Settings.xValue
        value = math.min(math.max(value, -200), 200)
        self:SetText(tostring(value))
        addon.xSlider:SetValue(value)
        Target_Settings.xValue = value
    end)
    addon.xInput:Show()

    -- Y Offset Slider
    addon.ySlider = CreateFrame("Slider", "TargetYSlider", addon.optionsFrame, "OptionsSliderTemplate")
    addon.ySlider:SetPoint("TOP", addon.xInput, "BOTTOM", 0, -20)
    addon.ySlider:SetMinMaxValues(-200, 200)
    addon.ySlider:SetValue(Target_Settings.yValue)
    addon.ySlider:SetValueStep(1)
    addon.ySlider:SetObeyStepOnDrag(true)
    addon.ySlider:SetWidth(200)
    addon.ySlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("Y Offset: " .. floor(value))
        Target_Settings.yValue = value
        if addon.yInput:GetText() ~= tostring(value) then
            addon.yInput:SetText(tostring(value))
        end
    end)
    addon.ySlider:Show()

    -- Y Offset Label
    addon.yLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.yLabel:SetPoint("TOPLEFT", addon.ySlider, "BOTTOMLEFT", 0, -5)
    addon.yLabel:SetText("Y Offset")
    addon.yLabel:Show()

    -- Y Offset Input Box
    addon.yInput = CreateFrame("EditBox", "TargetYInput", addon.optionsFrame, "InputBoxTemplate")
    addon.yInput:SetPoint("TOP", addon.ySlider, "BOTTOM", 0, -5)
    addon.yInput:SetSize(80, 20)
    addon.yInput:SetText(tostring(Target_Settings.yValue))
    addon.yInput:SetAutoFocus(false)
    addon.yInput:SetCursorPosition(0)
    addon.yInput:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or Target_Settings.yValue
        value = math.min(math.max(value, -200), 200)
        self:SetText(tostring(value))
        addon.ySlider:SetValue(value)
        Target_Settings.yValue = value
    end)
    addon.yInput:Show()

    -- Icon Style Label
    addon.iconStyleLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.iconStyleLabel:SetPoint("TOPLEFT", addon.yInput, "BOTTOMLEFT", 0, -20)
    addon.iconStyleLabel:SetText("Icon Style")
    addon.iconStyleLabel:Show()

    -- Icon Type Dropdown Menu
    addon.iconTypeDropdown = CreateFrame("Frame", "TargetIconTypeDropdown", addon.optionsFrame, "UIDropDownMenuTemplate")
    addon.iconTypeDropdown:SetPoint("TOPLEFT", addon.iconStyleLabel, "BOTTOMLEFT", 0, -5)
    addon.iconTypeDropdown.initialize = function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for iconType, data in pairs(iconTypes) do
            info.text = iconType
            info.func = function()
                Target_Settings.iconType = iconType
                UIDropDownMenu_SetText(addon.iconTypeDropdown, iconType)
                initializePlayers()
                updateNamePlates()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_SetWidth(addon.iconTypeDropdown, 150)
    UIDropDownMenu_SetButtonWidth(addon.iconTypeDropdown, 174)
    UIDropDownMenu_JustifyText(addon.iconTypeDropdown, "CENTER")
    UIDropDownMenu_SetText(addon.iconTypeDropdown, Target_Settings.iconType)
    addon.iconTypeDropdown:Show()

    -- Icon Size Slider
    addon.iconSizeSlider = CreateFrame("Slider", "TargetIconSizeSlider", addon.optionsFrame, "OptionsSliderTemplate")
    addon.iconSizeSlider:SetPoint("TOPLEFT", addon.iconTypeDropdown, "BOTTOMLEFT", 0, -20)
    addon.iconSizeSlider:SetMinMaxValues(1, 100)
    addon.iconSizeSlider:SetValue(tonumber(Target_Settings.iconSize) or 32)
    addon.iconSizeSlider:SetValueStep(1)
    addon.iconSizeSlider:SetObeyStepOnDrag(true)
    addon.iconSizeSlider:SetWidth(200)
    addon.iconSizeSlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("Icon Size: " .. floor(value))
        Target_Settings.iconSize = value
        initializePlayers()
        updateNamePlates()
    end)
    addon.iconSizeSlider:Show()

    -- Icon Size Label
    addon.iconSizeLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.iconSizeLabel:SetPoint("TOPLEFT", addon.iconSizeSlider, "BOTTOMLEFT", 0, -5)
    addon.iconSizeLabel:SetText("Icon Size")
    addon.iconSizeLabel:Show()

    -- Discord Link Label
    addon.discordLinkLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.discordLinkLabel:SetPoint("TOPLEFT", addon.iconSizeLabel, "BOTTOMLEFT", 0, -20)
    addon.discordLinkLabel:SetText("Discord Link")
    addon.discordLinkLabel:Show()

    -- Discord Link Input Box
    addon.discordLinkInput = CreateFrame("EditBox", "TargetDiscordLinkInput", addon.optionsFrame, "InputBoxTemplate")
    addon.discordLinkInput:SetPoint("TOPLEFT", addon.discordLinkLabel, "BOTTOMLEFT", 0, -5)
    addon.discordLinkInput:SetSize(200, 20)
    addon.discordLinkInput:SetText("https://discord.gg/dmwegA6Z")
    addon.discordLinkInput:SetAutoFocus(false)
    addon.discordLinkInput:SetCursorPosition(0)
    addon.discordLinkInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    addon.discordLinkInput:Show()

    function addon.optionsFrame:refresh()
        local isVisible = addon.optionsFrame:IsShown()
        addon.optionsFrame:SetShown(not isVisible)
    end
end
