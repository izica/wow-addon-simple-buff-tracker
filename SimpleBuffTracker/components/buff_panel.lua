-- buff_panel.lua -- the panel of buff icons: in lines the chosen way (settings.growDirection),
-- the buffs of the current mode (all, or only the missing ones).
--
-- The icons are secure buttons (ui/buff_button.lua): which buff sits on which
-- icon, where the icons stand and which are shown changes only out of combat.
-- In combat only the pictures of the icons already shown are updated; a new
-- set of icons waits for the end of combat (Refresh from events/auras.lua).
--
-- Unlocked, a green mover covers the panel and drags it, a right click on it
-- locks the panel; the place is saved in settings.position. The mover shows the
-- anchor: an open padlock on the middle of the edge the icons grow from and an
-- arrow the way they grow -- the panel stays held by that point.
--
-- The place is the addon's only: the client must not keep its own. A movable
-- frame dragged with StartMoving is "user placed", and the client restores it
-- after login by a point it picks itself (by the third of the screen: left,
-- center or right) -- the panel then grew left or both ways. So the client is
-- told not to save it, and every layout puts the panel back on its anchor. Locked, the same mover (without the green) comes up
-- while Shift is held with the mouse over the panel: Shift + drag moves it,
-- and a Shift-click does not reach the icons. Out of combat only.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Buff = ns.Models.Buff
local BuffService = ns.Services.Buff
local GROW_DIRECTION = ns.Constants.GROW_DIRECTION
local GROW_ANCHOR = ns.Constants.GROW_ANCHOR

local BuffPanel = {}
ns.Components.BuffPanel = BuffPanel

local PANEL_NAME = "SimpleBuffTrackerPanel"
local BUTTON_NAME_PREFIX = "SimpleBuffTrackerButton"
local MOVER_COLOR = { 0.2, 1, 0.2, 0.3 }
local MOVER_FRAME_LEVEL_GAP = 20   -- above the icons and their timers
local ANCHOR_COLOR = { 1, 0.82, 0 }   -- the arrow, gold like the padlock
-- the anchor: an open padlock drawn for the addon (scripts/make_icon.py)
local ANCHOR_TEXTURE = "Interface\\AddOns\\SimpleBuffTracker\\media\\lock_open"
local ANCHOR_SIZE = 20
local ARROW_TEXTURE = "Interface\\ChatFrame\\ChatFrameExpandArrow"   -- points right
local ARROW_SIZE = 16
local ARROW_GAP = 4                -- between the anchor mark and the arrow
-- the arrow's turn for each direction, radians (counterclockwise)
local ARROW_ROTATION = {
    right = 0,
    up = math.pi / 2,
    left = math.pi,
    down = -math.pi / 2,
}
-- the way the icons grow as x, y signs (the anchor stands the other way, outside the panel)
local ARROW_SHIFT = {
    right = { 1, 0 },
    left = { -1, 0 },
    down = { 0, -1 },
    up = { 0, 1 },
}
local TOOLTIP_TITLE_COLOR = { 1, 0.82, 0 }
local TOOLTIP_ACTIVE_COLOR = { 0.3, 1, 0.3 }
local TOOLTIP_MISSING_COLOR = { 1, 0.3, 0.3 }
local TOOLTIP_HINT_COLOR = { 0.8, 0.8, 0.8 }

local panel = nil
local mover = nil
local moverTint = nil
local anchorMark = nil      -- the open padlock on the point the panel is held by
local anchorArrow = nil     -- the arrow the way they grow
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

    local isEquippedItem = state.buff.target.isEquipped == true
    if state.isActive then
        local stateText = Text("tooltip.active")
        if isEquippedItem then
            stateText = Text("tooltip.equipped")
        end
        if state.expirationTime > 0 then
            local secondsLeft = state.expirationTime - GetTime()
            stateText = Text("tooltip.time_left", ns.Utilities.FormatSeconds(secondsLeft))
        end
        GameTooltip:AddLine(stateText, TOOLTIP_ACTIVE_COLOR[1], TOOLTIP_ACTIVE_COLOR[2], TOOLTIP_ACTIVE_COLOR[3])
    elseif isEquippedItem then
        GameTooltip:AddLine(Text("tooltip.not_equipped"),
            TOOLTIP_MISSING_COLOR[1], TOOLTIP_MISSING_COLOR[2], TOOLTIP_MISSING_COLOR[3])
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
    GameTooltip:AddLine(Text("tooltip.right_click_settings"),
        TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    GameTooltip:AddLine(Text("tooltip.shift_drag"), TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- The panel is held by the middle of the edge its icons grow from (GROW_ANCHOR):
-- growing right -- the middle of its left edge. More icons make it longer away
-- from that point, more lines spread to both sides of it; the point stays where
-- it was put. settings.position = { point = that point, x, y -- from the bottom
-- left of the screen, isCorner = true (the name of older versions: "relative to
-- the screen's bottom left") }; an older position (a corner, or "CENTER"
-- relative to the screen's center) is moved to the anchor on the next layout.
local function PinToAnchor()
    local anchor = GROW_ANCHOR[ns.db.settings.growDirection] or GROW_ANCHOR.right
    local left = panel:GetLeft()
    local right = panel:GetRight()
    local top = panel:GetTop()
    local bottom = panel:GetBottom()
    if not (left and right and top and bottom) then
        return
    end
    local x = (left + right) / 2
    if anchor:find("LEFT") then
        x = left
    elseif anchor:find("RIGHT") then
        x = right
    end
    local y = (top + bottom) / 2
    if anchor:find("TOP") then
        y = top
    elseif anchor:find("BOTTOM") then
        y = bottom
    end
    panel:ClearAllPoints()
    panel:SetPoint(anchor, UIParent, "BOTTOMLEFT", x, y)
    ns.db.settings.position = { point = anchor, x = x, y = y, isCorner = true }
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
    PinToAnchor()
end

-- The anchor outside the panel, off the point it is held by, so it covers no
-- icon: going away from the panel -- the arrow (pointing at the panel, the way the
-- icons grow), then the open padlock. Growing right: padlock, arrow, | icons.
local function PlaceAnchor()
    local direction = ns.db.settings.growDirection
    local anchor = GROW_ANCHOR[direction] or GROW_ANCHOR.right
    local shift = ARROW_SHIFT[direction] or ARROW_SHIFT.right
    local outX = -shift[1]
    local outY = -shift[2]
    local arrowDistance = ARROW_GAP + ARROW_SIZE / 2
    local markDistance = ARROW_GAP + ARROW_SIZE + ARROW_GAP + ANCHOR_SIZE / 2
    anchorArrow:ClearAllPoints()
    anchorArrow:SetPoint("CENTER", mover, anchor, outX * arrowDistance, outY * arrowDistance)
    anchorArrow:SetRotation(ARROW_ROTATION[direction] or 0)
    anchorMark:ClearAllPoints()
    anchorMark:SetPoint("CENTER", mover, anchor, outX * markDistance, outY * markDistance)
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
    PlaceAnchor()
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
        panel:SetUserPlaced(false)   -- the client does not keep its own copy of the place
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
        GameTooltip:AddLine(Text("tooltip.mover_anchor"), TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function()
        HideTooltip()
        BuffPanel.UpdateMover()
    end)

    -- the anchor: an open padlock, over everything on the mover
    anchorMark = mover:CreateTexture(nil, "OVERLAY", nil, 7)
    anchorMark:SetTexture(ANCHOR_TEXTURE)
    anchorMark:SetSize(ANCHOR_SIZE, ANCHOR_SIZE)
    anchorArrow = mover:CreateTexture(nil, "OVERLAY", nil, 7)
    anchorArrow:SetTexture(ARROW_TEXTURE)
    anchorArrow:SetVertexColor(ANCHOR_COLOR[1], ANCHOR_COLOR[2], ANCHOR_COLOR[3])
    anchorArrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    mover:Hide()
end

function BuffPanel.Create()
    panel = CreateFrame("Frame", PANEL_NAME, UIParent)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    -- the client must not restore the panel by a point of its own (see the top of the file)
    if panel.SetDontSavePosition then
        panel:SetDontSavePosition(true)
    end
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
            -- the buff's page in the window
            onRightClick = function(self)
                if self.state then
                    ns.Components.MainWindow.ShowBuff(self.state.buff)
                end
            end,
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
    -- a missing buff, or one about to run out (the warning time), draws the eye
    -- with the effect chosen on the Panel tab -- in both display modes
    local needsAttention = not state.isActive or state.isExpiring
    if needsAttention then
        button:SetGlow(ns.db.settings.missingGlow)
    else
        button:SetGlow(nil)
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

    -- another direction (or an older position): hold the panel by its new anchor first;
    -- otherwise put it back on its anchor -- whatever moved it, the anchor is the place.
    -- Not while it is dragged: the mouse holds it then (the ticker and the aura
    -- events lay out every second -- the panel jumped back under the mouse).
    -- The place is saved when the drag ends.
    if not isDragging then
        if settings.position.point ~= GROW_ANCHOR[direction] then
            PinToAnchor()
        else
            PlacePanel()
        end
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
        buttons[index]:SetGlow(nil)
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
