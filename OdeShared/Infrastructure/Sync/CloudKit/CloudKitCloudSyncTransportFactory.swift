@MainActor
final class CloudKitBrowserCloudSyncTransportFactory: BrowserCloudSyncTransportFactory {
    private let configuration: BrowserCloudSyncConfiguration
    private let core: OdeCore

    init(
        configuration: BrowserCloudSyncConfiguration,
        core: OdeCore
    ) {
        self.configuration = configuration
        self.core = core
    }

    func makeTransport(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void
    ) throws -> any BrowserCloudSyncTransport {
        try BrowserCloudSyncEngine(
            configuration: configuration,
            core: core,
            statusHandler: statusHandler,
            activityHandler: activityHandler
        )
    }
}
