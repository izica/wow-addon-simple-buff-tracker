-- buff_conditions.lua -- whether a buff is to be shown at all now: its show
-- conditions (buff.conditions, models/buff.lua) against the place, the bags and
-- the talents of the character. Every condition set must hold; a buff without
-- conditions is always shown.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Spell = ns.Utilities.Spell
local Item = ns.Utilities.Item
local Talents = ns.Dataflows.Talents
local Zones = ns.Dataflows.Zones
local COMBAT_STATE = ns.Constants.COMBAT_STATE

local BuffConditions = {}
ns.Dataflows.BuffConditions = BuffConditions

local WORLD = ns.Constants.INSTANCE_KIND.WORLD

-- In combat by the events (events/conditions.lua), not by InCombatLockdown: the
-- panel is laid out for combat on PLAYER_REGEN_DISABLED, the last moment the
-- client still lets secure icons be shown and hidden, before the lockdown starts.
local isInCombat = false

function BuffConditions.SetInCombat(isInCombatNow)
    isInCombat = isInCombatNow and true or false
end

function BuffConditions.IsInCombat()
    return isInCombat
end

-- where the player is: the instance type ("raid", "pvp", "party", "arena"...),
-- or "world" outside instances
function BuffConditions.InstanceKind()
    if not IsInInstance then
        return WORLD
    end
    local isInInstance, instanceType = IsInInstance()
    if not isInInstance or not instanceType or instanceType == "none" then
        return WORLD
    end
    return instanceType
end

local function IsSpellIdKnown(spellId)
    if IsPlayerSpell and IsPlayerSpell(spellId) then
        return true
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellId) then
        return true
    end
    if IsSpellKnown and IsSpellKnown(spellId) then
        return true
    end
    return false
end

-- Whether the character has the talent or spell { spellId, name }. The talent
-- tree first (by name, every rank); then the spell id; a name alone -- the
-- client finds a spell by name only when the character has it.
function BuffConditions.IsLearned(talent)
    local rank = Talents.Rank(talent.name)
    if rank then
        return rank > 0
    end
    if talent.spellId then
        local ok, isKnown = pcall(IsSpellIdKnown, talent.spellId)
        return ok and isKnown
    end
    if talent.name then
        return Spell.Find(talent.name) ~= nil
    end
    return true
end

local function HasHiddenPlaces(conditions)
    return conditions.hiddenPlaces ~= nil and next(conditions.hiddenPlaces) ~= nil
end

-- Why the buff is not shown now: the key of the text (settings.hidden_*) and
-- its argument; nil -- every condition holds. The buff window tells it.
function BuffConditions.Reason(buff)
    local conditions = buff.conditions
    if not conditions then
        return nil
    end
    -- a place turned off: not there (an arena, a scenario -- not in the list, always shown)
    local kind = BuffConditions.InstanceKind()
    if HasHiddenPlaces(conditions) and conditions.hiddenPlaces[kind] then
        return "settings.hidden_place", ns.Localization.Text("settings.place_" .. kind)
    end
    local zones = conditions.zones
    if zones and #zones > 0 and not Zones.IsHere(zones) then
        return "settings.hidden_zone", Zones.Current().name or "?"
    end
    if conditions.combat == COMBAT_STATE.IN and not isInCombat then
        return "settings.hidden_out_of_combat"
    end
    if conditions.combat == COMBAT_STATE.OUT and isInCombat then
        return "settings.hidden_in_combat"
    end
    local itemId = conditions.itemId
    if itemId and Item.Count(itemId) <= 0 then
        return "settings.hidden_item", Item.Name(itemId) or ("item:" .. itemId)
    end
    local talent = conditions.talent
    if talent then
        local isLearned = BuffConditions.IsLearned(talent)
        local talentName = talent.name or (talent.spellId and Spell.Name(talent.spellId)) or "?"
        if isLearned and conditions.talentMissing then
            return "settings.hidden_learned", talentName
        end
        if not isLearned and not conditions.talentMissing then
            return "settings.hidden_not_learned", talentName
        end
    end
    return nil
end

-- whether the buff is to be shown now
function BuffConditions.Hold(buff)
    return BuffConditions.Reason(buff) == nil
end

-- every place of the list turned off: the buff is never shown (but in an arena)
function BuffConditions.IsNowhere(buff)
    local hiddenPlaces = buff.conditions and buff.conditions.hiddenPlaces
    if not hiddenPlaces then
        return false
    end
    for _, kind in ipairs(ns.Constants.INSTANCE_KINDS) do
        if not hiddenPlaces[kind] then
            return false
        end
    end
    return true
end

-- how many conditions the buff has (the button of the buff window shows it)
function BuffConditions.Count(buff)
    local conditions = buff.conditions
    if not conditions then
        return 0
    end
    local count = 0
    if HasHiddenPlaces(conditions) then
        count = count + 1
    end
    if conditions.itemId then
        count = count + 1
    end
    if conditions.talent then
        count = count + 1
    end
    if conditions.zones and #conditions.zones > 0 then
        count = count + 1
    end
    if conditions.combat then
        count = count + 1
    end
    return count
end
