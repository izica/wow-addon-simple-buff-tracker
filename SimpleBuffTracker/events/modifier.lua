-- modifier.lua -- Shift over the panel brings up its mover (Shift + drag moves
-- the panel); combat takes it away.

local ADDON, ns = ...

ns.Events.On("MODIFIER_STATE_CHANGED", function()
    ns.Components.BuffPanel.UpdateMover()
end)

-- just before combat the panel can still move: a drag going on is ended here
ns.Events.On("PLAYER_REGEN_DISABLED", function()
    ns.Components.BuffPanel.StopDragging()
end)
