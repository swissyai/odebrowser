using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Keeps an archived tab in Saved or Pinned without showing its page. Its
/// identity stays the same and its archive entry goes only when keeping it
/// succeeds. A full pinned section overflows to Saved.
public sealed record KeepArchivedTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid ProfileId, Guid TabId, bool Pins)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (space.ProfileId != ProfileId || workspace.IssuingWindow(WindowId)?.ShownSpaceId != SpaceId)
            throw new Rejected(new SelectionChanged());
        var archived = space.ArchivedTabs.FirstOrDefault(entry => entry.Tab.Id == TabId)
            ?? throw new Rejected(new UnknownArchivedTab(TabId));
        if (turn.Basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == TabId)))
            throw new Rejected(new TabAlreadyExists(TabId));
        var remaining = space with { ArchivedTabs = [.. space.ArchivedTabs.Where(entry => entry.Tab.Id != TabId)] };
        var edited = BrowserTabCollection.Restore(remaining);
        var restored = edited.RestoreArchived(archived.Tab, turn.Now);
        var requested = Pins ? TabPlacement.Pinned : TabPlacement.Saved;
        var placement = requested.Fitting(space.Tabs.Count(tab => tab.Placement == requested) + 1);
        edited.FileSelected(edited.Select(new TabSelection([restored.Id], [], [restored.Id])), placement,
            null, null, null, leavesSplits: false, turn.Now);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(remaining)), SyncStaging.Creation);
    }

    #endregion
}
