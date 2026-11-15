-- about_page.lua -- the addon's main page in Options -> AddOns: its icon,
-- name, version and what it does, and a big button that closes the game's
-- settings and opens the addon's own window.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local AboutPage = {}
ns.Components.AboutPage = AboutPage

local PADDING = 24
local ICON_SIZE = 72
local ICON_FRAME = 3
local TITLE_GAP = 16
local SECTION_GAP = 22
local BUTTON_WIDTH = 320
local BUTTON_HEIGHT = 44
local TEXT_WIDTH = 560
local VERSION_COLOR = { 0.6, 0.6, 0.65 }
local DESCRIPTION_COLOR = { 0.85, 0.85, 0.87 }
local HINT_COLOR = { 0.55, 0.55, 0.6 }
local DIVIDER_COLOR = { 1, 0.82, 0, 0.35 }

local function AddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getMetadata then
        return nil
    end
    local ok, version = pcall(getMetadata, ADDON, "Version")
    if ok then
        return version
    end
    return nil
end

-- options: onOpen() -- the big button
function AboutPage.Create(parent, options)
    local page = CreateFrame("Frame", nil, parent)

    local iconFrame = page:CreateTexture(nil, "ARTWORK")
    iconFrame:SetColorTexture(0, 0, 0, 1)
    iconFrame:SetSize(ICON_SIZE + ICON_FRAME * 2, ICON_SIZE + ICON_FRAME * 2)
    iconFrame:SetPoint("TOPLEFT", PADDING, -PADDING)
    local icon = page:CreateTexture(nil, "OVERLAY")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", iconFrame, "CENTER")
    icon:SetTexture(ns.Constants.ADDON_ICON)

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", TITLE_GAP, -8)
    title:SetText(ns.Constants.ADDON_TITLE)

    local version = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    version:SetTextColor(VERSION_COLOR[1], VERSION_COLOR[2], VERSION_COLOR[3])
    local versionText = AddonVersion()
    if versionText then
        version:SetText(Text("about.version", versionText))
    end

    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", iconFrame, "BOTTOMLEFT", 0, -SECTION_GAP / 2)
    divider:SetPoint("RIGHT", page, "RIGHT", -PADDING, 0)
    divider:SetColorTexture(DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], DIVIDER_COLOR[4])

    local description = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -SECTION_GAP / 2)
    description:SetWidth(TEXT_WIDTH)
    description:SetJustifyH("LEFT")
    description:SetSpacing(4)
    description:SetTextColor(DESCRIPTION_COLOR[1], DESCRIPTION_COLOR[2], DESCRIPTION_COLOR[3])
    description:SetText(Text("about.description"))

    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -SECTION_GAP)
    button:SetText(Text("about.open"))
    local buttonText = button:GetFontString()
    if buttonText then
        buttonText:SetFontObject("GameFontNormalLarge")
    end
    button:SetScript("OnClick", function()
        options.onOpen()
    end)
    page.openButton = button

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -10)
    hint:SetWidth(TEXT_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3])
    hint:SetText(Text("about.hint"))

    return page
end
