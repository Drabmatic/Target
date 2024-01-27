-- TargetSettings.lua

local TargetSettings = {
    xOffset = 0,
    yOffset = 0,
}

function TargetSettings:GetXOffset()
    return self.xOffset
end

function TargetSettings:SetXOffset(value)
    self.xOffset = value
end

function TargetSettings:GetYOffset()
    return self.yOffset
end

function TargetSettings:SetYOffset(value)
    self.yOffset = value
end

return TargetSettings
