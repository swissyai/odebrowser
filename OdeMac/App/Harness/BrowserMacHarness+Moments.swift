#if DEBUG || ODE_REVIEW_BUILD

    import Foundation

    /// The harness's view of the moments ledger: the summary a run reports,
    /// as `tools/dev/ode-harness.py moments` writes it, and a fresh start for
    /// a run that measures from a known point.
    extension BrowserMacHarness {
        // MARK: - Actions - Moments

        /// The ledger's summary under `summary`; with `reset`, the ledger then
        /// starts again from nothing.
        func moments(reset: Bool) throws -> [String: Any] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(BrowserMoments.shared.ledger.summary)
            guard let summary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure(description: "The moments summary is not an object")
            }
            if reset { BrowserMoments.shared.reset() }
            return ["summary": summary]
        }
    }

#endif
