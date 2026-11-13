import Foundation

/// Answers the icon picker's searches and suggestions off the main actor.
///
/// The catalog is built on first use and released when the picker closes: the
/// symbol name list, the emoji keywords and the concept map are read here,
/// never on the main actor. Each query runs against a searcher that narrows as the person
/// types; a newer query from the same picker supersedes an older one.
actor BrowserIconSearchService {
    // MARK: - Static Variables

    static let shared = BrowserIconSearchService()

    // MARK: - Variables

    private var catalog: BrowserIconCatalog?
    private var symbolSearcher: OdeFuzzySearcher?
    private var emojiSearcher: OdeFuzzySearcher?
    private var suggester: SpaceIconSuggester?
    private let loadSymbolNames: @Sendable () -> [String]

    // MARK: - Initializers

    init(loadSymbolNames: @escaping @Sendable () -> [String] = { BrowserSystemSymbolCatalog.availableNames() }) {
        self.loadSymbolNames = loadSymbolNames
    }

    // MARK: - Actions - Catalog

    func loadedCatalog() -> BrowserIconCatalog {
        if let catalog { return catalog }
        let loaded = BrowserIconCatalog.load(symbolNames: loadSymbolNames())
        catalog = loaded
        symbolSearcher = OdeFuzzySearcher(
            index: OdeFuzzyIndex(
                loaded.symbols.map { .init(primary: $0.name, secondary: $0.keywords.joined(separator: " ")) }))
        emojiSearcher = OdeFuzzySearcher(
            index: OdeFuzzyIndex(
                loaded.emoji.map { .init(primary: $0.choice.name, secondary: $0.keywords.joined(separator: " ")) }))
        suggester = SpaceIconSuggester(catalog: loaded)
        return loaded
    }

    /// Whether the catalog and its searchers are held in memory.
    var isCatalogLoaded: Bool { catalog != nil }

    /// Drops the catalog and everything built from it when the picker closes;
    /// the next search or open rebuilds them.
    func releaseCatalog() {
        catalog = nil
        symbolSearcher = nil
        emojiSearcher = nil
        suggester = nil
    }

    // MARK: - Actions - Searching

    /// Symbol names for `query`, best first.
    func symbols(matching query: String) -> [String] {
        let catalog = loadedCatalog()
        guard let symbolSearcher else { return [] }
        return symbolSearcher.search(query).map { catalog.symbols[Int($0.index)].name }
    }

    /// Emoji choices for `query`, best first.
    func emoji(matching query: String) -> [BrowserTabEmojiChoice] {
        let catalog = loadedCatalog()
        guard let emojiSearcher else { return [] }
        return emojiSearcher.search(query).map { catalog.emoji[Int($0.index)].choice }
    }

    // MARK: - Actions - Suggesting

    /// Symbols and emoji for a Space called `name`.
    func suggestions(for name: String) -> SpaceIconSuggestions {
        _ = loadedCatalog()
        return suggester?.suggestions(for: name) ?? SpaceIconSuggestions()
    }
}
