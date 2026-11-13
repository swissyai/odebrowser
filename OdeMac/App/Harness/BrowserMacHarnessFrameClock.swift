#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import QuartzCore

    /// Notes when each display frame arrives in a window.
    @MainActor
    final class BrowserMacHarnessFrameClock: NSObject {
        private var link: CADisplayLink?
        private var stamps: [CFTimeInterval] = []

        func start(on view: NSView) {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            stamps.append(link.timestamp)
        }

        /// The frames seen: their count, the usual gap and the longest in
        /// milliseconds, and how many gaps ran past one and a half usual ones.
        func report() -> [String: Any] {
            let gaps = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
            guard !gaps.isEmpty else { return ["frames": stamps.count] }
            let usual = gaps.sorted()[gaps.count / 2]
            return [
                "frames": stamps.count, "usualMilliseconds": usual, "longestMilliseconds": gaps.max() ?? 0,
                "late": gaps.filter { $0 > usual * 1.5 }.count,
            ]
        }
    }

#endif
