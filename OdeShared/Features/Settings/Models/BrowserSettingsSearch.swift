import Foundation

/// How a Settings search matches a page, a setting on it or a Space's tab:
/// every word typed appears somewhere in the words it is found by, ignoring
/// case and accents, in any order.
enum BrowserSettingsSearch {
    /// Whether every word of `query` is in `haystack`, each resource read in
    /// `locale`. A query with no words matches nothing.
    static func matches(_ query: String, in haystack: [LocalizedStringResource], locale: Locale) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }
        let text = haystack.map { resource in
            var localized = resource
            localized.locale = locale
            return String(localized: localized)
        }.joined(separator: " ")
        return words.allSatisfy { word in
            text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
        }
    }
}
