using OdeCore.Application;

namespace OdeCore.Contracts;

/// Forgets the Space's Boost for `Site`, spelled as `SiteBoost.SiteOf` spells
/// a host or any way it reads one. Nothing changes when there is none.
public sealed record RemoveSiteBoost(Guid WorkspaceId, Guid SpaceId, string Site) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        string site = SiteBoost.SiteOf(Site) ?? throw new Rejected(new InvalidBoostSite());
        return workspace.SettingSpace(turn.Basis, workspace.Editable(turn.Basis, SpaceId),
            settings => settings with { Boosts = settings.Boosts?.Removing(site) }, staging: null);
    }

    #endregion
}
