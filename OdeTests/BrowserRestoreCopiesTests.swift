import Foundation
import XCTest

@testable import Ode

/// Restoring an earlier copy of the session: the copies the core lists, the
/// request a running app leaves for its next launch, the restore window's
/// model, the missing-tabs banner's answers, and the launch after an unclean
/// exit. The file-level contracts of the copies are the core's own tests.
@MainActor
final class BrowserRestoreCopiesTests: XCTestCase {
    private func copy(
        _ name: String = "session-20261029T091203000Z-2s-9t.sqlite", held: Bool = false, updateTo: String? = nil,
        beforeRestore: Bool = false, spaces: Int = 2, tabs: Int = 9
    ) -> RecoveryCopy {
        RecoveryCopy(
            name: name, takenAt: Date(timeIntervalSince1970: 1_800_000_000), spaces: spaces, tabs: tabs, bytes: 4096,
            held: held, updateTo: updateTo, beforeRestore: beforeRestore)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    // MARK: - The copies

    func testEachCopySaysWhyItWasKeptAndWhatItHeld() {
        XCTAssertEqual(copy().reason, String(localized: "When Ode started"))
        XCTAssertEqual(copy(held: true).reason, String(localized: "Kept back when tabs went missing"))
        XCTAssertEqual(copy(updateTo: "0.9.4").reason, String(localized: "Before updating to 0.9.4"))
        XCTAssertEqual(copy(beforeRestore: true).reason, String(localized: "Before a restore"))
        XCTAssertTrue(copy(spaces: 1, tabs: 1).contents.contains(String(localized: "1 Space")))
        XCTAssertTrue(copy(spaces: 1, tabs: 1).contents.contains(String(localized: "1 tab")))
        XCTAssertTrue(copy().contents.contains(String(localized: "9 tabs")))
    }

    func testARequestToRestoreIsTakenOnceByTheNextLaunch() throws {
        let directory = try temporaryDirectory()
        XCTAssertNil(BrowserRecoveryCopies.takeRequest(in: directory))
        XCTAssertTrue(BrowserRecoveryCopies.requestRestore(copy(), in: directory))
        XCTAssertEqual(BrowserRecoveryCopies.takeRequest(in: directory), copy().name)
        // A launch that fails while restoring never repeats the restore.
        XCTAssertNil(BrowserRecoveryCopies.takeRequest(in: directory))
    }

    func testTheCoreListsTheCopiesItKeptAndARestoreKeepsTheSessionItReplaced() throws {
        let directory = try temporaryDirectory()
        // A first launch adopts a session; the two after it each keep a copy
        // of the session they open.
        do {
            let core = try OdeCore(configuration: AppConfiguration(storageDirectory: directory.path))
            try BrowserInstalledRelease.adopt(.preview, journalData: nil, into: core)
        }
        for _ in 0..<2 {
            let core = try OdeCore(configuration: AppConfiguration(storageDirectory: directory.path))
            _ = try BrowserCoreSessionAuthority.openStored(in: core, favicons: InMemoryBrowserFaviconStore())
        }
        let copies = BrowserRecoveryCopies.list(in: directory)
        XCTAssertFalse(copies.isEmpty)
        XCTAssertTrue(copies.allSatisfy { !$0.beforeRestore && !$0.held })

        try BrowserRecoveryCopies.restore(try XCTUnwrap(copies.last), in: directory)
        XCTAssertTrue(BrowserRecoveryCopies.list(in: directory).contains(where: \.beforeRestore))
        // The restored session opens.
        let reopened = try OdeCore(configuration: AppConfiguration(storageDirectory: directory.path))
        _ = try BrowserCoreSessionAuthority.openStored(in: reopened, favicons: InMemoryBrowserFaviconStore())
        XCTAssertTrue(BrowserRecoveryCopies.list(in: URL(fileURLWithPath: "/no-such-ode-directory")).isEmpty)
    }

    // MARK: - The restore window

    func testWhileTheBrowserRunsARestoreIsRequestedAndOdeOpensAgain() throws {
        let directory = try temporaryDirectory()
        var requested: [String] = []
        var relaunches = 0
        var actions = BrowserRestoreCopiesModel.Actions()
        actions.requestRestore = { copy, _ in
            requested.append(copy.name)
            return true
        }
        actions.relaunch = { relaunches += 1 }
        actions.restoreNow = { _, _ in XCTFail("A running browser never restores at once") }
        let held = copy("session-20261028T091203000Z-5s-159t.sqlite", held: true, spaces: 5, tabs: 159)
        let model = BrowserRestoreCopiesModel(
            directory: directory, timing: .relaunch, copies: [copy(), held], actions: actions)

        XCTAssertEqual(model.initialSelection, held.id)
        XCTAssertTrue(model.restore(held))
        XCTAssertEqual(requested, [held.name])
        XCTAssertEqual(relaunches, 1)
        XCTAssertNil(model.failure)
    }

    func testARequestThatCannotBeSavedNeitherQuitsNorChangesAnything() throws {
        let directory = try temporaryDirectory()
        var relaunches = 0
        var actions = BrowserRestoreCopiesModel.Actions()
        actions.requestRestore = { _, _ in false }
        actions.relaunch = { relaunches += 1 }
        let model = BrowserRestoreCopiesModel(directory: directory, timing: .relaunch, copies: [copy()], actions: actions)

        XCTAssertFalse(model.restore(copy()))
        XCTAssertEqual(relaunches, 0)
        XCTAssertNotNil(model.failure)
    }

    func testBeforeTheSessionOpensACopyIsRestoredAtOnce() throws {
        let directory = try temporaryDirectory()
        var restoredNow: [String] = []
        var finished: [String] = []
        var actions = BrowserRestoreCopiesModel.Actions()
        actions.restoreNow = { copy, _ in restoredNow.append(copy.name) }
        actions.relaunch = { XCTFail("No session is open to quit") }
        let model = BrowserRestoreCopiesModel(directory: directory, timing: .now, copies: [copy()], actions: actions)
        model.restored = { finished.append($0.name) }

        XCTAssertTrue(model.restore(copy()))
        XCTAssertEqual(restoredNow, [copy().name])
        XCTAssertEqual(finished, [copy().name])

        actions.restoreNow = { _, _ in throw Rejection.storageFromNewerApp(StorageFromNewerApp()) }
        let failing = BrowserRestoreCopiesModel(directory: directory, timing: .now, copies: [copy()], actions: actions)
        failing.restored = { _ in XCTFail("A failed restore does not finish") }
        XCTAssertFalse(failing.restore(copy()))
        XCTAssertEqual(failing.failure, String(localized: "That copy couldn't be restored. Nothing was changed."))
    }

    // MARK: - The missing-tabs banner

    func testTheBannerShowsTheHeldCopyUntilThePersonAnswers() throws {
        let directory = try temporaryDirectory()
        var kept = 0
        var shownRestores: [URL] = []
        let held = copy(held: true, spaces: 5, tabs: 159)
        let banner = BrowserHeldCopy(
            directory: directory, copies: [copy(), held], keep: { kept += 1 }, showRestore: { shownRestores.append($0) })
        XCTAssertEqual(banner.copy, held)
        XCTAssertNotNil(banner.message)

        banner.restoreThatCopy()
        XCTAssertEqual(shownRestores, [directory])
        XCTAssertNotNil(banner.copy, "Opening the restore window is not an answer")

        banner.keepThisSession()
        XCTAssertEqual(kept, 1)
        XCTAssertNil(banner.copy)
        XCTAssertNil(banner.message)
        banner.keepThisSession()
        XCTAssertEqual(kept, 1)

        let none = BrowserHeldCopy(directory: directory, copies: [copy()], keep: { XCTFail() }, showRestore: { _ in XCTFail() })
        XCTAssertNil(none.copy)
        none.keepThisSession()
        none.restoreThatCopy()
    }

    // MARK: - After an unclean exit

    func testALaunchAfterOneThatDidNotQuitCleanlyLeavesItsPagesToLoadWhenOpened() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func launch(_ outcome: BrowserLaunchHistory.Launch.Outcome) -> BrowserLaunchHistory.Launch {
            BrowserLaunchHistory.Launch(id: UUID(), startedAt: start, build: "1", outcome: outcome, safeMode: false)
        }
        XCTAssertFalse(BrowserLaunchHistory().newestEndedUncleanly)
        XCTAssertFalse(BrowserLaunchHistory(launches: [launch(.started), launch(.clean)]).newestEndedUncleanly)
        // A crash while starting, and one after the first window settled.
        XCTAssertTrue(BrowserLaunchHistory(launches: [launch(.started)]).newestEndedUncleanly)
        XCTAssertTrue(BrowserLaunchHistory(launches: [launch(.clean), launch(.finished)]).newestEndedUncleanly)
    }
}
