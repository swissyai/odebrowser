using OdeCore.Application;

namespace OdeCore.Contracts;

/// Moves the nested tab `TabId`, with the tabs nested under it, out one level:
/// after the tabs nested under the tab it was nested under. A tab at the top
/// level stays where it is.
public sealed record OutdentTab(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.OutdentTab(TabId, turn.Now));

    #endregion
}
