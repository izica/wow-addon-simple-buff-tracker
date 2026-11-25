-- buff_editor.lua -- the right side of the Buffs tab: one buff -- what is
-- tracked, how a click puts it back, its icon, when it is shown; delete.
-- The order of the buffs is changed by dragging them in the list.
--
-- Text fields save on Enter or when they lose the focus, only if the text was
-- changed (a name shown for an item may not parse back when the item is not in
-- the bags). While typing, suggestions with pictures drop under a field
-- (ui/suggestions.lua, dataflows/icon_search.lua). A spell from the spellbook
-- or an item from the bags can be dragged onto a field, or shift-clicked while
-- the field is in focus (MainWindow.PickLink); a grey note under each field says
-- what to type or drop there. A field that does not apply (the buff of a weapon
-- enchant, the spell or item of a buff without a source) is hidden with its
-- label and note, and the fields under it move up (ui/form_layout.lua groups). Right of
-- the buff, spell and item fields stands their picture, with the game's tooltip
-- of the spell or item on hover. An edit that fails shows its reason in red in
-- the button row, left of Delete.
--
-- Two pages, as tabs at the top of the editor (ui/segment_tabs.lua): Buff --
-- what it is; Conditions -- when it is shown (where, an item in the bags, a
-- talent), its tab counts the conditions set. The window has no room for both
-- in one column. The page stays chosen when another buff is picked: setting the
-- same condition for several buffs goes one after another.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Trim = ns.Utilities.Trim
local Spell = ns.Utilities.Spell
local Item = ns.Utilities.Item
local BuffService = ns.Services.Buff
local IconSearch = ns.Dataflows.IconSearch
local WeaponEnchant = ns.Dataflows.WeaponEnchant
local BuffConditions = ns.Dataflows.BuffConditions
local Talents = ns.Dataflows.Talents
local INSTANCE_KINDS = ns.Constants.INSTANCE_KINDS
local COMBAT_STATE = ns.Constants.COMBAT_STATE
local Zones = ns.Dataflows.Zones
local SOURCE_KIND = ns.Constants.SOURCE_KIND
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT

local BuffEditor = {}
ns.Components.BuffEditor = BuffEditor

local TARGET_KIND = ns.Constants.TARGET_KIND
local SOURCE_NONE = "none"
local ANY_ENCHANT = ""     -- the enchant select: any temporary enchant on the slot
local COMBAT_ANY = "any"   -- the combat select: in combat and out of it

local PADDING = 18
local PREVIEW_SIZE = 28
local PREVIEW_GAP = 12
local PREVIEW_ART_GAP = 8     -- the field's art sticks out this far right of its frame
-- every control ends on one line; the pictures stand right of it
local RIGHT_INSET = PADDING + PREVIEW_SIZE + PREVIEW_GAP
local ICON_CROP = 0.08
local NOTE_LINES = 2
local BUTTON_GAP = 10
local BUTTON_WIDTH = 90
local BUTTON_HEIGHT = 24
-- the button row at the bottom of the editor: the pages end above it
local BUTTON_ROW_HEIGHT = PADDING + BUTTON_HEIGHT + BUTTON_GAP
local TABS_TOP = 8           -- from the top of the editor to its tabs
local TABS_SIDE = 10
-- the pages start under the tabs
local PAGE_TOP = TABS_TOP + ns.UI.SEGMENT_TABS_HEIGHT
local PAGE_BUFF = "buff"
local PAGE_CONDITIONS = "conditions"
local PLACE_COLUMN_WIDTH = 92   -- four places in one row
local TITLE_HEIGHT = 22
local HINT_LINES = 2
local HINT_LINE_HEIGHT = 12
local HINT_COLOR = { 0.6, 0.6, 0.6 }
local STATUS_HEIGHT = 16
local SHOWN_COLOR = { 0.3, 1, 0.3 }
local HIDDEN_COLOR = { 1, 0.3, 0.3 }
local CHECKBOX_NOTE_GAP = 6   -- a checkbox row has no gap under it of its own
local ERROR_COLOR = { 1, 0.3, 0.3 }
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

-- options: onChanged() -- after any edit; onDelete(index)
function BuffEditor.Create(parent, options)
    local frame = ns.UI.InsetPanel(parent, {})
    local buff = nil
    local buffIndex = nil
    local buffCount = 0
    local inputs = {}     -- [field key] = input

    -- two pages of one buff under the tabs: what it is (main) and when it is shown (conditions)
    local function NewPage()
        local newPage = CreateFrame("Frame", nil, frame)
        newPage:SetPoint("TOPLEFT", 0, -PAGE_TOP)
        newPage:SetPoint("BOTTOMRIGHT")
        return newPage
    end
    local mainPage = NewPage()
    -- the conditions scroll: there are more of them than the window is tall
    local conditionsArea = ns.UI.ScrollArea(frame)
    conditionsArea:SetPoint("TOPLEFT", 0, -PAGE_TOP)
    conditionsArea:SetPoint("BOTTOMRIGHT", -ns.UI.SCROLL_AREA_BAR_SPACE, BUTTON_ROW_HEIGHT)
    conditionsArea:Hide()
    local conditionsPage = conditionsArea.content
    local isConditionsPage = false
    local ShowPage = nil   -- defined after the fields (it clears their focus)
    local tabs = ns.UI.SegmentTabs(frame, {
        tabs = {
            { id = PAGE_BUFF, text = Text("settings.page_buff") },
            { id = PAGE_CONDITIONS, text = Text("settings.conditions") },
        },
        onSelect = function(id)
            ShowPage(id == PAGE_CONDITIONS)
            frame:Display(buff, buffIndex, buffCount)
        end,
    })
    tabs:SetPoint("TOPLEFT", TABS_SIDE, -TABS_TOP)
    tabs:SetPoint("TOPRIGHT", -TABS_SIDE, -TABS_TOP)
    tabs:Select(PAGE_BUFF)
    local mainForm = ns.UI.FormLayout(mainPage, { padding = PADDING, rightInset = RIGHT_INSET })
    local conditionsForm = ns.UI.FormLayout(conditionsPage, { padding = PADDING, rightInset = RIGHT_INSET })
    -- the page and its form the next fields go on
    local page = mainPage
    local form = mainForm

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
        local group = form:Group()
        local label = form:Label(Text(textKey))
        local select = ns.UI.Select(page, {
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
        select.group = group
        return select
    end

    -- key -- the field name; field: read(buff) -> text, save(buff, text) -> ok, errorKey,
    -- sources() -> IconSearch.SOURCES, textOf(suggestion) -> text,
    -- takes(linkKind) -> whether a "spell" / "item" link fits, note() -> the text under it,
    -- preview() -> icon, showTooltip(tooltip) -- the picture right of the field (optional)
    local function AddInput(key, textKey, field)
        local group = form:Group()
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

        input = ns.UI.Input(page, {
            width = 100,   -- the form stretches it
            fontObject = "GameFontHighlight",   -- the same font as the dropdowns
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
        input.note = form:Note(field.note(), NOTE_LINES)

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
        input.group = group
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

        input.preview = false   -- a field without a picture (the zone field)
        if field.preview then
            local preview = NewPreview(page, field.preview)
            -- right of the drawn edge of the field
            preview:SetPoint("LEFT", input, "RIGHT", PREVIEW_ART_GAP + PREVIEW_GAP, 0)
            input.preview = preview
        end
        inputs[key] = input
        return input
    end

    local targetSelect = AddSelect("settings.target", function()
        return {
            { value = TARGET_KIND.AURA, text = Text("settings.target_aura") },
            { value = WEAPON_SLOT.MAIN_HAND, text = Text("buff." .. WEAPON_SLOT.MAIN_HAND) },
            { value = WEAPON_SLOT.OFF_HAND, text = Text("buff." .. WEAPON_SLOT.OFF_HAND) },
            { value = TARGET_KIND.EQUIPPED, text = Text("settings.target_equipped") },
        }
    end, function()
        return buff and BuffService.TargetKind(buff)
    end, function(value)
        BuffService.SetTargetKind(buff, value)
    end)

    -- a weapon buff: which temporary enchant -- any, or one seen on the weapons before
    local enchantSelect = AddSelect("settings.enchant", function()
        local choices = { { value = ANY_ENCHANT, text = Text("settings.enchant_any") } }
        for _, name in ipairs(WeaponEnchant.SeenNames()) do
            table.insert(choices, { value = name, text = name })
        end
        return choices
    end, function()
        return buff and (WeaponEnchant.TargetName(buff.target) or ANY_ENCHANT)
    end, function(value)
        if value == ANY_ENCHANT then
            BuffService.SetEnchant(buff, nil)
        else
            BuffService.SetEnchant(buff, value)
        end
    end)
    enchantSelect.note = form:Note(Text("settings.enchant_note"), NOTE_LINES)

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
        note = function()
            return Text("settings.aura_note")
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

    -- an equipped item: the item to wear, it is the picture and the click too
    local equipInput = AddInput("equipItem", "settings.equip_item", {
        read = BuffService.EquipItemText,
        save = BuffService.SetEquipItemText,
        sources = function()
            return IconSearch.SOURCES.ITEMS
        end,
        textOf = ItemTextOf,
        takes = function(linkKind)
            return linkKind == "item"
        end,
        note = function()
            return Text("settings.equip_item_note")
        end,
        preview = function()
            local itemId = buff and buff.target.equipItemId
            if not itemId then
                return nil
            end
            return Item.Icon(itemId), function(tooltip)
                tooltip:SetItemByID(itemId)
            end
        end,
    })

    local sourceSelect = AddSelect("settings.source", function()
        -- an item to wear can only be put on; the others are cast or used
        if buff and BuffService.TargetKind(buff) == TARGET_KIND.EQUIPPED then
            return {
                { value = SOURCE_NONE, text = Text("settings.source_none") },
                { value = SOURCE_KIND.EQUIP, text = Text("settings.source_equip") },
            }
        end
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
        note = function()
            if IsItemSource() then
                return Text("settings.item_note")
            end
            return Text("settings.spell_note")
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
        note = function()
            return Text("settings.icon_note")
        end,
        preview = function()
            return buff and BuffService.Icon(buff)
        end,
    })

    -- how long before the end the buff counts as missing: its own, or the panel's
    -- (an equipped item has no end: hidden for it)
    local warnGroup = form:Group()
    local warnLabel = form:Label(Text("settings.buff_warn"))
    local warnSlider = ns.UI.StepSlider(page, {
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

    -- the conditions page: when the buff is shown at all
    page = conditionsPage
    form = conditionsForm

    local conditionsTitle = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    form:Text(conditionsTitle, TITLE_HEIGHT)
    local conditionsHint = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    conditionsHint:SetTextColor(HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3])
    conditionsHint:SetJustifyV("TOP")
    conditionsHint:SetHeight(HINT_LINES * HINT_LINE_HEIGHT)
    conditionsHint:SetText(Text("settings.conditions_hint"))
    form:Text(conditionsHint, HINT_LINES * HINT_LINE_HEIGHT)
    -- what the conditions do right now: shown, or hidden and why
    local conditionsStatus = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    conditionsStatus:SetWordWrap(false)
    form:Text(conditionsStatus, STATUS_HEIGHT + BUTTON_GAP)

    -- where: all checked (the default) -- everywhere; unchecked -- not there
    local placesLabel = form:Label(Text("settings.condition_places"))
    local placeBoxes = {}   -- [instance kind] = checkbox
    local placeRow = {}     -- the same, in the order of INSTANCE_KINDS
    for _, kind in ipairs(INSTANCE_KINDS) do
        local checkbox = ns.UI.Checkbox(page, {
            text = Text("settings.place_" .. kind),
            onChange = function(isChecked)
                if buff then
                    BuffService.SetConditionPlace(buff, kind, isChecked)
                    options.onChanged()
                end
            end,
        })
        placeBoxes[kind] = checkbox
        table.insert(placeRow, checkbox)
    end
    form:CheckboxRow(placeRow, PLACE_COLUMN_WIDTH)
    form:Space(CHECKBOX_NOTE_GAP)
    local placesNote = form:Note(Text("settings.condition_places_note"), 1)

    -- only in some zones: the zones picked stand as tags inside the field, the
    -- cursor after them; typing suggests zones and dungeons, the empty field
    -- offers the zone the player is in; a click on a tag takes it out
    local function PickedZones()
        local picked = {}
        local zones = buff and buff.conditions and buff.conditions.zones or {}
        for _, zone in ipairs(zones) do
            picked[zone.mapId or zone.name] = true
        end
        return picked
    end

    local function ZoneSuggestions(text)
        local picked = PickedZones()
        if text == "" then
            local current = Zones.Current()
            if not current.name or picked[current.mapId or current.name] then
                return {}
            end
            return { {
                label = Text("settings.zone_here", current.name),
                icon = IconSearch.MAP_ICON,
                mapId = current.mapId,
                zoneName = current.name,
            } }
        end
        local result = {}
        for _, suggestion in ipairs(IconSearch.Search(text, IconSearch.SOURCES.ZONES)) do
            if not picked[suggestion.mapId] then
                table.insert(result, suggestion)
            end
        end
        return result
    end

    local zoneLabel = form:Label(Text("settings.condition_zones"))
    local zoneField = ns.UI.TagInput(page, {
        placeholder = Text("settings.zone_placeholder"),
        removeTooltip = Text("settings.zone_remove_tooltip"),
        search = ZoneSuggestions,
        onChoose = function(suggestion)
            if not buff then
                return
            end
            BuffService.AddConditionZone(buff, {
                mapId = suggestion.mapId,
                name = suggestion.zoneName or suggestion.label,
            })
            ShowError(nil)
            options.onChanged()
        end,
        onRemove = function(index)
            if not buff then
                return
            end
            BuffService.RemoveConditionZone(buff, index)
            options.onChanged()
        end,
        onSubmit = function(text)
            if not buff then
                return false
            end
            local isAdded, errorKey = BuffService.AddConditionZoneText(buff, text)
            ShowError(errorKey)
            if isAdded then
                options.onChanged()
            end
            return isAdded
        end,
    })
    zoneField.editBox.fieldKey = "conditionZone"   -- the tests type into it like into the other fields
    form:Field(zoneField, function()
        return zoneField:GetContentHeight()
    end)
    local zoneNote = form:Note(Text("settings.condition_zones_note"), 1)

    -- in combat, out of it, or both
    local combatSelect = AddSelect("settings.condition_combat", function()
        return {
            { value = COMBAT_ANY, text = Text("settings.combat_any") },
            { value = COMBAT_STATE.IN, text = Text("settings.combat_in") },
            { value = COMBAT_STATE.OUT, text = Text("settings.combat_out") },
        }
    end, function()
        return buff and (buff.conditions and buff.conditions.combat or COMBAT_ANY)
    end, function(value)
        if value == COMBAT_ANY then
            BuffService.SetConditionCombat(buff, nil)
        else
            BuffService.SetConditionCombat(buff, value)
        end
    end)
    combatSelect.note = form:Note(Text("settings.condition_combat_note"), 1)

    local itemConditionInput = AddInput("conditionItem", "settings.condition_item", {
        read = BuffService.ConditionItemText,
        save = BuffService.SetConditionItemText,
        sources = function()
            return IconSearch.SOURCES.ITEMS
        end,
        textOf = ItemTextOf,
        takes = function(linkKind)
            return linkKind == "item"
        end,
        note = function()
            return Text("settings.condition_item_note")
        end,
        preview = function()
            local itemId = buff and buff.conditions and buff.conditions.itemId
            if not itemId then
                return nil
            end
            return Item.Icon(itemId), function(tooltip)
                tooltip:SetItemByID(itemId)
            end
        end,
    })

    local talentConditionInput = AddInput("conditionTalent", "settings.condition_talent", {
        read = BuffService.ConditionTalentText,
        save = BuffService.SetConditionTalentText,
        sources = function()
            return IconSearch.SOURCES.TALENTS
        end,
        textOf = NameOf,
        takes = function(linkKind)
            return linkKind == "spell" or linkKind == "talent"
        end,
        note = function()
            return Text("settings.condition_talent_note")
        end,
        preview = function()
            local talent = buff and buff.conditions and buff.conditions.talent
            if not talent then
                return nil
            end
            local spellId = talent.spellId
            if spellId then
                return Spell.Icon(spellId), function(tooltip)
                    tooltip:SetSpellByID(spellId)
                end
            end
            for _, known in ipairs(Talents.All()) do
                if known.name == talent.name then
                    return known.icon
                end
            end
            return Spell.Icon(talent.name)
        end,
    })

    -- the talent condition the other way round: for the other specialization
    local talentMissingBox = ns.UI.Checkbox(page, {
        text = Text("settings.condition_talent_missing"),
        onChange = function(isChecked)
            if buff then
                BuffService.SetConditionTalentMissing(buff, isChecked)
                options.onChanged()
            end
        end,
    })
    form:Checkbox(talentMissingBox)

    -- How tall the fields are at most, and the button row under them: the window
    -- must hold both. The enchant select and the buff field never show together
    -- (a weapon buff or an aura), the buff field is the taller one.
    enchantSelect.group:SetShown(false)
    equipInput.group:SetShown(false)
    mainForm:Layout()
    conditionsForm:Layout()
    -- (the conditions page scrolls: only the main page must fit)
    frame.formHeight = PAGE_TOP - mainForm.top
    frame.buttonRowHeight = PADDING + BUTTON_HEIGHT + BUTTON_GAP

    -- one page or the other; a field typed in on the page that goes away is saved first
    ShowPage = function(showConditions)
        for _, input in pairs(inputs) do
            if input:HasFocus() then
                input:ClearFocus()
            end
        end
        if zoneField.editBox:HasFocus() then
            zoneField.editBox:ClearFocus()
        end
        isConditionsPage = showConditions
        mainPage:SetShown(not showConditions)
        conditionsArea:SetShown(showConditions)
        if showConditions then
            tabs:Select(PAGE_CONDITIONS)
        else
            tabs:Select(PAGE_BUFF)
        end
    end

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
    errorText:SetPoint("LEFT", frame, "BOTTOMLEFT", PADDING, PADDING + BUTTON_HEIGHT / 2)
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
    local parts = { targetSelect, targetSelect.label, auraInput, auraInput.label, equipInput,
        equipInput.label, sourceSelect,
        sourceSelect.label, sourceInput, sourceInput.label, iconInput, iconInput.label,
        warnLabel, warnSlider, errorText, deleteButton, tabs, conditionsTitle, conditionsHint, conditionsStatus, placesLabel, placesNote, itemConditionInput,
        itemConditionInput.label, talentConditionInput, talentConditionInput.label, talentMissingBox,
        zoneLabel, zoneField, zoneNote, combatSelect, combatSelect.label, combatSelect.note }
    for _, kind in ipairs(INSTANCE_KINDS) do
        table.insert(parts, placeBoxes[kind])
    end

    -- the conditions page of the buff shown
    local function DisplayConditions()
        local conditions = buff.conditions or {}
        local hiddenPlaces = conditions.hiddenPlaces or {}
        for kind, checkbox in pairs(placeBoxes) do
            checkbox:SetChecked(not hiddenPlaces[kind])
        end
        talentMissingBox:SetChecked(conditions.talentMissing == true)
        talentMissingBox:SetEnabled(conditions.talent ~= nil)
        conditionsTitle:SetText(Text("settings.conditions_title", ns.Models.Buff.TargetLabel(buff)))

        local reasonKey, reasonArgument = BuffConditions.Reason(buff)
        if reasonKey then
            conditionsStatus:SetText(Text("settings.status_hidden", Text(reasonKey, reasonArgument)))
            conditionsStatus:SetTextColor(HIDDEN_COLOR[1], HIDDEN_COLOR[2], HIDDEN_COLOR[3])
        else
            conditionsStatus:SetText(Text("settings.status_shown"))
            conditionsStatus:SetTextColor(SHOWN_COLOR[1], SHOWN_COLOR[2], SHOWN_COLOR[3])
        end

        -- every place unchecked: say it plainly, it is easy to do by mistake
        if BuffConditions.IsNowhere(buff) then
            placesNote:SetText(Text("settings.condition_places_nowhere"))
            placesNote:SetTextColor(HIDDEN_COLOR[1], HIDDEN_COLOR[2], HIDDEN_COLOR[3])
        else
            placesNote:SetText(Text("settings.condition_places_note"))
            placesNote:SetTextColor(HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3])
        end

        -- the zones picked, as tags in their field
        local zoneTags = {}
        for _, zone in ipairs(conditions.zones or {}) do
            table.insert(zoneTags, { text = zone.name })
        end
        zoneField:SetTags(zoneTags)
        combatSelect:Refresh()

        -- the tab tells there are conditions without opening it
        local count = BuffConditions.Count(buff)
        if count > 0 then
            tabs:SetTabText(PAGE_CONDITIONS, Text("settings.conditions_count", count))
        else
            tabs:SetTabText(PAGE_CONDITIONS, Text("settings.conditions"))
        end
    end

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
            ShowPage(false)
            enchantSelect:Hide()
            enchantSelect.label:Hide()
            enchantSelect.note:Hide()
            for _, input in pairs(inputs) do
                input.note:Hide()
                if input.preview then
                    input.preview:Hide()
                end
            end
            return
        end
        if isNewBuff then
            ShowError(nil)
        end

        -- one field for what is tracked: the buff, the enchant or the item to wear
        local targetKind = BuffService.TargetKind(buff)
        local isAura = targetKind == TARGET_KIND.AURA
        local isEquipped = targetKind == TARGET_KIND.EQUIPPED
        local isWeapon = not isAura and not isEquipped
        auraInput:SetShown(isAura)
        auraInput.label:SetShown(isAura)
        auraInput.group:SetShown(isAura)
        equipInput:SetShown(isEquipped)
        equipInput.label:SetShown(isEquipped)
        equipInput.group:SetShown(isEquipped)
        enchantSelect:SetShown(isWeapon)
        enchantSelect.label:SetShown(isWeapon)
        enchantSelect.note:SetShown(isWeapon)
        enchantSelect.group:SetShown(isWeapon)

        -- "put it on" needs no spell or item: the item is the one above
        local hasSourceField = buff.source ~= nil and buff.source.kind ~= SOURCE_KIND.EQUIP
        sourceInput:SetShown(hasSourceField)
        sourceInput.label:SetShown(hasSourceField)
        sourceInput.group:SetShown(hasSourceField)

        warnLabel:SetShown(not isEquipped)
        warnSlider:SetShown(not isEquipped)
        warnGroup:SetShown(not isEquipped)

        iconInput:Show()
        iconInput.label:Show()
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
            -- the note goes with its field
            input.note:SetText(input.field.note())
            input.note:SetShown(input:IsShown())
            if input.preview then
                input.preview:Refresh()
                if not input:IsShown() then
                    input.preview:Hide()
                end
            end
        end
        targetSelect:Refresh()
        enchantSelect:Refresh()
        sourceSelect:Refresh()
        warnSlider:SetValueOf(buff.warnSeconds or WARN_DEFAULT)
        DisplayConditions()
        -- the hidden fields take no room: the shown ones stack up without holes
        mainForm:Layout()
        conditionsForm:Layout()
        conditionsArea:SetContentHeight(PADDING - conditionsForm.top, true)
    end

    -- a buff just added: its first page, typing in its Buff field
    function frame:StartEditing()
        ShowPage(false)
        local auraInput = inputs.aura
        if buff and auraInput:IsShown() then
            auraInput:SetFocus()
        end
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
        elseif link:find("talent:", 1, true) then
            linkKind = "talent"
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
