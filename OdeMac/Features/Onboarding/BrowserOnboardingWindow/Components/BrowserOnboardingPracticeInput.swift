import AppKit
import SwiftUI

/// A window-scoped native input seam. It never consumes another window's
/// event and removes its monitor when the handoff ends.
struct BrowserOnboardingPracticeInput: NSViewRepresentable {
    // MARK: - Variables

    let practice: BrowserOnboardingPractice
    let escape: () -> Void

    // MARK: - Actions - Native input

    func makeNSView(context: Context) -> InputView {
        InputView(practice: practice, escape: escape)
    }

    func updateNSView(_ nsView: InputView, context: Context) {}

    static func dismantleNSView(_ nsView: InputView, coordinator: ()) {
        nsView.stop()
    }

    @MainActor
    final class InputView: NSView {
        // MARK: - Variables

        private let practice: BrowserOnboardingPractice
        private let escape: () -> Void
        private var monitor: Any?

        // MARK: - Initializers

        init(practice: BrowserOnboardingPractice, escape: @escaping () -> Void) {
            self.practice = practice
            self.escape = escape
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, let window = self.window,
                        event.window === window, NSApp.keyWindow === window,
                        window.attachedSheet == nil, NSApp.modalWindow == nil
                    else { return false }
                    if event.keyCode == 53 {
                        if self.practice.chrome.isCommandPalettePresented {
                            self.practice.chrome.dismissCommandPalette()
                        } else {
                            self.escape()
                        }
                        return true
                    }
                    return self.practice.handle(event)
                }
                return handled ? nil : event
            }
        }

        required init?(coder: NSCoder) { nil }

        // MARK: - Actions - Lifecycle

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
