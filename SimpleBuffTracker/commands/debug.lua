-- debug.lua -- /sbt debug: what the addon sees, to send a screenshot of the chat.
-- The lines are diagnostics in English, not interface texts.

local ADDON, ns = ...

local Text = ns.Localization.Text
local Print = ns.Utilities.Print
local AuraScan = ns.Dataflows.AuraScan

ns.Commands.Add("debug", {
    run = function()
        AuraScan.Update()
        for _, line in ipairs(AuraScan.DebugLines()) do
            Print(line)
        end
        local now = GetTime()
        for index, buff in ipairs(ns.Services.Buff.List()) do
            local target = buff.target
            local aura = (not target.weapon) and AuraScan.Find(target, now)
            Print("buff " .. index .. ": name=" .. tostring(target.name)
                .. " spellId=" .. tostring(target.spellId)
                .. " weapon=" .. tostring(target.weapon)
                .. " icon=" .. tostring(target.icon)
                .. " found=" .. tostring(aura and aura.name))
        end
    end,
    help = Text("commands.debug.help"),
})
