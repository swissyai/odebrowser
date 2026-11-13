import Foundation

/// The one glyph a Space's icon draws, read from the Space's `symbol`: an SF
/// Symbol by name, an emoji, or a single letter.
enum BrowserSpaceGlyph: Equatable, Hashable, Sendable {
    case symbol(String)
    case emoji(String)
    case letter(String)

    init(symbol: String) {
        if let emoji = BrowserIconSymbol.emoji(from: symbol) {
            self = .emoji(emoji)
        } else if let letter = BrowserIconSymbol.letter(from: symbol) {
            self = .letter(letter)
        } else {
            self = .symbol(symbol)
        }
    }
}

extension BrowserSpaceGlyph {
    var systemSymbol: String? {
        if case .symbol(let name) = self { name } else { nil }
    }

    var emoji: String? {
        if case .emoji(let emoji) = self { emoji } else { nil }
    }

    var letter: String? {
        if case .letter(let letter) = self { letter } else { nil }
    }
}
