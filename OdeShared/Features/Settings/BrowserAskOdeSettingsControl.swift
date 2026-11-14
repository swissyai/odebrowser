import SwiftUI

/// Composes beside native intelligence settings. This and the Search results
/// row edit the same core-owned choice, independent of tab organization.
struct BrowserAskOdeSettingsControl: View {
    // MARK: - Variables

    @Bindable var preferences: BrowserAppPreferenceStore
    let availability: PaletteGenerativeStatus

    private var answers: OdeSettingValue<Bool> {
        OdeSettingValue(
            Binding(
                get: { preferences.palette.offers(.askOde) },
                set: { preferences.palette = preferences.palette.offering(.askOde, $0) }),
            default: false)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        OdeSettingsGroup(
            "Ode", settings: [answers.resettable("Answers in the command bar")],
            footnote:
                "Apple’s on-device model uses only what you type. Search suggestions use your search service."
        ) {
            OdeSettingRow("Answers in the command bar", setting: answers.resettable("Answers in the command bar")) {
                Toggle("Answers in the command bar", isOn: answers.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("ask-ode-private-answers")
            }
            .settingsSearchTarget(named: "palette-source-\(PaletteSource.askOde.name)")
            if availability == .answered {
                Text("Available")
                    .foregroundStyle(.secondary)
            } else {
                Text(availability.message)
                    .foregroundStyle(.secondary)
            }
            Link(
                "Set up Apple Intelligence",
                destination: ProductIdentity.website.appending(path: "guides/intelligence/"))
        }
    }
}

#if DEBUG
    #Preview("Ode — Ready") {
        @Previewable @State var preferences = BrowserAppPreferenceStore()
        Form {
            BrowserAskOdeSettingsControl(preferences: preferences, availability: .answered)
        }
        .odeSettingsForm()
        .frame(width: 520)
    }
#endif
