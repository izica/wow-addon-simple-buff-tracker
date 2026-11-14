-- weapon_enchant.lua -- temporary enchants on the weapons (oils, stones, poisons,
-- weapon spells like the shaman's Flametongue): they are not auras.
--
-- On Forever a weapon can carry an oil AND a weapon spell at once, while
-- GetWeaponEnchantInfo gives only one enchant per hand (seen in the game: oil +
-- Flametongue 5 on the main hand -> only Flametongue's id 1665 and its 60
-- minutes). So the enchants on a weapon are read from its tooltip, every line
-- like "Lesser Wizard Oil (30 min)" -- found by the client's own formats
-- ITEM_ENCHANT_TIME_LEFT_HOURS / _MIN / _SEC (translated with the client), each
-- with its name and time left. GetWeaponEnchantInfo still tells the id and the
-- exact time of one of them: it is tied to the line whose time left is the
-- closest, and ns.db.seenEnchants[id] = name is kept from that (a name taken
-- from the first line of two was wrong). Every name seen goes into
-- ns.db.seenEnchantNames: the buff window offers them.
--
-- The tooltip is read out of combat only; in combat the last lines count down
-- by the clock. The full duration is not given: the longest time left seen for
-- a name is taken as its duration, for the timer swipe.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Secrets = ns.Utilities.Secrets
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT
local WEAPON_INVENTORY_SLOT = ns.Constants.WEAPON_INVENTORY_SLOT

local WeaponEnchant = {}
ns.Dataflows.WeaponEnchant = WeaponEnchant

local MILLISECONDS_PER_SECOND = 1000
local SECONDS_PER_MINUTE = 60
-- the API's exact time and a line's rounded one (minutes) belong together within this
local TIE_TOLERANCE_SECONDS = 90
local SLOTS = { WEAPON_SLOT.MAIN_HAND, WEAPON_SLOT.OFF_HAND }

local linesBySlot = {}    -- [slot] = { { name, expirationTime }, ... } -- the last tooltip reading
local longestSeen = {}    -- [name] = the longest time left seen, seconds

local function Plain(value)
    if Secrets.IsSecret(value) then
        return nil
    end
    return value
end

-- A client format like "%s (%d min)" as a Lua pattern catching the name and the number.
local function FormatToPattern(format)
    local text = format:gsub("%%s", "\002")
    text = text:gsub("%%d", "\003")
    text = text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    text = text:gsub("\002", "(.-)")
    text = text:gsub("\003", "(%%d+)")
    return "^" .. text .. "$"
end

-- A grammar token "|4hour:hrs;" (singular:plural) gives a format for each of its
-- words: "%s (%d hour)" and "%s (%d hrs)" -- exact words, so "30 min" is not hours.
local function FormatVariants(format)
    local first, singular, plural, rest = format:match("^(.-)|4([^:;]*):([^;]*);(.*)$")
    if not first then
        return { format }
    end
    return { first .. singular .. rest, first .. plural .. rest }
end

-- { { pattern, seconds per unit }, ... } from the client's formats; built on first use
local timePatterns = nil

local function TimePatterns()
    if timePatterns then
        return timePatterns
    end
    timePatterns = {}
    local formats = {
        { ITEM_ENCHANT_TIME_LEFT_DAYS, 86400 },
        { ITEM_ENCHANT_TIME_LEFT_HOURS, 3600 },
        { ITEM_ENCHANT_TIME_LEFT_MIN, SECONDS_PER_MINUTE },
        { ITEM_ENCHANT_TIME_LEFT_SEC, 1 },
    }
    for _, entry in ipairs(formats) do
        if type(entry[1]) == "string" then
            for _, variant in ipairs(FormatVariants(entry[1])) do
                table.insert(timePatterns, { pattern = FormatToPattern(variant), seconds = entry[2] })
            end
        end
    end
    -- a client without the formats: "Name (30 something)", taken as minutes
    if #timePatterns == 0 then
        table.insert(timePatterns, { pattern = "^(.-)%s*%((%d+)[^%)]*%)$", seconds = SECONDS_PER_MINUTE })
    end
    return timePatterns
end

-- a tooltip line -> the enchant name and its seconds left; nil -- not an enchant line
local function ParseLine(text)
    for _, entry in ipairs(TimePatterns()) do
        local name, number = text:match(entry.pattern)
        if name and number and name ~= "" then
            return name, tonumber(number) * entry.seconds
        end
    end
    return nil
end

-- the enchant lines of the weapon's tooltip: { { name, seconds }, ... }; nil -- no tooltip
local function ReadTooltipLines(slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then
        return nil
    end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", WEAPON_INVENTORY_SLOT[slot])
    if not (ok and data and data.lines) then
        return nil
    end
    local result = {}
    for _, line in ipairs(data.lines) do
        local text = Plain(line.leftText)
        if type(text) == "string" then
            local name, seconds = ParseLine(text)
            if name then
                table.insert(result, { name = name, seconds = seconds })
            end
        end
    end
    return result
end

local function Remember(enchantId, name)
    if not ns.db then
        return
    end
    if enchantId then
        ns.db.seenEnchants[enchantId] = name
    end
    ns.db.seenEnchantNames[name] = true
end

-- the enchants on one weapon: { { name, enchantId, expirationTime, duration }, ... }
local function ReadSlot(slot, hasEnchant, millisecondsLeft, enchantId, now)
    local apiEnchant = nil
    if Plain(hasEnchant) then
        apiEnchant = {
            enchantId = Plain(enchantId),
            secondsLeft = (Plain(millisecondsLeft) or 0) / MILLISECONDS_PER_SECOND,
        }
    end

    if not InCombatLockdown() then
        local lines = ReadTooltipLines(slot)
        if lines then
            local kept = {}
            for _, line in ipairs(lines) do
                table.insert(kept, { name = line.name, expirationTime = now + line.seconds })
                Remember(nil, line.name)
            end
            linesBySlot[slot] = kept
        end
    end

    local enchants = {}
    for _, line in ipairs(linesBySlot[slot] or {}) do
        if line.expirationTime > now then
            table.insert(enchants, { name = line.name, expirationTime = line.expirationTime })
        end
    end

    -- the API's enchant: the line with the closest time left is it
    if apiEnchant then
        local closest = nil
        local closestGap = TIE_TOLERANCE_SECONDS
        for _, enchant in ipairs(enchants) do
            local gap = math.abs((enchant.expirationTime - now) - apiEnchant.secondsLeft)
            if gap <= closestGap then
                closest = enchant
                closestGap = gap
            end
        end
        if closest then
            closest.enchantId = apiEnchant.enchantId
            closest.expirationTime = now + apiEnchant.secondsLeft
            if not InCombatLockdown() then
                Remember(apiEnchant.enchantId, closest.name)
            end
        else
            -- no tooltip lines for it (no tooltip API, or not read yet): by its remembered name
            local seen = ns.db and ns.db.seenEnchants
            table.insert(enchants, {
                name = seen and apiEnchant.enchantId and seen[apiEnchant.enchantId],
                enchantId = apiEnchant.enchantId,
                expirationTime = now + apiEnchant.secondsLeft,
            })
        end
    end

    for _, enchant in ipairs(enchants) do
        local secondsLeft = enchant.expirationTime - now
        local key = enchant.name or tostring(enchant.enchantId)
        if secondsLeft > (longestSeen[key] or 0) then
            longestSeen[key] = secondsLeft
        end
        enchant.duration = longestSeen[key]
    end
    if #enchants == 0 then
        return nil
    end
    return enchants
end

-- { mainhand = enchants or nil, offhand = enchants or nil },
-- enchants = { { name, enchantId (only for the one GetWeaponEnchantInfo gives), expirationTime, duration }, ... }
function WeaponEnchant.Read(now)
    local hasMainHand, mainHandLeft, mainHandEnchantId
    local hasOffHand, offHandLeft, offHandEnchantId
    if GetWeaponEnchantInfo then
        local ok, mainHas, mainLeft, _, mainId, offHas, offLeft, _, offId = pcall(GetWeaponEnchantInfo)
        if ok then
            hasMainHand = mainHas
            mainHandLeft = mainLeft
            mainHandEnchantId = mainId
            hasOffHand = offHas
            offHandLeft = offLeft
            offHandEnchantId = offId
        end
    end
    local result = {}
    result[WEAPON_SLOT.MAIN_HAND] = ReadSlot(WEAPON_SLOT.MAIN_HAND, hasMainHand, mainHandLeft, mainHandEnchantId, now)
    result[WEAPON_SLOT.OFF_HAND] = ReadSlot(WEAPON_SLOT.OFF_HAND, hasOffHand, offHandLeft, offHandEnchantId, now)
    return result
end

-- the name of the enchant a weapon target tracks; nil -- any enchant.
-- A target chosen by id (older buffs) takes the name remembered for the id now:
-- a wrong one read once is corrected later.
function WeaponEnchant.TargetName(target)
    local seen = ns.db and ns.db.seenEnchants
    if target.enchantId and seen and seen[target.enchantId] then
        return seen[target.enchantId]
    end
    return target.enchantName
end

-- The enchant on the weapon that counts for a weapon target (from Read), or nil:
-- a chosen one -- the line with its name (or its id); none chosen -- any enchant,
-- the one the API gives first.
function WeaponEnchant.Find(target, enchants)
    if not enchants then
        return nil
    end
    local wantedName = WeaponEnchant.TargetName(target)
    if not (wantedName or target.enchantId) then
        for _, enchant in ipairs(enchants) do
            if enchant.enchantId then
                return enchant
            end
        end
        return enchants[1]
    end
    for _, enchant in ipairs(enchants) do
        local isSameName = wantedName ~= nil and enchant.name == wantedName
        local isSameId = target.enchantId ~= nil and enchant.enchantId == target.enchantId
        if isSameName or isSameId then
            return enchant
        end
    end
    return nil
end

-- every enchant name seen on the weapons, sorted
function WeaponEnchant.SeenNames()
    local names = {}
    local isListed = {}
    local function add(name)
        if name and not isListed[name] then
            isListed[name] = true
            table.insert(names, name)
        end
    end
    if ns.db then
        for name in pairs(ns.db.seenEnchantNames) do
            add(name)
        end
        for _, name in pairs(ns.db.seenEnchants) do
            add(name)
        end
    end
    table.sort(names)
    return names
end

-- For /sbt debug: the enchant lines of both weapon tooltips and what the API gives. Diagnostics, English.
function WeaponEnchant.DebugLines()
    local lines = {}
    for _, slot in ipairs(SLOTS) do
        local tooltipLines = ReadTooltipLines(slot)
        if not tooltipLines then
            table.insert(lines, slot .. " tooltip: none")
        else
            for _, line in ipairs(tooltipLines) do
                table.insert(lines, slot .. " tooltip enchant: " .. line.name .. " " .. line.seconds .. "s")
            end
        end
    end
    return lines
end
