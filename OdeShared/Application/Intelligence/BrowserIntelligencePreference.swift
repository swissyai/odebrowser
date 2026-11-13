import Foundation

/// Whether Ode may ask a language model for help, and which one: one on this
/// device, or the person's own ChatGPT plan. Off by default: nothing reads a
/// model until a person turns this on.
enum BrowserIntelligencePreference {
    // MARK: - Types

    /// A provider a person can choose, stored by its name.
    struct Choice: Hashable, Sendable {
        static let onDevice = Choice(
            name: "onDevice", title: "Apple on-device model", usesLocalEndpoint: false,
            makeProvider: { _, _ in OnDeviceIntelligenceProvider() })
        static let local = Choice(
            name: "local", title: "Model on this Mac", usesLocalEndpoint: true,
            makeProvider: { endpoint, model in LocalModelIntelligenceProvider(endpoint: endpoint, model: model) })
        static let chatGPT = Choice(
            name: "chatGPT", title: "ChatGPT", usesLocalEndpoint: false,
            makeProvider: { _, _ in ChatGPTIntelligenceProvider() })
        static let all = [onDevice, local, chatGPT]

        let name: String
        let title: LocalizedStringResource
        /// Whether the provider is a server the person runs, reached through
        /// the endpoint and model settings.
        let usesLocalEndpoint: Bool
        private let makeProvider: @Sendable (_ endpoint: String, _ model: String) -> any BrowserIntelligenceProvider

        /// The stored choice, or the default for a value that is not one of
        /// the choices, such as a hand-edited default.
        static func named(_ name: String) -> Choice {
            all.first { $0.name == name } ?? BrowserIntelligencePreference.defaultChoice
        }

        func provider(endpoint: String, model: String) -> any BrowserIntelligenceProvider {
            makeProvider(endpoint, model)
        }

        static func == (lhs: Choice, rhs: Choice) -> Bool { lhs.name == rhs.name }

        func hash(into hasher: inout Hasher) { hasher.combine(name) }
    }

    // MARK: - Static Variables

    static let enabledKey = "crest.intelligence.enabled"
    static let providerKey = "crest.intelligence.provider"
    static let localEndpointKey = "crest.intelligence.local-endpoint"
    static let localModelKey = "crest.intelligence.local-model"
    /// The ChatGPT model to use; empty or absent picks one the plan offers.
    static let chatGPTModelKey = "crest.intelligence.chatgpt-model"
    static let tidyTitlesOnPinKey = "crest.intelligence.tidy-titles-on-pin"
    static let defaultEnabled = false
    static let defaultChoice = Choice.onDevice
    static let defaultLocalEndpoint = "http://127.0.0.1:11434/v1"
    static let defaultLocalModel = ""
    static let defaultTidyTitlesOnPin = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultEnabled
    }

    /// Whether a tab a person pins or saves gets a tidy title. Off whenever
    /// intelligence is, whatever the stored value.
    static var tidyTitlesOnPin: Bool {
        guard isEnabled else { return false }
        return UserDefaults.standard.object(forKey: tidyTitlesOnPinKey) as? Bool ?? defaultTidyTitlesOnPin
    }
}
