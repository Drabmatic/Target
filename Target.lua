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

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_TARGET")

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
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_TARGET" then
        -- Clear nameplates only if the target actually changes
        clearNamePlates()
        updateNamePlates()  -- Update after target change
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

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_TARGET")

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
    local optionsFrame = CreateFrame("Frame", "TargetOptionsFrame", UIParent)
    optionsFrame.name = addonName

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
        updateNamePlates()
    end)
    xSlider:Show()

    -- Register the options frame
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, addonName)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(optionsFrame)
    end
end
