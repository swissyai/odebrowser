import XCTest

@testable import Ode

/// The automatic export: when a check writes, that it writes nothing while a
/// Space is locked or while it is turned off, that the person's choices are
/// remembered, and that an export reads back as the workspace it wrote.
@MainActor
final class BrowserAutomaticExportTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ode-automatic-export-\(UUID().uuidString)", isDirectory: true)
        suiteName = "ode-automatic-export-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAnExportIsDueDailyAndAfterAChangeAtMostHourly() {
        let written = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(BrowserAutomaticExport.due(at: written, lastExportedAt: nil), .always)
        XCTAssertEqual(
            BrowserAutomaticExport.due(at: written.addingTimeInterval(59 * 60), lastExportedAt: written), .none)
        XCTAssertEqual(
            BrowserAutomaticExport.due(at: written.addingTimeInterval(60 * 60), lastExportedAt: written), .ifChanged)
        XCTAssertEqual(
            BrowserAutomaticExport.due(at: written.addingTimeInterval(23 * 60 * 60), lastExportedAt: written),
            .ifChanged)
        XCTAssertEqual(
            BrowserAutomaticExport.due(at: written.addingTimeInterval(24 * 60 * 60), lastExportedAt: written), .always)
        XCTAssertEqual(
            BrowserAutomaticExport.due(at: written.addingTimeInterval(-60), lastExportedAt: written), .always)
    }

    func testAnExportReadsBackAsTheWorkspaceAndTheChoicesAreRemembered() async throws {
        let browser = BrowserStore(seed: .preview)
        let export = BrowserAutomaticExport(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), defaults: defaults, defaultFolder: folder)

        await export.exportNow()

        XCTAssertNil(export.failure)
        let written = try XCTUnwrap(export.lastExportURL)
        XCTAssertEqual(written.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: written.path).sorted(),
            ExportFormat.all.map(\.fileName).sorted())
        let read = try browser.core.query(
            ReadArchive(path: written.appendingPathComponent(ExportFormat.browserData.fileName).path))
        XCTAssertEqual(read.spaces.map(\.settings.name), browser.spaceModels.map(\.settings.name))
        XCTAssertEqual(read.spaces.map(\.tabs.count), browser.spaceModels.map(\.tabs.models.count))

        let chosen = folder.appendingPathComponent("Chosen", isDirectory: true)
        export.setFolder(chosen)
        export.setEnabled(false)
        let relaunched = BrowserAutomaticExport(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), defaults: defaults, defaultFolder: folder)
        XCTAssertEqual(relaunched.folder.path, chosen.path)
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertEqual(relaunched.lastExportedAt, export.lastExportedAt)
        XCTAssertEqual(relaunched.lastExportURL?.path, written.path)
    }

    func testAChangeWaitsForTheHourAndAnUnchangedWorkspaceWritesNothingUntilTheDayIsOut() async throws {
        let browser = BrowserStore(seed: .preview)
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let export = BrowserAutomaticExport(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), defaults: defaults, defaultFolder: folder,
            now: { now })
        await export.check()
        XCTAssertEqual(try exports().count, 1)

        browser.openNativeTab(.gettingStarted, placement: .saved)
        now.addTimeInterval(30 * 60)
        await export.check()
        XCTAssertEqual(try exports().count, 1)

        now.addTimeInterval(45 * 60)
        await export.check()
        XCTAssertEqual(try exports().count, 2)
        XCTAssertEqual(export.lastExportedAt, now)

        now.addTimeInterval(2 * 60 * 60)
        await export.check()
        XCTAssertEqual(try exports().count, 2)

        now.addTimeInterval(24 * 60 * 60)
        await export.check()
        XCTAssertEqual(try exports().count, 3)
    }

    func testNothingIsWrittenWhileTurnedOffOrWhileASpaceIsLocked() async throws {
        var session = SessionState.Seed.preview
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(seed: session)
        let access = BrowserSpaceAccessController(authenticator: AcceptingAuthenticator())
        browser.attachSpaceAccess(access)
        let export = BrowserAutomaticExport(
            browser: browser, spaceAccess: access, defaults: defaults, defaultFolder: folder)

        await export.check()
        await export.exportNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertNil(export.lastExportedAt)

        let unlocked = await access.unlock(browser.spaceModels[0])
        XCTAssertTrue(unlocked)
        export.setEnabled(false)
        await export.check()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))

        export.setEnabled(true)
        await export.check()
        XCTAssertEqual(try exports().count, 1)
    }

    /// The dated exports in the folder.
    private func exports() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }
    }
}
