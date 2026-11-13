using OdeCore.Application;

namespace OdeCore.Contracts;

/// Keeps a web link in its source tab's Space without showing or loading it.
/// Captured menu actions must still own the selected Space, profile and tab.
public sealed record KeepLink(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid ProfileId, Guid SourceTabId,
    Guid TabId, string Address, bool Pins) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (space.ProfileId != ProfileId || workspace.IssuingWindow(WindowId)?.ShownSpaceId != SpaceId
            || !space.Tabs.Any(tab => tab.Id == SourceTabId)) throw new Rejected(new SelectionChanged());
        if (!Uri.TryCreate(Address, UriKind.Absolute, out var address)
            || (address.Scheme != Uri.UriSchemeHttp && address.Scheme != Uri.UriSchemeHttps))
            throw new Rejected(new UnsupportedAddress(Address));
        var requested = Pins ? TabPlacement.Pinned : TabPlacement.Saved;
        var placement = requested.Fitting(space.Tabs.Count(tab => tab.Placement == requested) + 1);
        return new OpenTab(WorkspaceId, WindowId, SpaceId, TabId, new TabContent(Address, null, null),
            placement, null, false).Edit(workspace, turn);
    }

    #endregion
}
