import AppKit

@MainActor
enum BrowserPlatformFeedbackHandoff {
    // MARK: - Actions - Handoff

    static func open(_ url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        // Acceptance means LaunchServices received the request, not that a composer appeared.
        completion(NSWorkspace.shared.open(url))
    }

    static func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
