import Foundation
import XCTest

@testable import Ode

final class BrowserDownloadDestinationTests: XCTestCase {
    @MainActor
    func testUnavailableSavedFolderIsRetainedForRecoveryInsteadOfFallingBackToDownloads() async {
        let preferences = BrowserPlatformDownloadPreferences.shared
        let spaceID = UUID()
        defer { preferences.clearDirectory(for: spaceID) }
        preferences.setDirectoryMetadata(bookmark: Data([1, 2, 3]), displayName: "Work Files", for: spaceID)
        let resolution = await BrowserPlatformDownloadDirectory.resolve(
            suggestedFilename: "report.txt", spaceID: spaceID)
        guard resolution is BrowserDownloadFolderUnavailable else {
            XCTFail("A broken saved folder must not silently redirect a download.")
            return
        }
        XCTAssertEqual(preferences.directoryDisplayName(for: spaceID), "Work Files")
    }

    func testUsesTheSuggestedFilenameWhenItIsAvailable() {
        let directory = URL(fileURLWithPath: "/Downloads", isDirectory: true)

        let destination = BrowserDownloadDestination.availableURL(
            suggestedFilename: "report.pdf",
            directory: directory,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination, directory.appendingPathComponent("report.pdf"))
    }

    func testAddsAStableNumericSuffixWithoutChangingTheExtension() {
        let directory = URL(fileURLWithPath: "/Downloads", isDirectory: true)
        let occupied = Set(["report.pdf", "report 1.pdf"])

        let destination = BrowserDownloadDestination.availableURL(
            suggestedFilename: "report.pdf",
            directory: directory,
            fileExists: { occupied.contains($0.lastPathComponent) }
        )

        XCTAssertEqual(destination, directory.appendingPathComponent("report 2.pdf"))
    }

    func testRemovesPathTraversalFromASuggestedFilename() {
        let directory = URL(fileURLWithPath: "/Downloads", isDirectory: true)

        let destination = BrowserDownloadDestination.availableURL(
            suggestedFilename: "../../secret.txt",
            directory: directory,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination, directory.appendingPathComponent("secret.txt"))
    }

    /// The core's `DownloadFilenameTests` pin the same table, so a file is
    /// named the same way on both sides.
    func testASuggestedNameIsSavedUnderTheCoresSafeName() {
        let names: [(suggested: String, expected: String)] = [
            ("report.pdf", "report.pdf"),
            ("..\\..\\.pay\u{0}load.txt. ", "payload.txt"),
            ("../..", "download"),
            ("", "download"),
            ("folder/in\u{202E}exe.pdf", "inexe.pdf"),
            ("C:\\Users\\someone\\file.txt", "file.txt"),
            ("a:b.txt", "a_b.txt"),
            ("  .hidden. ", "hidden"),
            ("e\u{0301}te\u{0301}.txt", "\u{00E9}t\u{00E9}.txt"),
            ("invoice.pdf\u{202E}ppa", "invoice.pdfppa"),
            ("\u{FEFF}\u{200B}", "download"),
            ("tab\there\u{0085}.txt", "tabhere.txt"),
            ("\u{00A0}name\u{00A0}.txt\u{00A0}", "name\u{00A0}.txt"),
            ("archive.tar.gz", "archive.tar.gz"),
            (String(repeating: "a", count: 300) + ".txt", String(repeating: "a", count: 236) + ".txt"),
            (String(repeating: "\u{00E9}", count: 200) + ".pdf", String(repeating: "\u{00E9}", count: 118) + ".pdf"),
            (
                String(repeating: "a", count: 250) + "." + String(repeating: "b", count: 40),
                String(repeating: "a", count: 240)
            ),
            (
                String(repeating: "\u{1F468}\u{200D}\u{1F469}", count: 40) + ".png",
                String(repeating: "\u{1F468}\u{1F469}", count: 29) + "\u{1F468}.png"
            ),
        ]
        for (suggested, expected) in names {
            let saved = BrowserDownloadDestination.safeFilename(from: suggested)
            XCTAssertEqual(saved, expected, suggested.debugDescription)
        }
        // A name longer than the core reads keeps its end, and so its extension.
        XCTAssertEqual(
            BrowserDownloadDestination.safeFilename(from: String(repeating: "a", count: 10_000) + ".pdf"),
            String(repeating: "a", count: 236) + ".pdf")
    }

    @MainActor
    func testDownloadPreferencesStayLocalToTheirSpace() throws {
        let suiteName = "BrowserDownloadDestinationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = BrowserPlatformDownloadPreferences(defaults: defaults)
        let work = UUID()
        let personal = UUID()

        preferences.setAsksWhereToSave(true, for: work)
        preferences.setDirectoryMetadata(
            bookmark: Data([0x43, 0x52, 0x45, 0x53, 0x54]),
            displayName: "Work Downloads",
            for: work
        )

        XCTAssertTrue(preferences.asksWhereToSave(for: work))
        XCTAssertEqual(preferences.directoryDisplayName(for: work), "Work Downloads")
        XCTAssertFalse(preferences.asksWhereToSave(for: personal))
        XCTAssertNil(preferences.directoryDisplayName(for: personal))
    }
}
