import Foundation

struct BrowserSidebarWidgetKindID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let nowPlaying = Self(rawValue: "crest.now-playing")
    static let softwareUpdate = Self(rawValue: "crest.software-update")
}

struct BrowserSidebarWidgetID: Hashable, Identifiable, Sendable {
    let kindID: BrowserSidebarWidgetKindID
    let instanceID: String

    var id: String { "\(kindID.rawValue):\(instanceID)" }
}

struct BrowserSidebarWidgetPlatform: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let macOS = Self(rawValue: 1 << 0)
    static let mobile = Self(rawValue: 1 << 1)
    static let all: Self = [.macOS, .mobile]

    #if os(macOS)
        static let current = Self.macOS
    #else
        static let current = Self.mobile
    #endif
}

struct BrowserSidebarWidgetCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// The shell has a sidebar that remains beside web content.
    static let persistentSidebar = Self(rawValue: 1 << 0)
    /// Standard page Media Session state can be observed and controlled.
    static let mediaSessions = Self(rawValue: 1 << 1)
    /// This build is distributed directly and owns a Sparkle updater.
    static let directSoftwareUpdates = Self(rawValue: 1 << 2)
}

struct BrowserSidebarWidgetRegistration: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetKindID
    let settingsTitle: String
    let order: Int
    let platforms: BrowserSidebarWidgetPlatform
    let requiredCapabilities: BrowserSidebarWidgetCapabilities
    let instanceLimit: BrowserSidebarWidgetInstanceLimit
    let visibility: BrowserSidebarWidgetVisibility
    let backgroundActivityID: String?
}

extension BrowserSidebarWidgetRegistration {
    static let nowPlaying = Self(
        id: .nowPlaying,
        settingsTitle: String(localized: "Now Playing"),
        order: 200,
        platforms: .all,
        requiredCapabilities: [.mediaSessions],
        instanceLimit: .multiple,
        visibility: .userControllable,
        backgroundActivityID: "crest.media-session-observation"
    )

    static let softwareUpdate = Self(
        id: .softwareUpdate,
        settingsTitle: String(localized: "Software Update"),
        order: 100,
        platforms: .macOS,
        requiredCapabilities: [.directSoftwareUpdates],
        instanceLimit: .single,
        visibility: .mandatory,
        backgroundActivityID: "crest.software-update-observation"
    )
}

/// Who authored a widget. Sources still tag what they publish, but the deck is a
/// single global layer: visibility never consults the scope, so a tab playing
/// media in one profile stays on the card stack in every Space of every profile.
enum BrowserSidebarWidgetScope: Equatable, Sendable {
    case application
    case profile(UUID)
}

enum BrowserMediaSessionPlaybackState: String, Encodable, Equatable, Sendable {
    case none
    case paused
    case playing
}

struct BrowserMediaSessionID: Hashable, Identifiable, Sendable {
    let tabID: UUID
    let documentIdentifier: String

    var id: String {
        "\(tabID.uuidString.lowercased()):\(documentIdentifier)"
    }
}

struct BrowserMediaSessionSnapshot: Equatable, Identifiable, Sendable {
    let id: BrowserMediaSessionID
    let owner: BrowserTabRuntimeAssignment
    /// The owning tab's Ode-visible name, including a reader-supplied custom
    /// title. This is intentionally independent of page playback metadata.
    let ownerTitle: String?
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let playbackState: BrowserMediaSessionPlaybackState
    let isAudible: Bool
    /// Every media element the page has surfaced is muted. Distinct from
    /// `isAudible`, which also goes false for paused or zero-volume playback.
    let isMuted: Bool
    let availableActions: Set<MediaSessionAction>
    let orderingOrdinal: UInt64
    /// Where playback stands, when the page says; nil hides the progress.
    var position: BrowserMediaSessionPosition? = nil

    /// The tab's name, or, with none, what the session calls itself.
    var ownerDisplayTitle: String {
        ownerTitle ?? String(localized: "Media", comment: "A playing tab's name when the tab has none.")
    }

    /// The media's own title, else the tab's name: one fallback, never two
    /// lines saying the same thing.
    var mediaDisplayTitle: String { title ?? ownerDisplayTitle }

    /// System Now Playing still needs a single primary title. Prefer the
    /// standards-provided media title, with the stable tab title as its fallback.
    var displayTitle: String { title ?? ownerDisplayTitle }

    /// The line under the title: the artist and album; else where it plays,
    /// the tab's name without the title it repeats ("Radio" from "Evening
    /// Set - Radio"); else nothing, never the title twice.
    var sourceLine: String? {
        if let secondaryMetadata { return secondaryMetadata }
        guard let title, let ownerTitle, ownerTitle != title else { return nil }
        guard let range = ownerTitle.range(of: title) else { return ownerTitle }
        let rest = ownerTitle.replacingCharacters(in: range, with: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—|·•:")))
        return rest.isEmpty ? nil : rest
    }

    var secondaryMetadata: String? {
        [artist, album]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

struct BrowserSoftwareUpdateWidgetSnapshot: Equatable, Sendable {
    let phase: BrowserSoftwareUpdatePhase
    let title: String
    let version: String?
    let build: String?
    let releaseNotes: String?
    let informationURL: URL?
    let message: String?
    let progress: Double?
    let isInformationOnly: Bool
    let allowsInstallation: Bool
    let allowsSkipping: Bool
    let allowsCancellation: Bool
    let allowsInstallAndRelaunch: Bool
    let allowsInstallationRetry: Bool
    let isFixture: Bool
    /// The release fixes security problems only, so it can wait for a restart
    /// that suits the person.
    var isSecurityOnly = false
    /// Sparkle downloaded and prepared the update on its own; a restart, or
    /// the next quit, installs it.
    var isAutomaticUpdate = false
    /// What changed, in a few lines, on the card shown after Ode was updated.
    var highlights: [String] = []
}

struct BrowserSidebarWidgetInstance: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetID
    let scope: BrowserSidebarWidgetScope
    let orderingOrdinal: UInt64
    let presentation: BrowserSidebarWidgetPresentation
    let availableActions: Set<BrowserSidebarWidgetAction>
}
