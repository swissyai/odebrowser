import Foundation

extension MuteMediaSession {
    /// Ode runs its WebKit pages' Media Session through its own bridge in the page.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
