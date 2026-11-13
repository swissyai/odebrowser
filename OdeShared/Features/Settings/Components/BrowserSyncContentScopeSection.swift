import SwiftUI

/// Where each kind of Ode content lives, as plain status rows.
struct BrowserSyncContentScopeSection: View {
    var body: some View {
        Section("What syncs") {
            LabeledContent("Spaces, tabs and history", value: String(localized: "iCloud"))
            LabeledContent("Ode Passwords", value: String(localized: "iCloud Keychain, per Space"))
            LabeledContent("Cookies and website data", value: String(localized: "This device only"))
        }
    }
}
