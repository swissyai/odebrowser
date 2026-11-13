import SwiftUI

/// The site's Boost in its site controls: a way back into editing it, and a
/// switch that turns it on or off.
struct BrowserSiteBoostRow: View {
    let boost: BrowserBoostSession
    let dismiss: () -> Void

    var body: some View {
        if let kept = boost.kept {
            HStack(spacing: OdeSpacing.small) {
                Label("Boost", systemImage: kept.isEnabled ? "paintbrush.fill" : "paintbrush")
                Spacer(minLength: OdeSpacing.small)
                Button("Edit") {
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        boost.beginEditing()
                    }
                }
                .buttonStyle(.odeTertiary)
                .controlSize(.small)
                .accessibilityLabel("Edit Boost")
                .accessibilityIdentifier("site-boost-edit")
                Toggle(isOn: Binding(get: { kept.isEnabled }, set: { boost.setEnabled($0) })) {
                    Text("Boost")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityIdentifier("site-boost-enabled")
            }
        }
    }
}
