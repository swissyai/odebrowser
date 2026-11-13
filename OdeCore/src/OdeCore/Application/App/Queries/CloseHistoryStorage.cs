using OdeCore.Application;

namespace OdeCore.Contracts;

/// Finishes history storage before destroying the native handle. The host
/// records `Failure` while it can still receive the exact reason and unsaved
/// operation count. No further browsing calls may use this handle afterwards.
public sealed record CloseHistoryStorage : Query<HistoryStorageResult> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override HistoryStorageResult Answer(OdeApp app) {
        try {
            app.History?.Dispose();
        } catch (Rejected error) when (error.Rejection is StorageUnreadable) {
            // The closed store retains the typed failure returned below.
        }
        return new(app.History?.CloseFailure);
    }

    #endregion
}
