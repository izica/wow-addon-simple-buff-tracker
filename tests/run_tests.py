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
function Frame:GetText() return self.text end
function Frame:GetWidth() return 300 end
function Frame:IsMouseOver() return false end
function Frame:SetChecked(value) self.checked = value end
function Frame:GetChecked() return self.checked end
function Frame:SetEnabled(value) self.enabled = value end
-- edit boxes: the focus, and the scripts the client fires with it
function Frame:HasFocus() return self.focused == true end
function Frame:SetFocus()
    if keyboardFocus and keyboardFocus ~= self then keyboardFocus:ClearFocus() end
    self.focused = true
    keyboardFocus = self
    if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
end
function Frame:ClearFocus()
    if not self.focused then return end
    self.focused = false
    if keyboardFocus == self then keyboardFocus = nil end
    if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end

-- fields a real frame has only with some templates: nil here, like on a plain frame
NIL_FIELDS = { TopEdge = true, TopLeftCorner = true, NineSlice = true, Instructions = true, Text = true,
    TextOverlayContainer = true, layoutType = true }
local frameMeta = {
    __index = function(self, key)
        if NIL_FIELDS[key] then return nil end
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
    frame.template = template
    table.insert(allFrames, frame)
    -- the action bar template comes with its parts
    if template == "ActionButtonTemplate" then
        frame.icon = NewFrame()
        frame.cooldown = NewFrame()
        frame.HotKey = NewFrame()
        frame.Count = NewFrame()
        frame.Name = NewFrame()
        frame.TextOverlayContainer = NewFrame()
    end
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

-- the addon window: inputs found by their field key, typed into like a player would
StaticPopupDialogs = {}
function StaticPopup_Show(name, textArgument, _, data) StaticPopupDialogs[name].OnAccept(nil, data) end
UISpecialFrames = {}
function PanelTemplates_SelectTab(tab) tab.selected = true end
function PanelTemplates_DeselectTab(tab) tab.selected = false end
function PanelTemplates_TabResize() end
YES = "Yes"
NO = "No"
function FindField(key)
    for _, frame in ipairs(allFrames) do
        if rawget(frame, "fieldKey") == key and frame.shown then return frame end
    end
end
function FindFrames(field)
    local found = {}
    for _, frame in ipairs(allFrames) do
        if rawget(frame, field) then table.insert(found, frame) end
    end
    return found
end
-- type text into a field: suggestions appear, nothing is saved yet
function TypeInto(input, text)
    input:SetFocus()
    input.text = text
    input.scripts.OnTextChanged(input, true)
end
-- type text and leave the field: saved
function Enter(key, text)
    local input = FindField(key)
    input:SetFocus()
    input.text = text
    input:ClearFocus()
end
function FocusField(key)
    local input = FindField(key)
    input:SetFocus()
    return input
end
function Window() return ns.Components.MainWindow end
function Rows()
    local rows = {}
    for _, frame in ipairs(allFrames) do
        local parent = rawget(frame, "parent")
        local isRow = rawget(frame, "index") and rawget(frame, "selection") and frame.shown
        if isRow then table.insert(rows, frame) end
    end
    table.sort(rows, function(a, b) return a.index < b.index end)
    return rows
end
function ShownSuggestions()
    local rows = {}
    for _, frame in ipairs(allFrames) do
        local parent = rawget(frame, "parent")
        local isRow = parent and rawget(parent, "strata") == "TOOLTIP" and rawget(frame, "label")
        if isRow and frame.shown and parent.shown then table.insert(rows, frame) end
    end
    return rows
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

-- shift-click on an item in the bags: HandleModifiedItemClick -> ChatFrameUtil.InsertLink,
-- with the addon's hook after it
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
    check("left click opens the window", lua.eval("Window().IsOpen()") is True)
    lua.execute("launcher.OnClick(nil, 'LeftButton')")
    check("a second left click closes it", lua.eval("Window().IsOpen()") is False)
    lua.execute("shiftDown = true; launcher.OnClick(nil, 'LeftButton'); shiftDown = false")
    check("shift + left click opens the Panel tab", lua.eval("Window().IsOpen()") is True)
    lua.execute("launcher.OnClick(nil, 'RightButton')")
    check("right click switches the mode", lua.eval("SimpleBuffTrackerDB.settings.mode") == "missing")
    lua.execute("Slash('move')")
    check("/sbt move unlocks the panel", lua.eval("SimpleBuffTrackerDB.settings.locked") is False)
    lua.execute("launcher.OnTooltipShow(GameTooltip)")
    check("tooltip shows without errors", True)
    lua.execute("Slash('minimap')")
    check("/sbt minimap hides the button",
          lua.eval("SimpleBuffTrackerDB.settings.minimap.hide") is True and lua.eval("minimapShown") is False)


def click_button(lua, text):
    lua.execute("""
        local wanted = ...
        for _, frame in ipairs(allFrames) do
            if frame.text == wanted and frame.shown and frame.scripts.OnClick then
                frame.scripts.OnClick(frame)
                return
            end
        end
        error('no button ' .. wanted)
    """, text)


def test_window_editing():
    lua = new_runtime()
    lua.execute("Slash('buffs')")
    check("the window opens", lua.eval("Window().IsOpen()") is True)
    check("Escape closes it", lua.eval("UISpecialFrames[1]") == "SimpleBuffTrackerWindow")
    check("no buffs: nothing to edit", lua.eval("FindField('aura') == nil") is True)

    click_button(lua, "Add buff")
    check("Add buff makes an empty buff and shows it",
          lua.eval("#SimpleBuffTrackerDB.buffs") == 1 and lua.eval("FindField('aura') ~= nil") is True)
    check("the list shows it as New buff", lua.eval("Rows()[1].label.text") == "New buff")

    lua.execute("Enter('aura', 'Arcane Intellect')")
    check("typing a name sets the buff", lua.eval("SimpleBuffTrackerDB.buffs[1].target.spellId") == 1459)
    check("the list follows", lua.eval("Rows()[1].label.text") == "Arcane Intellect")

    lua.execute("ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'spell'); Window().Refresh()")
    check("the spell source takes the buff's spell", lua.eval("FindField('sourceValue').text") == "Arcane Intellect")
    lua.execute("ns.Components.BuffPanel.Refresh()")
    check("a spell button casts it", lua.eval("secureButtons[1].attributes.spell") == "Arcane Intellect")

    lua.execute("ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'item'); Window().Refresh()")
    lua.execute("Enter('sourceValue', 'Nothing at all')")
    check("an unknown item changes nothing", lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") is None)
    lua.execute("Enter('sourceValue', 'Crab Cake')")
    check("a bag item by name", lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 2683)
    lua.execute("bagItems = {}; Enter('sourceValue', 'Crab Cake')")
    check("an unchanged name is not parsed again (item no longer in the bags)",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 2683)

    lua.execute("Enter('icon', '1459')")
    check("an icon by spell id", lua.eval("SimpleBuffTrackerDB.buffs[1].icon") == 135932)
    lua.execute("Enter('icon', '')")
    check("empty icon: automatic", lua.eval("SimpleBuffTrackerDB.buffs[1].icon") is None)

    click_button(lua, "Add buff")
    lua.execute("Enter('aura', 'Well Fed')")
    click_button(lua, "Up")
    check("Up moves the buff", lua.eval("SimpleBuffTrackerDB.buffs[1].target.name") == "Well Fed"
          and lua.eval("Rows()[1].label.text") == "Well Fed")
    click_button(lua, "Delete")
    check("Delete removes it after the question", lua.eval("#SimpleBuffTrackerDB.buffs") == 1
          and lua.eval("SimpleBuffTrackerDB.buffs[1].target.name") == "Arcane Intellect")

    lua.execute("Slash('add Trueshot Aura')")
    check("a chat command redraws the window", lua.eval("Rows()[2].label.text") == "Trueshot Aura")


def find_slider(lua, shown_text):
    return lua.eval("""(function(wanted)
        for _, slider in ipairs(FindFrames('isStepSlider')) do
            if slider.shown and slider.valueText.text == wanted then return slider end
        end
    end)(...)""", shown_text)


def test_warn_seconds():
    lua = new_runtime()
    lua.execute("""
        Slash('add Arcane Intellect = spell')
        Slash('mode missing')
        auras = { { spellId = 1459, name = 'Arcane Intellect', icon = 135932,
                    expirationTime = clock + 500, duration = 1800 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("500 s left, panel warns at 120: hidden",
          lua.eval("secureButtons[1] == nil or not secureButtons[1].shown") is True)
    lua.execute("Slash('buffs')")
    lua.globals().warnSlider = find_slider(lua, "as the panel (120 sec)")
    check("the buff's slider starts at the panel's time", lua.eval("warnSlider ~= nil") is True)
    lua.execute("warnSlider.scripts.OnValueChanged(warnSlider, 9)")   # step 9: 600 seconds
    check("its own time is saved", lua.eval("SimpleBuffTrackerDB.buffs[1].warnSeconds") == 600)
    check("500 s left, the buff warns at 600: shown", lua.eval("secureButtons[1].shown") is True)
    lua.execute("warnSlider.scripts.OnValueChanged(warnSlider, 1)")
    check("first step: as the panel again", lua.eval("SimpleBuffTrackerDB.buffs[1].warnSeconds") is None)
    lua.execute("warnSlider.forwardButton.scripts.OnClick(warnSlider.forwardButton)")
    check("the right arrow moves one step", lua.eval("SimpleBuffTrackerDB.buffs[1].warnSeconds") == 0)
    lua.execute("warnSlider.backButton.scripts.OnClick(warnSlider.backButton)")
    check("the left arrow moves back", lua.eval("SimpleBuffTrackerDB.buffs[1].warnSeconds") is None)
    lua.execute("warnSlider.backButton.scripts.OnClick(warnSlider.backButton)")
    check("no step before the first", lua.eval("SimpleBuffTrackerDB.buffs[1].warnSeconds") is None)

    lua.execute("Slash('config')")
    lua.globals().sizeSlider = find_slider(lua, "36")
    lua.execute("sizeSlider.scripts.OnValueChanged(sizeSlider, 13)")   # 16, 18, ... step 13: 40
    check("the Panel tab's icon size slider", lua.eval("SimpleBuffTrackerDB.settings.iconSize") == 40)

    lua.execute("""
        for _, frame in ipairs(allFrames) do
            local label = rawget(frame, 'label')
            if label and label.text == 'Lock the panel' then lockBox = frame end
        end
    """)
    check("the lock checkbox is checked while the panel is locked", lua.eval("lockBox.checked") is True)
    lua.execute("lockBox.checked = false; lockBox.scripts.OnClick(lockBox)")
    check("unchecking it unlocks the panel", lua.eval("SimpleBuffTrackerDB.settings.locked") is False)
    lua.execute("lockBox.checked = true; lockBox.scripts.OnClick(lockBox)")
    check("checking it locks the panel", lua.eval("SimpleBuffTrackerDB.settings.locked") is True)


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
    check("no field in focus: a new buff", lua.eval("#SimpleBuffTrackerDB.buffs") == 1
          and lua.eval("SimpleBuffTrackerDB.buffs[1].target.name") == "Arcane Intellect")
    lua.execute("ShiftClickBuff(7)")
    check("the same buff again: no copy", lua.eval("#SimpleBuffTrackerDB.buffs") == 1)

    lua.execute("FocusField('aura'); ShiftClickBuff(8)")
    check("field in focus: the buff goes into it",
          lua.eval("SimpleBuffTrackerDB.buffs[1].target.name") == "Well Fed" and lua.eval("keyboardFocus") is None)
    lua.execute("FocusField('icon'); ShiftClickBuff(7)")
    check("the icon field takes the spell id", lua.eval("SimpleBuffTrackerDB.buffs[1].iconText") == "1459")
    lua.execute("ShiftClickBuff(9)")
    check("a secret aura is skipped", lua.eval("#SimpleBuffTrackerDB.buffs") == 1)


OIL_LINK = "|cff1eff00|Hitem:20749::::|h[Brilliant Wizard Oil]|h|r"
SPELL_LINK = "|cff71d5ff|Hspell:1459:0|h[Arcane Intellect]|h|r"


def test_item_link():
    lua = new_runtime()
    lua.execute("Slash('add mainhand = item 2683'); Slash('buffs'); FocusField('sourceValue')")
    lua.execute("ChatFrameUtil.InsertLink(...)", SPELL_LINK)
    check("a spell link is not taken by the item field",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 2683)
    lua.execute("ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("a shift-clicked item goes into the item field",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 20749 and lua.eval("keyboardFocus") is None)
    check("the oil goes on the main hand",
          lua.eval("secureButtons[1].attributes.macrotext") == "/use item:20749\n/use 16")

    lua.execute("FocusField('icon')")
    lua.execute("ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("the icon field takes an item too", lua.eval("SimpleBuffTrackerDB.buffs[1].icon") == 133000 + 20749)

    lua.execute("Slash('add Fake Buff = spell')")
    lua.execute("local row = Rows()[2]; row.scripts.OnClick(row); FocusField('aura')")
    lua.execute("ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("an item link is not taken by the buff field",
          lua.eval("SimpleBuffTrackerDB.buffs[2].target.name") == "Fake Buff")
    lua.execute("ChatFrameUtil.InsertLink(...)", SPELL_LINK)
    check("a spellbook link goes into the buff field", lua.eval("SimpleBuffTrackerDB.buffs[2].target.spellId") == 1459)
    lua.execute("keyboardFocus = nil")
    lua.execute("ChatFrameUtil.InsertLink(...)", OIL_LINK)
    check("no field in focus: links go to the chat as usual", lua.eval("#SimpleBuffTrackerDB.buffs") == 2)


def test_icons():
    lua = new_runtime()
    lua.execute("Slash('add Well Fed')")
    check("a typed buff the client does not know: question mark",
          lua.eval("ns.Services.Buff.Icon(SimpleBuffTrackerDB.buffs[1])") == 134400)
    lua.execute("""
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = clock + 900, duration = 900 } }
        Fire('UNIT_AURA', 'player')
        auras = {}
        Fire('UNIT_AURA', 'player')
    """)
    check("seen once on the player: its picture is kept",
          lua.eval("ns.Services.Buff.Icon(SimpleBuffTrackerDB.buffs[1])") == 136000
          and lua.eval("SimpleBuffTrackerDB.buffs[1].target.spellId") == 19705)
    lua.execute("""
        auras = { { spellId = 23697, name = 'Mana Regeneration', icon = 137000, expirationTime = 0, duration = 0 } }
        Fire('UNIT_AURA', 'player')
        Slash('add Mana Regeneration')
    """)
    check("typed while the buff is on: picture right away",
          lua.eval("ns.Services.Buff.Icon(SimpleBuffTrackerDB.buffs[2])") == 137000)


def test_learned_icon_redraws_window():
    lua = new_runtime()
    lua.execute("Slash('add Well Fed'); Slash('buffs')")
    check("before: question mark in the list", lua.eval("Rows()[1].icon.texture") == 134400)
    lua.execute("""
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = clock + 900, duration = 900 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("a learned picture redraws the window", lua.eval("Rows()[1].icon.texture") == 136000)


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


def labels(lua, query, sources="ALL"):
    found = lua.eval("ns.Dataflows.IconSearch.Search(..., ns.Dataflows.IconSearch.SOURCES.%s)" % sources, query)
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
    check("the item field searches only the bags", labels(lua, "arcane", "ITEMS") == [])
    check("the buff field does not search the bags", labels(lua, "crab", "BUFFS") == [])
    check("names starting with the query come first", labels(lua, "ar")[0] == "Arcane Intellect"
          and "Frost Armor" in labels(lua, "ar"))
    check("one letter: no search", labels(lua, "a") == [])
    check("a number is an id, not a search", labels(lua, "1459") == [])
    lua.execute("C_Container.GetContainerNumSlots = function() error('broken bags') end")
    check("a failing source does not stop the others", labels(lua, "arcane") == ["Arcane Intellect"])
    check("picture ids are read back", lua.eval("ns.Dataflows.BuffParser.ParseIcon('icon:136001')") == 136001
          and lua.eval("ns.Dataflows.BuffParser.ParseIcon('item:2683')") == 133000 + 2683)


def test_suggestions():
    lua = new_runtime()
    lua.execute("Slash('add Well Fed = item 2683'); Slash('buffs')")
    lua.execute("TypeInto(FindField('icon'), 'arc')")
    check("typing shows suggestions", len(lua.eval("ShownSuggestions()")) == 1
          and lua.eval("ShownSuggestions()[1].label.text") == "Arcane Intellect")
    lua.execute("local row = ShownSuggestions()[1]; row.scripts.OnClick(row)")
    check("a click saves the suggestion", lua.eval("SimpleBuffTrackerDB.buffs[1].iconText") == "1459"
          and lua.eval("SimpleBuffTrackerDB.buffs[1].icon") == 135932)
    check("and hides the list", len(lua.eval("ShownSuggestions()")) == 0)

    lua.execute("TypeInto(FindField('sourceValue'), 'cra')")
    check("the item field suggests bag items", lua.eval("ShownSuggestions()[1].label.text") == "Crab Cake")
    lua.execute("""
        local input = FindField('sourceValue')
        input.scripts.OnArrowPressed(input, 'DOWN')
        input.scripts.OnEnterPressed(input)
    """)
    check("Down + Enter takes the highlighted row",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 2683
          and len(lua.eval("ShownSuggestions()")) == 0)

    lua.execute("TypeInto(FindField('aura'), 'zzz')")
    check("nothing found: no list", len(lua.eval("ShownSuggestions()")) == 0)


def test_drag_and_previews():
    lua = new_runtime()
    lua.execute("""
        cursor = nil
        function GetCursorInfo() if cursor then return unpack(cursor) end end
        function ClearCursor() cursor = nil end
        function GameTooltip:SetItemByID(itemId) tooltipItem = itemId end
        function GameTooltip:SetSpellByID(spellId) tooltipSpell = spellId end
        Slash('add Arcane Intellect = item 2683')
        Slash('buffs')
    """)
    check("a note under the icon field says what it takes",
          lua.eval("FindField('icon').note.text").startswith("Empty: the buff's own picture")
          and lua.eval("FindField('icon').note.shown") is True)
    lua.execute("Enter('sourceValue', '')")
    check("the note under the item field says drag or shift-click",
          lua.eval("FindField('sourceValue').note.text").startswith("Drag an item from the bags here"))
    lua.execute("ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'spell'); Window().Refresh()")
    check("with a spell source the note talks of spells",
          lua.eval("FindField('sourceValue').note.text").startswith("Drag a spell from the spellbook"))
    lua.execute("ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'none'); Window().Refresh()")
    check("no source: no field and no note", lua.eval("FindField('sourceValue') == nil") is True)
    lua.execute("ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'item'); Window().Refresh()")

    # a spell dragged onto the item field: not taken, still on the cursor
    lua.execute("""
        cursor = { 'spell', 3, 'spell', 1459 }
        local input = FindField('sourceValue')
        input.scripts.OnReceiveDrag(input)
    """)
    check("a spell is not dropped into the item field",
          lua.eval("cursor ~= nil") is True and lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") is None)
    lua.execute("""
        cursor = { 'item', 20749, '|cff1eff00|Hitem:20749::::|h[Brilliant Wizard Oil]|h|r' }
        local input = FindField('sourceValue')
        input.scripts.OnReceiveDrag(input)
    """)
    check("an item dragged from the bags goes into the item field",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 20749 and lua.eval("cursor") is None)
    lua.execute("""
        cursor = { 'item', 2683, '|cffffffff|Hitem:2683::::|h[Crab Cake]|h|r' }
        local input = FindField('sourceValue')
        input.scripts.OnMouseDown(input)
    """)
    check("a click with an item on the cursor drops it too",
          lua.eval("SimpleBuffTrackerDB.buffs[1].source.itemId") == 2683)

    lua.execute("""
        cursor = { 'spell', 3, 'spell', 1459 }
        local input = FindField('aura')
        input.scripts.OnReceiveDrag(input)
    """)
    check("a spell dragged from the spellbook goes into the buff field",
          lua.eval("SimpleBuffTrackerDB.buffs[1].target.spellId") == 1459)

    preview = "FindField('sourceValue').preview"
    check("the item's picture stands right of the item field",
          lua.eval(preview + ".texture.texture") == 133000 + 2683 and lua.eval(preview + ".shown") is True)
    lua.execute("local preview = %s; preview.scripts.OnEnter(preview)" % preview)
    check("hovering it shows the item's tooltip", lua.eval("tooltipItem") == 2683)
    lua.execute("local preview = FindField('aura').preview; preview.scripts.OnEnter(preview)")
    check("hovering the buff's picture shows the spell's tooltip", lua.eval("tooltipSpell") == 1459)


def test_editor_fits():
    lua = new_runtime()
    lua.execute("Slash('buffs')")
    form_height = lua.eval("FindFrames('formHeight')[1].formHeight")
    button_row = lua.eval("FindFrames('formHeight')[1].buttonRowHeight")
    content_height = lua.eval("ns.Components.MainWindow.CONTENT_HEIGHT")
    check("the editor's fields and buttons fit in the window (%d + %d <= %d)"
          % (form_height, button_row, content_height), form_height + button_row <= content_height)


def test_action_bar_look():
    lua = new_runtime()
    lua.execute("Slash('add Arcane Intellect = spell')")
    found = lua.eval("""(function()
        for _, frame in ipairs(allFrames) do
            if rawget(frame, 'parent') == secureButtons[1] and frame.template == 'ActionButtonTemplate' then
                return true
            end
        end
        return false
    end)()""")
    check("the icon is the action bar template inside the secure button", found is True)


def test_russian():
    lua = new_runtime("ruRU")
    lua.execute("Slash('list')")
    check("russian texts load", "бафов пока нет" in last_chat(lua))


def main():
    test_buffs()
    test_minimap()
    test_window_editing()
    test_warn_seconds()
    test_shift_click()
    test_item_link()
    test_icons()
    test_learned_icon_redraws_window()
    test_debug()
    test_icon_search()
    test_suggestions()
    test_drag_and_previews()
    test_editor_fits()
    test_action_bar_look()
    test_russian()
    if failures:
        print("\n%d failed" % len(failures))
        sys.exit(1)
    print("\nall passed")


if __name__ == "__main__":
    main()
