import Foundation

/// Proposes folders for a Space's open tabs, on request. The configured
/// provider names the groups; the code decides what it accepts from the
/// answer, and finds duplicate tabs by address on its own. Nothing changes
/// until the person applies the proposal.
@MainActor
struct BrowserTidyToday {
    // MARK: - Types

    /// An open tab as Tidy reads it: its name and the address it shows.
    struct Tab: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let address: URL?

        /// The address without its fragment, which names the same page;
        /// `nil` for a tab that shows no web address.
        var pageKey: String? {
            guard let address, let components = URLComponents(url: address, resolvingAgainstBaseURL: false),
                let scheme = components.scheme?.lowercased(), let host = address.host()?.lowercased()
            else { return nil }
            let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
            return "\(scheme)://\(host)\(components.percentEncodedPath)\(query)"
        }
    }

    /// A folder Tidy proposes, with a name the person may still change.
    struct Group: Identifiable, Equatable, Sendable {
        let id: UUID
        var name: String
        let tabs: [Tab]
    }

    /// What Tidy proposes: folders, the later copies of a page that is open
    /// more than once, and why the proposal is empty when it is.
    struct Proposal: Equatable, Sendable {
        static func empty(_ reason: String) -> Proposal {
            Proposal(groups: [], duplicates: [], reason: reason)
        }

        var groups: [Group]
        let duplicates: [Tab]
        let reason: String?

        var isEmpty: Bool { groups.isEmpty && duplicates.isEmpty }
    }

    enum Failure: LocalizedError {
        case unreadableReply

        var errorDescription: String? {
            switch self {
            case .unreadableReply:
                String(localized: "The model’s answer couldn’t be read as groups.")
            }
        }
    }

    private struct Reply: Decodable {
        struct Group: Decodable {
            let name: String
            let tabs: [Int]
        }

        let groups: [Group]
    }

    // MARK: - Static Variables

    static let instructions = """
        You group browser tabs. Reply with JSON only: {"groups":[{"name":"...","tabs":[numbers]}]}. \
        Make two to six groups of related tabs, each name one to three words. Put every tab in exactly one group.
        """
    static let tabLimit = 60
    static let groupLimit = 6
    static let nameWordLimit = 3
    static let nameCharacterLimit = 24
    /// Titles are cut so sixty lines fit the smallest provider's prompt.
    static let titleCharacterLimit = 70

    /// Names that file nothing: a catch-all or a duplicate list leaves its
    /// tabs where they are.
    private static let rejectedNameWords: Set<String> = [
        "other", "others", "misc", "miscellaneous", "uncategorized", "unsorted", "duplicate", "duplicates",
    ]

    // MARK: - Variables

    /// The Space's open tabs in sidebar order.
    let tabs: [Tab]

    // MARK: - Actions - Proposal

    /// Asks `provider`, the configured one unless another is given, to group
    /// the tabs. Every later copy of a page is a duplicate and is not sent;
    /// the first `tabLimit` remaining tabs are. When the model fails, the
    /// duplicates are still offered, with a sentence saying why no folders
    /// came.
    func propose(
        using provider: (any BrowserIntelligenceProvider)? = BrowserIntelligenceProviderResolver.configuredProvider()
    ) async -> Proposal {
        guard let provider else {
            return .empty(String(localized: "Turn on intelligence in Settings to tidy tabs."))
        }
        let duplicates = Self.duplicates(in: tabs)
        let duplicateIDs = Set(duplicates.map(\.id))
        let candidates = Array(tabs.filter { !duplicateIDs.contains($0.id) }.prefix(Self.tabLimit))
        guard candidates.count >= 2 else {
            guard !duplicates.isEmpty else {
                return .empty(String(localized: "There aren’t enough open tabs to group."))
            }
            return Proposal(groups: [], duplicates: duplicates, reason: nil)
        }
        let reply: String
        do {
            reply = try await provider.complete(instructions: Self.instructions, prompt: Self.prompt(for: candidates))
        } catch {
            return Proposal(groups: [], duplicates: duplicates, reason: await Self.reason(afterFailureOf: provider))
        }
        guard let groups = try? Self.groups(from: reply, of: candidates) else {
            return Proposal(groups: [], duplicates: duplicates, reason: Failure.unreadableReply.localizedDescription)
        }
        guard !groups.isEmpty || !duplicates.isEmpty else {
            return .empty(String(localized: "The model didn’t suggest any groups."))
        }
        return Proposal(groups: groups, duplicates: duplicates, reason: nil)
    }

    /// Why `provider` proposed nothing after its model failed: the
    /// provider's own summary while it cannot run, such as Apple Intelligence
    /// being off or its model still downloading, and otherwise that the model
    /// suggested no groups. Never the error a framework threw.
    private static func reason(afterFailureOf provider: any BrowserIntelligenceProvider) async -> String {
        let availability = await provider.availability()
        guard availability.isAvailable else { return availability.summary }
        return String(localized: "The model didn’t suggest any groups.")
    }

    /// One line per tab, numbered from 0: `<n>: <title> (<host>)`.
    static func prompt(for tabs: [Tab]) -> String {
        tabs.enumerated().map { index, tab in
            let title = tab.title.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return "\(index): \(title.prefix(titleCharacterLimit)) (\(tab.address?.host() ?? ""))"
        }
        .joined(separator: "\n")
    }

    /// The groups the reply proposes that hold up: each tab placed once, a
    /// group of at least two tabs under a short name that is not a catch-all,
    /// and no more than `groupLimit` of them. Tabs no group keeps stay where
    /// they are.
    static func groups(from reply: String, of tabs: [Tab]) throws -> [Group] {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
            let decoded = try? JSONDecoder().decode(Reply.self, from: Data(reply[start...end].utf8))
        else { throw Failure.unreadableReply }
        var placed = Set<Int>()
        var groups: [Group] = []
        for proposed in decoded.groups {
            guard groups.count < groupLimit else { break }
            guard let name = acceptedName(proposed.name) else { continue }
            var indices: [Int] = []
            for index in proposed.tabs where tabs.indices.contains(index) && !placed.contains(index) {
                if !indices.contains(index) { indices.append(index) }
            }
            guard indices.count >= 2 else { continue }
            placed.formUnion(indices)
            groups.append(Group(id: UUID(), name: name, tabs: indices.sorted().map { tabs[$0] }))
        }
        return groups
    }

    /// The name cut to `nameWordLimit` words and `nameCharacterLimit`
    /// characters, or `nil` when nothing is left or it names a catch-all.
    static func acceptedName(_ name: String) -> String? {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace)
            .prefix(nameWordLimit)
        let trimmed = String(words.joined(separator: " ").prefix(nameCharacterLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !lowered.contains(where: { rejectedNameWords.contains($0) }) else { return nil }
        return trimmed
    }

    /// Every tab whose page an earlier tab already shows, by scheme, host,
    /// path and query.
    static func duplicates(in tabs: [Tab]) -> [Tab] {
        var seen = Set<String>()
        return tabs.filter { tab in
            guard let key = tab.pageKey else { return false }
            return !seen.insert(key).inserted
        }
    }
}
