-- buff_service.lua -- the tracked buffs of the character: add, remove, and
-- the state of each one now (active, running out, missing).

local ADDON, ns = ...
ns.Services = ns.Services or {}

local Buff = ns.Models.Buff
local AuraScan = ns.Dataflows.AuraScan
local WeaponEnchant = ns.Dataflows.WeaponEnchant
local BuffParser = ns.Dataflows.BuffParser
local BuffConditions = ns.Dataflows.BuffConditions
local Spell = ns.Utilities.Spell
local Item = ns.Utilities.Item
local SOURCE_KIND = ns.Constants.SOURCE_KIND
local DISPLAY_MODE = ns.Constants.DISPLAY_MODE

local BuffService = {}
ns.Services.Buff = BuffService

local QUESTION_MARK_ICON = 134400   -- Interface\Icons\INV_Misc_QuestionMark

function BuffService.List()
    return ns.db.buffs
end

function BuffService.Add(buff)
    table.insert(ns.db.buffs, buff)
end

-- index from the list of /sbt list; returns the removed buff or nil
function BuffService.Remove(index)
    if not ns.db.buffs[index] then
        return nil
    end
    return table.remove(ns.db.buffs, index)
end

-- swap the buff with its neighbour: offset -1 -- up the list, 1 -- down; false -- no neighbour
function BuffService.Move(index, offset)
    local buffs = ns.db.buffs
    local otherIndex = index + offset
    if not (buffs[index] and buffs[otherIndex]) then
        return false
    end
    local moved = buffs[index]
    buffs[index] = buffs[otherIndex]
    buffs[otherIndex] = moved
    return true
end

-- take the buff out of its place and put it at toIndex (the list dragged in
-- the buff window); false -- no such places
function BuffService.MoveTo(fromIndex, toIndex)
    local buffs = ns.db.buffs
    local isValid = buffs[fromIndex] ~= nil and toIndex >= 1 and toIndex <= #buffs
    if not isValid or fromIndex == toIndex then
        return false
    end
    local moved = table.remove(buffs, fromIndex)
    table.insert(buffs, toIndex, moved)
    return true
end

-- Edits from the buff window. Each takes what the player typed (trimmed); the
-- ones that can fail return nil and the key of the error text, else true.

-- what is tracked: "aura" or a weapon slot (ns.Constants.WEAPON_SLOT)
function BuffService.SetTargetKind(buff, kind)
    if kind == "aura" then
        if buff.target.weapon then
            buff.target = {}
        end
        return
    end
    buff.target = { weapon = kind }
end

-- which temporary enchant a weapon buff tracks: a name from WeaponEnchant.SeenNames;
-- nil -- any enchant on the slot. Chosen by name: a weapon may carry two
-- enchants, and the client gives the id of only one of them.
function BuffService.SetEnchant(buff, enchantName)
    if not buff.target.weapon then
        return
    end
    buff.target.enchantId = nil
    buff.target.enchantName = enchantName
end

-- the aura: a name, a spell id or a spell link; empty -- none yet
function BuffService.SetAuraText(buff, text)
    if text == "" then
        buff.target = {}
        return
    end
    buff.target = BuffParser.ParseSpell(text)
end

-- how a click puts it back: "none", "spell" or "item"
function BuffService.SetSourceKind(buff, kind)
    local currentKind = buff.source and buff.source.kind
    if kind == currentKind then
        return
    end
    if kind == "none" then
        buff.source = nil
    elseif kind == SOURCE_KIND.SPELL and not buff.target.weapon then
        -- most buffs are cast by the spell of the same name
        buff.source = { kind = SOURCE_KIND.SPELL, spellId = buff.target.spellId, name = buff.target.name }
    else
        buff.source = { kind = kind }
    end
end

-- the spell or item of the source, by the kind already chosen
function BuffService.SetSourceText(buff, text)
    local kind = buff.source and buff.source.kind
    if not kind then
        return true
    end
    if text == "" then
        buff.source = { kind = kind }
        return true
    end
    if kind == SOURCE_KIND.ITEM then
        local itemId = BuffParser.ParseItemId(text)
        if not itemId then
            return nil, "messages.unknown_item"
        end
        buff.source = { kind = kind, itemId = itemId }
        return true
    end
    local spell = BuffParser.ParseSpell(text)
    buff.source = { kind = kind, spellId = spell.spellId, name = spell.name }
    return true
end

-- a picture of its own; empty -- automatic again
function BuffService.SetIconText(buff, text)
    if text == "" then
        buff.icon = nil
        buff.iconText = nil
        return true
    end
    local icon = BuffParser.ParseIcon(text)
    if not icon then
        return nil, "messages.unknown_icon"
    end
    buff.icon = icon
    buff.iconText = text
    return true
end

-- Show conditions (buff.conditions, models/buff.lua). An empty conditions
-- table is dropped: the buff is shown always again.
local function Conditions(buff)
    buff.conditions = buff.conditions or {}
    return buff.conditions
end

local function DropEmptyConditions(buff)
    local conditions = buff.conditions
    if not conditions then
        return
    end
    if conditions.places and next(conditions.places) == nil then
        conditions.places = nil
    end
    if not conditions.talent then
        conditions.talentMissing = nil
    end
    if next(conditions) == nil then
        buff.conditions = nil
    end
end

-- shown in instances of that kind (ns.Constants.INSTANCE_KIND) or not
function BuffService.SetConditionPlace(buff, kind, isOn)
    local conditions = Conditions(buff)
    conditions.places = conditions.places or {}
    conditions.places[kind] = isOn or nil
    DropEmptyConditions(buff)
end

-- only while this item is in the bags: a name, id or link; empty -- no such condition
function BuffService.SetConditionItemText(buff, text)
    if text == "" then
        Conditions(buff).itemId = nil
        DropEmptyConditions(buff)
        return true
    end
    local itemId = BuffParser.ParseItemId(text)
    if not itemId then
        return nil, "messages.unknown_item"
    end
    Conditions(buff).itemId = itemId
    return true
end

-- only while a talent or spell is learned: a name, id or link; empty -- no such condition
function BuffService.SetConditionTalentText(buff, text)
    if text == "" then
        Conditions(buff).talent = nil
        DropEmptyConditions(buff)
        return true
    end
    Conditions(buff).talent = BuffParser.ParseTalent(text)
    return true
end

-- the talent condition the other way round: only while it is not learned
function BuffService.SetConditionTalentMissing(buff, isMissing)
    if not (buff.conditions and buff.conditions.talent) then
        return
    end
    buff.conditions.talentMissing = isMissing or nil
end

function BuffService.ConditionItemText(buff)
    local itemId = buff.conditions and buff.conditions.itemId
    if not itemId then
        return ""
    end
    return Item.Name(itemId) or tostring(itemId)
end

function BuffService.ConditionTalentText(buff)
    local talent = buff.conditions and buff.conditions.talent
    if not talent then
        return ""
    end
    return talent.name or (talent.spellId and tostring(talent.spellId)) or ""
end

-- what the fields show: the aura, the spell or item of the source
function BuffService.AuraText(buff)
    local target = buff.target
    return target.name or (target.spellId and tostring(target.spellId)) or ""
end

function BuffService.SourceText(buff)
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

local function TargetIcon(buff)
    local target = buff.target
    if target.weapon then
        local inventorySlot = ns.Constants.WEAPON_INVENTORY_SLOT[target.weapon]
        return GetInventoryItemTexture and GetInventoryItemTexture("player", inventorySlot)
    end
    return target.icon or Spell.Icon(target.spellId or target.name)
end

-- A buff typed by name ("Well Fed") has no spell the client knows by that name:
-- the first time it is seen on the player its spell id and picture are kept.
local hasLearnedIcons = false   -- a picture was kept since the last TakeLearnedIcons

local function RememberAura(target, aura)
    if aura.icon and target.icon ~= aura.icon then
        target.icon = aura.icon
        hasLearnedIcons = true
    end
    if aura.spellId and not target.spellId then
        target.spellId = aura.spellId
    end
end

-- whether a buff got its picture since the last call: the buff window shows
-- pictures and redraws only when told
function BuffService.TakeLearnedIcons()
    local result = hasLearnedIcons
    hasLearnedIcons = false
    return result
end

-- the picture of a buff that is not on the player: of its spell, of the
-- weapon, of its source, or a question mark
function BuffService.Icon(buff)
    return buff.icon or TargetIcon(buff) or Buff.SourceIcon(buff) or QUESTION_MARK_ICON
end

-- The state of one buff now:
-- { buff, index, isActive, isExpiring, expirationTime, duration, icon, itemCount, action }
-- expirationTime 0 -- active without an end (an aura without a timer).
local function Evaluate(buff, index, now, weapons, warnSeconds)
    local found = nil
    if buff.target.weapon then
        -- a chosen enchant: only that one on the weapon counts, any other does not
        found = WeaponEnchant.Find(buff.target, weapons[buff.target.weapon])
    else
        found = AuraScan.Find(buff.target, now)
        if found then
            RememberAura(buff.target, found)
        end
    end

    local state = {
        buff = buff,
        index = index,
        isActive = found ~= nil,
        isExpiring = false,
        expirationTime = 0,
        duration = 0,
        action = Buff.Action(buff),
    }
    if found then
        state.expirationTime = found.expirationTime
        state.duration = found.duration
        local hasTimer = found.expirationTime > 0
        local isLongerThanWarning = found.duration > warnSeconds
        local secondsLeft = found.expirationTime - now
        state.isExpiring = hasTimer and isLongerThanWarning and secondsLeft <= warnSeconds
    end

    -- a picture picked in the buff window wins over the one of the aura
    state.icon = buff.icon or (found and found.icon) or BuffService.Icon(buff)
    local isItemSource = Buff.HasCompleteSource(buff) and buff.source.kind == SOURCE_KIND.ITEM
    if isItemSource then
        state.itemCount = Item.Count(buff.source.itemId)
    end
    return state
end

-- The states of the buffs the panel shows in the current mode, in the order of
-- the list; a buff whose show conditions do not hold is left out.
function BuffService.VisibleStates()
    local now = GetTime()
    local settings = ns.db.settings
    local weapons = WeaponEnchant.Read(now)
    local onlyMissing = settings.mode == DISPLAY_MODE.MISSING

    local states = {}
    for index, buff in ipairs(ns.db.buffs) do
        -- not here, no item, no talent: not shown in any mode
        if BuffConditions.Hold(buff) then
            -- a buff's own warning time, or the panel's
            local warnSeconds = buff.warnSeconds or settings.warnSeconds
            local state = Evaluate(buff, index, now, weapons, warnSeconds)
            local isNeeded = not state.isActive or state.isExpiring
            if not onlyMissing or isNeeded then
                table.insert(states, state)
            end
        end
    end
    return states
end
