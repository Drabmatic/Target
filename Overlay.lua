-- Overlay.lua
local addonName, addon = ...

local overlayFrame

-- Function to save overlay position
local function SaveOverlayPosition()
    if Target_Settings then
        Target_Settings.overlayPosition = Target_Settings.overlayPosition or { x = 0, y = 0 }
        local x, y = overlayFrame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then
            Target_Settings.overlayPosition.x = x - ux
            Target_Settings.overlayPosition.y = y - uy
        else
            -- If GetCenter fails, retain previous or default position
            Target_Settings.overlayPosition.x = Target_Settings.overlayPosition.x or 0
            Target_Settings.overlayPosition.y = Target_Settings.overlayPosition.y or 0
        end
    end
end

-- Function to create the overlay frame
local function createOverlayFrame()
    if overlayFrame then
        overlayFrame:Show()
        return
    end

    if not Target_Settings.showOverlay then
        return
    end

    -- Ensure Target_Settings is initialized
    if not Target_Settings then
        Target_Settings = {}
    end

    -- Ensure overlayPosition is initialized
    if not Target_Settings.overlayPosition then
        Target_Settings.overlayPosition = { x = 0, y = 0 }
    end

    -- Create the overlay frame
    overlayFrame = CreateFrame("Frame", "TargetOverlayFrame", UIParent, "BackdropTemplate")
    overlayFrame:SetSize(650, 35)  -- Adjusted height
    overlayFrame:SetPoint("CENTER", UIParent, "CENTER", Target_Settings.overlayPosition.x, Target_Settings.overlayPosition.y)
    overlayFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = nil,
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    overlayFrame:SetBackdropColor(0, 0, 0, 0.7)  -- Slightly darker background for readability
    overlayFrame:EnableMouse(true)
    overlayFrame:SetMovable(true)
    overlayFrame:RegisterForDrag("LeftButton")
    overlayFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    overlayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveOverlayPosition()
    end)

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
        local button = CreateFrame("Button", nil, overlayFrame, "UIPanelButtonTemplate, SecureActionButtonTemplate")
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
    end

    -- Function to update ratings
    local function updateRatings()
        -- Loop through each button and fetch the corresponding rating
        for i = 1, #buttonData do
            local bracketIndex = buttonToBracket[i]
            local rating = GetPersonalRatedInfo(bracketIndex)
            if not rating then
                rating = "N/A"
            end

            -- Update the rating text on the button
            ratingTexts[i]:SetText(rating)
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

    overlayFrame:Show()
end

-- Expose the createOverlayFrame function
addon.createOverlayFrame = createOverlayFrame

-- Event Listener for Initialization
local overlayEventFrame = CreateFrame("Frame")
overlayEventFrame:RegisterEvent("ADDON_LOADED")
overlayEventFrame:RegisterEvent("PLAYER_LOGIN")

overlayEventFrame:SetScript("OnEvent", function(self, event, ...)
    if Target_Settings and Target_Settings.showOverlay then
        createOverlayFrame()
    end
    overlayEventFrame:UnregisterEvent("ADDON_LOADED")
    overlayEventFrame:UnregisterEvent("PLAYER_LOGIN")
end)
