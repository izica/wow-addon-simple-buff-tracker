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

local function TargetIcon(buff)
    local target = buff.target
    if target.weapon then
        local inventorySlot = ns.Constants.WEAPON_INVENTORY_SLOT[target.weapon]
        return GetInventoryItemTexture and GetInventoryItemTexture("player", inventorySlot)
    end
    return Spell.Icon(target.spellId or target.name)
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

    state.icon = (found and found.icon) or TargetIcon(buff) or Buff.SourceIcon(buff) or QUESTION_MARK_ICON
    local isItemSource = buff.source and buff.source.kind == SOURCE_KIND.ITEM
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
