-- buff_conditions.lua -- whether a buff is to be shown at all now: its show
-- conditions (buff.conditions, models/buff.lua) against the place, the bags and
-- the talents of the character. Every condition set must hold; a buff without
-- conditions is always shown.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Spell = ns.Utilities.Spell
local Item = ns.Utilities.Item
local Talents = ns.Dataflows.Talents

local BuffConditions = {}
ns.Dataflows.BuffConditions = BuffConditions

local WORLD = ns.Constants.INSTANCE_KIND.WORLD

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

local function HasPlaces(places)
    return places ~= nil and next(places) ~= nil
end

-- whether the buff is to be shown now
function BuffConditions.Hold(buff)
    local conditions = buff.conditions
    if not conditions then
        return true
    end
    if HasPlaces(conditions.places) then
        local kind = BuffConditions.InstanceKind()
        if not conditions.places[kind] then
            return false
        end
    end
    if conditions.itemId and Item.Count(conditions.itemId) <= 0 then
        return false
    end
    if conditions.talent then
        local isLearned = BuffConditions.IsLearned(conditions.talent)
        if isLearned == (conditions.talentMissing == true) then
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
    if HasPlaces(conditions.places) then
        count = count + 1
    end
    if conditions.itemId then
        count = count + 1
    end
    if conditions.talent then
        count = count + 1
    end
    return count
end
