import Foundation

/// The name catalog is generated from a versioned export, never discovered via
/// private OS bundles. Artwork comes from public platform APIs.
enum BrowserSystemSymbolCatalog {
    /// Every catalog name the running system can draw, in catalog order.
    ///
    /// `Scripts/update-sf-symbol-catalog.py` keeps only the symbols the oldest
    /// supported system draws, so no name is asked for here: asking the system
    /// for a symbol loads its artwork, which the system then keeps cached for
    /// the life of the process, over 100 MB for the whole catalog.
    static func availableNames(bundle: Bundle = .main) -> [String] {
        guard let url = bundle.url(forResource: "SFSymbolNames", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && seen.insert($0).inserted }
    }
}
