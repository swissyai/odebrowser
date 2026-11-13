import Foundation

struct BrowserOnboardingPreparedImport {
    let passwords: [BrowserImportedPassword]
    /// The source browser's Keychain secret, read once before the import
    /// applies, which its passwords and, for Arc, its sign-ins both use.
    var safeStorageSecret: String? = nil
    /// Whether the import carries the source browser's sign-ins over.
    var bringsSignIns = true
    /// The icons the source browser kept for the pages the import brings, by
    /// page address, which the tabs it places wear.
    var siteIcons: [String: Data] = [:]
}

struct BrowserOnboardingSignInResult: Equatable, Sendable {
    var cookies = 0
    var expired = 0
    var dropped = 0
    var missing = 0
    var existing = 0
    var unavailable = 0
    var failed = 0
    var merged = 0
}

struct BrowserOnboardingImportResult: Sendable {
    // MARK: - Static Variables

    static let empty = BrowserOnboardingImportResult(passwords: .empty)

    // MARK: - Variables

    let passwords: BrowserPasswordImportResult
    var signIns = BrowserOnboardingSignInResult()
}

enum BrowserOnboardingFailureText: Equatable {
    case localized(LocalizedStringResource)
    case verbatim(String)
}

extension SetupFailure {
    /// What the person is told of the failure: the words the Mac gave it, or
    /// Ode's own for a browser that went or a folder without its data.
    var message: BrowserOnboardingFailureText {
        if let detail { return .verbatim(detail) }
        guard reason == .dataFolder, let source else {
            return .localized(
                LocalizedStringResource(
                    "That browser is no longer available on this Mac.",
                    comment: "Browser-import error shown when a selected source app disappears."))
        }
        return .localized(
            LocalizedStringResource(
                "Ode could not read \(source.title) data there. Try Allow Access again, or choose the \(source.title) data folder if it moved.",
                comment: "Browser-import error. Both variables are the source browser name."))
    }
}
