-- buff_frame.lua -- shift-click on a buff in the client's own buff frame (top
-- right): the buff goes into the buff window (components/settings_window.lua).
--
-- On Forever the buff buttons are AuraButtonMixin (Blizzard_BuffFrame/BuffFrame.lua):
-- a click on a buff fires EventRegistry "BuffButton.OnClick" (button frame, mouse
-- button); the frame's buttonInfo.auraInstanceID names the aura. Weapon enchants
-- there fire nothing -- they are picked by the "What is tracked" list.

local ADDON, ns = ...

local Secrets = ns.Utilities.Secrets

local function Plain(value)
    if Secrets.IsSecret(value) then
        return nil
    end
    return value
end

local function OnBuffClick(_, buttonFrame, mouseButton)
    local isShiftClick = mouseButton == "LeftButton" and IsShiftKeyDown()
    if not isShiftClick then
        return
    end
    local buttonInfo = buttonFrame and buttonFrame.buttonInfo
    local auraInstanceId = buttonInfo and Plain(buttonInfo.auraInstanceID)
    local canRead = auraInstanceId and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if not canRead then
        return
    end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", auraInstanceId)
    if not (ok and aura) then
        return
    end
    local spellId = Plain(aura.spellId)
    local name = Plain(aura.name)
    if spellId or name then
        ns.Components.SettingsWindow.PickAura(spellId, name)
    end
end

ns.Events.On("PLAYER_LOGIN", function()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("BuffButton.OnClick", OnBuffClick, ns)
    end
end)
