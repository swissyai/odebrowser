using OdeCore.Application;

namespace OdeCore.Contracts;

/// This device, which held nothing, took the cloud's content.
public sealed record CloudContentTaken(long Attempt) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) => control.ResetThenStart(Attempt, overwritesCloud: false);

    #endregion
}
