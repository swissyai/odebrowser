import Foundation
import NaturalLanguage
import OSLog
import XCTest

@testable import Ode

/// Tidy Title asks the person's model for a short title: a model that fails
/// leaves the title as it is, says nothing to the person, and notes the
/// provider's own reason in the diagnostic log; Apple's on-device model is
/// asked only about titles in a language Apple Intelligence supports.
@MainActor
final class BrowserTidyTitlesTests: XCTestCase {
    func testAFailingModelLeavesTheTitleAndLogsTheProvidersReason() async throws {
        let started = Date()
        let summary = "The model is unavailable \(UUID().uuidString)."
        let failure = NSError(
            domain: "FoundationModels.LanguageModelSession.GenerationError", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed."])
        let provider = FailingIntelligenceProvider(isAvailable: false, summary: summary, failure: failure)

        let title = await BrowserTidyTitles.title(
            for: "(3) Inbox - Mail - Example", host: "mail.example", using: provider)

        XCTAssertNil(title)
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            at: store.position(date: started),
            matching: NSPredicate(format: "subsystem == %@ AND category == %@", "com.odebrowser.ode", "Intelligence"))
        let messages = entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
        XCTAssertTrue(messages.contains { $0.contains(summary) }, "\(messages)")
        XCTAssertFalse(messages.contains { $0.contains("Inbox") }, "\(messages)")
    }

    func testTheOnDeviceModelReadsTitlesInEveryAppleIntelligenceLanguageAndNoOther() {
        let provider = OnDeviceIntelligenceProvider()
        let titles: [(NLLanguage, String)] = [
            (.danish, "Sådan laver du den bedste rugbrødsmad med æg og rejer"),
            (.dutch, "Hoe maak je de lekkerste appeltaart met kaneel en rozijnen"),
            (.norwegian, "Slik lager du verdens beste vafler med syltetøy og rømme"),
            (.swedish, "Så här bakar du världens bästa kanelbullar hemma"),
            (.turkish, "Evde en güzel mercimek çorbası nasıl yapılır"),
            (.vietnamese, "Cách nấu phở bò ngon tuyệt tại nhà"),
        ]
        for (language, title) in titles {
            XCTAssertEqual(NLLanguageRecognizer.dominantLanguage(for: title), language, title)
            XCTAssertTrue(provider.readsTitle(title), title)
        }
        let polish = "Jak zrobić najlepsze pierogi z kapustą i grzybami"
        XCTAssertEqual(NLLanguageRecognizer.dominantLanguage(for: polish), .polish)
        XCTAssertFalse(provider.readsTitle(polish))
    }
}
