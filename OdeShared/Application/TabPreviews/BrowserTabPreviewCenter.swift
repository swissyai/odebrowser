import Foundation
import Observation

/// The previews of one workspace's pinned and saved tabs, which every window
/// over the workspace shares. It reads a tab's page only while the tab is
/// awake, on its site's schedule, and keeps what it read in memory only: a
/// sleeping tab keeps its last preview, and a tab that is closed, moved off
/// the site, unpinned or in a locked Space loses its preview. Reads pause
/// while the system asks for memory, and stop for a site the person turned
/// previews off for.
@MainActor
@Observable
final class BrowserTabPreviewCenter {
    // MARK: - Types

    /// A pinned or saved tab the center may preview: its address, and its
    /// page while the tab is awake and done loading.
    struct Source {
        let tabID: UUID
        let url: URL
        let document: BrowserTabPreviewDocument?
        /// Moves each time the page finishes loading a document.
        let generation: Int
    }

    // MARK: - Static Variables

    /// How often the center looks for previews due a read.
    static let tick: Duration = .seconds(15)
    /// How long a read may take before the center gives up on it.
    static let readTimeout: Duration = .seconds(20)
    /// How long reads pause for each step of severity of a memory warning.
    static let pressurePause: TimeInterval = 10 * 60

    // MARK: - Variables

    private(set) var previews: [UUID: BrowserTabPreview] = [:]
    @ObservationIgnored private var timings: [UUID: BrowserTabPreviewTiming] = [:]
    @ObservationIgnored private var reading: Set<UUID> = []
    @ObservationIgnored private(set) var pausedUntil: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    /// The workspace's pinned and saved tabs in unlocked Spaces.
    @ObservationIgnored var sources: @MainActor () -> [Source] = { [] }
    /// The person's choices, as the core keeps them.
    @ObservationIgnored var preferences: @MainActor () -> TabPreviewPreferences = { .default }
    /// Sites by origin for pages served on this Mac that stand in for them,
    /// which only the test harness sets.
    var standIns: [String: BrowserTabPreviewSite] = [:]
    @ObservationIgnored var now: @MainActor () -> Date = { .now }

    var isRunning: Bool { loop != nil }

    // MARK: - Actions - Reading previews

    /// The site whose preview a tab at `url` shows, if it has one and the
    /// person keeps previews on for it.
    func site(for url: URL?) -> BrowserTabPreviewSite? {
        guard let url, let site = previewSite(at: url), let name = BrowserSite.of(url),
            preferences().showsPreviews(on: name)
        else { return nil }
        return site
    }

    /// The site with previews whose pages `url` shows, previews on or off.
    func previewSite(at url: URL) -> BrowserTabPreviewSite? {
        standIns[Self.origin(of: url)] ?? BrowserTabPreviewSite.matching(url)
    }

    /// The preview of the tab `tabID` at `url`, while its site shows one.
    func preview(of tabID: UUID, at url: URL?) -> BrowserTabPreview? {
        guard site(for: url) != nil else { return nil }
        return previews[tabID]
    }

    // MARK: - Actions - Schedule

    /// Starts reading previews on schedule, once.
    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.refresh() != nil else { return }
                try? await Task.sleep(for: Self.tick, tolerance: .seconds(5))
            }
        }
    }

    /// Stops reading and forgets every preview.
    func stop() {
        loop?.cancel()
        loop = nil
        previews = [:]
        timings = [:]
    }

    /// Forgets the previews of tabs that no longer have one and reads each
    /// awake tab that is due.
    func refresh() {
        let now = now()
        var due: [(Source, BrowserTabPreviewSite)] = []
        var kept: Set<UUID> = []
        for source in sources() {
            guard let site = site(for: source.url) else { continue }
            kept.insert(source.tabID)
            let timing = timings[source.tabID] ?? BrowserTabPreviewTiming()
            if source.document != nil, timing.isDue(at: now, every: site.refreshInterval, generation: source.generation)
            {
                due.append((source, site))
            }
        }
        if previews.keys.contains(where: { !kept.contains($0) }) {
            previews = previews.filter { kept.contains($0.key) }
        }
        timings = timings.filter { kept.contains($0.key) }
        guard pausedUntil.map({ now >= $0 }) ?? true else { return }
        for (source, site) in due { read(source, as: site) }
    }

    /// The person is hovering the tab `tabID`: a preview that is no longer
    /// fresh is read again now.
    func hover(_ tabID: UUID) {
        guard timings[tabID]?.isFresh(at: now()) != true, pausedUntil.map({ now() >= $0 }) ?? true,
            let source = sources().first(where: { $0.tabID == tabID }), let site = site(for: source.url)
        else { return }
        read(source, as: site)
    }

    /// Pauses reads while the system is short of memory, longer the more
    /// severe its warning.
    func relieveMemoryPressure(_ level: MemoryPressureLevel) {
        let until = now().addingTimeInterval(Self.pressurePause * Double(max(level.severity, 1)))
        pausedUntil = max(pausedUntil ?? until, until)
    }

    // MARK: - Actions - Reading pages

    private func read(_ source: Source, as site: BrowserTabPreviewSite) {
        guard let document = source.document, reading.insert(source.tabID).inserted else { return }
        timings[source.tabID, default: BrowserTabPreviewTiming()].begin(at: now(), generation: source.generation)
        Task { @MainActor [weak self] in
            let answer = await document.read(site.reader, timeout: Self.readTimeout)
            self?.finish(source, as: site, answer: answer)
        }
    }

    private func finish(_ source: Source, as site: BrowserTabPreviewSite, answer: Data?) {
        reading.remove(source.tabID)
        guard timings[source.tabID] != nil, self.site(for: source.url) == site else { return }
        let readAt = now()
        if let preview = answer.flatMap({ site.preview(from: $0, page: source.url, readAt: readAt) }) {
            previews[source.tabID] = preview
            timings[source.tabID]?.succeed(at: readAt)
        } else {
            timings[source.tabID]?.fail()
        }
    }

    // MARK: - Actions - Origins

    /// `url`'s origin as a stand-in names it, such as `http://127.0.0.1:8080`.
    static func origin(of url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false)?.lowercased() else {
            return ""
        }
        return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }
}
