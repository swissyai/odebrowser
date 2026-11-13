import CoreGraphics

/// A tab row's place in a tree of open tabs, as the core's outline lists it:
/// how many tabs it nests under, how many nest under it however deep, and
/// whether it hides them. A row in no tree has none.
struct BrowserSidebarTabTree: Equatable, Sendable {
    // MARK: - Static Variables

    /// How far a row steps in for each tab it nests under.
    static let indent = OdeSpacing.medium
    /// The deepest a row steps in; a row nested deeper lines up there, so the
    /// title keeps its room in a narrow sidebar.
    static let deepestIndentedLevel = 6

    // MARK: - Variables

    let depth: Int
    let nestedTabs: Int
    let collapsesNestedTabs: Bool

    /// How far the row steps in from the rows at the top level.
    var leadingInset: CGFloat { Self.indent * CGFloat(min(depth, Self.deepestIndentedLevel)) }

    /// Whether tabs nest under the row, which then shows or hides them.
    var holdsNestedTabs: Bool { nestedTabs > 0 }

    // MARK: - Initializers

    init(depth: Int, nestedTabs: Int, collapsesNestedTabs: Bool) {
        self.depth = depth
        self.nestedTabs = nestedTabs
        self.collapsesNestedTabs = collapsesNestedTabs
    }

    /// The place `row` holds, or nil for a row that neither nests nor holds
    /// nested tabs.
    init?(_ row: SidebarRow) {
        guard row.treeDepth > 0 || row.nestedTabs > 0 else { return nil }
        self.init(depth: row.treeDepth, nestedTabs: row.nestedTabs, collapsesNestedTabs: row.collapsesNestedTabs)
    }
}
