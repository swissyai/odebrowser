using OdeCore.Application;

namespace OdeCore.Contracts;

/// Records an engine-observed result for one previously approved destination.
/// It cannot authorize a new destination or turn a completed install pending.
public sealed record SetSetupImportExtensionOutcome(Guid OutcomeId, string ExtensionId, Guid SpaceId,
    SetupImportExtensionStatus Status) : Intent {
    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(OdeApp app) => app.Turn(changes =>
        app.Device.SetImportExtensionOutcome(OutcomeId, ExtensionId, SpaceId, Status));

    #endregion
}
