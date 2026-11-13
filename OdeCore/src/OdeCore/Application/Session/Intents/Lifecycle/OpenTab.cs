using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Opens a tab, `TabId`, showing `Content` in `Placement`'s section of a
/// Space: after the tab `AfterTabId` names and outside its split, or where its
/// section puts a new tab. An open tab a page opened names the tab of that page
/// as `OpenerTabId`; it nests under that tab, after the tabs nested there
/// already, when the app's preferences nest tabs opened from pages and that tab
/// is an open tab at the top level in no split, and opens after `AfterTabId`
/// otherwise. When `Shows`, the window that asked shows the tab and its Space,
/// and the tabs above a nested one show their nested tabs. Refused with
/// `TabLimitReached` or `PinnedTabsFull` when the Space or the section is full,
/// and with `UnsupportedAddress` for an address a page cannot load.
public sealed record OpenTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, TabContent Content, TabPlacement Placement,
    Guid? AfterTabId, bool Shows, Guid? OpenerTabId = null) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Opens the tab, which the issuing window shows when the intent asks.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (turn.Basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == TabId)))
            throw new Rejected(new TabAlreadyExists(TabId));
        var edited = BrowserTabCollection.Restore(space);
        var tab = BrowserTab.Restore(workspace.NewTab(TabId, Content, Placement, turn.Now));
        if (OpenerTabId is not { } opener || !workspace.NestsTabsOpenedFromPages(turn.Basis)
            || !edited.InsertNestedTab(tab, opener, Shows))
            edited.InsertTab(tab, AfterTabId is { } origin ? edited.InsertionIndexAfter(origin) : null);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (Shows) followUp.ShowTab(space.Id, tab.Id).ShowSpace(space.Id);
        return new(turn.Basis.Replacing(edited.Capture(space)), SyncStaging.Creation, followUp);
    }

    #endregion
}
