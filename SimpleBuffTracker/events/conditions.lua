-- conditions.lua -- what changes the show conditions of the buffs
-- (dataflows/buff_conditions.lua): the zone (an instance or not) and the
-- talents and spells, the bags. In combat the panel is not laid out anew: the
-- end of combat does it. The buff list greys the buffs hidden now: redrawn too.

local ADDON, ns = ...

local function Refresh()
    ns.Core.Refresh()
    ns.Components.MainWindow.Refresh()
end

-- the panel is redrawn by events/auras.lua; here only the buff list
ns.Events.On("BAG_UPDATE_DELAYED", function()
    ns.Components.MainWindow.Refresh()
end)
ns.Events.On("ZONE_CHANGED_NEW_AREA", Refresh)
ns.Events.OnIfExists("CHARACTER_POINTS_CHANGED", Refresh)
ns.Events.OnIfExists("PLAYER_TALENT_UPDATE", Refresh)
ns.Events.OnIfExists("SPELLS_CHANGED", Refresh)
