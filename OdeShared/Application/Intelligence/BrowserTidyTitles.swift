import Foundation

/// A short title for a tab, from the provider a person chose in Settings. Nil
/// whenever intelligence is off, the model cannot help, or its answer is not a
/// short title, so a tab keeps the title it has.
@MainActor
enum BrowserTidyTitles {
    // MARK: - Static Variables

    static let instructions =
        "You shorten browser tab titles. Reply with only the new title, one to four words. Keep what the page is about; drop site names, notification counts, separators and filler. Use the site name only when the title says nothing else. No quotes, no trailing punctuation."
    static let maximumWordCount = 5
    static let maximumCharacterCount = 32
    /// A notification count a page puts in its title, such as (9+) or (159).
    private static let countPattern = #"\(\d+\+?\)"#
    private static let separators = CharacterSet(charactersIn: "|-–—·•:/\\»«~*")
        .union(.whitespacesAndNewlines)
    private static let quotes = CharacterSet(charactersIn: "\"'`“”‘’„«»「」『』")
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?…。，、；：！？")

    // MARK: - Actions - Titles

    /// A tidy title for the page a web tab shows. Native views, such as
    /// downloads, and pages without a web host, such as files, get none.
    static func title(for tab: TabStateModel) async -> String? {
        guard tab.isWebPage, let address = tab.address,
            let scheme = address.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = address.host(), !host.isEmpty
        else { return nil }
        return await title(for: tab.title, host: host)
    }

    /// A tidy title for a page titled `title` on `host` from `provider`, the
    /// configured one unless another is given, or nil when the provider is
    /// off, fails, or answers with something that is not a short new title.
    /// A failure interrupts no one: the tab keeps its title, and the
    /// diagnostic log notes the provider's own summary of why.
    static func title(
        for title: String, host: String,
        using provider: (any BrowserIntelligenceProvider)? = BrowserIntelligenceProviderResolver.configuredProvider()
    ) async -> String? {
        guard let provider else { return nil }
        let input = cleaned(title)
        guard !input.isEmpty else { return nil }
        if let onDevice = provider as? OnDeviceIntelligenceProvider, !onDevice.readsTitle(input) { return nil }
        let reply: String
        do {
            reply = try await provider.complete(instructions: instructions, prompt: "Title: \(input)\nSite: \(host)")
        } catch {
            let summary = await provider.availability().summary
            DiagnosticLog.intelligence.notice("Tidy Title kept a tab's title after \(type(of: error)): \(summary)")
            return nil
        }
        let answer = cleanedReply(reply)
        let wordCount = answer.split(whereSeparator: \.isWhitespace).count
        guard (1...maximumWordCount).contains(wordCount), answer.count <= maximumCharacterCount, answer != title
        else { return nil }
        return answer
    }

    // MARK: - Actions - Cleaning

    /// `title` without notification counts or the separators left at its ends.
    private static func cleaned(_ title: String) -> String {
        title.replacingOccurrences(of: countPattern, with: " ", options: .regularExpression)
            .trimmingCharacters(in: separators)
    }

    /// The model's answer without notification counts, the quotes around it
    /// or trailing punctuation. An apostrophe inside the title stays.
    private static func cleanedReply(_ reply: String) -> String {
        let unquoted = quotes.union(.whitespacesAndNewlines)
        var answer = reply.replacingOccurrences(of: countPattern, with: " ", options: .regularExpression)
            .trimmingCharacters(in: unquoted)
        while let last = answer.unicodeScalars.last, trailingPunctuation.contains(last) {
            answer.unicodeScalars.removeLast()
            answer = answer.trimmingCharacters(in: unquoted)
        }
        return answer
    }

}
