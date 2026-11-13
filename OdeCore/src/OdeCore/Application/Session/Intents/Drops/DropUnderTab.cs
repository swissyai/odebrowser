using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Drops the lift on the open tab `TabId`, nesting it there after the tabs
/// nested there already, as `NestTabs` nests a selection. Refused with
/// `InvalidFolderPlacement` when `TabId` cannot hold nested tabs, or is in the
/// lift or nested under it.
public sealed record DropUnderTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid TabId)
    : SidebarDrop(WorkspaceId, WindowId, SpaceId, Selection) {
    #region Actions - Session

    internal override SessionIntent Committed(NativeSessionAuthority.Lift lift, IIdSource ids) =>
        new NestTabs(WorkspaceId, WindowId, SpaceId, Selection, TabId);

    #endregion
}
