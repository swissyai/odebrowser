import Foundation

struct BrowserAboutBuildInformation: Equatable, Sendable {
    // MARK: - Static Variables

    static let current = BrowserAboutBuildInformation(bundle: .main)

    // MARK: - Variables

    let version: String
    let build: String
    let bundleIdentifier: String

    /// Release publication must provide this immutable tag for the packaged version.
    var sourceCodeURL: URL? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
            components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } })
        else { return nil }
        return URL(string: "https://github.com/swissyai/odebrowser/tree/v\(version)")
    }

    // MARK: - Initializers

    init(bundle: Bundle) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleIdentifier: bundle.bundleIdentifier
        )
    }

    init(
        infoDictionary: [String: Any],
        bundleIdentifier: String?
    ) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        build = infoDictionary["CFBundleVersion"] as? String ?? "—"
        self.bundleIdentifier =
            bundleIdentifier ?? ProductIdentity.bundleIdentifier
    }
}

enum BrowserAboutLinks {
    // MARK: - Static Variables

    static let webKitLicense = URL(string: "https://webkit.org/licensing-webkit/")!
}

enum BrowserAboutReleaseNoteCategory: String, Decodable, Sendable {
    case new
    case improved
    case fixed
    case `internal`
}

struct BrowserAboutReleaseNote: Equatable, Identifiable, Sendable {
    let id: String
    let category: BrowserAboutReleaseNoteCategory
    let message: String
}

struct BrowserAboutReleaseNotes: Sendable {
    private struct Document: Decodable {
        let entries: [String: Entry]
    }

    private struct Entry: Decodable {
        let category: BrowserAboutReleaseNoteCategory
        let message: String
    }

    private(set) var entries: [BrowserAboutReleaseNote]

    static let bundled = loadBundled()

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        entries = document.entries.map { id, entry in
            BrowserAboutReleaseNote(
                id: id,
                category: entry.category,
                message: entry.message
            )
        }
    }

    init(entries: [BrowserAboutReleaseNote]) {
        self.entries = entries
    }

    /// The public changes whose entries are not in `seen`, newest first.
    func changes(notIn seen: Set<String>) -> [BrowserAboutReleaseNote] {
        entries.filter { $0.category != .internal && !seen.contains($0.id) }.sorted { $0.id > $1.id }
    }

    func currentHighlights(limit: Int = 12) -> [BrowserAboutReleaseNote] {
        guard limit > 0 else { return [] }
        return Array(
            entries
                .filter { $0.category != .internal }
                .sorted { $0.id > $1.id }
                .prefix(limit)
        )
    }

    private static func loadBundled() -> BrowserAboutReleaseNotes {
        guard
            let url = Bundle.main.url(
                forResource: "ReleaseNotes",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let releaseNotes = try? BrowserAboutReleaseNotes(data: data)
        else {
            return BrowserAboutReleaseNotes(entries: [])
        }
        return releaseNotes
    }
}
