-- buff_list.lua -- the left side of the Buffs tab: the tracked buffs as rows
-- with a picture and a name, the chosen one highlighted, "Add buff" under them.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Buff = ns.Models.Buff
local BuffService = ns.Services.Buff

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

-- options: onSelect(index), onAdd(); returns the list frame, list:Refresh(selectedIndex)
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
            row.selection:SetShown(index == selectedIndex)
            row:Show()
        end
        for index = #buffs + 1, #rows do
            rows[index]:Hide()
        end
        area:SetContentHeight(#buffs * ROW_HEIGHT, true)
    end

    return frame
end
