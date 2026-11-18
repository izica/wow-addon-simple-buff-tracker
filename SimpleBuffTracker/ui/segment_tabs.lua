-- segment_tabs.lua -- tabs inside a panel, in a row at its top: text buttons
-- over a thin line, the chosen one white and underlined in gold, the others in
-- the gold of the game's labels, lit on hover. For pages of one thing (the
-- buff and its conditions); the tabs of the window itself hang under it
-- (ui/tab_bar.lua).

local ADDON, ns = ...
ns.UI = ns.UI or {}

local HEIGHT = 24
local TEXT_PADDING = 10        -- left and right of the text, inside the tab
local TAB_GAP = 4
local MIN_TAB_WIDTH = 60
local UNDERLINE_HEIGHT = 2
local UNDERLINE_COLOR = { 1, 0.82, 0, 1 }
local LINE_COLOR = { 1, 1, 1, 0.15 }
local HIGHLIGHT_TEXTURE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

ns.UI.SEGMENT_TABS_HEIGHT = HEIGHT

-- options: tabs = { { id, text } }, onSelect(id) -- a tab clicked.
-- tabs:Select(id), tabs:SetTabText(id, text); place it with SetPoint (TOPLEFT
-- and TOPRIGHT: the line goes across).
function ns.UI.SegmentTabs(parent, options)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(HEIGHT)
    local buttons = {}   -- [id] = button, in the order of options.tabs
    local selectedId = nil

    local line = frame:CreateTexture(nil, "BACKGROUND")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetColorTexture(LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], LINE_COLOR[4])

    local function Fit(button)
        local width = (button.label:GetStringWidth() or 0) + 2 * TEXT_PADDING
        button:SetWidth(math.max(MIN_TAB_WIDTH, width))
    end

    local function Paint()
        for id, button in pairs(buttons) do
            local isSelected = id == selectedId
            if isSelected then
                button.label:SetFontObject("GameFontHighlight")
            else
                button.label:SetFontObject("GameFontNormal")
            end
            button.underline:SetShown(isSelected)
        end
    end

    local previous = nil
    for _, tab in ipairs(options.tabs) do
        local button = CreateFrame("Button", nil, frame)
        button:SetHeight(HEIGHT)
        button:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.label:SetPoint("CENTER", 0, 1)
        button.label:SetText(tab.text)
        button.text = tab.text   -- what the tab says (the tests click tabs by it)

        button.underline = button:CreateTexture(nil, "ARTWORK")
        button.underline:SetHeight(UNDERLINE_HEIGHT)
        button.underline:SetPoint("BOTTOMLEFT")
        button.underline:SetPoint("BOTTOMRIGHT")
        button.underline:SetColorTexture(UNDERLINE_COLOR[1], UNDERLINE_COLOR[2], UNDERLINE_COLOR[3],
            UNDERLINE_COLOR[4])

        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", TAB_GAP, 0)
        else
            button:SetPoint("LEFT")
        end
        local id = tab.id
        button:SetScript("OnClick", function()
            options.onSelect(id)
        end)
        Fit(button)
        buttons[id] = button
        previous = button
    end

    function frame:Select(id)
        selectedId = id
        Paint()
    end

    function frame:SetTabText(id, text)
        local button = buttons[id]
        button.label:SetText(text)
        button.text = text
        Fit(button)
    end

    return frame
end
