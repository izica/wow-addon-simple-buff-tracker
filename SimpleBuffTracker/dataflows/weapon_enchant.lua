-- weapon_enchant.lua -- temporary enchants on the weapons (oils, stones, poisons,
-- weapon spells): they are not auras, the client tells about them by GetWeaponEnchantInfo.
--
-- The client gives only the time left, not the full duration: the longest time
-- left seen for the same enchant is taken as its duration, for the timer swipe.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Secrets = ns.Utilities.Secrets
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT

local WeaponEnchant = {}
ns.Dataflows.WeaponEnchant = WeaponEnchant

local MILLISECONDS_PER_SECOND = 1000

local longestSeen = {}   -- [slot] = { enchantId, seconds }

local function Plain(value)
    if Secrets.IsSecret(value) then
        return nil
    end
    return value
end

local function Describe(slot, hasEnchant, millisecondsLeft, charges, enchantId, now)
    if not Plain(hasEnchant) then
        return nil
    end
    local secondsLeft = (Plain(millisecondsLeft) or 0) / MILLISECONDS_PER_SECOND
    enchantId = Plain(enchantId)

    local seen = longestSeen[slot]
    local isSameEnchant = seen and seen.enchantId == enchantId
    if not isSameEnchant or secondsLeft > seen.seconds then
        seen = { enchantId = enchantId, seconds = secondsLeft }
        longestSeen[slot] = seen
    end

    return {
        expirationTime = now + secondsLeft,
        duration = seen.seconds,
        charges = Plain(charges) or 0,
    }
end

-- { mainhand = enchant or nil, offhand = enchant or nil },
-- enchant = { expirationTime, duration, charges }
function WeaponEnchant.Read(now)
    if not GetWeaponEnchantInfo then
        return {}
    end
    local ok, hasMainHand, mainHandLeft, mainHandCharges, mainHandEnchantId,
        hasOffHand, offHandLeft, offHandCharges, offHandEnchantId = pcall(GetWeaponEnchantInfo)
    if not ok then
        return {}
    end
    local result = {}
    result[WEAPON_SLOT.MAIN_HAND] = Describe(WEAPON_SLOT.MAIN_HAND, hasMainHand, mainHandLeft,
        mainHandCharges, mainHandEnchantId, now)
    result[WEAPON_SLOT.OFF_HAND] = Describe(WEAPON_SLOT.OFF_HAND, hasOffHand, offHandLeft,
        offHandCharges, offHandEnchantId, now)
    return result
end
