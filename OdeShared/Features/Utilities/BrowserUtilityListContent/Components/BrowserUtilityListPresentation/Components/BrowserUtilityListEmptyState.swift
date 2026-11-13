import SwiftUI

struct BrowserUtilityListEmptyState: View {
    // MARK: - Variables

    let surface: BrowserUtilitySurface
    let searchText: String
    let filter: BrowserUtilityListFilter
    let dismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: OdeSpacing.small) {
            Image(systemName: presentation.systemImage)
                .font(.title2)
                .foregroundStyle(SpaceRoleStyle.accentText)
                .accessibilityHidden(true)
                .padding(.bottom, OdeSpacing.extraSmall)
            Text(presentation.title)
                .font(.headline)
                .foregroundStyle(SpaceRoleStyle.text)
            if let description = presentation.description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(SpaceRoleStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(OdeSpacing.large)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(.rect)
        .onTapGesture {
            dismiss?()
        }
    }

    private var presentation: BrowserUtilityListEmptyPresentation {
        BrowserUtilityListEmptyPresentation(
            surface: surface,
            searchText: searchText,
            filter: filter
        )
    }
}

#if DEBUG
    #Preview("Empty and no search results") {
        VStack {
            BrowserUtilityListEmptyState(surface: .history, searchText: "", filter: .all, dismiss: nil)
            BrowserUtilityListEmptyState(surface: .downloads, searchText: "report", filter: .all, dismiss: nil)
        }.frame(width: 360, height: 420)
    }
#endif
