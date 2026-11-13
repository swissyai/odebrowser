import Foundation

@MainActor
struct LiveBrowserOnboardingImportCommitter:
    BrowserOnboardingImportCommitting
{
    // MARK: - Types

    /// The cookies of the Arc profile a reviewed Space was read from, and
    /// the engine profile the Space comes in with.
    private struct SignInCarry: Sendable {
        let source: URL
        let profileID: UUID
    }

    // MARK: - Variables

    private let safeStorage: any BrowserSafeStorageSecretProviding
    private let profileRoot: @Sendable () -> URL?
    private let targetKey: @Sendable () throws -> Data

    var supportsSignIns: Bool { profileRoot() != nil }

    // MARK: - Initializers

    init(
        safeStorage: any BrowserSafeStorageSecretProviding =
            LaunchScopedBrowserSafeStorage(),
        profileRoot: @escaping @Sendable () -> URL? = { LiveBrowserOnboardingImportCommitter.engineProfileRoot() },
        targetKey: @escaping @Sendable () throws -> Data = { try ChromiumSafeStorageKey.ode() }
    ) {
        self.safeStorage = safeStorage
        self.profileRoot = profileRoot
        self.targetKey = targetKey
    }

    // MARK: - Actions - Importing

    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport {
        try await prepare(review: review, payload: payload, bringsSignIns: true)
    }

    /// Reads the source browser's Keychain secret once, when its passwords
    /// or its sign-ins come over, so macOS asks once at most; neither
    /// coming over asks nothing.
    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?,
        bringsSignIns: Bool
    ) async throws -> BrowserOnboardingPreparedImport {
        let directoryAccess = BrowserImportAccessStore.resolve(for: review.source)
        defer { directoryAccess?.stopAccessing() }

        let bringsPasswords = payload != nil && review.includedPasswordCount > 0
        let carriesSignIns =
            supportsSignIns && bringsSignIns
            && Self.signInCarries(for: review).contains {
                FileManager.default.fileExists(atPath: $0.source.path)
            }
        guard bringsPasswords || carriesSignIns else {
            return BrowserOnboardingPreparedImport(passwords: [], bringsSignIns: bringsSignIns && supportsSignIns)
        }
        let safeStorage = safeStorage
        let source = review.source
        let secret = try await Task.detached(priority: .userInitiated) {
            try safeStorage.secret(for: source)
        }.value
        try Task.checkCancellation()
        var passwords: [BrowserImportedPassword] = []
        if bringsPasswords, let payload {
            passwords = try await BrowserPasswordImportReader.read(
                from: payload.passwordStores, application: review.source, secret: secret)
        }
        try Task.checkCancellation()
        return BrowserOnboardingPreparedImport(
            passwords: passwords, safeStorageSecret: secret, bringsSignIns: bringsSignIns && supportsSignIns)
    }

    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserOnboardingImportResult {
        let carry =
            preparedImport.bringsSignIns
            ? await carrySignIns(for: review, secret: preparedImport.safeStorageSecret)
            : (created: [URL](), result: BrowserOnboardingSignInResult())
        do {
            try browser.importReviewedSpaces(images: review.tabImages(from: preparedImport.siteIcons))
        } catch {
            await Task.detached(priority: .userInitiated) { Self.remove(carry.created) }.value
            throw error
        }
        let passwords = await BrowserPasswordImportCommitter.commit(preparedImport.passwords, browser: browser)
        return BrowserOnboardingImportResult(
            passwords: BrowserPasswordImportResult(
                importedCount: passwords.importedCount,
                skippedCount: max(passwords.skippedCount, review.includedPasswordCount - passwords.importedCount),
                unsavedCount: passwords.unsavedCount),
            signIns: carry.result)
    }

    // MARK: - Actions - Sign-ins

    /// For an Arc import, carries the cookies of the Arc profile each Space
    /// that comes in new was read from into that Space's own engine profile,
    /// before the engine can open it. Answers the engine profile folders the
    /// carry-over made, which a failed import removes.
    private func carrySignIns(
        for review: SetupImportReview, secret: String?
    ) async -> (created: [URL], result: BrowserOnboardingSignInResult) {
        guard review.source == .arc else { return ([], BrowserOnboardingSignInResult()) }
        let carries = Self.signInCarries(for: review)
        let merged = review.spaces.count { $0.included && $0.destinationID != nil }
        let withoutProfile = review.spaces.count {
            $0.included && $0.destinationID == nil && $0.sourceProfilePath == nil
        }
        let directoryAccess = BrowserImportAccessStore.resolve(for: review.source)
        defer { directoryAccess?.stopAccessing() }
        let profileRoot = profileRoot
        let targetKey = targetKey
        var carried = await Task.detached(priority: .userInitiated) {
            Self.carry(carries, secret: secret, root: profileRoot(), targetKey: targetKey)
        }.value
        carried.result.merged = merged
        carried.result.missing += withoutProfile
        return carried
    }

    /// The Arc profiles whose sign-ins come over: one for each included
    /// Space that comes in new.
    nonisolated private static func signInCarries(for review: SetupImportReview) -> [SignInCarry] {
        guard review.source == .arc else { return [] }
        return review.spaces.compactMap { space -> SignInCarry? in
            guard space.included, space.destinationID == nil, let path = space.sourceProfilePath else {
                return nil
            }
            return SignInCarry(
                source: URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("Cookies"),
                profileID: space.source.profileID
            )
        }
    }

    /// Carries each of `carries` whose Arc profile keeps cookies, skipping a
    /// Space whose target exists or whose carry-over fails, with the key the
    /// Keychain `secret` the import read once makes.
    nonisolated private static func carry(
        _ carries: [SignInCarry], secret: String?, root: URL?, targetKey: () throws -> Data
    ) -> (created: [URL], result: BrowserOnboardingSignInResult) {
        let fileManager = FileManager.default
        var result = BrowserOnboardingSignInResult()
        let pending = carries.filter { fileManager.fileExists(atPath: $0.source.path) }
        result.missing = carries.count - pending.count
        guard !pending.isEmpty else { return ([], result) }
        guard let root, let secret else {
            result.unavailable = pending.count
            return ([], result)
        }
        let sourceKey: Data
        let destinationKey: Data
        do {
            sourceKey = try ChromiumPasswordCrypto.key(safeStorageSecret: secret)
            destinationKey = try targetKey()
        } catch {
            result.unavailable = pending.count
            return ([], result)
        }
        var created: [URL] = []
        for carry in pending {
            let folder = root.appendingPathComponent("Crest-\(carry.profileID.uuidString)", isDirectory: true)
            let target = folder.appendingPathComponent("Cookies")
            let existed = fileManager.fileExists(atPath: folder.path)
            guard !fileManager.fileExists(atPath: target.path) else {
                result.existing += 1
                continue
            }
            do {
                let counts = try ChromiumCookieCarryOver.carry(
                    from: carry.source, to: target, sourceKey: sourceKey, targetKey: destinationKey)
                result.cookies += counts.carried
                result.expired += counts.expired
                result.dropped += counts.dropped
                created.append(existed ? target : folder)
            } catch {
                result.failed += 1
                if !existed { try? fileManager.removeItem(at: folder) }
            }
        }
        return (created, result)
    }

    /// Where this copy's Chromium keeps its Space profiles: the folder a
    /// launch names with `--user-data-dir`, else the released app's own. A
    /// development build that names none has no engine profiles, and never
    /// reads the released app's engine key or writes into its folder.
    nonisolated private static func engineProfileRoot(
        arguments: [String] = CommandLine.arguments, isRelease: Bool = ProductIdentity.isRelease
    ) -> URL? {
        #if ODE_CHROMIUM_HOST
            let switchPrefix = "--user-data-dir="
            if let named = arguments.last(where: { $0.hasPrefix(switchPrefix) })?.dropFirst(switchPrefix.count),
                named.hasPrefix("/")
            {
                return URL(fileURLWithPath: String(named), isDirectory: true)
            }
            guard isRelease else { return nil }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Crest/Chromium", isDirectory: true)
        #else
            return nil
        #endif
    }

    /// Removes only the cookie files or profile folders this carry created.
    nonisolated private static func remove(_ folders: [URL]) {
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
