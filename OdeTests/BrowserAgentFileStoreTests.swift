import OSLog
import XCTest

@testable import Ode

/// An agent file store reads its file once and writes a moment after the
/// latest change, or at once before the app quits. A file that does not read
/// is never written over: it is kept aside under a dated name and the failure
/// is logged. The origin grants and the activity log keep what an earlier run
/// wrote through it.
@MainActor
final class BrowserAgentFileStoreTests: XCTestCase {
    /// What a test store restored and what it saves.
    @MainActor
    private final class Values {
        var didRestore = false
        var restored: [String]?
        var saved: [String] = []
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserAgentFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func store(_ file: URL, delay: Duration, values: Values) -> BrowserAgentFileStore<[String]> {
        let store = BrowserAgentFileStore<[String]>(
            file: file, name: "Test values", queueLabel: "tests", saveDelay: delay)
        store.load(
            restore: { stored in
                values.restored = stored
                values.didRestore = true
            },
            snapshot: { values.saved })
        return store
    }

    private func decoded(_ file: URL) throws -> [String] {
        try JSONDecoder().decode([String].self, from: Data(contentsOf: file))
    }

    private func keptFiles(in directory: URL, stem: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(stem).unreadable-") }
    }

    func testAnUnreadableFileIsKeptAsideUnderADatedNameAndReported() async throws {
        let started = Date.now
        let directory = try directory()
        let file = directory.appendingPathComponent("values.json")
        let unreadable = Data("not json".utf8)
        try unreadable.write(to: file)
        let values = Values()
        let store = store(file, delay: .milliseconds(50), values: values)

        try await waitUntil { values.didRestore }
        XCTAssertNil(values.restored)
        let kept = try keptFiles(in: directory, stem: "values")
        XCTAssertEqual(kept.count, 1)
        let keptFile = try XCTUnwrap(kept.first)
        let keptName = keptFile.lastPathComponent
        XCTAssertNotNil(keptName.wholeMatch(of: /values\.unreadable-\d{8}T\d{6}Z\.json/), keptName)
        XCTAssertEqual(try Data(contentsOf: keptFile), unreadable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let log = try OSLogStore(scope: .currentProcessIdentifier)
        let messages = try log.getEntries(
            at: log.position(date: started),
            matching: NSPredicate(format: "subsystem == %@ AND category == %@", "com.odebrowser.ode", "Agents")
        ).compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
        XCTAssertTrue(
            messages.contains { $0.contains("Test values could not be read") && $0.contains(keptName) }, "\(messages)")

        // What the person does next is kept in a new file beside the old one.
        values.saved = ["after"]
        store.scheduleSave()
        store.flush()
        XCTAssertEqual(try decoded(file), ["after"])
        XCTAssertEqual(try Data(contentsOf: keptFile), unreadable)
    }

    func testChangesWriteOnceAfterTheLatestAndAFlushWritesAtOnce() async throws {
        let file = try directory().appendingPathComponent("values.json")
        let values = Values()
        let store = store(file, delay: .milliseconds(300), values: values)
        try await waitUntil { values.didRestore }
        XCTAssertNil(values.restored)

        values.saved = ["first"]
        store.scheduleSave()
        values.saved = ["first", "second"]
        store.scheduleSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try await waitUntil { FileManager.default.fileExists(atPath: file.path) }
        XCTAssertEqual(try decoded(file), ["first", "second"])

        values.saved = ["third"]
        store.scheduleSave()
        store.flush()
        XCTAssertEqual(try decoded(file), ["third"])

        let reread = Values()
        let rereadStore = self.store(file, delay: .milliseconds(50), values: reread)
        try await waitUntil { reread.didRestore }
        XCTAssertEqual(reread.restored, ["third"])
        XCTAssertTrue(rereadStore.isLoaded)
    }

    func testOriginGrantsKeepAnEarlierRunsGrantsAndNeverWriteOverAnUnreadableFile() async throws {
        let directory = try directory()
        let agent = AgentIdentity(teamID: "TEAM", signingID: "com.example.agent", path: nil, client: nil)
        let file = directory.appendingPathComponent("origin-grants.json")
        try Data(#"[{"agent":{"teamID":"TEAM","signingID":"com.example.agent"},"origins":["https://a.example"]}]"#.utf8)
            .write(to: file)
        let grants = BrowserAgentOriginGrants(file: file)
        try await waitUntil { grants.isAllowed("https://a.example", for: agent) }

        let unreadableFile = directory.appendingPathComponent("broken", isDirectory: true)
            .appendingPathComponent("origin-grants.json")
        try FileManager.default.createDirectory(
            at: unreadableFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let unreadable = Data("{".utf8)
        try unreadable.write(to: unreadableFile)
        let fresh = BrowserAgentOriginGrants(file: unreadableFile)
        try await waitUntil {
            (try? self.keptFiles(in: unreadableFile.deletingLastPathComponent(), stem: "origin-grants").count) == 1
        }
        XCTAssertEqual(fresh.origins(for: agent), [])
        fresh.grant("https://b.example", for: agent)
        try await waitUntil { FileManager.default.fileExists(atPath: unreadableFile.path) }
        let kept = try XCTUnwrap(keptFiles(in: unreadableFile.deletingLastPathComponent(), stem: "origin-grants").first)
        XCTAssertEqual(try Data(contentsOf: kept), unreadable)
        let reread = BrowserAgentOriginGrants(file: unreadableFile)
        try await waitUntil { reread.isAllowed("https://b.example", for: agent) }
    }

    func testTheActivityLogKeepsAnEarlierRunsEntries() async throws {
        let file = try directory().appendingPathComponent("activity.json")
        let entry = BrowserAgentActivityLog.Entry(
            time: Date(timeIntervalSinceReferenceDate: 1000), sessionID: nil, agentName: "Agent", agentColor: nil,
            tool: "open_tab", tabID: nil, tabTitle: nil, tabURL: nil, summary: "url: \"https://a.example\"",
            outcome: .failed("refused"))
        let log = BrowserAgentActivityLog(file: file)
        log.append(entry)
        try await waitUntil { FileManager.default.fileExists(atPath: file.path) }

        let reread = BrowserAgentActivityLog(file: file)
        try await waitUntil { reread.entries == [entry] }
    }
}
