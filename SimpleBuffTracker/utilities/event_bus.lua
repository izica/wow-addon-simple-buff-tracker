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

bus:SetScript("OnEvent", function(_, event, ...)
    for _, handler in ipairs(handlers[event]) do
        handler(...)
    end
end)
