import SwiftUI

struct BrowserUtilityNotificationBadge: View {
    // MARK: - Variables

    let count: Int
    let tint: Color
    let progress: Double?

    var body: some View {
        Text("\(min(count, 99))")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .browserReadableForeground(over: tint)
            .padding(
                .horizontal,
                BrowserUtilitySwitcherLayout.notificationBadgeHorizontalPadding
            )
            .frame(
                minWidth: BrowserUtilitySwitcherLayout.notificationBadgeMinimumSize,
                minHeight: BrowserUtilitySwitcherLayout.notificationBadgeMinimumSize
            )
            .background(tint, in: .capsule)
            .overlay {
                if let progress {
                    Capsule()
                        .trim(
                            from: 0,
                            to: max(min(progress, 1), 0.04)
                        )
                        .stroke(
                            .primary.opacity(0.72),
                            style: StrokeStyle(
                                lineWidth: 1.5,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .accessibilityHidden(true)
    }
}
