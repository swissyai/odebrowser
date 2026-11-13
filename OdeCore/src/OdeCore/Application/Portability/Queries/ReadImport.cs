using OdeCore.Application;

namespace OdeCore.Contracts;

/// The Spaces an import of `Profiles` from `Source` brings, read from the
/// files each profile names, without importing anything. A source that names
/// its own Spaces brings them as named there, those without tabs too; any
/// other brings one Space for each profile, holding its open tabs and as many
/// of its bookmarks, as saved tabs, as fit beside them, and named after it.
/// Chrome's and Arc's Spaces also offer the extensions their profile has
/// installed from the Chrome Web Store.
///
/// What fits is kept: the Spaces past the most a workspace holds, a Space
/// holding more than a Space keeps, a window that does not fit beside a
/// profile's others, bookmarks that do not fit, and a file that cannot be
/// read are each left out in `LeftOut`, named for their profile or Space, with
/// why, such as `SessionOverLimits`, `BookmarksOverLimits` or
/// `SessionUnrecognized`, while the rest come. When Chrome's latest session
/// cannot be read or holds no tab, the session before it is read instead.
///
/// The platform holds any access the files need while the core reads them,
/// and asks away from the main thread: the core answers without waiting for
/// any other work. Refused only when nothing could be brought: with the
/// reason the last profile or Space was left out, or `SessionHasNoTabs` when
/// no profile names a file.
public sealed record ReadImport(ImportSource Source, IReadOnlyList<ImportProfile> Profiles, Guid? ReadId = null) : Query<ImportedSpaces> {
    #region Variables

    /// It reads files, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// The Spaces the profiles bring. The whole history each brings stays
    /// with the core until an import takes it in.
    internal override ImportedSpaces Answer(OdeApp app) {
        var portability = app.Portability;
        var id = ReadId ?? portability.PrepareRead();
        portability.StartRead(id);
        try {
            Dictionary<Guid, IReadOnlyList<SessionHistoryEntry>> histories = [];
            var read = InstalledBrowser.Of(Source).Read(Profiles, portability.Names(Source), portability.Ids, portability.Clock.Now, histories);
            return portability.KeepRead(id, read, histories);
        } catch {
            portability.FailedRead(id);
            throw;
        }
    }

    #endregion
}
