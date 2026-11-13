#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import ObjectiveC

    /// Keeps a harnessed launch's windows away from the person: activation
    /// does nothing, no window enters fullscreen, and every window is placed
    /// off the screens, where it still draws, or with `transparent`, kept
    /// where it is at zero opacity, passing clicks through. Either way it
    /// stays out of Mission Control and window cycling, which would otherwise
    /// lay the person's windows out around one far off every display. A test
    /// host's windows are `shifted` instead: a window that would land on a
    /// screen lands `shift` away from where it was asked to be, so windows keep
    /// where they stand to one another and to the screen points worked out
    /// from them. These also stay out of Mission Control, but keep their native
    /// cycling behavior so tests can exercise window focus routing.
    @MainActor
    enum BrowserMacHarnessWindows {
        // MARK: - Types

        enum Placement {
            /// Every window at `offscreenOrigin`.
            case offscreen
            /// Where it is, at zero opacity, passing clicks through.
            case transparent
            /// Moved by `shift` whenever it would show on a screen.
            case shifted
        }

        // MARK: - Static Variables

        /// Far beyond any display's arrangement.
        static let offscreenOrigin = NSPoint(x: -40_000, y: -40_000)
        /// How far a test host's window moves to stay off every screen.
        static let shift = CGVector(dx: -60_000, dy: -60_000)
        private(set) static var placement = Placement.offscreen
        static var isTransparent: Bool { placement == .transparent }
        private static var isInstalled = false
        /// The titles of the windows asked to enter or leave fullscreen, in
        /// order. A harnessed launch never takes over a display, so the
        /// request is recorded instead of carried out.
        static var fullscreenRequests: [String] = []

        // MARK: - Actions - Installing

        static func install(transparent: Bool) {
            install(transparent ? .transparent : .offscreen)
        }

        static func install(_ placement: Placement) {
            guard !isInstalled else { return }
            isInstalled = true
            self.placement = placement
            exchange(
                NSApplication.self, "activateIgnoringOtherApps:",
                #selector(NSApplication.odeHarnessActivateIgnoring(_:)))
            exchange(NSApplication.self, "activate", #selector(NSApplication.odeHarnessActivateNow))
            exchange(NSWindow.self, "orderWindow:relativeTo:", #selector(NSWindow.odeHarnessOrder(_:relativeTo:)))
            exchange(NSWindow.self, "orderFrontRegardless", #selector(NSWindow.odeHarnessOrderFrontRegardless))
            exchange(NSWindow.self, "toggleFullScreen:", #selector(NSWindow.odeHarnessToggleFullScreen(_:)))
            // A behavior the app sets later keeps the window out too.
            exchange(
                NSWindow.self, "setCollectionBehavior:",
                #selector(NSWindow.odeHarnessSetCollectionBehavior(_:)))
            if placement != .transparent {
                exchange(NSWindow.self, "constrainFrameRect:toScreen:", #selector(NSWindow.odeHarnessConstrain(_:to:)))
                exchange(NSWindow.self, "setFrame:display:", #selector(NSWindow.odeHarnessSetFrame(_:display:)))
                exchange(NSWindow.self, "setAlphaValue:", #selector(NSWindow.odeHarnessSetAlpha(_:)))
                // Sheets and their parents also move through these paths,
                // without calling the two-argument frame setter.
                exchange(NSWindow.self, "center", #selector(NSWindow.odeHarnessCenter))
                exchange(NSWindow.self, "setFrameOrigin:", #selector(NSWindow.odeHarnessSetFrameOrigin(_:)))
                exchange(NSWindow.self, "setFrameTopLeftPoint:", #selector(NSWindow.odeHarnessSetFrameTopLeftPoint(_:)))
                exchange(
                    NSWindow.self, "setFrame:display:animate:",
                    #selector(NSWindow.odeHarnessSetFrame(_:display:animate:)))
            }
        }

        // MARK: - Actions - Placing

        /// Moves `window` where nobody sees it, before it is ordered in.
        static func place(_ window: NSWindow) {
            switch placement {
            case .transparent:
                window.alphaValue = 0
                window.ignoresMouseEvents = true
            case .offscreen:
                if window.frame.origin != offscreenOrigin { window.setFrameOrigin(offscreenOrigin) }
            case .shifted:
                if showsOnAScreen(window.frame) { window.setFrame(window.frame, display: false) }
            }
            window.collectionBehavior = leftOutOfWindowLists(window.collectionBehavior)
            precondition(
                placement == .transparent || !showsOnAScreen(window.frame),
                "A harness window must be outside every display before it is shown.")
        }

        /// Mission Control excludes transient windows. AppKit permits only one
        /// of managed, stationary and transient, and only one cycling flag.
        /// XCTest keeps the caller's cycling flags so native routing remains
        /// testable; ordinary harness runs must never enter the person's cycle.
        fileprivate static func leftOutOfWindowLists(
            _ behavior: NSWindow.CollectionBehavior
        ) -> NSWindow.CollectionBehavior {
            let excluded = behavior.subtracting([.managed, .stationary]).union(.transient)
            return placement == .shifted
                ? excluded : excluded.subtracting(.participatesInCycle).union(.ignoresCycle)
        }

        /// Where a window asked to stand at `frame` goes instead.
        static func placed(_ frame: NSRect) -> NSRect {
            let placed =
                switch placement {
                case .transparent: frame
                case .offscreen: NSRect(origin: offscreenOrigin, size: frame.size)
                case .shifted: showsOnAScreen(frame) ? frame.offsetBy(dx: shift.dx, dy: shift.dy) : frame
                }
            precondition(
                placement == .transparent || !showsOnAScreen(placed),
                "A harness frame must be outside every display before native placement.")
            return placed
        }

        private static func showsOnAScreen(_ frame: NSRect) -> Bool {
            NSScreen.screens.contains { $0.frame.intersects(frame) }
        }

        private static func exchange(_ type: AnyClass, _ original: String, _ replacement: Selector) {
            guard let originalMethod = class_getInstanceMethod(type, NSSelectorFromString(original)),
                let replacementMethod = class_getInstanceMethod(type, replacement)
            else { return }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    extension NSApplication {
        /// Stands in for activation: a harnessed launch never comes forward.
        @objc fileprivate func odeHarnessActivateIgnoring(_ flag: Bool) {}
        @objc fileprivate func odeHarnessActivateNow() {}
    }

    extension NSWindow {
        // After the exchange, each `odeHarness` call below runs AppKit's own.

        @objc fileprivate func odeHarnessOrder(_ place: NSWindow.OrderingMode, relativeTo otherWindow: Int) {
            if place != .out { BrowserMacHarnessWindows.place(self) }
            odeHarnessOrder(place, relativeTo: otherWindow)
        }

        /// Records the request and leaves the window as it is.
        @objc fileprivate func odeHarnessToggleFullScreen(_ sender: Any?) {
            BrowserMacHarnessWindows.fullscreenRequests.append(title)
        }

        @objc fileprivate func odeHarnessOrderFrontRegardless() {
            BrowserMacHarnessWindows.place(self)
            odeHarnessOrderFrontRegardless()
        }

        @objc fileprivate func odeHarnessSetCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
            odeHarnessSetCollectionBehavior(BrowserMacHarnessWindows.leftOutOfWindowLists(behavior))
        }

        @objc fileprivate func odeHarnessConstrain(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
            frame
        }

        @objc fileprivate func odeHarnessSetAlpha(_ alpha: CGFloat) {
            if alpha > 0 { BrowserMacHarnessWindows.place(self) }
            odeHarnessSetAlpha(alpha)
        }

        @objc fileprivate func odeHarnessSetFrame(_ frame: NSRect, display: Bool) {
            odeHarnessSetFrame(BrowserMacHarnessWindows.placed(frame), display: display)
        }

        @objc fileprivate func odeHarnessSetFrame(_ frame: NSRect, display: Bool, animate: Bool) {
            odeHarnessSetFrame(BrowserMacHarnessWindows.placed(frame), display: display, animate: animate)
        }

        @objc fileprivate func odeHarnessCenter() {
            guard let bounds = (screen ?? NSScreen.main)?.visibleFrame else { return }
            let centered = NSRect(
                x: bounds.midX - frame.width / 2, y: bounds.midY - frame.height / 2,
                width: frame.width, height: frame.height)
            setFrame(BrowserMacHarnessWindows.placed(centered), display: false)
        }

        @objc fileprivate func odeHarnessSetFrameOrigin(_ point: NSPoint) {
            let placed = BrowserMacHarnessWindows.placed(NSRect(origin: point, size: frame.size))
            odeHarnessSetFrameOrigin(placed.origin)
        }

        @objc fileprivate func odeHarnessSetFrameTopLeftPoint(_ point: NSPoint) {
            let proposed = NSRect(x: point.x, y: point.y - frame.height, width: frame.width, height: frame.height)
            let placed = BrowserMacHarnessWindows.placed(proposed)
            odeHarnessSetFrameTopLeftPoint(NSPoint(x: placed.minX, y: placed.maxY))
        }
    }

#endif
