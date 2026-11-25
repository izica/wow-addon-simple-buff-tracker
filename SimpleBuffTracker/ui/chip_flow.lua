-- chip_flow.lua -- small buttons ("chips") in rows that wrap: the zones picked
-- for a buff, each with a cross to take it out, and an "add" chip in front.
-- Only the look and the clicks: what a chip means is the caller's.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local CHIP_HEIGHT = 20
local CHIP_GAP = 4
local TEXT_PADDING = 8
local MIN_CHIP_WIDTH = 40
local FALLBACK_WIDTH = 300    -- the width before the client has laid the frame out
local BACKGROUND_COLOR = { 1, 1, 1, 0.08 }
local ADD_BACKGROUND_COLOR = { 0.3, 1, 0.3, 0.12 }
local HIGHLIGHT_TEXTURE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local TOOLTIP_TEXT_COLOR = { 1, 1, 1 }

-- options: width() -- the room for a row (optional).
-- flow:SetChips({ { text, tooltip, isAdd, onClick } }), flow:GetContentHeight().
function ns.UI.ChipFlow(parent, options)
    local flow = CreateFrame("Frame", nil, parent)
    local chips = {}       -- every chip button made, reused
    local contentHeight = CHIP_HEIGHT

    local function GetChip(index)
        local chip = chips[index]
        if chip then
            return chip
        end
        chip = CreateFrame("Button", nil, flow)
        chip:SetHeight(CHIP_HEIGHT)
        chip.background = chip:CreateTexture(nil, "BACKGROUND")
        chip.background:SetAllPoints()
        chip:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")
        chip.label = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chip.label:SetPoint("CENTER")
        chip:SetScript("OnClick", function(self)
            if self.onClick then
                self.onClick()
            end
        end)
        chip:SetScript("OnEnter", function(self)
            if not self.tooltip then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tooltip, TOOLTIP_TEXT_COLOR[1], TOOLTIP_TEXT_COLOR[2], TOOLTIP_TEXT_COLOR[3], true)
            GameTooltip:Show()
        end)
        chip:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        chips[index] = chip
        return chip
    end

    local function RowWidth()
        local width = options and options.width and options.width() or flow:GetWidth()
        if not width or width <= 0 then
            return FALLBACK_WIDTH
        end
        return width
    end

    -- lay the chips out left to right, a new row when one does not fit
    function flow:SetChips(list)
        local rowWidth = RowWidth()
        local x = 0
        local y = 0
        for index, entry in ipairs(list) do
            local chip = GetChip(index)
            chip.label:SetText(entry.text)
            chip.text = entry.text   -- what the chip says (the tests click chips by it)
            chip.tooltip = entry.tooltip
            chip.onClick = entry.onClick
            local color = BACKGROUND_COLOR
            if entry.isAdd then
                color = ADD_BACKGROUND_COLOR
            end
            chip.background:SetColorTexture(color[1], color[2], color[3], color[4])

            local width = math.max(MIN_CHIP_WIDTH, (chip.label:GetStringWidth() or 0) + 2 * TEXT_PADDING)
            chip:SetWidth(width)
            local isRowFull = x > 0 and x + width > rowWidth
            if isRowFull then
                x = 0
                y = y + CHIP_HEIGHT + CHIP_GAP
            end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", flow, "TOPLEFT", x, -y)
            chip:Show()
            x = x + width + CHIP_GAP
        end
        for index = #list + 1, #chips do
            chips[index]:Hide()
        end
        contentHeight = y + CHIP_HEIGHT
        if #list == 0 then
            contentHeight = 0
        end
    end

    function flow:GetContentHeight()
        return contentHeight
    end

    return flow
end
