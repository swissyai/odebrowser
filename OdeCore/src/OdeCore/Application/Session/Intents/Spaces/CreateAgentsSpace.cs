using OdeCore.Contracts;

namespace OdeCore.Application;

/// Adds the Space agents work in when the person turns them on: a Space as
/// `CreateSpace` makes one, named Agents, which no window is asked to show.
/// Only the core sends it.
internal sealed record CreateAgentsSpace(Guid WorkspaceId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Static Variables

    public const string Name = "Agents";

    #endregion

    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = CreateSpace.Made(workspace, turn, SpaceId);
        space = space with { Settings = space.Settings with { Name = Name } };
        return new(turn.Basis with { Spaces = [.. turn.Basis.Spaces, space] }, SyncStaging.Creation);
    }

    #endregion
}
