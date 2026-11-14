-- ticker.lua -- once in TICK_SECONDS: buffs run out by the clock without any
-- event, and in the "missing" mode a buff about to run out must appear.

local ADDON, ns = ...

ns.Events.On("PLAYER_LOGIN", function()
    C_Timer.NewTicker(ns.Config.TICK_SECONDS, function()
        ns.Core.Refresh()
    end)
end)
