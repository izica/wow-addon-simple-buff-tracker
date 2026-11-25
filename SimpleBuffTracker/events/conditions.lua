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
-- a town or a cave inside a zone: the zone condition counts the maps above
ns.Events.On("ZONE_CHANGED", Refresh)
ns.Events.On("ZONE_CHANGED_INDOORS", Refresh)

-- The combat condition: laid out on PLAYER_REGEN_DISABLED, the last moment
-- secure icons may still be shown and hidden (the lockdown starts after it),
-- and again when combat ends.
ns.Events.On("PLAYER_REGEN_DISABLED", function()
    ns.Dataflows.BuffConditions.SetInCombat(true)
    Refresh()
end)
ns.Events.On("PLAYER_REGEN_ENABLED", function()
    ns.Dataflows.BuffConditions.SetInCombat(false)
    Refresh()
end)
ns.Events.On("PLAYER_ENTERING_WORLD", function()
    ns.Dataflows.BuffConditions.SetInCombat(UnitAffectingCombat and UnitAffectingCombat("player"))
end)
ns.Events.OnIfExists("CHARACTER_POINTS_CHANGED", Refresh)
ns.Events.OnIfExists("PLAYER_TALENT_UPDATE", Refresh)
ns.Events.OnIfExists("SPELLS_CHANGED", Refresh)
