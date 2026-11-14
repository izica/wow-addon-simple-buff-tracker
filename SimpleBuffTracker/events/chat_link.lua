-- chat_link.lua -- shift-click on an item in the bags (or a spell in the
-- spellbook) puts its link where the client inserts chat links: ChatFrameUtil.InsertLink
-- on Forever (HandleModifiedItemClick calls it), ChatEdit_InsertLink on older
-- clients. A field of the addon window in focus takes it (components/main_window.lua).

local ADDON, ns = ...

local function OnInsertLink(link)
    if type(link) == "string" then
        ns.Components.MainWindow.PickLink(link)
    end
end

ns.Events.On("PLAYER_LOGIN", function()
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
    end
end)
