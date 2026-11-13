import SwiftUI

struct MobileBrowserSettingsDestinationPage: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @Environment(MobileBrowserRootModel.self) private var rootModel: MobileBrowserRootModel?
    @Environment(BrowserCloudSyncController.self) private var cloudSync
    @Environment(BrowserOnboardingCoordinator.self) private var onboardingCoordinator

    @State private var presentsPasswords = false

    var body: some View {
        BrowserSettingsDestinationRouter(
            destination: destination,
            browser: browser,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter,
            cloudSync: cloudSync,
            permissionCenter: pages.permissionCenter,
            contentBlockingErrorDescription:
                pages.contentBlockingErrorDescription,
            setupActions: setupActions,
            passwordLayout: .mobilePage,
            showsMacOSImportRequirement: true,
            managePasswords: {
                if let rootModel {
                    rootModel.openPasswords(fromSettings: true)
                } else {
                    presentsPasswords = true
                }
            }
        )
        .sheet(isPresented: passwordsPresentation, onDismiss: rootModel?.passwordsSheetDidDismiss) {
            MobilePasswordSettingsView(
                browser: browser,
                spaceAccess: spaceAccess,
                pendingOperationChanged: rootModel?.passwordsPendingOperationChanged
            )
            .onAppear { rootModel?.passwordsSheetDidAppear() }
        }
    }

    private var passwordsPresentation: Binding<Bool> {
        rootModel?.passwordsPresentation(fromSettings: true) ?? $presentsPasswords
    }

    private var setupActions: [BrowserAdvancedSetupAction] {
        [
            .init(
                id: "rerun-onboarding",
                title: "Rerun onboarding",
                symbol: "arrow.counterclockwise",
                identifier: "mobile-open-setup",
                action: rerunOnboarding
            )
        ]
    }

    private func rerunOnboarding() {
        onboardingCoordinator.presentOnMobile(.rerun)
    }
}
