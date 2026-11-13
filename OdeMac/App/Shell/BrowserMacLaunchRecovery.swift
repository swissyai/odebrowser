import AppKit
import SwiftUI

/// The window a launch that could not open the session shows instead of the
/// browser, with a menu bar that can only quit. Restoring the session there
/// continues into the normal launch, and a newer version can be installed
/// from it, which a session saved by a newer build needs.
@MainActor
final class BrowserMacLaunchRecovery {
    // MARK: - Types

    /// The recovery view, which hands the application on once the launch
    /// built it.
    private struct Content: View {
        let launch: BrowserApplicationLaunch<BrowserMacApplication>
        let softwareUpdates: BrowserSoftwareUpdateService?
        let restoreEarlierCopy: (@MainActor () -> Void)?
        let launched: @MainActor (BrowserMacApplication) -> Void

        var body: some View {
            VStack(spacing: 0) {
                BrowserSessionRecoveryView(launch: launch, restoreEarlierCopy: restoreEarlierCopy)
                if let softwareUpdates {
                    Divider()
                    BrowserLaunchUpdateSection(softwareUpdates: softwareUpdates, purpose: .session)
                        .padding(.horizontal, 32)
                        .padding(.vertical, OdeSpacing.large)
                }
            }
            .onChange(of: launch.value != nil, initial: true) {
                if let application = launch.value { launched(application) }
            }
        }
    }

    // MARK: - Variables

    private let window: NSWindow
    /// Quits on Command-Q even while the engine's own views would take the
    /// key equivalent first.
    private var keyMonitor: Any?

    // MARK: - Initializers

    /// Shows recovery for `launch`, with `softwareUpdates` to install a newer
    /// version from and `restoreEarlierCopy` to offer the dated copies of the
    /// session, and calls `launched` once it succeeds.
    init(
        launch: BrowserApplicationLaunch<BrowserMacApplication>,
        softwareUpdates: BrowserSoftwareUpdateService? = nil,
        restoreEarlierCopy: (@MainActor () -> Void)? = nil,
        launched: @escaping @MainActor (BrowserMacApplication) -> Void
    ) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: softwareUpdates == nil ? 380 : 480),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "Ode Recovery")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = NSHostingView(
            rootView: Content(
                launch: launch, softwareUpdates: softwareUpdates, restoreEarlierCopy: restoreEarlierCopy,
                launched: launched))
        let menu = NSMenu()
        let item = NSMenuItem()
        let applicationMenu = NSMenu(title: ProductIdentity.name)
        let quit = NSMenuItem(
            title: String(localized: "Quit Ode"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quit.target = NSApp
        applicationMenu.addItem(quit)
        item.submenu = applicationMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard BrowserShortcut(event: event) == BrowserShortcut(key: .character("q"), modifiers: .command)
            else { return event }
            NSApp.terminate(nil)
            return nil
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions - Closing

    /// The launch succeeded: recovery goes, and the shell's menus replace its
    /// own.
    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window.close()
    }
}
