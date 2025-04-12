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
    local numMembers = (GetNumSubgroupMembers() or 0) + 1
    if numMembers >= 5 then
        return "RBG", 4, "ConquestFrame.RatedBG"
    elseif numMembers >= 3 then
        return "3v3", 2, "ConquestFrame.Arena3v3"
    elseif numMembers >= 2 then
        return "2v2", 1, "ConquestFrame.Arena2v2"
    else
        return "Solo Shuffle", 7, "ConquestFrame.RatedSoloShuffle"
    end
end

-- Function to arrange arena buttons based on layout
function addon.arrangeArenaButtons()
    if not overlayFrame or not overlayFrame:IsShown() then return end

    local padding = Target_Settings.compactOverlay and 5 or 10
    local buttonWidth = Target_Settings.compactOverlay and 80 or 120
    local buttonHeight = Target_Settings.compactOverlay and 16 or 20
    local overlayLayout = Target_Settings.overlayLayout
    local numButtons = #addon.arenaButtons

    local requiredWidth, requiredHeight
    if overlayLayout == "Horizontal" then
        requiredWidth = padding + (buttonWidth + padding) * numButtons
        requiredHeight = padding + buttonHeight + padding + (Target_Settings.compactOverlay and 10 or 12)
    elseif overlayLayout == "Vertical" then
        requiredWidth = padding + buttonWidth + padding
        requiredHeight = padding + (buttonHeight + padding + (Target_Settings.compactOverlay and 10 or 12)) * numButtons
    elseif overlayLayout == "Grid" then
        local columns = 3
        local rows = math.ceil(numButtons / columns)
        requiredWidth = padding + (buttonWidth + padding) * columns
        requiredHeight = padding + (buttonHeight + padding + (Target_Settings.compactOverlay and 10 or 12)) * rows
    else
        requiredWidth = padding + (buttonWidth + padding) * numButtons
        requiredHeight = padding + buttonHeight + padding + (Target_Settings.compactOverlay and 10 or 12)
    end

    overlayFrame:SetSize(requiredWidth, requiredHeight)

    for i, button in ipairs(addon.arenaButtons) do
        button:ClearAllPoints()
        if overlayLayout == "Horizontal" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * (i - 1), -padding)
        elseif overlayLayout == "Vertical" then
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding, -padding - (buttonHeight + padding + (Target_Settings.compactOverlay and 10 or 12)) * (i - 1))
        elseif overlayLayout == "Grid" then
            local row = math.floor((i - 1) / 3)
            local col = (i - 1) % 3
            button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", padding + (buttonWidth + padding) * col, -padding - (buttonHeight + padding + (Target_Settings.compactOverlay and 10 or 12)) * row)
        end
        button.ratingText:SetPoint("CENTER", button, "CENTER", 0, Target_Settings.compactOverlay and -10 or -12)
    end
end

-- Updated to addon scope
function addon.UpdateButtonMacros()
    if InCombatLockdown() or not C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") then
        return
    end

    local RATED_CATEGORY_BUTTON = "PVPQueueFrameCategoryButton2"
    local _, groupBracketIndex = GetGroupSizeBracket()

    local bracketButtons = {
        [1] = "ConquestFrame.Arena2v2",        -- 2v2
        [2] = "ConquestFrame.Arena3v3",        -- 3v3
        [7] = "ConquestFrame.RatedSoloShuffle",-- Solo Shuffle
        [4] = "ConquestFrame.RatedBG",         -- RBG
        [9] = "ConquestFrame.BattleBlitz"      -- Battle Blitz
    }

    for _, button in ipairs(addon.arenaButtons) do
        ActionButton_HideOverlayGlow(button)
    end

    for _, button in ipairs(addon.arenaButtons) do
        local bracketButton = bracketButtons[button.bracketIndex]
        if bracketButton then
            button:SetAttribute("type", "macro")
            local macroText =
                "/click LFDMicroButton\n" ..
                "/click PVEFrameTab2\n" ..
                "/click " .. RATED_CATEGORY_BUTTON .. "\n" ..
                "/click " .. bracketButton .. "\n" ..
                "/click " .. bracketButton .. "\n" ..
                "/click ConquestJoinButton"
            button:SetAttribute("macrotext", macroText)
            if Target_Settings.enableGlow and button.bracketIndex == groupBracketIndex then
                ActionButton_ShowOverlayGlow(button)
            end
        else
            button:SetAttribute("type", "macro")
            button:SetAttribute("macrotext",
                "/click LFDMicroButton\n" ..
                "/click PVEFrameTab2"
            )
        end
    end
end

local function ConfigureSecureButtons()
    if not overlayFrame or InCombatLockdown() then
        return
    end
    for _, button in ipairs(addon.arenaButtons) do
        if not button.isConfigured then
            SecureHandlerWrapScript(button, "OnClick", button, [[
                if IsShiftKeyDown() then
                    self:SetAttribute("macrotext", "")
                    return
                end
            ]])
            button.isConfigured = true
        end
        button:Enable()
    end
    addon.UpdateButtonMacros()
end

local function HookPVEFrame()
    if PVEFrame and not PVEFrame.TargetHooked then
        hooksecurefunc(PVEFrame, "Show", function()
            if C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") and PVEFrame.activeTabIndex == 2 then
                C_Timer.After(0.5, function()
                    addon.UpdateButtonMacros()
                end)
            end
        end)
        PVEFrame.TargetHooked = true
    end
end

local function HookPVEFrameDelayed()
    if PVEFrame and not PVEFrame.TargetHooked then
        hooksecurefunc(PVEFrame, "Show", function()
            if C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") and PVEFrame.activeTabIndex == 2 then
                C_Timer.After(0.5, function()
                    addon.UpdateButtonMacros()
                end)
            end
        end)
        PVEFrame.TargetHooked = true
    end
end

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
    local overlayWidth = Target_Settings.compactOverlay and 450 or 650
    local overlayHeight = Target_Settings.compactOverlay and 30 or 38
    local posX = Target_Settings.overlayPosX or 0
    local posY = Target_Settings.overlayPosY or 0

    local useBackdropTemplate = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    overlayFrame = CreateFrame("Frame", "TargetOverlayFrame", UIParent, useBackdropTemplate and "BackdropTemplate" or nil)
    overlayFrame:SetSize(overlayWidth, overlayHeight)
    overlayFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)

    local backdrop = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
        edgeFile = borderStyle,
        tile = false,
        tileSize = 0,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    }
    overlayFrame:SetBackdrop(backdrop)
    overlayFrame:SetBackdropColor(1, 1, 1, 0.9)
    overlayFrame:SetBackdropBorderColor(1, 0.8, 0, 1)

    overlayFrame:EnableMouse(true)
    overlayFrame:SetMovable(true)
    overlayFrame:RegisterForDrag("LeftButton")
    overlayFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
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
        local button = CreateFrame("Button", "ArenaButton" .. data.name, overlayFrame, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
        local buttonWidth = Target_Settings.compactOverlay and 80 or 120
        local buttonHeight = Target_Settings.compactOverlay and 16 or 20
        button:SetSize(buttonWidth, buttonHeight)
        button:SetText(data.name)
        button.bracketIndex = data.bracketIndex
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:EnableMouse(true)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\UI-Button-Background")
        bg:SetVertexColor(0.8, 0.2, 0.2, 1)

        local border = button:CreateTexture(nil, "BORDER")
        border:SetAllPoints()
        border:SetTexture("Interface\\Buttons\\UI-Button-Border")
        border:SetVertexColor(1, 0.8, 0, 1)

        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        local highlight = button:GetHighlightTexture()
        highlight:SetAllPoints()
        highlight:SetAlpha(1.0)

        local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        buttonText:SetPoint("CENTER", button, "CENTER", 0, 0)
        buttonText:SetText(data.name)
        buttonText:SetFont("Fonts\\FRIZQT__.TTF", Target_Settings.compactOverlay and 8 or 10, "OUTLINE")
        buttonText:SetTextColor(1, 0.9, 0.1, 1)
        buttonText:SetShadowOffset(1, -1)
        buttonText:SetShadowColor(0, 0, 0, 1)

        local ratingText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ratingText:SetPoint("CENTER", button, "CENTER", 0, Target_Settings.compactOverlay and -10 or -12)
        ratingText:SetText("Loading...")
        ratingText:SetFont("Fonts\\FRIZQT__.TTF", Target_Settings.compactOverlay and 7 or 9, "OUTLINE")
        ratingText:SetTextColor(1, 1, 1, 1)
        ratingText:SetShadowOffset(1, -1)
        ratingText:SetShadowColor(0, 0, 0, 1)
        ratingTexts[index] = ratingText
        button.ratingText = ratingText

        button:SetAttribute("bracketIndex", data.bracketIndex)

        local animGroup = button:CreateAnimationGroup()
        local scaleDown = animGroup:CreateAnimation("Scale")
        scaleDown:SetScale(0.95, 0.95)
        scaleDown:SetDuration(0.1)
        scaleDown:SetOrder(1)
        local scaleUp = animGroup:CreateAnimation("Scale")
        scaleUp:SetScale(1.0526, 1.0526)
        scaleUp:SetDuration(0.1)
        scaleUp:SetOrder(2)
        button:SetScript("OnMouseDown", function(self)
            animGroup:Play()
        end)

        button:HookScript("OnEnter", function(self)
            if Target_Settings.enableGlow then
                ActionButton_ShowOverlayGlow(self)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local groupBracketName, groupBracketIndex = GetGroupSizeBracket()
            if IsShiftKeyDown() then
                GameTooltip:SetText("Drag to move overlay")
            elseif groupBracketIndex == self.bracketIndex then
                GameTooltip:SetText("Queue for " .. data.name)
            else
                GameTooltip:SetText("Queue for " .. data.name .. "\nGroup size suggests: " .. groupBracketName)
            end
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function(self)
            if Target_Settings.enableGlow then
                ActionButton_HideOverlayGlow(self)
            end
            GameTooltip:Hide()
        end)

        table.insert(addon.arenaButtons, button)
    end

    local function updateRatings()
        if not C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") then
            return
        end
        for i, button in ipairs(addon.arenaButtons) do
            local rating = GetPersonalRatedInfo(button.bracketIndex)
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
    overlayFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    overlayFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    overlayFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    overlayFrame:RegisterEvent("ADDON_LOADED")
    overlayFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    overlayFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_LOADED" then
            local addonLoaded = ...
            if addonLoaded == PVPUI_ADDON_NAME then
                updateRatings()
                ConfigureSecureButtons()
                HookPVEFrameDelayed()
            elseif addonLoaded == addonName then
                updateRatings()
                HookPVEFrameDelayed()
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_BATTLEFIELD_STATUS" then
            if not InCombatLockdown() then
                for _, button in ipairs(addon.arenaButtons) do
                    button:Enable()
                end
                addon.UpdateButtonMacros()
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            for _, button in ipairs(addon.arenaButtons) do
                button:Disable()
            end
        elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(1, function()
                if not C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") then
                    UIParentLoadAddOn("Blizzard_PVPUI")
                end
                addon.UpdateButtonMacros()
                ConfigureSecureButtons()
            end)
        end
        updateRatings()
    end)

    overlayFrame:SetScript("OnShow", function()
        addon.ApplyOverlayAppearanceChanges()
        updateRatings()
        ConfigureSecureButtons()
        for _, button in ipairs(addon.arenaButtons) do
            if not InCombatLockdown() then
                button:Enable()
            end
        end
    end)

    overlayFrame:SetScript("OnHide", function()
        for _, button in ipairs(addon.arenaButtons) do
            button:Disable()
        end
    end)

    addon.arrangeArenaButtons()
    _G["TargetOverlayFrame"] = overlayFrame
    overlayFrame:Show()
end

SLASH_TARGETRESET1 = "/targetreset"
SlashCmdList["TARGETRESET"] = function(msg)
    if Target_Settings then
        Target_Settings.overlayPosX = 0
        Target_Settings.overlayPosY = 0
        Target_Settings.overlayWidth = Target_Settings.compactOverlay and 450 or 650
        Target_Settings.overlayHeight = Target_Settings.compactOverlay and 30 or 38

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

local overlayEventFrame = CreateFrame("Frame")
overlayEventFrame:RegisterEvent("ADDON_LOADED")
overlayEventFrame:RegisterEvent("PLAYER_LOGIN")

-- Flag to ensure the message only prints once per session
local hasShownMessage = false

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

        -- Print the instructional message once per session
        if not hasShownMessage then
            print("|cFFFFD700ClassTarget:|r You will need to manually select the PvP bracket in the UI before clicking the overlay to queue the intended bracket.")
            hasShownMessage = true
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