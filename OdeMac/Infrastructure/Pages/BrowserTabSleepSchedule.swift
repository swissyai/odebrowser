import Foundation

/// Which hidden tabs' pages sleep at a moment: a decision from what each tab
/// is doing, when a window last showed it, the delay the person chose, the
/// Spaces windows show now, and the order tabs were last shown in. A value
/// with no engine behind it, so the decision can be read on its own.
///
/// A tab sleeps once no window has shown it for the delay, or for half the
/// delay when no window shows its Space. The few hidden tabs shown most
/// recently never sleep on the timer, so switching back among the handful a
/// person works across is always instant, and a tab with a hold never does.
struct BrowserTabSleepSchedule {
    // MARK: - Types

    /// One tab as the schedule sees it.
    struct Tab: Equatable {
        let id: UUID
        /// The Space the tab lives in.
        let spaceID: UUID
        /// When a window last showed the tab.
        let lastShown: Date
        /// What keeps the tab's page loaded whatever the timer says.
        let holds: Hold

        init(id: UUID, spaceID: UUID, lastShown: Date, holds: Hold = []) {
            self.id = id
            self.spaceID = spaceID
            self.lastShown = lastShown
            self.holds = holds
        }
    }

    /// What keeps a tab's page loaded however long the tab stays hidden.
    struct Hold: OptionSet, Hashable {
        let rawValue: Int

        /// A window shows the tab now.
        static let shown = Self(rawValue: 1 << 0)
        /// The person chose Keep Loaded for the tab.
        static let keptLoaded = Self(rawValue: 1 << 1)
        /// An agent works in the tab.
        static let agentHeld = Self(rawValue: 1 << 2)
        /// The page holds text the person typed, or has not yet said whether
        /// it does.
        static let typedText = Self(rawValue: 1 << 3)
        /// The page plays sound or video, in a call or otherwise.
        static let playing = Self(rawValue: 1 << 4)
        /// The page captures the camera or the microphone.
        static let capturing = Self(rawValue: 1 << 5)
        /// The page's video floats in Picture in Picture.
        static let pictureInPicture = Self(rawValue: 1 << 6)
        /// The page is not the tab's own resident page: a transient page, a
        /// leased one, or one another tab owns.
        static let transient = Self(rawValue: 1 << 7)
    }

    // MARK: - Static Variables

    /// How many of the hidden tabs shown most recently never sleep on the
    /// timer.
    static let protectedRecentCount = 5
    /// The share of the delay a tab waits when no window shows its Space.
    static let hiddenSpaceDelayShare = 0.5

    // MARK: - Variables

    /// How long a tab in a Space some window shows stays loaded after it was
    /// last shown.
    let delay: TimeInterval
    /// The Spaces some window shows now.
    let shownSpaceIDs: Set<UUID>
    /// How many of the hidden tabs shown most recently stay loaded whatever
    /// their age.
    let protectedRecentCount: Int

    // MARK: - Initializers

    /// The schedule the stored preference `stored` asks for, with nil for a
    /// preference never set, over the Spaces `shownSpaceIDs` some window
    /// shows; nil when tabs never sleep.
    init?(stored: Int?, shownSpaceIDs: Set<UUID>, protectedRecentCount: Int = Self.protectedRecentCount) {
        guard let delay = SleepingTabsPreference.delay(stored ?? SleepingTabsPreference.defaultValue) else {
            return nil
        }
        self.delay = delay
        self.shownSpaceIDs = shownSpaceIDs
        self.protectedRecentCount = protectedRecentCount
    }

    // MARK: - Actions - Deciding

    /// How long `tab` stays loaded after it was last shown: the delay, or
    /// half of it when no window shows its Space.
    func delay(for tab: Tab) -> TimeInterval {
        shownSpaceIDs.contains(tab.spaceID) ? delay : delay * Self.hiddenSpaceDelayShare
    }

    /// The tabs among `tabs` whose pages sleep at `time`: those no window
    /// shows, outside the protected most recent few, with no hold, shown
    /// longer ago than their delay.
    func tabsToSleep(among tabs: [Tab], at time: Date) -> [UUID] {
        let hidden = tabs.filter { !$0.holds.contains(.shown) }
        let protected = Set(hidden.sorted { $0.lastShown > $1.lastShown }.prefix(protectedRecentCount).map(\.id))
        return hidden.filter { tab in
            tab.holds.isEmpty && !protected.contains(tab.id) && time.timeIntervalSince(tab.lastShown) >= delay(for: tab)
        }.map(\.id)
    }
}
