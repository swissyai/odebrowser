import Foundation

@testable import Ode

extension DownloadState {
    /// A download record for tests that need one without running the core.
    static func fixture(
        id: UUID = UUID(),
        profileID: UUID,
        createdAt: Date = .now,
        filename: String = "report.pdf",
        destination: URL? = nil,
        progress: Double = 0,
        phase: DownloadPhase = .preparing,
        message: String? = nil,
        bytesReceived: Int64 = 0,
        isAcknowledged: Bool = false
    ) -> DownloadState {
        DownloadState(
            id: id,
            profileID: profileID,
            createdAt: createdAt,
            filename: filename,
            destination: destination?.absoluteString,
            progress: progress,
            telemetry: DownloadTelemetry(
                bytesReceived: bytesReceived, totalBytes: nil, bytesPerSecond: nil, estimatedTimeRemaining: nil,
                isPaused: false),
            phase: phase,
            failure: nil,
            message: message,
            risk: nil,
            isAcknowledged: isAcknowledged, canPause: false, canResume: false
        )
    }
}
