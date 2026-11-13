using OdeCore.Application;

namespace OdeCore.Contracts;

/// Removes the history entry for one address from a Space, and from every
/// Space of its group, whose history they share, with every visit to it this
/// device keeps for them. The address is compared the way history records it,
/// without its fragment, so an address history never records removes nothing.
public sealed record RemoveHistoryAddress(Guid WorkspaceId, Guid SpaceId, string Address) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var address = new WebAddress(Address).Normalized;
        var spaces = workspace.GroupEditable(turn.Basis, SpaceId);
        var remaining = spaces.Select(space => space.WithoutHistory(entry => address is not null && entry.Url == address));
        return new(turn.Basis.Replacing([.. remaining]), SyncStaging.Deletion,
            Stores: address is null ? null : store => {
                foreach (var space in spaces) store.Remove(space.Id, address);
            });
    }

    #endregion
}
