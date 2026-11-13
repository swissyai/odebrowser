import Dispatch
import Foundation

// MARK: - Types

/// A colour a page painted behind its content, as encoded sRGB components
/// from 0 to 1.
struct BrowserPageBackground: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

/// One site's remembered background and when a page of it last painted it.
struct BrowserSiteBackgroundEntry: Codable, Equatable, Sendable {
    let background: BrowserPageBackground
    let paintedAt: Date
}

/// The background each site's pages painted last, so a page of that site
/// that has not drawn yet shows its own colour instead of a blank or white
/// frame.
///
/// Kept on this Mac only, beside the launch's session, for the most recently
/// painted `capacity` sites, apart for each Space's profile, since its sites
/// say where the person went there. Private and temporary windows read it but
/// never add to it; clearing a persistent Space's history or deleting the
/// Space clears its part.
@MainActor
final class BrowserSiteBackgrounds {
    // MARK: - Static Variables

    static let fileName = "Site Backgrounds.json"
    static let capacity = 400
    /// The launch's own store, beside its session once the launch opens it
    /// there; in memory until then, and for a launch that keeps no session
    /// on disk.
    private(set) static var shared = BrowserSiteBackgrounds(file: nil)

    // MARK: - Variables

    private let file: URL?
    private var entries: [String: BrowserSiteBackgroundEntry]
    private var pendingSave: Task<Void, Never>?
    /// Whether changes still need a confirmed flush before quitting.
    private var isDirty = false
    /// Serializes saves so clearing history cannot be undone by an older write.
    private let writes = DispatchQueue(label: "com.odebrowser.page-backgrounds", qos: .utility)

    // MARK: - Initializers

    /// A store kept in `file`, or only in memory for nil.
    init(file: URL?) {
        self.file = file
        entries = [:]
        guard let file else { return }
        do {
            entries = try JSONDecoder().decode([String: BrowserSiteBackgroundEntry].self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A first launch has no remembered backgrounds yet.
        } catch {
            let failure = error as NSError
            DiagnosticLog.pages.error(
                "Remembered page backgrounds could not be loaded; using an empty cache (\(failure.domain) \(failure.code))."
            )
        }
    }

    // MARK: - Actions - Opening

    /// Keeps the launch's own store beside the session in
    /// `sessionDirectory`, before any page paints; nil keeps it in memory.
    static func openShared(in sessionDirectory: URL?) {
        shared = BrowserSiteBackgrounds(file: sessionDirectory?.appendingPathComponent(fileName))
    }

    // MARK: - Actions - Reading

    /// The background `url`'s site painted last in profile `profileID`, if
    /// it painted one.
    func background(for url: URL?, in profileID: UUID) -> BrowserPageBackground? {
        Self.key(url, profileID).flatMap { entries[$0]?.background }
    }

    /// The key for `url`'s site in profile `profileID`, for web pages only.
    private static func key(_ url: URL?, _ profileID: UUID) -> String? {
        guard let scheme = url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return BrowserSite.of(url).map { "\(profileID.uuidString) \($0)" }
    }

    // MARK: - Actions - Recording

    /// Remembers that a page of `url`'s site painted `background` at `time`
    /// in profile `profileID`, unless the page is private.
    func record(
        _ background: BrowserPageBackground, for url: URL?, in profileID: UUID, isPrivate: Bool, at time: Date = .now
    ) {
        guard !isPrivate, let key = Self.key(url, profileID) else { return }
        let changed = entries[key]?.background != background
        entries[key] = BrowserSiteBackgroundEntry(background: background, paintedAt: time)
        if entries.count > Self.capacity {
            let oldest = entries.sorted { $0.value.paintedAt < $1.value.paintedAt }.prefix(
                entries.count - Self.capacity)
            for (key, _) in oldest { entries.removeValue(forKey: key) }
        }
        if changed { scheduleSave() }
    }

    /// Forgets every site of profile `profileID`, as clearing its history does.
    func removeAll(in profileID: UUID) {
        let prefix = profileID.uuidString + " "
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
        scheduleSave()
        saveNow()
    }

    // MARK: - Actions - Persistence

    /// Writes the store a moment after its last change, off the main actor.
    private func scheduleSave() {
        guard let file else { return }
        isDirty = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.entries
            self.writes.async { _ = Self.write(snapshot, to: file) }
            // Keep a confirmed flush due: a queued write may fail, and quitting
            // must not silently treat that as a successful save.
        }
    }

    /// Writes a change still waiting at once, as the app quits.
    func saveNow() {
        pendingSave?.cancel()
        guard let file else { return }
        let snapshot = entries
        let dirty = isDirty
        let saved = writes.sync { !dirty || Self.write(snapshot, to: file) }
        if saved { isDirty = false }
    }

    private nonisolated static func write(_ snapshot: [String: BrowserSiteBackgroundEntry], to file: URL) -> Bool {
        do {
            try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
            return true
        } catch {
            let failure = error as NSError
            DiagnosticLog.pages.error(
                "Remembered page backgrounds could not be saved, including any history clearing; "
                    + "keeping a flush due (\(failure.domain) \(failure.code)).")
            return false
        }
    }
}
