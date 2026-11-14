-- command_router.lua -- a command has three entry points: chat (/sbt ...), a key from
-- Bindings.xml and a button in the UI. All three call ns.Commands.Run.

local ADDON, ns = ...

local routes = {}   -- [command name] = options
local order = {}    -- names in the order they were added, for the help list
ns.Commands = {}

-- options: run(arguments), help -- hint in chat, binding -- name in the key bindings menu
function ns.Commands.Add(name, options)
    routes[name] = options
    table.insert(order, name)
    if options.binding then
        _G["BINDING_NAME_SIMPLEBUFFTRACKER_" .. name:upper()] = options.binding
    end
end

function ns.Commands.PrintHelp()
    for _, commandName in ipairs(order) do
        -- "/sbt add <buff> - Track a buff." -- the arguments are part of the help text;
        -- "/sbt list - List the tracked buffs." -- a command without arguments
        local help = routes[commandName].help or ""
        local separator = " - "
        if help:find("^[<%[]") then
            separator = " "
        end
        ns.Utilities.Print("/sbt " .. commandName .. separator .. help)
    end
end

-- Unknown command -- print the list of all commands.
function ns.Commands.Run(name, arguments)
    local route = routes[name]
    if route then
        return route.run(arguments or "")
    end
    ns.Commands.PrintHelp()
end

-- Entry from chat and macros: /sbt <command> [...]; without a command -- the help list
SLASH_SIMPLEBUFFTRACKER1 = "/sbt"
SLASH_SIMPLEBUFFTRACKER2 = "/simplebufftracker"
SlashCmdList.SIMPLEBUFFTRACKER = function(message)
    local trimmed = ns.Utilities.Trim(message)
    local firstWord, rest = trimmed:match("^(%S*)%s*(.-)$")
    ns.Commands.Run(firstWord:lower(), rest)
end

-- entry from Bindings.xml: code there runs in the global environment and does not see ns
BINDING_HEADER_SIMPLEBUFFTRACKER = ns.Constants.ADDON_TITLE
SimpleBuffTracker_RunCommand = ns.Commands.Run
