import AppKit
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit
import XCTest

@testable import Ode

final class BrowserDownloadTransferTests: XCTestCase {
    @MainActor
    func testNativeSavePreservesDisplayedPDFBytesDestinationConsentAndProfileOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-native-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
        let source = URL(string: "https://pdf.crest.test/authenticated/redirected")!
        let destination = root.appending(path: "chosen.pdf")
        let data = try nativeSavePDFFixture()
        var destinationRequests = 0
        let center = BrowserDownloadCenter(resolveDownloadDestination: { filename, spaceID, forcesPrompt in
            destinationRequests += 1
            XCTAssertEqual(filename, "displayed.pdf")
            XCTAssertEqual(spaceID, assignment.spaceID)
            XCTAssertFalse(forcesPrompt)
            return .destination(destination, securityScopedURL: nil)
        })
        let itemID = await center.saveData(
            data, suggestedFilename: "../displayed.pdf", mimeType: "application/pdf",
            originatingURL: source, assignment: assignment, spaceName: "Private")
        let item = try XCTUnwrap(center.items(for: assignment.profileID).first)
        XCTAssertEqual(destinationRequests, 1)
        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.phase, .finished)
        XCTAssertEqual(item.filename, "chosen.pdf")
        XCTAssertTrue(center.items(for: UUID()).isEmpty)
        let saved = try Data(contentsOf: destination)
        XCTAssertEqual(saved, data)
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: saved as CFData)!))
        XCTAssertEqual(document.numberOfPages, 1)
        let quarantine = try XCTUnwrap(
            destination.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        XCTAssertEqual(quarantine[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
    }

    @MainActor
    func testNativeSaveReportsDestinationCancellationUnavailabilityAndWriteFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-native-save-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let occupied = root.appending(path: "occupied.pdf")
        let original = Data("Existing user file".utf8)
        try original.write(to: occupied)
        let resolutions: [any BrowserPlatformDownloadResolution] = [
            .cancelled, .unavailable, .destination(occupied, securityScopedURL: nil),
        ]
        for (index, resolution) in resolutions.enumerated() {
            let center = BrowserDownloadCenter(resolveDownloadDestination: { _, _, _ in resolution })
            await center.saveData(
                try nativeSavePDFFixture(), suggestedFilename: "displayed.pdf", mimeType: "application/pdf",
                originatingURL: URL(string: "https://pdf.crest.test/")!,
                assignment: BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID()), spaceName: "Work")
            let item = try XCTUnwrap(center.items.first)
            if index == 0 {
                guard item.phase == .canceled else { return XCTFail("Destination cancellation must remain canceled") }
            } else {
                guard item.phase == .failed else { return XCTFail("Destination errors must be visible") }
                XCTAssertFalse(item.message?.isEmpty ?? true)
            }
        }
        XCTAssertEqual(try Data(contentsOf: occupied), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["occupied.pdf"])
    }

    @MainActor
    func testNativeSaveRequiresApprovalForDeceptiveFilenameBeforeSelectingDestination() async throws {
        var approvalRequests = 0
        var destinationRequests = 0
        let center = BrowserDownloadCenter(
            approveRiskyDownload: { assessment, _, spaceName, _ in
                approvalRequests += 1
                XCTAssertTrue(assessment.reasons.contains(.deceptiveFilename))
                XCTAssertEqual(spaceName, "Work")
                return false
            },
            resolveDownloadDestination: { _, _, _ in
                destinationRequests += 1
                return .cancelled
            })
        await center.saveData(
            try nativeSavePDFFixture(), suggestedFilename: "invoice\u{202E}fdp.sh", mimeType: "application/pdf",
            originatingURL: URL(string: "https://pdf.crest.test/")!,
            assignment: BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID()), spaceName: "Work")
        XCTAssertEqual(approvalRequests, 1)
        XCTAssertEqual(destinationRequests, 0)
        guard case .canceled = center.items.first?.phase else { return XCTFail("Rejected save must be canceled") }
    }

    @MainActor
    func testNativeSaveCannotWriteAfterCancellationOrOwningSpaceRemovalWhileChoosingDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-native-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for removesSpace in [false, true] {
            var reply: CheckedContinuation<any BrowserPlatformDownloadResolution, Never>?
            let center = BrowserDownloadCenter(resolveDownloadDestination: { _, _, _ in
                await withCheckedContinuation { reply = $0 }
            })
            let assignment = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
            let data = try nativeSavePDFFixture()
            let saving = Task {
                await center.saveData(
                    data, suggestedFilename: "displayed.pdf", mimeType: "application/pdf",
                    originatingURL: URL(string: "https://pdf.crest.test/")!,
                    assignment: assignment, spaceName: "Work")
            }
            try await waitUntil(timeout: .seconds(5)) { reply != nil }
            let item = try XCTUnwrap(center.items.first)
            // Another Space's cleanup must not cancel or reassign this save.
            center.deleteRecords(profileID: UUID(), spaceID: UUID())
            XCTAssertEqual(center.items.first?.id, item.id)
            if removesSpace {
                center.deleteRecords(profileID: assignment.profileID, spaceID: assignment.spaceID)
            } else {
                center.cancel(item.id)
            }
            reply?.resume(returning: .destination(root.appending(path: "late.pdf"), securityScopedURL: nil))
            _ = await saving.value
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            if removesSpace {
                XCTAssertTrue(center.items.isEmpty)
            } else {
                guard case .canceled = center.items.first?.phase else {
                    return XCTFail("Late consent resurrected a canceled save")
                }
            }
        }
    }

    private func nativeSavePDFFixture() throws -> Data {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.fill(CGRect(x: 10, y: 10, width: 25, height: 25))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    @MainActor
    private func downloadingPage(
        destination: @escaping @MainActor (String) -> URL
    ) async throws -> (browser: BrowserStore, page: BrowserPage, kept: [AnyObject], download: () async throws -> Void) {
        let space = try XCTUnwrap(SessionState.Seed.preview.spaces.first)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let permissions = BrowserSitePermissionCenter(core: browser.core)
        let prompts = BrowserDownloadPrompts(
            core: browser.core, approve: { _, _ in false },
            resolveDestination: { filename, _, _ in .destination(destination(filename), securityScopedURL: nil) })
        let opened = try XCTUnwrap(browser.openWebKitPage(in: space.id, for: nil))
        let page = BrowserPage(
            corePage: opened.core, webKitPage: opened.webKit, dialogPresenter: BrowserDialogPresenter(),
            downloadCenter: BrowserDownloadCenter(core: browser.core), permissionCenter: permissions,
            spaceID: space.id, profileID: space.profileID, spaceName: space.settings.name)
        let web = page.webView
        let url = try XCTUnwrap(URL(string: "https://downloads.crest.test/"))
        web.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: """
                <title>Downloads</title><script>
                window.download = () => {
                  const link = document.createElement('a');
                  link.href = 'data:text/plain;base64,aGVsbG8=';
                  link.download = 'hello.txt';
                  link.click();
                };
                </script>
                """)
        try await waitUntil(timeout: .seconds(5)) { web.url == url && !web.isLoading }
        permissions.setDecision(
            .grantPersistently, for: .automaticDownloads, origin: try XCTUnwrap(SiteOrigin(url: url)), in: space.id)
        return (
            browser, page, [prompts, permissions],
            {
                _ = try await web.callAsyncJavaScript(
                    "window.download();", arguments: [:], in: nil, contentWorld: .page)
            }
        )
    }

    @MainActor
    func testTwoWebDownloadsSettledOnOneNameBothLand() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-download-collision-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Both files are settled on the same name, as two downloads of one
        // name are when neither has landed yet.
        let (browser, page, kept, download) = try await downloadingPage { root.appending(path: $0) }
        defer {
            page.release(keepingState: false)
            withExtendedLifetime(kept) {}
        }

        try await download()
        try await download()
        try await waitUntil(timeout: .seconds(5)) {
            browser.core.state.downloads.filter { $0.phase == .finished }.count == 2
        }

        let downloads = browser.core.state.downloads
        XCTAssertEqual(
            Set(downloads.compactMap(\.destinationURL).map(\.lastPathComponent)), ["hello.txt", "hello 1.txt"])
        XCTAssertEqual(Set(downloads.map(\.filename)), ["hello.txt", "hello 1.txt"])
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "hello.txt")), Data("hello".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "hello 1.txt")), Data("hello".utf8))
    }

    @MainActor
    func testAWebDownloadWhoseMoveFailsKeepsItsStagedFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-download-unmovable-\(UUID())")
        let locked = root.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let staging = try BrowserDownloadTransfer.stagingDirectory()
        let stagedBefore = Set(try FileManager.default.contentsOfDirectory(atPath: staging.path))
        let (browser, page, kept, download) = try await downloadingPage { locked.appending(path: $0) }
        defer {
            page.release(keepingState: false)
            withExtendedLifetime(kept) {}
        }

        try await download()
        try await waitUntil(timeout: .seconds(5)) { browser.core.state.downloads.contains { $0.phase == .failed } }

        let failed = try XCTUnwrap(browser.core.state.downloads.first { $0.phase == .failed })
        XCTAssertEqual(failed.failure, .fileAccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locked.appending(path: "hello.txt").path))
        let staged = Set(try FileManager.default.contentsOfDirectory(atPath: staging.path)).subtracting(stagedBefore)
            .filter { $0.hasSuffix("-hello.txt") }
        let stagedFile = staging.appending(path: try XCTUnwrap(staged.first))
        defer { try? FileManager.default.removeItem(at: stagedFile) }
        XCTAssertEqual(staged.count, 1)
        XCTAssertEqual(try Data(contentsOf: stagedFile), Data("hello".utf8))
    }

    func testStagingURLLivesInsideTheAppOwnedDirectory() {
        let directory = URL(fileURLWithPath: "/Application Support/Crest/Download Staging", isDirectory: true)
        let itemID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let url = BrowserDownloadTransfer.stagingURL(
            itemID: itemID,
            suggestedFilename: "report.pdf",
            directory: directory
        )

        XCTAssertEqual(url.deletingLastPathComponent(), directory)
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(url.lastPathComponent.contains(itemID.uuidString))
    }

    func testFinishingMovesTheStagedFileToItsVisibleDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = directory.appendingPathComponent("staging/source.txt")
        let destination = directory.appendingPathComponent("Downloads/report.txt")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("hello".utf8).write(to: staging)

        try BrowserDownloadTransfer.finish(from: staging, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
    }

    func testTwoStagedFilesFinishingUnderOneNameBothLand() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = directory.appendingPathComponent("staging/first.txt")
        let second = directory.appendingPathComponent("staging/second.txt")
        let destination = directory.appendingPathComponent("Downloads/report.txt")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        // Both were settled on the same name before either landed.
        let firstLanded = try BrowserDownloadTransfer.finish(from: first, toFreeNameFor: destination)
        let secondLanded = try BrowserDownloadTransfer.finish(from: second, toFreeNameFor: destination)

        XCTAssertEqual(firstLanded, destination)
        XCTAssertEqual(secondLanded, destination.deletingLastPathComponent().appendingPathComponent("report 1.txt"))
        XCTAssertEqual(try Data(contentsOf: firstLanded), Data("one".utf8))
        XCTAssertEqual(try Data(contentsOf: secondLanded), Data("two".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.deletingLastPathComponent().path), [])
    }

    func testAMoveThatFailsLeavesTheStagedFileInPlace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = directory.appendingPathComponent("staging/source.txt")
        let locked = directory.appendingPathComponent("locked", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(
            try BrowserDownloadTransfer.finish(
                from: staging, toFreeNameFor: locked.appendingPathComponent("report.txt")))

        XCTAssertEqual(try Data(contentsOf: staging), Data("hello".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: locked.path), [])
    }

    func testFinishingAWebDownloadAppliesSystemQuarantineMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = directory.appendingPathComponent("staging/source.txt")
        let destination = directory.appendingPathComponent("Downloads/report.txt")
        let sourceURL = try XCTUnwrap(URL(string: "https://downloads.example/report.txt"))
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("hello".utf8).write(to: staging)

        try BrowserDownloadTransfer.finish(
            from: staging,
            to: destination,
            quarantine: BrowserDownloadQuarantine(
                sourceURL: sourceURL,
                timestamp: Date(timeIntervalSince1970: 1_000),
                agentName: "Ode Tests",
                agentBundleIdentifier: "com.odebrowser.ode.tests"
            )
        )

        let properties = try destination.resourceValues(forKeys: [.quarantinePropertiesKey])
            .quarantineProperties
        XCTAssertNotNil(properties)
        XCTAssertFalse((properties?["LSQuarantineAgentName"] as? String)?.isEmpty ?? true)
    }

}
