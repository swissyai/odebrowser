import SwiftUI

struct BrowserDataPortabilitySection: View {
    @State private var model: BrowserDataPortabilityModel

    let showsMacOSImportRequirement: Bool
    /// The shell's automatic export, where it keeps one.
    let automaticExport: BrowserAutomaticExport?
    private let presentsSystemPanels: Bool

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        showsMacOSImportRequirement: Bool = false,
        automaticExport: BrowserAutomaticExport? = nil
    ) {
        _model = State(
            initialValue: BrowserDataPortabilityModel(
                browser: browser,
                spaceAccess: spaceAccess
            )
        )
        self.showsMacOSImportRequirement = showsMacOSImportRequirement
        self.automaticExport = automaticExport
        presentsSystemPanels = true
    }

    init(
        model: BrowserDataPortabilityModel,
        showsMacOSImportRequirement: Bool = false,
        automaticExport: BrowserAutomaticExport? = nil,
        presentsSystemPanels: Bool = false
    ) {
        _model = State(initialValue: model)
        self.showsMacOSImportRequirement = showsMacOSImportRequirement
        self.automaticExport = automaticExport
        self.presentsSystemPanels = presentsSystemPanels
    }

    var body: some View {
        BrowserDataPortabilityDocumentPresenter(
            model: model,
            presentsSystemPanels: presentsSystemPanels
        ) {
            BrowserDataPortabilityContent(
                model: model,
                showsMacOSImportRequirement: showsMacOSImportRequirement
            )
        }
        .onChange(of: model.lockedSpaceIDs) { _, spaceIDs in
            if !spaceIDs.isEmpty {
                model.cancelSensitiveExports()
            }
        }
        if let automaticExport {
            BrowserAutomaticExportSection(automaticExport: automaticExport, presentsSystemPanels: presentsSystemPanels)
        }
    }
}
