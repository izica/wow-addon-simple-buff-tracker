-- panel_settings.lua -- the Panel tab of the window: lock, what the panel shows
-- and how early, the glow of a missing buff, which way the icons grow, their look, size, line and spacing,
-- the minimap button. Applied at once.
-- Laid out by ui/form_layout.lua: one drawn width for every control.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local DISPLAY_MODE = ns.Constants.DISPLAY_MODE
local GROW_DIRECTION = ns.Constants.GROW_DIRECTION
local GROW_ORDER = { GROW_DIRECTION.RIGHT, GROW_DIRECTION.LEFT, GROW_DIRECTION.DOWN, GROW_DIRECTION.UP }
local ICON_TEMPLATE = ns.Constants.ICON_TEMPLATE
local TEMPLATE_ORDER = { ICON_TEMPLATE.ACTION_BAR, ICON_TEMPLATE.BORDERLESS, ICON_TEMPLATE.SQUARE }
local GLOW_EFFECT = ns.Constants.GLOW_EFFECT
local GLOW_ORDER = ns.Constants.GLOW_ORDER

local PanelSettings = {}
ns.Components.PanelSettings = PanelSettings

local PADDING = 20
local CONTROL_WIDTH = 320          -- the drawn width of the dropdown and of the sliders with their arrows
local SLIDER_VALUE_WIDTH = 90
local CHECKBOXES_GAP = 4
local WARN_STEPS = { 0, 15, 30, 60, 120, 180, 300, 600, 900, 1200, 1800 }

local function Range(minimum, maximum, step)
    local steps = {}
    for value = minimum, maximum, step do
        table.insert(steps, value)
    end
    return steps
end

-- options: onChanged() -- after any change (the panel and the buff list redraw)
function PanelSettings.Create(parent, options)
    local frame = ns.UI.InsetPanel(parent, {})
    local refreshers = {}   -- functions that put the saved values into the controls

    local function Settings()
        return ns.db.settings
    end

    -- one column, in the order a player looks for: lock first, then what the
    -- panel shows, then how it looks; the minimap button last
    local form = ns.UI.FormLayout(frame, {
        padding = PADDING,
        width = CONTROL_WIDTH,
        sliderWidth = CONTROL_WIDTH + SLIDER_VALUE_WIDTH + 8,
    })

    local function AddCheckbox(textKey, tooltipKey, read, write)
        local checkbox = ns.UI.Checkbox(frame, {
            text = Text(textKey),
            tooltip = tooltipKey and Text(tooltipKey),
            checked = read(),
            onChange = function(isChecked)
                write(isChecked)
                options.onChanged()
            end,
        })
        form:Checkbox(checkbox)
        table.insert(refreshers, function()
            checkbox:SetChecked(read())
        end)
    end

    -- choices() -> { { value, text } }; field -- the key in ns.db.settings;
    -- isLayout -- the change lays the secure icons out anew: not in combat
    local function AddSelect(textKey, choices, field, isLayout)
        form:Label(Text(textKey))
        local select = ns.UI.Select(frame, {
            width = CONTROL_WIDTH,
            choices = choices,
            selected = function()
                return Settings()[field]
            end,
            onChange = function(value)
                if isLayout and InCombatLockdown() then
                    ns.Utilities.Print(Text("messages.in_combat"))
                    return
                end
                Settings()[field] = value
                options.onChanged()
            end,
        })
        form:Field(select)
        table.insert(refreshers, function()
            select:Refresh()
        end)
    end

    local function AddSlider(textKey, field, steps, format)
        form:Label(Text(textKey))
        local slider = ns.UI.StepSlider(frame, {
            steps = steps,
            value = Settings()[field],
            width = 100,   -- the form sets it
            valueWidth = SLIDER_VALUE_WIDTH,
            format = format or tostring,
            onChange = function(value)
                Settings()[field] = value
                options.onChanged()
            end,
        })
        form:Slider(slider, SLIDER_VALUE_WIDTH)
        table.insert(refreshers, function()
            slider:SetValueOf(Settings()[field])
        end)
    end

    AddCheckbox("settings.locked", "settings.locked_hint", function()
        return Settings().locked
    end, function(isChecked)
        -- the panel holds secure buttons: it can not move in combat
        if InCombatLockdown() then
            ns.Utilities.Print(Text("messages.in_combat"))
            return
        end
        Settings().locked = isChecked
    end)
    form:Space(CHECKBOXES_GAP)

    -- what the panel shows
    AddSelect("settings.mode", function()
        return {
            { value = DISPLAY_MODE.ALL, text = Text("modes." .. DISPLAY_MODE.ALL) },
            { value = DISPLAY_MODE.MISSING, text = Text("modes." .. DISPLAY_MODE.MISSING) },
        }
    end, "mode", false)
    AddSlider("settings.warn_seconds", "warnSeconds", WARN_STEPS, ns.Utilities.FormatSeconds)
    -- how a missing buff draws the eye: a glow around its icon
    AddSelect("settings.missing_glow", function()
        local choices = {}
        for _, effect in ipairs(GLOW_ORDER) do
            table.insert(choices, { value = effect, text = Text("glow." .. effect) })
        end
        return choices
    end, "missingGlow", false)

    -- how it looks: which way the icons go (the panel stays held by the corner
    -- they start from), their look, size, line and spacing
    AddSelect("settings.grow", function()
        local choices = {}
        for _, direction in ipairs(GROW_ORDER) do
            table.insert(choices, { value = direction, text = Text("grow." .. direction) })
        end
        return choices
    end, "growDirection", true)
    AddSelect("settings.icon_template", function()
        local choices = {}
        for _, template in ipairs(TEMPLATE_ORDER) do
            table.insert(choices, { value = template, text = Text("icon_templates." .. template) })
        end
        return choices
    end, "iconTemplate", true)
    AddSlider("settings.icon_size", "iconSize", Range(ns.Config.MIN_ICON_SIZE, ns.Config.MAX_ICON_SIZE, 1))
    AddSlider("settings.icons_per_row", "iconsPerRow", Range(1, ns.Config.MAX_ICONS_PER_ROW, 1))
    AddSlider("settings.icon_spacing", "iconSpacing", Range(0, 20, 1))
    form:Space(CHECKBOXES_GAP)

    AddCheckbox("settings.minimap", nil, function()
        return not Settings().minimap.hide
    end, function(isChecked)
        ns.Components.MinimapButton.SetHidden(not isChecked)
    end)

    frame.panelFormHeight = PADDING - form.top   -- for the tests: the form fits in the window

    function frame:Refresh()
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end

    return frame
end
