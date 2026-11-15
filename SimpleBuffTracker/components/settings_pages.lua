-- settings_pages.lua -- the addon's pages in Options -> AddOns: the main page
-- (components/about_page.lua) and under it "Other addons"
-- (components/other_addons_page.lua). Registered once, on login; a client
-- without the Settings API gets no pages (the addon's own window still works).

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local SettingsPages = {}
ns.Components.SettingsPages = SettingsPages

local category = nil

-- the game's settings out of the way, then the addon's window
local function OpenAddonWindow()
    if SettingsPanel and SettingsPanel:IsShown() then
        if SettingsPanel.Close then
            SettingsPanel:Close(true)
        else
            HideUIPanel(SettingsPanel)
        end
    end
    ns.Components.MainWindow.Open(ns.Components.MainWindow.TAB.BUFFS)
end

function SettingsPages.Register()
    local hasApi = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
    if category or not hasApi then
        return
    end
    local about = ns.Components.AboutPage.Create(UIParent, { onOpen = OpenAddonWindow })
    about:Hide()
    category = Settings.RegisterCanvasLayoutCategory(about, ns.Constants.ADDON_TITLE)

    local others = ns.Components.OtherAddonsPage.Create(UIParent, {
        addons = ns.Config.OTHER_ADDONS,
        exclude = ADDON,
        text = Text,
    })
    others:Hide()
    Settings.RegisterCanvasLayoutSubcategory(category, others, Text("other_addons.title"))
    Settings.RegisterAddOnCategory(category)
end
