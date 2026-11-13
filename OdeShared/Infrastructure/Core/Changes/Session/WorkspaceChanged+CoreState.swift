import Foundation

extension WorkspaceChanged {
    @MainActor func apply(to state: CoreState) {
        state.workspaces[workspaceID]?.apply(self)
        state.touch(workspaceID)
    }

    @MainActor func apply(to core: OdeCore, in batch: inout CoreChangeBatch) {
        batch.notificationAccessChanged = true
        apply(to: core.state)
    }
}
