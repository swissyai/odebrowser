import Foundation
import Observation

/// The open-format copy of the workspace Ode keeps in a folder the person
/// chose, so their Spaces, tabs, bookmarks and history never depend on Ode
/// to be read: the core writes each export into a dated folder there and
/// keeps the newest seven (`WriteExportFolder`), and this decides when.
///
/// A check runs every quarter hour. It writes once a day whatever changed,
/// and sooner when something a person would miss changed, such as a Space,
/// a pinned or saved tab or a folder, but never twice within an hour. The
/// person can also export at once. Nothing is written while any Space is
/// locked, since its tabs and history would be in the files.
@Observable
@MainActor
final class BrowserAutomaticExport {
    // MARK: - Types

    /// What a check writes.
    enum Due: Equatable {
        /// Nothing yet.
        case none
        /// An export, when something a person would miss changed.
        case ifChanged
        /// An export, whatever changed.
        case always
    }

    private enum Key {
        static let isEnabled = "automaticExport.isEnabled"
        static let folder = "automaticExport.folder"
        static let lastExportedAt = "automaticExport.lastExportedAt"
        static let lastExportPath = "automaticExport.lastExportPath"
        static let fingerprint = "automaticExport.fingerprint"
    }

    // MARK: - Static Variables

    /// How often a check runs.
    nonisolated static let checkInterval: Duration = .seconds(15 * 60)
    /// The shortest time between two exports a change asks for.
    nonisolated static let changeInterval: TimeInterval = 60 * 60
    /// The longest time between two exports.
    nonisolated static let dailyInterval: TimeInterval = 24 * 60 * 60

    /// Where exports go until the person chooses a folder: `Ode Export` in
    /// their Documents folder, or a development build's own folder beside it,
    /// so its exports never take the place of the released app's.
    static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProductIdentity.exportDirectoryName, isDirectory: true)
    }

    // MARK: - Variables

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    /// The folder exports go to while the person has chosen none.
    let defaultFolder: URL

    private(set) var isEnabled: Bool
    private(set) var folder: URL
    private(set) var lastExportedAt: Date?
    /// The dated folder of the newest export, where it can be shown.
    private(set) var lastExportURL: URL?
    private(set) var isWriting = false
    /// Why the latest export was not written, until one is.
    private(set) var failure: String?

    /// The workspace's Spaces that ask for authentication and are locked,
    /// which keep an export from being written.
    var lockedSpaces: [SpaceModel] {
        (browser.workspaceModel?.spaces.models ?? []).filter(spaceAccess.isLocked)
    }

    private let defaults: UserDefaults?
    private let now: () -> Date
    private var fingerprint: String?
    private var checks: Task<Void, Never>?

    // MARK: - Initializers

    /// Reads the person's choices from `defaults`; with none, nothing is
    /// remembered past this launch.
    init(
        browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, defaults: UserDefaults?,
        defaultFolder: URL = BrowserAutomaticExport.documentsFolder, now: @escaping () -> Date = Date.init
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        self.defaults = defaults
        self.defaultFolder = defaultFolder
        self.now = now
        isEnabled = defaults?.object(forKey: Key.isEnabled) as? Bool ?? true
        folder =
            defaults?.string(forKey: Key.folder).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder
        lastExportedAt = defaults?.object(forKey: Key.lastExportedAt) as? Date
        lastExportURL = defaults?.string(forKey: Key.lastExportPath).map { URL(fileURLWithPath: $0, isDirectory: true) }
        fingerprint = defaults?.string(forKey: Key.fingerprint)
    }

    // MARK: - Actions - Scheduling

    /// What a check at `now` writes, given when the newest export was
    /// written. A clock set back counts as a day passed.
    nonisolated static func due(at now: Date, lastExportedAt: Date?) -> Due {
        guard let lastExportedAt else { return .always }
        let elapsed = now.timeIntervalSince(lastExportedAt)
        if elapsed >= dailyInterval || elapsed < 0 { return .always }
        return elapsed >= changeInterval ? .ifChanged : .none
    }

    /// Checks every `checkInterval` until `stop`, the first time one
    /// interval after it starts, so a launch is never slowed by an export.
    func start() {
        guard checks == nil else { return }
        checks = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.checkInterval)
                guard !Task.isCancelled, let self else { return }
                await self.check()
            }
        }
    }

    func stop() {
        checks?.cancel()
        checks = nil
    }

    /// Writes an export when one is due and every Space is open.
    func check() async {
        guard isEnabled else { return }
        switch Self.due(at: now(), lastExportedAt: lastExportedAt) {
        case .none: return
        case .ifChanged: await write(unlessFingerprint: fingerprint)
        case .always: await write(unlessFingerprint: nil)
        }
    }

    // MARK: - Actions - Choices

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults?.set(enabled, forKey: Key.isEnabled)
    }

    /// Sends later exports to `url`. The exports already written stay where
    /// they are.
    func setFolder(_ url: URL) {
        folder = url
        failure = nil
        defaults?.set(url.path, forKey: Key.folder)
    }

    /// Writes an export now, whatever changed.
    func exportNow() async {
        await write(unlessFingerprint: nil)
    }

    // MARK: - Actions - Writing

    /// Asks the core for an export into `folder` away from the main thread,
    /// none when nothing a person would miss changed since `fingerprint`.
    private func write(unlessFingerprint: String?) async {
        guard !isWriting, lockedSpaces.isEmpty else { return }
        isWriting = true
        defer { isWriting = false }
        let core = browser.core
        let query = WriteExportFolder(
            workspaceID: browser.family.workspaceID, folder: folder.path, unlessFingerprint: unlessFingerprint)
        do {
            let written = try await Task.detached(priority: .utility) { try core.query(query) }.value
            fingerprint = written.fingerprint
            defaults?.set(written.fingerprint, forKey: Key.fingerprint)
            failure = nil
            guard let path = written.path else { return }
            let writtenAt = now()
            lastExportedAt = writtenAt
            lastExportURL = URL(fileURLWithPath: path, isDirectory: true)
            defaults?.set(writtenAt, forKey: Key.lastExportedAt)
            defaults?.set(path, forKey: Key.lastExportPath)
        } catch {
            failure = error.personFacingDescription
        }
    }
}
