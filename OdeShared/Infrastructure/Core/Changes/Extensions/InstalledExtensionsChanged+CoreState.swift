import Foundation

extension InstalledExtensionsChanged {
    @MainActor func apply(to state: CoreState) {
        state.installedExtensions[engine, default: [:]][profileID] = extensions
        state.extensionInventoryRevisions[engine, default: [:]][profileID, default: 0] &+= 1
    }
}
