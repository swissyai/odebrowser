import Foundation
import Observation
import os

/// Ode's downloads for one browsing mode: the core's download records, the
/// feedback they present, and native data saves. Every record change is an
/// intent sent to the core; engines report their own downloads to the core,
/// which records them and hands the person's row actions back to the engine.
@Observable
@MainActor
final class BrowserDownloadCenter: NSObject {
    // MARK: - Types

    /// Asks the person to approve a risky download: its assessment, source,
    /// Space name and profile.
    typealias RiskApprovalHandler =
        @MainActor (
            DownloadRiskAssessment,
            URL?,
            String,
            UUID
        ) async -> Bool

    typealias DownloadDestinationChooser =
        @MainActor (
            String,
            UUID,
            Bool
        ) async -> any BrowserPlatformDownloadResolution

    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.odebrowser.ode", category: "Downloads")

    /// The core whose read model holds the download records. Views observe
    /// its records directly.
    let core: OdeCore
    private(set) var feedbackEvents: [BrowserDownloadFeedbackEvent] = []

    var items: [DownloadState] {
        core.state.downloads
    }

    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let approveRiskyDownload: RiskApprovalHandler
    @ObservationIgnored let resolveDownloadDestination: DownloadDestinationChooser
    @ObservationIgnored private var feedbackExpirationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var dataSaveAssignments: [UUID: BrowserSpaceRuntimeAssignment] = [:]
    /// When each record this center saw end did so, which the core does not
    /// keep: a finished file stays among the sidebar's recent downloads for a
    /// while after it finished, however long it took.
    @ObservationIgnored private var endTimes: [UUID: Date] = [:]

    // MARK: - Initializers

    init(
        core: OdeCore = OdeCore(),
        approveRiskyDownload: @escaping RiskApprovalHandler = { _, _, _, _ in false },
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        resolveDownloadDestination:
            @escaping DownloadDestinationChooser = {
                suggestedFilename,
                spaceID,
                forcesPrompt in
                await BrowserPlatformDownloadDirectory.resolve(
                    suggestedFilename: suggestedFilename,
                    spaceID: spaceID,
                    forcesPrompt: forcesPrompt
                )
            }
    ) {
        self.core = core
        self.approveRiskyDownload = approveRiskyDownload
        self.permissionCenter = permissionCenter
        self.resolveDownloadDestination = resolveDownloadDestination
        super.init()
        core.followDownloads(self) { [weak self] download in
            self?.noteEnd(of: download)
        }
    }

    // MARK: - Actions - Records

    func items(for profileID: UUID) -> [DownloadState] {
        items.filter { $0.profileID == profileID }
    }

    func unacknowledgedItems(for profileID: UUID) -> [DownloadState] {
        items.filter { $0.profileID == profileID && !$0.isAcknowledged }
    }

    func item(_ itemID: UUID) -> DownloadState? {
        items.first { $0.id == itemID }
    }

    /// When download `itemID` ended, if this center saw it end.
    func endTime(of itemID: UUID) -> Date? {
        endTimes[itemID]
    }

    /// Records the moment a record leaves its live phases, and forgets it
    /// when a retry or a recovery starts the record again.
    private func noteEnd(of download: DownloadState, at now: Date = .now) {
        if download.phase.isLive {
            endTimes.removeValue(forKey: download.id)
        } else if endTimes[download.id] == nil {
            endTimes[download.id] = now
        }
    }

    /// Sends one download intent. A refused intent changes nothing; the rule
    /// it broke is logged, since it means an engine reported something the
    /// core cannot record.
    func send(_ intent: some Intent) {
        do {
            try core.send(intent)
        } catch {
            Self.logger.error(
                "The core refused \(String(describing: type(of: intent)), privacy: .public): \(DiagnosticLog.describe(error), privacy: .public)"
            )
        }
    }

    /// Begins a new record and returns its identity.
    func begin(profileID: UUID, filename: String, createdAt: Date = .now, isAcknowledged: Bool = false) -> UUID {
        let itemID = UUID()
        send(
            BeginDownload(
                downloadID: itemID, profileID: profileID, filename: filename, createdAt: createdAt,
                isAcknowledged: isAcknowledged))
        return itemID
    }

    /// The destination names the file, so the record's filename follows it.
    func setDestination(_ destination: URL, for itemID: UUID) {
        send(
            SetDownloadDestination(
                downloadID: itemID, destination: destination.absoluteString, filename: destination.lastPathComponent))
    }

    /// The core's risk verdict for a download. A download the core cannot
    /// judge asks the person first rather than passing as safe.
    func riskVerdict(suggestedFilename: String, mimeType: String?, isUserInitiated: Bool) -> DownloadRiskVerdict {
        let facts = DownloadRiskFacts(suggestedFilename: suggestedFilename, mimeType: mimeType)
        do {
            return try core.query(DownloadRisk(facts: facts, isUserInitiated: isUserInitiated))
        } catch {
            return DownloadRiskVerdict(
                assessment: DownloadRiskAssessment(sanitizedFilename: facts.sanitizedFilename, reasons: []),
                requiresConfirmation: true)
        }
    }

    @discardableResult
    func acknowledgeItems(for profileID: UUID) -> Int {
        (try? core.send(AcknowledgeDownloads(profileID: profileID)))?.count ?? 0
    }

    /// Cancels a live download. The core cancels one an engine runs on its
    /// engine too.
    func cancel(_ itemID: UUID) {
        dataSaveAssignments.removeValue(forKey: itemID)
        if item(itemID)?.phase.isLive == true { send(CancelDownload(downloadID: itemID, message: "Canceled.")) }
    }

    func pause(_ itemID: UUID) {
        guard item(itemID)?.canPause == true else { return }
        send(PauseDownload(downloadID: itemID))
    }

    func resume(_ itemID: UUID) {
        guard item(itemID)?.canResume == true else { return }
        send(ResumeDownload(downloadID: itemID))
    }

    /// Clears a record whose download ended. One an engine ran also leaves the
    /// engine's own list.
    func clear(_ itemID: UUID) {
        guard item(itemID)?.phase.isLive != true, dataSaveAssignments[itemID] == nil else { return }
        send(RemoveDownload(downloadID: itemID))
        endTimes.removeValue(forKey: itemID)
    }

    /// Whether Clear Downloads drops `item`: a finished, canceled or failed
    /// record. A download still running, or one blocked until the person
    /// allows it, stays.
    nonisolated static func isClearable(_ item: DownloadState) -> Bool {
        !item.phase.isLive && !item.phase.awaitsDecision
    }

    /// Clears every record of `profileID` that `isClearable` allows, and
    /// answers how many went. Files already written stay on disk.
    @discardableResult
    func clearEnded(for profileID: UUID) -> Int {
        let ended = items(for: profileID).filter { Self.isClearable($0) && dataSaveAssignments[$0.id] == nil }
        for item in ended { clear(item.id) }
        return ended.count
    }

    /// Moves a finished download's file to the Trash, then clears its record.
    /// A file already gone only leaves the list; one the Trash refuses stays,
    /// and so does its record.
    @discardableResult
    func moveToTrash(
        _ itemID: UUID,
        trashItem: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> Bool {
        guard let item = item(itemID), item.phase.isComplete else { return false }
        if let fileURL = item.savedFileURL() {
            do {
                try trashItem(fileURL)
            } catch {
                Self.logger.error(
                    "A finished download could not be moved to the Trash: \(DiagnosticLog.describe(error), privacy: .public)"
                )
                return false
            }
        }
        clear(itemID)
        return true
    }

    /// Deletes the records of the Space `deletion` names. The core cancels and
    /// removes the downloads still running in each profile it erases; a
    /// profile a Space that stays browses with keeps its list.
    func deleteRecords(of deletion: SpaceDeletionState) {
        dataSaveAssignments = dataSaveAssignments.filter { $0.value.spaceID != deletion.spaceID }
        for profileID in deletion.erasing { send(RemoveProfileDownloads(profileID: profileID)) }
    }

    /// Deletes a Space's records. The core cancels and removes the downloads
    /// its profile's engines still run.
    func deleteRecords(profileID: UUID, spaceID: UUID) {
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
        dataSaveAssignments = dataSaveAssignments.filter { $0.value != assignment }
        send(RemoveProfileDownloads(profileID: profileID))
    }

    /// Retries a download the site's choices blocked, while its Space is
    /// still there to hold it: the core has its engine replay it.
    @discardableResult
    func retryAutomaticDownload(
        _ itemID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isAssignmentAvailable: @MainActor (BrowserSpaceRuntimeAssignment) -> Bool
    ) -> Bool {
        guard let item = item(itemID), item.profileID == assignment.profileID, item.phase.canRetry,
            isAssignmentAvailable(assignment)
        else { return false }
        send(RestartDownload(downloadID: itemID))
        return true
    }

    // MARK: - Actions - Native data saves

    /// Saves bytes supplied by a trusted native user action, such as WebKit's
    /// PDF toolbar. No network request or automatic-download permission is
    /// involved, but destination consent and file safeguards still apply.
    @discardableResult
    func saveData(
        _ data: Data,
        suggestedFilename: String,
        mimeType: String,
        originatingURL: URL,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String,
        feedbackSource: BrowserDownloadFeedbackSource? = nil
    ) async -> UUID {
        let verdict = riskVerdict(suggestedFilename: suggestedFilename, mimeType: mimeType, isUserInitiated: true)
        let assessment = verdict.assessment
        let itemID = begin(profileID: assignment.profileID, filename: assessment.sanitizedFilename)
        send(AssessDownloadRisk(downloadID: itemID, assessment: assessment))
        dataSaveAssignments[itemID] = assignment
        if let feedbackSource {
            presentFeedback(
                BrowserDownloadFeedbackEvent(
                    id: itemID, profileID: assignment.profileID, spaceID: assignment.spaceID,
                    filename: assessment.sanitizedFilename, source: feedbackSource))
        }
        await finishSavingData(
            data, itemID: itemID, verdict: verdict, originatingURL: originatingURL,
            assignment: assignment, spaceName: spaceName)
        return itemID
    }

    private func finishSavingData(
        _ data: Data,
        itemID: UUID,
        verdict: DownloadRiskVerdict,
        originatingURL: URL,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String
    ) async {
        defer { dataSaveAssignments.removeValue(forKey: itemID) }
        guard dataSaveAssignments[itemID] == assignment else { return }
        let assessment = verdict.assessment
        if verdict.requiresConfirmation {
            let approved = await approveRiskyDownload(assessment, originatingURL, spaceName, assignment.profileID)
            guard dataSaveAssignments[itemID] == assignment else { return }
            guard approved else {
                send(
                    CancelDownload(
                        downloadID: itemID, message: "Canceled before downloading a potentially dangerous file."))
                return
            }
        }
        let resolution = await resolveDownloadDestination(assessment.sanitizedFilename, assignment.spaceID, false)
        // Cancellation or removal of the owning Space can happen while a
        // native panel is open. A late response must never resurrect the save.
        guard dataSaveAssignments[itemID] == assignment else { return }
        resolution.save(data, as: itemID, from: originatingURL, in: self)
    }

    /// Writes `data` to `destination` through Ode's staging folder, with
    /// the quarantine of the page it came from.
    func saveDataToDestination(
        _ data: Data, itemID: UUID, destination: URL, originatingURL: URL
    ) throws {
        let fileManager = FileManager.default
        let stagingDirectory = try BrowserDownloadTransfer.stagingDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = BrowserDownloadTransfer.stagingURL(
            itemID: itemID, suggestedFilename: destination.lastPathComponent, directory: stagingDirectory)
        defer { try? fileManager.removeItem(at: staging) }
        setDestination(destination, for: itemID)
        try data.write(to: staging, options: .atomic)
        try BrowserDownloadTransfer.finish(
            from: staging, to: destination, quarantine: BrowserDownloadQuarantine(sourceURL: originatingURL))
    }

    // MARK: - Actions - Feedback

    func dismissFeedback(_ eventID: UUID) {
        feedbackEvents.removeAll { $0.id == eventID }
        feedbackExpirationTasks.removeValue(forKey: eventID)?.cancel()
    }

    /// Shows a download leaving where it started. Every window over the page
    /// hears its start, so an event already shown is shown once.
    func presentFeedback(_ event: BrowserDownloadFeedbackEvent) {
        guard !feedbackEvents.contains(where: { $0.id == event.id }) else { return }
        let previousIDs = Set(feedbackEvents.map(\.id))
        feedbackEvents = event.appended(to: feedbackEvents)
        let retainedIDs = Set(feedbackEvents.map(\.id))
        for removedID in previousIDs.subtracting(retainedIDs) {
            feedbackExpirationTasks.removeValue(forKey: removedID)?.cancel()
        }
        feedbackExpirationTasks[event.id]?.cancel()
        feedbackExpirationTasks[event.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserDownloadFeedbackEvent.lifetime)
            guard !Task.isCancelled else { return }
            self?.dismissFeedback(event.id)
        }
    }
}
