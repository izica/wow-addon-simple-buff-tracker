-- rounded_rect.lua -- a filled rectangle with rounded corners and a border, made
-- of textures: WoW has no border radius. Each corner is media/corner_round.tga
-- (a white quarter disc, turned by tex coords), between them three plain
-- rectangles. The border is the same shape in the border color under the
-- fill, the fill inset by the border's width (its corners rounded by
-- radius - border, so the border keeps its width around the curve).
--
-- local shape = ns.UI.RoundedRect(frame, radius, border)
-- shape:Paint(fillColor, borderColor) -- colors { r, g, b, a }

local ADDON, ns = ...
ns.UI = ns.UI or {}

local CORNER_TEXTURE = "Interface\\AddOns\\" .. ADDON .. "\\media\\corner_round"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- the art is the top left corner; tex coords turn it for the others
local CORNER_COORDS = {
    TOPLEFT = { 0, 1, 0, 1 },
    TOPRIGHT = { 1, 0, 0, 1 },
    BOTTOMLEFT = { 0, 1, 1, 0 },
    BOTTOMRIGHT = { 1, 0, 1, 0 },
}

-- A piece by its edges: left, top -- from the left / top side (>= 0) or the
-- right / bottom one (< 0); right, bottom -- from the left / top side (> 0) or
-- the right / bottom one (<= 0).
local function AddPiece(frame, pieces, sublevel, file, left, top, right, bottom, corner)
    local texture = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    texture:SetTexture(file or WHITE_TEXTURE)
    if corner then
        local coords = CORNER_COORDS[corner]
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
    texture:SetPoint("TOPLEFT", frame,
        (top >= 0 and "TOP" or "BOTTOM") .. (left >= 0 and "LEFT" or "RIGHT"), left, -top)
    texture:SetPoint("BOTTOMRIGHT", frame,
        (bottom > 0 and "TOP" or "BOTTOM") .. (right > 0 and "LEFT" or "RIGHT"), right, -bottom)
    table.insert(pieces, texture)
end

-- the rectangle inset from the sides, its corners rounded by radius
local function AddRounded(frame, pieces, sublevel, inset, radius)
    if radius <= 0 then
        AddPiece(frame, pieces, sublevel, nil, inset, inset, -inset, -inset)
        return
    end
    local edge = inset + radius
    AddPiece(frame, pieces, sublevel, nil, edge, inset, -edge, -inset)     -- the middle column
    AddPiece(frame, pieces, sublevel, nil, inset, edge, edge, -edge)       -- the left side
    AddPiece(frame, pieces, sublevel, nil, -edge, edge, -inset, -edge)     -- the right side
    AddPiece(frame, pieces, sublevel, CORNER_TEXTURE, inset, inset, edge, edge, "TOPLEFT")
    AddPiece(frame, pieces, sublevel, CORNER_TEXTURE, -edge, inset, -inset, edge, "TOPRIGHT")
    AddPiece(frame, pieces, sublevel, CORNER_TEXTURE, inset, -edge, edge, -inset, "BOTTOMLEFT")
    AddPiece(frame, pieces, sublevel, CORNER_TEXTURE, -edge, -edge, -inset, -inset, "BOTTOMRIGHT")
end

local function PaintPieces(pieces, color)
    for _, texture in ipairs(pieces) do
        texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
end

function ns.UI.RoundedRect(frame, radius, border)
    local shape = { borderPieces = {}, fillPieces = {} }
    if border > 0 then
        AddRounded(frame, shape.borderPieces, 0, 0, radius)
    end
    AddRounded(frame, shape.fillPieces, 1, border, math.max(radius - border, 0))

    function shape:Paint(fillColor, borderColor)
        PaintPieces(self.fillPieces, fillColor)
        if borderColor then
            PaintPieces(self.borderPieces, borderColor)
        end
    end

    return shape
end
