import SwiftUI

/// Native, offline document disclosure; legal text is shown verbatim, not Markdown-rendered.
struct BrowserAboutLicensesView: View {
    // MARK: - Variables

    let licenses: BrowserAboutLicenses

    // MARK: - Initializers

    init(licenses: BrowserAboutLicenses = .bundled) {
        self.licenses = licenses
    }

    var body: some View {
        DisclosureGroup("Licenses") {
            ForEach(licenses.documents) { document in
                DisclosureGroup {
                    if let text = document.text {
                        Text(verbatim: text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("License unavailable. Download the notices from Source Code.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } label: {
                    Text(verbatim: document.id)
                        .lineLimit(nil)
                }
            }
        }
        .accessibilityIdentifier("about-license-link")
    }
}
