-- buff_editor.lua -- the right side of the Buffs tab: one buff -- what is
-- tracked, how a click puts it back, its icon; up, down, delete.
--
-- Text fields save on Enter or when they lose the focus, only if the text was
-- changed (a name shown for an item may not parse back when the item is not in
-- the bags). While typing, suggestions with pictures drop under a field
-- (ui/suggestions.lua, dataflows/icon_search.lua). An edit that fails shows its
-- reason in red under the fields.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Trim = ns.Utilities.Trim
local BuffService = ns.Services.Buff
local IconSearch = ns.Dataflows.IconSearch
local SOURCE_KIND = ns.Constants.SOURCE_KIND
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT

local BuffEditor = {}
ns.Components.BuffEditor = BuffEditor

local TARGET_AURA = "aura"
local SOURCE_NONE = "none"

local PADDING = 16
local LABEL_HEIGHT = 16
local ROW_GAP = 12
local SELECT_WIDTH = 240
local SELECT_HEIGHT = 26
local INPUT_HEIGHT = 22
local INPUT_LEFT = PADDING + 9          -- the dropdown frame of an input sticks out 9 pixels on the left
local INPUT_RIGHT = PADDING + 8 + 34    -- room for the icon preview right of the fields
local PREVIEW_SIZE = 30
local BUTTON_WIDTH = 90
local BUTTON_HEIGHT = 24
local ERROR_COLOR = { 1, 0.3, 0.3 }
local HINT_COLOR = { 0.6, 0.6, 0.6 }
local DELETE_POPUP = "SIMPLEBUFFTRACKER_DELETE_BUFF"
-- the per-buff warning slider: the first step -- the panel's own setting
local WARN_DEFAULT = -1
local WARN_STEPS = { WARN_DEFAULT, 0, 15, 30, 60, 120, 180, 300, 600, 900, 1200, 1800 }
local WARN_SLIDER_WIDTH = 220
local WARN_SLIDER_HEIGHT = 22
local WARN_VALUE_WIDTH = 140

-- what goes into a field for a picked suggestion
local function AuraTextOf(suggestion)
    return suggestion.label
end

local function ItemTextOf(suggestion)
    if suggestion.itemId then
        return "item:" .. suggestion.itemId
    end
    return suggestion.label
end

local function IconTextOf(suggestion)
    if suggestion.itemId then
        return "item:" .. suggestion.itemId
    end
    if suggestion.spellId then
        return tostring(suggestion.spellId)
    end
    return "icon:" .. suggestion.icon
end

-- options: onChanged() -- after any edit; onMove(index, offset), onDelete(index)
function BuffEditor.Create(parent, options)
    local frame = ns.UI.InsetPanel(parent, {})
    local buff = nil
    local buffIndex = nil
    local buffCount = 0
    local inputs = {}   -- [field key] = input
    local nextTop = -PADDING

    local errorText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errorText:SetTextColor(ERROR_COLOR[1], ERROR_COLOR[2], ERROR_COLOR[3])
    errorText:SetJustifyH("LEFT")

    local function ShowError(errorKey)
        if errorKey then
            errorText:SetText(Text(errorKey))
        else
            errorText:SetText("")
        end
    end

    local function AddLabel(textKey)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", PADDING, nextTop)
        label:SetText(Text(textKey))
        nextTop = nextTop - LABEL_HEIGHT
        return label
    end

    local function AddSelect(textKey, choices, selected, onChange)
        local label = AddLabel(textKey)
        local select = ns.UI.Select(frame, {
            width = SELECT_WIDTH,
            height = SELECT_HEIGHT,
            choices = choices,
            selected = selected,
            onChange = function(value)
                if buff then
                    onChange(value)
                    ShowError(nil)
                    options.onChanged()
                end
            end,
        })
        select:SetPoint("TOPLEFT", PADDING, nextTop)
        nextTop = nextTop - SELECT_HEIGHT - ROW_GAP
        select.label = label
        return select
    end

    -- key -- the field name, for shift-clicks; read(buff) -> text;
    -- save(buff, text) -> ok, errorKey; sources -- IconSearch.SOURCES or a function
    -- returning them, textOf(suggestion) -> the text a picked suggestion puts in
    local function AddInput(key, textKey, read, save, sources, textOf)
        local label = AddLabel(textKey)
        local input = nil

        local function Save(text)
            if not buff then
                return
            end
            text = Trim(text)
            if text == input.shownText then
                return
            end
            local _, errorKey = save(buff, text)
            ShowError(errorKey)
            if not errorKey then
                options.onChanged()
            end
        end

        input = ns.UI.Input(frame, {
            height = INPUT_HEIGHT,
            width = 100,   -- stretched by the two points below
            onEnter = function()
                input:TakeHighlighted()
            end,
            onFocusLost = function()
                if not input:IsChoosingSuggestion() then
                    Save(input:GetText())
                end
            end,
        })
        input:SetPoint("TOPLEFT", INPUT_LEFT, nextTop - 2)
        input:SetPoint("RIGHT", frame, "RIGHT", -INPUT_RIGHT, 0)
        nextTop = nextTop - INPUT_HEIGHT - ROW_GAP - 2

        ns.UI.AttachSuggestions(input, {
            search = function(text)
                local fieldSources = sources
                if type(sources) == "function" then
                    fieldSources = sources()
                end
                return IconSearch.Search(text, fieldSources)
            end,
            onChoose = function(suggestion)
                local text = textOf(suggestion)
                input:SetText(text)
                Save(text)
                input:ClearFocus()
            end,
        })

        input.fieldKey = key
        input.label = label
        input.read = read
        -- put a text in as if typed and confirmed (shift-clicks)
        function input:Put(text)
            self:SetText(text)
            Save(text)
            self:ClearFocus()
        end
        inputs[key] = input
        return input
    end

    local targetSelect = AddSelect("settings.target", function()
        return {
            { value = TARGET_AURA, text = Text("settings.target_aura") },
            { value = WEAPON_SLOT.MAIN_HAND, text = Text("buff." .. WEAPON_SLOT.MAIN_HAND) },
            { value = WEAPON_SLOT.OFF_HAND, text = Text("buff." .. WEAPON_SLOT.OFF_HAND) },
        }
    end, function()
        return buff and (buff.target.weapon or TARGET_AURA)
    end, function(value)
        BuffService.SetTargetKind(buff, value)
    end)

    local auraInput = AddInput("aura", "settings.aura", BuffService.AuraText,
        BuffService.SetAuraText, IconSearch.SOURCES.BUFFS, AuraTextOf)

    local sourceSelect = AddSelect("settings.source", function()
        return {
            { value = SOURCE_NONE, text = Text("settings.source_none") },
            { value = SOURCE_KIND.SPELL, text = Text("settings.source_spell") },
            { value = SOURCE_KIND.ITEM, text = Text("settings.source_item") },
        }
    end, function()
        return buff and (buff.source and buff.source.kind or SOURCE_NONE)
    end, function(value)
        BuffService.SetSourceKind(buff, value)
    end)

    -- the source field searches spells or bag items, by the kind chosen
    local function IsItemSource()
        return buff ~= nil and buff.source ~= nil and buff.source.kind == SOURCE_KIND.ITEM
    end
    local sourceInput = AddInput("sourceValue", "settings.source_spell_value", BuffService.SourceText,
        BuffService.SetSourceText, function()
            if IsItemSource() then
                return IconSearch.SOURCES.ITEMS
            end
            return IconSearch.SOURCES.SPELLS
        end, function(suggestion)
            if IsItemSource() then
                return ItemTextOf(suggestion)
            end
            return AuraTextOf(suggestion)
        end)

    local iconInput = AddInput("icon", "settings.icon", function(edited)
        return edited.iconText or ""
    end, BuffService.SetIconText, IconSearch.SOURCES.ALL, IconTextOf)

    local preview = frame:CreateTexture(nil, "ARTWORK")
    preview:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
    preview:SetPoint("LEFT", iconInput, "RIGHT", 14, 0)

    -- how long before the end the buff counts as missing: its own, or the panel's
    local warnLabel = AddLabel("settings.buff_warn")
    local warnSlider = ns.UI.StepSlider(frame, {
        steps = WARN_STEPS,
        value = WARN_DEFAULT,
        width = WARN_SLIDER_WIDTH,
        valueWidth = WARN_VALUE_WIDTH,
        format = function(seconds)
            if seconds == WARN_DEFAULT then
                return Text("settings.warn_default", ns.Utilities.FormatSeconds(ns.db.settings.warnSeconds))
            end
            return ns.Utilities.FormatSeconds(seconds)
        end,
        onChange = function(seconds)
            if not buff then
                return
            end
            if seconds == WARN_DEFAULT then
                buff.warnSeconds = nil
            else
                buff.warnSeconds = seconds
            end
            options.onChanged()
        end,
    })
    warnSlider:SetPoint("TOPLEFT", PADDING + 18, nextTop - 4)
    nextTop = nextTop - WARN_SLIDER_HEIGHT - ROW_GAP

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", PADDING, nextTop)
    hint:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3])
    hint:SetText(Text("settings.edit_hint"))
    errorText:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    errorText:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)

    local upButton = ns.UI.Button(frame, {
        text = Text("settings.move_up"),
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            options.onMove(buffIndex, -1)
        end,
    })
    upButton:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    local downButton = ns.UI.Button(frame, {
        text = Text("settings.move_down"),
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            options.onMove(buffIndex, 1)
        end,
    })
    downButton:SetPoint("LEFT", upButton, "RIGHT", 6, 0)
    local deleteButton = ns.UI.Button(frame, {
        text = Text("settings.remove"),
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            StaticPopup_Show(DELETE_POPUP, ns.Models.Buff.TargetLabel(buff), nil, buffIndex)
        end,
    })
    deleteButton:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    StaticPopupDialogs[DELETE_POPUP] = {
        text = Text("settings.remove_confirm"),
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, index)
            options.onDelete(index)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER")
    emptyText:SetText(Text("settings.no_buff_chosen"))

    -- everything but the empty text: shown while a buff is chosen
    local parts = { targetSelect, targetSelect.label, auraInput, auraInput.label, sourceSelect,
        sourceSelect.label, sourceInput, sourceInput.label, iconInput, iconInput.label, preview,
        warnLabel, warnSlider, hint, errorText, upButton, downButton, deleteButton }

    -- show a buff (nil -- none chosen); index and count -- its place in the list
    function frame:Display(shownBuff, index, count)
        local isNewBuff = shownBuff ~= buff
        buff = shownBuff
        buffIndex = index
        buffCount = count
        for _, part in ipairs(parts) do
            part:SetShown(buff ~= nil)
        end
        emptyText:SetShown(buff == nil)
        if not buff then
            return
        end
        if isNewBuff then
            ShowError(nil)
        end

        local isAura = buff.target.weapon == nil
        auraInput:SetShown(isAura)
        auraInput.label:SetShown(isAura)

        local hasSource = buff.source ~= nil
        sourceInput:SetShown(hasSource)
        sourceInput.label:SetShown(hasSource)
        local isItemSource = hasSource and buff.source.kind == SOURCE_KIND.ITEM
        if isItemSource then
            sourceInput.label:SetText(Text("settings.source_item_value"))
        else
            sourceInput.label:SetText(Text("settings.source_spell_value"))
        end

        for _, input in pairs(inputs) do
            if not input:HasFocus() then
                input.shownText = input.read(buff)
                input:SetText(input.shownText)
            end
        end
        targetSelect:Refresh()
        sourceSelect:Refresh()
        preview:SetTexture(BuffService.Icon(buff))
        warnSlider:SetValueOf(buff.warnSeconds or WARN_DEFAULT)
        upButton:SetEnabled(buffIndex > 1)
        downButton:SetEnabled(buffIndex < buffCount)
    end

    -- the field being typed in now: input, its key and the buff; nil -- none
    function frame:FocusedField()
        if not buff then
            return nil
        end
        for key, input in pairs(inputs) do
            if input:IsShown() and input:HasFocus() then
                return input, key, buff
            end
        end
        return nil
    end

    frame:Display(nil, nil, 0)
    return frame
end
