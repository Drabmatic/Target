local addonName, addon = ...

-- Default values for settings
local defaultSettings = 
{
    xValue = 0,
    yValue = 0,
    transparent = true,
    useClassColor = false,
    iconSize = "default" -- default icon size preset
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

        local classImage
        if Target_Settings.useClassColor then
            classImage = player.class .. "-color" .. (Target_Settings.transparent and "-circle" or "") .. ".tga"
        else
            classImage = player.class .. (Target_Settings.transparent and "-circle" or "") .. ".tga"
        end

        player.texture  = frame:CreateTexture(player.guid .. "-Texture", "OVERLAY")
        local iconSize = presetSizes[Target_Settings.iconSize] or presetSizes["default"] -- fallback to default if preset not found
        player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
        player.texture:SetSize(iconSize.width, iconSize.height)
    end

    return player
end

function clearPlayers(players)
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
    for unitId, player in pairs(players) do
        if UnitExists(unitId) and UnitExists(player.targetId) and not UnitIsUnit("target", "player") then
            local nameplate = C_NamePlate.GetNamePlateForUnit(player.targetId)
            if nameplate and player.texture then
                local targetGUID  = UnitGUID(player.targetId)
                local targetCount = getTargetCount(targetGUID)

                local width, height = player.texture:GetSize()
                if not nameplateFrames[targetGUID] then
                    nameplateFrames[targetGUID] = CreateFrame("Frame", nil, nameplate)

                    local xOffset = Target_Settings.xValue
                    local yOffset = Target_Settings.yValue
    
                    nameplateFrames[targetGUID]:SetSize(width * targetCount, height)
                    nameplateFrames[targetGUID]:SetPoint("BOTTOM", nameplate, "TOP", xOffset, yOffset)
                    nameplateFrames[targetGUID]:Show()
                end

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
    addon.optionsFrame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
    addon.optionsFrame.name = addonName
    InterfaceOptions_AddCategory(addon.optionsFrame)

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

    addon.transparentCheck = CreateFrame("CheckButton", "TargetTransparentCheckButton", addon.optionsFrame, "UICheckButtonTemplate")
    addon.transparentCheck:SetPoint("TOP", addon.yInput, "BOTTOM", 0, -20)
    addon.transparentCheck.text:SetText("Transparent Background")
    addon.transparentCheck:SetChecked(Target_Settings.transparent)
    addon.transparentCheck:SetScript("OnClick", function(frame)
        local checked = frame:GetChecked()
        Target_Settings.transparent = checked
        initializePlayers()
        updateNamePlates()
    end)
    addon.transparentCheck:Show()

    addon.classColorCheck = CreateFrame("CheckButton", "TargetClassColorCheckButton", addon.optionsFrame, "UICheckButtonTemplate")
    addon.classColorCheck:SetPoint("TOP", addon.transparentCheck, "BOTTOM", 0, -20)
    addon.classColorCheck.text:SetText("Use Class Colors")
    addon.classColorCheck:SetChecked(Target_Settings.useClassColor)
    addon.classColorCheck:SetScript("OnClick", function(frame)
        local checked = frame:GetChecked()
        Target_Settings.useClassColor = checked
        initializePlayers()
        updateNamePlates()
    end)
    addon.classColorCheck:Show()

    addon.sizeDropdown = CreateFrame("Frame", "TargetSizeDropdown", addon.optionsFrame, "UIDropDownMenuTemplate")
    addon.sizeDropdown:SetPoint("TOP", addon.classColorCheck, "BOTTOM", 0, -20)
    addon.sizeDropdown.initialize = function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for size, dimensions in pairs(presetSizes) do
            info.text = size
            info.func = function()
                Target_Settings.iconSize = size
                UIDropDownMenu_SetText(addon.sizeDropdown, size)
                initializePlayers()
                updateNamePlates()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_SetWidth(addon.sizeDropdown, 100)
    UIDropDownMenu_SetButtonWidth(addon.sizeDropdown, 124)
    UIDropDownMenu_JustifyText(addon.sizeDropdown, "CENTER")
    UIDropDownMenu_SetText(addon.sizeDropdown, Target_Settings.iconSize)
    addon.sizeDropdown:Show()

    addon.discordLinkInput = CreateFrame("EditBox", "TargetDiscordLinkInput", addon.optionsFrame, "InputBoxTemplate")
    addon.discordLinkInput:SetPoint("TOP", addon.sizeDropdown, "BOTTOM", 0, -20)
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
