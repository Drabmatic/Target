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
}

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
-- Register UNIT_TARGET events for player and party members
frame:RegisterUnitEvent("UNIT_TARGET", "player", "party1", "party2", "party3", "party4")

local players = {}
local nameplateFrames = {}
local updateTicker -- This will periodically update icons

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

-- UI Panel
function initializeUI()
    local optionsFrame = CreateFrame("Frame", "TargetOptionsFrame", UIParent)
    optionsFrame.name = addonName

    local title = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Target Addon Settings")

    local lastControl = title

    -- Icon Type Dropdown
    local iconTypeLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iconTypeLabel:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -20)
    iconTypeLabel:SetText("Icon Style")

    local iconTypeDropdown = CreateFrame("Frame", "TargetIconTypeDropdown", optionsFrame, "UIDropDownMenuTemplate")
    iconTypeDropdown:SetPoint("TOPLEFT", iconTypeLabel, "BOTTOMLEFT", -15, -10)
    UIDropDownMenu_SetWidth(iconTypeDropdown, 150)

    local function OnClick(self)
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
    end

    local function Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local index = 1
        for k, v in pairs(iconTypes) do
            info = UIDropDownMenu_CreateInfo()
            info.text = k
            info.value = k
            info.func = OnClick
            info.checked = (Target_Settings.iconType == k)
            UIDropDownMenu_AddButton(info, level)
            if info.checked then
                UIDropDownMenu_SetSelectedID(iconTypeDropdown, index)
            end
            index = index + 1
        end
    end

    UIDropDownMenu_Initialize(iconTypeDropdown, Initialize)
    lastControl = iconTypeDropdown

    -- X Offset Slider
    local xSliderLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xSliderLabel:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 15, -20)
    xSliderLabel:SetText("X Offset")

    local xSlider = CreateFrame("Slider", "TargetXSlider", optionsFrame, "OptionsSliderTemplate")
    xSlider:SetPoint("TOPLEFT", xSliderLabel, "BOTTOMLEFT", 0, -10)
    xSlider:SetMinMaxValues(-200, 200)
    xSlider:SetValue(Target_Settings.xValue)
    xSlider:SetValueStep(1)
    xSlider:SetObeyStepOnDrag(true)
    xSlider:SetWidth(200)

    local xSliderValue = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    xSliderValue:SetPoint("LEFT", xSlider, "RIGHT", 10, 0)
    xSliderValue:SetText(floor(Target_Settings.xValue))

    xSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        xSliderValue:SetText(value)
        Target_Settings.xValue = value
        updateNamePlates()
    end)
    xSlider:Show()
    lastControl = xSlider

    -- Y Offset Slider
    local ySliderLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ySliderLabel:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -20)
    ySliderLabel:SetText("Y Offset")

    local ySlider = CreateFrame("Slider", "TargetYSlider", optionsFrame, "OptionsSliderTemplate")
    ySlider:SetPoint("TOPLEFT", ySliderLabel, "BOTTOMLEFT", 0, -10)
    ySlider:SetMinMaxValues(-200, 200)
    ySlider:SetValue(Target_Settings.yValue)
    ySlider:SetValueStep(1)
    ySlider:SetObeyStepOnDrag(true)
    ySlider:SetWidth(200)

    local ySliderValue = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ySliderValue:SetPoint("LEFT", ySlider, "RIGHT", 10, 0)
    ySliderValue:SetText(floor(Target_Settings.yValue))

    ySlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        ySliderValue:SetText(value)
        Target_Settings.yValue = value
        updateNamePlates()
    end)
    ySlider:Show()
    lastControl = ySlider

    -- Icon Size Slider
    local sizeSliderLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeSliderLabel:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -20)
    sizeSliderLabel:SetText("Icon Size")

    local sizeSlider = CreateFrame("Slider", "TargetSizeSlider", optionsFrame, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeSliderLabel, "BOTTOMLEFT", 0, -10)
    sizeSlider:SetMinMaxValues(10, 100)
    sizeSlider:SetValue(Target_Settings.iconSize)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetWidth(200)

    local sizeSliderValue = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
    end)
    sizeSlider:Show()
    lastControl = sizeSlider

    -- Icon Opacity Slider
    local opacitySliderLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    opacitySliderLabel:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -20)
    opacitySliderLabel:SetText("Icon Opacity")

    local opacitySlider = CreateFrame("Slider", "TargetOpacitySlider", optionsFrame, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", opacitySliderLabel, "BOTTOMLEFT", 0, -10)
    opacitySlider:SetMinMaxValues(0.1, 1.0)
    opacitySlider:SetValue(Target_Settings.iconOpacity)
    opacitySlider:SetValueStep(0.1)
    opacitySlider:SetObeyStepOnDrag(true)
    opacitySlider:SetWidth(200)

    local opacitySliderValue = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
    end)
    opacitySlider:Show()
    lastControl = opacitySlider

    -- Toggle options for different game modes
    local checkboxData = {
        { label = "Enable in Open World", setting = "enableInOpenWorld" },
        { label = "Enable in Arena", setting = "enableInArena" },
        { label = "Enable in Battleground", setting = "enableInBattleground" },
        { label = "Enable in Raid", setting = "enableInRaid" },
        { label = "Enable in Dungeons", setting = "enableInDungeon" },  -- For dungeons
        { label = "Enable in Delves", setting = "enableInDelves" },
    }

    for i, data in ipairs(checkboxData) do
        local checkbox = CreateFrame("CheckButton", "TargetCheckbox" .. i, optionsFrame, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -20)
        checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 0, 1)
        checkbox.text:SetText(data.label)
        checkbox:SetChecked(Target_Settings[data.setting])
        checkbox:SetScript("OnClick", function(self)
            Target_Settings[data.setting] = self:GetChecked()
            updateNamePlates()
        end)
        lastControl = checkbox
    end

    -- Donation and Reload UI Buttons
    local buttonContainer = CreateFrame("Frame", nil, optionsFrame)
    buttonContainer:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -30)
    buttonContainer:SetSize(1, 1)

    -- Reload UI Button
    local reloadButton = CreateFrame("Button", "TargetReloadButton", buttonContainer, "UIPanelButtonTemplate")
    reloadButton:SetSize(120, 25)
    reloadButton:SetText("Reload UI")
    reloadButton:SetScript("OnClick", function() ReloadUI() end)
    reloadButton:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)

    -- Donation Button
    local donateButton = CreateFrame("Button", "TargetDonateButton", buttonContainer, "UIPanelButtonTemplate")
    donateButton:SetSize(120, 25)
    donateButton:SetText("Donate")
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
    donateButton:SetPoint("LEFT", reloadButton, "RIGHT", 10, 0)

    -- Register the options frame
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, addonName)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(optionsFrame)
    end
end
