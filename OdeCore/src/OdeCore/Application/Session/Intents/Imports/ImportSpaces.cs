using OdeCore.Application;

namespace OdeCore.Contracts;

/// Adds each Space of `Spaces` after the workspace's own, whole: its tabs,
/// folders, splits, archive and history, as `ReadArchive` or `ReadImport`
/// brought them. A first launch's disposable Spaces stay while they fit
/// beside them, and otherwise make way, as a reviewed import's do. Pinned
/// tabs past the limit become saved tabs. The window shows the first of them,
/// on its first tab.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ImportSpaces(Guid WorkspaceId, Guid WindowId, IReadOnlyList<SpaceState> Spaces)
    : ImportWorkspace(WorkspaceId, WindowId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Importing(turn.Basis, this, Spaces, turn.Previewed, turn.Now, turn.Ids, import => import.AddSpaces());

    #endregion

    #region Actions - Routing

    /// Adds the Spaces, then the whole history each brought from a read,
    /// with its visits, into the history kept beside the session.
    internal override void Commit(OdeApp app, ChangeFeed changes) {
        app.Portability.ImportReads(Spaces, () => {
            base.Commit(app, changes);
            app.TakeImportedHistory(WorkspaceId, Spaces.Select(space => (space.Id, space.Id)));
        });
    }

    #endregion
}
