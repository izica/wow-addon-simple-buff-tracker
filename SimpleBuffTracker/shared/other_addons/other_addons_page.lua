-- other_addons_page.lua -- the "Other addons" page of the settings: the
-- author's other addons as cards -- icon, name, a line on what it is, its
-- features as points, and whether it is installed (installed / installed but
-- turned off / not installed). The cards scroll when they do not fit.
--
-- A self-contained module, the same in every addon of the author: the folder
-- shared/other_addons is copied whole and needs nothing of the addon it is in
-- but the addon's namespace (ns.OtherAddons). Its files, in this order in .toc:
--   shared\other_addons\addons.lua           -- the list of the addons
--   shared\other_addons\lang\en.lua          -- the texts (English is the fallback)
--   shared\other_addons\lang\ru.lua
--   shared\other_addons\other_addons_page.lua -- this file
--
-- Use:
--   ns.OtherAddons.Register(category, { exclude = ADDON })
--     -- a subcategory "Other addons" under the addon's category in the game's
--        settings (Settings.RegisterCanvasLayoutCategory); exclude -- the folder
--        of the addon to leave out, the one the page is in;
--   ns.OtherAddons.CreatePage(parent, { exclude = ADDON }) -> frame
--     -- only the page, to put somewhere else.
-- The statuses are read again every time the page is shown. The language is the
-- client's (GetLocale), options.language overrides it.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
local OtherAddons = ns.OtherAddons

local FALLBACK_LANGUAGE = "en"
local CLIENT_LANGUAGES = { ruRU = "ru" }

local PADDING = 24
local HEADER_GAP = 6
local DIVIDER_GAP = 16
local SCROLL_BAR_SPACE = 26      -- room for the scroll bar on the right of the cards
local CARD_GAP = 10
local CARD_INSET = 16            -- from the card edges to its content
local ICON_SIZE = 46
local ICON_CROP = 0.08
local ICON_FRAME = 2
local TEXT_GAP = 14              -- between the icon and the texts
local STATUS_WIDTH = 150
local STATUS_DOT_SIZE = 8
local ACCENT_WIDTH = 3
local LINE_GAP = 4               -- between the name, the line and the points
local FEATURES_GAP = 8
local FEATURE_SPACING = 3
local BULLET = "\226\128\162 "   -- "• " in UTF-8

local CARD_COLOR = { 0.07, 0.07, 0.09, 0.9 }
local CARD_HOVER_COLOR = { 0.11, 0.11, 0.14, 0.95 }
local BORDER_COLOR = { 0.24, 0.24, 0.28, 1 }
local BORDER_HOVER_COLOR = { 0.45, 0.45, 0.52, 1 }
local DIVIDER_COLOR = { 1, 0.82, 0, 0.35 }
local SUBTITLE_COLOR = { 0.7, 0.7, 0.74 }
local NOTES_COLOR = { 0.85, 0.85, 0.87 }
local FEATURES_COLOR = { 0.68, 0.68, 0.72 }
local FOOTER_COLOR = { 0.55, 0.55, 0.6 }

local STATE = {
    LOADED = "loaded",
    DISABLED = "disabled",
    MISSING = "missing",
}
local STATE_COLOR = {
    loaded = { 0.3, 0.9, 0.35 },
    disabled = { 1, 0.75, 0.2 },
    missing = { 0.55, 0.55, 0.6 },
}
local DOT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- the module's own icons, in the folder of the addon that carries it
local PICTURE_FOLDER = "Interface\\AddOns\\" .. ADDON .. "\\shared\\other_addons\\icons\\"

-- loaded -- installed and on; disabled -- installed, turned off (or not loaded);
-- missing -- not in the AddOns folder
local function AddonState(folder)
    local addOns = C_AddOns or {}
    local isLoaded = addOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded and isLoaded(folder) then
        return STATE.LOADED
    end
    if addOns.DoesAddOnExist then
        local ok, exists = pcall(addOns.DoesAddOnExist, folder)
        if ok then
            return exists and STATE.DISABLED or STATE.MISSING
        end
    end
    local getInfo = addOns.GetAddOnInfo or GetAddOnInfo
    if getInfo then
        local ok, name, _, _, _, reason = pcall(getInfo, folder)
        if ok and name and reason ~= "MISSING" then
            return STATE.DISABLED
        end
    end
    return STATE.MISSING
end

-- { "a", "b" } -> "• a\n• b"
local function Points(features)
    local lines = {}
    for _, feature in ipairs(features or {}) do
        table.insert(lines, BULLET .. feature)
    end
    return table.concat(lines, "\n")
end

-- the client's language, or the one in options.language
local function Language(options)
    if options and options.language then
        return options.language
    end
    local locale = GetLocale and GetLocale() or ""
    return CLIENT_LANGUAGES[locale] or FALLBACK_LANGUAGE
end

-- the text at a path ("state", "loaded") in the language, else in English; nil -- none
local function TextIn(language, ...)
    local all = OtherAddons.texts or {}
    local sources = { all[language], all[FALLBACK_LANGUAGE] }
    for sourceIndex = 1, 2 do
        local value = sources[sourceIndex]
        for index = 1, select("#", ...) do
            if type(value) ~= "table" then
                value = nil
                break
            end
            value = value[(select(index, ...))]
        end
        if value ~= nil then
            return value
        end
    end
    return nil
end

-- a 1 pixel frame of four textures; returns them, to recolor
local function PixelBorder(frame, color)
    local edges = {}
    local sides = {
        { "TOPLEFT", "TOPRIGHT", "height" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
        { "TOPLEFT", "BOTTOMLEFT", "width" },
        { "TOPRIGHT", "BOTTOMRIGHT", "width" },
    }
    for _, side in ipairs(sides) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(color[1], color[2], color[3], color[4])
        edge:SetPoint(side[1])
        edge:SetPoint(side[2])
        if side[3] == "height" then
            edge:SetHeight(1)
        else
            edge:SetWidth(1)
        end
        table.insert(edges, edge)
    end
    return edges
end

local function Paint(textures, color)
    for _, texture in ipairs(textures) do
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

local function MakeCard(parent, addon, text)
    local card = CreateFrame("Frame", nil, parent)
    card:EnableMouse(true)

    local background = card:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(CARD_COLOR[1], CARD_COLOR[2], CARD_COLOR[3], CARD_COLOR[4])
    local border = PixelBorder(card, BORDER_COLOR)

    -- a thin bar on the left in the color of the status
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", 1, 1)
    accent:SetWidth(ACCENT_WIDTH)

    -- the icon in a dark frame, at the top left
    local iconFrame = card:CreateTexture(nil, "ARTWORK")
    iconFrame:SetColorTexture(0, 0, 0, 1)
    iconFrame:SetSize(ICON_SIZE + ICON_FRAME * 2, ICON_SIZE + ICON_FRAME * 2)
    iconFrame:SetPoint("TOPLEFT", CARD_INSET, -CARD_INSET)
    local icon = card:CreateTexture(nil, "OVERLAY")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", iconFrame, "CENTER")
    -- a CurseForge icon whole; a game icon without its built-in edge
    if addon.picture then
        icon:SetTexture(PICTURE_FOLDER .. addon.picture)
    else
        icon:SetTexture(addon.icon)
        icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    end

    -- the status at the top right: a round dot and its word
    local status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPRIGHT", -CARD_INSET, -CARD_INSET - 4)
    status:SetJustifyH("RIGHT")
    local dot = card:CreateTexture(nil, "OVERLAY")
    dot:SetSize(STATUS_DOT_SIZE, STATUS_DOT_SIZE)
    dot:SetPoint("RIGHT", status, "LEFT", -6, 0)
    if card.CreateMaskTexture then
        local mask = card:CreateMaskTexture()
        if mask then
            mask:SetTexture(DOT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(dot)
            dot:AddMaskTexture(mask)
        end
    end

    local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", TEXT_GAP, -2)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(addon.title)

    local notes = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    notes:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -LINE_GAP)
    notes:SetJustifyH("LEFT")
    notes:SetJustifyV("TOP")
    notes:SetTextColor(NOTES_COLOR[1], NOTES_COLOR[2], NOTES_COLOR[3])
    notes:SetText(text("notes", addon.id) or "")

    local features = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    features:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -FEATURES_GAP)
    features:SetJustifyH("LEFT")
    features:SetJustifyV("TOP")
    features:SetSpacing(FEATURE_SPACING)
    features:SetTextColor(FEATURES_COLOR[1], FEATURES_COLOR[2], FEATURES_COLOR[3])
    features:SetText(Points(text("features", addon.id)))

    card:SetScript("OnEnter", function()
        background:SetColorTexture(CARD_HOVER_COLOR[1], CARD_HOVER_COLOR[2], CARD_HOVER_COLOR[3], CARD_HOVER_COLOR[4])
        Paint(border, BORDER_HOVER_COLOR)
    end)
    card:SetScript("OnLeave", function()
        background:SetColorTexture(CARD_COLOR[1], CARD_COLOR[2], CARD_COLOR[3], CARD_COLOR[4])
        Paint(border, BORDER_COLOR)
    end)

    -- the texts wrap in the width of the card; the card is as tall as they are
    function card:Fit(width)
        local textLeft = CARD_INSET + ICON_SIZE + ICON_FRAME * 2 + TEXT_GAP
        local textWidth = math.max(1, width - textLeft - CARD_INSET)
        name:SetWidth(math.max(1, textWidth - STATUS_WIDTH))
        notes:SetWidth(textWidth)
        features:SetWidth(textWidth)
        local textHeight = (name:GetStringHeight() or 0) + LINE_GAP + (notes:GetStringHeight() or 0)
            + FEATURES_GAP + (features:GetStringHeight() or 0)
        local height = math.max(ICON_SIZE + ICON_FRAME * 2, textHeight + 2) + CARD_INSET * 2
        self:SetSize(width, height)
        return height
    end

    -- the status; the picture of an addon not installed is grey
    function card:Refresh()
        local state = AddonState(addon.folder)
        local color = STATE_COLOR[state]
        accent:SetColorTexture(color[1], color[2], color[3], 1)
        dot:SetColorTexture(color[1], color[2], color[3], 1)
        status:SetText(text("state", state) or "")
        status:SetTextColor(color[1], color[2], color[3])
        icon:SetDesaturated(state == STATE.MISSING)
        icon:SetAlpha(state == STATE.MISSING and 0.7 or 1)
        return state
    end

    return card
end

function OtherAddons.CreatePage(parent, options)
    options = options or {}
    local language = Language(options)
    local function text(...)
        return TextIn(language, ...)
    end
    local page = CreateFrame("Frame", nil, parent)

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText(text("title") or "")

    local subtitle = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -HEADER_GAP)
    subtitle:SetPoint("RIGHT", page, "RIGHT", -PADDING, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(SUBTITLE_COLOR[1], SUBTITLE_COLOR[2], SUBTITLE_COLOR[3])

    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -DIVIDER_GAP / 2)
    divider:SetPoint("RIGHT", page, "RIGHT", -PADDING, 0)
    divider:SetColorTexture(DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], DIVIDER_COLOR[4])

    -- the cards and the footer in a scroll frame under the header
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -DIVIDER_GAP)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(PADDING + SCROLL_BAR_SPACE), PADDING)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local cards = {}
    for _, addon in ipairs(OtherAddons.list or {}) do
        if addon.folder ~= options.exclude then
            table.insert(cards, MakeCard(content, addon, text))
        end
    end

    local footer = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetJustifyH("LEFT")
    footer:SetTextColor(FOOTER_COLOR[1], FOOTER_COLOR[2], FOOTER_COLOR[3])
    footer:SetText(text("footer") or "")

    -- stack the cards in the width the scroll frame has now
    local function Layout()
        local width = scroll:GetWidth() or 0
        if width <= 1 then
            return
        end
        content:SetWidth(width)
        local top = 0
        for _, card in ipairs(cards) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
            top = top + card:Fit(width) + CARD_GAP
        end
        footer:ClearAllPoints()
        footer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(top + DIVIDER_GAP / 2))
        footer:SetWidth(width)
        content:SetHeight(top + DIVIDER_GAP / 2 + (footer:GetStringHeight() or 0))
    end
    scroll:SetScript("OnSizeChanged", Layout)

    function page:Refresh()
        local installed = 0
        for _, card in ipairs(cards) do
            if card:Refresh() ~= STATE.MISSING then
                installed = installed + 1
            end
        end
        subtitle:SetText(string.format(text("subtitle") or "%d / %d", installed, #cards))
        Layout()
    end

    page.cards = cards
    page:SetScript("OnShow", function(self)
        self:Refresh()
    end)
    page:Refresh()
    return page
end

-- "Other addons" under the addon's own category in the game's settings; nothing
-- on a client without the settings API. category -- what
-- Settings.RegisterCanvasLayoutCategory returned for the addon.
function OtherAddons.Register(category, options)
    local hasApi = Settings and Settings.RegisterCanvasLayoutSubcategory
    if not (category and hasApi) then
        return nil
    end
    local page = OtherAddons.CreatePage(UIParent, options)
    page:Hide()
    return Settings.RegisterCanvasLayoutSubcategory(category, page, TextIn(Language(options), "title"))
end
