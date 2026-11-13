import AppKit
import CoreServices
import Foundation

/// The Mac's own dictionary, read on the device: what it says for a word,
/// and the Dictionary app at that word. A Mac that never used its dictionary
/// has none until macOS downloads one, which the first lookup starts; until
/// then a lookup finds nothing and the palette says so only when asked
/// outright. Other platforms have no dictionary to read.
enum BrowserDictionary {
    // MARK: - Static Variables

    /// A word every dictionary holds, which tells a Mac with no dictionary
    /// yet from a word the dictionary lacks.
    private static let probe = "dictionary"

    // MARK: - Actions - Reading

    /// What the dictionary says for `term`; one whose text is nil when the
    /// Mac has no dictionary yet; or nil when it lacks the word.
    static func definition(of term: String) async -> PaletteDefinition? {
        await Task.detached(priority: .userInitiated) {
            if let text = text(for: term) { return PaletteDefinition(term: term, text: text) }
            return text(for: probe) == nil ? PaletteDefinition(term: term, text: nil) : nil
        }.value
    }

    /// Opens the Dictionary app at `term`, answering whether it could.
    @MainActor
    static func show(_ term: String) -> Bool {
        var components = URLComponents()
        components.scheme = "dict"
        components.host = term
        guard let url = components.url else { return false }
        return NSWorkspace.shared.open(url)
    }

    private static func text(for term: String) -> String? {
        let length = (term as NSString).length
        guard length > 0,
            let definition = DCSCopyTextDefinition(nil, term as CFString, CFRange(location: 0, length: length))
        else { return nil }
        let text = definition.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }
}
