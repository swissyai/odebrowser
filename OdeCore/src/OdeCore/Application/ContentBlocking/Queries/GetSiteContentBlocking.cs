using OdeCore.Application;

namespace OdeCore.Contracts;

/// Every site where Ode blocks no ads or trackers.
public sealed record GetSiteContentBlocking : Query<IReadOnlyList<SiteContentBlocking>> {
    #region Actions - Answering

    internal override IReadOnlyList<SiteContentBlocking> Answer(OdeApp app) => app.Device.BlockingSites;

    #endregion
}
