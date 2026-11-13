import Foundation

/// How long Ode's everyday moments took on this Mac, and how often one went
/// wrong: for each kind of moment, how many there were, their total and the
/// longest, the last ``recentKept`` as samples, and its counters. A sample is
/// a duration with the few tags in ``Tags``; the ledger has no field for an
/// address, a title or typed text, and nothing but Ode on this Mac reads it.
///
/// The file is `moments.json` beside the session, version 1:
///
///     {"version":1,"moments":{"tabSwitch":{"count":2,"totalMilliseconds":71.5,
///       "longestMilliseconds":40.1,"recent":[{"milliseconds":31.4,
///       "tags":{"engine":"chromium","slept":false}}],"counters":{"blankFrames":0}}}}
struct BrowserMomentLedger: Codable, Equatable, Sendable {
    // MARK: - Types

    /// A moment Ode times, named by what the person did.
    struct Kind: RawRepresentable, Codable, Hashable, Sendable {
        let rawValue: String

        /// The input that switched tabs to the arriving page's first frame.
        static let tabSwitch = Self(rawValue: "tabSwitch")
        /// The key that asked for the Command Bar to the frame that shows it.
        static let commandBarOpen = Self(rawValue: "commandBarOpen")
        /// Return in the Command Bar to the navigation it starts.
        static let commandBarReturn = Self(rawValue: "commandBarReturn")
        /// Showing a sleeping tab to its page's first frame.
        static let wake = Self(rawValue: "wake")
        /// The process starting to the restored session's windows opening.
        static let sessionRestore = Self(rawValue: "sessionRestore")
        /// The process starting, when Ode ran before since the Mac started,
        /// to the first window's first frame.
        static let launchWarm = Self(rawValue: "launchWarm")
        /// The process starting, for the first time since the Mac started,
        /// to the first window's first frame.
        static let launchCold = Self(rawValue: "launchCold")
        /// The time a Space switch's motion lost to frames it dropped.
        static let spaceSwitch = Self(rawValue: "spaceSwitch")
        /// A download reaching the window to the frame that shows it leave.
        static let downloadFeedback = Self(rawValue: "downloadFeedback")
        /// A main-thread hang of ``BrowserHangLog/recorded`` or more.
        static let hang = Self(rawValue: "hang")
    }

    /// A count of something that went wrong in a moment, which a release
    /// expects to stay at zero.
    struct Counter: Hashable, Sendable {
        let name: String
        let kind: Kind

        /// Frames that passed after the departing page left the screen and
        /// before the arriving one reported its first frame.
        static let blankFrames = Self(name: "blankFrames", kind: .tabSwitch)
        /// Switches whose arriving page reported no frame in time.
        static let undrawn = Self(name: "undrawn", kind: .tabSwitch)
        /// Tabs put to sleep while they held text the person typed.
        static let typedTextSlept = Self(name: "typedTextSlept", kind: .wake)
        /// Tabs a relaunch did not bring back where the last quit left them.
        static let restoreDifferences = Self(name: "differences", kind: .sessionRestore)
        /// Downloads that started without any feedback in the window.
        static let feedbackSkipped = Self(name: "skipped", kind: .downloadFeedback)
    }

    /// What a sample says about its moment besides how long it took.
    struct Tags: Codable, Hashable, Sendable {
        /// The engine's name, as `EngineKind` names it.
        var engine: String?
        /// Whether the tab was asleep, so its page had to load again.
        var slept: Bool?
        /// Whether the page came from this Mac rather than the network.
        var local: Bool?
        /// Whether a woken page came back from its kept history, with its
        /// scroll position and the text typed into it, rather than loading
        /// its address afresh.
        var historyRestored: Bool?
        /// For a hang, the kind of the moment in flight when it happened,
        /// whose own tags the hang carries too. Nil for no moment.
        var during: String?

        /// Whether a page at `url` comes from this Mac: a file, a page Ode
        /// makes itself, or a server on the loopback address. Nil without an
        /// address. Only the answer is kept, never the address.
        static func isLocal(_ url: URL?) -> Bool? {
            guard let url, let scheme = url.scheme?.lowercased() else { return nil }
            guard scheme == "http" || scheme == "https" else { return true }
            let host = (url.host() ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host.hasPrefix("127.")
        }

        /// Each tag as `name=value`, for grouping samples.
        var labels: [String] {
            [
                engine.map { "engine=\($0)" },
                slept.map { "slept=\($0)" },
                local.map { "local=\($0)" },
                historyRestored.map { "historyRestored=\($0)" },
                during.map { "during=\($0)" },
            ].compactMap { $0 }
        }
    }

    struct Sample: Codable, Equatable, Sendable {
        let milliseconds: Double
        let tags: Tags
    }

    /// Everything kept about one kind of moment.
    struct Entry: Codable, Equatable, Sendable {
        var count = 0
        var totalMilliseconds = 0.0
        var longestMilliseconds = 0.0
        /// The newest samples, oldest first, at most ``recentKept``.
        var recent: [Sample] = []
        /// Each counter of the kind by its name.
        var counters: [String: Int] = [:]
    }

    /// The middle, the 95th percentile and the largest of some durations, by
    /// nearest rank, so each is a duration that happened.
    struct Statistics: Codable, Equatable, Sendable {
        let count: Int
        let median: Double
        let p95: Double
        let max: Double

        /// Nil for no durations.
        init?(_ milliseconds: [Double]) {
            guard !milliseconds.isEmpty else { return nil }
            let sorted = milliseconds.sorted()
            count = sorted.count
            median = Self.rank(0.5, in: sorted)
            p95 = Self.rank(0.95, in: sorted)
            max = sorted[sorted.count - 1]
        }

        private static func rank(_ fraction: Double, in sorted: [Double]) -> Double {
            let rank = Int((fraction * Double(sorted.count)).rounded(.up))
            return sorted[Swift.min(sorted.count, Swift.max(1, rank)) - 1]
        }
    }

    /// What the ledger reports, per kind: every moment counted, the recent
    /// ones' statistics overall and by each tag, and the counters.
    struct Summary: Codable, Equatable, Sendable {
        struct Moment: Codable, Equatable, Sendable {
            let count: Int
            let recent: Int
            let median: Double?
            let p95: Double?
            let max: Double?
            let counters: [String: Int]
            let tags: [String: Statistics]
        }

        let version: Int
        let moments: [String: Moment]
    }

    // MARK: - Static Variables

    static let currentVersion = 1
    static let fileName = "moments.json"
    /// The samples kept per kind, which the percentiles are taken over.
    static let recentKept = 200

    // MARK: - Variables

    var version = currentVersion
    private(set) var moments: [String: Entry] = [:]

    // MARK: - Actions - Reading

    /// Statistics over the recent samples of `kind`, or only those carrying
    /// `label`; nil when there are none.
    func statistics(_ kind: Kind, label: String? = nil) -> Statistics? {
        let samples = moments[kind.rawValue]?.recent ?? []
        guard let label else { return Statistics(samples.map(\.milliseconds)) }
        return Statistics(samples.filter { $0.tags.labels.contains(label) }.map(\.milliseconds))
    }

    /// How many moments of `kind` were recorded, recent or not.
    func count(_ kind: Kind) -> Int {
        moments[kind.rawValue]?.count ?? 0
    }

    func value(_ counter: Counter) -> Int {
        moments[counter.kind.rawValue]?.counters[counter.name] ?? 0
    }

    var summary: Summary {
        Summary(
            version: version,
            moments: moments.mapValues { entry in
                let overall = Statistics(entry.recent.map(\.milliseconds))
                let labels = Set(entry.recent.flatMap(\.tags.labels))
                return Summary.Moment(
                    count: entry.count, recent: entry.recent.count, median: overall?.median, p95: overall?.p95,
                    max: entry.count > 0 ? entry.longestMilliseconds : nil, counters: entry.counters,
                    tags: Dictionary(
                        uniqueKeysWithValues: labels.compactMap { label in
                            Statistics(entry.recent.filter { $0.tags.labels.contains(label) }.map(\.milliseconds))
                                .map { (label, $0) }
                        }))
            })
    }

    // MARK: - Mutators

    /// Records a moment of `kind` that took `milliseconds`. A duration that
    /// is negative or not a number changes nothing.
    mutating func record(_ kind: Kind, milliseconds: Double, tags: Tags = Tags()) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        var entry = moments[kind.rawValue] ?? Entry()
        entry.count += 1
        entry.totalMilliseconds += milliseconds
        entry.longestMilliseconds = max(entry.longestMilliseconds, milliseconds)
        entry.recent.append(Sample(milliseconds: milliseconds, tags: tags))
        if entry.recent.count > Self.recentKept { entry.recent.removeFirst(entry.recent.count - Self.recentKept) }
        moments[kind.rawValue] = entry
    }

    /// Adds `amount` to `counter`; a count of zero still lists the counter.
    mutating func count(_ counter: Counter, by amount: Int = 1) {
        guard amount >= 0 else { return }
        moments[counter.kind.rawValue, default: Entry()].counters[counter.name, default: 0] += amount
    }

    // MARK: - Actions - Files

    /// The ledger beside the session in `directory`; an empty one when it is
    /// missing, cannot be read or has another version.
    static func read(in directory: URL, files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk()) -> Self {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? files.read(url), let ledger = try? JSONDecoder().decode(Self.self, from: data),
            ledger.version == currentVersion
        else { return Self() }
        return ledger
    }

    /// The ledger as its file holds it.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// Writes `data`, a ledger's ``encoded()`` form, beside the session in
    /// `directory`, whole.
    static func write(_ data: Data, in directory: URL, files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk())
    {
        try? files.writeDurably(data, to: directory.appendingPathComponent(fileName))
    }
}
