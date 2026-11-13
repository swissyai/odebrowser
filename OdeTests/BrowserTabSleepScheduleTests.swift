import XCTest

@testable import Ode

/// When a hidden tab's page sleeps: the default delay and the person's own,
/// the protected most recent tabs, the shorter delay in a Space no window
/// shows, and the holds that keep a page loaded whatever the timer says.
final class BrowserTabSleepScheduleTests: XCTestCase {
    private typealias Tab = BrowserTabSleepSchedule.Tab

    private let shownSpace = UUID()
    private let parkedSpace = UUID()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testAnUnsetPreferenceSleepsAfterFifteenMinutesAndAStoredChoiceKeepsItsDelay() throws {
        XCTAssertEqual(SleepingTabsPreference.defaultValue, 15)
        XCTAssertTrue(SleepingTabsPreference.choices.contains(15))
        let unset = try XCTUnwrap(BrowserTabSleepSchedule(stored: nil, shownSpaceIDs: [shownSpace]))
        XCTAssertEqual(unset.delay, 15 * 60)
        let kept = try XCTUnwrap(BrowserTabSleepSchedule(stored: 30, shownSpaceIDs: [shownSpace]))
        XCTAssertEqual(kept.delay, 30 * 60, "A choice the person stored stands when the default moves.")
        XCTAssertNil(BrowserTabSleepSchedule(stored: SleepingTabsPreference.never, shownSpaceIDs: [shownSpace]))
    }

    func testTheFiveHiddenTabsShownMostRecentlyNeverSleepOnTheTimer() throws {
        XCTAssertEqual(BrowserTabSleepSchedule.protectedRecentCount, 5)
        let schedule = try XCTUnwrap(BrowserTabSleepSchedule(stored: 15, shownSpaceIDs: [shownSpace]))
        // Seven tabs shown a minute apart; the last is still on screen.
        let tabs = (0..<7).map { index in
            Tab(
                id: UUID(), spaceID: shownSpace, lastShown: start.addingTimeInterval(Double(index) * 60),
                holds: index == 6 ? .shown : [])
        }
        let nextDay = start.addingTimeInterval(24 * 3_600)

        XCTAssertEqual(
            schedule.tabsToSleep(among: tabs, at: nextDay), [tabs[0].id],
            "Only the hidden tab shown least recently sleeps; the five after it stay, and the shown tab takes no slot.")
        XCTAssertEqual(
            schedule.tabsToSleep(among: Array(tabs[1...]), at: nextDay), [],
            "Five hidden tabs are all protected however long ago they were shown.")
    }

    func testATabInASpaceNoWindowShowsSleepsAfterHalfTheDelay() throws {
        let schedule = try XCTUnwrap(
            BrowserTabSleepSchedule(stored: 15, shownSpaceIDs: [shownSpace], protectedRecentCount: 0))
        let parked = Tab(id: UUID(), spaceID: parkedSpace, lastShown: start)
        let hidden = Tab(id: UUID(), spaceID: shownSpace, lastShown: start)
        XCTAssertEqual(schedule.delay(for: parked), 7.5 * 60)
        XCTAssertEqual(schedule.delay(for: hidden), 15 * 60)

        XCTAssertEqual(schedule.tabsToSleep(among: [parked, hidden], at: start.addingTimeInterval(7.5 * 60 - 1)), [])
        XCTAssertEqual(
            schedule.tabsToSleep(among: [parked, hidden], at: start.addingTimeInterval(7.5 * 60)), [parked.id])
        XCTAssertEqual(
            schedule.tabsToSleep(among: [parked, hidden], at: start.addingTimeInterval(15 * 60 - 1)), [parked.id])
        XCTAssertEqual(
            Set(schedule.tabsToSleep(among: [parked, hidden], at: start.addingTimeInterval(15 * 60))),
            [parked.id, hidden.id])
    }

    func testAHeldTabNeverSleepsOnTheTimer() throws {
        let schedule = try XCTUnwrap(BrowserTabSleepSchedule(stored: 5, shownSpaceIDs: [], protectedRecentCount: 0))
        let holds: [BrowserTabSleepSchedule.Hold] = [
            .shown, .keptLoaded, .agentHeld, .typedText, .playing, .capturing, .pictureInPicture, .transient,
        ]
        let nextWeek = start.addingTimeInterval(7 * 24 * 3_600)
        for hold in holds {
            let held = Tab(id: UUID(), spaceID: parkedSpace, lastShown: start, holds: hold)
            XCTAssertEqual(schedule.tabsToSleep(among: [held], at: nextWeek), [], "\(hold) keeps the page loaded.")
        }
        let free = Tab(id: UUID(), spaceID: parkedSpace, lastShown: start)
        XCTAssertEqual(schedule.tabsToSleep(among: [free], at: nextWeek), [free.id])
    }
}
