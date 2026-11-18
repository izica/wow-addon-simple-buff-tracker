-- event_bus.lua -- one hidden frame for all addon events.
-- Only files in events/ subscribe.

local ADDON, ns = ...

local bus = CreateFrame("Frame")
local handlers = {}
ns.Events = {}

function ns.Events.On(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        bus:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end

-- an event that not every client has (the talent events differ between
-- versions): registering an unknown event is an error, so it is skipped
function ns.Events.OnIfExists(event, handler)
    if not handlers[event] then
        if not pcall(bus.RegisterEvent, bus, event) then
            return
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], handler)
end

bus:SetScript("OnEvent", function(_, event, ...)
    for _, handler in ipairs(handlers[event]) do
        handler(...)
    end
end)
