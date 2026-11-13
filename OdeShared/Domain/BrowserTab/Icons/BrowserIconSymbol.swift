import Foundation

/// The storage boundary shared by every browser entity that can wear an emoji.
///
/// An emoji is stored in the same `symbol` slot as an SF Symbol, with a prefix
/// that makes the two vocabularies unambiguous. Normalization selects one
/// Swift `Character`, not one Unicode scalar, so flags, skin tones, keycaps,
/// and zero-width-joiner sequences survive as the complete grapheme a person
/// picked.
enum BrowserIconSymbol {
    static func symbol(forEmoji input: String) -> String {
        guard let emoji = normalizedEmoji(input) else { return input }
        return TabIconMode.emojiPrefix + emoji
    }

    static func emoji(from symbol: String) -> String? {
        guard symbol.hasPrefix(TabIconMode.emojiPrefix) else { return nil }
        return normalizedEmoji(String(symbol.dropFirst(TabIconMode.emojiPrefix.count)))
    }

    /// The prefix a Space's letter is stored under in the `symbol` slot, as an
    /// emoji is stored under its own. Stored data: never renamed.
    static let letterPrefix = "ode.letter:"

    /// `input`'s first letter or digit, uppercased, as a Space's symbol, or
    /// nil when it has none.
    static func symbol(forLetter input: String) -> String? {
        normalizedLetter(input).map { letterPrefix + $0 }
    }

    static func letter(from symbol: String) -> String? {
        guard symbol.hasPrefix(letterPrefix) else { return nil }
        return normalizedLetter(String(symbol.dropFirst(letterPrefix.count)))
    }

    /// The first letter or digit of `input`, uppercased: one `Character`, so
    /// an accented letter keeps its accent.
    static func normalizedLetter(_ input: String) -> String? {
        guard let character = input.trimmingCharacters(in: .whitespacesAndNewlines).first,
            character.isLetter || character.isNumber
        else { return nil }
        // A letter whose capital is two letters, such as ß, stays as typed.
        let capital = String(character).uppercased()
        return capital.count == 1 ? capital : String(character)
    }

    static func normalizedEmoji(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = trimmed.first else { return nil }
        let candidate = String(character)
        let scalars = candidate.unicodeScalars
        let isEmoji = scalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || scalar.value == 0xFE0F
                || scalar.value == 0x20E3
        }
        return isEmoji ? candidate : nil
    }
}
