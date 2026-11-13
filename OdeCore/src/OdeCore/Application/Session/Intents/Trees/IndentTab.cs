using OdeCore.Application;

namespace OdeCore.Contracts;

/// Nests the open tab `TabId` under the tab above it at its level, after the
/// tabs nested there, which then show. A tab first at its level, or one that
/// cannot nest, stays where it is.
public sealed record IndentTab(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.IndentTab(TabId));

    #endregion
}
