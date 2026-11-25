-- suggestions.lua -- a list of suggestions under an input (ui/input.lua): while
-- the player types, rows with a picture and a name drop under the field; a click
-- on a row chooses it. Up / Down move the highlight, Enter takes the highlighted
-- row, Escape closes the list.
--
-- One list frame serves every input (only one has the focus at a time). It
-- stands in the TOOLTIP strata, above our windows, the background and edge as
-- the game's dropdown menus have them on Forever.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local MAX_ROWS = 10
local ROW_HEIGHT = 20
local ICON_SIZE = 18
local PADDING = 5
local MIN_WIDTH = 220
local ICON_CROP = 0.08
local MENU_ATLAS = "common-dropdown-bg"     -- the menu background of WowStyle1DropdownTemplate
local MENU_OUTSET = 10                       -- the atlas has a soft shadow around it
local FALLBACK_BACKGROUND = { 0.05, 0.05, 0.05, 0.95 }
local FALLBACK_EDGE = { 0.4, 0.4, 0.4, 1 }
local HIGHLIGHT_COLOR = { 1, 1, 1, 0.15 }

local list = nil              -- the shared list frame, made on first use
local listOwner = nil         -- the input the list is shown for
local highlightedIndex = nil  -- the row Up / Down moved to
local shownRowCount = 0

local function HideList(owner)
    if not list then
        return
    end
    if owner == nil or listOwner == owner then
        listOwner = nil
        list:Hide()
    end
end

local function SetHighlighted(index)
    highlightedIndex = index
    for rowIndex, row in ipairs(list.rows) do
        row.selection:SetShown(rowIndex == index)
    end
end

local function NewRow(index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PADDING, -PADDING - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -PADDING, -PADDING - (index - 1) * ROW_HEIGHT)

    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:SetColorTexture(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], HIGHLIGHT_COLOR[4])
    row.selection:Hide()
    row:SetScript("OnEnter", function()
        SetHighlighted(index)
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -2, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        local owner = listOwner
        if owner and self.suggestion then
            owner.ChooseSuggestion(self.suggestion)
        end
    end)
    return row
end

local function CreateList()
    list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("TOOLTIP")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)

    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MENU_ATLAS)
    if hasAtlas then
        local background = list:CreateTexture(nil, "BACKGROUND")
        background:SetAtlas(MENU_ATLAS)
        background:SetPoint("TOPLEFT", -MENU_OUTSET, MENU_OUTSET)
        background:SetPoint("BOTTOMRIGHT", MENU_OUTSET, -MENU_OUTSET)
    else
        local edge = list:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(FALLBACK_EDGE[1], FALLBACK_EDGE[2], FALLBACK_EDGE[3], FALLBACK_EDGE[4])
        local background = list:CreateTexture(nil, "BORDER")
        background:SetPoint("TOPLEFT", 1, -1)
        background:SetPoint("BOTTOMRIGHT", -1, 1)
        background:SetColorTexture(FALLBACK_BACKGROUND[1], FALLBACK_BACKGROUND[2],
            FALLBACK_BACKGROUND[3], FALLBACK_BACKGROUND[4])
    end

    list.rows = {}
    for index = 1, MAX_ROWS do
        list.rows[index] = NewRow(index)
    end
    list:Hide()
end

local function ShowList(input, suggestions)
    if #suggestions == 0 then
        HideList(input)
        return
    end
    if not list then
        CreateList()
    end
    listOwner = input
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
    shownRowCount = shownCount
    SetHighlighted(nil)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -6)
    list:SetWidth(math.max(input:GetWidth(), MIN_WIDTH))
    list:SetHeight(shownCount * ROW_HEIGHT + PADDING * 2)
    list:Show()
end

local function IsOpenFor(input)
    return list ~= nil and listOwner == input and list:IsShown()
end

-- options: search(text) -> { { label, icon, ... }, ... },
-- onChoose(suggestion) -- a row was clicked or taken with Enter.
-- Adds to the input: input:IsChoosingSuggestion() -- the mouse is over the list
-- (a focus lost because of a click on a row is not an edit to save).
function ns.UI.AttachSuggestions(input, options)
    function input.ChooseSuggestion(suggestion)
        HideList(input)
        options.onChoose(suggestion)
    end

    function input:IsChoosingSuggestion()
        return IsOpenFor(self) and list:IsMouseOver()
    end

    input:HookScript("OnTextChanged", function(self, isUserInput)
        if not isUserInput then
            return
        end
        local ok, suggestions = pcall(options.search, self:GetText())
        if ok and suggestions then
            ShowList(self, suggestions)
        else
            HideList(self)
        end
    end)

    -- arrows walk the rows (an edit box gets them as OnArrowPressed)
    input:HookScript("OnArrowPressed", function(self, key)
        if not IsOpenFor(self) then
            return
        end
        local highlighted = highlightedIndex or 0
        if key == "DOWN" then
            SetHighlighted(math.min(highlighted + 1, shownRowCount))
        elseif key == "UP" then
            SetHighlighted(math.max(highlighted - 1, 1))
        end
    end)

    -- Enter on a highlighted row takes it instead of the typed text
    function input:TakeHighlighted()
        if not (IsOpenFor(self) and highlightedIndex) then
            return false
        end
        local suggestion = list.rows[highlightedIndex].suggestion
        if not suggestion then
            return false
        end
        self.ChooseSuggestion(suggestion)
        return true
    end

    input:HookScript("OnEscapePressed", function(self)
        HideList(self)
    end)
    input:HookScript("OnEditFocusLost", function(self)
        -- a click on a row takes the focus first: let the click land
        C_Timer.After(0.2, function()
            if not self:HasFocus() then
                HideList(self)
            end
        end)
    end)
    input:HookScript("OnHide", function(self)
        HideList(self)
    end)
end
