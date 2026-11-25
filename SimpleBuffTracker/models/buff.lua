-- buff.lua -- a tracked buff: what to look for and how to put it back.
--
-- Stored in SavedVariables as a plain table (no metatable):
--   target -- what is tracked, one of:
--     { spellId, name, icon }  an aura on the player; found by the spell id or by
--                        the name (the name covers every rank of the spell);
--                        icon -- its picture, kept once seen on the player;
--     { weapon, enchantId, enchantName }  a temporary enchant on a weapon slot
--                        (ns.Constants.WEAPON_SLOT); enchantId -- only this one
--                        (an oil, not the shaman's Flametongue), nil -- any;
--     { isEquipped = true, equipItemId }  an item the character must wear (a trinket, a fishing
--                        pole); active while it is equipped, no timer;
--   warnSeconds -- this buff counts as missing this long before its end; nil --
--             the panel's settings.warnSeconds;
--   icon, iconText -- a picture picked in the buff window (texture id) and what
--             was typed for it (spell id, spell or item link); nil -- automatic;
--   source -- how a click puts it back, or nil -- only tracked:
--     { kind = "spell", spellId, name }
--     { kind = "item", itemId }
--     { kind = "equip" }  put on the item of an "equipped item" buff
--   conditions -- when the buff is shown at all, nil -- always
--             (dataflows/buff_conditions.lua; every one set must hold):
--     hiddenPlaces -- { [ns.Constants.INSTANCE_KIND] = true }: not in these
--                 places ("world" -- outside instances); nil or empty -- everywhere
--                 (every checkbox of the buff window on: the default);
--     zones    -- { { mapId, name } }: only in these zones or dungeons (and
--                 the smaller maps inside them); nil -- any zone;
--     combat   -- ns.Constants.COMBAT_STATE: only in combat / only out of it;
--     itemId   -- only while this item is in the bags;
--     talent   -- { spellId, name }: only while the character has learned it,
--                 talentMissing = true -- only while not.

local ADDON, ns = ...
ns.Models = ns.Models or {}

local SOURCE_KIND = ns.Constants.SOURCE_KIND
local WEAPON_INVENTORY_SLOT = ns.Constants.WEAPON_INVENTORY_SLOT
local Spell = ns.Utilities.Spell
local Item = ns.Utilities.Item

local Buff = {}
ns.Models.Buff = Buff

function Buff.New(target, source)
    return { target = target, source = source }
end

-- whether it says what to track: a weapon slot, a spell, a name or an item to wear. A buff just
-- added in the window has nothing yet and is not put on the panel.
function Buff.HasTarget(buff)
    local target = buff.target
    return target.weapon ~= nil or target.spellId ~= nil or target.name ~= nil or target.equipItemId ~= nil
end

-- A source picked in the settings but not filled in yet (no spell, no item)
-- does nothing: no label, no icon, no action.
function Buff.HasCompleteSource(buff)
    local source = buff.source
    if not source then
        return false
    end
    if source.kind == SOURCE_KIND.SPELL then
        return source.name ~= nil or source.spellId ~= nil
    end
    if source.kind == SOURCE_KIND.EQUIP then
        return buff.target.equipItemId ~= nil
    end
    return source.itemId ~= nil
end

-- the name of what is tracked, as players see it
function Buff.TargetLabel(buff)
    local Text = ns.Localization.Text
    local target = buff.target
    if target.weapon then
        local slotName = Text("buff." .. target.weapon)
        -- the name remembered now for the chosen enchant (corrected if it was read wrong once)
        local enchantName = target.enchantName
        local seen = ns.db and ns.db.seenEnchants
        if target.enchantId and seen and seen[target.enchantId] then
            enchantName = seen[target.enchantId]
        end
        if enchantName then
            return Text("buff.weapon_enchant", slotName, enchantName)
        end
        return slotName
    end
    if target.equipItemId then
        return Item.Name(target.equipItemId) or ("item:" .. target.equipItemId)
    end
    return target.name or (target.spellId and Spell.Name(target.spellId)) or Text("buff.new")
end

-- the name of the spell or item that puts the buff back; nil -- no source
function Buff.SourceLabel(buff)
    if not Buff.HasCompleteSource(buff) then
        return nil
    end
    local source = buff.source
    if source.kind == SOURCE_KIND.SPELL then
        return source.name or Spell.Name(source.spellId) or "?"
    end
    local itemId = source.itemId or buff.target.equipItemId
    return Item.Name(itemId) or ("item:" .. tostring(itemId))
end

function Buff.SourceIcon(buff)
    if not Buff.HasCompleteSource(buff) then
        return nil
    end
    local source = buff.source
    if source.kind == SOURCE_KIND.SPELL then
        return Spell.Icon(source.spellId or source.name)
    end
    return Item.Icon(source.itemId or buff.target.equipItemId)
end

-- The attributes of a secure action button that put the buff back with a
-- click; nil -- no source. An item on a weapon buff is used and then put on
-- the weapon slot by a macro: "/use 16" applies the pending item to the main hand.
function Buff.Action(buff)
    if not Buff.HasCompleteSource(buff) then
        return nil
    end
    local source = buff.source
    if source.kind == SOURCE_KIND.SPELL then
        return { type = "spell", spell = source.name or source.spellId }
    end
    -- /equip picks the slot itself (the first free trinket slot, the main hand...)
    if source.kind == SOURCE_KIND.EQUIP then
        return { type = "macro", macrotext = "/equip item:" .. buff.target.equipItemId }
    end

    local itemReference = "item:" .. source.itemId
    local weaponSlot = buff.target.weapon
    if weaponSlot then
        local inventorySlot = WEAPON_INVENTORY_SLOT[weaponSlot]
        return { type = "macro", macrotext = "/use " .. itemReference .. "\n/use " .. inventorySlot }
    end
    return { type = "item", item = itemReference }
end
