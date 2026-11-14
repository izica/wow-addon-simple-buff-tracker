-- form_layout.lua -- lays out a form top to bottom: a label, the control under
-- it, the next label... so that the drawn edges of every control line up with
-- the labels on the left and with each other on the right.
--
-- The game's controls draw past their frames: the text holder of the dropdown
-- (WowStyle1DropdownTemplate, Blizzard_Menu/Mainline/MenuTemplates.xml) sticks
-- out 8 pixels left and right, 7 up and 9 down, and our inputs use the same art
-- (ui/input.lua); the slider has its arrow buttons outside of the bar
-- (MinimalSliderWithSteppersTemplate: 11 pixels wide, 4 from the bar). Placed
-- at the same x, such controls stood like a staircase. Here every control is
-- placed by its drawn edge, not by its frame.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local LABEL_HEIGHT = 14
local LABEL_GAP = 4           -- from a label down to the drawn top of its control
local ROW_GAP = 8             -- from the drawn bottom of a control to the next label
local FIELD_HEIGHT = 25       -- dropdowns and inputs: the same text holder art
local FIELD_ART_LEFT = 8
local FIELD_ART_RIGHT = 8
local FIELD_ART_TOP = 7
local FIELD_ART_BOTTOM = 9
local SLIDER_HEIGHT = 19
local SLIDER_STEPPER_SPACE = 15   -- the arrow button (11) and its gap (4), each side
local SLIDER_VALUE_GAP = 8        -- from the right arrow to the value text
local CHECKBOX_HEIGHT = 26
local CHECKBOX_SHIFT = -4         -- the checkbox art has an empty edge on the left

-- options: padding -- from the frame edges to the drawn edges of the controls;
-- rightInset -- room kept on the right (default: padding);
-- width -- the drawn width of every control; nil -- up to rightInset.
-- form:Label(text), form:Field(control), form:Slider(slider, valueWidth),
-- form:Checkbox(checkbox), form:Text(fontString, height), form:Space(pixels).
function ns.UI.FormLayout(frame, options)
    local padding = options.padding
    local rightInset = options.rightInset or padding
    local form = { top = -padding }

    -- place a control by its drawn box: art -- how far it draws past its frame
    local function Place(control, height, art)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + art.left, form.top - art.top)
        if options.width then
            control:SetWidth(options.width - art.left - art.right)
        else
            control:SetPoint("RIGHT", frame, "RIGHT", -(rightInset + art.right), 0)
        end
        control:SetHeight(height)
        form.top = form.top - art.top - height - art.bottom - ROW_GAP
    end

    function form:Label(text)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", padding, self.top)
        label:SetText(text)
        self.top = self.top - LABEL_HEIGHT - LABEL_GAP
        return label
    end

    -- a dropdown (ui/select.lua) or an input (ui/input.lua)
    function form:Field(control)
        Place(control, FIELD_HEIGHT, {
            left = FIELD_ART_LEFT,
            right = FIELD_ART_RIGHT,
            top = FIELD_ART_TOP,
            bottom = FIELD_ART_BOTTOM,
        })
    end

    -- a slider with arrows (ui/step_slider.lua); its value text right of it
    function form:Slider(slider, valueWidth)
        Place(slider, SLIDER_HEIGHT, {
            left = SLIDER_STEPPER_SPACE,
            right = SLIDER_STEPPER_SPACE + SLIDER_VALUE_GAP + valueWidth,
            top = 2,
            bottom = 2,
        })
    end

    function form:Checkbox(checkbox)
        checkbox:ClearAllPoints()
        checkbox:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + CHECKBOX_SHIFT, self.top)
        self.top = self.top - CHECKBOX_HEIGHT
    end

    -- a text across the form, height -- the room it takes
    function form:Text(fontString, height)
        fontString:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, self.top)
        fontString:SetPoint("RIGHT", frame, "RIGHT", -rightInset, 0)
        fontString:SetJustifyH("LEFT")
        self.top = self.top - height
    end

    function form:Space(pixels)
        self.top = self.top - pixels
    end

    return form
end
