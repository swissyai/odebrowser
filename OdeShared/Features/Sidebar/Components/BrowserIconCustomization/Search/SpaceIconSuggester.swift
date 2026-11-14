import Foundation
import NaturalLanguage

/// The symbols and emoji suggested for a name, best first.
struct SpaceIconSuggestions: Equatable, Sendable {
    var symbols: [String] = []
    var emoji: [String] = []

    var isEmpty: Bool { symbols.isEmpty && emoji.isEmpty }
}

/// Suggests icons for a Space from its name.
///
/// Three signals are fused, as the picker's research measured best:
/// 1. A hand-written concept map ("work", "job", "office" suggest a
///    briefcase), whose suggestions are pinned first.
/// 2. Lexical matches of the name's words against each symbol's name words
///    and keywords and each emoji's name and CLDR keywords: an exact word
///    scores 1, a plural 0.9, a shared prefix of three or more letters 0.7,
///    and keyword matches four fifths of that.
/// 3. Word-embedding similarity from Apple's English word embedding, which
///    adds recall for names no list anticipates; it is weighted 0.6.
///
/// Variants of one symbol count once. Not thread-safe; give it one owner.
final class SpaceIconSuggester {
    // MARK: - Static Variables

    static let embeddingWeight = 0.6
    /// Words a name carries that never say what the Space is about.
    static let stopWords: Set<String> = [
        "my", "the", "and", "of", "for", "a", "an", "to", "in", "on", "at", "with", "stuff", "things", "misc", "de",
        "la", "le", "les", "el", "los", "las", "das", "der", "die", "und", "et", "y", "e", "i", "mes", "mis", "meine",
    ]

    // MARK: - Variables

    let catalog: BrowserIconCatalog
    private let usesEmbedding: Bool
    private var embedding: NLEmbedding?
    private var didLoadEmbedding = false
    private var vectors: [String: [Float]] = [:]

    // MARK: - Initializers

    init(catalog: BrowserIconCatalog, usesEmbedding: Bool = true) {
        self.catalog = catalog
        self.usesEmbedding = usesEmbedding
    }

    // MARK: - Actions - Suggesting

    func suggestions(for name: String, limit: Int = 8) -> SpaceIconSuggestions {
        let typedEmoji = name.filter { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } }.map(
            String.init)
        let words = BrowserIconCatalog.words(name).filter { !Self.stopWords.contains($0) }
        guard !words.isEmpty || !typedEmoji.isEmpty else { return SpaceIconSuggestions() }
        let phrase = words.joined(separator: " ")
        let concepts = rankedConcepts(words: words, phrase: phrase)
        let similarity = embeddingSimilarity(for: words)

        // Symbols.
        let pinnedSymbols = Self.interleaved(concepts.map { $0.map(\.symbols) })
        var scoredSymbols: [(name: String, score: Double)] = []
        for entry in catalog.symbols where entry.isSuggestible {
            let score = fusedScore(words: words, tokens: entry.tokens, keywords: entry.keywords, similarity: similarity)
            if score > 0.3 { scoredSymbols.append((entry.name, score)) }
        }
        scoredSymbols.sort { $0.score != $1.score ? $0.score > $1.score : $0.name.count < $1.name.count }
        var symbols: [String] = []
        var families = Set<String>()
        for name in pinnedSymbols + scoredSymbols.map(\.name) where symbols.count < limit {
            if families.insert(BrowserIconCatalog.family(of: name)).inserted { symbols.append(name) }
        }

        // Emoji.
        let pinnedEmoji = typedEmoji + Self.interleaved(concepts.map { $0.map(\.emoji) })
        var scoredEmoji: [(emoji: String, score: Double)] = []
        for entry in catalog.emoji {
            let keywordWords = entry.keywords.flatMap { $0.split(separator: " ").map(String.init) }
            let score = fusedScore(words: words, tokens: entry.tokens, keywords: keywordWords, similarity: similarity)
            if score > 0.3 { scoredEmoji.append((entry.choice.emoji, score)) }
        }
        scoredEmoji.sort { $0.score > $1.score }
        var emoji: [String] = []
        var seen = Set<String>()
        for candidate in pinnedEmoji + scoredEmoji.map(\.emoji) where emoji.count < limit {
            let key = candidate.replacingOccurrences(of: "\u{FE0F}", with: "")
            if seen.insert(key).inserted { emoji.append(catalogEmoji(key) ?? candidate) }
        }
        return SpaceIconSuggestions(symbols: symbols, emoji: emoji)
    }

    /// Concepts the name names, strongest first: the share of the name's
    /// words among a concept's terms, plus one when the whole name is the
    /// concept. Concepts that tie for first come back grouped, so their
    /// suggestions can alternate; weaker ones follow.
    func rankedConcepts(words: [String], phrase: String) -> [[SpaceIconConcept]] {
        guard !words.isEmpty else { return [] }
        var ranked: [(concept: SpaceIconConcept, score: Double, order: Int)] = []
        for (order, concept) in catalog.concepts.enumerated() {
            let terms = Set(concept.terms)
            let matched = words.filter { terms.contains($0) || terms.contains(Self.singular($0)) }.count
            guard matched > 0 else { continue }
            var score = Double(matched) / Double(words.count)
            if concept.id == phrase || concept.id == Self.singular(phrase) { score += 1 }
            if score >= 0.5 { ranked.append((concept, score, order)) }
        }
        ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        let kept = ranked.prefix(3)
        guard let top = kept.first?.score else { return [] }
        let leaders = kept.filter { $0.score == top }.map(\.concept)
        let followers = kept.filter { $0.score != top }.map { [$0.concept] }
        return [leaders] + followers
    }

    /// The groups' lists, each group alternating between its concepts, then
    /// the next group.
    private static func interleaved(_ groups: [[[String]]]) -> [String] {
        groups.flatMap { lists -> [String] in
            var merged: [String] = []
            let longest = lists.map(\.count).max() ?? 0
            for index in 0..<longest {
                for list in lists where index < list.count { merged.append(list[index]) }
            }
            return merged
        }
    }

    // MARK: - Actions - Scoring

    private func fusedScore(words: [String], tokens: [String], keywords: [String], similarity: [String: Double])
        -> Double
    {
        var lexical = 0.0
        var semantic = 0.0
        for word in words {
            var best = 0.0
            for token in tokens { best = max(best, Self.lexicalMatch(word, token)) }
            for keyword in keywords { best = max(best, 0.8 * Self.lexicalMatch(word, keyword)) }
            lexical += best
            if !similarity.isEmpty {
                var closest = 0.0
                for token in tokens { closest = max(closest, similarity[token] ?? 0) }
                for keyword in keywords { closest = max(closest, 0.8 * (similarity[keyword] ?? 0)) }
                semantic += closest
            }
        }
        let count = Double(words.count)
        return lexical / count + Self.embeddingWeight * semantic / count
    }

    /// How well a word of the name matches a catalog word: exactly, as a
    /// plural, or as the start of a longer catalog word. A short catalog
    /// word inside a longer name word ("cry" in "crypto") does not count.
    static func lexicalMatch(_ word: String, _ token: String) -> Double {
        if word == token { return 1 }
        if singular(word) == singular(token) { return 0.9 }
        if word.count >= 3, token.hasPrefix(word) { return 0.7 }
        if token.count >= max(4, word.count - 2), word.hasPrefix(token) { return 0.6 }
        return 0
    }

    /// English plurals only; "worker" stays apart from "work".
    static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ses") || word.hasSuffix("xes") || word.hasSuffix("ches") || word.hasSuffix("shes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 { return String(word.dropLast()) }
        return word
    }

    // MARK: - Actions - Embedding

    /// Each catalog word's similarity to the closest of `words`, for the
    /// words the English embedding knows.
    private func embeddingSimilarity(for words: [String]) -> [String: Double] {
        guard usesEmbedding, let embedding = loadedEmbedding() else { return [:] }
        let queries = words.compactMap { vector(for: $0, in: embedding) }
        guard !queries.isEmpty else { return [:] }
        if vectors.isEmpty { cacheCatalogVectors(embedding) }
        var similarity: [String: Double] = [:]
        similarity.reserveCapacity(vectors.count)
        for (word, vector) in vectors {
            var best: Float = 0
            for query in queries {
                var dot: Float = 0
                for index in vector.indices { dot += vector[index] * query[index] }
                best = max(best, dot)
            }
            similarity[word] = Double(best)
        }
        return similarity
    }

    private func loadedEmbedding() -> NLEmbedding? {
        if !didLoadEmbedding {
            didLoadEmbedding = true
            embedding = NLEmbedding.wordEmbedding(for: .english)
        }
        return embedding
    }

    private func cacheCatalogVectors(_ embedding: NLEmbedding) {
        var words = Set<String>()
        for entry in catalog.symbols where entry.isSuggestible {
            words.formUnion(entry.tokens)
            words.formUnion(entry.keywords)
        }
        for entry in catalog.emoji {
            words.formUnion(entry.tokens)
            for keyword in entry.keywords { words.formUnion(keyword.split(separator: " ").map(String.init)) }
        }
        for word in words where !word.contains(" ") {
            if let vector = vector(for: word, in: embedding) { vectors[word] = vector }
        }
    }

    /// The word's vector, scaled to unit length so a dot product is the
    /// cosine.
    private func vector(for word: String, in embedding: NLEmbedding) -> [Float]? {
        guard let values = embedding.vector(for: word) else { return nil }
        let vector = values.map(Float.init)
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? vector.map { $0 / length } : nil
    }

    private func catalogEmoji(_ key: String) -> String? {
        catalog.emoji.first { $0.choice.emoji.replacingOccurrences(of: "\u{FE0F}", with: "") == key }?.choice.emoji
    }
}
