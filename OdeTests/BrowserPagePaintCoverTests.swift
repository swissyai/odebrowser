import AppKit
import XCTest

@testable import Ode

/// A page's view stays covered until its document draws, never by a picture
/// of the page before for longer than a second, and the colours that cover it
/// stay on this Mac, apart for each Space, and out of private windows.
@MainActor
final class BrowserPagePaintCoverTests: XCTestCase {
    // MARK: - Variables

    private let black = CGColor(gray: 0, alpha: 1)

    // MARK: - Actions - Navigation lifetime

    func testAnUnreportedPaintCannotKeepStaleContentPastTheDeadline() async {
        let clock = FakeSleeps()
        defer { clock.finishAll() }
        let hold = BrowserPagePaintHold(sleep: clock.sleep)
        guard let image = Self.image() else { return XCTFail("No image") }
        hold.hold(image: image, color: black)
        XCTAssertNotNil(hold.cover?.image)

        await clock.finish(BrowserPagePaintHold.maximumHold)
        XCTAssertNil(hold.cover)
    }

    func testTheCoverGoesOnceThePageDrawsOrItsLoadEnds() async {
        let clock = FakeSleeps()
        defer { clock.finishAll() }
        let hold = BrowserPagePaintHold(sleep: clock.sleep)
        hold.hold(image: nil, color: black)
        hold.painted()
        XCTAssertNil(hold.cover)

        hold.hold(image: nil, color: black)
        hold.loadEnded()
        XCTAssertNotNil(hold.cover)
        await clock.finish(BrowserPagePaintHold.loadSettle)
        XCTAssertNil(hold.cover)
    }

    func testANewerCoverOutlivesAnOlderOnesTimeout() async {
        let clock = FakeSleeps()
        defer { clock.finishAll() }
        let hold = BrowserPagePaintHold(sleep: clock.sleep)
        hold.hold(image: nil, color: black)
        let white = CGColor(gray: 1, alpha: 1)
        hold.hold(image: nil, color: white)
        await clock.finish(BrowserPagePaintHold.maximumHold)
        XCTAssertEqual(hold.cover?.color, white)
        await clock.finish(BrowserPagePaintHold.maximumHold)
        XCTAssertNil(hold.cover)
    }

    // MARK: - Actions - Private local persistence

    func testRememberedBackgroundsStayWithTheirSpaceAndOutOfPrivateWindows() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = BrowserSiteBackgrounds(file: file)
        let work = UUID()
        let personal = UUID()
        let dark = BrowserPageBackground(red: 0.08, green: 0.09, blue: 0.11)
        let site = URL(string: "https://www.example.com/a")

        store.record(dark, for: site, in: work, isPrivate: false)
        store.record(dark, for: URL(string: "https://other.example"), in: work, isPrivate: true)

        XCTAssertEqual(store.background(for: URL(string: "https://example.com/b"), in: work), dark)
        XCTAssertNil(store.background(for: site, in: personal))
        XCTAssertNil(store.background(for: URL(string: "https://other.example"), in: work))
        store.removeAll(in: work)
        XCTAssertNil(store.background(for: site, in: work))
        store.saveNow()
        XCTAssertNil(BrowserSiteBackgrounds(file: file).background(for: site, in: work))
    }

    func testPrivatePaintReportsNeverCreateOrChangePersistedSiteData() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let profile = UUID()
        let store = BrowserSiteBackgrounds(file: file)
        let report = try XCTUnwrap(
            BrowserPagePaintBridge.report([
                "url": "https://example.test/private/path?search=private#fragment",
                "background": "rgb(20, 22, 27)",
            ]))
        let privateColor = try XCTUnwrap(report.background)

        store.record(privateColor, for: report.url, in: profile, isPrivate: true)
        store.saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(store.background(for: report.url, in: profile))

        let normalColor = BrowserPageBackground(red: 1, green: 1, blue: 1)
        store.record(normalColor, for: report.url, in: profile, isPrivate: false)
        store.saveNow()
        let before = try Data(contentsOf: file)
        let entries = try JSONDecoder().decode([String: BrowserSiteBackgroundEntry].self, from: before)
        XCTAssertEqual(Set(entries.keys), [profile.uuidString + " example.test"])

        store.record(privateColor, for: report.url, in: profile, isPrivate: true)
        store.saveNow()
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(BrowserSiteBackgrounds(file: file).background(for: report.url, in: profile), normalColor)
    }

    func testRememberedBackgroundsSurviveAQuitAndARelaunch() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let profile = UUID()
        let site = URL(string: "https://example.com")
        let color = BrowserPageBackground(red: 0.1, green: 0.1, blue: 0.1)
        let store = BrowserSiteBackgrounds(file: file)
        store.record(color, for: site, in: profile, isPrivate: false)
        store.saveNow()

        XCTAssertEqual(BrowserSiteBackgrounds(file: file).background(for: site, in: profile), color)
    }

    func testRememberedBackgroundsKeepOnlyTheMostRecentSites() {
        let store = BrowserSiteBackgrounds(file: nil)
        let profile = UUID()
        let color = BrowserPageBackground(red: 1, green: 1, blue: 1)
        let start = Date(timeIntervalSince1970: 0)
        for index in 0...BrowserSiteBackgrounds.capacity {
            store.record(
                color, for: URL(string: "https://site\(index).example"), in: profile, isPrivate: false,
                at: start.addingTimeInterval(Double(index)))
        }
        XCTAssertNil(store.background(for: URL(string: "https://site0.example"), in: profile))
        XCTAssertEqual(store.background(for: URL(string: "https://site1.example"), in: profile), color)
    }

    func testAPaintReportCarriesOnlyAnOpaqueBackground() {
        XCTAssertEqual(
            BrowserPagePaintBridge.background(css: "rgb(20, 22, 27)"),
            BrowserPageBackground(red: 20 / 255, green: 22 / 255, blue: 27 / 255))
        XCTAssertNotNil(BrowserPagePaintBridge.background(css: "rgba(255, 255, 255, 1)"))
        XCTAssertNil(BrowserPagePaintBridge.background(css: "rgba(0, 0, 0, 0.5)"))
        XCTAssertNil(BrowserPagePaintBridge.background(css: "color(display-p3 1 0 0)"))
        XCTAssertNil(BrowserPagePaintBridge.report("painted"))
        XCTAssertNil(BrowserPagePaintBridge.report(["background": "rgb(0, 0, 0)"]))
        XCTAssertEqual(
            BrowserPagePaintBridge.report(["url": "https://example.com/a", "background": "rgb(0, 0, 0)"])?.url,
            URL(string: "https://example.com/a"))
    }

    func testAFailedSaveKeepsTheChangeDueForAnExplicitFlush() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(BrowserSiteBackgrounds.fileName)
        let store = BrowserSiteBackgrounds(file: file)
        let profile = UUID()
        let site = try XCTUnwrap(URL(string: "https://example.test/"))
        let color = BrowserPageBackground(red: 0.1, green: 0.2, blue: 0.3)
        store.record(color, for: site, in: profile, isPrivate: false)
        store.saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store.saveNow()
        XCTAssertEqual(BrowserSiteBackgrounds(file: file).background(for: site, in: profile), color)
        store.removeAll(in: profile)
        XCTAssertNil(BrowserSiteBackgrounds(file: file).background(for: site, in: profile))
    }

    func testHistoryClearingAfterADebouncedSaveCannotRestoreTheClearedProfile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = BrowserSiteBackgrounds(file: file)
        let cleared = UUID()
        let retained = UUID()
        let site = try XCTUnwrap(URL(string: "https://example.test/"))
        let color = BrowserPageBackground(red: 0.1, green: 0.2, blue: 0.3)
        store.record(color, for: site, in: cleared, isPrivate: false)
        store.record(color, for: site, in: retained, isPrivate: false)
        try await Task.sleep(for: .milliseconds(2100))
        store.removeAll(in: cleared)
        store.saveNow()

        let reloaded = BrowserSiteBackgrounds(file: file)
        XCTAssertNil(reloaded.background(for: site, in: cleared))
        XCTAssertEqual(reloaded.background(for: site, in: retained), color)
    }

    func testACorruptCacheFallsBackToEmptyAndCanBeReplaced() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not JSON".utf8).write(to: file)
        let store = BrowserSiteBackgrounds(file: file)
        let site = try XCTUnwrap(URL(string: "https://example.test/"))
        let profile = UUID()
        XCTAssertNil(store.background(for: site, in: profile))
        let color = BrowserPageBackground(red: 0.1, green: 0.2, blue: 0.3)
        store.record(color, for: site, in: profile, isPrivate: false)
        store.saveNow()
        XCTAssertEqual(BrowserSiteBackgrounds(file: file).background(for: site, in: profile), color)
    }

    private static func image() -> CGImage? {
        CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}

/// Sleeps that end when the test says the time has passed.
@MainActor
private final class FakeSleeps {
    // MARK: - Variables

    private var waiting: [(duration: Duration, resume: CheckedContinuation<Void, Never>)] = []

    var sleep: @MainActor (Duration) async -> Void {
        { [weak self] duration in
            await withCheckedContinuation { continuation in
                self?.waiting.append((duration, continuation))
            }
        }
    }

    // MARK: - Actions - Time

    func finish(_ duration: Duration) async {
        for _ in 0..<50 where !waiting.contains(where: { $0.duration == duration }) { await Task.yield() }
        guard let index = waiting.firstIndex(where: { $0.duration == duration }) else {
            return XCTFail("No sleep waiting for \(duration).")
        }
        waiting.remove(at: index).resume.resume()
        for _ in 0..<20 { await Task.yield() }
    }

    func finishAll() {
        for waiter in waiting { waiter.resume.resume() }
        waiting.removeAll()
    }
}
