import SwiftUI

/// The link button a live site puts in the address field's trailing slot, beside
/// Site Controls, when the person turned it on in Appearance.
struct BrowserAddressCopyURLButton: View {
    let page: BrowserPage

    var body: some View {
        Button {
            Self.copy(page)
        } label: {
            Image(systemName: "link")
                .font(
                    .system(
                        size: BrowserTabTrailingControlMetrics.pointer.glyphSize,
                        weight: .medium
                    )
                )
                .frame(
                    width: BrowserSiteControlMetrics.triggerSize.width,
                    height: BrowserSiteControlMetrics.triggerSize.height
                )
                .contentShape(.rect)
        }
        .buttonStyle(
            OdeChromeButtonStyle(
                controlSize: BrowserSiteControlMetrics.triggerSize
            )
        )
        .foregroundStyle(.secondary)
        .accessibilityLabel("Copy Address")
        .accessibilityIdentifier("browser-address-copy-url")
        .help("Copy Address")
    }

    /// The button, address menu and accessibility action share the page's
    /// canonical copy operation and the same nonmodal feedback.
    static func copy(_ page: BrowserPage) {
        guard page.copyPageLink() else { return }
        BrowserNoticeCenter.shared.post(.urlCopied)
    }
}
