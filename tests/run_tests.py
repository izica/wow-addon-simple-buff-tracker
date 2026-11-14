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
function Frame:HookScript(name, handler)
    local previous = self.scripts[name]
    self.scripts[name] = function(...)
        if previous then previous(...) end
        handler(...)
    end
end
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
function Frame:SetFrameStrata(strata) self.strata = strata end
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
allFrames = {}
function CreateFrame(frameType, name, parent, template)
    local frame = NewFrame()
    frame.parent = parent
    table.insert(allFrames, frame)
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


FAKE_LIBRARIES = r"""
local dataBroker = LibStub:NewLibrary("LibDataBroker-1.1", 1)
function dataBroker:NewDataObject(name, object) launcher = object; return object end
local dbIcon = LibStub:NewLibrary("LibDBIcon-1.0", 1)
minimapRegistered = false
function dbIcon:IsRegistered() return minimapRegistered end
function dbIcon:Register(name, object, settings) minimapRegistered = true end
function dbIcon:Hide() minimapShown = false end
function dbIcon:Show() minimapShown = true end

-- AceConfig: keeps the registered options; Options(name) builds the table as the dialog would
local registry = LibStub:NewLibrary("AceConfigRegistry-3.0", 1)
optionTables = {}
notified = 0
function registry:RegisterOptionsTable(name, options) optionTables[name] = options end
function registry:NotifyChange() notified = notified + 1 end
function registry:GetOptionsTable(name) return optionTables[name] end
function Options(name)
    local options = optionTables[name]
    if type(options) == "function" then return options() end
    return options
end
local dialog = LibStub:NewLibrary("AceConfigDialog-3.0", 1)
blizzardPages = {}
function dialog:AddToBlizOptions(name, title, parent)
    table.insert(blizzardPages, { name = name, title = title, parent = parent })
    return NewFrame(), #blizzardPages
end
function dialog:SelectGroup(name, key) selectedGroup = key end
dialog.OpenFrames = {}
function dialog:SetDefaultSize(name, width, height) windowSize = { width, height } end
function dialog:Open(name) self.OpenFrames[name] = NewFrame() end
function dialog:Close(name) self.OpenFrames[name] = nil end
Settings = { OpenToCategory = function(id) openedCategory = id end }

local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
function gui:ClearFocus() keyboardFocus = nil end
gui.WidgetRegistry = {}
function gui:RegisterWidgetType(name, constructor) self.WidgetRegistry[name] = constructor end
-- AceGUI's EditBox: a widget around an edit box frame; Fire("OnEnterPressed") is what AceConfigDialog hears
gui.WidgetRegistry.EditBox = function()
    local editbox = NewFrame()
    editbox.value = ""
    function editbox:GetText() return self.value end
    function editbox:HasFocus() return self.focused end
    function editbox:GetWidth() return 300 end
    local widget = { editbox = editbox, type = "EditBox", fired = {} }
    function widget:SetText(text) editbox.value = text end
    function widget:Fire(event, text) table.insert(self.fired, text) end
    function widget:OnRelease() end
    return widget
end
function Type(editbox, text)
    editbox.value = text
    editbox.scripts.OnTextChanged(editbox, true)
end

-- the spellbook and the bags, for the icon search
spellBook = { { name = 'Arcane Intellect', spellID = 1459, iconID = 135932 },
              { name = 'Frost Armor', spellID = 168, iconID = 135843 } }
Enum = { SpellBookSpellBank = { Player = 0 } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #spellBook } end,
    GetSpellBookItemInfo = function(index) return spellBook[index] end,
}
bagItems = { { itemID = 2683, itemName = 'Crab Cake', iconFileID = 133950 } }
C_Container = {
    GetContainerNumSlots = function(bag) if bag == 0 then return #bagItems end return 0 end,
    GetContainerItemInfo = function(bag, slot) return bagItems[slot] end,
}

-- the client's buff frame: shift-click a buff -> EventRegistry "BuffButton.OnClick"
shiftDown = false
function IsShiftKeyDown() return shiftDown end
function GetCurrentKeyBoardFocus() return keyboardFocus end
local callbacks = {}
EventRegistry = { RegisterCallback = function(self, event, handler, owner)
    callbacks[event] = { handler = handler, owner = owner }
end }
aurasByInstance = {}
C_UnitAuras.GetAuraDataByAuraInstanceID = function(unit, id) return aurasByInstance[id] end
function ShiftClickBuff(auraInstanceId)
    shiftDown = true
    local callback = callbacks["BuffButton.OnClick"]
    callback.handler(callback.owner, { buttonInfo = { auraInstanceID = auraInstanceId } }, "LeftButton")
    shiftDown = false
end
-- an AceGUI edit box of the buff window in focus; Enter runs the option's validate + set
function FocusField(buffKey, optionKey)
    local option = Options('SimpleBuffTracker_Buffs').args[buffKey].args[optionKey]
    local widget = {
        user = { appName = 'SimpleBuffTracker_Buffs', path = { buffKey, optionKey } },
    }
    function widget:GetUserDataTable() return self.user end
    function widget:SetText(text) self.text = text end
    function widget:Fire(event, text)
        if option.validate and option.validate(nil, text) ~= true then return end
        option.set(nil, text)
    end
    keyboardFocus = { obj = widget }
    return widget
end

-- shift-click on an item in the bags: HandleModifiedItemClick -> ChatFrameUtil.InsertLink,
-- with the hooks of AceGUI and of the addon after it
function hooksecurefunc(owner, name, hook)
    local original = owner[name]
    owner[name] = function(...)
        local result = original(...)
        hook(...)
        return result
    end
end
ChatFrameUtil = { InsertLink = function(link) return false end }
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
        if relative.endswith(".xml"):
            continue   # the minimap libraries: FAKE_LIBRARIES stand in for them
        with open(os.path.join(ADDON_FOLDER, relative), encoding="utf-8") as source:
            code = source.read()
        chunk = lua.eval("function(code, name) return assert(loadstring(code, name)) end")(code, "@" + relative)
        lua.execute("local chunk = ...; chunk('%s', ns)" % ADDON, chunk)
        if relative.endswith("LibStub.lua"):
            lua.execute(FAKE_LIBRARIES)
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


def test_minimap():
    lua = new_runtime()
    check("minimap button registered on login", lua.eval("minimapRegistered") is True)
    lua.execute("launcher.OnClick(nil, 'LeftButton')")
    check("left click opens the buff window",
          lua.eval("LibStub('AceConfigDialog-3.0').OpenFrames.SimpleBuffTracker_Buffs") is not None)
    lua.execute("launcher.OnClick(nil, 'LeftButton')")
    check("a second left click closes it",
          lua.eval("LibStub('AceConfigDialog-3.0').OpenFrames.SimpleBuffTracker_Buffs") is None)
    lua.execute("shiftDown = true; launcher.OnClick(nil, 'LeftButton'); shiftDown = false")
    check("shift + left click opens the settings", lua.eval("openedCategory") == 1)
    lua.execute("launcher.OnClick(nil, 'RightButton')")
    check("right click switches the mode", lua.eval("SimpleBuffTrackerDB.settings.mode") == "missing")
    lua.execute("Slash('move')")
    check("/sbt move unlocks the panel", lua.eval("SimpleBuffTrackerDB.settings.locked") is False)
    lua.execute("launcher.OnTooltipShow(GameTooltip)")
    check("tooltip shows without errors", True)
    lua.execute("Slash('minimap')")
    check("/sbt minimap hides the button",
          lua.eval("SimpleBuffTrackerDB.settings.minimap.hide") is True and lua.eval("minimapShown") is False)


def test_settings():
    lua = new_runtime()
    check("one page in Options -> AddOns, buffs in their own window", lua.eval("#blizzardPages") == 1
          and lua.eval("windowSize[1]") == 640)
    lua.execute("Options('SimpleBuffTracker').args.openBuffs.func()")
    check("the settings page button opens the buff window",
          lua.eval("LibStub('AceConfigDialog-3.0').OpenFrames.SimpleBuffTracker_Buffs") is not None)
    check("the window is titled", lua.eval("Options('SimpleBuffTracker_Buffs').name") == "Simple Buff Tracker: buffs")

    # the general page writes the settings and builds without errors
    lua.execute("""
        local general = Options('SimpleBuffTracker')
        general.args.mode.set(nil, 'missing')
        general.args.iconSize.set(nil, 40)
        general.args.unlocked.set(nil, true)
        general.args.minimap.set(nil, false)
    """)
    check("general page: mode", lua.eval("SimpleBuffTrackerDB.settings.mode") == "missing")
    check("general page: icon size", lua.eval("SimpleBuffTrackerDB.settings.iconSize") == 40)
    check("general page: unlock", lua.eval("SimpleBuffTrackerDB.settings.locked") is False)
    check("general page: hide minimap button", lua.eval("SimpleBuffTrackerDB.settings.minimap.hide") is True)

    # add a buff and fill it in, field by field, like a player would
    lua.execute("Options('SimpleBuffTracker_Buffs').args.add.func()")
    check("add makes an empty buff and selects it",
          lua.eval("#SimpleBuffTrackerDB.buffs") == 1 and lua.eval("selectedGroup") == "buff1")
    check("an empty buff is named 'New buff'", lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.name") == "New buff")
    lua.execute("""
        local page = Options('SimpleBuffTracker_Buffs').args.buff1.args
        page.aura.set(nil, 'Arcane Intellect')
    """)
    lua.execute("Options('SimpleBuffTracker_Buffs').args.buff1.args.sourceKind.set(nil, 'spell')")
    check("spell source takes the buff's own spell",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.name") == "Arcane Intellect")
    check("the page is named after the buff",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.name") == "Arcane Intellect")

    lua.execute("Options('SimpleBuffTracker_Buffs').args.add.func()")
    lua.execute("Options('SimpleBuffTracker_Buffs').args.buff2.args.target.set(nil, 'mainhand')")
    lua.execute("Options('SimpleBuffTracker_Buffs').args.buff2.args.sourceKind.set(nil, 'item')")
    check("a picked but empty item does nothing on click", lua.eval("secureButtons[2].attributes.type") is None)
    check("unknown item is refused by the field",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff2.args.sourceValue.validate(nil, 'Nothing')")
          == "unknown item: put it into the bags or give its id or link (shift-click)")
    lua.execute("""Options('SimpleBuffTracker_Buffs').args.buff2.args.sourceValue.set(nil,
        '|cff1eff00|Hitem:20749::::|h[Brilliant Wizard Oil]|h|r')""")
    check("a dragged item link fills the oil in",
          lua.eval("secureButtons[2].attributes.macrotext") == "/use item:20749\n/use 16")
    check("the item field shows the item name",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff2.args.sourceValue.get()") == "Brilliant Wizard Oil")

    lua.execute("Options('SimpleBuffTracker_Buffs').args.buff2.args.moveUp.func()")
    check("move up swaps the buffs", lua.eval("SimpleBuffTrackerDB.buffs[1].target.weapon") == "mainhand"
          and lua.eval("selectedGroup") == "buff1")
    lua.execute("Options('SimpleBuffTracker_Buffs').args.buff1.args.remove.func()")
    check("delete removes the buff", lua.eval("#SimpleBuffTrackerDB.buffs") == 1
          and lua.eval("SimpleBuffTrackerDB.buffs[1].target.name") == "Arcane Intellect")
    lua.execute("Slash('add Well Fed')")
    check("a chat command redraws the settings", lua.eval("notified") > 0
          and lua.eval("Options('SimpleBuffTracker_Buffs').args.buff2.name") == "Well Fed")


def test_shift_click():
    lua = new_runtime()
    lua.execute("""
        aurasByInstance[7] = { spellId = 1459, name = 'Arcane Intellect' }
        aurasByInstance[8] = { spellId = 19705, name = 'Well Fed' }
        aurasByInstance[9] = { spellId = SECRET, name = SECRET }
        ShiftClickBuff(7)
    """)
    check("window closed: a shift-click does nothing", lua.eval("#SimpleBuffTrackerDB.buffs") == 0)

    lua.execute("Slash('buffs'); ShiftClickBuff(7)")
    check("window open, no field in focus: a new buff",
          lua.eval("#SimpleBuffTrackerDB.buffs") == 1
          and lua.eval("SimpleBuffTrackerDB.buffs[1].target.name") == "Arcane Intellect"
          and lua.eval("selectedGroup") == "buff1")
    lua.execute("selectedGroup = nil; ShiftClickBuff(7)")
    check("the same buff again: its page, no copy",
          lua.eval("#SimpleBuffTrackerDB.buffs") == 1 and lua.eval("selectedGroup") == "buff1")

    lua.execute("Options('SimpleBuffTracker_Buffs').args.add.func(); FocusField('buff2', 'aura'); ShiftClickBuff(8)")
    check("field in focus: the buff goes into it",
          lua.eval("#SimpleBuffTrackerDB.buffs") == 2
          and lua.eval("SimpleBuffTrackerDB.buffs[2].target.name") == "Well Fed"
          and lua.eval("keyboardFocus") is None)

    lua.execute("""
        Options('SimpleBuffTracker_Buffs').args.buff2.args.sourceKind.set(nil, 'spell')
        FocusField('buff2', 'sourceValue')
        ShiftClickBuff(7)
    """)
    check("the spell field takes it too", lua.eval("SimpleBuffTrackerDB.buffs[2].source.name") == "Arcane Intellect")

    lua.execute("ShiftClickBuff(9)")
    check("a secret aura is skipped", lua.eval("#SimpleBuffTrackerDB.buffs") == 2)


OIL_LINK = "|cff1eff00|Hitem:20749::::|h[Brilliant Wizard Oil]|h|r"
SPELL_LINK = "|cff71d5ff|Hspell:1459:0|h[Arcane Intellect]|h|r"


def test_item_link():
    lua = new_runtime()
    lua.execute("""
        Slash('add mainhand = item 2683')
        Slash('buffs')
        oilField = FocusField('buff1', 'sourceValue')
    """)
    lua.execute("ChatFrameUtil.InsertLink(...)", SPELL_LINK)
    check("a spell link is not taken by the item field",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 2683
          and lua.eval("oilField.text") == "Crab Cake")
    lua.execute("ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("a shift-clicked item goes into the item field",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 20749
          and lua.eval("keyboardFocus") is None)

    lua.execute("Slash('add Fake Buff = spell'); FocusField('buff2', 'aura')")
    lua.execute("ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("an item link is not taken by the buff field",
          lua.eval("SimpleBuffTrackerDB.buffs[2].target.name") == "Fake Buff")
    lua.execute("ChatFrameUtil.InsertLink(...)", SPELL_LINK)
    check("a spellbook link goes into the buff field",
          lua.eval("SimpleBuffTrackerDB.buffs[2].target.spellId") == 1459)

    lua.execute("keyboardFocus = nil")
    lua.execute("ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("no field in focus: links go to the chat as usual", lua.eval("#SimpleBuffTrackerDB.buffs") == 2)


def test_icons():
    lua = new_runtime()
    lua.execute("Slash('add Well Fed')")
    check("a typed buff the client does not know: question mark",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.icon") == 134400)
    lua.execute("""
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = clock + 900, duration = 900 } }
        Fire('UNIT_AURA', 'player')
        auras = {}
        Fire('UNIT_AURA', 'player')
    """)
    check("seen once on the player: its picture is kept",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.icon") == 136000
          and lua.eval("SimpleBuffTrackerDB.buffs[1].target.spellId") == 19705)
    lua.execute("""
        auras = { { spellId = 23697, name = 'Mana Regeneration', icon = 137000, expirationTime = 0, duration = 0 } }
        Fire('UNIT_AURA', 'player')
        Slash('add Mana Regeneration')
    """)
    check("typed while the buff is on: picture right away",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff2.icon") == 137000)


def test_learned_icon_redraws_window():
    lua = new_runtime()
    lua.execute("Slash('add Well Fed'); notified = 0")
    lua.execute("""
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = clock + 900, duration = 900 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("a learned picture redraws the buff window", lua.eval("notified") >= 1)
    lua.execute("notified = 0; RunTickers()")
    check("nothing new: no redraw every tick", lua.eval("notified") == 0)


def test_debug():
    lua = new_runtime()
    lua.execute("""
        Slash('add Well Fed')
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = clock + 900, duration = 900 },
                  { spellId = SECRET, name = SECRET, icon = 1, expirationTime = 0, duration = 0 } }
        chat = {}
        Slash('debug')
    """)
    text = "\n".join(lua.eval("chat")[i] for i in range(1, int(lua.eval("#chat")) + 1))
    check("debug lists the auras", "name=Well Fed spellId=19705" in text)
    check("debug marks secret values", "name=<secret>" in text)
    check("debug shows the match of each buff", "found=Well Fed" in text)


def test_icon_field():
    lua = new_runtime()
    lua.execute("Slash('add Well Fed = item 2683'); Slash('buffs')")
    check("no picked icon: the food's picture", lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.icon") == 133000 + 2683)
    lua.execute("Options('SimpleBuffTracker_Buffs').args.buff1.args.icon.set(nil, '1459')")
    check("a spell id sets the picture", lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.icon") == 135932)
    check("an unknown spell is refused",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.args.icon.validate(nil, 'Nothing at all')") != True)
    lua.execute("FocusField('buff1', 'icon'); ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("a shift-clicked item sets the picture", lua.eval("SimpleBuffTrackerDB.buffs[1].icon") == 133000 + 20749)
    lua.execute("""
        aurasByInstance[7] = { spellId = 1459, name = 'Arcane Intellect' }
        FocusField('buff1', 'icon')
        ShiftClickBuff(7)
    """)
    check("a shift-clicked buff sets the picture by its id",
          lua.eval("SimpleBuffTrackerDB.buffs[1].iconText") == "1459")
    lua.execute("""
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = clock + 900, duration = 900 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("a picked icon wins over the aura's", lua.eval("secureButtons[1].state.icon") == 135932)
    lua.execute("Options('SimpleBuffTracker_Buffs').args.buff1.args.icon.set(nil, '')")
    check("empty: automatic again", lua.eval("secureButtons[1].state.icon") == 136000)


def labels(lua, query):
    found = lua.eval("ns.Dataflows.IconSearch.Search(...)", query)
    return [found[i].label for i in range(1, len(found) + 1)]


def test_icon_search():
    lua = new_runtime()
    lua.execute("""
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = 0, duration = 0 },
                  { spellId = SECRET, name = 'Hidden Thing', icon = 136001, expirationTime = 0, duration = 0 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("a buff on you is found", labels(lua, "well") == ["Well Fed"])
    check("a spellbook spell is found", labels(lua, "arcane") == ["Arcane Intellect"])
    check("a bag item is found", labels(lua, "crab") == ["Crab Cake"])
    check("names starting with the query come first", labels(lua, "ar")[0] == "Arcane Intellect"
          and "Frost Armor" in labels(lua, "ar"))
    check("one letter: no search", labels(lua, "a") == [])
    check("a number is an id, not a search", labels(lua, "1459") == [])
    lua.execute("C_Container.GetContainerNumSlots = function() error('broken bags') end")
    check("a failing source does not stop the others", labels(lua, "arcane") == ["Arcane Intellect"])
    found = lua.eval("ns.Dataflows.IconSearch.Search('hidden')")
    check("a buff without a plain spell id gives its picture id", found[1].text == "icon:136001")
    check("the picture id is read back", lua.eval("ns.Dataflows.BuffParser.ParseIcon('icon:136001')") == 136001
          and lua.eval("ns.Dataflows.BuffParser.ParseIcon('item:2683')") == 133000 + 2683)


def test_suggest_edit_box():
    lua = new_runtime()
    lua.execute("""
        box = LibStub('AceGUI-3.0').WidgetRegistry[ns.UI.SUGGEST_EDIT_BOX]()
        box:SetCustomData(ns.Dataflows.IconSearch.Search)
        function ShownRows()
            local rows = {}
            for _, frame in ipairs(allFrames) do
                local parent = rawget(frame, 'parent')
                local isRow = parent and rawget(parent, 'strata') == 'TOOLTIP' and rawget(frame, 'label')
                if isRow and frame.shown and frame.parent.shown then
                    table.insert(rows, frame)
                end
            end
            return rows
        end
    """)
    check("the widget has its own type", lua.eval("box.type") == "SimpleBuffTrackerSuggestEditBox")
    lua.execute("Slash('add Well Fed')")
    check("the icon field uses it",
          lua.eval("Options('SimpleBuffTracker_Buffs').args.buff1.args.icon.dialogControl")
          == "SimpleBuffTrackerSuggestEditBox")

    lua.execute("Type(box.editbox, 'arc')")
    check("typing shows the list", lua.eval("#ShownRows()") == 1
          and lua.eval("ShownRows()[1].label.text") == "Arcane Intellect")
    lua.execute("ShownRows()[1].scripts.OnClick(ShownRows()[1])")
    check("a click on a row saves its text like Enter",
          lua.eval("box.fired[1]") == "1459" and lua.eval("box.editbox.value") == "1459")
    check("and hides the list", lua.eval("#ShownRows()") == 0)

    lua.execute("Type(box.editbox, 'zzz')")
    check("nothing found: no list", lua.eval("#ShownRows()") == 0)
    lua.execute("Type(box.editbox, 'crab'); box:OnRelease()")
    check("release hides the list and forgets the search",
          lua.eval("#ShownRows()") == 0 and lua.eval("box.search") is None)


def test_russian():
    lua = new_runtime("ruRU")
    lua.execute("Slash('list')")
    check("russian texts load", "бафов пока нет" in last_chat(lua))


def main():
    test_buffs()
    test_minimap()
    test_settings()
    test_shift_click()
    test_item_link()
    test_icons()
    test_learned_icon_redraws_window()
    test_debug()
    test_icon_field()
    test_icon_search()
    test_suggest_edit_box()
    test_russian()
    if failures:
        print("\n%d failed" % len(failures))
        sys.exit(1)
    print("\nall passed")


if __name__ == "__main__":
    main()
