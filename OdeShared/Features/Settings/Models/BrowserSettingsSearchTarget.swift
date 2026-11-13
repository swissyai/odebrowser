import Foundation

/// A setting a Settings search lands on: the page it lives on, its name as
/// the row shows it, and other words a person might type for it.
///
/// The row marks itself with `settingsSearchTarget(_:)`. While the search
/// matches it, the page lists in the sidebar, the page scrolls to the first
/// row that matches, and every row that matches is marked. `name` is the
/// row's scroll identity, so it never changes.
struct BrowserSettingsSearchTarget: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let defaultBrowser = Self(
        name: "default-browser", on: .general, title: "Default browser", terms: "make default links open with")
    static let startup = Self(
        name: "startup", on: .general, title: "When Ode opens",
        terms: "startup launch open start page restore last session windows")
    static let defaultSpace = Self(
        name: "default-space", on: .general, title: "Default Space", terms: "new window Space start")
    static let spelling = Self(
        name: "spelling", on: .general, title: "Check spelling", terms: "spell spellcheck typing mistakes")
    static let pictureInPicture = Self(
        name: "picture-in-picture", on: .general, title: "Picture in Picture when switching tabs",
        terms: "PiP video floating player")
    static let newTabsFromLinks = Self(
        name: "new-tabs-from-links", on: .tabs, title: "Switch to tabs opened from links",
        terms: "focus background new tab open links")
    static let defaultSearch = Self(
        name: "default-search", on: .search, title: "Default search",
        terms: "search engine Google DuckDuckGo Bing Kagi Ecosia Brave")
    static let searchSuggestions = Self(
        name: "search-suggestions", on: .search, title: "Search suggestions", terms: "suggest autocomplete")
    static let privateSearch = Self(
        name: "private-search", on: .search, title: "Private windows", terms: "private search engine incognito")
    static let tabToSearch = Self(
        name: "tab-to-search", on: .search, title: "Tab to search providers", terms: "site search shortcut provider")
    static let resultsLayout = Self(
        name: "results-layout", on: .search, title: "Layout", terms: "results command bar palette blended sections")
    static let topHit = Self(
        name: "top-hit", on: .search, title: "Top Hit", terms: "results best match command bar palette")
    static let preferOpenTabs = Self(
        name: "prefer-open-tabs", on: .search, title: "Prefer open tabs", terms: "results ranking command bar palette")
    static let matchReasons = Self(
        name: "match-reasons", on: .search, title: "Show match reasons", terms: "results often visited already open")
    static let completeAddresses = Self(
        name: "complete-addresses", on: .search, title: "Complete addresses inline",
        terms: "autocomplete completion typing URL")
    static let learnChoices = Self(
        name: "learn-choices", on: .search, title: "Learn from my choices", terms: "typing ranking learned results")
    static let clearLearnedChoices = Self(
        name: "clear-learned-choices", on: .search, title: "Clear Learned Choices",
        terms: "forget reset learned results")
    static let paletteSources: [Self] = PaletteSource.all.map { source in
        Self(
            name: "palette-source-\(source.name)", on: .search, title: source.title,
            terms: source.detail ?? "results command bar palette")
    }
    static let tabLayout = Self(
        name: "tab-layout", on: .lookAndFeel, title: "Tabs",
        terms: "tabs on top top tabs horizontal tab bar vertical tabs sidebar layout")
    static let sidebarSide = Self(
        name: "sidebar-on-right", on: .lookAndFeel, title: "Sidebar on right", terms: "right side left side position")
    static let windowBorder = Self(
        name: "window-border", on: .lookAndFeel, title: "Window border", terms: "border frame ring borderless edge")
    static let sleepingTabs = Self(
        name: "sleeping-tabs", on: .lookAndFeel, title: "Put tabs to sleep after",
        terms: "sleeping tabs sleep memory unload")
    static let intelligence = Self(
        name: "intelligence", on: .search, title: "Tab organization",
        terms:
            "Tab organization Enable suggestions Ode Intelligence AI model ChatGPT Apple Intelligence on-device local model language model tidy titles tabs folders"
    )
    static let externalLinks = Self(
        name: "external-links", on: .links, title: "Open in",
        terms: "links from other apps external links default Quick Window")
    static let allowAgents = Self(
        name: "allow-agents", on: .agents, title: "Allow agents to use Ode",
        terms: "agents MCP Claude Code Codex automation coding agents")
    static let agentScripts = Self(
        name: "agent-scripts", on: .agents, title: "Let agents run scripts in pages", terms: "JavaScript scripts")
    static let camera = Self(
        name: "permission-camera", on: .privacy, title: "Camera", terms: "camera video calls permission access")
    static let microphone = Self(
        name: "permission-microphone", on: .privacy, title: "Microphone",
        terms: "microphone audio recording permission access")
    static let location = Self(
        name: "permission-location", on: .privacy, title: "Location", terms: "location geolocation permission access")
    static let notifications = Self(
        name: "permission-notifications", on: .privacy, title: "Notifications",
        terms: "notifications alerts permission access")
    static let passkeys = Self(
        name: "permission-passkeys", on: .privacy, title: "Passkeys",
        terms: "passkeys sign in system providers permission access")
    static let files = Self(
        name: "permission-files", on: .privacy, title: "Files & Folders",
        terms: "files folders download folder permission access")
    static let importBrowser = Self(
        name: "import-browser", on: .advanced, title: "Import from Another Browser",
        terms: "import Arc Chrome Safari Firefox Brave Edge Zen Dia move switch")
    static let automaticExport = Self(
        name: "automatic-export", on: .advanced, title: "Export automatically",
        terms: "automatic export backup daily copy")
    static let automaticUpdates = Self(
        name: "automatic-updates", on: .about, title: "Check for updates automatically",
        terms: "update updates software new version")
    static let automaticInstall = Self(
        name: "automatic-install", on: .about, title: "Download and install updates automatically",
        terms: "install update download")
    static let idleRestart = Self(
        name: "idle-restart", on: .about, title: "Restart to update when this Mac is idle",
        terms: "restart idle relaunch update")
    static let updateChannel = Self(
        name: "update-channel", on: .about, title: "Update channel", terms: "beta nightly development stable channel")
    static let earlierVersion = Self(
        name: "earlier-version", on: .about, title: "Go back to an earlier version",
        terms: "rollback roll back downgrade older previous version")
    static let crashReports = Self(
        name: "crash-reports", on: .about, title: "When Ode has a report", terms: "crash hang report diagnostics")

    /// Every target, in the order their pages show them.
    static let all: [Self] =
        [
            defaultBrowser, startup, defaultSpace, spelling, pictureInPicture, newTabsFromLinks, defaultSearch,
            searchSuggestions, privateSearch, tabToSearch, intelligence, resultsLayout, topHit, preferOpenTabs,
            matchReasons,
            completeAddresses, learnChoices, clearLearnedChoices,
            tabLayout, sidebarSide, windowBorder, sleepingTabs, externalLinks,
            allowAgents, agentScripts, camera, microphone, location, notifications, passkeys, files,
            importBrowser, automaticExport, automaticUpdates, automaticInstall, idleRestart,
            updateChannel, earlierVersion, crashReports,
        ] + paletteSources

    // MARK: - Variables

    let name: String
    let destination: BrowserSettingsDestination
    let title: LocalizedStringResource
    let terms: LocalizedStringResource

    /// The row's scroll identity on its page.
    var id: String { "settings-target-\(name)" }

    // MARK: - Initializers

    private init(
        name: String, on destination: BrowserSettingsDestination, title: LocalizedStringResource,
        terms: LocalizedStringResource
    ) {
        self.name = name
        self.destination = destination
        self.title = title
        self.terms = terms
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String) -> Self? {
        all.first { $0.name == name }
    }

    /// The targets on `destination`'s page that `query` matches, in page
    /// order.
    static func matching(_ query: String, on destination: BrowserSettingsDestination, locale: Locale) -> [Self] {
        all.filter { $0.destination == destination && $0.matches(query, locale: locale) }
    }

    /// The words a Settings search finds the target by.
    var searchHaystack: [LocalizedStringResource] { [title, terms] }

    /// Whether every word of `query` is in the target's title or terms.
    func matches(_ query: String, locale: Locale) -> Bool {
        BrowserSettingsSearch.matches(query, in: searchHaystack, locale: locale)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
