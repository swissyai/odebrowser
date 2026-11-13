#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import QuartzCore

    /// Calls `tick` once for each frame of the main display, or at `rate`
    /// when no display link can be made.
    @MainActor
    final class BrowserMacHarnessFrameTicker: NSObject {
        var tick: (CADisplayLink?) -> Void = { _ in }
        private var link: CADisplayLink?
        private var timer: Timer?

        func start(rate: Double) {
            if let screen = NSScreen.main {
                let link = screen.displayLink(target: self, selector: #selector(fire(_:)))
                link.add(to: .main, forMode: .common)
                self.link = link
            } else {
                timer = Timer.scheduledTimer(withTimeInterval: 1 / rate, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick(nil) }
                }
            }
        }

        func stop() {
            link?.invalidate()
            link = nil
            timer?.invalidate()
            timer = nil
        }

        @objc private func fire(_ link: CADisplayLink) { tick(link) }
    }

#endif
