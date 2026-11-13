using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// What `Input`, as a person typed it, loads: an address as it is, or a
/// search with what `SpaceId` in `WorkspaceId` searches with, and that
/// search's first result, which Shift-Return opens. Without a
/// workspace, as a setup draft whose Spaces do not exist yet, it searches with
/// Google, opens no internal page and reads no state, so a host may ask it
/// without an app.
public sealed record ResolveAddress(Guid? WorkspaceId, Guid? SpaceId, string Input) : Query<ResolvedAddress> {
    #region Actions - Answering

    /// An address that names a workspace resolves with what the Space it names
    /// searches with, or the device's default search when it names none, and
    /// opens an internal page when the default engine shows them.
    internal override ResolvedAddress Answer(OdeApp app) {
        if (WorkspaceId is not { } workspaceId) return Unplaced();
        var provider = SpaceId is { } spaceId ? app.Device.Workspace(workspaceId).Searches(spaceId) : app.Device.SearchCatalog.Default;
        return NativeSessionAuthority.Resolved(Input, provider, app.Pages.OpensInternalPages, app.Device.SearchCatalog);
    }

    /// What the address resolves to outside any workspace: Google searches
    /// what is not an address, and no internal page opens.
    internal ResolvedAddress Unplaced() {
        var catalog = SearchCatalog.Starting(language: null, region: null);
        return NativeSessionAuthority.Resolved(Input, catalog.Default, allowsInternalPages: false, catalog);
    }

    /// An address that names no workspace resolves by the default rules
    /// without an app; one that names a workspace only an app answers.
    internal override ResolvedAddress AnswerWithoutApp(StandaloneContext context) =>
        WorkspaceId is null ? Unplaced() : base.AnswerWithoutApp(context);

    #endregion
}
