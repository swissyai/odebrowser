import Foundation

/// Reads an installed browser's data for review: the core reads its profiles'
/// bookmarks, sessions and installed extensions away from the main thread, the
/// password stores are counted where the browser keeps passwords Ode imports,
/// and the icons it kept for the pages its tabs show are read beside them.
struct LiveBrowserOnboardingImportReader: BrowserOnboardingImportReading {
    // MARK: - Static Variables

    /// The largest icon file a review shows.
    private static let maximumIconBytes = 1_024 * 1_024

    // MARK: - Variables

    let core: OdeCore

    // MARK: - Actions - Reading

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        // Passwords never hold the rest back: a store the browser keeps
        // locked, or one Ode cannot read, leaves the review without them and
        // says why.
        var passwordCandidates: [BrowserPasswordImportCandidate] = []
        var passwordFailure: BrowserPasswordImportError?
        if payload.application.suppliesPasswords {
            do {
                passwordCandidates = try await BrowserPasswordImportReader.candidates(
                    from: payload.passwordStores,
                    application: payload.application
                )
            } catch let failure as BrowserPasswordImportError {
                passwordFailure = failure
            }
        }
        try Task.checkCancellation()

        let core = self.core
        let readID = try core.query(PrepareImportRead())
        let discard: @Sendable () -> Void = { _ = try? core.query(DiscardImportRead(readID: readID)) }
        let query = ReadImport(source: payload.application, profiles: payload.profiles, readID: readID)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let (imported, icons, siteIcons) = try await Task.detached(priority: .userInitiated) {
                    let imported = try core.query(query)
                    // Arc keeps a Space's profile beside the first one; each Space's
                    // own folder comes first.
                    var folders: [String] = []
                    for folder in (imported.profiles ?? []).map(\.profilePath)
                        + payload.profiles.compactMap(\.profilePath)
                    where !folders.contains(folder) {
                        folders.append(folder)
                    }
                    return (
                        imported, Self.icons(of: imported.extensions),
                        BrowserImportedSiteIcons.read(for: imported.spaces, in: folders)
                    )
                }.value
                try Task.checkCancellation()
                return BrowserOnboardingImportReadOutput(
                    payload: payload,
                    imported: imported.spaces,
                    passwordCandidates: passwordCandidates,
                    passwordFailure: passwordFailure,
                    extensions: imported.extensions,
                    extensionIcons: icons,
                    siteIcons: siteIcons,
                    leftOut: imported.leftOut,
                    profiles: imported.profiles ?? [],
                    discard: discard
                )
            } catch {
                discard()
                throw error
            }
        } onCancel: {
            discard()
        }
    }

    // MARK: - Actions - Icons

    /// The icons `offers` name, read while the browser's folder is open to
    /// Ode. An icon that is missing or too large is left out.
    private static func icons(of offers: [ImportSpaceExtensions]) -> [String: Data] {
        var icons: [String: Data] = [:]
        for item in offers.flatMap(\.extensions) where icons[item.extensionID] == nil {
            guard let path = item.iconPath,
                let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                data.count <= maximumIconBytes
            else { continue }
            icons[item.extensionID] = data
        }
        return icons
    }
}
