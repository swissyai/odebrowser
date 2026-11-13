import Foundation

/// Where the crash and hang reports come from: the launch record's launches
/// that never finished or never quit cleanly, the crash reports macOS keeps
/// for Ode and its helpers, read and never changed, and the long hangs the
/// watchdog logged. Each reader picks only what a fix needs.
enum BrowserCrashReportReaders {
    // MARK: - Static Variables

    /// How far back the readers look.
    static let window: TimeInterval = 30 * 24 * 60 * 60
    /// Where macOS keeps the person's crash reports.
    static var diagnosticReports: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Logs/DiagnosticReports", isDirectory: true)
    }

    // MARK: - Actions - Launch record

    /// The launches in `history` other than `current` that never finished
    /// starting or ended without a quit the person asked for.
    static func launches(in history: BrowserLaunchHistory, current: UUID?, now: Date) -> [BrowserCrashReport] {
        history.launches.compactMap { launch in
            guard launch.id != current, launch.outcome != .clean,
                now.timeIntervalSince(launch.startedAt) <= window
            else { return nil }
            let started = launch.outcome == .started
            var details = [
                "Started: \(launch.startedAt.ISO8601Format())",
                "Finished starting: \(started ? "no" : "yes")",
                "Safe mode: \(launch.safeMode ? "yes" : "no")",
            ]
            if let finishedAt = launch.finishedAt { details.append("Finished starting at: \(finishedAt.ISO8601Format())") }
            return BrowserCrashReport(
                id: "launch-\(launch.id.uuidString)", kind: started ? .unfinishedStart : .unexpectedQuit,
                occurredAt: launch.startedAt, build: launch.build,
                summary: started ? "The launch did not finish starting" : "The launch ended without a quit",
                details: details.joined(separator: "\n"))
        }
    }

    // MARK: - Actions - Hang log

    /// The long hangs in `log`.
    static func hangs(in log: BrowserHangLog, build: String, now: Date) -> [BrowserCrashReport] {
        log.long.compactMap { hang in
            guard now.timeIntervalSince(hang.at) <= window else { return nil }
            let seconds = String(format: "%.1f", hang.seconds)
            return BrowserCrashReport(
                id: "hang-\(hang.at.ISO8601Format())", kind: .hang, occurredAt: hang.at, build: build,
                summary: "The main thread did not respond for \(seconds) s",
                details: "Duration: \(seconds) s\nStarted: \(hang.at.ISO8601Format())")
        }
    }

    // MARK: - Actions - macOS crash reports

    /// The crash reports in `directory` that macOS wrote for this copy of
    /// Ode or one of its helpers within ``window``, newest first. `belongs`
    /// decides from a report's bundle identifier, process name and executable
    /// path whether it is this copy's.
    static func crashes(
        in directory: URL = diagnosticReports, now: Date,
        belongs: (_ bundleID: String?, _ name: String?, _ path: String?) -> Bool = {
            isOde(bundleID: $0, name: $1, path: $2)
        }
    ) -> [BrowserCrashReport] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        return files.filter { $0.pathExtension == "ips" }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                let modified = values.contentModificationDate, now.timeIntervalSince(modified) <= window,
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else { return nil }
            return crash(fromIPS: data, named: url.lastPathComponent, modified: modified, belongs: belongs)
        }
        .sorted { $0.occurredAt > $1.occurredAt }
    }

    /// Whether a crash report is this copy of Ode's: its bundle identifier is
    /// the app's own or a helper's, and the process ran from inside the app's
    /// bundle. A report from any other copy, such as a development build or a
    /// test host, is never listed, even under the same name. `app` and
    /// `appPath` name the copy asking.
    static func isOde(
        bundleID: String?, name: String?, path: String?,
        app: String? = Bundle.main.bundleIdentifier, appPath: String = Bundle.main.bundlePath
    ) -> Bool {
        if let path, !ran(from: path, insideBundleAt: appPath) { return false }
        if let bundleID { return ProductIdentity.owns(bundleIdentifier: bundleID, app: app) }
        guard let name else { return false }
        return name == "Ode" || name.hasPrefix("Ode Helper") || name == "OdeNativeCore"
    }

    /// Whether a report's executable `path` lies inside the app at
    /// `appPath`. macOS writes the path anonymized: the home folder's owner
    /// as `USER`, a volume's name as `VOLUME`, and some folders as `*`, so the
    /// bundle the path names is matched with those as wildcards.
    static func ran(from path: String, insideBundleAt appPath: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let bundleEnd = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return false }
        let app = appPath.hasSuffix("/") ? String(appPath.dropLast()) : appPath
        let bundle = components[...bundleEnd]
        if bundle.joined(separator: "/") == app { return true }
        let pattern = bundle.indices.map { index -> String in
            let component = bundle[index]
            let parent = index > bundle.startIndex ? bundle[index - 1] : ""
            if component == "*" { return ".+" }
            if (parent, component) == ("Users", "USER") || (parent, component) == ("Volumes", "VOLUME") {
                return "[^/]+"
            }
            return NSRegularExpression.escapedPattern(for: component)
        }
        return app.range(of: "^" + pattern.joined(separator: "/") + "$", options: .regularExpression) != nil
    }

    /// A report from one `.ips` file: a JSON header line, then the crash as
    /// JSON. Answers nil for a file that is not a crash of this copy's.
    static func crash(
        fromIPS data: Data, named name: String, modified: Date,
        belongs: (_ bundleID: String?, _ name: String?, _ path: String?) -> Bool = {
            isOde(bundleID: $0, name: $1, path: $2)
        }
    ) -> BrowserCrashReport? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
            let header = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any]
        else { return nil }
        let bundleID = header["bundleID"] as? String
        let process = header["app_name"] as? String ?? header["name"] as? String
        // The header rules most reports out before the larger body is read.
        guard belongs(bundleID, process, nil) else { return nil }
        let body = try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...]) as? [String: Any]
        guard belongs(bundleID, process, body?["procPath"] as? String) else { return nil }
        let build = [header["app_version"] as? String, (header["build_version"] as? String).map { "(\($0))" }]
            .compactMap { $0 }.joined(separator: " ")
        guard let body else {
            return BrowserCrashReport(
                id: "ips-\(name)", kind: .crash, occurredAt: modified, build: build.isEmpty ? "unknown" : build,
                summary: "\(process ?? "Ode") crashed", details: "Process: \(process ?? "unknown")")
        }
        var lines = ["Process: \(body["procName"] as? String ?? process ?? "unknown")"]
        var summary = "\(process ?? "Ode") crashed"
        if let exception = body["exception"] as? [String: Any] {
            let type = exception["type"] as? String ?? "unknown"
            let signal = exception["signal"] as? String
            lines.append("Exception: \(type)\(signal.map { " (\($0))" } ?? "")")
            summary = "\(type) in \(process ?? "Ode")"
        }
        if let termination = body["termination"] as? [String: Any], let indicator = termination["indicator"] as? String {
            lines.append("Termination: \(indicator)")
        }
        let images = body["usedImages"] as? [[String: Any]] ?? []
        if let threads = body["threads"] as? [[String: Any]] {
            let faulting = body["faultingThread"] as? Int ?? threads.firstIndex { ($0["triggered"] as? Bool) == true } ?? 0
            if threads.indices.contains(faulting), let frames = threads[faulting]["frames"] as? [[String: Any]] {
                lines.append("Thread \(faulting) stack:")
                for (index, frame) in frames.prefix(24).enumerated() {
                    let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil }
                    let imageName = image?["name"] as? String ?? "?"
                    let offset = frame["imageOffset"] as? Int ?? 0
                    let symbol = (frame["symbol"] as? String).map { " \($0)" } ?? ""
                    lines.append("  \(index) \(imageName) +\(offset)\(symbol)")
                }
            }
        }
        // The images the stack names, by identity, so the offsets can be symbolicated.
        let named = Set(lines.compactMap { $0.split(separator: " ").dropFirst(1).first.map(String.init) })
        for image in images {
            guard let imageName = image["name"] as? String, named.contains(imageName), let uuid = image["uuid"] as? String
            else { continue }
            lines.append("Image \(imageName) \(uuid)")
        }
        return BrowserCrashReport(
            id: "ips-\(name)", kind: .crash, occurredAt: modified, build: build.isEmpty ? "unknown" : build,
            summary: summary, details: lines.joined(separator: "\n"))
    }
}
