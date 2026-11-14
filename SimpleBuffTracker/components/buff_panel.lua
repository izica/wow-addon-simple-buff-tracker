-- buff_panel.lua -- the panel of buff icons: in rows from the top left corner,
-- the buffs of the current mode (all, or only the missing ones).
--
-- The icons are secure buttons (ui/buff_button.lua): which buff sits on which
-- icon, where the icons stand and which are shown changes only out of combat.
-- In combat only the pictures of the icons already shown are updated; a new
-- set of icons waits for the end of combat (Refresh from events/auras.lua).
--
-- Unlocked, a green mover covers the panel and drags it, a right click on it
-- locks the panel; the place is saved in settings.position. Locked, the same mover (without the green) comes up
-- while Shift is held with the mouse over the panel: Shift + drag moves it,
-- and a Shift-click does not reach the icons. Out of combat only.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Buff = ns.Models.Buff
local BuffService = ns.Services.Buff
local GROW_DIRECTION = ns.Constants.GROW_DIRECTION
local GROW_CORNER = ns.Constants.GROW_CORNER

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
local moverTint = nil
local isDragging = false
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
        -- "Click to cast X" / "Click to use X", as the game's own tooltips say it
        hint = Text("tooltip.click_" .. state.buff.source.kind, sourceLabel)
    end
    GameTooltip:AddLine(hint, TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    if state.itemCount then
        GameTooltip:AddLine(Text("tooltip.item_count", state.itemCount),
            TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    end
    GameTooltip:AddLine(Text("tooltip.shift_drag"), TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- The panel is held by the corner its icons grow from (GROW_CORNER): more icons
-- make it longer away from that corner, the corner stays where it was put.
-- settings.position = { point = the corner, x, y -- from the bottom left of the
-- screen, isCorner = true }; an older position (point = "CENTER", relative to
-- the same point of the screen) is moved to the corner on the next layout.
local function PinToCorner()
    local corner = GROW_CORNER[ns.db.settings.growDirection] or GROW_CORNER.right
    local left = panel:GetLeft()
    local right = panel:GetRight()
    local top = panel:GetTop()
    local bottom = panel:GetBottom()
    if not (left and right and top and bottom) then
        return
    end
    local x = left
    if corner:find("RIGHT") then
        x = right
    end
    local y = top
    if corner:find("BOTTOM") then
        y = bottom
    end
    panel:ClearAllPoints()
    panel:SetPoint(corner, UIParent, "BOTTOMLEFT", x, y)
    ns.db.settings.position = { point = corner, x = x, y = y, isCorner = true }
end

local function PlacePanel()
    local position = ns.db.settings.position
    local relativePoint = position.point
    if position.isCorner then
        relativePoint = "BOTTOMLEFT"
    end
    panel:ClearAllPoints()
    panel:SetPoint(position.point, UIParent, relativePoint, position.x, position.y)
end

local function SavePosition()
    PinToCorner()
end

-- Where the icon number index stands: the anchor point on the panel and the
-- offset from it. perLine -- icons in a row (growing right or left) or in a
-- column (growing down or up); a full line starts the next one.
local function IconPlace(index, perLine, step, direction)
    local along = (index - 1) % perLine
    local across = math.floor((index - 1) / perLine)
    if direction == GROW_DIRECTION.LEFT then
        return "TOPRIGHT", -along * step, -across * step
    end
    if direction == GROW_DIRECTION.DOWN then
        return "TOPLEFT", across * step, -along * step
    end
    if direction == GROW_DIRECTION.UP then
        return "BOTTOMLEFT", across * step, along * step
    end
    return "TOPLEFT", along * step, -across * step
end

-- The mover is up while unlocked, while dragging, or while Shift is held with
-- the mouse over the panel (not in combat: the panel can not move then).
function BuffPanel.UpdateMover()
    if not mover then
        return
    end
    local isLocked = ns.db.settings.locked
    local isShiftDrag = not InCombatLockdown() and IsShiftKeyDown() and panel:IsMouseOver()
    mover:SetShown(not isLocked or isDragging or isShiftDrag)
    moverTint:SetShown(not isLocked)
end

-- combat is about to start: a drag still going is ended while the panel can move
function BuffPanel.StopDragging()
    if isDragging then
        isDragging = false
        panel:StopMovingOrSizing()
        SavePosition()
    end
    BuffPanel.UpdateMover()
end

local function ShowButtonTooltip(button)
    ShowTooltip(button)
    BuffPanel.UpdateMover()
end

local function CreateMover()
    mover = CreateFrame("Frame", nil, panel)
    mover:SetAllPoints()
    mover:SetFrameLevel(panel:GetFrameLevel() + MOVER_FRAME_LEVEL_GAP)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    moverTint = mover:CreateTexture(nil, "OVERLAY")
    moverTint:SetAllPoints()
    moverTint:SetColorTexture(MOVER_COLOR[1], MOVER_COLOR[2], MOVER_COLOR[3], MOVER_COLOR[4])
    mover:SetScript("OnDragStart", function()
        if not InCombatLockdown() then
            isDragging = true
            panel:StartMoving()
        end
    end)
    mover:SetScript("OnDragStop", function()
        if not isDragging then
            return
        end
        isDragging = false
        panel:StopMovingOrSizing()
        SavePosition()
        BuffPanel.UpdateMover()
    end)
    -- unlocked: a right click locks the panel (the /sbt lock command)
    mover:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" and not ns.db.settings.locked then
            ns.Commands.Run("lock")
        end
    end)
    mover:SetScript("OnEnter", function(self)
        if ns.db.settings.locked then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(Text("tooltip.mover_drag"), TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
        GameTooltip:AddLine(Text("tooltip.mover_lock"), TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function()
        HideTooltip()
        BuffPanel.UpdateMover()
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
            template = ns.db.settings.iconTemplate,
            onEnter = ShowButtonTooltip,
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
    local perLine = settings.iconsPerRow
    local step = size + spacing
    local direction = settings.growDirection

    -- another direction (or an older position): hold the panel by its new corner first
    if settings.position.point ~= GROW_CORNER[direction] then
        PinToCorner()
    end

    for index, state in ipairs(states) do
        local button = GetButton(index)
        local point, x, y = IconPlace(index, perLine, step, direction)
        button:SetIconSize(size)
        if button.template ~= settings.iconTemplate then
            button:SetTemplate(settings.iconTemplate)
        end
        button:ClearAllPoints()
        button:SetPoint(point, panel, point, x, y)
        button:SetAction(state.action)
        Paint(button, state)
        button:Show()
    end
    for index = #states + 1, #buttons do
        buttons[index].state = nil
        buttons[index]:Hide()
    end
    shownCount = #states

    -- along the growth: up to perLine icons; across it: the lines
    local alongCount = math.min(shownCount, perLine)
    local acrossCount = math.ceil(shownCount / perLine)
    local isVertical = direction == GROW_DIRECTION.DOWN or direction == GROW_DIRECTION.UP
    local columns = alongCount
    local rows = acrossCount
    if isVertical then
        columns = acrossCount
        rows = alongCount
    end
    local width = math.max(ns.Config.EMPTY_PANEL_SIZE, columns * step - spacing)
    local height = math.max(ns.Config.EMPTY_PANEL_SIZE, rows * step - spacing)
    panel:SetSize(width, height)
    BuffPanel.UpdateMover()
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
