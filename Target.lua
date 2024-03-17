local addonName, addon = ...

-- Default values for settings
local defaultSettings = {
    xValue = 0,
    yValue = 0,
    iconType = "default",
    iconSize = "default",
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
    local iconSize = Target_Settings.iconSize or 32
    player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
    player.texture:SetSize(iconSize, iconSize)

    return player
end

local function clearPlayers()
    wipe(players)
end

local function initializePlayers()
    clearPlayers()

    players["player"] = createPlayer("player")
    players["party1"] = createPlayer("party1")
    players["party2"] = createPlayer("party2")
    players["party3"] = createPlayer("party3")
    players["party4"] = createPlayer("party4")
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
    if zoneType == "none" and not Target_Settings.enableInOpenWorld then
        return false
    elseif zoneType == "arena" and not Target_Settings.enableInArena then
        return false
    elseif zoneType == "pvp" and not Target_Settings.enableInBattleground then
        return false
    elseif zoneType == "raid" and not Target_Settings.enableInRaid then
        return false
    end
    return true
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
    local xOffset = Target_Settings.xValue
    local yOffset = Target_Settings.yValue

    for unitId, player in pairs(players) do
        local targetIdExists = UnitExists(player.targetId)
        if UnitExists(unitId) and targetIdExists and not UnitIsUnit("target", "player") then
            local nameplate = C_NamePlate.GetNamePlateForUnit(player.targetId)
            if nameplate and player.texture then
                local targetGUID = UnitGUID(player.targetId)
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
end

local function clearNamePlates()
    for _, frame in pairs(nameplateFrames) do
        frame:Hide()
    end
    wipe(nameplateFrames)
end

local function OnEvent(self, event, ...)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        initializePlayers()
        clearNamePlates()
        updateNamePlates()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_TARGET" then
        clearNamePlates()
        updateNamePlates()
    elseif event == "ADDON_LOADED" and ... == addonName then
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end
        initializeUI()
    elseif event == "PLAYER_LOGIN" then
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end
        initializeUI()
        updateNamePlates()
    end
end

frame:SetScript("OnEvent", OnEvent)

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

    -- Enable in Open World Checkbox
    addon.enableInOpenWorldCheckbox = CreateFrame("CheckButton", "TargetEnableInOpenWorldCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
    addon.enableInOpenWorldCheckbox:SetPoint("TOPLEFT", addon.iconSizeLabel, "BOTTOMLEFT", 0, -20)
    addon.enableInOpenWorldCheckbox.text:SetText("Enable in Open World")
    addon.enableInOpenWorldCheckbox:SetChecked(Target_Settings.enableInOpenWorld)
    addon.enableInOpenWorldCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInOpenWorld = self:GetChecked()
        updateNamePlates()
    end)
    addon.enableInOpenWorldCheckbox:Show()

    -- Enable in Arena Checkbox
    addon.enableInArenaCheckbox = CreateFrame("CheckButton", "TargetEnableInArenaCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
    addon.enableInArenaCheckbox:SetPoint("TOPLEFT", addon.enableInOpenWorldCheckbox, "BOTTOMLEFT", 0, -5)
    addon.enableInArenaCheckbox.text:SetText("Enable in Arena")
    addon.enableInArenaCheckbox:SetChecked(Target_Settings.enableInArena)
    addon.enableInArenaCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableInArena = self:GetChecked()
        updateNamePlates()
    end)
    addon.enableInArenaCheckbox:Show()

-- Enable in Battleground Checkbox
addon.enableInBattlegroundCheckbox = CreateFrame("CheckButton", "TargetEnableInBattlegroundCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
addon.enableInBattlegroundCheckbox:SetPoint("TOPLEFT", addon.enableInArenaCheckbox, "BOTTOMLEFT", 0, -5)
addon.enableInBattlegroundCheckbox.text:SetText("Enable in Battleground")
addon.enableInBattlegroundCheckbox:SetChecked(Target_Settings.enableInBattleground)
addon.enableInBattlegroundCheckbox:SetScript("OnClick", function(self)
    Target_Settings.enableInBattleground = self:GetChecked()
    updateNamePlates()
end)
addon.enableInBattlegroundCheckbox:Show()

-- Enable in Raid Checkbox
addon.enableInRaidCheckbox = CreateFrame("CheckButton", "TargetEnableInRaidCheckbox", addon.optionsFrame, "UICheckButtonTemplate")
addon.enableInRaidCheckbox:SetPoint("TOPLEFT", addon.enableInBattlegroundCheckbox, "BOTTOMLEFT", 0, -5)
addon.enableInRaidCheckbox.text:SetText("Enable in Raid")
addon.enableInRaidCheckbox:SetChecked(Target_Settings.enableInRaid)
addon.enableInRaidCheckbox:SetScript("OnClick", function(self)
    Target_Settings.enableInRaid = self:GetChecked()
    updateNamePlates()
end)
addon.enableInRaidCheckbox:Show()

-- Discord Link Label
addon.discordLinkLabel = addon.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
addon.discordLinkLabel:SetPoint("TOPLEFT", addon.enableInRaidCheckbox, "BOTTOMLEFT", 0, -20)
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