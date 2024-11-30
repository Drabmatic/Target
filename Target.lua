-- Target.lua
-- Adding Profile Management, Enhancing UI Organization, and Adding More Features

local addonName, addon = ...

-- Default values for settings
local defaultSettings = {
    xValue = 0,
    yValue = 0,
    iconType = "Default",
    iconSize = 32,
    iconOpacity = 1.0,
    enableInOpenWorld = true,
    enableInArena = true,
    enableInBattleground = true,
    enableInRaid = true,
    enableInDungeon = true,  -- For dungeons
    enableInDelves = true,   -- For new delves
    showOverlay = true,      -- Added this line
}

local profiles = {
    Default = CopyTable(defaultSettings)
}
local currentProfile = "Default"

local iconTypes = {
    ["Default"] = { suffix = "", useClassColor = false },
    ["Circle"] = { suffix = "-circle", useClassColor = false },
    ["Class Color"] = { suffix = "-color", useClassColor = true }
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterUnitEvent("UNIT_TARGET", "player", "party1", "party2", "party3", "party4")

local players = {}
local nameplateFrames = {}
local updateTicker -- This will periodically update icons

-- Function to save settings persistently
local function SaveProfileSettings()
    Target_Profiles[currentProfile] = CopyTable(Target_Settings)
    Target_CurrentProfile = currentProfile
end

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

-- Function to delete a profile
local function deleteProfile(profileName)
    if profileName and profiles[profileName] and profileName ~= "Default" then
        profiles[profileName] = nil
        if currentProfile == profileName then
            currentProfile = "Default"
            Target_Settings = profiles[currentProfile]
        end
        SaveProfileSettings()
    end
end

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

    local iconType = iconTypes[Target_Settings.iconType] or iconTypes["Default"]
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
        raid = Target_Settings.enableInRaid,
        party = Target_Settings.enableInDungeon,  -- For dungeons
        delves = Target_Settings.enableInDelves   -- New Delve feature
    }
    return zoneChecks[zoneType] or false
end

-- Update Nameplates (run continuously on a timer)
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
        if UnitExists(unitId) and UnitExists(player.targetId) then
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

                if not currentCounts[targetGUID] then
                    currentCounts[targetGUID] = 0
                end
                currentCounts[targetGUID] = currentCounts[targetGUID] + 1

                player.texture:SetParent(nameplateFrame)
                player.texture:SetPoint("LEFT", nameplateFrame, "LEFT", (currentCounts[targetGUID] - 1) * width, 0)
                player.texture:Show()
            end
        end
    end
end

local function clearNamePlates()
    -- Only clear hidden nameplates, leave the visible ones intact
    for _, frame in pairs(nameplateFrames) do
        frame:Hide()
    end
end

-- Function to refresh icons more frequently using a ticker
local function startTicker()
    if updateTicker then
        updateTicker:Cancel()  -- Cancel any existing ticker to avoid multiple ticks
    end
    updateTicker = C_Timer.NewTicker(0.1, updateNamePlates)  -- Adjust this value for more frequent updates
end

local function stopTicker()
    if updateTicker then
        updateTicker:Cancel()
    end
end

local function OnEvent(self, event, ...)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        initializePlayers()
        clearNamePlates()
        updateNamePlates()  -- Initial nameplate update
        startTicker()  -- Start continuous updates
    elseif event == "PLAYER_TARGET_CHANGED" then
        clearNamePlates()
        updateNamePlates()
    elseif event == "UNIT_TARGET" then
        local unit = ...
        if unit and players[unit] then
            -- Only update if the unit is a player or party member we're tracking
            clearNamePlates()
            updateNamePlates()
        end
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
        updateNamePlates()
        startTicker()  -- Start the periodic updates
    end
end

frame:SetScript("OnEvent", OnEvent)

-- UI Panel for Enhanced Settings
function initializeUI()
    -- Check if the settings frame is already created to prevent duplicate registrations
    if TargetOptionsFrame and TargetOptionsFrame:IsObjectType("Frame") then
        return -- Already created and registered
    end

    -- Create the settings frame
    local optionsFrame = CreateFrame("Frame", "TargetOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame.name = "ClassTarget"  -- Changed from addonName to "ClassTarget"
    optionsFrame:SetSize(600, 500) -- Adjusted size
    optionsFrame:SetPoint("CENTER")
    optionsFrame:Hide() -- Start hidden, show only when options are opened

    -- Title
    local title = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", optionsFrame, "TOP", 0, -16)
    title:SetText("ClassTarget Addon Settings")  -- Updated title text

    -- Create a container frame
    local container = CreateFrame("Frame", nil, optionsFrame)
    container:SetSize(optionsFrame:GetWidth() - 40, optionsFrame:GetHeight() - 80)
    container:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -50)

    -- Create left and right columns
    local leftColumn = CreateFrame("Frame", nil, container)
    leftColumn:SetSize((container:GetWidth() - 20) / 2, container:GetHeight())
    leftColumn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    local rightColumn = CreateFrame("Frame", nil, container)
    rightColumn:SetSize((container:GetWidth() - 20) / 2, container:GetHeight())
    rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", 20, 0)

    -- Left Column Controls
    local lastControlLeft = nil

    -- Profiles Section
    local profileTitle = leftColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    profileTitle:SetPoint("TOPLEFT", 0, 0)
    profileTitle:SetText("Profiles")
    lastControlLeft = profileTitle

    -- Dropdown to select profile
    local profileDropdown = CreateFrame("Frame", "TargetProfileDropdown", leftColumn, "UIDropDownMenuTemplate")
    profileDropdown:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", -15, -5)
    UIDropDownMenu_SetWidth(profileDropdown, 150)

    local function OnClick(self)
        UIDropDownMenu_SetSelectedID(profileDropdown, self:GetID())
        currentProfile = self.value
        Target_Settings = CopyTable(profiles[currentProfile])
        updateNamePlates()
        SaveProfileSettings()
    end

    local function Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local index = 1
        for k, v in pairs(profiles) do
            info = UIDropDownMenu_CreateInfo()
            info.text = k
            info.value = k
            info.func = OnClick
            info.checked = (currentProfile == k)
            UIDropDownMenu_AddButton(info, level)
            if info.checked then
                UIDropDownMenu_SetSelectedID(profileDropdown, index)
            end
            index = index + 1
        end
    end

    UIDropDownMenu_Initialize(profileDropdown, Initialize)
    lastControlLeft = profileDropdown

    -- Create New Profile Button
    local createProfileButton = CreateFrame("Button", "CreateProfileButton", leftColumn, "UIPanelButtonTemplate")
    createProfileButton:SetSize(120, 25)
    createProfileButton:SetText("Create Profile")
    createProfileButton:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, -10)
    createProfileButton:SetScript("OnClick", function()
        local newProfileName = generateUniqueProfileName("New Profile")
        profiles[newProfileName] = CopyTable(Target_Settings)
        currentProfile = newProfileName
        Target_Settings = profiles[currentProfile]
        UIDropDownMenu_Initialize(profileDropdown, Initialize)
        updateNamePlates()
        SaveProfileSettings()
    end)
    lastControlLeft = createProfileButton

    -- Delete Profile Button
    local deleteProfileButton = CreateFrame("Button", "DeleteProfileButton", leftColumn, "UIPanelButtonTemplate")
    deleteProfileButton:SetSize(120, 25)
    deleteProfileButton:SetText("Delete Profile")
    deleteProfileButton:SetPoint("LEFT", createProfileButton, "RIGHT", 10, 0)
    deleteProfileButton:SetScript("OnClick", function()
        deleteProfile(currentProfile)
        UIDropDownMenu_Initialize(profileDropdown, Initialize)
        updateNamePlates()
    end)
    -- No need to update lastControlLeft since it's on the same row

    -- General Settings Title
    local generalSettingsTitle = leftColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    generalSettingsTitle:SetPoint("TOPLEFT", createProfileButton, "BOTTOMLEFT", 0, -20)
    generalSettingsTitle:SetText("General Settings")
    lastControlLeft = generalSettingsTitle

    -- Icon Type Dropdown
    local iconTypeLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iconTypeLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, -10)
    iconTypeLabel:SetText("Icon Type")

    local iconTypeDropdown = CreateFrame("Frame", "TargetIconTypeDropdown", leftColumn, "UIDropDownMenuTemplate")
    iconTypeDropdown:SetPoint("TOPLEFT", iconTypeLabel, "BOTTOMLEFT", -15, -10)
    UIDropDownMenu_SetWidth(iconTypeDropdown, 150)

    local function OnIconTypeClick(self)
        UIDropDownMenu_SetSelectedID(iconTypeDropdown, self:GetID())
        Target_Settings.iconType = self.value
        -- Update player textures to use the new icon type
        for _, player in pairs(players) do
            if player.texture then
                local iconType = iconTypes[Target_Settings.iconType] or iconTypes["Default"]
                local classImage = player.class .. iconType.suffix .. ".tga"
                player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
            end
        end
        updateNamePlates()
        SaveProfileSettings()
    end

    local function InitializeIconTypeDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local index = 1
        for k, v in pairs(iconTypes) do
            info = UIDropDownMenu_CreateInfo()
            info.text = k
            info.value = k
            info.func = OnIconTypeClick
            info.checked = (Target_Settings.iconType == k)
            UIDropDownMenu_AddButton(info, level)
            if info.checked then
                UIDropDownMenu_SetSelectedID(iconTypeDropdown, index)
            end
            index = index + 1
        end
    end

    UIDropDownMenu_Initialize(iconTypeDropdown, InitializeIconTypeDropdown)
    lastControlLeft = iconTypeDropdown

    -- X Offset Slider
    local xSliderLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xSliderLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, -20)
    xSliderLabel:SetText("X Offset")

    local xSlider = CreateFrame("Slider", "TargetXSlider", leftColumn, "OptionsSliderTemplate")
    xSlider:SetPoint("TOPLEFT", xSliderLabel, "BOTTOMLEFT", 0, -10)
    xSlider:SetMinMaxValues(-200, 200)
    xSlider:SetValue(Target_Settings.xValue)
    xSlider:SetValueStep(1)
    xSlider:SetObeyStepOnDrag(true)
    xSlider:SetWidth(200)

    local xSliderValue = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    xSliderValue:SetPoint("LEFT", xSlider, "RIGHT", 10, 0)
    xSliderValue:SetText(floor(Target_Settings.xValue))

    xSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        xSliderValue:SetText(value)
        Target_Settings.xValue = value
        updateNamePlates()
        SaveProfileSettings()
    end)
    xSlider:Show()
    lastControlLeft = xSlider

    -- Y Offset Slider
    local ySliderLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ySliderLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, -20)
    ySliderLabel:SetText("Y Offset")

    local ySlider = CreateFrame("Slider", "TargetYSlider", leftColumn, "OptionsSliderTemplate")
    ySlider:SetPoint("TOPLEFT", ySliderLabel, "BOTTOMLEFT", 0, -10)
    ySlider:SetMinMaxValues(-200, 200)
    ySlider:SetValue(Target_Settings.yValue)
    ySlider:SetValueStep(1)
    ySlider:SetObeyStepOnDrag(true)
    ySlider:SetWidth(200)

    local ySliderValue = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ySliderValue:SetPoint("LEFT", ySlider, "RIGHT", 10, 0)
    ySliderValue:SetText(floor(Target_Settings.yValue))

    ySlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        ySliderValue:SetText(value)
        Target_Settings.yValue = value
        updateNamePlates()
        SaveProfileSettings()
    end)
    ySlider:Show()
    lastControlLeft = ySlider

    -- Icon Size Slider
    local sizeSliderLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeSliderLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, -20)
    sizeSliderLabel:SetText("Icon Size")

    local sizeSlider = CreateFrame("Slider", "TargetSizeSlider", leftColumn, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeSliderLabel, "BOTTOMLEFT", 0, -10)
    sizeSlider:SetMinMaxValues(10, 100)
    sizeSlider:SetValue(Target_Settings.iconSize)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetWidth(200)

    local sizeSliderValue = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeSliderValue:SetPoint("LEFT", sizeSlider, "RIGHT", 10, 0)
    sizeSliderValue:SetText(floor(Target_Settings.iconSize))

    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        sizeSliderValue:SetText(value)
        Target_Settings.iconSize = value
        -- Update the size of all player textures
        for _, player in pairs(players) do
            if player.texture then
                player.texture:SetSize(value, value)
            end
        end
        updateNamePlates()
        SaveProfileSettings()
    end)
    sizeSlider:Show()
    lastControlLeft = sizeSlider

    -- Icon Opacity Slider
    local opacitySliderLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    opacitySliderLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, -20)
    opacitySliderLabel:SetText("Icon Opacity")

    local opacitySlider = CreateFrame("Slider", "TargetOpacitySlider", leftColumn, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", opacitySliderLabel, "BOTTOMLEFT", 0, -10)
    opacitySlider:SetMinMaxValues(0.1, 1.0)
    opacitySlider:SetValue(Target_Settings.iconOpacity)
    opacitySlider:SetValueStep(0.1)
    opacitySlider:SetObeyStepOnDrag(true)
    opacitySlider:SetWidth(200)

    local opacitySliderValue = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    opacitySliderValue:SetPoint("LEFT", opacitySlider, "RIGHT", 10, 0)
    opacitySliderValue:SetText(string.format("%.1f", Target_Settings.iconOpacity))

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        value = tonumber(string.format("%.1f", value))
        opacitySliderValue:SetText(value)
        Target_Settings.iconOpacity = value
        -- Update the opacity of all player textures
        for _, player in pairs(players) do
            if player.texture then
                player.texture:SetAlpha(value)
            end
        end
        updateNamePlates()
        SaveProfileSettings()
    end)
    opacitySlider:Show()
    lastControlLeft = opacitySlider

    -- Show Overlay Checkbox
    local overlayCheckbox = CreateFrame("CheckButton", "TargetShowOverlayCheckbox", leftColumn, "UICheckButtonTemplate")
    overlayCheckbox:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, -20)
    overlayCheckbox.text = overlayCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlayCheckbox.text:SetPoint("LEFT", overlayCheckbox, "RIGHT", 0, 1)
    overlayCheckbox.text:SetText("Show PvP Rating Overlay")
    overlayCheckbox:SetChecked(Target_Settings.showOverlay)
    overlayCheckbox:SetScript("OnClick", function(self)
        Target_Settings.showOverlay = self:GetChecked()
        if Target_Settings.showOverlay then
            if TargetOverlayFrame then
                TargetOverlayFrame:Show()
            else
                -- If the overlay hasn't been created yet, create it
                if addon.createOverlayFrame then
                    addon.createOverlayFrame()
                end
            end
        else
            if TargetOverlayFrame then
                TargetOverlayFrame:Hide()
            end
        end
        SaveProfileSettings()
    end)
    lastControlLeft = overlayCheckbox

    -- Right Column Controls
    local lastControlRight = nil

    -- Toggle options for different game modes
    local toggleOptionsTitle = rightColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    toggleOptionsTitle:SetPoint("TOPLEFT", 0, 0)
    toggleOptionsTitle:SetText("Game Mode Toggles")
    lastControlRight = toggleOptionsTitle

    local checkboxData = {
        { label = "Enable in Open World", setting = "enableInOpenWorld" },
        { label = "Enable in Arena", setting = "enableInArena" },
        { label = "Enable in Battleground", setting = "enableInBattleground" },
        { label = "Enable in Raid", setting = "enableInRaid" },
        { label = "Enable in Dungeons", setting = "enableInDungeon" },  -- For dungeons
        { label = "Enable in Delves", setting = "enableInDelves" },
    }

    for i, data in ipairs(checkboxData) do
        local checkbox = CreateFrame("CheckButton", "TargetCheckbox" .. i, rightColumn, "UICheckButtonTemplate")
        if lastControlRight then
            checkbox:SetPoint("TOPLEFT", lastControlRight, "BOTTOMLEFT", 0, -10)
        else
            checkbox:SetPoint("TOPLEFT", toggleOptionsTitle, "BOTTOMLEFT", 0, -20)
        end
        checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 0, 1)
        checkbox.text:SetText(data.label)
        checkbox:SetChecked(Target_Settings[data.setting])
        checkbox:SetScript("OnClick", function(self)
            Target_Settings[data.setting] = self:GetChecked()
            updateNamePlates()
            SaveProfileSettings()
        end)
        lastControlRight = checkbox
    end

    -- Donation and Reload UI Buttons
    local buttonContainer = CreateFrame("Frame", nil, optionsFrame)
    buttonContainer:SetSize(1, 1)
    buttonContainer:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 20)

    -- Reload UI Button
    local reloadButton = CreateFrame("Button", "TargetReloadButton", buttonContainer, "UIPanelButtonTemplate")
    reloadButton:SetSize(120, 25)
    reloadButton:SetText("Reload UI")
    reloadButton:SetPoint("LEFT", buttonContainer, "CENTER", -65, 0)
    reloadButton:SetScript("OnClick", function() ReloadUI() end)

    -- Donation Button
    local donateButton = CreateFrame("Button", "TargetDonateButton", buttonContainer, "UIPanelButtonTemplate")
    donateButton:SetSize(120, 25)
    donateButton:SetText("Donate")
    donateButton:SetPoint("LEFT", reloadButton, "RIGHT", 10, 0)
    donateButton:SetScript("OnClick", function()
        local popup = CreateFrame("Frame", "DonatePopup", UIParent, "BasicFrameTemplateWithInset")
        popup:SetSize(350, 150)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("DIALOG")

        popup.title = popup:CreateFontString(nil, "OVERLAY")
        popup.title:SetFontObject("GameFontHighlight")
        popup.title:SetPoint("TOP", popup.TitleBg, "TOP", 0, -5)
        popup.title:SetText("Support This Addon")

        local donateText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        donateText:SetPoint("TOPLEFT", popup, "TOPLEFT", 15, -35)
        donateText:SetWidth(320)
        donateText:SetJustifyH("LEFT")
        donateText:SetText("Support this addon by donating! Copy the link below:")

        local editBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
        editBox:SetSize(320, 20)
        editBox:SetPoint("TOP", donateText, "BOTTOM", 0, -10)
        editBox:SetAutoFocus(false)
        editBox:SetText("https://paypal.me/Drabio?country.x=US&locale.x=en_US")
        editBox:HighlightText()
        editBox:SetCursorPosition(0)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        editBox:SetScript("OnTextChanged", function(self)
            self:SetText("https://paypal.me/Drabio?country.x=US&locale.x=en_US")
            self:HighlightText()
        end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        editBox:SetScript("OnMouseUp", function(self)
            self:HighlightText()
        end)
        editBox:SetScript("OnEditFocusLost", function(self)
            self:HighlightText(0, 0)
        end)
        editBox:EnableMouse(true)
        editBox:SetFocus()

        local closeButton = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
    end)

    -- Register the settings panel with Interface Options
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "ClassTarget")  -- Changed from addonName to "ClassTarget"
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(optionsFrame)
    end

    -- Show/Hide function when the options frame is opened/closed
    optionsFrame:SetScript("OnShow", function(self)
        self:Show()
    end)

    optionsFrame:SetScript("OnHide", function(self)
        self:Hide()
    end)
end

-- Hook to Interface Options for showing the frame
SLASH_TARGETOPTIONS1 = "/targetoptions"
SlashCmdList["TARGETOPTIONS"] = function()
    if not TargetOptionsFrame:IsShown() then
        TargetOptionsFrame:Show()
    else
        TargetOptionsFrame:Hide()
    end
end

-- Expose the addon table to allow accessing functions from other files
_G[addonName] = addon
