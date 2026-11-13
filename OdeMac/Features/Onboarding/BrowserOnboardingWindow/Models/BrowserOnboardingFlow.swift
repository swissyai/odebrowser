import AppKit
import Foundation
import Observation

/// The Mac's side of setup. The core holds setup itself: the step and where
/// Back leads, the browsers chosen and the queue of them, the review of the
/// one it is on, the manual setup, and what finishing does. This finds the
/// browsers installed here, holds access to their data folders, reads the
/// browser the core is on, imports the review's passwords and finishes setup,
/// telling the core how each went.
@Observable
@MainActor
final class BrowserOnboardingFlow {
    // MARK: - Variables

    let browser: BrowserStore
    /// The manual setup the core holds, which the manual-setup step edits.
    let manualSetup: BrowserManualSetupModel

    private(set) var request: BrowserOnboardingRequest
    private(set) var installedSources: [BrowserInstalledImportSource] = []
    /// The browsers setup found by looking, once the person asked it to scan.
    private(set) var unlistedSources: [BrowserInstalledImportSource] = []
    /// Whether the person asked setup to scan the browsers' data. Until then
    /// setup reads only the browser the person chooses, when they go on.
    private(set) var hasScanned = false
    /// The found browser `ImportSource.otherChromium` imports, by its app.
    private(set) var chosenUnlistedSourceURL: URL?
    private(set) var isChoosingDataAccess = false
    private(set) var isCompletingSetup = false
    var completionFailure: String?
    /// The icons the extensions the browsers read offer wear, by identifier.
    private(set) var extensionIcons: [String: NSImage] = [:]
    /// The icons the browsers read kept for the pages of the tabs their
    /// Spaces bring, by page address.
    @ObservationIgnored private var siteIcons: [String: Data] = [:]
    /// Why the reviewed browser's passwords were left out of the review,
    /// when they could not be read; everything else still comes over.
    private(set) var passwordReadFailure: BrowserPasswordImportError?
    private(set) var bringsPasswords = true
    private(set) var bringsSignIns = true
    private(set) var importOutcomes: [SetupImportOutcome] = []
    private(set) var outcomeReadFailure: String?
    @ObservationIgnored private var passwordSelectionBeforeDisabling: Set<UUID>?
    /// Whether setup shows the page that explains, before macOS asks, why
    /// Ode needs the browser's Keychain key.
    private(set) var isExplainingKeychain = false
    /// Whether macOS refused the key the last time it asked.
    private(set) var keychainWasRefused = false
    /// Whether the empty Spaces of the review show, folded away until asked.
    var showsEmptyReviewSpaces = false
    /// The stage the import plays on while it runs, and for a moment after.
    private(set) var importStage: BrowserOnboardingImportStage?

    @ObservationIgnored private let sourceDiscovery: any BrowserInstalledImportSourceDiscovering
    @ObservationIgnored private let dataAccessProvider: any BrowserOnboardingDataAccessProviding
    @ObservationIgnored private let importCommitter: any BrowserOnboardingImportCommitting
    @ObservationIgnored private let importReadCoordinator: BrowserOnboardingImportReadCoordinator
    /// What installs the extensions an import brings, when the engine runs any.
    @ObservationIgnored private let extensionInstaller: (any BrowserImportedExtensionInstalling)?
    /// The data of the browser being read, which its passwords come from.
    @ObservationIgnored private var currentImportPayload: BrowserDetectedImportPayload?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var finalizationTask: Task<Result<BrowserOnboardingImportResult, any Error>, Never>?
    @ObservationIgnored private var pendingResetRequest: BrowserOnboardingRequest?
    /// The review's Spaces as the views draw them, for the choices the core
    /// last published, so a view's body builds them once per change. Showing
    /// another Space changes no choice, so moving through the review builds
    /// nothing again.
    @ObservationIgnored private var reviewCache: (choices: [SetupReviewSpace], spaces: [BrowserImportSpaceReview])?
    /// The session the review would leave, until its choices change.
    @ObservationIgnored private var previewCache: (choices: [SetupReviewSpace], session: BrowserSessionPreview?)?
    @ObservationIgnored private var operationGeneration = 0

    /// Setup as the core holds it, or nil before it opens.
    var state: SetupFlowState? { browser.core.state.setupFlow }

    var step: SetupStep { state?.step ?? request.entryPoint.firstStep }
    /// The look the Spaces setup makes wear, which the stage and every
    /// preview follow.
    var look: SetupLook { state?.look ?? .heraldic }
    var failure: SetupFailure? { state?.failure }
    var review: SetupImportReview? { state?.review }
    var selectedImportApplications: Set<ImportSource> { Set(state?.selected ?? []) }

    var isReading: Bool { importReadCoordinator.isInFlight }
    var isCommittingImport: Bool { state?.phase == .committing }

    var isImportSelectionLocked: Bool {
        isReading || isChoosingDataAccess || isCommittingImport || isCompletingSetup
    }

    var supportsSignIns: Bool { importCommitter.supportsSignIns }

    /// Arc sign-ins can only be copied into a newly imported Space.
    var supportsSignInCarry: Bool {
        supportsSignIns && review?.source == .arc
            && review?.spaces.contains { $0.included && $0.destinationID == nil && $0.sourceProfilePath != nil } == true
    }

    /// The review's Spaces as the review views draw them: those holding the
    /// most first, keeping the browser's order among equals, then the empty
    /// ones, which show only when the person unfolds them.
    var reviewSpaces: [BrowserImportSpaceReview] {
        let ordered = orderedReviewSpaces
        return showsEmptyReviewSpaces ? ordered : ordered.filter { !$0.isEmpty }
    }

    /// The review's Spaces that hold nothing.
    var emptyReviewSpaceCount: Int { orderedReviewSpaces.count { $0.isEmpty } }

    private var orderedReviewSpaces: [BrowserImportSpaceReview] {
        guard let review else { return [] }
        if let reviewCache, reviewCache.choices == review.spaces { return reviewCache.spaces }
        let spaces = review.spaces.map(BrowserImportSpaceReview.init).enumerated()
            .sorted { lhs, rhs in
                lhs.element.contentCount != rhs.element.contentCount
                    ? lhs.element.contentCount > rhs.element.contentCount : lhs.offset < rhs.offset
            }
            .map(\.element)
        reviewCache = (review.spaces, spaces)
        return spaces
    }

    /// The Space after `spaceID` in the order the review shows them.
    func reviewSpace(after spaceID: UUID?) -> UUID? {
        let spaces = reviewSpaces
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }), index + 1 < spaces.count else { return nil }
        return spaces[index + 1].id
    }

    /// The Space the person is looking at in the review.
    var shownReviewSpaceID: UUID? {
        get { review?.shownSpaceID }
        set {
            guard let newValue, newValue != review?.shownSpaceID else { return }
            send(ShowImportSpace(sourceSpaceID: newValue))
        }
    }

    var completionSummary: [LocalizedStringResource] {
        state?.summary.map(BrowserOnboardingSummary.completed) ?? []
    }

    /// What the review's last Space offers: importing and going on to the
    /// next chosen browser, or importing alone.
    var importReviewActionTitle: LocalizedStringResource {
        state?.queue?.hasMoreAfterCurrent == true
            ? LocalizedStringResource(
                "Import & Continue",
                comment: "Button that imports the current browser and continues to the next selected browser.")
            : LocalizedStringResource(
                "Import", comment: "Button that imports the reviewed data from the final browser.")
    }

    // MARK: - Initializers

    /// A flow for `request` over `browser`'s workspace. It sends the core
    /// nothing until `start`, since a view may build it more than once.
    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        sourceDiscovery: any BrowserInstalledImportSourceDiscovering = LiveBrowserInstalledImportSourceDiscovery(),
        dataAccessProvider: any BrowserOnboardingDataAccessProviding = LiveBrowserOnboardingDataAccessProvider(),
        importReader: (any BrowserOnboardingImportReading)? = nil,
        importCommitter: any BrowserOnboardingImportCommitting = LiveBrowserOnboardingImportCommitter(),
        extensionInstaller: (any BrowserImportedExtensionInstalling)? = nil
    ) {
        self.request = request
        self.browser = browser
        self.sourceDiscovery = sourceDiscovery
        self.dataAccessProvider = dataAccessProvider
        self.importCommitter = importCommitter
        self.extensionInstaller = extensionInstaller
        importReadCoordinator = BrowserOnboardingImportReadCoordinator(
            reader: importReader ?? LiveBrowserOnboardingImportReader(core: browser.core))
        manualSetup = BrowserManualSetupModel(core: browser.core)
    }

    // MARK: - Actions - Lifecycle

    /// Opens setup in the core for the request, offering the browsers found.
    func start() {
        send(StartSetup(workspaceID: browser.family.workspaceID, entry: request.entryPoint))
        offerInstalledSources()
        reloadImportOutcomes()
    }

    /// Finds the browsers installed on this Mac by their apps, reading none
    /// of their data, and offers them to setup.
    func discoverInstalledSources() {
        installedSources = sourceDiscovery.installedSources()
        offerInstalledSources()
    }

    private func offerInstalledSources() {
        guard state != nil else { return }
        let unlisted: [ImportSource] = unlistedSources.isEmpty ? [] : [.otherChromium]
        send(OfferImportSources(installed: installedSources.map(\.application) + unlisted))
    }

    /// Reads what each listed browser keeps, and looks for the browsers built
    /// on Chromium that setup does not list, offering them beside the listed
    /// ones. macOS may say Ode looked at other apps' data, so setup scans
    /// only when the person asks.
    func scanForMore() {
        guard !isImportSelectionLocked else { return }
        installedSources = installedSources.map(sourceDiscovery.scanned)
        unlistedSources = sourceDiscovery.unlistedSources()
        hasScanned = true
        offerInstalledSources()
    }

    /// Every browser setup offers: the listed ones, then those it found.
    var offeredSources: [BrowserInstalledImportSource] { installedSources + unlistedSources }

    func isSelected(_ source: BrowserInstalledImportSource) -> Bool {
        guard selectedImportApplications.contains(source.application) else { return false }
        return source.application != .otherChromium || source.applicationURL == chosenUnlistedSourceURL
    }

    /// Chooses `source` or leaves it out. One found browser imports at a time,
    /// so choosing another found browser takes its place.
    func toggleSelection(_ source: BrowserInstalledImportSource) {
        guard !isImportSelectionLocked else { return }
        guard source.application == .otherChromium else {
            toggleImportSelection(source.application)
            return
        }
        let isChosen = selectedImportApplications.contains(.otherChromium)
        if isChosen, source.applicationURL != chosenUnlistedSourceURL {
            chosenUnlistedSourceURL = source.applicationURL
            return
        }
        chosenUnlistedSourceURL = isChosen ? nil : source.applicationURL
        toggleImportSelection(.otherChromium)
    }

    /// The browser `application` reads from: the listed one, or the found one chosen.
    func offeredSource(_ application: ImportSource) -> BrowserInstalledImportSource? {
        guard application == .otherChromium else {
            return installedSources.first { $0.application == application }
        }
        return unlistedSources.first { $0.applicationURL == chosenUnlistedSourceURL }
    }

    func reset(for request: BrowserOnboardingRequest) {
        guard finalizationTask == nil else {
            pendingResetRequest = request
            operationGeneration &+= 1
            return
        }
        applyReset(for: request)
    }

    private func applyReset(for request: BrowserOnboardingRequest) {
        invalidateOperations()
        self.request = request
        currentImportPayload = nil
        start()
    }

    /// Stops what this Mac is doing for setup as the window goes. An import
    /// already applying finishes.
    func cancelOperations() {
        guard finalizationTask == nil else { return }
        let wasPreparingImport = isCommittingImport
        invalidateOperations()
        if wasPreparingImport {
            send(CancelImportPreparation())
        } else if state?.phase == .reading {
            send(CancelImportRead())
        }
    }

    // MARK: - Actions - Steps

    func show(_ step: SetupStep) {
        guard !isImportSelectionLocked else { return }
        send(ShowSetupStep(step: step))
    }

    /// Reads may be abandoned, but an import already applying must finish.
    func prepareToSkipToEnd() -> Bool {
        guard !isCommittingImport, !isCompletingSetup else { return false }
        abandonImportPreparation()
        isExplainingKeychain = false
        return true
    }

    /// Gives the Spaces setup makes from here on `look`.
    func chooseLook(_ look: SetupLook) {
        guard !isImportSelectionLocked else { return }
        send(ChooseSetupLook(look: look))
    }

    /// Sets Spaces up by hand, leaving any read that has not finished.
    func beginManualSetup() {
        guard !isCommittingImport else { return }
        abandonImportPreparation()
        send(ShowSetupStep(step: .manualSetup))
    }

    /// Finishes setup: the core applies the manual setup and completes setup
    /// on this device, and the guide opens where the core names it.
    func completeSetup(
        progress: BrowserOnboardingProgressStore,
        skipping: Bool = false,
        spaceAccess: BrowserSpaceAccessController,
        onCompleted: @escaping @MainActor () -> Void
    ) {
        guard !isImportSelectionLocked else { return }
        let generation = operationGeneration
        let browser = self.browser
        isCompletingSetup = true
        completionFailure = nil
        completionTask = Task { @MainActor [weak self] in
            let result = await BrowserSetupFinish.finish(browser: browser, spaceAccess: spaceAccess, skipping: skipping)
            guard let self, !Task.isCancelled, operationGeneration == generation else { return }
            completionTask = nil
            isCompletingSetup = false
            result.apply(
                to: BrowserOnboardingSetupFinishing(flow: self, progress: progress, onCompleted: onCompleted))
        }
    }

    // MARK: - Actions - Choosing browsers

    func toggleImportSelection(_ application: ImportSource) {
        guard !isImportSelectionLocked else { return }
        send(ToggleImportSource(source: application))
    }

    /// Goes on from choosing browsers: the core moves to the manual setup when
    /// none is chosen, or to reading the next chosen one, which this reads.
    func continueImportQueue() {
        guard !isImportSelectionLocked else { return }
        send(ContinueImport())
        readCurrentSource()
    }

    func cancelImportRead() {
        importReadCoordinator.cancel()
        isChoosingDataAccess = false
        send(CancelImportRead())
    }

    // MARK: - Actions - Reading

    /// Reads the browser the core is on, when it is reading one: from what a
    /// scan found, then a folder the person gave access to, then the browser's
    /// own folder when nothing has read it yet, and otherwise the folder the
    /// person picks.
    private func readCurrentSource() {
        guard let state, state.phase == .reading, let application = state.source else { return }
        guard let source = offeredSource(application) else {
            send(FailImport(source: application, reason: .sourceUnavailable, detail: nil))
            return
        }
        if source.hasReadableDetectedData, let payload = source.detectedPayload {
            readImport(payload)
            return
        }
        if let access = dataAccessProvider.resolve(for: application) {
            let data = application.importData(in: access.url)
            if !data.profiles.isEmpty {
                readImport(
                    BrowserDetectedImportPayload(application: application, data: data), activeDirectoryAccess: access)
                return
            }
            access.stopAccessing()
            dataAccessProvider.clear(for: application)
        }
        if source.detectedPayload == nil {
            let scanned = scannedSource(source)
            if scanned.hasReadableDetectedData, let payload = scanned.detectedPayload {
                readImport(payload)
                return
            }
        }
        chooseBrowserDataAccess(for: application)
    }

    /// `source` with its data folder read now, kept among the browsers setup
    /// offers.
    private func scannedSource(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource {
        let scanned = sourceDiscovery.scanned(source)
        if let index = installedSources.firstIndex(where: { $0.id == source.id }) {
            installedSources[index] = scanned
        }
        return scanned
    }

    private func chooseBrowserDataAccess(for application: ImportSource) {
        isChoosingDataAccess = true
        let generation = operationGeneration
        dataAccessProvider.chooseDataFolder(for: application) { [weak self] folderURL in
            guard let self, operationGeneration == generation else { return }
            isChoosingDataAccess = false
            guard state?.phase == .reading, state?.source == application else { return }
            guard let folderURL else {
                send(CancelImportRead())
                return
            }
            let access = BrowserImportDataDirectoryAccess(url: folderURL)
            let data = application.importData(in: folderURL)
            guard !data.profiles.isEmpty else {
                access.stopAccessing()
                send(FailImport(source: application, reason: .dataFolder, detail: nil))
                return
            }
            try? dataAccessProvider.remember(folderURL, for: application)
            readImport(
                BrowserDetectedImportPayload(application: application, data: data), activeDirectoryAccess: access)
        }
    }

    private func readImport(
        _ payload: BrowserDetectedImportPayload,
        activeDirectoryAccess: BrowserImportDataDirectoryAccess? = nil
    ) {
        isChoosingDataAccess = false
        currentImportPayload = payload
        let generation = operationGeneration
        importReadCoordinator.startReading(
            payload,
            onFinish: { activeDirectoryAccess?.stopAccessing() },
            completion: { [weak self] result in
                guard let self, operationGeneration == generation else {
                    if case .success(let output) = result { output.discard() }
                    return
                }
                completeRead(result, from: payload.application)
            })
    }

    /// Hands the core what the read brought, with where each of the
    /// browser's passwords belongs, or why it failed.
    private func completeRead(
        _ result: Result<BrowserOnboardingImportReadOutput, any Error>, from application: ImportSource
    ) {
        do {
            let output = try result.get()
            defer {
                let accepted = Set(review?.spaces.compactMap { $0.source.importReadID } ?? [])
                if !output.imported.contains(where: { $0.importReadID.map(accepted.contains) == true }) {
                    output.discard()
                }
            }
            passwordReadFailure = output.passwordFailure
            bringsPasswords = true
            bringsSignIns = application == .arc && supportsSignIns
            passwordSelectionBeforeDisabling = nil
            showsEmptyReviewSpaces = false
            extensionIcons.merge(output.extensionIcons.compactMapValues(NSImage.init(data:))) { _, read in read }
            siteIcons.merge(output.siteIcons) { _, read in read }
            _ = try browser.core.send(
                ReviewImport(
                    source: application, spaces: output.imported.map(\.seed),
                    passwords: output.passwordCandidates.map(\.routingSource),
                    // An engine that runs no extensions is offered none to install.
                    extensions: extensionInstaller == nil ? [] : output.extensions,
                    leftOut: output.leftOut,
                    title: offeredSource(application)?.title,
                    profiles: output.profiles))
            // The review opens on the Space holding the most.
            if let first = reviewSpaces.first?.id { shownReviewSpaceID = first }
        } catch {
            send(FailImport(source: application, reason: .read, detail: error.personFacingDescription))
        }
    }

    // MARK: - Actions - Reviewing

    func setDestination(_ destination: BrowserImportDestination, for sourceSpaceID: UUID) {
        send(ChooseImportDestination(sourceSpaceID: sourceSpaceID, destinationSpaceID: destination.spaceID))
    }

    func setIncluded(_ tabID: UUID, _ isIncluded: Bool, in sourceSpaceID: UUID) {
        setIncluded([tabID], isIncluded, in: sourceSpaceID)
    }

    func setIncluded(_ tabIDs: Set<UUID>, _ isIncluded: Bool, in sourceSpaceID: UUID) {
        send(IncludeImportTabs(sourceSpaceID: sourceSpaceID, tabIDs: Array(tabIDs), included: isIncluded))
    }

    func setPlacement(_ placement: TabPlacement, for tabID: UUID, in sourceSpaceID: UUID) {
        send(PlaceImportTab(sourceSpaceID: sourceSpaceID, tabID: tabID, placement: placement))
    }

    func setSpaceIncluded(_ isIncluded: Bool, in sourceSpaceID: UUID) {
        send(IncludeImportSpace(sourceSpaceID: sourceSpaceID, included: isIncluded))
    }

    /// Brings the reviewed Space `sourceSpaceID` in on its own rather than in
    /// a group with the Spaces it shared a session with.
    func separate(_ sourceSpaceID: UUID) {
        send(SeparateImportSpace(sourceSpaceID: sourceSpaceID))
    }

    /// The reviewed Spaces that come into one group with `review`, in the
    /// review's order, as the import forms and joins groups. Empty when
    /// `review` does not come in.
    func reviewGroup(of review: BrowserImportSpaceReview) -> [BrowserImportSpaceReview] {
        guard review.isIncluded else { return [] }
        return reviewSpaces.filter { $0.isIncluded && $0.groupID == review.groupID }
    }

    func setPasswordsIncluded(_ isIncluded: Bool, in sourceSpaceID: UUID) {
        if isIncluded { bringsPasswords = true }
        passwordSelectionBeforeDisabling = nil
        send(IncludeImportPasswords(sourceSpaceID: sourceSpaceID, included: isIncluded))
    }

    func setExtensionIncluded(_ extensionID: String, _ isIncluded: Bool, in sourceSpaceID: UUID) {
        send(IncludeImportExtension(sourceSpaceID: sourceSpaceID, extensionID: extensionID, included: isIncluded))
    }

    /// Turns every extension the reviewed Space `sourceSpaceID` offers on or off.
    func setExtensionsIncluded(_ isIncluded: Bool, in sourceSpaceID: UUID) {
        guard let review = reviewSpaces.first(where: { $0.id == sourceSpaceID }) else { return }
        for item in review.extensions where review.includedExtensionIDs.contains(item.extensionID) != isIncluded {
            setExtensionIncluded(item.extensionID, isIncluded, in: sourceSpaceID)
        }
    }

    /// Gives the reviewed Space `sourceSpaceID` `customization`, which the
    /// core keeps with its branding rules applied.
    func customize(_ sourceSpaceID: UUID, as customization: SpaceCustomization) {
        send(CustomizeImportSpace(sourceSpaceID: sourceSpaceID, customization: customization))
    }

    func selectedReview(id: UUID?) -> BrowserImportSpaceReview? {
        reviewSpaces.first { $0.id == id } ?? reviewSpaces.first
    }

    func passwordCountLabel(for review: BrowserImportSpaceReview) -> LocalizedStringResource {
        BrowserOnboardingSummary.passwordCount(review.record.passwordCount)
    }

    func reviewSummary() -> LocalizedStringResource? {
        review?.summary
    }

    /// What the core says the review's choices mean.
    func reviewAnalysis() -> BrowserImportReviewAnalysis {
        BrowserImportReviewAnalysis(review)
    }

    /// The session the review would leave. The core answers once each time
    /// the review's choices change.
    private func reviewPreview() -> BrowserSessionPreview? {
        guard let review else { return nil }
        if let previewCache, previewCache.choices == review.spaces { return previewCache.session }
        let session = try? browser.reviewedImportPreview(images: review.tabImages(from: siteIcons))
        previewCache = (review.spaces, session)
        return session
    }

    /// The images the tabs of the session the review would leave wear.
    var previewFavicons: FaviconAssets {
        reviewPreview()?.favicons ?? FaviconAssets()
    }

    func previewDestinationSpace(for review: BrowserImportSpaceReview) -> SpaceModel? {
        reviewPreview()?.space(id: review.destination.spaceID ?? review.id)
    }

    func customizationPreviewSpace(_ spaceID: UUID) -> SpaceModel? {
        reviewSpaces.first { $0.id == spaceID }.flatMap(previewDestinationSpace)
    }

    func duplicateDestinationName(for review: BrowserImportSpaceReview) -> String? {
        review.destination.spaceID.flatMap { browser.spaceModel($0)?.settings.name }
    }

    func destinationName(for destination: BrowserImportDestination) -> String {
        guard let spaceID = destination.spaceID else { return String(localized: "New Space") }
        return browser.spaceModel(spaceID)?.settings.name ?? String(localized: "Existing Space")
    }

    /// The workspace's Spaces, which a reviewed Space may join.
    var destinationSpaces: [SpaceModel] {
        browser.workspaceModel?.spaces.models ?? []
    }

    /// Whether the workspace is still the first launch's disposable Spaces.
    var hasDisposableSeedState: Bool {
        browser.workspaceModel?.isDisposableSeed ?? false
    }

    func reviewProgressLabel(for review: BrowserImportSpaceReview) -> String {
        let spaces = reviewSpaces
        let index = spaces.firstIndex(where: { $0.id == review.id }) ?? 0
        let spaceProgress = String(localized: "Space \(index + 1) of \(spaces.count)")
        guard let queue = state?.queue, queue.sources.count > 1, queue.current != nil else { return spaceProgress }
        let browserProgress = String(localized: "Browser \(queue.index + 1) of \(queue.sources.count)")
        return String(localized: "\(browserProgress) · \(spaceProgress)")
    }

    /// What reading `source` takes, or nil before setup has read its data.
    func importAccessLabel(for source: BrowserInstalledImportSource) -> String? {
        if source.hasReadableDetectedData, let payload = source.detectedPayload {
            let count = payload.profiles.count
            return count > 1
                ? String(localized: "\(count) profiles found · Review them")
                : String(localized: "Browser data found · Review it")
        }
        if dataAccessProvider.hasSavedAccess(for: source.application) {
            return String(localized: "Access saved · Ready to review")
        }
        guard source.detectedPayload != nil else { return nil }
        return String(localized: "One-time macOS permission · No folder search")
    }

    // MARK: - Actions - Importing

    /// Imports the review: the core applies it, and this reads and imports
    /// the passwords it brings. The core refuses a review that brings no Space.
    /// Whether importing `review` asks macOS for the browser's Keychain
    /// key: its passwords, or Arc's sign-ins for a Space that comes in new.
    func asksForKeychainKey(_ review: SetupImportReview) -> Bool {
        guard review.source.suppliesPasswords else { return false }
        if review.includedPasswordCount > 0 { return true }
        return bringsSignIns && supportsSignInCarry
    }

    /// Temporarily excludes passwords without losing the reviewed per-Space
    /// choices. Sign-ins have independent consent and are never changed here.
    func setBringsPasswords(_ brings: Bool) {
        guard !isCommittingImport, brings != bringsPasswords, let review else { return }
        if !brings {
            passwordSelectionBeforeDisabling = Set(review.spaces.filter(\.includesPasswords).map { $0.source.id })
        }
        bringsPasswords = brings
        for space in review.spaces where space.passwordCount > 0 {
            let included =
                brings && (passwordSelectionBeforeDisabling?.contains(space.source.id) ?? space.includesPasswords)
            send(IncludeImportPasswords(sourceSpaceID: space.source.id, included: included))
        }
        if brings { passwordSelectionBeforeDisabling = nil }
    }

    func setBringsSignIns(_ brings: Bool) {
        guard !isCommittingImport else { return }
        bringsSignIns = brings
    }

    /// The no-Keychain alternative excludes both kinds of secrets explicitly.
    func importWithoutSecrets() {
        setBringsPasswords(false)
        setBringsSignIns(false)
        isExplainingKeychain = false
        commitReviewedImport(afterExplaining: true)
    }

    /// Leaves the Keychain page for the review, importing nothing yet.
    func dismissKeychainExplanation() {
        isExplainingKeychain = false
        keychainWasRefused = false
    }

    /// Imports the review: the core applies it, and this reads and imports
    /// the passwords it brings. When the import will ask macOS for the
    /// browser's Keychain key, setup first explains why, unless the person
    /// has read that page.
    func commitReviewedImport(afterExplaining: Bool = false) {
        guard let review, !isCommittingImport else { return }
        if asksForKeychainKey(review), !afterExplaining {
            isExplainingKeychain = true
            return
        }
        isExplainingKeychain = false
        keychainWasRefused = false
        let outcome = startedOutcome(for: review)
        var didRecordOutcome = false
        do {
            _ = try browser.core.send(RecordSetupImportOutcome(outcome: outcome))
            didRecordOutcome = true
            reloadImportOutcomes()
            _ = try browser.core.send(BeginImportCommit())
        } catch {
            if didRecordOutcome {
                recordOutcome(
                    outcome, status: .failed, omission: String(localized: "The reviewed import couldn't be started."))
            }
            send(FailImport(source: review.source, reason: .import, detail: error.explanation))
            return
        }
        importStage = makeImportStage(for: review)
        let generation = operationGeneration
        let payload = currentImportPayload
        let bringsSignIns = bringsSignIns
        commitTask = Task { @MainActor [weak self] in
            await self?.performImportCommit(
                review: review, payload: payload, generation: generation, outcome: outcome, bringsSignIns: bringsSignIns
            )
        }
    }

    private func performImportCommit(
        review: SetupImportReview, payload: BrowserDetectedImportPayload?, generation: Int, outcome: SetupImportOutcome,
        bringsSignIns: Bool
    ) async {
        defer { finishImportCommit(generation: generation) }
        do {
            var preparedImport = try await importCommitter.prepare(
                review: review, payload: payload, bringsSignIns: bringsSignIns)
            preparedImport.siteIcons = siteIcons
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            importStage?.bringing()

            // Finalization is the point of no return. It runs in its own task so
            // reset and window dismissal cannot leave the session or Keychain
            // credential import only partially applied.
            let importCommitter = self.importCommitter
            let browser = self.browser
            let finalizationTask: Task<Result<BrowserOnboardingImportResult, any Error>, Never> = Task { @MainActor in
                do {
                    return .success(
                        try await importCommitter.finalize(
                            review: review, preparedImport: preparedImport, browser: browser))
                } catch {
                    return .failure(error)
                }
            }
            self.finalizationTask = finalizationTask
            let result = await finalizationTask.value
            // Account for committed side effects before a queued reset changes
            // setup. A dismissed window cannot erase this source's receipt.
            switch result {
            case .success(let imported):
                let completed = completedOutcome(outcome, imported: imported)
                do {
                    _ = try browser.core.send(
                        FinishImportCommit(
                            passwordCount: imported.passwords.importedCount,
                            unsavedPasswordCount: imported.passwords.unsavedCount, outcome: completed))
                    reloadImportOutcomes()
                } catch {
                    importStage = nil
                    send(
                        FailImport(
                            source: review.source, reason: .import,
                            detail: String(
                                localized:
                                    "Import applied, but its result couldn't be saved. Check your Spaces before retrying."
                            )))
                    _ = finishImportFinalization()
                    return
                }
                currentImportPayload = nil
                if let extensionInstaller, !review.extensionInstalls.isEmpty {
                    extensionInstaller.installImported(review.extensionInstalls, outcomeID: outcome.id)
                }
                guard !finishImportFinalization(), operationGeneration == generation else { return }
                importStage?.finish(passwords: imported.passwords.importedCount)
                dismissImportStage(generation: generation)
                readCurrentSource()
            case .failure(let error):
                recordOutcome(
                    outcome, status: .failed, omission: String(localized: "The reviewed import couldn't be applied."))
                guard !finishImportFinalization(), operationGeneration == generation else { return }
                importStage = nil
                send(FailImport(source: review.source, reason: .import, detail: error.personFacingDescription))
            }
        } catch is CancellationError {
            recordOutcome(outcome, status: .cancelled)
            importStage = nil
            if operationGeneration == generation {
                send(FailImport(source: review.source, reason: .import, detail: String(localized: "Import cancelled.")))
            }
            return
        } catch {
            recordOutcome(
                outcome, status: .failed,
                omission: (error as? BrowserPasswordImportError) == .safeStorageUnavailable
                    ? String(localized: "The source Keychain key couldn't be read. Your reviewed choices were kept.")
                    : String(localized: "The selected passwords or sign-ins couldn't be prepared."))
            importStage = nil
            guard operationGeneration == generation else { return }
            if (error as? BrowserPasswordImportError) == .safeStorageUnavailable {
                // macOS refused the key: back to the page that explains it,
                // with a way to import without passwords.
                keychainWasRefused = true
                isExplainingKeychain = true
            }
            send(FailImport(source: review.source, reason: .import, detail: error.personFacingDescription))
        }
    }

    // MARK: - Actions - Import stage

    /// The stage for importing `review`: the Spaces it brings as Ode will
    /// show them, in the order the review shows them.
    private func makeImportStage(for review: SetupImportReview) -> BrowserOnboardingImportStage {
        BrowserOnboardingImportStage(
            sourceTitle: review.title,
            sourceIcon: offeredSource(review.source)?.icon,
            favicons: previewFavicons,
            spaces: reviewSpaces.filter(\.isIncluded).compactMap(previewDestinationSpace(for:)),
            passwordCount: review.includedPasswordCount,
            readsKeychain: asksForKeychainKey(review),
            leftOut: review.leftOut)
    }

    /// Takes the stage away once its beats end, and no later than a moment
    /// after the import finished.
    private func dismissImportStage(generation: Int) {
        guard let stage = importStage, let doneAt = stage.doneAt else { return }
        let choreography = BrowserOnboardingImportChoreography(
            flightCount: stage.shownSpaces.first?.flights.count ?? 0, spaceCount: stage.spaces.count,
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let done = doneAt.timeIntervalSince(stage.startedAt)
        let delay = stage.isSkipped ? 0.2 : choreography.dismissal(doneAt: done) - done
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0.2)))
            guard let self, self.importStage === stage, self.operationGeneration == generation else { return }
            self.importStage = nil
        }
    }

    private func finishImportCommit(generation: Int) {
        guard finalizationTask == nil, operationGeneration == generation else { return }
        commitTask = nil
    }

    /// The import finished applying. Answers whether a reset waited for it,
    /// which has now run.
    private func finishImportFinalization() -> Bool {
        finalizationTask = nil
        commitTask = nil
        guard let pendingResetRequest else { return false }
        self.pendingResetRequest = nil
        applyReset(for: pendingResetRequest)
        return true
    }

    // MARK: - Actions - Sending

    /// Sends `intent` to the core. A refused intent leaves setup as the core
    /// holds it.
    private func send(_ intent: some Intent) {
        _ = try? browser.core.send(intent)
    }

    private func invalidateOperations() {
        for id in Set(review?.spaces.compactMap { $0.source.importReadID } ?? []) {
            _ = try? browser.core.query(DiscardImportRead(readID: id))
        }
        operationGeneration &+= 1
        importStage = nil
        completionTask?.cancel()
        completionTask = nil
        isCompletingSetup = false
        completionFailure = nil
        importReadCoordinator.cancel()
        isChoosingDataAccess = false
        commitTask?.cancel()
        commitTask = nil
    }

    private func abandonImportPreparation() {
        if isReading || isChoosingDataAccess {
            operationGeneration &+= 1
            importReadCoordinator.cancel()
            isChoosingDataAccess = false
        }
        if state?.phase == .reading { send(CancelImportRead()) }
    }
}

extension BrowserOnboardingFlow {
    // MARK: - Actions - Import outcomes

    func reloadImportOutcomes() {
        do {
            importOutcomes = try browser.core.query(GetSetupImportOutcomes()).items
            outcomeReadFailure = nil
        } catch {
            outcomeReadFailure = String(localized: "Import results couldn't be read. Try again.")
        }
    }

    func startedOutcome(for review: SetupImportReview) -> SetupImportOutcome {
        var omissions = review.leftOut.map { "\($0.name): \($0.reason.explanation)" }
        if passwordReadFailure != nil {
            omissions.append(
                String(localized: "Passwords couldn't be read. Close the source browser and import again to retry."))
        }
        if review.spaces.contains(where: { $0.included && $0.passwordCount > 0 && !$0.includesPasswords }) {
            omissions.append(String(localized: "Unselected passwords were left out."))
        }
        if review.source != .arc {
            omissions.append(String(localized: "Sign-in import is only supported from Arc into new Spaces."))
        } else if !supportsSignIns {
            omissions.append(String(localized: "Sign-in import isn't available in this build."))
        } else if !bringsSignIns {
            omissions.append(String(localized: "Sign-ins were left out by choice."))
        }
        return SetupImportOutcome(
            id: UUID(), sourceTitle: review.title, status: .started,
            tabCount: review.includedTabCount, spaceCount: review.spaces.count { $0.included },
            passwordCount: 0, passwordSkippedCount: 0, omissions: omissions,
            cookieCount: 0, expiredCookieCount: 0, droppedCookieCount: 0, signInSpacesSkipped: 0,
            extensions: review.extensionInstalls.flatMap { item in
                item.spaceIDs.map {
                    SetupImportExtensionOutcome(
                        extensionID: item.extensionID, name: item.name, spaceID: $0, status: .pending)
                }
            })
    }

    func completedOutcome(_ started: SetupImportOutcome, imported: BrowserOnboardingImportResult) -> SetupImportOutcome
    {
        var outcome = started
        outcome.status = .imported
        outcome.passwordCount = imported.passwords.importedCount
        outcome.passwordSkippedCount = imported.passwords.skippedCount
        let signIns = imported.signIns
        outcome.cookieCount = signIns.cookies
        outcome.expiredCookieCount = signIns.expired
        outcome.droppedCookieCount = signIns.dropped
        outcome.signInSpacesSkipped =
            signIns.missing + signIns.existing + signIns.unavailable + signIns.failed + signIns.merged
        if signIns.missing > 0 {
            outcome.omissions.append(
                String(localized: "\(signIns.missing) Spaces had no readable source sign-in database."))
        }
        if signIns.existing > 0 {
            outcome.omissions.append(
                String(localized: "\(signIns.existing) existing sign-in databases were kept unchanged."))
        }
        if signIns.unavailable > 0 {
            outcome.omissions.append(
                String(
                    localized:
                        "Sign-ins for \(signIns.unavailable) Spaces couldn't be unlocked or stored by this build."))
        }
        if signIns.failed > 0 {
            outcome.omissions.append(
                String(localized: "Sign-in copying failed for \(signIns.failed) Spaces. Other imported data was kept."))
        }
        if signIns.merged > 0 {
            outcome.omissions.append(
                String(localized: "Sign-ins weren't merged into \(signIns.merged) existing Spaces."))
        }
        return outcome
    }

    func recordOutcome(_ started: SetupImportOutcome, status: SetupImportOutcomeStatus, omission: String? = nil) {
        var outcome = started
        outcome.status = status
        if let omission { outcome.omissions.append(omission) }
        do {
            _ = try browser.core.send(RecordSetupImportOutcome(outcome: outcome))
            reloadImportOutcomes()
        } catch {
            outcomeReadFailure = String(
                localized: "The import result couldn't be saved. Check your Spaces before retrying.")
        }
    }
}
