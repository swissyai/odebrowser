import Foundation

/// What the palette asks beyond the window it speaks for: the core's ranked
/// answer, the search suggestions and encyclopedia summary that answer
/// allows, the device's dictionary, whether the device is online, and the
/// pasteboard when the palette opens. Each defaults to the device's own; a
/// test or a preview replaces the ones it controls.
@MainActor
struct BrowserCommandPaletteLookups {
    // MARK: - Variables

    /// The answer to a question; nil ranks it in the window's core on a
    /// background thread.
    let answer: (@Sendable (PaletteSuggestions) async -> PaletteAnswer?)?
    /// How long after a keystroke's answer the palette waits before it
    /// fetches suggestions and a summary, so a quick typist sends none.
    let suggestionDebounce: Duration
    let suggestions: @Sendable (URL) async throws -> [String]
    /// Whether the device can reach the internet, so Shift-Return may open a
    /// search's first result rather than act as Return.
    let isOnline: () -> Bool
    /// What the device's dictionary says for a word, looked up on the device,
    /// or nil where it has nothing to say.
    let definition: @Sendable (String) async -> PaletteDefinition?
    /// Shows a word in the device's dictionary, answering whether it could.
    let showInDictionary: (String) -> Bool
    /// The encyclopedia summary a lookup the core named finds, or nil.
    let webSummary: @Sendable (PaletteWebLookup) async -> PaletteWebSummary?
    /// Only Apple’s already-installed on-device models. Never downloads or prompts.
    let translation: @Sendable (PaletteTranslationLookup) async -> PaletteTranslationResult
    /// Private typed-text previews always use Apple's on-device model directly.
    let generativeAnswer: @Sendable (PaletteGenerativeLookup) async -> PaletteGenerativeResult
    let generativeDebounce: Duration
    /// The text on the pasteboard, read once as the palette opens.
    let pasteboard: () -> String?

    // MARK: - Initializers

    init(
        suggestionDebounce: Duration = .milliseconds(250),
        fetchSuggestions: @escaping @Sendable (URL) async throws -> [String] = { address in
            try await BrowserSearchSuggestionClient.shared.suggestions(from: address)
        },
        isOnline: @escaping () -> Bool = { BrowserNetworkPath.shared.isSatisfied },
        lookUpDefinition: @escaping @Sendable (String) async -> PaletteDefinition? = { term in
            await BrowserDictionary.definition(of: term)
        },
        showInDictionary: @escaping (String) -> Bool = { BrowserDictionary.show($0) },
        fetchWebSummary: @escaping @Sendable (PaletteWebLookup) async -> PaletteWebSummary? = { lookup in
            await BrowserWebAnswerClient.shared.summary(for: lookup)
        },
        answer: (@Sendable (PaletteSuggestions) async -> PaletteAnswer?)? = nil,
        translate: @escaping @Sendable (PaletteTranslationLookup) async -> PaletteTranslationResult = { lookup in
            await BrowserPaletteTranslationClient.shared.translate(lookup)
        },
        generativeDebounce: Duration = .milliseconds(300),
        generateAnswer: @escaping @Sendable (PaletteGenerativeLookup) async -> PaletteGenerativeResult = { lookup in
            await BrowserPrivateAnswerClient.shared.answer(lookup)
        },
        readPasteboard: @escaping () -> String? = { nil }
    ) {
        self.answer = answer
        self.suggestionDebounce = suggestionDebounce
        suggestions = fetchSuggestions
        self.isOnline = isOnline
        definition = lookUpDefinition
        self.showInDictionary = showInDictionary
        webSummary = fetchWebSummary
        translation = translate
        self.generativeDebounce = generativeDebounce
        generativeAnswer = generateAnswer
        pasteboard = readPasteboard
    }
}
