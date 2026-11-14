-- settings.lua -- the addon window: the Buffs tab and the Panel tab.

local ADDON, ns = ...

local Text = ns.Localization.Text

ns.Commands.Add("buffs", {
    run = function()
        ns.Components.MainWindow.Toggle(ns.Components.MainWindow.TAB.BUFFS)
    end,
    help = Text("commands.buffs.help"),
    binding = Text("commands.buffs.binding"),
})

ns.Commands.Add("config", {
    run = function()
        ns.Components.MainWindow.Toggle(ns.Components.MainWindow.TAB.PANEL)
    end,
    help = Text("commands.config.help"),
    binding = Text("commands.config.binding"),
})
