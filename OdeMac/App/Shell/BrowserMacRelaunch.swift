import AppKit

/// Opens Ode again once this process has quit, for leaving safe mode: the
/// next launch runs normally. A quit the person or a page declines leaves
/// the waiting opener to give up after `patience`.
@MainActor
enum BrowserMacRelaunch {
    static let patience = 120

    /// Starts the opener, then asks Ode to quit through the usual quit.
    static func relaunchAfterQuit() {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/bin/sh")
        opener.arguments = [
            "-c",
            "i=0; while /bin/kill -0 \"$1\" 2>/dev/null; do i=$((i+1)); [ $i -gt $3 ] && exit 0; /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
            "ode-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
            String(patience * 5),
        ]
        do {
            try opener.run()
        } catch {
            DiagnosticLog.launch.notice("Ode could not arrange to open again: \(DiagnosticLog.describe(error))")
        }
        NSApp.terminate(nil)
    }
}
