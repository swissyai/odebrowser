import Foundation

/// The Mac shell reveals a finished export with the same Finder action as a
/// finished download.
@MainActor
enum BrowserPlatformAutomaticExport {
    // MARK: - Static Variables

    static let reveal: ((URL) -> Void)? = { BrowserWorkspaceFileOpener().revealFile($0) }
}
