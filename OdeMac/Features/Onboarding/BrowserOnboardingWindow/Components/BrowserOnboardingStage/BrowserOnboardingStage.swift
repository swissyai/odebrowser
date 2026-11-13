import SwiftUI

/// Setup stays on the same native, appearance-aware Ode surface as its
/// content. A selected Space supplies both its ground and readable ink.
struct BrowserOnboardingStage<Content: View>: View {
    // MARK: - Variables

    let step: SetupStep
    let branding: SpaceBranding?
    @ViewBuilder let content: Content

    // MARK: - Actions - Presentation

    var body: some View {
        ZStack {
            BrowserOnboardingBackdrop(branding: branding)
            VStack(spacing: 0) {
                BrowserOnboardingStageHeader()
                content
                    .frame(maxWidth: 1120, maxHeight: 820)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .foregroundStyle(SpaceRoleStyle.text)
        .spaceColorRolesAvailable(for: branding)
        .odeFieldSurfaceRole(.brand)
    }
}

/// Native window controls retain their own titlebar area.
private struct BrowserOnboardingStageHeader: View {
    // MARK: - Actions - Presentation

    var body: some View {
        HStack(spacing: 10) {
            OdeMark()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(ProductIdentity.name)
                .font(OdeTypography.sans(14, weight: .bold))
                .foregroundStyle(OdeBrandTheme.textDisplay)
            Spacer()
        }
        .padding(.leading, 100)
        .padding(.trailing, BrowserOnboardingStageMetrics.headerInset)
        .frame(height: BrowserOnboardingStageMetrics.headerHeight)
    }
}

/// The measurements the stage and its pages share.
enum BrowserOnboardingStageMetrics {
    static let headerHeight: CGFloat = 64
    static let headerInset: CGFloat = 28
    /// The inset the footer keeps from the stage's edges.
    static let inset: CGFloat = 40
    /// The inset a page's content keeps from the stage's edges on a wide
    /// stage; a narrower one keeps the footer's.
    static let pageInset: CGFloat = 120
    /// The stage width from which pages keep `pageInset`.
    static let wideStageWidth: CGFloat = 1440

    /// The inset a page's content keeps on a stage `width` wide.
    static func pageInset(for width: CGFloat) -> CGFloat {
        width >= wideStageWidth ? pageInset : inset
    }
    /// How far a page's headline sits under the header.
    static let headlineSize: CGFloat = 46
}
