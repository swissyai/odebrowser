using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Brings the saved passwords that belong with the reviewed Space
/// `SourceSpaceId`, or leaves them out.
public sealed record IncludeImportPasswords(Guid SourceSpaceId, bool Included) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.IncludingPasswords(SourceSpaceId, Included, session)));

    #endregion
}
