-- icon_search.lua -- suggestions for the fields of the buff window, found by
-- name as the player types: the buffs on the player, the buffs seen on the
-- character before (AuraScan.Seen), the spells of the spellbook and the items
-- in the bags. The client gives no names for the rest
-- of its pictures, so only these are searched.
--
-- A suggestion: { label -- the name shown, icon -- the picture, kind -- "aura",
-- "spell", "talent" or "item", spellId (may be nil for an aura or a talent), itemId }.
-- The talent condition also searches the talent tree (dataflows/talents.lua).

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local AuraScan = ns.Dataflows.AuraScan

local IconSearch = {}
ns.Dataflows.IconSearch = IconSearch

-- which sources a field searches
IconSearch.SOURCES = {
    ALL = { auras = true, seen = true, spells = true, items = true },
    BUFFS = { auras = true, seen = true, spells = true },
    SPELLS = { spells = true, auras = true },
    ITEMS = { items = true },
    -- the zone condition: the zones and dungeons of the world map
    ZONES = { zones = true },
    -- the talent condition: the talent tree and the spellbook with its passive spells
    TALENTS = { talents = true, spells = true, passives = true },
}

local MAX_SUGGESTIONS = 10
local MIN_QUERY_LENGTH = 2
local FIRST_BAG = 0
local LAST_BAG = 4

local function AuraSuggestions(add)
    for _, aura in ipairs(AuraScan.All()) do
        add({ label = aura.name, icon = aura.icon, kind = "aura", spellId = aura.spellId })
    end
end

-- buffs seen on the character before (not on now): "Well Fed" without eating first
local function SeenSuggestions(add)
    for _, aura in ipairs(AuraScan.Seen()) do
        add({ label = aura.name, icon = aura.icon, kind = "aura", spellId = aura.spellId })
    end
end

local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"

-- every zone and dungeon (dataflows/zones.lua)
local function ZoneSuggestions(add)
    for _, zone in ipairs(ns.Dataflows.Zones.All()) do
        add({ label = zone.name, icon = MAP_ICON, kind = "zone", mapId = zone.mapId })
    end
end

-- every talent of the tree, learned or not (dataflows/talents.lua)
local function TalentSuggestions(add)
    for _, talent in ipairs(ns.Dataflows.Talents.All()) do
        add({ label = talent.name, icon = talent.icon, kind = "talent" })
    end
end

-- includePassive -- the passive spells too (talents learned show up so)
local function SpellBookSuggestions(add, includePassive)
    local hasSpellBook = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and Enum and Enum.SpellBookSpellBank
    if not hasSpellBook then
        return
    end
    local bank = Enum.SpellBookSpellBank.Player
    for skillLineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local skillLine = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
        if skillLine then
            for offset = 1, skillLine.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(skillLine.itemIndexOffset + offset, bank)
                local isSpell = info and info.spellID and (includePassive or not info.isPassive)
                if isSpell then
                    add({ label = info.name, icon = info.iconID, kind = "spell", spellId = info.spellID })
                end
            end
        end
    end
end

local function BagSuggestions(add)
    if not (C_Container and C_Container.GetContainerNumSlots) then
        return
    end
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = info.itemName or (info.hyperlink and info.hyperlink:match("%[(.-)%]"))
                add({ label = name, icon = info.iconFileID, kind = "item", itemId = info.itemID })
            end
        end
    end
end

-- Suggestions from the sources (IconSearch.SOURCES) whose name has the query
-- in it, names that start with it first; nothing for a query shorter than
-- MIN_QUERY_LENGTH or a bare number (an id is being typed).
function IconSearch.Search(query, sources)
    sources = sources or IconSearch.SOURCES.ALL
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    local isTooShort = #query < MIN_QUERY_LENGTH
    if isTooShort or query:match("^%d+$") then
        return {}
    end

    local starting = {}
    local containing = {}
    local seen = {}
    local function add(suggestion)
        if not (suggestion.label and suggestion.icon) then
            return
        end
        local key = suggestion.label .. "|" .. tostring(suggestion.icon)
        if seen[key] then
            return
        end
        local position = suggestion.label:lower():find(query, 1, true)
        if not position then
            return
        end
        seen[key] = true
        if position == 1 then
            table.insert(starting, suggestion)
        else
            table.insert(containing, suggestion)
        end
    end

    -- every source on its own: one failing API must not take the others down
    if sources.auras then
        pcall(AuraSuggestions, add)
    end
    if sources.seen then
        pcall(SeenSuggestions, add)
    end
    if sources.zones then
        pcall(ZoneSuggestions, add)
    end
    if sources.talents then
        pcall(TalentSuggestions, add)
    end
    if sources.spells then
        pcall(SpellBookSuggestions, add, sources.passives)
    end
    if sources.items then
        pcall(BagSuggestions, add)
    end

    local result = {}
    for _, group in ipairs({ starting, containing }) do
        table.sort(group, function(a, b)
            return a.label < b.label
        end)
        for _, suggestion in ipairs(group) do
            if #result >= MAX_SUGGESTIONS then
                return result
            end
            table.insert(result, suggestion)
        end
    end
    return result
end
