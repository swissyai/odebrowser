import SwiftUI

struct BrowserInstalledImportSourceGrid: View {
    let sources: [BrowserInstalledImportSource]
    let isSelected: (BrowserInstalledImportSource) -> Bool
    let isLocked: Bool
    let accessLabel: (BrowserInstalledImportSource) -> String?
    let toggleSelection: (BrowserInstalledImportSource) -> Void

    private var rows: [[BrowserInstalledImportSource]] {
        stride(from: 0, to: sources.count, by: 3).map { start in
            Array(sources[start..<min(start + 3, sources.count)])
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: 20) {
                    ForEach(row) { source in
                        BrowserInstalledImportSourceCard(
                            source: source,
                            isSelected: isSelected(source),
                            isLocked: isLocked,
                            accessLabel: accessLabel(source),
                            toggleSelection: {
                                toggleSelection(source)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// One browser as a tile: its icon and name, and what reading it takes once
/// setup knows.
private struct BrowserInstalledImportSourceCard: View {
    let source: BrowserInstalledImportSource
    let isSelected: Bool
    let isLocked: Bool
    let accessLabel: String?
    let toggleSelection: () -> Void

    var body: some View {
        OdeSelectableCard(
            isSelected: isSelected, accessibilityLabel: Text("Import from \(source.title)"), density: .compact,
            tint: OdeBrandPalette.butter, action: toggleSelection
        ) {
            VStack(spacing: 12) {
                Image(nsImage: source.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
                Text(source.title)
                    .font(OdeTypography.sans(15, weight: .semibold))
                    .foregroundStyle(OdeBrandTheme.textDisplay)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .help(source.title)
                // Two lines, so the longer notes read in full.
                Text(accessLabel ?? "")
                    .font(OdeTypography.sans(11, weight: .medium))
                    .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 28, alignment: .top)
                    .help(accessLabel ?? "")
            }
            // The shared card adds its own padding; the notes may take two lines.
            .frame(width: 180)
            .frame(minHeight: 160)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 22, height: 22)
                        .background(OdeBrandPalette.butter, in: .circle)
                        .padding(OdeSpacing.extraExtraSmall)
                        .accessibilityHidden(true)
                }
            }
        }
        .fixedSize()
        .disabled(isLocked)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(accessibilityHint)
    }

    /// What going on with this browser does: an unscanned browser's data is
    /// read then and may need access, found data is reviewed, and otherwise
    /// Ode asks for the folder.
    private var accessibilityHint: Text {
        guard source.detectedPayload != nil else {
            return Text("Ode reads its data when you continue, which may ask for access")
        }
        return source.hasDetectedData
            ? Text("Review its Spaces and tabs")
            : Text("Ode locates the browser data folder and asks for one-time read access")
    }
}
