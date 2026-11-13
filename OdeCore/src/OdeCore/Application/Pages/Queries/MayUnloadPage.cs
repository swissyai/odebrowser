using OdeCore.Application;

namespace OdeCore.Contracts;

/// Whether browser-initiated unloading may discard this page's document.
/// This does not authorize closing a tab, navigating or changing engines.
public sealed record MayUnloadPage(Guid PageId) : Query<PageUnloadDecision> {
    #region Actions - Answering

    internal override PageUnloadDecision Answer(OdeApp app) =>
        new(app.Pages.Hosted(PageId)?.MayUnload == true);

    #endregion
}
