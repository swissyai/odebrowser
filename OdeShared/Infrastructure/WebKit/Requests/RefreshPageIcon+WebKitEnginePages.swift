import Foundation

extension RefreshPageIcon {
    /// Ode fetches its WebKit pages' icons itself.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
