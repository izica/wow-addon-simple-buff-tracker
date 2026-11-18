-- addon_loaded.lua -- addon start.

local ADDON, ns = ...

ns.Events.On("ADDON_LOADED", function(name)
    if name == ADDON then
        ns.Core.Init()
    end
end)

ns.Events.On("PLAYER_LOGIN", function()
    ns.Components.MinimapButton.Setup()
    ns.Components.SettingsPages.Register()
    -- a new player sees an empty, invisible panel: say once where buffs are added
    local isFirstLogin = not ns.db.settings.welcomed and #ns.db.buffs == 0
    ns.db.settings.welcomed = true
    if isFirstLogin then
        ns.Utilities.Print(ns.Localization.Text("messages.welcome"))
    end
end)

ns.Events.On("PLAYER_ENTERING_WORLD", function()
    ns.Dataflows.AuraScan.Update()
    ns.Core.Refresh()
end)
