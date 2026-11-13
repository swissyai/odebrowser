using OdeCore.Application;

namespace OdeCore.Contracts;

/// Removes every address and stored visit from the address's host and its
/// subdomains in one editable Space. A leading www. is ignored, as in the
/// local history store. Other Spaces and similarly spelled hosts stay intact.
public sealed record RemoveHistorySite(Guid WorkspaceId, Guid SpaceId, string Address) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (!Uri.TryCreate(Address, UriKind.Absolute, out var address) || address.Host.Length == 0) return null;
        string site = HistoryStore.Site(Address);
        var remaining = workspace.WithoutHistory(space, entry => {
            string host = HistoryStore.Site(entry.Url);
            return host == site || host.EndsWith("." + site, StringComparison.Ordinal);
        });
        return new(NativeSessionAuthority.Replacing(turn.Basis, remaining), SyncStaging.Deletion,
            Stores: store => store.RemoveSite(SpaceId, site));
    }

    #endregion
}
