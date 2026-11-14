-- aura_scan.lua -- the buffs on the player, read while the client lets addons see them.
--
-- In combat (and in some places) Forever hides auras from addons, and looking
-- through them one by one then is an error of the client (utilities/secrets.lua).
-- So the buffs are read only while they are visible, and the last reading is
-- kept: a buff seen before combat keeps its plain expiration time, its timer
-- still runs out by the clock.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Secrets = ns.Utilities.Secrets

local AuraScan = {}
ns.Dataflows.AuraScan = AuraScan

local MAX_AURAS = 255

-- { bySpellId = { [id] = aura }, byName = { [lower name] = aura } },
-- aura = { spellId, name, icon, expirationTime, duration } -- plain numbers only
local current = { bySpellId = {}, byName = {} }

local function Plain(value)
    if Secrets.IsSecret(value) then
        return nil
    end
    return value
end

local function ReadAura(index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
    end
    if not UnitAura then
        return nil
    end
    local name, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitAura("player", index, "HELPFUL")
    if not name then
        return nil
    end
    return { name = name, icon = icon, duration = duration, expirationTime = expirationTime, spellId = spellId }
end

local function ReadAll()
    local result = { bySpellId = {}, byName = {} }
    for index = 1, MAX_AURAS do
        local data = ReadAura(index)
        if not data then
            break
        end
        local aura = {
            spellId = Plain(data.spellId),
            name = Plain(data.name),
            icon = Plain(data.icon),
            expirationTime = Plain(data.expirationTime) or 0,
            duration = Plain(data.duration) or 0,
        }
        if aura.spellId then
            result.bySpellId[aura.spellId] = aura
        end
        if aura.name then
            result.byName[aura.name:lower()] = aura
        end
    end
    return result
end

local lastError = nil   -- why the last reading failed, for /sbt debug

-- Reads the buffs again if the client shows them now; returns whether it did.
function AuraScan.Update()
    if Secrets.AurasHidden() then
        return false
    end
    local ok, result = pcall(ReadAll)
    if not ok then
        lastError = tostring(result)
        return false
    end
    lastError = nil
    current = result
    return true
end

local function DescribeValue(value)
    if Secrets.IsSecret(value) then
        return "<secret>"
    end
    return tostring(value)
end

-- For /sbt debug: what the client gives for every buff on the player right now
-- (secret values marked), and what the last reading kept. Diagnostics, English.
function AuraScan.DebugLines()
    local lines = {}
    table.insert(lines, "auras hidden now: " .. tostring(Secrets.AurasHidden())
        .. ", last error: " .. tostring(lastError))
    if Secrets.AurasHidden() then
        return lines
    end
    for index = 1, MAX_AURAS do
        local ok, data = pcall(ReadAura, index)
        if not ok then
            table.insert(lines, index .. ": error " .. tostring(data))
            break
        end
        if not data then
            break
        end
        table.insert(lines, index .. ": name=" .. DescribeValue(data.name)
            .. " spellId=" .. DescribeValue(data.spellId)
            .. " icon=" .. DescribeValue(data.icon)
            .. " duration=" .. DescribeValue(data.duration))
    end
    local keptCount = 0
    for _ in pairs(current.byName) do
        keptCount = keptCount + 1
    end
    table.insert(lines, "kept by name: " .. keptCount)
    return lines
end

-- The aura of a target ({ spellId, name }) from the last reading; nil -- not on
-- the player. An aura already past its expiration time counts as gone.
function AuraScan.Find(target, now)
    local aura = nil
    if target.spellId then
        aura = current.bySpellId[target.spellId]
    end
    if not aura and target.name then
        aura = current.byName[target.name:lower()]
    end
    if not aura then
        return nil
    end
    local hasExpired = aura.expirationTime > 0 and aura.expirationTime <= now
    if hasExpired then
        return nil
    end
    return aura
end
