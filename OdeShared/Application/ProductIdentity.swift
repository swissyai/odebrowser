import Foundation

/// Which copy of Ode this process is. Only the released app runs as
/// `com.odebrowser.ode`; every other build (Debug, tests, the harness, review
/// packages) runs as the development identity, whose bundle identifiers all
/// start with `com.odebrowser.ode.dev`. Everything named after the identity
/// follows it: the preferences domains, the data folder, keychain services,
/// the agent socket, the export folder and the crash reports Ode lists. A
/// development build therefore never reads or changes the released app's
/// data, and the released app never sees a development build's crashes.
enum ProductIdentity {
    // MARK: - Static Variables

    static let name = "Ode"
    /// The released app's bundle identifier. Every Ode bundle identifier
    /// starts with it.
    static let releaseBundleIdentifier = "com.odebrowser.ode"
    /// The prefix every non-release build's bundle identifiers carry.
    static let developmentBundleIdentifier = "com.odebrowser.ode.dev"
    /// Whether this process is the released app.
    static let isRelease = isRelease(bundleIdentifier: Bundle.main.bundleIdentifier)
    /// This copy's identity: the released app's bundle identifier, or the
    /// development one for every other build.
    static let bundleIdentifier = isRelease ? releaseBundleIdentifier : developmentBundleIdentifier
    static let serviceNamespace = bundleIdentifier
    /// The folder under Application Support that holds this copy's data.
    static let storageDirectoryName = storageDirectoryName(forApp: Bundle.main.bundleIdentifier)
    /// The folder in Documents that automatic exports go to by default.
    static let exportDirectoryName = "\(storageDirectoryName) Export"
    /// The product's website; feedback and requests go to pages under it.
    static let website = URL(string: "https://odebrowser.com")!
    /// Where every update feed is published, one appcast per channel and engine.
    static let updateFeeds = URL(string: "https://odebrowser.com/updates/")!

    // MARK: - Actions - Identity

    /// Whether `bundleIdentifier` is the released app's own.
    static func isRelease(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == releaseBundleIdentifier
    }

    /// The data folder name of the app whose bundle identifier is
    /// `bundleIdentifier`, for code such as the agent helper that runs outside
    /// that app.
    static func storageDirectoryName(forApp bundleIdentifier: String?) -> String {
        isRelease(bundleIdentifier: bundleIdentifier) ? name : "\(name) Dev"
    }

    /// Whether a process whose bundle identifier is `other` belongs to this
    /// copy of Ode: the app itself or one of its helpers. The released app
    /// never claims a development build's identifiers.
    static func owns(bundleIdentifier other: String, app: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard let app else { return false }
        if other == app { return true }
        guard other.hasPrefix(app + ".") else { return false }
        return !isRelease(bundleIdentifier: app) || !other.hasPrefix(developmentBundleIdentifier)
    }
}
