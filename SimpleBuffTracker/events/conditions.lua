-- conditions.lua -- what changes the show conditions of the buffs
-- (dataflows/buff_conditions.lua): the zone (an instance or not) and the
-- talents and spells. The bags already redraw the panel (events/auras.lua).
-- In combat the panel is not laid out anew: the end of combat does it.

local ADDON, ns = ...

local function Refresh()
    ns.Core.Refresh()
end

ns.Events.On("ZONE_CHANGED_NEW_AREA", Refresh)
ns.Events.OnIfExists("CHARACTER_POINTS_CHANGED", Refresh)
ns.Events.OnIfExists("PLAYER_TALENT_UPDATE", Refresh)
ns.Events.OnIfExists("SPELLS_CHANGED", Refresh)
