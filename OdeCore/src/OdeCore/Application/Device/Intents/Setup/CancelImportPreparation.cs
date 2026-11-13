using OdeCore.Application;

namespace OdeCore.Contracts;

/// The platform cancelled before its point of no return. Release the review's
/// staged reads and return to the selected browsers, which a retry reads anew.
/// The platform must not send this once finalization has started.
public sealed record CancelImportPreparation : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) =>
        flow.Phase == SetupPhase.Committing
            ? flow with { Phase = SetupPhase.Idle, Step = SetupStep.ImportBrowser, Source = null, Review = null, Failure = null }
            : flow);

    #endregion
}
