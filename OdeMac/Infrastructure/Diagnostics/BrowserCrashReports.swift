import Foundation
import Observation

/// The crash and hang reports Ode keeps on this Mac, in `Reports` beside the
/// session: at most ``mostKept`` of them and ``mostBytes`` in all, none older
/// than ``daysKept`` days. Each launch collects what the readers find that it
/// has not seen, and asks the person about new ones as their choice says:
/// ask each time, always send, or never send. Nothing leaves the Mac before
/// the person sends a report or chose to always send, and no report says it
/// was sent unless an uploader confirmed it arrived.
@MainActor @Observable
final class BrowserCrashReports {
    // MARK: - Types

    /// What happens to a new report.
    enum Sending: String, CaseIterable, Identifiable, Sendable {
        case ask
        case always
        case never

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ask: String(localized: "Ask each time")
            case .always: String(localized: "Always send")
            case .never: String(localized: "Never send")
            }
        }
    }

    /// Sends a report's text where reports go, throwing when it did not arrive.
    typealias Uploader = @Sendable (String) async throws -> Void

    /// What the store remembers beside the reports.
    struct Memory: Codable, Equatable, Sendable {
        /// The records collected before, so a report the person deleted does
        /// not come back from the record it came from.
        var seen: [String] = []
        /// The newest report the notice already asked about.
        var noticedThrough: Date?
        /// How many notices in a row the person answered with Don't send.
        var declinedInARow = 0
    }

    // MARK: - Static Variables

    static let directoryName = "Reports"
    static let mostKept = 50
    static let mostBytes = 50 * 1024 * 1024
    static let daysKept = 30
    /// Two Don't send answers in a row stop the notice; the reports stay listed.
    static let declinesBeforeQuiet = 2
    static let sendingKey = "ode.reports.sending"
    private static let memoryFileName = "memory.json"
    private static let seenKept = 500

    // MARK: - Variables

    let directory: URL
    private(set) var reports: [BrowserCrashReport] = []
    private(set) var memory = Memory()
    /// Whether a report can be sent anywhere; Send is unavailable without it.
    var canSend: Bool { uploader != nil }
    var sending: Sending {
        didSet { defaults.set(sending.rawValue, forKey: Self.sendingKey) }
    }
    @ObservationIgnored private let uploader: Uploader?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> Date

    // MARK: - Initializers

    /// Reads the reports kept in `Reports` inside `sessionDirectory`.
    init(
        sessionDirectory: URL, uploader: Uploader? = nil, defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        directory = sessionDirectory.appendingPathComponent(Self.directoryName, isDirectory: true)
        self.uploader = uploader
        self.defaults = defaults
        self.now = now
        sending = defaults.string(forKey: Self.sendingKey).flatMap(Sending.init(rawValue:)) ?? .ask
        reload()
    }

    // MARK: - Actions - Collecting

    /// Keeps the reports in `found` that are new, then trims the store to its
    /// caps. Answers the reports it kept.
    @discardableResult
    func collect(_ found: [BrowserCrashReport]) -> [BrowserCrashReport] {
        let seen = Set(memory.seen)
        let new = found.filter { !seen.contains($0.id) }
        for report in new { write(report) }
        memory.seen = Array((memory.seen + new.map(\.id)).suffix(Self.seenKept))
        saveMemory()
        reload()
        prune()
        return new.filter { report in reports.contains { $0.id == report.id } }
    }

    /// Removes reports older than ``daysKept`` days, then the oldest until at
    /// most ``mostKept`` and ``mostBytes`` remain.
    func prune() {
        let cutoff = now().addingTimeInterval(-Double(Self.daysKept) * 24 * 60 * 60)
        var kept = reports.filter { $0.occurredAt >= cutoff }
        while kept.count > Self.mostKept || kept.reduce(0, { $0 + $1.bytes }) > Self.mostBytes, !kept.isEmpty {
            kept.removeLast()
        }
        for report in reports where !kept.contains(where: { $0.id == report.id }) { removeFile(of: report) }
        reports = kept
    }

    // MARK: - Actions - Answering

    /// The reports the notice asks about: kept and not yet noticed, while the
    /// person's choice is to be asked and they have not declined twice in a row.
    var unnoticed: [BrowserCrashReport] {
        guard sending == .ask, memory.declinedInARow < Self.declinesBeforeQuiet else { return [] }
        return reports.filter { report in
            report.delivery == .notSent && memory.noticedThrough.map { report.occurredAt > $0 } ?? true
        }
    }

    /// The person answered the notice about `asked`.
    func answerNotice(about asked: [BrowserCrashReport], sends: Bool) async {
        memory.noticedThrough = asked.map(\.occurredAt).max() ?? memory.noticedThrough
        memory.declinedInARow = sends ? 0 : memory.declinedInARow + 1
        saveMemory()
        if sends { for report in asked { await send(report) } }
    }

    /// The person opened the list from the notice: the notice is answered,
    /// without counting as Don't send.
    func reviewNotice(about asked: [BrowserCrashReport]) {
        memory.noticedThrough = asked.map(\.occurredAt).max() ?? memory.noticedThrough
        saveMemory()
    }

    /// Sends what the person chose to always send.
    func sendNewIfChosen(_ new: [BrowserCrashReport]) async {
        guard sending == .always else { return }
        for report in new { await send(report) }
    }

    /// Sends `report`, when there is somewhere to send it. Only an uploader
    /// that answered marks it sent; a failure marks it not sent.
    func send(_ report: BrowserCrashReport) async {
        guard let uploader else { return }
        var updated = report
        do {
            try await uploader(BrowserCrashReportPayload.text(for: report))
            updated.delivery = .sent(now())
        } catch {
            updated.delivery = .failed(now())
        }
        write(updated)
        reload()
    }

    func delete(_ report: BrowserCrashReport) {
        removeFile(of: report)
        reports.removeAll { $0.id == report.id }
    }

    // MARK: - Actions - Files

    private func url(of report: BrowserCrashReport) -> URL {
        let safe = report.id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }

    private func write(_ report: BrowserCrashReport) {
        guard let data = try? Self.encoder.encode(report) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(of: report), options: .atomic)
    }

    private func removeFile(of report: BrowserCrashReport) {
        try? FileManager.default.removeItem(at: url(of: report))
    }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        reports = files.filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.memoryFileName }
            .compactMap { try? Self.decoder.decode(BrowserCrashReport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.occurredAt > $1.occurredAt }
        memory =
            (try? Self.decoder.decode(
                Memory.self, from: Data(contentsOf: directory.appendingPathComponent(Self.memoryFileName))))
            ?? memory
    }

    private func saveMemory() {
        guard let data = try? Self.encoder.encode(memory) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(Self.memoryFileName), options: .atomic)
    }

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
