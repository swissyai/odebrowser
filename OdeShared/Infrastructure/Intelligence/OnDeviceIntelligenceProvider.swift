import Foundation
import FoundationModels
import NaturalLanguage

/// Apple's on-device model through FoundationModels. It runs on this device
/// only, once Apple Intelligence is on and its model has downloaded.
@available(iOS 26.0, macOS 26.0, *)
struct OnDeviceIntelligenceProvider: BrowserIntelligenceProvider {
    // MARK: - Static Variables

    /// The sixteen languages Apple Intelligence supports, Chinese in both
    /// scripts, all of which Apple's on-device model reads. A title in any
    /// other language is left alone rather than renamed by a model that
    /// misreads it.
    static let titleLanguages: Set<NLLanguage> = [
        .english, .danish, .dutch, .french, .german, .italian, .norwegian, .portuguese, .spanish, .swedish,
        .turkish, .vietnamese, .simplifiedChinese, .traditionalChinese, .japanese, .korean,
    ]

    /// Input past this many characters is cut so the instructions, the prompt
    /// and the answer fit the model's context window of about 4,096 tokens.
    static let promptCharacterLimit = 6_000

    // MARK: - Actions - Availability

    func availability() async -> BrowserIntelligenceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            BrowserIntelligenceAvailability(
                isAvailable: true, summary: String(localized: "Apple’s on-device model is ready."))
        case .unavailable(let reason):
            BrowserIntelligenceAvailability(isAvailable: false, summary: Self.summary(of: reason))
        }
    }

    private static func summary(of reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            String(localized: "This device can’t run Apple’s on-device model.")
        case .appleIntelligenceNotEnabled:
            String(localized: "Turn on Apple Intelligence in System Settings to use Apple’s on-device model.")
        case .modelNotReady:
            String(localized: "Apple’s on-device model is still downloading. Try again later.")
        @unknown default:
            String(localized: "Apple’s on-device model isn’t available.")
        }
    }

    // MARK: - Actions - Title Language

    /// Whether Apple's on-device model reads the language `title` is in.
    func readsTitle(_ title: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(title)
        guard let language = recognizer.dominantLanguage else { return false }
        return Self.titleLanguages.contains(language)
    }

    // MARK: - Actions - Completion

    func complete(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let response = try await session.respond(to: String(prompt.prefix(Self.promptCharacterLimit)))
        return response.content
    }
}
