import Foundation
import Observation

struct BrowserOnboardingImportReadOutput: Sendable {
    let payload: BrowserDetectedImportPayload
    /// The Spaces the core read, with new identities.
    let imported: [SpaceState]
    let passwordCandidates: [BrowserPasswordImportCandidate]
    /// Why the browser's passwords could not be read, when they could not;
    /// the rest of the review comes in without them.
    var passwordFailure: BrowserPasswordImportError? = nil
    /// The extensions each Space offers to install, for the browsers that
    /// keep them where Ode reads them.
    var extensions: [ImportSpaceExtensions] = []
    /// The icon each offered extension wears, by its identifier.
    var extensionIcons: [String: Data] = [:]
    /// The icons the browser kept for the pages of the tabs the Spaces bring,
    /// by page address.
    var siteIcons: [String: Data] = [:]
    /// What the browser held that the import cannot bring, and why.
    var leftOut: [ImportLeftOut] = []
    /// The Chromium profile folder each Space was read from, for browsers
    /// built on Chromium.
    var profiles: [ImportSpaceProfile] = []
    /// Releases a real core read when this output is not handed to a review.
    var discard: @Sendable () -> Void = {}
}

enum BrowserOnboardingImportReadPhase: Equatable {
    case idle
    case reading(id: UUID, application: ImportSource)

    var application: ImportSource? {
        switch self {
        case .idle:
            nil
        case .reading(_, let application):
            application
        }
    }

    var requestID: UUID? {
        switch self {
        case .idle:
            nil
        case .reading(let id, _):
            id
        }
    }
}

@Observable
@MainActor
final class BrowserOnboardingImportReadCoordinator {
    // MARK: - Variables

    private(set) var phase: BrowserOnboardingImportReadPhase = .idle

    var isInFlight: Bool {
        phase.requestID != nil
    }

    @ObservationIgnored private let reader: any BrowserOnboardingImportReading
    @ObservationIgnored private var readTask: Task<Void, Never>?

    // MARK: - Initializers

    init(reader: any BrowserOnboardingImportReading) {
        self.reader = reader
    }

    // MARK: - Actions - Read ownership

    func startReading(
        _ payload: BrowserDetectedImportPayload,
        onFinish: @escaping @MainActor () -> Void = {},
        completion:
            @escaping @MainActor (
                Result<BrowserOnboardingImportReadOutput, any Error>
            ) -> Void
    ) {
        cancel()

        let requestID = UUID()
        let reader = self.reader
        phase = .reading(id: requestID, application: payload.application)
        readTask = Task { @MainActor [weak self] in
            defer { onFinish() }

            let result: Result<BrowserOnboardingImportReadOutput, any Error>
            do {
                try Task.checkCancellation()
                let output = try await reader.read(payload)
                guard !Task.isCancelled else {
                    output.discard()
                    self?.finish(requestID: requestID)
                    return
                }
                result = .success(output)
            } catch is CancellationError {
                self?.finish(requestID: requestID)
                return
            } catch {
                result = .failure(error)
            }

            guard self?.finish(requestID: requestID) == true else {
                if case .success(let output) = result { output.discard() }
                return
            }
            completion(result)
        }
    }

    func cancel() {
        readTask?.cancel()
        readTask = nil
        phase = .idle
    }

    @discardableResult
    private func finish(requestID: UUID) -> Bool {
        guard phase.requestID == requestID else { return false }
        readTask = nil
        phase = .idle
        return true
    }
}
