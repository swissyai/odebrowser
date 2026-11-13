import Foundation
import XCTest

@testable import Ode

/// A site's daily limit counts only the time a window shows it with the
/// keyboard, starts again each day, takes five more minutes on request, and
/// keeps its count on this Mac across a relaunch.
@MainActor
final class BrowserFocusTimeKeeperTests: XCTestCase {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_900_000_000)
    }

    private var suiteName = ""
    private var defaults: UserDefaults!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        suiteName = "focus-time-keeper-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testOnlyTheTimeAWindowShowsALimitedSiteCountsAndAPauseEndsWithFiveMoreMinutes() {
        let clock = Clock()
        let keeper = BrowserFocusTimeKeeper(defaults: defaults, calendar: calendar, now: { clock.now })
        let window = UUID()
        let limit = SiteTimeLimit(site: "video.example", minutesPerDay: 10)

        keeper.show("video.example", in: window)
        clock.now += 9 * 60
        XCTAssertFalse(keeper.isPaused("video.example", limit: limit))
        keeper.show(nil, in: window)
        clock.now += 60 * 60
        XCTAssertEqual(keeper.seconds(on: "video.example"), 9 * 60, accuracy: 0.5, "Time away never counts")

        keeper.show("video.example", in: window)
        clock.now += 60
        XCTAssertTrue(keeper.isPaused("video.example", limit: limit))
        XCTAssertFalse(keeper.isPaused("other.example", limit: nil))

        keeper.grantExtraTime(on: "video.example", limit: limit)
        clock.now += 4 * 60
        XCTAssertFalse(keeper.isPaused("video.example", limit: limit))
        clock.now += 61
        XCTAssertTrue(keeper.isPaused("video.example", limit: limit))
    }

    func testTheCountOutlastsARelaunchAndStartsAgainTheNextDay() {
        let clock = Clock()
        let window = UUID()
        let first = BrowserFocusTimeKeeper(defaults: defaults, calendar: calendar, now: { clock.now })
        first.show("news.example", in: window)
        clock.now += 20 * 60
        first.show(nil, in: window)

        let relaunched = BrowserFocusTimeKeeper(defaults: defaults, calendar: calendar, now: { clock.now })
        XCTAssertEqual(relaunched.seconds(on: "news.example"), 20 * 60, accuracy: 0.5)

        clock.now += 24 * 60 * 60
        let nextDay = BrowserFocusTimeKeeper(defaults: defaults, calendar: calendar, now: { clock.now })
        XCTAssertEqual(nextDay.seconds(on: "news.example"), 0)
        XCTAssertFalse(nextDay.isPaused("news.example", limit: SiteTimeLimit(site: "news.example", minutesPerDay: 1)))
    }
}
