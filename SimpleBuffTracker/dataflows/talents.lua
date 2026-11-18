-- talents.lua -- the talents of the character, from the talent tree of the client.
--
-- The classic talent API: GetNumTalentTabs(), GetNumTalents(tab),
-- GetTalentInfo(tab, index) -> name, icon, tier, column, rank, maxRank. Passive
-- talents are not in the spellbook and IsPlayerSpell does not always know them by
-- one id (every rank is its own spell), so a talent is looked up by its name here.
-- A client with another shape of the API (no tabs, the first value not a name)
-- has no talents for us: the other checks (spell id, spellbook) still work.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Talents = {}
ns.Dataflows.Talents = Talents

local function ReadAll()
    local result = {}
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then
        return result
    end
    for tab = 1, GetNumTalentTabs() or 0 do
        for index = 1, GetNumTalents(tab) or 0 do
            local name, icon, _, _, rank, maxRank = GetTalentInfo(tab, index)
            if type(name) == "string" and name ~= "" then
                table.insert(result, {
                    name = name,
                    icon = icon,
                    rank = tonumber(rank) or 0,
                    maxRank = tonumber(maxRank) or 0,
                })
            end
        end
    end
    return result
end

-- every talent of the tree: { name, icon, rank, maxRank }; empty -- no such API
function Talents.All()
    local ok, result = pcall(ReadAll)
    if not ok then
        return {}
    end
    return result
end

-- the points put into the talent of that name (any case); nil -- no such talent
function Talents.Rank(name)
    if not name then
        return nil
    end
    local wanted = name:lower()
    for _, talent in ipairs(Talents.All()) do
        if talent.name:lower() == wanted then
            return talent.rank
        end
    end
    return nil
end
