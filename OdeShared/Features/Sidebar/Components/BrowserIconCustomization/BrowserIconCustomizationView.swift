import SwiftUI

/// Shared icon selection and emoji insertion for tabs, folders, Spaces, and
/// split groups; a Space's icon may also be one letter.
///
/// Given the name the icon is for, it suggests symbols and emoji for that
/// name first. Searches rank symbols and emoji by name and keyword, tolerate
/// a typo, and run off the main actor, as does loading the catalog.
struct BrowserIconCustomizationView: View {
    let title: LocalizedStringKey
    let currentEmoji: String?
    var currentSystemSymbol: String? = nil
    var currentLetter: String? = nil
    var showsReset = false
    var resetTitle: LocalizedStringKey? = nil
    /// The name the icon is for, such as a Space's, whose words suggest
    /// icons; nil where there is none.
    var suggestionContext: String? = nil
    var service: BrowserIconSearchService = .shared
    let setEmoji: (String) -> Void
    var setSystemSymbol: ((String) -> Void)? = nil
    var setLetter: ((String) -> Void)? = nil
    var reset: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = BrowserIconPickerMode.emoji
    @State private var category = BrowserEmojiCategory.people
    @State private var query = ""
    @State private var catalog: BrowserIconCatalog?
    @State private var suggestions = SpaceIconSuggestions()
    @State private var symbolResults: [String]?
    @State private var emojiResults: [BrowserTabEmojiChoice]?

    /// How long the name must rest before its suggestions are worked out.
    private static let suggestionDelay = Duration.milliseconds(150)

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            BrowserIconPickerHeader(
                title: title, showsSystemSymbols: setSystemSymbol != nil, showsLetters: setLetter != nil,
                mode: $mode, showsReset: showsReset, resetTitle: resetTitle,
                reset: reset.map { action in
                    {
                        query = ""
                        action()
                    }
                })
            switch mode {
            case .letter:
                BrowserIconLetterField(letter: currentLetter, setLetter: { setLetter?($0) })
            case .systemSymbol:
                suggestionRows
                BrowserIconSearchField(mode: mode, query: $query, commitEmoji: commitInsertedEmoji)
                BrowserSystemSymbolCatalogGrid(
                    selection: currentSystemSymbol, query: query, catalog: catalog,
                    results: isSearching ? symbolResults ?? [] : nil, select: selectSystemSymbol
                )
                .frame(height: 330)
            case .emoji:
                suggestionRows
                BrowserIconSearchField(mode: mode, query: $query, commitEmoji: commitInsertedEmoji)
                BrowserIconSelectionGrid(
                    emojiChoices: visibleEmojiChoices, currentEmoji: currentEmoji, selectEmoji: selectEmoji)
            }
            if mode == .emoji, query.isEmpty {
                BrowserEmojiCategoryBar(category: $category, contentWidth: BrowserIconPickerLayout.contentWidth)
            }
        }
        .padding(OdeSpacing.large)
        .frame(
            idealWidth: BrowserIconPickerLayout.contentWidth + OdeSpacing.large * 2,
            maxWidth: BrowserIconPickerLayout.contentWidth + OdeSpacing.large * 2,
            alignment: .leading
        )
        .animation(resetAnimation, value: showsReset)
        .onAppear(perform: repairMode)
        .onDisappear { [service] in Task { await service.releaseCatalog() } }
        .onChange(of: query, handlePotentialEmojiInsertion)
        .onChange(of: currentEmoji) { _, _ in repairMode() }
        .task { catalog = await service.loadedCatalog() }
        .task(id: suggestionName) { await loadSuggestions() }
        .task(id: SearchRequest(query: query, mode: mode)) { await search() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-icon-picker")
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionRows: some View {
        if let name = suggestionName, query.isEmpty, !suggestions.isEmpty {
            BrowserIconSuggestionRows(
                name: name, suggestions: suggestions, currentSystemSymbol: currentSystemSymbol,
                currentEmoji: currentEmoji,
                selectSystemSymbol: suggestedSymbolAction,
                selectEmoji: { selectEmoji($0) })
        }
    }

    /// Choosing a suggested symbol, where this icon may be one.
    private var suggestedSymbolAction: ((String) -> Void)? {
        guard setSystemSymbol != nil else { return nil }
        return { symbol in selectSystemSymbol(symbol) }
    }

    private var suggestionName: String? {
        let name = suggestionContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private func loadSuggestions() async {
        guard let name = suggestionName else {
            suggestions = SpaceIconSuggestions()
            return
        }
        try? await Task.sleep(for: Self.suggestionDelay)
        guard !Task.isCancelled else { return }
        let found = await service.suggestions(for: name)
        guard !Task.isCancelled else { return }
        suggestions = found
    }

    // MARK: - Search

    private struct SearchRequest: Equatable {
        let query: String
        let mode: BrowserIconPickerMode
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func search() async {
        guard isSearching else {
            symbolResults = nil
            emojiResults = nil
            return
        }
        switch mode {
        case .systemSymbol:
            let found = await service.symbols(matching: query)
            if !Task.isCancelled { symbolResults = found }
        case .emoji:
            let found = await service.emoji(matching: query)
            if !Task.isCancelled { emojiResults = found }
        case .letter:
            break
        }
    }

    private var visibleEmojiChoices: [BrowserTabEmojiChoice] {
        isSearching ? emojiResults ?? [] : BrowserTabEmojiChoices.choices(in: category)
    }

    // MARK: - Choices

    private var resetAnimation: Animation? {
        OdeMotion.collection.unlessReducingMotion(reduceMotion)
    }

    private func repairMode() {
        if setLetter != nil, currentLetter != nil {
            mode = .letter
            return
        }
        guard setSystemSymbol != nil else {
            mode = .emoji
            return
        }
        mode = currentEmoji == nil ? .systemSymbol : .emoji
    }

    private func handlePotentialEmojiInsertion(_ oldValue: String, _ newValue: String) {
        guard mode == .emoji, let emoji = BrowserIconSymbol.normalizedEmoji(newValue) else { return }
        setEmoji(emoji)
        query = ""
    }

    private func commitInsertedEmoji() {
        guard let emoji = BrowserIconSymbol.normalizedEmoji(query) else { return }
        setEmoji(emoji)
        query = ""
    }

    private func selectEmoji(_ emoji: String) {
        query = ""
        mode = .emoji
        setEmoji(emoji)
    }

    private func selectSystemSymbol(_ symbol: String) {
        query = ""
        mode = .systemSymbol
        setSystemSymbol?(symbol)
    }
}
