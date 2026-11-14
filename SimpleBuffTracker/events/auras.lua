-- auras.lua -- what changes the buffs: auras on the player, weapons, bags, end of combat.

local ADDON, ns = ...

local function Refresh()
    ns.Components.BuffPanel.Refresh()
end

ns.Events.On("UNIT_AURA", function(unit)
    if unit ~= "player" then
        return
    end
    ns.Dataflows.AuraScan.Update()
    Refresh()
end)

ns.Events.On("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then
        Refresh()
    end
end)

ns.Events.On("PLAYER_EQUIPMENT_CHANGED", Refresh)
ns.Events.On("BAG_UPDATE_DELAYED", Refresh)

-- auras are visible again and the icons may move: read and lay out anew
ns.Events.On("PLAYER_REGEN_ENABLED", function()
    ns.Dataflows.AuraScan.Update()
    Refresh()
end)
