-- Overlay.lua
local addonName, addon = ...

local overlayFrame
addon.arenaButtons = {}

-- Function to save overlay settings
local function SaveOverlaySettings()
    if Target_Settings and overlayFrame then
        local point, relativeTo, relativePoint, x, y = overlayFrame:GetPoint()
        Target_Settings.overlayPosX = x
        Target_Settings.overlayPosY = y
        Target_Settings.overlayWidth = overlayFrame:GetWidth()
        Target_Settings.overlayHeight = overlayFrame:GetHeight()
    end
end

-- Function to clear the overlay frame reference
function addon.ClearOverlayFrameReference()
    overlayFrame = nil
end

-- Function to arrange arena buttons based on layout
function addon.arrangeArenaButtons()
    if not overlayFrame or not overlayFrame:IsShown() then return end

    local padding = 10
    local buttonWidth, buttonHeight = 120, 20
    local overlayLayout = Target_Settings.overlayLayout
    local numButtons = #addon.arenaButtons

    local requiredWidth, requiredHeight
    if overlayLayout == "Horizontal" then
        requiredWidth = padding + (buttonWidth + padding) * numButtons
        requiredHeight = padding + buttonHeight + padding
    elseif overlayLayout == "Vertical" then
        requiredWidth = padding + buttonWidth + padding
        requiredHeight = padding + (buttonHeight + padding) * numButtons
    elseif overlayLayout == "Grid" then
        local columns = 3
        local rows = math.ceil(numButtons / columns)
        requiredWidth = padding + (buttonWidth + padding) * columns
        requiredHeight = padding + (buttonHeight + padding) * rows
    else
        requiredWidth = padding + (buttonWidth + padding) * numButtons
        requiredHeight = padding + buttonHeight + padding
    end

    overlayFrame:SetSize(requiredWidth, requiredHeight)
    addon.titleBar:SetSize(requiredWidth, 20)

    for i, button in ipairs(addon.arenaButtons) do
        button:ClearAllPoints()
        if overlayLayout == "Horizontal" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * (i - 1), -padding)
        elseif overlayLayout == "Vertical" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding, -padding - (buttonHeight + padding) * (i - 1))
        elseif overlayLayout == "Grid" then
            local row = math.floor((i - 1) / 3)
            local col = (i - 1) % 3
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * col, -padding - (buttonHeight + padding) * row)
        end
    end
end

-- Function to create the overlay frame
function addon.createOverlayFrame()
    if overlayFrame then
        overlayFrame:Show()
        addon.arrangeArenaButtons()
        addon.ApplyOverlayAppearanceChanges()
        return
    end

    if not Target_Settings.showOverlay then
        return
    end

    if not Target_Settings then
        Target_Settings = {}
    end

    local borderStyle = Target_Settings.overlayBorderStyle or "Interface\\DialogFrame\\UI-DialogBox-Border"
    local overlayWidth = Target_Settings.overlayWidth or 650
    local overlayHeight = Target_Settings.overlayHeight or 38
    local posX = Target_Settings.overlayPosX or 0
    local posY = Target_Settings.overlayPosY or 0

    overlayFrame = CreateFrame("Frame", "TargetOverlayFrame", UIParent, "BackdropTemplate")
    overlayFrame:SetSize(overlayWidth, overlayHeight)
    overlayFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)

    overlayFrame:SetBackdrop({
        bgFile = "Interface\\FriendsFrame\\UI-Toast-Background",
        edgeFile = borderStyle,
        tile = false,
        tileSize = 0,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    overlayFrame:SetBackdropColor(1, 1, 1, 1)

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

    addon.titleBar = CreateFrame("Frame", nil, overlayFrame)
    addon.titleBar:SetSize(overlayFrame:GetWidth(), 20)
    addon.titleBar:SetPoint("TOP", overlayFrame, "TOP", 0, 0)
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

    addon.arenaButtons = {}

    local buttonData = {
        { name = "2v2", xOffset = 10 },
        { name = "3v3", xOffset = 140 },
        { name = "Solo Shuffle", xOffset = 270 },
        { name = "RBG", xOffset = 400 },
        { name = "Battle Blitz", xOffset = 530 },
    }

    local buttonToBracket = {
        [1] = 1,
        [2] = 2,
        [3] = 7,
        [4] = 4,
        [5] = 9,
    }

    local ratingTexts = {}

    for index, data in ipairs(buttonData) do
        local button = CreateFrame("Button", "ArenaButton"..data.name, overlayFrame, "UIPanelButtonTemplate")
        button:SetSize(120, 20)
        button:SetText(data.name)
        button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", data.xOffset, -5)

        local buttonFontString = button:GetFontString()
        buttonFontString:SetFont("Fonts\\FRIZQT__.TTF", 10)

        local ratingText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ratingText:SetPoint("CENTER", button, "CENTER", 0, -12)
        ratingText:SetText("Loading...")
        ratingText:SetFont("Fonts\\FRIZQT__.TTF", 9)
        ratingTexts[index] = ratingText

        local bracketIndex = buttonToBracket[index]
        local pvpJoinFunction = string.format("/run C_PvP.JoinRated(%d)", bracketIndex)
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", pvpJoinFunction)

        table.insert(addon.arenaButtons, button)
    end

    local function updateRatings()
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

    overlayFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")
    overlayFrame:RegisterEvent("PVP_REWARDS_UPDATE")
    overlayFrame:RegisterEvent("HONOR_XP_UPDATE")
    overlayFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    overlayFrame:RegisterEvent("PLAYER_LOGIN")
    overlayFrame:SetScript("OnEvent", function(self, event, ...)
        updateRatings()
    end)

    overlayFrame:SetScript("OnShow", function()
        updateRatings()
        addon.ApplyOverlayAppearanceChanges()
    end)

    addon.arrangeArenaButtons()
    _G["TargetOverlayFrame"] = overlayFrame
    overlayFrame:Show()
end

-- Slash command to reset overlay position and size
SLASH_TARGETRESET1 = "/targetreset"
SlashCmdList["TARGETRESET"] = function(msg)
    if Target_Settings then
        Target_Settings.overlayPosX = 0
        Target_Settings.overlayPosY = 0
        Target_Settings.overlayWidth = 650
        Target_Settings.overlayHeight = 35

        print("ClassTarget: Overlay position and size have been reset to default.")

        if overlayFrame and overlayFrame:IsShown() then
            overlayFrame:SetSize(Target_Settings.overlayWidth, Target_Settings.overlayHeight)
            overlayFrame:SetPoint("CENTER", UIParent, "CENTER", Target_Settings.overlayPosX, Target_Settings.overlayPosY)
            addon.arrangeArenaButtons()
        end
    else
        print("ClassTarget: No settings found to reset.")
    end
end

-- Event frame for addon initialization
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

        profiles = Target_Profiles
        currentProfile = Target_CurrentProfile
        Target_Settings = profiles[currentProfile]

        if Target_Settings.showOverlay then
            addon.createOverlayFrame()
        end
    elseif event == "PLAYER_LOGIN" then
        if Target_Settings and Target_Settings.showOverlay then
            addon.createOverlayFrame()
        end
    end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        overlayEventFrame:UnregisterEvent(event)
    end
end)
