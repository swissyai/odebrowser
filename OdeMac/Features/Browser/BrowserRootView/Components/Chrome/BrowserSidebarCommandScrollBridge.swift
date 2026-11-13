import AppKit
import SwiftUI

/// Lets wheel input reach the sidebar while the Command Bar owns all clicks
/// and keyboard focus. It never changes the responder or forwards a click.
struct BrowserSidebarCommandScrollBridge: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> RoutingView { RoutingView() }

    func updateNSView(_ view: RoutingView, context: Context) {
        view.setRoutingEnabled(isEnabled)
    }

    static func dismantleNSView(_ view: RoutingView, coordinator: ()) {
        view.setRoutingEnabled(false)
    }

    /// Lives in a sidebar scrolling document, so ownership follows AppKit's
    /// actual enclosing scroll view even when SwiftUI replaces that view.
    struct DocumentMarker: NSViewRepresentable {
        func makeNSView(context: Context) -> DocumentView { DocumentView() }
        func updateNSView(_ view: DocumentView, context: Context) {}
    }

    @MainActor
    final class DocumentView: NSView {
        // MARK: - Static Variables

        private static let documents = NSHashTable<DocumentView>.weakObjects()

        // MARK: - Initializers

        override init(frame: NSRect) {
            super.init(frame: frame)
            Self.documents.add(self)
        }

        required init?(coder: NSCoder) { nil }

        // MARK: - Actions - Routing

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }

        static func scrollViews(in window: NSWindow) -> [NSScrollView] {
            documents.allObjects.compactMap { document in
                guard document.window === window, !document.isHiddenOrHasHiddenAncestor else { return nil }
                return document.enclosingScrollView
            }
        }
    }

    @MainActor
    final class RoutingView: NSView {
        // MARK: - Variables

        private var monitor: Any?
        private var routingEnabled = false

        // MARK: - Actions - Lifecycle

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            removeMonitor()
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitorIfNeeded()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }

        func setRoutingEnabled(_ enabled: Bool) {
            guard routingEnabled != enabled else { return }
            routingEnabled = enabled
            removeMonitor()
            installMonitorIfNeeded()
        }

        private func installMonitorIfNeeded() {
            guard routingEnabled, monitor == nil, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                    self.routeWheel(event, in: window, at: event.locationInWindow)
                else { return event }
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        // MARK: - Actions - Wheel routing

        /// Uses the original native event, including phase and momentum, so
        /// AppKit keeps ordinary trackpad mechanics without touching the editor.
        @discardableResult
        func routeWheel(_ event: NSEvent, in window: NSWindow, at point: NSPoint) -> Bool {
            guard routingEnabled, event.type == .scrollWheel, self.window === window,
                !isHiddenOrHasHiddenAncestor,
                convert(visibleRect.intersection(bounds), to: nil).contains(point),
                !BrowserPlatformCommandPaletteScrollBoundary.BoundaryView.contains(point, in: window)
            else { return false }
            let target = DocumentView.scrollViews(in: window).filter { scroll in
                !scroll.isHiddenOrHasHiddenAncestor
                    && scroll.convert(scroll.visibleRect.intersection(scroll.bounds), to: nil).contains(point)
            }.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
            guard let target else { return false }
            target.scrollWheel(with: event)
            return true
        }
    }
}
