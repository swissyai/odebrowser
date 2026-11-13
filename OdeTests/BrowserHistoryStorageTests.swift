import Foundation
import SQLite3
import XCTest

@testable import Ode

@MainActor
final class BrowserHistoryStorageTests: XCTestCase {
    func testNativeCloseReturnsTheUnsavedHistoryOutcomeBeforeDestroyingTheHandle() async throws {
        try await withStoredHistory { core, store, directory in
            await core.flushPendingSaves()
            var connection: OpaquePointer?
            let path = directory.appendingPathComponent("history.sqlite").path
            XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
            defer { sqlite3_close(connection) }
            let trigger =
                "CREATE TRIGGER refuse_history BEFORE INSERT ON place BEGIN SELECT RAISE(ABORT,'fixture refusal'); END"
            XCTAssertEqual(sqlite3_exec(connection, trigger, nil, nil, nil), SQLITE_OK)
            let at = Date(timeIntervalSince1970: 1_793_650_000)
            let visit = HistoryEntryState(
                id: UUID(), url: "https://fixture.example/unsaved", title: "Unsaved fixture",
                firstVisitedAt: at, lastVisitedAt: at, visitCount: 1)
            try core.send(
                ImportSpaces(
                    workspaceID: store.family.workspaceID, windowID: store.windowID,
                    spaces: [SpaceState.Seed(name: "Imported", tabs: [], history: [visit])]))

            let closed = try core.query(CloseHistoryStorage())
            let failure = try XCTUnwrap(closed.failure)
            XCTAssertEqual(failure.operation, .close)
            XCTAssertEqual(failure.reason, .unavailable)
            XCTAssertGreaterThan(failure.unsavedWrites, 0)
            failure.record()
            XCTAssertNil(core.state.storageFailure)
        }
    }

    func testHistoryReaderPropagatesStorageRefusalAndTheNativeBoundaryRecordsItsReason() async throws {
        try await withStoredHistory { core, store, directory in
            let workspace = store.family.workspaceID
            let space = try XCTUnwrap(store.shownSpace).id
            await core.flushPendingSaves()
            let reader = BrowserHistoryReader(core: core, workspaceID: workspace)
            _ = try reader.places(in: space, matching: "", limit: 10)

            var connection: OpaquePointer?
            let path = directory.appendingPathComponent("history.sqlite").path
            XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
            defer { sqlite3_close(connection) }
            XCTAssertEqual(sqlite3_exec(connection, "DROP TABLE place", nil, nil, nil), SQLITE_OK)

            XCTAssertThrowsError(try reader.places(in: space, matching: "", limit: 10)) { error in
                guard let rejection = error as? Rejection, case .storageUnreadable = rejection else {
                    return XCTFail("Expected a storage refusal, not empty or partial history: \(error)")
                }
            }
            core.drain()
            XCTAssertEqual(core.state.historyStorageFailure?.operation, .read)
            XCTAssertEqual(core.state.historyStorageFailure?.reason, .unavailable)
            XCTAssertNil(core.state.storageFailure, "A history issue must not report that the session save failed.")
        }
    }

    private func withStoredHistory(
        _ perform: @MainActor (OdeCore, BrowserStore, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        weak var releasedCore: OdeCore?
        // End every owner before removing its SQLite files, not from a fixture
        // deinit whose stored core still has live connections.
        func run() async throws {
            let core = try OdeCore(configuration: AppConfiguration(storageDirectory: directory.path))
            releasedCore = core
            try BrowserInstalledRelease.adopt(.preview, journalData: nil, into: core)
            let favicons = InMemoryBrowserFaviconStore()
            let stored = try BrowserCoreSessionAuthority.openStored(in: core, favicons: favicons)
            let store = BrowserStore.production(
                stored: stored, core: core, favicons: favicons, credentialVault: InMemoryCredentialVault())
            try await perform(core, store, directory)
        }
        try await run()
        // Page release and the wake relay can finish on the next main turn.
        for _ in 0..<100 where releasedCore != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(releasedCore)
        if releasedCore == nil { try FileManager.default.removeItem(at: directory) }
    }
}
