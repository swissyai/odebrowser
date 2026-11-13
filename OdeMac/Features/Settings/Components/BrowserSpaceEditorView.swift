import SwiftUI

/// A Space's Appearance page: its name, accent color and icon, beside the
/// window's live sidebar or on their own where Settings can't show it.
struct BrowserSpaceEditorView: View {
    @Environment(\.browserSettingsTabState) private var tabState
    @State private var standaloneScroll = BrowserNativeScrollState()

    private var scrollState: BrowserNativeScrollState {
        tabState?.scroll(forKey: "space-\(space.id)-appearance") ?? standaloneScroll
    }

    let browser: BrowserStore
    let space: SpaceModel

    var body: some View {
        GeometryReader { geometry in
            let dense = geometry.size.height < 640
            ScrollView {
                BrowserSpaceIdentityEditor(name: name, symbol: symbol, branding: branding)
                    .id(space.id)
                    .padding(dense ? 14 : 20)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .browserNativeScrollState(scrollState)
            .contentMargins(.trailing, 12, for: .scrollContent)
            .defaultScrollAnchor(.top, for: .initialOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("space-customization-controls")
    }

    private var name: Binding<String> {
        browser.spaceNameBinding(in: space)
    }

    private var symbol: Binding<String> {
        browser.spaceSymbolBinding(in: space)
    }

    private var branding: Binding<SpaceBranding> {
        browser.spaceBrandingBinding(in: space)
    }
}
