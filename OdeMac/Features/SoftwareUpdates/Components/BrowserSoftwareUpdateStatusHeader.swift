import SwiftUI

struct BrowserSoftwareUpdateStatusHeader: View {
    let model: BrowserSoftwareUpdateModel

    var body: some View {
        HStack(alignment: .top, spacing: OdeSpacing.medium) {
            Image(systemName: model.phase.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                title
                    .font(.title2.weight(.semibold))

                if let message = model.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var title: Text {
        if model.phase.isTitledByUpdate, let updateTitle = model.updateTitle {
            return Text(verbatim: updateTitle)
        }
        return Text(model.phase.title)
    }

    private var symbolColor: Color {
        switch model.phase.tone {
        case .accent: OdeBrandTheme.accent
        case .success: OdeColor.success
        case .warning: OdeColor.warning
        }
    }
}

#if DEBUG
    #Preview("Update available") {
        let model = BrowserSoftwareUpdateModel()
        BrowserSoftwareUpdateStatusHeader(model: model)
            .padding().frame(width: 500)
            .task {
                model.presentUpdate(
                    title: "Ode update", version: "1.0", releaseNotes: "A new update is ready.",
                    isInformationOnly: false, install: {}, skip: {})
            }
    }
#endif
