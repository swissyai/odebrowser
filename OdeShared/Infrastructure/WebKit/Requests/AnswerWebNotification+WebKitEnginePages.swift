import Foundation

extension AnswerWebNotification {
    /// WebKit's documents hear about their notifications through Ode's
    /// hosted notification bridge instead.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
