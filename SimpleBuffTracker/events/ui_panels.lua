-- ui_panels.lua -- the game's own panels (spellbook, talents, character...)
-- opening: the addon window may have been closed by them and comes back
-- (components/main_window.lua, MainWindow.OnGamePanelShown).

local ADDON, ns = ...

ns.Events.On("PLAYER_LOGIN", function()
    if ShowUIPanel then
        hooksecurefunc("ShowUIPanel", function(panel)
            ns.Components.MainWindow.OnGamePanelShown(panel)
        end)
    end
end)
