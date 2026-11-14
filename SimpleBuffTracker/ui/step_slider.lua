-- step_slider.lua -- a slider over a list of values that are not evenly spaced
-- (1 copper, 5 copper, ... 10 gold), with the chosen one as text on its right.
-- The mouse wheel over it moves it one step.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local HEIGHT = 19
local VALUE_GAP = 6
local TOOLTIP_TEXT_COLOR = { 1, 1, 1 }

local function ClosestStep(steps, value)
    local closest = 1
    for index, stepValue in ipairs(steps) do
        if math.abs(stepValue - value) < math.abs(steps[closest] - value) then
            closest = index
        end
    end
    return closest
end

-- options: steps -- the values, in order; value; width; valueWidth;
-- format(value) -> text; onChange(value);
-- title and tooltip -- shown on hover (optional).
-- slider:SetValueOf(value), slider:GetValueOf().
function ns.UI.StepSlider(parent, options)
    local steps = options.steps
    local slider = CreateFrame("Slider", nil, parent, "MinimalSliderTemplate")
    slider.isStepSlider = true
    slider:SetSize(options.width, HEIGHT)
    slider:SetMinMaxValues(1, #steps)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", VALUE_GAP, 0)
    valueText:SetWidth(options.valueWidth)
    valueText:SetJustifyH("LEFT")
    valueText:SetWordWrap(false)
    slider.valueText = valueText

    local stepIndex = ClosestStep(steps, options.value or steps[1])
    local isSetting = false

    local function Show(index)
        stepIndex = index
        valueText:SetText(options.format(steps[index]))
    end

    function slider:SetValueOf(value)
        isSetting = true
        Show(ClosestStep(steps, value))
        self:SetValue(stepIndex)
        isSetting = false
    end

    function slider:GetValueOf()
        return steps[stepIndex]
    end

    -- index -- a step number, from the slider or the wheel
    local function Choose(index)
        index = math.max(1, math.min(#steps, math.floor(index + 0.5)))
        if index == stepIndex then return end

        Show(index)
        options.onChange(steps[index])
    end

    slider:SetScript("OnValueChanged", function(_, index)
        if not isSetting then
            Choose(index)
        end
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        Choose(stepIndex + delta)
        isSetting = true
        self:SetValue(stepIndex)
        isSetting = false
    end)

    if options.tooltip then
        slider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(options.title or "")
            GameTooltip:AddLine(options.tooltip,
                TOOLTIP_TEXT_COLOR[1], TOOLTIP_TEXT_COLOR[2], TOOLTIP_TEXT_COLOR[3], true)
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    slider:SetValueOf(options.value or steps[1])
    return slider
end
