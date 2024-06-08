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
        debouncedUpdateNamePlates() -- Update in real-time
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
        debouncedUpdateNamePlates() -- Update in real-time
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
        debouncedUpdateNamePlates() -- Update in real-time
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
        debouncedUpdateNamePlates() -- Update in real-time
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
                debouncedUpdateNamePlates() -- Update in real-time
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
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    addon.iconSizeSlider:Show()

    -- Icon Size Label
    addon.iconSizeLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.iconSizeLabel:SetPoint("TOPLEFT", addon.iconSizeSlider, "BOTTOMLEFT", 0, -5)
    addon.iconSizeLabel:SetText("Icon Size")
    addon.iconSizeLabel:Show()

    -- Icon Opacity Slider
    addon.iconOpacitySlider = CreateFrame("Slider", "TargetIconOpacitySlider", addon.optionsFrame, "OptionsSliderTemplate")
    addon.iconOpacitySlider:SetPoint("TOPLEFT", addon.iconSizeSlider, "BOTTOMLEFT", 0, -20)
    addon.iconOpacitySlider:SetMinMaxValues(0.1, 1.0)
    addon.iconOpacitySlider:SetValue(tonumber(Target_Settings.iconOpacity) or 1.0)
    addon.iconOpacitySlider:SetValueStep(0.1)
    addon.iconOpacitySlider:SetObeyStepOnDrag(true)
    addon.iconOpacitySlider:SetWidth(200)
    addon.iconOpacitySlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText("Icon Opacity: " .. string.format("%.1f", value))
        Target_Settings.iconOpacity = value
        initializePlayers()
        debouncedUpdateNamePlates() -- Update in real-time
    end)
    addon.iconOpacitySlider:Show()

    -- Icon Opacity Label
    addon.iconOpacityLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.iconOpacityLabel:SetPoint("TOPLEFT", addon.iconOpacitySlider, "BOTTOMLEFT", 0, -5)
    addon.iconOpacityLabel:SetText("Icon Opacity")
    addon.iconOpacityLabel:Show()

    -- Enable in Open World Checkbox
    addon.enableInOpenWorldCheckbox = CreateFrame("CheckButton", "TargetEnableInOpenWorldCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
    addon.enableInOpenWorldCheckbox:SetPoint("TOPLEFT", addon.iconOpacityLabel, "BOTTOMLEFT", 0, -20)
    addon.enableInOpenWorldCheckbox.text:SetText("Enable in Open World")
    addon.enableInOpenWorldCheckbox:SetChecked(Target_Settings.enableInOpenWorld)
    addon.enableInOpenWorldCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInOpenWorld = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    addon.enableInOpenWorldCheckbox:Show()

    -- Enable in Arena Checkbox
    addon.enableInArenaCheckbox = CreateFrame("CheckButton", "TargetEnableInArenaCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
    addon.enableInArenaCheckbox:SetPoint("TOPLEFT", addon.enableInOpenWorldCheckbox, "BOTTOMLEFT", 0, -5)
    addon.enableInArenaCheckbox.text:SetText("Enable in Arena")
    addon.enableInArenaCheckbox:SetChecked(Target_Settings.enableInArena)
    addon.enableInArenaCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInArena = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    addon.enableInArenaCheckbox:Show()

    -- Enable in Battleground Checkbox
    addon.enableInBattlegroundCheckbox = CreateFrame("CheckButton", "TargetEnableInBattlegroundCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
    addon.enableInBattlegroundCheckbox:SetPoint("TOPLEFT", addon.enableInArenaCheckbox, "BOTTOMLEFT", 0, -5)
    addon.enableInBattlegroundCheckbox.text:SetText("Enable in Battleground")
    addon.enableInBattlegroundCheckbox:SetChecked(Target_Settings.enableInBattleground)
    addon.enableInBattlegroundCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInBattleground = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    addon.enableInBattlegroundCheckbox:Show()

    -- Enable in Raid Checkbox
    addon.enableInRaidCheckbox = CreateFrame("CheckButton", "TargetEnableInRaidCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
    addon.enableInRaidCheckbox:SetPoint("TOPLEFT", addon.enableInBattlegroundCheckbox, "BOTTOMLEFT", 0, -5)
    addon.enableInRaidCheckbox.text:SetText("Enable in Raid")
    addon.enableInRaidCheckbox:SetChecked(Target_Settings.enableInRaid)
    addon.enableInRaidCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInRaid = self:GetChecked()
        debouncedUpdateNamePlates()
    end)
    addon.enableInRaidCheckbox:Show()

    -- Profile Management
    addon.profileLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addon.profileLabel:SetPoint("TOPLEFT", addon.enableInRaidCheckbox, "BOTTOMLEFT", 0, -20)
    addon.profileLabel:SetText("Profile Management")
    addon.profileLabel:Show()

    -- Profile Dropdown Menu
    addon.profileDropdown = CreateFrame("Frame", "TargetProfileDropdown", addon.optionsFrame, "UIDropDownMenuTemplate")
    addon.profileDropdown:SetPoint("TOPLEFT", addon.profileLabel, "BOTTOMLEFT", 0, -5)
    addon.profileDropdown.initialize = function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for profileName in pairs(profiles) do
            info.text = profileName
            info.func = function()
                currentProfile = profileName
                Target_Settings = profiles[profileName]
                UIDropDownMenu_SetText(addon.profileDropdown, profileName)
                initializePlayers()
                debouncedUpdateNamePlates()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_SetWidth(addon.profileDropdown, 150)
    UIDropDownMenu_SetButtonWidth(addon.profileDropdown, 174)
    UIDropDownMenu_JustifyText(addon.profileDropdown, "CENTER")
    UIDropDownMenu_SetText(addon.profileDropdown, currentProfile)
    addon.profileDropdown:Show()

    -- Save Profile Button
    addon.saveProfileButton = CreateFrame("Button", "TargetSaveProfileButton", addon.optionsFrame, "UIPanelButtonTemplate")
    addon.saveProfileButton:SetPoint("TOPLEFT", addon.profileDropdown, "BOTTOMLEFT", 0, -10)
    addon.saveProfileButton:SetSize(120, 20)
    addon.saveProfileButton:SetText("Save Profile")
    addon.saveProfileButton:SetScript("OnClick", function()
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
    addon.saveProfileButton:Show()

    -- New Profile Button
    addon.newProfileButton = CreateFrame("Button", "TargetNewProfileButton", addon.optionsFrame, "UIPanelButtonTemplate")
    addon.newProfileButton:SetPoint("TOPLEFT", addon.saveProfileButton, "BOTTOMLEFT", 0, -10)
    addon.newProfileButton:SetSize(120, 20)
    addon.newProfileButton:SetText("New Profile")
    addon.newProfileButton:SetScript("OnClick", function()
        local newProfileName = generateUniqueProfileName("Profile")
        profiles[newProfileName] = CopyTable(defaultSettings)
        currentProfile = newProfileName
        Target_Settings = profiles[newProfileName]
        UIDropDownMenu_SetText(addon.profileDropdown, newProfileName)
        Target_Profiles = profiles
        Target_CurrentProfile = currentProfile
        initializePlayers()
        debouncedUpdateNamePlates()
    end)
    addon.newProfileButton:Show()
end
