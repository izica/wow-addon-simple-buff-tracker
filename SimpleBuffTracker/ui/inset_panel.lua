-- inset_panel.lua -- a framed inner panel, like the two halves of the profession
-- window on Forever: the game's InsetFrameTemplate border (a NineSlice layout,
-- the same as the recipe list and the recipe form use) over an atlas
-- background or a dark fill.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local INSET_LAYOUT = "InsetFrameTemplate"
local BACKGROUND_INSET = 3
local FILL_COLOR = { 0.03, 0.03, 0.04, 0.6 }

-- options: backgroundAtlas -- nil or missing on this client: a dark fill
function ns.UI.InsetPanel(parent, options)
    local panel = CreateFrame("Frame", nil, parent)

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", BACKGROUND_INSET, -BACKGROUND_INSET)
    background:SetPoint("BOTTOMRIGHT", -BACKGROUND_INSET, BACKGROUND_INSET)
    local hasAtlas = options.backgroundAtlas and C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(options.backgroundAtlas)
    if hasAtlas then
        background:SetAtlas(options.backgroundAtlas)
    else
        background:SetColorTexture(FILL_COLOR[1], FILL_COLOR[2], FILL_COLOR[3], FILL_COLOR[4])
    end

    local border = CreateFrame("Frame", nil, panel)
    border:SetAllPoints()
    local isBordered = NineSliceUtil and NineSliceUtil.ApplyLayoutByName
        and pcall(NineSliceUtil.ApplyLayoutByName, border, INSET_LAYOUT)
    if not isBordered then
        border:Hide()
    end
    return panel
end
