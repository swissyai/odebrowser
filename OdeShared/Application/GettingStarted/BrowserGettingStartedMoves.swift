import Foundation
import Observation

/// One of the seven everyday moves the guide teaches, each in the words of
/// the written answer the Command Bar gives for it, and done when the person
/// does it anywhere in Ode.
enum BrowserGettingStartedMove: String, CaseIterable, Identifiable, Sendable {
    case commandBar
    case siteSearch
    case splitView
    case peek
    case switchSpace
    case boost
    case askAI

    // MARK: - Variables

    var id: String { rawValue }

    /// The written answer whose title, steps and keys the lesson uses.
    var answerID: String {
        switch self {
        case .commandBar: "open-command-bar"
        case .siteSearch: "search-a-site"
        case .splitView: "split-view-create"
        case .peek: "peek"
        case .switchSpace: "switch-space"
        case .boost: "boost-site"
        case .askAI: "ask-ai-from-command-bar"
        }
    }

    var title: String {
        switch self {
        case .commandBar: String(localized: "Open the Command Bar")
        case .siteSearch: String(localized: "Search YouTube, Wikipedia or another site from the Command Bar")
        case .splitView: String(localized: "See two tabs side by side with Split View")
        case .peek: String(localized: "Preview a link without leaving the page")
        case .switchSpace: String(localized: "Switch to another Space")
        case .boost: String(localized: "Restyle a website with a Boost")
        case .askAI: String(localized: "Ask ChatGPT, Claude or Perplexity from the Command Bar")
        }
    }

    /// The steps, in order.
    var steps: [String] {
        switch self {
        case .commandBar:
            [
                String(localized: "Click New Tab in the sidebar, or press Command-T."),
                String(localized: "Type an address, a search, or the name of a tab, setting or command."),
                String(localized: "Press Return."),
            ]
        case .siteSearch:
            [
                String(
                    localized:
                        "Open the Command Bar and type a site's shortcut, such as yt for YouTube or w for Wikipedia."),
                String(localized: "Press Tab. The site's name appears beside the field."),
                String(localized: "Type your search and press Return."),
            ]
        case .splitView:
            [
                String(localized: "Drag a tab from the sidebar onto the page you're looking at."),
                String(localized: "Or right-click a tab in the sidebar and choose Split with Current Tab."),
                String(localized: "Click a side to choose which page the keyboard and address bar use."),
            ]
        case .peek:
            [
                String(localized: "Option-click a link, or right-click it and choose Open Link in Peek."),
                String(localized: "Read it in the Peek over your page."),
                String(localized: "Press Escape to close it, or click Open In… to keep it as a tab."),
            ]
        case .switchSpace:
            [
                String(localized: "Press Control-1 to Control-9 to jump to a Space by its place, as in Arc."),
                String(localized: "Or click the Space's icon at the bottom of the sidebar."),
                String(localized: "Or swipe left or right with two fingers over the sidebar."),
            ]
        case .boost:
            [
                String(localized: "Open the site and choose Page > Boost This Site."),
                String(localized: "Use the Boost bar over the page: Colors, Font, Zap to hide things, or CSS."),
                String(
                    localized:
                        "Click Done. Ode saves it and applies it every time you visit the site in this Space."),
            ]
        case .askAI:
            [
                String(
                    localized:
                        "Open the Command Bar and type the assistant's name, such as chatgpt, claude or perplexity."),
                String(localized: "Press Tab."),
                String(localized: "Type your question and press Return. It opens on the assistant's own site."),
            ]
        }
    }

    /// The default keys, in Mac symbols, or nil.
    var keys: String? {
        switch self {
        case .commandBar: "⌘T"
        case .siteSearch, .askAI: "⇥"
        case .switchSpace: "⌥⌘→"
        case .splitView, .peek, .boost: nil
        }
    }

    /// The window command "Show me" runs to start the move, or nil when the
    /// move needs a page or a link the guide can't hand over.
    var demonstration: ShortcutCommand? {
        switch self {
        case .commandBar, .siteSearch, .askAI: .newTab
        case .splitView: .splitWithNextTab
        case .switchSpace: .nextSpace
        case .peek, .boost: nil
        }
    }
}

/// Which of the seven moves the person has done, kept across launches so the
/// guide resumes where it stopped. The features the moves use report here as
/// the person uses them, in any window.
@Observable
@MainActor
final class BrowserGettingStartedMoves {
    // MARK: - Static Variables

    static let defaultsKey = "GettingStarted.Moves"

    /// The launch's record, which the features report to.
    static var current: BrowserGettingStartedMoves?

    // MARK: - Variables

    private(set) var done: Set<BrowserGettingStartedMove>
    /// A move someone asked the guide to show, which the guide opens to.
    var requestedMove: BrowserGettingStartedMove?
    @ObservationIgnored private let defaults: UserDefaults?

    /// The first move not done yet, in the guide's order.
    var next: BrowserGettingStartedMove? {
        BrowserGettingStartedMove.allCases.first { !done.contains($0) }
    }

    // MARK: - Initializers

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        done = Set(
            (defaults?.stringArray(forKey: Self.defaultsKey) ?? []).compactMap(BrowserGettingStartedMove.init))
    }

    // MARK: - Actions - Recording

    /// Records that the person did `move`.
    func record(_ move: BrowserGettingStartedMove) {
        guard done.insert(move).inserted else { return }
        defaults?.set(done.map(\.rawValue).sorted(), forKey: Self.defaultsKey)
    }

    /// Records `move` in the launch's record, when there is one.
    static func record(_ move: BrowserGettingStartedMove) {
        current?.record(move)
    }

    /// Starts the seven moves over.
    func reset() {
        done = []
        defaults?.removeObject(forKey: Self.defaultsKey)
    }
}
