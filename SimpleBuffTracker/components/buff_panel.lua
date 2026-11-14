-- buff_panel.lua -- the panel of buff icons: in rows from the top left corner,
-- the buffs of the current mode (all, or only the missing ones).
--
-- The icons are secure buttons (ui/buff_button.lua): which buff sits on which
-- icon, where the icons stand and which are shown changes only out of combat.
-- In combat only the pictures of the icons already shown are updated; a new
-- set of icons waits for the end of combat (Refresh from events/auras.lua).
--
-- Unlocked, a green mover covers the panel and drags it; the place is saved
-- in settings.position.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Buff = ns.Models.Buff
local BuffService = ns.Services.Buff

local BuffPanel = {}
ns.Components.BuffPanel = BuffPanel

local PANEL_NAME = "SimpleBuffTrackerPanel"
local BUTTON_NAME_PREFIX = "SimpleBuffTrackerButton"
local MOVER_COLOR = { 0.2, 1, 0.2, 0.3 }
local MOVER_FRAME_LEVEL_GAP = 20   -- above the icons and their timers
local TOOLTIP_TITLE_COLOR = { 1, 0.82, 0 }
local TOOLTIP_ACTIVE_COLOR = { 0.3, 1, 0.3 }
local TOOLTIP_MISSING_COLOR = { 1, 0.3, 0.3 }
local TOOLTIP_HINT_COLOR = { 0.8, 0.8, 0.8 }

local panel = nil
local mover = nil
local buttons = {}          -- every button made so far, reused
local shownCount = 0        -- buttons[1..shownCount] are shown

local function ShowTooltip(button)
    local state = button.state
    if not state then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
    local title = Buff.TargetLabel(state.buff)
    GameTooltip:AddLine(title, TOOLTIP_TITLE_COLOR[1], TOOLTIP_TITLE_COLOR[2], TOOLTIP_TITLE_COLOR[3])

    if state.isActive then
        local stateText = Text("tooltip.active")
        if state.expirationTime > 0 then
            local secondsLeft = state.expirationTime - GetTime()
            stateText = Text("tooltip.time_left", ns.Utilities.FormatSeconds(secondsLeft))
        end
        GameTooltip:AddLine(stateText, TOOLTIP_ACTIVE_COLOR[1], TOOLTIP_ACTIVE_COLOR[2], TOOLTIP_ACTIVE_COLOR[3])
    else
        GameTooltip:AddLine(Text("tooltip.missing"),
            TOOLTIP_MISSING_COLOR[1], TOOLTIP_MISSING_COLOR[2], TOOLTIP_MISSING_COLOR[3])
    end

    local sourceLabel = Buff.SourceLabel(state.buff)
    local hint = Text("tooltip.no_source")
    if sourceLabel then
        hint = Text("tooltip.click", sourceLabel)
    end
    GameTooltip:AddLine(hint, TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    if state.itemCount then
        GameTooltip:AddLine(Text("tooltip.item_count", state.itemCount),
            TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

local function SavePosition()
    local point, _, _, x, y = panel:GetPoint(1)
    local position = ns.db.settings.position
    position.point = point
    position.x = x
    position.y = y
end

local function PlacePanel()
    local position = ns.db.settings.position
    panel:ClearAllPoints()
    panel:SetPoint(position.point, UIParent, position.point, position.x, position.y)
end

local function CreateMover()
    mover = CreateFrame("Frame", nil, panel)
    mover:SetAllPoints()
    mover:SetFrameLevel(panel:GetFrameLevel() + MOVER_FRAME_LEVEL_GAP)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    local tint = mover:CreateTexture(nil, "OVERLAY")
    tint:SetAllPoints()
    tint:SetColorTexture(MOVER_COLOR[1], MOVER_COLOR[2], MOVER_COLOR[3], MOVER_COLOR[4])
    mover:SetScript("OnDragStart", function()
        if not InCombatLockdown() then
            panel:StartMoving()
        end
    end)
    mover:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        SavePosition()
    end)
    mover:Hide()
end

function BuffPanel.Create()
    panel = CreateFrame("Frame", PANEL_NAME, UIParent)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:SetSize(ns.Config.EMPTY_PANEL_SIZE, ns.Config.EMPTY_PANEL_SIZE)
    PlacePanel()
    CreateMover()
end

local function GetButton(index)
    local button = buttons[index]
    if not button then
        button = ns.UI.BuffButton(panel, {
            name = BUTTON_NAME_PREFIX .. index,
            size = ns.db.settings.iconSize,
            onEnter = ShowTooltip,
            onLeave = HideTooltip,
        })
        buttons[index] = button
    end
    return button
end

local function Paint(button, state)
    button.state = state
    button:SetIcon(state.icon)
    button:SetMissing(not state.isActive)
    if state.isActive then
        button:SetTimer(state.expirationTime, state.duration)
    else
        button:SetTimer(0, 0)
    end
    button:SetItemCount(state.itemCount)
end

-- In combat: the buffs on the icons already shown get new pictures; a new set
-- of icons waits for the end of combat.
local function PaintInCombat(states)
    local stateByBuff = {}
    for _, state in ipairs(states) do
        stateByBuff[state.buff] = state
    end
    for i = 1, shownCount do
        local state = stateByBuff[buttons[i].state.buff]
        if state then
            Paint(buttons[i], state)
        end
    end
end

local function Layout(states)
    local settings = ns.db.settings
    local size = settings.iconSize
    local spacing = settings.iconSpacing
    local perRow = settings.iconsPerRow

    for index, state in ipairs(states) do
        local button = GetButton(index)
        local column = (index - 1) % perRow
        local row = math.floor((index - 1) / perRow)
        button:SetIconSize(size)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", column * (size + spacing), -row * (size + spacing))
        button:SetAction(state.action)
        Paint(button, state)
        button:Show()
    end
    for index = #states + 1, #buttons do
        buttons[index].state = nil
        buttons[index]:Hide()
    end
    shownCount = #states

    local columns = math.min(shownCount, perRow)
    local rows = math.ceil(shownCount / perRow)
    local width = math.max(ns.Config.EMPTY_PANEL_SIZE, columns * (size + spacing) - spacing)
    local height = math.max(ns.Config.EMPTY_PANEL_SIZE, rows * (size + spacing) - spacing)
    panel:SetSize(width, height)
    mover:SetShown(not settings.locked)
end

function BuffPanel.Refresh()
    if not panel then
        return
    end
    local states = BuffService.VisibleStates()
    if InCombatLockdown() then
        PaintInCombat(states)
        return
    end
    Layout(states)
end
