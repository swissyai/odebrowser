import AppKit

/// The WebKit product's entry point, which runs AppKit's application with the
/// shared Mac shell behind `OdeAppDelegate`. The Chromium product is entered
/// through `ChromiumComposition` and leaves this folder out.
@main
enum OdeMain {
    // MARK: - Actions - Launch

    @MainActor
    static func main() {
        // The core decides which windows a launch opens. AppKit replays none
        // of the windows an earlier release saved for its own restoration.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
        let application = NSApplication.shared
        #if DEBUG || ODE_REVIEW_BUILD
            // A test run hosted here keeps every window off the screens and
            // never comes forward, so it neither covers nor takes focus from
            // the person's own work, and the person's pointer reaches no test.
            if BrowserLaunchEnvironment.current.isXCTestRuntime {
                application.setActivationPolicy(.accessory)
                BrowserMacHarnessWindows.install(.shifted)
                BrowserPointerLocation.current = { BrowserPointerLocation.outsideEveryWindow }
            }
        #endif
        let delegate = OdeAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
