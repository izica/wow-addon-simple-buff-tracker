-- weapon_enchant.lua -- temporary enchants on the weapons (oils, stones, poisons,
-- weapon spells): they are not auras, the client tells about them by GetWeaponEnchantInfo.
--
-- The client gives only the time left, not the full duration: the longest time
-- left seen for the same enchant is taken as its duration, for the timer swipe.
--
-- Which enchant it is: GetWeaponEnchantInfo gives its id (a different one for
-- every oil and every rank of a weapon spell), the name is only in the weapon's
-- tooltip -- a green line "Brilliant Wizard Oil (30 min)". The client has no
-- line type of its own for it (Enum.TooltipDataLineType knows only permanent
-- enchants), so the line is the green one that ends with the time in brackets
-- and is not a "Use:" / "Equip:" / "Chance on hit:" line. Every enchant seen is
-- kept in ns.db.seenEnchants[id] = name: the buff window offers them, a buff
-- may track one of them (a weapon with oil and a shaman's Flametongue).

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Secrets = ns.Utilities.Secrets
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT
local WEAPON_INVENTORY_SLOT = ns.Constants.WEAPON_INVENTORY_SLOT

local WeaponEnchant = {}
ns.Dataflows.WeaponEnchant = WeaponEnchant

local MILLISECONDS_PER_SECOND = 1000
local GREEN_MIN = 0.8      -- a tooltip line this green, with red and blue under GREEN_OTHER_MAX
local GREEN_OTHER_MAX = 0.2

local longestSeen = {}   -- [slot] = { enchantId, seconds }

local function Plain(value)
    if Secrets.IsSecret(value) then
        return nil
    end
    return value
end

local function IsGreen(color)
    if not (color and color.GetRGB) then
        return false
    end
    local r, g, b = color:GetRGB()
    r = Plain(r)
    g = Plain(g)
    b = Plain(b)
    if not (r and g and b) then
        return false
    end
    return g >= GREEN_MIN and r <= GREEN_OTHER_MAX and b <= GREEN_OTHER_MAX
end

-- "Use:", "Equip:", "Chance on hit:" -- green lines of the item itself
local function IsItemSpellLine(text)
    local prefixes = { ITEM_SPELL_TRIGGER_ONUSE, ITEM_SPELL_TRIGGER_ONEQUIP, ITEM_SPELL_TRIGGER_ONPROC }
    for _, prefix in pairs(prefixes) do
        if prefix and text:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- the name of the temporary enchant from the tooltip of the weapon in the slot; nil -- not found
local function ReadEnchantName(slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then
        return nil
    end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", WEAPON_INVENTORY_SLOT[slot])
    if not (ok and data and data.lines) then
        return nil
    end
    for _, line in ipairs(data.lines) do
        local text = Plain(line.leftText)
        local isCandidate = type(text) == "string" and IsGreen(line.leftColor) and not IsItemSpellLine(text)
        if isCandidate then
            local name = text:match("^(.-)%s*%(.-%)$")
            if name and name ~= "" then
                return name
            end
        end
    end
    return nil
end

-- The name of an enchant: read from the tooltip on every reading out of combat,
-- the remembered one in combat. Read every time, not once: right after a new
-- enchant goes on (oil over Flametongue) the client already gives the new id
-- while the tooltip may still show the old line -- the name read then was
-- wrong, and kept for good it made the oil look missing. A later reading puts
-- the right name over it.
local function EnchantName(slot, enchantId)
    if not enchantId then
        return nil
    end
    local seen = ns.db and ns.db.seenEnchants
    if not InCombatLockdown() then
        local name = ReadEnchantName(slot)
        if name and seen then
            seen[enchantId] = name
        end
        if name then
            return name
        end
    end
    return seen and seen[enchantId]
end

-- the name remembered for an enchant id; nil -- never read
function WeaponEnchant.Name(enchantId)
    local seen = ns.db and ns.db.seenEnchants
    return seen and enchantId and seen[enchantId]
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
        enchantId = enchantId,
        name = EnchantName(slot, enchantId),
    }
end

-- { mainhand = enchant or nil, offhand = enchant or nil },
-- enchant = { expirationTime, duration, charges, enchantId, name }
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

-- every temporary enchant seen on the weapons: { { enchantId, name }, ... } by name
function WeaponEnchant.Seen()
    local result = {}
    for enchantId, name in pairs((ns.db and ns.db.seenEnchants) or {}) do
        table.insert(result, { enchantId = enchantId, name = name })
    end
    table.sort(result, function(a, b)
        return a.name < b.name
    end)
    return result
end

-- does the enchant on the weapon (from Read) count for a weapon target?
-- target.enchantId -- a chosen one: the same id, or another id with the same
-- name (the same oil seen before under its other id); none chosen -- any.
-- The name of the chosen id is the one remembered now (a wrong one read once is
-- corrected later), the name kept in the buff only when there is none.
function WeaponEnchant.Matches(target, enchant)
    if not enchant then
        return false
    end
    if not target.enchantId then
        return true
    end
    if enchant.enchantId == target.enchantId then
        return true
    end
    local targetName = WeaponEnchant.Name(target.enchantId) or target.enchantName
    return targetName ~= nil and enchant.name == targetName
end
