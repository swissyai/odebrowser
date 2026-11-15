import AppKit
import Observation

/// One window's short tour. Only its final disposition is persisted; neither
/// queries nor keyboard input enter that record.
@Observable
@MainActor
final class BrowserGettingStartedTour {
    // MARK: - Types

    enum Step: Int {
        case commandBar, answer, sidebar, finished
    }

    enum Disposition: String {
        case completed, dismissed
    }

    // MARK: - Static Variables

    static let defaultsKey = "GettingStarted.TourDisposition"

    // MARK: - Variables

    private(set) var guide: BrowserTabRuntimeAssignment?
    private(set) var step = Step.commandBar
    private(set) var confirmation: Step?
    private(set) var completedShortcut: BrowserShortcut?
    private(set) var heldShortcut: BrowserShortcut?
    private(set) var pressedModifiers: ShortcutModifiers = []
    private(set) var answerIsReady = false
    private(set) var answerIsAvailable = false
    private(set) var sidebarChanges = 0
    private(set) var disposition: Disposition?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private weak var browser: BrowserStore?
    @ObservationIgnored private weak var chrome: BrowserChromeState?
    @ObservationIgnored private weak var hostWindow: NSWindow?
    @ObservationIgnored private var copyAnswerAction: (@MainActor () -> Bool)?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var focusObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var heldKeyCode: UInt16?
    @ObservationIgnored private var originalSidebar = true
    @ObservationIgnored private var lastSidebar = true

    var confirmed: Bool { confirmation != nil }
    var isRunning: Bool { guide != nil }
    var sidebarIsPresented: Bool { chrome?.columnVisibility != .detailOnly }
    var isCommandBarPresented: Bool { chrome?.isCommandPalettePresented == true }

    var expectedShortcut: BrowserShortcut? {
        if step == .commandBar { return shortcut(for: .newTab) }
        if step == .answer {
            if !isCommandBarPresented { return shortcut(for: .newTab) }
            if answerIsReady { return BrowserShortcut(key: .special(.tab), modifiers: []) }
        }
        if step == .sidebar { return shortcut(for: .toggleSidebar) }
        if step == .finished, !isCommandBarPresented { return shortcut(for: .newTab) }
        return nil
    }

    var isShowingGuide: Bool {
        guard let guide, let browser, !browser.isPrivateBrowsing,
            let space = browser.shownSpace,
            space.id == guide.spaceID, space.profileID == guide.profileID,
            browser.selectedTabID(in: space.id) == guide.tabID,
            space.tabs.model(guide.tabID)?.nativeTabContent == .gettingStarted
        else { return false }
        return true
    }

    private var acceptsKeyboardInput: Bool {
        isShowingGuide && NSApp.isActive && hostWindow?.isKeyWindow == true
            && hostWindow?.attachedSheet == nil && NSApp.modalWindow == nil
    }

    // MARK: - Initializers

    init(defaults: UserDefaults?, browser: BrowserStore, chrome: BrowserChromeState) {
        self.defaults = defaults
        self.browser = browser
        self.chrome = chrome
        disposition = defaults?.string(forKey: Self.defaultsKey).flatMap(Disposition.init(rawValue:))
    }

    isolated deinit {
        stopKeyboardObservation()
    }

    // MARK: - Actions - Lifecycle

    func attach(to window: NSWindow) {
        hostWindow = window
        if isRunning { startKeyboardObservation() }
    }

    func start(_ assignment: BrowserTabRuntimeAssignment, automatically: Bool) {
        guard let browser, !browser.isPrivateBrowsing, !browser.isTemporaryWorkspace,
            !automatically || disposition == nil,
            let space = browser.shownSpace,
            space.id == assignment.spaceID, space.profileID == assignment.profileID,
            browser.selectedTabID(in: space.id) == assignment.tabID,
            space.tabs.model(assignment.tabID)?.nativeTabContent == .gettingStarted
        else { return }
        stopKeyboardObservation()
        guide = assignment
        step = .commandBar
        clearConfirmation()
        answerIsReady = false
        answerIsAvailable = false
        copyAnswerAction = nil
        sidebarChanges = 0
        originalSidebar = sidebarIsPresented
        lastSidebar = originalSidebar
        startKeyboardObservation()
    }

    func replay() {
        guard let browser, let space = browser.shownSpace, let tab = browser.shownTab,
            tab.nativeTabContent == .gettingStarted
        else { return }
        start(
            BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
            automatically: false)
    }

    func dismiss(completed: Bool = false) {
        guard isRunning else { return }
        if isShowingGuide, step == .sidebar, sidebarChanges == 1,
            let chrome, sidebarIsPresented == lastSidebar, lastSidebar != originalSidebar
        {
            chrome.sidebarToggle?()
        }
        disposition = completed ? .completed : .dismissed
        defaults?.set(disposition?.rawValue, forKey: Self.defaultsKey)
        stopKeyboardObservation()
        guide = nil
        copyAnswerAction = nil
        answerIsReady = false
        answerIsAvailable = false
        clearConfirmation()
    }

    func finishBrowsing(completed: Bool = true) {
        guard isShowingGuide, let guide, let browser else {
            dismiss(completed: completed)
            return
        }
        chrome?.dismissCommandPalette()
        dismiss(completed: completed)
        browser.dismissNativeTab(
            guide.tabID, matching: BrowserSpaceRuntimeAssignment(spaceID: guide.spaceID, profileID: guide.profileID))
    }

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        browser?.core.state.shortcuts[command]?.keys.flatMap(BrowserShortcut.init(boundKeys:))
    }

    func copyAnswer() -> Bool {
        guard isShowingGuide, step == .answer, answerIsReady else { return false }
        return copyAnswerAction?() == true
    }

    // MARK: - Actions - Native cancellation

    func handleCancel(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
            BrowserShortcut(event: event) == BrowserShortcut(key: .special(.escape), modifiers: []),
            isShowingGuide, !isCommandBarPresented
        else { return false }
        finishBrowsing(completed: false)
        return true
    }

    // MARK: - Actions - Real outcomes

    func commandBarOpened() {
        guard isShowingGuide, step == .commandBar else { return }
        confirmation = .commandBar
        completedShortcut = shortcut(for: .newTab)
        step = .answer
    }

    /// Receives only a revocable copy action, never the query or result value.
    func offerAnswer(_ copy: (@MainActor () -> Bool)?, hasNumericAnswer: Bool) {
        guard isShowingGuide, step == .answer, isCommandBarPresented else {
            copyAnswerAction = nil
            answerIsReady = false
            answerIsAvailable = false
            return
        }
        copyAnswerAction = copy
        answerIsReady = copy != nil
        answerIsAvailable = hasNumericAnswer
        if answerIsReady { clearConfirmation() }
    }

    func copiedCard(_ kind: PaletteCardKind) {
        guard isShowingGuide, isCommandBarPresented, step == .answer,
            kind == .calculation || kind == .conversion
        else { return }
        confirmation = .answer
        completedShortcut = BrowserShortcut(key: .special(.tab), modifiers: [])
        step = .sidebar
        copyAnswerAction = nil
        answerIsReady = false
        answerIsAvailable = false
        originalSidebar = sidebarIsPresented
        lastSidebar = originalSidebar
        chrome?.dismissCommandPalette()
    }

    func sidebarChanged(isPresented: Bool) {
        guard isShowingGuide, step == .sidebar, isPresented != lastSidebar else { return }
        lastSidebar = isPresented
        sidebarChanges += 1
        confirmation = .sidebar
        completedShortcut = shortcut(for: .toggleSidebar)
        if sidebarChanges >= 2, isPresented == originalSidebar { step = .finished }
    }

    func clearConfirmation() {
        confirmation = nil
        completedShortcut = nil
    }

    // MARK: - Actions - Expected keys

    /// The shell calls this before routing a key down. It never consumes it.
    func observeKeyDown(_ event: NSEvent) {
        guard acceptsKeyboardInput, event.window == nil || event.window === hostWindow else { return }
        updateKeyState(event)
    }

    /// Tracks only the expected chord. Unrelated keys and input text are not retained.
    func updateKeyState(_ event: NSEvent) {
        guard isShowingGuide else { return }
        let modifiers = ShortcutModifiers(event.modifierFlags)
        // A released modifier ends the chord even when its key-up is absent.
        if let heldShortcut, !modifiers.isSuperset(of: heldShortcut.modifiers) {
            self.heldShortcut = nil
            heldKeyCode = nil
        }
        if event.type == .keyUp {
            if event.keyCode == heldKeyCode {
                heldKeyCode = nil
                heldShortcut = nil
            }
            pressedModifiers = modifiers.intersection(expectedShortcut?.modifiers ?? [])
            return
        }
        let expected = heldShortcut ?? expectedShortcut
        guard let expected else {
            pressedModifiers = []
            return
        }
        pressedModifiers = modifiers.intersection(expected.modifiers)
        guard event.type == .keyDown, !event.isARepeat, modifiers == expected.modifiers else { return }
        if case .special(let key) = expected.key, ShortcutSpecialKey(keyCode: event.keyCode) != key { return }
        guard BrowserShortcut(event: event) == expected
        else { return }
        clearConfirmation()
        heldKeyCode = event.keyCode
        heldShortcut = expected
    }

    func pressedKeys(for shortcut: BrowserShortcut) -> Set<Int> {
        let modifiers: [ShortcutModifiers] = [.control, .option, .shift, .command]
        let shown = modifiers.filter { shortcut.modifiers.contains($0) }
        var keys = Set(shown.enumerated().compactMap { pressedModifiers.contains($0.element) ? $0.offset : nil })
        if heldShortcut == shortcut, heldKeyCode != nil { keys.insert(shown.count) }
        return keys
    }

    func resetPressedKeys() {
        pressedModifiers = []
        heldShortcut = nil
        heldKeyCode = nil
    }

    // MARK: - Actions - Observation lifetime

    private func startKeyboardObservation() {
        guard let hostWindow else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            focusObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.suspendKeyboardObservation() }
                })
        }
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
            focusObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resumeKeyboardObservation() }
                })
        }
        focusObservers.append(
            center.addObserver(forName: NSWindow.willCloseNotification, object: hostWindow, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.dismiss() }
            })
        resumeKeyboardObservation()
    }

    private func resumeKeyboardObservation() {
        guard keyMonitor == nil, acceptsKeyboardInput else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.acceptsKeyboardInput, event.window == nil || event.window === self.hostWindow else {
                return event
            }
            self.updateKeyState(event)
            return event
        }
    }

    private func suspendKeyboardObservation() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        resetPressedKeys()
    }

    private func stopKeyboardObservation() {
        suspendKeyboardObservation()
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
        focusObservers = []
    }
}
