import Foundation

/// The launches this Mac remembers, oldest first: when each began, which
/// build ran it, whether it finished starting and whether it quit cleanly.
///
/// The file is `launches.json` beside the session, version 1:
///
///     {"version":1,"launches":[{"id":"…","startedAt":"2026-10-29T09:12:03Z",
///       "build":"0.9.2 (202610290912)","outcome":"started|finished|clean",
///       "safeMode":false,"finishedAt":"…","endedAt":"…"}]}
///
/// A launch is `started` until its first window has been on screen for
/// ``BrowserLaunchRecord/finishingDelay``, then `finished`, and `clean` once
/// a quit the person asked for saved every edit. A launch the process left
/// as `started` is one that did not finish starting: a crash, a hang the
/// person force quit or a power loss. The crash reports read the same file.
struct BrowserLaunchHistory: Codable, Equatable, Sendable {
    // MARK: - Types

    struct Launch: Codable, Equatable, Identifiable, Sendable {
        enum Outcome: String, Codable, Sendable {
            case started
            case finished
            case clean
        }

        let id: UUID
        let startedAt: Date
        let build: String
        var outcome: Outcome
        var safeMode: Bool
        var finishedAt: Date?
        var endedAt: Date?
        /// The process generation, when recorded, to attribute OS crash reports
        /// without confusing a reused PID or another isolated profile.
        var processID: Int? = nil
        var processStartedAt: Double? = nil
    }

    // MARK: - Static Variables

    static let currentVersion = 1
    /// Enough launches for a startup streak and for the crash reports to
    /// date a crash; older ones go.
    static let mostKept = 20
    /// Launches further apart than this never add up to a streak, so a crash
    /// on Monday and another on Thursday stay separate.
    static let streakWindow: TimeInterval = 6 * 60 * 60

    // MARK: - Variables

    var version = currentVersion
    var launches: [Launch] = []

    // MARK: - Actions - Reading

    /// How many launches in a row, each within ``streakWindow`` of the next and
    /// the newest within it of `now`, did not finish starting. A finished
    /// launch ends the count, except that a finished launch in safe mode
    /// counts as one, so the next failed start in normal mode asks again.
    func startupStreak(at now: Date) -> Int {
        var streak = 0
        var reference = now
        for launch in launches.reversed() {
            guard reference.timeIntervalSince(launch.startedAt) <= Self.streakWindow else { break }
            guard launch.outcome == .started else {
                if launch.safeMode { streak += 1 }
                break
            }
            streak += 1
            reference = launch.startedAt
        }
        return streak
    }

    /// Whether the newest launch ended without a quit the person asked for: a
    /// crash, a force quit or a power loss, whether or not it had finished
    /// starting. No launch before is a clean start.
    var newestEndedUncleanly: Bool {
        guard let newest = launches.last else { return false }
        return newest.outcome != .clean
    }

    /// Whether the newest launch ran in safe mode and did not finish starting,
    /// within ``streakWindow`` of `now`.
    func safeModeFailed(at now: Date) -> Bool {
        guard let newest = launches.last else { return false }
        return newest.safeMode && newest.outcome == .started
            && now.timeIntervalSince(newest.startedAt) <= Self.streakWindow
    }

    // MARK: - Mutators

    mutating func append(_ launch: Launch) {
        launches.append(launch)
        if launches.count > Self.mostKept { launches.removeFirst(launches.count - Self.mostKept) }
    }

    mutating func update(_ id: UUID, _ change: (inout Launch) -> Void) {
        guard let index = launches.lastIndex(where: { $0.id == id }) else { return }
        change(&launches[index])
    }
}

/// Reads and writes the launch history file. The real one writes a whole
/// file under a temporary name, flushes it to the drive with `F_FULLFSYNC`
/// and renames it over the old one, so a power loss leaves the old history or
/// the new, never a mix; tests hand in their own.
protocol BrowserLaunchRecordFiles: Sendable {
    func read(_ url: URL) throws -> Data?
    func writeDurably(_ data: Data, to url: URL) throws
}

struct BrowserLaunchRecordDisk: BrowserLaunchRecordFiles {
    func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return nil
        }
    }

    func writeDurably(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var written = 0
        let status: Int32 = data.withUnsafeBytes { buffer in
            while written < buffer.count {
                let result = write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if result < 0 {
                    if errno == EINTR { continue }
                    return errno
                }
                written += result
            }
            // A plain fsync leaves the bytes in the drive's cache; only
            // F_FULLFSYNC orders them onto the medium before the rename.
            return fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0 ? 0 : errno
        }
        close(descriptor)
        guard status == 0, rename(temporary.path, url.path) == 0 else {
            let failure = status == 0 ? errno : status
            unlink(temporary.path)
            throw POSIXError(.init(rawValue: failure) ?? .EIO)
        }
    }
}

/// The launch record a Mac launch keeps beside its session: it opens a
/// `started` entry before the engine loads, marks it finished once the first
/// window has stayed up for ``finishingDelay`` and clean at the end of a quit
/// the person asked for. Writing never throws to its caller; a record that
/// cannot be written only means the next launch may not count a streak.
@MainActor
final class BrowserLaunchRecord {
    // MARK: - Static Variables

    static let fileName = "launches.json"
    /// How long the first window stays on screen before the launch counts as
    /// started: long enough for a crash in restoring the last pages to show.
    static let finishingDelay: Duration = .seconds(15)

    // MARK: - Variables

    let url: URL
    private(set) var history: BrowserLaunchHistory
    /// This launch's entry, once `begin` wrote it.
    private(set) var currentID: UUID?
    private let files: any BrowserLaunchRecordFiles
    private let now: @Sendable () -> Date

    // MARK: - Initializers

    /// Reads the history in `directory`. A file that is missing or cannot be
    /// read starts an empty history rather than stopping the launch.
    init(
        directory: URL,
        files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        url = directory.appendingPathComponent(Self.fileName)
        self.files = files
        self.now = now
        let stored = (try? files.read(url)).flatMap { data in
            try? Self.decoder.decode(BrowserLaunchHistory.self, from: data)
        }
        history =
            stored.map { $0.version == BrowserLaunchHistory.currentVersion ? $0 : BrowserLaunchHistory() }
            ?? BrowserLaunchHistory()
    }

    // MARK: - Actions - Reading

    /// The streak of launches before this one that did not finish starting.
    var startupStreak: Int {
        let earlier = earlierHistory
        return earlier.startupStreak(at: currentLaunch?.startedAt ?? now())
    }

    /// Whether the launch before this one ended without a quit the person
    /// asked for, so this one leaves its pages to load when they are opened.
    var previousLaunchEndedUncleanly: Bool {
        earlierHistory.newestEndedUncleanly
    }

    /// Whether the launch before this one ran in safe mode and did not finish.
    var safeModeFailed: Bool {
        earlierHistory.safeModeFailed(at: currentLaunch?.startedAt ?? now())
    }

    /// Whether a launch before this one started at or after `date`, as one
    /// since the Mac last started has.
    func launchedEarlier(since date: Date) -> Bool {
        earlierHistory.launches.contains { $0.startedAt >= date }
    }

    var currentLaunch: BrowserLaunchHistory.Launch? {
        currentID.flatMap { id in history.launches.last { $0.id == id } }
    }

    private var earlierHistory: BrowserLaunchHistory {
        guard let currentID else { return history }
        var earlier = history
        earlier.launches.removeAll { $0.id == currentID }
        return earlier
    }

    // MARK: - Actions - Writing

    /// Opens this launch's entry as `started` for `build`.
    func begin(build: String, processID: Int? = nil, processStartedAt: Double? = nil) {
        guard currentID == nil else { return }
        let launch = BrowserLaunchHistory.Launch(
            id: UUID(), startedAt: now(), build: build, outcome: .started, safeMode: false,
            processID: processID, processStartedAt: processStartedAt)
        currentID = launch.id
        history.append(launch)
        save()
    }

    /// Marks this launch as running in safe mode.
    func enterSafeMode() {
        change { $0.safeMode = true }
    }

    /// The first window stayed up: this launch finished starting.
    func finish() {
        change { launch in
            guard launch.outcome == .started else { return }
            launch.outcome = .finished
            launch.finishedAt = now()
        }
    }

    /// A quit the person asked for saved every edit.
    func endCleanly() {
        change { launch in
            launch.outcome = .clean
            launch.endedAt = now()
        }
    }

    private func change(_ change: (inout BrowserLaunchHistory.Launch) -> Void) {
        guard let currentID else { return }
        history.update(currentID, change)
        save()
    }

    private func save() {
        guard let data = try? Self.encoder.encode(history) else { return }
        do {
            try files.writeDurably(data, to: url)
        } catch {
            DiagnosticLog.launch.notice("The launch record could not be saved: \(DiagnosticLog.describe(error))")
        }
    }

    // MARK: - Coding

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
