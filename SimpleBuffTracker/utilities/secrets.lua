-- secrets.lua -- what the client hides from addons right now (C_Secrets).
--
-- In combat (and in encounters, keystones, PvP, on some maps) Forever hides
-- auras, cooldowns, power from addons. A hidden aura is not given out by the
-- lookups, and looking through auras one by one (GetAuraDataByIndex) while
-- they are hidden is an error ("Auras cannot be accessed when secret while
-- tainted"): ask here first.

local ADDON, ns = ...

local Secrets = {}
ns.Utilities.Secrets = Secrets

local SECRECY_LEVELS = {
    NeverSecret = "never",
    AlwaysSecret = "always",
    ContextuallySecret = "contextual",
}

function Secrets.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- auras are hidden from addons now (in general)
function Secrets.AurasHidden()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then
        return false
    end
    return C_Secrets.ShouldAurasBeSecret() == true
end

-- the aura of this spell (ID or name) is hidden now; nil -- the client can not say
function Secrets.SpellAuraHidden(spellIdentifier)
    if not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then
        return nil
    end
    local ok, isHidden = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellIdentifier)
    if not ok then
        return nil
    end
    return isHidden == true
end

-- how the client treats the aura of this spell: "never", "always" or
-- "contextual" (hidden in combat and the like); nil -- unknown
function Secrets.SpellAuraLevel(spellIdentifier)
    if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel) then
        return nil
    end
    local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, spellIdentifier)
    if not ok then
        return nil
    end
    for enumName, levelName in pairs(SECRECY_LEVELS) do
        if Enum.SecrecyLevel[enumName] == level then
            return levelName
        end
    end
    return nil
end
