import SwiftUI

/// Places a small bounded grid without destroying the source of an active drag.
struct BrowserPinnedTabSlotLayout: Layout {
    let projection: BrowserPinnedTabReorderLayout

    /// An empty slot at the trailing edge of `last`, or at the grid's start
    /// when it has no tiles.
    private static func closedSlot(after last: CGRect?, in bounds: CGRect) -> CGRect {
        guard let last else { return CGRect(origin: bounds.origin, size: .zero) }
        return CGRect(x: last.maxX, y: last.minY, width: 0, height: last.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? BrowserChromeLayout.sidebarIdealWidth
        var resolved = projection
        resolved.availableWidth = width
        return CGSize(width: width, height: resolved.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Measurement and placement use this pass's width, never state from the previous frame.
        var resolved = projection
        resolved.availableWidth = bounds.width
        var resting = resolved
        resting.liftedID = nil
        resting.liftedIDs = []
        resting.insertionIndex = nil
        for (index, subview) in subviews.enumerated() {
            let slot: BrowserPinnedTabReorderLayout.Slot =
                index < projection.ids.count ? .tab(projection.ids[index]) : .gap
            // The invisible source retains a frame and its recognizer even when
            // it has left the grid. It contributes no capacity to this layout.
            // A closed slot waits, empty, after the last tile, so it opens
            // beside the tiles rather than flying in from the grid's corner.
            let lastTile = projection.ids.last.flatMap { resting.frame(for: .tab($0), in: bounds) }
            let frame =
                resolved.frame(for: slot, in: bounds) ?? resting.frame(for: slot, in: bounds)
                ?? Self.closedSlot(after: lastTile, in: bounds)
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
