using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Makes the reviewed Space `SourceSpaceId` come in on its own, rather than
/// in a group with the Spaces it shared a session with where it came from.
public sealed record SeparateImportSpace(Guid SourceSpaceId) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.Separating(SourceSpaceId, session)));

    #endregion
}
