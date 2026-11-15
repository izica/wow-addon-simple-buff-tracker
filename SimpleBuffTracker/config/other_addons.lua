-- other_addons.lua -- the author's addons, for the "Other addons" page of the
-- settings (components/other_addons_page.lua).
--
-- The same list goes into every addon of the author: each page hides its own
-- addon (the page's exclude option). A new addon -- a line here, and its
-- description under other_addons.notes.<id> in lang/*.json, in every addon.
--
-- folder -- the folder in Interface\AddOns (tells whether it is installed);
-- title  -- the name players know it by (a name: not translated);
-- icon   -- a picture of the game: an addon's own picture is there only when
--           it is installed, so with an own picture fallbackIcon is shown
--           while it is not.

local ADDON, ns = ...
ns.Config = ns.Config or {}

ns.Config.OTHER_ADDONS = {
    {
        id = "purple_note",
        folder = "PurpleNote",
        title = "Purple Note",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
    },
    {
        id = "prr",
        folder = "PRR",
        title = "PRR: Professions, Recipes, Reagents",
        icon = "Interface\\Icons\\INV_Misc_Bag_10",
    },
    {
        id = "target_it",
        folder = "TargetIt",
        title = "Target It: NPC Finder",
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    },
    {
        id = "simple_buff_tracker",
        folder = "SimpleBuffTracker",
        title = "Simple Buff Tracker",
        icon = "Interface\\AddOns\\SimpleBuffTracker\\media\\icon",
        fallbackIcon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    },
}
