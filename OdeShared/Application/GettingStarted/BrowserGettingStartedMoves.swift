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

    /// The guide's immediate action, without repeating the reference answer.
    var cue: LocalizedStringResource {
        switch self {
        case .commandBar: "Find anything"
        case .siteSearch: "Search a site"
        case .splitView: "See two pages together"
        case .peek: "Take a quick look"
        case .switchSpace: "Switch spaces"
        case .boost: "Make a site yours"
        case .askAI: "Ask an assistant"
        }
    }

    var hint: LocalizedStringResource {
        switch self {
        case .commandBar: "Find a tab, a setting or something on the web."
        case .siteSearch: "Choose a site in Search settings."
        case .splitView: "Drag a tab from the sidebar onto a page."
        case .peek: "Option-click a link on a web page."
        case .switchSpace: "Choose another Space in the sidebar."
        case .boost: "On a website, choose Page > Boost This Site."
        case .askAI: "Choose an assistant in Search settings."
        }
    }

    var consequence: LocalizedStringResource? {
        switch self {
        case .splitView: "The split stays until you remove it."
        case .boost: "Ode saves the changes for this site in this Space."
        case .askAI: "Your question opens on the assistant’s website."
        default: nil
        }
    }

    /// Guidance stays with the requested site or assistant, and yields when
    /// the person starts an unrelated task. No text is retained here.
    func paletteHint(
        for text: String, provider: SearchProvider?, offer: SearchProvider?, example: String? = nil
    ) -> LocalizedStringResource? {
        if self == .commandBar { return text.isEmpty ? "Type an address or a search." : nil }
        guard self == .siteSearch || self == .askAI else { return nil }
        if let provider {
            guard accepts(provider) else { return nil }
            return self == .askAI ? "Type a question and press Return." : "Type a search and press Return."
        }
        if let offer, accepts(offer) {
            return "Press Tab to use \(offer.title)."
        }
        guard let example, example.lowercased().hasPrefix(text.trimmingCharacters(in: .whitespaces).lowercased())
        else { return nil }
        return "Type \(example)."
    }

    func accepts(_ provider: SearchProvider) -> Bool {
        self == .askAI ? provider.kind == .assistant : self == .siteSearch && provider.kind == .website
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
                        "In Settings > Search, enable a site and Tab to search providers, and check its shortcut."),
                String(localized: "Type that shortcut in the Command Bar. Press Tab when the site is offered."),
                String(localized: "Type your search and press Return."),
            ]
        case .splitView:
            [
                String(localized: "Open two pages, then drag one tab from the sidebar onto the other page."),
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
                String(
                    localized:
                        "With one Space, show the sidebar and right-click an empty area, then choose New Space… Press Control-1 to Control-9 to jump to a Space."
                ),
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
                        "In Settings > Search, enable an AI website and Tab to search providers, and check its shortcut."
                ),
                String(localized: "Type that shortcut in the Command Bar. Press Tab when the assistant is offered."),
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

/// The current window's prerequisites, read without changing its preferences or browsing data.
@MainActor
struct BrowserGettingStartedGuideContext {
    let searchesWithTab: Bool
    let hasOtherSpace: Bool
    let canSplit: Bool
    private let providers: [SearchProvider]

    init(browser: BrowserStore) {
        let catalog = BrowserSearchCatalog(core: browser.core)
        providers = catalog.providers.filter { catalog.isEnabled($0) }
        searchesWithTab = BrowserAppPreferenceStore.shared.preferences.palette.searchesSitesWithTab
        hasOtherSpace = browser.availableSpaces.count > 1
        canSplit = browser.nextSplitJoinCandidate != nil
    }

    func provider(for move: BrowserGettingStartedMove) -> SearchProvider? {
        guard searchesWithTab else { return nil }
        return providers.first { move.accepts($0) }
    }

    func keyword(for move: BrowserGettingStartedMove) -> String? {
        guard let provider = provider(for: move) else { return nil }
        return provider.shortcuts.first ?? provider.site
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

    /// The next unfinished move after the current one, wrapping once.
    func next(after move: BrowserGettingStartedMove) -> BrowserGettingStartedMove? {
        let all = BrowserGettingStartedMove.allCases
        let start = all.firstIndex(of: move) ?? 0
        return (1...all.count).lazy.map { all[(start + $0) % all.count] }.first { !done.contains($0) }
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
