import Foundation

// MARK: - Types

struct BrowserFaviconFallbackCacheKey: Hashable, Sendable {
    let profileID: UUID
    let iconURL: URL
}

struct BrowserFaviconFallbackRequestLease: Sendable {
    let token: BrowserFaviconFallbackRequestToken
    let task: Task<Data?, Never>
}

actor BrowserFaviconFallbackLoader {
    static let shared = BrowserFaviconFallbackLoader()
    private static let maximumCachedByteCount = 4 * 1_024 * 1_024
    private static let maximumMissingCount = 256
    /// How long a site that served no icon is left alone before it is asked
    /// again.
    private static let missRetryDelay: Duration = .seconds(15 * 60)
    private let downloadData: @Sendable (URL) async -> Data?
    private var cachedData: [BrowserFaviconFallbackCacheKey: Data] = [:]
    private var cacheRecency: [BrowserFaviconFallbackCacheKey] = []
    private var cachedByteCount = 0
    /// When each site that served no icon may be asked again.
    private var knownMissing: [BrowserFaviconFallbackCacheKey: ContinuousClock.Instant] = [:]
    private var inFlight: [BrowserFaviconFallbackCacheKey: BrowserFaviconFallbackRequestLease] = [:]
    private var profileGenerations: [UUID: UInt64] = [:]
    private var nextRequestID: UInt64 = 0

    init(
        download: @escaping @Sendable (URL) async -> Data? = { iconURL in
            await BrowserFaviconFallbackLoader.download(iconURL)
        }
    ) {
        downloadData = download
    }

    func data(for pageURL: URL, profileID: UUID) async -> Data? {
        guard !Task.isCancelled, let iconURL = Self.defaultIconURL(for: pageURL) else { return nil }
        let key = BrowserFaviconFallbackCacheKey(
            profileID: profileID,
            iconURL: iconURL
        )
        if let data = cachedData[key] {
            recordAccess(to: key)
            return data
        }
        if let retryAt = knownMissing[key] {
            guard retryAt <= .now else { return nil }
            knownMissing[key] = nil
        }

        let generation = currentGeneration(for: profileID)
        let lease: BrowserFaviconFallbackRequestLease
        if let pending = inFlight[key],
            pending.token.profileGeneration == generation
        {
            lease = pending
        } else {
            nextRequestID &+= 1
            let token = BrowserFaviconFallbackRequestToken(
                profileGeneration: generation,
                requestID: nextRequestID
            )
            let downloadData = downloadData
            let task = Task.detached(priority: .utility) {
                await downloadData(iconURL)
            }
            lease = BrowserFaviconFallbackRequestLease(token: token, task: task)
            inFlight[key] = lease
        }

        let downloadedData = await lease.task.value
        guard lease.token.profileGeneration == currentGeneration(for: profileID) else {
            return nil
        }

        if let activeLease = inFlight[key] {
            guard activeLease.token == lease.token else {
                return cachedData[key]
            }
            inFlight[key] = nil
            guard let downloadedData else {
                rememberMissing(key)
                return nil
            }
            insert(downloadedData, for: key)
            return downloadedData
        }

        return cachedData[key]
    }

    func removeAll(for profileID: UUID) {
        profileGenerations[profileID] = currentGeneration(for: profileID) &+ 1
        cachedData = cachedData.filter { $0.key.profileID != profileID }
        cacheRecency.removeAll { $0.profileID == profileID }
        cachedByteCount = cachedData.values.reduce(0) { $0 + $1.count }
        knownMissing = knownMissing.filter { $0.key.profileID != profileID }
        let pendingKeys = inFlight.keys.filter { $0.profileID == profileID }
        for key in pendingKeys {
            inFlight[key]?.task.cancel()
            inFlight[key] = nil
        }
    }

    private func rememberMissing(_ key: BrowserFaviconFallbackCacheKey) {
        if knownMissing.count >= Self.maximumMissingCount,
            let soonest = knownMissing.min(by: { $0.value < $1.value })?.key
        {
            knownMissing[soonest] = nil
        }
        knownMissing[key] = .now + Self.missRetryDelay
    }

    private func insert(_ data: Data, for key: BrowserFaviconFallbackCacheKey) {
        if let previous = cachedData[key] {
            cachedByteCount -= previous.count
        }
        cachedData[key] = data
        cachedByteCount += data.count
        recordAccess(to: key)

        while cachedByteCount > Self.maximumCachedByteCount,
            let leastRecent = cacheRecency.first
        {
            cacheRecency.removeFirst()
            if let removed = cachedData.removeValue(forKey: leastRecent) {
                cachedByteCount -= removed.count
            }
        }
    }

    private func recordAccess(to key: BrowserFaviconFallbackCacheKey) {
        cacheRecency.removeAll { $0 == key }
        cacheRecency.append(key)
    }

    private func currentGeneration(for profileID: UUID) -> UInt64 {
        profileGenerations[profileID, default: 0]
    }

    private static func defaultIconURL(for pageURL: URL) -> URL? {
        guard pageURL.scheme?.lowercased() == "https" || pageURL.scheme?.lowercased() == "http",
            var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
            components.host != nil
        else { return nil }
        components.user = nil
        components.password = nil
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func download(
        _ iconURL: URL,
        session requestedSession: URLSession? = nil
    ) async -> Data? {
        await BrowserFaviconCapture.downloadCandidate(iconURL, session: requestedSession)
    }
}
