import XCTest

@testable import Ode

final class BrowserDownloadCenterRecordTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ode-download-records-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// A record of a file the center saved at `fileURL`, finished unless `finishes` is false.
    @MainActor
    private func record(
        in center: BrowserDownloadCenter, profileID: UUID, at fileURL: URL, finishes: Bool = true
    ) -> UUID {
        let itemID = center.begin(profileID: profileID, filename: fileURL.lastPathComponent)
        center.setDestination(fileURL, for: itemID)
        if finishes { center.send(FinishDownload(downloadID: itemID, finalByteCount: 5)) }
        return itemID
    }

    @MainActor
    func testMovingAFinishedFileToTheTrashClearsItsRecord() throws {
        let center = BrowserDownloadCenter()
        let profileID = UUID()
        let file = folder.appending(path: "Design assets.zip")
        try Data("bytes".utf8).write(to: file)
        let itemID = record(in: center, profileID: profileID, at: file)
        var trashed: [URL] = []

        XCTAssertTrue(center.moveToTrash(itemID) { trashed.append($0) })

        XCTAssertEqual(trashed, [file])
        XCTAssertNil(center.item(itemID))
    }

    @MainActor
    func testAFileTheTrashRefusesKeepsItsRecord() throws {
        let center = BrowserDownloadCenter()
        let file = folder.appending(path: "Locked.pdf")
        try Data("bytes".utf8).write(to: file)
        let itemID = record(in: center, profileID: UUID(), at: file)

        XCTAssertFalse(center.moveToTrash(itemID) { _ in throw CocoaError(.fileWriteNoPermission) })

        XCTAssertNotNil(center.item(itemID))
    }

    @MainActor
    func testAFileAlreadyGoneOnlyLeavesTheList() {
        let center = BrowserDownloadCenter()
        let itemID = record(in: center, profileID: UUID(), at: folder.appending(path: "Gone.txt"))
        var trashed: [URL] = []

        XCTAssertTrue(center.moveToTrash(itemID) { trashed.append($0) })

        XCTAssertTrue(trashed.isEmpty)
        XCTAssertNil(center.item(itemID))
    }

    @MainActor
    func testADownloadStillRunningIsNeverTrashed() throws {
        let center = BrowserDownloadCenter()
        let file = folder.appending(path: "Partial.mov")
        try Data("bytes".utf8).write(to: file)
        let itemID = record(in: center, profileID: UUID(), at: file, finishes: false)
        var trashed: [URL] = []

        XCTAssertFalse(center.moveToTrash(itemID) { trashed.append($0) })

        XCTAssertTrue(trashed.isEmpty)
        XCTAssertEqual(center.item(itemID)?.phase, .downloading)
    }

    @MainActor
    func testClearingDropsEndedDownloadsOfTheSpaceOnly() throws {
        let center = BrowserDownloadCenter()
        let profileID = UUID()
        let file = folder.appending(path: "Kept.pdf")
        try Data("bytes".utf8).write(to: file)
        let finished = record(in: center, profileID: profileID, at: file)
        let canceled = record(in: center, profileID: profileID, at: folder.appending(path: "c.zip"), finishes: false)
        center.send(CancelDownload(downloadID: canceled, message: "Canceled."))
        let failed = record(in: center, profileID: profileID, at: folder.appending(path: "f.zip"), finishes: false)
        center.send(FailDownload(downloadID: failed, reason: nil, message: "The connection was lost."))
        let running = record(in: center, profileID: profileID, at: folder.appending(path: "r.mov"), finishes: false)
        let blocked = center.begin(profileID: profileID, filename: "b.zip")
        center.send(BlockAutomaticDownload(downloadID: blocked))
        let elsewhere = record(in: center, profileID: UUID(), at: folder.appending(path: "e.pdf"))

        XCTAssertEqual(center.clearEnded(for: profileID), 3)

        XCTAssertEqual(Set(center.items(for: profileID).map(\.id)), [running, blocked])
        XCTAssertNotNil(center.item(elsewhere))
        XCTAssertNil(center.item(finished))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(center.clearEnded(for: profileID), 0)
    }

    func testOnlyEndedDownloadsAreClearable() {
        let profileID = UUID()
        let clearable = DownloadPhase.all.filter {
            BrowserDownloadCenter.isClearable(.fixture(profileID: profileID, phase: $0))
        }
        XCTAssertEqual(Set(clearable.map(\.name)), ["finished", "canceled", "failed"])
    }
}
