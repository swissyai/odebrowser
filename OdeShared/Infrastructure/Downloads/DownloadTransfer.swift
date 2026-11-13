import Foundation

/// A download's file while it downloads and when it lands: it is written in
/// Ode's own staging folder under a name only its download uses, then moved,
/// quarantined, to the place the download settled. A move never overwrites a
/// file, and a move that fails leaves the staged file where it is.
enum BrowserDownloadTransfer {
    // MARK: - Actions - Staging

    /// Ode's own folder for files still downloading, created when absent.
    static func stagingDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
        .appendingPathComponent("Download Staging", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func stagingURL(
        itemID: UUID,
        suggestedFilename: String,
        directory: URL
    ) -> URL {
        let safeFilename = BrowserDownloadDestination.safeFilename(
            from: suggestedFilename
        )
        return directory.appendingPathComponent(
            "\(itemID.uuidString)-\(safeFilename)"
        )
    }

    // MARK: - Actions - Finishing

    /// Moves the staged file to `destinationURL`, which must be free, and
    /// quarantines it there. A file that cannot be quarantined goes back to
    /// staging, or away when it cannot, so no unquarantined download is left
    /// where the person looks.
    static func finish(
        from stagingURL: URL,
        to destinationURL: URL,
        quarantine: BrowserDownloadQuarantine? = nil,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        guard let quarantine else { return }

        do {
            try BrowserPlatformDownloadQuarantine.apply(
                quarantine,
                to: destinationURL
            )
        } catch {
            if (try? fileManager.moveItem(at: destinationURL, to: stagingURL)) == nil {
                try? fileManager.removeItem(at: destinationURL)
            }
            throw error
        }
    }

    /// Moves the staged file to `destinationURL` or, when a file has taken
    /// that name since it was chosen, such as a download of the same name
    /// that landed first, to the first free numbered name beside it, and
    /// answers where the file went. Whether a name is free is decided by the
    /// move itself, which never overwrites.
    static func finish(
        from stagingURL: URL,
        toFreeNameFor destinationURL: URL,
        quarantine: BrowserDownloadQuarantine? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        for candidate in BrowserDownloadDestination.candidates(for: destinationURL) {
            do {
                try finish(from: stagingURL, to: candidate, quarantine: quarantine, fileManager: fileManager)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        return destinationURL
    }
}
