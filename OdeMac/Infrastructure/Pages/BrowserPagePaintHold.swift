import AppKit
import Observation

// MARK: - Types

/// A temporary cover for a document that has not painted yet.
struct BrowserPagePaintCover: Equatable {
    let image: CGImage?
    let color: CGColor
    let generation: Int
}

/// Covers an empty page until it paints, without retaining stale content for
/// more than a second. Navigation failures bypass the cover at presentation.
@MainActor
@Observable
final class BrowserPagePaintHold {
    // MARK: - Static Variables

    static let maximumHold: Duration = .seconds(1)
    /// A completed document can report loading finished before its frame arrives.
    static let loadSettle: Duration = .milliseconds(100)

    // MARK: - Variables

    private(set) var cover: BrowserPagePaintCover?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var completion: Task<Void, Never>?
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void

    // MARK: - Initializers

    init(sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    // MARK: - Actions - Covering

    func hold(image: CGImage?, color: CGColor) {
        painted()
        generation &+= 1
        cover = BrowserPagePaintCover(image: image, color: color, generation: generation)
        let held = generation
        expiry = Task { [weak self, sleep] in
            await sleep(Self.maximumHold)
            guard !Task.isCancelled, let self, self.generation == held else { return }
            self.painted()
        }
    }

    func painted() {
        expiry?.cancel()
        completion?.cancel()
        expiry = nil
        completion = nil
        cover = nil
    }

    /// Releases documents without a paint bridge too, while the original
    /// deadline remains in force even when loading completes late.
    func loadEnded() {
        guard cover != nil else { return }
        let held = generation
        completion?.cancel()
        completion = Task { [weak self, sleep] in
            await sleep(Self.loadSettle)
            guard !Task.isCancelled, let self, self.generation == held else { return }
            self.painted()
        }
    }
}
