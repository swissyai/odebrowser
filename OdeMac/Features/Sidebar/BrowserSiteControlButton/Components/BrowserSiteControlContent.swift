import SwiftUI

struct BrowserSiteControlContent: View {
    let configuration: BrowserSiteControlConfiguration
    @Binding var permissionsExpansion: Bool
    let dismiss: () -> Void
    let reviewCertificate: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            BrowserSiteControlHeader(page: configuration.page)
            if let notice = configuration.page.blockedPopupNotice {
                BrowserBlockedPopupSiteControlNotice(
                    notice: notice,
                    allow: {
                        configuration.page.allowAutomaticPopupsForBlockedSite()
                        permissionsExpansion = true
                    }
                )
            }
            BrowserSiteQuickActions(
                page: configuration.page,
                dismiss: dismiss
            )
            BrowserSiteBoostRow(boost: configuration.page.boost, dismiss: dismiss)
            BrowserSitePreviewRow(page: configuration.page, tabPreviews: configuration.tabPreviews)
            BrowserSiteDailyLimitRow(page: configuration.page)
            BrowserEngineSiteControlsSection(
                page: configuration.page,
                space: configuration.space,
                url: configuration.page.live.documentURL,
                dismiss: dismiss
            )
            Divider()
            BrowserSiteSettingsContent(
                page: configuration.page,
                permissionCenter: configuration.permissionCenter,
                reviewCertificate: reviewCertificate,
                permissionsExpansion: $permissionsExpansion
            )
            if configuration.page.live.displayURL?.host()?.isEmpty == false {
                Divider()
                BrowserSiteDataActions(page: configuration.page, dismiss: dismiss)
                BrowserSiteOpenInSpaceMenu(page: configuration.page, dismiss: dismiss)
            }
        }
        .padding(OdeSpacing.medium)
    }
}
