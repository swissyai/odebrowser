import Foundation

/// How many minutes a tab no window shows keeps its page before the page
/// unloads, keeping the tab and its state; 0 keeps every page loaded. Only
/// the default moves between releases: a choice the person stored stands.
/// `BrowserTabSleepSchedule` decides which tabs the delay puts to sleep.
enum SleepingTabsPreference {
    static let key = "crest.performance.sleep-tabs-after-minutes"
    static let never = 0
    static let defaultValue = 15
    static let choices = [5, 15, 30, 60, 180, never]

    /// The delay a stored value asks for, or nil when tabs never sleep. A
    /// value that is not one of the choices, such as a hand-edited default,
    /// falls back to the default delay.
    static func delay(_ stored: Int) -> TimeInterval? {
        guard stored != never else { return nil }
        return TimeInterval((choices.contains(stored) ? stored : defaultValue) * 60)
    }
}
