import Foundation
@testable import Ode

@MainActor
final class SuspendingBrowserSpaceDataDeleter: BrowserSpaceDataDeleting {
    private let core: OdeCore
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var deletionContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    init(core: OdeCore) {
        self.core = core
    }

    func deleteData(for deletion: SpaceDeletionState) async throws {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            deletionContinuation = continuation
        }
        for profileID in deletion.erasing { try await core.eraseProfile(profileID) }
    }

    func waitUntilDeletionStarts() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishDeletion() {
        deletionContinuation?.resume()
        deletionContinuation = nil
    }
}

extension OdeCore {
    /// Has every engine erase the profile `profileID`, which keeps nothing
    /// on disk in a test, as the app's deleter does before the Space may go.
    func eraseProfile(_ profileID: UUID) async throws {
        guard await deleteData(DeleteProfileData(requestID: UUID(), profileID: profileID, ephemeral: true))
        else { throw BrowserSpaceDeletionError.dataNotErased }
    }
}
