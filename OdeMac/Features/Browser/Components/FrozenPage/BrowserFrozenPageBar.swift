import SwiftUI

/// The bar a page that stopped answering the person shows across its top:
/// wait for it, or stop it and keep the tab. It never covers the page, so the
/// person can still read what is there.
struct BrowserFrozenPageBar: View {
    let wait: () -> Void
    let stop: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: OdeSpacing.medium) {
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
                Text("This page isn't responding")
                    .fontWeight(.semibold)
                Text("You can wait for it, or stop it and keep the tab.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: OdeSpacing.medium)
            Button("Wait", action: wait)
                .accessibilityIdentifier("frozen-page-wait")
            Button("Stop page", action: stop)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("frozen-page-stop")
        }
        .font(.callout)
        .padding(.horizontal, OdeSpacing.large)
        .padding(.vertical, OdeSpacing.medium)
        .frame(maxWidth: 620)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).fill(
                    Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).strokeBorder(
                .separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("frozen-page-bar")
    }
}

/// What a tab shows once the person stopped its frozen page: that it was
/// stopped, and the way to load it again. The tab and its history stay.
struct BrowserStoppedPagePlaceholder: View {
    let reload: () -> Void

    var body: some View {
        VStack(spacing: OdeSpacing.medium) {
            Image(systemName: "stop.circle")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("This page was stopped")
                .font(.title3.weight(.semibold))
            Text("It wasn't responding, so Ode stopped it. The tab and its history are kept.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Reload page", action: reload)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("stopped-page-reload")
        }
        .padding(OdeSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stopped-page-placeholder")
    }
}
