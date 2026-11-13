import Foundation

/// Dictionary lookup is unavailable on mobile; it must not offer a definition
/// or try to open the Mac's Dictionary app.
enum BrowserDictionary {
    // MARK: - Actions - Reading

    static func definition(of term: String) async -> PaletteDefinition? { nil }

    @MainActor
    static func show(_ term: String) -> Bool { false }
}
