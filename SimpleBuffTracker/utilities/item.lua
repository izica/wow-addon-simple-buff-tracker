-- item.lua -- the client's item API in one shape. Forever has no old
-- globals like GetItemInfo: C_Item first, the globals only as a fallback.

local ADDON, ns = ...

local Item = {}
ns.Utilities.Item = Item

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

-- an item id by name, "item:ID" or a link; a name is found only for items the
-- client has seen (in the bags, for example); nil -- unknown
function Item.FindId(identifier)
    if GetItemInfoInstant then
        local itemId = GetItemInfoInstant(identifier)
        if itemId then
            return itemId
        end
    end
    if GetItemInfo then
        local _, link = GetItemInfo(identifier)
        if link then
            return tonumber(link:match("|Hitem:(%d+)"))
        end
    end
    return nil
end

-- nil while the client has not loaded the item yet
function Item.Name(itemId)
    if C_Item and C_Item.GetItemNameByID then
        return C_Item.GetItemNameByID(itemId)
    end
    if GetItemInfo then
        return (GetItemInfo(itemId))
    end
    return nil
end

function Item.Icon(itemId)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemId)
    end
    if GetItemInfoInstant then
        return select(5, GetItemInfoInstant(itemId))
    end
    return nil
end

local IsEquippedItem = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem

-- whether the character wears it now (any slot)
function Item.IsEquipped(itemId)
    if not IsEquippedItem then
        return false
    end
    return IsEquippedItem(itemId) and true or false
end

-- how many are in the bags
function Item.Count(itemId)
    if not GetItemCount then
        return 0
    end
    return GetItemCount(itemId) or 0
end
