import Foundation

/// Where the Mac shows the address when tabs stay in the sidebar. This is a
/// device appearance choice; it never changes a Space or the mobile shell.
struct BrowserAddressPlacement: Hashable, Sendable {
    // MARK: - Static Variables

    static let top = Self(name: "top", title: "Top", showsTopBar: true)
    static let sidebar = Self(name: "sidebar", title: "Sidebar", showsTopBar: false)
    static let all = [top, sidebar]
    static let defaultValue = top

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let showsTopBar: Bool

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, showsTopBar: Bool) {
        self.name = name
        self.title = title
        self.showsTopBar = showsTopBar
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String) -> Self? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension BrowserAddressPlacement: Codable {
    init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        if let placement = Self.named(name) {
            self = placement
        } else {
            DiagnosticLog.windows.notice("Saved address placement is unknown; using the default top position.")
            self = .defaultValue
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(name)
    }
}
