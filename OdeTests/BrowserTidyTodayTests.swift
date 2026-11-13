import Foundation
import XCTest

@testable import Ode

/// Tidy Open Tabs when the person's model fails: the duplicates the code
/// found without it are still offered, and the reason given is a sentence
/// Ode wrote, never the error a framework threw.
@MainActor
final class BrowserTidyTodayTests: XCTestCase {
    private let failure = NSError(
        domain: "FoundationModels.LanguageModelSession.GenerationError", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed."])

    func testAFailingModelStillOffersTheDuplicatesWithTheProvidersReason() async {
        let tabs = Self.tabs([
            "https://a.example/", "https://b.example/", "https://a.example/#top", "https://c.example/",
        ])
        let summary = "Apple’s on-device model is still downloading. Try again later."
        let provider = FailingIntelligenceProvider(isAvailable: false, summary: summary, failure: failure)

        let proposal = await BrowserTidyToday(tabs: tabs).propose(using: provider)

        XCTAssertEqual(proposal.groups, [])
        XCTAssertEqual(proposal.duplicates, [tabs[2]])
        XCTAssertEqual(proposal.reason, summary)
    }

    func testAModelThatFailsWhileAvailableSaysItSuggestedNoGroups() async {
        let tabs = Self.tabs(["https://a.example/", "https://b.example/", "https://c.example/"])
        let provider = FailingIntelligenceProvider(isAvailable: true, summary: "Ready.", failure: failure)

        let proposal = await BrowserTidyToday(tabs: tabs).propose(using: provider)

        XCTAssertTrue(proposal.isEmpty)
        XCTAssertEqual(proposal.reason, String(localized: "The model didn’t suggest any groups."))
        XCTAssertNotEqual(proposal.reason, failure.localizedDescription)
    }

    /// One open tab per address, in order.
    private static func tabs(_ addresses: [String]) -> [BrowserTidyToday.Tab] {
        addresses.enumerated().map { index, address in
            BrowserTidyToday.Tab(id: UUID(), title: "Page \(index)", address: URL(string: address))
        }
    }
}
