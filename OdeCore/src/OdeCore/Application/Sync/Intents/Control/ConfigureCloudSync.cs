using OdeCore.Application;

namespace OdeCore.Contracts;

/// Sync starts on this device: whether the person turned it on, and whether
/// this build can reach Ode's CloudKit container at all.
public sealed record ConfigureCloudSync(bool IsEnabled, bool CanReachCloud) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        control.IsEnabled = IsEnabled;
        control.CanReachCloud = CanReachCloud;
        control.Phase = control.IsEnabled ? CloudSyncPhase.Checking : CloudSyncPhase.Disabled;
        return [];
    }

    #endregion
}
