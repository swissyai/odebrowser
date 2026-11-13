import Foundation

extension StoredHistoryChanged {
    @MainActor func apply(to state: CoreState) {
        state.storedHistoryRevision = max(state.storedHistoryRevision, revision)
    }
}
