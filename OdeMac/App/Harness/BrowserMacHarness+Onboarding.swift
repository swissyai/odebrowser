#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import SwiftUI

    /// The harness's setup commands: draw the import stage over the window's
    /// own Spaces, still at a moment of its beats, without reading any other
    /// browser's data.
    extension BrowserMacHarness {
        // MARK: - Actions - Import stage

        /// Shows the import stage in a window titled "Import Stage", bringing
        /// the window's Spaces as if from `source`, drawn still `time` seconds
        /// in, and done with `passwords` passwords when `done` says.
        func showImportStage(_ arguments: [String: Any]) throws -> [String: Any] {
            let browser = try context().browser
            let time = arguments["time"] as? Double ?? 0.8
            let passwords = arguments["passwords"] as? Int ?? 0
            let stage = BrowserOnboardingImportStage(
                sourceTitle: arguments["source"] as? String ?? "Arc", sourceIcon: nil,
                favicons: browser.core.state.favicons, spaces: browser.spaceModels, passwordCount: passwords,
                readsKeychain: arguments["reading"] as? Bool ?? false,
                leftOut: [],
                startedAt: Date().addingTimeInterval(-time))
            if arguments["done"] as? Bool == true { stage.finish(passwords: passwords) }
            return show(
                BrowserOnboardingImportStageView(stage: stage, frozenTime: time)
                    .frame(width: 880, height: 600),
                titled: "Import Stage", width: 912)
        }
    }

#endif
