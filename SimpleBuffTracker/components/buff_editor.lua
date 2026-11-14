-- buff_editor.lua -- the right side of the Buffs tab: one buff -- what is
-- tracked, how a click puts it back, its icon; up, down, delete.
--
-- Text fields save on Enter or when they lose the focus, only if the text was
-- changed (a name shown for an item may not parse back when the item is not in
-- the bags). While typing, suggestions with pictures drop under a field
-- (ui/suggestions.lua, dataflows/icon_search.lua). A spell from the spellbook
-- or an item from the bags can be dragged onto a field, or shift-clicked while
-- the field is in focus (MainWindow.PickLink); an empty field says so. Right of
-- the buff, spell and item fields stands their picture, with the game's tooltip
-- of the spell or item on hover. An edit that fails shows its reason in red in
-- the button row.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Trim = ns.Utilities.Trim
local Spell = ns.Utilities.Spell
local Item = ns.Utilities.Item
local BuffService = ns.Services.Buff
local IconSearch = ns.Dataflows.IconSearch
local SOURCE_KIND = ns.Constants.SOURCE_KIND
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT

local BuffEditor = {}
ns.Components.BuffEditor = BuffEditor

local TARGET_AURA = "aura"
local SOURCE_NONE = "none"

local PADDING = 18
local PREVIEW_SIZE = 28
local PREVIEW_GAP = 12
local PREVIEW_ART_GAP = 8     -- the field's art sticks out this far right of its frame
-- every control ends on one line; the pictures stand right of it
local RIGHT_INSET = PADDING + PREVIEW_SIZE + PREVIEW_GAP
local ICON_CROP = 0.08
local HINT_HEIGHT = 28
local BUTTON_GAP = 10
local BUTTON_WIDTH = 90
local BUTTON_HEIGHT = 24
local ERROR_COLOR = { 1, 0.3, 0.3 }
local HINT_COLOR = { 0.6, 0.6, 0.6 }
local DELETE_POPUP = "SIMPLEBUFFTRACKER_DELETE_BUFF"
-- the per-buff warning slider: the first step -- the panel's own setting
local WARN_DEFAULT = -1
local WARN_STEPS = { WARN_DEFAULT, 0, 15, 30, 60, 120, 180, 300, 600, 900, 1200, 1800 }
local WARN_VALUE_WIDTH = 130

-- what goes into a field for a picked suggestion
local function NameOf(suggestion)
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

-- What the cursor holds, as a link: a spell dragged from the spellbook or an
-- item from the bags; nil -- nothing of that.
local function CursorLink()
    if not GetCursorInfo then
        return nil
    end
    local kind, first, second, third = GetCursorInfo()
    if kind == "item" then
        return second or ("item:" .. tostring(first))
    end
    if kind == "spell" then
        -- modern clients: "spell", slot, book, spellID
        local spellId = third or first
        local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(spellId)
        return link or ("|Hspell:" .. tostring(spellId) .. "|h")
    end
    return nil
end

-- A picture with the game's tooltip on hover. getInfo() -> icon, showTooltip(tooltip) or nil.
local function NewPreview(parent, getInfo)
    local preview = CreateFrame("Button", nil, parent)
    preview:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
    local texture = preview:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    preview.texture = texture

    preview:SetScript("OnEnter", function(self)
        local _, showTooltip = getInfo()
        if not showTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        showTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    preview:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    function preview:Refresh()
        local icon = getInfo()
        self.texture:SetTexture(icon)
        self:SetShown(icon ~= nil)
    end
    return preview
end

-- options: onChanged() -- after any edit; onMove(index, offset), onDelete(index)
function BuffEditor.Create(parent, options)
    local frame = ns.UI.InsetPanel(parent, {})
    local buff = nil
    local buffIndex = nil
    local buffCount = 0
    local inputs = {}     -- [field key] = input
    local previews = {}   -- pictures right of the fields
    local form = ns.UI.FormLayout(frame, { padding = PADDING, rightInset = RIGHT_INSET })

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

    local function IsItemSource()
        return buff ~= nil and buff.source ~= nil and buff.source.kind == SOURCE_KIND.ITEM
    end

    local function AddSelect(textKey, choices, selected, onChange)
        local label = form:Label(Text(textKey))
        local select = ns.UI.Select(frame, {
            width = 100,   -- the form stretches it
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
        form:Field(select)
        select.label = label
        return select
    end

    -- key -- the field name; field: read(buff) -> text, save(buff, text) -> ok, errorKey,
    -- sources() -> IconSearch.SOURCES, textOf(suggestion) -> text,
    -- takes(linkKind) -> whether a "spell" / "item" link fits, placeholder() -> text,
    -- preview() -> icon, showTooltip(tooltip) -- the picture right of the field (optional)
    local function AddInput(key, textKey, field)
        local label = form:Label(Text(textKey))
        local input = nil

        local function Save(text)
            if not buff then
                return
            end
            text = Trim(text)
            if text == input.shownText then
                return
            end
            local _, errorKey = field.save(buff, text)
            ShowError(errorKey)
            if not errorKey then
                options.onChanged()
            end
        end

        input = ns.UI.Input(frame, {
            width = 100,   -- the form stretches it
            fontObject = "GameFontHighlight",   -- the same font as the dropdowns
            placeholder = "",
            onEnter = function()
                input:TakeHighlighted()
            end,
            onFocusLost = function()
                if not input:IsChoosingSuggestion() then
                    Save(input:GetText())
                end
            end,
        })
        form:Field(input)

        ns.UI.AttachSuggestions(input, {
            search = function(text)
                return IconSearch.Search(text, field.sources())
            end,
            onChoose = function(suggestion)
                local text = field.textOf(suggestion)
                input:SetText(text)
                Save(text)
                input:ClearFocus()
            end,
        })

        input.fieldKey = key
        input.label = label
        input.field = field
        -- put a text in as if typed and confirmed (shift-clicks, drops)
        function input:Put(text)
            self:SetText(text)
            Save(text)
            self:ClearFocus()
        end

        -- a spell or an item dropped on the field (or clicked onto it while carried)
        local function Drop()
            local link = CursorLink()
            if link and frame:TakeLink(input, link) then
                ClearCursor()
            end
        end
        input:HookScript("OnReceiveDrag", Drop)
        input:HookScript("OnMouseDown", function()
            if GetCursorInfo and GetCursorInfo() then
                Drop()
            end
        end)

        if field.preview then
            local preview = NewPreview(frame, field.preview)
            -- right of the drawn edge of the field
            preview:SetPoint("LEFT", input, "RIGHT", PREVIEW_ART_GAP + PREVIEW_GAP, 0)
            input.preview = preview
            table.insert(previews, preview)
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

    local auraInput = AddInput("aura", "settings.aura", {
        read = BuffService.AuraText,
        save = BuffService.SetAuraText,
        sources = function()
            return IconSearch.SOURCES.BUFFS
        end,
        textOf = NameOf,
        takes = function(linkKind)
            return linkKind == "spell"
        end,
        placeholder = function()
            return Text("settings.aura_placeholder")
        end,
        preview = function()
            if not buff then
                return nil
            end
            local spellId = buff.target.spellId
            local icon = buff.target.icon or Spell.Icon(spellId or buff.target.name)
            if not spellId then
                return icon
            end
            return icon, function(tooltip)
                tooltip:SetSpellByID(spellId)
            end
        end,
    })

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

    -- the source field: spells or bag items, by the kind chosen
    local sourceInput = AddInput("sourceValue", "settings.source_spell_value", {
        read = BuffService.SourceText,
        save = BuffService.SetSourceText,
        sources = function()
            if IsItemSource() then
                return IconSearch.SOURCES.ITEMS
            end
            return IconSearch.SOURCES.SPELLS
        end,
        textOf = function(suggestion)
            if IsItemSource() then
                return ItemTextOf(suggestion)
            end
            return NameOf(suggestion)
        end,
        takes = function(linkKind)
            if IsItemSource() then
                return linkKind == "item"
            end
            return linkKind == "spell"
        end,
        placeholder = function()
            if IsItemSource() then
                return Text("settings.item_placeholder")
            end
            return Text("settings.spell_placeholder")
        end,
        preview = function()
            local source = buff and buff.source
            if not source then
                return nil
            end
            if source.kind == SOURCE_KIND.ITEM then
                local itemId = source.itemId
                if not itemId then
                    return nil
                end
                return Item.Icon(itemId), function(tooltip)
                    tooltip:SetItemByID(itemId)
                end
            end
            local spellId = source.spellId
            local icon = Spell.Icon(spellId or source.name)
            if not spellId then
                return icon
            end
            return icon, function(tooltip)
                tooltip:SetSpellByID(spellId)
            end
        end,
    })

    local iconInput = AddInput("icon", "settings.icon", {
        read = function(edited)
            return edited.iconText or ""
        end,
        save = BuffService.SetIconText,
        sources = function()
            return IconSearch.SOURCES.ALL
        end,
        textOf = IconTextOf,
        takes = function(linkKind)
            return linkKind == "spell" or linkKind == "item"
        end,
        placeholder = function()
            return Text("settings.icon_placeholder")
        end,
        preview = function()
            return buff and BuffService.Icon(buff)
        end,
    })

    -- how long before the end the buff counts as missing: its own, or the panel's
    local warnLabel = form:Label(Text("settings.buff_warn"))
    local warnSlider = ns.UI.StepSlider(frame, {
        steps = WARN_STEPS,
        value = WARN_DEFAULT,
        width = 100,   -- the form stretches it
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
    form:Slider(warnSlider, WARN_VALUE_WIDTH)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetTextColor(HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3])
    hint:SetText(Text("settings.edit_hint"))
    form:Text(hint, HINT_HEIGHT)
    -- how tall the fields are, and the button row under them: the window must hold both
    frame.formHeight = -form.top
    frame.buttonRowHeight = PADDING + BUTTON_HEIGHT + BUTTON_GAP

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

    -- the reason an edit failed: one line in the button row, it takes no room in the form
    errorText:SetPoint("LEFT", downButton, "RIGHT", BUTTON_GAP, 0)
    errorText:SetPoint("RIGHT", deleteButton, "LEFT", -BUTTON_GAP, 0)
    errorText:SetWordWrap(false)

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
        sourceSelect.label, sourceInput, sourceInput.label, iconInput, iconInput.label,
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
            for _, preview in ipairs(previews) do
                preview:Hide()
            end
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
        if IsItemSource() then
            sourceInput.label:SetText(Text("settings.source_item_value"))
        else
            sourceInput.label:SetText(Text("settings.source_spell_value"))
        end

        for _, input in pairs(inputs) do
            if not input:HasFocus() then
                input.shownText = input.field.read(buff)
                input:SetText(input.shownText)
            end
            input.placeholder:SetText(input.field.placeholder())
            input.placeholder:SetShown(input:GetText() == "")
            if input.preview then
                input.preview:Refresh()
                if not input:IsShown() then
                    input.preview:Hide()
                end
            end
        end
        targetSelect:Refresh()
        sourceSelect:Refresh()
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

    -- A spell or item link into a field, if the field takes that kind (the item
    -- field items, the buff and spell fields spells, the icon field both).
    -- Returns whether it was taken.
    function frame:TakeLink(input, link)
        if not buff then
            return false
        end
        local linkKind = nil
        if link:find("item:", 1, true) then
            linkKind = "item"
        elseif link:find("spell:", 1, true) then
            linkKind = "spell"
        end
        if not (linkKind and input.field.takes(linkKind)) then
            return false
        end
        input:Put(link)
        return true
    end

    frame:Display(nil, nil, 0)
    return frame
end
