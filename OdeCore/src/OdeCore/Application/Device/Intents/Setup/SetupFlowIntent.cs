using OdeCore.Application;

namespace OdeCore.Contracts;

/// Moves setup on this device along. Each publishes setup as it leaves it in
/// `SetupFlowChanged`. One is refused with `NoSetup` while setup is not open,
/// and one that changes what setup works on with `SetupBusy` while it reads or
/// imports.
public abstract record SetupFlowIntent : Intent {
    #region Variables

    internal virtual IReadOnlyList<SpaceState> ReadSpaces => [];

    #endregion

    #region Abstract Methods

    /// Runs the intent on the setup open on the device, publishing the flow it
    /// leaves.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(OdeApp app) => app.Turn(changes => {
        var previous = app.Device.SetupFlow?.Review?.Spaces.Select(space => space.Source) ?? [];
        var candidates = previous.Concat(ReadSpaces).Select(space => space.ImportReadId).OfType<Guid>().Distinct().ToArray();
        try {
            app.Device.Handle(this, app.DeviceTurn(changes));
        } finally {
            var kept = app.Device.SetupFlow?.Review?.Spaces.Select(space => space.Source.ImportReadId).OfType<Guid>().ToHashSet() ?? [];
            foreach (var id in candidates.Where(id => !kept.Contains(id))) app.Portability.DiscardRead(id);
        }
    });

    #endregion
}
