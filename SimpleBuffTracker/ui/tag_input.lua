-- tag_input.lua -- a field that holds tags: the picked values stand inside the
-- field as small framed tags, the cursor after them; the field grows a row
-- when they do not fit. Typing drops suggestions under it (ui/suggestions.lua),
-- and with nothing typed the list opens on focus (the zone the player is in,
-- for example). A click on a tag takes it out; Backspace in the empty field
-- takes out the last one. The look is the game's dropdown text holder, as our
-- other fields (ui/input.lua), the tags framed in bronze like its edge.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local FRAME_ATLAS = "common-dropdown-textholder"
local INSET_LEFT = 6
local INSET_RIGHT = 6
local INSET_TOP = 3
local ROW_HEIGHT = 19               -- one row of tags; the field is 25 high with one row
local TAG_HEIGHT = 17
local TAG_GAP = 4
local TAG_TEXT_PADDING = 6
local CROSS_SIZE = 10
local CROSS_GAP = 4
local MIN_TAG_WIDTH = 30
local MIN_EDIT_WIDTH = 90           -- less room left in the row: the cursor goes to a new row
local FALLBACK_WIDTH = 300          -- before the client laid the field out
local CROSS_TEXTURE = "Interface\\Buttons\\UI-StopButton"
local TAG_BORDER_COLOR = { 0.55, 0.45, 0.25, 1 }     -- the bronze of the field's edge
local TAG_FILL_COLOR = { 0.08, 0.07, 0.05, 1 }
local TAG_HOVER_BORDER_COLOR = { 1, 0.82, 0, 1 }
local CROSS_ALPHA = 0.55
local PLAIN_FILL = { 0, 0, 0, 0.5 }
local PLAIN_EDGE = { 0.4, 0.4, 0.45, 1 }
local TOOLTIP_TEXT_COLOR = { 1, 1, 1 }

ns.UI.TAG_INPUT_ROW_HEIGHT = ROW_HEIGHT

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

-- options: placeholder, removeTooltip, search(text) -> suggestions (text may be
-- empty: what to offer on focus), onChoose(suggestion), onRemove(index),
-- onSubmit(text) -- typed text left in the field (Enter or the focus lost).
-- field:SetTags({ text, ... }), field:GetContentHeight(), field.editBox.
function ns.UI.TagInput(parent, options)
    local field = CreateFrame("Button", nil, parent)
    AddFrameArt(field)
    local tags = {}            -- every tag button made, reused
    local tagCount = 0
    local contentHeight = ROW_HEIGHT

    local editBox = CreateFrame("EditBox", nil, field)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetHeight(ROW_HEIGHT)
    field.editBox = editBox

    local placeholder = editBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", 1, 0)
    placeholder:SetText(options.placeholder or "")

    local function UpdatePlaceholder()
        local text = editBox:GetText() or ""
        placeholder:SetShown(text == "" and tagCount == 0)
    end

    -- a click anywhere in the field puts the cursor in it
    field:SetScript("OnClick", function()
        editBox:SetFocus()
    end)

    ns.UI.AttachSuggestions(editBox, {
        anchor = field,
        search = options.search,
        onChoose = function(suggestion)
            editBox:SetText("")
            options.onChoose(suggestion)
        end,
    })

    local function Submit()
        local text = editBox:GetText() or ""
        text = text:match("^%s*(.-)%s*$")
        if text == "" then
            return
        end
        if options.onSubmit(text) then
            editBox:SetText("")
        end
    end

    editBox:HookScript("OnTextChanged", UpdatePlaceholder)
    editBox:HookScript("OnEditFocusGained", function(self)
        -- nothing typed yet: what there is to offer right away
        self:ShowSuggestionsFor("")
    end)
    editBox:HookScript("OnEnterPressed", function(self)
        if not self:TakeHighlighted() then
            Submit()
        end
        self:ClearFocus()
    end)
    editBox:HookScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        if not self:IsChoosingSuggestion() then
            Submit()
        end
    end)
    -- Backspace in the empty field takes the last tag out
    editBox:HookScript("OnKeyDown", function(self, key)
        local isEmpty = (self:GetText() or "") == ""
        if key == "BACKSPACE" and isEmpty and tagCount > 0 then
            options.onRemove(tagCount)
        end
    end)

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
        return width - INSET_LEFT - INSET_RIGHT
    end

    -- the tags in rows, the cursor after the last one; returns nothing, the
    -- height is read with GetContentHeight (the form lays the field out by it)
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
        tagCount = #list

        -- the cursor: after the tags, or on a row of its own when too little is left
        if x > 0 and rowWidth - x < MIN_EDIT_WIDTH then
            x = 0
            row = row + 1
        end
        editBox:ClearAllPoints()
        editBox:SetPoint("TOPLEFT", field, "TOPLEFT", INSET_LEFT + x, -INSET_TOP - row * ROW_HEIGHT)
        editBox:SetPoint("RIGHT", field, "RIGHT", -INSET_RIGHT, 0)
        contentHeight = (row + 1) * ROW_HEIGHT
        UpdatePlaceholder()
    end

    -- the height of the field: its rows and the insets
    function field:GetContentHeight()
        return contentHeight + INSET_TOP * 2
    end

    field:SetTags({})
    return field
end
