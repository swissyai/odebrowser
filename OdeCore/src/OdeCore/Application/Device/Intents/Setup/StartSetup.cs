using OdeCore.Application;

namespace OdeCore.Contracts;

/// Opens setup over the workspace for a person arriving by `Entry`, on the
/// entry's first step, in place of any setup open before. A manual setup kept
/// from before is kept for the manual-setup step only where the platform keeps
/// one and the entry does not start it over.
///
/// Refused with `PersistentWorkspaceRequired` for a workspace setup cannot
/// change.
public sealed record StartSetup(Guid WorkspaceId, SetupEntry Entry) : SetupFlowIntent {
    #region Actions - Device

    /// Opens setup for `Entry` over its workspace. A manual setup the
    /// device holds is kept for the manual-setup step only where the platform
    /// keeps one and the entry does not start it over.
    internal override void Apply(Device device, DeviceTurn turn) {
        var authority = device.Workspace(WorkspaceId);
        if (!authority.Kind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(WorkspaceId));
        var session = authority.Current;
        lock (device.Gate) {
            if (Entry.StartsManualSetupOver || !device.Platform.KeepsSetupDraft) device.KeepSetup(null, turn.Changes);
            // Browsers offered before are offered again, with Arc chosen when
            // it is among them, as a first offer chooses it.
            var offered = device.SetupFlow?.Offered ?? [];
            IReadOnlyList<ImportSource> selected = offered.Contains(ImportSource.Arc) ? [ImportSource.Arc] : [];
            var flow = new SetupFlowState(WorkspaceId, Entry, Entry.FirstStep, BackStep: null, NextStep: null,
                SetupPhase.Idle, Offered: offered, Selected: selected, Queue: null, Source: null, Review: null,
                Failure: null, Summary: null, OpensGuide: false, OpensOdeFromWelcome: false, SetupLook.Modern);
            if (flow.Step == SetupStep.ManualSetup)
                device.BeginSetup(WorkspaceId, session, startsOver: false, flow.Look, turn.Changes, turn.Ids);
            device.Publish(flow, turn.Changes);
        }
    }

    #endregion
}
