import Foundation

extension BrowserSettingsDestination {
    /// What a Settings search finds the destination by: its own names and
    /// terms, then each setting on its page by that setting's title and
    /// terms. Every word typed must be in one of them, so words scattered
    /// across unrelated settings do not list the page.
    private var searchHaystacks: [[LocalizedStringResource]] {
        [[title, navigationTitle, subtitle, searchTerms]]
            + BrowserSettingsSearchTarget.all.filter { $0.destination == self }.map(\.searchHaystack)
    }

    /// Whether `query` names the destination, or a setting on its page.
    func matchesSearchQuery(_ query: String, locale: Locale) -> Bool {
        searchHaystacks.contains { BrowserSettingsSearch.matches(query, in: $0, locale: locale) }
    }
}

extension BrowserSettingsDestination {
    /// Every settings page as the command palette offers it: by its name,
    /// with its title and the words a person might type to find it. Kept
    /// per locale, since each palette asks for them as it opens.
    @MainActor static var palettePages: [PaletteSettingsPage] {
        let locale = Locale.current
        if let cached = palettePagesByLocale, cached.locale == locale { return cached.pages }
        let pages = all.map {
            PaletteSettingsPage(
                name: $0.name, title: String(localized: $0.title),
                terms: [String(localized: $0.subtitle), String(localized: $0.searchTerms)].joined(separator: " "))
        }
        palettePagesByLocale = (locale, pages)
        return pages
    }

    @MainActor private static var palettePagesByLocale: (locale: Locale, pages: [PaletteSettingsPage])?
}
