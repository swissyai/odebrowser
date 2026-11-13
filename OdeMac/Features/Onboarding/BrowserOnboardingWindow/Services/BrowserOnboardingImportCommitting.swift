@MainActor
protocol BrowserOnboardingImportCommitting {
    /// Whether this adapter has a destination Chromium profile of its own.
    var supportsSignIns: Bool { get }

    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport

    /// Prepares the import, reading the source browser's Keychain secret
    /// at most once, and only when its passwords or its sign-ins come over.
    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?,
        bringsSignIns: Bool
    ) async throws -> BrowserOnboardingPreparedImport

    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserOnboardingImportResult
}

extension BrowserOnboardingImportCommitting {
    var supportsSignIns: Bool { false }

    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?,
        bringsSignIns: Bool
    ) async throws -> BrowserOnboardingPreparedImport {
        var prepared = try await prepare(review: review, payload: payload)
        prepared.bringsSignIns = bringsSignIns
        return prepared
    }
}
