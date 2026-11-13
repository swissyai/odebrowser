import Foundation
import XCTest

@testable import Ode

/// The crash and hang reports kept on this Mac: what the readers pick from the
/// launch record, macOS's crash reports and the hang log, the store's caps,
/// the notice and its answers, sending only after a choice, and the text a
/// report becomes, which never holds a page or the person.
@MainActor
final class BrowserCrashReportsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func defaults() -> UserDefaults {
        let suite = "ode-reports-tests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    private func report(_ id: String, ago: TimeInterval = 60, kind: BrowserCrashReport.Kind = .crash) -> BrowserCrashReport {
        BrowserCrashReport(
            id: id, kind: kind, occurredAt: now - ago, build: "0.9.4 (1)", summary: "EXC_BAD_ACCESS in Ode",
            details: "Exception: EXC_BAD_ACCESS")
    }

    // MARK: - Readers

    func testTheLaunchRecordGivesAReportForEachLaunchThatEndedUncleanly() {
        func launch(_ outcome: BrowserLaunchHistory.Launch.Outcome, ago: TimeInterval) -> BrowserLaunchHistory.Launch {
            BrowserLaunchHistory.Launch(id: UUID(), startedAt: now - ago, build: "0.9.4 (1)", outcome: outcome, safeMode: false)
        }
        let unfinished = launch(.started, ago: 600)
        let crashedLater = launch(.finished, ago: 400)
        let clean = launch(.clean, ago: 300)
        let old = launch(.started, ago: 40 * 86_400)
        let current = launch(.started, ago: 1)
        let history = BrowserLaunchHistory(launches: [old, unfinished, crashedLater, clean, current])

        let reports = BrowserCrashReportReaders.launches(in: history, current: current.id, now: now)
        XCTAssertEqual(reports.map(\.kind), [.unfinishedStart, .unexpectedQuit])
        XCTAssertEqual(reports.map(\.id), ["launch-\(unfinished.id.uuidString)", "launch-\(crashedLater.id.uuidString)"])
    }

    func testOnlyLongHangsBecomeReports() {
        var log = BrowserHangLog()
        log.record(start: now - 120, seconds: 0.8)
        log.record(start: now - 60, seconds: 4.5)
        let reports = BrowserCrashReportReaders.hangs(in: log, build: "0.9.4 (1)", now: now)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.kind, .hang)
    }

    /// A crash report as macOS writes it, with what a reader must leave out:
    /// an address the page showed, the person's home folder, memory
    /// addresses, registers and a run of raw bytes.
    private func ipsData(
        bundleID: String = "com.odebrowser.ode", name: String = "Ode",
        path: String = "/Applications/Ode.app/Contents/MacOS/Chromium"
    ) -> Data {
        let header = #"{"app_name":"\#(name)","bundleID":"\#(bundleID)","app_version":"0.9.4","build_version":"1","bug_type":"309","name":"\#(name)"}"#
        let body = """
            {"procName":"\(name)","procPath":"\(path)","exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV","codes":"0x0000000000000001, 0x00000001045a8000"},
             "asi":{"WebKit":["Loading https://bank.example.com/account?id=42 titled My Bank Statement"]},
             "faultingThread":0,
             "threads":[{"triggered":true,"threadState":{"x":[{"value":4372430848}],"pc":{"value":4372430852}},
               "frames":[{"imageIndex":0,"imageOffset":81234,"symbol":"objc_msgSend"},{"imageIndex":1,"imageOffset":2048}]}],
             "usedImages":[{"name":"libobjc.A.dylib","base":4372430848,"uuid":"11111111-2222-3333-4444-555555555555","path":"/usr/lib/libobjc.A.dylib"},
               {"name":"Ode","base":4294967296,"uuid":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","path":"/Applications/Ode.app/Contents/MacOS/Ode"}],
             "vmSummary":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef page heap bytes"}
            """
        return Data((header + "\n" + body).utf8)
    }

    /// The released app at its usual place, asking which reports are its own.
    private func released(_ bundleID: String?, _ name: String?, _ path: String?) -> Bool {
        BrowserCrashReportReaders.isOde(
            bundleID: bundleID, name: name, path: path, app: "com.odebrowser.ode", appPath: "/Applications/Ode.app")
    }

    func testAMacOSCrashReportKeepsTheFailingStackAndNothingThatNamesAPageOrThePerson() throws {
        let crash = try XCTUnwrap(
            BrowserCrashReportReaders.crash(
                fromIPS: ipsData(), named: "Ode-2026-10-29.ips", modified: now, belongs: released))
        XCTAssertEqual(crash.kind, .crash)
        XCTAssertEqual(crash.build, "0.9.4 (1)")
        XCTAssertTrue(crash.details.contains("libobjc.A.dylib +81234 objc_msgSend"))
        XCTAssertTrue(crash.details.contains("Ode +2048"))
        XCTAssertTrue(crash.details.contains("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"), "Image identities let offsets be symbolicated")

        let payload = BrowserCrashReportPayload.text(for: crash, osVersion: "26.1")
        for leak in ["https://", "bank.example.com", "My Bank Statement", "/Users/person", "4372430848", "4294967296",
            "0x00000001045a8000", "deadbeefdeadbeef", "threadState"]
        {
            XCTAssertFalse(payload.contains(leak), "The report text holds \(leak)")
        }

        XCTAssertNil(
            BrowserCrashReportReaders.crash(
                fromIPS: ipsData(bundleID: "com.example.other", name: "Other"), named: "Other.ips", modified: now,
                belongs: released))
        let helper = "/Applications/Ode.app/Contents/Frameworks/Ode Helper (Renderer).app/Contents/MacOS/Ode Helper"
        XCTAssertNotNil(
            BrowserCrashReportReaders.crash(
                fromIPS: ipsData(
                    bundleID: "com.odebrowser.ode.helper.renderer", name: "Ode Helper (Renderer)", path: helper),
                named: "Helper.ips", modified: now, belongs: released))
    }

    /// The released app never lists a crash of another copy: a development
    /// build, or a test host that ran under the released identifier from
    /// somewhere else.
    func testTheReleasedAppNeverListsADevelopmentBuildOrATestHostCrash() {
        let development = ipsData(
            bundleID: "com.odebrowser.ode.dev", name: "Ode",
            path: "/Users/person/Library/Developer/Xcode/DerivedData/Build/Products/Debug/Ode.app/Contents/MacOS/Ode")
        XCTAssertNil(
            BrowserCrashReportReaders.crash(fromIPS: development, named: "Dev.ips", modified: now, belongs: released))
        let testHost = ipsData(
            bundleID: "com.odebrowser.ode", name: "Ode",
            path: "/Users/person/Library/Developer/Xcode/DerivedData/Build/Products/Debug/Ode.app/Contents/MacOS/Ode")
        XCTAssertNil(
            BrowserCrashReportReaders.crash(fromIPS: testHost, named: "Host.ips", modified: now, belongs: released))
        XCTAssertFalse(released("com.odebrowser.ode.dev.native-core", "OdeNativeCore", nil))
        // macOS anonymizes the paths it writes.
        XCTAssertFalse(released("com.odebrowser.ode", "Ode", "/private/tmp/*/Ode.app/Contents/MacOS/Ode"))
        XCTAssertTrue(
            BrowserCrashReportReaders.ran(
                from: "/Users/USER/Applications/Ode.app/Contents/MacOS/Chromium",
                insideBundleAt: "/Users/person/Applications/Ode.app"))
        XCTAssertFalse(
            BrowserCrashReportReaders.ran(
                from: "/Users/USER/Applications/Ode.app/Contents/MacOS/Chromium", insideBundleAt: "/Applications/Ode.app"))
        XCTAssertTrue(
            BrowserCrashReportReaders.isOde(
                bundleID: "com.odebrowser.ode.dev", name: "Ode", path: nil, app: "com.odebrowser.ode.dev",
                appPath: "/tmp/Ode.app"),
            "A development build lists its own crashes")
    }

    func testRedactionRemovesAddressesPathsEmailsAndRawBytesFromAnyText() {
        let text = """
            Opened https://example.com/a?b=c and www.example.org/x for person@example.com
            at /Users/person/Documents/file.txt, address 0x7ff8a1b2c3d4, heap 0123456789abcdef0123456789abcdef01
            blob QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NTY3ODk=
            """
        let redacted = BrowserCrashReportPayload.redact(text)
        for leak in ["https://example.com", "www.example.org", "person@example.com", "/Users/person", "0x7ff8a1b2c3d4",
            "0123456789abcdef0123456789abcdef01", "QUJDREVGR0hJSktM"]
        {
            XCTAssertFalse(redacted.contains(leak), "Redaction left \(leak)")
        }
        XCTAssertTrue(redacted.contains("/Users/<user>/Documents"))
    }

    // MARK: - The store

    func testTheStoreKeepsAtMostFiftyReportsFromTheLastThirtyDays() throws {
        let store = BrowserCrashReports(sessionDirectory: try directory(), defaults: defaults(), now: { [now] in now })
        var found = (0..<60).map { report("crash-\($0)", ago: Double($0) * 60) }
        found.append(report("old", ago: 31 * 86_400))
        store.collect(found)
        XCTAssertEqual(store.reports.count, BrowserCrashReports.mostKept)
        XCTAssertFalse(store.reports.contains { $0.id == "old" })
        XCTAssertEqual(store.reports.first?.id, "crash-0", "The newest stay")
        XCTAssertLessThanOrEqual(store.reports.reduce(0) { $0 + $1.bytes }, BrowserCrashReports.mostBytes)
    }

    func testADeletedReportDoesNotReturnFromTheRecordItCameFrom() throws {
        let sessionDirectory = try directory()
        let store = BrowserCrashReports(sessionDirectory: sessionDirectory, defaults: defaults(), now: { [now] in now })
        store.collect([report("ips-a"), report("ips-b")])
        store.delete(try XCTUnwrap(store.reports.first { $0.id == "ips-a" }))
        store.collect([report("ips-a"), report("ips-b")])
        XCTAssertEqual(store.reports.map(\.id), ["ips-b"])
        // The store reads the same from disk at the next launch.
        let reopened = BrowserCrashReports(sessionDirectory: sessionDirectory, defaults: defaults(), now: { [now] in now })
        XCTAssertEqual(reopened.reports.map(\.id), ["ips-b"])
    }

    // MARK: - Asking and sending

    func testNothingIsSentBeforeAClickWhileThePersonChoseToBeAsked() async throws {
        let uploads = UploadLog()
        let store = BrowserCrashReports(
            sessionDirectory: try directory(), uploader: { uploads.add($0) }, defaults: defaults(),
            now: { [now] in now })
        XCTAssertEqual(store.sending, .ask)
        let new = store.collect([report("ips-a")])
        await store.sendNewIfChosen(new)
        XCTAssertEqual(uploads.count, 0)
        XCTAssertEqual(store.unnoticed.map(\.id), ["ips-a"])

        await store.answerNotice(about: store.unnoticed, sends: true)
        XCTAssertEqual(uploads.count, 1)
        XCTAssertEqual(store.reports.first?.delivery, .sent(now))
        XCTAssertTrue(store.unnoticed.isEmpty)
        XCTAssertFalse(uploads.texts.joined().contains("https://"))
    }

    func testAlwaysSendSendsNewReportsAndAFailedUploadIsNeverCalledSent() async throws {
        let store = BrowserCrashReports(
            sessionDirectory: try directory(), uploader: { _ in throw URLError(.notConnectedToInternet) },
            defaults: defaults(), now: { [now] in now })
        store.sending = .always
        XCTAssertTrue(store.unnoticed.isEmpty, "Only an ask choice asks")
        let new = store.collect([report("ips-a")])
        await store.sendNewIfChosen(new)
        XCTAssertEqual(store.reports.first?.delivery, .failed(now))

        store.sending = .never
        await store.sendNewIfChosen(store.collect([report("ips-b")]))
        XCTAssertEqual(store.reports.first { $0.id == "ips-b" }?.delivery, .notSent)
    }

    func testTwoDontSendAnswersInARowStopTheNoticeAndTheReportsStayListed() throws {
        let sessionDirectory = try directory()
        let defaults = defaults()
        let store = BrowserCrashReports(sessionDirectory: sessionDirectory, defaults: defaults, now: { [now] in now })
        store.collect([report("ips-a", ago: 120)])
        let first = store.unnoticed
        XCTAssertEqual(first.count, 1)
        let declined = expectation(description: "Declined twice")
        Task {
            await store.answerNotice(about: first, sends: false)
            store.collect([report("ips-b", ago: 60)])
            XCTAssertEqual(store.unnoticed.map(\.id), ["ips-b"])
            await store.answerNotice(about: store.unnoticed, sends: false)
            store.collect([report("ips-c", ago: 30)])
            XCTAssertTrue(store.unnoticed.isEmpty)
            declined.fulfill()
        }
        wait(for: [declined], timeout: 5)
        XCTAssertEqual(Set(store.reports.map(\.id)), ["ips-a", "ips-b", "ips-c"])
        // Reviewing answers the notice without counting as Don't send.
        let fresh = BrowserCrashReports(sessionDirectory: try directory(), defaults: defaults, now: { [now] in now })
        fresh.collect([report("ips-d")])
        fresh.reviewNotice(about: fresh.unnoticed)
        XCTAssertEqual(fresh.memory.declinedInARow, 0)
        XCTAssertTrue(fresh.unnoticed.isEmpty)
    }
}

private final class UploadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func add(_ text: String) { lock.withLock { stored.append(text) } }
    var count: Int { lock.withLock { stored.count } }
    var texts: [String] { lock.withLock { stored } }
}
