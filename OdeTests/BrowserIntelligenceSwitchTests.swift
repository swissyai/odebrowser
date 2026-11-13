import Foundation
import XCTest

@testable import Ode

/// Every model path answers to the one switch in Settings.
@MainActor
final class BrowserIntelligenceSwitchTests: XCTestCase {
    func testIntelligenceIsOffUntilAPersonTurnsItOn() {
        keepPreferences()
        UserDefaults.standard.removeObject(forKey: BrowserIntelligencePreference.enabledKey)

        XCTAssertFalse(BrowserIntelligencePreference.isEnabled)
        XCTAssertNil(BrowserIntelligenceProviderResolver.configuredProvider())
    }

    func testNoFeatureReachesAModelWhileTheSwitchIsOff() async {
        keepPreferences()
        UserDefaults.standard.set(false, forKey: BrowserIntelligencePreference.enabledKey)

        for choice in BrowserIntelligencePreference.Choice.all {
            UserDefaults.standard.set(choice.name, forKey: BrowserIntelligencePreference.providerKey)
            XCTAssertNil(BrowserIntelligenceProviderResolver.configuredProvider(), choice.name)
        }
        UserDefaults.standard.set(true, forKey: BrowserIntelligencePreference.tidyTitlesOnPinKey)
        XCTAssertFalse(BrowserIntelligencePreference.tidyTitlesOnPin)
        let title = await BrowserTidyTitles.title(for: "(3) Inbox - Mail - Example", host: "mail.example")
        XCTAssertNil(title)
        let tabs = (0..<3).map {
            BrowserTidyToday.Tab(id: UUID(), title: "Page \($0)", address: URL(string: "https://site\($0).example/"))
        }
        let proposal = await BrowserTidyToday(tabs: tabs).propose()
        XCTAssertTrue(proposal.groups.isEmpty)
        XCTAssertNotNil(proposal.reason)
    }

    /// Puts the person's own intelligence settings back after the test.
    private func keepPreferences() {
        let switches = [BrowserIntelligencePreference.enabledKey, BrowserIntelligencePreference.tidyTitlesOnPinKey]
        let storedSwitches = switches.map { UserDefaults.standard.object(forKey: $0) as? Bool }
        let storedProvider = UserDefaults.standard.string(forKey: BrowserIntelligencePreference.providerKey)
        addTeardownBlock {
            let defaults = UserDefaults.standard
            for (key, value) in zip(switches, storedSwitches) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            if let storedProvider {
                defaults.set(storedProvider, forKey: BrowserIntelligencePreference.providerKey)
            } else {
                defaults.removeObject(forKey: BrowserIntelligencePreference.providerKey)
            }
        }
    }
}
