import Foundation

/// How a docked sidebar shows: in full, with titles, or as a narrow column of
/// icons for small screens, with titles on hover. A sidebar out over the page
/// is always in full, since it is there to be read.
struct BrowserSidebarStyle: Hashable, Sendable {
    // MARK: - Static Variables

    static let key = "ode.appearance.sidebar-style"

    static let full = BrowserSidebarStyle(name: "full", title: "Full", showsIcons: false)
    static let icons = BrowserSidebarStyle(name: "icons", title: "Icons", showsIcons: true)

    static let all = [full, icons]
    static let defaultValue = full

    // MARK: - Variables

    /// How the choice is stored.
    let name: String
    let title: LocalizedStringResource
    let showsIcons: Bool

    /// The style a switch leads to.
    var other: BrowserSidebarStyle { showsIcons ? .full : .icons }

    /// What the menu bar and the Command Bar call switching to the other style.
    var switchTitle: LocalizedStringResource {
        showsIcons ? "Show Full Sidebar" : "Show Sidebar as Icons"
    }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, showsIcons: Bool) {
        self.name = name
        self.title = title
        self.showsIcons = showsIcons
    }

    // MARK: - Actions - Lookup

    /// The style stored as `name`, or the default for a name this build does
    /// not know.
    static func named(_ name: String) -> BrowserSidebarStyle {
        all.first { $0.name == name } ?? defaultValue
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarStyle, rhs: BrowserSidebarStyle) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
