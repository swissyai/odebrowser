import XCTest

@testable import Ode

@MainActor
final class BrowserMacHarnessTests: XCTestCase {
    func testHarnessStaysOffWithoutItsVariableOrAnIsolatedSession() throws {
        let isolated = BrowserLaunchEnvironment(values: ["ODE_ISOLATED_SESSION": "1"], isXCTestRuntime: false)
        let installed = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
        XCTAssertTrue(isolated.requiresIsolation)
        XCTAssertFalse(installed.requiresIsolation)
        XCTAssertFalse(BrowserMacHarness.isRequested(isolated, values: ["ODE_ISOLATED_SESSION": "1"]))
        XCTAssertTrue(BrowserMacHarness.isRequested(isolated, values: ["ODE_TEST_HARNESS": "1"]))
        XCTAssertFalse(BrowserMacHarness.isRequested(installed, values: ["ODE_TEST_HARNESS": "1"]))
        XCTAssertFalse(BrowserMacHarness.isRequested(isolated, values: ["ODE_TEST_HARNESS": "0"]))
    }

    func testRequestsDecodeTheirCommandAndArguments() {
        let (command, arguments) = BrowserMacHarness.decode(Data(#"{"command": "measureCommandBar", "runs": 3}"#.utf8))
        XCTAssertEqual(command, "measureCommandBar")
        XCTAssertEqual(arguments["runs"] as? Int, 3)
        XCTAssertEqual(BrowserMacHarness.decode(Data("not json".utf8)).command, "")
    }

    func testRepliesCarryOkAndTheCommandOrTheError() throws {
        let success = BrowserMacHarness.encode(.success(["pid": 7]), command: "ping")
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: success) as? [String: Any])
        XCTAssertEqual(decoded["ok"] as? Bool, true)
        XCTAssertEqual(decoded["command"] as? String, "ping")
        XCTAssertEqual(decoded["pid"] as? Int, 7)
        XCTAssertFalse(success.contains(0x0A), "A reply is one line")

        let failure = BrowserMacHarness.encode(
            .failure(BrowserMacHarness.Failure(description: "Unknown command nope")), command: "nope")
        let refused = try XCTUnwrap(JSONSerialization.jsonObject(with: failure) as? [String: Any])
        XCTAssertEqual(refused["ok"] as? Bool, false)
        XCTAssertEqual(refused["error"] as? String, "Unknown command nope")
    }

    func testSummaryReportsMedianPercentileFirstAndFastest() throws {
        let samples: [[String: Double]] = (1...20).map { ["focused": Double($0)] } + [["frameCommitted": 9]]
        let summary = BrowserMacHarness.summary(of: samples)
        let focused = try XCTUnwrap(summary["focused"])
        XCTAssertEqual(focused["count"], 20)
        XCTAssertEqual(focused["first"], 1)
        XCTAssertEqual(focused["min"], 1)
        XCTAssertEqual(focused["median"], 11)
        XCTAssertEqual(focused["p95"], 19)
        XCTAssertEqual(summary["frameCommitted"]?["count"], 1)
    }

    func testCommandBarMarksReachAnObserverInOrder() {
        var heard: [BrowserCommandBarTiming.Mark] = []
        BrowserCommandBarTiming.observer = { mark, _ in heard.append(mark) }
        defer { BrowserCommandBarTiming.observer = nil }
        BrowserCommandBarTiming.mark(.command)
        BrowserCommandBarTiming.mark(.focused)
        XCTAssertEqual(heard, [.command, .focused])
    }
}
