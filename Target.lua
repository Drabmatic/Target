local addonName, addon = ...

-- Default values for settings
local defaultSettings = {
    xValue = 0,
    yValue = 0,
    iconType = "default",
    iconSize = 32,
    iconOpacity = 1.0,
    enableInOpenWorld = true,
    enableInArena = true,
    enableInBattleground = true,
    enableInRaid = true
}

local iconTypes = {
    default = { suffix = "", useClassColor = false },
    circle = { suffix = "-circle", useClassColor = false },
    classColor = { suffix = "-color", useClassColor = true }
}

local presetSizes = {
    small = { width = 10, height = 10 },
    medium = { width = 20, height = 20 },
    default = { width = 32, height = 32 },
    bigger = { width = 40, height = 40 },
    biggest = { width = 50, height = 50 }
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_TARGET")

local players = {}
local nameplateFrames = {}

-- Function to create or update a player object
local function createPlayer(unitId)
    local player = players[unitId] or {}
    players[unitId] = player

    player.unitId = unitId
    player.targetId = unitId .. "target"
    player.guid = UnitGUID(unitId) or ""
    player.class = select(2, UnitClass(unitId)) or ""
    if player.class then
        player.class = player.class:lower()
    end

    local iconType = iconTypes[Target_Settings.iconType] or iconTypes["default"]
    local classImage = player.class .. iconType.suffix .. ".tga"

    if not player.texture then
        player.texture = frame:CreateTexture(player.guid .. "-Texture", "OVERLAY")
    end
    local iconSize = tonumber(Target_Settings.iconSize) or 32
    player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
    player.texture:SetSize(iconSize, iconSize)
    player.texture:SetAlpha(Target_Settings.iconOpacity) -- Set opacity

    return player
end

local function clearPlayers()
    wipe(players)
end

local function initializePlayers()
    clearPlayers()
    players["player"] = createPlayer("player")
    for i = 1, 4 do
        players["party" .. i] = createPlayer("party" .. i)
    end
end

local function getTargetCount(unitGuid)
    local count = 0
    for _, player in pairs(players) do
        if unitGuid == UnitGUID(player.targetId) then
            count = count + 1
        end
    end
    return count
end

local function isAddonEnabled()
    local zoneType = select(2, IsInInstance())
    local zoneChecks = {
        none = Target_Settings.enableInOpenWorld,
        arena = Target_Settings.enableInArena,
        pvp = Target_Settings.enableInBattleground,
        raid = Target_Settings.enableInRaid
    }
    return zoneChecks[zoneType] or false
end

local function updateNamePlates()
    if not isAddonEnabled() then
        for _, frame in pairs(nameplateFrames) do
            frame:Hide()
        end
        wipe(nameplateFrames)
        return
    end

    local currentCounts = {}
    local xOffset, yOffset = Target_Settings.xValue, Target_Settings.yValue

    for unitId, player in pairs(players) do
        if UnitExists(unitId) and UnitExists(player.targetId) and not UnitIsUnit("target", "player") then
            local nameplate = C_NamePlate.GetNamePlateForUnit(player.targetId)
            if nameplate and player.texture then
                local targetGUID = UnitGUID(player.targetId)
                local targetCount = getTargetCount(targetGUID)
                local width, height = player.texture:GetSize()
                local nameplateFrame = nameplateFrames[targetGUID]

                if not nameplateFrame then
                    nameplateFrame = CreateFrame("Frame", nil, nameplate)
                    nameplateFrames[targetGUID] = nameplateFrame
                end
                nameplateFrame:SetSize(width * targetCount, height)
                nameplateFrame:SetPoint("BOTTOM", nameplate, "TOP", xOffset, yOffset)
                nameplateFrame:Show()

                currentCounts[targetGUID] = (currentCounts[targetGUID] or 0) + 1

                player.texture:SetParent(nameplateFrame)
                player.texture:SetPoint("LEFT", nameplateFrame, "LEFT", (currentCounts[targetGUID] - 1) * width, 0)
                player.texture:Show()
            end
        end
    end
end

local function clearNamePlates()
    for _, frame in pairs(nameplateFrames) do
        frame:Hide()
    end
    wipe(nameplateFrames)
end

-- Debounce function to limit how often a function can run
local function debounce(func, delay)
    local last = 0
    return function(...)
        local now = GetTime()
        if now - last >= delay then
            last = now
            return func(...)
        end
    end
end

local debouncedUpdateNamePlates = debounce(updateNamePlates, 0.1)

local function OnEvent(self, event, ...)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        initializePlayers()
        clearNamePlates()
        debouncedUpdateNamePlates()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_TARGET" then
        clearNamePlates()
        debouncedUpdateNamePlates()
    elseif event == "ADDON_LOADED" and ... == addonName then
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end
        if not Target_Profiles then
            Target_Profiles = { ["Default"] = CopyTable(defaultSettings) }
        end
        if not Target_CurrentProfile then
            Target_CurrentProfile = "Default"
        end

        -- Load the current profile
        profiles = Target_Profiles
        currentProfile = Target_CurrentProfile
        Target_Settings = profiles[currentProfile]

        initializeUI()
    elseif event == "PLAYER_LOGIN" then
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end
        initializeUI()
        debouncedUpdateNamePlates()
    end
end

frame:SetScript("OnEvent", OnEvent)

-- Function to generate a unique profile name
local function generateUniqueProfileName(baseName)
    local counter = 1
    local uniqueName = baseName

    while profiles[uniqueName] do
        uniqueName = baseName .. " " .. counter
        counter = counter + 1
    end

    return uniqueName
end

function initializeUI()
    -- Create the main options frame
    local optionsFrame = CreateFrame("Frame", "TargetOptionsFrame", UIParent)
    optionsFrame.name = addonName

    -- Create title
    local title = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Target Addon Settings")

    -- X Offset Slider
    local xSlider = CreateFrame("Slider", "TargetXSlider", optionsFrame, "OptionsSliderTemplate")
    xSlider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -40)
    xSlider:SetMinMaxValues(-200, 200)
    xSlider:SetValue(Target_Settings.xValue)
    xSlider:SetValueStep(1)
    xSlider:SetObeyStepOnDrag(true)
    xSlider:SetWidth(200)
    xSlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("X Offset: " .. floor(value))
        Target_Settings.xValue = value
        if xInput:GetText() ~= tostring(value) then
            xInput:SetText(tostring(value))
        end
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    xSlider:Show()

    -- X Offset Label
    local xLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xLabel:SetPoint("TOPLEFT", xSlider, "BOTTOMLEFT", 0, -5)
    xLabel:SetText("X Offset")
    xLabel:Show()

    -- X Offset Input Box
    local xInput = CreateFrame("EditBox", "TargetXInput", optionsFrame, "InputBoxTemplate")
    xInput:SetPoint("TOP", xSlider, "BOTTOM", 0, -25)
    xInput:SetSize(80, 20)
    xInput:SetText(tostring(Target_Settings.xValue))
    xInput:SetAutoFocus(false)
    xInput:SetCursorPosition(0)
    xInput:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or Target_Settings.xValue
        value = math.min(math.max(value, -200), 200)
        self:SetText(tostring(value))
        xSlider:SetValue(value)
        Target_Settings.xValue = value
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    xInput:Show()

    -- Y Offset Slider
    local ySlider = CreateFrame("Slider", "TargetYSlider", optionsFrame, "OptionsSliderTemplate")
    ySlider:SetPoint("TOP", xInput, "BOTTOM", 0, -40)
    ySlider:SetMinMaxValues(-200, 200)
    ySlider:SetValue(Target_Settings.yValue)
    ySlider:SetValueStep(1)
    ySlider:SetObeyStepOnDrag(true)
    ySlider:SetWidth(200)
    ySlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("Y Offset: " .. floor(value))
        Target_Settings.yValue = value
        if yInput:GetText() ~= tostring(value) then
            yInput:SetText(tostring(value))
        end
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    ySlider:Show()

    -- Y Offset Label
    local yLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    yLabel:SetPoint("TOPLEFT", ySlider, "BOTTOMLEFT", 0, -5)
    yLabel:SetText("Y Offset")
    yLabel:Show()

    -- Y Offset Input Box
    local yInput = CreateFrame("EditBox", "TargetYInput", optionsFrame, "InputBoxTemplate")
    yInput:SetPoint("TOP", ySlider, "BOTTOM", 0, -25)
    yInput:SetSize(80, 20)
    yInput:SetText(tostring(Target_Settings.yValue))
    yInput:SetAutoFocus(false)
    yInput:SetCursorPosition(0)
    yInput:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or Target_Settings.yValue
        value = math.min(math.max(value, -200), 200)
        self:SetText(tostring(value))
        ySlider:SetValue(value)
        Target_Settings.yValue = value
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    yInput:Show()

    -- Icon Style Label
    local iconStyleLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iconStyleLabel:SetPoint("TOPLEFT", yInput, "BOTTOMLEFT", 0, -40)
    iconStyleLabel:SetText("Icon Style")
    iconStyleLabel:Show()

    -- Icon Type Dropdown Menu
    local iconTypeDropdown = CreateFrame("Frame", "TargetIconTypeDropdown", optionsFrame, "UIDropDownMenuTemplate")
    iconTypeDropdown:SetPoint("TOPLEFT", iconStyleLabel, "BOTTOMLEFT", 0, -5)
    iconTypeDropdown.initialize = function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for iconType, data in pairs(iconTypes) do
            info.text = iconType
            info.func = function()
                Target_Settings.iconType = iconType
                UIDropDownMenu_SetText(iconTypeDropdown, iconType)
                initializePlayers()
                debouncedUpdateNamePlates() -- Update in real-time
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_SetWidth(iconTypeDropdown, 150)
    UIDropDownMenu_SetButtonWidth(iconTypeDropdown, 174)
    UIDropDownMenu_JustifyText(iconTypeDropdown, "CENTER")
    UIDropDownMenu_SetText(iconTypeDropdown, Target_Settings.iconType)
    iconTypeDropdown:Show()

    -- Icon Size Slider
    local iconSizeSlider = CreateFrame("Slider", "TargetIconSizeSlider", optionsFrame, "OptionsSliderTemplate")
    iconSizeSlider:SetPoint("TOPLEFT", iconTypeDropdown, "BOTTOMLEFT", 0, -40)
    iconSizeSlider:SetMinMaxValues(1, 100)
    iconSizeSlider:SetValue(tonumber(Target_Settings.iconSize) or 32)
    iconSizeSlider:SetValueStep(1)
    iconSizeSlider:SetObeyStepOnDrag(true)
    iconSizeSlider:SetWidth(200)
    iconSizeSlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("Icon Size: " .. floor(value))
        Target_Settings.iconSize = value
        initializePlayers()
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    iconSizeSlider:Show()

    -- Icon Size Label
    local iconSizeLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iconSizeLabel:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -5)
    iconSizeLabel:SetText("Icon Size")
    iconSizeLabel:Show()

    -- Icon Opacity Slider
    local iconOpacitySlider = CreateFrame("Slider", "TargetIconOpacitySlider", optionsFrame, "OptionsSliderTemplate")
    iconOpacitySlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -40)
    iconOpacitySlider:SetMinMaxValues(0.1, 1.0)
    iconOpacitySlider:SetValue(tonumber(Target_Settings.iconOpacity) or 1.0)
    iconOpacitySlider:SetValueStep(0.1)
    iconOpacitySlider:SetObeyStepOnDrag(true)
    iconOpacitySlider:SetWidth(200)
    iconOpacitySlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("Icon Opacity: " .. string.format("%.1f", value))
        Target_Settings.iconOpacity = value
        initializePlayers()
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    iconOpacitySlider:Show()

    -- Icon Opacity Label
    local iconOpacityLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iconOpacityLabel:SetPoint("TOPLEFT", iconOpacitySlider, "BOTTOMLEFT", 0, -5)
    iconOpacityLabel:SetText("Icon Opacity")
    iconOpacityLabel:Show()

    -- Enable in Open World Checkbox
    local enableInOpenWorldCheckbox = CreateFrame("CheckButton", "TargetEnableInOpenWorldCheckbox", optionsFrame, "UICheckButtonTemplate")
    enableInOpenWorldCheckbox:SetPoint("TOPLEFT", iconOpacityLabel, "BOTTOMLEFT", 0, -20)
    enableInOpenWorldCheckbox.text:SetText("Enable in Open World")
    enableInOpenWorldCheckbox:SetChecked(Target_Settings.enableInOpenWorld)
    enableInOpenWorldCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInOpenWorld = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    enableInOpenWorldCheckbox:Show()

    -- Enable in Arena Checkbox
    local enableInArenaCheckbox = CreateFrame("CheckButton", "TargetEnableInArenaCheckbox", optionsFrame, "UICheckButtonTemplate")
    enableInArenaCheckbox:SetPoint("TOPLEFT", enableInOpenWorldCheckbox, "BOTTOMLEFT", 0, -5)
    enableInArenaCheckbox.text:SetText("Enable in Arena")
    enableInArenaCheckbox:SetChecked(Target_Settings.enableInArena)
    enableInArenaCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInArena = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    enableInArenaCheckbox:Show()

    -- Enable in Battleground Checkbox
    local enableInBattlegroundCheckbox = CreateFrame("CheckButton", "TargetEnableInBattlegroundCheckbox", optionsFrame, "UICheckButtonTemplate")
    enableInBattlegroundCheckbox:SetPoint("TOPLEFT", enableInArenaCheckbox, "BOTTOMLEFT", 0, -5)
    enableInBattlegroundCheckbox.text:SetText("Enable in Battleground")
    enableInBattlegroundCheckbox:SetChecked(Target_Settings.enableInBattleground)
    enableInBattlegroundCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInBattleground = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    enableInBattlegroundCheckbox:Show()

    -- Enable in Raid Checkbox
    local enableInRaidCheckbox = CreateFrame("CheckButton", "TargetEnableInRaidCheckbox", optionsFrame, "UICheckButtonTemplate")
    enableInRaidCheckbox:SetPoint("TOPLEFT", enableInBattlegroundCheckbox, "BOTTOMLEFT", 0, -5)
    enableInRaidCheckbox.text:SetText("Enable in Raid")
    enableInRaidCheckbox:SetChecked(Target_Settings.enableInRaid)
    enableInRaidCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInRaid = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    enableInRaidCheckbox:Show()

    -- Profile Management
    local profileLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileLabel:SetPoint("TOPLEFT", enableInRaidCheckbox, "BOTTOMLEFT", 0, -40)
    profileLabel:SetText("Profile Management")
    profileLabel:Show()

    -- Profile Dropdown Menu
    local profileDropdown = CreateFrame("Frame", "TargetProfileDropdown", optionsFrame, "UIDropDownMenuTemplate")
    profileDropdown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -5)
    profileDropdown.initialize = function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for profileName in pairs(profiles) do
            info.text = profileName
            info.func = function()
                currentProfile = profileName
                Target_Settings = profiles[profileName]
                UIDropDownMenu_SetText(profileDropdown, profileName)
                initializePlayers()
                debouncedUpdateNamePlates()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_SetWidth(profileDropdown, 150)
    UIDropDownMenu_SetButtonWidth(profileDropdown, 174)
    UIDropDownMenu_JustifyText(profileDropdown, "CENTER")
    UIDropDownMenu_SetText(profileDropdown, currentProfile)
    profileDropdown:Show()

    -- Save Profile Button
    local saveProfileButton = CreateFrame("Button", "TargetSaveProfileButton", optionsFrame, "UIPanelButtonTemplate")
    saveProfileButton:SetPoint("TOPLEFT", profileDropdown, "BOTTOMLEFT", 0, -10)
    saveProfileButton:SetSize(120, 20)
    saveProfileButton:SetText("Save Profile")
    saveProfileButton:SetScript("OnClick", function()
        local profileName = currentProfile
        if profileName ~= "Default" and profiles[profileName] then
            StaticPopupDialogs["SAVE_PROFILE_CONFIRMATION"] = {
                text = "Overwrite existing profile " .. profileName .. "?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    profiles[profileName] = CopyTable(Target_Settings)
                    Target_Profiles = profiles
                    Target_CurrentProfile = currentProfile
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("SAVE_PROFILE_CONFIRMATION")
        else
            profiles[profileName] = CopyTable(Target_Settings)
            Target_Profiles = profiles
            Target_CurrentProfile = currentProfile
        end
    end)
    saveProfileButton:Show()

    -- New Profile Button
    local newProfileButton = CreateFrame("Button", "TargetNewProfileButton", optionsFrame, "UIPanelButtonTemplate")
    newProfileButton:SetPoint("TOPLEFT", saveProfileButton, "BOTTOMLEFT", 0, -10)
    newProfileButton:SetSize(120, 20)
    newProfileButton:SetText("New Profile")
    newProfileButton:SetScript("OnClick", function()
        local newProfileName = generateUniqueProfileName("Profile")
        profiles[newProfileName] = CopyTable(defaultSettings)
        currentProfile = newProfileName
        Target_Settings = profiles[newProfileName]
        UIDropDownMenu_SetText(profileDropdown, newProfileName)
        Target_Profiles = profiles
        Target_CurrentProfile = currentProfile
        initializePlayers()
        debouncedUpdateNamePlates()
    end)
    newProfileButton:Show()

    -- Register the options frame with the Blizzard Interface Options
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, addonName)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(optionsFrame)
    end
end

-- Ensure the initializeUI function is called when the addon is loaded
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end
        if not Target_Profiles then
            Target_Profiles = { ["Default"] = CopyTable(defaultSettings) }
        end
        if not Target_CurrentProfile then
            Target_CurrentProfile = "Default"
        end

        -- Load the current profile
        profiles = Target_Profiles
        currentProfile = Target_CurrentProfile
        Target_Settings = profiles[currentProfile]

        initializeUI()
    end

    if event == "PLAYER_LOGIN" then
        initializeUI()
        debouncedUpdateNamePlates()
    end

    -- Handle other events
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        initializePlayers()
        clearNamePlates()
        debouncedUpdateNamePlates()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_TARGET" then
        clearNamePlates()
        debouncedUpdateNamePlates()
    end
end)

-- Register the frame for events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_TARGET")
