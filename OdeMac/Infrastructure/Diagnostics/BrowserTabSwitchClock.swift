import Foundation
import os

/// Times the tab switch in progress: the page pool starts it as a window
/// presents another tab of the same Space, the page host says when the
/// departing page's view is held on screen and when it goes, and the arriving
/// page ends it when it reports its first frame. A switch whose page reports
/// no frame within ``longestWait`` is counted as undrawn; one the next switch
/// overtakes records nothing. A switch to a sleeping tab is also that tab's
/// wake. Each switch is a `Tab Switch` signpost interval.
@MainActor
final class BrowserTabSwitchClock {
    // MARK: - Types

    private struct Pending {
        let page: ObjectIdentifier
        var timing: BrowserTabSwitchTiming
        let interval: OSSignpostIntervalState
        let expiry: Task<Void, Never>
    }

    // MARK: - Static Variables

    static let shared = BrowserTabSwitchClock()
    /// How long the arriving page has to draw: long enough for a sleeping
    /// page to load again from the network.
    static let longestWait: Duration = .seconds(10)

    // MARK: - Variables

    private let moments: BrowserMoments
    private var pending: Pending?

    // MARK: - Initializers

    init(moments: BrowserMoments = .shared) {
        self.moments = moments
    }

    // MARK: - Actions - Switching

    /// A window began showing `page` in place of another tab's page of the
    /// same Space, asked for at `start`.
    func began(
        arriving page: AnyObject, at start: UInt64, framesPerSecond: Int, tags: BrowserMomentLedger.Tags
    ) {
        finish()
        let interval = moments.signposter.beginInterval("Tab Switch", id: moments.signposter.makeSignpostID())
        let page = ObjectIdentifier(page)
        let expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.longestWait)
            guard !Task.isCancelled, let self, self.pending?.page == page else { return }
            self.moments.count(.undrawn)
            self.finish()
        }
        pending = Pending(
            page: page, timing: BrowserTabSwitchTiming(began: start, framesPerSecond: framesPerSecond, tags: tags),
            interval: interval, expiry: expiry)
        moments.began(.tabSwitch, at: start, tags: tags)
    }

    /// The departing page's view stays on screen above the arriving one.
    func departureHeld() {
        pending?.timing.holdDeparture()
    }

    /// The arriving page, which was asleep, started loading: from its kept
    /// history, with its scroll position and typed text, or afresh.
    func loaded(_ page: AnyObject, fromHistory: Bool) {
        guard pending?.page == ObjectIdentifier(page), pending?.timing.tags.slept == true else { return }
        pending?.timing.tags.historyRestored = fromHistory
    }

    /// The held departing page's view left the screen.
    func departed(at time: UInt64 = BrowserMoments.now) {
        pending?.timing.releaseDeparture(at: time)
    }

    /// `page` reported a frame at `time`; when it is the arriving page, the
    /// switch is over.
    func drew(_ page: AnyObject, at time: UInt64 = BrowserMoments.now) {
        guard let switching = pending, switching.page == ObjectIdentifier(page) else { return }
        let outcome = switching.timing.outcome(drawnAt: time)
        moments.record(.tabSwitch, milliseconds: outcome.milliseconds, tags: switching.timing.tags)
        moments.count(.blankFrames, by: outcome.blankFrames)
        if switching.timing.tags.slept == true {
            moments.record(.wake, milliseconds: outcome.milliseconds, tags: switching.timing.tags)
        }
        finish()
    }

    /// Ends the switch in progress, recorded or not.
    private func finish() {
        guard let switching = pending else { return }
        pending = nil
        switching.expiry.cancel()
        moments.signposter.endInterval("Tab Switch", switching.interval)
    }
}
