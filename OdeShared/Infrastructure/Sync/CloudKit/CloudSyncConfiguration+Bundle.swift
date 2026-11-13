import Foundation

extension BrowserCloudSyncConfiguration {
    static func configured(in bundle: Bundle = .main) -> BrowserCloudSyncConfiguration? {
        guard
            let identifier = bundle.object(
                forInfoDictionaryKey: "OdeCloudKitContainerIdentifier"
            ) as? String,
            identifier.hasPrefix("iCloud."),
            !identifier.isEmpty
        else { return nil }
        return BrowserCloudSyncConfiguration(containerIdentifier: identifier)
    }
}
