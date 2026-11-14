-- ace_suggest_edit_box.lua -- an AceGUI edit box with suggestions: while the
-- player types, a list of pictures with names drops under the field; a click
-- on a row puts its text into the field and saves it, as Enter would.
--
-- Built on AceGUI's own "EditBox" (the same field, button and drag and drop),
-- registered as its own widget type for AceConfig's dialogControl. Where the
-- suggestions come from is not known here: the option's arg is a function
-- search(text) -> { { label, icon, text }, ... } (AceConfigDialog hands it to
-- SetCustomData). One list frame serves every such field.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local AceGUI = LibStub("AceGUI-3.0")

local TYPE = "SimpleBuffTrackerSuggestEditBox"
local VERSION = 1
ns.UI.SUGGEST_EDIT_BOX = TYPE

local MAX_ROWS = 10
local ROW_HEIGHT = 20
local ICON_SIZE = 18
local PADDING = 4
local BACKGROUND_COLOR = { 0.05, 0.05, 0.05, 0.95 }
local EDGE_COLOR = { 0.4, 0.4, 0.4, 1 }
local HIGHLIGHT_COLOR = { 1, 1, 1, 0.15 }
local HIDE_DELAY_SECONDS = 0.2   -- a click on a row takes the focus first: hide after it lands

local list = nil   -- the shared list frame, made on first use

local function HideList(owner)
    if list and (owner == nil or list.owner == owner) then
        list.owner = nil
        list:Hide()
    end
end

local function NewRow(index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PADDING, -PADDING - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -PADDING, -PADDING - (index - 1) * ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], HIGHLIGHT_COLOR[4])

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 2, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -2, 0)
    row.label:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        local owner = list.owner
        if owner and self.suggestion then
            owner:Choose(self.suggestion)
        end
    end)
    return row
end

local function CreateList()
    list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("TOOLTIP")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)

    local edge = list:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(EDGE_COLOR[1], EDGE_COLOR[2], EDGE_COLOR[3], EDGE_COLOR[4])
    local background = list:CreateTexture(nil, "BORDER")
    background:SetPoint("TOPLEFT", 1, -1)
    background:SetPoint("BOTTOMRIGHT", -1, 1)
    background:SetColorTexture(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3], BACKGROUND_COLOR[4])

    list.rows = {}
    for index = 1, MAX_ROWS do
        list.rows[index] = NewRow(index)
    end
    list:Hide()
end

local function ShowSuggestions(widget)
    local suggestions = {}
    if widget.search then
        local ok, found = pcall(widget.search, widget.editbox:GetText())
        if ok and found then
            suggestions = found
        end
    end
    if #suggestions == 0 then
        HideList(widget)
        return
    end

    if not list then
        CreateList()
    end
    list.owner = widget
    local shownCount = math.min(#suggestions, MAX_ROWS)
    for index, row in ipairs(list.rows) do
        local suggestion = suggestions[index]
        row.suggestion = suggestion
        if suggestion and index <= shownCount then
            row.icon:SetTexture(suggestion.icon)
            row.label:SetText(suggestion.label)
            row:Show()
        else
            row:Hide()
        end
    end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", widget.editbox, "BOTTOMLEFT", -6, -2)
    list:SetWidth(math.max(widget.editbox:GetWidth() + 6, 200))
    list:SetHeight(shownCount * ROW_HEIGHT + PADDING * 2)
    list:Show()
end

local function Constructor()
    local widget = AceGUI.WidgetRegistry["EditBox"]()
    widget.type = TYPE

    local editbox = widget.editbox
    editbox:HookScript("OnTextChanged", function(_, isUserInput)
        if isUserInput then
            ShowSuggestions(widget)
        end
    end)
    editbox:HookScript("OnEditFocusLost", function()
        C_Timer.After(HIDE_DELAY_SECONDS, function()
            if not editbox:HasFocus() then
                HideList(widget)
            end
        end)
    end)
    editbox:HookScript("OnHide", function()
        HideList(widget)
    end)
    editbox:HookScript("OnEscapePressed", function()
        HideList(widget)
    end)

    -- AceConfigDialog passes the option's arg here: the search function
    function widget:SetCustomData(search)
        self.search = search
    end

    -- a row was clicked: as if typed and confirmed with Enter
    function widget:Choose(suggestion)
        HideList(self)
        self:SetText(suggestion.text)
        self:Fire("OnEnterPressed", suggestion.text)
        AceGUI:ClearFocus()
    end

    local baseRelease = widget.OnRelease
    function widget:OnRelease()
        HideList(self)
        self.search = nil
        baseRelease(self)
    end

    return widget
end

AceGUI:RegisterWidgetType(TYPE, Constructor, VERSION)
