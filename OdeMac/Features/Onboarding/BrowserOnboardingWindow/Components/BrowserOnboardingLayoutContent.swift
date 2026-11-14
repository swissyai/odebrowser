import SwiftUI

/// Layout is an appearance preference. Browsing and setup remain in the core;
/// these bindings write the existing Appearance settings only on confirmation.
struct BrowserOnboardingLayoutContent: View {
    // MARK: - Variables

    let storedLayout: String
    let storedRight: Bool
    @State private var selection: BrowserOnboardingTabPlacement?
    var addressPlacement = BrowserAddressPlacement.defaultValue

    let back: BrowserOnboardingBackAction
    let continueSetup: () -> Void
    let confirmLayout: (BrowserOnboardingTabPlacement) -> Void

    private var chosen: BrowserOnboardingTabPlacement {
        selection ?? BrowserOnboardingTabPlacement.current(layout: storedLayout, onRight: storedRight)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BrowserOnboardingHeadline("Tab placement")
                Picker("Tab placement", selection: Binding(get: { chosen }, set: { selection = $0 })) {
                    ForEach(BrowserOnboardingTabPlacement.all, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .odeControlPointer()
                .frame(maxWidth: 580)
                BrowserOnboardingWindowPreview(
                    branding: SpaceColorPreset.azure.branding, symbol: "house.fill",
                    name: String(localized: "Personal"),
                    tabLayout: chosen.layout, sidebarOnRight: chosen.onRight, addressPlacement: addressPlacement
                ) {
                    VStack(spacing: 18) {
                        Image(systemName: "mountain.2").font(.system(size: 60, weight: .ultraLight))
                        Text("Weekend plans").font(OdeTypography.display(34))
                    }
                    .foregroundStyle(OdeBrandTheme.textDisplay)
                }
                .frame(height: 320)
                .padding(.horizontal, BrowserOnboardingStageMetrics.inset)
                if chosen.layout.showsTopBar {
                    Text("Folders, History and Downloads stay in the sidebar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                BrowserOnboardingFooter(back: back) {
                    HStack(spacing: 18) {
                        Button("Keep current layout", action: continueSetup)
                            .buttonStyle(.odeSecondary)
                        BrowserOnboardingContinueButton("Use this layout") {
                            confirmLayout(chosen)
                        }
                    }
                }
            }
            .frame(maxWidth: 860)
            .padding(.vertical, 20)
            .padding(.horizontal, BrowserOnboardingStageMetrics.inset)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The three supported combinations of the existing appearance controls.
struct BrowserOnboardingTabPlacement: Hashable {
    // MARK: - Static Variables

    static let left = Self(title: "Left sidebar", layout: .sidebar, onRight: false)
    static let right = Self(title: "Right sidebar", layout: .sidebar, onRight: true)
    static let top = Self(title: "Tabs across the top", layout: .top, onRight: false)
    static let all = [left, right, top]

    // MARK: - Variables

    let title: LocalizedStringResource
    let layout: BrowserTabLayout
    let onRight: Bool

    // MARK: - Actions - Selection

    static func current(layout: String, onRight: Bool) -> Self {
        BrowserTabLayout.named(layout).showsTopBar ? .top : onRight ? .right : .left
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.layout == rhs.layout && lhs.onRight == rhs.onRight
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(layout)
        hasher.combine(onRight)
    }
}

#if DEBUG
    #Preview("Tab placement") {
        @Previewable @State var layout = BrowserTabLayout.sidebar.name
        @Previewable @State var right = false
        BrowserOnboardingLayoutContent(
            storedLayout: layout, storedRight: right, back: BrowserOnboardingBackAction(closes: false, action: {}),
            continueSetup: {},
            confirmLayout: { placement in
                layout = placement.layout.name
                if !placement.layout.showsTopBar { right = placement.onRight }
            }
        )
        .frame(width: 980, height: 660)
    }
#endif
