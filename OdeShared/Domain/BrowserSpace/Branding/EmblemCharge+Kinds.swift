import Foundation

/// What an emblem bears: a figure from the heraldic set, any system symbol, an
/// emoji, a monogram of up to two letters, or nothing.
extension EmblemCharge {
    // MARK: - Static Variables

    /// A charge that draws nothing in place of the heraldic figure.
    static let none = EmblemCharge(kind: .none, symbol: nil, text: nil, style: nil)

    // MARK: - Initializers

    static func heraldic(_ symbol: EmblemSymbol) -> EmblemCharge {
        EmblemCharge(kind: .heraldic, symbol: symbol, text: nil, style: nil)
    }

    static func system(_ name: String) -> EmblemCharge {
        EmblemCharge(kind: .system, symbol: nil, text: name, style: nil)
    }

    static func emoji(_ emoji: String) -> EmblemCharge {
        EmblemCharge(kind: .emoji, symbol: nil, text: emoji, style: nil)
    }

    static func monogram(_ letters: String, _ style: EmblemMonogramStyle) -> EmblemCharge {
        EmblemCharge(kind: .monogram, symbol: nil, text: letters, style: style)
    }
}
