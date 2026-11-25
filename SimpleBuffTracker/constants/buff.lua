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
    EQUIP = "equip",   -- put on the tracked item (a buff of the "equipped item" kind)
}

-- what the Track select of the buff window offers besides the weapon slots
ns.Constants.TARGET_KIND = {
    AURA = "aura",          -- a buff on the player
    EQUIPPED = "equipped",  -- an item worn: a trinket, a fishing pole, a riding crop
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

-- where the panel adds icons: the next icon of a line stands that way
ns.Constants.GROW_DIRECTION = {
    RIGHT = "right",
    LEFT = "left",
    DOWN = "down",
    UP = "up",
}

-- the point the panel is held by: the middle of the edge the icons grow from --
-- it stays in place as the panel grows (more lines spread evenly to both sides)
ns.Constants.GROW_ANCHOR = {
    right = "LEFT",
    left = "RIGHT",
    down = "TOP",
    up = "BOTTOM",
}

-- how an icon on the panel looks (ui/buff_button.lua)
ns.Constants.ICON_TEMPLATE = {
    ACTION_BAR = "action_bar",     -- like the buttons of the action bars
    BORDERLESS = "borderless",     -- the same, without the frame around it
    SQUARE = "square",             -- only the picture, square edges
}

-- the effect around the icon of a missing buff (ui/glow.lua)
ns.Constants.GLOW_EFFECT = {
    NONE = "none",
    PIXEL = "pixel",
    AUTOCAST = "autocast",
    PROC = "proc",
    PULSE = "pulse",
}

-- where a buff with a place condition is shown: the instance type the client
-- gives (IsInInstance), or the open world outside instances; a buff with none
-- of them -- everywhere
ns.Constants.INSTANCE_KIND = {
    WORLD = "world",          -- outside instances
    RAID = "raid",            -- a raid instance
    BATTLEGROUND = "pvp",     -- a battleground
    DUNGEON = "party",        -- a dungeon (five-player instance)
}
-- the order of the checkboxes in the buff window
ns.Constants.INSTANCE_KINDS = { "world", "party", "raid", "pvp" }

-- the combat condition of a buff: only in combat or only out of it (nil -- both)
ns.Constants.COMBAT_STATE = {
    IN = "in",
    OUT = "out",
}

-- when the icon of one buff glows (buff.glowWhen); nil -- as the panel: missing or expiring
ns.Constants.GLOW_WHEN = {
    ACTIVE = "active",     -- while the buff is on
    MISSING = "missing",   -- while it is missing or about to run out
    ALWAYS = "always",
    NEVER = "never",
}
-- the order of the effects in the selects
ns.Constants.GLOW_ORDER = { "none", "pixel", "autocast", "proc", "pulse" }
