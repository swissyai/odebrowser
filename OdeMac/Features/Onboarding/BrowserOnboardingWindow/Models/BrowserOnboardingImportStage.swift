import AppKit
import Observation

/// What the import stage shows while setup's import runs: the browser it
/// comes from, the Spaces it brings as Ode will show them, and what the
/// import itself reports. Counts and the summary come from the import's
/// result, never from the clock; the stage's motion only accompanies them.
@Observable
@MainActor
final class BrowserOnboardingImportStage {
    // MARK: - Types

    /// One Space the import brings, as Ode will show it.
    @MainActor
    struct Space: Identifiable {
        nonisolated let id: UUID
        let space: SpaceModel
        let name: String
        /// The tabs whose icons fly in: pinned first, then saved.
        let flights: [TabStateModel]
        let tabCount: Int
        let pinnedCount: Int
        let folderCount: Int

        init(space: SpaceModel) {
            id = space.id
            self.space = space
            name = space.settings.name
            flights = Array(
                (space.pinnedTabs + space.savedTabs).prefix(BrowserOnboardingImportChoreography.maximumFlights))
            tabCount = space.tabs.models.count
            pinnedCount = space.pinnedTabs.count
            folderCount = space.folders.models.count
        }

        /// "Work · 42 tabs · 6 pinned · 4 folders", leaving out what is none.
        var countLine: String {
            var parts = [
                name,
                tabCount == 1
                    ? String(localized: "1 tab", comment: "The one tab an imported Space brings.")
                    : String(localized: "\(tabCount) tabs", comment: "Tabs an imported Space brings."),
            ]
            if pinnedCount > 0 {
                parts.append(String(localized: "\(pinnedCount) pinned", comment: "Pinned tabs a Space brings."))
            }
            if folderCount > 0 {
                parts.append(
                    folderCount == 1
                        ? String(localized: "1 folder", comment: "The one folder a Space brings.")
                        : String(localized: "\(folderCount) folders", comment: "Folders a Space brings."))
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Where the import is.
    enum Phase: Equatable {
        /// Reading what needs the Keychain: saved passwords and sign-ins.
        case reading
        /// Putting the Spaces, tabs and passwords in place.
        case bringing
        /// Done, with how many passwords came over.
        case done(passwords: Int)
    }

    // MARK: - Variables

    let sourceTitle: String
    let sourceIcon: NSImage?
    let favicons: FaviconAssets
    /// Every Space the import brings, in the order the review showed them.
    let spaces: [Space]
    /// The passwords the review chose to bring.
    let passwordCount: Int
    /// What the browser held that the import leaves out.
    let leftOut: [ImportLeftOut]
    let startedAt: Date
    private(set) var phase: Phase
    /// When the import last reported, which tells a stall from work.
    private(set) var lastNewsAt: Date
    private(set) var doneAt: Date?
    /// Whether the person asked the stage to skip to its end.
    private(set) var isSkipped = false

    // MARK: - Initializers

    init(
        sourceTitle: String, sourceIcon: NSImage?, favicons: FaviconAssets, spaces: [SpaceModel],
        passwordCount: Int, readsKeychain: Bool, leftOut: [ImportLeftOut], startedAt: Date = .now
    ) {
        self.sourceTitle = sourceTitle
        self.sourceIcon = sourceIcon
        self.favicons = favicons
        self.spaces = spaces.map(Space.init)
        self.passwordCount = passwordCount
        self.leftOut = leftOut
        self.startedAt = startedAt
        phase = readsKeychain ? .reading : .bringing
        lastNewsAt = startedAt
    }

    // MARK: - Variables - Derived

    /// The Spaces the stage could show in turn; its choreography says how
    /// many fit.
    var shownSpaces: ArraySlice<Space> { spaces.prefix(BrowserOnboardingImportChoreography.maximumShownSpaces) }

    var isDone: Bool { doneAt != nil }

    /// The one line under the window: what the import is doing, or, once it
    /// is done, what came over.
    func statusLine(at date: Date) -> String {
        switch phase {
        case .reading:
            return isStalled(at: date)
                ? String(localized: "Still waiting for \(sourceTitle)'s passwords. macOS may be asking you first.")
                : String(localized: "Reading passwords from \(sourceTitle)")
        case .bringing:
            return isStalled(at: date)
                ? String(localized: "Still bringing your Spaces over from \(sourceTitle).")
                : passwordCount > 0
                    ? String(localized: "Bringing \(passwordCount) passwords and \(spacesPhrase)")
                    : String(localized: "Bringing \(spacesPhrase) from \(sourceTitle)")
        case .done(let passwords):
            let tabs = spaces.reduce(0) { $0 + $1.tabCount }
            var parts = [spacesPhrase, tabs == 1 ? String(localized: "1 tab") : String(localized: "\(tabs) tabs")]
            if passwords > 0 {
                parts.append(
                    passwords == 1 ? String(localized: "1 password") : String(localized: "\(passwords) passwords"))
            }
            return parts.joined(separator: " · ")
        }
    }

    /// "1 Space" or "3 Spaces".
    private var spacesPhrase: String {
        spaces.count == 1 ? String(localized: "1 Space") : String(localized: "\(spaces.count) Spaces")
    }

    /// What the summary says the import left out, or nil.
    var leftOutLine: String? {
        guard !leftOut.isEmpty else { return nil }
        let names = leftOut.prefix(3).map(\.name).joined(separator: ", ")
        let more = leftOut.count > 3 ? String(localized: " and \(leftOut.count - 3) more") : ""
        return String(localized: "Left out: \(names)\(more)")
    }

    /// Whether the import has gone long enough without news that the stage
    /// stops moving and says so.
    func isStalled(at date: Date) -> Bool {
        !isDone && date.timeIntervalSince(lastNewsAt) >= BrowserOnboardingImportChoreography.stallDelay
    }

    // MARK: - Actions - Reporting

    /// The Keychain reading is over; the Spaces are going in.
    func bringing(at date: Date = .now) {
        guard !isDone else { return }
        phase = .bringing
        lastNewsAt = date
    }

    /// The import is done, with `passwords` passwords in place.
    func finish(passwords: Int, at date: Date = .now) {
        guard !isDone else { return }
        phase = .done(passwords: passwords)
        lastNewsAt = date
        doneAt = date
    }

    /// Jumps the beats to their end, as a click or a key asks.
    func skip() {
        isSkipped = true
    }
}
