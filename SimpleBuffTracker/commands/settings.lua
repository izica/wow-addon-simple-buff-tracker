-- settings.lua -- the buff window and the settings page in Options -> AddOns.

local ADDON, ns = ...

local Text = ns.Localization.Text

ns.Commands.Add("buffs", {
    run = function()
        ns.Components.SettingsWindow.ToggleBuffs()
    end,
    help = Text("commands.buffs.help"),
    binding = Text("commands.buffs.binding"),
})

ns.Commands.Add("config", {
    run = function()
        ns.Components.SettingsWindow.Toggle()
    end,
    help = Text("commands.config.help"),
    binding = Text("commands.config.binding"),
})
