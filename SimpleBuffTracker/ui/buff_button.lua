-- buff_button.lua -- a buff icon that is also a secure action button: a click
-- casts the spell or uses the item set by SetAction.
--
-- The look is the action bar's: the client's own ActionButtonTemplate inside,
-- scaled to the icon size -- the same art, icon and cooldown as the buttons of
-- the action bars. Not drawn by hand: on Forever the art comes from the template
-- as it is (the Mainline UpdateButtonArt does not load there), a copy of its
-- pieces looked wrong in the game (SimpleAuras, ui/aura_icon.lua). The template
-- button is only a picture: no action, no mouse; the secure button around it
-- takes the clicks. Without the template -- a picture in a thin dark edge.
--
-- Secure: in combat the client does not let addons move, show, hide or change
-- the action of it (SetAction, Show, Hide, SetPoint -- only out of combat).
-- The picture (icon, timer, count, tint) can change any time.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local ICON_CROP = 0.08            -- icon textures have a frame around the picture: cut it off
local EDGE_SIZE = 1
local EDGE_COLOR = { 0, 0, 0, 1 }
local COUNTDOWN_FONT_SCALE = 0.36 -- the size of the timer numbers, part of the icon size (simple look)
local MISSING_ALPHA = 0.9
local ACTIVE_ALPHA = 1
local NO_ITEMS_COLOR = { 1, 0.3, 0.3 }
local NORMAL_COLOR = { 1, 1, 1 }
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

local ACTION_BUTTON_TEMPLATE = "ActionButtonTemplate"
local ACTION_BUTTON_SIZE = 45     -- the size of the template button
-- above the template's own text overlay (frameLevel 500 in the template)
local ACTION_BUTTON_TEXT_LEVEL_GAP = 10

-- every attribute SetAction may set: the old ones are cleared first
local ACTION_ATTRIBUTES = { "type", "spell", "item", "macrotext" }

-- Each Dress* puts a look on the button and returns { icon, cooldown,
-- textLevel -- the frame level above the look, resize(size) or nil,
-- count -- the font string for the item count or nil, scalesNumbers }.

local function DressActionBar(button, size)
    local ok, look = pcall(CreateFrame, "CheckButton", nil, button, ACTION_BUTTON_TEMPLATE)
    local isComplete = ok and look and look.icon and look.cooldown
    if not isComplete then
        if ok and look then
            look:Hide()
        end
        return nil
    end
    look:SetPoint("CENTER")
    look:EnableMouse(false)   -- the secure button around it takes the clicks
    for _, text in ipairs({ look.HotKey, look.Count, look.Name }) do
        text:SetText("")
    end
    local function Resize(newSize)
        look:SetScale(newSize / ACTION_BUTTON_SIZE)
    end
    Resize(size)

    local textLevel = look:GetFrameLevel() + 1
    if look.TextOverlayContainer then
        textLevel = look.TextOverlayContainer:GetFrameLevel() + ACTION_BUTTON_TEXT_LEVEL_GAP
    end
    return {
        icon = look.icon,
        cooldown = look.cooldown,
        textLevel = textLevel,
        resize = Resize,
        count = look.Count,
        scalesNumbers = true,
    }
end

local function DressSimple(button)
    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(EDGE_COLOR[1], EDGE_COLOR[2], EDGE_COLOR[3], EDGE_COLOR[4])

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", EDGE_SIZE, -EDGE_SIZE)
    icon:SetPoint("BOTTOMRIGHT", -EDGE_SIZE, EDGE_SIZE)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    return { icon = icon, cooldown = cooldown, textLevel = cooldown:GetFrameLevel() + 1 }
end

-- options: name -- global frame name (secure buttons work best with one), size,
-- onEnter(button), onLeave(button)
function ns.UI.BuffButton(parent, options)
    local button = CreateFrame("Button", options.name, parent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")

    local look = DressActionBar(button, options.size) or DressSimple(button)
    local icon = look.icon
    local cooldown = look.cooldown

    -- the swipe shows the time left: full at the start, empty at the end
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

    -- above the look: the count of items in the bags and the mouse-over highlight
    -- (the button's own highlight texture would be under the template)
    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(look.textLevel)
    local count = look.count
    if not count then
        count = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    local highlight = textLayer:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(HIGHLIGHT_TEXTURE)
    highlight:SetBlendMode("ADD")
    highlight:Hide()

    button:SetScript("OnEnter", function(self)
        highlight:Show()
        if options.onEnter then
            options.onEnter(self)
        end
    end)
    button:SetScript("OnLeave", function(self)
        highlight:Hide()
        if options.onLeave then
            options.onLeave(self)
        end
    end)

    -- out of combat only
    function button:SetIconSize(size)
        self:SetSize(size, size)
        if look.resize then
            look.resize(size)
        end
        -- the action bar look is scaled with its numbers; the simple one gets a font for its size
        if countdown and countdownFont and not look.scalesNumbers then
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
