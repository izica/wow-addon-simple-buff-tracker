-- buff_parser.lua -- a buff from the text of "/sbt add":
--
--   <buff> [= <source>]
--   buff   -- a spell name, a spell id, a spell link (shift-click), or
--             "mainhand" / "offhand" for a temporary weapon enchant;
--   source -- "spell <name, id or link>" or "item <name, id or link>";
--             a bare spell or item link is enough too; "spell" alone -- the
--             same spell as the buff. Without "=" the buff is only tracked.
--
--   /sbt add Arcane Intellect = spell
--   /sbt add Well Fed = item Roasted Quail
--   /sbt add mainhand = item [Brilliant Wizard Oil]

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Buff = ns.Models.Buff
local Spell = ns.Utilities.Spell
local Item = ns.Utilities.Item
local AuraScan = ns.Dataflows.AuraScan
local Trim = ns.Utilities.Trim
local SOURCE_KIND = ns.Constants.SOURCE_KIND
local WEAPON_SLOT = ns.Constants.WEAPON_SLOT

local BuffParser = {}
ns.Dataflows.BuffParser = BuffParser

local WEAPON_KEYWORDS = {
    mainhand = WEAPON_SLOT.MAIN_HAND,
    offhand = WEAPON_SLOT.OFF_HAND,
}

local function SpellIdFrom(text)
    return tonumber(text:match("|Hspell:(%d+)")) or tonumber(text:match("^(%d+)$"))
end

-- { spellId, name } of a spell by link, id or name; a name the client does not
-- know as a spell is kept as it is: auras like "Well Fed" are found by name.
-- Also used by the settings window.
function BuffParser.ParseSpell(text)
    local spellId = SpellIdFrom(text)
    if spellId then
        return { spellId = spellId, name = Spell.Name(spellId) }
    end
    local found = Spell.Find(text)
    if found then
        return { spellId = found.spellId, name = found.name }
    end
    -- not a spell of the character ("Well Fed"): maybe a buff on the player now or
    -- seen on the character before -- then its spell id and picture are known
    local aura = AuraScan.Find({ name = text }, GetTime()) or AuraScan.FindSeen(text)
    if aura then
        return { spellId = aura.spellId, name = aura.name, icon = aura.icon }
    end
    return { name = text }
end

local function ParseTarget(text)
    local weaponSlot = WEAPON_KEYWORDS[text:lower()]
    if weaponSlot then
        return { weapon = weaponSlot }
    end
    if text:find("|Hitem:") then
        return nil
    end
    return BuffParser.ParseSpell(text)
end

-- A picture for the icon field: "icon:<id>" -> that picture; an item link or
-- "item:<id>" -> the item's picture; a spell link, a spell id or the name of a
-- spell of the character -> the spell's picture. nil -- nothing found.
function BuffParser.ParseIcon(text)
    -- a picture id as it is (from the icon search: a buff without a plain spell id)
    local pictureId = tonumber(text:match("^icon:(%d+)$"))
    if pictureId then
        return pictureId
    end
    local itemId = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^item:(%d+)$"))
    if itemId then
        return Item.Icon(itemId)
    end
    local spellId = SpellIdFrom(text)
    if spellId then
        return Spell.Icon(spellId)
    end
    return Spell.Icon(text)
end

-- { spellId, name } of a talent or spell for the talent condition: a talent
-- link (shift-click in the talent window) gives its name, a talent of the tree
-- is found by name (in its own spelling), anything else as ParseSpell.
function BuffParser.ParseTalent(text)
    if text:find("|Htalent:") then
        local name = text:match("|h%[(.-)%]|h")
        if name then
            return { name = name }
        end
    end
    local wanted = text:lower()
    for _, talent in ipairs(ns.Dataflows.Talents.All()) do
        if talent.name:lower() == wanted then
            return { name = talent.name }
        end
    end
    local spell = BuffParser.ParseSpell(text)
    return { spellId = spell.spellId, name = spell.name }
end

-- an item id by id, link or name of an item the client has seen; nil -- unknown
function BuffParser.ParseItemId(text)
    return tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^(%d+)$")) or Item.FindId(text)
end

-- source text -> source, or nil and the key of the error text
local function ParseSource(text, target)
    local keyword, rest = text:match("^(%S+)%s*(.-)$")
    keyword = (keyword or ""):lower()

    if keyword ~= SOURCE_KIND.SPELL and keyword ~= SOURCE_KIND.ITEM then
        -- no keyword: a bare link tells the kind
        if text:find("|Hitem:") then
            keyword = SOURCE_KIND.ITEM
        elseif text:find("|Hspell:") then
            keyword = SOURCE_KIND.SPELL
        else
            return nil, "messages.unknown_source_kind"
        end
        rest = text
    end

    if keyword == SOURCE_KIND.SPELL then
        if rest == "" then
            if target.weapon then
                return nil, "messages.unknown_source_kind"
            end
            return { kind = SOURCE_KIND.SPELL, spellId = target.spellId, name = target.name }
        end
        local spell = BuffParser.ParseSpell(rest)
        return { kind = SOURCE_KIND.SPELL, spellId = spell.spellId, name = spell.name }
    end

    local itemId = BuffParser.ParseItemId(rest)
    if not itemId then
        return nil, "messages.unknown_item"
    end
    return { kind = SOURCE_KIND.ITEM, itemId = itemId }
end

-- the text after "/sbt add" -> buff, or nil and the key of the error text
function BuffParser.Parse(text)
    local targetText, sourceText = text:match("^(.-)=(.*)$")
    if not targetText then
        targetText = text
    end
    targetText = Trim(targetText)
    if targetText == "" then
        return nil, "messages.add_usage"
    end

    local target = ParseTarget(targetText)
    if not target then
        return nil, "messages.unknown_target"
    end

    local source = nil
    if sourceText then
        local errorKey = nil
        source, errorKey = ParseSource(Trim(sourceText), target)
        if not source then
            return nil, errorKey
        end
    end
    return Buff.New(target, source)
end
