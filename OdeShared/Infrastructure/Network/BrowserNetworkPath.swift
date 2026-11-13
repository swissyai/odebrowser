import Foundation
import Network
import Observation

/// Whether this device can reach the internet, as the system's path monitor
/// last said. Features that only make sense online, such as opening a
/// search's first result, read it and fall back to what they do offline. It
/// starts out reachable, since the monitor answers within moments.
@MainActor
@Observable
final class BrowserNetworkPath {
    // MARK: - Static Variables

    static let shared = BrowserNetworkPath()

    // MARK: - Variables

    /// Whether the last path the monitor reported can reach the internet.
    private(set) var isSatisfied = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    // MARK: - Initializers

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.isSatisfied = satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "BrowserNetworkPath", qos: .utility))
    }
}
