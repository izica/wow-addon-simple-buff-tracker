-- buff_button.lua -- a buff icon that is also a secure action button: a click
-- casts the spell or uses the item set by SetAction.
--
-- Secure: in combat the client does not let addons move, show, hide or change
-- the action of it (SetAction, Show, Hide, SetPoint -- only out of combat).
-- The picture (icon, timer, count, tint) can change any time.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local ICON_CROP = 0.08            -- icon textures have a frame around the picture: cut it off
local EDGE_SIZE = 1
local EDGE_COLOR = { 0, 0, 0, 1 }
local COUNTDOWN_FONT_SCALE = 0.36 -- the size of the timer numbers, part of the icon size
local MISSING_ALPHA = 0.9
local ACTIVE_ALPHA = 1
local NO_ITEMS_COLOR = { 1, 0.3, 0.3 }
local NORMAL_COLOR = { 1, 1, 1 }
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

-- every attribute SetAction may set: the old ones are cleared first
local ACTION_ATTRIBUTES = { "type", "spell", "item", "macrotext" }

-- options: name -- global frame name (secure buttons work best with one), size,
-- onEnter(button), onLeave(button)
function ns.UI.BuffButton(parent, options)
    local button = CreateFrame("Button", options.name, parent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")

    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(EDGE_COLOR[1], EDGE_COLOR[2], EDGE_COLOR[3], EDGE_COLOR[4])

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", EDGE_SIZE, -EDGE_SIZE)
    icon:SetPoint("BOTTOMRIGHT", -EDGE_SIZE, EDGE_SIZE)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    -- the swipe shows the time left: full at the start, empty at the end
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetReverse(true)
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(false)
    end
    local countdown = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
    local countdownFont = nil
    local countdownFlags = nil
    if countdown then
        countdownFont, _, countdownFlags = countdown:GetFont()
    end

    -- above the swipe: the count of items in the bags
    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local count = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)

    if options.onEnter then
        button:SetScript("OnEnter", options.onEnter)
    end
    if options.onLeave then
        button:SetScript("OnLeave", options.onLeave)
    end

    -- out of combat only
    function button:SetIconSize(size)
        self:SetSize(size, size)
        if countdown and countdownFont then
            countdown:SetFont(countdownFont, math.floor(size * COUNTDOWN_FONT_SCALE), countdownFlags or "OUTLINE")
        end
    end
    button:SetIconSize(options.size)

    -- attributes -- from ns.Models.Buff.Action, nil -- a click does nothing; out of combat only
    function button:SetAction(attributes)
        for _, attributeName in ipairs(ACTION_ATTRIBUTES) do
            self:SetAttribute(attributeName, nil)
        end
        if not attributes then
            return
        end
        for attributeName, value in pairs(attributes) do
            self:SetAttribute(attributeName, value)
        end
    end

    function button:SetIcon(texture)
        icon:SetTexture(texture)
    end

    -- plain numbers; duration 0 or expirationTime 0 -- no timer
    function button:SetTimer(expirationTime, duration)
        local hasTimer = expirationTime > 0 and duration > 0
        if hasTimer then
            cooldown:SetCooldown(expirationTime - duration, duration)
        else
            cooldown:Clear()
        end
    end

    -- a missing buff: grey picture (the texture, not the secure button itself)
    function button:SetMissing(isMissing)
        icon:SetDesaturated(isMissing)
        if isMissing then
            icon:SetAlpha(MISSING_ALPHA)
        else
            icon:SetAlpha(ACTIVE_ALPHA)
        end
    end

    -- itemCount -- nil for a buff without an item: no number
    function button:SetItemCount(itemCount)
        if not itemCount then
            count:SetText("")
            return
        end
        count:SetText(itemCount)
        local color = NORMAL_COLOR
        if itemCount == 0 then
            color = NO_ITEMS_COLOR
        end
        count:SetTextColor(color[1], color[2], color[3])
    end

    return button
end
