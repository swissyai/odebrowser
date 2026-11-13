using OdeCore.Application;

namespace OdeCore.Contracts;

/// Hides the tabs nested under the open tab `TabId` in the sidebar, or shows
/// them. A tab that holds no nested tabs has none to hide.
public sealed record CollapseNestedTabs(Guid WorkspaceId, Guid SpaceId, Guid TabId, bool Collapsed) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.CollapseNestedTabs(TabId, Collapsed));

    #endregion
}
