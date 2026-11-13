using OdeCore.Application;

namespace OdeCore.Contracts;

/// Keeps the session file as it is now as a copy named for `Version`, the
/// version an update is about to install, before the update replaces the app.
/// A restore can return to it after the update, as to any dated copy. Sent
/// once every edit is saved, as the quit that installs the update finishes.
/// A core that keeps nothing on disk, or whose file holds no session yet,
/// keeps nothing; a version a copy cannot be named for is refused with
/// `InvalidUpdateVersion`. It publishes nothing.
public sealed record KeepCopyBeforeUpdate(string Version) : Intent {
    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(OdeApp app) => app.Turn(_ => Keep(app));

    #endregion

    #region Actions - App

    private void Keep(OdeApp app) {
        if (!RecoveryGenerations.IsUpdateVersion(Version)) throw new Rejected(new InvalidUpdateVersion());
        if (app.Storage is not { } target || app.StoredSession is not { } session) return;
        try {
            target.SaveUpdateCopy(session.Current, app.Clock.Now, Version);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
    }

    #endregion
}
