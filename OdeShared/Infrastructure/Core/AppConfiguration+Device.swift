import Foundation

extension AppConfiguration {
    /// A configuration for the device this process runs on, keeping the
    /// session in `storageDirectory`, or in memory when it is nil. An import
    /// names the Spaces it brings in the person's language, and the
    /// languages they read choose the regional filter lists. `restoreFrom`
    /// names the dated copy a restore returns to; nil restores the recovery
    /// checkpoint. An isolated launch may name where the content filter's
    /// resources come from, to test a copy not yet published.
    init(storageDirectory: String?, restoreFrom: String? = nil) {
        let launch = BrowserLaunchEnvironment.current
        self.init(
            storageDirectory: storageDirectory, platform: .current,
            importNames: ImportSource.all.compactMap(ImportSpaceNames.init(resolving:)), restoreFrom: restoreFrom,
            languages: Locale.preferredLanguages,
            filterResourcesURL: launch.requiresIsolation
                ? ProcessInfo.processInfo.environment["ODE_FILTER_RESOURCES_URL"] : nil)
    }
}
