import Foundation

/// A fixed list of short texts prepared once for fuzzy search.
///
/// Each entry has a primary text (a name) and a secondary one (keywords);
/// both are folded to lowercase without diacritics and stored in one flat
/// byte buffer, with a boundary bonus per byte and a 64-bit character mask
/// per entry. Matching follows fzf's scoring: a query is an ordered
/// subsequence of an entry, each matched character scores 16, a gap costs 3
/// to open and 1 to extend, and characters at word starts, after a delimiter,
/// at a camelCase hump or at a letter-digit change earn a bonus, doubled for
/// the query's first character. A match that ends inside the primary text
/// keeps its full score; one found only in the keywords keeps four fifths. A
/// token that is a whole word earns more, and more again as the entry's or
/// its keywords' first word. A token found only spread across words is weak:
/// such matches rank after every other kind, typos included.
struct OdeFuzzyIndex: Sendable {
    // MARK: - Static Variables

    static let scoreMatch: Int32 = 16
    static let scoreGapStart: Int32 = -3
    static let scoreGapExtension: Int32 = -1
    static let bonusBoundary: Int32 = 8
    static let bonusBoundaryWhite: Int32 = 10
    static let bonusBoundaryDelimiter: Int32 = 9
    static let bonusCamel123: Int32 = 7
    static let bonusConsecutive: Int32 = 4
    static let bonusFirstCharMultiplier: Int32 = 2
    /// Added when a query token is a whole word of the entry, enough to rank
    /// an exact keyword above a prefix of a name.
    static let bonusExactWord: Int32 = 48
    /// Added on top when that whole word leads the name or the keywords.
    static let bonusLeadingWord: Int32 = 32
    /// The score a weak match earns per character, enough only to order the
    /// weak tail by length.
    static let weakScorePerCharacter: Int32 = 4
    /// Entries are cut to this many bytes, which every name and keyword
    /// list in the picker's corpus fits.
    static let maximumLength = 255
    /// Whether this module was compiled with optimization; search timing
    /// only means something when it was.
    static var isOptimizedBuild: Bool { !_isDebugAssertConfiguration() }

    // MARK: - Types

    struct Entry: Sendable {
        var primary: String
        var secondary = ""
    }

    // MARK: - Variables

    let count: Int
    fileprivate let bytes: [UInt8]
    fileprivate let bonuses: [Int8]
    fileprivate let starts: [Int32]
    fileprivate let primaryEnds: [Int32]
    fileprivate let masks: [UInt64]

    // MARK: - Initializers

    init(_ entries: [Entry]) {
        var bytes: [UInt8] = []
        var bonuses: [Int8] = []
        var starts: [Int32] = [0]
        var primaryEnds: [Int32] = []
        var masks: [UInt64] = []
        bytes.reserveCapacity(entries.count * 32)
        bonuses.reserveCapacity(entries.count * 32)
        for entry in entries {
            let primary = Self.prepared(entry.primary)
            let secondary = entry.secondary.isEmpty ? (bytes: [], bonuses: []) : Self.prepared(entry.secondary)
            var text = primary.bytes
            var classes = primary.bonuses
            if !secondary.bytes.isEmpty {
                text.append(UInt8(ascii: " "))
                classes.append(0)
                text += secondary.bytes
                // The keywords start a new word after the separating space.
                var keywordBonuses = secondary.bonuses
                if !keywordBonuses.isEmpty { keywordBonuses[0] = Int8(Self.bonusBoundaryWhite) }
                classes += keywordBonuses
            }
            if text.count > Self.maximumLength {
                text.removeLast(text.count - Self.maximumLength)
                classes.removeLast(classes.count - Self.maximumLength)
            }
            var mask: UInt64 = 0
            for byte in text { mask |= Self.maskBit(byte) }
            bytes += text
            bonuses += classes
            primaryEnds.append(Int32(min(primary.bytes.count, Self.maximumLength)))
            starts.append(Int32(bytes.count))
            masks.append(mask)
        }
        count = entries.count
        self.bytes = bytes
        self.bonuses = bonuses
        self.starts = starts
        self.primaryEnds = primaryEnds
        self.masks = masks
    }

    // MARK: - Actions - Preparation

    /// `text` folded for matching, with the bonus each byte earns.
    static func prepared(_ text: String) -> (bytes: [UInt8], bonuses: [Int8]) {
        let folded = Array(fold(text).utf8)
        let original = Array(text.utf8)
        // CamelCase is read from the original casing when folding kept the
        // byte layout, as it does for the ASCII names this index holds.
        let casing = original.count == folded.count ? original : folded
        var bonuses = [Int8](repeating: 0, count: folded.count)
        var previous = ByteClass.white
        for index in folded.indices {
            let current = ByteClass(casing[index])
            bonuses[index] = Int8(bonus(previous: previous, current: current))
            previous = current
        }
        return (folded, bonuses)
    }

    /// Lowercased, without diacritics, with runs of whitespace kept as is.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func maskBit(_ byte: UInt8) -> UInt64 {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"): 1 << UInt64(byte - UInt8(ascii: "a"))
        case UInt8(ascii: "0")...UInt8(ascii: "9"): 1 << UInt64(26 + byte - UInt8(ascii: "0"))
        default: 1 << UInt64(36 + byte % 28)
        }
    }

    private static func bonus(previous: ByteClass, current: ByteClass) -> Int32 {
        guard current.isWordCharacter else { return 0 }
        switch previous {
        case .white: return bonusBoundaryWhite
        case .delimiter: return bonusBoundaryDelimiter
        case .other: return bonusBoundary
        case .lower where current == .upper: return bonusCamel123
        case .lower where current == .digit, .upper where current == .digit: return bonusCamel123
        case .digit where current != .digit: return bonusCamel123
        default: return 0
        }
    }

    private enum ByteClass: Equatable {
        case white, delimiter, other, lower, upper, digit, letter

        init(_ byte: UInt8) {
            switch byte {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"): self = .white
            case UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "/"),
                UInt8(ascii: ":"), UInt8(ascii: ","), UInt8(ascii: "|"):
                self = .delimiter
            case UInt8(ascii: "a")...UInt8(ascii: "z"): self = .lower
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): self = .upper
            case UInt8(ascii: "0")...UInt8(ascii: "9"): self = .digit
            case 0x80...: self = .letter
            default: self = .other
            }
        }

        var isWordCharacter: Bool {
            switch self {
            case .lower, .upper, .digit, .letter: true
            default: false
            }
        }
    }
}

/// A query split into tokens that must all match, in any order.
struct OdeFuzzyQuery: Sendable, Equatable {
    let text: String
    let tokens: [[UInt8]]
    let masks: [UInt64]

    init(_ text: String) {
        let folded = OdeFuzzyIndex.fold(text)
        self.text = folded.trimmingCharacters(in: .whitespacesAndNewlines)
        tokens = folded.split(whereSeparator: \.isWhitespace).map { Array($0.utf8) }.filter { !$0.isEmpty }
        masks = tokens.map { $0.reduce(0) { $0 | OdeFuzzyIndex.maskBit($1) } }
    }

    var isEmpty: Bool { tokens.isEmpty }

    /// Whether every entry matching `self` also matches `previous`: the new
    /// text extends the old one, so the old survivors can be searched alone.
    func narrows(_ previous: OdeFuzzyQuery) -> Bool {
        !previous.isEmpty && text.hasPrefix(previous.text) && tokens.count >= previous.tokens.count
    }
}

/// One entry a search found, with its score; a typo match carries the
/// number of edits it needed, and a weak one is spread over several words.
struct OdeFuzzyHit: Sendable, Equatable {
    let index: Int32
    let score: Int32
    var edits: Int8 = 0
    var isWeak = false
}

/// An entry's score for a query, and whether some token only matched it
/// spread over several words.
struct OdeFuzzyScore: Sendable, Equatable {
    let score: Int32
    let isWeak: Bool
}

/// Scratch rows reused across entries so scoring allocates nothing.
struct OdeFuzzyScratch {
    fileprivate var scores: [Int32] = []
    fileprivate var runs: [Int16] = []
    fileprivate var distance: [Int32] = []
    fileprivate var feasible: [Int] = []

    init() {}
}

extension OdeFuzzyIndex {
    // MARK: - Actions - Matching

    /// The score of entry `index` for `query`, or nil when some token is not
    /// a subsequence of it.
    func score(_ index: Int, for query: OdeFuzzyQuery, scratch: inout OdeFuzzyScratch) -> OdeFuzzyScore? {
        let mask = masks[index]
        for tokenMask in query.masks where tokenMask & ~mask != 0 { return nil }
        let start = Int(starts[index])
        let end = Int(starts[index + 1])
        let primaryEnd = Int(primaryEnds[index])
        var total: Int32 = 0
        var isWeak = false
        return bytes.withUnsafeBufferPointer { bytes in
            bonuses.withUnsafeBufferPointer { bonuses in
                for token in query.tokens {
                    var exactWord: Int?
                    if token.count > 1 {
                        let words = Self.wordMatch(token, in: bytes, bonuses: bonuses, from: start, to: end)
                        guard words.exact != nil || words.withinOneWord else {
                            // Spread over several words: weak, ranked last,
                            // so a nominal score saves the alignment.
                            guard Self.isSubsequence(token, in: bytes, from: start, to: end) else { return nil }
                            isWeak = true
                            total += Int32(token.count) * Self.weakScorePerCharacter
                            continue
                        }
                        exactWord = words.exact
                    }
                    guard
                        let (score, last) = Self.align(
                            token, in: bytes, bonuses: bonuses, from: start, to: end, scratch: &scratch)
                    else { return nil }
                    var weighted = last - start < primaryEnd ? score : score * 4 / 5
                    if let word = exactWord {
                        weighted += Self.bonusExactWord
                        if word == start || word == start + primaryEnd + 1 { weighted += Self.bonusLeadingWord }
                    }
                    total += weighted
                }
                return OdeFuzzyScore(score: total, isWeak: isWeak)
            }
        }
    }

    /// fzf's alignment of `token` within `start..<end`: the best score and
    /// the position its last character landed on.
    private static func align(
        _ token: [UInt8], in text: UnsafeBufferPointer<UInt8>, bonuses: UnsafeBufferPointer<Int8>,
        from start: Int, to end: Int, scratch: inout OdeFuzzyScratch
    ) -> (Int32, Int)? {
        let m = token.count
        guard let first = firstFeasible(token, in: text, from: start, to: end, scratch: &scratch) else { return nil }
        if m == 1 {
            return alignOneCharacter(token[0], in: text, bonuses: bonuses, from: first, to: end)
        }
        // Nothing after the last occurrence of the token's last character
        // can end a match.
        var lastEnd = end - 1
        while text[lastEnd] != token[m - 1] { lastEnd -= 1 }
        let width = lastEnd + 1 - first
        let cells = m * width
        if scratch.scores.count < cells {
            scratch.scores = [Int32](repeating: 0, count: cells)
            scratch.runs = [Int16](repeating: 0, count: cells)
        }
        var best: Int32 = 0
        var bestPosition = end - 1
        var found = false
        let feasibleColumns = scratch.feasible
        scratch.scores.withUnsafeMutableBufferPointer { scores in
            scratch.runs.withUnsafeMutableBufferPointer { runs in
                // Row 0.
                var inGap = false
                var previous: Int32 = 0
                for column in 0..<width {
                    let position = first + column
                    if text[position] == token[0] {
                        scores[column] = scoreMatch + Int32(bonuses[position]) * bonusFirstCharMultiplier
                        runs[column] = 1
                        inGap = false
                    } else {
                        scores[column] = max(previous + (inGap ? scoreGapExtension : scoreGapStart), 0)
                        runs[column] = 0
                        inGap = true
                    }
                    previous = scores[column]
                }
                // Rows 1 and on.
                for row in 1..<m {
                    let byte = token[row]
                    let rowStart = row * width
                    let above = (row - 1) * width
                    inGap = false
                    var left: Int32 = 0
                    // Before its first feasible column a row cannot match.
                    let firstColumn = feasibleColumns[row] - first
                    for column in 0..<firstColumn {
                        scores[rowStart + column] = 0
                        runs[rowStart + column] = 0
                    }
                    for column in firstColumn..<width {
                        let position = first + column
                        var s1: Int32 = 0
                        var run: Int16 = 0
                        let s2 = column == firstColumn ? 0 : left + (inGap ? scoreGapExtension : scoreGapStart)
                        if column > 0, text[position] == byte {
                            (s1, run) = diagonalMatch(
                                at: position, diagonal: scores[above + column - 1], run: runs[above + column - 1],
                                gap: s2, bonuses: bonuses)
                        }
                        runs[rowStart + column] = run
                        inGap = s1 < s2
                        let score = max(max(s1, s2), 0)
                        scores[rowStart + column] = score
                        left = score
                        if row == m - 1, run > 0, score > best {
                            best = score
                            bestPosition = position
                            found = true
                        }
                    }
                }
            }
        }
        // A subsequence whose alignment decayed through long gaps still
        // matches, with the lowest score.
        return found ? (best, bestPosition) : (1, lastEnd)
    }

    /// Greedy forward scan: `token` must be a subsequence of `start..<end`,
    /// and nothing before its first character's first occurrence can take
    /// part. Keeps each character's earliest position in `scratch.feasible`
    /// and answers the first one's, or nil when `token` is no subsequence.
    private static func firstFeasible(
        _ token: [UInt8], in text: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int,
        scratch: inout OdeFuzzyScratch
    ) -> Int? {
        var first = -1
        var cursor = start
        var feasible = scratch.feasible
        feasible.removeAll(keepingCapacity: true)
        defer { scratch.feasible = feasible }
        for (offset, byte) in token.enumerated() {
            while cursor < end, text[cursor] != byte { cursor += 1 }
            guard cursor < end else { return nil }
            if offset == 0 { first = cursor }
            feasible.append(cursor)
            cursor += 1
        }
        return first
    }

    /// A one-character token's alignment: its best-scored occurrence from
    /// `first` on, the earliest of equal ones.
    private static func alignOneCharacter(
        _ byte: UInt8, in text: UnsafeBufferPointer<UInt8>, bonuses: UnsafeBufferPointer<Int8>,
        from first: Int, to end: Int
    ) -> (Int32, Int) {
        var best: Int32 = -1
        var bestPosition = first
        for column in first..<end where text[column] == byte {
            let score = scoreMatch + Int32(bonuses[column]) * bonusFirstCharMultiplier
            if score > best {
                best = score
                bestPosition = column
            }
        }
        return (best, bestPosition)
    }

    /// The score and run of a token character matching at `position` after
    /// the cell above and to the left, which scored `diagonal` with `run`,
    /// where a gap from the left would score `gap`. A match that continues a
    /// run keeps the run's leading bonus unless it starts a stronger
    /// boundary; one that scores below the gap restarts its run.
    @inline(__always)
    private static func diagonalMatch(
        at position: Int, diagonal: Int32, run diagonalRun: Int16, gap: Int32, bonuses: UnsafeBufferPointer<Int8>
    ) -> (Int32, Int16) {
        guard diagonal > 0 || diagonalRun > 0 else { return (0, 0) }
        var score = diagonal + scoreMatch
        var bonus = Int32(bonuses[position])
        var run = diagonalRun + 1
        if run > 1 {
            let runStart = Int32(bonuses[position - Int(run) + 1])
            if bonus >= bonusBoundary && bonus > runStart {
                run = 1
            } else {
                bonus = max(bonus, max(bonusConsecutive, runStart))
            }
        }
        if score + bonus < gap {
            return (score + Int32(bonuses[position]), 0)
        }
        score += bonus
        return (score, run)
    }

    /// Where `token` first appears in `start..<end` as a whole word, and
    /// whether it is a subsequence of a single word, in one pass.
    private static func wordMatch(
        _ token: [UInt8], in text: UnsafeBufferPointer<UInt8>, bonuses: UnsafeBufferPointer<Int8>,
        from start: Int, to end: Int
    ) -> (exact: Int?, withinOneWord: Bool) {
        let m = token.count
        var withinOneWord = false
        var wordStart = start
        while wordStart < end {
            var wordEnd = wordStart + 1
            while wordEnd < end, isWordByte(text[wordEnd]), bonuses[wordEnd] < Int8(bonusCamel123) { wordEnd += 1 }
            let length = wordEnd - wordStart
            if length >= m {
                if length == m {
                    var index = 0
                    while index < m, text[wordStart + index] == token[index] { index += 1 }
                    if index == m { return (wordStart, true) }
                }
                if !withinOneWord {
                    var matched = 0
                    for position in wordStart..<wordEnd where text[position] == token[matched] {
                        matched += 1
                        if matched == m {
                            withinOneWord = true
                            break
                        }
                    }
                }
            }
            wordStart = wordEnd
            while wordStart < end, !isWordByte(text[wordStart]) { wordStart += 1 }
        }
        return (nil, withinOneWord)
    }

    private static func isSubsequence(
        _ token: [UInt8], in text: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int
    )
        -> Bool
    {
        var matched = 0
        for position in start..<end where text[position] == token[matched] {
            matched += 1
            if matched == token.count { return true }
        }
        return false
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || byte >= 0x80
    }

    // MARK: - Actions - Typos

    /// The fewest edits (insertion, deletion, substitution or a swap of
    /// neighbors) turning `token` into the start of some word of entry
    /// `index`, when every token gets there within its allowance: one edit
    /// from four characters, two from eight. Only words that start with the
    /// token's first letter, or swap it with the second, are tried.
    func typoEdits(_ index: Int, for query: OdeFuzzyQuery, scratch: inout OdeFuzzyScratch) -> Int? {
        let mask = masks[index]
        let start = Int(starts[index])
        let end = Int(starts[index + 1])
        var total = 0
        for (token, tokenMask) in zip(query.tokens, query.masks) {
            let allowance = token.count >= 8 ? 2 : token.count >= 4 ? 1 : 0
            guard (tokenMask & ~mask).nonzeroBitCount <= allowance else { return nil }
            var bestEdits = Int.max
            bytes.withUnsafeBufferPointer { text in
                bonuses.withUnsafeBufferPointer { bonuses in
                    var wordStart = start
                    while wordStart < end {
                        if wordStart == start || bonuses[wordStart] >= Int8(Self.bonusCamel123) {
                            var wordEnd = wordStart + 1
                            while wordEnd < end, Self.isWordByte(text[wordEnd]),
                                bonuses[wordEnd] < Int8(Self.bonusCamel123)
                            {
                                wordEnd += 1
                            }
                            // A typo almost always keeps the word's first
                            // letter, or swaps it with the second.
                            let opens =
                                text[wordStart] == token[0]
                                || (wordEnd - wordStart > 1 && text[wordStart + 1] == token[0])
                                || text[wordStart] == token[1]
                            if opens, wordEnd - wordStart + allowance >= token.count {
                                let edits = Self.prefixEdits(
                                    token, text, from: wordStart, to: wordEnd, limit: allowance, scratch: &scratch)
                                bestEdits = min(bestEdits, edits)
                            }
                            wordStart = wordEnd
                        } else {
                            wordStart += 1
                        }
                    }
                }
            }
            guard bestEdits <= allowance else { return nil }
            total += bestEdits
        }
        return total
    }

    /// Restricted Damerau-Levenshtein distance from `token` to the closest
    /// prefix of `text[start..<end]`, or `limit + 1` when it exceeds `limit`.
    private static func prefixEdits(
        _ token: [UInt8], _ text: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int, limit: Int,
        scratch: inout OdeFuzzyScratch
    ) -> Int {
        let m = token.count
        let n = min(end - start, m + limit)
        let columns = n + 1
        let cells = (m + 1) * columns
        if scratch.distance.count < cells { scratch.distance = [Int32](repeating: 0, count: cells) }
        var result = Int32(limit + 1)
        scratch.distance.withUnsafeMutableBufferPointer { d in
            for j in 0...n { d[j] = Int32(j) }
            for i in 1...m {
                d[i * columns] = Int32(i)
                var rowMinimum = Int32(i)
                for j in 1...n {
                    let cost: Int32 = token[i - 1] == text[start + j - 1] ? 0 : 1
                    var value = min(
                        d[(i - 1) * columns + j] + 1, d[i * columns + j - 1] + 1, d[(i - 1) * columns + j - 1] + cost)
                    if i > 1, j > 1, token[i - 1] == text[start + j - 2], token[i - 2] == text[start + j - 1] {
                        value = min(value, d[(i - 2) * columns + j - 2] + 1)
                    }
                    d[i * columns + j] = value
                    rowMinimum = min(rowMinimum, value)
                }
                if rowMinimum > limit { return }
            }
            // The closest prefix: any length of the word from m - limit on.
            for j in max(0, m - limit)...n { result = min(result, d[m * columns + j]) }
        }
        return Int(result)
    }
}

/// Fuzzy search over one index, as a person types.
///
/// While the query only grows, it searches just the entries the previous
/// query matched. When the exact pass finds fewer than `typoThreshold`
/// entries, it adds those within a small number of edits, ranked after every
/// exact match. Not thread-safe; give each one a single owner.
final class OdeFuzzySearcher {
    // MARK: - Static Variables

    static let typoThreshold = 8

    // MARK: - Variables

    let index: OdeFuzzyIndex
    let limit: Int
    private var previousQuery = OdeFuzzyQuery("")
    private var survivors: [Int32] = []
    private var scratch = OdeFuzzyScratch()

    // MARK: - Initializers

    init(index: OdeFuzzyIndex, limit: Int = 400) {
        self.index = index
        self.limit = limit
    }

    // MARK: - Actions - Searching

    /// The best entries for `text`, highest score first, ties in index
    /// order: matches within a word, then typo matches. Matches spread over
    /// several words only follow when those two found fewer than
    /// `typoThreshold`, since they are rarely what was meant. Empty for an
    /// empty query.
    func search(_ text: String) -> [OdeFuzzyHit] {
        let query = OdeFuzzyQuery(text)
        guard !query.isEmpty else {
            previousQuery = query
            survivors = []
            return []
        }
        let candidates: [Int32]? = query.narrows(previousQuery) ? survivors : nil
        var matched: [Int32] = []
        var strongHits: [OdeFuzzyHit] = []
        var weakHits: [OdeFuzzyHit] = []
        func consider(_ position: Int32) {
            guard let result = index.score(Int(position), for: query, scratch: &scratch) else { return }
            matched.append(position)
            if result.isWeak {
                weakHits.append(OdeFuzzyHit(index: position, score: result.score, isWeak: true))
            } else {
                strongHits.append(OdeFuzzyHit(index: position, score: result.score))
            }
        }
        if let candidates {
            for position in candidates { consider(position) }
        } else {
            for position in 0..<Int32(index.count) { consider(position) }
        }
        previousQuery = query
        survivors = matched
        let ranked = best(strongHits)
        let weak = best(weakHits)
        guard ranked.count < Self.typoThreshold else { return ranked }
        guard query.tokens.contains(where: { $0.count >= 4 }) else {
            return ranked + weak.prefix(max(0, limit - ranked.count))
        }
        // Typo pass, after every strong match; a weak match may still be a
        // near miss of a whole word.
        let exact = Set(ranked.map(\.index))
        var typos: [OdeFuzzyHit] = []
        for position in 0..<Int32(index.count) where !exact.contains(position) {
            guard let edits = index.typoEdits(Int(position), for: query, scratch: &scratch) else { continue }
            let length = query.tokens.reduce(0) { $0 + $1.count }
            typos.append(OdeFuzzyHit(index: position, score: Int32((length - edits) * 4), edits: Int8(edits)))
        }
        typos = best(typos)
        let strong = ranked + typos.prefix(max(0, limit - ranked.count))
        guard strong.count < Self.typoThreshold else { return strong }
        let typoIndices = Set(typos.map(\.index))
        let remaining = weak.filter { !typoIndices.contains($0.index) }
        return strong + remaining.prefix(max(0, limit - strong.count))
    }

    /// The first `limit` hits in ranking order. Hits arrive in index order
    /// and scores are small integers, so a counting sort by score keeps ties
    /// in index order without comparing hits.
    private func best(_ hits: [OdeFuzzyHit]) -> [OdeFuzzyHit] {
        guard hits.count > 1 else { return hits }
        var lowest = Int32.max
        var highest = Int32.min
        for hit in hits {
            lowest = min(lowest, hit.score)
            highest = max(highest, hit.score)
        }
        let range = Int(highest - lowest) + 1
        guard range <= 1 << 14 else { return Array(hits.sorted(by: Self.precedes).prefix(limit)) }
        var counts = [Int32](repeating: 0, count: range)
        for hit in hits { counts[Int(highest - hit.score)] += 1 }
        // Start offset of each score, highest first.
        var offset: Int32 = 0
        for bucket in 0..<range {
            let count = counts[bucket]
            counts[bucket] = offset
            offset += count
        }
        let kept = min(limit, hits.count)
        var ordered = [OdeFuzzyHit?](repeating: nil, count: kept)
        for hit in hits {
            let bucket = Int(highest - hit.score)
            let slot = Int(counts[bucket])
            counts[bucket] += 1
            if slot < kept { ordered[slot] = hit }
        }
        return ordered.compactMap { $0 }
    }

    private static func precedes(_ lhs: OdeFuzzyHit, _ rhs: OdeFuzzyHit) -> Bool {
        lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
    }
}
