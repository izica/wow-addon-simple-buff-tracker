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
        for slot, enchants in pairs(weapons) do
            for _, enchant in ipairs(enchants) do
                Print("weapon " .. slot .. ": name=" .. tostring(enchant.name)
                    .. " enchantId=" .. tostring(enchant.enchantId)
                    .. " left=" .. math.floor(enchant.expirationTime - now))
            end
        end
        for _, line in ipairs(WeaponEnchant.DebugLines()) do
            Print(line)
        end
        for enchantId, name in pairs(ns.db.seenEnchants) do
            Print("seen enchant " .. tostring(enchantId) .. " = " .. tostring(name))
        end
        for index, buff in ipairs(ns.Services.Buff.List()) do
            local target = buff.target
            local found = nil
            if target.weapon then
                local enchant = WeaponEnchant.Find(target, weapons[target.weapon])
                found = enchant and (enchant.name or enchant.enchantId)
            else
                local aura = AuraScan.Find(target, now)
                found = aura and aura.name
            end
            Print("buff " .. index .. ": name=" .. tostring(target.name)
                .. " spellId=" .. tostring(target.spellId)
                .. " weapon=" .. tostring(target.weapon)
                .. " enchant=" .. tostring(WeaponEnchant.TargetName(target))
                .. " icon=" .. tostring(target.icon)
                .. " found=" .. tostring(found))
        end
    end,
    help = Text("commands.debug.help"),
})
