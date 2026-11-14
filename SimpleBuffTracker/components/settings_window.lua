-- settings_window.lua -- the addon settings in the game settings (Options ->
-- AddOns -> Simple Buff Tracker), not a window of our own.
--
-- AceConfig-3.0 describes options as a table, AceConfigDialog-3.0 draws them.
--   the addon page    -- in the game's settings panel (AddToBlizOptions), as in
--                        Purple Note and PRR: mode, lock, icon size, icons per
--                        row, warning time, and a button to the buff window;
--   the buff window   -- a small window of its own (AceConfigDialog:Open): the
--                        tracked buffs as a tree on the left, one buff per page --
--                        what is tracked, how a click puts it back, order, delete.
-- The buff window is built anew on every redraw (the options table is a
-- function): after a change of the list SettingsWindow.Refresh redraws it.
-- Every change is applied to the panel at once.
--
-- The text fields take a dragged spell (from the spellbook) or item (from the
-- bags): AceGUI's edit box puts its name or link in and saves. A shift-click on
-- a buff of the player (the client's buff frame, events/buff_frame.lua) goes to
-- SettingsWindow.PickAura: into the buff field being typed in, or, with no field
-- in focus, as a new buff.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Buff = ns.Models.Buff
local BuffParser = ns.Dataflows.BuffParser
local BuffService = ns.Services.Buff
local Item = ns.Utilities.Item
local Trim = ns.Utilities.Trim
local DISPLAY_MODE = ns.Constants.DISPLAY_MODE
local SOURCE_KIND = ns.Constants.SOURCE_KIND
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT

local SettingsWindow = {}
ns.Components.SettingsWindow = SettingsWindow

local OPTIONS_NAME = "SimpleBuffTracker"         -- AceConfig id of the addon page
local BUFFS_NAME = "SimpleBuffTracker_Buffs"     -- AceConfig id of the buff window
local BUFF_KEY_PREFIX = "buff"                   -- buff pages: buff1, buff2, ...
local BUFF_WINDOW_WIDTH = 640
local BUFF_WINDOW_HEIGHT = 420
-- the fields of a buff page that take a shift-clicked buff, spell or item
local LINK_FIELDS = { aura = true, sourceValue = true, icon = true }

local TARGET_AURA = "aura"                       -- the target select: an aura or a weapon slot
local SOURCE_NONE = "none"                       -- the source select: only tracked
local WARN_SECONDS_MAX = 600
local WARN_SECONDS_STEP = 10

local configRegistry = LibStub("AceConfigRegistry-3.0")
local configDialog = LibStub("AceConfigDialog-3.0")

local categoryId = nil
local panelFrame = nil

local function ApplyToPanel()
    ns.Components.BuffPanel.Refresh()
end

-- The buffs page is drawn from the current list: redraw it after any change of
-- the list, also from chat commands.
function SettingsWindow.Refresh()
    if configRegistry:GetOptionsTable(BUFFS_NAME) then
        configRegistry:NotifyChange(BUFFS_NAME)
    end
end

local function Changed()
    SettingsWindow.Refresh()
    ApplyToPanel()
end

-- Same as settings[field], applied to the panel after a change.
local function WithSetting(option, field)
    option.get = function()
        return ns.db.settings[field]
    end
    option.set = function(_, value)
        ns.db.settings[field] = value
        ApplyToPanel()
    end
    return option
end

local function GeneralPage()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or ""
    return {
        type = "group",
        name = ns.Constants.ADDON_TITLE,
        args = {
            title = {
                type = "description",
                name = ns.Constants.ADDON_TITLE .. "  |cff888888" .. Text("settings.version", version) .. "|r",
                fontSize = "large",
                order = 1,
            },
            summary = {
                type = "description",
                name = Text("settings.summary") .. "\n",
                fontSize = "medium",
                order = 2,
            },
            openBuffs = {
                type = "execute",
                name = Text("settings.open_buffs"),
                func = function()
                    if SettingsPanel and SettingsPanel:IsShown() then
                        HideUIPanel(SettingsPanel)
                    end
                    SettingsWindow.OpenBuffs()
                end,
                width = "double",
                order = 3,
            },
            mode = WithSetting({
                type = "select",
                name = Text("settings.mode"),
                values = {
                    [DISPLAY_MODE.ALL] = Text("modes." .. DISPLAY_MODE.ALL),
                    [DISPLAY_MODE.MISSING] = Text("modes." .. DISPLAY_MODE.MISSING),
                },
                sorting = { DISPLAY_MODE.ALL, DISPLAY_MODE.MISSING },
                width = "double",
                order = 10,
            }, "mode"),
            warnSeconds = WithSetting({
                type = "range",
                name = Text("settings.warn_seconds"),
                desc = Text("settings.warn_seconds_hint"),
                min = 0,
                max = WARN_SECONDS_MAX,
                step = WARN_SECONDS_STEP,
                width = "double",
                order = 11,
            }, "warnSeconds"),
            iconSize = WithSetting({
                type = "range",
                name = Text("settings.icon_size"),
                min = ns.Config.MIN_ICON_SIZE,
                max = ns.Config.MAX_ICON_SIZE,
                step = 1,
                order = 20,
            }, "iconSize"),
            iconsPerRow = WithSetting({
                type = "range",
                name = Text("settings.icons_per_row"),
                min = 1,
                max = ns.Config.MAX_ICONS_PER_ROW,
                step = 1,
                order = 21,
            }, "iconsPerRow"),
            iconSpacing = WithSetting({
                type = "range",
                name = Text("settings.icon_spacing"),
                min = 0,
                max = 20,
                step = 1,
                order = 22,
            }, "iconSpacing"),
            unlocked = {
                type = "toggle",
                name = Text("settings.unlocked"),
                desc = Text("settings.unlocked_hint"),
                get = function()
                    return not ns.db.settings.locked
                end,
                set = function(_, value)
                    ns.db.settings.locked = not value
                    ApplyToPanel()
                end,
                disabled = InCombatLockdown,
                width = "full",
                order = 30,
            },
            minimap = {
                type = "toggle",
                name = Text("settings.minimap"),
                get = function()
                    return not ns.db.settings.minimap.hide
                end,
                set = function(_, value)
                    ns.Components.MinimapButton.SetHidden(not value)
                end,
                width = "full",
                order = 31,
            },
        },
    }
end

-- what the target field shows: the aura name, or its id while the name is unknown
local function AuraText(buff)
    local target = buff.target
    return target.name or (target.spellId and tostring(target.spellId)) or ""
end

local function SourceText(buff)
    local source = buff.source
    if not source then
        return ""
    end
    if source.kind == SOURCE_KIND.SPELL then
        return source.name or (source.spellId and tostring(source.spellId)) or ""
    end
    if not source.itemId then
        return ""
    end
    return Item.Name(source.itemId) or tostring(source.itemId)
end

local function TargetChoices()
    return {
        [TARGET_AURA] = Text("settings.target_aura"),
        [WEAPON_SLOT.MAIN_HAND] = Text("buff." .. WEAPON_SLOT.MAIN_HAND),
        [WEAPON_SLOT.OFF_HAND] = Text("buff." .. WEAPON_SLOT.OFF_HAND),
    }
end

local function SourceChoices()
    return {
        [SOURCE_NONE] = Text("settings.source_none"),
        [SOURCE_KIND.SPELL] = Text("settings.source_spell"),
        [SOURCE_KIND.ITEM] = Text("settings.source_item"),
    }
end

local function SelectBuff(index)
    configDialog:SelectGroup(BUFFS_NAME, BUFF_KEY_PREFIX .. index)
end

-- the page of one buff; index -- its place in ns.db.buffs at the time of drawing
local function BuffPage(buff, index, count)
    return {
        type = "group",
        name = Buff.TargetLabel(buff),
        icon = BuffService.Icon(buff),
        order = index,
        args = {
            target = {
                type = "select",
                name = Text("settings.target"),
                values = TargetChoices(),
                sorting = { TARGET_AURA, WEAPON_SLOT.MAIN_HAND, WEAPON_SLOT.OFF_HAND },
                get = function()
                    return buff.target.weapon or TARGET_AURA
                end,
                set = function(_, value)
                    if value == TARGET_AURA then
                        buff.target = {}
                    else
                        buff.target = { weapon = value }
                    end
                    Changed()
                end,
                order = 1,
            },
            aura = {
                type = "input",
                name = Text("settings.aura"),
                desc = Text("settings.aura_hint"),
                hidden = function()
                    return buff.target.weapon ~= nil
                end,
                get = function()
                    return AuraText(buff)
                end,
                set = function(_, value)
                    value = Trim(value)
                    if value == "" then
                        buff.target = {}
                    else
                        buff.target = BuffParser.ParseSpell(value)
                    end
                    Changed()
                end,
                width = "double",
                order = 2,
            },
            sourceKind = {
                type = "select",
                name = Text("settings.source"),
                values = SourceChoices(),
                sorting = { SOURCE_NONE, SOURCE_KIND.SPELL, SOURCE_KIND.ITEM },
                get = function()
                    return buff.source and buff.source.kind or SOURCE_NONE
                end,
                set = function(_, value)
                    if value == SOURCE_NONE then
                        buff.source = nil
                    elseif value == SOURCE_KIND.SPELL and not buff.target.weapon then
                        -- most buffs are cast by the spell of the same name
                        buff.source = { kind = SOURCE_KIND.SPELL, spellId = buff.target.spellId, name = buff.target.name }
                    else
                        buff.source = { kind = value }
                    end
                    Changed()
                end,
                order = 3,
            },
            sourceValue = {
                type = "input",
                name = function()
                    if buff.source and buff.source.kind == SOURCE_KIND.ITEM then
                        return Text("settings.source_item_value")
                    end
                    return Text("settings.source_spell_value")
                end,
                desc = Text("settings.source_hint"),
                hidden = function()
                    return buff.source == nil
                end,
                get = function()
                    return SourceText(buff)
                end,
                validate = function(_, value)
                    value = Trim(value)
                    local isItem = buff.source and buff.source.kind == SOURCE_KIND.ITEM
                    if isItem and value ~= "" and not BuffParser.ParseItemId(value) then
                        return Text("messages.unknown_item")
                    end
                    return true
                end,
                set = function(_, value)
                    value = Trim(value)
                    local kind = buff.source.kind
                    if value == "" then
                        buff.source = { kind = kind }
                    elseif kind == SOURCE_KIND.ITEM then
                        buff.source = { kind = kind, itemId = BuffParser.ParseItemId(value) }
                    else
                        local spell = BuffParser.ParseSpell(value)
                        buff.source = { kind = kind, spellId = spell.spellId, name = spell.name }
                    end
                    Changed()
                end,
                width = "double",
                order = 4,
            },
            icon = {
                type = "input",
                name = Text("settings.icon"),
                desc = Text("settings.icon_hint"),
                -- suggestions with pictures while typing a name (ui/ace_suggest_edit_box.lua)
                dialogControl = ns.UI.SUGGEST_EDIT_BOX,
                arg = ns.Dataflows.IconSearch.Search,
                get = function()
                    return buff.iconText or ""
                end,
                validate = function(_, value)
                    value = Trim(value)
                    if value ~= "" and not BuffParser.ParseIcon(value) then
                        return Text("messages.unknown_icon")
                    end
                    return true
                end,
                set = function(_, value)
                    value = Trim(value)
                    if value == "" then
                        buff.icon = nil
                        buff.iconText = nil
                    else
                        buff.icon = BuffParser.ParseIcon(value)
                        buff.iconText = value
                    end
                    Changed()
                end,
                width = "double",
                order = 4.5,
            },
            dragHint = {
                type = "description",
                name = "\n" .. Text("settings.drag_hint") .. "\n",
                order = 5,
            },
            moveUp = {
                type = "execute",
                name = Text("settings.move_up"),
                disabled = function()
                    return index == 1
                end,
                func = function()
                    BuffService.Move(index, -1)
                    Changed()
                    SelectBuff(index - 1)
                end,
                width = "half",
                order = 10,
            },
            moveDown = {
                type = "execute",
                name = Text("settings.move_down"),
                disabled = function()
                    return index == count
                end,
                func = function()
                    BuffService.Move(index, 1)
                    Changed()
                    SelectBuff(index + 1)
                end,
                width = "half",
                order = 11,
            },
            remove = {
                type = "execute",
                name = Text("settings.remove"),
                confirm = true,
                confirmText = Text("settings.remove_confirm", Buff.TargetLabel(buff)),
                func = function()
                    BuffService.Remove(index)
                    Changed()
                end,
                order = 12,
            },
        },
    }
end

local function BuffsPage()
    local buffs = BuffService.List()
    local page = {
        type = "group",
        name = Text("settings.buffs_window", ns.Constants.ADDON_TITLE),
        childGroups = "tree",
        args = {
            intro = {
                type = "description",
                name = Text("settings.buffs_intro") .. "\n",
                fontSize = "medium",
                order = 1,
            },
            add = {
                type = "execute",
                name = Text("settings.add"),
                func = function()
                    BuffService.Add(Buff.New({}, nil))
                    Changed()
                    SelectBuff(#BuffService.List())
                end,
                order = 2,
            },
        },
    }
    for index, buff in ipairs(buffs) do
        page.args[BUFF_KEY_PREFIX .. index] = BuffPage(buff, index, #buffs)
    end
    return page
end

-- The addon page and the buffs page in Options -> AddOns. Once, after the
-- settings are loaded (PLAYER_LOGIN).
function SettingsWindow.Setup()
    if categoryId or panelFrame then return end
    configRegistry:RegisterOptionsTable(OPTIONS_NAME, GeneralPage)
    configRegistry:RegisterOptionsTable(BUFFS_NAME, BuffsPage)
    configDialog:SetDefaultSize(BUFFS_NAME, BUFF_WINDOW_WIDTH, BUFF_WINDOW_HEIGHT)

    panelFrame, categoryId = configDialog:AddToBlizOptions(OPTIONS_NAME, ns.Constants.ADDON_TITLE)
end

function SettingsWindow.IsBuffWindowOpen()
    return configDialog.OpenFrames[BUFFS_NAME] ~= nil
end

function SettingsWindow.OpenBuffs()
    configDialog:Open(BUFFS_NAME)
end

-- the buff window: open it, or close it when it is open
function SettingsWindow.ToggleBuffs()
    if SettingsWindow.IsBuffWindowOpen() then
        configDialog:Close(BUFFS_NAME)
        return
    end
    SettingsWindow.OpenBuffs()
end

-- The AceGUI edit box of the buff window being typed in now, the key of its
-- option and the buff of its page; nil -- none.
local function FocusedBuffField()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    local widget = focus and focus.obj
    if not (widget and widget.GetUserDataTable) then
        return nil
    end
    local user = widget:GetUserDataTable()
    if user.appName ~= BUFFS_NAME or not user.path then
        return nil
    end
    local optionKey = user.path[#user.path]
    if not LINK_FIELDS[optionKey] then
        return nil
    end
    local buffIndex = tonumber((user.path[1] or ""):match("^" .. BUFF_KEY_PREFIX .. "(%d+)$"))
    local buff = buffIndex and BuffService.List()[buffIndex]
    if not buff then
        return nil
    end
    return widget, optionKey, buff
end

-- as if typed into the field and confirmed with Enter: the option's validate and set run
local function Confirm(widget, text)
    widget:SetText(text)
    widget:Fire("OnEnterPressed", text)
    LibStub("AceGUI-3.0"):ClearFocus()
end

-- A shift-clicked link (an item from the bags, a spell from the spellbook)
-- while a field of the buff window is in focus: the item field takes an item,
-- the buff and spell fields take a spell. AceGUI itself has already inserted
-- the link at the cursor: a link the field does not take is undone.
function SettingsWindow.PickLink(link)
    local widget, optionKey, buff = FocusedBuffField()
    if not widget then
        return
    end
    local isItemLink = link:find("|Hitem:") ~= nil
    local isSpellLink = link:find("|Hspell:") ~= nil
    local isIconField = optionKey == "icon"
    local isItemField = optionKey == "sourceValue" and buff.source and buff.source.kind == SOURCE_KIND.ITEM
    local isSpellField = not isIconField and not isItemField
    local isTaken = (isIconField and (isItemLink or isSpellLink))
        or (isItemField and isItemLink)
        or (isSpellField and isSpellLink)
    if isTaken then
        Confirm(widget, link)
        return
    end
    if optionKey == "aura" then
        widget:SetText(AuraText(buff))
    elseif isIconField then
        widget:SetText(buff.iconText or "")
    else
        widget:SetText(SourceText(buff))
    end
end

-- A shift-click on a buff of the player. Into the buff field being typed in --
-- as if typed and confirmed with Enter (the option's validate and set run); with
-- no such field but the buff window open -- a new buff with this aura.
-- Returns whether the click was used.
function SettingsWindow.PickAura(spellId, name)
    local widget, optionKey = FocusedBuffField()
    if widget then
        -- the icon field wants the exact spell: its id; the others -- the name (every rank)
        if optionKey == "icon" and spellId then
            Confirm(widget, tostring(spellId))
        else
            Confirm(widget, name or tostring(spellId))
        end
        return true
    end
    if not SettingsWindow.IsBuffWindowOpen() then
        return false
    end
    -- already tracked: show its page instead of a second copy
    for index, buff in ipairs(BuffService.List()) do
        local target = buff.target
        local isSameSpell = spellId ~= nil and target.spellId == spellId
        local isSameName = name ~= nil and target.name ~= nil and target.name:lower() == name:lower()
        if isSameSpell or isSameName then
            SelectBuff(index)
            return true
        end
    end
    BuffService.Add(Buff.New({ spellId = spellId, name = name }, nil))
    Changed()
    SelectBuff(#BuffService.List())
    return true
end

-- Open the game settings on our page; a second call closes them.
function SettingsWindow.Toggle()
    local isOpen = SettingsPanel and SettingsPanel:IsShown()
    if isOpen then
        HideUIPanel(SettingsPanel)
        return
    end
    if Settings and Settings.OpenToCategory and categoryId then
        Settings.OpenToCategory(categoryId)
        return
    end
    if InterfaceOptionsFrame_OpenToCategory and panelFrame then
        InterfaceOptionsFrame_OpenToCategory(panelFrame)
    end
end
