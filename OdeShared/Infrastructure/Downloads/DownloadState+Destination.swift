import Foundation

extension DownloadState {
    /// The file the download writes, once a destination is known.
    var destinationURL: URL? {
        destination.flatMap(URL.init(string:))
    }

    /// The finished file, while it is still where the download saved it.
    func savedFileURL(
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        guard phase.isComplete, let url = destinationURL, url.isFileURL, fileExists(url) else { return nil }
        return url
    }

    /// A finished file that has since been moved or deleted, which the row
    /// can no longer open, show or hand over.
    func isSavedFileMissing(
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        phase.isComplete && destinationURL?.isFileURL == true && savedFileURL(fileExists: fileExists) == nil
    }
}
