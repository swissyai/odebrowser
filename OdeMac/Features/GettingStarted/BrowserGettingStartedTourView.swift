import SwiftUI

struct BrowserGettingStartedTourView: View {
    // MARK: - Variables

    let tour: BrowserGettingStartedTour
    let runCommand: (ShortcutCommand) -> Bool
    let showGuide: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 430
            let artworkHeight: CGFloat = geometry.size.height < 285 ? 32 : compact ? 65 : 130
            VStack(spacing: compact ? OdeSpacing.small : OdeSpacing.extraExtraLarge) {
                Spacer(minLength: 0)
                BrowserGettingStartedTourCue(tour: tour, runCommand: runCommand, compact: compact)
                Image(decorative: "OdeWelcomeBeret")
                    .resizable().scaledToFit()
                    .frame(height: artworkHeight)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if tour.step == .finished {
                    HStack(spacing: OdeSpacing.medium) {
                        Button("Browse", systemImage: "arrow.right") { tour.finishBrowsing() }
                            .buttonStyle(.odePrimary)
                        Button("Full guide", systemImage: "book", action: showGuide)
                            .buttonStyle(.odeSecondary)
                    }
                } else {
                    HStack(spacing: OdeSpacing.large) {
                        Text("\(tour.step.rawValue + 1) of 3")
                            .font(OdeTypography.sans(13)).foregroundStyle(OdeBrandTheme.textSecondary)
                        Button("Skip tour") { tour.finishBrowsing(completed: false) }.buttonStyle(.odeSecondary)
                    }
                }
            }
            .padding(.vertical, compact ? OdeSpacing.extraSmall : OdeSpacing.medium)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(tour.isCommandBarPresented ? 0 : 1)
            .allowsHitTesting(!tour.isCommandBarPresented)
            .accessibilityHidden(tour.isCommandBarPresented)
        }
        .foregroundStyle(OdeBrandTheme.textDisplay)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Getting Started tour")
    }
}
