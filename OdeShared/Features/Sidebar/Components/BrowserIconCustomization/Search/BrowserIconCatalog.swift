import Foundation

/// One Space-name concept: the words that name it, and the symbols and emoji
/// it suggests, best first.
struct SpaceIconConcept: Decodable, Sendable {
    let id: String
    let terms: [String]
    let symbols: [String]
    let emoji: [String]
}

/// The symbols and emoji the icon picker offers, with the words each can be
/// found by: a symbol's name and the terms of the concepts that suggest it,
/// an emoji's name and its Unicode CLDR keywords.
///
/// Built once, off the main actor. Symbols come in browsing order: base
/// symbols before their filled and enclosed variants, and names led by a
/// digit or a single letter, or written for one script, last.
struct BrowserIconCatalog: Sendable {
    // MARK: - Types

    struct SymbolEntry: Sendable {
        let name: String
        /// The symbol with its fill and enclosure variants folded away, so
        /// "briefcase.circle.fill" and "briefcase" count as one choice.
        let family: String
        let tokens: [String]
        let keywords: [String]
        /// Whether the picker offers it as a suggestion; restricted, digit
        /// and letter symbols are only found by search.
        let isSuggestible: Bool
    }

    struct EmojiEntry: Sendable {
        let choice: BrowserTabEmojiChoice
        let tokens: [String]
        let keywords: [String]
    }

    struct Section: Sendable, Identifiable {
        let id: String
        let title: LocalizedStringResource
        let symbols: [String]
    }

    // MARK: - Variables

    let symbols: [SymbolEntry]
    /// Every symbol's name, in browsing order.
    let symbolNames: [String]
    let emoji: [EmojiEntry]
    let concepts: [SpaceIconConcept]
    /// Curated groups of symbols the picker shows before anything is typed.
    let popularSections: [Section]

    // MARK: - Initializers

    init(
        symbolNames: [String], emojiChoices: [BrowserTabEmojiChoice], concepts: [SpaceIconConcept],
        emojiKeywords: [String: String]
    ) {
        self.concepts = concepts
        let keywordsBySymbol = Self.conceptTerms(concepts.map { ($0.symbols, $0.terms) })
        let keywordsByEmoji = Self.conceptTerms(
            concepts.map { ($0.emoji.map { $0.replacingOccurrences(of: "\u{FE0F}", with: "") }, $0.terms) })
        let entries = symbolNames.map { name in
            SymbolEntry(
                name: name, family: Self.family(of: name), tokens: Self.symbolTokens(name),
                keywords: Self.unique(keywordsBySymbol[name] ?? []), isSuggestible: Self.isSuggestible(name))
        }
        symbols = entries.sorted { lhs, rhs in
            let left = (Self.browsingRank(lhs.name), lhs.family, lhs.name.count, lhs.name)
            let right = (Self.browsingRank(rhs.name), rhs.family, rhs.name.count, rhs.name)
            return left < right
        }
        self.symbolNames = symbols.map(\.name)
        emoji = emojiChoices.map { choice in
            let key = choice.emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
            let cldr = (emojiKeywords[key] ?? "").split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            return EmojiEntry(
                choice: choice, tokens: Self.words(choice.name),
                keywords: Self.unique((keywordsByEmoji[key] ?? []) + cldr.filter { !$0.isEmpty }))
        }
        let available = Set(symbolNames)
        popularSections = Self.sections.map { section in
            var seen = Set<String>()
            var names: [String] = []
            for id in section.concepts {
                guard let concept = concepts.first(where: { $0.id == id }) else { continue }
                for name in concept.symbols.prefix(3) where available.contains(name) {
                    if seen.insert(Self.family(of: name)).inserted { names.append(name) }
                }
            }
            return Section(id: section.id, title: section.title, symbols: names)
        }
    }

    // MARK: - Actions - Loading

    /// The catalog from the bundled resources, for the symbols the running
    /// system can draw.
    static func load(symbolNames: [String], bundle: Bundle = .main) -> BrowserIconCatalog {
        BrowserIconCatalog(
            symbolNames: symbolNames,
            emojiChoices: BrowserTabEmojiChoices.searchableChoices,
            concepts: loadConcepts(bundle: bundle),
            emojiKeywords: loadEmojiKeywords(bundle: bundle))
    }

    static func loadConcepts(bundle: Bundle = .main) -> [SpaceIconConcept] {
        struct Document: Decodable { let concepts: [SpaceIconConcept] }
        guard let url = bundle.url(forResource: "SpaceIconConcepts", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let document = try? JSONDecoder().decode(Document.self, from: data)
        else { return [] }
        return document.concepts
    }

    static func loadEmojiKeywords(bundle: Bundle = .main) -> [String: String] {
        struct Document: Decodable { let keywords: [String: String] }
        guard let url = bundle.url(forResource: "EmojiKeywords", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let document = try? JSONDecoder().decode(Document.self, from: data)
        else { return [:] }
        return document.keywords
    }

    /// Each item's concept terms, from the concepts that rank it highest
    /// first, so a symbol's leading keyword is what it best stands for.
    private static func conceptTerms(_ lists: [(items: [String], terms: [String])]) -> [String: [String]] {
        var contributions: [String: [(rank: Int, order: Int, terms: [String])]] = [:]
        for (order, list) in lists.enumerated() {
            for (rank, item) in list.items.enumerated() {
                contributions[item, default: []].append((rank, order, list.terms))
            }
        }
        return contributions.mapValues { entries in
            entries.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }.flatMap(\.terms)
        }
    }

    // MARK: - Actions - Names

    /// Segments that only vary a symbol's drawing, never its meaning.
    static let variantSegments: Set<String> = ["fill", "circle", "square", "inverse", "rectangle"]

    /// Words in symbol names that say how it is drawn rather than what it is.
    static let structuralWords: Set<String> = [
        "fill", "circle", "square", "rectangle", "inverse", "slash", "badge", "plus", "minus", "and", "on", "with",
        "left", "right", "up", "down", "forward", "backward", "top", "bottom", "trianglehead", "dotted", "dashed",
        "filled", "half", "fullscreen", "portrait", "landscape", "path", "vertical", "horizontal", "open", "closed",
        "counterclockwise", "clockwise", "rotate", "90", "180", "2", "3", "4", "lefthalf", "righthalf",
    ]

    /// The symbol with trailing fill and enclosure segments removed;
    /// currency signs fold into one family.
    static func family(of name: String) -> String {
        var segments = name.split(separator: ".").map(String.init)
        while segments.count > 1, let last = segments.last, variantSegments.contains(last) { segments.removeLast() }
        if segments.count == 1, segments[0].hasSuffix("sign"), segments[0] != "sign" { return "currencysign" }
        return segments.joined(separator: ".")
    }

    static func symbolTokens(_ name: String) -> [String] {
        unique(
            name.split(separator: ".").map(String.init).filter {
                !structuralWords.contains($0) && !$0.allSatisfy(\.isNumber)
            })
    }

    static func words(_ text: String) -> [String] {
        unique(
            OdeFuzzyIndex.fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                .filter { $0.count > 1 })
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }

    /// Two-letter script codes Apple appends to symbols drawn for one
    /// writing system, such as "character.ja".
    private static let scriptSuffixes: Set<String> = [
        "ar", "he", "hi", "ja", "ko", "th", "zh", "zh.traditional", "rtl", "bn", "gu", "kn", "ml", "mr", "or", "pa",
        "ta", "te", "my", "km", "el", "ru", "sat", "mni", "si", "ur", "lo", "ug", "tr",
    ]

    /// Apple's own products and services, which its symbol license reserves
    /// for referring to them.
    private static let productPrefixes = [
        "iphone", "ipad", "ipod", "applewatch", "airpods", "airpod", "homepod", "appletv", "macbook", "macpro",
        "macmini", "imac", "macstudio", "visionpro", "vision.pro", "applelogo", "apple.", "icloud", "airtag",
        "beats.", "facetime", "airplay", "carplay", "applescript", "swift", "xcode", "safari", "appclip", "siri",
        "homekit", "magicmouse", "keyboard.badge", "pencil.tip", "airport", "earpods", "headphones.over",
        "studentdesk.ipad",
    ]

    static func isSuggestible(_ name: String) -> Bool {
        guard let first = name.first, !first.isNumber else { return false }
        let segments = name.split(separator: ".")
        if segments.first?.count == 1 { return false }
        if let last = segments.last, scriptSuffixes.contains(String(last)) { return false }
        return !productPrefixes.contains { name.hasPrefix($0) }
    }

    /// Browsing order: everyday symbols first, letters, digits and
    /// script-specific symbols after them.
    private static func browsingRank(_ name: String) -> Int {
        guard let first = name.first else { return 3 }
        if first.isNumber { return 3 }
        if name.split(separator: ".").first?.count == 1 { return 2 }
        return isSuggestible(name) ? 0 : 1
    }

    // MARK: - Popular

    private struct SectionDefinition {
        let id: String
        let title: LocalizedStringResource
        let concepts: [String]
    }

    private static let sections = [
        SectionDefinition(
            id: "work", title: "Work and study",
            concepts: [
                "work", "project", "startup", "research", "school", "learning", "development", "design", "data",
                "admin", "clients", "email", "calendar", "productivity", "notes", "writing", "ideas", "finance",
            ]),
        SectionDefinition(
            id: "life", title: "Life and home",
            concepts: [
                "personal", "home", "family", "friends", "kids", "pets", "health", "fitness", "food", "cooking",
                "shopping", "garden", "car", "money", "meditation",
            ]),
        SectionDefinition(
            id: "travel", title: "Travel and outdoors",
            concepts: ["travel", "vacation", "beach", "hiking", "camping", "nature", "cycling", "trains", "weather"]),
        SectionDefinition(
            id: "fun", title: "Play and culture",
            concepts: [
                "music", "podcasts", "gaming", "movies", "photos", "art", "books", "sports", "events", "gifts",
                "news", "space",
            ]),
    ]
}

extension BrowserTabEmojiChoices {
    /// One choice per emoji, with skin-tone and other variants grouped
    /// under it as the browsing grid shows them, across every category.
    static var searchableChoices: [BrowserTabEmojiChoice] {
        BrowserEmojiCategory.all.flatMap { choices(in: $0) }
    }
}
