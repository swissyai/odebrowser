import Foundation

/// What changed since the version of Ode that ran before this one, from the
/// release notes this build carries. Every launch records its build and the
/// release-note entries it carries; the first launch of a newer build lists
/// the public entries the one before it did not carry.
struct BrowserSoftwareUpdateWhatsNew: Equatable, Sendable {
    // MARK: - Static Variables

    static let lastBuildPreferenceKey = "ode.software-update.last-build"
    static let seenEntriesPreferenceKey = "ode.software-update.seen-release-notes"
    /// How many changes the first launch after an update lists when the build
    /// before it recorded no entries: the newest this build carries.
    static let newestCount = 5

    // MARK: - Variables

    let version: String
    let build: String
    let changes: [BrowserAboutReleaseNote]

    /// The changes in a line each.
    var highlights: [String] {
        changes.map(\.message)
    }

    /// The changes as release notes the update window shows.
    var releaseNotes: String {
        changes.map { "- \($0.message)" }.joined(separator: "\n")
    }

    // MARK: - Actions - Launch

    /// Records this launch in `preferences`, and answers what changed when a
    /// newer build than the last one runs. `ranBefore` says whether an
    /// earlier launch, of a build that recorded nothing, used these
    /// preferences; a first launch ever has nothing new to show.
    static func recordLaunch(
        preferences: UserDefaults, ranBefore: Bool,
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        catalog: BrowserAboutReleaseNotes = .bundled
    ) -> Self? {
        let previousBuild = preferences.string(forKey: lastBuildPreferenceKey)
        let seen = preferences.stringArray(forKey: seenEntriesPreferenceKey).map(Set.init)
        preferences.set(build, forKey: lastBuildPreferenceKey)
        preferences.set(catalog.entries.map(\.id).sorted(), forKey: seenEntriesPreferenceKey)
        let updated = previousBuild.map { build.compare($0, options: .numeric) == .orderedDescending } ?? ranBefore
        guard updated, !build.isEmpty else { return nil }
        let changes = seen.map { catalog.changes(notIn: $0) } ?? catalog.currentHighlights(limit: newestCount)
        guard !changes.isEmpty else { return nil }
        return Self(version: version, build: build, changes: changes)
    }
}
