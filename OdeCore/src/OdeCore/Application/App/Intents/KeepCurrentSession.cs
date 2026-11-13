using OdeCore.Application;

namespace OdeCore.Contracts;

/// Keeps the session as it is after a launch held back an earlier copy because
/// the session had lost more than half of its Spaces or tabs: the person
/// answered that nothing is missing, so the held copy rotates out again like
/// any other. A core that keeps nothing on disk does nothing. It publishes
/// nothing.
public sealed record KeepCurrentSession : Intent {
    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(OdeApp app) => app.Turn(_ => Keep(app));

    #endregion

    #region Actions - App

    private static void Keep(OdeApp app) {
        if (app.Storage is { } target) RecoveryGenerations.Release(target.Directory);
    }

    #endregion
}
