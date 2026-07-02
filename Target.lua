local addonName, addon = ...

local borderStyles = {
    ["Default"] = "Interface\\DialogFrame\\UI-DialogBox-Border",
    ["Thin"] = "Interface\\Tooltips\\UI-Tooltip-Border",
    ["None"] = ""
}

function addon.ApplyOverlayAppearanceChanges()
    -- No dynamic changes, we recreate the overlay frame when needed.
end

local defaultSettings = {
    xValue = 0,
    yValue = 0,
    iconType = "Default",
    iconSize = 32,
    iconOpacity = 1.0,
    enableInOpenWorld = true,
    enableInArena = true,
    enableInSoloShuffle = true,
    enableInBattleground = true,
    enableInRaid = true,
    enableInDungeon = true,
    enableInDelves = true,
    showOverlay = true,
    layout = "Horizontal",
    overlayLayout = "Horizontal",
    overlayBorderStyle = "Interface\\DialogFrame\\UI-DialogBox-Border",
    compactOverlay = false,
    enableGlow = true,
    overlayScale = 1.0,
    hideOverlayInArena = false,  -- New: Option to hide overlay in arena
}

local profiles = {
    Default = CopyTable(defaultSettings)
}
local currentProfile = "Default"

local iconTypes = {
    ["Default"] = { suffix = "",        useClassColor = false },
    ["Circle"]  = { suffix = "-circle", useClassColor = false },
    ["Class Color"] = { suffix = "-color", useClassColor = true },
    ["Minimalistic"] = { styleKey = "Min" },
    ["HD"]           = { styleKey = "HD" },
    ["Cartoon"]      = { styleKey = "Cartoon" },
}

local classToFilenames = {
    deathknight = {
        Min = "Death Knight-Min.tga",
        HD  = "DK-HD.tga",
        Cartoon = "DeathKnight-Cartoon.tga",
    },
    demonhunter = {
        Min = "Demon Hunter-Min.tga",
        HD  = "DH-HD.tga",
        Cartoon = "DemonHunter-Cartoon.tga",
    },
    druid = {
        Min = "Druid-Min.tga",
        HD  = "Druid-HD.tga",
        Cartoon = "Druid-Cartoon.tga",
    },
    evoker = {
        Min = "Evoker-Min.tga",
        HD  = "Evoker-HD.tga",
        Cartoon = "Evoker-Cartoon.tga",
    },
    hunter = {
        Min = "Hunter-Min.tga",
        HD  = "Hunter-HD.tga",
        Cartoon = "Hunter-Cartoon.tga",
    },
    mage = {
        Min = "Mage-Min.tga",
        HD  = "Mage-HD.tga",
        Cartoon = "Mage-Cartoon.tga",
    },
    monk = {
        Min = "Monk-Min.tga",
        HD  = "Monk-HD.tga",
        Cartoon = "Monk-Cartoon.tga",
    },
    paladin = {
        Min = "Paladin-Min.tga",
        HD  = "Paladin-HD.tga",
        Cartoon = "Paladin-Cartoon.tga",
    },
    priest = {
        Min = "Priest-Min.tga",
        HD  = "Priest-HD.tga",
        Cartoon = "Priest-Cartoon.tga",
    },
    rogue = {
        Min = "Rogue-Min.tga",
        HD  = "Rogue-HD.tga",
        Cartoon = "Rogue-Cartoon.tga",
    },
    shaman = {
        Min = "Shaman-Min.tga",
        HD  = "Shaman-HD.tga",
        Cartoon = "Shaman-Cartoon.tga",
    },
    warlock = {
        Min = "Warlock-Min.tga",
        HD  = "Warlock-HD.tga",
        Cartoon = "Warlock-Cartoon.tga",
    },
    warrior = {
        Min = "Warrior-Min.tga",
        HD  = "Warrior-HD.tga",
        Cartoon = "Warrior-Cartoon.tga",
    },
}

local layoutTypes = {
    ["Horizontal"] = "Horizontal",
    ["Vertical"] = "Vertical",
    ["Grid"] = "Grid"
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

local players = {}
local nameplateFrames = {}
local updateTicker

-- In rated arena/Solo Shuffle, identity APIs (UnitIsUnit/UnitGUID/GetNamePlateForUnit)
-- against a teammate's target return restricted "secret" values, and UnitName on an
-- ENEMY target is now secret on every frame (probe log 2026-06-20), so names can no
-- longer bridge the gap in rated play. The primary arena matcher is now the
-- FINGERPRINT tier (see unitFingerprint below): class/race/sex/honor level remain
-- readable through teammate-target tokens even when identity is secret. The name
-- cache below still serves open world / unrated content, where names stay readable
-- but can flicker. The cache is invalidated the moment that teammate actually changes
-- target (UNIT_TARGET), so we never show a stale icon for a target they no longer have.
local targetNameCache = {}

-- Persistent debug log (written to SavedVariables\Target.lua so it can be read
-- off-game). Capped so it can't grow without bound. Toggle with /targetlog.
local MAX_DEBUG_LINES = 500
local debugLoggingEnabled = false

local function debugLog(msg)
    if not debugLoggingEnabled then return end
    if type(Target_DebugLog) ~= "table" then Target_DebugLog = {} end
    local stamp = date("%Y-%m-%d %H:%M:%S")
    Target_DebugLog[#Target_DebugLog + 1] = stamp .. "  " .. tostring(msg)
    -- Trim from the front when over the cap.
    local overflow = #Target_DebugLog - MAX_DEBUG_LINES
    if overflow > 0 then
        for i = 1, #Target_DebugLog - overflow do
            Target_DebugLog[i] = Target_DebugLog[i + overflow]
        end
        for i = #Target_DebugLog, #Target_DebugLog - overflow + 1, -1 do
            Target_DebugLog[i] = nil
        end
    end
end

local function SaveProfileSettings()
    Target_Profiles[currentProfile] = CopyTable(Target_Settings)
    Target_CurrentProfile = currentProfile
end

local function generateUniqueProfileName(baseName)
    local counter = 1
    local uniqueName = baseName
    while profiles[uniqueName] do
        uniqueName = baseName .. " " .. counter
        counter = counter + 1
    end
    return uniqueName
end

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

local function createPlayer(unitId)
    if unitId ~= "player" and not UnitExists(unitId) then
        return nil
    end

    local player = players[unitId] or {}
    players[unitId] = player

    player.unitId = unitId
    player.targetId = unitId .. "target"
    player.guid = unitId
    player.classToken = select(2, UnitClass(unitId)) or ""
    player.classKey = player.classToken ~= "" and player.classToken:lower() or ""

    local iconType = iconTypes[Target_Settings.iconType] or iconTypes["Default"]
    local classImage = player.classToken .. (iconType.suffix or "") .. ".tga"

    if iconType.styleKey and player.classKey ~= "" and classToFilenames[player.classKey] and classToFilenames[player.classKey][iconType.styleKey] then
        classImage = classToFilenames[player.classKey][iconType.styleKey]
    end

    if not player.texture then
        player.texture = frame:CreateTexture(player.guid .. "-Texture", "OVERLAY")
    end
    local iconSize = tonumber(Target_Settings.iconSize) or 32

    if player.classToken ~= "" then
        player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
    else
        -- Hide non-player/unknown class units (e.g. follower dungeon companions)
        player.texture:SetTexture(nil)
    end
    player.texture:SetSize(iconSize, iconSize)
    player.texture:SetAlpha(Target_Settings.iconOpacity)

    return player
end

local function clearPlayers()
    for _, player in pairs(players) do
        if player.texture then
            player.texture:ClearAllPoints()
            player.texture:Hide()
            player.texture:SetParent(UIParent)
        end
    end
    wipe(players)
end

local function getTrackedUnitIds()
    local unitIds = { "player" }

    if IsInRaid() then
        local numMembers = GetNumGroupMembers() or 0
        for i = 1, numMembers do
            local unitId = "raid" .. i
            if UnitExists(unitId) and not UnitIsUnit(unitId, "player") then
                unitIds[#unitIds + 1] = unitId
            end
        end
    else
        local numMembers = GetNumSubgroupMembers() or 0
        for i = 1, numMembers do
            local unitId = "party" .. i
            if UnitExists(unitId) then
                unitIds[#unitIds + 1] = unitId
            end
        end
    end

    return unitIds
end

local function registerTargetUnitEvents(unitIds)
    frame:UnregisterEvent("UNIT_TARGET")
    frame:RegisterUnitEvent("UNIT_TARGET", unpack(unitIds))
end

local function initializePlayers()
    clearPlayers()
    wipe(targetNameCache)
    local unitIds = getTrackedUnitIds()

    for _, unitId in ipairs(unitIds) do
        createPlayer(unitId)
    end

    registerTargetUnitEvents(unitIds)

    if debugLoggingEnabled then
        debugLog(("initializePlayers: inRaid=%s grp=%d subgrp=%d tracking={%s}"):format(
            tostring(IsInRaid()), GetNumGroupMembers() or 0,
            GetNumSubgroupMembers() or 0, table.concat(unitIds, ", ")))
    end
end

local function isAddonEnabled()
    local inInstance, zoneType = IsInInstance()
    if zoneType == "arena" and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle() then
        return Target_Settings.enableInSoloShuffle
    end

    local zoneChecks = {
        none = Target_Settings.enableInOpenWorld,
        arena = Target_Settings.enableInArena,
        pvp = Target_Settings.enableInBattleground,
        raid = Target_Settings.enableInRaid,
        party = Target_Settings.enableInDungeon,
        scenario = Target_Settings.enableInDungeon,
        delves = Target_Settings.enableInDelves
    }
    return zoneChecks[zoneType] or false
end
local function clearNamePlates()
    for _, f in pairs(nameplateFrames) do
        f:Hide()
    end
    for _, player in pairs(players) do
        if player.texture then
            player.texture:ClearAllPoints()
            player.texture:Hide()
        end
    end
end

-- Return a usable (non-forbidden) nameplate frame for a nameplate unit token.
local function usablePlate(npUnit)
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, npUnit)
    if ok and plate and (not plate.IsForbidden or not plate:IsForbidden()) then
        return plate
    end
    return nil
end

-- "Fingerprint" identity matching (technique proven by SweepyBoop in current rated
-- arena): UnitIsUnit/UnitGUID/UnitName against enemy players return secrets in
-- instanced PvP, but class, race, sex and honor level stay READABLE - even through
-- indirect tokens like "party1target". Comparing that tuple is the only sanctioned
-- way left to link a teammate's target to a nameplate.
local function safeRead(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Returns class, raceFile, sex, honorLevel (multiple values, no table -> no GC
-- churn from the 10Hz ticker). Returns nil if even the class is unreadable.
local function unitFingerprint(unit)
    local class = safeRead(UnitClassBase, unit)
    if not class then return nil end
    local race
    local ok, _, raceFile = pcall(UnitRace, unit) -- raceFile is locale-independent
    if ok and raceFile and not (issecretvalue and issecretvalue(raceFile)) then
        race = raceFile
    end
    return class, race, safeRead(UnitSex, unit), safeRead(UnitHonorLevel, unit)
end

-- Components can be nil (out of range / secret); only compare what both sides have.
-- Class is mandatory. The caller additionally requires the match to be UNIQUE among
-- visible nameplates, so partial prints can never mistag a lookalike.
local function fingerprintsMatch(cA, rA, sA, hA, cB, rB, sB, hB)
    if not cA or not cB or cA ~= cB then return false end
    if rA and rB and rA ~= rB then return false end
    if sA and sB and sA ~= sB then return false end
    if hA and hB and hA ~= hB then return false end
    return true
end

local function fingerprintString(class, race, sex, honor)
    if not class then return "nil" end
    return ("%s/%s/%s/%s"):format(class, tostring(race), tostring(sex), tostring(honor))
end

local function getNamePlateForTarget(targetUnitId)
    if not targetUnitId then
        return nil
    end

    -- Fast path for the player's own target.
    if targetUnitId == "playertarget" then
        local plate = usablePlate("target")
        if plate then return plate end
    end

    if not UnitExists(targetUnitId) then
        return nil
    end

    -- Direct lookup for tokens GetNamePlateForUnit accepts directly (e.g. "target").
    local plate = usablePlate(targetUnitId)
    if plate then return plate end

    -- Match a group member's target to a visible nameplate, in order of reliability:
    --   1. UnitIsUnit - exact; works in open world / dungeons.
    --   2. GUID match - exact; also disambiguates duplicate names.
    --   3. Fingerprint match (instanced PvP only) - class/race/sex/honor level stay
    --      readable when identity APIs return secrets (probe log 2026-06-20 showed
    --      UnitIsUnit vs arenaN silently returns FALSE and enemy names are ALWAYS
    --      secret in rated arena, killing tiers 1-2 and 4 there). Only trusted when
    --      exactly ONE visible nameplate matches the tuple.
    --   4. Name match - last resort for unrated content. Only used when the name is
    --      UNIQUE among nameplates, so we never tag the wrong same-named unit.
    -- IMPORTANT: these APIs don't error on restricted units - they RETURN "secret"
    -- values, and merely comparing (==) a secret raises a blocked-action Lua error.
    -- pcall around the API call does NOT cover the later comparison, so every
    -- secret must be detected with issecretvalue() and treated as unknown.
    local issecret = issecretvalue or function() return false end
    local okGUID, targetGUID = pcall(UnitGUID, targetUnitId)
    if not okGUID or issecret(targetGUID) then targetGUID = nil end
    local okName, liveName = pcall(UnitName, targetUnitId)
    if not okName or issecret(liveName) then liveName = nil end

    -- Fingerprint tier setup: only inside instanced PvP, where the exact tiers are
    -- the ones that lie; anywhere else tiers 1-2 are exact and this could only
    -- mistag a lookalike. Skip friendly targets (friendlies aren't secret, so if
    -- identity was going to resolve at all, tiers 1-2 already did). Pets are fair
    -- game: teammates DO target enemy pets (2026-07-01 log), and a pet's print
    -- (race=nil, sex=1, honor=0) can't collide with any player's print because sex
    -- is always 2/3 for players.
    local tfClass, tfRace, tfSex, tfHonor
    local targetIsPlayer
    local _, zoneType = IsInInstance()
    if zoneType == "arena" or zoneType == "pvp" then
        local isFriend = safeRead(UnitIsFriend, "player", targetUnitId)
        if isFriend ~= true then
            targetIsPlayer = safeRead(UnitIsPlayer, targetUnitId)
            tfClass, tfRace, tfSex, tfHonor = unitFingerprint(targetUnitId)
        end
    end

    -- Name flickers to a secret on some frames in rated arena, and worse, the
    -- restricted API sometimes returns a WRONG-but-readable name (e.g. the player's
    -- own name) for a teammate's target. So we do NOT trust a live name blindly:
    -- we only cache a name once it has been PROVEN to map to a real enemy nameplate
    -- (done after the match loop below). During secret/garbage frames we bridge with
    -- that proven cached name. Cache is cleared on UNIT_TARGET so it can never point
    -- at a target the teammate has since switched away from.
    local targetName = liveName or targetNameCache[targetUnitId]

    local nameMatch, nameMatchCount = nil, 0
    local fpMatch, fpMatchCount = nil, 0
    for i = 1, 40 do
        local npUnit = "nameplate" .. i
        if UnitExists(npUnit) then
            -- 1. identity
            local okSame, same = pcall(UnitIsUnit, npUnit, targetUnitId)
            if okSame and not issecret(same) and same then
                local p = usablePlate(npUnit)
                if p then return p end
            end
            -- 2. guid
            if targetGUID then
                local okG, npGUID = pcall(UnitGUID, npUnit)
                if okG and not issecret(npGUID) and npGUID and npGUID == targetGUID then
                    local p = usablePlate(npUnit)
                    if p then return p end
                end
            end
            -- 3. collect fingerprint candidates: hostile plates whose playerness
            --    agrees with the target's (when both are readable), so a teammate
            --    targeting a pet matches pet plates and never a player lookalike
            if tfClass then
                local plateIsPlayer = safeRead(UnitIsPlayer, npUnit)
                local playernessOk = targetIsPlayer == nil or plateIsPlayer == nil
                    or targetIsPlayer == plateIsPlayer
                local reaction = safeRead(UnitReaction, "player", npUnit)
                if playernessOk and (not reaction or reaction < 5)
                    and fingerprintsMatch(tfClass, tfRace, tfSex, tfHonor, unitFingerprint(npUnit)) then
                    fpMatchCount = fpMatchCount + 1
                    fpMatch = npUnit
                end
            end
            -- 4. collect unique-name candidates for the fallback
            if targetName then
                local okN, npName = pcall(UnitName, npUnit)
                if okN and not issecret(npName) and npName and npName == targetName then
                    nameMatchCount = nameMatchCount + 1
                    nameMatch = npUnit
                end
            end
        end
    end

    -- Unique fingerprint match: the arena/BG path. Two same-tuple enemies (mirror
    -- comp with equal honor level) stay ambiguous and draw nothing - never wrong.
    if fpMatchCount == 1 then
        return usablePlate(fpMatch)
    end

    if nameMatchCount == 1 then
        -- We matched a real, unique enemy nameplate by name. If this match came from
        -- a freshly-read live name, remember it so we can bridge future secret frames.
        -- (Only cache PROVEN names -> never poisons the cache with the player's own
        -- name or other garbage the restricted API returns.)
        if liveName then
            targetNameCache[targetUnitId] = liveName
        end
        return usablePlate(nameMatch)
    end

    return nil
end

local updateNamePlates
local updateNamePlatesPending = false

local function scheduleUpdateNamePlates()
    if updateNamePlatesPending then return end
    updateNamePlatesPending = true
    C_Timer.After(0, function()
        updateNamePlatesPending = false
        updateNamePlates()
    end)
end

updateNamePlates = function()
    if not isAddonEnabled() then
        if debugLoggingEnabled then
            local _, zoneType = IsInInstance()
            debugLog("addon DISABLED for this zone (instanceType=" .. tostring(zoneType) .. ")")
        end
        for _, f in pairs(nameplateFrames) do
            f:Hide()
        end
        wipe(nameplateFrames)
        return
    end

    local currentCounts = {}
    local layout = Target_Settings.layout
    local xOffset, yOffset = Target_Settings.xValue, Target_Settings.yValue

    -- Resolve each tracked player's nameplate exactly ONCE per pass. The matcher is
    -- non-deterministic frame-to-frame in rated arena (names flicker), so calling it
    -- multiple times for the same player can disagree. Cache the result for this pass
    -- so the match, the per-plate count, and the draw all use the same answer.
    local resolved = {}
    for _, player in pairs(players) do
        if player.texture and player.classToken ~= "" then
            resolved[player] = getNamePlateForTarget(player.targetId)
        end
    end

    for _, player in pairs(players) do
        -- Class may not have been available when the player was first created
        -- (e.g. party member's data not yet loaded on zone-in). Without this,
        -- a group member whose class was "" at init is skipped forever and
        -- their target icon never appears. Re-resolve it here.
        if player.classToken == "" and UnitExists(player.unitId) and (select(2, UnitClass(player.unitId)) or "") ~= "" then
            createPlayer(player.unitId)
        end
        if player.texture and player.classToken ~= "" then
            local nameplate = resolved[player]
            if debugLoggingEnabled then
                local issecret = issecretvalue or function() return false end
                local function fmt(ok, v)
                    if not ok then return "err" end
                    if issecret(v) then return "SECRET" end
                    if v == nil then return "nil" end
                    return tostring(v)
                end
                local okExists, tExists = pcall(UnitExists, player.targetId)
                local okName, tName = pcall(UnitName, player.targetId)
                -- Count how many enemy nameplates are currently visible, so we can
                -- tell "no nameplates at all" from "nameplate exists but unmatched".
                local npCount = 0
                for i = 1, 40 do
                    if UnitExists("nameplate" .. i) then npCount = npCount + 1 end
                end
                -- PROBE: for teammate targets, dump the fingerprint of the target
                -- token next to every visible nameplate's fingerprint, so the log
                -- shows exactly why the fingerprint tier did or didn't match.
                local probe = ""
                if player.targetId ~= "playertarget" then
                    probe = " fp=" .. fingerprintString(unitFingerprint(player.targetId))
                    for i = 1, 40 do
                        local npU = "nameplate" .. i
                        if UnitExists(npU) then
                            probe = probe .. (" np%d=%s"):format(i, fingerprintString(unitFingerprint(npU)))
                        end
                    end
                end
                local line = ("%s (%s) target=%s exists=%s name=%s nameplates=%d plate=%s%s"):format(
                    player.unitId, player.classToken, player.targetId,
                    fmt(okExists, tExists), fmt(okName, tName), npCount,
                    nameplate and "FOUND" or "MISSING", probe)
                -- Only record when this unit's line CHANGES, so the log stays readable
                -- instead of 250 identical spam entries per second.
                if player._lastLogLine ~= line then
                    player._lastLogLine = line
                    debugLog(line)
                end
            end
            if nameplate then
                -- Use the nameplate frame object as a stable key instead of GUIDs
                local plate = nameplate
                local targetCount = 0
                for other, otherPlate in pairs(resolved) do
                    if otherPlate == plate then
                        targetCount = targetCount + 1
                    end
                end

                local width, height = player.texture:GetSize()
                local nameplateFrame = nameplateFrames[plate]

                if not nameplateFrame then
                    nameplateFrame = CreateFrame("Frame", nil, plate)
                    -- SweepyBoop's proven recipe for plate-attached icons: in arena
                    -- the plate base frame's effective alpha is driven to ~0 for
                    -- units you aren't targeting (Blizzard fading + nameplate-
                    -- replacement addons), which silently blanks any child that
                    -- inherits it. IsShown() stays true - invisible by alpha only.
                    nameplateFrame:SetMouseClickEnabled(false)
                    nameplateFrame:SetAlpha(1)
                    nameplateFrame:SetIgnoreParentAlpha(true)
                    nameplateFrame:SetFrameStrata("HIGH")
                    nameplateFrames[plate] = nameplateFrame
                end
                nameplateFrame:ClearAllPoints()

                if layout == "Horizontal" then
                    nameplateFrame:SetSize(width * targetCount, height)
                    nameplateFrame:SetPoint("BOTTOM", plate, "TOP", xOffset, yOffset)
                elseif layout == "Vertical" then
                    nameplateFrame:SetSize(width, height * targetCount)
                    nameplateFrame:SetPoint("BOTTOM", plate, "TOP", xOffset, yOffset)
                elseif layout == "Grid" then
                    local columns = math.ceil(math.sqrt(targetCount))
                    local rows = math.ceil(targetCount / columns)
                    nameplateFrame:SetSize(width * columns, height * rows)
                    nameplateFrame:SetPoint("BOTTOM", plate, "TOP", xOffset, yOffset)
                else
                    nameplateFrame:SetSize(width * targetCount, height)
                    nameplateFrame:SetPoint("BOTTOM", plate, "TOP", xOffset, yOffset)
                end

                nameplateFrame:Show()

                if not currentCounts[plate] then
                    currentCounts[plate] = 0
                end
                currentCounts[plate] = currentCounts[plate] + 1

                player.texture:SetParent(nameplateFrame)

                if layout == "Horizontal" then
                    player.texture:SetPoint("LEFT", nameplateFrame, "LEFT", (currentCounts[plate] - 1) * width, 0)
                elseif layout == "Vertical" then
                    player.texture:SetPoint("TOP", nameplateFrame, "TOP", 0, -(currentCounts[plate] - 1) * height)
                elseif layout == "Grid" then
                    local col = (currentCounts[plate] - 1) % math.ceil(math.sqrt(targetCount))
                    local row = math.floor((currentCounts[plate] - 1) / math.ceil(math.sqrt(targetCount)))
                    player.texture:SetPoint("LEFT", nameplateFrame, "LEFT", col * width, -row * height)
                end

                player.texture:Show()
            end
        end
    end
end

local function startTicker()
    if updateTicker then
        updateTicker:Cancel()
    end
    updateTicker = C_Timer.NewTicker(0.1, scheduleUpdateNamePlates)
end

local function addTooltip(frame, text)
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function initializeUI()
    if TargetOptionsFrame and TargetOptionsFrame:IsObjectType("Frame") then
        return
    end

    local optionsFrame = CreateFrame("Frame", "TargetOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame.name = "ClassTarget"
    optionsFrame:SetSize(700, 600)
    optionsFrame:SetPoint("CENTER")
    optionsFrame:Hide()

    local title = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", optionsFrame, "TOP", 0, -16)
    title:SetText("ClassTarget Addon Settings")

    local container = CreateFrame("Frame", nil, optionsFrame)
    container:SetSize(optionsFrame:GetWidth() - 40, optionsFrame:GetHeight() - 80)
    container:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -50)

    local leftColumn = CreateFrame("Frame", nil, container)
    leftColumn:SetSize((container:GetWidth() - 20) / 2, container:GetHeight())
    leftColumn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    local rightColumn = CreateFrame("Frame", nil, container)
    rightColumn:SetSize((container:GetWidth() - 20) / 2, container:GetHeight())
    rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", 20, 0)

    local verticalSpacing = -5
    local sectionSpacing = -10
    local lastControlLeft = nil

    -- Profiles
    local profileTitle = leftColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    profileTitle:SetPoint("TOPLEFT", 0, 0)
    profileTitle:SetText("Profiles")
    lastControlLeft = profileTitle

    local profileDropdown = CreateFrame("Frame", "TargetProfileDropdown", leftColumn, "UIDropDownMenuTemplate")
    profileDropdown:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", -15, verticalSpacing)
    UIDropDownMenu_SetWidth(profileDropdown, 150)
    addTooltip(profileDropdown, "Select a profile to load its settings.")

    local function OnClick(self)
        UIDropDownMenu_SetSelectedID(profileDropdown, self:GetID())
        currentProfile = self.value
        Target_Settings = CopyTable(profiles[currentProfile])
        scheduleUpdateNamePlates()
        SaveProfileSettings()
        addon.ApplyOverlayAppearanceChanges()
    end

    local function InitializeProfileDropdown(self, level)
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

    UIDropDownMenu_Initialize(profileDropdown, InitializeProfileDropdown)
    lastControlLeft = profileDropdown

    local createProfileButton = CreateFrame("Button", "CreateProfileButton", leftColumn, "UIPanelButtonTemplate")
    createProfileButton:SetSize(120, 25)
    createProfileButton:SetText("Create Profile")
    createProfileButton:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, verticalSpacing)
    createProfileButton:SetScript("OnClick", function()
        local newProfileName = generateUniqueProfileName("New Profile")
        profiles[newProfileName] = CopyTable(Target_Settings)
        currentProfile = newProfileName
        Target_Settings = profiles[currentProfile]
        UIDropDownMenu_Initialize(profileDropdown, InitializeProfileDropdown)
        scheduleUpdateNamePlates()
        SaveProfileSettings()
        addon.ApplyOverlayAppearanceChanges()
    end)
    addTooltip(createProfileButton, "Create a new profile with the current settings.")
    lastControlLeft = createProfileButton

    local deleteProfileButton = CreateFrame("Button", "DeleteProfileButton", leftColumn, "UIPanelButtonTemplate")
    deleteProfileButton:SetSize(120, 25)
    deleteProfileButton:SetText("Delete Profile")
    deleteProfileButton:SetPoint("LEFT", createProfileButton, "RIGHT", 10, 0)
    deleteProfileButton:SetScript("OnClick", function()
        deleteProfile(currentProfile)
        UIDropDownMenu_Initialize(profileDropdown, InitializeProfileDropdown)
        scheduleUpdateNamePlates()
        addon.ApplyOverlayAppearanceChanges()
    end)
    addTooltip(deleteProfileButton, "Delete the currently selected profile.")
    lastControlLeft = deleteProfileButton

    -- General Settings
    local generalSettingsTitle = leftColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    generalSettingsTitle:SetPoint("TOPLEFT", deleteProfileButton, "BOTTOMLEFT", 0, sectionSpacing)
    generalSettingsTitle:SetText("General Settings")
    lastControlLeft = generalSettingsTitle

    local iconTypeLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iconTypeLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, verticalSpacing)
    iconTypeLabel:SetText("Icon Type")

    local iconTypeDropdown = CreateFrame("Frame", "TargetIconTypeDropdown", leftColumn, "UIDropDownMenuTemplate")
    iconTypeDropdown:SetPoint("TOPLEFT", iconTypeLabel, "BOTTOMLEFT", -15, verticalSpacing)
    UIDropDownMenu_SetWidth(iconTypeDropdown, 150)
    addTooltip(iconTypeDropdown, "Choose the appearance of the target icons.")

    local function OnIconTypeClick(self)
        UIDropDownMenu_SetSelectedID(iconTypeDropdown, self:GetID())
        Target_Settings.iconType = self.value
        for _, player in pairs(players) do
            if player.texture then
                local it = iconTypes[Target_Settings.iconType] or iconTypes["Default"]
                local classImage = player.classToken .. (it.suffix or "") .. ".tga"
                if it.styleKey and player.classKey ~= "" and classToFilenames[player.classKey] and classToFilenames[player.classKey][it.styleKey] then
                    classImage = classToFilenames[player.classKey][it.styleKey]
                end
                if player.classToken ~= "" then
                    player.texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\" .. classImage)
                else
                    player.texture:SetTexture(nil)
                end
            end
        end
        scheduleUpdateNamePlates()
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

    local layoutDropdownLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    layoutDropdownLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, verticalSpacing)
    layoutDropdownLabel:SetText("Target Icons Layout")

    local layoutDropdown = CreateFrame("Frame", "TargetLayoutDropdown", leftColumn, "UIDropDownMenuTemplate")
    layoutDropdown:SetPoint("TOPLEFT", layoutDropdownLabel, "BOTTOMLEFT", -15, verticalSpacing)
    UIDropDownMenu_SetWidth(layoutDropdown, 150)
    addTooltip(layoutDropdown, "Choose how the target icons are arranged.")

    local function OnLayoutClick(self)
        UIDropDownMenu_SetSelectedID(layoutDropdown, self:GetID())
        Target_Settings.layout = self.value
        scheduleUpdateNamePlates()
        SaveProfileSettings()
    end

    local function InitializeLayoutDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local index = 1
        for k, v in pairs(layoutTypes) do
            info = UIDropDownMenu_CreateInfo()
            info.text = k
            info.value = k
            info.func = OnLayoutClick
            info.checked = (Target_Settings.layout == k)
            UIDropDownMenu_AddButton(info, level)
            if info.checked then
                UIDropDownMenu_SetSelectedID(layoutDropdown, index)
            end
            index = index + 1
        end
    end

    UIDropDownMenu_Initialize(layoutDropdown, InitializeLayoutDropdown)
    lastControlLeft = layoutDropdown

    -- Arena Overlay Settings
    local arenaOverlayTitle = leftColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    arenaOverlayTitle:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, sectionSpacing)
    arenaOverlayTitle:SetText("Arena Overlay Settings")
    lastControlLeft = arenaOverlayTitle

    local overlayCheckbox = CreateFrame("CheckButton", "TargetShowOverlayCheckbox", leftColumn, "UICheckButtonTemplate")
    overlayCheckbox:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, verticalSpacing)
    overlayCheckbox.text = overlayCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlayCheckbox.text:SetPoint("LEFT", overlayCheckbox, "RIGHT", 0, 1)
    overlayCheckbox.text:SetText("Arena Overlay Rating")
    overlayCheckbox:SetChecked(Target_Settings.showOverlay)
    overlayCheckbox:SetScript("OnClick", function(self)
        Target_Settings.showOverlay = self:GetChecked()
        if Target_Settings.showOverlay then
            if TargetOverlayFrame then
                TargetOverlayFrame:Show()
            else
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
        addon.ApplyOverlayAppearanceChanges()
    end)
    addTooltip(overlayCheckbox, "Toggle the arena overlay rating display.")
    lastControlLeft = overlayCheckbox

    local compactOverlayCheckbox = CreateFrame("CheckButton", "TargetCompactOverlayCheckbox", leftColumn, "UICheckButtonTemplate")
    compactOverlayCheckbox:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, verticalSpacing)
    compactOverlayCheckbox.text = compactOverlayCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compactOverlayCheckbox.text:SetPoint("LEFT", compactOverlayCheckbox, "RIGHT", 0, 1)
    compactOverlayCheckbox.text:SetText("Compact Overlay")
    compactOverlayCheckbox:SetChecked(Target_Settings.compactOverlay)
    compactOverlayCheckbox:SetScript("OnClick", function(self)
        Target_Settings.compactOverlay = self:GetChecked()
        if TargetOverlayFrame then
            TargetOverlayFrame:Hide()
            TargetOverlayFrame = nil
            addon.ClearOverlayFrameReference()
            addon.createOverlayFrame()
        end
        SaveProfileSettings()
    end)
    addTooltip(compactOverlayCheckbox, "Use a more compact version of the overlay.")
    lastControlLeft = compactOverlayCheckbox

    local hideOverlayInArenaCheckbox = CreateFrame("CheckButton", "TargetHideOverlayInArenaCheckbox", leftColumn, "UICheckButtonTemplate")
    hideOverlayInArenaCheckbox:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, verticalSpacing)
    hideOverlayInArenaCheckbox.text = hideOverlayInArenaCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hideOverlayInArenaCheckbox.text:SetPoint("LEFT", hideOverlayInArenaCheckbox, "RIGHT", 0, 1)
    hideOverlayInArenaCheckbox.text:SetText("Hide Overlay in Arena")
    hideOverlayInArenaCheckbox:SetChecked(Target_Settings.hideOverlayInArena)
    hideOverlayInArenaCheckbox:SetScript("OnClick", function(self)
        Target_Settings.hideOverlayInArena = self:GetChecked()
        if TargetOverlayFrame then
            local inInstance, instanceType = IsInInstance()
            if Target_Settings.hideOverlayInArena and inInstance and instanceType == "arena" then
                TargetOverlayFrame:Hide()
            elseif Target_Settings.showOverlay then
                TargetOverlayFrame:Show()
            end
        end
        SaveProfileSettings()
    end)
    addTooltip(hideOverlayInArenaCheckbox, "Hide the overlay when entering an arena and show it when leaving.")
    lastControlLeft = hideOverlayInArenaCheckbox

    local glowCheckbox = CreateFrame("CheckButton", "TargetEnableGlowCheckbox", leftColumn, "UICheckButtonTemplate")
    glowCheckbox:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 0, verticalSpacing)
    glowCheckbox.text = glowCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    glowCheckbox.text:SetPoint("LEFT", glowCheckbox, "RIGHT", 0, 1)
    glowCheckbox.text:SetText("Enable Button Glow")
    glowCheckbox:SetChecked(Target_Settings.enableGlow)
    glowCheckbox:SetScript("OnClick", function(self)
        Target_Settings.enableGlow = self:GetChecked()
        addon.UpdateButtonMacros()
        SaveProfileSettings()
    end)
    addTooltip(glowCheckbox, "Toggle the glow effect on overlay buttons.")
    lastControlLeft = glowCheckbox

    local overlayLayoutLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlayLayoutLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, verticalSpacing)
    overlayLayoutLabel:SetText("Arena Overlay Layout")

    local overlayLayoutDropdown = CreateFrame("Frame", "TargetOverlayLayoutDropdown", leftColumn, "UIDropDownMenuTemplate")
    overlayLayoutDropdown:SetPoint("TOPLEFT", overlayLayoutLabel, "BOTTOMLEFT", -15, verticalSpacing)
    UIDropDownMenu_SetWidth(overlayLayoutDropdown, 150)
    addTooltip(overlayLayoutDropdown, "Choose how the arena overlay buttons are arranged.")

    local function OnOverlayLayoutClick(self)
        UIDropDownMenu_SetSelectedID(overlayLayoutDropdown, self:GetID())
        Target_Settings.overlayLayout = self.value
        if TargetOverlayFrame and TargetOverlayFrame:IsShown() then
            addon.arrangeArenaButtons()
        end
        SaveProfileSettings()
    end

    local function InitializeOverlayLayoutDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local index = 1
        for k, v in pairs(layoutTypes) do
            info = UIDropDownMenu_CreateInfo()
            info.text = k
            info.value = k
            info.func = OnOverlayLayoutClick
            info.checked = (Target_Settings.overlayLayout == k)
            UIDropDownMenu_AddButton(info, level)
            if info.checked then
                UIDropDownMenu_SetSelectedID(overlayLayoutDropdown, index)
            end
            index = index + 1
        end
    end

    UIDropDownMenu_Initialize(overlayLayoutDropdown, InitializeOverlayLayoutDropdown)
    lastControlLeft = overlayLayoutDropdown

    local borderStyleLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    borderStyleLabel:SetPoint("TOPLEFT", lastControlLeft, "BOTTOMLEFT", 15, verticalSpacing)
    borderStyleLabel:SetText("Overlay Border Style")

    local borderStyleDropdown = CreateFrame("Frame", "TargetOverlayBorderStyleDropdown", leftColumn, "UIDropDownMenuTemplate")
    borderStyleDropdown:SetPoint("TOPLEFT", borderStyleLabel, "BOTTOMLEFT", -15, verticalSpacing)
    UIDropDownMenu_SetWidth(borderStyleDropdown, 150)
    addTooltip(borderStyleDropdown, "Choose the border style for the arena overlay.")

    local function OnBorderStyleClick(self)
        UIDropDownMenu_SetSelectedID(borderStyleDropdown, self:GetID())
        Target_Settings.overlayBorderStyle = self.value
        SaveProfileSettings()
        if TargetOverlayFrame then
            if TargetOverlayFrame:IsShown() then
                local point, relativeTo, relativePoint, x, y = TargetOverlayFrame:GetPoint()
                Target_Settings.overlayPosX = x
                Target_Settings.overlayPosY = y
                Target_Settings.overlayWidth = TargetOverlayFrame:GetWidth()
                Target_Settings.overlayHeight = TargetOverlayFrame:GetHeight()
            end
            SaveProfileSettings()
            TargetOverlayFrame:Hide()
            TargetOverlayFrame = nil
            addon.ClearOverlayFrameReference()
            addon.createOverlayFrame()
        end
    end

    local function InitializeBorderStyleDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local index = 1
        for styleName, stylePath in pairs(borderStyles) do
            info = UIDropDownMenu_CreateInfo()
            info.text = styleName
            info.value = stylePath
            info.func = OnBorderStyleClick
            info.checked = (Target_Settings.overlayBorderStyle == stylePath)
            UIDropDownMenu_AddButton(info, level)
            if info.checked then
                UIDropDownMenu_SetSelectedID(borderStyleDropdown, index)
            end
            index = index + 1
        end
    end

    UIDropDownMenu_Initialize(borderStyleDropdown, InitializeBorderStyleDropdown)
    lastControlLeft = borderStyleDropdown

    -- Right Column: Game Mode Toggles
    local toggleOptionsTitle = rightColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    toggleOptionsTitle:SetPoint("TOPLEFT", 0, 0)
    toggleOptionsTitle:SetText("Game Mode Toggles")

    local lastControlRight = toggleOptionsTitle
    local checkboxData = {
        { label = "Enable in Open World",   setting = "enableInOpenWorld" },
        { label = "Enable in Arena",        setting = "enableInArena" },
        { label = "Enable in Solo Shuffle", setting = "enableInSoloShuffle" },
        { label = "Enable in Battleground", setting = "enableInBattleground" },
        { label = "Enable in Raid",         setting = "enableInRaid" },
        { label = "Enable in Dungeons",     setting = "enableInDungeon" },
        { label = "Enable in Delves",       setting = "enableInDelves" },
    }

    for i, data in ipairs(checkboxData) do
        local checkbox = CreateFrame("CheckButton", "TargetCheckbox" .. i, rightColumn, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", lastControlRight, "BOTTOMLEFT", 0, verticalSpacing)
        checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 0, 1)
        checkbox.text:SetText(data.label)
        checkbox:SetChecked(Target_Settings[data.setting])
        checkbox:SetScript("OnClick", function(self)
            Target_Settings[data.setting] = self:GetChecked()
            scheduleUpdateNamePlates()
            SaveProfileSettings()
        end)
        addTooltip(checkbox, "Enable or disable the addon in " .. data.label .. ".")
        lastControlRight = checkbox
    end

    -- Position & Sizing
    local positionTitle = rightColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    positionTitle:SetPoint("TOPLEFT", lastControlRight, "BOTTOMLEFT", 0, sectionSpacing - 5)
    positionTitle:SetText("Position & Sizing")

    local xSliderLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xSliderLabel:SetPoint("TOPLEFT", positionTitle, "BOTTOMLEFT", 0, verticalSpacing)
    xSliderLabel:SetText("X Offset")

    local xSlider = CreateFrame("Slider", "TargetXSlider", rightColumn, "OptionsSliderTemplate")
    xSlider:SetPoint("TOPLEFT", xSliderLabel, "BOTTOMLEFT", 0, verticalSpacing)
    xSlider:SetMinMaxValues(-200, 200)
    xSlider:SetValue(Target_Settings.xValue)
    xSlider:SetValueStep(1)
    xSlider:SetObeyStepOnDrag(true)
    xSlider:SetWidth(200)
    addTooltip(xSlider, "Adjust the horizontal position of the target icons.")

    local xSliderValue = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    xSliderValue:SetPoint("LEFT", xSlider, "RIGHT", 10, 0)
    xSliderValue:SetText(floor(Target_Settings.xValue))

    xSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        xSliderValue:SetText(value)
        Target_Settings.xValue = value
        scheduleUpdateNamePlates()
        SaveProfileSettings()
    end)

    local ySliderLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ySliderLabel:SetPoint("TOPLEFT", xSlider, "BOTTOMLEFT", 0, sectionSpacing)
    ySliderLabel:SetText("Y Offset")

    local ySlider = CreateFrame("Slider", "TargetYSlider", rightColumn, "OptionsSliderTemplate")
    ySlider:SetPoint("TOPLEFT", ySliderLabel, "BOTTOMLEFT", 0, verticalSpacing)
    ySlider:SetMinMaxValues(-200, 200)
    ySlider:SetValue(Target_Settings.yValue)
    ySlider:SetValueStep(1)
    ySlider:SetObeyStepOnDrag(true)
    ySlider:SetWidth(200)
    addTooltip(ySlider, "Adjust the vertical position of the target icons.")

    local ySliderValue = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ySliderValue:SetPoint("LEFT", ySlider, "RIGHT", 10, 0)
    ySliderValue:SetText(floor(Target_Settings.yValue))

    ySlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        ySliderValue:SetText(value)
        Target_Settings.yValue = value
        scheduleUpdateNamePlates()
        SaveProfileSettings()
    end)

    local sizeSliderLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeSliderLabel:SetPoint("TOPLEFT", ySlider, "BOTTOMLEFT", 0, sectionSpacing)
    sizeSliderLabel:SetText("Icon Size")

    local sizeSlider = CreateFrame("Slider", "TargetSizeSlider", rightColumn, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeSliderLabel, "BOTTOMLEFT", 0, verticalSpacing)
    sizeSlider:SetMinMaxValues(10, 100)
    sizeSlider:SetValue(Target_Settings.iconSize)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetWidth(200)
    addTooltip(sizeSlider, "Adjust the size of the target icons.")

    local sizeSliderValue = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeSliderValue:SetPoint("LEFT", sizeSlider, "RIGHT", 10, 0)
    sizeSliderValue:SetText(floor(Target_Settings.iconSize))

    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        sizeSliderValue:SetText(value)
        Target_Settings.iconSize = value
        for _, player in pairs(players) do
            if player.texture then
                player.texture:SetSize(value, value)
            end
        end
        scheduleUpdateNamePlates()
        SaveProfileSettings()
    end)

    local opacitySliderLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    opacitySliderLabel:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, sectionSpacing)
    opacitySliderLabel:SetText("Icon Opacity")

    local opacitySlider = CreateFrame("Slider", "TargetOpacitySlider", rightColumn, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", opacitySliderLabel, "BOTTOMLEFT", 0, verticalSpacing)
    opacitySlider:SetMinMaxValues(0.1, 1.0)
    opacitySlider:SetValue(Target_Settings.iconOpacity)
    opacitySlider:SetValueStep(0.1)
    opacitySlider:SetObeyStepOnDrag(true)
    opacitySlider:SetWidth(200)
    addTooltip(opacitySlider, "Adjust the transparency of the target icons.")

    local opacitySliderValue = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    opacitySliderValue:SetPoint("LEFT", opacitySlider, "RIGHT", 10, 0)
    opacitySliderValue:SetText(string.format("%.1f", Target_Settings.iconOpacity))

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        value = tonumber(string.format("%.1f", value))
        opacitySliderValue:SetText(value)
        Target_Settings.iconOpacity = value
        for _, player in pairs(players) do
            if player.texture then
                player.texture:SetAlpha(value)
            end
        end
        scheduleUpdateNamePlates()
        SaveProfileSettings()
    end)

    local scaleSliderLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleSliderLabel:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, sectionSpacing)
    scaleSliderLabel:SetText("Overlay Scale")

    local scaleSlider = CreateFrame("Slider", "TargetScaleSlider", rightColumn, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleSliderLabel, "BOTTOMLEFT", 0, verticalSpacing)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValue(Target_Settings.overlayScale)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetWidth(200)
    addTooltip(scaleSlider, "Adjust the overall scale of the arena overlay.")

    local scaleSliderValue = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleSliderValue:SetPoint("LEFT", scaleSlider, "RIGHT", 10, 0)
    scaleSliderValue:SetText(string.format("%.1f", Target_Settings.overlayScale))

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = tonumber(string.format("%.1f", value))
        scaleSliderValue:SetText(value)
        Target_Settings.overlayScale = value
        if TargetOverlayFrame then
            TargetOverlayFrame:SetScale(value)
        end
        SaveProfileSettings()
    end)

    local buttonContainer = CreateFrame("Frame", nil, optionsFrame)
    buttonContainer:SetSize(1, 1)
    buttonContainer:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 20)

    local reloadButton = CreateFrame("Button", "TargetReloadButton", buttonContainer, "UIPanelButtonTemplate")
    reloadButton:SetSize(120, 25)
    reloadButton:SetText("Reload UI")
    reloadButton:SetPoint("LEFT", buttonContainer, "CENTER", -65, 0)
    reloadButton:SetScript("OnClick", function() ReloadUI() end)
    addTooltip(reloadButton, "Reload the UI to apply changes.")

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
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        editBox:SetScript("OnTextChanged", function(self)
            self:SetText("https://paypal.me/Drabio?country.x=US&locale.x=en_US")
            self:HighlightText()
        end)
        editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        editBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        editBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
        editBox:EnableMouse(true)
        editBox:SetFocus()

        local closeButton = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
    end)
    addTooltip(donateButton, "Support the addon developer by donating.")

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "ClassTarget")
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(optionsFrame)
    end

    optionsFrame:SetScript("OnShow", function(self)
        self:Show()
        addon.ApplyOverlayAppearanceChanges()
    end)
    optionsFrame:SetScript("OnHide", function(self) self:Hide() end)
end

local function OnEvent(self, event, ...)
    if event == "GROUP_ROSTER_UPDATE" then
        initializePlayers()
        clearNamePlates()
        scheduleUpdateNamePlates()
        startTicker()
    elseif event == "PLAYER_ENTERING_WORLD" then
        initializePlayers()
        clearNamePlates()
        scheduleUpdateNamePlates()
        startTicker()
        -- Handle overlay visibility based on zone
        if Target_Settings.showOverlay and TargetOverlayFrame then
            local inInstance, instanceType = IsInInstance()
            if Target_Settings.hideOverlayInArena and inInstance and instanceType == "arena" then
                TargetOverlayFrame:Hide()
            else
                TargetOverlayFrame:Show()
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        targetNameCache["playertarget"] = nil
        clearNamePlates()
        scheduleUpdateNamePlates()
    elseif event == "UNIT_TARGET" then
        local unit = ...
        if unit and players[unit] then
            -- This teammate just changed target; drop the cached name for their
            -- target token so we don't bridge to a target they no longer have.
            targetNameCache[unit .. "target"] = nil
            clearNamePlates()
            scheduleUpdateNamePlates()
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        scheduleUpdateNamePlates()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        clearNamePlates()
        scheduleUpdateNamePlates()
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

        -- Ensure overlayScale and hideOverlayInArena exist in all profiles
        for profileName, profile in pairs(Target_Profiles) do
            if profile.overlayScale == nil then
                profile.overlayScale = 1.0
            end
            if profile.hideOverlayInArena == nil then
                profile.hideOverlayInArena = false
            end
        end
        if Target_Settings.overlayScale == nil then
            Target_Settings.overlayScale = 1.0
        end
        if Target_Settings.hideOverlayInArena == nil then
            Target_Settings.hideOverlayInArena = false
        end

        profiles = Target_Profiles
        currentProfile = Target_CurrentProfile
        Target_Settings = profiles[currentProfile]

        initializeUI()
    elseif event == "PLAYER_LOGIN" then
        if not Target_Settings then
            Target_Settings = CopyTable(defaultSettings)
        end
        initializeUI()
        scheduleUpdateNamePlates()
        startTicker()
    end
end

frame:SetScript("OnEvent", OnEvent)

SLASH_TARGETOPTIONS1 = "/targetoptions"
SlashCmdList["TARGETOPTIONS"] = function()
    if not TargetOptionsFrame:IsShown() then
        TargetOptionsFrame:Show()
    else
        TargetOptionsFrame:Hide()
    end
end

DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffClassTarget|r v8.9 loaded. Type |cffffd100/targetlog|r to start logging.")

SLASH_TARGETLOG1 = "/targetlog"
SlashCmdList["TARGETLOG"] = function(arg)
    local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffClassTarget|r " .. msg) end
    arg = (arg or ""):lower():gsub("%s+", "")
    if arg == "clear" then
        Target_DebugLog = {}
        p("debug log cleared.")
        return
    end
    debugLoggingEnabled = not debugLoggingEnabled
    if debugLoggingEnabled then
        if type(Target_DebugLog) ~= "table" then Target_DebugLog = {} end
        debugLog("=== logging started ===")
        p("|cff44ff44logging ON|r. Just play normally, then /reload. The results")
        p("are saved in: WTF\\Account\\<name>\\SavedVariables\\Target.lua")
        p("Use |cffffd100/targetlog|r again to stop, or |cffffd100/targetlog clear|r to wipe it.")
    else
        debugLog("=== logging stopped ===")
        p("|cffff4444logging OFF|r. Type |cffffd100/reload|r to flush the file to disk.")
    end
end

SLASH_TARGETDEBUG1 = "/targetdebug"
SlashCmdList["TARGETDEBUG"] = function()
    local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffClassTarget|r " .. msg) end
    -- pcall everything: in rated arena some unit queries can be "secret values".
    local function exists(u) local ok, r = pcall(UnitExists, u); return ok and r and true or false end
    local function uname(u) local ok, r = pcall(UnitName, u); return ok and r or "?" end

    p(("inRaid=%s inGroup=%s grp=%d subgrp=%d enabled=%s"):format(
        tostring(IsInRaid()), tostring(IsInGroup()),
        GetNumGroupMembers() or 0, GetNumSubgroupMembers() or 0, tostring(isAddonEnabled())))

    -- Which group-member token family yields a working "<unit>target"? This is the
    -- crux: the addon picks party vs raid via IsInRaid(); we need to see which one
    -- actually resolves teammates' targets in this instance.
    for _, fam in ipairs({ {"party", 4}, {"raid", 5}, {"arena", 3} }) do
        local prefix, count = fam[1], fam[2]
        for i = 1, count do
            local u = prefix .. i
            if exists(u) then
                local t = u .. "target"
                p(("  %s=%s | %s exists=%s name=%s"):format(
                    u, uname(u), t, tostring(exists(t)), exists(t) and uname(t) or "-"))
            end
        end
    end

    local cnt = 0
    for i = 1, 40 do
        local u = "nameplate" .. i
        if exists(u) then cnt = cnt + 1; p(("  %s = %s"):format(u, uname(u))) end
    end
    p(("nameplates: %d"):format(cnt))

    local n = 0
    for _, player in pairs(players) do
        n = n + 1
        local t = player.targetId
        local plate = getNamePlateForTarget(t)
        p(("tracked %s class=%s | %s exists=%s name=%s plate=%s"):format(
            player.unitId, player.classToken ~= "" and player.classToken or "(none)",
            t, tostring(exists(t)), exists(t) and uname(t) or "-", plate and "YES" or "no"))
    end
    if n == 0 then p("no players tracked") end
end

_G[addonName] = addon
