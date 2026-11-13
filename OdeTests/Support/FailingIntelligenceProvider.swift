import Foundation

@testable import Ode

/// A provider whose model fails every request with `failure`, and which
/// reports itself as `isAvailable` with `summary`, for the paths a feature
/// takes when a model cannot answer.
struct FailingIntelligenceProvider: BrowserIntelligenceProvider {
    // MARK: - Variables

    let isAvailable: Bool
    let summary: String
    let failure: any Error

    // MARK: - Actions

    func availability() async -> BrowserIntelligenceAvailability {
        BrowserIntelligenceAvailability(isAvailable: isAvailable, summary: summary)
    }

    func complete(instructions: String, prompt: String) async throws -> String {
        throw failure
    }
}
