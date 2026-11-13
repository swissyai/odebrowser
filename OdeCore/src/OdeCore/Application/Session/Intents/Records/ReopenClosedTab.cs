using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Reopens what the Space archived last, as `RestoreArchivedTab` reopens one
/// tab, and the window that asked shows it. Tabs closed together, as clearing
/// the Space's open tabs closes them, come back together in their order.
/// Refused with `NoArchivedTabs` when the Space keeps none.
public sealed record ReopenClosedTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Reopens the tab the Space archived last, with the tabs closed in the
    /// same turn, and the issuing window shows the one used most recently.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var newest = space.ArchivedTabs.MaxBy(archived => archived.ArchivedAt) ?? throw new Rejected(new NoArchivedTabs(space.Id));
        // One dismissal archives its tabs at one time, in sidebar order; the
        // archive sweep and deletions are never reopened as a batch.
        var batch = newest.Reason == ArchiveReason.Closed
            ? space.ArchivedTabs.Where(archived => archived.Reason == ArchiveReason.Closed && archived.ArchivedAt == newest.ArchivedAt).ToArray()
            : [newest];
        if (batch.Length == 1) return new RestoreArchivedTab(WorkspaceId, WindowId, space.Id, newest.Tab.Id).Edit(workspace, turn);
        var reopening = batch.Select(archived => archived.Tab.Id).ToHashSet();
        if (turn.Basis.Spaces.SelectMany(candidate => candidate.Tabs).FirstOrDefault(tab => reopening.Contains(tab.Id)) is { } existing)
            throw new Rejected(new TabAlreadyExists(existing.Id));
        var remaining = space with { ArchivedTabs = [.. space.ArchivedTabs.Where(archived => !reopening.Contains(archived.Tab.Id))] };
        var edited = BrowserTabCollection.Restore(remaining);
        // Each reopened tab goes to the top of the open tabs, so the last
        // in sidebar order goes first.
        for (var index = batch.Length - 1; index >= 0; index--) edited.RestoreArchived(batch[index].Tab, turn.Now);
        var shown = batch.MaxBy(archived => archived.Tab.LastActivatedAt)!.Tab.Id;
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId)).ShowTab(space.Id, shown);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(remaining)), SyncStaging.Creation, followUp);
    }

    #endregion
}
