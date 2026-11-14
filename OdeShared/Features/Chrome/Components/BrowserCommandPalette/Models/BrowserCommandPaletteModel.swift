import Foundation
import Observation
import SwiftUI
@preconcurrency import Translation

// MARK: - Types

private struct BrowserPalettePendingGeneration {
    let lookup: PaletteGenerativeLookup
    let question: PaletteSuggestions
    let sequence: Int
}

struct BrowserPaletteTranslationPreparation {
    let lookup: PaletteTranslationLookup
    let sequence: Int
    let configuration: TranslationSession.Configuration
}

/// The shared palette's rows, keyboard selection and the search provider or
/// scope a person narrowed it to. The core ranks what the palette offers for each
/// query, off the main thread; an answer that arrives after a newer keystroke
/// is dropped, so the latest query always wins, and a key pressed before the
/// first answer for its text waits for it. The query text, the selection, the
/// completion editing and the modifier keys held stay here.
@MainActor
@Observable
final class BrowserCommandPaletteModel {
    // MARK: - Static Variables

    /// How long Return, Tab or Down wait for the answer to what was typed
    /// before the key expires without acting on older rows.
    private static let keyWait: Duration = .milliseconds(300)

    // MARK: - Variables

    /// The window the palette speaks for, whose core answers it.
    let browser: BrowserStore
    /// The Space the palette speaks for, or nil when the window shows none.
    let space: SpaceModel?
    let selectedTabID: UUID?
    let commands: BrowserCommandPaletteCommandRegistry?
    /// Whether the palette offers the platform's resting commands before
    /// anything is typed. The Start Page's palette offers commands only once
    /// what is typed matches one.
    let offersRestingCommands: Bool
    private let presentation: BrowserCommandPalettePresentation

    var query: String {
        didSet {
            guard query != oldValue else { return }
            selectedResultIndex = 0
            keepsQueryPrivate = false
            requestAnswer()
        }
    }

    private(set) var groups: [BrowserCommandPaletteGroup] = []
    /// Every row, in the order the keyboard steps through them.
    private(set) var items: [BrowserCommandPaletteItem] = []
    private(set) var selectedResultIndex = 0
    private(set) var keyboardSelectionRevision = 0
    var isFieldFocused = false
    private(set) var copiedCardID: BrowserCommandPaletteRowID?
    @ObservationIgnored private var copiedFeedbackTask: Task<Void, Never>?
    /// A fresh request's first result set may reveal selection. Enrichment
    /// of that same request must not pull a manually scrolled list back.
    private(set) var resultSetRevision = 0
    private(set) var completionEditing = BrowserURLCompletionEditingState()
    /// The search provider the person narrowed the palette to, or nil.
    private(set) var activeProvider: SearchProvider?
    /// The kind of result the person narrowed the palette to, or nil.
    private(set) var activeScope: PaletteScope?
    /// The modifier keys the person holds, which choose where a row opens.
    private(set) var heldModifiers: EventModifiers = []
    private var completionProposal: AddressCompletion?
    private var offeredSearch: SearchOffer?
    /// Every provider what is typed names or starts to name, closest first.
    private var matchingProviders: [SearchProvider] = []
    private var offeredScope: PaletteScope?
    /// The button of an answer Return runs, kept for the row it was chosen
    /// on; any other answer starts on its first button.
    private var answerChoice: (row: BrowserCommandPaletteRowID, control: BrowserCommandPaletteAnswerControl)?
    /// Hover may select Return's target, but must not resize answers under
    /// a pointer that is manually scrolling the list.
    private var expandedAnswerID: BrowserCommandPaletteRowID?
    @ObservationIgnored var applyCompletion: ((String, NSRange) -> Void)?
    /// Replaces the field's text, as entering or leaving a scope does.
    @ObservationIgnored var replaceText: ((String) -> Void)?
    /// Reports native editing changes to a shell retaining focus across adaptive hosts.
    @ObservationIgnored var focusChanged: ((Bool) -> Void)?

    /// Counts keystrokes: each query asks under the next number, and only the
    /// answer to the latest is shown.
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var isActive = true
    private var isCopySessionActive = true
    private var translationResult: PaletteTranslationResult?
    private var generativeResult: PaletteGenerativeResult?
    private var shownAnswerRequiresAskOde = false
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingGeneration: BrowserPalettePendingGeneration?
    @ObservationIgnored private var keepsQueryPrivate = false
    private(set) var translationPreparation: BrowserPaletteTranslationPreparation?
    /// The keystroke whose answer the rows show.
    @ObservationIgnored private var shownSequence = 0
    @ObservationIgnored private var answerTask: Task<Void, Never>?
    /// A key pressed before its query's answer arrived. A later edit must
    /// never carry this key into a different query.
    @ObservationIgnored private var waitingKey: (sequence: Int, action: () -> Void)?
    @ObservationIgnored private var keyWaitTask: Task<Void, Never>?
    /// The text on the pasteboard when the palette opened, offered with
    /// Paste and Go while the text is still what the palette opened with, or
    /// nil.
    @ObservationIgnored private var pasteboard: String?
    /// What the field held when the palette opened: nothing for a new tab, or
    /// the address of the page the window shows.
    @ObservationIgnored private var openedWith: String

    /// The asynchronous answer boundary; normally ranks in the real core on
    /// a background thread, independently of native editing.
    private let fetchAnswer: @Sendable (PaletteSuggestions) async -> PaletteAnswer?
    /// What the palette asks the device, the network and the dictionary.
    private let lookups: BrowserCommandPaletteLookups
    private let isSourceAvailableAction: (BrowserTabRuntimeAssignment) -> Bool
    private let selectTabAction: (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool
    private let openURLAction: (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool
    private let dismissAction: () -> Void
    /// Where the palette opens a pick when it has no tab of its own.
    private let destination: (any BrowserPaletteDestination)?
    /// Where this platform can open a row, which the modifier keys choose among.
    let openings: [BrowserCommandPaletteOpening]

    /// How the person set the palette to rank and arrange its rows.
    var preferences: PalettePreferences { BrowserAppPreferenceStore.shared.preferences.palette }

    /// The search provider Tab enters for what is typed, or nil: one the
    /// text names exactly by its shortcut, or one whose site the completion
    /// that shows opens, as "you" completing to youtube.com offers YouTube;
    /// else one the text names by title or site once no completion shows.
    var providerOffer: SearchProvider? {
        guard isUnscoped, completionEditing.isAtEnd, preferences.searchesSitesWithTab, isCompletionSourceAvailable,
            let offer = offeredSearch
        else { return nil }
        guard let completion = urlCompletion, !offer.beatsCompletion else { return offer.provider }
        return offer.provider.isSite(of: completion.accepted) ? offer.provider : nil
    }

    /// The providers the palette offers as chips while what is typed is one
    /// word, closest first, when Tab or Space enters them, as the core matches
    /// them; none once the palette is narrowed, or while the only one is the
    /// one Tab offers, which the field already names.
    var providerChips: [SearchProvider] {
        guard isUnscoped, isCompletionSourceAvailable,
            matchingProviders != [providerOffer].compactMap({ $0 })
        else { return [] }
        return matchingProviders
    }

    /// The scope Tab enters for what is typed, or nil. One the text names by
    /// a plain word, as "help" names Ode Help, wins over a completion.
    var scopeOffer: PaletteScope? {
        guard isUnscoped, completionEditing.isAtEnd, urlCompletion == nil || wordScopeOffer != nil else { return nil }
        return offeredScope
    }

    /// The scope what is typed names by one of its plain words, or nil.
    private var wordScopeOffer: PaletteScope? {
        guard isUnscoped, completionEditing.isAtEnd, let scope = offeredScope else { return nil }
        let word = query.trimmingCharacters(in: .whitespaces)
        return scope.words.contains { $0.caseInsensitiveCompare(word) == .orderedSame } ? scope : nil
    }

    var generativeStatus: PaletteGenerativeStatus { generativeResult?.status ?? .waiting }
    var canRetryGenerativeAnswer: Bool { generativeResult != nil && generationTask == nil }

    var translationStatus: PaletteTranslationStatus { translationResult?.status ?? .waiting }
    var canRetryTranslation: Bool { translationResult != nil && translationPreparation == nil }
    var canDownloadTranslationLanguages: Bool { translationResult?.status == .notInstalled }

    /// The ready card Tab copies, also used by the card's keycap. Completion
    /// offers win, and an intentional selection of another result stays intact.
    var tabCopyCandidate: BrowserCommandPaletteItem? {
        guard isFieldFocused, providerOffer == nil, wordScopeOffer == nil, urlCompletion == nil,
            scopeOffer == nil, items.indices.contains(selectedResultIndex)
        else { return nil }
        let selected = items[selectedResultIndex]
        if canCopyQuickAnswer(selected) { return selected }
        guard selectedResultIndex == 0, selected.row.kind == .search else { return nil }
        let candidates = items.filter { canCopyQuickAnswer($0) }
        return candidates.count == 1 ? candidates.first : nil
    }

    /// The written answer the selected row shows, or nil.
    var selectedAnswer: AnswerCard? {
        items.indices.contains(selectedResultIndex) ? items[selectedResultIndex].row.answer : nil
    }

    /// The completion the field shows: the core's for what is typed, or,
    /// until its answer arrives, the last one shown while the keystrokes
    /// since then still type into it.
    var urlCompletion: AddressCompletion? {
        guard isUnscoped, isCompletionSourceAvailable, completionEditing.canPropose(for: query) else { return nil }
        return completionProposal?.continued(to: query)
    }

    var isCompletionSourceAvailable: Bool {
        if selectedTabID != nil { return availableSourceAssignment != nil }
        return availableDestination != nil
    }

    /// Where Return opens the selected row while the person holds the keys
    /// they hold: `here` for a row that opens nothing, or keys that choose
    /// nothing.
    var selectedOpening: BrowserCommandPaletteOpening {
        guard items.indices.contains(selectedResultIndex) else { return .here }
        return opening(for: items[selectedResultIndex].row)
    }

    private var isUnscoped: Bool { activeProvider == nil && activeScope == nil }

    private var availableSourceAssignment: BrowserTabRuntimeAssignment? {
        guard let sourceAssignment, isSourceAvailableAction(sourceAssignment) else { return nil }
        return sourceAssignment
    }

    private var sourceAssignment: BrowserTabRuntimeAssignment? {
        guard let space, let selectedTabID else { return nil }
        return BrowserTabRuntimeAssignment(tabID: selectedTabID, spaceID: space.id, profileID: space.profileID)
    }

    // MARK: - Initializers

    init(
        browser: BrowserStore,
        space: SpaceModel?,
        selectedTabID: UUID?,
        initialQuery: String,
        commands: BrowserCommandPaletteCommandRegistry?,
        offersRestingCommands: Bool = true,
        presentation: BrowserCommandPalettePresentation = .overlay,
        lookups: BrowserCommandPaletteLookups = BrowserCommandPaletteLookups(),
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab: @escaping (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool,
        dismiss: @escaping () -> Void,
        destination: (any BrowserPaletteDestination)? = nil,
        openings: [BrowserCommandPaletteOpening] = [.here]
    ) {
        self.browser = browser
        self.space = space
        self.selectedTabID = selectedTabID
        self.commands = commands
        self.offersRestingCommands = offersRestingCommands
        self.presentation = presentation
        query = initialQuery
        let core = browser.core
        fetchAnswer = lookups.answer ?? { question in await Self.answer(question, from: core) }
        self.lookups = lookups
        isSourceAvailableAction = isSourceAvailable
        selectTabAction = selectTab
        openURLAction = openURL
        dismissAction = dismiss
        self.destination = destination
        self.openings = openings
        openedWith = initialQuery
        pasteboard =
            browser.workspaceModel?.kind.isPractice != true
                && BrowserAppPreferenceStore.shared.preferences.palette.offers(.pasteAndGo) ? lookups.pasteboard() : nil
        // The palette opens with its rows: the resting answer is quick to
        // rank, so it is asked for on the main thread.
        if let answer = try? browser.core.query(question(for: initialQuery)) { show(answer, for: sequence) }
        BrowserCommandBarTiming.mark(.modelReady)
        if items.contains(where: { $0.row.card?.kind == .translation || $0.row.card?.kind == .generativeAnswer }) {
            requestAnswer()
        }
    }

    // MARK: - Actions - Completion

    func updateCompletionEditing(text: String, selection: NSRange, isComposing: Bool) {
        let couldPropose = completionEditing.canPropose(for: query)
        let wasComposing = completionEditing.isComposing
        completionEditing.update(text: text, selection: selection, isComposing: isComposing)
        if isComposing {
            resetCopiedFeedback()
            waitingKey = nil
            keyWaitTask?.cancel()
            sequence &+= 1
            answerTask?.cancel()
            cancelGenerativeAnswer()
            translationPreparation = nil
            translationResult = nil
            groups = []
            items = []
        } else {
            let unchanged = query == text
            query = text
            if wasComposing && unchanged { requestAnswer() }
        }
        // The core leads with the completion only while the field may show
        // it, so a caret that moves away asks again.
        if !isComposing, text == query, couldPropose != completionEditing.canPropose(for: query) { requestAnswer() }
    }

    func rejectURLCompletion() { completionEditing.reject() }

    func invalidateURLCompletion() {
        completionProposal = nil
        completionEditing.reject()
    }

    @discardableResult
    func acceptURLCompletion() -> Bool {
        guard let proposal = urlCompletion, let applyCompletion else { return false }
        completionEditing.reject()
        applyCompletion(proposal.insertionText, proposal.insertionRange)
        // Return right after Tab must find the accepted address as the primary
        // action even before the off-main answer arrives.
        if query == proposal.accepted, let answer = try? browser.core.query(question(for: query)) {
            show(answer, for: sequence)
            selectedResultIndex = 0
        }
        completionEditing.reject()
        return true
    }

    // MARK: - Actions - Keys

    /// Tab: enters the search provider whose shortcut the text is or whose
    /// site the completion opens, or the scope the text names by a plain
    /// word, else accepts the completion the field shows, else enters the
    /// provider or scope the text names, else copies a ready quick answer,
    /// else moves to the next button or row. A waiting Tab never copies a
    /// result that was not ready when pressed. It never
    /// moves focus out of the field.
    func pressTab() {
        if let item = tabCopyCandidate {
            copyCard(item)
            return
        }
        waitForAnswer { [weak self] in self?.completeOrMoveWithTab() }
    }

    private func completeOrMoveWithTab() {
        if let provider = providerOffer {
            enter(provider)
            return
        }
        if let scope = wordScopeOffer {
            enter(scope)
            return
        }
        if acceptURLCompletion() { return }
        if let scope = scopeOffer {
            enter(scope)
        } else if !moveAnswerControl(by: 1) {
            moveSelection(by: 1)
        }
    }

    /// Shift-Tab moves to the answer's button before, or to the row before.
    func pressBacktab() {
        if !moveAnswerControl(by: -1) { moveSelection(by: -1) }
    }

    /// Return runs the selected row, once the answer to what was typed arrived.
    func pressReturn() {
        waitForAnswer { [weak self] in self?.activateSelectedResult() }
    }

    /// Down moves to the next row, once the answer to what was typed arrived.
    func pressDown() {
        waitForAnswer { [weak self] in self?.moveSelection(by: 1) }
    }

    /// Notes the modifier keys the person holds.
    func updateHeldModifiers(_ modifiers: EventModifiers) {
        let held = modifiers.intersection([.command, .shift, .option])
        if held != heldModifiers { heldModifiers = held }
    }

    /// Runs `key` now when the rows answer what was typed, or once they do
    /// within the short wait. An expired key never acts on older rows.
    private func waitForAnswer(_ key: @escaping () -> Void) {
        guard !completionEditing.isComposing else { return }
        guard shownSequence != sequence else {
            key()
            return
        }
        waitingKey = (sequence, key)
        keyWaitTask?.cancel()
        keyWaitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.keyWait)
            guard !Task.isCancelled, let self else { return }
            runWaitingKey()
        }
    }

    private func runWaitingKey() {
        keyWaitTask?.cancel()
        guard let key = waitingKey else { return }
        waitingKey = nil
        guard key.sequence == sequence else { return }
        guard shownSequence == sequence else {
            DiagnosticLog.shortcuts.notice("Command Bar key expired while awaiting current results.")
            return
        }
        key.action()
    }

    // MARK: - Actions - Scopes

    /// Narrows the palette to `provider`: what the person types next searches it.
    func enter(_ provider: SearchProvider) {
        activeProvider = provider
        activeScope = nil
        narrowed()
        BrowserGettingStartedMoves.record(provider.kind == .assistant ? .askAI : .siteSearch)
    }

    /// Narrows the palette to `scope`'s kind of result.
    func enter(_ scope: PaletteScope) {
        activeScope = scope
        activeProvider = nil
        narrowed()
    }

    /// Leaves the search provider or scope, keeping what was typed.
    @discardableResult
    func leaveScope() -> Bool {
        guard !isUnscoped else { return false }
        activeProvider = nil
        activeScope = nil
        requestAnswer()
        replaceText?(query)
        return true
    }

    /// Enters what the text named in the palette's notation, keeping what
    /// followed it as what is typed.
    private func enter(_ entry: PaletteEntry) {
        // Notation narrows the same input, unlike a later edit. Keep only a
        // key belonging to that input, under its original timeout.
        let key = waitingKey.flatMap { $0.sequence == sequence ? $0.action : nil }
        activeProvider = entry.provider
        activeScope = entry.scope
        narrowed(keeping: entry.text)
        if let key { waitingKey = (sequence, key) }
    }

    private func narrowed(keeping text: String = "") {
        invalidateURLCompletion()
        query = text
        replaceText?(text)
        requestAnswer()
    }

    // MARK: - Actions - Answers

    /// Copy is presentation-local: unlike Return it neither records a pick
    /// nor dismisses the palette. Revalidate the exact live row at action time.
    func canCopyCard(_ item: BrowserCommandPaletteItem) -> Bool {
        guard isActive, isCopySessionActive, shownSequence == sequence, !completionEditing.isComposing,
            isCompletionSourceAvailable, commands?.canCopy == true, items.contains(item),
            let card = item.row.card, card.kind.copiesValue,
            let value = BrowserCommandPaletteCardText.copied(card), !value.isEmpty
        else { return false }
        let sources = browser.workspaceModel?.appPreferences?.palette ?? preferences
        if shownAnswerRequiresAskOde, !sources.offers(.askOde) { return false }
        if card.kind == .calculation { return sources.offers(.calculator) }
        if card.kind == .conversion || card.kind == .time { return sources.offers(.conversions) }
        if card.kind == .generativeAnswer { return sources.offers(.askOde) }
        return card.kind == .translation
    }

    private func canCopyQuickAnswer(_ item: BrowserCommandPaletteItem) -> Bool {
        canCopyCard(item) && item.row.card?.value != nil && item.row.card?.kind != .time
    }

    func isCopied(_ item: BrowserCommandPaletteItem) -> Bool {
        copiedCardID == item.id && canCopyCard(item)
    }

    func copyCard(_ item: BrowserCommandPaletteItem) {
        guard canCopyCard(item), let card = item.row.card,
            let value = BrowserCommandPaletteCardText.copied(card), let commands
        else { return }
        guard commands.copyInPlace(value) else { return }
        resetCopiedFeedback()
        copiedCardID = item.id
        copiedFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.resetCopiedFeedback()
        }
    }

    private func resetCopiedFeedback() {
        copiedFeedbackTask?.cancel()
        copiedFeedbackTask = nil
        copiedCardID = nil
    }

    /// The button of `item`'s answer that Return runs.
    func answerControl(for item: BrowserCommandPaletteItem) -> BrowserCommandPaletteAnswerControl {
        guard let card = item.row.answer else { return .readMore }
        if let choice = answerChoice, choice.row == item.id, choice.control.isOffered(for: card, in: self) {
            return choice.control
        }
        return BrowserCommandPaletteAnswerControl.offered(for: card, in: self).first ?? .readMore
    }

    /// Keyboard or explicit selection expands an answer; otherwise the first
    /// answer stays expanded while hover changes Return's target.
    func expandsAnswer(_ item: BrowserCommandPaletteItem) -> Bool {
        guard let card = item.row.answer, !isDirectFeedbackAction(card) else { return false }
        let expanded =
            items.first { $0.id == expandedAnswerID && $0.row.answer != nil }
            ?? items.first { $0.row.answer != nil }
        return expanded?.id == item.id
    }

    /// Direct report requests run the native action rather than opening how-to controls.
    func isDirectFeedbackAction(_ card: AnswerCard) -> Bool {
        guard isUnscoped, card.action?.applicationAction == BrowserFeedbackDraft.applicationActionName,
            canPerformAnswerAction(of: card)
        else { return false }
        let request = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["bug", "report bug", "feedback"].contains(request)
    }

    /// Runs `control` of the answer `item` shows, as clicking it does.
    func run(_ control: BrowserCommandPaletteAnswerControl, of item: BrowserCommandPaletteItem) {
        guard isActive, shownSequence == sequence, items.contains(item), let card = item.row.answer,
            control.isOffered(for: card, in: self)
        else { return }
        answerChoice = (item.id, control)
        selectResult(at: item.index)
        activate(item.row)
    }

    /// Runs the button of `row`'s answer that Return runs, answering whether
    /// it ran.
    func runAnswer(_ row: PaletteRow) -> BrowserCommandPaletteCommandRegistry.Result {
        guard isCompletionSourceAvailable, let card = row.answer,
            let item = items.first(where: { $0.row == row })
        else { return .unsupported }
        return answerControl(for: item).run(card, self)
    }

    func canPerformAnswerAction(of card: AnswerCard) -> Bool {
        guard isActive, isCompletionSourceAvailable, let action = card.action else { return false }
        return commands?.supports(action) == true
    }

    /// Only curated actions reach this registry; generated answers remain text-only.
    func performAnswerAction(of card: AnswerCard) -> BrowserCommandPaletteCommandRegistry.Result {
        guard canPerformAnswerAction(of: card), let action = card.action, let commands else { return .unsupported }
        return commands.perform(action)
    }

    func performCommand(_ command: ShortcutCommand) -> BrowserCommandPaletteCommandRegistry.Result {
        guard isCompletionSourceAvailable, let commands else { return .unsupported }
        return commands.perform(command)
    }

    func openSettingsPage(_ page: String) -> BrowserCommandPaletteCommandRegistry.Result {
        guard isCompletionSourceAvailable, let commands else { return .unsupported }
        return commands.openSettings(page)
    }

    /// Does what Return does to a card row: copies its value, shows its word
    /// in the device's dictionary, or opens its address where the keys
    /// choose, answering whether it did.
    func runCard(_ row: PaletteRow) -> Bool {
        guard let card = row.card else { return false }
        if card.kind == .translation || card.kind == .generativeAnswer {
            guard isCompletionSourceAvailable else { return false }
        }
        if card.kind == .generativeAnswer, card.value == nil { return false }
        if card.kind == .translation, card.value == nil {
            retryTranslation()
            return false
        }
        if card.kind.copiesValue {
            guard let item = items.first(where: { $0.row == row }), canCopyCard(item),
                let value = BrowserCommandPaletteCardText.copied(card), let commands
            else { return false }
            commands.copy(value)
            return true
        }
        if card.kind.looksUpTerm, let term = card.term { return lookups.showInDictionary(term) }
        return open(card.address, where: opening(for: row))
    }

    /// Opens the guide `card` comes from in a new tab where the platform can.
    func openGuide(of card: AnswerCard) -> Bool {
        open(card.guide, where: openings.contains(.newTab) ? .newTab : .here)
    }

    /// Moves to the next or previous button of the selected answer, answering
    /// whether the answer had another.
    private func moveAnswerControl(by offset: Int) -> Bool {
        guard shownSequence == sequence, items.indices.contains(selectedResultIndex),
            let card = items[selectedResultIndex].row.answer
        else { return false }
        let offered = BrowserCommandPaletteAnswerControl.offered(for: card, in: self)
        let item = items[selectedResultIndex]
        guard offered.count > 1, let current = offered.firstIndex(of: answerControl(for: item)) else { return false }
        answerChoice = (item.id, offered[(current + offset + offered.count) % offered.count])
        return true
    }

    // MARK: - Actions - Selection

    func moveSelection(by offset: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, !items.isEmpty else { return }
        selectResult(at: (selectedResultIndex + offset + items.count) % items.count)
        keyboardSelectionRevision &+= 1
    }

    /// Moves to the first row of the next or previous section.
    func moveSection(by offset: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, !groups.isEmpty,
            let current = groups.firstIndex(where: { $0.items.contains { $0.index == selectedResultIndex } }),
            let first = groups[(current + offset + groups.count) % groups.count].items.first
        else { return }
        selectResult(at: first.index)
        keyboardSelectionRevision &+= 1
    }

    func selectResult(at index: Int, expandsAnswer: Bool = true) {
        rejectURLCompletion()
        guard shownSequence == sequence, items.indices.contains(index) else { return }
        selectedResultIndex = index
        if expandsAnswer { expandedAnswerID = items[index].row.answer != nil ? items[index].id : nil }
    }

    /// Forgets the row the person moved to: a row whose kind forgets from
    /// history takes its page out of the Space's history, and what the palette
    /// learned about the row goes. The row the palette leads with is never
    /// forgotten this way.
    @discardableResult
    func forgetSelectedRow() -> Bool {
        guard selectedResultIndex > 0, items.indices.contains(selectedResultIndex) else { return false }
        let row = items[selectedResultIndex].row
        guard row.kind.forgetsFromHistory || row.reason == .learned else { return false }
        if row.kind.forgetsFromHistory, let address = row.address, let space {
            browser.removeHistoryAddress(address, in: space.id)
        }
        try? browser.core.send(
            ForgetPaletteChoices(windowID: browser.windowID, row: row.seed, spaceID: destination?.paletteSpaceID))
        requestAnswer()
        return true
    }

    func activateSelectedResult() {
        guard items.indices.contains(selectedResultIndex) else { return }
        activate(items[selectedResultIndex].row)
    }

    /// Runs `row` as its kind's activation does. One that closes the palette
    /// has it remember the pick for what was typed and close; one that
    /// narrows it, to a provider or a scope, leaves it open.
    func activate(_ row: PaletteRow) {
        guard isActive, shownSequence == sequence else { return }
        let activation = row.kind.activation
        let typed = query
        guard let result = BrowserCommandPaletteActivation.of(activation)?.run(row, self),
            result.wasPerformed, activation.closesPalette
        else { return }
        if !keepsQueryPrivate {
            try? browser.core.send(
                RecordPaletteChoice(
                    windowID: browser.windowID, text: typed, row: row.seed, spaceID: destination?.paletteSpaceID))
        }
        if result.managesPresentation {
            // Native commands own the overlay. Retire a replaced palette,
            // but keep an embedded editor usable after that overlay closes.
            isActive = !presentation.closesOnExit
            cancelPendingWork()
            groups = []
            items = []
            invalidateURLCompletion()
        } else {
            dismiss()
        }
    }

    func dismiss() {
        isCopySessionActive = false
        cancelPendingWork()
        // Embedded palettes may keep their current results after copying.
        // Native presentation changes instead revoke those results above.
        shownSequence = sequence
        dismissAction()
    }

    private func cancelPendingWork() {
        resetCopiedFeedback()
        sequence &+= 1
        waitingKey = nil
        keyWaitTask?.cancel()
        answerTask?.cancel()
        cancelGenerativeAnswer()
        translationPreparation = nil
    }

    /// A temporary source loss revokes work but does not tear down a mounted
    /// editor. If its assignment becomes usable again, answer its current text.
    func sourceAvailabilityChanged(_ available: Bool) {
        resetCopiedFeedback()
        invalidateURLCompletion()
        sequence &+= 1
        waitingKey = nil
        keyWaitTask?.cancel()
        answerTask?.cancel()
        cancelGenerativeAnswer()
        translationPreparation = nil
        translationResult = nil
        groups = []
        items = []
        if available { requestAnswer() }
    }

    /// Ends this presentation, including work a provider might not cancel
    /// cooperatively. No query-bearing answer survives closing the palette.
    func stop() {
        resetCopiedFeedback()
        isFieldFocused = false
        isActive = false
        sequence &+= 1
        waitingKey = nil
        keyWaitTask?.cancel()
        answerTask?.cancel()
        answerTask = nil
        cancelGenerativeAnswer()
        translationPreparation = nil
        translationResult = nil
        groups = []
        items = []
        completionProposal = nil
        completionEditing = BrowserURLCompletionEditingState()
        pasteboard = nil
        openedWith = ""
        query = ""
    }

    func waitForPendingResults() async {
        await answerTask?.value
        while let generationTask { await generationTask.value }
    }

    func preferencesChanged() { requestAnswer() }

    // MARK: - Actions - Activation

    /// Shows the tab `tabID` names in the palette's Space, from the tab the
    /// palette opened over or from its destination.
    func switchToTab(_ tabID: UUID?) -> Bool {
        guard let tabID else { return false }
        if selectedTabID == nil {
            guard let destination = availableDestination, let space else { return false }
            return destination.selectTab(
                BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID))
        }
        guard let sourceAssignment = availableSourceAssignment else { return false }
        return selectTabAction(
            sourceAssignment,
            BrowserTabRuntimeAssignment(
                tabID: tabID, spaceID: sourceAssignment.spaceID, profileID: sourceAssignment.profileID))
    }

    /// Opens `address` where `opening` says, from the tab the palette opened
    /// over, or in its destination, which opens it in place.
    func open(_ address: String?, where opening: BrowserCommandPaletteOpening) -> Bool {
        guard browser.workspaceModel?.kind.isPractice != true else { return false }
        guard let url = address.flatMap(URL.init(string:)) else { return false }
        if selectedTabID == nil { return availableDestination?.openURL(url) ?? false }
        guard let sourceAssignment = availableSourceAssignment else { return false }
        return openURLAction(sourceAssignment, url, opening)
    }

    /// Where `row` opens while the person holds the keys they hold: where the
    /// keys choose for a row whose activation lets them, else here. Shift on
    /// a search with a first result opens that result, as in Arc, or the
    /// search here while the device is offline; on any other row it keeps
    /// opening Split View.
    func opening(for row: PaletteRow) -> BrowserCommandPaletteOpening {
        guard opensWhereKeysChoose(row) else { return .here }
        if row.topResult != nil, heldModifiers == [.shift] { return lookups.isOnline() ? .topResult : .here }
        return BrowserCommandPaletteOpening.held(heldModifiers, among: openings)
    }

    /// What Shift-Return does to `row`, which the selected row says while no
    /// keys are held: open a search's first result, or open the row in Split
    /// View; nil where Shift-Return opens it as Return does.
    func shiftReturnOpening(for row: PaletteRow) -> BrowserCommandPaletteOpening? {
        guard opensWhereKeysChoose(row) else { return nil }
        if row.topResult != nil { return lookups.isOnline() ? .topResult : nil }
        let held = BrowserCommandPaletteOpening.held([.shift], among: openings)
        return held == .here ? nil : held
    }

    /// Whether the keys a person holds choose where `row` opens: rows whose
    /// activation lets them, except a card that opens nothing.
    private func opensWhereKeysChoose(_ row: PaletteRow) -> Bool {
        row.kind.activation.opensWhereKeysChoose && (row.card == nil || row.card?.address != nil)
    }

    /// The address `row` opens `opening`: its first result for the top
    /// result, else its own address.
    func address(of row: PaletteRow, opening: BrowserCommandPaletteOpening) -> String? {
        opening == .topResult ? row.topResult : row.address
    }

    /// The palette's destination, when it opens into the palette's Space and
    /// can act now.
    private var availableDestination: (any BrowserPaletteDestination)? {
        guard let destination, let space,
            destination.source == BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID),
            destination.isAvailable
        else { return nil }
        return destination
    }

    // MARK: - Actions - Presentation

    /// The tab a row shows, for its icon.
    func tab(for row: PaletteRow) -> TabStateModel? {
        row.tabID.flatMap { space?.shownTab($0) }
    }

    /// The engine a row's tab runs on, when its icon wears that engine's
    /// badge, for what the row says to VoiceOver.
    func engineBadge(for row: PaletteRow) -> EngineKind? {
        row.tabID.flatMap(browser.core.state.engineBadge(forTab:))
    }

    /// The search provider a row searches with, for its icon.
    func searchProvider(for row: PaletteRow) -> SearchProvider? {
        row.provider
    }

    // MARK: - Actions - Answers

    /// The question for `text`, with the commands and settings pages this
    /// window offers, the suggestions fetched for the same text, the scope
    /// the person narrowed to, and whether the field may complete inline.
    private func question(for text: String, remote: [String] = []) -> PaletteSuggestions {
        PaletteSuggestions(
            windowID: browser.windowID, text: text, commands: offeredCommands(for: text),
            settingsPages: commands?.settingsPages ?? [], remote: remote, provider: activeProvider?.seed,
            scope: activeScope, allowsCompletion: completionEditing.canPropose(for: text),
            pasteboard: text.isEmpty || text == openedWith ? pasteboard : nil, definition: nil, webSummary: nil,
            spaceID: destination?.paletteSpaceID, translation: nil, generative: nil)
    }

    /// The commands the core may rank for `text`. A palette without resting
    /// commands offers none while the text is blank, which the core reads as
    /// nothing typed.
    private func offeredCommands(for text: String) -> [PaletteCommand] {
        guard offersRestingCommands || !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return commands?.paletteCommands ?? []
    }

    /// Asks the core for the current query's answer off the main thread,
    /// then for the definition the device's dictionary holds for the word the
    /// answer names, then, after a pause, for the search suggestions and the
    /// encyclopedia summary the answer allows, and shows each only while no
    /// later keystroke has asked again, keeping the row the person had
    /// selected.
    private func requestAnswer() {
        guard isActive else { return }
        isCopySessionActive = true
        resetCopiedFeedback()
        cancelGenerativeAnswer()
        translationResult = nil
        translationPreparation = nil
        waitingKey = nil
        sequence &+= 1
        let asked = sequence
        var question = question(for: query)
        let answerQuestion = fetchAnswer
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            guard var answer = await answerQuestion(question), !Task.isCancelled, let self,
                asked == sequence
            else { return }
            guard canApply(asked) else { return }
            show(answer, for: asked)
            if await answerOnDevice(answer, question: question, for: asked) { return }
            if let term = answer.definitionTerm, let definition = await lookups.definition(term) {
                question = question.answering(definition: definition)
                guard let defined = await answerQuestion(question), asked == sequence else { return }
                merge(defined, for: asked)
                answer = defined
            }
            // A preference change must not turn the same already-private
            // input into a background network query. A new edit owns new intent.
            guard !keepsQueryPrivate else { return }
            let address = answer.suggestionAddress.flatMap(URL.init(string:))
            let lookup = answer.webLookup
            guard address != nil || lookup != nil else { return }
            do {
                try await Task.sleep(for: lookups.suggestionDebounce)
            } catch {
                return
            }
            let fetch = lookups.webSummary
            async let summary = Self.summary(for: lookup, with: fetch)
            if let address {
                // The local rows are already shown. A failed fetch or an
                // unreadable response leaves them as they are.
                let fetched = (try? await lookups.suggestions(address)) ?? []
                guard !Task.isCancelled, asked == sequence else { return }
                if !fetched.isEmpty, let merged = await answerQuestion(question.answering(remote: fetched)),
                    asked == sequence
                {
                    question = question.answering(remote: fetched)
                    merge(merged, for: asked)
                }
            }
            guard let found = await summary, !Task.isCancelled, asked == sequence,
                let summarized = await answerQuestion(question.answering(webSummary: found)), asked == sequence
            else { return }
            merge(summarized, for: asked)
        }
    }

    /// Shows a later answer for the same keystroke, keeping the row the
    /// person had selected.
    private func merge(_ answer: PaletteAnswer, for asked: Int) {
        let selected = items.indices.contains(selectedResultIndex) ? items[selectedResultIndex].id : nil
        show(answer, for: asked)
        if let selected, let index = items.firstIndex(where: { $0.id == selected }) {
            selectedResultIndex = index
        }
    }

    private func show(_ answer: PaletteAnswer, for asked: Int) {
        guard canApply(asked) else { return }
        if shownSequence != asked {
            resultSetRevision &+= 1
            expandedAnswerID = nil
        }
        shownSequence = asked
        keepsQueryPrivate = keepsQueryPrivate || answer.keepsQueryPrivate
        let copiedCard = items.first { $0.id == copiedCardID }?.row.card
        groups = BrowserCommandPaletteGroup.groups(of: answer)
        items = groups.flatMap(\.items)
        // The core never offers a generative lookup alongside a deterministic numeric card.
        // This provenance belongs to this exact result set; canCopyCard also checks exact item membership.
        shownAnswerRequiresAskOde = answer.generativeLookup != nil
        if copiedCard != items.first(where: { $0.id == copiedCardID })?.row.card { resetCopiedFeedback() }
        completionProposal = answer.completion
        offeredSearch = answer.offeredSearch
        matchingProviders = answer.matchingProviders
        offeredScope = answer.offeredScope
        if !items.indices.contains(selectedResultIndex) { selectedResultIndex = 0 }
        // A key waiting on this answer acts once the entry's own answer arrives.
        if asked == sequence, isUnscoped, let entry = answer.entry { enter(entry) }
        if asked == sequence, waitingKey != nil { runWaitingKey() }
    }

    private func answerOnDevice(_ answer: PaletteAnswer, question: PaletteSuggestions, for asked: Int) async -> Bool {
        if let lookup = answer.translationLookup {
            await translate(lookup, question: question, for: asked)
            return true
        }
        if let lookup = answer.generativeLookup {
            await prepareGenerativeAnswer(lookup, question: question, for: asked)
            return true
        }
        return false
    }

    // MARK: - Actions - Private answers

    func retryGenerativeAnswer() { requestAnswer() }

    private func cancelGenerativeAnswer() {
        pendingGeneration = nil
        generativeResult = nil
        // Keep the task slot until even a noncooperative provider returns.
        // Edits can replace one pending request, never build an unbounded queue.
        generationTask?.cancel()
    }

    private func prepareGenerativeAnswer(
        _ lookup: PaletteGenerativeLookup, question: PaletteSuggestions, for asked: Int
    ) async {
        do { try await Task.sleep(for: lookups.generativeDebounce) } catch { return }
        guard canApplyGenerativeAnswer(asked) else { return }
        pendingGeneration = BrowserPalettePendingGeneration(lookup: lookup, question: question, sequence: asked)
        startNextGenerativeAnswer()
    }

    private func startNextGenerativeAnswer() {
        guard generationTask == nil, let pending = pendingGeneration else { return }
        pendingGeneration = nil
        let generate = lookups.generativeAnswer
        generationTask = Task { [weak self] in
            let result = await generate(pending.lookup)
            guard let self else { return }
            if canApplyGenerativeAnswer(pending.sequence) {
                generativeResult = result
                if let enriched = await fetchAnswer(pending.question.answering(generative: result)),
                    canApplyGenerativeAnswer(pending.sequence)
                {
                    merge(enriched, for: pending.sequence)
                }
            }
            generationTask = nil
            startNextGenerativeAnswer()
        }
    }

    private func canApplyGenerativeAnswer(_ asked: Int) -> Bool { canApply(asked) && isCompletionSourceAvailable }

    // MARK: - Actions - Translation

    func retryTranslation() { requestAnswer() }

    private func translate(_ lookup: PaletteTranslationLookup, question: PaletteSuggestions, for asked: Int) async {
        do { try await Task.sleep(for: lookups.suggestionDebounce) } catch { return }
        guard canApplyTranslation(asked) else { return }
        let translated = await lookups.translation(lookup)
        guard canApplyTranslation(asked) else { return }
        translationResult = translated
        guard let enriched = await fetchAnswer(question.answering(translation: translated)), canApplyTranslation(asked)
        else {
            return
        }
        merge(enriched, for: asked)
    }

    private func canApplyTranslation(_ asked: Int) -> Bool { canApply(asked) && isCompletionSourceAvailable }

    /// Only this explicit action creates a host that may ask Apple to download.
    func downloadTranslationLanguages() {
        guard isActive, let result = translationResult, result.status == .notInstalled,
            let source = result.sourceLanguage, !completionEditing.isComposing
        else { return }
        let asked = sequence
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: result.lookup.targetLanguage)
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            var configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
            if #available(macOS 26.4, iOS 26.4, *) {
                let status = await BrowserTranslationPreference.languageAvailability(lowLatency: true)
                    .status(from: sourceLanguage, to: targetLanguage)
                if status != .unsupported {
                    configuration = TranslationSession.Configuration(
                        source: sourceLanguage, target: targetLanguage, preferredStrategy: .lowLatency)
                }
            }
            guard let self, canApplyTranslation(asked) else { return }
            translationPreparation = BrowserPaletteTranslationPreparation(
                lookup: result.lookup, sequence: asked, configuration: configuration)
        }
    }

    func prepareTranslation(using session: TranslationSession, preparation: BrowserPaletteTranslationPreparation) async
    {
        guard canApplyTranslation(preparation.sequence), translationPreparation != nil else { return }
        do {
            try await session.prepareTranslation()
            guard canApplyTranslation(preparation.sequence), translationPreparation != nil else { return }
            translationPreparation = nil
            retryTranslation()
        } catch {
            guard canApplyTranslation(preparation.sequence) else { return }
            translationPreparation = nil
            let failed = PaletteTranslationResult(
                lookup: preparation.lookup, sourceLanguage: preparation.lookup.sourceLanguage, text: nil,
                status: .failed)
            translationResult = failed
            if let answer = await fetchAnswer(question(for: query).answering(translation: failed)),
                canApplyTranslation(preparation.sequence)
            {
                merge(answer, for: preparation.sequence)
            }
        }
    }

    private func canApply(_ asked: Int) -> Bool {
        isActive && !Task.isCancelled && asked == sequence && !completionEditing.isComposing
    }

    /// The encyclopedia summary `lookup` finds through `fetch`, or nil
    /// without a lookup.
    private nonisolated static func summary(
        for lookup: PaletteWebLookup?, with fetch: @Sendable (PaletteWebLookup) async -> PaletteWebSummary?
    ) async -> PaletteWebSummary? {
        guard let lookup else { return nil }
        return await fetch(lookup)
    }

    /// The core's answer, ranked on a background thread.
    private nonisolated static func answer(_ question: PaletteSuggestions, from core: OdeCore) async -> PaletteAnswer? {
        await Task.detached(priority: .userInitiated) { try? core.query(question) }.value
    }
}

extension PaletteSuggestions {
    /// These transient results never cross into the persistent session.
    func answering(
        remote: [String]? = nil, definition: PaletteDefinition? = nil, webSummary: PaletteWebSummary? = nil,
        translation: PaletteTranslationResult? = nil, generative: PaletteGenerativeResult? = nil
    ) -> PaletteSuggestions {
        PaletteSuggestions(
            windowID: windowID, text: text, commands: commands, settingsPages: settingsPages,
            remote: remote ?? self.remote,
            provider: provider, scope: scope, allowsCompletion: allowsCompletion, pasteboard: pasteboard,
            definition: definition ?? self.definition, webSummary: webSummary ?? self.webSummary, spaceID: spaceID,
            translation: translation ?? self.translation, generative: generative ?? self.generative)
    }
}

extension PalettePreferences {
    /// Whether the palette offers results of `source`.
    func offers(_ source: PaletteSource) -> Bool {
        sources.first { $0.source == source }?.isEnabled ?? false
    }
}
