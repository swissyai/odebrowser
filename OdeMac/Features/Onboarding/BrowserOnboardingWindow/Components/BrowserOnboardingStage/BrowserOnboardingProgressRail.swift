import SwiftUI

/// Where setup stands: one segment per position, the current one long and
/// lit, those behind it dimmer, those ahead faint.
struct BrowserOnboardingProgressRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let step: SetupStep

    private var position: Int { step.progressPosition }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<SetupStep.progressCount, id: \.self) { item in
                Capsule()
                    .fill(fill(item))
                    .frame(width: item == position ? 40 : 22, height: 5)
            }
        }
        .animation(OdeMotion.onboardingProgress.unlessReducingMotion(reduceMotion), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(position + 1) of \(SetupStep.progressCount)")
    }

    private func fill(_ item: Int) -> Color {
        if item == position { return OdeBrandPalette.butter }
        return item < position ? OdeBrandPalette.butter.opacity(0.7) : OdeBrandPalette.paper.opacity(0.22)
    }
}
