import XCTest

@testable import Ode

final class BrowserLaunchSafetyTests: XCTestCase {
    private func decide(_ failedStarts: Int, safeModeFailed: Bool = false, shift: Bool = false, prompts: Bool = true)
        -> BrowserLaunchSafetyDecision
    {
        BrowserLaunchSafety.decide(
            failedStarts: failedStarts, safeModeFailed: safeModeFailed, shiftHeld: shift, promptsAllowed: prompts)
    }

    func testOneFailedStartStartsNormallyAndLooksForAFix() {
        XCTAssertEqual(decide(0), .start(checksForFix: false))
        XCTAssertEqual(decide(1), .start(checksForFix: true))
    }

    func testTwoAndThreeFailedStartsAskAboutSafeMode() {
        XCTAssertEqual(decide(2), .askSafeStart(failedStarts: 2, askedWithShift: false))
        XCTAssertEqual(decide(3), .askSafeStart(failedStarts: 3, askedWithShift: false))
    }

    func testFourFailedStartsOrAFailedSafeModeOfferRecovery() {
        XCTAssertEqual(decide(4), .recover(failedStarts: 4, safeModeFailed: false))
        XCTAssertEqual(decide(1, safeModeFailed: true), .recover(failedStarts: 1, safeModeFailed: true))
    }

    func testShiftAsksEvenAfterGoodStarts() {
        XCTAssertEqual(decide(0, shift: true), .askSafeStart(failedStarts: 0, askedWithShift: true))
        XCTAssertEqual(decide(2, shift: true), .askSafeStart(failedStarts: 2, askedWithShift: false))
    }

    func testASilencedLaunchNeverAsksButStillLooksForAFix() {
        XCTAssertEqual(decide(5, safeModeFailed: true, shift: true, prompts: false), .start(checksForFix: true))
        XCTAssertEqual(decide(0, shift: true, prompts: false), .start(checksForFix: false))
    }

    func testPromptsStayOffUnderTestsAndWhenSilenced() {
        let underTest = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: true)
        XCTAssertFalse(BrowserLaunchSafety.promptsAllowed(underTest, values: [:]))
        let isolated = BrowserLaunchEnvironment(
            values: ["ODE_ISOLATED_SESSION": "1", "ODE_ISOLATED_PERSISTENCE_ID": "safety"], isXCTestRuntime: false)
        if isolated.presentsInstalledApplicationUI {
            XCTAssertFalse(BrowserLaunchSafety.promptsAllowed(isolated, values: [:]))
            XCTAssertTrue(
                BrowserLaunchSafety.promptsAllowed(isolated, values: [BrowserLaunchSafety.isolatedPromptsKey: "1"]))
            XCTAssertFalse(
                BrowserLaunchSafety.promptsAllowed(
                    isolated,
                    values: [BrowserLaunchSafety.isolatedPromptsKey: "1", BrowserLaunchSafety.suppressingKey: "1"]))
        }
    }

    func testSafeModeSaysOnlyWhatItTurnsOff() {
        let now = BrowserSafeMode()
        XCTAssertEqual(now.controls, [.pagesWaitUntilOpened, .syncPaused])
        XCTAssertEqual(
            now.offer,
            "You can start with sync paused and with pages loading only when you open them. Nothing is deleted or changed."
        )
        XCTAssertEqual(now.banner, "Safe mode: sync is off, and pages load when you open them.")

        let withEngine = BrowserSafeMode(controls: [
            .pagesWaitUntilOpened, .syncPaused, .extensionsOff, .graphicsAccelerationOff,
        ])
        // The list follows the locale's own punctuation.
        XCTAssertTrue(withEngine.banner.hasPrefix("Safe mode: extensions, sync"))
        XCTAssertTrue(withEngine.banner.hasSuffix("graphics acceleration are off, and pages load when you open them."))
        XCTAssertTrue(withEngine.offer.hasPrefix("You can start without extensions"))
    }
}
