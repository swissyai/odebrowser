import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import Ode

final class BrowserDownloadFileTransferTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ode-download-transfer-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testOnlyAFinishedFileStillOnDiskIsHandedOver() throws {
        let file = folder.appending(path: "Trail photo.png")
        try Data([0x89, 0x50]).write(to: file)
        let profileID = UUID()

        let finished = DownloadState.fixture(profileID: profileID, destination: file, progress: 1, phase: .finished)
        XCTAssertEqual(finished.savedFileURL(), file)
        XCTAssertFalse(finished.isSavedFileMissing())

        let downloading = DownloadState.fixture(profileID: profileID, destination: file, phase: .downloading)
        XCTAssertNil(downloading.savedFileURL())
        XCTAssertFalse(downloading.isSavedFileMissing())

        let failed = DownloadState.fixture(profileID: profileID, destination: file, phase: .failed)
        XCTAssertNil(failed.savedFileURL())

        try FileManager.default.removeItem(at: file)
        XCTAssertNil(finished.savedFileURL())
        XCTAssertTrue(finished.isSavedFileMissing())

        let web = DownloadState.fixture(
            profileID: profileID, destination: URL(string: "https://example.com/file.png"), phase: .finished)
        XCTAssertNil(web.savedFileURL { _ in true })
        XCTAssertFalse(web.isSavedFileMissing { _ in true })
    }

    @MainActor
    func testDraggingAFileCarriesItsFileURLAndName() async throws {
        let file = folder.appending(path: "Quarterly report.pdf")
        try Data("%PDF-1.4".utf8).write(to: file)

        let item = BrowserDownloadFileTransfer.dragItem(for: file)

        XCTAssertEqual(item.suggestedName, "Quarterly report.pdf")
        XCTAssertTrue(item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        let loaded: URL? = await withCheckedContinuation { continuation in
            _ = item.loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: (object as? NSURL) as URL?)
            }
        }
        XCTAssertEqual(loaded?.standardizedFileURL, file.standardizedFileURL)
    }

    @MainActor
    func testCopyingAFilePutsItOnThePasteboardAsFinderDoes() throws {
        let file = folder.appending(path: "Meeting notes.txt")
        try Data("notes".utf8).write(to: file)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ode-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("earlier", forType: .string)

        XCTAssertTrue(BrowserDownloadFileTransfer.copy(file, to: pasteboard))

        XCTAssertNil(pasteboard.string(forType: .string))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.standardizedFileURL), [file.standardizedFileURL])
        XCTAssertTrue(pasteboard.types?.contains(.fileURL) ?? false)
    }
}
