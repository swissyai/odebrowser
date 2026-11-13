using OdeCore.Application;

namespace OdeCore.Contracts;

/// The scriptlets an engine runs in a page's own world for the document at
/// `Url` it is about to show, before the page's scripts, as one script: empty
/// when Ode does not block on the site, the filter runs none
/// there, or the core does not host the page on that engine.
public sealed record PageInjectedScript(Guid PageId, string Url) : EngineQuestion<string> {
    #region Actions - Answering

    internal override string Answer(OdeApp app, Engine engine) =>
        app.Pages.Hosted(PageId) is { } page && ReferenceEquals(page.Engine, engine)
            && app.Device.Blocks(page.SpaceId, new WebAddress(Url).Origin)
            ? app.Filters.Scriptlets(Url) : "";

    #endregion
}
