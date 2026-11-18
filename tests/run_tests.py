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
function Frame:SetPoint(...)
    self.point = { ... }
    self.points = rawget(self, "points") or {}
    self.points[(...)] = { ... }
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:GetPoint() return "TOPLEFT", nil, "TOPLEFT", 10, -20 end
function Frame:GetFrameLevel() return 1 end
function Frame:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
function Frame:SetText(text) self.text = text end
function Frame:SetFontObject(font) self.fontObject = font end
function Frame:SetFrameStrata(strata) self.strata = strata end
function Frame:SetTexture(texture) self.texture = texture end
function Frame:SetDesaturated(value) self.desaturated = value end
function Frame:SetAlpha(value) self.alpha = value end
function Frame:SetCooldown(start, duration) self.cooldown = { start, duration } end
function Frame:Clear() self.cooldown = nil end
-- every texture made, to look for pictures in the tests
allTextures = {}
function Frame:CreateTexture()
    local texture = NewFrame()
    table.insert(allTextures, texture)
    return texture
end
function Frame:CreateFontString()
    local fontString = NewFrame()
    table.insert(allFrames, fontString)
    return fontString
end
function Frame:GetCountdownFontString() return NewFrame() end
function Frame:GetText() return self.text end
function Frame:GetWidth() return 300 end
function Frame:IsMouseOver() return rawget(self, "mouseOver") == true end
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
        frame.Border = NewFrame()
        local normalTexture = NewFrame()
        frame.normalTexture = normalTexture
        function frame:GetNormalTexture() return normalTexture end
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
-- the weapon tooltips: weaponTooltips[inventory slot] = { { text, r, g, b }, ... }
weaponTooltips = {}
ITEM_SPELL_TRIGGER_ONUSE = "Use:"
ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
-- the client formats of the enchant lines (GlobalStrings)
ITEM_ENCHANT_TIME_LEFT_HOURS = "%s (%d |4hour:hrs;)"
ITEM_ENCHANT_TIME_LEFT_MIN = "%s (%d min)"
ITEM_ENCHANT_TIME_LEFT_SEC = "%s (%d sec)"
local function Color(r, g, b) return { GetRGB = function() return r, g, b end } end
C_TooltipInfo = { GetInventoryItem = function(unit, slot)
    local lines = {}
    for _, line in ipairs(weaponTooltips[slot] or {}) do
        table.insert(lines, { leftText = line[1], leftColor = Color(line[2], line[3], line[4]) })
    end
    return { lines = lines }
end }

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

-- the game's settings: registered pages are kept to look at
settingsCategories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local category = { frame = frame, name = name, subcategories = {} }
        table.insert(settingsCategories, category)
        return category
    end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        local category = { frame = frame, name = name }
        table.insert(parent.subcategories, category)
        return category
    end,
    RegisterAddOnCategory = function(category) category.isAddOn = true end,
}
SettingsPanel = NewFrame()
SettingsPanel.shown = false
function SettingsPanel:Close() self.shown = false end
-- the AddOns folder: [folder] = "loaded" | "disabled"; missing ones are not there
installedAddons = { SimpleBuffTracker = "loaded", PurpleNote = "loaded", PRR = "disabled" }
C_AddOns = {
    IsAddOnLoaded = function(folder) return installedAddons[folder] == "loaded" end,
    DoesAddOnExist = function(folder) return installedAddons[folder] ~= nil end,
    GetAddOnMetadata = function(addon, field) if field == "Version" then return "1.0.1" end end,
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
    check("add a spell buff with its own spell", "Now tracking: Arcane Intellect" in last_chat(lua))
    lua.execute("Slash('add Well Fed = item Crab Cake')")
    check("add food by item name", "Crab Cake" in last_chat(lua))
    lua.execute("Slash('add mainhand = item |cff1eff00|Hitem:20749::::|h[Brilliant Wizard Oil]|h|r')")
    check("add a weapon oil by link", "Brilliant Wizard Oil" in last_chat(lua))
    lua.execute("Slash('add Trueshot Aura')")
    check("add a buff that is only tracked", last_chat(lua).endswith("Now tracking: Trueshot Aura."))
    lua.execute("Slash('add |cffffffff|Hitem:2683::::|h[Crab Cake]|h|r')")
    check("an item is not a buff", "not an item" in lua.eval("chat[#chat - 1]"))
    lua.execute("Slash('add Well Fed = eat it')")
    check("a source needs spell or item", "type spell or item" in lua.eval("chat[#chat - 1]"))
    lua.execute("Slash('add Well Fed = item Unknown Thing')")
    check("an unknown item is refused", "Item not found" in lua.eval("chat[#chat - 1]"))
    check("four buffs in the list", lua.eval("#SimpleBuffTrackerDB.buffs") == 4)

    lua.execute("""
        auras = { { spellId = 1459, name = "Arcane Intellect", icon = 135932,
                    expirationTime = clock + 1800, duration = 1800 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("all mode shows every buff", shown_buttons(lua) == 4)
    check("spell button casts the spell",
          lua.eval("secureButtons[1].attributes.type1") == "spell"
          and lua.eval("secureButtons[1].attributes.spell") == "Arcane Intellect")
    check("food button uses the item", lua.eval("secureButtons[2].attributes.item") == "item:2683")
    check("oil button puts the oil on the main hand",
          lua.eval("secureButtons[3].attributes.macrotext") == "/use item:20749\n/use 16")
    check("tracked-only button has no action", lua.eval("secureButtons[4].attributes.type1") is None)
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
    check("mode does not change in combat", "while in combat" in last_chat(lua))

    lua.execute("""
        inCombat = false
        aurasHidden = false
        auras = {}
        Fire('PLAYER_REGEN_ENABLED')
    """)
    check("after combat the missing buffs are laid out", shown_buttons(lua) == 3)

    lua.execute("Slash('remove 2')")
    check("remove by number", "No longer tracking: Well Fed" in last_chat(lua))
    lua.execute("Slash('remove 9')")
    check("remove a number that is not there", "No buff with that number" in last_chat(lua))
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
    check("right click unlocks the panel", lua.eval("SimpleBuffTrackerDB.settings.locked") is False)
    lua.execute("launcher.OnClick(nil, 'RightButton')")
    check("a second right click locks it", lua.eval("SimpleBuffTrackerDB.settings.locked") is True)
    lua.execute("shiftDown = true; launcher.OnClick(nil, 'RightButton'); shiftDown = false")
    check("shift + right click switches the mode", lua.eval("SimpleBuffTrackerDB.settings.mode") == "missing")
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

    click_button(lua, "Add Buff")
    check("Add buff makes an empty buff and shows it",
          lua.eval("#SimpleBuffTrackerDB.buffs") == 1 and lua.eval("FindField('aura') ~= nil") is True)
    check("the list shows it as New buff", lua.eval("Rows()[1].label.text") == "New Buff")

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

    click_button(lua, "Add Buff")
    lua.execute("Enter('aura', 'Well Fed')")
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
    lua.globals().warnSlider = find_slider(lua, "Panel default (120 sec)")
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
    lua.execute("sizeSlider.scripts.OnValueChanged(sizeSlider, 13)")   # 16, 17, ... step 13: 28
    check("the Panel tab's icon size slider goes by 1", lua.eval("SimpleBuffTrackerDB.settings.iconSize") == 28)

    lua.execute("""
        for _, frame in ipairs(allFrames) do
            local label = rawget(frame, 'label')
            if label and label.text == 'Lock Panel' then lockBox = frame end
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
    lua.execute("""
        weaponTooltips[16] = { { 'Arcanite Reaper', 1, 1, 1 },
                               { 'Flametongue 3 (5 min)', 0, 1, 0 },
                               { 'Brilliant Wizard Oil (30 min)', 0, 1, 0 } }
        weaponEnchant = { true, 1800000, 0, 2628, false, 0, 0, 0 }
        chat = {}
        Slash('debug')
    """)
    text = "\n".join(lua.eval("chat")[i] for i in range(1, int(lua.eval("#chat")) + 1))
    check("debug shows every enchant line of the weapon tooltip",
          "mainhand tooltip enchant: Flametongue 3 300s" in text
          and "mainhand tooltip enchant: Brilliant Wizard Oil 1800s" in text)
    check("debug shows the remembered enchants", "seen enchant 2628 = " in text)


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


def test_seen_buffs():
    lua = new_runtime()
    lua.execute("""
        auras = { { spellId = 19705, name = 'Well Fed', icon = 136000, expirationTime = clock + 900, duration = 900 } }
        Fire('UNIT_AURA', 'player')
        auras = {}
        Fire('UNIT_AURA', 'player')
    """)
    check("a buff seen once is remembered", lua.eval("SimpleBuffTrackerDB.seenAuras['well fed'].spellId") == 19705)
    check("the buff field finds it when it is gone", labels(lua, "well", "BUFFS") == ["Well Fed"])
    check("the icon field too", labels(lua, "well") == ["Well Fed"])
    check("the item field does not", labels(lua, "well", "ITEMS") == [])
    lua.execute("Slash('add Well Fed')")
    check("typing its name gives its id and picture right away",
          lua.eval("SimpleBuffTrackerDB.buffs[1].target.spellId") == 19705
          and lua.eval("ns.Services.Buff.Icon(SimpleBuffTrackerDB.buffs[1])") == 136000)
    lua.execute("""
        Slash('buffs')
        TypeInto(FindField('aura'), 'fed')
    """)
    check("the buff field drops it in its list", lua.eval("ShownSuggestions()[1].label.text") == "Well Fed")
    lua.execute("""
        auras = { { spellId = SECRET, name = 'Hidden Thing', icon = 1, expirationTime = 0, duration = 0 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("a buff without a plain id is remembered by name",
          lua.eval("SimpleBuffTrackerDB.seenAuras['hidden thing'].spellId") is None)


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
          lua.eval("FindField('icon').note.text").startswith("Leave empty to use the buff's own icon")
          and lua.eval("FindField('icon').note.shown") is True)
    lua.execute("Enter('sourceValue', '')")
    check("the note under the item field says drag or shift-click",
          lua.eval("FindField('sourceValue').note.text").startswith("Drag an item here from your bags"))
    lua.execute("ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'spell'); Window().Refresh()")
    check("with a spell source the note talks of spells",
          lua.eval("FindField('sourceValue').note.text").startswith("Drag a spell here from your spellbook"))
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


def icon_field_top(lua):
    return lua.eval("FindField('icon').points.TOPLEFT[5]")


def names(lua):
    count = int(lua.eval("#SimpleBuffTrackerDB.buffs"))
    return [lua.eval("SimpleBuffTrackerDB.buffs[%d].target.name" % i) for i in range(1, count + 1)]


def icon_place(lua, index):
    point = lua.eval("secureButtons[%d].point" % index)
    return (point[1], point[4], point[5])


def test_grow_direction():
    lua = new_runtime()
    lua.execute("""
        -- the panel stands with its left edge at 100, right 300, top 500, bottom 400
        local panel = SimpleBuffTrackerPanel
        function panel:GetLeft() return 100 end
        function panel:GetRight() return 300 end
        function panel:GetTop() return 500 end
        function panel:GetBottom() return 400 end
        Slash('size 36')
        Slash('row 2')
        Slash('add Arcane Intellect')
        Slash('add Well Fed')
        Slash('add Trueshot Aura')
    """)
    # icon 36 + spacing 4 = a step of 40; two in a line
    check("right: the old centered place is moved to the middle of the left edge",
          lua.eval("SimpleBuffTrackerDB.settings.position.point") == "LEFT"
          and lua.eval("SimpleBuffTrackerDB.settings.position.x") == 100
          and lua.eval("SimpleBuffTrackerDB.settings.position.y") == 450)
    check("right: second icon right of the first, third on the next row",
          icon_place(lua, 2) == ("TOPLEFT", 40, 0) and icon_place(lua, 3) == ("TOPLEFT", 0, -40))

    lua.execute("SimpleBuffTrackerDB.settings.growDirection = 'left'; ns.Components.BuffPanel.Refresh()")
    check("left: held by the middle of the right edge",
          lua.eval("SimpleBuffTrackerDB.settings.position.point") == "RIGHT"
          and lua.eval("SimpleBuffTrackerDB.settings.position.x") == 300)
    check("left: second icon left of the first",
          icon_place(lua, 2) == ("TOPRIGHT", -40, 0) and icon_place(lua, 3) == ("TOPRIGHT", 0, -40))

    lua.execute("SimpleBuffTrackerDB.settings.growDirection = 'down'; ns.Components.BuffPanel.Refresh()")
    check("down: second icon under the first, third in the next column",
          icon_place(lua, 2) == ("TOPLEFT", 0, -40) and icon_place(lua, 3) == ("TOPLEFT", 40, 0))

    lua.execute("SimpleBuffTrackerDB.settings.growDirection = 'up'; ns.Components.BuffPanel.Refresh()")
    check("up: held by the middle of the bottom edge",
          lua.eval("SimpleBuffTrackerDB.settings.position.point") == "BOTTOM"
          and lua.eval("SimpleBuffTrackerDB.settings.position.y") == 400)
    check("up: second icon above the first",
          icon_place(lua, 2) == ("BOTTOMLEFT", 0, 40) and icon_place(lua, 3) == ("BOTTOMLEFT", 40, 0))

    lua.execute("""
        Slash('config')
        for _, frame in ipairs(allFrames) do
            if frame.text == 'Growth Direction' then growLabel = frame end
        end
    """)
    check("the Panel tab has the grow select", lua.eval("growLabel ~= nil") is True)


def test_weapon_enchants():
    lua = new_runtime()
    lua.execute("""
        -- oil on the main hand: the enchant line of its tooltip, among the weapon's own lines
        weaponTooltips[16] = { { 'Arcanite Reaper', 1, 1, 1 },
                               { 'Use: Something (5 Min Cooldown)', 0, 1, 0 },
                               { 'Brilliant Wizard Oil (30 min)', 0, 1, 0 } }
        weaponEnchant = { true, 1800000, 0, 2628, false, 0, 0, 0 }
        Slash('add mainhand = item 20749')
        Slash('add mainhand = spell Flametongue Weapon')
        RunTickers()
    """)
    check("the enchant's name is read from the weapon tooltip",
          lua.eval("SimpleBuffTrackerDB.seenEnchants[2628]") == "Brilliant Wizard Oil"
          and lua.eval("SimpleBuffTrackerDB.seenEnchantNames['Brilliant Wizard Oil']") is True)
    check("with no enchant chosen any enchant counts", lua.eval("secureButtons[1].state.isActive") is True
          and lua.eval("secureButtons[2].state.isActive") is True)

    lua.execute("""
        weaponTooltips[16] = { { 'Flametongue 3 (5 min)', 0, 1, 0 } }
        weaponEnchant = { true, 300000, 0, 5, false, 0, 0, 0 }
        RunTickers()
        ns.Services.Buff.SetEnchant(SimpleBuffTrackerDB.buffs[1], 'Brilliant Wizard Oil')
        ns.Services.Buff.SetEnchant(SimpleBuffTrackerDB.buffs[2], 'Flametongue 3')
        RunTickers()
    """)
    check("Flametongue on: the Flametongue buff is on, the oil buff missing",
          lua.eval("secureButtons[2].state.isActive") is True and lua.eval("secureButtons[1].state.isActive") is False)
    check("the buff is named after its enchant",
          lua.eval("ns.Models.Buff.TargetLabel(SimpleBuffTrackerDB.buffs[2])") == "Main Hand Enchant: Flametongue 3")

    lua.execute("""
        weaponTooltips[16] = { { 'Sharpened (2 hrs)', 0, 1, 0 } }
        weaponEnchant = { true, 7200000, 0, 777, false, 0, 0, 0 }
        RunTickers()
    """)
    check("hours are read with the client's grammar token",
          lua.eval("SimpleBuffTrackerDB.seenEnchants[777]") == "Sharpened")

    lua.execute("""
        inCombat = true
        weaponTooltips[16] = { { 'Something Else (30 min)', 0, 1, 0 } }
        weaponEnchant = { true, 1800000, 0, 888, false, 0, 0, 0 }
        RunTickers()
        inCombat = false
    """)
    check("in combat the tooltip is not read", lua.eval("SimpleBuffTrackerDB.seenEnchants[888]") is None)

    # the editor: the enchant select for weapon buffs only, by name
    lua.execute("Slash('buffs')")
    lua.execute("""
        for _, frame in ipairs(allFrames) do
            if rawget(frame, 'label') and rawget(frame, 'group') and frame.label.text == 'Enchant' then
                enchantSelect = frame
            end
        end
    """)
    check("a weapon buff shows the enchant select", lua.eval("enchantSelect.shown") is True)
    check("the select offers the names seen",
          lua.eval("ns.Dataflows.WeaponEnchant.SeenNames()[1]") == "Brilliant Wizard Oil")
    lua.execute("Slash('add Arcane Intellect'); Rows()[3].scripts.OnClick(Rows()[3])")
    check("an aura hides it", lua.eval("enchantSelect.shown") is False)


def test_oil_with_flametongue():
    # what the game showed: oil and Flametongue on one weapon at once, the API gives only Flametongue
    lua = new_runtime()
    lua.execute("""
        -- remembered wrong by the older version: Flametongue's id under the oil's name
        SimpleBuffTrackerDB.seenEnchants[1665] = 'Lesser Wizard Oil'
        SimpleBuffTrackerDB.seenEnchants[2626] = 'Lesser Wizard Oil'
        Slash('add mainhand = spell Flametongue Weapon')
        Slash('add mainhand = item 20746')
        -- buffs chosen by id by the older version
        SimpleBuffTrackerDB.buffs[1].target.enchantId = 1665
        SimpleBuffTrackerDB.buffs[1].target.enchantName = 'Lesser Wizard Oil'
        SimpleBuffTrackerDB.buffs[2].target.enchantId = 2626
        SimpleBuffTrackerDB.buffs[2].target.enchantName = 'Lesser Wizard Oil'

        weaponTooltips[16] = { { 'Enchanted: Revelation', 0, 1, 0 },
                               { 'Lesser Wizard Oil (30 min)', 0, 1, 0 },
                               { 'Flametongue 5 (60 min)', 0, 1, 0 } }
        weaponEnchant = { true, 3569000, 0, 1665, false, 0, 0, 0 }
        RunTickers()
    """)
    check("the API's id goes to the line with the same time: 1665 is Flametongue",
          lua.eval("SimpleBuffTrackerDB.seenEnchants[1665]") == "Flametongue 5")
    check("both on: the Flametongue buff is on", lua.eval("secureButtons[1].state.isActive") is True)
    check("both on: the oil buff is on too, though the API gives only Flametongue",
          lua.eval("secureButtons[2].state.isActive") is True)
    check("the old buff is named right now",
          lua.eval("ns.Models.Buff.TargetLabel(SimpleBuffTrackerDB.buffs[1])") == "Main Hand Enchant: Flametongue 5")

    lua.execute("""
        -- Flametongue cancelled: only the oil, the API gives the oil now
        weaponTooltips[16] = { { 'Enchanted: Revelation', 0, 1, 0 },
                               { 'Lesser Wizard Oil (29 min)', 0, 1, 0 } }
        weaponEnchant = { true, 1731000, 0, 2626, false, 0, 0, 0 }
        RunTickers()
    """)
    check("Flametongue cancelled: its buff is missing", lua.eval("secureButtons[1].state.isActive") is False)
    check("the oil buff stays on", lua.eval("secureButtons[2].state.isActive") is True)

    lua.execute("""
        -- in combat the tooltip is not read: the last lines run out by the clock
        inCombat = true
        aurasHidden = true
        weaponTooltips[16] = {}
        RunTickers()
    """)
    check("in combat the oil still counts from the last reading", lua.eval("secureButtons[2].state.isActive") is True)


def test_drag_order():
    lua = new_runtime()
    lua.execute("""
        Slash('add Arcane Intellect')
        Slash('add Well Fed')
        Slash('add Trueshot Aura')
        Slash('buffs')
        function DragRow(from, to)
            local rows = Rows()
            local row = rows[from]
            row.scripts.OnDragStart(row)
            rows[to].mouseOver = true
            frameUpdate = row
            row.scripts.OnDragStop(row)
            rows[to].mouseOver = false
        end
    """)
    lua.execute("DragRow(1, 3)")
    check("a row dragged down goes under the others",
          names(lua) == ["Well Fed", "Trueshot Aura", "Arcane Intellect"])
    check("the list and the panel follow", lua.eval("Rows()[3].label.text") == "Arcane Intellect"
          and lua.eval("secureButtons[3].state.buff.target.name") == "Arcane Intellect")
    check("the dragged buff stays chosen", lua.eval("Rows()[3].selection.shown") is True)
    lua.execute("DragRow(3, 1)")
    check("and back to the top", names(lua) == ["Arcane Intellect", "Well Fed", "Trueshot Aura"])
    lua.execute("DragRow(2, 2)")
    check("dropped on its own place: nothing changes", names(lua) == ["Arcane Intellect", "Well Fed", "Trueshot Aura"])


def test_fields_stack():
    lua = new_runtime()
    lua.execute("Slash('add Arcane Intellect = item 2683'); Slash('buffs')")
    with_source = icon_field_top(lua)
    lua.execute("ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'none'); Window().Refresh()")
    without_source = icon_field_top(lua)
    check("no source: the icon field moves up into the room of the item field (%d -> %d)"
          % (with_source, without_source), without_source > with_source)
    lua.execute("ns.Services.Buff.SetTargetKind(SimpleBuffTrackerDB.buffs[1], 'mainhand'); Window().Refresh()")
    weapon = icon_field_top(lua)
    check("a weapon enchant: the enchant select takes the place of the buff field", weapon == without_source
          and lua.eval("FindField('aura') == nil") is True)
    lua.execute("""
        ns.Services.Buff.SetTargetKind(SimpleBuffTrackerDB.buffs[1], 'aura')
        ns.Services.Buff.SetSourceKind(SimpleBuffTrackerDB.buffs[1], 'item')
        Window().Refresh()
    """)
    check("all fields back: the icon field back in its place", icon_field_top(lua) == with_source)


def test_editor_fits():
    lua = new_runtime()
    lua.execute("Slash('buffs')")
    form_height = lua.eval("FindFrames('formHeight')[1].formHeight")
    button_row = lua.eval("FindFrames('formHeight')[1].buttonRowHeight")
    content_height = lua.eval("ns.Components.MainWindow.CONTENT_HEIGHT")
    check("the editor's fields and buttons fit in the window (%d + %d <= %d)"
          % (form_height, button_row, content_height), form_height + button_row <= content_height)
    lua.execute("Slash('config')")
    panel_height = lua.eval("FindFrames('panelFormHeight')[1].panelFormHeight")
    check("the Panel tab fits in the window (%d <= %d)" % (panel_height, content_height),
          panel_height <= content_height)


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

    lua.execute("""
        -- the looks made inside the first button, by their kind
        function Looks()
            local looks = { templates = {}, squares = {} }
            for _, frame in ipairs(allFrames) do
                if rawget(frame, 'parent') == secureButtons[1] then
                    if frame.template == 'ActionButtonTemplate' then
                        table.insert(looks.templates, frame)
                    elseif frame.template == nil and rawget(frame, 'points') == nil then
                        table.insert(looks.squares, frame)
                    end
                end
            end
            return looks
        end
        SimpleBuffTrackerDB.settings.iconTemplate = 'borderless'
        ns.Components.BuffPanel.Refresh()
    """)
    check("borderless: a second template, its frame art invisible",
          lua.eval("#Looks().templates") == 2
          and lua.eval("Looks().templates[2].Border.alpha") == 0
          and lua.eval("Looks().templates[2].normalTexture.alpha") == 0)
    check("borderless: the framed one hidden, the borderless one shown",
          lua.eval("Looks().templates[1].shown") is False and lua.eval("Looks().templates[2].shown") is True)
    check("the framed look keeps its frame", lua.eval("rawget(Looks().templates[1].Border, 'alpha')") is None)
    check("the picture goes to the shown look",
          lua.eval("Looks().templates[2].icon.texture") == 135932)

    lua.execute("SimpleBuffTrackerDB.settings.iconTemplate = 'square'; ns.Components.BuffPanel.Refresh()")
    check("square: both templates hidden", lua.eval("Looks().templates[1].shown") is False
          and lua.eval("Looks().templates[2].shown") is False)
    check("square: its icon has the picture", lua.eval("secureButtons[1].template") == "square")

    lua.execute("SimpleBuffTrackerDB.settings.iconTemplate = 'action_bar'; ns.Components.BuffPanel.Refresh()")
    check("back to the action bar: no new template made, the first shown again",
          lua.eval("#Looks().templates") == 2 and lua.eval("Looks().templates[1].shown") is True)

    lua.execute("Slash('config')")
    lua.execute("""
        inCombat = true
        for _, frame in ipairs(allFrames) do
            if frame.text == 'Icon Style' then lookLabel = frame end
        end
    """)
    check("the Panel tab has the icon look select", lua.eval("lookLabel ~= nil") is True)


def test_shift_drag():
    lua = new_runtime()
    lua.execute("""
        for _, frame in ipairs(allFrames) do
            if rawget(frame, 'parent') == SimpleBuffTrackerPanel and rawget(frame.scripts, 'OnDragStart') then
                mover = frame
            end
        end
        SimpleBuffTrackerPanel.mouseOver = true
        local panel = SimpleBuffTrackerPanel
        function panel:GetLeft() return 300 end
        function panel:GetRight() return 400 end
        function panel:GetTop() return 600 end
        function panel:GetBottom() return 560 end
    """)
    check("locked: no mover", lua.eval("SimpleBuffTrackerDB.settings.locked") is True
          and lua.eval("mover.shown") is False)
    lua.execute("shiftDown = true; Fire('MODIFIER_STATE_CHANGED', 'LSHIFT', 1)")
    check("Shift over the panel brings the mover up", lua.eval("mover.shown") is True)
    lua.execute("mover.scripts.OnDragStart(mover); shiftDown = false; Fire('MODIFIER_STATE_CHANGED', 'LSHIFT', 0)")
    check("the mover stays while dragging", lua.eval("mover.shown") is True)
    lua.execute("mover.scripts.OnDragStop(mover)")
    check("after the drag it goes away and the place is saved", lua.eval("mover.shown") is False
          and lua.eval("SimpleBuffTrackerDB.settings.position.x") == 300)
    lua.execute("""
        SimpleBuffTrackerPanel.mouseOver = false
        shiftDown = true; Fire('MODIFIER_STATE_CHANGED', 'LSHIFT', 1)
    """)
    check("Shift with the mouse elsewhere does nothing", lua.eval("mover.shown") is False)
    lua.execute("""
        SimpleBuffTrackerPanel.mouseOver = true
        inCombat = true; Fire('MODIFIER_STATE_CHANGED', 'LSHIFT', 1)
        inCombat = false; shiftDown = false
    """)
    check("not in combat", lua.eval("mover.shown") is False)
    lua.execute("Slash('unlock'); mover.scripts.OnMouseUp(mover, 'LeftButton')")
    check("unlocked: a left click does not lock", lua.eval("SimpleBuffTrackerDB.settings.locked") is False
          and lua.eval("mover.shown") is True)
    lua.execute("mover.scripts.OnMouseUp(mover, 'RightButton')")
    check("unlocked: a right click locks the panel", lua.eval("SimpleBuffTrackerDB.settings.locked") is True
          and lua.eval("mover.shown") is False)


def test_missing_glow():
    lua = new_runtime()
    lua.execute("""
        Slash('add Arcane Intellect = spell Arcane Intellect')
        RunTickers()
        button = secureButtons[1]
        -- the glow holder: the child of the icon that runs OnUpdate
        for _, frame in ipairs(allFrames) do
            if rawget(frame, 'parent') == button and rawget(frame.scripts, 'OnUpdate') then glowHolder = frame end
        end
    """)
    check("a missing buff has no glow by default", lua.eval("glowHolder.shown") is False)
    for effect in ("pixel", "autocast", "proc", "pulse"):
        lua.execute("SimpleBuffTrackerDB.settings.missingGlow = '%s'; ns.Core.Refresh()" % effect)
        check("the %s glow shows on a missing buff" % effect, lua.eval("glowHolder.shown") is True)
        lua.execute("""
            -- give the effect frames a size: the lines and sparkles are laid out along it
            for _, frame in ipairs(allFrames) do
                if rawget(frame, 'parent') == glowHolder then
                    function frame:GetWidth() return 36 end
                    function frame:GetHeight() return 36 end
                end
            end
            for step = 1, 50 do glowHolder.scripts.OnUpdate(glowHolder, 0.37) end
        """)
    lua.execute("""
        auras = { { spellId = 1459, name = 'Arcane Intellect', icon = 135932,
                    expirationTime = clock + 1500, duration = 1800 } }
        Fire('UNIT_AURA', 'player')
    """)
    check("the buff is back: no glow", lua.eval("glowHolder.shown") is False)
    lua.execute("""
        auras = {}
        inCombat = true
        Fire('UNIT_AURA', 'player')
    """)
    check("in combat the glow still comes up", lua.eval("glowHolder.shown") is True)


def test_panel_stays_on_its_corner():
    lua = new_runtime()
    lua.execute("""
        local panel = SimpleBuffTrackerPanel
        function panel:GetLeft() return 300 end
        function panel:GetRight() return 400 end
        function panel:GetTop() return 600 end
        function panel:GetBottom() return 560 end
        Slash('add Arcane Intellect')
        RunTickers()
        for _, frame in ipairs(allFrames) do
            if rawget(frame, 'parent') == SimpleBuffTrackerPanel and rawget(frame.scripts, 'OnDragStart') then
                mover = frame
            end
        end
        -- what the client did after login: put the panel back by a point of its own
        SimpleBuffTrackerPanel:ClearAllPoints()
        SimpleBuffTrackerPanel:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
        ns.Core.Refresh()
    """)
    check("growing right, the panel is put back on the middle of its left edge",
          lua.eval("SimpleBuffTrackerPanel.point[1]") == "LEFT"
          and lua.eval("SimpleBuffTrackerPanel.point[3]") == "BOTTOMLEFT")
    lua.execute("""
        local panel = SimpleBuffTrackerPanel
        function panel:GetLeft() return 300 end
        function panel:GetRight() return 400 end
        function panel:GetTop() return 600 end
        function panel:GetBottom() return 560 end
        Slash('unlock')
        for _, direction in ipairs({ 'left', 'down', 'up', 'right' }) do
            SimpleBuffTrackerDB.settings.growDirection = direction
            ns.Core.Refresh()
        end
        SimpleBuffTrackerDB.settings.growDirection = 'left'
        ns.Core.Refresh()
    """)
    lua.execute("""
        Slash('unlock')
        mover.scripts.OnDragStart(mover)
        -- the mouse moved the panel: the client holds it somewhere else now
        SimpleBuffTrackerPanel:ClearAllPoints()
        SimpleBuffTrackerPanel:SetPoint('CENTER', UIParent, 'CENTER', 50, 50)
        RunTickers()
        Fire('UNIT_AURA', 'player')
    """)
    check("while dragged the panel is not put back (it jumped)",
          lua.eval("SimpleBuffTrackerPanel.point[1]") == "CENTER")
    lua.execute("mover.scripts.OnDragStop(mover)")
    check("the drag ends: held by its anchor again", lua.eval("SimpleBuffTrackerPanel.point[1]") == "RIGHT")
    check("growing left, it is held by the middle of its right edge",
          lua.eval("SimpleBuffTrackerPanel.point[1]") == "RIGHT"
          and lua.eval("SimpleBuffTrackerDB.settings.position.x") == 400)


def test_right_click_opens_settings():
    lua = new_runtime()
    lua.execute("""
        Slash('add Arcane Intellect = spell Arcane Intellect')
        Slash('add Trueshot Aura')
        RunTickers()
        local button = secureButtons[2]
        button.scripts.OnClick(button, 'RightButton', true)
    """)
    check("pressing the right button does nothing yet", lua.eval("Window().IsOpen()") is False)
    lua.execute("secureButtons[2].scripts.OnClick(secureButtons[2], 'RightButton', false)")
    check("a right click on an icon opens the window", lua.eval("Window().IsOpen()") is True)
    check("on that buff's page", lua.eval("FindField('aura').text") == "Trueshot Aura")
    lua.execute("secureButtons[1].scripts.OnClick(secureButtons[1], 'RightButton', false)")
    check("another icon: the window stays open on its buff", lua.eval("Window().IsOpen()") is True
          and lua.eval("FindField('aura').text") == "Arcane Intellect")
    check("the action is on the left button only", lua.eval("secureButtons[1].attributes.type1") == "spell"
          and lua.eval("secureButtons[1].attributes.type") is None)


def test_settings_pages():
    lua = new_runtime()
    check("one addon category in the game's settings", lua.eval("#settingsCategories") == 1
          and lua.eval("settingsCategories[1].isAddOn") is True
          and lua.eval("settingsCategories[1].name") == "Simple Buff Tracker")
    check("the Other Addons page under it",
          lua.eval("settingsCategories[1].subcategories[1].name") == "Other Addons")
    lua.execute("""
        others = settingsCategories[1].subcategories[1].frame
        others.scripts.OnShow(others)
        states = {}
        for _, card in ipairs(others.cards) do states[#states + 1] = card:Refresh() end
    """)
    check("the page leaves out its own addon: four cards", lua.eval("#others.cards") == 4)
    check("installed, turned off, not installed",
          list(lua.eval("states").values()) == ["loaded", "disabled", "missing", "missing"])
    lua.execute("""
        bulletLines = 0
        for _, frame in ipairs(allFrames) do
            local text = rawget(frame, 'text')
            if type(text) == 'string' and text:find('Share notes with your guild', 1, true) then
                purpleFeatures = text
            end
        end
        -- a card is as tall as its texts: give the font strings a height and fit it
        local card = others.cards[1]
        cardHeight = card:Fit(500)
    """)
    features = lua.eval("purpleFeatures") or ""
    check("the features are points, one per line",
          features.startswith("• Write a note") and features.count("• ") == 6)
    lua.execute("""
        for _, frame in ipairs(allTextures) do
            local texture = rawget(frame, 'texture')
            if type(texture) == 'string' and texture:find('target_it', 1, true) then
                moduleIcon = texture
            end
        end
    """)
    check("a CurseForge icon comes from the module's own folder",
          lua.eval("moduleIcon") == "Interface\\AddOns\\SimpleBuffTracker\\shared\\other_addons\\icons\\target_it")
    lua.execute("""
        local card = others.cards[2]
        card.copyButton.scripts.OnClick(card.copyButton)
        box = card.nameBox
    """)
    check("Copy Name turns the name into a box with the name in it",
          lua.eval("box.shown") is True and lua.eval("box.text") == "PRR: Professions, Recipes, Reagents")
    check("the copy control is an icon", lua.eval("others.cards[2].copyIcon.texture")
          == "Interface\\AddOns\\SimpleBuffTracker\\shared\\other_addons\\icons\\copy")
    lua.execute("box:SetText('PRR: Professions, Recipes, Reagentsx'); box.scripts.OnTextChanged(box, true)")
    check("typing does not change the name", lua.eval("box.text") == "PRR: Professions, Recipes, Reagents")
    lua.execute("box.scripts.OnEscapePressed(box)")
    check("Escape closes the box", lua.eval("box.shown") is False)
    lua.execute("others.cards[2].nameButton.scripts.OnClick(others.cards[2].nameButton)")
    check("a click on the name opens the box too", lua.eval("box.shown") is True)
    lua.execute("box.scripts.OnEscapePressed(box)")
    lua.execute("""
        controlDown = false
        function IsControlKeyDown() return controlDown end
        local card = others.cards[2]
        card.copyButton.scripts.OnClick(card.copyButton)
        box.scripts.OnKeyDown(box, 'C')
    """)
    check("C alone does not close the box", lua.eval("box.shown") is True)
    lua.execute("controlDown = true; box.scripts.OnKeyDown(box, 'C'); controlDown = false")
    check("Ctrl+C copies and closes the box", lua.eval("box.shown") is False)
    check("the copy icon is drawn by the page, not a default button",
          lua.eval("rawget(others.cards[2].copyButton, 'template')") is None)
    check("the module needs none of the addon's texts",
          lua.eval("ns.Localization.Text('other_addons.title')") == "other_addons.title")
    check("a card gets a height from its texts", (lua.eval("cardHeight") or 0) > 0)
    lua.execute("""
        about = settingsCategories[1].frame
        SettingsPanel.shown = true
        about.openButton.scripts.OnClick(about.openButton)
    """)
    check("the big button closes the game's settings and opens the addon window",
          lua.eval("SettingsPanel.shown") is False and lua.eval("Window().IsOpen()") is True)
    lua.execute("about.openButton.scripts.OnClick(about.openButton)")
    check("pressed again, the window stays open", lua.eval("Window().IsOpen()") is True)


def test_other_addons_languages():
    lua = new_runtime()
    lua.execute("""
        others = settingsCategories[1].subcategories[1].frame
        function HasText(wanted)
            for _, frame in ipairs(allFrames) do
                if rawget(frame, 'text') == wanted then return true end
            end
            return false
        end
    """)
    check("the page starts in the client's language", lua.eval("others:GetLanguage()") == "en")
    lua.execute("others:SetLanguage('de')")
    check("choosing German changes the texts at once",
          lua.eval("HasText('Weitere Addons')") is True
)
    check("the choice is kept in the table the addon gave",
          lua.eval("SimpleBuffTrackerDB.otherAddons.language") == "de")
    lua.execute("others:SetLanguage('zh')")
    check("Chinese is not offered on a client without Chinese letters", lua.eval("others:GetLanguage()") == "de")

    # every language has every text, and as many points as English
    lua.execute("""
        problems = {}
        local english = ns.OtherAddons.texts.en
        local function Walk(reference, other, path, language)
            for key, value in pairs(reference) do
                local mine = other and other[key]
                if type(value) == 'table' then
                    if type(mine) ~= 'table' then
                        table.insert(problems, language .. ': no ' .. path .. key)
                    elseif #value > 0 and #mine ~= #value then
                        table.insert(problems, language .. ': ' .. path .. key .. ' has ' .. #mine .. ' points')
                    else
                        Walk(value, mine, path .. key .. '.', language)
                    end
                elseif type(mine) ~= 'string' or mine == '' then
                    table.insert(problems, language .. ': no ' .. path .. key)
                end
            end
        end
        for _, language in ipairs({ 'de', 'fr', 'es', 'it', 'pt', 'ru', 'zh' }) do
            Walk(english, ns.OtherAddons.texts[language], '', language)
        end
        problemText = table.concat(problems, '; ')
    """)
    check("all 8 languages have every text (" + (lua.eval("problemText") or "") + ")",
          lua.eval("#problems") == 0)

    lua = new_runtime("zhCN")
    lua.execute("others = settingsCategories[1].subcategories[1].frame")
    check("a Chinese client starts in Chinese", lua.eval("others:GetLanguage()") == "zh")


def test_russian():
    lua = new_runtime("ruRU")
    lua.execute("Slash('list')")
    check("russian texts load", "Нет отслеживаемых бафов" in last_chat(lua))
    check("the Other Addons page is in Russian on a Russian client",
          lua.eval("settingsCategories[1].subcategories[1].name") == "Другие аддоны")


def test_wording():
    lua = new_runtime()
    lua.execute("Slash('')")
    lua.execute("""
        helpLines = {}
        for _, line in ipairs(chat) do helpLines[#helpLines + 1] = line end
    """)
    lines = list(lua.eval("helpLines").values())
    check("help: a command with arguments has them right after its name",
          any("/sbt add <buff> [= spell|item <source>] - Track a buff." in line for line in lines))
    check("help: a command without arguments gets a dash",
          any("/sbt list - List the tracked buffs." in line for line in lines))
    lua.execute("""
        tooltipLines = {}
        function GameTooltip:AddLine(text) tooltipLines[#tooltipLines + 1] = text end
        Slash('add Arcane Intellect = spell Arcane Intellect')
        Slash('add Well Fed = item 20749')
        RunTickers()
        secureButtons[1].scripts.OnEnter(secureButtons[1])
        secureButtons[2].scripts.OnEnter(secureButtons[2])
        tooltipText = table.concat(tooltipLines, '|')
    """)
    text = lua.eval("tooltipText")
    check("the icon tooltip says Click to cast for a spell", "Click to cast Arcane Intellect" in text)
    check("and Click to use for an item", "Click to use " in text)


def click_checkbox(lua, text, checked):
    lua.execute("""
        local wanted, checked = ...
        for _, frame in ipairs(allFrames) do
            local label = rawget(frame, "label")
            if frame.template == "UICheckButtonTemplate" and label and label.text == wanted then
                frame.checked = checked
                frame.scripts.OnClick(frame)
                return
            end
        end
        error('no checkbox ' .. wanted)
    """, text, checked)


def test_show_conditions():
    lua = new_runtime()
    lua.execute("""
        instanceType = nil
        function IsInInstance() return instanceType ~= nil, instanceType or "none" end
        -- the classic talent tree: name, icon, tier, column, rank, maxRank
        talentTree = { { "Arcane Mind", 135991, 1, 1, 0, 5 }, { "Ice Shards", 135855, 1, 2, 0, 5 } }
        function GetNumTalentTabs() return 1 end
        function GetNumTalents() return #talentTree end
        function GetTalentInfo(tab, index) return unpack(talentTree[index]) end
        knownSpells = {}
        function IsPlayerSpell(spellId) return knownSpells[spellId] == true end
        Slash('add Arcane Intellect = spell')
        Slash('buffs')
    """)
    check("a buff without conditions is shown", shown_buttons(lua) == 1)
    check("the Conditions tab at the top of the editor",
          lua.eval("(function() for _, f in ipairs(allFrames) do if rawget(f, 'text') == 'Conditions' and f.shown then return true end end return false end)()") is True)
    click_button(lua, "Conditions")
    check("Conditions opens its page with the buff's name",
          any("Show Arcane Intellect only when:" == text for text in
              lua.eval("(function() local r = {} for _, f in ipairs(allFrames) do r[#r + 1] = rawget(f, 'text') end return r end)()").values()
              if isinstance(text, str)))

    click_checkbox(lua, "Raid", True)
    check("a raid checkbox: the place is kept", lua.eval("SimpleBuffTrackerDB.buffs[1].conditions.places.raid") is True)
    lua.execute("RunTickers()")
    check("outside a raid the buff is hidden", shown_buttons(lua) == 0)
    lua.execute("instanceType = 'party'; RunTickers()")
    check("in a dungeon too (only Raid checked)", shown_buttons(lua) == 0)
    click_checkbox(lua, "Dungeon", True)
    lua.execute("RunTickers()")
    check("Raid or Dungeon: shown in a dungeon", shown_buttons(lua) == 1)
    lua.execute("instanceType = 'pvp'; RunTickers()")
    check("not on a battleground", shown_buttons(lua) == 0)
    click_checkbox(lua, "Raid", False)
    click_checkbox(lua, "Dungeon", False)
    check("no place checked: no places kept", lua.eval("SimpleBuffTrackerDB.buffs[1].conditions") is None)
    lua.execute("RunTickers()")
    check("and shown everywhere", shown_buttons(lua) == 1)

    lua.execute("Enter('conditionItem', 'Crab Cake')")
    check("an item condition by name", lua.eval("SimpleBuffTrackerDB.buffs[1].conditions.itemId") == 2683)
    lua.execute("itemCounts[2683] = 0; RunTickers()")
    check("no item in the bags: hidden", shown_buttons(lua) == 0)
    lua.execute("Fire('BAG_UPDATE_DELAYED')")
    check("the list greys the buff hidden now", lua.eval("Rows()[1].isHidden") is True
          and lua.eval("Rows()[1].label.fontObject") == "GameFontDisable")
    lua.execute("itemCounts[2683] = 3; RunTickers()")
    check("the item in the bags: shown", shown_buttons(lua) == 1)
    lua.execute("Fire('BAG_UPDATE_DELAYED')")
    check("and back to white when shown", lua.eval("Rows()[1].isHidden") is False)
    lua.execute("Enter('conditionItem', 'Nothing at all')")
    check("an unknown item changes nothing", lua.eval("SimpleBuffTrackerDB.buffs[1].conditions.itemId") == 2683)
    lua.execute("Enter('conditionItem', '')")
    check("empty: no item condition", lua.eval("SimpleBuffTrackerDB.buffs[1].conditions") is None)

    lua.execute("Enter('conditionTalent', 'arcane mind')")
    check("a talent of the tree by name, in its own spelling",
          lua.eval("SimpleBuffTrackerDB.buffs[1].conditions.talent.name") == "Arcane Mind")
    lua.execute("RunTickers()")
    check("a talent not learned: hidden", shown_buttons(lua) == 0)
    lua.execute("talentTree[1][5] = 1; Fire('CHARACTER_POINTS_CHANGED')")
    check("a point in it: shown", shown_buttons(lua) == 1)
    click_checkbox(lua, "Only if NOT learned", True)
    lua.execute("RunTickers()")
    check("Only if NOT learned: hidden with the talent", shown_buttons(lua) == 0)
    lua.execute("talentTree[1][5] = 0; RunTickers()")
    check("and shown without it", shown_buttons(lua) == 1)
    click_checkbox(lua, "Only if NOT learned", False)

    lua.execute("Enter('conditionTalent', '1459')")
    check("a spell by id", lua.eval("SimpleBuffTrackerDB.buffs[1].conditions.talent.spellId") == 1459)
    lua.execute("RunTickers()")
    check("a spell not known: hidden", shown_buttons(lua) == 0)
    lua.execute("knownSpells[1459] = true; RunTickers()")
    check("a known spell: shown", shown_buttons(lua) == 1)
    lua.execute("Window().PickLink('|cff4e96f7|Htalent:1234:0|h[Ice Shards]|h|r')")
    check("a talent link while no field is in focus changes nothing",
          lua.eval("SimpleBuffTrackerDB.buffs[1].conditions.talent.spellId") == 1459)
    lua.execute("FocusField('conditionTalent'); Window().PickLink('|cff4e96f7|Htalent:1234:0|h[Ice Shards]|h|r')")
    check("a talent link (shift-click) into the talent field",
          lua.eval("SimpleBuffTrackerDB.buffs[1].conditions.talent.name") == "Ice Shards")

    lua.execute("Enter('conditionItem', 'Crab Cake')")
    click_checkbox(lua, "Raid", True)
    click_button(lua, "Buff")
    check("the Buff tab shows the fields again", lua.eval("FindField('aura').parent.shown") is True
          and lua.eval("FindField('conditionItem').parent.shown") is False)
    check("the Conditions tab counts the conditions",
          lua.eval("(function() for _, f in ipairs(allFrames) do if rawget(f, 'text') == 'Conditions (3)' then return true end end return false end)()") is True)

    click_button(lua, "Conditions (3)")
    lua.execute("Slash('add Well Fed'); Window().Refresh()")
    lua.execute("Rows()[2].scripts.OnClick(Rows()[2])")
    check("another buff picked: the Conditions page stays open",
          lua.eval("FindField('conditionItem').parent.shown") is True
          and lua.eval("(function() for _, f in ipairs(allFrames) do if rawget(f, 'text') == 'Show Well Fed only when:' then return true end end return false end)()") is True)
    check("its tab has no count: no conditions",
          lua.eval("(function() for _, f in ipairs(allFrames) do if rawget(f, 'text') == 'Conditions' and rawget(f, 'scripts').OnClick then return true end end return false end)()") is True)
    lua.execute("ns.Services.Buff.Remove(2); Window().Refresh()")

    # combat: the conditions change, the icons stay until the end of combat
    lua.execute("instanceType = 'raid'; talentTree[2][5] = 1; RunTickers()")
    check("all three conditions met: shown", shown_buttons(lua) == 1)
    lua.execute("inCombat = true; itemCounts[2683] = 0; Fire('BAG_UPDATE_DELAYED'); RunTickers()")
    check("in combat the icon stays (no layout in combat)", shown_buttons(lua) == 1)
    lua.execute("inCombat = false; Fire('PLAYER_REGEN_ENABLED')")
    check("after combat the buff without its item is hidden", shown_buttons(lua) == 0)


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
    test_seen_buffs()
    test_suggestions()
    test_drag_and_previews()
    test_grow_direction()
    test_weapon_enchants()
    test_oil_with_flametongue()
    test_drag_order()
    test_fields_stack()
    test_editor_fits()
    test_action_bar_look()
    test_shift_drag()
    test_missing_glow()
    test_panel_stays_on_its_corner()
    test_right_click_opens_settings()
    test_settings_pages()
    test_other_addons_languages()
    test_russian()
    test_wording()
    test_show_conditions()
    if failures:
        print("\n%d failed" % len(failures))
        sys.exit(1)
    print("\nall passed")


if __name__ == "__main__":
    main()
