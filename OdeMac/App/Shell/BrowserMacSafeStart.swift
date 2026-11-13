import AppKit
import SwiftUI

/// The window a launch shows before it builds the browser when the launches
/// before it did not finish starting, or when Shift was held: start in safe
/// mode, start normally, look for a fixed version, or quit. Nothing here loads
/// an engine, so a crash in the engine, an extension or a restored page cannot
/// stop it. After repeated failures, or when safe mode itself failed, it
/// offers recovery: an update, safe mode once more, or quitting.
@MainActor
final class BrowserMacSafeStart {
    // MARK: - Types

    enum Choice {
        case safeMode
        case normal
    }

    // MARK: - Variables

    private let window: NSWindow
    private var keyMonitor: Any?
    private var chosen: ((Choice) -> Void)?

    // MARK: - Initializers

    /// Shows the window for `decision`, with `softwareUpdates` to look for a
    /// fixed version, and calls `choose` once with the person's choice.
    /// `restoreEarlierCopy`, when given, offers the dated copies of the
    /// session; `storageDirectory` shows the saved files.
    init(
        decision: BrowserLaunchSafetyDecision,
        safeMode: BrowserSafeMode,
        softwareUpdates: BrowserSoftwareUpdateService,
        storageDirectory: URL?,
        restoreEarlierCopy: (@MainActor () -> Void)? = nil,
        choose: @escaping @MainActor (Choice) -> Void
    ) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            // Closing it would leave the launch waiting with nothing on screen;
            // Quit is the way out.
            styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.title = ProductIdentity.name
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        chosen = choose
        let content = NSHostingView(
            rootView: BrowserSafeStartView(
                decision: decision, safeMode: safeMode, softwareUpdates: softwareUpdates,
                storageDirectory: storageDirectory, restoreEarlierCopy: restoreEarlierCopy,
                choose: { [weak self] choice in self?.finish(choice) }))
        // The window follows its content as the update section changes.
        content.sizingOptions = [.preferredContentSize]
        window.contentView = content
        installQuitMenu()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions - Choosing

    private func finish(_ choice: Choice) {
        guard let chosen else { return }
        self.chosen = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window.close()
        chosen(choice)
    }

    /// A menu bar that can only quit, and Command-Q, until the launch goes on.
    private func installQuitMenu() {
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
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "q"
            else { return event }
            NSApp.terminate(nil)
            return nil
        }
    }
}

/// The safe start window's content.
struct BrowserSafeStartView: View {
    let decision: BrowserLaunchSafetyDecision
    let safeMode: BrowserSafeMode
    let softwareUpdates: BrowserSoftwareUpdateService
    let storageDirectory: URL?
    let restoreEarlierCopy: (@MainActor () -> Void)?
    let choose: @MainActor (BrowserMacSafeStart.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            Text(title)
                .font(.title2.bold())
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            if offersUpdate {
                BrowserLaunchUpdateSection(softwareUpdates: softwareUpdates, purpose: .failedStarts)
            }
            if restoreEarlierCopy != nil || (isRecovery && storageDirectory != nil) {
                HStack(spacing: OdeSpacing.large) {
                    if let restoreEarlierCopy {
                        Button("Restore from an earlier copy…", action: restoreEarlierCopy)
                    }
                    if isRecovery, let storageDirectory {
                        Button("Show saved files") { NSWorkspace.shared.open(storageDirectory) }
                    }
                }
                .buttonStyle(.link)
            }
            HStack(spacing: OdeSpacing.medium) {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                if !isRecovery {
                    Button("Start normally") { choose(.normal) }
                        .accessibilityIdentifier("safe-start-normally")
                }
                Button("Start in safe mode") { choose(.safeMode) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("safe-start-safe-mode")
            }
        }
        .padding(28)
        .frame(width: 560, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var isRecovery: Bool {
        if case .recover = decision { return true }
        return false
    }

    /// Asked with Shift, the launch had nothing to fix.
    private var offersUpdate: Bool {
        if case .askSafeStart(_, true) = decision { return false }
        return true
    }

    private var title: String {
        switch decision {
        case .askSafeStart(_, true):
            String(localized: "Start Ode in safe mode?")
        case .askSafeStart(let failedStarts, false):
            String(localized: "Ode didn't finish starting the last \(failedStarts) times")
        case .recover:
            String(localized: "Ode still isn't starting")
        case .start:
            ""
        }
    }

    private var message: String {
        switch decision {
        case .recover(let failedStarts, let safeModeFailed):
            let what =
                safeModeFailed
                ? String(localized: "It didn't finish starting in safe mode either.")
                : String(localized: "It didn't finish starting the last \(failedStarts) times.")
            return what + " "
                + String(localized: "A newer version may fix it, or you can try safe mode again. Nothing is deleted or changed.")
        default:
            return safeMode.offer
        }
    }
}

/// The note each window shows while the launch runs in safe mode, with the
/// way back.
struct BrowserSafeModeBanner: View {
    let safeMode: BrowserSafeMode
    let restartNormally: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: OdeSpacing.medium) {
            Label(safeMode.banner, systemImage: "lifepreserver")
                .lineLimit(2)
            Button("Restart normally", action: restartNormally)
                .buttonStyle(.borderless)
                .foregroundStyle(OdeBrandTheme.accent)
                .accessibilityIdentifier("safe-mode-restart-normally")
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, OdeSpacing.large)
        .padding(.vertical, OdeSpacing.small)
        .background {
            if reduceTransparency {
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("safe-mode-banner")
    }
}
