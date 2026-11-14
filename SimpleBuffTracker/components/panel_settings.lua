-- panel_settings.lua -- the Panel tab of the window: what the panel shows, the
-- size of its icons, how many in a row, the space between them, the warning
-- time, unlock to drag, the minimap button. Applied at once.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local DISPLAY_MODE = ns.Constants.DISPLAY_MODE

local PanelSettings = {}
ns.Components.PanelSettings = PanelSettings

local PADDING = 20
local LABEL_HEIGHT = 18
local ROW_GAP = 16
local SELECT_WIDTH = 260
local SELECT_HEIGHT = 26
local SLIDER_WIDTH = 260
local SLIDER_HEIGHT = 22
local SLIDER_VALUE_WIDTH = 80
local CHECKBOX_HEIGHT = 26
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
    local nextTop = -PADDING
    local refreshers = {}   -- functions that put the saved values into the controls

    local function Settings()
        return ns.db.settings
    end

    local function AddLabel(textKey)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", PADDING, nextTop)
        label:SetText(Text(textKey))
        nextTop = nextTop - LABEL_HEIGHT
    end

    AddLabel("settings.mode")
    local modeSelect = ns.UI.Select(frame, {
        width = SELECT_WIDTH,
        height = SELECT_HEIGHT,
        choices = function()
            return {
                { value = DISPLAY_MODE.ALL, text = Text("modes." .. DISPLAY_MODE.ALL) },
                { value = DISPLAY_MODE.MISSING, text = Text("modes." .. DISPLAY_MODE.MISSING) },
            }
        end,
        selected = function()
            return Settings().mode
        end,
        onChange = function(value)
            Settings().mode = value
            options.onChanged()
        end,
    })
    modeSelect:SetPoint("TOPLEFT", PADDING, nextTop)
    nextTop = nextTop - SELECT_HEIGHT - ROW_GAP
    table.insert(refreshers, function()
        modeSelect:Refresh()
    end)

    -- field -- the key in ns.db.settings
    local function AddSlider(textKey, field, steps, format)
        AddLabel(textKey)
        local slider = ns.UI.StepSlider(frame, {
            steps = steps,
            value = Settings()[field],
            width = SLIDER_WIDTH,
            valueWidth = SLIDER_VALUE_WIDTH,
            format = format or tostring,
            onChange = function(value)
                Settings()[field] = value
                options.onChanged()
            end,
        })
        slider:SetPoint("TOPLEFT", PADDING + 18, nextTop - 4)
        nextTop = nextTop - SLIDER_HEIGHT - ROW_GAP
        table.insert(refreshers, function()
            slider:SetValueOf(Settings()[field])
        end)
    end

    AddSlider("settings.icon_size", "iconSize", Range(ns.Config.MIN_ICON_SIZE, ns.Config.MAX_ICON_SIZE, 2))
    AddSlider("settings.icons_per_row", "iconsPerRow", Range(1, ns.Config.MAX_ICONS_PER_ROW, 1))
    AddSlider("settings.icon_spacing", "iconSpacing", Range(0, 20, 1))
    AddSlider("settings.warn_seconds", "warnSeconds", WARN_STEPS, ns.Utilities.FormatSeconds)

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
        checkbox:SetPoint("TOPLEFT", PADDING - 4, nextTop)
        nextTop = nextTop - CHECKBOX_HEIGHT
        table.insert(refreshers, function()
            checkbox:SetChecked(read())
        end)
    end

    AddCheckbox("settings.unlocked", "settings.unlocked_hint", function()
        return not Settings().locked
    end, function(isChecked)
        -- the panel holds secure buttons: it can not move in combat
        if InCombatLockdown() then
            ns.Utilities.Print(Text("messages.in_combat"))
            return
        end
        Settings().locked = not isChecked
    end)
    AddCheckbox("settings.minimap", nil, function()
        return not Settings().minimap.hide
    end, function(isChecked)
        ns.Components.MinimapButton.SetHidden(not isChecked)
    end)

    function frame:Refresh()
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end

    return frame
end
