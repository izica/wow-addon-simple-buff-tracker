"""Loads the addon in LuaJIT (lupa) with stubs of the client API and plays
buffs, combat and chat commands through it. Usage: python tests/run_tests.py

The stubs are strict about secure frames: showing, hiding, moving or changing
the attributes of a secure button (or of the panel holding them) while
InCombatLockdown() is true is an error, as ADDON_ACTION_BLOCKED in the game.
Looking through auras while they are hidden is an error too."""

import os
import sys

from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "SimpleBuffTracker"
ADDON_FOLDER = os.path.join(ROOT, ADDON)

STUBS = r"""
clock = 1000
function GetTime() return clock end
local tickers = {}
C_Timer = {
    NewTicker = function(seconds, handler) table.insert(tickers, handler) end,
    After = function(seconds, handler) handler() end,
}
function RunTickers() for _, handler in ipairs(tickers) do handler() end end
function GetLocale() return locale or "enUS" end
function SecondsToTime(seconds) return seconds .. " sec" end

local secretMeta = {
    __lt = function() error("attempt to compare a secret value") end,
    __le = function() error("attempt to compare a secret value") end,
    __concat = function() error("attempt to concatenate a secret value") end,
}
SECRET = setmetatable({}, secretMeta)
function issecretvalue(value) return value == SECRET end

inCombat = false
function InCombatLockdown() return inCombat end

chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, text) table.insert(chat, text) end }

-- frames: unknown methods do nothing; secure ones refuse protected calls in combat
local PROTECTED = { Show = true, Hide = true, SetPoint = true, ClearAllPoints = true,
    SetSize = true, SetAttribute = true, SetShown = true, SetAlpha = true, SetScale = true }
local Frame = {}
function Frame:SetScript(name, handler) self.scripts[name] = handler end
function Frame:RegisterEvent(event) eventFrame = self end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(shown) self.shown = shown and true or false end
function Frame:IsShown() return self.shown end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:SetPoint(...) self.point = { ... } end
function Frame:GetPoint() return "TOPLEFT", nil, "TOPLEFT", 10, -20 end
function Frame:GetFrameLevel() return 1 end
function Frame:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
function Frame:SetText(text) self.text = text end
function Frame:SetTexture(texture) self.texture = texture end
function Frame:SetDesaturated(value) self.desaturated = value end
function Frame:SetCooldown(start, duration) self.cooldown = { start, duration } end
function Frame:Clear() self.cooldown = nil end
function Frame:CreateTexture() return NewFrame() end
function Frame:CreateFontString() return NewFrame() end
function Frame:GetCountdownFontString() return NewFrame() end

local frameMeta = {
    __index = function(self, key)
        local method = Frame[key]
        if not method then
            return function() end
        end
        if PROTECTED[key] and rawget(self, "protected") then
            return function(...)
                if inCombat then
                    error("ADDON_ACTION_BLOCKED: " .. key .. " in combat")
                end
                return method(...)
            end
        end
        return method
    end,
}
function NewFrame()
    return setmetatable({ scripts = {}, attributes = {}, shown = true }, frameMeta)
end

panelFrame = nil
secureButtons = {}
function CreateFrame(frameType, name, parent, template)
    local frame = NewFrame()
    frame.parent = parent
    if template and template:find("SecureActionButtonTemplate") then
        frame.protected = true
        table.insert(secureButtons, frame)
        if parent then
            parent.protected = true
        end
    end
    if name then
        _G[name] = frame
    end
    return frame
end
UIParent = NewFrame()
GameTooltip = NewFrame()

-- the player's buffs
aurasHidden = false
auras = {}
C_Secrets = { ShouldAurasBeSecret = function() return aurasHidden end }
C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if aurasHidden then
            error("Auras cannot be accessed when secret while tainted")
        end
        return auras[index]
    end,
}

weaponEnchant = { false, 0, 0, 0, false, 0, 0, 0 }
function GetWeaponEnchantInfo() return unpack(weaponEnchant) end
function GetInventoryItemTexture() return 135000 end

local spells = {
    [1459] = { spellID = 1459, name = "Arcane Intellect", iconID = 135932 },
}
C_Spell = {
    GetSpellInfo = function(identifier)
        for _, info in pairs(spells) do
            if info.spellID == identifier or info.name == identifier then
                return info
            end
        end
        return nil
    end,
    GetSpellName = function(spellId) return spells[spellId] and spells[spellId].name end,
    GetSpellTexture = function(identifier)
        local info = C_Spell.GetSpellInfo(identifier)
        return info and info.iconID
    end,
}

local items = { [2683] = "Crab Cake", [20749] = "Brilliant Wizard Oil" }
itemCounts = { [2683] = 5, [20749] = 0 }
C_Item = {
    GetItemInfoInstant = function(identifier)
        local id = tonumber(tostring(identifier):match("item:(%d+)"))
        if id then return id end
        for itemId, name in pairs(items) do
            if name == identifier then return itemId end
        end
        return nil
    end,
    GetItemNameByID = function(itemId) return items[itemId] end,
    GetItemIconByID = function(itemId) return 133000 + itemId end,
    GetItemCount = function(itemId) return itemCounts[itemId] or 0 end,
}

SlashCmdList = {}
function Fire(event, ...)
    local handler = eventFrame.scripts.OnEvent
    handler(eventFrame, event, ...)
end
function Slash(text) SlashCmdList.SIMPLEBUFFTRACKER(text) end
"""


def toc_files():
    with open(os.path.join(ADDON_FOLDER, ADDON + ".toc"), encoding="utf-8") as toc:
        for line in toc:
            line = line.strip()
            if line and not line.startswith("#"):
                yield line.replace("\\", os.sep)


def new_runtime(locale="enUS"):
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.globals().locale = locale
    lua.execute("ns = {}")
    for relative in toc_files():
        with open(os.path.join(ADDON_FOLDER, relative), encoding="utf-8") as source:
            code = source.read()
        chunk = lua.eval("function(code, name) return assert(loadstring(code, name)) end")(code, "@" + relative)
        lua.execute("local chunk = ...; chunk('%s', ns)" % ADDON, chunk)
    lua.execute("Fire('ADDON_LOADED', '%s'); Fire('PLAYER_LOGIN'); Fire('PLAYER_ENTERING_WORLD')" % ADDON)
    return lua


failures = []


def check(name, condition):
    if condition:
        print("ok    " + name)
    else:
        print("FAIL  " + name)
        failures.append(name)


def shown_buttons(lua):
    return lua.eval("""(function()
        local result = {}
        for _, button in ipairs(secureButtons) do
            if button.shown then table.insert(result, button) end
        end
        return #result
    end)()""")


def last_chat(lua):
    return lua.eval("chat[#chat]") or ""


def test_buffs():
    lua = new_runtime()
    lua.execute("Slash('add Arcane Intellect = spell')")
    check("add a spell buff with its own spell", "added: Arcane Intellect" in last_chat(lua))
    lua.execute("Slash('add Well Fed = item Crab Cake')")
    check("add food by item name", "Crab Cake" in last_chat(lua))
    lua.execute("Slash('add mainhand = item |cff1eff00|Hitem:20749::::|h[Brilliant Wizard Oil]|h|r')")
    check("add a weapon oil by link", "Brilliant Wizard Oil" in last_chat(lua))
    lua.execute("Slash('add Trueshot Aura')")
    check("add a buff that is only tracked", last_chat(lua).endswith("added: Trueshot Aura"))
    lua.execute("Slash('add |cffffffff|Hitem:2683::::|h[Crab Cake]|h|r')")
    check("an item is not a buff", "not an item" in lua.eval("chat[#chat - 1]"))
    lua.execute("Slash('add Well Fed = eat it')")
    check("a source needs spell or item", "write spell or item" in lua.eval("chat[#chat - 1]"))
    lua.execute("Slash('add Well Fed = item Unknown Thing')")
    check("an unknown item is refused", "unknown item" in lua.eval("chat[#chat - 1]"))
    check("four buffs in the list", lua.eval("#SimpleBuffTrackerDB.buffs") == 4)

    lua.execute("""
        auras = { { spellId = 1459, name = "Arcane Intellect", icon = 135932,
                    expirationTime = clock + 1800, duration = 1800 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("all mode shows every buff", shown_buttons(lua) == 4)
    check("spell button casts the spell",
          lua.eval("secureButtons[1].attributes.type") == "spell"
          and lua.eval("secureButtons[1].attributes.spell") == "Arcane Intellect")
    check("food button uses the item", lua.eval("secureButtons[2].attributes.item") == "item:2683")
    check("oil button puts the oil on the main hand",
          lua.eval("secureButtons[3].attributes.macrotext") == "/use item:20749\n/use 16")
    check("tracked-only button has no action", lua.eval("secureButtons[4].attributes.type") is None)
    check("active buff has its timer", lua.eval("secureButtons[1].state.isActive") is True)
    check("food count is shown", lua.eval("secureButtons[2].state.itemCount") == 5)

    lua.execute("Slash('mode missing')")
    check("missing mode hides the active buff", shown_buttons(lua) == 3)
    lua.execute("clock = clock + 1700; RunTickers()")
    check("a buff about to run out shows again", shown_buttons(lua) == 4)

    lua.execute("""
        clock = clock - 1700
        RunTickers()
        weaponEnchant = { true, 1800000, 0, 2628, false, 0, 0, 0 }
        RunTickers()
    """)
    check("an oil on the weapon counts as the buff", shown_buttons(lua) == 2)

    # combat: auras hidden, the layout must not move
    lua.execute("""
        inCombat = true
        aurasHidden = true
        Fire('UNIT_AURA', 'player')
        clock = clock + 1900
        RunTickers()
    """)
    check("in combat the icons stay where they were", shown_buttons(lua) == 2)
    lua.execute("Slash('mode all')")
    check("mode does not change in combat", "not in combat" in last_chat(lua))

    lua.execute("""
        inCombat = false
        aurasHidden = false
        auras = {}
        Fire('PLAYER_REGEN_ENABLED')
    """)
    check("after combat the missing buffs are laid out", shown_buttons(lua) == 3)

    lua.execute("Slash('remove 2')")
    check("remove by number", "removed: Well Fed" in last_chat(lua))
    lua.execute("Slash('remove 9')")
    check("remove a number that is not there", "no buff with this number" in last_chat(lua))
    lua.execute("Slash('list')")
    check("list numbers the buffs", "3. Trueshot Aura" in last_chat(lua))


def test_russian():
    lua = new_runtime("ruRU")
    lua.execute("Slash('list')")
    check("russian texts load", "бафов пока нет" in last_chat(lua))


def main():
    test_buffs()
    test_russian()
    if failures:
        print("\n%d failed" % len(failures))
        sys.exit(1)
    print("\nall passed")


if __name__ == "__main__":
    main()
