import AppKit
import CryptoKit
import Foundation

/// One JSON file an agent feature keeps in the app's Agents directory, such as
/// the origin grants and the activity log. The store reads the file once off
/// the main thread and hands what it holds to its owner, then writes the
/// owner's value a moment after the latest change and again before the app
/// quits, in order on the file's own queue. Nothing is written before the
/// stored value is in, so a save never replaces what was not read yet.
///
/// A file that is there but does not read or decode is never written over:
/// the store moves it aside under a dated name in the same directory, logs
/// the named failure to the Agents diagnostics log and starts empty. When it
/// cannot move the file, it leaves it in place and writes nothing for the rest
/// of the run. A save that does not reach the disk is logged the same way.
@MainActor
final class BrowserAgentFileStore<Value: Codable & Sendable> {
    // MARK: - Types

    /// Why the store did not read its file or did not write it.
    enum Failure: Error, Equatable, Sendable {
        /// The file did not read or decode and was moved to `keptAt`.
        case unreadable(keptAt: URL)
        /// The file did not read or decode and could not be moved aside, so
        /// it stays where it is and the store writes nothing.
        case unreadableAndUnmoved
        /// A save did not reach the disk.
        case unwritable
    }

    // MARK: - Static Variables

    private static var directoryName: String { "Agents" }

    // MARK: - Variables

    /// Where the value is kept, or nil when this launch keeps it in memory.
    let file: URL?
    /// What the file holds, as the diagnostics log names it.
    private let name: String
    private let saveDelay: Duration
    /// Reads and writes the file in order, off the main thread.
    private let queue: DispatchQueue
    /// Whether the stored value is in, before which nothing is written.
    private(set) var isLoaded = false
    /// False once an unreadable file could not be moved aside.
    private var isWritable = true
    private var snapshot: (@MainActor () -> Value?)?
    private var pendingSave: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    // MARK: - Initializers

    /// A store for `file`, named `name` in the diagnostics log, that writes
    /// `saveDelay` after the latest change on a queue labelled `queueLabel`.
    init(file: URL?, name: String, queueLabel: String, saveDelay: Duration) {
        self.file = file
        self.name = name
        self.saveDelay = saveDelay
        queue = DispatchQueue(label: "\(ProductIdentity.serviceNamespace).agents.\(queueLabel)", qos: .utility)
    }

    /// The file named `fileName` for `environment`: the installed app's, or
    /// the one a persistent review launch keeps apart from it. Nil keeps the
    /// value in memory.
    static func file(named fileName: String, for environment: BrowserLaunchEnvironment) -> URL? {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else { return nil }
        var directory =
            applicationSupport
            .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        if environment.requiresIsolation {
            guard !environment.isXCTestRuntime, !environment.isSwiftUIPreviewRuntime,
                let identity = environment.persistentIsolationID
            else { return nil }
            let namespace = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            directory =
                directory
                .appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true)
        }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    // MARK: - Actions - Loading

    /// Reads the file, then hands its value to `restore` on the main actor,
    /// or nil when there is none yet or it was set aside. Saves write what
    /// `snapshot` answers then; a nil snapshot writes nothing.
    func load(
        restore: @escaping @MainActor @Sendable (Value?) -> Void,
        snapshot: @escaping @MainActor () -> Value?
    ) {
        self.snapshot = snapshot
        guard let file else {
            isLoaded = true
            restore(nil)
            return
        }
        let name = name
        queue.async { [weak self] in
            let (stored, failure) = Self.read(file, named: name)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if failure == .unreadableAndUnmoved { self.isWritable = false }
                    self.isLoaded = true
                    restore(stored)
                }
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// What `file` holds, or nil with the failure that set it aside. A file
    /// that is not there yet is no failure.
    private nonisolated static func read(_ file: URL, named name: String) -> (Value?, Failure?) {
        do {
            return (try JSONDecoder().decode(Value.self, from: Data(contentsOf: file)), nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (nil, nil)
        } catch {
            let failure = setAside(file)
            let kept =
                switch failure {
                case .unreadable(let keptAt): "moved it aside as \(keptAt.lastPathComponent) and started empty"
                default: "left it in place and will not write it this run"
                }
            let reason = error as NSError
            DiagnosticLog.agents.error(
                "\(name) could not be read (\(reason.domain) \(reason.code)); \(kept)."
            )
            return (nil, failure)
        }
    }

    /// Moves an unreadable `file` to a dated name beside it.
    private nonisolated static func setAside(_ file: URL) -> Failure {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        let stamp = formatter.string(from: .now)
        let stem = file.deletingPathExtension().lastPathComponent
        let fileExtension = file.pathExtension
        for attempt in 1...9 {
            let suffix = attempt == 1 ? stamp : "\(stamp)-\(attempt)"
            let kept = file.deletingLastPathComponent()
                .appendingPathComponent("\(stem).unreadable-\(suffix)", isDirectory: false)
                .appendingPathExtension(fileExtension)
            guard !FileManager.default.fileExists(atPath: kept.path) else { continue }
            do {
                try FileManager.default.moveItem(at: file, to: kept)
                return .unreadable(keptAt: kept)
            } catch {
                return .unreadableAndUnmoved
            }
        }
        return .unreadableAndUnmoved
    }

    // MARK: - Actions - Saving

    /// Writes a moment after the latest change, so several changes write once.
    func scheduleSave() {
        guard file != nil else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes a change still waiting, and waits for the disk, as before the
    /// app quits.
    func flush() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        save()
        queue.sync {}
    }

    private func save() {
        pendingSave = nil
        guard isLoaded, isWritable, let file, let value = snapshot?() else { return }
        let name = name
        queue.async {
            Self.write(value, to: file, named: name)
        }
    }

    private nonisolated static func write(_ value: Value, to file: URL, named name: String) {
        do {
            let data = try JSONEncoder().encode(value)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            let reason = error as NSError
            DiagnosticLog.agents.error(
                "\(name) could not be saved (\(Failure.unwritable), \(reason.domain) \(reason.code))."
            )
        }
    }
}
