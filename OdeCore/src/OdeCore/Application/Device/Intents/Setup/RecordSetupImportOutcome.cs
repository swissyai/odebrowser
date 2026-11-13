using OdeCore.Application;

namespace OdeCore.Contracts;

/// Checkpoints a platform import attempt before side effects or after failure.
/// Successful imports pass their receipt to FinishImportCommit instead.
public sealed record RecordSetupImportOutcome(SetupImportOutcome Outcome) : Intent {
    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(OdeApp app) => app.Turn(changes => app.Device.KeepImportOutcome(Outcome));

    #endregion
}
