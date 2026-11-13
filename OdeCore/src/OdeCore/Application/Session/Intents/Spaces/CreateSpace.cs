using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Adds a Space after the others, with a profile of its own and one Start
/// Page tab. The core names it and gives it its symbol, accent and look; a
/// private workspace's Space never offers to save passwords. The window that
/// asked shows it, when that window is open over the workspace.
public sealed record CreateSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = Made(workspace, turn, SpaceId);
        // A new Space is the one its window shows next, on its only tab.
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId)).ShowSpace(space.Id).ShowTab(space.Id, space.Tabs[0].Id);
        return new(turn.Basis with { Spaces = [.. turn.Basis.Spaces, space] }, SyncStaging.Creation, followUp);
    }

    /// The Space `spaceId` that goes after the others of the session `turn`
    /// edits, from the workspace's template, with a profile of its own.
    /// Refused for a workspace that borrows its Spaces, an identity the
    /// session holds, or a session already at `SessionState.MaximumSpaces`.
    internal static SpaceState Made(NativeSessionAuthority workspace, SessionTurn turn, Guid spaceId) {
        workspace.RequireOwnedSpaces();
        if (turn.Basis.Space(spaceId) is not null) throw new Rejected(new SpaceAlreadyExists(spaceId));
        if (turn.Basis.Spaces.Count >= SessionState.MaximumSpaces) throw new Rejected(new SpaceLimitReached(SessionState.MaximumSpaces));
        return SpaceTemplate.For(workspace.Kind.IsPrivate)
            .Make(spaceId, turn.Ids.Next(), turn.Ids.Next, turn.Basis.Spaces.Count + 1, turn.Now);
    }

    #endregion
}
