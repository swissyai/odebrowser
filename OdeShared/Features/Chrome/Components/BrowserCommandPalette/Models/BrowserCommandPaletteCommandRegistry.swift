import Foundation

/// Commands, settings pages and the window's own actions, supplied by the
/// presenting platform shell, which palette rows other than addresses and
/// tabs perform, and which a written answer's "Do it" runs.
@MainActor
struct BrowserCommandPaletteCommandRegistry {
    // MARK: - Static Variables

    /// Commands with their titles, kept per locale for repeated ranking.
    private static var titled: (locale: Locale, commands: [ShortcutCommand: PaletteCommand])?

    // MARK: - Types

    struct Result: Equatable, Sendable {
        // MARK: - Static Variables

        static let unsupported = Result(wasPerformed: false, managesPresentation: false)
        static let performed = Result(wasPerformed: true, managesPresentation: false)
        static let performedManagingPresentation = Result(wasPerformed: true, managesPresentation: true)

        // MARK: - Variables

        let wasPerformed: Bool
        let managesPresentation: Bool

        // MARK: - Initializers

        private init(wasPerformed: Bool, managesPresentation: Bool) {
            self.wasPerformed = wasPerformed
            self.managesPresentation = managesPresentation
        }
    }

    // MARK: - Variables

    let commands: [ShortcutCommand]
    /// The settings pages the palette may open, by their settings name.
    let settingsPages: [PaletteSettingsPage]
    private let shortcutProvider: (ShortcutCommand) -> BrowserShortcut?
    private let performer: ((ShortcutCommand) -> Result)?
    /// Curated actions may name native commands intentionally absent from ranked rows.
    private let supportedCommands: [ShortcutCommand]
    private let commandAvailability: (ShortcutCommand) -> Bool
    private let settingsOpener: ((String) -> Bool)?
    private let spaceSettingsOpener: ((String) -> Bool)?
    private let spaceSettingsPages: [String]
    private let applicationActionRunner: ((String) -> Bool)?
    private let applicationActions: [String]
    private let spaceSwitcher: (UUID) -> Void
    private let archiveReopener: (UUID) -> Void
    private let copier: ((String) -> Void)?
    private let inlineCopier: ((String) -> Bool)?
    var canCopy: Bool { inlineCopier != nil || copier != nil }
    /// What a command is called now, where that follows what the window
    /// shows, such as Show Tabs on Top; nil for its own title.
    private let currentTitle: (ShortcutCommand) -> LocalizedStringResource?

    // MARK: - Initializers

    init(
        commands: [ShortcutCommand],
        supportedCommands: [ShortcutCommand]? = nil,
        settingsPages: [PaletteSettingsPage] = [],
        shortcut: @escaping (ShortcutCommand) -> BrowserShortcut? = { _ in nil },
        perform: ((ShortcutCommand) -> Void)? = nil,
        dispatch: ((ShortcutCommand) -> Result)? = nil,
        canPerform: @escaping (ShortcutCommand) -> Bool = { _ in true },
        openSettings: ((String) -> Bool)? = nil,
        spaceSettingsPages: [String] = [],
        openSpaceSettings: ((String) -> Bool)? = nil,
        applicationActions: [String] = [],
        runApplicationAction: ((String) -> Bool)? = nil,
        switchSpace: @escaping (UUID) -> Void = { _ in },
        reopenArchivedTab: @escaping (UUID) -> Void = { _ in },
        copy: ((String) -> Void)? = nil,
        copyInline: ((String) -> Bool)? = nil,
        currentTitle: @escaping (ShortcutCommand) -> LocalizedStringResource? = { _ in nil }
    ) {
        self.commands = commands
        self.supportedCommands = supportedCommands ?? commands
        self.settingsPages = settingsPages
        shortcutProvider = shortcut
        // Simple explicitly supplied handlers acknowledge dispatch by returning.
        // Native adapters use dispatch to report refusal or presentation ownership.
        performer =
            dispatch
            ?? perform.map { action in
                { command in
                    action(command)
                    return .performed
                }
            }
        commandAvailability = canPerform
        settingsOpener = openSettings
        self.spaceSettingsPages = spaceSettingsPages
        spaceSettingsOpener = openSpaceSettings
        self.applicationActions = applicationActions
        applicationActionRunner = runApplicationAction
        spaceSwitcher = switchSpace
        archiveReopener = reopenArchivedTab
        copier = copy
        inlineCopier = copyInline
        self.currentTitle = currentTitle
    }

    // MARK: - Actions - Ranking

    /// The commands as the palette ranks them, with the titles this device
    /// shows for them.
    var paletteCommands: [PaletteCommand] {
        let locale = Locale.current
        if Self.titled?.locale != locale { Self.titled = (locale, [:]) }
        return commands.map { command in
            var titled: PaletteCommand
            if let cached = Self.titled?.commands[command] {
                titled = cached
            } else {
                titled = PaletteCommand(
                    command: command, title: command.title(locale: locale),
                    sectionTitle: command.section.title(locale: locale))
                Self.titled?.commands[command] = titled
            }
            if let current = currentTitle(command) {
                var localized = current
                localized.locale = locale
                titled.title = String(localized: localized)
            }
            return titled
        }
    }

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        shortcutProvider(command)
    }

    // MARK: - Actions - Dispatch

    func supports(_ action: AnswerAction) -> Bool {
        if let command = action.command { return supports(command) }
        if let page = action.settingsPage { return settingsOpener != nil && settingsPages.contains { $0.name == page } }
        if let page = action.spacePage { return spaceSettingsOpener != nil && spaceSettingsPages.contains(page) }
        if let name = action.applicationAction {
            return applicationActionRunner != nil && applicationActions.contains(name)
        }
        return false
    }

    func supports(_ command: ShortcutCommand) -> Bool {
        performer != nil && supportedCommands.contains(command) && commandAvailability(command)
    }

    @discardableResult
    func perform(_ command: ShortcutCommand) -> Result {
        guard supports(command), let performer else { return .unsupported }
        return performer(command)
    }

    func perform(_ action: AnswerAction) -> Result {
        guard supports(action) else { return .unsupported }
        if let command = action.command { return perform(command) }
        if let page = action.settingsPage { return openSettings(page) }
        if let page = action.spacePage {
            return spaceSettingsOpener?(page) == true ? .performed : .unsupported
        }
        if let name = action.applicationAction {
            return runApplicationAction(name) ? .performed : .unsupported
        }
        return .unsupported
    }

    /// A named page is supported only when a real opener was supplied.
    func openSettings(_ name: String) -> Result {
        guard supports(AnswerAction(settingsPage: name)) else { return .unsupported }
        return settingsOpener?(name) == true ? .performed : .unsupported
    }

    /// Runs an explicitly supported application menu action, answering whether it ran.
    func runApplicationAction(_ name: String) -> Bool {
        guard applicationActions.contains(name) else { return false }
        return applicationActionRunner?(name) == true
    }

    func switchSpace(_ id: UUID) {
        spaceSwitcher(id)
    }

    func reopenArchivedTab(_ id: UUID) {
        archiveReopener(id)
    }

    /// Existing Return activations may report through the window's notice.
    func copy(_ text: String) {
        copier?(text)
    }

    /// An inline confirmation belongs to its card, not the window's notice.
    func copyInPlace(_ text: String) -> Bool {
        if let inlineCopier { return inlineCopier(text) }
        guard let copier else { return false }
        copier(text)
        return true
    }
}
