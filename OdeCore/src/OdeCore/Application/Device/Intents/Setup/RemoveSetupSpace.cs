using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Leaves the new Space `SpaceId` out of the manual setup. A setup never
/// removes an existing Space, so naming one changes nothing.
public sealed record RemoveSetupSpace(Guid SpaceId) : SetupDraftIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSetup(turn.Changes, draft => draft.Removing(SpaceId));

    #endregion
}
