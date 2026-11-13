using OdeCore.Application;

namespace OdeCore.Contracts;

/// Keeps `Boost` as the Space's Boost for its site, in place of the one it
/// had, as the Boost rules normalize it. Refused with `InvalidBoostSite` when
/// it names no site, and with `BoostLimitReached` when the Space keeps as many
/// Boosts as it may and none for this site.
public sealed record SetSiteBoost(Guid WorkspaceId, Guid SpaceId, SiteBoost Boost) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var boost = Boost.Normalized() ?? throw new Rejected(new InvalidBoostSite());
        return workspace.SettingSpace(turn.Basis, workspace.Editable(turn.Basis, SpaceId),
            settings => settings with { Boosts = (settings.Boosts ?? new([])).Setting(boost) }, staging: null);
    }

    #endregion
}
