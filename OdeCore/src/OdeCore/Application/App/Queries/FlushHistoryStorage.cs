using OdeCore.Application;

namespace OdeCore.Contracts;

/// Waits for history accepted before the call, retrying a failed batch once.
/// Quit and background persistence use the returned outcome instead of
/// claiming a successful session save means history is on disk too.
public sealed record FlushHistoryStorage : Query<HistoryStorageResult> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override HistoryStorageResult Answer(OdeApp app) {
        var store = app.History;
        if (store is null) return new(app.Storage is null ? null
            : new HistoryStorageFailed(HistoryStorageOperation.Open, StorageFailure.Unavailable, 0));
        try {
            store.Flush();
            return new(null);
        } catch (Rejected error) when (error.Rejection is StorageUnreadable failure) {
            return new(new HistoryStorageFailed(HistoryStorageOperation.Write, failure.Reason, store.UnsavedWrites));
        }
    }

    #endregion
}
