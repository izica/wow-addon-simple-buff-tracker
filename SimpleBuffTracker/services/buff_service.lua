-- buff_service.lua -- the tracked buffs of the character: add, remove, and
-- the state of each one now (active, running out, missing).

local ADDON, ns = ...
ns.Services = ns.Services or {}

local Buff = ns.Models.Buff
local AuraScan = ns.Dataflows.AuraScan
local WeaponEnchant = ns.Dataflows.WeaponEnchant
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
        found = weapons[buff.target.weapon]
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

-- The states of the buffs the panel shows in the current mode, in the order of the list.
function BuffService.VisibleStates()
    local now = GetTime()
    local settings = ns.db.settings
    local weapons = WeaponEnchant.Read(now)
    local onlyMissing = settings.mode == DISPLAY_MODE.MISSING

    local states = {}
    for index, buff in ipairs(ns.db.buffs) do
        local state = Evaluate(buff, index, now, weapons, settings.warnSeconds)
        local isNeeded = not state.isActive or state.isExpiring
        if not onlyMissing or isNeeded then
            table.insert(states, state)
        end
    end
    return states
end
