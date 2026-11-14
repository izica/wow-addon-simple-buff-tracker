-- core.lua -- initialization: the character's data from SavedVariables and the panel.
-- Called from events/addon_loaded.lua; before that ns.db == nil.

local ADDON, ns = ...

ns.Core = {}

function ns.Core.Init()
    SimpleBuffTrackerDB = ns.Utilities.Defaults(SimpleBuffTrackerDB, ns.Config.defaults)
    ns.db = SimpleBuffTrackerDB

    ns.Components.BuffPanel.Create()
end
