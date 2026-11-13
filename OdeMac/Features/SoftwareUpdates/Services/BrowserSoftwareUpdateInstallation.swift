import Foundation
import Security

/// The copy of Ode that is running, as going back to an earlier version sees
/// it: where it is installed, who signed it, and what its data needs. It
/// checks a candidate earlier version against itself, and replaces itself
/// with that version once Ode has quit.
struct BrowserSoftwareUpdateInstallation: Sendable {
    // MARK: - Types

    struct Failure: LocalizedError, Equatable {
        let errorDescription: String?

        init(_ description: String) {
            errorDescription = description
        }
    }

    // MARK: - Static Variables

    /// The Info.plist keys naming the newest session storage and sync
    /// journal versions a build reads. Builds without them read version 1.
    static let sessionStorageVersionKey = "OdeSessionStorageVersion"
    static let sessionJournalVersionKey = "OdeSessionJournalVersion"
    static let engineVersionKey = "OdeChromiumEngineVersion"

    /// How long the replacement waits for Ode to quit before giving up, in
    /// seconds.
    static let patience = 120

    /// Swaps the installed bundle for the staged one once Ode's process has
    /// gone, keeping the installed one until the swap succeeded, then opens
    /// Ode. Paths arrive as arguments, never inside the script.
    static let replacementScript = """
        pid="$1"; installed="$2"; staged="$3"; previous="$4"; reopen="$5"; patience="$6"
        i=0
        while /bin/kill -0 "$pid" 2>/dev/null; do
          i=$((i + 1)); [ "$i" -gt "$patience" ] && exit 1
          /bin/sleep 0.2
        done
        status=1
        if /bin/mv "$installed" "$previous"; then
          if /bin/mv "$staged" "$installed"; then
            /bin/rm -rf -- "${previous:?}"
            status=0
          else
            /bin/mv "$previous" "$installed"
          fi
        fi
        [ "$reopen" = reopen ] && /usr/bin/open "$installed"
        exit "$status"
        """

    // MARK: - Variables

    let bundleURL: URL
    let bundleIdentifier: String
    let version: String
    let build: String
    /// The Developer ID team that signed this copy, or nil for an unsigned
    /// or ad hoc build, which cannot verify an earlier version.
    let team: String?
    /// The session storage and journal versions this build reads.
    let sessionVersions: [String: Int]
    /// The Chromium engine version this build carries, when it has one.
    let engineVersion: String?

    // MARK: - Initializers

    init(bundle: Bundle = .main, team: String? = Self.runningTeam()) {
        let info = bundle.infoDictionary ?? [:]
        self.init(
            bundleURL: bundle.bundleURL, bundleIdentifier: bundle.bundleIdentifier ?? "",
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "", team: team,
            sessionVersions: Dictionary(
                uniqueKeysWithValues: [Self.sessionStorageVersionKey, Self.sessionJournalVersionKey].map {
                    ($0, Self.number(info[$0]))
                }),
            engineVersion: info[Self.engineVersionKey] as? String)
    }

    init(
        bundleURL: URL, bundleIdentifier: String, version: String, build: String, team: String?,
        sessionVersions: [String: Int], engineVersion: String?
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.team = team
        self.sessionVersions = sessionVersions
        self.engineVersion = engineVersion
    }

    // MARK: - Actions - Availability

    /// Why this copy cannot go back to an earlier version, or nil when it can.
    var unavailableReason: String? {
        guard team != nil else {
            return String(localized: "Going back to an earlier version needs a copy of Ode signed for release.")
        }
        guard !bundleURL.path.contains("/AppTranslocation/") else {
            return String(localized: "Move Ode to the Applications folder to go back to an earlier version.")
        }
        let folder = bundleURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: folder),
            FileManager.default.isWritableFile(atPath: bundleURL.path)
        else {
            return String(
                localized: "Ode can't replace itself in \(folder). Install it where your account can change it.")
        }
        return nil
    }

    // MARK: - Actions - Verifying

    /// Checks `app` is `release` of this Ode: the same bundle identifier,
    /// signed by the same Developer ID team, notarized, valid in every
    /// architecture and nested bundle, and the build the feed named.
    func verify(_ app: URL, isRelease release: BrowserSoftwareUpdateRelease) throws {
        guard let team else { throw Failure(String(localized: "This copy of Ode is not signed for release.")) }
        let candidate = Bundle(url: app)?.infoDictionary ?? [:]
        guard candidate["CFBundleIdentifier"] as? String == bundleIdentifier,
            candidate["CFBundleVersion"] as? String == release.build
        else {
            throw Failure(String(localized: "The download is not Ode \(release.version)."))
        }
        let requirementText =
            "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(team)\" and notarized"
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else {
            throw Failure(String(localized: "Ode \(release.version) could not be checked."))
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        var errors: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &errors) == errSecSuccess else {
            throw Failure(
                String(
                    localized:
                        "Ode \(release.version) is not signed and notarized like this copy, so Ode won't install it.")
            )
        }
    }

    /// What `earlier`, the Info.plist of an earlier version, cannot keep from
    /// this one. Nothing is deleted either way; the warnings say what waits
    /// until the person updates again.
    func warnings(goingBackTo earlier: [String: Any], version earlierVersion: String) -> [String] {
        var warnings: [String] = []
        if sessionVersions.contains(where: { key, current in Self.number(earlier[key]) < current }) {
            warnings.append(
                String(
                    localized:
                        "Ode \(earlierVersion) can't open the Spaces and tabs this version saved. It will ask you to update before it opens them. Nothing is deleted."
                ))
        }
        if let current = Self.majorVersion(engineVersion),
            let older = Self.majorVersion(earlier[Self.engineVersionKey]), older < current
        {
            warnings.append(
                String(
                    localized:
                        "Ode \(earlierVersion) uses an older web engine. Some sites may sign you out until you update again."
                ))
        }
        return warnings
    }

    // MARK: - Actions - Replacing

    /// Hands the swap to a process that outlives Ode: once `pid` has exited,
    /// `staged` takes the installed bundle's place and Ode opens again. The
    /// installed bundle is kept until the swap succeeded, and comes back if
    /// it fails.
    func replace(with staged: URL, afterExitOf pid: Int32, reopen: Bool = true) throws -> Process {
        let previous = staged.deletingLastPathComponent()
            .appendingPathComponent("Previous-\(UUID().uuidString).app", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", Self.replacementScript, "ode-go-back", String(pid), bundleURL.path, staged.path, previous.path,
            reopen ? "reopen" : "stay", String(Self.patience * 5),
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    // MARK: - Actions - Signing

    /// The team that signed the running process, read from its signature.
    static func runningTeam() -> String? {
        var running: SecCode?
        var code: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
            SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code,
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func number(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? String).flatMap(Int.init) ?? 1
    }

    private static func majorVersion(_ value: Any?) -> Int? {
        (value as? String)?.split(separator: ".").first.flatMap { Int($0) }
    }
}
