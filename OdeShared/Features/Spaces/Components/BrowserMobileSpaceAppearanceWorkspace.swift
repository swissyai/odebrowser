#if os(iOS)
    import SwiftUI

    /// A setup draft's touch editor and adaptive preview, in the setup flow's
    /// own paper.
    struct BrowserMobileSpaceAppearanceWorkspace: View {
        // MARK: - Variables

        @Binding var branding: SpaceBranding
        @Binding var symbol: String
        @Binding var name: String
        var spacePicker: BrowserSpaceCustomizationPicker? = nil
        var defersDetails = false
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        // MARK: - Actions - Presentation

        var body: some View {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700 && horizontalSizeClass == .regular
                HStack(alignment: .top, spacing: wide ? 24 : 0) {
                    if wide {
                        preview(compact: false)
                            .frame(width: 260)
                            .frame(maxHeight: 580)
                            .padding(.leading, 24)
                            .padding(.vertical, 20)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !wide { preview(compact: true) }
                            BrowserSpaceIdentityEditor(
                                name: $name, symbol: $symbol, branding: $branding, defersDetails: defersDetails)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(wide ? 24 : 20)
                        // The vertical scroll view must propose its viewport, not the
                        // ideal width of the editor, to every shared child.
                        .frame(width: wide ? min(600, max(0, geometry.size.width - 308)) : geometry.size.width)
                        .id("mobile-space-appearance-top")
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .background { BrowserSpaceBannerBackground(branding: branding, surface: .window) }
            .spaceColorRoles(for: branding)
            .foregroundStyle(SpaceRoleStyle.text)
        }

        private func preview(compact: Bool) -> some View {
            BrowserSpaceAppearanceHero(
                branding: branding, symbol: symbol, name: name, compact: compact, spacePicker: spacePicker)
        }
    }
#endif
