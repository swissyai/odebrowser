#if DEBUG || ODE_REVIEW_BUILD

    /// Takes the staged players' controls and remembers what they asked.
    @MainActor
    final class BrowserMacHarnessMediaEndpoint: BrowserMediaSessionCommandEndpoint {
        private(set) var actions: [MediaSessionAction] = []

        func performMediaSessionAction(_ action: MediaSessionAction, documentIdentifier: String) {
            actions.append(action)
        }

        func setMediaSessionMuted(_ muted: Bool, documentIdentifier: String) {}
    }

#endif
