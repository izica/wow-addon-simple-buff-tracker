-- buffs.lua -- the list of tracked buffs: add, remove, list.

local ADDON, ns = ...

local Text = ns.Localization.Text
local Print = ns.Utilities.Print
local Buff = ns.Models.Buff
local BuffParser = ns.Dataflows.BuffParser
local BuffService = ns.Services.Buff

local function Describe(buff)
    local sourceLabel = Buff.SourceLabel(buff)
    if not sourceLabel then
        return Buff.TargetLabel(buff)
    end
    return Text("messages.buff_with_source", Buff.TargetLabel(buff), Text("source." .. buff.source.kind), sourceLabel)
end

ns.Commands.Add("add", {
    run = function(arguments)
        local buff, errorKey = BuffParser.Parse(arguments)
        if not buff then
            Print(Text(errorKey))
            if errorKey ~= "messages.add_usage" then
                Print(Text("messages.add_usage"))
            end
            return
        end
        BuffService.Add(buff)
        Print(Text("messages.added", Describe(buff)))
        ns.Components.BuffPanel.Refresh()
        ns.Components.MainWindow.Refresh()
    end,
    help = Text("commands.add.help"),
})

ns.Commands.Add("remove", {
    run = function(arguments)
        local index = tonumber(arguments)
        local removed = index and BuffService.Remove(index)
        if not removed then
            Print(Text("messages.bad_index"))
            return
        end
        Print(Text("messages.removed", Describe(removed)))
        ns.Components.BuffPanel.Refresh()
        ns.Components.MainWindow.Refresh()
    end,
    help = Text("commands.remove.help"),
})

ns.Commands.Add("list", {
    run = function()
        local buffs = BuffService.List()
        if #buffs == 0 then
            Print(Text("messages.list_empty"))
            return
        end
        for index, buff in ipairs(buffs) do
            Print(index .. ". " .. Describe(buff))
        end
    end,
    help = Text("commands.list.help"),
})
