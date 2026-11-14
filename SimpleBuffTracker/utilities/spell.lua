-- spell.lua -- the client's spell API in one shape. Forever has the Retail
-- C_Spell functions; the old globals are only a fallback.

local ADDON, ns = ...

local Spell = {}
ns.Utilities.Spell = Spell

-- A spell by id or by name: { spellId, name, icon }, or nil if the client
-- does not know such a spell. A name is found only for spells the character has.
function Spell.Find(identifier)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(identifier)
        if not info then
            return nil
        end
        return { spellId = info.spellID, name = info.name, icon = info.iconID }
    end

    if not GetSpellInfo then
        return nil
    end
    local name, _, icon, _, _, _, spellId = GetSpellInfo(identifier)
    if not name then
        return nil
    end
    return { spellId = spellId, name = name, icon = icon }
end

-- by id or by name; nil -- unknown
function Spell.Icon(identifier)
    if not identifier then
        return nil
    end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(identifier)
    end
    if GetSpellTexture then
        return GetSpellTexture(identifier)
    end
    return nil
end

function Spell.Name(spellId)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellId)
    end
    if GetSpellInfo then
        return (GetSpellInfo(spellId))
    end
    return nil
end
