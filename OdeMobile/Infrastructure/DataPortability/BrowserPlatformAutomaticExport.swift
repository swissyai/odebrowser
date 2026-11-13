import Foundation

/// The mobile shell has no Finder action to offer for an automatic export.
@MainActor
enum BrowserPlatformAutomaticExport {
    // MARK: - Static Variables

    static let reveal: ((URL) -> Void)? = nil
}
