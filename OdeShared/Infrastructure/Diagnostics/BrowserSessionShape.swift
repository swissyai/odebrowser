import Foundation

/// Which tabs each Space held, in order, when Ode last quit cleanly, so the
/// next launch can count the tabs it did not bring back where they were. It
/// holds identities only: no address, title or typed text.
///
/// The file is `session-shape.json` beside the session, version 1:
///
///     {"version":1,"spaces":[{"id":"…","tabs":["…","…"]}]}
struct BrowserSessionShape: Codable, Equatable, Sendable {
    // MARK: - Types

    struct Space: Codable, Equatable, Sendable {
        let id: UUID
        let tabs: [UUID]
    }

    /// How a shape differs from a saved one, by kind of difference.
    struct Differences: Equatable, Sendable {
        /// The saved shape's tabs this one does not hold, in its order.
        var missing: [UUID] = []
        /// This shape's tabs the saved one does not hold, in its order.
        var added: [UUID] = []
        /// The tabs both hold that are now in another Space.
        var moved: [UUID] = []
        /// The places where the tabs both keep in a Space stand in another order.
        var reordered = 0

        var total: Int { missing.count + added.count + moved.count + reordered }

        /// The differences as one line for the log, each added tab as
        /// `describe` names it; never an address or a title.
        func line(describingAdded describe: (UUID) -> String?) -> String {
            let counts =
                "\(missing.count) missing, \(added.count) added, \(moved.count) in another Space, \(reordered) out of order"
            let kinds = added.compactMap(describe)
            return "The restored session differs from the last clean quit in \(total) places: \(counts)"
                + (kinds.isEmpty ? "" : "; added: \(kinds.joined(separator: ", "))")
        }
    }

    // MARK: - Static Variables

    static let currentVersion = 1
    static let fileName = "session-shape.json"

    // MARK: - Variables

    var version = currentVersion
    let spaces: [Space]

    // MARK: - Initializers

    init(spaces: [Space]) {
        self.spaces = spaces
    }

    // MARK: - Actions - Comparing

    /// How many tabs differ from `saved`: each tab missing, each tab added,
    /// each tab now in another Space, and each place where the tabs both
    /// shapes keep in a Space stand in another order.
    func differences(from saved: Self) -> Int {
        compared(with: saved).total
    }

    /// The tabs that differ from `saved`, by kind of difference.
    func compared(with saved: Self) -> Differences {
        let before = saved.placements
        let after = placements
        var found = Differences()
        found.missing = saved.orderedTabs.filter { after[$0] == nil }
        found.added = orderedTabs.filter { before[$0] == nil }
        found.moved = saved.orderedTabs.filter { tab in after[tab].map { $0 != before[tab] } ?? false }
        for space in saved.spaces {
            let kept = Set(spaces.first { $0.id == space.id }?.tabs ?? [])
            let beforeOrder = space.tabs.filter(kept.contains)
            let afterOrder = spaces.first { $0.id == space.id }?.tabs.filter(Set(beforeOrder).contains) ?? []
            found.reordered += zip(beforeOrder, afterOrder).filter { $0 != $1 }.count
        }
        return found
    }

    /// Every tab once, in Space and tab order.
    private var orderedTabs: [UUID] {
        var seen = Set<UUID>()
        return spaces.flatMap(\.tabs).filter { seen.insert($0).inserted }
    }

    /// Each tab's Space.
    private var placements: [UUID: UUID] {
        Dictionary(
            spaces.flatMap { space in space.tabs.map { ($0, space.id) } }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Actions - Files

    /// The shape kept beside the session in `directory`; nil when there is
    /// none or it cannot be read.
    static func read(in directory: URL, files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk()) -> Self? {
        guard let data = try? files.read(directory.appendingPathComponent(fileName)),
            let shape = try? JSONDecoder().decode(Self.self, from: data), shape.version == currentVersion
        else { return nil }
        return shape
    }

    func write(in directory: URL, files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? files.writeDurably(data, to: directory.appendingPathComponent(Self.fileName))
    }
}
