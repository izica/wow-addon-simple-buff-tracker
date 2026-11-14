-- glow.lua -- an effect around an icon that draws the eye, like the glows of
-- WeakAuras (ns.Constants.GLOW_EFFECT):
--   pixel     -- short lines running around the edge ("Pixel Glow");
--   autocast  -- sparkles circling the edge at different speeds ("Autocast Shine");
--   proc      -- the client's own spell alert of the action bars
--                (ActionButtonSpellAlertTemplate, the "proc" flash and loop);
--                without the template -- the pixel lines;
--   pulse     -- a red frame that fades in and out.
-- Drawn by hand with textures moved in OnUpdate (no animation templates): one
-- code for every client. Each effect is made the first time it is shown.
--
-- The glow is a plain frame over the owner (a secure button may be the owner:
-- the glow is not protected, so it is shown and hidden in combat too).

local ADDON, ns = ...
ns.UI = ns.UI or {}

local GLOW_EFFECT = ns.Constants.GLOW_EFFECT

local GLOW_COLOR = { 0.95, 0.95, 0.32 }    -- the yellow of the WeakAuras glows
local PULSE_COLOR = { 1, 0.15, 0.1 }

local PIXEL_LINES = 8
local PIXEL_THICKNESS = 2
local PIXEL_LINE_SHARE = 0.5     -- a line takes this share of the gap between lines
local PIXEL_LAP_SECONDS = 4      -- one lap around the edge

local SPARKLE_TEXTURE = "Interface\\Cooldown\\star4"
-- groups of sparkles: size (share of the icon), seconds per lap; each group runs its own speed
local SPARKLE_GROUPS = {
    { size = 0.34, lap = 8 },
    { size = 0.28, lap = 7 },
    { size = 0.22, lap = 6 },
    { size = 0.17, lap = 5 },
}
local SPARKLES_PER_GROUP = 4

local PROC_TEMPLATE = "ActionButtonSpellAlertTemplate"
local PROC_SCALE = 1.4           -- the client makes the alert this much bigger than the button

local PULSE_THICKNESS = 3
local PULSE_SECONDS = 1.2        -- one fade in and out
local PULSE_MIN_ALPHA = 0.25

-- A point on the edge of a w x h box, distance along it clockwise from the top left
-- corner: x right, y down from the top left.
local function EdgePoint(distance, width, height)
    local perimeter = 2 * (width + height)
    distance = distance % perimeter
    if distance < width then
        return distance, 0
    end
    distance = distance - width
    if distance < height then
        return width, distance
    end
    distance = distance - height
    if distance < width then
        return width - distance, height
    end
    return 0, height - (distance - width)
end

-- The part of one side from..to (distances along that side, clockwise) as a rectangle:
-- left, top (down from the top), width, height. side: 1 top, 2 right, 3 bottom, 4 left.
local function SideRectangle(side, from, to, width, height, thickness)
    if side == 1 then
        return from, 0, to - from, thickness
    end
    if side == 2 then
        return width - thickness, from, thickness, to - from
    end
    if side == 3 then
        return width - to, height - thickness, to - from, thickness
    end
    return 0, height - to, thickness, to - from
end

local function PlaceRectangle(texture, frame, left, top, rectangleWidth, rectangleHeight)
    if rectangleWidth <= 0 or rectangleHeight <= 0 then
        texture:Hide()
        return
    end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
    texture:SetSize(rectangleWidth, rectangleHeight)
    texture:Show()
end

-- A line along the edge from distance start, length long: on one side, or bent
-- over a corner onto the next (two textures).
local function PlaceLine(frame, first, second, start, length, width, height)
    local sides = { width, height, width, height }
    local perimeter = 2 * (width + height)
    start = start % perimeter
    local side = 1
    while side < 4 and start >= sides[side] do   -- side < 4: a rounding error never runs past the last side
        start = start - sides[side]
        side = side + 1
    end
    local onThisSide = math.min(length, sides[side] - start)
    PlaceRectangle(first, frame, SideRectangle(side, start, start + onThisSide, width, height, PIXEL_THICKNESS))
    local rest = length - onThisSide
    if rest > 0 then
        local nextSide = side % 4 + 1
        PlaceRectangle(second, frame, SideRectangle(nextSide, 0, rest, width, height, PIXEL_THICKNESS))
    else
        second:Hide()
    end
end

local function SolidTexture(frame, color, layer)
    local texture = frame:CreateTexture(nil, layer or "OVERLAY")
    texture:SetColorTexture(color[1], color[2], color[3], 1)
    return texture
end

-- Each Make* returns { frame, start(), update(elapsed), stop() }.

local function MakePixel(holder)
    local frame = CreateFrame("Frame", nil, holder)
    frame:SetAllPoints()
    local lines = {}
    for index = 1, PIXEL_LINES do
        lines[index] = { SolidTexture(frame, GLOW_COLOR), SolidTexture(frame, GLOW_COLOR) }
    end
    local clock = 0
    local effect = { frame = frame }
    function effect.start()
        clock = 0
    end
    function effect.update(elapsed)
        clock = clock + elapsed
        local width = frame:GetWidth() or 0
        local height = frame:GetHeight() or 0
        if width <= 0 or height <= 0 then
            return
        end
        local perimeter = 2 * (width + height)
        local gap = perimeter / PIXEL_LINES
        local offset = (clock / PIXEL_LAP_SECONDS % 1) * perimeter
        for index, line in ipairs(lines) do
            PlaceLine(frame, line[1], line[2], offset + (index - 1) * gap, gap * PIXEL_LINE_SHARE, width, height)
        end
    end
    function effect.stop() end
    return effect
end

local function MakeAutocast(holder)
    local frame = CreateFrame("Frame", nil, holder)
    frame:SetAllPoints()
    local sparkles = {}
    for groupIndex, group in ipairs(SPARKLE_GROUPS) do
        for index = 1, SPARKLES_PER_GROUP do
            local texture = frame:CreateTexture(nil, "OVERLAY")
            texture:SetTexture(SPARKLE_TEXTURE)
            texture:SetBlendMode("ADD")
            texture:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3])
            table.insert(sparkles, { texture = texture, group = group, place = (index - 1) / SPARKLES_PER_GROUP })
        end
    end
    local clock = 0
    local effect = { frame = frame }
    function effect.start()
        clock = 0
    end
    function effect.update(elapsed)
        clock = clock + elapsed
        local width = frame:GetWidth() or 0
        local height = frame:GetHeight() or 0
        if width <= 0 or height <= 0 then
            return
        end
        local perimeter = 2 * (width + height)
        for _, sparkle in ipairs(sparkles) do
            local share = (clock / sparkle.group.lap + sparkle.place) % 1
            local x, y = EdgePoint(share * perimeter, width, height)
            local size = math.min(width, height) * sparkle.group.size
            sparkle.texture:ClearAllPoints()
            sparkle.texture:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
            sparkle.texture:SetSize(size, size)
        end
    end
    function effect.stop() end
    return effect
end

local function MakeProc(holder)
    local ok, alert = pcall(CreateFrame, "Frame", nil, holder, PROC_TEMPLATE)
    local isComplete = ok and alert and type(alert.ProcStartAnim) == "table" and type(alert.ProcLoop) == "table"
    if not isComplete then
        if ok and alert then
            alert:Hide()
        end
        return nil
    end
    alert:SetPoint("CENTER")
    local effect = { frame = alert }
    function effect.start()
        local width = holder:GetWidth() or 0
        local height = holder:GetHeight() or 0
        alert:SetSize(width * PROC_SCALE, height * PROC_SCALE)
        -- the flash, then the loop (the template's OnLoad chains them)
        alert.ProcStartAnim:Play()
    end
    function effect.update() end
    function effect.stop()
        alert.ProcStartAnim:Stop()
        alert.ProcLoop:Stop()
    end
    return effect
end

local function MakePulse(holder)
    local frame = CreateFrame("Frame", nil, holder)
    frame:SetAllPoints()
    local edges = {
        { "TOPLEFT", "TOPRIGHT", "height" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
        { "TOPLEFT", "BOTTOMLEFT", "width" },
        { "TOPRIGHT", "BOTTOMRIGHT", "width" },
    }
    for _, edge in ipairs(edges) do
        local texture = SolidTexture(frame, PULSE_COLOR)
        texture:SetPoint(edge[1])
        texture:SetPoint(edge[2])
        if edge[3] == "height" then
            texture:SetHeight(PULSE_THICKNESS)
        else
            texture:SetWidth(PULSE_THICKNESS)
        end
    end
    -- a soft red light over the whole icon, under the frame
    local wash = frame:CreateTexture(nil, "ARTWORK")
    wash:SetAllPoints()
    wash:SetColorTexture(PULSE_COLOR[1], PULSE_COLOR[2], PULSE_COLOR[3], 0.25)
    wash:SetBlendMode("ADD")

    local clock = 0
    local effect = { frame = frame }
    function effect.start()
        clock = 0
    end
    function effect.update(elapsed)
        clock = clock + elapsed
        local wave = (math.sin(clock / PULSE_SECONDS * 2 * math.pi) + 1) / 2
        frame:SetAlpha(PULSE_MIN_ALPHA + (1 - PULSE_MIN_ALPHA) * wave)
    end
    function effect.stop() end
    return effect
end

local MAKERS = {
    [GLOW_EFFECT.PIXEL] = MakePixel,
    [GLOW_EFFECT.AUTOCAST] = MakeAutocast,
    [GLOW_EFFECT.PROC] = MakeProc,
    [GLOW_EFFECT.PULSE] = MakePulse,
}

-- glow:Set(effect) -- show that effect (GLOW_EFFECT), nil or NONE -- none;
-- glow:SetFrameLevel(level) -- above the owner's own layers.
function ns.UI.Glow(owner)
    local holder = CreateFrame("Frame", nil, owner)
    holder:SetAllPoints()
    holder:Hide()

    local effects = {}       -- [effect name] = effect, made on first use
    local current = nil      -- the name shown, or nil

    local function Make(name)
        if effects[name] == nil then
            local made = MAKERS[name] and MAKERS[name](holder)
            -- the client without the spell alert: the pixel lines instead
            if not made and name == GLOW_EFFECT.PROC then
                made = MakePixel(holder)
            end
            effects[name] = made or false
        end
        return effects[name] or nil
    end

    holder:SetScript("OnUpdate", function(_, elapsed)
        local effect = current and effects[current]
        if effect then
            effect.update(elapsed)
        end
    end)

    local glow = {}

    function glow:Set(name)
        if name == GLOW_EFFECT.NONE then
            name = nil
        end
        if name == current then
            return
        end
        if current and effects[current] then
            effects[current].stop()
            effects[current].frame:Hide()
        end
        current = name
        local effect = name and Make(name)
        if not effect then
            current = nil
            holder:Hide()
            return
        end
        holder:Show()
        effect.frame:Show()
        effect.start()
        effect.update(0)
    end

    function glow:SetFrameLevel(level)
        holder:SetFrameLevel(level)
    end

    return glow
end
