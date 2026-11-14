-- core.lua -- initialization: the character's data from SavedVariables and the panel.
-- Called from events/addon_loaded.lua; before that ns.db == nil.

local ADDON, ns = ...

ns.Core = {}

function ns.Core.Init()
    SimpleBuffTrackerDB = ns.Utilities.Defaults(SimpleBuffTrackerDB, ns.Config.defaults)
    ns.db = SimpleBuffTrackerDB

    ns.Components.BuffPanel.Create()
end

-- After the buffs may have changed (events, ticker): the panel, and the buff
-- window when a buff got its picture (it shows pictures in its tree).
function ns.Core.Refresh()
    ns.Components.BuffPanel.Refresh()
    if ns.Services.Buff.TakeLearnedIcons() then
        ns.Components.MainWindow.Refresh()
    end
end
