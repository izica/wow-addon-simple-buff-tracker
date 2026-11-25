-- tag_select.lua -- a field that holds tags and opens a menu: the picked values
-- stand inside the field as small framed tags, an arrow on the right; a click
-- on the field opens the game's menu (Blizzard_Menu, as the dropdowns), where
-- the caller builds whatever it needs -- submenus with checkboxes, a tree.
-- A click on a tag takes it out. The field grows a row when the tags do not
-- fit. The look is the game's dropdown text holder, as our other fields
-- (ui/input.lua), the tags framed in bronze like its edge.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local FRAME_ATLAS = "common-dropdown-textholder"
local ARROW_TEMPLATE = "WowStyle1ArrowDropdownTemplate"
local ARROW_WIDTH = 22
local INSET_LEFT = 6
local INSET_TOP = 3
local ROW_HEIGHT = 19               -- one row of tags; the field is 25 high with one row
local TAG_HEIGHT = 17
local TAG_GAP = 4
local TAG_TEXT_PADDING = 6
local CROSS_SIZE = 10
local CROSS_GAP = 4
local MIN_TAG_WIDTH = 30
local FALLBACK_WIDTH = 300          -- before the client laid the field out
local MENU_GAP = 4
local CROSS_TEXTURE = "Interface\\Buttons\\UI-StopButton"
local TAG_BORDER_COLOR = { 0.55, 0.45, 0.25, 1 }     -- the bronze of the field's edge
local TAG_FILL_COLOR = { 0.08, 0.07, 0.05, 1 }
local TAG_HOVER_BORDER_COLOR = { 1, 0.82, 0, 1 }
local CROSS_ALPHA = 0.55
local PLAIN_FILL = { 0, 0, 0, 0.5 }
local PLAIN_EDGE = { 0.4, 0.4, 0.45, 1 }
local TOOLTIP_TEXT_COLOR = { 1, 1, 1 }

-- the field's frame: the dropdown text holder, or a thin edge without it
local function AddFrameArt(field)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FRAME_ATLAS)
    if hasAtlas then
        local art = field:CreateTexture(nil, "BACKGROUND")
        art:SetAtlas(FRAME_ATLAS)
        art:SetPoint("TOPLEFT", -8, 7)
        art:SetPoint("BOTTOMRIGHT", 8, -9)
        return
    end
    local edge = field:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(PLAIN_EDGE[1], PLAIN_EDGE[2], PLAIN_EDGE[3], PLAIN_EDGE[4])
    local fill = field:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(PLAIN_FILL[1], PLAIN_FILL[2], PLAIN_FILL[3], PLAIN_FILL[4])
end

local function PaintTagBorder(tag, color)
    tag.border:SetColorTexture(color[1], color[2], color[3], color[4])
end

-- options: placeholder -- shown while there are no tags, removeTooltip,
-- buildMenu(rootDescription) -- the menu (MenuUtil element descriptions),
-- onRemove(index) -- a tag clicked.
-- field:SetTags({ text, ... }), field:GetContentHeight(), field:RefreshMenu(),
-- field.BuildMenu -- the menu builder (the tests walk it without the game's menu).
function ns.UI.TagSelect(parent, options)
    local field = CreateFrame("Button", nil, parent)
    AddFrameArt(field)
    local tags = {}            -- every tag button made, reused
    local contentHeight = ROW_HEIGHT
    field.BuildMenu = options.buildMenu

    local placeholder = field:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("TOPLEFT", INSET_LEFT + 2, -INSET_TOP - 3)
    placeholder:SetText(options.placeholder or "")

    -- the game's dropdown arrow: it owns the menu; the whole field opens it
    local ok, arrow = pcall(CreateFrame, "DropdownButton", nil, field, ARROW_TEMPLATE)
    local hasMenu = ok and arrow ~= nil and arrow.SetupMenu ~= nil
    if hasMenu then
        arrow:SetSize(ARROW_WIDTH, ARROW_WIDTH)
        arrow:SetPoint("TOPRIGHT", 0, -1)
        arrow:SetupMenu(function(_, rootDescription)
            options.buildMenu(rootDescription)
        end)
        if arrow.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
            arrow:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", field, "BOTTOMLEFT", 0, -MENU_GAP))
        end
        field:SetScript("OnClick", function()
            if arrow:IsMenuOpen() then
                arrow:CloseMenu()
            else
                arrow:OpenMenu()
            end
        end)
    end

    -- the menu shows the picks again after they changed outside of it
    function field:RefreshMenu()
        if hasMenu and arrow.GenerateMenu then
            arrow:GenerateMenu()
        end
    end

    local function GetTag(index)
        local tag = tags[index]
        if tag then
            return tag
        end
        tag = CreateFrame("Button", nil, field)
        tag:SetHeight(TAG_HEIGHT)
        tag.border = tag:CreateTexture(nil, "BACKGROUND")
        tag.border:SetAllPoints()
        tag.fill = tag:CreateTexture(nil, "BORDER")
        tag.fill:SetPoint("TOPLEFT", 1, -1)
        tag.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        tag.fill:SetColorTexture(TAG_FILL_COLOR[1], TAG_FILL_COLOR[2], TAG_FILL_COLOR[3], TAG_FILL_COLOR[4])
        PaintTagBorder(tag, TAG_BORDER_COLOR)
        tag.label = tag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tag.label:SetPoint("LEFT", TAG_TEXT_PADDING, 0)
        tag.cross = tag:CreateTexture(nil, "OVERLAY")
        tag.cross:SetTexture(CROSS_TEXTURE)
        tag.cross:SetSize(CROSS_SIZE, CROSS_SIZE)
        tag.cross:SetPoint("RIGHT", -TAG_TEXT_PADDING + 2, 0)
        tag.cross:SetAlpha(CROSS_ALPHA)

        tag:SetScript("OnEnter", function(self)
            PaintTagBorder(self, TAG_HOVER_BORDER_COLOR)
            self.cross:SetAlpha(1)
            if options.removeTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(options.removeTooltip,
                    TOOLTIP_TEXT_COLOR[1], TOOLTIP_TEXT_COLOR[2], TOOLTIP_TEXT_COLOR[3], true)
                GameTooltip:Show()
            end
        end)
        tag:SetScript("OnLeave", function(self)
            PaintTagBorder(self, TAG_BORDER_COLOR)
            self.cross:SetAlpha(CROSS_ALPHA)
            GameTooltip:Hide()
        end)
        tag:SetScript("OnClick", function(self)
            GameTooltip:Hide()
            options.onRemove(self.index)
        end)
        tags[index] = tag
        return tag
    end

    local function RowWidth()
        local width = field:GetWidth()
        if not width or width <= 0 then
            width = FALLBACK_WIDTH
        end
        return width - INSET_LEFT - ARROW_WIDTH
    end

    -- the tags in rows; the form lays the field out by GetContentHeight
    function field:SetTags(list)
        local rowWidth = RowWidth()
        local x = 0
        local row = 0
        for index, entry in ipairs(list) do
            local tag = GetTag(index)
            tag.index = index
            tag.label:SetText(entry.text)
            tag.text = entry.text   -- what the tag says (the tests click tags by it)
            local textWidth = tag.label:GetStringWidth() or 0
            local width = math.max(MIN_TAG_WIDTH, textWidth + TAG_TEXT_PADDING * 2 + CROSS_GAP + CROSS_SIZE)
            width = math.min(width, rowWidth)
            tag:SetWidth(width)
            if x > 0 and x + width > rowWidth then
                x = 0
                row = row + 1
            end
            tag:ClearAllPoints()
            tag:SetPoint("TOPLEFT", field, "TOPLEFT", INSET_LEFT + x, -INSET_TOP - row * ROW_HEIGHT - 1)
            tag:Show()
            x = x + width + TAG_GAP
        end
        for index = #list + 1, #tags do
            tags[index]:Hide()
        end
        placeholder:SetShown(#list == 0)
        contentHeight = (row + 1) * ROW_HEIGHT
    end

    -- the height of the field: its rows and the insets
    function field:GetContentHeight()
        return contentHeight + INSET_TOP * 2
    end

    field:SetTags({})
    return field
end
