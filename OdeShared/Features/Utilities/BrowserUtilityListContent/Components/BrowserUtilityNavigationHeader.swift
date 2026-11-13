import SwiftUI

/// Navigation stays inside the Library, above its search and files, rather than over the page.
struct BrowserUtilityNavigationHeader: View {
    // MARK: - Variables

    let surface: BrowserUtilitySurface
    let select: (BrowserUtilitySurface) -> Void
    let backToTabs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
            Button(action: backToTabs) {
                Label(String(localized: "Back to tabs"), systemImage: "chevron.backward")
                    .font(.subheadline)
                    .padding(.horizontal, OdeSpacing.small)
                    .frame(minHeight: OdeLayout.sidebarRowHeight)
            }
            .buttonStyle(OdeChromeButtonStyle(controlSize: nil))
            .accessibilityIdentifier("browser.library.back-to-tabs")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.extraSmall) {
                    sectionButtons(horizontal: true)
                }
                VStack(spacing: OdeSpacing.extraExtraSmall) {
                    sectionButtons(horizontal: false)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Library"))
        }
        .foregroundStyle(SpaceRoleStyle.text)
    }

    // MARK: - Actions - Sections

    private func sectionButtons(horizontal: Bool) -> some View {
        ForEach(BrowserUtilitySurface.all) { destination in
            Button {
                select(destination)
            } label: {
                HStack(spacing: OdeSpacing.small) {
                    if !horizontal {
                        Image(systemName: destination.systemImage)
                            .accessibilityHidden(true)
                    }
                    Text(destination.title)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, OdeSpacing.small)
                .padding(.vertical, OdeSpacing.extraSmall)
                .frame(
                    maxWidth: horizontal ? nil : .infinity,
                    minHeight: OdeLayout.sidebarRowHeight,
                    alignment: .leading
                )
            }
            .buttonStyle(BrowserUtilityNavigationButtonStyle(isSelected: surface == destination))
            .accessibilityAddTraits(surface == destination ? .isSelected : [])
            .accessibilityIdentifier(BrowserUtilityAccessibilityID.destination(destination))
        }
    }
}

#if DEBUG
    #Preview("Library navigation") {
        @Previewable @State var selected = BrowserUtilitySurface.downloads
        BrowserUtilityNavigationHeader(surface: selected, select: { selected = $0 }, backToTabs: {})
            .padding(OdeSpacing.small)
            .frame(width: 280)
    }
#endif
