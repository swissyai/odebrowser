using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Gives the Space `SpaceId` of the manual setup the name and look of
/// `Customization`. The look is kept within the ranges every device draws;
/// the name is kept as typed.
public sealed record CustomizeSetupSpace(Guid SpaceId, SpaceCustomization Customization) : SetupDraftIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSetup(turn.Changes, draft => draft.Customizing(SpaceId, Customization));

    #endregion
}
