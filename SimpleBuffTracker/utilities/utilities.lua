-- utilities.lua -- chat output, default settings, small string helpers.

local ADDON, ns = ...

local Utilities = {}
ns.Utilities = Utilities

function Utilities.Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. ns.Constants.ADDON_TITLE .. "|r: " .. tostring(text))
end

-- Adds missing keys from defaults into target; nested tables -- recursively.
function Utilities.Defaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = Utilities.Defaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function Utilities.Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

-- seconds -> "1 hr" / "12 min" / "40 sec" in the client's language
function Utilities.FormatSeconds(seconds)
    seconds = math.max(0, math.floor(seconds))
    if SecondsToTime then
        local noSeconds = seconds >= 60
        return SecondsToTime(seconds, noSeconds)
    end
    return tostring(seconds)
end
