-- Overlay.lua
local addonName, addon = ...

local overlayFrame

-- Initialize arenaButtons table
addon.arenaButtons = {}

-- Function to save overlay position and size
local function SaveOverlaySettings()
    if Target_Settings and overlayFrame then
        -- Save position
        local point, relativeTo, relativePoint, x, y = overlayFrame:GetPoint()
        Target_Settings.overlayPosX = x
        Target_Settings.overlayPosY = y

        -- Save size
        Target_Settings.overlayWidth = overlayFrame:GetWidth()
        Target_Settings.overlayHeight = overlayFrame:GetHeight()
    end
end

-- Function to arrange arena buttons based on layout
function addon.arrangeArenaButtons()
    if not overlayFrame or not overlayFrame:IsShown() then return end

    local padding = 10
    local buttonWidth, buttonHeight = 120, 20
    local layout = Target_Settings.layout
    local numButtons = #addon.arenaButtons

    -- Determine required size based on layout
    local requiredWidth, requiredHeight

    if layout == "Horizontal" then
        requiredWidth = padding + (buttonWidth + padding) * numButtons
        requiredHeight = padding + buttonHeight + padding
    elseif layout == "Vertical" then
        requiredWidth = padding + buttonWidth + padding
        requiredHeight = padding + (buttonHeight + padding) * numButtons
    elseif layout == "Grid" then
        local columns = 3  -- Adjust this number based on preference
        local rows = math.ceil(numButtons / columns)
        requiredWidth = padding + (buttonWidth + padding) * columns
        requiredHeight = padding + (buttonHeight + padding) * rows
    else
        -- Default to Horizontal if layout is unknown
        requiredWidth = padding + (buttonWidth + padding) * numButtons
        requiredHeight = padding + buttonHeight + padding
    end

    -- Set the size of the overlay frame
    overlayFrame:SetSize(requiredWidth, requiredHeight)

    -- Adjust the titleBar size accordingly
    addon.titleBar:SetSize(requiredWidth, 20)  -- Keep the height consistent

    -- Re-arrange the buttons
    for i, button in ipairs(addon.arenaButtons) do
        button:ClearAllPoints()
        if layout == "Horizontal" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * (i - 1), -padding)
        elseif layout == "Vertical" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding, -padding - (buttonHeight + padding) * (i - 1))
        elseif layout == "Grid" then
            local columns = 3  -- Ensure this matches the columns used above
            local row = math.floor((i - 1) / columns)
            local col = (i - 1) % columns
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * col, -padding - (buttonHeight + padding) * row)
        end
    end
end

-- Function to create the overlay frame
local function createOverlayFrame()
    if overlayFrame then
        overlayFrame:Show()
        addon.arrangeArenaButtons()
        return
    end

    if not Target_Settings.showOverlay then
        return
    end

    -- Ensure Target_Settings is initialized
    if not Target_Settings then
        Target_Settings = {}
    end

    -- Create the overlay frame with BackdropTemplate
    overlayFrame = CreateFrame("Frame", "TargetOverlayFrame", UIParent, "BackdropTemplate")
    overlayFrame:SetSize(650, 35)  -- Initial size; will be adjusted based on layout
    overlayFrame:SetPoint("CENTER", UIParent, "CENTER", Target_Settings.overlayPosX or 0, Target_Settings.overlayPosY or 0)
    overlayFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    overlayFrame:SetBackdropColor(0, 0, 0, 0.7)  -- Uniform semi-transparent black
    overlayFrame:EnableMouse(true)
    overlayFrame:SetMovable(true)
    overlayFrame:RegisterForDrag("LeftButton")
    overlayFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    overlayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveOverlaySettings()
    end)

    -- Title Bar for dragging (without title text)
    addon.titleBar = CreateFrame("Frame", nil, overlayFrame)
    addon.titleBar:SetSize(overlayFrame:GetWidth(), 20)
    addon.titleBar:SetPoint("TOP", overlayFrame, "TOP", 0, 0)
    -- Removed SetBackdrop and SetBackdropColor for titleBar

    addon.titleBar:SetMovable(true)
    addon.titleBar:EnableMouse(true)
    addon.titleBar:RegisterForDrag("LeftButton")
    addon.titleBar:SetScript("OnDragStart", function(self)
        overlayFrame:StartMoving()
    end)
    addon.titleBar:SetScript("OnDragStop", function(self)
        overlayFrame:StopMovingOrSizing()
        SaveOverlaySettings()
    end)

    --[[
    -- Title Text (Removed)
    local title = addon.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", addon.titleBar, "LEFT", 5, 0)
    title:SetText("Arena Rating")
    --]]

    -- Ratings and Buttons
    local buttonData = {
        { name = "2v2", xOffset = 10 },
        { name = "3v3", xOffset = 140 },
        { name = "Solo Shuffle", xOffset = 270 },
        { name = "RBG", xOffset = 400 },
        { name = "Battle Blitz", xOffset = 530 },
    }

    -- Mapping of button index to bracket index
    local buttonToBracket = {
        [1] = 1,  -- 2v2
        [2] = 2,  -- 3v3
        [3] = 7,  -- Solo Shuffle
        [4] = 4,  -- 10v10 RBG
        [5] = 9,  -- Battle Blitz
    }

    -- Store rating text objects to update them later
    local ratingTexts = {}  -- Initialize the ratingTexts table

    for index, data in ipairs(buttonData) do
        -- Create a button for each rating bracket
        local button = CreateFrame("Button", "ArenaButton"..data.name, overlayFrame, "UIPanelButtonTemplate")
        button:SetSize(120, 20)  -- Adjusted size
        button:SetText(data.name)
        button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", data.xOffset, -5)

        -- Adjust font size for button text
        local buttonFontString = button:GetFontString()
        buttonFontString:SetFont("Fonts\\FRIZQT__.TTF", 10)

        -- Create rating text on the button (for dynamic updates)
        local ratingText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ratingText:SetPoint("CENTER", button, "CENTER", 0, -12)  -- Positioned below the button text
        ratingText:SetText("Loading...")
        ratingText:SetFont("Fonts\\FRIZQT__.TTF", 9)  -- Adjusted font size for better display

        -- Store the ratingText in the table
        ratingTexts[index] = ratingText

        -- Set up secure button attributes with JoinRated
        local bracketIndex = buttonToBracket[index]
        local pvpJoinFunction = string.format("/run C_PvP.JoinRated(%d)", bracketIndex)

        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", pvpJoinFunction)

        -- Store the button in addon.arenaButtons
        table.insert(addon.arenaButtons, button)
    end

    -- Debugging: Verify if SetBackdrop exists
    if overlayFrame.SetBackdrop then
        print("SetBackdrop method exists.")
    else
        print("SetBackdrop method does NOT exist.")
    end

    -- Debugging: Verify arenaButtons table
    if addon.arenaButtons then
        print("arenaButtons table initialized with " .. #addon.arenaButtons .. " buttons.")
    else
        print("arenaButtons table NOT initialized.")
    end

    -- Function to update ratings
    local function updateRatings()
        -- Loop through each button and fetch the corresponding rating
        for i = 1, #buttonData do
            local bracketIndex = buttonToBracket[i]
            local rating = GetPersonalRatedInfo(bracketIndex)
            if rating and type(rating) == "number" then
                ratingTexts[i]:SetText(tostring(rating))
            else
                ratingTexts[i]:SetText("N/A")
            end
        end
    end

    -- Register events to update ratings when needed
    overlayFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")
    overlayFrame:RegisterEvent("PVP_REWARDS_UPDATE")
    overlayFrame:RegisterEvent("HONOR_XP_UPDATE")
    overlayFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    overlayFrame:RegisterEvent("PLAYER_LOGIN")
    overlayFrame:SetScript("OnEvent", function(self, event, ...)
        updateRatings()
    end)

    -- Initial ratings update when the frame is shown
    overlayFrame:SetScript("OnShow", updateRatings)

    -- Initially arrange buttons based on selected layout
    addon.arrangeArenaButtons()

    -- Save the overlay frame reference globally (optional)
    _G["TargetOverlayFrame"] = overlayFrame

    overlayFrame:Show()

    -- Define a slash command to reset the overlay position and size
    SLASH_TARGETRESET1 = "/targetreset"
    SlashCmdList["TARGETRESET"] = function(msg)
        if Target_Settings then
            -- Reset position
            Target_Settings.overlayPosX = 0
            Target_Settings.overlayPosY = 0

            -- Reset size
            Target_Settings.overlayWidth = 650
            Target_Settings.overlayHeight = 35

            print("ClassTarget: Overlay position and size have been reset to default.")

            -- Apply the reset if the overlay is shown
            if overlayFrame and overlayFrame:IsShown() then
                overlayFrame:SetSize(Target_Settings.overlayWidth, Target_Settings.overlayHeight)
                overlayFrame:SetPoint("CENTER", UIParent, "CENTER", Target_Settings.overlayPosX, Target_Settings.overlayPosY)
                addon.arrangeArenaButtons()
            end
        else
            print("ClassTarget: No settings found to reset.")
        end
    end
end

-- Expose the createOverlayFrame function
addon.createOverlayFrame = createOverlayFrame

-- Event Listener for Initialization
local overlayEventFrame = CreateFrame("Frame")
overlayEventFrame:RegisterEvent("ADDON_LOADED")
overlayEventFrame:RegisterEvent("PLAYER_LOGIN")

overlayEventFrame:SetScript("OnEvent", function(self, event, ...)
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

        -- Create the overlay frame if enabled
        if Target_Settings.showOverlay then
            createOverlayFrame()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Ensure the overlay is created after player login
        if Target_Settings and Target_Settings.showOverlay then
            createOverlayFrame()
        end
    end
    -- Unregister events after handling
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        overlayEventFrame:UnregisterEvent(event)
    end
end)
