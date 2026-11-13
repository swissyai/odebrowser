import Foundation

/// Installs the extensions an import brought once the import has made the
/// Spaces they go into, using the choices already confirmed in review. They
/// remain pending until the engine confirms installation. Only an engine
/// that runs extensions supplies one, and setup offers no extensions without
/// it.
@MainActor
protocol BrowserImportedExtensionInstalling: AnyObject {
    func installImported(_ installs: [ImportExtensionInstall])
    func installImported(_ installs: [ImportExtensionInstall], outcomeID: UUID)
}

extension BrowserImportedExtensionInstalling {
    func installImported(_ installs: [ImportExtensionInstall], outcomeID: UUID) {
        installImported(installs)
    }
}
