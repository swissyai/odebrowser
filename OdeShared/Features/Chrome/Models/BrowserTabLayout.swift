import Foundation

/// Where a window lists its tabs: down the sidebar, as Arc did, or in a bar
/// across the top of the window. With tabs on top the sidebar never docks; it
/// comes out over the page for what only it holds, such as folders, History
/// and Downloads.
struct BrowserTabLayout: Hashable, Sendable {
    // MARK: - Static Variables

    static let key = "ode.appearance.tab-layout"

    static let sidebar = BrowserTabLayout(name: "sidebar", title: "Sidebar", showsTopBar: false)
    static let top = BrowserTabLayout(name: "top", title: "Top", showsTopBar: true)

    static let all = [sidebar, top]
    static let defaultValue = sidebar

    // MARK: - Variables

    /// How the choice is stored.
    let name: String
    let title: LocalizedStringResource
    /// Whether the window lists its tabs in a bar across its top.
    let showsTopBar: Bool

    /// The layout a switch leads to.
    var other: BrowserTabLayout { showsTopBar ? .sidebar : .top }

    /// What the menu bar and the Command Bar call switching to the other
    /// layout.
    var switchTitle: LocalizedStringResource {
        showsTopBar ? "Show Tabs in Sidebar" : "Show Tabs on Top"
    }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, showsTopBar: Bool) {
        self.name = name
        self.title = title
        self.showsTopBar = showsTopBar
    }

    // MARK: - Actions - Lookup

    /// The layout stored as `name`, or the default for a name this build does
    /// not know.
    static func named(_ name: String) -> BrowserTabLayout {
        all.first { $0.name == name } ?? defaultValue
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserTabLayout, rhs: BrowserTabLayout) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
