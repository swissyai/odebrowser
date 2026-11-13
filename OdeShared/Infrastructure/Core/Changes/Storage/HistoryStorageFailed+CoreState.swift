import Foundation

extension HistoryStorageFailed {
    @MainActor func apply(to state: CoreState) {
        state.historyStorageFailure = self
        record()
    }

    /// Safe to record even during native handle destruction, when no further
    /// change drain can reach the read model.
    nonisolated func record() {
        DiagnosticLog.history.error(
            "History storage operation \(operation) failed: \(reason); unsaved queued operations: \(unsavedWrites)."
        )
    }
}
