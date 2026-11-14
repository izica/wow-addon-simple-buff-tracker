-- localization.lua -- UI texts in the client's language.
--
-- Texts live in lang/<language>.json. The game does not read .json, so
-- scripts/build_lang.py builds lang/<language>.lua next to it, which passes
-- the JSON string here, to Add. Keys are nested, in code -- dotted:
-- Text("window.title", 5) -> "Players nearby: 5".

local ADDON, ns = ...

local Localization = {}
ns.Localization = Localization

local FALLBACK_LANGUAGE = "en"

-- ruRU -> ru, everything else for now -> en
local CLIENT_LANGUAGES = {
    ruRU = "ru",
}
local currentLanguage = CLIENT_LANGUAGES[GetLocale()] or FALLBACK_LANGUAGE

local texts = {}   -- [language] = { ["window.title"] = "..." }

-- { window = { title = "..." } } -> { ["window.title"] = "..." }
local function Flatten(tree, prefix, result)
    for key, value in pairs(tree) do
        local path = key
        if prefix ~= "" then
            path = prefix .. "." .. key
        end

        if type(value) == "table" then
            Flatten(value, path, result)
        else
            result[path] = value
        end
    end
    return result
end

-- Called from lang/<language>.lua. Only the needed languages are decoded: current and fallback.
function Localization.Add(language, jsonText)
    local needed = language == currentLanguage or language == FALLBACK_LANGUAGE
    if not needed then return end

    local ok, tree = pcall(ns.json.decode, jsonText)
    if not ok then
        ns.Utilities.Print("lang/" .. language .. ".json: " .. tostring(tree))
        return
    end
    texts[language] = Flatten(tree, "", {})
end

-- Text by key. Missing in the current language -- take the fallback, missing there too --
-- the key itself, so the gap is visible in the UI. Extra arguments go to
-- string.format: Text("window.footer", 2, 3, 140).
function Localization.Text(key, ...)
    local current = texts[currentLanguage] or {}
    local fallback = texts[FALLBACK_LANGUAGE] or {}
    local text = current[key] or fallback[key] or key

    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end
