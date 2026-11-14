-- debug.lua -- /sbt debug: what the addon sees, to send a screenshot of the chat.
-- The lines are diagnostics in English, not interface texts.

local ADDON, ns = ...

local Text = ns.Localization.Text
local Print = ns.Utilities.Print
local AuraScan = ns.Dataflows.AuraScan
local WeaponEnchant = ns.Dataflows.WeaponEnchant

ns.Commands.Add("debug", {
    run = function()
        AuraScan.Update()
        for _, line in ipairs(AuraScan.DebugLines()) do
            Print(line)
        end
        local now = GetTime()
        local weapons = WeaponEnchant.Read(now)
        for slot, enchant in pairs(weapons) do
            Print("weapon " .. slot .. ": enchantId=" .. tostring(enchant.enchantId)
                .. " name=" .. tostring(enchant.name)
                .. " left=" .. math.floor(enchant.expirationTime - now))
        end
        for index, buff in ipairs(ns.Services.Buff.List()) do
            local target = buff.target
            local found = nil
            if target.weapon then
                local enchant = weapons[target.weapon]
                found = WeaponEnchant.Matches(target, enchant) and enchant.name
            else
                local aura = AuraScan.Find(target, now)
                found = aura and aura.name
            end
            Print("buff " .. index .. ": name=" .. tostring(target.name)
                .. " spellId=" .. tostring(target.spellId)
                .. " weapon=" .. tostring(target.weapon)
                .. " enchantId=" .. tostring(target.enchantId)
                .. " icon=" .. tostring(target.icon)
                .. " found=" .. tostring(found))
        end
    end,
    help = Text("commands.debug.help"),
})
