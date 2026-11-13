import Foundation
import Observation
import os

/// Finds which agents' commands are installed on this Mac and runs the line
/// that adds Ode to one, both through the person's login shell so their
/// PATH applies. It runs only those lookups and the registration lines the
/// agents' commands describe.
@MainActor
@Observable
final class BrowserAgentConnector {
    // MARK: - Static Variables

    /// One connector per launch, so what the shell found holds until Ode
    /// quits.
    static let shared = BrowserAgentConnector()

    nonisolated private static let shell = URL(filePath: "/bin/zsh")
    /// How long finding a command may take, including the person's shell
    /// startup files.
    private static let lookupTimeout: TimeInterval = 5
    /// How long a registration may take before it is stopped.
    private static let registrationTimeout: TimeInterval = 30
    /// How long a stopped shell has to exit before it is killed.
    nonisolated private static let terminationTimeout: TimeInterval = 2
    /// How long output may keep arriving after the shell exits, as from a
    /// process it left holding the output open.
    nonisolated private static let drainTimeout: TimeInterval = 1

    // MARK: - Types

    /// How a command line ended: its exit status, and what it wrote to
    /// standard output and standard error, trimmed.
    struct Outcome: Equatable, Sendable {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }
    }

    // MARK: - Variables

    /// Whether each command was found, once its lookup finished.
    private(set) var installed: [BrowserAgentCommand: Bool] = [:]
    private var lookups: Set<BrowserAgentCommand> = []

    // MARK: - Actions - Lookup

    func isInstalled(_ command: BrowserAgentCommand) -> Bool {
        installed[command] == true
    }

    /// Looks the command up once per launch; later calls keep the first
    /// answer.
    func find(_ command: BrowserAgentCommand) async {
        guard installed[command] == nil, lookups.insert(command).inserted else { return }
        let outcome = await Self.run("command -v \(command.name)", timeout: Self.lookupTimeout)
        installed[command] = outcome.succeeded
        lookups.remove(command)
    }

    // MARK: - Actions - Registration

    /// Runs the command's own line that adds Ode, with the helper at `helper`.
    func register(_ command: BrowserAgentCommand, helper: String) async -> Outcome {
        await Self.run(command.line(helper: helper), timeout: Self.registrationTimeout)
    }

    // MARK: - Actions - Shell

    /// Runs the script in the person's login shell on a background queue,
    /// stopping it after the timeout.
    nonisolated private static func run(_ script: String, timeout: TimeInterval) async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runNow(script, timeout: timeout))
            }
        }
    }

    nonisolated private static func runNow(_ script: String, timeout: TimeInterval) -> Outcome {
        let process = Process()
        process.executableURL = shell
        process.arguments = ["-l", "-c", script]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return Outcome(status: -1, output: error.localizedDescription)
        }

        let output = OSAllocatedUnfairLock(initialState: Data())
        let drained = DispatchSemaphore(value: 0)
        let reading = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = reading.availableData
                if chunk.isEmpty { break }
                output.withLock { $0.append(chunk) }
            }
            drained.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + terminationTimeout) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        _ = drained.wait(timeout: .now() + drainTimeout)
        let text = String(decoding: output.withLock { $0 }, as: UTF8.self)
        return Outcome(status: process.terminationStatus, output: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
