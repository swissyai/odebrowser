using System.Text.Json.Nodes;

using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

public sealed partial class OdeApp {
    #region Variables

    private readonly SessionStorage? storage;
    internal SessionStorage? Storage => storage;
    /// Every visit the stored session's Spaces made, beside its file; null
    /// without a storage directory or when it could not be opened.
    private readonly HistoryStore? history;
    internal HistoryStore? History => history;

    /// The session this core keeps in its file, as it loaded and repaired it,
    /// once the file holds one. `OpenWorkspace` opens it. Set once, under the
    /// lock; the cloud transport's calls read it without the lock.
    private volatile NativeSessionAuthority? storedSession;
    internal NativeSessionAuthority? StoredSession => storedSession;
    /// The sync component the file's session stages into, kept beside it. Set
    /// with `storedSession`.
    private volatile NativeSyncAuthority? storedSync;
    /// The selection an older release kept in the stored session, which the
    /// windows of the launch that loaded it adopt.
    private JsonObject? storedSelection;
    /// The tabs the repair gave a new identity, each with the tab whose image
    /// it wears.
    private IReadOnlyList<(Guid Source, Guid Copy)> repairedCopies = [];

    /// The sync component of the session this core keeps in its file, which
    /// the tests read the journal of; null while the file holds no session.
    internal NativeSyncAuthority? StoredSync => storedSync;

    #endregion

    #region Actions - History

    /// Takes the whole history each read Space of `spaces` brought into the
    /// history kept beside the stored session, under the Space it became or
    /// joined there, once the import into `workspaceId` committed. Nothing
    /// for another workspace, a Space the session does not hold, or a read
    /// that kept no history for it.
    internal void TakeImportedHistory(Guid workspaceId, IEnumerable<(Guid Source, Guid Destination)> spaces) {
        if (history is null || storedSession is not { } session || device.Identity(session) != workspaceId) return;
        var held = session.Current.Spaces.ToDictionary(space => space.Id);
        foreach (var (source, destination) in spaces) {
            if (portability.TakeReadHistory(source) is not { } places || !held.TryGetValue(destination, out var space)) continue;
            history.Import(destination, places);
            if (space.Settings.BrowsingPreferences.DataRetention.History.Lifetime is { } lifetime)
                history.Expire(destination, clock.Now - lifetime);
        }
    }

    #endregion

    #region Actions - Stored session

    /// Replaces the session file in `configuration`'s directory with the
    /// recovery checkpoint the last good launch kept, while no core has that
    /// file open. Throws `Rejected` naming why it cannot; see
    /// `SessionStorage.Restore`.
    public static void RestoreRecoveryCheckpoint(AppConfiguration configuration) {
        ArgumentNullException.ThrowIfNull(configuration);
        if (configuration.StorageDirectory is not { } directory)
            throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.Unavailable));
        SessionStorage.Restore(directory);
    }

    /// The dated copies of the session file in `configuration`'s directory
    /// that a restore can return to, newest first, each with when a launch
    /// took it and what it held. A copy a launch held back, because the
    /// session had since lost more than half of its Spaces or tabs without
    /// the person removing them, is marked `Held`.
    public static IReadOnlyList<RecoveryCopy> ListRecoveryGenerations(AppConfiguration configuration) {
        ArgumentNullException.ThrowIfNull(configuration);
        return configuration.StorageDirectory is { } directory ? RecoveryGenerations.List(directory) : [];
    }

    /// Replaces the session file in `configuration`'s directory with the dated
    /// copy named `generation`, while no core has that file open. Throws
    /// `Rejected` naming why it cannot.
    public static void RestoreRecoveryCheckpoint(AppConfiguration configuration, string generation) {
        ArgumentNullException.ThrowIfNull(configuration);
        if (configuration.StorageDirectory is not { } directory)
            throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.Unavailable));
        SessionStorage.Restore(directory, generation);
    }

    /// Keeps the session as it is: a copy a launch held back rotates out
    /// again like any other.
    public static void KeepCurrentSession(AppConfiguration configuration) {
        ArgumentNullException.ThrowIfNull(configuration);
        if (configuration.StorageDirectory is { } directory) RecoveryGenerations.Release(directory);
    }

    /// Makes a stored session the one `OpenWorkspace` opens from the file. The
    /// recovery checkpoint preserves the file exactly as loaded before anything
    /// else is written; the repaired session is then the first save.
    internal void Establish(SessionState stored, NativeSyncJournal? journal, JsonObject? legacySelection) {
        var target = storage!;
        try {
            target.SaveRecoveryCheckpoint(stored, clock.Now);
        } catch (Exception error) when (error is StorageException or IOException or UnauthorizedAccessException) {
            // A launch that cannot preserve a copy still opens the session it read.
        }
        SessionState repaired;
        IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins;
        try {
            repaired = NativeSessionMaintenance.Repair(stored, DateTimeOffset.UtcNow, null, new SystemIdSource(), out origins);
        } catch (BrowserRuleException) {
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        }
        storedSession = new NativeSessionAuthority(repaired, target, history);
        storedSync = new NativeSyncAuthority(journal ?? NativeSyncJournal.Fresh(Guid.NewGuid()));
        storedSelection = legacySelection;
        repairedCopies = NativeSessionMaintenance.Copies(repaired, origins);
    }

    #endregion
}
