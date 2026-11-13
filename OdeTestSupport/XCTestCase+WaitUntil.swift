import XCTest

extension XCTestCase {
    /// Waits until `condition` holds, asking again every `interval`, or
    /// after a yield to the caller's other work when `interval` is zero.
    /// Once `timeout` passes without it, fails the test naming
    /// `description`. The condition runs on the caller's actor, so it may
    /// read the caller's state.
    @nonobjc func waitUntil(
        _ description: String = "the condition",
        timeout: Duration = .seconds(10),
        interval: Duration = .milliseconds(25),
        isolation: isolated (any Actor)? = #isolation,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () async throws -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while try await !condition() {
            guard clock.now < deadline else {
                return XCTFail("Timed out waiting for \(description).", file: file, line: line)
            }
            if interval == .zero {
                await Task.yield()
            } else {
                try await Task.sleep(for: interval)
            }
        }
    }
}
