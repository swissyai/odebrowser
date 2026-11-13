#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import QuartzCore

    /// The harness's frame-pacing command: switch Space as the switcher does
    /// and report how evenly the window's frames arrived meanwhile.
    extension BrowserMacHarness {
        // MARK: - Actions - Frames

        /// Switches the window to the Space named `name` and counts the
        /// display's frames for `seconds`: how many came, the usual gap
        /// between them, the longest, and how many came late.
        func measureSpaceSwitch(name: String, seconds: Double) async throws -> [String: Any] {
            let context = try context()
            guard let space = context.browser.spaceModels.first(where: { $0.settings.name == name }) else {
                throw Failure(description: "No Space is named \(name)")
            }
            guard let view = try targetWindow().contentView else {
                throw Failure(description: "The window has no view")
            }
            let clock = BrowserMacHarnessFrameClock()
            clock.start(on: view)
            try? await Task.sleep(for: .milliseconds(120))
            context.browser.selectSpace(space.id)
            context.pages.selectSpace(in: context.browser)
            try? await Task.sleep(for: .seconds(seconds))
            clock.stop()
            return clock.report()
        }
    }

#endif
