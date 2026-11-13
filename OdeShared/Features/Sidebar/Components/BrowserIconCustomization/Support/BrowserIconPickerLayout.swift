import SwiftUI

enum BrowserIconPickerMode: Hashable {
    case emoji
    case systemSymbol
    /// One letter or digit, offered where an icon may be one: a Space's.
    case letter
}

enum BrowserIconPickerLayout {
    static let contentWidth: CGFloat = 284
    static let emptyGridHeight: CGFloat = 72
    static let cellSize = max(OdeLayout.minimumHitTarget, 32)
    static let gridSpacing = OdeSpacing.extraSmall
    static let resetTransitionScale = 0.72
    /// Suggestions per row: as many cells as the content width holds.
    static let suggestionCount = 8
    static let selectedFillOpacity = 0.16
    static let selectedBorderWidth: CGFloat = 1.5
    private static let maximumVisibleRows = 4

    private static var columnCount: Int {
        max(Int((contentWidth + gridSpacing) / (cellSize + gridSpacing)), 1)
    }

    static var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellSize), spacing: gridSpacing), count: columnCount)
    }

    static func gridHeight(choiceCount: Int) -> CGFloat {
        let rows = max(Int(ceil(Double(choiceCount) / Double(columnCount))), 1)
        let visibleRows = min(rows, maximumVisibleRows)
        return CGFloat(visibleRows) * cellSize + CGFloat(visibleRows - 1) * gridSpacing
    }
}
