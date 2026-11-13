using OdeCore.Application;

namespace OdeCore.Contracts;

/// Removes every address a Space's history holds that was visited within
/// `Range`, ending now, and the same from every Space of its group, whose
/// history they share; an address visited earlier too goes with its earlier
/// visits. The visits this device keeps for those Spaces within `Range` go
/// too, and a place left without one. Without a Space it clears every Space
/// this process may read, passing over one that is locked or being deleted.
public sealed record ClearHistory(Guid WorkspaceId, Guid? SpaceId, BrowsingDataRange Range) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        SpaceState[] spaces = SpaceId is { } spaceId
            ? [.. workspace.GroupEditable(turn.Basis, spaceId)] : [.. workspace.EditableSpaces(turn.Basis)];
        var since = Range.Since(turn.Now);
        var cleared = spaces.Select(space => space.WithoutHistory(entry => since is null || entry.LastVisitedAt >= since));
        return new(turn.Basis.Replacing([.. cleared]), SyncStaging.Deletion, Stores: store => {
            foreach (var space in spaces) {
                if (since is { } start) store.RemoveVisits(space.Id, start, DateTimeOffset.MaxValue);
                else store.Clear(space.Id);
            }
        });
    }

    #endregion
}
