import Foundation

extension SchemeHandling {
    // MARK: - Actions - Answer

    /// Which engine, if any, owns a navigation once its scheme is known. Only
    /// a load Ode itself initiated may keep `file:`. An unanswered question
    /// blocks the scheme.
    static func disposition(for url: URL?, isAppInitiated: Bool = false) -> ExternalSchemeDisposition {
        let question = SchemeHandling(scheme: url?.scheme.nonEmpty, appInitiated: isAppInitiated)
        return (try? OdeCore.answer(question))?.disposition ?? .blocked
    }
}
