import SwiftUI

/// The sidebar's edge: drag it to resize the sidebar, drag it narrow to show
/// the sidebar as icons and all the way in to put it away, where the shell
/// can, and double-click it to go back to the standard width, or from icons
/// to the full sidebar.
struct BrowserSidebarResizeHandle: View {
    // MARK: - Variables

    @Binding var width: CGFloat
    var onResizeEnded: (CGFloat) -> Void = { _ in }
    var edge: HorizontalEdge = .leading
    /// Puts the sidebar away once a drag ends far enough in, or nil where the
    /// shell keeps its sidebar.
    var onCollapse: (() -> Void)? = nil
    /// Whether the sidebar shows as a column of icons, which a drag past the
    /// icons threshold opens out into the full sidebar.
    var showsIcons = false
    /// Shows the sidebar as icons, or in full, once a drag ends across the
    /// icons threshold; nil where the shell has no sidebar of icons.
    var onShowIcons: ((Bool) -> Void)? = nil

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragStartWidth: CGFloat?
    @State private var isActive = false
    /// Whether the drag is still under way. A drag the system cancels never
    /// ends, so this answers for it when it resets.
    @GestureState private var isDragging = false

    // MARK: - Actions - Presentation

    var body: some View {
        Color.clear
            .frame(width: BrowserSidebarResizeHandleMetrics.hitWidth)
            .contentShape(.rect)
            .modifier(BrowserPlatformColumnResizePointerModifier())
            .overlay {
                Capsule()
                    .fill(
                        .primary.opacity(
                            isActive
                                ? BrowserSidebarResizeHandleMetrics.activeIndicatorOpacity
                                : 0
                        )
                    )
                    .frame(
                        width: BrowserSidebarResizeHandleMetrics.indicatorWidth,
                        height: BrowserSidebarResizeHandleMetrics.indicatorHeight
                    )
                    .accessibilityHidden(true)
            }
            .gesture(
                // The handle moves as width changes; measure in stationary coordinates.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged(resize)
                    .onEnded(endResize)
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded(resetWidth))
            .onChange(of: isDragging) { _, isDragging in
                // A cancelled drag still settles the width it reached, so the
                // resize it began is never left open.
                guard !isDragging, dragStartWidth != nil else { return }
                finishResize()
            }
            // So does a drag whose handle goes away under it, as when the
            // sidebar is put away mid-drag.
            .onDisappear {
                guard dragStartWidth != nil else { return }
                finishResize()
            }
            .accessibilityLabel("Resize Sidebar")
            .accessibilityValue("\(Int(width.rounded())) points")
            .accessibilityAdjustableAction(adjustWidth)
    }

    // MARK: - Actions - Resize

    private func resize(_ value: DragGesture.Value) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let start = dragStartWidth ?? width
            dragStartWidth = start
            isActive = true
            width = BrowserChromeLayout.clampedSidebarWidth(draggedWidth(value, from: start))
        }
    }

    private func endResize(_ value: DragGesture.Value) {
        let start = dragStartWidth ?? width
        let dragged = draggedWidth(value, from: start)
        resize(value)
        dragStartWidth = nil
        isActive = false
        if let onCollapse, dragged < BrowserChromeLayout.sidebarCollapseWidth {
            // The full sidebar comes back at the width it had before the drag.
            if !showsIcons {
                width = start
                onResizeEnded(start)
            }
            onCollapse()
            return
        }
        if let onShowIcons, dragged < BrowserChromeLayout.sidebarIconsWidth {
            if !showsIcons {
                width = start
                onResizeEnded(start)
                onShowIcons(true)
            }
            return
        }
        if showsIcons, let onShowIcons {
            onShowIcons(false)
            onResizeEnded(BrowserChromeLayout.clampedSidebarWidth(dragged))
            return
        }
        onResizeEnded(width)
    }

    /// Settles a drag that ended without its gesture ending, as a cancelled
    /// one or one whose handle went away, at the width it reached.
    private func finishResize() {
        dragStartWidth = nil
        isActive = false
        onResizeEnded(width)
    }

    /// The width the pointer asks for, before it is held to the sidebar's
    /// limits.
    private func draggedWidth(_ value: DragGesture.Value, from start: CGFloat) -> CGFloat {
        start + layoutDirection.sidebarResizeDelta(value.translation.width) * (edge == .leading ? 1 : -1)
    }

    private func resetWidth() {
        if showsIcons, let onShowIcons {
            onShowIcons(false)
            return
        }
        width = BrowserChromeLayout.sidebarIdealWidth
        onResizeEnded(width)
    }

    private func adjustWidth(_ direction: AccessibilityAdjustmentDirection) {
        let delta: CGFloat
        switch direction {
        case .increment:
            delta = BrowserSidebarResizeHandleMetrics.accessibilityStep
        case .decrement:
            delta = -BrowserSidebarResizeHandleMetrics.accessibilityStep
        @unknown default:
            delta = 0
        }
        guard delta != 0 else { return }
        width = BrowserChromeLayout.clampedSidebarWidth(width + delta)
        onResizeEnded(width)
    }
}
