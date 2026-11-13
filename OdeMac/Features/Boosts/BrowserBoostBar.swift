import SwiftUI

/// The bar over a page while the person edits its site's Boost: turn it on
/// or off, hide elements by clicking them, set its colors, font and CSS,
/// show hidden elements again, or remove it.
struct BrowserBoostBar: View {
    let boost: BrowserBoostSession

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0
    @State private var isShowingColors = false
    @State private var isShowingStylesheet = false

    var body: some View {
        BrowserPageToolbarSurface(label: "Boost", identifier: "page-boost-bar") {
            if let shown = boost.draft {
                controls(shown)
                    .font(.callout.weight(.medium))
            }
        } background: {
            OdeSurfaceLayer(shape: Rectangle())
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
    }

    /// Below this width, or at accessibility text sizes, the bar's controls
    /// show their symbols alone.
    private var showsTitles: Bool {
        availableWidth >= 700 && !dynamicTypeSize.isAccessibilitySize
    }

    private func controls(_ shown: SiteBoost) -> some View {
        HStack(spacing: OdeSpacing.extraSmall) {
            Image(systemName: shown.isEnabled ? "paintbrush.fill" : "paintbrush")
                .font(.system(size: BrowserBoostBarLabel.symbolSize, weight: .semibold))
                .foregroundStyle(shown.isEnabled ? OdeBrandTheme.accentText : Color.secondary)
                .frame(width: controlHeight, height: controlHeight)
                .accessibilityHidden(true)
            Text(verbatim: shown.site)
                .lineLimit(1)
                .truncationMode(.middle)
            Toggle(isOn: Binding(get: { shown.isEnabled }, set: { boost.setEnabled($0) })) {
                Text("Boost")
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .accessibilityIdentifier("boost-enabled")
            divider
            BrowserBoostBarButton(
                title: "Zap", systemImage: "bolt", showsTitle: showsTitles, isActive: boost.isHiding,
                help: boost.isHiding ? "Stop hiding elements" : "Click elements on the page to hide them"
            ) {
                boost.setHiding(!boost.isHiding)
            }
            .accessibilityIdentifier("boost-zap")
            BrowserBoostBarButton(
                title: "Colors", systemImage: "circle.lefthalf.filled", showsTitle: showsTitles,
                isActive: shown.isDark || shown.tintStrength > 0 || shown.brightness != 1 || shown.contrast != 1,
                help: "Colors"
            ) {
                isShowingColors.toggle()
            }
            .popover(isPresented: $isShowingColors, arrowEdge: .bottom) {
                BrowserBoostColorsPanel(boost: boost)
            }
            fontMenu(shown)
            BrowserBoostBarButton(
                title: "CSS", systemImage: "curlybraces", showsTitle: showsTitles,
                isActive: !shown.customCss.isEmpty, help: "Custom CSS"
            ) {
                isShowingStylesheet.toggle()
            }
            .popover(isPresented: $isShowingStylesheet, arrowEdge: .bottom) {
                BrowserBoostStylesheetEditor(boost: boost)
            }
            if !shown.hiddenSelectors.isEmpty {
                hiddenMenu(shown)
            }
            Spacer(minLength: OdeSpacing.small)
            Menu {
                Button("Remove Boost", systemImage: "trash", role: .destructive) { boost.removeBoost() }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: controlHeight, height: controlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeCornerScale.control))
            .help("More")
            .accessibilityLabel("More")
            Button {
                boost.endEditing()
            } label: {
                Text("Done")
                    .padding(.horizontal, OdeSpacing.small)
                    .frame(minHeight: controlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(
                OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeCornerScale.control, showsRestingFill: true)
            )
            .accessibilityIdentifier("boost-done")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
    }

    private func fontMenu(_ shown: SiteBoost) -> some View {
        Menu {
            Picker(
                selection: Binding(get: { shown.font }, set: { font in boost.change { $0.font = font } })
            ) {
                Text("Site’s Font").tag(BoostFont?.none)
                Divider()
                ForEach(BoostFont.all, id: \.self) { font in
                    Text(font.title).tag(BoostFont?.some(font))
                }
            } label: {
                Text("Font")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            BrowserBoostBarLabel(
                title: shown.font.map { Text($0.title) } ?? Text("Font"), systemImage: "textformat",
                showsTitle: showsTitles, isActive: shown.font != nil)
        }
        .buttonStyle(OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeCornerScale.control))
        .help("Font")
        .accessibilityLabel("Font")
        .accessibilityValue(shown.font.map { Text($0.title) } ?? Text("Site’s Font"))
    }

    private func hiddenMenu(_ shown: SiteBoost) -> some View {
        Menu {
            ForEach(shown.hiddenSelectors, id: \.self) { selector in
                Button {
                    boost.showHidden(selector)
                } label: {
                    Text(verbatim: selector)
                }
            }
            Divider()
            Button("Show All") { boost.change { $0.hiddenSelectors = [] } }
        } label: {
            BrowserBoostBarLabel(
                title: Text("\(shown.hiddenSelectors.count) Hidden"), systemImage: "eye.slash",
                showsTitle: showsTitles, isActive: false)
        }
        .buttonStyle(OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeCornerScale.control))
        .help("Show hidden elements again")
        .accessibilityLabel("Hidden elements")
        .accessibilityValue(Text("\(shown.hiddenSelectors.count)"))
    }

    private var divider: some View {
        Divider().frame(height: 18).padding(.horizontal, OdeSpacing.extraSmall).accessibilityHidden(true)
    }

    private var controlHeight: CGFloat { 28 }
}

/// A Boost bar control's look: its symbol, and its title where the bar has
/// room, in Ode's accent on a faint accent fill while what it sets is in
/// use, the same for buttons and menus.
struct BrowserBoostBarLabel: View {
    /// Every symbol on the bar draws at this size.
    static let symbolSize: CGFloat = 13
    /// How strongly an active control's fill shows the accent.
    static let activeFillOpacity = 0.12

    let title: Text
    let systemImage: String
    let showsTitle: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: OdeSpacing.extraSmall) {
            Image(systemName: systemImage)
                .font(.system(size: Self.symbolSize, weight: .semibold))
            if showsTitle { title.lineLimit(1) }
        }
        .foregroundStyle(isActive ? OdeBrandTheme.accentText : Color.primary)
        .padding(.horizontal, showsTitle ? OdeSpacing.small : 0)
        .frame(minWidth: 28, minHeight: 28)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: OdeCornerScale.control, style: .continuous)
                    .fill(OdeBrandTheme.accent.opacity(Self.activeFillOpacity))
            }
        }
        .contentShape(.rect)
    }
}

/// A Boost bar control that acts at once.
struct BrowserBoostBarButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let showsTitle: Bool
    var isActive = false
    let help: LocalizedStringKey
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            BrowserBoostBarLabel(
                title: Text(title), systemImage: systemImage, showsTitle: showsTitle, isActive: isActive)
        }
        .buttonStyle(OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeCornerScale.control))
        .help(Text(help))
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
