using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Which engine, if any, owns a navigation once its scheme is known. Only a
/// load Ode itself started may keep `file:`.
public sealed record SchemeHandling(string? Scheme, bool AppInitiated) : StandaloneQuery<SchemeHandled> {
    #region Actions - Answering

    internal override SchemeHandled Answer(StandaloneContext context) => new(UrlScheme.DispositionOf(Scheme, AppInitiated));

    #endregion
}
