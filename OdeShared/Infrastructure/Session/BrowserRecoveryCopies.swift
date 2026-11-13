import Foundation

/// The dated copies of the session a restore can return to, as the core lists
/// them beside the session file, and the restores that return to one. The
/// core reads only the folder of copies to list them, so the list can be
/// shown whether or not a core has the session open; a restore needs the
/// session closed, so a running app asks for one at its next launch.
enum BrowserRecoveryCopies {
    // MARK: - Static Variables

    /// The request a running app leaves beside the session for its next
    /// launch: the name of the copy to restore before the session opens.
    static let requestFileName = "restore-request"

    // MARK: - Actions - Reading

    /// The copies kept beside the session in `directory`, newest first; none
    /// when the folder cannot be read.
    static func list(in directory: URL) -> [RecoveryCopy] {
        (try? OdeCore.answer(RecoveryCopiesIn(storageDirectory: directory.path)).copies) ?? []
    }

    // MARK: - Actions - Restoring

    /// Puts `copy` in place of the session in `directory`, which no core may
    /// have open. The core keeps the session it replaces as a copy first, so
    /// the restore can be undone from the same list. Throws the rejection
    /// naming why it could not; the session is unchanged then.
    static func restore(_ copy: RecoveryCopy, in directory: URL) throws(Rejection) {
        try OdeCore.restoreRecoveryCheckpoint(
            configuration: AppConfiguration(storageDirectory: directory.path, restoreFrom: copy.name))
    }

    /// Asks the next launch to restore `copy` before it opens the session in
    /// `directory`. Answers false when the request could not be written.
    @discardableResult
    static func requestRestore(
        _ copy: RecoveryCopy, in directory: URL, files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk()
    ) -> Bool {
        do {
            try files.writeDurably(Data(copy.name.utf8), to: directory.appendingPathComponent(requestFileName))
            return true
        } catch {
            DiagnosticLog.launch.notice("The restore request could not be saved: \(DiagnosticLog.describe(error))")
            return false
        }
    }

    /// The copy a running app asked this launch to restore, which taking
    /// removes, so a launch that fails while restoring never repeats it.
    static func takeRequest(in directory: URL) -> String? {
        let url = directory.appendingPathComponent(requestFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

extension RecoveryCopy: Identifiable {
    var id: String { name }

    /// Why the copy was kept, as the restore list says it.
    var reason: String {
        if held { return String(localized: "Kept back when tabs went missing") }
        if let updateTo { return String(localized: "Before updating to \(updateTo)") }
        if beforeRestore { return String(localized: "Before a restore") }
        return String(localized: "When Ode started")
    }

    /// What the copy holds, as the restore list says it.
    var contents: String {
        let spaces = spaces == 1 ? String(localized: "1 Space") : String(localized: "\(spaces) Spaces")
        let tabs = tabs == 1 ? String(localized: "1 tab") : String(localized: "\(tabs) tabs")
        return [spaces, tabs].formatted(.list(type: .and))
    }

    /// When the copy was taken, as the restore list says it.
    var taken: String {
        takenAt.formatted(date: .abbreviated, time: .shortened)
    }
}
