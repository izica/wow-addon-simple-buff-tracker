-- icon_search.lua -- pictures for the icon field of the buff window, found by
-- name as the player types: the buffs on the player, the spells of the
-- spellbook and the items in the bags. The client gives no names for the rest
-- of its pictures, so only these are searched.
--
-- A suggestion: { label -- the name shown, icon -- the picture, text -- what
-- goes into the field (BuffParser.ParseIcon reads it back): a spell id,
-- "item:<id>" or "icon:<picture id>" }.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local AuraScan = ns.Dataflows.AuraScan

local IconSearch = {}
ns.Dataflows.IconSearch = IconSearch

local MAX_SUGGESTIONS = 10
local MIN_QUERY_LENGTH = 2
local FIRST_BAG = 0
local LAST_BAG = 4

local function AuraSuggestions(add)
    for _, aura in ipairs(AuraScan.All()) do
        if aura.icon then
            local text = "icon:" .. aura.icon
            if aura.spellId then
                text = tostring(aura.spellId)
            end
            add(aura.name, aura.icon, text)
        end
    end
end

local function SpellBookSuggestions(add)
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
                if info and info.spellID and info.name then
                    add(info.name, info.iconID, tostring(info.spellID))
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
                if name then
                    add(name, info.iconFileID, "item:" .. info.itemID)
                end
            end
        end
    end
end

-- Suggestions whose name has the query in it, names that start with it first;
-- nothing for a query shorter than MIN_QUERY_LENGTH or a bare number (an id is typed).
function IconSearch.Search(query)
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    local isTooShort = #query < MIN_QUERY_LENGTH
    if isTooShort or query:match("^%d+$") then
        return {}
    end

    local starting = {}
    local containing = {}
    local seen = {}
    local function add(name, icon, text)
        if not (name and icon) then
            return
        end
        local key = name .. "|" .. tostring(icon)
        if seen[key] then
            return
        end
        local position = name:lower():find(query, 1, true)
        if not position then
            return
        end
        seen[key] = true
        local suggestion = { label = name, icon = icon, text = text }
        if position == 1 then
            table.insert(starting, suggestion)
        else
            table.insert(containing, suggestion)
        end
    end

    -- every source on its own: one failing API must not take the others down
    pcall(AuraSuggestions, add)
    pcall(SpellBookSuggestions, add)
    pcall(BagSuggestions, add)

    local result = {}
    for _, list in ipairs({ starting, containing }) do
        table.sort(list, function(a, b)
            return a.label < b.label
        end)
        for _, suggestion in ipairs(list) do
            if #result >= MAX_SUGGESTIONS then
                return result
            end
            table.insert(result, suggestion)
        end
    end
    return result
end
