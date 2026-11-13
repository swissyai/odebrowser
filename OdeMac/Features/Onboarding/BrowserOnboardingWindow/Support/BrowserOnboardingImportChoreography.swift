import Foundation

/// When each beat of the import stage plays, in seconds from the moment the
/// stage appears. The stage never adds waiting: its beats run beside the
/// import, all of them within `cap`, and once the import is done the stage
/// leaves within `finishCap`, cut short if it must. With Reduce Motion
/// nothing travels: each Space takes its color and its rows in one cross-fade.
struct BrowserOnboardingImportChoreography: Equatable, Sendable {
    // MARK: - Static Variables

    /// The longest the beats run, from the stage appearing to the last.
    static let cap: TimeInterval = 2.4
    /// The longest the stage stays once the import is done.
    static let finishCap: TimeInterval = 0.6
    /// The most favicons that fly, pinned tabs first, then saved ones.
    static let maximumFlights = 8
    /// The most Spaces the stage shows in turn; the summary counts them all.
    static let maximumShownSpaces = 3
    /// How long the import goes without news before the stage stops moving
    /// and says what it is doing.
    static let stallDelay: TimeInterval = 8

    static let settle: TimeInterval = 0.32
    static let flight: TimeInterval = 0.42
    static let flightStagger: TimeInterval = 0.045
    /// How long a flying favicon takes to fade in.
    static let flightFadeIn: TimeInterval = 0.12
    static let takeColor: TimeInterval = 0.36
    static let nameFade: TimeInterval = 0.2
    static let rest: TimeInterval = 0.2
    static let nextSpace: TimeInterval = 0.32
    /// How long the stage rests on a whole Space before the next comes in.
    static let spaceHold: TimeInterval = 0.35
    static let reducedFade: TimeInterval = 0.2

    // MARK: - Variables

    /// The favicons that fly into the first Space.
    let flightCount: Int
    /// The Spaces the stage shows in turn: as many as fit in `cap`.
    private(set) var spaceCount: Int
    let reducesMotion: Bool

    // MARK: - Initializers

    init(flightCount: Int, spaceCount: Int, reducesMotion: Bool) {
        self.flightCount = reducesMotion ? 0 : min(max(flightCount, 0), Self.maximumFlights)
        self.reducesMotion = reducesMotion
        self.spaceCount = min(max(spaceCount, 1), Self.maximumShownSpaces)
        // A Space whose arrival the cap would cut short is left to the
        // summary, so the stage never rests halfway through a swipe.
        while self.spaceCount > 1, lastSpaceEnd(self.spaceCount) > Self.cap {
            self.spaceCount -= 1
        }
    }

    // MARK: - Beats

    /// When the stage has settled into place.
    var settled: TimeInterval { reducesMotion ? Self.reducedFade : Self.settle }

    /// When the favicon at `index` leaves the source browser's icon.
    func flightStart(_ index: Int) -> TimeInterval {
        Self.settle + Double(index) * Self.flightStagger
    }

    /// When the first favicon lands, and the sidebar starts to take the
    /// Space's color.
    var firstLanding: TimeInterval {
        flightCount == 0 ? settled : flightStart(0) + Self.flight
    }

    /// When the last favicon lands, and everything not flown appears.
    var lastLanding: TimeInterval {
        flightCount == 0 ? settled : flightStart(flightCount - 1) + Self.flight
    }

    /// When the first Space is whole: its color taken and its rows in place.
    var firstSpaceWhole: TimeInterval {
        reducesMotion
            ? settled + Self.reducedFade
            : max(firstLanding + Self.takeColor, lastLanding + Self.rest)
    }

    /// When the Space at `index`, from zero, starts to come in.
    func spaceStart(_ index: Int) -> TimeInterval {
        guard index > 0 else { return 0 }
        let step = (reducesMotion ? Self.reducedFade : Self.nextSpace) + Self.spaceHold
        return firstSpaceWhole + Self.spaceHold + Double(index - 1) * step
    }

    /// When the last beat ends, never later than `cap`.
    var end: TimeInterval {
        min(Self.cap, lastSpaceEnd(spaceCount))
    }

    /// When the last of `count` Spaces has fully come in.
    private func lastSpaceEnd(_ count: Int) -> TimeInterval {
        count > 1
            ? spaceStart(count - 1) + (reducesMotion ? Self.reducedFade : Self.nextSpace)
            : firstSpaceWhole
    }

    /// When the stage leaves for an import done at `doneAt`: when its beats
    /// end, but no sooner than the import is done and no later than
    /// `finishCap` after it.
    func dismissal(doneAt: TimeInterval) -> TimeInterval {
        max(doneAt, min(end, doneAt + Self.finishCap))
    }

    /// How far, from 0 to 1, a beat starting at `start` and lasting
    /// `duration` has gone at `time`.
    static func progress(at time: TimeInterval, start: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return min(max((time - start) / duration, 0), 1)
    }
}
