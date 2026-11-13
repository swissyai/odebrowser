import Foundation
import os

/// A category of Ode's unified log. The application layer writes through
/// it, so the stores that report a core's refusal name where the message goes
/// without depending on the logging framework. A message is written public,
/// whole, as it reads.
struct DiagnosticLog: Sendable {
    // MARK: - Static Variables

    /// The launch record, safe mode and the updates a failed start asks for.
    static let launch = DiagnosticLog(category: "Launch")
    /// The files agents' origin grants and activity are kept in, and what the
    /// core refused about an agent's session.
    static let agents = DiagnosticLog(category: "Agents")
    /// Each main-thread hang: when it began, how long it lasted and the
    /// moment in flight, by kind and tags.
    static let hangs = DiagnosticLog(category: "Hangs")
    static let history = DiagnosticLog(category: "HistoryStorage")
    /// What a model the person turned on could not do, in its provider's
    /// words; never the titles or tabs it was given.
    static let intelligence = DiagnosticLog(category: "Intelligence")
    static let links = DiagnosticLog(category: "Links")
    /// Which pages each window shows, the engine told to show or hide a page,
    /// Picture in Picture and what memory pressure takes back. Pages are named
    /// by their identities, never their addresses.
    static let pages = DiagnosticLog(category: "Pages")
    static let popups = DiagnosticLog(category: "Popups")
    static let shortcuts = DiagnosticLog(category: "Shortcuts")
    static let sitePermissions = DiagnosticLog(category: "SitePermissions")
    static let windows = DiagnosticLog(category: "Windows")

    // MARK: - Variables

    private let logger: Logger

    // MARK: - Initializers

    private init(category: String) {
        logger = Logger(subsystem: "com.odebrowser.ode", category: category)
    }

    // MARK: - Actions - Describing

    /// How a message names `error`: a rejection by its rule alone, because
    /// what it carries can name an address or a site the log must not keep,
    /// and any other error as it describes itself.
    static func describe(_ error: any Error) -> String {
        guard let rejection = error as? Rejection else { return String(describing: error) }
        return Mirror(reflecting: rejection).children.first?.label ?? String(describing: rejection)
    }

    // MARK: - Actions - Writing

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
