-- tag_select.lua -- a picker with badges under it: a one-line field in the look
-- of the game's dropdowns (the same text holder as our other fields,
-- ui/input.lua) that opens the game's menu (Blizzard_Menu), where the caller
-- builds whatever it needs -- submenus with checkboxes, a tree. The field
-- tells how many values are picked; the values themselves stand under it as
-- small bronze-framed badges, in rows. A click on a badge takes it out.
--
-- The text holder art is made for one line: it is never stretched, the badges
-- live outside it.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local FRAME_ATLAS = "common-dropdown-textholder"
local ARROW_TEMPLATE = "WowStyle1ArrowDropdownTemplate"
-- the picker is a field of the form: 25 high, the art sticks out as on the
-- dropdowns (Blizzard_Menu/Mainline/MenuTemplates.xml)
local PICKER_HEIGHT = 25
local ART_OUTSET_LEFT = 8
local ART_OUTSET_TOP = 7
local ART_OUTSET_RIGHT = 8
local ART_OUTSET_BOTTOM = 9
local TEXT_INSET = 9
local ARROW_SIZE = 22
local ARROW_RIGHT = 2
local MENU_GAP = 4
-- the badges: under the art's bottom edge, rows with even gaps
local BADGES_TOP = PICKER_HEIGHT + ART_OUTSET_BOTTOM + 3
local BADGE_HEIGHT = 18
local BADGE_GAP = 4                 -- between badges in a row
local ROW_GAP = 4                   -- between rows
local BADGE_TEXT_PADDING = 6
local CROSS_SIZE = 10
local CROSS_GAP = 4
local MIN_BADGE_WIDTH = 30
local FALLBACK_WIDTH = 300          -- before the client laid the field out
local CROSS_TEXTURE = "Interface\\Buttons\\UI-StopButton"
local BADGE_BORDER_COLOR = { 0.55, 0.45, 0.25, 1 }     -- the bronze of the field's edge
local BADGE_FILL_COLOR = { 0.12, 0.09, 0.05, 0.95 }
local BADGE_HOVER_BORDER_COLOR = { 1, 0.82, 0, 1 }
local BADGE_HOVER_FILL_COLOR = { 0.22, 0.16, 0.06, 0.95 }
local CROSS_ALPHA = 0.55
local PLAIN_FILL = { 0, 0, 0, 0.5 }
local PLAIN_EDGE = { 0.4, 0.4, 0.45, 1 }
local TOOLTIP_TEXT_COLOR = { 1, 1, 1 }

-- the picker's frame: the dropdown text holder, or a thin edge without it
local function AddFrameArt(picker)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FRAME_ATLAS)
    if hasAtlas then
        local art = picker:CreateTexture(nil, "BACKGROUND")
        art:SetAtlas(FRAME_ATLAS)
        art:SetPoint("TOPLEFT", -ART_OUTSET_LEFT, ART_OUTSET_TOP)
        art:SetPoint("BOTTOMRIGHT", ART_OUTSET_RIGHT, -ART_OUTSET_BOTTOM)
        return
    end
    local edge = picker:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(PLAIN_EDGE[1], PLAIN_EDGE[2], PLAIN_EDGE[3], PLAIN_EDGE[4])
    local fill = picker:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(PLAIN_FILL[1], PLAIN_FILL[2], PLAIN_FILL[3], PLAIN_FILL[4])
end

local function PaintBadge(badge, border, fill)
    badge.border:SetColorTexture(border[1], border[2], border[3], border[4])
    badge.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
end

-- options: placeholder -- the picker's text while nothing is picked,
-- summary(count) -- its text with picks, removeTooltip,
-- buildMenu(rootDescription) -- the menu (MenuUtil element descriptions),
-- onRemove(index) -- a badge clicked.
-- field:SetTags({ { text }, ... }), field:GetContentHeight() -- the picker and
-- the badges, field:RefreshMenu(), field.BuildMenu -- the menu builder (the
-- tests walk it without the game's menu).
function ns.UI.TagSelect(parent, options)
    local field = CreateFrame("Frame", nil, parent)
    local badges = {}          -- every badge made, reused
    local rowCount = 0
    field.BuildMenu = options.buildMenu

    local picker = CreateFrame("Button", nil, field)
    picker:SetPoint("TOPLEFT")
    picker:SetPoint("TOPRIGHT")
    picker:SetHeight(PICKER_HEIGHT)
    AddFrameArt(picker)

    local pickerText = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pickerText:SetPoint("LEFT", TEXT_INSET, 0)
    pickerText:SetPoint("RIGHT", -(ARROW_RIGHT + ARROW_SIZE + 4), 0)
    pickerText:SetJustifyH("LEFT")
    pickerText:SetWordWrap(false)

    -- the game's dropdown arrow: it owns the menu; the whole picker opens it
    local ok, arrow = pcall(CreateFrame, "DropdownButton", nil, picker, ARROW_TEMPLATE)
    local hasMenu = ok and arrow ~= nil and arrow.SetupMenu ~= nil
    if hasMenu then
        arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
        arrow:SetPoint("RIGHT", -ARROW_RIGHT, 0)
        arrow:SetupMenu(function(_, rootDescription)
            options.buildMenu(rootDescription)
        end)
        if arrow.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
            arrow:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", picker, "BOTTOMLEFT", 0, -MENU_GAP))
        end
        picker:SetScript("OnClick", function()
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

    local function GetBadge(index)
        local badge = badges[index]
        if badge then
            return badge
        end
        badge = CreateFrame("Button", nil, field)
        badge:SetHeight(BADGE_HEIGHT)
        badge.border = badge:CreateTexture(nil, "BACKGROUND")
        badge.border:SetAllPoints()
        badge.fill = badge:CreateTexture(nil, "BORDER")
        badge.fill:SetPoint("TOPLEFT", 1, -1)
        badge.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        PaintBadge(badge, BADGE_BORDER_COLOR, BADGE_FILL_COLOR)
        badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        badge.label:SetPoint("LEFT", BADGE_TEXT_PADDING, 0)
        badge.cross = badge:CreateTexture(nil, "OVERLAY")
        badge.cross:SetTexture(CROSS_TEXTURE)
        badge.cross:SetSize(CROSS_SIZE, CROSS_SIZE)
        badge.cross:SetPoint("RIGHT", -BADGE_TEXT_PADDING + 2, 0)
        badge.cross:SetAlpha(CROSS_ALPHA)

        badge:SetScript("OnEnter", function(self)
            PaintBadge(self, BADGE_HOVER_BORDER_COLOR, BADGE_HOVER_FILL_COLOR)
            self.cross:SetAlpha(1)
            if options.removeTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(options.removeTooltip,
                    TOOLTIP_TEXT_COLOR[1], TOOLTIP_TEXT_COLOR[2], TOOLTIP_TEXT_COLOR[3], true)
                GameTooltip:Show()
            end
        end)
        badge:SetScript("OnLeave", function(self)
            PaintBadge(self, BADGE_BORDER_COLOR, BADGE_FILL_COLOR)
            self.cross:SetAlpha(CROSS_ALPHA)
            GameTooltip:Hide()
        end)
        badge:SetScript("OnClick", function(self)
            GameTooltip:Hide()
            options.onRemove(self.index)
        end)
        badges[index] = badge
        return badge
    end

    local function RowWidth()
        local width = field:GetWidth()
        if not width or width <= 0 then
            width = FALLBACK_WIDTH
        end
        return width
    end

    -- the picker's text and the badges in rows; the form lays the field out
    -- by GetContentHeight
    function field:SetTags(list)
        if #list == 0 then
            pickerText:SetFontObject("GameFontDisableSmall")
            pickerText:SetText(options.placeholder or "")
        else
            pickerText:SetFontObject("GameFontHighlightSmall")
            pickerText:SetText(options.summary and options.summary(#list) or "")
        end

        local rowWidth = RowWidth()
        local x = 0
        local row = 0
        for index, entry in ipairs(list) do
            local badge = GetBadge(index)
            badge.index = index
            badge.label:SetText(entry.text)
            badge.text = entry.text   -- what the badge says (the tests click badges by it)
            local textWidth = badge.label:GetStringWidth() or 0
            local width = math.max(MIN_BADGE_WIDTH, textWidth + BADGE_TEXT_PADDING * 2 + CROSS_GAP + CROSS_SIZE)
            width = math.min(width, rowWidth)
            badge:SetWidth(width)
            if x > 0 and x + width > rowWidth then
                x = 0
                row = row + 1
            end
            badge:ClearAllPoints()
            badge:SetPoint("TOPLEFT", field, "TOPLEFT", x, -BADGES_TOP - row * (BADGE_HEIGHT + ROW_GAP))
            badge:Show()
            x = x + width + BADGE_GAP
        end
        for index = #list + 1, #badges do
            badges[index]:Hide()
        end
        if #list == 0 then
            rowCount = 0
        else
            rowCount = row + 1
        end
    end

    -- the picker alone, or the picker and the rows of badges under it
    function field:GetContentHeight()
        if rowCount == 0 then
            return PICKER_HEIGHT
        end
        return BADGES_TOP + rowCount * BADGE_HEIGHT + (rowCount - 1) * ROW_GAP
    end

    field:SetTags({})
    return field
end
