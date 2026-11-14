-- addon_loaded.lua -- addon start.

local ADDON, ns = ...

ns.Events.On("ADDON_LOADED", function(name)
    if name == ADDON then
        ns.Core.Init()
    end
end)

ns.Events.On("PLAYER_LOGIN", function()
    ns.Components.MinimapButton.Setup()
    ns.Components.SettingsWindow.Setup()
end)

ns.Events.On("PLAYER_ENTERING_WORLD", function()
    ns.Dataflows.AuraScan.Update()
    ns.Core.Refresh()
end)
