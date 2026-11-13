struct BrowserShortcutCommandGroup: Equatable, Identifiable, Sendable {
    let section: ShortcutSection
    let commands: [ShortcutCommand]

    var id: ShortcutSection { section }
}

struct BrowserShortcutPendingConflict: Equatable, Sendable {
    let command: ShortcutCommand
    let shortcut: BrowserShortcut
    let conflictingCommands: [ShortcutCommand]
}

enum BrowserShortcutValidationIssue: Equatable, Sendable {
    case invalidShortcut
    case reservedByOde(
        shortcut: BrowserShortcut,
        commands: [ShortcutCommand]
    )
}
