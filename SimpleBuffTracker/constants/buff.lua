-- buff.lua -- the kinds of buffs, of their sources and of the panel modes.

local ADDON, ns = ...
ns.Constants = ns.Constants or {}

-- what the panel shows
ns.Constants.DISPLAY_MODE = {
    ALL = "all",           -- every tracked buff, active ones with their timers
    MISSING = "missing",   -- only buffs that are gone or about to run out
}

-- how a buff is put back with a click
ns.Constants.SOURCE_KIND = {
    SPELL = "spell",   -- cast a spell
    ITEM = "item",     -- use an item: food, scroll, elixir; on a weapon buff -- oil, stone, poison
}

-- a temporary weapon enchant instead of an aura: the slot it sits on
ns.Constants.WEAPON_SLOT = {
    MAIN_HAND = "mainhand",
    OFF_HAND = "offhand",
}

-- inventory slot numbers of the client for the weapon slots
ns.Constants.WEAPON_INVENTORY_SLOT = {
    mainhand = 16,
    offhand = 17,
}
