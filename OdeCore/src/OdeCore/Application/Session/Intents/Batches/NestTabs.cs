using OdeCore.Application;

namespace OdeCore.Contracts;

/// Nests the tabs a person selected in a window under the open tab
/// `ParentTabId`, after the tabs nested there already: each selected tab
/// brings the tabs nested under it and leaves its split. Refused with
/// `InvalidFolderPlacement` for a selection that holds folders, or a tab that
/// cannot hold nested tabs or that the selection holds or nests over. Saved
/// with the sync journal before the intent returns.
public sealed record NestTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid ParentTabId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        batch.Edited.NestSelected(batch.Selected, ParentTabId, turn.Now);
        return batch.Result(turn.Basis, SyncStaging.Batch);
    }

    #endregion
}
