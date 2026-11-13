import XCTest

@testable import Ode

@MainActor
final class BrowserUpdatePromptTests: XCTestCase {
    private func readyModel(installed: @escaping () -> Void = {}) -> BrowserSoftwareUpdateModel {
        let model = BrowserSoftwareUpdateModel()
        model.presentUpdate(
            title: "Ode 0.9.4", version: "0.9.4", build: "1066", isInformationOnly: false, install: {}, skip: {})
        model.presentReadyToInstall(install: installed, cancel: {})
        return model
    }

    // MARK: - Remind me tomorrow

    func testRemindingTomorrowHidesTheCardForADayAndAPersonsCheckBringsItBack() {
        let model = readyModel()
        var kept: [Date?] = []
        model.reminderChanged = { kept.append($0) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        model.remindTomorrow(now: now)
        XCTAssertNil(model.sidebarWidgetSnapshot)
        XCTAssertEqual(model.remindAfter, now.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(kept, [now.addingTimeInterval(24 * 60 * 60)])

        model.reveal()
        XCTAssertNotNil(model.sidebarWidgetSnapshot)
        XCTAssertNil(model.remindAfter)
        XCTAssertEqual(kept.last, .some(nil))
    }

    func testAReminderFromAnEarlierLaunchHoldsUntilItsDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let waiting = readyModel()
        waiting.restoreReminder(until: now.addingTimeInterval(60), now: now)
        XCTAssertNil(waiting.sidebarWidgetSnapshot)
        waiting.reminderDue()
        XCTAssertNotNil(waiting.sidebarWidgetSnapshot)

        let passed = readyModel()
        passed.restoreReminder(until: now.addingTimeInterval(-60), now: now)
        XCTAssertNotNil(passed.sidebarWidgetSnapshot)
    }

    func testTheReminderSurvivesARelaunch() throws {
        let suite = "ode.tests.update-reminder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = BrowserSoftwareUpdateService(isEnabled: false, preferences: defaults)
        first.model.remindTomorrow()
        XCTAssertNotNil(defaults.object(forKey: BrowserSoftwareUpdateService.reminderPreferenceKey))

        let relaunched = BrowserSoftwareUpdateService(isEnabled: false, preferences: defaults)
        XCTAssertNotNil(relaunched.model.remindAfter)
        XCTAssertTrue(relaunched.model.isHidden)
    }

    func testAnUpdateWaitingOnThePersonOffersTheReminder() {
        let model = readyModel()
        let snapshot = model.snapshot
        XCTAssertTrue(snapshot.phase.cardActions(for: snapshot).contains(.remindUpdateTomorrow))
        XCTAssertFalse(BrowserSoftwareUpdatePhase.checking.cardActions(for: snapshot).contains(.remindUpdateTomorrow))
    }

    // MARK: - Security-only releases

    func testASecurityOnlyReleaseIsMarkedUntilTheNextOffer() {
        let model = readyModel()
        XCTAssertFalse(model.snapshot.isSecurityOnly)
        model.setSecurityOnly(true)
        XCTAssertTrue(model.snapshot.isSecurityOnly)
        model.dismissInstallation()
        XCTAssertFalse(model.snapshot.isSecurityOnly)
    }

    // MARK: - Idle restart

    func testAnIdleMacRestartsToInstallWhenTurnedOn() {
        var installed = 0
        let model = readyModel(installed: { installed += 1 })
        var idle: TimeInterval = 0
        let restart = BrowserIdleRestart(model: model, preferences: nil, idleSeconds: { idle })

        idle = 10 * 60
        XCTAssertFalse(restart.restartIfIdle(), "Off until the person turns it on.")
        restart.isEnabled = true
        idle = 4 * 60
        XCTAssertFalse(restart.restartIfIdle())
        idle = 5 * 60
        XCTAssertTrue(restart.restartIfIdle())
        XCTAssertEqual(installed, 1)
    }

    func testADownloadOrPlayingMediaHoldsTheRestart() {
        var installed = 0
        let model = readyModel(installed: { installed += 1 })
        let restart = BrowserIdleRestart(model: model, preferences: nil, idleSeconds: { 3_600 })
        restart.isEnabled = true
        var downloading = true
        var playing = true
        restart.blockers = [{ downloading }, { playing }]

        XCTAssertFalse(restart.restartIfIdle())
        downloading = false
        XCTAssertFalse(restart.restartIfIdle())
        playing = false
        XCTAssertTrue(restart.restartIfIdle())
        XCTAssertEqual(installed, 1)
    }

    func testNothingRestartsWithoutAnUpdateReadyToInstall() {
        let model = BrowserSoftwareUpdateModel()
        let restart = BrowserIdleRestart(model: model, preferences: nil, idleSeconds: { 3_600 })
        restart.isEnabled = true
        XCTAssertFalse(restart.restartIfIdle())
    }
}
