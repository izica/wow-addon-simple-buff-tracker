-- step_slider.lua -- a slider over a list of values that are not evenly spaced
-- (1 copper, 5 copper, ... 10 gold), with the chosen one as text on its right.
-- Arrows on both sides, like the game's settings sliders, and the mouse wheel
-- over it move it one step. The arrows stand outside of the slider frame.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local HEIGHT = 19
local VALUE_GAP = 8
-- the arrow buttons, as in MinimalSliderWithSteppersTemplate (Blizzard_SharedXML/Shared/Slider)
local BACK_ATLAS = "Minimal_SliderBar_Button_Left"
local FORWARD_ATLAS = "Minimal_SliderBar_Button_Right"
local BACK_WIDTH = 11
local BACK_HEIGHT = 19
local FORWARD_WIDTH = 9
local FORWARD_HEIGHT = 18
local STEPPER_GAP = 4
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
    -- one step to either side, from the arrows and the wheel
    local function Step(delta)
        Choose(stepIndex + delta)
        isSetting = true
        slider:SetValue(stepIndex)
        isSetting = false
    end

    -- the arrows of the game's settings sliders (MinimalSliderWithSteppersTemplate)
    local function AddStepper(atlas, width, height, point, relativePoint, offset, delta)
        local button = CreateFrame("Button", nil, slider)
        button:SetSize(width, height)
        button:SetPoint(point, slider, relativePoint, offset, 0)
        local texture = button:CreateTexture(nil, "BACKGROUND")
        texture:SetAtlas(atlas, true)
        texture:SetPoint("CENTER")
        button:SetScript("OnClick", function()
            Step(delta)
        end)
        return button
    end
    local backButton = AddStepper(BACK_ATLAS, BACK_WIDTH, BACK_HEIGHT, "RIGHT", "LEFT", -STEPPER_GAP, -1)
    local forwardButton = AddStepper(FORWARD_ATLAS, FORWARD_WIDTH, FORWARD_HEIGHT, "LEFT", "RIGHT", STEPPER_GAP, 1)
    slider.backButton = backButton
    slider.forwardButton = forwardButton
    valueText:ClearAllPoints()
    valueText:SetPoint("LEFT", forwardButton, "RIGHT", VALUE_GAP, 0)

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
