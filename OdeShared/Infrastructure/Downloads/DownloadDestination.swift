import Foundation

enum BrowserDownloadDestination {
    static func availableURL(
        suggestedFilename: String,
        directory: URL,
        fileExists: (URL) -> Bool
    ) -> URL {
        let preferred = directory.appendingPathComponent(safeFilename(from: suggestedFilename), isDirectory: false)
        for candidate in candidates(for: preferred) where !fileExists(candidate) { return candidate }
        return preferred
    }

    /// The names a file may take at `url`, in the order they are tried: the
    /// name itself, then "name 1.ext", "name 2.ext" and on, without end.
    static func candidates(for url: URL) -> some Sequence<URL> {
        let directory = url.deletingLastPathComponent()
        let path = url.lastPathComponent as NSString
        let stem = path.deletingPathExtension
        let pathExtension = path.pathExtension
        return sequence(state: 0) { (suffix: inout Int) -> URL? in
            defer { suffix += 1 }
            guard suffix > 0 else { return url }
            let suffixedName =
                pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(pathExtension)"
            return directory.appendingPathComponent(suffixedName, isDirectory: false)
        }
    }

    /// The name a download suggested as `suggestedFilename` is saved and shown
    /// under, as the core names it: its last path component, composed,
    /// without control or direction-changing characters or path separators,
    /// trimmed of edge spaces and dots, and short enough for a file system.
    /// Only the last `DownloadRiskFacts.maximumSuggestedFilenameLength`
    /// characters are asked about, which hold any name a file system keeps.
    static func safeFilename(from suggestedFilename: String) -> String {
        let suggested = String(suggestedFilename.suffix(DownloadRiskFacts.maximumSuggestedFilenameLength))
        // The core refuses no name; a refusal would leave the generic one.
        return (try? OdeCore.answer(SanitizeDownloadFilename(suggested: suggested)).filename) ?? "download"
    }
}
