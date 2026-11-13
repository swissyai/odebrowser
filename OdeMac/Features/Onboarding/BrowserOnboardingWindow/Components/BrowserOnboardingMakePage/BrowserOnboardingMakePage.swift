import SwiftUI

/// Making a Space yours: the Space as its sidebar beside a page, and its
/// name, color and icon edited beside it.
struct BrowserOnboardingMakePage: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    @Binding var name: String
    /// The Space as its icon draws it, for the page beside the sidebar.
    let identity: BrowserSpaceIdentity
    var previewSpace: SpaceModel? = nil
    var favicons = FaviconAssets()
    var addressPlacement = BrowserAddressPlacement.defaultValue
    /// The Spaces being made, as chips, or nil for a page that makes one
    /// Space alone.
    var picker: BrowserOnboardingMakePicker? = nil
    /// Why the last edit was refused, when it was.
    var failure: BrowserOnboardingFailureText? = nil
    let back: BrowserOnboardingBackAction?
    let advanceTitle: Text
    let advance: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: OdeSpacing.extraExtraLarge) {
                    BrowserOnboardingHeadline("Make it yours")
                    if let picker { BrowserOnboardingMakeChips(picker: picker) }
                    if geometry.size.width >= 1000 {
                        HStack(alignment: .top, spacing: OdeSpacing.extraExtraLarge) {
                            preview.frame(width: 460, height: 320)
                            sheet
                        }
                    } else {
                        preview.frame(height: 280)
                        sheet
                    }
                    if let failure {
                        BrowserOnboardingFailureMessage(message: failure)
                            .font(.callout)
                            .foregroundStyle(SpaceRoleStyle.dangerText)
                            .accessibilityIdentifier("onboarding-workflow-error")
                    }
                    BrowserOnboardingFooter(back: back) {
                        BrowserOnboardingContinueButton(advanceTitle, action: advance)
                            .accessibilityIdentifier("space-setup-continue")
                    }
                }
                .frame(maxWidth: 960, alignment: .leading)
                .padding(BrowserOnboardingStageMetrics.inset)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The Space as its window, its icon large on the page.
    private var preview: some View {
        BrowserOnboardingWindowPreview(
            branding: branding, symbol: symbol, name: name, editableName: $name,
            previewSpace: previewSpace, favicons: favicons, addressPlacement: addressPlacement
        ) {
            BrowserSpaceIcon(identity: identity, form: .tile, size: BrowserOnboardingMakeMetrics.pageIconSize)
                .frame(
                    width: BrowserOnboardingMakeMetrics.pageIconSize, height: BrowserOnboardingMakeMetrics.pageIconSize)
        }
    }

    /// The Space's name, color and icon, as Settings edits them.
    private var sheet: some View {
        BrowserSpaceIdentityEditor(name: $name, symbol: $symbol, branding: $branding, defersDetails: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The Spaces a page makes, as chips with one to add.
struct BrowserOnboardingMakePicker {
    let spaces: [BrowserSpaceIdentity]
    let selectedID: UUID?
    let select: (UUID) -> Void
    let add: () -> Void
    /// Removes a Space the setup made, or nil for one it cannot remove.
    let remove: (UUID) -> (() -> Void)?
}

/// The Spaces being made as a rail of chips, with one to add. The rail
/// scrolls sideways where a setup has made more Spaces than fit the header.
private struct BrowserOnboardingMakeChips: View {
    let picker: BrowserOnboardingMakePicker

    var body: some View {
        OdeSpaceChipRail(
            spaces: OdeSpaceIdentity.list(picker.spaces),
            selection: Binding(
                get: { picker.selectedID },
                set: { if let id = $0 { picker.select(id) } }),
            add: OdeSpaceChipAddAction(
                title: "New Space", accessibilityIdentifier: "space-customization-add", perform: picker.add),
            commands: { space in picker.remove(space.id).map { [.remove($0)] } ?? [] }
        )
        .frame(maxWidth: BrowserOnboardingMakeMetrics.chipsWidth)
        .accessibilityLabel("Spaces")
    }
}

enum BrowserOnboardingMakeMetrics {
    /// The most of the header the Space chips take once they scroll.
    static let chipsWidth: CGFloat = 520
    static let pageIconSize: CGFloat = 100
}
