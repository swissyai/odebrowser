import UIKit

@MainActor
enum BrowserPlatformFeedbackHandoff {
    // MARK: - Actions - Handoff

    static func open(_ url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.open(url, options: [:]) { accepted in
            Task { @MainActor in completion(accepted) }
        }
    }

    static func copy(_ text: String) -> Bool {
        UIPasteboard.general.string = text
        return true
    }
}
