import Foundation

/// A pinned or saved tab's main document as its preview reads it: a site's
/// reader run in a script world the page cannot see, through whichever engine
/// shows the page. Nothing the reader learns goes back into the page.
@MainActor
struct BrowserTabPreviewDocument {
    // MARK: - Types

    /// Runs `body` as the body of an async function with `arguments` bound as
    /// constants, in the main document's preview world, and answers its
    /// result, or nil when the document is gone.
    typealias Evaluate = @MainActor (_ body: String, _ arguments: [String: Any]) async throws -> Any?

    /// Resumes a read once, with its answer or with nothing once it took too
    /// long.
    @MainActor
    private final class Outcome {
        private var continuation: CheckedContinuation<Data?, Never>?

        init(_ continuation: CheckedContinuation<Data?, Never>) {
            self.continuation = continuation
        }

        func finish(_ answer: Data?) {
            continuation?.resume(returning: answer)
            continuation = nil
        }
    }

    // MARK: - Variables

    private let evaluate: Evaluate

    // MARK: - Initializers

    init(evaluate: @escaping Evaluate) {
        self.evaluate = evaluate
    }

    /// The main document of a page whose engine runs Ode's content bridges
    /// itself, in the isolated world they share.
    init(mainFrameOf scripting: any BrowserPageContentScripting) {
        evaluate = { [weak scripting] body, arguments in
            try await scripting?.callAsyncJavaScriptInMainFrame(body, arguments: arguments)
        }
    }

    // MARK: - Actions - Reading

    /// This document, telling `reading` when a reader starts running and when
    /// it ends.
    func observing(_ reading: @escaping @MainActor (_ isReading: Bool) -> Void) -> BrowserTabPreviewDocument {
        let evaluate = evaluate
        return BrowserTabPreviewDocument { body, arguments in
            reading(true)
            defer { reading(false) }
            return try await evaluate(body, arguments)
        }
    }

    /// Runs `reader` and answers the JSON text it returned, or nil when it
    /// returned none within `timeout`. A frozen page never answers, and the
    /// read gives up on it.
    func read(_ reader: String, timeout: Duration) async -> Data? {
        let evaluate = evaluate
        return await withCheckedContinuation { continuation in
            let outcome = Outcome(continuation)
            Task { @MainActor in
                let answer = (try? await evaluate(reader, [:])) as? String
                outcome.finish(answer.map { Data($0.utf8) })
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                outcome.finish(nil)
            }
        }
    }
}
