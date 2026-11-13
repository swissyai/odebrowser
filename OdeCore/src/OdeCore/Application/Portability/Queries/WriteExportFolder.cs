using OdeCore.Application;

namespace OdeCore.Contracts;

/// Writes every `ExportFormat`'s file of the workspace's Spaces into a new
/// dated folder inside `Folder`, creating it when needed, and keeps the
/// newest seven exports there, as `ExportFolder` describes. Passwords,
/// cookies, website storage, permissions, downloads, favicons and extensions
/// are never written.
///
/// When `UnlessFingerprint` is the workspace's fingerprint, nothing a person
/// would miss changed since the export that answered it, so nothing is
/// written and the answer names no folder.
///
/// Refused with `SpaceLocked` while any of its Spaces is locked,
/// `ArchiveTooLarge` or `BookmarksTooLarge` when a file would be larger than
/// an import reads, and `ExportFolderUnwritable` when `Folder` is not an
/// absolute path or cannot be written.
public sealed record WriteExportFolder(Guid WorkspaceId, string Folder, string? UnlessFingerprint = null) : Query<WrittenExport> {
    #region Variables

    /// Only reading the session holds the lock; the files are written outside it.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override WrittenExport Answer(OdeApp app) {
        SessionState session;
        HistoryStore? history;
        lock (app.Gate) {
            var workspace = app.Device.Workspace(WorkspaceId);
            (session, history) = (workspace.Exported(), workspace.History);
        }
        string fingerprint = ExportFolder.Fingerprint(session.Spaces);
        if (fingerprint == UnlessFingerprint) return new(null, fingerprint);
        var documents = ExportFormat.All.Select(format => app.Portability.Export(session, format, history)).ToArray();
        return new(ExportFolder.Write(Folder, documents, app.Portability.Clock.Now, TimeZoneInfo.Local), fingerprint);
    }

    #endregion
}
