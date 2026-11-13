import Foundation

#if os(macOS)
    @testable import Ode
#else
    @testable import OdeMobile
#endif

/// Authenticates the device owner at once, every time.
final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason _: String) async throws -> Bool {
        true
    }
}

/// Holds each authentication until the test answers it, counting how many
/// were asked for.
final class HeldAuthenticator: BrowserDeviceAuthenticating {
    // MARK: - Variables

    private(set) var attemptCount = 0
    private var request: CheckedContinuation<Bool, Error>?
    private var waiter: CheckedContinuation<Void, Never>?

    // MARK: - Actions - Authenticating

    func authenticate(reason _: String) async throws -> Bool {
        attemptCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            request = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    /// Returns once an authentication is held.
    func waitForRequest() async {
        if request != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    /// Answers the held authentication with `allowed`.
    func resolve(_ allowed: Bool) {
        let pending = request
        request = nil
        pending?.resume(returning: allowed)
    }
}
