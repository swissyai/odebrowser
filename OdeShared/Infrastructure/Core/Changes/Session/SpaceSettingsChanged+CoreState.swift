import Foundation

extension SpaceSettingsChanged {
    @MainActor func apply(to state: CoreState) {
        state.space(spaceID, in: workspaceID)?.apply(self)
        state.touch(workspaceID)
    }

    @MainActor func apply(to core: OdeCore, in batch: inout CoreChangeBatch) {
        batch.notificationAccessChanged = true
        apply(to: core.state)
    }
}
