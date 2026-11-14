-- settings.lua -- the settings page in Options -> AddOns.

local ADDON, ns = ...

local Text = ns.Localization.Text

ns.Commands.Add("config", {
    run = function()
        ns.Components.SettingsWindow.Toggle()
    end,
    help = Text("commands.config.help"),
    binding = Text("commands.config.binding"),
})
