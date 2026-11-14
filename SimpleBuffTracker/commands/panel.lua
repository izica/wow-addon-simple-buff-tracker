-- panel.lua -- how the panel looks: mode, lock, icon size, icons per row, warning time.
-- The panel holds secure buttons: in combat its layout can not change.

local ADDON, ns = ...

local Text = ns.Localization.Text
local Print = ns.Utilities.Print
local DISPLAY_MODE = ns.Constants.DISPLAY_MODE

-- refuses in combat with a message; true -- may go on
local function OutOfCombat()
    if InCombatLockdown() then
        Print(Text("messages.in_combat"))
        return false
    end
    return true
end

local function Apply()
    ns.Components.BuffPanel.Refresh()
end

-- a whole number from the arguments within the limits, or nil with the usage printed
local function ReadNumber(arguments, minimum, maximum, usageKey)
    local value = tonumber(arguments)
    local isValid = value and value >= minimum and value <= maximum
    if not isValid then
        Print(Text(usageKey, minimum, maximum))
        return nil
    end
    return math.floor(value)
end

ns.Commands.Add("mode", {
    run = function(arguments)
        if not OutOfCombat() then return end
        local settings = ns.db.settings
        local wanted = arguments:lower()
        if wanted == DISPLAY_MODE.ALL or wanted == DISPLAY_MODE.MISSING then
            settings.mode = wanted
        elseif settings.mode == DISPLAY_MODE.ALL then
            settings.mode = DISPLAY_MODE.MISSING
        else
            settings.mode = DISPLAY_MODE.ALL
        end
        Print(Text("messages.mode_set", Text("modes." .. settings.mode)))
        Apply()
    end,
    help = Text("commands.mode.help"),
    binding = Text("commands.mode.binding"),
})

ns.Commands.Add("unlock", {
    run = function()
        if not OutOfCombat() then return end
        ns.db.settings.locked = false
        Print(Text("messages.unlocked"))
        Apply()
    end,
    help = Text("commands.unlock.help"),
})

ns.Commands.Add("lock", {
    run = function()
        if not OutOfCombat() then return end
        ns.db.settings.locked = true
        Print(Text("messages.locked"))
        Apply()
    end,
    help = Text("commands.lock.help"),
})

ns.Commands.Add("size", {
    run = function(arguments)
        if not OutOfCombat() then return end
        local size = ReadNumber(arguments, ns.Config.MIN_ICON_SIZE, ns.Config.MAX_ICON_SIZE, "messages.size_usage")
        if not size then return end
        ns.db.settings.iconSize = size
        Apply()
    end,
    help = Text("commands.size.help"),
})

ns.Commands.Add("row", {
    run = function(arguments)
        if not OutOfCombat() then return end
        local perRow = ReadNumber(arguments, 1, ns.Config.MAX_ICONS_PER_ROW, "messages.row_usage")
        if not perRow then return end
        ns.db.settings.iconsPerRow = perRow
        Apply()
    end,
    help = Text("commands.row.help"),
})

ns.Commands.Add("warn", {
    run = function(arguments)
        local seconds = ReadNumber(arguments, 0, 3600, "messages.warn_usage")
        if not seconds then return end
        ns.db.settings.warnSeconds = seconds
        Print(Text("messages.warn_set", seconds))
        Apply()
    end,
    help = Text("commands.warn.help"),
})
