-- buff_button.lua -- a buff icon that is also a secure action button: a click
-- casts the spell or uses the item set by SetAction.
--
-- Looks (ns.Constants.ICON_TEMPLATE), switched by SetTemplate:
--   action_bar  -- the client's own ActionButtonTemplate inside, scaled to the
--                  icon size: the same art, icon and cooldown as the buttons of
--                  the action bars. Not drawn by hand: on Forever the art comes
--                  from the template as it is (the Mainline UpdateButtonArt does
--                  not load there), a copy of its pieces looked wrong in the game.
--                  The template button is only a
--                  picture: no action, no mouse; the secure button takes the clicks.
--   borderless  -- the same template with its frame art made invisible: the
--                  icon keeps the template's rounded mask, no border around it;
--   square      -- only the picture, square edges, no border.
-- Each look is made the first time it is chosen and kept: switching shows one,
-- hides the others. Without the template both template looks fall back to square.
--
-- SetGlow(effect) puts an effect around the icon (ui/glow.lua), over every look.
--
-- Secure: in combat the client does not let addons move, show, hide or change
-- the action of it (SetAction, Show, Hide, SetPoint -- only out of combat;
-- SetTemplate and SetIconSize too). The picture (icon, timer, count, tint) can
-- change any time.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local ICON_TEMPLATE = ns.Constants.ICON_TEMPLATE

local ICON_CROP = 0.08            -- icon textures have a frame around the picture: cut it off
local COUNTDOWN_FONT_SCALE = 0.36 -- the size of the timer numbers, part of the icon size (square look)
local MISSING_ALPHA = 0.9
local ACTIVE_ALPHA = 1
local NO_ITEMS_COLOR = { 1, 0.3, 0.3 }
local NORMAL_COLOR = { 1, 1, 1 }
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

local ACTION_BUTTON_TEMPLATE = "ActionButtonTemplate"
local ACTION_BUTTON_SIZE = 45     -- the size of the template button
-- above the template's own text overlay (frameLevel 500 in the template)
local ACTION_BUTTON_TEXT_LEVEL_GAP = 10
-- the frame art of the template, made invisible in the borderless look
local ACTION_BUTTON_FRAME_PARTS = { "Border", "SlotArt", "SlotBackground", "FloatingBG", "NewActionTexture" }

-- every attribute SetAction may set: the old ones are cleared first
local ACTION_ATTRIBUTES = { "type", "spell", "item", "macrotext" }

-- Each Dress* makes a look inside the button and returns { frame -- shown or
-- hidden as a whole, icon, cooldown, textLevel -- the frame level above it,
-- resize(size), scalesNumbers -- the numbers follow the size by themselves },
-- or nil when it can not be made.

local function DressActionBar(button, size, isBorderless)
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
    if isBorderless then
        local normalTexture = look.GetNormalTexture and look:GetNormalTexture()
        if normalTexture then
            normalTexture:SetAlpha(0)
        end
        for _, partName in ipairs(ACTION_BUTTON_FRAME_PARTS) do
            local part = look[partName]
            if type(part) == "table" and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
    end

    local textLevel = look:GetFrameLevel() + 1
    if look.TextOverlayContainer then
        textLevel = look.TextOverlayContainer:GetFrameLevel() + ACTION_BUTTON_TEXT_LEVEL_GAP
    end
    return {
        frame = look,
        icon = look.icon,
        cooldown = look.cooldown,
        textLevel = textLevel,
        resize = function(newSize)
            look:SetScale(newSize / ACTION_BUTTON_SIZE)
        end,
        scalesNumbers = true,
    }
end

local function DressSquare(button)
    local look = CreateFrame("Frame", nil, button)
    look:SetAllPoints()
    local icon = look:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    local cooldown = CreateFrame("Cooldown", nil, look, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    return { frame = look, icon = icon, cooldown = cooldown, textLevel = cooldown:GetFrameLevel() + 1 }
end

local function Dress(button, template, size)
    if template == ICON_TEMPLATE.SQUARE then
        return DressSquare(button)
    end
    local isBorderless = template == ICON_TEMPLATE.BORDERLESS
    return DressActionBar(button, size, isBorderless) or DressSquare(button)
end

-- options: name -- global frame name (secure buttons work best with one), size,
-- template -- ns.Constants.ICON_TEMPLATE, onEnter(button), onLeave(button)
function ns.UI.BuffButton(parent, options)
    local button = CreateFrame("Button", options.name, parent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")

    local looks = {}        -- [template] = look, made on first use
    local look = nil        -- the one shown
    local size = options.size

    -- above every look: the count of items in the bags and the mouse-over highlight
    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints()
    local count = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    local highlight = textLayer:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(HIGHLIGHT_TEXTURE)
    highlight:SetBlendMode("ADD")
    highlight:Hide()

    -- the effect around a missing buff, above the looks and the text layer
    local glow = ns.UI.Glow(button)

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

    local function ApplySize(target)
        if target.resize then
            target.resize(size)
        end
        -- the action bar look is scaled with its numbers; the square one gets a font for its size
        if target.countdown and target.countdownFont and not target.scalesNumbers then
            target.countdown:SetFont(target.countdownFont, math.floor(size * COUNTDOWN_FONT_SCALE),
                target.countdownFlags or "OUTLINE")
        end
    end

    local function MakeLook(template)
        local made = Dress(button, template, size)
        -- the swipe shows the time left: full at the start, empty at the end
        made.cooldown:SetReverse(true)
        if made.cooldown.SetHideCountdownNumbers then
            made.cooldown:SetHideCountdownNumbers(false)
        end
        local countdown = made.cooldown.GetCountdownFontString and made.cooldown:GetCountdownFontString()
        if countdown then
            made.countdown = countdown
            local font, _, flags = countdown:GetFont()   -- local _: a global one taints the game's code
            made.countdownFont = font
            made.countdownFlags = flags
        end
        textLayer:SetFrameLevel(math.max(textLayer:GetFrameLevel(), made.textLevel))
        return made
    end

    -- out of combat only; the picture is set again by the caller (Paint)
    function button:SetTemplate(template)
        if not looks[template] then
            looks[template] = MakeLook(template)
        end
        look = looks[template]
        for _, other in pairs(looks) do
            other.frame:SetShown(other == look)
        end
        ApplySize(look)
        glow:SetFrameLevel(textLayer:GetFrameLevel() + 1)
        self.template = template
    end

    -- out of combat only
    function button:SetIconSize(newSize)
        size = newSize
        self:SetSize(size, size)
        if look then
            ApplySize(look)
        end
    end

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
        look.icon:SetTexture(texture)
    end

    -- plain numbers; duration 0 or expirationTime 0 -- no timer
    function button:SetTimer(expirationTime, duration)
        local hasTimer = expirationTime > 0 and duration > 0
        if hasTimer then
            look.cooldown:SetCooldown(expirationTime - duration, duration)
        else
            look.cooldown:Clear()
        end
    end

    -- a missing buff: grey picture (the texture, not the secure button itself)
    function button:SetMissing(isMissing)
        look.icon:SetDesaturated(isMissing)
        if isMissing then
            look.icon:SetAlpha(MISSING_ALPHA)
        else
            look.icon:SetAlpha(ACTIVE_ALPHA)
        end
    end

    -- effect -- ns.Constants.GLOW_EFFECT, nil -- none; any time, in combat too
    function button:SetGlow(effect)
        glow:Set(effect)
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

    button:SetIconSize(size)
    button:SetTemplate(options.template or ICON_TEMPLATE.ACTION_BAR)
    return button
end
