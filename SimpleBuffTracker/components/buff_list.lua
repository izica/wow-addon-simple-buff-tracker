-- buff_list.lua -- the left side of the Buffs tab: the tracked buffs as rows
-- with a picture and a name, the chosen one highlighted, "Add buff" under them.
-- A row dragged with the mouse goes to another place (the order of the panel):
-- a gold line shows where it will land. A buff not on the panel right now (not
-- set up yet, or hidden by its show conditions: not in a raid, no item...) is
-- grey, its tooltip says why.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Buff = ns.Models.Buff
local BuffService = ns.Services.Buff
local BuffConditions = ns.Dataflows.BuffConditions

local BuffList = {}
ns.Components.BuffList = BuffList

local ROW_HEIGHT = 26
local ICON_SIZE = 20
local ICON_CROP = 0.08
local PADDING = 6
local ADD_BUTTON_HEIGHT = 24
local NOTE_GAP = 6
local NOTE_ROOM = 44             -- the list ends above the note (up to three lines)
local NOTE_COLOR = { 0.6, 0.6, 0.6 }
local SELECTED_COLOR = { 1, 0.82, 0, 0.18 }
local HIGHLIGHT_TEXTURE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local INSERT_LINE_HEIGHT = 2
local INSERT_LINE_COLOR = { 1, 0.82, 0, 1 }
local DRAGGED_ALPHA = 0.5

-- options: onSelect(index), onAdd(), onMove(fromIndex, toIndex) -- a row was
-- dragged to another place; returns the list frame, list:Refresh(selectedIndex)
function BuffList.Create(parent, options)
    local frame = ns.UI.InsetPanel(parent, {})

    local addButton = ns.UI.Button(frame, {
        text = Text("settings.add"),
        height = ADD_BUTTON_HEIGHT,
        onClick = options.onAdd,
    })
    addButton:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    addButton:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    -- the other way to add: a shift-click on a buff of yours
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("BOTTOMLEFT", addButton, "TOPLEFT", 2, NOTE_GAP)
    note:SetPoint("BOTTOMRIGHT", addButton, "TOPRIGHT", -2, NOTE_GAP)
    note:SetJustifyH("LEFT")
    note:SetTextColor(NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3])
    note:SetText(Text("settings.add_note"))

    local area = ns.UI.ScrollArea(frame)
    area:SetPoint("TOPLEFT", PADDING, -PADDING)
    area:SetPoint("BOTTOMRIGHT", addButton, "TOPRIGHT", -ns.UI.SCROLL_AREA_BAR_SPACE, NOTE_ROOM)

    local rows = {}
    local rowCount = 0       -- rows[1..rowCount] show buffs
    local dragFrom = nil     -- the place of the row being dragged

    -- where a dragged row goes in: the line above or under the row it will take
    local insertLine = area.content:CreateTexture(nil, "OVERLAY")
    insertLine:SetHeight(INSERT_LINE_HEIGHT)
    insertLine:SetColorTexture(INSERT_LINE_COLOR[1], INSERT_LINE_COLOR[2], INSERT_LINE_COLOR[3], INSERT_LINE_COLOR[4])
    insertLine:Hide()

    -- the place under the mouse: the row it is over; above the rows -- the first,
    -- under them -- the last
    local function DropIndex()
        for index = 1, rowCount do
            if rows[index]:IsMouseOver() then
                return index
            end
        end
        local _, cursorY = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        local firstTop = rows[1] and rows[1]:GetTop()
        local isAbove = firstTop ~= nil and cursorY / scale > firstTop
        if isAbove then
            return 1
        end
        return rowCount
    end

    local function ShowInsertLine()
        local target = DropIndex()
        if not dragFrom or target == dragFrom then
            insertLine:Hide()
            return
        end
        local row = rows[target]
        local edge = "BOTTOM"
        if target < dragFrom then
            edge = "TOP"
        end
        insertLine:ClearAllPoints()
        insertLine:SetPoint("LEFT", row, edge .. "LEFT")
        insertLine:SetPoint("RIGHT", row, edge .. "RIGHT")
        insertLine:Show()
    end

    local function StartDrag(row)
        dragFrom = row.index
        row:SetAlpha(DRAGGED_ALPHA)
        frame:SetScript("OnUpdate", ShowInsertLine)
    end

    local function StopDrag(row)
        frame:SetScript("OnUpdate", nil)
        insertLine:Hide()
        row:SetAlpha(1)
        local from = dragFrom
        dragFrom = nil
        if not from then
            return
        end
        local target = DropIndex()
        if target ~= from then
            options.onMove(from, target)
        end
    end

    local function GetRow(index)
        local row = rows[index]
        if row then
            return row
        end
        row = CreateFrame("Button", nil, area.content)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", area.content, "RIGHT")
        row:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")

        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:SetColorTexture(SELECTED_COLOR[1], SELECTED_COLOR[2], SELECTED_COLOR[3], SELECTED_COLOR[4])

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", -4, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        row:SetScript("OnClick", function(self)
            options.onSelect(self.index)
        end)
        row:SetScript("OnEnter", function(self)
            if not self.isHidden then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label:GetText() or "")
            GameTooltip:AddLine(self.hiddenText, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", StartDrag)
        row:SetScript("OnDragStop", StopDrag)
        rows[index] = row
        return row
    end

    function frame:Refresh(selectedIndex)
        local buffs = BuffService.List()
        for index, buff in ipairs(buffs) do
            local row = GetRow(index)
            row.index = index
            row.icon:SetTexture(BuffService.Icon(buff))
            row.label:SetText(Buff.TargetLabel(buff))
            -- not on the panel right now (not set up, or its show conditions):
            -- grey, the tooltip says why
            local hiddenText = nil
            if not Buff.HasTarget(buff) then
                hiddenText = Text("settings.hidden_not_set_up")
            else
                local reasonKey, reasonArgument = BuffConditions.Reason(buff)
                if reasonKey then
                    hiddenText = Text("settings.status_hidden", Text(reasonKey, reasonArgument))
                end
            end
            local isHidden = hiddenText ~= nil
            row.isHidden = isHidden
            row.hiddenText = hiddenText
            row.icon:SetDesaturated(isHidden)
            if isHidden then
                row.label:SetFontObject("GameFontDisable")
            else
                row.label:SetFontObject("GameFontHighlight")
            end
            row.selection:SetShown(index == selectedIndex)
            row:Show()
        end
        for index = #buffs + 1, #rows do
            rows[index]:Hide()
        end
        rowCount = #buffs
        area:SetContentHeight(#buffs * ROW_HEIGHT, true)
    end

    return frame
end
