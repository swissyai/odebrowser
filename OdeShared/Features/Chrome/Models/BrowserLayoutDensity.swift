import CoreGraphics
import Foundation

/// How much room the chrome gives its rows and controls: Comfortable, Ode's
/// own spacing, or Compact, which fits more tabs in the same height. Text and
/// icons keep the size Tab scale gives them; only the rows, the gaps between
/// them and the address field change.
struct BrowserLayoutDensity: Hashable, Sendable {
    // MARK: - Static Variables

    static let key = "ode.appearance.density"

    static let comfortable = BrowserLayoutDensity(
        name: "comfortable", title: "Comfortable", rowScale: 1, gapScale: 1,
        addressHeight: BrowserChromeLayout.addressHeight, topTabHeight: 30)
    static let compact = BrowserLayoutDensity(
        name: "compact", title: "Compact", rowScale: 0.75, gapScale: 0.5, addressHeight: 30, topTabHeight: 26)

    static let all = [comfortable, compact]
    static let defaultValue = comfortable

    // MARK: - Variables

    /// How the choice is stored.
    let name: String
    let title: LocalizedStringResource
    /// What a sidebar row's and pinned tile's height is multiplied by.
    let rowScale: CGFloat
    /// What the gaps between sidebar sections and pinned tiles are multiplied by.
    let gapScale: CGFloat
    /// The sidebar address field's height on a pointer shell.
    let addressHeight: CGFloat
    /// The height of one tab in the bar of tabs on top. The bar itself keeps
    /// the window controls' line.
    let topTabHeight: CGFloat

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, rowScale: CGFloat, gapScale: CGFloat, addressHeight: CGFloat,
        topTabHeight: CGFloat
    ) {
        self.name = name
        self.title = title
        self.rowScale = rowScale
        self.gapScale = gapScale
        self.addressHeight = addressHeight
        self.topTabHeight = topTabHeight
    }

    // MARK: - Actions - Lookup

    /// The density stored as `name`, or the default for a name this build does
    /// not know.
    static func named(_ name: String) -> BrowserLayoutDensity {
        all.first { $0.name == name } ?? defaultValue
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserLayoutDensity, rhs: BrowserLayoutDensity) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
