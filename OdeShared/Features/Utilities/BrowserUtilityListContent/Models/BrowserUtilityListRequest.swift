import Foundation

/// The fields that can change download membership, grouping, search results,
/// text, or available actions. Progress is intentionally row-local and does
/// not require rebuilding the section model.
struct BrowserUtilityDownloadPreparationIdentity: Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    let createdAt: Date
    let filename: String
    let destination: String?
    let phase: DownloadPhase
    let message: String?
    let risk: DownloadRiskAssessment?

    init(_ item: DownloadState) {
        id = item.id
        profileID = item.profileID
        createdAt = item.createdAt
        filename = item.filename
        destination = item.destination
        phase = item.phase
        message = item.message
        risk = item.risk
    }
}

struct BrowserUtilityListRequest: Equatable, Sendable {
    let surface: BrowserUtilitySurface
    let assignment: BrowserSpaceRuntimeAssignment
    let searchText: String
    let filter: BrowserUtilityListFilter
    var historyGrouping: BrowserHistoryGrouping = .time
    let archivedTabs: [ArchivedTabState]
    /// The Space's newest history entries, as the session holds them, which
    /// a list without a history reader shows.
    let history: [HistoryEntryState]
    let downloads: [DownloadState]
    /// Whether the list reads the history kept beside the session: a history
    /// list of a Space this process may show.
    let readsHistory: Bool
    /// How many history addresses the list reads, and the revision of the
    /// history kept beside the session it reads at.
    let historyLimit: Int
    let historyRevision: Int64
    private let downloadPreparationIdentities: [BrowserUtilityDownloadPreparationIdentity]

    init(
        surface: BrowserUtilitySurface,
        assignment: BrowserSpaceRuntimeAssignment,
        archivedTabs: [ArchivedTabState],
        history: [HistoryEntryState],
        downloads: [DownloadState],
        searchText: String,
        filter: BrowserUtilityListFilter,
        readsHistory: Bool = false,
        historyLimit: Int = BrowserHistoryReader.pageSize,
        historyRevision: Int64 = 0
    ) {
        let normalizedDownloads = Self.normalizedDownloads(
            downloads,
            profileID: assignment.profileID
        )
        self.surface = surface
        self.assignment = assignment
        self.searchText = searchText
        self.filter = filter
        self.archivedTabs = archivedTabs
        self.history = history
        self.downloads = normalizedDownloads
        self.readsHistory = readsHistory
        self.historyLimit = historyLimit
        self.historyRevision = historyRevision
        downloadPreparationIdentities = normalizedDownloads.map(
            BrowserUtilityDownloadPreparationIdentity.init
        )
    }

    /// A locked Space yields no rows at all. Copying its history, archive or
    /// downloads into a request and then blurring the result still materialises
    /// the titles and URLs the lock exists to withhold, so the gate belongs here
    /// rather than in the drawing layer.
    @MainActor
    init(
        surface: BrowserUtilitySurface,
        space: SpaceModel,
        downloads: [DownloadState],
        searchText: String,
        filter: BrowserUtilityListFilter,
        isUnlocked: Bool = true,
        historyLimit: Int = BrowserHistoryReader.pageSize,
        historyRevision: Int64 = 0
    ) {
        self.init(
            surface: surface,
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            archivedTabs: isUnlocked && surface == .archive ? space.archive.entries : [],
            history: isUnlocked && surface == .history ? space.groupHistory : [],
            downloads: isUnlocked && surface == .downloads ? downloads : [],
            searchText: searchText,
            filter: filter,
            readsHistory: isUnlocked && surface == .history,
            historyLimit: historyLimit,
            historyRevision: historyRevision
        )
    }

    static func == (
        lhs: BrowserUtilityListRequest,
        rhs: BrowserUtilityListRequest
    ) -> Bool {
        lhs.surface == rhs.surface
            && lhs.assignment == rhs.assignment
            && lhs.searchText == rhs.searchText
            && lhs.filter == rhs.filter
            && lhs.historyGrouping == rhs.historyGrouping
            && lhs.archivedTabs == rhs.archivedTabs
            && lhs.history == rhs.history
            && lhs.readsHistory == rhs.readsHistory
            && lhs.historyLimit == rhs.historyLimit
            && lhs.historyRevision == rhs.historyRevision
            && lhs.downloadPreparationIdentities
                == rhs.downloadPreparationIdentities
    }

    func hasSamePresentationOwnership(
        as other: BrowserUtilityListRequest
    ) -> Bool {
        surface == other.surface && assignment == other.assignment
    }

    private static func normalizedDownloads(
        _ downloads: [DownloadState],
        profileID: UUID
    ) -> [DownloadState] {
        var seenIDs: Set<UUID> = []
        return downloads.filter { item in
            item.profileID == profileID && seenIDs.insert(item.id).inserted
        }
    }
}
