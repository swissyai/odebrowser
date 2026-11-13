import Observation
import SwiftUI

/// Keeping the tab the window shows in view in a scrolling sidebar: where its
/// row sits against the visible part, the offset that brings it into view, the
/// edge it is beyond when the person scrolled it away, and when the sidebar may
/// move on its own.
enum SidebarShownTabReveal {
    // MARK: - Types

    enum Edge: Equatable, Sendable {
        case top
        case bottom
    }

    // MARK: - Static Variables

    /// The room a revealed row keeps from the edge it comes in at.
    static let margin: CGFloat = 24
    /// How long after the person's last scroll the sidebar keeps still.
    static let quietPeriod: Duration = .seconds(1)
    /// The coordinate space of a scrolling sidebar's content, in which a row
    /// reports where it is.
    static let contentSpace = "sidebar-scroll-content"

    // MARK: - Actions - Placement

    /// The offset that shows `row` whole, `margin` in from the edge it comes in
    /// at, or nil when it already shows whole. A row taller than the visible
    /// part shows from its top.
    static func offset(
        revealing row: CGRect, offset: CGFloat, viewportHeight: CGFloat, maximumOffset: CGFloat
    ) -> CGFloat? {
        guard viewportHeight > 0, !row.isEmpty else { return nil }
        let bottom = offset + viewportHeight
        guard row.minY < offset || row.maxY > bottom else { return nil }
        let target =
            row.minY < offset || row.height + margin * 2 > viewportHeight
            ? row.minY - margin : row.maxY + margin - viewportHeight
        let clamped = min(max(0, target), max(0, maximumOffset))
        return abs(clamped - offset) > 0.5 ? clamped : nil
    }

    /// The edge `row` is beyond when less than half of it shows, or nil.
    static func edge(of row: CGRect, offset: CGFloat, viewportHeight: CGFloat) -> Edge? {
        guard viewportHeight > 0, row.height > 0 else { return nil }
        let visible = min(row.maxY, offset + viewportHeight) - max(row.minY, offset)
        guard visible < row.height / 2 else { return nil }
        return row.midY < offset + viewportHeight / 2 ? .top : .bottom
    }

    /// Where the row holding `tabID` falls among the rows of `space`'s
    /// scrolling sidebar, as a fraction from its top: the saved tabs while they
    /// show, then the open tabs, each folder's inside while it is open, and a
    /// collapsed folder's row for a tab inside it. Nil when no row there holds
    /// the tab. A row that was never laid out is first scrolled to by it.
    @MainActor
    static func fraction(of tabID: UUID, in space: SpaceModel) -> CGFloat? {
        var count = 0
        var found: Int?
        func walk(_ list: SidebarListModel, depth: Int) {
            for row in list.rows where !row.isHiddenInTree {
                if found == nil, row.members.contains(tabID) { found = count }
                count += 1
                guard row.kind.opensList else { continue }
                if let folder = space.folders.model(row.id), !folder.isCollapsed, depth < 16 {
                    walk(space.sidebar.inside(row.id), depth: depth + 1)
                } else if found == nil, space.tabIDs(inFolder: row.id).contains(tabID) {
                    found = count - 1
                }
            }
        }
        if space.settings.isSavedTabsExpanded { walk(space.sidebar.section(.saved), depth: 0) }
        walk(space.sidebar.section(.current), depth: 0)
        guard let found, count > 0 else { return nil }
        return (CGFloat(found) + 0.5) / CGFloat(count)
    }

    // MARK: - Actions - Timing

    /// Whether the sidebar may scroll on its own: never while the person
    /// scrolls it or drags in it, nor within `quietPeriod` of their last scroll.
    static func mayScroll(
        isScrolling: Bool, isDragging: Bool, lastPersonScroll: ContinuousClock.Instant?,
        now: ContinuousClock.Instant
    ) -> Bool {
        guard !isScrolling, !isDragging else { return false }
        guard let lastPersonScroll else { return true }
        return now - lastPersonScroll >= quietPeriod
    }
}

/// The live geometry of shown rows in one scrolling sidebar. A row stops
/// reporting when it is no longer shown or laid out: retaining its old frame
/// could reveal the wrong place after tabs are inserted or reordered above it.
@MainActor
@Observable
final class SidebarShownRows {
    // MARK: - Variables

    private var frames: [UUID: CGRect] = [:]

    // MARK: - Actions - Reporting

    func report(_ tabID: UUID, frame: CGRect) {
        guard frames[tabID] != frame else { return }
        frames[tabID] = frame
    }

    func forget(_ tabID: UUID) {
        frames.removeValue(forKey: tabID)
    }

    func frame(of tabID: UUID) -> CGRect? {
        frames[tabID]
    }
}

extension EnvironmentValues {
    /// The rows of shown tabs a scrolling sidebar keeps in view, or nil where
    /// none does.
    @Entry var sidebarShownRows: SidebarShownRows? = nil
}

extension View {
    /// Reports where this row of the tab `tabID` is laid out while its tab is
    /// shown, to the sidebar that keeps it in view.
    func sidebarShownRowReporting(tabID: UUID, isShown: Bool) -> some View {
        modifier(SidebarShownRowReporting(tabID: tabID, isShown: isShown))
    }
}

private struct SidebarShownRowReporting: ViewModifier {
    let tabID: UUID
    let isShown: Bool
    @Environment(\.sidebarShownRows) private var shownRows

    func body(content: Content) -> some View {
        content.background {
            if isShown, let shownRows {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(SidebarShownTabReveal.contentSpace))
                    } action: { frame in
                        shownRows.report(tabID, frame: frame)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onDisappear { shownRows.forget(tabID) }
            }
        }
    }
}
