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
--
-- Rows can be put into groups (form:Group()): a hidden group takes no room --
-- after showing or hiding groups, form:Layout() stacks the shown rows again,
-- with no holes where the hidden ones were.

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
local NOTE_GAP = 2                -- from the drawn bottom of a control to its note
local NOTE_LINE_HEIGHT = 12
local NOTE_COLOR = { 0.6, 0.6, 0.6 }
local CHECKBOX_HEIGHT = 26
local CHECKBOX_SHIFT = -4         -- the checkbox art has an empty edge on the left

-- options: padding -- from the frame edges to the drawn edges of the controls;
-- rightInset -- room kept on the right (default: padding);
-- width -- the drawn width of every control; nil -- up to rightInset;
-- sliderWidth -- the drawn width of the sliders with their value text, width when nil.
-- form:Label(text), form:Field(control), form:Slider(slider, valueWidth),
-- form:Checkbox(checkbox), form:CheckboxRow(checkboxes, columnWidth),
-- form:Text(fontString, height), form:Note(text, lines),
-- form:Space(pixels); form:Group() -> group, group:SetShown(isShown), form:Layout().
function ns.UI.FormLayout(frame, options)
    local padding = options.padding
    local rightInset = options.rightInset or padding
    local form = { top = -padding }
    local steps = {}           -- { place = function(), group = group or nil }, in order
    local currentGroup = nil   -- the group new rows join

    -- remember a row and place it now; Layout places all the shown rows again
    local function AddStep(place)
        table.insert(steps, { place = place, group = currentGroup })
        place()
    end

    -- place a control by its drawn box: art -- how far it draws past its frame
    -- width -- the drawn width of this control, options.width when nil
    local function Place(control, height, art, width)
        width = width or options.width
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + art.left, form.top - art.top)
        if width then
            control:SetWidth(width - art.left - art.right)
        else
            control:SetPoint("RIGHT", frame, "RIGHT", -(rightInset + art.right), 0)
        end
        control:SetHeight(height)
        form.top = form.top - art.top - height - art.bottom - ROW_GAP
    end

    local function PlaceText(fontString, height)
        fontString:ClearAllPoints()
        fontString:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, form.top)
        fontString:SetPoint("RIGHT", frame, "RIGHT", -rightInset, 0)
        fontString:SetJustifyH("LEFT")
        form.top = form.top - height
    end

    -- the rows added after this call belong to the returned group, until the next Group
    function form:Group()
        local group = { isShown = true }
        function group:SetShown(isShown)
            self.isShown = isShown
        end
        currentGroup = group
        return group
    end

    -- stack the rows of the shown groups from the top again
    function form:Layout()
        self.top = -padding
        for _, step in ipairs(steps) do
            local isShown = step.group == nil or step.group.isShown
            if isShown then
                step.place()
            end
        end
    end

    function form:Label(text)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText(text)
        AddStep(function()
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, form.top)
            form.top = form.top - LABEL_HEIGHT - LABEL_GAP
        end)
        return label
    end

    -- a dropdown (ui/select.lua) or an input (ui/input.lua)
    function form:Field(control)
        AddStep(function()
            Place(control, FIELD_HEIGHT, {
                left = FIELD_ART_LEFT,
                right = FIELD_ART_RIGHT,
                top = FIELD_ART_TOP,
                bottom = FIELD_ART_BOTTOM,
            })
        end)
    end

    -- a slider with arrows (ui/step_slider.lua); its value text right of it
    function form:Slider(slider, valueWidth)
        AddStep(function()
            Place(slider, SLIDER_HEIGHT, {
                left = SLIDER_STEPPER_SPACE,
                right = SLIDER_STEPPER_SPACE + SLIDER_VALUE_GAP + valueWidth,
                top = 2,
                bottom = 2,
            }, options.sliderWidth)
        end)
    end

    function form:Checkbox(checkbox)
        AddStep(function()
            checkbox:ClearAllPoints()
            checkbox:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + CHECKBOX_SHIFT, form.top)
            form.top = form.top - CHECKBOX_HEIGHT
        end)
    end

    -- checkboxes side by side in one row, each in a column of columnWidth
    function form:CheckboxRow(checkboxes, columnWidth)
        AddStep(function()
            for index, checkbox in ipairs(checkboxes) do
                checkbox:ClearAllPoints()
                local x = padding + CHECKBOX_SHIFT + (index - 1) * columnWidth
                checkbox:SetPoint("TOPLEFT", frame, "TOPLEFT", x, form.top)
            end
            form.top = form.top - CHECKBOX_HEIGHT
        end)
    end

    -- a text across the form, height -- the room it takes
    function form:Text(fontString, height)
        AddStep(function()
            PlaceText(fontString, height)
        end)
    end

    -- A small grey note right under the control placed last (what to type or
    -- drop there); lines -- how many lines of room it takes. Returns the text.
    function form:Note(text, lines)
        local note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        note:SetTextColor(NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3])
        note:SetText(text)
        note:SetJustifyV("TOP")
        local height = NOTE_LINE_HEIGHT * (lines or 1)
        note:SetHeight(height)
        AddStep(function()
            form.top = form.top + ROW_GAP - NOTE_GAP
            PlaceText(note, height)
            form.top = form.top - ROW_GAP
        end)
        return note
    end

    function form:Space(pixels)
        AddStep(function()
            form.top = form.top - pixels
        end)
    end

    return form
end
