using OdeCore.Application;

namespace OdeCore.Contracts;

/// Leaves setup without applying its unconfirmed manual draft or opening the
/// separate guide. Imports already committed and confirmed appearance choices
/// stay as they are. A read must be cancelled first; an applying import cannot
/// be interrupted. This records the same normal completion as FinishSetup.
public sealed record SkipSetup : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var finish = device.FinishingSetup(skipsManualSetup: true);
        device.FinishManualSetup(finish.WorkspaceId, turn.Changes);
        device.FinishedSetup(finish, guideSpaceId: null, turn.Changes);
    }

    #endregion
}
