-- main_window.lua -- the addon window in the game's own look (Forever): the
-- game-window border, two tabs under it.
--   Buffs -- the list of buffs on the left (components/buff_list.lua), the
--            chosen buff on the right (components/buff_editor.lua);
--   Panel -- how the panel looks (components/panel_settings.lua).
--
-- Shift-clicks from the game land here: a buff of the player (events/buff_frame.lua
-- -> PickAura), an item or a spell link (events/chat_link.lua -> PickLink) go into
-- the field being typed in; a buff with no field in focus becomes a new buff.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text
local Buff = ns.Models.Buff
local BuffService = ns.Services.Buff

local MainWindow = {}
ns.Components.MainWindow = MainWindow

local WINDOW_NAME = "SimpleBuffTrackerWindow"
local TAB_PREFIX = "SimpleBuffTrackerWindowTab"
local WIDTH = 680
local HEIGHT = 610
local CONTENT_TOP = 30       -- under the title band
local CONTENT_SIDE = 10
local CONTENT_BOTTOM = 10
local LIST_WIDTH = 210
local GAP = 6

MainWindow.TAB = { BUFFS = "buffs", PANEL = "panel" }
-- the height inside the window, under the title band (the tests check the editor fits)
MainWindow.CONTENT_HEIGHT = HEIGHT - CONTENT_TOP - CONTENT_BOTTOM

local window = nil
local tabBar = nil
local buffList = nil
local buffEditor = nil
local panelSettings = nil
local tabFrames = {}
local selectedIndex = nil
local currentTab = MainWindow.TAB.BUFFS

local function SavePosition(frame)
    local point, _, _, x, y = frame:GetPoint(1)
    ns.db.settings.window = { point = point, x = x, y = y }
end

local function PlaceWindow()
    local saved = ns.db.settings.window
    window:ClearAllPoints()
    if saved and saved.point then
        window:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
    else
        window:SetPoint("CENTER")
    end
end

-- the buffs, the list, the editor and the panel after a change
local function Changed()
    MainWindow.Refresh()
    ns.Components.BuffPanel.Refresh()
end

local function Select(index)
    selectedIndex = index
    MainWindow.Refresh()
end

local function ShowTab(tabId)
    currentTab = tabId
    for id, frame in pairs(tabFrames) do
        frame:SetShown(id == tabId)
    end
    tabBar:Select(tabId)
    MainWindow.Refresh()
end

local function Create()
    window = ns.UI.Panel(WINDOW_NAME, UIParent, {
        width = WIDTH,
        height = HEIGHT,
        title = ns.Constants.ADDON_TITLE,
        gameSkin = true,
        onMoved = SavePosition,
    })
    table.insert(UISpecialFrames, WINDOW_NAME)   -- Escape closes it
    PlaceWindow()

    local buffsTab = CreateFrame("Frame", nil, window)
    buffsTab:SetPoint("TOPLEFT", CONTENT_SIDE, -CONTENT_TOP)
    buffsTab:SetPoint("BOTTOMRIGHT", -CONTENT_SIDE, CONTENT_BOTTOM)
    tabFrames[MainWindow.TAB.BUFFS] = buffsTab

    buffList = ns.Components.BuffList.Create(buffsTab, {
        onSelect = Select,
        -- a dragged row: the buff keeps being the chosen one at its new place
        onMove = function(fromIndex, toIndex)
            if BuffService.MoveTo(fromIndex, toIndex) then
                selectedIndex = toIndex
            end
            Changed()
        end,
        onAdd = function()
            BuffService.Add(Buff.New({}, nil))
            selectedIndex = #BuffService.List()
            Changed()
            buffEditor:StartEditing()
        end,
    })
    buffList:SetPoint("TOPLEFT")
    buffList:SetPoint("BOTTOMLEFT")
    buffList:SetWidth(LIST_WIDTH)

    buffEditor = ns.Components.BuffEditor.Create(buffsTab, {
        onChanged = Changed,
        onDelete = function(index)
            BuffService.Remove(index)
            selectedIndex = math.min(index, #BuffService.List())
            if selectedIndex == 0 then
                selectedIndex = nil
            end
            Changed()
        end,
    })
    buffEditor:SetPoint("TOPLEFT", buffList, "TOPRIGHT", GAP, 0)
    buffEditor:SetPoint("BOTTOMRIGHT")

    local panelTab = ns.Components.PanelSettings.Create(window, { onChanged = Changed })
    panelTab:SetPoint("TOPLEFT", CONTENT_SIDE, -CONTENT_TOP)
    panelTab:SetPoint("BOTTOMRIGHT", -CONTENT_SIDE, CONTENT_BOTTOM)
    panelSettings = panelTab
    tabFrames[MainWindow.TAB.PANEL] = panelTab

    tabBar = ns.UI.TabBar(window, {
        namePrefix = TAB_PREFIX,
        tabs = {
            { id = MainWindow.TAB.BUFFS, text = Text("settings.tab_buffs") },
            { id = MainWindow.TAB.PANEL, text = Text("settings.tab_panel") },
        },
        onSelect = ShowTab,
    })
    window:HookScript("OnShow", function()
        MainWindow.Refresh()
    end)
    window:Hide()
end

function MainWindow.IsOpen()
    return window ~= nil and window:IsShown()
end

-- Redraw what is shown: after any change of the buffs, also from chat commands.
function MainWindow.Refresh()
    if not MainWindow.IsOpen() then
        return
    end
    local buffs = BuffService.List()
    if selectedIndex and not buffs[selectedIndex] then
        selectedIndex = nil
    end
    if not selectedIndex and #buffs > 0 then
        selectedIndex = 1
    end
    buffList:Refresh(selectedIndex)
    buffEditor:Display(buffs[selectedIndex], selectedIndex, #buffs)
    panelSettings:Refresh()
end

-- tabId -- MainWindow.TAB; open on that tab, or close if it is already shown there
function MainWindow.Toggle(tabId)
    tabId = tabId or MainWindow.TAB.BUFFS
    if not window then
        Create()
    end
    if window:IsShown() and currentTab == tabId then
        window:Hide()
        return
    end
    window:Show()
    ShowTab(tabId)
end

-- Open the window on that tab (MainWindow.TAB); an open window stays open.
function MainWindow.Open(tabId)
    if not window then
        Create()
    end
    window:Show()
    ShowTab(tabId or MainWindow.TAB.BUFFS)
end

-- Open the window on the Buffs tab with this buff chosen (a right click on its
-- icon on the panel); an open window stays open.
function MainWindow.ShowBuff(buff)
    for index, tracked in ipairs(BuffService.List()) do
        if tracked == buff then
            selectedIndex = index
        end
    end
    MainWindow.Open(MainWindow.TAB.BUFFS)
end

-- A shift-clicked link (an item from the bags, a spell from the spellbook)
-- into the field being typed in: the item field takes an item, the buff and
-- spell fields take a spell, the icon field takes both.
function MainWindow.PickLink(link)
    if not MainWindow.IsOpen() then
        return
    end
    local input = buffEditor:FocusedField()
    if input then
        buffEditor:TakeLink(input, link)
    end
end

-- A shift-click on a buff of the player: into the field being typed in (the
-- icon field takes the exact spell id, the others the name, every rank);
-- with no field in focus -- a new buff (or the page of the same one).
-- Returns whether the click was used.
function MainWindow.PickAura(spellId, name)
    if not MainWindow.IsOpen() then
        return false
    end
    local input, key = buffEditor:FocusedField()
    if input then
        -- a buff is a spell: only the fields that take spells
        if not input.field.takes("spell") then
            return false
        end
        if key == "icon" and spellId then
            input:Put(tostring(spellId))
        else
            input:Put(name or tostring(spellId))
        end
        return true
    end

    for index, tracked in ipairs(BuffService.List()) do
        local target = tracked.target
        local isSameSpell = spellId ~= nil and target.spellId == spellId
        local isSameName = name ~= nil and target.name ~= nil and target.name:lower() == name:lower()
        if isSameSpell or isSameName then
            Select(index)
            return true
        end
    end
    BuffService.Add(Buff.New({ spellId = spellId, name = name }, nil))
    selectedIndex = #BuffService.List()
    if currentTab ~= MainWindow.TAB.BUFFS then
        ShowTab(MainWindow.TAB.BUFFS)
    end
    Changed()
    return true
end
