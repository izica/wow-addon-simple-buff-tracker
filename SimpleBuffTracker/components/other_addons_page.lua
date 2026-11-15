-- other_addons_page.lua -- the "Other addons" page of the settings: the
-- author's other addons as cards -- icon, name, description and whether it is
-- installed (installed / installed but turned off / not installed).
--
-- Shared between the author's addons: the same file in each. It needs only the
-- game's API and what it is given: the list (config/other_addons.lua), the
-- texts (other_addons.* in lang/*.json, through options.text) and the addon to
-- leave out -- the one the page is in.
--
--   ns.Components.OtherAddonsPage.Create(parent, {
--       addons = ns.Config.OTHER_ADDONS,
--       exclude = "SimpleBuffTracker",           -- folder of the addon to leave out
--       text = ns.Localization.Text,             -- text(key, ...) -> string
--   }) -> frame; the statuses are read again every time the page is shown.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local OtherAddonsPage = {}
ns.Components.OtherAddonsPage = OtherAddonsPage

local PADDING = 24
local HEADER_GAP = 6
local DIVIDER_GAP = 16
local CARD_HEIGHT = 76
local CARD_GAP = 10
local ICON_SIZE = 46
local ICON_INSET = 16
local ICON_CROP = 0.08
local ICON_FRAME = 2
local TEXT_GAP = 14
local STATUS_WIDTH = 150
local STATUS_DOT_SIZE = 8
local ACCENT_WIDTH = 3
local NOTES_LINES = 2

local CARD_COLOR = { 0.07, 0.07, 0.09, 0.9 }
local CARD_HOVER_COLOR = { 0.11, 0.11, 0.14, 0.95 }
local BORDER_COLOR = { 0.24, 0.24, 0.28, 1 }
local BORDER_HOVER_COLOR = { 0.45, 0.45, 0.52, 1 }
local DIVIDER_COLOR = { 1, 0.82, 0, 0.35 }
local SUBTITLE_COLOR = { 0.7, 0.7, 0.74 }
local NOTES_COLOR = { 0.78, 0.78, 0.8 }
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

local function MakeCard(page, addon, text)
    local card = CreateFrame("Frame", nil, page)
    card:SetHeight(CARD_HEIGHT)
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

    -- the icon in a dark frame
    local iconFrame = card:CreateTexture(nil, "ARTWORK")
    iconFrame:SetColorTexture(0, 0, 0, 1)
    iconFrame:SetSize(ICON_SIZE + ICON_FRAME * 2, ICON_SIZE + ICON_FRAME * 2)
    iconFrame:SetPoint("LEFT", ICON_INSET, 0)
    local icon = card:CreateTexture(nil, "OVERLAY")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", iconFrame, "CENTER")
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    -- the status on the right: a round dot and its word
    local status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("RIGHT", -ICON_INSET, 0)
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
    name:SetPoint("RIGHT", card, "RIGHT", -(ICON_INSET + STATUS_WIDTH), 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(addon.title)

    local notes = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notes:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    notes:SetPoint("RIGHT", card, "RIGHT", -(ICON_INSET + STATUS_WIDTH), 0)
    notes:SetJustifyH("LEFT")
    notes:SetJustifyV("TOP")
    notes:SetTextColor(NOTES_COLOR[1], NOTES_COLOR[2], NOTES_COLOR[3])
    if notes.SetMaxLines then
        notes:SetMaxLines(NOTES_LINES)
    end
    notes:SetText(text("other_addons.notes." .. addon.id))

    card:SetScript("OnEnter", function()
        background:SetColorTexture(CARD_HOVER_COLOR[1], CARD_HOVER_COLOR[2], CARD_HOVER_COLOR[3], CARD_HOVER_COLOR[4])
        Paint(border, BORDER_HOVER_COLOR)
    end)
    card:SetScript("OnLeave", function()
        background:SetColorTexture(CARD_COLOR[1], CARD_COLOR[2], CARD_COLOR[3], CARD_COLOR[4])
        Paint(border, BORDER_COLOR)
    end)

    -- the status and the picture (an own picture only while installed)
    function card:Refresh()
        local state = AddonState(addon.folder)
        local color = STATE_COLOR[state]
        accent:SetColorTexture(color[1], color[2], color[3], 1)
        dot:SetColorTexture(color[1], color[2], color[3], 1)
        status:SetText(text("other_addons.state." .. state))
        status:SetTextColor(color[1], color[2], color[3])
        local picture = addon.icon
        if state == STATE.MISSING and addon.fallbackIcon then
            picture = addon.fallbackIcon
        end
        icon:SetTexture(picture)
        icon:SetDesaturated(state == STATE.MISSING)
        icon:SetAlpha(state == STATE.MISSING and 0.7 or 1)
        return state
    end

    return card
end

function OtherAddonsPage.Create(parent, options)
    local text = options.text
    local page = CreateFrame("Frame", nil, parent)

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText(text("other_addons.title"))

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

    local cards = {}
    local previous = divider
    for _, addon in ipairs(options.addons) do
        if addon.folder ~= options.exclude then
            local card = MakeCard(page, addon, text)
            local gap = CARD_GAP
            if previous == divider then
                gap = DIVIDER_GAP
            end
            card:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -gap)
            card:SetPoint("RIGHT", page, "RIGHT", -PADDING, 0)
            table.insert(cards, card)
            previous = card
        end
    end

    local footer = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -DIVIDER_GAP)
    footer:SetPoint("RIGHT", page, "RIGHT", -PADDING, 0)
    footer:SetJustifyH("LEFT")
    footer:SetTextColor(FOOTER_COLOR[1], FOOTER_COLOR[2], FOOTER_COLOR[3])
    footer:SetText(text("other_addons.footer"))

    function page:Refresh()
        local installed = 0
        for _, card in ipairs(cards) do
            if card:Refresh() ~= STATE.MISSING then
                installed = installed + 1
            end
        end
        subtitle:SetText(text("other_addons.subtitle", installed, #cards))
    end

    page.cards = cards
    page:SetScript("OnShow", function(self)
        self:Refresh()
    end)
    page:Refresh()
    return page
end
