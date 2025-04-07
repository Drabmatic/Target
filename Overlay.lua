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

-- Function to get the appropriate bracket based on group size
local function GetGroupSizeBracket()
    local numMembers = GetNumGroupMembers() -- Includes player
    if numMembers >= 5 then
        return "RBG", 4, "ConquestFrame.RatedBG" -- Rated Battleground (10v10)
    elseif numMembers >= 3 then
        return "3v3", 2, "ConquestFrame.Arena3v3" -- Arena 3v3
    elseif numMembers >= 2 then
        return "2v2", 1, "ConquestFrame.Arena2v2" -- Arena 2v2
    else
        return "Solo Shuffle", 7, "ConquestFrame.RatedSoloShuffle" -- Solo Shuffle
    end
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
        requiredHeight = padding + buttonHeight + padding + 12
    elseif overlayLayout == "Vertical" then
        requiredWidth = padding + buttonWidth + padding
        requiredHeight = padding + (buttonHeight + padding + 12) * numButtons
    elseif overlayLayout == "Grid" then
        local columns = 3
        local rows = math.ceil(numButtons / columns)
        requiredWidth = padding + (buttonWidth + padding) * columns
        requiredHeight = padding + (buttonHeight + padding + 12) * rows
    else
        requiredWidth = padding + (buttonWidth + padding) * numButtons
        requiredHeight = padding + buttonHeight + padding + 12
    end

    overlayFrame:SetSize(requiredWidth, requiredHeight)

    for i, button in ipairs(addon.arenaButtons) do
        button:ClearAllPoints()
        if overlayLayout == "Horizontal" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * (i - 1), -padding)
        elseif overlayLayout == "Vertical" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding, -padding - (buttonHeight + padding + 12) * (i - 1))
        elseif overlayLayout == "Grid" then
            local row = math.floor((i - 1) / 3)
            local col = (i - 1) % 3
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * col, -padding - (buttonHeight + padding + 12) * row)
        end
        button.ratingText:SetPoint("CENTER", button, "CENTER", 0, -12)
    end
end

-- Function to update button macros and highlights based on group size
local function UpdateButtonMacros()
    if InCombatLockdown() or not C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") then
        return
    end
    local groupBracketName, groupBracketIndex, groupBracketButton = GetGroupSizeBracket()
    for _, button in ipairs(addon.arenaButtons) do
        if button.bracketIndex == groupBracketIndex then
            button:SetAttribute("type", "macro")
            button:SetAttribute("macrotext", "/click LFDMicroButton\n/click PVEFrameTab2\n/click PVPQueueFrameCategoryButton2\n/click " .. groupBracketButton .. "\n/click " .. groupBracketButton .. "\n/click ConquestJoinButton")
            -- Highlight the active button using default glow
            ActionButton_ShowOverlayGlow(button)
        else
            button:SetAttribute("type", "macro")
            button:SetAttribute("macrotext", "/click LFDMicroButton\n/click PVEFrameTab2\n/click PVPQueueFrameCategoryButton2")
            ActionButton_HideOverlayGlow(button)
        end
    end
end

-- Function to configure secure buttons
local function ConfigureSecureButtons()
    if not overlayFrame or InCombatLockdown() or not C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") then
        return
    end
    for _, button in ipairs(addon.arenaButtons) do
        if not button.isConfigured then
            SecureHandlerWrapScript(button, "OnClick", button, [[
                if IsShiftKeyDown() then
                    self:SetAttribute("macrotext", "")
                    return
                end
                local macrotext = self:GetAttribute("macrotext")
                self:SetAttribute("macrotext", macrotext)
            ]])
            button.isConfigured = true
        end
    end
    UpdateButtonMacros() -- Set initial macros
end

-- Function to create the overlay frame
function addon.createOverlayFrame()
    if overlayFrame then
        overlayFrame:Show()
        addon.arrangeArenaButtons()
        addon.ApplyOverlayAppearanceChanges()
        ConfigureSecureButtons()
        return
    end

    if not Target_Settings.showOverlay then
        return
    end

    if not Target_Settings then
        Target_Settings = {}
    end

    local borderStyle = Target_Settings.overlayBorderStyle or "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
    local overlayWidth = Target_Settings.overlayWidth or 650
    local overlayHeight = Target_Settings.overlayHeight or 38
    local posX = Target_Settings.overlayPosX or 0
    local posY = Target_Settings.overlayPosY or 0

    -- Check WoW version for BackdropTemplate compatibility
    local useBackdropTemplate = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE -- Retail WoW
    overlayFrame = CreateFrame("Frame", "TargetOverlayFrame", UIParent, useBackdropTemplate and "BackdropTemplate" or nil)
    overlayFrame:SetSize(overlayWidth, overlayHeight)
    overlayFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)

    -- Set backdrop (with version compatibility)
    local backdrop = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
        edgeFile = borderStyle,
        tile = false,
        tileSize = 0,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    }
    if useBackdropTemplate then
        overlayFrame:SetBackdrop(backdrop)
        overlayFrame:SetBackdropColor(1, 1, 1, 0.9)
        overlayFrame:SetBackdropBorderColor(1, 0.8, 0, 1) -- Gold border tint
    else
        overlayFrame:SetBackdrop(backdrop)
        overlayFrame:SetBackdropColor(1, 1, 1, 0.9)
        overlayFrame:SetBackdropBorderColor(1, 0.8, 0, 1)
    end

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

    addon.arenaButtons = {}

    local buttonData = {
        { name = "2v2", bracketIndex = 1 },
        { name = "3v3", bracketIndex = 2 },
        { name = "Solo Shuffle", bracketIndex = 7 },
        { name = "RBG", bracketIndex = 4 },
        { name = "Battle Blitz", bracketIndex = 9 },
    }

    local ratingTexts = {}
    local PVPUI_ADDON_NAME = "Blizzard_PVPUI"

    for index, data in ipairs(buttonData) do
        -- Custom button creation without UIPanelButtonTemplate
        local button = CreateFrame("Button", "ArenaButton"..data.name, overlayFrame, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
        button:SetSize(120, 20)
        button:SetText(data.name) -- Set text for debugging
        button.bracketIndex = data.bracketIndex
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:EnableMouse(true) -- Ensure mouse events are enabled

        -- Button background with gradient
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\UI-Button-Background")
        bg:SetVertexColor(0.8, 0.2, 0.2, 1) -- Reddish tint

        -- Button border
        local border = button:CreateTexture(nil, "BORDER")
        border:SetAllPoints()
        border:SetTexture("Interface\\Buttons\\UI-Button-Border")
        border:SetVertexColor(1, 0.8, 0, 1) -- Gold border

        -- Highlight texture for hover
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        local highlight = button:GetHighlightTexture()
        highlight:SetAllPoints()
        highlight:SetAlpha(1.0) -- Max visibility

        -- Button text
        local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        buttonText:SetPoint("CENTER", button, "CENTER", 0, 0)
        buttonText:SetText(data.name)
        buttonText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        buttonText:SetTextColor(1, 0.9, 0.1, 1) -- Gold text
        buttonText:SetShadowOffset(1, -1)
        buttonText:SetShadowColor(0, 0, 0, 1)

        -- Rating text
        local ratingText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ratingText:SetPoint("CENTER", button, "CENTER", 0, -12)
        ratingText:SetText("Loading...")
        ratingText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        ratingText:SetTextColor(1, 1, 1, 1) -- White text
        ratingText:SetShadowOffset(1, -1)
        ratingText:SetShadowColor(0, 0, 0, 1)
        ratingTexts[index] = ratingText
        button.ratingText = ratingText

        button:SetAttribute("bracketIndex", data.bracketIndex)

        -- Animation for click effect
        local animGroup = button:CreateAnimationGroup()
        local scaleDown = animGroup:CreateAnimation("Scale")
        scaleDown:SetScale(0.95, 0.95)
        scaleDown:SetDuration(0.1)
        scaleDown:SetOrder(1)
        local scaleUp = animGroup:CreateAnimation("Scale")
        scaleUp:SetScale(1.0526, 1.0526) -- Inverse of 0.95 to return to original size
        scaleUp:SetDuration(0.1)
        scaleUp:SetOrder(2)
        button:SetScript("OnMouseDown", function(self)
            animGroup:Play()
        end)

        -- Hover effects
        button:SetScript("OnEnter", function(self)
            ActionButton_ShowOverlayGlow(self) -- Use default glow for hover
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local groupBracketName, groupBracketIndex = GetGroupSizeBracket()
            if IsShiftKeyDown() then
                GameTooltip:SetText("Drag to move overlay")
            elseif groupBracketIndex == self.bracketIndex then
                GameTooltip:SetText("Queue for " .. data.name)
            else
                GameTooltip:SetText("Open Rated PvP Tab\nGroup size suggests: " .. groupBracketName)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            ActionButton_HideOverlayGlow(self) -- Hide glow on leave
            GameTooltip:Hide()
        end)

        table.insert(addon.arenaButtons, button)
    end

    local function updateRatings()
        for i, button in ipairs(addon.arenaButtons) do
            local rating = GetPersonalRatedInfo(button.bracketIndex)
            if rating and type(rating) == "number" then
                ratingTexts[i]:SetText(tostring(rating))
            else
                ratingTexts[i]:SetText("N/A")
            end
        end
    end

    -- Load Blizzard_PVPUI addon if needed
    local function ensurePVPUILoaded()
        local _, isLoaded = C_AddOns.IsAddOnLoaded(PVPUI_ADDON_NAME)
        if not isLoaded then
            UIParentLoadAddOn(PVPUI_ADDON_NAME)
        end
    end

    overlayFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")
    overlayFrame:RegisterEvent("PVP_REWARDS_UPDATE")
    overlayFrame:RegisterEvent("HONOR_XP_UPDATE")
    overlayFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    overlayFrame:RegisterEvent("PLAYER_LOGIN")
    overlayFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    overlayFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    overlayFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    overlayFrame:RegisterEvent("ADDON_LOADED")
    overlayFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_LOADED" then
            local addonLoaded = ...
            if addonLoaded == PVPUI_ADDON_NAME or addonLoaded == addonName then
                updateRatings()
                ConfigureSecureButtons()
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
            UpdateButtonMacros()
        elseif event == "PLAYER_REGEN_DISABLED" then
            for _, button in ipairs(addon.arenaButtons) do
                button:Disable()
            end
        elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            UpdateButtonMacros() -- Ensure glow updates on login
        end
        updateRatings()
    end)

    overlayFrame:SetScript("OnShow", function()
        ensurePVPUILoaded()
        updateRatings()
        addon.ApplyOverlayAppearanceChanges()
        ConfigureSecureButtons()
        UpdateButtonMacros() -- Ensure glow updates when frame is shown
        for _, button in ipairs(addon.arenaButtons) do
            button:Enable()
        end
    end)

    overlayFrame:SetScript("OnHide", function()
        for _, button in ipairs(addon.arenaButtons) do
            button:Disable()
        end
    end)

    ensurePVPUILoaded()
    addon.arrangeArenaButtons()
    UpdateButtonMacros() -- Call immediately after creation
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
        Target_Settings.overlayHeight = 38

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