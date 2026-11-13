import AppKit
import SwiftUI

/// Marks the actual card, not its full-window scrim, for native wheel routing.
struct BrowserPlatformCommandPaletteScrollBoundary: NSViewRepresentable {
    func makeNSView(context: Context) -> BoundaryView { BoundaryView() }
    func updateNSView(_ view: BoundaryView, context: Context) {}

    @MainActor
    final class BoundaryView: NSView {
        // MARK: - Static Variables

        private static let boundaries = NSHashTable<BoundaryView>.weakObjects()

        // MARK: - Initializers

        override init(frame: NSRect) {
            super.init(frame: frame)
            Self.boundaries.add(self)
        }

        required init?(coder: NSCoder) { nil }

        // MARK: - Actions - Routing

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }

        static func contains(_ point: NSPoint, in window: NSWindow) -> Bool {
            boundaries.allObjects.contains { boundary in
                boundary.window === window && !boundary.isHiddenOrHasHiddenAncestor
                    && boundary.convert(boundary.bounds, to: nil).contains(point)
            }
        }
    }
}
