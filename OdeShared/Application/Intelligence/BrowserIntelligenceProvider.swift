import Foundation

// MARK: - Types

/// Whether a provider can answer now, with what a person reads beside the
/// setting: the model it found, or why it cannot run.
struct BrowserIntelligenceAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let summary: String
}

/// A language model that answers a feature's prompt. Only the ChatGPT provider
/// reaches a remote service, and only once the person chose it and signed in;
/// the others run on this device.
protocol BrowserIntelligenceProvider: Sendable {
    func availability() async -> BrowserIntelligenceAvailability

    /// Answers a prompt under short instructions, such as what to write and
    /// how long it may be.
    func complete(instructions: String, prompt: String) async throws -> String
}

/// The provider a person chose in Settings.
enum BrowserIntelligenceProviderResolver {
    /// The configured provider, or nil while the preference is off.
    static func configuredProvider() -> (any BrowserIntelligenceProvider)? {
        guard BrowserIntelligencePreference.isEnabled else { return nil }
        let defaults = UserDefaults.standard
        let choice = BrowserIntelligencePreference.Choice.named(
            defaults.string(forKey: BrowserIntelligencePreference.providerKey)
                ?? BrowserIntelligencePreference.defaultChoice.name)
        return choice.provider(
            endpoint: defaults.string(forKey: BrowserIntelligencePreference.localEndpointKey)
                ?? BrowserIntelligencePreference.defaultLocalEndpoint,
            model: defaults.string(forKey: BrowserIntelligencePreference.localModelKey)
                ?? BrowserIntelligencePreference.defaultLocalModel)
    }
}
