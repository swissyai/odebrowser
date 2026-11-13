using OdeCore.Application;

namespace OdeCore.Contracts;

/// The browsers the platform found installed, in the order it lists them,
/// which is the order setup imports from them. Arc comes chosen the first time
/// it is offered while nothing is chosen, so a person leaving it goes on with
/// one click; once offered, choosing stays the person's.
public sealed record OfferImportSources(IReadOnlyList<ImportSource> Installed) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) => {
        var selected = Installed.Where(flow.Selected.Contains).ToList();
        if (selected.Count == 0 && Installed.Contains(ImportSource.Arc) && !flow.Offered.Contains(ImportSource.Arc))
            selected.Add(ImportSource.Arc);
        return flow with { Offered = Installed, Selected = selected };
    });

    #endregion
}
