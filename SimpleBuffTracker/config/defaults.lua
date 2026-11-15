-- defaults.lua -- settings and data of a new character, sizes and timings.

local ADDON, ns = ...
ns.Config = ns.Config or {}

local DISPLAY_MODE = ns.Constants.DISPLAY_MODE

ns.Config.defaults = {
    settings = {
        mode = DISPLAY_MODE.ALL,
        iconSize = 36,
        iconsPerRow = 8,
        growDirection = ns.Constants.GROW_DIRECTION.RIGHT,
        iconTemplate = ns.Constants.ICON_TEMPLATE.ACTION_BAR,
        iconSpacing = 4,
        -- the effect around the icon of a missing buff (ns.Constants.GLOW_EFFECT)
        missingGlow = ns.Constants.GLOW_EFFECT.NONE,
        locked = true,
        -- a buff with this many seconds left or less counts as missing in the "missing" mode
        warnSeconds = 120,
        position = { point = "CENTER", x = 0, y = -180 },
        minimap = { hide = false, minimapPos = 200 },   -- LibDBIcon keeps the position here
    },
    -- { target = { spellId, name, weapon }, source = { kind, spellId, name, itemId } or nil }
    buffs = {},
    -- [lower name] = { spellId, name, icon }: every buff seen on the character, for the search
    seenAuras = {},
    -- [enchant id] = name: every temporary enchant seen on the weapons
    seenEnchants = {},
    -- [name] = true: every temporary enchant name seen in the weapon tooltips
    seenEnchantNames = {},
    -- what the shared Other Addons page keeps (shared/other_addons): its language
    otherAddons = {},
}

ns.Config.TICK_SECONDS = 1             -- how often timers and the "missing" list are checked
ns.Config.MIN_ICON_SIZE = 16
ns.Config.MAX_ICON_SIZE = 96
ns.Config.MAX_ICONS_PER_ROW = 40
ns.Config.EMPTY_PANEL_SIZE = 36        -- the size of an unlocked panel without icons, to drag it
